import {test,expect} from '@playwright/test';
import {simulerSoignant,entrer,attendreAPI} from './helpers/recette-complete-soignant';

// Réponses synthétiques uniquement ; aucune suppression ni connexion distante.
for(const panne of ['erreur','malforme','delai'] as const)test(`profil ${panne} : confidentialité, annuler, réessayer et recharger`,async({page,context},info)=>{
  await context.addInitScript(()=>{
    if(!Reflect.deleteProperty(Object.getPrototypeOf(navigator),'serviceWorker')||'serviceWorker' in navigator)throw Error('Service Worker interdit en simulation');
    Object.defineProperty(window,'Stripe',{value:()=>{throw Error('Paiement hors périmètre');}});
  });
  const s=await simulerSoignant(page),externes:string[]=[],consoleErrors:string[]=[],suppressions:string[]=[];
  page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.text());});
  await page.route('**/*',route=>{
    const u=new URL(route.request().url());
    if(['localhost','127.0.0.1'].includes(u.hostname))return route.fallback();
    if(u.hostname==='fonts.googleapis.com')return route.fulfill({contentType:'text/css',body:''});
    if(u.hostname==='js.stripe.com')return route.fulfill({contentType:'application/javascript',body:'window.Stripe=()=>{throw Error("Paiement interdit")};'});
    externes.push(u.origin+u.pathname);return route.abort();
  });
  await page.route('**/functions/v1/delete-account',route=>{suppressions.push(route.request().method());return route.abort();});
  await entrer(page,'connexion');await attendreAPI(page);
  let mauvais=true,appels=0,liberer:(()=>void)|undefined;
  await page.route('**/rest/v1/rpc/fn_mon_profil_soignant_complet',async route=>{
    if(route.request().method()==='OPTIONS')return route.fulfill({status:200,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'}});
    appels++;const headers={'access-control-allow-origin':'*'};
    if(!mauvais)return route.fulfill({headers,json:s.profile});
    if(panne==='delai'){
      await new Promise<void>(resolve=>{liberer=resolve;});
      return route.fulfill({headers,json:{...s.profile,prenom:'Réponse périmée'}});
    }
    // HTTP 200 with an RPC error envelope reproduces the existing empty form
    // without adding a browser-generated network warning to the observation.
    return route.fulfill({headers,json:panne==='erreur'?{error:'Indisponible'}:{...s.profile,specialites:'{json-invalide'}});
  });
  await page.clock.install();
  try{
    await page.goto('/soignant/profil');await expect.poll(()=>appels).toBe(1);
    await page.getByRole('tab',{name:'Confidentialité',exact:true}).click();
    await expect(page.getByRole('heading',{name:'Suppression de compte',exact:true})).toBeVisible();
    await page.getByRole('button',{name:'Supprimer mon compte',exact:true}).click();
    await expect(page.getByRole('button',{name:'Supprimer définitivement',exact:true})).toBeDisabled();
    await page.getByPlaceholder('Tape SUPPRIMER',{exact:true}).fill('SUPPRIMER');
    await expect(page.getByRole('button',{name:'Supprimer définitivement',exact:true})).toBeEnabled();
    await page.getByRole('button',{name:'Annuler',exact:true}).click();
    await expect(page.getByPlaceholder('Tape SUPPRIMER',{exact:true})).toHaveCount(0);
    await page.getByRole('tab',{name:'Profil principal',exact:true}).click();
    if(panne==='delai')await page.clock.fastForward(10001);
    await expect(page.getByRole('alert')).toContainText('Ton profil n’a pas pu être chargé.');
    await expect(page.getByRole('status',{name:'Chargement en cours'})).toHaveCount(0);
    await expect(page.getByRole('button',{name:'Enregistrer les modifications',exact:true})).toHaveCount(0);
    await page.screenshot({path:info.outputPath(`${panne}-reprise.png`),scale:'css'});
    mauvais=false;await page.getByRole('button',{name:'Réessayer',exact:true}).click();
    await expect(page.getByRole('heading',{level:1,name:'Camille Recette',exact:true})).toBeVisible();
    liberer?.();await page.clock.resume();await attendreAPI(page);
    await expect(page.getByRole('heading',{level:1,name:'Camille Recette',exact:true})).toBeVisible();
    await expect(page.getByText('Réponse périmée',{exact:true})).toHaveCount(0);
    await page.reload();await expect(page.getByRole('heading',{level:1,name:'Camille Recette',exact:true})).toBeVisible();
    await attendreAPI(page);expect(appels).toBe(3);expect(suppressions).toEqual([]);expect(externes).toEqual([]);expect(consoleErrors).toEqual([]);expect(s.errors).toEqual([]);expect(s.unknown).toEqual([]);
    expect(s.calls.filter(x=>x.method!=='GET'&&(x.name==='soignants'||/supprimer|modifier_profil/.test(x.name)))).toEqual([]);
    await page.screenshot({path:info.outputPath(`${panne}-recharge.png`),scale:'css'});
  }finally{liberer?.();await info.attach('preuve',{body:JSON.stringify({panne,appels,suppressions,externes,consoleErrors,pageErrors:s.errors,inconnues:s.unknown}),contentType:'application/json'});}
});

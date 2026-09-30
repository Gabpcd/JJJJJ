import {test,expect} from '@playwright/test';
import {simulerSoignant,entrer as entrerSoignant,aller,attendreAPI} from './helpers/recette-complete-soignant';
import {simulerEtablissement,entrer as entrerEtablissement,allerA,stabiliserLectures} from './helpers/recette-complete-etablissement';

// La conservation réelle des notes est prouvée par notation-anonymisation-compte.test.sql.
// Ici seules les interfaces et leurs réponses Edge sont simulées, sans compte distant.
for(const famille of ['soignant','etablissement'] as const) {
  test(`${famille} : annuler, refuser puis supprimer et rester déconnecté après reload`,async({context,page},info)=>{
    const soignant=famille==='soignant';
    await context.addInitScript(()=>{
      if(!Reflect.deleteProperty(Object.getPrototypeOf(navigator),'serviceWorker') || 'serviceWorker' in navigator)
        throw new Error('La simulation exige un navigateur sans Service Worker.');
    });
    await context.routeWebSocket('**/*',socket=>socket.close());
    const s=soignant?await simulerSoignant(page):undefined;
    const e=soignant?undefined:(await simulerEtablissement(page)).etat;
    (s?.overrides??e!.overrides).set('fn_missions_publiques_recherche',[]);
    const erreurs:string[]=[];const avertissements:string[]=[];const externes:string[]=[];
    page.on('console',m=>{if(m.type()==='error')erreurs.push(m.text());if(m.type()==='warning')avertissements.push(m.text());});
    await page.route('**/*',route=>{
      const u=new URL(route.request().url());
      if(['127.0.0.1','localhost'].includes(u.hostname)||u.protocol==='blob:')return route.fallback();
      if(u.hostname==='fonts.googleapis.com')return route.fulfill({contentType:'text/css',body:''});
      if(u.hostname==='js.stripe.com')return route.fulfill({contentType:'application/javascript',body:'window.Stripe=function(){return {};};'});
      externes.push(u.origin+u.pathname);return route.abort();
    });
    const appels:unknown[]=[];let autorise=false;let erreurTechnique=false;let terminee=false;let terminer:(()=>void)|undefined;
    const refus='Suppression impossible pour le moment. Réessayez.';
    await page.route('**/functions/v1/delete-account',async route=>{
      const headers={'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'POST,OPTIONS'};
      if(route.request().method()==='OPTIONS')return route.fulfill({headers,status:200,body:''});
      expect(route.request().method()).toBe('POST');appels.push(route.request().postDataJSON());
      if(erreurTechnique)return route.fulfill({headers,status:503,json:{message:'Failed to fetch'}});
      if(!autorise)return route.fulfill({headers,json:{success:false,error:refus}});
      await new Promise<void>(resolve=>{terminer=resolve;});
      expect(terminee).toBe(false);terminee=true;
      return route.fulfill({headers,json:{success:true}});
    });
    const champ=page.getByPlaceholder(soignant?'Tape SUPPRIMER':'SUPPRIMER',{exact:true});
    const confirmation=()=>page.getByRole('button',{name:soignant?'Supprimer définitivement':'Confirmer la suppression',exact:true});
    const calme=()=>soignant?attendreAPI(page):stabiliserLectures(page);
    try {
      await (soignant?entrerSoignant(page,'connexion'):entrerEtablissement(page,'connexion'));
      await (soignant?aller(page,'/soignant/mon-compte'):allerA(page,'/etablissement/mon-compte'));
      await page.getByRole('button',{name:'Supprimer mon compte',exact:true}).click();
      await expect(page).toHaveURL(soignant?/profil\?tab=confidentialite#suppression-compte$/:/parametres\?tab=securite#suppression-compte$/);
      await page.getByRole('button',{name:'Supprimer mon compte',exact:true}).click();
      await expect(confirmation()).toBeDisabled();
      await champ.fill('SUPPRIMER');await page.getByRole('button',{name:'Annuler',exact:true}).click();
      expect(appels).toEqual([]);
      await page.getByRole('button',{name:'Supprimer mon compte',exact:true}).click();
      await expect(champ).toHaveValue('');await champ.fill('SUPPRIMER');await confirmation().click();
      await expect(page.getByRole('alert')).toContainText(refus);
      await expect(champ).toHaveValue('SUPPRIMER');await expect(confirmation()).toBeEnabled();
      await page.screenshot({path:info.outputPath('refus.png'),fullPage:true});
      expect(appels).toEqual([{}]);erreurTechnique=true;await confirmation().click();
      await expect(page.getByRole('alert')).toContainText('Une erreur est survenue. Veuillez réessayer.');
      await expect(page.getByRole('alert')).not.toContainText(/Failed to fetch|non-2xx|status code/i);
      await expect(champ).toHaveValue('SUPPRIMER');await expect(confirmation()).toBeEnabled();
      await page.screenshot({path:info.outputPath('refus-technique.png'),fullPage:true});
      expect(appels).toEqual([{},{}]);erreurTechnique=false;autorise=true;await confirmation().click();
      await expect(page.getByRole('button',{name:'Suppression…',exact:true})).toBeDisabled();
      await expect(page.getByRole('button',{name:'Annuler',exact:true})).toBeDisabled();
      await expect(champ).toBeDisabled();
      await expect.poll(()=>appels.length,{message:'Réessai reçu par le transport simulé'}).toBe(3);
      expect(appels).toEqual([{},{},{}]);expect(terminer).toBeDefined();terminer!();
      await expect(page).toHaveURL(/\/$/);expect(terminee).toBe(true);
      await calme();await page.reload();await expect(page).toHaveURL(/\/$/);
      await (soignant?aller(page,'/soignant/mes-documents'):allerA(page,'/etablissement/mon-compte'));
      await expect(page).toHaveURL(/\/connexion/);
      await expect(page.getByRole('button',{name:'Se connecter',exact:true})).toBeVisible();
      await calme();await page.reload();await expect(page).toHaveURL(/\/connexion/);
      await expect(page.getByRole('button',{name:'Se connecter',exact:true})).toBeVisible();
      await page.screenshot({path:info.outputPath('deconnexion-rechargee.png'),fullPage:true});
      expect(appels).toEqual([{},{},{}]);expect(externes).toEqual([]);
      expect(s?.unknown??e!.inconnues).toEqual([]);expect(s?.errors??e!.erreurs).toEqual([]);
      // Le navigateur annonce exactement la réponse 503 volontaire. Toutes
      // les erreurs restent enregistrées ; aucune autre erreur n'est admise.
      expect(erreurs).toHaveLength(1);
      expect(erreurs[0]).toMatch(/^Failed to load resource: the server responded with a status of 503 \(/);
      expect(avertissements).toEqual([]);
    } finally {
      await info.attach('preuve-isolee',{body:JSON.stringify({famille,appels,terminee,externes,erreurs,avertissements,inconnues:s?.unknown??e?.inconnues,pageErrors:s?.errors??e?.erreurs}),contentType:'application/json'});
    }
  });
}

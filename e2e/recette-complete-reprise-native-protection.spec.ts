import {test,expect, type Page} from '@playwright/test';
import {simulerBridgeNatif} from './helpers/native-bridge-simule';
import {communicationsSimulees,conversationId} from './helpers/recette-complete-communications';
import {simulerEtablissement,entrer,etablissement} from './helpers/recette-complete-etablissement';
async function reprendre(page: Page){
 const now=await page.evaluate(()=>Date.now());
 await page.evaluate(()=>(window as any).__native.emit('App','appStateChange',{isActive:false}));
 await page.clock.setFixedTime(now+31*60000);
 await page.evaluate(()=>(window as any).__native.emit('App','appStateChange',{isActive:true}));
 await page.waitForTimeout(1000);
}
test('le brouillon de messagerie survit à 31 minutes',async({context,page},info)=>{
 await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
 await communicationsSimulees(context,'SOIGNANT');
 await page.addInitScript(()=>{const raw=sessionStorage.getItem('sb-127-auth-token');if(raw)localStorage.setItem('sb-127-auth-token',raw);});
 await page.route('**/rest/v1/rpc/fn_upsert_token_push',r=>r.fulfill({json:null}));
 await page.goto(`/soignant/messagerie?conv=${conversationId}`);
 const input=page.getByRole('textbox',{name:'Saisir un message',exact:true});
 await input.fill('Brouillon fictif à conserver lors du retour');
 await expect(input).toHaveValue('Brouillon fictif à conserver lors du retour');
 await info.attach('avant',{body:await page.locator('main').ariaSnapshot(),contentType:'text/plain'});
 await reprendre(page);
 await info.attach('apres',{body:await page.locator('main').ariaSnapshot(),contentType:'text/plain'});
 await expect(page).toHaveURL(new RegExp(`/soignant/messagerie\\?conv=${conversationId}`));
 await expect(input).toHaveValue('Brouillon fictif à conserver lors du retour');
});
test('la signature activation etablissement survit à 31 minutes',async({page},info)=>{
 await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
 const {etat}=await simulerEtablissement(page);
 await page.route('**/rest/v1/rpc/fn_upsert_token_push',r=>r.fulfill({json:null}));
 await entrer(page,'connexion');
 etat.overrides.set('etablissements',{...etablissement,contrat_service_signe:false});
 await page.goto('/etablissement/activer');
 const accord=page.getByRole('checkbox').nth(0);
 await expect(accord).toBeVisible();
 await page.locator('div').evaluateAll(els=>{const el=els.find(e=>e.classList.contains('max-h-[50vh]'));if(el){el.scrollTop=el.scrollHeight;el.dispatchEvent(new Event('scroll',{bubbles:true}));}});
 await accord.check();await page.getByRole('checkbox').nth(1).check();
 const canvas=page.locator('canvas');await canvas.scrollIntoViewIfNeeded();
 const box=(await canvas.boundingBox())!;
 for(let i=0;i<2;i++){await page.mouse.move(box.x+20,box.y+20+i*25);await page.mouse.down();await page.mouse.move(box.x+150,box.y+50+i*25,{steps:12});await page.mouse.up();}
 await expect(page.getByRole('button',{name:'Valider la signature',exact:true})).toBeEnabled();
 await info.attach('avant',{body:await page.locator('main').ariaSnapshot(),contentType:'text/plain'});
 await reprendre(page);
 await info.attach('apres',{body:await page.locator('main').ariaSnapshot(),contentType:'text/plain'});
 await expect(page).toHaveURL(/\/etablissement\/activer$/);
 await expect(page.getByRole('button',{name:'Valider la signature',exact:true})).toBeEnabled();
});
test('le lien de démarrage reste prioritaire pendant une restauration lente de compte incomplet',async({page},info)=>{
 await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
 const {etat}=await simulerEtablissement(page,'minimal');
 await page.route('**/rest/v1/rpc/fn_upsert_token_push',r=>r.fulfill({json:null}));
 await entrer(page,'connexion');
 await page.route('**/rest/v1/rpc/fn_get_my_role',async route=>{await new Promise(r=>setTimeout(r,6000));await route.fallback();});
 await page.route('**/rest/v1/parcours_inscription*',async route=>{await new Promise(r=>setTimeout(r,6000));await route.fallback();});
 await page.addInitScript(()=>{
  const bridge=(window as any).Capacitor;
  const original=bridge.nativePromise;
  bridge.nativePromise=async(plugin:string,method:string,args:any)=>plugin==='App'&&method==='getLaunchUrl'?{url:'https://jolene.app/etablissement/messagerie'}:original(plugin,method,args);
  localStorage.setItem('jolene.native.background.79000000-0000-4000-8000-000000000071',String(Date.now()-86400000));
 });
 const history:string[]=[];page.on('framenavigated',frame=>{if(frame===page.mainFrame())history.push(`${Date.now()} ${frame.url()}`);});
 await page.goto('/');
 await expect(page).toHaveURL(/\/etablissement\/messagerie$/);
 await info.attach('avant-demarrage',{body:JSON.stringify({url:page.url(),history}),contentType:'application/json'});
 await page.waitForTimeout(16000);
 await info.attach('chronologie',{body:JSON.stringify(history),contentType:'application/json'});
 await info.attach('apres-demarrage',{body:await page.locator('body').ariaSnapshot(),contentType:'text/plain'});
 await expect(page).toHaveURL(/\/etablissement\/messagerie$/);
});
test('le dialogue de duplication reste ouvert après une absence longue',async({page},info)=>{
 await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios');
 const {etat}=await simulerEtablissement(page);etat.donnees=true;
 await page.route('**/rest/v1/rpc/fn_upsert_token_push',r=>r.fulfill({json:null}));
 await entrer(page,'connexion');
 await page.goto('/etablissement/missions');
 await page.getByRole('button',{name:/Dupliquer/}).click();
 const dialog=page.getByRole('dialog',{name:'Préremplir une nouvelle mission ?'});
 await expect(dialog).toBeVisible();
 expect(await dialog.getAttribute('data-state')).toBeNull();
 await info.attach('avant',{body:await dialog.ariaSnapshot(),contentType:'text/plain'});
 await reprendre(page);
 await info.attach('apres',{body:await page.locator('body').ariaSnapshot(),contentType:'text/plain'});
 await expect(dialog).toBeVisible();
 await expect(page).toHaveURL(/\/etablissement\/missions$/);
});
import {simulerSoignant,entrer as entrerSoignant} from './helpers/recette-complete-soignant';
for (const role of ['soignant', 'etablissement'] as const) {
test(`panne store puis réessai et fermeture de l’avis (${role})`,async({page},info)=>{
 await simulerBridgeNatif(page, info.project.name === 'android' ? 'android' : 'ios',-1);
 if (role === 'soignant') await simulerSoignant(page); else await simulerEtablissement(page);
 await page.route('**/rest/v1/rpc/fn_upsert_token_push',r=>r.fulfill({json:null}));
 if (role === 'soignant') await entrerSoignant(page,'connexion'); else await entrer(page,'connexion');
 await page.goto(`/${role}/mon-compte`);
 const banner=page.getByRole('complementary',{name:'Mise à jour de Jolene'});
 await expect(banner).toBeHidden();
 await page.getByRole('button',{name:'Vérifier les mises à jour',exact:true}).click();
 await expect(page.getByText('Impossible de vérifier les mises à jour. Vérifiez votre connexion puis réessayez.',{exact:true})).toBeVisible();
 await expect(page.getByRole('status').filter({hasText:'Impossible de vérifier les mises à jour.'})).toBeVisible();
 await expect(page.locator('[data-sonner-toast]').filter({hasText:'Impossible de vérifier les mises à jour.'})).toHaveCount(0);
 await info.attach('erreur-store',{body:await page.locator('main').ariaSnapshot(),contentType:'text/plain'});
 await page.screenshot({path:info.outputPath('erreur-store.png'),fullPage:true});
 await expect(page.getByText('Jolene est à jour sur cet appareil.',{exact:true})).toBeHidden();
 await page.evaluate(()=>(window as any).__native.update=2);
 await page.getByRole('button',{name:'Vérifier les mises à jour',exact:true}).click();
 await expect(banner).toBeVisible();
 await banner.getByRole('button',{name:'Me le rappeler plus tard'}).click();await expect(banner).toBeHidden();
 await page.getByRole('button',{name:'Vérifier les mises à jour',exact:true}).click();await expect(banner).toBeVisible();
 await info.attach('apres-reessai',{body:await banner.ariaSnapshot(),contentType:'text/plain'});
});
}

// Frontend simulation only: no real backend, provider, upload or qualification.
// Scheduled by the existing five-format recette-complete CI matrix.
// Metadata/profile/document responses are synthetic; no upload or provider call.
import { test, expect, type Page } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { simulerSoignant, aller, recharger, attendreAPI, preuve, sansDebordement } from './helpers/recette-complete-soignant';

const rules = JSON.parse(readFileSync(new URL('./ide-reference-rules.fixture.json', import.meta.url), 'utf8'));
const labels = {
 CARTE_IDENTITE: "Pièce d'identité", DIPLOME: "Diplôme d'État", RPPS_ADELI: 'Attestation RPPS / ADELI',
 RIB: 'RIB', RCP_ASSURANCE: 'Assurance RCP', ATTESTATION_URSSAF: 'Attestation URSSAF',
 AUTORISATION_EXERCICE: "Autorisation d'exercice",
} as const;
type Kind = keyof typeof labels;
const cases: { name: string; exercise: string; rpps: boolean; adeli: boolean; visible: Kind[] }[] = [
 { name:'liberal-sans-registre', exercise:'LIBERAL', rpps:false, adeli:false, visible:['CARTE_IDENTITE','DIPLOME','RPPS_ADELI','RIB','RCP_ASSURANCE','ATTESTATION_URSSAF','AUTORISATION_EXERCICE'] },
 { name:'mixte-sans-registre', exercise:'MIXTE', rpps:false, adeli:false, visible:['CARTE_IDENTITE','DIPLOME','RPPS_ADELI','RIB','RCP_ASSURANCE','ATTESTATION_URSSAF','AUTORISATION_EXERCICE'] },
 { name:'salarie-sans-registre', exercise:'SALARIE', rpps:false, adeli:false, visible:['CARTE_IDENTITE','DIPLOME','RPPS_ADELI','RIB','AUTORISATION_EXERCICE'] },
 { name:'liberal-rpps', exercise:'LIBERAL', rpps:true, adeli:false, visible:['CARTE_IDENTITE','RIB','RCP_ASSURANCE','ATTESTATION_URSSAF'] },
 { name:'salarie-rpps', exercise:'SALARIE', rpps:true, adeli:false, visible:['CARTE_IDENTITE','RIB'] },
 { name:'liberal-adeli-seul', exercise:'LIBERAL', rpps:false, adeli:true, visible:['CARTE_IDENTITE','DIPLOME','RIB','RCP_ASSURANCE','ATTESTATION_URSSAF'] },
 { name:'salarie-adeli-seul', exercise:'SALARIE', rpps:false, adeli:true, visible:['CARTE_IDENTITE','DIPLOME','RIB'] },
];
const runs = new WeakMap<Page, { state: Awaited<ReturnType<typeof simulerSoignant>>; forbidden: string[]; blockedExternal: string[] }>();
test.use({ actionTimeout: 15_000 });
test.setTimeout(180_000);

async function assertViewport(page: Page) {
 const expected=test.info().project.use.viewport;
 expect(['iphone','android','ipad-portrait','ipad-paysage','ordinateur']).toContain(test.info().project.name);
 expect(expected,'Un viewport explicite est requis pour revendiquer le format').toBeTruthy();
 await expect.poll(()=>page.evaluate(()=>({width:innerWidth,height:innerHeight})), {
  message:'Le viewport du DOM correspond réellement au projet simulé',
 }).toEqual(expected);
}

async function setup(page: Page) {
 const origin=new URL(test.info().project.use.baseURL!);
 expect(['http:','https:']).toContain(origin.protocol);
 expect(['localhost','127.0.0.1','[::1]']).toContain(origin.hostname);
 const state = await simulerSoignant(page);
 const actorId = randomUUID(), email = `fictif-ide-metadata-${actorId}@example.invalid`;
 Object.assign(state.profile, { id:actorId, email, prenom:'Fictif', nom:'Metadata IDE', profession:'IDE',
  type_exercice:'LIBERAL', est_compte_test:true, rpps_verifie:false, adeli_verifie:false,
  numero_rpps:null, numero_adeli:null, tous_documents_valides:false, identite_verifiee:false, diplome_verifie:false });
 const user = { id:actorId, email, aud:'authenticated', role:'authenticated', email_confirmed_at:new Date().toISOString(),
  app_metadata:{ est_compte_test:true }, user_metadata:{}, identities:[] };
 state.overrides.set('user', user);
 state.overrides.set('token', { user, token_type:'bearer', access_token:'fixture-auth', refresh_token:'fixture-refresh',
  expires_in:3600, expires_at:Math.floor(Date.now()/1000)+3600 });
 state.tables.set('documents_requis_par_profession', rules.map((row: Record<string,unknown>) => ({ ...row, id:randomUUID() })));
 state.tables.set('documents_soignants', []);
 const forbidden: string[] = [], blockedExternal: string[] = [];
 runs.set(page, { state, forbidden, blockedExternal });
 // Runs before the helper route: all external HTTP is aborted; no storage,
 // document write, verification or account mutation is permitted even locally.
 await page.route('**/*', async route => {
  const request=route.request(), url=new URL(request.url());
  if(!['http:','https:'].includes(url.protocol))return route.fallback();
  if(url.origin!==origin.origin) {
   blockedExternal.push(url.hostname+url.pathname);
   if(/\/(?:auth|rest|functions|storage)\/v1\//.test(url.pathname)||!['GET','HEAD','OPTIONS'].includes(request.method())) {
    forbidden.push('OUTSIDE_SIMULATOR '+request.method()+' '+url.pathname);
   }
   return route.abort();
  }
  const forbiddenFunction=url.pathname.startsWith('/functions/v1/')&&!url.pathname.endsWith('/stripe-connect-status');
  const forbiddenRpc=/\/rest\/v1\/rpc\/fn_(?:remplacer_document_soignant|admin_ajouter_document_soignant|demander_revue_document|signer_attestation_sante|modifier_mon_profil|enregistrer_parcours_inscription)$/.test(url.pathname);
  const forbiddenTableWrite=url.pathname.startsWith('/rest/v1/')&&!url.pathname.startsWith('/rest/v1/rpc/')&&!['GET','HEAD','OPTIONS'].includes(request.method());
  if(url.pathname.startsWith('/storage/v1/')||forbiddenFunction||forbiddenRpc||forbiddenTableWrite) {
   forbidden.push(request.method()+' '+url.pathname);return route.abort();
  }
  return route.fallback();
 });
 await aller(page,'/connexion');
 await page.getByLabel('Email',{exact:true}).fill(email);
 await page.getByLabel('Mot de passe',{exact:true}).fill('Mot!Solide-FICTIF-2026');
 await page.getByRole('button',{name:'Se connecter',exact:true}).click();
 await expect(page).toHaveURL(/\/soignant\/(tableau-de-bord|recherche-missions)$/);
 await expect(page.locator('#app-route-content')).toBeVisible();
 await expect(page.locator('main').getByRole('heading',{level:1})).toContainText(/Explorer|Bonjour|Bonsoir/);
 if(new URL(page.url()).pathname==='/soignant/recherche-missions') {
  await expect(page.getByRole('heading',{name:'Aucune nouvelle mission à parcourir',exact:true})).toBeVisible();
 }
 await attendreAPI(page);
 await page.waitForLoadState('networkidle');
 await aller(page,'/soignant/mes-documents?tab=justificatifs');
 await expect(page.getByRole('heading',{name:'Mes documents',exact:true})).toBeVisible();
 await assertViewport(page);
 return state;
}

async function assertCards(page: Page, visible: Kind[]) {
 await expect(page.getByRole('tab',{name:'Justificatifs',exact:true})).toHaveAttribute('aria-selected','true');
 for(const [kind,label] of Object.entries(labels)) {
  await expect(page.locator('main').getByRole('heading',{level:3,name:label,exact:true})).toHaveCount(visible.includes(kind as Kind)?1:0);
 }
 await expect(page.locator('main')).not.toContainText(/Tous tes documents obligatoires sont à jour|Vérifié ✅/);
 await sansDebordement(page);
 await assertViewport(page);
}

test.afterEach(async({page},info)=>{
 const run=runs.get(page);if(!run)return;
 await info.attach('ide-reference-metadata-only',{body:JSON.stringify({ mode:'FRONTEND_SIMULATED_METADATA_ONLY',
  realBackend:false, realProvider:false, physicalCamera:false,
  project:info.project.name, expectedViewport:info.project.use.viewport,
  actualViewport:page.isClosed()?null:await page.evaluate(()=>({width:innerWidth,height:innerHeight})),
  forbiddenRequests:run.forbidden,
  blockedExternalRequests:run.blockedExternal, apiCalls:run.state.calls },null,2),contentType:'application/json'});
 expect(run.forbidden,'Aucune tentative upload, vérification ou écriture documentaire').toEqual([]);
 expect(run.state.unknown,'Aucun endpoint implicitement simulé').toEqual([]);
 expect(run.state.errors,'Aucune exception JavaScript').toEqual([]);
});

test('IDE — sept règles de référence, conditions exercice/RPPS/ADELI et reload',async({page},info)=>{
 const state=await setup(page);
 for(const c of cases)await test.step(c.name,async()=>{
  Object.assign(state.profile,{type_exercice:c.exercise,rpps_verifie:c.rpps,adeli_verifie:c.adeli});
  await recharger(page);
  await assertCards(page,c.visible);
  await preuve(page,`ide-regles-${c.name}`,info,true);
 });
});

test('IDE — onglets, modales CNI/diplôme et annulation sans upload',async({page},info)=>{
 await setup(page);await assertCards(page,cases[0].visible);
 for(const kind of ['CARTE_IDENTITE','DIPLOME'] as const) {
  const card=page.locator('main .card-base').filter({has:page.getByRole('heading',{level:3,name:labels[kind],exact:true})});
  await card.getByRole('button',{name:'+ Téléverser',exact:true}).click();
  const dialog=page.getByRole('dialog',{name:'📤 Téléverser',exact:true});
  await expect(dialog).toBeVisible();await expect(dialog).toContainText(labels[kind]);
  await expect(dialog.getByRole('button',{name:'Téléverser',exact:true})).toBeDisabled();
  await expect(dialog.getByRole('button',{name:'Choisir un document à téléverser',exact:true})).toBeVisible();
  if(info.project.name!=='ordinateur')await expect(dialog.getByRole('button',{name:'Prendre une photo',exact:true})).toBeVisible();
  await sansDebordement(page);
  await assertViewport(page);
  await preuve(page,`ide-modale-${kind}`,info,true);
  await dialog.getByRole('button',{name:'Annuler',exact:true}).click();
  await expect(dialog).toHaveCount(0);
 }
 for(const tab of ['Contrats','DPAE','Justificatifs']) {
  await page.getByRole('tab',{name:tab,exact:true}).click();
  await expect(page.getByRole('tab',{name:tab,exact:true})).toHaveAttribute('aria-selected','true');
  await expect(page.getByRole('tabpanel')).toBeVisible();
 }
 await recharger(page);await assertCards(page,cases[0].visible);
});

test('IDE — metadata indisponible, message de refus puis reprise explicite',async({page},info)=>{
 const state=await setup(page);
 state.failures.add('documents_requis_par_profession');await recharger(page);
 await expect(page.locator('main')).toContainText('Vos documents sont temporairement indisponibles');
 await expect(page.locator('main')).not.toContainText(/Tous tes documents obligatoires sont à jour|Aucun document obligatoire/);
 await expect(page.locator('main').getByRole('heading',{level:3,name:labels.CARTE_IDENTITE,exact:true})).toHaveCount(0);
 await assertViewport(page);
 await preuve(page,'ide-metadata-indisponible',info,true);
 state.failures.delete('documents_requis_par_profession');
 await page.getByRole('button',{name:'Réessayer',exact:true}).click();
 await assertCards(page,cases[0].visible);await recharger(page);await assertCards(page,cases[0].visible);
});

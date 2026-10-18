import { test, expect, type Page, type Request } from '@playwright/test';
import { creerMissionSimulee, ids, preuveMission } from './helpers/recette-complete-mission';

function attendreLectures(page: Page) {
 const pending = new Set<Request>();
 let last = Date.now();
 page.on('request', request => {
  if (/\/(auth|rest|functions|storage)\/v1\//.test(request.url())) {
   pending.add(request);last = Date.now();
  }
 });
 const finished = (request: Request) => {if (pending.delete(request)) last = Date.now();};
 page.on('requestfinished',finished);page.on('requestfailed',finished);
 return () => expect.poll(() => pending.size === 0 && Date.now()-last >= 500,
  {message:'Attendre les lectures déclenchées par la clôture avant de recharger'}).toBe(true);
}

// Frontend à réponses simulées uniquement, à exécuter sur les cinq formats
// usuels. Ni worker, Storage, paiement ni email réels dans ce témoin.
for (const role of ['ADMIN_ETABLISSEMENT','SOIGNANT'] as const) {
 test(`honoraires ${role} : absence de pièce prématurée puis finale émise et PDF après recharge`,async({context,page},info)=>{
  const stabiliser=attendreLectures(page);
  const simulation=creerMissionSimulee(),{state}=simulation;
  Object.assign(state.mission,{statut:role==='ADMIN_ETABLISSEMENT'?'EN_COURS':'TERMINEE',
   type_contrat_applique:'LIBERAL',soignant_assigne_id:ids.soignant,strategie_facturation:'FINALE_UNIQUE'});
  const segment={id:'71000000-0000-4000-8000-000000000021',mission_id:ids.mission,
   debut:state.mission.debut_le,fin:state.mission.fin_le,ordre:1,type_creneau:'EFFECTIF',est_pause:false};
  state.creneaux.push(segment);state.segments.push(segment);
  state.presence={id:ids.presence,mission_id:ids.mission,soignant_id:ids.soignant,
   pointage_arrivee_le:segment.debut,pointage_depart_le:segment.fin,valide_par_etablissement:true};
  state.mission.presences=[state.presence];
  await simulation.installer(context,role);
  await context.route('https://fonts.googleapis.com/**',r=>r.fulfill({contentType:'text/css',body:''}));
  await context.route('https://js.stripe.com/**',r=>r.fulfill({contentType:'application/javascript',body:'window.Stripe=()=>{throw Error("Provider interdit")};'}));
  await context.route('**/rest/v1/rpc/fn_score_etab_public',r=>r.fulfill({json:{score_qualite:null,niveau:null}}));
  await context.route('**/rest/v1/rpc/fn_user_id_pour_etablissement',r=>r.fulfill({json:ids.etablissement}));
  let storageReads=0,signatures=0;
  await context.route('**/storage/v1/object/sign/jolene-documents/invoices/recette-finale.pdf*',async route=>{
   const req=route.request(),url=new URL(req.url());
   expect(['127.0.0.1','localhost']).toContain(url.hostname);
   if(req.method()==='POST'){
    expect(url.search).toBe('');expect(req.postDataJSON()).toEqual({expiresIn:300});signatures++;
    return route.fulfill({json:{signedURL:'/object/sign/jolene-documents/invoices/recette-finale.pdf?token=simulation'}});
   }
   expect(req.method()).toBe('GET');expect(url.search).toBe('?token=simulation');storageReads++;
   return route.fulfill({contentType:'application/pdf',body:'%PDF-1.4\n%Document fictif de simulation du téléchargement\n%%EOF'});
  });
  await page.clock.setFixedTime(new Date('2026-09-24T15:30:00Z'));
  const path=role==='SOIGNANT'?`/soignant/missions/${ids.mission}`:`/etablissement/missions/${ids.mission}`;
  await page.goto(path);await expect(page.getByRole('heading',{name:state.mission.intitule,exact:true})).toBeVisible();
  if(role==='ADMIN_ETABLISSEMENT'){
   await page.getByRole('button',{name:'Terminer la mission',exact:true}).click();
   await page.getByRole('dialog').getByRole('button',{name:'Terminer la mission',exact:true}).click();
   await expect.poll(()=>state.mission.statut).toBe('TERMINEE');
   await expect(page.getByRole('heading',{name:'Mission terminée 🎉',exact:true})).toBeVisible();
   await page.getByRole('button',{name:'Fermer',exact:true}).click();
  }
  await expect(page.getByRole('button',{name:/Télécharger le PDF FH-RECETTE-FINALE/})).toHaveCount(0);
  await stabiliser();
  await page.reload();await expect(page.getByRole('heading',{name:state.mission.intitule,exact:true})).toBeVisible();
  if(role==='ADMIN_ETABLISSEMENT'){
   await expect(page.getByRole('heading',{name:'Mission terminée 🎉',exact:true})).toBeVisible();
   await page.getByRole('button',{name:'Fermer',exact:true}).click();
   await expect(page.getByRole('heading',{name:'Mission terminée 🎉',exact:true})).toHaveCount(0);
  }
  await expect(page.getByText('FH-RECETTE-FINALE',{exact:true})).toHaveCount(0);
  await stabiliser();
  await preuveMission(page,info,'01-cloture-sans-piece-prematuree');
  state.facture={id:'71000000-0000-4000-8000-000000000040',mission_id:ids.mission,soignant_id:ids.soignant,etablissement_id:ids.etablissement,
   numero_facture:'FH-RECETTE-FINALE',statut:'EMISE',type_document:'FACTURE',nature_correction:'ORIGINALE',
   template_version:'v2_facturx',regime_tva_snapshot:'EXONERE_ART_261_4_1',montant_ht:640,montant_ttc:640,montant_tva:0,montant_signe:640,
   taux_tva:0,exoneration_tva:true,date_emission:'2026-09-24',date_echeance:'2026-10-24',cree_le:'2026-09-24T15:31:00Z',
   periode_debut:'2026-09-24',periode_fin:'2026-09-24',est_facture_finale_mission:true,pdf_s3_key:'invoices/recette-finale.pdf',facturx_xml_url:'invoices/recette-finale.xml'};
  await page.reload();await expect(page.getByText('FH-RECETTE-FINALE',{exact:true})).toBeVisible();
  if(role==='ADMIN_ETABLISSEMENT'){
   await expect(page.getByRole('heading',{name:'Mission terminée 🎉',exact:true})).toBeVisible();
   await page.getByRole('button',{name:'Fermer',exact:true}).click();
   await expect(page.getByRole('heading',{name:'Mission terminée 🎉',exact:true})).toHaveCount(0);
  }
  await expect(page.getByText('Facture finale',{exact:true})).toBeVisible();
  await expect(page.getByText('Format historique',{exact:true})).toHaveCount(0);
  const downloadPromise=page.waitForEvent('download');
  await page.getByRole('button',{name:'Télécharger le PDF FH-RECETTE-FINALE',exact:true}).click();
  const download=await downloadPromise;expect(download.suggestedFilename()).toBe('FH-RECETTE-FINALE.pdf');
  expect(signatures).toBe(1);expect(storageReads).toBe(1);
  await stabiliser();
  await preuveMission(page,info,'02-piece-emise-pdf-disponible');
  expect(state.calls.filter(c=>/generate-invoice|fn_generer_facture|fn_prendre_demandes/.test(c.name))).toEqual([]);
  expect(state.calls.filter(c=>c.name==='fn_terminer_mission')).toHaveLength(role==='ADMIN_ETABLISSEMENT'?1:0);
  expect(state.errors).toEqual([]);expect(state.unknown).toEqual([]);expect(state.external).toEqual([]);
 });
}

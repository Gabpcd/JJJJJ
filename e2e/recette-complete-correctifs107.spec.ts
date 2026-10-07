import { test, expect, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { creerActionsNationales, stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { ids, now, preuveMission, type RoleRecette } from './helpers/recette-complete-mission';
import { simulerSoignant, entrer as entrerSoignant, aller, recharger, ids as idsSoignant } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures, ids as idsEtab, etablissement } from './helpers/recette-complete-etablissement';

// Compatibilité du frontend livré avec les réponses du banc PG17 de CE commit.
// Transport UI simulé : aucune prétention de paiement, SMS ou backend distant.
function receipt(name:string,file:string) {
  const data=JSON.parse(readFileSync(path.resolve(process.env.CORRECTIFS107_RECEIPTS || 'preuves-ui',name,file),'utf8'));
  expect(data.sourceSha).toBe(process.env.GITHUB_SHA);
  return data;
}
async function fermerReseau(page:Page) {
  const interdits:string[]=[],erreurs:string[]=[];
  page.on('console',m=>{if(m.type()==='error')erreurs.push(m.text());});
  await page.clock.setFixedTime(new Date(now));
  await page.route('**/*',async route=>{
    const r=route.request(),u=new URL(r.url());
    // Le module facturation charge Stripe.js dès son import. Ce double local
    // suffit pour consulter les factures ; aucune API Stripe n'est appelée.
    if(u.hostname==='js.stripe.com' && r.method()==='GET' && r.resourceType()==='script') {
      return route.fulfill({contentType:'application/javascript',body:'window.Stripe = function(){ return {}; };'});
    }
    if(!['127.0.0.1','localhost'].includes(u.hostname)||/^\/(functions|storage)\//.test(u.pathname)) {
      interdits.push(`${r.method()} ${u.origin}${u.pathname}`);return route.abort();
    }
    if(r.isNavigationRequest()&&r.resourceType()==='document') {
      const response=await route.fetch();return route.fulfill({response,body:(await response.text())
        .replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi,'')
        .replace(/<link\b(?=[^>]*\bhref=["']https:\/\/fonts\.googleapis\.com\/)[^>]*>/gi,'')});
    }
    return route.fallback();
  });
  return ()=>{expect(interdits).toEqual([]);expect(erreurs).toEqual([]);};
}
for(const role of ['SOIGNANT','ADMIN_ETABLISSEMENT'] as RoleRecette[]) {
 test(`SIG107 ${role} : un écran périmé ne renvoie pas de code après signature ; reprise après reload`,async({browser},info)=>{
  const partie=role==='SOIGNANT'?'soignant':'etablissement';
  const proof=receipt('signature-'+partie,'signature-race.json');
  expect(proof.completed).toBe(true);expect(proof.signedProofPreserved).toBe(true);
  expect(proof.afterResendCommit).toEqual(proof.afterSignatureBeforeCommit);
  const context=await browser.newContext({...info.project.use});
  const {state,installer,control}=creerActionsNationales();
  state.contratCree=true;state.mission.statut='ASSIGNEE';state.mission.soignant_assigne_id=ids.soignant;
  await installer(context,role);
  const page=await context.newPage();const verifier=await fermerReseau(page);
  try {
    await page.goto(`/contrat/${ids.contrat}`);
    await expect(page.getByRole('heading',{name:'Document fictif de recette',exact:true})).toBeVisible();
    await page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
    // Une autre session a terminé la signature pendant que cet écran restait ouvert.
    Object.assign(state.contrat,{statut:proof.afterResendCommit.contractStatus,
      ['signature_'+partie]:true,['signature_'+partie+'_le']:proof.afterResendCommit.proofSignedAt});
    state.signatures.push({id:'preuve-concurrence-synthetique',contrat_id:ids.contrat,
      signataire_user_id:partie==='soignant'?ids.soignant:ids.etablissement,signataire_role:partie,
      signe_a:proof.afterResendCommit.proofSignedAt,otp_valide_a:proof.afterResendCommit.otpValidatedAt,
      statut_signature:proof.afterResendCommit.proofStatus,hash_document:state.contrat.hash_document,
      cree_le:now,ip_signature:'127.0.0.1',user_agent:'UI simulée, état issu du témoin PG17'});
    const original=structuredClone(state.signatures);
    control.refuser('fn_envoyer_otp_signature',proof.resendResult);
    await page.getByRole('button',{name:'Recevoir le code SMS pour signer',exact:true}).click();
    await expect(page.getByRole('alert')).toContainText('Vous avez déjà signé ce contrat.');
    await expect(page.getByRole('textbox',{name:'Code SMS à 6 chiffres'})).toHaveCount(0);
    await preuveMission(page,info,partie+'-renvoi-refuse');
    await stabiliserActionsNationales(page);await page.reload();
    await expect(page.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
    await expect(page.getByRole('button',{name:'Recevoir le code SMS pour signer',exact:true})).toHaveCount(0);
    await preuveMission(page,info,partie+'-preuve-conservee-reload');
    expect(state.signatures).toEqual(original);expect(state.sms).toHaveLength(0);
    expect(state.unknown).toEqual([]);expect(state.errors).toEqual([]);expect(state.external).toEqual([]);verifier();
  } finally {await context.close();}
 });
}
function factures(corrigees=false) {
 const proof=receipt('finances','receipt.json');
 expect(proof.qualification).toBe('FIX_VERIFIED');expect(proof.invoicedHt).toBe(480);expect(proof.commissionHt).toBe(72);
 const source=corrigees?proof.cases['correction-documentaire-ui']:proof;
 if(corrigees){expect(source.cumulHt).toBe(140);expect(source.semaineSuivante.montant_ht_periode).toBe(80);}
 return {honoraires:source.honoraires.map((f:any)=>({...f,mission_intitule:'Mission de nuit fictive',etablissement_nom:'Clinique fictive',
  statut_litige:'NORMAL',montant_tva:0,taux_tva:0,date_emission:'2026-09-09T09:00:00Z',emise_le:'2026-09-09T09:00:00Z',
  notifiee_soignant_le:'2026-09-09T09:00:00Z',verification_echeance_le:'2026-10-09T09:00:00Z'})),
 commissions:proof.commissions.map((f:any)=>({...f,facture_id:f.id,chorus_pro_statut:'NON_APPLICABLE'}))};
}
for(const corrigees of [false,true]) {
 test(`FIN107 soignant : périodes ${corrigees?'corrigée 60 puis 80':'200 puis 280'} conservées après rechargement`,async({page},info)=>{
 const {honoraires}=factures(corrigees);const etat=await simulerSoignant(page),verifier=await fermerReseau(page);
 Object.assign(etat.profile,{type_exercice:'LIBERAL',statut_liberal:'EN_COURS'});
 const rows=honoraires.map((f:any)=>({...f,soignant_id:idsSoignant.user,etablissement_id:idsSoignant.etab}));
 etat.overrides.set('fn_mes_factures_honoraires',rows);etat.tables.set('factures_honoraires',rows);
 await entrerSoignant(page,'connexion');await aller(page,'/soignant/mes-gains');
 await page.getByRole('tab',{name:'Factures',exact:true}).click();
 for(const reload of [false,true]) {
  if(reload)await recharger(page);
  for(const f of rows)await expect(page.getByText(f.numero_facture,{exact:true})).toBeVisible();
  await expect(page.getByRole('tabpanel')).toContainText(corrigees?/60,00\s*€/:/200,00\s*€/);
  await expect(page.getByRole('tabpanel')).toContainText(corrigees?/80,00\s*€/:/280,00\s*€/);
 }
 await page.screenshot({path:info.outputPath('soignant-deux-periodes.png'),fullPage:true});
 expect(etat.unknown).toEqual([]);expect(etat.errors).toEqual([]);verifier();
});
}
test('FIN107 établissement : commissions distinctes 36 et 50,40 euros TTC après rechargement',async({page},info)=>{
 const {commissions}=factures();const {etat}=await simulerEtablissement(page),verifier=await fermerReseau(page);
 etat.overrides.set('fn_mon_etablissement_complet',{...etablissement,type:'CLINIQUE_PRIVEE',est_compte_test:true,
  statut_verification:'EN_ATTENTE',est_verifie:false,peut_publier_missions:false,mode_paiement_commission:'FACTURE_MENSUELLE'});
 const rows=commissions.map((f:any)=>({...f,etablissement_id:idsEtab.etab}));
 etat.overrides.set('fn_obligations_financieres',{total_du:86.4,missions_a_payer:[],factures_impayees:rows});
 etat.overrides.set('fn_mes_factures',rows);
 await entrerEtablissement(page,'connexion');await allerA(page,'/etablissement/facturation?tab=commissions');
 for(const reload of [false,true]){
  if(reload){await stabiliserLectures(page);await page.reload();}
  for(const f of rows)await expect(page.getByText(f.numero_facture,{exact:true})).toBeVisible();
  await expect(page.locator('main')).toContainText(/36,00\s*€/);await expect(page.locator('main')).toContainText(/50,40\s*€/);
 }
 await page.screenshot({path:info.outputPath('etablissement-deux-commissions.png'),fullPage:true});
 expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.operations).toEqual([]);verifier();
});

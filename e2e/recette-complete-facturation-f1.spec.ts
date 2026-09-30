import { test, expect, type Page } from '@playwright/test';
import { simulerSoignant, entrer as entrerSoignant, aller, recharger, ids as idsSoignant } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures, ids as idsEtab, etablissement } from './helpers/recette-complete-etablissement';

// États simulés correspondant aux montants F1. Aucun appel des RPC financières,
// PDF/XML, Edge ou fournisseur ; la preuve SQL est distincte de ces écrans.
const honoraire = { id:'f1300004-4000-4000-8000-000000000004', mission_id:'f1300003-3000-4000-8000-000000000003',
  numero_facture:'F1-HONORAIRE-SEMAINE', mission_intitule:'Mission hebdomadaire fictive F1', etablissement_nom:'Clinique fictive F1',
  type_document:'FACTURE', nature_correction:'ORIGINALE', statut:'EMISE', statut_litige:'NORMAL', montant_ht:80,montant_ttc:80,montant_tva:0,taux_tva:0,
  periode_debut:'2026-09-21',periode_fin:'2026-09-27',est_facture_finale_mission:false,
  date_emission:'2026-09-30T09:00:00Z',emise_le:'2026-09-30T09:00:00Z',notifiee_soignant_le:'2026-09-30T09:00:00Z',verification_echeance_le:'2026-10-02T09:00:00Z' };
const commission={id:'f1300006-6000-4000-8000-000000000006',facture_id:'f1300006-6000-4000-8000-000000000006',
  facture_honoraire_id:honoraire.id,numero_facture:'F1-COMMISSION-SEMAINE',statut:'EMISE',type_document:'FACTURE',
  montant_ht:12,montant_tva:2.4,montant_ttc:14.4,nombre_missions:1,periode_debut:honoraire.periode_debut,periode_fin:honoraire.periode_fin,
  date_emission:honoraire.date_emission,date_echeance:'2026-10-30',est_secteur_public:false,chorus_pro_statut:'NON_APPLICABLE'};
async function fermerReseau(page:Page) {
  const interdits:string[]=[],erreurs:string[]=[];
  page.on('console',message=>{if(message.type()==='error')erreurs.push(message.text());});
  await page.clock.setFixedTime(new Date('2026-09-30T10:00:00Z'));
  await page.addInitScript(()=>Object.defineProperty(window,'Stripe',{value:()=>{throw Error('Paiement interdit dans F1');}}));
  await page.route('**/*',async route=>{
    const r=route.request(),u=new URL(r.url());
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
test('F1 soignant : honoraire intermédiaire émis et à vérifier, montant conservé après recharge',async({page},info)=>{
  const etat=await simulerSoignant(page),verifier=await fermerReseau(page);
  Object.assign(etat.profile,{type_exercice:'LIBERAL',statut_liberal:'EN_COURS',rpps_verifie:false,tous_documents_valides:false});
  etat.overrides.set('fn_mes_factures_honoraires',[{...honoraire,soignant_id:idsSoignant.user,etablissement_id:idsSoignant.etab}]);
  etat.tables.set('factures_honoraires',[{...honoraire,soignant_id:idsSoignant.user}]);
  await entrerSoignant(page,'connexion');await aller(page,'/soignant/mes-gains');
  await page.getByRole('tab',{name:'Factures',exact:true}).click();
  for(const reload of [false,true]) {
    if(reload)await recharger(page);
    await expect(page.getByText(honoraire.numero_facture,{exact:true})).toBeVisible();
    await expect(page.getByRole('tabpanel')).toContainText(/80,00\s*€/);
    await expect(page.getByRole('tabpanel')).toContainText('À vérifier');
    await expect(page.getByRole('button',{name:/^(Valider|Tout est correct)$/})).toBeVisible();
  }
  await page.screenshot({path:info.outputPath('soignant-honoraire-recharge.png'),fullPage:false});
  expect(etat.unknown).toEqual([]);expect(etat.errors).toEqual([]);
  expect(etat.calls.filter(c=>/emettre|preparer_facture|accepter_document|generate-invoice|checkout/.test(c.name))).toEqual([]);verifier();
});
test('F1 établissement : commission de période distincte, montant et échéance après recharge',async({page},info)=>{
  const {etat}=await simulerEtablissement(page),verifier=await fermerReseau(page);
  etat.overrides.set('fn_mon_etablissement_complet',{...etablissement,type:'CLINIQUE_PRIVEE',est_compte_test:true,
    statut_verification:'EN_ATTENTE',est_verifie:false,peut_publier_missions:false,mode_paiement_commission:'FACTURE_MENSUELLE'});
  etat.overrides.set('fn_obligations_financieres',{total_du:14.4,missions_a_payer:[],factures_impayees:[commission]});
  etat.overrides.set('fn_mes_factures',[{...commission,etablissement_id:idsEtab.etab}]);
  await entrerEtablissement(page,'connexion');await allerA(page,'/etablissement/facturation?tab=commissions');
  for(const reload of [false,true]) {
    if(reload){await stabiliserLectures(page);await page.reload();}
    await expect(page.getByText(commission.numero_facture,{exact:true})).toBeVisible();
    await expect(page.locator('main')).toContainText(/14,40\s*€/);
    await expect(page.getByText('Période facturée : 21 septembre 2026 → 27 septembre 2026. Le montant correspond à cette période, pas nécessairement à toute la mission.',{exact:true})).toBeVisible();
  }
  await page.getByText(commission.numero_facture,{exact:true}).scrollIntoViewIfNeeded();
  await page.screenshot({path:info.outputPath('etablissement-commission-recharge.png'),fullPage:false});
  expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);expect(etat.operations).toEqual([]);verifier();
});

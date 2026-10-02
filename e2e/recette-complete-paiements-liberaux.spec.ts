import { test, expect, type Page, type Locator } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

// Simulation explicite : réponses API fictives, aucune déclaration, aucun email
// ni paiement fournisseur. Le backend transactionnel possède sa preuve distincte.
// Seule l'exécution ciblée configurée utilise cette valeur fictive compilée.
const configurationFictive = process.env.RECETTE_STRIPE_CONFIGURATION === 'fictive';
const indisponible = 'Le paiement par carte est momentanément indisponible. Réessayez plus tard.';
const commissionId = '71000000-0000-4000-8000-000000000097';
const hostedUrl = 'https://checkout.stripe.com/c/pay/cs_test_fixture_configuration';
const autreMission = '71000000-0000-4000-8000-000000000093';
const originale = '71000000-0000-4000-8000-000000000080';
const remplacement = '71000000-0000-4000-8000-000000000060';
const seconde = '71000000-0000-4000-8000-000000000081';
const autreFacture = '71000000-0000-4000-8000-000000000090';
const lectureRpc = new Set(['fn_get_my_role','fn_compte_auth_actif','fn_mon_etablissement_complet','fn_etablissement_public','fn_etablissement_pour_mission','fn_etablissements_safe','fn_soignant_pour_etablissement','fn_messages_non_lus','fn_mes_permissions_etab','fn_obligations_financieres','fn_paiements_etablissement','fn_mes_factures','fn_detail_facture','fn_litige_pour_mission','fn_presences_detail_mission','fn_suivi_escrow_mission','fn_lister_copies_bulletins','fn_note_moyenne','fn_mode_exercice','fn_param_bool','fn_onboarding_soignant_statut','fn_alerte_cddu_repetitif','fn_etat_pointage_mission','fn_mode_paiement_mission','fn_score_etab_public','fn_user_id_pour_etablissement','fn_est_bloque','fn_interlocuteurs_conversations']);
async function action(page: Page, cible: Locator) {
  await cible.scrollIntoViewIfNeeded();
  if (test.info().project.use.hasTouch) await cible.tap(); else await cible.click();
}
async function verifierActionsPaiement(piece: Locator, nom: string) {
  const payer = piece.getByRole('button', { name: nom, exact: true });
  const contester = piece.getByRole('button', { name: 'Contester', exact: true });
  await payer.scrollIntoViewIfNeeded();
  if (!test.info().project.use.hasTouch) await payer.hover();
  await expect.poll(async () => {
    const [p, c, icone, texte] = await Promise.all([
      payer.boundingBox(), contester.boundingBox(), payer.locator('svg').boundingBox(),
      payer.getByText(nom, { exact: true }).boundingBox(),
    ]);
    if (!p || !c || !icone || !texte) return false;
    const separes = p.x + p.width <= c.x || c.x + c.width <= p.x || p.y + p.height <= c.y || c.y + c.height <= p.y;
    const centresAlignes = Math.abs(icone.y + icone.height / 2 - texte.y - texte.height / 2) <= 2;
    return separes && centresAlignes && icone.x + icone.width <= texte.x;
  }, { message: 'Icône alignée avec le texte et actions de paiement sans recouvrement au survol' }).toBe(true);
}
async function fixture(page: Page, connect = false, commission = false, commissionScenario: 'mensuelle' | 'complementaire-salariee' | 'liee-payee' = 'mensuelle') {
  const simulation = creerSuiviSimule(), { state } = simulation;
  Object.assign(state.mission, { statut: connect ? 'EN_COURS' : 'TERMINEE', type_contrat_applique: 'LIBERAL',
    soignant_assigne_id: ids.soignant, taux_horaire_base: 20, total_brut: 160, net_a_payer: 160,
    intitule: 'Mission libérale documentaire', debut_le: '2026-09-14T08:00:00Z', fin_le: '2026-09-21T12:00:00Z' });
  if (commissionScenario === 'complementaire-salariee') state.mission.type_contrat_applique = 'SALARIE';
  state.creneaux.splice(0,state.creneaux.length,
    {...state.creneaux[0],debut:'2026-09-14T08:00:00Z',fin:'2026-09-14T12:00:00Z'},
    {...state.creneaux[0],id:'71000000-0000-4000-8000-000000000014',debut:'2026-09-21T08:00:00Z',fin:'2026-09-21T12:00:00Z'});
  await simulation.installer(page.context(), 'ADMIN_ETABLISSEMENT');
  await page.clock.setFixedTime(new Date('2026-10-01T10:00:00Z'));
  const erreurs: string[] = [], interdits: string[] = [], mutations: { name: string; body: unknown }[] = [];
  const controle = { checkoutHeberge: false, modeInvalide: false, legacy: false, sansPiece: false, salarie: false, retour: false, historiqueIncomplet: false, historiqueLieComplet: false, refus: 'PAIEMENT_HISTORIQUE_A_RAPPROCHER', refusMessage: '', refusStatus: 200 };
  page.on('console', m => { if (m.type() === 'error') erreurs.push(m.text()); });
  page.on('pageerror', e => erreurs.push(e.message));
  await page.context().routeWebSocket('**/*', socket => socket.close());
  const docs = [
    { id: originale, numero_facture: 'FACTURE-ORIGINALE-80', statut: 'REMPLACEE', montant_ttc: 80, nature_correction: 'ORIGINALE' },
    { id: remplacement, numero_facture: 'FACTURE-RECTIFICATIVE-60', statut: 'EMISE', montant_ttc: 60, nature_correction: 'REMPLACEMENT', facture_precedente_id: originale },
    { id: seconde, numero_facture: 'FACTURE-SECONDE-80', statut: commissionScenario === 'liee-payee' ? 'PAYEE' : 'EMISE', montant_ttc: 80, nature_correction: 'ORIGINALE' },
    { id: autreFacture, numero_facture: 'FACTURE-AUTRE-MISSION', statut: 'EMISE', montant_ttc: 90, nature_correction: 'ORIGINALE' },
  ].map(f => ({ ...f, type_document: 'FACTURE', soignant_id: ids.soignant, etablissement_id: ids.etablissement,
    mission_id: f.id === autreFacture ? autreMission : ids.mission, date_emission: '2026-09-30',
    montant_ht: f.montant_ttc, montant_tva: 0, taux_tva: 0, periode_debut: f.id === seconde ? '2026-09-21' : '2026-09-14', periode_fin: f.id === seconde ? '2026-09-27' : '2026-09-20', est_facture_finale_mission: false,
    quantite_heures_snapshot: f.id === remplacement ? 3 : f.id === autreFacture ? 4.5 : 4, taux_horaire_snapshot: 20 }));
  const obligation = (id: string, net: number, missionId = ids.mission) => ({ mission_id: missionId,
    intitule: missionId === ids.mission ? state.mission.intitule : 'Autre mission documentaire',
    payment_key: id, facture_honoraires_id: controle.sansPiece ? null : id, type_contrat_applique: 'LIBERAL',
    soignant_id: ids.soignant, soignant_nom: 'Camille Recette', soignant_profession: 'MEDECIN',
    soignant_stripe_connect: connect, net_a_payer: net, montant_commission_ttc: 0, heures: 4,
    periode_debut: id === seconde ? '2026-09-21' : '2026-09-14', periode_fin: id === seconde ? '2026-09-27' : '2026-09-20', debut_le: state.mission.debut_le, fin_le: state.mission.fin_le, jours_depuis_fin: 1 });
  const factureCommission = { id: commissionId, facture_id: commissionId, numero_facture: 'COMMISSION-SIMULATION',
    etablissement_id: ids.etablissement, statut: commissionScenario === 'liee-payee' ? 'PAYEE' : 'EMISE',
    type_document: commissionScenario === 'complementaire-salariee' ? 'FACTURE_COMPLEMENTAIRE' : 'FACTURE', est_secteur_public: false,
    mission_id: commissionScenario === 'mensuelle' ? null : ids.mission,
    facture_honoraire_id: commissionScenario === 'liee-payee' ? seconde : null,
    mode_paiement: commissionScenario === 'complementaire-salariee' ? 'VIREMENT' : 'STRIPE',
    montant_ht: 12, montant_tva: 2.4, montant_ttc: 14.4, nombre_missions: 0,
    date_emission: '2026-09-30', date_echeance: '2026-10-30', periode_debut: '2026-09-01', periode_fin: '2026-09-30' };
  await page.route('**/*', async route => {
    const req = route.request(), url = new URL(req.url()), name = url.pathname.split('/').at(-1)!;
    const json = (data: unknown, count = Array.isArray(data) ? data.length : 0, offset = 0) => route.fulfill({ json: data, headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers':'content-range', ...(Array.isArray(data)?{'content-range':data.length?`${offset}-${offset+data.length-1}/${count}`:`*/${count}`}:{}) } });
    // Ressources externes neutralisées localement, jamais téléchargées.
    if (url.origin === 'https://fonts.googleapis.com' && req.method() === 'GET') return route.fulfill({contentType:'text/css',body:''});
    if (url.origin === 'https://js.stripe.com' && url.pathname === '/clover/stripe.js' && req.method() === 'GET') {
      return route.fulfill({contentType:'application/javascript',body: configurationFictive
        ? `window.Stripe = function(key){ if(key !== 'pk_test_JOLENE_SIMULATION_CONFIGURATION') throw Error('Clé réelle interdite'); window.__joleneStripeConfigurationFictive=true; const refuse=()=>{throw Error('Paiement fournisseur interdit');}; return {_registerWrapper(){},registerAppInfo(){},elements:refuse,createToken:refuse,createPaymentMethod:refuse,confirmCardPayment:refuse,initEmbeddedCheckout:refuse}; };`
        : 'window.Stripe = function(){ throw Error("Fournisseur interdit dans la simulation sans clé"); };'});
    }
    if (commission && req.url() === hostedUrl && req.isNavigationRequest() && req.method() === 'GET') {
      return route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html lang="fr"><meta charset="utf-8"><title>Paiement simulé</title><h1>Paiement hébergé simulé</h1></html>'});
    }
    if (!['127.0.0.1','localhost'].includes(url.hostname)) { interdits.push(`${req.method()} ${url.origin}${url.pathname}`); return route.abort(); }
    if (url.pathname.startsWith('/functions/')) {
      if (commission) {
        expect(name).toBe('create-invoice-payment'); expect(req.method()).toBe('POST');
        expect(req.postDataJSON()).toEqual({ facture_id: commissionId, embedded: false });
        mutations.push({ name, body: req.postDataJSON() });
        return json(controle.checkoutHeberge ? { url: hostedUrl } : { client_secret: 'cs_test_fixture_secret', resumed: true });
      }
      expect(name).toBe('stripe-connect-pay-mission'); expect(connect).toBe(true); expect(req.method()).toBe('POST');
      expect(req.postDataJSON()).toEqual({ mission_id: ids.mission, facture_honoraire_id: remplacement });
      mutations.push({ name, body: req.postDataJSON() });
      return route.fulfill({ status: controle.refusStatus, json: { error: controle.refus, ...(controle.refusMessage ? { message: controle.refusMessage } : {}) } });
    }
    if (url.pathname.startsWith('/storage/')) { interdits.push(`${req.method()} ${url.pathname}`); return route.abort(); }
    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      const body = req.postDataJSON(); expect(req.method()).toBe('POST');
      if (['fn_update_presence','fn_obtenir_conversation','fn_marquer_messages_lus'].includes(name)) return json(name === 'fn_obtenir_conversation' ? '71000000-0000-4000-8000-000000000007' : null);
      if (name === 'fn_declarer_paiement_facture_soignant') {
        expect(connect).toBe(false); expect(body).toEqual({ p_facture_honoraire_id: remplacement, p_montant: 60, p_methode: 'VIREMENT', p_reference: 'VIR-2026-060', p_date_paiement: '2026-10-01', p_attestation_sur_l_honneur: true });
        mutations.push({ name, body }); return json({ error: controle.refus });
      }
      if (name === 'fn_suivi_remboursements_connect_facture') {
        expect(connect && controle.retour).toBe(true);
        expect(body).toEqual({ p_facture_honoraire_id: remplacement, p_checkout_session_id: 'cs_test_retour_liberal' });
        return json({ facture_honoraire_id: remplacement, mission_id: ids.mission, checkout_session_id_filtre: 'cs_test_retour_liberal',
          source: 'CONNECT_AVANT_TRANSFERT', visibilite_montants: 'TOTAL_ETABLISSEMENT', paiement_statut: 'ECHOUE', operations: [], lecture_complete: true });
      }
      if (!lectureRpc.has(name)) { interdits.push(`RPC ${name}`); return route.abort(); }
      if (commission && name === 'fn_mes_factures') return json([factureCommission]);
      if (commission && name === 'fn_detail_facture') {
        expect(body).toEqual({ p_facture_id: commissionId });
        return json({ facture: factureCommission, missions: [] });
      }
      if (commission && name === 'fn_obligations_financieres') return json({ total_du: commissionScenario === 'liee-payee' ? 0 : 14.4,
        total_soignants_du: 0, total_commissions_du: commissionScenario === 'liee-payee' ? 0 : 14.4, missions_non_payees: [],
        factures_impayees: commissionScenario === 'liee-payee' ? [] : [factureCommission], paiements_soignants_en_attente: [], paiements_soignants_confirmes: [],
        factures_commission_historique: commissionScenario === 'liee-payee' ? [factureCommission] : [], missions_non_facturees: [] });
      if (name === 'fn_mode_paiement_mission') return json(controle.modeInvalide ? {} : { type_contrat_applique: controle.salarie ? 'SALARIE' : 'LIBERAL', mode_recommande: controle.salarie ? 'VIREMENT_PAIE' : connect ? 'STRIPE_CONNECT' : 'VIREMENT_NOTE_HONORAIRES', montant_soignant: 160, commission_ttc: 24, total: 184 });
      if (name === 'fn_obligations_financieres') return json({ total_du: 230, total_soignants_du: 230, total_commissions_du: 0, nb_missions_non_payees: 2,
        missions_non_payees: [obligation(remplacement,60),obligation(seconde,80),obligation(autreFacture,90,autreMission)],
        factures_impayees: [], paiements_soignants_en_attente: [], paiements_soignants_confirmes: [], factures_commission_historique: [], missions_non_facturees: [] });
    }
    if (url.pathname.startsWith('/rest/') && !url.pathname.includes('/rpc/')) {
      if (!['GET','HEAD'].includes(req.method())) { interdits.push(`${req.method()} ${name}`); return route.abort(); }
      if (commission && name === 'factures') {
        expect([`eq.${commissionId}`, `in.(${commissionId})`]).toContain(url.searchParams.get('id'));
        expect(url.searchParams.get('etablissement_id')).toBe(`eq.${ids.etablissement}`);
        return json(req.headers().accept?.includes('vnd.pgrst.object') ? factureCommission : [factureCommission]);
      }
      if (commission && name === 'missions' && url.searchParams.get('select') === 'id,type_contrat_applique') {
        expect(url.searchParams.get('id')).toBe(`eq.${ids.mission}`);
        expect(url.searchParams.get('etablissement_id')).toBe(`eq.${ids.etablissement}`);
        return json({ id: ids.mission, type_contrat_applique: state.mission.type_contrat_applique });
      }
      if (name === 'stripe_transfers' && url.searchParams.get('select') === 'statut' && controle.retour) {
        interdits.push('Retour déduit de la dernière trace sans Session exacte'); return route.abort();
      }
      if (name === 'factures_honoraires') {
        let rows = docs;
        for (const key of ['id', 'etablissement_id', 'mission_id','statut'] as const) {
          const filter = url.searchParams.get(key);
          if (filter?.startsWith('eq.')) rows = rows.filter(f => String(f[key]) === filter.slice(3));
          if (filter?.startsWith('in.(')) rows = rows.filter(f => filter.slice(4,-1).split(',').includes(String(f[key])));
        }
        if (req.headers().accept?.includes('vnd.pgrst.object')) {
          expect(rows).toHaveLength(1);
          return json(rows[0]);
        }
        return json(rows);
      }
      if (name === 'paiements_soignant') {
        const historique = { id:'71000000-0000-4000-8000-000000000096',mission_id:ids.mission,facture_honoraire_id:null,statut:'DECLARE',montant_net:60 };
        const select = url.searchParams.get('select');
        if (select === 'id,mission_id,facture_honoraire_id,statut') {
          expect(req.headers().prefer).toContain('count=exact');
          expect(url.searchParams.get('mission_id')).toBe(`in.(${ids.mission},${autreMission})`);
          const rows = controle.legacy || controle.historiqueLieComplet ? [...Array.from({length:200},(_,i)=>({id:`71000000-0000-4000-8001-${String(i).padStart(12,'0')}`,mission_id:ids.mission,facture_honoraire_id:originale,statut:'CONFIRME'})),{...historique,facture_honoraire_id:controle.legacy?null:originale}].map(({id,mission_id,facture_honoraire_id,statut})=>({id,mission_id,facture_honoraire_id,statut})) : [];
          const offset = Number(url.searchParams.get('offset') || 0), limit=Number(url.searchParams.get('limit'));
          expect(limit).toBe(200);
          return json(controle.historiqueIncomplet && offset > 0 ? [] : rows.slice(offset,offset+limit),rows.length,offset);
        }
        return json(controle.legacy ? [historique] : []);
      }
    }
    return route.fallback();
  });
  return { ...simulation, controle, mutations, docs,
    verifier(erreursAttendues: string[] = []) { expect(interdits).toEqual([]); expect(erreurs).toEqual(erreursAttendues); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]); expect(state.emails).toEqual([]); expect(state.sms).toEqual([]); expect(state.signatures).toEqual([]); } };
}
for (const connect of [false,true]) test(`Libéral ${connect ? `Connect EN_COURS (${configurationFictive ? 'configuration fictive' : 'sans clé'})` : 'virement TERMINEE'} : détail → pièce exacte, filtre et reprise`, async ({ page }, info) => {
  const f = await fixture(page, connect); await page.goto(`/etablissement/missions/${ids.mission}`);
  const carte = page.getByText('Paiement par facture', { exact: true }).locator('..');
  await expect(carte).toBeVisible(); if (!connect) await action(page,page.getByRole('button',{name:'Fermer',exact:true})); await expect(carte).not.toContainText(/160,00/);
  await expect(page.getByRole('button',{name:/Déclarer le paiement effectué|Payer via Stripe/})).toHaveCount(0);
  await action(page,page.getByRole('button',{name:'Voir les factures de cette mission'}));
  await expect(page).toHaveURL(new RegExp(`facturation\\?tab=missions-a-payer&mission=${ids.mission}`));
  for (const reload of [false,true]) {
    if (reload) { await stabiliserActionsNationales(page); await page.reload(); }
    f.controle.refus = reload ? 'PAIEMENT_STRIPE_EN_COURS' : 'PAIEMENT_HISTORIQUE_A_RAPPROCHER';
    const refusAttendu = reload
      ? 'Un règlement Stripe est déjà engagé pour cette facture. Consultez son état dans l’historique avant toute autre action.'
      : 'Un paiement antérieur doit être rapproché de sa facture avant de déclarer un nouveau règlement.';
    await expect(page.getByText('FACTURE-RECTIFICATIVE-60',{exact:true})).toBeVisible();
    await expect(page.getByText('FACTURE-SECONDE-80',{exact:true})).toBeVisible();
    await expect(page.getByText('FACTURE-ORIGINALE-80',{exact:true})).toHaveCount(0);
    await expect(page.getByText('FACTURE-AUTRE-MISSION',{exact:true})).toHaveCount(0);
    const piece = page.getByText('FACTURE-RECTIFICATIVE-60',{exact:true}).locator('xpath=ancestor::div[contains(@class,"card-base")][1]');
    await expect(piece).toContainText(/60,00\s*€/);
    await verifierActionsPaiement(piece, connect ? 'Payer via Stripe' : 'Déclarer un paiement');
    if (connect) {
      await action(page,piece.getByRole('button',{name:'Payer via Stripe',exact:true}));
      await expect(page.getByText(configurationFictive ? refusAttendu : indisponible,{exact:true})).toBeVisible();
      if (configurationFictive) await expect.poll(() => page.evaluate(() => Boolean((window as unknown as { __joleneStripeConfigurationFictive?: boolean }).__joleneStripeConfigurationFictive))).toBe(true);
    } else {
      await action(page,piece.getByRole('button',{name:'Déclarer un paiement',exact:true}));
      const dialog = page.getByRole('dialog'); await expect(dialog.getByLabel('Montant des honoraires versés')).toHaveValue('60.00');
      await action(page,dialog.getByRole('button',{name:'Annuler',exact:true})); await expect(dialog).toHaveCount(0); expect(f.mutations).toHaveLength(reload?1:0);
      await action(page,piece.getByRole('button',{name:'Déclarer un paiement',exact:true}));
      await dialog.getByLabel(/Référence/).fill('VIR-2026-060'); await dialog.getByLabel('Date du paiement',{exact:true}).fill('2026-10-01');
      await dialog.getByRole('checkbox').check(); await action(page,dialog.getByRole('button',{name:'Valider la déclaration'}));
      await expect(dialog.getByRole('alert')).toHaveText(refusAttendu);
      await action(page,dialog.getByRole('button',{name:'Annuler',exact:true}));
    }
    expect(f.mutations).toHaveLength(connect && !configurationFictive ? 0 : reload?2:1);
  }
  if (connect) {
    f.controle.retour=true;
    await stabiliserActionsNationales(page);
    await page.goto(`/etablissement/facturation?tab=missions-a-payer&mission=${ids.mission}&facture_honoraire=${remplacement}&paiement=succes&session_id=cs_test_retour_liberal`);
    await expect(page.getByText('La situation de ce paiement nécessite une vérification. Consultez son suivi avant de réessayer.',{exact:true})).toBeVisible();
    await expect(page.getByRole('dialog')).toContainText('La situation de ce paiement nécessite une vérification');
    await expect(page.getByText(/Aucun paiement n’a été enregistré/)).toHaveCount(0);
    await expect(page).toHaveURL(new RegExp(`mission=${ids.mission}`));
    await expect(page).not.toHaveURL(/paiement=|facture_honoraire=|session_id=/);
    await expect(page.getByText('FACTURE-AUTRE-MISSION',{exact:true})).toHaveCount(0);
    expect(f.mutations).toHaveLength(configurationFictive ? 2 : 0);
    await stabiliserActionsNationales(page);
    await page.goto(`/etablissement/facturation?tab=missions-a-payer&mission=${ids.mission}&paiement=succes`);
    await expect(page.getByText('Le retour Stripe ne permet pas d’identifier exactement ce paiement. Consultez son suivi avant de réessayer.',{exact:true})).toBeVisible();
    await expect(page.getByText('Paiement confirmé et enregistré.',{exact:true})).toHaveCount(0);
    await expect(page).toHaveURL(new RegExp(`mission=${ids.mission}`));
  }
  await page.getByRole('button',{name:'Retirer le filtre mission'}).scrollIntoViewIfNeeded();
  await page.screenshot({path:info.outputPath('factures-filtrees.png'),scale:'css',animations:'disabled'});
  await action(page,page.getByRole('button',{name:'Retirer le filtre mission'})); await expect(page).not.toHaveURL(/mission=/);
  await expect(page.getByText('FACTURE-AUTRE-MISSION',{exact:true})).toBeVisible();
  await stabiliserActionsNationales(page); await page.reload(); await expect(page.getByText('FACTURE-AUTRE-MISSION',{exact:true})).toBeVisible();
  f.verifier();
});
test('Libéral : mode invalide puis reprise, historique conservé et absence de pièce refuse le paiement',async({page},info)=>{
  const f=await fixture(page); f.controle.modeInvalide=true;
  await page.goto(`/etablissement/missions/${ids.mission}`); await expect(page.getByRole('alert').filter({hasText:'Paiement indisponible'})).toBeVisible(); await action(page,page.getByRole('button',{name:'Fermer',exact:true}));
  await expect(page.getByRole('button',{name:/Déclarer le paiement effectué|Payer via Stripe/})).toHaveCount(0);
  f.controle.modeInvalide=false; f.controle.legacy=true;
  await action(page,page.getByRole('button',{name:'Réessayer',exact:true}));
  await expect(page.getByText('Paiement déclaré — en attente du soignant',{exact:true})).toBeVisible();
  await expect(page.getByText(/Ce paiement antérieur n’est pas lié à une facture/)).toBeVisible();
  await action(page,page.getByRole('button',{name:'Voir les factures de cette mission'}));
  await expect(page.getByRole('alert').filter({hasText:'Un paiement antérieur doit être rapproché'})).toHaveCount(2);
  await expect(page.getByText('Total payable non établi',{exact:true})).toBeVisible();
  await expect(page.getByText('Montant de la pièce · solde à rapprocher',{exact:true})).toHaveCount(2);
  await page.screenshot({path:info.outputPath('historique-a-rapprocher.png'),scale:'css',animations:'disabled'});
  f.controle.historiqueIncomplet=true;
  await stabiliserActionsNationales(page); await page.reload();
  await expect(page.getByText('Impossible de charger les données de facturation en toute sécurité.',{exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:'Déclarer un paiement',exact:true})).toHaveCount(0);
  f.controle.historiqueIncomplet=false;
  await action(page,page.getByRole('button',{name:'Réessayer',exact:true}));
  await expect(page.getByRole('alert').filter({hasText:'Un paiement antérieur doit être rapproché'})).toHaveCount(2);
  // Nouvelle réponse fictive : les 201 règlements sont tous rattachés,
  // l'interface doit retrouver ses actions sur les deux pièces non réglées.
  f.controle.legacy=false; f.controle.historiqueLieComplet=true;
  await stabiliserActionsNationales(page); await page.reload();
  await expect(page.getByRole('button',{name:'Déclarer un paiement',exact:true})).toHaveCount(2);
  await expect(page.getByText('Total à régler',{exact:true})).toBeVisible();
  f.controle.sansPiece=true;
  await stabiliserActionsNationales(page); await page.reload();
  await expect(page.getByRole('alert').filter({hasText:'Facture identifiée requise'})).toHaveCount(2);
  await expect(page.getByRole('button',{name:'Déclarer un paiement',exact:true})).toHaveCount(0);
  await expect(page.getByRole('button',{name:'Payer via Stripe',exact:true})).toHaveCount(0);
  await page.screenshot({path:info.outputPath('paiement-indisponible.png'),scale:'css',animations:'disabled'});
  expect(f.mutations).toEqual([]);f.verifier(['[ERROR] Facturation charger error Historique des paiements incomplet ou incohérent']);
});

test('Salarié : bulletin explicite, montant partiel refusé et escrow conservé après recharge',async({page},info)=>{
  const f=await fixture(page); f.controle.salarie=true; f.state.mission.type_contrat_applique='SALARIE';
  await page.goto(`/etablissement/missions/${ids.mission}`);
  await expect(page.getByText('Virement de rémunération salariée',{exact:true})).toBeVisible(); await action(page,page.getByRole('button',{name:'Fermer',exact:true}));
  await expect(page.getByRole('button',{name:'Voir les factures de cette mission'})).toHaveCount(0);
  const total=page.getByLabel('Montant net total dû selon le bulletin officiel *',{exact:true});
  const verse=page.getByLabel('Montant réellement versé aujourd’hui *',{exact:true});
  await expect(total).toHaveValue(''); await expect(verse).toHaveValue('');
  await total.fill('100'); await verse.fill('60');
  await page.getByLabel('Référence de paiement *',{exact:true}).fill('VIR-2026-060');
  const carte=page.getByText('Virement de rémunération salariée',{exact:true}).locator('..');
  await carte.getByRole('checkbox').check();
  await action(page,carte.getByRole('button',{name:'Déclarer le paiement effectué'}));
  await expect(page.getByText('Le montant versé doit correspondre exactement au total net dû. Les paiements partiels ne sont pas acceptés.',{exact:true})).toBeVisible();
  expect(f.mutations).toEqual([]);
  await verse.fill('100'); await expect(carte.getByRole('button',{name:'Déclarer le paiement effectué'})).toBeEnabled();
  await page.screenshot({path:info.outputPath('salarie-bulletin.png'),scale:'css',animations:'disabled'});
  f.suivi.escrow=[{statut:'DEBITE',paye_le:null}];
  await stabiliserActionsNationales(page); await page.reload();
  await expect(page.getByText('Paiement suivi par Jolene',{exact:true})).toBeVisible(); await action(page,page.getByRole('button',{name:'Fermer',exact:true}));
  await expect(page.getByRole('button',{name:'Déclarer le paiement effectué'})).toHaveCount(0);
  await page.screenshot({path:info.outputPath('escrow-conserve.png'),scale:'css',animations:'disabled'});
  expect(f.mutations).toEqual([]); f.verifier();
});

// Ces deux routes font partie de la CI ordinaire compilée sans clé. L'exécution
// configurée ciblée couvre séparément les refus API Connect, y compris ceux ci-dessous.
for (const detail of [false, true]) test(`Stripe sans clé — commission depuis ${detail ? 'le détail facture' : 'la facturation'}`, async ({ page }, info) => {
  const f = await fixture(page, false, true);
  const path = detail ? `/etablissement/facturation/${commissionId}` : '/etablissement/facturation?tab=commissions';
  await page.goto(path);
  if (!detail) {
    await action(page, page.getByRole('button', { name: 'Consulter les modalités de règlement', exact: true }));
    await expect(page).toHaveURL(new RegExp(`/etablissement/facturation/${commissionId}$`));
  }
  const payer = () => page.getByRole('button', { name: 'Payer', exact: true });
  await action(page, payer());
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByText(indisponible, { exact: true })).toBeVisible();
  await expect(page.locator('#stripe-checkout-container')).toHaveCount(0);
  expect(f.mutations).toHaveLength(1);
  await page.screenshot({ path: info.outputPath('stripe-sans-cle.png'), scale: 'css', animations: 'disabled' });
  await action(page, dialog.getByText(indisponible, { exact: true }).locator('..').getByRole('button', { name: 'Fermer', exact: true }));
  await expect(dialog).toHaveCount(0);
  await stabiliserActionsNationales(page); await page.reload();
  await expect(payer()).toBeVisible(); expect(f.mutations).toHaveLength(1);
  f.controle.checkoutHeberge = true;
  await action(page, payer());
  await expect(page).toHaveURL(hostedUrl);
  await expect(page.getByRole('heading', { name: 'Paiement hébergé simulé' })).toBeVisible();
  expect(f.mutations).toHaveLength(2); f.verifier();
});

test('Détail commission complémentaire salariée : virement disponible, carte absente après rechargement', async ({ page }, info) => {
  const f = await fixture(page, false, true, 'complementaire-salariee');
  await page.goto(`/etablissement/facturation/${commissionId}`);
  for (const reload of [false, true]) {
    if (reload) { await stabiliserActionsNationales(page); await page.reload(); }
    await expect(page.getByText('COMMISSION-SIMULATION', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Payer', exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Payer par carte', exact: true })).toHaveCount(0);
    await action(page, page.getByRole('button', { name: 'Virement', exact: true }));
    await expect(page.getByLabel('Référence de votre virement')).toBeVisible();
    await expect(page.getByRole('button', { name: /J'ai effectué le virement/ })).toBeDisabled();
    await action(page, page.getByRole('button', { name: 'Annuler', exact: true }));
    expect(f.mutations).toHaveLength(0);
  }
  await page.screenshot({ path: info.outputPath('commission-complementaire-virement.png'), scale: 'css', animations: 'disabled' });
  f.verifier();
});

test('Détail commission liée payée : historique annoncé sans faux filtre ni nouveau paiement', async ({ page }, info) => {
  const f = await fixture(page, false, true, 'liee-payee');
  await page.goto(`/etablissement/facturation/${commissionId}`);
  const historique = page.getByRole('button', { name: 'Consulter l’historique des paiements', exact: true });
  for (const reload of [false, true]) {
    if (reload) { await stabiliserActionsNationales(page); await page.reload(); }
    await expect(historique).toBeVisible();
    await expect(page.getByText('4 h facturées', { exact: true })).toBeVisible();
    await expect(page.getByText(/Prélèvement SEPA automatique programmé/)).toHaveCount(0);
    await expect(page.getByRole('button', { name: /^(Payer|Payer par carte|Virement|Consulter le règlement des honoraires)$/ })).toHaveCount(0);
    expect(f.mutations).toHaveLength(0);
  }
  await page.screenshot({ path: info.outputPath('commission-liee-payee-historique.png'), scale: 'css', animations: 'disabled' });
  await action(page, historique);
  await expect(page).toHaveURL(/\/etablissement\/facturation\?tab=historique$/);
  await page.reload();
  await expect(page).toHaveURL(/\/etablissement\/facturation\?tab=historique$/);
  expect(f.mutations).toHaveLength(0); f.verifier();
});

for (const refus of [
  {
    code: 'CONNECT_REFUND_RECONCILIATION_REQUIRED', status: 409, statusText: 'Conflict',
    message: 'Un remboursement est lié à cette tentative de paiement. Son rapprochement doit être terminé avant tout nouveau règlement de cette facture.',
  },
  {
    code: 'CONNECT_RELEASE_CLOSED', status: 503, statusText: 'Service Unavailable',
    message: 'Le paiement de cette facture est temporairement indisponible pendant une mise à jour. Réessayez plus tard depuis Facturation.',
  },
  {
    code: 'CONNECT_CLIENT_VERSION_REQUIRED', status: 503, statusText: 'Service Unavailable',
    message: 'Cette version du paiement est indisponible. Rechargez Facturation avant de réessayer.',
  },
]) test(`Connect (${configurationFictive ? 'configuration fictive' : 'sans clé'}) : ${refus.code} explique le refus sans ouvrir un paiement`, async ({ page }, info) => {
  const f = await fixture(page, true);
  f.controle.refus = refus.code;
  f.controle.refusMessage = refus.message;
  f.controle.refusStatus = refus.status;
  await page.goto(`/etablissement/facturation?tab=missions-a-payer&mission=${ids.mission}`);
  const piece = page.getByText('FACTURE-RECTIFICATIVE-60', { exact: true }).locator('xpath=ancestor::div[contains(@class,"card-base")][1]');
  await action(page, piece.getByRole('button', { name: 'Payer via Stripe', exact: true }));
  await expect(page.getByText(configurationFictive ? f.controle.refusMessage : indisponible, { exact: true })).toBeVisible();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByText('Paiement confirmé et enregistré.', { exact: true })).toHaveCount(0);
  expect(f.mutations).toEqual(configurationFictive ? [{ name: 'stripe-connect-pay-mission', body: { mission_id: ids.mission, facture_honoraire_id: remplacement } }] : []);
  await page.screenshot({ path: info.outputPath(`${refus.code.toLowerCase()}.png`), scale: 'css', animations: 'disabled' });
  await stabiliserActionsNationales(page); await page.reload();
  await expect(piece).toBeVisible();
  expect(f.mutations).toHaveLength(configurationFictive ? 1 : 0);
  f.verifier(configurationFictive ? [`Failed to load resource: the server responded with a status of ${refus.status} (${refus.statusText})`] : []);
});

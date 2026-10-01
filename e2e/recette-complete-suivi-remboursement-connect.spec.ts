import { test, expect, type Page, type Locator, type BrowserContext } from '@playwright/test';
import { ids } from './helpers/recette-complete-mission';
import { creerActionsNationales, stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

// Réponses API contrôlées : aucune Session, aucun paiement/refund créé chez Stripe.
const session = 'cs_test_retour_exact';
async function action(target: Locator) {
  await target.scrollIntoViewIfNeeded();
  if (test.info().project.use.hasTouch) await target.tap(); else await target.click();
}
async function installer(page: Page, context: BrowserContext, role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' | 'ADMIN_PLATEFORME') {
  const simulation = creerActionsNationales(), { state } = simulation;
  Object.assign(state.mission, { statut: 'TERMINEE', soignant_assigne_id: ids.soignant, type_contrat_applique: 'LIBERAL' });
  state.presence = { valide_par_etablissement: true }; simulation.simulerEmissionFacture();
  Object.assign(state.facture, { statut: 'PAYEE', emise_le: '2026-09-30T09:00:00Z' });
  await simulation.installer(context, role); await stabiliserActionsNationales(page);
  await page.clock.setFixedTime(new Date('2026-10-01T12:00:00Z'));
  await page.route('https://fonts.googleapis.com/**', r => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('https://js.stripe.com/**', r => r.fulfill({ contentType: 'application/javascript', body: 'window.Stripe=function(){throw Error("Stripe interdit dans cette simulation")}' }));
  await context.routeWebSocket('**/*', socket => socket.close());
  const errors: string[] = []; page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.route('**/rest/v1/rpc/fn_mes_factures_honoraires', r => r.fulfill({ json: [state.facture] }));
  await page.route('**/rest/v1/rpc/fn_mes_bulletins_paie', r => r.fulfill({ json: [] }));
  await page.route('**/rest/v1/rpc/fn_lister_copies_bulletins', r => r.fulfill({ json: [] }));
  if (role === 'ADMIN_PLATEFORME') await page.route('**/rest/v1/rpc/fn_admin_mes_acces', r => r.fulfill({ json: { acces_total: true, groupes: [] } }));
  await page.route('**/rest/v1/rpc/fn_obligations_financieres', r => r.fulfill({ json: {
    total_du: 0, total_soignants_du: 0, total_commissions_du: 0, nb_missions_non_payees: 0,
    factures_impayees: [], missions_non_payees: [], missions_non_facturees: [], paiements_soignants_en_attente: [], factures_commission_historique: [],
    paiements_soignants_confirmes: [{ paiement_id: '71000000-0000-4000-8000-000000000091', mission_id: ids.mission, mission_intitule: state.mission.intitule,
      soignant_nom: 'Camille Recette', montant_net: 80, confirme_par_soignant_le: '2026-09-30', reference_virement: 'VIR-80', facture_honoraires_id: state.facture.id }],
  } }));
  const suivi = (statut: string, filtre: string | null = null) => ({ facture_honoraire_id: state.facture.id, mission_id: ids.mission,
    checkout_session_id_filtre: filtre, source: 'CONNECT_AVANT_TRANSFERT', visibilite_montants: role === 'SOIGNANT' ? 'HONORAIRES' : 'TOTAL_ETABLISSEMENT',
    paiement_statut: filtre ? statut === 'SUCCEEDED' ? 'REMBOURSE' : ['REVIEW', 'FAILED', 'CANCELED'].includes(statut) ? 'ECHOUE' : 'EN_ATTENTE' : null, lecture_complete: true,
    operations: [{ id: '71000000-0000-4000-8000-000000000095', checkout_session_id: session, statut,
      montant_honoraires_centimes: 8000, montant_commission_centimes: role === 'SOIGNANT' ? null : 1200, montant_total_centimes: role === 'SOIGNANT' ? null : 9200,
      cree_le: '2026-09-30T12:00:00Z', mis_a_jour_le: null, succeeded_at: ['SUCCEEDED', 'REVIEW'].includes(statut) ? '2026-09-30T12:05:00Z' : null,
      review_code: statut === 'REVIEW' ? 'REFUND_RETURNED_AFTER_SUCCESS' : null }],
  });
  return { state, suivi, verifier: () => { expect(errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]); expect(state.emails).toEqual([]); expect(state.sms).toEqual([]); } };
}

for (const role of ['ADMIN_ETABLISSEMENT', 'SOIGNANT'] as const) {
  test(`${role} : reprise du suivi, sept états et incident après confirmation`, async ({ page, context }, info) => {
    const { state, suivi, verifier } = await installer(page, context, role);
    let etat: string | null = null;
    const calls: unknown[] = [];
    await page.route('**/rest/v1/rpc/fn_suivi_remboursements_connect_facture', async route => {
      const body = route.request().postDataJSON(); calls.push(body);
      expect(body).toEqual({ p_facture_honoraire_id: state.facture.id, p_checkout_session_id: null });
      return route.fulfill({ json: etat === null ? null : suivi(etat) });
    });
    await page.goto(role === 'SOIGNANT' ? '/soignant/mes-gains?tab=factures' : '/etablissement/facturation?tab=historique');
    const entree = page.getByRole('button', { name: 'Suivi du paiement par carte', exact: true });
    await action(entree);
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('alert')).toContainText('Impossible de vérifier le suivi');
    await expect(dialog.getByText(/Aucun remboursement enregistré/)).toHaveCount(0);
    await expect(dialog).toHaveCSS('opacity', '1');
    await page.screenshot({ path: info.outputPath('lecture-en-erreur.png'), scale: 'css', animations: 'disabled' });
    etat = 'READY'; await action(dialog.getByRole('button', { name: 'Réessayer le suivi' }));
    await expect(dialog.getByRole('heading', { name: 'Remboursement en préparation', exact: true })).toBeVisible();
    for (const [valeur, titre] of [
      ['PENDING', 'Remboursement en cours'], ['REQUIRES_ACTION', 'Remboursement à vérifier'], ['FAILED', 'Remboursement échoué'],
      ['CANCELED', 'Remboursement annulé'], ['SUCCEEDED', 'Remboursement confirmé'], ['REVIEW', 'Vérification nécessaire'],
    ]) {
      etat = valeur; await action(dialog.getByRole('button', { name: 'Actualiser le suivi' }));
      await expect(dialog.getByRole('heading', { name: titre, exact: true })).toBeVisible();
      if (valeur !== 'SUCCEEDED') await expect(dialog.getByRole('heading', { name: 'Remboursement confirmé', exact: true })).toHaveCount(0);
    }
    await expect(dialog.getByText('Honoraires concernés', { exact: true })).toBeVisible();
    if (role === 'SOIGNANT') {
      await expect(dialog.getByText('Commission concernée', { exact: true })).toHaveCount(0);
      await expect(dialog.getByText('Montant du remboursement', { exact: true })).toHaveCount(0);
    } else {
      await expect(dialog.getByText('Montant du remboursement', { exact: true })).toBeVisible();
      await expect(dialog.getByText(/92,00/)).toBeVisible();
    }
    await page.screenshot({ path: info.outputPath('retour-bancaire-a-verifier.png'), scale: 'css', animations: 'disabled' });
    await action(dialog.getByRole('button', { name: 'Fermer le suivi' }));
    await stabiliserActionsNationales(page); await page.reload();
    await action(entree); await expect(dialog.getByRole('heading', { name: 'Vérification nécessaire', exact: true })).toBeVisible();
    await expect(dialog.getByText('Confirmation reçue le', { exact: true })).toHaveCount(0);
    expect(calls).toHaveLength(9);
    await page.screenshot({ path: info.outputPath('apres-rechargement.png'), scale: 'css', animations: 'disabled' });
    verifier();
  });
}

test('Établissement : retour exact sans faux succès et ancien lien sans confirmation automatique', async ({ page, context }) => {
  const { state, suivi, verifier } = await installer(page, context, 'ADMIN_ETABLISSEMENT');
  const calls: any[] = [];
  await page.route('**/rest/v1/rpc/fn_suivi_remboursements_connect_facture', async route => {
    const body = route.request().postDataJSON(); calls.push(body);
    expect(body.p_facture_honoraire_id).toBe(state.facture.id);
    expect([session, 'cs_test_non_connue', null]).toContain(body.p_checkout_session_id);
    const reponse = suivi('REVIEW', body.p_checkout_session_id);
    if (body.p_checkout_session_id === 'cs_test_non_connue') { reponse.paiement_statut = null; reponse.operations = []; }
    return route.fulfill({ json: reponse });
  });
  const chemin = `/etablissement/facturation?tab=historique&mission=${ids.mission}&facture_honoraire=${state.facture.id}&paiement=succes`;
  await page.goto(`${chemin}&session_id=${session}`);
  await expect(page.getByRole('dialog').getByRole('heading', { name: 'Vérification nécessaire', exact: true })).toBeVisible();
  await expect(page.getByText('Paiement confirmé et enregistré.', { exact: true })).toHaveCount(0);
  expect(calls.length).toBeGreaterThanOrEqual(2); expect(calls.every(body => body.p_checkout_session_id === session)).toBe(true);
  await action(page.getByRole('button', { name: 'Fermer le suivi' }));
  calls.length = 0;
  await page.goto(chemin);
  await expect(page.getByText('Le retour Stripe ne permet pas d’identifier exactement ce paiement. Consultez son suivi avant de réessayer.', { exact: true })).toBeVisible();
  await expect(page.getByRole('dialog').getByRole('heading', { name: 'Vérification nécessaire', exact: true })).toBeVisible();
  expect(calls).toHaveLength(1); expect(calls[0].p_checkout_session_id).toBeNull();
  await expect(page.getByText('Paiement confirmé et enregistré.', { exact: true })).toHaveCount(0);
  await expect(page.getByText(/Aucun paiement n’a été enregistré/)).toHaveCount(0);
  await page.goto(`${chemin}&session_id=cs_test_non_connue`);
  await expect(page.getByText('La confirmation de ce paiement n’est pas disponible pour le moment. Consultez son suivi avant de réessayer.', { exact: true })).toBeVisible({ timeout: 35_000 });
  await expect(page.getByRole('dialog')).toContainText('La confirmation de ce paiement est encore en attente.');
  await expect(page.getByText('Paiement confirmé et enregistré.', { exact: true })).toHaveCount(0);
  await expect(page.getByText(/Paiement transmis à Stripe/)).toHaveCount(0);
  verifier();
});

for (const role of ['ADMIN_ETABLISSEMENT', 'SOIGNANT', 'ADMIN_PLATEFORME'] as const) {
  test(`${role} : suivi accessible depuis la facture du détail mission`, async ({ page, context }) => {
    const { state, suivi, verifier } = await installer(page, context, role);
    state.mission.statut = 'EN_COURS';
    await page.route('**/rest/v1/rpc/fn_suivi_remboursements_connect_facture', async route => {
      expect(route.request().postDataJSON()).toEqual({ p_facture_honoraire_id: state.facture.id, p_checkout_session_id: null });
      return route.fulfill({ json: suivi('REVIEW') });
    });
    await page.goto(`/${role === 'SOIGNANT' ? 'soignant' : role === 'ADMIN_PLATEFORME' ? 'admin' : 'etablissement'}/missions/${ids.mission}`);
    await action(page.getByRole('button', { name: 'Suivi du paiement par carte', exact: true }));
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: 'Vérification nécessaire', exact: true })).toBeVisible();
    if (role === 'SOIGNANT') await expect(dialog.getByText('Commission concernée', { exact: true })).toHaveCount(0);
    else await expect(dialog.getByText('Commission concernée', { exact: true })).toBeVisible();
    await action(dialog.getByRole('button', { name: 'Fermer le suivi' }));
    verifier();
  });
}

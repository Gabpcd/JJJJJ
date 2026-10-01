import { test, expect, type Page, type Locator } from '@playwright/test';
import { ids } from './helpers/recette-complete-mission';
import { creerActionsNationales, stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';

// API intégralement simulée : aucun litige, remboursement ou email réel.
async function action(page: Page, target: Locator) {
  await target.scrollIntoViewIfNeeded();
  if (test.info().project.use.hasTouch) await target.tap(); else await target.click();
}
for (const role of ['ADMIN_ETABLISSEMENT', 'SOIGNANT'] as const) {
  test(`${role} : pièce exacte, lecture en erreur, reprise et confirmation vérifiée`, async ({ page, context }, info) => {
    const simulation = creerActionsNationales(), { state } = simulation;
    Object.assign(state.mission, { statut: 'TERMINEE', soignant_assigne_id: ids.soignant, type_contrat_applique: 'LIBERAL' });
    state.presence = { valide_par_etablissement: true }; simulation.simulerEmissionFacture();
    Object.assign(state.facture, { statut: 'PAYEE', emise_le: '2026-09-30T09:00:00Z', verification_echeance_le: '2026-10-02T09:00:00Z' });
    await simulation.installer(context, role);
    await stabiliserActionsNationales(page);
    await page.clock.setFixedTime(new Date('2026-10-01T10:00:00Z'));
    await page.route('https://fonts.googleapis.com/**', r => r.fulfill({ contentType: 'text/css', body: '' }));
    await page.route('https://js.stripe.com/**', r => r.fulfill({ contentType: 'application/javascript', body: 'window.Stripe=function(){throw Error("Stripe interdit dans ce test")}' }));
    await context.routeWebSocket('**/*', socket => socket.close());
    const errors: string[] = [], calls: unknown[] = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    let lectureDisponible = false, ouvert = false;
    await page.route('**/rest/v1/factures_honoraires?**', async route => {
      const req = route.request(), url = new URL(req.url());
      if (url.searchParams.get('select') !== 'id,mission_id,numero_facture,periode_debut,periode_fin,montant_ttc,statut,nature_correction') return route.fallback();
      expect(req.method()).toBe('GET');
      expect(req.headers().prefer).toContain('count=exact');
      expect(url.searchParams.get('mission_id')).toBe(`eq.${ids.mission}`);
      expect(url.searchParams.get('id')).toBe(`eq.${state.facture.id}`);
      if (!lectureDisponible) return route.fulfill({ json: null }); // réponse incomplète, jamais absence de facture
      return route.fulfill({ json: [state.facture], headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': '0-0/1' } });
    });
    await page.route('**/rest/v1/rpc/fn_ouvrir_litige_rate_limited', async route => {
      calls.push(route.request().postDataJSON());
      if (calls.length === 1) return route.fulfill({ json: { success: false } });
      if (calls.length === 2) return route.fulfill({ json: { success: false, error: 'La fenêtre de contestation de cette facture est fermée. Contactez le support.' } });
      ouvert = true; state.facture.statut_litige = 'EN_ATTENTE_LITIGE';
      return route.fulfill({ json: { success: true, litige_id: '71000000-0000-4000-8000-000000000090', facture_id: state.facture.id } });
    });
    await page.route('**/rest/v1/rpc/fn_mes_factures_honoraires', r => r.fulfill({ json: [state.facture] }));
    await page.route('**/rest/v1/rpc/fn_mes_bulletins_paie', r => r.fulfill({ json: [] }));
    await page.route('**/rest/v1/rpc/fn_lister_copies_bulletins', r => r.fulfill({ json: [] }));
    await page.route('**/rest/v1/rpc/fn_obligations_financieres', r => r.fulfill({ json: {
      total_du: 0, total_soignants_du: 0, total_commissions_du: 0, nb_missions_non_payees: 0,
      factures_impayees: [], missions_non_payees: [], missions_non_facturees: [], paiements_soignants_en_attente: [], factures_commission_historique: [],
      paiements_soignants_confirmes: [
        { paiement_id: '71000000-0000-4000-8000-000000000091', mission_id: ids.mission, mission_intitule: state.mission.intitule, soignant_nom: 'Camille Recette', montant_net: 640, confirme_par_soignant_le: '2026-09-30', reference_virement: 'VIR-640', facture_honoraires_id: state.facture.id },
        { paiement_id: '71000000-0000-4000-8000-000000000092', mission_id: ids.mission, mission_intitule: 'Ancien paiement sans pièce', soignant_nom: 'Camille Recette', montant_net: 80, confirme_par_soignant_le: '2026-09-20', reference_virement: 'VIR-80', facture_honoraires_id: null },
      ],
    } }));
    await page.goto(role === 'SOIGNANT' ? '/soignant/mes-gains?tab=factures' : '/etablissement/facturation?tab=historique');
    const entree = role === 'SOIGNANT' ? page.getByRole('button', { name: /^(Erreur|Signaler une erreur)$/ }) : page.getByRole('button', { name: 'Contester la facture payée', exact: true });
    await expect(entree).toHaveCount(1); await action(page, entree);
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('alert')).toContainText('Impossible de vérifier la facture concernée');
    await expect(dialog.getByRole('button', { name: 'Suivant', exact: true })).toBeDisabled(); expect(calls).toEqual([]);
    await expect(dialog).toHaveCSS('opacity', '1');
    await page.screenshot({ path: info.outputPath('lecture-indisponible.png'), scale: 'css', animations: 'disabled' });
    lectureDisponible = true;
    await action(page, dialog.getByRole('button', { name: 'Réessayer le chargement des factures' }));
    await expect(dialog.getByLabel('Facture concernée')).toHaveValue(state.facture.id);
    await expect(dialog.getByLabel('Facture concernée')).toBeDisabled();
    await action(page, dialog.getByRole('button', { name: 'Suivant', exact: true }));
    const detail = 'Le montant de cette facture payée doit être vérifié.';
    await dialog.getByLabel('Décrivez précisément le problème').fill(detail);
    await action(page, dialog.getByRole('button', { name: 'Suivant', exact: true }));
    await expect(dialog.getByText(state.facture.numero_facture, { exact: true })).toBeVisible();
    const envoyer = dialog.getByRole('button', { name: "Confirmer l'ouverture du litige" });
    await action(page, envoyer);
    await expect(dialog.getByRole('alert')).toHaveText('La création du litige n’a pas pu être confirmée. Réessayez.');
    await expect(page.getByText('Litige ouvert. Vous pouvez suivre son traitement dans l’app.', { exact: true })).toHaveCount(0);
    await action(page, envoyer);
    await expect(dialog.getByRole('alert')).toHaveText('La fenêtre de contestation de cette facture est fermée. Contactez le support.');
    await page.screenshot({ path: info.outputPath('refus-serveur.png'), scale: 'css', animations: 'disabled' });
    await action(page, dialog.getByRole('button', { name: 'Précédent' }));
    await expect(dialog.getByLabel('Décrivez précisément le problème')).toHaveValue(detail);
    await action(page, dialog.getByRole('button', { name: 'Suivant', exact: true }));
    await action(page, envoyer); await expect(dialog).toBeHidden();
    expect(ouvert).toBe(true); expect(calls).toHaveLength(3);
    for (const body of calls) expect(body).toEqual({ p_mission_id: ids.mission, p_type_litige: 'DESACCORD_MONTANT_FACTURE', p_motif: `[PAIEMENT] ${detail}`, p_facture_id: state.facture.id });
    await stabiliserActionsNationales(page); await page.reload();
    const resultat = role === 'SOIGNANT' ? page.getByText('Correction en cours', { exact: true }) : page.getByText('VIR-640', { exact: true }).filter({ visible: true });
    await expect(resultat).toBeVisible(); await resultat.scrollIntoViewIfNeeded();
    expect(calls).toHaveLength(3);
    await page.screenshot({ path: info.outputPath('apres-rechargement.png'), scale: 'css', animations: 'disabled' });
    expect(errors).toEqual([]); expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]); expect(state.emails).toEqual([]); expect(state.sms).toEqual([]);
    await info.attach('requetes-simulees', { body: JSON.stringify({ role, calls, errors }), contentType: 'application/json' });
  });
}

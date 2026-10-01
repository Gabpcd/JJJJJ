import { expect, test, type Page, type Locator, type TestInfo } from '@playwright/test';
import { simulerEtablissement, ids as adminIds, stabiliserLectures } from './helpers/recette-complete-etablissement';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales as stabiliserActions } from './helpers/recette-complete-actions-nationales';

// Contrat frontend seulement : aucune SQL, émission documentaire ou opération
// fournisseur. Les deux résultats sont des constantes indépendantes du SQL.
const cas = [
  { taux: 18, periode: 72, global: 144, commissionHt: 21.6, commissionTtc: 25.92 },
  { taux: 22, periode: 88, global: 176, commissionHt: 26.4, commissionTtc: 31.68 },
];
const factureId = '71000000-0000-4000-8000-000000000081';
const remplacementId = '71000000-0000-4000-8000-000000000082';
const litigeId = '71000000-0000-4000-8000-000000000090';
const observations = new Map<TestInfo, unknown>();
test.afterEach(async ({}, info) => {
  await info.attach('transport-local', { body: JSON.stringify(observations.get(info), null, 2), contentType: 'application/json' });
  observations.delete(info);
});
const lectures = new Set([
  'fn_get_my_role', 'fn_compte_auth_actif', 'fn_admin_mes_acces', 'fn_litiges_historique_similaires',
  'fn_admin_solde_correction_facture_honoraires', 'fn_mon_profil_soignant_complet', 'fn_mon_etablissement_complet',
  'fn_etablissement_public', 'fn_etablissement_pour_mission', 'fn_etablissements_safe', 'fn_soignant_pour_etablissement',
  'fn_messages_non_lus', 'fn_mes_permissions_etab', 'fn_litige_pour_mission', 'fn_presences_detail_mission',
  'fn_suivi_escrow_mission', 'fn_lister_copies_bulletins', 'fn_note_moyenne', 'fn_mode_exercice', 'fn_param_bool',
  'fn_onboarding_soignant_statut', 'fn_alerte_cddu_repetitif', 'fn_etat_pointage_mission', 'fn_mode_paiement_mission',
  'fn_score_etab_public', 'fn_est_bloque', 'fn_interlocuteurs_conversations', 'fn_user_id_pour_etablissement',
]);

async function preuve(page: Page, info: TestInfo, nom: string) {
  await info.attach(nom, { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath(nom + '.png'), animations: 'disabled', scale: 'css' });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
}

for (const scenario of cas) {
  test(`Remplacement commission F1 taux ${scenario.taux} : décision admin et montants des parties après recharge`, async ({ page, browser }, info) => {
    const activer = (element: Locator) => info.project.use.hasTouch ? element.tap() : element.click();
    const demandes: unknown[] = [], inertes: string[] = [], interdits: string[] = [], erreurs: string[] = [];
    const surveiller = (p: Page) => {
      p.on('console', m => { if (m.type() === 'error') erreurs.push(m.text()); });
      p.on('pageerror', e => erreurs.push(e.message));
    };
    surveiller(page);
    const original: any = { id: factureId, numero_facture: 'SIM-F1-ORIGINALE', mission_id: ids.mission,
      soignant_id: ids.soignant, etablissement_id: ids.etablissement, statut: 'EMISE', type_document: 'FACTURE',
      nature_correction: 'ORIGINALE', montant_ht: 80, montant_tva: 0, montant_ttc: 80, taux_tva: 0,
      quantite_heures_snapshot: 4, taux_horaire_snapshot: 20, periode_debut: '2026-09-21', periode_fin: '2026-09-27',
      est_facture_finale_mission: false, numero_semaine_iso: 39, annee_iso: 2026, date_emission: '2026-09-30',
      date_echeance: '2026-10-30', exoneration_tva: true };
    const remplacement: any = { ...original, id: remplacementId, numero_facture: 'SIM-F1-REMPLACEMENT',
      facture_precedente_id: factureId, nature_correction: 'REMPLACEMENT', montant_ht: scenario.periode,
      montant_ttc: scenario.periode, taux_horaire_snapshot: scenario.taux };
    const { state, installer } = creerSuiviSimule();
    Object.assign(state.mission, { statut: 'EN_COURS', type_contrat_applique: 'LIBERAL', type_contrat_recherche: 'LIBERAL',
      soignant_assigne_id: ids.soignant, profession_requise: 'IDE', intitule: 'Mission fictive F1 — rectification',
      debut_le: '2026-09-21T08:00:00Z', fin_le: '2026-10-04T12:00:00Z', nb_creneaux: 2, duree_heures: 8,
      taux_horaire_base: 20, total_brut: 160, net_a_payer: 160, net_estime: 160,
      montant_commission_ht: 24, montant_commission_tva: 4.8, montant_commission_ttc: 28.8, taux_commission: 15 });
    Object.assign(state.soignant, { profession: 'IDE', est_compte_test: true });
    Object.assign(state.etablissement, { est_compte_test: true, taux_commission_negocie: 15 });
    state.creneaux.splice(0, state.creneaux.length,
      { id: 'prev-1', mission_id: ids.mission, debut: '2026-09-21T08:00:00Z', fin: '2026-09-21T12:00:00Z', type_creneau: 'PREVISIONNEL', est_pause: false },
      { id: 'prev-2', mission_id: ids.mission, debut: '2026-10-04T08:00:00Z', fin: '2026-10-04T12:00:00Z', type_creneau: 'PREVISIONNEL', est_pause: false },
      { id: 'eff-1', mission_id: ids.mission, debut: '2026-09-21T08:00:00Z', fin: '2026-09-21T12:00:00Z', type_creneau: 'EFFECTIF', est_pause: false });
    const litige: any = { id: litigeId, motif: 'Rectification fictive du taux de la première période', statut: 'REVUE_ADMIN',
      cree_le: '2026-09-30T12:00:00Z', soignant_id: ids.soignant, etablissement_id: ids.etablissement,
      mission_id: ids.mission, initie_par: 'SOIGNANT', type_litige: 'DESACCORD_MONTANT_FACTURE', facture_id: factureId,
      accord_soignant: false, accord_etablissement: false, payload_modifications: null,
      missions: state.mission, soignants: state.soignant, etablissements: state.etablissement };
    const { etat } = await simulerEtablissement(page);
    observations.set(info, { demandes, inertes, interdits, erreurs, inconnuesAdmin: etat.inconnues,
      appelsAdmin: etat.appels, inconnuesParties: state.unknown, appelsParties: state.calls });
    etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
    etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
    etat.overrides.set('messages_litige', []); etat.overrides.set('fn_litiges_historique_similaires', []);
    etat.overrides.set('litiges', [litige]);
    etat.overrides.set('factures_honoraires', original);
    etat.overrides.set('fn_admin_solde_correction_facture_honoraires', { success: true, facture_id: factureId,
      montant_ht: 80, montant_tva: 0, montant_ttc: 80, a_des_corrections: false });
    await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-30T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
      expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    })), { id: adminIds.user });
    let expirations = 0, resolution = 0;
    async function fermerReseau(p: Page, role: string) {
      // Static vendor resources receive inert local content. No connection is
      // forwarded and no console error is filtered out of the assertions.
      await p.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
      await p.route('https://js.stripe.com/**', route => route.fulfill({ contentType: 'application/javascript', body: 'window.Stripe = function(){ return {}; };' }));
      await p.route('**/functions/v1/**', async route => {
        const req = route.request(), url = new URL(req.url());
        if (role === 'ADMIN_PLATEFORME' && ['127.0.0.1', 'localhost'].includes(url.hostname)
          && url.pathname === '/functions/v1/expire-invoice-checkout-for-dispute' && req.method() === 'POST') {
          expect(req.postDataJSON()).toEqual({ litige_id: litigeId });
          expect(req.headers().authorization).toBe('Bearer simulation-admin');
          expirations++;
          return route.fulfill({ json: { success: true, expired: false, reason: 'NO_CHECKOUT_SESSION', simulated: true } });
        }
        interdits.push(req.method() + ' ' + url.pathname); return route.abort();
      });
      await p.route('**/storage/v1/**', async route => { interdits.push(route.request().url()); return route.abort(); });
      await p.route('**/rest/v1/**', async route => {
        const req = route.request(), url = new URL(req.url()), nom = url.pathname.split('/').at(-1)!;
        const rpc = url.pathname.startsWith('/rest/v1/rpc/');
        if (!['127.0.0.1', 'localhost'].includes(url.hostname)) { interdits.push(url.href); return route.abort(); }
        if (rpc && nom === 'fn_admin_resoudre_litige_intelligent' && role === 'ADMIN_PLATEFORME') {
          expect(req.method()).toBe('POST'); expect(expirations).toBe(1); expect(resolution).toBe(0);
          expect(req.postDataJSON()).toEqual({ p_litige_id: litigeId, p_resolution: 'Décision fictive de correction du taux.',
            p_en_faveur_de: 'NEUTRE', p_ajuster_heures: 4, p_ajuster_taux: scenario.taux, p_action_financiere: 'ANNULER_REEMETTRE' });
          demandes.push(req.postDataJSON()); resolution++;
          // Publication explicite du résultat simulé ; aucun moteur SQL recopié.
          original.statut = 'REMPLACEE'; litige.statut = 'RESOLU_ADMIN'; state.facture = remplacement;
          Object.assign(state.mission, { taux_horaire_base: scenario.taux, total_brut: scenario.global,
            net_a_payer: scenario.global, net_estime: scenario.global, montant_commission_ht: scenario.commissionHt,
            montant_commission_tva: Number((scenario.commissionTtc - scenario.commissionHt).toFixed(2)),
            montant_commission_ttc: scenario.commissionTtc, commission_a_recalculer: false });
          return route.fulfill({ json: { success: true, action_financiere: 'ANNULER_REEMETTRE', nouvelle_facture_id: remplacementId,
            heures_final: 4, taux_final: scenario.taux, montant_final_ttc: scenario.periode, simulated: true } });
        }
        if (rpc && ['fn_update_presence', 'fn_obtenir_conversation', 'fn_marquer_messages_lus'].includes(nom)) {
          expect(req.method()).toBe('POST'); inertes.push(role + ':' + nom);
          return route.fulfill({ json: nom === 'fn_obtenir_conversation' ? '71000000-0000-4000-8000-000000000007' : null });
        }
        if (rpc ? req.method() !== 'POST' || !lectures.has(nom) : !['GET', 'HEAD'].includes(req.method())) {
          interdits.push(req.method() + ' ' + nom); return route.abort();
        }
        if (nom === 'factures_honoraires' && role !== 'ADMIN_PLATEFORME') return route.fulfill({ json: [original, remplacement] });
        return route.fallback();
      });
    }
    await fermerReseau(page, 'ADMIN_PLATEFORME');
    await page.goto(`/admin/litiges?litige=${litigeId}`);
    await expect(page.getByRole('heading', { name: 'Litiges — Supervision admin' })).toBeVisible();
    await activer(page.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true }));
    const dialog = page.getByRole('dialog', { name: 'Résoudre le litige', exact: true });
    await expect(dialog.getByText(original.numero_facture, { exact: false }).first()).toBeVisible();
    await dialog.getByRole('textbox', { name: 'Résolution', exact: true }).fill('Décision fictive de correction du taux.');
    await activer(dialog.getByRole('combobox', { name: 'En faveur de' }));
    await activer(page.getByRole('option', { name: 'Neutre', exact: true }));
    await dialog.getByRole('spinbutton', { name: 'Ajuster le taux', exact: true }).fill(String(scenario.taux));
    await activer(dialog.getByRole('combobox', { name: 'Action financière', exact: true }));
    await activer(page.getByRole('option', { name: 'Annuler + réémettre', exact: true }));
    await expect(dialog.getByTestId('preview-resolution')).toContainText('ANNULER + réémettre');
    await preuve(page, info, 'admin-avant-resolution');
    await activer(dialog.getByRole('button', { name: 'Valider la résolution', exact: true }));
    await expect(dialog.getByRole('status')).toHaveText('Litige résolu avec succès.');
    await expect(dialog.getByTestId('result-json')).toContainText(remplacementId);
    expect(resolution).toBe(1); expect(expirations).toBe(1);
    await preuve(page, info, 'admin-apres-resolution');
    await activer(dialog.getByRole('button', { name: 'Fermer', exact: true }).first());
    await stabiliserLectures(page); await page.reload();
    await activer(page.getByRole('button', { name: /^Résolus 1$/ }));
    await expect(page.locator(`[data-litige-id="${litigeId}"]`)).toHaveAttribute('data-statut', 'RESOLU_ADMIN');
    await preuve(page, info, 'admin-apres-recharge');
    expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
    const use: typeof info.project.use & { screen?: { width: number; height: number } } = info.project.use;
    for (const role of ['ADMIN_ETABLISSEMENT', 'SOIGNANT'] as const) {
      const ctx = await browser.newContext({ viewport: use.viewport, screen: use.screen, deviceScaleFactor: use.deviceScaleFactor,
        isMobile: use.isMobile, hasTouch: use.hasTouch, userAgent: use.userAgent,
        locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block' });
      try {
        await installer(ctx, role); const partie = await ctx.newPage(); surveiller(partie); await fermerReseau(partie, role);
        await partie.goto(`/${role === 'SOIGNANT' ? 'soignant' : 'etablissement'}/missions/${ids.mission}`);
        for (const recharge of [false, true]) {
          if (recharge) { await stabiliserActions(partie); await partie.reload(); }
          await expect(partie.getByText(state.mission.intitule, { exact: true }).first()).toBeVisible();
          const titre = role === 'SOIGNANT' ? 'Vos documents d’honoraires pour cette mission' : 'Documents d’honoraires du soignant';
          const card = partie.locator('.card-base').filter({ has: partie.getByRole('heading', { name: titre, exact: true }) });
          await expect(card).toBeVisible();
          await expect(card.getByText('Remplacée', { exact: true })).toBeVisible();
          await expect(card.getByText(original.numero_facture, { exact: true })).toBeVisible();
          await expect(card.getByText(remplacement.numero_facture, { exact: true })).toBeVisible();
          await expect(card.getByText('Net facturé', { exact: true }).locator('..')).toContainText(`${scenario.periode},00`);
          await expect(partie.getByText(new RegExp(`${scenario.global}[,.]00`)).first()).toBeVisible();
          if (role === 'ADMIN_ETABLISSEMENT') {
            await expect(partie.getByText(`${scenario.commissionHt.toFixed(2).replace('.', ',')} € HT + TVA 20 %`, { exact: true })).toBeVisible();
            await expect(partie.getByText(`${scenario.commissionTtc.toFixed(2).replace('.', ',')} € TTC`, { exact: true })).toBeVisible();
          }
          await card.scrollIntoViewIfNeeded();
          await preuve(partie, info, `${role.toLowerCase()}-${recharge ? 'recharge' : 'initial'}`);
        }
        await stabiliserActions(partie);
      } finally { await ctx.close(); }
    }
    expect(state.mission.statut).toBe('EN_COURS'); expect(state.mission.duree_heures).toBe(8);
    expect(state.mission.net_a_payer).toBe(scenario.global);
    expect((state.mission as any).montant_commission_ht).toBe(scenario.commissionHt);
    expect(state.unknown).toEqual([]); expect(state.external).toEqual([]); expect(state.errors).toEqual([]);
    expect(state.signatures).toEqual([]); expect(state.emails).toEqual([]); expect(state.sms).toEqual([]);
    expect(interdits).toEqual([]); expect(erreurs).toEqual([]); expect(resolution).toBe(1); expect(expirations).toBe(1);
    await info.attach('frontiere-simulation', { body: JSON.stringify({ scenario, demandes, inertes, interdits,
      expirationCheckout: 'Réponse inerte NO_CHECKOUT_SESSION ; aucun appel Stripe', mission: state.mission,
      factures: [original, remplacement], cloud: false, sqlExecute: false, documentsGeneres: false }, null, 2), contentType: 'application/json' });
  });
}

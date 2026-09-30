import { test, expect } from '@playwright/test';
import { creerMissionSimulee, ids, now, preuveMission } from './helpers/recette-complete-mission';

// Simulation UI uniquement : les factures ci-dessous sont des réponses fictives.
// Le trigger PostgreSQL est exercé séparément par factures-numerotation-series.test.sql.
for (const role of ['ADMIN_ETABLISSEMENT', 'SOIGNANT'] as const) {
  test(`factures ${role} : consultation, reprise et rechargement`, async ({ context, page }, info) => {
    const simulation = creerMissionSimulee();
    const { state } = simulation;
    state.mission.statut = 'TERMINEE';
    state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = 'LIBERAL';
    state.presence = { valide_par_etablissement: true };
    simulation.simulerEmissionFacture();
    state.facture.numero_facture = 'JOL-71000000-2026-00001';
    await simulation.installer(context, role);
    // CSS de police vide simulé localement ; aucun appel au fournisseur.
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({
      status: 200, contentType: 'text/css', body: '',
    }));
    await context.route('https://js.stripe.com/**', route => route.fulfill({
      contentType: 'application/javascript',
      body: 'window.Stripe = function(){ return {}; }; window.Stripe.version = "clover";',
    }));
    // Banc sans PWA : aucune inscription SW ni push, aucun warning filtré.
    await context.addInitScript(() => {
      if (!Reflect.deleteProperty(Object.getPrototypeOf(navigator), 'serviceWorker') || 'serviceWorker' in navigator) {
        throw new Error('Capacité ServiceWorker encore présente dans le banc simulé');
      }
    });
    await page.clock.setFixedTime(new Date(now));
    const consoleMessages: { type: string; text: string }[] = [];
    page.on('console', message => {
      if (['error', 'warning'].includes(message.type())) consoleMessages.push({ type: message.type(), text: message.text() });
    });
    const commissions = ['H', 'HC', 'HR'].map((serie, i) => ({
      facture_id: `a9305902-0000-4000-8000-00000000000${i + 2}`,
      numero_facture: `JOL-2026-${serie}-A93059020${i + 1}`,
      statut: 'EMISE', montant_ht: 10, montant_tva: 2, montant_ttc: 12,
      nombre_missions: 1, date_echeance: '2026-10-24', est_secteur_public: false,
    }));
    let indisponible = true;
    let lectures = 0;
    await context.route('**/rest/v1/rpc/fn_obligations_financieres', async route => {
      if (route.request().method() === 'OPTIONS') return route.fallback();
      lectures += 1;
      await route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*' },
        json: indisponible ? { error: 'Lecture des factures indisponible dans cette simulation.' } : {
          total_du: 36, total_soignants_du: 0, total_commissions_du: 36,
          nb_missions_non_payees: 0, factures_impayees: commissions,
          paiements_soignants_en_attente: [], paiements_soignants_confirmes: [],
          factures_commission_historique: [], missions_non_facturees: [], missions_non_payees: [],
        } });
    });
    try {
      if (role === 'ADMIN_ETABLISSEMENT') {
        await page.goto('/etablissement/facturation?tab=commissions');
        await expect(page.getByRole('heading', { name: 'Facturation indisponible', exact: true })).toBeVisible();
        await expect(page.getByRole('alert')).toContainText('Impossible de charger les données de facturation en toute sécurité.');
        for (const facture of commissions) await expect(page.getByText(facture.numero_facture, { exact: true })).toHaveCount(0);
        await preuveMission(page, info, 'commission-erreur-lecture');
        const avantReprise = lectures;
        indisponible = false;
        await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
        for (const facture of commissions) await expect(page.getByText(facture.numero_facture, { exact: true })).toBeVisible();
        expect(lectures).toBe(avantReprise + 1);
        await page.getByRole('button', { name: 'Commissions Jolene (3)', exact: true }).click();
        await expect(page.getByText(commissions[0].numero_facture, { exact: true })).toBeHidden();
        await page.getByRole('button', { name: 'Commissions Jolene (3)', exact: true }).click();
      } else {
        await page.goto('/soignant/mes-gains?tab=factures');
        await expect(page.getByText(state.facture.numero_facture, { exact: true })).toBeVisible();
        await page.getByRole('tab', { name: 'Aperçu', exact: true }).click();
        await page.getByRole('tab', { name: 'Factures', exact: true }).click();
        await expect(page.getByText(state.facture.numero_facture, { exact: true })).toBeVisible();
      }
      await page.waitForLoadState('networkidle');
      await page.reload();
      for (const numero of role === 'ADMIN_ETABLISSEMENT' ? commissions.map(f => f.numero_facture) : [state.facture.numero_facture]) {
        await expect(page.getByText(numero, { exact: true })).toBeVisible();
      }
      await preuveMission(page, info, 'factures-apres-rechargement');
      expect(state.unknown).toEqual([]);
      expect(state.external).toEqual([]);
      expect(state.errors).toEqual([]);
      // Conserver et vérifier aussi l'erreur volontaire : aucune exclusion de log.
      expect(consoleMessages).toEqual(role === 'ADMIN_ETABLISSEMENT' ? [{
        type: 'error', text: '[ERROR] Facturation charger error Obligations financières: Lecture des factures indisponible dans cette simulation.',
      }] : []);
      expect(state.emails).toEqual([]);
    } finally {
      await info.attach('journal-simulation', { contentType: 'application/json', body: JSON.stringify({
        simulation: true, role, lectures, consoleMessages, pageErrors: state.errors,
        unknown: state.unknown, external: state.external,
      }, null, 2) });
    }
  });
}

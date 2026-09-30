import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Simulation stricte : aucune RPC ni résolution financière distante.
for (const contrat of ['SALARIE', 'LIBERAL']) {
  test(`admin ${contrat} — refus uniforme, réessai et reprise du dossier`, async ({ page }, info) => {
    const { etat } = await simulerEtablissement(page);
    etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
    etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
    etat.overrides.set('messages_litige', []);
    etat.overrides.set('fn_litiges_historique_similaires', []);
    const litigeId = '79000000-0000-4000-8000-000000000093';
    const litige = {
      id: litigeId, motif: `Contestations fictives ${contrat}`, statut: 'REVUE_ADMIN',
      cree_le: '2026-09-28T12:00:00Z', soignant_id: ids.soignant, etablissement_id: ids.etab,
      mission_id: ids.mission, initie_par: 'SYSTEME', type_litige: 'AUTRE', facture_id: null,
      accord_soignant: false, accord_etablissement: false, payload_modifications: null,
      missions: { id: ids.mission, intitule: `Mission fictive ${contrat}`, debut_le: '2026-10-01T07:00:00Z', type_contrat_applique: contrat, statut: 'TERMINEE', duree_heures: 8, taux_horaire_base_fige: 30, taux_horaire_base: 30 },
      soignants: { id: ids.soignant, prenom: 'Camille', nom: 'Recette', profession: 'IDE' },
      etablissements: { id: ids.etab, nom: 'Établissement fictif' },
    };
    etat.overrides.set('litiges', [litige]);
    let appels = 0;
    let autorise = false;
    await page.route('**/rest/v1/rpc/fn_admin_resoudre_litige_intelligent', async route => {
      const payload = route.request().postDataJSON();
      expect(payload).toMatchObject({ p_litige_id: litigeId, p_en_faveur_de: 'NEUTRE', p_action_financiere: 'AUTO' });
      expect(payload.p_ajuster_heures).toBeUndefined();
      expect(payload.p_ajuster_taux).toBeUndefined();
      appels++;
      if (autorise) litige.statut = 'RESOLU_ADMIN';
      await route.fulfill({ json: autorise
        ? { success: true, statut: 'RESOLU_ADMIN', action_financiere: 'AUCUNE' }
        : { success: false, error: 'Administrateur requis.' } });
    });
    await page.addInitScript(({ id }) => {
      sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
        user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-28T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
        access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
        expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
      }));
    }, { id: ids.user });
    await page.goto(`/admin/litiges?litige=${litigeId}`);
    await expect(page.getByRole('heading', { name: 'Litiges — Supervision admin' })).toBeVisible();
    await page.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: 'Résoudre le litige' })).toBeVisible();
    await expect(dialog.getByTestId('action-paie-salariee')).toHaveCount(contrat === 'SALARIE' ? 1 : 0);
    await dialog.getByRole('textbox', { name: 'Résolution', exact: true }).fill('Décision fictive sans changement financier.');
    await dialog.getByRole('combobox', { name: 'En faveur de' }).click();
    await page.getByRole('option', { name: 'Neutre', exact: true }).click();
    const valider = dialog.getByRole('button', { name: 'Valider la résolution', exact: true });
    await valider.click();
    await expect(page.getByText('Administrateur requis.', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('Litige résolu avec succès.', { exact: true })).toHaveCount(0);
    await expect(valider).toBeEnabled();
    expect(appels).toBe(1);
    await preuve(page, `refus-${contrat.toLowerCase()}`, info);
    // Aucun réessai automatique : la décision reste dans le formulaire.
    await expect(dialog.getByRole('textbox', { name: 'Résolution', exact: true })).toHaveValue('Décision fictive sans changement financier.');
    autorise = true;
    await valider.click();
    await expect(page.getByText('Litige résolu avec succès.', { exact: true })).toBeVisible();
    expect(appels).toBe(2);
    await dialog.getByRole('button', { name: 'Fermer', exact: true }).first().click();
    await page.reload();
    await page.getByRole('button', { name: /^Résolus 1$/ }).click();
    await expect(page.locator(`[data-litige-id="${litigeId}"]`)).toHaveAttribute('data-statut', 'RESOLU_ADMIN');
    expect(appels).toBe(2);
    await stabiliserLectures(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
    expect(etat.inconnues).toEqual([]);
    expect(etat.erreurs).toEqual([]);
    await preuve(page, `reprise-${contrat.toLowerCase()}`, info);
  });
}

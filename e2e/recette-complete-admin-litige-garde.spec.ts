import { expect, test, type Locator } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Simulation stricte : aucune RPC ni résolution financière distante.
for (const contrat of ['SALARIE', 'LIBERAL']) {
  test(`admin ${contrat} — refus uniforme, réessai et reprise du dossier`, async ({ page, isMobile }, info) => {
    const activer = (element: Locator) => isMobile ? element.tap() : element.click();
    const { etat } = await simulerEtablissement(page);
    const erreursConsole: string[] = [];
    page.on('console', message => { if (message.type() === 'error') erreursConsole.push(message.text()); });
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
    const secondId = '79000000-0000-4000-8000-000000000094';
    const secondLitige = { ...litige, id: secondId, motif: `Autre dossier fictif ${contrat}` };
    etat.overrides.set('litiges', [litige, secondLitige]);
    let appels = 0;
    let autorise = false;
    let libererPremierAppel!: () => void;
    const premiereReponse = new Promise<void>(resolve => { libererPremierAppel = resolve; });
    await page.route('**/rest/v1/rpc/fn_admin_resoudre_litige_intelligent', async route => {
      const payload = route.request().postDataJSON();
      expect(payload).toMatchObject({ p_litige_id: litigeId, p_en_faveur_de: 'NEUTRE', p_action_financiere: 'AUTO' });
      expect(payload.p_ajuster_heures).toBeUndefined();
      expect(payload.p_ajuster_taux).toBeUndefined();
      appels++;
      if (appels === 1) await premiereReponse;
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
    await activer(page.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true }));
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: 'Résoudre le litige' })).toBeVisible();
    await expect(dialog.getByTestId('action-paie-salariee')).toHaveCount(contrat === 'SALARIE' ? 1 : 0);
    await dialog.getByRole('textbox', { name: 'Résolution', exact: true }).fill('Décision fictive sans changement financier.');
    await activer(dialog.getByRole('combobox', { name: 'En faveur de' }));
    await activer(page.getByRole('option', { name: 'Neutre', exact: true }));
    const valider = dialog.getByRole('button', { name: 'Valider la résolution', exact: true });
    // Interaction tactile sur mobile ; double clic sur ordinateur pendant la réponse retenue.
    // Le verrou est aussi testé par deux événements synchrones dans le test du composant.
    if (isMobile) await valider.tap();
    else await valider.dblclick();
    await expect.poll(() => appels).toBe(1);
    await expect(dialog.getByRole('button', { name: 'Résolution…', exact: true })).toBeDisabled();
    await expect(dialog.getByRole('button', { name: 'Fermer', exact: true }).first()).toBeDisabled();
    await page.keyboard.press('Escape');
    await expect(dialog).toBeVisible();
    libererPremierAppel();
    const refus = dialog.getByRole('alert');
    await expect(refus).toHaveText('Administrateur requis.');
    await expect(refus).toBeFocused();
    await expect(valider).toHaveAccessibleDescription('Administrateur requis.');
    await expect(page.locator('[data-sonner-toast]')).toHaveCount(0);
    // Le retour occupe sa place dans le flux, au-dessus du bouton, sans le recouvrir.
    const zoneRefus = await refus.boundingBox();
    const zoneBouton = await valider.boundingBox();
    expect(zoneRefus).not.toBeNull();
    expect(zoneBouton).not.toBeNull();
    expect(zoneRefus!.y + zoneRefus!.height).toBeLessThanOrEqual(zoneBouton!.y);
    await expect(refus).toBeInViewport();
    await expect(valider).toBeInViewport();
    await page.screenshot({ path: info.outputPath(`refus-inline-${contrat.toLowerCase()}.png`) });
    await expect(page.getByText('Litige résolu avec succès.', { exact: true })).toHaveCount(0);
    await expect(valider).toBeEnabled();
    expect(appels).toBe(1);
    await preuve(page, `refus-${contrat.toLowerCase()}`, info);
    // Réessai dès le refus affiché : aucun sommeil, clic forcé ou attente de disparition d'un toast.
    await expect(dialog.getByRole('textbox', { name: 'Résolution', exact: true })).toHaveValue('Décision fictive sans changement financier.');
    autorise = true;
    await activer(valider);
    await expect(dialog.getByRole('status')).toHaveText('Litige résolu avec succès.');
    await expect(dialog.getByRole('status')).toBeInViewport();
    await expect(valider).toBeInViewport();
    await expect(dialog.getByRole('alert')).toHaveCount(0);
    await expect(valider).toBeDisabled();
    await expect(page.locator('[data-sonner-toast]')).toHaveCount(0);
    expect(appels).toBe(2);
    await preuve(page, `succes-${contrat.toLowerCase()}`, info);
    await page.screenshot({ path: info.outputPath(`succes-inline-${contrat.toLowerCase()}.png`) });
    await activer(dialog.getByRole('button', { name: 'Fermer', exact: true }).first());
    await expect(dialog).toHaveCount(0);
    // Ouvrir un autre dossier puis le rouvrir remet aussi la décision à zéro.
    const secondDossier = page.locator(`[data-litige-id="${secondId}"]`);
    await activer(secondDossier.locator('button[aria-expanded]'));
    await expect(secondDossier.locator('button[aria-expanded]')).toHaveAttribute('aria-expanded', 'true');
    await secondDossier.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true }).scrollIntoViewIfNeeded();
    await activer(secondDossier.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true }));
    const decision = dialog.getByRole('textbox', { name: 'Résolution', exact: true });
    await expect(decision).toHaveValue('');
    await expect(dialog.getByRole('combobox', { name: 'En faveur de' })).toHaveText('Choisir...');
    await expect(dialog.getByRole('alert')).toHaveCount(0);
    await expect(dialog.getByRole('status')).toHaveCount(0);
    await expect(dialog.getByTestId('result-json')).toHaveCount(0);
    await expect(valider).toBeDisabled();
    await decision.fill('Autre décision fictive non envoyée.');
    await dialog.getByRole('spinbutton', { name: 'Ajuster les heures', exact: true }).fill('7');
    await activer(dialog.getByRole('button', { name: 'Fermer', exact: true }).first());
    await expect(dialog).toHaveCount(0);
    await activer(secondDossier.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true }));
    await expect(decision).toHaveValue('');
    await expect(dialog.getByRole('spinbutton', { name: 'Ajuster les heures', exact: true })).toHaveValue('');
    await expect(valider).toBeDisabled();
    await preuve(page, `dossier-reinitialise-${contrat.toLowerCase()}`, info);
    await activer(dialog.getByRole('button', { name: 'Fermer', exact: true }).first());
    await expect(dialog).toHaveCount(0);
    await stabiliserLectures(page);
    await page.reload();
    await activer(page.getByRole('button', { name: /^Résolus 1$/ }));
    await expect(page.locator(`[data-litige-id="${litigeId}"]`)).toHaveAttribute('data-statut', 'RESOLU_ADMIN');
    expect(appels).toBe(2);
    await stabiliserLectures(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
    expect(etat.inconnues).toEqual([]);
    expect(etat.erreurs).toEqual([]);
    expect(erreursConsole).toEqual([]);
    await preuve(page, `reprise-${contrat.toLowerCase()}`, info);
  });
}

import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { simulerEtablissement, ids as idsAdmin, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Routes réellement montées, API strictement simulée : aucun paiement ni relance réelle.
const salaire = "En salarié, le salaire est versé par l'établissement employeur.";
const liberal = 'En libéral, le paiement suit les modalités de la mission.';
const ancienPaiement = /Le paiement (?:est débloqué|se débloque)/;

async function preuve(page: Page, zone: Locator, info: TestInfo, nom: string) {
  await zone.scrollIntoViewIfNeeded();
  await expect(zone).toBeInViewport();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
  await info.attach(`${nom}-texte`, { body: await zone.innerText(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath(`${nom}.png`), animations: 'disabled' });
}

for (const regime of ['SALARIE', 'LIBERAL'] as const) {
  test(`présences ${regime} — historique, détail, relance et reprise distinguent heures et versement`, async ({ context, page }, info) => {
    const { state, installer } = creerSuiviSimule();
    state.mission.statut = 'TERMINEE';
    state.mission.soignant_assigne_id = ids.soignant;
    state.mission.type_contrat_applique = regime;
    state.mission.type_contrat_recherche = regime;
    state.soignant.type_exercice = regime;
    state.creneaux.push({ id: 'segment-coherence', mission_id: ids.mission,
      debut: state.mission.debut_le, fin: state.mission.fin_le, est_pause: false, type_creneau: 'EFFECTIF' });
    state.presence = { id: ids.presence, mission_id: ids.mission, soignant_id: ids.soignant,
      pointage_arrivee_le: state.mission.debut_le, pointage_depart_le: state.mission.fin_le,
      cree_le: state.mission.debut_le, valide_par_etablissement: false,
      methode_pointage_arrivee: 'CODE_ROTATIF', methode_pointage_depart: 'CODE_ROTATIF',
      missions: { ...state.mission, creneaux: state.creneaux, presences: undefined } };
    state.mission.presences = [{ ...state.presence, missions: undefined }];
    await installer(context, 'SOIGNANT');
    await context.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
    await page.clock.setFixedTime(new Date('2026-09-24T18:00:00Z'));
    let relances = 0;
    await context.route('**/rest/v1/rpc/fn_relancer_validation_presence', async route => {
      expect(route.request().postDataJSON()).toEqual({ p_mission_id: ids.mission });
      relances++;
      await route.fulfill({ json: { success: true, message: 'Établissement relancé.' } });
    });

    await page.goto('/soignant/presences?tab=historique&filtre=a_valider');
    await expect(page.getByRole('tab', { name: 'Historique', exact: true })).toHaveAttribute('data-state', 'active');
    const historique = page.getByText("⏳ Présences en attente de validation par l'établissement", { exact: false });
    await expect(historique).toContainText('validation automatique sous 72 h');
    await expect(historique).toContainText('La validation des heures est distincte du versement.');
    await expect(historique).toContainText(salaire);
    await expect(historique).toContainText(liberal);
    await expect(page.getByText(ancienPaiement)).toHaveCount(0);
    await preuve(page, historique, info, `historique-${regime}`);
    await stabiliserActionsNationales(page);
    await page.reload();
    await expect(historique).toContainText(salaire);
    await page.getByRole('button', { name: 'Détail', exact: true }).click();
    await expect(page).toHaveURL(new RegExp(`/soignant/presences/mission/${ids.mission}$`));
    const detail = page.getByText('La validation des heures (automatique sous 72 h)', { exact: false });
    await expect(detail).toContainText('est distincte du versement.');
    await expect(detail).toContainText(salaire);
    await expect(detail).toContainText(liberal);
    await expect(page.getByText(ancienPaiement)).toHaveCount(0);
    await preuve(page, detail.locator('..'), info, `detail-${regime}`);
    await page.getByRole('button', { name: "Relancer l'établissement", exact: true }).click();
    await expect(page.getByText('Établissement relancé.', { exact: true })).toBeVisible();
    expect(relances).toBe(1);
    await stabiliserActionsNationales(page);
    await page.reload();
    await expect(detail).toContainText(liberal);
    await expect(page.getByRole('button', { name: "Relancer l'établissement", exact: true })).toBeEnabled();
    expect(relances).toBe(1);
    await stabiliserActionsNationales(page);
    expect(state.calls.filter(c => /paiement|payer|resoudre|valider_presence/.test(c.name))).toEqual([]);
    expect(state.unknown).toEqual([]);
    expect(state.errors).toEqual([]);
    expect(state.external).toEqual([]);
  });
}

test('admin — la correction salariée annonce une simulation et conserve le formulaire après reprise', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('fn_litiges_historique_similaires', []);
  etat.overrides.set('messages_litige', []);
  const litigeId = '79000000-0000-4000-8000-000000000098';
  etat.overrides.set('litiges', [{ id: litigeId, motif: 'Heures salariées fictives à vérifier', statut: 'REVUE_ADMIN',
    cree_le: '2026-09-28T12:00:00Z', soignant_id: idsAdmin.soignant, etablissement_id: idsAdmin.etab,
    mission_id: idsAdmin.mission, initie_par: 'SOIGNANT', accord_soignant: false, accord_etablissement: false,
    modifications_executees: false, type_litige: 'HEURES',
    missions: { id: idsAdmin.mission, intitule: 'Mission salariée de recette', debut_le: '2026-09-28T07:00:00Z',
      fin_le: '2026-09-28T15:00:00Z', statut: 'TERMINEE', duree_heures: 8, taux_horaire_base: 30, type_contrat_applique: 'SALARIE' },
    soignants: { id: idsAdmin.soignant, prenom: 'Camille', nom: 'Recette', profession: 'IDE' },
    etablissements: { id: idsAdmin.etab, nom: 'Établissement de recette' } }]);
  await page.addInitScript(({ id }) => sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
    user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-28T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
    access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
    expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  })), { id: idsAdmin.user });
  await page.goto(`/admin/litiges?litige=${litigeId}`);
  const ouvrir = page.getByRole('button', { name: 'Résoudre (financier + statut)', exact: true });
  await ouvrir.click();
  const dialog = page.getByRole('dialog', { name: 'Résoudre le litige', exact: true });
  const simulation = dialog.getByTestId('action-paie-salariee');
  await expect(simulation).toContainText('Recalcul automatique de la simulation de paie');
  await expect(dialog.getByText('Rectification de paie automatique', { exact: true })).toHaveCount(0);
  await dialog.getByRole('spinbutton', { name: 'Ajuster les heures', exact: true }).fill('7');
  await expect(simulation).toContainText('Recalcul automatique de la simulation de paie');
  await preuve(page, simulation, info, 'admin-simulation-paie');
  await stabiliserLectures(page);
  await page.reload();
  await page.getByRole('button', { name: 'À trancher 1', exact: true }).click();
  await page.getByText('Mission salariée de recette', { exact: true }).click();
  await ouvrir.click();
  await expect(simulation).toContainText('Recalcul automatique de la simulation de paie');
  expect(etat.appels.filter(c => /fn_admin_.*resoudre|fn_admin_valider_accord|fn_declarer_paiement/.test(c))).toEqual([]);
  expect(etat.inconnues).toEqual([]);
  expect(etat.erreurs).toEqual([]);
});

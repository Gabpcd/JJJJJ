import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { creerSuiviSimule } from './helpers/recette-complete-suivi-mission';
import { ids } from './helpers/recette-complete-mission';
import { stabiliserActionsNationales } from './helpers/recette-complete-actions-nationales';
import { entrer, simulerEtablissement, ids as idsAdmin, mission as missionEtab, stabiliserLectures } from './helpers/recette-complete-etablissement';

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
    await expect(page.getByText('CODE_ROTATIF', { exact: false })).toHaveCount(0);
    await expect(page.getByText('🔢 Code', { exact: true })).toHaveCount(2);
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
    await expect(page.getByText(/NaN|Infinity|Première arrivée : 0m/)).toHaveCount(0);
    await preuve(page, page.getByRole('heading', { name: 'Contrôles du pointage' }).locator('..'), info, `controle-sans-gps-${regime}`);
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


test('établissement — présences sans GPS, alerte connue et mesure zéro restent distinctes après reprise', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  await entrer(page, 'connexion');
  const mission = { ...missionEtab, statut: 'TERMINEE', soignant_assigne_id: idsAdmin.soignant,
    debut_le: '2026-09-24T07:00:00Z', fin_le: '2026-09-24T15:00:00Z', duree_heures: 8 };
  const presence = { id: 'presence-gps-recette', mission_id: idsAdmin.mission, soignant_id: idsAdmin.soignant,
    pointage_arrivee_le: mission.debut_le, pointage_depart_le: mission.fin_le,
    perimetre_gps_valide: null as boolean | null, distance_etablissement_m: null as number | null,
    valide_par_etablissement: false, alerte_teleportation: false, missions: mission };
  etat.overrides.set('presences', [presence]);
  // La mission terminée a bien un pointage : l'absence de GPS ne doit pas créer une fausse absence.
  etat.overrides.set('missions', [mission]);
  etat.overrides.set('fn_mes_soignants_etablissement', [{ id: idsAdmin.soignant, prenom: 'Camille', nom: 'GPS Recette', profession: 'IDE' }]);
  const creneaux = ['PREVISIONNEL', 'EFFECTIF'].map((type_creneau, index) => ({
    id: `gps-creneau-${index}`, mission_id: idsAdmin.mission, debut: mission.debut_le, fin: mission.fin_le, est_pause: false, type_creneau }));
  let lecturesCreneaux = 0;
  await page.route('**/rest/v1/mission_creneaux?*', async route => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: {
      'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET, OPTIONS',
    } });
    expect(route.request().method()).toBe('GET');
    expect(new URL(route.request().url()).searchParams.get('mission_id')).toBe(`in.(${idsAdmin.mission})`);
    lecturesCreneaux++;
    etat.appels.push('GET mission_creneaux');
    // Le lecteur paginé exige le count exact de PostgREST, même pour une seule mission.
    await route.fulfill({ json: creneaux, headers: {
      'content-range': '0-1/2', 'access-control-expose-headers': 'content-range', 'access-control-allow-origin': '*',
    } });
  });

  const mobile = page.viewportSize()!.width < 768;
  const panneau = page.getByRole('tabpanel');
  const surface = mobile
    ? panneau.getByRole('listitem').filter({ hasText: 'Camille GPS Recette · IDE' })
    : panneau.getByRole('row').filter({ hasText: 'Camille GPS Recette' });
  const lot = page.getByRole('button', { name: /Tout valider \(sans alerte\)/ });
  const alertes = page.getByRole('tab', { name: /Alertes:/ });
  const aValider = page.getByRole('tab', { name: 'À valider: 1 présences', exact: true });
  async function verifierMontage() {
    await expect(surface).toBeVisible();
    await stabiliserLectures(page);
    await expect(aValider).toBeVisible();
    await expect(page.getByRole('tab', { name: 'En cours: 0 présences', exact: true })).toBeVisible();
    if (mobile) {
      await expect(surface.getByRole('heading', { name: 'Camille GPS Recette · IDE', exact: true })).toBeVisible();
      await expect(panneau.getByRole('table')).toHaveCount(0);
    } else {
      await expect(panneau.getByRole('table')).toBeVisible();
      await expect(panneau.getByRole('listitem')).toHaveCount(0);
      await expect(surface.getByRole('button', { name: 'Valider', exact: true })).toBeVisible();
    }
    await expect(page.getByText(/NaN|Infinity|Missions terminées sans pointage/)).toHaveCount(0);
  }
  async function verifierAucuneAlerte() {
    await alertes.click();
    await expect(panneau.getByText('Aucune alerte', { exact: true })).toBeVisible();
    await stabiliserLectures(page);
    await expect(page.getByText('Missions terminées sans pointage', { exact: true })).toHaveCount(0);
    await aValider.click();
    await verifierMontage();
  }

  await page.goto('/etablissement/presences?tab=a_valider');
  await verifierMontage();
  await page.reload();
  await verifierMontage();
  await expect(surface.getByText(/Hors périmètre|Hors zone|Arrivée : 0m/)).toHaveCount(0);
  await expect(alertes).toHaveAccessibleName('Alertes: 0 anomalies');
  await expect(lot).toBeDisabled();
  await preuve(page, surface, info, 'etab-presence-sans-gps');
  await verifierAucuneAlerte();

  presence.perimetre_gps_valide = false;
  await page.reload();
  await verifierMontage();
  await expect(surface.getByText(mobile
    ? "Hors périmètre à l'arrivée (distance indisponible)"
    : 'Hors zone', { exact: true })).toBeVisible();
  await expect(surface.getByText(/Arrivée : 0m/)).toHaveCount(0);
  await expect(alertes).toHaveAccessibleName('Alertes: 1 anomalies');
  await expect(lot).toBeDisabled();
  await alertes.click();
  await verifierMontage();
  await preuve(page, surface, info, 'etab-alerte-sans-distance');
  await aValider.click();
  await verifierMontage();

  presence.perimetre_gps_valide = true; presence.distance_etablissement_m = 0;
  await page.reload();
  await verifierMontage();
  // Seule la carte mobile affiche la distance ; le tableau affiche l'état et l'éligibilité.
  await expect(surface.getByText(mobile ? 'Arrivée : 0m · ✅ OK' : 'À valider', { exact: true })).toBeVisible();
  await expect(surface.getByText(/Hors périmètre|Hors zone/)).toHaveCount(0);
  await expect(alertes).toHaveAccessibleName('Alertes: 0 anomalies');
  await expect(lot).toHaveText('Tout valider (sans alerte) · 1 présences');
  await expect(lot).toBeEnabled();
  await preuve(page, surface, info, 'etab-mesure-zero');
  await verifierAucuneAlerte();
  expect(lecturesCreneaux).toBeGreaterThanOrEqual(4);
  expect(etat.appels.filter(c => /fn_valider_presence|fn_declarer_paiement/.test(c))).toEqual([]);
  expect(etat.ecritures).toEqual([]);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
});

import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { simulerEtablissement, entrer, allerA, stabiliserLectures, preuve } from './helpers/recette-complete-etablissement';

// Vrai frontend et réponses fictives : aucun SQL, aucune publication réelle. Le refus qui fait foi est celui du
// serveur (verrou différé de la migration 20261125120000, prouvé par tests/postgres/taux-horaire-minimum-salarie.pg17.mjs).
// Exécution sur les cinq projets de playwright.recette-complete.config.ts (dont iphone 390 × 844 et ordinateur 1440 × 900).
const maintenant = '2026-11-25T08:00:00.000Z';
const debut = '2026-12-02T07:00:00.000Z';
const fin = '2026-12-02T15:00:00.000Z';
const MESSAGE = "Le taux horaire doit être d'au moins 12,31 €/h.";

async function activer(cible: Locator, info: TestInfo) {
  await cible.scrollIntoViewIfNeeded();
  if (info.project.use.hasTouch) await cible.tap(); else await cible.click();
}

const champTaux = (page: Page) => page.getByLabel(/^Taux horaire (?:brut|proposé)/);
const publier = (page: Page) => page.getByRole('button', { name: /^Publier la mission/ });

test('Taux salarié : 12,30 refusé avec le message exact, après recharge aussi ; 12,31 accepté et publié', async ({ page }, info) => {
  const { etat, parcours } = await simulerEtablissement(page);
  Object.assign(parcours.donnees, { brouillonMission: true, missionFormulaire: {
    intitule: 'AS — taux minimal salarié', profession: 'AS', service: 'Soins',
    description: 'Brouillon fictif repris par le vrai formulaire.', tauxHoraire: '12.30',
    estUrgente: false, modeAttribution: 'CANDIDATURE', contratPreference: 'SALARIE',
    creneaux: [{ debut, fin }],
  } });
  const creations: Record<string, unknown>[] = [];
  await page.clock.setFixedTime(new Date(maintenant));
  await page.route('**/rest/v1/rpc/fn_creer_mission_multi_jours_v4', async route => {
    const requete = route.request();
    expect(['localhost', '127.0.0.1']).toContain(new URL(requete.url()).hostname);
    expect(requete.method()).toBe('POST');
    const corps = requete.postDataJSON();
    creations.push(corps);
    // Même règle que le verrou serveur : refus sous 12,31 €/h pour une mission SALARIE ou TOUS.
    if (corps.p_type_contrat_recherche !== 'LIBERAL' && Number(corps.p_taux_horaire_base) < 12.31) {
      return route.fulfill({ status: 400, json: { code: 'P0001', hint: 'TAUX_HORAIRE_SOUS_MINIMUM_SALARIE', details: null, message: MESSAGE } });
    }
    return route.fulfill({ json: { success: true, mission_id: '79000000-0000-4000-8000-000000000072' } });
  });
  await page.route('**/rest/v1/rpc/fn_calculer_remuneration_mission', route => route.fulfill({ json: {
    total_brut: 98.48, montant_base: 98.48, net_a_payer: 98.48, montant_ifm: 0, montant_icp: 0 } }));

  try {
    await entrer(page, 'connexion');
    await allerA(page, '/etablissement/missions/creer');
    for (const recharge of [false, true]) {
      if (recharge) { await stabiliserLectures(page); await page.reload(); }
      await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('AS — taux minimal salarié');
      await expect(champTaux(page)).toHaveValue('12.30');
      await expect(champTaux(page)).toHaveAttribute('min', '12.31');
      await expect(champTaux(page)).toHaveAttribute('aria-invalid', 'true');
      const alerte = page.locator('#mission-taux-minimum');
      await expect(alerte).toHaveText(MESSAGE);
      await expect(alerte).toHaveAttribute('role', 'alert');
      await expect(champTaux(page)).toHaveAttribute('aria-describedby', 'mission-taux-minimum');
      await expect(publier(page)).toBeDisabled();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(page.getByText(/11[,.]65/)).toHaveCount(0);
      await preuve(page, `taux-minimal-1230-refuse-${recharge ? 'recharge' : 'initial'}`, info);
    }
    expect(creations).toEqual([]);

    await champTaux(page).fill('12.31');
    await expect(champTaux(page)).toHaveValue('12.31');
    await expect(page.locator('#mission-taux-minimum')).toHaveCount(0);
    await expect(page.getByText(MESSAGE, { exact: true })).toHaveCount(0);
    await expect(champTaux(page)).not.toHaveAttribute('aria-invalid', 'true');
    await expect(publier(page)).toBeEnabled();
    await preuve(page, 'taux-minimal-1231-accepte', info);
    await activer(publier(page), info);
    const dialogue = page.getByRole('dialog');
    await expect(dialogue).toBeVisible();
    await expect(dialogue).toContainText('12.31 €/h');
    await preuve(page, 'taux-minimal-1231-recapitulatif', info);
    await activer(dialogue.getByRole('button', { name: /Publier|Confirmer/ }).last(), info);
    await expect.poll(() => creations.length).toBe(1);
    expect(creations[0]).toMatchObject({ p_taux_horaire_base: 12.31, p_type_contrat_recherche: 'SALARIE', p_profession_requise: 'AS' });
    await expect(page).toHaveURL(/\/etablissement\/missions$/);
    expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
  } finally {
    await info.attach('taux-minimal-reponses-fictives', { body: JSON.stringify({
      simulation: true, backendVerified: false, published: false, creations, inconnus: etat.inconnues, erreurs: etat.erreurs,
    }, null, 2), contentType: 'application/json' });
  }
});

test('Taux salarié lu au serveur (paramètre annoncé, 12,50) : 12,40 refusé, 12,50 accepté jusqu’au récapitulatif', async ({ page }, info) => {
  const { etat, parcours } = await simulerEtablissement(page);
  Object.assign(parcours.donnees, { brouillonMission: true, missionFormulaire: {
    intitule: 'AS — plancher relevé', profession: 'AS', service: 'Soins',
    description: 'Brouillon fictif repris par le vrai formulaire.', tauxHoraire: '12.40',
    estUrgente: false, modeAttribution: 'CANDIDATURE', contratPreference: 'SALARIE',
    creneaux: [{ debut, fin }],
  } });
  const annonces: unknown[] = [];
  let lectures = 0;
  await page.clock.setFixedTime(new Date(maintenant));
  // Seule la clé du plancher est annoncée ; tous les autres drapeaux restent fermés comme dans le harnais.
  await page.route('**/rest/v1/rpc/fn_param_bool', async route => {
    const corps = route.request().postDataJSON();
    annonces.push(corps);
    return route.fulfill({ json: corps?.p_cle === 'taux_horaire_minimum_salarie' });
  });
  await page.route('**/rest/v1/rpc/fn_taux_horaire_minimum_salarie', route => { lectures += 1; return route.fulfill({ json: 12.5 }); });
  await page.route('**/rest/v1/rpc/fn_calculer_remuneration_mission', route => route.fulfill({ json: {
    total_brut: 100, montant_base: 100, net_a_payer: 100, montant_ifm: 0, montant_icp: 0 } }));
  const message = "Le taux horaire doit être d'au moins 12,50 €/h.";
  try {
    await entrer(page, 'connexion');
    await allerA(page, '/etablissement/missions/creer');
    await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('AS — plancher relevé');
    await expect(champTaux(page)).toHaveAttribute('min', '12.5');
    await expect(page.locator('#mission-taux-minimum')).toHaveText(message);
    await expect(publier(page)).toBeDisabled();
    await preuve(page, 'taux-minimal-serveur-1240-refuse', info);
    await champTaux(page).fill('12.50');
    await expect(page.locator('#mission-taux-minimum')).toHaveCount(0);
    await expect(publier(page)).toBeEnabled();
    await activer(publier(page), info);
    await expect(page.getByRole('dialog')).toContainText('12.50 €/h');
    await preuve(page, 'taux-minimal-serveur-1250-recapitulatif', info);
    expect(lectures).toBeGreaterThan(0);
    expect(annonces).toContainEqual({ p_cle: 'taux_horaire_minimum_salarie', p_defaut: false });
    expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
  } finally {
    await info.attach('taux-minimal-serveur-reponses-fictives', { body: JSON.stringify({
      simulation: true, backendVerified: false, published: false, minimumServi: 12.5, annonces, lectures,
    }, null, 2), contentType: 'application/json' });
  }
});

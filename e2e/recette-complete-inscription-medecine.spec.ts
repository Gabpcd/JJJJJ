import { expect, test, type Page, type Route } from '@playwright/test';
import { ouvrirDossierDepuisMission, remplirIdentite, simulerCompletionSoignant, verifierRppsSimule } from './helpers/recette-complete-completion-soignant';
import { attendreAPI, ids, mission, preuve, sansDebordement } from './helpers/recette-complete-soignant';

// Formulaire réel, réponses Auth/Annuaire Santé/inscription entièrement simulées.
// Les réponses ne prouvent aucune habilitation médicale ni création de compte distant.
const INTERNAT = 'Médecine — 3e cycle (internat)';
const INDISPONIBLE = 'La vérification des possibilités d’emploi temporaire est indisponible. Votre niveau d’études reste enregistré ; aucune équivalence n’est confirmée.';
type ReponseSimulee = { status?: number; json: unknown; attente?: Promise<void> };

function differer() {
  let liberer!: () => void;
  const attente = new Promise<void>(resolve => { liberer = resolve; });
  return { attente, liberer };
}

async function repondre(route: Route, reponse: ReponseSimulee) {
  if (reponse.attente) await reponse.attente;
  await route.fulfill({
    status: reponse.status ?? 200,
    json: reponse.json,
    headers: {
      'access-control-allow-origin': '*',
      'access-control-allow-headers': '*',
      'access-control-allow-methods': 'POST,OPTIONS',
    },
  });
}

async function simulerInscriptionMedecine(page: Page) {
  const { state, completion } = await simulerCompletionSoignant(page);
  state.overrides.set('fn_types_exercice_autorises', ['SALARIE']);
  const simulation = {
    state, completion,
    equivalence: { json: ['AS'] } as ReponseSimulee,
    marche: { json: { nb_missions: 0, nb_etablissements: 0, taux_max: null, taux_moyen: null, zone: 'national' } } as ReponseSimulee,
  };
  const chemins = new Set([
    '/functions/v1/verify-rpps', '/functions/v1/register-soignant',
    '/rest/v1/rpc/fn_professions_autorisees_scolarite', '/rest/v1/rpc/fn_apercu_marche_profession',
  ]);
  await page.route(url => chemins.has(url.pathname), async route => {
    const req = route.request();
    const url = new URL(req.url());
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) return route.abort();
    if (req.method() === 'OPTIONS') return repondre(route, { json: null });
    if (req.method() !== 'POST') {
      state.unknown.push(`${req.method()} ${url.pathname}`);
      return repondre(route, { status: 501, json: { code: 'RECETTE_INCONNU' } });
    }
    const name = url.pathname.split('/').pop()!;
    const body = req.postDataJSON();
    state.calls.push({ name, method: req.method(), body, url: url.pathname });
    if (name === 'fn_professions_autorisees_scolarite') {
      // Toute requête DES serait une régression : ce parcours ne consulte pas
      // le référentiel des passerelles temporaires aide-soignant.
      expect(['MEDECINE_DFGSM', 'MEDECINE_DFASM']).toContain(body.p_formation);
      expect(Object.keys(body).sort()).toEqual(['p_annee_validee', 'p_formation']);
      expect(Number.isInteger(body.p_annee_validee)).toBe(true);
      return repondre(route, simulation.equivalence);
    }
    if (name === 'fn_apercu_marche_profession') {
      if (body.p_profession === 'MEDECIN') return repondre(route, simulation.marche);
      expect(['IDE', 'AS']).toContain(body.p_profession);
      return repondre(route, { json: { nb_missions: 0, nb_etablissements: 0, taux_max: null, zone: 'national' } });
    }
    if (name === 'verify-rpps') {
      expect(body).toMatchObject({ prenom: 'Camille', nom: 'Recette', profession: 'MEDECIN', rpps: '10000000001' });
      return repondre(route, { json: { trouve: true, prenom: 'Camille', nom_api: 'Recette', profession_api: 'MEDECIN', profession_correspond: true } });
    }
    expect(req.headers().authorization).toBe('Bearer fixture-auth');
    expect(body).toMatchObject({
      prenom: 'Camille', nom: 'Recette', telephone: '0100000000', dateNaissance: '1990-01-01',
      profession: 'MEDECIN', typesContrat: ['SALARIE'], rpps: '10000000001',
      est_etudiant: true, etudiant_details: INTERNAT,
    });
    expect(body).not.toHaveProperty('password');
    expect(body).not.toHaveProperty('motDePasse');
    completion.soumissions.push(body);
    Object.assign(state.profile, {
      prenom: body.prenom, nom: body.nom, telephone: body.telephone,
      date_naissance: body.dateNaissance, profession: body.profession,
      numero_rpps: body.rpps, rpps_verifie: true,
      est_etudiant: true, etudiant_details: body.etudiant_details,
      types_contrat_acceptes: JSON.stringify(body.typesContrat),
    });
    state.mode = 'complet';
    return repondre(route, { json: { ok: true, user_id: ids.user } });
  });
  return simulation;
}

const profession = (page: Page) => page.getByRole('combobox', { name: 'Profession *', exact: true });
const formation = (page: Page) => page.getByRole('combobox', { name: 'Formation', exact: true });
const annee = (page: Page) => page.getByLabel(/^Dernière année validée/);
const choisirAs = (page: Page) => page.getByRole('button', { name: /^Choisir le profil Aide-Soignant/ });
const appelsEquivalence = (simulation: Awaited<ReturnType<typeof simulerInscriptionMedecine>>) =>
  simulation.state.calls.filter(call => call.name === 'fn_professions_autorisees_scolarite');

async function ouvrirEtudiantMedecine(page: Page) {
  await ouvrirDossierDepuisMission(page);
  await profession(page).click();
  await page.getByTestId('profession-option-MEDECIN').click();
  await expect(profession(page)).toHaveText('Médecin');
  await page.getByRole('button', { name: 'Je suis étudiant en santé', exact: true }).click();
  await expect(formation(page)).toBeVisible();
  await expect(formation(page).locator('option')).toHaveText([
    '— Choisir —', 'Médecine — 1er cycle (DFGSM)',
    'Médecine — 2e cycle (DFASM / externat)', INTERNAT,
  ]);
  expect(await formation(page).locator('option').evaluateAll(options => options.map(option => (option as HTMLOptionElement).value)))
    .toEqual(['', 'MEDECINE_DFGSM', 'MEDECINE_DFASM', 'MEDECINE_DES']);
}

test('étudiant médecine — internat conservé dans le brouillon et la finalisation simulée', async ({ page }, info) => {
  const simulation = await simulerInscriptionMedecine(page);
  await ouvrirEtudiantMedecine(page);
  await formation(page).selectOption('MEDECINE_DES');
  await expect(annee(page)).toHaveCount(0);
  await expect(choisirAs(page)).toHaveCount(0);
  await expect(profession(page)).toHaveText('Médecin');
  await remplirIdentite(page);
  await page.getByLabel(/^Date de naissance \*/).press('Enter');
  await expect(formation(page)).toBeFocused();
  const sauvegardesAvant = simulation.state.calls.filter(call => call.name === 'fn_enregistrer_parcours_inscription').length;
  await page.getByRole('button', { name: 'Enregistrer et continuer plus tard', exact: true }).click();
  await expect(page).toHaveURL(/\/soignant\/recherche-missions$/);
  const brouillons = simulation.state.calls.filter(call => call.name === 'fn_enregistrer_parcours_inscription');
  expect(brouillons).toHaveLength(sauvegardesAvant + 1);
  expect(brouillons[brouillons.length - 1].body.p_donnees).toMatchObject({ profession: 'MEDECIN', estEtudiant: true, scolariteFormation: 'MEDECINE_DES', scolariteAnnee: '' });
  expect(simulation.completion.soumissions).toEqual([]);

  // Reprise par l'action visible de candidature, puis relecture du brouillon
  // après une navigation document complète, sans réinjecter de données UI.
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  await page.getByText(mission.intitule, { exact: true }).click();
  await page.getByRole('button', { name: 'Candidater', exact: true }).first().click();
  await expect(page).toHaveURL(/\/inscription\/completer$/);
  await expect(formation(page)).toHaveValue('MEDECINE_DES');
  await attendreAPI(page);
  await page.reload();
  await expect(formation(page)).toHaveValue('MEDECINE_DES');
  await expect(annee(page)).toHaveCount(0);
  await expect(profession(page)).toHaveText('Médecin');
  const etudiant = page.getByRole('button', { name: 'Je suis étudiant en santé', exact: true });
  await expect(etudiant).toHaveAttribute('aria-pressed', 'true');
  // La cible tactile peut être agrandie par iOS sans déformer le rail ni
  // laisser sortir le curseur de l'interrupteur.
  const cible = await etudiant.boundingBox();
  expect(cible?.width).toBeGreaterThanOrEqual(44);
  expect(cible?.height).toBeGreaterThanOrEqual(44);
  const rail = await etudiant.locator(':scope > span').boundingBox();
  const curseur = await etudiant.locator('span > span').boundingBox();
  expect(rail).not.toBeNull(); expect(curseur).not.toBeNull();
  expect(curseur!.x).toBeGreaterThanOrEqual(rail!.x);
  expect(curseur!.y).toBeGreaterThanOrEqual(rail!.y);
  expect(curseur!.x + curseur!.width).toBeLessThanOrEqual(rail!.x + rail!.width);
  expect(curseur!.y + curseur!.height).toBeLessThanOrEqual(rail!.y + rail!.height);
  await expect(page.getByLabel(/^Prénom \*/)).toHaveValue('Camille');
  await formation(page).scrollIntoViewIfNeeded();
  await preuve(page, 'inscription-medecine-internat-brouillon-recharge', info, true);
  expect(appelsEquivalence(simulation)).toEqual([]);

  await verifierRppsSimule(page);
  await page.getByRole('button', { name: 'Enregistrer mon profil', exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
  expect(simulation.completion.soumissions).toHaveLength(1);
  expect(simulation.completion.soumissions[0]).toMatchObject({ profession: 'MEDECIN', est_etudiant: true, etudiant_details: INTERNAT });
  expect(simulation.state.profile.tous_documents_valides).toBe(false);
  expect(appelsEquivalence(simulation)).toEqual([]);
  await preuve(page, 'inscription-medecine-internat-finalisation-simulee', info);
  await sansDebordement(page);
  expect(simulation.state.errors).toEqual([]); expect(simulation.state.unknown).toEqual([]);
});

test('étudiant médecine — changement de cycle et proposition aide-soignant uniquement sur choix explicite', async ({ page }, info) => {
  const simulation = await simulerInscriptionMedecine(page);
  await ouvrirEtudiantMedecine(page);
  await formation(page).selectOption('MEDECINE_DFGSM');
  await annee(page).fill('2');
  await expect(choisirAs(page)).toBeVisible();
  await annee(page).press('Enter');
  await expect(page.getByPlaceholder(/^11 chiffres/)).toBeFocused();
  await expect(profession(page)).toHaveText('Médecin');
  expect(appelsEquivalence(simulation).map(call => call.body)).toEqual([{ p_formation: 'MEDECINE_DFGSM', p_annee_validee: 2 }]);
  await preuve(page, 'inscription-medecine-premier-cycle-proposition-seule', info);

  const attente = differer();
  simulation.equivalence = { json: ['AS'], attente: attente.attente };
  try {
    await formation(page).selectOption('MEDECINE_DFASM');
    await expect(annee(page)).toHaveValue('');
    await expect(choisirAs(page)).toHaveCount(0);
    expect(appelsEquivalence(simulation)).toHaveLength(1);
    await annee(page).fill('1');
    await expect.poll(() => appelsEquivalence(simulation).length).toBe(2);
    await expect(page.getByRole('status').filter({ hasText: 'Vérification des possibilités d’emploi temporaire…' })).toBeVisible();
    await expect(choisirAs(page)).toHaveCount(0);
    await expect(profession(page)).toHaveText('Médecin');
  } finally {
    attente.liberer();
  }
  await expect(choisirAs(page)).toBeVisible();
  await expect(profession(page)).toHaveText('Médecin');
  expect(appelsEquivalence(simulation)[1].body).toEqual({ p_formation: 'MEDECINE_DFASM', p_annee_validee: 1 });
  await preuve(page, 'inscription-medecine-deuxieme-cycle-proposition-renouvelee', info);
  await choisirAs(page).click();
  await expect(profession(page)).toHaveText('Aide-Soignant(e) (AS)');
  await expect(page.getByText(/Pré-éligibilité détectée pour des missions comme/)).toBeVisible();
  await expect(choisirAs(page)).toHaveCount(0);
  expect(simulation.completion.soumissions).toEqual([]);
  await preuve(page, 'inscription-medecine-profil-as-choisi-explicitement', info);
  await sansDebordement(page);
  expect(simulation.state.errors).toEqual([]); expect(simulation.state.unknown).toEqual([]);
});

test('étudiant médecine — panne du référentiel distincte d’un niveau insuffisant, puis reprise', async ({ page }, info) => {
  const simulation = await simulerInscriptionMedecine(page);
  simulation.equivalence = { status: 503, json: { code: 'RECETTE_503', message: 'Référentiel indisponible dans la simulation' } };
  await ouvrirEtudiantMedecine(page);
  await formation(page).selectOption('MEDECINE_DFGSM');
  await annee(page).fill('2');
  await expect(page.getByRole('status').filter({ hasText: INDISPONIBLE })).toBeVisible();
  await expect(page.getByText(/Ce niveau ne permet pas encore d’exercer|Ce niveau ne permet pas encore d'exercer/)).toHaveCount(0);
  await expect(choisirAs(page)).toHaveCount(0);
  await expect(profession(page)).toHaveText('Médecin');
  await expect(annee(page)).toHaveValue('2');
  await preuve(page, 'inscription-medecine-referentiel-indisponible', info);

  simulation.equivalence = { json: ['AS'] };
  await annee(page).fill('3');
  await expect(choisirAs(page)).toBeVisible();
  await expect(page.getByRole('status').filter({ hasText: INDISPONIBLE })).toHaveCount(0);
  await formation(page).selectOption('MEDECINE_DES');
  await expect(annee(page)).toHaveCount(0);
  await expect(choisirAs(page)).toHaveCount(0);
  await expect(profession(page)).toHaveText('Médecin');
  await preuve(page, 'inscription-medecine-reprise-puis-internat-sans-equivalence', info);
  expect(appelsEquivalence(simulation).map(call => call.body)).toEqual([
    { p_formation: 'MEDECINE_DFGSM', p_annee_validee: 2 },
    { p_formation: 'MEDECINE_DFGSM', p_annee_validee: 3 },
  ]);
  expect(simulation.completion.soumissions).toEqual([]);
  expect(simulation.state.errors).toEqual([]); expect(simulation.state.unknown).toEqual([]);
});

test('étudiant médecine — aperçu tardif sous le formulaire sans déplacer les champs actifs', async ({ page }, info) => {
  const simulation = await simulerInscriptionMedecine(page);
  const attente = differer();
  simulation.marche = {
    attente: attente.attente,
    json: { nb_missions: 17, nb_etablissements: 4, taux_max: 60, taux_moyen: 45, zone: 'national' },
  };
  try {
    await ouvrirEtudiantMedecine(page);
    await expect.poll(() => simulation.state.calls.filter(call => call.name === 'fn_apercu_marche_profession' && call.body.p_profession === 'MEDECIN').length).toBe(1);
    await expect(page.getByText('Vérification des modes d’exercice autorisés…', { exact: true })).toHaveCount(0);
    const prenom = page.getByLabel(/^Prénom \*/);
    await prenom.click();
    await page.evaluate(() => document.fonts.ready);
    const positions = () => page.evaluate(() => {
      const main = document.querySelector('main')!;
      const prenom = document.querySelector<HTMLInputElement>('input[autocomplete="given-name"]')!;
      const profession = document.getElementById('profession-select')!;
      return { prenom: prenom.getBoundingClientRect().top, profession: profession.getBoundingClientRect().top, scroll: main.scrollTop };
    });
    const avant = await positions();
    attente.liberer();
    const apercu = page.getByRole('status').filter({ hasText: '17 missions Médecin' });
    await expect(apercu).toBeVisible();
    await attendreAPI(page);
    const apres = await positions();
    expect(Math.abs(apres.prenom - avant.prenom)).toBeLessThanOrEqual(1);
    expect(Math.abs(apres.profession - avant.profession)).toBeLessThanOrEqual(1);
    expect(Math.abs(apres.scroll - avant.scroll)).toBeLessThanOrEqual(1);
    await expect(prenom).toBeFocused();
    expect(await apercu.evaluate(element => {
      const form = document.querySelector('form')!;
      return !form.contains(element) && !!(form.compareDocumentPosition(element) & Node.DOCUMENT_POSITION_FOLLOWING);
    })).toBe(true);
    await preuve(page, 'inscription-medecine-apercu-tardif-champs-stables', info);
    await sansDebordement(page);
    expect(simulation.completion.soumissions).toEqual([]);
    expect(simulation.state.errors).toEqual([]); expect(simulation.state.unknown).toEqual([]);
  } finally {
    attente.liberer();
  }
});

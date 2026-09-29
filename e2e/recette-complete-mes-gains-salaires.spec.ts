import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, attendreAPI, sansDebordement, ids, mission } from './helpers/recette-complete-soignant';

// États fictifs du contrat legacy : aucun paiement, compte ou appel distant réel.
type Ligne = Record<string, any>;
const regionSalaires = (page: Page) => page.getByRole('region', { name: 'Déclarations de salaire par mission' });
const date = new Date();
date.setDate(1); date.setHours(10, 0, 0, 0);
const debut = date.toISOString();
const fin = new Date(date.getTime() + 8 * 3600000).toISOString();
const idMission = (n: number) => `69000000-0000-4000-8000-${String(200 + n).padStart(12, '0')}`;
function creerMission(n: number, intitule: string, extra: Ligne = {}) {
  return { ...mission, id: idMission(n), intitule, debut_le: debut, fin_le: fin, statut: 'TERMINEE', soignant_assigne_id: ids.user, nb_creneaux: 1, net_estime: 999, net_a_payer: 1210, total_brut: 1000, presences: [{ valide_par_etablissement: true }], creneaux: [], ...extra };
}
function creerPaiement(n: number, extra: Ligne = {}) {
  return { id: `paiement-${n}`, mission_id: idMission(n), soignant_id: ids.user, etablissement_id: ids.etab,
    statut: 'CONFIRME', confirme_par_soignant: true, conteste: false, montant_net: 300,
    montant_du_reference: 999, solde_restant: 699, est_partiel: true, source_montant_du: 'ESTIMATION_AVANT_PAS_A_CONFIRMER',
    methode: 'VIREMENT', reference_virement: 'RECETTE', date_paiement: debut, modifie_le: debut, cree_le: debut, ...extra };
}
async function preparer(page: Page) {
  const etat = await simulerSoignant(page);
  // Les polices externes sont remplacées localement ; toute API reste simulée.
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ body: '' }));
  await page.route('**/rest/v1/mission_creneaux?*', async route => {
    const url = new URL(route.request().url());
    const demande = url.searchParams.get('mission_id') ?? '';
    const lignes = (etat.tables.get('missions') ?? []).filter(m => demande.includes(m.id)).map(m => ({
      id: `creneau-${m.id}`, mission_id: m.id, debut: m.debut_le, fin: m.fin_le, est_pause: false, type_creneau: 'EFFECTIF',
    }));
    etat.calls.push({ name: 'mission_creneaux', method: route.request().method(), body: null, url: url.pathname + url.search });
    await route.fulfill({ json: lignes, headers: {
      'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range',
      'content-range': lignes.length ? `0-${lignes.length - 1}/${lignes.length}` : '*/0',
    } });
  });
  return etat;
}
async function ouvrir(page: Page) {
  await entrer(page, 'connexion');
  await page.evaluate(() => { localStorage.removeItem('jolene_prompt_parrainage_1er_paiement'); localStorage.removeItem('jolene_prompt_parrainage_le'); });
  await aller(page, '/soignant/mes-gains?tab=apercu');
  await expect(regionSalaires(page)).toBeVisible();
  await regionSalaires(page).locator('summary').click();
}
async function aucuneReception(page: Page) {
  await attendreAPI(page);
  await expect(regionSalaires(page)).toContainText('Réception confirmée pour 0 mission');
  await expect(page.getByText(/Premier paiement reçu/)).toHaveCount(0);
  expect(await page.evaluate(() => localStorage.getItem('jolene_prompt_parrainage_1er_paiement'))).toBeNull();
  expect(await page.evaluate(() => localStorage.getItem('jolene_prompt_parrainage_le'))).toBeNull();
}
function verifierLectures(etat: Awaited<ReturnType<typeof simulerSoignant>>) {
  const lectures = etat.calls.filter(c => c.name === 'paiements_soignant' && !new URL(c.url, 'http://localhost').searchParams.has('statut'));
  expect(lectures.length).toBeGreaterThan(0);
  for (const lecture of lectures) {
    const select = new URL(lecture.url, 'http://localhost').searchParams.get('select')?.split(',');
    for (const champ of ['montant_net', 'confirme_par_soignant', 'conteste', 'montant_du_reference', 'source_montant_du']) expect(select).toContain(champ);
  }
  expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
}
async function preuve(page: Page, info: TestInfo, nom: string) {
  await sansDebordement(page);
  await info.attach(nom, { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
  await regionSalaires(page).scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath(`${nom}.png`), fullPage: false });
}

test('salaires — états prudents, montants invalides, badges et absence de faux premier paiement', async ({ page }, info) => {
  const etat = await preparer(page);
  const cas = [
    ['Confirmation absente', { confirme_par_soignant: false }, 'Réception à vérifier'],
    ['Confirmation nulle', { confirme_par_soignant: null }, 'Réception à vérifier'],
    ['Litige résolu', { statut: 'RESOLU' }, 'Litige résolu · réception à vérifier'],
    ['Ancienne confirmation contestée', { conteste: true }, 'Paiement contesté'],
    ['Paiement contesté', { statut: 'CONTESTE' }, 'Paiement contesté'],
    ['Montant zéro', { montant_net: 0 }, 'Réception à vérifier'],
    ['Montant non numérique', { montant_net: 'invalide' }, 'Réception à vérifier'],
    ['Montant manquant', { montant_net: null }, 'Réception à vérifier'],
    ['Montant négatif', { montant_net: -20 }, 'Réception à vérifier'],
    ['Montant infini', { montant_net: 'Infinity' }, 'Réception à vérifier'],
    ['Montant vide', { montant_net: '' }, 'Réception à vérifier'],
    ['Montant booléen', { montant_net: true }, 'Réception à vérifier'],
    ['Versement déclaré', { statut: 'DECLARE', confirme_par_soignant: false }, 'Réception à confirmer'],
    ['Déclaration en attente', { statut: 'EN_ATTENTE', confirme_par_soignant: false }, 'Réception à vérifier'],
  ] as const;
  etat.tables.set('missions', [...cas.map(([nom], n) => creerMission(n, nom)), creerMission(20, 'Sans déclaration'), creerMission(21, 'Régime indéterminé', { type_contrat_applique: null, type_contrat_recherche: null }), creerMission(22, 'Régime inconnu', { type_contrat_applique: 'INCONNU', type_contrat_recherche: 'SALARIE' })]);
  etat.tables.set('paiements_soignant', [...cas.map(([, extra], n) => creerPaiement(n, extra)), creerPaiement(21), creerPaiement(22)]);
  await ouvrir(page);
  const salaires = regionSalaires(page);
  for (const [nom, extra, libelle] of cas) {
    const ligne = salaires.getByRole('listitem', { name: nom, exact: true });
    await expect(ligne).toContainText(libelle);
    if ('montant_net' in extra) await expect(ligne).toContainText('Montant déclaré indisponible');
    // Le badge de l'historique utilise exactement la même classification.
    await expect(page.getByRole('button', { name: new RegExp(nom) }).filter({ hasText: 'brut :' })).toContainText(libelle);
  }
  await expect(salaires.getByRole('listitem', { name: 'Sans déclaration' })).toContainText('Aucun versement déclaré');
  await expect(page.getByRole('button', { name: 'Voir mission Sans déclaration', exact: true })).toContainText('Aucun versement déclaré');
  for (const nom of ['Régime indéterminé', 'Régime inconnu']) {
    await expect(page.getByRole('button', { name: `Voir mission ${nom}`, exact: true })).toContainText('Régime à vérifier');
    await expect(salaires.getByRole('listitem', { name: nom })).toHaveCount(0);
  }
  await expect(salaires).not.toContainText(/999,00|699,00|à solder|Net de référence/);
  await expect(page.getByRole('region', { name: 'Suivi des honoraires' })).toHaveCount(0);
  await aucuneReception(page);
  await salaires.getByRole('button', { name: 'Voir les paiements à confirmer' }).click();
  await expect(page).toHaveURL(/mes-gains\?tab=apercu$/);
  await expect(page.locator('#paiements-a-confirmer')).toBeFocused();
  await expect.poll(() => page.locator('#paiements-a-confirmer').evaluate(element => Math.round(element.getBoundingClientRect().top))).toBe(80);
  await expect(page.getByText(/déclare t'avoir payé/)).toBeVisible();
  await preuve(page, info, 'etats-salaries-prudents');
  await recharger(page);
  await aucuneReception(page);
  verifierLectures(etat);
});

test('salaires — confirmer depuis le bandeau puis reprendre sans reliquat estimé ni double nudge', async ({ page }, info) => {
  const etat = await preparer(page);
  etat.tables.set('missions', [creerMission(0, 'Salaire net employeur')]);
  const paiement = creerPaiement(0, { statut: 'DECLARE', confirme_par_soignant: false, montant_net: 400, montant_du_reference: 400, solde_restant: 0, est_partiel: false, source_montant_du: 'BULLETIN_OFFICIEL_ETABLISSEMENT' });
  etat.tables.set('paiements_soignant', [paiement]);
  let confirmations = 0;
  await page.route('**/rest/v1/rpc/fn_confirmer_paiement_soignant', async route => {
    expect(route.request().postDataJSON()).toEqual({ p_paiement_id: paiement.id });
    confirmations++;
    Object.assign(paiement, { statut: 'CONFIRME', confirme_par_soignant: true });
    await route.fulfill({ json: null, headers: { 'access-control-allow-origin': '*' } });
  });
  await ouvrir(page);
  await aucuneReception(page);
  await regionSalaires(page).getByRole('button', { name: 'Voir les paiements à confirmer' }).click();
  await page.getByRole('button', { name: /déclare t'avoir payé/ }).click();
  await page.getByRole('button', { name: 'Confirmer la réception', exact: true }).click();
  await expect(regionSalaires(page)).toContainText('Réception confirmée pour 1 mission');
  await expect(regionSalaires(page)).toContainText(/Montant déclaré : 400,00\s*€/);
  await expect(regionSalaires(page)).toContainText(/Net de référence déclaré par l’employeur : 400,00\s*€/);
  await expect(regionSalaires(page)).not.toContainText(/999,00|599,00|à solder/);
  await expect(page.getByRole('region', { name: 'Suivi des honoraires' })).toHaveCount(0);
  await expect(page.getByText(/Premier paiement reçu/)).toBeVisible();
  await expect(page.getByRole('button', { name: /Salaire net employeur/ }).filter({ hasText: 'brut :' })).toContainText('Réception confirmée');
  expect(confirmations).toBe(1);
  await expect(page.getByText(/Cette estimation peut différer du net du bulletin officiel/)).toBeVisible();
  await expect(page.getByText(/Les simulations salariales sont indicatives/)).toBeVisible();
  await expect(page.getByText(/font foi|montant définitif est confirmé après validation/)).toHaveCount(0);
  for (const nom of [/Net salarié estimé.*999,00/, /Brut.*1[\s\u202f]000,00/]) {
    await page.getByRole('button', { name: nom }).click();
    await expect(page).toHaveURL(/mes-gains\?tab=apercu$/);
    await expect(regionSalaires(page)).toBeFocused();
    await expect.poll(() => regionSalaires(page).evaluate(element => Math.round(element.getBoundingClientRect().top))).toBe(80);
  }
  await preuve(page, info, 'reception-explicite');
  await recharger(page);
  await expect(regionSalaires(page)).toContainText('Réception confirmée pour 1 mission');
  await expect(page.getByText(/Premier paiement reçu/)).toHaveCount(0);
  expect(await page.evaluate(() => localStorage.getItem('jolene_prompt_parrainage_1er_paiement'))).toBe('1');
  await expect(page.getByRole('button', { name: /déclare t'avoir payé/ })).toHaveCount(0);
  verifierLectures(etat);
});

test('historique salarié et profil libéral ou mixte — factures conservées, dernier état et navigation', async ({ page }, info) => {
  const etat = await preparer(page);
  etat.profile.type_exercice = 'LIBERAL'; etat.profile.statut_liberal = 'ACTIF';
  const ancien = { debut_le: '2025-09-01T08:00:00Z', fin_le: '2025-09-01T16:00:00Z' };
  etat.tables.set('missions', [
    creerMission(0, 'Ancien salaire résolu', ancien),
    creerMission(1, 'Salaire mensuel mission A', ancien),
    creerMission(2, 'Salaire mensuel mission B', { ...ancien, type_contrat_applique: null }),
    creerMission(3, 'Honoraires hebdomadaires', { type_contrat_applique: 'LIBERAL', type_contrat_recherche: 'LIBERAL' }),
  ]);
  const paiements = [
    creerPaiement(0, { id: 'ancien-confirme', montant_net: 500, modifie_le: '2025-09-02T00:00:00Z' }),
    creerPaiement(0, { id: 'recent-resolu', statut: 'RESOLU', montant_net: 500, modifie_le: '2025-09-03T00:00:00Z' }),
    creerPaiement(1, { montant_net: 500 }), creerPaiement(2, { montant_net: 500 }),
    creerPaiement(3, { montant_net: 9900, facture_honoraire_id: 'facture-payee' }),
  ];
  etat.tables.set('paiements_soignant', paiements);
  const factures = [
    { id: 'facture-payee', mission_id: idMission(3), numero_facture: 'F-RECETTE-1', statut: 'PAYEE', montant_ttc: 200 },
    { id: 'facture-retard', mission_id: idMission(3), numero_facture: 'F-RECETTE-2', statut: 'EN_RETARD', montant_ttc: 80 },
    { id: 'avance-hors-page', mission_id: 'mission-encore-en-cours', numero_facture: 'F-RECETTE-3', statut: 'FACTORISEE', montant_ttc: 50 },
    { id: 'avoir', mission_id: 'mission-avoir', numero_facture: 'DOCUMENT-4', statut: 'EMISE', montant_ttc: 30 },
  ].map(f => ({ ...f, etablissement_id: ids.etab, etablissement_nom: 'Résidence simulation', date_emission: debut }));
  etat.overrides.set('fn_mes_factures_honoraires', factures);
  etat.tables.set('factures_honoraires', factures.map(f => ({ id: f.id, soignant_id: ids.user, type_document: f.id === 'avoir' ? 'AVOIR' : 'FACTURE' })));
  await ouvrir(page);
  for (const type of ['LIBERAL', 'MIXTE']) {
    if (type === 'MIXTE') { etat.profile.type_exercice = type; etat.tables.set('paiements_soignant', [...paiements].reverse()); await recharger(page); await regionSalaires(page).locator('summary').click(); }
    await expect(regionSalaires(page)).toContainText('Réception confirmée pour 2 missions');
    await expect(regionSalaires(page).getByRole('listitem', { name: 'Ancien salaire résolu' })).toContainText('Litige résolu · réception à vérifier');
    await expect(regionSalaires(page)).not.toContainText(/1[\s\u202f]000,00|9[\s\u202f]900,00/);
    const honoraires = page.getByRole('region', { name: 'Suivi des honoraires' });
    await expect(honoraires.getByRole('button', { name: /^Payé/ })).toContainText(/250,00\s*€/);
    await expect(honoraires.getByRole('button', { name: /^En attente de paiement/ })).toContainText(/80,00\s*€/);
    await expect(honoraires).not.toContainText(/500,00|999,00|30,00/);
  }
  await preuve(page, info, 'historique-et-honoraires');
  await page.getByRole('region', { name: 'Suivi des honoraires' }).getByRole('button', { name: /^En attente de paiement/ }).click();
  await expect(page).toHaveURL(/tab=factures$/);
  await expect(page.getByText('F-RECETTE-2', { exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Aperçu', exact: true }).click();
  await expect(regionSalaires(page)).toContainText('Réception confirmée pour 2 missions');
  await expect(page.getByText(/Premier paiement reçu/)).toHaveCount(0);
  verifierLectures(etat);
});

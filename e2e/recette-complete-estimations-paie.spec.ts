import { expect, test, type Page, type Locator, type TestInfo } from '@playwright/test';
import { simulerSoignant, entrer, aller, recharger, sansDebordement, mission, ids } from './helpers/recette-complete-soignant';
import { simulerEtablissement, entrer as entrerEtab, allerA, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Parcours visibles fictifs : les notes distinguent simulation, bulletin employeur et facture.
async function preuveNote(page: Page, note: Locator, info: TestInfo, nom: string) {
  await expect(note).toBeVisible();
  await note.evaluate(element => element.scrollIntoView({ block: 'center' }));
  await expect.poll(() => note.evaluate(element => {
    const rect = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2));
  })).toBe(true);
  await sansDebordement(page);
  await expect(page.getByText(/montants calculés par le moteur de paie font foi|montant définitif est confirmé après validation/)).toHaveCount(0);
  await info.attach(nom, { body: await page.locator('main').ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath(`${nom}.png`), fullPage: false });
}

test('soignant — estimations sur accueil, historique, recherche, détail et sélection de série', async ({ page }, info) => {
  const etat = await simulerSoignant(page); etat.offers = true;
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ body: '' }));
  const date = new Date(); date.setDate(1); date.setHours(10, 0, 0, 0);
  etat.tables.set('missions', [{ ...mission, statut: 'TERMINEE', soignant_assigne_id: ids.user, debut_le: date.toISOString(), fin_le: new Date(date.getTime() + 8 * 3600000).toISOString() }]);
  await page.route('**/rest/v1/mission_creneaux?*', async route => {
    const idsDemandes = new URL(route.request().url()).searchParams.get('mission_id') ?? '';
    const lignes = (etat.tables.get('missions') ?? []).filter(m => idsDemandes.includes(m.id)).map(m => ({ id: `creneau-${m.id}`, mission_id: m.id, debut: m.debut_le, fin: m.fin_le, est_pause: false, type_creneau: 'PREVISIONNEL' }));
    await route.fulfill({ json: lignes, headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': lignes.length ? `0-${lignes.length - 1}/${lignes.length}` : '*/0' } });
  });
  await entrer(page, 'connexion');
  const noteCommune = page.getByText(/Cette estimation peut différer du net du bulletin officiel/);
  await aller(page, '/soignant/tableau-de-bord');
  await preuveNote(page, noteCommune, info, 'note-accueil');
  await aller(page, '/soignant/missions?tab=passees');
  await expect(page.getByRole('tab', { name: 'Passées', exact: true })).toHaveAttribute('aria-selected', 'true');
  await preuveNote(page, noteCommune, info, 'note-historique');
  const serie = 'SERIE_1790700000000_test';
  const ouverte = { ...mission, description: `${mission.description} [SERIE_ID:${serie}]` };
  etat.tables.set('missions', [ouverte]);
  await aller(page, '/soignant/recherche-missions');
  await page.getByRole('dialog', { name: '5 questions pour un deck qui te ressemble' }).getByRole('button', { name: 'Plus tard', exact: true }).click();
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  await preuveNote(page, noteCommune, info, 'note-recherche');
  await page.getByText(mission.intitule, { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${ids.mission}$`));
  await preuveNote(page, page.getByText('Simulation salariale indicative avant prélèvement à la source. Le net exact figure sur le bulletin officiel établi par l’employeur.', { exact: true }), info, 'note-detail-salarie');
  await aller(page, `/soignant/missions/serie/${serie}`);
  const selection = page.locator('main').getByRole('checkbox');
  await expect(selection).toBeChecked();
  await preuveNote(page, page.getByText(/^Simulation salariale indicative avant prélèvement à la source/), info, 'note-serie-salariee');
  await selection.uncheck();
  await expect(page.getByText(/^Simulation salariale indicative avant prélèvement à la source/)).toHaveCount(0);
  await selection.check();
  await expect(page.getByText(/^Simulation salariale indicative avant prélèvement à la source/)).toBeVisible();
  etat.tables.set('missions', [{ ...ouverte, type_contrat_applique: 'LIBERAL', type_contrat_recherche: 'LIBERAL' }]);
  await recharger(page);
  await preuveNote(page, page.getByText('Les honoraires libéraux sont détaillés sur la facture.', { exact: true }), info, 'note-serie-liberale');
  await expect(page.getByText(/^Simulation salariale indicative/)).toHaveCount(0);
  await aller(page, `/soignant/missions/${ids.mission}`);
  await preuveNote(page, page.getByText('Honoraires indiqués à titre prévisionnel. Le montant facturé est détaillé sur la facture d’honoraires.', { exact: true }), info, 'note-detail-liberal');
  await expect(page.getByText(/^Simulation salariale indicative/)).toHaveCount(0);
  etat.tables.set('missions', [{ ...ouverte, type_contrat_applique: null, type_contrat_recherche: 'TOUS' }]);
  await recharger(page);
  const neutre = page.getByText('Montant brut indicatif tant que le régime de la mission n’est pas choisi.', { exact: true });
  await preuveNote(page, neutre, info, 'note-detail-regime-non-choisi');
  await expect(page.getByText(/^Simulation salariale indicative|^Honoraires indiqués à titre prévisionnel|Salaire versé vers/)).toHaveCount(0);
  await recharger(page);
  await expect(neutre).toBeVisible();
  expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
});

test('établissement — variables de préparation de paie séparées des copies officielles après rechargement', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  await entrerEtab(page, 'connexion'); await allerA(page, '/etablissement/export-paie');
  const variables = page.getByRole('region', { name: 'Variables pour votre service paie' });
  const note = variables.getByText(/Ces montants servent à préparer la paie/);
  await expect(page.getByRole('region', { name: 'Copies des bulletins officiels', exact: true })).toBeVisible();
  await preuveNote(page, note, info, 'note-export-paie');
  await stabiliserLectures(page); await page.reload();
  await expect(note).toContainText('le bulletin officiel est établi par l’employeur ou son service paie');
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
});

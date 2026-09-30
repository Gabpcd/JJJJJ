import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { readFile, writeFile } from 'node:fs/promises';
import {
  simulerEtablissement, entrer as entrerEtablissement, allerA, stabiliserLectures,
  ids as idsEtablissement,
} from './helpers/recette-complete-etablissement';
import {
  simulerSoignant, entrer as entrerSoignant, aller, recharger, sansDebordement,
  ids as idsSoignant, mission as modeleMission, profil,
} from './helpers/recette-complete-soignant';

// Interface réelle, réponses API fictives et réseau distant bloqué par les helpers.
// Aucun compte, paiement, bulletin ni fichier fournisseur n'est créé.
type Ligne = Record<string, any>;
const missionA = '69000000-0000-4000-8000-000000000281';
const missionB = '69000000-0000-4000-8000-000000000282';
const titres = ['Mission A — huit heures', 'Mission B — six heures'];
const variables = (page: Page) => page.getByRole('region', { name: 'Variables pour votre service paie' });

function fixtures(etablissementId: string, soignantId: string) {
  const moisParis = new Intl.DateTimeFormat('fr-CA', { timeZone: 'Europe/Paris', year: 'numeric', month: '2-digit' }).format(new Date());
  const missions: Ligne[] = [missionA, missionB].map((id, index) => {
    const debut = `${moisParis}-0${index === 0 ? 3 : 5}T08:00:00.000Z`;
    const heures = index === 0 ? 8 : 6;
    const brut = index === 0 ? 320 : 180;
    return {
      ...modeleMission, id, intitule: titres[index], etablissement_id: etablissementId,
      soignant_assigne_id: soignantId, debut_le: debut,
      fin_le: new Date(new Date(debut).getTime() + heures * 3_600_000).toISOString(),
      statut: 'TERMINEE', nb_creneaux: index, duree_heures: heures,
      taux_horaire_base: index === 0 ? 40 : 30, total_brut: brut,
      net_estime: brut * 0.8, net_a_payer: brut * 0.8,
      type_paiement_soignant: 'BULLETIN_PAIE', type_contrat_applique: 'SALARIE',
      presences: [{ valide_par_etablissement: true }], creneaux: [],
      heures_nuit: 0, heures_dimanche: 0, heures_ferie: 0,
      montant_majoration_nuit: 0, montant_majoration_dimanche: 0, montant_majoration_ferie: 0,
      montant_ifm: 0, montant_icp: 0,
    };
  });
  const previsionnels = missions.map(m => ({
    id: `previsionnel-${m.id}`, mission_id: m.id, debut: m.debut_le, fin: m.fin_le,
    type_creneau: 'PREVISIONNEL', est_pause: false,
  }));
  return { missions, creneaux: [...previsionnels], previsionnels, lectures: [] as string[], mutations: [] as string[] };
}

async function simulerLectures(page: Page, donnees: ReturnType<typeof fixtures>) {
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('https://fonts.gstatic.com/**', route => route.fulfill({ body: '' }));
  for (const table of ['missions', 'mission_creneaux']) {
    await page.route(`**/rest/v1/${table}?*`, async route => {
      const request = route.request();
      const url = new URL(request.url());
      donnees.lectures.push(url.pathname + url.search);
      if (!['GET', 'HEAD'].includes(request.method())) {
        donnees.mutations.push(`${request.method()} ${url.pathname}`);
        return route.fulfill({ status: 501, json: { message: 'Mutation non simulée' } });
      }
      const source = table === 'missions' ? donnees.missions : donnees.creneaux;
      let lignes = source.filter(ligne => [...url.searchParams.entries()].every(([cle, filtre]) => {
        if (['select', 'order', 'limit', 'offset', 'or', 'and'].includes(cle) || cle.includes('.')) return true;
        const [op, ...reste] = filtre.split('.');
        const valeur = reste.join('.');
        if (op === 'eq') return String(ligne[cle]) === valeur;
        if (op === 'in') return valeur.replace(/^\(|\)$/g, '').split(',').includes(String(ligne[cle]));
        if (op === 'lt') return ligne[cle] < valeur;
        if (op === 'gt') return ligne[cle] > valeur;
        if (op === 'is') return valeur === 'null' ? ligne[cle] == null : String(ligne[cle]) === valeur;
        return true;
      }));
      const total = lignes.length;
      const offset = Number(url.searchParams.get('offset') ?? 0);
      lignes = lignes.slice(offset, offset + Number(url.searchParams.get('limit') ?? total));
      await route.fulfill({ json: lignes, headers: {
        'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range',
        'content-range': total ? `${offset}-${offset + lignes.length - 1}/${total}` : '*/0',
      } });
    });
  }
}

function effectif(mission: Ligne, heures: number) {
  return {
    id: `effectif-${mission.id}`, mission_id: mission.id, debut: mission.debut_le,
    fin: new Date(new Date(mission.debut_le).getTime() + heures * 3_600_000).toISOString(),
    type_creneau: 'EFFECTIF', est_pause: false,
  };
}

async function preuve(page: Page, info: TestInfo, nom: string) {
  await sansDebordement(page);
  const aria = await page.locator('main').ariaSnapshot();
  await writeFile(info.outputPath(`${nom}.txt`), aria);
  await info.attach(nom, { body: aria, contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath(`${nom}.png`), fullPage: true, animations: 'disabled' });
}

async function csv(page: Page, bouton: Locator, info: TestInfo, nom: string) {
  const telechargement = page.waitForEvent('download');
  await bouton.click();
  const fichier = await telechargement;
  expect(fichier.suggestedFilename()).toMatch(/\.csv$/);
  await fichier.saveAs(info.outputPath(`${nom}.csv`));
  const contenu = await readFile(info.outputPath(`${nom}.csv`), 'utf8');
  await info.attach(nom, { body: contenu, contentType: 'text/csv' });
  return contenu.replace(/^\uFEFF/, '').trim().split(/\r?\n/);
}

async function verifierEtablissement(page: Page, heures: number[], bruts: number[], sources: string[]) {
  await expect(variables(page).getByRole('alert')).toHaveCount(0);
  const lignes = variables(page).locator('tbody tr');
  await expect(lignes).toHaveCount(2);
  for (const [i, titre] of titres.entries()) {
    const ligne = lignes.filter({ hasText: titre });
    await expect(ligne.getByRole('cell').nth(3)).toHaveText(`${heures[i]}h`);
    await expect(ligne.getByRole('cell').nth(10)).toHaveText(new RegExp(`^${bruts[i]},00\\s*€$`));
    await expect(ligne).toContainText(sources[i]);
    // Une autre mission ne doit fournir ni la date ni les heures de cette ligne.
    await expect(ligne.getByRole('cell').nth(2)).not.toContainText(i === 0 ? '05/' : '03/');
  }
  await expect(variables(page).getByRole('button', { name: 'Télécharger', exact: true }).first()).toBeEnabled();
}

async function verifierSoignant(page: Page, heures: number[], bruts: number[]) {
  await expect(page.getByRole('combobox', { name: 'Période des revenus' })).toHaveText('Ce mois');
  await expect(page.getByText('Totaux et export en attente de validation', { exact: true })).toHaveCount(0);
  for (const [i, titre] of titres.entries()) {
    const ligne = page.getByRole('button', { name: `Voir mission ${titre}`, exact: true });
    await expect(ligne.getByText(`${heures[i]}h`, { exact: true })).toBeVisible();
    await expect(ligne.getByText(new RegExp(`^brut : ${bruts[i]},00\\s*€$`))).toBeVisible();
    await expect(ligne).toContainText('Aucun versement déclaré');
  }
  await expect(page.getByRole('button', { name: new RegExp(`^2 missions ${heures[0] + heures[1]}h$`) })).toBeVisible();
  await expect(page.getByRole('button', { name: 'CSV', exact: true })).toBeEnabled();
}

function verifierLotMultiMission(donnees: ReturnType<typeof fixtures>) {
  expect(donnees.lectures.some(url => url.includes('mission_creneaux?') && url.includes(missionA) && url.includes(missionB))).toBe(true);
  expect(donnees.mutations).toEqual([]);
}

test('établissement — deux prévisionnels isolés, effectifs prioritaires et mission en cours proratisée', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  const donnees = fixtures(idsEtablissement.etab, idsEtablissement.soignant);
  donnees.missions[1].nb_creneaux = 0;
  etat.overrides.set('fn_mes_soignants_etablissement', [{ ...profil, id: idsEtablissement.soignant }]);
  await simulerLectures(page, donnees);
  await entrerEtablissement(page, 'connexion');
  await allerA(page, '/etablissement/export-paie');
  const previsionnel = ['Planning prévisionnel validé', 'Planning prévisionnel validé'];
  await verifierEtablissement(page, [8, 6], [320, 180], previsionnel);
  await preuve(page, info, 'etablissement-previsionnels-avant-rechargement');
  const lignes = await csv(page, variables(page).getByRole('button', { name: 'Télécharger', exact: true }).first(), info, 'etablissement-previsionnels');
  expect(lignes).toHaveLength(3);
  for (const [index, titre] of titres.entries()) {
    const cellules = lignes[index + 1].split(';');
    expect(cellules[3]).toBe(titre);
    expect(cellules[6]).toBe(index === 0 ? '8' : '6');
    expect(cellules[13]).toBe(index === 0 ? '320.00' : '180.00');
  }
  await stabiliserLectures(page); await page.reload();
  await verifierEtablissement(page, [8, 6], [320, 180], previsionnel);
  await preuve(page, info, 'etablissement-previsionnels-apres-rechargement');

  donnees.missions[1].nb_creneaux = 1;
  await stabiliserLectures(page); await page.reload();
  await verifierEtablissement(page, [8, 6], [320, 180], previsionnel);
  await preuve(page, info, 'etablissement-nombre-creneaux-un');
  donnees.missions[1].statut = 'EN_COURS';
  donnees.creneaux = [...donnees.previsionnels, effectif(donnees.missions[0], 4), effectif(donnees.missions[1], 3)];
  await stabiliserLectures(page); await page.reload();
  await verifierEtablissement(page, [4, 3], [320, 90], ['Pointages effectifs validés', 'Pointages effectifs validés']);
  const effectifs = await csv(page, variables(page).getByRole('button', { name: 'Télécharger', exact: true }).first(), info, 'etablissement-effectifs');
  expect(effectifs).toHaveLength(3);
  expect(effectifs[1].split(';')[6]).toBe('4'); expect(effectifs[1].split(';')[13]).toBe('320.00');
  expect(effectifs[2].split(';')[6]).toBe('3'); expect(effectifs[2].split(';')[13]).toBe('90.00');
  await preuve(page, info, 'etablissement-effectifs-en-cours');
  verifierLotMultiMission(donnees);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

test('établissement — un créneau étranger ne complète pas une mission incomplète, reprise par Réessayer', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  const donnees = fixtures(idsEtablissement.etab, idsEtablissement.soignant);
  donnees.missions[0].nb_creneaux = 2;
  etat.overrides.set('fn_mes_soignants_etablissement', [{ ...profil, id: idsEtablissement.soignant }]);
  await simulerLectures(page, donnees);
  let telechargements = 0;
  page.on('download', () => { telechargements++; });
  await entrerEtablissement(page, 'connexion'); await allerA(page, '/etablissement/export-paie');
  const blocage = variables(page).getByRole('alert');
  const message = `Le planning exact de la mission « ${titres[0]} » est incomplet.`;
  await expect(blocage).toContainText('Export de paie bloqué');
  await expect(blocage).toContainText(message);
  await expect(variables(page).getByRole('button', { name: 'Télécharger', exact: true })).toHaveCount(0);
  await preuve(page, info, 'etablissement-incomplet-avant-rechargement');
  await stabiliserLectures(page); await page.reload();
  await expect(blocage).toContainText(message);
  await preuve(page, info, 'etablissement-incomplet-apres-rechargement');
  expect(telechargements).toBe(0);
  donnees.missions[0].nb_creneaux = 0;
  await blocage.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await verifierEtablissement(page, [8, 6], [320, 180], ['Planning prévisionnel validé', 'Planning prévisionnel validé']);
  await preuve(page, info, 'etablissement-reprise');
  verifierLotMultiMission(donnees);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

test('soignant salarié — heures et bruts par mission, CSV, effectifs et refus du planning incomplet', async ({ page }, info) => {
  const etat = await simulerSoignant(page);
  const donnees = fixtures(idsSoignant.etab, idsSoignant.user);
  donnees.missions[1].nb_creneaux = 0;
  await simulerLectures(page, donnees);
  await entrerSoignant(page, 'connexion'); await aller(page, '/soignant/mes-gains?tab=apercu');
  await verifierSoignant(page, [8, 6], [320, 180]);
  await preuve(page, info, 'soignant-previsionnels-avant-rechargement');
  const lignes = await csv(page, page.getByRole('button', { name: 'CSV', exact: true }), info, 'soignant-previsionnels');
  expect(lignes).toHaveLength(3);
  for (const [index, titre] of titres.entries()) {
    const cellules = lignes[index + 1].split(',');
    expect(cellules[2]).toBe(`"${titre}"`);
    expect(cellules[5]).toBe(index === 0 ? '8' : '6');
    expect(cellules[7]).toBe(index === 0 ? '320.00' : '180.00');
  }
  await recharger(page); await verifierSoignant(page, [8, 6], [320, 180]);
  await preuve(page, info, 'soignant-previsionnels-apres-rechargement');
  donnees.missions[1].nb_creneaux = 1;
  await recharger(page); await verifierSoignant(page, [8, 6], [320, 180]);
  await preuve(page, info, 'soignant-nombre-creneaux-un');
  donnees.creneaux = [...donnees.previsionnels, effectif(donnees.missions[0], 4)];
  await recharger(page); await verifierSoignant(page, [4, 6], [320, 180]);
  await preuve(page, info, 'soignant-effectif-prioritaire');

  donnees.missions[0].nb_creneaux = 2;
  donnees.creneaux = [...donnees.previsionnels];
  await recharger(page);
  const blocage = page.getByRole('status').filter({ hasText: 'Totaux et export en attente de validation' });
  await expect(blocage).toContainText(`Le planning exact de la mission « ${titres[0]} » est incomplet.`);
  await expect(page.getByRole('button', { name: 'CSV', exact: true })).toBeDisabled();
  await expect(page.getByRole('button', { name: `Voir mission ${titres[0]}`, exact: true })).toHaveCount(0);
  await preuve(page, info, 'soignant-incomplet');
  await recharger(page);
  await expect(blocage).toContainText('Totaux et export en attente de validation');
  await expect(page.getByRole('button', { name: 'CSV', exact: true })).toBeDisabled();
  donnees.missions[0].nb_creneaux = 0;
  await recharger(page); await verifierSoignant(page, [8, 6], [320, 180]);
  await preuve(page, info, 'soignant-reprise');
  verifierLotMultiMission(donnees);
  expect(etat.unknown).toEqual([]); expect(etat.errors).toEqual([]);
});

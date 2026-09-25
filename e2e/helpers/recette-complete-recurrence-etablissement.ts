import { expect, type Page } from '@playwright/test';
import { allerA, entrer, ids, mission, simulerEtablissement, stabiliserLectures } from './recette-complete-etablissement';

/** Même isolateur strict que la recette générale ; aucune mutation mission préparée. */
export async function ouvrirRecurrence(page: Page, duplication = false) {
  const simulation = await simulerEtablissement(page);
  const publications: string[] = [];
  page.on('request', request => {
    const nom = new URL(request.url()).pathname.split('/').pop() ?? '';
    if (/^fn_(creer|modifier|publier)_mission/.test(nom)) publications.push(nom);
  });
  if (duplication) {
    const creneaux = [
      { debut: '2030-10-14T05:00:00.000Z', fin: '2030-10-14T10:00:00.000Z' },
      { debut: '2030-10-14T11:00:00.000Z', fin: '2030-10-14T15:00:00.000Z' },
      { debut: '2030-10-16T20:00:00.000Z', fin: '2030-10-17T04:00:00.000Z' },
    ].map((c, i) => ({ ...c, id: `recurrence-source-${i}`, mission_id: ids.mission, ordre: i, type_creneau: 'PREVISIONNEL', est_pause: false }));
    const source = { ...mission, intitule: 'Planning source — pause et nuit', debut_le: creneaux[0].debut, fin_le: creneaux[2].fin, nb_creneaux: 3, duree_heures: 17, total_brut: 510 };
    await page.route('**/rest/v1/**', async route => {
      const request = route.request(), url = new URL(request.url());
      const table = url.pathname.split('/').pop();
      if (!['localhost', '127.0.0.1'].includes(url.hostname) || !['missions', 'mission_creneaux'].includes(table ?? '')) return route.fallback();
      if (!['GET', 'HEAD'].includes(request.method())) return route.fallback();
      const rows: Record<string, unknown>[] = table === 'missions' ? [source] : creneaux;
      for (const [cle, valeur] of url.searchParams) {
        if (['id', 'mission_id', 'etablissement_id', 'est_pause', 'type_creneau'].includes(cle) && valeur.startsWith('eq.') && rows.some(row => String(row[cle]) !== valeur.slice(3))) {
          simulation.etat.inconnues.push(`Filtre source inattendu : ${cle}=${valeur}`);
          return route.fulfill({ status: 501, json: { message: 'Périmètre source non préparé' } });
        }
      }
      const object = request.headers().accept?.includes('object');
      return route.fulfill({ json: object ? rows[0] : rows, headers: { 'content-range': `0-${rows.length - 1}/${rows.length}` } });
    });
  }
  await entrer(page, 'connexion');
  await allerA(page, duplication ? `/etablissement/missions/creer?dupliquer=${ids.mission}&debut=2030-11-01T07:00:00Z&fin=2030-11-01T17:00:00Z` : '/etablissement/missions/creer');
  if (duplication) return { ...simulation, publications };
  await page.getByLabel('Intitulé *', { exact: true }).fill('Planning récurrent — simulation uniquement');
  await page.locator('#mission-profession').click();
  await page.getByRole('option', { name: /Infirmier.*Diplômé.*IDE/ }).click();
  await page.getByRole('radio', { name: /^Salarié/ }).check();
  await page.getByLabel('Taux horaire brut * (€/h)', { exact: true }).fill('30');
  return { ...simulation, publications };
}

export async function definirPeriode(page: Page, debut: string, fin = debut) {
  await page.getByLabel('Première date affichée *', { exact: true }).fill(debut);
  await page.getByLabel('Dernière date affichée *', { exact: true }).fill(fin);
  await page.getByRole('button', { name: 'Toutes les dates', exact: true }).click();
}

export async function definirHoraire(page: Page, date: string, debut: string, fin: string, index = 1) {
  await page.getByLabel(`Début du créneau ${index} du ${date}`, { exact: true }).fill(debut);
  await page.getByLabel(`Fin du créneau ${index} du ${date}`, { exact: true }).fill(fin);
}

export async function verifierIsolation(page: Page, simulation: Awaited<ReturnType<typeof ouvrirRecurrence>>) {
  await stabiliserLectures(page);
  expect(simulation.publications, 'Le récapitulatif ne publie aucune mission').toEqual([]);
  expect(simulation.etat.inconnues, 'Tous les endpoints sont explicitement simulés').toEqual([]);
  expect(simulation.etat.ecritures, 'Aucune mutation non préparée').toEqual([]);
  expect(simulation.etat.erreurs, 'Aucune exception JavaScript').toEqual([]);
}

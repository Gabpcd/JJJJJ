import { test, expect, type Page } from '@playwright/test';
import { compteNeuf, inscrire, missionId } from './helpers/exploration-simulee';

// Même budget lorsque ce fichier est découvert par la configuration CI générale.
test.setTimeout(45_000);

async function cadre(page: Page) {
  return (page.viewportSize()?.width || 0) < 768
    ? page.getByRole('navigation', { name: 'Navigation mobile', exact: true })
    : page.getByRole('navigation', { name: 'Sidebar', exact: true });
}

async function onglet(page: Page, label: string, desktop = label) {
  const nav = await cadre(page);
  const nom = (page.viewportSize()?.width || 0) < 768 ? label : desktop;
  const bouton = nav.getByRole('button', { name: nom, exact: true });
  if (!(await bouton.isVisible()) && ['Trouver une mission', 'Mes missions'].includes(nom)) {
    await nav.getByRole('button', { name: 'Missions', exact: true }).click();
  }
  if (!(await bouton.isVisible()) && nom === 'Parrainage') {
    await nav.getByRole('button', { name: 'Pilotage', exact: true }).click();
  }
  await bouton.click();
}

async function marquerCadre(page: Page) {
  const nav = await cadre(page);
  await expect(nav).toBeVisible();
  await nav.evaluate((element) => { (element as any).__recettePersistante = true; });
  await page.evaluate(() => { (window as any).__recetteDocument = 'document-initial'; });
}

async function verifierCadre(page: Page) {
  const nav = await cadre(page);
  await expect(nav).toBeVisible();
  expect(await nav.evaluate(element => (element as any).__recettePersistante)).toBe(true);
  expect(await page.evaluate(() => (window as any).__recetteDocument)).toBe('document-initial');
  await expect(page.locator('#main-content')).toHaveCount(1);
  expect(await nav.evaluate(element => {
    for (let p: Element | null = element; p; p = p.parentElement) {
      if (Number(getComputedStyle(p).opacity) < 1) return false;
    }
    return true;
  })).toBe(true);
}

for (const type of ['SOIGNANT', 'ETABLISSEMENT'] as const) {
  test(`${type} : navigation persistante par les cinq entrées principales`, async ({ page }) => {
    const fixture = await compteNeuf(page, type);
    await inscrire(page, type);
    await expect(page).toHaveURL(type === 'SOIGNANT' ? /soignant\/recherche-missions/ : /etablissement\/tableau-de-bord/);
    await marquerCadre(page);
    const items = type === 'SOIGNANT'
      ? [['Accueil', 'Accueil', 'tableau-de-bord'], ['Mes missions', 'Mes missions', 'missions'], ['Revenus', 'Revenus', 'mes-gains'], ['Profil', 'Mon compte', 'mon-compte'], ['Explorer', 'Trouver une mission', 'recherche-missions']]
      : [['Missions', 'Missions', 'missions'], ['Publier', 'Publier une mission', 'missions/creer'], ['Messages', 'Messagerie', 'messagerie'], ['Menu', 'Parrainage', (page.viewportSize()?.width || 0) < 768 ? 'mon-compte' : 'parrainage'], ['Accueil', 'Accueil', 'tableau-de-bord']];
    for (const [mobile, desktop, route] of items) {
      await onglet(page, mobile, desktop);
      await expect(page).toHaveURL(new RegExp(`/${route}$`));
      await verifierCadre(page);
    }
    expect(fixture.mutations).toEqual([]);
    expect(fixture.errors).toEqual([]);
  });
}

test('Explorer conserve ses filtres et sa liste après détail puis après un autre onglet', async ({ page }) => {
  const fixture = await compteNeuf(page, 'SOIGNANT', true);
  await inscrire(page, 'SOIGNANT');
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  await page.getByRole('button', { name: /^Filtres/ }).click();
  await page.getByLabel('📍 Ville ou code postal', { exact: true }).fill('Paris');
  await page.getByLabel('Taux horaire minimum (€/h)', { exact: true }).fill('29');
  await page.getByRole('button', { name: /^Voir 1 mission/ }).click();
  await expect(page.getByText('Remplacement infirmier de jour', { exact: true })).toBeVisible();
  await marquerCadre(page);
  await page.getByText('Remplacement infirmier de jour', { exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${missionId}`));
  await expect(page.getByRole('heading', { name: 'Remplacement infirmier de jour', exact: true })).toBeVisible();
  await verifierCadre(page);
  await page.getByRole('button', { name: 'Retour', exact: true }).filter({ visible: true }).click();
  await expect(page.getByRole('tab', { name: 'Liste', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByText('📍 Paris', { exact: true })).toBeAttached();
  const lecturesAvant = fixture.lectures.fn_explorer_missions_inscription;
  await onglet(page, 'Revenus');
  await expect(page).toHaveURL(/soignant\/mes-gains/);
  await onglet(page, 'Explorer', 'Trouver une mission');
  await expect(page.getByRole('tab', { name: 'Liste', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByText('Remplacement infirmier de jour', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: /^Filtres/ }).click();
  await expect(page.getByLabel('📍 Ville ou code postal', { exact: true })).toHaveValue('Paris');
  await expect(page.getByLabel('Taux horaire minimum (€/h)', { exact: true })).toHaveValue('29');
  expect(fixture.lectures.fn_explorer_missions_inscription).toBe(lecturesAvant);
  expect(fixture.mutations).toEqual([]);
  expect(fixture.errors).toEqual([]);
});

test('Swipe : clic ou tap ouvre le détail, un déplacement horizontal ne le déclenche pas', async ({ page, isMobile }) => {
  const fixture = await compteNeuf(page, 'SOIGNANT', true);
  await inscrire(page, 'SOIGNANT');
  await expect(page).toHaveURL(/soignant\/recherche-missions/);
  const titre = page.getByRole('button', { name: /^Mission IDE à Résidence Camille/ });
  await expect(titre).toBeVisible();
  if (isMobile) await titre.tap(); else await titre.click();
  const detail = page.getByRole('dialog', { name: 'Remplacement infirmier de jour', exact: true });
  await expect(detail).toBeVisible();
  await detail.getByRole('button', { name: 'Fermer', exact: true }).click();
  await expect(detail).toHaveCount(0);
  const box = await titre.boundingBox();
  if (!box) throw new Error('Carte absente');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  // Au-delà du seuil de drag, en deçà de celui validant un swipe métier.
  await page.mouse.move(box.x + box.width / 2 - 40, box.y + box.height / 2, { steps: 8 });
  await page.mouse.up();
  await expect(detail).toHaveCount(0);
  await expect(titre).toBeVisible();
  expect(fixture.mutations).toEqual([]);
  expect(fixture.errors).toEqual([]);
});

test('Carte chargée à la demande : popup sans rechargement et retours successifs', async ({ page }) => {
  const requetesCarte: string[] = [];
  page.on('request', req => {
    if (/CarteMissionsExploration(?:\.tsx|[^/]*\.js)|\/leaflet[^/]*\.js/.test(req.url())) requetesCarte.push(req.url());
  });
  const fixture = await compteNeuf(page, 'SOIGNANT', true);
  await inscrire(page, 'SOIGNANT');
  await expect(page.getByRole('button', { name: /^Mission IDE à Résidence Camille/ })).toBeVisible();
  expect(requetesCarte).toEqual([]);
  await marquerCadre(page);
  await page.getByRole('tab', { name: 'Carte', exact: true }).click();
  const marqueur = page.getByTitle('Remplacement infirmier de jour', { exact: true });
  await expect(marqueur).toBeVisible();
  expect(requetesCarte.length).toBeGreaterThan(0);
  await marqueur.click();
  await page.getByRole('link', { name: 'Voir la mission', exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/soignant/missions/${missionId}`));
  await verifierCadre(page);
  await page.getByRole('button', { name: 'Retour', exact: true }).filter({ visible: true }).click();
  await expect(page.getByRole('tab', { name: 'Carte', exact: true })).toHaveAttribute('aria-selected', 'true');
  await expect(marqueur).toBeVisible();
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  await expect(marqueur).toHaveCount(0);
  await page.getByRole('tab', { name: 'Carte', exact: true }).click();
  await expect(marqueur).toBeVisible();
  await page.getByRole('button', { name: 'Zoom avant', exact: true }).click();
  await verifierCadre(page);
  expect(fixture.mutations).toEqual([]);
  expect(fixture.errors).toEqual([]);
});

test('Explorer retrouve sa position après un détail et après un autre onglet', async ({ page }) => {
  const fixture = await compteNeuf(page, 'SOIGNANT', true, 10);
  await inscrire(page, 'SOIGNANT');
  await page.getByRole('tab', { name: 'Liste', exact: true }).click();
  const titre = page.getByText('Renfort infirmier 8', { exact: true });
  await titre.scrollIntoViewIfNeeded();
  await expect(titre).toBeInViewport();
  const y = await page.evaluate(() => window.scrollY);
  expect(y).toBeGreaterThan(200);
  await titre.click();
  await expect(page).toHaveURL(/soignant\/missions\/69000000-0000-4000-8000-000000000107/);
  await page.getByRole('button', { name: 'Retour', exact: true }).filter({ visible: true }).click();
  await expect(titre).toBeInViewport();
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeCloseTo(y, 0);
  await onglet(page, 'Revenus');
  await expect(page).toHaveURL(/soignant\/mes-gains/);
  await onglet(page, 'Explorer', 'Trouver une mission');
  await expect(titre).toBeInViewport();
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeCloseTo(y, 0);
  expect(fixture.mutations).toEqual([]);
  expect(fixture.errors).toEqual([]);
});

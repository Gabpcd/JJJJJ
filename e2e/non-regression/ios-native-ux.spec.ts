import { expect, test, type Page } from '@playwright/test';
import { loginAs } from '../helpers/auth';

test.use({ viewport: { width: 440, height: 956 }, hasTouch: true, isMobile: true });
test.describe.configure({ mode: 'serial' });

async function preparerCoquilleIOS(page: Page) {
  await page.addInitScript(() => {
    localStorage.setItem('cookie-consent', 'accepted');
    localStorage.setItem('push_permission_asked', 'later');
  });
}

async function verifierEcran(page: Page, route: string) {
  await page.goto(route, { waitUntil: 'domcontentloaded' });
  const main = page.locator('#main-content');
  await expect(main).toBeVisible();
  await page.waitForTimeout(250);

  const mesures = await page.evaluate(() => ({
    debordement: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    largeurViewport: document.documentElement.clientWidth,
    largeurMain: document.querySelector('main')?.getBoundingClientRect().width ?? 0,
  }));
  expect(mesures.debordement, `${route} ne doit pas déborder horizontalement`).toBeLessThanOrEqual(1);
  expect(mesures.largeurMain, `${route} doit occuper le viewport`).toBeLessThanOrEqual(mesures.largeurViewport + 1);
}

async function compterRetoursVisibles(page: Page) {
  return page.getByRole('button', { name: /^Retour$/ }).evaluateAll((boutons) => (
    boutons.filter((bouton) => {
      const rect = bouton.getBoundingClientRect();
      const style = getComputedStyle(bouton);
      return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';
    }).length
  ));
}

test.describe('expérience iOS — soignant', () => {
  test('les écrans principaux restent stables et sans contenu sous la barre d’onglets', async ({ page }) => {
    await preparerCoquilleIOS(page);
    await loginAs(page, 'soignant');

    for (const route of [
      '/soignant/tableau-de-bord',
      '/soignant/recherche-missions',
      '/soignant/missions',
      '/soignant/mes-gains',
      '/soignant/messagerie',
      '/soignant/mes-documents',
      '/soignant/mon-compte',
    ]) {
      await verifierEcran(page, route);
    }

    await page.goto('/soignant/mes-gains');
    const cta = page.getByRole('button', { name: 'Trouver une mission' });
    const nav = page.locator('.mobile-nav-bottom');
    await expect(cta).toBeVisible();
    await expect(nav).toBeVisible();
    const [ctaBox, navBox] = await Promise.all([cta.boundingBox(), nav.boundingBox()]);
    expect(ctaBox).not.toBeNull();
    expect(navBox).not.toBeNull();
    expect(ctaBox!.y + ctaBox!.height).toBeLessThanOrEqual(navBox!.y + 1);

    await page.goto('/soignant/score');
    await expect(page.getByRole('heading', { name: /Mon score de fiabilité/i })).toBeVisible();
    expect(await compterRetoursVisibles(page)).toBe(1);
  });
});

test.describe('expérience iOS — établissement', () => {
  test('les écrans principaux et la modale Contact restent dans le viewport', async ({ page }) => {
    await preparerCoquilleIOS(page);
    await loginAs(page, 'etab');

    for (const route of [
      '/etablissement/tableau-de-bord',
      '/etablissement/missions',
      '/etablissement/missions/creer',
      '/etablissement/messagerie',
      '/etablissement/presences',
      '/etablissement/contrats',
      '/etablissement/soignants',
      '/etablissement/facturation',
      '/etablissement/mon-compte',
    ]) {
      await verifierEcran(page, route);
    }

    await page.goto('/etablissement/equipe');
    await expect(page.getByRole('heading', { name: 'Mon équipe' })).toBeVisible();
    expect(await compterRetoursVisibles(page)).toBe(1);

    await page.goto('/etablissement/mon-compte');
    await page.getByRole('button', { name: /Contacter Jolene/i }).click();
    const dialogue = page.getByRole('dialog', { name: /Contacter Jolene/i });
    await expect(dialogue).toBeVisible();
    const dialogueBox = await dialogue.boundingBox();
    expect(dialogueBox).not.toBeNull();
    expect(dialogueBox!.y).toBeGreaterThanOrEqual(0);
    expect(dialogueBox!.y + dialogueBox!.height).toBeLessThanOrEqual(956);

    await page.getByLabel('Sujet').fill('Question de test visuel');
    await page.getByLabel('Votre message').fill('La modale reste stable au focus.');
    await expect(page.getByRole('button', { name: 'Envoyer' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Annuler' })).toBeVisible();
  });
});

test.describe('expérience établissement — desktop', () => {
  test.use({ viewport: { width: 1440, height: 900 }, hasTouch: false, isMobile: false });

  test('les écrans métier conservent leur largeur et leur navigation', async ({ page }) => {
    await preparerCoquilleIOS(page);
    await loginAs(page, 'etab');

    for (const route of [
      '/etablissement/tableau-de-bord',
      '/etablissement/missions',
      '/etablissement/missions/creer',
      '/etablissement/facturation',
      '/etablissement/mon-compte',
    ]) {
      await verifierEcran(page, route);
    }
  });
});

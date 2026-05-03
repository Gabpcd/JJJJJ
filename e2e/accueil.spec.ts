import { test, expect } from '@playwright/test';

test.describe('Page d\'accueil', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('charge la page avec le bon titre', async ({ page }) => {
    await expect(page).toHaveTitle(/Jolene/);
  });

  test('affiche le logo et le nom Jolene dans le header', async ({ page }) => {
    const header = page.locator('header');
    await expect(header.getByText('Jolene', { exact: true }).first()).toBeVisible();
  });

  test('affiche les liens de navigation principaux', async ({ page }) => {
    const header = page.locator('header');
    await expect(header.locator('a[href="/tarifs"]')).toBeVisible();
    await expect(header.locator('a[href="/blog"]')).toBeVisible();
    await expect(header.locator('a[href="/a-propos"]')).toBeVisible();
  });

  test('affiche le bouton de connexion dans le header', async ({ page }) => {
    await expect(page.getByTestId('header-cta-connexion')).toBeVisible();
  });

  test('le bouton "Se connecter" redirige vers /connexion', async ({ page }) => {
    await page.getByTestId('header-cta-connexion').click();
    await expect(page).toHaveURL(/\/connexion/);
  });

  test('affiche les CTA soignant et etablissement dans le hero', async ({ page }) => {
    await expect(page.getByTestId('hero-cta-soignant')).toBeVisible();
    await expect(page.getByTestId('hero-cta-etab')).toBeVisible();
  });

  test('le CTA hero soignant redirige vers /inscription/soignant', async ({ page }) => {
    await page.getByTestId('hero-cta-soignant').click();
    await expect(page).toHaveURL(/\/inscription\/soignant/);
  });

  test('le CTA hero etablissement redirige vers /inscription/etablissement', async ({ page }) => {
    await page.getByTestId('hero-cta-etab').click();
    await expect(page).toHaveURL(/\/inscription\/etablissement/);
  });

  test('affiche la section "Comment ca marche"', async ({ page }) => {
    await expect(page.getByText('Comment ça marche').first()).toBeVisible();
  });

  test('affiche la section FAQ', async ({ page }) => {
    await expect(page.getByText('Comment fonctionne la commission').first()).toBeVisible();
  });
});

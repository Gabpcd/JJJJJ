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
    await expect(header.locator('text=Jolene')).toBeVisible();
  });

  test('affiche les liens de navigation principaux', async ({ page }) => {
    const header = page.locator('header');
    await expect(header.locator('a[href="/tarifs"]')).toBeVisible();
    await expect(header.locator('a[href="/blog"]')).toBeVisible();
    await expect(header.locator('a[href="/a-propos"]')).toBeVisible();
  });

  test('affiche le bouton de connexion dans le header', async ({ page }) => {
    const header = page.locator('header');
    await expect(header.getByText('Se connecter')).toBeVisible();
  });

  test('le bouton "Se connecter" redirige vers /connexion', async ({ page }) => {
    await page.locator('header').getByText('Se connecter').click();
    await expect(page).toHaveURL(/\/connexion/);
  });

  test('affiche les CTA soignant et etablissement dans le hero', async ({ page }) => {
    const ctaSoignant = page.getByRole('button', { name: /soignant/i });
    const ctaEtablissement = page.getByRole('button', { name: /établissement/i });

    await expect(ctaSoignant.first()).toBeVisible();
    await expect(ctaEtablissement.first()).toBeVisible();
  });

  test('le CTA soignant redirige vers /inscription/soignant', async ({ page }) => {
    await page.getByRole('button', { name: /Je suis soignant/i }).click();
    await expect(page).toHaveURL(/\/inscription\/soignant/);
  });

  test('le CTA etablissement redirige vers /inscription/etablissement', async ({ page }) => {
    await page.getByRole('button', { name: /Je suis un établissement/i }).click();
    await expect(page).toHaveURL(/\/inscription\/etablissement/);
  });

  test('affiche la section "Comment ca marche"', async ({ page }) => {
    await expect(page.getByText('Comment ça marche')).toBeVisible();
  });

  test('affiche la section FAQ', async ({ page }) => {
    await expect(page.getByText('Comment fonctionne la commission')).toBeVisible();
  });
});

import { test, expect } from '@playwright/test';

test.describe('Navigation pages publiques', () => {
  test('/tarifs charge la grille tarifaire', async ({ page }) => {
    await page.goto('/tarifs');
    await expect(page).toHaveTitle(/Tarifs/i);
    // The page should contain pricing-related content
    await expect(page.getByText(/commission/i).first()).toBeVisible();
    // The "S'inscrire gratuitement" CTA should be visible (présent dans le header
    // ET dans le corps de la page → strict mode violation sans .first()).
    await expect(page.getByText(/S'inscrire gratuitement/i).first()).toBeVisible();
  });

  test('/a-propos charge la page a propos', async ({ page }) => {
    await page.goto('/a-propos');
    await expect(page.locator('body')).not.toContainText('404');
    await page.waitForLoadState('networkidle');
    // Should contain content about Jolene
    await expect(page.getByText(/Jolene/i).first()).toBeVisible();
  });

  test('/cgu charge la page des conditions generales', async ({ page }) => {
    await page.goto('/cgu');
    await expect(page.locator('body')).not.toContainText('Page introuvable');
    await page.waitForLoadState('networkidle');
  });

  test('/cgv charge la page des conditions generales de vente', async ({ page }) => {
    await page.goto('/cgv');
    await expect(page.locator('body')).not.toContainText('Page introuvable');
    await page.waitForLoadState('networkidle');
  });

  test('/mentions-legales charge la page des mentions legales', async ({ page }) => {
    await page.goto('/mentions-legales');
    await expect(page.locator('body')).not.toContainText('Page introuvable');
    await page.waitForLoadState('networkidle');
  });

  test('une URL invalide affiche la page 404', async ({ page }) => {
    await page.goto('/cette-page-nexiste-pas');
    await expect(page.getByText('404')).toBeVisible();
    await expect(page.getByText('Page introuvable')).toBeVisible();
    await expect(page.getByText(/Retour à l'accueil/i)).toBeVisible();
  });

  test('le lien retour de la page 404 ramene a l\'accueil', async ({ page }) => {
    await page.goto('/cette-page-nexiste-pas');
    await page.getByText(/Retour à l'accueil/i).click();
    await expect(page).toHaveURL('/');
  });
});

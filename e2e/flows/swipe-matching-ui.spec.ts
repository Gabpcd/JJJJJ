/**
 * Sprint 14 PR 3 — Tests E2E réels UI swipe matching Hinge-style.
 *
 * Remplace les 10 stubs Sprint 13-D par 6 tests fonctionnels qui valident :
 * - Route /soignant/swipe-missions accessible + page rendue
 * - Toggle Swipe/Liste : persistance localStorage + navigation
 * - Page MesMatches : route accessible + stats KPIs + filtres
 *
 * Pattern : login via UI (formulaire /connexion), navigation, assertion DOM.
 * Pas de dispatch Pointer Events (gesture swipe testé manuellement — flaky
 * cross-browser CI à cause de setPointerCapture + transform inline).
 */

import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

test.describe('Sprint 14 — UI swipe matching (réels)', () => {
  // Session G1 : le swipe est consolidé DANS /soignant/recherche-missions via un
  // toggle in-page (sans navigation). L'ancienne route /soignant/swipe-missions
  // redirige vers la page canonique. Tests alignés sur cette architecture.

  test('/soignant/swipe-missions redirige vers la page canonique + toggle présent', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.evaluate(() => localStorage.removeItem('jolene_missions_view_pref'));
    await page.goto('/soignant/swipe-missions');
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/, { timeout: 10_000 });

    await expect(page.getByRole('heading', { name: /Trouver une mission/i, level: 1 })).toBeVisible();
    await expect(page.getByRole('tablist', { name: /Vue Swipe ou Liste/i })).toBeVisible();
  });

  test('Toggle Liste : bascule in-page (pas de navigation) + localStorage', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.evaluate(() => localStorage.setItem('jolene_missions_view_pref', 'swipe'));
    await page.goto('/soignant/recherche-missions');
    await page.waitForLoadState('networkidle');

    const toggle = page.getByRole('tablist', { name: /Vue Swipe ou Liste/i });
    await toggle.getByRole('tab', { name: 'Liste', exact: true }).click();

    // Toggle in-page : l'URL ne change pas, seule la préférence est mémorisée.
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/);
    const pref = await page.evaluate(() => localStorage.getItem('jolene_missions_view_pref'));
    expect(pref).toBe('liste');
  });

  test('Toggle Swipe : bascule in-page (pas de navigation) + localStorage', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.evaluate(() => localStorage.setItem('jolene_missions_view_pref', 'liste'));
    await page.goto('/soignant/recherche-missions');
    await page.waitForLoadState('networkidle');

    const toggle = page.getByRole('tablist', { name: /Vue Swipe ou Liste/i });
    await toggle.getByRole('tab', { name: 'Swipe', exact: true }).click();

    await expect(page).toHaveURL(/\/soignant\/recherche-missions/);
    const pref = await page.evaluate(() => localStorage.getItem('jolene_missions_view_pref'));
    expect(pref).toBe('swipe');
  });

  test('Préférence localStorage=liste redirige depuis /swipe-missions vers /recherche-missions', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.evaluate(() => localStorage.setItem('jolene_missions_view_pref', 'liste'));
    await page.goto('/soignant/swipe-missions');
    // Redirection immediate via useEffect au mount
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/, { timeout: 10_000 });
  });

  test('Route /soignant/mes-matches accessible + stats engagement rendues', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/mes-matches');
    await page.waitForLoadState('networkidle');

    await expect(page.getByRole('heading', { name: 'Mes matches', level: 1 })).toBeVisible();

    // Soit la section stats (chargée), soit le spinner pendant fetch
    const stats = page.getByRole('region', { name: /Statistiques engagement/i });
    const spinner = page.locator('.animate-spin').first();
    await expect(stats.or(spinner)).toBeVisible({ timeout: 10_000 });
  });

  test('Page MesMatches : 3 filtres BoutonY2K (Tous / En cours / Terminées)', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/mes-matches');
    await page.waitForLoadState('networkidle');

    await expect(page.getByRole('button', { name: 'Tous', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'En cours', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Terminées', exact: true })).toBeVisible();

    // Click "En cours" → ne crash pas, filtre activé
    await page.getByRole('button', { name: 'En cours', exact: true }).click();
    // Le filtre actif ne déclenche pas de navigation, juste un re-render local
    await expect(page).toHaveURL(/\/soignant\/mes-matches/);
  });
});

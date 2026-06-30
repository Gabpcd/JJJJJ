/**
 * Sprint 14 PR 3 — Tests E2E réels UI swipe matching Hinge-style.
 *
 * Remplace les 10 stubs Sprint 13-D par 6 tests fonctionnels qui valident :
 * - Route /soignant/swipe-missions accessible + page rendue
 * - Toggle Swipe/Liste : persistance localStorage + navigation
 * - Routes legacy (mes-matches, planning) → redirect vers Mes missions (refonte nav)
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

  // Refonte nav : « Matchs » est absorbé par « Mes missions › À venir », et le
  // planning aussi. Les anciennes routes redirigent vers /soignant/missions.
  test('Route /soignant/mes-matches redirige vers Mes missions', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/mes-matches');
    await expect(page).toHaveURL(/\/soignant\/missions/, { timeout: 10_000 });
    await expect(page.getByRole('heading', { name: 'Mes missions', level: 1 })).toBeVisible();
  });

  test('Route /soignant/planning redirige vers Mes missions › À venir', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/planning');
    await expect(page).toHaveURL(/\/soignant\/missions/, { timeout: 10_000 });
  });
});

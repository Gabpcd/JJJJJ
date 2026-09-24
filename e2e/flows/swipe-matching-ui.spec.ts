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

import { test, expect, type Page } from '@playwright/test';
import { loginAs } from '../helpers/auth';

async function connecterEtLireClePreference(page: Page) {
  const reponseSession = page.waitForResponse(response =>
    new URL(response.url()).pathname === '/auth/v1/token'
    && response.request().method() === 'POST',
  );
  await loginAs(page, 'soignant');
  const session = await (await reponseSession).json();
  expect(session.user?.id).toMatch(/^[0-9a-f-]{36}$/i);
  return `jolene_missions_view_pref:${session.user.id}`;
}

test.describe('Sprint 14 — UI swipe matching (réels)', () => {
  // Session G1 : le swipe est consolidé DANS /soignant/recherche-missions via un
  // toggle in-page (sans navigation). L'ancienne route /soignant/swipe-missions
  // redirige vers la page canonique. Tests alignés sur cette architecture.

  test('/soignant/swipe-missions redirige vers la page canonique + toggle présent', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.evaluate(() => localStorage.removeItem('jolene_missions_view_pref'));
    await page.goto('/soignant/swipe-missions');
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/, { timeout: 10_000 });

    await expect(page.getByRole('heading', { name: /Explorer/i, level: 1 })).toBeVisible();
    await expect(page.getByRole('tablist', { name: /Vue Swipe/i })).toBeVisible();
  });

  test('Toggle Liste : bascule in-page (pas de navigation) + localStorage', async ({ page }) => {
    const clePreference = await connecterEtLireClePreference(page);
    await page.evaluate(cle => {
      localStorage.setItem(cle, 'swipe');
      localStorage.setItem('jolene_missions_view_pref', 'swipe');
    }, clePreference);
    await page.goto('/soignant/recherche-missions', { waitUntil: 'domcontentloaded' });

    const toggle = page.getByRole('tablist', { name: /Vue Swipe/i });
    await expect(toggle).toBeVisible();
    await expect(toggle.getByRole('tab', { name: 'Swipe', exact: true })).toHaveAttribute('aria-selected', 'true');
    await toggle.getByRole('tab', { name: 'Liste', exact: true }).click();

    // Toggle in-page : l'URL ne change pas, seule la préférence est mémorisée.
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/);
    await expect(toggle.getByRole('tab', { name: 'Liste', exact: true })).toHaveAttribute('aria-selected', 'true');
    const pref = await page.evaluate(cle => localStorage.getItem(cle), clePreference);
    expect(pref).toBe('liste');
    expect(await page.evaluate(() => localStorage.getItem('jolene_missions_view_pref'))).toBe('swipe');
    await page.reload();
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/);
    await expect(toggle.getByRole('tab', { name: 'Liste', exact: true })).toHaveAttribute('aria-selected', 'true');
  });

  test('Toggle Swipe : bascule in-page (pas de navigation) + localStorage', async ({ page }) => {
    const clePreference = await connecterEtLireClePreference(page);
    await page.evaluate(cle => {
      localStorage.setItem(cle, 'liste');
      localStorage.setItem('jolene_missions_view_pref', 'liste');
    }, clePreference);
    await page.goto('/soignant/recherche-missions', { waitUntil: 'domcontentloaded' });

    const toggle = page.getByRole('tablist', { name: /Vue Swipe/i });
    await expect(toggle).toBeVisible();
    await expect(toggle.getByRole('tab', { name: 'Liste', exact: true })).toHaveAttribute('aria-selected', 'true');
    await toggle.getByRole('tab', { name: 'Swipe', exact: true }).click();

    await expect(page).toHaveURL(/\/soignant\/recherche-missions/);
    await expect(toggle.getByRole('tab', { name: 'Swipe', exact: true })).toHaveAttribute('aria-selected', 'true');
    const pref = await page.evaluate(cle => localStorage.getItem(cle), clePreference);
    expect(pref).toBe('swipe');
    expect(await page.evaluate(() => localStorage.getItem('jolene_missions_view_pref'))).toBe('liste');
    await page.reload();
    await expect(page).toHaveURL(/\/soignant\/recherche-missions/);
    await expect(toggle.getByRole('tab', { name: 'Swipe', exact: true })).toHaveAttribute('aria-selected', 'true');
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

  // PR-B : onglet « Candidatures » (candidatures EN_ATTENTE) dans Mes missions.
  test('Mes missions : onglet Candidatures rendu (cartes ou état vide)', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/missions?tab=candidatures', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Mes missions', level: 1 })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Candidatures', exact: true })).toBeVisible();
    // Soit des cartes de candidature, soit l'état vide « élan » — jamais d'erreur.
    // NB : la description de l'état vide contient aussi « en attente de réponse »
    // (substring insensible à la casse) → quand l'état vide est rendu, les DEUX
    // branches du .or() matchent en même temps. .first() évite la violation
    // strict mode (pattern recommandé Playwright pour or()).
    const etatVide = page.getByText('Pas encore de candidature en attente');
    const enAttente = page.getByText('En attente de réponse').first();
    await expect(etatVide.or(enAttente).first()).toBeVisible({ timeout: 10_000 });
  });
});

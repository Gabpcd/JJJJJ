/**
 * Flow N — Recherche missions soignant : filtres, sauvegarde, alertes.
 *
 * Tests UI des filtres de recherche + persistence sauvegarde côté DB
 * (utilise les RPCs fn_creer_filtre_sauvegarde régénérées dans types.ts).
 */

import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

test.describe('Recherche missions soignant', () => {
  test('page d\'accueil publique a un sélecteur de profession', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    // Le combobox "Toutes les professions" via le SelectProfession dans hero
    await expect(page.getByLabel(/Profession à rechercher/i)).toBeVisible({ timeout: 10_000 });
  });

  test('input ville sur landing accepte texte', async ({ page }) => {
    await page.goto('/');
    const ville = page.getByLabel(/Ville ou code postal/i).first();
    await expect(ville).toBeVisible({ timeout: 5000 });
    await ville.fill('Paris');
    await expect(ville).toHaveValue('Paris');
  });

  test('soignant authentifié → page /soignant/recherche-missions accessible', async ({ page }) => {
    await loginAs(page, 'soignant');

    // Forcer pref liste pour éviter redirection vers /swipe-missions
    await page.evaluate(() => localStorage.setItem('jolene_missions_view_pref', 'liste'));

    // Les abonnements Supabase de l'explorateur peuvent maintenir le réseau
    // actif. Le contenu visible ci-dessous est le signal utilisateur fiable.
    await page.goto('/soignant/recherche-missions', { waitUntil: 'domcontentloaded' });

    // 6c.1 : la page canonique a pour titre « Explorer » (aligné sur
    // l'onglet de la bottom nav) + le switcher Swipe · Liste · Carte.
    await expect(page.getByRole('heading', { name: /Explorer/i, level: 1 })).toBeVisible({ timeout: 10_000 });
    await expect(page.getByRole('tablist', { name: /Vue Swipe/i })).toBeVisible();
  });
});

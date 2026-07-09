import { test, expect } from '@playwright/test';
import { loginAs } from '../helpers/auth';

/**
 * Non-régression Lot 11 — mécanique UX établissement.
 * Garde les invariants de la passe UX : plus de FAB flottant, garde-fou 48h
 * désactivant, labels visibles sous les onglets Paramètres, un seul
 * « Se déconnecter ». Viewport mobile de référence : 390×844.
 */

test.use({ viewport: { width: 390, height: 844 } });

test.describe('Lot 11 — UX établissement', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'etab');
  });

  test('aucun FAB flottant ne recouvre le contenu', async ({ page }) => {
    await page.goto('/etablissement/tableau-de-bord');
    await page.waitForLoadState('networkidle');
    // Le FAB « + Publier » (fixed, rond, bas-droite) a été supprimé au Lot 11.
    const fabs = page.locator('button.fixed, a.fixed').filter({ hasText: /publier/i });
    await expect(fabs).toHaveCount(0);
  });

  test('publication bloquée au-delà de 48h hebdo (bouton désactivé + erreur unique)', async ({ page }) => {
    await page.goto('/etablissement/missions/creer');
    await page.waitForLoadState('networkidle');
    // fixme(Lot 13) : parcours complet — remplir 6 jours × 9h (54h) en mode
    // récurrent, vérifier UNE zone role=alert avec la suggestion chiffrée
    // (« retirez un jour ou passez à … »), et le bouton Publier désactivé.
    test.fixme(true, 'Parcours 48h complet à automatiser (formulaire récurrent multi-étapes)');
  });

  test('Paramètres : les 4 onglets ont un label visible sur mobile', async ({ page }) => {
    await page.goto('/etablissement/parametres');
    await page.waitForLoadState('networkidle');
    for (const label of ['Profil', 'Groupe', 'Config', 'Exclusions']) {
      await expect(page.getByRole('tab', { name: new RegExp(label, 'i') })).toBeVisible();
    }
  });

  test('un seul « Se déconnecter » (fin de Mon compte)', async ({ page }) => {
    await page.goto('/etablissement/parametres');
    await page.waitForLoadState('networkidle');
    // L'onglet Profil ne porte plus le doublon mobile.
    await expect(page.getByRole('button', { name: /se déconnecter/i })).toHaveCount(0);
    await page.goto('/etablissement/mon-compte');
    await page.waitForLoadState('networkidle');
    await expect(page.getByText(/se déconnecter/i)).toHaveCount(1);
  });

  test('Publier expose « Type de contrat proposé » avec conséquences', async ({ page }) => {
    await page.goto('/etablissement/missions/creer');
    await page.waitForLoadState('networkidle');
    await expect(page.getByText('Type de contrat proposé')).toBeVisible();
    await expect(page.getByText(/vous êtes l.employeur/i)).toBeVisible();
  });
});

/**
 * Sprint 13-D PR 2 — Tests E2E UI swipe matching Hinge-style.
 *
 * Couvre :
 * - Navigation page SwipeMissions accessible role SOIGNANT
 * - Toggle Swipe/Liste persistance localStorage
 * - Affichage CardMissionSwipe + StackCards + BoutonsActionSwipe
 * - Gestures swipe gauche/droite via dispatchEvent Pointer
 * - Bouton SUPER_LIKE + animation confetti (via DOM assertion)
 * - Quota super-like badge + désactivation à 0 restant
 * - Modal détail mission ouverte au tap card
 * - EmptyState Mascotte si plus de missions
 *
 * Pattern Jolene : test.skip(true) car helpers seed + auth soignant
 * complexes à mettre en place CI (cf candidature.spec.ts, etc).
 */

import { test, expect } from '@playwright/test';
import { TEST_ACCOUNTS } from '../helpers/auth';

test.describe('Sprint 13-D — UI swipe matching Hinge-style', () => {
  test('Route /soignant/swipe-missions accessible (SOIGNANT)', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — auth soignant requis');

    const creds = TEST_ACCOUNTS.soignant;
    await page.goto('/connexion');
    await page.locator('input[type="email"]').fill(creds.email);
    await page.locator('input[type="password"]').first().fill(creds.password);
    await page.getByTestId('login-submit').click();
    await page.waitForURL(/\/soignant/, { timeout: 15000 });

    await page.goto('/soignant/swipe-missions');
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('heading', { name: 'Découvrir' })).toBeVisible();
  });

  test('Toggle Swipe/Liste persiste préférence localStorage', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement');
    // Click "Liste" sur SwipeMissions
    // Vérifier navigation /soignant/recherche-missions
    // Vérifier localStorage.getItem('jolene_missions_view_pref') === 'liste'
    // Recharger : devrait rediriger vers /soignant/recherche-missions (pref liste)
    // Click "Swipe" sur RechercheMissions
    // Vérifier navigation /soignant/swipe-missions + localStorage = 'swipe'
  });

  test('CardMissionSwipe affiche infos + BadgeY2K Match X/100', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — seed missions matchées');
    // Vérifier 1 card visible avec titre mission, étab, badge Match X/100
    // Si score >= 80 : variant=premium (gradient celebrate)
    // Si est_urgente : badge "⚡ Urgent"
    // Grid 3 cols date/durée/tarif visible
  });

  test('Swipe droite → LIKE enregistré + card suivante remontre', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — Pointer Events dispatch complexe');
    // Locate top card, dispatchEvent pointerdown puis pointermove +200px puis pointerup
    // Attendre transition exit animation
    // Vérifier card suivante affichée (top change)
    // Vérifier RPC fn_enregistrer_swipe appelée avec direction='LIKE'
  });

  test('Swipe gauche → DISLIKE enregistré + card suivante remontre', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement');
    // Idem mais -200px
  });

  test('Bouton SUPER_LIKE déclenche confetti + notif succès', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement');
    // Click bouton SUPER_LIKE (Star)
    // Vérifier .animate-confetti-pop éléments visibles (>= 30)
    // Vérifier toast/notif "Super-like envoyé !"
    // Vérifier badge quota décrémenté (de 5 à 4)
  });

  test('Quota super-like épuisé (0/5) → bouton disabled', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — pré-seed 5 super-likes du jour');
    // Vérifier bouton SUPER_LIKE a [disabled] + opacity-40
    // Vérifier aria-label contient "indisponible (quota épuisé)"
  });

  test('Tap card → modal ModalDetailMissionSwipe ouverte', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — wiring tap pas encore implémenté');
    // Click sur la card (button onTap)
    // Vérifier role=dialog ouvert avec titre mission complet
    // Vérifier breakdown score (tarif/distance/etab/urgence) affiché
    // Click "Postuler maintenant" → fermeture + LIKE
  });

  test('EmptyState Mascotte happy si plus de missions à swiper', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — soignant ayant swipé toutes les missions');
    // Vérifier Mascotte état "happy" visible
    // Vérifier titre "Vous avez tout vu pour aujourd\'hui !"
    // Vérifier bouton "Recharger" présent
  });

  test('Page MesMatches affiche stats engagement + filtres', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement');
    // Navigate /soignant/mes-matches
    // Vérifier 3 CarteKPIY2K visibles : Swipes / Matches (holographic) / Taux match (soft)
    // Vérifier 3 BoutonY2K filtres : Tous / En cours / Terminées
    // Click "En cours" → liste filtrée affichée
  });

  test('Streak badge dashboard soignant si streak >= 1', async ({ page }) => {
    test.skip(true, 'Helper CI à fixer post-lancement — wiring widget streak dashboard à faire');
    // Navigate /soignant/tableau-de-bord
    // Vérifier widget streak visible avec streak_count
  });
});

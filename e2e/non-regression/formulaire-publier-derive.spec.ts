import { test, expect, type Page } from '@playwright/test';
import { loginAs } from '../helpers/auth';

/**
 * Non-régression — Formulaire « Publier » (établissement) piloté par un ÉTAT
 * DÉRIVÉ de la période (bug structurel : jours/horaires étaient des états
 * indépendants à défaut statique lundi-first tout-coché).
 *
 * Repro d'origine (DESKTOP — les établissements travaillent sur desktop) :
 *   Du 22/07/2026 (mercredi) → Au 29/07/2026 ⇒ « Horaires par jour » commençait
 *   par LUNDI. Attendu : commence par Mer. 22/07.
 *
 * PROTOCOLE DE PREUVE : la vérification est une ASSERTION sur le texte exact
 * rendu (pas de screenshot). Vérifié en DESKTOP 1440×900 ET mobile 390×844 —
 * ce bug a survécu aux recettes précédentes car elles étaient mobile-only.
 *
 * La preuve la plus forte de la dérivation (ordre, libellés datés, 48h par
 * semaine civile) est le test unitaire src/lib/planning-derive.test.ts ; cet
 * e2e prouve que le composant RESTITUE bien ce texte à l'écran.
 */

async function ouvrirFormulairePublier(page: Page) {
  await loginAs(page, 'etab');
  await page.goto('/etablissement/missions/creer');
  await page.waitForLoadState('networkidle');
  // Période : Du mercredi 22/07/2026 → Au mercredi 29/07/2026.
  const dates = page.locator('input[type="date"]');
  await dates.first().fill('2026-07-22');
  await dates.nth(1).fill('2026-07-29');
}

function assertionsDerivation(viewport: { width: number; height: number }) {
  test.use({ viewport, isMobile: viewport.width < 768, hasTouch: viewport.width < 768 });

  test('jours travaillés dérivés : première entrée = Mer. 22/07, lundi seulement daté du 27', async ({ page }) => {
    await ouvrirFormulairePublier(page);

    // (1) Chips « Jours travaillés » : ordonnés depuis le 1er jour, libellés datés.
    const chips = page.getByTestId('jours-travailles').locator('button');
    await expect(chips.first()).toContainText('Mer. 22/07');
    await expect(chips.filter({ hasText: 'Lun.' })).toHaveText(/Lun\. 27\/07/);

    // (2) « Horaires par jour » : première ligne = mercredi 22/07 (pas lundi).
    const horaires = page.getByTestId('horaires-par-jour');
    await expect(horaires.locator('> div').first()).toContainText('Mer. 22/07');
    await expect(horaires).toContainText('Lun. 27/07');
    // Aucun lundi antérieur au 27 : le seul libellé « Lun. » est « Lun. 27/07 ».
    await expect(horaires).not.toContainText('Lun. 20/07');
  });

  test('garde-fou 48h par semaine civile : semaine du 20/07 = 60h, Publier désactivé', async ({ page }) => {
    await ouvrirFormulairePublier(page);
    // Défaut dérivé : tous les jours présents cochés à 12h (07:00→19:00).
    // Semaine civile du 20/07 (lun 20 → dim 26) contient 22,23,24,25,26 = 5×12 = 60h.
    const recap = page.getByTestId('recap-semaines');
    await expect(recap).toContainText('Semaine du 20/07');
    await expect(recap).toContainText('60h');
    await expect(recap).toContainText('Semaine du 27/07'); // 27,28,29 = 36h
    await expect(recap).toContainText('36h');

    // Erreur 48h unique (role=alert) + bouton Publier désactivé.
    await expect(page.getByRole('alert')).toContainText(/48\s?h/);
    await expect(page.getByRole('button', { name: /Publier la mission/i })).toBeDisabled();
  });
}

test.describe('Formulaire Publier — état dérivé — DESKTOP 1440×900', () => {
  assertionsDerivation({ width: 1440, height: 900 });
});

test.describe('Formulaire Publier — état dérivé — mobile 390×844', () => {
  assertionsDerivation({ width: 390, height: 844 });
});

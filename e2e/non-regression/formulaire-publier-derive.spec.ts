import { test, expect, type Page } from '@playwright/test';
import { loginAs } from '../helpers/auth';

/**
 * Non-régression du planning établissement : les dates réelles sont la source
 * de vérité. Deux mercredis restent deux dates indépendantes, les heures sont
 * contrôlées par semaine civile et la publication reste bloquée au-delà de 48 h.
 */

async function ouvrirFormulairePublier(page: Page) {
  await loginAs(page, 'etab');
  await page.goto('/etablissement/missions/creer');
  await page.waitForLoadState('networkidle');
  const dates = page.locator('input[type="date"]');
  await dates.first().fill('2026-07-22');
  await dates.nth(1).fill('2026-07-29');
  await page.getByRole('button', { name: 'Toutes les dates' }).click();
}

function assertionsPlanningExact(viewport: { width: number; height: number }) {
  test.use({ viewport, isMobile: viewport.width < 768, hasTouch: viewport.width < 768 });

  test('affiche toutes les dates réelles dans l’ordre et gère les exceptions séparément', async ({ page }) => {
    await ouvrirFormulairePublier(page);

    const horaires = page.getByTestId('horaires-par-jour');
    await expect(horaires.locator('section').first()).toContainText('mercredi 22 juillet 2026');
    await expect(page.getByTestId('jour-planning-2026-07-27')).toContainText('lundi 27 juillet 2026');
    await expect(page.getByTestId('jour-planning-2026-07-29')).toContainText('mercredi 29 juillet 2026');

    const premierMercredi = page.getByLabel('mercredi 22 juillet 2026 travaillé');
    const secondMercredi = page.getByLabel('mercredi 29 juillet 2026 travaillé');
    await expect(premierMercredi).toBeChecked();
    await expect(secondMercredi).toBeChecked();
    await premierMercredi.uncheck();
    await expect(premierMercredi).not.toBeChecked();
    await expect(secondMercredi).toBeChecked();
  });

  test('bloque exactement la semaine civile à 60 h', async ({ page }) => {
    await ouvrirFormulairePublier(page);
    const recap = page.getByTestId('recap-semaines');
    await expect(recap).toContainText('Semaine du 20/07');
    await expect(recap).toContainText('60 h');
    await expect(recap).toContainText('Semaine du 27/07');
    await expect(recap).toContainText('36 h');
    await expect(page.getByRole('alert')).toContainText(/Maximum légal : 48 h/i);
    await expect(page.getByRole('button', { name: /Publier la mission/i })).toBeDisabled();
  });
}

test.describe('Planning exact établissement — desktop', () => {
  assertionsPlanningExact({ width: 1440, height: 900 });
});

test.describe('Planning exact établissement — mobile', () => {
  assertionsPlanningExact({ width: 390, height: 844 });
});

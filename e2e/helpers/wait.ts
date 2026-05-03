import type { Page, Locator } from '@playwright/test';
import { expect } from '@playwright/test';

/**
 * Attend qu'un toast Sonner avec le type donné apparaisse.
 * Type peut être 'success', 'error', 'warning', 'info'.
 */
export async function waitForToast(
  page: Page,
  type: 'success' | 'error' | 'warning' | 'info',
  textIncludes?: string,
  timeout = 10_000,
): Promise<Locator> {
  const toast = page.locator(`[data-sonner-toast][data-type="${type}"]`).first();
  await expect(toast).toBeVisible({ timeout });
  if (textIncludes) {
    await expect(toast).toContainText(textIncludes, { timeout });
  }
  return toast;
}

/** Attend que le loader de page disparaisse (Loader2, ChargementPage). */
export async function waitForLoadingDone(page: Page, timeout = 15_000): Promise<void> {
  await page.waitForFunction(
    () => !document.querySelector('[data-loading], .animate-spin'),
    { timeout },
  );
}

/** Attend la fin d'une navigation et que la page soit interactive. */
export async function waitForPageReady(page: Page, timeout = 15_000): Promise<void> {
  await page.waitForLoadState('networkidle', { timeout });
}

/**
 * Mesure le Time-To-Interactive (TTI). Échoue si > maxMs.
 * Retourne le TTI mesuré en ms.
 */
export async function assertFastLoad(page: Page, maxMs = 3_000): Promise<number> {
  const tti = await page.evaluate(() => {
    const perf = performance.timing;
    return perf.domInteractive - perf.navigationStart;
  });
  expect.soft(tti).toBeLessThan(maxMs);
  return tti;
}

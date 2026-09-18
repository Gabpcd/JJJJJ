import { test, expect } from '@playwright/test';

/**
 * Non-régression mobile (projet `mobile-non-regression`, 390×844 tactile).
 *
 * Cible les régressions UX Safari iOS documentées dans CLAUDE.md (« Pièges
 * Safari iOS mobile ») : débordement horizontal parasite et inputs < 16px
 * (qui déclenchent le zoom auto au focus). Pages publiques uniquement —
 * aucun compte, aucun seed.
 *
 * Lancer : npm run test:e2e:regression
 */

test.describe('non-régression mobile — pages publiques', () => {
  test('accueil : rendu sans scroll horizontal', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('body')).toBeVisible();
    const debordement = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(debordement).toBeLessThanOrEqual(0);
  });

  test('connexion : inputs ≥ 16px (anti zoom auto iOS)', async ({ page }) => {
    await page.goto('/connexion');
    const email = page.locator('input[type="email"], input[name="email"]').first();
    await expect(email).toBeVisible();
    const taillePx = await email.evaluate(
      (el) => parseFloat(getComputedStyle(el).fontSize),
    );
    expect(taillePx).toBeGreaterThanOrEqual(16);
  });
});

test.describe('inscription soignant — iPhone 16 Pro Max', () => {
  test.use({ viewport: { width: 440, height: 956 }, hasTouch: true, isMobile: true });

  test.beforeEach(async ({ page }) => {
    await page.goto('/inscription/soignant');
    await page.locator('body').evaluate((body) => {
      body.classList.remove('platform-web');
      body.classList.add('platform-ios');
    });
  });

  test('ouvre le compte simplifié dans une surface native stable', async ({ page }) => {
    const carte = page.locator('.auth-scroll > .card-base');
    await expect(carte).toBeVisible();
    const chrome = await carte.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        borderTopWidth: style.borderTopWidth,
        borderRadius: style.borderRadius,
        boxShadow: style.boxShadow,
        flexShrink: style.flexShrink,
      };
    });
    expect(chrome).toEqual({
      borderTopWidth: '0px',
      borderRadius: '0px',
      boxShadow: 'none',
      flexShrink: '0',
    });

    const topInitial = await carte.evaluate((element) => element.getBoundingClientRect().top);
    expect(topInitial, 'le formulaire doit commencer sous le header, sans grand vide').toBeLessThan(120);

    const champsTropPetits = await page.locator('input, textarea, select').evaluateAll((elements) => (
      elements
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden';
        })
        .map((element) => Number.parseFloat(getComputedStyle(element).fontSize))
        .filter((fontSize) => fontSize < 16)
    ));
    expect(champsTropPetits, 'aucun champ visible ne doit provoquer le zoom iOS').toEqual([]);

    await expect(page.getByLabel('Profession', { exact: true })).toBeVisible();
    await expect(page.locator('input[type="password"]')).toHaveCount(1);
    await expect(page.locator('input[type="date"]')).toHaveCount(0);

  });

  test('garde le CTA accessible au-dessus de la zone sûre en fin de formulaire', async ({ page }) => {
    const scroller = page.locator('.auth-scroll');
    await scroller.evaluate((element) => element.scrollTo({ top: element.scrollHeight, behavior: 'auto' }));

    const continuer = page.getByRole('button', { name: 'Créer mon compte', exact: true });
    await expect(continuer).toBeVisible();
    const geometry = await continuer.evaluate((element) => ({
      bottom: element.getBoundingClientRect().bottom,
      viewportHeight: window.visualViewport?.height ?? window.innerHeight,
    }));
    expect(geometry.bottom).toBeLessThanOrEqual(geometry.viewportHeight - 16);
  });

  test('choisit la profession depuis le contrôle natif sans étape supplémentaire', async ({ page }) => {
    await page.getByRole('combobox', { name: 'Profession', exact: true }).selectOption('IDE');
    await expect(page.getByRole('combobox', { name: 'Profession', exact: true })).toHaveValue('IDE');
    await expect(page.getByRole('button', { name: 'Créer mon compte', exact: true })).toBeVisible();
  });
});

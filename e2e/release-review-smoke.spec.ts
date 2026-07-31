import { expect, test, type Page } from '@playwright/test';

type ReviewAccount = {
  email: string | undefined;
  password: string | undefined;
  destination: RegExp;
};

async function connecterCompteReview(page: Page, compte: ReviewAccount) {
  if (!compte.email || !compte.password) {
    test.skip(true, 'Identifiants de recette review absents de l’environnement.');
  }

  const erreursConsole: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') erreursConsole.push(message.text());
  });
  page.on('pageerror', (error) => erreursConsole.push(error.message));

  await page.goto('/connexion');
  await page.locator('input[type="email"]').fill(compte.email!);
  await page.locator('input[type="password"]').first().fill(compte.password!);
  await page.getByTestId('login-submit').click();

  await expect(page).toHaveURL(compte.destination, { timeout: 20_000 });
  await expect(page.getByText(/Votre espace est momentanément indisponible/i)).toHaveCount(0);
  await expect(page.locator('body')).not.toBeEmpty();
  await page.waitForLoadState('networkidle');
  expect(erreursConsole.filter((message) => !message.includes('favicon'))).toEqual([]);

  return erreursConsole;
}

test.describe('release review — reprise de session iPad', () => {
  test('le compte établissement review ouvre son tableau de bord', async ({ page }) => {
    const erreursConsole = await connecterCompteReview(page, {
      email: process.env.REVIEW_ETAB_EMAIL,
      password: process.env.REVIEW_ETAB_PASSWORD,
      destination: /\/etablissement\/tableau-de-bord/,
    });
    await expect(page.getByRole('heading').first()).toBeVisible();
    expect(erreursConsole.filter((message) => !message.includes('favicon'))).toEqual([]);
  });

  test('le compte soignant démo ouvre son tableau de bord et ses présences', async ({ page }) => {
    const erreursConsole = await connecterCompteReview(page, {
      email: process.env.REVIEW_SOIGNANT_EMAIL,
      password: process.env.REVIEW_SOIGNANT_PASSWORD,
      destination: /\/soignant\/tableau-de-bord/,
    });
    await page.goto('/soignant/presences?tab=avenir');
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('heading', { name: 'Mes présences' })).toBeVisible();
    await expect(page.getByText(/Votre espace est momentanément indisponible/i)).toHaveCount(0);
    expect(erreursConsole.filter((message) => !message.includes('favicon'))).toEqual([]);
  });
});

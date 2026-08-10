import { expect, test, type Page } from '@playwright/test';
import { TEST_ACCOUNTS, type TestAccountKey } from './helpers/auth';

type ReviewAccount = {
  email: string;
  password: string;
  destination: RegExp;
  source: 'review' | 'fallback-ci';
};

function obtenirCompteReview(
  role: 'ETAB' | 'SOIGNANT',
  fallback: TestAccountKey,
  destination: RegExp,
): ReviewAccount | null {
  const email = process.env[`REVIEW_${role}_EMAIL`];
  const password = process.env[`REVIEW_${role}_PASSWORD`];

  if (Boolean(email) !== Boolean(password)) {
    throw new Error(`Configuration REVIEW_${role} partielle : email et mot de passe sont tous les deux requis.`);
  }

  if (email && password) return { email, password, destination, source: 'review' };

  // La CI doit toujours exécuter la reprise de session. En l'absence des
  // identifiants App Review, elle emploie les comptes Playwright canoniques et
  // signale explicitement ce repli dans le rapport au lieu de masquer le test.
  if (process.env.CI === 'true') {
    const compteFallback = TEST_ACCOUNTS[fallback];
    if (!compteFallback.password) {
      throw new Error(`Mot de passe du compte Playwright ${fallback} absent de la CI.`);
    }
    return {
      email: compteFallback.email,
      password: compteFallback.password,
      destination,
      source: 'fallback-ci',
    };
  }

  return null;
}

async function connecterCompteReview(page: Page, compte: ReviewAccount) {
  if (compte.source === 'fallback-ci') {
    test.info().annotations.push({
      type: 'review-account-fallback',
      description: `Identifiants App Review absents : smoke exécuté avec ${compte.email}.`,
    });
  }

  const erreursConsole: string[] = [];
  const statutsAuth: number[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') erreursConsole.push(message.text());
  });
  page.on('pageerror', (error) => erreursConsole.push(error.message));
  page.on('response', (response) => {
    if (response.url().includes('/auth/v1/token')) statutsAuth.push(response.status());
  });

  await page.goto('/connexion');
  await page.locator('input[type="email"]').fill(compte.email);
  await page.locator('input[type="password"]').first().fill(compte.password);
  await page.getByTestId('login-submit').click();

  await expect(
    page,
    `La connexion ${compte.email} n'a pas abouti (réponses Supabase Auth : ${statutsAuth.join(', ') || 'aucune'}).`,
  ).toHaveURL(compte.destination, { timeout: 20_000 });
  await expect(page.getByText(/Votre espace est momentanément indisponible/i)).toHaveCount(0);
  await expect(page.locator('body')).not.toBeEmpty();
  await page.waitForLoadState('networkidle');
  expect(erreursConsole.filter((message) => !message.includes('favicon'))).toEqual([]);

  return erreursConsole;
}

async function verifierSansDebordementHorizontal(page: Page, route: string) {
  const dimensions = await page.evaluate(() => ({
    largeurDocument: document.documentElement.scrollWidth,
    largeurViewport: window.innerWidth,
  }));
  expect(
    dimensions.largeurDocument,
    `${route} déborde horizontalement sur iPad`,
  ).toBeLessThanOrEqual(dimensions.largeurViewport + 1);
}

test.describe('release review — reprise de session iPad', () => {
  test('les pages publiques critiques restent lisibles sur iPad', async ({ page }) => {
    for (const route of ['/tarifs', '/cgu', '/cgv', '/mentions-legales', '/confidentialite', '/aide']) {
      await page.goto(route);
      await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
      await verifierSansDebordementHorizontal(page, route);
    }
  });

  test('l’inscription soignant expose les consentements et champs essentiels sur iPad', async ({ page }) => {
    await page.goto('/inscription/soignant');
    await expect(page.getByRole('heading', { name: /Inscription Soignant/i })).toBeVisible();
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await expect(page.locator('input[type="password"]').first()).toBeVisible();
    await expect(page.getByRole('checkbox').first()).toBeVisible();
    await verifierSansDebordementHorizontal(page, '/inscription/soignant');
  });

  test('le compte établissement review ouvre son tableau de bord', async ({ page }) => {
    const compte = obtenirCompteReview('ETAB', 'etab', /\/etablissement\/tableau-de-bord/);
    test.skip(!compte, 'Identifiants review absents en local ; la CI utilise un fallback explicite.');
    if (!compte) return;

    const erreursConsole = await connecterCompteReview(page, compte);
    await expect(page.getByRole('heading').first()).toBeVisible();

    // Reproduire la navigation réelle de l'iPad dans la SPA. Un rechargement
    // complet ici annule les lectures encore actives du dashboard et WebKit les
    // remonte à tort comme erreurs « due to access control checks ».
    const sidebar = page.getByRole('navigation', { name: 'Sidebar' });
    await sidebar.getByRole('button', { name: 'Publier une mission', exact: true }).click();
    await expect(page).toHaveURL(/\/etablissement\/missions\/creer$/);
    await expect(page.getByRole('heading', { name: /Publier une mission/i })).toBeVisible();
    await expect(page.getByLabel('Intitulé *')).toBeVisible();
    await expect(page.getByText('Type de contrat proposé')).toBeVisible();
    await verifierSansDebordementHorizontal(page, '/etablissement/missions/creer');

    await sidebar.getByRole('button', { name: 'Soignants', exact: true }).click();
    await sidebar.getByRole('button', { name: 'Pool urgence', exact: true }).click();
    await expect(page).toHaveURL(/\/etablissement\/pool-urgence$/);
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('heading', { name: /Pool d'urgence/i })).toBeVisible();
    await verifierSansDebordementHorizontal(page, '/etablissement/pool-urgence');
    expect(erreursConsole.filter((message) => !message.includes('favicon'))).toEqual([]);
  });

  test('le compte soignant démo ouvre son tableau de bord et ses présences', async ({ page }) => {
    const compte = obtenirCompteReview('SOIGNANT', 'soignant', /\/soignant\/tableau-de-bord/);
    test.skip(!compte, 'Identifiants review absents en local ; la CI utilise un fallback explicite.');
    if (!compte) return;

    const erreursConsole = await connecterCompteReview(page, compte);
    // Reproduire le vrai parcours App Review dans la SPA. Un `page.goto`
    // rechargeait tout le document juste après le dashboard : WebKit annulait
    // alors les requêtes Supabase encore actives et les remontait à tort comme
    // erreurs « due to access control checks ».
    await page.getByRole('button', { name: 'Activité' }).click();
    await page.getByRole('button', { name: 'Présences' }).click();
    await expect(page).toHaveURL(/\/soignant\/presences$/);
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('heading', { name: 'Mes présences' })).toBeVisible();
    await expect(page.getByText(/Votre espace est momentanément indisponible/i)).toHaveCount(0);

    await page.goto('/soignant/mes-documents?tab=justificatifs');
    await expect(page.getByRole('heading', { name: 'Mes documents' })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Justificatifs' })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'DPAE' })).toBeVisible();
    await verifierSansDebordementHorizontal(page, '/soignant/mes-documents');

    await page.goto('/soignant/profil');
    await expect(page.getByRole('heading').first()).toBeVisible();
    await verifierSansDebordementHorizontal(page, '/soignant/profil');
    expect(erreursConsole.filter((message) => !message.includes('favicon'))).toEqual([]);
  });
});

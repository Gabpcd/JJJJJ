import { expect, test, type APIResponse, type Page, type Response, type TestInfo } from '@playwright/test';

const PASSWORD = 'Playwright!Test2026';
const VIEWPORTS = [
  { name: 'iPhone-SE', width: 360, height: 780 },
  { name: 'iPhone-mini', width: 375, height: 812 },
  { name: 'iPhone-standard', width: 390, height: 844 },
  { name: 'iPhone-16-Pro-Max', width: 440, height: 956 },
  { name: 'Pixel-7', width: 412, height: 915 },
] as const;

function uniqueEmail(role: 'soignant' | 'etab') {
  const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  return `playwright-test-${role}-${suffix}@jolene.app`;
}

function uniqueValidSiret() {
  const seed = `${Date.now()}${Math.floor(Math.random() * 10_000)}`.replace(/\D/g, '');
  const base = (`9900000000000${seed}`).slice(-13);
  let sum = 0;
  for (let index = 0; index < base.length; index += 1) {
    let digit = Number(base[index]);
    if (index % 2 === 0) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return `${base}${(10 - (sum % 10)) % 10}`;
}

async function expectMobileFormIntegrity(page: Page, route: string, testInfo: TestInfo) {
  const result = await page.evaluate(() => {
    const viewportWidth = document.documentElement.clientWidth;
    const interactive = Array.from(document.querySelectorAll<HTMLElement>(
      'input, select, textarea, button, [role="button"], [role="combobox"]',
    )).filter((element) => {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      return style.display !== 'none'
        && style.visibility !== 'hidden'
        && Number(style.opacity) > 0
        && rect.width > 0
        && rect.height > 0;
    });

    return {
      route: location.pathname,
      viewportWidth,
      scrollWidth: document.documentElement.scrollWidth,
      inputsBelow16px: interactive
        .filter((element) => element.matches('input, select, textarea'))
        .filter((element) => Number.parseFloat(getComputedStyle(element).fontSize) < 16)
        .map((element) => ({
          type: element.getAttribute('type') || element.tagName.toLowerCase(),
          fontSize: getComputedStyle(element).fontSize,
        })),
      offscreenControls: interactive
        .map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            label: element.getAttribute('aria-label') || element.textContent?.trim().slice(0, 80) || element.getAttribute('placeholder') || element.tagName,
            left: rect.left,
            right: rect.right,
          };
        })
        .filter(({ left, right }) => left < -1 || right > viewportWidth + 1),
    };
  });

  await testInfo.attach(`signup-${route.replaceAll('/', '-')}-${page.viewportSize()?.width}.json`, {
    body: Buffer.from(JSON.stringify(result, null, 2)),
    contentType: 'application/json',
  });
  expect(result.scrollWidth, `${route}: aucun débordement horizontal`).toBeLessThanOrEqual(result.viewportWidth + 1);
  expect(result.inputsBelow16px, `${route}: champs à 16 px minimum sur iOS`).toEqual([]);
  expect(result.offscreenControls, `${route}: contrôles intégralement dans le viewport`).toEqual([]);
}

async function fillCredentials(page: Page, email: string, legalCheckboxCount: number) {
  const consent = page.getByRole('button', { name: 'Accepter', exact: true });
  if (await consent.isVisible().catch(() => false)) await consent.click();
  await page.locator('input[type="email"]').fill(email);
  await page.locator('input[type="password"]').first().fill(PASSWORD);
  await page.locator('input[type="password"]').nth(1).fill(PASSWORD);
  const checkboxes = page.locator('input[type="checkbox"]');
  for (let index = 0; index < legalCheckboxCount; index += 1) await checkboxes.nth(index).check();
  await expect(page.getByRole('button', { name: 'Continuer', exact: true })).toBeEnabled();
  await page.getByRole('button', { name: 'Continuer', exact: true }).click();
}

async function fillSoignantProfile(page: Page) {
  await page.locator('label').filter({ hasText: /^Prénom/ }).locator('input').fill('Camille');
  await page.locator('label').filter({ hasText: /^Nom/ }).locator('input').fill('Audit');
  await page.locator('input[type="tel"]').fill('+33612345678');
  await page.locator('input[type="date"]').fill('1990-05-15');
  await page.locator('#profession-select').click();
  await page.getByTestId('profession-option-AS').click();
  await page.getByRole('checkbox', { name: 'Contrat à Durée Déterminée (CDD)' }).click();
  await expect(page.getByRole('button', { name: 'Créer mon compte' })).toBeEnabled({ timeout: 10_000 });
}

async function fillEtablissementProfile(page: Page, siret: string) {
  await page.getByText("Nom de l'établissement *", { exact: true }).locator('..').locator('input').fill('Clinique Audit Jolene');
  const siretInput = page.getByText('SIRET * (14 chiffres)', { exact: true }).locator('..').locator('input');
  await siretInput.fill(siret);
  await siretInput.blur();
  await page.locator('select').selectOption({ index: 1 });
  await page.locator('input[placeholder="Ville"]').fill('Paris');
  await expect(page.getByRole('button', { name: 'Créer le compte' })).toBeEnabled({ timeout: 10_000 });
}

async function responseDiagnostic(response: Response | APIResponse) {
  const raw = await response.json().catch(() => ({})) as Record<string, unknown>;
  return {
    status: response.status(),
    ok: response.ok(),
    code: raw.error_code ?? raw.code ?? null,
    message: raw.msg ?? raw.message ?? raw.error ?? null,
  };
}

function captureSignupDiagnostics(page: Page) {
  const events: string[] = [];
  const sanitize = (value: string) => value
    .replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, '<uuid>')
    .replace(/playwright-test-[^\s@]+@jolene\.app/gi, '<test-email>');
  page.on('console', (message) => {
    const text = message.text();
    if (text.includes('[INSCRIPTION]') || text.includes('[ERROR]')) events.push(sanitize(text));
  });
  page.on('requestfailed', (request) => {
    if (request.url().includes('/auth/') || request.url().includes('/functions/')) {
      events.push(`requestfailed ${request.method()} ${request.url().replace(/^https?:\/\/[^/]+/, '')} ${request.failure()?.errorText || ''}`);
    }
  });
  return events;
}

test.describe('inscriptions mobile Série C', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      // Le bandeau web arrive après 1,5 s et peut masquer l'étape 2. Dans la
      // coquille native il n'existe pas ; mémoriser ici le choix déjà exprimé
      // isole donc bien le funnel mobile testé.
      localStorage.setItem('cookie-consent', 'accepted');
    });
  });

  test('les deux funnels restent intègres sur la matrice mobile', async ({ page }, testInfo) => {
    test.setTimeout(90_000);
    for (const viewport of VIEWPORTS) {
      await page.setViewportSize({ width: viewport.width, height: viewport.height });

      await page.goto('/inscription/soignant');
      await expectMobileFormIntegrity(page, `/inscription/soignant-etape-1-${viewport.name}`, testInfo);
      await fillCredentials(page, uniqueEmail('soignant'), 1);
      await fillSoignantProfile(page);
      await expectMobileFormIntegrity(page, `/inscription/soignant-etape-2-${viewport.name}`, testInfo);

      await page.goto('/inscription/etablissement');
      await expectMobileFormIntegrity(page, `/inscription/etablissement-etape-1-${viewport.name}`, testInfo);
      await fillCredentials(page, uniqueEmail('etab'), 2);
      await fillEtablissementProfile(page, uniqueValidSiret());
      await expectMobileFormIntegrity(page, `/inscription/etablissement-etape-2-${viewport.name}`, testInfo);
    }
  });

  test('inscription soignant réelle : UI → Auth → Edge Function → dashboard', async ({ page }) => {
    test.setTimeout(60_000);
    await page.setViewportSize({ width: 390, height: 844 });
    const events = captureSignupDiagnostics(page);
    await page.goto('/inscription/soignant');
    await fillCredentials(page, uniqueEmail('soignant'), 1);
    await fillSoignantProfile(page);
    const signupResponse = page.waitForResponse((response) => response.url().includes('/auth/v1/signup'));
    const registerResponse = page.waitForResponse(
      (response) => response.url().includes('/functions/v1/register-soignant'),
      { timeout: 30_000 },
    ).catch(() => null);
    await page.getByRole('button', { name: 'Créer mon compte' }).click();

    const signup = await responseDiagnostic(await signupResponse);
    expect(signup, 'GoTrue signup').toMatchObject({ status: 200, ok: true });
    const registerRaw = await registerResponse;
    expect(registerRaw, `register-soignant absent après signup: ${JSON.stringify(signup)}; événements: ${JSON.stringify(events)}`).not.toBeNull();
    const register = await responseDiagnostic(registerRaw!);
    expect(register, 'register-soignant').toMatchObject({ status: 200, ok: true });
    await expect(page).toHaveURL(/\/inscription\/succes\?role=soignant/, { timeout: 30_000 });
    await expect(page.getByRole('heading', { name: 'Bienvenue sur Jolene !' })).toBeVisible();
    await page.getByRole('button', { name: /Compléter mon profil/ }).click();
    await expect(page).toHaveURL(/\/soignant\/tableau-de-bord/);
  });

  test('inscription établissement réelle : UI → Auth → Edge Function → dashboard', async ({ page }) => {
    test.setTimeout(60_000);
    await page.setViewportSize({ width: 390, height: 844 });
    const events = captureSignupDiagnostics(page);
    await page.goto('/inscription/etablissement');
    await fillCredentials(page, uniqueEmail('etab'), 2);
    await fillEtablissementProfile(page, uniqueValidSiret());
    const signupResponse = page.waitForResponse((response) => response.url().includes('/auth/v1/signup'));
    const registerResponse = page.waitForResponse(
      (response) => response.url().includes('/functions/v1/register-etablissement'),
      { timeout: 30_000 },
    ).catch(() => null);
    await page.getByRole('button', { name: 'Créer le compte' }).click();

    const signup = await responseDiagnostic(await signupResponse);
    expect(signup, 'GoTrue signup').toMatchObject({ status: 200, ok: true });
    const registerRaw = await registerResponse;
    expect(registerRaw, `register-etablissement absent après signup: ${JSON.stringify(signup)}; événements: ${JSON.stringify(events)}`).not.toBeNull();
    const register = await responseDiagnostic(registerRaw!);
    expect(register, 'register-etablissement').toMatchObject({ status: 200, ok: true });
    await expect(page).toHaveURL(/\/inscription\/succes\?role=etab/, { timeout: 30_000 });
    await expect(page.getByRole('heading', { name: 'Bienvenue sur Jolene !' })).toBeVisible();
    await page.getByRole('button', { name: /Publier ma première mission/ }).click();
    await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord/);
  });
});

import {
  expect,
  test,
  type APIResponse,
  type ConsoleMessage,
  type Page,
  type Response,
  type TestInfo,
} from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { runAxe } from '../helpers/axe';
import { ROUTES_ETABLISSEMENT, ROUTES_SOIGNANT } from '../helpers/ios-series-c-routes';

const PASSWORD = 'Playwright!Test2026';
const VIEWPORTS = [
  { name: 'iPhone-SE', width: 360, height: 780 },
  { name: 'iPhone-mini', width: 375, height: 812 },
  { name: 'iPhone-standard', width: 390, height: 844 },
  { name: 'iPhone-16-Pro-Max', width: 440, height: 956 },
  { name: 'Pixel-7', width: 412, height: 915 },
] as const;

const FRESH_ACCOUNT_IPHONE_VIEWPORTS = [
  { name: 'iPhone-compact', width: 375, height: 667 },
  { name: 'iPhone-standard', width: 390, height: 844 },
  { name: 'iPhone-16-Pro-Max', width: 440, height: 956 },
] as const;

const FRESH_ACCOUNT_ANDROID_VIEWPORTS = [
  { name: 'Pixel-7', width: 412, height: 915 },
] as const;

function freshAccountViewports(testInfo: TestInfo) {
  return testInfo.project.name === 'android-pixel-audit'
    ? FRESH_ACCOUNT_ANDROID_VIEWPORTS
    : FRESH_ACCOUNT_IPHONE_VIEWPORTS;
}

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
  // IDE ouvre le périmètre fonctionnel le plus large, notamment le parcours
  // « Passer en libéral ». Un profil AS y est redirigé par règle métier et ne
  // permet donc pas d'en auditer l'état de premier accès.
  await page.getByTestId('profession-option-IDE').click();
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

type FreshAccountRole = 'soignant' | 'etab';

type FreshAccountRouteAudit = {
  route: string;
  finalUrl: string;
  viewport: string;
  horizontalOverflow: number;
  inputsBelow16px: Array<{ label: string; fontSize: number }>;
  offscreenControls: Array<{ label: string; left: number; right: number }>;
  smallTouchTargets: Array<{
    label: string;
    width: number;
    height: number;
    tag: string;
    className: string;
  }>;
  tinyTexts: Array<{ text: string; fontSize: number }>;
  duplicateBackButtons: number;
  consoleErrors: string[];
  pageErrors: string[];
  apiErrors: Array<{ status: number; path: string }>;
};

async function settleFreshAccountDashboard(page: Page) {
  await expect(page.locator('#main-content')).toBeVisible();
  await page.waitForLoadState('networkidle', { timeout: 5_000 }).catch(() => undefined);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(500);
}

async function auditFreshAccountRoute(
  page: Page,
  role: FreshAccountRole,
  route: string,
): Promise<FreshAccountRouteAudit> {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  const apiErrors: Array<{ status: number; path: string }> = [];
  const onConsole = (message: ConsoleMessage) => {
    if (message.type() !== 'error') return;
    const source = message.location().url;
    const stripeCspNoise = /^https:\/\/(?:[^/]+\.)?stripe\.(?:com|network)\//.test(source)
      && message.text().includes('Refused to apply a stylesheet')
      && message.text().includes('Content Security Policy');
    if (!stripeCspNoise) consoleErrors.push(`${source || 'source-inconnue'} :: ${message.text()}`);
  };
  const onPageError = (error: Error) => {
    if (!error.message.includes('due to access control checks')) pageErrors.push(error.message);
  };
  const onResponse = (response: Response) => {
    if (response.status() < 400) return;
    const url = new URL(response.url());
    if (url.hostname.endsWith('.supabase.co')) {
      apiErrors.push({ status: response.status(), path: url.pathname });
    }
  };
  page.on('console', onConsole);
  page.on('pageerror', onPageError);
  page.on('response', onResponse);

  try {
    await page.goto(route, { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle', { timeout: 3_000 }).catch(() => undefined);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(500);
    await expect(page.locator('#main-content, #app-route-content, main, body').first()).toBeVisible();
    await expect.poll(
      async () => (await page.locator('body').innerText()).trim().length,
      { message: `${route} doit rendre un contenu visible` },
    ).toBeGreaterThan(0);

    if (role === 'etab' && route === '/etablissement/tableau-de-bord') {
      const onboardingBanner = page.getByTestId('onboarding-etab-banner');
      await expect(onboardingBanner).toBeVisible();
      const accessibility = await runAxe(page, { include: '[data-testid="onboarding-etab-banner"]' });
      expect.soft(
        accessibility.violations
          .filter(({ id }) => id === 'color-contrast')
          .map(({ id, impact, nodes }) => ({ id, impact, nodes: nodes.map(({ html }) => html) })),
        'le bandeau établissement post-inscription doit conserver un contraste WCAG AA',
      ).toEqual([]);
    }

    const metrics = await page.evaluate(() => {
      const visible = (element: Element) => {
        if (element.getAttribute('aria-hidden') === 'true' || element.closest('[aria-hidden="true"]')) {
          return false;
        }
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none'
          && style.visibility !== 'hidden'
          && Number(style.opacity) > 0
          && rect.width > 0
          && rect.height > 0;
      };
      const labelOf = (element: Element) => (
        element.getAttribute('aria-label')
        || element.getAttribute('title')
        || (element.textContent || '').replace(/\s+/g, ' ').trim()
        || element.tagName.toLowerCase()
      ).slice(0, 100);
      const controls = Array.from(document.querySelectorAll(
        'button, input, select, textarea, [role="button"], [role="tab"], [role="switch"]',
      )).filter(visible);
      const editable = Array.from(document.querySelectorAll('input, select, textarea')).filter(visible);
      const textNodes = Array.from(document.querySelectorAll(
        'p, span, label, small, li, td, th, h1, h2, h3, h4',
      )).filter((element) => visible(element) && (element.textContent || '').trim().length > 0);
      const belongsToHorizontalScroller = (element: Element) => {
        let current = element.parentElement;
        while (current && current !== document.body) {
          const style = getComputedStyle(current);
          if ((style.overflowX === 'auto' || style.overflowX === 'scroll')
            && current.scrollWidth > current.clientWidth + 1) return true;
          current = current.parentElement;
        }
        return false;
      };

      const inputsBelow16px = editable
        .map((element) => ({
          label: labelOf(element),
          fontSize: Number.parseFloat(getComputedStyle(element).fontSize),
        }))
        .filter(({ fontSize }) => fontSize < 16);
      const offscreenControls = controls
        .map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            label: labelOf(element),
            left: rect.left,
            right: rect.right,
            intentionalScroller: belongsToHorizontalScroller(element),
          };
        })
        .filter(({ left, right, intentionalScroller }) => !intentionalScroller
          && (left < -1 || right > window.innerWidth + 1))
        .map(({ label, left, right }) => ({ label, left, right }));
      const smallTouchTargets = controls
        .map((element) => {
          const ownRect = element.getBoundingClientRect();
          const enclosingLabel = element.closest('label');
          const associatedLabel = element.id
            ? document.querySelector(`label[for="${CSS.escape(element.id)}"]`)
            : null;
          const effectiveLabel = enclosingLabel ?? associatedLabel;
          const labelRect = effectiveLabel && visible(effectiveLabel)
            ? effectiveLabel.getBoundingClientRect()
            : null;
          const rect = labelRect
            && labelRect.width >= ownRect.width
            && labelRect.height >= ownRect.height
            ? labelRect
            : ownRect;
          return {
            label: labelOf(element),
            width: Math.round(rect.width),
            height: Math.round(rect.height),
            tag: element.tagName.toLowerCase(),
            className: element instanceof HTMLElement ? element.className : '',
          };
        })
        .filter(({ width, height }) => width < 44 || height < 44)
        .slice(0, 40);
      const tinyTexts = textNodes
        .map((element) => ({
          text: (element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 100),
          fontSize: Number.parseFloat(getComputedStyle(element).fontSize),
        }))
        .filter(({ fontSize }) => fontSize < 11)
        .slice(0, 40);
      const visibleBackButtons = Array.from(document.querySelectorAll('button'))
        .filter((button) => visible(button) && /^Retour$/.test((button.textContent || '').trim()));

      return {
        horizontalOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        inputsBelow16px,
        offscreenControls,
        smallTouchTargets,
        tinyTexts,
        duplicateBackButtons: Math.max(0, visibleBackButtons.length - 1),
      };
    });

    const viewport = page.viewportSize();
    const viewportLabel = `${viewport?.width || 0}x${viewport?.height || 0}`;
    const screenshotDirectory = process.env.UX_FRESH_ACCOUNT_SCREENSHOTS_DIR;
    if (screenshotDirectory) {
      await mkdir(screenshotDirectory, { recursive: true });
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(100);
      const routeSlug = route
        .replace(/^\//, '')
        .replace(/[/?=&]+/g, '-')
        .replace(/[^a-z0-9-]+/gi, '-')
        .replace(/^-+|-+$/g, '') || 'accueil';
      await page.screenshot({
        path: path.join(screenshotDirectory, `${role}-${viewportLabel}-${routeSlug}.png`),
        fullPage: false,
        animations: 'disabled',
      });
    }

    return {
      route,
      finalUrl: new URL(page.url()).pathname + new URL(page.url()).search,
      viewport: viewportLabel,
      ...metrics,
      consoleErrors,
      pageErrors,
      apiErrors,
    };
  } finally {
    page.off('console', onConsole);
    page.off('pageerror', onPageError);
    page.off('response', onResponse);
  }
}

async function auditFreshAccountRoutes(
  page: Page,
  testInfo: TestInfo,
  role: FreshAccountRole,
  routes: readonly string[],
) {
  await settleFreshAccountDashboard(page);
  const results: FreshAccountRouteAudit[] = [];
  for (const viewport of freshAccountViewports(testInfo)) {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    for (const route of routes) results.push(await auditFreshAccountRoute(page, role, route));
  }

  await testInfo.attach(`audit-compte-neuf-${role}.json`, {
    body: Buffer.from(JSON.stringify(results, null, 2)),
    contentType: 'application/json',
  });

  expect.soft(results.filter(({ route, finalUrl }) => route !== finalUrl)
    .map(({ route, finalUrl, viewport }) => ({ route, finalUrl, viewport })),
  `le compte ${role} neuf doit atteindre chaque route demandée`).toEqual([]);
  expect.soft(results.filter(({ horizontalOverflow }) => horizontalOverflow > 1)
    .map(({ route, horizontalOverflow, viewport }) => ({ route, horizontalOverflow, viewport })),
  `aucun écran du compte ${role} neuf ne doit déborder`).toEqual([]);
  expect.soft(results.filter(({ inputsBelow16px }) => inputsBelow16px.length > 0)
    .map(({ route, inputsBelow16px, viewport }) => ({ route, inputsBelow16px, viewport })),
  `les champs du compte ${role} neuf doivent rester à 16 px minimum`).toEqual([]);
  expect.soft(results.filter(({ offscreenControls }) => offscreenControls.length > 0)
    .map(({ route, offscreenControls, viewport }) => ({ route, offscreenControls, viewport })),
  `aucun contrôle du compte ${role} neuf ne doit sortir du viewport`).toEqual([]);
  expect.soft(results.filter(({ smallTouchTargets }) => smallTouchTargets.length > 0)
    .map(({ route, smallTouchTargets, viewport }) => ({ route, smallTouchTargets, viewport })),
  `les cibles tactiles du compte ${role} neuf doivent mesurer au moins 44 × 44 px`).toEqual([]);
  expect.soft(results.filter(({ tinyTexts }) => tinyTexts.length > 0)
    .map(({ route, tinyTexts, viewport }) => ({ route, tinyTexts, viewport })),
  `aucun texte du compte ${role} neuf ne doit descendre sous 11 px`).toEqual([]);
  expect.soft(results.filter(({ duplicateBackButtons }) => duplicateBackButtons > 0)
    .map(({ route, duplicateBackButtons, viewport }) => ({ route, duplicateBackButtons, viewport })),
  `aucun écran du compte ${role} neuf ne doit dupliquer le bouton retour`).toEqual([]);
  expect.soft(results.filter(({ consoleErrors, pageErrors, apiErrors }) => (
    consoleErrors.length > 0 || pageErrors.length > 0 || apiErrors.length > 0
  )).map(({ route, viewport, consoleErrors, pageErrors, apiErrors }) => ({
    route,
    viewport,
    consoleErrors,
    pageErrors,
    apiErrors,
  })), `aucun écran du compte ${role} neuf ne doit lever d'erreur runtime ou API`).toEqual([]);
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

  test('inscription soignant réelle : UI → Auth → Edge Function → tous les écrans', async ({ page }, testInfo) => {
    test.setTimeout(360_000);
    const [signupViewport] = freshAccountViewports(testInfo);
    await page.setViewportSize({ width: signupViewport.width, height: signupViewport.height });
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
    await auditFreshAccountRoutes(page, testInfo, 'soignant', ROUTES_SOIGNANT);
  });

  test('inscription établissement réelle : UI → Auth → Edge Function → tous les écrans', async ({ page }, testInfo) => {
    test.setTimeout(360_000);
    const [signupViewport] = freshAccountViewports(testInfo);
    await page.setViewportSize({ width: signupViewport.width, height: signupViewport.height });
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
    await auditFreshAccountRoutes(page, testInfo, 'etab', ROUTES_ETABLISSEMENT);
  });
});

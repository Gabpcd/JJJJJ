import {
  expect,
  test,
  type APIResponse,
  type ConsoleMessage,
  type Page,
  type Request,
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

async function fillQuickAccount(page: Page, email: string, role: FreshAccountRole) {
  const consent = page.getByRole('button', { name: 'Accepter', exact: true });
  if (await consent.isVisible().catch(() => false)) await consent.click();
  await expect(page.getByRole('heading', { name: 'Créez votre compte.' })).toBeVisible();
  await expect(page.locator('form input:not([type="checkbox"]):not([type="hidden"]), form select')).toHaveCount(3);
  await expect(page.locator('input[type="password"]')).toHaveCount(1);
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Mot de passe', { exact: true }).fill(PASSWORD);
  if (role === 'soignant') {
    // IDE ouvre ensuite tout le périmètre, dont « Passer en libéral ».
    await page.getByLabel('Profession', { exact: true }).selectOption('IDE');
    await expect(page.getByLabel('Profession', { exact: true })).toHaveValue('IDE');
  } else {
    await page.getByLabel('Nom de l’établissement', { exact: true }).fill('Clinique Audit Jolene');
    await expect(page.getByLabel('Nom de l’établissement', { exact: true })).toHaveValue('Clinique Audit Jolene');
    await page.locator('#cgv').check();
  }
  await page.locator('#cgu').check();
  await expect(page.getByLabel('Email', { exact: true })).toHaveValue(email);
  await expect(page.getByLabel('Mot de passe', { exact: true })).toHaveValue(PASSWORD);
  await expect(page.getByRole('button', { name: 'Créer mon compte', exact: true })).toBeEnabled();
}

async function fillSoignantProfile(page: Page) {
  await expect(page.getByRole('heading', { name: 'Vos informations professionnelles' })).toBeVisible();
  await expect(page.locator('input[type="email"], input[type="password"]')).toHaveCount(0);
  await page.locator('label').filter({ hasText: /^Prénom/ }).locator('input').fill('Camille');
  await page.locator('label').filter({ hasText: /^Nom/ }).locator('input').fill('Audit');
  await page.locator('input[type="tel"]').fill('+33612345678');
  await page.locator('input[type="date"]').fill('1990-05-15');
  await expect(page.locator('#profession-select'), 'la profession du compte rapide est reprise').toContainText('(IDE)');
  await page.getByRole('checkbox', { name: 'Contrat à Durée Déterminée (CDD)' }).check();
  await expect(page.getByRole('button', { name: 'Enregistrer mon profil', exact: true })).toBeEnabled();
}

async function fillEtablissementProfile(page: Page, siret: string) {
  await expect(page.getByRole('heading', { name: 'Identifier votre établissement' })).toBeVisible();
  await expect(page.locator('input[type="email"], input[type="password"]')).toHaveCount(0);
  await expect(page.locator('#profil-nom'), 'le nom du compte rapide est repris').toHaveValue('Clinique Audit Jolene');
  await page.locator('#profil-nom').fill('Clinique Audit Jolene');
  const siretInput = page.locator('#profil-siret');
  await siretInput.fill(siret);
  await siretInput.blur();
  await page.locator('#profil-type').selectOption('CLINIQUE_PRIVEE');
  await page.locator('#profil-ville').fill('Paris');
  await expect(page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true })).toBeEnabled();
}

async function responseDiagnostic(response: Response | APIResponse) {
  const raw = await response.json().catch(() => ({})) as Record<string, unknown>;
  return {
    status: response.status(),
    ok: response.ok(),
    code: raw.error_code ?? raw.code ?? null,
    message: raw.msg ?? raw.message ?? raw.error ?? null,
    hasSession: typeof raw.access_token === 'string' && raw.access_token.length > 0,
    businessOk: raw.ok ?? raw.success ?? null,
    verification: raw.statut_verification ?? null,
    canPublish: raw.peut_publier_missions ?? null,
    verificationRequired: raw.verification_complete_requise ?? null,
  };
}

async function handleStagingEmailRateLimit(
  page: Page,
  signup: Awaited<ReturnType<typeof responseDiagnostic>>,
  role: FreshAccountRole,
  testInfo: TestInfo,
) {
  if (signup.status !== 429) return false;

  const rateLimit = page.getByRole('alert').filter({ hasText: /rate|limit|quota|tentatives/i });
  await expect(rateLimit, 'le quota email staging doit produire une erreur explicite et actionnable').toBeVisible();
  await expect(page.getByRole('button', { name: 'Créer mon compte', exact: true })).toBeEnabled();
  await expect(page.getByLabel('Email', { exact: true })).not.toHaveValue('');
  await expectMobileFormIntegrity(page, `/inscription/${role}-quota-email`, testInfo);
  testInfo.annotations.push({
    type: 'quota staging',
    description: `GoTrue a refusé la création ${role} avec HTTP 429 ; l’UI de reprise est conforme, mais le compte neuf complet doit être rejoué après réouverture du quota email.`,
  });
  return true;
}

async function createQuickAccount(page: Page, role: FreshAccountRole, testInfo: TestInfo) {
  const registrations: string[] = [];
  const onRegister = (request: Request) => {
    if (/\/functions\/v1\/register-(soignant|etablissement)$/.test(new URL(request.url()).pathname)) {
      registrations.push(new URL(request.url()).pathname);
    }
  };
  page.on('request', onRegister);
  const roleResponse = page.waitForResponse(
    (response) => new URL(response.url()).pathname.endsWith('/rpc/fn_get_my_role'),
    { timeout: 30_000 },
  ).catch(() => null);
  try {
    const signupResponse = page.waitForResponse(
      (response) => response.request().method() === 'POST'
        && new URL(response.url()).pathname === '/auth/v1/signup',
    );
    await page.getByRole('button', { name: 'Créer mon compte', exact: true }).click();
    const signup = await responseDiagnostic(await signupResponse);
    await testInfo.attach(`signup-auth-${role}.json`, {
      body: Buffer.from(JSON.stringify(signup, null, 2)), contentType: 'application/json',
    });
    if (await handleStagingEmailRateLimit(page, signup, role, testInfo)) return false;
    expect(signup, 'GoTrue signup').toMatchObject({ status: 200, ok: true });

    if (!signup.hasSession) {
      await expect(page.getByRole('status').filter({ hasText: 'Un lien de confirmation' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'J’ai confirmé mon email', exact: true })).toBeVisible();
      await expect(page.getByLabel('Email', { exact: true })).not.toHaveValue('');
      await expectMobileFormIntegrity(page, `/inscription/${role}-confirmation-email`, testInfo);
      expect(registrations, 'aucun profil métier avant confirmation email').toEqual([]);
      const description = `Confirmation email requise pour ${role} : compte Auth créé sans session ; profil métier non créé et audit des écrans non exécuté. Confirmer le compte puis rejouer la recette complète.`;
      testInfo.annotations.push({ type: 'confirmation email requise', description });
      await testInfo.attach(`signup-${role}-confirmation-requise.txt`, {
        body: description, contentType: 'text/plain',
      });
      throw new Error(description);
    }

    await expect(page).toHaveURL(role === 'soignant'
      ? /\/soignant\/recherche-missions$/
      : /\/etablissement\/tableau-de-bord$/, { timeout: 30_000 });
    const navigation = page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
    await expect(navigation).toBeVisible();
    for (const label of role === 'soignant'
      ? ['Accueil', 'Explorer', 'Mes missions', 'Revenus', 'Profil']
      : ['Accueil', 'Missions', 'Publier', 'Messages', 'Menu']) {
      await expect(navigation.getByRole('button', { name: label, exact: true })).toBeVisible();
    }
    await expect(page.getByRole('heading', { name: /Vos informations professionnelles|Identifier votre établissement/ })).toHaveCount(0);
    const roleRaw = await roleResponse;
    expect(roleRaw, 'le compte rapide doit faire vérifier son rôle serveur').not.toBeNull();
    expect(roleRaw!.ok(), 'la vérification du rôle doit réussir').toBe(true);
    const roleData = await roleRaw!.json() as { role: string | null };
    expect([null, 'INCONNU'], 'le brouillon privé ne donne aucun rôle métier').toContain(roleData.role);
    expect(registrations, 'la création du compte rapide ne doit pas appeler register-*').toEqual([]);
    await expectMobileFormIntegrity(page, `/inscription/${role}-espace-prive`, testInfo);
    return true;
  } finally {
    page.off('request', onRegister);
  }
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
      // Le bandeau web arrive après 1,5 s et peut masquer le formulaire. Dans la
      // coquille native il n'existe pas ; mémoriser ici le choix déjà exprimé
      // isole donc bien le funnel mobile testé.
      localStorage.setItem('cookie-consent', 'accepted');
    });
  });

  test('les deux funnels restent intègres sur la matrice mobile', async ({ page }, testInfo) => {
    test.setTimeout(90_000);
    const signupRequests: string[] = [];
    page.on('request', (request) => {
      if (request.method() === 'POST' && new URL(request.url()).pathname === '/auth/v1/signup') {
        signupRequests.push(request.url());
      }
    });
    for (const viewport of VIEWPORTS) {
      await page.setViewportSize({ width: viewport.width, height: viewport.height });

      await page.goto('/inscription/soignant');
      await expectMobileFormIntegrity(page, `/inscription/soignant-vide-${viewport.name}`, testInfo);
      await fillQuickAccount(page, uniqueEmail('soignant'), 'soignant');
      await expectMobileFormIntegrity(page, `/inscription/soignant-trois-champs-${viewport.name}`, testInfo);

      await page.goto('/inscription/etablissement');
      await expectMobileFormIntegrity(page, `/inscription/etablissement-vide-${viewport.name}`, testInfo);
      await fillQuickAccount(page, uniqueEmail('etab'), 'etab');
      await expectMobileFormIntegrity(page, `/inscription/etablissement-trois-champs-${viewport.name}`, testInfo);
    }
    expect(signupRequests, 'la matrice de viewports ne crée aucun compte Auth').toEqual([]);
  });

  test('compte minimal réel : explorer et naviguer sans créer de profil métier', async ({ page }, testInfo) => {
    test.setTimeout(90_000);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/inscription/soignant');
    const email = uniqueEmail('soignant');
    await fillQuickAccount(page, email, 'soignant');
    const exploration = page.waitForResponse(response =>
      new URL(response.url()).pathname.endsWith('/rpc/fn_explorer_missions_inscription'),
    ).catch(() => null);
    expect(await createQuickAccount(page, 'soignant', testInfo), 'un vrai compte minimal est requis pour cette recette').toBe(true);
    const offres = await exploration;
    expect(offres, 'l’exploration doit appeler le serveur').not.toBeNull();
    expect(offres!.ok(), 'la vraie API doit autoriser l’exploration sans profil').toBe(true);
    await testInfo.attach('compte-minimal-recette.json', {
      body: JSON.stringify({ email }), contentType: 'application/json',
    });
    const navigation = page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
    for (const [label, route] of [
      ['Accueil', 'tableau-de-bord'], ['Mes missions', 'missions'],
      ['Revenus', 'mes-gains'], ['Profil', 'mon-compte'], ['Explorer', 'recherche-missions'],
    ]) {
      await navigation.getByRole('button', { name: label, exact: true }).click();
      await expect(page).toHaveURL(new RegExp(`/soignant/${route}$`));
      await expect(page.getByRole('heading', { name: 'Vos informations professionnelles' })).toHaveCount(0);
    }
    await page.reload();
    await expect(page).toHaveURL(/\/soignant\/recherche-missions$/);
    await expect(navigation).toBeVisible();
  });

  test('inscription soignant réelle : compte rapide → vraie app → profil volontaire → tous les écrans', async ({ page }, testInfo) => {
    test.setTimeout(360_000);
    const [signupViewport] = freshAccountViewports(testInfo);
    await page.setViewportSize({ width: signupViewport.width, height: signupViewport.height });
    const events = captureSignupDiagnostics(page);
    try {
      await page.goto('/inscription/soignant');
      await fillQuickAccount(page, uniqueEmail('soignant'), 'soignant');
      if (!await createQuickAccount(page, 'soignant', testInfo)) return;

      await page.getByRole('navigation', { name: 'Navigation mobile', exact: true })
        .getByRole('button', { name: 'Profil', exact: true }).click();
      await expect(page).toHaveURL(/\/soignant\/mon-compte$/);
      await page.getByRole('button', { name: 'Mon profil', exact: true }).click();
      await expect(page).toHaveURL(/\/inscription\/completer$/);
      await fillSoignantProfile(page);
      await expectMobileFormIntegrity(page, '/inscription/soignant-profil', testInfo);
      const registerResponse = page.waitForResponse(
        (response) => response.request().method() === 'POST'
          && new URL(response.url()).pathname === '/functions/v1/register-soignant',
        { timeout: 30_000 },
      ).catch(() => null);
      await page.getByRole('button', { name: 'Enregistrer mon profil', exact: true }).click();
      const registerRaw = await registerResponse;
      expect(registerRaw, `register-soignant absent après complétion ; événements: ${JSON.stringify(events)}`).not.toBeNull();
      const register = await responseDiagnostic(registerRaw!);
      await testInfo.attach('signup-register-soignant.json', {
        body: Buffer.from(JSON.stringify(register, null, 2)), contentType: 'application/json',
      });
      expect(register, 'register-soignant crée réellement le profil').toMatchObject({ status: 200, ok: true, businessOk: true });
      await expect(page).toHaveURL(/\/soignant\/recherche-missions$/, { timeout: 30_000 });
      await settleFreshAccountDashboard(page);
      await page.goto('/soignant/tableau-de-bord');
      await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
      await auditFreshAccountRoutes(page, testInfo, 'soignant', ROUTES_SOIGNANT);
    } finally {
      await testInfo.attach('signup-soignant-evenements.json', {
        body: Buffer.from(JSON.stringify(events, null, 2)), contentType: 'application/json',
      });
    }
  });

  test('inscription établissement réelle : compte rapide → vraie app → publier un brouillon → profil → tous les écrans', async ({ page }, testInfo) => {
    test.setTimeout(360_000);
    const [signupViewport] = freshAccountViewports(testInfo);
    await page.setViewportSize({ width: signupViewport.width, height: signupViewport.height });
    const events = captureSignupDiagnostics(page);
    try {
      await page.goto('/inscription/etablissement');
      await fillQuickAccount(page, uniqueEmail('etab'), 'etab');
      if (!await createQuickAccount(page, 'etab', testInfo)) return;

      const missionDate = new Date(Date.now() + 7 * 86_400_000).toISOString().slice(0, 10);
      const publier = () => page.getByRole('navigation', { name: 'Navigation mobile', exact: true })
        .getByRole('button', { name: 'Publier', exact: true }).click();
      await publier();
      await expect(page).toHaveURL(/\/etablissement\/missions\/creer$/);
      await page.getByLabel('Intitulé *', { exact: true }).fill('Renfort IDE — audit inscription');
      await page.locator('#mission-profession').click();
      await page.getByRole('option', { name: /Infirmier.*IDE/ }).click();
      await page.getByLabel(/Première date affichée/).fill(missionDate);
      await page.getByLabel(/Dernière date affichée/).fill(missionDate);
      await page.getByRole('button', { name: 'Toutes les dates', exact: true }).click();
      await page.getByLabel(`Début du créneau 1 du ${missionDate}`, { exact: true }).fill('07:00');
      await page.getByLabel(`Fin du créneau 1 du ${missionDate}`, { exact: true }).fill('19:00');
      await expect(page.getByText(/Veuillez compléter votre SIRET/)).toHaveCount(0);
      await expectMobileFormIntegrity(page, '/inscription/etablissement-brouillon', testInfo);
      const savedDraftResponse = page.waitForResponse(
        (response) => new URL(response.url()).pathname.endsWith('/rpc/fn_enregistrer_parcours_inscription'),
      );
      await page.getByRole('button', { name: /^Publier la mission/ }).click();
      expect((await savedDraftResponse).ok(), 'le brouillon doit être enregistré en SQL').toBe(true);
      await expect(page).toHaveURL(/\/inscription\/completer$/);
      await page.getByRole('button', { name: 'Retour', exact: true }).click();
      await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
      await publier();
      await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('Renfort IDE — audit inscription');
      await page.reload();
      await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('Renfort IDE — audit inscription');
      await expect(page.getByLabel(`Début du créneau 1 du ${missionDate}`, { exact: true })).toHaveValue('07:00');
      await expect(page.getByLabel(`Fin du créneau 1 du ${missionDate}`, { exact: true })).toHaveValue('19:00');
      await page.getByRole('button', { name: /^Publier la mission/ }).click();
      await expect(page).toHaveURL(/\/inscription\/completer$/);
      await fillEtablissementProfile(page, uniqueValidSiret());
      await expectMobileFormIntegrity(page, '/inscription/etablissement-profil', testInfo);
      const registerResponse = page.waitForResponse(
        (response) => response.request().method() === 'POST'
          && new URL(response.url()).pathname === '/functions/v1/register-etablissement',
        { timeout: 30_000 },
      ).catch(() => null);
      await page.getByRole('button', { name: 'Enregistrer mon établissement', exact: true }).click();
      const registerRaw = await registerResponse;
      expect(registerRaw, `register-etablissement absent après complétion ; événements: ${JSON.stringify(events)}`).not.toBeNull();
      const register = await responseDiagnostic(registerRaw!);
      await testInfo.attach('signup-register-etablissement.json', {
        body: Buffer.from(JSON.stringify(register, null, 2)), contentType: 'application/json',
      });
      // Un SIRET technique peut laisser l'identité en revue. Le test ne contourne
      // aucune vérification et ne confond pas profil créé avec publication autorisée.
      expect(register, 'register-etablissement crée un profil restant à vérifier').toMatchObject({
        status: 200, ok: true, businessOk: true, canPublish: false, verificationRequired: true,
      });
      await expect(page).toHaveURL(/\/etablissement\/missions\/creer\?inscription=1$/, { timeout: 30_000 });
      await expect(page.getByLabel('Intitulé *', { exact: true })).toHaveValue('Renfort IDE — audit inscription');

      // L'entrée normale de création retrouve aussi le brouillon après inscription.
      await page.goto('/etablissement/missions/creer');
      await expect(page.getByText('Brouillon repris', { exact: true })).toBeVisible();
      await expect(page.getByLabel(/Première date affichée/)).toHaveValue(missionDate);
      await expect(page.getByLabel(`Début du créneau 1 du ${missionDate}`, { exact: true })).toHaveValue('07:00');
      await expect(page.getByLabel(`Fin du créneau 1 du ${missionDate}`, { exact: true })).toHaveValue('19:00');
      await page.goto('/etablissement/tableau-de-bord');
      await expect(page).toHaveURL(/\/etablissement\/tableau-de-bord$/);
      await auditFreshAccountRoutes(page, testInfo, 'etab', ROUTES_ETABLISSEMENT);
    } finally {
      await testInfo.attach('signup-etablissement-evenements.json', {
        body: Buffer.from(JSON.stringify(events, null, 2)), contentType: 'application/json',
      });
    }
  });
});

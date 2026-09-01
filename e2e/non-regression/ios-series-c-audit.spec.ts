import { expect, test, type ConsoleMessage, type Page, type TestInfo } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { loginAs, TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userIdByEmail } from '../helpers/db';
import { ROUTES_ETABLISSEMENT, ROUTES_SOIGNANT } from '../helpers/ios-series-c-routes';
import { PREFIX_MISSION_MATCHING, seedMissionMatching } from '../helpers/seed-matching';

type RoleAudit = 'soignant' | 'etab';

type RouteAudit = {
  route: string;
  finalUrl: string;
  title: string;
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
};

const ROUTES_PUBLIQUES = [
  '/',
  '/connexion',
  '/inscription/soignant',
  '/inscription/etablissement',
  '/verification-email-etab',
  '/reset-password',
  '/confirmer-email',
  '/acces-admin-indisponible',
  '/tarifs',
  '/devenir-soignant',
  '/recruter-soignants',
  '/infirmiere-liberale',
  '/emploi-soignant/paris',
  '/metier/infirmier',
  '/a-propos',
  '/contact',
  '/telecharger',
  '/cgu',
  '/cgv',
  '/confidentialite',
  '/supprimer-mon-compte',
  '/mentions-legales',
  '/accessibilite',
  '/aide',
  '/aide/pro-sante-connect',
  '/etab/invitation/token-invalide-recette-visuelle',
  '/cette-page-nexiste-pas',
] as const;

const MOBILE_AUDIT_VIEWPORT = {
  width: Number.parseInt(process.env.UX_AUDIT_WIDTH || '390', 10),
  height: Number.parseInt(process.env.UX_AUDIT_HEIGHT || '844', 10),
};

async function prepareNativeShell(page: Page) {
  await page.addInitScript(() => {
    localStorage.setItem('cookie-consent', 'accepted');
    localStorage.setItem('push_permission_asked', 'later');
  });
}

async function settleAuthenticatedShell(page: Page) {
  await expect(page.locator('#main-content')).toBeVisible();
  const pathname = new URL(page.url()).pathname;
  if (pathname === '/etablissement/tableau-de-bord') {
    // Le dashboard établissement lance plusieurs RPC dans sa query primaire.
    // Attendre seulement l'URL ou le shell peut interrompre ces appels lors de
    // la navigation suivante et attribuer leurs erreurs à tort à la sous-page.
    await expect(page.getByTestId('dashboard-etablissement-ready')).toBeAttached({ timeout: 30_000 });
  }
  await page.waitForLoadState('networkidle', { timeout: 10_000 }).catch(() => undefined);
  await page.evaluate(() => document.fonts.ready);
}

function screenshotSlug(value: string) {
  return value
    .replace(/^\//, '')
    .replace(/[/?=&]+/g, '-')
    .replace(/[^a-z0-9-]+/gi, '-')
    .replace(/^-+|-+$/g, '') || 'accueil';
}

function expectRouteAuditClean(result: RouteAudit) {
  expect.soft(result.horizontalOverflow, `${result.route} ne doit pas déborder`).toBeLessThanOrEqual(1);
  expect.soft(result.inputsBelow16px, `${result.route} conserve des champs iOS à 16 px minimum`).toEqual([]);
  expect.soft(result.offscreenControls, `${result.route} ne doit pas sortir de contrôle du viewport`).toEqual([]);
  expect.soft(result.smallTouchTargets, `${result.route} conserve des cibles tactiles de 44 px`).toEqual([]);
  expect.soft(result.tinyTexts, `${result.route} ne doit pas rendre de texte sous 11 px`).toEqual([]);
  expect.soft(result.duplicateBackButtons, `${result.route} ne doit afficher qu'un seul retour`).toBe(0);
  expect.soft(result.consoleErrors, `${result.route} ne doit pas lever d'erreur console`).toEqual([]);
  expect.soft(result.pageErrors, `${result.route} ne doit pas lever d'erreur JavaScript`).toEqual([]);
}

async function captureVisualStates(
  page: Page,
  testInfo: TestInfo,
  role: string,
  route: string,
) {
  if (process.env.UX_AUDIT_SCREENSHOTS !== '1') return;
  const viewport = page.viewportSize();
  const root = process.env.UX_AUDIT_SCREENSHOTS_DIR
    || testInfo.outputPath('captures-visuelles');
  await mkdir(root, { recursive: true });
  const prefix = `${role}-${viewport?.width || 0}x${viewport?.height || 0}-${screenshotSlug(route)}`;
  const capture = async (suffix: string, fullPage = true) => {
    const filePath = path.join(root, `${prefix}-${suffix}.png`);
    await page.screenshot({ path: filePath, fullPage, animations: 'disabled' });
  };

  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  await capture('haut', false);
  await page.evaluate(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' }));
  await page.waitForTimeout(150);
  await capture('bas', false);
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  await capture('page-complete');

  const tabs = page.locator('[role="tab"]:visible');
  const tabCount = Math.min(await tabs.count(), 12);
  for (let index = 0; index < tabCount; index += 1) {
    const tab = tabs.nth(index);
    const name = screenshotSlug((await tab.innerText().catch(() => '')) || `onglet-${index + 1}`);
    if (await tab.isEnabled()) {
      await tab.click();
      await page.waitForTimeout(250);
      await capture(`onglet-${index + 1}-${name}`);
    }
  }
}

async function auditRoute(
  page: Page,
  testInfo: TestInfo,
  role: string,
  route: string,
): Promise<RouteAudit> {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  const onConsole = (message: ConsoleMessage) => {
    if (message.type() !== 'error') return;
    const source = message.location().url;
    const stripeCspNoise = /^https:\/\/(?:[^/]+\.)?stripe\.(?:com|network)\//.test(source)
      && message.text().includes('Refused to apply a stylesheet')
      && message.text().includes('Content Security Policy');
    if (!stripeCspNoise) {
      consoleErrors.push(`${source || 'source-inconnue'} :: ${message.text()}`);
    }
  };
  const onPageError = (error: Error) => {
    // WebKit transforme les fetch de la route précédente, annulés par une
    // navigation volontaire, en PageError « due to access control checks ».
    // Ils ne correspondent ni à une panne API ni à une erreur de la route
    // nouvellement affichée.
    if (!error.message.includes('due to access control checks')) pageErrors.push(error.message);
  };
  page.on('console', onConsole);
  page.on('pageerror', onPageError);
  const requestedUrl = new URL(route, 'http://audit.local');
  const currentUrl = page.url().startsWith('http') ? new URL(page.url()) : null;
  const alreadyOnRoute = currentUrl?.pathname === requestedUrl.pathname
    && currentUrl.search === requestedUrl.search;
  try {
    if (!alreadyOnRoute) await page.goto(route, { waitUntil: 'domcontentloaded' });
  } catch (error) {
    // WebKit peut signaler l'interruption lorsque le redirect post-login et
    // l'audit visent exactement la même URL. Selon sa version, Playwright
    // remonte soit « interrupted by another navigation », soit « Frame load
    // interrupted ». La redirection post-login peut gagner cette course et
    // terminer sur le dashboard. Une fois stabilisée, on rejoue la route
    // auditée. Si le garde d'accès la refuse réellement, l'assertion finale
    // reste rouge : cette reprise ne masque aucune redirection métier.
    const navigationRace = error instanceof Error
      && (
        error.message.includes('is interrupted by another navigation')
        || error.message.includes('Frame load interrupted')
    );
    if (!navigationRace) throw error;
    await page.waitForLoadState('domcontentloaded').catch(() => undefined);
    const settledUrl = page.url().startsWith('http') ? new URL(page.url()) : null;
    const settledOnRequestedRoute = settledUrl?.pathname === requestedUrl.pathname
      && settledUrl.search === requestedUrl.search;
    if (!settledOnRequestedRoute) {
      await page.goto(route, { waitUntil: 'domcontentloaded' });
    }
  }
  // Vérification systématique, même lorsque page.goto ne lève rien : un garde
  // d'accès qui redirige silencieusement vers un dashboard ne doit jamais être
  // compté comme l'audit réussi de la route demandée.
  await expect.poll(
    () => {
      const activeUrl = new URL(page.url());
      return `${activeUrl.pathname}${activeUrl.search}`;
    },
    { timeout: 5_000, message: `WebKit doit terminer sur ${route}` },
  ).toBe(`${requestedUrl.pathname}${requestedUrl.search}`);
  const contentRoot = page.locator('#main-content, #app-route-content, main, body').first();
  await expect(contentRoot).toBeVisible();
  await expect.poll(async () => (await page.locator('body').innerText()).trim().length,
    { message: `${route} doit rendre un contenu visible` }).toBeGreaterThan(0);
  await page.waitForLoadState('networkidle', { timeout: 3_000 }).catch(() => undefined);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1_000);
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
    const editable = Array.from(document.querySelectorAll('input, select, textarea'))
      .filter(visible);
    const textNodes = Array.from(document.querySelectorAll(
      'p, span, label, small, li, td, th, h1, h2, h3, h4',
    )).filter((element) => visible(element) && (element.textContent || '').trim().length > 0);

    const inputsBelow16px = editable
      .map((element) => ({
        label: labelOf(element),
        fontSize: Number.parseFloat(getComputedStyle(element).fontSize),
      }))
      .filter(({ fontSize }) => fontSize < 16);

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
      title: document.querySelector('h1')?.textContent?.replace(/\s+/g, ' ').trim() || document.title,
      horizontalOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      inputsBelow16px,
      offscreenControls,
      smallTouchTargets,
      tinyTexts,
      duplicateBackButtons: Math.max(0, visibleBackButtons.length - 1),
    };
  });

  // La mesure porte toujours sur l'état initial de la route. Les captures des
  // onglets sont réalisées ensuite : cliquer chaque onglet ne doit pas faire
  // dépendre les seuils tactiles de celui qui se trouve en dernier dans le DOM.
  await captureVisualStates(page, testInfo, role, route);

  page.off('console', onConsole);
  page.off('pageerror', onPageError);

  return {
    route,
    finalUrl: new URL(page.url()).pathname + new URL(page.url()).search,
    ...metrics,
    consoleErrors,
    pageErrors,
  };
}

async function auditRole(
  page: Page,
  testInfo: TestInfo,
  role: RoleAudit,
  routes: readonly string[],
) {
  await prepareNativeShell(page);
  await loginAs(page, role);

  const results: RouteAudit[] = [];
  for (const route of routes) results.push(await auditRoute(page, testInfo, role, route));

  const viewport = page.viewportSize();
  await testInfo.attach(`audit-${role}-${viewport?.width}x${viewport?.height}.json`, {
    body: Buffer.from(JSON.stringify(results, null, 2)),
    contentType: 'application/json',
  });

  const overflow = results.filter((result) => result.horizontalOverflow > 1);
  const undersizedInputs = results.filter((result) => result.inputsBelow16px.length > 0);
  const offscreen = results.filter((result) => result.offscreenControls.length > 0);
  const undersizedTargets = results.filter((result) => result.smallTouchTargets.length > 0);
  const unreadableText = results.filter((result) => result.tinyTexts.length > 0);
  const duplicateBacks = results.filter((result) => result.duplicateBackButtons > 0);
  const runtimeErrors = results.filter((result) => (
    result.pageErrors.length > 0 || result.consoleErrors.length > 0
  ));

  const summary = results
    .map((result) => ({
      route: result.route,
      overflow: result.horizontalOverflow,
      inputsBelow16px: result.inputsBelow16px.length,
      offscreenControls: result.offscreenControls.length,
      smallTouchTargets: result.smallTouchTargets.length,
      tinyTexts: result.tinyTexts.length,
      duplicateBackButtons: result.duplicateBackButtons,
      consoleErrors: result.consoleErrors.length,
      pageErrors: result.pageErrors.length,
    }))
    .filter((result) => Object.entries(result).some(([key, value]) => key !== 'route' && value > 0));
  console.log(`[ux-audit:${role}:${viewport?.width}x${viewport?.height}] ${JSON.stringify(summary)}`);
  if (process.env.UX_AUDIT_VERBOSE === '1') {
    console.log(`[ux-audit-details:${role}:${viewport?.width}x${viewport?.height}] ${JSON.stringify(
      results
        .filter((result) => result.smallTouchTargets.length > 0 || result.tinyTexts.length > 0)
        .map(({ route, smallTouchTargets, tinyTexts }) => ({ route, smallTouchTargets, tinyTexts })),
    )}`);
  }

  expect.soft(overflow.map(({ route, horizontalOverflow }) => ({ route, horizontalOverflow })),
    'aucune route ne doit déborder horizontalement').toEqual([]);
  if ((viewport?.width ?? 0) <= 500) {
    expect.soft(undersizedInputs.map(({ route, inputsBelow16px }) => ({ route, inputsBelow16px })),
      'les champs iOS doivent rester à 16 px minimum pour éviter le zoom').toEqual([]);
    expect.soft(undersizedTargets.map(({ route, smallTouchTargets }) => ({ route, smallTouchTargets })),
      'les cibles tactiles iOS doivent mesurer au moins 44 × 44 px').toEqual([]);
    expect.soft(unreadableText.map(({ route, tinyTexts }) => ({ route, tinyTexts })),
      'aucun texte mobile ne doit descendre sous Caption 2 (11 px)').toEqual([]);
  }
  expect.soft(offscreen.map(({ route, offscreenControls }) => ({ route, offscreenControls })),
    'aucun contrôle ne doit sortir du viewport').toEqual([]);
  expect.soft(duplicateBacks.map(({ route, duplicateBackButtons }) => ({ route, duplicateBackButtons })),
    'une sous-page ne doit afficher qu’un seul retour').toEqual([]);
  expect.soft(runtimeErrors.map(({ route, consoleErrors, pageErrors }) => ({
    route,
    consoleErrors,
    pageErrors,
  })), 'aucune route ne doit lever une erreur JavaScript ou console').toEqual([]);
}

async function auditPublicRoutes(page: Page, testInfo: TestInfo) {
  await prepareNativeShell(page);
  const results: RouteAudit[] = [];
  for (const route of ROUTES_PUBLIQUES) {
    results.push(await auditRoute(page, testInfo, 'public', route));
  }
  await testInfo.attach(`audit-public-${page.viewportSize()?.width}x${page.viewportSize()?.height}.json`, {
    body: Buffer.from(JSON.stringify(results, null, 2)),
    contentType: 'application/json',
  });
  expect.soft(results.filter((result) => result.horizontalOverflow > 1)
    .map(({ route, horizontalOverflow }) => ({ route, horizontalOverflow })),
  'aucune interface publique ne doit déborder horizontalement').toEqual([]);
  expect.soft(results.filter((result) => result.inputsBelow16px.length > 0)
    .map(({ route, inputsBelow16px }) => ({ route, inputsBelow16px })),
  'les champs publics iOS doivent rester à 16 px minimum').toEqual([]);
  expect.soft(results.filter((result) => result.offscreenControls.length > 0)
    .map(({ route, offscreenControls }) => ({ route, offscreenControls })),
  'aucun contrôle public ne doit sortir du viewport').toEqual([]);
  expect.soft(results.filter((result) => result.smallTouchTargets.length > 0)
    .map(({ route, smallTouchTargets }) => ({ route, smallTouchTargets })),
  'les cibles tactiles publiques doivent mesurer au moins 44 × 44 px').toEqual([]);
  expect.soft(results.filter((result) => result.tinyTexts.length > 0)
    .map(({ route, tinyTexts }) => ({ route, tinyTexts })),
  'aucun texte public mobile ne doit descendre sous 11 px').toEqual([]);
  expect.soft(results.filter((result) => result.duplicateBackButtons > 0)
    .map(({ route, duplicateBackButtons }) => ({ route, duplicateBackButtons })),
  'une interface publique ne doit afficher qu’un seul retour').toEqual([]);
  expect.soft(results.filter((result) => (
    result.consoleErrors.length > 0 || result.pageErrors.length > 0
  )).map(({ route, consoleErrors, pageErrors }) => ({ route, consoleErrors, pageErrors })),
  'aucune interface publique ne doit lever une erreur JavaScript ou console').toEqual([]);
}

test.describe('audit iOS Série C — parcours complet', () => {
  test.use({ viewport: MOBILE_AUDIT_VIEWPORT, hasTouch: true, isMobile: true });

  test('dashboard soignant — la carte suggérée ne comprime ni le contenu ni le CTA', async ({ page }) => {
    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    expect(soignantId, 'compte soignant de recette disponible').toBeTruthy();
    const { data: soignant } = await adminClient()
      .from('soignants' as any)
      .select('profession')
      .eq('id', soignantId!)
      .maybeSingle();
    const mission = await seedMissionMatching({
      intitule: `${PREFIX_MISSION_MATCHING} dashboard-mobile-${Date.now()}`,
      profession: (soignant as any)?.profession || 'IDE',
    });
    expect(mission, 'mission compatible dédiée au contrôle visuel').toBeTruthy();

    try {
      await prepareNativeShell(page);
      await loginAs(page, 'soignant');
      // loginAs attend déjà ce dashboard. Une seconde navigation immédiate vers
      // la même URL peut entrer en concurrence avec la résolution finale du rôle
      // sous WebKit et produire un faux « navigation interrupted ».

      const cta = page.getByRole('button', { name: 'Voir le planning et postuler' }).first();
      await expect(cta).toBeVisible();
      const card = cta.locator('xpath=ancestor::*[contains(concat(" ", normalize-space(@class), " "), " card-base ")][1]');
      const missionLink = card.locator('a').first();
      const layout = await card.evaluate((element) => {
        const link = element.querySelector('a');
        const button = element.querySelector('button');
        if (!link || !button) throw new Error('Composition de carte mission incomplète');
        const cardRect = element.getBoundingClientRect();
        const linkRect = link.getBoundingClientRect();
        const buttonRect = button.getBoundingClientRect();
        return {
          cardWidth: cardRect.width,
          linkWidth: linkRect.width,
          buttonWidth: buttonRect.width,
          linkBottom: linkRect.bottom,
          buttonTop: buttonRect.top,
        };
      });

      await expect(missionLink).toBeVisible();
      expect(layout.linkWidth).toBeGreaterThanOrEqual(layout.cardWidth - 40);
      expect(layout.buttonWidth).toBeGreaterThanOrEqual(layout.cardWidth - 40);
      expect(layout.buttonTop).toBeGreaterThanOrEqual(layout.linkBottom + 8);
    } finally {
      if (mission) {
        await adminClient().from('missions' as any).delete().eq('id', mission.id);
      }
    }
  });

  test('public — toutes les interfaces accessibles depuis la coquille mobile', async ({ page }, testInfo) => {
    test.setTimeout(180_000);
    await auditPublicRoutes(page, testInfo);
  });

  test('soignant — toutes les interfaces publiques du compte', async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await auditRole(page, testInfo, 'soignant', ROUTES_SOIGNANT);
  });

  test('établissement — toutes les interfaces publiques du compte', async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await auditRole(page, testInfo, 'etab', ROUTES_ETABLISSEMENT);
  });

  test('établissement — fiche soignant réelle depuis l’annuaire', async ({ page }, testInfo) => {
    test.setTimeout(60_000);
    await prepareNativeShell(page);
    await loginAs(page, 'etab');
    await settleAuthenticatedShell(page);
    await page.goto('/etablissement/soignants');
    const premiereFiche = page.getByRole('button', { name: /^Voir le profil de / }).first();
    await expect(premiereFiche, 'l’annuaire de recette doit exposer au moins une fiche').toBeVisible();
    await premiereFiche.click();
    await expect(page).toHaveURL(/\/etablissement\/soignants\/[0-9a-f-]+$/);
    const route = new URL(page.url()).pathname;
    expectRouteAuditClean(await auditRoute(page, testInfo, 'etab-dynamique', route));
  });

  test('mission réelle — détail et modification établissement, détail soignant', async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    test.skip(
      !(process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.PLAYWRIGHT_SERVICE_ROLE_KEY),
      'fixture dynamique réservée à la CI munie de la clé service_role',
    );

    const soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
    const { data: soignant } = await adminClient()
      .from('soignants' as any)
      .select('profession')
      .eq('id', soignantId!)
      .maybeSingle();
    const mission = await seedMissionMatching({
      intitule: `${PREFIX_MISSION_MATCHING} audit-visuel-dynamique-${Date.now()}`,
      profession: (soignant as any)?.profession || 'IDE',
    });
    expect(mission, 'mission réelle dédiée à l’audit visuel dynamique').toBeTruthy();

    try {
      await prepareNativeShell(page);
      await loginAs(page, 'etab');
      await settleAuthenticatedShell(page);
      expectRouteAuditClean(await auditRoute(
        page,
        testInfo,
        'etab-dynamique',
        `/etablissement/missions/${mission!.id}`,
      ));
      expectRouteAuditClean(await auditRoute(
        page,
        testInfo,
        'etab-dynamique',
        `/etablissement/missions/${mission!.id}/modifier`,
      ));

      await page.evaluate(() => {
        localStorage.clear();
        sessionStorage.clear();
      });
      await loginAs(page, 'soignant');
      await settleAuthenticatedShell(page);
      expectRouteAuditClean(await auditRoute(
        page,
        testInfo,
        'soignant-dynamique',
        `/soignant/missions/${mission!.id}`,
      ));
    } finally {
      const { error } = await adminClient().from('missions' as any).delete().eq('id', mission!.id);
      expect(error, 'la mission visuelle temporaire doit être nettoyée').toBeNull();
    }
  });
});

test.describe('audit établissement Série C — grand écran', () => {
  test.use({ viewport: { width: 1440, height: 900 }, hasTouch: false, isMobile: false });

  test('les interfaces métier critiques restent stables', async ({ page }, testInfo) => {
    test.setTimeout(90_000);
    await auditRole(page, testInfo, 'etab', [
      '/etablissement/tableau-de-bord',
      '/etablissement/missions',
      '/etablissement/missions/creer',
      '/etablissement/presences',
      '/etablissement/facturation',
      '/etablissement/soignants',
      '/etablissement/rh',
      '/etablissement/parametres',
    ]);
  });
});

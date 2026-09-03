import { expect, test, type ConsoleMessage, type Page, type TestInfo } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { loginAs } from '../helpers/auth';

type RouteExpectation = {
  route: string;
  finalRoute?: string;
};

const ADMIN_ROUTES: RouteExpectation[] = [
  { route: '/admin' },
  { route: '/admin/fondateur' },
  { route: '/admin/fondateur/lancement' },
  { route: '/admin/cohort' },
  { route: '/admin/fondateur/equipe' },
  { route: '/admin/fondateur/levee' },
  { route: '/admin/fondateur/acquisition' },
  { route: '/admin/fondateur/sales' },
  { route: '/admin/missions' },
  { route: '/admin/calendrier' },
  { route: '/admin/planning-global' },
  { route: '/admin/pool-urgence' },
  { route: '/admin/alertes-pointage' },
  { route: '/admin/messagerie' },
  { route: '/admin/messages-contact' },
  { route: '/admin/utilisateurs' },
  { route: '/admin/verification-etablissements' },
  { route: '/admin/revues-manuelles' },
  { route: '/admin/moderation' },
  { route: '/admin/signalements' },
  { route: '/admin/reclamations' },
  { route: '/admin/reclamations-score', finalRoute: '/admin/reclamations?tab=score' },
  { route: '/admin/scores', finalRoute: '/admin/reclamations?tab=triage' },
  { route: '/admin/litiges' },
  { route: '/admin/heures-externes' },
  { route: '/admin/groupes' },
  { route: '/admin/finances' },
  { route: '/admin/facturation' },
  { route: '/admin/impayees' },
  { route: '/admin/chorus-pro' },
  { route: '/admin/mandats-facturation' },
  { route: '/admin/affacturage' },
  { route: '/admin/taux-commission' },
  { route: '/admin/bfa' },
  { route: '/admin/conformite' },
  { route: '/admin/dpia' },
  { route: '/admin/rgpd-tools' },
  { route: '/admin/audit' },
  { route: '/admin/audit-rls' },
  { route: '/admin/contrats' },
  { route: '/admin/templates-contrats' },
  { route: '/admin/status' },
  { route: '/admin/healthcheck', finalRoute: '/admin/status' },
  { route: '/admin/config' },
  { route: '/admin/emails' },
  { route: '/admin/api' },
  { route: '/admin/externalisations-actions' },
  { route: '/admin/demo' },
];

const screenshotEnabled = process.env.UX_ADMIN_AUDIT_SCREENSHOTS === '1';
const requestedRoutes = new Set(
  (process.env.UX_ADMIN_AUDIT_ROUTES || '')
    .split(',')
    .map((route) => route.trim())
    .filter(Boolean),
);
const routesToAudit = requestedRoutes.size > 0
  ? ADMIN_ROUTES.filter(({ route }) => requestedRoutes.has(route))
  : ADMIN_ROUTES;

function routeSlug(route: string) {
  return route
    .replace(/^\//, '')
    .replace(/[/?=&]+/g, '-')
    .replace(/[^a-z0-9-]+/gi, '-') || 'admin';
}

async function capture(page: Page, testInfo: TestInfo, route: string, suffix: string) {
  if (!screenshotEnabled) return;
  const viewport = page.viewportSize();
  const directory = process.env.UX_ADMIN_AUDIT_SCREENSHOTS_DIR
    || testInfo.outputPath('captures-admin');
  await mkdir(directory, { recursive: true });
  await page.screenshot({
    path: path.join(
      directory,
      `${testInfo.project.name}-${viewport?.width || 0}x${viewport?.height || 0}-${routeSlug(route)}-${suffix}.png`,
    ),
    fullPage: suffix === 'page-complete',
    animations: 'disabled',
  });
}

async function waitForAdminPage(page: Page) {
  await expect(page.locator('main').first()).toBeVisible({ timeout: 15_000 });
  await expect.poll(
    async () => (await page.locator('body').innerText()).trim().length,
    { timeout: 15_000 },
  ).toBeGreaterThan(40);
  await page.waitForLoadState('networkidle', { timeout: 4_000 }).catch(() => undefined);
  // `main` et la navigation sont déjà visibles pendant le squelette. Attendre
  // explicitement la fin de l'état de chargement évite d'auditer la coquille
  // avant que le titre et les données réelles de la fiche soient montés.
  await page.getByRole('status', { name: 'Chargement en cours' })
    .waitFor({ state: 'hidden', timeout: 30_000 });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(350);
}

async function inspectRoute(page: Page, isMobile: boolean) {
  return page.evaluate(({ mobile }) => {
    const visible = (element: Element) => {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      return style.display !== 'none'
        && style.visibility !== 'hidden'
        && Number(style.opacity) > 0
        && rect.width > 0
        && rect.height > 0
        && !element.closest('[aria-hidden="true"]');
    };
    const labelOf = (element: Element) => (
      element.getAttribute('aria-label')
      || element.getAttribute('title')
      || element.closest('label')?.textContent
      || (element.textContent || '').replace(/\s+/g, ' ').trim()
      || element.tagName.toLowerCase()
    ).slice(0, 100);
    const horizontalScrollerFor = (element: Element) => {
      let current = element.parentElement;
      while (current && current !== document.body) {
        const style = getComputedStyle(current);
        if ((style.overflowX === 'auto' || style.overflowX === 'scroll')
          && current.scrollWidth > current.clientWidth + 1) return current;
        current = current.parentElement;
      }
      return null;
    };
    const inHorizontalScroller = (element: Element) => Boolean(horizontalScrollerFor(element));
    const controls = Array.from(document.querySelectorAll(
      'button, a[href], input, select, textarea, [role="button"], [role="tab"], [role="switch"]',
    )).filter(visible);
    const inputsBelow16px = Array.from(document.querySelectorAll('input, select, textarea'))
      .filter(visible)
      .map((element) => ({
        label: labelOf(element),
        fontSize: Number.parseFloat(getComputedStyle(element).fontSize),
      }))
      .filter(({ fontSize }) => mobile && fontSize < 16);
    const offscreenControls = controls
      .filter((element) => !inHorizontalScroller(element))
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return { label: labelOf(element), left: rect.left, right: rect.right };
      })
      .filter(({ left, right }) => left < -1 || right > innerWidth + 1)
      .slice(0, 12);
    const overflowingLayoutElements = Array.from(document.body.querySelectorAll('*'))
      .filter(visible)
      .filter((element) => !inHorizontalScroller(element))
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return {
          tag: element.tagName.toLowerCase(),
          label: labelOf(element),
          className: typeof element.className === 'string' ? element.className.slice(0, 180) : '',
          left: Math.round(rect.left),
          right: Math.round(rect.right),
        };
      })
      .filter(({ left, right }) => left < -1 || right > innerWidth + 1)
      .slice(0, 12);
    const smallTouchTargets = controls
      .filter((element) => !inHorizontalScroller(element))
      .filter((element) => {
        if (!(element instanceof HTMLInputElement) || !['checkbox', 'radio'].includes(element.type)) return true;
        const label = element.closest('label');
        if (!label) return true;
        const labelRect = label.getBoundingClientRect();
        return labelRect.width < 44 || labelRect.height < 44;
      })
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return {
          label: labelOf(element),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          text: (element.textContent || '').trim(),
        };
      })
      .filter(({ width, height, text }) => mobile && text.length === 0 && (width < 44 || height < 44));
    const activeScrollerItemsOutOfView = Array.from(document.querySelectorAll(
      'nav [aria-current="page"], [role="tab"][aria-selected="true"]',
    ))
      .filter(visible)
      .map((element) => {
        const scroller = horizontalScrollerFor(element);
        if (!scroller) return null;
        const itemRect = element.getBoundingClientRect();
        const scrollerRect = scroller.getBoundingClientRect();
        return {
          label: labelOf(element),
          itemLeft: itemRect.left,
          itemRight: itemRect.right,
          scrollerLeft: scrollerRect.left,
          scrollerRight: scrollerRect.right,
        };
      })
      .filter((entry) => entry !== null
        && (entry.itemLeft < entry.scrollerLeft - 1 || entry.itemRight > entry.scrollerRight + 1));
    const duplicateSkipLinks = Array.from(document.querySelectorAll('a'))
      .filter((element) => (element.textContent || '').trim() === 'Aller au contenu principal')
      .length;
    const text = (document.body.innerText || '').replace(/\s+/g, ' ').trim();
    const scrollingElement = document.scrollingElement;
    const previousScrollLeft = scrollingElement?.scrollLeft || 0;
    if (scrollingElement) scrollingElement.scrollLeft = scrollingElement.scrollWidth;
    const rootOverflowIsClipped = [document.documentElement, document.body]
      .some((element) => ['clip', 'hidden'].includes(getComputedStyle(element).overflowX));
    const horizontalOverflow = rootOverflowIsClipped
      ? 0
      : Math.max(0, scrollingElement?.scrollLeft || 0);
    if (scrollingElement) scrollingElement.scrollLeft = previousScrollLeft;
    return {
      horizontalOverflow,
      inputsBelow16px,
      offscreenControls,
      overflowingLayoutElements,
      smallTouchTargets,
      activeScrollerItemsOutOfView,
      duplicateSkipLinks,
      hasMainHeading: Boolean(document.querySelector('main h1')),
      hasFatalCopy: /page introuvable|une erreur inattendue|failed to fetch|importing a module script failed/i.test(text),
      hasMfaGate: /double authentification|authentification à deux facteurs|saisissez le code à 6 chiffres|\b2fa\b|\bmfa\b/i.test(text),
    };
  }, { mobile: isMobile });
}

async function expectHealthyAdminView(page: Page, label: string) {
  const isMobile = (page.viewportSize()?.width || 1280) < 768;
  await waitForAdminPage(page);
  const metrics = await inspectRoute(page, isMobile);
  expect(metrics.horizontalOverflow, `${label}: aucun scroll horizontal racine`).toBeLessThanOrEqual(1);
  expect(metrics.inputsBelow16px, `${label}: champs iOS à 16 px minimum`).toEqual([]);
  expect(metrics.offscreenControls, `${label}: contrôles dans le viewport`).toEqual([]);
  expect(metrics.smallTouchTargets, `${label}: contrôles tactiles iconiques de 44 px`).toEqual([]);
  expect(metrics.activeScrollerItemsOutOfView, `${label}: onglet actif entièrement visible`).toEqual([]);
  expect(metrics.duplicateSkipLinks, `${label}: un seul lien d’évitement`).toBe(1);
  expect(metrics.hasMainHeading, `${label}: titre principal explicite`).toBe(true);
  expect(metrics.hasFatalCopy, `${label}: aucun état d’erreur fatal visible`).toBe(false);
  expect(metrics.hasMfaGate, `${label}: aucun écran MFA administrateur`).toBe(false);
}

function isLocalPreviewHealthRoute(route: string) {
  return /^http:\/\/127\.0\.0\.1:\d+/.test(process.env.PLAYWRIGHT_BASE_URL || '')
    && ['/admin/status', '/admin/healthcheck'].includes(route);
}

function isLocalPreviewTransportNoise(message: string, route = '') {
  if (!/^http:\/\/127\.0\.0\.1:\d+/.test(process.env.PLAYWRIGHT_BASE_URL || '')) return false;
  const localHealthCors = isLocalPreviewHealthRoute(route)
    && (/Access to fetch at 'https:\/\/[^']+\.supabase\.co\/functions\/v1\/[^']+' from origin 'http:\/\/127\.0\.0\.1:\d+'.*(?:blocked by CORS policy|Access-Control-Allow-Origin)/.test(message)
      || message === 'Failed to load resource: net::ERR_FAILED');
  return localHealthCors
    || /Origin http:\/\/127\.0\.0\.1:\d+ is not allowed by Access-Control-Allow-Origin/.test(message)
    || /WebSocket connection to 'wss:\/\/[^']+\.supabase\.co\/realtime\/v1\/websocket\?[^']+' failed: The operation couldn’t be completed\. Socket is not connected/.test(message);
}

function isLocalPreviewCancelledSupabaseRequest(message: string, route = '') {
  if (!/^http:\/\/127\.0\.0\.1:\d+/.test(process.env.PLAYWRIGHT_BASE_URL || '')) return false;
  const cancelledRestRequest = /supabase\.co\/rest\/v1\/.+ due to access control checks\.$/.test(message);
  const cancelledHealthFunction = isLocalPreviewHealthRoute(route)
    && /supabase\.co\/functions\/v1\/.+ due to access control checks\.$/.test(message);
  return cancelledRestRequest || cancelledHealthFunction;
}

test.describe('audit frontend administrateur Série C', () => {
  test('connexion sans MFA et parcours visuel complet', async ({ page }, testInfo) => {
    test.setTimeout(8 * 60_000);
    const isMobile = (page.viewportSize()?.width || 1280) < 768;
    let currentRoute = '/connexion';
    let consoleErrors: string[] = [];
    let pageErrors: string[] = [];
    let forbiddenResponses: string[] = [];

    page.on('console', (message: ConsoleMessage) => {
      if (message.type() !== 'error') return;
      const source = message.location().url;
      const stripeNoise = /^https:\/\/(?:[^/]+\.)?stripe\.(?:com|network)\//.test(source)
        && message.text().includes('Refused to apply a stylesheet')
        && message.text().includes('Content Security Policy');
      if (!stripeNoise && !isLocalPreviewTransportNoise(message.text(), currentRoute)) {
        consoleErrors.push(`${currentRoute}: ${message.text()}`);
      }
    });
    page.on('pageerror', (error) => {
      if (!isLocalPreviewCancelledSupabaseRequest(error.message, currentRoute)) {
        pageErrors.push(`${currentRoute}: ${error.message}`);
      }
    });
    page.on('response', (response) => {
      if (![401, 403].includes(response.status()) && response.status() < 500) return;
      forbiddenResponses.push(`${currentRoute}: ${response.status()} ${response.url()}`);
    });
    await page.addInitScript(() => {
      localStorage.setItem('cookie-consent', 'accepted');
      localStorage.setItem('push_permission_asked', 'later');
    });

    await loginAs(page, 'admin');
    await waitForAdminPage(page);
    await expect(page).toHaveURL(/\/admin(?:\/|$)/);
    await expect(page.getByText(/double authentification|authentification à deux facteurs/i)).toHaveCount(0);
    expect(new URL(page.url()).pathname).not.toMatch(/2fa|mfa/i);

    for (const { route, finalRoute = route } of routesToAudit) {
      currentRoute = route;
      consoleErrors = [];
      pageErrors = [];
      forbiddenResponses = [];
      await page.goto(route, { waitUntil: 'domcontentloaded' });
      await waitForAdminPage(page);
      const current = new URL(page.url());
      expect.soft(
        `${current.pathname}${current.search}`,
        `${route} doit conserver sa destination attendue`,
      ).toBe(finalRoute);

      const metrics = await inspectRoute(page, isMobile);
      if (process.env.UX_ADMIN_AUDIT_DEBUG === '1') {
        console.log(`[admin-audit] ${route}`, JSON.stringify(metrics));
      }
      expect.soft(metrics.horizontalOverflow, `${route}: aucun débordement horizontal`).toBeLessThanOrEqual(1);
      expect.soft(metrics.inputsBelow16px, `${route}: champs iOS à 16 px minimum`).toEqual([]);
      expect.soft(metrics.offscreenControls, `${route}: contrôles dans le viewport`).toEqual([]);
      expect.soft(metrics.smallTouchTargets, `${route}: contrôles tactiles iconiques de 44 px`).toEqual([]);
      expect.soft(metrics.activeScrollerItemsOutOfView, `${route}: onglet actif entièrement visible`).toEqual([]);
      expect.soft(metrics.duplicateSkipLinks, `${route}: un seul lien d’évitement`).toBe(1);
      expect.soft(metrics.hasMainHeading, `${route}: titre principal explicite`).toBe(true);
      expect.soft(
        isLocalPreviewHealthRoute(route) ? false : metrics.hasFatalCopy,
        `${route}: aucun état d’erreur fatal visible`,
      ).toBe(false);
      expect.soft(metrics.hasMfaGate, `${route}: aucun écran MFA administrateur`).toBe(false);
      expect.soft(consoleErrors, `${route}: aucune erreur console`).toEqual([]);
      expect.soft(pageErrors, `${route}: aucune erreur JavaScript`).toEqual([]);
      expect.soft(forbiddenResponses, `${route}: aucune réponse API 401/403/5xx`).toEqual([]);

      await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
      await capture(page, testInfo, route, 'haut');
      await capture(page, testInfo, route, 'page-complete');

      const tabs = page.locator('[role="tab"]:visible');
      const tabCount = Math.min(await tabs.count(), 12);
      for (let index = 0; index < tabCount; index += 1) {
        const tab = tabs.nth(index);
        if (await tab.isEnabled()) {
          consoleErrors = [];
          pageErrors = [];
          forbiddenResponses = [];
          await tab.click();
          await page.waitForTimeout(300);
          await expect(page.locator('main').first()).toBeVisible();
          const tabMetrics = await inspectRoute(page, isMobile);
          const tabLabel = `${route} — onglet ${index + 1}`;
          if (process.env.UX_ADMIN_AUDIT_DEBUG === '1') {
            console.log(`[admin-audit] ${tabLabel}`, JSON.stringify(tabMetrics));
          }
          expect.soft(tabMetrics.horizontalOverflow, `${tabLabel}: aucun débordement horizontal`).toBeLessThanOrEqual(1);
          expect.soft(tabMetrics.inputsBelow16px, `${tabLabel}: champs iOS à 16 px minimum`).toEqual([]);
          expect.soft(tabMetrics.offscreenControls, `${tabLabel}: contrôles dans le viewport`).toEqual([]);
          expect.soft(tabMetrics.smallTouchTargets, `${tabLabel}: contrôles tactiles iconiques de 44 px`).toEqual([]);
          expect.soft(tabMetrics.activeScrollerItemsOutOfView, `${tabLabel}: onglet actif entièrement visible`).toEqual([]);
          expect.soft(tabMetrics.duplicateSkipLinks, `${tabLabel}: un seul lien d’évitement`).toBe(1);
          expect.soft(
            isLocalPreviewHealthRoute(route) ? false : tabMetrics.hasFatalCopy,
            `${tabLabel}: aucun état d’erreur fatal visible`,
          ).toBe(false);
          expect.soft(tabMetrics.hasMfaGate, `${tabLabel}: aucun écran MFA administrateur`).toBe(false);
          expect.soft(consoleErrors, `${tabLabel}: aucune erreur console`).toEqual([]);
          expect.soft(pageErrors, `${tabLabel}: aucune erreur JavaScript`).toEqual([]);
          expect.soft(forbiddenResponses, `${tabLabel}: aucune réponse API 401/403/5xx`).toEqual([]);
          await capture(page, testInfo, route, `onglet-${index + 1}`);
        }
      }
    }
  });

  test('interactions du cockpit et détails issus des données réelles', async ({ page }, testInfo) => {
    test.setTimeout(3 * 60_000);
    const isMobile = (page.viewportSize()?.width || 1280) < 768;
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];
    const forbiddenResponses: string[] = [];

    page.on('console', (message: ConsoleMessage) => {
      if (message.type() !== 'error') return;
      if (!isLocalPreviewTransportNoise(message.text())) consoleErrors.push(message.text());
    });
    page.on('pageerror', (error) => {
      if (!isLocalPreviewCancelledSupabaseRequest(error.message)) pageErrors.push(error.message);
    });
    page.on('response', (response) => {
      if ([401, 403].includes(response.status()) || response.status() >= 500) {
        forbiddenResponses.push(`${response.status()} ${response.url()}`);
      }
    });
    await page.addInitScript(() => {
      localStorage.setItem('cookie-consent', 'accepted');
      localStorage.setItem('push_permission_asked', 'later');
    });

    await loginAs(page, 'admin');
    await expectHealthyAdminView(page, 'cockpit admin après connexion');

    const searchButton = page.getByRole('button', { name: 'Rechercher' }).first();
    await searchButton.click();
    const searchDialog = page.getByRole('dialog', { name: /Recherche globale/i });
    await expect(searchDialog).toBeVisible();
    const searchInput = searchDialog.locator('input').first();
    await searchInput.fill('Camille');
    await page.waitForTimeout(450);
    await page.keyboard.press('Escape');
    await expect(searchDialog).toBeHidden();

    const notificationsButton = page.getByRole('button', { name: /^Notifications(?:,|$)/ }).first();
    await notificationsButton.click();
    await expect(page.getByRole('dialog', { name: 'Notifications' })).toBeVisible();
    await page.getByRole('button', { name: 'Fermer les notifications' }).click();

    const themeButton = page.getByRole('button', { name: /Passer en mode (?:sombre|clair)/ }).first();
    await themeButton.click();
    await expectHealthyAdminView(page, 'cockpit admin en thème alternatif');
    await page.getByRole('button', { name: /Passer en mode (?:sombre|clair)/ }).first().click();

    if (isMobile) {
      const moreButton = page.getByRole('button', { name: 'Plus' });
      await moreButton.click();
      await expect(page.getByRole('dialog', { name: 'Autres espaces admin' })).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog', { name: 'Autres espaces admin' })).toBeHidden();
    }

    await page.goto('/admin/utilisateurs', { waitUntil: 'domcontentloaded' });
    await expectHealthyAdminView(page, 'liste utilisateurs réelle');
    const viewUser = page.getByRole('button', { name: 'Détails' }).first();
    await expect(viewUser).toBeVisible();
    await viewUser.click();
    await expect(page).toHaveURL(/\/admin\/utilisateurs\/[^/?]+/);
    await expectHealthyAdminView(page, 'détail utilisateur réel');
    await capture(page, testInfo, '/admin/utilisateurs/detail-reel', 'haut');

    await page.goto('/admin/missions', { waitUntil: 'domcontentloaded' });
    await expectHealthyAdminView(page, 'liste missions réelle');
    const historyButton = page.getByRole('button', { name: /Historique — toutes les missions/ });
    if (await historyButton.getAttribute('aria-expanded') !== 'true') await historyButton.click();
    const missionCard = isMobile
      ? page.getByRole('listitem').first()
      : page.locator('a[href^="/admin/missions/"]').first();
    await expect(missionCard).toBeVisible();
    await missionCard.click();
    await expect(page).toHaveURL(/\/admin\/missions\/[^/?]+/);
    const missionId = new URL(page.url()).pathname.split('/').filter(Boolean).at(-1);
    await expectHealthyAdminView(page, 'détail mission réel');
    const adminMissionControl = page.getByTestId('admin-mission-control');
    await expect(adminMissionControl).toBeVisible();
    await expect(adminMissionControl).toContainText('Centre de contrôle admin');
    await expect(adminMissionControl.getByRole('link', { name: 'Présences & pauses' })).toBeVisible();
    await expect(adminMissionControl.getByRole('link', { name: 'Facturation' })).toBeVisible();
    await expect(adminMissionControl.getByRole('link', { name: 'Paiements & commission' })).toBeVisible();
    await expect(page.getByText(/actions métier restent réservées à l’établissement propriétaire/i)).toHaveCount(0);
    await capture(page, testInfo, '/admin/missions/detail-reel', 'haut');

    expect(missionId, 'un identifiant de mission réel doit être disponible').toBeTruthy();
    await page.goto(`/admin/presences/mission/${missionId}`, { waitUntil: 'domcontentloaded' });
    await expectHealthyAdminView(page, 'présences d’une mission réelle');
    await expect(page.getByRole('region', { name: 'Intervention admin sur les présences' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Intervenir sur les heures ou le paiement' })).toBeVisible();
    // La fiche distingue désormais le planning, le pointage et la base de paie
    // au lieu d'afficher un ambigu « total brut de la mission ».
    await expect(page.getByRole('heading', { name: '💶 Récapitulatif financier' })).toBeVisible();
    await expect(page.getByText('Base brute retenue')).toBeVisible();
    await expect(page.getByText('Net salarié estimé avant PAS')).toBeVisible();
    await capture(page, testInfo, '/admin/presences/mission/detail-reel', 'haut');

    await page.goto('/admin/litiges', { waitUntil: 'domcontentloaded' });
    await expectHealthyAdminView(page, 'supervision des litiges');
    const litigeAvecAccord = page.getByRole('button', { name: /Revue admin.*À trancher/i }).first();
    if (await litigeAvecAccord.count()) {
      await litigeAvecAccord.click();
      const executerAccord = page.getByRole('button', { name: 'Valider l’accord et exécuter' });
      if (await executerAccord.count()) {
        await executerAccord.click();
        const confirmationFinanciere = page.getByRole('alertdialog', { name: 'Confirmer le mouvement financier' });
        await expect(confirmationFinanciere).toBeVisible();
        await expect(confirmationFinanciere).toContainText(/Mission|Accord|Justification/);
        await expect(confirmationFinanciere.getByRole('button', { name: 'Confirmer et exécuter' })).toBeVisible();
        await confirmationFinanciere.getByRole('button', { name: 'Revenir au dossier' }).click();
        await expect(confirmationFinanciere).toBeHidden();
      } else {
        testInfo.annotations.push({ type: 'donnée absente', description: 'Aucun accord financier directement exécutable.' });
      }
    } else {
      testInfo.annotations.push({ type: 'donnée absente', description: 'Aucun litige en revue admin disponible.' });
    }

    await page.goto('/admin/contrats', { waitUntil: 'domcontentloaded' });
    await expectHealthyAdminView(page, 'liste contrats réelle');
    const contractCard = isMobile
      ? page.getByRole('listitem').first()
      : page.locator('a[href^="/admin/contrats/"]').first();
    if (await contractCard.count()) {
      await contractCard.click();
      await expect(page).toHaveURL(/\/admin\/contrats\/[^/?]+/);
      await expectHealthyAdminView(page, 'détail contrat réel');
      await capture(page, testInfo, '/admin/contrats/detail-reel', 'haut');
    } else {
      testInfo.annotations.push({ type: 'donnée absente', description: 'Aucun contrat réel disponible pour ouvrir un détail.' });
    }

    await page.goto('/admin/templates-contrats', { waitUntil: 'domcontentloaded' });
    await expectHealthyAdminView(page, 'liste templates réelle');
    const editTemplate = page.getByRole('button', { name: 'Éditer' }).first();
    if (await editTemplate.count()) {
      await editTemplate.click();
      await expect(page).toHaveURL(/\/admin\/templates-contrats\/[^/?]+/);
      await expectHealthyAdminView(page, 'éditeur de template réel sans sauvegarde');
      await capture(page, testInfo, '/admin/templates-contrats/detail-reel', 'haut');
    } else {
      testInfo.annotations.push({ type: 'donnée absente', description: 'Aucun template disponible pour ouvrir l’éditeur.' });
    }

    expect(consoleErrors, 'aucune erreur console pendant les interactions admin').toEqual([]);
    expect(pageErrors, 'aucune erreur JavaScript pendant les interactions admin').toEqual([]);
    expect(forbiddenResponses, 'aucune réponse API 401/403/5xx pendant les interactions admin').toEqual([]);
    expect(new URL(page.url()).pathname).not.toMatch(/2fa|mfa/i);
  });
});

import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { loginAs, TEST_ACCOUNTS } from '../helpers/auth';
import { adminClient, userIdByEmail } from '../helpers/db';
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

const ROUTES_SOIGNANT = [
  '/soignant/tableau-de-bord',
  '/soignant/recherche-missions',
  '/soignant/missions',
  '/soignant/mes-gains',
  '/soignant/messagerie',
  '/soignant/mes-documents',
  '/soignant/presences',
  '/soignant/score',
  '/soignant/evaluations',
  '/soignant/disponibilites',
  '/soignant/conformite',
  '/soignant/prevoyance',
  '/soignant/attestation-heures',
  '/soignant/passer-en-liberal',
  '/soignant/exclusions',
  '/soignant/charges',
  '/soignant/notifications',
  '/soignant/parrainage',
  '/soignant/litiges',
  '/soignant/pool-urgence',
  '/soignant/mes-favoris',
  '/soignant/parametres/notifications',
  '/soignant/parametres/recherches-sauvegardees',
  '/soignant/profil',
  '/soignant/mon-compte',
] as const;

const ROUTES_ETABLISSEMENT = [
  '/etablissement/tableau-de-bord',
  '/etablissement/missions',
  '/etablissement/missions/creer',
  '/etablissement/messagerie',
  '/etablissement/presences',
  '/etablissement/contrats',
  '/etablissement/facturation',
  '/etablissement/soignants',
  '/etablissement/mes-favoris',
  '/etablissement/pool-urgence',
  '/etablissement/equipe',
  '/etablissement/rh',
  '/etablissement/export-paie',
  '/etablissement/score',
  '/etablissement/evaluations-a-faire',
  '/etablissement/litiges',
  '/etablissement/notifications',
  '/etablissement/parrainage',
  '/etablissement/parametres/notifications',
  '/etablissement/parametres/recherches-sauvegardees',
  '/etablissement/parametres',
  '/etablissement/mon-compte',
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

async function auditRoute(page: Page, route: string): Promise<RouteAudit> {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  const onConsole = (message: { type(): string; text(): string }) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  };
  const onPageError = (error: Error) => pageErrors.push(error.message);
  try {
    await page.goto(route, { waitUntil: 'domcontentloaded' });
  } catch (error) {
    // WebKit peut signaler l'interruption lorsque le redirect post-login et
    // l'audit visent exactement la même URL. Ce n'est pas un échec de page :
    // attendre la navigation déjà en cours, puis vérifier l'URL obtenue.
    const sameDestinationRace = error instanceof Error
      && error.message.includes('is interrupted by another navigation')
      && new URL(page.url()).pathname === route;
    if (!sameDestinationRace) throw error;
    await page.waitForLoadState('domcontentloaded');
  }
  // N'écouter qu'après la navigation : WebKit remonte les fetch de la route
  // précédente, volontairement annulés par page.goto(), comme des erreurs
  // « due to access control checks ». Ils ne doivent pas être attribués à la
  // nouvelle interface. Les erreurs de montage/lazy-load restent capturées.
  page.on('console', onConsole);
  page.on('pageerror', onPageError);
  await expect(page.locator('#main-content')).toBeVisible();
  await page.waitForTimeout(500);

  const metrics = await page.evaluate(() => {
    const visible = (element: Element) => {
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
  for (const route of routes) results.push(await auditRoute(page, route));

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
  const runtimeErrors = results.filter((result) => result.pageErrors.length > 0);

  const summary = results
    .map((result) => ({
      route: result.route,
      overflow: result.horizontalOverflow,
      inputsBelow16px: result.inputsBelow16px.length,
      offscreenControls: result.offscreenControls.length,
      smallTouchTargets: result.smallTouchTargets.length,
      tinyTexts: result.tinyTexts.length,
      duplicateBackButtons: result.duplicateBackButtons,
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
  expect.soft(runtimeErrors.map(({ route, pageErrors }) => ({ route, pageErrors })),
    'aucune route ne doit lever une erreur JavaScript').toEqual([]);
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

  test('soignant — toutes les interfaces publiques du compte', async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await auditRole(page, testInfo, 'soignant', ROUTES_SOIGNANT);
  });

  test('établissement — toutes les interfaces publiques du compte', async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await auditRole(page, testInfo, 'etab', ROUTES_ETABLISSEMENT);
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

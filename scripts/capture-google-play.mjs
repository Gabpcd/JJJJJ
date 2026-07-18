#!/usr/bin/env node

/**
 * Captures Google Play Jolene pour téléphone, tablette 7" et tablette 10".
 *
 * Les identifiants ne sont lus que depuis l'environnement. Le script ne
 * sauvegarde sur disque ni storageState, ni trace, ni vidéo et ne capture
 * jamais l'écran de connexion. Les captures contiennent volontairement les
 * données démo visibles dans l'application.
 */

import { chmod, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CAPTURE_PROFILES = Object.freeze({
  phone: Object.freeze({
    directory: 'phone',
    viewport: Object.freeze({ width: 360, height: 640 }),
    deviceScaleFactor: 3,
    expectedPixels: Object.freeze({ width: 1080, height: 1920 }),
    isMobile: true,
  }),
  'tablet-7': Object.freeze({
    directory: 'tablet-7',
    viewport: Object.freeze({ width: 1280, height: 720 }),
    deviceScaleFactor: 1.5,
    expectedPixels: Object.freeze({ width: 1920, height: 1080 }),
    isMobile: false,
  }),
  'tablet-10': Object.freeze({
    directory: 'tablet-10',
    viewport: Object.freeze({ width: 1600, height: 900 }),
    deviceScaleFactor: 1.2,
    expectedPixels: Object.freeze({ width: 1920, height: 1080 }),
    isMobile: false,
  }),
  'iphone-6.5': Object.freeze({
    directory: 'iphone-6.5',
    viewport: Object.freeze({ width: 428, height: 926 }),
    deviceScaleFactor: 3,
    expectedPixels: Object.freeze({ width: 1284, height: 2778 }),
    isMobile: true,
  }),
  'iphone-6.9': Object.freeze({
    directory: 'iphone-6.9',
    viewport: Object.freeze({ width: 440, height: 956 }),
    deviceScaleFactor: 3,
    expectedPixels: Object.freeze({ width: 1320, height: 2868 }),
    isMobile: true,
  }),
  'ipad-13': Object.freeze({
    directory: 'ipad-13',
    viewport: Object.freeze({ width: 1032, height: 1376 }),
    deviceScaleFactor: 2,
    expectedPixels: Object.freeze({ width: 2064, height: 2752 }),
    isMobile: false,
  }),
  'ipad-13-landscape': Object.freeze({
    directory: 'ipad-13-landscape',
    viewport: Object.freeze({ width: 1376, height: 1032 }),
    deviceScaleFactor: 2,
    expectedPixels: Object.freeze({ width: 2752, height: 2064 }),
    isMobile: false,
  }),
});

const CAPTURE_STORES = Object.freeze({
  'google-play': Object.freeze(['phone', 'tablet-7', 'tablet-10']),
  'app-store': Object.freeze(['iphone-6.5', 'iphone-6.9', 'ipad-13', 'ipad-13-landscape']),
});

const CAPTURE_STYLE_ID = 'jolene-store-capture-stabilizer';
const CAPTURE_ACTIONS = new Set(['explorer-list', 'missions-past', 'conversation-marie']);
const CAPTURE_CSS = `
  html,
  body,
  #root,
  #root > div,
  #root > div > div,
  #app-route-content,
  main,
  main > div {
    background-color: #fff !important;
  }

  html {
    color-scheme: light !important;
    scroll-behavior: auto !important;
  }

  *,
  *::before,
  *::after {
    animation-delay: 0s !important;
    animation-duration: 0s !important;
    transition-delay: 0s !important;
    transition-duration: 0s !important;
  }

  [class*="backdrop-blur"] {
    -webkit-backdrop-filter: none !important;
    backdrop-filter: none !important;
  }

  header[role="banner"] {
    position: relative !important;
    top: auto !important;
    background-color: #fff !important;
    -webkit-backdrop-filter: none !important;
    backdrop-filter: none !important;
  }

  .mobile-nav-bottom {
    background-color: #fff !important;
    -webkit-backdrop-filter: none !important;
    backdrop-filter: none !important;
  }
`;

const CAPTURE_TARGETS = Object.freeze([
  { role: 'soignant', path: '/soignant/tableau-de-bord', file: '01-soignant-accueil.png', heading: /^(Bonjour|Bonsoir),/ },
  { role: 'soignant', path: '/soignant/recherche-missions', file: '02-soignant-explorer.png', heading: /^Explorer$/, action: 'explorer-list' },
  { role: 'soignant', path: '/soignant/missions', file: '03-soignant-mes-missions.png', heading: /^Mes missions$/, action: 'missions-past' },
  { role: 'soignant', path: '/soignant/mes-gains', file: '04-soignant-revenus.png', heading: /Revenus/ },
  { role: 'etablissement', path: '/etablissement/tableau-de-bord', file: '05-etablissement-accueil.png', heading: /^(Bonjour,|Publiez votre première mission|Tableau de bord$)/ },
  { role: 'etablissement', path: '/etablissement/missions', file: '06-etablissement-missions.png', heading: /^Mes missions$/ },
  { role: 'etablissement', path: '/etablissement/messagerie', file: '07-etablissement-messagerie.png', heading: /^Messagerie$/, action: 'conversation-marie' },
  { role: 'etablissement', path: '/etablissement/facturation', file: '08-etablissement-facturation.png', heading: /^Facturation$/ },
]);

const ACCOUNT_ENV = Object.freeze({
  soignant: Object.freeze({
    email: 'JOLENE_STORE_SOIGNANT_EMAIL',
    password: 'JOLENE_STORE_SOIGNANT_PASSWORD',
    expectedPath: '/soignant/tableau-de-bord',
  }),
  etablissement: Object.freeze({
    email: 'JOLENE_STORE_ETAB_EMAIL',
    password: 'JOLENE_STORE_ETAB_PASSWORD',
    expectedPath: '/etablissement/tableau-de-bord',
  }),
});

function parseBoolean(value, defaultValue) {
  if (value === undefined) return defaultValue;
  if (/^(1|true|yes)$/i.test(value)) return true;
  if (/^(0|false|no)$/i.test(value)) return false;
  throw new Error('HEADLESS doit valoir true/false, 1/0 ou yes/no.');
}

function parseStore(value) {
  const store = (value || 'google-play').trim().toLowerCase();
  if (!CAPTURE_STORES[store]) {
    throw new Error(`CAPTURE_STORE doit valoir : ${Object.keys(CAPTURE_STORES).join(' ou ')}.`);
  }
  return store;
}

function parseProfiles(value, store) {
  const available = CAPTURE_STORES[store];
  if (!value || value.trim().toLowerCase() === 'all') return available;

  const requested = [...new Set(
    value
      .split(',')
      .map((profile) => profile.trim().toLowerCase())
      .filter(Boolean),
  )];
  if (requested.length === 0) {
    throw new Error(`CAPTURE_FORMATS doit contenir au moins un format parmi : ${available.join(', ')}.`);
  }

  const unknown = requested.filter((profile) => !CAPTURE_PROFILES[profile]);
  if (unknown.length > 0) {
    throw new Error(`Formats de capture inconnus : ${unknown.join(', ')}. Formats valides : ${available.join(', ')}.`);
  }
  return requested;
}

function readConfig() {
  const baseUrl = new URL(process.env.BASE_URL || 'https://jolene.app');
  if (!['http:', 'https:'].includes(baseUrl.protocol)) {
    throw new Error('BASE_URL doit utiliser http ou https.');
  }

  const store = parseStore(process.env.CAPTURE_STORE);
  const requestedOutput = process.env.OUTPUT_DIR || path.join('artifacts', store);
  const outputDir = path.resolve(REPO_ROOT, requestedOutput);
  const relativeOutput = path.relative(REPO_ROOT, outputDir);
  const outputIsInRepo = relativeOutput !== '..' && !relativeOutput.startsWith(`..${path.sep}`) && !path.isAbsolute(relativeOutput);
  const outputIsIgnoredArtifact = relativeOutput === 'artifacts' || relativeOutput.startsWith(`artifacts${path.sep}`);
  if (outputIsInRepo && !outputIsIgnoredArtifact) {
    throw new Error('OUTPUT_DIR doit être hors du dépôt ou sous artifacts/ (ignoré par Git).');
  }

  return {
    baseUrl,
    store,
    outputDir,
    headless: parseBoolean(process.env.HEADLESS, true),
    profiles: parseProfiles(process.env.CAPTURE_FORMATS, store),
  };
}

function validateTargets() {
  const files = new Set();
  for (const target of CAPTURE_TARGETS) {
    if (!ACCOUNT_ENV[target.role]) throw new Error(`Rôle de capture inconnu : ${target.role}`);
    if (!target.path.startsWith('/')) throw new Error(`Route invalide : ${target.path}`);
    if (!/^\d{2}-[a-z0-9-]+\.png$/.test(target.file)) throw new Error(`Nom de PNG invalide : ${target.file}`);
    if (target.action && !CAPTURE_ACTIONS.has(target.action)) throw new Error(`Action de capture inconnue : ${target.action}`);
    if (files.has(target.file)) throw new Error(`Nom de PNG dupliqué : ${target.file}`);
    files.add(target.file);
  }

  for (const [name, profile] of Object.entries(CAPTURE_PROFILES)) {
    const width = profile.viewport.width * profile.deviceScaleFactor;
    const height = profile.viewport.height * profile.deviceScaleFactor;
    if (width !== profile.expectedPixels.width || height !== profile.expectedPixels.height) {
      throw new Error(`Configuration de rendu invalide pour ${name} : ${width}x${height}.`);
    }
    if (!/^[a-z0-9.-]+$/.test(profile.directory)) {
      throw new Error(`Dossier de profil invalide pour ${name} : ${profile.directory}.`);
    }
  }
}

function readAccounts() {
  const missing = [];
  const accounts = {};

  for (const [role, names] of Object.entries(ACCOUNT_ENV)) {
    const email = process.env[names.email];
    const password = process.env[names.password];
    if (!email) missing.push(names.email);
    if (!password) missing.push(names.password);
    accounts[role] = { email, password, expectedPath: names.expectedPath };
  }

  if (missing.length > 0) {
    throw new Error(`Variables d'environnement manquantes : ${missing.join(', ')}`);
  }
  return accounts;
}

function resolveUrl(baseUrl, route) {
  return new URL(route, baseUrl).href;
}

function pngDimensions(buffer) {
  const pngSignature = '89504e470d0a1a0a';
  if (buffer.length < 24 || buffer.subarray(0, 8).toString('hex') !== pngSignature) {
    throw new Error('La capture produite n’est pas un PNG valide.');
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

async function installCaptureEnvironment(context, baseUrl, authSessionEntries = []) {
  await context.addInitScript(({ appOrigin, authEntries, css, styleId }) => {
    // Ne jamais injecter la session dans un éventuel iframe tiers (Turnstile).
    if (window.location.origin !== appOrigin) return;

    try {
      for (const [key, value] of authEntries) {
        sessionStorage.setItem(key, value);
      }

      // Équivaut au clic sur « Accepter ». Cela empêche le bandeau différé
      // (1,5 s) de recouvrir les captures sans masquer de données de démo.
      localStorage.setItem('cookie-consent', 'accepted');
      localStorage.setItem('cookie-consent-date', new Date().toISOString());
    } catch {
      // Certaines pages intermédiaires sans origine n'exposent pas le stockage.
    }

    const installStyle = () => {
      if (!document.head) return;
      let style = document.getElementById(styleId);
      if (!(style instanceof HTMLStyleElement)) {
        style = document.createElement('style');
        style.id = styleId;
        document.head.appendChild(style);
      }
      style.textContent = css;
    };

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', installStyle, { once: true });
    } else {
      installStyle();
    }
  }, {
    appOrigin: baseUrl.origin,
    authEntries: authSessionEntries,
    css: CAPTURE_CSS,
    styleId: CAPTURE_STYLE_ID,
  });
}

async function ensureCaptureStyle(page) {
  await page.evaluate(({ css, styleId }) => {
    let style = document.getElementById(styleId);
    if (!(style instanceof HTMLStyleElement)) {
      style = document.createElement('style');
      style.id = styleId;
      document.head.appendChild(style);
    }
    style.textContent = css;
  }, { css: CAPTURE_CSS, styleId: CAPTURE_STYLE_ID });
}

async function dismissCookieConsent(page) {
  const acceptButton = page.getByRole('button', { name: /^Accepter$/i });
  await acceptButton.waitFor({ state: 'visible', timeout: 1_800 }).catch(() => {});
  if (await acceptButton.isVisible().catch(() => false)) {
    await acceptButton.click();
    await acceptButton.waitFor({ state: 'hidden', timeout: 3_000 }).catch(() => {});
  }
}

async function login(page, baseUrl, account) {
  await page.goto(resolveUrl(baseUrl, '/connexion'), { waitUntil: 'domcontentloaded' });
  await dismissCookieConsent(page);
  const email = page.locator('#connexion-email');
  const password = page.locator('#connexion-mot-de-passe');
  await email.waitFor({ state: 'visible', timeout: 20_000 });
  await email.fill(account.email);
  await password.fill(account.password);
  await page.getByTestId('login-submit').click();

  try {
    await page.waitForURL(
      (url) => url.pathname === account.expectedPath,
      { timeout: 45_000 },
    );
  } catch {
    throw new Error('La connexion n’a pas atteint le tableau de bord attendu. Vérifier le compte et le rôle.');
  }
}

async function clickFirstVisible(locator) {
  const count = await locator.count();
  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);
    if (await candidate.isVisible().catch(() => false)) {
      await candidate.click({ timeout: 2_000 }).catch(() => {});
      return true;
    }
  }
  return false;
}

async function dismissTransientUi(page) {
  // Les actions sont uniquement des fermetures explicites : aucune donnée de
  // démonstration n'est supprimée, masquée via CSS ou modifiée côté serveur.
  for (let pass = 0; pass < 5; pass += 1) {
    const dialog = page.locator('[role="dialog"]:visible').first();
    if (await dialog.isVisible().catch(() => false)) {
      const dismissedDialog = await clickFirstVisible(
        dialog.getByRole('button', {
          name: /^(Plus tard|Fermer|Annuler|Compris, ne plus afficher)$/i,
        }),
      );
      if (!dismissedDialog) {
        await page.keyboard.press('Escape').catch(() => {});
      }
      await page.waitForTimeout(150);
      continue;
    }

    const dismissedBanner = await clickFirstVisible(
      page.getByRole('button', {
        name: /^(Fermer|Masquer|Masquer définitivement)$/i,
      }),
    );
    if (!dismissedBanner) break;
    await page.waitForTimeout(150);
  }
}

async function preventCaptureMutations(page, target, baseUrl) {
  if (target.action !== 'conversation-marie') return;

  // L'ouverture d'une conversation appelle normalement cette RPC et marque
  // les messages comme lus. Pour une capture, on simule seulement sa réponse
  // afin de conserver intact l'état des données de démonstration.
  await page.route('**/rest/v1/rpc/fn_marquer_messages_lus', async (route) => {
    const requestedHeaders = route.request().headers()['access-control-request-headers'];
    const corsHeaders = {
      'access-control-allow-origin': baseUrl.origin,
      'access-control-allow-headers': requestedHeaders || 'authorization, x-client-info, apikey, content-type',
      'access-control-allow-methods': 'POST, OPTIONS',
      vary: 'Origin',
    };
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: corsHeaders });
      return;
    }
    await route.fulfill({
      status: 200,
      headers: { ...corsHeaders, 'content-type': 'application/json' },
      body: 'null',
    });
  });
}

async function prepareTarget(page, target) {
  if (!target.action) return;

  if (target.action === 'explorer-list') {
    const listTab = page.getByRole('tab', { name: /^Liste$/ }).first();
    await listTab.waitFor({ state: 'visible', timeout: 20_000 });
    if (await listTab.getAttribute('aria-selected') !== 'true') {
      await listTab.click();
    }
    await page.waitForFunction(() => {
      const tabs = [...document.querySelectorAll('[role="tab"]')];
      return tabs.some((tab) => tab.textContent?.trim() === 'Liste' && tab.getAttribute('aria-selected') === 'true');
    }, undefined, { timeout: 5_000 });
    return;
  }

  if (target.action === 'missions-past') {
    const pastButton = page.getByRole('button', { name: /^Passées$/ }).first();
    await pastButton.waitFor({ state: 'visible', timeout: 20_000 });
    if (!(await pastButton.getAttribute('class'))?.includes('border-primary')) {
      await pastButton.click();
    }
    await page.waitForFunction(() => {
      const buttons = [...document.querySelectorAll('button')];
      return buttons.some((button) => (
        button.textContent?.trim() === 'Passées'
        && button.classList.contains('border-primary')
      ));
    }, undefined, { timeout: 5_000 });
    return;
  }

  if (target.action === 'conversation-marie') {
    const marieConversation = page.getByRole('button', { name: /Marie\s+Lef[eè]vre/i }).first();
    await marieConversation.waitFor({ state: 'visible', timeout: 20_000 });
    await marieConversation.click();
    await page.waitForURL((url) => (
      url.pathname === target.path && Boolean(url.searchParams.get('conv'))
    ), { timeout: 10_000 });
    await page.getByText(/Marie\s+Lef[eè]vre/i).last().waitFor({ state: 'visible', timeout: 10_000 });
    await page.getByText(/^Chargement…$/).last().waitFor({ state: 'hidden', timeout: 15_000 }).catch(() => {});
    return;
  }

  throw new Error(`Action de capture inconnue : ${target.action}`);
}

async function waitUntilReady(page, baseUrl, target) {
  await page.goto(resolveUrl(baseUrl, target.path), { waitUntil: 'domcontentloaded' });
  if (new URL(page.url()).pathname === '/connexion') {
    throw new Error(`La session a expiré avant la capture de ${target.path}.`);
  }
  await page.locator('main').waitFor({ state: 'visible', timeout: 20_000 });
  await page.getByRole('heading', { level: 1, name: target.heading }).waitFor({ state: 'visible', timeout: 20_000 });
  if (new URL(page.url()).pathname !== target.path) {
    throw new Error(`Redirection inattendue avant la capture de ${target.path}.`);
  }
  await page.locator('main [aria-label="Chargement en cours"], main .card-base.animate-pulse')
    .first()
    .waitFor({ state: 'hidden', timeout: 15_000 })
    .catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
  await ensureCaptureStyle(page);
  await dismissTransientUi(page);
  await prepareTarget(page, target);
  await page.locator('main [aria-label="Chargement en cours"], main .card-base.animate-pulse')
    .first()
    .waitFor({ state: 'hidden', timeout: 15_000 })
    .catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 6_000 }).catch(() => {});
  await page.evaluate(async () => {
    await document.fonts?.ready;
    window.scrollTo({ top: 0, left: 0, behavior: 'instant' });
  });
  await dismissTransientUi(page);

  // Les toasts de connexion/navigation disparaissent naturellement : on ne
  // retire aucun nœud du DOM pour nettoyer artificiellement l'image.
  await page.locator('[data-sonner-toast]').first().waitFor({ state: 'hidden', timeout: 6_000 }).catch(() => {});
  await page.waitForTimeout(350);
  await dismissTransientUi(page);
  await ensureCaptureStyle(page);
  if (new URL(page.url()).pathname !== target.path) {
    throw new Error(`La session a expiré avant la capture de ${target.path}.`);
  }
}

async function createCaptureContext(browser, config, profile, authSessionEntries = []) {
  const context = await browser.newContext({
    viewport: profile.viewport,
    screen: profile.viewport,
    deviceScaleFactor: profile.deviceScaleFactor,
    hasTouch: true,
    isMobile: profile.isMobile,
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    colorScheme: 'light',
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
  });
  await installCaptureEnvironment(context, config.baseUrl, authSessionEntries);
  return context;
}

async function authenticateRole(browser, config, account) {
  const context = await createCaptureContext(browser, config, CAPTURE_PROFILES.phone);
  const page = await context.newPage();
  page.on('dialog', (dialog) => dialog.dismiss().catch(() => {}));

  try {
    await login(page, config.baseUrl, account);
    await page.locator('main').waitFor({ state: 'visible', timeout: 20_000 });

    // Supabase utilise sessionStorage dans cette application. On ne garde en
    // mémoire que son entrée d'authentification, jamais dans un fichier.
    const authSessionEntries = await page.evaluate(() => (
      Object.entries(sessionStorage).filter(([key]) => (
        key.startsWith('sb-') && key.endsWith('-auth-token')
      ))
    ));
    if (authSessionEntries.length !== 1) {
      throw new Error('La session Supabase attendue est absente après la connexion.');
    }
    return authSessionEntries;
  } finally {
    await context.close();
  }
}

async function captureTarget(browser, config, profileName, authSessionEntries, target) {
  const profile = CAPTURE_PROFILES[profileName];
  const context = await createCaptureContext(browser, config, profile, authSessionEntries);
  const page = await context.newPage();
  page.on('dialog', (dialog) => dialog.dismiss().catch(() => {}));

  try {
    await preventCaptureMutations(page, target, config.baseUrl);
    await waitUntilReady(page, config.baseUrl, target);

    const profileOutputDir = path.join(config.outputDir, profile.directory);
    await mkdir(profileOutputDir, { recursive: true, mode: 0o700 });
    const outputPath = path.join(profileOutputDir, target.file);
    const buffer = await page.screenshot({
      path: outputPath,
      type: 'png',
      fullPage: false,
      animations: 'disabled',
      caret: 'hide',
      scale: 'device',
    });
    const dimensions = pngDimensions(buffer);
    if (
      dimensions.width !== profile.expectedPixels.width
      || dimensions.height !== profile.expectedPixels.height
    ) {
      throw new Error(
        `${profileName}/${target.file} mesure ${dimensions.width}x${dimensions.height}, `
        + `attendu ${profile.expectedPixels.width}x${profile.expectedPixels.height}.`,
      );
    }
    await chmod(outputPath, 0o600);
    console.log(`OK  ${profile.directory}/${target.file}  ${dimensions.width}x${dimensions.height}`);
  } finally {
    await context.close();
  }
}

async function captureRole(browser, config, role, authSessionEntries) {
  const targets = CAPTURE_TARGETS.filter((target) => target.role === role);
  for (const profileName of config.profiles) {
    for (const target of targets) {
      await captureTarget(browser, config, profileName, authSessionEntries, target);
    }
  }
}

function printHelp() {
  console.log(`Usage : npm run screenshots:play | npm run screenshots:app-store

Variables obligatoires :
  JOLENE_STORE_SOIGNANT_EMAIL
  JOLENE_STORE_SOIGNANT_PASSWORD
  JOLENE_STORE_ETAB_EMAIL
  JOLENE_STORE_ETAB_PASSWORD

Variables optionnelles :
  BASE_URL        défaut : https://jolene.app
  CAPTURE_STORE   défaut : google-play (ou app-store)
  OUTPUT_DIR      défaut : artifacts/<CAPTURE_STORE>
  CAPTURE_FORMATS défaut : all (formats du store sélectionné, séparés par des virgules)
  HEADLESS        défaut : true (utiliser false si Turnstile demande une action)

Vérification sans navigateur ni identifiants :
  npm run screenshots:play:check
  npm run screenshots:app-store:check`);
}

async function main() {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    printHelp();
    return;
  }

  validateTargets();
  const config = readConfig();
  if (process.argv.includes('--check')) {
    const summary = config.profiles.map((profileName) => {
      const profile = CAPTURE_PROFILES[profileName];
      return `${profileName} ${profile.expectedPixels.width}x${profile.expectedPixels.height}`;
    }).join(', ');
    console.log(`OK  configuration : ${CAPTURE_TARGETS.length * config.profiles.length} PNG (${summary})`);
    return;
  }

  const accounts = readAccounts();
  await mkdir(config.outputDir, { recursive: true, mode: 0o700 });

  let browser;
  try {
    browser = await chromium.launch({
      headless: config.headless,
      args: [
        '--disable-save-password-bubble',
        '--disable-features=PasswordManagerOnboarding,PasswordManagerAccountStorage',
        '--disable-gpu-compositing',
        '--force-color-profile=srgb',
      ],
    });
  } catch {
    throw new Error('Chromium Playwright est indisponible. Exécuter : npx playwright install chromium');
  }

  try {
    const soignantSession = await authenticateRole(browser, config, accounts.soignant);
    await captureRole(browser, config, 'soignant', soignantSession);

    const etablissementSession = await authenticateRole(browser, config, accounts.etablissement);
    await captureRole(browser, config, 'etablissement', etablissementSession);
  } finally {
    await browser.close();
  }

  console.log(`Captures ${config.store} prêtes dans ${config.outputDir}`);
}

main().catch((error) => {
  console.error(`[captures stores] ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});

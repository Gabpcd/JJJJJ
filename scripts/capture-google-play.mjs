#!/usr/bin/env node

/**
 * Captures Google Play Jolene (PNG 1080 x 1920).
 *
 * Les identifiants ne sont lus que depuis l'environnement. Le script ne
 * sauvegarde ni storageState, ni trace, ni vidéo et ne capture jamais l'écran
 * de connexion. Les captures contiennent volontairement les données démo
 * visibles dans l'application.
 */

import { chmod, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CSS_VIEWPORT = Object.freeze({ width: 360, height: 640 });
const DEVICE_SCALE_FACTOR = 3;
const EXPECTED_PIXELS = Object.freeze({ width: 1080, height: 1920 });

const CAPTURE_TARGETS = Object.freeze([
  { role: 'soignant', path: '/soignant/tableau-de-bord', file: '01-soignant-accueil.png', heading: /^(Bonjour|Bonsoir),/ },
  { role: 'soignant', path: '/soignant/recherche-missions', file: '02-soignant-explorer.png', heading: /^Explorer$/ },
  { role: 'soignant', path: '/soignant/missions', file: '03-soignant-mes-missions.png', heading: /^Mes missions$/ },
  { role: 'soignant', path: '/soignant/mes-gains', file: '04-soignant-revenus.png', heading: /Revenus/ },
  { role: 'etablissement', path: '/etablissement/tableau-de-bord', file: '05-etablissement-accueil.png', heading: /^(Bonjour,|Publiez votre première mission|Tableau de bord$)/ },
  { role: 'etablissement', path: '/etablissement/missions', file: '06-etablissement-missions.png', heading: /^Mes missions$/ },
  { role: 'etablissement', path: '/etablissement/presences', file: '07-etablissement-presences.png', heading: /Présences à valider/ },
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

function readConfig() {
  const baseUrl = new URL(process.env.BASE_URL || 'https://jolene.app');
  if (!['http:', 'https:'].includes(baseUrl.protocol)) {
    throw new Error('BASE_URL doit utiliser http ou https.');
  }

  const requestedOutput = process.env.OUTPUT_DIR || path.join('artifacts', 'google-play');
  const outputDir = path.resolve(REPO_ROOT, requestedOutput);
  const relativeOutput = path.relative(REPO_ROOT, outputDir);
  const outputIsInRepo = relativeOutput !== '..' && !relativeOutput.startsWith(`..${path.sep}`) && !path.isAbsolute(relativeOutput);
  const outputIsIgnoredArtifact = relativeOutput === 'artifacts' || relativeOutput.startsWith(`artifacts${path.sep}`);
  if (outputIsInRepo && !outputIsIgnoredArtifact) {
    throw new Error('OUTPUT_DIR doit être hors du dépôt ou sous artifacts/ (ignoré par Git).');
  }

  return {
    baseUrl,
    outputDir,
    headless: parseBoolean(process.env.HEADLESS, true),
  };
}

function validateTargets() {
  const files = new Set();
  for (const target of CAPTURE_TARGETS) {
    if (!ACCOUNT_ENV[target.role]) throw new Error(`Rôle de capture inconnu : ${target.role}`);
    if (!target.path.startsWith('/')) throw new Error(`Route invalide : ${target.path}`);
    if (!/^\d{2}-[a-z0-9-]+\.png$/.test(target.file)) throw new Error(`Nom de PNG invalide : ${target.file}`);
    if (files.has(target.file)) throw new Error(`Nom de PNG dupliqué : ${target.file}`);
    files.add(target.file);
  }

  const width = CSS_VIEWPORT.width * DEVICE_SCALE_FACTOR;
  const height = CSS_VIEWPORT.height * DEVICE_SCALE_FACTOR;
  if (width !== EXPECTED_PIXELS.width || height !== EXPECTED_PIXELS.height) {
    throw new Error(`Configuration de rendu invalide : ${width}x${height}.`);
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

async function waitForTurnstile(page) {
  const widget = page.locator('iframe[src*="challenges.cloudflare.com"], [name="cf-turnstile-response"]');
  await widget.first().waitFor({ state: 'attached', timeout: 3_000 }).catch(() => {});
  if ((await widget.count()) === 0) return;

  const responseField = page.locator('[name="cf-turnstile-response"]');
  await responseField.first().waitFor({ state: 'attached', timeout: 10_000 }).catch(() => {});
  if ((await responseField.count()) === 0) {
    throw new Error('Le widget Turnstile est présent mais son champ de validation ne s’est pas initialisé.');
  }

  try {
    await page.waitForFunction(() => {
      const input = document.querySelector('[name="cf-turnstile-response"]');
      return input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement
        ? input.value.length > 0
        : false;
    }, undefined, { timeout: 240_000 });
  } catch {
    throw new Error('Turnstile n’a pas validé la connexion. Relancer avec HEADLESS=false pour traiter un éventuel challenge.');
  }
}

async function dismissCookieConsent(page) {
  const acceptButton = page.getByRole('button', { name: /^Accepter$/i });
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
  await waitForTurnstile(page);
  await page.getByTestId('login-submit').click();

  try {
    await page.waitForURL(
      (url) => url.pathname === account.expectedPath,
      { timeout: 45_000 },
    );
  } catch {
    throw new Error('La connexion n’a pas atteint le tableau de bord attendu. Vérifier le compte, le rôle et Turnstile.');
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
  if (new URL(page.url()).pathname !== target.path) {
    throw new Error(`La session a expiré avant la capture de ${target.path}.`);
  }
}

async function captureRole(browser, config, role, account) {
  const context = await browser.newContext({
    viewport: CSS_VIEWPORT,
    screen: CSS_VIEWPORT,
    deviceScaleFactor: DEVICE_SCALE_FACTOR,
    hasTouch: true,
    isMobile: true,
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    colorScheme: 'light',
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.on('dialog', (dialog) => dialog.dismiss().catch(() => {}));

  try {
    await login(page, config.baseUrl, account);
    const targets = CAPTURE_TARGETS.filter((target) => target.role === role);
    for (const target of targets) {
      await waitUntilReady(page, config.baseUrl, target);
      const outputPath = path.join(config.outputDir, target.file);
      const buffer = await page.screenshot({
        path: outputPath,
        type: 'png',
        fullPage: false,
        animations: 'disabled',
        caret: 'hide',
        scale: 'device',
      });
      const dimensions = pngDimensions(buffer);
      if (dimensions.width !== EXPECTED_PIXELS.width || dimensions.height !== EXPECTED_PIXELS.height) {
        throw new Error(`${target.file} mesure ${dimensions.width}x${dimensions.height}, attendu ${EXPECTED_PIXELS.width}x${EXPECTED_PIXELS.height}.`);
      }
      await chmod(outputPath, 0o600);
      console.log(`OK  ${target.file}  ${dimensions.width}x${dimensions.height}`);
    }
  } finally {
    await context.close();
  }
}

function printHelp() {
  console.log(`Usage : npm run screenshots:play

Variables obligatoires :
  JOLENE_STORE_SOIGNANT_EMAIL
  JOLENE_STORE_SOIGNANT_PASSWORD
  JOLENE_STORE_ETAB_EMAIL
  JOLENE_STORE_ETAB_PASSWORD

Variables optionnelles :
  BASE_URL     défaut : https://jolene.app
  OUTPUT_DIR   défaut : artifacts/google-play
  HEADLESS     défaut : true (utiliser false si Turnstile demande une action)

Vérification sans navigateur ni identifiants :
  npm run screenshots:play:check`);
}

async function main() {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    printHelp();
    return;
  }

  validateTargets();
  const config = readConfig();
  if (process.argv.includes('--check')) {
    console.log(`OK  configuration : ${CAPTURE_TARGETS.length} PNG ${EXPECTED_PIXELS.width}x${EXPECTED_PIXELS.height}`);
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
      ],
    });
  } catch {
    throw new Error('Chromium Playwright est indisponible. Exécuter : npx playwright install chromium');
  }

  try {
    await captureRole(browser, config, 'soignant', accounts.soignant);
    await captureRole(browser, config, 'etablissement', accounts.etablissement);
  } finally {
    await browser.close();
  }

  console.log(`Captures prêtes dans ${config.outputDir}`);
}

main().catch((error) => {
  console.error(`[captures Google Play] ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});

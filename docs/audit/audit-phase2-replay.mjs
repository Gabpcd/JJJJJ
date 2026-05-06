// Audit Phase 2 — script de replay pour env avec accès supabase.co
//
// Usage :
//   1. Démarrer le dev server : npx vite --host 127.0.0.1 --port 8080
//   2. Installer chromium si besoin : npx playwright install chromium
//   3. Lancer : node docs/audit/audit-phase2-replay.mjs
//
// Le script écrit screenshots dans docs/audit/screenshots/ et résultats
// dans docs/audit/screenshots/results.json.
//
// Comptes test attendus (créés en Phase 1, mot de passe auditTest2026!) :
//   audit-as@jolene-test.dev, audit-pharmacie@jolene-test.dev

import { chromium } from 'playwright';
import fs from 'fs/promises';
import path from 'path';

const URL = 'http://127.0.0.1:8080';
const SHOTS = 'docs/audit/screenshots';
const PWD = 'auditTest2026!';
const TS = Date.now();
const newEmail = (slug) => `audit-pw-${slug}-${TS}@jolene-test.dev`;
const results = [];

async function shot(page, name) {
  const file = path.join(SHOTS, `${name}.png`);
  try { await page.screenshot({ path: file, fullPage: true }); return file; }
  catch (e) { return `(failed: ${e.message})`; }
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });

// S1 — Inscription IDE (RPPS test 00000000001)
{
  const page = await ctx.newPage();
  const email = newEmail('ide');
  const screenshots = [];
  const bugs = [];
  try {
    await page.goto(`${URL}/inscription/soignant`, { waitUntil: 'networkidle' });
    screenshots.push(await shot(page, 's1-01-page'));
    await page.locator('input[type="email"]').fill(email);
    await page.locator('input[type="password"]').first().fill(PWD);
    await page.locator('input[type="password"]').nth(1).fill(PWD);
    await page.locator('input[type="checkbox"]').first().check();
    await page.getByRole('button', { name: /continuer/i }).click();
    await page.waitForTimeout(800);
    await page.locator('label:has-text("Prénom") ~ input').first().fill('Gabrielle');
    await page.locator('label:has-text("Nom") ~ input').first().fill('PICARD');
    await page.locator('input[type="date"]').first().fill('1990-01-01');
    await page.getByRole('combobox').click();
    await page.waitForTimeout(300);
    await page.getByRole('option').filter({ hasText: /Infirmier/i }).first().click();
    await page.waitForTimeout(400);
    await page.locator('label:has-text("CDD")').first().click().catch(() => {});
    await page.locator('input[placeholder*="11 chiffres"]').fill('00000000001');
    await page.waitForTimeout(2500);
    screenshots.push(await shot(page, 's1-rpps'));
    if (!await page.getByText(/RPPS Vérifié/i).first().isVisible().catch(() => false))
      bugs.push({ severity: 'P1', desc: 'Badge RPPS Vérifié absent' });
    await page.getByRole('button', { name: /Créer mon compte/i }).click();
    await page.waitForTimeout(5000);
    screenshots.push(await shot(page, 's1-after'));
    if (!page.url().includes('/soignant')) bugs.push({ severity: 'P1', desc: 'Pas de redirect dashboard' });
    results.push({ scenario: 'S1 IDE', status: bugs.length ? 'FAIL' : 'PASS', email, bugs, screenshots });
  } catch (e) {
    results.push({ scenario: 'S1 IDE', status: 'FAIL', error: e.message, screenshots });
  }
  await page.close();
}

// S2 — Inscription AS sans RPPS
{
  const page = await ctx.newPage();
  const email = newEmail('as');
  const screenshots = [];
  const bugs = [];
  try {
    await page.goto(`${URL}/inscription/soignant`, { waitUntil: 'networkidle' });
    await page.locator('input[type="email"]').fill(email);
    await page.locator('input[type="password"]').first().fill(PWD);
    await page.locator('input[type="password"]').nth(1).fill(PWD);
    await page.locator('input[type="checkbox"]').first().check();
    await page.getByRole('button', { name: /continuer/i }).click();
    await page.waitForTimeout(800);
    await page.locator('label:has-text("Prénom") ~ input').first().fill('Sophie');
    await page.locator('label:has-text("Nom") ~ input').first().fill('MARTIN');
    await page.locator('input[type="date"]').first().fill('1985-03-15');
    await page.getByRole('combobox').click();
    await page.waitForTimeout(300);
    await page.getByRole('option').filter({ hasText: /Aide-soignant/i }).first().click();
    await page.waitForTimeout(500);
    screenshots.push(await shot(page, 's2-as'));
    if (await page.locator('input[placeholder*="11 chiffres"]').isVisible().catch(() => false))
      bugs.push({ severity: 'P1', desc: 'Champ RPPS visible pour AS' });
    if (await page.locator('label:has-text("Libéral")').first().isVisible().catch(() => false))
      bugs.push({ severity: 'P1', desc: 'Checkbox LIBERAL visible pour AS' });
    if (await page.locator('label:has-text("Vacation")').first().isVisible().catch(() => false))
      bugs.push({ severity: 'P1', desc: 'Checkbox VACATION visible pour AS' });
    await page.locator('label:has-text("CDD")').first().click().catch(() => {});
    await page.getByRole('button', { name: /Créer mon compte/i }).click();
    await page.waitForTimeout(5000);
    screenshots.push(await shot(page, 's2-after'));
    if (!page.url().includes('/soignant')) bugs.push({ severity: 'P1', desc: 'Pas de redirect dashboard' });
    results.push({ scenario: 'S2 AS', status: bugs.length ? 'FAIL' : 'PASS', email, bugs, screenshots });
  } catch (e) {
    results.push({ scenario: 'S2 AS', status: 'FAIL', error: e.message, screenshots });
  }
  await page.close();
}

// Bonus 2 — login AS, vérifier profil pas de RPPS
{
  const page = await ctx.newPage();
  const screenshots = [];
  const bugs = [];
  try {
    await page.goto(`${URL}/connexion`, { waitUntil: 'networkidle' });
    await page.locator('input[type="email"]').fill('audit-as@jolene-test.dev');
    await page.locator('input[type="password"]').fill(PWD);
    await page.getByRole('button', { name: /se connecter|connexion/i }).first().click();
    await page.waitForTimeout(4000);
    if (!page.url().includes('/soignant')) {
      bugs.push({ severity: 'P1', desc: `Login échoué. URL: ${page.url()}` });
    } else {
      await page.goto(`${URL}/soignant/profil`, { waitUntil: 'networkidle' });
      await page.waitForTimeout(1500);
      screenshots.push(await shot(page, 'b2-profil'));
      if (await page.getByText(/Vérification RPPS|Numéro RPPS/i).first().isVisible().catch(() => false))
        bugs.push({ severity: 'P1', desc: 'Section RPPS visible pour AS' });
      if (!await page.getByText(/Identification professionnelle/i).first().isVisible().catch(() => false))
        bugs.push({ severity: 'P2', desc: 'Carte "Identification professionnelle" absente' });
    }
    results.push({ scenario: 'B2 Profil AS', status: bugs.length ? 'FAIL' : 'PASS', bugs, screenshots });
  } catch (e) {
    results.push({ scenario: 'B2 Profil AS', status: 'FAIL', error: e.message, screenshots });
  }
  await page.close();
}

// Bonus 3 — Pharmacie filtre profession
{
  const page = await ctx.newPage();
  const screenshots = [];
  const bugs = [];
  try {
    await page.goto(`${URL}/connexion`, { waitUntil: 'networkidle' });
    await page.locator('input[type="email"]').fill('audit-pharmacie@jolene-test.dev');
    await page.locator('input[type="password"]').fill(PWD);
    await page.getByRole('button', { name: /se connecter|connexion/i }).first().click();
    await page.waitForTimeout(4000);
    if (!page.url().includes('/etablissement')) {
      bugs.push({ severity: 'P1', desc: `Login étab échoué. URL: ${page.url()}` });
    } else {
      await page.goto(`${URL}/etablissement/missions/creer`, { waitUntil: 'networkidle' });
      await page.waitForTimeout(2000);
      screenshots.push(await shot(page, 'b3-creer'));
      const combobox = page.getByRole('combobox').first();
      if (await combobox.isVisible().catch(() => false)) {
        await combobox.click();
        await page.waitForTimeout(500);
        const options = await page.getByRole('option').allInnerTexts();
        if (options.some(l => /infirmier|^IDE/i.test(l)))
          bugs.push({ severity: 'P1', desc: `IDE proposé pour pharmacie. Options: ${options.join(', ')}` });
        if (!options.some(l => /pharmacien|préparateur/i.test(l)))
          bugs.push({ severity: 'P1', desc: `Pharmacien/Préparateur absents. Options: ${options.join(', ')}` });
      } else {
        bugs.push({ severity: 'P1', desc: 'Combobox profession introuvable' });
      }
    }
    results.push({ scenario: 'B3 Pharmacie filtre', status: bugs.length ? 'FAIL' : 'PASS', bugs, screenshots });
  } catch (e) {
    results.push({ scenario: 'B3 Pharmacie', status: 'FAIL', error: e.message, screenshots });
  }
  await page.close();
}

await browser.close();
await fs.writeFile(path.join(SHOTS, 'results.json'), JSON.stringify(results, null, 2));
console.log(JSON.stringify(results.map(r => ({ scenario: r.scenario, status: r.status, bugs: r.bugs?.length || 0 })), null, 2));

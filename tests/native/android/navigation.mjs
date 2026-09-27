import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { _android as android, expect } from '@playwright/test';
import { currentImeShown } from './ime-state.mjs';
import { attachNativeWebView } from './webview-attachment.mjs';

const output = 'test-results/android-native';
const pkg = 'app.jolene.recette';
const api = 'http://127.0.0.1:8904';
const password = 'Recette-Native!2026';
await mkdir(output, { recursive: true });
const devices = await android.devices();
assert.equal(devices.length, 1, 'Exactly one isolated Android emulator is required');
const device = devices[0];
const validations = [];
const errors = [];
let page;
const nativeShell = async (command) => (await device.shell(command)).toString();
const save = (name, value) => writeFile(`${output}/${name}`, value);
const metric = (kind, data) => validations.push({ kind, ...data });
async function capture(name) {
  await device.screenshot({ path: `${output}/${name}.png` });
  if (page) {
    await save(`${name}.ime.txt`, await nativeShell('dumpsys input_method'));
    await save(`${name}.aria.txt`, await page.locator('body').ariaSnapshot());
    await save(`${name}.viewport.json`, JSON.stringify(await page.evaluate(() => ({
      width: innerWidth, height: innerHeight, dpr: devicePixelRatio,
      visual: { height: visualViewport.height, offsetTop: visualViewport.offsetTop },
      path: location.pathname,
    })), null, 2));
  }
}
async function invitation() {
  const later = page.getByRole('button', { name: 'Plus tard', exact: true });
  // Native permissions may resolve asynchronously after authentication.
  if (await later.isVisible()) await later.click();
}
async function nav(name) {
  await invitation();
  const navigation = page.getByRole('navigation', { name: 'Navigation mobile', exact: true });
  await expect(navigation).toBeVisible();
  await navigation.getByRole('button', { name, exact: true }).click();
  await invitation();
  await expect(page.getByText('Une erreur inattendue est survenue', { exact: true })).toHaveCount(0);
}
async function keyboardVisible() {
  // Check the Android IME itself, not merely focus or a screenshot.
  await expect.poll(async () => currentImeShown(await nativeShell('dumpsys input_method')), { timeout: 10000 }).toBe(true);
}
async function keyboardHidden() {
  await expect.poll(async () => currentImeShown(await nativeShell('dumpsys input_method')), { timeout: 10000 }).toBe(false);
}
async function closeKeyboard() {
  const path = new URL(page.url()).pathname;
  await nativeShell('input keyevent KEYCODE_BACK');
  await keyboardHidden();
  assert.equal(new URL(page.url()).pathname, path, 'First Android back must dismiss the keyboard without leaving the form');
}
async function credentials(role) {
  await page.getByLabel('Email', { exact: true }).fill(`native-android-${role}@example.invalid`);
  const secret = page.getByLabel('Mot de passe', { exact: true });
  await secret.click();
  await secret.fill(password);
  await keyboardVisible();
  await capture(`${role}-clavier-auth`);
  await closeKeyboard();
}
async function inscription(role) {
  const etab = role === 'etab';
  await page.getByRole('button', { name: etab ? 'Créer un compte établissement' : 'Créer un compte soignant', exact: true }).click();
  await credentials(role);
  if (etab) {
    const name = page.getByLabel('Nom de l’établissement', { exact: true });
    await name.click();
    await name.fill('Résidence Camille — simulation');
    await keyboardVisible();
    await closeKeyboard();
  } else await page.getByLabel('Profession', { exact: true }).selectOption('IDE');
  await page.getByRole('checkbox', { name: /CGU/ }).check();
  if (etab) await page.getByRole('checkbox', { name: /conditions générales de vente/ }).check();
  await page.getByRole('button', { name: 'Créer mon compte', exact: true }).click();
  await expect(page.getByRole('navigation', { name: 'Navigation mobile', exact: true })).toBeVisible({ timeout: 25000 });
  await invitation();
}
async function connexion(role) {
  await credentials(role);
  await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
  await expect(page.getByRole('navigation', { name: 'Navigation mobile', exact: true })).toBeVisible({ timeout: 25000 });
  await invitation();
}
async function logout(role) {
  await nav(role === 'etab' ? 'Menu' : 'Profil');
  await page.locator('main').getByRole('button', { name: 'Se déconnecter', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Créer un compte soignant', exact: true })).toBeVisible();
}
async function fiveTabs(role, phase) {
  const etab = role === 'etab';
  const names = etab ? ['Accueil', 'Missions', 'Publier', 'Messages', 'Menu'] : ['Accueil', 'Mes missions', 'Revenus', 'Profil', 'Explorer'];
  for (const name of names) {
    await nav(name);
    const main = page.locator('main');
    if (etab) {
      if (name === 'Accueil') {
        await expect(main.getByRole('heading', { name: 'Préparez votre première mission', exact: true })).toBeVisible();
        await expect(main.getByText('Paiements à jour', { exact: true })).toHaveCount(0);
        await expect(main.getByText('À compléter avant publication', { exact: true })).toBeVisible();
      } else if (name === 'Missions') await expect(main.getByText('Publiez votre première mission', { exact: true })).toBeVisible();
      else if (name === 'Publier') await expect(page.getByLabel(/Intitulé/)).toBeVisible();
      else if (name === 'Messages') await expect(main.getByText('Aucune conversation', { exact: true })).toBeVisible();
      else {
        await expect(main.getByRole('button', { name: 'Se déconnecter', exact: true })).toBeVisible();
        await expect(main.getByRole('button', { name: 'Supprimer mon compte', exact: true })).toBeVisible();
      }
    } else if (name === 'Explorer') {
      await expect(page.getByRole('button', { name: /^Mission IDE à Résidence Camille/ })).toBeVisible();
    } else if (name === 'Accueil') await expect(main.getByText('Explorez les missions librement. Votre profil sera demandé lorsque vous souhaiterez candidater.', { exact: true })).toBeVisible();
    else await expect(main.getByRole('heading', { name: name === 'Profil' ? 'Mon compte' : name === 'Revenus' ? '💰 Revenus' : name, exact: true }).first()).toBeVisible();
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1), `Overflow: ${role}/${phase}/${name}`);
    metric('tab', { role, phase, name, url: page.url() });
    await capture(`${role}-${phase}-${name.replaceAll(' ', '-').toLowerCase()}`);
  }
}

try {
  await nativeShell(`am force-stop ${pkg}`);
  await nativeShell(`am start -n ${pkg}/app.jolene.android.MainActivity`);
  const attachment = [];
  page = await attachNativeWebView({ device, shell: nativeShell, pkg, record: async (step) => {
    attachment.push(step);
    await save('webview-attachment.json', JSON.stringify(attachment, null, 2));
  } });
  page.setDefaultTimeout(15000);
  page.on('pageerror', (error) => errors.push(error.message));
  await expect(page.getByRole('button', { name: 'Créer un compte soignant', exact: true })).toBeVisible({ timeout: 25000 });
  assert.equal(await page.evaluate(() => window.Capacitor?.getPlatform()), 'android', 'Must exercise the native Capacitor bridge');
  await page.addLocatorHandler(page.getByRole('button', { name: 'Plus tard', exact: true }), async (button) => { await button.click(); });
  for (const role of ['soignant', 'etab']) {
    await inscription(role);
    await fiveTabs(role, 'inscription');
    if (role === 'soignant') {
      const card = page.getByRole('button', { name: /^Mission IDE à Résidence Camille/ });
      const explorerUrl = page.url();
      await card.click();
      await expect(page.getByRole('dialog')).toContainText('Remplacement infirmier de jour — simulation');
      await capture('soignant-detail');
      await nativeShell('input keyevent KEYCODE_BACK');
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(card).toBeVisible();
      assert.equal(page.url(), explorerUrl, 'Android Back closes the mission without leaving Explorer');
      await capture('soignant-detail-retour-explorer');
      metric('hardware-back-mission-detail', { role, url: page.url() });
    } else {
      await nav('Publier');
      const title = page.getByLabel(/Intitulé/);
      await title.click();
      await title.fill('Préparation native — simulation');
      await keyboardVisible();
      assert(await title.evaluate((el) => {
        const rect = el.getBoundingClientRect();
        return rect.top >= visualViewport.offsetTop && rect.bottom <= visualViewport.offsetTop + visualViewport.height;
      }), 'The focused mission field must remain above the native keyboard');
      await capture('etab-mission-clavier');
      await closeKeyboard();
      await expect(title).toHaveValue('Préparation native — simulation');
      metric('keyboard-back-preserves-draft', { role });
      await nav('Messages');
      await nav('Menu');
      await nativeShell('input keyevent KEYCODE_BACK');
      await expect(page.locator('main').getByText('Aucune conversation', { exact: true })).toBeVisible();
      metric('hardware-back-route', { role, url: page.url() });
    }
    await logout(role);
    await connexion(role);
    await fiveTabs(role, 'connexion');
    await logout(role);
  }
  assert.equal(validations.filter((item) => item.kind === 'tab').length, 20);
  const report = await (await fetch(`${api}/__recette/bilan`)).json();
  await save('api-report.json', JSON.stringify(report, null, 2));
  assert.deepEqual(report.unknown, [], 'No unimplemented API may pass silently');
  assert.deepEqual(report.errors, [], 'No uncaught runtime error or blocked WebView service request');
  assert.deepEqual(errors, []);
  assert.equal(report.users.length, 2);
  assert.equal(Object.keys(report.parcours).length, 2);
  assert.equal(report.calls.filter((call) => call.path === '/auth/v1/signup').length, 2);
  assert.equal(report.calls.filter((call) => call.path === '/auth/v1/token' && call.query === 'grant_type=password').length, 2);
  // Native plugins are blocked by the app UID firewall, separately from CSP.
  for (const binary of ['iptables', 'ip6tables']) {
    const table = await nativeShell(`${binary} -L JOLENE_RECETTE -v -n -x`);
    await save(`${binary}.txt`, table);
    const rejected = table.split('\n').filter((line) => /\bREJECT\b/.test(line));
    assert.equal(rejected.length, 1);
    assert.equal(Number(rejected[0].trim().split(/\s+/)[0]), 0, 'Unexpected native outbound traffic');
  }
  await save('summary.json', JSON.stringify({
    result: 'passed', device: device.model(), android: (await nativeShell('getprop ro.build.version.release')).trim(),
    evidence: 'Actual Capacitor debug APK in Android emulator; fictional local API',
    excludes: ['real backend behavior', 'push/SMS delivery', 'store signing', 'physical-device performance'],
    validations, apiCalls: report.calls.length, errors,
  }, null, 2));
} catch (error) {
  await capture('failure').catch(() => {});
  await save('failure.json', JSON.stringify({ message: error.message, stack: error.stack, validations, errors }, null, 2));
  throw error;
} finally {
  await device.close();
}

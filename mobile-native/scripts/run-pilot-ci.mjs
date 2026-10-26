import { spawn } from 'node:child_process';
import { copyFileSync, createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { readPngDimensions } from './png-dimensions.mjs';

// Expo CLI: https://docs.expo.dev/more/expo-cli/
// Maestro CLI: https://docs.maestro.dev/maestro-cli/maestro-cli-commands-and-options
// Local Expo Go on CI simulators only. No app build, OTA or store delivery.
if (process.env.GITHUB_ACTIONS !== 'true') throw new Error('Runner réservé aux simulateurs GitHub Actions.');
const platform = process.argv[2];
if (!['ios', 'android'].includes(platform)) throw new Error('Plateforme attendue : ios ou android.');
const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.env.PILOT_OUTPUT_DIR || resolve(project, 'test-results', `native-${platform}`));
mkdirSync(output, { recursive: true });
const flow = resolve(project, 'maestro', 'consultation.yaml');
const iosProject = resolve(project, 'ios-ui-tests', 'NativePilotUITests.xcodeproj');
const iosFamily = process.env.IOS_DEVICE_FAMILY || 'iphone';
const isIpad = platform === 'ios' && iosFamily === 'ipad';
const env = {
  ...process.env, CI: '1', EXPO_PUBLIC_JOLENE_MODE: 'demo',
  EXPO_PUBLIC_SUPABASE_URL: '', EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: '',
  EXPO_NO_DOTENV: '1', EXPO_NO_TELEMETRY: '1', MAESTRO_CLI_NO_ANALYTICS: '1',
  MAESTRO_DRIVER_STARTUP_TIMEOUT: '300000',
  NODE_OPTIONS: '--dns-result-order=ipv4first',
};
const appId = platform === 'ios' ? 'host.exp.Exponent' : 'host.exp.exponent';
const expoUrl = 'exp://127.0.0.1:8090';
let device;
let metro;
let metroError;
let stage = 'device-selection';
let success = false;
const started = new Date().toISOString();
const streams = [];
const scenarios = [];

function stopTree(child, signal = 'SIGTERM') {
  if (!child?.pid) return;
  try { process.kill(-child.pid, signal); } catch { /* Already stopped. */ }
}

async function run(command, args, { timeout = 60_000, logfile, allowFailure = false } = {}) {
  const stream = logfile ? createWriteStream(resolve(output, logfile), { flags: 'a' }) : null;
  if (stream) streams.push(stream);
  const child = spawn(command, args, { cwd: project, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let expired = false;
  child.stdout.on('data', chunk => { stdout += chunk.toString(); stream?.write(chunk); });
  child.stderr.on('data', chunk => { stderr += chunk.toString(); stream?.write(chunk); });
  const timer = setTimeout(() => { expired = true; stopTree(child, 'SIGKILL'); }, timeout);
  try {
    const code = await new Promise((res, rej) => {
      child.once('error', rej);
      child.once('close', res);
    });
    if ((expired || code !== 0) && !allowFailure) {
      throw new Error(`${command} ${args[0] ?? ''} ${expired ? 'délai dépassé' : `code ${code}`}: ${stderr.slice(-2000)}`);
    }
    return { code, stdout, stderr };
  } finally { clearTimeout(timer); }
}

async function waitUntil(label, check, timeout) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (metroError) throw metroError;
    if (metro && (metro.exitCode !== null || metro.signalCode !== null)) throw new Error(`Metro s’est arrêté (${metro.exitCode ?? metro.signalCode}) pendant ${label}. Voir metro.log.`);
    if (await check()) return;
    await delay(2000);
  }
  throw new Error(`Délai dépassé : ${label}. Voir les journaux conservés.`);
}

async function chooseIosDevice() {
  const runtimes = JSON.parse((await run('xcrun', ['simctl', 'list', 'runtimes', '--json'])).stdout).runtimes;
  const devices = JSON.parse((await run('xcrun', ['simctl', 'list', 'devices', 'available', '--json'])).stdout).devices;
  const family = process.env.IOS_DEVICE_FAMILY || 'iphone';
  if (!['iphone', 'ipad'].includes(family)) throw new Error('Famille de simulateur iOS invalide.');
  const ios = runtimes.filter(runtime => runtime.isAvailable && runtime.identifier.includes('.iOS-'))
    .sort((a, b) => b.version.localeCompare(a.version, undefined, { numeric: true }));
  for (const runtime of ios) {
    const candidates = (devices[runtime.identifier] || [])
      .filter(item => item.isAvailable && (item.deviceTypeIdentifier || item.name).toLowerCase().includes(family))
      .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
    if (candidates.length) {
      const selected = candidates[0];
      writeFileSync(resolve(output, 'device.json'), JSON.stringify({ platform, family, runtime: runtime.version, name: selected.name, udid: selected.udid }, null, 2));
      // These are disposable CI simulators; leave only the selected one booted so --ios is unambiguous.
      await run('xcrun', ['simctl', 'shutdown', 'all'], { logfile: 'simulator.log' });
      await run('xcrun', ['simctl', 'boot', selected.udid], { logfile: 'simulator.log' });
      await run('xcrun', ['simctl', 'bootstatus', selected.udid, '-b'], { timeout: 240_000, logfile: 'simulator.log' });
      await run('defaults', ['write', 'com.apple.iphonesimulator', 'ConnectHardwareKeyboard', '-bool', 'false']);
      return selected.udid;
    }
  }
  throw new Error(`Aucun simulateur ${family} disponible : aucun SDK supplémentaire ne sera installé.`);
}

async function chooseAndroidDevice() {
  const { stdout } = await run('adb', ['devices']);
  const attached = stdout.split('\n').slice(1).map(line => line.trim()).filter(Boolean)
    .map(line => line.split(/\s+/));
  // Expo enumerates attached devices itself. Refuse physical/offline/unauthorized
  // devices before --android can select one or attempt its global adb reverse.
  if (attached.length !== 1 || !/^emulator-\d+$/.test(attached[0][0]) || attached[0][1] !== 'device') {
    throw new Error('Un unique émulateur Android prêt est requis, sans appareil USB ni appareil non autorisé.');
  }
  const serial = attached[0][0];
  env.ANDROID_SERIAL = serial;
  const boot = await run('adb', ['-s', serial, 'shell', 'getprop', 'sys.boot_completed']);
  if (boot.stdout.trim() !== '1') throw new Error('Le démarrage de l’émulateur Android n’est pas terminé.');
  await run('adb', ['-s', serial, 'reverse', 'tcp:8090', 'tcp:8090']);
  writeFileSync(resolve(output, 'device.json'), JSON.stringify({ platform, serial, profile: 'pixel_7', api: 35 }, null, 2));
  return serial;
}

async function installExpoGo() {
  // Use the SDK-pinned Expo CLI downloader, without its automatic app launch.
  // Combining --ios with Metro lets a simctl openurl timeout kill the server.
  const binaryRecord = resolve(output, 'expo-go.json');
  const download = `
    const { createRequire } = require('node:module');
    const { dirname, resolve } = require('node:path');
    const { writeFileSync } = require('node:fs');
    const expoRequire = createRequire(require.resolve('expo/package.json'));
    const cliRoot = dirname(expoRequire.resolve('@expo/cli/package.json'));
    const { downloadExpoGoAsync } = require(resolve(cliRoot, 'build/src/utils/downloadExpoGoAsync.js'));
    downloadExpoGoAsync(process.argv[1], { sdkVersion: '57.0.0' })
      .then(binaryPath => writeFileSync(process.argv[2], JSON.stringify({ sdkVersion: '57.0.0', binaryPath })))
      .catch(error => { console.error(error); process.exitCode = 1; });
  `;
  await run(process.execPath, ['-e', download, platform, binaryRecord],
    { timeout: 360_000, logfile: 'expo-install.log' });
  const { binaryPath } = JSON.parse(readFileSync(binaryRecord, 'utf8'));
  if (typeof binaryPath !== 'string' || !existsSync(binaryPath)) throw new Error('Binaire Expo Go téléchargé introuvable.');
  if (platform === 'ios') {
    await run('xcrun', ['simctl', 'install', device, binaryPath], { timeout: 180_000, logfile: 'expo-install.log' });
  } else {
    await run('adb', ['-s', device, 'install', '-r', binaryPath], { timeout: 180_000, logfile: 'expo-install.log' });
  }
}

async function runScenario(name, scenarioFlow, directory) {
  stage = `maestro-${name}`;
  console.log(`Début du parcours natif ${name} (${platform}).`);
  mkdirSync(directory, { recursive: true });
  await run('maestro', ['--device', device, '--platform', platform, 'test',
    '--format', 'junit', '--output', resolve(directory, 'junit.xml'),
    '--debug-output', resolve(directory, 'maestro'), '--test-output-dir', resolve(directory, 'maestro'),
    '-e', `APP_ID=${appId}`, '-e', `EXPO_URL=${expoUrl}`,
    '-e', `OUTPUT_DIR=${directory}`, '-e', `PLATFORM=${platform}`,
    '-e', `FRESH_EXPO_GO=${name === 'portrait' ? '1' : '0'}`, scenarioFlow],
  { timeout: 720_000, logfile: `${name}-maestro.log` });
  const junit = readFileSync(resolve(directory, 'junit.xml'), 'utf8');
  if (!/<testsuite\b[^>]*\btests="[1-9]\d*"/.test(junit)
    || /\b(?:failures|errors|skipped)="[1-9]\d*"/.test(junit)) {
    throw new Error(`Le rapport JUnit ${name} ne confirme pas un parcours exécuté sans échec ni exclusion.`);
  }
  scenarios.push({ name, success: true });
  console.log(`Parcours natif ${name} terminé sans échec ni exclusion (${platform}).`);
}

async function runIosXCTest(name, directory) {
  const portrait = name === 'portrait';
  const testMethod = portrait
    ? (isIpad ? 'testPortraitConsultation' : 'testIphoneConsultation')
    : 'testLandscapeConsultation';
  stage = `xctest-${name}`;
  console.log(`Début du parcours ${iosFamily} ${name} avec XCTest (gestes Apple par élément).`);
  mkdirSync(directory, { recursive: true });
  const temporary = process.env.RUNNER_TEMP;
  if (!temporary) throw new Error('RUNNER_TEMP requis pour le runner XCTest CI.');
  const resultPath = resolve(temporary, `jolene-native-${iosFamily}-${name}.xcresult`);
  const result = await run('xcodebuild', ['test', '-project', iosProject,
    '-scheme', 'NativePilotUITests', `-only-testing:NativePilotUITests/NativePilotTests/${testMethod}`, '-configuration', 'Debug', '-sdk', 'iphonesimulator',
    '-destination', `platform=iOS Simulator,id=${device}`,
    '-derivedDataPath', resolve(temporary, 'jolene-native-ui-derived'),
    '-resultBundlePath', resultPath, '-parallel-testing-enabled', 'NO',
    '-maximum-concurrent-test-simulator-destinations', '1',
    '-test-timeouts-enabled', 'YES', '-maximum-test-execution-time-allowance', '300',
    'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO'],
  { timeout: 600_000, logfile: `${name}-xctest.log`, allowFailure: true });
  if (!existsSync(resultPath)) throw new Error(`Rapport XCTest ${name} absent. Voir ${name}-xctest.log.`);
  const report = await run('xcrun', ['xcresulttool', 'get', 'test-results', 'summary', '--path', resultPath]);
  writeFileSync(resolve(directory, 'xctest-summary.json'), report.stdout);
  const attachments = resolve(directory, 'attachments');
  await run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', resultPath, '--output-path', attachments]);
  const summary = JSON.parse(report.stdout);
  if (result.code !== 0 || summary.result !== 'Passed' || summary.totalTestCount !== 1
    || summary.passedTests !== 1 || summary.failedTests !== 0 || summary.skippedTests !== 0
    || summary.expectedFailures !== 0) {
    throw new Error(`Le rapport XCTest ${name} ne confirme pas un test réussi sans exclusion.`);
  }
  const manifest = JSON.parse(readFileSync(resolve(attachments, 'manifest.json'), 'utf8'));
  if (!Array.isArray(manifest)) throw new Error('Manifest des captures XCTest invalide.');
  const captures = resolve(directory, 'captures');
  mkdirSync(captures, { recursive: true });
  const names = portrait
    ? ['connexion', 'missions', 'detail', 'retour'].map(screen => `${iosFamily}-portrait-${screen}`)
    : ['connexion', 'liste', 'detail', 'retour'].map(screen => `ipad-paysage-${screen}`);
  for (const name of names) {
    const matching = manifest.flatMap(test => test.attachments ?? []).filter(item =>
      item.suggestedHumanReadableName?.includes(name) && item.exportedFileName?.endsWith('.png'));
    if (matching.length !== 1 || basename(matching[0].exportedFileName) !== matching[0].exportedFileName) {
      throw new Error(`Capture XCTest absente ou ambiguë : ${name}.`);
    }
    copyFileSync(resolve(attachments, matching[0].exportedFileName), resolve(captures, `${name}.png`));
  }
  verifyCaptureOrientation(captures, portrait ? 'PORTRAIT' : 'LANDSCAPE_LEFT', names);
  scenarios.push({ name, success: true, driver: 'XCTest' });
  console.log(`Parcours ${iosFamily} ${name} terminé : un test XCTest réussi et quatre captures dans l’orientation attendue.`);
}

function verifyCaptureOrientation(directory, orientation, names) {
  function files(folder) {
    return readdirSync(folder, { withFileTypes: true }).flatMap(entry =>
      entry.isDirectory() ? files(resolve(folder, entry.name)) : [resolve(folder, entry.name)]);
  }
  const candidates = files(directory);
  const captures = names.map(screen => {
    const filename = `${screen}.png`;
    const matching = candidates.filter(file => basename(file) === filename);
    if (matching.length !== 1) throw new Error(`Capture ${orientation} absente ou ambiguë : ${filename}.`);
    let dimensions;
    try {
      dimensions = readPngDimensions(readFileSync(matching[0]));
    } catch (error) {
      throw new Error(`Capture PNG invalide : ${filename}. ${error.message}`, { cause: error });
    }
    const { width, height } = dimensions;
    const expected = orientation === 'PORTRAIT' ? width < height : width > height;
    if (!expected) throw new Error(`Orientation ${orientation} non confirmée : ${filename}, ${width}×${height}.`);
    return { screen, filename, ...dimensions };
  });
  writeFileSync(resolve(directory, 'orientation.json'), JSON.stringify({ requested: orientation, captures }, null, 2));
}

try {
  if (!existsSync(flow)) throw new Error('Le scénario maestro/consultation.yaml est requis.');
  if (platform === 'ios' && !existsSync(iosProject)) throw new Error('Le projet XCTest iPhone et iPad est requis.');
  device = platform === 'ios' ? await chooseIosDevice() : await chooseAndroidDevice();
  stage = 'expo-go-install';
  await installExpoGo();
  stage = 'metro-start';
  console.log(`Démarrage Expo SDK 57 sur ${platform} (${device}).`);
  const metroLog = createWriteStream(resolve(output, 'metro.log'));
  streams.push(metroLog);
  metro = spawn('npx', ['--no-install', 'expo', 'start', '--go', '--localhost', '--port', '8090'],
    { cwd: project, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  metro.stdout.pipe(metroLog, { end: false });
  metro.stderr.pipe(metroLog, { end: false });
  metro.once('error', error => { metroError = error; metroLog.write(`${error.message}\n`); });
  await waitUntil('réponse Metro sur IPv4 localhost', async () => {
    try {
      const response = await fetch('http://127.0.0.1:8090/status', { signal: AbortSignal.timeout(5000) });
      return response.ok && (await response.text()).includes('packager-status:running');
    } catch { return false; }
  }, 180_000);

  stage = 'expo-go-installed';
  await waitUntil('installation Expo Go pour SDK 57', async () => {
    const result = platform === 'ios'
      ? await run('xcrun', ['simctl', 'get_app_container', device, appId, 'app'], { allowFailure: true, timeout: 10_000 })
      : await run('adb', ['-s', device, 'shell', 'pm', 'path', appId], { allowFailure: true, timeout: 10_000 });
    return result.code === 0 && result.stdout.trim().length > 0;
  }, 360_000);

  stage = 'metro-manifest';
  const response = await fetch('http://127.0.0.1:8090/', {
    headers: { 'expo-platform': platform, accept: 'application/expo+json' },
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) throw new Error(`Le manifeste Metro retourne ${response.status}.`);
  const manifest = await response.json();
  const sdk = manifest.extra?.expoClient?.sdkVersion ?? manifest.sdkVersion;
  if (!String(sdk).startsWith('57.')) throw new Error(`Version Expo du manifeste inattendue : ${sdk}.`);
  writeFileSync(resolve(output, 'manifest-summary.json'), JSON.stringify({ sdkVersion: sdk, platform, mode: 'demo', expoUrl }, null, 2));

  stage = 'metro-bundle-ready';
  const bundleUrl = new URL(manifest.launchAsset?.url);
  if (bundleUrl.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(bundleUrl.hostname) || bundleUrl.port !== '8090') {
    throw new Error('Le bundle de démonstration doit provenir du serveur Metro local.');
  }
  const bundle = await fetch(bundleUrl, { signal: AbortSignal.timeout(180_000) });
  if (!bundle.ok) throw new Error(`Le bundle Metro retourne ${bundle.status}.`);
  const bundleBytes = (await bundle.arrayBuffer()).byteLength;
  if (!bundleBytes) throw new Error('Le bundle Metro est vide.');
  writeFileSync(resolve(output, 'bundle-summary.json'), JSON.stringify({ platform, bytes: bundleBytes, source: 'localhost' }, null, 2));

  console.log('Installation, manifeste et bundle prêts ; lancement du parcours natif.');
  if (platform === 'ios') {
    stage = 'open-ios-experience';
    await run('xcrun', ['simctl', 'launch', device, appId], { timeout: 120_000, logfile: 'expo-launch.log' });
    await run('xcrun', ['simctl', 'openurl', device, expoUrl], { timeout: 120_000, logfile: 'expo-launch.log' });
    await runIosXCTest('portrait', resolve(output, 'portrait'));
    if (isIpad) await runIosXCTest('landscape', resolve(output, 'landscape'));
  } else {
    await runScenario('portrait', flow, output);
    stage = 'portrait-captures';
    verifyCaptureOrientation(output, 'PORTRAIT', ['connexion', 'missions', 'detail', 'retour']);
  }
  success = true;
  stage = 'complete';
} catch (error) {
  console.error(error);
  writeFileSync(resolve(output, 'failure.txt'), `${stage}: ${error.stack || error}\n`);
  process.exitCode = 1;
} finally {
  if (device) {
    if (platform === 'ios') {
      await run('xcrun', ['simctl', 'io', device, 'screenshot', resolve(output, 'final.png')], { allowFailure: true, timeout: 15_000, logfile: 'simulator.log' });
    } else {
      await run('adb', ['-s', device, 'shell', 'screencap', '-p', '/sdcard/jolene-pilot-final.png'], { allowFailure: true, timeout: 15_000 });
      await run('adb', ['-s', device, 'pull', '/sdcard/jolene-pilot-final.png', resolve(output, 'final.png')], { allowFailure: true, timeout: 15_000 });
      await run('adb', ['-s', device, 'logcat', '-d', '-t', '1500'], { allowFailure: true, timeout: 15_000, logfile: 'android-logcat.log' });
    }
  }
  stopTree(metro);
  if (metro?.pid) {
    await delay(1000);
    stopTree(metro, 'SIGKILL');
  }
  writeFileSync(resolve(output, 'result.json'), JSON.stringify({ started, ended: new Date().toISOString(), platform,
    device, stage, success, scenarios, evidence: 'native-simulator-synthetic-demo', production: false, physicalDevice: false }, null, 2));
  await Promise.all(streams.map(stream => new Promise(resolveClose => stream.end(resolveClose))));
}

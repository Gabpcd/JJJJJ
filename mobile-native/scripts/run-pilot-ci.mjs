import { spawn } from 'node:child_process';
import { createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

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
const landscapeFlow = resolve(project, 'maestro', 'consultation-ipad-paysage.yaml');
const isIpad = platform === 'ios' && process.env.IOS_DEVICE_FAMILY === 'ipad';
const env = {
  ...process.env, CI: '1', EXPO_PUBLIC_JOLENE_MODE: 'demo',
  EXPO_PUBLIC_SUPABASE_URL: '', EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: '',
  EXPO_NO_DOTENV: '1', EXPO_NO_TELEMETRY: '1', MAESTRO_CLI_NO_ANALYTICS: '1',
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

async function runScenario(name, scenarioFlow, directory) {
  stage = `maestro-${name}`;
  mkdirSync(directory, { recursive: true });
  await run('maestro', ['--device', device, '--platform', platform, 'test',
    '--format', 'junit', '--output', resolve(directory, 'junit.xml'),
    '--debug-output', resolve(directory, 'maestro'), '--test-output-dir', resolve(directory, 'maestro'),
    '-e', `APP_ID=${appId}`, '-e', `EXPO_URL=${expoUrl}`,
    '-e', `OUTPUT_DIR=${directory}`, '-e', `PLATFORM=${platform}`, scenarioFlow],
  { timeout: 720_000, logfile: `${name}-maestro.log` });
  const junit = readFileSync(resolve(directory, 'junit.xml'), 'utf8');
  if (!/<testsuite\b[^>]*\btests="[1-9]\d*"/.test(junit)
    || /\b(?:failures|errors|skipped)="[1-9]\d*"/.test(junit)) {
    throw new Error(`Le rapport JUnit ${name} ne confirme pas un parcours exécuté sans échec ni exclusion.`);
  }
  scenarios.push({ name, success: true });
}

function verifyLandscapeCaptures(directory) {
  function files(folder) {
    return readdirSync(folder, { withFileTypes: true }).flatMap(entry =>
      entry.isDirectory() ? files(resolve(folder, entry.name)) : [resolve(folder, entry.name)]);
  }
  const candidates = files(directory);
  const captures = ['connexion', 'liste', 'detail', 'retour'].map(screen => {
    const filename = `ipad-paysage-${screen}.png`;
    const matching = candidates.filter(file => basename(file) === filename);
    if (matching.length !== 1) throw new Error(`Capture paysage absente ou ambiguë : ${filename}.`);
    const image = readFileSync(matching[0]);
    if (!image.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
      || image.subarray(12, 16).toString() !== 'IHDR') throw new Error(`Capture PNG invalide : ${filename}.`);
    const width = image.readUInt32BE(16);
    const height = image.readUInt32BE(20);
    if (width <= height) throw new Error(`Le scénario paysage a produit une capture portrait : ${filename}, ${width}×${height}.`);
    return { screen, filename, width, height };
  });
  writeFileSync(resolve(directory, 'orientation.json'), JSON.stringify({ requested: 'LANDSCAPE_LEFT', captures }, null, 2));
}

try {
  if (!existsSync(flow)) throw new Error('Le scénario maestro/consultation.yaml est requis.');
  if (isIpad && !existsSync(landscapeFlow)) throw new Error('Le scénario iPad paysage est requis en complément du portrait.');
  device = platform === 'ios' ? await chooseIosDevice() : await chooseAndroidDevice();
  stage = 'metro-start';
  console.log(`Démarrage Expo SDK 57 sur ${platform} (${device}).`);
  const metroLog = createWriteStream(resolve(output, 'metro.log'));
  streams.push(metroLog);
  metro = spawn('npx', ['--no-install', 'expo', 'start', '--go', `--${platform}`, '--localhost', '--port', '8090'],
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

  stage = 'expo-go-install';
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

  console.log('Installation et manifeste confirmés ; lancement du parcours natif.');
  await runScenario('portrait', flow, output);
  if (isIpad) {
    const landscapeOutput = resolve(output, 'landscape');
    await runScenario('landscape', landscapeFlow, landscapeOutput);
    stage = 'landscape-captures';
    verifyLandscapeCaptures(landscapeOutput);
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

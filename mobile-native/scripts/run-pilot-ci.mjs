import { spawn } from 'node:child_process';
import { copyFileSync, createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { verifyContractsHomeEvidence } from './contracts-home-oracle.mjs';
import { readPngDimensions } from './png-dimensions.mjs';
import { collectIosFailureDiagnostics } from './ios-failure-diagnostics.mjs';
import { createIosNavigationStallMonitor } from './ios-navigation-stall.mjs';
import { selectNativeScenario, iosTestMethod, scenarioCaptureNames } from './native-scenarios.mjs';
import { buildCompiledIosClient, COMPILED_APP_ID, requireSimulatorBuildSpace } from './ios-compiled-client.mjs';
import { startNativeEventStream } from './ios-native-event-stream.mjs';

// Expo CLI: https://docs.expo.dev/more/expo-cli/
// Maestro CLI: https://docs.maestro.dev/maestro-cli/maestro-cli-commands-and-options
// CI simulators only: Expo Go, or an additional unsigned Debug comparison.
// No archive, OTA, EAS or store delivery.
if (process.env.GITHUB_ACTIONS !== 'true') throw new Error('Runner réservé aux simulateurs GitHub Actions.');
const platform = process.argv[2];
if (!['ios', 'android'].includes(platform)) throw new Error('Plateforme attendue : ios ou android.');
const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.env.PILOT_OUTPUT_DIR || resolve(project, 'test-results', `native-${platform}`));
mkdirSync(output, { recursive: true });
const iosFamily = process.env.IOS_DEVICE_FAMILY || 'iphone';
const selectedScenario = selectNativeScenario(process.env, platform, iosFamily);
const iosHost = process.env.NATIVE_IOS_HOST || 'expo-go';
if (!['expo-go', 'compiled-debug'].includes(iosHost)) throw new Error('Hôte iOS inconnu.');
const compiled = iosHost === 'compiled-debug';
if (compiled && (platform !== 'ios' || iosFamily !== 'iphone' || !['contracts', 'input-reference'].includes(selectedScenario.name)
  || selectedScenario.orientations.join() !== 'portrait')) throw new Error('Comparaison compilée limitée à Contrats ou au témoin RN iPhone portrait.');
const flow = selectedScenario.flowFile ? resolve(project, 'maestro', selectedScenario.flowFile) : null;
if (selectedScenario.name === 'input-reference'
  && JSON.parse(readFileSync(resolve(project, 'package.json'), 'utf8')).name !== 'jolene-input-reference-ci') {
  throw new Error('Le témoin RN ne peut pas utiliser le projet applicatif Jolene.');
}
const iosProject = resolve(project, 'ios-ui-tests', 'NativePilotUITests.xcodeproj');
writeFileSync(resolve(output, 'scenario.json'), JSON.stringify(selectedScenario, null, 2));
const env = {
  ...process.env, CI: '1', EXPO_PUBLIC_JOLENE_MODE: 'demo',
  EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: selectedScenario.documentScenarioFlag,
  EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: selectedScenario.contractScenarioFlag ?? '0',
  EXPO_PUBLIC_SUPABASE_URL: '', EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: '',
  EXPO_NO_DOTENV: '1', EXPO_NO_TELEMETRY: '1', MAESTRO_CLI_NO_ANALYTICS: '1',
  MAESTRO_DRIVER_STARTUP_TIMEOUT: '300000',
  NODE_OPTIONS: '--dns-result-order=ipv4first',
};
const appId = compiled ? COMPILED_APP_ID : platform === 'ios' ? 'host.exp.Exponent' : 'host.exp.exponent';
const expoUrl = 'exp://127.0.0.1:8090';
let device;
let metro;
let metroError;
let navigationStallMonitor;
let compiledClient;
let nativeEventStream;
let iosTestsBuilt = false;
let stage = 'device-selection';
let success = false;
const started = new Date().toISOString();
const streams = [];
const scenarios = [];

function stopTree(child, signal = 'SIGTERM') {
  if (!child?.pid) return;
  try { process.kill(-child.pid, signal); } catch { /* Already stopped. */ }
}

async function run(command, args, { timeout = 60_000, logfile, allowFailure = false, captureLimit, extraEnv } = {}) {
  const stream = logfile ? createWriteStream(resolve(output, logfile), { flags: 'a' }) : null;
  if (stream) streams.push(stream);
  const commandStarted = performance.now();
  const child = spawn(command, args, { cwd: project, env: { ...env, ...extraEnv }, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let expired = false;
  let diskError;
  let logBytes = 0;
  const logLimit = compiled ? 16_000_000 : Infinity;
  const log = chunk => {
    if (!stream || logBytes >= logLimit) return;
    const remaining = logLimit - logBytes;
    stream.write(chunk.subarray(0, Math.min(chunk.length, remaining)));
    logBytes += chunk.length;
    if (logBytes >= logLimit) stream.write('\n[runner: diagnostic log capped at 16000000 bytes]\n');
  };
  child.stdout.on('data', chunk => { stdout += chunk.toString(); if (captureLimit) stdout = stdout.slice(-captureLimit); log(chunk); });
  child.stderr.on('data', chunk => { stderr += chunk.toString(); if (captureLimit) stderr = stderr.slice(-captureLimit); log(chunk); });
  const timer = setTimeout(() => { expired = true; stopTree(child, 'SIGKILL'); }, timeout);
  const diskTimer = compiled ? setInterval(() => {
    try { requireSimulatorBuildSpace(project); }
    catch (error) { diskError = error; stopTree(child, 'SIGKILL'); }
  }, 10_000) : undefined;
  try {
    const { code, signal } = await new Promise((res, rej) => {
      child.once('error', rej);
      child.once('close', (code, signal) => res({ code, signal }));
    });
    if (diskError) throw diskError;
    if ((expired || code !== 0) && !allowFailure) {
      throw new Error(`${command} ${args[0] ?? ''} ${expired ? 'délai dépassé' : `code ${code}`}: ${stderr.slice(-2000)}`);
    }
    return { code, signal, expired, durationMs: Math.round(performance.now() - commandStarted), stdout, stderr };
  } finally { clearTimeout(timer); clearInterval(diskTimer); }
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
  // A fresh macOS runner may still be initializing CoreSimulator before listing
  // runtimes. Bound that startup separately; do not relax any application assertion.
  const inventory = { timeout: 180_000, logfile: 'simulator-inventory.log' };
  const runtimes = JSON.parse((await run('xcrun', ['simctl', 'list', 'runtimes', '--json'], inventory)).stdout).runtimes;
  const devices = JSON.parse((await run('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], inventory)).stdout).devices;
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
      // Cold iOS 26.5 data migrations exceeded four minutes on both source
      // reference runners, before any app build. Bound simulator preparation
      // separately; application waits and XCTest allowances remain unchanged.
      stage = 'ios-boot-readiness';
      const bootTimeout = 600_000;
      const bootStarted = new Date().toISOString();
      const boot = await run('xcrun', ['simctl', 'bootstatus', selected.udid, '-b'],
        { timeout: bootTimeout, logfile: 'simulator.log', allowFailure: true, captureLimit: 64_000 });
      writeFileSync(resolve(output, 'simulator-boot-command.json'), JSON.stringify({
        phase: stage, command: ['xcrun', 'simctl', 'bootstatus', selected.udid, '-b'],
        started: bootStarted, ended: new Date().toISOString(), timeoutMs: bootTimeout,
        code: boot.code, signal: boot.signal, expired: boot.expired, durationMs: boot.durationMs,
      }, null, 2));
      if (boot.expired || boot.code !== 0 || boot.signal) throw new Error('Le démarrage du simulateur a échoué ; voir simulator-boot-command.json.');
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
  { timeout: selectedScenario.name === 'consultation' ? 720_000 : 600_000, logfile: `${name}-maestro.log` });
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
  const testMethod = iosTestMethod(selectedScenario, iosFamily, name);
  mkdirSync(directory, { recursive: true });
  const temporary = process.env.RUNNER_TEMP;
  if (!temporary) throw new Error('RUNNER_TEMP requis pour le runner XCTest CI.');
  const common = ['-project', iosProject, '-scheme', 'NativePilotUITests',
    '-configuration', 'Debug', '-sdk', 'iphonesimulator',
    '-destination', `platform=iOS Simulator,id=${device}`,
    '-derivedDataPath', resolve(temporary, 'jolene-native-ui-derived'),
    'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
    `JOLENE_TEST_APP_ID=${appId}`, `JOLENE_TEST_HOME_ICON=${compiledClient?.iconName ?? 'Expo Go'}`];
  const saveCommand = (path, result, timeoutMs) => {
    const { code, signal, expired, durationMs } = result;
    writeFileSync(path, JSON.stringify({ code, signal, expired, durationMs, timeoutMs }, null, 2));
  };
  // Compilation must not consume the bounded execution/finalization budget.
  // Reuse the same built test bundle for the next orientation in this CI job.
  if (!iosTestsBuilt) {
    stage = 'xctest-build';
    const build = await run('xcodebuild', ['build-for-testing', ...common],
      { timeout: 300_000, logfile: 'xctest-build.log', allowFailure: true });
    saveCommand(resolve(output, 'xctest-build-command.json'), build, 300_000);
    if (build.expired || build.code !== 0) {
      throw new Error(`Compilation du harnais XCTest ${build.expired ? 'délai externe de 300 s dépassé' : `code ${build.code}, signal ${build.signal ?? 'aucun'}`}. Voir xctest-build.log.`);
    }
    iosTestsBuilt = true;
  }
  stage = `xctest-${name}`;
  console.log(`Début du parcours ${iosFamily} ${name} avec XCTest (gestes Apple par élément).`);
  const resultPath = resolve(temporary, `jolene-native-${iosFamily}-${name}.xcresult`);
  const result = await run('xcodebuild', ['test-without-building', ...common,
    `-only-testing:NativePilotUITests/${selectedScenario.iosTestClass ?? 'NativePilotTests'}/${testMethod}`,
    '-resultBundlePath', resultPath, '-parallel-testing-enabled', 'NO',
    '-maximum-concurrent-test-simulator-destinations', '1',
    '-test-timeouts-enabled', 'YES', '-maximum-test-execution-time-allowance', '600'],
  { timeout: 900_000, logfile: `${name}-xctest.log`, allowFailure: true });
  saveCommand(resolve(directory, 'xctest-command.json'), result, 900_000);
  // Preserve an external timeout even if xcresulttool encounters a partial bundle.
  // A readable report is collected once for diagnosis; it cannot rescue a timeout.
  const commandFailure = result.expired ? 'Délai externe XCTest de 900 s dépassé. '
    : result.code !== 0 ? `xcodebuild code ${result.code}, signal ${result.signal ?? 'aucun'}. ` : '';
  const attachments = resolve(directory, 'attachments');
  let summary;
  try {
    if (!existsSync(resultPath)) throw new Error('Le bundle .xcresult est absent.');
    const report = await run('xcrun', ['xcresulttool', 'get', 'test-results', 'summary', '--path', resultPath]);
    writeFileSync(resolve(directory, 'xctest-summary.json'), report.stdout);
    summary = JSON.parse(report.stdout);
    await run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', resultPath, '--output-path', attachments]);
  } catch (error) {
    throw new Error(`${commandFailure}Rapport ou pièces jointes XCTest ${name} incomplets ou inexploitables : ${error.message}`, { cause: error });
  }
  if (result.expired || result.code !== 0 || summary.result !== 'Passed' || summary.totalTestCount !== 1
    || summary.passedTests !== 1 || summary.failedTests !== 0 || summary.skippedTests !== 0
    || summary.expectedFailures !== 0) {
    throw new Error(`${commandFailure}Le rapport XCTest ${name} ne confirme pas un test réussi sans exclusion.`);
  }
  const manifest = JSON.parse(readFileSync(resolve(attachments, 'manifest.json'), 'utf8'));
  if (!Array.isArray(manifest)) throw new Error('Manifest des captures XCTest invalide.');
  if (selectedScenario.name === 'contracts') {
    const prefix = name === 'landscape' ? 'ipad-paysage' : `${iosFamily}-portrait`;
    const proofs = manifest.flatMap(test => test.attachments ?? []).filter(item =>
      item.suggestedHumanReadableName?.startsWith(`${prefix}-contrats-home-oracle`)
      && ['.json', '.txt'].some(extension => item.exportedFileName?.endsWith(extension)));
    if (proofs.length !== 1 || basename(proofs[0].exportedFileName) !== proofs[0].exportedFileName) {
      throw new Error('Preuve Home XCTest absente ou ambiguë.');
    }
    const proof = JSON.parse(readFileSync(resolve(attachments, proofs[0].exportedFileName), 'utf8'));
    if (proof.prefix !== prefix) throw new Error('Preuve Home provenant d’un autre format.');
    nativeEventStream?.assertHealthy();
    const evidenceLog = nativeEventStream?.eventPath ?? resolve(output, 'metro.log');
    const evidence = verifyContractsHomeEvidence({ proof, metro: readFileSync(evidenceLog, 'utf8') });
    writeFileSync(resolve(directory, 'contracts-home-evidence.json'), JSON.stringify(evidence, null, 2));
  }
  const captures = resolve(directory, 'captures');
  mkdirSync(captures, { recursive: true });
  const names = scenarioCaptureNames(selectedScenario, platform, iosFamily, name);
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
  console.log(`Parcours ${iosFamily} ${name} terminé : un test XCTest réussi et ${names.length} captures dans l’orientation attendue.`);
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
  if (flow && !existsSync(flow)) throw new Error(`Le scénario Maestro sélectionné est absent : ${selectedScenario.flowFile}.`);
  if (platform === 'ios' && !existsSync(iosProject)) throw new Error('Le projet XCTest iPhone et iPad est requis.');
  device = platform === 'ios' ? await chooseIosDevice() : await chooseAndroidDevice();
  stage = compiled ? 'compiled-debug-build' : 'expo-go-install';
  if (compiled) compiledClient = await buildCompiledIosClient({ project, output, device, env, run,
    referenceSourceSha: selectedScenario.name === 'input-reference' ? env.NATIVE_INPUT_REFERENCE_SOURCE_SHA : undefined });
  else await installExpoGo();
  stage = 'metro-start';
  console.log(`Démarrage Expo SDK 57 sur ${platform} (${device}).`);
  const metroLog = createWriteStream(resolve(output, 'metro.log'));
  streams.push(metroLog);
  metro = spawn('npx', ['--no-install', 'expo', 'start', compiled ? '--dev-client' : '--go', '--localhost', '--port', '8090'],
    { cwd: project, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  metro.stdout.pipe(metroLog, { end: false });
  metro.stderr.pipe(metroLog, { end: false });
  metro.stdout.on('data', chunk => { if (!compiled) navigationStallMonitor?.consume('stdout', chunk); });
  metro.stderr.on('data', chunk => { if (!compiled) navigationStallMonitor?.consume('stderr', chunk); });
  metro.once('error', error => { metroError = error; metroLog.write(`${error.message}\n`); });
  await waitUntil('réponse Metro sur IPv4 localhost', async () => {
    try {
      const response = await fetch('http://127.0.0.1:8090/status', { signal: AbortSignal.timeout(5000) });
      return response.ok && (await response.text()).includes('packager-status:running');
    } catch { return false; }
  }, 180_000);

  stage = 'app-installed';
  await waitUntil(`installation de ${appId}`, async () => {
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
  writeFileSync(resolve(output, 'manifest-summary.json'), JSON.stringify({ sdkVersion: sdk, platform, mode: 'demo', host: iosHost, appId, expoUrl: compiled ? null : expoUrl }, null, 2));

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

  console.log(`Installation, manifeste et bundle prêts ; parcours natif ${selectedScenario.name}.`);
  if (platform === 'ios') {
    stage = 'open-ios-experience';
    if (compiled) {
      nativeEventStream = await startNativeEventStream({ device, executable: compiledClient.executable, output, env,
        onLine: line => navigationStallMonitor?.consume('stdout', line) });
    }
    // RCTBundleURLProvider in the locked RN version reads this NSArgumentDomain
    // setting. It also works when the precompiled RN core has port 8081 baked in.
    const launchArguments = compiled ? ['-RCT_jsLocation', '127.0.0.1:8090'] : [
      '--initialUrl', expoUrl, '-EXDevMenuIsOnboardingFinished', 'YES',
      '-EXDevMenuShowsAtLaunch', 'NO', '-EXDevMenuShowFloatingActionButton', 'NO',
    ];
    const launch = await run('xcrun', [
      'simctl', 'launch', device, appId, ...launchArguments,
    ], { timeout: 120_000, logfile: compiled ? 'compiled-launch.log' : 'expo-launch.log' });
    nativeEventStream?.bindLaunch(launch.stdout, appId);
    navigationStallMonitor = await createIosNavigationStallMonitor({ env, platform, device, output, run, launchOutput: launch.stdout, bundleId: appId });
    // Expo Go SDK 57 opens --initialUrl after its home controller appears.
    // Temporary NSArgumentDomain defaults prepare the Expo Go host only.
    // XCTest activates the existing process and requires its overlays absent;
    // every Jolene interaction and assertion remains in the scenario.
    for (const orientation of selectedScenario.orientations) {
      await runIosXCTest(orientation, resolve(output, orientation));
    }
  } else {
    await runScenario('portrait', flow, output);
    stage = 'portrait-captures';
    verifyCaptureOrientation(output, 'PORTRAIT', scenarioCaptureNames(selectedScenario, platform, iosFamily, 'portrait'));
  }
  success = true;
  stage = 'complete';
} catch (error) {
  console.error(error);
  writeFileSync(resolve(output, 'failure.txt'), `${stage}: ${error.stack || error}\n`);
  process.exitCode = 1;
} finally {
  await navigationStallMonitor?.dispose();
  await nativeEventStream?.dispose();
  if (device) {
    if (platform === 'ios') {
      if (!success) {
        try { await collectIosFailureDiagnostics({ device, output, started, run, env, failed: true, compiledClient }); }
        catch (error) { writeFileSync(resolve(output, 'ios-diagnostics-error.txt'), String(error)); }
      }
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
  writeFileSync(resolve(output, 'result.json'), JSON.stringify({ started, ended: new Date().toISOString(), platform, scenario: selectedScenario.name, orientations: selectedScenario.orientations,
    device, host: iosHost, appId, stage, success, scenarios,
    evidence: selectedScenario.name === 'input-reference' ? 'synthetic-rn-input-reference' : 'native-simulator-synthetic-demo',
    ...(selectedScenario.name === 'input-reference' ? { productScenario: false, contractsVerdictChanged: false } : {}),
    production: false, physicalDevice: false }, null, 2));
  await Promise.all(streams.map(stream => new Promise(resolveClose => stream.end(resolveClose))));
}

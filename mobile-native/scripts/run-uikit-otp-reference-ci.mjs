import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, statfsSync, writeFileSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { IOS_CI_DEVELOPER_DIR, selectIosCiSimulator, verifyIosCiXcode } from './ios-ci-toolchain.mjs';

// Standalone UIKit control: no npm install, Pods, Metro, RN or product mutation.
if (process.env.GITHUB_ACTIONS !== 'true' || process.platform !== 'darwin' || !process.env.RUNNER_TEMP) {
  throw new Error('Le témoin UIKit est réservé au simulateur GitHub Actions.');
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.env.UIKIT_REFERENCE_OUTPUT_DIR || resolve(root, 'test-results/uikit-otp-reference'));
const project = resolve(root, 'ios-ui-tests/NativePilotUITests.xcodeproj');
const derived = resolve(process.env.RUNNER_TEMP, 'jolene-uikit-reference-derived');
const resultPath = resolve(process.env.RUNNER_TEMP, 'jolene-uikit-reference.xcresult');
const bundleId = 'app.jolene.otp-uikit-reference';
const scheme = 'UIKitOtpReference';
const kind = process.env.UIKIT_REFERENCE_KIND || 'otp';
const family = process.env.IOS_DEVICE_FAMILY || 'iphone';
if (!['otp', 'touch'].includes(kind) || !['iphone', 'ipad'].includes(family)) {
  throw new Error('Témoin UIKit ou famille non reconnue.');
}
const test = `NativePilotUITests/UIKitOtpReferenceTests/${kind === 'touch' ? 'testButtonReleases' : 'testSixZeros'}`;
const source = kind === 'touch' ? 'synthetic-uikit-touch-reference' : 'synthetic-uikit-reference';
const prefix = kind === 'touch' ? 'uikit-touch' : 'uikit-reference';
const started = new Date().toISOString();
const environment = { ...process.env, CI: '1', DEVELOPER_DIR: IOS_CI_DEVELOPER_DIR };
let device;
let stage = 'inventory';
let success = false;
mkdirSync(output, { recursive: true });

function space() {
  const fs = statfsSync(root);
  if (fs.bavail * fs.bsize < 5 * 1024 ** 3) throw new Error('Moins de 5 Gio libres : témoin interrompu.');
}

async function run(command, args, { timeout = 60_000, logfile, allowFailure = false } = {}) {
  space();
  const child = spawn(command, args, { cwd: root, env: environment,
    detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '', stderr = '', bytes = 0, issue;
  const kill = () => { try { process.kill(-child.pid, 'SIGKILL'); } catch { } };
  const collect = (kind, chunk) => {
    if (kind === 'stdout') stdout = (stdout + chunk.toString()).slice(-1_000_000);
    else stderr = (stderr + chunk.toString()).slice(-32_000);
    if (logfile && bytes < 8_000_000) {
      appendFileSync(resolve(output, logfile), chunk.subarray(0, 8_000_000 - bytes));
      bytes += chunk.length;
      if (bytes >= 8_000_000) appendFileSync(resolve(output, logfile), '\n[diagnostic capped at 8 MB]\n');
    }
  };
  child.stdout.on('data', chunk => collect('stdout', chunk));
  child.stderr.on('data', chunk => collect('stderr', chunk));
  const timer = setTimeout(() => { issue = new Error(`${command} : délai dépassé`); kill(); }, timeout);
  const diskTimer = setInterval(() => { try { space(); } catch (error) { issue = error; kill(); } }, 10_000);
  try {
    const code = await new Promise((res, rej) => { child.once('error', rej); child.once('close', res); });
    if (issue) throw issue;
    if (code !== 0 && !allowFailure) throw new Error(`${command} ${args[0]} : ${code}\n${stderr.slice(-2000)}`);
    return { code, stdout, stderr };
  } finally { clearTimeout(timer); clearInterval(diskTimer); }
}

try {
  const toolchain = verifyIosCiXcode((await run('xcodebuild', ['-version'])).stdout);
  writeFileSync(resolve(output, 'ios-toolchain.json'), JSON.stringify(toolchain, null, 2));
  const runtimes = JSON.parse((await run('xcrun', ['simctl', 'list', 'runtimes', '--json'], { timeout: 180_000 })).stdout).runtimes;
  const devices = JSON.parse((await run('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { timeout: 180_000 })).stdout).devices;
  const { runtime, device: selected } = selectIosCiSimulator(runtimes, devices, family);
  device = selected.udid;
  if (!/^[0-9A-F-]{36}$/i.test(device)) throw new Error('UUID simulateur invalide.');
  writeFileSync(resolve(output, 'device.json'), JSON.stringify({ udid: device, name: selected.name,
    runtime: runtime.version, family, platform: 'ios' }, null, 2));
  if (selected.state !== 'Booted') await run('xcrun', ['simctl', 'boot', device], { logfile: 'simulator.log' });
  await run('xcrun', ['simctl', 'bootstatus', device, '-b'], { timeout: 240_000, logfile: 'simulator.log' });
  await run('defaults', ['write', 'com.apple.iphonesimulator', 'ConnectHardwareKeyboard', '-bool', 'false']);
  stage = 'build-reference';
  const base = ['-project', project, '-scheme', scheme, '-configuration', 'Debug', '-sdk', 'iphonesimulator',
    '-destination', `platform=iOS Simulator,id=${device}`, '-derivedDataPath', derived,
    'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO'];
  await run('xcodebuild', ['build-for-testing', ...base], { timeout: 300_000, logfile: 'build.log' });
  const app = resolve(derived, 'Build/Products/Debug-iphonesimulator/UIKitOtpReference.app');
  const plist = resolve(app, 'Info.plist');
  const readPlist = async key => (await run('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, plist])).stdout.trim();
  if (await readPlist('CFBundleIdentifier') !== bundleId || await readPlist('CFBundleSupportedPlatforms:0') !== 'iPhoneSimulator'
    || await readPlist('CFBundleExecutable') !== 'UIKitOtpReference') throw new Error('Mauvaise cible compilée.');
  if (await readPlist('UIDeviceFamily:0') !== '1' || await readPlist('UIDeviceFamily:1') !== '2') {
    throw new Error('Le témoin doit être universel iPhone/iPad, sans mode de compatibilité iPhone.');
  }
  const hash = relative => createHash('sha256').update(readFileSync(resolve(root, relative))).digest('hex');
  writeFileSync(resolve(output, 'provenance.json'), JSON.stringify({ source, kind, family,
    sourceSha: (await run('git', ['rev-parse', 'HEAD'])).stdout.trim(), bundleId, test,
    xcode: (await run('xcodebuild', ['-version'])).stdout.trim(), platform: 'iphonesimulator', configuration: 'Debug',
    applicationSha256: hash('ios-ui-tests/UIKitOtpReference/UIKitOtpReference.swift'),
    testSha256: hash('ios-ui-tests/NativePilotUITests/UIKitOtpReferenceTests.swift'),
    physicalDevice: false, production: false, productScenario: false }, null, 2));
  stage = 'launch-reference';
  await run('xcrun', ['simctl', 'install', device, app], { timeout: 120_000, logfile: 'launch.log' });
  const launch = await run('xcrun', ['simctl', 'launch', device, bundleId, '-JoleneReferenceMode', kind], { timeout: 120_000, logfile: 'launch.log' });
  if (!/^app\.jolene\.otp-uikit-reference: [1-9]\d*$/.test(launch.stdout.trim())) throw new Error('Lancement absent ou ambigu.');
  stage = 'xctest-reference';
  const result = await run('xcodebuild', ['test-without-building', ...base, `-only-testing:${test}`,
    '-resultBundlePath', resultPath, '-parallel-testing-enabled', 'NO',
    '-maximum-concurrent-test-simulator-destinations', '1', '-test-timeouts-enabled', 'YES',
    '-maximum-test-execution-time-allowance', '120'], { timeout: 300_000, logfile: 'xctest.log', allowFailure: true });
  if (!existsSync(resultPath)) throw new Error('Rapport XCTest du témoin absent.');
  const summary = await run('xcrun', ['xcresulttool', 'get', 'test-results', 'summary', '--path', resultPath]);
  writeFileSync(resolve(output, 'xctest-summary.json'), summary.stdout);
  const attachments = resolve(output, 'attachments');
  await run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', resultPath, '--output-path', attachments]);
  const parsed = JSON.parse(summary.stdout);
  if (result.code !== 0 || parsed.result !== 'Passed' || parsed.totalTestCount !== 1 || parsed.passedTests !== 1
    || parsed.failedTests !== 0 || parsed.skippedTests !== 0 || parsed.expectedFailures !== 0) {
    throw new Error('Le témoin ne confirme pas un test réussi sans exclusion.');
  }
  const manifest = JSON.parse(readFileSync(resolve(attachments, 'manifest.json'), 'utf8'));
  if (!Array.isArray(manifest)) throw new Error('Manifest de preuves absent.');
  for (const moment of ['before', 'after']) for (const kind of ['screen', 'accessibility', 'metrics.json']) {
    const name = `${prefix}-${moment}-${kind}`;
    const matches = manifest.flatMap(item => item.attachments || []).filter(item =>
      item.suggestedHumanReadableName?.startsWith(name.replace(/\.json$/, ''))
      && item.exportedFileName?.endsWith(kind === 'screen' ? '.png' : '.txt'));
    if (matches.length !== 1 || basename(matches[0].exportedFileName) !== matches[0].exportedFileName) {
      throw new Error(`Preuve unique manquante : ${name}`);
    }
  }
  success = true;
  stage = 'complete';
} catch (error) {
  writeFileSync(resolve(output, 'failure.txt'), `${stage}: ${error.stack || error}\n`);
  console.error(error);
  process.exitCode = 1;
} finally {
  // Read-only system evidence after the observation. It cannot retry a contact
  // or alter the result; successful controls retain a comparison trace too.
  if (device && kind === 'touch') {
    try {
      const input = await run('xcrun', ['simctl', 'spawn', device, 'log', 'show', '--last', '10m',
        '--style', 'ndjson', '--info', '--debug', '--predicate',
        '(process == "backboardd" OR process == "testmanagerd" OR process == "SpringBoard") AND (eventMessage CONTAINS[c] "digitizer" OR eventMessage CONTAINS[c] "HID" OR eventMessage CONTAINS[c] "sender" OR eventMessage CONTAINS[c] "synthesi")'],
      { timeout: 30_000, allowFailure: true });
      writeFileSync(resolve(output, 'simulator-input-system.ndjson'), input.stdout);
      writeFileSync(resolve(output, 'input-collection.json'), JSON.stringify({ code: input.code,
        tailLimitCharacters: 1_000_000, mayBeTruncated: input.stdout.length >= 1_000_000 }));
    } catch (error) { writeFileSync(resolve(output, 'input-collection-error.txt'), String(error)); }
  }
  writeFileSync(resolve(output, 'result.json'), JSON.stringify({ source, kind, family, started,
    ended: new Date().toISOString(), device, bundleId, stage, success,
    productScenario: false, contractsVerdictChanged: false, production: false, physicalDevice: false }, null, 2));
}

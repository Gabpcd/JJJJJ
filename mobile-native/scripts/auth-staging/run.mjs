import { spawn } from 'node:child_process';
import { createWriteStream, existsSync } from 'node:fs';
import { chmod, copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { finished } from 'node:stream/promises';
import { androidFlows } from './android-flow.mjs';
import { buildCompiledIosClient, COMPILED_APP_ID, requireSimulatorBuildSpace } from '../ios-compiled-client.mjs';
import { readMetroResponse } from '../metro-http.mjs';
import { CAPTURES, PHASES, PROJECT_REF, guardRun, parseCohort, privateLogFilter,
  publicEnvironment, publicReport, sensitiveForms, validatePhaseProof, validatePublicDirectory } from './policy.mjs';

const project = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const format = process.env.AUTH_FORMAT;
const platform = format === 'android' ? 'android' : 'ios';
const appId = platform === 'ios' ? COMPILED_APP_ID : 'host.exp.exponent';
let temporary, output, device, metro, environment, cohort, forms = [], phases = [], passed = false, cleanup = false;
let failure = 'preparation';
const streams = new Set();
const children = new Set();
const metroFilters = [];
const stop = child => { if (child?.pid) { try { process.kill(-child.pid, 'SIGKILL'); } catch { /* Finished. */ } } };
function fail(code) { throw new Error(code); }
async function stopAndWait(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const closed = new Promise(resolve => child.once('close', resolve));
  stop(child);
  await Promise.race([closed, delay(5000)]);
  // Never let a late pipe write into an ended log after a bounded cleanup wait.
  child.stdout?.unpipe(); child.stderr?.unpipe();
}

async function run(command, args, { timeout = 60_000, input, allowFailure = false, capture = true,
  captureLimit = 32 * 1024 * 1024, extraEnv = {} } = {}) {
  const log = createWriteStream(resolve(temporary, 'commands.redacted.log'), { flags: 'a', mode: 0o600 });
  const out = privateLogFilter(forms), err = privateLogFilter(forms);
  out.pipe(log, { end: false }); err.pipe(log, { end: false }); streams.add(log);
  const started = Date.now();
  const child = spawn(command, args, { cwd: project, env: { ...environment, ...extraEnv }, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
  children.add(child);
  child.stdout.pipe(out); child.stderr.pipe(err);
  let stdout = '', size = 0, expired = false;
  if (capture) child.stdout.on('data', chunk => {
    const remaining = Math.max(0, captureLimit - size);
    if (remaining) stdout += chunk.subarray(0, remaining).toString();
    size += chunk.length;
  });
  child.stdin.on('error', () => {}); child.stdin.end(input);
  const timer = setTimeout(() => { expired = true; stop(child); }, timeout);
  const diskTimer = platform === 'ios' ? setInterval(() => {
    try { requireSimulatorBuildSpace(project); }
    catch { expired = true; stop(child); }
  }, 15_000) : null;
  try {
    const code = await new Promise((accept, reject) => {
      child.once('error', () => reject(new Error('COMMAND_START'))); child.once('close', accept);
    });
    await Promise.all([finished(out), finished(err)]);
    if (!allowFailure && (expired || child.signalCode || code !== 0)) fail('COMMAND_FAILED');
    return { code, stdout, expired, signal: child.signalCode, durationMs: Date.now() - started };
  } finally { clearTimeout(timer); if (diskTimer) clearInterval(diskTimer); children.delete(child); log.end(); await finished(log); streams.delete(log); }
}

async function files(directory) {
  return (await Promise.all((await readdir(directory, { withFileTypes: true })).map(item =>
    item.isDirectory() ? files(resolve(directory, item.name)) : [resolve(directory, item.name)]))).flat();
}
async function privateWrite(path, data) { await writeFile(path, data, { flag: 'wx', mode: 0o600 }); }
async function copyCapture(source, name) {
  const bytes = await readFile(source);
  if (bytes.length < 32 || bytes.length > 20 * 1024 * 1024 || !bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) fail('CAPTURE_FORMAT');
  await copyFile(source, resolve(output, name));
}

async function chooseDevice() {
  if (platform === 'android') {
    const list = (await run('adb', ['devices'])).stdout.split('\n').slice(1).map(x => x.trim()).filter(Boolean).map(x => x.split(/\s+/));
    if (list.length !== 1 || !/^emulator-\d+$/.test(list[0][0]) || list[0][1] !== 'device') fail('EMULATOR_ONLY');
    device = list[0][0]; environment.ANDROID_SERIAL = device;
    if ((await run('adb', ['-s', device, 'shell', 'getprop', 'sys.boot_completed'])).stdout.trim() !== '1') fail('EMULATOR_BOOT');
    await run('adb', ['-s', device, 'reverse', 'tcp:8090', 'tcp:8090']);
    return;
  }
  const runtimes = JSON.parse((await run('xcrun', ['simctl', 'list', 'runtimes', '--json'], { timeout: 180_000 })).stdout).runtimes;
  const devices = JSON.parse((await run('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { timeout: 180_000 })).stdout).devices;
  const family = format === 'iphone' ? 'iphone' : 'ipad';
  for (const runtime of runtimes.filter(r => r.isAvailable && r.identifier.includes('.iOS-')).sort((a,b) => b.version.localeCompare(a.version, undefined, { numeric: true }))) {
    const candidate = (devices[runtime.identifier] ?? []).find(d => d.isAvailable && (d.deviceTypeIdentifier ?? d.name).toLowerCase().includes(family));
    if (!candidate) continue;
    device = candidate.udid;
    await run('xcrun', ['simctl', 'shutdown', 'all']);
    await run('xcrun', ['simctl', 'boot', device]);
    await run('xcrun', ['simctl', 'bootstatus', device, '-b'], { timeout: 360_000 });
    await run('defaults', ['write', 'com.apple.iphonesimulator', 'ConnectHardwareKeyboard', '-bool', 'false']);
    return;
  }
  fail('SIMULATOR_UNAVAILABLE');
}

async function prepareExpo() {
  if (platform === 'ios') {
    const compiledOutput = resolve(temporary, 'compiled');
    await mkdir(compiledOutput, { mode: 0o700 });
    // Same source client and TextInput patch as the passing consultation tests.
    // Build receipts and logs remain private; no identity is passed to this build.
    await buildCompiledIosClient({ project, output: compiledOutput, device, env: environment, run });
  } else {
  const record = resolve(temporary, 'expo-binary.json');
  // Same pinned SDK downloader as the existing native consultation runner.
  const source = `const {createRequire}=require('node:module');const {dirname,resolve}=require('node:path');const {writeFileSync}=require('node:fs');
    const req=createRequire(require.resolve('expo/package.json'));const root=dirname(req.resolve('@expo/cli/package.json'));
    require(resolve(root,'build/src/utils/downloadExpoGoAsync.js')).downloadExpoGoAsync(process.argv[1],{sdkVersion:'57.0.0'})
    .then(binaryPath=>writeFileSync(process.argv[2],JSON.stringify({binaryPath}))).catch(()=>{process.exitCode=1;});`;
  await run(process.execPath, ['-e', source, platform, record], { timeout: 360_000 });
  const binary = JSON.parse(await readFile(record, 'utf8')).binaryPath;
  if (typeof binary !== 'string' || !existsSync(binary)) fail('EXPO_BINARY');
  await run('adb', ['-s', device, 'install', '-r', binary], { timeout: 180_000 });
  }
  const log = createWriteStream(resolve(temporary, 'metro.redacted.log'), { mode: 0o600 }); streams.add(log);
  metro = spawn('npx', ['--no-install', 'expo', 'start', platform === 'ios' ? '--dev-client' : '--go', '--localhost', '--port', '8090'],
    { cwd: project, env: environment, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  const filterA = privateLogFilter(forms), filterB = privateLogFilter(forms);
  metroFilters.push(filterA, filterB);
  metro.stdout.pipe(filterA).pipe(log, { end: false }); metro.stderr.pipe(filterB).pipe(log, { end: false });
  metro.on('error', () => {});
  const deadline = Date.now() + 180_000;
  let ready = false;
  while (Date.now() < deadline) {
    if (metro.exitCode !== null || metro.signalCode !== null) fail('METRO_STOPPED');
    try { const response = await readMetroResponse('http://127.0.0.1:8090/status', { timeoutMs: 5000, maxBytes: 4096 });
      if (response.ok && response.body.toString('utf8').includes('packager-status:running')) { ready = true; break; }
    } catch { /* Bounded Metro startup only, never an Auth retry. */ }
    await delay(2000);
  }
  if (!ready) fail('METRO_STARTUP');
  const response = await readMetroResponse('http://127.0.0.1:8090/', { headers: { 'expo-platform': platform, accept: 'application/expo+json' }, timeoutMs: 120_000, maxBytes: 1024 * 1024 });
  if (!response.ok) fail('METRO_MANIFEST');
  const manifest = JSON.parse(response.body.toString('utf8')), sdk = manifest.extra?.expoClient?.sdkVersion ?? manifest.sdkVersion;
  if (!String(sdk).startsWith('57.')) fail('EXPO_SDK');
  const url = new URL(manifest.launchAsset?.url);
  if (url.protocol !== 'http:' || !['127.0.0.1','localhost'].includes(url.hostname) || url.port !== '8090') fail('METRO_ORIGIN');
  const bundle = await readMetroResponse(url, { timeoutMs: 180_000, maxBytes: 128 * 1024 * 1024 });
  if (!bundle.ok || !bundle.body.byteLength) fail('METRO_BUNDLE');
}

async function ios() {
  const derived = resolve(temporary, 'derived');
  await run('xcodebuild', ['build-for-testing', '-project', resolve(project, 'ios-auth-ui-tests/NativeAuthUITests.xcodeproj'),
    '-scheme', 'NativeAuthUITests', '-configuration', 'Debug', '-sdk', 'iphonesimulator',
    '-destination', `platform=iOS Simulator,id=${device}`, '-derivedDataPath', derived,
    'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO'], { timeout: 600_000 });
  const candidates = (await files(resolve(derived, 'Build/Products'))).filter(p => p.endsWith('.xctestrun'));
  if (candidates.length !== 1) fail('XCTESTRUN_AMBIGUOUS');
  const privateRun = resolve(dirname(candidates[0]), 'NativeAuth.private.xctestrun');
  await run('python3', [resolve(project, 'scripts/auth-staging/inject-xctestrun.py')], { input: JSON.stringify({
    source: candidates[0], destination: privateRun, environment: {
      JOLENE_AUTH_COHORT_JSON: JSON.stringify(cohort), JOLENE_AUTH_FORMAT: format,
    },
  }) });
  // One initial launch after Metro is ready, then four planned persistence
  // restarts in XCTest. The argument is only the public local Metro address.
  await run('xcrun', [
    'simctl', 'launch', device, appId, '-RCT_jsLocation', '127.0.0.1:8090',
  ], { timeout: 120_000 });
  failure = 'driver';
  const resultPath = resolve(temporary, 'auth.xcresult');
  const result = await run('xcodebuild', ['test-without-building', '-xctestrun', privateRun,
    '-only-testing:NativeAuthUITests/NativeAuthTests/testStagingAuthIsolation',
    '-destination', `platform=iOS Simulator,id=${device}`, '-resultBundlePath', resultPath,
    '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
    '-test-timeouts-enabled', 'YES', '-maximum-test-execution-time-allowance', '540'], { timeout: 660_000, allowFailure: true, capture: false });
  failure = 'proof';
  if (!existsSync(resultPath)) fail('XCTEST_NO_RESULT');
  const summary = JSON.parse((await run('xcrun', ['xcresulttool', 'get', 'test-results', 'summary', '--path', resultPath])).stdout);
  const attachments = resolve(temporary, 'attachments');
  await run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', resultPath, '--output-path', attachments]);
  const manifest = JSON.parse(await readFile(resolve(attachments, 'manifest.json'), 'utf8'));
  if (!Array.isArray(manifest)) fail('ATTACHMENT_MANIFEST');
  const all = manifest.flatMap(test => test.attachments ?? []);
  const attachment = name => {
    const matching = all.filter(item => item.suggestedHumanReadableName?.startsWith(name));
    if (matching.length !== 1 || typeof matching[0].exportedFileName !== 'string'
      || basename(matching[0].exportedFileName) !== matching[0].exportedFileName) fail('ATTACHMENT_SELECTION');
    return resolve(attachments, matching[0].exportedFileName);
  };
  phases = validatePhaseProof(JSON.parse(await readFile(attachment('native-auth-proof-v1.json'), 'utf8')));
  for (const phase of phases) if (CAPTURES[phase]) await copyCapture(attachment(CAPTURES[phase].replace('.png', '')), CAPTURES[phase]);
  if (result.expired || result.signal || result.code !== 0 || summary.result !== 'Passed' || summary.totalTestCount !== 1 || summary.passedTests !== 1
    || summary.failedTests !== 0 || summary.skippedTests !== 0 || summary.expectedFailures !== 0 || phases.length !== PHASES.length) fail('XCTEST_FAILED');
}

async function android() {
  for (const scenario of androidFlows(cohort)) {
    const directory = resolve(temporary, scenario.phase); await mkdir(directory, { mode: 0o700 });
    const flow = resolve(directory, 'private.yaml'); await privateWrite(flow, scenario.flow);
    if (scenario.restartProcess) {
      await run('adb', ['-s', device, 'shell', 'am', 'force-stop', appId]);
      const state = await run('adb', ['-s', device, 'shell', 'pidof', appId], { allowFailure: true });
      if (state.code !== 1 || state.stdout.trim()) fail('PROCESS_NOT_STOPPED');
    }
    failure = 'driver';
    await run('maestro', ['--device', device, '--platform', 'android', 'test', '--format', 'junit',
      '--output', resolve(directory, 'junit.xml'), '--debug-output', resolve(directory, 'debug'),
      '--test-output-dir', resolve(directory, 'results'), flow], { timeout: scenario.phase === 'initial_signed_out' ? 240_000 : 120_000, capture: false });
    failure = 'proof';
    const junit = await readFile(resolve(directory, 'junit.xml'), 'utf8');
    if (!/<testsuite\b[^>]*\btests="1"/.test(junit) || /\b(?:failures|errors|skipped)="[1-9]\d*"/.test(junit)
      || /<(?:failure|error|skipped)\b/.test(junit)) fail('MAESTRO_PROOF');
    phases.push(scenario.phase);
    if (scenario.capture) {
      const matches = (await files(directory)).filter(p => basename(p) === `${scenario.capture}.png`);
      if (matches.length !== 1) fail('CAPTURE_SELECTION');
      await copyCapture(matches[0], `${scenario.capture}.png`);
    }
  }
}

try {
  let input = Buffer.alloc(0);
  for await (const chunk of process.stdin) { input = Buffer.concat([input, chunk]); if (input.length > 8192) fail('INPUT_SIZE'); }
  cohort = parseCohort(input.toString('utf8')); input.fill(0); forms = sensitiveForms(cohort);
  if (!process.env.RUNNER_TEMP || !process.env.GITHUB_WORKSPACE) fail('RUNNER_DIRECTORIES');
  temporary = await mkdtemp(resolve(process.env.RUNNER_TEMP, 'jolene-auth-private-')); await chmod(temporary, 0o700);
  environment = publicEnvironment(process.env, { key: process.env.AUTH_PUBLISHABLE_KEY, sha: process.env.AUTH_SHA });
  const sha = (await run('git', ['rev-parse', 'HEAD'])).stdout.trim();
  guardRun({ actions: process.env.GITHUB_ACTIONS, event: process.env.GITHUB_EVENT_NAME, ref: process.env.GITHUB_REF,
    sha: process.env.AUTH_SHA, reviewedSha: process.env.AUTH_REVIEWED_SHA, checkoutSha: sha,
    dispatchSha: process.env.GITHUB_SHA, workflowSha: process.env.GITHUB_WORKFLOW_SHA,
    format, projectRef: process.env.AUTH_PROJECT_REF, url: process.env.AUTH_URL, key: process.env.AUTH_PUBLISHABLE_KEY });
  await mkdir(resolve(project, 'test-results'), { recursive: true });
  const freshOutput = resolve(project, 'test-results', `native-auth-${format}`);
  await mkdir(freshOutput, { recursive: false }); output = freshOutput;
  await chooseDevice(); await prepareExpo();
  if (platform === 'ios') await ios(); else await android();
  passed = true; failure = null;
} catch { process.exitCode = 1; /* No exception text, raw command, credential or response body leaves this runner. */ }
finally {
  await Promise.allSettled([...children].map(stopAndWait));
  await stopAndWait(metro);
  for (const filter of metroFilters) { filter.unpipe(); filter.destroy(); }
  if (device && temporary && environment) {
    try {
      if (platform === 'ios') await run('xcrun', ['simctl', 'terminate', device, appId], { allowFailure: true });
      else await run('adb', ['-s', device, 'shell', 'am', 'force-stop', appId], { allowFailure: true });
    } catch { /* Temporary-file cleanup still runs. */ }
  }
  for (const stream of streams) stream.end();
  await Promise.allSettled([...streams].map(stream => finished(stream)));
  try { if (temporary) await rm(temporary, { recursive: true, force: true }); cleanup = true; }
  catch { passed = false; failure = 'cleanup'; process.exitCode = 1; }
  if (output) {
    try {
      await writeFile(resolve(output, 'report.json'), publicReport({ sha: process.env.AUTH_SHA, format, phases, passed, failure, cleanup }, forms));
      validatePublicDirectory(await readdir(output), phases);
      process.stdout.write(`Native Auth TEST: ${passed ? 'PASS' : 'FAIL'}; public whitelist only.\n`);
    } catch { process.exitCode = 1; await rm(output, { recursive: true, force: true }); process.stderr.write('AUTH_PUBLIC_EXPORT_REFUSED\n'); }
  } else process.stderr.write('AUTH_PREPARATION_REFUSED\n');
}

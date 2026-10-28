import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const BUNDLE_ID = 'host.exp.Exponent';
const MARKER = '[jolene-native-navigation]';
const THRESHOLD_MS = 2_000;
const SAMPLE_SECONDS = 3;
const SAMPLE_INTERVAL_MS = 10;
const MAX_LINE = 8_192;
const noopMonitor = { consume() {}, async dispose() {} };

function processIdentity(stdout, pid, uid, executable) {
  // macOS ps lstart is a fixed, five-field date. Keep it opaque when comparing
  // so a PID recycled since simctl launch cannot silently select another process.
  const match = stdout.trim().match(/^(\d+)\s+(\d+)\s+(\S+\s+\S+\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(.+)$/);
  if (!match || Number(match[1]) !== pid || Number(match[2]) !== uid || match[4] !== executable) return null;
  return { pid, uid, executable, started: match[3].replace(/\s+/g, ' ') };
}

/**
 * One bounded, read-only host sample of the prepared app in a disposable CI simulator.
 * Apple sample(1): duration is seconds; interval is milliseconds. Sampling briefly
 * suspends threads, so its timestamps are recorded and never used as a test pass.
 * No process-name fallback, elevated access, new app launch, or test retry.
 */
export async function createIosNavigationStallMonitor({
  env, platform, device, output, launchOutput, run, bundleId = BUNDLE_ID,
  hostPlatform = process.platform, uid = process.getuid?.(),
  schedule = setTimeout, cancel = clearTimeout, now = Date.now,
}) {
  if (env.GITHUB_ACTIONS !== 'true' || platform !== 'ios' || hostPlatform !== 'darwin'
    || env.EXPO_PUBLIC_JOLENE_MODE !== 'demo' || env.EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS !== '1'
    || ![BUNDLE_ID, 'app.jolene.nativepilot'].includes(bundleId)
    || !/^[0-9A-F-]{36}$/i.test(device) || !Number.isSafeInteger(uid)) return noopMonitor;

  const directory = resolve(output, 'ios-navigation-stall');
  const report = { diagnosticOnly: true, simulator: device, status: 'initializing', thresholdMs: THRESHOLD_MS,
    sampleSeconds: SAMPLE_SECONDS, sampleIntervalMs: SAMPLE_INTERVAL_MS, maxSamples: 1 };
  const persist = () => {
    // Diagnostic disk errors must not replace the XCTest result.
    try { mkdirSync(directory, { recursive: true }); writeFileSync(resolve(directory, 'index.json'), JSON.stringify(report, null, 2)); }
    catch { /* Existing XCTest/runner artifacts remain authoritative. */ }
  };
  const read = async (operation, command, args) => {
    // Fixed operation names identify the failed guard without exporting process
    // arguments, paths or arbitrary command output. Keep the existing bounds.
    report.operation = operation;
    persist();
    const result = await run(command, args, { timeout: 5_000, allowFailure: true });
    if (result.code !== 0) {
      report.commandExitCode = Number.isInteger(result.code) ? result.code : null;
      throw new Error('DIAGNOSTIC_COMMAND_FAILED');
    }
    return result.stdout;
  };

  let identity;
  try {
    const launches = launchOutput.trim().split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    const prefix = `${bundleId}: `;
    const value = launches.length === 1 && launches[0].startsWith(prefix) ? launches[0].slice(prefix.length) : '';
    const pid = /^[1-9]\d*$/.test(value) ? Number(value) : NaN;
    if (!Number.isSafeInteger(pid) || pid < 2 || pid > 2_147_483_647) throw new Error('INVALID_LAUNCH_PID');
    const app = (await read('locate-expo-container', 'xcrun', ['simctl', 'get_app_container', device, bundleId, 'app'])).trim();
    if (!app.startsWith('/') || !app.includes(`/CoreSimulator/Devices/${device}/data/Containers/Bundle/Application/`)
      || !app.endsWith('.app') || /[\r\n\0]/.test(app)) throw new Error('INVALID_SIMULATOR_APP_PATH');
    const plist = resolve(app, 'Info.plist');
    const bundle = (await read('read-expo-bundle-id', '/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', plist])).trim();
    const name = (await read('read-expo-executable', '/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleExecutable', plist])).trim();
    if (bundle !== bundleId || !/^[A-Za-z0-9._ -]+$/.test(name) || name === '.' || name === '..') throw new Error('INVALID_EXPO_BUNDLE');
    identity = processIdentity(await read('verify-launched-process', '/bin/ps', ['-ww', '-p', String(pid), '-o', 'pid=,uid=,lstart=,comm=']), pid, uid, resolve(app, name));
    if (!identity) throw new Error('LAUNCHED_PROCESS_MISMATCH');
    report.process = identity;
    report.status = 'waiting';
  } catch (error) {
    report.status = 'unavailable';
    report.reason = error instanceof Error && /^[A-Z_]+$/.test(error.message) ? error.message : 'DIAGNOSTIC_SETUP_FAILED';
    persist();
    return noopMonitor;
  }
  persist();

  let closed = false;
  let attempted = false;
  let timer;
  let pending;
  let collection;
  let sequence = 0;
  let lastState;
  let lastMissionPush;
  const buffers = new Map();
  const clearPending = () => { if (timer !== undefined) cancel(timer); timer = undefined; pending = undefined; };
  const collect = async candidate => {
    if (closed || attempted || pending !== candidate) return;
    attempted = true; // Even a failed process check consumes this run's only attempt.
    timer = undefined;
    report.trigger = { ...candidate, observedAt: now() };
    report.status = 'verifying-process';
    persist();
    try {
      const current = processIdentity(await read('recheck-launched-process', '/bin/ps', ['-ww', '-p', String(identity.pid), '-o', 'pid=,uid=,lstart=,comm=']), identity.pid, uid, identity.executable);
      if (!current || current.started !== identity.started) throw new Error('LAUNCHED_PROCESS_CHANGED');
      // Transition callbacks can arrive while ps runs. Do not sample a recovered
      // transition or a route that has already been left.
      if (closed || pending !== candidate) {
        report.status = 'cancelled-before-sample';
        return;
      }
      report.status = 'sampling';
      report.sampleStartedAt = now();
      persist();
      const result = await run('/usr/bin/sample', [String(identity.pid), String(SAMPLE_SECONDS), String(SAMPLE_INTERVAL_MS),
        '-file', resolve(directory, 'expo-main-thread.sample.txt')],
      { timeout: 15_000, allowFailure: true, logfile: 'ios-navigation-stall/sample-command.log' });
      report.sampleFinishedAt = now();
      report.exitCode = result.code;
      report.status = result.code === 0 ? 'collected' : 'collection-failed';
    } catch (error) {
      report.status = 'collection-failed';
      report.reason = error instanceof Error && /^[A-Z_]+$/.test(error.message) ? error.message : 'DIAGNOSTIC_COLLECTION_FAILED';
    } finally { persist(); }
  };
  const acceptLine = line => {
    if (closed || line.length > MAX_LINE) return;
    const marker = line.indexOf(MARKER);
    if (marker < 0) return;
    let event;
    try { event = JSON.parse(line.slice(marker + MARKER.length).replace(/\u001b\[[0-9;]*m/g, '').trim()); }
    catch { return; }
    if (!event || !Number.isSafeInteger(event.sequence) || event.sequence <= sequence
      || !Number.isFinite(event.elapsedMs) || event.elapsedMs < 0 || typeof event.detail !== 'string') return;
    sequence = event.sequence;
    if (event.event === 'transitionStart' && event.detail === 'Mission:push') {
      lastMissionPush = event;
      if (pending) {
        report.transitionStartedAt = now();
        report.transitionElapsedMs = event.elapsedMs;
        clearPending();
        persist();
      }
    } else if (event.event === 'state') {
      if (event.detail === lastState) return;
      lastState = event.detail;
      clearPending();
      if (attempted || !/(?:^|\/)Mission\[\d+\/\d+\]$/.test(event.detail)) return;
      // Native callbacks can precede onStateChange in the same transition.
      if (lastMissionPush && event.elapsedMs >= lastMissionPush.elapsedMs && event.elapsedMs - lastMissionPush.elapsedMs <= THRESHOLD_MS) return;
      pending = { sequence: event.sequence, route: event.detail, elapsedMs: event.elapsedMs, receivedAt: now() };
      const candidate = pending;
      timer = schedule(() => { collection = collect(candidate); }, THRESHOLD_MS);
    }
  };
  return {
    consume(channel, chunk) {
      if (closed || !['stdout', 'stderr'].includes(channel)) return;
      const text = (buffers.get(channel) ?? '') + chunk.toString();
      const lines = text.split(/\r?\n/);
      const remainder = lines.pop();
      buffers.set(channel, remainder.length <= MAX_LINE ? remainder : '');
      for (const line of lines) acceptLine(line);
    },
    async dispose() {
      closed = true;
      clearPending();
      buffers.clear();
      await collection; // At most one ps (5s) and one sample (15s), never a test retry.
      if (!attempted) report.status = 'not-triggered';
      persist();
    },
  };
}

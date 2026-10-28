import { collectExpoUpdatesFailureLog } from './expo-updates-failure-log.mjs';
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve } from 'node:path';

/** Diagnostic only: this reads the disposable CI simulator, never a developer's Mac. */
export async function collectIosFailureDiagnostics({ device, output, started, run, env, failed, compiledClient }) {
  if (process.env.GITHUB_ACTIONS !== 'true' || !/^[0-9A-F-]{36}$/i.test(device)) return;
  if (compiledClient && (compiledClient.bundleId !== 'app.jolene.nativepilot'
    || !/^[A-Za-z0-9._ -]+$/.test(compiledClient.executable))) return;
  const directory = resolve(output, 'ios-failure-diagnostics');
  mkdirSync(directory, { recursive: true });
  const notes = [];
  if (!compiledClient) notes.push(await collectExpoUpdatesFailureLog({ env, failed, device, started, directory, run }));
  const processes = compiledClient ? `process == "${compiledClient.executable}"` : 'process == "Exponent" OR process == "Expo Go"';
  const bundleId = compiledClient?.bundleId ?? 'host.exp.Exponent';
  // Include OS events that explicitly name this app's scene, so cancellation by
  // BackBoard remains visible alongside the app's own touch callbacks.
  const systemPredicate = `${processes} OR eventMessage CONTAINS "${bundleId}"`;
  const logPrefix = compiledClient ? 'compiled' : 'expo';
  try {
    const result = await run('xcrun', ['simctl', 'spawn', device, 'log', 'show', '--last', '15m',
      '--style', 'compact', '--predicate',
      `(${systemPredicate}) AND NOT (subsystem BEGINSWITH[c] "com.apple.dt.xctest")`],
    { timeout: 30_000, allowFailure: true });
    // AX dumps otherwise consume the entire tail and erase the touch/focus events
    // preceding the failure. XCTest preserves its own AX attachments separately.
    // The original test result remains the only success criterion.
    writeFileSync(resolve(directory, `${logPrefix}-system.log`), (result.stdout + result.stderr).slice(-2_000_000));
    notes.push({ systemLogExitCode: result.code });
  } catch (error) { notes.push({ systemLogError: String(error) }); }

  // AX snapshots also repeat the visible error text: exclude XCTest's subsystem
  // before bounding the log, otherwise it erases the original network failure.
  // Preserve a separate bounded view of Expo network failures, without
  // enabling verbose network logging or changing the application under test.
  try {
    const result = await run('xcrun', ['simctl', 'spawn', device, 'log', 'show', '--last', '15m',
      '--style', 'compact', '--predicate',
      `(${processes}) AND NOT (subsystem BEGINSWITH[c] "com.apple.dt.xctest") AND (subsystem CONTAINS[c] "CFNetwork" OR eventMessage CONTAINS[c] "timed out" OR eventMessage CONTAINS "NSURLError" OR eventMessage CONTAINS "CFNetwork" OR eventMessage CONTAINS[c] "connection failed")`],
    { timeout: 30_000, allowFailure: true });
    writeFileSync(resolve(directory, `${logPrefix}-network-errors.log`), (result.stdout + result.stderr).slice(-256_000));
    notes.push({ networkErrorLogExitCode: result.code });
  } catch (error) { notes.push({ networkErrorLogError: String(error) }); }

  const folders = [
    resolve(homedir(), 'Library/Logs/DiagnosticReports'),
    resolve(homedir(), 'Library/Developer/CoreSimulator/Devices', device, 'data/Library/Logs/CrashReporter'),
  ];
  let count = 0;
  for (const folder of folders) {
    if (!existsSync(folder)) continue;
    for (const entry of readdirSync(folder, { withFileTypes: true })) {
      const matchingName = compiledClient
        ? entry.name.startsWith(`${compiledClient.executable}-`) || entry.name.startsWith(`${compiledClient.executable}_`) || /^JetsamEvent[-_]/i.test(entry.name)
        : /^(Exponent|Expo[ -]?Go|JetsamEvent)[-_]/i.test(entry.name);
      if (count >= 8 || !entry.isFile() || !/\.(ips|crash)$/i.test(entry.name) || !matchingName) continue;
      const path = resolve(folder, entry.name);
      const stats = statSync(path);
      if (stats.mtimeMs < Date.parse(started) || stats.size > 2_000_000) continue;
      const contents = readFileSync(path, 'utf8');
      if (compiledClient ? !contents.includes(compiledClient.bundleId)
        : !/host\.exp\.Exponent|"name"\s*:\s*"Exponent"/.test(contents)) continue;
      copyFileSync(path, resolve(directory, `${++count}-${entry.name}`));
      notes.push({ report: entry.name, bytes: stats.size });
    }
  }
  writeFileSync(resolve(directory, 'index.json'), JSON.stringify({ started, reports: count, notes }, null, 2));
}

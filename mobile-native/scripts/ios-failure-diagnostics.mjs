import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve } from 'node:path';

/** Diagnostic only: this reads the disposable CI simulator, never a developer's Mac. */
export async function collectIosFailureDiagnostics({ device, output, started, run }) {
  if (process.env.GITHUB_ACTIONS !== 'true' || !/^[0-9A-F-]{36}$/i.test(device)) return;
  const directory = resolve(output, 'ios-failure-diagnostics');
  mkdirSync(directory, { recursive: true });
  const notes = [];
  try {
    const result = await run('xcrun', ['simctl', 'spawn', device, 'log', 'show', '--last', '15m',
      '--style', 'compact', '--predicate',
      'process == "Exponent" OR process == "Expo Go" OR eventMessage CONTAINS "host.exp.Exponent"'],
    { timeout: 30_000, allowFailure: true });
    // Keep a bounded tail; the original test result remains the only success criterion.
    writeFileSync(resolve(directory, 'expo-system.log'), (result.stdout + result.stderr).slice(-2_000_000));
    notes.push({ systemLogExitCode: result.code });
  } catch (error) { notes.push({ systemLogError: String(error) }); }

  const folders = [
    resolve(homedir(), 'Library/Logs/DiagnosticReports'),
    resolve(homedir(), 'Library/Developer/CoreSimulator/Devices', device, 'data/Library/Logs/CrashReporter'),
  ];
  let count = 0;
  for (const folder of folders) {
    if (!existsSync(folder)) continue;
    for (const entry of readdirSync(folder, { withFileTypes: true })) {
      if (count >= 8 || !entry.isFile() || !/\.(ips|crash)$/i.test(entry.name)
        || !/^(Exponent|Expo[ -]?Go|JetsamEvent)[-_]/i.test(entry.name)) continue;
      const path = resolve(folder, entry.name);
      const stats = statSync(path);
      if (stats.mtimeMs < Date.parse(started) || stats.size > 2_000_000) continue;
      const contents = readFileSync(path, 'utf8');
      if (!/host\.exp\.Exponent|"name"\s*:\s*"Exponent"/.test(contents)) continue;
      copyFileSync(path, resolve(directory, `${++count}-${entry.name}`));
      notes.push({ report: entry.name, bytes: stats.size });
    }
  }
  writeFileSync(resolve(directory, 'index.json'), JSON.stringify({ started, reports: count, notes }, null, 2));
}

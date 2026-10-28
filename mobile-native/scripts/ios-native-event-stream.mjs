import { spawn } from 'node:child_process';
import { appendFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { StringDecoder } from 'node:string_decoder';
import { setTimeout as delay } from 'node:timers/promises';

const MAX_BYTES = 2_000_000;
const MAX_LINE = 32_768;
const MARKER = /\[jolene-native-(?:navigation|contract-input)\]/;

/** Strip only the two observed RN console envelopes; never rewrite the event. */
export function nativeDiagnosticLine(message) {
  if (typeof message !== 'string' || !MARKER.test(message)) return null;
  if (message.length > MAX_LINE) throw new Error('Événement natif trop long.');
  const start = message.search(MARKER);
  const match = message.slice(start).match(/^(\[jolene-native-(?:navigation|contract-input)\])(?:\s+(\{[^\r\n]*\})|', '(\{[^\r\n]*\})')$/);
  if (!match) throw new Error('Enveloppe du diagnostic natif inconnue ou tronquée.');
  const json = match[2] ?? match[3];
  JSON.parse(json);
  return `${match[1]} ${json}\n`;
}

/** One canonical, bounded stream, bound to the PID returned by the sole launch. */
export async function startNativeEventStream({ device, executable, output, env, onLine }) {
  if (env.GITHUB_ACTIONS !== 'true' || process.platform !== 'darwin'
    || env.EXPO_PUBLIC_JOLENE_MODE !== 'demo' || env.EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS !== '1'
    || !/^[0-9A-F-]{36}$/i.test(device) || !/^[A-Za-z0-9._ -]+$/.test(executable)) {
    throw new Error('Collecte native réservée au processus de démonstration CI.');
  }
  const eventPath = resolve(output, 'native-events.log');
  const rawPath = resolve(output, 'native-events.ndjson');
  writeFileSync(eventPath, '');
  writeFileSync(rawPath, '');
  const child = spawn('xcrun', ['simctl', 'spawn', device, 'log', 'stream', '--style', 'ndjson',
    '--level', 'debug', '--predicate', `process == "${executable}" AND eventMessage CONTAINS "[jolene-native-"`],
  { env, stdio: ['ignore', 'pipe', 'pipe'] });
  const decoder = new StringDecoder('utf8');
  let buffer = '';
  let bytes = 0;
  let events = 0;
  let pid;
  let failure;
  let closed = false;
  let pending = [];
  let stderr = '';
  let resolveClosed;
  const ended = new Promise(resolveEnd => { resolveClosed = resolveEnd; });
  const fail = error => { failure ??= error; child.kill('SIGTERM'); };
  const accept = (record, raw) => {
    if (record.processID !== pid) throw new Error('Diagnostic émis par un autre processus que celui lancé.');
    const line = nativeDiagnosticLine(record.eventMessage);
    if (!line) return;
    // Raw metadata is retained for this exact PID and these demo markers only.
    appendFileSync(rawPath, raw + '\n');
    appendFileSync(eventPath, line);
    events += 1;
    onLine?.(line);
  };
  child.stdout.on('data', chunk => {
    if (failure || closed) return;
    try {
      bytes += chunk.length;
      if (bytes > MAX_BYTES) throw new Error('Plafond du flux natif atteint ; preuve incomplète.');
      buffer += decoder.write(chunk);
      const lines = buffer.split('\n');
      buffer = lines.pop();
      if (buffer.length > MAX_LINE) throw new Error('Ligne native non bornée.');
      for (const raw of lines) {
        if (raw.length > MAX_LINE) throw new Error('Ligne native trop longue.');
        if (!raw.trim()) continue;
        // log stream emits a single filter description before its NDJSON.
        if (!raw.startsWith('{')) {
          if (/^Filtering the log data using /.test(raw)) continue;
          throw new Error('Sortie non JSON inattendue du flux natif.');
        }
        const record = JSON.parse(raw);
        if (!MARKER.test(record.eventMessage ?? '')) continue;
        if (!Number.isSafeInteger(record.processID)) throw new Error('PID natif absent.');
        if (pid === undefined) pending.push({ record, raw });
        else accept(record, raw);
      }
    } catch (error) { fail(error); }
  });
  child.stderr.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(-8_192); });
  child.once('error', error => { fail(error); resolveClosed(); });
  child.once('close', code => {
    if (!closed && !failure) failure = new Error(`Flux natif arrêté prématurément (${code}).`);
    resolveClosed();
  });
  const assertHealthy = () => {
    if (failure) throw failure;
    if (child.exitCode !== null || child.signalCode !== null) throw new Error('Collecteur natif arrêté.');
  };
  // Give log stream its bounded startup before the sole app launch; missing early
  // events still fail the existing sequence/lifecycle oracle, never a fallback.
  await delay(1_000);
  try { assertHealthy(); } catch (error) { child.kill('SIGKILL'); throw error; }
  return {
    eventPath,
    bindLaunch(launchOutput, appId) {
      if (pid !== undefined) throw new Error('Le flux natif ne peut pas être lié à un second lancement.');
      const lines = launchOutput.trim().split(/\r?\n/);
      const prefix = `${appId}: `;
      if (lines.length !== 1 || !lines[0].startsWith(prefix) || !/^[1-9]\d*$/.test(lines[0].slice(prefix.length))) {
        throw new Error('PID du lancement natif absent ou ambigu.');
      }
      pid = Number(lines[0].slice(prefix.length));
      if (!Number.isSafeInteger(pid) || pid < 2 || pid > 2_147_483_647) throw new Error('PID natif invalide.');
      for (const item of pending) accept(item.record, item.raw);
      pending = [];
      assertHealthy();
    },
    assertHealthy() {
      assertHealthy();
      if (pid === undefined || events === 0) throw new Error('Aucun événement du processus natif lancé.');
      if (buffer.trim()) throw new Error('Événement natif partiel à la clôture de la preuve.');
    },
    async dispose() {
      closed = true;
      child.kill('SIGTERM');
      await Promise.race([ended, delay(2_000)]);
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
      writeFileSync(resolve(output, 'native-events-status.json'), JSON.stringify({ pid, events, bytes,
        failure: failure?.message ?? null, pendingBytes: buffer.length, stderr }, null, 2));
    },
  };
}

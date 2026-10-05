import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

const fixturePackage = 'app.jolene.recette';
const commands = Object.freeze({
  state: ['get-state'],
  absence: ['shell', 'pm', 'list', 'packages', fixturePackage],
  uid: ['shell', 'id', '-u'],
  root: ['root'],
});

const reasons = new Set(['TIMEOUT', 'INVALID_OUTPUT', 'STATE_REFUSED', 'APP_ALREADY_INSTALLED',
  'UID_REFUSED', 'ROOT_REQUEST_LIMIT', 'ROOT_REFUSED', 'ATTEMPT_LIMIT', 'UNEXPECTED_FAILURE',
  'COMMAND_REFUSED_STATE', 'COMMAND_REFUSED_ABSENCE', 'COMMAND_REFUSED_UID', 'COMMAND_REFUSED_ROOT']);
class ReadinessRefused extends Error {
  constructor(reason) {
    const safe = reasons.has(reason) ? reason : 'UNEXPECTED_FAILURE';
    super(`ADB_READINESS_${safe}`);
    this.reason = safe;
  }
}

// Only exact adb transport failures can wait/reprobe. Never classify an
// application error, a timeout, permissions or arbitrary diagnostic prose.
export function transientAdbFailure(error, stage) {
  if (!Object.hasOwn(commands, stage) || error?.code !== 1 || error.signal !== null
    || error.killed !== false || typeof error.stdout !== 'string' || typeof error.stderr !== 'string'
    || error.stdout !== '') return null;
  const text = typeof error.stderr === 'string' ? error.stderr.trim() : '';
  if (text === 'error: device offline' || text === 'adb: device offline') return 'device_offline';
  if (stage === 'state' && text === 'error: no devices/emulators found') return 'device_missing';
  if (stage === 'root' && text === 'adb: unable to connect for root: closed') return 'root_closed';
  if (stage === 'root' && text === 'adb: unable to connect for root: device offline') return 'device_offline';
  return null;
}

export async function prepareAdbRoot({ adb, record, now = () => performance.now(), pause = delay,
  timeoutMs = 60_000, stableMs = 1_000, maxAttempts = 30, maxRootRequests = 3 }) {
  assert(Number.isInteger(timeoutMs) && timeoutMs > 0 && timeoutMs <= 60_000);
  assert(Number.isInteger(stableMs) && stableMs >= 1_000 && stableMs < timeoutMs);
  assert(Number.isInteger(maxAttempts) && maxAttempts > 0 && maxAttempts <= 30);
  assert(Number.isInteger(maxRootRequests) && maxRootRequests > 0 && maxRootRequests <= 3);
  const start = now(), deadline = start + timeoutMs;
  let stableSince = null, rootRequests = 0, attempt = 0, stage = 'state';
  const refuse = (reason) => { throw new ReadinessRefused(reason); };
  const checkDeadline = () => { if (now() >= deadline) refuse('TIMEOUT'); };
  const emit = async (phase, data = {}) => {
    if (phase !== 'failed') checkDeadline();
    await record({ phase, elapsedMs: now() - start, attempt, ...data });
    if (phase !== 'failed') checkDeadline();
  };
  const boundedPause = async ms => { await pause(ms); checkDeadline(); };
  const run = async (name) => {
    stage = name;
    const remaining = deadline - now();
    if (remaining <= 0) refuse('TIMEOUT');
    const output = await adb([...commands[name]], { timeoutMs: Math.max(1, Math.min(5_000, Math.floor(remaining))) });
    if (now() >= deadline) refuse('TIMEOUT');
    if (typeof output !== 'string') refuse('INVALID_OUTPUT');
    return output.trim();
  };
  try {
    await emit('before-installation');
    while (attempt < maxAttempts && now() < deadline) {
      attempt++;
      try {
        const state = await run('state');
        if (state === 'offline') {
          stableSince = null;
          await emit('transport-wait', { stage: 'state', reason: 'device_offline' });
          await boundedPause(Math.min(1_000, Math.max(0, deadline - now())));
          continue;
        }
        if (state !== 'device') refuse('STATE_REFUSED');
        if (await run('absence') !== '') refuse('APP_ALREADY_INSTALLED');
        const uid = await run('uid');
        if (uid !== '0' && uid !== '2000') refuse('UID_REFUSED');
        await emit('probe', { uid: Number(uid), fixtureInstalled: false });
        if (uid === '0') {
          stableSince ??= now();
          if (now() - stableSince >= stableMs) {
            await emit('ready-before-installation', { uid: 0, fixtureInstalled: false,
              stableMs: now() - stableSince, rootRequests });
            return;
          }
        } else {
          stableSince = null;
          if (rootRequests >= maxRootRequests) refuse('ROOT_REQUEST_LIMIT');
          rootRequests++;
          await emit('root-requested', { rootRequests });
          const result = await run('root');
          if (!['restarting adbd as root', 'adbd is already running as root'].includes(result)) refuse('ROOT_REFUSED');
          // The command may return before adbd restarts. Only fresh uid and
          // absence probes after the restart can establish readiness.
        }
      } catch (error) {
        const reason = transientAdbFailure(error, stage);
        if (!reason) {
          if (error instanceof ReadinessRefused && reasons.has(error.reason)) throw error;
          refuse(`COMMAND_REFUSED_${stage.toUpperCase()}`);
        }
        stableSince = null;
        await emit('transport-wait', { stage, reason });
      }
      const remaining = deadline - now();
      if (remaining > 0) await boundedPause(Math.min(1_000, remaining));
    }
    refuse(now() >= deadline ? 'TIMEOUT' : 'ATTEMPT_LIMIT');
  } catch (error) {
    const reason = error instanceof ReadinessRefused && reasons.has(error.reason) ? error.reason : 'UNEXPECTED_FAILURE';
    try { await emit('failed', { reason: `ADB_READINESS_${reason}`, rootRequests }); } catch {}
    throw new ReadinessRefused(reason);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.equal(process.env.CI, 'true');
  assert.equal(process.env.NATIVE_RECETTE, '1');
  const output = 'test-results/android-native';
  await mkdir(output, { recursive: true });
  const exec = promisify(execFile), entries = [];
  await prepareAdbRoot({
    adb: async (args, { timeoutMs }) => (await exec('adb', args, { timeout: timeoutMs, maxBuffer: 64 * 1024 })).stdout,
    record: async (entry) => {
      entries.push(entry);
      await writeFile(`${output}/adb-readiness.json`, JSON.stringify(entries, null, 2));
    },
  });
}

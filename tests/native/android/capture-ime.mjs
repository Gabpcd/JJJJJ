import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { currentImeShown } from './ime-state.mjs';
import { fixturePackage, requireAppWindow } from './emulator-preflight.mjs';

const execute = promisify(execFile);
const completion = '\nJOLENE_IME_DUMP_COMPLETE\n';
const dumpCommand = "dumpsys -t 10 input_method && printf '\\nJOLENE_IME_DUMP_COMPLETE\\n'";
const dumpError = /DUMP TIMEOUT|Error dumping service|Can't find service|Permission Denial/i;

// Only closed diagnostic codes reach the outer message saved in failure.json.
// Never copy an inner message, command, stdout/stderr or user-entered value.
function diagnosticCode(error) {
  if (error?.code === 'ERR_ASSERTION') return 'ASSERTION_FAILED';
  if (error?.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') return 'OUTPUT_LIMIT';
  if (error?.code === 'ENOENT') return 'FILE_NOT_FOUND';
  if (error?.code === 'EACCES') return 'ACCESS_DENIED';
  if (error?.killed === true) return 'PROCESS_KILLED';
  if (error?.code === 255) return 'ADB_EXIT_255';
  if (Number.isInteger(error?.code) && error.code !== 0) return 'ADB_EXIT_NONZERO';
  return 'OTHER';
}

/** Collect the required evidence through the ADB CLI, independently of the
 * Playwright keyboard assertions. A single interrupted read may be repeated,
 * never an app action; the original app PID and window must survive it. */
export async function captureIme(serial, { expectedPid, run = execute, record = async () => {} } = {}) {
  assert(typeof serial === 'string' && /^[\w.:-]+$/.test(serial), 'A discovered Android serial is required for IME capture');
  assert(typeof expectedPid === 'string' && /^[1-9]\d*$/.test(expectedPid), 'The original Jolene process PID is required for IME capture');
  const adb = (args, timeout = 15_000) => run('adb', ['-s', serial, ...args], {
    encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
  });
  let phase = 'before-pid-read';
  const requireSameApp = async (stage) => {
    phase = `${stage}-pid-read`;
    const { stdout: pid } = await adb(['shell', 'pidof', fixturePackage], 5_000);
    phase = `${stage}-pid-check`;
    assert.equal(pid.trim(), expectedPid, 'Jolene stopped or restarted during IME evidence collection');
    phase = `${stage}-window-read`;
    const { stdout: windows } = await adb(['shell', 'dumpsys', '-t', '10', 'window']);
    phase = `${stage}-window-check`;
    requireAppWindow(windows);
  };
  try {
    await requireSameApp('before');
    let stdout;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        phase = 'ime-read';
        ({ stdout } = await adb(['shell', dumpCommand]));
      } catch (error) {
        phase = 'collection-failure-record';
        await record({ phase: 'collection-failed', attempt, code: error.code ?? null,
          killed: error.killed === true, signal: error.signal ?? null,
          partialBytes: Buffer.byteLength(error.stdout ?? '') });
        phase = 'ime-read';
        // Run 36635052652: adbd write failed/offline, exit 255 with an
        // interrupted dump; host-20 reconnected 0.5s later. Neither a host
        // timeout nor an output-buffer overflow is eligible for this retry.
        const interrupted = error.code === 255 && error.killed === false
          && error.signal === null && error.stderr === ''
          && typeof error.stdout === 'string'
          && error.stdout.startsWith('Current Input Method Manager state:')
          && !error.stdout.endsWith(completion) && !dumpError.test(error.stdout);
        if (attempt !== 1 || !interrupted) throw error;
        phase = 'reconnect-wait';
        await adb(['wait-for-device'], 5_000);
        await requireSameApp('reconnected');
        phase = 'transport-recovery-record';
        await record({ phase: 'transport-recovered-same-app', attempt, pid: expectedPid });
        continue;
      }
      // The marker is written only after dumpsys has exited successfully.
      // Never accept error.stdout, a timeout, or a plausible truncated state.
      phase = 'ime-marker-check';
      assert(typeof stdout === 'string' && stdout.endsWith(completion), 'IME evidence is incomplete');
      const dump = stdout.slice(0, -completion.length);
      phase = 'ime-header-check';
      assert(dump.startsWith('Current Input Method Manager state:'), 'IME evidence has no Android service header');
      phase = 'ime-history-check';
      assert(/^\s*mStartInputHistory:/m.test(dump), 'IME evidence has no history boundary');
      phase = 'ime-service-check';
      assert(!dumpError.test(dump), 'Android IME dump reported an error');
      phase = 'ime-visibility-check';
      currentImeShown(dump);
      await requireSameApp('after');
      phase = 'complete-record';
      await record({ phase: 'complete', attempt, pid: expectedPid, bytes: Buffer.byteLength(dump) });
      return dump;
    }
  } catch (error) {
    throw new Error(`Required IME evidence collection failed via adb on ${serial} [phase=${phase}; code=${diagnosticCode(error)}]`, { cause: error });
  }
}

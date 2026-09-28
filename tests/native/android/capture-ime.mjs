import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execute = promisify(execFile);

/** Collect the required evidence through the ADB CLI, independently of the
 * Playwright Android protocol used for keyboard assertions. No fallback/retry. */
export async function captureIme(serial, run = execute) {
  assert(typeof serial === 'string' && /^[\w.:-]+$/.test(serial), 'A discovered Android serial is required for IME capture');
  try {
    const { stdout } = await run('adb', ['-s', serial, 'shell', 'dumpsys', 'input_method'], {
      encoding: 'utf8', timeout: 10_000, maxBuffer: 4 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    throw new Error(`Required IME evidence collection failed via adb on ${serial}`, { cause: error });
  }
}

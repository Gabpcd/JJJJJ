import assert from 'node:assert/strict';
import test from 'node:test';
import { captureIme } from './capture-ime.mjs';

test('IME evidence uses exactly the discovered serial and preserves the complete dump', async () => {
  const calls = [];
  const dump = 'Current Input Method Manager state:\n  mInputShown=true\n';
  const result = await captureIme('emulator-fixture-5782', async (...args) => {
    calls.push(args);
    return { stdout: dump, stderr: '' };
  });
  assert.equal(result, dump);
  assert.deepEqual(calls, [[
    'adb', ['-s', 'emulator-fixture-5782', 'shell', 'dumpsys', 'input_method'],
    { encoding: 'utf8', timeout: 10_000, maxBuffer: 4 * 1024 * 1024 },
  ]]);
});

test('ADB collection failure aborts once with context and original cause, without retry or empty evidence', async () => {
  let calls = 0;
  const cause = Object.assign(new Error('device offline'), { code: 1, stderr: 'adb: device offline' });
  await assert.rejects(captureIme('emulator-fixture-5782', async () => {
    calls++;
    throw cause;
  }), error => {
    assert.match(error.message, /Required IME evidence collection failed via adb on emulator-fixture-5782/);
    assert.equal(error.cause, cause);
    return true;
  });
  assert.equal(calls, 1);
});

test('Missing serial never runs adb against an arbitrary connected device', async () => {
  let calls = 0;
  await assert.rejects(captureIme('', async () => { calls++; }), /discovered Android serial/);
  assert.equal(calls, 0);
});

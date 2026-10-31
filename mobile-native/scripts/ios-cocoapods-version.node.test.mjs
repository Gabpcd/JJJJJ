import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { readCocoaPodsVersion } from './ios-compiled-client.mjs';

const ok = { stdout: '1.16.2\n', stderr: '', code: 0, signal: null, expired: false, durationMs: 80001 };
for (const [name, result, succeeds] of [
  ['cold successful probe', ok, true],
  ['timeout even with a printed version', { ...ok, expired: true, durationMs: 180001 }, false],
  ['nonzero exit', { ...ok, code: 1 }, false],
  ['killed process', { ...ok, signal: 'SIGKILL' }, false],
  ['empty version', { ...ok, stdout: '' }, false],
]) test(name, async () => {
  const output = mkdtempSync(join(tmpdir(), 'jolene-pod-probe-'));
  const calls = [];
  try {
    const promise = readCocoaPodsVersion({ output, run: async (...args) => { calls.push(args); return result; } });
    if (succeeds) assert.equal(await promise, '1.16.2');
    else await assert.rejects(promise, /CocoaPods échouée/);
    assert.equal(calls.length, 1, 'No blind retry or installation of a different tool');
    assert.deepEqual(calls[0].slice(0, 2), ['pod', ['--version']]);
    assert.equal(calls[0][2].timeout, 180000);
    assert.equal(calls[0][2].allowFailure, true);
    assert.equal(calls[0][2].logfile, 'compiled-cocoapods-version.log');
    const receipt = JSON.parse(readFileSync(join(output, 'compiled-cocoapods-version-command.json')));
    assert.deepEqual(receipt, { command: ['pod', '--version'], timeoutMs: 180000,
      code: result.code, signal: result.signal, expired: result.expired, durationMs: result.durationMs });
  } finally { rmSync(output, { recursive: true, force: true }); }
});

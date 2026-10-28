import test from 'node:test';
import assert from 'node:assert/strict';
import { nativeDiagnosticLine } from './ios-native-event-stream.mjs';
import { verifyContractsHomeEvidence } from './contracts-home-oracle.mjs';

test('native stream preserves the JSON bytes in the RN console envelope observed in e334', () => {
  const json = '{"sequence":6,"event":"native-change","length":1,"eventCount":1}';
  assert.equal(nativeDiagnosticLine(`2026-10-27 [info][tid:com.facebook.react.runtime.JavaScript] '[jolene-native-contract-input]', '${json}'`),
    `[jolene-native-contract-input] ${json}\n`);
  assert.equal(nativeDiagnosticLine(`[jolene-native-navigation] ${json}`), `[jolene-native-navigation] ${json}\n`);
});

test('native stream rejects wrapped, truncated, unknown or invalid JSON without repairing it', () => {
  for (const suffix of [' {"sequence":1,\n"event":"x"}', "', '{\"sequence\":1}", ' {broken}', ' {"sequence":1} suffix']) {
    assert.throws(() => nativeDiagnosticLine(`[jolene-native-navigation]${suffix}`));
  }
  assert.equal(nativeDiagnosticLine('unrelated system diagnostic'), null);
  assert.throws(() => nativeDiagnosticLine('[jolene-native-navigation] ' + 'x'.repeat(32_768)));
});

test('native envelope normalization retains the strict composite Home oracle', () => {
  const proof = { schemaVersion: 1, id: '12345678-1234-1234-1234-123456789abc', prefix: 'iphone-portrait',
    homePresses: 1, activations: 1, markers: [
      { stage: 'armed', atMs: 100, homeVisible: false, codeLength: 6 },
      { stage: 'home-visible', atMs: 120, homeVisible: true },
      { stage: 'activate', atMs: 130 },
      { stage: 'resumed', atMs: 160, homeVisible: false, codeLength: 0, consentEnabled: false, originalVisible: true },
    ] };
  const event = (stream, sequence, atMs, rest) => nativeDiagnosticLine(
    `'[jolene-native-${stream}]', '${JSON.stringify({ sequence, startedAtMs: 1, atMs, ...rest })}'`);
  const lines = [
    event('contract-input', 1, 90, { event: 'committed', length: 6, active: true }),
    event('navigation', 1, 105, { event: 'appState', detail: 'background' }),
    event('contract-input', 2, 106, { event: 'reset', reason: 'app-nonactive' }),
    event('navigation', 2, 140, { event: 'appState', detail: 'active' }),
    event('contract-input', 3, 141, { event: 'reset', reason: 'app-active' }),
    event('contract-input', 4, 145, { event: 'committed', length: 0, active: true }),
  ];
  assert.equal(verifyContractsHomeEvidence({ proof, metro: lines.join('') }).success, true);
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro: lines.filter((_, i) => i !== 1).join('') }));
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro: lines.slice(0, -1).join('') }));
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro: '' }));
});

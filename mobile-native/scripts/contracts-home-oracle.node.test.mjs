import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyContractsHomeEvidence } from './contracts-home-oracle.mjs';

function fixture() {
  const proof = { schemaVersion: 1, id: 'b004cc00-97c5-4eab-80e8-2d74930485ed', prefix: 'ipad-paysage', homePresses: 1, activations: 1,
    markers: [{ stage: 'armed', atMs: 1000, homeVisible: false, codeLength: 6 },
      { stage: 'home-visible', atMs: 1200, homeVisible: true }, { stage: 'activate', atMs: 1300 },
      { stage: 'resumed', atMs: 1500, homeVisible: false, codeLength: 0, consentEnabled: false, originalVisible: true }] };
  const entries = [
    ['contract-input', { sequence: 8, startedAtMs: 500, atMs: 950, event: 'committed', length: 6, active: true }],
    ['navigation', { sequence: 20, startedAtMs: 100, atMs: 1020, event: 'appState', detail: 'inactive' }],
    ['contract-input', { sequence: 9, startedAtMs: 500, atMs: 1021, event: 'reset', reason: 'app-nonactive' }],
    ['contract-input', { sequence: 10, startedAtMs: 500, atMs: 1022, event: 'committed', length: 0, active: false }],
    ['navigation', { sequence: 21, startedAtMs: 100, atMs: 1100, event: 'appState', detail: 'background' }],
    ['contract-input', { sequence: 11, startedAtMs: 500, atMs: 1101, event: 'reset', reason: 'app-nonactive' }],
    ['navigation', { sequence: 22, startedAtMs: 100, atMs: 1320, event: 'appState', detail: 'active' }],
    ['contract-input', { sequence: 12, startedAtMs: 500, atMs: 1321, event: 'reset', reason: 'app-active' }],
    ['contract-input', { sequence: 13, startedAtMs: 500, atMs: 1322, event: 'committed', length: 0, active: true }],
  ];
  return { proof, entries };
}
function verdict({ proof, entries }) {
  return verifyContractsHomeEvidence({ proof, metro: entries.map(([stream, entry]) =>
    ` LOG [jolene-native-${stream}] ${JSON.stringify(entry)}`).join('\n') });
}
function log(entries) {
  return entries.map(([stream, entry]) => `[jolene-native-${stream}] ${JSON.stringify(entry)}`).join('\n');
}
test('requires real Home UI plus one background/active transition and purge in the same input stream', () => {
  const result = verdict(fixture()); assert.equal(result.success, true);
  assert.equal(result.committedBeforeHome, 6); assert.equal(result.committedAfterResume, 0);
  assert.equal(result.backgroundObserved, true);
});
test('inactive and purge without background are not enough', () => {
  const input = fixture(); input.entries[4][1].detail = 'inactive';
  assert.throws(() => verdict(input), /background absent/);
});
test('background outside the observed Home cannot reuse an older passage', () => {
  const input = fixture(); input.entries[1][1].atMs = 960; input.entries[4][1].atMs = 980;
  assert.throws(() => verdict(input), /background absent ou hors/);
});
test('active before background is rejected even when the UI proof claims resume', () => {
  const input = fixture(); input.entries[4][1].detail = 'active'; input.entries[6][1].detail = 'background';
  assert.throws(() => verdict(input), /background absent ou hors|reprise active/);
});
test('a fresh input instance or a reset sequence cannot stand in for the original one', () => {
  for (const key of ['startedAtMs', 'sequence']) {
    const input = fixture(); input.entries[8][1][key] = key === 'startedAtMs' ? 1250 : 1;
    assert.throws(() => verdict(input), /flux saisie interrompu ou réinitialisé/);
  }
});
test('navigation runtime reset is rejected', () => {
  const input = fixture(); input.entries[6][1].sequence = 1; input.entries[6][1].startedAtMs = 1200;
  assert.throws(() => verdict(input), /flux navigation interrompu ou réinitialisé/);
});
test('pre-resume zero alone is insufficient; a zero committed after active is required', () => {
  const input = fixture(); input.entries.pop();
  assert.throws(() => verdict(input), /purge à zéro non confirmée/);
});
test('missing six committed digits and retained code fail', () => {
  const missing = fixture(); missing.entries[0][1].length = 2;
  assert.throws(() => verdict(missing), /six chiffres/);
  const retained = fixture(); retained.entries[8][1].length = 6;
  assert.throws(() => verdict(retained), /saisie intervenue/);
});
test('Home already visible, missing final consent check and repeated Home fail', () => {
  const visible = fixture(); visible.proof.markers[0].homeVisible = true;
  assert.throws(() => verdict(visible), /oracles visuels/);
  const consent = fixture(); consent.proof.markers[3].consentEnabled = true;
  assert.throws(() => verdict(consent), /oracles visuels/);
  const repeat = fixture(); repeat.proof.homePresses = 2;
  assert.throws(() => verdict(repeat), /marqueurs XCTest/);
});
test('old non-correlatable logs, reordered markers and a missing final marker fail closed', () => {
  const old = fixture(); delete old.entries[0][1].atMs;
  assert.throws(() => verdict(old), /événement non horodaté/);
  const reordered = fixture(); reordered.proof.markers.reverse();
  assert.throws(() => verdict(reordered), /ordre des marqueurs/);
  const incomplete = fixture(); incomplete.proof.markers.pop();
  assert.throws(() => verdict(incomplete), /marqueurs XCTest/);
});

test('a lost native log burst does not discard the complete Metro sequence and matching UI evidence', () => {
  const { proof, entries } = fixture();
  const early = ['contract-input', { sequence: 7, startedAtMs: 500, atMs: 900, event: 'focus', count: 1 }];
  const metro = log([early, ...entries]);
  // Unified Logging lost the six-digit commit; retain only independent native
  // witnesses before Home, background/active, and the final cleared commit.
  const native = log([early, entries[4], entries[6], entries[8]]);
  const result = verifyContractsHomeEvidence({ proof, metro, native });
  assert.equal(result.success, true);
  assert.equal(result.nativeProcessStreamMatched, true);
  assert.equal(result.canonicalStream, 'metro');
  assert.equal(result.committedBeforeHome, 6);
  assert.equal(result.committedAfterResume, 0);
});

test('native data cannot fill a gap or rescue an invalid Metro/UI proof', () => {
  const { proof, entries } = fixture();
  const native = log(entries);
  for (const remove of [0, 2, 4, 6, 8]) {
    assert.throws(() => verifyContractsHomeEvidence({ proof,
      metro: log(entries.filter((_, index) => index !== remove)), native }));
  }
  const altered = structuredClone(entries); altered[0][1].length = 2;
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro: log(altered), native }), /six chiffres/);
  const noHome = structuredClone(proof); noHome.markers[1].homeVisible = false;
  assert.throws(() => verifyContractsHomeEvidence({ proof: noHome, metro: log(entries), native }), /oracles visuels/);
});

test('native provenance must match the same input instance and both lifecycle transitions', () => {
  const { proof, entries } = fixture();
  const metro = log(entries);
  for (const remove of [0, 4, 6, 8]) {
    assert.throws(() => verifyContractsHomeEvidence({ proof, metro,
      native: log(entries.filter((_, index) => index !== remove)) }), /origine native/);
  }
  const changed = structuredClone(entries); changed[0][1].startedAtMs = 501;
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro, native: log(changed) }), /flux natif distinct/);
  const conflicting = structuredClone(entries); conflicting[0][1].length = 2;
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro, native: log(conflicting) }), /flux natif distinct/);
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro, native: '' }), /origine native/);
});

test('duplicated events in either transport cannot count as an independent native witness', () => {
  const { proof, entries } = fixture();
  const metro = log(entries);
  const duplicate = log([entries[0], ...entries]);
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro, native: duplicate }), /flux natif distinct/);
  assert.throws(() => verifyContractsHomeEvidence({ proof, metro: duplicate, native: metro }), /événement Metro dupliqué/);
});

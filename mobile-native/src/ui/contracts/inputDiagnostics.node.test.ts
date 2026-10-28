import test from 'node:test';
import assert from 'node:assert/strict';
import { createContractInputDiagnostics, type ContractCodeResetReason } from './inputDiagnostics';

function collect(gatewayMode = 'demo', appMode: string | undefined = 'demo', flag: string | undefined = '1') {
  const entries: unknown[] = [];
  const diagnostics = createContractInputDiagnostics({ gatewayMode, appMode, flag, emit: entry => entries.push(entry) });
  return { entries, diagnostics };
}
function exercise(diagnostics: ReturnType<typeof createContractInputDiagnostics>) {
  diagnostics.focus(); diagnostics.keyPress(1); diagnostics.selection(6, 6);
  diagnostics.nativeChange(6, 8); diagnostics.textChange(6); diagnostics.committed(6, true, false); diagnostics.reset('submit'); diagnostics.blur();
}
test('STAGING and every missing demo opt-in export no input diagnostics', () => {
  for (const gateway of ['demo', 'staging']) for (const mode of ['demo', 'staging', undefined]) for (const flag of ['1', '0', undefined]) {
    if (gateway === 'demo' && mode === 'demo' && flag === '1') continue;
    // Construct directly: default parameters must not turn undefined into demo.
    const entries: unknown[] = [];
    exercise(createContractInputDiagnostics({ gatewayMode: gateway, appMode: mode, flag, emit: entry => entries.push(entry) }));
    assert.deepEqual(entries, [], `${gateway}/${mode}/${flag}`);
  }
});
test('demo emits only fixed event names, lengths, counts, reset reasons and timing', () => {
  const { entries, diagnostics } = collect(); exercise(diagnostics);
  assert.equal(entries.length, 8);
  const sanitized = entries.map(entry => {
    const { sequence, elapsedMs, startedAtMs, atMs, ...fields } = entry as Record<string, unknown>;
    assert.equal(typeof sequence, 'number'); assert.equal(typeof elapsedMs, 'number');
    assert.equal(typeof startedAtMs, 'number'); assert.equal(typeof atMs, 'number');
    assert.ok((atMs as number) >= (startedAtMs as number)); return fields;
  });
  assert.deepEqual(sanitized, [{ event: 'focus', count: 1 }, { event: 'key-press', count: 1, length: 1 },
    { event: 'selection', count: 1, start: 6, end: 6 }, { event: 'native-change', length: 6, eventCount: 8 },
    { event: 'text-change', length: 6 }, { event: 'committed', length: 6, active: true, blocked: false },
    { event: 'reset', reason: 'submit' }, { event: 'blur', count: 1 }]);
});
test('runtime guards discard arbitrary strings and invalid numeric inputs', () => {
  const { entries, diagnostics } = collect();
  const canary = 'private-canary-not-an-otp';
  diagnostics.nativeChange(6, canary as unknown as number);
  diagnostics.textChange(canary as unknown as number);
  diagnostics.committed(Number.NaN); diagnostics.textChange(-1); diagnostics.textChange(1.5);
  diagnostics.reset(canary as ContractCodeResetReason);
  diagnostics.keyPress(canary as unknown as number); diagnostics.keyPress(Infinity);
  diagnostics.selection(canary as unknown as number, 0); diagnostics.selection(1, 0);
  diagnostics.selection(0, 1025); diagnostics.selection(0.5, 1);
  diagnostics.committed(1, true, canary as unknown as boolean);
  assert.deepEqual(entries, []);
});
test('diagnostics are bounded and a failed sink cannot break input actions', () => {
  const { entries, diagnostics } = collect();
  for (let i = 0; i < 200; i++) diagnostics.nativeChange(1, i);
  assert.equal(entries.length, 128);
  const failing = createContractInputDiagnostics({ gatewayMode: 'demo', appMode: 'demo', flag: '1', emit: () => { throw new Error('sink'); } });
  assert.doesNotThrow(() => exercise(failing));
});

test('committed visibility is observed without accepting arbitrary state strings', () => {
  const { entries, diagnostics } = collect();
  diagnostics.committed(6, true); diagnostics.committed(0, false); diagnostics.committed(0, true);
  const observed = entries as Array<{ length: number; active: boolean; startedAtMs: number }>;
  assert.deepEqual(observed.map(({ length, active }) => ({ length, active })), [
    { length: 6, active: true }, { length: 0, active: false }, { length: 0, active: true },
  ]);
  assert.ok(observed.every(entry => entry.startedAtMs === observed[0].startedAtMs));
  diagnostics.committed(0, 'private-state-canary' as unknown as boolean);
  assert.equal(entries.length, 3);
});

test('six attempted keys remain distinguishable from one accepted native change', () => {
  const { entries, diagnostics } = collect();
  diagnostics.focus(); diagnostics.committed(0, true, false);
  for (let i = 0; i < 6; i++) diagnostics.keyPress(1);
  diagnostics.nativeChange(1, 1); diagnostics.textChange(1); diagnostics.selection(1, 1);
  diagnostics.committed(1, true, false);
  const observed = entries as Array<{ event: string; count?: number; length?: number; blocked?: boolean }>;
  assert.deepEqual(observed.filter(entry => entry.event === 'key-press').map(entry => entry.count), [1, 2, 3, 4, 5, 6]);
  assert.equal(observed.filter(entry => entry.event === 'native-change').length, 1);
  assert.equal(observed.filter(entry => entry.event === 'blur').length, 0);
  assert.deepEqual(observed.filter(entry => entry.event === 'committed').map(entry => [entry.length, entry.blocked]), [[0, false], [1, false]]);
});

test('focus, blur and selection counters are independent and bounded by the shared stream cap', () => {
  const { entries, diagnostics } = collect();
  for (let i = 0; i < 100; i++) { diagnostics.focus(); diagnostics.selection(0, 0); diagnostics.blur(); }
  const observed = entries as Array<{ event: string; count: number; sequence: number }>;
  assert.equal(observed.length, 128);
  for (const event of ['focus', 'selection', 'blur']) {
    const counts = observed.filter(entry => entry.event === event).map(entry => entry.count);
    assert.deepEqual(counts, counts.map((_, index) => index + 1));
  }
  assert.deepEqual(observed.map(entry => entry.sequence), observed.map((_, index) => index + 1));
});

test('committed blocked state preserves the boolean used by editable', () => {
  const { entries, diagnostics } = collect();
  diagnostics.committed(1, true, false); diagnostics.committed(1, true, true); diagnostics.committed(0, false, true);
  assert.deepEqual((entries as Array<{ active: boolean; blocked: boolean }>).map(({ active, blocked }) => ({ active, blocked })), [
    { active: true, blocked: false }, { active: true, blocked: true }, { active: false, blocked: true },
  ]);
});

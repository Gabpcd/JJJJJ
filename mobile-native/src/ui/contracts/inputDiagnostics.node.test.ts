import test from 'node:test';
import assert from 'node:assert/strict';
import { createContractInputDiagnostics, type ContractCodeResetReason } from './inputDiagnostics';

function collect(gatewayMode = 'demo', appMode: string | undefined = 'demo', flag: string | undefined = '1') {
  const entries: unknown[] = [];
  const diagnostics = createContractInputDiagnostics({ gatewayMode, appMode, flag, emit: entry => entries.push(entry) });
  return { entries, diagnostics };
}
function exercise(diagnostics: ReturnType<typeof createContractInputDiagnostics>) {
  diagnostics.nativeChange(6, 8); diagnostics.textChange(6); diagnostics.committed(6); diagnostics.reset('submit');
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
  assert.equal(entries.length, 4);
  const sanitized = entries.map(entry => {
    const { sequence, elapsedMs, startedAtMs, atMs, ...fields } = entry as Record<string, unknown>;
    assert.equal(typeof sequence, 'number'); assert.equal(typeof elapsedMs, 'number');
    assert.equal(typeof startedAtMs, 'number'); assert.equal(typeof atMs, 'number');
    assert.ok((atMs as number) >= (startedAtMs as number)); return fields;
  });
  assert.deepEqual(sanitized, [{ event: 'native-change', length: 6, eventCount: 8 }, { event: 'text-change', length: 6 },
    { event: 'committed', length: 6 }, { event: 'reset', reason: 'submit' }]);
});
test('runtime guards discard arbitrary strings and invalid numeric inputs', () => {
  const { entries, diagnostics } = collect();
  const canary = 'private-canary-not-an-otp';
  diagnostics.nativeChange(6, canary as unknown as number);
  diagnostics.textChange(canary as unknown as number);
  diagnostics.committed(Number.NaN); diagnostics.textChange(-1); diagnostics.textChange(1.5);
  diagnostics.reset(canary as ContractCodeResetReason);
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

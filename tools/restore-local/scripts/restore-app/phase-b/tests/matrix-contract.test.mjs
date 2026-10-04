import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { CASE_IDS, PROJECT_IDS, assertRestoreMatrix } from '../matrix-contract.mjs';

function fixture(side = 'target') {
  const cases = side === 'source' ? CASE_IDS.slice(0, 2) : CASE_IDS;
  const projects = side === 'source' ? ['ordinateur'] : PROJECT_IDS;
  const specs = cases.map(title => ({ title, tests: projects.map(projectName => ({ projectName })) }));
  return { raw: { suites: [{ specs }] }, projected: specs.flatMap(spec => spec.tests.map(result => ({
    file: 'e2e/restore-app.spec.ts', line: 86, column: 1, project: result.projectName,
    expectedStatus: 'passed', outcome: 'expected', attempts: [{ retry: 0, status: 'passed' }],
  }))) };
}
const refused = action => assert.throws(action, error => error.message === 'RESTORE_REPORT_MATRIX');

test('target requires and identifies all 25 distinct case/format pairs even with shared source lines', () => {
  const { raw, projected } = fixture();
  const identified = assertRestoreMatrix(raw, projected, 'target');
  assert.equal(identified.length, 25);
  assert.equal(new Set(identified.map(result => result.caseId + ':' + result.project)).size, 25);
  assert.deepEqual([...new Set(identified.map(result => result.caseId))], CASE_IDS);
});

test('duplicate replacing a missing pair is refused despite 25 passed records', () => {
  const { raw, projected } = fixture();
  raw.suites[0].specs[4].tests[4].projectName = 'iphone';
  projected[24].project = 'iphone';
  assert.equal(projected.length, 25);
  refused(() => assertRestoreMatrix(raw, projected, 'target'));
});

test('repeated actor with another actor missing is refused despite 25 records and shared lines', () => {
  const { raw, projected } = fixture();
  raw.suites[0].specs[1].title = CASE_IDS[0];
  refused(() => assertRestoreMatrix(raw, projected, 'target'));
});

test('unknown case and format refuse with constant error and no private canary', () => {
  const canary = randomBytes(24).toString('hex');
  for (const kind of ['title', 'project']) {
    const { raw, projected } = fixture();
    if (kind === 'title') raw.suites[0].specs[0].title = canary;
    else { raw.suites[0].specs[0].tests[0].projectName = canary; projected[0].project = canary; }
    let error;
    try { assertRestoreMatrix(raw, projected, 'target'); } catch (caught) { error = caught; }
    assert.equal(error?.message, 'RESTORE_REPORT_MATRIX');
    assert.equal(String(error).includes(canary), false);
    assert.equal(JSON.stringify(error).includes(canary), false);
  }
});

test('missing pair and raw/projected project disagreement each refuse', () => {
  const missing = fixture(); missing.raw.suites[0].specs[0].tests.pop(); missing.projected.splice(4, 1);
  refused(() => assertRestoreMatrix(missing.raw, missing.projected, 'target'));
  const mismatch = fixture(); mismatch.projected[0].project = 'ordinateur';
  refused(() => assertRestoreMatrix(mismatch.raw, mismatch.projected, 'target'));
});

test('source accepts exactly the two owners on desktop, never a duplicate or target pair', () => {
  const { raw, projected } = fixture('source');
  assert.deepEqual(assertRestoreMatrix(raw, projected, 'source').map(result => result.caseId), CASE_IDS.slice(0, 2));
  raw.suites[0].specs[1].title = CASE_IDS[0];
  refused(() => assertRestoreMatrix(raw, projected, 'source'));
  const wrong = fixture('source'); wrong.raw.suites[0].specs[1].tests[0].projectName = 'iphone'; wrong.projected[1].project = 'iphone';
  refused(() => assertRestoreMatrix(wrong.raw, wrong.projected, 'source'));
});

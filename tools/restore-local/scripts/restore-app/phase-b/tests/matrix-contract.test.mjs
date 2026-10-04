import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { CASE_IDS, PROJECT_IDS, assertRestoreMatrix } from '../matrix-contract.mjs';
import { browserArguments } from '../browser-entry.mjs';

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

// Actual Playwright 1.58.2 _grepTitleWithTags shape for the pinned source project.
const fullSourceTitle = caseId => `ordinateur restore-app.spec.ts ${caseId}`;
function selectedBySource(titles) {
  const args = browserArguments('source');
  const selectors = args.filter(value => value.startsWith('--grep='));
  assert.equal(selectors.length, 1);
  const expression = new RegExp(selectors[0].slice('--grep='.length), 'gi');
  return titles.filter(title => { expression.lastIndex = 0; return expression.test(title); });
}

test('source CLI selects the two owners from complete Playwright titles', () => {
  const args = browserArguments('source');
  assert.deepEqual(args.filter(value => value.startsWith('--project=')), ['--project=ordinateur']);
  assert.deepEqual(selectedBySource(CASE_IDS.map(fullSourceTitle)), CASE_IDS.slice(0, 2).map(fullSourceTitle));
  const { raw, projected } = fixture('source');
  assert.equal(assertRestoreMatrix(raw, projected, 'source').length, 2);
});

test('source CLI rejects extra owner-like titles and target retains all 25 cases', () => {
  const extra = ['RESTORE_OWNER_ADMIN', 'RESTORE_OWNER_SS', 'NOT_RESTORE_OWNER_S',
    'RESTORE_OWNER_S_EXTRA', 'RESTORE_OWNER_S extra', ...CASE_IDS.slice(2)];
  assert.deepEqual(selectedBySource(extra.map(fullSourceTitle)), []);
  const args = browserArguments('target');
  assert.equal(args.some(value => value.startsWith('--grep=') || value.startsWith('--project=')), false);
  const { raw, projected } = fixture('target');
  assert.equal(assertRestoreMatrix(raw, projected, 'target').length, 25);
  assert.throws(() => browserArguments('other'), error => error.code === 'B_BROWSER');
});

test('source matrix still refuses an empty or surplus selection', () => {
  refused(() => assertRestoreMatrix({ suites: [{ specs: [] }] }, [], 'source'));
  const { raw, projected } = fixture('source');
  raw.suites[0].specs.push({ title: 'RESTORE_OTHER_S', tests: [{ projectName: 'ordinateur' }] });
  projected.push({ ...projected[0] });
  refused(() => assertRestoreMatrix(raw, projected, 'source'));
});

import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtemp, mkdir, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import ts from 'typescript';
import { projectSignupFinalAudit, signupAuditRefusalDiagnostic } from '../../scripts/ci/signup-final-audit-public.mjs';
import { projectReport, runPublicPlaywright } from '../../scripts/ci/run-playwright-public.mjs';

const FILE = 'e2e/non-regression/signup-series-c-audit.spec.ts';
const ROOT = path.resolve(import.meta.dirname, '../..');
const canary = `private-${randomBytes(24).toString('hex')}@example.invalid`;
const context = { phase: 'series-c-ios', file: FILE };
const attachment = (name, value) => ({ name, contentType: 'application/json', body: Buffer.from(JSON.stringify(value)).toString('base64') });

function fixture(role = 'soignant', phase = context.phase) {
  const routeCount = role === 'soignant' ? 40 : 39;
  const viewports = phase === 'series-c-ios' ? ['375x667', '390x844', '440x956'] : ['412x915'];
  const audit = viewports.flatMap(viewport => Array.from({ length: routeCount }, (_, routeIndex) => ({
    route: `/${canary}/${routeIndex}`, viewport, consoleErrors: [], pageErrors: [], apiErrors: [],
    finalUrl: canary, inputsBelow16px: [{ label: canary }], tinyTexts: [{ text: canary }],
    privateHeaders: { Authorization: `Bearer ${canary}` },
  })));
  const roleHttp = { truncated: false, events: [] };
  const transport = [];
  function result() {
    return { status: 'failed', retry: 0, duration: 10, errors: [{ message: canary }],
      attachments: [attachment(`audit-compte-neuf-${role}.json`, audit),
        attachment(`audit-compte-neuf-role-http-${role}.json`, roleHttp),
        attachment(`audit-compte-neuf-transport-${role}.json`, transport),
        { name: canary, body: canary, path: `/private/${canary}`, contentType: 'text/plain' }],
    };
  }
  return { role, phase, routeCount, audit, roleHttp, transport, result };
}

function project(f) {
  const projected = projectSignupFinalAudit(f.result(), { ...context, phase: f.phase });
  const bytes = JSON.stringify(projected);
  assert.equal(bytes.includes(canary), false);
  assert.doesNotMatch(bytes, /https?:|Bearer|Authorization|privateHeaders|timestamp|requestId|documentId/);
  return projected;
}

test('publishes counts and closed categories per route/viewport, never private contents', () => {
  const f = fixture();
  f.audit[42].consoleErrors = [
    `${canary} :: WebSocket connection to wss://invalid/${canary} failed`,
    `${canary} HTTP/2 Error: NO_ERROR`, `${canary} Failed to load resource`,
    `${canary} Failed to fetch`, `${canary} Content Security Policy`, canary,
  ];
  f.audit[42].pageErrors = [`${canary} Load failed`, canary];
  f.audit[42].apiErrors = [
    { status: 503, path: '/rest/v1/rpc/fn_get_my_role', body: canary },
    { status: 503, path: '/rest/v1/rpc/fn_get_my_role' },
    { status: 401, path: `/unknown/${canary}?token=${canary}` },
  ];
  assert.deepEqual(project(f), { schemaVersion: 1, role: 'soignant', routeCount: 40, viewportCount: 3, inspectedCount: 120,
    rows: [{ routeIndex: 2, viewportIndex: 1, consoleCount: 6, pageErrorCount: 2, apiErrorCount: 3,
      consoleCategories: ['WEBSOCKET', 'HTTP2_NO_ERROR', 'RESOURCE_LOAD', 'FETCH_FAILED', 'CSP', 'OTHER'].map(category => ({ category, count: 1 })),
      pageCategories: [{ category: 'FETCH_FAILED', count: 1 }, { category: 'OTHER', count: 1 }],
      apiResponses: [{ endpoint: 'ROLE_RPC', status: 503, count: 2 }, { endpoint: 'OTHER', status: 401, count: 1 }],
    }], roleRpcFailures: [], websocketErrors: [],
  });
});

test('endpoint names are fixed enums and the two role/viewport matrices are bounded', () => {
  const f = fixture('etab', 'series-c-android');
  const paths = ['/rest/v1/rpc/fn_messages_non_lus', '/rest/v1/rpc/fn_private', '/rest/v1/private_table',
    '/functions/v1/private-function', '/auth/v1/token', '/storage/v1/object/private', `/unknown/${canary}`];
  f.audit[38].apiErrors = paths.map(path => ({ status: 403, path }));
  const actual = project(f);
  assert.equal(actual.inspectedCount, 39);
  assert.equal(actual.rows[0].routeIndex, 38);
  assert.equal(actual.rows[0].viewportIndex, 0);
  assert.deepEqual(actual.rows[0].apiResponses.map(value => value.endpoint),
    ['UNREAD_MESSAGES_RPC', 'OTHER_RPC', 'REST_RESOURCE', 'EDGE_FUNCTION', 'AUTH', 'STORAGE', 'OTHER']);
});

test('keeps RPC provenance including unknown and never guesses the WS viewport', () => {
  const f = fixture();
  const event = { timestamp: canary, route: canary, requestId: canary, documentId: canary,
    navigationId: 43, matrixIndex: 2, phase: 'navigation', event: 'requestfailed', scope: 'previous-document',
    httpStatus: null, failureCode: 'CANCELLED_OR_ABORTED' };
  f.roleHttp.events = [event, { ...event, scope: 'current-document', failureCode: 'HTTP2_NO_ERROR' },
    { ...event, scope: 'unknown', failureCode: 'OTHER' },
    { ...event, event: 'response', scope: 'current-document', httpStatus: 503, failureCode: null }];
  f.transport.push({ timestamp: canary, route: canary, matrixIndex: 2, phase: 'settling',
    event: 'websocket-error', connectionAttempt: 1, subsequentAttempts: 0, httpStatus: 503 });
  const actual = project(f);
  assert.deepEqual(actual.roleRpcFailures.map(({ routeIndex, viewportIndex, scope }) => ({ routeIndex, viewportIndex, scope })),
    ['previous-document', 'current-document', 'unknown', 'current-document'].map(scope => ({ routeIndex: 2, viewportIndex: 1, scope })));
  assert.deepEqual(actual.websocketErrors, [{ routeIndex: 2, viewportIndex: null, event: 'websocket-error', phase: 'settling', status: 503, count: 1 }]);
});

test('ignores all attachments in unknown files/phases and unknown attachment names', () => {
  const f = fixture();
  assert.equal(projectSignupFinalAudit(f.result(), { ...context, file: 'e2e/private.spec.ts' }), undefined);
  assert.equal(projectSignupFinalAudit(f.result(), { ...context, phase: 'chromium' }), undefined);
  assert.equal(projectSignupFinalAudit({ attachments: [{ name: canary, body: canary, path: '/etc/passwd' }] }, context), undefined);
  assert.deepEqual(project(f).rows, []);
});

test('rejects known attachment files, duplicate/missing bodies, malformed or oversized data as a whole', () => {
  const changes = [
    result => { result.attachments[0].path = '/etc/passwd'; },
    result => { result.attachments.push(result.attachments[0]); },
    result => { result.attachments.splice(1, 1); },
    result => { result.attachments[0].contentType = 'text/plain'; },
    result => { result.attachments[0].body = canary; },
    result => { result.attachments[0].body = Buffer.from(`{${canary}`).toString('base64'); },
    result => { result.attachments[0].body = 'A'.repeat(12 * 1024 * 1024); },
  ];
  for (const change of changes) {
    const result = fixture().result(); change(result);
    assert.throws(() => projectSignupFinalAudit(result, context), /^Error: SIGNUP_AUDIT_REFUSED$/);
  }
});

test('rejects counters, indices, statuses and enum values outside their bounds', () => {
  const changes = [
    f => { f.audit.pop(); }, f => { f.audit[0].viewport = canary; },
    f => { f.audit[40].route = canary; }, f => { f.audit[0].consoleErrors = Array(257).fill(canary); },
    f => { f.audit[0].pageErrors = [canary.repeat(1000)]; },
    f => { f.audit[0].apiErrors = [{ status: 200, path: canary }]; },
    f => { f.roleHttp.truncated = true; },
    f => { f.roleHttp.events = Array(2049).fill({}); },
    ...['scope', 'phase', 'event', 'failureCode', 'httpStatus', 'navigationId', 'matrixIndex'].map(key => f => {
      f.roleHttp.events = [{ navigationId: 1, matrixIndex: 0, phase: 'inspection', event: 'requestfailed', scope: 'unknown', httpStatus: null, failureCode: 'OTHER', [key]: canary }];
    }),
    f => { f.roleHttp.events = [{ navigationId: 41, matrixIndex: 1, phase: 'inspection', event: 'requestfailed', scope: 'unknown', httpStatus: null, failureCode: 'OTHER' }]; },
    f => { f.transport.push({ matrixIndex: 40, phase: 'settling', event: 'websocket-error', connectionAttempt: 1, subsequentAttempts: 0, httpStatus: null }); },
    f => { f.transport.push({ matrixIndex: 0, phase: 'settling', event: canary, connectionAttempt: 1, subsequentAttempts: 0, httpStatus: null }); },
  ];
  for (const change of changes) {
    const f = fixture(); change(f);
    assert.throws(() => project(f), /^Error: SIGNUP_AUDIT_REFUSED$/);
  }
});

async function withReport(run) {
  const directory = await realpath(await mkdtemp(path.join(tmpdir(), 'jolene-signup-public-unit-')));
  const cwd = path.join(directory, 'repo');
  await mkdir(path.join(cwd, 'e2e/non-regression'), { recursive: true });
  await writeFile(path.join(cwd, FILE), '// known declaration\n');
  const f = fixture();
  const attempt = f.result();
  const testCase = { projectName: 'ios-webkit-audit', expectedStatus: 'passed', status: 'unexpected', results: [attempt] };
  const report = { config: { rootDir: path.join(cwd, 'e2e') }, errors: [],
    stats: { duration: 20, expected: 0, unexpected: 1, flaky: 0, skipped: 0 },
    suites: [{ specs: [{ file: 'non-regression/signup-series-c-audit.spec.ts', line: 1, column: 1, tests: [testCase] }] }],
  };
  try { await run({ directory, cwd, f, attempt, testCase, report }); }
  finally { await rm(directory, { recursive: true, force: true }); }
}

test('projects each retry separately and a passed retry remains a red phase', async () => withReport(async ({ directory, cwd, f, testCase, report }) => {
  f.audit[0].consoleErrors.push(canary);
  testCase.results[0] = f.result();
  testCase.results.push({ ...fixture().result(), status: 'passed', retry: 1, errors: [] });
  testCase.status = 'flaky'; report.stats.unexpected = 0; report.stats.flaky = 1;
  let output = '';
  const code = await runPublicPlaywright(['--phase', 'series-c-ios', '--', 'test'], {
    cwd, env: { RUNNER_TEMP: directory }, getSourceSha: () => 'a'.repeat(40), emit: value => { output += value; },
    launch: async context => {
      assert.ok(context.args.includes('--fail-on-flaky-tests'));
      await writeFile(context.env.PLAYWRIGHT_JSON_OUTPUT_FILE, JSON.stringify(report)); return 1;
    },
  });
  assert.equal(code, 1); assert.equal(output.includes(canary), false);
  const receipt = JSON.parse(output);
  assert.ok(receipt.codes.includes('FLAKY_TESTS'));
  assert.equal(receipt.tests[0].attempts[0].signupAudit.rows[0].consoleCount, 1);
  assert.deepEqual(receipt.tests[0].attempts[1].signupAudit.rows, []);
}));

test('an absent diagnostic preserves the failed attempt; a malformed known one refuses public projection', async () => withReport(async ({ cwd, attempt, report }) => {
  attempt.attachments = [];
  const projected = await projectReport(report, { ...context, cwd });
  assert.equal(projected.tests[0].attempts[0].code, 'TEST_FAILED');
  assert.equal(projected.counts.unexpected, 1);
  assert.equal(Object.hasOwn(projected.tests[0].attempts[0], 'signupAudit'), false);
  attempt.attachments = fixture().result().attachments;
  attempt.attachments[0].body = canary;
  await assert.rejects(projectReport(report, { ...context, cwd }), /^Error: SIGNUP_AUDIT_REFUSED$/);
}));

test('original runtime/API assertion and anti-flake controls remain present', async () => {
  const spec = await readFile(path.join(ROOT, FILE), 'utf8');
  assert.ok(spec.includes("expect.soft(results.filter(({ consoleErrors, pageErrors, apiErrors }) => (\n    consoleErrors.length > 0 || pageErrors.length > 0 || apiErrors.length > 0\n  )).map(({ route, viewport, consoleErrors, pageErrors, apiErrors }) => ({\n    route,\n    viewport,\n    consoleErrors,\n    pageErrors,\n    apiErrors,\n  })), `aucun écran du compte ${role} neuf ne doit lever d'erreur runtime ou API`).toEqual([]);"));
  const config = await readFile(path.join(ROOT, 'playwright.config.ts'), 'utf8');
  assert.ok(config.includes('failOnFlakyTests: IS_CI'));
});

test('projection schema matches unique source routes and real viewports via TypeScript AST only', async () => {
  async function source(relative, kind = ts.ScriptKind.TS) {
    return ts.createSourceFile(relative, await readFile(path.join(ROOT, relative), 'utf8'), ts.ScriptTarget.Latest, true, kind);
  }
  function initializer(tree, name) {
    const found = [];
    const visit = node => {
      if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === name) found.push(node.initializer);
      ts.forEachChild(node, visit);
    };
    visit(tree); assert.equal(found.length, 1, name);
    let value = found[0];
    while (ts.isAsExpression(value) || ts.isParenthesizedExpression(value)) value = value.expression;
    return value;
  }
  function strings(value) {
    assert.ok(ts.isArrayLiteralExpression(value));
    return value.elements.map(element => { assert.ok(ts.isStringLiteral(element)); return element.text; });
  }
  function numbers(value) {
    assert.ok(ts.isObjectLiteralExpression(value));
    return Object.fromEntries(value.properties.map(property => {
      assert.ok(ts.isPropertyAssignment(property) && ts.isIdentifier(property.name) && ts.isNumericLiteral(property.initializer));
      return [property.name.text, Number(property.initializer.text)];
    }));
  }
  function viewports(value) {
    assert.ok(ts.isArrayLiteralExpression(value));
    return value.elements.map(element => {
      assert.ok(ts.isObjectLiteralExpression(element));
      const dimensions = {};
      for (const property of element.properties) {
        assert.ok(ts.isPropertyAssignment(property) && ts.isIdentifier(property.name));
        if (['width', 'height'].includes(property.name.text)) {
          assert.ok(ts.isNumericLiteral(property.initializer));
          dimensions[property.name.text] = Number(property.initializer.text);
        }
      }
      assert.ok(dimensions.width > 0 && dimensions.height > 0);
      return `${dimensions.width}x${dimensions.height}`;
    });
  }
  const routes = await source('e2e/helpers/ios-series-c-routes.ts');
  const spec = await source(FILE);
  const helper = await source('scripts/ci/signup-final-audit-public.mjs', ts.ScriptKind.JS);
  const counts = {};
  for (const [role, declaration] of [['soignant', 'ROUTES_SOIGNANT'], ['etab', 'ROUTES_ETABLISSEMENT']]) {
    const matrix = strings(initializer(routes, declaration));
    assert.equal(new Set(matrix).size, matrix.length, 'route ordinals require unique routes');
    counts[role] = matrix.length;
  }
  assert.deepEqual(numbers(initializer(helper, 'ROLES')), counts);
  assert.deepEqual(counts, { soignant: 40, etab: 39 });
  const choice = initializer(helper, 'viewports');
  assert.ok(ts.isConditionalExpression(choice) && ts.isBinaryExpression(choice.condition));
  assert.equal(choice.condition.operatorToken.kind, ts.SyntaxKind.EqualsEqualsEqualsToken);
  assert.ok(ts.isIdentifier(choice.condition.left) && choice.condition.left.text === 'phase');
  assert.ok(ts.isStringLiteral(choice.condition.right) && choice.condition.right.text === 'series-c-ios');
  for (const [branch, declaration] of [[choice.whenTrue, 'FRESH_ACCOUNT_IPHONE_VIEWPORTS'], [choice.whenFalse, 'FRESH_ACCOUNT_ANDROID_VIEWPORTS']]) {
    const actual = viewports(initializer(spec, declaration));
    assert.equal(new Set(actual).size, actual.length);
    assert.deepEqual(strings(branch), actual);
  }
});


// Refusal diagnostics are negative evidence, never a partial successful audit.
function closedRefusal(result, selected = context) {
  let error;
  try { projectSignupFinalAudit(result, selected); }
  catch (caught) { error = caught; }
  assert.ok(error);
  assert.equal(error.message, 'SIGNUP_AUDIT_REFUSED');
  const diagnostic = signupAuditRefusalDiagnostic(error);
  assert.ok(diagnostic);
  const bytes = JSON.stringify(diagnostic);
  assert.equal(bytes.includes(canary), false);
  assert.doesNotMatch(bytes, /Bearer|Authorization|https?:|wss?:|privateHeaders|requestId|documentId|timestamp/);
  assert.ok(bytes.length < 5000);
  assert.deepEqual(Object.keys(diagnostic).sort(), [
    'schemaVersion', 'checkpoint', 'attachmentRole', 'attachmentCount', 'attachmentCountLimitExceeded',
    'knownAttachmentCount', 'duplicateKnownAttachments', 'attachmentsByRole', 'attachmentSizes',
    'expectedMatrixRows', 'collections', 'roleHttpTruncated',
  ].sort());
  return { error, diagnostic };
}

async function refusedReceipt(mutator, { childExitCode = 1 } = {}) {
  let answer;
  await withReport(async state => {
    await mutator(state);
    let output = '';
    const code = await runPublicPlaywright(['--phase', 'series-c-ios', '--', 'test'], {
      cwd: state.cwd, env: { RUNNER_TEMP: state.directory }, getSourceSha: () => 'a'.repeat(40),
      emit: value => { output += value; },
      launch: async launchContext => {
        await writeFile(launchContext.env.PLAYWRIGHT_JSON_OUTPUT_FILE, JSON.stringify(state.report));
        return childExitCode;
      },
    });
    assert.equal(code, 1);
    assert.equal(output.includes(canary), false);
    answer = JSON.parse(output);
    assert.equal(answer.complete, false);
    assert.equal(answer.childExitCode, childExitCode);
    assert.equal(answer.exitCode, 1);
    assert.equal(answer.counts, null);
    assert.deepEqual(answer.tests, []);
  });
  return answer;
}

test('two finally attachments without matrix stay red and retain only safe failed/timedOut provenance', async () => {
  for (const status of ['failed', 'timedOut']) {
    const receipt = await refusedReceipt(({ cwd, attempt }) => {
      attempt.status = status;
      attempt.duration = 360000;
      attempt.attachments = attempt.attachments.filter(item => item.name !== 'audit-compte-neuf-soignant.json');
      attempt.errors = [{ message: canary, stack: canary,
        location: { file: path.join(cwd, FILE), line: 1, column: 1 } }];
    });
    assert.deepEqual(receipt.codes, ['SIGNUP_AUDIT_REFUSED']);
    const d = receipt.signupAuditRefusal;
    assert.equal(d.checkpoint, 'KNOWN_ATTACHMENT_SET');
    assert.equal(d.attachmentRole, 'soignant');
    assert.equal(d.knownAttachmentCount, 2);
    assert.deepEqual(d.attachmentsByRole.soignant, { matrix: false, roleHttp: true, transport: true });
    assert.deepEqual(d.attachmentsByRole.etab, { matrix: false, roleHttp: false, transport: false });
    assert.deepEqual(d.attempt, { file: FILE, line: 1, column: 1, retry: 0, status,
      durationMs: 360000, failureLocation: { file: FILE, line: 1, column: 1 } });
    assert.equal(d.otherTestsOrRefusalsComplete, false);
  }
});

test('a refused projection never invents a failed child when the actual child returned zero', async () => {
  const receipt = await refusedReceipt(({ attempt }) => { attempt.attachments.pop(); attempt.attachments.pop(); }, { childExitCode: 0 });
  assert.equal(receipt.childExitCode, 0);
  assert.equal(receipt.exitCode, 1);
  assert.deepEqual(receipt.codes, ['SIGNUP_AUDIT_REFUSED']);
});

test('forged errors, primitive values and hostile getters have no diagnostic provenance', () => {
  const forged = new Error('SIGNUP_AUDIT_REFUSED');
  forged.signupAuditRefusal = { privateHeaders: canary };
  const hostile = Object.create(null);
  for (const key of ['message', 'diagnostic', 'signupAuditRefusal']) {
    Object.defineProperty(hostile, key, { get() { throw new Error(canary); } });
  }
  const revocable = Proxy.revocable({}, {}); revocable.revoke();
  for (const value of [forged, hostile, revocable.proxy, null, undefined, false, 0, canary, [], () => canary]) {
    assert.equal(signupAuditRefusalDiagnostic(value), undefined);
  }
});

test('public diagnostic clones cannot mutate stored provenance or inject private extras', () => {
  const result = fixture().result(); result.attachments.splice(0, 1);
  const { error, diagnostic } = closedRefusal(result);
  diagnostic.attachmentsByRole.soignant.matrix = true;
  diagnostic.attachmentSizes.matrix.decodedBytes = 999;
  diagnostic.collections.matrixRows.count = 999;
  diagnostic.checkpoint = canary;
  diagnostic.privateHeaders = canary;
  error.signupAuditRefusal = { checkpoint: canary };
  const next = signupAuditRefusalDiagnostic(error);
  assert.equal(next.attachmentsByRole.soignant.matrix, false);
  assert.equal(next.attachmentSizes.matrix.decodedBytes, null);
  assert.equal(next.collections.matrixRows.count, null);
  assert.equal(next.checkpoint, 'KNOWN_ATTACHMENT_SET');
  assert.equal(JSON.stringify(next).includes(canary), false);
});

test('missing, duplicate and mixed-role pieces report fixed presence bits while still refusing', () => {
  for (const index of [0, 1, 2]) {
    const result = fixture().result(); result.attachments.splice(index, 1);
    const { diagnostic } = closedRefusal(result);
    assert.equal(diagnostic.checkpoint, 'KNOWN_ATTACHMENT_SET');
    assert.equal(diagnostic.knownAttachmentCount, 2);
    assert.equal(diagnostic.duplicateKnownAttachments, false);
    assert.equal(Object.values(diagnostic.attachmentsByRole.soignant).filter(Boolean).length, 2);
  }
  const duplicate = fixture().result(); duplicate.attachments.push(duplicate.attachments[0]);
  assert.equal(closedRefusal(duplicate).diagnostic.duplicateKnownAttachments, true);
  const mixed = fixture().result();
  mixed.attachments[1].name = 'audit-compte-neuf-role-http-etab.json';
  assert.equal(closedRefusal(mixed).diagnostic.checkpoint, 'ROLE_HTTP_ATTACHMENT');
});

test('attachment arrays and envelopes stay bounded without publishing names, paths or malformed bodies', () => {
  for (const change of [
    result => { result.attachments = { privateHeaders: canary }; },
    result => { result.attachments = Array(101).fill({ name: canary }); },
    result => { result.attachments[0].path = `/private/${canary}/../secret`; },
    result => { result.attachments[0].contentType = canary; },
    result => { result.attachments[0].body = canary; },
    result => { result.attachments[0].body = Buffer.from(`{${canary}`).toString('base64'); },
  ]) {
    const result = fixture().result(); change(result);
    closedRefusal(result);
  }
  const big = fixture().result(); big.attachments = Array(101).fill({ name: canary });
  const d = closedRefusal(big).diagnostic;
  assert.equal(d.attachmentCount, null); assert.equal(d.attachmentCountLimitExceeded, true);
  assert.equal(d.knownAttachmentCount, null);
});

test('the exact 8MiB decoding boundary remains strict and reports no oversized numeric value', () => {
  const MAX = 8 * 1024 * 1024;
  for (const size of [MAX, MAX + 1]) {
    const result = fixture().result();
    result.attachments[0].body = Buffer.from('"' + 'x'.repeat(size - 2) + '"').toString('base64');
    const d = closedRefusal(result).diagnostic;
    assert.equal(d.checkpoint, size === MAX ? 'MATRIX_SHAPE' : 'MATRIX_ATTACHMENT');
    assert.equal(d.attachmentSizes.matrix.decodedBytes, size === MAX ? MAX : null);
    assert.equal(d.attachmentSizes.matrix.decodedLimitExceeded, size > MAX);
  }
});

test('short/oversized matrices remain refused for both roles and both mobile phases', () => {
  for (const role of ['soignant', 'etab']) for (const phase of ['series-c-ios', 'series-c-android']) {
    for (const delta of [-1, 1]) {
      const f = fixture(role, phase), expected = f.audit.length;
      if (delta < 0) f.audit.pop(); else f.audit.push(f.audit[0]);
      const d = closedRefusal(f.result(), { ...context, phase }).diagnostic;
      assert.equal(d.checkpoint, 'MATRIX_SHAPE');
      assert.equal(d.expectedMatrixRows, expected);
      assert.equal(d.collections.matrixRows.count, delta < 0 ? expected - 1 : null);
      assert.equal(d.collections.matrixRows.limitExceeded, delta > 0);
    }
  }
});

test('truncated and non-boolean RPC flags remain refused without coercing private values', () => {
  for (const value of [true, undefined, 'false', canary, 0]) {
    const f = fixture(); f.roleHttp.truncated = value;
    const d = closedRefusal(f.result()).diagnostic;
    assert.equal(d.checkpoint, 'ROLE_HTTP_SHAPE');
    assert.equal(d.roleHttpTruncated, value === true ? true : null);
  }
});

test('RPC and transport event caps still accept 2048 valid entries and refuse 2049', () => {
  const rpc = { navigationId: 1, matrixIndex: 0, phase: 'inspection', scope: 'unknown',
    event: 'request', failureCode: null, httpStatus: null, privateHeaders: canary };
  const ws = { matrixIndex: 0, phase: 'inspection', event: 'websocket-requested',
    connectionAttempt: 1, subsequentAttempts: 0, httpStatus: null, privateHeaders: canary };
  for (const kind of ['rpc', 'ws']) {
    const f = fixture();
    if (kind === 'rpc') f.roleHttp.events = Array(2048).fill(rpc);
    else f.transport.push(...Array(2048).fill(ws));
    assert.ok(projectSignupFinalAudit(f.result(), context));
    if (kind === 'rpc') f.roleHttp.events.push(rpc); else f.transport.push(ws);
    const d = closedRefusal(f.result()).diagnostic;
    const counter = kind === 'rpc' ? d.collections.roleHttpEvents : d.collections.transportEvents;
    assert.equal(counter.count, null); assert.equal(counter.limitExceeded, true);
    assert.equal(d.checkpoint, kind === 'rpc' ? 'ROLE_HTTP_EVENTS' : 'TRANSPORT_EVENTS');
  }
});

test('invalid attempt metadata and arbitrary thrown errors cannot acquire a refusal receipt', async () => {
  for (const change of [
    attempt => { attempt.duration = Infinity; }, attempt => { attempt.duration = -1; },
    attempt => { attempt.retry = 99; }, attempt => { attempt.status = canary; },
  ]) {
    const receipt = await refusedReceipt(({ attempt }) => { change(attempt); attempt.attachments.splice(0, 1); });
    assert.equal(Object.hasOwn(receipt, 'signupAuditRefusal'), false);
    assert.deepEqual(receipt.codes, ['REPORT_INVALID']);
  }
  await withReport(async ({ cwd, directory }) => {
    let output = '';
    const forged = new Error('SIGNUP_AUDIT_REFUSED'); forged.signupAuditRefusal = { body: canary };
    await runPublicPlaywright(['--phase', 'series-c-ios', '--', 'test'], {
      cwd, env: { RUNNER_TEMP: directory }, getSourceSha: () => 'a'.repeat(40),
      emit: value => { output += value; }, launch: async () => { throw forged; },
    });
    const receipt = JSON.parse(output);
    assert.deepEqual(receipt.codes, ['PRIVATE_RUN_FAILED']);
    assert.equal(Object.hasOwn(receipt, 'signupAuditRefusal'), false);
    assert.equal(output.includes(canary), false);
  });
});

test('successful, absent and unknown-file projections retain their original public schemas', async () => {
  const f = fixture();
  const projected = projectSignupFinalAudit(f.result(), context);
  assert.deepEqual(Object.keys(projected).sort(), ['schemaVersion', 'role', 'routeCount', 'viewportCount',
    'inspectedCount', 'rows', 'roleRpcFailures', 'websocketErrors'].sort());
  for (const attachments of [undefined, null, [], [{ name: canary, body: canary, path: canary }]]) {
    assert.equal(projectSignupFinalAudit({ attachments }, context), undefined);
  }
  assert.equal(projectSignupFinalAudit(f.result(), { ...context, file: canary }), undefined);
  await withReport(async ({ cwd, report, attempt }) => {
    attempt.attachments = [];
    const summary = await projectReport(report, { ...context, cwd });
    assert.equal(summary.tests[0].attempts[0].code, 'TEST_FAILED');
    assert.equal(Object.hasOwn(summary.tests[0].attempts[0], 'signupAuditRefusal'), false);
  });
});

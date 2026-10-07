import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, createHash } from 'node:crypto';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { BRANCH, PRODUCT_SHA, MIGRATION_COUNT, WORKFLOW_PATH, checkIdentity, checkVercel, executionIdentity, hash } from './identity.mjs';
import { projectToc, projectSnapshot, closedFailure, PG17_TOC_KINDS } from './projection.mjs';
import { parseTap } from './phase-a.mjs';
import { newSourceFixture, seedSource, sqlJson } from './source-fixture.mjs';
import { phaseFailure } from './failure.mjs';
import { runPhaseA } from './phase-a-core.mjs';
import { captureSource, CAPTURE_STAGES, normalizedToc } from './snapshot-restore.mjs';

const head = 'a'.repeat(40), run = 'jolene-restore-drill-123456-1';
const env = { GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_EVENT_NAME: 'workflow_dispatch',
  GITHUB_REF: 'refs/heads/' + BRANCH, GITHUB_SHA: head,
  GITHUB_WORKFLOW_REF: 'Gabpcd/JJJJJ/' + WORKFLOW_PATH + '@refs/heads/' + BRANCH, GITHUB_WORKFLOW_SHA: head, GITHUB_RUN_ID: '123456', GITHUB_RUN_ATTEMPT: '1' };
const paths = { stack: '/tmp/private-synthetic-phase-a-stack' };
const requiredTables = ['auth.users', 'auth.identities', 'auth.sessions', 'auth.refresh_tokens',
  'storage.objects', 'storage.buckets', 'public.factures_honoraires', 'public.factures_honoraires_documents'];
function toc() {
  const entries = requiredTables.flatMap(table => ['TABLE', 'TABLE DATA'].map(kind => `${kind} ${table.replace('.', ' ')} synthetic_owner`));
  entries.push('ENCODING - ENCODING', 'STDSTRINGS - STDSTRINGS', 'SEARCHPATH - SEARCHPATH');
  for (let i = 0; i < 90; i++) entries.push(`FUNCTION public synthetic_${i}() synthetic_owner`);
  return Buffer.from('; Synthetic TOC contract only\n' + entries.map((value, index) => `${index + 1}; 0 0 ${value}`).join('\n') + '\n');
}
function snapshot(fixture, listing = toc()) {
  const counts = { 'auth.users': 5, 'auth.identities': 5, 'public.soignants': 2, 'public.etablissements': 2,
    'public.missions': 1, 'public.factures_honoraires': 1, 'public.factures_honoraires_documents': 1,
    'storage.objects': 2, 'auth.sessions': 0, 'auth.refresh_tokens': 0 };
  return { before: Object.fromEntries(Object.entries(counts).map(([table, count]) => [table, { count, sha256: hash(table) }])),
    catalogue: { synthetic: true }, archiveSha256: hash('synthetic-private-archive'), tocSha256: projectToc(listing).normalizedSha256,
    files: fixture.files.map(file => ({ path: file.key, bytes: file.bytes.length, sha256: hash(file.bytes) })) };
}
function harness(change = {}) {
  const calls = [], fixture = newSourceFixture(PRODUCT_SHA, run), captured = snapshot(fixture);
  const runtime = {
    run,
    verifyState: async state => calls.push(['state', state]),
    assertTargetNativeEmpty: async () => calls.push(['target-empty']),
    startApis: async side => calls.push(['start', side]),
    assertApiHealthy: async side => calls.push(['healthy', side]),
    privateWrite: async () => calls.push(['private-write']),
    verifyDocumentBytes: async () => { calls.push(['bytes']); return { verified: 2 }; },
    sqlJson: async (side, sql) => { assert.equal(side, 'source');
      if (sql === 'synthetic-current-product') { calls.push(['current-witness']); return { localContext: true, functionsExact: true, certificateExact: true }; }
      calls.push(['native-version']); return {
      postgresVersionNum: 170006, auth: { count: 40, sha256: hash('synthetic-auth-version') },
      storage: { count: 30, sha256: hash('synthetic-storage-version') },
    }; },
    stopSource: async () => calls.push(['stop-source']),
    copyFilesOut: async side => { assert.equal(side, 'target'); calls.push(['copy-target']); },
  };
  const dependencies = {
    importer: async () => { calls.push(['import']); return { result: 'ISOLATED_IMPORT_AND_SQL_TEST_PASSED',
      product_sha: PRODUCT_SHA, canonical_test_passed: true, rollback_verified: true,
      migrations: Array.from({ length: MIGRATION_COUNT }, (_, i) => ({ completed: true, path: `synthetic-${i}`, sha256: hash(String(i)) })) }; },
    makeRuntime: () => runtime, makeFixture: () => fixture,
    seed: async () => { calls.push(['seed']); return { users: 5, invoices: 1, objects: 2 }; },
    makeDirectory: () => {}, checkpointSql: 'synthetic-checkpoint', currentProductSql: 'synthetic-current-product', nativeSql: 'synthetic-native-version',
    capture: async () => { calls.push(['capture']); return captured; },
    readToc: () => toc(), readFileTree: () => [], ...change,
  };
  const reports = [], evidence = { pins: { qualifiedProductSha: PRODUCT_SHA }, productSha: PRODUCT_SHA,
    harnessSha: head, run, migrations: Array.from({ length: MIGRATION_COUNT }, (_, i) => ({ path: `synthetic-${i}`, sha256: hash(String(i)) })) };
  return { calls, fixture, captured, reports, runtime, dependencies,
    execute: () => runPhaseA(evidence, paths, value => reports.push(value), dependencies) };
}

test('identity is exact manual branch, commit, clean allowed scaffold and no product change', () => {
  const allowed = ['tools/restore-local/scripts/restore-app/phase-a.mjs'];
  assert.equal(checkIdentity(env, head, allowed, '', allowed).run, run);
  assert.equal(executionIdentity(env, head).run, run); // cleanup never depends on import completion or source pins
  for (const patch of [{ GITHUB_REF: 'refs/heads/main' }, { GITHUB_EVENT_NAME: 'push' },
    { GITHUB_REPOSITORY: 'other/repo' }, { GITHUB_WORKFLOW_SHA: 'b'.repeat(40) },
    { GITHUB_WORKFLOW_REF: 'Gabpcd/JJJJJ/.github/workflows/other.yml@refs/heads/' + BRANCH }, { GITHUB_SHA: PRODUCT_SHA }, { GITHUB_RUN_ATTEMPT: '0' }])
    assert.throws(() => checkIdentity({ ...env, ...patch }, head, allowed, '', allowed));
  assert.throws(() => checkIdentity(env, head, allowed, ' M private', allowed));
  assert.throws(() => checkIdentity(env, head, ['src/App.tsx'], '', allowed));
  assert.throws(() => checkIdentity(env, head, [], '', allowed));
  const base = { git: { deploymentEnabled: { main: true } }, buildCommand: 'unchanged' };
  const next = structuredClone(base); next.git.deploymentEnabled[BRANCH] = false;
  checkVercel(base, next); next.git.deploymentEnabled.main = false;
  assert.throws(() => checkVercel(base, next));
});

test('TOC exposes only closed kinds/schemas/counts and refuses missing or duplicate native table data', () => {
  const listing = toc(), canary = randomBytes(24).toString('hex');
  const receipt = projectToc(Buffer.from(listing.toString().replace('synthetic_0()', canary + '()')));
  assert.equal(receipt.requiredTables['auth.identities'].data, 1);
  assert.equal(JSON.stringify(receipt).includes(canary), false);
  for (const bytes of [Buffer.from(listing.toString().replace(/^.*TABLE DATA auth identities.*\n/m, '')),
    Buffer.concat([listing, Buffer.from('999; 0 0 TABLE DATA auth identities synthetic_owner\n')]),
    Buffer.concat([listing, Buffer.from('999; 0 0 TABLE ' + canary + ' unknown owner\n')])])
    assert.throws(() => projectToc(bytes));
});

test('native snapshot requires both original object bytes, exact actor counts and no sessions', () => {
  const fixture = newSourceFixture(PRODUCT_SHA, run), value = snapshot(fixture);
  assert.equal(projectSnapshot(value, fixture).expectedObjectBytesPresent, 2);
  for (const mutate of [x => { x.files[1].sha256 = hash('missing XML'); },
    x => { x.before['auth.identities'].count = 4; }, x => { x.before['auth.sessions'].count = 1; }]) {
    const invalid = structuredClone(value); mutate(invalid); assert.throws(() => projectSnapshot(invalid, fixture));
  }
});

test('phase A finishes capture with source off, empty untouched target and every phase B flag false', async () => {
  const h = harness(), receipt = await h.execute();
  assert.equal(receipt.result, 'PHASE_A_NATIVE_CAPTURE_PASSED');
  assert.deepEqual(h.calls.filter(([kind]) => ['import', 'start', 'healthy', 'seed', 'bytes', 'capture', 'stop-source', 'copy-target'].includes(kind)),
    [['import'], ['start', 'source'], ['healthy', 'source'], ['seed'], ['bytes'], ['capture'], ['stop-source'], ['copy-target']]);
  assert.deepEqual(h.calls.filter(([kind]) => kind === 'state').at(-1), ['state', { source: 'off', target: 'db-only', browser: 'absent' }]);
  assert.equal(h.calls.filter(([kind]) => kind === 'target-empty').length, 2);
  for (const flag of ['restored', 'appVerified', 'targetSeeded', 'providerContacted', 'readyForRestore', 'readyForDispatchPhaseB']) assert.equal(receipt[flag], false);
  assert.equal(receipt.currentProductWitnessPassed, true);
  assert.ok(h.calls.findIndex(([kind]) => kind === 'current-witness') < h.calls.findIndex(([kind]) => kind === 'start'));
  assert.equal(h.reports.at(-1), receipt);
});

test('failed import never seeds, and missing bytes or nonempty target never claim capture success', async () => {
  const refused = harness({ importer: async () => ({ result: 'FAILED' }) });
  await assert.rejects(refused.execute(), /PHASE_A_IMPORT_REQUIRED/);
  assert.equal(refused.calls.some(([kind]) => kind === 'seed'), false);
  const missing = harness(); missing.captured.files[1].sha256 = hash('other bytes');
  await assert.rejects(missing.execute(), /PHASE_A_STORAGE_BYTES/);
  assert.equal(missing.calls.some(([kind]) => kind === 'stop-source'), false);
  const occupied = harness({ readFileTree: () => [{ bytes: 1, sha256: hash('occupied') }] });
  await assert.rejects(occupied.execute(), /PHASE_A_TARGET_FILES_NOT_EMPTY/);
  assert.equal(occupied.reports.some(value => value.result === 'PHASE_A_NATIVE_CAPTURE_PASSED'), false);
});

test('capture stops APIs before reading data, saves a real native archive and rejects checkpoint drift', async () => {
  for (const drift of [false, true]) {
    const directory = mkdtempSync(join(tmpdir(), 'phase-a-synthetic-'));
    const calls = [], saved = [], before = { synthetic: { count: 5, sha256: hash('unchanged') } };
    let checkpoints = 0;
    const runtime = { run,
      stopApis: async side => { assert.equal(side, 'source'); calls.push('stop'); },
      verifyState: async state => { assert.deepEqual(state, { source: 'db-only', target: 'db-only', browser: 'absent' }); calls.push('state'); },
      sqlJson: async side => { assert.equal(side, 'source'); calls.push('checkpoint'); return ++checkpoints === 2 && drift ? { changed: true } : before; },
      catalogue: async side => { assert.equal(side, 'source'); return { synthetic: true }; },
      databaseTool: async (side, tool, args) => {
        assert.equal(side, 'source'); assert.equal(tool, 'pg_dump'); assert.ok(args.includes('-Fc'));
        assert.equal(args.includes('--disable-triggers'), false); calls.push('dump'); return Buffer.from('PGDMPsynthetic');
      },
      archiveList: async () => toc(),
      privateWrite: async (path, bytes) => { saved.push(path); assert.ok(Buffer.isBuffer(bytes)); },
      copyFilesOut: async (side, destination) => {
        assert.equal(side, 'source'); mkdirSync(destination, { mode: 0o700 });
        writeFileSync(join(destination, 'synthetic.pdf'), 'bytes-pdf'); writeFileSync(join(destination, 'synthetic.xml'), 'bytes-xml');
      },
    };
    try {
      if (drift) {
        await assert.rejects(captureSource(runtime, directory, 'synthetic-checkpoint'), /RESTORE_SOURCE_CHANGED_DURING_BACKUP/);
        assert.equal(saved.some(path => path.endsWith('snapshot.private.json')), false);
      } else assert.equal((await captureSource(runtime, directory, 'synthetic-checkpoint')).files.length, 2);
      assert.deepEqual(calls.slice(0, 4), ['stop', 'state', 'checkpoint', 'dump']);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  }
});

test('seed uses five runtime synthetic identities, source-only canonical SQL and two no-upsert objects', async () => {
  const fixture = newSourceFixture(PRODUCT_SHA, run), calls = [];
  assert.equal(new Set(fixture.members.map(member => member.id)).size, 5);
  assert.ok(fixture.members.every(member => member.email.endsWith('@example.invalid')));
  const runtime = { side: 'source', run, guard: async phase => calls.push(['guard', phase]),
    sql: async text => { assert.match(text, /BEGIN; SET LOCAL row_security=off/); assert.match(text, /COMMIT;/); calls.push(['sql']); },
    api: async (path, request) => {
      calls.push(['api', path]); assert.equal(request.method, 'POST');
      if (path === '/auth/v1/admin/users') return { status: 201, json: { ...request.body, email_confirmed_at: 'synthetic' } };
      assert.match(path, /^\/storage\/v1\/object\/jolene-documents\/invoices\/restore\//); return { status: 200 };
    } };
  assert.equal((await seedSource(runtime, fixture)).objects, 2);
  assert.equal(calls.filter(([kind]) => kind === 'api').length, 7);
  assert.deepEqual(calls.at(-1), ['guard', 'seeded']);
  await assert.rejects(seedSource({ ...runtime, side: 'target' }, fixture), /RESTORE_SOURCE_ONLY/);
  assert.throws(() => sqlJson({ value: '$restore_fixture_json$' }), /RESTORE_JSON_DELIMITER/);
});

test('public failure and unit projection never include random private output or error messages', () => {
  const canary = randomBytes(24).toString('hex');
  const error = Object.assign(Error(canary), { diagnostic: { sqlstate: '42P01', line: 123, assertion: canary }, raw: canary });
  const receipt = closedFailure(error, 'capture');
  assert.equal(receipt.sqlstate, '42P01'); assert.equal(receipt.sqlLine, 123);
  assert.equal(JSON.stringify(receipt).includes(canary), false);
  assert.equal(closedFailure(error, canary).stage, 'identity');
  const tap = canary + '\n# tests 2\n# pass 2\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n';
  assert.equal(JSON.stringify(parseTap(tap, 0)).includes(canary), false);
  for (const [text, status] of [[canary, 0], [tap, 1], [tap.replace('# skipped 0', '# skipped 1'), 0], [tap + '# tests 2\n', 0]])
    assert.throws(() => parseTap(text, status), error => !error.message.includes(canary));
});

test('workflow is manual exact branch with private raw logs, explicit closed uploads, cleanup and no restore command', () => {
  const complete = readFileSync(new URL('../../../../.github/workflows/restore-local-bootstrap.yml', import.meta.url), 'utf8');
  const workflow = complete.split('\n  native-capture:\n')[1];
  assert.ok(workflow);
  const legacy = complete.split('\n  native-capture:\n')[0];
  assert.match(legacy, /github.ref != 'refs\/heads\/ci\/restore-app-phase-a-20261004' && github.head_ref != 'ci\/restore-app-phase-a-20261004'/);
  assert.ok(!/pull_request:|\bpush:|secrets\.|environment:|npm (ci|install)|supabase db|workflow run/.test(workflow));
  assert.match(workflow, /github.ref == 'refs\/heads\/ci\/restore-app-phase-a-20261004'/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(workflow, /name: Always clean exact owned resources twice\n\s+if: always\(\)/);
  assert.match(workflow, /name: Independent exact absence\n\s+if: always\(\)/);
  const uploads = [...workflow.matchAll(/\$\{\{ env\.PROOF_DIR \}\}\/([^\n]+)/g)].map(match => match[1]);
  assert.deepEqual(uploads, ['identity.json', 'units.json', 'bootstrap-proof.json', 'phase-a.json',
    'diagnostic.json', 'cleanup.json', 'cleanup-again.json', 'absence.json']);
  for (const line of workflow.split('\n').filter(line => /^\s+(node|timeout).*phase-a\.mjs/.test(line)))
    assert.match(line, /> "\$PRIVATE_DIR\/[a-z-]+\.log" 2>&1$/);
  const runtime = readFileSync(new URL('./local-runtime.mjs', import.meta.url), 'utf8');
  assert.ok(!/recreateDatabase|copyFilesIn|pg_restore',\s*'-d'|--clean|--disable-triggers/.test(runtime.replaceAll("!args.includes('--disable-triggers')", '').replaceAll("!args.includes('--clean')", '')));
  assert.match(runtime, /'pg_restore', '--list'/);
  assert.match(runtime, /side === 'source' && tool === 'pg_dump'/);
});


test('221 import must identify current product and exact ordered migration bytes before runtime exists', async () => {
  for (const patch of [value => { value.product_sha = '0'.repeat(40); },
    value => { value.migrations.pop(); }, value => { value.migrations.reverse(); },
    value => { value.migrations[218].sha256 = hash('wrong OTP'); },
    value => { value.migrations[219].sha256 = hash('wrong signature lock'); },
    value => { value.migrations[220].sha256 = hash('wrong period totals'); }]) {
    const h = harness(), importer = h.dependencies.importer;
    h.dependencies.importer = async () => { const result = await importer(); patch(result); return result; };
    await assert.rejects(h.execute(), /PHASE_A_IMPORT_REQUIRED/);
    assert.equal(h.calls.some(([kind]) => ['start','seed','capture'].includes(kind)), false);
  }
});

test('current-product catalogue failure refuses before API restart or durable fixture', async () => {
  for (const result of [null, [], { localContext: true, functionsExact: false, certificateExact: true },
    { localContext: true, functionsExact: true, certificateExact: false },
    { localContext: false, functionsExact: true, certificateExact: true },
    { localContext: true, functionsExact: true, certificateExact: true, extra: true }]) {
    const h = harness(); h.runtime.sqlJson = async () => result;
    await assert.rejects(h.execute(), /PHASE_A_CURRENT_PRODUCT_WITNESS/);
    assert.equal(h.calls.some(([kind]) => ['start','seed','capture'].includes(kind)), false);
  }
});


test('closed non-SQL diagnostics distinguish Auth and Storage status without private response values', async () => {
  const canary=randomBytes(24).toString('hex');
  for(const [step,status,expected] of [['auth',401,'RESTORE_AUTH_CREATE'],['object',409,'RESTORE_OBJECT_CREATE']]){
    const fixture=newSourceFixture(PRODUCT_SHA,run), runtime={side:'source',run,guard:async()=>{},sql:async()=>{},
      api:async(path,request)=>{
        if(path==='/auth/v1/admin/users') return step==='auth'?{status,json:{error:canary}}:
          {status:201,json:{...request.body,email_confirmed_at:'synthetic'}};
        return {status,json:{error:canary}};
      }};
    await assert.rejects(seedSource(runtime,fixture),error=>{
      const receipt=closedFailure(error,'source_seed');assert.equal(receipt.code,expected);
      assert.equal(receipt.httpStatus,status);assert.equal(JSON.stringify(receipt).includes(canary),false);return true;
    });
  }
  for(const status of [0,600,'401',NaN,Infinity])assert.equal(closedFailure(phaseFailure('RESTORE_OBJECT_CREATE',{httpStatus:status}),'source_seed').httpStatus,null);
  const unknown=Object.assign(Error(canary),{publicCode:canary,httpStatus:401,body:canary});
  assert.equal(closedFailure(unknown,'capture').code,'PHASE_A_FAILED');
  assert.equal(closedFailure(unknown,'capture').httpStatus,null);
  assert.equal(JSON.stringify(closedFailure(unknown,'capture')).includes(canary),false);
});


test('current-product certificate witness uses the real baseline columns and migration 219 revoked column', () => {
  // Read the integral product sources, not a copied list in a synthetic catalogue response.
  const baseline = readFileSync(new URL('../../../../supabase/migrations/00000000000000_baseline_prod.sql', import.meta.url), 'utf8');
  const migration = readFileSync(new URL('../../../../supabase/migrations/20261004124300_refuser_signature_otp_et_document_incoherents.sql', import.meta.url), 'utf8');
  const witness = readFileSync(new URL('./sql/current-product-witness.sql', import.meta.url), 'utf8');
  const table = baseline.match(/CREATE TABLE IF NOT EXISTS "public"\."signatures_contrats" \(([\s\S]*?)\n\);/);
  assert.ok(table, 'canonical certificate table must be present');
  const actualColumns = new Set([...table[1].matchAll(/^\s+"([a-z_]+)"\s/gm)].map(match => match[1]));
  const revoked = [...migration.matchAll(/REVOKE SELECT \(([a-z_]+)\) ON TABLE public\.signatures_contrats FROM PUBLIC, anon, authenticated;/g)].map(match => match[1]);
  assert.equal(revoked.length, 1, 'canonical private-column revoke must be unambiguous');
  const checked = [...witness.matchAll(/NOT has_column_privilege\('authenticated','public\.signatures_contrats','([a-z_]+)','SELECT'\)/g)].map(match => match[1]);
  assert.equal(checked.length, 1, 'witness must check the explicit private column');
  for (const column of checked) assert.ok(actualColumns.has(column), 'witness refers to a nonexistent product column');
  assert.deepEqual(checked, revoked, 'witness must check the column revoked by the real migration');
});


test('capture distinguishes checkpoint, catalogue and archive stages without leaking SQL diagnostics', async () => {
  for (const failedStage of CAPTURE_STAGES) {
    const directory = mkdtempSync(join(tmpdir(), 'phase-a-stage-'));
    const canary = randomBytes(24).toString('hex'), seen = [];
    let lastStage = 'capture', dumpStarted = false;
    const failure = Object.assign(Error(canary), { diagnostic: { sqlstate: '42725', line: 36 }, raw: canary });
    const failHere = () => { if (lastStage === failedStage) throw failure; };
    const runtime = { run, stopApis: async () => {}, verifyState: async () => {},
      sqlJson: async () => { failHere(); return { unchanged: true }; },
      catalogue: async () => { failHere(); return { synthetic: true }; },
      databaseTool: async () => { dumpStarted = true; failHere(); return Buffer.from('PGDMPsynthetic'); },
      archiveList: async () => { failHere(); return toc(); }, privateWrite: async () => {},
      copyFilesOut: async (_side, destination) => {
        failHere(); mkdirSync(destination); writeFileSync(join(destination, 'synthetic.pdf'), 'pdf');
        writeFileSync(join(destination, 'synthetic.xml'), 'xml');
      },
    };
    try {
      await assert.rejects(captureSource(runtime, directory, 'synthetic-checkpoint', stage => { lastStage = stage; seen.push(stage); }), error => {
        assert.equal(error, failure);
        const report = closedFailure(error, lastStage);
        assert.equal(report.stage, failedStage); assert.equal(report.sqlstate, '42725'); assert.equal(report.sqlLine, 36);
        assert.equal(JSON.stringify(report).includes(canary), false); return true;
      });
      assert.deepEqual(seen, CAPTURE_STAGES.slice(0, CAPTURE_STAGES.indexOf(failedStage) + 1));
      if (['capture_checkpoint_before', 'capture_catalogue'].includes(failedStage)) assert.equal(dumpStarted, false);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  }
});

test('phase A forwards native capture substages into its closed public progress', async () => {
  const h = harness();
  h.dependencies.capture = async (_runtime, _directory, _checkpoint, enter) => {
    for (const stage of CAPTURE_STAGES) enter(stage);
    return h.captured;
  };
  await h.execute();
  assert.deepEqual(h.reports.map(value => value.stage).filter(stage => CAPTURE_STAGES.includes(stage)), [...CAPTURE_STAGES]);
});

test('TOC schema refusal keeps all guards and reports only a closed parser context', () => {
  const canary = 'secret_' + randomBytes(24).toString('hex');
  const baseline = toc(), expectedOrdinal = baseline.toString().split('\n').filter(line => line && !line.startsWith(';')).length + 1;
  const cases = [
    ...['_realtime', '_analytics', 'pgmq', 'pgmq_public'].map(token => ['FUNCTION', token, 'known_native_candidate', token]),
    ['TABLE ATTACH', canary, 'other_identifier', null],
    ['INDEX ATTACH', canary, 'other_identifier', null],
    ['FUNCTION', '', 'empty_token', null],
    ['FUNCTION', '"' + canary + '"', 'quoted_token', null],
    ['FUNCTION', canary, 'other_identifier', null],
    ['FUNCTION', canary + '!', 'invalid_token', null],
  ];
  for (const [kind, token, tokenClass, candidate] of cases) {
    const listing = Buffer.concat([baseline, Buffer.from(`999; 0 0 ${kind} ${token} ${canary} ${canary}\n`)]);
    assert.throws(() => projectToc(listing), error => {
      const receipt = closedFailure(error, 'project_toc');
      assert.equal(receipt.result, 'PHASE_A_REFUSED'); assert.equal(receipt.code, 'PHASE_A_TOC_SCHEMA');
      assert.equal(receipt.stage, 'project_toc');
      assert.deepEqual(receipt.toc, { entryOrdinal: expectedOrdinal, kind, tokenClass, candidate,
        tokenSha256: candidate === null ? hash(token) : null });
      assert.equal(JSON.stringify(receipt).includes(canary), false);
      assert.equal(receipt.restored, false); assert.equal(receipt.readyForDispatchPhaseB, false);
      return true;
    });
  }
  // Unknown descriptors remain rejected before schema diagnosis with a closed hash-only context.
  assert.throws(() => projectToc(Buffer.concat([baseline, Buffer.from(`999; 0 0 ${canary} public object owner\n`)])), error => {
    const receipt = closedFailure(error, 'project_toc');
    assert.equal(receipt.code, 'PHASE_A_TOC_KIND'); assert.equal(receipt.toc.candidate, null);
    assert.equal(receipt.toc.entryOrdinal, expectedOrdinal); assert.match(receipt.toc.prefixSha256,/^[a-f0-9]{64}$/);
    assert.equal(JSON.stringify(receipt).includes(canary), false); return true;
  });
  assert.equal(projectToc(baseline).requiredTables['auth.identities'].data, 1);
});

test('TOC failure projection rejects forged fields, unbounded ordinals and non-enum strings', () => {
  const canary = 'secret_' + randomBytes(24).toString('hex');
  const valid = { entryOrdinal: 1, kind: 'FUNCTION', tokenClass: 'other_identifier', candidate: null, tokenSha256: hash(canary) };
  const project = value => closedFailure(phaseFailure('PHASE_A_TOC_SCHEMA', { tocDiagnostic: value }), 'project_toc');
  assert.deepEqual(project(valid).toc, valid);
  for (const patch of [{ entryOrdinal: 0 }, { entryOrdinal: 30_001 }, { entryOrdinal: 1.5 },
    { entryOrdinal: '1' }, { kind: canary }, { tokenClass: canary }, { candidate: canary },
    { tokenSha256: canary }, { tokenSha256: { toJSON: () => canary } }, { rawToken: canary },
    { toJSON: () => canary }, { tokenClass: 'known_native_candidate' },
    { candidate: '_realtime', tokenSha256: null }]) {
    const receipt = project({ ...valid, ...patch });
    assert.equal(receipt.toc, null); assert.equal(JSON.stringify(receipt).includes(canary), false);
  }
  assert.equal(closedFailure(Object.assign(Error(canary), { publicCode: 'PHASE_A_FAILED', tocDiagnostic: valid }), 'project_toc').toc, null);
  for (const entryOrdinal of [1, 30_000]) assert.equal(project({ ...valid, entryOrdinal }).toc.entryOrdinal, entryOrdinal);
});

test('native pgbouncer schema observed in run 37228749020 is counted without exporting object names', () => {
  const canary = 'private_' + randomBytes(24).toString('hex');
  const listing = Buffer.concat([toc(), Buffer.from(`999; 0 0 FUNCTION pgbouncer ${canary}() ${canary}\n`)]);
  const receipt = projectToc(listing);
  assert.equal(receipt.schemas.pgbouncer, 1);
  assert.equal(JSON.stringify(receipt).includes(canary), false);
  for (const unknown of ['pgbouncer_extra', 'pgbouncer.' + canary, '_realtime']) {
    assert.throws(() => projectToc(Buffer.concat([toc(), Buffer.from(`999; 0 0 FUNCTION ${unknown} object owner\n`)])),
      error => error.publicCode === 'PHASE_A_TOC_SCHEMA');
  }
  assert.throws(() => projectToc(Buffer.from(listing.toString().replace(/^.*TABLE DATA auth identities.*\n/m, ''))),
    error => error.publicCode === 'PHASE_A_TOC_REQUIRED_TABLE');
});

test('TOC projection has its own stage and a V6-style refusal cannot continue to source-off', async () => {
  const canary = 'secret_' + randomBytes(24).toString('hex');
  const h = harness({ readToc: () => Buffer.concat([toc(), Buffer.from(`999; 0 0 FUNCTION ${canary} object owner\n`)]) });
  await assert.rejects(h.execute(), error => {
    const receipt = closedFailure(error, h.reports.at(-1).stage);
    assert.equal(receipt.stage, 'project_toc'); assert.equal(receipt.code, 'PHASE_A_TOC_SCHEMA');
    assert.equal(receipt.toc.tokenSha256, hash(canary));
    assert.equal(JSON.stringify(receipt).includes(canary), false); return true;
  });
  assert.equal(h.calls.some(([kind]) => ['native-version', 'stop-source', 'copy-target'].includes(kind)), false);
  assert.equal(h.reports.some(value => value.result === 'PHASE_A_NATIVE_CAPTURE_PASSED'), false);
});


test('official PG17 inventory covers every emitted descriptor and keeps names private',()=>{
  const inventory=JSON.parse(readFileSync(new URL('./toc-pg17-descriptors.json',import.meta.url),'utf8'));
  assert.equal(inventory.postgresTag,'REL_17_6');assert.equal(inventory.emittedDescriptorCount,63);
  assert.deepEqual([...PG17_TOC_KINDS].sort(),inventory.entries.map(value=>value.kind).sort());
  assert.equal(new Set(PG17_TOC_KINDS).size,63);
  const canary='private_'+randomBytes(24).toString('hex'),before=projectToc(toc());
  const additions=inventory.entries.map(({kind},i)=>`${1000+i}; 0 0 ${kind} public ${canary} ${canary}\n`).join('');
  const result=projectToc(Buffer.concat([toc(),Buffer.from(additions)]));
  for(const {kind,origins} of inventory.entries){assert.equal(result.kinds[kind],(before.kinds[kind]??0)+1);assert.ok(origins.length>0);}
  assert.equal(JSON.stringify(result).includes(canary),false);assert.equal(result.requiredTables['auth.users'].table,1);
});
test('longest known descriptor wins across all overlapping PG17 families',()=>{
  const kinds=['DEFAULT','DEFAULT ACL','INDEX','INDEX ATTACH','TABLE','TABLE ATTACH','TABLE DATA',
    'PUBLICATION','PUBLICATION TABLE','PUBLICATION TABLES IN SCHEMA','MATERIALIZED VIEW','MATERIALIZED VIEW DATA',
    'SEQUENCE','SEQUENCE SET','SEQUENCE OWNED BY','OPERATOR','OPERATOR CLASS','OPERATOR FAMILY',
    'FK CONSTRAINT','CHECK CONSTRAINT','CONSTRAINT','DATABASE','DATABASE PROPERTIES','SUBSCRIPTION','SUBSCRIPTION TABLE'];
  for(const kind of kinds){const result=projectToc(Buffer.concat([toc(),Buffer.from(`900; 0 0 ${kind} public object owner\n`)]));
    assert.equal(result.kinds[kind],(projectToc(toc()).kinds[kind]??0)+1);assert.equal(result.schemas.public,projectToc(toc()).schemas.public+1);}
});
test('projection of a native descriptor cannot relax capture DATABASE or SUBSCRIPTION refusals',()=>{
  for(const kind of ['DATABASE','DATABASE PROPERTIES','SUBSCRIPTION','SUBSCRIPTION TABLE']){
    const listing=Buffer.concat([toc(),Buffer.from(`900; 0 0 ${kind} - synthetic owner\n`)]);
    assert.equal(projectToc(listing).kinds[kind],1);
    assert.throws(()=>normalizedToc(listing),/RESTORE_TOC_SCOPE/);
  }
});
test('unknown and legacy-only descriptors refuse with no free names or owners',()=>{
  const canary='secret_'+randomBytes(24).toString('hex');
  for(const kind of [canary,'UNRECOGNIZED NATIVE DESCRIPTOR','<Init>','ACL LANGUAGE','BLOB','BLOB COMMENTS','WARNING']){
    assert.throws(()=>projectToc(Buffer.concat([toc(),Buffer.from(`900; 0 0 ${kind} public ${canary} ${canary}\n`)])),error=>{
      const receipt=closedFailure(error,'project_toc');assert.equal(receipt.code,'PHASE_A_TOC_KIND');
      assert.equal(receipt.toc.candidate,['ACL LANGUAGE','BLOB','BLOB COMMENTS','WARNING'].includes(kind)?kind:null);
      assert.match(receipt.toc.prefixSha256,/^[a-f0-9]{64}$/);assert.equal(JSON.stringify(receipt).includes(canary),false);return true;
    });
  }
});
test('kind failure diagnostic rejects forged field names values and unbounded ordinals',()=>{
  const canary='private_'+randomBytes(24).toString('hex');
  const valid={entryOrdinal:200,candidate:'BLOB COMMENTS',prefixSha256:hash(canary)};
  const project=v=>closedFailure(phaseFailure('PHASE_A_TOC_KIND',{tocDiagnostic:v}),'project_toc');
  assert.deepEqual(project(valid).toc,valid);
  for(const change of [{entryOrdinal:0},{entryOrdinal:30001},{entryOrdinal:'1'},{candidate:canary},{prefixSha256:canary},
    {rawLine:canary},{toJSON:()=>canary},{prefixSha256:{toJSON:()=>canary}}]){
    const receipt=project({...valid,...change});assert.equal(receipt.toc,null);assert.equal(JSON.stringify(receipt).includes(canary),false);
  }
});
test('complete descriptor inventory never expands schema names or required native tables',()=>{
  const canary='unknown_'+randomBytes(24).toString('hex');
  for(const kind of PG17_TOC_KINDS)assert.throws(()=>projectToc(Buffer.concat([toc(),Buffer.from(`900; 0 0 ${kind} ${canary} object owner\n`)])),/PHASE_A_TOC_SCHEMA/);
  assert.throws(()=>projectToc(Buffer.from(toc().toString().replace(/^.*TABLE DATA storage objects.*\n/m,''))),/PHASE_A_TOC_REQUIRED_TABLE/);
});

test('native version SQL hashes stable migration identity and guards every native column', () => {
  const sql=readFileSync(new URL('./sql/native-versions.sql',import.meta.url),'utf8');
  const guard=JSON.parse(sql.match(/actual IS DISTINCT FROM '([\s\S]*?)'::jsonb/)[1]);
  assert.deepEqual(guard,[['auth','schema_migrations','version','character varying(255)',true],
    ['storage','migrations','executed_at','timestamp without time zone',false],
    ['storage','migrations','hash','character varying(40)',true],
    ['storage','migrations','id','integer',true],['storage','migrations','name','character varying(100)',true]]);
  const resultSql=sql.slice(sql.indexOf("SELECT jsonb_build_object(\n 'postgresVersionNum'"));
  const storageSql=resultSql.slice(resultSql.indexOf("'storage'"));
  // Exercise the field projection selected by the real query, not an independent allowlist.
  const omitted=[...storageSql.matchAll(/to_jsonb\(m\)-'([^']+)'/g)].map(match=>match[1]);
  assert.deepEqual(omitted,['executed_at','executed_at']);
  const fingerprint=row=>hash(JSON.stringify(Object.fromEntries(Object.entries(row)
    .filter(([key])=>!omitted.includes(key)).sort(([a],[b])=>a.localeCompare(b)))));
  const row={id:0,name:'synthetic',hash:'a'.repeat(40),executed_at:'2000-01-01'};
  assert.equal(fingerprint(row),fingerprint({...row,executed_at:'2001-01-01'}));
  for(const change of [{id:1},{name:'changed'},{hash:'b'.repeat(40)}])assert.notEqual(fingerprint(row),fingerprint({...row,...change}));
  assert.match(resultSql,/jsonb_agg\(to_jsonb\(m\) ORDER BY to_jsonb\(m\)::text\)[\s\S]*FROM auth\.schema_migrations m/);
  assert.match(sql,/same_a IS DISTINCT FROM same_b OR same_a IS NOT DISTINCT FROM changed/);
  assert.match(sql,/PHASE_A_NATIVE_IDENTITY_WITNESS/);
  assert.equal(/\b(?:CREATE|INSERT|UPDATE|DELETE|ALTER|DROP)\b/.test(sql.replace(/^--.*$/gm,'')),false);
});
test('same-run catalogue and checkpoint retain full native rows including installation timestamps', () => {
  for(const file of ['catalogue.sql','checkpoint.sql']){
    const sql=readFileSync(new URL('./sql/'+file,import.meta.url),'utf8');
    assert.equal(sql.includes("-'executed_at'"),false);
  }
  const checkpoint=readFileSync(new URL('./sql/checkpoint.sql',import.meta.url),'utf8');
  assert.match(checkpoint,/to_jsonb/);
  assert.match(checkpoint,/n\.nspname IN\('auth','storage','public','private'\)/);
  assert.match(checkpoint,/jsonb_agg\(to_jsonb\(t\) ORDER BY to_jsonb\(t\)::text\)/);
});

test('current-product OTP witness pins both actual bodies from the version7 server migration',()=>{
 const migration=readFileSync(new URL('../../../../supabase/migrations/20261006144554_serialiser_renvoi_et_validation_signature.sql',import.meta.url),'utf8');
 const witness=readFileSync(new URL('./sql/current-product-witness.sql',import.meta.url),'utf8');
 const definitions=[...migration.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\([\s\S]*?AS (\$[A-Za-z_]*\$)([\s\S]*?)\2/g)];
 assert.deepEqual(definitions.map(m=>m[1]),['fn_envoyer_otp_signature','fn_signer_contrat_otp']);
 for(const m of definitions){const md5=createHash('md5').update(m[3]).digest('hex');assert(witness.includes("'"+md5+"'"));}
 assert(witness.includes("proowner='postgres'::regrole"));assert(witness.includes("proconfig=ARRAY['search_path=public, extensions']"));
 assert(witness.includes("NOT has_function_privilege('anon',oid,'EXECUTE')"));
});

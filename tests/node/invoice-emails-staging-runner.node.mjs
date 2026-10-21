import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// Les seuls reads réels sont les bytes publics du runner et TypeScript local.
// Le runner est évalué avec FS/Git/stdin/fetch entièrement remplacés en mémoire.
const CHECKOUT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const HERE = `${CHECKOUT}/scripts/ci`;
const require = createRequire(`${CHECKOUT}/package.json`), ts = require('typescript');
const source = readFileSync(`${HERE}/invoice-emails-staging-test.mjs`, 'utf8');
const compiled = ts.transpileModule(source.replaceAll('import.meta.url', JSON.stringify(`file://${HERE}/invoice-emails-staging-test.mjs`)), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true,
});
assert.deepEqual(compiled.diagnostics, []);
const sha = value => createHash('sha256').update(value).digest('hex');
const entry = 'supabase/functions/send-email/index.ts', queue = 'supabase/functions/_shared/facturation-email-queue.ts';
const TARGET = 'a'.repeat(40);
const NOW = Date.parse('2026-10-21T12:00:00.000Z');
const ISOLATED_MISSION = '6bf15d0e-e2a0-4fd7-a903-767679b280bb';

async function closedRun(change = () => {}, args = ['--execute', '/reviewed.json']) {
  const now = NOW, files = new Map(), counters = { network: 0, stdin: 0, writes: 0, dependencyImports: 0 };
  const runtime = { serverSha: TARGET, manifestSha256: sha('{}'),
    missionId: ISOLATED_MISSION, honorairesId: 'f1660000-0000-4000-8000-000000000002', commissionId: 'f1660000-0000-4000-8000-000000000003',
    events: [
      { family: 'HONORAIRES', recipientRole: 'SOIGNANT', emailId: 'f1660000-0000-4000-8000-000000000004', bodySha256: 'b'.repeat(64) },
      { family: 'HONORAIRES', recipientRole: 'ETABLISSEMENT', emailId: 'f1660000-0000-4000-8000-000000000005', bodySha256: 'c'.repeat(64) },
      { family: 'COMMISSION', recipientRole: 'ETABLISSEMENT', emailId: 'f1660000-0000-4000-8000-000000000006', bodySha256: 'd'.repeat(64) },
    ],
    createdAt: new Date(now - 1000).toISOString(), expiresAt: new Date(now + 59 * 60_000).toISOString() };
  const attestation = { project: 'mejpriaetwgtcstbgfid', targetSha: TARGET, allExact: true,
    method: 'Supabase Management API GET /v1/projects/{project}/functions/send-email/body', sourcePins: { [entry]: sha('export const synthetic = 1;') } };
  const contract = { schemaVersion: 1, ready: true, project: 'mejpriaetwgtcstbgfid', checkout: CHECKOUT, targetSha: TARGET,
    intentPath: '/intent.json', runtimePath: '/runtime.json', activationManifestPath: '/manifest.json', sourceAttestationPath: '/attest.json',
    queueHelperSha256: sha('export const syntheticQueue = 1;') };
  const state = { now, contract, runtime, attestation, head: TARGET, dirty: false, committedDrift: false };
  files.set(`${CHECKOUT}/${entry}`, 'export const synthetic = 1;');
  files.set(`${CHECKOUT}/${queue}`, 'export const syntheticQueue = 1;');
  files.set('/manifest.json', '{}');
  change(state);
  files.set('/runtime.json', JSON.stringify(runtime)); files.set('/attest.json', JSON.stringify(attestation));
  contract.runtimeSha256 ??= sha(files.get('/runtime.json')); contract.sourceAttestationSha256 ??= sha(files.get('/attest.json'));
  files.set('/reviewed.json', JSON.stringify(contract));
  let output = '';
  const fakeFs = {
    readFileSync(path, encoding) { assert.ok(files.has(String(path)), `lecture virtuelle inconnue ${path}`); const value = files.get(String(path)); return encoding ? value : Buffer.from(value); },
    realpathSync: path => String(path),
    writeFileSync() { counters.writes++; throw Error('WRITE_FORBIDDEN'); },
    openSync() { counters.writes++; throw Error('WRITE_FORBIDDEN'); }, closeSync() {}, fsyncSync() {},
  };
  const fakeProcess = { argv: ['node', 'runner', ...args], exitCode: 0, stdout: { write(text) { output += text; } },
    stdin: { isTTY: false, async *[Symbol.asyncIterator]() { counters.stdin++; throw Error('NO_CREDENTIALS_IMPORTED'); } } };
  const modules = {
    'node:fs': fakeFs, 'node:crypto': require('node:crypto'), 'node:path': require('node:path'), 'node:url': require('node:url'),
    'node:module': { createRequire() { return () => { counters.dependencyImports++; throw Error('DEPENDENCY_FORBIDDEN'); }; } },
    'node:child_process': { execFileSync(cmd, gitArgs) {
      assert.equal(cmd, 'git');
      if (gitArgs[0] === 'rev-parse') return state.head + '\n';
      if (gitArgs[0] === 'status') return state.dirty ? ' M source\n' : '';
      assert.equal(gitArgs[0], 'show');
      const name = gitArgs[1].slice(TARGET.length + 1), value = files.get(resolve(CHECKOUT, name));
      assert.ok(value); return value + (state.committedDrift ? 'changed' : '');
    } },
  };
  runInNewContext(compiled.outputText, { exports: {}, require: name => { assert.ok(modules[name]); return modules[name]; },
    process: fakeProcess, Buffer, Date: class extends Date { static now() { return state.now; } }, URL, Headers,
    fetch: async () => { counters.network++; throw Error('NETWORK_FORBIDDEN'); } });
  await new Promise(setImmediate);
  assert.equal(counters.network, 0); assert.equal(counters.stdin, 0);
  assert.equal(counters.writes, 0); assert.equal(counters.dependencyImports, 0);
  return { output, code: fakeProcess.exitCode };
}

test('sans --execute : fermé sans credentials, réseau ou écriture', async () => {
  const result = await closedRun(() => {}, []); assert.match(result.output, /SOURCE_ONLY_CLOSED/); assert.equal(result.code, 0);
});
for (const [label, change, expected] of [
  ['contrat fermé', s => { s.contract.ready = false; }, 'REVIEWED_CONTRACT_REQUIRED'],
  ['projet PROD', s => { s.contract.project = 'flripxtsyegjshnhzjkz'; }, 'REVIEWED_CONTRACT_REQUIRED'],
  ['mauvais SHA cible', s => { s.head = 'b'.repeat(40); }, 'EXACT_CLEAN_TARGET_REQUIRED'],
  ['checkout modifié', s => { s.dirty = true; }, 'EXACT_CLEAN_TARGET_REQUIRED'],
  ['empreinte runtime différente', s => { s.contract.runtimeSha256 = '1'.repeat(64); }, 'FRESH_RUNTIME_REQUIRED'],
  ['runtime ancien', s => { s.runtime.createdAt = new Date(NOW - 6 * 60_000).toISOString(); }, 'FRESH_RUNTIME_REQUIRED'],
  ['runtime expiré', s => { s.runtime.expiresAt = new Date(NOW - 1000).toISOString(); }, 'FRESH_RUNTIME_REQUIRED'],
  ['plus de 60 minutes', s => { s.runtime.expiresAt = new Date(NOW + 60 * 60_000).toISOString(); }, 'FRESH_RUNTIME_REQUIRED'],
  ['moins de cinq minutes restantes', s => { s.runtime.expiresAt = new Date(NOW + 5 * 60_000 - 1).toISOString(); }, 'FRESH_RUNTIME_REQUIRED'],
  ['autre mission', s => { s.runtime.missionId = 'f1660000-0000-4000-8000-000000000001'; }, 'EXACT_ISOLATED_TUPLE_REQUIRED'],
  ['échéance absolue dépassée', s => {
    s.now = Date.parse('2026-10-21T23:50:00.000Z');
    s.runtime.createdAt = '2026-10-21T23:49:59.000Z'; s.runtime.expiresAt = '2026-10-22T00:15:00.000Z';
  }, 'EXACT_ISOLATED_TUPLE_REQUIRED'],
  ['mauvaise facture', s => { s.runtime.honorairesId = s.runtime.missionId; }, 'FRESH_RUNTIME_REQUIRED'],
  ['quatrième message', s => { s.runtime.events.push(s.runtime.events[0]); }, 'EXACT_EVENTS_REQUIRED'],
  ['identité de file dupliquée', s => { s.runtime.events[1].emailId = s.runtime.events[0].emailId; }, 'EXACT_EVENTS_REQUIRED'],
  ['rôle étranger', s => { s.runtime.events[2].recipientRole = 'SOIGNANT'; }, 'EXACT_EVENTS_REQUIRED'],
  ['chemin intention relatif', s => { s.contract.intentPath = 'intent.json'; }, 'REVIEWED_CONTRACT_REQUIRED'],
  ['mauvais manifest', s => { s.runtime.manifestSha256 = '2'.repeat(64); }, 'FRESH_RUNTIME_REQUIRED'],
  ['readback faussement CLI', s => { s.attestation.method = 'Supabase CLI official download --use-api'; }, 'OFFICIAL_SOURCE_ATTESTATION_REQUIRED'],
  ['source non attestée', s => { s.attestation.allExact = false; }, 'OFFICIAL_SOURCE_ATTESTATION_REQUIRED'],
  ['source différente', s => { s.attestation.sourcePins[entry] = '3'.repeat(64); }, 'OFFICIAL_SOURCE_ATTESTATION_REQUIRED'],
  ['helper file différent', s => { s.contract.queueHelperSha256 = '4'.repeat(64); }, 'QUEUE_HELPER_PIN_REQUIRED'],
  ['bytes hors commit', s => { s.committedDrift = true; }, 'COMMITTED_SOURCE_PIN_REQUIRED'],
]) test(`préflight ferme ${label} sans effet de bord`, async () => {
  const result = await closedRun(change); assert.equal(result.code, 1); assert.equal(JSON.parse(result.output).code, expected);
});


// Exécute les fonctions utilisées par le runner, avec la frontière Management API
// remplacée. Aucun module Supabase, secret réel, réseau ou écriture n'est disponible.
function runnerBoundaries() {
  const context = { exports: {}, Buffer, Date, URL, Headers,
    process: { argv: ['node', 'runner'], stdout: { write() {} } },
    require(name) {
      if (name === 'node:fs' || name === 'node:child_process' || name === 'node:module') return {};
      assert.ok(['node:crypto', 'node:path'].includes(name)); return require(name);
    },
    fetch() { throw Error('NETWORK_FORBIDDEN'); },
  };
  runInNewContext(compiled.outputText + '\nexports.boundaries = { runtimeServiceDigest, loadRuntimeServiceKey, requireGenerationClosed, readbackSql };', context);
  return context.exports.boundaries;
}
const boundary = runnerBoundaries();
const SYNTHETIC_KEY = 'synthetic-runtime-credential-for-unit-tests';
const KEY_DIGEST = sha(SYNTHETIC_KEY);
const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';
function readOnlySelect(body) {
  assert.equal(body.read_only, true);
  assert.match(body.query, /^SELECT\s/i);
  assert.doesNotMatch(body.query, /\b(?:BEGIN|ROLLBACK|COMMIT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b/i);
  assert.equal((body.query.match(/;/g) || []).length, 1);
}
const vaultEvidence = () => ({ readOnly: true, urlCount: 1, url: STAGE, keyCount: 1, key: SYNTHETIC_KEY });
test('runner : clé Vault correspondant exactement au runtime, lecture seule et réponse effacée', async () => {
  const rows = [{ evidence: vaultEvidence() }], calls = [];
  const key = await boundary.loadRuntimeServiceKey(async (path, body) => {
    calls.push(path); assert.equal(path, '/database/query'); readOnlySelect(body);
    assert.match(body.query, /vault\.decrypted_secrets/); return rows;
  }, KEY_DIGEST);
  assert.equal(key, SYNTHETIC_KEY); assert.deepEqual(calls, ['/database/query']);
  assert.equal(rows[0].evidence.key, '');
});
for (const [label, change] of [
  ['mauvaise clé', r => { r[0].evidence.key = 'synthetic-other-credential-for-unit-tests'; }],
  ['projet PROD', r => { r[0].evidence.url = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
  ['URL absente', r => { r[0].evidence.urlCount = 0; }],
  ['URL dupliquée', r => { r[0].evidence.urlCount = 2; }],
  ['clé absente', r => { r[0].evidence.keyCount = 0; }],
  ['clé dupliquée', r => { r[0].evidence.keyCount = 2; }],
  ['clé avec espaces', r => { r[0].evidence.key += ' '; }],
  ['transaction writable', r => { r[0].evidence.readOnly = false; }],
  ['deux lignes', r => { r.push({ evidence: vaultEvidence() }); }],
  ['aucune ligne', r => { r.length = 0; }],
]) test(`runner ferme Vault : ${label}, aucune suite ni fuite de clé`, async () => {
  const rows = [{ evidence: vaultEvidence() }]; change(rows); let calls = 0;
  await assert.rejects(() => boundary.loadRuntimeServiceKey(async (path, body) => {
    calls++; assert.equal(path, '/database/query'); readOnlySelect(body); return rows;
  }, KEY_DIGEST), { code: 'EXACT_RUNTIME_SERVICE_KEY_REQUIRED' });
  assert.equal(calls, 1);
  for (const row of rows) assert.equal(row.evidence.key, '');
});
test('runner : clé/runtime stable et métadonnées ambiguës ou modifiées refusées', () => {
  const metadata = [{ name: 'SUPABASE_SERVICE_ROLE_KEY', digest: KEY_DIGEST }];
  assert.equal(boundary.runtimeServiceDigest(metadata), KEY_DIGEST);
  assert.equal(boundary.runtimeServiceDigest(metadata, KEY_DIGEST, SYNTHETIC_KEY), KEY_DIGEST);
  assert.throws(() => boundary.runtimeServiceDigest([], KEY_DIGEST), { code: 'SERVICE_KEY_METADATA_DRIFT' });
  assert.throws(() => boundary.runtimeServiceDigest([...metadata, ...metadata]), { code: 'SERVICE_KEY_METADATA_DRIFT' });
  assert.throws(() => boundary.runtimeServiceDigest(metadata, 'b'.repeat(64)), { code: 'SERVICE_KEY_METADATA_DRIFT' });
  assert.throws(() => boundary.runtimeServiceDigest(metadata, KEY_DIGEST, 'synthetic-wrong-runtime-key'), { code: 'SERVICE_KEY_RUNTIME_MISMATCH' });
});
test('runner : génération close pour le tuple exact, chaque relecture refuse une réouverture', async () => {
  const evidence = { readOnly: true, closed: true, allClosed: true }; let calls = 0;
  const mgmt = async (path, body) => {
    calls++; assert.equal(path, '/database/query'); readOnlySelect(body);
    for (const id of [ISOLATED_MISSION, '1de96e4c-9be8-4897-a5bb-7640c05d5706', '41c85ec5-0aa9-4450-a958-a2b5e58e4205', 'fcaa6c97-46c1-4da9-8f74-1395aed616c5']) assert.ok(body.query.includes(id));
    return [{ evidence }];
  };
  await boundary.requireGenerationClosed(mgmt);
  for (const field of ['readOnly', 'closed', 'allClosed']) {
    evidence[field] = false;
    await assert.rejects(() => boundary.requireGenerationClosed(mgmt), { code: 'GENERATION_NOT_CLOSED' });
    evidence[field] = true;
  }
  assert.equal(calls, 4);
});
test('runner : état des factures relu par un seul SELECT sans transaction imbriquée', () => {
  readOnlySelect({ read_only: true, query: boundary.readbackSql(
    'f1660000-0000-4000-8000-000000000002', 'f1660000-0000-4000-8000-000000000003', ISOLATED_MISSION,
    [{ id: 'f1660000-0000-4000-8000-000000000004' }],
  ) });
});

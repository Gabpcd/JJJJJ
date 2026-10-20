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

async function closedRun(change = () => {}, args = ['--execute', '/reviewed.json']) {
  const now = Date.now(), files = new Map(), counters = { network: 0, stdin: 0, writes: 0, dependencyImports: 0 };
  const runtime = { serverSha: TARGET, manifestSha256: sha('{}'),
    missionId: 'f1660000-0000-4000-8000-000000000001', honorairesId: 'f1660000-0000-4000-8000-000000000002', commissionId: 'f1660000-0000-4000-8000-000000000003',
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
  const state = { contract, runtime, attestation, head: TARGET, dirty: false, committedDrift: false };
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
    process: fakeProcess, Buffer, Date, URL, Headers,
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
  ['runtime ancien', s => { s.runtime.createdAt = new Date(Date.now() - 6 * 60_000).toISOString(); }, 'FRESH_RUNTIME_REQUIRED'],
  ['runtime expiré', s => { s.runtime.expiresAt = new Date(Date.now() - 1000).toISOString(); }, 'FRESH_RUNTIME_REQUIRED'],
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

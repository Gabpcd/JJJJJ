import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, readdir, stat, mkdir, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { contextF1, requireReady, ledgerF1, generateOnce, documentBytes, originalBody,
  sha256, checkContract, requireTimeReserveF1, STAGING, ORIGIN } from '../../scripts/ci/f1-cloud-core.mjs';
import { closeContexts, downloadPdf, uiMatrixF1, FORMATS } from '../../scripts/ci/f1-cloud-ui.mjs';
import { pilotF1, projectDocumentEvidenceF1, projectUiEvidenceF1, projectFinalizationF1 } from '../../scripts/ci/f1-cloud-pilot.mjs';

const sha = 'a'.repeat(40), originalId = 'f1300004-4000-4000-8000-000000000004';
const replacementId = 'f1300005-5000-4000-8000-000000000005';
const env = { GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_EVENT_NAME: 'workflow_dispatch',
  GITHUB_REF: 'refs/heads/main', GITHUB_SHA: sha, F1_APPROVED_SHA: sha,
  STAGING_SUPABASE_PROJECT_REF: STAGING, STAGING_SUPABASE_URL: ORIGIN,
  GITHUB_RUN_ID: '123456', GITHUB_RUN_ATTEMPT: '1', RUNNER_TEMP: tmpdir(), F1_JOB_STARTED_UNIX:String(Math.floor(Date.now()/1000)) };
const readiness = { ready: true, sourceSha: sha, catalogueExact: true, generatorSourceExact: true,
  outgoingClosed: true, noActiveCron: true, authCreationReviewed: true, replacementCanonicalWithoutPayment: true,
  retentionReviewed: true, uiDocumentsAccessible: true, uiNetworkContractReviewed: true };
const manifest = { missionId: 'f1300003-3000-4000-8000-000000000003',
  period: { start: '2026-09-21', end: '2026-09-27', week: 39, year: 2026 } };
const secret = 'CANARY-password-email@example.invalid-https://secret.invalid/?jwt=private';
function documentEvidence() {
  const downloads = [], semantic = [];
  for (const role of ['SOIGNANT','ETABLISSEMENT']) for (const slot of ['original','replacement']) {
    const hash = (slot === 'original' ? '1' : '2').repeat(64);
    for (const format of ['pdf','xml']) downloads.push({ role,slot,format,size:100,sha256:hash,duration_ms:1,secret });
    semantic.push({ role,slot,pdf_sha256:hash,pages:1,overflow_count:0,previous_number_and_date:slot==='replacement',secret });
    semantic.push({ role,slot,xml_sha256:hash,type:'380',quantity:4,rate:slot==='original'?20:18,net:slot==='original'?80:72,
      total:slot==='original'?80:72,vat:0,previous_number_and_date:slot==='replacement',secret });
  }
  return { downloads,semantic };
}
function uiEvidence() {
  return {contextsClosed:true,observations:FORMATS.flatMap(({name:format})=>['SOIGNANT','ETABLISSEMENT'].map(role=>({format,role,secret,
    downloads:[false,true].flatMap(reload=>['original','replacement'].map(slot=>({slot,reload,size:100,sha256:(slot==='original'?'1':'2').repeat(64),duration_ms:2,secret}))) }))) };
}
test('UI evidence requires all ten contexts and forty hash-bound PDF downloads, never forwards identity or signed URL',()=>{
  const docs=projectDocumentEvidenceF1(documentEvidence());
  assert(!JSON.stringify(projectUiEvidenceF1(uiEvidence(),docs)).includes(secret));
  for(const mutate of [x=>{x.observations.pop();},x=>{x.observations[0]=x.observations[1];},x=>{x.observations[0].downloads[1]=x.observations[0].downloads[0];},
    x=>{x.observations[0].downloads[0].sha256='9'.repeat(64);},x=>{x.observations[0].downloads[0].duration_ms=-1;},x=>{x.observations[0].downloads[0].reload='true';}]) {
    const bad=uiEvidence();mutate(bad);assert.throws(()=>projectUiEvidenceF1(bad,docs),/F1_UI_EVIDENCE_INCOMPLETE/);
  }
});
async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), 'f1-core-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const ctx = contextF1({ ...env, RUNNER_TEMP: dir });
  return { ctx, ledger: await ledgerF1(ctx) };
}
const response = (id = originalId) => new Response(JSON.stringify({ success: true, facture_id: id,
  type_document: 'FACTURE', pdf_path: 'owned/a.pdf', xml_path: 'owned/a.xml' }), { status: 200 });

test('manual main exact and fixed staging are checked before any operation', () => {
  assert.equal(contextF1(env).run, 'f1-ci-123456-1');
  for (const changes of [{ GITHUB_EVENT_NAME: 'pull_request' }, { GITHUB_REF: 'refs/heads/feature' },
    { GITHUB_REPOSITORY: 'fork/JJJJJ' }, { F1_APPROVED_SHA: 'b'.repeat(40) },
    { STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' }, { STAGING_SUPABASE_PROJECT_REF: 'wnepopwygokbhlqghydb' },
    { STAGING_SUPABASE_URL: 'https://attacker.invalid' }, { GITHUB_RUN_ID: '../other' }, { RUNNER_TEMP: '.' }]) {
    assert.throws(() => contextF1({ ...env, ...changes }), /^Error: F1_/);
  }
});

test('every independent readiness fact must be true, not truthy', () => {
  const ctx = contextF1(env); requireReady(readiness, ctx);
  for (const key of Object.keys(readiness).filter(k => k !== 'sourceSha')) {
    for (const value of [false, undefined, 'true', 1]) assert.throws(() => requireReady({ ...readiness, [key]: value }, ctx));
  }
  assert.throws(() => requireReady({ ...readiness, sourceSha: 'b'.repeat(40) }, ctx));
});

test('distributed readiness file remains blocked; no adapter is implied', async () => {
  await assert.rejects(checkContract(new URL('../../scripts/ci/f1-cloud-readiness.json', import.meta.url), contextF1(env)), /F1_CONTRACT_PENDING/);
});

test('durable private intent exists before operation, result never includes return data', async t => {
  const { ctx, ledger } = await fixture(t);
  const returned = await ledger.once('generate_original', async () => {
    const intent = JSON.parse(await readFile(join(ledger.directory, 'generate_original.intent.json')));
    assert.equal(intent.run, ctx.run); return { token: secret };
  });
  assert.equal(returned.token, secret);
  assert.equal((await stat(ledger.directory)).mode & 0o777, 0o700);
  for (const name of await readdir(ledger.directory)) {
    assert.equal((await stat(join(ledger.directory, name))).mode & 0o777, 0o600);
    assert(!String(await readFile(join(ledger.directory, name))).includes(secret));
  }
  assert.equal(ledger.projection()[0].state, 'response_received');
  assert(Number.isInteger(ledger.projection()[0].duration_ms));
});

test('same effect concurrent submissions and reopening never replay', async t => {
  const { ctx, ledger } = await fixture(t); let calls = 0;
  const outcomes = await Promise.allSettled([1, 2].map(() => ledger.once('generate_original', async () => { calls++; })));
  assert.equal(calls, 1); assert.equal(outcomes.filter(o => o.status === 'rejected').length, 1);
  const reopened = await ledgerF1(ctx);
  await assert.rejects(reopened.once('generate_original', async () => { calls++; }), /ALREADY_ATTEMPTED/);
  assert.equal(calls, 1);
});

test('timeout retains intent and emits no exception secrets; no automatic retry', async t => {
  const { ledger } = await fixture(t); let calls = 0;
  const operation = async () => { calls++; throw Error(secret); };
  await assert.rejects(ledger.once('generate_original', operation), error => error.message === 'F1_EFFECT_AMBIGUOUS');
  await assert.rejects(ledger.once('generate_original', operation), /ALREADY_ATTEMPTED/);
  assert.equal(calls, 1); assert.equal(ledger.projection()[0].state, 'ambiguous');
  assert(!JSON.stringify(ledger.projection()).includes(secret));
});

test('unknown effect and symlink/public private directory refuse before callback', async t => {
  const { ctx, ledger } = await fixture(t); let calls = 0;
  await assert.rejects(ledger.once('payment', async () => calls++), /EFFECT_REFUSED/);
  assert.equal(calls, 0);
  const other = { ...ctx, run: 'f1-ci-123456-2' };
  await symlink(ledger.directory, join(ctx.privateRoot, other.run));
  await assert.rejects(ledgerF1(other), /PERMISSIONS/);
  const publicCtx = { ...ctx, run: 'f1-ci-123456-3' };
  await mkdir(join(ctx.privateRoot, publicCtx.run), { mode: 0o755 });
  await assert.rejects(ledgerF1(publicCtx), /PERMISSIONS/);
});

test('original request has the closed period shape, no final/payment/override', () => {
  assert.deepEqual(originalBody(manifest), { mission_id: manifest.missionId, periode_debut: '2026-09-21',
    periode_fin: '2026-09-27', numero_semaine_iso: 39, annee_iso: 2026, est_facture_finale_mission: false });
  for (const period of [{ ...manifest.period, start: '2026-02-30' }, { ...manifest.period, end: '2026-99-12' },
    { ...manifest.period, week: 54 }, { ...manifest.period, start: '2026-09-28' }]) assert.throws(() => originalBody({ ...manifest, period }), /PERIOD_INVALID/);
});

test('single generation uses only fixed Edge destination, no redirect or retry', async t => {
  const { ctx, ledger } = await fixture(t); let calls = 0;
  const result = await generateOnce({ ctx, ledger, manifest, token: secret, kind: 'original', preflight: readiness,
    fetcher: async (url, options) => {
      calls++; assert.equal(url, `${ORIGIN}/functions/v1/generate-invoice`);
      assert.equal(options.redirect, 'error'); assert.equal(options.method, 'POST');
      assert.equal(options.headers.Authorization, `Bearer ${secret}`);
      assert.deepEqual(JSON.parse(options.body), originalBody(manifest)); return response();
    } });
  assert.equal(result.facture_id, originalId); assert.equal(calls, 1);
});

test('pending preflight, pg_net initiation, unknown kind and extra initiation keys never fetch', async t => {
  const { ctx, ledger } = await fixture(t); let calls = 0;
  const common = { ctx, ledger, manifest, token: secret, preflight: readiness, fetcher: async () => { calls++; return response(); } };
  for (const changes of [{ kind: 'original', preflight: { ...readiness, ready: false } },
    { kind: 'credit' }, { kind: 'replacement', correction: { id: replacementId, initiation: { type: 'pg_net', requestId: 4 } } },
    { kind: 'replacement', correction: { id: replacementId, initiation: { type: 'runner', requestId: null } } }]) {
    await assert.rejects(generateOnce({ ...common, ...changes }));
  }
  assert.equal(calls, 0);
});

for (const mode of ['http500', 'lost_response', 'invalid_json', 'false_success', 'wrong_id']) test(`replacement ${mode} stays ambiguous with one request`, async t => {
  const { ctx, ledger } = await fixture(t); let calls = 0;
  const args = { ctx, ledger, manifest, token: secret, preflight: readiness, kind: 'replacement',
    correction: { id: replacementId, initiation: { type: 'runner' } }, fetcher: async () => {
      calls++;
      if (mode === 'lost_response') throw Error(secret);
      if (mode === 'http500') return new Response(secret, { status: 500 });
      if (mode === 'invalid_json') return new Response(secret);
      if (mode === 'false_success') return Response.json({ success: 'true' });
      return response(originalId);
    } };
  await assert.rejects(generateOnce(args), /AMBIGUOUS/);
  await assert.rejects(generateOnce(args), /ALREADY_ATTEMPTED/); assert.equal(calls, 1);
});

test('download compares actual streamed bytes and removes its temporary file', async () => {
  const bytes = Buffer.from('%PDF-test-local'); let clicks = 0, deletes = 0;
  const document = { number: 'F/Ł-test', pdf: { size: bytes.length, sha256: sha256(bytes) } };
  const page = { waitForEvent: async () => ({ failure: async () => null, suggestedFilename: () => 'F--test.pdf',
    createReadStream: async () => Readable.from([bytes.subarray(0, 3), bytes.subarray(3)]), delete: async () => deletes++ }) };
  const observed = await downloadPdf(page, { click: async () => clicks++ }, document);
  assert.equal(observed.sha256, document.pdf.sha256); assert.equal(clicks, 1); assert.equal(deletes, 1);
  assert(Number.isInteger(observed.duration_ms));
});

test('click failure still waits for download completion and deletes it', async () => {
  let deletes = 0, finished = false;
  const page = { waitForEvent: async () => { await new Promise(r => setTimeout(r, 5)); finished = true; return { delete: async () => deletes++ }; } };
  await assert.rejects(downloadPdf(page, { click: async () => { throw Error(secret); } }, {}), /DOWNLOAD_FAILED/);
  assert(finished); assert.equal(deletes, 1);
});

test('document byte, size and format mismatches reject, never claiming semantic XML proof', () => {
  const bytes = Buffer.from('%PDF-local'), expected = { format: 'pdf', sha256: sha256(bytes), size: bytes.length };
  assert.equal(documentBytes(bytes, expected).sha256, expected.sha256);
  for (const change of [{ size: bytes.length + 1 }, { sha256: '0'.repeat(64) }, { format: 'xml' }]) assert.throws(() => documentBytes(bytes, { ...expected, ...change }));
  assert.throws(() => documentBytes(Buffer.alloc(0), expected));
});

test('all contexts close despite one failing drain or close guard', async () => {
  const events = [];
  await assert.rejects(closeContexts([0, 1].map(slot => ({
    network: { close() { events.push(`stop${slot}`); if (!slot) throw Error(secret); }, async drain() { events.push(`drain${slot}`); if (!slot) throw Error(secret); } },
    context: { async close() { events.push(`close${slot}`); } },
  }))), /CONTEXT_CLOSE_FAILED/);
  for (const slot of [0, 1]) assert(events.includes(`close${slot}`));
});

test('five real device formats declared; incomplete UI contract never loads a browser', async () => {
  assert.equal(new Set(FORMATS.map(f => f.name)).size, 5); let loaded = 0;
  await assert.rejects(uiMatrixF1({ ctx: contextF1(env), preflight: readiness, manifest: {}, loadPlaywright: async () => loaded++ }), /UI_ADAPTER_PENDING/);
  assert.equal(loaded, 0);
});

for (const failure of ['prepare', 'original', 'correction', 'ui', 'documents', 'finalize', 'verify', 'none']) test(`pipeline ${failure}: finite effects, finalization independent, no retry`, async t => {
  const { ctx } = await fixture(t); const calls = []; let edge = 0;
  const invoke = async name => { calls.push(name); if (failure === name) throw Error(secret); };
  const adapter = {
    preflight: async () => readiness,
    prepare: async () => { await invoke('prepare'); return manifest; },
    authenticateGenerator: async () => secret,
    reconcileOriginal: async () => invoke('reconcileOriginal'),
    prepareCorrection: async () => { await invoke('correction'); return { id: replacementId, initiation: { type: 'runner' } }; },
    reconcileDocuments: async () => [], reconcileEffects: async () => invoke('reconcileEffects'),
    verifyDownloads: async () => { await invoke('documents'); return documentEvidence(); },
    finalize: async () => invoke('finalize'), verifyFinalization: async () => {await invoke('verify');return {owned_auth_banned:3,sessions:0,active_admin:0,financial_retention:true,secret};},
  };
  const observed=[];
  const promise = pilotF1({ ctx, adapter, observe:async row=>observed.push(row), ui: async () => { await invoke('ui'); return uiEvidence(); },
    fetcher: async () => { edge++; if (failure === 'original') throw Error(secret); return response(edge === 1 ? originalId : replacementId); } });
  if (failure === 'none') {
    const result = await promise; assert.equal(result.success, true); assert.equal(edge, 2); assert(!JSON.stringify(result).includes(secret));
  } else await assert.rejects(promise, error => error.message === 'F1_PILOT_FAILED_RECONCILE_REQUIRED');
  assert(calls.includes('finalize')); assert(edge <= 2);
  assert(calls.includes('verify'));
  assert(!JSON.stringify(observed).includes(secret));
  if(['finalize','verify'].includes(failure))assert(observed.some(x=>x.phase===(failure==='finalize'?'finalize_auth':'verify_finalization')&&x.state==='failed'&&x.code.startsWith('F1_')));
  else assert(observed.some(x=>x.phase==='verify_finalization'&&x.state==='succeeded'&&x.finalization.owned_auth_banned===3));
});

test('document evidence strips arbitrary fields and refuses duplicate roles, hashes not downloaded and missing semantic proof', () => {
  const report = documentEvidence();
  assert(!JSON.stringify(projectDocumentEvidenceF1(report)).includes(secret));
  for (const mutate of [x=>{x.downloads.pop();},x=>{x.semantic[0].pdf_sha256='3'.repeat(64);},
    x=>{x.downloads[0].role='ADMIN';},x=>{x.semantic[0]=x.semantic[2];},x=>{x.downloads[0].duration_ms='1';}]) {
    const changed=structuredClone(report);mutate(changed);assert.throws(()=>projectDocumentEvidenceF1(changed),/EVIDENCE_INCOMPLETE/);
  }
});

test('matrix lifecycle visits 10 isolated contexts, downloads 40 times, closes before return, and never inherits credentials', async () => {
  const bytes = Buffer.from('%PDF-protocol-test'); let created = 0, closed = 0, downloads = 0, reloads = 0, captures = 0;
  const documents = ['original', 'replacement'].map((slot, i) => ({ id: i ? replacementId : originalId,
    kind: 'FACTURE', slot, number: `F-${i}`, pdf: { size: bytes.length, sha256: sha256(bytes) } }));
  let downloadName;
  const engine = { async launch(options) {
    assert(!Object.values(options.env).includes(secret));
    return { async newContext() {
      created++; let role;
      const page = {
        setDefaultTimeout() {}, setDefaultNavigationTimeout() {}, on() {}, async goto() {},
        locator() { return {filter(){return this;},locator(){return this;},first(){return this;},getByText(){return this;},getByRole(type,options){return page.getByRole(type,options);}}; },
        getByText(){return {};},
        getByLabel(label) { return { async fill(value) { if (label === 'Email') role = value; } }; },
        getByRole(type, { name }) { return { async evaluate() {}, async click() {
          if (name.startsWith('Télécharger le PDF ')) downloadName = name.slice('Télécharger le PDF '.length) + '.pdf';
        } }; },
        async waitForEvent(event) {
          assert.equal(event, 'download'); downloads++;
          return { failure: async () => null, suggestedFilename: () => downloadName,
            createReadStream: async () => Readable.from([bytes]), delete: async () => {} };
        }, async reload() { reloads++; assert(role); },
      };
      return { async routeWebSocket() {}, async newPage() { return page; }, async close() { closed++; } };
    }, async close() { assert.equal(created, closed); } };
  } };
  const expect = () => ({ async toHaveURL() {}, async toHaveCount() {}, async toBeVisible() {}, async toBeEnabled() {} });
  const report = await uiMatrixF1({ ctx: contextF1(env), preflight: readiness,
    manifest: { members: [{ role: 'SOIGNANT', email: 's@example.invalid', password: secret }, { role: 'ETABLISSEMENT', email: 'e@example.invalid', password: secret }] },
    documents, env: { PATH: '/bin', SUPABASE_SERVICE_ROLE_KEY: secret, STAGING_SUPABASE_ACCESS_TOKEN: secret },
    loadPlaywright: async () => ({ webkit: engine, chromium: engine, expect, devices: {} }),
    installNetwork: async () => ({ close() {}, async drain() {}, async assert() {} }),
    openScreen: async () => {}, capture: async () => { captures++; },
  });
  assert.equal(created, 10); assert.equal(closed, 10); assert.equal(downloads, 40); assert.equal(reloads, 10); assert.equal(captures, 20);
  assert.equal(report.observations.length, 10); assert.equal(report.contextsClosed, true);
  assert(!JSON.stringify(report).includes(secret));
});

test('network adapter setup failure still closes the just-created context and every browser', async () => {
  let contextsClosed = 0, browsersClosed = 0;
  const engine = { async launch() { return { async newContext() { return { async close() { contextsClosed++; } }; }, async close() { browsersClosed++; } }; } };
  await assert.rejects(uiMatrixF1({ ctx: contextF1(env), preflight: readiness,
    manifest: { members: [{ role: 'SOIGNANT' }, { role: 'ETABLISSEMENT' }] },
    loadPlaywright: async () => ({ webkit: engine, devices: {} }),
    installNetwork: async () => { throw Error(secret); }, openScreen: async () => {}, capture: async () => {},
  }), error => error.message === 'F1_UI_FAILED_CONTEXTS_FINALIZED');
  assert.equal(contextsClosed, 1); assert.equal(browsersClosed, 1);
});

test('UI failures retain role/format/phase and a hash, never exception text or arbitrary identity',async()=>{
  const observed=[];let closed=0;
  const engine={async launch(){return{async newContext(){throw Error(secret);},async close(){closed++;}};}};
  await assert.rejects(uiMatrixF1({ctx:contextF1(env),preflight:readiness,manifest:{members:[{role:'SOIGNANT'},{role:'ETABLISSEMENT'}]},documents:[],
    installNetwork:async()=>{},openScreen:async()=>{},capture:async()=>{},observe:async value=>observed.push(value),loadPlaywright:async()=>({webkit:engine,chromium:engine,devices:{}})}),/UI_FAILED_CONTEXTS_FINALIZED/);
  assert.equal(closed,1);const failed=observed.find(x=>x.state==='failed');assert.equal(failed.format,'iphone');assert.equal(failed.role,'SOIGNANT');assert.equal(failed.phase,'context');
  assert.equal(failed.exception_sha256,sha256(secret));assert(!JSON.stringify(observed).includes(secret));
});


test('time reserve refuses stale, missing and future job clocks without starting a timer',()=>{
  const now=1800000000000;
  for(const jobStartedUnix of [undefined,'bad',String(now/1000+1),String(now/1000-16*60-1)])assert.throws(()=>requireTimeReserveF1({jobStartedUnix},now),/TIME_RESERVE/);
  requireTimeReserveF1({jobStartedUnix:String(now/1000-16*60)},now);
});

test('closure proof is typed, strips private fields, and cannot claim full retention for a partial fixture',()=>{
  const row={owned_auth_banned:3,sessions:0,active_admin:0,financial_retention:true,secret};
  assert.deepEqual(projectFinalizationF1(row,true),{owned_auth_banned:3,sessions:0,active_admin:0,financial_retention:true});
  for(const delta of [{owned_auth_banned:4},{owned_auth_banned:'3'},{sessions:1},{active_admin:1},{financial_retention:'true'},{financial_retention:false},{owned_auth_banned:2}])assert.throws(()=>projectFinalizationF1({...row,...delta},true),/FINALIZATION_EVIDENCE/);
  assert.equal(projectFinalizationF1({...row,owned_auth_banned:1,financial_retention:false}).financial_retention,false);
});

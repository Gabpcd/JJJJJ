import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, readdir, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { manifestF1, validateActorF1, periodFromReceiptF1, createAdapterF1, loadSqlTemplatesF1, validateReconciliationF1 } from '../../scripts/ci/f1-cloud-adapter.mjs';
import { sqlManifestF1, transactionF1, reconcileSqlF1, catalogueSqlF1 } from '../../scripts/ci/f1-cloud-sql.mjs';
import { STAGING, ORIGIN } from '../../scripts/ci/f1-cloud-core.mjs';

const secret = 'CANARY-private-password-jwt-sql@example.invalid';
const ctx = { sha: 'a'.repeat(40), ref: STAGING, run: 'f1-ci-1234-1', jobStartedUnix:String(Math.floor(Date.now()/1000)) };
const catalog = { queuedRequests:0, commissionHelper:'c793ac81eaef0fe18fb5920c9264c675', routines: 'a'.repeat(32), triggers: 'b'.repeat(32), columns: 'c'.repeat(32), activeCrons: 0,
  runningCrons: 0, generationUrlAbsent: true, supportStagingExact: true };
const contract = { ready: true, sourceSha: ctx.sha, catalogueExact: true, generatorSourceExact: true,
  outgoingClosed: true, noActiveCron: true, authCreationReviewed: true, replacementCanonicalWithoutPayment: true,
  retentionReviewed: true, uiDocumentsAccessible: true, uiNetworkContractReviewed: true, catalogue: catalog,
  edge: Object.fromEntries(['generate-invoice', 'send-email', 'notify-support'].map(slug => [slug, { version: 16, verify_jwt: false, ezbr_sha256: 'd'.repeat(64) }])) };
const env = { STAGING_SUPABASE_ACCESS_TOKEN: secret, STAGING_SUPABASE_SERVICE_ROLE_KEY: `${secret}-service`, STAGING_SUPABASE_ANON_KEY: 'public-key' };
const makeUser = (member, m) => ({ id: member.id, email: member.email, email_confirmed_at: '2026-10-01T10:00:00Z',
  app_metadata: { role: member.authRole, est_compte_test: true, jolene_f1_owner: m.sql.ownerMarker }, banned_until: null });
const receipt = m => ({ runId: m.sql.runId, missionId: m.missionId, periodeDebut: '2026-09-21', periodeFin: '2026-09-27',
  presenceIdReserve:m.sql.ids.presence, montantOriginal: 80, montantRemplacement: 72, qualificationVerifiee: false, signatureSynthetique: true, mfaProuve: false });

test('private manifest plans every actor before effects and excludes credentials from exact SQL shape', () => {
  const m = manifestF1(ctx), sql = sqlManifestF1(m);
  assert.equal(new Set([...m.members, m.admin].map(x => x.password)).size, 3);
  for (const actor of [...m.members, m.admin]) {
    assert(actor.password.length >= 32); assert(!JSON.stringify(sql).includes(actor.password));
    validateActorF1(makeUser(actor, m), actor, m);
  }
  assert.equal(sql.sqlActors.admin.id, m.admin.id); assert(!JSON.stringify(sql).includes('password'));
  const changed = structuredClone(m); changed.sql.actors.soignant.id = changed.sql.ids.mission;
  assert.throws(() => sqlManifestF1(changed), /SQL_MANIFEST/);
  changed.sql.projectRef = 'flripxtsyegjshnhzjkz'; assert.throws(() => sqlManifestF1(changed), /SQL_MANIFEST/);
});

test('Auth response ownership requires actual role/confirmed TEST/marker and exact actor, never truthy values', () => {
  const m = manifestF1(ctx), actor = m.members[0], user = makeUser(actor, m);
  for (const mutate of [x => { x.id = m.members[1].id; }, x => { x.email = secret; }, x => { x.app_metadata.est_compte_test = 'true'; },
    x => { x.app_metadata.role = 'ADMIN_PLATEFORME'; }, x => { x.app_metadata.jolene_f1_owner = 'other'; },
    x => { x.email_confirmed_at = null; }, x => { x.deleted_at = '2026-01-01'; }, x => { x.banned_until = '2100-01-01'; }]) {
    const bad = structuredClone(user); mutate(bad); assert.throws(() => validateActorF1(bad, actor, m), /^Error: F1_AUTH_OWNERSHIP$/);
  }
});

test('SQL receipts keep the real ISO week and cannot silently manufacture 80/72 or a signature/MFA proof', () => {
  const m = manifestF1(ctx);
  assert.deepEqual(periodFromReceiptF1(receipt(m), m), { start: '2026-09-21', end: '2026-09-27', week: 39, year: 2026 });
  for (const delta of [{ montantRemplacement: 80 }, { mfaProuve: true }, { qualificationVerifiee: true }, { periodeFin: '2026-09-28' },
    { periodeDebut: '2026-02-30' }, { runId: 'foreign' }]) assert.throws(() => periodFromReceiptF1({ ...receipt(m), ...delta }, m));
});

test('exact SQL files load unchanged, transaction guards precede writes and no password enters any query', async () => {
  const templates = await loadSqlTemplatesF1(), m = manifestF1(ctx);
  const sql = transactionF1('prepare', m, templates.prepare, catalog);
  assert(sql.startsWith('BEGIN;')); assert(sql.endsWith('COMMIT;')); assert(sql.indexOf('F1_CATALOGUE_DRIFT') < sql.indexOf('INSERT INTO public.soignants'));
  for (const actor of [...m.members, m.admin]) assert(!sql.includes(actor.password));
  assert.throws(() => transactionF1('delete', m, templates.prepare, catalog));
  assert.throws(() => transactionF1('correction', m, templates.correction, catalog), /ORIGINAL_REQUIRED/);
  assert.throws(() => transactionF1('prepare', m, templates.prepare, { ...catalog, columns: null }));
  assert(!reconcileSqlF1(m).includes('DELETE')); assert(!catalogueSqlF1().includes('SELECT decrypted_secret'));
});

async function setup(t, { alterCatalog, failCreateSlot, ambiguousLogout = false } = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'f1-adapter-test-')); t.after(() => rm(dir, { recursive: true, force: true }));
  const users = new Map(), calls = []; let m, creates = 0;
  const fetcher = async (url, options) => {
    calls.push({ url, method: options.method, body: options.body });
    assert.equal(options.redirect, 'error');
    if (url.startsWith('https://api.github.com/')) {
      assert(!Object.values(options.headers).some(x => x.includes(secret)), 'no Supabase credential sent to public GitHub');
      return Response.json({ ref: 'refs/heads/main', object: { type: 'commit', sha: ctx.sha } });
    }
    if (url.endsWith('/functions')) return Response.json(Object.entries(contract.edge).map(([slug, x]) => ({ ...x, slug, status: 'ACTIVE' })));
    if (url.endsWith('/database/query')) {
      const request = JSON.parse(options.body);
      if (request.query === catalogueSqlF1()) { assert.equal(request.read_only, true); return Response.json([{ catalogue: alterCatalog ?? catalog }]); }
      m = JSON.parse(await readFile(join(dir, 'manifest.private.json')));
      if (request.query.startsWith('BEGIN;')) {
        assert.equal(request.read_only, false); assert.equal(users.size, 3); return Response.json([{ receipt: receipt(m) }]);
      }
      assert.equal(request.read_only, true);
      return Response.json([{ receipt: { actors: [...users.values()].map(u => ({ id: u.id, owned: true, banned: !!u.banned_until, confirmed: true })),
        sessions: 0, adminActive: 0 } }]);
    }
    assert(url.startsWith(`${ORIGIN}/auth/v1/`));
    if (url === `${ORIGIN}/auth/v1/admin/users` && options.method === 'POST') {
      m = JSON.parse(await readFile(join(dir, 'manifest.private.json')));
      const body = JSON.parse(options.body); const member = [...m.members, m.admin][creates++];
      assert.equal(body.id, member.id); assert.equal(body.email_confirm, true); assert.equal(body.password, member.password);
      assert.equal(body.app_metadata.jolene_f1_owner, m.sql.ownerMarker);
      assert.equal((await stat(join(dir, 'manifest.private.json'))).mode & 0o777, 0o600);
      if (creates - 1 === failCreateSlot) throw Error(secret);
      const user = makeUser(member, m); users.set(user.id, user); return Response.json(user);
    }
    if (url === `${ORIGIN}/auth/v1/token?grant_type=password`) {
      assert.equal(options.headers.apikey, 'public-key'); assert.equal(options.headers.Authorization, 'Bearer public-key');
      return Response.json({ user: users.get(m.members[0].id), access_token: secret });
    }
    if (url === `${ORIGIN}/auth/v1/logout?scope=global`) {
      assert.equal(options.headers.Authorization, `Bearer ${secret}`); assert.equal(options.headers.apikey, `${secret}-service`);
      if (ambiguousLogout) throw Error(secret); return new Response(null, { status: 204 });
    }
    const id = url.slice(`${ORIGIN}/auth/v1/admin/users/`.length), user = users.get(id);
    if (!user) return new Response(null, { status: 404 });
    if (options.method === 'PUT') { assert.deepEqual(JSON.parse(options.body), { ban_duration: '876000h' }); user.banned_until = '2126-10-01T00:00:00Z'; }
    else assert.equal(options.method, 'GET');
    return Response.json(user);
  };
  const adapter = createAdapterF1({ env, contract, fetcher, analyzePdf: async () => ({}), verifyUiEffects: async () => {} });
  return { dir, adapter, users, calls };
}

test('three Auth creations + exact SQL then global logout/ban; retained finance is never deleted and private tokens never enter SQL', async t => {
  const { dir, adapter, calls, users } = await setup(t);
  await adapter.preflight(ctx); const manifest = await adapter.prepare(ctx, dir); assert(manifest.period);
  await adapter.authenticateGenerator(); await adapter.finalize(ctx, dir); await adapter.verifyFinalization(ctx, dir);
  assert.equal(users.size, 3); assert([...users.values()].every(u => !!u.banned_until));
  assert.equal(calls.filter(c => c.method === 'PUT').length, 3); assert(!calls.some(c => c.method === 'DELETE'));
  for (const c of calls.filter(c => c.url.endsWith('/database/query'))) assert(!c.body.includes(secret));
  for (const name of (await readdir(dir)).filter(x => x.includes('.intent.'))) assert(!String(await readFile(join(dir, name))).includes(secret));
});

test('preflight catalogue drift refuses before any Auth or SQL mutation', async t => {
  const { adapter, calls } = await setup(t, { alterCatalog: { ...catalog, activeCrons: 1 } });
  await assert.rejects(adapter.preflight(ctx), /CATALOGUE_DRIFT/);
  assert(!calls.some(c => c.url.startsWith(ORIGIN)));
  assert(calls.filter(c => c.url.endsWith('/database/query')).every(c => JSON.parse(c.body).read_only === true));
});

test('lost second creation does not create a fourth user; finalization bans only the independently owned partial cohort', async t => {
  const { adapter, dir, users, calls } = await setup(t, { failCreateSlot: 1 });
  await adapter.preflight(ctx); await assert.rejects(adapter.prepare(ctx, dir), /^Error: F1_ADAPTER_EFFECT_AMBIGUOUS$/);
  assert.equal(calls.filter(c => c.url.endsWith('/auth/v1/admin/users')).length, 2);
  await assert.rejects(adapter.finalize(ctx, dir), /FINALIZATION_UNCERTAIN/);
  await adapter.verifyFinalization(ctx, dir); assert.equal(users.size, 1); assert([...users.values()].every(u => !!u.banned_until));
});

test('ambiguous logout still bans all three, then independent session read runs; no logout replay', async t => {
  const { adapter, dir, users, calls } = await setup(t, { ambiguousLogout: true });
  await adapter.preflight(ctx); await adapter.prepare(ctx, dir); await adapter.authenticateGenerator();
  await assert.rejects(adapter.finalize(ctx, dir), /FINALIZATION_UNCERTAIN/); await adapter.verifyFinalization(ctx, dir);
  assert([...users.values()].every(u => !!u.banned_until));
  assert.equal(calls.filter(c => c.url.endsWith('/logout?scope=global')).length, 1);
});

test('distributed pending contract prevents credentials/network access entirely', async () => {
  let calls = 0; const pending = JSON.parse(await readFile(new URL('../../scripts/ci/f1-cloud-readiness.json', import.meta.url)));
  const adapter = createAdapterF1({ env: {}, contract: pending, fetcher: async () => calls++ });
  await assert.rejects(adapter.preflight(ctx), /CONTRACT_PENDING/); assert.equal(calls, 0);
});

test('reconciliation rejects foreign identities, payment and silent mutation before any document transport', () => {
  const m = manifestF1(ctx); m.period = periodFromReceiptF1(receipt(m), m);
  for (const row of [{ actors: [] }, { actors: [...m.members, m.admin].map(x => ({ id: x.id, owned: true, confirmed: true })),
    adminActive: 0, payments: 1, transfers: 0, emailsQueued: 0, emailRetries: 0, messages: 0 }]) {
    assert.throws(() => validateReconciliationF1(row, m, 'replacement'), /F1_/);
  }
});

test('corrected helper is required before any Auth creation even if other catalogue fields match',async t=>{
  const {adapter,calls}=await setup(t,{alterCatalog:{...catalog,commissionHelper:'0'.repeat(32)}});
  await assert.rejects(adapter.preflight(ctx),/CATALOGUE_DRIFT/);assert(!calls.some(c=>c.url.startsWith(ORIGIN)));
});
test('synthetic presence is absent before correction and exactly the retained owned 4h history afterward',()=>{
  const m=manifestF1(ctx);m.period=periodFromReceiptF1(receipt(m),m);
  const row={actors:[...m.members,m.admin].map(x=>({id:x.id,owned:true,confirmed:true})),adminActive:0,payments:0,paymentsSoignant:0,paymentsMission:0,transfers:0,emailsQueued:0,emailRetries:0,messages:0,
    mission:{id:m.missionId,soignant:m.members[0].id,etablissement:m.members[1].id,status:'EN_COURS',hours:8,effectiveHours:4,rate:18,net:144,commission:21.6},
    syntheticPresence:[{id:m.sql.ids.presence,mission:m.missionId,soignant:m.members[0].id,hours:4,adjusted:4,litige:m.sql.ids.litige,arrival:false,departure:false,validated:false}],documents:[]};
  // Reach the next independent check only when the exact presence is valid.
  assert.throws(()=>validateReconciliationF1(row,m,'replacement'),/DOCUMENT_COUNT/);
  for(const change of [x=>x.syntheticPresence=[],x=>x.syntheticPresence[0].id=m.admin.id,x=>x.syntheticPresence[0].hours=3,x=>x.syntheticPresence[0].arrival=true,x=>x.syntheticPresence[0].validated=true]){
    const bad=structuredClone(row);change(bad);assert.throws(()=>validateReconciliationF1(bad,m,'replacement'),/SYNTHETIC_PRESENCE/);
  }
  assert.throws(()=>validateReconciliationF1(row,m,'original'),/SYNTHETIC_PRESENCE/);
});

test('independent commissions 12→10.80 and all payment tables are checked, not inferred from honoraires',()=>{
  const m=manifestF1(ctx);m.period=periodFromReceiptF1(receipt(m),m);
  const ids=['f1300004-4000-4000-8000-000000000004','f1300005-5000-4000-8000-000000000005'];
  const commissionsIds=['f1400004-4000-4000-8000-000000000004','f1400005-5000-4000-8000-000000000005'];
  const documents=ids.map((id,i)=>({id,kind:'FACTURE',nature:i?'REMPLACEMENT':'ORIGINALE',status:i?'EMISE':'REMPLACEE',predecessor:i?ids[0]:null,
    soignant:m.members[0].id,etablissement:m.members[1].id,quantity:4,rate:i?18:20,net:i?72:80,vat:0,total:i?72:80,paid:false,final:false,
    periodStart:m.period.start,periodEnd:m.period.end,versionCount:1,versions:[{pdf_s3_key:`${i}.pdf`,facturx_xml_url:`${i}.xml`}],pdf:{key:`${i}.pdf`},xml:{key:`${i}.xml`}}));
  const row={actors:[...m.members,m.admin].map(x=>({id:x.id,owned:true,confirmed:true})),adminActive:0,payments:0,paymentsSoignant:0,paymentsMission:0,transfers:0,emailsQueued:0,emailRetries:0,messages:0,
    mission:{id:m.missionId,soignant:m.members[0].id,etablissement:m.members[1].id,status:'EN_COURS',hours:8,effectiveHours:4,rate:18,net:144,commission:21.6},
    syntheticPresence:[{id:m.sql.ids.presence,mission:m.missionId,soignant:m.members[0].id,hours:4,adjusted:4,litige:m.sql.ids.litige,arrival:false,departure:false,validated:false}],documents,
    commissions:commissionsIds.map((id,i)=>({id,honoraire:ids[i],predecessor:i?commissionsIds[0]:null,mission:m.missionId,etablissement:m.members[1].id,kind:'FACTURE',status:i?'EMISE':'REMPLACEE',net:i?10.8:12,vat:i?2.16:2.4,total:i?12.96:14.4,
      periodStart:m.period.start,periodEnd:m.period.end,providerLinked:false,immutable:{number:`fixture-${i}`}}))};
  assert.equal(validateReconciliationF1(row,m,'replacement').length,2);
  for(const mutate of [x=>{x.paymentsSoignant=1;},x=>{x.paymentsMission=1;},x=>{x.commissions.pop();},x=>{x.commissions[0].status='EMISE';},
    x=>{x.commissions[1].net=9.6;},x=>{x.commissions[1].predecessor=null;},x=>{x.commissions[1].providerLinked=true;},x=>{x.mission.commission=20.4;}]){
    const bad=structuredClone(row);mutate(bad);assert.throws(()=>validateReconciliationF1(bad,m,'replacement'),/^Error: F1_/);
  }
  m.snapshots.originalCommission={number:'old-number'};assert.throws(()=>validateReconciliationF1(row,m,'replacement'),/ORIGINAL_COMMISSION_CHANGED/);
});

test('pre-existing outgoing request refuses before Auth and cannot be counted as this fixture request',async t=>{
  const {adapter,calls}=await setup(t,{alterCatalog:{...catalog,queuedRequests:1}});
  await assert.rejects(adapter.preflight(ctx),/CATALOGUE_DRIFT/);assert(!calls.some(c=>c.url.startsWith(ORIGIN)));
});


test('exhausted setup reserve refuses before any Auth request or private fixture is created',async t=>{
  const {adapter,dir,calls}=await setup(t);await adapter.preflight(ctx);const before=calls.length;
  await assert.rejects(adapter.prepare({...ctx,jobStartedUnix:String(Math.floor(Date.now()/1000)-17*60)},dir),/TIME_RESERVE/);
  assert.equal(calls.length,before);assert.deepEqual(await readdir(dir),[]);
});

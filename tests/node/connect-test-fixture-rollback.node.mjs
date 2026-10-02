import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { context, observationSql, validateObservation, renderRollback, executeWitness, loadSeed, SEED_SHA256, REVIEWED_CATALOGUE } from '../../scripts/ci/connect-test-fixture-rollback.mjs';
const source='a'.repeat(40),seed=loadSeed();
const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'pull_request',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',PR_HEAD_REPOSITORY:'Gabpcd/JJJJJ',
  GITHUB_RUN_ID:'123456789',GITHUB_RUN_ATTEMPT:'1',SOURCE_SHA:source,STAGING_SUPABASE_PROJECT_REF:'mejpriaetwgtcstbgfid',STAGING_SUPABASE_ACCESS_TOKEN:'private-management-token'};
const empty=()=>({catalogue:{...REVIEWED_CATALOGUE,commissionHelper:'c'.repeat(32),queuedRequests:0,activeCrons:0,runningCrons:0,generationUrlAbsent:true,supportStagingExact:true},
  snapshot:{auth:[],soignants:[],etablissements:[],onboarding:[],invoices:[],commissions:[],mission:null,payments:0,paymentClaims:0,emailQueue:0,emailRetries:0,activeAdmin:0},
  authInsertTriggers:0,externalNotifications:'1'.repeat(32),emailQueue:'2'.repeat(32),externalQueues:'3'.repeat(32),cohort:{mandats:0,creneaux:0,notifications:0,audit:0,preferences:0,sessions:0,identities:0}});
const sentinel=[{proof:'CONNECT_TEST_FIXTURE_SEED_ROLLBACK',rolled_back:true,seed_sha256:SEED_SHA256}];
function transport({lost=false,missing=false,drift=false}={}) {
  const calls=[];
  const fetcher=async(url,options)=>{
    const request=JSON.parse(options.body);calls.push({url,...request});
    assert.equal(url,'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
    assert.equal(options.redirect,'error');
    assert.equal(request.read_only,false);
    if(request.query.startsWith('BEGIN READ ONLY;'))return {ok:true,redirected:false,json:async()=>[{observation:drift&&calls.length===3?{...empty(),cohort:{...empty().cohort,mandats:1}}:empty()}]};
    if(lost)throw Error('secret that must not escape');
    return {ok:true,redirected:false,json:async()=>missing?[]:sentinel};
  };
  return {calls,fetcher};
}

test('CI staging identity refuses before transport on forks, wrong SHA, non-CI or production',async()=>{
  for(const delta of [{PR_HEAD_REPOSITORY:'fork/JJJJJ'},{SOURCE_SHA:'b'.repeat(40)},{GITHUB_ACTIONS:'false'},{STAGING_SUPABASE_PROJECT_REF:'flripxtsyegjshnhzjkz'}]) {
    let calls=0;await assert.rejects(executeWitness({env:{...env,...delta},localSha:source,seed,fetcher:async()=>{calls++;}}),/CI_CONTEXT_REFUSED/);assert.equal(calls,0);
  }
});
test('pins and Auth triggers reject drift without authorizing fixture creation',()=>{
  const m=context(env,source);validateObservation([{observation:empty()}],m);
  for(const change of [{authInsertTriggers:1},{catalogue:{...empty().catalogue,triggers:'f'.repeat(32)}},{catalogue:{...empty().catalogue,activeCrons:1}},{catalogue:{...empty().catalogue,queuedRequests:1}},{cohort:{...empty().cohort,identities:1}}])
    assert.throws(()=>validateObservation([{observation:{...empty(),...change}}],m),/STAGING_PREFLIGHT_REFUSED/);
});
test('rendered SQL contains exact seed bytes, synthetic Auth only, independent rollback barriers',()=>{
  const m=context(env,source),sql=renderRollback(seed,m,empty());
  const embedded=sql.split(`-- BEGIN EXACT SEED SHA256 ${SEED_SHA256}\n`)[1].split('\n-- END EXACT SEED')[0];assert.equal(embedded,seed);
  assert.equal((sql.match(/^BEGIN;$/gm)||[]).length,1);assert.equal((sql.match(/^ROLLBACK;$/gm)||[]).length,1);assert.doesNotMatch(sql,/^COMMIT;/m);
  assert.ok(sql.indexOf('SAVEPOINT connect_fixture_exact_seed;')<sql.indexOf('INSERT INTO auth.users'));
  assert.ok(sql.indexOf('ROLLBACK TO SAVEPOINT connect_fixture_exact_seed;')>sql.indexOf('-- END EXACT SEED'));
  assert.ok(sql.lastIndexOf('CONNECT_SEED_OBSERVATION_CHANGED')>sql.indexOf('ROLLBACK TO SAVEPOINT'));
  assert.match(sql,/fn_verifier_pre_facturation\([^)]*::uuid,\(receipt->>'periodeDebut'\)::date,\(receipt->>'periodeFin'\)::date\)/);
  assert.doesNotMatch(sql,/encrypted_password|INSERT INTO auth\.(sessions|identities)|DISABLE TRIGGER|app\.test_mode','true'/);
  for(const a of m.members)assert.ok(!sql.includes(a.password));
  assert.throws(()=>renderRollback(seed+'\n',m,empty()),/SEED_SOURCE_DRIFT/);
  assert.match(observationSql(m),/tgtype::int & 20/);assert.match(sql,/t\.tgenabled::text/);
});
test('simulated SQL transport requires rollback sentinel and separate read; it is not a PostgreSQL execution',async()=>{
  const h=transport(),reports=[];const r=await executeWitness({env,localSha:source,seed,fetcher:h.fetcher,record:x=>reports.push(structuredClone(x))});
  assert.equal(r.success,true);assert.equal(r.rollbackSentinel,true);assert.equal(r.independentRead,true);
  assert.deepEqual(h.calls.map(x=>x.query.startsWith('BEGIN READ ONLY;')),[true,false,true]);assert.equal(h.calls.filter(x=>!x.query.startsWith('BEGIN READ ONLY;')).length,1);
  for(const call of [h.calls[0],h.calls[2]]){assert.equal(call.read_only,false);assert.match(call.query,/ROLLBACK;$/);assert.match(call.query,/transaction_read_only/);assert.match(call.query,/vault\.decrypted_secrets/);}
  assert.equal(r.authHttp,false);assert.equal(r.edgeCalled,false);assert.equal(r.stripeCalled,false);
  assert.ok(reports.every(x=>!JSON.stringify(x).includes('private-management-token')));
});
test('lost transaction or missing sentinel still rechecks once and never retries',async()=>{
  for(const option of [{lost:true},{missing:true},{drift:true}]) {
    const h=transport(option),r=await executeWitness({env,localSha:source,seed,fetcher:h.fetcher});assert.equal(r.success,false);
    assert.deepEqual(h.calls.map(x=>x.query.startsWith('BEGIN READ ONLY;')),[true,false,true]);assert.equal(h.calls.filter(x=>!x.query.startsWith('BEGIN READ ONLY;')).length,1);
  }
});

test('HTTP diagnostics expose only status and allowlisted SQLSTATE/category, without provider details or retry',async()=>{
  for(const [body,state,category] of [
    [{message:'ERROR:  42501: permission denied for function _crypto_aead_det_decrypt\nsecret-token customer@example.com'},'42501','VAULT_EXECUTE_DENIED'],
    [{error:{code:'25006',message:'secret-token customer@example.com'}},'25006','READ_ONLY_VIOLATION'],
    [{code:'SECRT',message:'secret-token customer@example.com',details:{Authorization:'private-management-token'}},null,'HTTP_REFUSED'],
  ]) {
    let calls=0;const report=await executeWitness({env,localSha:source,seed,fetcher:async()=>{calls++;return {ok:false,status:400,redirected:false,json:async()=>body};}});
    assert.equal(calls,1);assert.equal(report.attempted,false);assert.equal(report.code,'SQL_HTTP_REFUSED');
    assert.deepEqual(report.httpFailures,[{phase:'preflight',httpStatus:400,sqlState:state,category}]);
    assert.doesNotMatch(JSON.stringify(report),/secret-token|customer@|private-management-token|SECRT/);
  }
});
test('Validate PR runs this witness in its serialized staging job before bootstrap, even without a migration',async()=>{
  const workflow=await readFile(new URL('../../.github/workflows/validate-pr.yml',import.meta.url),'utf8');
  const start=workflow.indexOf('group: jolene-supabase-staging-writes'),run=workflow.indexOf('run: node scripts/ci/connect-test-fixture-rollback.mjs');
  assert.ok(start>0&&run>start);assert.ok(run<workflow.indexOf('- name: Synchroniser le schéma main vers le staging'));
  const step=workflow.slice(workflow.lastIndexOf('- name:',run),run);
  assert.match(step,/if: steps\.migration_scope\.outputs\.has_connect_fixture == 'true'/);assert.doesNotMatch(step,/has_migrations/);
  assert.match(step,/SOURCE_SHA: \$\{\{ github\.event\.pull_request\.head\.sha \}\}/);
  assert.match(workflow,/'scripts\/ci\/connect-test-fixture\*\.mjs'/);
});

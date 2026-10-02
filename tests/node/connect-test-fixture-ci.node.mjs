import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync } from 'node:crypto';
import { readFile, mkdtemp, writeFile, stat, rm, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { SOURCE_FILES, recipientKey, sealJournal, openJournal, checkCi, verifyProvenance, resolveStagingApiKeys, runCi } from '../../scripts/ci/connect-test-fixture-ci.mjs';
import { Refusal as FixtureRefusal } from '../../scripts/ci/connect-test-fixture.mjs';

const pair=generateKeyPairSync('rsa',{modulusLength:4096}),pem=pair.publicKey.export({type:'spki',format:'pem'});
const privatePem=pair.privateKey.export({type:'pkcs8',format:'pem'});
const hash=x=>createHash('sha256').update(x).digest('hex'),fp=hash(pair.publicKey.export({type:'spki',format:'der'}));
const mainSha='a'.repeat(40),fixtureSha='b'.repeat(40),tree='c'.repeat(40);
const sources=Object.fromEntries(SOURCE_FILES.map((p,i)=>[p,`reviewed fixture ${i}`]));
const catalogue={routines:'1'.repeat(32),triggers:'2'.repeat(32),columns:'3'.repeat(32),commissionHelper:'4'.repeat(32),queuedRequests:0,activeCrons:0,runningCrons:0,generationUrlAbsent:true,supportStagingExact:true,gateClosed:true,capacitiesEmpty:true,operationsEmpty:true};
const edges=Object.fromEntries(['generate-invoice','send-email','notify-support'].map(p=>[p,{version:3,verify_jwt:false,ezbr_sha256:'a'.repeat(64)}]));
const resolvedKeys={STAGING_SUPABASE_ANON_KEY:'anon-resolved-canary-do-not-export',STAGING_SUPABASE_SERVICE_ROLE_KEY:'service-resolved-canary-do-not-export'};
const env=()=>({GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_REF:'refs/heads/main',EXPECTED_MAIN_SHA:mainSha,GITHUB_SHA:mainSha,GITHUB_RUN_ID:'12345678',GITHUB_RUN_ATTEMPT:'1',GITHUB_TOKEN:'github-token-kept-in-ci',RECIPIENT_PUBLIC_KEY:pem,RECIPIENT_SHA256:fp,
  STAGING_SUPABASE_ACCESS_TOKEN:'management-canary-do-not-export',STRIPE_TEST_SECRET_KEY:'rk_test_canaryNeverExport'});
const local={sha:mainSha,clean:true};
const contract=()=>({schemaVersion:1,ready:true,projectRef:'mejpriaetwgtcstbgfid',reviewedFixtureSha:fixtureSha,reviewedFixtureTree:tree,
  sourcePins:Object.fromEntries(SOURCE_FILES.map(p=>[p,hash(sources[p])])),expiresAt:new Date(Date.now()+3600000).toISOString(),reviewedBy:'independent fixture review',
  pgProof:{runId:'87654321',runAttempt:1,jobName:'Fixture SQL PostgreSQL 17',workflowPath:'.github/workflows/validate-pr.yml',fixtureSqlReviewed:true},
  fixtureContract:{schemaVersion:1,ready:true,projectRef:'mejpriaetwgtcstbgfid',stripePlatformId:'acct_1T9pt0EVhQ7cb53W',seedSha256:hash(sources[SOURCE_FILES[2]]),protocolEnabled:false,capabilityEnabled:false,notificationsTestSkipReviewed:true,catalogue,edges}});
function github(overrides={}) {
  const calls=[];
  const fetcher=async(url,options)=>{
    const u=new URL(url);calls.push({url,options});assert.equal(u.origin,'https://api.github.com');assert.equal(options.redirect,'error');
    let value;
    if(u.pathname.endsWith('/git/ref/heads/main'))value={ref:'refs/heads/main',object:{sha:mainSha,type:'commit'}};
    else if(u.pathname.includes('/git/commits/'))value={sha:fixtureSha,tree:{sha:tree}};
    else if(u.pathname.endsWith('/actions/runs/87654321'))value={id:87654321,run_attempt:1,head_sha:fixtureSha,path:'.github/workflows/validate-pr.yml',repository:{full_name:'Gabpcd/JJJJJ'},head_repository:{full_name:'Gabpcd/JJJJJ'},status:'completed',conclusion:'success'};
    else if(u.pathname.endsWith('/jobs'))value={total_count:1,jobs:[{name:'Fixture SQL PostgreSQL 17',status:'completed',conclusion:'success'}]};
    else if(u.pathname.endsWith('/connect-test-fixture.yml/runs'))value={total_count:1,workflow_runs:[{id:12345678,path:'.github/workflows/connect-test-fixture.yml'}]};
    else if(u.pathname.includes('/contents/')){const path=u.pathname.split('/contents/')[1];assert.equal(u.searchParams.get('ref'),fixtureSha);value={type:'file',encoding:'base64',content:Buffer.from(sources[path]).toString('base64')};}
    else assert.fail(`Unexpected API path: ${u.pathname}`);
    if(overrides.transform)value=overrides.transform(value,u);
    return {ok:true,redirected:false,text:async()=>JSON.stringify(value)};
  };return {fetcher,calls};
}
function management(options={}) {
  const calls=[],base='https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid';
  const fetcher=async(url,init)=>{
    calls.push(url);assert.ok([base,`${base}/api-keys`].includes(url));assert.equal(init.redirect,'error');
    assert.equal(init.headers.Authorization,`Bearer ${env().STAGING_SUPABASE_ACCESS_TOKEN}`);
    if(options.httpFailure===true||options.httpFailure==='keys'&&url.endsWith('/api-keys'))return {ok:false,text:async()=>{assert.fail('A rejected provider body must not be read');}};
    const value=url===base?(options.project??{id:'mejpriaetwgtcstbgfid',status:'ACTIVE_HEALTHY',database:{host:'db.mejpriaetwgtcstbgfid.supabase.co'}})
      :(options.rows??[{name:'anon',api_key:resolvedKeys.STAGING_SUPABASE_ANON_KEY},{name:'service_role',api_key:resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY}]);
    return {ok:true,redirected:false,text:async()=>options.invalidJson?'provider-secret-body':JSON.stringify(value)};
  };return {fetcher,calls};
}
function runner(options={}) {
  const checkpoints=[],privateJournals=[],summaries=[],g=github(options.github),m=management(options.management),calls=[];
  const fetcher=async(url,init)=>{calls.push(url);return url.startsWith('https://api.github.com/')?g.fetcher(url,init):m.fetcher(url,init);};
  const args={env:env(),local,contract:contract(),sources,fetcher,
    writePrivateJournal:async value=>privateJournals.push(structuredClone(value)),
    writeCheckpoint:async value=>checkpoints.push(structuredClone(value)),writeSummary:async value=>summaries.push(value),...options};
  return {args,checkpoints,privateJournals,summaries,g,m,calls};
}

test('versioned contract validates closed or explicitly pinned readiness without enabling a transport',async()=>{
  const versioned=JSON.parse(await readFile(new URL('../../scripts/ci/connect-test-fixture-ci.contract.json',import.meta.url),'utf8'));
  assert.equal(typeof versioned.ready,'boolean');
  let calls=0;
  await assert.rejects(runCi({contract:{...versioned,ready:false},fetcher:()=>{calls++;},prepare:()=>{calls++;}}),/CI_READINESS_CLOSED/);
  assert.equal(calls,0);
  if(versioned.ready===false) {
    for(const key of ['reviewedFixtureSha','reviewedFixtureTree','sourcePins','pgProof','fixtureContract','expiresAt','reviewedBy'])assert.equal(versioned[key],null);
    return;
  }
  const reviewedSources=Object.fromEntries(await Promise.all(SOURCE_FILES.map(async path=>[
    path,await readFile(new URL('../../'+path,import.meta.url),'utf8'),
  ])));
  assert.match(versioned.expiresAt,/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/);
  const expiry=Date.parse(versioned.expiresAt);assert.ok(Number.isFinite(expiry));
  // Structural proof at a deterministic point within the declared window.
  // An expired historical contract must not break unrelated future PRs;
  // the runtime still uses Date.now() and refuses expiration before any effect.
  const checked=checkCi(env(),local,versioned,reviewedSources,expiry-3600000);
  assert.equal(checked.fixtureContract.protocolEnabled,false);
  assert.equal(checked.fixtureContract.capabilityEnabled,false);
  assert.equal(checked.fixtureContract.notificationsTestSkipReviewed,true);
  assert.equal(checked.manifest.sql.sourceSha,mainSha);
  assert.throws(()=>checkCi(env(),local,versioned,reviewedSources,expiry),/CI_CONTRACT/);
  assert.throws(()=>checkCi(env(),local,versioned,reviewedSources,expiry-4*3600000-1),/CI_CONTRACT/);
  await assert.rejects(runCi({env:{...env(),GITHUB_EVENT_NAME:'pull_request'},local,contract:versioned,sources:reviewedSources,
    fetcher:()=>{calls++;},prepare:()=>{calls++;}}),/CI_TRUSTED_MAIN/);
  assert.equal(calls,0);
});
test('exact main, first attempt, expiry, source bytes and explicit SQL review are mandatory',()=>{
  for(const change of [{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_REF:'refs/heads/fix'},{GITHUB_RUN_ATTEMPT:'2'},{EXPECTED_MAIN_SHA:fixtureSha},{GITHUB_REPOSITORY:'fork/JJJJJ'}])assert.throws(()=>checkCi({...env(),...change},local,contract(),sources),/CI_TRUSTED_MAIN/);
  assert.throws(()=>checkCi(env(),{...local,clean:false},contract(),sources),/CI_TRUSTED_MAIN/);
  assert.throws(()=>checkCi(env(),local,{...contract(),expiresAt:new Date(Date.now()-1).toISOString()},sources),/CI_CONTRACT/);
  assert.throws(()=>checkCi(env(),local,contract(),{...sources,[SOURCE_FILES[1]]:'changed'}),/CI_SOURCE_PINS/);
  const c=contract();c.pgProof.fixtureSqlReviewed=false;assert.throws(()=>checkCi(env(),local,c,sources),/CI_PG_PROOF/);
  const checked=checkCi(env(),local,contract(),sources);assert.equal(checked.manifest.sql.sourceSha,mainSha);assert.equal(checked.fixtureContract.sourceSha,mainSha);
});
test('recipient is only the matching RSA4096 public key; authenticated encryption rejects alterations',()=>{
  const c=checkCi(env(),local,contract(),sources),payload={format:'JOLENE_CONNECT_FIXTURE_PRIVATE_V1',projectRef:'mejpriaetwgtcstbgfid',manifest:c.manifest};
  assert.throws(()=>recipientKey(pem,'d'.repeat(64)),/CI_RECIPIENT/);
  assert.throws(()=>recipientKey(pair.privateKey.export({type:'pkcs8',format:'pem'}),fp),/CI_RECIPIENT/);
  const encrypted=sealJournal(payload,c.key);assert.deepEqual(openJournal(encrypted,privatePem,fp),payload);
  const altered={...encrypted,ciphertext:Buffer.from('different ciphertext').toString('base64')};assert.throws(()=>openJournal(altered,privatePem,fp));
  assert.throws(()=>openJournal(encrypted,privatePem,'d'.repeat(64)),/CI_RECIPIENT/);
});
test('GitHub attests the reviewed tree, exact PG run/job, same bytes, and a single dispatch',async()=>{
  await verifyProvenance(env(),contract(),sources,github().fetcher);
  for(const [segment,change,code]of [
    ['/git/ref/',x=>({...x,object:{sha:fixtureSha,type:'commit'}}),'CI_MAIN_MOVED'],
    ['/git/commits/',x=>({...x,tree:{sha:mainSha}}),'CI_REVIEWED_SOURCE'],
    ['/actions/runs/87654321',x=>({...x,conclusion:'failure'}),'CI_SQL_RUN'],
    ['/jobs',x=>({...x,jobs:[]}),'CI_SQL_JOB'],
    ['/connect-test-fixture.yml/runs',x=>({...x,total_count:2}),'CI_PREVIOUS_DISPATCH'],
    ['/contents/',x=>({...x,content:Buffer.from('other source').toString('base64')}),'CI_REVIEWED_BYTES'],
  ])await assert.rejects(verifyProvenance(env(),contract(),sources,github({transform:(x,u)=>u.pathname.includes(segment)?change(x):x}).fetcher),new RegExp(code));
});
test('API keys are resolved only from the verified staging project, in memory without inherited-key fallback',async()=>{
  const m=management();assert.deepEqual(await resolveStagingApiKeys(env(),m.fetcher),resolvedKeys);
  assert.deepEqual(m.calls,['https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid','https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/api-keys']);
  assert.equal(env().STAGING_SUPABASE_SERVICE_ROLE_KEY,undefined);
  for(const rows of [[],[{name:'anon',api_key:'valid-anon-key'}],[{name:'service_role',api_key:'valid-service-key'}],[{name:'anon',api_key:'valid-anon-key'},{name:'anon',api_key:'duplicate-anon-key'},{name:'service_role',api_key:'valid-service-key'}],
    [{name:'anon',api_key:'valid-anon-key'},{name:'service_role',api_key:'valid-service-key'},{name:'service_role',api_key:'duplicate-service-key'}],
    [{name:'anon',api_key:'shared-key-canary'},{name:'service_role',api_key:'shared-key-canary'}]]) {
    await assert.rejects(resolveStagingApiKeys({...env(),...resolvedKeys},management({rows}).fetcher),/CI_STAGING_KEYS/);
  }
});
test('wrong project, canonical host, HTTP and JSON failures close before preparation without provider bodies',async()=>{
  for(const project of [{id:'another-project',status:'ACTIVE_HEALTHY',database:{host:'db.mejpriaetwgtcstbgfid.supabase.co'}},
    {id:'mejpriaetwgtcstbgfid',status:'ACTIVE_HEALTHY',database:{host:'db.other.supabase.co'}}]) {
    const m=management({project});await assert.rejects(resolveStagingApiKeys(env(),m.fetcher),/CI_STAGING_PROJECT/);assert.equal(m.calls.length,1);
  }
  for(const options of [{httpFailure:true},{httpFailure:'keys'},{invalidJson:true}])await assert.rejects(resolveStagingApiKeys(env(),management(options).fetcher),error=>error.message==='CI_STAGING_API_READ'&&!error.message.includes('provider-secret-body'));
  const r=runner({management:{rows:[]},prepare:async()=>assert.fail('Preparation must not start')});
  await assert.rejects(runCi(r.args),/CI_STAGING_KEYS/);assert.equal(r.summaries.at(-1).preparationAttempted,false);
});
test('a provenance refusal never resolves staging API keys',async()=>{
  const r=runner({github:{transform:(x,u)=>u.pathname.includes('/git/ref/')?{...x,object:{sha:fixtureSha,type:'commit'}}:x},prepare:async()=>assert.fail('Preparation must not start')});
  await assert.rejects(runCi(r.args),/CI_MAIN_MOVED/);assert.equal(r.m.calls.length,0);
});
test('real preparer save contract persists encrypted intent before effect and receipt afterwards, without CI secrets',async()=>{
  const r=runner({prepare:async({manifest,save,env:preparedEnv})=>{
    assert.deepEqual(preparedEnv,{STAGING_SUPABASE_ACCESS_TOKEN:env().STAGING_SUPABASE_ACCESS_TOKEN,STRIPE_TEST_SECRET_KEY:env().STRIPE_TEST_SECRET_KEY,...resolvedKeys});
    assert.ok(r.calls.slice(0,8).every(url=>url.startsWith('https://api.github.com/')));
    assert.ok(r.calls.slice(8).every(url=>url.startsWith('https://api.supabase.com/')));
    manifest.steps.customer={state:'intent'};await save(manifest);
    assert.equal(openJournal(r.checkpoints.at(-1),privatePem,fp).manifest.steps.customer.state,'intent');
    manifest.steps.customer={state:'done',result:{id:'cus_test'}};await save(manifest);
    return {prepared:true,invoiceId:'10000000-0000-4000-8000-000000000001',commissionId:'10000000-0000-4000-8000-000000000002'};
  }});
  const result=await runCi(r.args);assert.equal(result.prepared,true);assert.equal(r.checkpoints.length,5);
  assert.equal(r.args.env.STAGING_SUPABASE_ANON_KEY,undefined);assert.equal(r.args.env.STAGING_SUPABASE_SERVICE_ROLE_KEY,undefined);
  const opened=openJournal(r.checkpoints.at(-1),privatePem,fp);assert.equal(opened.manifest.steps.customer.result.id,'cus_test');
  const clear=JSON.stringify(opened),publicFiles=JSON.stringify([r.checkpoints,r.summaries]);
  for(const value of [r.args.env.GITHUB_TOKEN,r.args.env.STAGING_SUPABASE_ACCESS_TOKEN,r.args.env.STRIPE_TEST_SECRET_KEY,...Object.values(resolvedKeys)]) {
    assert.ok(!clear.includes(value));assert.ok(!publicFiles.includes(value));assert.ok(!JSON.stringify(r.privateJournals).includes(value));
  }
  for(const member of opened.manifest.members)assert.ok(!publicFiles.includes(member.password));
  assert.ok(r.summaries.every(x=>Object.values(x).every(v=>typeof v==='boolean')));
});
test('uncertain preparation keeps the same encrypted intent and a failed boolean summary',async()=>{
  const r=runner({prepare:async({manifest,save})=>{manifest.steps.account={state:'intent'};await save(manifest);throw new FixtureRefusal('TRANSPORT_OR_JSON_UNCERTAIN');}});
  await assert.rejects(runCi(r.args),/TRANSPORT_OR_JSON_UNCERTAIN/);
  assert.equal(openJournal(r.checkpoints.at(-1),privatePem,fp).manifest.steps.account.state,'intent');
  assert.equal(r.summaries.at(-1).prepared,false);assert.equal(r.summaries.at(-1).failed,true);
});
test('checkpoint failure prevents the next remote effect and retains the last encrypted intent',async()=>{
  let writes=0,effects=0;
  const r=runner({prepare:async({manifest,save})=>{manifest.steps.account={state:'intent'};await save(manifest);effects++;}});
  r.args.writeCheckpoint=async envelope=>{writes++;if(writes>=3)throw Error('disk unavailable');r.checkpoints.push(envelope);};
  await assert.rejects(runCi(r.args),/disk unavailable/);assert.equal(effects,0);assert.equal(r.checkpoints.length,2);assert.equal(r.summaries.at(-1).failed,true);
});
test('workflow is manual trusted main only, Node-only before credentials and uploads two exact safe paths',async()=>{
  const text=await readFile(new URL('../../.github/workflows/connect-test-fixture.yml',import.meta.url),'utf8');
  assert.match(text,/workflow_dispatch:/);assert.doesNotMatch(text,/pull_request:|\n  push:|schedule:|npm ci|deploy|AccountLink/);
  assert.match(text,/github\.ref == 'refs\/heads\/main'/);assert.match(text,/group: jolene-supabase-staging-writes/);
  const secrets=text.indexOf('secrets.STAGING_SUPABASE_ACCESS_TOKEN');assert.ok(secrets>text.indexOf('connect-test-fixture-ci.mjs check'));
  assert.ok(text.indexOf('node --test')<secrets);assert.doesNotMatch(text.slice(0,text.indexOf('connect-test-fixture-ci.mjs run')),/secrets\./);
  assert.match(text,/connect-test-fixture-proof\/fixture\.encrypted\.json/);assert.match(text,/connect-test-fixture-proof\/result\.json/);
  assert.doesNotMatch(text,/\/\*|manifest\.private|journal\.private|recipient_private/);
  assert.doesNotMatch(text,/secrets\.STAGING_SUPABASE_SERVICE_ROLE_KEY|secrets\.STAGING_SUPABASE_ANON_KEY|GITHUB_ENV/);
});
test('offline open CLI writes only private files and its frontend handoff excludes the admin and every CI key',async()=>{
  const directory=await mkdtemp(join(await realpath(tmpdir()),'connect-ci-open-'));
  try {
    const c=checkCi(env(),local,contract(),sources),payload={format:'JOLENE_CONNECT_FIXTURE_PRIVATE_V1',projectRef:'mejpriaetwgtcstbgfid',mainSha,
      manifest:c.manifest,result:null};
    const encrypted=JSON.stringify(sealJournal(payload,c.key)),input=join(directory,'fixture.encrypted.json'),keyPath=join(directory,'local.private.pem'),output=join(directory,'opened');
    await writeFile(input,encrypted,{mode:0o600});await writeFile(keyPath,privatePem,{mode:0o600});
    const script=fileURLToPath(new URL('../../scripts/ci/connect-test-fixture-ci.mjs',import.meta.url));
    const response=spawnSync(process.execPath,[script,'open',input,keyPath,hash(encrypted),fp,output],{encoding:'utf8',env:{PATH:process.env.PATH},timeout:10000});
    assert.equal(response.status,0);assert.deepEqual(JSON.parse(response.stdout),{opened:true,credentialsPrinted:false,serviceCredentialsIncluded:false});
    const frontend=JSON.parse(await readFile(join(output,'frontend.private.json'),'utf8'));
    assert.equal(frontend.members.length,2);assert.deepEqual(frontend.members.map(x=>x.role),['SOIGNANT','ADMIN_ETABLISSEMENT']);
    assert.ok(!JSON.stringify(frontend).includes(c.manifest.members[2].password));
    for(const name of ['journal.private.json','manifest.private.json','frontend.private.json'])assert.equal((await stat(join(output,name))).mode&0o777,0o600);
    assert.equal((await stat(output)).mode&0o777,0o700);
    for(const member of c.manifest.members)assert.ok(!`${response.stdout}${response.stderr}`.includes(member.password));
    const duplicate=spawnSync(process.execPath,[script,'open',input,keyPath,hash(encrypted),fp,output],{encoding:'utf8',env:{PATH:process.env.PATH},timeout:10000});assert.equal(duplicate.status,1);
  } finally {await rm(directory,{recursive:true,force:true});}
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync } from 'node:crypto';
import { readFile, mkdtemp, writeFile, stat, rm, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  AUTH_ONLY_PURPOSE, AUTH_HOOK_FLAGS, projectAuthHooks, newAuthOnlyManifest, validateAuthOnlyManifest,
  authOnlyCatalogueSql, authOnlySnapshotSql, validateAuthOnlyUser, executeAuthOnlyPreparation, requireAuthOnlyComplete,
} from '../../scripts/ci/auth-test-frontend.mjs';
import { PROJECT } from '../../scripts/ci/connect-test-fixture.mjs';
import {
  AUTH_ONLY_SOURCE_FILES, checkAuthOnlyCi, openAuthOnlyJournal,
  runAuthOnlyCi, verifyAuthOnlyProvenance,
} from '../../scripts/ci/auth-test-frontend-ci.mjs';
import {
  resolveStagingApiKeys, sealJournal, recipientKey,
} from '../../scripts/ci/connect-test-fixture-ci.mjs';

const pair=generateKeyPairSync('rsa',{modulusLength:4096});
const publicPem=pair.publicKey.export({type:'spki',format:'pem'});
const privatePem=pair.privateKey.export({type:'pkcs8',format:'pem'});
const hash=x=>createHash('sha256').update(x).digest('hex');
const fingerprint=hash(pair.publicKey.export({type:'spki',format:'der'}));
const mainSha='a'.repeat(40),reviewedSha='b'.repeat(40),reviewedTree='c'.repeat(40);
const sources=Object.fromEntries(AUTH_ONLY_SOURCE_FILES.map((path,index)=>[path,`reviewed auth-only source ${index}`]));
const manifest=()=>newAuthOnlyManifest('auth-test-ci-12345678-1',mainSha);
const catalogue=()=>({authTriggersMd5:'1'.repeat(32),profileTriggersMd5:'2'.repeat(32),
  authInsertOrUpdateTriggers:0,profileTriggersValid:true,queuedRequests:0,activeCrons:0,runningCrons:0});
const hooks=()=>Object.fromEntries(AUTH_HOOK_FLAGS.map(key=>[key,false]));
const contract=()=>({schemaVersion:1,purpose:AUTH_ONLY_PURPOSE,ready:true,projectRef:PROJECT,
  reviewedSourceSha:reviewedSha,reviewedSourceTree:reviewedTree,
  sourcePins:Object.fromEntries(AUTH_ONLY_SOURCE_FILES.map(path=>[path,hash(sources[path])])),
  expiresAt:new Date(Date.now()+3600000).toISOString(),reviewedBy:'independent Auth effect review',
  authEffectsReviewed:true,catalogue:catalogue(),authHooks:hooks()});
const env=()=>({GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',
  GITHUB_REF:'refs/heads/main',EXPECTED_MAIN_SHA:mainSha,GITHUB_SHA:mainSha,GITHUB_RUN_ID:'12345678',GITHUB_RUN_ATTEMPT:'1',
  GITHUB_TOKEN:'github-secret-canary-never-export',RECIPIENT_PUBLIC_KEY:publicPem,RECIPIENT_SHA256:fingerprint,
  STAGING_SUPABASE_ACCESS_TOKEN:'management-secret-canary-never-export'});
const local={sha:mainSha,clean:true};
const resolvedKeys={STAGING_SUPABASE_ANON_KEY:'anon-secret-canary-never-export',STAGING_SUPABASE_SERVICE_ROLE_KEY:'service-secret-canary-never-export'};

test('fresh frontend manifest contains exactly two different Auth TEST intentions without a business role or seed',()=>{
  const m=manifest(),other=manifest();
  validateAuthOnlyManifest(m);
  assert.equal(m.purpose,'AUTH_ONLY_FRONTEND_V1');assert.equal(m.projectRef,PROJECT);
  assert.deepEqual(m.members.map(x=>x.intention),['SOIGNANT','ETABLISSEMENT']);
  assert.equal(new Set(m.members.map(x=>x.id)).size,2);assert.equal(new Set(m.members.map(x=>x.email)).size,2);
  assert.deepEqual(m.steps,{});assert.equal(m.sql,undefined);
  for(const actor of m.members) {
    assert.equal(actor.role,undefined);assert.equal(actor.etablissement_id,undefined);
    assert.ok(!other.members.some(x=>x.id===actor.id||x.email===actor.email||x.password===actor.password));
    assert.ok(actor.password.length>=32);
  }
});

test('historical identities, duplicate actors, roles and foreign purposes cannot be smuggled into the manifest',()=>{
  for(const mutate of [
    m=>{m.purpose='JOLENE_CONNECT_FIXTURE_PRIVATE_V1';},m=>{m.projectRef='flripxtsyegjshnhzjkz';},
    m=>{m.members.push(structuredClone(m.members[0]));},m=>{m.members.pop();},
    m=>{m.members[1].id=m.members[0].id;},m=>{m.members[1].email=m.members[0].email;},
    m=>{m.members[0].email='historical@example.com';},m=>{m.members[0].role='SOIGNANT';},
    m=>{m.members[1].etablissement_id=m.members[1].id;},m=>{m.members[1].intention='ADMIN_PLATEFORME';},
    m=>{m.members[1].intention='SOIGNANT';},m=>{m.members[0].password='short';},
    m=>{m.ownerMarker='old-owner';},m=>{m.sql={seed:'forbidden'};},
  ]) {const m=manifest();mutate(m);assert.throws(()=>validateAuthOnlyManifest(m));}
});

test('closed readiness refuses before credential lookup, journal callbacks, preparation or any transport',async()=>{
  let calls=0;
  await assert.rejects(runAuthOnlyCi({contract:{...contract(),ready:false},
    fetcher:async()=>{calls++;},prepare:async()=>{calls++;},writePrivateJournal:async()=>{calls++;},
    writeCheckpoint:async()=>{calls++;},writeSummary:async()=>{calls++;}}));
  assert.equal(calls,0);
});

test('main identity, first attempt, reviewed bytes, expiry and explicit Auth review are mandatory before effects',()=>{
  checkAuthOnlyCi(env(),local,contract(),sources);
  for(const change of [{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_ACTIONS:'false'},{GITHUB_REF:'refs/heads/fix'},
    {GITHUB_REPOSITORY:'fork/JJJJJ'},{GITHUB_RUN_ATTEMPT:'2'},{GITHUB_RUN_ID:'0'},
    {EXPECTED_MAIN_SHA:reviewedSha},{GITHUB_SHA:reviewedSha}])assert.throws(()=>checkAuthOnlyCi({...env(),...change},local,contract(),sources));
  for(const change of [{sha:reviewedSha},{clean:false}])assert.throws(()=>checkAuthOnlyCi(env(),{...local,...change},contract(),sources));
  for(const change of [{ready:false},{authEffectsReviewed:false},{purpose:'CONNECT_TEST'},{projectRef:'flripxtsyegjshnhzjkz'},
    {expiresAt:new Date(Date.now()-1).toISOString()},{expiresAt:new Date(Date.now()+5*3600000).toISOString()},
    {reviewedSourceSha:'0'.repeat(40)},{reviewedSourceTree:'0'.repeat(40)},
    {reviewedBy:''},{sourcePins:{}}])assert.throws(()=>checkAuthOnlyCi(env(),local,{...contract(),...change},sources));
  for(const path of AUTH_ONLY_SOURCE_FILES)assert.throws(()=>checkAuthOnlyCi(env(),local,contract(),{...sources,[path]:'unreviewed source'}));
});

test('quiescence, live trigger pins and disabled Auth hooks cannot drift or disappear',()=>{
  for(const change of [{authInsertOrUpdateTriggers:1},{profileTriggersValid:false},{queuedRequests:1},{activeCrons:1},
    {runningCrons:1},{authTriggersMd5:null},{profileTriggersMd5:null}])
    assert.throws(()=>checkAuthOnlyCi(env(),local,{...contract(),catalogue:{...catalogue(),...change}},sources));
  for(const authHooks of [{}, {...hooks(),hook_before_user_created_enabled:true},
    {...hooks(),hook_before_user_created_enabled:'false'},
    {...hooks(),hook_unreviewed_enabled:false},
    {...hooks(),hook_unreviewed_uri:null},
    Object.fromEntries(Object.entries(hooks()).filter(([key])=>key!==AUTH_HOOK_FLAGS[0]))])
    assert.throws(()=>checkAuthOnlyCi(env(),local,{...contract(),authHooks},sources));
  assert.deepEqual(projectAuthHooks({...hooks(),hook_before_user_created_uri:'https://private.invalid/hook',
    hook_before_user_created_secret:'hook-secret-canary-never-export',mailer_autoconfirm:false}),hooks());
});

test('read-only observation covers actor IDs and emails without passwords or any seed mutation',()=>{
  const m=manifest(),sql=authOnlyCatalogueSql()+'\n'+authOnlySnapshotSql(m);
  for(const actor of m.members){assert.ok(sql.includes(actor.id));assert.ok(sql.includes(actor.email));assert.ok(!sql.includes(actor.password));}
  assert.doesNotMatch(sql,/\b(?:INSERT|UPDATE|DELETE|ALTER|DROP|CREATE|GRANT|REVOKE)\b\s+(?:INTO\s+|TABLE\s+|FUNCTION\s+)?(?:public|private|auth)\./i);
  assert.doesNotMatch(sql,/DISABLE TRIGGER|session_replication_role|set_config\('app\.test_mode'/i);
  assert.match(sql,/auth\.users/);assert.match(sql,/public\.soignants/);assert.match(sql,/public\.etablissements/);
});

const cleanSnapshot=count=>({authCount:count,profiles:0,parcours:0,types:0,admin:0,members:0,missions:0,
  documents:0,contracts:0,invoices:0,onboarding:0,emailQueue:0,notifications:0,sessions:0,identities:count});
const authUser=(actor,m)=>({id:actor.id,email:actor.email,email_confirmed_at:'2026-10-14T00:00:00Z',
  app_metadata:{est_compte_test:true,is_test_playwright:true,jolene_auth_fixture_owner:m.ownerMarker,jolene_recette_purpose:AUTH_ONLY_PURPOSE}});
const preparationEnv=()=>({...env(),...resolvedKeys});
const result=()=>({prepared:true,authCreated:2,profilesCreated:0,missionsCreated:0,qualificationVerified:false,
  frontendCompletionRequired:true,stripeObjectsCreated:0,paymentCreated:false,smsSent:false,mailSent:false});

function harness(m,options={}) {
  const state={users:[],calls:[],posts:[],saves:[],events:[]};
  const save=async value=>{
    if(options.beforeSave)await options.beforeSave(value,state);
    state.saves.push(structuredClone(value));state.events.push({kind:'save',steps:structuredClone(value.steps)});
  };
  const fetcher=async(url,init)=>{
    const u=new URL(url);state.calls.push({url,init});state.events.push({kind:'request',url,method:init.method??'GET'});
    assert.equal(init.redirect,'error');
    const override=options.beforeRequest?await options.beforeRequest(url,init,state):undefined;
    if(override!==undefined)return override;
    let value;
    if(u.origin==='https://api.github.com') {
      assert.equal(u.pathname,'/repos/Gabpcd/JJJJJ/git/ref/heads/main');
      value={ref:'refs/heads/main',object:{sha:mainSha,type:'commit'}};
    }else if(u.origin==='https://api.supabase.com') {
      const base=`/v1/projects/${PROJECT}`;
      assert.equal(init.headers.Authorization,`Bearer ${env().STAGING_SUPABASE_ACCESS_TOKEN}`);
      if(u.pathname===base)value={id:PROJECT,status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`}};
      else if(u.pathname===`${base}/config/auth`)value=hooks();
      else if(u.pathname===`${base}/database/query`) {
        const body=JSON.parse(init.body);assert.equal(body.read_only,false);
        assert.match(body.query,/^BEGIN READ ONLY;/);assert.match(body.query,/ROLLBACK;$/);
        const receipt=body.query.includes("'authTriggersMd5'")?catalogue():cleanSnapshot(state.users.length);
        value=[{receipt:options.observation?options.observation(receipt,state):receipt}];
      }else assert.fail(`Forbidden management endpoint ${u.pathname}`);
    }else {
      assert.equal(u.origin,`https://${PROJECT}.supabase.co`);
      assert.equal(init.headers.Authorization,`Bearer ${resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY}`);
      assert.equal(init.headers.apikey,resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY);
      if(u.pathname==='/auth/v1/admin/users'&&init.method==='POST') {
        const body=JSON.parse(init.body),actor=m.members.find(x=>x.id===body.id);assert.ok(actor);
        assert.deepEqual(Object.keys(body).sort(),['app_metadata','email','email_confirm','id','password']);
        assert.deepEqual(body,{id:actor.id,email:actor.email,password:actor.password,email_confirm:true,
          app_metadata:authUser(actor,m).app_metadata});
        state.posts.push(body);state.users.push(authUser(actor,m));
        value=state.users.at(-1);
        if(options.afterPost)return options.afterPost(value,state);
      }else {
        assert.equal(init.method,'GET');assert.ok(m.members.some(x=>u.pathname===`/auth/v1/admin/users/${x.id}`));
        value={user:state.users.find(x=>u.pathname.endsWith('/'+x.id))};
      }
    }
    if(options.transform)value=options.transform(value,u,state);
    return {ok:true,redirected:false,text:async()=>JSON.stringify(value)};
  };
  return {state,save,fetcher};
}
const runPreparation=(m,h,options={})=>executeAuthOnlyPreparation({manifest:m,contract:{...contract(),sourceSha:mainSha},
  env:preparationEnv(),local,fetcher:h.fetcher,save:h.save,...options});

test('simulated preparation performs exactly two TEST-at-birth Auth creations and no profile, login, mail, Stripe or seed',async()=>{
  const m=manifest(),h=harness(m);assert.deepEqual(await runPreparation(m,h),result());
  assert.equal(h.state.posts.length,2);assert.equal(h.state.users.length,2);
  assert.deepEqual(m.steps,{auth0:{state:'done',result:{created:true}},auth1:{state:'done',result:{created:true}}});
  for(const actor of m.members)assert.ok(h.state.calls.some(x=>x.url===`https://${PROJECT}.supabase.co/auth/v1/admin/users/${actor.id}`));
  assert.doesNotMatch(JSON.stringify(h.state.calls),/api\.stripe\.com|\/auth\/v1\/(?:token|signup|invite)|\/functions\/v1\//);
  assert.deepEqual(h.state.saves.map(x=>Object.values(x.steps).map(step=>step.state)),[['intent'],['done'],['done','intent'],['done','done']]);
  for(const post of h.state.posts) {
    const eventIndex=h.state.events.findIndex(x=>x.kind==='request'&&x.url.endsWith('/auth/v1/admin/users')&&
      h.state.events.slice(0,h.state.events.indexOf(x)).filter(e=>e.kind==='request'&&e.url.endsWith('/auth/v1/admin/users')).length===h.state.posts.indexOf(post));
    const priorSave=h.state.events.slice(0,eventIndex).findLast(x=>x.kind==='save');
    assert.equal(priorSave.steps[`auth${h.state.posts.indexOf(post)}`].state,'intent');
    assert.equal(post.app_metadata.est_compte_test,true);assert.equal(post.app_metadata.role,undefined);
    assert.equal(post.app_metadata.etablissement_id,undefined);assert.equal(post.app_metadata.intention,undefined);
  }
});

test('Auth response and reread reject reclassification, wrong ownership, deleted, banned or unconfirmed actors',()=>{
  const m=manifest(),actor=m.members[0],valid=authUser(actor,m);validateAuthOnlyUser(valid,actor,m);
  for(const mutation of [
    u=>{u.id=m.members[1].id;},u=>{u.email=m.members[1].email;},u=>{u.email_confirmed_at=null;},
    u=>{u.deleted_at='2026-10-14T00:00:00Z';},u=>{u.banned_until='2999-01-01T00:00:00Z';},
    u=>{u.app_metadata.est_compte_test=false;},u=>{u.app_metadata.is_test_playwright=false;},
    u=>{u.app_metadata.jolene_auth_fixture_owner='historical-owner';},u=>{u.app_metadata.jolene_recette_purpose='CONNECT_TEST';},
    u=>{u.app_metadata.role='SOIGNANT';},u=>{u.app_metadata.role=null;},u=>{u.app_metadata.etablissement_id=actor.id;},
  ]) {const user=structuredClone(valid);mutation(user);assert.throws(()=>validateAuthOnlyUser(user,actor,m));}
});

test('ID or email collisions and every forbidden downstream row stop before the first creation',async()=>{
  for(const field of ['authCount','identities','profiles','parcours','types','admin','members','missions','documents','contracts',
    'invoices','onboarding','emailQueue','notifications','sessions']) {
    const m=manifest(),h=harness(m,{observation:receipt=>Object.hasOwn(receipt,'authCount')?{...receipt,[field]:1}:receipt});
    await assert.rejects(runPreparation(m,h));assert.equal(h.state.posts.length,0);assert.equal(h.state.saves.length,0);
  }
  const sql=authOnlySnapshotSql(manifest());
  assert.match(sql,/FROM auth\.users WHERE id IN\([^)]*\) OR email IN\(/);
  assert.match(sql,/FROM public\.etablissements WHERE id IN\([^)]*\) OR email_contact IN\(/);
});

test('trigger, hook or provider side effects after one actor stop the second Auth creation',async()=>{
  for(const field of ['profiles','parcours','types','admin','members','missions','documents','contracts','invoices','onboarding',
    'emailQueue','notifications','sessions']) {
    const m=manifest(),h=harness(m,{observation:(receipt,state)=>Object.hasOwn(receipt,'authCount')&&state.users.length===1?
      {...receipt,[field]:1}:receipt});
    await assert.rejects(runPreparation(m,h));assert.equal(h.state.posts.length,1);assert.equal(m.steps.auth0.state,'intent');assert.equal(m.steps.auth1,undefined);
  }
  for(const kind of ['main','hook','catalogue']) {
    const m=manifest(),h=harness(m,{transform:(value,u,state)=>{
      if(state.users.length!==1)return value;
      if(kind==='main'&&u.origin==='https://api.github.com')return {...value,object:{sha:reviewedSha,type:'commit'}};
      if(kind==='hook'&&u.pathname.endsWith('/config/auth'))return {...value,hook_send_email_enabled:true};
      if(kind==='catalogue'&&Array.isArray(value)&&value[0]?.receipt?.authTriggersMd5)return [{receipt:{...catalogue(),authTriggersMd5:'f'.repeat(32)}}];
      return value;
    }});
    await assert.rejects(runPreparation(m,h));assert.equal(h.state.posts.length,1);assert.equal(m.steps.auth1,undefined);
  }
});

test('lost, rejected, malformed and misbound Auth receipts stay ambiguous with no retry or repair',async()=>{
  for(const afterPost of [
    async()=>{throw Error('provider-secret-canary-never-export');},
    async()=>({ok:false,redirected:false,text:async()=>assert.fail('Rejected provider body must not be read')}),
    async()=>({ok:true,redirected:true,text:async()=>assert.fail('Redirected provider body must not be read')}),
    async()=>({ok:true,redirected:false,text:async()=>'provider-secret-canary-not-json'}),
    async user=>({ok:true,redirected:false,text:async()=>JSON.stringify({...user,app_metadata:{...user.app_metadata,role:'SOIGNANT'}})}),
  ]) {
    const m=manifest(),h=harness(m,{afterPost});
    await assert.rejects(runPreparation(m,h),error=>!error.message.includes('provider-secret-canary'));
    assert.equal(h.state.posts.length,1);assert.equal(m.steps.auth0.state,'intent');assert.equal(m.steps.auth1,undefined);
    const calls=h.state.calls.length;await assert.rejects(runPreparation(m,h),/AUTH_ONLY_NO_RETRY/);
    assert.equal(h.state.calls.length,calls);assert.equal(h.state.posts.length,1);
  }
});

test('a failed intent checkpoint prevents its next Auth POST, including after the first actor is complete',async()=>{
  for(const failureIndex of [0,1]) {
    const m=manifest(),h=harness(m,{beforeSave:async value=>{
      if(value.steps[`auth${failureIndex}`]?.state==='intent')throw Error('checkpoint unavailable');
    }});
    await assert.rejects(runPreparation(m,h),/checkpoint unavailable/);assert.equal(h.state.posts.length,failureIndex);
  }
});

test('a real preparer cannot silently use a missing checkpoint callback before creating actors',async()=>{
  const m=manifest(),h=harness(m);
  await assert.rejects(executeAuthOnlyPreparation({manifest:m,contract:{...contract(),sourceSha:mainSha},
    env:preparationEnv(),local,fetcher:h.fetcher}),/AUTH_ONLY_CHECKPOINT_REQUIRED/);
  assert.equal(h.state.calls.length,0);assert.equal(h.state.posts.length,0);assert.deepEqual(m.steps,{});
});

test('historical or completed steps, inherited Stripe credentials and wrong local sources refuse without network',async()=>{
  for(const [change,options]of [
    [m=>{m.steps.auth0={state:'intent'};},{}],
    [m=>{m.steps.auth0={state:'done',result:{created:true}};},{}],
    [()=>{}, {env:{...preparationEnv(),STRIPE_TEST_SECRET_KEY:'rk_test_forbidden_in_auth_only'}}],
    [()=>{}, {local:{sha:reviewedSha,clean:true}}],
    [()=>{}, {local:{sha:mainSha,clean:false}}],
  ]) {
    const m=manifest();change(m);const h=harness(m);await assert.rejects(runPreparation(m,h,options));assert.equal(h.state.calls.length,0);
  }
});

function github(options={}) {
  const calls=[];
  const fetcher=async(url,init)=>{
    const u=new URL(url);calls.push({url,init});assert.equal(u.origin,'https://api.github.com');assert.equal(init.redirect,'error');
    let value;
    if(u.pathname.endsWith('/git/ref/heads/main'))value={ref:'refs/heads/main',object:{sha:mainSha,type:'commit'}};
    else if(u.pathname.includes('/git/commits/'))value={sha:reviewedSha,tree:{sha:reviewedTree}};
    else if(u.pathname.endsWith('/connect-test-fixture.yml/runs'))value={total_count:1,workflow_runs:[{id:12345678,path:'.github/workflows/connect-test-fixture.yml'}]};
    else if(u.pathname.includes('/contents/')) {
      const path=u.pathname.split('/contents/')[1];assert.equal(u.searchParams.get('ref'),reviewedSha);
      value={type:'file',encoding:'base64',content:Buffer.from(sources[path]).toString('base64')};
    }else assert.fail(`Forbidden GitHub endpoint ${u.pathname}`);
    if(options.transform)value=options.transform(value,u);
    return {ok:true,redirected:false,text:async()=>JSON.stringify(value)};
  };
  return {calls,fetcher};
}
function management(options={}) {
  const calls=[],base=`https://api.supabase.com/v1/projects/${PROJECT}`;
  const fetcher=async(url,init)=>{
    calls.push({url,init});assert.equal(init.redirect,'error');assert.equal(init.headers.Authorization,`Bearer ${env().STAGING_SUPABASE_ACCESS_TOKEN}`);
    if(options.failure===true||options.failure===new URL(url).pathname.split('/').at(-1))
      return {ok:false,redirected:false,text:async()=>assert.fail('Rejected provider body must not be read')};
    let value;
    if(url===base)value=options.project??{id:PROJECT,status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`}};
    else if(url===`${base}/config/auth`)value=options.config??{...hooks(),hook_send_email_secret:'hook-secret-canary-never-export'};
    else if(url===`${base}/database/query`) {
      const body=JSON.parse(init.body);assert.match(body.query,/^BEGIN READ ONLY;/);assert.match(body.query,/ROLLBACK;$/);
      value=[{receipt:options.catalogue??catalogue()}];
    }else if(url===`${base}/api-keys`)value=options.rows??[
      {name:'anon',api_key:resolvedKeys.STAGING_SUPABASE_ANON_KEY},{name:'service_role',api_key:resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY},
    ];
    else assert.fail(`Forbidden management endpoint ${new URL(url).pathname}`);
    return {ok:true,redirected:false,text:async()=>options.invalidJson?'private-provider-body-canary':JSON.stringify(value)};
  };
  return {calls,fetcher};
}
function ciRunner(options={}) {
  const checkpoints=[],privateJournals=[],summaries=[],g=github(options.github),mgmt=management(options.management),calls=[];
  const fetcher=async(url,init)=>{calls.push(url);return url.startsWith('https://api.github.com/')?g.fetcher(url,init):mgmt.fetcher(url,init);};
  const prepare=async({manifest,save})=>{
    manifest.steps.auth0={state:'done',result:{created:true}};
    manifest.steps.auth1={state:'done',result:{created:true}};await save(manifest);return result();
  };
  const args={env:env(),local,contract:contract(),sources,fetcher,prepare,
    writePrivateJournal:async value=>privateJournals.push(structuredClone(value)),
    writeCheckpoint:async value=>checkpoints.push(structuredClone(value)),
    writeSummary:async value=>summaries.push(structuredClone(value)),...options};
  return {args,checkpoints,privateJournals,summaries,g,mgmt,calls};
}

test('reviewed GitHub bytes, tree, current main and exactly one dispatch must all attest before staging credentials',async()=>{
  await verifyAuthOnlyProvenance(env(),contract(),sources,github().fetcher);
  for(const [segment,transform]of [
    ['/git/ref/',value=>({...value,object:{sha:reviewedSha,type:'commit'}})],
    ['/git/commits/',value=>({...value,tree:{sha:mainSha}})],
    ['/connect-test-fixture.yml/runs',value=>({...value,total_count:2})],
    ['/connect-test-fixture.yml/runs',value=>({...value,workflow_runs:[]})],
    ['/connect-test-fixture.yml/runs',value=>({...value,workflow_runs:[{id:98765432,path:'.github/workflows/connect-test-fixture.yml'}]})],
    ['/connect-test-fixture.yml/runs',value=>({...value,workflow_runs:[{id:12345678,path:'.github/workflows/another.yml'}]})],
    ['/contents/',value=>({...value,content:Buffer.from('unreviewed source').toString('base64')})],
  ]) {
    const r=ciRunner({github:{transform:(value,url)=>url.pathname.includes(segment)?transform(value):value},
      prepare:async()=>assert.fail('A refused provenance must not prepare actors')});
    await assert.rejects(runAuthOnlyCi(r.args));assert.equal(r.mgmt.calls.length,0);assert.equal(r.summaries.at(-1).failed,true);
  }
});

test('fixed staging identity, hooks and catalogue are verified before API key resolution; wrong values never reach api-keys',async()=>{
  const r=ciRunner();await runAuthOnlyCi(r.args);
  assert.deepEqual(r.mgmt.calls.map(x=>new URL(x.url).pathname.split('/').at(-1)),[PROJECT,'auth','query',PROJECT,'api-keys']);
  for(const change of [
    {project:{id:'another-project',status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`}}},
    {project:{id:PROJECT,status:'INACTIVE',database:{host:`db.${PROJECT}.supabase.co`}}},
    {project:{id:PROJECT,status:'ACTIVE_HEALTHY',database:{host:'db.foreign.supabase.co'}}},
    {config:{...hooks(),hook_send_email_enabled:true}},
    {config:{...hooks(),hook_unreviewed_enabled:false}},
    {catalogue:{...catalogue(),authTriggersMd5:'f'.repeat(32)}},
    {catalogue:{...catalogue(),queuedRequests:1}},
  ]) {
    const refused=ciRunner({management:change,prepare:async()=>assert.fail('A refused preflight must not prepare actors')});
    await assert.rejects(runAuthOnlyCi(refused.args));assert.ok(!refused.mgmt.calls.some(x=>x.url.endsWith('/api-keys')));
    assert.equal(refused.summaries.at(-1).preparationAttempted,false);
  }
});

test('API key resolution rejects missing, duplicate and shared provider keys without inherited-key fallback',async()=>{
  assert.deepEqual(await resolveStagingApiKeys(env(),management().fetcher),resolvedKeys);
  for(const rows of [[],[{name:'anon',api_key:resolvedKeys.STAGING_SUPABASE_ANON_KEY}],
    [{name:'service_role',api_key:resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY}],
    [{name:'anon',api_key:'same-private-key'},{name:'service_role',api_key:'same-private-key'}],
    [{name:'anon',api_key:resolvedKeys.STAGING_SUPABASE_ANON_KEY},{name:'anon',api_key:'duplicate-anon-private-key'},
      {name:'service_role',api_key:resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY}],
    [{name:'anon',api_key:resolvedKeys.STAGING_SUPABASE_ANON_KEY},{name:'service_role',api_key:resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY},
      {name:'service_role',api_key:'duplicate-service-private-key'}],
  ])await assert.rejects(resolveStagingApiKeys({...env(),...resolvedKeys},management({rows}).fetcher));
  for(const options of [{failure:true},{failure:'api-keys'},{invalidJson:true}])
    await assert.rejects(resolveStagingApiKeys(env(),management(options).fetcher),error=>!error.message.includes('private-provider-body'));
});

test('CI encrypts both actor intentions before each real preparer POST; all credentials remain out of saved objects and public receipt',async()=>{
  let executed;
  const r=ciRunner({prepare:async args=>{
    assert.deepEqual(args.env,{STAGING_SUPABASE_ACCESS_TOKEN:env().STAGING_SUPABASE_ACCESS_TOKEN,
      STAGING_SUPABASE_SERVICE_ROLE_KEY:resolvedKeys.STAGING_SUPABASE_SERVICE_ROLE_KEY,GITHUB_TOKEN:env().GITHUB_TOKEN});
    executed=harness(args.manifest,{beforeRequest:async(url,init,state)=>{
      if(url.endsWith('/auth/v1/admin/users')&&init.method==='POST') {
        const checkpoint=openAuthOnlyJournal(r.checkpoints.at(-1),privatePem,fingerprint);
        assert.equal(checkpoint.manifest.steps[`auth${state.posts.length}`].state,'intent');
        assert.equal(r.summaries.at(-1).uncertain,true);
        assert.equal(checkpoint.manifest.members.length,2);
      }
    }});
    return executeAuthOnlyPreparation({...args,fetcher:executed.fetcher});
  }});
  const receipt=await runAuthOnlyCi(r.args);assert.equal(receipt.prepared,true);assert.equal(receipt.authCreated,2);assert.equal(receipt.uncertain,false);
  assert.equal(executed.state.posts.length,2);
  const opened=openAuthOnlyJournal(r.checkpoints.at(-1),privatePem,fingerprint);
  assert.deepEqual(opened.result,result());
  const savedClear=JSON.stringify(r.privateJournals),publicFiles=JSON.stringify([r.checkpoints,r.summaries]);
  for(const secret of [env().GITHUB_TOKEN,env().STAGING_SUPABASE_ACCESS_TOKEN,...Object.values(resolvedKeys),'hook-secret-canary-never-export']) {
    assert.ok(!savedClear.includes(secret));assert.ok(!publicFiles.includes(secret));
  }
  for(const actor of opened.manifest.members)for(const privateValue of [actor.id,actor.email,actor.password,actor.intention])assert.ok(!publicFiles.includes(privateValue));
  assert.ok(r.summaries.every(value=>Object.values(value).every(x=>typeof x==='boolean'||Number.isSafeInteger(x))));
  assert.equal(r.args.env.STAGING_SUPABASE_SERVICE_ROLE_KEY,undefined);assert.equal(r.args.env.STAGING_SUPABASE_ANON_KEY,undefined);
});

test('failed CI checkpoint stops the next effect and uncertain provider failure preserves its encrypted intent with confirmed count only',async()=>{
  let effects=0,writes=0;
  const checkpointFailure=ciRunner({prepare:async({manifest,save})=>{
    manifest.steps.auth0={state:'intent'};await save(manifest);effects++;return result();
  }});
  checkpointFailure.args.writeCheckpoint=async value=>{if(++writes>=3)throw Error('checkpoint unavailable');checkpointFailure.checkpoints.push(value);};
  await assert.rejects(runAuthOnlyCi(checkpointFailure.args),/checkpoint unavailable/);assert.equal(effects,0);
  const uncertain=ciRunner({prepare:async args=>{
    const h=harness(args.manifest,{afterPost:async()=>{throw Error('private-provider-failure-canary');}});
    return executeAuthOnlyPreparation({...args,fetcher:h.fetcher});
  }});
  await assert.rejects(runAuthOnlyCi(uncertain.args),error=>!error.message.includes('private-provider-failure'));
  const journal=openAuthOnlyJournal(uncertain.checkpoints.at(-1),privatePem,fingerprint);
  assert.equal(journal.manifest.steps.auth0.state,'intent');assert.equal(journal.manifest.steps.auth1,undefined);
  assert.equal(uncertain.summaries.at(-1).prepared,false);assert.equal(uncertain.summaries.at(-1).failed,true);
  assert.equal(uncertain.summaries.at(-1).uncertain,true);assert.equal(uncertain.summaries.at(-1).authCreated,0);
});

test('authenticated envelope rejects changed recipient, ciphertext, extra fields and a foreign purpose',()=>{
  const checked=checkAuthOnlyCi(env(),local,contract(),sources);
  const payload={format:'JOLENE_AUTH_ONLY_PRIVATE_V1',purpose:AUTH_ONLY_PURPOSE,projectRef:PROJECT,mainSha,
    manifest:checked.manifest,result:null};
  const encrypted=sealJournal(payload,checked.key);assert.deepEqual(openAuthOnlyJournal(encrypted,privatePem,fingerprint),payload);
  assert.throws(()=>openAuthOnlyJournal(encrypted,privatePem,'d'.repeat(64)));
  assert.throws(()=>openAuthOnlyJournal({...encrypted,ciphertext:Buffer.from('changed ciphertext').toString('base64')},privatePem,fingerprint));
  assert.throws(()=>openAuthOnlyJournal({...encrypted,extra:'unreviewed'},privatePem,fingerprint));
  assert.throws(()=>openAuthOnlyJournal(sealJournal({...payload,purpose:'CONNECT_TEST'},checked.key),privatePem,fingerprint));
  assert.throws(()=>openAuthOnlyJournal(sealJournal({...payload,mainSha:reviewedSha},checked.key),privatePem,fingerprint));
  assert.throws(()=>recipientKey(privatePem,fingerprint));
});

test('versioned readiness stays closed until review evidence, and manual workflow exposes no Auth-only Stripe or inherited service key',async()=>{
  const versioned=JSON.parse(await readFile(new URL('../../scripts/ci/auth-test-frontend-ci.contract.json',import.meta.url),'utf8'));
  assert.equal(typeof versioned.ready,'boolean');
  let calls=0;await assert.rejects(runAuthOnlyCi({contract:{...versioned,ready:false},fetcher:()=>{calls++;},prepare:()=>{calls++;}}));assert.equal(calls,0);
  if(versioned.ready===false) {
    assert.equal(versioned.authEffectsReviewed,false);
    for(const field of ['reviewedSourceSha','reviewedSourceTree','sourcePins','expiresAt','reviewedBy','catalogue'])assert.equal(versioned[field],null);
  }else {
    const reviewedSources=Object.fromEntries(await Promise.all(AUTH_ONLY_SOURCE_FILES.map(async path=>[
      path,await readFile(new URL('../../'+path,import.meta.url),'utf8'),
    ])));
    const expiry=Date.parse(versioned.expiresAt);assert.ok(Number.isFinite(expiry));
    // This structural witness stays deterministic after a reviewed historical window expires.
    // Runtime uses Date.now() and still closes expired or overlong execution windows.
    const checked=checkAuthOnlyCi(env(),local,versioned,reviewedSources,expiry-3600000);
    assert.equal(checked.operatorContract.authEffectsReviewed,true);
    assert.equal(checked.operatorContract.sourceSha,mainSha);
    assert.throws(()=>checkAuthOnlyCi(env(),local,versioned,reviewedSources,expiry));
    assert.throws(()=>checkAuthOnlyCi(env(),local,versioned,reviewedSources,expiry-4*3600000-1));
  }
  const workflow=await readFile(new URL('../../.github/workflows/connect-test-fixture.yml',import.meta.url),'utf8');
  assert.match(workflow,/workflow_dispatch:/);assert.doesNotMatch(workflow,/pull_request:|\n  push:|schedule:|npm ci/);
  assert.match(workflow,/group: jolene-supabase-staging-writes/);assert.match(workflow,/github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow,/AUTH_ONLY_FRONTEND_V1\) node scripts\/ci\/auth-test-frontend-ci\.mjs check-auth-only/);
  const authStep=workflow.slice(workflow.lastIndexOf('- name:',workflow.indexOf('run: node scripts/ci/auth-test-frontend-ci.mjs run-auth-only')),
    workflow.indexOf('- name: Conserver'));
  assert.match(authStep,/if: inputs\.purpose == 'AUTH_ONLY_FRONTEND_V1'/);assert.doesNotMatch(authStep,/STRIPE|ANON_KEY|SERVICE_ROLE_KEY/);
  assert.ok(workflow.indexOf('node --test')<workflow.indexOf('secrets.STAGING_SUPABASE_ACCESS_TOKEN'));
  assert.doesNotMatch(workflow,/secrets\.STAGING_SUPABASE_SERVICE_ROLE_KEY|secrets\.STAGING_SUPABASE_ANON_KEY|GITHUB_ENV|manifest\.private|journal\.private|recipient_private/);
  assert.match(workflow,/connect-test-fixture-proof\/fixture\.encrypted\.json/);assert.match(workflow,/connect-test-fixture-proof\/result\.json/);
});

test('a fabricated success receipt without both closed done steps cannot make CI or handoff claim creation',async()=>{
  const r=ciRunner({prepare:async()=>result()});await assert.rejects(runAuthOnlyCi(r.args),/AUTH_ONLY_INCOMPLETE_HANDOFF/);
  assert.equal(r.summaries.at(-1).prepared,false);assert.equal(r.summaries.at(-1).authCreated,0);
  for(const mutate of [
    m=>{},m=>{m.steps.auth0={state:'intent'};},
    m=>{m.steps.auth0={state:'done',result:{created:true}};},
    m=>{m.steps.auth0={state:'done',result:{created:true,unexpected:'unreviewed'}};m.steps.auth1={state:'done',result:{created:true}};},
  ]) {const m=manifest();mutate(m);assert.throws(()=>requireAuthOnlyComplete(m,result()),/AUTH_ONLY_INCOMPLETE_HANDOFF/);}
});

test('offline handoff refuses initial or ambiguous encrypted checkpoints before creating a directory or exposing credentials',async()=>{
  const directory=await mkdtemp(join(await realpath(tmpdir()),'auth-only-refused-open-'));
  try {
    const keyPath=join(directory,'recipient.private.pem');await writeFile(keyPath,privatePem,{mode:0o600});
    for(const state of ['initial','uncertain','partial']) {
      const m=manifest();
      if(state==='uncertain')m.steps.auth0={state:'intent'};
      if(state==='partial')m.steps.auth0={state:'done',result:{created:true}};
      const payload={format:'JOLENE_AUTH_ONLY_PRIVATE_V1',purpose:AUTH_ONLY_PURPOSE,projectRef:PROJECT,mainSha,
        manifest:m,result:state==='partial'?result():null};
      const encrypted=JSON.stringify(sealJournal(payload,recipientKey(publicPem,fingerprint)));
      const input=join(directory,`${state}.encrypted.json`),output=join(directory,`${state}-opened`);
      await writeFile(input,encrypted,{mode:0o600});
      // Decryption remains available for private diagnosis; CLI frontend handoff requires full proof.
      assert.deepEqual(openAuthOnlyJournal(JSON.parse(encrypted),privatePem,fingerprint),payload);
      const response=spawnSync(process.execPath,[fileURLToPath(new URL('../../scripts/ci/auth-test-frontend-ci.mjs',import.meta.url)),
        'open-auth-only',input,keyPath,hash(encrypted),fingerprint,output],{encoding:'utf8',env:{PATH:process.env.PATH},timeout:10000});
      assert.equal(response.status,1);assert.match(response.stderr,/AUTH_ONLY_INCOMPLETE_HANDOFF/);
      await assert.rejects(stat(output),{code:'ENOENT'});
      for(const actor of m.members)assert.ok(!`${response.stdout}${response.stderr}`.includes(actor.password));
      assert.ok(!`${response.stdout}${response.stderr}`.includes(privatePem));
    }
  }finally{await rm(directory,{recursive:true,force:true});}
});

test('offline successful handoff is private, has exactly two intentions, no business role or CI key, and refuses overwrite',async()=>{
  const directory=await mkdtemp(join(await realpath(tmpdir()),'auth-only-complete-open-'));
  try {
    const m=manifest();m.steps={auth0:{state:'done',result:{created:true}},auth1:{state:'done',result:{created:true}}};
    const payload={format:'JOLENE_AUTH_ONLY_PRIVATE_V1',purpose:AUTH_ONLY_PURPOSE,projectRef:PROJECT,mainSha,manifest:m,result:result()};
    const encrypted=JSON.stringify(sealJournal(payload,recipientKey(publicPem,fingerprint))),input=join(directory,'fixture.encrypted.json');
    const keyPath=join(directory,'recipient.private.pem'),output=join(directory,'opened');
    await writeFile(input,encrypted,{mode:0o600});await writeFile(keyPath,privatePem,{mode:0o600});
    const args=[fileURLToPath(new URL('../../scripts/ci/auth-test-frontend-ci.mjs',import.meta.url)),
      'open-auth-only',input,keyPath,hash(encrypted),fingerprint,output];
    const execute=()=>spawnSync(process.execPath,args,{encoding:'utf8',env:{PATH:process.env.PATH},timeout:10000});
    const response=execute();assert.equal(response.status,0);
    assert.deepEqual(JSON.parse(response.stdout),{opened:true,credentialsPrinted:false,serviceCredentialsIncluded:false});
    const frontend=JSON.parse(await readFile(join(output,'frontend.private.json'),'utf8'));
    assert.deepEqual(frontend.members,m.members);assert.equal(frontend.authCreatedByOperator,true);
    assert.equal(frontend.frontendCompletionRequired,true);assert.equal(frontend.qualificationVerified,false);
    assert.equal(frontend.purpose,AUTH_ONLY_PURPOSE);assert.equal(frontend.missionId,undefined);assert.equal(frontend.invoiceId,undefined);
    assert.ok(frontend.members.every(x=>x.role===undefined));
    for(const name of ['journal.private.json','manifest.private.json','frontend.private.json'])assert.equal((await stat(join(output,name))).mode&0o777,0o600);
    assert.equal((await stat(output)).mode&0o777,0o700);
    for(const secret of [env().GITHUB_TOKEN,env().STAGING_SUPABASE_ACCESS_TOKEN,...Object.values(resolvedKeys)])assert.ok(!JSON.stringify(frontend).includes(secret));
    for(const actor of m.members)assert.ok(!`${response.stdout}${response.stderr}`.includes(actor.password));
    assert.equal(execute().status,1);
  }finally{await rm(directory,{recursive:true,force:true});}
});

test('Auth-only adapter pins all six dependencies and cannot invoke the historical Connect CLI modes',async()=>{
  assert.deepEqual([...AUTH_ONLY_SOURCE_FILES].sort(),[
    'scripts/ci/auth-test-frontend.mjs','scripts/ci/auth-test-frontend-ci.mjs',
    'scripts/ci/connect-test-fixture-ci.mjs','scripts/ci/connect-test-fixture.mjs',
    'scripts/ci/connect-test-fixture-sql.mjs','.github/workflows/connect-test-fixture.yml',
  ].sort());
  const historical=await import('../../scripts/ci/connect-test-fixture-ci.mjs');
  for(const name of ['AUTH_ONLY_SOURCE_FILES','checkAuthOnlyCi','runAuthOnlyCi','openAuthOnlyJournal'])assert.equal(historical[name],undefined);
  const script=fileURLToPath(new URL('../../scripts/ci/auth-test-frontend-ci.mjs',import.meta.url));
  for(const mode of ['check','run','open']) {
    const response=spawnSync(process.execPath,[script,mode],{encoding:'utf8',env:{PATH:process.env.PATH},timeout:10000});
    assert.equal(response.status,1);assert.equal(response.stdout,'');
    assert.deepEqual(JSON.parse(response.stderr),{prepared:false,code:'CI_ARGUMENTS'});
  }
});

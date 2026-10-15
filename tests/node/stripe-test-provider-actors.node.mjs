/** Local refusal tests only; every transport is an in-memory function, never fetch. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,privateDecrypt,createDecipheriv,constants} from 'node:crypto';
import {readFile,mkdtemp,writeFile,access,rm,realpath} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
const moduleUrl=existsSync(new URL('./stripe-test-provider-actors.mjs',import.meta.url))?new URL('./stripe-test-provider-actors.mjs',import.meta.url):new URL('../../scripts/ci/stripe-test-provider-actors.mjs',import.meta.url);
const {prepareStripeTestActors,PURPOSE,PROJECT,PLATFORM,API_VERSION,WORKFLOW,SOURCE_FILES,hash,snapshotSql,writeEncryptedCheckpoint,transmissionProjection,projectionDigest,manifestFromContract,requireComplete,sealJournal,recipientKey,deriveActors,discoverySql,checkVersionedContext}=await import(moduleUrl);
const cliUrl=new URL('./stripe-test-provider-actors-ci.mjs',moduleUrl),contractUrl=new URL('./stripe-test-provider-actors.contract.json',moduleUrl);
const {openPrivateHandoff,openCompleteJournal,readOwnedActors}=await import(cliUrl);
const closedContract=JSON.parse(await readFile(contractUrl));

const sha='a'.repeat(40),authSha='b'.repeat(40),tree='c'.repeat(40),digest='d'.repeat(64);
const s='00000000-0000-4000-8000-000000000001',e='00000000-0000-4000-8000-000000000002';
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:4096});
const pem=publicKey.export({type:'spki',format:'pem'}),fp=hash(publicKey.export({type:'spki',format:'der'}));
const sources=Object.fromEntries(SOURCE_FILES.map((p,i)=>[p,`unit-fixture-source-${i}`]));
const FLAGS=['hook_custom_access_token_enabled','hook_mfa_verification_attempt_enabled','hook_password_verification_attempt_enabled','hook_send_sms_enabled','hook_send_email_enabled','hook_before_user_created_enabled','hook_after_user_created_enabled'];
const owner=`auth-test-ci-123-1:${authSha}`;
function args() {
  const manifest={schemaVersion:1,purpose:PURPOSE,projectRef:PROJECT,platformId:PLATFORM,authPurpose:'AUTH_ONLY_FRONTEND_V1',authOwner:owner,
    actors:{soignant:s,etablissement:e},authJournalSha256:digest,uiEvidenceSha256:digest,steps:{}};
  const edges=structuredClone(closedContract.edges),endpoints=structuredClone(closedContract.webhookEndpoints);
  const contract={schemaVersion:1,purpose:PURPOSE,ready:true,canExecute:true,projectRef:PROJECT,platformId:PLATFORM,apiVersion:API_VERSION,reviewedSourceSha:sha,reviewedSourceTree:tree,
    sourcePins:Object.fromEntries(SOURCE_FILES.map(p=>[p,hash(sources[p])])),reviewedBy:'Local unit fixture',expiresAt:new Date(Date.now()+3600000).toISOString(),
    actors:{...manifest.actors},authOwner:owner,authSourceSha:authSha,authJournalSha256:digest,uiEvidenceSha256:digest,frontendCompletedReviewed:true,authJournalReviewed:true,stripeWebhookSafetyReviewed:true,
    catalogue:{routinesMd5:'e'.repeat(32),triggersMd5:'f'.repeat(32)},edges,webhookEndpoints:endpoints};
  const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_REF:'refs/heads/main',GITHUB_SHA:sha,EXPECTED_MAIN_SHA:sha,
    GITHUB_RUN_ID:'456',GITHUB_RUN_ATTEMPT:'1',GITHUB_TOKEN:'github-canary-never-persist',STAGING_SUPABASE_ACCESS_TOKEN:'management-canary-never-persist',STRIPE_TEST_SECRET_KEY:'rk_test_canaryNeverPersist',
    RECIPIENT_PUBLIC_KEY:pem,RECIPIENT_SHA256:fp};
  const a={manifest,contract,env,local:{sha,clean:true,sources:{...sources}}};
  manifest.uiEvidenceSha256=contract.uiEvidenceSha256=projectionDigest(transmissionProjection(unitSnapshot(a),manifest));return a;
}
function decrypt(x) {
  const key=privateDecrypt({key:privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(x.wrappedKey,'base64'));
  try{const d=createDecipheriv('aes-256-gcm',key,Buffer.from(x.iv,'base64'));d.setAuthTag(Buffer.from(x.tag,'base64'));
    return JSON.parse(Buffer.concat([d.update(Buffer.from(x.ciphertext,'base64')),d.final()]));}finally{key.fill(0);}
}
function unitSnapshot(a) {
  const auth=(id,role)=>({id,email:`auth-test-${id}@example.invalid`,metadata:{role,est_compte_test:true,is_test_playwright:true,jolene_auth_fixture_owner:owner,jolene_recette_purpose:'AUTH_ONLY_FRONTEND_V1',...(role==='ADMIN_ETABLISSEMENT'?{etablissement_id:id}:{})},confirmed:true,deleted:false,banned:null});
  return {ownerCount:2,auth:[auth(s,'SOIGNANT'),auth(e,'ADMIN_ETABLISSEMENT')],
    soignants:[{id:s,prenom:'TEST',nom:'Synthetique',email:`playwright-test-caregiver-${s}@jolene.app`,est_compte_test:true,supprime_le:null,stripe_account_id:null}],
    etablissements:[{id:e,nom:'TEST Etablissement Synthetique',email_contact:`auth-test-${e}@example.invalid`,est_compte_test:true,supprime_le:null,stripe_customer_id:null,stripe_account_id:null}],
    business:{missions:0,candidatures:0,contracts:0,invoices:0,mandates:0,onboarding:0,payments:0},quiet:{queuedRequests:0,activeCrons:0,runningCrons:0},catalogue:structuredClone(a.contract.catalogue)};
}
function harness(a=args(),{mutate,transport,save}={}) {
  const calls=[],proof=[],created={customers:[],accounts:[]};
  const receipt=unitSnapshot(a);
  const fetcher=async(url,init)=>{
    const u=new URL(url);calls.push({url,init});if(transport)await transport(url,init,calls);
    let value;
    if(u.hostname==='api.github.com') {
      if(u.pathname.endsWith('/git/ref/heads/main'))value={ref:'refs/heads/main',object:{sha,type:'commit'}};
      else if(u.pathname.includes('/git/commits/'))value={sha,tree:{sha:tree}};
      else if(u.pathname.includes('/contents/')){const p=u.pathname.split('/contents/')[1];value={type:'file',encoding:'base64',content:Buffer.from(sources[p]).toString('base64')};}
      else if(u.pathname.endsWith('/actions/runs/123'))value={id:123,run_attempt:1,head_sha:authSha,path:'.github/workflows/connect-test-fixture.yml',status:'completed',conclusion:'success',repository:{full_name:'Gabpcd/JJJJJ'},head_repository:{full_name:'Gabpcd/JJJJJ'}};
      else if(u.pathname.includes('/actions/workflows/'))value={total_count:1,workflow_runs:[{id:456,path:WORKFLOW}]};
      else assert.fail('unexpected GitHub unit path');
    }else if(u.hostname==='api.supabase.com') {
      if(u.pathname.endsWith('/config/auth'))value={...Object.fromEntries(FLAGS.map(k=>[k,false])),hook_send_email_uri:'ignored-existing-config-value'};
      else if(u.pathname.endsWith('/functions'))value=Object.entries(a.contract.edges).map(([slug,pin])=>({slug,status:'ACTIVE',...pin}));
      else if(u.pathname.endsWith('/database/query')){const q=JSON.parse(init.body);assert.match(q.query,/^BEGIN READ ONLY;/);assert.match(q.query,/ROLLBACK;$/);assert.doesNotMatch(q.query,/\b(?:UPDATE|INSERT|DELETE|CREATE|ALTER|DROP)\b/i);value=[{receipt:structuredClone(receipt)}];}
      else value={id:PROJECT,status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`}};
    }else if(u.hostname==='api.stripe.com') {
      assert.equal(init.headers['Stripe-Version'],API_VERSION);
      if(u.pathname==='/v1/account')value={id:PLATFORM};
      else if(u.pathname==='/v1/balance')value={object:'balance',livemode:false};
      else if(u.pathname==='/v1/webhook_endpoints')value={object:'list',has_more:false,data:structuredClone(a.contract.webhookEndpoints)};
      else if(init.method==='POST') {
        assert.ok(['/v1/customers','/v1/accounts'].includes(u.pathname));const b=Object.fromEntries(new URLSearchParams(init.body));
        const metadata=Object.fromEntries(Object.entries(b).filter(([k])=>k.startsWith('metadata[')).map(([k,v])=>[k.slice(9,-1),v]));
        if(u.pathname==='/v1/customers'){value={id:'cus_UnitTestOnly',object:'customer',livemode:false,name:b.name,email:b.email,metadata};created.customers.push(value);}
        else{value={id:'acct_UnitTestOnly',object:'account',type:b.type,country:b.country,business_type:b.business_type,email:b.email,metadata,
          individual:{first_name:b['individual[first_name]'],last_name:b['individual[last_name]'],email:b.email},settings:{payouts:{schedule:{interval:b['settings[payouts][schedule][interval]']}}},
          details_submitted:false,charges_enabled:false,payouts_enabled:false,external_accounts:{data:[]},tos_acceptance:{}};created.accounts.push(value);}
      }else {const kind=u.pathname.startsWith('/v1/customers')?'customers':'accounts';value=u.pathname===`/v1/${kind}`?{object:'list',has_more:false,data:structuredClone(created[kind])}:structuredClone(created[kind].find(x=>u.pathname.endsWith(x.id)));}
    }else assert.fail('unexpected unit hostname');
    if(mutate)value=mutate(u,init,value,receipt,created)??value;
    return {ok:true,redirected:false,text:async()=>JSON.stringify(value)};
  };
  return {a,calls,proof,receipt,created,posts:()=>calls.filter(x=>x.url.startsWith('https://api.stripe.com/')&&x.init.method==='POST'),
    run:()=>prepareStripeTestActors({...a,fetcher,save:async x=>{if(save)await save(x,proof);proof.push(decrypt(x));}})};
}
async function refused(h,code){await assert.rejects(h.run(),e=>e.code===code);return h;}

test('versioned contract is closed or structurally valid at its reviewed deterministic window',async()=>{
  const c=JSON.parse(await readFile(contractUrl));assert.equal(typeof c.ready,'boolean');assert.equal(c.ready,c.canExecute);assert.equal(c.actors,null);assert.equal(c.apiVersion,API_VERSION);
  if(!c.ready)return;
  // An eventual reviewed activation must not break this offline structure test.
  // Runtime Date.now expiry checks remain mandatory in check/run and before POST.
  const localSources=Object.fromEntries(await Promise.all(SOURCE_FILES.map(async p=>{
    const adjacent=new URL('./'+p.split('/').at(-1),moduleUrl),url=existsSync(adjacent)?adjacent:new URL('../../'+p,moduleUrl);
    return [p,await readFile(url,'utf8')];
  })));
  const now=Date.parse(c.expiresAt)-3600000;assert.ok(Number.isFinite(now));
  const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_REF:'refs/heads/main',GITHUB_SHA:sha,EXPECTED_MAIN_SHA:sha,GITHUB_RUN_ID:'1',GITHUB_RUN_ATTEMPT:'1'};
  checkVersionedContext(c,env,{sha,clean:true,sources:localSources},now,false);
});
test('readiness, exact two actors, frontend review, TEST key, main and pins refuse before transport',async()=>{
  const cases=[['ACTORS_OR_NO_RETRY',a=>a.manifest.steps=[]],['ACTORS_OR_NO_RETRY',a=>a.manifest.steps=[{}]],['ACTORS_OR_NO_RETRY',a=>a.manifest.steps=''],['ACTORS_OR_NO_RETRY',a=>a.manifest.steps=Object.create(null)],['READINESS_CLOSED',a=>a.contract.ready=false],['READINESS_CLOSED',a=>a.contract.canExecute=false],['READINESS_CLOSED',a=>delete a.contract.canExecute],['ACTORS_OR_NO_RETRY',a=>a.manifest.actors.admin=s],
    ['ACTORS_OR_NO_RETRY',a=>a.manifest.actors.etablissement=s],['ACTORS_OR_NO_RETRY',a=>a.manifest.steps.customer={state:'intent'}],
    ['CONTRACT',a=>a.contract.expiresAt='2020-01-01T00:00:00.000Z'],['CONTRACT',a=>a.contract.frontendCompletedReviewed=false],['CONTRACT',a=>a.contract.authJournalReviewed=false],
    ['RUNNER_TEST_CREDENTIALS',a=>a.env.STRIPE_TEST_SECRET_KEY='sk_live_forbidden'],['RUNNER_TEST_CREDENTIALS',a=>a.env.STAGING_SUPABASE_SERVICE_ROLE_KEY='forbidden-extra-privilege'],
    ['TRUSTED_MAIN',a=>a.env.GITHUB_RUN_ATTEMPT='2'],['TRUSTED_MAIN',a=>a.env.GITHUB_REF='refs/heads/feature'],['SOURCE_PINS',a=>a.local.sources[SOURCE_FILES[0]]+='changed']];
  for(const [code,change]of cases){const a=args();change(a);const h=harness(a);await refused(h,code);assert.equal(h.calls.length,0);}
});
test('missing checkpoint and failed initial checkpoint have no transport',async()=>{
  const a=args();await assert.rejects(prepareStripeTestActors({...a,fetcher:()=>assert.fail('no transport')}),e=>e.code==='TRANSPORT_AND_CHECKPOINT_REQUIRED');
  const h=harness(a,{save:()=>{throw Error('UNIT_CHECKPOINT_FAIL');}});await assert.rejects(h.run(),/UNIT_CHECKPOINT_FAIL/);assert.equal(h.calls.length,0);
});
test('only encrypted payloads cross the checkpoint boundary; exactly two provider POSTs and zero DB DML',async()=>{
  const h=harness(),r=await h.run();assert.deepEqual(r,{prepared:true,stripeObjectsCreated:2,dbLinked:false,onboardingVerified:false,qualificationVerified:false,paymentCreated:false,refundCreated:false});
  assert.deepEqual(h.posts().map(x=>new URL(x.url).pathname),['/v1/customers','/v1/accounts']);
  assert.equal(new Set(h.posts().map(x=>x.init.headers['Idempotency-Key'])).size,2);
  assert.ok(h.proof.slice(0,-1).every(x=>x.prepared===false));assert.equal(h.proof.at(-1).prepared,true);
  for(const kind of ['customer','account']) {
    assert.ok(h.proof.some(x=>!Array.isArray(x.manifest.steps)&&x.manifest.steps[kind]?.state==='intent'&&x.manifest.steps[kind].requestSha256));
    assert.ok(h.proof.some(x=>!Array.isArray(x.manifest.steps)&&x.manifest.steps[kind]?.state==='done'&&x.manifest.steps[kind].result.id));
  }
  const completed=requireComplete(h.proof.at(-1));assert.equal(completed.manifest.steps.customer.result.id,'cus_UnitTestOnly');assert.equal(completed.manifest.steps.account.result.id,'acct_UnitTestOnly');
  const plaintext=JSON.stringify(h.proof);for(const secret of [h.a.env.GITHUB_TOKEN,h.a.env.STAGING_SUPABASE_ACCESS_TOKEN,h.a.env.STRIPE_TEST_SECRET_KEY])assert.ok(!plaintext.includes(secret));
  assert.ok(!h.calls.some(x=>/api-keys|\/auth\/|\/secrets|generate-invoice|account_links|payment_intents|refunds/.test(x.url)));
});
test('wrong live main, old Auth run, staging identity, key mode and destination refuse before POST',async()=>{
  const changes=[['MAIN_MOVED',u=>u.pathname.endsWith('/git/ref/heads/main'),x=>({...x,object:{sha:authSha,type:'commit'}})],
    ['AUTH_PROVENANCE',u=>u.pathname.endsWith('/actions/runs/123'),x=>({...x,conclusion:'failure'})],
    ['PROJECT_IDENTITY',u=>u.hostname==='api.supabase.com'&&u.pathname.endsWith(PROJECT),x=>({...x,id:'wrong-project'})],
    ['PLATFORM_OR_MODE',u=>u.pathname==='/v1/account',x=>({...x,id:'acct_WrongPlatform'})],
    ['PLATFORM_OR_MODE',u=>u.pathname==='/v1/balance',x=>({...x,livemode:true})],
    ['WEBHOOK_DESTINATIONS',u=>u.pathname==='/v1/webhook_endpoints',x=>({...x,data:x.data.map(y=>({...y,url:'https://jolene.app/unsafe'}))})]];
  for(const [code,match,change]of changes){const h=harness(args(),{mutate:(u,i,x)=>match(u)?change(x):x});await refused(h,code);assert.equal(h.posts().length,0);}
});
test('missing UI profile, non-TEST role/owner, business object, linked Stripe, active queue and catalogue drift refuse',async()=>{
  const cases=[['UI_PROFILES_REQUIRED',x=>x.soignants=[]],['AUTH_OWNERSHIP',x=>x.auth[0].metadata.est_compte_test=false],
    ['AUTH_OWNERSHIP',x=>x.auth[0].metadata.jolene_auth_fixture_owner='other-owner'],['TEST_PROFILE_OR_EXISTING_LINK',x=>x.soignants[0].stripe_account_id='acct_Existing'],
    ['BUSINESS_OR_QUIESCENCE',x=>x.business.missions=1],['BUSINESS_OR_QUIESCENCE',x=>x.quiet.queuedRequests=1],['CATALOGUE_DRIFT',x=>x.catalogue={routinesMd5:'0'.repeat(32),triggersMd5:'0'.repeat(32)}]];
  for(const [code,change]of cases){const h=harness();change(h.receipt);await refused(h,code);assert.equal(h.posts().length,0);}
});
test('new or active hook flags and drifted deployed code refuse before provider creation',async()=>{
  for(const [code,mutate]of [['AUTH_HOOKS',(u,i,x)=>u.pathname.endsWith('/config/auth')?{...x,hook_new_enabled:false}:x],
    ['AUTH_HOOKS',(u,i,x)=>u.pathname.endsWith('/config/auth')?{...x,hook_send_email_enabled:true}:x],
    ['WEBHOOK_EDGE_DRIFT',(u,i,x)=>u.pathname.endsWith('/functions')?x.map(y=>({...y,version:2})):x]]){
    const h=harness(args(),{mutate});await refused(h,code);assert.equal(h.posts().length,0);
  }
});
test('provider metadata/email collision refuses adoption, and incomplete pagination refuses guessing',async()=>{
  for(const [code,mutate]of [['PROVIDER_COLLISION',(u,i,x)=>u.pathname==='/v1/customers'&&i.method==='GET'?{...x,data:[{id:'cus_Foreign',metadata:{etablissement_id:e}}]}:x],
    ['LIST_LIMIT',(u,i,x)=>u.pathname==='/v1/accounts'&&i.method==='GET'?{...x,data:[{id:'acct_PageUnitOnly',metadata:{}}],has_more:true}:x]]){
    const h=harness(args(),{mutate});await refused(h,code);assert.equal(h.posts().length,0);
  }
});
test('intent checkpoint failure stops before sole POST',async()=>{
  const h=harness(args(),{save:(x,proof)=>{if(proof.length===1)throw Error('UNIT_INTENT_SAVE_FAIL');}});
  await assert.rejects(h.run(),/UNIT_INTENT_SAVE_FAIL/);assert.equal(h.posts().length,0);
});
test('ambiguous creation never retries and does not create the second object',async()=>{
  const h=harness(args(),{transport:(url,i)=>{if(url.endsWith('/v1/customers')&&i.method==='POST')throw Error('unit-timeout');}});
  await refused(h,'TRANSPORT_UNCERTAIN');assert.equal(h.posts().length,1);assert.equal(h.a.manifest.steps.customer.state,'intent');
  assert.equal(h.proof.at(-1).prepared,false);const before=h.calls.length;await refused(h,'ACTORS_OR_NO_RETRY');assert.equal(h.calls.length,before);
});
test('bad creation/reread ownership or backend drift cannot hand off prepared=true',async()=>{
  const h=harness(args(),{mutate:(u,i,x,receipt,created)=>{
    if(u.pathname==='/v1/customers'&&i.method==='POST'){receipt.soignants[0].nom='changed-after-intent';}
    return x;
  }});await refused(h,'BACKEND_CHANGED');assert.equal(h.posts().length,1);assert.ok(h.proof.every(x=>!x.prepared));
  const bad=harness(args(),{mutate:(u,i,x)=>u.pathname.endsWith('/cus_UnitTestOnly')?{...x,metadata:{...x.metadata,etablissement_id:s}}:x});
  await refused(bad,'CUSTOMER_RECEIPT');assert.equal(bad.posts().length,1);assert.ok(bad.proof.every(x=>!x.prepared));
});
test('standalone SQL refuses owner interpolation and contains only a rollback read',()=>{
  const a=args();assert.match(snapshotSql(a.manifest),/^BEGIN READ ONLY;/);a.manifest.authOwner="x'; SELECT 1; --";
  assert.throws(()=>snapshotSql(a.manifest),e=>e.code==='ACTORS');
});
test('Express enabled/onboarded or connected LIVE balance never yields a success handoff',async()=>{
  for(const [code,mutate]of [['EXPRESS_RECEIPT',(u,i,x)=>u.pathname==='/v1/accounts'&&i.method==='POST'?{...x,charges_enabled:true}:x],
    ['CONNECTED_TEST_MODE',(u,i,x)=>u.pathname==='/v1/balance'&&i.headers['Stripe-Account']?{...x,livemode:true}:x]]) {
    const h=harness(args(),{mutate});await refused(h,code);assert.equal(h.posts().length,2);assert.ok(h.proof.every(x=>!x.prepared));
  }
});
test('a checkpoint final pathname is closed before any file write',async()=>{
  await assert.rejects(writeEncryptedCheckpoint('/private/tmp/arbitrary-plaintext.json',{format:'plaintext'}),e=>e.code==='PRIVATE_OUTPUT_PATH');
});
test('review P2: every initial transmitted profile value is bound before the first POST',async()=>{
  for(const [table,key]of [['soignants','prenom'],['soignants','nom'],['soignants','email'],['etablissements','nom'],['etablissements','email_contact']]) {
    const h=harness();h.receipt[table][0][key]='unreviewed-unit-value@example.invalid';
    await refused(h,'UI_TRANSMISSION_PROJECTION');assert.equal(h.posts().length,0);assert.equal(h.proof.at(-1).prepared,false);
  }
});
test('review P2: exact three webhook pins allow only two stage endpoints and the disabled historical endpoint',async()=>{
  const valid=harness();await valid.run();assert.equal(valid.posts().length,2);
  for(const change of [xs=>xs[2].status='enabled',xs=>xs[2].url='https://unreviewed.invalid/webhook',xs=>xs[2].api_version=API_VERSION,
    xs=>xs.push({...xs[0],id:'we_Unexpected'}),xs=>xs[0].status='disabled']) {
    const a=args();change(a.contract.webhookEndpoints);const h=harness(a);await refused(h,'WEBHOOK_DESTINATIONS');assert.equal(h.posts().length,0);
  }
  const drift=harness(args(),{mutate:(u,i,x)=>u.pathname==='/v1/webhook_endpoints'?{...x,data:x.data.map((row,index)=>index?row:{...row,enabled_events:[...row.enabled_events,'unreviewed.event']})}:x});
  await refused(drift,'WEBHOOK_DESTINATIONS');assert.equal(drift.posts().length,0);
});
test('review P2: arrays and non-object steps refuse before any transport',async()=>{
  for(const steps of [[],[{}],null,'',true,0,Object.create(null)]) {
    const a=args();a.manifest.steps=steps;const h=harness(a);await refused(h,'ACTORS_OR_NO_RETRY');assert.equal(h.calls.length,0);
  }
});
test('expiry during encrypted intent checkpoint prevents the provider POST',async()=>{
  const a=args(),realNow=Date.now,end=realNow()+60000;a.contract.expiresAt=new Date(end).toISOString();
  const h=harness(a,{save:(_x,proof)=>{if(proof.length===1)Date.now=()=>end+1;}});
  try{await refused(h,'CONTRACT_EXPIRED');assert.equal(h.posts().length,0);assert.equal(h.proof.at(-1).manifest.steps.customer.state,'intent');}
  finally{Date.now=realNow;}
});
test('private owner discovery binds two current UI actors without publishing UIDs',async()=>{
  const a=args(),publicContract={...a.contract,actors:null},snapshot=unitSnapshot(a);
  const derived=deriveActors(snapshot,publicContract);assert.deepEqual(derived.manifest.actors,{soignant:s,etablissement:e});assert.deepEqual(derived.contract.actors,{soignant:s,etablissement:e});assert.equal(publicContract.actors,null);
  const fake=async(url,init)=>({ok:true,redirected:false,text:async()=>JSON.stringify(url.endsWith('/database/query')?[{receipt:snapshot}]:{id:PROJECT,status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`}})});
  assert.deepEqual((await readOwnedActors(publicContract,a.env,fake)).manifest.actors,{soignant:s,etablissement:e});
  for(const change of [x=>x.ownerCount=3,x=>x.auth.push({...x.auth[0]}),x=>x.auth[1].metadata.role='SOIGNANT',x=>delete x.auth[1].metadata.etablissement_id,
    x=>x.auth[1].metadata.etablissement_id=s,x=>x.auth[0].metadata.etablissement_id=e,x=>x.etablissements=[],x=>x.soignants[0].prenom='changed-before-discovery']) {
    const bad=unitSnapshot(a);change(bad);assert.throws(()=>deriveActors(bad,publicContract));
  }
  assert.throws(()=>checkVersionedContext(a.contract,a.env,a.local),e=>e.code==='VERSIONED_UIDS_FORBIDDEN');
  assert.doesNotMatch(discoverySql(publicContract),/\b(?:UPDATE|INSERT|DELETE|CREATE|ALTER|DROP)\b/i);assert.ok(!discoverySql(publicContract).includes(s));
});
test('signed establishment scope must match the actor and remain absent on caregiver',async()=>{
  for(const change of [x=>delete x.auth[1].metadata.etablissement_id,x=>x.auth[1].metadata.etablissement_id=s,x=>x.auth[0].metadata.etablissement_id=e]) {
    const h=harness();change(h.receipt);await refused(h,'AUTH_OWNERSHIP');assert.equal(h.posts().length,0);
  }
});
test('CLI is closed before git/network, and workflow inputs contain only three public fields',async()=>{
  const directory=await realpath(await mkdtemp(join(tmpdir(),'stripe-provider-initial-closed-cli-unit-')));
  try {
    for(const url of [moduleUrl,cliUrl])await writeFile(join(directory,url.pathname.split('/').at(-1)),await readFile(url),{mode:0o600});
    await writeFile(join(directory,'stripe-test-provider-actors.contract.json'),JSON.stringify({...closedContract,ready:false,canExecute:false}),{mode:0o600});
    for(const mode of ['check','run']) {
      const r=spawnSync(process.execPath,[join(directory,'stripe-test-provider-actors-ci.mjs'),mode],{env:{PATH:''},encoding:'utf8'});
      assert.equal(r.status,1);assert.equal(r.stdout,'');assert.deepEqual(JSON.parse(r.stderr),{prepared:false,code:'READINESS_CLOSED'});
    }
  }finally{await rm(directory,{recursive:true,force:true});}
  const yml=await readFile(existsSync(new URL('./stripe-test-provider-actors.yml',moduleUrl))?new URL('./stripe-test-provider-actors.yml',moduleUrl):new URL('../../.github/workflows/stripe-test-provider-actors.yml',moduleUrl),'utf8');
  const inputBlock=yml.split('    inputs:')[1].split('\npermissions:')[0];
  assert.deepEqual([...inputBlock.matchAll(/^      ([a-z0-9_]+):$/gm)].map(x=>x[1]),['expected_main_sha','recipient_public_key','recipient_sha256']);
  assert.doesNotMatch(inputBlock,/password|phone|email|actor|soignant|etablissement/i);
  assert.match(yml,/group: jolene-supabase-staging-writes/);assert.match(yml,/persist-credentials: false/);
  assert.equal([...yml.matchAll(/secrets\./g)].length,2);assert.ok(yml.indexOf('secrets.')>yml.indexOf('Deux objets fournisseur TEST uniquement'));
});
test('CLI ready=true with canExecute=false or missing refuses before git/network',async()=>{
  const directory=await realpath(await mkdtemp(join(tmpdir(),'stripe-provider-closed-cli-unit-')));
  try {
    for(const url of [moduleUrl,cliUrl])await writeFile(join(directory,url.pathname.split('/').at(-1)),await readFile(url),{mode:0o600});
    for(const canExecute of [false,undefined]) {
      const contract={...closedContract,ready:true};if(canExecute===undefined)delete contract.canExecute;else contract.canExecute=canExecute;
      await writeFile(join(directory,'stripe-test-provider-actors.contract.json'),JSON.stringify(contract),{mode:0o600});
      for(const mode of ['check','run']) {
        const r=spawnSync(process.execPath,[join(directory,'stripe-test-provider-actors-ci.mjs'),mode],{env:{PATH:''},encoding:'utf8'});
        assert.equal(r.status,1);assert.equal(r.stdout,'');assert.deepEqual(JSON.parse(r.stderr),{prepared:false,code:'READINESS_CLOSED'});
      }
    }
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('local opening refuses initial/intent/forged/array journals before mkdir and opens only a complete encrypted receipt',async()=>{
  const h=harness();await h.run();const rsa=recipientKey(pem,fp),complete=h.proof.at(-1);
  assert.equal(openCompleteJournal(sealJournal(complete,rsa),privateKey.export({type:'pkcs8',format:'pem'}),fp).manifest.steps.account.result.id,'acct_UnitTestOnly');
  const directory=await realpath(await mkdtemp(join(tmpdir(),'stripe-provider-cli-unit-')));
  try{
    const keyPath=join(directory,'key.pem');await writeFile(keyPath,privateKey.export({type:'pkcs8',format:'pem'}),{mode:0o600});
    const forged=structuredClone(complete);forged.manifest.steps=[];
    for(const [index,payload]of [h.proof[0],h.proof.find(x=>x.manifest.steps.customer?.state==='intent'),{...h.proof[0],prepared:true,result:complete.result},forged].entries()) {
      const input=join(directory,`partial-${index}.json`),output=join(directory,`refused-${index}`),encrypted=JSON.stringify(sealJournal(payload,rsa));await writeFile(input,encrypted,{mode:0o600});
      await assert.rejects(openPrivateHandoff({input,keyPath,expectedHash:hash(encrypted),fingerprint:fp,output}),e=>e.code==='INCOMPLETE_HANDOFF');
      await assert.rejects(access(output));
    }
    const input=join(directory,'complete.json'),output=join(directory,'opened'),encrypted=JSON.stringify(sealJournal(complete,rsa));await writeFile(input,encrypted,{mode:0o600});
    assert.deepEqual(await openPrivateHandoff({input,keyPath,expectedHash:hash(encrypted),fingerprint:fp,output}),{opened:true,credentialsPrinted:false,providerIdsPrinted:false,dbLinked:false});
    const handoff=JSON.parse(await readFile(join(output,'provider-handoff.private.json')));assert.equal(handoff.customerId,'cus_UnitTestOnly');assert.equal(handoff.connectedAccountId,'acct_UnitTestOnly');
    for(const v of [h.a.env.GITHUB_TOKEN,h.a.env.STAGING_SUPABASE_ACCESS_TOKEN,h.a.env.STRIPE_TEST_SECRET_KEY])assert.ok(!JSON.stringify(handoff).includes(v));
  }finally{await rm(directory,{recursive:true,force:true});}
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, mkdtemp, stat, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { newManifest, validateManifest, checkContract, validateAuth, validateCustomer, validateAccount, validateSnapshot,
  executePreparation, privateRead, privateWrite, readOnlySql, CLOSED_CONTRACT, PROJECT, PLATFORM, EXCLUDED_ACCOUNT } from '../../scripts/ci/connect-test-fixture.mjs';
import { preflightSql, snapshotSql, transactionSql, linkSql, catalogueSqlFixture, calendarProofSql } from '../../scripts/ci/connect-test-fixture-sql.mjs';
const seed=await readFile(new URL('../../scripts/ci/connect-test-fixture-prepare.sql',import.meta.url),'utf8');
const sha='a'.repeat(40),hash=createHash('sha256').update(seed).digest('hex');
const manifest=()=>newManifest('connect-test-node-proof',sha);
const catalogue={routines:'1'.repeat(32),triggers:'2'.repeat(32),columns:'3'.repeat(32),commissionHelper:'4'.repeat(32),queuedRequests:0,activeCrons:0,runningCrons:0,generationUrlAbsent:true,supportStagingExact:true,gateClosed:true,capacitiesEmpty:true,operationsEmpty:true};
const edges=Object.fromEntries(['generate-invoice','send-email','notify-support'].map(x=>[x,{version:7,verify_jwt:false,ezbr_sha256:'a'.repeat(64)}]));
const contract=()=>({...CLOSED_CONTRACT,ready:true,sourceSha:sha,seedSha256:hash,expiresAt:new Date(Date.now()+3600000).toISOString(),reviewedBy:'node transport simulation',notificationsTestSkipReviewed:true,catalogue,edges});
const auth=(a,m)=>({id:a.id,email:a.email,email_confirmed_at:'2026-01-01T00:00:00Z',app_metadata:{role:a.role,est_compte_test:true,jolene_connect_fixture_owner:m.sql.ownerMarker,...(a.role==='ADMIN_ETABLISSEMENT'?{etablissement_id:a.id}:{})}});
const customer=m=>({id:'cus_fixture',object:'customer',livemode:false,name:'TEST Clinique Connect Synthétique',email:m.members[1].email,metadata:{etablissement_id:m.members[1].id,jolene_connect_fixture_owner:m.sql.ownerMarker}});
const account=m=>({id:'acct_fixture',object:'account',type:'express',country:'FR',email:m.members[0].email,details_submitted:false,charges_enabled:false,payouts_enabled:false,settings:{payouts:{schedule:{interval:'manual'}}},metadata:{soignant_id:m.members[0].id,jolene_connect_fixture_owner:m.sql.ownerMarker}});
const env={STAGING_SUPABASE_ACCESS_TOKEN:'management-test-fixture-token',STAGING_SUPABASE_SERVICE_ROLE_KEY:'service-test-fixture-token',STAGING_SUPABASE_ANON_KEY:'anon-test-fixture-token',STRIPE_TEST_SECRET_KEY:'rk_test_fixture'};
const invoiceId='10000000-0000-4000-8000-000000000001',commissionId='10000000-0000-4000-8000-000000000002';
function harness(m,options={}) {
  const state={auth:[],seeded:false,linked:false,generated:false,calls:[],writes:[],...options.state};
  const snapshot=()=>({auth:state.auth,soignants:state.seeded?[{id:m.members[0].id,email:m.members[0].email,test:true,source:'RECETTE_CONNECT_TEST_SYNTHETIQUE',account:state.linked?'acct_fixture':null,sms:false,smsAlerts:false,defacto:false}]:[],
    etablissements:state.seeded?[{id:m.members[1].id,email:m.members[1].email,test:true,source:'RECETTE_CONNECT_TEST_SYNTHETIQUE',customer:state.linked?'cus_fixture':null,sms:false,chorus:false}]:[],
    mission:state.seeded?{id:m.sql.ids.mission,soignant:m.members[0].id,etablissement:m.members[1].id,status:'EN_COURS',label:`RECETTE CONNECT TEST SYNTHETIQUE ${m.sql.runId}`,hours:8,effective:4,net:160,commission:24,startsOn:options.missionStartsOn??'2026-09-21',endsOn:'2026-10-09'}:null,
    preferencesClosed:state.seeded,activeAdmin:0,payments:0,paymentClaims:0,emailQueue:0,emailRetries:0,emailSkips:state.generated?2:0,
    onboarding:state.linked?[{account:'acct_fixture',soignant:m.members[0].id,status:'EN_COURS',complete:false,charges:false,payouts:false,details:false}]:[],
    invoices:state.generated?[{id:invoiceId,soignant:m.members[0].id,etablissement:m.members[1].id,status:'EMISE',kind:'FACTURE',nature:'ORIGINALE',total:80,paid:false,versions:1,pdf:'invoices/synthetic.pdf',xml:'invoices/synthetic.xml'}]:[],
    commissions:state.generated?[{id:commissionId,honoraire:invoiceId,status:'EMISE',kind:'FACTURE',total:14.4,linked:false}]:[]});
  const fetcher=async(url,init)=>{
    const u=new URL(url);state.calls.push({url,init});let result;
    if(init.method==='POST'&&!(u.pathname.endsWith('/database/query')&&JSON.parse(init.body).query.startsWith('BEGIN READ ONLY;')))state.writes.push({url,init});
    if(options.before)await options.before(url,init,state);
    if(u.hostname==='api.github.com')result={ref:'refs/heads/main',object:{type:'commit',sha}};
    else if(u.hostname==='api.supabase.com') {
      if(u.pathname.endsWith('/functions'))result=Object.entries(edges).map(([slug,pin])=>({slug,status:'ACTIVE',...pin}));
      else if(u.pathname.endsWith('/database/query')) {
        const {query,read_only}=JSON.parse(init.body);
        assert.equal(read_only,false);
        if(query.startsWith('BEGIN READ ONLY;')&&query.includes("'gateClosed'"))result=[{receipt:catalogue}];
        else if(query.startsWith('BEGIN READ ONLY;'))result=[{receipt:snapshot()}];
        else if(query.includes('INSERT INTO public.soignants')) {state.seeded=true;result=[{receipt:{runId:m.sql.runId,missionId:m.sql.ids.mission,montantOriginal:80,commissionTtc:14.4,signatureSynthetique:true,qualificationVerifiee:false,mfaProuve:false,periodeDebut:'2026-09-21',periodeFin:'2026-09-27'}}];}
        else {state.linked=true;result=[{receipt:{linked:true}}];}
      }else result={id:PROJECT,status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`}};
    }else if(u.hostname==='api.stripe.com') {
      if(u.pathname==='/v1/account')result={id:PLATFORM};
      else if(u.pathname==='/v1/balance')result={livemode:false};
      else if(u.pathname.startsWith('/v1/customers'))result=customer(m);
      else if(u.pathname.startsWith('/v1/accounts'))result=account(m);
      else assert.fail(`Forbidden Stripe endpoint ${u.pathname}`);
    }else if(u.pathname==='/auth/v1/admin/users') {
      const body=JSON.parse(init.body),a=m.members.find(x=>x.id===body.id);assert.equal(body.email_confirm,true);result=auth(a,m);state.auth.push(result);
    }else if(u.pathname.startsWith('/auth/v1/admin/users/'))result={user:state.auth.find(x=>x.id===u.pathname.split('/').at(-1))};
    else if(u.pathname==='/auth/v1/token')result={user:auth(m.members[0],m),access_token:'private-login-token-never-save'};
    else if(u.pathname==='/functions/v1/generate-invoice') {state.generated=true;result={facture_id:invoiceId,pdf_path:'invoices/synthetic.pdf',xml_path:'invoices/synthetic.xml'};}
    else assert.fail(`Forbidden endpoint ${u.pathname}`);
    return {ok:true,redirected:false,text:async()=>JSON.stringify(result)};
  };
  return {state,snapshot,fetcher};
}
const run=(m,h,c=contract(),save=async()=>{})=>executePreparation({manifest:m,contract:c,env,seed,local:{sha,clean:true},fetcher:h.fetcher,save});

test('shipped closure refuses before credential, network or journal work',async()=>{
  let called=false;await assert.rejects(executePreparation({manifest:manifest(),contract:CLOSED_CONTRACT,fetcher:async()=>{called=true;}}),/READINESS_CLOSED/);assert.equal(called,false);
});
test('contract requires explicit provenance, reviewed notifications, closed pins and fresh expiry',()=>{
  const m=manifest();checkContract(contract(),m,seed);
  for(const delta of [{sourceSha:'b'.repeat(40)},{seedSha256:'b'.repeat(64)},{expiresAt:'2020-01-01'},{notificationsTestSkipReviewed:false},{protocolEnabled:true},{capabilityEnabled:true},{catalogue:{...catalogue,activeCrons:1}}])assert.throws(()=>checkContract({...contract(),...delta},m,seed));
  assert.throws(()=>checkContract(contract(),m,`${seed}\n`));
});
test('manifest refuses reclassification and historical actor substitutions',()=>{
  const m=manifest();validateManifest(m);const copy=structuredClone(m);copy.members[0].email='historical@example.com';assert.throws(()=>validateManifest(copy));
  for(const delta of [{est_compte_test:false},{jolene_connect_fixture_owner:'old'},{role:'ADMIN_PLATEFORME'}]) {const a=auth(m.members[0],m);a.app_metadata={...a.app_metadata,...delta};assert.throws(()=>validateAuth(a,m.members[0],m),/AUTH_OWNERSHIP/);}
  const h=harness(m);const r=h.snapshot();r.soignants.push({id:m.members[0].id});assert.throws(()=>validateSnapshot(r,m,'empty'),/HISTORICAL_COLLISION/);
});
test('provider objects require TEST, dedicated ownership, FR Express and no fabricated onboarding',()=>{
  const m=manifest();validateCustomer(customer(m),m);validateAccount(account(m),m);
  for(const delta of [{livemode:true},{metadata:{}},{email:'historical@example.invalid'}])assert.throws(()=>validateCustomer({...customer(m),...delta},m));
  for(const delta of [{id:EXCLUDED_ACCOUNT},{id:PLATFORM},{type:'custom'},{country:'US'},{details_submitted:true},{charges_enabled:true},{metadata:{}}])assert.throws(()=>validateAccount({...account(m),...delta},m));
});
test('simulated preparation creates only three fresh Auth actors, two Stripe objects and a real generator call; completed resume writes nothing',async()=>{
  const m=manifest(),h=harness(m),journals=[];const result=await run(m,h,contract(),async x=>journals.push(JSON.stringify(x)));
  assert.equal(result.prepared,true);assert.equal(result.onboardingComplete,false);assert.equal(result.uiPaymentVerified,false);assert.equal(result.invoiceId,invoiceId);
  assert.equal(h.state.writes.filter(x=>x.url.includes('/auth/v1/admin/users')).length,3);
  const stripe=h.state.writes.filter(x=>x.url.startsWith('https://api.stripe.com'));
  assert.deepEqual(stripe.map(x=>new URL(x.url).pathname),['/v1/customers','/v1/accounts']);
  assert.equal(stripe[0].init.headers['Idempotency-Key'],`customer_etablissement_${m.members[1].id}`);
  assert.equal(stripe[1].init.headers['Idempotency-Key'],`connect_account_${m.members[0].id}`);
  assert.equal(new URLSearchParams(stripe[1].init.body).get('type'),'express');
  const generation=h.state.writes.filter(x=>x.url.endsWith('/functions/v1/generate-invoice'));assert.equal(generation.length,1);
  assert.equal(JSON.parse(generation[0].init.body).mission_id,m.sql.ids.mission);assert.equal(JSON.parse(generation[0].init.body).est_facture_finale_mission,false);
  assert.ok(journals.every(x=>!x.includes('private-login-token-never-save')&&!x.includes('rk_test_')));
  const writes=h.state.writes.length;await run(m,h);assert.equal(h.state.writes.length,writes);
});
test('a lost provider receipt stays ambiguous on resume without a second create',async()=>{
  const m=manifest(),h=harness(m,{before:async(url,init)=>{if(url==='https://api.stripe.com/v1/accounts'&&init.method==='POST')throw Error('secret-token must not leak');}});
  await assert.rejects(run(m,h),/TRANSPORT_OR_JSON_UNCERTAIN/);assert.equal(m.steps.account.state,'intent');
  const n=h.state.calls.length;await assert.rejects(run(m,h),/AMBIGUOUS_PREVIOUS_ATTEMPT/);assert.equal(h.state.calls.length,n);
});
test('live key and wrong provenance refuse before any transport',async()=>{
  for(const delta of [{env:{...env,STRIPE_TEST_SECRET_KEY:'sk_live_forbidden'}},{local:{sha:'b'.repeat(40),clean:true}},{local:{sha,clean:false}}]) {
    let n=0;await assert.rejects(executePreparation({manifest:manifest(),contract:contract(),seed,env,local:{sha,clean:true},fetcher:async()=>{n++;},...delta}));assert.equal(n,0);
  }
});
test('SQL never inserts or forces an invoice or opens a release/capability',()=>{
  const m=manifest(),sql=transactionSql(m,catalogue,seed)+linkSql(m.sql,customer(m),account(m));
  assert.doesNotMatch(sql,/(?:INSERT INTO|UPDATE) public\.factures(?:_honoraires)?\b/i);
  assert.doesNotMatch(sql,/(?:INSERT INTO|UPDATE) private\.stripe_connect_(?:test_capacities|release_gate)/i);
  assert.doesNotMatch(sql,/DISABLE TRIGGER|session_replication_role|ALTER TABLE/i);
  assert.match(sql,/fn_signer_mandat_facturation_serveur/);assert.match(sql,/fn_confirmer_nature_tva_mission/);
  assert.match(sql,/UPDATE public\.equipe_admin SET actif=false/);assert.match(sql,/canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false/);
  assert.match(preflightSql(),/enabled IS FALSE/);assert.ok(!snapshotSql(m.sql).includes(m.members[0].password));
});
test('private journal files are 0600 and permissive reads are rejected',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'connect-test-fixture-node-')),path=join(dir,'manifest.private.json');
  try {await privateWrite(path,{test:1});assert.equal((await stat(path)).mode&0o777,0o600);assert.deepEqual(await privateRead(path),{test:1});
    await privateWrite(path,{test:2},true);assert.deepEqual(await privateRead(path),{test:2});await chmod(path,0o644);await assert.rejects(privateRead(path),/PRIVATE_FILE/);
  }finally{await rm(dir,{recursive:true,force:true});}
});

// This check reads the actual versioned schema, not mocked HTTP results. It is
// deliberately limited to the commission SELECT where the missing column lived.
test('commission snapshot references existing columns in the versioned factures table',async()=>{
  const schema=await readFile(new URL('../../supabase/schema/public.sql',import.meta.url),'utf8');
  const table=schema.match(/CREATE TABLE IF NOT EXISTS "public"\."factures" \(([\s\S]*?)\n\);/)[1];
  const columns=new Set([...table.matchAll(/^    "([^"]+)"/gm)].map(x=>x[1]));
  const expression=snapshotSql(manifest().sql).match(/'commissions',\(SELECT ([\s\S]*?) FROM public\.factures WHERE/)[1];
  const words=expression.replace(/'(?:[^']|'')*'/g,' ').match(/[a-z_][a-z0-9_]*/gi);
  const syntax=new Set(['coalesce','jsonb_agg','jsonb_build_object','is','not','null','or']);
  for(const word of words)assert.ok(syntax.has(word.toLowerCase())||columns.has(word),`Unknown factures column: ${word}`);
});
test('a preexisting payment claim blocks preparation even without a transfer row',()=>{
  const m=manifest(),h=harness(m),r=h.snapshot();r.paymentClaims=1;assert.throws(()=>validateSnapshot(r,m,'empty'),/UNEXPECTED_EFFECTS/);
  assert.match(snapshotSql(m.sql),/FROM public\.stripe_payment_flow_claims WHERE resource_key='MISSION:'/);
});
test('an invoice period outside mission bounds is refused before Stripe creations',async()=>{
  const m=manifest(),h=harness(m,{missionStartsOn:'2026-09-22'});
  await assert.rejects(run(m,h),/PERIOD_OUTSIDE_MISSION/);
  assert.equal(h.state.writes.filter(x=>x.url.startsWith('https://api.stripe.com')).length,0);
  assert.match(seed,/INTO semaine FROM generate_series[\s\S]*?interval '-7 days'[\s\S]*?WHERE NOT public\.fn_est_jour_ferie/);
  assert.match(seed,/passe := semaine;/);assert.match(seed,/debut_le::date=semaine/);
});

test('catalogue casts internal char and calendar witness injects holidays only in SELECT CTEs',()=>{
  const catalogue=catalogueSqlFixture();assert.match(catalogue,/t\.tgenabled::text/);
  assert.doesNotMatch(catalogue,/\|\|t\.tgenabled(?!::text)/);
  for(const column of ['n.nspname','c.relname','a.attname'])assert.ok(catalogue.includes(`${column}::text||`));
  const calendar=calendarProofSql();assert.match(calendar,/injected_holidays\(day\) AS \(VALUES/);
  assert.match(calendar,/week_start=expected_week/);assert.match(calendar,/2026-04-06/);assert.match(calendar,/2026-05-25/);
  assert.doesNotMatch(calendar,/\b(?:INSERT|UPDATE|DELETE|ALTER|CREATE|DROP)\b/i);
});

test('operator catalogue reads preserve Vault guard inside a PostgreSQL read-only transaction',()=>{
  const sql=readOnlySql(preflightSql());
  assert.match(sql,/^BEGIN READ ONLY;/);assert.match(sql,/ROLLBACK;$/);
  assert.match(sql,/current_setting\('transaction_read_only'\)<>'on'/);
  assert.match(sql,/current_user NOT IN \('postgres','supabase_admin'\)/);
  assert.match(sql,/FROM vault\.decrypted_secrets/);assert.match(sql,/'supportStagingExact'/);
  assert.doesNotMatch(sql,/\b(?:COMMIT|GRANT|REVOKE)\b/);
  assert.throws(()=>readOnlySql('BEGIN; SELECT 1; COMMIT;'),/READ_ONLY_SELECT_REQUIRED/);
  assert.throws(()=>readOnlySql('SELECT 1; COMMIT; UPDATE public.notifications SET lu=true;'),/READ_ONLY_SELECT_REQUIRED/);
});

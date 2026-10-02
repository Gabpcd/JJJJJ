import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {expectedDefaultAclGrants,QUALIFICATION_DEFAULT_ACL_ALIGN,QUALIFICATION_DEFAULT_ACL_PROBE,projectSqlDiagnostic,SQL_DIAGNOSTIC_CATEGORIES,makePlan,validatePlan,qualificationPsqlArgs,QUALIFICATION_DB,QUALIFICATION_ARGS,QUALIFICATION_OWNER_REPAIR,ownerRepairPsqlArgs,validateInspection} from './bootstrap.mjs';
import {projectDefaultAclProbe,checkDefaultAclProbe,HISTORICAL_MANIFEST_PATH,HISTORICAL_MANIFEST_SHA,historicalManifestEntries,historicalManifestSQL,projectHistoricalManifest,PRODUCT_SHA,QUALIFICATION_BRANCH,TEST_PATH,checkVercel,checkIdentity,buildReplay,qualify,hash,safeFailure,LOCAL_GUARD,STOP_CRONS,QUIESCENCE,zeros,ownerProbe,projectOwnerProbe} from './qualify-import.mjs';
const run='jolene-restore-drill-12345-1',head='a'.repeat(40);
const env={GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:'refs/heads/'+QUALIFICATION_BRANCH,GITHUB_RUN_ID:'12345',GITHUB_RUN_ATTEMPT:'1',GITHUB_SHA:head};
const lock=JSON.parse(readFileSync(new URL('../../images.lock.json',import.meta.url)));
const requirements=JSON.parse(readFileSync(new URL('../export/scope.json',import.meta.url))).extensions;
const secrets={source:{password:'SOURCE_CANARY',jwt:'LOCAL_CANARY'},target:{password:'TARGET_CANARY',jwt:'OTHER_CANARY'}};
const paths=['supabase/migrations/20261002064017_lire_candidatures_mission_habilitee.sql','supabase/migrations/00000000000000_baseline_prod.sql','supabase/migrations/20260101000000_before.sql'];
const byteMap=new Map([...paths,TEST_PATH].map((p,i)=>[p,Buffer.from('-- '+i+'\r\nSELECT '+i+';\r\n')]));
const load=p=>byteMap.get(p);
const replay=()=>buildReplay(paths,load,load);
const evidence=()=>({...checkIdentity(env,head,['tools/restore-local/scripts/restore/qualify-import.mjs'],''),...replay()});
const runtimeExtensions=()=>({postgres_major:17,extensions:requirements.map(e=>({name:e.name,installed:{version:e.version,schema:e.schema},available_count:1,available_truncated:false,available_versions:[{version:e.version,superuser:true,trusted:false,relocatable:false,schema:e.schema,requires:null}]}))});
const zeroValue=()=>Object.fromEntries(['auth_users','auth_sessions','soignants','etablissements','missions','candidatures','members','externalisations','storage_objects','active_crons','cron_executions','http_queue','http_responses','vault_secrets'].map(k=>[k,0]));
const nativeOwner=(repaired=false)=>({local_empty_context:true,session_postgres:true,named_owner:repaired?'postgres':'supabase_admin',native_owner:'postgres',named_create:repaired,native_create:true,named_connect:true,native_connect:true,named_temp:true,native_temp:true,postgres_superuser:false,admin_superuser:true});
const nativeDefaults=(aligned=false)=>({local_empty_context:true,postgres_superuser:false,global_client_grants:0,target_grants:aligned?[]:expectedDefaultAclGrants(),other_acl_count:111,other_acl_md5:'a'.repeat(32)});
function fakeRuntime(options={}){
 let repaired=false,defaultsAligned=false;
 const calls=[],extensionSQL=Buffer.from('CANONICAL_EXTENSION_SQL');
 return {calls,extensionSQL,run,
 probeDatabaseOwner(){calls.push({ownerProbe:true,repaired});return structuredClone(repaired?(options.ownerAfter??nativeOwner(true)):(options.ownerBefore??nativeOwner()));},
 repairDatabaseOwner(){calls.push({ownerRepair:true});repaired=true;},
  probeDefaultAcls(){calls.push({defaultsProbe:true,defaultsAligned});return structuredClone(defaultsAligned?(options.defaultsAfter??nativeDefaults(true)):(options.defaultsBefore??nativeDefaults()));},
  alignDefaultAcls(){calls.push({defaultsAlign:true});defaultsAligned=true;},
 verify(){calls.push({verify:true});},sql(bytes,flags={}){
  calls.push({bytes,flags});if(options.failOn&&options.failOn(bytes,flags))throw Error('CANARY_SECRET');
  if(bytes.toString()===STOP_CRONS)return JSON.stringify({locally_disabled_jobs:4});
  if(bytes.toString()===QUIESCENCE)return JSON.stringify(zeroValue());
  if(bytes.equals(extensionSQL))return JSON.stringify(runtimeExtensions());
  return '';
 }};
}
test('qualification identity accepts only manual branch with exact product ancestry handled by source',()=>{
 const result=checkIdentity(env,head,['.github/workflows/restore-local-bootstrap.yml'],'');assert.equal(result.product_sha,PRODUCT_SHA);assert.equal(result.run,run);
 for(const changes of [['supabase/migrations/changed.sql'],['tests/security/candidatures-multi-etablissements.test.sql'],[]])assert.throws(()=>checkIdentity(env,head,changes,''));
 for(const patch of [{GITHUB_REPOSITORY:'other/repo'},{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_EVENT_NAME:'push'},{GITHUB_REF:'refs/heads/main'},{GITHUB_SHA:'b'.repeat(40)},{GITHUB_RUN_ID:'unsafe'},{GITHUB_RUN_ATTEMPT:''}])assert.throws(()=>checkIdentity({...env,...patch},head,['tools/restore-local/scripts/restore/qualify-import.mjs'],''));
 assert.throws(()=>checkIdentity(env,head,['tools/restore-local/scripts/restore/qualify-import.mjs'],' M source'));
});
test('ordered full replay uses exact Buffer objects; no newline or statement normalization',()=>{
 const result=replay();assert.equal(result.migrations.length,paths.length);assert.deepEqual(result.migrations.map(x=>x.path),[...paths].sort());
 for(const x of [...result.migrations,result.test]){assert.equal(x.bytes,load(x.path));assert.equal(x.sha256,hash(load(x.path)));assert.ok(x.bytes.includes(Buffer.from('\r\n')));}
 assert.equal(result.test.path,TEST_PATH);
});
test('missing baseline, last migration, duplicate or unexpected extension refuses rather than skips',()=>{
 for(const list of [paths.slice(1),paths.slice(0,1),[...paths,paths[1]],[...paths,'supabase/migrations/unsafe.txt']])assert.throws(()=>buildReplay(list,load,load));
 assert.throws(()=>buildReplay(paths,load,p=>Buffer.concat([load(p),Buffer.from('\n')])));
});
test('qualification retains pinned images and isolation while changing only local database/settings',()=>{
 const base=makePlan(run,'/tmp/unit',lock,secrets),p=makePlan(run,'/tmp/unit',lock,secrets,{qualification:true});assert.equal(validatePlan(p,run),true);
 assert.equal(p.networks.isolated.internal,true);assert.equal(Object.keys(p.services).length,10);
 for(const side of ['source','target']){
  const db=p.services[side+'-db'];assert.equal(db.environment.POSTGRES_DB,QUALIFICATION_DB);assert.equal(db.environment.PGDATABASE,QUALIFICATION_DB);assert.deepEqual(db.command.slice(-QUALIFICATION_ARGS.length),QUALIFICATION_ARGS);
  for(const role of ['db','auth','rest','storage','api']){const s=p.services[side+'-'+role];assert.equal(s.image,base.services[side+'-'+role].image);assert.equal(s.ports,undefined);assert.equal(s.pull_policy,'never');}
 }
});
test('scheduler enabled, worker capacity, database mismatch or external URL refuses in qualification plan',()=>{
 for(const change of [p=>p.services['source-db'].command.pop(),p=>p.services['source-db'].command.push('-c','max_worker_processes=8'),p=>p.services['target-db'].environment.POSTGRES_DB='postgres',p=>p.services['source-auth'].environment.GOTRUE_DB_DATABASE_URL='postgres://local:local@foreign:5432/'+QUALIFICATION_DB]){
  const p=makePlan(run,'/tmp/unit',lock,secrets,{qualification:true});change(p);assert.throws(()=>validatePlan(p,run));
 }
});
test('psql connects only own source through Unix socket with ON_ERROR_STOP; marker only for unchanged test',()=>{
 const a=qualificationPsqlArgs(run);assert.ok(a.includes(run+'-source-db'));assert.equal(a[a.indexOf('-d')+1],QUALIFICATION_DB);assert.equal(a[a.indexOf('-h')+1],'/var/run/postgresql');assert.ok(a.includes('-X'));assert.ok(a.includes('ON_ERROR_STOP=1'));assert.equal(a.includes('--env'),false);
 const b=qualificationPsqlArgs(run,{test:true});assert.ok(b.includes('PGOPTIONS=-c jolene.test_isolated=candidatures_multi_pg17'));assert.throws(()=>qualificationPsqlArgs('remote'));assert.throws(()=>qualificationPsqlArgs(run,{test:'true'}));
});
test('memory success executes all canonical files once, then local cron stop, exact extensions, unchanged test, rollback probe',()=>{
 const e=evidence(),r=fakeRuntime(),reports=[];const result=qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x)));
 assert.equal(result.result,'ISOLATED_IMPORT_AND_SQL_TEST_PASSED');assert.equal(result.canonical_test_passed,true);assert.equal(result.rollback_verified,true);
 const sql=r.calls.filter(x=>x.bytes);assert.equal(sql[0].bytes.toString(),LOCAL_GUARD);
 e.migrations.forEach((m,i)=>assert.equal(sql[i+1].bytes,m.bytes));
 assert.equal(sql.filter(x=>x.flags.test===true).length,1);assert.equal(sql.find(x=>x.flags.test).bytes,e.test.bytes);
 assert.ok(sql.findIndex(x=>x.bytes.toString()===STOP_CRONS)>e.migrations.length);assert.equal(result.locally_disabled_jobs,4);assert.equal(reports.at(-1).migrations.every(x=>x.completed),true);
});
test('first SQL error stops integral replay without retry, later file, canonical test or false success',()=>{
 const e=evidence(),r=fakeRuntime({failOn:b=>b===e.migrations[1].bytes}),reports=[];
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x))));
 assert.equal(r.calls.some(x=>x.bytes===e.migrations[2].bytes),false);assert.equal(r.calls.some(x=>x.flags?.test),false);
 const last=reports.at(-1);assert.equal(last.migrations.length,2);assert.equal(last.migrations[1].completed,false);assert.equal(last.canonical_test_passed,false);assert.equal(last.rollback_verified,false);assert.ok(!JSON.stringify(reports).includes('CANARY'));
});
test('test preflight failure is preserved and cannot be reported as rollback/success',()=>{
 const e=evidence(),r=fakeRuntime({failOn:(_,flags)=>flags.test}),reports=[];
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x))));assert.equal(reports.at(-1).phase,'unchanged_canonical_test');assert.equal(reports.at(-1).canonical_test_passed,false);
});
test('unexpected rows, cron activity, missing probe or extra keys refuse',()=>{
 assert.deepEqual(zeros(JSON.stringify(zeroValue())),zeroValue());
 for(const k of Object.keys(zeroValue())){const v=zeroValue();v[k]=1;assert.throws(()=>zeros(JSON.stringify(v)));}
 const missing=zeroValue();delete missing.auth_users;assert.throws(()=>zeros(JSON.stringify(missing)));assert.throws(()=>zeros(JSON.stringify({...zeroValue(),extra:0})));
});
test('no raw SQL, DSN, notices, credentials or exception messages in failure projection',()=>{
 assert.deepEqual(safeFailure(Error('postgres://CANARY_SECRET')), {code:'QUALIFICATION_REFUSED'});
 const e=Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:{sqlstate:'42P01',line:25,assertion:'CAND_MULTI_HELPER_LIVE_DIFFERENT',other:'CANARY'}});
 assert.deepEqual(safeFailure(e),{code:'QUALIFICATION_SQL_FAILED',sqlstate:'42P01',input_line:25,assertion:'CAND_MULTI_HELPER_LIVE_DIFFERENT'});
 e.diagnostic={sqlstate:'CANARY',line:-1,assertion:'secret'};assert.deepEqual(safeFailure(e),{code:'QUALIFICATION_SQL_FAILED',sqlstate:null,input_line:null,assertion:null});
});
test('workflow remains dispatch-only on qualification branch, no secrets, no ValidatePR and cleanup always',()=>{
 const workflow=readFileSync(new URL('../../../../.github/workflows/restore-local-bootstrap.yml',import.meta.url),'utf8');
 assert.ok(!/pull_request:|\bpush:|secrets\.|environment:|^\s+npm |supabase db|supabase migration|workflow run/.test(workflow));
 assert.match(workflow,/contents: read/);assert.match(workflow,/persist-credentials: false/);assert.match(workflow,/refs\/heads\/ci\/qualification-pg17-/);assert.match(workflow,/fetch-depth: 0/);
 assert.match(workflow,/name: Always clean only exact owned resources\n\s+if: always\(\)/);assert.match(workflow,/name: Independently verify exact absence\n\s+if: always\(\)/);
 assert.ok(workflow.indexOf('qualify-import.mjs identity')<workflow.indexOf('bootstrap.mjs preload'));assert.ok(workflow.indexOf('qualify-import.mjs run')>workflow.indexOf('extensions.mjs compare'));
});

test('only the exact temporary Vercel branch is disabled; all other settings equal the canonical object',()=>{
 const base={installCommand:'npm ci',headers:[{source:'/x',headers:[]}],git:{provider:'github',deploymentEnabled:{main:true}}};
 const expected={...base,git:{...base.git,deploymentEnabled:{main:true,[QUALIFICATION_BRANCH]:false}}};
 assert.equal(checkVercel(base,expected,'refs/heads/'+QUALIFICATION_BRANCH),true);
 const empty={installCommand:'npm ci'},withBranch={...empty,git:{deploymentEnabled:{[QUALIFICATION_BRANCH]:false}}};
 assert.equal(checkVercel(empty,withBranch,'refs/heads/'+QUALIFICATION_BRANCH),true);
 for(const mutate of [x=>x.installCommand='arbitrary',x=>x.git.deploymentEnabled.main=false,x=>x.git.deploymentEnabled.other=false,x=>x.git.deploymentEnabled[QUALIFICATION_BRANCH]=true,x=>x.git.deploymentEnabled=false,x=>x.extra='setting',x=>delete x.headers]){
  const altered=structuredClone(expected);mutate(altered);assert.throws(()=>checkVercel(base,altered,'refs/heads/'+QUALIFICATION_BRANCH));
 }
 assert.throws(()=>checkVercel(base,expected,'refs/heads/ci/qualification-pg17-other'));
 assert.throws(()=>checkIdentity({...env,GITHUB_REF:'refs/heads/ci/qualification-pg17-other'},head,['vercel.json'],''));
});

test('exact expected native ownership gap is repaired once before replay; roles and all other values unchanged',()=>{
 const e=evidence(),r=fakeRuntime(),reports=[];const result=qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x)));
 assert.deepEqual(result.ownership_before,projectOwnerProbe(nativeOwner()));assert.deepEqual(result.ownership_after,projectOwnerProbe(nativeOwner(true)));
 assert.equal(result.local_database_owner_reconciled,true);assert.equal(r.calls.filter(x=>x.ownerRepair).length,1);
 assert.ok(r.calls.findIndex(x=>x.ownerRepair)<r.calls.findIndex(x=>x.bytes===e.migrations[0].bytes));
 const args=ownerRepairPsqlArgs(run);assert.equal(args[args.indexOf('-U')+1],'supabase_admin');assert.equal(args[args.indexOf('-d')+1],QUALIFICATION_DB);assert.equal(args[args.indexOf('-h')+1],'/var/run/postgresql');
 assert.match(QUALIFICATION_OWNER_REPAIR,/ALTER DATABASE jolene_candidatures_pg17_test OWNER TO postgres;/);
 assert.ok(!/ALTER ROLE|ALTER USER|GRANT |SET ROLE|ALTER SCHEMA|DROP |DISABLE TRIGGER/.test(QUALIFICATION_OWNER_REPAIR));
 assert.match(QUALIFICATION_OWNER_REPAIR,/session_user<>'supabase_admin'/);assert.match(QUALIFICATION_OWNER_REPAIR,/IS DISTINCT FROM 'supabase_admin'/);assert.match(QUALIFICATION_OWNER_REPAIR,/IS DISTINCT FROM 'postgres'/);
});
test('unexpected owner or any nonexact precondition refuses before repair and before first migration',()=>{
 const variants=[{...nativeOwner(),named_owner:'postgres'},{...nativeOwner(),native_owner:'other'},{...nativeOwner(),named_create:true},{...nativeOwner(),native_create:false},{...nativeOwner(),postgres_superuser:true},{...nativeOwner(),admin_superuser:false},{...nativeOwner(),local_empty_context:false},{...nativeOwner(),session_postgres:false},{...nativeOwner(),named_connect:false},{...nativeOwner(),native_temp:false},{...nativeOwner(),extra:'CANARY'}];
 for(const before of variants){
  const e=evidence(),r=fakeRuntime({ownerBefore:before}),reports=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x))));
  assert.equal(r.calls.some(x=>x.ownerRepair),false);assert.equal(r.calls.some(x=>x.bytes===e.migrations[0].bytes),false);assert.equal(reports.at(-1).phase,'native_owner_probe');assert.equal(reports.at(-1).failure.code,'QUALIFICATION_OWNER_REFUSED');assert.ok(!JSON.stringify(reports).includes('CANARY'));
 }
});
test('post-repair verification must match native privileges without adding SUPERUSER; otherwise no replay',()=>{
 for(const after of [{...nativeOwner(true),named_create:false},{...nativeOwner(true),named_owner:'supabase_admin'},{...nativeOwner(true),postgres_superuser:true},{...nativeOwner(true),local_empty_context:false}]){
  const e=evidence(),r=fakeRuntime({ownerAfter:after}),reports=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x))));
  assert.equal(r.calls.filter(x=>x.ownerRepair).length,1);assert.equal(r.calls.some(x=>x.bytes===e.migrations[0].bytes),false);assert.equal(reports.at(-1).canonical_test_passed,false);
 }
});
test('ownership projection retains only fixed names and booleans; no arbitrary catalogue values escape',()=>{
 const result=projectOwnerProbe({named_owner:'CANARY_SECRET',native_owner:'postgres',local_empty_context:'CANARY_SECRET',extra:'CANARY_SECRET'});
 assert.equal(result.named_owner,'other');assert.equal(result.native_owner,'postgres');assert.equal(result.local_empty_context,null);assert.ok(!JSON.stringify(result).includes('CANARY'));assert.throws(()=>ownerProbe(result));
});


test('only canonical migrations use one transaction; test and fixed probes retain their semantics',()=>{
 const migration=qualificationPsqlArgs(run,{migration:true});assert.equal(migration.filter(x=>x==='--single-transaction').length,1);
 for(const args of [qualificationPsqlArgs(run),qualificationPsqlArgs(run,{test:true}),ownerRepairPsqlArgs(run)])assert.equal(args.includes('--single-transaction'),false);
 assert.equal(migration.includes('--env'),false);assert.ok(migration.includes('ON_ERROR_STOP=1'));assert.equal(migration[migration.indexOf('-f')+1],'-');
 for(const flags of [{migration:'true'},{migration:1},{migration:true,test:true}])assert.throws(()=>qualificationPsqlArgs(run,flags));
});
test('whole explicit transactions and ON COMMIT DROP files remain byte-identical migration inputs',()=>{
 const e=evidence();e.migrations[1].bytes=Buffer.from('CREATE TEMP TABLE t (id int) ON COMMIT DROP;\nINSERT INTO t VALUES (1);\n');
 e.migrations[2].bytes=Buffer.from('BEGIN;\nSELECT 2;\nCOMMIT;\n');const r=fakeRuntime();qualify(e,r,r.extensionSQL,requirements,()=>{});
 const actual=r.calls.filter(x=>x.flags?.migration);assert.equal(actual.length,e.migrations.length);
 e.migrations.forEach((m,i)=>{assert.equal(actual[i].bytes,m.bytes);assert.deepEqual(actual[i].flags,{migration:true});});
 assert.deepEqual(r.calls.find(x=>x.flags?.test).flags,{test:true});
 for(const c of r.calls.filter(x=>x.bytes&&!e.migrations.some(m=>m.bytes===x.bytes)))assert.equal(c.flags.migration,undefined);
});
test('transaction failure stops before next file and test without an autocommit retry',()=>{
 const e=evidence(),r=fakeRuntime({failOn:(bytes,flags)=>bytes===e.migrations[1].bytes&&flags.migration===true}),reports=[];
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x))));
 assert.equal(r.calls.filter(x=>x.bytes===e.migrations[1].bytes).length,1);assert.equal(r.calls.some(x=>x.bytes===e.migrations[2].bytes),false);
 assert.equal(r.calls.some(x=>x.flags?.test),false);assert.equal(reports.at(-1).canonical_test_passed,false);assert.equal(reports.at(-1).rollback_verified,false);
});


const historicalBytes=readFileSync(new URL('../../../../'+HISTORICAL_MANIFEST_PATH,import.meta.url));
const historicalEntries=historicalManifestEntries(historicalBytes);
const cleanHistorical=()=>({expected_count:422,matched_count:422,missing_exposed_count:0,differences:[]});
test('diagnostic input line belongs to ERROR, not prior BEGIN warning or later CONTEXT',()=>{
 const message='psql:<stdin>:7: WARNING:  25001: there is already a transaction in progress\npsql:<stdin>:525: ERROR:  P0001: Corps SECURITY DEFINER modifiés sans revue : CANARY\nCONTEXT: PL/pgSQL function inline_code_block line 62 at RAISE';
 const d=projectSqlDiagnostic(message);assert.deepEqual(d,{sqlstate:'P0001',line:525,assertion:null,category:'HISTORICAL_MANIFEST_BODY_CHANGED'});
 assert.deepEqual(safeFailure(Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:d})),{code:'QUALIFICATION_SQL_FAILED',sqlstate:'P0001',input_line:525,assertion:null,category:'HISTORICAL_MANIFEST_BODY_CHANGED'});
 assert.ok(!JSON.stringify(d).includes('CANARY'));
 assert.deepEqual(projectSqlDiagnostic('psql:<stdin>:7: WARNING:  P0001: CANARY'),{sqlstate:null,line:null,assertion:null});
 assert.deepEqual(projectSqlDiagnostic('ERROR:  42P01: CANARY'),{sqlstate:'42P01',line:null,assertion:null});
});
test('all nine historical raises map only to closed category names, never payload',()=>{
 const labels=['SECURITY DEFINER non classées : CANARY','Signatures SECURITY DEFINER obsolètes : CANARY','Corps SECURITY DEFINER modifiés sans revue : CANARY','Manifest SECURITY DEFINER incomplet : CANARY','Compte RPC_UTILISATEUR_AUTH_INTERNE inattendu','Compte ADMIN_EST_ADMIN_VALIDE inattendu','Compte MIXTE_TENANT_ADMIN inattendu','Compte PUBLIC_VOLONTAIRE inattendu','Compte SERVICE_ONLY_REVOQUE inattendu'];
 labels.forEach((label,i)=>{const d=projectSqlDiagnostic('psql:<stdin>:525: ERROR:  P0001: '+label);assert.equal(d.category,SQL_DIAGNOSTIC_CATEGORIES[i]);assert.ok(!JSON.stringify(d).includes('CANARY'));});
 assert.equal(projectSqlDiagnostic('psql:<stdin>:5: ERROR:  P0001: CANARY').category,undefined);
 assert.equal(projectSqlDiagnostic('psql:<stdin>:5: ERROR:  42501: '+labels[0]).category,undefined);
 assert.equal(projectSqlDiagnostic('psql:<stdin>:5: ERROR:  P0001: CAND_MULTI_HELPER_LIVE_DIFFERENT').assertion,'CAND_MULTI_HELPER_LIVE_DIFFERENT');
 const d=safeFailure(Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:{category:'CANARY'}}));assert.equal(d.category,undefined);
});
test('historical diagnostic reads only byte-pinned 422 literals and emits a read-only local query',()=>{
 assert.equal(hash(historicalBytes),HISTORICAL_MANIFEST_SHA);assert.equal(historicalEntries.length,422);
 assert.throws(()=>historicalManifestEntries(Buffer.concat([historicalBytes,Buffer.from('\n')])));
 const sql=historicalManifestSQL(historicalEntries);assert.ok(sql.startsWith('BEGIN READ ONLY;\n'+LOCAL_GUARD));assert.ok(sql.endsWith('\nROLLBACK;'));
 assert.ok(sql.includes('md5(p.prosrc)'));assert.ok(!/\b(?:INSERT INTO|UPDATE |DELETE FROM|TRUNCATE |ALTER |CREATE |DROP |GRANT |REVOKE )/.test(sql));
 assert.ok(!sql.includes('jsonb_build_object(\'prosrc\''));assert.ok(!sql.includes('pg_get_functiondef'));
 assert.deepEqual(projectHistoricalManifest(JSON.stringify(cleanHistorical()),historicalEntries),cleanHistorical());
});
test('projection only admits source signatures, exact expected hashes, bounded counts and two difference kinds',()=>{
 const source=historicalEntries[0],v=cleanHistorical();v.matched_count=421;v.missing_exposed_count=2;v.differences=[{...source,kind:'hash_mismatch',actual_md5:'0'.repeat(32)}];
 assert.deepEqual(projectHistoricalManifest(JSON.stringify(v),historicalEntries),v);
 for(const mutate of [x=>x.differences[0].signature='CANARY',x=>x.differences[0].expected_md5='0'.repeat(32),x=>x.differences[0].actual_md5='CANARY',x=>x.differences[0].kind='CANARY',x=>x.differences[0].prosrc='CANARY',x=>x.missing_exposed_count=-1,x=>x.matched_count=422,x=>x.differences.push(x.differences[0]),x=>x.unexpected='CANARY']){const bad=structuredClone(v);mutate(bad);assert.throws(()=>projectHistoricalManifest(JSON.stringify(bad),historicalEntries));}
 const absent=structuredClone(v);absent.differences[0].kind='missing_or_not_definer';absent.differences[0].actual_md5=null;assert.deepEqual(projectHistoricalManifest(JSON.stringify(absent),historicalEntries),absent);
});
test('probe precedes exactly the historical migration, records diagnostic but does not bypass its failure',()=>{
 const e=evidence(),item={path:HISTORICAL_MANIFEST_PATH,sha256:HISTORICAL_MANIFEST_SHA,bytes:historicalBytes};e.migrations.push(item);e.migrations.sort((a,b)=>a.path.localeCompare(b.path));
 const r=fakeRuntime(),original=r.sql,proof=[],v=cleanHistorical();v.matched_count=421;v.differences=[{...historicalEntries[0],kind:'hash_mismatch',actual_md5:'0'.repeat(32)}];
 r.sql=(bytes,flags={})=>{if(bytes.toString().startsWith('BEGIN READ ONLY;')){r.calls.push({bytes,flags});return JSON.stringify(v);}if(bytes===historicalBytes){r.calls.push({bytes,flags});throw Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:{sqlstate:'P0001',line:525,assertion:null,category:'HISTORICAL_MANIFEST_BODY_CHANGED'}});}return original(bytes,flags);};
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
 const pi=r.calls.findIndex(x=>x.bytes?.toString().startsWith('BEGIN READ ONLY;')),mi=r.calls.findIndex(x=>x.bytes===historicalBytes);assert.ok(pi>=0&&pi<mi);assert.deepEqual(r.calls[pi].flags,{});assert.deepEqual(r.calls[mi].flags,{migration:true});
 const last=proof.at(-1);assert.deepEqual(last.historical_manifest,{path:item.path,sha256:item.sha256,...v});assert.equal(last.failure.category,'HISTORICAL_MANIFEST_BODY_CHANGED');assert.equal(last.canonical_test_passed,false);
 assert.equal(last.migrations.at(-1).completed,false);assert.equal(r.calls.some(x=>x.flags?.test),false);assert.equal(r.calls.filter(x=>x.bytes===historicalBytes).length,1);
});
test('unsafe historical diagnostic refuses before its migration, no arbitrary values saved',()=>{
 const e=evidence();e.migrations.push({path:HISTORICAL_MANIFEST_PATH,sha256:HISTORICAL_MANIFEST_SHA,bytes:historicalBytes});e.migrations.sort((a,b)=>a.path.localeCompare(b.path));
 const r=fakeRuntime(),original=r.sql,proof=[];r.sql=(bytes,flags={})=>bytes.toString().startsWith('BEGIN READ ONLY;')?JSON.stringify({...cleanHistorical(),CANARY:'CANARY'}):original(bytes,flags);
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));assert.equal(r.calls.some(x=>x.bytes===historicalBytes),false);assert.equal(proof.at(-1).failure.code,'QUALIFICATION_MANIFEST_DIAGNOSTIC_REFUSED');assert.ok(!JSON.stringify(proof).includes('CANARY'));
});


test('native default ACL target is exactly PG17 postgres/public grants for two client roles',()=>{
 const grants=expectedDefaultAclGrants();assert.equal(grants.length,24);assert.equal(grants.filter(x=>x.object_type==='r').length,16);assert.equal(grants.filter(x=>x.object_type==='S').length,6);assert.equal(grants.filter(x=>x.object_type==='f').length,2);
 assert.ok(grants.every(x=>['anon','authenticated'].includes(x.grantee)&&x.grantor==='postgres'&&x.is_grantable===false));
 assert.deepEqual(checkDefaultAclProbe(nativeDefaults()),nativeDefaults());assert.deepEqual(checkDefaultAclProbe(nativeDefaults(true),{aligned:true,before:nativeDefaults()}),nativeDefaults(true));
});
test('fixed local alignment matches the existing staging preparation, with transaction rollback on changed other ACL',()=>{
 const workflow=readFileSync(new URL('../../../../.github/workflows/deploy-supabase-staging.yml',import.meta.url),'utf8').replace(/\s+/g,' ');
 const statements=[...QUALIFICATION_DEFAULT_ACL_ALIGN.matchAll(/ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON (?:TABLES|SEQUENCES|FUNCTIONS) FROM anon, authenticated;/g)].map(m=>m[0]);assert.equal(statements.length,3);for(const q of statements)assert.ok(workflow.includes(q));
 assert.ok(QUALIFICATION_DEFAULT_ACL_ALIGN.startsWith('BEGIN;'));assert.ok(QUALIFICATION_DEFAULT_ACL_ALIGN.endsWith('COMMIT;'));
 assert.ok(QUALIFICATION_DEFAULT_ACL_PROBE.startsWith('BEGIN READ ONLY;'));assert.ok(QUALIFICATION_DEFAULT_ACL_PROBE.endsWith('ROLLBACK;'));
 assert.match(QUALIFICATION_DEFAULT_ACL_ALIGN,/current_database\(\)='jolene_candidatures_pg17_test'/);assert.match(QUALIFICATION_DEFAULT_ACL_ALIGN,/inet_server_addr\(\) IS NULL/);assert.match(QUALIFICATION_DEFAULT_ACL_ALIGN,/session_user='postgres'/);
 assert.match(QUALIFICATION_DEFAULT_ACL_ALIGN,/WHERE n.nspname IN \('public','private'\)/);assert.match(QUALIFICATION_DEFAULT_ACL_ALIGN,/other_acl_md5' IS DISTINCT FROM before_acl/);
 assert.ok(!/REVOKE ALL ON ALL|REVOKE ALL ON FUNCTION public|ALTER ROLE|ALTER USER|SET ROLE|CREATE |DROP |GRANT /.test(QUALIFICATION_DEFAULT_ACL_ALIGN));
});
test('default ACL alignment happens once after owner reconciliation and before baseline, not during or after replay',()=>{
 const e=evidence(),r=fakeRuntime(),result=qualify(e,r,r.extensionSQL,requirements,()=>{});
 assert.equal(r.calls.filter(x=>x.defaultsAlign).length,1);const i=r.calls.findIndex(x=>x.defaultsAlign);assert.ok(i>r.calls.findIndex(x=>x.ownerRepair));assert.ok(i<r.calls.findIndex(x=>x.bytes===e.migrations[0].bytes));
 assert.deepEqual(result.default_acl_before,nativeDefaults());assert.deepEqual(result.default_acl_after,nativeDefaults(true));assert.equal(result.local_default_acls_aligned,true);
 assert.equal(r.calls.filter(x=>x.defaultsProbe).length,2);
});
test('unexpected default ACL context, grants, grantor or global access refuses before alignment and baseline',()=>{
 const variants=[{local_empty_context:false},{postgres_superuser:true},{global_client_grants:1},{target_grants:[]},{other_acl_count:null},{other_acl_md5:'CANARY'},{extra:'CANARY'}];
 for(const patch of variants){const e=evidence(),r=fakeRuntime({defaultsBefore:{...nativeDefaults(),...patch}}),proof=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));assert.equal(r.calls.some(x=>x.defaultsAlign),false);assert.equal(r.calls.some(x=>x.bytes===e.migrations[0].bytes),false);assert.equal(proof.at(-1).failure.code,'QUALIFICATION_DEFAULT_ACL_REFUSED');assert.ok(!JSON.stringify(proof).includes('CANARY'));}
 for(const patch of [{grantor:'supabase_admin'},{grantee:'PUBLIC'},{privilege:'CANARY'},{is_grantable:true},{object_type:'T'},{extra:'CANARY'}]){const v=nativeDefaults();Object.assign(v.target_grants[0],patch);assert.throws(()=>checkDefaultAclProbe(v));}
});
test('changed other default ACLs or remaining client grants refuse before any import',()=>{
 for(const patch of [{other_acl_count:110},{other_acl_md5:'b'.repeat(32)},{target_grants:expectedDefaultAclGrants()},{postgres_superuser:true},{local_empty_context:false}]){
  const e=evidence(),r=fakeRuntime({defaultsAfter:{...nativeDefaults(true),...patch}}),proof=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));assert.equal(r.calls.filter(x=>x.defaultsAlign).length,1);assert.equal(r.calls.some(x=>x.bytes===e.migrations[0].bytes),false);assert.equal(proof.at(-1).canonical_test_passed,false);
 }
});
test('default ACL projection never exposes unknown role, privilege, payload or unbounded rows',()=>{
 const v=nativeDefaults();v.target_grants[0]={object_type:'CANARY',grantee:'CANARY',grantor:'CANARY',privilege:'CANARY',is_grantable:'CANARY',secret:'CANARY'};v.other_acl_md5='CANARY';v.extra='CANARY';const p=projectDefaultAclProbe(v);assert.ok(!JSON.stringify(p).includes('CANARY'));assert.equal(p.target_grants[0].grantee,'other');assert.equal(p.other_acl_md5,null);
 assert.equal(projectDefaultAclProbe({...nativeDefaults(),target_grants:Array(101).fill({})}).target_grants,null);
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {BASELINE_SERVICE_DEFAULT_PROBE,BASELINE_SERVICE_DEFAULT_SUSPEND,expectedDefaultAclGrants,QUALIFICATION_DEFAULT_ACL_ALIGN,QUALIFICATION_DEFAULT_ACL_PROBE,projectSqlDiagnostic,SQL_DIAGNOSTIC_CATEGORIES,makePlan,validatePlan,qualificationPsqlArgs,QUALIFICATION_DB,QUALIFICATION_ARGS,QUALIFICATION_OWNER_REPAIR,ownerRepairPsqlArgs,validateInspection} from './bootstrap.mjs';
import {VAULT_PROVENANCE_PATH,VAULT_PROVENANCE_SHA,VAULT_METADATA_PROBE,readVaultMetadata,localVaultCleanupSQL,BASELINE_PATH,projectBaselineServiceDefault,checkBaselineServiceDefault,NOTATION_PREFLIGHT_PATH,NOTATION_PREFLIGHT_SHA,notationPreflightSQL,projectNotationPreflight,projectDefaultAclProbe,checkDefaultAclProbe,HISTORICAL_MANIFEST_PATH,HISTORICAL_MANIFEST_SHA,historicalManifestEntries,historicalManifestSQL,projectHistoricalManifest,PRODUCT_SHA,QUALIFICATION_BRANCH,TEST_PATH,TEST_SHA256,checkVercel,checkIdentity,buildReplay,qualify,hash,safeFailure,LOCAL_GUARD,STOP_CRONS,QUIESCENCE,projectQuiescence,zeros,ownerProbe,projectOwnerProbe} from './qualify-import.mjs';
const run='jolene-restore-drill-12345-1',head='a'.repeat(40);
const env={GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:'refs/heads/'+QUALIFICATION_BRANCH,GITHUB_RUN_ID:'12345',GITHUB_RUN_ATTEMPT:'1',GITHUB_SHA:head};
const lock=JSON.parse(readFileSync(new URL('../../images.lock.json',import.meta.url)));
const requirements=JSON.parse(readFileSync(new URL('../export/scope.json',import.meta.url))).extensions;
const secrets={source:{password:'SOURCE_CANARY',jwt:'LOCAL_CANARY'},target:{password:'TARGET_CANARY',jwt:'OTHER_CANARY'}};
const paths=['supabase/migrations/20261002064017_lire_candidatures_mission_habilitee.sql','supabase/migrations/00000000000000_baseline_prod.sql','supabase/migrations/20260101000000_before.sql',VAULT_PROVENANCE_PATH];
const byteMap=new Map([...paths,TEST_PATH].map((p,i)=>[p,Buffer.from('-- '+i+'\r\nSELECT '+i+';\r\n')]));
byteMap.set(VAULT_PROVENANCE_PATH,readFileSync(new URL('../../../../'+VAULT_PROVENANCE_PATH,import.meta.url)));
byteMap.set(TEST_PATH,readFileSync(new URL('../../../../'+TEST_PATH,import.meta.url)));
const load=p=>byteMap.get(p);
const vaultReceipt=()=>({id:'33333333-4444-5555-6666-777777777777',created_epoch:'1790955000.123456',updated_epoch:'1790955000.123456'});
const vaultMetadata=(after=false)=>({total:after?1:0,metadata_exact:after,receipt:after?vaultReceipt():null});
const replay=()=>buildReplay(paths,load,load);
const evidence=()=>({...checkIdentity(env,head,['tools/restore-local/scripts/restore/qualify-import.mjs'],''),...replay()});
const runtimeExtensions=()=>({postgres_major:17,extensions:requirements.map(e=>({name:e.name,installed:{version:e.version,schema:e.schema},available_count:1,available_truncated:false,available_versions:[{version:e.version,superuser:true,trusted:false,relocatable:false,schema:e.schema,requires:null}]}))});
const zeroValue=()=>Object.fromEntries(['auth_users','auth_sessions','soignants','etablissements','missions','candidatures','members','externalisations','storage_objects','active_crons','cron_executions','http_queue','http_responses','vault_secrets'].map(k=>[k,0]));
const nativeOwner=(repaired=false)=>({local_empty_context:true,session_postgres:true,named_owner:repaired?'postgres':'supabase_admin',native_owner:'postgres',named_create:repaired,native_create:true,named_connect:true,native_connect:true,named_temp:true,native_temp:true,postgres_superuser:false,admin_superuser:true});
const nativeDefaults=(aligned=false)=>({local_empty_context:true,postgres_superuser:false,global_client_grants:0,target_grants:aligned?[]:expectedDefaultAclGrants(),other_acl_count:111,other_acl_md5:'a'.repeat(32)});
const serviceDefault=(phase='before')=>({local_isolated_context:true,local_empty_context:phase!=='restored',postgres_superuser:false,global_service_function_grants:0,client_grants:0,
 target_grants:phase==='suspended'?[]:[{grantor:'postgres',privilege:'EXECUTE',is_grantable:false}],other_acl_count:110,other_acl_md5:'b'.repeat(32)});
function fakeRuntime(options={}){
 let repaired=false,defaultsAligned=false,serviceSuspended=false,baselineReplayed=false,vaultCreated=false;
 const calls=[],extensionSQL=Buffer.from('CANONICAL_EXTENSION_SQL');
 return {calls,extensionSQL,run,
 probeDatabaseOwner(){calls.push({ownerProbe:true,repaired});return structuredClone(repaired?(options.ownerAfter??nativeOwner(true)):(options.ownerBefore??nativeOwner()));},
 repairDatabaseOwner(){calls.push({ownerRepair:true});repaired=true;},
  probeDefaultAcls(){calls.push({defaultsProbe:true,defaultsAligned});return structuredClone(defaultsAligned?(options.defaultsAfter??nativeDefaults(true)):(options.defaultsBefore??nativeDefaults()));},
  alignDefaultAcls(){calls.push({defaultsAlign:true});defaultsAligned=true;},
  probeBaselineServiceDefault(){const phase=baselineReplayed?'restored':serviceSuspended?'suspended':'before';calls.push({serviceDefaultProbe:phase});return structuredClone(options['service_'+phase]??serviceDefault(phase));},
  suspendBaselineServiceDefault(){calls.push({serviceDefaultSuspend:true});serviceSuspended=true;},
 verify(){calls.push({verify:true});},sql(bytes,flags={}){
  calls.push({bytes,flags});if(options.failOn&&options.failOn(bytes,flags))throw Error('CANARY_SECRET');
   if(bytes===load(BASELINE_PATH))baselineReplayed=true;
   if(bytes===load(VAULT_PROVENANCE_PATH))vaultCreated=true;
   if(bytes.toString()===VAULT_METADATA_PROBE)return JSON.stringify(vaultMetadata(vaultCreated));
   if(bytes.toString().includes('DO $vault_cleanup$'))return JSON.stringify({removed_count:1,after_cleanup_count:0});
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
 for(const x of [...result.migrations,result.test]){assert.equal(x.bytes,load(x.path));assert.equal(x.sha256,hash(load(x.path)));if(x.path!==VAULT_PROVENANCE_PATH&&x.path!==TEST_PATH)assert.ok(x.bytes.includes(Buffer.from('\r\n')));}
 assert.equal(result.test.path,TEST_PATH);assert.equal(result.test.sha256,TEST_SHA256);
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
 e.migrations.forEach((m,i)=>assert.equal(sql.filter(x=>x.flags.migration)[i].bytes,m.bytes));
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
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>reports.push(structuredClone(x))));assert.equal(reports.at(-1).phase,'pinned_synthetic_test');assert.equal(reports.at(-1).canonical_test_passed,false);
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
 e.migrations.at(-1).bytes=Buffer.from('BEGIN;\nSELECT 2;\nCOMMIT;\n');const r=fakeRuntime();qualify(e,r,r.extensionSQL,requirements,()=>{});
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
 r.sql=(bytes,flags={})=>{if((bytes.toString().startsWith('BEGIN READ ONLY;')&&bytes.toString()!==VAULT_METADATA_PROBE)){r.calls.push({bytes,flags});return JSON.stringify(v);}if(bytes===historicalBytes){r.calls.push({bytes,flags});throw Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:{sqlstate:'P0001',line:525,assertion:null,category:'HISTORICAL_MANIFEST_BODY_CHANGED'}});}return original(bytes,flags);};
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
 const pi=r.calls.findIndex(x=>(x.bytes?.toString().startsWith('BEGIN READ ONLY;')&&x.bytes?.toString()!==VAULT_METADATA_PROBE)),mi=r.calls.findIndex(x=>x.bytes===historicalBytes);assert.ok(pi>=0&&pi<mi);assert.deepEqual(r.calls[pi].flags,{});assert.deepEqual(r.calls[mi].flags,{migration:true});
 const last=proof.at(-1);assert.deepEqual(last.historical_manifest,{path:item.path,sha256:item.sha256,...v});assert.equal(last.failure.category,'HISTORICAL_MANIFEST_BODY_CHANGED');assert.equal(last.canonical_test_passed,false);
 assert.equal(last.migrations.at(-1).completed,false);assert.equal(r.calls.some(x=>x.flags?.test),false);assert.equal(r.calls.filter(x=>x.bytes===historicalBytes).length,1);
});
test('unsafe historical diagnostic refuses before its migration, no arbitrary values saved',()=>{
 const e=evidence();e.migrations.push({path:HISTORICAL_MANIFEST_PATH,sha256:HISTORICAL_MANIFEST_SHA,bytes:historicalBytes});e.migrations.sort((a,b)=>a.path.localeCompare(b.path));
 const r=fakeRuntime(),original=r.sql,proof=[];r.sql=(bytes,flags={})=>(bytes.toString().startsWith('BEGIN READ ONLY;')&&bytes.toString()!==VAULT_METADATA_PROBE)?JSON.stringify({...cleanHistorical(),CANARY:'CANARY'}):original(bytes,flags);
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


const notationBytes=readFileSync(new URL('../../../../'+NOTATION_PREFLIGHT_PATH,import.meta.url));
const notationValue=()=>({
 audit_helper_exists:true,audit_helper_md5:'04cc44127e325b434445113e88ce38b7',audit_helper_matches:true,
 action_constraint_exists:true,action_constraint_md5:'5d8ca35986765f1530b47d63b9f8f432',action_constraint_validated:true,action_constraint_matches:true,
 actor_constraint_exists:true,actor_constraint_md5:'cad0a04c75e18f5b5a2b25fe3fd6f5fe',actor_constraint_validated:true,actor_constraint_matches:true,
 notation_exists:true,notation_md5:'de8b4925694aa624a8e45c22e47416b0',notation_body_matches:true,notation_definer:true,
 notation_owner_matches:true,notation_config_matches:true,notation_acl_exact:false,notation_acl_set_equal:true,notation_acl_dimensions_match:true,
 notation_acl_entries:['postgres','service_role','authenticated'].map((grantee,i)=>({position:i+1,grantee,grantor:'postgres',privilege:'EXECUTE',is_grantable:false})),
 inventory_single_row:true,inventory_matches:true,inventory_md5:'de8b4925694aa624a8e45c22e47416b0',
});
test('notation exceptions map to three closed categories without free text or SQL payload',()=>{
 const labels=['Notation : dépendances du journal audit inattendues','Notation : définition ou droits inattendus','Notation : inventaire divergent'];
 const categories=['NOTATION_AUDIT_DEPENDENCY','NOTATION_DEFINITION_OR_ACL','NOTATION_INVENTORY'];
 labels.forEach((label,i)=>{
  const diagnostic=projectSqlDiagnostic('psql:<stdin>:7: WARNING:  25001: already in transaction\npsql:<stdin>:36: ERROR:  P0001: '+label);
  assert.deepEqual(diagnostic,{sqlstate:'P0001',line:36,assertion:null,category:categories[i]});
  assert.equal(safeFailure(Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic})).category,categories[i]);
  assert.equal(projectSqlDiagnostic('ERROR:  P0001: '+label+' CANARY').category,undefined);
  assert.equal(projectSqlDiagnostic('ERROR:  42501: '+label).category,undefined);
 });
});
test('notation probe is pinned to exact file bytes and reads only metadata in guarded local read-only transaction',()=>{
 assert.equal(hash(notationBytes),NOTATION_PREFLIGHT_SHA);
 assert.throws(()=>notationPreflightSQL(Buffer.concat([notationBytes,Buffer.from('\n')])));
 const sql=notationPreflightSQL(notationBytes);
 assert.ok(sql.startsWith('BEGIN READ ONLY;\n'+LOCAL_GUARD));assert.ok(sql.endsWith('ROLLBACK;'));
 assert.ok(!/\b(?:INSERT INTO|UPDATE |DELETE FROM|TRUNCATE |ALTER |CREATE |DROP |GRANT |REVOKE )/.test(sql));
 assert.ok(sql.includes('WITH ORDINALITY'));assert.ok(sql.includes('p.proacl=e.acl'));assert.ok(sql.includes('cardinality(p.proacl)=cardinality(e.acl)'));
 assert.ok(sql.includes('pg_get_constraintdef'));assert.ok(!sql.includes('pg_get_functiondef'));assert.ok(!sql.includes("'prosrc'"));
});
test('notation projection preserves ordered ACL and distinguishes exact order from equal effective grants',()=>{
 const v=notationValue();assert.deepEqual(projectNotationPreflight(JSON.stringify(v)),v);
 assert.deepEqual(v.notation_acl_entries.map(x=>x.grantee),['postgres','service_role','authenticated']);
 assert.equal(v.notation_acl_exact,false);assert.equal(v.notation_acl_set_equal,true);
 const changed=notationValue();changed.notation_acl_set_equal=false;changed.notation_acl_entries[1].is_grantable=true;
 assert.deepEqual(projectNotationPreflight(JSON.stringify(changed)),changed);
 const missing=notationValue();missing.notation_exists=false;missing.notation_md5=null;missing.notation_acl_entries=[];
 assert.deepEqual(projectNotationPreflight(JSON.stringify(missing)),missing);
});
test('notation diagnostic rejects unknown fields, raw bodies, unknown roles, malformed hashes and unbounded ACLs',()=>{
 const mutators=[x=>x.prosrc='CANARY',x=>x.notation_md5='CANARY',x=>x.notation_md5=['a'.repeat(32)],x=>delete x.audit_helper_exists,x=>x.notation_acl_exact='CANARY',
  x=>x.notation_acl_entries[0].grantee='CANARY',x=>x.notation_acl_entries[0].grantor='CANARY',x=>x.notation_acl_entries[0].privilege='CANARY',
  x=>x.notation_acl_entries[0].is_grantable='CANARY',x=>x.notation_acl_entries[0].secret='CANARY',x=>x.notation_acl_entries[0].position=0,
  x=>x.notation_acl_entries[1].position=1,x=>x.notation_acl_entries=Array(65).fill(x.notation_acl_entries[0])];
 for(const mutate of mutators){const v=notationValue();mutate(v);assert.throws(()=>projectNotationPreflight(JSON.stringify(v)),/QUALIFICATION_NOTATION_DIAGNOSTIC_REFUSED/);}
 for(const raw of ['null','[]','{}','CANARY'])assert.throws(()=>projectNotationPreflight(raw));
});
test('notation probe precedes the unchanged migration once and preserves its failure without retry or canonical test',()=>{
 const e=evidence(),item={path:NOTATION_PREFLIGHT_PATH,sha256:NOTATION_PREFLIGHT_SHA,bytes:notationBytes};e.migrations.push(item);e.migrations.sort((a,b)=>a.path.localeCompare(b.path));
 const r=fakeRuntime(),original=r.sql,proof=[];
 r.sql=(bytes,flags={})=>{
  if(bytes.toString()===notationPreflightSQL(notationBytes)){r.calls.push({bytes,flags});return JSON.stringify(notationValue());}
  if(bytes===notationBytes){r.calls.push({bytes,flags});throw Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:{sqlstate:'P0001',line:36,assertion:null,category:'NOTATION_DEFINITION_OR_ACL'}});}
  return original(bytes,flags);
 };
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
 const pi=r.calls.findIndex(x=>x.bytes?.toString()===notationPreflightSQL(notationBytes)),mi=r.calls.findIndex(x=>x.bytes===notationBytes);
 assert.ok(pi>=0&&pi<mi);assert.deepEqual(r.calls[pi].flags,{});assert.deepEqual(r.calls[mi].flags,{migration:true});
 assert.equal(r.calls.filter(x=>x.bytes===notationBytes).length,1);assert.equal(r.calls.filter(x=>x.bytes?.toString()===notationPreflightSQL(notationBytes)).length,1);
 assert.equal(r.calls.some(x=>x.bytes===e.migrations.at(-1).bytes),false);assert.equal(r.calls.some(x=>x.flags?.test),false);
 const last=proof.at(-1);assert.deepEqual(last.notation_preflight,{path:item.path,sha256:item.sha256,...notationValue()});
 assert.equal(last.migrations.at(-1).completed,false);assert.equal(last.failure.category,'NOTATION_DEFINITION_OR_ACL');assert.equal(last.canonical_test_passed,false);
});
test('invalid notation projection or altered pin refuses before guarded migration without storing arbitrary output',()=>{
 for(const kind of ['unsafe','bytes','sha']){
  const e=evidence(),item={path:NOTATION_PREFLIGHT_PATH,sha256:NOTATION_PREFLIGHT_SHA,bytes:notationBytes};
  if(kind==='bytes')item.bytes=Buffer.concat([notationBytes,Buffer.from('\n')]);if(kind==='sha')item.sha256='0'.repeat(64);
  e.migrations.push(item);e.migrations.sort((a,b)=>a.path.localeCompare(b.path));
  const r=fakeRuntime(),original=r.sql,proof=[];r.sql=(bytes,flags={})=>(bytes.toString().startsWith('BEGIN READ ONLY;')&&bytes.toString()!==VAULT_METADATA_PROBE)?JSON.stringify({...notationValue(),prosrc:'CANARY'}):original(bytes,flags);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
  assert.equal(r.calls.some(x=>x.bytes===item.bytes),false);assert.equal(r.calls.some(x=>x.flags?.test),false);
  assert.equal(proof.at(-1).failure.code,'QUALIFICATION_NOTATION_DIAGNOSTIC_REFUSED');assert.ok(!JSON.stringify(proof).includes('CANARY'));
 }
});


test('service default suspension touches only future postgres/public functions before an empty import',()=>{
 assert.ok(BASELINE_SERVICE_DEFAULT_PROBE.startsWith('BEGIN READ ONLY;'));assert.ok(BASELINE_SERVICE_DEFAULT_PROBE.endsWith('ROLLBACK;'));
 assert.ok(BASELINE_SERVICE_DEFAULT_SUSPEND.startsWith('BEGIN;'));assert.ok(BASELINE_SERVICE_DEFAULT_SUSPEND.endsWith('COMMIT;'));
 assert.equal((BASELINE_SERVICE_DEFAULT_SUSPEND.match(/ALTER DEFAULT PRIVILEGES/g)||[]).length,1);
 assert.ok(BASELINE_SERVICE_DEFAULT_SUSPEND.includes('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM service_role;'));
 assert.ok(!/REVOKE .* ON FUNCTION public|GRANT |ALTER ROLE|UPDATE |INSERT |DELETE |DROP |CREATE /.test(BASELINE_SERVICE_DEFAULT_SUSPEND));
 assert.ok(BASELINE_SERVICE_DEFAULT_SUSPEND.includes("defaclnamespace=0 AND defaclobjtype='f' AND grantee='service_role'::regrole"));
 assert.ok(BASELINE_SERVICE_DEFAULT_SUSPEND.includes("WHERE n.nspname IN ('public','private')"));
 assert.ok(BASELINE_SERVICE_DEFAULT_SUSPEND.includes("after_acl->'other_acl_md5' IS DISTINCT FROM before_acl->'other_acl_md5'"));
 const baseline=readFileSync(new URL('../../../../'+BASELINE_PATH,import.meta.url),'utf8');
 assert.ok(baseline.includes('ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";'));
});
test('service default suspended exactly once before baseline and restored by baseline before next migration',()=>{
 const e=evidence(),r=fakeRuntime(),result=qualify(e,r,r.extensionSQL,requirements,()=>{});
 const si=r.calls.findIndex(x=>x.serviceDefaultSuspend),bi=r.calls.findIndex(x=>x.bytes===e.migrations[0].bytes),ri=r.calls.findIndex(x=>x.serviceDefaultProbe==='restored'),next=r.calls.findIndex(x=>x.bytes===e.migrations[1].bytes);
 assert.ok(si>r.calls.findIndex(x=>x.defaultsAlign)&&si<bi&&bi<ri&&ri<next);
 assert.equal(r.calls.filter(x=>x.serviceDefaultSuspend).length,1);assert.equal(r.calls.filter(x=>x.serviceDefaultProbe).length,3);
 assert.deepEqual(result.baseline_service_default_before,serviceDefault());assert.deepEqual(result.baseline_service_default_suspended,serviceDefault('suspended'));
 assert.deepEqual(result.baseline_service_default_after_baseline,serviceDefault('restored'));assert.equal(result.baseline_service_default_restored,true);
});
test('service default refuses global inheritance, unexpected privilege, actor or nonempty context before mutation',()=>{
 for(const patch of [{global_service_function_grants:1},{client_grants:1},{local_empty_context:false},{local_isolated_context:false},{postgres_superuser:true},{target_grants:[]},{target_grants:[{grantor:'other',privilege:'EXECUTE',is_grantable:false}]},{target_grants:[{grantor:'postgres',privilege:'EXECUTE',is_grantable:true}]},{extra:'CANARY'}]){
  const e=evidence(),r=fakeRuntime({service_before:{...serviceDefault(),...patch}}),proof=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
  assert.equal(r.calls.some(x=>x.serviceDefaultSuspend),false);assert.equal(r.calls.some(x=>x.bytes===e.migrations[0].bytes),false);
  assert.equal(proof.at(-1).failure.code,'QUALIFICATION_BASELINE_DEFAULT_REFUSED');assert.ok(!JSON.stringify(proof).includes('CANARY'));
 }
});
test('changed other defaults or ineffective suspension refuses before any baseline bytes',()=>{
 for(const patch of [{other_acl_count:109},{other_acl_md5:'c'.repeat(32)},{target_grants:serviceDefault().target_grants},{global_service_function_grants:1}]){
  const e=evidence(),r=fakeRuntime({service_suspended:{...serviceDefault('suspended'),...patch}}),proof=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
  assert.equal(r.calls.filter(x=>x.serviceDefaultSuspend).length,1);assert.equal(r.calls.some(x=>x.bytes===e.migrations[0].bytes),false);assert.equal(proof.at(-1).canonical_test_passed,false);
 }
});
test('baseline itself must restore original default and all other defaults before continuing, without corrective GRANT',()=>{
 for(const patch of [{target_grants:[]},{other_acl_count:109},{other_acl_md5:'c'.repeat(32)},{local_empty_context:true},{global_service_function_grants:1}]){
  const e=evidence(),r=fakeRuntime({service_restored:{...serviceDefault('restored'),...patch}}),proof=[];assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
  assert.equal(r.calls.filter(x=>x.bytes===e.migrations[0].bytes).length,1);assert.equal(r.calls.some(x=>x.bytes===e.migrations[1].bytes),false);
  assert.equal(r.calls.some(x=>x.flags?.test),false);assert.equal(r.calls.filter(x=>x.serviceDefaultSuspend).length,1);assert.equal(proof.at(-1).baseline_service_default_restored,undefined);
 }
});
test('service default projection publishes only bounded fixed metadata and refuses hidden fields',()=>{
 const bad={...serviceDefault(),other_acl_md5:'CANARY',target_grants:[{grantor:'CANARY',privilege:'CANARY',is_grantable:'CANARY',secret:'CANARY'}],secret:'CANARY'};
 assert.ok(!JSON.stringify(projectBaselineServiceDefault(bad)).includes('CANARY'));assert.throws(()=>checkBaselineServiceDefault(bad));
 assert.throws(()=>checkBaselineServiceDefault(serviceDefault(),{phase:'other'}));assert.throws(()=>checkBaselineServiceDefault(serviceDefault('suspended'),{phase:'suspended'}));
});


test('cron stop uses the official API transactionally without direct table writes or added privileges',()=>{
 assert.ok(STOP_CRONS.startsWith('BEGIN;\nSET LOCAL row_security=off;\n'+LOCAL_GUARD));assert.ok(STOP_CRONS.endsWith('COMMIT;'));
 assert.ok(STOP_CRONS.includes("has_function_privilege(current_user,'cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE')"));
 assert.ok(STOP_CRONS.includes('WHERE username IS DISTINCT FROM current_user'));
 assert.ok(STOP_CRONS.includes('WHERE active AND username=current_user ORDER BY jobid'));
 assert.ok(STOP_CRONS.includes('PERFORM cron.alter_job(job.jobid,active:=false);'));
 assert.ok(STOP_CRONS.includes("before_jobs IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(j)-'active' ORDER BY j.jobid)"));
 assert.ok(!/UPDATE cron\.job|DELETE FROM|INSERT INTO|ALTER ROLE|GRANT |BYPASSRLS;|SET ROLE|CREATE /.test(STOP_CRONS));
 assert.ok(!STOP_CRONS.includes('database=current_database()'));
});
test('quiescence reads cannot silently pass through row-filtered cron or business tables',()=>{
 assert.ok(QUIESCENCE.startsWith('BEGIN READ ONLY;\nSET LOCAL row_security=off;\n'+LOCAL_GUARD));assert.ok(QUIESCENCE.endsWith('ROLLBACK;'));
 assert.ok(QUIESCENCE.includes("'active_crons',(SELECT count(*) FROM cron.job WHERE active)"));
 assert.ok(QUIESCENCE.includes("'cron_executions',(SELECT count(*) FROM cron.job_run_details)"));
 assert.deepEqual(zeros(JSON.stringify(zeroValue())),zeroValue());
 for(const key of ['active_crons','cron_executions'])assert.throws(()=>zeros(JSON.stringify({...zeroValue(),[key]:1})));
});
test('refused cron ownership, RLS or API permissions aborts qualification before canonical test',()=>{
 const e=evidence(),r=fakeRuntime({failOn:bytes=>bytes.toString()===STOP_CRONS}),proof=[];
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
 assert.equal(proof.at(-1).migrations.every(x=>x.completed),true);assert.equal(proof.at(-1).phase,'stop_local_crons');
 assert.equal(proof.at(-1).canonical_test_passed,false);assert.equal(proof.at(-1).rollback_verified,false);
 assert.equal(r.calls.filter(x=>x.bytes?.toString()===STOP_CRONS).length,1);assert.equal(r.calls.some(x=>x.flags?.test),false);
});
test('malformed cron result cannot advertise successful deactivation or continue the SQL test',()=>{
 for(const value of [{locally_disabled_jobs:-1},{locally_disabled_jobs:'4'},{locally_disabled_jobs:4,extra:'CANARY'}]){
  const e=evidence(),r=fakeRuntime(),original=r.sql,proof=[];r.sql=(bytes,flags={})=>bytes.toString()===STOP_CRONS?JSON.stringify(value):original(bytes,flags);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
  assert.equal(proof.at(-1).failure.code,'QUALIFICATION_CRON_REPORT');assert.equal(r.calls.some(x=>x.flags?.test),false);assert.ok(!JSON.stringify(proof).includes('CANARY'));
 }
});


test('quiescence projection accepts exactly the known nonnegative safe integer counters',()=>{
 for(const key of Object.keys(zeroValue())){
  const value={...zeroValue(),[key]:Number.MAX_SAFE_INTEGER};assert.deepEqual(projectQuiescence(JSON.stringify(value)),value);
  assert.throws(()=>zeros(JSON.stringify(value)),/QUALIFICATION_NONEMPTY/);
 }
 const missing=zeroValue();delete missing.auth_users;
 for(const raw of ['CANARY_SECRET','null','[]','"CANARY_SECRET"',JSON.stringify(missing),JSON.stringify({...zeroValue(),extra:'CANARY_SECRET'}),
  ...[-1,0.5,Number.MAX_SAFE_INTEGER+1,'0',null,false,{},[]].map(v=>JSON.stringify({...zeroValue(),auth_users:v}))]){
  assert.throws(()=>projectQuiescence(raw),/QUALIFICATION_QUIESCENCE_REPORT/);
 }
});
test('each nonzero preflight counter is preserved before refusal without executing the canonical test',()=>{
 for(const key of Object.keys(zeroValue())){
  const value={...zeroValue(),[key]:1},e=evidence(),r=fakeRuntime(),sql=r.sql,proof=[];
  r.sql=(bytes,flags={})=>bytes.toString()===QUIESCENCE?JSON.stringify(value):sql(bytes,flags);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))),/QUALIFICATION_NONEMPTY/);
  const last=proof.at(-1);assert.deepEqual(last.before,value);assert.equal(last.after,undefined);
  assert.ok(proof.some(x=>x.before?.[key]===1&&!x.failure));assert.equal(last.phase,'canonical_preflight');
  assert.equal(last.canonical_test_passed,false);assert.equal(last.rollback_verified,false);assert.equal(r.calls.some(x=>x.flags?.test),false);
 }
});
test('nonzero post-test counter is preserved but cannot confirm rollback or a successful qualification',()=>{
 const value={...zeroValue(),vault_secrets:1},e=evidence(),r=fakeRuntime(),sql=r.sql,proof=[];let probes=0;
 r.sql=(bytes,flags={})=>bytes.toString()===QUIESCENCE?JSON.stringify(++probes===1?zeroValue():value):sql(bytes,flags);
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))),/QUALIFICATION_NONEMPTY/);
 const last=proof.at(-1);assert.deepEqual(last.before,zeroValue());assert.deepEqual(last.after,value);assert.equal(last.phase,'rollback_verification');
 assert.equal(last.canonical_test_passed,true);assert.equal(last.rollback_verified,false);assert.equal(last.result,'IMPORT_NOT_PROVEN');
 assert.equal(r.calls.filter(x=>x.flags?.test).length,1);
});
test('malformed quiescence is never persisted and its raw contents cannot escape through failure reports',()=>{
 for(const malformedAt of [1,2])for(const raw of ['CANARY_SECRET',JSON.stringify({...zeroValue(),vault_secrets:'CANARY_SECRET'}),JSON.stringify({...zeroValue(),extra:'CANARY_SECRET'})]){
  const e=evidence(),r=fakeRuntime(),sql=r.sql,proof=[];let probes=0;
  r.sql=(bytes,flags={})=>bytes.toString()===QUIESCENCE?(++probes===malformedAt?raw:JSON.stringify(zeroValue())):sql(bytes,flags);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))),/QUALIFICATION_QUIESCENCE_REPORT/);
  const last=proof.at(-1);assert.equal(last.failure.code,'QUALIFICATION_QUIESCENCE_REPORT');assert.equal(last.rollback_verified,false);
  assert.equal(last[malformedAt===1?'before':'after'],undefined);assert.ok(!JSON.stringify(proof).includes('CANARY_SECRET'));
  assert.equal(r.calls.filter(x=>x.flags?.test).length,malformedAt-1);
 }
});

test('local Vault provenance requires exactly one byte-identical pinned migration before any SQL',()=>{
 for(const mutate of [e=>e.migrations=e.migrations.filter(x=>x.path!==VAULT_PROVENANCE_PATH),e=>e.migrations.push(e.migrations.find(x=>x.path===VAULT_PROVENANCE_PATH)),e=>e.migrations.find(x=>x.path===VAULT_PROVENANCE_PATH).sha256='0'.repeat(64),e=>e.migrations.find(x=>x.path===VAULT_PROVENANCE_PATH).bytes=Buffer.from('CANARY')]){
  const e=evidence(),r=fakeRuntime(),proof=[];mutate(e);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))),/QUALIFICATION_LOCAL_VAULT_REFUSED/);
  assert.equal(r.calls.length,0);assert.equal(proof.at(-1).canonical_test_passed,false);assert.ok(!JSON.stringify(proof).includes('CANARY'));
 }
 assert.equal(hash(load(VAULT_PROVENANCE_PATH)),VAULT_PROVENANCE_SHA);
});
test('Vault probes enclose only the pinned migration and retain identity privately while public evidence contains counts and booleans',()=>{
 const e=evidence(),r=fakeRuntime(),proof=[];const result=qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x)));
 const sql=r.calls.filter(x=>x.bytes),mi=sql.findIndex(x=>x.bytes===load(VAULT_PROVENANCE_PATH));
 assert.equal(sql[mi-1].bytes.toString(),VAULT_METADATA_PROBE);assert.equal(sql[mi+1].bytes.toString(),VAULT_METADATA_PROBE);
 assert.deepEqual(sql[mi].flags,{migration:true});assert.equal(sql.filter(x=>x.bytes.toString()===VAULT_METADATA_PROBE).length,2);
 const cleanup=sql.findIndex(x=>x.bytes.toString().includes('DO $vault_cleanup$'));
 assert.ok(cleanup>sql.findIndex(x=>x.bytes.toString()===STOP_CRONS));assert.ok(cleanup<sql.findIndex(x=>x.flags.test));
 assert.deepEqual(result.local_vault,{before_count:0,after_count:1,metadata_exact:true,provenance_verified:true,removed_count:1,after_cleanup_count:0});
 for(const privateValue of Object.values(vaultReceipt()))assert.ok(!JSON.stringify(proof).includes(privateValue));
 assert.deepEqual(result.before,zeroValue());assert.deepEqual(result.after,zeroValue());
});
test('Vault identity uses exact epoch strings and refuses malformed, unbounded or extra metadata before interpolation',()=>{
 assert.equal(readVaultMetadata(JSON.stringify(vaultMetadata())),null);assert.deepEqual(readVaultMetadata(JSON.stringify(vaultMetadata(true)),{after:true}),vaultReceipt());
 const mutations=[v=>v.total=2,v=>v.metadata_exact=false,v=>v.receipt.id="';DELETE",v=>v.receipt.created_epoch=1790955000.123456,v=>v.receipt.created_epoch='1e10',v=>v.receipt.created_epoch='1790955000.1234567',v=>v.receipt.updated_epoch='1790955000.123457',v=>v.receipt.extra='CANARY',v=>v.extra='CANARY',v=>delete v.receipt.created_epoch,v=>v.receipt=null];
 for(const mutate of mutations){const v=vaultMetadata(true);mutate(v);assert.throws(()=>readVaultMetadata(JSON.stringify(v),{after:true}),/QUALIFICATION_LOCAL_VAULT_REFUSED/);}
 for(const raw of ['CANARY','null','[]'])assert.throws(()=>readVaultMetadata(raw,{after:true}));
 for(const receipt of [null,{}, {...vaultReceipt(),id:"';DROP"},{...vaultReceipt(),created_epoch:'1790955000.123456 OR true'}, {...vaultReceipt(),extra:'CANARY'}])assert.throws(()=>localVaultCleanupSQL(receipt),/QUALIFICATION_LOCAL_VAULT_REFUSED/);
});
test('preexisting or unexpected post-migration Vault metadata refuses before any cleanup or canonical test',()=>{
 for(const badAt of [1,2])for(const malformed of [vaultMetadata(true),{total:2,metadata_exact:true,receipt:null},{...vaultMetadata(true),receipt:{...vaultReceipt(),extra:'CANARY'}},'CANARY']){
  const e=evidence(),r=fakeRuntime(),sql=r.sql,proof=[];let n=0;
  const bad=badAt===2&&malformed?.total===1&&!malformed.receipt?.extra?{...malformed,metadata_exact:false}:malformed;
  r.sql=(bytes,flags={})=>bytes.toString()===VAULT_METADATA_PROBE&&++n===badAt?(typeof bad==='string'?bad:JSON.stringify(bad)):sql(bytes,flags);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))),/QUALIFICATION_LOCAL_VAULT_REFUSED/);
  assert.equal(r.calls.some(x=>x.bytes?.toString().includes('DO $vault_cleanup$')),false);assert.equal(r.calls.some(x=>x.flags?.test),false);
  assert.equal(r.calls.some(x=>x.bytes===e.migrations.at(-1).bytes),false);assert.equal(proof.at(-1).phase,badAt===1?'local_vault_provenance_before':'local_vault_provenance_after');
  assert.equal(r.calls.some(x=>x.bytes===load(VAULT_PROVENANCE_PATH)),badAt===2);assert.ok(!JSON.stringify(proof).includes('CANARY'));
 }
});
test('local Vault cleanup uses existing rights, locked exact identity and zero guards without decryption or broad delete',()=>{
 const sql=localVaultCleanupSQL(vaultReceipt());
 assert.ok(VAULT_METADATA_PROBE.startsWith('BEGIN READ ONLY;\nSET LOCAL row_security=off;\n'+LOCAL_GUARD));
 assert.ok(sql.startsWith('BEGIN;\nSET LOCAL row_security=off;\n'+LOCAL_GUARD));assert.ok(sql.endsWith('COMMIT;'));
 assert.ok(sql.includes("has_table_privilege(current_user,'vault.secrets','DELETE') IS DISTINCT FROM true"));assert.ok(sql.includes('rolsuper'));
 assert.ok(sql.indexOf('LOCK TABLE vault.secrets IN EXCLUSIVE MODE;')<sql.indexOf('DELETE FROM vault.secrets'));
 assert.equal((sql.match(/DELETE FROM vault\.secrets/g)||[]).length,1);assert.ok(sql.includes("DELETE FROM vault.secrets WHERE id='"+vaultReceipt().id+"'::uuid"));
 assert.equal((sql.match(/name='cron_automations_key' AND description='Secret dédié aux appels pg_cron vers les Edge Functions Jolene'/g)||[]).length,2);
 assert.equal((sql.match(/extract\(epoch FROM created_at\)::text='1790955000\.123456'/g)||[]).length,2);
 assert.ok(sql.includes('GET DIAGNOSTICS removed = ROW_COUNT;'));assert.ok(sql.includes('IF removed<>1 OR'));
 assert.ok(sql.includes(JSON.stringify({...zeroValue(),vault_secrets:1})));assert.ok(sql.includes(JSON.stringify(zeroValue())));
 for(const text of [sql,VAULT_METADATA_PROBE])assert.ok(!/decrypted_secrets|decrypted_secret|\bkey_id\b|\bnonce\b|\bsecret\b|SELECT \*|RETURNING \*|GRANT |ALTER ROLE|SET ROLE|TRUNCATE|DROP |INSERT INTO|CREATE /.test(text));
});
test('refused SQL cleanup never retries or runs the canonical test and cannot leak private identity',()=>{
 const e=evidence(),r=fakeRuntime({failOn:bytes=>bytes.toString().includes('DO $vault_cleanup$')}),proof=[];
 assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
 assert.equal(r.calls.filter(x=>x.bytes?.toString().includes('DO $vault_cleanup$')).length,1);assert.equal(r.calls.some(x=>x.flags?.test),false);
 assert.equal(proof.at(-1).phase,'local_vault_cleanup');assert.equal(proof.at(-1).local_vault.removed_count,undefined);
 assert.equal(proof.at(-1).rollback_verified,false);for(const v of [...Object.values(vaultReceipt()),'CANARY'])assert.ok(!JSON.stringify(proof).includes(v));
});
test('only exactly one removed local artifact and an empty Vault permit canonical preflight',()=>{
 for(const result of [{removed_count:0,after_cleanup_count:0},{removed_count:2,after_cleanup_count:0},{removed_count:1,after_cleanup_count:1},{removed_count:1,after_cleanup_count:0,extra:'CANARY'},'CANARY']){
  const e=evidence(),r=fakeRuntime(),sql=r.sql,proof=[];
  r.sql=(bytes,flags={})=>bytes.toString().includes('DO $vault_cleanup$')?(typeof result==='string'?result:JSON.stringify(result)):sql(bytes,flags);
  assert.throws(()=>qualify(e,r,r.extensionSQL,requirements,x=>proof.push(structuredClone(x))));
  assert.equal(proof.at(-1).phase,'local_vault_cleanup');assert.equal(proof.at(-1).local_vault.removed_count,undefined);assert.equal(r.calls.some(x=>x.flags?.test),false);assert.ok(!JSON.stringify(proof).includes('CANARY'));
 }
});


test('new fixture is read only from current checkout and pinned while migrations remain canonical',()=>{
 const canonical=p=>{assert.notEqual(p,TEST_PATH);return load(p);};
 const r=buildReplay(paths,canonical,load);assert.equal(r.test.bytes,load(TEST_PATH));assert.equal(r.test.sha256,TEST_SHA256);
 assert.equal(checkIdentity(env,head,[TEST_PATH],'' ).product_sha,PRODUCT_SHA);
 for(const bytes of [Buffer.concat([load(TEST_PATH),Buffer.from('\n')]),Buffer.alloc(0),'not-a-buffer'])
  assert.throws(()=>buildReplay(paths,canonical,p=>p===TEST_PATH?bytes:load(p)),/PINNED_TEST_BYTES_CHANGED/);
 assert.throws(()=>buildReplay(paths,canonical,p=>p===paths[0]?Buffer.concat([load(p),Buffer.from('\n')]):load(p)),/CANONICAL_BYTES_CHANGED/);
});
test('refund fixture assertion diagnostics expose bounded codes only, preserving ERROR line',()=>{
 for(const code of ['REUSE_PROTECTED_ROWS_CHANGED','WITNESS_CANONICAL_COMMISSION_REFUSED']){
  const raw='psql:<stdin>:7: WARNING:  25001: prior CANARY\npsql:<stdin>:951: ERROR:  P0001: '+code+': CANARY\nCONTEXT: CANARY';
  const d=projectSqlDiagnostic(raw);assert.deepEqual(d,{sqlstate:'P0001',line:951,assertion:code});
  const out=safeFailure(Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:d}));
  assert.deepEqual(out,{code:'QUALIFICATION_SQL_FAILED',sqlstate:'P0001',input_line:951,assertion:code});
  assert.ok(!JSON.stringify(out).includes('CANARY'));
 }
 for(const code of ['OTHER_CANARY','reuse_lowercase','WITNESS_'+ 'A'.repeat(81)]){
  assert.equal(projectSqlDiagnostic('ERROR:  P0001: '+code).assertion,null);
  assert.equal(safeFailure(Object.assign(Error('QUALIFICATION_SQL_FAILED'),{diagnostic:{assertion:code}})).assertion,null);
 }
});

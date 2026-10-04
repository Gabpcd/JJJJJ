#!/usr/bin/env node
// Temporary, dispatch-only qualification. No cloud credentials, API, CLI or fixture service.
import {readFileSync,writeFileSync,renameSync,lstatSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {qualifiedSession,QUALIFICATION_DB,SQL_DIAGNOSTIC_CATEGORIES,expectedDefaultAclGrants} from './bootstrap.mjs';
import {compareRequired} from './extensions.mjs';
export const QUALIFICATION_BRANCH='ci/qualification-pg17-refund-20261004';
export const PRODUCT_SHA='01b135471e1e6ee7ee31439ffc248c8b8519260c';
export const VAULT_PROVENANCE_PATH='supabase/migrations/20260729121442_securiser_auth_et_crons_critiques.sql';
export const VAULT_PROVENANCE_SHA='c123858a03b188317f4889de989ca2a104a205956256635595176aece0507faf';
export const TEST_PATH='tests/security/refund-reuse-fixture-pg17.test.sql';
export const TEST_SHA256='12639614a3d1dcee4e3c6841ecd76ef8932096b6115076a669899c3a33066451';
export const SCAFFOLD_PATHS=[
 TEST_PATH,
 '.github/workflows/restore-local-bootstrap.yml',
 'vercel.json',
 'tools/restore-local/scripts/restore/bootstrap.mjs',
 'tools/restore-local/scripts/restore/qualify-import.mjs',
 'tools/restore-local/scripts/restore/qualify-import.test.mjs',
 'tools/restore-local/QUALIFICATION-PG17.md',
];
const HERE=dirname(fileURLToPath(import.meta.url)),ROOT=resolve(HERE,'../../../..');
export const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const refuse=code=>{throw new Error(code)};
function git(args){
 const r=spawnSync('git',args,{cwd:ROOT,encoding:null,maxBuffer:32*1024*1024,timeout:20000,env:{PATH:process.env.PATH,HOME:process.env.HOME,GIT_CONFIG_NOSYSTEM:'1'}});
 if(r.error||r.status!==0)refuse('SOURCE_GIT_REFUSED');return r.stdout;
}
export function checkIdentity(env,head,changes,dirty){
 if(env.GITHUB_REPOSITORY!=='Gabpcd/JJJJJ'||env.GITHUB_EVENT_NAME!=='workflow_dispatch'
  ||env.GITHUB_REF!=='refs/heads/'+QUALIFICATION_BRANCH
  ||!/^\d{1,15}$/.test(env.GITHUB_RUN_ID??'')||!/^\d{1,3}$/.test(env.GITHUB_RUN_ATTEMPT??'')
  ||!/^([a-f0-9]{40})$/.test(head)||env.GITHUB_SHA!==head||head===PRODUCT_SHA
  ||dirty!==''||changes.length===0||changes.some(p=>!SCAFFOLD_PATHS.includes(p)))refuse('QUALIFICATION_IDENTITY_REFUSED');
 return {product_sha:PRODUCT_SHA,harness_sha:head,event:'workflow_dispatch',run:'jolene-restore-drill-'+env.GITHUB_RUN_ID+'-'+env.GITHUB_RUN_ATTEMPT};
}
export function checkVercel(base,current,ref){
 if(ref!=='refs/heads/'+QUALIFICATION_BRANCH||!base||Array.isArray(base)||typeof base!=='object'
  ||(base.git!==undefined&&(base.git===null||Array.isArray(base.git)||typeof base.git!=='object'))
  ||(base.git?.deploymentEnabled!==undefined&&(base.git.deploymentEnabled===null||Array.isArray(base.git.deploymentEnabled)||typeof base.git.deploymentEnabled!=='object')))refuse('QUALIFICATION_VERCEL_REFUSED');
 const expected={...base,git:{...(base.git??{}),deploymentEnabled:{...(base.git?.deploymentEnabled??{}),[QUALIFICATION_BRANCH]:false}}};
 if(!isDeepStrictEqual(current,expected))refuse('QUALIFICATION_VERCEL_REFUSED');return true;
}
export function buildReplay(paths,readCanonical,readCurrent){
 const names=paths.filter(p=>p.startsWith('supabase/migrations/')).sort();
 if(names.length<2||names[0]!=='supabase/migrations/00000000000000_baseline_prod.sql'
  ||!names.includes('supabase/migrations/20261002064017_lire_candidatures_mission_habilitee.sql')
  ||new Set(names).size!==names.length||names.some(p=>!/^supabase\/migrations\/\d{14}_[a-z0-9_]+\.sql$/.test(p)))refuse('MIGRATION_ORDER_REFUSED');
 const migrations=names.map(path=>{
  const bytes=readCanonical(path),current=readCurrent(path);
  if(!Buffer.isBuffer(bytes)||!Buffer.isBuffer(current)||!bytes.equals(current)||bytes.length===0)refuse('CANONICAL_BYTES_CHANGED');
  // Whole files are replayed, never filtered, wrapped or normalized.
  return {path,sha256:hash(bytes),bytes};
 });
 // The fixture is newly committed on this qualification branch, never read from PRODUCT_SHA.
 // Its exact path is allowlisted above and every byte is independently pinned here.
 const bytes=readCurrent(TEST_PATH);
 if(!Buffer.isBuffer(bytes)||bytes.length===0||hash(bytes)!==TEST_SHA256)refuse('PINNED_TEST_BYTES_CHANGED');
 return {migrations,test:{path:TEST_PATH,sha256:TEST_SHA256,bytes}};
}
export function source(env=process.env){
 const head=git(['rev-parse','HEAD']).toString().trim();
 git(['merge-base','--is-ancestor',PRODUCT_SHA,head]);
 const changes=git(['diff','--name-only','-z',PRODUCT_SHA,head]).toString().split('\0').filter(Boolean);
 const identity=checkIdentity(env,head,changes,git(['status','--porcelain','--untracked-files=all']).toString());
 checkVercel(JSON.parse(git(['show',PRODUCT_SHA+':vercel.json'])),JSON.parse(readFileSync(resolve(ROOT,'vercel.json'))),env.GITHUB_REF);
 const paths=git(['ls-tree','-r','--name-only','-z',PRODUCT_SHA,'supabase/migrations']).toString().split('\0').filter(Boolean);
 const replay=buildReplay(paths,path=>git(['show',PRODUCT_SHA+':'+path]),path=>{
  const file=resolve(ROOT,path);if(!lstatSync(file).isFile())refuse('CANONICAL_FILE_TYPE');return readFileSync(file);
 });
 return {...identity,...replay};
}
export const LOCAL_GUARD=`
DO $local$
BEGIN
 IF current_database()<>'${QUALIFICATION_DB}' OR inet_server_addr() IS NOT NULL
  OR session_user<>'postgres' OR current_user<>session_user
  OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
  OR current_setting('cron.database_name')<>'${QUALIFICATION_DB}'
  OR current_setting('cron.launch_active_jobs')<>'off'
  OR current_setting('max_worker_processes')<>'0'
  OR EXISTS(SELECT 1 FROM pg_stat_activity WHERE backend_type IN ('pg_cron launcher','pg_cron worker','pg_net worker'))
 THEN RAISE EXCEPTION 'QUALIFICATION_LOCAL_CONTEXT_REQUIRED'; END IF;
END $local$;`;
export const STOP_CRONS=`BEGIN;
SET LOCAL row_security=off;
${LOCAL_GUARD}
DO $cron_guard$
BEGIN
 IF (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) IS DISTINCT FROM false
  OR has_function_privilege(current_user,'cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'QUALIFICATION_CRON_API_CONTEXT_REQUIRED'; END IF;
 -- row_security=off raises if a policy would hide jobs; it never grants BYPASSRLS.
 IF EXISTS(SELECT 1 FROM cron.job WHERE username IS DISTINCT FROM current_user)
 THEN RAISE EXCEPTION 'QUALIFICATION_CRON_OWNERSHIP_REQUIRED'; END IF;
END $cron_guard$;
-- This count is consumed only if the complete transaction below succeeds.
SELECT jsonb_build_object('locally_disabled_jobs',count(*)) FROM cron.job WHERE active;
DO $stop_crons$
DECLARE job record; before_jobs jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(to_jsonb(j)-'active' ORDER BY j.jobid),'[]'::jsonb) INTO before_jobs FROM cron.job j;
 FOR job IN SELECT jobid FROM cron.job WHERE active AND username=current_user ORDER BY jobid LOOP
  PERFORM cron.alter_job(job.jobid,active:=false);
 END LOOP;
 IF EXISTS(SELECT 1 FROM cron.job WHERE active)
  OR before_jobs IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(j)-'active' ORDER BY j.jobid),'[]'::jsonb) FROM cron.job j)
 THEN RAISE EXCEPTION 'QUALIFICATION_CRON_DEACTIVATION_REQUIRED'; END IF;
END $stop_crons$;
COMMIT;`;
const QUIESCENCE_COUNTS=`jsonb_build_object(
 'auth_users',(SELECT count(*) FROM auth.users),
 'auth_sessions',(SELECT count(*) FROM auth.sessions),
 'soignants',(SELECT count(*) FROM public.soignants),
 'etablissements',(SELECT count(*) FROM public.etablissements),
 'missions',(SELECT count(*) FROM public.missions),
 'candidatures',(SELECT count(*) FROM public.candidatures),
 'members',(SELECT count(*) FROM public.membres_etablissement),
 'externalisations',(SELECT count(*) FROM public.externalisation_actions),
 'storage_objects',(SELECT count(*) FROM storage.objects),
 'active_crons',(SELECT count(*) FROM cron.job WHERE active),
 'cron_executions',(SELECT count(*) FROM cron.job_run_details),
 'http_queue',(SELECT count(*) FROM net.http_request_queue),
 'http_responses',(SELECT count(*) FROM net._http_response),
 'vault_secrets',(SELECT count(*) FROM vault.secrets))`;
export const QUIESCENCE=`BEGIN READ ONLY;
SET LOCAL row_security=off;
${LOCAL_GUARD}
SELECT ${QUIESCENCE_COUNTS};
ROLLBACK;`;
const ZERO_KEYS=['auth_users','auth_sessions','soignants','etablissements','missions','candidatures','members','externalisations','storage_objects','active_crons','cron_executions','http_queue','http_responses','vault_secrets'];
export function projectQuiescence(text){
 const fail=()=>refuse('QUALIFICATION_QUIESCENCE_REPORT');
 let value;try{value=JSON.parse(text);}catch{fail();}
 if(!value||typeof value!=='object'||Array.isArray(value)
  ||Object.keys(value).sort().join()!==[...ZERO_KEYS].sort().join()
  ||ZERO_KEYS.some(k=>!Number.isSafeInteger(value[k])||value[k]<0))fail();
 return Object.fromEntries(ZERO_KEYS.map(k=>[k,value[k]]));
}
export function zeros(text){
 const value=projectQuiescence(text);if(Object.values(value).some(x=>x!==0))refuse('QUALIFICATION_NONEMPTY');return value;
}
// Only nonsensitive identity metadata leaves SQL, and remains private in this process.
export const VAULT_METADATA_PROBE=`BEGIN READ ONLY;
SET LOCAL row_security=off;
${LOCAL_GUARD}
SELECT jsonb_build_object(
 'total',count(*),
 'metadata_exact',coalesce(bool_and(name='cron_automations_key' AND description='Secret dédié aux appels pg_cron vers les Edge Functions Jolene'),false),
 'receipt',CASE WHEN count(*)=1 THEN jsonb_build_object(
  'id',min(id::text),'created_epoch',min(extract(epoch FROM created_at)::text),'updated_epoch',min(extract(epoch FROM updated_at)::text)) ELSE NULL END)
FROM vault.secrets;
ROLLBACK;`;
function validVaultReceipt(value){
 return !!value&&typeof value==='object'&&!Array.isArray(value)
  &&Object.keys(value).sort().join()==='created_epoch,id,updated_epoch'
  &&typeof value.id==='string'&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(value.id)
  &&typeof value.created_epoch==='string'&&/^\d{10}\.\d{6}$/.test(value.created_epoch)
  &&value.updated_epoch===value.created_epoch;
}
export function readVaultMetadata(raw,{after=false}={}){
 let value;try{value=JSON.parse(raw);}catch{refuse('QUALIFICATION_LOCAL_VAULT_REFUSED');}
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join()!=='metadata_exact,receipt,total'
  ||value.total!==(after?1:0)||value.metadata_exact!==after
  ||(after?!validVaultReceipt(value.receipt):value.receipt!==null))refuse('QUALIFICATION_LOCAL_VAULT_REFUSED');
 return after?{id:value.receipt.id,created_epoch:value.receipt.created_epoch,updated_epoch:value.receipt.updated_epoch}:null;
}
export function localVaultCleanupSQL(receipt){
 if(!validVaultReceipt(receipt))refuse('QUALIFICATION_LOCAL_VAULT_REFUSED');
 const empty=Object.fromEntries(ZERO_KEYS.map(k=>[k,0])),before={...empty,vault_secrets:1};
 return `BEGIN;
SET LOCAL row_security=off;
${LOCAL_GUARD}
DO $vault_cleanup$
DECLARE removed bigint;
BEGIN
 IF (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) IS DISTINCT FROM false
  OR has_table_privilege(current_user,'vault.secrets','DELETE') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'QUALIFICATION_LOCAL_VAULT_PRIVILEGE'; END IF;
 LOCK TABLE vault.secrets IN EXCLUSIVE MODE;
 IF (${QUIESCENCE_COUNTS}) IS DISTINCT FROM '${JSON.stringify(before)}'::jsonb
  OR NOT EXISTS(SELECT 1 FROM vault.secrets WHERE id='${receipt.id}'::uuid
   AND name='cron_automations_key' AND description='Secret dédié aux appels pg_cron vers les Edge Functions Jolene'
   AND extract(epoch FROM created_at)::text='${receipt.created_epoch}' AND extract(epoch FROM updated_at)::text='${receipt.updated_epoch}')
 THEN RAISE EXCEPTION 'QUALIFICATION_LOCAL_VAULT_PROVENANCE'; END IF;
 DELETE FROM vault.secrets WHERE id='${receipt.id}'::uuid
  AND name='cron_automations_key' AND description='Secret dédié aux appels pg_cron vers les Edge Functions Jolene'
  AND extract(epoch FROM created_at)::text='${receipt.created_epoch}' AND extract(epoch FROM updated_at)::text='${receipt.updated_epoch}';
 GET DIAGNOSTICS removed = ROW_COUNT;
 IF removed<>1 OR (${QUIESCENCE_COUNTS}) IS DISTINCT FROM '${JSON.stringify(empty)}'::jsonb
 THEN RAISE EXCEPTION 'QUALIFICATION_LOCAL_VAULT_CLEANUP'; END IF;
END $vault_cleanup$;
SELECT jsonb_build_object('removed_count',1,'after_cleanup_count',(SELECT count(*) FROM vault.secrets));
COMMIT;`;
}
export function exactExtensions(requirements,runtime){
 const result=compareRequired(requirements,runtime);
 if(!result.declarations_compatible||result.checks.some(c=>c.installed_version_matches!==true||c.installed_schema_matches!==true))refuse('EXTENSION_EXACT_INSTALL_REQUIRED');
 return result.checks;
}
export function projectOwnerProbe(value){
 const owners=['postgres','supabase_admin'];
 const out={named_owner:owners.includes(value?.named_owner)?value.named_owner:'other',native_owner:owners.includes(value?.native_owner)?value.native_owner:'other'};
 for(const key of ['local_empty_context','session_postgres','named_create','native_create','named_connect','native_connect','named_temp','native_temp','postgres_superuser','admin_superuser'])out[key]=typeof value?.[key]==='boolean'?value[key]:null;
 return out;
}
export function ownerProbe(value,{repaired=false}={}){
 const expected={local_empty_context:true,session_postgres:true,named_owner:repaired?'postgres':'supabase_admin',native_owner:'postgres',
  named_create:repaired,native_create:true,named_connect:true,native_connect:true,named_temp:true,native_temp:true,
  postgres_superuser:false,admin_superuser:true};
 if(!isDeepStrictEqual(value,expected))refuse('QUALIFICATION_OWNER_REFUSED');return expected;
}
export function projectDefaultAclProbe(value){
 const bool=k=>typeof value?.[k]==='boolean'?value[k]:null;
 const count=k=>Number.isSafeInteger(value?.[k])&&value[k]>=0&&value[k]<=10000?value[k]:null;
 const privileges=new Set(expectedDefaultAclGrants().map(x=>x.privilege));
 const grants=Array.isArray(value?.target_grants)&&value.target_grants.length<=100?value.target_grants.map(row=>({
  object_type:['r','S','f'].includes(row?.object_type)?row.object_type:'other',
  grantee:['anon','authenticated'].includes(row?.grantee)?row.grantee:'other',
  grantor:row?.grantor==='postgres'?'postgres':'other',
  privilege:privileges.has(row?.privilege)?row.privilege:'other',
  is_grantable:typeof row?.is_grantable==='boolean'?row.is_grantable:null,
 })):null;
 return {local_empty_context:bool('local_empty_context'),postgres_superuser:bool('postgres_superuser'),global_client_grants:count('global_client_grants'),
  target_grants:grants,other_acl_count:count('other_acl_count'),other_acl_md5:/^[a-f0-9]{32}$/.test(value?.other_acl_md5??'')?value.other_acl_md5:null};
}
export function checkDefaultAclProbe(value,{aligned=false,before}={}){
 const p=projectDefaultAclProbe(value);
 if(!isDeepStrictEqual(value,p)||p.local_empty_context!==true||p.postgres_superuser!==false||p.global_client_grants!==0
  ||p.other_acl_count===null||p.other_acl_md5===null||!isDeepStrictEqual(p.target_grants,aligned?[]:expectedDefaultAclGrants())
  ||(aligned&&(!before||p.other_acl_count!==before.other_acl_count||p.other_acl_md5!==before.other_acl_md5)))refuse('QUALIFICATION_DEFAULT_ACL_REFUSED');
 return p;
}
export const BASELINE_PATH='supabase/migrations/00000000000000_baseline_prod.sql';
export function projectBaselineServiceDefault(value){
 const bool=k=>typeof value?.[k]==='boolean'?value[k]:null;
 const count=k=>Number.isSafeInteger(value?.[k])&&value[k]>=0&&value[k]<=10000?value[k]:null;
 return {local_isolated_context:bool('local_isolated_context'),local_empty_context:bool('local_empty_context'),postgres_superuser:bool('postgres_superuser'),
  global_service_function_grants:count('global_service_function_grants'),client_grants:count('client_grants'),
  target_grants:Array.isArray(value?.target_grants)&&value.target_grants.length<=16?value.target_grants.map(v=>({grantor:v?.grantor==='postgres'?'postgres':'other',privilege:v?.privilege==='EXECUTE'?'EXECUTE':'other',is_grantable:typeof v?.is_grantable==='boolean'?v.is_grantable:null})):null,
  other_acl_count:count('other_acl_count'),other_acl_md5:typeof value?.other_acl_md5==='string'&&/^[a-f0-9]{32}$/.test(value.other_acl_md5)?value.other_acl_md5:null};
}
export function checkBaselineServiceDefault(value,{phase='before',before}={}){
 const p=projectBaselineServiceDefault(value),expected=phase==='suspended'?[]:[{grantor:'postgres',privilege:'EXECUTE',is_grantable:false}];
 if(!['before','suspended','restored'].includes(phase)||!isDeepStrictEqual(value,p)
  ||p.local_isolated_context!==true||p.local_empty_context!==(phase!=='restored')||p.postgres_superuser!==false
  ||p.global_service_function_grants!==0||p.client_grants!==0||!isDeepStrictEqual(p.target_grants,expected)
  ||p.other_acl_count===null||p.other_acl_md5===null
  ||(phase!=='before'&&(!before||p.other_acl_count!==before.other_acl_count||p.other_acl_md5!==before.other_acl_md5)))refuse('QUALIFICATION_BASELINE_DEFAULT_REFUSED');
 return p;
}
export const HISTORICAL_MANIFEST_PATH='supabase/migrations/20260729121443_figer_inventaire_security_definer.sql';
export const HISTORICAL_MANIFEST_SHA='160626d9fab04c230e517f8774101a7644a52b014d6bf5c1e8f10f66e1c6aa6f';
export function historicalManifestEntries(bytes){
 if(!Buffer.isBuffer(bytes)||hash(bytes)!==HISTORICAL_MANIFEST_SHA)refuse('QUALIFICATION_MANIFEST_DIAGNOSTIC_REFUSED');
 const rows=[...bytes.toString().matchAll(/^  \('([^']+)', '[A-Z_]+', '([a-f0-9]{32})',/gm)].map(m=>({signature:m[1],expected_md5:m[2]}));
 if(rows.length!==422||new Set(rows.map(r=>r.signature)).size!==422)refuse('QUALIFICATION_MANIFEST_DIAGNOSTIC_REFUSED');
 return rows;
}
export function historicalManifestSQL(entries){
 // Entries only come from the byte-pinned historical manifest, never live recapture.
 if(entries.length!==422)refuse('QUALIFICATION_MANIFEST_DIAGNOSTIC_REFUSED');
 const quote=x=>"'"+x.replaceAll("'","''")+"'";
 return `BEGIN READ ONLY;\n${LOCAL_GUARD}
WITH expected(signature,expected_md5) AS (VALUES ${entries.map(r=>'('+quote(r.signature)+','+quote(r.expected_md5)+')').join(',')}),
actual AS (
 SELECT p.oid::regprocedure::text AS signature,md5(p.prosrc) AS actual_md5,p.oid,p.prosecdef,p.prokind
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
), compared AS (
 SELECT e.signature,e.expected_md5,a.actual_md5,
 CASE WHEN a.oid IS NULL OR a.prosecdef IS NOT TRUE OR a.prokind<>'f' THEN 'missing_or_not_definer'
      WHEN a.actual_md5<>e.expected_md5 THEN 'hash_mismatch' ELSE 'match' END AS kind
 FROM expected e LEFT JOIN actual a USING(signature)
)
SELECT jsonb_build_object(
 'expected_count',(SELECT count(*) FROM expected),
 'matched_count',(SELECT count(*) FROM compared WHERE kind='match'),
 'missing_exposed_count',(SELECT count(*) FROM actual a WHERE a.prosecdef IS TRUE AND a.prokind='f'
   AND (has_function_privilege('anon',a.oid,'EXECUTE') OR has_function_privilege('authenticated',a.oid,'EXECUTE')
     OR a.signature IN ('fn_doit_notifier(uuid,type_evenement_notification,canal_notification)','fn_sms_doit_envoyer(uuid,text,integer)',
       'fn_generer_numero_contrat_safe(text)','fn_conflit_planning_soignant(uuid,uuid)','fn_calculer_score_matching(uuid,uuid)'))
   AND NOT EXISTS(SELECT 1 FROM expected e WHERE e.signature=a.signature)),
 'differences',coalesce((SELECT jsonb_agg(jsonb_build_object('signature',signature,'kind',kind,'expected_md5',expected_md5,'actual_md5',actual_md5) ORDER BY signature) FROM compared WHERE kind<>'match'),'[]'::jsonb)
);\nROLLBACK;`;
}
export function projectHistoricalManifest(raw,entries){
 const fail=()=>refuse('QUALIFICATION_MANIFEST_DIAGNOSTIC_REFUSED');
 let value;try{value=JSON.parse(raw);}catch{fail();}
 const keys=['expected_count','matched_count','missing_exposed_count','differences'];
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==keys.length||keys.some(k=>!(k in value)))fail();
 if(value.expected_count!==422||!Number.isSafeInteger(value.matched_count)||value.matched_count<0||value.matched_count>422
  ||!Number.isSafeInteger(value.missing_exposed_count)||value.missing_exposed_count<0||value.missing_exposed_count>10000||!Array.isArray(value.differences)
  ||value.differences.length+value.matched_count!==422)fail();
 const expected=new Map(entries.map(x=>[x.signature,x.expected_md5])),seen=new Set();
 const differences=value.differences.map(row=>{
  if(!row||typeof row!=='object'||Array.isArray(row)||Object.keys(row).sort().join()!=='actual_md5,expected_md5,kind,signature'
   ||!expected.has(row.signature)||seen.has(row.signature)||row.expected_md5!==expected.get(row.signature)
   ||!['missing_or_not_definer','hash_mismatch'].includes(row.kind)
   ||!(row.actual_md5===null||/^[a-f0-9]{32}$/.test(row.actual_md5))
   ||(row.kind==='hash_mismatch'&&(row.actual_md5===null||row.actual_md5===row.expected_md5)))fail();
  seen.add(row.signature);return {signature:row.signature,kind:row.kind,expected_md5:row.expected_md5,actual_md5:row.actual_md5};
 });
 return {expected_count:422,matched_count:value.matched_count,missing_exposed_count:value.missing_exposed_count,differences};
}
export const NOTATION_PREFLIGHT_PATH='supabase/migrations/20260930145136_securiser_auteur_notation_mission.sql';
export const NOTATION_PREFLIGHT_SHA='23f7ee94d48fa6c2f7ba48344c341a0db4411d467ec2861c4a0fa2a470abdbe3';
export function notationPreflightSQL(bytes){
 if(!Buffer.isBuffer(bytes)||hash(bytes)!==NOTATION_PREFLIGHT_SHA)refuse('QUALIFICATION_NOTATION_DIAGNOSTIC_REFUSED');
 // Observe metadata before the original guarded migration, never repair or bypass it.
 return `BEGIN READ ONLY;
${LOCAL_GUARD}
WITH notation AS (
 SELECT p.* FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure('public.fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)')
), audit_helper AS (
 SELECT p.* FROM pg_catalog.pg_proc p
 WHERE p.oid=pg_catalog.to_regprocedure('public.fn_ecrire_audit_safe(uuid,text,text,text,uuid,text,jsonb,inet,text)')
), action_constraint AS (
 SELECT c.* FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.journaux_audit') AND c.conname='journaux_audit_action_check'
), actor_constraint AS (
 SELECT c.* FROM pg_catalog.pg_constraint c WHERE c.conrelid=pg_catalog.to_regclass('public.journaux_audit') AND c.conname='journaux_audit_type_acteur_check'
), inventory AS (
 SELECT definition_md5,categorie FROM private.security_definer_inventory
 WHERE signature='fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)'
), expected AS (
 SELECT '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[] AS acl
), acl_rows AS (
 SELECT u.ordinality AS position,
  CASE WHEN a.grantee=0 THEN 'PUBLIC'
   WHEN pg_catalog.pg_get_userbyid(a.grantee) IN ('postgres','authenticated','service_role','anon') THEN pg_catalog.pg_get_userbyid(a.grantee) ELSE 'other' END AS grantee,
  CASE WHEN pg_catalog.pg_get_userbyid(a.grantor) IN ('postgres','authenticated','service_role','anon') THEN pg_catalog.pg_get_userbyid(a.grantor) ELSE 'other' END AS grantor,
  CASE WHEN a.privilege_type='EXECUTE' THEN 'EXECUTE' ELSE 'other' END AS privilege,
  a.is_grantable
 FROM notation p CROSS JOIN LATERAL unnest(p.proacl) WITH ORDINALITY u(item,ordinality)
 CROSS JOIN LATERAL pg_catalog.aclexplode(ARRAY[u.item]::aclitem[]) a
)
SELECT jsonb_build_object(
 'audit_helper_exists',EXISTS(SELECT 1 FROM audit_helper),
 'audit_helper_md5',(SELECT md5(prosrc) FROM audit_helper),
 'audit_helper_matches',EXISTS(SELECT 1 FROM audit_helper WHERE md5(prosrc)='04cc44127e325b434445113e88ce38b7'),
 'action_constraint_exists',EXISTS(SELECT 1 FROM action_constraint),
 'action_constraint_md5',(SELECT md5(pg_get_constraintdef(oid)) FROM action_constraint),
 'action_constraint_validated',COALESCE((SELECT convalidated FROM action_constraint),false),
 'action_constraint_matches',EXISTS(SELECT 1 FROM action_constraint WHERE convalidated AND md5(pg_get_constraintdef(oid))='5d8ca35986765f1530b47d63b9f8f432'),
 'actor_constraint_exists',EXISTS(SELECT 1 FROM actor_constraint),
 'actor_constraint_md5',(SELECT md5(pg_get_constraintdef(oid)) FROM actor_constraint),
 'actor_constraint_validated',COALESCE((SELECT convalidated FROM actor_constraint),false),
 'actor_constraint_matches',EXISTS(SELECT 1 FROM actor_constraint WHERE convalidated AND md5(pg_get_constraintdef(oid))='cad0a04c75e18f5b5a2b25fe3fd6f5fe'),
 'notation_exists',EXISTS(SELECT 1 FROM notation),
 'notation_md5',(SELECT md5(prosrc) FROM notation),
 'notation_body_matches',EXISTS(SELECT 1 FROM notation WHERE md5(prosrc) IN ('de8b4925694aa624a8e45c22e47416b0','0a12aab3a7d9bfe89e3e4c0b51b68faa')),
 'notation_definer',COALESCE((SELECT prosecdef FROM notation),false),
 'notation_owner_matches',EXISTS(SELECT 1 FROM notation WHERE pg_get_userbyid(proowner)='postgres'),
 'notation_config_matches',EXISTS(SELECT 1 FROM notation WHERE proconfig=ARRAY['search_path=public, extensions']::text[]),
 'notation_acl_exact',EXISTS(SELECT 1 FROM notation p CROSS JOIN expected e WHERE p.proacl=e.acl),
 'notation_acl_set_equal',EXISTS(SELECT 1 FROM notation p CROSS JOIN expected e WHERE cardinality(p.proacl)=cardinality(e.acl) AND p.proacl @> e.acl AND p.proacl <@ e.acl),
 'notation_acl_dimensions_match',EXISTS(SELECT 1 FROM notation p CROSS JOIN expected e WHERE array_dims(p.proacl)=array_dims(e.acl)),
 'notation_acl_entries',COALESCE((SELECT jsonb_agg(jsonb_build_object('position',position,'grantee',grantee,'grantor',grantor,'privilege',privilege,'is_grantable',is_grantable) ORDER BY position,grantee,grantor,privilege) FROM acl_rows),'[]'::jsonb),
 'inventory_single_row',(SELECT count(*)=1 FROM inventory),
 'inventory_matches',EXISTS(SELECT 1 FROM inventory WHERE categorie='MIXTE_TENANT_ADMIN' AND definition_md5 IN ('de8b4925694aa624a8e45c22e47416b0','0a12aab3a7d9bfe89e3e4c0b51b68faa')),
 'inventory_md5',(SELECT CASE WHEN count(*)=1 THEN min(definition_md5) END FROM inventory)
);
ROLLBACK;`;
}
const NOTATION_BOOLS=['audit_helper_exists','audit_helper_matches','action_constraint_exists','action_constraint_validated','action_constraint_matches',
 'actor_constraint_exists','actor_constraint_validated','actor_constraint_matches','notation_exists','notation_body_matches','notation_definer',
 'notation_owner_matches','notation_config_matches','notation_acl_exact','notation_acl_set_equal','notation_acl_dimensions_match','inventory_single_row','inventory_matches'];
const NOTATION_HASHES=['audit_helper_md5','action_constraint_md5','actor_constraint_md5','notation_md5','inventory_md5'];
export function projectNotationPreflight(raw){
 const fail=()=>refuse('QUALIFICATION_NOTATION_DIAGNOSTIC_REFUSED');
 let v;try{v=JSON.parse(raw);}catch{fail();}
 const keys=[...NOTATION_BOOLS,...NOTATION_HASHES,'notation_acl_entries'];
 if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==keys.length||keys.some(k=>!(k in v))
  ||NOTATION_BOOLS.some(k=>typeof v[k]!=='boolean')||NOTATION_HASHES.some(k=>v[k]!==null&&(typeof v[k]!=='string'||!/^[a-f0-9]{32}$/.test(v[k])))
  ||!Array.isArray(v.notation_acl_entries)||v.notation_acl_entries.length>64)fail();
 let previous=0;
 const rows=v.notation_acl_entries.map(row=>{
  if(!row||typeof row!=='object'||Array.isArray(row)||Object.keys(row).sort().join()!=='grantee,grantor,is_grantable,position,privilege'
   ||!Number.isSafeInteger(row.position)||row.position<=previous||row.position>64
   ||!['postgres','authenticated','service_role','anon','PUBLIC','other'].includes(row.grantee)
   ||!['postgres','authenticated','service_role','anon','other'].includes(row.grantor)
   ||!['EXECUTE','other'].includes(row.privilege)||typeof row.is_grantable!=='boolean')fail();
  previous=row.position;return {position:row.position,grantee:row.grantee,grantor:row.grantor,privilege:row.privilege,is_grantable:row.is_grantable};
 });
 return {...Object.fromEntries([...NOTATION_BOOLS,...NOTATION_HASHES].map(k=>[k,v[k]])),notation_acl_entries:rows};
}
export function safeFailure(error){
 const codes=['PINNED_TEST_BYTES_CHANGED','QUALIFICATION_IDENTITY_REFUSED','SOURCE_GIT_REFUSED','MIGRATION_ORDER_REFUSED','CANONICAL_BYTES_CHANGED','CANONICAL_FILE_TYPE','QUALIFICATION_SQL_FAILED','QUALIFICATION_NONEMPTY','QUALIFICATION_QUIESCENCE_REPORT','EXTENSION_EXACT_INSTALL_REQUIRED','QUALIFICATION_RUNTIME_RUN_CHANGED','QUALIFICATION_REPORT_PATH','QUALIFICATION_CRON_REPORT','QUALIFICATION_VERCEL_REFUSED','QUALIFICATION_OWNER_REFUSED','QUALIFICATION_MANIFEST_DIAGNOSTIC_REFUSED','QUALIFICATION_DEFAULT_ACL_REFUSED','QUALIFICATION_NOTATION_DIAGNOSTIC_REFUSED','QUALIFICATION_BASELINE_DEFAULT_REFUSED','QUALIFICATION_LOCAL_VAULT_REFUSED'];
 const code=codes.includes(error?.message)?error.message:'QUALIFICATION_REFUSED';
 const diagnostic=error?.diagnostic;
 return {code,...(code==='QUALIFICATION_SQL_FAILED'?{sqlstate:/^[0-9A-Z]{5}$/.test(diagnostic?.sqlstate??'')?diagnostic.sqlstate:null,
  input_line:Number.isSafeInteger(diagnostic?.line)&&diagnostic.line>0?diagnostic.line:null,
  assertion:/^(?:CAND_MULTI|REUSE|WITNESS|OPERATOR)_[A-Z_]{1,80}$/.test(diagnostic?.assertion??'')?diagnostic.assertion:null,
  ...(SQL_DIAGNOSTIC_CATEGORIES.includes(diagnostic?.category)?{category:diagnostic.category}:{})}:{})};
}
export function qualify(evidence,runtime,extensionSQL,requirements,save){
 const report={result:'IMPORT_NOT_PROVEN',product_sha:evidence.product_sha,harness_sha:evidence.harness_sha,run:evidence.run,
  test_kind:'PINNED_LOCAL_SYNTHETIC',canonical_test_sha256:evidence.test.sha256,migration_count:evidence.migrations.length,
  ordered_manifest_sha256:hash(JSON.stringify(evidence.migrations.map(({path,sha256})=>({path,sha256})))),
  migrations:[],phase:'local_preflight',canonical_test_passed:false,rollback_verified:false,cloud_contacted:false};
 save(report);
 try{
  const vaultItems=evidence.migrations.filter(x=>x.path===VAULT_PROVENANCE_PATH);
  if(vaultItems.length!==1||vaultItems[0].sha256!==VAULT_PROVENANCE_SHA||hash(vaultItems[0].bytes)!==VAULT_PROVENANCE_SHA)refuse('QUALIFICATION_LOCAL_VAULT_REFUSED');
  let localVaultReceipt=null;
  if(runtime.run!==evidence.run)refuse('QUALIFICATION_RUNTIME_RUN_CHANGED');
  runtime.verify();runtime.sql(Buffer.from(LOCAL_GUARD));
  report.phase='native_owner_probe';save(report);
  // Project only a bounded inventory; unexpected ownership refuses before the one local repair.
  const before=runtime.probeDatabaseOwner();
  report.ownership_before=projectOwnerProbe(before);save(report);
  ownerProbe(before);
  report.phase='native_owner_repair';save(report);runtime.repairDatabaseOwner();
  const after=runtime.probeDatabaseOwner();report.ownership_after=projectOwnerProbe(after);save(report);ownerProbe(after,{repaired:true});
  report.local_database_owner_reconciled=true;
  report.phase='native_default_acl_probe';save(report);
  const defaultsBefore=runtime.probeDefaultAcls();report.default_acl_before=projectDefaultAclProbe(defaultsBefore);save(report);checkDefaultAclProbe(defaultsBefore);
  report.phase='native_default_acl_alignment';save(report);runtime.alignDefaultAcls();
  const defaultsAfter=runtime.probeDefaultAcls();report.default_acl_after=projectDefaultAclProbe(defaultsAfter);save(report);
  checkDefaultAclProbe(defaultsAfter,{aligned:true,before:defaultsBefore});report.local_default_acls_aligned=true;
   if(evidence.migrations[0]?.path!==BASELINE_PATH)refuse('QUALIFICATION_BASELINE_DEFAULT_REFUSED');
   report.phase='baseline_service_default_probe';save(report);
   const serviceBefore=runtime.probeBaselineServiceDefault();report.baseline_service_default_before=projectBaselineServiceDefault(serviceBefore);save(report);checkBaselineServiceDefault(serviceBefore);
   report.phase='baseline_service_default_suspend';save(report);runtime.suspendBaselineServiceDefault();
   const serviceSuspended=runtime.probeBaselineServiceDefault();report.baseline_service_default_suspended=projectBaselineServiceDefault(serviceSuspended);save(report);
   checkBaselineServiceDefault(serviceSuspended,{phase:'suspended',before:serviceBefore});
   report.phase='integral_replay';
   for(const item of evidence.migrations){
   if(item.path===HISTORICAL_MANIFEST_PATH){
    const entries=historicalManifestEntries(item.bytes);report.phase='historical_manifest_read_only_probe';save(report);runtime.verify();
    report.historical_manifest={path:item.path,sha256:item.sha256,...projectHistoricalManifest(runtime.sql(Buffer.from(historicalManifestSQL(entries))),entries)};
    save(report);report.phase='integral_replay';
   }
    if(item.path===NOTATION_PREFLIGHT_PATH){
     const sql=notationPreflightSQL(item.bytes);
     if(item.sha256!==NOTATION_PREFLIGHT_SHA)refuse('QUALIFICATION_NOTATION_DIAGNOSTIC_REFUSED');
     report.phase='notation_preflight_read_only_probe';save(report);runtime.verify();
     report.notation_preflight={path:item.path,sha256:item.sha256,...projectNotationPreflight(runtime.sql(Buffer.from(sql)))};
     save(report);report.phase='integral_replay';
    }
   if(item.path===VAULT_PROVENANCE_PATH){
    report.phase='local_vault_provenance_before';save(report);runtime.verify();
    readVaultMetadata(runtime.sql(Buffer.from(VAULT_METADATA_PROBE)));report.local_vault={before_count:0};save(report);report.phase='integral_replay';
   }
   const current={path:item.path,sha256:item.sha256,completed:false};report.migrations.push(current);save(report);
   runtime.sql(item.bytes,{migration:true});current.completed=true;save(report);
   if(item.path===VAULT_PROVENANCE_PATH){
    report.phase='local_vault_provenance_after';save(report);runtime.verify();
    localVaultReceipt=readVaultMetadata(runtime.sql(Buffer.from(VAULT_METADATA_PROBE)),{after:true});
    report.local_vault={...report.local_vault,after_count:1,metadata_exact:true,provenance_verified:true};save(report);report.phase='integral_replay';
   }
   if(item.path===BASELINE_PATH){
    report.phase='baseline_service_default_restore_verification';save(report);runtime.verify();
    const restored=runtime.probeBaselineServiceDefault();report.baseline_service_default_after_baseline=projectBaselineServiceDefault(restored);save(report);
    checkBaselineServiceDefault(restored,{phase:'restored',before:serviceBefore});report.baseline_service_default_restored=true;save(report);report.phase='integral_replay';
   }
  }
  report.phase='stop_local_crons';save(report);
  const crons=JSON.parse(runtime.sql(Buffer.from(STOP_CRONS)));
  if(Object.keys(crons).join()!=='locally_disabled_jobs'||!Number.isSafeInteger(crons.locally_disabled_jobs)||crons.locally_disabled_jobs<0)refuse('QUALIFICATION_CRON_REPORT');
  report.locally_disabled_jobs=crons.locally_disabled_jobs;
  report.phase='local_vault_cleanup';save(report);runtime.verify();
  const vaultCleanup=JSON.parse(runtime.sql(Buffer.from(localVaultCleanupSQL(localVaultReceipt))));
  if(!isDeepStrictEqual(vaultCleanup,{removed_count:1,after_cleanup_count:0}))refuse('QUALIFICATION_LOCAL_VAULT_REFUSED');
  report.local_vault={...report.local_vault,removed_count:1,after_cleanup_count:0};save(report);
  report.phase='canonical_preflight';save(report);
  report.extension_checks=exactExtensions(requirements,JSON.parse(runtime.sql(extensionSQL)));
  runtime.verify();report.before=projectQuiescence(runtime.sql(Buffer.from(QUIESCENCE)));save(report);zeros(JSON.stringify(report.before));
  report.phase='pinned_synthetic_test';save(report);
  runtime.sql(evidence.test.bytes,{test:true});report.canonical_test_passed=true;
  report.phase='rollback_verification';save(report);
  runtime.verify();report.after=projectQuiescence(runtime.sql(Buffer.from(QUIESCENCE)));save(report);zeros(JSON.stringify(report.after));
  report.rollback_verified=true;report.phase='complete';report.result='ISOLATED_IMPORT_AND_SQL_TEST_PASSED';save(report);
  return report;
 }catch(error){report.failure=safeFailure(error);save(report);throw error;}
}
export function main(args,env=process.env){
 const [command,...rest]=args;if(!['identity','run'].includes(command))refuse('QUALIFICATION_IDENTITY_REFUSED');
 const evidence=source(env);
 if(command==='identity'&&rest.length===0)return {product_sha:evidence.product_sha,harness_sha:evidence.harness_sha,run:evidence.run,migration_count:evidence.migrations.length,canonical_test_sha256:evidence.test.sha256};
 const [privateDir,proofDir]=rest;
 if(command!=='run'||rest.length!==2||privateDir!=='/tmp/jolene-restore-private-'+env.GITHUB_RUN_ID+'-'+env.GITHUB_RUN_ATTEMPT||proofDir!=='/tmp/jolene-restore-proof-'+env.GITHUB_RUN_ID+'-'+env.GITHUB_RUN_ATTEMPT)refuse('QUALIFICATION_REPORT_PATH');
 const target=resolve(proofDir,'import-qualification.json');
 const save=report=>{const tmp=target+'.writing';writeFileSync(tmp,JSON.stringify(report,null,2)+'\n',{mode:0o600});renameSync(tmp,target);};
 const runtime=qualifiedSession(privateDir);
 return qualify(evidence,runtime,readFileSync(resolve(HERE,'preflight-extensions.sql')),JSON.parse(readFileSync(resolve(HERE,'../export/scope.json'))).extensions,save);
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{const result=main(process.argv.slice(2));console.log(JSON.stringify({result:result.result??'SOURCE_IDENTITY_VERIFIED',...('phase' in result?{phase:result.phase,product_sha:result.product_sha,harness_sha:result.harness_sha,canonical_test_passed:result.canonical_test_passed,rollback_verified:result.rollback_verified}:result)}));}
 catch(error){console.error(JSON.stringify(safeFailure(error)));process.exitCode=1;}
}

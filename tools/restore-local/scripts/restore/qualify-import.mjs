#!/usr/bin/env node
// Temporary, dispatch-only qualification. No cloud credentials, API, CLI or fixture service.
import {readFileSync,writeFileSync,renameSync,lstatSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {qualifiedSession,QUALIFICATION_DB} from './bootstrap.mjs';
import {compareRequired} from './extensions.mjs';
export const QUALIFICATION_BRANCH='ci/qualification-pg17-candidatures-20261002';
export const PRODUCT_SHA='7bec1138ae79131ab940137369e1706ebf0ec860';
export const TEST_PATH='tests/security/candidatures-multi-etablissements.test.sql';
export const SCAFFOLD_PATHS=[
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
 const items=[...names,TEST_PATH].map(path=>{
  const bytes=readCanonical(path),current=readCurrent(path);
  if(!Buffer.isBuffer(bytes)||!Buffer.isBuffer(current)||!bytes.equals(current)||bytes.length===0)refuse('CANONICAL_BYTES_CHANGED');
  // Whole files are replayed, never filtered, wrapped or normalized.
  return {path,sha256:hash(bytes),bytes};
 });
 return {migrations:items.slice(0,-1),test:items.at(-1)};
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
export const STOP_CRONS=LOCAL_GUARD+`
WITH changed AS (UPDATE cron.job SET active=false WHERE active RETURNING 1)
SELECT jsonb_build_object('locally_disabled_jobs',count(*)) FROM changed;`;
export const QUIESCENCE=LOCAL_GUARD+`
SELECT jsonb_build_object(
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
 'vault_secrets',(SELECT count(*) FROM vault.secrets));`;
const ZERO_KEYS=['auth_users','auth_sessions','soignants','etablissements','missions','candidatures','members','externalisations','storage_objects','active_crons','cron_executions','http_queue','http_responses','vault_secrets'];
export function zeros(text){
 const value=JSON.parse(text);if(Object.keys(value).sort().join()!==[...ZERO_KEYS].sort().join()||Object.values(value).some(x=>x!==0))refuse('QUALIFICATION_NONEMPTY');return value;
}
export function exactExtensions(requirements,runtime){
 const result=compareRequired(requirements,runtime);
 if(!result.declarations_compatible||result.checks.some(c=>c.installed_version_matches!==true||c.installed_schema_matches!==true))refuse('EXTENSION_EXACT_INSTALL_REQUIRED');
 return result.checks;
}
export function safeFailure(error){
 const codes=['QUALIFICATION_IDENTITY_REFUSED','SOURCE_GIT_REFUSED','MIGRATION_ORDER_REFUSED','CANONICAL_BYTES_CHANGED','CANONICAL_FILE_TYPE','QUALIFICATION_SQL_FAILED','QUALIFICATION_NONEMPTY','EXTENSION_EXACT_INSTALL_REQUIRED','QUALIFICATION_RUNTIME_RUN_CHANGED','QUALIFICATION_REPORT_PATH','QUALIFICATION_CRON_REPORT','QUALIFICATION_VERCEL_REFUSED'];
 const code=codes.includes(error?.message)?error.message:'QUALIFICATION_REFUSED';
 const diagnostic=error?.diagnostic;
 return {code,...(code==='QUALIFICATION_SQL_FAILED'?{sqlstate:/^[0-9A-Z]{5}$/.test(diagnostic?.sqlstate??'')?diagnostic.sqlstate:null,
  input_line:Number.isSafeInteger(diagnostic?.line)&&diagnostic.line>0?diagnostic.line:null,
  assertion:/^CAND_MULTI_[A-Z_]{1,80}$/.test(diagnostic?.assertion??'')?diagnostic.assertion:null}:{})};
}
export function qualify(evidence,runtime,extensionSQL,requirements,save){
 const report={result:'IMPORT_NOT_PROVEN',product_sha:evidence.product_sha,harness_sha:evidence.harness_sha,run:evidence.run,
  canonical_test_sha256:evidence.test.sha256,migration_count:evidence.migrations.length,
  ordered_manifest_sha256:hash(JSON.stringify(evidence.migrations.map(({path,sha256})=>({path,sha256})))),
  migrations:[],phase:'local_preflight',canonical_test_passed:false,rollback_verified:false,cloud_contacted:false};
 save(report);
 try{
  if(runtime.run!==evidence.run)refuse('QUALIFICATION_RUNTIME_RUN_CHANGED');
  runtime.verify();runtime.sql(Buffer.from(LOCAL_GUARD));
  report.phase='integral_replay';
  for(const item of evidence.migrations){
   const current={path:item.path,sha256:item.sha256,completed:false};report.migrations.push(current);save(report);
   runtime.sql(item.bytes);current.completed=true;save(report);
  }
  report.phase='stop_local_crons';save(report);
  const crons=JSON.parse(runtime.sql(Buffer.from(STOP_CRONS)));
  if(Object.keys(crons).join()!=='locally_disabled_jobs'||!Number.isSafeInteger(crons.locally_disabled_jobs)||crons.locally_disabled_jobs<0)refuse('QUALIFICATION_CRON_REPORT');
  report.locally_disabled_jobs=crons.locally_disabled_jobs;
  report.phase='canonical_preflight';save(report);
  report.extension_checks=exactExtensions(requirements,JSON.parse(runtime.sql(extensionSQL)));
  runtime.verify();report.before=zeros(runtime.sql(Buffer.from(QUIESCENCE)));save(report);
  report.phase='unchanged_canonical_test';save(report);
  runtime.sql(evidence.test.bytes,{test:true});report.canonical_test_passed=true;
  report.phase='rollback_verification';save(report);
  runtime.verify();report.after=zeros(runtime.sql(Buffer.from(QUIESCENCE)));
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

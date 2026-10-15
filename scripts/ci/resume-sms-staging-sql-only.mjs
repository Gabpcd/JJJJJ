// Separate recovery after deployment of exact send-sms v24. No deploy command,
// allocator, activation, credentials change, business RPC or provider endpoint.
import {readFileSync,writeFileSync,renameSync,mkdirSync,openSync,fsyncSync,closeSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,REPOSITORY,FUNCTION,CONTRACT,ASSET_PATHS,digest,canonical,checkContract,
 checkContext,checkAssets,checkBody,checkSnapshot,closureDigest,readResponse,readLocal} from './install-sms-staging-closed.mjs';
import {functionsMetadata} from './refresh-generate-invoice-staging.mjs';
import {snapshotSql} from './install-sms-staging-closed-sql.mjs';
import {transactionSqlOnly} from './resume-sms-staging-sql-only-sql.mjs';

export const RESUME_CONTRACT='scripts/ci/resume-sms-staging-sql-only.contract.json';
export const RECOVERY_WORKFLOW='.github/workflows/sms-install-sql-only-pg17.yml';
export const RECOVERY_ARTIFACT='sms-install-sql-only-pg17-public';
export const OPERATOR_PATHS=Object.freeze([...ASSET_PATHS,
 CONTRACT,'scripts/ci/install-sms-staging-closed.mjs','scripts/ci/install-sms-staging-closed-sql.mjs',
 'scripts/ci/connect-staging-closed-sql.mjs','scripts/ci/refresh-generate-invoice-staging.mjs',
 'scripts/ci/resume-sms-staging-sql-only.mjs','scripts/ci/resume-sms-staging-sql-only-sql.mjs',
 'scripts/ci/sms-install-sql-only-pg17.py','tests/python/test_sms_install_sql_only_witness.py',
 'tests/node/resume-sms-staging-sql-only.node.mjs','tests/node/resume-sms-staging-sql-only-sql.node.mjs',
 RECOVERY_WORKFLOW,'.github/workflows/resume-sms-staging-sql-only.yml'].sort());
const API=`https://api.supabase.com/v1/projects/${PROJECT}`;
const GH=`https://api.github.com/repos/${REPOSITORY}`;
const same=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const exact=(v,k)=>v&&typeof v==='object'&&!Array.isArray(v)&&same(Object.keys(v).sort(),[...k].sort());
const hash=(v,n=64)=>typeof v==='string'&&new RegExp(`^[a-f0-9]{${n}}$`).test(v)&&!/^0+$/.test(v);
const id=v=>typeof v==='string'&&/^[1-9][0-9]{0,19}$/.test(v);
class Refusal extends Error{constructor(code){super(code);this.code=code;}}
const fail=code=>{throw new Refusal(code);};

export function checkResumeContract(c,historical,requireReady=true){
 checkContract(historical);
 if(!exact(c,['schemaVersion','ready','projectRef','installationOnly','capabilityEnabled','deploymentAllowed',
   'failedRunId','deployedSourceSha','historicalManifestSha256','cronJobControl','edge','recoveryCi','manifestSha256'])
   ||c.schemaVersion!==1||typeof c.ready!=='boolean'||c.projectRef!==PROJECT||c.installationOnly!==true
   ||c.capabilityEnabled!==false||c.deploymentAllowed!==false||c.failedRunId!=='38629072392'
   ||c.deployedSourceSha!=='8cc26771120fa962af431af1c0dc45ac82d8c500'
   ||c.historicalManifestSha256!==historical.manifestSha256
   ||c.cronJobControl!=='OBSERVATION_BEFORE_AFTER_ACCESS_SHARE_ONLY')fail('RESUME_MANIFEST_REFUSED');
 const {manifestSha256,...payload}=c;
 if(!hash(manifestSha256)||digest(JSON.stringify(canonical(payload)))!==manifestSha256)fail('RESUME_MANIFEST_DIGEST_REFUSED');
 const e=c.edge;
 if(!exact(e,['id','version','bundleSha256','metadataSha256','closureSha256','files'])
   ||e.id!==historical.edgeBefore.id||e.version!==24
   ||![e.bundleSha256,e.metadataSha256,e.closureSha256].every(x=>hash(x))
   ||!exact(e.files,ASSET_PATHS.filter(p=>p.startsWith('supabase/functions/')))
   ||Object.values(e.files).some(x=>!hash(x)))fail('RESUME_EDGE_PIN_REFUSED');
 const ci=c.recoveryCi;
 if(ci!==null&&(!exact(ci,['runId','jobId','headSha','executedSha','artifactId','artifactZipSha256','artifactName','workflow'])
   ||![ci.runId,ci.jobId,ci.artifactId].every(id)||![ci.headSha,ci.executedSha].every(x=>hash(x,40))
   ||!hash(ci.artifactZipSha256)||ci.artifactName!==RECOVERY_ARTIFACT||ci.workflow!==RECOVERY_WORKFLOW))fail('RESUME_CI_PIN_REFUSED');
 if(requireReady&&(c.ready!==true||ci===null))fail('RESUME_NOT_REVIEWED');
 return c;
}

export function checkResumeMetadata(raw,c){
 const rows=Array.isArray(raw)?raw:raw?.functions;
 let normalized;try{normalized=functionsMetadata(rows);}catch{fail('RESUME_EDGE_METADATA_REFUSED');}
 const target=rows.find(x=>x.slug===FUNCTION),e=c.edge;
 if(!target||target.id!==e.id||target.status!=='ACTIVE'||target.version!==24
   ||target.verify_jwt!==false||target.import_map!==false||target.import_map_path!=null
   ||target.ezbr_sha256!==e.bundleSha256||digest(JSON.stringify(canonical(target)))!==e.metadataSha256)fail('RESUME_EDGE_CHANGED');
 return normalized;
}

export async function resumeSqlOnly({env,local,historical,contract:c,fetchImpl=fetch,checkpoint=()=>{}}){
 const r={schemaVersion:1,status:'failed',phase:'context',code:null,projectRef:PROJECT,sourceSha:null,manifestSha256:null,
  failedRunId:'38629072392',deploymentAttempted:false,deploymentConfirmed:false,existingDeploymentVerified:false,
  dryRunAttempted:false,dryRunVerified:false,commitAttempted:false,commitConfirmed:false,closedStateVerified:false,
  businessRowsUnchanged:false,businessComparisonScope:'CURRENT_RECOVERY_ONLY',beforeInvariant:null,beforeTargets:null,
  cronJobControl:'OBSERVATION_BEFORE_AFTER_ACCESS_SHARE_ONLY',providerInvoked:false,authCreated:false,
  capabilityAllocated:false,credentialsChanged:false,httpFailure:null};
 const save=()=>{try{checkpoint(structuredClone(r));}catch{fail('CHECKPOINT_FAILED');}};
 let mutationStarted=false;
 const request=async(url,label,body,management=false,files=false)=>{
  try{
   const response=await fetchImpl(url,{method:body===undefined?'GET':'POST',redirect:'error',signal:AbortSignal.timeout(110000),
    headers:management?{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json',...(files?{Accept:'multipart/form-data'}:{})}:
     {Authorization:`Bearer ${env.GITHUB_TOKEN}`,Accept:'application/vnd.github+json','User-Agent':'Jolene-sql-only-sms-recovery'},
    ...(body===undefined?{}:{body:JSON.stringify(body)})});
   if(!response.ok){r.httpFailure={endpoint:label,status:Number.isInteger(response.status)&&response.status>=100&&response.status<=599?response.status:null};fail('HTTP_REFUSED');}
   return await readResponse(response,files,`${PROJECT}_${c.edge.id}_24`);
  }catch(e){if(e instanceof Refusal)throw e;fail('TRANSPORT_OR_JSON_UNCERTAIN');}
 };
 const query=(sql,label)=>request(`${API}/database/query`,label,{query:sql,read_only:false},true);
 const main=async()=>{const x=await request(`${GH}/git/ref/heads/main`,'main');
  if(x?.ref!=='refs/heads/main'||x.object?.type!=='commit'||x.object.sha!==env.GITHUB_SHA)fail('MAIN_MOVED');};
 const edge=async()=>checkResumeMetadata(await request(`${API}/functions`,'edge_catalogue',undefined,true),c);
 const body=async()=>{
  const actual=checkBody(await request(`${API}/functions/${FUNCTION}/body`,'edge_body',undefined,true,true),new Map(Object.entries(c.edge.files)));
  if(closureDigest(actual)!==c.edge.closureSha256)fail('RESUME_EDGE_CLOSURE_REFUSED');
 };
 try{
  checkResumeContract(c,historical);checkContext(env,local,historical);
  const {rendered,closure}=checkAssets(historical,local);
  if(!same(Object.fromEntries([...closure].map(([p,v])=>[p,digest(v)])),c.edge.files)
    ||closureDigest(closure)!==c.edge.closureSha256)fail('RESUME_LOCAL_EDGE_REFUSED');
  if(!env.STAGING_SUPABASE_ACCESS_TOKEN?.trim()||!env.GITHUB_TOKEN?.trim())fail('TOKENS_REQUIRED');
  if(!exact(local.operatorBlobs,OPERATOR_PATHS)||Object.values(local.operatorBlobs).some(x=>!hash(x,40)))fail('RESUME_OPERATOR_BLOBS_REFUSED');
  r.sourceSha=env.GITHUB_SHA;r.manifestSha256=c.manifestSha256;save();
  r.phase='provenance';await main();
  const proof=c.recoveryCi;
  const run=await request(`${GH}/actions/runs/${proof.runId}`,'recovery_ci_run');
  if(String(run.id)!==proof.runId||run.head_sha!==proof.headSha||run.event!=='pull_request'||run.run_attempt!==1
    ||run.path!==RECOVERY_WORKFLOW||run.status!=='completed'||run.conclusion!=='success'
    ||run.repository?.full_name!==REPOSITORY||run.head_repository?.full_name!==REPOSITORY)fail('RESUME_CI_RUN_REFUSED');
  const job=await request(`${GH}/actions/jobs/${proof.jobId}`,'recovery_ci_job');
  if(String(job.id)!==proof.jobId||String(job.run_id)!==proof.runId||job.head_sha!==proof.headSha
    ||job.status!=='completed'||job.conclusion!=='success'||job.name!=='Reprise SMS SQL-only — PostgreSQL 17 éphémère')fail('RESUME_CI_JOB_REFUSED');
  const merge=await request(`${GH}/git/commits/${proof.executedSha}`,'recovery_ci_commit');
  if(merge.sha!==proof.executedSha||!hash(merge.tree?.sha,40)||merge.parents?.length!==2
    ||!merge.parents.some(x=>x.sha===proof.headSha))fail('RESUME_CI_COMMIT_REFUSED');
  const tree=await request(`${GH}/git/trees/${merge.tree.sha}?recursive=1`,'recovery_ci_tree');
  if(tree.sha!==merge.tree.sha||tree.truncated!==false||!Array.isArray(tree.tree))fail('RESUME_CI_TREE_REFUSED');
  for(const path of OPERATOR_PATHS){const items=tree.tree.filter(x=>x.path===path);
   if(items.length!==1||items[0].type!=='blob'||items[0].mode!=='100644'||items[0].sha!==local.operatorBlobs[path])fail('RESUME_CI_SOURCE_DRIFT');}
  const artifact=await request(`${GH}/actions/artifacts/${proof.artifactId}`,'recovery_ci_artifact');
  if(String(artifact.id)!==proof.artifactId||artifact.name!==RECOVERY_ARTIFACT||artifact.expired!==false
    ||artifact.digest!==`sha256:${proof.artifactZipSha256}`||String(artifact.workflow_run?.id)!==proof.runId
    ||artifact.workflow_run?.head_sha!==proof.headSha)fail('RESUME_CI_ARTIFACT_REFUSED');
  r.phase='identity';const project=await request(API,'project_identity',undefined,true);
  if(project.id!==PROJECT||project.region!=='eu-west-1'||project.status!=='ACTIVE_HEALTHY'
    ||project.database?.host!==`db.${PROJECT}.supabase.co`||project.database?.postgres_engine!=='17')fail('PROJECT_IDENTITY_REFUSED');
  r.phase='baseline';const beforeEdge=await edge();await body();r.existingDeploymentVerified=true;save();
  const before=checkSnapshot(await query(snapshotSql(historical,false),'baseline_readonly'),historical,false);
  r.beforeInvariant=structuredClone(before.invariant);r.beforeTargets=before.targets;save();
  await main();if(!same(await edge(),beforeEdge))fail('RESUME_EDGE_CATALOGUE_DRIFT');
  checkSnapshot(await query(snapshotSql(historical,false),'baseline_readonly'),historical,false,before);
  r.phase='rollback_once';r.status='uncertain';r.dryRunAttempted=true;save();mutationStarted=true;
  const preview=checkSnapshot(await query(transactionSqlOnly(historical,rendered,before,false),'preview_sql'),historical,true,before);
  const restored=checkSnapshot(await query(snapshotSql(historical,false),'restored_readonly'),historical,false,before);
  if(!same(restored,before))fail('ROLLBACK_NOT_CONFIRMED');
  r.dryRunVerified=true;save();await main();
  if(!same(await edge(),beforeEdge))fail('RESUME_EDGE_CATALOGUE_DRIFT');await body();
  r.phase='commit_once';r.commitAttempted=true;save();
  const committed=checkSnapshot(await query(transactionSqlOnly(historical,rendered,before,true),'commit_sql'),historical,true,before);
  if(!same(committed,preview))fail('COMMIT_RESPONSE_MISMATCH');
  r.phase='readback';const final=checkSnapshot(await query(snapshotSql(historical,true),'final_readonly'),historical,true,before);
  if(!same(final,preview))fail('READBACK_MISMATCH');
  if(!same(await edge(),beforeEdge))fail('RESUME_EDGE_CATALOGUE_DRIFT');await body();
  r.commitConfirmed=true;r.closedStateVerified=true;r.businessRowsUnchanged=true;r.status='success';r.phase='complete';save();
 }catch(e){r.code=e instanceof Refusal?e.code:'LOCAL_OR_SQL_REFUSAL';if(mutationStarted)r.status='uncertain';try{save();}catch{r.code='CHECKPOINT_FAILED';}}
 return r;
}

export function readResumeLocal(root,historical){
 const local=readLocal(root,historical);
 const git=args=>execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe'],
  env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'}}).trim();
 local.operatorBlobs=Object.fromEntries(OPERATOR_PATHS.map(p=>[p,git(['rev-parse',`HEAD:${p}`])]));
 return local;
}

export function durableCheckpoint(directory,value){
 const pending=resolve(directory,'result.json.new'),final=resolve(directory,'result.json');
 const fd=openSync(pending,'wx',0o600);
 try{writeFileSync(fd,JSON.stringify(value,null,2)+'\n');fsyncSync(fd);}finally{closeSync(fd);}
 renameSync(pending,final);
 const parent=openSync(directory,'r');try{fsyncSync(parent);}finally{closeSync(parent);}
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 let report;
 try{
  if(process.argv.length!==2)fail('ARGUMENTS_REFUSED');
  const root=process.cwd(),historical=JSON.parse(readFileSync(resolve(root,CONTRACT),'utf8')),
   contract=JSON.parse(readFileSync(resolve(root,RESUME_CONTRACT),'utf8'));
  // Drafts and CI witness pins are checked before credentials or any network.
  checkResumeContract(contract,historical);
  if(!process.env.RUNNER_TEMP||!isAbsolute(process.env.RUNNER_TEMP))fail('REPORT_PATH_REQUIRED');
  const out=resolve(process.env.RUNNER_TEMP,'resume-sms-staging-sql-only');mkdirSync(out,{mode:0o700});
  report=await resumeSqlOnly({env:process.env,local:readResumeLocal(root,historical),historical,contract,
   checkpoint:value=>durableCheckpoint(out,value)});
 }catch(e){report={schemaVersion:1,status:'failed',code:e instanceof Refusal?e.code:'LOCAL_REFUSAL',deploymentAttempted:false,providerInvoked:false};}
 console.log(JSON.stringify(report));if(report.status!=='success')process.exitCode=1;
}

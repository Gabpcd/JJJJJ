// Manual, closed staging installation. No allocator, credentials or business call.
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,renameSync,mkdirSync,lstatSync,existsSync} from 'node:fs';
import {resolve,isAbsolute,posix} from 'node:path';
import {fileURLToPath} from 'node:url';
import {renderSignatureSmsStaging} from './sms-signature-staging-render.mjs';
import {functionsMetadata} from './refresh-generate-invoice-staging.mjs';
import {snapshotSql,transactionSql} from './install-sms-staging-closed-sql.mjs';

export const PROJECT='mejpriaetwgtcstbgfid';
export const REPOSITORY='Gabpcd/JJJJJ';
export const FUNCTION='send-sms';
export const CONTRACT='scripts/ci/install-sms-staging-closed.contract.json';
const API=`https://api.supabase.com/v1/projects/${PROJECT}`;
const GH=`https://api.github.com/repos/${REPOSITORY}`;
const SOURCE='scripts/ci/sms-signature-staging-otp.source.sql';
const SUPPLEMENT='scripts/ci/sms-signature-staging.sql';
const LIMIT=8*1024*1024;
export const digest=(value,algorithm='sha256')=>createHash(algorithm).update(value).digest('hex');
export const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])])):value;
const same=(a,b)=>JSON.stringify(canonical(a))===JSON.stringify(canonical(b));
const hash=(v,n=64)=>typeof v==='string'&&new RegExp(`^[a-f0-9]{${n}}$`).test(v)&&!/^0+$/.test(v);
const id=v=>typeof v==='string'&&/^[1-9][0-9]{0,19}$/.test(v);
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const exact=(v,keys)=>object(v)&&Object.keys(v).sort().join(',')===keys.slice().sort().join(',');
class Refusal extends Error {constructor(code){super(code);this.code=code;}}
const fail=code=>{throw new Refusal(code);};
export const ASSET_PATHS=Object.freeze([
 'supabase/config.toml',
 'supabase/functions/send-sms/index.ts','supabase/functions/_shared/admin-auth.ts','supabase/functions/_shared/cors.ts',
 'supabase/functions/_shared/rate-limit.ts','supabase/functions/_shared/test-account.ts','supabase/functions/_shared/signature-sms-staging-test.ts',
 SOURCE,SUPPLEMENT,'scripts/ci/sms-signature-staging-render.mjs','scripts/ci/sms-signature-staging-pg17.py',
 'scripts/ci/signature-otp-fix-pg17.py','scripts/ci/signature-otp-diagnostic-pg17.py','scripts/ci/recette107-signature-race.py',
 'supabase/schema/public.sql','supabase/migrations/20261004124300_refuser_signature_otp_et_document_incoherents.sql',
 'supabase/migrations/20261006144554_serialiser_renvoi_et_validation_signature.sql',
 'supabase/migrations/20260729121442_securiser_auth_et_crons_critiques.sql',
 'tests/fixtures/sms-signature-staging-pg17.sql','tests/fixtures/signature-otp-catalogue-before.json',
 'tests/fixtures/signature-otp-sender-catalogue-before.json','tests/fixtures/connect-pretransfer-auth-dependencies.json',
 'src/lib/signatureSmsStagingAdmission.ts','src/components/SignerContratOtp.tsx','src/pages/ContratMission.tsx',
 'e2e/helpers/recette-signature-sms-staging.ts','e2e/helpers/recette-complete-mission.ts',
 'e2e/recette-complete-signature-sms-staging.spec.ts','e2e/playwright.recette-complete.config.ts',
 '.github/workflows/signature-otp-pg17.yml','.github/workflows/signature-sms-staging.yml',
].sort());

export function checkContract(c){
 if(!exact(c,['schemaVersion','projectRef','installationOnly','capabilityEnabled','reviewedProductSha','baselineSourceSha','edgeBefore','assets','renderedSha256','beforeRoutines','afterRoutines','ci','manifestSha256'])
   ||c.schemaVersion!==1||c.projectRef!==PROJECT||c.installationOnly!==true||c.capabilityEnabled!==false
   ||!hash(c.reviewedProductSha,40)||!hash(c.baselineSourceSha,40)||!hash(c.renderedSha256))fail('MANIFEST_REFUSED');
 const {manifestSha256,...payload}=c;
 if(!hash(manifestSha256)||digest(JSON.stringify(canonical(payload)))!==manifestSha256)fail('MANIFEST_DIGEST_REFUSED');
 if(!object(c.assets)||!same(Object.keys(c.assets).sort(),ASSET_PATHS)
   ||Object.values(c.assets).some(x=>!exact(x,['sha256','gitBlob'])||!hash(x.sha256)||!hash(x.gitBlob,40)))fail('ASSET_MANIFEST_REFUSED');
 if(!exact(c.edgeBefore,['id','version','verify_jwt','import_map','bundleSha256','metadataSha256','closureSha256','files'])
   ||!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(c.edgeBefore.id??'')
   ||c.edgeBefore.version!==23||c.edgeBefore.verify_jwt!==false||c.edgeBefore.import_map!==false
   ||![c.edgeBefore.bundleSha256,c.edgeBefore.metadataSha256,c.edgeBefore.closureSha256].every(v=>hash(v))
   ||!object(c.edgeBefore.files)||Object.keys(c.edgeBefore.files).length!==5||Object.values(c.edgeBefore.files).some(v=>!hash(v)))fail('EDGE_MANIFEST_REFUSED');
 if(!Array.isArray(c.beforeRoutines)||c.beforeRoutines.length!==5||!Array.isArray(c.afterRoutines)||c.afterRoutines.length!==8)fail('SQL_MANIFEST_REFUSED');
 const ci=c.ci;
 if(!exact(ci,['headSha','executedSha','parents','pg','ui'])||ci.headSha!==c.reviewedProductSha||!hash(ci.executedSha,40)
   ||!same(ci.parents,[c.baselineSourceSha,ci.headSha]))fail('CI_MANIFEST_REFUSED');
 if(!exact(ci.pg,['runId','jobIds','workflow','artifactId','artifactName','artifactZipSha256','casesPassed','renderedSha256'])
   ||!id(ci.pg.runId)||!id(ci.pg.artifactId)||!Array.isArray(ci.pg.jobIds)||ci.pg.jobIds.length!==1||!id(ci.pg.jobIds[0])
   ||ci.pg.workflow!=='.github/workflows/signature-otp-pg17.yml'||ci.pg.artifactName!=='signature-sms-staging-pg17-public'
   ||!hash(ci.pg.artifactZipSha256)||ci.pg.casesPassed!==58||ci.pg.renderedSha256!==c.renderedSha256)fail('PG_WITNESS_PIN_REFUSED');
 if(!exact(ci.ui,['runId','jobIds','workflow','passed'])||!id(ci.ui.runId)||ci.ui.workflow!=='.github/workflows/signature-sms-staging.yml'
   ||ci.ui.passed!==80||!Array.isArray(ci.ui.jobIds)||ci.ui.jobIds.length!==5||ci.ui.jobIds.some(x=>!id(x))||new Set(ci.ui.jobIds).size!==5)fail('UI_WITNESS_PIN_REFUSED');
 return c;
}
export function checkContext(env,local,c){
 checkContract(c);
 if(env.GITHUB_ACTIONS!=='true'||env.GITHUB_EVENT_NAME!=='workflow_dispatch'||env.GITHUB_REPOSITORY!==REPOSITORY
   ||env.GITHUB_REF!=='refs/heads/main'||!hash(env.GITHUB_SHA,40)||env.EXPECTED_SHA!==env.GITHUB_SHA
   ||local.sha!==env.GITHUB_SHA||local.clean!==true||!id(env.GITHUB_RUN_ID)||env.GITHUB_RUN_ATTEMPT!=='1')fail('EXACT_TRUSTED_MAIN_REQUIRED');
}
export function sourceClosure(readBlob){
 const files=new Map();
 const visit=path=>{
  if(files.has(path))return;
  if(!/^supabase\/functions\/[a-zA-Z0-9_./-]+\.ts$/.test(path)||path.includes('/../')||files.size>=32)fail('SOURCE_PATH_REFUSED');
  const content=readBlob(path);if(typeof content!=='string'||Buffer.byteLength(content)>LIMIT)fail('SOURCE_SIZE_REFUSED');files.set(path,content);
  for(const match of content.matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s*)["']([^"']+)["']/g)){
   const spec=match[1];if(spec.startsWith('.'))visit(posix.normalize(posix.join(posix.dirname(path),spec)));
   else if(spec!=='npm:@supabase/supabase-js@2.99.2')fail('EXTERNAL_IMPORT_REFUSED');
  }
 };
 visit('supabase/functions/send-sms/index.ts');return files;
}
export const closureDigest=files=>digest(JSON.stringify([...files].sort(([a],[b])=>a.localeCompare(b)).map(([path,content])=>({path,sha256:digest(content)}))));
export function checkAssets(c,local){
 if(!same(Object.keys(local.files).sort(),ASSET_PATHS))fail('LOCAL_ASSET_SET_REFUSED');
 for(const path of ASSET_PATHS)if(digest(local.files[path])!==c.assets[path].sha256||local.blobs[path]!==c.assets[path].gitBlob)fail('LOCAL_ASSET_DRIFT');
 const section=[...local.files['supabase/config.toml'].matchAll(/^\[functions\.send-sms\][ \t]*(?:#[^\n]*)?\r?\n([\s\S]*?)(?=^\[|$(?![\s\S]))/gm)];
 if(section.length!==1||!/^verify_jwt\s*=\s*false$/.test(section[0][1].replace(/#[^\n]*/g,'').trim()))fail('LOCAL_EDGE_CONFIG_REFUSED');
 const rendered=renderSignatureSmsStaging(local.files[SOURCE],local.files[SUPPLEMENT]);
 if(digest(rendered)!==c.renderedSha256)fail('RENDERED_SOURCE_DRIFT');
 const closure=sourceClosure(path=>local.files[path]);
 if(!same([...closure.keys()].sort(),ASSET_PATHS.filter(x=>x.startsWith('supabase/functions/'))))fail('LOCAL_CLOSURE_REFUSED');
 return {rendered,closure};
}
function entrypoint(value,version,c){
 const suffix=`/user_fn_${PROJECT}_${c.edgeBefore.id}_${version}/source/supabase/functions/send-sms/index.ts`;
 if(typeof value!=='string'||value.length>2048||/[\0\r\n?#%\\]/.test(value)||value.split('/').includes('..'))return false;
 const path=value.startsWith('file:///')?value.slice('file://'.length):value;
 return path===`/tmp${suffix}`||path===`/var/tmp${suffix}`;
}
export function checkMetadata(raw,c,after=false,before){
 const rows=Array.isArray(raw)?raw:raw?.functions;
 let normalized;try{normalized=functionsMetadata(rows);}catch{fail('EDGE_METADATA_REFUSED');}
 const target=rows.find(x=>x.slug===FUNCTION),expectedVersion=c.edgeBefore.version+(after?1:0);
 if(!target||target.id!==c.edgeBefore.id||target.status!=='ACTIVE'||target.version!==expectedVersion
   ||target.verify_jwt!==false||target.import_map!==false||target.import_map_path!=null||!entrypoint(target.entrypoint_path,expectedVersion,c)
   ||!hash(target.ezbr_sha256))fail('EDGE_BASELINE_DRIFT');
 if(!after&&(target.ezbr_sha256!==c.edgeBefore.bundleSha256||digest(JSON.stringify(canonical(target)))!==c.edgeBefore.metadataSha256))fail('EDGE_BASELINE_DRIFT');
 if(after&&(target.ezbr_sha256===c.edgeBefore.bundleSha256||!same(normalized.filter(x=>x.slug!==FUNCTION),before.filter(x=>x.slug!==FUNCTION))))fail('EDGE_DEPLOYMENT_NOT_CONFIRMED');
 return normalized;
}
export function checkBody(value,expected){
 const rows=Array.isArray(value)?value:value?.files;
 if(!Array.isArray(rows)||rows.length!==expected.size)fail('EDGE_BODY_REFUSED');
 const actual=new Map();
 for(const row of rows){
  if(!object(row)||typeof row.name!=='string'||typeof row.content!=='string'||Buffer.byteLength(row.content)>LIMIT
    ||/[\0\r\n?#\\]/.test(row.name)||row.name.split('/').includes('..'))fail('EDGE_BODY_REFUSED');
  const suffix=/(?:^|\/)(?:supabase\/)?functions\/(.+)$/.exec(row.name)?.[1];
  const path=suffix?`supabase/functions/${suffix}`:null;
  if(!path||!expected.has(path)||actual.has(path)||digest(row.content)!==expected.get(path))fail('EDGE_SOURCE_DRIFT');actual.set(path,row.content);
 }
 return actual;
}
// Management API bodies are multipart files (the MCP normalizes them to JSON).
// Parse that actual wire format in memory with built-in Node APIs, bounded first.
export async function readResponse(response,files=false){
 const reader=response.body?.getReader();if(!reader)fail('RESPONSE_BODY_REFUSED');
 const chunks=[];let size=0;
 while(true){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>LIMIT){await reader.cancel();fail('RESPONSE_SIZE_REFUSED');}chunks.push(Buffer.from(value));}
 const bytes=Buffer.concat(chunks,size),contentType=response.headers.get('content-type')??'';
 if(files&&/^multipart\/form-data\s*;/i.test(contentType)){
  let form;try{form=await new Response(bytes,{headers:{'content-type':contentType}}).formData();}catch{fail('EDGE_MULTIPART_REFUSED');}
  const result=[];
  for(const [,part] of form){
   if(typeof part==='string'||typeof part.name!=='string'||result.length>=32||part.size>LIMIT)fail('EDGE_MULTIPART_REFUSED');
   let content;try{content=new TextDecoder('utf-8',{fatal:true}).decode(await part.arrayBuffer());}catch{fail('EDGE_MULTIPART_REFUSED');}
   result.push({name:part.name,content});
  }
  if(!result.length)fail('EDGE_MULTIPART_REFUSED');return {files:result};
 }
 try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{fail('RESPONSE_JSON_REFUSED');}
}
export function checkSnapshot(value,c,after,before){
 if(!Array.isArray(value)||value.length!==1||!exact(value[0],['snapshot']))fail('SQL_SNAPSHOT_SHAPE');
 const s=value[0].snapshot;
 if(!exact(s,['quiet','absent','closed','routines','invariant','targets'])||s.quiet!==true||s.absent!==!after||s.closed!==after
   ||!exact(s.invariant,['structure','routines','inventory','registry','rows'])||Object.values(s.invariant).some(x=>!hash(x,32))
   ||!hash(s.targets,32)||!Array.isArray(s.routines))fail('SQL_SNAPSHOT_REFUSED');
 const expected=after?c.afterRoutines:c.beforeRoutines;
 if(s.routines.length!==expected.length)fail('SQL_ROUTINES_DRIFT');
 for(const e of expected){
  const a=s.routines.find(x=>x.signature===e.signature);
  if(!a||!hash(a.definition_md5,32)||!same(Object.fromEntries(Object.entries(a).filter(([k])=>k!=='definition_md5'||Object.hasOwn(e,k))),e))fail('SQL_ROUTINES_DRIFT');
 }
 if(before&&!same(s.invariant,before.invariant))fail('BUSINESS_OR_CATALOGUE_CHANGED');
 return s;
}
export function deployCommand(env,cwd,execute=execFileSync){
 const childEnv={PATH:env.PATH,HOME:env.HOME,CI:'true',NO_COLOR:'1',DO_NOT_TRACK:'1',SUPABASE_ACCESS_TOKEN:env.STAGING_SUPABASE_ACCESS_TOKEN};
 const options={cwd,env:childEnv,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:180000,maxBuffer:LIMIT};
 if(execute('supabase',['--version'],options).trim()!=='2.98.0')fail('CLI_VERSION_REFUSED');
 execute('supabase',['functions','deploy',FUNCTION,'--project-ref',PROJECT,'--use-api','--no-verify-jwt'],options);
}

export async function installClosed({env,local,contract:c,fetchImpl=fetch,deploy=()=>deployCommand(env,process.cwd()),checkpoint=()=>{}}){
 const r={schemaVersion:1,status:'failed',phase:'context',code:null,projectRef:PROJECT,sourceSha:null,manifestSha256:null,
  deploymentAttempted:false,deploymentConfirmed:false,dryRunVerified:false,commitAttempted:false,commitConfirmed:false,
  closedStateVerified:false,businessRowsUnchanged:false,providerInvoked:false,authCreated:false,capabilityAllocated:false,credentialsChanged:false};
 const save=()=>{try{checkpoint(structuredClone(r));}catch{fail('CHECKPOINT_FAILED');}};
 let mutationStarted=false;
 async function request(url,body,management=false,files=false){
  try{
   const response=await fetchImpl(url,{method:body===undefined?'GET':'POST',redirect:'error',signal:AbortSignal.timeout(110000),
    headers:management?{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json',...(files?{Accept:'multipart/form-data'}:{})}:
     {Authorization:`Bearer ${env.GITHUB_TOKEN}`,Accept:'application/vnd.github+json','User-Agent':'Jolene-closed-sms-install'},
    ...(body===undefined?{}:{body:JSON.stringify(body)})});
   if(!response.ok)fail('HTTP_REFUSED');
   return await readResponse(response,files);
  }catch(e){if(e instanceof Refusal)throw e;fail('TRANSPORT_OR_JSON_UNCERTAIN');}
 }
 // Preserve Management's operator role for private/auth catalogues. Read-only
 // snapshots enforce BEGIN READ ONLY, postgres identity and row_security=off.
 const query=sql=>request(`${API}/database/query`,{query:sql,read_only:false},true);
 const main=async()=>{const x=await request(`${GH}/git/ref/heads/main`);if(x?.ref!=='refs/heads/main'||x.object?.type!=='commit'||x.object.sha!==env.GITHUB_SHA)fail('MAIN_MOVED');};
 const body=()=>request(`${API}/functions/${FUNCTION}/body`,undefined,true,true);
 try{
  checkContext(env,local,c);const {rendered,closure}=checkAssets(c,local);
  if(!env.STAGING_SUPABASE_ACCESS_TOKEN?.trim()||!env.GITHUB_TOKEN?.trim())fail('TOKENS_REQUIRED');
  r.sourceSha=env.GITHUB_SHA;r.manifestSha256=c.manifestSha256;save();
  r.phase='provenance';await main();
  const merge=await request(`${GH}/git/commits/${c.ci.executedSha}`);
  if(merge.sha!==c.ci.executedSha||!same(merge.parents?.map(x=>x.sha),c.ci.parents)||!hash(merge.tree?.sha,40))fail('CI_MERGE_PROVENANCE_REFUSED');
  const tree=await request(`${GH}/git/trees/${merge.tree.sha}?recursive=1`);
  if(tree.sha!==merge.tree.sha||tree.truncated!==false||!Array.isArray(tree.tree))fail('CI_TREE_REFUSED');
  for(const path of ASSET_PATHS){const items=tree.tree.filter(x=>x.path===path);if(items.length!==1||items[0].type!=='blob'||items[0].mode!=='100644'||items[0].sha!==c.assets[path].gitBlob)fail('CI_SOURCE_DRIFT');}
  for(const proof of [c.ci.pg,c.ci.ui]){
   const run=await request(`${GH}/actions/runs/${proof.runId}`);
   if(String(run.id)!==proof.runId||run.head_sha!==c.ci.headSha||run.event!=='pull_request'||run.run_attempt!==1||run.path!==proof.workflow
     ||run.status!=='completed'||run.conclusion!=='success'||run.repository?.full_name!==REPOSITORY||run.head_repository?.full_name!==REPOSITORY)fail('CI_RUN_REFUSED');
   for(const jobId of proof.jobIds){const job=await request(`${GH}/actions/jobs/${jobId}`);if(String(job.id)!==jobId||String(job.run_id)!==proof.runId||job.status!=='completed'||job.conclusion!=='success'||job.head_sha!==c.ci.headSha)fail('CI_JOB_REFUSED');}
  }
  const artifact=await request(`${GH}/actions/artifacts/${c.ci.pg.artifactId}`);
  if(String(artifact.id)!==c.ci.pg.artifactId||artifact.name!==c.ci.pg.artifactName||artifact.expired!==false
    ||artifact.digest!==`sha256:${c.ci.pg.artifactZipSha256}`||String(artifact.workflow_run?.id)!==c.ci.pg.runId||artifact.workflow_run?.head_sha!==c.ci.headSha)fail('PG_ARTIFACT_REFUSED');
  r.phase='identity';const project=await request(API,undefined,true);
  if(project.id!==PROJECT||project.region!=='eu-west-1'||project.status!=='ACTIVE_HEALTHY'||project.database?.host!==`db.${PROJECT}.supabase.co`||project.database?.postgres_engine!=='17')fail('PROJECT_IDENTITY_REFUSED');
  r.phase='baseline';const beforeEdge=checkMetadata(await request(`${API}/functions`,undefined,true),c);
  const baselineExpected=new Map(Object.entries(c.edgeBefore.files));
  const live=checkBody(await body(),baselineExpected);if(closureDigest(live)!==c.edgeBefore.closureSha256)fail('EDGE_CLOSURE_DRIFT');
  const before=checkSnapshot(await query(snapshotSql(c,false)),c,false);
  await main();
  if(!same(checkMetadata(await request(`${API}/functions`,undefined,true),c),beforeEdge))fail('EDGE_CATALOGUE_DRIFT');
  checkSnapshot(await query(snapshotSql(c,false)),c,false,before);
  r.phase='deploy_once';save();
  // The version command is checked inside deploy. A lost result is never retried.
  r.status='uncertain';r.deploymentAttempted=true;save();mutationStarted=true;
  try{await deploy();}catch(e){if(e instanceof Refusal&&e.code==='CLI_VERSION_REFUSED'){r.status='failed';r.deploymentAttempted=false;mutationStarted=false;throw e;}fail('DEPLOY_RESULT_UNCERTAIN');}
  r.phase='verify_deployment';const deployed=checkMetadata(await request(`${API}/functions`,undefined,true),c,true,beforeEdge);
  checkBody(await body(),new Map([...closure].map(([p,v])=>[p,digest(v)])));
  r.deploymentConfirmed=true;save();
  r.phase='rollback_once';await main();
  const preview=checkSnapshot(await query(transactionSql(c,rendered,before,false)),c,true,before);
  const restored=checkSnapshot(await query(snapshotSql(c,false)),c,false,before);
  if(!same(restored,before))fail('ROLLBACK_NOT_CONFIRMED');
  r.dryRunVerified=true;save();await main();
  if(!same(checkMetadata(await request(`${API}/functions`,undefined,true),c,true,beforeEdge),deployed))fail('DEPLOYMENT_CHANGED');
  r.phase='commit_once';r.status='uncertain';r.commitAttempted=true;save();
  const committed=checkSnapshot(await query(transactionSql(c,rendered,before,true)),c,true,before);
  if(!same(committed,preview))fail('COMMIT_RESPONSE_MISMATCH');
  r.phase='readback';const final=checkSnapshot(await query(snapshotSql(c,true)),c,true,before);
  if(!same(final,preview))fail('READBACK_MISMATCH');
  if(!same(checkMetadata(await request(`${API}/functions`,undefined,true),c,true,beforeEdge),deployed))fail('DEPLOYMENT_CHANGED');
  r.commitConfirmed=true;r.closedStateVerified=true;r.businessRowsUnchanged=true;r.status='success';r.phase='complete';save();
 }catch(e){r.code=e instanceof Refusal?e.code:'LOCAL_OR_SQL_REFUSAL';if(mutationStarted)r.status='uncertain';try{save();}catch{r.code='CHECKPOINT_FAILED';}}
 return r;
}

const git=(root,args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe'],env:{PATH:process.env.PATH,LC_ALL:'C',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'}}).trim();
export function readLocal(root,c){
 const files={},blobs={};
 for(const path of ASSET_PATHS){const f=resolve(root,path);if(lstatSync(f).isSymbolicLink()||!lstatSync(f).isFile())fail('ASSET_NOT_REGULAR');files[path]=readFileSync(f,'utf8');blobs[path]=git(root,['rev-parse',`HEAD:${path}`]);}
 for(const path of ['supabase/functions/deno.json','supabase/functions/deno.jsonc','supabase/functions/send-sms/deno.json','supabase/functions/send-sms/deno.jsonc'])if(existsSync(resolve(root,path)))fail('UNREVIEWED_DENO_CONFIG');
 return {sha:git(root,['rev-parse','HEAD']),clean:git(root,['status','--porcelain','--untracked-files=all'])==='',files,blobs};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 let report;
 try{
  if(process.argv.length!==2)fail('ARGUMENTS_REFUSED');
  const root=process.cwd(),c=JSON.parse(readFileSync(resolve(root,CONTRACT),'utf8'));
  if(!process.env.RUNNER_TEMP||!isAbsolute(process.env.RUNNER_TEMP))fail('REPORT_PATH_REQUIRED');
  const out=resolve(process.env.RUNNER_TEMP,'install-sms-staging-closed');mkdirSync(out,{recursive:true,mode:0o700});
  report=await installClosed({env:process.env,local:readLocal(root,c),contract:c,checkpoint:value=>{
   writeFileSync(resolve(out,'result.json.tmp'),JSON.stringify(value,null,2)+'\n',{mode:0o600});
   renameSync(resolve(out,'result.json.tmp'),resolve(out,'result.json'));
  }});
 }catch(e){report={schemaVersion:1,status:'failed',code:e instanceof Refusal?e.code:'LOCAL_REFUSAL',providerInvoked:false};}
 console.log(JSON.stringify(report));if(report.status!=='success')process.exitCode=1;
}

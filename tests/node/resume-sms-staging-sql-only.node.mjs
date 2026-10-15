import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,statSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {PROJECT,REPOSITORY,CONTRACT,ASSET_PATHS,Refusal,checkSnapshot,digest,canonical} from '../../scripts/ci/install-sms-staging-closed.mjs';
import {RESUME_CONTRACT,RECOVERY_WORKFLOW,RECOVERY_ARTIFACT,OPERATOR_PATHS,checkResumeContract,resumeSqlOnly,durableCheckpoint}
 from '../../scripts/ci/resume-sms-staging-sql-only.mjs';

const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const historical=JSON.parse(read(CONTRACT)),draft=JSON.parse(read(RESUME_CONTRACT));
const CANARY='PRIVATE_OTP_623019_TOKEN_NEVER_REPORT';
const local={sha:'a'.repeat(40),clean:true,files:Object.fromEntries(ASSET_PATHS.map(p=>[p,read(p)])),
 blobs:Object.fromEntries(ASSET_PATHS.map(p=>[p,historical.assets[p].gitBlob])),
 operatorBlobs:Object.fromEntries(OPERATOR_PATHS.map(p=>[p,digest(p,'sha1')]))};
const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:REPOSITORY,
 GITHUB_REF:'refs/heads/main',GITHUB_SHA:local.sha,EXPECTED_SHA:local.sha,GITHUB_RUN_ID:'123456789',GITHUB_RUN_ATTEMPT:'1',
 STAGING_SUPABASE_ACCESS_TOKEN:'management-'+CANARY,GITHUB_TOKEN:'github-'+CANARY};
const repin=c=>{const {manifestSha256,...payload}=c;c.manifestSha256=digest(JSON.stringify(canonical(payload)));return c;};
function contract(){
 const c=structuredClone(draft);c.ready=true;
 c.recoveryCi={runId:'123',jobId:'456',headSha:'b'.repeat(40),executedSha:'c'.repeat(40),artifactId:'789',
  artifactZipSha256:'d'.repeat(64),artifactName:RECOVERY_ARTIFACT,workflow:RECOVERY_WORKFLOW};
 c.edge.metadataSha256=digest(JSON.stringify(canonical(edgeRows(c)[0])));return repin(c);
}
function edgeRows(c){return [{id:c.edge.id,slug:'send-sms',status:'ACTIVE',version:24,verify_jwt:false,import_map:false,
 import_map_path:null,ezbr_sha256:c.edge.bundleSha256,
 entrypoint_path:`file:///tmp/user_fn_${PROJECT}_${c.edge.id}_24/source/supabase/functions/send-sms/index.ts`,created_at:1700000000000},
 {id:'00000000-0000-4000-8000-000000000002',slug:'generate-invoice',status:'ACTIVE',version:22,verify_jwt:false,ezbr_sha256:'e'.repeat(64)}];}
const response=v=>new Response(JSON.stringify(v),{headers:{'content-type':'application/json'}});
function harness(options={}){
 const c=options.contract??contract(),state={calls:[],reports:[],rollbacks:0,commits:0,reads:0,edgeReads:0,bodyReads:0};
 const invariant=Object.fromEntries(['structure','routines','inventory','registry','rows'].map((k,i)=>[k,String(i+1).repeat(32)]));
 const before={quiet:true,absent:true,closed:false,routines:structuredClone(historical.beforeRoutines),invariant,targets:'6'.repeat(32)};
 const after={quiet:true,absent:false,closed:true,routines:historical.afterRoutines.map(r=>({...r,definition_md5:r.definition_md5??'f'.repeat(32)})),invariant,targets:'7'.repeat(32)};
 const snapshotReply=(s,phase)=>{const rows=[{snapshot:s}];options.snapshotResponse?.(rows,state,phase);return response(rows);};
 const API=`https://api.supabase.com/v1/projects/${PROJECT}`,GH=`https://api.github.com/repos/${REPOSITORY}`;
 const fetchImpl=async(url,request)=>{
  state.calls.push({url,request});assert.equal(request.redirect,'error');assert.ok(request.signal instanceof AbortSignal);
  assert.equal(request.headers.Authorization,`Bearer ${url.startsWith(API)?env.STAGING_SUPABASE_ACCESS_TOKEN:env.GITHUB_TOKEN}`);
  if(options.failure?.(url,request,state))return new Response(CANARY,{status:403});
  if(options.lost?.(url,request,state))throw Error(CANARY);
  if(url===`${GH}/git/ref/heads/main`)return response({ref:'refs/heads/main',object:{type:'commit',sha:env.GITHUB_SHA}});
  const ci=c.recoveryCi;
  if(url===`${GH}/actions/runs/${ci.runId}`)return response({id:Number(ci.runId),head_sha:ci.headSha,event:'pull_request',run_attempt:1,
   path:ci.workflow,status:'completed',conclusion:'success',repository:{full_name:REPOSITORY},head_repository:{full_name:REPOSITORY}});
  if(url===`${GH}/actions/jobs/${ci.jobId}`)return response({id:Number(ci.jobId),run_id:Number(ci.runId),head_sha:ci.headSha,
   name:'Reprise SMS SQL-only — PostgreSQL 17 éphémère',status:'completed',conclusion:'success'});
  if(url===`${GH}/git/commits/${ci.executedSha}`)return response({sha:ci.executedSha,tree:{sha:'8'.repeat(40)},parents:[{sha:ci.headSha},{sha:'9'.repeat(40)}]});
  if(url===`${GH}/git/trees/${'8'.repeat(40)}?recursive=1`){
   const tree=OPERATOR_PATHS.map(path=>({path,type:'blob',mode:'100644',sha:local.operatorBlobs[path]}));options.tree?.(tree);
   return response({sha:'8'.repeat(40),truncated:false,tree});
  }
  if(url===`${GH}/actions/artifacts/${ci.artifactId}`)return response({id:Number(ci.artifactId),name:RECOVERY_ARTIFACT,expired:false,
   digest:'sha256:'+ci.artifactZipSha256,workflow_run:{id:Number(ci.runId),head_sha:ci.headSha}});
  if(url===API)return response({id:PROJECT,region:'eu-west-1',status:'ACTIVE_HEALTHY',database:{host:`db.${PROJECT}.supabase.co`,postgres_engine:'17'}});
  if(url===`${API}/functions`){state.edgeReads++;const rows=edgeRows(c);options.metadata?.(rows,state);return response(rows);}
  if(url===`${API}/functions/send-sms/body`){state.bodyReads++;
   return response({files:Object.keys(c.edge.files).map(p=>({name:p,content:local.files[p]}))});}
  assert.equal(url,`${API}/database/query`);assert.equal(request.method,'POST');
  const payload=JSON.parse(request.body);assert.equal(payload.read_only,false);
  if(payload.query.startsWith('BEGIN READ ONLY;')){state.reads++;
   const s=structuredClone(state.commits?after:before);options.snapshot?.(s,state,'read');return snapshotReply(s,'read');}
  assert.equal(state.reports.at(-1).status,'uncertain');
  assert.equal(state.reports.at(-1).dryRunAttempted,true);
  const isCommit=/COMMIT;$/.test(payload.query);
  if(isCommit){state.commits++;assert.equal(state.reports.at(-1).commitAttempted,true);}else{state.rollbacks++;assert.match(payload.query,/ROLLBACK;$/);}
  assert.ok(state.rollbacks===1&&state.commits<=1);
  assert.match(payload.query,/LOCK TABLE cron\.job IN ACCESS SHARE MODE NOWAIT;/);
  const phase=isCommit?'commit':'preview',s=structuredClone(after);options.snapshot?.(s,state,phase);return snapshotReply(s,phase);
 };
 return {state,contract:c,run:()=>resumeSqlOnly({env:{...env,...options.env},local:{...local,...options.local},historical,
  contract:c,fetchImpl,checkpoint:r=>{state.reports.push(structuredClone(r));if(options.checkpoint?.(r,state))throw Error(CANARY);}})};
}
function noLeak(h,r){assert.ok(!JSON.stringify([r,...h.state.reports]).includes(CANARY));
 assert.ok(!/Bearer|SELECT |CREATE |entrypoint_path|definition_md5/.test(JSON.stringify([r,...h.state.reports])));}

test('real manifest pins six source files; an unreviewed draft refuses before any network',async()=>{
 checkResumeContract(draft,historical,false);
 const unreviewed=repin({...structuredClone(draft),ready:false,recoveryCi:null});
 assert.equal(unreviewed.ready,false);assert.equal(unreviewed.recoveryCi,null);
 const h=harness({contract:unreviewed}),r=await h.run();assert.equal(r.code,'RESUME_NOT_REVIEWED');
 assert.equal(h.state.calls.length,0);assert.equal(h.state.commits,0);noLeak(h,r);
});
test('the versioned manifest can be rearmed with a valid witness without changing operator sources',async()=>{
 const manifestBefore=read(RESUME_CONTRACT),pathsBefore=[...OPERATOR_PATHS];
 const sourcesBefore=Object.fromEntries(OPERATOR_PATHS.map(p=>[p,digest(read(p))]));
 assert.equal(OPERATOR_PATHS.includes(RESUME_CONTRACT),false);
 const rearmed=contract();
 assert.equal(checkResumeContract(rearmed,historical),rearmed);
 const h=harness({contract:rearmed}),r=await h.run();assert.equal(r.status,'success');noLeak(h,r);
 assert.equal(read(RESUME_CONTRACT),manifestBefore);
 assert.deepEqual(OPERATOR_PATHS,pathsBefore);
 assert.deepEqual(Object.fromEntries(OPERATOR_PATHS.map(p=>[p,digest(read(p))])),sourcesBefore);
});
test('SQL-only success observes exact v24 throughout, rollback once, commit once, empty closed readback',async()=>{
 const h=harness(),r=await h.run();assert.equal(r.status,'success');assert.equal(r.code,null);
 assert.equal(h.state.rollbacks,1);assert.equal(h.state.commits,1);assert.equal(h.state.bodyReads,3);
 for(const k of ['existingDeploymentVerified','dryRunVerified','commitConfirmed','closedStateVerified','businessRowsUnchanged'])assert.equal(r[k],true);
 for(const k of ['deploymentAttempted','deploymentConfirmed','providerInvoked','authCreated','capabilityAllocated','credentialsChanged'])assert.equal(r[k],false);
 assert.equal(r.businessComparisonScope,'CURRENT_RECOVERY_ONLY');assert.equal(r.beforeInvariant.rows,'5'.repeat(32));
 assert.equal(r.cronJobControl,'OBSERVATION_BEFORE_AFTER_ACCESS_SHARE_ONLY');
 assert.equal(r.snapshotDiagnostics.length,6);
 assert.deepEqual(r.snapshotDiagnostics.map(d=>d.sequence),[1,2,3,4,5,6]);
 assert.deepEqual(r.snapshotDiagnostics.map(d=>d.phase),['baseline','baseline','rollback_once','rollback_once','commit_once','readback']);
 assert.deepEqual(r.snapshotDiagnostics[0].invariant,r.beforeInvariant);
 assert.ok(h.state.calls.every(x=>x.request.method==='GET'||x.url.endsWith('/database/query')));noLeak(h,r);
});
for(const [key,value] of [['GITHUB_EVENT_NAME','push'],['GITHUB_REF','refs/heads/feature'],['EXPECTED_SHA','b'.repeat(40)],['GITHUB_RUN_ATTEMPT','2']])
 test(`bad trusted dispatch ${key} refuses before network`,async()=>{
  const h=harness({env:{[key]:value}}),r=await h.run();assert.equal(r.code,'EXACT_TRUSTED_MAIN_REQUIRED');assert.equal(h.state.calls.length,0);noLeak(h,r);
 });
test('the exported helper refusal is the class retained by the resume',()=>{
 assert.throws(()=>checkSnapshot([],historical,false),e=>e instanceof Refusal&&e.code==='SQL_SNAPSHOT_SHAPE');
});
for(const [name,change,code,inspect] of [
 ['quiet',s=>{s.quiet=false;},'SQL_SNAPSHOT_REFUSED',d=>assert.equal(d.quiet,false)],
 ['routine metadata',s=>{s.routines[0].acl=[CANARY];},'SQL_ROUTINES_DRIFT',d=>assert.equal(d.routineCount,5)],
 ['business invariant',s=>{s.invariant.rows='f'.repeat(32);},'BUSINESS_OR_CATALOGUE_CHANGED',d=>assert.equal(d.invariant.rows,'f'.repeat(32))],
 ['untrusted snapshot fields',s=>{s.quiet=CANARY;s.invariant.rows=CANARY;s.targets=CANARY;s.extra=CANARY;},'SQL_SNAPSHOT_REFUSED',d=>{
  assert.equal(d.quiet,null);assert.equal(d.invariant.rows,null);assert.equal(d.targets,null);assert.equal(d.snapshotKeysExact,false);
 }],
 ['oversized routine list',s=>{s.routines=Array.from({length:40},()=>({definition_md5:CANARY}));},'SQL_ROUTINES_DRIFT',d=>{
  assert.equal(d.routineCount,32);assert.equal(d.routineCountCapped,true);
 }],
])test(`second baseline ${name} is checkpointed publicly before the imported refusal`,async()=>{
 const h=harness({snapshot:(s,state,phase)=>{if(phase==='read'&&state.reads===2)change(s);}}),r=await h.run();
 assert.equal(r.status,'failed');assert.equal(r.phase,'baseline');assert.equal(r.code,code);
 assert.equal(r.dryRunAttempted,false);assert.equal(r.commitAttempted,false);
 assert.equal(h.state.rollbacks,0);assert.equal(h.state.commits,0);assert.equal(r.snapshotDiagnostics.length,2);
 const saved=h.state.reports.find(x=>x.snapshotDiagnostics.length===2);
 assert.equal(saved.code,null);assert.equal(saved.dryRunAttempted,false);inspect(saved.snapshotDiagnostics[1]);noLeak(h,r);
});
for(const [name,change,count,capped] of [
 ['empty response',rows=>rows.splice(0),0,false],
 ['duplicate response',rows=>rows.push(rows[0],rows[0]),2,true],
 ['extra envelope key',rows=>{rows[0].extra=CANARY;},1,false],
])test(`second baseline ${name} keeps bounded shape diagnostics before refusal`,async()=>{
 const h=harness({snapshotResponse:(rows,state,phase)=>{if(phase==='read'&&state.reads===2)change(rows);}}),r=await h.run();
 assert.equal(r.code,'SQL_SNAPSHOT_SHAPE');assert.equal(r.dryRunAttempted,false);assert.equal(h.state.rollbacks,0);
 const saved=h.state.reports.find(x=>x.snapshotDiagnostics.length===2),d=saved.snapshotDiagnostics[1];
 assert.equal(saved.code,null);assert.equal(d.responseRowCount,count);assert.equal(d.responseRowCountCapped,capped);
 assert.equal(d.envelopeExact,false);noLeak(h,r);
});
test('failure to checkpoint the second baseline diagnostic prevents all SQL writes',async()=>{
 const h=harness({checkpoint:r=>r.snapshotDiagnostics.length===2}),r=await h.run();
 assert.equal(r.code,'CHECKPOINT_FAILED');assert.equal(r.dryRunAttempted,false);assert.equal(r.commitAttempted,false);
 assert.equal(h.state.rollbacks,0);assert.equal(h.state.commits,0);noLeak(h,r);
});
test('CI source drift, wrong v24 metadata and dirty checkout refuse before any SQL write',async()=>{
 for(const options of [{tree:t=>t[0].sha='f'.repeat(40)},{metadata:r=>r[0].version=25},{local:{clean:false}}]){
  const h=harness(options),r=await h.run();assert.notEqual(r.status,'success');assert.equal(h.state.rollbacks,0);assert.equal(h.state.commits,0);noLeak(h,r);
 }
});
test('unknown response body stays private while status and closed endpoint label are retained',async()=>{
 const h=harness({failure:u=>u.endsWith('/database/query')}),r=await h.run();assert.equal(r.status,'failed');
 assert.equal(r.code,'HTTP_REFUSED');assert.deepEqual(r.httpFailure,{endpoint:'baseline_readonly',status:403});noLeak(h,r);
});
test('lost dry run result is uncertain, never replayed and never committed',async()=>{
 const h=harness({lost:(u,q)=>u.endsWith('/database/query')&&JSON.parse(q.body).query.startsWith('BEGIN;')}),r=await h.run();
 assert.equal(r.status,'uncertain');assert.equal(r.dryRunAttempted,true);assert.equal(r.commitAttempted,false);
 assert.equal(h.state.calls.filter(x=>x.url.endsWith('/database/query')&&JSON.parse(x.request.body).query.startsWith('BEGIN;')).length,1);noLeak(h,r);
});
test('bad rollback readback and catalogue drift after preview prevent commit',async()=>{
 for(const options of [{snapshot:(s,state,phase)=>{if(phase==='read'&&state.rollbacks)s.invariant.rows='f'.repeat(32);}},
  {metadata:(rows,state)=>{if(state.rollbacks)rows[1].version++;}}]){
  const h=harness(options),r=await h.run();assert.equal(r.status,'uncertain');assert.equal(h.state.rollbacks,1);assert.equal(h.state.commits,0);noLeak(h,r);
 }
});
test('checkpoint failure before preview prevents SQL submission',async()=>{
 const h=harness({checkpoint:r=>r.dryRunAttempted}),r=await h.run();assert.equal(r.code,'CHECKPOINT_FAILED');
 assert.equal(h.state.rollbacks,0);assert.equal(h.state.commits,0);noLeak(h,r);
});
test('journal uses private files, durable replacement, and does not retain stale pending content',()=>{
 const directory=mkdtempSync(join(tmpdir(),'sms-resume-journal-'));
 try{durableCheckpoint(directory,{phase:'before'});durableCheckpoint(directory,{phase:'after'});
  assert.deepEqual(JSON.parse(readFileSync(join(directory,'result.json'),'utf8')),{phase:'after'});
  assert.equal(statSync(join(directory,'result.json')).mode&0o777,0o600);
  assert.throws(()=>readFileSync(join(directory,'result.json.new')),/ENOENT/);
 }finally{rmSync(directory,{recursive:true,force:true});}
});

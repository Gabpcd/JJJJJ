import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {PROJECT,REPOSITORY,FUNCTION,CONTRACT,ASSET_PATHS,digest,canonical,closureDigest,
 checkContract,checkAssets,checkMetadata,checkSnapshot,checkBody,sourceClosure,readLocal,readResponse,deployCommand,installClosed} from '../../scripts/ci/install-sms-staging-closed.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const versioned=JSON.parse(readFileSync(new URL('../../'+CONTRACT,import.meta.url),'utf8'));
// Exercise current assets with a synthetic in-memory contract. The versioned
// historical contract is never repinned and must still refuse their drift.
const actual=readLocal(root,versioned);
const local={...actual,clean:true};
const baselineFiles=new Map(Object.keys(versioned.edgeBefore.files).map(path=>[path,
 execFileSync('git',['-C',root,'show',`${versioned.baselineSourceSha}:${path}`],{encoding:'utf8',stdio:['ignore','pipe','pipe']})]));
const API=`https://api.supabase.com/v1/projects/${PROJECT}`;
const GH=`https://api.github.com/repos/${REPOSITORY}`;
const CANARY='private-canary-never-report-SMS-OTP-623019';
const env={GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REPOSITORY:REPOSITORY,
 GITHUB_REF:'refs/heads/main',GITHUB_SHA:actual.sha,EXPECTED_SHA:actual.sha,GITHUB_RUN_ID:'123456789',GITHUB_RUN_ATTEMPT:'1',
 STAGING_SUPABASE_ACCESS_TOKEN:'management-'+CANARY,GITHUB_TOKEN:'github-'+CANARY,PATH:'/synthetic/bin',HOME:'/synthetic/home'};
const repin=c=>{
 const {manifestSha256,...payload}=c;
 c.manifestSha256=digest(JSON.stringify(canonical(payload)));return c;
};
function edgeRows(c,after=false){
 const version=c.edgeBefore.version+(after?1:0);
 return [{id:c.edgeBefore.id,slug:FUNCTION,status:'ACTIVE',version,verify_jwt:false,import_map:false,import_map_path:null,
  ezbr_sha256:after?'e'.repeat(64):c.edgeBefore.bundleSha256,
  entrypoint_path:`/tmp/user_fn_${PROJECT}_${c.edgeBefore.id}_${version}/source/supabase/functions/send-sms/index.ts`,
  created_at:1700000000000},
 {id:'00000000-0000-4000-8000-000000000002',slug:'generate-invoice',status:'ACTIVE',version:22,verify_jwt:false,
  ezbr_sha256:'d'.repeat(64),entrypoint_path:'file:///synthetic/invoice/index.ts',opaque_field:'unchanged'}];
}
function contract(){
 const c=structuredClone(versioned);
 c.assets=Object.fromEntries(ASSET_PATHS.map(path=>[path,{sha256:digest(local.files[path]),gitBlob:local.blobs[path]}]));
 // Production baseline metadata is deliberately not persisted in this test.
 // A synthetic catalogue keeps its own authenticated, complete metadata pin.
 c.edgeBefore.metadataSha256=digest(JSON.stringify(canonical(edgeRows(c)[0])));
 return repin(c);
}
const closure=checkAssets(contract(),local).closure;
function snapshots(c){
 const invariant=Object.fromEntries(['structure','routines','inventory','registry','rows'].map((k,i)=>[k,String(i+1).repeat(32)]));
 return {before:{quiet:true,absent:true,closed:false,routines:structuredClone(c.beforeRoutines),invariant,targets:'6'.repeat(32)},
  after:{quiet:true,absent:false,closed:true,routines:c.afterRoutines.map(r=>({...structuredClone(r),
   definition_md5:r.definition_md5??digest('synthetic-definition:'+r.signature,'md5')})),invariant:structuredClone(invariant),targets:'7'.repeat(32)}};
}
const response=value=>new Response(JSON.stringify(value),{headers:{'content-type':'application/json'}});
function harness(options={}){
 const c=options.contract??contract(),s=snapshots(c);
 const state={calls:[],events:[],reports:[],deploys:0,rollbacks:0,commits:0,reads:0,edgeReads:0,bodyReads:0,mainReads:0};
 const edit=(name,value,info={})=>{const copy=structuredClone(value);options[name]?.(copy,{...info,state,contract:c});return copy;};
 const fetchImpl=async(url,request)=>{
  state.calls.push({url,request});
  assert.equal(request.redirect,'error');assert.ok(request.signal instanceof AbortSignal);
  assert.ok(url.startsWith(GH+'/')||url===API||url.startsWith(API+'/'),'only GitHub and this staging Management API');
  assert.equal(request.headers.Authorization,`Bearer ${url.startsWith(API)?env.STAGING_SUPABASE_ACCESS_TOKEN:env.GITHUB_TOKEN}`);
  if(options.transport?.(url,request,state))throw Error(CANARY);
  if(url===`${GH}/git/ref/heads/main`){
   state.events.push('main');state.mainReads++;
   return response(edit('main',{ref:'refs/heads/main',object:{type:'commit',sha:env.GITHUB_SHA}},{read:state.mainReads}));
  }
  if(url===`${GH}/git/commits/${c.ci.executedSha}`)
   return response(edit('merge',{sha:c.ci.executedSha,parents:c.ci.parents.map(sha=>({sha})),tree:{sha:'8'.repeat(40)}}));
  if(url===`${GH}/git/trees/${'8'.repeat(40)}?recursive=1`)
   return response(edit('tree',{sha:'8'.repeat(40),truncated:false,tree:ASSET_PATHS.map(path=>({path,type:'blob',mode:'100644',sha:c.assets[path].gitBlob}))}));
  for(const proof of [c.ci.pg,c.ci.ui]){
   if(url===`${GH}/actions/runs/${proof.runId}`)
    return response(edit('run',{id:Number(proof.runId),head_sha:c.ci.headSha,event:'pull_request',run_attempt:1,path:proof.workflow,
     status:'completed',conclusion:'success',repository:{full_name:REPOSITORY},head_repository:{full_name:REPOSITORY}},{proof}));
   for(const jobId of proof.jobIds)if(url===`${GH}/actions/jobs/${jobId}`)
    return response(edit('job',{id:Number(jobId),run_id:Number(proof.runId),head_sha:c.ci.headSha,status:'completed',conclusion:'success'},{proof}));
  }
  if(url===`${GH}/actions/artifacts/${c.ci.pg.artifactId}`)
   return response(edit('artifact',{id:Number(c.ci.pg.artifactId),name:c.ci.pg.artifactName,expired:false,
    digest:'sha256:'+c.ci.pg.artifactZipSha256,workflow_run:{id:Number(c.ci.pg.runId),head_sha:c.ci.headSha}}));
  if(url===API)return response(edit('project',{id:PROJECT,region:'eu-west-1',status:'ACTIVE_HEALTHY',
   database:{host:`db.${PROJECT}.supabase.co`,postgres_engine:'17'}}));
  if(url===`${API}/functions`){
   state.edgeReads++;state.events.push('edge');
   return response(edit('metadata',edgeRows(c,state.deploys>0),{after:state.deploys>0,read:state.edgeReads}));
  }
  if(url===`${API}/functions/${FUNCTION}/body`){
   state.bodyReads++;state.events.push('body');
   const files=state.deploys?closure:baselineFiles;
   if(options.bodyWire)return options.bodyWire({files,after:state.deploys>0,state,contract:c});
   return response(edit('body',{files:[...files].map(([path,content])=>({name:'/synthetic/source/'+path,content}))},{after:state.deploys>0}));
  }
  if(url===`${API}/database/query`){
   const body=JSON.parse(request.body);
   assert.equal(request.method,'POST');assert.equal(body.read_only,false,'preserve operator role; SQL enforces read-only');
   if(body.query.startsWith('BEGIN READ ONLY;')){
    assert.match(body.query,/SET LOCAL row_security=off/);
    assert.match(body.query,/current_user<>'postgres' OR session_user<>'postgres'/);
    assert.match(body.query,/current_setting\('transaction_read_only'\)<>'on'/);
    state.reads++;state.events.push(state.commits?'readback':'snapshot');
    return response(edit('snapshot',[{snapshot:state.commits?s.after:s.before}],{phase:state.commits?'readback':state.rollbacks?'restored':'before',read:state.reads}));
   }
   assert.equal(body.read_only,false);
   assert.equal(state.reports.at(-1).status,'uncertain','persist ambiguity before a SQL mutation can begin');
   const commit=/COMMIT;$/.test(body.query);
   if(commit){state.commits++;state.events.push('commit');}else{assert.match(body.query,/ROLLBACK;$/);state.rollbacks++;state.events.push('rollback');}
   assert.ok(state.deploys===1&&state.rollbacks===1&&state.commits<=1);
   if(options.loseMutation===(commit?'commit':'rollback'))throw Error('lost database response '+CANARY);
   return response(edit('snapshot',[{snapshot:s.after}],{phase:commit?'commit':'preview'}));
  }
  assert.fail('unhandled synthetic request '+url);
 };
 const deploy=async()=>{
  assert.equal(state.reports.at(-1).status,'uncertain','persist ambiguity before deployment can begin');
  assert.equal(state.reports.at(-1).deploymentAttempted,true);
  state.deploys++;state.events.push('deploy');assert.equal(state.deploys,1);
  if(options.loseDeploy)throw Error('lost deployment response '+CANARY);
  if(options.deploy)await options.deploy(state);
 };
 const checkpoint=report=>{
  state.reports.push(structuredClone(report));
  if(options.checkpoint?.(report,state))throw Error('disk failure '+CANARY);
 };
 return {state,contract:c,run:()=>installClosed({env:{...env,...options.env},local:{...local,...options.local},contract:c,fetchImpl,deploy,checkpoint})};
}
function noLeak(state,result){
 const report=JSON.stringify([result,...state.reports]);
 assert.ok(!report.includes(CANARY));assert.ok(!/Bearer|SELECT |CREATE |file:\/\/|entrypoint_path|definition_md5/.test(report));
}
function noSqlMutation(state){assert.equal(state.rollbacks,0);assert.equal(state.commits,0);}

test('historical manifest stays intact while a synthetic contract exercises current assets and the full render',()=>{
 checkContract(versioned);checkAssets(contract(),local);
 assert.equal(baselineFiles.size,5);assert.equal(closure.size,6);
 for(const [path,content] of baselineFiles)assert.equal(digest(content),versioned.edgeBefore.files[path]);
 assert.equal(closureDigest(baselineFiles),versioned.edgeBefore.closureSha256);
 assert.equal(contract().manifestSha256,repin(contract()).manifestSha256);
 assert.notEqual(contract().edgeBefore.metadataSha256,versioned.edgeBefore.metadataSha256);
 assert.deepEqual(JSON.parse(readFileSync(new URL('../../'+CONTRACT,import.meta.url),'utf8')),versioned);
});
test('the real historical contract rejects current schema drift before network, deployment or SQL',async()=>{
 assert.notEqual(digest(local.files['supabase/schema/public.sql']),versioned.assets['supabase/schema/public.sql'].sha256);
 const h=harness({contract:versioned}),r=await h.run();
 assert.equal(r.code,'LOCAL_ASSET_DRIFT');assert.equal(r.status,'failed');
 assert.equal(h.state.calls.length,0);assert.equal(h.state.deploys,0);noSqlMutation(h.state);noLeak(h.state,r);
});
test('one deployment precedes a verified rollback, one commit and independent readback',async()=>{
 const h=harness(),r=await h.run();assert.equal(r.status,'success');assert.equal(r.code,null);
 assert.equal(h.state.deploys,1);assert.equal(h.state.rollbacks,1);assert.equal(h.state.commits,1);
 const effects=h.state.events.filter(x=>['deploy','rollback','commit','readback'].includes(x));
 assert.deepEqual(effects,['deploy','rollback','commit','readback']);
 assert.equal(h.state.bodyReads,2);assert.equal(h.state.reads,4);
 for(const key of ['deploymentConfirmed','dryRunVerified','commitConfirmed','closedStateVerified','businessRowsUnchanged'])assert.equal(r[key],true);
 for(const key of ['providerInvoked','authCreated','capabilityAllocated','credentialsChanged'])assert.equal(r[key],false);
 assert.ok(h.state.reports.some(x=>x.status==='uncertain'&&x.deploymentAttempted&&!x.deploymentConfirmed));
 assert.ok(h.state.reports.some(x=>x.status==='uncertain'&&x.commitAttempted&&!x.commitConfirmed));noLeak(h.state,r);
});
for(const [key,value] of [['GITHUB_EVENT_NAME','push'],['GITHUB_REPOSITORY','fork/repo'],['GITHUB_REF','refs/heads/feature'],
 ['GITHUB_SHA','a'.repeat(40)],['EXPECTED_SHA','b'.repeat(40)],['GITHUB_RUN_ATTEMPT','2'],['GITHUB_RUN_ID','0']])
 test(`dispatch identity ${key} refuses before any network or deployment`,async()=>{
  const h=harness({env:{[key]:value}}),r=await h.run();assert.equal(r.code,'EXACT_TRUSTED_MAIN_REQUIRED');
  assert.equal(h.state.calls.length,0);assert.equal(h.state.deploys,0);noSqlMutation(h.state);noLeak(h.state,r);
 });
test('dirty checkout, missing token, byte drift and wrong Git blob refuse before network',async()=>{
 const files={...local.files,[ASSET_PATHS[0]]:local.files[ASSET_PATHS[0]]+'\n'};
 const blobs={...local.blobs,[ASSET_PATHS[0]]:'f'.repeat(40)};
 for(const options of [{local:{clean:false}},{local:{files}},{local:{blobs}},{env:{GITHUB_TOKEN:''}},{env:{STAGING_SUPABASE_ACCESS_TOKEN:''}}]){
  const h=harness(options),r=await h.run();assert.equal(r.status,'failed');assert.equal(h.state.calls.length,0);assert.equal(h.state.deploys,0);
 }
});
test('a changed manifest digest or nonclosed scope cannot authorize installation',async()=>{
 for(const edit of [c=>c.manifestSha256='f'.repeat(64),c=>c.projectRef='flripxtsyegjshnhzjkz',
  c=>c.capabilityEnabled=true,c=>c.installationOnly=false,c=>c.assets[ASSET_PATHS[0]].gitBlob='f'.repeat(40)]){
  const c=contract();edit(c);const h=harness({contract:c}),r=await h.run();
  assert.equal(r.status,'failed');assert.equal(h.state.calls.length,0);assert.equal(h.state.deploys,0);
 }
});
test('source closure rejects remote imports and relative paths outside reviewed functions',()=>{
 for(const spec of ['https://example.invalid/'+CANARY,'npm:@supabase/supabase-js@latest','../../../outside.ts']){
  assert.throws(()=>sourceClosure(path=>path.endsWith('/send-sms/index.ts')?`import '${spec}';`:'unreviewed'),/IMPORT_REFUSED|SOURCE_PATH_REFUSED/);
 }
});
test('project identity, engine, region and health must all match staging',async()=>{
 for(const project of [p=>p.id='flripxtsyegjshnhzjkz',p=>p.database.host='db.other.supabase.co',
  p=>p.database.postgres_engine='16',p=>p.region='us-east-1',p=>p.status='INACTIVE']){
  const h=harness({project}),r=await h.run();assert.equal(r.code,'PROJECT_IDENTITY_REFUSED');assert.equal(h.state.deploys,0);noSqlMutation(h.state);
 }
});
test('main movement stops at every barrier, before the next mutation',async()=>{
 for(const read of [1,2,3,4]){
  const h=harness({main:(x,info)=>{if(info.read===read)x.object.sha='f'.repeat(40);}}),r=await h.run();
  assert.equal(r.code,'MAIN_MOVED');assert.equal(h.state.deploys,read<=2?0:1);
  assert.equal(h.state.rollbacks,read===4?1:0);assert.equal(h.state.commits,0);noLeak(h.state,r);
 }
});
test('CI merge provenance and every exact asset blob are required',async()=>{
 for(const options of [{merge:x=>x.parents.reverse()},{merge:x=>x.sha='f'.repeat(40)},
  {tree:x=>x.truncated=true},{tree:x=>x.tree.pop()},{tree:x=>x.tree.push(x.tree[0])},
  {tree:x=>x.tree[0].sha='f'.repeat(40)},{tree:x=>x.tree[0].mode='100755'}]){
  const h=harness(options),r=await h.run();assert.equal(r.status,'failed');assert.equal(h.state.deploys,0);noSqlMutation(h.state);
 }
});
test('CI runs, jobs and artifact attest the reviewed source and successful first attempt',async()=>{
 for(const options of [{run:x=>x.conclusion='failure'},{run:x=>x.run_attempt=2},{run:x=>x.head_repository.full_name='fork/repo'},
  {run:x=>x.head_sha='f'.repeat(40)},{run:x=>x.event='push'},{job:x=>x.conclusion='skipped'},
  {job:x=>x.run_id++},{job:x=>x.head_sha='f'.repeat(40)},{artifact:x=>x.expired=true},
  {artifact:x=>x.digest='sha256:'+'f'.repeat(64)},{artifact:x=>x.workflow_run.head_sha='f'.repeat(40)}]){
  const h=harness(options),r=await h.run();assert.equal(r.status,'failed');assert.equal(h.state.deploys,0);noSqlMutation(h.state);
 }
});
test('baseline Edge identity, version, JWT, import map and complete metadata are pinned',async()=>{
 for(const change of [x=>x.version++,x=>x.id='00000000-0000-4000-8000-000000000003',x=>x.verify_jwt=true,
  x=>x.status='THROTTLED',x=>x.import_map=true,x=>x.import_map_path='import_map.json',x=>x.ezbr_sha256='f'.repeat(64),
  x=>x.entrypoint_path+='?outside',x=>x.new_field=CANARY]){
  const h=harness({metadata:(rows,info)=>{if(!info.after)change(rows[0]);}}),r=await h.run();
  assert.equal(r.code,'EDGE_BASELINE_DRIFT');assert.equal(h.state.deploys,0);noSqlMutation(h.state);noLeak(h.state,r);
 }
});
test('entrypoint permits only exact tmp locations and rejects arbitrary schemes, prefixes and traversal',()=>{
 const base=contract(),suffix=`/user_fn_${PROJECT}_${base.edgeBefore.id}_${base.edgeBefore.version}/source/supabase/functions/send-sms/index.ts`;
 for(const path of [`/tmp${suffix}`,`/var/tmp${suffix}`,`file:///tmp${suffix}`,`file:///var/tmp${suffix}`]){
  const c=structuredClone(base),rows=edgeRows(c);rows[0].entrypoint_path=path;
  c.edgeBefore.metadataSha256=digest(JSON.stringify(canonical(rows[0])));repin(c);
  assert.equal(checkMetadata(rows,c).length,2);
 }
 for(const path of [`https://example.invalid/tmp${suffix}`,`s3://tmp${suffix}`,`file://outside/tmp${suffix}`,
  `file:/tmp${suffix}`,`/synthetic/tmp${suffix}`,`/tmp/prefix${suffix}`,`/tmp/elsewhere/..${suffix}`,
  `/tmp/%2e%2e${suffix}`,`/tmp${suffix}?outside`,`/tmp${suffix}#outside`]){
  const c=structuredClone(base),rows=edgeRows(c);rows[0].entrypoint_path=path;
  // Repinning removes metadata-digest drift as a competing reason for refusal.
  c.edgeBefore.metadataSha256=digest(JSON.stringify(canonical(rows[0])));repin(c);
  assert.throws(()=>checkMetadata(rows,c),/EDGE_BASELINE_DRIFT/);
 }
});
test('the historical baseline body must have exactly the five reviewed files',async()=>{
 for(const body of [x=>x.files.pop(),x=>x.files.push(x.files[0]),x=>x.files[0].content+=CANARY,
  x=>x.files[0].name='/synthetic/source/supabase/functions/../other.ts']){
  const h=harness({body:(x,info)=>{if(!info.after)body(x);}}),r=await h.run();
  assert.equal(r.status,'failed');assert.equal(h.state.deploys,0);noSqlMutation(h.state);noLeak(h.state,r);
 }
});
test('baseline quiescence, routine metadata and invariant changes stop before deploy',async()=>{
 for(const change of [s=>s.quiet=false,s=>s.absent=false,s=>s.closed=true,
  s=>s.routines.find(r=>r.signature.startsWith('public.fn_finaliser')).body_md5='f'.repeat(32),
  s=>s.routines[0].config=['search_path=public'],s=>s.routines[0].acl=['=X/postgres'],
  s=>s.routines[0].definition_md5='f'.repeat(32),s=>s.extra=CANARY]){
  const h=harness({snapshot:(rows,info)=>{if(info.phase==='before')change(rows[0].snapshot);}}),r=await h.run();
  assert.equal(r.status,'failed');assert.equal(h.state.deploys,0);noSqlMutation(h.state);noLeak(h.state,r);
 }
 for(const key of ['structure','routines','inventory','registry','rows']){
  const h=harness({snapshot:(rows,info)=>{if(info.phase==='before'&&info.read===2)rows[0].snapshot.invariant[key]='f'.repeat(32);}}),r=await h.run();
  assert.equal(r.code,'BUSINESS_OR_CATALOGUE_CHANGED');assert.equal(h.state.deploys,0);noSqlMutation(h.state);
 }
});
test('unrelated Edge change before deployment prevents it; after deployment it blocks SQL',async()=>{
 for(const after of [false,true]){
  const h=harness({metadata:(rows,info)=>{if(after?info.after:info.read===2)rows[1].opaque_field=CANARY;}}),r=await h.run();
  assert.equal(r.code,after?'EDGE_DEPLOYMENT_NOT_CONFIRMED':'EDGE_CATALOGUE_DRIFT');
  assert.equal(h.state.deploys,after?1:0);noSqlMutation(h.state);noLeak(h.state,r);
 }
});
test('deployed source must match all six local files before SQL is attempted',async()=>{
 for(const body of [x=>x.files.pop(),x=>x.files[0].content+=CANARY]){
  const h=harness({body:(x,info)=>{if(info.after)body(x);}}),r=await h.run();
  assert.equal(r.status,'uncertain');assert.equal(h.state.deploys,1);assert.equal(r.deploymentConfirmed,false);noSqlMutation(h.state);noLeak(h.state,r);
 }
});
test('closed-table failure or changed after metadata/invariants prevent the single commit',async()=>{
 for(const change of [s=>s.closed=false,s=>s.quiet=false,
  s=>s.routines[0].body_md5='f'.repeat(32),s=>s.routines[0].config=['search_path=public'],
  s=>s.routines.find(r=>r.signature.startsWith('public.fn_reserver_envoi')).definition_md5='f'.repeat(32),
  s=>s.invariant.rows='f'.repeat(32),s=>s.invariant.registry='f'.repeat(32)]){
  const h=harness({snapshot:(rows,info)=>{if(info.phase==='preview')change(rows[0].snapshot);}}),r=await h.run();
  assert.equal(r.status,'uncertain');assert.equal(h.state.deploys,1);assert.equal(h.state.rollbacks,1);assert.equal(h.state.commits,0);assert.equal(r.dryRunVerified,false);
 }
});
test('rollback must restore even target metadata, then commit and readback must match preview exactly',async()=>{
 for(const [phase,code] of [['restored','ROLLBACK_NOT_CONFIRMED'],['commit','COMMIT_RESPONSE_MISMATCH'],['readback','READBACK_MISMATCH']]){
  const h=harness({snapshot:(rows,info)=>{if(info.phase===phase)rows[0].snapshot.targets='f'.repeat(32);}}),r=await h.run();
  assert.equal(r.code,code);assert.equal(r.status,'uncertain');assert.equal(h.state.deploys,1);assert.equal(h.state.rollbacks,1);
  assert.equal(h.state.commits,phase==='restored'?0:1);assert.equal(r.commitConfirmed,false);noLeak(h.state,r);
 }
});
test('lost deployment, rollback or commit responses never retry a mutation or leak transport details',async()=>{
 for(const options of [{loseDeploy:true},{loseMutation:'rollback'},{loseMutation:'commit'}]){
  const h=harness(options),r=await h.run();assert.equal(r.status,'uncertain');assert.equal(r.commitConfirmed,false);assert.equal(h.state.deploys,1);
  assert.equal(h.state.rollbacks,options.loseDeploy?0:1);assert.equal(h.state.commits,options.loseMutation==='commit'?1:0);
  assert.equal(r.code,options.loseDeploy?'DEPLOY_RESULT_UNCERTAIN':'TRANSPORT_OR_JSON_UNCERTAIN');noLeak(h.state,r);
 }
});
test('checkpoint persistence is a prerequisite for deployment and commit intent',async()=>{
 for(const phase of ['deploy_once','commit_once']){
  const h=harness({checkpoint:r=>r.phase===phase}),r=await h.run();
  assert.equal(r.code,'CHECKPOINT_FAILED');assert.equal(h.state.deploys,phase==='deploy_once'?0:1);assert.equal(h.state.commits,0);noLeak(h.state,r);
 }
});
test('transport failures before mutation remain failed with sanitized reports',async()=>{
 const h=harness({transport:url=>url===`${GH}/actions/artifacts/${versioned.ci.pg.artifactId}`}),r=await h.run();
 assert.equal(r.status,'failed');assert.equal(r.code,'TRANSPORT_OR_JSON_UNCERTAIN');assert.equal(h.state.deploys,0);noSqlMutation(h.state);noLeak(h.state,r);
});
test('SQL snapshot checker rejects extra fields, duplicate routines and missing observed definition hash',()=>{
 const c=contract(),s=snapshots(c);
 for(const mutate of [x=>x.push(x[0]),x=>x[0].extra=CANARY,x=>x[0].snapshot.routines.push(x[0].snapshot.routines[0]),
  x=>delete x[0].snapshot.routines[0].definition_md5,x=>x[0].snapshot.routines[0].extra=CANARY]){
  const input=[{snapshot:structuredClone(s.before)}];mutate(input);assert.throws(()=>checkSnapshot(input,c,false));
 }
});
test('wire-format multipart file bodies preserve the reviewed function paths and source bytes',async()=>{
 const boundary='jolene-synthetic-files';
 const wire=[...baselineFiles].map(([path,content])=>`--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="${path}"\r\nContent-Type: application/typescript\r\n\r\n${content}\r\n`).join('')+`--${boundary}--\r\n`;
 const parsed=await readResponse(new Response(wire,{headers:{'content-type':`multipart/form-data; boundary=${boundary}`}}),true);
 assert.equal(parsed.files.length,5);
 const actual=checkBody(parsed,new Map(Object.entries(versioned.edgeBefore.files)));
 assert.equal(closureDigest(actual),versioned.edgeBefore.closureSha256);
 assert.deepEqual(await readResponse(response({files:[{name:'synthetic.ts',content:CANARY}]}),true),{files:[{name:'synthetic.ts',content:CANARY}]});
 await assert.rejects(readResponse(new Response(`--${boundary}\r\nContent-Disposition: form-data; name="files"\r\n\r\n${CANARY}\r\n--${boundary}--\r\n`,
  {headers:{'content-type':`multipart/form-data; boundary=${boundary}`}}),true),/EDGE_MULTIPART_REFUSED/);
});
// Reconstruct the captured GET body from already pinned Git blobs rather than
// duplicate its source files. Byte length and SHA pin the complete real wire.
const wireBoundary='----WebKitFormBoundary7MA4YWxkTrZu0gW';
const wireDeploymentId=`${PROJECT}_${versioned.edgeBefore.id}_23`;
const wireMetadata={deployment_id:wireDeploymentId,original_size:7996122,compressed_size:1233143,module_count:5,
 deno2_entrypoint_path:'functions/send-sms/index.ts'};
const wireMetadataPart=value=>({name:'metadata',type:'application/json',content:typeof value==='string'?value:JSON.stringify(value)});
function wireFileParts(files=baselineFiles){
 const paths=files===baselineFiles?['send-sms/index.ts','_shared/rate-limit.ts','_shared/cors.ts','_shared/admin-auth.ts','_shared/test-account.ts']:
  [...files.keys()].map(path=>path.slice('supabase/functions/'.length));
 return paths.map(path=>({name:'file',filename:'functions/'+path,type:'text/plain',content:files.get('supabase/functions/'+path)}));
}
function wireBytes(parts){
 return Buffer.concat([...parts.flatMap(part=>[
  Buffer.from(`--${wireBoundary}\r\nContent-Disposition: form-data; name="${part.name}"${part.filename===undefined?'':`; filename="${part.filename}"`}\r\nContent-Type: ${part.type??'text/plain'}\r\n\r\n`),
  Buffer.from(part.content),Buffer.from('\r\n')]),Buffer.from(`--${wireBoundary}--\r\n`)]);
}
const wireResponse=parts=>new Response(wireBytes(parts),{headers:{'content-type':`multipart/form-data; boundary=${wireBoundary}`}});
test('the exact captured Management body accepts only metadata beside the five pinned source files',async()=>{
 const parts=[wireMetadataPart(wireMetadata),...wireFileParts()],bytes=wireBytes(parts);
 assert.equal(bytes.length,47109);assert.equal(digest(bytes),'b90aae9788b680a92a95f9ea51155be7bfc32d1fac3ebbe7efa61a096b274d65');
 const parsed=await readResponse(wireResponse(parts),true,wireDeploymentId);
 assert.equal(parsed.files.length,5);assert.deepEqual(Object.keys(parsed),['files']);
 assert.equal(closureDigest(checkBody(parsed,new Map(Object.entries(versioned.edgeBefore.files)))),versioned.edgeBefore.closureSha256);
 // Metadata order has no bearing on the source closure.
 for(const at of [2,5]){
  const reordered=wireFileParts();reordered.splice(at,0,wireMetadataPart(wireMetadata));
  assert.deepEqual(await readResponse(wireResponse(reordered),true,wireDeploymentId),parsed);
 }
});
test('multipart metadata rejects malformed, duplicate, unknown and filename-disguised parts',async()=>{
 const invalid=[wireMetadataPart('{'),wireMetadataPart(''),wireMetadataPart('null'),wireMetadataPart('[]'),wireMetadataPart('1'),
  wireMetadataPart({...wireMetadata,import_map_path:'import_map.json'}),wireMetadataPart({...wireMetadata,deno2_entrypoint_path:'functions/other/index.ts'}),
  wireMetadataPart({...wireMetadata,deployment_id:wireDeploymentId.replace(/_23$/,'_24')}),
  wireMetadataPart({...wireMetadata,original_size:0}),wireMetadataPart({...wireMetadata,compressed_size:1.5}),
  wireMetadataPart({...wireMetadata,original_size:Number.MAX_SAFE_INTEGER+1}),wireMetadataPart({...wireMetadata,module_count:33}),
  {...wireMetadataPart(wireMetadata),name:'unknown'},
  {...wireMetadataPart(wireMetadata),filename:'metadata.json'},
  {...wireMetadataPart(wireMetadata),filename:'functions/send-sms/index.ts'},
  wireMetadataPart(' '.repeat(4097)),
  {name:'metadata',content:Buffer.from([0xc3,0x28])}];
 const missing=structuredClone(wireMetadata);delete missing.module_count;invalid.push(wireMetadataPart(missing));
 for(const part of invalid)await assert.rejects(readResponse(wireResponse([part,...wireFileParts()]),true,wireDeploymentId),/EDGE_MULTIPART_REFUSED/);
 await assert.rejects(readResponse(wireResponse([wireMetadataPart(wireMetadata),...wireFileParts(),wireMetadataPart(wireMetadata)]),true,wireDeploymentId),/EDGE_MULTIPART_REFUSED/);
 await assert.rejects(readResponse(wireResponse([wireMetadataPart(wireMetadata),...wireFileParts()]),true),/EDGE_MULTIPART_REFUSED/);
 await assert.rejects(readResponse(wireResponse([...Array.from({length:32},()=>wireFileParts()[0]),wireMetadataPart(wireMetadata)]),true,wireDeploymentId),/EDGE_MULTIPART_REFUSED/);
 await assert.rejects(readResponse(wireResponse([{...wireFileParts()[0],content:Buffer.from([0xc3,0x28])}]),true),/EDGE_MULTIPART_REFUSED/);
 let cancelled=false;
 const oversized=new Response(new ReadableStream({start(controller){controller.enqueue(new Uint8Array(8*1024*1024+1));},cancel(){cancelled=true;}}),
  {headers:{'content-type':`multipart/form-data; boundary=${wireBoundary}`}});
 await assert.rejects(readResponse(oversized,true,wireDeploymentId),/RESPONSE_SIZE_REFUSED/);assert.equal(cancelled,true);
});
test('metadata cannot relax source hashes, paths, cardinality or duplicates',async()=>{
 const expected=new Map(Object.entries(versioned.edgeBefore.files));
 for(const change of [parts=>parts.pop(),parts=>parts.push(parts[0]),parts=>parts[0].content+='\n',
  parts=>parts[0].filename='functions/unknown.ts',parts=>parts[0].filename='functions/../send-sms/index.ts']){
  const files=wireFileParts();change(files);
  const parsed=await readResponse(wireResponse([wireMetadataPart(wireMetadata),...files]),true,wireDeploymentId);
  assert.throws(()=>checkBody(parsed,expected),/EDGE_(?:BODY_REFUSED|SOURCE_DRIFT)/);
 }
});
test('installer binds multipart metadata to baseline and deployed versions before any SQL transaction',async()=>{
 const bodyWire=({files,after})=>wireResponse([wireMetadataPart({...wireMetadata,
  deployment_id:wireDeploymentId.replace(/_23$/,after?'_24':'_23'),module_count:files.size}),...wireFileParts(files)]);
 const good=harness({bodyWire});const report=await good.run();assert.equal(report.status,'success');assert.equal(good.state.deploys,1);noLeak(good.state,report);
 for(const wrongAfter of [false,true]){
  const bad=harness({bodyWire:info=>info.after===wrongAfter?wireResponse([wireMetadataPart({...wireMetadata,
   deployment_id:wireDeploymentId.replace(/_23$/,info.after?'_23':'_24')}),...wireFileParts(info.files)]):bodyWire(info)});
  const refused=await bad.run();assert.equal(refused.code,'EDGE_MULTIPART_REFUSED');
  assert.equal(refused.deploymentAttempted,wrongAfter);assert.equal(refused.commitAttempted,false);assert.equal(refused.providerInvoked,false);
  assert.equal(bad.state.deploys,wrongAfter?1:0);noSqlMutation(bad.state);noLeak(bad.state,refused);
 }
});
test('CLI pins its version, deploys send-sms alone and receives a reduced environment',()=>{
 const calls=[];
 const supplied={...env,TWILIO_AUTH_TOKEN:CANARY,STRIPE_SECRET_KEY:CANARY,SUPABASE_DB_PASSWORD:CANARY,
  SUPABASE_SERVICE_ROLE_KEY:CANARY,HTTP_PROXY:CANARY,HTTPS_PROXY:CANARY,DENO_AUTH_TOKENS:CANARY,
  SUPABASE_PROJECT_ID:'production',SUPABASE_ACCESS_TOKEN:'inherited-'+CANARY,NODE_OPTIONS:'--require='+CANARY};
 deployCommand(supplied,'/synthetic/worktree',(command,args,options)=>{calls.push({command,args,options});return '2.98.0\n';});
 assert.equal(calls.length,2);assert.deepEqual(calls.map(x=>x.command),['supabase','supabase']);
 assert.deepEqual(calls[0].args,['--version']);
 assert.deepEqual(calls[1].args,['functions','deploy','send-sms','--project-ref',PROJECT,'--use-api','--no-verify-jwt']);
 for(const {options} of calls){
  assert.deepEqual(options.env,{PATH:env.PATH,HOME:env.HOME,CI:'true',NO_COLOR:'1',DO_NOT_TRACK:'1',SUPABASE_ACCESS_TOKEN:env.STAGING_SUPABASE_ACCESS_TOKEN});
  assert.equal(options.cwd,'/synthetic/worktree');assert.deepEqual(options.stdio,['ignore','pipe','pipe']);
 }
 let count=0;assert.throws(()=>deployCommand(env,root,()=>{count++;return '2.99.0\n';}),/CLI_VERSION_REFUSED/);assert.equal(count,1);
});

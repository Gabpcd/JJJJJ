import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,readdirSync,lstatSync,realpathSync,symlinkSync,linkSync,chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BRANCH,PRODUCT_SHA,IMAGE,assertReview,assertNativeReview,closedFailure,validateBrowserReceipt,STAGES,digest,projectRestoreCall,RESTORE_CALL_OPERATIONS,projectPgRestoreDiagnostic } from '../contract.mjs';
import { executionIdentity,checkIdentity,checkVercel } from '../identity.mjs';
import { restoreTarget } from '../restore-target.mjs';
import { fileTree } from '../../snapshot-restore.mjs';
import { STAGES as A_STAGES } from '../../projection.mjs';
import { SETTINGS_SQL,ROLE_SETTINGS_SQL,assertObjectWitness,proveControlledMissingPdf,classifyPgRestoreStderr } from '../native-runtime.mjs';
import { makePlan } from '../../../restore/bootstrap.mjs';
import { localBuildEnvironment } from '../build-app.mjs';
import { validateBrowser,boundedOutput } from '../browser-driver.mjs';
import { runPhaseB } from '../core.mjs';
const run='jolene-restore-drill-123456-1';
const approved=()=>({productSha:PRODUCT_SHA,approved:true,phaseAHarnessSha:'a'.repeat(40),phaseARunId:'123456',nativeRestoreTocSha256:'b'.repeat(64),nativeRoleSettingsReviewed:true,nativeGraphqlRepairReviewed:true,native:{postgresVersionNum:170006,auth:{count:40,sha256:'c'.repeat(64)},storage:{count:30,sha256:'d'.repeat(64)}}});
const receipt=side=>{const projects=side==='source'?['ordinateur']:['ipad-portrait','ipad-paysage','iphone','android','ordinateur'];const cases=side==='source'?['RESTORE_OWNER_S','RESTORE_OWNER_E']:['RESTORE_OWNER_S','RESTORE_OWNER_E','RESTORE_OTHER_S','RESTORE_OTHER_E','RESTORE_ANONYMOUS'];const tests=cases.flatMap(caseId=>projects.map(project=>({caseId,project,outcome:'expected',attempts:[{status:'passed',code:'PASSED',retry:0}]})));return {schemaVersion:1,productSha:PRODUCT_SHA,side,complete:true,passed:true,expectedCount:tests.length,globalErrorCount:0,counts:{expected:tests.length,unexpected:0,flaky:0,skipped:0},tests};};
const env={GITHUB_REPOSITORY:'Gabpcd/JJJJJ',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:'refs/heads/'+BRANCH,GITHUB_SHA:'f'.repeat(40),GITHUB_WORKFLOW_SHA:'f'.repeat(40),GITHUB_WORKFLOW_REF:'Gabpcd/JJJJJ/.github/workflows/restore-local-bootstrap.yml@refs/heads/'+BRANCH,GITHUB_RUN_ID:'123456',GITHUB_RUN_ATTEMPT:'1'};
async function importProgress(directory,reports) {
 const stop=Object.assign(new Error('SYNTHETIC_IMPORT_STOP'),{code:'TEST_IMPORT_STOP'});
 return runPhaseB({}, {stack:directory},approved(),()=>{}, {
  runPhaseA:(_e,_p,_save,{saveImport})=>{for(const report of reports)saveImport(report);throw stop;}
 });
}
function progressDirectory(t) {
 const dir=realpathSync(mkdtempSync(join(tmpdir(),'jolene-import-progress-')));
 t.after(()=>rmSync(dir,{recursive:true,force:true}));return dir;
}
test('private import progress preserves repeated updates and the original import failure',async t=>{
 const dir=progressDirectory(t),reports=[{phase:'start'},{phase:'native_owner_probe'},
  {phase:'integral_replay',migrations:[{completed:true}]},{phase:'failed',failure:{code:'SYNTHETIC_IMPORT'}}];
 await assert.rejects(()=>importProgress(dir,reports),error=>error.code==='TEST_IMPORT_STOP');
 const target=join(dir,'import-qualification.private.json');
 assert.deepEqual(JSON.parse(readFileSync(target,'utf8')),reports.at(-1));
 assert.equal(lstatSync(target).mode&0o777,0o600);
 assert.deepEqual(readdirSync(dir),['import-qualification.private.json']);
});
test('private import progress refuses linked targets without touching their contents',async t=>{
 for(const type of ['symlink','dangling','hardlink','directory']) {
  const dir=progressDirectory(t),target=join(dir,'import-qualification.private.json'),other=join(dir,'other');
  writeFileSync(other,'UNTOUCHED',{mode:0o600});
  if(type==='symlink')symlinkSync(other,target);
  if(type==='dangling')symlinkSync(join(dir,'absent'),target);
  if(type==='hardlink')linkSync(other,target);
  if(type==='directory')mkdirSync(target,{mode:0o700});
  await assert.rejects(()=>importProgress(dir,[{phase:'start'}]),error=>error.code==='B_CONTEXT');
  assert.equal(readFileSync(other,'utf8'),'UNTOUCHED');
  assert.equal(readdirSync(dir).includes('import-qualification.private.json.writing'),false);
 }
});
test('private import progress refuses an existing temporary file and preserves the last report',async t=>{
 for(const type of ['file','dangling']) {
  const dir=progressDirectory(t),target=join(dir,'import-qualification.private.json'),temporary=target+'.writing';
  await assert.rejects(()=>importProgress(dir,[{phase:'first'}]),error=>error.code==='TEST_IMPORT_STOP');
  if(type==='file')writeFileSync(temporary,'UNTOUCHED',{mode:0o600});else symlinkSync(join(dir,'absent'),temporary);
  await assert.rejects(()=>importProgress(dir,[{phase:'second'}]),error=>error.code==='EEXIST');
  assert.deepEqual(JSON.parse(readFileSync(target,'utf8')),{phase:'first'});
  if(type==='file')assert.equal(readFileSync(temporary,'utf8'),'UNTOUCHED');else assert.equal(lstatSync(temporary).isSymbolicLink(),true);
 }
});
test('private import progress rejects a public or aliased directory',async t=>{
 const dir=progressDirectory(t);chmodSync(dir,0o755);
 await assert.rejects(()=>importProgress(dir,[{phase:'start'}]),error=>error.code==='B_CONTEXT');
 assert.equal(readdirSync(dir).length,0);chmodSync(dir,0o700);
 const parent=progressDirectory(t),alias=join(parent,'alias');symlinkSync(dir,alias);
 await assert.rejects(()=>importProgress(alias,[{phase:'start'}]),error=>error.code==='B_CONTEXT');
 assert.equal(readdirSync(dir).length,0);
});
test('exact B dispatch and source scope reject branch event dirty source and product changes',()=>{
 assert.equal(executionIdentity(env,env.GITHUB_SHA).run,run);
 for(const patch of [{GITHUB_REF:'refs/heads/main'},{GITHUB_REF:'refs/heads/ci/restore-app-phase-a-20261004'},{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_SHA:PRODUCT_SHA},{GITHUB_WORKFLOW_SHA:'e'.repeat(40)},{GITHUB_REPOSITORY:'foreign/repo'}])assert.throws(()=>executionIdentity({...env,...patch},env.GITHUB_SHA));
 assert.throws(()=>checkIdentity(env,env.GITHUB_SHA,['src/App.tsx'],'',['allowed']));
 assert.throws(()=>checkIdentity(env,env.GITHUB_SHA,['allowed'],'dirty',['allowed']));
 const current={git:{deploymentEnabled:{'ci/restore-app-phase-a-20261004':false,[BRANCH]:false}}};checkVercel({},current);current.git.deploymentEnabled[BRANCH]=true;assert.throws(()=>checkVercel({},current));
});
test('pending A review refuses before any work; no automatic review or TOC acceptance',async()=>{
 for(const flags of [{approved:false,nativeRoleSettingsReviewed:false},{approved:true,nativeRoleSettingsReviewed:false},{approved:false,nativeRoleSettingsReviewed:true}]){
  const pending={...approved(),...flags};assert.throws(()=>assertReview(pending));let called=false;
  await assert.rejects(()=>runPhaseB({}, {},pending,()=>{}, {runPhaseA:()=>{called=true;}}),e=>e.code==='B_REVIEW');assert.equal(called,false);
 }
 for(const edit of [{approved:false},{nativeRestoreTocSha256:null},{nativeRoleSettingsReviewed:false},{nativeGraphqlRepairReviewed:false},{productSha:'f'.repeat(40)},{phaseARunId:''}])assert.throws(()=>assertReview({...approved(),...edit}));
 const review=approved(),native={result:'PHASE_A_NATIVE_CAPTURE_PASSED',productSha:PRODUCT_SHA,toc:{normalizedSha256:review.nativeRestoreTocSha256},native:review.native,sourceStopped:true,targetNativeEmpty:true,targetFilesEmpty:true};assertNativeReview(native,review);
 for(const edit of [{sourceStopped:false},{targetNativeEmpty:false},{toc:{normalizedSha256:'0'.repeat(64)}}])assert.throws(()=>assertNativeReview({...native,...edit},review));
});
test('all A stages remain known and closed failure drops arbitrary messages, Auth and raw diagnostics',()=>{
 for(const stage of A_STAGES)assert.equal(STAGES.has(stage),true);
 const canary='PRIVATE_TOKEN_CANARY';const result=closedFailure({code:canary,message:canary,diagnostic:{sqlstate:'42725',line:36,body:canary}},canary);
 assert.equal(result.code,'B_FAILED');assert.equal(result.sqlstate,'42725');assert.equal(result.sqlLine,36);assert.ok(!JSON.stringify(result).includes(canary));
});
test('browser receipts require exact 2 or 25 pairs, single attempts and no leaks',()=>{
 for(const side of ['source','target'])assert.equal(validateBrowserReceipt(receipt(side),side).passed,true);
 for(const edit of [r=>r.tests[0]=r.tests[1],r=>r.tests.pop(),r=>r.tests[0].attempts.push(r.tests[0].attempts[0]),r=>r.tests[0].project='unknown',r=>r.counts.expected=24,r=>r.globalErrorCount=1]){const r=receipt('target');edit(r);assert.throws(()=>validateBrowserReceipt(r,'target'));}
 const r=receipt('target');r.password='CANARY';r.tests[0].raw='CANARY';assert.ok(!JSON.stringify(validateBrowserReceipt(r,'target')).includes('CANARY'));
 const failed=receipt('target');failed.passed=false;failed.counts.expected--;failed.counts.unexpected++;failed.tests[0].outcome='unexpected';failed.tests[0].attempts=[{status:'failed',code:'TEST_FAILED',retry:0}];assert.equal(validateBrowserReceipt(failed,'target').passed,false);
});
test('restore call diagnostics retain only closed operation and process fields without changing failure',()=>{
 const canary='PRIVATE_SQL_AUTH_DUMP_PATH_CANARY';
 for(const operation of RESTORE_CALL_OPERATIONS){
  const raw={operation,exitCode:1,signal:null,systemError:null,stderr:canary,args:[canary],input:canary};
  const error={code:'B_CALL',restoreCall:raw,diagnostic:{sqlstate:'42501',line:2,message:canary}};
  const projected=closedFailure(error,'restore');
  assert.deepEqual(projected.restoreCall,{schemaVersion:1,operation,exitCode:1,signal:null,systemError:null,timedOut:false});
  assert.equal(projected.code,'B_CALL');assert.equal(projected.stage,'restore');assert.equal(projected.sqlstate,'42501');
  assert.equal(projected.restored,false);assert.equal(projected.appVerified,false);assert.ok(!JSON.stringify(projected).includes(canary));
  assert.equal(closedFailure(error,'browser_source').restoreCall,undefined);
  assert.equal(closedFailure({...error,code:'B_FAILED'},'restore').restoreCall,undefined);
 }
 assert.deepEqual(projectRestoreCall({operation:canary,exitCode:999,signal:canary,systemError:canary,timedOut:true}),
  {schemaVersion:1,operation:'UNKNOWN',exitCode:null,signal:'OTHER',systemError:'OTHER',timedOut:false});
 const timeout=projectRestoreCall({operation:'TARGET_ARCHIVE_RESTORE',exitCode:null,signal:'SIGTERM',systemError:'ETIMEDOUT'});
 assert.equal(timeout.timedOut,true);assert.equal(timeout.signal,'SIGTERM');
 for(const value of [-1,256,Infinity,NaN,1.5,canary])assert.equal(projectRestoreCall({exitCode:value}).exitCode,null);
 assert.equal(closedFailure({code:'B_CALL'},'restore').restoreCall,undefined);
});
function restoreHarness(t,patch={}){const dir=mkdtempSync(join(tmpdir(),'restore-b-contract-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));mkdirSync(join(dir,'files'));writeFileSync(join(dir,'database.dump'),'PGDMPsynthetic');writeFileSync(join(dir,'archive-toc.private.txt'),'SYNTHETIC_TOC');writeFileSync(join(dir,'files','file'),'synthetic');const calls=[];const snap={run,archiveSha256:digest('PGDMPsynthetic'),tocSha256:approved().nativeRestoreTocSha256,files:fileTree(join(dir,'files')),before:{rows:'synthetic'},catalogue:{catalogue:'synthetic'}};const r={run,verifyState:async v=>calls.push(['state',v]),assertTargetNativeEmpty:async()=>calls.push(['empty-db']),assertTargetFilesEmpty:async()=>calls.push(['empty-files']),recreateOwnedEmptyTargetDatabase:async n=>calls.push(['drop-create',n]),prepareTargetArchiveRestore:async input=>{calls.push(['prepare',input]);return input;},executePreparedTargetRestore:async prepared=>calls.push(['restore',prepared]),applyReviewedRoleSettings:async()=>calls.push(['roles']),copyFilesIn:async()=>calls.push(['copy']),sqlJson:async()=>snap.before,assertSourceOffAndTargetCatalogExact:async()=>calls.push(['catalogue']),startApis:async()=>calls.push(['start']),assertApiHealthy:async()=>calls.push(['healthy']),...patch};return{dir,snap,r,calls,execute:()=>restoreTarget(r,dir,snap,approved(),'checkpoint')};}
test('restore prepares exact archive before DROP then executes only prepared transaction',async t=>{const h=restoreHarness(t);const r=await h.execute();assert.equal(r.restored,true);assert.deepEqual(h.calls.map(v=>v[0]),['state','empty-db','empty-files','prepare','drop-create','restore','roles','empty-files','copy','catalogue','start','healthy']);const prepare=h.calls.find(v=>v[0]==='prepare');assert.equal(prepare[1].archive.toString(),'PGDMPsynthetic');assert.equal(prepare[1].toc.toString(),'SYNTHETIC_TOC');assert.equal(h.calls.find(v=>v[0]==='restore')[1],prepare[1]);});
for(const failure of ['source-active','occupied-db','occupied-files','dump-change','file-change','toc-change','checkpoint-change'])test('restore refuses '+failure,async t=>{const h=restoreHarness(t);if(failure==='source-active')h.r.verifyState=async()=>{throw Error('state');};if(failure==='occupied-db')h.r.assertTargetNativeEmpty=async()=>{throw Error('db');};if(failure==='occupied-files')h.r.assertTargetFilesEmpty=async()=>{throw Error('files');};if(failure==='dump-change')writeFileSync(join(h.dir,'database.dump'),'PGDMPchanged');if(failure==='file-change')writeFileSync(join(h.dir,'files','file'),'changed');if(failure==='toc-change')h.snap.tocSha256='0'.repeat(64);if(failure==='checkpoint-change')h.r.sqlJson=async()=>({rows:'changed'});await assert.rejects(h.execute);if(failure!=='checkpoint-change')assert.ok(!h.calls.some(v=>v[0]==='drop-create'));else assert.ok(!h.calls.some(v=>v[0]==='start'));});
test('volume appearing after DB restore prevents copying any storage bytes',async t=>{let checks=0;const h=restoreHarness(t,{assertTargetFilesEmpty:async()=>{if(++checks===2)throw Error('appeared');}});await assert.rejects(h.execute);assert.ok(h.calls.some(v=>v[0]==='restore'));assert.ok(!h.calls.some(v=>v[0]==='copy'));});
function plan(){const lock=JSON.parse(readFileSync(new URL('../../../../images.lock.json',import.meta.url)));return makePlan(run,'/tmp/private-b-plan',lock,{source:{password:'SYNTHETIC_A',jwt:'SYNTHETIC_A_JWT'},target:{password:'SYNTHETIC_B',jwt:'SYNTHETIC_B_JWT'}});}
test('build receives only explicit local URL and anon key, never inherited provider variables',()=>{const p=plan();const original=process.env.SUPABASE_SERVICE_ROLE_KEY;process.env.SUPABASE_SERVICE_ROLE_KEY='CANARY';try{for(const side of ['source','target']){const env=localBuildEnvironment(p,side);assert.equal(env.VITE_SUPABASE_URL,`http://${run}-${side}-api:8000`);assert.equal(env.VITE_NATIVE_BUILD,'false');assert.ok(!JSON.stringify(env).includes('CANARY'));assert.ok(!Object.hasOwn(env,'SUPABASE_SERVICE_ROLE_KEY'));}assert.throws(()=>localBuildEnvironment(p,'production'));p.services['source-storage'].environment.ANON_KEY=p.services['source-storage'].environment.SERVICE_KEY;assert.throws(()=>localBuildEnvironment(p,'source'));}finally{if(original===undefined)delete process.env.SUPABASE_SERVICE_ROLE_KEY;else process.env.SUPABASE_SERVICE_ROLE_KEY=original;}});
test('GUC catalogue maps database and role names; only exact existing product role settings replay',()=>{assert.match(SETTINGS_SQL,/CASE WHEN s.setdatabase=0 THEN '\*' ELSE d.datname END/);assert.match(SETTINGS_SQL,/CASE WHEN s.setrole=0 THEN '\*' ELSE r.rolname END/);assert.ok(!/jsonb_build_array\(\s*s.setdatabase/.test(SETTINGS_SQL));const migrations=new URL('../../../../../../supabase/migrations/',import.meta.url);const all=readdirSync(migrations).filter(n=>n.endsWith('.sql')).map(n=>readFileSync(new URL(n,migrations),'utf8')).join('\n');assert.match(all,/ALTER ROLE authenticator\s+SET pgrst\.db_pre_request = 'public\.fn_pre_request_compte_actif'/);assert.match(all,/ALTER ROLE authenticator SET statement_timeout = ''120s''/);assert.equal((ROLE_SETTINGS_SQL.match(/ALTER ROLE/g)||[]).length,2);assert.ok(!/PASSWORD|SUPERUSER|CREATEROLE|LOGIN/.test(ROLE_SETTINGS_SQL));});
function inspection(side='source'){const p=plan(),network={Name:run+'-network',Internal:true,Labels:{'org.jolene.restore-drill':run},Driver:'bridge',Attachable:false,EnableIPv6:false,Containers:{}};const natives=Object.values(p.services).map((s,i)=>{const running=side==='source'?s.container_name.includes('-source-')||s.container_name.endsWith('-target-db'):s.container_name.includes('-target-');const n={Id:'n'+i,Name:'/'+s.container_name,Config:{Labels:s.labels,Image:s.image,Env:Object.entries(s.environment).map(([k,v])=>k+'='+v),Cmd:s.command},NetworkSettings:{Networks:{[network.Name]:{}}},HostConfig:{PortBindings:{},CapAdd:null,NetworkMode:network.Name},Mounts:(s.volumes??[]).map(v=>v.type==='bind'?{Type:'bind',Source:v.source,Destination:v.target,RW:false}:{Type:'volume',Name:p.volumes[v.source].name,Destination:v.target,RW:true}),State:{Status:running?'running':'exited',Health:{Status:'healthy'}}};if(running)network.Containers[n.Id]={Name:s.container_name};return n;});const volumes=Object.values(p.volumes).map(v=>({Name:v.name,Labels:v.labels,Driver:'local',Options:null})),mounts=[{source:'/private/synthetic',target:'/restore-code',readOnly:true}];const c={Name:'/'+run+'-browser',Image:'image-id',Config:{Image:IMAGE,Env:['JOLENE_RESTORE_BROWSER_INPUT=/restore-private/input.json','PLAYWRIGHT_BROWSERS_PATH=/ms-playwright','HOME=/tmp','TMPDIR=/tmp','NODE_ENV=test'],Labels:{'org.jolene.restore-browser':run,'org.jolene.restore-browser-side':side}},State:{Status:'running'},HostConfig:{NetworkMode:network.Name,Privileged:false,ReadonlyRootfs:true,CapDrop:['ALL'],SecurityOpt:['no-new-privileges'],IpcMode:'private',LogConfig:{Type:'none'}},NetworkSettings:{Networks:{[network.Name]:{}}},Mounts:[{Type:'bind',Source:mounts[0].source,Destination:mounts[0].target,RW:false}]};network.Containers.browser={Name:run+'-browser'};return{p,c,network,natives,volumes,mounts,check:()=>validateBrowser(p,side,c,network,natives,volumes,mounts,'image-id')};}
test('browser contract accepts isolated synthetic inspection only',()=>{assert.equal(inspection().check(),true);assert.equal(inspection('target').check(),true);});
for(const [name,edit]of [['server key',h=>h.c.Config.Env.push('SERVICE_KEY=synthetic')],['proxy',h=>h.c.Config.Env.push('HTTPS_PROXY=http://synthetic')],['ports',h=>h.c.HostConfig.PortBindings={'80/tcp':[{}]}],['network',h=>h.network.Internal=false],['host IPC',h=>h.c.HostConfig.IpcMode='host'],['foreign service',h=>h.network.Containers.foreign={Name:'foreign'}],['source still on',h=>h.natives[0].State.Status='running'],['writable code',h=>h.c.Mounts[0].RW=true],['secret bind',h=>h.c.Mounts.push({Type:'bind',Source:'/secret',Destination:'/s'})],['missing container',h=>h.natives.pop()],['changed database command',h=>h.natives.find(n=>n.Name.endsWith('-db')).Config.Cmd=['wrong']]])test('browser contract rejects '+name,()=>{const h=inspection('target');edit(h);assert.throws(h.check);});
test('bounded raw output never permits large file or too many files',t=>{const dir=mkdtempSync(join(tmpdir(),'restore-b-output-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));writeFileSync(join(dir,'a'),'1234');assert.equal(boundedOutput(dir,4).bytes,4);assert.throws(()=>boundedOutput(dir,3));});
test('workflow keeps closed B entry and excludes both manual branches from empty bootstrap',()=>{const all=readFileSync(new URL('../../../../../../.github/workflows/restore-local-bootstrap.yml',import.meta.url),'utf8'),b=all.split('  native-restore-app:\n')[1].split('  native-capture:\n')[0];assert.match(b,/github.event_name == 'workflow_dispatch'/);assert.match(b,/refs\/heads\/ci\/restore-app-phase-b-20261004/);assert.ok(!/secrets\.|environment:|supabase db|workflow run|download-artifact/.test(b));assert.match(b,/native > "\$PRIVATE_DIR\/native.log" 2>&1/);assert.match(b,/if: always\(\)/);const uploads=[...b.matchAll(/\$\{\{ env\.PROOF_DIR \}\}\/([^\n]+)/g)].map(v=>v[1]);assert.equal(uploads.length,15);assert.ok(uploads.every(v=>v.endsWith('.json')));assert.match(all,/github.head_ref != 'ci\/restore-app-phase-b-20261004'/);});
function coreHarness(change={}) {
 const calls=[],reports=[],review=approved();const fixture={run},snapshot={run};
 const runtime={run,startSourceForUi:async()=>calls.push('start-source'),createPostBackupSentinel:async()=>calls.push('sentinel'),stopSource:async()=>calls.push('stop-source'),verifyState:async state=>calls.push('state:'+state.source+':'+state.target),assertRestoredObjects:async()=>{calls.push('objects');return {verified:2,sentinelAbsent:true};}};
 const dependencies={runPhaseA:async(e,p,save,d)=>{calls.push('capture');d.makeRuntime('synthetic');d.makeFixture();await d.capture();return {result:'PHASE_A_NATIVE_CAPTURE_PASSED',productSha:PRODUCT_SHA,toc:{normalizedSha256:review.nativeRestoreTocSha256},native:review.native,sourceStopped:true,targetNativeEmpty:true,targetFilesEmpty:true};},makeRuntime:()=>runtime,makeFixture:()=>fixture,capture:async()=>snapshot,
 browserDriver:()=>({run:async side=>{calls.push('ui-'+side);return {exitCode:0,report:receipt(side)};}}),verifyBuild:(_p,side)=>calls.push('build-'+side),checkpointSql:'synthetic',proveControlledMissingPdf:async()=>{calls.push('negative');return {result:'CONTROLLED_TARGET_PDF_MISSING_REJECTED',expectedCode:'B_FILES',sameVerifierRejected:true,xmlStillExact:true,sourceOff:true};},restoreTarget:async()=>{calls.push('restore');return {restored:true,sourceOff:true,targetSeeded:false,nativeGraphqlPrerequisiteVerified:true,nativeGraphqlRestoredExact:true};},...change};
 return{calls,reports,execute:()=>runPhaseB({run,productDirectory:'/synthetic'},{stack:'/synthetic'},review,(...args)=>reports.push(args),dependencies)};
}
test('orchestration reuses A same run then source2, sentinel, source off, restore and target25',async()=>{const h=coreHarness();const result=await h.execute();assert.deepEqual(h.calls,['capture','start-source','build-source','ui-source','sentinel','stop-source','state:off:db-only','restore','objects','build-target','ui-target','objects','state:off:running','negative']);assert.equal(result.sourceCases,2);assert.equal(result.targetCases,25);assert.equal(result.liveSessionsRestored,false);assert.equal(result.readyForNationalLaunch,false);});
test('failed source browser prevents restore; failed target never produces app passed',async()=>{
 for(const failingSide of ['source','target']){const h=coreHarness({browserDriver:()=>({run:async side=>({exitCode:side===failingSide?1:0,report:receipt(side)})})});await assert.rejects(h.execute);assert.ok(!h.reports.some(([,r])=>r.result==='ISOLATED_SYNTHETIC_APP_RESTORATION_PASSED'));if(failingSide==='source')assert.ok(!h.calls.includes('restore'));}
});
test('changed A native inventory refuses before starting source UI',async()=>{const h=coreHarness({runPhaseA:async()=>({result:'PHASE_A_NATIVE_CAPTURE_PASSED',productSha:PRODUCT_SHA,toc:{normalizedSha256:'0'.repeat(64)}})});await assert.rejects(h.execute);assert.ok(!h.calls.includes('start-source'));});
test('browser entry imports stay within mounted browser files or closed projector',()=>{for(const name of ['browser-entry.mjs','contract.mjs','private-app.mjs','browser-input.mjs','matrix-contract.mjs']){const src=readFileSync(new URL('../'+name,import.meta.url),'utf8');assert.ok(!/from ['"]\.\.\//.test(src),name);}});
test('actual main closed projector and B matrix compose without exposing raw report errors',async()=>{
 const {projectReport}=await import('../../../../../../scripts/ci/run-playwright-public.mjs');
 const {assertRestoreMatrix}=await import('../matrix-contract.mjs');
 const {fileURLToPath}=await import('node:url');
 const cwd=fileURLToPath(new URL('../',import.meta.url)).replace(/\/$/,'');
 for(const side of ['source','target']){
  const expected=receipt(side),raw={config:{rootDir:cwd+'/e2e'},stats:{duration:1,...expected.counts},errors:[],suites:[{specs:expected.tests.map(item=>({title:item.caseId,file:'restore-app.spec.ts',line:1,column:1,tests:[{projectName:item.project,expectedStatus:'passed',status:'expected',results:[{status:'passed',duration:1,retry:0,errors:[]}]}]}))}]};
  const projected=await projectReport(raw,{phase:'simulation-admin',cwd});
  const tests=assertRestoreMatrix(raw,projected.tests,side);
  const closed=validateBrowserReceipt({...expected,counts:projected.counts,globalErrorCount:projected.globalErrorCount,tests},side);
  assert.equal(closed.passed,true);assert.equal(closed.expectedCount,side==='source'?2:25);
  raw.errors.push({message:'PRIVATE_CANARY_DO_NOT_PUBLISH'});const failure=await projectReport(raw,{phase:'simulation-admin',cwd});assert.equal(failure.globalErrorCount,1);assert.ok(!JSON.stringify(failure).includes('PRIVATE_CANARY_DO_NOT_PUBLISH'));
 }
});
const objectsExact=()=>({verified:2,pdfExact:true,xmlExact:true,pdfMissing:false,xmlMissing:false,sentinelAbsent:true});
const pdfMissing=()=>({verified:1,pdfExact:false,xmlExact:true,pdfMissing:true,xmlMissing:false,sentinelAbsent:true});
test('controlled negative requires the same checker to reject only the removed known PDF',async()=>{
 assert.equal(assertObjectWitness(objectsExact()).verified,2);
 const calls=[];const runtime={removeKnownTargetPdf:async()=>{calls.push('remove-known-target');return{deleted:true,status:200};},assertRestoredObjects:async()=>{calls.push('same-checker');return assertObjectWitness(pdfMissing());},verifyState:async state=>{assert.deepEqual(state,{source:'off',target:'running',browser:'absent'});calls.push('source-off');}};
 const result=await proveControlledMissingPdf(runtime,{});assert.equal(result.expectedCode,'B_FILES');assert.equal(result.xmlStillExact,true);assert.deepEqual(calls,['remove-known-target','same-checker','source-off']);
});
for(const [name,check]of [['still exact',()=>assertObjectWitness(objectsExact())],['arbitrary transport error',()=>{throw Error('TIMEOUT_CANARY');}],['untyped failure',()=>{throw {code:'B_FILES'};}],['also XML missing',()=>assertObjectWitness({...pdfMissing(),xmlExact:false,xmlMissing:true,verified:0})],['only PDF corrupt',()=>assertObjectWitness({...pdfMissing(),pdfMissing:false})],['wrong sentinel',()=>assertObjectWitness({...pdfMissing(),sentinelAbsent:false})]])test('controlled negative rejects '+name,async()=>{await assert.rejects(()=>proveControlledMissingPdf({removeKnownTargetPdf:async()=>({deleted:true,status:200}),assertRestoredObjects:async()=>check(),verifyState:async()=>{}},{}));});
test('failed controlled deletion cannot be counted as a negative witness',async()=>{let checked=false;await assert.rejects(()=>proveControlledMissingPdf({removeKnownTargetPdf:async()=>({deleted:false,status:500}),assertRestoredObjects:async()=>{checked=true;}},{}));assert.equal(checked,false);});
test('negative runtime mutation is a single exact target Storage key, never SQL/source deletion',()=>{
 const src=readFileSync(new URL('../native-runtime.mjs',import.meta.url),'utf8').split('removeKnownTargetPdf:async fixture=>{')[1].split('assertRestoredObjects:async fixture=>{')[0];
 assert.match(src,/key===`invoices\/restore\/\$\{id\}\/invoice\.pdf`/);assert.match(src,/prefixes:\[p.key\]/);assert.match(src,/count===1/);assert.match(src,/`\$\{run\}-target-storage`/);assert.ok(!/source-storage|DELETE FROM|TRUNCATE|DROP/.test(src));
});

test('B preserves exact A V9 project_toc schema diagnosis while dropping arbitrary payloads',async()=>{
 const {runtimeFailure}=await import('../main.mjs');
 const {phaseFailure}=await import('../../failure.mjs');
 const diagnosis={entryOrdinal:200,kind:'FUNCTION',tokenClass:'known_native_candidate',candidate:'_realtime',tokenSha256:null};
 const error=phaseFailure('PHASE_A_TOC_SCHEMA',{tocDiagnostic:diagnosis});error.message='PRIVATE_CANARY';
 const result=runtimeFailure(error,'project_toc');
 assert.equal(result.stage,'project_toc');assert.equal(result.phaseA.code,'PHASE_A_TOC_SCHEMA');assert.deepEqual(result.phaseA.toc,diagnosis);
 assert.equal(result.restored,false);assert.ok(!JSON.stringify(result).includes('PRIVATE_CANARY'));
 const forged=runtimeFailure({publicCode:'PRIVATE_CANARY',message:'PRIVATE_CANARY'},'project_toc');assert.equal(forged.phaseA,undefined);assert.ok(!JSON.stringify(forged).includes('PRIVATE_CANARY'));
});

test('B retains A V9 closed unknown-kind diagnosis without any free token',async()=>{
 const {runtimeFailure}=await import('../main.mjs');const {phaseFailure}=await import('../../failure.mjs');
 const canary='PRIVATE_KIND_CANARY',diagnosis={entryOrdinal:200,candidate:null,prefixSha256:digest(canary)};
 const result=runtimeFailure(phaseFailure('PHASE_A_TOC_KIND',{tocDiagnostic:diagnosis}),'project_toc');
 assert.deepEqual(result.phaseA.toc,diagnosis);assert.equal(result.phaseA.code,'PHASE_A_TOC_KIND');
 assert.equal(result.restored,false);assert.equal(result.appVerified,false);assert.ok(!JSON.stringify(result).includes(canary));
 const forged=runtimeFailure(phaseFailure('PHASE_A_TOC_KIND',{tocDiagnostic:{...diagnosis,raw:canary}}),'project_toc');
 assert.equal(forged.phaseA.toc,null);assert.ok(!JSON.stringify(forged).includes(canary));
});
test('A V9 native version projection permits new installation date but B rejects changed migration identity',()=>{
 const sql=readFileSync(new URL('../../sql/native-versions.sql',import.meta.url),'utf8');
 const output=sql.slice(sql.indexOf("SELECT jsonb_build_object(\n 'postgresVersionNum'"));
 const removed=[...output.slice(output.indexOf("'storage'")).matchAll(/to_jsonb\(m\)-'([^']+)'/g)].map(m=>m[1]);
 assert.deepEqual(removed,['executed_at','executed_at']);
 const fingerprint=row=>digest(JSON.stringify(Object.fromEntries(Object.entries(row).filter(([k])=>!removed.includes(k)).sort())));
 const row={id:0,name:'synthetic',hash:'a'.repeat(40),executed_at:'2000-01-01'},review=approved();
 review.native.storage={count:1,sha256:fingerprint(row)};
 const result=change=>({result:'PHASE_A_NATIVE_CAPTURE_PASSED',productSha:PRODUCT_SHA,toc:{normalizedSha256:review.nativeRestoreTocSha256},
  native:{...review.native,storage:{count:1,sha256:fingerprint({...row,...change})}},sourceStopped:true,targetNativeEmpty:true,targetFilesEmpty:true});
 assertNativeReview(result({executed_at:'2001-01-01'}),review);
 for(const change of [{hash:'b'.repeat(40)},{name:'different'},{id:1}])assert.throws(()=>assertNativeReview(result(change),review),e=>e.code==='B_REVIEW');
});


test('pg_restore classifies the first error without verbose TOC or leaking query identifiers',()=>{
 const canary='PRIVATE_AUTH_IDENTITY_DUMP_SQL_PATH_CANARY';
 const fixture=(message,command='ALTER TABLE public.'+canary+' OWNER TO '+canary+';')=>
  'pg_restore: error: could not execute query: ERROR:  '+message+'\nDETAIL: '+canary+'\nCONTEXT: '+canary+'\nCommand was: '+command+'\n';
 const cases=[
  ['schema "public" already exists','CREATE SCHEMA public;','OBJECT_EXISTS','CREATE_SCHEMA','public',null],
  ['relation "'+canary+'" already exists','CREATE TABLE public.'+canary+' ();','OBJECT_EXISTS','CREATE_TABLE',null,null],
  ['schema "auth" does not exist','ALTER TABLE auth.'+canary+' ADD COLUMN x int;','OBJECT_MISSING','ALTER','auth',null],
  ['permission denied for schema storage','CREATE TABLE storage.'+canary+' ();','PERMISSION_DENIED','CREATE_TABLE','storage',null],
  ['must be owner of extension pg_cron','COMMENT ON EXTENSION pg_cron IS NULL;','OWNER_REQUIRED','COMMENT',null,'pg_cron'],
  ['must be able to SET ROLE "'+canary+'"','ALTER TABLE public.'+canary+' OWNER TO '+canary+';','ROLE_REQUIRED','ALTER',null,null],
  ['must be superuser to create an event trigger','CREATE EVENT TRIGGER '+canary+' ON ddl_command_start EXECUTE FUNCTION x();','SUPERUSER_REQUIRED','CREATE_EVENT_TRIGGER',null,null],
  ['extension "pgjwt" is not available','CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;','EXTENSION_UNAVAILABLE','CREATE_EXTENSION',null,'pgjwt'],
  ['could not open extension control file "'+canary+'": No such file or directory','CREATE EXTENSION pgjwt;','EXTENSION_UNAVAILABLE','CREATE_EXTENSION',null,'pgjwt'],
  ['could not load library "'+canary+'"','CREATE EXTENSION pg_net;','EXTENSION_LIBRARY','CREATE_EXTENSION',null,'pg_net'],
  ['can only create extension in database postgres','CREATE EXTENSION pg_cron;','EXTENSION_PREREQUISITE','CREATE_EXTENSION',null,'pg_cron'],
  ['CREATE INDEX CONCURRENTLY cannot run inside a transaction block','CREATE UNIQUE INDEX '+canary+' ON x(id);','TRANSACTION_RESTRICTION','CREATE_INDEX',null,null],
  ['unrecognized configuration parameter "'+canary+'"','SET '+canary+' = 0;','CONFIGURATION','SET',null,null],
  ['duplicate key value violates unique constraint "'+canary+'"','INSERT INTO auth.users VALUES (\''+canary+'\');','CONSTRAINT','INSERT',null,null],
  ['invalid input syntax for type uuid: "'+canary+'"','COPY auth.users FROM stdin;','DATA','COPY',null,null],
  ['cannot drop extension "'+canary+'" because other objects depend on it','ALTER EXTENSION x DROP TABLE y;','DEPENDENCY','ALTER',null,null],
  ['out of shared memory','CREATE TABLE public.'+canary+' ();','RESOURCE','CREATE_TABLE',null,null],
  ['server closed the connection unexpectedly','CREATE TABLE public.'+canary+' ();','CONNECTION','CREATE_TABLE',null,null],
  [canary,'SELECT '+canary+'();','SQL_OTHER','SELECT',null,null],
 ];
 for(const [message,command,category,expectedCommand,schema,extension]of cases){
  const result=classifyPgRestoreStderr(Buffer.from(fixture(message,command)));
  assert.deepEqual(result,{schemaVersion:1,parser:'FIRST_ERROR',inputTruncated:false,category,command:expectedCommand,schema,extension,
   missingObjectType:category==='OBJECT_MISSING'?'SCHEMA':null,missingRole:null});
  assert.ok(!JSON.stringify(result).includes(canary));
  assert.deepEqual(projectPgRestoreDiagnostic({...result,sql:canary,message:canary,raw:canary}),result);
 }
 const copy=classifyPgRestoreStderr('pg_restore: error: COPY failed for table "'+canary+'": ERROR:  duplicate key value violates unique constraint "'+canary+'"\nDETAIL: '+canary+'\n');
 assert.equal(copy.category,'CONSTRAINT');assert.equal(copy.command,'COPY');
 const first=fixture('must be owner of schema public','ALTER SCHEMA public OWNER TO '+canary+';');
 const later=fixture('schema "auth" already exists','CREATE SCHEMA auth;');
 assert.deepEqual(classifyPgRestoreStderr(first+later),classifyPgRestoreStderr(first));
});

test('pg_restore unknown malformed oversized and injected diagnostics remain closed',()=>{
 const canary='PRIVATE_AUTH_IDENTITY_DUMP_SQL_PATH_CANARY';
 for(const [message,expected]of [
  ['unsupported version (99.99) in file header','ARCHIVE_FORMAT'],
  ['did not find magic string in file header','ARCHIVE_FORMAT'],
  ['could not read from input file: '+canary,'ARCHIVE_READ'],
  ['unexpected end of file','ARCHIVE_READ'],
  ['connection to server on socket "'+canary+'" failed: '+canary,'CONNECTION'],
  [canary,'UNKNOWN']]){
  const result=classifyPgRestoreStderr('pg_restore: error: '+message+'\n');
  assert.equal(result.category,expected);assert.ok(!JSON.stringify(result).includes(canary));
 }
 for(const v of [undefined,null,{},[],true,1])assert.equal(classifyPgRestoreStderr(v).parser,'INVALID_INPUT');
 assert.equal(classifyPgRestoreStderr('').parser,'EMPTY');assert.equal(classifyPgRestoreStderr(Buffer.alloc(0)).parser,'EMPTY');
 for(const text of ['ERROR: schema "public" already exists','pg_restore: warning: '+canary,' '+ 'pg_restore: error: '+canary,'erreur : '+canary])
  assert.equal(classifyPgRestoreStderr(text).parser,'NO_PRIMARY_ERROR');
 const sql='pg_restore: error: could not execute query: ERROR:  '+canary+'\n';
 const injected=sql+'DETAIL: schema "public" already exists\nHINT: permission denied for schema auth\nCONTEXT: '+canary+'\nCommand was: SELECT '+canary+'\nCommand was: CREATE SCHEMA auth;\n';
 const result=classifyPgRestoreStderr(injected);assert.equal(result.category,'SQL_OTHER');assert.equal(result.command,'UNKNOWN');
 assert.equal(result.schema,null);assert.equal(result.extension,null);
 const unknown=classifyPgRestoreStderr('pg_restore: error: could not execute query: ERROR:  schema "'+canary+'" already exists\nCommand was: CREATE SCHEMA "'+canary+'";\n');
 assert.equal(unknown.schema,null);assert.ok(!JSON.stringify(unknown).includes(canary));
 const oversized=sql+'x'.repeat(128*1024)+'\nCommand was: CREATE SCHEMA auth;';
 const bounded=classifyPgRestoreStderr(oversized);assert.equal(bounded.inputTruncated,true);assert.equal(bounded.command,'UNKNOWN');
 const late='x'.repeat(64*1024)+'\npg_restore: error: unsupported version';
 assert.equal(classifyPgRestoreStderr(late).parser,'NO_PRIMARY_ERROR');
 assert.deepEqual(projectPgRestoreDiagnostic({parser:canary,inputTruncated:canary,category:canary,command:canary,schema:canary,extension:canary,raw:canary}),
  {schemaVersion:1,parser:'INVALID_INPUT',inputTruncated:false,category:'UNKNOWN',command:'UNKNOWN',schema:null,extension:null,missingObjectType:null,missingRole:null});
});

test('pg_restore missing-object hints distinguish GRANT failures without exporting identifiers',async()=>{
 const canary='PRIVATE_ROLE_RELATION_FUNCTION_IDENTIFIER_CANARY';
 const fixture=message=>'pg_restore: error: could not execute query: ERROR:  '+message+'\nCommand was: GRANT ALL ON TABLE public.'+canary+' TO anon;\n';
 for(const type of ['schema','relation','type','function','role','extension','operator','collation']){
  const suffix=type==='function'?'(uuid)':'';
  const result=classifyPgRestoreStderr(fixture(type+' "'+canary+'"'+suffix+' does not exist'));
  assert.equal(result.category,'OBJECT_MISSING');assert.equal(result.command,'GRANT');
  assert.equal(result.missingObjectType,type.toUpperCase());assert.equal(result.missingRole,null);
  assert.ok(!JSON.stringify(result).includes(canary));
 }
 for(const role of ['postgres','supabase_admin','anon','authenticated','service_role','authenticator','pgbouncer',
  'supabase_auth_admin','supabase_functions_admin','supabase_storage_admin']){
  for(const name of [role,'"'+role+'"']){
   const result=classifyPgRestoreStderr(fixture('role '+name+' does not exist'));
   assert.equal(result.missingObjectType,'ROLE');assert.equal(result.missingRole,role);
   assert.deepEqual(projectPgRestoreDiagnostic({...result,raw:canary,sql:canary,role:canary}),result);
  }
 }
 for(const name of ['"anon_'+canary+'"','"anon""'+canary+'"','"'+canary+'"']){
  const result=classifyPgRestoreStderr(fixture('role '+name+' does not exist'));
  assert.equal(result.missingRole,null);assert.ok(!JSON.stringify(result).includes(canary));
 }
 for(const [message,schema]of [
  ['relation "net.'+canary+'" does not exist','net'],
  ['schema "net" does not exist','net'],
  ['function net.synthetic(text, uuid) does not exist','net'],
  ['function "auth"."synthetic"(uuid) does not exist','auth'],
  ['relation "private.synthetic" does not exist','private'],
  ['relation "'+canary+'.synthetic" does not exist',null],
  ['function '+canary+'.synthetic(uuid) does not exist',null],
  ['relation "net_'+canary+'.synthetic" does not exist',null],
  ['relation "'+canary+'" does not exist',null],
 ]){
  const result=classifyPgRestoreStderr(fixture(message));assert.equal(result.schema,schema);
  assert.ok(!JSON.stringify(result).includes(canary));assert.ok(!JSON.stringify(result).includes('synthetic'));
  assert.ok(!JSON.stringify(result).includes('uuid'));
 }
 const first=fixture('relation "'+canary+'" does not exist');
 const later=fixture('role "anon" does not exist');
 assert.deepEqual(classifyPgRestoreStderr(first+later),classifyPgRestoreStderr(first));
 const injected=first+'DETAIL: role "anon" does not exist\nHINT: relation "net.synthetic" does not exist\n';
 assert.equal(classifyPgRestoreStderr(injected).missingObjectType,'RELATION');
 assert.equal(classifyPgRestoreStderr(injected).missingRole,null);assert.equal(classifyPgRestoreStderr(injected).schema,null);
 const valid={parser:'FIRST_ERROR',category:'OBJECT_MISSING',missingObjectType:'ROLE',missingRole:'anon'};
 for(const change of [{parser:'EMPTY'},{category:'PERMISSION_DENIED'},{missingObjectType:canary},{missingObjectType:'RELATION'},{missingRole:canary}]){
  const result=projectPgRestoreDiagnostic({...valid,...change,raw:canary,schema:canary});
  assert.equal(result.missingRole,null);assert.equal(result.schema,null);assert.ok(!JSON.stringify(result).includes(canary));
 }
 const bounded=classifyPgRestoreStderr(first+'x'.repeat(64*1024)+later);
 assert.equal(bounded.inputTruncated,true);assert.equal(bounded.missingObjectType,'RELATION');assert.equal(bounded.missingRole,null);
 const {runtimeFailure}=await import('../main.mjs');
 for(const message of ['role "anon" does not exist','relation "net.'+canary+'" does not exist']){
  const diagnostic=classifyPgRestoreStderr(fixture(message));
  const result=runtimeFailure({code:'B_CALL',restoreCall:{operation:'TARGET_ARCHIVE_RESTORE',exitCode:1,signal:null,systemError:null,pgRestore:{...diagnostic,raw:canary}}},'restore');
  assert.deepEqual(result.restoreCall.pgRestore,diagnostic);assert.equal(result.restored,false);assert.equal(result.appVerified,false);
  assert.equal(result.readyForNationalLaunch,false);assert.ok(!JSON.stringify(result).includes(canary));
 }
});

test('pg_restore diagnostic is gated to archive restore and reprojected by the actual public bridge',async()=>{
 const {runtimeFailure}=await import('../main.mjs');
 const canary='PRIVATE_AUTH_IDENTITY_DUMP_SQL_PATH_CANARY';
 const pgRestore=classifyPgRestoreStderr('pg_restore: error: could not execute query: ERROR:  schema "auth" already exists\nCommand was: CREATE SCHEMA auth;\n');
 const error={code:'B_CALL',diagnostic:{sqlstate:'42501',line:2},restoreCall:{operation:'TARGET_ARCHIVE_RESTORE',exitCode:1,signal:null,systemError:null,pgRestore:{...pgRestore,raw:canary}}};
 const result=runtimeFailure(error,'restore');
 assert.deepEqual(result.restoreCall.pgRestore,pgRestore);assert.equal(result.code,'B_CALL');assert.equal(result.sqlstate,'42501');assert.equal(result.sqlLine,2);
 assert.equal(result.restored,false);assert.equal(result.appVerified,false);assert.equal(result.readyForNationalLaunch,false);assert.ok(!JSON.stringify(result).includes(canary));
 for(const operation of RESTORE_CALL_OPERATIONS.filter(v=>!['TARGET_ARCHIVE_RESTORE','TARGET_ARCHIVE_TOC_READ','TARGET_ARCHIVE_SQL_EXPORT'].includes(v)))
  assert.equal(projectRestoreCall({...error.restoreCall,operation}).pgRestore,undefined);
 assert.equal(runtimeFailure(error,'browser_target').restoreCall,undefined);
 assert.equal(runtimeFailure({...error,code:'B_FAILED'},'restore').restoreCall,undefined);
});

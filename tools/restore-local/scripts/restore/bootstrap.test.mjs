import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createServer,request} from 'node:http';
import {makePlan,validatePlan,validateInspection,gateway,runName,main,FORBIDDEN,verifySources,assertAbsent,projectContainers,projectProcessFailure,publicFailure,classifyHealthOutput} from './bootstrap.mjs';
const run='jolene-restore-drill-unittest',lock=JSON.parse(readFileSync(new URL('../../images.lock.json',import.meta.url)));
const secrets={source:{password:'SOURCE_PASSWORD_CANARY',jwt:'SOURCE_JWT_CANARY'},target:{password:'TARGET_PASSWORD_CANARY',jwt:'TARGET_JWT_CANARY'}};
const plan=()=>makePlan(run,'/tmp/private-plan',lock,secrets);
const clone=structuredClone;
function inspection(p){
 const network={Name:run+'-network',Internal:true,Labels:{'org.jolene.restore-drill':run},Driver:'bridge',Attachable:false,EnableIPv6:false,Containers:{}};
 const containers=Object.values(p.services).map((s,i)=>({Id:'unit-'+i,Name:'/'+s.container_name,Config:{Labels:s.labels,Image:s.image},NetworkSettings:{Networks:{[network.Name]:{}}},HostConfig:{PortBindings:{},CapAdd:null,NetworkMode:network.Name},Mounts:(s.volumes??[]).map(v=>v.type==='bind'?{Type:'bind',Source:v.source,Destination:v.target,RW:false}:{Type:'volume',Name:p.volumes[v.source].name,Destination:v.target,RW:true}),State:{Status:'running',Health:{Status:'healthy'}}}));
 for(const c of containers)network.Containers[c.Id]={};
 const volumes=Object.values(p.volumes).map(v=>({Name:v.name,Labels:v.labels,Driver:'local',Options:null}));
 return {network,containers,volumes};
}
test('actual pinned sources verify; generation creates only ten digest-pinned internal services',()=>{
 verifySources();const p=plan();assert.equal(validatePlan(p,run),true);assert.equal(Object.keys(p.services).length,10);
 assert.equal(new Set(Object.values(p.services).map(s=>s.image)).size,5);assert.equal(Object.keys(p.volumes).length,6);
 assert.notEqual(p.services['source-auth'].environment.GOTRUE_JWT_SECRET,p.services['target-auth'].environment.GOTRUE_JWT_SECRET);
 assert.equal(p.services['source-auth'].environment.GOTRUE_SMTP_HOST,'127.0.0.1');
 assert.equal(p.services['source-auth'].environment.API_EXTERNAL_URL,'http://'+run+'-source-api:8000/auth/v1');
});
test('Storage health URL reaches an actual IPv4-only listener and retains failure responses',async t=>{
 const p=plan(),probes=['source','target'].map(side=>p.services[side+'-storage'].healthcheck);
 for(const probe of probes){
  assert.deepEqual(probe.test.slice(0,-1),['CMD','wget','--no-verbose','--tries=1','--spider']);
  const u=new URL(probe.test.at(-1));assert.equal(u.protocol,'http:');assert.equal(u.hostname,'127.0.0.1');assert.equal(u.port,'5000');assert.equal(u.pathname,'/status');
 }
 let status=200;const observed=[];
 const server=createServer((req,res)=>{observed.push({method:req.method,path:req.url});res.writeHead(status);res.end();});
 await new Promise((ok,no)=>{server.once('error',no);server.listen(0,'127.0.0.1',ok);});
 t.after(()=>new Promise(ok=>server.listening?server.close(ok):ok()));
 const port=server.address().port;
 const getStatus=host=>new Promise((ok,no)=>{const q=request({hostname:host,port,path:'/status',method:'HEAD',timeout:1000},r=>{r.resume();r.once('end',()=>ok(r.statusCode));});q.on('error',no);q.on('timeout',()=>q.destroy(new Error('LOCAL_PROBE_TIMEOUT')));q.end();});
 // Only the ephemeral port is substituted. The generated address, path and HEAD semantics are exercised over real loopback TCP.
 for(const probe of probes)assert.equal(await getStatus(new URL(probe.test.at(-1)).hostname),200);
 assert.deepEqual(observed,[{method:'HEAD',path:'/status'},{method:'HEAD',path:'/status'}]);
 await assert.rejects(getStatus('::1'),{code:'ECONNREFUSED'});
 status=503;assert.equal(await getStatus('127.0.0.1'),503);
 await new Promise(ok=>server.close(ok));await assert.rejects(getStatus('127.0.0.1'),{code:'ECONNREFUSED'});
});
test('all known project references and arbitrary remote run names refuse',()=>{
 for(const ref of FORBIDDEN)assert.throws(()=>runName('jolene-restore-drill-'+ref),/RUN_INVALID/);
 for(const value of ['prod','../elsewhere','https://example.com'])assert.throws(()=>runName(value),/RUN_INVALID/);
});
test('unpinned or ambiguous image lock refuses before Docker',()=>{
 const l=clone(lock);l.images[0].reference=l.images[0].repository+':latest';assert.throws(()=>makePlan(run,'/tmp/unit',l,secrets),/IMAGE_LOCK_INVALID/);
});
for(const [label,mutate]of [
 ['external network',p=>p.networks.isolated.internal=false],['published port',p=>p.services['source-db'].ports=['5432:5432']],
 ['second network',p=>p.services['source-storage'].networks.push('default')],['privilege',p=>p.services['source-api'].privileged=true],
 ['socket',p=>p.services['source-api'].volumes.push({type:'bind',source:'/var/run/docker.sock',target:'/x',read_only:true})],
 ['provider URL',p=>p.services['source-auth'].environment.API_EXTERNAL_URL='https://mejpriaetwgtcstbgfid.supabase.co'],
 ['proxy',p=>p.services['source-rest'].environment.HTTPS_PROXY='http://proxy:8080']])
 test('plan refuses '+label,()=>{const p=plan();mutate(p);assert.throws(()=>validatePlan(p,run));});
test('gateway routes have only local Auth REST Storage, no cross-stack aliases or provider',()=>{
 for(const side of ['source','target']){const g=gateway(run,side,'anon-canary','service-canary');assert.equal(g.services.length,4);
  for(const s of g.services)assert.ok(s.url.startsWith('http://'+run+'-'+side+'-'));
  assert.ok(!JSON.stringify(g).includes('https://'));assert.ok(!JSON.stringify(g).includes('functions/v1'));}
});
test('signed Storage gateway route admits only document GET and HEAD while all original routes stay protected',()=>{
 for(const side of ['source','target']){
  const g=gateway(run,side,'anon-canary','service-canary');
  const signed=g.services.find(s=>s.name==='storage-signed-download-v1');
  assert.equal(signed.url,'http://'+run+'-'+side+'-storage:5000/object/sign/jolene-documents/');
  assert.deepEqual(signed.routes,[{name:'storage-signed-download-v1',strip_path:true,methods:['GET','HEAD'],paths:['/storage/v1/object/sign/jolene-documents/']}]);
  assert.deepEqual(signed.plugins,[{name:'cors'}]);
  for(const role of ['auth','rest','storage']){
   const s=g.services.find(value=>value.name===role+'-v1');
   assert.equal(s.url,'http://'+run+'-'+side+'-'+role+':'+({auth:9999,rest:3000,storage:5000}[role])+'/');
   assert.deepEqual(s.routes,[{name:role+'-v1',strip_path:true,paths:['/'+role+'/v1/']}]);
   assert.deepEqual(s.plugins.map(p=>p.name),['cors','key-auth','request-transformer','acl']);
   assert.deepEqual(s.plugins.find(p=>p.name==='key-auth').config,{hide_credentials:false});
   assert.deepEqual(s.plugins.find(p=>p.name==='acl').config,{hide_groups_header:true,allow:['anon','admin']});
  }
 }
});
test('inspection accepts a unit fixture (not a Docker runtime proof)',()=>{
 const p=plan(),i=inspection(p);assert.equal(validateInspection(p,i.network,i.containers,i.volumes),true);
});
for(const [label,mutate]of [
 ['foreign network container',i=>i.network.Containers.foreign={}],['second attachment',i=>i.containers[0].NetworkSettings.Networks.default={}],
 ['lost owner label',i=>i.containers[0].Config.Labels={}],['unhealthy service',i=>i.containers[0].State.Health.Status='unhealthy'],
 ['external volume driver',i=>i.volumes[0].Driver='nfs'],['host volume options',i=>i.volumes[0].Options={device:'/'}],
 ['unexpected bind',i=>i.containers[0].Mounts.push({Type:'bind',Source:'/private',Destination:'/leak',RW:false})],
 ['changed bind source',i=>i.containers[0].Mounts.find(v=>v.Type==='bind').Source='/private'],
 ['published inspect port',i=>i.containers[0].HostConfig.PortBindings={'5432/tcp':[{}]}]])
 test('inspection refuses '+label,()=>{const p=plan(),i=inspection(p);mutate(i);assert.throws(()=>validateInspection(p,i.network,i.containers,i.volumes));});
test('partial cleanup accepts known stopped subset but refuses foreign resources before deletion',()=>{
 const p=plan(),i=inspection(p);i.containers=i.containers.slice(0,2);i.network.Containers=Object.fromEntries(i.containers.map(c=>[c.Id,{}]));i.containers[0].State.Status='exited';i.volumes=i.volumes.slice(0,1);
 assert.equal(validateInspection(p,i.network,i.containers,i.volumes,{partial:true}),true);i.volumes[0].Name='foreign';assert.throws(()=>validateInspection(p,i.network,i.containers,i.volumes,{partial:true}));
});
test('actual file generation has private permissions and public summary contains no credentials',()=>{
 const parent=mkdtempSync(resolve(tmpdir(),'restore-bootstrap-unit-')),dir=resolve(parent,'run');
 const summary=main(['plan',dir,run]);assert.equal(summary.result,'LOCAL_PLAN_ONLY');
 const p=JSON.parse(readFileSync(resolve(dir,'compose.private.json'))),m=readFileSync(resolve(dir,'manifest.json'),'utf8');
 for(const n of ['compose.private.json','source-gateway.private.json','target-gateway.private.json'])assert.equal(statSync(resolve(dir,n)).mode&0o077,0);
 for(const side of ['source','target']){const g=JSON.parse(readFileSync(resolve(dir,side+'-gateway.private.json')));assert.ok(g.consumers[0].keyauth_credentials[0].key===p.services[side+'-storage'].environment.ANON_KEY,'Local anon key mismatch');assert.ok(g.consumers[1].keyauth_credentials[0].key===p.services[side+'-storage'].environment.SERVICE_KEY,'Local service key mismatch');}
 for(const s of ['source','target'])for(const secret of [p.services[s+'-db'].environment.POSTGRES_PASSWORD,p.services[s+'-auth'].environment.GOTRUE_JWT_SECRET,p.services[s+'-storage'].environment.SERVICE_KEY]){assert.ok(!m.includes(secret));assert.ok(!JSON.stringify(summary).includes(secret));}
 assert.throws(()=>main(['plan',dir,run]),/DIRECTORY_MUST_BE_NEW/);
});

test('independent absence uses exact names AND labels, without delete',()=>{
 const calls=[];const r=assertAbsent(run,args=>{calls.push(args);return ''});assert.equal(r.result,'EXACT_RESOURCES_ABSENT');assert.equal(calls.length,6);assert.ok(calls.every(a=>!a.includes('rm')));
 for(const output of [run+'-source-db',run+'-source-data',run+'-network'])assert.throws(()=>assertAbsent(run,()=>output),/RESOURCES_REMAIN/);
 assert.throws(()=>assertAbsent(run,args=>args.includes('--filter')?'unexpected-labelled-object':''),/RESOURCES_REMAIN/);
});

test('diagnostic distinguishes running unhealthy from stopped OOM without logging payload',()=>{
 const p=plan(),i=inspection(p);
 const a=i.containers[0],b=i.containers[1];
 a.State={Status:'running',ExitCode:0,OOMKilled:false,Health:{Status:'unhealthy',FailingStreak:24,Log:[{ExitCode:1,Output:'CANARY_PASSWORD_JWT_URL'}]}};
 b.State={Status:'exited',ExitCode:137,OOMKilled:true,Error:'CANARY_PASSWORD_JWT_URL'};
 a.Config.Env=['CANARY_PASSWORD_JWT_URL'];
 const d=projectContainers(p,i.containers,i.network);
 assert.equal(d.services[0].state,'running');assert.equal(d.services[0].health,'unhealthy');assert.equal(d.services[0].exit_code,0);assert.equal(d.services[0].health_exit_code,1);assert.equal(d.services[0].oom_killed,false);
 assert.equal(d.services[1].state,'exited');assert.equal(d.services[1].exit_code,137);assert.equal(d.services[1].oom_killed,true);
 assert.ok(!JSON.stringify(d).includes('CANARY'));assert.ok(!JSON.stringify(d).includes('Output'));assert.ok(!JSON.stringify(d).includes('Env'));
});
test('diagnostic handles partial startup and closed unknown enums without raw identifiers',()=>{
 const p=plan(),i=inspection(p);i.containers=i.containers.slice(0,1);i.containers[0].State={Status:'CANARY_SECRET',ExitCode:999,OOMKilled:'CANARY_SECRET',Health:{Status:'CANARY_SECRET',FailingStreak:-1,Log:[{ExitCode:-1,Output:'CANARY_SECRET'}]}};
 i.containers.push({Name:'/CANARY_SECRET',Config:{Env:['CANARY_SECRET']}});
 const d=projectContainers(p,i.containers,null);assert.equal(d.unexpected_labelled_containers,1);assert.equal(d.network_present,false);assert.equal(d.services[0].state,'other');assert.equal(d.services[0].health,'other');assert.equal(d.services[0].exit_code,null);assert.equal(d.services[0].health_exit_code,null);assert.equal(d.services[0].oom_killed,null);assert.equal(d.services[1].present,false);assert.equal(d.services.length,10);assert.ok(!JSON.stringify(d).includes('CANARY'));
});
test('process projection emits only numeric exit/signal enum/timeout',()=>{
 const p=projectProcessFailure({status:1,signal:'SIGTERM',error:{code:'ETIMEDOUT',message:'CANARY_SECRET'},stderr:'CANARY_SECRET',stdout:'CANARY_SECRET',env:{JWT:'CANARY_SECRET'}});
 assert.deepEqual(p,{exit_code:1,signal:'SIGTERM',timed_out:true});
 assert.deepEqual(projectProcessFailure({status:-1,signal:'CANARY_SECRET',error:{code:'CANARY_SECRET'}}),{exit_code:null,signal:'other',timed_out:false});
});
test('untrusted exception message, name, stack and process detail never become public code',()=>{
 const e=Object.assign(new Error('CANARY_SECRET'),{name:'CANARY_SECRET',stack:'CANARY_SECRET',detail:{status:1,stderr:'CANARY_SECRET'}});
 const p=publicFailure(e);assert.equal(p.code,'UNCLASSIFIED_FAILURE');assert.ok(!JSON.stringify(p).includes('CANARY'));assert.equal('process' in p,false);
});
test('known CLI refusal preserves failure and fixed phase',()=>{
 let caught;try{main(['invalid','/tmp/no-run']);}catch(e){caught=e;}
 assert.ok(caught);assert.deepEqual(publicFailure(caught),{result:'REFUSED',code:'COMMAND_INVALID',phase:'read_plan'});
});
test('health output classifies transport, HTTP and executable failures without retaining text',()=>{
 const examples=[
  ["wget: can't connect to remote host: Connection refused",'connection_refused',null],
  ["wget: bad address 'CANARY_SECRET:5000'",'dns_failure',null],
  ['wget: server returned error: HTTP/1.1 503 CANARY_SECRET','http_status',503],
  ['OCI runtime exec failed: exec: "wget": executable file not found in $PATH: CANARY_SECRET','executable_missing',null],
  ["wget: unrecognized option '--CANARY_SECRET'",'invalid_option',null],
  ['wget: download timed out CANARY_SECRET','timeout',null],
  ['wget: permission denied CANARY_SECRET','permission_denied',null],
  ['CANARY_SECRET HTTP/1.1 999','unclassified',null],
  ['', 'no_output',null],
 ];
 for(const [message,category,http_status]of examples){
  const r=classifyHealthOutput(message);assert.deepEqual(r,{category,http_status,loopback_family:'not_observed'});assert.ok(!JSON.stringify(r).includes('CANARY'));
 }
 assert.deepEqual(classifyHealthOutput({Output:'CANARY_SECRET'}),{category:'no_output',http_status:null,loopback_family:'not_observed'});
});
test('inspection projects only the last healthcheck category, never its body or credentials',()=>{
 const p=plan(),i=inspection(p),secret='CANARY_EMAIL_PASSWORD_JWT_HTTPS_QUERY';
 i.containers[0].State.Health.Log=[{ExitCode:1,Output:'wget: server returned error: HTTP/1.1 500 '+secret},{ExitCode:1,Output:"wget: can't connect to remote host: Connection refused "+secret}];
 const d=projectContainers(p,i.containers,i.network);
 assert.deepEqual(d.services[0].health_output,{category:'connection_refused',http_status:null,loopback_family:'not_observed'});
 assert.ok(!JSON.stringify(d).includes(secret));assert.ok(!JSON.stringify(d).includes('HTTP/'));assert.ok(!JSON.stringify(d).includes('Output'));
 assert.deepEqual(classifyHealthOutput('x'.repeat(4096)+'HTTP/1.1 503 '+secret),{category:'unclassified',http_status:null,loopback_family:'not_observed'});
});
test('loopback family requires a known connection line, not an address mentioned elsewhere',()=>{
 for(const [text,family]of [
  ['Connecting to localhost:5000 ([::1]:5000)\nwget: Connection refused','ipv6'],
  ['Connecting to localhost:5000 (127.0.0.1:5000)\nwget: Connection refused','ipv4'],
  ['Connecting to localhost (localhost)|::1|:5000... failed: Connection refused.','ipv6'],
  ['Connecting to localhost (localhost)|127.0.0.1|:5000... connected.','ipv4'],
  ['Connecting to localhost:5000 ([::1]:5000)\nConnecting to localhost:5000 (127.0.0.1:5000)','both'],
  ['Resolving localhost... ::1, 127.0.0.1\nHTTP/1.1 503 CANARY_SECRET','not_observed'],
  ['response body: Connecting to localhost:5000 ([::1]:5000) CANARY_SECRET','not_observed'],
  ['Connecting to CANARY_SECRET:5000 (192.0.2.1:5000)','not_observed'],
 ]){
  const r=classifyHealthOutput(text);assert.equal(r.loopback_family,family);assert.ok(!JSON.stringify(r).includes('CANARY'));assert.ok(!JSON.stringify(r).includes('::1'));assert.ok(!JSON.stringify(r).includes('127.0.0.1'));
 }
});

test('063 server replacement changes only the two database images in the generated plan',()=>{
 const previous=clone(lock),db=previous.images.find(x=>x.repository==='supabase/postgres');
 db.linux_amd64_digest='sha256:5a4314708484bec672de2c09653a5c01fb1c84a998564ac231b0325e2238ed5b';db.reference='supabase/postgres@'+db.linux_amd64_digest;
 const old=makePlan(run,'/tmp/private-plan',previous,secrets),next=plan();
 for(const side of ['source','target']){assert.notEqual(old.services[side+'-db'].image,next.services[side+'-db'].image);old.services[side+'-db'].image=next.services[side+'-db'].image;}
 assert.deepEqual(next,old);assert.equal(Object.keys(next.volumes).length,6);
 const another=makePlan(run+'-next','/tmp/private-next',lock,secrets);
 const names=new Set(Object.values(next.volumes).map(x=>x.name));assert.ok(Object.values(another.volumes).every(x=>!names.has(x.name)));
 for(const resource of ['source-data','source-config','source-files','target-data','target-config','target-files'])assert.throws(()=>assertAbsent(run,()=>run+'-'+resource),/RESOURCES_REMAIN/);
});

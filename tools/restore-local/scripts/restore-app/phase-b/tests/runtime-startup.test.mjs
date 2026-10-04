import test from 'node:test';
import assert from 'node:assert/strict';
import cp from 'node:child_process';
import crypto from 'node:crypto';
import {syncBuiltinESMExports} from 'node:module';
import {mkdtempSync,readFileSync,readdirSync,lstatSync,writeFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {preparePlan,localRuntime} from '../../local-runtime.mjs';
import {nativeRuntime} from '../native-runtime.mjs';
const run='jolene-restore-drill-987654-1';
function fixture(t){
 const parent=realpathSync(mkdtempSync(join(tmpdir(),'restore-b-startup-')));t.after(()=>rmSync(parent,{recursive:true,force:true}));
 const directory=join(parent,'stack');preparePlan(directory,run);
 return{directory,plan:JSON.parse(readFileSync(join(directory,'compose.private.json'),'utf8'))};
}
function mocks(t,spawn){
 t.mock.method(cp,'spawnSync',spawn);let uuid=0;
 t.mock.method(crypto,'randomUUID',()=>`00000000-0000-4000-8000-${String(++uuid).padStart(12,'0')}`);
 syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
}
function output(value,status=0,stderr='SYNTHETIC_PRIVATE_DIAGNOSTIC'){
 return{stdout:Buffer.from(typeof value==='string'?value:JSON.stringify(value)),stderr:Buffer.from(stderr),status,signal:null};
}
test('actual localRuntime keeps build native diagnose cleanup evidence across repeated instances',t=>{
 const{directory}=fixture(t);let calls=0,failed=false;
 mocks(t,(command,args)=>{assert.equal(command,'docker');assert.deepEqual(args,['context','inspect']);calls++;
  return output([{Endpoints:{docker:{Host:'unix:///synthetic.sock'}}}],failed?1:0,'synthetic-'+calls);});
 localRuntime(directory);const first=readdirSync(directory).filter(n=>n.endsWith('.stderr.private'));assert.equal(first.length,1);
 const original=readFileSync(join(directory,first[0]));
 const legacy=join(directory,'command-1.stderr.private');if(!readdirSync(directory).includes('command-1.stderr.private'))writeFileSync(legacy,'old-proof',{mode:0o600,flag:'wx'});
 const legacyBytes=readFileSync(legacy);
 for(const phase of ['native','diagnose','cleanup','cleanup-again']){assert.ok(phase);localRuntime(directory);}
 failed=true;assert.throws(()=>localRuntime(directory),/RESTORE_LOCAL_COMMAND_FAILED/);failed=false;localRuntime(directory);
 assert.equal(calls,7);assert.deepEqual(readFileSync(join(directory,first[0])),original);assert.deepEqual(readFileSync(legacy),legacyBytes);
 const names=readdirSync(directory).filter(n=>n.endsWith('.stderr.private'));assert.equal(names.length,8);
 assert.equal(names.filter(n=>/^command-[a-f0-9-]{36}-1\.stderr\.private$/.test(n)).length,7);
 for(const name of names){const stat=lstatSync(join(directory,name));assert.equal(stat.mode&0o777,0o600);assert.equal(stat.nlink,1);}
});
function dockerFixture(t,{sequence=['starting','starting','healthy'],exited=false,drift=false}={}){
 const {directory,plan}=fixture(t),events=[];let healthyReads=0,sleeps=0;
 const containers=Object.values(plan.services).map((s,i)=>({Id:'native'+i,Name:'/'+s.container_name,
  Config:{Labels:s.labels,Image:s.image,Env:Object.entries(s.environment).map(([k,v])=>k+'='+v),Cmd:s.command},
  NetworkSettings:{Networks:{[run+'-network']:{}}},
  HostConfig:{PortBindings:{},CapAdd:null,NetworkMode:run+'-network',LogConfig:{Type:'none'}},
  Mounts:(s.volumes??[]).map(v=>v.type==='bind'?{Type:'bind',Source:v.source,Destination:v.target,RW:false}:{Type:'volume',Name:plan.volumes[v.source].name,Destination:v.target,RW:true}),
  State:{Status:s.container_name===run+'-target-db'?'running':'exited',Health:{Status:'healthy'},OOMKilled:false}}));
 const db=containers.find(c=>c.Name===`/${run}-source-db`);
 const network={Name:run+'-network',Internal:true,Labels:{'org.jolene.restore-drill':run},Driver:'bridge',Attachable:false,EnableIPv6:false,Containers:{}};
 const volumes=Object.values(plan.volumes).map(v=>({Name:v.name,Labels:v.labels,Driver:'local',Options:null}));
 mocks(t,(command,args)=>{
  assert.equal(command,'docker');
  if(args[0]==='context'){assert.deepEqual(args,['context','inspect']);return output([{Endpoints:{docker:{Host:'unix:///synthetic.sock'}}}]);}
  if(args[0]==='ps')return output(containers.map(c=>c.Name.slice(1)).join('\n'));
  if(args[0]==='network'){assert.deepEqual(args,['network','inspect',run+'-network']);return output([network]);}
  if(args[0]==='volume'){assert.deepEqual(args,['volume','inspect',...Object.values(plan.volumes).map(v=>v.name)]);return output(volumes);}
  if(args[0]==='inspect'){
   if(args.length===2){assert.equal(args[1],run+'-source-db');const state=sequence[Math.min(healthyReads++,sequence.length-1)];db.State.Health.Status=state;events.push('db-health:'+state);return output([db]);}
   assert.deepEqual(args.slice(1),containers.map(c=>c.Name.slice(1)));events.push('full-plan');return output(containers);
  }
  if(args[0]==='start'){
   assert.equal(args.length,2);const c=containers.find(c=>c.Name==='/'+args[1]);assert.ok(c);
   if(c===db){events.push('start-db');db.State.Status=exited?'exited':'running';db.State.Health.Status='starting';if(drift)network.Internal=false;}
   else{assert.equal(db.State.Health.Status,'healthy','TEST_API_BEFORE_DATABASE_HEALTHY');events.push('start-api');c.State.Status='running';c.State.Health.Status='healthy';}
   return output('');
  }
  if(args[0]==='exec'){assert.equal(args[1],run+'-source-storage');assert.equal(args[2],'node');events.push('api-health');return output({healthy:true,httpStatus:200});}
  assert.fail('UNEXPECTED_DOCKER_STUB_CALL');
 });
 t.mock.method(globalThis,'setTimeout',(callback,ms)=>{assert.equal(ms,2000);sleeps++;queueMicrotask(callback);return 0;});
 return{directory,events,run:()=>nativeRuntime(directory).startSourceForUi(),healthReads:()=>healthyReads,sleeps:()=>sleeps};
}
test('actual native startup waits for DB healthy and complete plan before any API',async t=>{
 const h=dockerFixture(t);await h.run();assert.equal(h.healthReads(),3);assert.equal(h.sleeps(),2);
 assert.ok(h.events.indexOf('start-api')>h.events.indexOf('db-health:healthy'));
 for(let i=0;i<h.events.length;i++)if(h.events[i].startsWith('db-health:'))assert.equal(h.events[i-1],'full-plan');
 assert.equal(h.events.filter(v=>v==='start-api').length,4);
});
for(const [name,options,code]of [
 ['exited DB',{exited:true},'RESTORE_SERVICE_STATE'],
 ['unhealthy DB',{sequence:['unhealthy']},'B_DATABASE_READINESS'],
 ['DB timeout',{sequence:['starting']},'B_DATABASE_READINESS_TIMEOUT'],
 ['changed plan',{drift:true},'NETWORK_INSPECTION_REFUSED']
])test('actual native startup refuses '+name+' without starting APIs',async t=>{
 const h=dockerFixture(t,options);await assert.rejects(h.run,e=>e.code===code||e.publicCode===code||e.message===code);
 assert.equal(h.events.includes('start-api'),false);assert.equal(h.events.includes('api-health'),false);
 if(name==='DB timeout'){assert.equal(h.healthReads(),60);assert.equal(h.sleeps(),59);}
});

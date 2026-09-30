import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {makePlan,validatePlan,validateInspection,gateway,runName,main,FORBIDDEN,verifySources,assertAbsent} from './bootstrap.mjs';
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
 for(const side of ['source','target']){const g=gateway(run,side,'anon-canary','service-canary');assert.equal(g.services.length,3);
  for(const s of g.services)assert.ok(s.url.startsWith('http://'+run+'-'+side+'-'));
  assert.ok(!JSON.stringify(g).includes('https://'));assert.ok(!JSON.stringify(g).includes('functions/v1'));}
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

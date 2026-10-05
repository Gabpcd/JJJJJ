import test from 'node:test';
import assert from 'node:assert/strict';
import cp from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, realpathSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { preparePlan } from '../../local-runtime.mjs';
import { captureSource } from '../../snapshot-restore.mjs';
import { nativeRuntime, SETTINGS_SQL } from '../native-runtime.mjs';
import { CATALOGUE_PRIVATE_KEY } from '../catalogue-facts-diagnostic.mjs';
import { closedFailure } from '../contract.mjs';
import { input as graphqlInput } from './graphql-test-fixture.mjs';
import { b21Fixture,v2Fixture,PRIVATE_CANARY } from './catalogue-semantics-fixture.mjs';

// Every child process is replaced before nativeRuntime construction. No Docker,
// database, browser, network or native process is run by these tests.
function harness(t,{targetHash='b',targetState='off',targetFacts=true,b21=false,v2=false,probeAnchorDrift=false,probeFailure=false,probeBindingDrift=false}={}) {
 const parent=realpathSync(mkdtempSync(join(tmpdir(),'catalogue-b20-pure-')));t.after(()=>rmSync(parent,{recursive:true,force:true}));
 const directory=join(parent,'stack'),run='jolene-restore-drill-987654-1';preparePlan(directory,run);
 const plan=JSON.parse(readFileSync(join(directory,'compose.private.json'),'utf8')),events=[],graphql=graphqlInput();
 const canary='PRIVATE_B20_RAW_DEFINITION_AND_ACL_IDENTITY',b21f=v2?v2Fixture():b21Fixture();let sourceOff=false;
 const containers=Object.values(plan.services).map((s,i)=>({Id:'synthetic'+i,Name:'/'+s.container_name,
  Config:{Labels:s.labels,Image:s.image,Env:Object.entries(s.environment).map(([k,v])=>k+'='+v),Cmd:s.command},
  NetworkSettings:{Networks:{[run+'-network']:{}}},HostConfig:{PortBindings:{},CapAdd:null,NetworkMode:run+'-network',LogConfig:{Type:'none'}},
  Mounts:(s.volumes??[]).map(v=>v.type==='bind'?{Type:'bind',Source:v.source,Destination:v.target,RW:false}:{Type:'volume',Name:plan.volumes[v.source].name,Destination:v.target,RW:true}),
  State:{Status:s.container_name.endsWith('-db')?'running':'exited',Health:{Status:'healthy'},OOMKilled:false}}));
 const network={Name:run+'-network',Internal:true,Labels:{'org.jolene.restore-drill':run},Driver:'bridge',Attachable:false,EnableIPv6:false,Containers:{}};
 const volumes=Object.values(plan.volumes).map(v=>({Name:v.name,Labels:v.labels,Driver:'local',Options:null}));
 const output=v=>({stdout:Buffer.from(typeof v==='string'?v:JSON.stringify(v)),stderr:Buffer.alloc(0),status:0,signal:null});
 t.mock.method(cp,'spawnSync',(command,args,options)=>{
  assert.equal(command,'docker');
  if(args[0]==='context')return output([{Endpoints:{docker:{Host:'unix:///synthetic.sock'}}}]);
  if(args[0]==='ps')return output(containers.map(c=>c.Name.slice(1)).join('\n'));
  if(args[0]==='inspect')return output(containers);
  if(args[0]==='network')return output([network]);
  if(args[0]==='volume')return output(volumes);
  if(args[0]==='stop'){
   for(const name of args.slice(3)){const c=containers.find(c=>c.Name==='/'+name);assert.ok(c);c.State.Status='exited';}
   if(args.includes(run+'-source-db')){sourceOff=true;events.push('source-off');if(targetState!=='off')containers.find(c=>c.Name==='/'+run+'-source-db').State.Status='running';}
   return output('');
  }
  if(args[0]==='cp'){
   assert.equal(args[2],run+'-source-storage:/var/lib/storage/.');writeFileSync(join(args[3],'one'),'synthetic');writeFileSync(join(args[3],'two'),'synthetic');return output('');
  }
  assert.equal(args[0],'exec');assert.equal(args[1],'-i');const side=args[2]===run+'-source-db'?'source':'target';
  assert.equal(args[2],run+'-'+side+'-db');if(sourceOff)assert.equal(side,'target','SOURCE_REREAD_AFTER_STOP');
  if(args[3]==='pg_dump'){events.push('dump');assert.equal(side,'source');assert.deepEqual(args.slice(4),['-Fc','--no-password','-U','supabase_admin','-h','/var/run/postgresql','-d','jolene_candidatures_pg17_test']);return output(graphql.archive.toString());}
  if(args[3]==='pg_restore'){assert.deepEqual(args.slice(4),['--list']);return output(graphql.toc.toString());}
  assert.equal(args[3],'psql');const sql=options.input.toString();
  assert.equal(args[args.indexOf('-U')+1],'postgres');assert.equal(args[args.indexOf('-h')+1],'/var/run/postgresql');
  if(sql.includes('WITH expression_objects AS')){
   if(!b21)throw Error('SYNTHETIC_NO_B21_CAPTURE');events.push(side+'-b21-probe');
   if(probeFailure)return{...output(''),status:1,stderr:Buffer.from(PRIVATE_CANARY+'_stderr')};
   const p=structuredClone(side==='source'?b21f.sourceProbe:b21f.targetProbe);
   if(probeAnchorDrift)p.anchor.catalogue_sha256='c'.repeat(64);
   if(probeBindingDrift&&side==='source')p.fixed.expressions[0].bindings.columns[0][1]=PRIVATE_CANARY+'_qualified_type';
   return output([p.anchor,p.current,p.fixed].map(JSON.stringify).join('\n'));
  }
  if(sql.includes(CATALOGUE_PRIVATE_KEY)){
   events.push(side+'-catalogue');if(side==='target')assert.equal(sourceOff,true);
   if(b21)return output({...b21f[side],[CATALOGUE_PRIVATE_KEY]:b21f[side+'Facts']});
   const facts={schemaVersion:1,status:'COMPLETE',facts:[['function',canary,[canary,'postgres',side==='source'?['a=r/b','c=r/b']:['c=r/b','a=r/b']],
    [['ROLE','a','b','SELECT',false],['ROLE','c','b','SELECT',false]]]]};
   return output({catalogue_sha256:(side==='source'?'a':targetHash).repeat(64),database:[],roles:[],memberships:[],
    ...((side==='source'||targetFacts)?{[CATALOGUE_PRIVATE_KEY]:facts}:{})});
  }
  if(sql===SETTINGS_SQL)return output([]);
  if(sql.includes('wrapperSchemaRawFingerprint'))return output(graphql.witness);
  assert.equal(sql,'SYNTHETIC_CHECKPOINT');return output({checkpoint:true});
 });
 syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});
 const runtime=nativeRuntime(directory),snapshotDir=join(directory,'snapshot');mkdirSync(snapshotDir,{mode:0o700});
 return{runtime,directory,snapshotDir,events,canary,capture:()=>captureSource(runtime,snapshotDir,'SYNTHETIC_CHECKPOINT')};
}
test('actual capture/runtime keeps source facts in memory before dump and compares target only after source off',async t=>{
 const h=harness(t),snapshot=await h.capture();assert.ok(h.events.indexOf('source-catalogue')<h.events.indexOf('dump'));
 for(const v of [JSON.stringify(snapshot),readFileSync(join(h.snapshotDir,'snapshot.private.json'),'utf8')]){
  assert.ok(!v.includes(CATALOGUE_PRIVATE_KEY));assert.ok(!v.includes(h.canary));
 }
 assert.equal(Object.getOwnPropertySymbols(snapshot.catalogue).length,0);assert.deepEqual(Object.keys(snapshot.catalogue),['catalogue_sha256','database','roles','memberships','databaseRoleSettings','nativeGraphql']);
 await h.runtime.stopSource();await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),error=>{
  const v=closedFailure(error,'restore');assert.equal(v.code,'B_RESTORE');assert.deepEqual(v.restoreInvariant.catalogue.sections,['catalogue_sha256']);
  assert.equal(v.restoreInvariant.catalogue.facts.status,'COMPLETE');assert.equal(v.restoreInvariant.catalogue.facts.kinds.find(k=>k.kind==='function').acl.orderOnlyCount,1);
  assert.equal(v.readyForNationalLaunch,false);assert.equal(v.restored,false);assert.equal(v.appVerified,false);assert.ok(!JSON.stringify(v).includes(h.canary));return true;
 });
 assert.deepEqual(h.events,['source-catalogue','dump','source-off','target-catalogue']);
});
test('missing run-local capture is closed and does not replace the original mismatch',async t=>{
 const h=harness(t),snapshot=await h.capture();await h.runtime.stopSource();
 const reloaded=JSON.parse(JSON.stringify(snapshot));await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(reloaded),error=>{
  const v=closedFailure(error,'restore');assert.equal(v.code,'B_RESTORE');assert.equal(v.restoreInvariant.catalogue.facts.status,'NOT_CAPTURED');return true;
 });
});
test('missing target facts cannot bypass a rejection',async t=>{
 const h=harness(t,{targetFacts:false}),snapshot=await h.capture();await h.runtime.stopSource();
 await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),error=>{
  const v=closedFailure(error,'restore');assert.equal(v.code,'B_RESTORE');assert.equal(v.restoreInvariant.catalogue.facts.status,'NOT_CAPTURED');return true;
 });
});
test('equal original catalogues still pass the unchanged predicate without diagnostic capture',async t=>{
 const h=harness(t,{targetHash:'a',targetFacts:false}),snapshot=await h.capture();await h.runtime.stopSource();
 const result=await h.runtime.assertSourceOffAndTargetCatalogExact(snapshot);assert.equal(result.nativeGraphqlRestoredExact,true);
 // A diagnostic is not a second acceptance rule and is not evaluated on pass.
});
test('source-off guard rejects before reading target catalogue when source is running',async t=>{
 const h=harness(t,{targetState:'running'}),snapshot=await h.capture();await h.runtime.stopSource();
 await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),error=>error.message==='RESTORE_SERVICE_STATE'||error.publicCode==='RESTORE_SERVICE_STATE');
 assert.ok(!h.events.includes('target-catalogue'));
});
test('B21 actual runtime anchors private source/target probes and publishes only closed counters',async t=>{
 const h=harness(t,{b21:true}),snapshot=await h.capture();await h.runtime.stopSource();
 await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),error=>{
  const v=closedFailure(error,'restore');assert.equal(v.code,'B_RESTORE');assert.equal(v.restoreInvariant.catalogue.semantics.status,'COMPLETE');
  assert.equal(v.restoreInvariant.catalogue.semantics.acl.equalCount,16);assert.ok(!JSON.stringify(v).includes(PRIVATE_CANARY));return true;
 });
 assert.deepEqual(h.events,['source-catalogue','source-b21-probe','dump','source-off','target-catalogue','target-b21-probe']);
 assert.ok(!JSON.stringify(snapshot).includes(PRIVATE_CANARY));
 for(const file of readdirSync(h.directory,{recursive:true,withFileTypes:true}).filter(d=>d.isFile())){
  assert.ok(!readFileSync(join(file.parentPath??file.path,file.name)).includes(Buffer.from(PRIVATE_CANARY)));
 }
 const n=h.events.length;await assert.rejects(()=>h.runtime.catalogue('source'),e=>e.code==='B_CONTEXT');assert.equal(h.events.length,n);
});
test('B21 anchor drift is a closed diagnostic while the original mismatch still refuses',async t=>{
 const h=harness(t,{b21:true,probeAnchorDrift:true}),snapshot=await h.capture();await h.runtime.stopSource();
 await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),e=>{
  const v=closedFailure(e,'restore');assert.equal(v.code,'B_RESTORE');assert.equal(v.restoreInvariant.catalogue.semantics.status,'ANCHOR_MISMATCH');return true;
 });
});
test('B21 failed native capture discards stdout/stderr and cannot replace the original refusal',async t=>{
 const h=harness(t,{b21:true,probeFailure:true}),snapshot=await h.capture();await h.runtime.stopSource();
 await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),e=>{
  const v=closedFailure(e,'restore');assert.equal(v.code,'B_RESTORE');assert.equal(v.restoreInvariant.catalogue.semantics.status,'CAPTURE_FAILED');return true;
 });
 for(const file of readdirSync(h.directory,{recursive:true,withFileTypes:true}).filter(d=>d.isFile()))assert.ok(!readFileSync(join(file.parentPath??file.path,file.name)).includes(Buffer.from(PRIVATE_CANARY)));
});
test('actual runtime v2 accepts only anchored private object parity and preserves the raw v1 mismatch',async t=>{
 const h=harness(t,{b21:true,v2:true}),snapshot=await h.capture();await h.runtime.stopSource();
 const result=await h.runtime.assertSourceOffAndTargetCatalogExact(snapshot);
 assert.equal(result.catalogueComparison.v1Equal,false);assert.equal(result.catalogueComparison.v2Equal,true);
 assert.equal(result.catalogueComparison.aclNormalizedCount,2);assert.equal(result.catalogueComparison.expressionNormalizedCount,2);
 assert(!JSON.stringify(result).includes(PRIVATE_CANARY));assert(!JSON.stringify(snapshot).includes(PRIVATE_CANARY));
 assert.deepEqual(h.events,['source-catalogue','source-b21-probe','dump','source-off','target-catalogue','target-b21-probe']);
 const reloaded=JSON.parse(JSON.stringify(snapshot));await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(reloaded));
});

test('B23 source anchor detail survives private-row disposal before stop without weakening refusal',async t=>{
 const h=harness(t,{b21:true,v2:true,probeBindingDrift:true}),snapshot=await h.capture();await h.runtime.stopSource();
 await assert.rejects(()=>h.runtime.assertSourceOffAndTargetCatalogExact(snapshot),error=>{
  const v=closedFailure(error,'restore'),c=v.restoreInvariant.catalogue;
  assert.equal(v.code,'B_RESTORE');assert.equal(c.comparison.reason,'ANCHOR');assert.equal(c.comparison.v2Equal,false);
  assert.equal(c.comparison.aclNormalizedCount,0);assert.equal(c.comparison.expressionNormalizedCount,0);
  assert.equal(c.semantics.status,'INCOMPLETE');assert.equal(c.anchors.source.reason,'CURRENT_FIXED');
  assert.equal(c.anchors.source.counters.bindingColumnsDifferentCount,1);assert.equal(c.anchors.source.counters.bindingFactKeysDifferentCount,0);
  assert.deepEqual(c.anchors.target,{schemaVersion:1,status:'COMPLETE',reason:'COMPLETE'});
  assert(!JSON.stringify(v).includes(PRIVATE_CANARY));assert.equal(v.appVerified,false);return true;
 });
 assert.deepEqual(h.events,['source-catalogue','source-b21-probe','dump','source-off','target-catalogue','target-b21-probe']);
 assert(!JSON.stringify(snapshot).includes('anchors'));assert(!JSON.stringify(snapshot).includes(PRIVATE_CANARY));
 for(const file of readdirSync(h.directory,{recursive:true,withFileTypes:true}).filter(d=>d.isFile()))
  assert(!readFileSync(join(file.parentPath??file.path,file.name)).includes(Buffer.from(PRIVATE_CANARY)));
});

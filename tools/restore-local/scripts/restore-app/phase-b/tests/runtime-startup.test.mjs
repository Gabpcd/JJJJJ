import test from 'node:test';
import assert from 'node:assert/strict';
import cp from 'node:child_process';
import crypto from 'node:crypto';
import {syncBuiltinESMExports} from 'node:module';
import {mkdtempSync,mkdirSync,readFileSync,readdirSync,lstatSync,writeFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {preparePlan,localRuntime} from '../../local-runtime.mjs';
import {nativeRuntime} from '../native-runtime.mjs';
import {restoreTarget} from '../restore-target.mjs';
import {fileTree,digest} from '../../snapshot-restore.mjs';
import {closedFailure} from '../contract.mjs';
import {graphqlExportArgs,graphqlTransactionArgs} from '../graphql-restore-plan.mjs';
import {input as graphqlInput} from './graphql-test-fixture.mjs';
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
const exportSequence=['TARGET_TOC_WRITE','TARGET_TOC_READBACK','TARGET_ARCHIVE_SQL_EXPORT','TARGET_TOC_READBACK','TARGET_TOC_REMOVE'];
const restoreSequence=['TARGET_ARCHIVE_TOC_READ',...exportSequence,...exportSequence,'TARGET_DATABASE_RECREATE','TARGET_SQL_RESTORE','TARGET_ROLE_SETTINGS','TARGET_FILES_COPY_IN'];
for(const failedOperation of [...new Set(restoreSequence),'TOC_BINDING'])test('actual restore attributes first failing native call '+failedOperation,async t=>{
 const {directory,plan}=fixture(t),operations=[],canary='PRIVATE_SQL_AUTH_DUMP_PATH_CANARY';
 let pristineSchemas=null;const lists=new Map(),graphql=graphqlInput();let exports=0;
 const snapshotDir=join(directory,'snapshot');mkdirSync(snapshotDir,{mode:0o700});mkdirSync(join(snapshotDir,'files'),{mode:0o700});
 const dump=graphql.archive;writeFileSync(join(snapshotDir,'database.dump'),dump,{mode:0o600});writeFileSync(join(snapshotDir,'archive-toc.private.txt'),failedOperation==='TOC_BINDING'?Buffer.from(graphql.toc.toString().replace('1; 0 1000 ','77777; 0 1000 ')):graphql.toc,{mode:0o600});
 writeFileSync(join(snapshotDir,'files','synthetic-file'),'synthetic',{mode:0o600});
 const containers=Object.values(plan.services).map((s,i)=>({Id:'native'+i,Name:'/'+s.container_name,
  Config:{Labels:s.labels,Image:s.image,Env:Object.entries(s.environment).map(([k,v])=>k+'='+v),Cmd:s.command},
  NetworkSettings:{Networks:{[run+'-network']:{}}},HostConfig:{PortBindings:{},CapAdd:null,NetworkMode:run+'-network',LogConfig:{Type:'none'}},
  Mounts:(s.volumes??[]).map(v=>v.type==='bind'?{Type:'bind',Source:v.source,Destination:v.target,RW:false}:{Type:'volume',Name:plan.volumes[v.source].name,Destination:v.target,RW:true}),
  State:{Status:s.container_name===run+'-target-db'?'running':'exited',Health:{Status:'healthy'},OOMKilled:false}}));
 const network={Name:run+'-network',Internal:true,Labels:{'org.jolene.restore-drill':run},Driver:'bridge',Attachable:false,EnableIPv6:false,Containers:{}};
 const volumes=Object.values(plan.volumes).map(v=>({Name:v.name,Labels:v.labels,Driver:'local',Options:null}));
 mocks(t,(command,args,options)=>{
  assert.equal(command,'docker');let operation=null;
  if(args[0]==='context')return output([{Endpoints:{docker:{Host:'unix:///synthetic.sock'}}}]);
  if(args[0]==='ps')return output(containers.map(c=>c.Name.slice(1)).join('\n'));
  if(args[0]==='network')return output([network]);
  if(args[0]==='volume')return output(volumes);
  if(args[0]==='inspect')return output(containers);
  if(args[0]==='exec'){
   const targetIndex=args[1]==='-i'?2:1,commandIndex=targetIndex+1;
   assert.equal(args[targetIndex],run+'-target-db');const tool=args[commandIndex];
   if(tool==='sh'){
    operation='TARGET_TOC_WRITE';const script=args.at(-1);assert.match(script,/^umask 077; set -C; cat > \/tmp\/jolene-graphql-(prerequisites|remainder)\.list$/);
    const path=script.split(' > ')[1];assert.equal(lists.has(path),false);lists.set(path,options.input);
   }else if(tool==='cat'){
    operation='TARGET_TOC_READBACK';assert.ok(lists.has(args.at(-1)));
    operations.push(operation);return output(lists.get(args.at(-1)).toString(),operation===failedOperation?1:0,canary);
   }else if(tool==='rm'){
    operation='TARGET_TOC_REMOVE';assert.ok(lists.has(args.at(-1)));lists.delete(args.at(-1));
   }else if(tool==='pg_restore'){
    if(args.at(-1)==='--list'){operation='TARGET_ARCHIVE_TOC_READ';assert.deepEqual(options.input,dump);assert.equal(pristineSchemas,null);operations.push(operation);return output(graphql.toc.toString(),operation===failedOperation?1:0,'pg_restore: error: input file does not appear to be a valid archive');}
    operation='TARGET_ARCHIVE_SQL_EXPORT';const partition=exports++===0?'prerequisites':'remainder';
    assert.deepEqual(args.slice(commandIndex+1),graphqlExportArgs(partition));assert.deepEqual(options.input,dump);
    assert.equal(pristineSchemas,null,'SQL_EXPORT_MUST_PRECEDE_DATABASE_DROP');
    const list=lists.get('/tmp/jolene-graphql-'+partition+'.list').toString();
    assert.equal(list.includes('EVENT TRIGGER - issue_pg_graphql_access'),partition==='prerequisites');
    assert.equal(list.includes('EXTENSION - pg_graphql '),partition==='remainder');
    operations.push(operation);return output('-- synthetic-'+partition+'\nSELECT 1;\n',operation===failedOperation?1:0,
     'pg_restore: error: could not execute query: ERROR:  must be owner of schema public\nCommand was: ALTER SCHEMA public OWNER TO '+canary+';\n');
   }else{
    assert.equal(tool,'psql');const sql=options.input.toString();
    if(sql.startsWith('DROP DATABASE ')){
     assert.equal(exports,2);assert.equal(lists.size,0);
     assert.equal(sql,'DROP DATABASE jolene_candidatures_pg17_test;\nCREATE DATABASE jolene_candidatures_pg17_test OWNER postgres TEMPLATE template0;');
     assert.equal(args[args.indexOf('-d')+1],'postgres');operation='TARGET_DATABASE_RECREATE';
     pristineSchemas=new Map([['pg_catalog',{}],['information_schema',{}],['public',{owner:'pg_database_owner',acl:['owner:UC','PUBLIC:U']}]]);
    }else if(args.includes('--single-transaction')){
     operation='TARGET_SQL_RESTORE';assert.deepEqual(args.slice(commandIndex+1),graphqlTransactionArgs());
     assert.equal(sql,'-- synthetic-prerequisites\nSELECT 1;\n\n-- synthetic-remainder\nSELECT 1;\n\n');
     assert.deepEqual([...pristineSchemas.keys()],['pg_catalog','information_schema','public']);
     assert.deepEqual(pristineSchemas.get('public'),{owner:'pg_database_owner',acl:['owner:UC','PUBLIC:U']});
    }else if(sql.startsWith('ALTER ROLE authenticator'))operation='TARGET_ROLE_SETTINGS';
    else {assert.ok(sql.includes('BEGIN READ ONLY;'));return output('');}
   }
  }else if(args[0]==='cp'){
   if(args[2]===run+'-target-storage:/var/lib/storage/.')return output('');
   assert.equal(args[2],join(snapshotDir,'files')+'/.');assert.equal(args[3],run+'-target-storage:/var/lib/storage/');
   operation='TARGET_FILES_COPY_IN';
  }else assert.fail('UNEXPECTED_RESTORE_STUB_CALL');
  operations.push(operation);return output('',operation===failedOperation?1:0,canary);
 });
 const snapshot={run,archiveSha256:digest(dump),tocSha256:graphql.review.nativeRestoreTocSha256,files:fileTree(join(snapshotDir,'files')),before:{},catalogue:{nativeGraphql:graphql.witness}};
 const reviewed={...graphql.review,nativeRoleSettingsReviewed:true};
 await assert.rejects(()=>restoreTarget(nativeRuntime(directory),snapshotDir,snapshot,reviewed,'unused'),error=>{
  const publicResult=closedFailure(error,'restore');if(failedOperation==='TOC_BINDING'){assert.equal(publicResult.code,'B_SNAPSHOT');return true;}assert.equal(publicResult.code,'B_CALL');
  assert.equal(publicResult.restoreCall.operation,failedOperation);assert.equal(publicResult.restoreCall.exitCode,1);
  if(failedOperation==='TARGET_ARCHIVE_SQL_EXPORT')assert.deepEqual(publicResult.restoreCall.pgRestore,{schemaVersion:1,parser:'FIRST_ERROR',inputTruncated:false,category:'OWNER_REQUIRED',command:'ALTER',schema:'public',extension:null,missingObjectType:null,missingRole:null});
  else if(failedOperation==='TARGET_ARCHIVE_TOC_READ')assert.equal(publicResult.restoreCall.pgRestore.category,'ARCHIVE_FORMAT');
  else assert.equal(publicResult.restoreCall.pgRestore,undefined);
  assert.ok(!JSON.stringify(publicResult).includes(canary));return true;
 });
 assert.deepEqual(operations,failedOperation==='TOC_BINDING'?['TARGET_ARCHIVE_TOC_READ']:restoreSequence.slice(0,restoreSequence.indexOf(failedOperation)+1));
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

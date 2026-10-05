import test from 'node:test';
import assert from 'node:assert/strict';
import cp from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { readFileSync } from 'node:fs';
import { runB21NativeWitnesses,validateB21NativeContainer,B21_IMAGE,B21_LABEL,B21_START_SCRIPT } from '../catalogue-semantics-native.mjs';
import { buildB21NativeWitnessSql,validateB21NativeWitnesses,projectB21NativeWitnessReceipt,decodeB21Witness,B21_ACL_CASES,B21_EXPRESSION_CASES,B22_EXPRESSION_CASES,b21SqlFailure,projectB21SqlFailure } from '../catalogue-semantics-witness.mjs';
import { relation,expression,PRIVATE_CANARY } from './catalogue-semantics-fixture.mjs';
import { closedFailure } from '../contract.mjs';
const run='jolene-restore-drill-987654-1',name=run+'-b21-semantics';
function fixture(){
 const acl={schemaVersion:1,status:'SYNTHETIC_WITNESSES_PASSED',nullDefault:true,nullEmptyDistinct:true,ownerImplicitGrantOption:true,sequenceTypeDistinct:true,orderOnly:true,
  grantorPreserved:true,realRevokeRejected:true,grantOptionPreserved:true,ownerPreserved:true,inheritOptionPreserved:true,creationDefaultsOnly:true,cases:[]};
 for(const n of Object.keys(B21_ACL_CASES)){
  const a=relation(),b=structuredClone(a);b.rawState='PRESENT';
  if(n==='NULL_EMPTY'){b.rawState='EMPTY';b.expandedAcl=[];}
  if(n==='SEQUENCE_DEFAULT'){a.relkind=b.relkind='S';a.expandedAcl=b.expandedAcl=[['ROLE','owner','owner','USAGE',false]];}
  if(n==='SEQUENCE_TABLE')a.relkind='S';
  if(n==='GRANTOR')b.expandedAcl[0][2]='other';
  if(n==='REAL_REVOKE')b.expandedAcl.pop();
  if(n==='GRANT_OPTION')b.expandedAcl[0][4]=true;
  if(n==='OWNER')b.owner='other';
  acl.cases.push({name:n,left:a,right:b});
 }
 const expr={schemaVersion:1,status:'SYNTHETIC_WITNESSES_PASSED',checkNativeRoundtrip:true,timezoneCanChangeDeparse:true,fixedContextReproduces:true,regclassNativeRebind:true,
  sameDependenciesDoNotErasePredicateChange:true,notValidPreserved:true,deferrabilityPreserved:true,literalChangeRejected:true,cases:[],v2Cases:[]};
 for(const [n,expected] of Object.entries(B21_EXPRESSION_CASES)){
  const a=expression(['REGCLASS_REBIND','PREDICATE_CHANGE'].includes(n)?'policy':'constraint'),b=structuredClone(a);
  if(expected==='persistentDifferenceCount'){b.definition+=' changed';b.prettyDefinition+=' changed';}
  if(n==='REGCLASS_REBIND')b.localOid++;
  if(n==='VALIDATION_CHANGE')a.metadata.convalidated=false;
  if(n==='DEFERRABILITY_CHANGE')a.metadata.condeferrable=true;
  expr.cases.push({name:n,left:a,right:b});
 }
 for(const [n,expected] of Object.entries(B22_EXPRESSION_CASES)){
  const a=expression(['POLICY_PRETTY_ROUNDTRIP','WITH_CHECK','NULL_PREDICATE'].includes(n)?'policy':'constraint'),b=structuredClone(a);
  a.secondaryDefinition=b.secondaryDefinition=a.secondaryPrettyDefinition=b.secondaryPrettyDefinition=PRIVATE_CANARY;
  b.definition+=' grouped';
  if(n.startsWith('USER_'))a.bindings.complete=b.bindings.complete=false;
  else if(n==='WITH_CHECK')b.secondaryDefinition+=' changed';
  else if(!expected)b.prettyDefinition+=' changed';
  expr.v2Cases.push({name:n,left:a,right:b});
 }
 return [acl,expr];
}
function container(){return {Name:'/'+name,Config:{Labels:{[B21_LABEL]:run},Image:B21_IMAGE,User:'postgres',Entrypoint:['sh'],Cmd:['-ceu',B21_START_SCRIPT]},
 HostConfig:{NetworkMode:'none',ReadonlyRootfs:true,Privileged:false,LogConfig:{Type:'none'},PortBindings:{},Binds:null,CapAdd:null,CapDrop:['ALL'],SecurityOpt:['no-new-privileges'],Memory:768*1024*1024,PidsLimit:128,NanoCpus:1_000_000_000,ShmSize:64*1024*1024,
  Tmpfs:{'/tmp':'rw,noexec,nosuid,size=256m,mode=1777','/var/run/postgresql':'rw,noexec,nosuid,size=16m,mode=1777'}},
 NetworkSettings:{Ports:{'5432/tcp':null},Networks:{none:{}}},Mounts:[],State:{Status:'created',OOMKilled:false}};}
test('native private rows traverse the actual semantic comparators and a closed receipt',()=>{
 const f=fixture(),receipt=validateB21NativeWitnesses(...f);assert.equal(receipt.aclCases,9);assert.equal(receipt.expressionCases,8);assert.equal(receipt.catalogueV2Cases,12);
 assert.ok(!JSON.stringify(receipt).includes(PRIVATE_CANARY));assert.deepEqual(projectB21NativeWitnessReceipt(receipt),receipt);
 assert.throws(()=>projectB21NativeWitnessReceipt({...receipt,sql:PRIVATE_CANARY}),/B_SEMANTICS_WITNESS/);
 for(const edit of [v=>v[0].cases.find(r=>r.name==='REAL_REVOKE').right=structuredClone(v[0].cases.find(r=>r.name==='REAL_REVOKE').left),
  v=>v[1].cases.find(r=>r.name==='PREDICATE_CHANGE').right=structuredClone(v[1].cases.find(r=>r.name==='PREDICATE_CHANGE').left),
  v=>v[1].cases.find(r=>r.name==='VALIDATION_CHANGE').left.metadata.convalidated=true,
  v=>v[0].cases[0].sql=PRIVATE_CANARY,v=>v[0].cases.pop(),v=>v[1].cases[0].name=PRIVATE_CANARY,
  v=>v[1].v2Cases.find(r=>r.name==='USER_DOMAIN').right.bindings.complete=true,
  v=>v[1].v2Cases.find(r=>r.name==='BOOLEAN_PRECEDENCE').right.prettyDefinition=v[1].v2Cases.find(r=>r.name==='BOOLEAN_PRECEDENCE').left.prettyDefinition]){
  const v=fixture();edit(v);assert.throws(()=>validateB21NativeWitnesses(...v),e=>{assert.ok(!JSON.stringify(closedFailure(e,'semantics_witnesses')).includes(PRIVATE_CANARY));return e.code==='B_SEMANTICS_WITNESS';});
 }
});
test('native expression JSON with an uncast oid string fails the existing strict row gate',()=>{
 const [acl,expressions]=fixture();
 expressions.cases[0].left.localOid=String(expressions.cases[0].left.localOid);
 const decoded=decodeB21Witness(Buffer.from(JSON.stringify(expressions)));
 assert.equal(typeof decoded.cases[0].left.localOid,'string');
 assert.throws(()=>validateB21NativeWitnesses(acl,decoded),e=>e.code==='B_SEMANTICS_WITNESS'&&e.b21WitnessReason==='PRIVATE_SHAPE');
});
test('container isolation rejects every host/network/identity escape before SQL or deletion',()=>{
 assert.equal(validateB21NativeContainer(container(),run),true);
 for(const edit of [v=>v.Name='/foreign',v=>v.Config.Labels[B21_LABEL]='foreign',v=>v.Config.Image='postgres:latest',v=>v.Config.User='root',
  v=>v.HostConfig.NetworkMode='host',v=>v.HostConfig.ReadonlyRootfs=false,v=>v.HostConfig.Privileged=true,v=>v.HostConfig.LogConfig.Type='json-file',
  v=>v.HostConfig.Binds=['/host:/tmp'],v=>v.HostConfig.CapAdd=['SYS_ADMIN'],v=>v.HostConfig.PortBindings={'5432/tcp':[{}]},
  v=>v.Mounts=[{Type:'volume',Destination:'/tmp'}],v=>v.Config.Volumes={'/var/lib/postgresql/data':{}},v=>v.Config.Cmd=['foreign']]){
  const v=container();edit(v);assert.throws(()=>validateB21NativeContainer(v,run),/B_SEMANTICS_WITNESS/);
 }
});
function harness(t,{failSql=false,unclean=false,existingSource=false,imageVolumes=null,createTimeout=false}={}){
 let present=false;const c=container(),events=[],outputs=fixture(),output=v=>({stdout:Buffer.from(typeof v==='string'?v:JSON.stringify(v)),stderr:Buffer.alloc(0),status:0,signal:null});
 t.mock.method(cp,'spawnSync',(command,args,options)=>{
  assert.equal(command,'docker');assert.ok(!args.some(a=>String(a).includes('POSTGRES_PASSWORD')));
  if(args[0]==='context')return output([{Endpoints:{docker:{Host:'unix:///synthetic.sock'}}}]);
  if(args[0]==='image'){assert.deepEqual(args,['image','inspect',B21_IMAGE]);return output([{RepoDigests:[B21_IMAGE],Os:'linux',Architecture:'amd64',Config:{Volumes:imageVolumes}}]);}
  if(args[0]==='ps'){
   const filter=args[args.indexOf('--filter')+1];
   if(filter.startsWith('label=org.jolene.restore-drill='))return output(existingSource?'source-is-present':'');
   if(filter.startsWith('label=org.jolene.restore-browser='))return output('');
   return output(present?name:'');
  }
  if(args[0]==='create'){assert.equal(present,false);assert.ok(args.includes('--pull')&&args.includes('never'));present=true;events.push('create');return createTimeout?{...output(''),status:null,signal:'SIGTERM',error:Error(PRIVATE_CANARY)}:output('id');}
  if(args[0]==='inspect'){assert.equal(present,true);return output([c]);}
  if(args[0]==='start'){c.State.Status='running';events.push('start');return output('');}
  if(args[0]==='rm'){assert.equal(present,true);assert.deepEqual(args,['rm','--force',name]);present=false;events.push('remove');return output('');}
  assert.equal(args[0],'exec');assert.equal(present,true);
  if(args.includes('pg_isready'))return output('');
  assert.equal(args[2],name);assert.equal(args[args.indexOf('-h')+1],'/var/run/postgresql');
  assert.ok(args.includes('VERBOSITY=verbose'));
  const sql=options.input.toString();
  if(sql.startsWith('CREATE DATABASE')){events.push('database');return output('');}
  if(sql.startsWith('SELECT jsonb_build_object')){events.push('rollback');return output({clean:!unclean});}
  const kind=sql.includes('B21_NULL_DEFAULT')?'acl':'expression';events.push(kind);
  assert.ok(sql.includes('WITH expression_objects AS'));assert.ok(sql.endsWith('ROLLBACK;\n'));
  if(failSql)return {...output(''),status:1,stderr:Buffer.from(PRIVATE_CANARY)};
  return output(outputs[kind==='acl'?0:1]);
 });syncBuiltinESMExports();t.after(()=>{t.mock.restoreAll();syncBuiltinESMExports();});return {events,isPresent:()=>present};
}
test('dedicated native runner has no source/target resources and proves rollback and removal before returning',async t=>{
 const h=harness(t),r=await runB21NativeWitnesses(run);assert.equal(r.cleanupVerified,true);assert.equal(h.isPresent(),false);
 assert.deepEqual(h.events,['create','start','database','acl','rollback','expression','rollback','remove']);
});
test('native SQL failure discards private error and still removes only the owned witness container',async t=>{
 const h=harness(t,{failSql:true});await assert.rejects(()=>runB21NativeWitnesses(run),e=>{const r=closedFailure(e,'semantics_witnesses');assert.equal(r.semanticsWitness.reason,'SQL');assert.equal(r.semanticsWitness.sql.phase,'ACL');assert.equal(r.semanticsWitness.sql.outcome,'EXIT');assert.ok(!JSON.stringify(r).includes(PRIVATE_CANARY));return true;});
 assert.equal(h.isPresent(),false);assert.equal(h.events.at(-1),'remove');
});
test('witness SQL failure keeps only the first ERROR code, line and exact synthetic assertion',()=>{
 const stderr=Buffer.from(`WARNING: ${PRIVATE_CANARY}\npsql:<stdin>:421: ERROR:  55000: B22_CHECK_CASE_USER_DOMAIN\nCONTEXT: ${PRIVATE_CANARY}\npsql:<stdin>:900: ERROR:  42P01: ${PRIVATE_CANARY}`);
 const e=b21SqlFailure({status:3,signal:null,stderr},'EXPRESSION'),r=closedFailure(e,'semantics_witnesses');
 assert.deepEqual(r.semanticsWitness.sql,{phase:'EXPRESSION',outcome:'EXIT',sqlstate:'55000',line:421,assertion:'B22_CHECK_CASE_USER_DOMAIN'});
 assert.equal(r.sqlstate,'55000');assert.equal(r.sqlLine,421);assert.ok(!JSON.stringify(r).includes(PRIVATE_CANARY));assert.equal(e.stderr,undefined);
});
test('unknown and malformed SQL diagnostics never expose arbitrary messages or labels',()=>{
 for(const stderr of [Buffer.from(`psql:<stdin>:44: ERROR:  42P01: ${PRIVATE_CANARY}`),
  Buffer.from(`psql:<stdin>:44: ERROR:  55000: B22_CHECK_CASE_USER_DOMAIN ${PRIVATE_CANARY}`),
  Buffer.from(`CONTEXT: ERROR: 55000: B22_CHECK_CASE_USER_DOMAIN\n${PRIVATE_CANARY}`),
  Buffer.from('psql:<stdin>:2: ERROR:  42P01: B22_CHECK_CASE_USER_DOMAIN'),
  Buffer.from(`psql:<stdin>:2: ERROR: ${PRIVATE_CANARY}\npsql:<stdin>:3: ERROR:  55000: B22_CHECK_CASE_USER_DOMAIN`),
  Buffer.alloc(65537,65),Buffer.from([0xff,0xfe])]){
  const r=closedFailure(b21SqlFailure({status:1,signal:null,stderr},PRIVATE_CANARY),'semantics_witnesses');
  assert.equal(r.semanticsWitness.sql.phase,'UNKNOWN');assert.equal(r.semanticsWitness.sql.assertion,null);assert.ok(!JSON.stringify(r).includes(PRIVATE_CANARY));
 }
 const r=projectB21SqlFailure({phase:PRIVATE_CANARY,outcome:PRIVATE_CANARY,sqlstate:'invalid',line:1000000,assertion:PRIVATE_CANARY,raw:PRIVATE_CANARY});
 assert.deepEqual(r,{phase:'UNKNOWN',outcome:'UNKNOWN',sqlstate:null,line:null,assertion:null});
 for(const sqlstate of [['55000'],{private:PRIVATE_CANARY,toString(){return '55000';}},'42P01']){
  const sql=projectB21SqlFailure({phase:'ACL',outcome:'EXIT',sqlstate,line:2,assertion:'B21_NULL_DEFAULT'});
  assert.equal(sql.assertion,null);assert.equal(sql.sqlstate,typeof sqlstate==='string'?sqlstate:null);
  const final=closedFailure({code:'B_SEMANTICS_WITNESS',b21WitnessReason:'SQL',b21Sql:{...sql,sqlstate},diagnostic:{sqlstate}},'semantics_witnesses');
  assert.equal(final.sqlstate,typeof sqlstate==='string'?sqlstate:null);assert.ok(!JSON.stringify(final).includes(PRIVATE_CANARY));
 }
});
test('SQL timeout, output bound, signal and executor failure remain failed and distinct',()=>{
 for(const [detail,outcome] of [[{error:{code:'ETIMEDOUT',message:PRIVATE_CANARY}},'TIMEOUT'],[{error:{code:'ENOBUFS'}},'OUTPUT_BOUND'],
  [{signal:'SIGTERM'},'SIGNAL'],[{error:{code:'ENOENT',message:PRIVATE_CANARY}},'EXECUTION_ERROR']]){
  const e=b21SqlFailure({...detail,status:null,stderr:Buffer.from(PRIVATE_CANARY)},'ROLLBACK'),r=closedFailure(e,'semantics_witnesses');
  assert.equal(e.code,'B_SEMANTICS_WITNESS');assert.equal(r.semanticsWitness.sql.outcome,outcome);assert.equal(r.restored,false);assert.equal(r.appVerified,false);
  assert.equal(r.semanticsWitness.sql.sqlstate,null);assert.ok(!JSON.stringify(r).includes(PRIVATE_CANARY));
 }
});
test('rollback failure stops before the next witness and cleans up',async t=>{
 const h=harness(t,{unclean:true});await assert.rejects(()=>runB21NativeWitnesses(run),e=>e.b21WitnessReason==='ROLLBACK');assert.ok(!h.events.includes('expression'));assert.equal(h.isPresent(),false);
});
test('an existing source stack refuses before creating a dedicated instance',async t=>{
 const h=harness(t,{existingSource:true});await assert.rejects(()=>runB21NativeWitnesses(run),e=>e.b21WitnessReason==='EXISTING_RESOURCE');assert.deepEqual(h.events,[]);
});
test('an image-declared volume refuses before creating any container or anonymous volume',async t=>{
 const h=harness(t,{imageVolumes:{'/var/lib/postgresql/data':{}}});await assert.rejects(()=>runB21NativeWitnesses(run),e=>e.b21WitnessReason==='ISOLATION');assert.deepEqual(h.events,[]);assert.equal(h.isPresent(),false);
});
test('an ambiguous create timeout still inspects and removes only the owned container',async t=>{
 const h=harness(t,{createTimeout:true});await assert.rejects(()=>runB21NativeWitnesses(run),e=>e.b21WitnessReason==='STARTUP');assert.deepEqual(h.events,['create','remove']);assert.equal(h.isPresent(),false);
});
test('witness SQL uses the same native capture with a fixed synthetic schema and bounded private parser',()=>{
 for(const kind of ['acl','expression']){
  const raw=readFileSync(new URL(`../catalogue-semantics-${kind}-witness.sql`,import.meta.url),'utf8'),sql=buildB21NativeWitnessSql(kind,raw);
  assert.ok(!sql.includes('-- B21_CAPTURE_FUNCTION'));assert.ok(sql.includes("current_database()<>'jolene_b21_semantics_test'"));assert.ok(sql.includes("current_setting('server_version_num')<>'170006'"));
 }
 assert.throws(()=>buildB21NativeWitnessSql('foreign',''),/B_SEMANTICS_WITNESS/);assert.throws(()=>decodeB21Witness(Buffer.from('{}\n{}')),/B_SEMANTICS_WITNESS/);
});

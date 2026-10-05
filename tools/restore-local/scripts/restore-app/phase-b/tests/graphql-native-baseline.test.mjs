import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {nativeGraphqlSchemaBaselineExact,GRAPHQL_BASELINE_SOURCE,GRAPHQL_VENDOR_SCHEMA_GRANT,
 GRAPHQL_NATIVE_BASELINE_SQL} from '../graphql-native-baseline.mjs';
import {assertGraphqlNativeBaseline,assertGraphqlWitness,prepareGraphqlRestore,partitionGraphqlRestore,
 assertGraphqlRestored} from '../graphql-restore-plan.mjs';
import {GRAPHQL_COMPONENTS,closedFailure} from '../contract.mjs';
import {input,witness,nativeSchemaGrants} from './graphql-test-fixture.mjs';
const hash=v=>createHash('sha256').update(v).digest('hex');

test('fixed prerequisite is byte-exact to pinned vendor migration, not derived from diagnostic values',()=>{
 const vendor=readFileSync(new URL('../vendor/'+GRAPHQL_BASELINE_SOURCE.migration,import.meta.url));
 assert.equal(vendor.length,GRAPHQL_BASELINE_SOURCE.bytes);assert.equal(hash(vendor),GRAPHQL_BASELINE_SOURCE.sha256);
 const exact=Buffer.from(GRAPHQL_VENDOR_SCHEMA_GRANT);assert.equal(vendor.indexOf(exact),vendor.lastIndexOf(exact));assert.ok(vendor.includes(exact));
 assert.equal(GRAPHQL_NATIVE_BASELINE_SQL.split(GRAPHQL_VENDOR_SCHEMA_GRANT).length,2);
 const module=readFileSync(new URL('../graphql-native-baseline.mjs',import.meta.url),'utf8');
 assert.ok(!/from ['"]node:(child_process|net|http|https|tls|fs)['"]/.test(module));
 assert.ok(!GRAPHQL_NATIVE_BASELINE_SQL.includes('${'));assert.ok(!/REVOKE|ALTER (?:ROLE|SCHEMA)|CREATE (?:ROLE|FUNCTION)/i.test(GRAPHQL_NATIVE_BASELINE_SQL));
});
test('source current and initial ACL must exactly match official native baseline before exporting',async()=>{
 const good=witness();assert.equal(nativeGraphqlSchemaBaselineExact(good),true);assert.equal(assertGraphqlNativeBaseline(good),good);
 for(const field of ['wrapperSchemaDetails','wrapperSchemaInitialPrivileges'])for(const mutate of [
  x=>x.isNull=true, x=>x.grants=[], x=>x.grants.pop(), x=>x.grants.push([...x.grants[0]]),
  x=>x.grants.push(['ROLE','unexpected','supabase_admin','USAGE',false]),
  x=>x.grants[3][0]='PUBLIC', x=>x.grants[3][1]='unexpected', x=>x.grants[3][2]='unexpected',
  x=>x.grants[3][3]='CREATE', x=>x.grants[3][4]=true, x=>x.grants[2][4]=false,
 ]){
  const v=input();mutate(field==='wrapperSchemaDetails'?v.witness[field]:v.witness[field][0]);
  assert.equal(nativeGraphqlSchemaBaselineExact(v.witness),false);
  let exports=0;await assert.rejects(()=>prepareGraphqlRestore(v,()=>{exports++;return Buffer.from('SELECT 1;');}),e=>e.code==='B_GRAPHQL_RESTORE_REFUSED');assert.equal(exports,0);
 }
 for(const mutate of [v=>v.wrapperSchemaDetails.owner='postgres',v=>v.wrapperSchemaInitialPrivileges=[],
  v=>v.wrapperSchemaInitialPrivileges.push(structuredClone(v.wrapperSchemaInitialPrivileges[0])),
  v=>v.wrapperSchemaInitialPrivileges[0].privtype='i',v=>v.wrapperSchemaInitialPrivileges[0].extra='PRIVATE_CANARY']){
  const v=input();mutate(v.witness);let exports=0;await assert.rejects(()=>prepareGraphqlRestore(v,()=>{exports++;return Buffer.from('SELECT 1;');}));assert.equal(exports,0);
 }
});
test('baseline refuses the exact historical B17 missing-three target and a NULL or empty source',()=>{
 for(const mutate of [v=>v.wrapperSchemaDetails.grants=nativeSchemaGrants().slice(0,3),v=>v.wrapperSchemaInitialPrivileges[0].grants=nativeSchemaGrants().slice(0,3),
  v=>{v.wrapperSchemaDetails.isNull=true;v.wrapperSchemaDetails.grants=[];},v=>{v.wrapperSchemaInitialPrivileges[0].isNull=true;v.wrapperSchemaInitialPrivileges[0].grants=[];}]){
  const v=witness();mutate(v);assert.throws(()=>assertGraphqlNativeBaseline(v,'SOURCE_CAPTURE'),e=>{
   const closed=closedFailure(e,'capture_catalogue');assert.equal(closed.graphql.reason,'WITNESS_NATIVE_SCHEMA_BASELINE');
   assert.equal(closed.graphql.context,'SOURCE_CAPTURE');assert.equal(closed.restored,false);assert.ok(!JSON.stringify(closed).includes('grants'));return true;
  });
 }
});
test('baseline tuple permutations preserve rights while count, option and grantor remain significant',()=>{
 for(let k=0;k<6;k++){
  const v=witness();v.wrapperSchemaDetails.grants.reverse();v.wrapperSchemaInitialPrivileges[0].grants.push(...v.wrapperSchemaInitialPrivileges[0].grants.splice(0,k));
  assert.equal(nativeGraphqlSchemaBaselineExact(v),true);
 }
});
test('native prerequisite is placed once between two unchanged complete archive fragments',async()=>{
 const fragments=[Buffer.from('/* original prerequisite exporter bytes */\n'),Buffer.from('/* original remainder exporter bytes */\n')],calls=[];
 const result=await prepareGraphqlRestore(input(),async req=>{calls.push(req.partition);return fragments[calls.length-1];});
 assert.deepEqual(calls,['prerequisites','remainder']);assert.deepEqual(result.sql,Buffer.concat([fragments[0],Buffer.from('\n'),Buffer.from(GRAPHQL_NATIVE_BASELINE_SQL),fragments[1],Buffer.from('\n')]));
 assert.equal(result.transactionArgs.filter(x=>x==='--single-transaction').length,1);assert.equal(result.proof.restored,false);assert.equal(result.proof.appVerified,false);
 const prior=GRAPHQL_NATIVE_BASELINE_SQL.slice(0,GRAPHQL_NATIVE_BASELINE_SQL.indexOf(GRAPHQL_VENDOR_SCHEMA_GRANT));
 for(const term of ["current_database()='jolene_candidatures_pg17_test'","inet_server_addr() IS NULL","session_user='supabase_admin'","current_user=session_user","n.nspacl IS NULL","extname='pg_graphql'","pg_catalog.pg_init_privs","IS NOT TRUE THEN RAISE EXCEPTION"] )assert.ok(prior.includes(term),term);
 assert.equal(GRAPHQL_NATIVE_BASELINE_SQL.match(/IS NOT TRUE THEN RAISE EXCEPTION/g).length,2);
});
test('nine original component and global fingerprint refusals remain mandatory',()=>{
 for(const key of GRAPHQL_COMPONENTS){const a=witness(),b=witness();b.components[key]='c'.repeat(64);assert.throws(()=>assertGraphqlRestored(a,b),e=>e.graphql.reason==='PARITY_FINGERPRINT');}
 assert.equal(GRAPHQL_COMPONENTS.length,9);const b=witness();b.fingerprint='c'.repeat(64);assert.throws(()=>assertGraphqlRestored(witness(),b),e=>e.graphql.reason==='PARITY_FINGERPRINT');
});
test('initial ACL private snapshot is validated, deep-frozen and absent from public proof',()=>{
 const v=input(),p=partitionGraphqlRestore(v);v.witness.wrapperSchemaInitialPrivileges[0].grants[0][1]='PRIVATE_CANARY';
 assert.equal(p.sourceWitness.wrapperSchemaInitialPrivileges[0].grants[0][1],'supabase_admin');
 assert.ok(Object.isFrozen(p.sourceWitness.wrapperSchemaInitialPrivileges));assert.ok(Object.isFrozen(p.sourceWitness.wrapperSchemaInitialPrivileges[0]));assert.ok(Object.isFrozen(p.sourceWitness.wrapperSchemaInitialPrivileges[0].grants[0]));
 assert.ok(!JSON.stringify(p.proof).includes('wrapperSchemaInitialPrivileges'));
 for(const wrong of [null,{},[{privtype:'e',isNull:false,grants:[],extra:true}],Array(2).fill({privtype:'e',isNull:false,grants:[]})])assert.throws(()=>assertGraphqlWitness({...witness(),wrapperSchemaInitialPrivileges:wrong}),e=>e.graphql.reason==='WITNESS_SCHEMA_INITIAL_PRIVILEGES');
});
test('source capture uses the guard; SQL captures schema initial ACL without mutating catalogs',()=>{
 const adapter=readFileSync(new URL('../native-runtime.mjs',import.meta.url),'utf8');assert.ok(adapter.includes("side==='source'?assertGraphqlNativeBaseline:assertGraphqlWitness"));
 const sql=readFileSync(new URL('../graphql-native-witness.sql',import.meta.url),'utf8');assert.match(sql,/'wrapperSchemaInitialPrivileges'/);
 assert.ok(sql.includes("i.classoid='pg_namespace'::regclass AND i.objsubid=0"));assert.ok(sql.includes('FROM aclexplode(i.initprivs) x'));
 assert.match(sql,/BEGIN READ ONLY;/);assert.match(sql,/ROLLBACK;/);
});

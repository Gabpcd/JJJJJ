import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {closedFailure,projectGraphqlDiagnostic,GRAPHQL_COMPONENTS,GRAPHQL_COMPONENT_LABELS,GRAPHQL_WITNESS_FLAGS,
 GRAPHQL_DIAGNOSTIC_REASONS,GRAPHQL_DIAGNOSTIC_CONTEXTS} from '../contract.mjs';
import {assertGraphqlWitness,assertGraphqlRestored,normalizedGraphqlTocHash,partitionGraphqlRestore,prepareGraphqlRestore,graphqlExportArgs} from '../graphql-restore-plan.mjs';
import {normalizedToc} from '../../snapshot-restore.mjs';
import {runtimeFailure} from '../main.mjs';
import {input,witness,descriptions,tocOf} from './graphql-test-fixture.mjs';
const hash=v=>createHash('sha256').update(v).digest('hex');
const canary='PRIVATE_NAME_SIGNATURE_SQL_PATH_CANARY';
const capture=fn=>{try{fn();}catch(error){assert.equal(error.code,'B_GRAPHQL_RESTORE_REFUSED');return error;}assert.fail('EXPECTED_REFUSAL');};
const check=(error,reason,context)=>{
 const result=runtimeFailure(error,context==='SOURCE_CAPTURE'?'capture_catalogue':'restore');
 assert.equal(result.code,'B_GRAPHQL_RESTORE_REFUSED');assert.equal(result.graphql.reason,reason);assert.equal(result.graphql.context,context);
 assert.equal(result.restored,false);assert.equal(result.appVerified,false);assert.ok(!JSON.stringify(result).includes(canary));
 return result.graphql;
};
test('closed diagnostic projection is bounded, idempotent, enum only, and gated to its error code',()=>{
 for(const reason of GRAPHQL_DIAGNOSTIC_REASONS)for(const context of GRAPHQL_DIAGNOSTIC_CONTEXTS){
  const p=projectGraphqlDiagnostic({reason,context,sql:canary,signature:canary,hash:'a'.repeat(64),
   failedFlags:[...GRAPHQL_WITNESS_FLAGS,...GRAPHQL_WITNESS_FLAGS,canary],mismatchedComponents:[...Object.values(GRAPHQL_COMPONENT_LABELS),canary]});
  assert.deepEqual(projectGraphqlDiagnostic(p),p);assert.deepEqual(Object.keys(p),['schemaVersion','context','reason','failedFlags','mismatchedComponents']);
  assert.ok(!JSON.stringify(p).includes(canary));assert.ok(!JSON.stringify(p).includes('a'.repeat(64)));
  assert.ok(p.failedFlags.length<=14&&p.mismatchedComponents.length<=9);
 }
 assert.deepEqual(projectGraphqlDiagnostic({reason:canary,context:canary,failedFlags:[canary],mismatchedComponents:[canary]}),
  {schemaVersion:1,context:'UNKNOWN',reason:'UNKNOWN',failedFlags:[],mismatchedComponents:[]});
 assert.equal(closedFailure({code:'B_CALL',graphql:{reason:'REVIEW',context:'PARTITION'}},'restore').graphql,undefined);
 assert.deepEqual(closedFailure({code:'B_GRAPHQL_RESTORE_REFUSED'},'restore').graphql,projectGraphqlDiagnostic(null));
});
test('source and target native witness failures identify only fixed failed flags',()=>{
 for(const context of ['SOURCE_CAPTURE','SOURCE_SNAPSHOT','TARGET_RESTORED'])for(const flag of GRAPHQL_WITNESS_FLAGS){
  const d=check(capture(()=>assertGraphqlWitness({...witness(),[flag]:canary},context)),'WITNESS_FLAGS',context);
  assert.deepEqual(d.failedFlags,[flag]);assert.deepEqual(d.mismatchedComponents,[]);
 }
 for(const [patch,reason] of [[{schemaVersion:1},'WITNESS_SHAPE'],[{unexpected:canary},'WITNESS_SHAPE'],
  [{initialPrivilegesCount:2},'WITNESS_INITIAL_PRIVILEGES'],[{fingerprint:canary},'WITNESS_FINGERPRINT'],
  [{components:{wrapper:canary}},'WITNESS_COMPONENTS']])check(capture(()=>assertGraphqlWitness({...witness(),...patch},'SOURCE_CAPTURE')),reason,'SOURCE_CAPTURE');
});
test('target parity identifies each private component without publishing its values',()=>{
 for(const key of GRAPHQL_COMPONENTS){const target=witness();target.components[key]='b'.repeat(64);target.fingerprint='c'.repeat(64);
  const d=check(capture(()=>assertGraphqlRestored(witness(),target)),'PARITY_FINGERPRINT','TARGET_COMPARE');
  assert.deepEqual(d.mismatchedComponents,[GRAPHQL_COMPONENT_LABELS[key]]);assert.ok(!JSON.stringify(d).includes('b'.repeat(64)));
 }
 check(capture(()=>assertGraphqlRestored(witness(),{...witness(),initialPrivilegesCount:0})),'PARITY_INITIAL_PRIVILEGES','TARGET_COMPARE');
 const target=witness();target.fingerprint='b'.repeat(64);
 assert.deepEqual(check(capture(()=>assertGraphqlRestored(witness(),target)),'PARITY_FINGERPRINT','TARGET_COMPARE').mismatchedComponents,[]);
 const changedComponent=witness();changedComponent.components.wrapper='b'.repeat(64);
 check(capture(()=>assertGraphqlRestored(witness(),changedComponent)),'PARITY_FINGERPRINT','TARGET_COMPARE');
});
test('every prerequisite and structural selector has a distinct refusal without relaxing B14 matches',()=>{
 const cases=[
  ['REQUIRED_EXTENSION_SCHEMA',r=>r.filter(v=>v!=='SCHEMA - extensions postgres')],
  ['REQUIRED_WRAPPER_SCHEMA',r=>r.filter(v=>v!=='SCHEMA - graphql_public supabase_admin')],
  ['REQUIRED_HOOK',r=>r.filter(v=>v!=='FUNCTION extensions grant_pg_graphql_access() supabase_admin')],
  ['REQUIRED_DEFAULT_ACL',r=>r.filter(v=>v!=='DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS supabase_admin')],
  ['REQUIRED_TRIGGER',r=>r.filter(v=>v!=='EVENT TRIGGER - issue_pg_graphql_access supabase_admin')],
  ['HOOK_COUNT',r=>[...r,'FUNCTION extensions grant_pg_graphql_access(text) supabase_admin']],
  ['TRIGGER_COUNT',r=>[...r,'EVENT TRIGGER - issue_pg_graphql_access postgres']],
  ['DEFAULT_ACL_COUNT',r=>[...r,'DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS postgres']],
  ['WRAPPER_DEFINITION',r=>[...r,'FUNCTION graphql_public different_function(text) supabase_admin']],
  ['EXTENSION_COUNT',r=>r.filter(v=>v!=='EXTENSION - pg_graphql ')],
  ['WRAPPER_ACL',r=>r.map(v=>v.startsWith('ACL graphql_public FUNCTION graphql(')?'ACL graphql_public FUNCTION graphql(text, text, jsonb, jsonb) supabase_admin':v)],
 ];
 for(const [reason,edit] of cases)check(capture(()=>partitionGraphqlRestore(input(edit(descriptions())))),reason,'PARTITION');
 for(const [patch,reason] of [[{review:{}},'REVIEW'],[{archive:Buffer.alloc(0)},'ARCHIVE_BUFFER'],
  [{archive:Buffer.from(canary)},'ARCHIVE_MAGIC'],[{archiveSha256:'b'.repeat(64)},'ARCHIVE_HASH']])
  check(capture(()=>partitionGraphqlRestore({...input(),...patch})),reason,'PARTITION');
 const mismatch=input();mismatch.review.nativeRestoreTocSha256='b'.repeat(64);check(capture(()=>partitionGraphqlRestore(mismatch)),'TOC_REVIEW_HASH','PARTITION');
});
test('TOC parser distinguishes encoding, shape, duplicate identifiers and forbidden scope',()=>{
 const cases=[['TOC_BUFFER',Buffer.alloc(0)],['TOC_UTF8',Buffer.from([255])],['TOC_CONTROL',Buffer.from('1; 0 0 TABLE public x\towner\n')],
 ['TOC_FORMAT',Buffer.from(canary)],['TOC_DUPLICATE_ID',Buffer.from('1; 0 0 TABLE public x owner\n1; 0 0 TABLE public y owner\n')],
 ['TOC_SCOPE',Buffer.from('1; 0 0 DATABASE - forbidden owner\n')],['TOC_COUNT',Buffer.from('1; 0 0 TABLE public x owner\n')]];
 for(const [reason,toc] of cases)check(capture(()=>normalizedGraphqlTocHash(toc)),reason,'NORMALIZE');
});
test('export failures identify the partition and preserve failure after byte mutation',async()=>{
 check(capture(()=>graphqlExportArgs(canary)),'EXPORT_PARTITION','EXPORT_ASSEMBLY');
 await assert.rejects(()=>prepareGraphqlRestore(input(),null),e=>{check(e,'EXPORT_CALLBACK','EXPORT_ASSEMBLY');return true;});
 for(const partition of ['prerequisites','remainder'])for(const failure of ['buffer','nul','archive','list']){
  await assert.rejects(()=>prepareGraphqlRestore(input(),async r=>{
   if(r.partition!==partition)return Buffer.from('SELECT 1;');
   if(failure==='buffer')return canary;if(failure==='nul')return Buffer.from('x\0y');
   r[failure][0]=120;return Buffer.from('SELECT 1;');
  }),e=>{check(e,{buffer:'EXPORT_SQL_BUFFER',nul:'EXPORT_SQL_NUL',archive:'EXPORT_ARCHIVE_MUTATED',list:'EXPORT_LIST_MUTATED'}[failure],partition==='prerequisites'?'EXPORT_PREREQUISITES':'EXPORT_REMAINDER');return true;});
 }
});
test('capture and GraphQL normalized hashes agree for PostgreSQL list formatting and identifiers',()=>{
 const initial=tocOf(descriptions());
 for(const toc of [initial,Buffer.from(initial.toString().replaceAll('\n','\r\n')),tocOf([...descriptions()].reverse()),
  Buffer.from(initial.toString().replaceAll(/^(\d+); 0 (\d+) /gm,(_,id,oid)=>`${Number(id)+10000}; 1255 ${Number(oid)+777} `))])
  assert.equal(normalizedGraphqlTocHash(toc),hash(normalizedToc(toc)));
 assert.equal(normalizedGraphqlTocHash(initial),normalizedGraphqlTocHash(tocOf([...descriptions()].reverse())));
 // The empty extension owner has a meaningful trailing space, retained by both algorithms.
 const changed=Buffer.from(initial.toString().replace('EXTENSION - pg_graphql \n','EXTENSION - pg_graphql other_owner\n'));
 assert.notEqual(normalizedGraphqlTocHash(initial),normalizedGraphqlTocHash(changed));
});
test('private component witness is immutable and does not escape the public preparation proof',async()=>{
 const x=input(),prepared=await prepareGraphqlRestore(x,async()=>Buffer.from('SELECT 1;'));x.witness.components.wrapper='b'.repeat(64);
 assert.equal(prepared.sourceWitness.components.wrapper,'a'.repeat(64));assert.ok(Object.isFrozen(prepared.sourceWitness.components));
 assert.ok(!JSON.stringify(prepared.proof).includes('components'));
 const sql=readFileSync(new URL('../graphql-native-witness.sql',import.meta.url),'utf8');
 for(const key of GRAPHQL_COMPONENTS)assert.ok(sql.includes("'"+key+"'"));
 assert.ok(sql.includes('BEGIN READ ONLY;'));assert.ok(sql.includes('ROLLBACK;'));
});

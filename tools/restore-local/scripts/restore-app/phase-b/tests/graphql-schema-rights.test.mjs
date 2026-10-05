import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {assertGraphqlRestored,assertGraphqlWitness,graphqlComparableWitness} from '../graphql-restore-plan.mjs';
import {projectGraphqlDiagnostic,closedFailure} from '../contract.mjs';
import {witness} from './graphql-test-fixture.mjs';
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
// Independent semantic fixture model for the aclexplode tuple projection below.
// It is not an executed PostgreSQL query; the native SQL still needs isolated CI.
const grants=()=>[
 ['ROLE','supabase_admin','supabase_admin','CREATE',false],
 ['ROLE','supabase_admin','supabase_admin','USAGE',false],
 ['ROLE','postgres','supabase_admin','USAGE',true],
 ['ROLE','anon','supabase_admin','USAGE',false],
 ['ROLE','authenticated','supabase_admin','USAGE',false],
 ['ROLE','service_role','supabase_admin','USAGE',false],
 ['PUBLIC',null,'supabase_admin','USAGE',false],
];
const canonical=(rows,owner='supabase_admin')=>['graphql_public',owner,{isNull:rows===null,
 grants:[...(rows??[])].map(row=>[...row]).sort((a,b)=>Buffer.compare(Buffer.from(JSON.stringify(a)),Buffer.from(JSON.stringify(b))))}];
const observed=(rows,owner='supabase_admin')=>{const value=witness(),semantic=canonical(rows,owner);
 value.wrapperSchemaDetails={owner,isNull:rows===null,grants:structuredClone(rows??[])};
 value.wrapperSchemaRawFingerprint=hash(['graphql_public',owner,rows]);
 value.components.schema_graphql_public=hash(semantic);value.fingerprint=hash(value.components);return value;};
const refusal=(source,target)=>{let caught;try{assertGraphqlRestored(source,target);}catch(error){caught=error;}
 assert.ok(caught);assert.equal(caught.graphql.reason,'PARITY_FINGERPRINT');return closedFailure(caught,'restore');};

test('tuple permutations pass semantic parity while raw-order differences remain visible',()=>{
 const original=grants(),source=observed(original);
 for(let turn=0;turn<original.length;turn++){
  const changed=[...original.slice(turn),...original.slice(0,turn)].reverse();
  const target=observed(changed),proof=assertGraphqlRestored(source,target);
  assert.equal(proof.nativeGraphqlWrapperSchemaSemanticEqual,true);
  assert.equal(proof.nativeGraphqlWrapperSchemaRawEqual,false);
  assert.deepEqual(graphqlComparableWitness(source),graphqlComparableWitness(target));
 }
 assert.equal(assertGraphqlRestored(source,observed(original)).nativeGraphqlWrapperSchemaRawEqual,true);
});
test('every added, removed or duplicated grant remains a semantic refusal',()=>{
 const source=observed(grants());
 for(const rows of [grants().slice(1),[...grants(),['ROLE','other','supabase_admin','USAGE',false]],[...grants(),grants()[0]]]){
  const result=refusal(source,observed(rows));assert.deepEqual(result.graphql.wrapperSchemaComparison,{rawEqual:false,semanticEqual:false});
  assert.deepEqual(result.graphql.mismatchedComponents,['WRAPPER_SCHEMA_RIGHTS']);
 }
});
test('grantee, grantor, privilege, grant option and schema owner all remain significant',()=>{
 const source=observed(grants());
 for(const [index,value] of [[1,'another_role'],[2,'another_grantor'],[3,'CREATE'],[4,true]]){
  const rows=grants();rows[3][index]=value;refusal(source,observed(rows));
 }
 refusal(source,observed(grants(),'other_owner'));
 const explicitRole=grants();explicitRole.at(-1)[0]='ROLE';explicitRole.at(-1)[1]='PUBLIC';refusal(source,observed(explicitRole));
});
test('NULL ACL, explicit empty ACL and explicit defaults are never collapsed',()=>{
 for(const [a,b] of [[null,[]],[null,grants().slice(0,2)],[[],grants().slice(0,2)]])refusal(observed(a),observed(b));
 assert.equal(assertGraphqlRestored(observed(null),observed(null)).nativeGraphqlWrapperSchemaSemanticEqual,true);
});
test('raw schema hash is diagnostic only and all other comparable witness fields are retained',()=>{
 const source=witness(),target=witness();target.wrapperSchemaRawFingerprint='f'.repeat(64);
 assert.equal(assertGraphqlRestored(source,target).nativeGraphqlWrapperSchemaRawEqual,false);
 const comparable=graphqlComparableWitness(source);assert.ok(!Object.hasOwn(comparable,'wrapperSchemaRawFingerprint'));
 assert.deepEqual(Object.keys(comparable).sort(),Object.keys(source).filter(k=>!['wrapperSchemaRawFingerprint','wrapperSchemaDetails'].includes(k)).sort());
 assert.equal(source.wrapperSchemaRawFingerprint,'d'.repeat(64));
 for(const key of Object.keys(source.components).filter(k=>k!=='schema_graphql_public')){
  const target=witness();target.components[key]='b'.repeat(64);refusal(source,target);
 }
 for(const raw of [null,'not-a-hash',123])assert.throws(()=>assertGraphqlWitness({...source,wrapperSchemaRawFingerprint:raw}),
  error=>error.graphql.reason==='WITNESS_RAW_SCHEMA_FINGERPRINT');
});
test('raw and semantic comparison diagnostics are fixed booleans without private payloads',()=>{
 const canary='PRIVATE_ACL_ROLE_GRANTOR_SQL_CANARY';
 const value={reason:'PARITY_FINGERPRINT',context:'TARGET_COMPARE',mismatchedComponents:['WRAPPER_SCHEMA_RIGHTS'],
  wrapperSchemaComparison:{rawEqual:false,semanticEqual:true,grantee:canary,grantor:canary,hash:'e'.repeat(64)}};
 const projected=projectGraphqlDiagnostic(value);assert.deepEqual(projectGraphqlDiagnostic(projected),projected);
 assert.deepEqual(projected.wrapperSchemaComparison,{rawEqual:false,semanticEqual:true});
 assert.ok(!JSON.stringify(projected).includes(canary));assert.ok(!JSON.stringify(projected).includes('e'.repeat(64)));
 for(const comparison of [{rawEqual:canary,semanticEqual:true},{rawEqual:false,semanticEqual:1}])
  assert.equal(projectGraphqlDiagnostic({...value,wrapperSchemaComparison:comparison}).wrapperSchemaComparison,undefined);
 assert.equal(projectGraphqlDiagnostic({...value,reason:'REVIEW'}).wrapperSchemaComparison,undefined);
});
test('native query uses the complete role-name tuple and only canonicalizes the wrapper schema ACL',()=>{
 const sql=readFileSync(new URL('../graphql-native-witness.sql',import.meta.url),'utf8');
 const tuple=sql.slice(sql.indexOf('), wrapper_schema_acl AS ('),sql.indexOf('), facts AS ('));
 assert.match(tuple,/jsonb_build_array\(CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE 'ROLE' END,\s*CASE WHEN x.grantee=0 THEN NULL ELSE pg_get_userbyid\(x.grantee\) END,\s*pg_get_userbyid\(x.grantor\),x.privilege_type,x.is_grantable\)/);
 assert.match(tuple,/CROSS JOIN LATERAL aclexplode\(n.nspacl\) x/);assert.ok(!/DISTINCT|acldefault|coalesce/i.test(tuple));
 const schema=sql.slice(sql.indexOf("UNION ALL SELECT 'schemas'"),sql.indexOf('SELECT jsonb_build_object(\n'));
 assert.match(schema,/jsonb_build_array\(n.nspname,pg_get_userbyid\(n.nspowner\),/);
 assert.match(schema,/CASE WHEN n.nspname='graphql_public' THEN jsonb_build_object\('isNull',n.nspacl IS NULL,/);
 assert.match(schema,/jsonb_agg\(grant_tuple ORDER BY grant_tuple::text COLLATE "C"\)/);
 assert.match(schema,/ELSE to_jsonb\(n.nspacl\) END/);assert.ok(!/DISTINCT|acldefault/i.test(schema));
 assert.match(sql,/'wrapperSchemaRawFingerprint',[\s\S]*n.nspname,pg_get_userbyid\(n.nspowner\),n.nspacl/);
 assert.match(sql,/BEGIN READ ONLY;/);assert.match(sql,/ROLLBACK;/);
});

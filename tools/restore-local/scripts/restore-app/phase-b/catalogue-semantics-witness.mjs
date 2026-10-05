import { b21WitnessCaptureSql } from './catalogue-semantics-probe.mjs';
import { compareB21Relation,compareB21Expression,validB21Relation,validB21Expression } from './catalogue-semantics-diagnostic.mjs';
import { catalogueV2RelationEqual,catalogueV2ExpressionEqual } from './catalogue-parity-v2.mjs';

export const B21_WITNESS_REASONS=Object.freeze(['CONTEXT','EXISTING_RESOURCE','STARTUP','ISOLATION','SQL','PRIVATE_SHAPE','ACL_COMPARISON','EXPRESSION_COMPARISON','ROLLBACK','CLEANUP','UNKNOWN']);
const aclFlags=['nullDefault','nullEmptyDistinct','ownerImplicitGrantOption','sequenceTypeDistinct','orderOnly','grantorPreserved','realRevokeRejected',
 'grantOptionPreserved','ownerPreserved','inheritOptionPreserved','creationDefaultsOnly'];
const expressionFlags=['checkNativeRoundtrip','timezoneCanChangeDeparse','fixedContextReproduces','regclassNativeRebind','sameDependenciesDoNotErasePredicateChange',
 'notValidPreserved','deferrabilityPreserved','literalChangeRejected'];
export const B21_ACL_CASES=Object.freeze({NULL_DEFAULT:'equalCount',NULL_EMPTY:'differentCount',SEQUENCE_DEFAULT:'equalCount',SEQUENCE_TABLE:'inconsistentCount',
 ORDER:'equalCount',GRANTOR:'differentCount',REAL_REVOKE:'differentCount',GRANT_OPTION:'differentCount',OWNER:'ownerDifferentCount'});
export const B21_EXPRESSION_CASES=Object.freeze({CHECK_ROUNDTRIP:'strictFixedEqualCount',TIMEZONE_VARIATION:'persistentDifferenceCount',FIXED_CONTEXT:'strictFixedEqualCount',
 REGCLASS_REBIND:'strictFixedEqualCount',PREDICATE_CHANGE:'persistentDifferenceCount',VALIDATION_CHANGE:'persistentDifferenceCount',
 DEFERRABILITY_CHANGE:'persistentDifferenceCount',LITERAL_CHANGE:'persistentDifferenceCount'});
export const B22_EXPRESSION_CASES=Object.freeze({CHECK_PRETTY_ROUNDTRIP:true,POLICY_PRETTY_ROUNDTRIP:true,
 BOOLEAN_PRECEDENCE:false,RIGHT_SUBTRACTION:false,CAST_CHANGE:false,LITERAL_SAME_BINDINGS:false,NULL_PREDICATE:false,WITH_CHECK:false,
 USER_COLLATION:false,USER_DOMAIN:false,USER_ARRAY:false,USER_OPERATOR:false});
const keys=(v,expected)=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===expected.length&&expected.every(k=>Object.hasOwn(v,k));
export function b21WitnessFailure(reason){return Object.assign(Error('B_SEMANTICS_WITNESS'),{code:'B_SEMANTICS_WITNESS',b21WitnessReason:B21_WITNESS_REASONS.includes(reason)?reason:'UNKNOWN'});}
const sqlPhases=['CREATE_DATABASE','ACL','EXPRESSION','ROLLBACK'];
const sqlAssertions=['B21_DEFAULT_CREATION_ONLY','B21_GRANTOR_PRESERVED','B21_GRANT_OPTION','B21_INHERIT_OFF','B21_INHERIT_ON',
 'B21_NULL_DEFAULT','B21_NULL_EMPTY_OWNER','B21_ORDER','B21_OWNER','B21_REAL_REVOKE_NOT_REJECTED','B21_SEQUENCE_TYPE','B21_SYNTHETIC_CONTEXT',
 'B21_CHECK_ROUNDTRIP','B21_DEFERRABILITY_CHANGE_REJECTED','B21_FIXED_CONTEXT','B21_LITERAL_CHANGE_REJECTED','B21_NOT_VALID_CAPTURED',
 'B21_OID_JSON_TYPE','B21_POLICY_CHANGE_REJECTED','B21_REGCLASS_NATIVE_REBIND','B21_TIMEZONE_VARIATION','B21_VALIDATION_CHANGE_REJECTED',
 'B22_COUNTEREXAMPLE','B22_POLICY_ROUNDTRIP','B22_WITH_CHECK',...Object.keys(B22_EXPRESSION_CASES).map(k=>'B22_CHECK_CASE_'+k)];
export function projectB21SqlFailure(v) {
 return {phase:sqlPhases.includes(v?.phase)?v.phase:'UNKNOWN',
  outcome:['EXIT','TIMEOUT','SIGNAL','EXECUTION_ERROR','OUTPUT_BOUND'].includes(v?.outcome)?v.outcome:'UNKNOWN',
  sqlstate:typeof v?.sqlstate==='string'&&/^[A-Z0-9]{5}$/.test(v.sqlstate)?v.sqlstate:null,
  line:Number.isSafeInteger(v?.line)&&v.line>0&&v.line<1000000?v.line:null,
  assertion:v?.sqlstate==='55000'&&sqlAssertions.includes(v?.assertion)?v.assertion:null};
}
export function b21SqlFailure(result,phase) {
 const bytes=result?.stderr,valid=Buffer.isBuffer(bytes)&&bytes.length<=65536&&bytes.equals(Buffer.from(bytes.toString('utf8')));
 const first=valid?bytes.toString('utf8').split(/\r?\n/).find(s=>/^(?:psql:<stdin>:\d+:\s*)?(?:ERROR|FATAL):/.test(s)):undefined;
 const record=first?/^(?:psql:<stdin>:(\d+):\s*)?(?:ERROR|FATAL):\s+([A-Z0-9]{5}):\s*(.*)$/.exec(first):null;
 const sql=projectB21SqlFailure({phase,outcome:result?.error?.code==='ETIMEDOUT'?'TIMEOUT':result?.error?.code==='ENOBUFS'?'OUTPUT_BOUND':result?.error?'EXECUTION_ERROR':result?.signal?'SIGNAL':'EXIT',
  sqlstate:record?.[2],line:record?.[1]?Number(record[1]):null,assertion:record?.[2]==='55000'?record?.[3]:null});
 // No raw stderr, SQL, process error, signal or private message survives.
 return Object.assign(b21WitnessFailure('SQL'),{b21Sql:sql,diagnostic:{sqlstate:sql.sqlstate,line:sql.line}});
}
export function projectB21WitnessFailure(reason,sql){return {schemaVersion:1,reason:B21_WITNESS_REASONS.includes(reason)?reason:'UNKNOWN',
 ...(reason==='SQL'&&sql!==undefined?{sql:projectB21SqlFailure(sql)}:{})};}
export function buildB21NativeWitnessSql(kind,original){
 if(!['acl','expression'].includes(kind)||typeof original!=='string'||original.split('-- B21_CAPTURE_FUNCTION\n').length!==2)throw b21WitnessFailure('CONTEXT');
 return original.replace('-- B21_CAPTURE_FUNCTION\n',b21WitnessCaptureSql(kind==='acl'?'b21_fixture':'b21_expr'));
}
export function decodeB21Witness(bytes){
 try{if(!Buffer.isBuffer(bytes)||bytes.length>8*1024*1024||!bytes.equals(Buffer.from(bytes.toString('utf8'))))throw Error();
  return JSON.parse(bytes.toString('utf8'));
 }catch{throw b21WitnessFailure('PRIVATE_SHAPE');}
}
function cases(value,flags,names,validator,extras=[]){
 if(!keys(value,['schemaVersion','status',...flags,'cases',...extras])||value.schemaVersion!==1||value.status!=='SYNTHETIC_WITNESSES_PASSED'
  ||!flags.every(k=>value[k]===true)||!Array.isArray(value.cases)||value.cases.length!==names.length)throw b21WitnessFailure('PRIVATE_SHAPE');
 const rows=new Map();for(const row of value.cases){
  if(!keys(row,['name','left','right'])||!names.includes(row.name)||rows.has(row.name)||!validator(row.left)||!validator(row.right))throw b21WitnessFailure('PRIVATE_SHAPE');
  rows.set(row.name,row);
 }return rows;
}
// Uses precisely the relation/expression comparators used on real probe rows.
// SQL booleans alone cannot satisfy this adapter; every negative uses native rows.
export function validateB21NativeWitnesses(acl,expressions){
 const a=cases(acl,aclFlags,Object.keys(B21_ACL_CASES),validB21Relation);
 for(const [name,expected] of Object.entries(B21_ACL_CASES)){
  const row=a.get(name);if(compareB21Relation(row.left,row.right)!==expected)throw b21WitnessFailure('ACL_COMPARISON');
  if(catalogueV2RelationEqual(row.left,row.right)!==(expected==='equalCount'))throw b21WitnessFailure('ACL_COMPARISON');
 }
 const n=a.get('NULL_DEFAULT'),e=a.get('NULL_EMPTY'),s=a.get('SEQUENCE_DEFAULT');
 if(n.left.rawState!=='NULL'||n.right.rawState!=='PRESENT'||e.left.rawState!=='NULL'||e.right.rawState!=='EMPTY'
  ||s.left.relkind!=='S'||s.right.relkind!=='S')throw b21WitnessFailure('ACL_COMPARISON');
 const x=cases(expressions,expressionFlags,Object.keys(B21_EXPRESSION_CASES),validB21Expression,['v2Cases']);
 for(const [name,expected] of Object.entries(B21_EXPRESSION_CASES)){
  const row=x.get(name),d=compareB21Expression(row.left,row.right);if(d?.definition!==expected)throw b21WitnessFailure('EXPRESSION_COMPARISON');
  if(['REGCLASS_REBIND','PREDICATE_CHANGE','TIMEZONE_VARIATION','FIXED_CONTEXT'].includes(name)&&d.dependencies!=='dependenciesEqualCount')throw b21WitnessFailure('EXPRESSION_COMPARISON');
  if(expected==='persistentDifferenceCount'&&catalogueV2ExpressionEqual(row.left,row.right))throw b21WitnessFailure('EXPRESSION_COMPARISON');
 }
 const reg=x.get('REGCLASS_REBIND'),v=x.get('VALIDATION_CHANGE'),d=x.get('DEFERRABILITY_CHANGE');
 if(reg.left.localOid===reg.right.localOid||v.left.metadata.convalidated!==false||v.right.metadata.convalidated!==true
  ||d.left.metadata.condeferrable!==true||d.right.metadata.condeferrable!==false)throw b21WitnessFailure('EXPRESSION_COMPARISON');
 const v2=cases({schemaVersion:1,status:expressions.status,cases:expressions.v2Cases},[],Object.keys(B22_EXPRESSION_CASES),validB21Expression);
 for(const [name,expected] of Object.entries(B22_EXPRESSION_CASES)){
  const row=v2.get(name);
  if(catalogueV2ExpressionEqual(row.left,row.right)!==expected)throw b21WitnessFailure('EXPRESSION_COMPARISON');
  if(expected&&(row.left.definition===row.right.definition||row.left.prettyDefinition!==row.right.prettyDefinition))throw b21WitnessFailure('EXPRESSION_COMPARISON');
  // This negative must isolate WITH CHECK, not fail for unrelated drift.
  if(name==='WITH_CHECK'&&(!['identity','metadata','dependencies','bindings','definition','prettyDefinition']
   .every(k=>JSON.stringify(row.left[k])===JSON.stringify(row.right[k]))
   ||!row.left.bindings.complete||typeof row.left.secondaryDefinition!=='string'||typeof row.right.secondaryDefinition!=='string'
   ||row.left.secondaryDefinition===row.right.secondaryDefinition))throw b21WitnessFailure('EXPRESSION_COMPARISON');
  if(name.startsWith('USER_')&&(row.left.bindings.complete||row.right.bindings.complete||row.left.prettyDefinition!==row.right.prettyDefinition))throw b21WitnessFailure('EXPRESSION_COMPARISON');
 }
 return projectB21NativeWitnessReceipt({schemaVersion:1,result:'B21_NATIVE_WITNESSES_PASSED',postgresVersionNum:170006,
  aclCases:9,expressionCases:8,realRevokeRejected:true,predicateChangeRejected:true,validationChangeRejected:true,
  catalogueV2Cases:12,catalogueV2SameComparators:true,sameComparators:true,rollbackVerified:true,cleanupVerified:true,providerContacted:false});
}
// Final publication is reconstructed, including for tests feeding forged receipts.
export function projectB21NativeWitnessReceipt(v){
 const expected={schemaVersion:1,result:'B21_NATIVE_WITNESSES_PASSED',postgresVersionNum:170006,aclCases:9,expressionCases:8,
  realRevokeRejected:true,predicateChangeRejected:true,validationChangeRejected:true,catalogueV2Cases:12,catalogueV2SameComparators:true,
  sameComparators:true,rollbackVerified:true,cleanupVerified:true,providerContacted:false};
 if(!keys(v,Object.keys(expected))||!Object.keys(expected).every(k=>v[k]===expected[k]))throw b21WitnessFailure('PRIVATE_SHAPE');
 return expected;
}

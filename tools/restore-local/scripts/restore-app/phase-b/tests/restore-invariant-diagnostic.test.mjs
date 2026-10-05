import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { requireRestoreInvariant, catalogueRestoreDiagnostic, projectRestoreInvariant, closedFailure,
 RESTORE_INVARIANT_REASONS, RESTORE_CATALOGUE_FIELDS, RESTORE_NATIVE_GRAPHQL_FIELDS, digest } from '../contract.mjs';
import { restoreTarget } from '../restore-target.mjs';
import { graphqlComparableWitness, assertGraphqlRestored } from '../graphql-restore-plan.mjs';
import { witness } from './graphql-test-fixture.mjs';

const canary='PRIVATE_REVIEW_CANARY_credential_sql_path_role';
const catalogue=()=>({catalogue_sha256:canary,database:[canary],roles:[canary],memberships:[canary],
 databaseRoleSettings:[canary],nativeGraphql:graphqlComparableWitness(witness())});
const capture=fn=>{try{fn();assert.fail('expected refusal');}catch(error){assert.equal(error.code,'B_RESTORE');return error;}};

for(const reason of RESTORE_INVARIANT_REASONS)test('first restore refusal retains its closed identity: '+reason,()=>{
 const error=capture(()=>requireRestoreInvariant(false,reason,()=>catalogueRestoreDiagnostic(catalogue(),catalogue())));
 const receipt=closedFailure(error,'restore');assert.equal(receipt.code,'B_RESTORE');assert.equal(receipt.restoreInvariant.reason,reason);
 assert.equal(receipt.restored,false);assert.equal(receipt.appVerified,false);assert.equal(receipt.readyForNationalLaunch,false);
 assert.equal(receipt.sqlstate,null);assert.equal(receipt.sqlLine,null);assert.ok(!JSON.stringify(receipt).includes(canary));
});
test('diagnostic cannot change a success or replace the original refusal if it fails',()=>{
 let called=0;requireRestoreInvariant(true,'CATALOGUE_PARITY',()=>{called++;throw Error(canary);});assert.equal(called,0);
 const error=capture(()=>requireRestoreInvariant(false,'CATALOGUE_PARITY',()=>{throw Error(canary);}));
 assert.deepEqual(closedFailure(error,'restore').restoreInvariant,{schemaVersion:1,reason:'CATALOGUE_PARITY',catalogue:{status:'INVALID_SHAPE'}});
});
test('catalogue diagnostic exposes only fixed sections and boolean GraphQL fields',()=>{
 for(const field of RESTORE_CATALOGUE_FIELDS){
  const source=catalogue(),target=catalogue();
  if(field==='nativeGraphql')target.nativeGraphql.wrapperSchemaInitialPrivileges[0].grants[0][2]=canary;
  else target[field]=[canary,'changed'];
  const before=JSON.stringify({source,target});const raw=catalogueRestoreDiagnostic(source,target);
  const safe=projectRestoreInvariant({reason:'CATALOGUE_PARITY',catalogue:raw});
  assert.deepEqual(safe.catalogue.sections,[field]);assert.ok(!JSON.stringify(safe).includes(canary));
  assert.equal(JSON.stringify({source,target}),before);
  if(field==='nativeGraphql'){
   assert.deepEqual(Object.keys(safe.catalogue.nativeGraphqlFields),RESTORE_NATIVE_GRAPHQL_FIELDS);
   assert.equal(safe.catalogue.nativeGraphqlFields.wrapperSchemaInitialPrivileges,false);
   assert.equal(safe.catalogue.nativeGraphqlFields.components,true);
   assert.ok(Object.values(safe.catalogue.nativeGraphqlFields).every(v=>typeof v==='boolean'));
  }else assert.equal(safe.catalogue.nativeGraphqlFields,undefined);
 }
});
test('order and unexpected catalogue fields remain mismatches without exporting their names or values',()=>{
 const source=catalogue(),reordered=Object.fromEntries(Object.entries(source).reverse());
 assert.notEqual(JSON.stringify(source),JSON.stringify(reordered));
 assert.deepEqual(catalogueRestoreDiagnostic(source,reordered).sections,['FIELD_ORDER']);
 const target=catalogue();target[canary]=canary;
 const safe=projectRestoreInvariant({reason:'CATALOGUE_PARITY',catalogue:catalogueRestoreDiagnostic(source,target)});
 assert.deepEqual(safe.catalogue.sections,['OTHER_FIELDS','FIELD_ORDER']);assert.ok(!JSON.stringify(safe).includes(canary));
});
test('initial ACL tuple order remains significant to the existing catalogue comparison and is located without exposing tuples',()=>{
 const source=catalogue(),target=catalogue();
 target.nativeGraphql.wrapperSchemaInitialPrivileges[0].grants.reverse();
 assert.notEqual(JSON.stringify(source),JSON.stringify(target));
 const fullSource=witness(),fullTarget=witness();fullTarget.wrapperSchemaInitialPrivileges[0].grants.reverse();
 assertGraphqlRestored(fullSource,fullTarget); // Existing nine synthetic hashes stay equal.
 const result=projectRestoreInvariant({reason:'CATALOGUE_PARITY',catalogue:catalogueRestoreDiagnostic(source,target)});
 assert.deepEqual(result.catalogue.sections,['nativeGraphql']);
 assert.equal(result.catalogue.nativeGraphqlFields.wrapperSchemaInitialPrivileges,false);
 assert.equal(result.catalogue.nativeGraphqlFields.components,true);
 assert.equal(result.catalogue.nativeGraphqlFields.fingerprint,true);
 assert.ok(!JSON.stringify(result).includes('grants'));
});
test('public projection refuses forged nested values, extra fields and dynamic section names',()=>{
 const source=catalogue(),target=catalogue();target.nativeGraphql.wrapperSchemaInitialPrivileges=[];
 const good=catalogueRestoreDiagnostic(source,target);
 for(const mutate of [v=>v.sections.push(canary),v=>v.sections.push('nativeGraphql'),v=>v.extra=canary,
  v=>v.nativeGraphqlFields.fingerprint=canary,v=>v.nativeGraphqlFields.extra=canary,
  v=>delete v.nativeGraphqlFields.schemaVersion,v=>v.sections=[canary]]){
  const value=structuredClone(good);mutate(value);
  assert.deepEqual(projectRestoreInvariant({reason:'CATALOGUE_PARITY',catalogue:value}),
   {schemaVersion:1,reason:'CATALOGUE_PARITY',catalogue:{status:'INVALID_SHAPE'}});
 }
 assert.deepEqual(projectRestoreInvariant({reason:canary,catalogue:good,raw:canary}),{schemaVersion:1,reason:'UNKNOWN'});
 assert.deepEqual(projectRestoreInvariant({reason:'RESTORE_RESULT',catalogue:good}),{schemaVersion:1,reason:'RESTORE_RESULT'});
});
test('closed restore addition leaves SQLSTATE and line projection unchanged and is scoped to restore B_RESTORE',()=>{
 const error=capture(()=>requireRestoreInvariant(false,'CHECKPOINT_BEFORE_API'));
 error.diagnostic={sqlstate:'P0001',line:123,sql:canary};error.message=canary;error.stack=canary;
 const projected=closedFailure(error,'restore');assert.equal(projected.sqlstate,'P0001');assert.equal(projected.sqlLine,123);
 assert.ok(!JSON.stringify(projected).includes(canary));
 assert.equal(closedFailure(error,'browser_target').restoreInvariant,undefined);
 assert.equal(closedFailure({...error,code:'B_CALL'},'restore').restoreInvariant,undefined);
});
function harness(t,reason){
 const dir=mkdtempSync(join(tmpdir(),'jolene-b19-pure-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 mkdirSync(join(dir,'files'));const archive=Buffer.from('PGDMPsynthetic');writeFileSync(join(dir,'database.dump'),archive);writeFileSync(join(dir,'archive-toc.private.txt'),'synthetic');
 const events=[],snapshot={run:'synthetic',tocSha256:'a'.repeat(64),archiveSha256:digest(archive),files:[],before:{same:true},catalogue:catalogue()};let checkpoints=0;
 const flags={nativeGraphqlPrerequisiteVerified:true,nativeGraphqlRestoredExact:true,nativeGraphqlWrapperSchemaSemanticEqual:true,nativeGraphqlWrapperSchemaRawEqual:false,catalogueComparison:{schemaVersion:2,status:'EQUAL',reason:'NORMALIZED',v1Equal:false,v2Equal:true,aclNormalizedCount:1,expressionNormalizedCount:0}};
 const runtime={run:'synthetic',verifyState:async()=>{},assertTargetNativeEmpty:async()=>{},assertTargetFilesEmpty:async()=>{},
  prepareTargetArchiveRestore:async()=>{events.push('prepare');if(reason==='TOC_READBACK_BEFORE_EXPORT')requireRestoreInvariant(false,reason);return {};},
  recreateOwnedEmptyTargetDatabase:async()=>events.push('recreate'),executePreparedTargetRestore:async()=>events.push('execute'),applyReviewedRoleSettings:async()=>events.push('roles'),copyFilesIn:async()=>events.push('copy'),
  sqlJson:async()=>{checkpoints++;events.push('checkpoint'+checkpoints);return (reason==='CHECKPOINT_BEFORE_API'&&checkpoints===1)||(reason==='CHECKPOINT_AFTER_API'&&checkpoints===2)?{same:false}:snapshot.before;},
  assertSourceOffAndTargetCatalogExact:async()=>{events.push('catalogue');if(reason==='CATALOGUE_PARITY'){const target=catalogue();target.database=[canary,'changed'];requireRestoreInvariant(false,reason,()=>catalogueRestoreDiagnostic(snapshot.catalogue,target));}return flags;},
  startApis:async()=>events.push('start'),assertApiHealthy:async()=>events.push('healthy')};
 return {events,execute:()=>restoreTarget(runtime,dir,snapshot,{nativeRestoreTocSha256:snapshot.tocSha256,nativeRoleSettingsReviewed:true},'synthetic')};
}
for(const reason of ['TOC_READBACK_BEFORE_EXPORT','CHECKPOINT_BEFORE_API','CATALOGUE_PARITY','CHECKPOINT_AFTER_API'])test('actual restore orchestration preserves earliest diagnostic: '+reason,async t=>{
 const h=harness(t,reason);await assert.rejects(h.execute,e=>{assert.equal(e.code,'B_RESTORE');assert.equal(closedFailure(e,'restore').restoreInvariant.reason,reason);return true;});
 if(reason==='TOC_READBACK_BEFORE_EXPORT')assert.deepEqual(h.events,['prepare']);
 if(['CHECKPOINT_BEFORE_API','CATALOGUE_PARITY'].includes(reason))assert.ok(!h.events.includes('start'));
 if(reason==='CHECKPOINT_AFTER_API')assert.ok(h.events.includes('healthy'));
});
test('every native, target and outer B_RESTORE site has a distinct constant diagnostic',()=>{
 const sources=['native-runtime.mjs','restore-target.mjs','core.mjs'].map(name=>readFileSync(new URL('../'+name,import.meta.url),'utf8')).join('\n');
 assert.ok(!sources.includes("'B_RESTORE'"));
 for(const reason of RESTORE_INVARIANT_REASONS)assert.equal(sources.split("'"+reason+"'").length-1,1,reason);
});

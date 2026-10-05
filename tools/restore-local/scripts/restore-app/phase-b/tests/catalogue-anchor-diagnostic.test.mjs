import test from 'node:test';
import assert from 'node:assert/strict';
import { catalogueAnchorDiagnostic, projectCatalogueAnchorDiagnostic, projectCatalogueAnchors } from '../catalogue-anchor-diagnostic.mjs';
import { validateB21Probe } from '../catalogue-semantics-diagnostic.mjs';
import { catalogueParityV2 } from '../catalogue-parity-v2.mjs';
import { catalogueRestoreDiagnostic, closedFailure, requireRestoreInvariant } from '../contract.mjs';
import { v2Fixture, PRIVATE_CANARY } from './catalogue-semantics-fixture.mjs';

function run(mutate){const v=v2Fixture();mutate?.(v.sourceProbe);return {v,out:catalogueAnchorDiagnostic(v.sourceProbe,v.source)};}
test('complete and missing probes expose only closed markers',()=>{
 assert.deepEqual(run().out,{schemaVersion:1,status:'COMPLETE',reason:'COMPLETE'});
 assert.deepEqual(catalogueAnchorDiagnostic(undefined,{}),{schemaVersion:1,status:'NOT_CAPTURED',reason:'NOT_CAPTURED'});
 assert.deepEqual(catalogueAnchorDiagnostic({schemaVersion:1,status:'CAPTURE_FAILED'},{}),{schemaVersion:1,status:'CAPTURE_FAILED',reason:'STATUS_ONLY'});
});
for(const [label,mutate,reason,status] of [
 ['anchor',p=>p.anchor.catalogue_sha256='c'.repeat(64),'ANCHOR_FIELDS','ANCHOR_MISMATCH'],
 ['current shape',p=>p.current.currentUser=PRIVATE_CANARY,'CURRENT_CAPTURE','INVALID_SHAPE'],
 ['fixed duplicate',p=>p.fixed.expressions.push(structuredClone(p.fixed.expressions[0])),'FIXED_CAPTURE','INCOMPLETE'],
 ['context',p=>p.fixed.context.search_path=PRIVATE_CANARY,'CONTEXT','CONTEXT_MISMATCH'],
 ['fixed bound',p=>p.fixed={schemaVersion:1,status:'BOUND_EXCEEDED'},'FIXED_CAPTURE','BOUND_EXCEEDED']
])test('closed location: '+label,()=>{const {out}=run(mutate);assert.deepEqual(out,{schemaVersion:1,status,reason});});
for(const [label,mutate,field] of [
 ['type spelling',p=>p.fixed.expressions[0].bindings.columns[0][1]=PRIVATE_CANARY,'bindingColumnsDifferentCount'],
 ['function spelling',p=>p.fixed.expressions[0].bindings.factKeys.at(-1)[1]=PRIVATE_CANARY,'bindingFactKeysDifferentCount'],
 ['coverage',p=>p.fixed.expressions[0].bindings.complete=false,'bindingCompleteDifferentCount'],
 ['OID',p=>p.fixed.expressions[0].localOid++,'localOidDifferentCount'],
 ['metadata',p=>p.fixed.expressions[0].metadata.permissive=false,'metadataDifferentCount'],
 ['dependencies',p=>p.fixed.expressions[0].dependencies.reverse(),'dependenciesDifferentCount'],
 ['identity',p=>p.fixed.expressions[0].identity[2]=PRIVATE_CANARY,'missingIdentityCount'],
])test('counts locate '+label+' but preserve ANCHOR refusal',()=>{
 const {v,out}=run(mutate),before=JSON.stringify(v);
 assert.equal(out.status,'INCOMPLETE');assert.equal(out.reason,'CURRENT_FIXED');assert.equal(out.counters[field],1);
 assert.equal(out.counters.changedExpressionCount,1);assert(!JSON.stringify(out).includes(PRIVATE_CANARY));
 assert.equal(validateB21Probe(v.sourceProbe,v.source),'INCOMPLETE');
 const gate=catalogueParityV2(v.source,v.target,v.sourceFacts,v.targetFacts,v.sourceProbe,v.targetProbe);
 assert.equal(gate.reason,'ANCHOR');assert.equal(gate.v2Equal,false);assert.equal(gate.expressionNormalizedCount,0);assert.equal(gate.aclNormalizedCount,0);
 assert.equal(JSON.stringify(v),before);assert.deepEqual(projectCatalogueAnchorDiagnostic(out),out);
});
test('relation drift and expression counts remain distinguishable without identities',()=>{
 const a=run(p=>p.fixed.relations[0].owner=PRIVATE_CANARY).out;assert.equal(a.counters.relationsDifferent,true);assert.equal(a.counters.changedExpressionCount,0);
 const b=run(p=>p.fixed.expressions.pop()).out;assert.equal(b.counters.currentExpressionCount,2);assert.equal(b.counters.fixedExpressionCount,1);assert.equal(b.counters.missingIdentityCount,1);
});
test('projector refuses extra data, coercion, impossible counts and forged success',()=>{
 const good=run(p=>p.fixed.expressions[0].bindings.columns[0][1]=PRIVATE_CANARY).out;
 for(const change of [v=>v.extra=PRIVATE_CANARY,v=>v.reason=PRIVATE_CANARY,v=>v.status={toString(){return PRIVATE_CANARY;}},
  v=>v.counters.bindingColumnsDifferentCount='1',v=>v.counters.bindingColumnsDifferentCount=100001,
  v=>v.counters.bindingColumnsDifferentCount=-1,v=>v.counters.bindingColumnsDifferentCount=0.5,
  v=>v.counters.changedExpressionCount=0,v=>v.counters.bindingsDifferentCount=0,
  v=>v.counters.currentExpressionCount=0,v=>v.counters.extra=PRIVATE_CANARY,v=>v.status='COMPLETE']){
  const bad=structuredClone(good);change(bad);const out=projectCatalogueAnchorDiagnostic(bad);
  assert.deepEqual(out,{schemaVersion:1,status:'INVALID_SHAPE',reason:'PROBE'});assert(!JSON.stringify(out).includes(PRIVATE_CANARY));
 }
 const circular={};circular.self=circular;assert.equal(catalogueAnchorDiagnostic(circular,{}).status,'INVALID_SHAPE');
 assert.equal(projectCatalogueAnchors({source:good,target:good,extra:PRIVATE_CANARY}).source.status,'INVALID_SHAPE');
});
test('outer restore failure reprojects anchors and cannot turn refusal into success',()=>{
 const {v,out}=run(p=>p.fixed.expressions[0].bindings.columns[0][1]=PRIVATE_CANARY);
 let error;try{requireRestoreInvariant(false,'CATALOGUE_PARITY',()=>catalogueRestoreDiagnostic(v.source,v.target,undefined,undefined,undefined,
  {source:out,target:{schemaVersion:1,status:'COMPLETE',reason:'COMPLETE',raw:PRIVATE_CANARY}}));}catch(e){error=e;}
 const closed=closedFailure(error,'restore');assert.equal(closed.code,'B_RESTORE');assert.equal(closed.restored,false);assert.equal(closed.appVerified,false);
 assert.equal(closed.restoreInvariant.catalogue.anchors.source.counters.bindingColumnsDifferentCount,1);
 assert.equal(closed.restoreInvariant.catalogue.anchors.target.status,'INVALID_SHAPE');assert(!JSON.stringify(closed).includes(PRIVATE_CANARY));
});

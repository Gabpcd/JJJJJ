import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { catalogueParityV2,projectCatalogueParityV2,catalogueV2ExpressionEqual,catalogueV2RelationEqual,catalogueBindingDiagnostic,projectCatalogueBindingDiagnostic } from '../catalogue-parity-v2.mjs';
import {catalogueRestoreDiagnostic,requireRestoreInvariant,closedFailure} from '../contract.mjs';
import { buildB21ProbeSql,ORIGINAL_SQL_SHA256 } from '../catalogue-semantics-probe.mjs';
import { v2Fixture,diagnosticArgs,PRIVATE_CANARY } from './catalogue-semantics-fixture.mjs';
const compare=f=>catalogueParityV2(...diagnosticArgs(f));
const expression=(f,kind='constraint',side='target')=>f[side+'Probe'].fixed.expressions.find(r=>r.kind===kind);
const relation=f=>f.targetProbe.current.relations[0];
const syncRelations=f=>{f.targetProbe.fixed.relations=structuredClone(f.targetProbe.current.relations);};
const syncMetadata=f=>{for(const x of f.targetProbe.fixed.expressions){const y=f.targetProbe.current.expressions.find(r=>r.kind===x.kind);y.metadata=structuredClone(x.metadata);y.dependencies=structuredClone(x.dependencies);y.bindings=structuredClone(x.bindings);}};

const bindingDiagnostic=f=>catalogueBindingDiagnostic(...diagnosticArgs(f));
function eachPolicy(f,edit){for(const side of ['source','target'])for(const view of ['current','fixed'])edit(f[side+'Probe'][view].expressions.find(x=>x.kind==='policy'));}
test('B26 exhaustively classifies changed expressions and keeps private names and definitions out',()=>{
 const f=v2Fixture(),before=JSON.stringify(f),d=bindingDiagnostic(f);
 assert.equal(d.status,'COMPLETE');assert.deepEqual(d.kinds.map(x=>[x.kind,x.selected,x.none]),[['policy',1,1],['constraint',1,1]]);
 assert.deepEqual(projectCatalogueBindingDiagnostic(d),d);assert.equal(JSON.stringify(f),before);
 assert(!JSON.stringify(d).includes(PRIVATE_CANARY));assert(!JSON.stringify(d).includes('public.subject'));
});
for(const [gate,edit] of [
 ['incompleteCoverage',f=>eachPolicy(f,p=>{p.bindings.complete=false;p.bindings.columnCount++;p.bindings.uncoveredColumns=[[['public','subject','typed'],['public',PRIVATE_CANARY],-1,null]];})],
 ['referenceFactMissing',f=>eachPolicy(f,p=>p.bindings.factKeys.push(['column','public.subject.missing']))],
 ['columnFactMissing',f=>eachPolicy(f,p=>p.bindings.columns[0][0]='public.subject.missing')],
 ['columnTypeMismatch',f=>eachPolicy(f,p=>p.bindings.columns[0][1]='integer')],
 ['metadataDifference',f=>{for(const v of ['current','fixed'])f.targetProbe[v].expressions.find(x=>x.kind==='policy').metadata.permissive=false;}],
 ['expressionDifference',f=>{for(const v of ['current','fixed'])f.targetProbe[v].expressions.find(x=>x.kind==='policy').prettyDefinition+=' changed';}]
])test('B26 identifies '+gate+' without bypassing the original refusal',()=>{
 const f=v2Fixture();edit(f);const comparison=compare(f),d=bindingDiagnostic(f);
 assert.equal(comparison.v2Equal,false);assert.equal(d.status,'COMPLETE');assert.equal(d.kinds[0][gate],1);assert.equal(d.kinds[1].none,1);
 assert.deepEqual(compare(f),comparison);assert(!JSON.stringify(d).includes(PRIVATE_CANARY));
});
test('B26 auto-only attribution never labels a column unused; explicit dependency takes precedence',()=>{
 for(const explicit of [false,true]){
  const f=v2Fixture();eachPolicy(f,p=>{
   p.bindings.complete=false;p.bindings.columnCount++;p.bindings.uncoveredColumns=[[['public','subject','typed'],['public',PRIVATE_CANARY],-1,null]];
   if(explicit)p.dependencies.push(['n','table column',['public','subject','typed'],[]]);
  });
  const row=bindingDiagnostic(f).kinds[0];assert.equal(row.sourceAutoOnly,explicit?0:1);assert.equal(row.sourceExplicit,explicit?1:0);
  assert.equal(row.sourceUncovered,1);assert.equal(row.incompleteCoverage,1);assert.equal(compare(f).v2Equal,false);
 }
});
test('B26 refuses non-expression policy fact drift even when probe metadata still matches',()=>{
 const f=v2Fixture();f.targetFacts.facts.find(x=>x[0]==='policy')[2].roles=['other'];
 assert.equal(compare(f).reason,'FACT_DRIFT');
 assert.deepEqual(bindingDiagnostic(f),{schemaVersion:1,status:'INVALID_SHAPE'});
});
test('B26 rejects columns on empty selections and uncovered columns on complete expressions',()=>{
 const d=bindingDiagnostic(v2Fixture());
 for(const side of ['source','target'])for(const empty of [false,true]){
  const v=structuredClone(d),r=v.kinds[0];
  if(empty){for(const k of Object.keys(r))if(k!=='kind')r[k]=0;r[side+'Covered']=1;r[side+'Total']=1;}
  else{r[side+'Uncovered']=1;r[side+'Total']++;r[side+'AutoOnly']=1;}
  assert.deepEqual(projectCatalogueBindingDiagnostic(v),{schemaVersion:1,status:'INVALID_SHAPE'});
 }
});
test('B26 malformed, duplicate and missing links fail closed without publishing their values',()=>{
 for(const edit of [f=>f.sourceFacts.facts.push(f.sourceFacts.facts[0]),f=>f.sourceProbe.current.expressions.pop(),
  f=>f.targetProbe.fixed.expressions[0].bindings.complete=PRIVATE_CANARY,
  f=>f.targetFacts.facts.find(x=>x[0]==='policy')[2].qual=PRIVATE_CANARY]){
  const f=v2Fixture();edit(f);assert.deepEqual(bindingDiagnostic(f),{schemaVersion:1,status:'INVALID_SHAPE'});
 }
 const d=bindingDiagnostic(v2Fixture());
 for(const edit of [v=>v.extra=PRIVATE_CANARY,v=>v.kinds[0].extra=PRIVATE_CANARY,v=>v.kinds[0].kind=PRIVATE_CANARY,
  v=>v.kinds[0].none++,v=>v.kinds[0].sourceTotal++,v=>v.kinds[0].sourceAutoOnly++,v=>v.kinds[0].selected=Infinity]){
  const v=structuredClone(d);edit(v);assert.deepEqual(projectCatalogueBindingDiagnostic(v),{schemaVersion:1,status:'INVALID_SHAPE'});
 }
});
test('B26 closed diagnostic survives actual failure publication without changing restoration flags',()=>{
 const f=v2Fixture();eachPolicy(f,p=>p.bindings.factKeys.push(['column','public.subject.missing']));const comparison=compare(f);
 const diagnostic=()=>catalogueRestoreDiagnostic(f.source,f.target,undefined,undefined,comparison,undefined,bindingDiagnostic(f));
 try{requireRestoreInvariant(false,'CATALOGUE_PARITY',diagnostic);assert.fail('must refuse');}catch(error){
  const out=closedFailure(error,'restore');assert.equal(out.restored,false);assert.equal(out.appVerified,false);assert.equal(out.readyForNationalLaunch,false);
  assert.equal(out.restoreInvariant.catalogue.comparison.v2Equal,false);assert.equal(out.restoreInvariant.catalogue.bindings.kinds[0].referenceFactMissing,1);
  assert(!JSON.stringify(out).includes(PRIVATE_CANARY));
 }
});

test('v2 compares complete private objects, keeps v1 red and never publishes identities or definitions',()=>{
 const f=v2Fixture(),before=JSON.stringify(f),r=compare(f);
 assert.deepEqual(r,{schemaVersion:2,status:'EQUAL',reason:'NORMALIZED',v1Equal:false,v2Equal:true,aclNormalizedCount:2,expressionNormalizedCount:2});
 assert.equal(JSON.stringify(f),before);assert(!JSON.stringify(r).includes(PRIVATE_CANARY));
 assert.deepEqual(projectCatalogueParityV2(r),r);
 // No dependence on B21's historical 16/1/3 scope, nor on row/tuple ordering.
 for(const k of ['sourceFacts','targetFacts'])f[k].facts.reverse();
 assert.deepEqual(compare(f),r);
});
test('exact original equality retains its own explicitly identified rule',()=>{
 const f=v2Fixture();f.target=structuredClone(f.source);f.targetFacts=structuredClone(f.sourceFacts);f.targetProbe=structuredClone(f.sourceProbe);
 assert.deepEqual(compare(f),{schemaVersion:2,status:'EQUAL',reason:'V1_EXACT',v1Equal:true,v2Equal:true,aclNormalizedCount:0,expressionNormalizedCount:0});
});
test('all original non-hash fields, unknown fields and field order remain strict',()=>{
 for(const edit of [f=>f.target.roles.push(PRIVATE_CANARY),f=>f.target.memberships.push(PRIVATE_CANARY),f=>f.target.database.push(PRIVATE_CANARY),
  f=>f.target.extra=PRIVATE_CANARY,f=>f.target=Object.fromEntries(Object.entries(f.target).reverse())]){
  const f=v2Fixture();edit(f);assert.equal(compare(f).reason,'FACT_DRIFT');
 }
});
test('missing, duplicate, ambiguous, unanchored or stale native captures refuse',()=>{
 for(const edit of [f=>delete f.sourceFacts,f=>f.targetFacts.facts.pop(),f=>f.targetFacts.facts.push(structuredClone(f.targetFacts.facts[0])),
  f=>f.sourceProbe.anchor.catalogue_sha256='c'.repeat(64),f=>f.targetProbe.fixed.postgresVersionNum=170005,
  f=>f.targetProbe.fixed.resolvedSchemas=['pg_catalog','public'],f=>f.targetProbe.fixed.expressions[0].localOid++,
  f=>f.targetProbe.current.relations.push(structuredClone(f.targetProbe.current.relations[0]))]){
  const f=v2Fixture();edit(f);assert.equal(compare(f).v2Equal,false);
 }
});
test('ACL privileges, grantor, grant option, owner, kind, provenance and EMPTY cannot disappear',()=>{
 for(const edit of [r=>r.expandedAcl.pop(),r=>r.expandedAcl[0][2]='other',r=>r.expandedAcl[0][4]=true,
  r=>r.owner='other',r=>r.relkind='S',r=>r.rawState='EMPTY',r=>r.extensionMember=true,r=>r.initialPrivilegeKinds=['e'],r=>r.identitiesResolved=false]){
  const f=v2Fixture();edit(relation(f));syncRelations(f);assert.equal(compare(f).v2Equal,false);
 }
 const f=v2Fixture(),a=f.sourceProbe.current.relations[0],b=relation(f);
 a.extensionMember=b.extensionMember=true;assert.equal(catalogueV2RelationEqual(a,b),false);
});
test('all 16 constraint metadata fields remain significant even when pretty expressions match',()=>{
 const sample=expression(v2Fixture());
 for(const key of Object.keys(sample.metadata)){
  const f=v2Fixture(),v=expression(f).metadata;
  v[key]=typeof v[key]==='boolean'?!v[key]:typeof v[key]==='number'?v[key]+1:typeof v[key]==='string'?v[key]+'x':v[key]===null?[]:[];
  syncMetadata(f);assert.equal(compare(f).v2Equal,false,key);
 }
});
test('pretty CHECK body, policy WITH CHECK, predicates and complete resolved dependencies remain strict',()=>{
 for(const edit of [f=>expression(f).secondaryPrettyDefinition+=' OR true',f=>expression(f).secondaryPrettyDefinition=null,
  f=>expression(f,'policy').secondaryDefinition='b',f=>expression(f).prettyDefinition+=' OR true',
  f=>expression(f).dependencies.push(['n','collation',['other','collation'],[]]),
  f=>expression(f).dependencies[0][1]=null,f=>expression(f).metadata.conkey=[null]]){
  const f=v2Fixture();edit(f);syncMetadata(f);assert.equal(compare(f).v2Equal,false);
 }
});
test('uncovered bindings, missing referred facts and changed referred bodies cannot be accepted',()=>{
 for(const edit of [f=>expression(f).bindings.complete=false,
  f=>expression(f).bindings.factKeys.push(['function','public.missing()']),
  f=>expression(f).bindings.columns[0][2]=['pg_catalog','C'],
  f=>f.targetFacts.facts.find(r=>r[0]==='function')[2][0]+=' changed',
  f=>f.targetFacts.facts.find(r=>r[0]==='column')[2][0]='integer']){
  const f=v2Fixture();edit(f);syncMetadata(f);assert.equal(compare(f).v2Equal,false);
 }
});
test('normalization cannot erase another family, column ACL, function NULL default or a missing object',()=>{
 for(const edit of [f=>f.targetFacts.facts.find(r=>r[0]==='column')[2][4]=[],
  f=>f.targetFacts.facts.find(r=>r[0]==='function')[2][2]=null,
  f=>{for(const side of ['sourceFacts','targetFacts'])f[side].facts.push(['extension','example',['1','public','owner'],null]);f.targetFacts.facts.at(-1)[2][0]='2';},
  f=>f.targetFacts.facts.find(r=>r[0]==='relation')[2][1]=true]){
  const f=v2Fixture();edit(f);assert.equal(compare(f).v2Equal,false);
 }
});
test('non-CHECK constraints are outside the pretty exception and local OIDs are not identities',()=>{
 const f=v2Fixture(),a=expression(f,'constraint','source'),b=expression(f);
 b.localOid=4294967295;assert.equal(catalogueV2ExpressionEqual(a,b),true);
 a.metadata.contype=b.metadata.contype='f';assert.equal(catalogueV2ExpressionEqual(a,b),false);
});
test('a raw hash mismatch without a witnessed object delta never becomes green',()=>{
 const f=v2Fixture();f.targetFacts=structuredClone(f.sourceFacts);f.targetProbe=structuredClone(f.sourceProbe);f.targetProbe.anchor=structuredClone(f.target);
 assert.equal(compare(f).reason,'HASH_WITHOUT_FACT_DELTA');
});
test('closed receipt rejects extra values, fabricated success states and arbitrary counts',()=>{
 const r=compare(v2Fixture());for(const patch of [{private:PRIVATE_CANARY},{v1Equal:true},{status:'REFUSED'},{reason:'UNKNOWN'},
  {aclNormalizedCount:-1},{expressionNormalizedCount:100001},{aclNormalizedCount:100000,expressionNormalizedCount:100000},
  {status:'REFUSED',reason:'SHAPE',v1Equal:true,v2Equal:false},{aclNormalizedCount:0,expressionNormalizedCount:0}]){
  const out=projectCatalogueParityV2({...r,...patch});assert.equal(out.v2Equal,false);assert(!JSON.stringify(out).includes(PRIVATE_CANARY));
 }
});
test('v1 SQL stays pinned and v2 uses native body and conservative builtin coverage',()=>{
 const raw=readFileSync(new URL('../../sql/catalogue.sql',import.meta.url),'utf8');
 assert.equal(createHash('sha256').update(raw).digest('hex'),ORIGINAL_SQL_SHA256);
 const sql=buildB21ProbeSql(raw);
 assert(sql.includes('pg_get_expr(k.conbin,k.conrelid,true)'));assert(sql.includes("oid<16384 AND typnamespace='pg_catalog'::regnamespace"));
 assert(sql.includes('coalesce(p.proallargtypes,p.proargtypes::oid[])||p.prorettype'));
 assert(sql.includes('a.attcollation IN(SELECT oid FROM builtin_collations)'));assert(!sql.includes('UPDATE pg_'));
});

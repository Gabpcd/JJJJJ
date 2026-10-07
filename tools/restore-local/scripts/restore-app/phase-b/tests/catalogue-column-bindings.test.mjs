import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { validB21Expression,validateB21Probe } from '../catalogue-semantics-diagnostic.mjs';
import { catalogueParityV2 } from '../catalogue-parity-v2.mjs';
import { catalogueAnchorDiagnostic,projectCatalogueAnchorDiagnostic } from '../catalogue-anchor-diagnostic.mjs';
import { buildB21ProbeSql,b21WitnessCaptureSql,b23LegacyWitnessCaptureSql } from '../catalogue-semantics-probe.mjs';
import { validateB24ColumnWitnesses } from '../catalogue-semantics-witness.mjs';
import { b24ColumnFixture,v2Fixture,expression,PRIVATE_CANARY } from './catalogue-semantics-fixture.mjs';

test('explicit binding schema preserves covered strings and rejects omissions/overlap/false coverage',()=>{
 const row=b24ColumnFixture().find(x=>x.name==='MIXED_CONTEXT').left.expressions[0];assert(validB21Expression(row));
 assert.deepEqual(row.bindings.columns,[['public.subject.id','integer',null]]);
 for(const edit of [b=>delete b.uncoveredColumns,b=>delete b.columnCount,b=>b.schemaVersion=1,b=>b.extra=PRIVATE_CANARY,
  b=>b.complete=true,b=>b.columnCount=1,b=>b.columnCount=3,b=>b.uncoveredColumns=[],
  b=>b.uncoveredColumns.push(structuredClone(b.uncoveredColumns[0])),
  b=>b.uncoveredColumns[0][0]=['public','subject','id'],b=>b.uncoveredColumns[0][1]=[null,'type'],
  b=>b.uncoveredColumns[0][2]='-1',b=>b.uncoveredColumns[0][2]=2147483648,b=>b.uncoveredColumns[0][2]=-2147483649,
  b=>b.uncoveredColumns[0][2]=0.5,b=>b.uncoveredColumns[0][3]=[],b=>b.uncoveredColumns[0].push(PRIVATE_CANARY)]){
  const x=structuredClone(row);edit(x.bindings);assert.equal(validB21Expression(x),false);
 }
 for(const value of [-2147483648,-1,0,2147483647]){const x=structuredClone(row);x.bindings.uncoveredColumns[0][2]=value;assert(validB21Expression(x));}
});
test('new native cases use the actual validator but cannot grant an uncovered exception',()=>{
 assert.deepEqual(validateB24ColumnWitnesses(b24ColumnFixture()),{columnBindingCases:10,columnBindingSameValidator:true});
 for(const edit of [v=>v.pop(),v=>v.push(v[0]),v=>v[0].extra=PRIVATE_CANARY,
  v=>v[0].right.expressions[0].bindings.complete=true,
  v=>v[0].left.expressions[0].localOid++,
  v=>v.find(r=>r.name==='TYPE_CHANGE').right=structuredClone(v.find(r=>r.name==='TYPE_CHANGE').left),
  v=>v.find(r=>r.name==='WHOLE_ROW_TYPE_CHANGE').right=structuredClone(v.find(r=>r.name==='WHOLE_ROW_TYPE_CHANGE').left),
  v=>v.find(r=>r.name==='TYPEMOD_CHANGE').right.expressions[0].bindings.uncoveredColumns[0][2]=12,
  v=>v.find(r=>r.name==='MIXED_CONTEXT').left.expressions[0].bindings.columns=[],
  v=>v.find(r=>r.name==='FUNCTION_CONTEXT').right=structuredClone(v.find(r=>r.name==='FUNCTION_CONTEXT').left)]){
  const rows=b24ColumnFixture();edit(rows);assert.throws(()=>validateB24ColumnWitnesses(rows),/B_SEMANTICS_WITNESS/);
 }
});
for(const [name,index,value] of [['type',1,['private',PRIVATE_CANARY]],['typmod',2,13],['collation',3,['private',PRIVATE_CANARY]]])
 test('a whole-row policy '+name+' drift refuses the anchor with no normalization',()=>{
  const pair=b24ColumnFixture().find(x=>x.name==='WHOLE_ROW_CONTEXT');
  const original={catalogue_sha256:'a'.repeat(64),database:[],roles:[],memberships:[]};
  pair.right.expressions[0].bindings.uncoveredColumns[0][index]=value;
  const probe={anchor:original,current:pair.left,fixed:pair.right};
  assert.equal(validateB21Probe(probe,original),'INCOMPLETE');
  const target={...original,catalogue_sha256:'b'.repeat(64)};
  const facts={schemaVersion:1,status:'COMPLETE',facts:[]};
  const result=catalogueParityV2(original,target,facts,facts,probe,{anchor:target,current:pair.right,fixed:pair.right});
  assert.equal(result.v2Equal,false);assert.equal(result.reason,'ANCHOR');
  assert.equal(result.expressionNormalizedCount,0);assert.equal(result.aclNormalizedCount,0);
  assert(!JSON.stringify(result).includes(PRIVATE_CANARY));
 });
for(const [name,index,value] of [['type',1,['private',PRIVATE_CANARY]],['typmod',2,13],['collation',3,['private',PRIVATE_CANARY]]])
 test('a real '+name+' drift remains INCOMPLETE and is located without publishing the value',()=>{
  const pair=b24ColumnFixture()[0],original={catalogue_sha256:'a'.repeat(64),database:[],roles:[],memberships:[]};
  pair.right.expressions[0].bindings.uncoveredColumns[0][index]=value;
  const probe={anchor:original,current:pair.left,fixed:pair.right};assert.equal(validateB21Probe(probe,original),'INCOMPLETE');
  const out=catalogueAnchorDiagnostic(probe,original);assert.equal(out.counters.bindingColumnsDifferentCount,1);
  assert.equal(out.counters.bindingsDifferentCount,1);assert.deepEqual(projectCatalogueAnchorDiagnostic(out),out);
  assert(!JSON.stringify(out).includes(PRIVATE_CANARY));
 });
test('an unchanged outside-coverage object can anchor, but a changed one is still BINDING_UNCOVERED',()=>{
 const v=v2Fixture();
 for(const probe of [v.sourceProbe,v.targetProbe])for(const view of ['current','fixed']){
  const row=probe[view].expressions[0];row.bindings.complete=false;row.bindings.columnCount++;
  row.bindings.uncoveredColumns=[[['public','subject','typed'],['public','synthetic_domain'],-1,null]];
 }
 assert.equal(validateB21Probe(v.sourceProbe,v.source),'COMPLETE');assert.equal(validateB21Probe(v.targetProbe,v.target),'COMPLETE');
 const result=catalogueParityV2(v.source,v.target,v.sourceFacts,v.targetFacts,v.sourceProbe,v.targetProbe);
 assert.equal(result.reason,'BINDING_UNCOVERED');assert.equal(result.v2Equal,false);assert.equal(result.expressionNormalizedCount,0);
});
test('an unchanged uncovered CHECK preserves all existing normalization gates for other objects',()=>{
 const v=v2Fixture(),row=expression('constraint','unchanged_uncovered');
 row.definition=row.prettyDefinition='CHECK (typed IS NOT NULL)';row.metadata.conkey=['typed'];
 row.bindings={schemaVersion:2,complete:false,columnCount:1,factKeys:[['column','public.subject.typed']],columns:[],
  uncoveredColumns:[[['public','subject','typed'],['public','synthetic_domain'],-1,null]]};
 row.dependencies=[['a','table column',['public','subject','typed'],[]]];
 for(const side of ['source','target']){
  v[side+'Facts'].facts.push(['column','public.subject.typed',['synthetic_domain',false,'','',null,null],null],
   ['constraint',row.identity.join('.'),row.definition,null]);
  for(const view of ['current','fixed'])v[side+'Probe'][view].expressions.push(structuredClone(row));
 }
 const result=catalogueParityV2(v.source,v.target,v.sourceFacts,v.targetFacts,v.sourceProbe,v.targetProbe);
 assert.equal(result.v2Equal,true);assert.equal(result.v1Equal,false);assert.equal(result.expressionNormalizedCount,2);
 v.targetFacts.facts.at(-1)[2]='CHECK (typed IS NULL)';
 for(const view of ['current','fixed']){
  const r=v.targetProbe[view].expressions.at(-1);r.definition=r.prettyDefinition='CHECK (typed IS NULL)';
 }
 const refused=catalogueParityV2(v.source,v.target,v.sourceFacts,v.targetFacts,v.sourceProbe,v.targetProbe);
 assert.equal(refused.v2Equal,false);assert.equal(refused.reason,'BINDING_UNCOVERED');
});
test('covered column links to v1 and function key rendering stay exact',()=>{
 const v=v2Fixture();v.sourceProbe.fixed.expressions[0].bindings.columns[0][1]='pg_catalog.boolean';
 assert.equal(validateB21Probe(v.sourceProbe,v.source),'INCOMPLETE');
 const f=b24ColumnFixture().find(r=>r.name==='FUNCTION_CONTEXT'),original={catalogue_sha256:'a'.repeat(64),database:[],roles:[],memberships:[]};
 assert.equal(validateB21Probe({anchor:original,current:f.left,fixed:f.right},original),'INCOMPLETE');
});
test('SQL remains read-only, keeps v1 bytes and splits columns only after coverage evaluation',()=>{
 const original=readFileSync(new URL('../../sql/catalogue.sql',import.meta.url),'utf8'),sql=buildB21ProbeSql(original);
 assert.equal(createHash('sha256').update(original).digest('hex'),'29098b4dc0caf44f2a4501517603ee8fa78b2b00ab84a0ca7a34031dadc63969');
 assert(sql.includes(original.slice('BEGIN READ ONLY;\n'.length,-'ROLLBACK;\n'.length)));
 assert.match(sql,/coalesce\(bool_and\(b.covered\),true\)/);assert.match(sql,/NOT a.types_covered/);
 assert.match(sql,/count\(DISTINCT a.column_identity\)/);assert.match(sql,/FILTER\(WHERE a.types_covered\)/);
 assert.match(sql,/FILTER\(WHERE NOT a.types_covered\)/);assert(sql.includes('OR z.whole_row'));
 assert(sql.includes("pg_get_function_identity_arguments(p.oid)"));assert(!sql.includes('capture_legacy'));
 assert(!sql.includes('CREATE FUNCTION'));assert(sql.endsWith('ROLLBACK;\n'));
 const legacy=b23LegacyWitnessCaptureSql();assert(!legacy.includes('FILTER(WHERE a.types_covered)'));
 assert(legacy.includes('format_type(a.atttypid,a.atttypmod)'));assert(legacy.includes('capture_legacy()'));
 assert(b21WitnessCaptureSql('b21_expr').includes('FILTER(WHERE a.types_covered)'));
});

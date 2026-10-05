import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildB21ProbeSql,decodeB21Probe,b21WitnessCaptureSql } from '../catalogue-semantics-probe.mjs';
import { catalogueSemanticsDiagnostic,projectCatalogueSemanticsDiagnostic,compareB21Relation,compareB21Expression,validateB21Probe } from '../catalogue-semantics-diagnostic.mjs';
import { catalogueRestoreDiagnostic,requireRestoreInvariant,closedFailure } from '../contract.mjs';
import { b21Fixture,diagnosticArgs,relation,expression,PRIVATE_CANARY } from './catalogue-semantics-fixture.mjs';
const compare=v=>catalogueSemanticsDiagnostic(...diagnosticArgs(v));
const safe=v=>{assert.ok(!JSON.stringify(v).includes(PRIVATE_CANARY));return v;};
test('B21 explains all 16 NULL transitions and 1+3 definitions without changing a raw refusal',()=>{
 const f=b21Fixture(),d=safe(compare(f));assert.equal(d.status,'COMPLETE');assert.equal(d.acl.equalCount,16);
 assert.equal(d.acl.nullToPresentCount,16);assert.equal(d.expressions[0].strictFixedEqualCount,1);assert.equal(d.expressions[1].strictFixedEqualCount,3);
 assert.throws(()=>requireRestoreInvariant(false,'CATALOGUE_PARITY',()=>catalogueRestoreDiagnostic(f.source,f.target,undefined,d)),e=>{
  const receipt=safe(closedFailure(e,'restore'));assert.equal(receipt.code,'B_RESTORE');assert.equal(receipt.restored,false);assert.equal(receipt.restoreInvariant.catalogue.semantics.status,'COMPLETE');return true;});
});
test('NULL/empty, owner, grantor, PUBLIC, grant options, relkind and unknown identities stay distinct',()=>{
 const a=relation(),different=edit=>{const b=structuredClone(a);edit(b);return compareB21Relation(a,b);};
 assert.equal(different(b=>{b.rawState='EMPTY';b.expandedAcl=[];}),'differentCount');
 assert.equal(different(b=>b.owner='other'),'ownerDifferentCount');
 assert.equal(different(b=>b.expandedAcl[0][2]='other'),'differentCount');
 assert.equal(different(b=>b.expandedAcl[0][4]=true),'differentCount');
 assert.equal(different(b=>b.expandedAcl[0].splice(0,2,'PUBLIC',null)),'differentCount');
 assert.equal(different(b=>{b.relkind='S';b.expandedAcl=[['ROLE','owner','owner','USAGE',false]];}),'inconsistentCount');
 assert.equal(different(b=>{b.relkind='i';b.supported=false;b.expandedAcl=null;}),'unsupportedCount');
 assert.equal(different(b=>b.identitiesResolved=false),'inconsistentCount');
 assert.equal(different(b=>b.expandedAcl.reverse()),'equalCount');
 const pub={...a,expandedAcl:[['PUBLIC',null,'owner','SELECT',false]]};
 assert.equal(compareB21Relation(pub,{...pub,expandedAcl:[['ROLE','PUBLIC','owner','SELECT',false]]}),'differentCount');
});
test('same dependencies do not erase a predicate, validation or deferrability change',()=>{
 const a=expression(),b=structuredClone(a);b.definition+=' changed';b.prettyDefinition+=' changed';b.metadata.convalidated=false;
 const d=compareB21Expression(a,b);assert.equal(d.definition,'persistentDifferenceCount');assert.equal(d.dependencies,'dependenciesEqualCount');assert.ok(d.fields.includes('convalidated'));
 b.metadata.condeferrable=true;assert.ok(compareB21Expression(a,b).fields.includes('condeferrable'));
 b.prettyDefinition=a.prettyDefinition;assert.equal(compareB21Expression(a,b).definition,'prettyOnlyConvergedCount');
 b.metadata.conkey=[null];assert.equal(compareB21Expression(a,b).dependencies,'dependenciesIncompleteCount');
 const empty=structuredClone(a);empty.metadata.conkey=[];empty.metadata.operators.conexclop=[];
 assert.deepEqual(compareB21Expression(a,empty).fields,['conkey','operators']);
});
test('all crosschecks are closed for missing, changed, ambiguous or forged private capture',()=>{
 for(const [edit,status] of [
  [f=>delete f.sourceProbe,'NOT_CAPTURED'],[f=>f.sourceProbe.anchor.roles.push('changed'),'ANCHOR_MISMATCH'],
  [f=>f.sourceProbe.current.relations.push(structuredClone(f.sourceProbe.current.relations[0])),'INCOMPLETE'],
  [f=>f.targetFacts.facts.pop(),'INCOMPLETE'],[f=>f.targetProbe.fixed.context.TimeZone='PRIVATE','CONTEXT_MISMATCH'],
  [f=>f.targetProbe.current.secret=PRIVATE_CANARY,'INVALID_SHAPE'],[f=>f.targetProbe.current.expressions[0].metadata.rolesResolved=false,'INVALID_SHAPE'],
  [f=>f.sourceProbe.current={schemaVersion:1,status:'BOUND_EXCEEDED'},'BOUND_EXCEEDED'],
 ]){const f=b21Fixture();edit(f);assert.equal(safe(compare(f)).status,status);}
});
test('public projection rejects extra fields, forged enums, arithmetic and nonfinite counts',()=>{
 const good=compare(b21Fixture());assert.deepEqual(projectCatalogueSemanticsDiagnostic(good),good);
 for(const edit of [v=>v.sql=PRIVATE_CANARY,v=>v.acl.secret=PRIVATE_CANARY,v=>v.acl.equalCount=17,v=>v.acl.equalCount=NaN,
  v=>v.context[0].current=PRIVATE_CANARY,v=>v.expressions[0].selectedCount=2,v=>v.constraints.kinds[0].count=4,
  v=>v.constraints.fields[0].changedCount=1,v=>v.acl.relkinds[0].relkind=PRIVATE_CANARY]){
  const v=structuredClone(good);edit(v);assert.deepEqual(safe(projectCatalogueSemanticsDiagnostic(v)),{schemaVersion:1,status:'INVALID_SHAPE'});
 }
});
test('probe keeps original body bytes, fixes context in one read-only snapshot and decodes only three bounded JSON lines',()=>{
 const original=readFileSync(new URL('../../sql/catalogue.sql',import.meta.url),'utf8'),sql=buildB21ProbeSql(original);
 assert.ok(sql.includes(original.slice('BEGIN READ ONLY;\n'.length,-'ROLLBACK;\n'.length)));
 assert.ok(sql.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'));assert.ok(sql.endsWith('ROLLBACK;\n'));
 assert.equal((sql.match(/WITH expression_objects AS/g)||[]).length,2);assert.ok(sql.includes("THEN 's'::\"char\" ELSE 'r'::\"char\""));
 assert.ok(sql.includes("SELECT coalesce(jsonb_agg(jsonb_build_array(a.type,a.object_names,a.object_args) ORDER BY q.ord),'[]'::jsonb)"));
 assert.throws(()=>buildB21ProbeSql(original+' '),/B21_SQL_PIN/);assert.throws(()=>b21WitnessCaptureSql('public'),/B21_WITNESS_SCOPE/);
 const f=b21Fixture(),p=f.sourceProbe;assert.deepEqual(decodeB21Probe(Buffer.from([p.anchor,p.current,p.fixed].map(JSON.stringify).join('\n'))),p);
 assert.equal(validateB21Probe(p,f.source),'COMPLETE');assert.throws(()=>decodeB21Probe(Buffer.from('{}\n{}\n{}\n{}')),/B21_PRIVATE_SHAPE/);
});

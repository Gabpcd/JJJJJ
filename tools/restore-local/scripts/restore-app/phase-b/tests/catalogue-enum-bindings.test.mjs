import test from 'node:test';
import assert from 'node:assert/strict';
import {enumColumnValid,columnFactTypeMatches,extendScalarEnumBindings} from '../catalogue-enum-bindings.mjs';
import {catalogueParityV2} from '../catalogue-parity-v2.mjs';
import {v2Fixture,diagnosticArgs} from './catalogue-semantics-fixture.mjs';
const compare=f=>catalogueParityV2(...diagnosticArgs(f));
function fixture(exact=false){
 const f=v2Fixture();
 for(const side of ['source','target']){
  f[side+'Facts'].facts.push(['column','public.subject.status',['enum_status',false,'','',null,null],null]);
  for(const view of ['current','fixed']){
   const p=f[side+'Probe'][view].expressions.find(r=>r.kind==='policy');
   p.bindings.columnCount++;p.bindings.columns.push(['public.subject.status','public.enum_status',null,
    {schemaVersion:1,shape:'PG17_SCALAR_ENUM',column:['public','subject','status'],identity:['public','enum_status'],owner:'owner',acl:null,labels:['ONLINE','AWAY','OFFLINE']}]);
  }
 }
 if(exact){f.target=structuredClone(f.source);f.targetFacts=structuredClone(f.sourceFacts);f.targetProbe=structuredClone(f.sourceProbe);}
 return f;
}
const column=p=>p.expressions.find(r=>r.kind==='policy').bindings.columns.at(-1);
for(const exact of [false,true]){
 test(`scalar enum proof accepts stable ordered labels and owner with raw equality=${exact}`,()=>{
  const f=fixture(exact),before=JSON.stringify(f);assert.equal(compare(f).v2Equal,true);assert.equal(compare(f).reason,exact?'V1_EXACT':'NORMALIZED');assert.equal(JSON.stringify(f),before);
 });
 const edits={label_add:c=>c[3].labels.push('BUSY'),label_rename:c=>c[3].labels[1]='BUSY',label_order:c=>c[3].labels.reverse(),
 owner:c=>c[3].owner='other',acl:c=>c[3].acl=['owner=U/owner'],missing_proof:c=>c.pop(),
 wrong_column:c=>c[3].column[2]='other',wrong_type:c=>c[3].identity[1]='other',duplicate_label:c=>c[3].labels.push('ONLINE'),
 extra_field:c=>c[3].extra=true,bad_collation:c=>c[2]=['public','other'],unsupported_shape:c=>c[3].shape='DOMAIN'};
 for(const [name,edit] of Object.entries(edits))test(`enum ${name} refuses with raw equality=${exact}`,()=>{
  const f=fixture(exact);for(const v of ['current','fixed'])edit(column(f.targetProbe[v]));assert.equal(compare(f).v2Equal,false);
 });
 for(const mode of ['duplicate','missing_fact','wrong_fact','current_fixed_disagree'])test(`enum ${mode} refuses with raw equality=${exact}`,()=>{
  const f=fixture(exact);
  if(mode==='missing_fact')for(const s of ['source','target'])f[s+'Facts'].facts.pop();
  if(mode==='wrong_fact')for(const s of ['source','target'])f[s+'Facts'].facts.at(-1)[2][0]='other_enum';
  if(mode==='duplicate')for(const v of ['current','fixed']){const p=f.targetProbe[v].expressions.find(r=>r.kind==='policy');p.bindings.columns.push(structuredClone(column(f.targetProbe[v])));p.bindings.columnCount++;}
  if(mode==='current_fixed_disagree')column(f.targetProbe.current)[3].labels.reverse();
  assert.equal(compare(f).v2Equal,false);
 });
}
test('same raw catalogue cannot bypass missing or stale private capture',()=>{
 for(const mutate of [f=>delete f.sourceProbe,f=>f.targetProbe.anchor.catalogue_sha256='c'.repeat(64),f=>delete f.targetFacts]){
  const f=fixture(true);mutate(f);assert.equal(compare(f).v2Equal,false);
 }
});
test('enum fact type only accepts the captured exact qualified or visible name',()=>{
 const c=column(fixture().sourceProbe.fixed);assert(enumColumnValid(c));
 for(const value of ['public.enum_status','enum_status'])assert(columnFactTypeMatches(c,value));
 for(const value of ['other.enum_status','enum_status[]','public.enum_status[]','integer','ENUM_STATUS'])assert.equal(columnFactTypeMatches(c,value),false);
});
test('enum renderer rejects missing and ambiguous SQL insertion points',()=>{
 for(const q of ['', '), covered_columns AS (', '), covered_columns AS (), covered_columns AS ('])assert.throws(()=>extendScalarEnumBindings(q),/B27_ENUM_RENDER_SCOPE/);
});

test('raw equality ignores fact row order but preserves every internal value',()=>{
 const f=fixture(true);f.targetFacts.facts.reverse();assert.equal(compare(f).reason,'V1_EXACT');
 f.targetFacts.facts.find(x=>x[0]==='column')[2][1]=true;assert.equal(compare(f).v2Equal,false);
});

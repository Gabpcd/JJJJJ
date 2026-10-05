import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { catalogueDiagnosticSql, catalogueFactsDiagnostic, projectCatalogueFactsDiagnostic,
 CATALOGUE_KINDS, CATALOGUE_FIELDS, CATALOGUE_PRIVATE_KEY, CATALOGUE_FACT_BOUND, CATALOGUE_FACT_BYTES,
 CATALOGUE_DIAGNOSTIC_BYTES } from '../catalogue-facts-diagnostic.mjs';
import { catalogueRestoreDiagnostic, projectRestoreInvariant, requireRestoreInvariant, closedFailure } from '../contract.mjs';

const canary='PRIVATE_SQL_AUTH_TOKEN_IDENTITY_CANARY';
const grants=()=>[['ROLE',canary+'recipient',canary+'grantor','SELECT',false],['PUBLIC',null,canary+'grantor','UPDATE',true]];
const acl=()=>[canary+'recipient=r/'+canary+'grantor','=w*/'+canary+'grantor'];
function facts() { return [
 ['relation',canary+'.table',['r',true,false,canary,acl()],grants()],
 ['column',canary+'.table.column',['text',true,'','',acl(),canary+' default'],grants()],
 ['function',canary+'.function()',[canary+' definition',canary,acl()],grants()],
 ['policy',canary+'.table.policy',{schemaname:canary,tablename:canary,policyname:canary,permissive:'PERMISSIVE',roles:[canary],cmd:'ALL',qual:canary,with_check:null},null],
 ['trigger',canary+'.table.trigger',[canary+' definition','O'],null],
 ['constraint',canary+'.table.constraint',canary+' definition',null],
 ['index',canary+'.index',canary+' definition',null],
 ['extension',canary,['1.0',canary,canary],null],
 ['default_acl',canary+'.global.r',acl(),grants()],
 ]; }
const capture=rows=>({schemaVersion:1,status:'COMPLETE',facts:rows});
const compare=(a,b)=>catalogueFactsDiagnostic(capture(a),capture(b));
const row=(v,kind)=>v.kinds.find(v=>v.kind===kind);
const safe=value=>{assert.ok(!JSON.stringify(value).includes(canary));return value;};
const changeValue=(v,p)=>p==='value'?v[2]=canary+' changed':v[2][p]=typeof v[2][p]==='boolean'?!v[2][p]:Array.isArray(v[2][p])?[canary+' changed']:canary+' changed';

test('all nine kinds and every fixed field are present even when identical',()=>{
 const a=facts(),before=JSON.stringify(a),out=safe(compare(a,structuredClone(a)));
 assert.equal(out.status,'COMPLETE');assert.deepEqual(out.kinds.map(v=>v.kind),CATALOGUE_KINDS);
 for(const k of CATALOGUE_KINDS){const v=row(out,k);assert.equal(v.sourceCount,1);assert.equal(v.targetCount,1);assert.equal(v.unchangedCount,1);assert.equal(v.changedCount,0);assert.ok(v.fields.every(f=>f.changedCount===0));}
 assert.equal(JSON.stringify(a),before);assert.ok(Buffer.byteLength(JSON.stringify(out))<=CATALOGUE_DIAGNOSTIC_BYTES);
});
for(const kind of CATALOGUE_KINDS)for(const field of CATALOGUE_FIELDS[kind].filter(f=>f.field!=='acl'))test('locates only fixed field '+kind+'.'+field.field,()=>{
 const a=facts(),b=facts(),v=b.find(v=>v[0]===kind);changeValue(v,field.position);
 const out=safe(compare(a,b));assert.equal(out.status,'COMPLETE');const changed=row(out,kind);
 assert.equal(changed.changedCount,1);assert.deepEqual(changed.fields.filter(v=>v.changedCount).map(v=>v.position),[field.position]);
 for(const other of out.kinds.filter(v=>v.kind!==kind))assert.equal(other.changedCount,0);
});
for(const kind of CATALOGUE_KINDS)test('counts additions and removals without names '+kind,()=>{
 const a=facts(),b=facts();b.find(v=>v[0]===kind)[1]+=canary+' other';const out=safe(compare(a,b));
 assert.equal(out.status,'COMPLETE');assert.equal(row(out,kind).sourceOnlyCount,1);assert.equal(row(out,kind).targetOnlyCount,1);assert.equal(row(out,kind).changedCount,0);
});
test('JSONB object key order is ignored in advisory facts but not array order',()=>{
 const a=facts(),b=facts();const policy=b.find(v=>v[0]==='policy');policy[2]=Object.fromEntries(Object.entries(policy[2]).reverse());
 assert.equal(row(compare(a,b),'policy').unchangedCount,1);
 policy[2].roles.push(canary+' second');a.find(v=>v[0]==='policy')[2].roles.unshift(canary+' second');
 assert.equal(row(compare(a,b),'policy').fields.find(v=>v.field==='roles').changedCount,1);
});
for(const kind of ['relation','column','function','default_acl'])test('ACL ordering is advisory and never changes the hash refusal '+kind,()=>{
 const a=facts(),b=facts(),v=b.find(v=>v[0]===kind),p=CATALOGUE_FIELDS[kind].find(v=>v.field==='acl').position;
 (p==='value'?v[2]:v[2][p]).reverse();v[3].reverse();const delta=safe(compare(a,b));
 assert.equal(delta.status,'COMPLETE');assert.equal(row(delta,kind).acl.orderOnlyCount,1);assert.equal(row(delta,kind).acl.rightsDifferentCount,0);
 const source={catalogue_sha256:'a'.repeat(64)},target={catalogue_sha256:'b'.repeat(64)};
 assert.throws(()=>requireRestoreInvariant(JSON.stringify(source)===JSON.stringify(target),'CATALOGUE_PARITY',()=>catalogueRestoreDiagnostic(source,target,delta)),error=>{
  const out=safe(closedFailure(error,'restore'));assert.equal(out.code,'B_RESTORE');assert.equal(out.restored,false);assert.equal(out.appVerified,false);assert.equal(out.readyForNationalLaunch,false);
  assert.equal(row(out.restoreInvariant.catalogue.facts,kind).acl.orderOnlyCount,1);return true;
 });
});
for(const kind of ['relation','column','function','default_acl'])test('ACL multiplicity is representation difference, never order only '+kind,()=>{
 const a=facts(),b=facts(),v=b.find(v=>v[0]===kind),p=CATALOGUE_FIELDS[kind].find(v=>v.field==='acl').position;
 const raw=p==='value'?v[2]:v[2][p];raw.push(raw[0]);v[3].push(structuredClone(v[3][0]));
 const before=JSON.stringify([a,b]),delta=safe(compare(a,b));assert.equal(delta.status,'COMPLETE');
 const summary=row(delta,kind).acl;assert.equal(summary.representationDifferentCount,1);
 assert.equal(summary.orderOnlyCount,0);assert.equal(summary.rightsDifferentCount,0);
 assert.equal(summary.sourceOnlyTupleCount,0);assert.equal(summary.targetOnlyTupleCount,0);
 assert.equal(JSON.stringify([a,b]),before);
 assert.throws(()=>requireRestoreInvariant(false,'CATALOGUE_PARITY',()=>catalogueRestoreDiagnostic(
  {catalogue_sha256:'a'.repeat(64)},{catalogue_sha256:'b'.repeat(64)},delta)),error=>{
   const out=safe(closedFailure(error,'restore'));assert.equal(out.code,'B_RESTORE');assert.equal(out.restored,false);
   assert.equal(row(out.restoreInvariant.catalogue.facts,kind).acl.representationDifferentCount,1);return true;
  });
});
test('a genuine ACL permutation preserves multiplicities and remains order only',()=>{
 const a=facts();a[0][2][4].push(a[0][2][4][0]);a[0][3].push(structuredClone(a[0][3][0]));
 const b=structuredClone(a);b[0][2][4].reverse();b[0][3].reverse();
 // The duplicate first item makes reverse palindromic; rotate to change order.
 b[0][2][4].push(b[0][2][4].shift());
 const out=safe(compare(a,b));assert.equal(out.status,'COMPLETE');
 assert.equal(row(out,'relation').acl.orderOnlyCount,1);
 assert.equal(row(out,'relation').acl.representationDifferentCount,0);
});
test('equivalent privilege sets with differently grouped ACL entries are representation only',()=>{
 const a=facts(),b=facts(),tuples=[['ROLE',canary+'recipient',canary+'grantor','SELECT',false],
  ['ROLE',canary+'recipient',canary+'grantor','UPDATE',false]];
 a[0][2][4]=[canary+'recipient=rw/'+canary+'grantor'];a[0][3]=structuredClone(tuples);
 b[0][2][4]=[canary+'recipient=r/'+canary+'grantor',canary+'recipient=w/'+canary+'grantor'];b[0][3]=structuredClone(tuples);
 const out=safe(compare(a,b));assert.equal(out.status,'COMPLETE');
 const summary=row(out,'relation').acl;assert.equal(summary.representationDifferentCount,1);
 assert.equal(summary.orderOnlyCount,0);assert.equal(summary.rightsDifferentCount,0);
});
for(const position of [0,1,2,3,4])test('ACL tuple identities and grant options compare privately at position '+position,()=>{
 const a=facts(),b=facts(),v=b[0];v[2][4]=[canary+' changed'];
 if(position===0){v[3][0][0]='PUBLIC';v[3][0][1]=null;}
 else v[3][0][position]=position===4?true:position===3?'DELETE':canary+' changed';
 const out=safe(compare(a,b));assert.equal(out.status,'COMPLETE');const acl=row(out,'relation').acl;
 assert.equal(acl.rightsDifferentCount,1);assert.equal(acl.sourceOnlyTupleCount,1);assert.equal(acl.targetOnlyTupleCount,1);
});
test('equal raw ACL with inconsistent semantic projection is explicit, not an equality claim',()=>{
 const a=facts(),b=facts();b[0][3][0][1]+=canary;const out=safe(compare(a,b));
 assert.equal(out.status,'COMPLETE');assert.equal(row(out,'relation').acl.inconsistentCount,1);assert.equal(row(out,'relation').acl.rawEqualCount,0);
});
test('null ACL is distinguished from an explicit empty ACL without inferring effective rights',()=>{
 const a=facts(),b=facts();a[0][2][4]=null;a[0][3]=null;b[0][2][4]=[];b[0][3]=[];
 const out=safe(compare(a,b));assert.equal(out.status,'COMPLETE');assert.equal(row(out,'relation').acl.nullStateDifferentCount,1);assert.equal(row(out,'relation').acl.rightsDifferentCount,0);
});
test('exact subtraction precedes pairing and ambiguous concatenated names are not guessed',()=>{
 const a=facts(),b=facts();a.push(structuredClone(a[7]),structuredClone(a[7]));b.push(structuredClone(b[7]),structuredClone(b[7]));
 a.at(-1)[2][0]='source2';a.at(-2)[2][0]='source1';b.at(-1)[2][0]='target2';b.at(-2)[2][0]='target1';
 const out=safe(compare(a,b)),v=row(out,'extension');assert.equal(out.status,'COMPLETE');assert.equal(v.unchangedCount,1);assert.equal(v.ambiguousSourceCount,2);assert.equal(v.ambiguousTargetCount,2);assert.equal(v.changedCount,0);
});
test('private capture bounds and missing capture emit only constant status, never a partial set',()=>{
 assert.deepEqual(catalogueFactsDiagnostic(undefined,capture(facts())),{schemaVersion:1,status:'NOT_CAPTURED'});
 assert.deepEqual(catalogueFactsDiagnostic({schemaVersion:1,status:'BOUND_EXCEEDED'},capture(facts())),{schemaVersion:1,status:'BOUND_EXCEEDED'});
 const oversized=capture(Array(CATALOGUE_FACT_BOUND+1).fill(facts()[0]));assert.equal(catalogueFactsDiagnostic(oversized,capture([])).status,'BOUND_EXCEEDED');
 const big=facts();big[5][2]='x'.repeat(CATALOGUE_FACT_BYTES+1);assert.equal(compare(big,facts()).status,'BOUND_EXCEEDED');
});
test('malformed private rows and ACL tuples never leak unknown keys, values or failures',()=>{
 for(const mutate of [a=>a.push([canary,canary,canary,null]),a=>a[0].push(canary),a=>a[0][2].push(canary),
  a=>a[3][2][canary]=canary,a=>delete a[3][2].cmd,a=>a[0][3][0][3]=canary,a=>a[0][3][0][4]=canary,
  a=>a[0][3][0][0]=canary,a=>a[5][2]={sql:canary},a=>a[0][1]='',a=>a[0][2][1]=1]){
  const a=facts();mutate(a);assert.deepEqual(safe(compare(a,facts())),{schemaVersion:1,status:'INVALID_SHAPE'});
 }
});
test('public projector revalidates complete kind order, positions, enums, counts and exact nested keys',()=>{
 const good=compare(facts(),facts());
 for(const mutate of [v=>v[canary]=canary,v=>v.kinds.pop(),v=>v.kinds.reverse(),v=>v.kinds[0].kind=canary,
  v=>v.kinds[0].fields[0].position=canary,v=>v.kinds[0].fields[0].field=canary,v=>v.kinds[0].fields[0][canary]=canary,
  v=>v.kinds[0].sourceCount++,v=>v.kinds[0].sourceCount=-1,v=>v.kinds[0].sourceCount=0.5,
  v=>v.kinds[0].fields[0].changedCount=1,v=>v.kinds[0].acl.rawEqualCount=2,v=>v.kinds[0].acl[canary]=canary,
  v=>v.kinds[0].acl.representationDifferentCount=1,v=>v.kinds[0].acl.representationDifferentCount=-1,
  v=>v.kinds[0].acl.representationDifferentCount=canary,v=>delete v.kinds[0].acl.representationDifferentCount,
  v=>v.kinds[0].acl.sourceOnlyTupleCount=1,v=>v.kinds[0].ambiguousSourceCount=1,v=>v.kinds[8].kind=canary]){
  const v=structuredClone(good);mutate(v);assert.deepEqual(safe(projectCatalogueFactsDiagnostic(v)),{schemaVersion:1,status:'INVALID_SHAPE'});
 }
 const forged=projectRestoreInvariant({reason:'CATALOGUE_PARITY',catalogue:{status:'COMPLETE',sections:['catalogue_sha256'],facts:{...good,sql:canary}}});
 assert.deepEqual(forged.catalogue.facts,{schemaVersion:1,status:'INVALID_SHAPE'});safe(forged);
});
test('instrumentation preserves the exact original SQL after removing its one projection',()=>{
 const original=readFileSync(new URL('../../sql/catalogue.sql',import.meta.url),'utf8'),sql=catalogueDiagnosticSql(original);
 const start=sql.indexOf(" '"+CATALOGUE_PRIVATE_KEY+"',"),end=sql.indexOf(" 'catalogue_sha256',",start);
 assert.ok(start>0&&end>start);assert.equal(sql.slice(0,start)+sql.slice(end),original);
 assert.equal(sql.split('WITH facts AS (').length,2);assert.ok(sql.startsWith('BEGIN READ ONLY;'));assert.ok(sql.endsWith('ROLLBACK;\n'));
 assert.match(sql,/FROM aclexplode\(ARRAY\(SELECT jsonb_array_elements_text\(a.acl\)\)::aclitem\[\]\) x/);
 assert.match(sql,/pg_get_userbyid\(x.grantee\)/);assert.match(sql,/pg_get_userbyid\(x.grantor\)/);
 assert.ok(sql.includes("'BOUND_EXCEEDED'"));assert.ok(!/\bLIMIT\b/.test(sql));
 for(const changed of [original+' ',original.replace('ORDER BY kind,name,value::text','ORDER BY name')])assert.throws(()=>catalogueDiagnosticSql(changed),/CATALOGUE_DIAGNOSTIC_SQL_PIN/);
});

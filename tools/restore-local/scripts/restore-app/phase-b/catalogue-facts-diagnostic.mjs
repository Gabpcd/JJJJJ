import { createHash } from 'node:crypto';

// Advisory only. No names, values, SQL, hashes or ACL identities cross this module's
// public projection. The original catalogue comparison remains the only gate.
export const CATALOGUE_FACT_BOUND = 100000;
export const CATALOGUE_FACT_BYTES = 16 * 1024 * 1024;
export const CATALOGUE_DIAGNOSTIC_BYTES = 16384;
export const CATALOGUE_PRIVATE_KEY = '_catalogue_facts_private';
export const CATALOGUE_SQL_SHA256 = '29098b4dc0caf44f2a4501517603ee8fa78b2b00ab84a0ca7a34031dadc63969';
const policyFields = ['schemaname','tablename','policyname','permissive','roles','cmd','qual','with_check'];
const definitions = {
 relation: ['relkind','relrowsecurity','relforcerowsecurity','owner','acl'],
 column: ['type','not_null','identity','generated','acl','default_expression'],
 function: ['definition','owner','acl'],
 policy: policyFields,
 trigger: ['definition','enabled'],
 constraint: ['definition'],
 index: ['definition'],
 extension: ['version','schema','owner'],
 default_acl: ['acl'],
};
export const CATALOGUE_KINDS = Object.freeze(Object.keys(definitions));
export const CATALOGUE_FIELDS = Object.freeze(Object.fromEntries(CATALOGUE_KINDS.map(kind => [kind,
 Object.freeze(definitions[kind].map((field, index) => Object.freeze({
  position: kind === 'policy' ? field : ['constraint','index','default_acl'].includes(kind) ? 'value' : index, field,
 })))])));
const privileges = ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','EXECUTE','USAGE','CREATE','CONNECT','TEMPORARY','SET','ALTER SYSTEM','MAINTAIN'];
const aclPosition = {relation:4,column:4,function:2,default_acl:'value'};
const statuses = ['NOT_CAPTURED','INVALID_SHAPE','BOUND_EXCEEDED'];
const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const keys = (v, expected) => plain(v) && Object.keys(v).length === expected.length && expected.every(k => Object.hasOwn(v,k));
const string = v => typeof v === 'string' && !v.includes('\0');
const nullableString = v => v === null || string(v);
const acl = v => v === null || (Array.isArray(v) && v.every(string));
const invalid = status => ({schemaVersion:1,status});
const equal = (a,b) => canonical(a) === canonical(b);
function canonical(value) {
 if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
 if (plain(value)) return '{' + Object.keys(value).sort().map(k => JSON.stringify(k)+':'+canonical(value[k])).join(',') + '}';
 return JSON.stringify(value);
}

// Add one read-only projection to the SAME facts CTE and transaction as the
// unchanged catalogue hash. No extra database session or recapture after dump.
// The full payload is returned, or a closed bound marker: never a truncated set.
export function catalogueDiagnosticSql(original) {
 if (typeof original !== 'string' || createHash('sha256').update(original).digest('hex') !== CATALOGUE_SQL_SHA256)
  throw Error('CATALOGUE_DIAGNOSTIC_SQL_PIN');
 const marker = "SELECT jsonb_build_object(\n 'catalogue_sha256',";
 if (original.split(marker).length !== 2) throw Error('CATALOGUE_DIAGNOSTIC_SQL_SHAPE');
 const projection = ` '${CATALOGUE_PRIVATE_KEY}', (SELECT CASE
  WHEN d.n>${CATALOGUE_FACT_BOUND} OR octet_length(d.rows::text)>${CATALOGUE_FACT_BYTES}
   THEN jsonb_build_object('schemaVersion',1,'status','BOUND_EXCEEDED')
  ELSE jsonb_build_object('schemaVersion',1,'status','COMPLETE','facts',d.rows) END
 FROM (SELECT count(*) AS n,coalesce(jsonb_agg(jsonb_build_array(f.kind,f.name,f.value,
  CASE WHEN f.kind IN ('relation','column','function','default_acl') AND a.acl IS NOT NULL AND a.acl<>'null'::jsonb
   THEN (SELECT coalesce(jsonb_agg(jsonb_build_array(
    CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE 'ROLE' END,
    CASE WHEN x.grantee=0 THEN NULL ELSE pg_get_userbyid(x.grantee) END,
    pg_get_userbyid(x.grantor),x.privilege_type,x.is_grantable)),'[]'::jsonb)
    FROM aclexplode(ARRAY(SELECT jsonb_array_elements_text(a.acl))::aclitem[]) x)
   ELSE NULL END)),'[]'::jsonb) AS rows
 FROM facts f CROSS JOIN LATERAL (SELECT CASE f.kind
  WHEN 'relation' THEN f.value->4 WHEN 'column' THEN f.value->4
  WHEN 'function' THEN f.value->2 WHEN 'default_acl' THEN f.value ELSE NULL END AS acl) a) d),\n`;
 return original.replace(marker, 'SELECT jsonb_build_object(\n'+projection+" 'catalogue_sha256',");
}

function validValue(kind,v) {
 if (kind === 'policy') return keys(v,policyFields) && policyFields.filter(k=>!['roles','qual','with_check'].includes(k)).every(k=>string(v[k]))
  && Array.isArray(v.roles) && v.roles.every(string) && nullableString(v.qual) && nullableString(v.with_check);
 if (kind === 'default_acl') return acl(v);
 if (['constraint','index'].includes(kind)) return string(v);
 if (!Array.isArray(v) || v.length !== definitions[kind].length) return false;
 if (kind === 'relation') return string(v[0]) && typeof v[1] === 'boolean' && typeof v[2] === 'boolean' && string(v[3]) && acl(v[4]);
 if (kind === 'column') return string(v[0]) && typeof v[1] === 'boolean' && string(v[2]) && string(v[3]) && acl(v[4]) && nullableString(v[5]);
 if (kind === 'function') return string(v[0]) && string(v[1]) && acl(v[2]);
 return v.every(string);
}
function rawAcl(row) { const p=aclPosition[row[0]]; return p === 'value' ? row[2] : row[2][p]; }
function validSemantic(row) {
 if (!Object.hasOwn(aclPosition,row[0]) || rawAcl(row) === null) return row[3] === null;
 return Array.isArray(row[3]) && row[3].length <= CATALOGUE_FACT_BOUND && row[3].every(t => Array.isArray(t) && t.length === 5
  && ((t[0] === 'PUBLIC' && t[1] === null) || (t[0] === 'ROLE' && string(t[1]) && t[1].length>0))
  && string(t[2]) && t[2].length>0 && privileges.includes(t[3]) && typeof t[4] === 'boolean');
}
function captureStatus(value) {
 if (value === undefined) return 'NOT_CAPTURED';
 if (keys(value,['schemaVersion','status']) && value.schemaVersion === 1 && value.status === 'BOUND_EXCEEDED') return 'BOUND_EXCEEDED';
 if (!keys(value,['schemaVersion','status','facts']) || value.schemaVersion !== 1 || value.status !== 'COMPLETE' || !Array.isArray(value.facts)) return 'INVALID_SHAPE';
 if (value.facts.length > CATALOGUE_FACT_BOUND || Buffer.byteLength(JSON.stringify(value.facts)) > CATALOGUE_FACT_BYTES) return 'BOUND_EXCEEDED';
 for (const row of value.facts) if (!Array.isArray(row) || row.length !== 4 || !CATALOGUE_KINDS.includes(row[0])
  || !string(row[1]) || row[1].length === 0 || !validValue(row[0],row[2]) || !validSemantic(row)) return 'INVALID_SHAPE';
 return 'COMPLETE';
}
const tupleSet = rows => new Set(rows.map(canonical));
function tupleDelta(a,b) {
 const sa=tupleSet(a),sb=tupleSet(b);
 return {sourceOnly:[...sa].filter(v=>!sb.has(v)).length,targetOnly:[...sb].filter(v=>!sa.has(v)).length};
}
function aclSummary() { return {rawEqualCount:0,orderOnlyCount:0,representationDifferentCount:0,rightsDifferentCount:0,nullStateDifferentCount:0,
 inconsistentCount:0,sourceOnlyTupleCount:0,targetOnlyTupleCount:0}; }
function compareAcl(a,b,summary) {
 const va=rawAcl(a),vb=rawAcl(b);
 if (va === null || vb === null) {
  summary[va === vb ? 'rawEqualCount' : 'nullStateDifferentCount']++;return;
 }
 const delta=tupleDelta(a[3],b[3]),semanticEqual=delta.sourceOnly === 0 && delta.targetOnly === 0;
 summary.sourceOnlyTupleCount+=delta.sourceOnly;summary.targetOnlyTupleCount+=delta.targetOnly;
 if (equal(va,vb)) summary[semanticEqual ? 'rawEqualCount' : 'inconsistentCount']++;
 else if (!semanticEqual) summary.rightsDifferentCount++;
 else summary[equal([...va].sort(),[...vb].sort()) ? 'orderOnlyCount' : 'representationDifferentCount']++;
}
function group(rows,kind) {
 const result=new Map();
 for (const row of rows) if (row[0] === kind) {const list=result.get(row[1])??[];list.push(row);result.set(row[1],list);}
 return result;
}
function fields(value,kind) { return kind === 'policy' ? policyFields.map(k=>value[k]) : ['constraint','index','default_acl'].includes(kind) ? [value] : value; }
function kindDelta(source,target,kind) {
 const a=group(source,kind),b=group(target,kind);
 const result={kind,sourceCount:0,targetCount:0,unchangedCount:0,changedCount:0,sourceOnlyCount:0,targetOnlyCount:0,
  ambiguousSourceCount:0,ambiguousTargetCount:0,fields:CATALOGUE_FIELDS[kind].map(f=>({...f,changedCount:0})),
  ...(Object.hasOwn(aclPosition,kind)?{acl:aclSummary()}: {})};
 for (const name of new Set([...a.keys(),...b.keys()])) {
  const left=a.get(name)??[],right=b.get(name)??[];result.sourceCount+=left.length;result.targetCount+=right.length;
  // Subtract exact facts before pairing. Concatenated catalogue names can collide;
  // ambiguous residual groups are counted explicitly instead of guessed or lost.
  const remaining=new Map();
  for (const row of right) {const key=canonical(row[2]),list=remaining.get(key)??[];list.push(row);remaining.set(key,list);}
  const aa=[];
  for (const row of left) {const same=remaining.get(canonical(row[2]));
   if (same?.length) {const other=same.pop();result.unchangedCount++;if(result.acl)compareAcl(row,other,result.acl);}
   else aa.push(row);
  }
  const bb=[...remaining.values()].flat();
  if (aa.length===1 && bb.length===1) {
   result.changedCount++;const av=fields(aa[0][2],kind),bv=fields(bb[0][2],kind);
   result.fields.forEach((f,i)=>{if(!equal(av[i],bv[i]))f.changedCount++;});
   if(result.acl)compareAcl(aa[0],bb[0],result.acl);
  } else if (aa.length && bb.length) {result.ambiguousSourceCount+=aa.length;result.ambiguousTargetCount+=bb.length;}
  else {result.sourceOnlyCount+=aa.length;result.targetOnlyCount+=bb.length;}
 }
 return result;
}
export function catalogueFactsDiagnostic(source,target) {
 try {
  const statuses=[captureStatus(source),captureStatus(target)];
  const status=statuses.find(v=>v!=='COMPLETE');if(status)return invalid(status);
  return projectCatalogueFactsDiagnostic({schemaVersion:1,status:'COMPLETE',kinds:CATALOGUE_KINDS.map(kind=>kindDelta(source.facts,target.facts,kind))});
 } catch { return invalid('INVALID_SHAPE'); }
}
const count = n => Number.isSafeInteger(n) && n>=0 && n<=CATALOGUE_FACT_BOUND;
const tupleCount = n => Number.isSafeInteger(n) && n>=0 && n<=CATALOGUE_FACT_BOUND*CATALOGUE_FACT_BOUND;
export function projectCatalogueFactsDiagnostic(value) {
 const bad=()=>invalid('INVALID_SHAPE');
 try {
  if (keys(value,['schemaVersion','status']) && value.schemaVersion===1 && statuses.includes(value.status)) return invalid(value.status);
  if (!keys(value,['schemaVersion','status','kinds']) || value.schemaVersion!==1 || value.status!=='COMPLETE'
   || !Array.isArray(value.kinds) || value.kinds.length!==CATALOGUE_KINDS.length) return bad();
  const kinds=[];
  for (const [index,kind] of CATALOGUE_KINDS.entries()) {
   const row=value.kinds[index],hasAcl=Object.hasOwn(aclPosition,kind);
   const counters=['sourceCount','targetCount','unchangedCount','changedCount','sourceOnlyCount','targetOnlyCount','ambiguousSourceCount','ambiguousTargetCount'];
   if (!keys(row,['kind',...counters,'fields',...(hasAcl?['acl']:[])]) || row.kind!==kind || !counters.every(k=>count(row[k]))
    || row.sourceCount!==row.unchangedCount+row.changedCount+row.sourceOnlyCount+row.ambiguousSourceCount
    || row.targetCount!==row.unchangedCount+row.changedCount+row.targetOnlyCount+row.ambiguousTargetCount
    || ((row.ambiguousSourceCount===0)!==(row.ambiguousTargetCount===0))
    || !Array.isArray(row.fields) || row.fields.length!==CATALOGUE_FIELDS[kind].length) return bad();
   const projectedFields=[];let changed=0;
   for (const [i,definition] of CATALOGUE_FIELDS[kind].entries()) {
    const field=row.fields[i];
    if (!keys(field,['position','field','changedCount']) || field.position!==definition.position || field.field!==definition.field
     || !count(field.changedCount) || field.changedCount>row.changedCount) return bad();
    changed+=field.changedCount;projectedFields.push({...definition,changedCount:field.changedCount});
   }
   if (changed<row.changedCount) return bad();
   let projectedAcl;
   if (hasAcl) {
    const acl=row.acl,aclCounts=['rawEqualCount','orderOnlyCount','representationDifferentCount','rightsDifferentCount','nullStateDifferentCount','inconsistentCount'];
    if (!keys(acl,[...aclCounts,'sourceOnlyTupleCount','targetOnlyTupleCount']) || !aclCounts.every(k=>count(acl[k]))
     || !tupleCount(acl.sourceOnlyTupleCount) || !tupleCount(acl.targetOnlyTupleCount)
     || aclCounts.reduce((n,k)=>n+acl[k],0)!==row.unchangedCount+row.changedCount
     || acl.orderOnlyCount+acl.representationDifferentCount+acl.rightsDifferentCount+acl.nullStateDifferentCount!==projectedFields.find(f=>f.field==='acl').changedCount
     || ((acl.rightsDifferentCount+acl.inconsistentCount===0)!==(acl.sourceOnlyTupleCount+acl.targetOnlyTupleCount===0))) return bad();
    projectedAcl=Object.fromEntries([...aclCounts,'sourceOnlyTupleCount','targetOnlyTupleCount'].map(k=>[k,acl[k]]));
   }
   kinds.push({kind,...Object.fromEntries(counters.map(k=>[k,row[k]])),fields:projectedFields,...(hasAcl?{acl:projectedAcl}:{})});
  }
  if (kinds.reduce((n,v)=>n+v.sourceCount,0)>CATALOGUE_FACT_BOUND || kinds.reduce((n,v)=>n+v.targetCount,0)>CATALOGUE_FACT_BOUND) return bad();
  const result={schemaVersion:1,status:'COMPLETE',kinds};
  return Buffer.byteLength(JSON.stringify(result))<=CATALOGUE_DIAGNOSTIC_BYTES ? result : invalid('BOUND_EXCEEDED');
 } catch { return bad(); }
}

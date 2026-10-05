import { B21_STATUSES, validateB21Capture, validateB21Probe } from './catalogue-semantics-diagnostic.mjs';
import { CATALOGUE_FACT_BOUND } from './catalogue-facts-diagnostic.mjs';

// Advisory only: the existing validator supplies the status and remains the
// sole anchor decision. Never publish an identity, definition or context value.
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const keys=(v,ks)=>plain(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
const canonical=v=>Array.isArray(v)?'['+v.map(canonical).join(',')+']':plain(v)?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}':JSON.stringify(v);
const equal=(a,b)=>canonical(a)===canonical(b);
const reasons=Object.freeze(['COMPLETE','NOT_CAPTURED','STATUS_ONLY','PROBE','ANCHOR_FIELDS','CURRENT_CAPTURE','FIXED_CAPTURE','CONTEXT','CURRENT_FIXED','UNKNOWN']);
const fields=Object.freeze(['currentExpressionCount','fixedExpressionCount','missingIdentityCount','changedExpressionCount',
 'localOidDifferentCount','metadataDifferentCount','dependenciesDifferentCount','bindingsDifferentCount',
 'bindingCompleteDifferentCount','bindingFactKeysDifferentCount','bindingColumnsDifferentCount']);
const count=v=>Number.isSafeInteger(v)&&v>=0&&v<=CATALOGUE_FACT_BOUND;
const marker=(status,reason)=>({schemaVersion:1,status,reason});
const invalid=()=>marker('INVALID_SHAPE','PROBE');

export function catalogueAnchorDiagnostic(probe,original) {
 try {
  const status=validateB21Probe(probe,original);
  if(status==='COMPLETE')return marker(status,'COMPLETE');
  if(probe===undefined)return marker(status,'NOT_CAPTURED');
  if(keys(probe,['schemaVersion','status']))return marker(status,'STATUS_ONLY');
  if(!keys(probe,['anchor','current','fixed']))return marker(status,'PROBE');
  if(status==='ANCHOR_MISMATCH')return marker(status,'ANCHOR_FIELDS');
  for(const [name,reason] of [['current','CURRENT_CAPTURE'],['fixed','FIXED_CAPTURE']])
   if(validateB21Capture(probe[name])!=='COMPLETE')return marker(status,reason);
  if(status==='CONTEXT_MISMATCH')return marker(status,'CONTEXT');
  if(status!=='INCOMPLETE')return marker(status,'UNKNOWN');
  const a=probe.current,b=probe.fixed,counters=Object.fromEntries(fields.map(k=>[k,0]));
  counters.currentExpressionCount=a.expressions.length;counters.fixedExpressionCount=b.expressions.length;
  const fixed=new Map(b.expressions.map(x=>[canonical([x.kind,x.identity]),x]));
  for(const row of a.expressions){
   const other=fixed.get(canonical([row.kind,row.identity]));
   if(!other){counters.missingIdentityCount++;counters.changedExpressionCount++;continue;}
   let changed=false;
   for(const [field,name] of [['localOid','localOidDifferentCount'],['metadata','metadataDifferentCount'],['dependencies','dependenciesDifferentCount'],['bindings','bindingsDifferentCount']])
    if(!equal(row[field],other[field])){counters[name]++;changed=true;}
   for(const [field,name] of [['complete','bindingCompleteDifferentCount'],['factKeys','bindingFactKeysDifferentCount'],['columns','bindingColumnsDifferentCount']])
    if(!equal(row.bindings[field],other.bindings[field]))counters[name]++;
   if(changed)counters.changedExpressionCount++;
  }
  return projectCatalogueAnchorDiagnostic({schemaVersion:1,status,reason:'CURRENT_FIXED',
   counters:{...counters,relationsDifferent:!equal(a.relations,b.relations)}});
 }catch{return invalid();}
}

export function projectCatalogueAnchorDiagnostic(value) {
 try {
  if(!plain(value)||value.schemaVersion!==1||!['COMPLETE',...B21_STATUSES].includes(value.status)||!reasons.includes(value.reason))return invalid();
  const {status,reason}=value;
  if(reason!=='CURRENT_FIXED'){
   if(!keys(value,['schemaVersion','status','reason'])||(status==='COMPLETE')!==(reason==='COMPLETE')
    ||(reason==='NOT_CAPTURED'&&status!=='NOT_CAPTURED')||(reason==='ANCHOR_FIELDS'&&status!=='ANCHOR_MISMATCH')
    ||(reason==='CONTEXT'&&status!=='CONTEXT_MISMATCH'))return invalid();
   return marker(status,reason);
  }
  const c=value.counters;
  if(!keys(value,['schemaVersion','status','reason','counters'])||status!=='INCOMPLETE'||!keys(c,[...fields,'relationsDifferent'])
   ||!fields.every(k=>count(c[k]))||typeof c.relationsDifferent!=='boolean')return invalid();
  const n=c.currentExpressionCount,m=c.missingIdentityCount,changed=c.changedExpressionCount;
  const direct=['localOidDifferentCount','metadataDifferentCount','dependenciesDifferentCount','bindingsDifferentCount'];
  const binding=['bindingCompleteDifferentCount','bindingFactKeysDifferentCount','bindingColumnsDifferentCount'];
  if(m>changed||changed>n||direct.some(k=>c[k]>n-m||c[k]>changed-m)
   ||changed>m+direct.reduce((sum,k)=>sum+c[k],0)||m<Math.max(0,n-c.fixedExpressionCount)
   ||binding.some(k=>c[k]>c.bindingsDifferentCount)||c.bindingsDifferentCount>binding.reduce((sum,k)=>sum+c[k],0)
   ||(!c.relationsDifferent&&n===c.fixedExpressionCount&&changed===0))return invalid();
  return {...marker(status,reason),counters:{...Object.fromEntries(fields.map(k=>[k,c[k]])),relationsDifferent:c.relationsDifferent}};
 }catch{return invalid();}
}

export function projectCatalogueAnchors(value) {
 try {
  if(!keys(value,['source','target']))return {source:invalid(),target:invalid()};
  return {source:projectCatalogueAnchorDiagnostic(value.source),target:projectCatalogueAnchorDiagnostic(value.target)};
 }catch{return {source:invalid(),target:invalid()};}
}

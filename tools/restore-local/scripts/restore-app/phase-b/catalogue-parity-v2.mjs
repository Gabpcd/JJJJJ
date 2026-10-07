import { captureStatus, CATALOGUE_FACT_BOUND } from './catalogue-facts-diagnostic.mjs';
import { validateB21Probe, compareB21Relation, compareB21Expression } from './catalogue-semantics-diagnostic.mjs';
import { columnFactTypeMatches } from './catalogue-enum-bindings.mjs';

// Versioned comparison, not a rewrite of catalogue.sql or of restored objects.
// Private facts stay in memory. Counters describe a decision; they never make it.
const reasons=['V1_EXACT','NORMALIZED','SHAPE','ANCHOR','CONTEXT','IDENTITY','FACT_DRIFT','ACL_DRIFT',
 'EXPRESSION_DRIFT','BINDING_UNCOVERED','METADATA_DRIFT','HASH_WITHOUT_FACT_DELTA'];
const canonical=v=>Array.isArray(v)?'['+v.map(canonical).join(',')+']':v!==null&&typeof v==='object'
 ?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}':JSON.stringify(v);
const equal=(a,b)=>canonical(a)===canonical(b);
const set=v=>[...new Set(v.map(canonical))].sort();
const setEqual=(a,b)=>equal(set(a),set(b));
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const text=v=>typeof v==='string'&&v.length>0&&!v.includes('\0');
const rawState=v=>v===null?'NULL':v.length===0?'EMPTY':'PRESENT';
function map(rows,key){const m=new Map();for(const row of rows){const k=key(row);if(m.has(k))return null;m.set(k,row);}return m;}
const factKey=r=>canonical(r.slice(0,2));

// Called by native adversarial witnesses too. Object identity is checked by the
// enclosing bijection; local OIDs are deliberately never compared across DBs.
export function catalogueV2RelationEqual(a,b) {
 if(compareB21Relation(a,b)!=='equalCount')return false;
 if(a.extensionMember!==b.extensionMember||!setEqual(a.initialPrivilegeKinds,b.initialPrivilegeKinds))return false;
 if((a.rawState==='NULL')!==(b.rawState==='NULL'))
  return !a.extensionMember&&!b.extensionMember&&a.initialPrivilegeKinds.length===0&&b.initialPrivilegeKinds.length===0
   &&a.rawState!=='EMPTY'&&b.rawState!=='EMPTY';
 return true;
}
export function catalogueV2ExpressionEqual(a,b) {
 const d=compareB21Expression(a,b);
 if(!d||d.metadataDifferent||d.dependencies!=='dependenciesEqualCount'
  ||!a.bindings.complete||!b.bindings.complete||!setEqual(a.bindings.factKeys,b.bindings.factKeys)
  ||!setEqual(a.bindings.columns,b.bindings.columns))return false;
 if(a.kind==='constraint'&&(a.metadata.contype!=='c'||b.metadata.contype!=='c'))return false;
 if(!text(a.prettyDefinition)||a.prettyDefinition!==b.prettyDefinition)return false;
 // WITH CHECK is a separate rule, not part of the USING normalization.
 if(a.kind==='policy')return equal(a.secondaryDefinition,b.secondaryDefinition);
 return text(a.secondaryDefinition)&&text(b.secondaryDefinition)&&text(a.secondaryPrettyDefinition)
  &&a.secondaryPrettyDefinition===b.secondaryPrettyDefinition;
}

export function projectCatalogueParityV2(v) {
 const keys=['schemaVersion','status','reason','v1Equal','v2Equal','aclNormalizedCount','expressionNormalizedCount'];
 if(!plain(v)||Object.keys(v).length!==keys.length||!keys.every(k=>Object.hasOwn(v,k))||v.schemaVersion!==2
  ||!['EQUAL','REFUSED'].includes(v.status)||!reasons.includes(v.reason)||typeof v.v1Equal!=='boolean'||typeof v.v2Equal!=='boolean'
  ||!['aclNormalizedCount','expressionNormalizedCount'].every(k=>Number.isSafeInteger(v[k])&&v[k]>=0&&v[k]<=CATALOGUE_FACT_BOUND)
  ||v.aclNormalizedCount+v.expressionNormalizedCount>CATALOGUE_FACT_BOUND
  ||(v.status==='EQUAL')!==v.v2Equal||(v.v2Equal?!['V1_EXACT','NORMALIZED'].includes(v.reason):['V1_EXACT','NORMALIZED'].includes(v.reason))
  ||(v.reason==='V1_EXACT'&&(!v.v1Equal||v.aclNormalizedCount+v.expressionNormalizedCount!==0))
  ||(v.reason==='NORMALIZED'&&(v.v1Equal||v.aclNormalizedCount+v.expressionNormalizedCount===0)))
  return {schemaVersion:2,status:'REFUSED',reason:'SHAPE',v1Equal:false,v2Equal:false,aclNormalizedCount:0,expressionNormalizedCount:0};
 return Object.fromEntries(keys.map(k=>[k,v[k]]));
}

export function catalogueParityV2(source,target,sourceFacts,targetFacts,sourceProbe,targetProbe) {
 let aclNormalizedCount=0,expressionNormalizedCount=0,v1Equal=false;
 const result=reason=>projectCatalogueParityV2({schemaVersion:2,status:['V1_EXACT','NORMALIZED'].includes(reason)?'EQUAL':'REFUSED',
  reason,v1Equal,v2Equal:['V1_EXACT','NORMALIZED'].includes(reason),aclNormalizedCount,expressionNormalizedCount});
 try {
  if(!plain(source)||!plain(target)||!['source','target'].every(k=>/^[a-f0-9]{64}$/.test((k==='source'?source:target).catalogue_sha256??'')))return result('SHAPE');
  v1Equal=JSON.stringify(source)===JSON.stringify(target);
  // Retain the exact former predicate on every field except the raw fact hash,
  // including unknown fields and top-level field order.
  const rest=v=>Object.fromEntries(Object.entries(v).filter(([k])=>k!=='catalogue_sha256'));
  if(!equal(Object.keys(source),Object.keys(target))||JSON.stringify(rest(source))!==JSON.stringify(rest(target)))return result('FACT_DRIFT');
  if(captureStatus(sourceFacts)!=='COMPLETE'||captureStatus(targetFacts)!=='COMPLETE')return result('SHAPE');
  if(validateB21Probe(sourceProbe,source)!=='COMPLETE'||validateB21Probe(targetProbe,target)!=='COMPLETE')return result('ANCHOR');
  if(!equal(sourceProbe.fixed.context,targetProbe.fixed.context)
   ||![sourceProbe,targetProbe].every(p=>equal(p.fixed.resolvedSchemas,['pg_catalog'])))return result('CONTEXT');
  const left=map(sourceFacts.facts,factKey),right=map(targetFacts.facts,factKey);
  if(!left||!right||left.size!==right.size)return result('IDENTITY');
  const rows=probe=>({relations:map(probe.current.relations,r=>r.identity.join('.')),
   current:map(probe.current.expressions,r=>canonical([r.kind,r.identity.join('.')])),
   fixed:map(probe.fixed.expressions,r=>canonical([r.kind,r.identity.join('.')]))});
  const a=rows(sourceProbe),b=rows(targetProbe);
  if([a,b].some(m=>!m.relations||!m.current||!m.fixed))return result('IDENTITY');
  for(const [m,facts] of [[a,sourceFacts],[b,targetFacts]])
   if(m.relations.size!==facts.facts.filter(r=>r[0]==='relation').length
    ||m.current.size!==facts.facts.filter(r=>['policy','constraint'].includes(r[0])).length)return result('IDENTITY');
  for(const [key,x] of left){
   const y=right.get(key);if(!y)return result('IDENTITY');
   if(v1Equal&&!equal(x,y))return result('FACT_DRIFT');
   const kind=x[0];
   if(kind==='relation'){
    const u=a.relations.get(x[1]),v=b.relations.get(y[1]);if(!u||!v)return result('IDENTITY');
    for(const [r,p] of [[x,u],[y,v]]){
     if(r[2][0]!==p.relkind||r[2][3]!==p.owner||rawState(r[2][4])!==p.rawState||!p.identitiesResolved
      ||(r[2][4]!==null&&p.supported&&!setEqual(r[3],p.expandedAcl)))return result('ANCHOR');
    }
    if(!equal(x[2].slice(0,4),y[2].slice(0,4)))return result('FACT_DRIFT');
    if(equal(x[2][4],y[2][4])){
     if(!equal(u.expandedAcl,v.expandedAcl)||u.extensionMember!==v.extensionMember||!equal(u.initialPrivilegeKinds,v.initialPrivilegeKinds))return result('ACL_DRIFT');
    }else{
     if(!catalogueV2RelationEqual(u,v))return result('ACL_DRIFT');aclNormalizedCount++;
    }
   }else if(kind==='function'&&!equal(x[2],y[2])){
    if(!equal(x[2].slice(0,2),y[2].slice(0,2)))return result('FACT_DRIFT');
    if(x[2][2]===null||y[2][2]===null||!setEqual(x[3],y[3]))return result('ACL_DRIFT');
    aclNormalizedCount++;
   }else if(['policy','constraint'].includes(kind)){
    const u=a.current.get(key),v=b.current.get(key),uf=a.fixed.get(key),vf=b.fixed.get(key);
    if(!u||!v||!uf||!vf)return result('IDENTITY');
    for(const [r,p] of [[x,u],[y,v]])if(p.definition!==(kind==='policy'?r[2].qual:r[2])
     ||(kind==='policy'&&!equal(p.secondaryDefinition,r[2].with_check)))return result('ANCHOR');
    if(!equal(uf.metadata,vf.metadata)||!setEqual(uf.dependencies,vf.dependencies))return result('METADATA_DRIFT');
    // Scalar enum evidence is checked even when raw catalogue bytes match.
    // A label/owner/ACL drift must never hide behind unchanged policy SQL.
    const enumColumns=p=>p.bindings.columns.filter(c=>c.length===4);
    if(!setEqual(enumColumns(uf),enumColumns(vf)))return result('EXPRESSION_DRIFT');
    for(const [facts,p] of [[left,uf],[right,vf]])for(const column of enumColumns(p)){
     const fact=facts.get(canonical(['column',column[0]]));
     if(!fact||!columnFactTypeMatches(column,fact[2][0]))return result('BINDING_UNCOVERED');
    }
    if(equal(x[2],y[2]))continue;
    if(kind==='policy'){
     const rest=v=>Object.fromEntries(Object.entries(v).filter(([k])=>k!=='qual'));
     if(!equal(rest(x[2]),rest(y[2])))return result('FACT_DRIFT');
    }
    if(!uf.bindings.complete||!vf.bindings.complete)return result('BINDING_UNCOVERED');
    if(!catalogueV2ExpressionEqual(uf,vf))return result('EXPRESSION_DRIFT');
    for(const ref of [...uf.bindings.factKeys,...vf.bindings.factKeys]){
     const k=canonical(ref);if(!left.has(k)||!right.has(k))return result('BINDING_UNCOVERED');
     // All referenced facts are checked in this same exhaustive loop, including
     // bodies/configuration/owners and complete ACL tuples of functions.
    }
    for(const [facts,row] of [[left,uf],[right,vf]])for(const column of row.bindings.columns){
     const fact=facts.get(canonical(['column',column[0]]));
     if(!fact||!columnFactTypeMatches(column,fact[2][0]))return result('BINDING_UNCOVERED');
    }
    expressionNormalizedCount++;
   }else if(!equal(x,y))return result('FACT_DRIFT');
  }
  return result(v1Equal?'V1_EXACT':aclNormalizedCount+expressionNormalizedCount>0?'NORMALIZED':'HASH_WITHOUT_FACT_DELTA');
 }catch{return result('SHAPE');}
}

// Advisory only, called after the original refusal. No identities, SQL, types,
// values or hashes cross this projection, and it cannot grant equivalence.
const bindingFields=['selected','incompleteCoverage','metadataDifference','expressionDifference','referenceFactMissing',
 'columnFactMissing','columnTypeMismatch','none','sourceComplete','targetComplete','sourceCovered','targetCovered',
 'sourceUncovered','targetUncovered','sourceTotal','targetTotal','factKeysEqual','coveredEqual','uncoveredEqual',
 'prettyEqual','secondaryEqual','secondaryPrettyEqual','sourceExplicit','targetExplicit','sourceAutoOnly','targetAutoOnly',
 'sourceOther','targetOther'];
const bindingFail=()=>({schemaVersion:1,status:'INVALID_SHAPE'});
export function projectCatalogueBindingDiagnostic(value){
 if(!plain(value)||!equal(Object.keys(value).sort(),['schemaVersion','status','kinds'].sort())||value.schemaVersion!==1
  ||value.status!=='COMPLETE'||!Array.isArray(value.kinds)||value.kinds.length!==2)return bindingFail();
 const kinds=[];
 for(const [index,kind] of ['policy','constraint'].entries()){
  const row=value.kinds[index];
  if(!plain(row)||row.kind!==kind||!equal(Object.keys(row).sort(),['kind',...bindingFields].sort())
   ||bindingFields.some(k=>!Number.isSafeInteger(row[k])||row[k]<0||row[k]>CATALOGUE_FACT_BOUND**2)
   ||row.selected>CATALOGUE_FACT_BOUND
   ||['incompleteCoverage','metadataDifference','expressionDifference','referenceFactMissing','columnFactMissing','columnTypeMismatch','none'].reduce((s,k)=>s+row[k],0)!==row.selected
   ||['sourceComplete','targetComplete','factKeysEqual','coveredEqual','uncoveredEqual','prettyEqual','secondaryEqual','secondaryPrettyEqual'].some(k=>row[k]>row.selected)
   ||['source','target'].some(s=>row[s+'Covered']+row[s+'Uncovered']!==row[s+'Total']||row[s+'Explicit']+row[s+'AutoOnly']+row[s+'Other']!==row[s+'Uncovered']
    ||row[s+'Total']>row.selected*CATALOGUE_FACT_BOUND||row[s+'Uncovered']>(row.selected-row[s+'Complete'])*CATALOGUE_FACT_BOUND))return bindingFail();
  kinds.push({kind,...Object.fromEntries(bindingFields.map(k=>[k,row[k]]))});
 }
 return {schemaVersion:1,status:'COMPLETE',kinds};
}
export function catalogueBindingDiagnostic(source,target,sourceFacts,targetFacts,sourceProbe,targetProbe){
 try{
  if(captureStatus(sourceFacts)!=='COMPLETE'||captureStatus(targetFacts)!=='COMPLETE'
   ||validateB21Probe(sourceProbe,source)!=='COMPLETE'||validateB21Probe(targetProbe,target)!=='COMPLETE')return bindingFail();
  const left=map(sourceFacts.facts,factKey),right=map(targetFacts.facts,factKey);
  if(!left||!right||left.size!==right.size||[...left.keys()].some(k=>!right.has(k)))return bindingFail();
  const kinds=[];
  for(const kind of ['policy','constraint']){
   const row={kind,...Object.fromEntries(bindingFields.map(k=>[k,0]))};
   const selected=sourceFacts.facts.filter(r=>r[0]===kind);
   const captures=[sourceProbe.current,sourceProbe.fixed,targetProbe.current,targetProbe.fixed].map(p=>map(p.expressions.filter(x=>x.kind===kind),x=>canonical([kind,x.identity.join('.')])));
   if(captures.some(m=>!m||m.size!==selected.length))return bindingFail();
   for(const x of selected){
    const key=factKey(x),y=right.get(key),[u,uf,v,vf]=captures.map(m=>m.get(key));
    if(!y||![u,uf,v,vf].every(Boolean))return bindingFail();
    for(const [fact,p] of [[x,u],[y,v]])if(p.definition!==(kind==='policy'?fact[2].qual:fact[2])
     ||(kind==='policy'&&!equal(p.secondaryDefinition,fact[2].with_check)))return bindingFail();
    if(equal(x[2],y[2]))continue;
    // This diagnostic only classifies expression drift. Other policy facts
    // remain outside its scope, just as they refuse the original comparator.
    if(kind==='policy'){
     const rest=p=>Object.fromEntries(Object.entries(p).filter(([k])=>k!=='qual'));
     if(!equal(rest(x[2]),rest(y[2])))return bindingFail();
    }
    row.selected++;
    for(const [side,p] of [['source',uf],['target',vf]]){
     row[side+'Complete']+=Number(p.bindings.complete);row[side+'Covered']+=p.bindings.columns.length;
     row[side+'Uncovered']+=p.bindings.uncoveredColumns.length;row[side+'Total']+=p.bindings.columnCount;
     for(const [identity] of p.bindings.uncoveredColumns){
      const explicit=p.dependencies.some(d=>d[1]==='table column'&&equal(d[2],identity));
      const auto=p.dependencies.some(d=>d[0]==='a'&&d[1]==='table'&&equal(d[2],identity.slice(0,2)));
      row[side+(explicit?'Explicit':auto?'AutoOnly':'Other')]++;
     }
    }
    for(const [field,a,b] of [['factKeysEqual',uf.bindings.factKeys,vf.bindings.factKeys],['coveredEqual',uf.bindings.columns,vf.bindings.columns],
     ['uncoveredEqual',uf.bindings.uncoveredColumns,vf.bindings.uncoveredColumns]])row[field]+=Number(setEqual(a,b));
    row.prettyEqual+=Number(equal(uf.prettyDefinition,vf.prettyDefinition));
    row.secondaryEqual+=Number(equal(uf.secondaryDefinition,vf.secondaryDefinition));
    row.secondaryPrettyEqual+=Number(equal(uf.secondaryPrettyDefinition,vf.secondaryPrettyDefinition));
    // Same order as the existing comparator; all changed expressions are
    // inspected, even if the comparator already stopped on the first one.
    let gate='none';
    if(!equal(uf.metadata,vf.metadata)||!setEqual(uf.dependencies,vf.dependencies))gate='metadataDifference';
    else if(!uf.bindings.complete||!vf.bindings.complete)gate='incompleteCoverage';
    else if(!catalogueV2ExpressionEqual(uf,vf))gate='expressionDifference';
    else if([...uf.bindings.factKeys,...vf.bindings.factKeys].some(ref=>!left.has(canonical(ref))||!right.has(canonical(ref))))gate='referenceFactMissing';
    else for(const [facts,p] of [[left,uf],[right,vf]]){
     for(const column of p.bindings.columns){const fact=facts.get(canonical(['column',column[0]]));
      if(!fact){gate='columnFactMissing';break;}if(!columnFactTypeMatches(column,fact[2][0])){gate='columnTypeMismatch';break;}}
     if(gate!=='none')break;
    }
    row[gate]++;
   }
   kinds.push(row);
  }
  return projectCatalogueBindingDiagnostic({schemaVersion:1,status:'COMPLETE',kinds});
 }catch{return bindingFail();}
}

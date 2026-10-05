import { catalogueFactsDiagnostic, CATALOGUE_FACT_BOUND, CATALOGUE_FACT_BYTES } from './catalogue-facts-diagnostic.mjs';
import { CONTEXT_KEYS } from './catalogue-semantics-probe.mjs';

// B21 public summaries remain advisory. V2 also reuses the strict private
// validators and row comparators below; no public counter decides parity.
export const B21_PUBLIC_BYTES=16384;
export const B21_STATUSES=Object.freeze(['NOT_CAPTURED','INVALID_SHAPE','BOUND_EXCEEDED','ANCHOR_MISMATCH','INCOMPLETE','CONTEXT_MISMATCH','CAPTURE_FAILED']);
export const B21_RELKINDS=Object.freeze(['r','p','v','m','f','S','i','I','c','t','UNKNOWN']);
export const B21_CONSTRAINT_KINDS=Object.freeze(['CHECK','FOREIGN_KEY','PRIMARY_KEY','UNIQUE','EXCLUSION','TRIGGER','NOT_NULL','UNKNOWN']);
export const B21_CONSTRAINT_FIELDS=Object.freeze(['contype','convalidated','condeferrable','condeferred','connoinherit','conislocal','coninhcount',
 'confupdtype','confdeltype','confmatchtype','conkey','confkey','confdelsetcols','operators','referencedRelation','parentConstraint']);
const fixedContext={search_path:'pg_catalog',TimeZone:'UTC',DateStyle:'ISO, YMD',IntervalStyle:'postgres',extra_float_digits:'3',
 quote_all_identifiers:'off',standard_conforming_strings:'on',bytea_output:'hex',lc_monetary:'C'};
const supported=['r','p','v','m','f','S'];
const privileges=['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','EXECUTE','USAGE','CREATE','CONNECT','TEMPORARY','SET','ALTER SYSTEM','MAINTAIN'];
const rawStates=['NULL','EMPTY','PRESENT'];
const aclOutcomes=['equalCount','differentCount','ownerDifferentCount','unsupportedCount','inconsistentCount'];
const directions=['nullToEmptyCount','nullToPresentCount','emptyToNullCount','presentToNullCount'];
const provenance=['sourceExtensionCount','targetExtensionCount','sourceInitialExtensionCount','targetInitialExtensionCount','sourceInitialInitdbCount','targetInitialInitdbCount'];
const expressionCounts=['selectedCount','strictFixedEqualCount','prettyOnlyConvergedCount','persistentDifferenceCount',
 'dependenciesEqualCount','dependenciesDifferentCount','dependenciesIncompleteCount','metadataDifferentCount','secondaryFixedDifferentCount'];
const statuses=['EQUAL','DIFFERENT','UNKNOWN'];
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const keys=(v,k)=>plain(v)&&Object.keys(v).length===k.length&&k.every(x=>Object.hasOwn(v,x));
const str=v=>typeof v==='string'&&!v.includes('\0');
const text=v=>str(v)&&v.length>0;
const nullable=v=>v===null||str(v);
const array=(v,test,max=CATALOGUE_FACT_BOUND)=>Array.isArray(v)&&v.length<=max&&v.every(test);
const count=v=>Number.isSafeInteger(v)&&v>=0&&v<=CATALOGUE_FACT_BOUND;
const fail=status=>({schemaVersion:1,status});
const canonical=v=>Array.isArray(v)?'['+v.map(canonical).join(',')+']':plain(v)?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}':JSON.stringify(v);
const equal=(a,b)=>canonical(a)===canonical(b);
const setEqual=(a,b)=>equal([...new Set(a.map(canonical))].sort(),[...new Set(b.map(canonical))].sort());
const role=v=>Array.isArray(v)&&v.length===2&&((v[0]==='PUBLIC'&&v[1]===null)||(v[0]==='ROLE'&&text(v[1])));
const tuple=v=>Array.isArray(v)&&v.length===5&&role(v.slice(0,2))&&text(v[2])&&privileges.includes(v[3])&&typeof v[4]==='boolean';
const identity=(v,n)=>Array.isArray(v)&&v.length===n&&v.every(text);
const address=v=>v===null||(Array.isArray(v)&&v.length===3&&nullable(v[0])&&[v[1],v[2]].every(x=>x===null||array(x,nullable)));
const completeAddress=v=>Array.isArray(v)&&text(v[0])&&array(v[1],text)&&v[1].length>0&&array(v[2],str);
const dependency=v=>Array.isArray(v)&&v.length===4&&text(v[0])&&address(v.slice(1));
const relationKeys=['identity','relkind','owner','identitiesResolved','rawState','supported','expandedAcl','initialPrivilegeKinds','extensionMember'];
export function validB21Relation(v) {
 return keys(v,relationKeys)&&identity(v.identity,2)&&text(v.relkind)&&v.relkind.length===1&&text(v.owner)
  &&typeof v.identitiesResolved==='boolean'&&rawStates.includes(v.rawState)&&v.supported===supported.includes(v.relkind)
  &&(v.supported?array(v.expandedAcl,tuple):v.expandedAcl===null)
  &&array(v.initialPrivilegeKinds,x=>['e','i'].includes(x),2)&&new Set(v.initialPrivilegeKinds).size===v.initialPrivilegeKinds.length
  &&typeof v.extensionMember==='boolean'&&(v.rawState!=='EMPTY'||!v.supported||v.expandedAcl.length===0);
}
const operators=['conpfeqop','conppeqop','conffeqop','conexclop'];
function metadata(kind,v) {
 if(kind==='policy')return keys(v,['cmd','permissive','roles','rolesResolved'])&&v.rolesResolved===true&&['*','r','a','w','d'].includes(v.cmd)&&typeof v.permissive==='boolean'&&array(v.roles,role);
 return keys(v,B21_CONSTRAINT_FIELDS)&&str(v.contype)&&v.contype.length===1
  &&['convalidated','condeferrable','condeferred','connoinherit','conislocal'].every(k=>typeof v[k]==='boolean')
  &&count(v.coninhcount)&&['confupdtype','confdeltype','confmatchtype'].every(k=>str(v[k])&&v[k].length<=1)
  &&['conkey','confkey','confdelsetcols'].every(k=>v[k]===null||array(v[k],nullable))
  &&keys(v.operators,operators)&&operators.every(k=>v.operators[k]===null||array(v.operators[k],address))
  &&address(v.referencedRelation)&&address(v.parentConstraint);
}
const expressionKeys=['kind','identity','localOid','metadata','definition','prettyDefinition','secondaryDefinition','secondaryPrettyDefinition','bindings','dependencies'];
export function validB21Expression(v) {
 return keys(v,expressionKeys)&&['policy','constraint'].includes(v.kind)&&identity(v.identity,3)
  &&Number.isSafeInteger(v.localOid)&&v.localOid>0&&v.localOid<=4294967295&&metadata(v.kind,v.metadata)
  &&['definition','prettyDefinition','secondaryDefinition','secondaryPrettyDefinition'].every(k=>nullable(v[k]))&&array(v.dependencies,dependency)
  &&keys(v.bindings,['complete','factKeys','columns'])&&typeof v.bindings.complete==='boolean'
  &&array(v.bindings.factKeys,k=>identity(k,2)&&['relation','column','function'].includes(k[0]))
  &&array(v.bindings.columns,c=>Array.isArray(c)&&c.length===3&&text(c[0])&&text(c[1])&&(c[2]===null||identity(c[2],2)));
}
export function validateB21Capture(v) {
 try {
  if(keys(v,['schemaVersion','status'])&&v.schemaVersion===1&&v.status==='BOUND_EXCEEDED')return 'BOUND_EXCEEDED';
  if(!keys(v,['schemaVersion','status','postgresVersionNum','context','resolvedSchemas','currentUser','sessionUser','expressions','relations'])
   ||v.schemaVersion!==1||v.status!=='COMPLETE'||v.postgresVersionNum!==170006||!keys(v.context,CONTEXT_KEYS)||!CONTEXT_KEYS.every(k=>str(v.context[k]))
   ||!array(v.resolvedSchemas,text)||v.currentUser!=='postgres'||v.sessionUser!=='postgres'
   ||!array(v.expressions,validB21Expression)||!array(v.relations,validB21Relation))return 'INVALID_SHAPE';
  if(v.expressions.length+v.relations.length>CATALOGUE_FACT_BOUND||Buffer.byteLength(JSON.stringify(v))>CATALOGUE_FACT_BYTES)return 'BOUND_EXCEEDED';
  if(new Set(v.relations.map(x=>canonical(x.identity))).size!==v.relations.length
   ||new Set(v.expressions.map(x=>canonical([x.kind,x.identity]))).size!==v.expressions.length)return 'INCOMPLETE';
  return 'COMPLETE';
 } catch{return 'INVALID_SHAPE';}
}
const anchorFields=['catalogue_sha256','database','roles','memberships'];
export function validateB21Probe(v,original) {
 try {
  if(v===undefined)return 'NOT_CAPTURED';
  if(keys(v,['schemaVersion','status'])&&v.schemaVersion===1&&B21_STATUSES.includes(v.status))return v.status;
  if(!keys(v,['anchor','current','fixed'])||!keys(v.anchor,anchorFields)||!plain(original)
   ||!/^[a-f0-9]{64}$/.test(v.anchor.catalogue_sha256??'')||!anchorFields.slice(1).every(k=>v.anchor[k]===null||Array.isArray(v.anchor[k])))return 'INVALID_SHAPE';
  if(!anchorFields.every(k=>Object.hasOwn(original,k)&&equal(v.anchor[k],original[k])))return 'ANCHOR_MISMATCH';
  for(const capture of [v.current,v.fixed]){const status=validateB21Capture(capture);if(status!=='COMPLETE')return status;}
  if(!Object.entries(fixedContext).every(([k,x])=>v.fixed.context[k]===x)
   ||!['server_encoding','client_encoding'].every(k=>v.current.context[k]===v.fixed.context[k]))return 'CONTEXT_MISMATCH';
  if(!equal(v.current.relations,v.fixed.relations)||v.current.expressions.length!==v.fixed.expressions.length)return 'INCOMPLETE';
  const fixed=new Map(v.fixed.expressions.map(x=>[canonical([x.kind,x.identity]),x]));
  for(const row of v.current.expressions){const other=fixed.get(canonical([row.kind,row.identity]));
   if(!other||row.localOid!==other.localOid||!equal(row.metadata,other.metadata)||!equal(row.dependencies,other.dependencies)||!equal(row.bindings,other.bindings))return 'INCOMPLETE';}
  return 'COMPLETE';
 }catch{return 'INVALID_SHAPE';}
}
// Shared by the actual diagnostic and native witness adapter. No role, grantor,
// grant option, PUBLIC identity or owner is erased by these classifications.
export function compareB21Relation(a,b) {
 if(!validB21Relation(a)||!validB21Relation(b))return 'inconsistentCount';
 if(!a.identitiesResolved||!b.identitiesResolved)return 'inconsistentCount';
 if(!a.supported||!b.supported)return 'unsupportedCount';
 if(a.relkind!==b.relkind)return 'inconsistentCount';
 if(a.owner!==b.owner)return 'ownerDifferentCount';
 return setEqual(a.expandedAcl,b.expandedAcl)?'equalCount':'differentCount';
}
export function compareB21Expression(a,b) {
 if(!validB21Expression(a)||!validB21Expression(b)||a.kind!==b.kind)return null;
 const complete=x=>x.dependencies.every(d=>completeAddress(d.slice(1)))
  &&(x.kind!=='constraint'||(['conkey','confkey','confdelsetcols'].every(k=>x.metadata[k]===null||x.metadata[k].every(text))
   &&operators.every(k=>x.metadata.operators[k]===null||x.metadata.operators[k].every(completeAddress))
   &&['referencedRelation','parentConstraint'].every(k=>x.metadata[k]===null||completeAddress(x.metadata[k]))));
 return {definition:equal(a.definition,b.definition)?'strictFixedEqualCount':equal(a.prettyDefinition,b.prettyDefinition)?'prettyOnlyConvergedCount':'persistentDifferenceCount',
  dependencies:!complete(a)||!complete(b)?'dependenciesIncompleteCount':setEqual(a.dependencies,b.dependencies)?'dependenciesEqualCount':'dependenciesDifferentCount',
  metadataDifferent:!equal(a.metadata,b.metadata),secondaryDifferent:!equal(a.secondaryDefinition,b.secondaryDefinition),
  fields:a.kind==='constraint'?B21_CONSTRAINT_FIELDS.filter(k=>!equal(a.metadata[k],b.metadata[k])):[]};
}
const mapRows=(rows,identityOf)=>{const m=new Map();for(const row of rows){const key=identityOf(row);if(m.has(key))return null;m.set(key,row);}return m;};
const rawState=v=>v===null?'NULL':v.length===0?'EMPTY':'PRESENT';
function newSummary(){return {schemaVersion:1,status:'COMPLETE',acl:{selectedCount:0,...Object.fromEntries([...directions,...aclOutcomes,...provenance].map(k=>[k,0])),
 relkinds:B21_RELKINDS.map(relkind=>({relkind,count:0}))},expressions:['policy','constraint'].map(kind=>({kind,...Object.fromEntries(expressionCounts.map(k=>[k,0]))})),
 constraints:{kinds:B21_CONSTRAINT_KINDS.map(kind=>({kind,count:0})),fields:B21_CONSTRAINT_FIELDS.map(field=>({field,changedCount:0}))},
 context:CONTEXT_KEYS.map(key=>({key,current:'UNKNOWN',fixed:'UNKNOWN'}))};}
const constraintKind=x=>({c:'CHECK',f:'FOREIGN_KEY',p:'PRIMARY_KEY',u:'UNIQUE',x:'EXCLUSION',t:'TRIGGER',n:'NOT_NULL'})[x]??'UNKNOWN';

export function catalogueSemanticsDiagnostic(source,target,sourceFacts,targetFacts,sourceProbe,targetProbe) {
 try {
  for(const [probe,original] of [[sourceProbe,source],[targetProbe,target]]){const status=validateB21Probe(probe,original);if(status!=='COMPLETE')return fail(status);}
  const b20=catalogueFactsDiagnostic(sourceFacts,targetFacts);if(b20.status!=='COMPLETE')return fail(b20.status);
  const family=k=>b20.kinds.find(x=>x.kind===k);
  // One closed B21 pass explains the exact unresolved B20 scope, not a guessed subset.
  if(family('relation').acl.nullStateDifferentCount!==16||family('policy').changedCount!==1||family('constraint').changedCount!==3
   ||['relation','policy','constraint'].some(k=>['sourceOnlyCount','targetOnlyCount','ambiguousSourceCount','ambiguousTargetCount'].some(f=>family(k)[f]!==0)))return fail('INCOMPLETE');
  const result=newSummary();
  for(const row of result.context)for(const view of ['current','fixed'])row[view]=sourceProbe[view].context[row.key]===targetProbe[view].context[row.key]?'EQUAL':'DIFFERENT';
  for(const kind of ['relation','policy','constraint']){
   const left=mapRows(sourceFacts.facts.filter(r=>r[0]===kind),r=>r[1]);
   const right=mapRows(targetFacts.facts.filter(r=>r[0]===kind),r=>r[1]);
   if(!left||!right)return fail('INCOMPLETE');
   const projected=probe=>kind==='relation'?probe.current.relations:probe.current.expressions.filter(r=>r.kind===kind);
   const la=mapRows(projected(sourceProbe),r=>r.identity.join('.')),lb=mapRows(projected(targetProbe),r=>r.identity.join('.'));
   if(!la||!lb||la.size!==left.size||lb.size!==right.size)return fail('INCOMPLETE');
   const fa=mapRows(sourceProbe.fixed.expressions.filter(r=>r.kind===kind),r=>r.identity.join('.'));
   const fb=mapRows(targetProbe.fixed.expressions.filter(r=>r.kind===kind),r=>r.identity.join('.'));
   for(const [name,a] of left){const b=right.get(name),pa=la.get(name),pb=lb.get(name);if(!b||!pa||!pb)return fail('INCOMPLETE');
    if(kind==='relation'){
     if(![ [a,pa],[b,pb] ].every(([raw,probe])=>raw[2][0]===probe.relkind&&raw[2][3]===probe.owner&&rawState(raw[2][4])===probe.rawState))return fail('INCOMPLETE');
     if((a[2][4]===null)===(b[2][4]===null))continue;
     const acl=result.acl;acl.selectedCount++;acl[compareB21Relation(pa,pb)]++;
     const direction=pa.rawState==='NULL'?(pb.rawState==='EMPTY'?'nullToEmptyCount':'nullToPresentCount'):(pa.rawState==='EMPTY'?'emptyToNullCount':'presentToNullCount');acl[direction]++;
     acl.relkinds.find(r=>r.relkind===(B21_RELKINDS.includes(pa.relkind)?pa.relkind:'UNKNOWN')).count++;
     for(const [prefix,row] of [['source',pa],['target',pb]]){
      if(row.extensionMember)acl[prefix+'ExtensionCount']++;
      if(row.initialPrivilegeKinds.includes('e'))acl[prefix+'InitialExtensionCount']++;
      if(row.initialPrivilegeKinds.includes('i'))acl[prefix+'InitialInitdbCount']++;
     }
    }else{
     const definition=raw=>kind==='policy'?raw[2].qual:raw[2];
     if(!equal(pa.definition,definition(a))||!equal(pb.definition,definition(b)))return fail('INCOMPLETE');
     if(equal(a[2],b[2]))continue;
     const x=fa.get(name),y=fb.get(name),comparison=compareB21Expression(x,y);if(!comparison)return fail('INCOMPLETE');
     const row=result.expressions.find(r=>r.kind===kind);row.selectedCount++;row[comparison.definition]++;row[comparison.dependencies]++;
     if(comparison.metadataDifferent)row.metadataDifferentCount++;if(comparison.secondaryDifferent)row.secondaryFixedDifferentCount++;
     if(kind==='constraint'){
      result.constraints.kinds.find(r=>r.kind===constraintKind(x.metadata.contype)).count++;
      for(const field of comparison.fields)result.constraints.fields.find(r=>r.field===field).changedCount++;
     }
    }
   }
  }
  if(result.acl.selectedCount!==16||result.expressions[0].selectedCount!==1||result.expressions[1].selectedCount!==3)return fail('INCOMPLETE');
  return projectCatalogueSemanticsDiagnostic(result);
 }catch{return fail('INVALID_SHAPE');}
}

export function projectCatalogueSemanticsDiagnostic(value) {
 try {
  if(keys(value,['schemaVersion','status'])&&value.schemaVersion===1&&B21_STATUSES.includes(value.status))return fail(value.status);
  if(!keys(value,['schemaVersion','status','acl','expressions','constraints','context'])||value.schemaVersion!==1||value.status!=='COMPLETE')return fail('INVALID_SHAPE');
  const out=newSummary(),a=value.acl;
  const aclCounts=['selectedCount',...directions,...aclOutcomes,...provenance];
  if(!keys(a,[...aclCounts,'relkinds'])||!aclCounts.every(k=>count(a[k]))||a.selectedCount!==16
   ||directions.reduce((n,k)=>n+a[k],0)!==a.selectedCount||aclOutcomes.reduce((n,k)=>n+a[k],0)!==a.selectedCount
   ||provenance.some(k=>a[k]>a.selectedCount)||!Array.isArray(a.relkinds)||a.relkinds.length!==B21_RELKINDS.length)return fail('INVALID_SHAPE');
  for(const k of aclCounts)out.acl[k]=a[k];
  for(const [i,relkind] of B21_RELKINDS.entries()){
   const row=a.relkinds[i];if(!keys(row,['relkind','count'])||row.relkind!==relkind||!count(row.count))return fail('INVALID_SHAPE');out.acl.relkinds[i].count=row.count;
  }
  if(out.acl.relkinds.reduce((n,r)=>n+r.count,0)!==a.selectedCount||!Array.isArray(value.expressions)||value.expressions.length!==2)return fail('INVALID_SHAPE');
  for(const [i,kind] of ['policy','constraint'].entries()){
   const row=value.expressions[i];if(!keys(row,['kind',...expressionCounts])||row.kind!==kind||!expressionCounts.every(k=>count(row[k]))||row.selectedCount!==(i===0?1:3)
    ||row.strictFixedEqualCount+row.prettyOnlyConvergedCount+row.persistentDifferenceCount!==row.selectedCount
    ||row.dependenciesEqualCount+row.dependenciesDifferentCount+row.dependenciesIncompleteCount!==row.selectedCount
    ||row.metadataDifferentCount>row.selectedCount||row.secondaryFixedDifferentCount>row.selectedCount)return fail('INVALID_SHAPE');
   for(const k of expressionCounts)out.expressions[i][k]=row[k];
  }
  if(!keys(value.constraints,['kinds','fields'])||!Array.isArray(value.constraints.kinds)||value.constraints.kinds.length!==B21_CONSTRAINT_KINDS.length
   ||!Array.isArray(value.constraints.fields)||value.constraints.fields.length!==B21_CONSTRAINT_FIELDS.length)return fail('INVALID_SHAPE');
  for(const [i,kind] of B21_CONSTRAINT_KINDS.entries()){
   const row=value.constraints.kinds[i];if(!keys(row,['kind','count'])||row.kind!==kind||!count(row.count))return fail('INVALID_SHAPE');out.constraints.kinds[i].count=row.count;
  }
  if(out.constraints.kinds.reduce((n,r)=>n+r.count,0)!==3)return fail('INVALID_SHAPE');
  for(const [i,field] of B21_CONSTRAINT_FIELDS.entries()){
   const row=value.constraints.fields[i];if(!keys(row,['field','changedCount'])||row.field!==field||!count(row.changedCount)||row.changedCount>3)return fail('INVALID_SHAPE');out.constraints.fields[i].changedCount=row.changedCount;
  }
  const changes=out.constraints.fields.reduce((n,r)=>n+r.changedCount,0);
  if(changes<out.expressions[1].metadataDifferentCount||out.constraints.fields.some(r=>r.changedCount>out.expressions[1].metadataDifferentCount))return fail('INVALID_SHAPE');
  if(!Array.isArray(value.context)||value.context.length!==CONTEXT_KEYS.length)return fail('INVALID_SHAPE');
  for(const [i,key] of CONTEXT_KEYS.entries()){
   const row=value.context[i];if(!keys(row,['key','current','fixed'])||row.key!==key||!statuses.includes(row.current)||!statuses.includes(row.fixed))return fail('INVALID_SHAPE');
   out.context[i]={key,current:row.current,fixed:row.fixed};
  }
  return Buffer.byteLength(JSON.stringify(out))<=B21_PUBLIC_BYTES?out:fail('BOUND_EXCEEDED');
 }catch{return fail('INVALID_SHAPE');}
}

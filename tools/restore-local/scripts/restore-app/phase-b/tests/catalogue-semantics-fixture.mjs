import { CONTEXT_KEYS } from '../catalogue-semantics-probe.mjs';
export const PRIVATE_CANARY='PRIVATE_B21_DEFINITION_ROLE_CONTEXT';
export const defaultTuples=()=>['INSERT','SELECT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'].map(p=>['ROLE','owner','owner',p,false]);
export function relation(name='table') {return {identity:['public',name],relkind:'r',owner:'owner',identitiesResolved:true,rawState:'NULL',supported:true,
 expandedAcl:defaultTuples(),initialPrivilegeKinds:[],extensionMember:false};}
export function expression(kind='constraint',name='constraint') {
 const metadata=kind==='policy'?{cmd:'*',permissive:true,rolesResolved:true,roles:[['PUBLIC',null]]}:
 {contype:'c',convalidated:true,condeferrable:false,condeferred:false,connoinherit:false,conislocal:true,coninhcount:0,
 confupdtype:'',confdeltype:'',confmatchtype:'',conkey:['id'],confkey:null,confdelsetcols:null,
 operators:{conpfeqop:null,conppeqop:null,conffeqop:null,conexclop:null},referencedRelation:null,parentConstraint:null};
 return {kind,identity:['public','subject',name],localOid:123,metadata,definition:PRIVATE_CANARY,prettyDefinition:PRIVATE_CANARY,
 secondaryDefinition:null,secondaryPrettyDefinition:null,bindings:{schemaVersion:2,columnCount:1,uncoveredColumns:[],complete:true,factKeys:[['column','public.subject.id']],columns:[['public.subject.id','integer',null]]},dependencies:[['a','table column',['public','subject','id'],[]]]};
}
export function capture(){return {schemaVersion:1,status:'COMPLETE',postgresVersionNum:170006,context:Object.fromEntries(CONTEXT_KEYS.map(k=>[k,({search_path:'pg_catalog',TimeZone:'UTC',DateStyle:'ISO, YMD',
 IntervalStyle:'postgres',extra_float_digits:'3',quote_all_identifiers:'off',standard_conforming_strings:'on',bytea_output:'hex',lc_monetary:'C',server_encoding:'UTF8',client_encoding:'UTF8'})[k]])),
 resolvedSchemas:['pg_catalog'],currentUser:'postgres',sessionUser:'postgres',relations:[],expressions:[]};}
export function b24ColumnFixture(){
 return ['TYPE_CONTEXT','MIXED_CONTEXT','WHOLE_ROW_CONTEXT','FIXED_STABLE','TYPE_CHANGE','TYPEMOD_CHANGE','COLLATION_CHANGE','PREDICATE_CHANGE','FUNCTION_CONTEXT'].map(name=>{
  const left=capture(),right=capture(),l=expression(name==='WHOLE_ROW_CONTEXT'?'policy':'constraint');
  l.bindings.complete=false;
  if(name!=='FUNCTION_CONTEXT'){
   l.bindings.uncoveredColumns=[[['public','subject','typed'],['public','synthetic_domain'],-1,null]];
   if(['MIXED_CONTEXT','WHOLE_ROW_CONTEXT'].includes(name)){l.bindings.columnCount=2;l.bindings.factKeys.push(['column','public.subject.typed']);}
   else{l.bindings.columns=[];l.bindings.factKeys=[['column','public.subject.typed']];}
   if(name==='WHOLE_ROW_CONTEXT')l.bindings.factKeys=[['relation','public.subject']];
  }
  const r=structuredClone(l);left.expressions=[l];right.expressions=[r];
  if(name.endsWith('_CONTEXT'))left.context.search_path='b21_expr,pg_catalog';
  if(name==='TYPE_CHANGE')r.bindings.uncoveredColumns[0][1][1]='other_domain';
  if(name==='TYPEMOD_CHANGE'){l.bindings.uncoveredColumns[0][2]=12;r.bindings.uncoveredColumns[0][2]=13;}
  if(name==='COLLATION_CHANGE'){l.bindings.uncoveredColumns[0][3]=['public','first'];r.bindings.uncoveredColumns[0][3]=['public','second'];}
  if(name==='PREDICATE_CHANGE'){r.definition+=' changed';r.prettyDefinition+=' changed';r.localOid++;}
  if(name==='FUNCTION_CONTEXT'){
   l.bindings.factKeys.push(['function','b21_expr.fn(synthetic_domain)']);
   r.bindings.factKeys.push(['function','b21_expr.fn(b21_expr.synthetic_domain)']);
  }
  return {name,left,right};
 });
}
const policyValue=e=>({schemaname:e.identity[0],tablename:e.identity[1],policyname:e.identity[2],permissive:'PERMISSIVE',roles:['public'],cmd:'ALL',qual:e.definition,with_check:e.secondaryDefinition});
export function b21Fixture() {
 const source={catalogue_sha256:'a'.repeat(64),database:[],roles:[],memberships:[]},target={...structuredClone(source),catalogue_sha256:'b'.repeat(64)};
 const sourceFacts={schemaVersion:1,status:'COMPLETE',facts:[]},targetFacts=structuredClone(sourceFacts);
 const a=capture(),b=capture();
 for(let i=0;i<16;i++){
  const x=relation('relation_'+i),y={...structuredClone(x),rawState:'PRESENT'};a.relations.push(x);b.relations.push(y);
  sourceFacts.facts.push(['relation',x.identity.join('.'),['r',false,false,'owner',null],null]);
  targetFacts.facts.push(['relation',y.identity.join('.'),['r',false,false,'owner',['owner=arwdDxtm/owner']],defaultTuples()]);
 }
 for(const [kind,n] of [['policy',1],['constraint',3]])for(let i=0;i<n;i++){
  const x=expression(kind,kind+i),y={...structuredClone(x),definition:PRIVATE_CANARY+'_target',localOid:456};a.expressions.push(x);b.expressions.push(y);
  sourceFacts.facts.push([kind,x.identity.join('.'),kind==='policy'?policyValue(x):x.definition,null]);
  targetFacts.facts.push([kind,y.identity.join('.'),kind==='policy'?policyValue(y):y.definition,null]);
 }
 const sourceProbe={anchor:structuredClone(source),current:a,fixed:structuredClone(a)};
 const targetProbe={anchor:structuredClone(target),current:b,fixed:structuredClone(b)};
 for(const row of targetProbe.fixed.expressions)row.definition=PRIVATE_CANARY;
 return {source,target,sourceFacts,targetFacts,sourceProbe,targetProbe};
}
export const diagnosticArgs=v=>[v.source,v.target,v.sourceFacts,v.targetFacts,v.sourceProbe,v.targetProbe];

export function v2Fixture(){
 const source={catalogue_sha256:'a'.repeat(64),database:[],roles:[],memberships:[]},target={...structuredClone(source),catalogue_sha256:'b'.repeat(64)};
 const sourceFacts={schemaVersion:1,status:'COMPLETE',facts:[]},targetFacts=structuredClone(sourceFacts),a=capture(),b=capture();
 const r=relation('subject');r.rawState='PRESENT';const s={...structuredClone(r),rawState:'NULL'};
 a.relations.push(r);b.relations.push(s);
 sourceFacts.facts.push(['relation','public.subject',['r',false,false,'owner',['owner=arwdDxtm/owner']],defaultTuples()]);
 targetFacts.facts.push(['relation','public.subject',['r',false,false,'owner',null],null]);
 for(const facts of [sourceFacts,targetFacts]){
  for(const name of ['a','b','c'])facts.facts.push(['column','public.subject.'+name,['boolean',false,'','',null,null],null]);
  facts.facts.push(['function','public.helper()',[PRIVATE_CANARY,'owner',['owner=X/owner','reader=X/owner']],
   [['ROLE','owner','owner','EXECUTE',false],['ROLE','reader','owner','EXECUTE',false]]]);
 }
 targetFacts.facts.at(-1)[2][2].reverse();targetFacts.facts.at(-1)[3].reverse();
 for(const kind of ['policy','constraint']){
  const x=expression(kind,kind),y=structuredClone(x);
  x.metadata=kind==='constraint'?{...x.metadata,conkey:['a','b','c']}:x.metadata;y.metadata=structuredClone(x.metadata);
  x.bindings=y.bindings={schemaVersion:2,columnCount:1,uncoveredColumns:[],complete:true,factKeys:[['relation','public.subject'],['column','public.subject.a'],['function','public.helper()']],columns:[['public.subject.a','boolean',null]]};
  x.dependencies=y.dependencies=[['a','table',['public','subject'],[]],['n','table column',['public','subject','a'],[]],['n','function',['public','helper'],[]]];
  x.definition=kind==='policy'?'(a AND (b AND c))':'CHECK ((a AND (b AND c)))';
  y.definition=kind==='policy'?'(a AND b AND c)':'CHECK ((a AND b AND c))';
  x.prettyDefinition=y.prettyDefinition=kind==='policy'?'a AND b AND c':'CHECK (a AND b AND c)';
  x.secondaryDefinition=kind==='policy'?'a':'(a AND (b AND c))';y.secondaryDefinition=kind==='policy'?'a':'(a AND b AND c)';
  x.secondaryPrettyDefinition=y.secondaryPrettyDefinition=kind==='policy'?'a':'a AND b AND c';y.localOid++;
  a.expressions.push(structuredClone(x));b.expressions.push(structuredClone(y));
  sourceFacts.facts.push([kind,x.identity.join('.'),kind==='policy'?policyValue(x):x.definition,null]);
  targetFacts.facts.push([kind,y.identity.join('.'),kind==='policy'?policyValue(y):y.definition,null]);
 }
 return {source,target,sourceFacts,targetFacts,sourceProbe:{anchor:structuredClone(source),current:a,fixed:structuredClone(a)},
  targetProbe:{anchor:structuredClone(target),current:b,fixed:structuredClone(b)}};
}

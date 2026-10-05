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
 secondaryDefinition:null,dependencies:[['a','table column',['public','subject','id'],[]]]};
}
export function capture(){return {schemaVersion:1,status:'COMPLETE',context:Object.fromEntries(CONTEXT_KEYS.map(k=>[k,({search_path:'pg_catalog',TimeZone:'UTC',DateStyle:'ISO, YMD',
 IntervalStyle:'postgres',extra_float_digits:'3',quote_all_identifiers:'off',standard_conforming_strings:'on',bytea_output:'hex',lc_monetary:'C',server_encoding:'UTF8',client_encoding:'UTF8'})[k]])),
 resolvedSchemas:['pg_catalog'],currentUser:'postgres',sessionUser:'postgres',relations:[],expressions:[]};}
const policyValue=e=>({schemaname:e.identity[0],tablename:e.identity[1],policyname:e.identity[2],permissive:'PERMISSIVE',roles:['public'],cmd:'ALL',qual:e.definition,with_check:e.secondaryDefinition});
export function b21Fixture() {
 const source={catalogue_sha256:'a'.repeat(64),database:[],roles:[],memberships:[]},target={...source,catalogue_sha256:'b'.repeat(64)};
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

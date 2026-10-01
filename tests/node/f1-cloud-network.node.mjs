import test from 'node:test';
import assert from 'node:assert/strict';
import { uiContractF1, installNetworkF1, UI_ORIGIN, networkFailureF1 } from '../../scripts/ci/f1-cloud-network.mjs';
import { manifestF1, verifyUiEffectsF1 } from '../../scripts/ci/f1-cloud-adapter.mjs';
import { ORIGIN, STAGING, sha256 } from '../../scripts/ci/f1-cloud-core.mjs';
import { preparerHtmlPreview } from '../../scripts/ci/f1-cloud-runtime.mjs';
const m=manifestF1({sha:'a'.repeat(40),run:'f1-ci-1234-1',ref:STAGING});
const documents=['original','replacement'].map((slot,i)=>({slot,id:`f130000${i+4}-${i+4}000-4000-8000-00000000000${i+4}`,number:`F1-${i}`,
  pdf:{key:`invoices/${m.members[0].id}/F1-${i}/11111111-1111-4111-8111-111111111111.pdf`}}));
const conversation='c1000000-1111-4111-8111-111111111111';
const call=(rpc,body,method='POST')=>({url:`${ORIGIN}/rest/v1/rpc/${rpc}`,method,body});

test('exact actors/mission conversation and read markers; unknown IDs cannot be laundered into a subsequent request',()=>{
  const c=uiContractF1(m.members[0],m,documents);
  assert.equal(c.authorize(call('fn_marquer_messages_lus',{p_conversation_id:conversation})),false);
  assert.equal(c.authorize(call('fn_obtenir_conversation',{p_autre_id:m.admin.id,p_mission_id:m.missionId})),false);
  assert(c.authorize(call('fn_obtenir_conversation',{p_autre_id:m.members[1].id,p_mission_id:m.missionId})));
  c.response({...call('fn_obtenir_conversation',{}),data:conversation});
  assert(c.authorize(call('fn_marquer_messages_lus',{p_conversation_id:conversation})));
  assert.throws(()=>c.response({...call('fn_obtenir_conversation',{}),data:m.admin.id}),/CONVERSATION_RESPONSE/);
  assert.equal(c.authorize(call('fn_obtenir_conversation',{p_autre_id:m.members[1].id,p_mission_id:null})),false);
});

test('all manual financial/message/invitation/pointage writes are refused, including extra body keys',()=>{
  const c=uiContractF1(m.members[0],m,documents);
  for(const rpc of ['fn_envoyer_message','fn_confirmer_presence_mission','fn_terminer_mission','fn_confirmer_action_planning_v1',
    'fn_creer_notation_mission','fn_ouvrir_litige_rate_limited','fn_inviter_membre_etablissement'])assert.equal(c.authorize(call(rpc,{})),false);
  assert.equal(c.authorize(call('fn_update_presence',{user_id:m.members[1].id})),false);
  for(let i=0;i<10;i++)assert(c.authorize(call('fn_update_presence',{})));
  assert.equal(c.authorize(call('fn_update_presence',{})),false);
  for(const path of ['/functions/v1/generate-invoice','/functions/v1/send-email','/rest/v1/messages_chat'])
    assert.equal(c.authorize({url:ORIGIN+path,method:'POST',body:{}}),false);
});

test('read scoping cannot be broadened by OR, duplicate selector, foreign object or embedding relation',()=>{
  const c=uiContractF1(m.members[0],m,documents),base=`${ORIGIN}/rest/v1/missions?select=id&${new URLSearchParams({id:`eq.${m.missionId}`})}`;
  assert(c.authorize({url:base,method:'GET'}));
  for(const url of [base+'&or=(id.not.is.null)',base+`&id=eq.${m.admin.id}`,base.replace(m.missionId,m.admin.id),
    base.replace('select=id','select=auth_users(*)'),base.replace(ORIGIN,'https://flripxtsyegjshnhzjkz.supabase.co'),
    base.replace('https://','https://canary@'),base+'#canary'])assert.equal(c.authorize({url,method:'GET'}),false);
  assert.equal(c.authorize({url:base,method:'PATCH',body:{statut:'PAYEE'}}),false);
});

test('Auth and dashboard writes have independent actor-specific one-shot budgets',()=>{
  for(const actor of m.members){const c=uiContractF1(actor,m,documents),auth={url:`${ORIGIN}/auth/v1/token?grant_type=password`,method:'POST',body:{email:actor.email,password:actor.password,gotrue_meta_security:{}}};
    assert(c.authorize(auth));assert.equal(c.authorize(auth),false);
    assert(c.authorize(call('fn_audit_connexion',{p_action:'CONNEXION'})));assert.equal(c.authorize(call('fn_audit_connexion',{p_action:'CONNEXION'})),false);
    assert.equal(!!c.authorize(call('fn_maj_activite_soignant',{})),actor.role==='SOIGNANT');
  }
});

test('network rejection aborts without calling fetch and stays a failing observation without retaining canaries',async()=>{
  let handler,fetches=0,aborted=0;const context={async addInitScript(){},async route(pattern,callback){handler=callback;}};
  const network=await installNetworkF1(context,m.members[0],m,documents,{recordAuth:async()=>{},assetPaths:new Set(['/assets/index.js'])});
  await handler({request:()=>({url:()=>`${ORIGIN}/functions/v1/send-email?token=CANARY`,postData:()=>null,method:()=> 'POST'}),
    async abort(){aborted++;},async fetch(){fetches++;}});
  await network.drain();await assert.rejects(network.assert(),/^Error: F1_NETWORK_FAILED$/);assert.equal(fetches,0);assert.equal(aborted,1);
});

test('HTML fallback removes only external font and DNS hints; module remains exact and third-party requests remain refused',()=>{
  const module='<script type="module" src="/assets/index-abc.js"></script>',css='<link rel="stylesheet" href="/assets/index.css">';
  assert.equal(preparerHtmlPreview(module+css+'<link rel="preconnect" href="https://x.invalid"><link rel="stylesheet" href="https://fonts.googleapis.com/css">'),module+css);
  assert.equal(uiContractF1(m.members[0],m,documents).authorize({url:'https://fonts.googleapis.com/css',method:'GET'}),false);
});

test('expected UI effects are ten connections, five establishment audits, one owned empty conversation and two presences; any extra effect fails',()=>{
  const current=structuredClone(m),[s,e]=current.members.map(x=>x.id);
  current.snapshots.uiAudit=[s,e].map(id=>({id,connexions:0,consultations:0,other:2}));
  const row={uiAudit:[{id:s,connexions:5,consultations:0,other:2},{id:e,connexions:5,consultations:5,other:2}],
    conversations:[{id:conversation,mission:current.missionId,soignant:s,etablissement:e,first:[s,e].sort()[0],second:[s,e].sort()[1]}],
    messages:0,presences:2,typing:0};verifyUiEffectsF1(row,current);
  for(const change of [x=>{x.messages=1;},x=>{x.conversations[0].second=m.admin.id;},x=>{x.uiAudit[0].connexions=4;},x=>{x.typing=1;},x=>{x.presences=3;}]){
    const bad=structuredClone(row);change(bad);assert.throws(()=>verifyUiEffectsF1(bad,current),/^Error: F1_UI_/);
  }
});

test('closed failure projection keeps category/known path/status/time, never arbitrary segments or credentials',()=>{
  const canary='CANARY-password-jwt@example.invalid';
  for(const url of [ORIGIN+'/rest/v1/missions?token='+canary,ORIGIN+'/rest/v1/'+canary,ORIGIN+'/storage/v1/object/sign/jolene-documents/'+canary,
    'https://'+canary+'@foreign.invalid/'+canary]) {
    const row=networkFailureF1({url,method:'POST',error:Error(canary),status:503,start:100,now:113});
    assert(!JSON.stringify(row).includes(canary));assert.equal(row.relative_ms,13);assert.equal(row.status,503);
  }
  const row=networkFailureF1({url:ORIGIN+'/rest/v1/missions?secret=hidden',method:'GET',error:Error('F1_NETWORK_REFUSED'),start:0,now:5});
  assert.equal(row.category,'F1_NETWORK_REFUSED');assert.equal(row.path,'/rest/v1/missions');
});

test('only registered signed GET may omit Authorization; signing and API still require the current session',async()=>{
  let handler,fetches=0,aborted=0;const bytes=Buffer.from('%PDF-real-transport-test'),token='private-jwt',signed='private-signed-token';
  const docs=documents.map(d=>({...d,pdf:{...d.pdf,size:bytes.length,sha256:sha256(bytes)}}));
  const context={async addInitScript(){},async route(pattern,callback){handler=callback;}};
  const network=await installNetworkF1(context,m.members[0],m,docs,{recordAuth:async()=>{},assetPaths:new Set()});
  async function dispatch(url,method,body,headers,data,isPdf=false){await handler({request:()=>({url:()=>url,method:()=>method,postData:()=>body?JSON.stringify(body):null,postDataJSON:()=>body,headers:()=>headers}),
    async fetch(){fetches++;return{ok:()=>true,status:()=>200,json:async()=>data,body:async()=>bytes};},async fulfill(){},async abort(){aborted++;}});}
  await dispatch(`${ORIGIN}/auth/v1/token?grant_type=password`,'POST',{email:m.members[0].email,password:m.members[0].password},{},{access_token:token});
  const path=`/storage/v1/object/sign/jolene-documents/${docs[0].pdf.key}`;
  await dispatch(ORIGIN+path,'POST',{expiresIn:300},{authorization:`Bearer ${token}`},{signedURL:path.slice('/storage/v1'.length)+`?token=${signed}`});
  await dispatch(ORIGIN+path+`?token=${signed}`,'GET',null,{},null,true);await network.assert();assert.equal(fetches,3);assert.equal(aborted,0);
  await dispatch(ORIGIN+path+'?token=unregistered','GET',null,{},null,true);assert.equal(fetches,3);assert.equal(aborted,1);await assert.rejects(network.assert(),/NETWORK_FAILED/);
});

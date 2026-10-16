import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {renderStagingAdmission} from '../../scripts/ci/connect-staging-admission-render.mjs';
import {renderStagingStandardV2} from '../../scripts/ci/connect-staging-standard-v2-render.mjs';
const read=p=>readFileSync(p,'utf8');
const output=ts.transpileModule(read('supabase/functions/_shared/stripe-connect-staging-test.ts'),{
 compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
assert.deepEqual(output.diagnostics,[]);
const {parseStagingConnectCapacity,requireStagingTransferScope,requireStagingPayoutScope,requireStagingPayoutEventScope}=await import(`data:text/javascript;base64,${Buffer.from(output.outputText).toString('base64')}`);
const id=n=>`f1620000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const config={serverSha:'a'.repeat(40),uiSha:'b'.repeat(40),manifestSha256:'c'.repeat(64),platformAccountId:'acct_TestPlatform',capabilityId:id(9),returnOrigin:'http://127.0.0.1:18491'};
function simulation(){
 const calls=[];
 const row={id:id(9),protocol:'CONNECT_STAGING_STANDARD_TEST_V2',project_ref:'mejpriaetwgtcstbgfid',run_id:'f1-standard-test',
  server_sha:config.serverSha,ui_sha:config.uiSha,source_manifest_sha256:config.manifestSha256,platform_account_id:config.platformAccountId,
  livemode:false,transfers_allowed:true,payouts_allowed:true,max_transfers:1,max_payouts:1,max_checkouts:1,max_refunds:1,
  enabled:true,revoked_at:null,expires_at:new Date(Date.now()+3600000).toISOString(),
  mission_id:id(3),etablissement_id:id(2),soignant_id:id(1),facture_honoraire_id:id(4),facture_commission_id:id(5),
  customer_id:'cus_Test',destination_id:'acct_TestRecipient',soignant_cents:8000,commission_cents:1440,total_cents:9440,
  operation_id:id(8),session_id:'cs_test_Test',trace_id:id(7),claim_reserved_at:new Date().toISOString(),
  transfer_reserved_at:null,transfer_id:null,payout_reserved_at:null,payout_id:null};
 const op={id:id(8),trace_id:id(7),session_id:row.session_id,payment_intent_id:'pi_Test',charge_id:'ch_Test',
  mission_id:id(3),etablissement_id:id(2),soignant_id:id(1),facture_honoraire_id:id(4),facture_commission_id:id(5),
  customer_id:row.customer_id,destination_id:row.destination_id,soignant_cents:8000,commission_cents:1440,total_cents:9440,
  livemode:false,orientation:'TRANSFER',litige_id:null,refund_id:null,refund_status:'READY'};
 const work={id:id(7),missionId:id(3),soignantId:id(1),etablissementId:id(2),factureHonoraireId:id(4),
  accountId:row.destination_id,customerId:row.customer_id,transferId:'tr_Test',paymentIntentId:'pi_Test',chargeId:'ch_Test',
  amountCents:8000,totalCents:9440,livemode:false,attempt:0,state:'WAITING',payoutId:null,previousPayoutId:null,firstPostAt:null};
 const payout={id:'po_Test',amount:8000,currency:'eur',livemode:false,automatic:false,status:'pending',
  metadata:{type:'CONNECT_STANDARD_PAYOUT',trace_id:work.id,transfer_id:work.transferId,mission_id:work.missionId,soignant_id:work.soignantId,attempt:'0'}};
 const sb={rpc:async(name,args)=>{
  calls.push({name,args});
  if(name==='fn_connect_test_capacite_lire'||name==='fn_connect_test_capacite_par_trace')return {data:row,error:null};
  if(name==='fn_connect_test_transfer_autoriser')return {data:{operation_id:op.id,allowed:true},error:null};
  if(name==='fn_connect_test_payout_autoriser')return {data:{trace_id:work.id,allowed:true},error:null};
  throw Error('Unexpected RPC');
 }};
 const stripe={accounts:{retrieve:async()=>({id:config.platformAccountId})},balance:{retrieve:async()=>({livemode:false})},
  payouts:{retrieve:async(pid,opts)=>{assert.equal(pid,payout.id);assert.deepEqual(opts,{stripeAccount:row.destination_id});return payout;}}};
 const transferred=()=>{row.transfer_reserved_at=new Date().toISOString();row.transfer_id=work.transferId;};
 return {row,op,work,payout,sb,stripe,calls,transferred};
}
test('V2 strict admits one transfer and one payout with immutable actor/document scope',async()=>{
 const s=simulation();assert.equal(parseStagingConnectCapacity(s.row,config).transfersAllowed,true);
 await requireStagingTransferScope(s.sb,s.stripe,config,s.op);
 assert.equal(s.calls.at(-1).name,'fn_connect_test_transfer_autoriser');
 s.transferred();await requireStagingPayoutScope(s.sb,s.stripe,config,s.work);
 assert.deepEqual(s.calls.at(-1),{name:'fn_connect_test_payout_autoriser',args:{p_trace_id:s.work.id,p_transfer_id:'tr_Test',p_attempt:0,p_server_sha:config.serverSha,p_manifest_sha256:config.manifestSha256}});
});
for(const [key,value] of Object.entries({protocol:'UNKNOWN',run_id:'',max_transfers:2,max_payouts:2,payouts_allowed:false,transfers_allowed:false,
 livemode:true,project_ref:'flripxtsyegjshnhzjkz',server_sha:'d'.repeat(40),source_manifest_sha256:'d'.repeat(64)}))
 test(`V2 refuses invalid ${key}`,()=>{const s=simulation();assert.throws(()=>parseStagingConnectCapacity({...s.row,[key]:value},config));});
for(const [key,value] of Object.entries({id:id(99),trace_id:id(99),session_id:'cs_test_Other',mission_id:id(99),etablissement_id:id(99),soignant_id:id(99),
 facture_honoraire_id:id(99),facture_commission_id:id(99),customer_id:'cus_Other',destination_id:'acct_Other',total_cents:9441,livemode:true,orientation:'REFUND'}))
 test(`transfer authorizer refuses ${key} mismatch before reservation`,async()=>{
  const s=simulation();await assert.rejects(()=>requireStagingTransferScope(s.sb,s.stripe,config,{...s.op,[key]:value}));
  assert.ok(!s.calls.some(c=>c.name==='fn_connect_test_transfer_autoriser'));
 });
for(const [key,value] of Object.entries({id:id(99),missionId:id(99),etablissementId:id(99),soignantId:id(99),factureHonoraireId:id(99),
 accountId:'acct_Other',customerId:'cus_Other',transferId:'tr_Other',amountCents:8001,totalCents:9441,livemode:true,attempt:1}))
 test(`payout authorizer refuses ${key} mismatch before reservation`,async()=>{
  const s=simulation();s.transferred();await assert.rejects(()=>requireStagingPayoutScope(s.sb,s.stripe,config,{...s.work,[key]:value}));
  assert.ok(!s.calls.some(c=>c.name==='fn_connect_test_payout_autoriser'));
 });
for(const change of [{enabled:false},{revoked_at:new Date().toISOString()},{expires_at:'2020-01-01T00:00:00Z'}])
 test(`closed capacity refuses provider creation ${Object.keys(change)[0]}`,async()=>{
  const s=simulation();Object.assign(s.row,change);await assert.rejects(()=>requireStagingTransferScope(s.sb,s.stripe,config,s.op));
  s.transferred();await assert.rejects(()=>requireStagingPayoutScope(s.sb,s.stripe,config,s.work));
 });
test('payout readback after expiration reconciles a reserved exact object without creation',async()=>{
 const s=simulation();s.transferred();s.row.payout_reserved_at=new Date().toISOString();s.row.expires_at='2020-01-01T00:00:00Z';
 await requireStagingPayoutEventScope(s.sb,s.stripe,config,s.row.destination_id,s.payout.id);
 assert.ok(!s.calls.some(c=>c.name.endsWith('_autoriser')));
});
for(const change of [{livemode:true},{amount:8001},{automatic:true},{currency:'usd'}, {metadata:{}}])
 test(`payout event refuses foreign provider object ${Object.keys(change)[0]}`,async()=>{
  const s=simulation();s.transferred();s.row.payout_reserved_at=new Date().toISOString();Object.assign(s.payout,change);
  await assert.rejects(()=>requireStagingPayoutEventScope(s.sb,s.stripe,config,s.row.destination_id,s.payout.id));
 });
test('payout event without reservation is never admitted',async()=>{
 const s=simulation();s.transferred();await assert.rejects(()=>requireStagingPayoutEventScope(s.sb,s.stripe,config,s.row.destination_id,s.payout.id));
});
const v1=renderStagingAdmission(read('supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql'),read('scripts/ci/connect-staging-admission.sql'));
const delta=read('scripts/ci/connect-staging-standard-v2.sql');
const payout=read('supabase/migrations/20261016125516_securiser_beneficiaire_connect_et_versements_standard.sql');
test('V2 renderer preserves LIVE entrypoint and does not allocate, enable or reclassify',()=>{
 const sql=renderStagingStandardV2(v1,delta,payout);
 assert.match(sql,/CONNECT_V2_CANONICAL_DRIFT/);assert.match(sql,/CONNECT_V2_PAYOUT_SOURCE_DRIFT/);
 assert.match(sql,/CREATE FUNCTION public.fn_connect_payout_demarrer_test/);
 assert.doesNotMatch(sql,/CREATE(?: OR REPLACE)? FUNCTION public.fn_connect_payout_demarrer\(/);
 assert.doesNotMatch(sql,/SET enabled\s*=\s*true|est_compte_test\s*=\s*false|INSERT INTO private\.stripe_connect_test_capacities/i);
 assert.match(sql,/o.livemode IS DISTINCT FROM FALSE/);
});
test('changed payout source fails generation rather than silently changing admission',()=>{
 assert.throws(()=>renderStagingStandardV2(v1,delta,payout.replace('OR o.livemode IS DISTINCT FROM TRUE','OR false')),/PATCH_ANCHOR/);
});

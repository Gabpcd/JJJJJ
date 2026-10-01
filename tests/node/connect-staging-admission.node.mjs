import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {renderStagingAdmission} from '../../scripts/ci/connect-staging-admission-render.mjs';
const source=readFileSync('supabase/functions/_shared/stripe-connect-staging-test.ts','utf8');
const output=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
assert.deepEqual(output.diagnostics,[]);
const {stagingConnectConfig,parseStagingConnectCapacity,readStagingConnectCapacity,verifyStagingStripeIdentity,authorizeStagingCheckout,requireStagingRefundScope}=await import(`data:text/javascript;base64,${Buffer.from(output.outputText).toString('base64')}`);
const id=n=>`f1560000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const config={serverSha:'a'.repeat(40),uiSha:'b'.repeat(40),manifestSha256:'c'.repeat(64),platformAccountId:'acct_PlatformTEST',capabilityId:id(9),returnOrigin:'http://127.0.0.1:18491'};
const env={SUPABASE_URL:'https://mejpriaetwgtcstbgfid.supabase.co',SUPABASE_ENV:'staging',STRIPE_SECRET_KEY:'sk_test_SyntheticOnly',CONNECT_STAGING_TEST_RUN:JSON.stringify(config)};
const row={id:id(9),protocol:'CONNECT_STAGING_TEST_V1',project_ref:'mejpriaetwgtcstbgfid',server_sha:config.serverSha,ui_sha:config.uiSha,source_manifest_sha256:config.manifestSha256,
 platform_account_id:config.platformAccountId,livemode:false,transfers_allowed:false,max_checkouts:1,max_refunds:1,enabled:true,revoked_at:null,expires_at:new Date(Date.now()+3600_000).toISOString(),
 mission_id:id(3),etablissement_id:id(2),soignant_id:id(1),facture_honoraire_id:id(4),facture_commission_id:id(5),customer_id:'cus_TEST',destination_id:'acct_RecipientTEST',
 soignant_cents:8000,commission_cents:1440,total_cents:9440,operation_id:id(8),trace_id:id(7),session_id:'cs_test_TEST',claim_reserved_at:new Date().toISOString()};
const op={id:id(8),facture_honoraire_id:id(4),session_id:'cs_test_TEST',livemode:false,orientation:'REFUND'};
const db={rpc:async()=>({data:row,error:null})};
const stripe={accounts:{retrieve:async()=>({id:config.platformAccountId})},balance:{retrieve:async()=>({livemode:false})}};
test('configuration absente ne lit aucun autre environnement',()=>{const keys=[];assert.equal(stagingConnectConfig(k=>{keys.push(k);return undefined;}),null);assert.deepEqual(keys,['CONNECT_STAGING_TEST_RUN']);});
test('configuration staging exacte acceptée sans effet réseau',()=>assert.deepEqual(stagingConnectConfig(k=>env[k]),config));
for(const [i,change] of [{SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co'},{STRIPE_SECRET_KEY:'sk_live_SYNTHETIC'},{SUPABASE_ENV:'production'},{CONNECT_STAGING_TEST_RUN:'{}'},
 {CONNECT_STAGING_TEST_RUN:JSON.stringify({...config,returnOrigin:'https://evil.example'})},{CONNECT_STAGING_TEST_RUN:JSON.stringify({...config,extra:'x'})}].entries())
 test(`runtime invalide ${i}`,()=>assert.throws(()=>stagingConnectConfig(k=>({...env,...change})[k])));
test('identité Stripe compte et balance TEST relus',async()=>verifyStagingStripeIdentity(stripe,config));
test('compte Stripe étranger refusé',async()=>assert.rejects(()=>verifyStagingStripeIdentity({...stripe,accounts:{retrieve:async()=>({id:'acct_Foreign'})}},config)));
test('balance live refusée',async()=>assert.rejects(()=>verifyStagingStripeIdentity({...stripe,balance:{retrieve:async()=>({livemode:true})}},config)));
test('capacité exacte positive',()=>assert.equal(parseStagingConnectCapacity(row,config).active,true));
test('Session sans trace ou opération refusée',()=>{assert.throws(()=>parseStagingConnectCapacity({...row,trace_id:null},config));assert.throws(()=>parseStagingConnectCapacity({...row,operation_id:null},config));});
for(const key of ['id','project_ref','server_sha','ui_sha','source_manifest_sha256','platform_account_id','customer_id','destination_id','session_id','operation_id','trace_id'])
 test(`capacité refuse ${key} étranger ou mal formé`,()=>assert.throws(()=>parseStagingConnectCapacity({...row,[key]:'foreign'},config)));
for(const [i,changes] of [{livemode:true},{transfers_allowed:true},{max_checkouts:2},{max_refunds:2},{total_cents:9441},{commission_cents:NaN},{soignant_cents:Number.MAX_SAFE_INTEGER},{etablissement_id:row.soignant_id},{facture_commission_id:row.facture_honoraire_id}].entries())
 test(`budget/identité refuse ${i}`,()=>assert.throws(()=>parseStagingConnectCapacity({...row,...changes},config)));
test('expiration distingue constat de création',async()=>{
 const expired={...row,expires_at:'2020-01-01T00:00:00Z'};
 assert.equal(parseStagingConnectCapacity(expired,config).active,false);
 const sb={rpc:async()=>({data:expired,error:null})};
 await readStagingConnectCapacity(sb,config,id(4));await assert.rejects(()=>readStagingConnectCapacity(sb,config,id(4),true));
});
test('révocation refuse création',async()=>assert.rejects(()=>readStagingConnectCapacity({rpc:async()=>({data:{...row,revoked_at:new Date().toISOString()},error:null})},config,id(4),true)));
test('RPC erreur ne vaut jamais autorisation',async()=>assert.rejects(()=>readStagingConnectCapacity({rpc:async()=>({data:row,error:{}})},config,id(4),true)));
test('FH étrangère refusée malgré retour valide',async()=>assert.rejects(()=>readStagingConnectCapacity(db,config,id(55),true)));
test('autorisation Checkout confirme le reçu exact après identité Stripe',async()=>{
 const calls=[];await authorizeStagingCheckout({rpc:async(name,args)=>{calls.push({name,args});return {data:{operation_id:op.id,allowed:true},error:null};}},stripe,config,op.id);
 assert.equal(calls[0].name,'fn_connect_test_checkout_autoriser');assert.equal(calls[0].args.p_manifest_sha256,config.manifestSha256);
});
test('autorisation Checkout receipt autre op refusé',async()=>assert.rejects(()=>authorizeStagingCheckout({rpc:async()=>({data:{operation_id:id(99),allowed:true},error:null})},stripe,config,op.id)));
test('refund seulement exact op Session mode',async()=>{
 await requireStagingRefundScope(db,config,op);
 for(const change of [{id:id(55)},{session_id:'cs_test_OTHER'},{livemode:true},{orientation:'TRANSFER'}])await assert.rejects(()=>requireStagingRefundScope(db,config,{...op,...change}));
});
const migration=readFileSync('supabase/migrations/20261001201055_reserver_remboursement_connect_avant_transfert.sql','utf8');
const helpers=readFileSync('scripts/ci/connect-staging-admission.sql','utf8');
test('raccord conserve gate false et source gelée',()=>{
 const sql=renderStagingAdmission(migration,helpers);
 assert.match(sql,/CONNECT_TEST_SOURCE_DRIFT/);assert.match(sql,/fn_stripe_payment_flow_claim_connect_test_v1/);
 assert.match(sql,/fn_connect_remboursements_test_a_traiter\(p_limit integer,p_capacity_id uuid\)/);
 assert.doesNotMatch(sql,/SET enabled\s*=\s*true/i);assert.doesNotMatch(sql,/est_compte_test\s*=\s*false/i);
 assert.doesNotMatch(sql,/INSERT INTO private\.stripe_connect_test_capacities/i);assert.match(sql,/CONNECT_TEST_TRANSFER_FORBIDDEN/);
});
test('source incompatible refuse raccord partiel',()=>assert.throws(()=>renderStagingAdmission(migration.replace(' -- Une insertion neuve a trace_id NULL',' -- source modifiée'),helpers),/STAGING_PATCH_ANCHOR/));

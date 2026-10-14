import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {webcrypto,createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import ts from 'typescript';
import {renderSignatureSmsStaging} from '../../scripts/ci/sms-signature-staging-render.mjs';

function transpile(path,module=ts.ModuleKind.ESNext){
 const result=ts.transpileModule(readFileSync(path,'utf8'),{compilerOptions:{module,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
 assert.deepEqual(result.diagnostics,[]);return result.outputText;
}
const helper=await import(`data:text/javascript;base64,${Buffer.from(transpile('supabase/functions/_shared/signature-sms-staging-test.ts')).toString('base64')}`);
const ui=await import(`data:text/javascript;base64,${Buffer.from(transpile('src/lib/signatureSmsStagingAdmission.ts')).toString('base64')}`);
const actor='f1560000-0000-4000-8000-000000000001',contract='f1560000-0000-4000-8000-000000000002',mission='f1560000-0000-4000-8000-000000000003';
const phone='+33612345678';
const config={runId:'sms-signature-synthetic-20261014',sourceSha:'a'.repeat(40),manifestSha256:'b'.repeat(64),accountSid:'AC'+'a'.repeat(32),senderPhone:'+33123456789'};
const env={SUPABASE_URL:'https://mejpriaetwgtcstbgfid.supabase.co',TWILIO_ACCOUNT_SID:config.accountSid,TWILIO_FROM_NUMBER:config.senderPhone,TWILIO_AUTH_TOKEN:'synthetic-only',SIGNATURE_SMS_STAGING_TEST_RUN:JSON.stringify(config)};
const syntheticCode='123456';
const payload={type:'OTP_SIGNATURE',prefix_type:'SIGNATURE',telephone:phone,destinataire_id:actor,
 contenu:`Code de signature Jolene : ${syntheticCode} (valide 10 min). Ne le partagez avec personne.`,
 idempotency_key:`otp-signature.${contract}.${actor}.soignant.1791979200.1`,data:{contrat_id:contract,mission_id:mission}};

test('absent config reads no provider/environment values',()=>{
 const keys=[];assert.equal(helper.signatureSmsStagingConfig(key=>{keys.push(key);return undefined;}),null);
 assert.deepEqual(keys,['SIGNATURE_SMS_STAGING_TEST_RUN']);
});
test('exact staging config accepts reserved env label absent',()=>assert.deepEqual(helper.signatureSmsStagingConfig(key=>env[key]),config));
for(const [name,changes] of [
 ['production',{SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co'}],
 ['foreign host',{SUPABASE_URL:'https://mejpriaetwgtcstbgfid.supabase.co.invalid'}],
 ['label production',{SUPABASE_ENV:'production'}],['missing credential',{TWILIO_AUTH_TOKEN:''}],
 ['other sender',{TWILIO_FROM_NUMBER:'+33123456780'}],['other provider account',{TWILIO_ACCOUNT_SID:'AC'+'b'.repeat(32)}],
 ['empty config',{SIGNATURE_SMS_STAGING_TEST_RUN:''}],['extra field',{SIGNATURE_SMS_STAGING_TEST_RUN:JSON.stringify({...config,enabled:true})}],
 ['missing manifest',{SIGNATURE_SMS_STAGING_TEST_RUN:JSON.stringify({...config,manifestSha256:undefined})}],
])test(`config fails closed: ${name}`,()=>assert.throws(()=>helper.signatureSmsStagingConfig(key=>({...env,...changes})[key]),/CONFIG_REFUSED/));

test('valid internal request produces bound hash, never the code',async()=>{
 const request=await helper.signatureSmsStagingRequest(config,true,payload,phone);
 assert.equal(request.p_otp_hash,createHash('sha256').update(`${syntheticCode}|${contract}|${actor}`).digest('hex'));
 assert.equal(request.p_mission_id,mission);assert.equal(request.p_actor_id,actor);
 assert.equal(Object.values(request).includes(syntheticCode),false);
 assert.equal('contenu' in request,false);
});
for(const [name,change] of [
 ['phone OTP',{type:'OTP_VERIFICATION_TELEPHONE'}],['ordinary message',{type:'CUSTOM'}],
 ['arbitrary content',{contenu:'arbitrary text'}],['missing mission',{data:{contrat_id:contract}}],
 ['malformed contract',{data:{contrat_id:'invalid',mission_id:mission}}],['extra data',{data:{...payload.data,override:true}}],
 ['other recipient key',{destinataire_id:mission}],['missing key',{idempotency_key:undefined}],['wrong prefix',{prefix_type:'CUSTOM'}],
])test(`request refuses ${name}`,async()=>assert.equal(await helper.signatureSmsStagingRequest(config,true,{...payload,...change},phone),null));
test('browser and missing runtime cannot admit OTP',async()=>{
 assert.equal(await helper.signatureSmsStagingRequest(config,false,payload,phone),null);
 assert.equal(await helper.signatureSmsStagingRequest(null,true,payload,phone),null);
});

async function exercise(options={}){
 const state={provider:[],reservations:[],finalizations:[],audits:[],logs:[]};
 const fail=name=>{throw new Error(`Unexpected simulated I/O: ${name}`);};
 const sb={from(table){
  if(table==='preferences_notifications'){const q={select:()=>q,eq:()=>q,maybeSingle:async()=>({data:{canal_sms:options.preference!==false},error:null})};return q;}
  if(table==='soignants'){const q={select:()=>q,eq:()=>q,maybeSingle:async()=>({data:{telephone:phone,supprime_le:null},error:null})};return q;}
  if(['sms_envoyes','journaux_audit'].includes(table))return {insert:async row=>{state.audits.push(row);return {error:null};}};
  return fail(table);
 },async rpc(name,args){
  if(name==='fn_mes_permissions_etab')return {data:{etablissement_id:mission,permissions:{missions:true}},error:null};
  if(name==='fn_pool_urgence_etablissement')return {data:[{soignant_id:actor}],error:null};
  if(name==='fn_verifier_rate_limit'||name==='fn_doit_notifier')return {data:true,error:null};
  if(name==='fn_reserver_sms_signature_recette'||name==='fn_reserver_envoi_sms_idempotent'){
   state.reservations.push({name,args});return {data:{statut:options.reservation??'RESERVE'},error:options.sqlError?{}:null};
  }
  if(name==='fn_finaliser_envoi_sms_idempotent'){state.finalizations.push(args);return {error:null};}
  return fail(name);
 }};
 const modules={
  'npm:@supabase/supabase-js@2.99.2':{createClient:()=>sb},
  '../_shared/rate-limit.ts':{applyRateLimit:()=>false,getClientIp:()=> '192.0.2.1'},
  '../_shared/cors.ts':{corsHeaders:{},jsonResponse:(_req,body,status=200)=>new Response(JSON.stringify(body),{status}),preflightResponse:()=>new Response(null,{status:204})},
  '../_shared/admin-auth.ts':{verifyUserOrServiceRole:async()=>({ok:true,isServiceRole:options.service!==false,userId:actor,role:options.admin?'ADMIN_PLATEFORME':'SOIGNANT'}),verifyAdminOrServiceRole:async()=>({ok:true})},
  '../_shared/test-account.ts':{resolveOperationalTestAccount:async()=>({ok:true,isTest:options.isTest!==false}),resolveOperationalTestSource:async()=>({ok:true,isTest:options.isTest!==false})},
  '../_shared/signature-sms-staging-test.ts':helper,
 };
 let handler;
 const runtime={...env,SUPABASE_SERVICE_ROLE_KEY:'synthetic-only',SUPABASE_ANON_KEY:'synthetic-only',...options.env};
 const log=(...args)=>state.logs.push(args.map(String).join(' '));
 runInNewContext(transpile('supabase/functions/send-sms/index.ts',ts.ModuleKind.CommonJS),{
  exports:{},require:name=>modules[name]??fail(name),Deno:{env:{get:key=>runtime[key]},serve:fn=>{handler=fn;}},
  console:{error:log,warn:log,info:log,log},Request,Response,URLSearchParams,TextEncoder,crypto:webcrypto,btoa,Error,
  fetch:async(url,init)=>{state.provider.push({url,body:Object.fromEntries(new URLSearchParams(String(init.body)))});
   if(options.networkFailure)throw new Error('synthetic transport failure');
   return new Response(JSON.stringify({sid:'SM'+'c'.repeat(32)}),{status:201});
  },
 });
 const response=await handler(new Request('https://example.invalid/send-sms',{method:'POST',headers:{Authorization:'Bearer synthetic-only','Content-Type':'application/json'},body:JSON.stringify({...payload,...options.payload})}));
 return {...state,status:response.status,body:await response.json()};
}
test('real handler admits TEST only through the scoped reservation then existing finalizer',async()=>{
 const result=await exercise();assert.equal(result.status,200);assert.equal(result.provider.length,1);
 assert.equal(result.reservations[0].name,'fn_reserver_sms_signature_recette');
 assert.equal(result.finalizations[0].p_statut,'ENVOYE');
 assert.equal(result.audits.at(-1).contenu,'Jolene: [CODE OTP MASQUÉ]');
 assert.equal(result.logs.join('').includes(syntheticCode),false);
});
for(const [name,options,status] of [
 ['no admission config',{env:{SIGNATURE_SMS_STAGING_TEST_RUN:undefined}},200],
 ['preference remains off',{preference:false},200],['browser cannot request OTP',{service:false},403],
 ['SQL admission refusal',{sqlError:true},503],
 ['provider prefix changed',{env:{SMS_PREFIX_OVERRIDES:JSON.stringify({SIGNATURE:'Other: '})}},503],
 ['ordinary TEST SMS',{payload:{type:'CUSTOM'}},200],
 ['wrong OTP content',{payload:{contenu:'arbitrary content'}},200],
 ['foreign runtime',{env:{SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co'}},500],
])test(`real handler sends nothing: ${name}`,async()=>{const result=await exercise(options);assert.equal(result.status,status);assert.equal(result.provider.length,0);});
for(const status of ['DEJA_ENVOYE','EN_COURS','INDETERMINE','CONFLIT'])test(`existing ledger ${status} never repeats provider`,async()=>{
 const result=await exercise({reservation:status});assert.equal(result.provider.length,0);
});
test('ambiguous transport finalizes INDETERMINE without retry or code log',async()=>{
 const result=await exercise({networkFailure:true});assert.equal(result.provider.length,1);
 assert.equal(result.finalizations[0].p_statut,'INDETERMINE');assert.equal(result.logs.join('').includes(syntheticCode),false);
});
for(const [name,options] of [
 ['NORMAL internal OTP with configured manifest',{isTest:false}],
 ['NORMAL internal ordinary SMS',{isTest:false,payload:{type:'CUSTOM'}}],
 ['NORMAL internal OTP without manifest',{isTest:false,env:{SIGNATURE_SMS_STAGING_TEST_RUN:undefined}}],
 ['NORMAL internal OTP with invalid manifest',{isTest:false,env:{SIGNATURE_SMS_STAGING_TEST_RUN:'invalid'}}],
 ['NORMAL browser urgent alert with full permissions',{isTest:false,service:false,payload:{type:'MISSION_URGENTE'}}],
 ['NORMAL admin browser test',{isTest:false,service:false,admin:true,payload:{type:'TEST_ADMIN'}}],
])test(`shared staging remains closed: ${name}`,async()=>{
 const result=await exercise(options);assert.equal(result.status,200);assert.equal(result.body.reason,'staging_sms_closed');
 assert.equal(result.provider.length,0);assert.equal(result.reservations.length,0);assert.equal(result.finalizations.length,0);
});
test('NORMAL staging browser cannot invoke OTP directly',async()=>{
 const result=await exercise({isTest:false,service:false});assert.equal(result.status,403);assert.equal(result.provider.length,0);
});
test('production NORMAL internal OTP keeps existing reservation without reading staging config',async()=>{
 const result=await exercise({isTest:false,env:{SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co',SIGNATURE_SMS_STAGING_TEST_RUN:'invalid'}});
 assert.equal(result.status,200);assert.equal(result.reservations[0].name,'fn_reserver_envoi_sms_idempotent');
 assert.equal(result.provider.length,1);
});
test('production NORMAL browser urgent alert keeps existing permissions and transport',async()=>{
 const result=await exercise({isTest:false,service:false,payload:{type:'MISSION_URGENTE'},env:{SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co'}});
 assert.equal(result.status,200);assert.equal(result.provider.length,1);assert.equal(result.reservations[0].name,'fn_reserver_envoi_sms_idempotent');
});

const source=readFileSync('scripts/ci/sms-signature-staging-otp.source.sql','utf8');
const sql=readFileSync('scripts/ci/sms-signature-staging.sql','utf8');
test('closed supplement renders exact LIVE source and retains concurrency guards',()=>{
 const rendered=renderSignatureSmsStaging(source,sql);
 assert.match(rendered,/SIGNATURE_SMS_TEST_INSTALLATION_REFUSED/);
 assert.match(rendered,/FOR UPDATE/);assert.match(rendered,/RETURNING id INTO v_signature_id/);
 assert.match(rendered,/DEFAULT false/);assert.match(rendered,/interval '60 minutes'/);
 assert.match(rendered,/private\.fn_reserver_envoi_sms_idempotent\(p_idempotency_key,p_request_fingerprint\)/);
 assert.doesNotMatch(rendered,/INSERT INTO private\.signature_sms_test_capacities|SET enabled\s*=\s*true|est_compte_test\s*:=?\s*false/i);
 assert.equal((rendered.match(/CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_signature/g)||[]).length,1);
});
test('any LIVE source drift is refused before producing SQL',()=>assert.throws(()=>renderSignatureSmsStaging(source+'\n',sql),/SOURCE_DRIFT/));

test('UI never calls admission on production or malformed IDs',async()=>{
 let calls=0;const client={rpc:async()=>{calls++;return {data:{admitted:true},error:null};}};
 assert.equal(await ui.readSignatureSmsStagingAdmission(client,'https://flripxtsyegjshnhzjkz.supabase.co',contract),null);
 assert.equal(await ui.readSignatureSmsStagingAdmission(client,env.SUPABASE_URL,'invalid'),null);assert.equal(calls,0);
});
test('UI read is exact caller-bound RPC and requires finite fresh bounded admission',async()=>{
 const now=Date.now(),valid={admitted:true,can_send:true,can_validate:false,remaining:2,expires_at:new Date(now+30_000).toISOString()};let call;
 const client={rpc:async(name,args)=>{call={name,args};return {data:valid,error:null};}};
 assert.deepEqual(await ui.readSignatureSmsStagingAdmission(client,env.SUPABASE_URL,contract,now),{expiresAt:now+30_000,canSend:true,canValidate:false});
 assert.deepEqual(call,{name:'fn_admission_otp_signature_recette',args:{p_contrat_id:contract}});
 for(const change of [{admitted:false},{admitted:'true'},{remaining:0},{remaining:3},{expires_at:'invalid'},{expires_at:new Date(now).toISOString()},{expires_at:new Date(now+3600_001).toISOString()}]){
  assert.equal(await ui.readSignatureSmsStagingAdmission({rpc:async()=>({data:{...valid,...change},error:null})},env.SUPABASE_URL,contract,now),null);
 }
 assert.equal(await ui.readSignatureSmsStagingAdmission({rpc:async()=>({data:valid,error:{}})},env.SUPABASE_URL,contract,now),null);
 assert.deepEqual(await ui.readSignatureSmsStagingAdmission({rpc:async()=>({data:{...valid,remaining:0,can_send:false,can_validate:true},error:null})},env.SUPABASE_URL,contract,now),
  {expiresAt:now+30_000,canSend:false,canValidate:true});
 assert.equal(await ui.readSignatureSmsStagingAdmission({rpc:async()=>({data:{...valid,remaining:0,can_send:false,can_validate:false},error:null})},env.SUPABASE_URL,contract,now),null);
});

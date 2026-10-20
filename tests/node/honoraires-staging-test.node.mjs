import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import ts from 'typescript';
import { createClient } from '@supabase/supabase-js';
// Real worker, admission and auth helper; only network/SQL boundaries are mocked.
const root = new URL('../../', import.meta.url);
const M='11111111-1111-4111-8111-111111111111', C='22222222-2222-4222-8222-222222222222';
const T='33333333-3333-4333-8333-333333333333', H='44444444-4444-4444-8444-444444444444', F='55555555-5555-4555-8555-555555555555';
const config=()=>({capabilityId:C,missionId:M,sourceSha:'a'.repeat(40),manifestSha256:'b'.repeat(64),
 createdAt:new Date(Date.now()-1000).toISOString(),expiresAt:new Date(Date.now()+900000).toISOString()});
function banc(options={}) {
 const c={...config(),...options.config}, calls=[], unknown=[];let clients=0, handler;
 const env={SUPABASE_URL:'https://mejpriaetwgtcstbgfid.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'service-fictif',
  SUPABASE_ENV:'staging',HONORAIRES_STAGING_TEST_RUN:JSON.stringify(c),...options.env};
 const modules=new Map();let takeCount=0;
 const json=(v,status=200)=>new Response(JSON.stringify(v),{status,headers:{'content-type':'application/json'}});
 const transport=async(input,init)=>{
  const req=new Request(input,init), u=new URL(req.url),body=await req.json();calls.push({path:u.pathname,body});
  try {
   assert.equal(u.origin,env.SUPABASE_URL);assert.equal(u.search,'');assert.equal(req.method,'POST');
   assert.equal(req.headers.get('apikey'),'service-fictif');
   if(u.pathname==='/rest/v1/rpc/fn_demande_honoraires_recette'){
    assert.deepEqual(Object.keys(body).sort(),['p_action','p_capacity_id','p_created_at','p_expires_at','p_manifest_sha256','p_mission_id','p_source_sha','p_token']);
    for(const [k,v] of Object.entries({p_capacity_id:C,p_mission_id:M,p_source_sha:c.sourceSha,p_manifest_sha256:c.manifestSha256,p_created_at:c.createdAt,p_expires_at:c.expiresAt}))assert.equal(body[k],v);
    if(body.p_action==='PRENDRE'){
     assert.equal(body.p_token,null);takeCount++;
     return json(options.take ?? (takeCount>1 ? {state:'TERMINEE',mission_id:M,facture_id:H,facture_commission_id:F}
      : {state:'PRISE',mission_id:M,token:T,invoke:true}));
    }
    assert.equal(body.p_action,'INVOQUER');assert.equal(body.p_token,T);
    if(options.admitError)return json({message:'closed'},403);
    return json({state:'AUTORISEE',mission_id:M});
   }
   if(u.pathname==='/rest/v1/rpc/fn_mission_est_reelle_pour_service'){
    assert.deepEqual(body,{p_mission_id:M});return json(options.real ?? false);
   }
   if(u.pathname==='/functions/v1/generate-invoice'){
    assert.deepEqual(body,{mission_id:M,service_role_reason:`ops_test_honoraires_${C}`});
    if(options.lost)throw new TypeError('LOST_RESPONSE_FIXTURE');
    return json({success:options.httpSuccess ?? true},options.httpStatus ?? 200);
   }
   if(u.pathname==='/rest/v1/rpc/fn_constater_demande_facturation_honoraires'){
    assert.deepEqual(body,{p_mission_id:M,p_token:T});return json(options.observed ?? {success:true,facture_id:H,facture_commission_id:F});
   }
   throw new Error('Unexpected transport');
  }catch(e){if(e.message!=='LOST_RESPONSE_FIXTURE')unknown.push(String(e));throw e;}
 };
 const paths=['weekly-invoicing-cron/index.ts','_shared/cron-service-auth.ts','_shared/demandes-facturation-honoraires.ts','_shared/honoraires-staging-test.ts'];
 const context={Request,Response,Headers,TextEncoder,crypto:webcrypto,setTimeout,console:{log(){},warn(){},error(){}},
  fetch(){throw new Error('NETWORK_FORBIDDEN');},Deno:{env:{get:k=>env[k]},serve:fn=>{assert.equal(handler,undefined);handler=fn;}}};
 function load(path){
  assert(paths.includes(path));if(modules.has(path))return modules.get(path);
  const module={exports:{}};modules.set(path,module.exports);
  const source=ts.transpileModule(readFileSync(new URL('supabase/functions/'+path,root),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const require=name=>{
   if(name==='npm:@supabase/supabase-js@2')return {createClient:(url,key,opts)=>{clients++;return createClient(url,key,{...opts,global:{fetch:transport}});}};
   const mapped=({'../_shared/cron-service-auth.ts':paths[1],'./cron-service-auth.ts':paths[1],
    '../_shared/demandes-facturation-honoraires.ts':paths[2],'../_shared/honoraires-staging-test.ts':paths[3]})[name];
   assert(mapped,'Unknown import '+name);return load(mapped);
  };
  new vm.Script(`(function(require,module,exports,${Object.keys(context).join(',')}){${source}\n})`).runInThisContext()(require,module,module.exports,...Object.values(context));
  return module.exports;
 }
 load(paths[0]);
 return {calls,unknown,get clients(){return clients;},run:(body={mode:'demandes-test'},headers={authorization:'Bearer service-fictif'})=>handler(new Request(env.SUPABASE_URL+'/functions/v1/weekly-invoicing-cron',{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)}))};
}
test('exact TEST path: take, false classification, durable budget, canonical generator, canonical ack; replay has no generation',async()=>{
 const b=banc();let r=await b.run();assert.equal(r.status,200);assert.equal((await r.json()).replay,false);
 assert.deepEqual(b.calls.map(c=>c.path),['/rest/v1/rpc/fn_demande_honoraires_recette','/rest/v1/rpc/fn_mission_est_reelle_pour_service','/rest/v1/rpc/fn_demande_honoraires_recette','/functions/v1/generate-invoice','/rest/v1/rpc/fn_constater_demande_facturation_honoraires']);
 r=await b.run();assert.equal(r.status,200);assert.equal((await r.json()).replay,true);
 assert.equal(b.calls.filter(c=>c.path.startsWith('/functions/')).length,1);assert.deepEqual(b.unknown,[]);
});
test('PROD, cron credential, closed/expired/malformed config and other transport admission refuse before client/SQL',async()=>{
 const cases=[{env:{SUPABASE_URL:'https://flripxtsyegjshnhzjkz.supabase.co'}},{env:{SUPABASE_ENV:'production'}},
  {env:{HONORAIRES_STAGING_TEST_RUN:undefined}},{env:{HONORAIRES_STAGING_TEST_RUN:'{'}},
  {config:{expiresAt:new Date(Date.now()-1000).toISOString()}},{config:{expiresAt:new Date(Date.now()+3600001).toISOString()}},
  {config:{missionId:[M]}},{config:{extra:'unexpected'}},
  ...['CONNECT_STAGING_TEST_RUN','INVOICE_STAGING_TEST_RUN','SIGNATURE_SMS_STAGING_TEST_RUN','INVOICE_EMAIL_STAGING_TEST_RUN'].map(k=>({env:{[k]:'{}'}}))];
 for(const args of cases){const b=banc(args);assert.equal((await b.run()).status,403);assert.equal(b.clients,0);assert.deepEqual(b.calls,[]);}
 for(const headers of [{},{'x-jolene-cron-secret':'service-fictif'},{authorization:'Bearer forged'}]){
  const b=banc();assert.equal((await b.run(undefined,headers)).status,403);assert.equal(b.clients,0);
 }
 const b=banc();assert.equal((await b.run({mode:'demandes-test',mission_id:M})).status,403);assert.equal(b.clients,0);
});
test('real classification, wrong scope/token/response or refused budget never invoke',async()=>{
 for(const args of [{real:true},{admitError:true},{take:{state:'PRISE',mission_id:C,token:T,invoke:true}},
  {take:{state:'PRISE',mission_id:M,token:[T],invoke:true}},{take:{state:'PRISE',mission_id:M,token:T,invoke:'true'}}]){
  const b=banc(args);assert.equal((await b.run()).status,403);assert.equal(b.calls.filter(c=>c.path.startsWith('/functions/')).length,0);assert.deepEqual(b.unknown,[]);
 }
});
test('busy lease is a no-effect 409; ambiguous replay can only acknowledge',async()=>{
 const busy=banc({take:{state:'OCCUPEE',mission_id:M}});assert.equal((await busy.run()).status,409);assert.equal(busy.calls.length,1);
 const replay=banc({take:{state:'PRISE',mission_id:M,token:T,invoke:false}});assert.equal((await replay.run()).status,200);
 assert.deepEqual(replay.calls.map(c=>c.path),['/rest/v1/rpc/fn_demande_honoraires_recette','/rest/v1/rpc/fn_constater_demande_facturation_honoraires']);
});
test('HTTP alone never acknowledges; lost response does not cause another generation',async()=>{
 for(const args of [{observed:{success:false}},{httpStatus:500},{lost:true},{observed:{success:true}}]){
  const b=banc(args),r=await b.run();assert.equal(r.status,args.observed?409:200);
  assert.equal(b.calls.filter(c=>c.path.startsWith('/functions/')).length,1);
  assert.equal(b.calls.at(-1).path,'/rest/v1/rpc/fn_constater_demande_facturation_honoraires');assert.deepEqual(b.unknown,[]);
 }
});

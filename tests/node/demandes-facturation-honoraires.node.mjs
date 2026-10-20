import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import ts from 'typescript';
import { createClient } from '@supabase/supabase-js';
const root = new URL('../../', import.meta.url);
const M='11111111-1111-4111-8111-111111111111', T='22222222-2222-4222-8222-222222222222';
const entry = () => ({mission_id:M,token:T,body:{mission_id:M}});
function banc({entries=[entry()], observed=true, invokeStatus=200, loseResponse=false, real=true, classifyFailure=false, takeFailure=false}={}) {
 const calls=[],authReads=[],unknown=[],env={SUPABASE_URL:'https://recette.invalid',SUPABASE_SERVICE_ROLE_KEY:'service-fictif',CRON_AUTOMATIONS_SECRET:'cron-fictif',CRON_SECRET:undefined,SUPABASE_SECRET_KEY:undefined,SB_SECRET_KEY:undefined,SUPABASE_SECRET_KEYS:undefined};
 let handler; const modules=new Map();
 const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
 const transport=async(input,init)=>{
  const req=new Request(input,init),u=new URL(req.url),body=await req.json();
  const call={path:u.pathname,body};
  try {
   assert.equal(u.origin,env.SUPABASE_URL);assert.equal(u.search,'');assert.equal(req.method,'POST');
   assert.equal(req.headers.get('apikey'),env.SUPABASE_SERVICE_ROLE_KEY);
   if(['/rest/v1/rpc/fn_lire_secret_cron_automations','/rest/v1/rpc/fn_lire_secret_cron'].includes(u.pathname)){assert.deepEqual(body,{});authReads.push(call);return json(null);}
   calls.push(call);
   if(u.pathname==='/rest/v1/rpc/fn_prendre_demandes_facturation_honoraires'){
    assert.deepEqual(body,{p_limit:3});return takeFailure?json({message:'unavailable'},503):json(entries);
   }
   if(u.pathname==='/rest/v1/rpc/fn_mission_est_reelle_pour_service'){
    assert.deepEqual(body,{p_mission_id:M});return classifyFailure?json({message:'unavailable'},503):json(real);
   }
   if(u.pathname==='/functions/v1/generate-invoice'){
    assert.equal(body.mission_id,M);assert.equal(body.service_role_reason,'cron_auto_generation');
    if(loseResponse)throw new TypeError('lost');
    return json(invokeStatus===200?{success:true,facture_id:'fiction'}:{error:'exists'},invokeStatus);
   }
   if(u.pathname==='/rest/v1/rpc/fn_constater_demande_facturation_honoraires'){
    assert.deepEqual(body,{p_mission_id:M,p_token:T});return json({success:observed});
   }
   if(u.pathname==='/rest/v1/rpc/fn_lister_missions_a_facturer'){assert.deepEqual(body,{});return json({finales:[],hebdo:[]});}
   throw new Error('Unknown transport '+u.pathname);
  }catch(e){if(e.message!=='lost')unknown.push(String(e));throw e;}
 };
 const context={Request,Response,Headers,TextEncoder,crypto:webcrypto,console:{log(){},warn(){},error(){}},setTimeout,
  Deno:{env:{get(k){assert(Object.hasOwn(env,k),'unknown env '+k);return env[k];}},serve(fn){assert.equal(handler,undefined);handler=fn;}},
  fetch(){throw new Error('Network forbidden');}};
 const allowed=['supabase/functions/weekly-invoicing-cron/index.ts','supabase/functions/_shared/demandes-facturation-honoraires.ts','supabase/functions/_shared/cron-service-auth.ts','supabase/functions/_shared/honoraires-staging-test.ts'];
 function load(path){
  assert(allowed.includes(path),path);if(modules.has(path))return modules.get(path);
  const module={exports:{}};modules.set(path,module.exports);
  const js=ts.transpileModule(readFileSync(new URL(path,root),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const require=(name)=>{
   if(name==='npm:@supabase/supabase-js@2')return {createClient:(url,key,opts)=>{assert.equal(url,env.SUPABASE_URL);assert.equal(key,env.SUPABASE_SERVICE_ROLE_KEY);return createClient(url,key,{...opts,global:{fetch:transport}});}};
   if(name==='../_shared/cron-service-auth.ts'||name==='./cron-service-auth.ts')return load(allowed[2]);
   if(name==='../_shared/honoraires-staging-test.ts')return load(allowed[3]);
   if(name==='../_shared/demandes-facturation-honoraires.ts')return load(allowed[1]);
   throw new Error('Import forbidden '+name);
  };
  new vm.Script(`(function(require,module,exports,${Object.keys(context).join(',')}){${js}\n})`).runInThisContext()(require,module,module.exports,...Object.values(context));
  return module.exports;
 }
 load(allowed[0]);
 return {calls,unknown, async run(body={mode:'demandes'},headers={'x-jolene-cron-secret':'cron-fictif'}){
  return handler(new Request('https://recette.invalid/functions/v1/weekly-invoicing-cron',{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)}));
 }};
}
test('demandes seules : vrai handler/auth/client, aucun listeur global ni autre effet',async()=>{
 const b=banc(),r=await b.run();assert.equal(r.status,200);assert.equal((await r.json()).ok,1);
 assert.deepEqual(b.calls.map(x=>x.path),['/rest/v1/rpc/fn_prendre_demandes_facturation_honoraires','/rest/v1/rpc/fn_mission_est_reelle_pour_service','/functions/v1/generate-invoice','/rest/v1/rpc/fn_constater_demande_facturation_honoraires']);assert.deepEqual(b.unknown,[]);
});
test('200 incomplet reste échec ; 409/réponse perdue complète peut être acquittée seulement par SQL',async()=>{
 for(const args of [{observed:false},{invokeStatus:409},{loseResponse:true}]){
  const b=banc(args),r=await b.run();assert.equal(r.status,args.observed===false?500:200);
  assert.equal(b.calls.filter(x=>x.path.includes('/functions/')).length,1);
  assert.equal(b.calls.at(-1).path,'/rest/v1/rpc/fn_constater_demande_facturation_honoraires');
 }
});
test('classification TEST ou indisponible : aucun appel générateur',async()=>{
 for(const args of [{real:false},{classifyFailure:true}]){
  const b=banc({...args,observed:false}),r=await b.run();assert.equal(r.status,args.real===false?200:500);
  assert.equal(b.calls.filter(x=>x.path.includes('/functions/')).length,0);
 }
});
test('modes inconnus et auth invalide refusent avant prise de demande',async()=>{
 for(const body of [{mode:'global'},[],{mode:'demandes',mission_id:M},null]){
  const b=banc();assert.equal((await b.run(body)).status,400);assert.deepEqual(b.calls,[]);
 }
 const b=banc();assert.equal((await b.run({}, {'x-jolene-cron-secret':'forged'})).status,401);assert.deepEqual(b.calls,[]);
});
test('lot mal formé/doublon/paramètre externe : aucun générateur ni constat',async()=>{
 for(const entries of [[{...entry(),body:{mission_id:M,facture_id:T}}],[entry(),entry()],null,Array.from({length:4},entry)]){
  const b=banc({entries});assert.equal((await b.run()).status,500);assert.equal(b.calls.length,1);
 }
});
test('passage quotidien garde le listeur et le drain, sonde auth sans aucun effet',async()=>{
 const b=banc({entries:[]});assert.equal((await b.run({})).status,200);assert.equal(b.calls.at(-1).path,'/rest/v1/rpc/fn_lister_missions_a_facturer');
 const probe=banc();assert.equal((await probe.run({mode:'demandes'},{'x-jolene-cron-secret':'cron-fictif','x-jolene-cron-probe':'auth-only'})).status,200);assert.deepEqual(probe.calls,[]);
});

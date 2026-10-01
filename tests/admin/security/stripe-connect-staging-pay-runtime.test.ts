import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {runInNewContext} from 'node:vm';
import ts from 'typescript';
import {describe,it,expect} from 'vitest';

// Vrai handler et vrais helpers. Seuls les transports Auth/DB/Stripe sont en
// mémoire : ce fichier ne constitue pas une preuve d'intégration fournisseur.
type Row=Record<string,any>;
const id=(n:number)=>`f1580000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [M,E,S,H,C,T,O,CAP]=Array.from({length:8},(_,n)=>id(n+1));
const SESSION='cs_test_F158';
const transpiled=new Map<string,string>();
function simulate(){
 const calls:string[]=[],writes:string[]=[],unexpected:string[]=[];
 const config={serverSha:'a'.repeat(40),uiSha:'b'.repeat(40),manifestSha256:'c'.repeat(64),platformAccountId:'acct_PlatformTEST',capabilityId:CAP,returnOrigin:'http://127.0.0.1:18491'};
 const capacity:Row={id:CAP,protocol:'CONNECT_STAGING_TEST_V1',project_ref:'mejpriaetwgtcstbgfid',server_sha:config.serverSha,ui_sha:config.uiSha,source_manifest_sha256:config.manifestSha256,
  platform_account_id:config.platformAccountId,livemode:false,transfers_allowed:false,max_checkouts:1,max_refunds:1,enabled:true,revoked_at:null,expires_at:new Date(Date.now()+3600000).toISOString(),
  mission_id:M,etablissement_id:E,soignant_id:S,facture_honoraire_id:H,facture_commission_id:C,customer_id:'cus_F158',destination_id:'acct_RecipientTEST',
  soignant_cents:8000,commission_cents:1440,total_cents:9440,operation_id:null,session_id:null,trace_id:null,claim_reserved_at:null};
 const metadata={type:'CONNECT_MISSION_PAYMENT',payment_scope:'INVOICE',connect_operation_id:O,mission_id:M,etablissement_id:E,soignant_id:S,connected_account_id:capacity.destination_id,
  facture_honoraires_id:H,facture_commission_id:C,soignant_cents:'8000',commission_cents:'1440'};
 const session:Row={id:SESSION,metadata,customer:capacity.customer_id,client_reference_id:M,livemode:false,currency:'eur',amount_total:9440,status:'open',payment_status:'unpaid',payment_intent:null,
  client_secret:'test_client_secret',created:Math.floor(Date.now()/1000),expires_at:Math.floor(Date.now()/1000)+3600};
 const provider:Row={sessions:[],platformId:config.platformAccountId,livemode:false,customer:{id:capacity.customer_id,livemode:false,metadata:{etablissement_id:E}},
  destination:{id:capacity.destination_id,metadata:{soignant_id:S},charges_enabled:true,payouts_enabled:true,details_submitted:true,capabilities:{transfers:'active'},requirements:{disabled_reason:null,currently_due:[]}}};
 const db:Record<string,Row[]>={missions:[{id:M,etablissement_id:E,soignant_assigne_id:S,statut:'EN_COURS',strategie_facturation:'HEBDO_ET_FINALE',type_contrat_applique:'LIBERAL',montant_commission_ttc:14.4,net_a_payer:80}],
  factures_honoraires:[{id:H,mission_id:M,etablissement_id:E,soignant_id:S,statut:'EMISE',montant_ttc:80,periode_fin:'2020-01-05',est_facture_finale_mission:false,stripe_payment_intent_id:null}],
  etablissements:[{id:E,stripe_customer_id:capacity.customer_id,nom:'Fixture',email_contact:'fixture@example.invalid'}],soignants:[{id:S,type_exercice:'LIBERAL'}],
  stripe_transfers:[],factures:[{id:C,facture_honoraire_id:H,mission_id:M,etablissement_id:E,type_document:'FACTURE',statut:'EMISE',montant_ttc:14.4,stripe_payment_intent_id:null,stripe_hosted_url:null}],
  stripe_connect_onboarding:[{soignant_id:S,stripe_account_id:capacity.destination_id,statut:'COMPLET'}],paiements_mission:[],litiges:[],stripe_payment_flow_claims:[]};
 const forbid=(x:string):never=>{unexpected.push(x);throw Error(`FORBIDDEN:${x}`);};
 const settings={userId:E,bothTest:true,claimError:false,authorizationError:false,admissionError:false,claimResponseLost:false,reserveError:false};
 const sb={from(table:string){
  if(!db[table])return forbid(`table:${table}`);calls.push(`read:${table}`);
  const filters:((r:Row)=>boolean)[]=[];let update:Row|undefined,insert:Row|undefined;
  const execute=()=>{let rows=db[table].filter(r=>filters.every(f=>f(r)));
   if(update){writes.push(`update:${table}`);rows.forEach(r=>Object.assign(r,structuredClone(update)));}
   if(insert){writes.push(`insert:${table}`);const r={id:T,...structuredClone(insert)};db[table].push(r);rows=[r];}
   return {data:structuredClone(rows),error:null};};
  const q:any={select:()=>q,eq:(k:string,v:unknown)=>{filters.push(r=>r[k]===v);return q;},neq:(k:string,v:unknown)=>{filters.push(r=>r[k]!==v);return q;},
   is:(k:string,v:unknown)=>{filters.push(r=>r[k]===v);return q;},in:(k:string,v:unknown[])=>{filters.push(r=>v.includes(r[k]));return q;},
   or:(expression:string)=>{filters.push(r=>expression.split(',').some(term=>{const [k,op,v]=term.split('.');return op==='eq'?r[k]===v:op==='is'&&v==='null'&&r[k]===null;}));return q;},order:()=>q,limit:()=>q,
   update:(v:Row)=>{update=v;return q;},insert:(v:Row)=>{insert=v;return q;},
   maybeSingle:async()=>{const result=execute();return {...result,data:result.data[0]??null};},single:()=>q.maybeSingle(),
   then:(yes:any,no:any)=>Promise.resolve(execute()).then(yes,no)};return q;
 },async rpc(name:string,args:Row){calls.push(`rpc:${name}`);
  if(name==='fn_a_permission_etablissement')return {data:true,error:null};
  if(name==='fn_connect_test_capacite_lire')return {data:structuredClone(capacity),error:null};
  if(name==='fn_connect_avant_transfert_lire')return {data:null,error:null};
  if(name==='fn_stripe_payment_flow_claim_connect_test_v1'){
   if(settings.claimError)return {data:null,error:{message:'CONNECT_TEST_NO_HISTORICAL_CLAIM'}};
   writes.push('rpc:claim');if(!db.stripe_payment_flow_claims.length)db.stripe_payment_flow_claims.push({resource_key:`FACTURE:${C}`,flow:'CONNECT_INVOICE',owner_token:`connect-invoice:${H}`,stripe_checkout_session_id:null,stripe_payment_intent_id:null});
   capacity.claim_reserved_at=capacity.claim_reserved_at??new Date().toISOString();
   if(settings.claimResponseLost)return {data:null,error:{message:'response lost'}};
   return {data:{acquired:true,resources:[`FACTURE:${C}`],stripe_checkout_session_id:null,stripe_payment_intent_id:null},error:null};
  }
  if(name==='fn_connect_checkout_preparer'){if(settings.reserveError)return {data:null,error:{message:'reserve unavailable'}};writes.push('rpc:reserve');capacity.operation_id=O;return {data:{operation_id:O,facture_honoraire_id:H,facture_commission_id:C},error:null};}
  if(name==='fn_connect_test_checkout_autoriser'){expect(args).toEqual({p_operation_id:O,p_server_sha:config.serverSha,p_manifest_sha256:config.manifestSha256});return {data:settings.authorizationError?null:{operation_id:O,allowed:true},error:settings.authorizationError?{message:'closed'}:null};}
  if(name==='fn_connect_checkout_lier'){writes.push('rpc:bind');capacity.session_id=args.p_session_id;capacity.trace_id=T;return {data:{bound:true,operation_id:O,session_id:SESSION},error:null};}
  if(name==='fn_connect_checkout_verifier')return {data:{admitted:!settings.admissionError,operation_id:O,session_id:SESSION},error:null};
  return forbid(`rpc:${name}`);
 }};
 class StripeTest{
  accounts={retrieve:async(accountId?:string)=>{calls.push(`stripe:account:${accountId??'self'}`);return structuredClone(accountId?provider.destination:{id:provider.platformId});}};
  balance={retrieve:async()=>{calls.push('stripe:balance');return {livemode:provider.livemode};}};
  customers={retrieve:async()=>{calls.push('stripe:customer');return structuredClone(provider.customer);},create:()=>forbid('customer:create'),update:()=>forbid('customer:update')};
  checkout={sessions:{list:async(params:Row)=>{calls.push('stripe:sessions:list');const rows=provider.sessions.filter((r:Row)=>!params.status||r.status===params.status);const start=params.starting_after?rows.findIndex((r:Row)=>r.id===params.starting_after)+1:0;return {data:structuredClone(rows.slice(start,start+100)),has_more:rows.length>start+100};},
   retrieve:async(sid:string)=>{calls.push('stripe:session:retrieve');expect(sid).toBe(SESSION);return structuredClone(session);},
   create:async(body:Row,options:Row)=>{writes.push('stripe:checkout:create');expect(options.idempotencyKey).toBe(`connect_checkout_${H}`);expect(body.metadata).toEqual(metadata);expect(body.return_url).toContain(config.returnOrigin);provider.sessions.push(structuredClone(session));return structuredClone(session);},
   expire:()=>forbid('session:expire')}};
  transfers={create:()=>forbid('transfer:create'),retrieve:()=>forbid('transfer:retrieve')};
  refunds={create:()=>forbid('refund:create')};paymentIntents={retrieve:()=>forbid('pi:retrieve')};
 }
 const env:Row={SUPABASE_URL:'https://mejpriaetwgtcstbgfid.supabase.co',SUPABASE_ENV:'staging',SUPABASE_ANON_KEY:'synthetic',SUPABASE_SERVICE_ROLE_KEY:'synthetic',STRIPE_SECRET_KEY:'sk_test_SyntheticOnly',CONNECT_STAGING_TEST_RUN:JSON.stringify(config)};
 let handler:((r:Request)=>Promise<Response>)|undefined;const cache=new Map<string,Row>();
 const load=(file:string):Row=>{file=resolve(file);if(cache.has(file))return cache.get(file)!;const exports:Row={};cache.set(file,exports);
  if(!transpiled.has(file))transpiled.set(file,ts.transpileModule(readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText);
  runInNewContext(transpiled.get(file)!,{exports,Request,Response,URL,URLSearchParams,Date,Error,Map,Set,structuredClone,
   require:(name:string)=>name==='npm:stripe@20.4.1'?{default:StripeTest}:name==='npm:@supabase/supabase-js@2'?{createClient:()=>sb}:
    name.endsWith('/admin-auth.ts')?{verifyUserOrServiceRole:async()=>({ok:true,isServiceRole:false,userId:settings.userId})}:
    name.endsWith('/test-account.ts')?{resolveOperationalTestAccount:async()=>({ok:true,isTest:settings.bothTest})}:
    name.startsWith('.')?load(resolve(dirname(file),name)):forbid(`import:${name}`),
   Deno:{env:{get:(name:string)=>env[name]},serve:(fn:any)=>{handler=fn;}},fetch:()=>forbid('fetch'),console:{log(){},warn(){},error(){},info(){}}});return exports;};
 load('supabase/functions/stripe-connect-pay-mission/index.ts');
 const historical=(status='ECHOUE',sid:string|null=null)=>({id:T,mission_id:M,etablissement_id:E,soignant_id:S,facture_id:C,facture_honoraire_id:H,stripe_checkout_session_id:sid,stripe_payment_intent_id:null,stripe_transfer_id:null,statut:status,cree_le:'2020-01-01T00:00:00Z'});
 const known=()=>{capacity.claim_reserved_at=new Date().toISOString();capacity.operation_id=O;capacity.session_id=SESSION;capacity.trace_id=T;db.stripe_transfers=[historical('EN_ATTENTE',SESSION)];provider.sessions=[structuredClone(session)];db.stripe_payment_flow_claims=[{resource_key:`FACTURE:${C}`,flow:'CONNECT_INVOICE',owner_token:`connect-invoice:${H}`,stripe_checkout_session_id:SESSION,stripe_payment_intent_id:null}];};
 return {capacity,db,provider,session,settings,env,writes,calls,unexpected,historical,known,run:()=>handler!(new Request('https://simulation.invalid/pay',{method:'POST',headers:{Authorization:'Bearer synthetic'},body:JSON.stringify({mission_id:M,facture_honoraire_id:H})}))};
}

describe('Connect staging : handler configuré, transports simulés sans fournisseur',()=>{
 it('première capacité fraîche crée exactement un Checkout et lie sa nouvelle trace',async()=>{
  const s=simulate();const response=await s.run();expect(response.status).toBe(200);expect(await response.json()).toMatchObject({success:true,checkout_session_id:SESSION,client_secret:'test_client_secret'});
  expect(s.writes).toEqual(['rpc:claim','rpc:reserve','stripe:checkout:create','update:stripe_payment_flow_claims','insert:stripe_transfers','rpc:bind','update:missions']);
  expect(s.calls).toContain('stripe:account:acct_RecipientTEST');expect(s.unexpected).toEqual([]);expect(s.db.stripe_transfers).toHaveLength(1);
 });
 it.each(['ECHOUE','EN_ATTENTE','REMBOURSE','ANNULEE'])('trace historique %s avec Session NULL refusée sans écrit',async status=>{
  const s=simulate();s.db.stripe_transfers=[s.historical(status)];const before=structuredClone(s.db);expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.db).toEqual(before);expect(s.unexpected).toEqual([]);expect(s.calls).not.toContain('stripe:account:self');
 });
 it.each(['open','expired','complete'])('Session historique %s sans trace SQL refusée avant claim/expiration',async status=>{
  const s=simulate();s.provider.sessions=[{...structuredClone(s.session),id:'cs_test_Historical',status}];expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it('Session historique sur deuxième page refuse aussi sans mutation',async()=>{
  const s=simulate();s.provider.sessions=[...Array.from({length:100},(_,n)=>({id:`cs_test_Unrelated${n}`,metadata:{},status:'expired'})),{...s.session,id:'cs_test_Historical',status:'expired'}];expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it('claim historique même owner et Session NULL refusé avant acquisition',async()=>{
  const s=simulate();s.db.stripe_payment_flow_claims=[{resource_key:`FACTURE:${C}`,flow:'CONNECT_INVOICE',owner_token:`connect-invoice:${H}`,stripe_checkout_session_id:null,stripe_payment_intent_id:null}];expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.calls).not.toContain('rpc:fn_stripe_payment_flow_claim_connect_test_v1');
 });
 it('reprise exacte de sa Session ouverte ancienne : lecture seule, pas de nettoyage 15 min',async()=>{
  const s=simulate();s.known();const before=structuredClone(s.db);const response=await s.run();expect(response.status).toBe(200);expect(await response.json()).toMatchObject({success:true,resumed:true,checkout_session_id:SESSION});expect(s.db).toEqual(before);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it.each(['expired','complete'])('Session exacte %s demande le rapprochement, sans réemploi',async status=>{
  const s=simulate();s.known();s.session.status=status;const response=await s.run();expect(response.status).toBe(409);expect((await response.json()).error).toBe('CONNECT_TEST_RECONCILIATION_REQUIRED');expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it.each(['trace','session','operation','transfer'])('liaison %s étrangère refuse sans mutation',async field=>{
  const s=simulate();s.known();if(field==='trace')s.db.stripe_transfers[0].id=id(99);if(field==='session')s.db.stripe_transfers[0].stripe_checkout_session_id='cs_test_Foreign';if(field==='operation')s.session.metadata.connect_operation_id=id(99);if(field==='transfer')s.db.stripe_transfers[0].stripe_transfer_id='tr_Historical';expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it.each(['owner','charges','payouts','details','capability','requirements','disabled','id'])('destination fournisseur %s invalide : refus avant claim',async key=>{
  const s=simulate(),d=s.provider.destination;if(key==='owner')d.metadata.soignant_id=id(99);if(key==='charges')d.charges_enabled=false;if(key==='payouts')d.payouts_enabled=false;if(key==='details')d.details_submitted=false;if(key==='capability')d.capabilities.transfers='inactive';if(key==='requirements')d.requirements.currently_due=['document'];if(key==='disabled')d.requirements.disabled_reason='rejected';if(key==='id')d.id='acct_Foreign';expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it('commission absente refusée sans préparation implicite de facture',async()=>{const s=simulate();s.db.factures=[];expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);});
 it.each(['claim-response','reserve'])('timeout %s : reprise du claim propre sans adoption historique',async kind=>{
  const s=simulate();s.settings.claimResponseLost=kind==='claim-response';s.settings.reserveError=kind==='reserve';expect((await s.run()).status).toBe(500);
  expect(s.capacity.operation_id).toBeNull();expect(s.capacity.claim_reserved_at).toEqual(expect.any(String));expect(s.db.stripe_payment_flow_claims).toHaveLength(1);
  s.settings.claimResponseLost=false;s.settings.reserveError=false;expect((await s.run()).status).toBe(200);expect(s.writes.filter(x=>x==='stripe:checkout:create')).toHaveLength(1);expect(s.unexpected).toEqual([]);
 });
 it.each(['same-fh','commission-only','foreign-mission'])('ancienne trace masquée %s refusée sans écrit',async kind=>{
  const s=simulate();s.known();const other={...s.historical('ECHOUE'),id:id(99)};if(kind==='commission-only')other.facture_honoraire_id=null as any;if(kind==='foreign-mission')other.mission_id=id(98);s.db.stripe_transfers.push(other);
  expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it.each(['absent','owner','session','intent'])('reprise exacte sans claim exact %s refuse le client_secret',async key=>{
  const s=simulate();s.known();if(key==='absent')s.db.stripe_payment_flow_claims=[];if(key==='owner')s.db.stripe_payment_flow_claims[0].owner_token='foreign';if(key==='session')s.db.stripe_payment_flow_claims[0].stripe_checkout_session_id='cs_test_Foreign';if(key==='intent')s.db.stripe_payment_flow_claims[0].stripe_payment_intent_id='pi_Foreign';
  const response=await s.run();expect(response.status).toBe(500);expect((await response.json()).client_secret).toBeUndefined();expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);
 });
 it('autorisation révoquée après réservation refuse le POST Stripe',async()=>{const s=simulate();s.settings.authorizationError=true;expect((await s.run()).status).toBe(500);expect(s.writes).toEqual(['rpc:claim','rpc:reserve']);expect(s.unexpected).toEqual([]);});
 it('claim concurrent refusé par SQL sans Checkout',async()=>{const s=simulate();s.settings.claimError=true;expect((await s.run()).status).toBe(500);expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);});
 it('admission SQL de Session refusée avant restitution du client_secret',async()=>{const s=simulate();s.known();s.settings.admissionError=true;const response=await s.run();expect(response.status).toBe(500);expect((await response.json()).client_secret).toBeUndefined();expect(s.writes).toEqual([]);expect(s.unexpected).toEqual([]);});
});

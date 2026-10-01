import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

// Handler complet et parseur produit réels. Auth/DB sont des transports en
// mémoire ; aucune qualification de compte réel ni requête Stripe n'est créée.
type Row = Record<string, any>;
const id=(n:number)=>`f1570000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [M,E,S,H,C,T,O,L]=Array.from({length:8},(_,n)=>id(n+1));
function simulation(status:string, activeDispute=false, denied=false, gateClosed: false | 'CONNECT_RELEASE_CLOSED' | 'CONNECT_CLIENT_VERSION_REQUIRED'=false) {
  const calls:string[]=[],unexpected:string[]=[];
  const op:Row={id:O,trace_id:T,mission_id:M,etablissement_id:E,soignant_id:S,facture_honoraire_id:H,
    facture_commission_id:C,litige_id:L,session_id:'cs_f157',payment_intent_id:'pi_f157',charge_id:'ch_f157',
    customer_id:'cus_f157',destination_id:'acct_f157',soignant_cents:8000,commission_cents:1440,total_cents:9440,
    livemode:false,orientation:'REFUND',refund_id:status==='READY'?null:'re_f157',refund_status:status};
  const db:Record<string,Row[]>={
    missions:[{id:M,etablissement_id:E,soignant_assigne_id:S,statut:'EN_COURS',strategie_facturation:'HEBDO_ET_FINALE',type_contrat_applique:'LIBERAL'}],
    factures_honoraires:[{id:H,mission_id:M,etablissement_id:E,soignant_id:S,statut:'EMISE',montant_ttc:80,periode_fin:'2020-01-05',est_facture_finale_mission:false}],
    etablissements:[{id:E,stripe_customer_id:'cus_f157',nom:'Fixture',email_contact:'fixture@example.invalid'}],soignants:[{id:S,type_exercice:'LIBERAL'}],
    stripe_transfers:[{id:T,mission_id:M,etablissement_id:E,soignant_id:S,facture_honoraire_id:H,
      stripe_checkout_session_id:'cs_f157',stripe_transfer_id:null,statut:status==='SUCCEEDED'?'REMBOURSE':status==='READY'||status==='PENDING'||status==='REQUIRES_ACTION'?'EN_ATTENTE':'ECHOUE'}],
    factures:[{id:C,facture_honoraire_id:H,mission_id:M,etablissement_id:E,type_document:'FACTURE',statut:'EMISE',montant_ttc:14.4}],
    stripe_connect_onboarding:[{soignant_id:S,stripe_account_id:'acct_f157',statut:'COMPLET'}],
    paiements_mission:[],litiges:[{id:L,mission_id:M,facture_id:H,statut:activeDispute?'OUVERT':'RESOLU'}],
  };
  if(gateClosed)db.stripe_transfers=[];
  const forbid=(name:string):never=>{unexpected.push(name);throw new Error(`IO_SIMULEE_REFUSEE:${name}`);};
  const sb={from(table:string){
    calls.push(`table:${table}`);if(!db[table])return forbid(`table:${table}`);
    const filters:((r:Row)=>boolean)[]=[];
    const q={select(){return q;},eq(k:string,v:unknown){filters.push(r=>r[k]===v);return q;},
      neq(k:string,v:unknown){filters.push(r=>r[k]!==v);return q;},
      in(k:string,v:unknown[]){filters.push(r=>v.includes(r[k]));return q;},
      or(){filters.push(r=>r.facture_id===H||r.facture_id===null);return q;},order(){return q;},limit(){return q;},
      async maybeSingle(){return {data:structuredClone(db[table].find(r=>filters.every(f=>f(r)))||null),error:null};},
      async single(){return q.maybeSingle();}};return q;
  },async rpc(name:string,args:Row){calls.push(`rpc:${name}`);
    if(name==='fn_a_permission_etablissement')return {data:!denied,error:null};
    if(name==='fn_stripe_payment_flow_claim_connect_v1' && gateClosed)return {data:null,error:{message:gateClosed}};
    if(name==='fn_connect_avant_transfert_lire'){
      expect(args).toEqual({p_session_id:'cs_f157'});return {data:structuredClone(op),error:null};
    }return forbid(`rpc:${name}`);
  }};
  class StripeClosed {
    constructor(){if(!gateClosed)forbid('Stripe');}
    customers={retrieve:async()=>{calls.push('Stripe:customer.retrieve');return {id:'cus_f157',name:'Fixture',email:'fixture@example.invalid',metadata:{etablissement_id:E}};},
      create:()=>forbid('Stripe:customer.create'),update:()=>forbid('Stripe:customer.update')};
    checkout={sessions:{list:async()=>{calls.push('Stripe:sessions.list');return {data:[],has_more:false};},create:()=>forbid('Stripe:checkout.create')}};
    transfers={create:()=>forbid('Stripe:transfer.create')};refunds={create:()=>forbid('Stripe:refund.create')};
  }
  let handler:((request:Request)=>Promise<Response>)|undefined;
  const cache=new Map<string,Row>();
  function load(file:string):Row {
    file=resolve(file);if(cache.has(file))return cache.get(file)!;
    const exports:Row={};cache.set(file,exports);
    const code=ts.transpileModule(readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
    runInNewContext(code,{exports,Request,Response,URL,URLSearchParams,Date,Error,Map,Set,structuredClone,
      require:(name:string)=>{
        if(name==='npm:stripe@20.4.1')return {default:StripeClosed};
        if(name==='npm:@supabase/supabase-js@2')return {createClient:()=>sb};
        if(name.endsWith('/admin-auth.ts'))return {verifyUserOrServiceRole:async()=>({ok:true,isServiceRole:false,userId:E})};
        if(name.endsWith('/test-account.ts'))return {resolveOperationalTestAccount:async()=>({ok:true,isTest:false})};
        if(name.startsWith('.'))return load(resolve(dirname(file),name));
        return forbid(`import:${name}`);
      },Deno:{env:{get:(name:string)=>({
        SUPABASE_URL:'https://simulation.invalid',
        SUPABASE_ANON_KEY:'simulation',
        SUPABASE_SERVICE_ROLE_KEY:'simulation',
        STRIPE_SECRET_KEY:'simulation',
      } as Record<string,string>)[name]},serve:(fn:any)=>{handler=fn;}},
      fetch:()=>forbid('fetch'),console:{log(){},info(){},warn(){},error(){}}});return exports;
  }
  load('supabase/functions/stripe-connect-pay-mission/index.ts');
  return {op,db,calls,unexpected,run:()=>handler!(new Request('https://simulation.invalid/pay',{
    method:'POST',headers:{Authorization:'Bearer simulation'},body:JSON.stringify({mission_id:M,facture_honoraire_id:H})}))};
}

describe('Payer à nouveau après orientation REFUND : handler réel, zéro fournisseur',()=>{
  it.each(['READY','PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED','REVIEW'])('%s + litige clôturé refuse une nouvelle tentative sur la même pièce',async status=>{
    const s=simulation(status);const before=structuredClone(s.db);const response=await s.run();const body=await response.json();
    expect(response.status).toBe(409);expect(body.error).toBe('CONNECT_REFUND_RECONCILIATION_REQUIRED');
    expect(body.message).toBe('Un remboursement est lié à cette tentative de paiement. Son rapprochement doit être terminé avant tout nouveau règlement de cette facture.');
    expect(body.client_secret).toBeUndefined();expect(body.already_paid).toBeUndefined();
    expect(s.unexpected).toEqual([]);expect(s.db).toEqual(before);
    expect(s.calls).not.toContain('table:factures');
  });
  it('litige encore ouvert : refus existant avant toute nouvelle lecture d’opération',async()=>{
    const s=simulation('SUCCEEDED',true);const response=await s.run();
    expect(response.status).toBe(409);expect((await response.json()).error).toBe('FACTURE_EN_LITIGE');
    expect(s.calls).not.toContain('rpc:fn_connect_avant_transfert_lire');expect(s.unexpected).toEqual([]);
  });
  it('acteur sans droit paiement : ne lit pas l’opération privée',async()=>{
    const s=simulation('SUCCEEDED',false,true);expect((await s.run()).status).toBe(403);
    expect(s.calls).not.toContain('rpc:fn_connect_avant_transfert_lire');expect(s.unexpected).toEqual([]);
  });
  it.each(['CONNECT_RELEASE_CLOSED','CONNECT_CLIENT_VERSION_REQUIRED'] as const)('%s : refus lisible du vrai handler, sans mouvement',async code=>{
    const s=simulation('READY',false,false,code);const before=structuredClone(s.db);const response=await s.run();const body=await response.json();
    expect(response.status).toBe(503);expect(body.error).toBe(code);
    expect(body.message).toBe(code==='CONNECT_RELEASE_CLOSED'
      ? 'Le paiement de cette facture est temporairement indisponible pendant une mise à jour. Réessayez plus tard depuis Facturation.'
      : 'Cette version du paiement est indisponible. Rechargez Facturation avant de réessayer.');
    expect(body.client_secret).toBeUndefined();expect(body.already_paid).toBeUndefined();
    expect(s.calls).toContain('rpc:fn_stripe_payment_flow_claim_connect_v1');
    expect(s.calls).not.toContain('rpc:fn_stripe_payment_flow_claim');
    expect(s.unexpected).toEqual([]);expect(s.db).toEqual(before);
  });
  it('opération d’une autre pièce refusée, sans mutation ni exposition de son contenu',async()=>{
    const s=simulation('SUCCEEDED');s.op.facture_honoraire_id=id(99);const response=await s.run();const body=await response.json();
    expect(response.status).toBe(500);expect(body.client_secret).toBeUndefined();
    expect(JSON.stringify(body)).not.toContain(id(99));expect(s.unexpected).toEqual([]);
  });
});

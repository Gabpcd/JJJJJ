import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

// Handler et helpers réels ; SDK Stripe/Supabase exclusivement en mémoire.
// Aucun appel HTTP, objet fournisseur ou secret réel. Les flags non-TEST de ces
// objets fictifs servent uniquement à exercer la branche de rapprochement.
type Row = Record<string, any>;
const M='f1540000-0000-4000-8000-000000000001';
const S='f1540000-0000-4000-8000-000000000002';
const E='f1540000-0000-4000-8000-000000000003';
const H='f1540000-0000-4000-8000-000000000004';
const F='f1540000-0000-4000-8000-000000000005';
const H2='f1540000-0000-4000-8000-000000000006';
const O='f1540000-0000-4000-8000-000000000008';
const T='f1540000-0000-4000-8000-000000000009';
function simulation(options: { fk?: string | null; pi?: string | null; charge?: string | null;
  missing?: boolean; race?: string; pending?: boolean; invoice?: boolean; expiration?: 'INVOICE' | 'MISSION' }={}) {
  const metadata={type:'CONNECT_MISSION_PAYMENT',mission_id:M,soignant_id:S,etablissement_id:E,
    connected_account_id:'acct_f154',soignant_cents:'8000',commission_cents:'1440',
    connect_operation_id:O,facture_honoraires_id:H,facture_commission_id:F,payment_scope:options.expiration || (options.invoice?'INVOICE':'MISSION')};
  const session={id:'cs_f154',payment_intent:'pi_f154',customer:'cus_f154',client_reference_id:M,
    status:'complete',payment_method_types:['card'],livemode:false,payment_status:'paid',amount_total:9440,currency:'eur',metadata};
  const state={unknown:[] as string[],writes:[] as Row[],create:0,retrieve:0,processed:false,
    logs:[] as string[],raced:false};
  const st={id:T,mission_id:M,soignant_id:S,etablissement_id:E,facture_id:F,
    facture_honoraire_id:options.fk===undefined?null:options.fk,
    stripe_payment_intent_id:options.pi===undefined?null:options.pi,
    stripe_charge_id:options.charge===undefined?null:options.charge,
    statut:options.pending?'EN_ATTENTE':'TRANSFERE',stripe_transfer_id:options.pending?null:'tr_f154',
    stripe_checkout_session_id:'cs_f154',montant_soignant:80,montant_commission:14.4,montant_total:94.4};
  const db:Record<string,Row[]>={
    missions:[{id:M,etablissement_id:E,soignant_assigne_id:S,statut:'TERMINEE',type_contrat_applique:'LIBERAL',
      net_a_payer:80,montant_commission_ttc:14.4,commission_facturee:true,intitule:'Mission fictive'}],
    etablissements:[{id:E,stripe_customer_id:'cus_f154',est_compte_test:false}],
    soignants:[{id:S,est_compte_test:false}],
    stripe_connect_onboarding:[{soignant_id:S,stripe_account_id:'acct_f154',statut:'COMPLET'}],
    stripe_transfers:options.missing?[]:[st],
    factures_honoraires:[{id:H,mission_id:M,soignant_id:S,etablissement_id:E,montant_ttc:80,statut:'PAYEE',
      stripe_payment_intent_id:'pi_f154',periode_debut:'2026-09-01',periode_fin:'2026-09-07',est_facture_finale_mission:true},
      {id:H2,mission_id:M,soignant_id:S,etablissement_id:E,montant_ttc:60,statut:'PAYEE',
        stripe_payment_intent_id:'pi_f154_autre',periode_debut:'2026-08-01',periode_fin:'2026-08-07',est_facture_finale_mission:false}],
    factures:[{id:F,mission_id:M,etablissement_id:E,facture_honoraire_id:H,type_document:'FACTURE',statut:'PAYEE',
      montant_ht:12,montant_tva:2.4,montant_ttc:14.4,stripe_payment_intent_id:'pi_f154'}],
    paiements_soignant:[],paiements_escrow:[],paiements_mission:[],litiges:[],
    stripe_webhook_events:[{event_id:'evt_f154',traite_le:null}],
    stripe_payment_flow_claims:[{resource_key:options.expiration==='INVOICE'?`FACTURE:${F}`:`MISSION:${M}`,
      flow:options.expiration==='INVOICE'?'CONNECT_INVOICE':'CONNECT_MISSION',stripe_checkout_session_id:'cs_f154'}],
  };
  const forbidden=(name:string):never=>{state.unknown.push(name);throw new Error(`IO imprévue ${name}`);};
  const sb={from(table:string) {
    if(!db[table]) return forbidden(`table ${table}`);
    let patch:Row|undefined,insert:Row|undefined,remove=false;
    const filters:((r:Row)=>boolean)[]=[];
    const result=()=>{
      if(table==='stripe_transfers' && patch?.facture_honoraire_id && options.race && !state.raced) {
        st[options.race]=options.race==='facture_honoraire_id'?F:'contradictoire';state.raced=true;
      }
      let rows=db[table].filter(r=>filters.every(f=>f(r)));
      if(insert) {
        if(table!=='paiements_soignant') return forbidden(`insert ${table}`);
        if(st.facture_honoraire_id!==H || st.stripe_payment_intent_id!=='pi_f154' || st.stripe_charge_id!=='ch_f154') {
          return {data:null,error:{message:'PREUVE_STRIPE_REQUISE'}};
        }
        db[table].push({...insert,id:'paiement'});rows=[db[table].at(-1)!];
        state.writes.push({table,operation:'insert',patch:insert});
      }
      if(patch) {
        if(!['stripe_transfers','missions','factures_honoraires','factures','stripe_webhook_events'].includes(table)) return forbidden(`update ${table}`);
        state.writes.push({table,operation:'update',patch,matched:rows.length});
        rows.forEach(r=>Object.assign(r,patch));
        if(table==='stripe_webhook_events' && patch.traite_le && rows.length)state.processed=true;
      }
      if(remove) {
        if(table!=='stripe_payment_flow_claims')return forbidden(`delete ${table}`);
        db[table]=db[table].filter(r=>!rows.includes(r));
        state.writes.push({table,operation:'delete',matched:rows.length});
      }
      return {data:rows,error:null};
    };
    const single=()=>{const r=result();return {...r,data:r.data?.[0]?structuredClone(r.data[0]):null};};
    const q={select(){return q;},update(p:Row){patch=p;return q;},insert(p:Row){insert=p;return q;},delete(){remove=true;return q;},
      eq(k:string,v:unknown){filters.push(r=>r[k]===v);return q;},neq(k:string,v:unknown){filters.push(r=>r[k]!==v);return q;},
      is(k:string,v:unknown){filters.push(r=>r[k]===v);return q;},in(k:string,v:unknown[]){filters.push(r=>v.includes(r[k]));return q;},
      or(expr:string){const alternatives=expr.split(',').map(x=>{const [k,op,...rest]=x.split('.');const val=rest.join('.');
        if(!['eq','is'].includes(op))return forbidden(`filtre ${expr}`);return (r:Row)=>r[k]===(val==='null'?null:val);});
        filters.push(r=>alternatives.some(f=>f(r)));return q;},
      limit(n:number){if(n!==1)return forbidden(`limit ${n}`);return q;},
      maybeSingle:async()=>single(),single:async()=>single(),
      then(ok:any,bad:any){return Promise.resolve(result()).then(ok,bad);}};
    return q;
  },rpc:async(name:string,args:Row)=>{
    if(name.startsWith('fn_stripe_webhook_event_claim')){
      expect(name).toBe(options.expiration?'fn_stripe_webhook_event_claim':'fn_stripe_webhook_event_claim_connect_v1');
      return {data:state.processed?'PROCESSED':'CLAIMED',error:null};
    }
    if(name==='fn_connect_avant_transfert_lire')return {data:null,error:null};
    if(name==='fn_connect_avant_transfert_arbitrer') {
      expect(args.p_trace_id).toBe(T);expect(args.p_operation_id).toBe(O);
      return {data:{...args.p_source,id:O,trace_id:T,orientation:'TRANSFER',litige_id:null,refund_id:null,refund_status:'READY'},error:null};
    }
    if(name==='fn_ecrire_audit_safe'){state.writes.push({table:'audit',args});return {data:{success:true},error:null};}
    return forbidden(`rpc ${name}`);
  }};
  const intent={id:'pi_f154',status:'succeeded',payment_method_types:['card'],amount_capturable:0,livemode:false,amount:9440,amount_received:9440,currency:'eur',customer:'cus_f154',latest_charge:'ch_f154',metadata};
  const transfer={id:'tr_f154',amount:8000,currency:'eur',destination:'acct_f154',source_transaction:'ch_f154',metadata:{mission_id:M,soignant_id:S}};
  class StripeStub {
    checkout={sessions:{retrieve:async(id:string)=>id===session.id?session:forbidden(`session ${id}`)}};
    webhooks={constructEventAsync:async()=>({id:'evt_f154',type:options.expiration?'checkout.session.expired':'checkout.session.completed',
      livemode:false,data:{object:session}})};
    paymentIntents={retrieve:async(id:string)=>id==='pi_f154'?intent:forbidden(`PI ${id}`)};
    customers={retrieve:async(id:string)=>id==='cus_f154'?{id,metadata:{etablissement_id:E}}:forbidden(`customer ${id}`)};
    charges={retrieve:async(id:string)=>id==='ch_f154'?{id,payment_method_details:{type:'card'},livemode:false,captured:true,created:1790000000,refunded:false,amount_refunded:0,disputed:false,paid:true,status:'succeeded',
      amount:9440,currency:'eur',customer:'cus_f154',payment_intent:'pi_f154'}:forbidden(`charge ${id}`)};
    transfers={retrieve:async(id:string)=>{state.retrieve++;return id==='tr_f154'?transfer:forbidden(`transfer ${id}`);},
      create:async()=>{state.create++;if(!options.pending)return forbidden('second transfert');return transfer;}};
  }
  const env:Row={SUPABASE_URL:'https://simulation.invalid',SUPABASE_SERVICE_ROLE_KEY:'simulation',
    STRIPE_SECRET_KEY:'sk_test_simulation',STRIPE_WEBHOOK_SECRET:'whsec_simulation'};
  const cache=new Map<string,Row>();
  function load(file:string):Row {
    file=resolve(file);if(cache.has(file))return cache.get(file)!;
    const exports:Row={};cache.set(file,exports);
    const js=ts.transpileModule(readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
    runInNewContext(js,{exports,Request,Response,URL,Date,Error,Set,Map,structuredClone,crypto:globalThis.crypto,
      require:(name:string)=>{
        if(name==='npm:stripe@20.4.1')return {default:StripeStub};
        if(name==='npm:@supabase/supabase-js@2')return {createClient:()=>sb};
        if(name.startsWith('./'))return load(resolve(dirname(file),name));
        return forbidden(`import ${name}`);
      },Deno:{env:{get:(key:string)=>env[key]}},fetch:()=>forbidden('fetch'),
      console:{log(){},info(){},warn(...x:any[]){state.logs.push(x.join(' '));},error(...x:any[]){state.logs.push(x.join(' '));}}});
    return exports;
  }
  const handler=load('supabase/functions/_shared/stripe-webhook-handler.ts').handleStripeWebhook;
  return {state,db,run:()=>handler(new Request('https://simulation.invalid/webhook',
    {method:'POST',headers:{'stripe-signature':'simulation'},body:'{}'}),'PLATFORM') as Promise<Response>};
}

describe('Webhook réel : pièce explicite et reprise sans second transfert',()=>{
  it.each([
    {fk:null,pi:null,charge:null},{fk:H,pi:null,charge:null},
    {fk:null,pi:'pi_f154',charge:'ch_f154'},{fk:H,pi:'pi_f154',charge:'ch_f154'},
    {fk:H,pi:'pi_f154',charge:null},{fk:H,pi:null,charge:'ch_f154'},
    {fk:H,pi:null,charge:null,invoice:true},
  ])('reprend les champs manquants avec les objets vérifiés %j',async values=>{
    const s=simulation(values);const other=structuredClone(s.db.factures_honoraires.find(h=>h.id===H2));const r=await s.run();
    expect(s.state.unknown).toEqual([]);expect(r.status,s.state.logs.join('\n')).toBe(200);expect(await r.json()).toMatchObject({received:true});
    expect(s.state.create).toBe(0);expect(s.state.retrieve).toBe(1);expect(s.state.processed).toBe(true);
    expect(s.db.stripe_transfers[0]).toMatchObject({facture_honoraire_id:H,stripe_payment_intent_id:'pi_f154',stripe_charge_id:'ch_f154'});
    const missingFields=Object.entries({facture_honoraire_id:values.fk,stripe_payment_intent_id:values.pi,
      stripe_charge_id:values.charge}).filter(([,value])=>value===null).map(([key])=>key).sort();
    const patches=s.state.writes.filter(w=>w.table==='stripe_transfers' && w.operation==='update');
    expect(patches.map(w=>Object.keys(w.patch).sort())).toEqual(missingFields.length?[missingFields]:[]);
    expect(s.db.factures_honoraires.find(h=>h.id===H2)).toEqual(other);
    expect(s.db.paiements_soignant).toHaveLength(1);expect(s.db.paiements_soignant[0]).toMatchObject({facture_honoraire_id:H,montant_net:80});
    await s.run();expect(s.db.paiements_soignant).toHaveLength(1);expect(s.state.create).toBe(0);
  });
  it.each([{pi:'pi_autre'},{charge:'ch_autre'},{fk:F},{missing:true}])('refuse une trace absente/contradictoire avant transfert %j',async values=>{
    const s=simulation(values);const r=await s.run();expect(s.state.unknown).toEqual([]);expect(r.status).toBe(500);
    expect(s.state.create).toBe(0);expect(s.state.retrieve).toBe(0);expect(s.db.paiements_soignant).toHaveLength(0);
    expect(s.state.processed).toBe(false);
    expect(s.state.writes.some(w=>w.table==='audit' && w.args.p_details.evenement==='CONNECT_PAIEMENT_IDENTITE_INCOHERENTE')).toBe(true);
  });
  it.each(['facture_honoraire_id','stripe_payment_intent_id','stripe_charge_id'])('perte CAS %s : pas de paiement ni faux acquittement',async race=>{
    const s=simulation({race});const r=await s.run();expect(s.state.unknown).toEqual([]);expect(r.status).toBe(500);
    expect(s.db.paiements_soignant).toHaveLength(0);expect(s.state.processed).toBe(false);expect(s.state.create).toBe(0);
    expect(s.state.logs.join('\n')).toContain('Post-transfer reconciliation failed');
  });
  it('premier rapprochement fictif : persiste la preuve exacte avant le paiement',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H});const r=await s.run();
    expect(s.state.unknown).toEqual([]);expect(r.status,s.state.logs.join('\n')).toBe(200);
    expect(s.state.create).toBe(1);expect(s.state.processed).toBe(true);
    expect(s.db.paiements_soignant).toHaveLength(1);
    expect(s.db.stripe_transfers[0]).toMatchObject({facture_honoraire_id:H,stripe_payment_intent_id:'pi_f154',stripe_charge_id:'ch_f154'});
    await s.run();expect(s.state.create).toBe(1);expect(s.db.paiements_soignant).toHaveLength(1);
  });
  it('borne aussi la première persistance après un nouveau transfert fictif',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H,race:'facture_honoraire_id'});const r=await s.run();
    expect(s.state.unknown).toEqual([]);expect(r.status).toBe(500);expect(s.state.create).toBe(1);
    expect(s.db.paiements_soignant).toHaveLength(0);expect(s.state.processed).toBe(false);
    expect(s.db.stripe_transfers[0].facture_honoraire_id).toBe(F);
  });
  it('ancien Checkout mission sans admission : aucun nouveau transfert ni paiement',async()=>{
    const s=simulation({pending:true});const r=await s.run();
    expect(s.state.unknown).toEqual([]);expect(r.status).toBe(500);expect(s.state.create).toBe(0);
    expect(s.db.paiements_soignant).toHaveLength(0);expect(s.state.processed).toBe(false);
  });
  it.each(['INVOICE','MISSION'] as const)('expiration vérifiée : libère seulement le claim %s de cette Session',async expiration=>{
    const s=simulation({expiration,pending:true});s.db.stripe_payment_flow_claims.push({resource_key:'autre',flow:expiration==='INVOICE'?'CONNECT_INVOICE':'CONNECT_MISSION',stripe_checkout_session_id:'cs_autre'});
    const r=await s.run();expect(s.state.unknown).toEqual([]);expect(r.status).toBe(200);
    expect(s.db.stripe_payment_flow_claims).toHaveLength(1);expect(s.db.stripe_payment_flow_claims[0].stripe_checkout_session_id).toBe('cs_autre');
    expect(s.db.stripe_transfers[0].statut).toBe('ECHOUE');expect(s.state.create).toBe(0);
  });
});

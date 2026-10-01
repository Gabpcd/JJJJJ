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
  missing?: boolean; race?: string; pending?: boolean; invoice?: boolean; expiration?: 'INVOICE' | 'MISSION'; refundStatus?: string; refundSqlError?: boolean }={}) {
  const metadata={type:'CONNECT_MISSION_PAYMENT',mission_id:M,soignant_id:S,etablissement_id:E,
    connected_account_id:'acct_f154',soignant_cents:'8000',commission_cents:'1440',
    connect_operation_id:O,facture_honoraires_id:H,facture_commission_id:F,payment_scope:options.expiration || (options.invoice?'INVOICE':'MISSION')};
  const session={id:'cs_f154',payment_intent:'pi_f154',customer:'cus_f154',client_reference_id:M,
    status:'complete',payment_method_types:['card'],livemode:false,payment_status:'paid',amount_total:9440,currency:'eur',metadata};
  const state={unknown:[] as string[],writes:[] as Row[],create:0,retrieve:0,processed:false,
    logs:[] as string[],raced:false,claimClosed:false,refundCreates:[] as Row[],timeoutAfterCreate:false,refundSqlError:!!options.refundSqlError};
  let eventId='evt_f154',eventType=options.expiration?'checkout.session.expired':'checkout.session.completed';
  let eventObject:Row=session;
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
  db.litiges.push({id:'f1540000-0000-4000-8000-000000000007',mission_id:M,facture_id:H,statut:'OUVERT'});
  for(const table of ['factures_honoraires','factures']) for(const row of db[table]) {
    if(row.id===H || row.id===F) {row.statut='EMISE';row.stripe_payment_intent_id=null;}
  }
  let operation:Row|null=null;
  let refund:Row|null=null;
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
        if(table==='stripe_transfers' && patch.statut==='REMBOURSE' && options.refundSqlError) {
          state.writes.push({table,operation:'update-refused',patch});
          return {data:null,error:{message:'SQL_UPDATE_SIMULE_REFUSE'}};
        }
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
      expect(name).toBe(eventType==='checkout.session.completed'?'fn_stripe_webhook_event_claim_connect_v1':'fn_stripe_webhook_event_claim');
      if(state.claimClosed && name==='fn_stripe_webhook_event_claim_connect_v1')return {data:null,error:{message:'CONNECT_RELEASE_CLOSED'}};
      return {data:state.processed?'PROCESSED':'CLAIMED',error:null};
    }
    if(name==='fn_connect_avant_transfert_lire')return {data:operation?structuredClone(operation):null,error:null};
    if(name==='fn_connect_avant_transfert_arbitrer') {
      expect(args.p_trace_id).toBe(T);expect(args.p_operation_id).toBe(O);
      operation={...args.p_source,id:O,trace_id:T,orientation:'REFUND',litige_id:db.litiges[0].id,
        refund_id:null,refund_status:'READY'};
      state.writes.push({table:'operation',operation:'arbitrer'});
      return {data:structuredClone(operation),error:null};
    }
    if(name==='fn_connect_remboursement_prendre')return {data:{acquired:true,owner_token:args.p_owner_token,can_create:true,operation:structuredClone(operation)},error:null};
    if(name==='fn_connect_remboursement_demarrer') {
      state.writes.push({table:'operation',operation:'demarrer'});
      return {data:{operation_id:O,owner_token:args.p_owner_token,create_allowed:true},error:null};
    }
    if(name==='fn_connect_remboursement_constater') {
      if(state.refundSqlError)return {data:null,error:{message:'SQL_UPDATE_SIMULE_REFUSE'}};
      const wasSucceeded=operation!.refund_status==='SUCCEEDED';
      operation!.refund_id=args.p_refund.id;
      if(!(wasSucceeded && args.p_refund.status==='pending'))operation!.refund_status=args.p_refund.status.toUpperCase();
      if(args.p_refund.status==='succeeded' && !wasSucceeded) {
        st.statut='REMBOURSE';state.writes.push({table:'audit',args:{p_details:{evenement:'CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE'}}});
      }
      return {data:{operation_id:O,refund_id:operation!.refund_id,status:operation!.refund_status},error:null};
    }
    if(name==='fn_ecrire_audit_safe'){state.writes.push({table:'audit',args});return {data:{success:true},error:null};}
    return forbidden(`rpc ${name}`);
  }};
  const intent={id:'pi_f154',status:'succeeded',payment_method_types:['card'],livemode:false,amount_capturable:0,amount:9440,amount_received:9440,currency:'eur',customer:'cus_f154',latest_charge:'ch_f154',metadata};
  const transfer={id:'tr_f154',amount:8000,currency:'eur',destination:'acct_f154',source_transaction:'ch_f154',metadata:{mission_id:M,soignant_id:S}};
  const charge={id:'ch_f154',payment_method_details:{type:'card'},livemode:false,captured:true,created:1790000000,refunded:false,amount_refunded:0,
    disputed:false,paid:true,status:'succeeded',amount:9440,currency:'eur',customer:'cus_f154',payment_intent:'pi_f154'};
  class StripeStub {
    checkout={sessions:{retrieve:async(id:string)=>id===session.id?session:forbidden(`session ${id}`)}};
    refunds={list:async()=>({data:refund?[refund]:[],has_more:false}),retrieve:async()=>refund,
      create:async(params:Row,request:Row)=>{state.refundCreates.push({params,request});
      refund={id:'re_f154',status:options.refundStatus || 'succeeded',amount:9440,currency:'eur',reason:'requested_by_customer',
        payment_intent:'pi_f154',charge:'ch_f154',metadata:params.metadata};
      if(refund.status==='succeeded'){charge.amount_refunded=9440;charge.refunded=true;}
      if(state.timeoutAfterCreate)throw new Error('REPONSE_STRIPE_PERDUE_SIMULEE');return refund;}};
    webhooks={constructEventAsync:async()=>({id:eventId,type:eventType,livemode:false,data:{object:eventObject}})};
    paymentIntents={retrieve:async(id:string)=>id==='pi_f154'?intent:forbidden(`PI ${id}`)};
    customers={retrieve:async(id:string)=>id==='cus_f154'?{id,metadata:{etablissement_id:E}}:forbidden(`customer ${id}`)};
    charges={retrieve:async(id:string)=>id==='ch_f154'?charge:forbidden(`charge ${id}`)};
    transfers={list:async()=>({data:[],has_more:false}),retrieve:async(id:string)=>{state.retrieve++;return id==='tr_f154'?transfer:forbidden(`transfer ${id}`);},
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
  return {state,db,changeRefundStatus(status:string){
    if(!refund)throw new Error('OBJET_REFUND_ABSENT');refund.status=status;
    charge.amount_refunded=status==='succeeded'?9440:0;charge.refunded=status==='succeeded';
  },nextEvent(type:string){
    state.processed=false;eventId+='x';eventType=type;
    eventObject=type.startsWith('refund.')?structuredClone(refund!):type==='charge.refunded'?structuredClone(charge):session;
    db.stripe_webhook_events.push({event_id:eventId,traite_le:null});
  },run:()=>handler(new Request('https://simulation.invalid/webhook',
    {method:'POST',headers:{'stripe-signature':'simulation'},body:'{}'}),'PLATFORM') as Promise<Response>};
}

describe('Remboursement Connect avant transfert : handler réel, fournisseurs en mémoire',()=>{
  it('protocole Connect fermé : webhook en échec retryable, aucun mouvement ni acquittement',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H});s.state.claimClosed=true;
    expect((await s.run()).status).toBe(500);expect(s.state.unknown).toEqual([]);
    expect(s.state.processed).toBe(false);expect(s.state.refundCreates).toHaveLength(0);
    expect(s.state.create).toBe(0);expect(s.state.writes).toEqual([]);
  });
  it('témoin positif : remboursement intégral confirmé, aucune facture ni transfert créé',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H});
    const before=structuredClone({h:s.db.factures_honoraires,c:s.db.factures});
    const r=await s.run();expect(s.state.unknown).toEqual([]);
    expect(r.status,s.state.logs.join('\n')).toBe(200);
    expect(await r.json()).toMatchObject({refunded:true});
    expect(s.state.refundCreates).toHaveLength(1);expect(s.state.create).toBe(0);
    expect(s.state.refundCreates[0].params).toMatchObject({payment_intent:'pi_f154'});
    expect(s.db.stripe_transfers[0].statut).toBe('REMBOURSE');
    expect({h:s.db.factures_honoraires,c:s.db.factures}).toEqual(before);
    expect(s.db.paiements_soignant).toHaveLength(0);
  });
  it('pending ne devient jamais REMBOURSE ni refunded:true',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H,refundStatus:'pending'});
    const r=await s.run();const body=await r.json();
    expect(s.state.unknown).toEqual([]);expect(s.state.refundCreates).toHaveLength(1);
    expect(s.state.create).toBe(0);expect(s.db.paiements_soignant).toHaveLength(0);
    expect(s.db.stripe_transfers[0].statut).not.toBe('REMBOURSE');
    expect(body.refunded).not.toBe(true);
    expect(s.state.writes.some(w=>w.table==='audit' && w.args.p_details.evenement==='CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE')).toBe(false);
  });
  it('erreur SQL après effet Stripe : pas de faux succès ni événement acquitté',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H,refundSqlError:true});
    const r=await s.run();const body=await r.json();
    expect(s.state.unknown).toEqual([]);expect(s.state.refundCreates).toHaveLength(1);
    expect(s.state.create).toBe(0);expect(s.db.stripe_transfers[0].statut).toBe('EN_ATTENTE');
    expect(r.status).toBe(500);expect(body.refunded).not.toBe(true);expect(s.state.processed).toBe(false);
  });
  it('cohorte TEST conservée : aucun remboursement, aucun transfert, aucune mutation financière',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H});s.db.etablissements[0].est_compte_test=true;
    const r=await s.run();expect(s.state.unknown).toEqual([]);
    expect(await r.json()).toMatchObject({test_skipped:true});
    expect(s.state.refundCreates).toHaveLength(0);expect(s.state.create).toBe(0);
    expect(s.db.stripe_transfers[0].statut).toBe('EN_ATTENTE');
  });
  it.each(['SQL','réponse Stripe'])('reprise après perte %s : objet exact retrouvé, un seul remboursement',async cause=>{
    const s=simulation({pending:true,invoice:true,fk:H});
    const before=structuredClone({h:s.db.factures_honoraires,c:s.db.factures});
    s.state.refundSqlError=cause==='SQL';s.state.timeoutAfterCreate=cause==='réponse Stripe';
    expect((await s.run()).status).toBe(500);expect(s.state.processed).toBe(false);
    s.state.refundSqlError=false;s.state.timeoutAfterCreate=false;
    // La clôture du litige ne doit pas convertir l'orientation durable en transfert.
    s.db.litiges[0].statut='RESOLU';
    const replay=await s.run();expect(replay.status,s.state.logs.join('\n')).toBe(200);
    expect(await replay.json()).toMatchObject({refunded:true,refund_status:'SUCCEEDED'});
    expect(s.state.refundCreates).toHaveLength(1);expect(s.state.create).toBe(0);
    expect(s.state.writes.filter(w=>w.table==='operation' && w.operation==='arbitrer')).toHaveLength(1);
    expect({h:s.db.factures_honoraires,c:s.db.factures}).toEqual(before);
    expect(s.state.unknown).toEqual([]);
  });
  it.each(['refund.updated','charge.refunded'])('%s rapproche pending puis succeeded sans second POST',async type=>{
    const s=simulation({pending:true,invoice:true,fk:H,refundStatus:'pending'});
    expect((await s.run()).status).toBe(200);expect(s.db.stripe_transfers[0].statut).toBe('EN_ATTENTE');
    s.changeRefundStatus('succeeded');s.nextEvent(type);
    const receipt=await s.run();expect(receipt.status,s.state.logs.join('\n')).toBe(200);
    expect(await receipt.json()).toMatchObject({refunded:true,refund_status:'SUCCEEDED'});
    s.nextEvent(type);expect((await s.run()).status).toBe(200);
    expect(s.state.refundCreates).toHaveLength(1);expect(s.state.create).toBe(0);
    expect(s.state.writes.filter(w=>w.table==='audit' && w.args.p_details.evenement==='CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE')).toHaveLength(1);
    expect(s.db.paiements_soignant).toHaveLength(0);expect(s.state.unknown).toEqual([]);
  });
  it('webhook reçu avec pending périmé : lit le Refund courant, puis le doublon ne crée rien',async()=>{
    const s=simulation({pending:true,invoice:true,fk:H,refundStatus:'pending'});await s.run();
    s.nextEvent('refund.updated');s.changeRefundStatus('succeeded');
    expect(await (await s.run()).json()).toMatchObject({refunded:true,refund_status:'SUCCEEDED'});
    expect((await s.run()).status).toBe(200);
    expect(s.state.refundCreates).toHaveLength(1);expect(s.state.create).toBe(0);expect(s.state.unknown).toEqual([]);
  });
});

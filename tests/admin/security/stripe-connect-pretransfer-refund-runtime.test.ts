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
  missing?: boolean; race?: string; pending?: boolean; invoice?: boolean; expiration?: 'INVOICE' | 'MISSION'; refundStatus?: string; refundSqlError?: boolean; stagingRefund?: boolean }={}) {
  const sessionId=options.stagingRefund?'cs_test_f154':'cs_f154';
  const metadata={type:'CONNECT_MISSION_PAYMENT',mission_id:M,soignant_id:S,etablissement_id:E,
    connected_account_id:'acct_f154',soignant_cents:'8000',commission_cents:'1440',
    connect_operation_id:O,facture_honoraires_id:H,facture_commission_id:F,payment_scope:options.expiration || (options.invoice?'INVOICE':'MISSION')};
  const session={id:sessionId,payment_intent:'pi_f154',customer:'cus_f154',client_reference_id:M,
    status:'complete',payment_method_types:['card'],livemode:false,payment_status:'paid',amount_total:9440,currency:'eur',metadata};
  const state={unknown:[] as string[],writes:[] as Row[],create:0,retrieve:0,processed:false,
    logs:[] as string[],rpcs:[] as string[],providerReads:[] as string[],invalidSignature:false,revokeOnRefundRead:false,raced:false,claimClosed:false,refundCreates:[] as Row[],timeoutAfterCreate:false,refundSqlError:!!options.refundSqlError};
  let eventId='evt_f154',eventType=options.expiration?'checkout.session.expired':'checkout.session.completed';
  let eventObject:Row=session;
  const st={id:T,mission_id:M,soignant_id:S,etablissement_id:E,facture_id:F,
    facture_honoraire_id:options.fk===undefined?null:options.fk,
    stripe_payment_intent_id:options.pi===undefined?null:options.pi,
    stripe_charge_id:options.charge===undefined?null:options.charge,
    statut:options.pending?'EN_ATTENTE':'TRANSFERE',stripe_transfer_id:options.pending?null:'tr_f154',
    stripe_checkout_session_id:sessionId,montant_soignant:80,montant_commission:14.4,montant_total:94.4};
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
      flow:options.expiration==='INVOICE'?'CONNECT_INVOICE':'CONNECT_MISSION',stripe_checkout_session_id:sessionId}],
  };
  db.litiges.push({id:'f1540000-0000-4000-8000-000000000007',mission_id:M,facture_id:H,statut:'OUVERT'});
  for(const table of ['factures_honoraires','factures']) for(const row of db[table]) {
    if(row.id===H || row.id===F) {row.statut='EMISE';row.stripe_payment_intent_id=null;}
  }
  const config={serverSha:'a'.repeat(40),uiSha:'b'.repeat(40),manifestSha256:'c'.repeat(64),
    platformAccountId:'acct_PlatformTEST',capabilityId:'f1540000-0000-4000-8000-000000000010',returnOrigin:'http://127.0.0.1:18491'};
  const capacity:Row={id:config.capabilityId,protocol:'CONNECT_STAGING_TEST_V1',project_ref:'mejpriaetwgtcstbgfid',
    server_sha:config.serverSha,ui_sha:config.uiSha,source_manifest_sha256:config.manifestSha256,platform_account_id:config.platformAccountId,
    livemode:false,transfers_allowed:false,max_checkouts:1,max_refunds:1,enabled:true,revoked_at:null,
    expires_at:new Date(Date.now()+3600_000).toISOString(),claim_reserved_at:new Date().toISOString(),
    mission_id:M,etablissement_id:E,soignant_id:S,facture_honoraire_id:H,facture_commission_id:F,
    customer_id:'cus_f154',destination_id:'acct_f154',soignant_cents:8000,commission_cents:1440,total_cents:9440,
    operation_id:O,session_id:sessionId,trace_id:T};
  const platform={id:config.platformAccountId,livemode:false};
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
    state.rpcs.push(name);
    if(name==='fn_connect_test_capacite_lire')return {data:structuredClone(capacity),error:null};
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
    if(name==='fn_connect_remboursement_prendre')return {data:{acquired:true,owner_token:args.p_owner_token,can_create:!options.stagingRefund,operation:structuredClone(operation)},error:null};
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
    accounts={retrieve:async()=>{state.providerReads.push('account');return {id:platform.id};}};
    balance={retrieve:async()=>{state.providerReads.push('balance');return {livemode:platform.livemode};}};
    checkout={sessions:{retrieve:async(id:string)=>id===session.id?session:forbidden(`session ${id}`)}};
    refunds={list:async()=>({data:refund?[refund]:[],has_more:false}),retrieve:async(id:string)=>{
      state.providerReads.push('refund');
      if(state.revokeOnRefundRead)capacity.revoked_at=new Date().toISOString();
      return refund?.id===id?refund:forbidden('autre Refund');},
      create:async(params:Row,request:Row)=>{state.refundCreates.push({params,request});
      refund={id:'re_f154',status:options.refundStatus || 'succeeded',amount:9440,currency:'eur',reason:'requested_by_customer',
        payment_intent:'pi_f154',charge:'ch_f154',metadata:params.metadata};
      if(refund.status==='succeeded'){charge.amount_refunded=9440;charge.refunded=true;}
      if(state.timeoutAfterCreate)throw new Error('REPONSE_STRIPE_PERDUE_SIMULEE');return refund;}};
    webhooks={constructEventAsync:async()=>{
      if(state.invalidSignature)throw new Error('SIGNATURE_FICTIVE_REJETEE');
      return {id:eventId,type:eventType,livemode:false,data:{object:eventObject}};}};
    paymentIntents={retrieve:async(id:string)=>id==='pi_f154'?intent:forbidden(`PI ${id}`)};
    customers={retrieve:async(id:string)=>id==='cus_f154'?{id,metadata:{etablissement_id:E}}:forbidden(`customer ${id}`)};
    charges={retrieve:async(id:string)=>id==='ch_f154'?charge:forbidden(`charge ${id}`)};
    transfers={list:async()=>({data:[],has_more:false}),retrieve:async(id:string)=>{state.retrieve++;return id==='tr_f154'?transfer:forbidden(`transfer ${id}`);},
      create:async()=>{state.create++;if(!options.pending)return forbidden('second transfert');return transfer;}};
  }
  const env:Row={SUPABASE_URL:'https://simulation.invalid',SUPABASE_SERVICE_ROLE_KEY:'simulation',
    STRIPE_SECRET_KEY:'sk_test_simulation',STRIPE_WEBHOOK_SECRET:'whsec_simulation'};
  if(options.stagingRefund){
    env.SUPABASE_URL='https://mejpriaetwgtcstbgfid.supabase.co';env.SUPABASE_ENV='staging';
    env.CONNECT_STAGING_TEST_RUN=JSON.stringify(config);
    db.etablissements[0].est_compte_test=true;db.soignants[0].est_compte_test=true;
  }
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
  if(options.stagingRefund){
    // État préexistant fictif : aucun Checkout ni Refund créé par cette simulation.
    operation={id:O,trace_id:T,session_id:sessionId,payment_intent_id:intent.id,charge_id:charge.id,
      mission_id:M,etablissement_id:E,soignant_id:S,facture_honoraire_id:H,facture_commission_id:F,
      customer_id:'cus_f154',destination_id:'acct_f154',soignant_cents:8000,commission_cents:1440,total_cents:9440,
      livemode:false,orientation:'REFUND',litige_id:db.litiges[0].id,refund_id:'re_f154',refund_status:'PENDING'};
    refund={id:'re_f154',status:'pending',amount:9440,currency:'eur',reason:'requested_by_customer',
      payment_intent:intent.id,charge:charge.id,
      metadata:load('supabase/functions/_shared/stripe-connect-pretransfer.ts').connectRefundMetadata(operation)};
    eventType='refund.updated';eventObject=structuredClone(refund);
  }
  const handler=load('supabase/functions/_shared/stripe-webhook-handler.ts').handleStripeWebhook;
  return {state,db,capacity,platform,env,operation:()=>operation,refund:()=>refund,event:()=>eventObject,changeRefundStatus(status:string){
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


describe('Admission TEST du Refund existant : handler réel, aucun fournisseur appelé',()=>{
  const fixture=()=>simulation({stagingRefund:true,pending:true,invoice:true,fk:H});
  const noCreation=(s:ReturnType<typeof simulation>)=>{
    expect(s.state.refundCreates).toEqual([]);expect(s.state.create).toBe(0);expect(s.state.unknown).toEqual([]);
    expect(s.state.rpcs).not.toContain('fn_connect_remboursement_demarrer');
    expect(s.state.rpcs).not.toContain('fn_connect_avant_transfert_arbitrer');
    expect(s.state.rpcs).not.toContain('fn_stripe_webhook_event_claim_connect_test_v1');
  };
  it.each(['refund.updated','refund.failed'])('%s utilise le Refund courant exact, même si le payload est périmé',async type=>{
    const s=fixture();s.nextEvent(type);s.changeRefundStatus(type==='refund.failed'?'failed':'succeeded');
    const r=await s.run();expect(r.status,s.state.logs.join('\n')).toBe(200);
    expect(await r.json()).toMatchObject({refund_status:type==='refund.failed'?'FAILED':'SUCCEEDED',refunded:type!=='refund.failed'});
    expect(s.state.processed).toBe(true);expect(s.state.rpcs).toContain('fn_stripe_webhook_event_claim');
    expect(s.state.rpcs.filter(x=>x==='fn_connect_test_capacite_lire')).toHaveLength(2);
    expect(s.state.providerReads).toContain('account');expect(s.state.providerReads).toContain('balance');noCreation(s);
  });
  it('le doublon conserve une seule observation et aucun nouvel objet',async()=>{
    const s=fixture();s.changeRefundStatus('succeeded');expect((await s.run()).status).toBe(200);
    expect(await (await s.run()).json()).toMatchObject({skipped:'already_processed'});
    expect(s.state.rpcs.filter(x=>x==='fn_connect_remboursement_constater')).toHaveLength(1);noCreation(s);
  });
  it.each(['révocation','expiration'])('doublon après %s : refus fermé avec CONFIG, puis acquittement sans nouveau constat',async closure=>{
    const s=fixture();s.changeRefundStatus('succeeded');
    const signedSnapshot=structuredClone(s.event());
    const first=await s.run();expect(first.status,s.state.logs.join('\n')).toBe(200);
    expect(await first.json()).toMatchObject({refunded:true,refund_status:'SUCCEEDED'});
    expect(s.state.processed).toBe(true);
    expect(s.state.rpcs.filter(x=>x==='fn_connect_remboursement_constater')).toHaveLength(1);
    const writesAfterSuccess=structuredClone(s.state.writes);
    const readsAfterSuccess=[...s.state.providerReads];
    const rpcCountAfterSuccess=s.state.rpcs.length;
    if(closure==='révocation')s.capacity.revoked_at=new Date().toISOString();
    else s.capacity.expires_at='2020-01-01T00:00:00Z';
    // Même événement, sans nextEvent : l'admission précède encore PROCESSED.
    const closed=await s.run();expect(closed.status).toBe(500);
    expect(s.event()).toEqual(signedSnapshot);expect(s.state.processed).toBe(true);
    expect(s.state.rpcs.slice(rpcCountAfterSuccess)).toEqual([
      'fn_connect_avant_transfert_lire','fn_connect_test_capacite_lire',
    ]);
    expect(s.state.writes).toEqual(writesAfterSuccess);
    expect(s.state.providerReads).toEqual(readsAfterSuccess);
    const rpcCountAfterRefusal=s.state.rpcs.length;
    delete s.env.CONNECT_STAGING_TEST_RUN;
    const unconfigured=await s.run();expect(unconfigured.status).toBe(200);
    expect(await unconfigured.json()).toMatchObject({skipped:'already_processed'});
    expect(s.event()).toEqual(signedSnapshot);expect(s.state.processed).toBe(true);
    expect(s.state.rpcs.slice(rpcCountAfterRefusal)).toEqual(['fn_stripe_webhook_event_claim']);
    expect(s.state.writes).toEqual(writesAfterSuccess);
    expect(s.state.providerReads).toEqual(readsAfterSuccess);
    expect(s.state.rpcs.filter(x=>x==='fn_connect_remboursement_constater')).toHaveLength(1);
    noCreation(s);
  });
  it('signature rejetée avant classification, claim ou lecture fournisseur',async()=>{
    const s=fixture();s.state.invalidSignature=true;expect((await s.run()).status).toBe(400);
    expect(s.state.rpcs).toEqual([]);expect(s.state.providerReads).toEqual([]);expect(s.state.writes).toEqual([]);noCreation(s);
  });
  it.each(['absente','autre origine','charge.refunded'])('neutralisation conservée : %s',async kind=>{
    const s=fixture();
    if(kind==='absente')delete s.env.CONNECT_STAGING_TEST_RUN;
    if(kind==='autre origine')s.event().metadata.source='autre_origine';
    if(kind==='charge.refunded')s.nextEvent(kind);
    expect(await (await s.run()).json()).toMatchObject({test_skipped:true});
    expect(s.state.rpcs).not.toContain('fn_connect_remboursement_prendre');
    expect(s.state.providerReads).toEqual([]);noCreation(s);
  });
  it.each(['autre plateforme','balance live','expirée','révoquée','Refund absent','autre Refund','montant','PI','charge','metadata'])('refuse %s avant le claim',async kind=>{
    const s=fixture();
    if(kind==='autre plateforme')s.platform.id='acct_OTHER';
    if(kind==='balance live')s.platform.livemode=true;
    if(kind==='expirée')s.capacity.expires_at='2020-01-01T00:00:00Z';
    if(kind==='révoquée')s.capacity.revoked_at=new Date().toISOString();
    if(kind==='Refund absent')s.operation()!.refund_id=null;
    if(kind==='autre Refund')s.operation()!.refund_id='re_OTHER';
    if(kind==='montant')s.event().amount=9441;
    if(kind==='PI')s.event().payment_intent='pi_OTHER';
    if(kind==='charge')s.event().charge='ch_OTHER';
    if(kind==='metadata')s.event().metadata.trace_id='f1540000-0000-4000-8000-000000000099';
    expect((await s.run()).status).toBe(500);expect(s.state.processed).toBe(false);
    expect(s.state.rpcs.some(x=>x.startsWith('fn_stripe_webhook_event_claim'))).toBe(false);
    expect(s.state.rpcs).not.toContain('fn_connect_remboursement_prendre');noCreation(s);
  });
  it.each(['montant','origine','PI','metadata'])('Refund courant discordant : %s, aucun constat',async kind=>{
    const s=fixture();
    if(kind==='montant')s.refund()!.amount=9441;
    if(kind==='origine')s.refund()!.metadata.source='autre_origine';
    if(kind==='PI')s.refund()!.payment_intent='pi_OTHER';
    if(kind==='metadata')s.refund()!.metadata.trace_id='f1540000-0000-4000-8000-000000000099';
    expect((await s.run()).status).toBe(500);expect(s.state.processed).toBe(false);
    expect(s.state.rpcs).toContain('fn_stripe_webhook_event_claim');
    expect(s.state.rpcs).not.toContain('fn_connect_remboursement_prendre');noCreation(s);
  });
  it('révocation entre admission et lecture fournisseur : aucun bail métier ni constat',async()=>{
    const s=fixture();s.state.revokeOnRefundRead=true;s.changeRefundStatus('succeeded');
    expect((await s.run()).status).toBe(500);expect(s.state.processed).toBe(false);
    expect(s.state.rpcs).toContain('fn_stripe_webhook_event_claim');
    expect(s.state.rpcs).not.toContain('fn_connect_remboursement_prendre');
    expect(s.state.rpcs).not.toContain('fn_connect_remboursement_constater');noCreation(s);
  });
  it('échec de persistance : erreur retryable, jamais un acquittement de succès',async()=>{
    const s=fixture();s.state.refundSqlError=true;s.changeRefundStatus('succeeded');
    expect((await s.run()).status).toBe(500);expect(s.state.processed).toBe(false);noCreation(s);
  });
});

import { describe, expect, it } from 'vitest';
import { connectRefundMetadata, parseConnectOperation, processConnectPretransferRefund,
  processConnectRefundBatch, type ConnectOperation } from '../../../supabase/functions/_shared/stripe-connect-pretransfer.ts';

// Le helper produit est exécuté. DB et SDK sont des transports en mémoire :
// ces tests ne prétendent prouver ni verrous PostgreSQL ni argent Stripe TEST.
const id=(n:number)=>`f1550000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const owner=id(20);
function operation(): ConnectOperation {
  return { id:id(1),trace_id:id(2),mission_id:id(3),etablissement_id:id(4),soignant_id:id(5),
    facture_honoraire_id:id(6),facture_commission_id:id(7),litige_id:id(8),session_id:'cs_f155',
    payment_intent_id:'pi_f155',charge_id:'ch_f155',customer_id:'cus_f155',destination_id:'acct_f155',
    soignant_cents:8000,commission_cents:1440,total_cents:9440,livemode:false,
    orientation:'REFUND',refund_id:null,refund_status:'READY' };
}
function harness() {
  const op=operation(), calls:string[]=[], params:unknown[]=[], refunds:any[]=[];
  const state={sqlError:false,refuseLease:false,canCreate:true,createAllowed:true,timeoutAfterCreate:false,refundStatus:'succeeded',
    refundPages:null as any[]|null, transferPages:null as any[]|null,receipt:null as any, leaseOperation:null as any,reviewCode:null as string|null};
  const metadata={type:'CONNECT_MISSION_PAYMENT',payment_scope:'INVOICE',connect_operation_id:op.id,mission_id:op.mission_id,
    etablissement_id:op.etablissement_id,soignant_id:op.soignant_id,connected_account_id:op.destination_id,
    facture_honoraires_id:op.facture_honoraire_id,facture_commission_id:op.facture_commission_id,
    soignant_cents:'8000',commission_cents:'1440'};
  const session:any={id:op.session_id,status:'complete',payment_method_types:['card'],payment_status:'paid',livemode:false,amount_total:9440,
    currency:'eur',client_reference_id:op.mission_id,customer:op.customer_id,payment_intent:op.payment_intent_id,metadata};
  const pi:any={id:op.payment_intent_id,status:'succeeded',payment_method_types:['card'],livemode:false,amount:9440,amount_received:9440,
    amount_capturable:0,currency:'eur',customer:op.customer_id,latest_charge:op.charge_id,metadata:{...metadata}};
  const charge:any={id:op.charge_id,payment_method_details:{type:'card'},livemode:false,paid:true,captured:true,status:'succeeded',currency:'eur',amount:9440,
    customer:op.customer_id,payment_intent:op.payment_intent_id,created:1_790_000_000,amount_refunded:0,refunded:false,disputed:false};
  const customer:any={id:op.customer_id,metadata:{etablissement_id:op.etablissement_id}};
  const find=(kind:string,expected:string,row:()=>unknown)=>({retrieve:async(value:string)=>{
    calls.push(`${kind}.retrieve`);expect(value).toBe(expected);return structuredClone(row());}});
  const stripe={checkout:{sessions:find('session',op.session_id,()=>session)},paymentIntents:find('pi',op.payment_intent_id,()=>pi),
    charges:find('charge',op.charge_id,()=>charge),customers:find('customer',op.customer_id,()=>customer),
    transfers:{list:async(args:unknown)=>{calls.push('transfers.list');params.push(args);
      return structuredClone(state.transferPages?.shift() || {data:[],has_more:false});}},
    refunds:{...find('refund','re_f155',()=>refunds[0]),list:async(args:unknown)=>{calls.push('refunds.list');params.push(args);
      return structuredClone(state.refundPages?.shift() || {data:refunds,has_more:false});},
      create:async(args:any,options:unknown)=>{calls.push('refunds.create');params.push({args,options});
        expect(refunds).toHaveLength(0);
        const refund={id:'re_f155',amount:9440,currency:'eur',payment_intent:op.payment_intent_id,charge:op.charge_id,
          reason:'requested_by_customer',status:state.refundStatus,metadata:args.metadata,transfer_reversal:null,source_transfer_reversal:null};
        refunds.push(refund); if(refund.status==='succeeded'){charge.amount_refunded=9440;charge.refunded=true;}
        if(state.timeoutAfterCreate)throw new Error('TRANSPORT_TIMEOUT_SIMULE');return structuredClone(refund);}}};
  const sb={rpc:async(name:string,args:any)=>{
    calls.push(name);
    if(name==='fn_connect_remboursements_a_traiter'){expect(args.p_limit).toBe(2);return {data:[structuredClone(op)],error:null};}
    expect(args.p_operation_id).toBe(op.id);expect(args.p_owner_token).toBe(owner);
    if(name==='fn_connect_remboursement_prendre')return {data:{acquired:!state.refuseLease,owner_token:owner,can_create:state.canCreate,
      operation:structuredClone(state.leaseOperation || op)},error:null};
    if(name==='fn_connect_remboursement_demarrer')return {data:{operation_id:op.id,owner_token:owner,create_allowed:state.createAllowed},error:null};
    if(name==='fn_connect_remboursement_constater'){
      if(state.sqlError)return {data:null,error:{message:'DETAIL_PRIVE_NON_EXPOSE'}};
      op.refund_id=args.p_refund.id;
      if(['FAILED','CANCELED'].includes(op.refund_status) && op.refund_status!==args.p_refund.status.toUpperCase()) {
        op.refund_status='REVIEW';state.reviewCode='REFUND_STATUS_CONTRADICTORY';
      } else if(op.refund_status==='SUCCEEDED' && ['failed','canceled','requires_action'].includes(args.p_refund.status)) {
        op.refund_status='REVIEW';state.reviewCode=args.p_refund.status==='requires_action'?'REFUND_REQUIRES_ACTION_AFTER_SUCCESS':'REFUND_RETURNED_AFTER_SUCCESS';
      } else if(op.refund_status!=='REVIEW' && !(op.refund_status==='SUCCEEDED' && args.p_refund.status==='pending'))op.refund_status=args.p_refund.status.toUpperCase();
      return {data:state.receipt || {operation_id:op.id,refund_id:op.refund_id,status:op.refund_status,review_code:state.reviewCode},error:null};
    } throw new Error(`RPC imprévue ${name}`);
  }};
  return {op,state,session,pi,charge,customer,refunds,calls,params,sb,stripe,
    run:()=>processConnectPretransferRefund(sb,stripe,structuredClone(op),owner)};
}

describe('Intention Connect avant transfert : primitive réelle, réseau fermé',()=>{
  it.each(['pending','requires_action','failed','canceled','succeeded'])('%s est constaté, seul succeeded est un succès',async status=>{
    const h=harness();h.state.refundStatus=status;const result=await h.run();
    expect(result).toEqual({operationId:h.op.id,status:status.toUpperCase(),refunded:status==='succeeded'});
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
    expect(h.calls.indexOf('fn_connect_remboursement_demarrer')).toBeLessThan(h.calls.indexOf('refunds.create'));
    expect(h.params.at(-1)).toEqual({args:{payment_intent:'pi_f155',amount:9440,reason:'requested_by_customer',
      metadata:connectRefundMetadata(h.op)},options:{idempotencyKey:`connect_pretransfer_refund_${h.op.id}`}});
  });
  it('réponse Stripe perdue : reprise retrouve le même objet, sans nouveau POST',async()=>{
    const h=harness();h.state.timeoutAfterCreate=true;
    await expect(h.run()).rejects.toThrow('TRANSPORT_TIMEOUT_SIMULE');
    expect(h.op.refund_status).toBe('READY');h.state.timeoutAfterCreate=false;
    expect((await h.run()).refunded).toBe(true);
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('écriture SQL refusée après Stripe : échec, puis reprise de l’objet exact',async()=>{
    const h=harness();h.state.sqlError=true;
    await expect(h.run()).rejects.toThrow('CONNECT_OPERATION_SQL_FAILED');
    expect(h.op.refund_status).toBe('READY');h.state.sqlError=false;
    expect((await h.run()).refunded).toBe(true);expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('doublons et pending tardif ne créent aucun deuxième remboursement',async()=>{
    const h=harness();await h.run();await h.run();
    h.refunds[0].status='pending';h.charge.amount_refunded=0;h.charge.refunded=false;
    expect((await h.run()).status).toBe('SUCCEEDED');expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it.each([['failed',0],['failed',9440],['canceled',0],['canceled',9440]] as const)('retour bancaire %s, agrégat Charge %s après succès : REVIEW, jamais nouveau mouvement',async(status,aggregate)=>{
    const h=harness();await h.run();h.refunds[0].status=status;h.charge.amount_refunded=aggregate;h.charge.refunded=aggregate===9440;
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_RETURN_NOT_PROVEN');
    expect(h.op.refund_status).toBe('SUCCEEDED');
    h.refunds[0].failure_balance_transaction='txn_retour';
    expect(await h.run()).toMatchObject({status:'REVIEW',refunded:false});
    h.refunds[0].status='succeeded';h.charge.amount_refunded=9440;h.charge.refunded=true;
    expect(await h.run()).toMatchObject({status:'REVIEW',refunded:false});
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('requires_action courant après succès carte : incident à rapprocher, pas succès silencieux',async()=>{
    const h=harness();await h.run();h.refunds[0].status='requires_action';
    expect(await h.run()).toMatchObject({status:'REVIEW',refunded:false});
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it.each(['session','pi','charge'])('admission carte stricte : autre moyen %s refusé',async key=>{
    const h=harness();if(key==='charge')h.charge.payment_method_details.type='sepa_debit';else(h as any)[key].payment_method_types=['sepa_debit'];
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_SOURCE_MISMATCH');expect(h.calls).not.toContain('refunds.create');
  });
  it('webhook de constat sans objet dans la liste : aucun droit de créer',async()=>{
    const h=harness();await expect(processConnectPretransferRefund(h.sb,h.stripe,h.op,owner,{allowCreate:false})).rejects.toThrow('CONNECT_REFUND_WEBHOOK_OBJECT_MISSING');
    expect(h.calls).not.toContain('refunds.create');expect(h.calls).not.toContain('fn_connect_remboursement_demarrer');
  });
  it('worker : même primitive, budget deux et rapport fermé sans détail SQL/fournisseur',async()=>{
    const h=harness();h.state.refundStatus='pending';
    expect(await processConnectRefundBatch(h.sb,h.stripe,()=>owner)).toEqual({processed:1,succeeded:0,pending:1,failed:0,errors:[]});
    const broken=harness();broken.state.sqlError=true;
    expect(await processConnectRefundBatch(broken.sb,broken.stripe,()=>owner)).toEqual({processed:1,succeeded:0,pending:1,failed:0,errors:['CONNECT_OPERATION_SQL_FAILED']});
  });
  it('bail refusé (dont cohorte TEST refusée côté SQL) : aucun appel Stripe',async()=>{
    const h=harness();h.state.refuseLease=true;await expect(h.run()).rejects.toThrow('CONNECT_REFUND_BUSY');
    expect(h.calls).toEqual(['fn_connect_remboursement_prendre']);
  });
  it('fenêtre d’idempotence dépassée sans objet : aucun nouveau POST',async()=>{
    const h=harness();h.state.createAllowed=false;await expect(h.run()).rejects.toThrow('CONNECT_REFUND_CREATE_WINDOW_CLOSED');
    expect(h.calls).not.toContain('refunds.create');
  });
  it.each(['pending','réponse perdue'])('compte anonymisé après %s : constat de l’objet conservé, aucun nouveau POST',async prior=>{
    const h=harness();h.state.refundStatus='pending';h.state.timeoutAfterCreate=prior==='réponse perdue';
    if(h.state.timeoutAfterCreate)await expect(h.run()).rejects.toThrow('TRANSPORT_TIMEOUT_SIMULE');else await h.run();
    h.state.canCreate=false;h.customer.deleted=true;delete h.customer.metadata;
    h.refunds[0].status='succeeded';h.charge.amount_refunded=9440;h.charge.refunded=true;
    expect(await h.run()).toMatchObject({status:'SUCCEEDED',refunded:true});
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('compte suspendu, objet encore absent après issue ambiguë : aucune nouvelle création',async()=>{
    const h=harness();h.state.canCreate=false;
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_ACCOUNT_CLOSED');
    expect(h.calls).not.toContain('refunds.create');expect(h.calls).not.toContain('fn_connect_remboursement_demarrer');
  });
  it('orientation TRANSFER immuable : aucun remboursement',async()=>{
    const h=harness();h.op.orientation='TRANSFER';h.op.litige_id=null;
    await expect(h.run()).rejects.toThrow('CONNECT_OPERATION_ORIENTATION');expect(h.calls).toEqual([]);
  });
  it.each(['etablissement_id','facture_honoraire_id','trace_id'])('bail d’une autre identité %s refusé',async key=>{
    const h=harness();h.state.leaseOperation={...h.op,[key]:id(99)};
    await expect(h.run()).rejects.toThrow('CONNECT_OPERATION_CHANGED');expect(h.calls).toHaveLength(1);
  });
  it.each(['session','pi','charge','customer'])('source %s d’un autre tenant refusée avant POST',async key=>{
    const h=harness(); if(key==='customer')h.customer.metadata.etablissement_id=id(99);else(h as any)[key].customer='cus_autre';
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_SOURCE_MISMATCH');expect(h.calls).not.toContain('refunds.create');
  });
  it('la Session fraîche refuse une autre FH, même si le PI est correct',async()=>{
    const h=harness();h.session.metadata={...h.session.metadata,facture_honoraires_id:id(99)};
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_SOURCE_MISMATCH');expect(h.calls).not.toContain('refunds.create');
  });
  it.each(['pending','requires_action'])('agrégat Charge intégral ne confirme pas un Refund %s',async status=>{
    const h=harness();h.state.refundStatus=status;await h.run();h.charge.amount_refunded=9440;h.charge.refunded=true;
    expect(await h.run()).toMatchObject({status:status.toUpperCase(),refunded:false});
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it.each(['transfer_data','application_fee_amount','on_behalf_of'])('PI destination charge %s refusé',async key=>{
    const h=harness();h.pi[key]=key==='application_fee_amount'?100:{destination:'acct_etranger'};
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_SOURCE_MISMATCH');expect(h.calls).not.toContain('refunds.create');
  });
  it.each(['transfer_data','transfer','application_fee','application_fee_amount','on_behalf_of','destination'])('Charge non séparée %s refusée',async key=>{
    const h=harness();h.charge[key]=key==='application_fee_amount'?100:'objet_etranger';
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_SOURCE_MISMATCH');expect(h.calls).not.toContain('refunds.create');
  });
  it('un transfert de la Charge sur la seconde page bloque, même autre destination/groupe',async()=>{
    const h=harness();h.state.transferPages=[{data:[{id:'tr_autre',source_transaction:'ch_autre'}],has_more:true},
      {data:[{id:'tr_exact',source_transaction:h.op.charge_id,destination:'acct_autre',transfer_group:'autre'}],has_more:false}];
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_TRANSFER_PRESENT');expect(h.calls).not.toContain('refunds.create');
    expect(h.params.find((p:any)=>p.starting_after==='tr_autre')).toEqual({created:{gte:h.charge.created},limit:100,starting_after:'tr_autre'});
  });
  it('pagination répétée ou tronquée refuse toute absence supposée',async()=>{
    const h=harness();h.state.transferPages=[{data:[{id:'tr_x'}],has_more:true},{data:[{id:'tr_x'}],has_more:false}];
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_PAGINATION');expect(h.calls).not.toContain('refunds.create');
  });
  it('saturation globale avant création : aucune absence supposée ni nouvelle clé',async()=>{
    const h=harness();h.state.transferPages=Array.from({length:20},(_,page)=>({
      data:Array.from({length:100},(_,i)=>({id:`tr_${page}_${i}`,source_transaction:'ch_ailleurs'})),has_more:true}));
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_PAGINATION_LIMIT');
    expect(h.calls.filter(c=>c==='transfers.list')).toHaveLength(20);
    expect(h.calls).not.toContain('refunds.create');expect(h.calls).not.toContain('fn_connect_remboursement_demarrer');
  });
  it('constat du Refund propre après croissance du flux : aucun listing global bloquant ni nouveau POST',async()=>{
    const h=harness();h.state.refundStatus='pending';await h.run();
    const callsBefore=h.calls.length;
    h.state.transferPages=[{data:[],has_more:true}];
    h.refunds[0].status='succeeded';h.charge.amount_refunded=9440;h.charge.refunded=true;
    expect(await h.run()).toMatchObject({status:'SUCCEEDED',refunded:true});
    expect(h.calls.slice(callsBefore)).not.toContain('transfers.list');
    expect(h.calls.slice(callsBefore)).toContain('refunds.list');
    expect(h.calls.slice(callsBefore)).toContain('refund.retrieve');
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('refund étranger ou deux objets propres refusés, aucune adoption',async()=>{
    const h=harness();await h.run();h.refunds[0].metadata.litige_id=id(99);
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_IDENTITY_MISMATCH');
    h.refunds[0].metadata=connectRefundMetadata(h.op);h.refunds.push({...h.refunds[0],id:'re_second'});
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_FOREIGN_MOVEMENT');expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('un remboursement partiel étranger dans la Charge refuse le POST',async()=>{
    const h=harness();h.charge.amount_refunded=1;
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_FOREIGN_MOVEMENT');expect(h.calls).not.toContain('refunds.create');
  });
  it('reçu SQL incohérent ne peut annoncer un succès',async()=>{
    const h=harness();h.state.receipt={operation_id:id(99),refund_id:'re_f155',status:'SUCCEEDED'};
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_RECEIPT_INVALID');
  });
  it.each(['REFUND_FAILED','REFUND_CANCELED'])('reçu SQL SUCCEEDED avec incident %s refusé',async reviewCode=>{
    const h=harness();h.state.receipt={operation_id:h.op.id,refund_id:'re_f155',status:'SUCCEEDED',review_code:reviewCode};
    await expect(h.run()).rejects.toThrow('CONNECT_REFUND_RECEIPT_INVALID');
  });
  it.each(['failed','canceled'])('constat frais succeeded après %s : incident, pas deuxième POST',async prior=>{
    const h=harness();h.state.refundStatus=prior;await h.run();const before=h.calls.length;
    h.refunds[0].status='succeeded';h.charge.amount_refunded=9440;h.charge.refunded=true;
    expect(await h.run()).toMatchObject({status:'REVIEW',refunded:false});
    expect(h.calls.slice(before)).toContain('refund.retrieve');
    expect(h.calls.slice(before)).not.toContain('refunds.create');
    expect(h.calls.filter(c=>c==='refunds.create')).toHaveLength(1);
  });
  it('shape incomplète, montants/IDs et orientation ambiguës refusés',()=>{
    expect(()=>parseConnectOperation({})).toThrow('CONNECT_OPERATION_IDENTITY');
    expect(()=>parseConnectOperation({...operation(),total_cents:9441})).toThrow('CONNECT_OPERATION_AMOUNT');
    expect(()=>parseConnectOperation({...operation(),orientation:'UNKNOWN'})).toThrow('CONNECT_OPERATION_ORIENTATION');
  });
});

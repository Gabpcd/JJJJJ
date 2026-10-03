import { describe, expect, it } from 'vitest';
import { acquireStripePaymentFlowClaim, mapStripeConnectProtocolError, StripeConnectProtocolError, type StripePaymentFlow } from '../../../supabase/functions/_shared/stripe-payment-flow-claim.ts';

// Exécute le helper appelé avant Checkout et son erreur explicite. Transport
// SQL simulé seulement ; les signatures/ACL fermées sont prouvées par PG17.
describe('Protocole Connect versionné : ancien contrat conservé pour les autres paiements',()=>{
  it.each(['CONNECT_MISSION','CONNECT_INVOICE','CHECKOUT_INVOICE','SEPA_INVOICE'] as StripePaymentFlow[])('%s choisit exactement sa signature',async flow=>{
    const calls:{name:string;args:Record<string,unknown>}[]=[];
    const expected={flow,owner_token:'owner-fixture',mission_id:'mission-fixture',facture_id:'facture-fixture'};
    const sb={from(){throw new Error('LECTURE_IMPREVUE');},async rpc(name:string,args:Record<string,unknown>){calls.push({name,args});return {data:{acquired:true},error:null};}};
    expect((await acquireStripePaymentFlowClaim(sb,expected)).acquired).toBe(true);
    expect(calls).toEqual([{name:flow.startsWith('CONNECT_')?'fn_stripe_payment_flow_claim_connect_v1':'fn_stripe_payment_flow_claim',args:{
      p_flow:flow,p_owner_token:expected.owner_token,p_facture_id:expected.facture_id,p_mission_id:expected.mission_id}}]);
  });
  it.each(['CONNECT_MISSION','CONNECT_INVOICE'] as StripePaymentFlow[])('%s fermé ne retourne jamais un acquired=false exploitable en recovery',async flow=>{
    let attempts=0;
    const sb={from(){throw new Error('LECTURE_IMPREVUE');},async rpc(name:string){attempts++;expect(name).toBe('fn_stripe_payment_flow_claim_connect_v1');return {data:null,error:{message:'CONNECT_RELEASE_CLOSED'}};}};
    await expect(acquireStripePaymentFlowClaim(sb,{flow,owner_token:'owner-fixture',mission_id:null,facture_id:'facture-fixture'})).rejects.toThrow('CONNECT_RELEASE_CLOSED');
    expect(attempts).toBe(1);
  });
});


describe('Erreurs de protocole : projection fermée',()=>{
  it.each(['CONNECT_RELEASE_CLOSED','CONNECT_CLIENT_VERSION_REQUIRED'] as const)('%s est typé seulement sur le claim Connect',async code=>{
    const sb={from(){throw new Error('LECTURE_IMPREVUE');},async rpc(){return {data:null,error:{message:code}};}};
    const error=await acquireStripePaymentFlowClaim(sb,{flow:'CONNECT_INVOICE',owner_token:'fixture',mission_id:null,facture_id:'fixture'}).catch(error=>error);
    expect(error).toBeInstanceOf(StripeConnectProtocolError);
    expect(mapStripeConnectProtocolError(error)).toMatchObject({status:503,code,retryable:false});
    const other=await acquireStripePaymentFlowClaim(sb,{flow:'CHECKOUT_INVOICE',owner_token:'fixture',mission_id:null,facture_id:'fixture'}).catch(error=>error);
    expect(mapStripeConnectProtocolError(other)).toBeNull();
  });
  it('un message libre ressemblant au code ne devient jamais une instruction de maintenance',async()=>{
    const sb={from(){throw new Error('LECTURE_IMPREVUE');},async rpc(){return {data:null,error:{message:'CONNECT_RELEASE_CLOSED details SQL'}};}};
    const error=await acquireStripePaymentFlowClaim(sb,{flow:'CONNECT_INVOICE',owner_token:'fixture',mission_id:null,facture_id:'fixture'}).catch(error=>error);
    expect(mapStripeConnectProtocolError(error)).toBeNull();
    expect(mapStripeConnectProtocolError({code:'CONNECT_RELEASE_CLOSED'})).toBeNull();
  });
});

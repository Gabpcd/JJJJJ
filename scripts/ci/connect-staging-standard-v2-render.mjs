import { createHash } from 'node:crypto';
const md5=s=>createHash('md5').update(s).digest('hex');
const quote=s=>`'${s.replaceAll("'","''")}'`;
const once=(s,a,b)=>{if(s.split(a).length!==2)throw Error('CONNECT_V2_PATCH_ANCHOR');return s.replace(a,()=>b);};
function definition(sql,name) {
 const re=new RegExp(`CREATE (?:OR REPLACE )?FUNCTION ${name.replaceAll('.','\\.')}\\(`);
 const start=sql.search(re);if(start<0)throw Error('CONNECT_V2_SOURCE_ABSENT');
 const tail=sql.slice(start),d=/\bAS\s+(\$[A-Za-z_0-9]*\$)/i.exec(tail);if(!d)throw Error('CONNECT_V2_SOURCE_DELIMITER');
 const begin=d.index+d[0].length,end=tail.indexOf(d[1],begin);if(end<0)throw Error('CONNECT_V2_SOURCE_END');
 return {sql:tail.slice(0,end+d[1].length+1),body:tail.slice(begin,end)};
}

/** Render only. Applies to the reviewed V1 installation, including revoked
 * historical V1 receipts. No capacity allocation, provider or activation. */
export function renderStagingStandardV2(admissionV1,delta,payoutSource) {
 if(typeof admissionV1!=='string'||typeof delta!=='string'||typeof payoutSource!=='string')throw Error('CONNECT_V2_SOURCE_REQUIRED');
 const guards=[],changes=[];
 for(const signature of ['private.fn_connect_operation_verrouiller(uuid)','private.fn_connect_creation_autorisee(uuid)']) {
   const d=definition(admissionV1,signature.split('(')[0]);
   guards.push(`IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(${quote(signature)})) IS DISTINCT FROM ${quote(md5(d.body))} THEN RAISE EXCEPTION 'CONNECT_V2_CANONICAL_DRIFT (${signature})'; END IF;`);
 }
 function alter(signature,change){
   const d=definition(admissionV1,signature.split('(')[0]);
   guards.push(`IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(${quote(signature)})) IS DISTINCT FROM ${quote(md5(d.body))} THEN RAISE EXCEPTION 'CONNECT_V2_SOURCE_DRIFT (${signature})'; END IF;`);
   changes.push(d.sql.replace(d.body,()=>change(d.body)).replace(/^CREATE FUNCTION /,'CREATE OR REPLACE FUNCTION '));
 }
 alter('private.fn_connect_test_scope(uuid,boolean)',s=>once(s,
   "IF c.protocol<>'CONNECT_STAGING_TEST_V1' OR c.project_ref<>'mejpriaetwgtcstbgfid'\n   OR c.livemode IS DISTINCT FROM FALSE OR c.transfers_allowed IS DISTINCT FROM FALSE",
   "IF c.protocol NOT IN('CONNECT_STAGING_TEST_V1','CONNECT_STAGING_STANDARD_TEST_V2') OR c.project_ref<>'mejpriaetwgtcstbgfid'\n   OR c.livemode IS DISTINCT FROM FALSE\n   OR (c.protocol='CONNECT_STAGING_TEST_V1' AND (c.transfers_allowed OR c.payouts_allowed OR c.max_transfers<>0 OR c.max_payouts<>0))\n   OR (c.protocol='CONNECT_STAGING_STANDARD_TEST_V2' AND (NOT c.transfers_allowed OR NOT c.payouts_allowed OR c.max_transfers<>1 OR c.max_payouts<>1))"));
 alter('private.fn_connect_test_operation_connue(uuid)',s=>once(s,
   "OR o.livemode IS TRUE OR o.orientation='TRANSFER' OR c.checkout_reserved_at IS NULL",
   "OR o.livemode IS TRUE OR (o.orientation='TRANSFER' AND c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2') OR c.checkout_reserved_at IS NULL"));
 alter('private.fn_connect_test_verifier_arbitrage(uuid,uuid,jsonb)',s=>{
   s=once(s,'BEGIN\n IF NOT private.fn_connect_test_operation_connue',
     'DECLARE c private.stripe_connect_test_capacities;\nBEGIN\n IF NOT private.fn_connect_test_operation_connue');
   return once(s," IF p_source->'livemode' IS DISTINCT FROM 'false'::jsonb OR p_litige_id IS NULL",
     " SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE operation_id=p_operation_id;\n IF c.protocol='CONNECT_STAGING_STANDARD_TEST_V2' AND p_litige_id IS NULL THEN\n   IF p_source->'livemode' IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'CONNECT_TEST_TRANSFER_FORBIDDEN'; END IF;\n   RETURN;\n END IF;\n IF p_source->'livemode' IS DISTINCT FROM 'false'::jsonb OR p_litige_id IS NULL");
 });
 // After final payment, the same claim may contain its exact admitted PI.
 alter('private.fn_connect_test_exiger_claim(uuid,text,uuid)',s=>once(s,
   'OR f.stripe_payment_intent_id IS NOT NULL))',
   "OR (f.stripe_payment_intent_id IS NOT NULL AND (c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2'\n       OR f.stripe_payment_intent_id IS DISTINCT FROM (SELECT payment_intent_id FROM private.stripe_connect_avant_transfert WHERE id=c.operation_id)))))"));
 const start=definition(payoutSource,'public.fn_connect_payout_demarrer');
 guards.push(`IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_connect_payout_demarrer(uuid,uuid)'::regprocedure) IS DISTINCT FROM ${quote(md5(start.body))} THEN RAISE EXCEPTION 'CONNECT_V2_PAYOUT_SOURCE_DRIFT'; END IF;`);
 let body=once(start.body,'OR o.livemode IS DISTINCT FROM TRUE',`OR o.livemode IS DISTINCT FROM FALSE
     OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities cap
       WHERE cap.id=p_capacity_id AND cap.operation_id=o.id AND cap.protocol='CONNECT_STAGING_STANDARD_TEST_V2'
         AND cap.payouts_allowed AND cap.max_payouts=1 AND cap.payout_reserved_at IS NOT NULL
         AND cap.payout_id IS NULL AND cap.transfer_id=s.stripe_transfer_id AND s.standard_payout_attempt=0
         AND private.fn_connect_test_creation_autorisee(o.id))`);
 changes.push(start.sql.replace(start.body,()=>body).replace(
   'public.fn_connect_payout_demarrer(p_trace_id uuid,p_owner uuid)',
   'public.fn_connect_payout_demarrer_test(p_trace_id uuid,p_owner uuid,p_capacity_id uuid)'));
 changes.push(`ALTER FUNCTION public.fn_connect_payout_demarrer_test(uuid,uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_connect_payout_demarrer_test(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_connect_payout_demarrer_test(uuid,uuid,uuid) TO service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT 'fn_connect_payout_demarrer_test(uuid,uuid,uuid)','SERVICE_ONLY_REVOQUE',md5(prosrc),
 'Copie vérifiée du CAS payout : mode TEST et capacité V2 exacte ; fonction LIVE inchangée.',clock_timestamp()
FROM pg_proc WHERE oid='public.fn_connect_payout_demarrer_test(uuid,uuid,uuid)'::regprocedure;`);
 return `-- STAGING ONLY: generated reviewed V2 delta, no allocation.\nDO $sources$ BEGIN\n${guards.join('\n')}\nEND $sources$;\n${delta}\n${changes.join('\n\n')}\n`;
}

import { createHash } from 'node:crypto';
const md5=s=>createHash('md5').update(s).digest('hex');
const quote=s=>`'${s.replaceAll("'","''")}'`;
const once=(s,a,b)=>{if(s.split(a).length!==2)throw Error('STAGING_PATCH_ANCHOR');return s.replace(a,()=>b);};
function source(migration,signature){
 const name=signature.split('(')[0], [schema,fn]=name.split('.');
 const re=new RegExp(`CREATE (?:OR REPLACE )?FUNCTION (?:${schema}\\.${fn}|"${schema}"\\."${fn}")\\(`);
 const start=migration.search(re);if(start<0)throw Error('STAGING_SOURCE_ABSENT');
 const tail=migration.slice(start),d=/\bAS\s+(\$[A-Za-z_0-9]*\$)/i.exec(tail);if(!d)throw Error('STAGING_SOURCE_DELIMITER');
 const b=d.index+d[0].length,end=tail.indexOf(d[1],b);if(end<0)throw Error('STAGING_SOURCE_END');
 return {sql:tail.slice(0,end+d[1].length+1),body:tail.slice(b,end),signature};
}
function replaceBody(f,body){return f.sql.replace(f.body,()=>body).replace(/^CREATE FUNCTION /,'CREATE OR REPLACE FUNCTION ');}
const condition=`  IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
    WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'CONNECT_RELEASE_CLOSED' USING ERRCODE='55000';
  END IF;`;
export function renderStagingAdmission(migration,helpers){
 if(typeof migration!=='string'||typeof helpers!=='string')throw Error('STAGING_SOURCE_REQUIRED');
 const changes=[],guards=[];
 function alter(sig,fn){const s=source(migration,sig);guards.push(`IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(${quote(sig)})) IS DISTINCT FROM ${quote(md5(s.body))} THEN RAISE EXCEPTION 'CONNECT_TEST_SOURCE_DRIFT (${sig})'; END IF;`);changes.push(replaceBody(s,fn(s.body)));}
 alter('private.fn_connect_operation_verrouiller(uuid)',s=>{
 const old=`   OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=o.soignant_id AND est_compte_test IS FALSE)
   OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=o.etablissement_id AND est_compte_test IS FALSE)
   OR EXISTS(SELECT 1 FROM public.soignants WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)
   OR EXISTS(SELECT 1 FROM public.etablissements WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)`;
 return once(s,old,`   OR (NOT private.fn_connect_test_operation_connue(o.id) AND (
     NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=o.soignant_id AND est_compte_test IS FALSE)
     OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=o.etablissement_id AND est_compte_test IS FALSE)
     OR EXISTS(SELECT 1 FROM public.soignants WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)
     OR EXISTS(SELECT 1 FROM public.etablissements WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)))`);
 });
 alter('private.fn_connect_creation_autorisee(uuid)',s=>once(s,
   'private.fn_connect_protocole_ouvert() AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE',
   '((private.fn_connect_protocole_ouvert() AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE) OR private.fn_connect_test_creation_autorisee(o.id))'));
 alter('public.fn_connect_checkout_preparer(uuid,uuid,text)',s=>once(s,
   ' -- Une insertion neuve a trace_id NULL et n\'acquiert donc aucune ST tardive.',
   ` PERFORM private.fn_connect_test_reserver_checkout(o.id);
 -- Une insertion neuve a trace_id NULL et n'acquiert donc aucune ST tardive.`));
 alter('public.fn_connect_avant_transfert_arbitrer(uuid,uuid,jsonb)',s=>once(s,
   " UPDATE private.stripe_connect_avant_transfert SET payment_intent_id=p_source->>'payment_intent_id',charge_id=p_source->>'charge_id',",
   " PERFORM private.fn_connect_test_verifier_arbitrage(o.id,l,p_source);\n UPDATE private.stripe_connect_avant_transfert SET payment_intent_id=p_source->>'payment_intent_id',charge_id=p_source->>'charge_id',"));
 alter('public.fn_connect_remboursement_demarrer(uuid,uuid)',s=>once(s,
   " allowed:=o.first_attempt_at IS NULL OR o.first_attempt_at>clock_timestamp()-interval '20 hours';",
   " PERFORM private.fn_connect_test_reserver_refund(o.id);\n allowed:=o.first_attempt_at IS NULL OR o.first_attempt_at>clock_timestamp()-interval '20 hours';"));
 // Les anciens RPC restent inchangés et fermés ; noms distincts uniquement
 // appelés par l'Edge staging après sa preuve d'identité serveur et Stripe TEST.
 for(const [sig,newName,guard] of [
  ['public.fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)','fn_stripe_payment_flow_claim_connect_test_v1','  PERFORM private.fn_connect_test_exiger_claim(p_facture_id,p_flow,p_mission_id);'],
  ['public.fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)','fn_stripe_webhook_event_claim_connect_test_v1','  PERFORM private.fn_connect_test_exiger_evenement(p_payload,p_livemode);'],
 ]){
  const s=source(migration,sig),old=sig.split('.')[1].split('(')[0];
  guards.push(`IF to_regprocedure(${quote(sig.replace(old,newName))}) IS NOT NULL THEN RAISE EXCEPTION 'CONNECT_TEST_RPC_PREEXISTS'; END IF;`);
  changes.push(replaceBody(s,once(s.body,condition,guard)).replace(`"${old}"`,`"${newName}"`));
  changes.push(`ALTER FUNCTION ${sig.replace(old,newName)} OWNER TO postgres;\nREVOKE ALL ON FUNCTION ${sig.replace(old,newName)} FROM PUBLIC,anon,authenticated,service_role;\nGRANT EXECUTE ON FUNCTION ${sig.replace(old,newName)} TO service_role;`);
 }
 const batch=source(migration,'public.fn_connect_remboursements_a_traiter(integer)');
 changes.push(replaceBody(batch,once(batch.body,
   'AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE',
   'AND private.fn_connect_test_operation_connue(o.id) AND EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities cap WHERE cap.id=p_capacity_id AND cap.operation_id=o.id)')).replace('public.fn_connect_remboursements_a_traiter(p_limit integer DEFAULT 2)', 'public.fn_connect_remboursements_test_a_traiter(p_limit integer,p_capacity_id uuid)'));
 changes.push(`ALTER FUNCTION public.fn_connect_remboursements_test_a_traiter(integer,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_connect_remboursements_test_a_traiter(integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_connect_remboursements_test_a_traiter(integer,uuid) TO service_role;`);
 return `-- CANDIDAT staging, sans allocation. Installation via job revu seulement.\nDO $source$ BEGIN\n${guards.join('\n')}\nEND $source$;\n${helpers}\n${changes.join('\n\n')}\nDO $inventory$ DECLARE p record; BEGIN
 FOR p IN SELECT oid,proname||'('||pg_catalog.oidvectortypes(proargtypes)||')' AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace
  AND proname IN('fn_connect_test_capacite_lire','fn_connect_test_checkout_autoriser','fn_connect_checkout_preparer',
    'fn_connect_avant_transfert_arbitrer','fn_connect_remboursement_demarrer','fn_stripe_payment_flow_claim_connect_test_v1',
    'fn_stripe_webhook_event_claim_connect_test_v1','fn_connect_remboursements_test_a_traiter')
 LOOP
  INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
  SELECT p.signature,'SERVICE_ONLY_REVOQUE',md5(prosrc),'Recette staging Connect TEST exacte ; gate generale fermee.',clock_timestamp() FROM pg_proc WHERE oid=p.oid
  ON CONFLICT(signature) DO UPDATE SET definition_md5=excluded.definition_md5,justification=excluded.justification,recense_le=excluded.recense_le
  WHERE private.security_definer_inventory.categorie='SERVICE_ONLY_REVOQUE';
  IF NOT FOUND THEN RAISE EXCEPTION 'CONNECT_TEST_INVENTORY'; END IF;
 END LOOP;
END $inventory$;\nDO $closed$ BEGIN
 IF EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities) OR EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE enabled)
 THEN RAISE EXCEPTION 'CONNECT_TEST_INSTALLATION_OPEN'; END IF;
END $closed$;\n`;
}

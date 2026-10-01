-- Supplément exclusivement staging, à appliquer par l'exécuteur revu après
-- contrôle de mejpriaetwgtcstbgfid. Aucune ligne de capacité n'est créée ici.
DO $preflight$
BEGIN
 IF current_user <> 'postgres' OR current_setting('server_version_num')::integer/10000 <> 17
   OR to_regclass('private.stripe_connect_test_capacities') IS NULL
   OR EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities)
   OR EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert)
   OR EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace IN('private'::regnamespace,'public'::regnamespace) AND proname LIKE 'fn_connect_test_%')
   OR (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
 THEN RAISE EXCEPTION 'CONNECT_TEST_INSTALLATION_REFUSED'; END IF;
END $preflight$;

ALTER TABLE private.stripe_connect_test_capacities ADD COLUMN claim_reserved_at timestamptz;

CREATE FUNCTION private.fn_connect_test_cohorte(p_e uuid,p_s uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $test$
 SELECT p_e<>p_s
   AND EXISTS(SELECT 1 FROM public.etablissements WHERE id=p_e AND est_compte_test IS TRUE)
   AND EXISTS(SELECT 1 FROM public.soignants WHERE id=p_s AND est_compte_test IS TRUE)
   AND NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id IN(p_e,p_s) AND est_compte_test IS DISTINCT FROM TRUE)
   AND NOT EXISTS(SELECT 1 FROM public.soignants WHERE id IN(p_e,p_s) AND est_compte_test IS DISTINCT FROM TRUE);
$test$;

CREATE FUNCTION private.fn_connect_test_scope(p_id uuid,p_creation boolean)
 RETURNS private.stripe_connect_test_capacities LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities;
BEGIN
 SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE id=p_id;
 IF c.protocol<>'CONNECT_STAGING_TEST_V1' OR c.project_ref<>'mejpriaetwgtcstbgfid'
   OR c.livemode IS DISTINCT FROM FALSE OR c.transfers_allowed IS DISTINCT FROM FALSE
   OR c.max_checkouts<>1 OR c.max_refunds<>1
   OR NOT private.fn_connect_test_cohorte(c.etablissement_id,c.soignant_id)
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
   OR (p_creation AND (NOT c.enabled OR c.revoked_at IS NOT NULL OR c.expires_at<=clock_timestamp()
      OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=c.soignant_id AND statut_compte::text='ACTIF' AND supprime_le IS NULL)
      OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=c.etablissement_id AND supprime_le IS NULL AND stripe_customer_id=c.customer_id)
      OR NOT EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE soignant_id=c.soignant_id AND statut='COMPLET' AND stripe_account_id=c.destination_id)))
 THEN RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_CLOSED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.factures_honoraires h
   JOIN public.factures f ON f.id=c.facture_commission_id
   JOIN public.missions m ON m.id=c.mission_id
   WHERE h.id=c.facture_honoraire_id AND h.mission_id=m.id AND h.etablissement_id=c.etablissement_id AND h.soignant_id=c.soignant_id
     AND h.type_document='FACTURE' AND f.type_document='FACTURE' AND f.facture_honoraire_id=h.id
     AND f.mission_id=m.id AND f.etablissement_id=c.etablissement_id
     AND m.etablissement_id=c.etablissement_id AND m.soignant_assigne_id=c.soignant_id AND m.type_contrat_applique::text='LIBERAL'
     AND round(h.montant_ttc*100)::bigint=c.soignant_cents AND round(f.montant_ttc*100)::bigint=c.commission_cents)
 THEN RAISE EXCEPTION 'CONNECT_TEST_DOCUMENTS_CHANGED'; END IF;
 RETURN c;
END $test$;

-- Une ligne n'autorise jamais un autre op, objet ou mode. Les constats restent
-- accessibles après expiration/révocation, sous la filiation immuable.
CREATE FUNCTION private.fn_connect_test_operation_connue(p_operation_id uuid)
 RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities; o private.stripe_connect_avant_transfert;
BEGIN
 SELECT * INTO c FROM private.stripe_connect_test_capacities WHERE operation_id=p_operation_id;
 IF NOT FOUND THEN RETURN FALSE; END IF;
 c:=private.fn_connect_test_scope(c.id,false);
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_operation_id;
 IF o.mission_id IS DISTINCT FROM c.mission_id OR o.etablissement_id IS DISTINCT FROM c.etablissement_id OR o.soignant_id IS DISTINCT FROM c.soignant_id
   OR o.facture_honoraire_id IS DISTINCT FROM c.facture_honoraire_id OR o.facture_commission_id IS DISTINCT FROM c.facture_commission_id
   OR o.customer_id IS DISTINCT FROM c.customer_id OR o.destination_id IS DISTINCT FROM c.destination_id
   OR o.soignant_cents IS DISTINCT FROM c.soignant_cents OR o.commission_cents IS DISTINCT FROM c.commission_cents OR o.total_cents IS DISTINCT FROM c.total_cents
   OR o.livemode IS TRUE OR o.orientation='TRANSFER' OR c.checkout_reserved_at IS NULL
 THEN RAISE EXCEPTION 'CONNECT_TEST_OPERATION_CHANGED'; END IF;
 RETURN TRUE;
END $test$;

CREATE FUNCTION private.fn_connect_test_creation_autorisee(p_operation_id uuid)
 RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities;
BEGIN
 IF NOT private.fn_connect_test_operation_connue(p_operation_id) THEN RETURN FALSE; END IF;
 SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE operation_id=p_operation_id;
 -- Une fermeture ferme la création, pas les lectures de constats existants.
 IF NOT c.enabled OR c.revoked_at IS NOT NULL OR c.expires_at<=clock_timestamp() THEN RETURN FALSE; END IF;
 c:=private.fn_connect_test_scope(c.id,true);
 RETURN TRUE;
END $test$;

CREATE FUNCTION public.fn_connect_test_capacite_lire(p_facture_honoraire_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT * INTO c FROM private.stripe_connect_test_capacities WHERE facture_honoraire_id=p_facture_honoraire_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 c:=private.fn_connect_test_scope(c.id,false);
 RETURN to_jsonb(c)||jsonb_build_object(
   'session_id',(SELECT session_id FROM private.stripe_connect_avant_transfert WHERE id=c.operation_id),
   'trace_id',(SELECT trace_id FROM private.stripe_connect_avant_transfert WHERE id=c.operation_id));
END $test$;

-- Appelé après les verrous métier et l'insertion de l'opération. Jamais avant
-- mission. Un concurrent ne peut consommer une nouvelle clé sur la même FH.
CREATE FUNCTION private.fn_connect_test_reserver_checkout(p_operation_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities; o private.stripe_connect_avant_transfert;
BEGIN
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_operation_id;
 SELECT * INTO c FROM private.stripe_connect_test_capacities WHERE facture_honoraire_id=o.facture_honoraire_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 c:=private.fn_connect_test_scope(c.id,true);
 IF c.operation_id IS NOT NULL AND c.operation_id IS DISTINCT FROM o.id THEN RAISE EXCEPTION 'CONNECT_TEST_CHECKOUT_BUDGET'; END IF;
 IF o.session_id IS NOT NULL OR o.trace_id IS NOT NULL OR o.orientation IS NOT NULL OR o.livemode IS NOT NULL
 THEN RAISE EXCEPTION 'CONNECT_TEST_NO_HISTORICAL_ADOPTION'; END IF;
 UPDATE private.stripe_connect_test_capacities SET operation_id=o.id,checkout_reserved_at=COALESCE(checkout_reserved_at,clock_timestamp()) WHERE id=c.id;
 IF NOT private.fn_connect_test_operation_connue(o.id) THEN RAISE EXCEPTION 'CONNECT_TEST_CHECKOUT_SCOPE'; END IF;
END $test$;

CREATE FUNCTION private.fn_connect_test_reserver_refund(p_operation_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities; o private.stripe_connect_avant_transfert;
BEGIN
 SELECT * INTO c FROM private.stripe_connect_test_capacities WHERE operation_id=p_operation_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 c:=private.fn_connect_test_scope(c.id,true);
 IF NOT private.fn_connect_test_operation_connue(p_operation_id) THEN RAISE EXCEPTION 'CONNECT_TEST_REFUND_SCOPE'; END IF;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_operation_id;
 IF o.orientation IS DISTINCT FROM 'REFUND' OR o.livemode IS DISTINCT FROM FALSE OR o.litige_id IS NULL
   OR o.refund_id IS NOT NULL OR o.refund_status<>'READY'
 THEN RAISE EXCEPTION 'CONNECT_TEST_REFUND_BUDGET'; END IF;
 -- Le même op conserve la même clé d'idempotence Stripe, même après timeout.
 UPDATE private.stripe_connect_test_capacities SET refund_reserved_at=COALESCE(refund_reserved_at,clock_timestamp()) WHERE id=c.id;
END $test$;

CREATE FUNCTION private.fn_connect_test_verifier_arbitrage(p_operation_id uuid,p_litige_id uuid,p_source jsonb)
 RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
BEGIN
 IF NOT private.fn_connect_test_operation_connue(p_operation_id) THEN RETURN; END IF;
 IF p_source->'livemode' IS DISTINCT FROM 'false'::jsonb OR p_litige_id IS NULL
   OR NOT EXISTS(SELECT 1 FROM public.litiges l JOIN private.stripe_connect_avant_transfert o ON o.id=p_operation_id
     WHERE l.id=p_litige_id AND l.facture_id=o.facture_honoraire_id AND l.mission_id=o.mission_id
       AND l.statut IN('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS','REVUE_ADMIN'))
 THEN RAISE EXCEPTION 'CONNECT_TEST_TRANSFER_FORBIDDEN'; END IF;
END $test$;

-- Autorisation courte juste avant le POST Checkout. Un POST déjà autorisé peut
-- être en vol : révoquer implique ensuite drain et constat, pas une annulation.
CREATE FUNCTION public.fn_connect_test_checkout_autoriser(p_operation_id uuid,p_server_sha text,p_manifest_sha256 text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $test$
DECLARE o private.stripe_connect_avant_transfert; c private.stripe_connect_test_capacities;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE operation_id=o.id FOR UPDATE;
 c:=private.fn_connect_test_scope(c.id,true);
 IF c.server_sha IS DISTINCT FROM p_server_sha OR c.source_manifest_sha256 IS DISTINCT FROM p_manifest_sha256
   OR NOT private.fn_connect_test_operation_connue(o.id) OR o.orientation IS NOT NULL OR o.session_id IS NOT NULL
 THEN RAISE EXCEPTION 'CONNECT_TEST_CHECKOUT_CLOSED'; END IF;
 RETURN jsonb_build_object('operation_id',o.id,'allowed',true);
END $test$;

-- Précondition du claim : lecture seulement, afin de conserver l'ordre du
-- moteur métier et de ne pas tenir la capacité pendant l'attente de mission.
CREATE FUNCTION private.fn_connect_test_exiger_claim(p_facture_id uuid,p_flow text,p_mission_id uuid)
 RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
DECLARE c private.stripe_connect_test_capacities;
BEGIN
 IF p_flow IS DISTINCT FROM 'CONNECT_INVOICE' OR p_mission_id IS NOT NULL THEN RAISE EXCEPTION 'CONNECT_TEST_INVOICE_REQUIRED'; END IF;
 SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE facture_commission_id=p_facture_id;
 c:=private.fn_connect_test_scope(c.id,true);
 IF c.claim_reserved_at IS NULL AND EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='FACTURE:'||p_facture_id::text)
 THEN RAISE EXCEPTION 'CONNECT_TEST_NO_HISTORICAL_CLAIM'; END IF;
 IF c.claim_reserved_at IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='FACTURE:'||p_facture_id::text)
 THEN RAISE EXCEPTION 'CONNECT_TEST_CLAIM_SCOPE'; END IF;
 IF c.operation_id IS NOT NULL AND NOT private.fn_connect_test_operation_connue(c.operation_id)
 THEN RAISE EXCEPTION 'CONNECT_TEST_CLAIM_SCOPE'; END IF;
 IF EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims f
   WHERE f.resource_key='FACTURE:'||p_facture_id::text
   AND (f.flow IS DISTINCT FROM 'CONNECT_INVOICE' OR f.owner_token IS DISTINCT FROM 'connect-invoice:'||c.facture_honoraire_id::text
     OR f.stripe_checkout_session_id IS DISTINCT FROM (SELECT session_id FROM private.stripe_connect_avant_transfert WHERE id=c.operation_id)
     OR f.stripe_payment_intent_id IS NOT NULL))
 THEN RAISE EXCEPTION 'CONNECT_TEST_CLAIM_SCOPE'; END IF;
END $test$;

CREATE FUNCTION private.fn_connect_test_exiger_evenement(p_payload jsonb,p_livemode boolean)
 RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $test$
DECLARE o private.stripe_connect_avant_transfert;
BEGIN
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE session_id=p_payload#>>'{object,id}';
 IF p_livemode IS DISTINCT FROM FALSE OR p_payload#>'{object,livemode}' IS DISTINCT FROM 'false'::jsonb
   OR p_payload#>>'{object,metadata,connect_operation_id}' IS DISTINCT FROM o.id::text
   OR NOT private.fn_connect_test_operation_connue(o.id) THEN RAISE EXCEPTION 'CONNECT_TEST_EVENT_SCOPE'; END IF;
END $test$;

-- Aucun droit d'allocation via le Data API. Une activation opérateur sera une
-- transaction revue distincte, au même verrou staging, avec identité complète.
DO $acl$
DECLARE x record;
BEGIN
 FOR x IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN('private','public') AND p.proname LIKE 'fn_connect_test_%'
 LOOP
   EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',x.signature);
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',x.signature);
   IF x.signature::text LIKE 'fn_connect_test_capacite_lire(%' OR x.signature::text LIKE 'fn_connect_test_checkout_autoriser(%'
     OR x.signature::text LIKE 'public.fn_connect_test_capacite_lire(%' OR x.signature::text LIKE 'public.fn_connect_test_checkout_autoriser(%'
   THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',x.signature); END IF;
 END LOOP;
END $acl$;

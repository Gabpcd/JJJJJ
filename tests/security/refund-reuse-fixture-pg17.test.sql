-- LOCAL PG17 ONLY; exact preparation DO sha256 d44cf3fe7618a292ca2470605d91b536a7f44f753ad223ed45657249e01c7b2a
-- Reviewed synthetic seed sha256 920b4e4654040222feab487aec4b9d705f9eb42ee908823169cc78f1a0da8de5; no provider evidence is claimed.
BEGIN;
SET LOCAL row_security=off;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='3s';
SET LOCAL TIME ZONE 'UTC';
DO $local$
BEGIN
 IF current_database()<>'jolene_candidatures_pg17_test' OR inet_server_addr() IS NOT NULL
  OR session_user<>'postgres' OR current_user<>session_user
  OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
  OR current_setting('cron.database_name')<>'jolene_candidatures_pg17_test'
  OR current_setting('cron.launch_active_jobs')<>'off' OR current_setting('max_worker_processes')<>'0'
  OR EXISTS(SELECT 1 FROM pg_stat_activity WHERE backend_type IN ('pg_cron launcher','pg_cron worker','pg_net worker'))
 THEN RAISE EXCEPTION 'QUALIFICATION_LOCAL_CONTEXT_REQUIRED'; END IF;
END $local$;
SELECT pg_advisory_xact_lock(184731,1017);
-- BEGIN REVIEWED SYNTHETIC SEED (also rolled back)
-- PG17_SYNTHETIC_ONLY: all rows below are local fixtures, not an observed provider history.
-- No credentials, Auth API, identity records, passwords or sessions. No real PDF/XML storage objects.
DO $empty$
BEGIN
 IF EXISTS(SELECT 1 FROM auth.users) OR EXISTS(SELECT 1 FROM public.soignants)
  OR EXISTS(SELECT 1 FROM public.etablissements) OR EXISTS(SELECT 1 FROM public.missions)
  OR EXISTS(SELECT 1 FROM public.equipe_admin) OR EXISTS(SELECT 1 FROM vault.secrets)
  OR EXISTS(SELECT 1 FROM net.http_request_queue) OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal AND tgenabled<>'D' AND (tgtype::integer & 20)<>0)
 THEN RAISE EXCEPTION 'WITNESS_EMPTY_FULL_RESTORE_REQUIRED'; END IF;
 -- Public project origin only, deliberately no service_role_key/cron_key. No HTTP credential exists.
 PERFORM vault.create_secret('https://mejpriaetwgtcstbgfid.supabase.co','supabase_url','PG17_SYNTHETIC_ONLY public URL; no credential');
END $empty$;
-- Fragment staging uniquement. Installation vide ; aucun consommateur ni activation.
-- Le projet est prouvé par l'exécuteur Management avant cet appel, pas par ce CHECK.
DO $capacity_preflight$
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17
   OR to_regclass('private.stripe_connect_test_capacities') IS NOT NULL
   OR to_regtype('private.stripe_connect_test_capacities') IS NOT NULL
   OR (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
   OR EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert) THEN
   RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_INSTALLATION_REFUSED';
 END IF;
END $capacity_preflight$;
CREATE TABLE private.stripe_connect_test_capacities (
 id uuid PRIMARY KEY,
 protocol text NOT NULL CHECK(protocol='CONNECT_STAGING_TEST_V1'),
 project_ref text NOT NULL CHECK(project_ref='mejpriaetwgtcstbgfid'),
 run_id text NOT NULL UNIQUE CHECK(run_id ~ '^f1-[A-Za-z0-9-]{1,80}$'),
 server_sha text NOT NULL CHECK(server_sha ~ '^[a-f0-9]{40}$'),
 ui_sha text NOT NULL CHECK(ui_sha ~ '^[a-f0-9]{40}$'),
 source_manifest_sha256 text NOT NULL CHECK(source_manifest_sha256 ~ '^[a-f0-9]{64}$'),
 enabled boolean NOT NULL DEFAULT false,
 installed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
 soignant_id uuid NOT NULL REFERENCES public.soignants(id),
 mission_id uuid NOT NULL REFERENCES public.missions(id),
 facture_honoraire_id uuid NOT NULL UNIQUE REFERENCES public.factures_honoraires(id),
 facture_commission_id uuid NOT NULL UNIQUE REFERENCES public.factures(id),
 platform_account_id text NOT NULL CHECK(platform_account_id ~ '^acct_[A-Za-z0-9]+$'),
 customer_id text NOT NULL CHECK(customer_id ~ '^cus_[A-Za-z0-9]+$'),
 destination_id text NOT NULL CHECK(destination_id ~ '^acct_[A-Za-z0-9]+$'),
 livemode boolean NOT NULL DEFAULT false CHECK(livemode IS FALSE),
 soignant_cents bigint NOT NULL CHECK(soignant_cents>0 AND soignant_cents<=9007199254740991),
 commission_cents bigint NOT NULL CHECK(commission_cents>0 AND commission_cents<=9007199254740991),
 total_cents bigint NOT NULL CHECK(total_cents>0 AND total_cents<=9007199254740991),
 max_checkouts smallint NOT NULL DEFAULT 1 CHECK(max_checkouts=1),
 max_refunds smallint NOT NULL DEFAULT 1 CHECK(max_refunds=1),
 transfers_allowed boolean NOT NULL DEFAULT false CHECK(transfers_allowed IS FALSE),
 operation_id uuid UNIQUE REFERENCES private.stripe_connect_avant_transfert(id),
 checkout_reserved_at timestamptz,
 refund_reserved_at timestamptz,
 revoked_at timestamptz,
 CHECK(expires_at>installed_at),
 CHECK(etablissement_id<>soignant_id),
 CHECK(facture_honoraire_id<>facture_commission_id),
 CHECK(soignant_cents+commission_cents=total_cents),
 CHECK((checkout_reserved_at IS NULL)=(operation_id IS NULL)),
 CHECK(refund_reserved_at IS NULL OR checkout_reserved_at IS NOT NULL),
 CHECK(revoked_at IS NULL OR enabled IS FALSE)
);
ALTER TABLE private.stripe_connect_test_capacities OWNER TO postgres;
ALTER TABLE private.stripe_connect_test_capacities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.stripe_connect_test_capacities FROM PUBLIC,anon,authenticated,service_role;
DO $capacity_postflight$
DECLARE v_role text;
BEGIN
 IF EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities)
   OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
     WHERE c.oid='private.stripe_connect_test_capacities'::regclass AND (a.grantee<>c.relowner OR a.grantor<>c.relowner))
   OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.stripe_connect_test_capacities'::regclass)
   OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.stripe_connect_test_capacities'::regclass AND NOT tgisinternal)
   OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.stripe_connect_test_capacities'::regclass
      AND relowner='postgres'::regrole AND relrowsecurity) THEN
   RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_POSTFLIGHT';
 END IF;
 FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_table_privilege(v_role,'private.stripe_connect_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
     RAISE EXCEPTION 'CONNECT_TEST_CAPACITY_ACL'; END IF;
 END LOOP;
END $capacity_postflight$;

-- CANDIDAT staging, sans allocation. Installation via job revu seulement.
DO $source$ BEGIN
IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('private.fn_connect_operation_verrouiller(uuid)')) IS DISTINCT FROM 'daad06e3d7fa97e32e73a5d306a22c1e' THEN RAISE EXCEPTION 'CONNECT_TEST_SOURCE_DRIFT (private.fn_connect_operation_verrouiller(uuid))'; END IF;
IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('private.fn_connect_creation_autorisee(uuid)')) IS DISTINCT FROM 'b785cd6184643b4f5c96831320a899f4' THEN RAISE EXCEPTION 'CONNECT_TEST_SOURCE_DRIFT (private.fn_connect_creation_autorisee(uuid))'; END IF;
IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fn_connect_checkout_preparer(uuid,uuid,text)')) IS DISTINCT FROM 'a35da900f76db80473b197d798422f39' THEN RAISE EXCEPTION 'CONNECT_TEST_SOURCE_DRIFT (public.fn_connect_checkout_preparer(uuid,uuid,text))'; END IF;
IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fn_connect_avant_transfert_arbitrer(uuid,uuid,jsonb)')) IS DISTINCT FROM '50e0e5e382878ec1e0013ceb4b87a843' THEN RAISE EXCEPTION 'CONNECT_TEST_SOURCE_DRIFT (public.fn_connect_avant_transfert_arbitrer(uuid,uuid,jsonb))'; END IF;
IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fn_connect_remboursement_demarrer(uuid,uuid)')) IS DISTINCT FROM '4c43f80bab2ab55c2b2e7d0dc8cf4af2' THEN RAISE EXCEPTION 'CONNECT_TEST_SOURCE_DRIFT (public.fn_connect_remboursement_demarrer(uuid,uuid))'; END IF;
IF to_regprocedure('public.fn_stripe_payment_flow_claim_connect_test_v1(text,text,uuid,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'CONNECT_TEST_RPC_PREEXISTS'; END IF;
IF to_regprocedure('public.fn_stripe_webhook_event_claim_connect_test_v1(text,text,jsonb,text,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'CONNECT_TEST_RPC_PREEXISTS'; END IF;
END $source$;
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

CREATE OR REPLACE FUNCTION private.fn_connect_operation_verrouiller(p_id uuid)
 RETURNS private.stripe_connect_avant_transfert LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; m public.missions; h public.factures_honoraires; c public.factures; s public.stripe_transfers;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_id;
 SELECT * INTO STRICT m FROM public.missions WHERE id=o.mission_id FOR UPDATE;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_id;
 IF o.mission_id IS DISTINCT FROM m.id THEN RAISE EXCEPTION 'CONNECT_OPERATION_CHANGED'; END IF;
 IF o.trace_id IS NOT NULL THEN SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=o.trace_id FOR UPDATE; END IF;
 SELECT * INTO STRICT h FROM public.factures_honoraires WHERE id=o.facture_honoraire_id FOR UPDATE;
 SELECT * INTO STRICT c FROM public.factures WHERE id=o.facture_commission_id FOR UPDATE;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_id FOR UPDATE;
 IF m.etablissement_id IS DISTINCT FROM o.etablissement_id OR m.soignant_assigne_id IS DISTINCT FROM o.soignant_id
   OR m.type_contrat_applique::text IS DISTINCT FROM 'LIBERAL'
   OR h.mission_id IS DISTINCT FROM m.id OR h.etablissement_id IS DISTINCT FROM o.etablissement_id OR h.soignant_id IS DISTINCT FROM o.soignant_id
   OR c.mission_id IS DISTINCT FROM m.id OR c.facture_honoraire_id IS DISTINCT FROM h.id OR c.etablissement_id IS DISTINCT FROM o.etablissement_id
   OR c.type_document IS DISTINCT FROM 'FACTURE'
   OR round(h.montant_ttc*100)::bigint IS DISTINCT FROM o.soignant_cents
   OR round(c.montant_ttc*100)::bigint IS DISTINCT FROM o.commission_cents
   OR (NOT private.fn_connect_test_operation_connue(o.id) AND (
     NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=o.soignant_id AND est_compte_test IS FALSE)
     OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=o.etablissement_id AND est_compte_test IS FALSE)
     OR EXISTS(SELECT 1 FROM public.soignants WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)
     OR EXISTS(SELECT 1 FROM public.etablissements WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)))
 THEN RAISE EXCEPTION 'CONNECT_OPERATION_IDENTITY_OR_COHORT'; END IF;
 IF o.trace_id IS NOT NULL AND (s.mission_id IS DISTINCT FROM m.id OR s.etablissement_id IS DISTINCT FROM o.etablissement_id
   OR s.soignant_id IS DISTINCT FROM o.soignant_id OR s.facture_honoraire_id IS DISTINCT FROM h.id OR s.facture_id IS DISTINCT FROM c.id
   OR s.stripe_checkout_session_id IS DISTINCT FROM o.session_id
   OR round(s.montant_soignant*100)::bigint IS DISTINCT FROM o.soignant_cents
   OR round(s.montant_commission*100)::bigint IS DISTINCT FROM o.commission_cents
   OR round(s.montant_total*100)::bigint IS DISTINCT FROM o.total_cents
   OR (o.payment_intent_id IS NOT NULL AND s.stripe_payment_intent_id IS NOT NULL AND s.stripe_payment_intent_id IS DISTINCT FROM o.payment_intent_id)
   OR (o.charge_id IS NOT NULL AND s.stripe_charge_id IS NOT NULL AND s.stripe_charge_id IS DISTINCT FROM o.charge_id))
 THEN RAISE EXCEPTION 'CONNECT_TRACE_IDENTITY'; END IF;
 RETURN o;
END;$f$;

CREATE OR REPLACE FUNCTION private.fn_connect_creation_autorisee(p_id uuid)
 RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$
 SELECT EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert o
   JOIN public.soignants s ON s.id=o.soignant_id JOIN public.etablissements e ON e.id=o.etablissement_id
   JOIN public.stripe_connect_onboarding b ON b.soignant_id=o.soignant_id
   WHERE o.id=p_id AND ((private.fn_connect_protocole_ouvert() AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE) OR private.fn_connect_test_creation_autorisee(o.id))
     AND s.supprime_le IS NULL AND e.supprime_le IS NULL AND s.statut_compte::text='ACTIF'
     AND e.stripe_customer_id=o.customer_id AND b.statut='COMPLET' AND b.stripe_account_id=o.destination_id);
$f$;

CREATE OR REPLACE FUNCTION public.fn_connect_checkout_preparer(p_facture_honoraire_id uuid,p_facture_commission_id uuid,p_cle_tentative text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE h public.factures_honoraires; c public.factures; m public.missions; o private.stripe_connect_avant_transfert;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT * INTO STRICT h FROM public.factures_honoraires WHERE id=p_facture_honoraire_id;
 SELECT * INTO STRICT m FROM public.missions WHERE id=h.mission_id FOR UPDATE;
 SELECT * INTO o FROM private.stripe_connect_avant_transfert WHERE attempt_key=p_cle_tentative;
 IF FOUND THEN
   IF o.mission_id IS DISTINCT FROM m.id OR o.facture_honoraire_id IS DISTINCT FROM p_facture_honoraire_id
     OR o.facture_commission_id IS DISTINCT FROM p_facture_commission_id THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONFLICT'; END IF;
   -- Rejeu lié : prendre ST AVANT FH/C, pas depuis un appel sous leurs verrous.
   o:=private.fn_connect_operation_verrouiller(o.id);
 END IF;
 SELECT * INTO STRICT h FROM public.factures_honoraires WHERE id=p_facture_honoraire_id FOR UPDATE;
 SELECT * INTO STRICT c FROM public.factures WHERE id=p_facture_commission_id FOR UPDATE;
 IF h.statut IS NULL OR h.statut NOT IN('EMISE','EN_RETARD') OR c.statut IS NULL OR c.statut NOT IN('EMISE','EN_RETARD') OR h.mission_id IS DISTINCT FROM m.id
   OR h.stripe_payment_intent_id IS NOT NULL OR c.stripe_payment_intent_id IS NOT NULL
   OR c.facture_honoraire_id IS DISTINCT FROM h.id OR c.mission_id IS DISTINCT FROM m.id OR c.type_document IS DISTINCT FROM 'FACTURE'
   OR m.type_contrat_applique::text IS DISTINCT FROM 'LIBERAL' OR m.statut IS NULL OR m.statut NOT IN('EN_COURS','TERMINEE')
   OR (m.statut='EN_COURS' AND (h.est_facture_finale_mission IS DISTINCT FROM FALSE OR h.periode_fin IS NULL OR h.periode_fin>=current_date))
   OR NOT EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='FACTURE:'||c.id::text AND flow='CONNECT_INVOICE')
 THEN RAISE EXCEPTION 'CONNECT_ADMISSION_NOT_PAYABLE'; END IF;
 IF o.id IS NULL THEN
 INSERT INTO private.stripe_connect_avant_transfert(attempt_key,mission_id,etablissement_id,soignant_id,facture_honoraire_id,
   facture_commission_id,customer_id,destination_id,soignant_cents,commission_cents,total_cents)
 SELECT p_cle_tentative,m.id,m.etablissement_id,m.soignant_assigne_id,h.id,c.id,e.stripe_customer_id,onb.stripe_account_id,
   round(h.montant_ttc*100)::bigint,round(c.montant_ttc*100)::bigint,round((h.montant_ttc+c.montant_ttc)*100)::bigint
 FROM public.etablissements e JOIN public.stripe_connect_onboarding onb ON onb.soignant_id=m.soignant_assigne_id AND onb.statut='COMPLET'
 WHERE e.id=m.etablissement_id ON CONFLICT(attempt_key) DO NOTHING;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE attempt_key=p_cle_tentative;
 IF o.facture_honoraire_id IS DISTINCT FROM h.id OR o.facture_commission_id IS DISTINCT FROM c.id THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONFLICT'; END IF;
 PERFORM private.fn_connect_test_reserver_checkout(o.id);
 -- Une insertion neuve a trace_id NULL et n'acquiert donc aucune ST tardive.
 IF o.trace_id IS NOT NULL THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONCURRENT_LINK'; END IF;
 o:=private.fn_connect_operation_verrouiller(o.id);
 END IF;
 IF NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
 RETURN jsonb_build_object('operation_id',o.id,'facture_honoraire_id',h.id,'facture_commission_id',c.id);
END;$f$;

CREATE OR REPLACE FUNCTION public.fn_connect_avant_transfert_arbitrer(p_operation_id uuid,p_trace_id uuid,p_source jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; s public.stripe_transfers; l uuid;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 IF o.trace_id IS DISTINCT FROM p_trace_id OR p_source IS NULL
   OR (to_jsonb(o)-ARRAY['id','attempt_key','trace_id','payment_intent_id','charge_id','livemode','orientation','litige_id','refund_id','refund_status','first_attempt_at','owner_token','lease_until','next_read_at','review_code','failure_balance_transaction_id','created_at','succeeded_at'])
     IS DISTINCT FROM (p_source-ARRAY['payment_intent_id','charge_id','livemode'])
   OR jsonb_typeof(p_source->'livemode') IS DISTINCT FROM 'boolean'
   OR COALESCE(p_source->>'payment_intent_id','')!~'^pi_[A-Za-z0-9_]+$' OR COALESCE(p_source->>'charge_id','')!~'^ch_[A-Za-z0-9_]+$'
 THEN RAISE EXCEPTION 'CONNECT_ARBITRATION_SOURCE'; END IF;
 IF o.orientation IS NOT NULL THEN
   IF o.orientation='TRANSFER' AND NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
   IF o.payment_intent_id IS DISTINCT FROM p_source->>'payment_intent_id' OR o.charge_id IS DISTINCT FROM p_source->>'charge_id'
     OR o.livemode IS DISTINCT FROM (p_source->>'livemode')::boolean THEN RAISE EXCEPTION 'CONNECT_ARBITRATION_CONFLICT'; END IF;
   RETURN to_jsonb(o)-'attempt_key'-'owner_token'-'lease_until';
 END IF;
 IF NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
 SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id;
 IF (s.stripe_payment_intent_id IS NOT NULL AND s.stripe_payment_intent_id IS DISTINCT FROM p_source->>'payment_intent_id')
   OR (s.stripe_charge_id IS NOT NULL AND s.stripe_charge_id IS DISTINCT FROM p_source->>'charge_id')
   OR s.stripe_transfer_id IS NOT NULL OR s.statut IS NULL OR s.statut NOT IN('EN_ATTENTE','ECHOUE','CHARGE_REUSSI')
   OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=o.mission_id AND (facture_honoraire_id=o.facture_honoraire_id OR facture_honoraire_id IS NULL)
     AND statut IN('DECLARE','CONFIRME','CONTESTE','RESOLU'))
   OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=o.mission_id AND statut<>'REMBOURSE')
   OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=o.facture_honoraire_id AND statut IN('EMISE','EN_RETARD'))
   OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=o.facture_commission_id AND statut IN('EMISE','EN_RETARD'))
 THEN RAISE EXCEPTION 'CONNECT_ARBITRATION_ALREADY_MOVED'; END IF;
 -- Observation du litige au moment de l'arbitrage, PAS de verrou litige après mission.
 SELECT id INTO l FROM public.litiges WHERE mission_id=o.mission_id AND (facture_id=o.facture_honoraire_id OR facture_id IS NULL)
   AND statut IN('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS','REVUE_ADMIN') ORDER BY id LIMIT 1;
 PERFORM private.fn_connect_test_verifier_arbitrage(o.id,l,p_source);
 UPDATE private.stripe_connect_avant_transfert SET payment_intent_id=p_source->>'payment_intent_id',charge_id=p_source->>'charge_id',
   livemode=(p_source->>'livemode')::boolean,orientation=CASE WHEN l IS NULL THEN 'TRANSFER' ELSE 'REFUND' END,litige_id=l
 WHERE id=o.id RETURNING * INTO o;
 IF o.orientation='REFUND' THEN
   UPDATE public.stripe_transfers SET statut='EN_ATTENTE',erreur='Remboursement avant transfert en cours de rapprochement'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL;
 END IF;
 RETURN to_jsonb(o)-'attempt_key'-'owner_token'-'lease_until';
END;$f$;

CREATE OR REPLACE FUNCTION public.fn_connect_remboursement_demarrer(p_operation_id uuid,p_owner_token uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; allowed boolean; a jsonb;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 IF o.orientation IS DISTINCT FROM 'REFUND' OR p_owner_token IS NULL OR o.owner_token IS DISTINCT FROM p_owner_token OR o.lease_until IS NULL OR o.lease_until<=clock_timestamp()
   OR o.refund_id IS NOT NULL OR o.refund_status<>'READY' THEN RAISE EXCEPTION 'CONNECT_REFUND_LEASE'; END IF;
 IF NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
 PERFORM private.fn_connect_test_reserver_refund(o.id);
 allowed:=o.first_attempt_at IS NULL OR o.first_attempt_at>clock_timestamp()-interval '20 hours';
 UPDATE private.stripe_connect_avant_transfert SET first_attempt_at=COALESCE(first_attempt_at,clock_timestamp()),
   review_code=CASE WHEN allowed THEN review_code ELSE 'CREATE_WINDOW_CLOSED' END,
   refund_status=CASE WHEN allowed THEN refund_status ELSE 'REVIEW' END,
   owner_token=CASE WHEN allowed THEN owner_token ELSE NULL END,
   lease_until=CASE WHEN allowed THEN lease_until ELSE NULL END WHERE id=o.id;
 IF NOT allowed THEN
   UPDATE public.stripe_transfers SET statut='ECHOUE',erreur='Résultat du remboursement à rapprocher ; aucun nouvel appel automatique autorisé'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL;
   a:=public.fn_ecrire_audit_safe(o.etablissement_id,'SYSTEME','ADMIN_ACTION','factures_honoraires',o.facture_honoraire_id,NULL,
     jsonb_build_object('evenement','CONNECT_REMBOURSEMENT_INCIDENT','operation_id',o.id,'incident','CREATE_WINDOW_CLOSED'),NULL,'connect-pretransfer');
   IF (a->>'success')::boolean IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'CONNECT_REFUND_AUDIT_FAILED'; END IF;
 END IF;
 RETURN jsonb_build_object('operation_id',o.id,'owner_token',p_owner_token,'create_allowed',allowed);
END;$f$;

CREATE OR REPLACE FUNCTION "public"."fn_stripe_payment_flow_claim_connect_test_v1"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid" DEFAULT NULL::"uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_resources text[];
  v_resource text;
  v_conflict public.stripe_payment_flow_claims%ROWTYPE;
  v_session_ids text[];
  v_intent_ids text[];
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  IF p_flow IS NULL OR p_flow NOT IN ('CONNECT_MISSION','CONNECT_INVOICE') THEN
    RAISE EXCEPTION 'CONNECT_PROTOCOL_SCOPE' USING ERRCODE='22023';
  END IF;
  IF COALESCE(NULLIF(auth.jwt()->>'role',''),NULLIF(current_setting('request.jwt.claim.role',true),''),'')<>'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501';
  END IF;

  IF p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION', 'CONNECT_INVOICE')
     OR NULLIF(btrim(p_owner_token), '') IS NULL
     OR ((p_facture_id IS NULL) = (p_mission_id IS NULL)) THEN
    RAISE EXCEPTION 'Paramètres de claim Stripe invalides' USING ERRCODE = '22023';
  END IF;

  IF p_facture_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.factures f
      WHERE f.id = p_facture_id
        AND f.type_document = 'FACTURE'
        AND f.statut <> 'ANNULEE'
    ) THEN
      RAISE EXCEPTION 'Facture de claim introuvable ou non payable' USING ERRCODE = 'P0002';
    END IF;
    IF p_flow = 'CONNECT_INVOICE' THEN
      v_resources := ARRAY['FACTURE:' || p_facture_id::text];
    ELSE
      SELECT array_agg(DISTINCT r.resource_key ORDER BY r.resource_key)
      INTO v_resources
      FROM (
        SELECT 'FACTURE:' || p_facture_id::text AS resource_key
        UNION ALL
        SELECT 'MISSION:' || f.mission_id::text
        FROM public.factures f
        WHERE f.id = p_facture_id AND f.mission_id IS NOT NULL
        UNION ALL
        SELECT 'MISSION:' || m.id::text
        FROM public.missions m
        WHERE m.facture_id = p_facture_id
      ) r;
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.missions m WHERE m.id = p_mission_id) THEN
      RAISE EXCEPTION 'Mission de claim introuvable' USING ERRCODE = 'P0002';
    END IF;
    v_resources := ARRAY['MISSION:' || p_mission_id::text];
  END IF;

  FOREACH v_resource IN ARRAY v_resources LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(v_resource, 0));
  END LOOP;
  PERFORM private.fn_connect_test_exiger_claim(p_facture_id,p_flow,p_mission_id);

  SELECT c.* INTO v_conflict
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources)
    AND (c.flow <> p_flow OR c.owner_token <> p_owner_token)
  ORDER BY c.resource_key
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'acquired', false,
      'flow', v_conflict.flow,
      'owner_token', v_conflict.owner_token,
      'resources', v_resources,
      'stripe_checkout_session_id', v_conflict.stripe_checkout_session_id,
      'stripe_payment_intent_id', v_conflict.stripe_payment_intent_id
    );
  END IF;

  INSERT INTO public.stripe_payment_flow_claims (resource_key, flow, owner_token)
  SELECT r.resource_key, p_flow, p_owner_token
  FROM unnest(v_resources) AS r(resource_key)
  ON CONFLICT (resource_key) DO NOTHING;

  SELECT
    array_agg(DISTINCT c.stripe_checkout_session_id)
      FILTER (WHERE c.stripe_checkout_session_id IS NOT NULL),
    array_agg(DISTINCT c.stripe_payment_intent_id)
      FILTER (WHERE c.stripe_payment_intent_id IS NOT NULL)
  INTO v_session_ids, v_intent_ids
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources)
    AND c.flow = p_flow
    AND c.owner_token = p_owner_token;

  IF COALESCE(array_length(v_session_ids, 1), 0) > 1
     OR COALESCE(array_length(v_intent_ids, 1), 0) > 1 THEN
    RAISE EXCEPTION 'Claims Stripe du même flux incohérents' USING ERRCODE = '23514';
  END IF;
  IF COALESCE(array_length(v_session_ids, 1), 0) = 1 THEN
    UPDATE public.stripe_payment_flow_claims c
    SET stripe_checkout_session_id = v_session_ids[1], modifie_le = now()
    WHERE c.resource_key = ANY(v_resources)
      AND c.flow = p_flow
      AND c.owner_token = p_owner_token
      AND c.stripe_checkout_session_id IS NULL;
  END IF;
  IF COALESCE(array_length(v_intent_ids, 1), 0) = 1 THEN
    UPDATE public.stripe_payment_flow_claims c
    SET stripe_payment_intent_id = v_intent_ids[1], modifie_le = now()
    WHERE c.resource_key = ANY(v_resources)
      AND c.flow = p_flow
      AND c.owner_token = p_owner_token
      AND c.stripe_payment_intent_id IS NULL;
  END IF;

  UPDATE private.stripe_connect_test_capacities
  SET claim_reserved_at=COALESCE(claim_reserved_at,clock_timestamp()) WHERE facture_commission_id=p_facture_id;
  RETURN jsonb_build_object(
    'acquired', true,
    'flow', p_flow,
    'owner_token', p_owner_token,
    'resources', v_resources,
    'stripe_checkout_session_id', v_session_ids[1],
    'stripe_payment_intent_id', v_intent_ids[1]
  );
END;
$$;

ALTER FUNCTION public.fn_stripe_payment_flow_claim_connect_test_v1(text,text,uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_stripe_payment_flow_claim_connect_test_v1(text,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_stripe_payment_flow_claim_connect_test_v1(text,text,uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION "public"."fn_stripe_webhook_event_claim_connect_test_v1"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_inserted integer := 0;
  v_claimed integer := 0;
  v_traite_le timestamptz;
BEGIN
  IF NOT (
    public.est_admin()
    OR COALESCE(NULLIF(auth.jwt()->>'role', ''), NULLIF(current_setting('request.jwt.claim.role', true), ''), '') = 'service_role'
  ) THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  IF p_event_type IS DISTINCT FROM 'checkout.session.completed'
    OR p_source_webhook IS DISTINCT FROM 'PLATFORM'
    OR p_payload#>>'{object,metadata,type}' IS DISTINCT FROM 'CONNECT_MISSION_PAYMENT' THEN
    RAISE EXCEPTION 'CONNECT_PROTOCOL_SCOPE' USING ERRCODE='22023';
  END IF;
  IF COALESCE(NULLIF(auth.jwt()->>'role',''),NULLIF(current_setting('request.jwt.claim.role',true),''),'')<>'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501';
  END IF;
  PERFORM private.fn_connect_test_exiger_evenement(p_payload,p_livemode);

  IF p_source_webhook NOT IN ('PLATFORM', 'CONNECT') THEN
    RAISE EXCEPTION 'Source webhook invalide' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.stripe_webhook_events (
    event_id,
    event_type,
    payload,
    source_webhook,
    livemode,
    traitement_commence_le,
    tentatives
  ) VALUES (
    p_event_id,
    p_event_type,
    p_payload,
    p_source_webhook,
    p_livemode,
    now(),
    1
  )
  ON CONFLICT (event_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 1 THEN
    RETURN 'CLAIMED';
  END IF;

  SELECT traite_le
    INTO v_traite_le
  FROM public.stripe_webhook_events
  WHERE event_id = p_event_id;

  IF v_traite_le IS NOT NULL THEN
    RETURN 'PROCESSED';
  END IF;

  -- Reprise possible après cinq minutes. Une Edge Function ne doit pas rester
  -- active aussi longtemps ; ce lease couvre un crash sans bloquer l'event à vie.
  UPDATE public.stripe_webhook_events
  SET traitement_commence_le = now(),
      tentatives = tentatives + 1,
      erreur = NULL,
      event_type = p_event_type,
      payload = p_payload,
      source_webhook = p_source_webhook,
      livemode = p_livemode
  WHERE event_id = p_event_id
    AND traite_le IS NULL
    AND (
      traitement_commence_le IS NULL
      OR traitement_commence_le < now() - interval '5 minutes'
    );

  GET DIAGNOSTICS v_claimed = ROW_COUNT;
  IF v_claimed = 1 THEN
    RETURN 'CLAIMED';
  END IF;

  RETURN 'PROCESSING';
END;
$$;

ALTER FUNCTION public.fn_stripe_webhook_event_claim_connect_test_v1(text,text,jsonb,text,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_stripe_webhook_event_claim_connect_test_v1(text,text,jsonb,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_stripe_webhook_event_claim_connect_test_v1(text,text,jsonb,text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_connect_remboursements_test_a_traiter(p_limit integer,p_capacity_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE r jsonb;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 IF p_limit IS NULL OR p_limit<1 OR p_limit>2 THEN RAISE EXCEPTION 'CONNECT_REFUND_BATCH_LIMIT'; END IF;
 SELECT COALESCE(jsonb_agg(x.doc ORDER BY x.created_at,x.id),'[]'::jsonb) INTO r FROM (
   SELECT o.id,o.created_at,to_jsonb(o)-'attempt_key'-'owner_token'-'lease_until' AS doc
   FROM private.stripe_connect_avant_transfert o JOIN public.soignants s ON s.id=o.soignant_id
   JOIN public.etablissements e ON e.id=o.etablissement_id
   WHERE o.orientation='REFUND' AND (o.refund_status IN('READY','PENDING','REQUIRES_ACTION')
     OR (o.refund_status='SUCCEEDED' AND o.succeeded_at>clock_timestamp()-interval '31 days')) AND o.review_code IS NULL
     AND o.next_read_at<=clock_timestamp() AND (o.lease_until IS NULL OR o.lease_until<=clock_timestamp())
     AND private.fn_connect_test_operation_connue(o.id) AND EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities cap WHERE cap.id=p_capacity_id AND cap.operation_id=o.id)
   ORDER BY o.next_read_at,o.created_at,o.id LIMIT p_limit
 ) x;
 RETURN r;
END;$f$;

ALTER FUNCTION public.fn_connect_remboursements_test_a_traiter(integer,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_connect_remboursements_test_a_traiter(integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_connect_remboursements_test_a_traiter(integer,uuid) TO service_role;
DO $inventory$ DECLARE p record; BEGIN
 FOR p IN SELECT oid,regexp_replace(oid::regprocedure::text,'^public[.]','') AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace
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
END $inventory$;
DO $closed$ BEGIN
 IF EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities) OR EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE enabled)
 THEN RAISE EXCEPTION 'CONNECT_TEST_INSTALLATION_OPEN'; END IF;
END $closed$;

INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at,created_at) VALUES
('d5aa1eda-5932-4046-a85c-76293de31b4e'::uuid,'00000000-0000-0000-0000-000000000000'::uuid,'connect-test-d5aa1eda-5932-4046-a85c-76293de31b4e@example.invalid','authenticated','authenticated','{"role":"SOIGNANT","est_compte_test":true,"is_test_playwright":true,"jolene_connect_fixture_owner":"connect-test-pg17-history-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c"}'::jsonb,transaction_timestamp(),transaction_timestamp()-interval '1 day'),
('dc0aef51-c949-4604-9533-8381e34dc445'::uuid,'00000000-0000-0000-0000-000000000000'::uuid,'connect-test-dc0aef51-c949-4604-9533-8381e34dc445@example.invalid','authenticated','authenticated','{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true,"is_test_playwright":true,"jolene_connect_fixture_owner":"connect-test-pg17-history-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c","etablissement_id":"dc0aef51-c949-4604-9533-8381e34dc445"}'::jsonb,transaction_timestamp(),transaction_timestamp()-interval '1 day'),
('8dfb41d8-1106-43a6-a23c-bc494ea38ea6'::uuid,'00000000-0000-0000-0000-000000000000'::uuid,'connect-test-8dfb41d8-1106-43a6-a23c-bc494ea38ea6@example.invalid','authenticated','authenticated','{"role":"ADMIN_PLATEFORME","est_compte_test":true,"is_test_playwright":true,"jolene_connect_fixture_owner":"connect-test-pg17-history-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c"}'::jsonb,transaction_timestamp(),transaction_timestamp()-interval '1 day'),
('15f85f94-c966-4a82-a687-1ae1a3f4738f'::uuid,'00000000-0000-0000-0000-000000000000'::uuid,'connect-test-15f85f94-c966-4a82-a687-1ae1a3f4738f@example.invalid','authenticated','authenticated','{"role":"ADMIN_PLATEFORME","est_compte_test":true,"is_test_playwright":true,"jolene_connect_fixture_owner":"connect-test-pg17-reuse-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c"}'::jsonb,transaction_timestamp(),transaction_timestamp());
SELECT set_config('jolene.connect_test_fixture_manifest','{"schemaVersion":1,"projectRef":"mejpriaetwgtcstbgfid","runId":"connect-test-pg17-history-20261004","sourceSha":"01b135471e1e6ee7ee31439ffc248c8b8519260c","ownerMarker":"connect-test-pg17-history-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c","actors":{"soignant":{"id":"d5aa1eda-5932-4046-a85c-76293de31b4e","email":"connect-test-d5aa1eda-5932-4046-a85c-76293de31b4e@example.invalid"},"etablissement":{"id":"dc0aef51-c949-4604-9533-8381e34dc445","email":"connect-test-dc0aef51-c949-4604-9533-8381e34dc445@example.invalid"}},"sqlActors":{"admin":{"id":"8dfb41d8-1106-43a6-a23c-bc494ea38ea6","email":"connect-test-8dfb41d8-1106-43a6-a23c-bc494ea38ea6@example.invalid"}},"ids":{"mission":"5c8cecba-c552-485b-9c74-dbd682364a7b","equipeAdmin":"fefbf196-c290-4197-a24c-18021bdeb180","presence":"4eb38ad8-8224-4020-986e-3fa37fbb9674"},"identifiants":{"siretSoignant":"99176821827458","siretEtablissement":"99450762613213"}}',true);
-- Canonical mission/mandate/TVA fixture body, byte-for-byte (its Auth API comment does not apply to this local seed).
-- Préparation synthétique uniquement ; aucune facture ni statut financier forcé.
-- Dérivé du seed F1 : aucun lancement du pilote F1 ni modification de ses verrous.
-- Le troisième acteur est un admin synthétique désactivé dans cette transaction.
-- Exiger avant ce corps le preflight de catalogue, canaux et manifeste.
-- Parametre JSON transactionnel : jolene.connect_test_fixture_manifest.
-- Auth est cree auparavant par API Admin, sans invitation/email ni session admin.
-- Historique synthetique de maintenance : aucune preuve d'attribution/qualification.
SET LOCAL TIME ZONE 'UTC';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $fixture$
DECLARE
  v jsonb := current_setting('jolene.connect_test_fixture_manifest')::jsonb;
  s uuid := (v#>>'{actors,soignant,id}')::uuid;
  e uuid := (v#>>'{actors,etablissement,id}')::uuid;
  a uuid := (v#>>'{sqlActors,admin,id}')::uuid;
  m uuid := (v#>>'{ids,mission}')::uuid;
  team uuid := (v#>>'{ids,equipeAdmin}')::uuid;
  presence uuid := (v#>>'{ids,presence}')::uuid;
  semaine date;
  passe date;
  futur date;
  mandat text;
  r jsonb;
  n text;
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
    OR v->>'projectRef' IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
    OR v->>'schemaVersion' IS DISTINCT FROM '1'
    OR v->>'runId' !~ '^connect-test-[a-z0-9-]{8,64}$'
    OR v->>'sourceSha' !~ '^[a-f0-9]{40}$'
    OR v->>'ownerMarker' IS DISTINCT FROM (v->>'runId')||':'||(v->>'sourceSha')
    OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'CONNECT TEST contexte/manifeste invalide'; END IF;
  FOREACH n IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.tva_mission_managed','app.internal_operation'] LOOP
    IF NULLIF(current_setting(n,true),'') IS NOT NULL THEN RAISE EXCEPTION 'CONNECT TEST override present'; END IF;
  END LOOP;
  IF cardinality(ARRAY[s,e,a,m,team,presence])<>6 OR (SELECT count(DISTINCT x) FROM unnest(ARRAY[s,e,a,m,team,presence]) x)<>6
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=s)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=e OR siret=v#>>'{identifiants,siretEtablissement}')
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team OR user_id=a)
    OR EXISTS(SELECT 1 FROM public.missions WHERE id=m)
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=presence OR mission_id=m)
  THEN RAISE EXCEPTION 'CONNECT TEST collision ou identifiant absent'; END IF;
  IF (SELECT count(*) FROM auth.users u WHERE u.id IN(s,e,a)
    AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=v->>'ownerMarker'
    AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
    AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=now())
    AND u.email = CASE u.id WHEN s THEN v#>>'{actors,soignant,email}' WHEN e THEN v#>>'{actors,etablissement,email}' ELSE v#>>'{sqlActors,admin,email}' END
    AND u.email LIKE '%@example.invalid'
    AND u.raw_app_meta_data->>'role'=CASE u.id WHEN s THEN 'SOIGNANT' WHEN e THEN 'ADMIN_ETABLISSEMENT' ELSE 'ADMIN_PLATEFORME' END)<>3
  THEN RAISE EXCEPTION 'CONNECT TEST filiation Auth incorrecte'; END IF;
  -- Une semaine dont le lundi est ouvré garde periodeDebut dans la mission.
  -- Un lundi férié ne doit pas décaler le premier créneau après cette borne.
  SELECT d::date INTO semaine FROM generate_series(date_trunc('week',current_date)::date-7,
    date_trunc('week',current_date)::date-35,interval '-7 days') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d DESC LIMIT 1;
  passe := semaine;
  -- Reste futur même si la semaine facturable a reculé à cause d'un jour férié.
  SELECT d::date INTO futur FROM generate_series(date_trunc('week',current_date)::date+7,
    date_trunc('week',current_date)::date+11,interval '1 day') d
    WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
  IF passe IS NULL OR futur IS NULL OR semaine+6>=current_date THEN RAISE EXCEPTION 'CONNECT TEST calendrier invalide'; END IF;
  INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
    source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
    identite_verifiee,diplome_verifie,rpps_verifie,tous_documents_valides,
    siret_liberal,adresse_rue,adresse_code_postal,adresse_ville)
  VALUES(s,'Connect','TEST Synthétique',v#>>'{actors,soignant,email}','IDE','LIBERAL','1990-01-01',true,
    'RECETTE_CONNECT_TEST_SYNTHETIQUE',upper(replace(s::text,'-','')),false,false,false,false,false,false,false,
    v#>>'{identifiants,siretSoignant}','Adresse SYNTHETIQUE sans personne réelle','75001','Paris TEST');
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
    est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,statut_verification,
    peut_publier_missions,est_secteur_public,rist_plafond_actif,taux_commission_negocie)
  VALUES(e,'TEST Clinique Connect Synthétique',v#>>'{identifiants,siretEtablissement}','CLINIQUE_PRIVEE',
    'Adresse SYNTHETIQUE sans établissement réel','Paris TEST','75001',v#>>'{actors,etablissement,email}',
    true,'RECETTE_CONNECT_TEST_SYNTHETIQUE',upper(replace(e::text,'-','')),false,false,'EN_ATTENTE',false,false,false,15);
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id IN(s,e);
  IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(s,e)
    AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
  THEN RAISE EXCEPTION 'CONNECT TEST canaux non fermes'; END IF;
  -- Le vrai RPC serveur conserve une attestation explicitement fictive, pas le texte d'un mandat utilisateur.
  mandat := repeat('RECETTE SYNTHETIQUE CONNECT TEST — AUCUNE PORTEE JURIDIQUE — NON SIGNE PAR UNE PERSONNE REELLE — ',16)
    || (v->>'ownerMarker');
  r:=public.fn_signer_mandat_facturation_serveur(s,'1.4',NULL,'RECETTE_SYNTHETIQUE',
    'recette-connect-test-synthetique',encode(extensions.digest(convert_to(mandat,'UTF8'),'sha256'),'hex'),mandat,'FRANCHISE_EN_BASE');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CONNECT TEST mandat fixture refuse: %',r; END IF;
  -- L'application du régime après INSERT laisse le trigger TVA initier A_REVOIR.
  -- Le régime financier initial reste libéral (recherche/choix/note d'honoraires).
  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
    duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
    choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
  VALUES(m,e,'RECETTE CONNECT TEST SYNTHETIQUE '||(v->>'runId'),'IDE',futur+time '09:00',futur+time '13:00',
    4,20,'EN_COURS',s,'LIBERAL',NULL,'LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
  UPDATE public.missions SET type_contrat_applique='LIBERAL' WHERE id=m;
  UPDATE public.mission_creneaux SET debut=passe+time '09:00',fin=passe+time '13:00'
    WHERE mission_id=m AND type_creneau='PREVISIONNEL';
  INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
  VALUES(m,futur+time '09:00',futur+time '13:00','PREVISIONNEL',false,2),
    (m,passe+time '09:00',passe+time '13:00','EFFECTIF',false,3);
  INSERT INTO public.equipe_admin(id,user_id,nom,prenom,email,poste,actif,acces_groupes)
  VALUES(team,a,'SYNTHETIQUE','CONNECT TEST',v#>>'{sqlActors,admin,email}','RECETTE CONNECT TEST SANS SESSION',true,
    ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','aal','aal2')::text,true);
  r:=public.fn_admin_proposer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE','RECETTE SYNTHETIQUE sans prestation ni attestation réelle');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CONNECT TEST revue TVA refusee: %',r; END IF;
  PERFORM set_config('request.jwt.claim.sub',s::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'role','authenticated')::text,true);
  r:=public.fn_confirmer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE');
  IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva'<>'CONFIRMEE' THEN RAISE EXCEPTION 'CONNECT TEST confirmation TVA refusee'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.equipe_admin SET actif=false WHERE id=team AND user_id=a;
  IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=m AND statut='EN_COURS' AND nb_creneaux=2
    AND duree_heures=8 AND duree_heures_effective=4 AND net_a_payer=160 AND montant_commission_ht=24
    AND statut_validation_tva='CONFIRMEE' AND fige_le IS NULL
    AND debut_le::date=semaine AND fin_le::date=futur AND semaine+6<fin_le::date)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e))
    OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE user_id=a AND actif)
  THEN RAISE EXCEPTION 'CONNECT TEST seed ou effets inattendus'; END IF;
  r:=public.fn_calculer_montant_periode(m,semaine,semaine+6);
  IF (r->>'montant_ht_periode')::numeric IS DISTINCT FROM 80 THEN RAISE EXCEPTION 'CONNECT TEST prorata inattendu'; END IF;
  PERFORM set_config('jolene.connect_test_fixture_receipt',jsonb_build_object('runId',v->>'runId','missionId',m,
    'periodeDebut',semaine,'periodeFin',semaine+6,'montantOriginal',80,'commissionTtc',14.4,
    'presenceIdReserve',presence,'qualificationVerifiee',false,'signatureSynthetique',true,'mfaProuve',false)::text,true);
END $fixture$;
SELECT current_setting('jolene.connect_test_fixture_receipt')::jsonb AS receipt;

DO $fixture_link$ DECLARE n integer; BEGIN
    IF EXISTS(SELECT 1 FROM public.etablissements WHERE stripe_customer_id='cus_PG17SyntheticN')
      OR EXISTS(SELECT 1 FROM public.soignants WHERE stripe_account_id='acct_PG17SyntheticN')
      OR EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE stripe_account_id='acct_PG17SyntheticN' OR soignant_id='d5aa1eda-5932-4046-a85c-76293de31b4e'::uuid)
    THEN RAISE EXCEPTION 'CONNECT_FIXTURE_LINK_EXISTS'; END IF;
    UPDATE public.etablissements SET stripe_customer_id='cus_PG17SyntheticN' WHERE id='dc0aef51-c949-4604-9533-8381e34dc445'::uuid AND est_compte_test IS TRUE AND stripe_customer_id IS NULL AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE';
    GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'CONNECT_FIXTURE_CUSTOMER_CAS'; END IF;
    UPDATE public.soignants SET stripe_account_id='acct_PG17SyntheticN' WHERE id='d5aa1eda-5932-4046-a85c-76293de31b4e'::uuid AND est_compte_test IS TRUE AND stripe_account_id IS NULL AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE';
    GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'CONNECT_FIXTURE_ACCOUNT_CAS'; END IF;
    INSERT INTO public.stripe_connect_onboarding(soignant_id,stripe_account_id,statut,onboarding_complete,charges_enabled,payouts_enabled,details_submitted)
      VALUES('d5aa1eda-5932-4046-a85c-76293de31b4e'::uuid,'acct_PG17SyntheticN','EN_COURS',false,false,false,false);
  END $fixture_link$;
  SELECT jsonb_build_object('linked',true) AS receipt;
DO $synthetic_n$
DECLARE
 v jsonb:=current_setting('jolene.connect_test_fixture_manifest')::jsonb;
 j jsonb:='{"schemaVersion":1,"purpose":"CONNECT_REFUND_REUSE_ACTORS_NEW_MISSION_V1","ready":true,"evidenceScope":"PG17_SYNTHETIC_ONLY","providerEvidence":false,"authorizationEvidence":false,"projectRef":"mejpriaetwgtcstbgfid","sourceSha":"01b135471e1e6ee7ee31439ffc248c8b8519260c","runId":"connect-test-pg17-reuse-20261004","ownerMarker":"connect-test-pg17-reuse-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c","actorProvenance":{"runId":"connect-test-pg17-history-20261004","sourceSha":"01b135471e1e6ee7ee31439ffc248c8b8519260c","ownerMarker":"connect-test-pg17-history-20261004:01b135471e1e6ee7ee31439ffc248c8b8519260c","soignantId":"d5aa1eda-5932-4046-a85c-76293de31b4e","etablissementId":"dc0aef51-c949-4604-9533-8381e34dc445","customerId":"cus_PG17SyntheticN","destinationId":"acct_PG17SyntheticN"},"historicalN":{"capacityId":"dcadcb14-3741-48ab-9606-5cd4ed573389","operationId":"1e9f9e75-a556-4610-8dca-ba4aa710d8fa","missionId":"5c8cecba-c552-485b-9c74-dbd682364a7b","honorairesId":"1856f3fc-ea0b-4d61-b23f-0498977c1be2","traceId":"5e0af7ec-453f-4845-bbff-3125e2fe02cb","adminId":"8dfb41d8-1106-43a6-a23c-bc494ea38ea6","adminTeamId":"fefbf196-c290-4197-a24c-18021bdeb180","sessionId":"cs_test_PG17SyntheticN","refundId":"re_PG17SyntheticN"},"new":{"missionId":"945a25e3-5285-4032-b77f-49b690ce481a","adminId":"15f85f94-c966-4a82-a687-1ae1a3f4738f","adminTeamId":"4be965ed-3569-4c8c-8f66-52c9e6064c3e"}}'::jsonb;
 s uuid:=(v#>>'{actors,soignant,id}')::uuid;
 e uuid:=(v#>>'{actors,etablissement,id}')::uuid;
 a uuid:='15f85f94-c966-4a82-a687-1ae1a3f4738f'::uuid;
 team uuid:='4be965ed-3569-4c8c-8f66-52c9e6064c3e'::uuid;
 hm uuid:=(v#>>'{ids,mission}')::uuid;
 ha uuid:=(v#>>'{sqlActors,admin,id}')::uuid;
 hteam uuid:=(v#>>'{ids,equipeAdmin}')::uuid;
 hh uuid:='1856f3fc-ea0b-4d61-b23f-0498977c1be2'::uuid;
 hf uuid;
 ht uuid:='5e0af7ec-453f-4845-bbff-3125e2fe02cb'::uuid;
 ho uuid:='1e9f9e75-a556-4610-8dca-ba4aa710d8fa'::uuid;
 hc uuid:='dcadcb14-3741-48ab-9606-5cd4ed573389'::uuid;
 lt uuid:='8252d3be-44cb-4c80-ad9f-f57e9bb35520'::uuid;
 week_n date:=(current_setting('jolene.connect_test_fixture_receipt')::jsonb->>'periodeDebut')::date;
 week_new date;
 future_new date;
 r jsonb;
 snap jsonb;
 cat jsonb;
 evidence jsonb:=jsonb_build_object('reviewer','PG17_SYNTHETIC_ONLY; no external review, provider or Auth proof');
 payloads jsonb:='{}'::jsonb;
 payload jsonb;
 evidence_pin_key text;
BEGIN
 -- Declared readiness fixture only; no KYC/onboarding claim outside this transaction.
 UPDATE public.stripe_connect_onboarding SET statut='COMPLET',onboarding_complete=true,
  charges_enabled=true,payouts_enabled=true,details_submitted=true WHERE soignant_id=s;
 INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
  montant_ht,montant_tva,montant_ttc,taux_tva,statut,mandat_version,periode_debut,periode_fin,
  est_facture_finale_mission,quantite_heures_snapshot,taux_horaire_snapshot,pdf_s3_key,facturx_xml_url)
 VALUES(hh,public.next_invoice_number(s),s,e,hm,80,0,80,0,'EMISE','1.4',week_n,week_n+6,false,4,20,
  'pg17-synthetic-only/no-file.pdf','pg17-synthetic-only/no-file.xml');
 INSERT INTO public.factures_honoraires_documents(facture_honoraire_id,pdf_s3_key,facturx_xml_url,motif_generation)
 VALUES(hh,'pg17-synthetic-only/no-file.pdf','pg17-synthetic-only/no-file.xml','PG17_SYNTHETIC_ONLY_NO_DOCUMENT_BYTES');
 r:=public.fn_preparer_facture_commission_periode(hh);
 IF r->'success' IS DISTINCT FROM 'true'::jsonb OR (r->>'montant_ttc')::numeric IS DISTINCT FROM 14.4
 THEN RAISE EXCEPTION 'WITNESS_CANONICAL_COMMISSION_REFUSED'; END IF;
 hf:=(r->>'facture_id')::uuid;
 INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token,stripe_checkout_session_id,stripe_payment_intent_id)
 VALUES('FACTURE:'||hf::text,'CONNECT_INVOICE','connect-invoice:'||hh::text,'cs_test_PG17SyntheticN',NULL);
 -- Closed historical dispute; no mutation/settlement RPC or supplier action is being claimed.
 INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,
  gel_facture_scope,resolu_le,resolution)
 VALUES(lt,hm,s,e,'SYSTEME','PG17_SYNTHETIC_ONLY refund history','FERME','AUCUN',transaction_timestamp()-interval '1 day',
  'PG17_SYNTHETIC_ONLY no provider observed');
 INSERT INTO public.stripe_transfers(id,mission_id,facture_id,facture_honoraire_id,soignant_id,etablissement_id,
  montant_total,montant_commission,montant_soignant,stripe_checkout_session_id,stripe_payment_intent_id,stripe_charge_id,statut)
 VALUES(ht,hm,hf,hh,s,e,94.4,14.4,80,'cs_test_PG17SyntheticN',NULL,NULL,'REMBOURSE');
 INSERT INTO private.stripe_connect_avant_transfert(id,attempt_key,mission_id,etablissement_id,soignant_id,
  facture_honoraire_id,facture_commission_id,customer_id,destination_id,soignant_cents,commission_cents,total_cents,
  session_id,trace_id,payment_intent_id,charge_id,livemode,orientation,litige_id,refund_id,refund_status,first_attempt_at,succeeded_at)
 VALUES(ho,'PG17_SYNTHETIC_ONLY_N',hm,e,s,hh,hf,'cus_PG17SyntheticN','acct_PG17SyntheticN',8000,1440,9440,
  'cs_test_PG17SyntheticN',ht,'pi_PG17SyntheticN','ch_PG17SyntheticN',false,'REFUND',lt,'re_PG17SyntheticN','SUCCEEDED',
  transaction_timestamp()-interval '2 days',transaction_timestamp()-interval '1 day');
 INSERT INTO private.stripe_connect_test_capacities(id,protocol,project_ref,run_id,server_sha,ui_sha,source_manifest_sha256,
  enabled,installed_at,expires_at,etablissement_id,soignant_id,mission_id,facture_honoraire_id,facture_commission_id,
  platform_account_id,customer_id,destination_id,soignant_cents,commission_cents,total_cents,operation_id,
  checkout_reserved_at,refund_reserved_at,claim_reserved_at,revoked_at)
 VALUES(hc,'CONNECT_STAGING_TEST_V1','mejpriaetwgtcstbgfid','f1-PG17SyntheticN','01b135471e1e6ee7ee31439ffc248c8b8519260c','01b135471e1e6ee7ee31439ffc248c8b8519260c',
  encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex'),false,
  transaction_timestamp()-interval '3 days',transaction_timestamp()-interval '1 day',e,s,hm,hh,hf,
  'acct_1T9pt0EVhQ7cb53W','cus_PG17SyntheticN','acct_PG17SyntheticN',8000,1440,9440,ho,
  transaction_timestamp()-interval '2 days',transaction_timestamp()-interval '2 days',transaction_timestamp()-interval '2 days',
  transaction_timestamp()-interval '1 day');
 -- The schema-only restore has no liberal-profession reference rows, so the canonical
 -- initial seed creates no conversion row. Assert that diagnosis before adding a
 -- declared local historical row; keep the reference table and all triggers intact.
 IF EXISTS(SELECT 1 FROM public.professions_liberal_eligible)
  OR EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=s)
 THEN RAISE EXCEPTION 'WITNESS_EXPECTED_EMPTY_CONVERSION_REFERENCE'; END IF;
 INSERT INTO public.suivi_conversion_3200h(soignant_id,profession_cible_liberal,cree_le)
 SELECT id,profession::text,transaction_timestamp()-interval '1 day' FROM public.soignants WHERE id=s;
 -- Canonical code explicitly supports an already existing historical follow-up.
 PERFORM private.fn_resynchroniser_compteurs_soignant(s);
 -- Artificially old technical timestamps prevent a same-transaction seed masking the canonical trigger effect.
 UPDATE public.soignants SET modifie_le=transaction_timestamp()-interval '1 day' WHERE id=s;
 UPDATE public.suivi_conversion_3200h SET modifie_le=transaction_timestamp()-interval '1 day' WHERE soignant_id=s;
 SELECT d::date INTO week_new FROM generate_series(date_trunc('week',current_date)::date-7,
  date_trunc('week',current_date)::date-35,interval '-7 days') d
  WHERE d::date<>week_n AND d::date>=current_date-35 AND NOT public.fn_est_jour_ferie(d::date) ORDER BY d DESC LIMIT 1;
 SELECT d::date INTO future_new FROM generate_series(date_trunc('week',current_date)::date+14,
  date_trunc('week',current_date)::date+18,interval '1 day') d
  WHERE NOT public.fn_est_jour_ferie(d::date) ORDER BY d LIMIT 1;
 IF week_new IS NULL OR future_new IS NULL THEN RAISE EXCEPTION 'WITNESS_CALENDAR_REQUIRED'; END IF;
 j:=j||jsonb_build_object('issuedAt',transaction_timestamp()-interval '1 second','expiresAt',transaction_timestamp()+interval '1 hour',
  'calendar',jsonb_build_object('periodStart',week_new,'periodEnd',week_new+6,
   'pastStart',week_new+time '09:00','pastEnd',week_new+time '13:00','futureStart',future_new+time '09:00','futureEnd',future_new+time '13:00'));
 j:=jsonb_set(j,'{actorProvenance}',(j->'actorProvenance')||jsonb_build_object(
  'manifestSha256',encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex'),
  'mandatId',(SELECT id FROM public.mandats_facturation_signatures WHERE soignant_id=s AND version='1.4' AND revoked_at IS NULL)));
 j:=jsonb_set(j,'{historicalN,commissionId}',to_jsonb(hf));
 snap:=-- Expression uniquement ; aliases PL/pgSQL j,s,e,a,team et hc/ho/hm/hh/hf/ht/ha/hteam.
-- Valeurs sensibles Auth exclues : ni password/hash, ni recovery token, ni JWT.
-- A/T neufs sont exclus ; toute autre équipe existante est conservée.
jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
 j:=jsonb_set(j,'{historicalN}',(j->'historicalN')||jsonb_build_object(
  'protectedSnapshotSha256',encode(extensions.digest(convert_to(snap::text,'UTF8'),'sha256'),'hex'),
  'proofSha256',encode(extensions.digest(convert_to(jsonb_build_object('scope','PG17_SYNTHETIC_ONLY',
   'closedSyntheticState',snap)::text,'UTF8'),'sha256'),'hex')));
 SELECT c.catalogue INTO cat FROM (SELECT jsonb_build_object(
    'routines', (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,''),E'\n' ORDER BY p.oid::regprocedure::text))
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')),
    'triggers', (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text,E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth','storage')),
    'columns', (SELECT md5(string_agg(n.nspname::text||'.'||c.relname::text||'.'||a.attname::text||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),''),E'\n' ORDER BY n.nspname,c.relname,a.attnum))
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname IN ('public','private','auth','storage')),
    'commissionHelper',md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure)),
    'queuedRequests',(SELECT count(*)::int FROM net.http_request_queue),
    'activeCrons',(SELECT count(*)::int FROM cron.job WHERE active),
    'runningCrons',(SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')),
    'generationUrlAbsent',NOT EXISTS(SELECT 1 FROM public.parametres_litiges WHERE cle='generate_invoice_url' AND coalesce(length(valeur),0)>0),
    'supportStagingExact',coalesce((SELECT nullif(btrim(decrypted_secret),'')='https://mejpriaetwgtcstbgfid.supabase.co' FROM vault.decrypted_secrets WHERE name='supabase_url' LIMIT 1),false)
  ) AS catalogue) c;
 j:=jsonb_set(j,'{catalogue}',cat);
 -- These required hash-shaped pins are hashes of explicit LOCAL SYNTHETIC DECLARATIONS, not acquired proofs.
 FOREACH evidence_pin_key IN ARRAY ARRAY['protocolSha256','adminAuthIntentSha256','adminAuthReceiptSha256','providerReadinessReceiptSha256',
  'providerHistoryReceiptSha256','edgeGenerationReceiptSha256','calendarReceiptSha256'] LOOP
  payload:=jsonb_build_object('scope','PG17_SYNTHETIC_ONLY','notExternalEvidence',true,'field',evidence_pin_key,
   'sqlModelSha256','9168901ab6a48afbb8c530e07c8b49e21f07bb4650bd326dd7ff31b013d108dd','syntheticManifest',j);
  payloads:=payloads||jsonb_build_object(evidence_pin_key,payload);
  evidence:=evidence||jsonb_build_object(evidence_pin_key,encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'));
 END LOOP;
 j:=j||jsonb_build_object('reviewedEvidence',evidence,'syntheticEvidencePayloads',payloads);
 IF (SELECT count(*) FROM auth.users)<>4 OR EXISTS(SELECT 1 FROM auth.sessions)
  OR EXISTS(SELECT 1 FROM auth.identities) OR (SELECT count(*) FROM public.missions)<>1
  OR (SELECT count(*) FROM public.equipe_admin)<>1 OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE actif)
  OR (SELECT count(*) FROM vault.secrets)<>1 OR EXISTS(SELECT 1 FROM net.http_request_queue)
  OR EXISTS(SELECT 1 FROM public.email_queue) OR (SELECT count(*) FROM public.factures_honoraires_documents)<>1
  OR NOT private.fn_connect_test_operation_connue(ho)
 THEN RAISE EXCEPTION 'WITNESS_SYNTHETIC_GRAPH_OR_QUIESCENCE'; END IF;
 PERFORM set_config('jolene.connect_reuse_manifest',j::text,true);
END $synthetic_n$;

-- END REVIEWED SYNTHETIC SEED
-- The real preparation starts in a later transaction. The rollback-only witness
-- shares the seed transaction, whose canonical TVA RPCs leave this local flag set.
-- Require that exact residue and reject every other override before clearing only it.
DO $seed_transaction_boundary$
DECLARE boundary_setting text;
BEGIN
 IF current_setting('jolene.tva_mission_managed',true) IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'WITNESS_EXPECTED_SEED_TVA_CONTEXT'; END IF;
 FOREACH boundary_setting IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
  'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
  'app.internal_operation','app.test_bypass_protections'] LOOP
  IF NULLIF(current_setting(boundary_setting,true),'') IS NOT NULL
  THEN RAISE EXCEPTION 'WITNESS_UNEXPECTED_SEED_OVERRIDE'; END IF;
 END LOOP;
 PERFORM set_config('jolene.tva_mission_managed','',true);
 IF NULLIF(current_setting('jolene.tva_mission_managed',true),'') IS NOT NULL
 THEN RAISE EXCEPTION 'WITNESS_SEED_TVA_CONTEXT_NOT_CLEARED'; END IF;
END $seed_transaction_boundary$;
DO $witness$
DECLARE
 j jsonb:=current_setting('jolene.connect_reuse_manifest')::jsonb;
 s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
 e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
 a uuid:=(j#>>'{new,adminId}')::uuid;
 m uuid:=(j#>>'{new,missionId}')::uuid;
 team uuid:=(j#>>'{new,adminTeamId}')::uuid;
 hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
 ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
 hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
 hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
 hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
 ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
 ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
 hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
 preparation text:=$exact_preparation$DO $reuse_new_mission$
DECLARE
 j jsonb:=current_setting('jolene.connect_reuse_manifest')::jsonb;
 s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
 e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
 a uuid:=(j#>>'{new,adminId}')::uuid;
 m uuid:=(j#>>'{new,missionId}')::uuid;
 team uuid:=(j#>>'{new,adminTeamId}')::uuid;
 hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
 ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
 hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
 hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
 hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
 ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
 ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
 hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
 week_start date:=(j#>>'{calendar,periodStart}')::date;
 week_end date:=(j#>>'{calendar,periodEnd}')::date;
 past_start timestamptz:=(j#>>'{calendar,pastStart}')::timestamptz;
 past_end timestamptz:=(j#>>'{calendar,pastEnd}')::timestamptz;
 future_start timestamptz:=(j#>>'{calendar,futureStart}')::timestamptz;
 future_end timestamptz:=(j#>>'{calendar,futureEnd}')::timestamptz;
 historical_capacity private.stripe_connect_test_capacities;
 o private.stripe_connect_avant_transfert;
 before_state jsonb;
 after_state jsonb;
 catalogue jsonb;
 r jsonb;
 n text;
 v_count integer;
 soignant_modified_before timestamptz;
BEGIN
 -- Ne pas masquer un appel utilisateur préexistant en remplaçant son contexte.
 IF current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin')
  OR current_setting('server_version_num')::integer/10000<>17
  OR auth.uid() IS NOT NULL
  OR j->'schemaVersion' IS DISTINCT FROM '1'::jsonb
  OR j->>'purpose' IS DISTINCT FROM 'CONNECT_REFUND_REUSE_ACTORS_NEW_MISSION_V1'
  OR j->'ready' IS DISTINCT FROM 'true'::jsonb
  OR j->>'projectRef' IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
  OR COALESCE(j->>'sourceSha','') !~ '^[a-f0-9]{40}$'
  OR COALESCE(j->>'runId','') !~ '^connect-test-[a-z0-9-]{8,64}$'
  OR j->>'ownerMarker' IS DISTINCT FROM (j->>'runId')||':'||(j->>'sourceSha')
  OR j->>'issuedAt' IS NULL OR j->>'expiresAt' IS NULL
  OR (j->>'issuedAt')::timestamptz>clock_timestamp()
  OR (j->>'expiresAt')::timestamptz<=clock_timestamp()
  OR (j->>'expiresAt')::timestamptz-(j->>'issuedAt')::timestamptz>interval '4 hours'
  OR j->>'runId' IS NOT DISTINCT FROM j#>>'{actorProvenance,runId}'
  OR COALESCE(j#>>'{actorProvenance,sourceSha}','') !~ '^[a-f0-9]{40}$'
  OR COALESCE(j#>>'{actorProvenance,runId}','') !~ '^connect-test-[a-z0-9-]{8,64}$'
  OR j#>>'{actorProvenance,ownerMarker}' IS DISTINCT FROM (j#>>'{actorProvenance,runId}')||':'||(j#>>'{actorProvenance,sourceSha}')
  OR COALESCE(j#>>'{actorProvenance,manifestSha256}','') !~ '^[a-f0-9]{64}$'
  OR COALESCE(j#>>'{historicalN,proofSha256}','') !~ '^[a-f0-9]{64}$'
  OR COALESCE(j#>>'{historicalN,protectedSnapshotSha256}','') !~ '^[a-f0-9]{64}$'
  OR COALESCE(j#>>'{reviewedEvidence,reviewer}','')=''
 THEN RAISE EXCEPTION 'REUSE_CONTEXT_OR_PROVENANCE_REFUSED'; END IF;
 FOREACH n IN ARRAY ARRAY['protocolSha256','adminAuthIntentSha256','adminAuthReceiptSha256',
  'providerReadinessReceiptSha256','providerHistoryReceiptSha256','edgeGenerationReceiptSha256','calendarReceiptSha256'] LOOP
  IF COALESCE(j#>>ARRAY['reviewedEvidence',n],'') !~ '^[a-f0-9]{64}$'
  THEN RAISE EXCEPTION 'REUSE_REVIEWED_EVIDENCE_REQUIRED'; END IF;
 END LOOP;
 FOREACH n IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
  'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
  'jolene.tva_mission_managed','app.internal_operation','app.test_bypass_protections'] LOOP
  IF NULLIF(current_setting(n,true),'') IS NOT NULL THEN RAISE EXCEPTION 'REUSE_OVERRIDE_REFUSED'; END IF;
 END LOOP;
 IF (SELECT count(DISTINCT x) FROM unnest(ARRAY[s,e,a,m,team,hc,ho,hm,hh,hf,ht,ha,hteam]) x)<>13
  OR EXISTS(SELECT 1 FROM public.missions WHERE id=m OR intitule='RECETTE CONNECT TEST SYNTHETIQUE '||(j->>'runId'))
  OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team OR user_id=a)
  OR EXISTS(SELECT 1 FROM public.soignants WHERE id=a)
  OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=a)
  OR EXISTS(SELECT 1 FROM public.presences WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.factures WHERE mission_id=m)
 THEN RAISE EXCEPTION 'REUSE_NEW_IDENTIFIERS_REQUIRED'; END IF;
 -- Les modèles restent bornés à N seule : toute troisième histoire est refusée.
 LOCK TABLE private.stripe_connect_release_gate IN SHARE MODE;
 LOCK TABLE private.stripe_connect_test_capacities IN SHARE MODE;
 LOCK TABLE private.stripe_connect_avant_transfert IN SHARE MODE;
 IF (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
  OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
  OR (SELECT count(*) FROM private.stripe_connect_test_capacities)<>1
  OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
 THEN RAISE EXCEPTION 'REUSE_EXACT_CLOSED_N_REQUIRED'; END IF;
 SELECT * INTO STRICT historical_capacity FROM private.stripe_connect_test_capacities WHERE id=hc;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=ho;
 IF historical_capacity.enabled IS DISTINCT FROM FALSE OR historical_capacity.revoked_at IS NULL OR historical_capacity.revoked_at>clock_timestamp()
  OR historical_capacity.protocol<>'CONNECT_STAGING_TEST_V1' OR historical_capacity.project_ref<>'mejpriaetwgtcstbgfid'
  OR historical_capacity.platform_account_id<>'acct_1T9pt0EVhQ7cb53W'
  OR historical_capacity.livemode IS DISTINCT FROM FALSE OR historical_capacity.transfers_allowed IS DISTINCT FROM FALSE
  OR historical_capacity.max_checkouts<>1 OR historical_capacity.max_refunds<>1 OR historical_capacity.checkout_reserved_at IS NULL
  OR historical_capacity.refund_reserved_at IS NULL OR historical_capacity.claim_reserved_at IS NULL OR historical_capacity.operation_id IS DISTINCT FROM ho
  OR historical_capacity.etablissement_id IS DISTINCT FROM e OR historical_capacity.soignant_id IS DISTINCT FROM s
  OR historical_capacity.mission_id IS DISTINCT FROM hm OR historical_capacity.facture_honoraire_id IS DISTINCT FROM hh OR historical_capacity.facture_commission_id IS DISTINCT FROM hf
  OR historical_capacity.customer_id IS DISTINCT FROM j#>>'{actorProvenance,customerId}'
  OR historical_capacity.destination_id IS DISTINCT FROM j#>>'{actorProvenance,destinationId}'
  OR historical_capacity.destination_id IN('acct_1T9pt0EVhQ7cb53W','acct_1UKlZCEVhQI2aaZg')
  OR o.orientation IS DISTINCT FROM 'REFUND' OR o.refund_status IS DISTINCT FROM 'SUCCEEDED'
  OR o.refund_id IS DISTINCT FROM j#>>'{historicalN,refundId}' OR o.refund_id IS NULL
  OR o.session_id IS DISTINCT FROM j#>>'{historicalN,sessionId}' OR o.trace_id IS DISTINCT FROM ht
  OR o.succeeded_at IS NULL OR o.review_code IS NOT NULL OR o.owner_token IS NOT NULL OR o.lease_until IS NOT NULL
  OR o.livemode IS DISTINCT FROM FALSE OR NOT private.fn_connect_test_operation_connue(ho)
  OR NOT EXISTS(SELECT 1 FROM public.stripe_transfers WHERE id=ht AND statut='REMBOURSE'
   AND stripe_transfer_id IS NULL AND stripe_checkout_session_id=o.session_id)
  OR NOT EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=hteam AND user_id=ha AND actif IS FALSE)
 THEN RAISE EXCEPTION 'REUSE_HISTORICAL_N_NOT_CLOSED'; END IF;
 -- Catalogue identique au préflight historique (booléen Vault seulement, aucune valeur exportée).
 SELECT catalogue_source.catalogue INTO catalogue FROM (SELECT jsonb_build_object(
    'routines', (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,''),E'\n' ORDER BY p.oid::regprocedure::text))
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')),
    'triggers', (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text,E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth','storage')),
    'columns', (SELECT md5(string_agg(n.nspname::text||'.'||c.relname::text||'.'||a.attname::text||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),''),E'\n' ORDER BY n.nspname,c.relname,a.attnum))
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname IN ('public','private','auth','storage')),
    'commissionHelper',md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure)),
    'queuedRequests',(SELECT count(*)::int FROM net.http_request_queue),
    'activeCrons',(SELECT count(*)::int FROM cron.job WHERE active),
    'runningCrons',(SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')),
    'generationUrlAbsent',NOT EXISTS(SELECT 1 FROM public.parametres_litiges WHERE cle='generate_invoice_url' AND coalesce(length(valeur),0)>0),
    'supportStagingExact',coalesce((SELECT nullif(btrim(decrypted_secret),'')='https://mejpriaetwgtcstbgfid.supabase.co' FROM vault.decrypted_secrets WHERE name='supabase_url' LIMIT 1),false)
  ) AS catalogue) catalogue_source;
 IF catalogue IS DISTINCT FROM j->'catalogue'
  OR catalogue->'queuedRequests' IS DISTINCT FROM '0'::jsonb
  OR catalogue->'activeCrons' IS DISTINCT FROM '0'::jsonb
  OR catalogue->'runningCrons' IS DISTINCT FROM '0'::jsonb
  OR catalogue->'generationUrlAbsent' IS DISTINCT FROM 'true'::jsonb
  OR catalogue->'supportStagingExact' IS DISTINCT FROM 'true'::jsonb
  OR EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
  OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
  OR EXISTS(SELECT 1 FROM public.stripe_webhook_events WHERE traitement_commence_le IS NOT NULL AND traite_le IS NULL)
  OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e))
 THEN RAISE EXCEPTION 'REUSE_CATALOGUE_OR_QUIESCENCE_REFUSED'; END IF;
 -- E/S exacts, liens et mandat existants : aucune réparation de profil dans ce modèle.
 IF (SELECT count(*) FROM auth.users u WHERE u.id IN(s,e) AND u.deleted_at IS NULL
  AND u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
  AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
  AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=j#>>'{actorProvenance,ownerMarker}'
  AND u.email='connect-test-'||u.id::text||'@example.invalid'
  AND ((u.id=s AND u.raw_app_meta_data->>'role'='SOIGNANT')
   OR (u.id=e AND u.raw_app_meta_data->>'role'='ADMIN_ETABLISSEMENT' AND u.raw_app_meta_data->>'etablissement_id'=e::text)))<>2
  OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=s AND est_compte_test IS TRUE
   AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE' AND supprime_le IS NULL AND statut_compte::text='ACTIF'
   AND stripe_account_id=historical_capacity.destination_id AND type_exercice::text='LIBERAL'
   AND mandat_facturation_signe IS TRUE AND mandat_facturation_version='1.4')
  OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND est_compte_test IS TRUE
   AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE' AND supprime_le IS NULL AND stripe_customer_id=historical_capacity.customer_id)
  OR (SELECT count(*) FROM public.etablissements WHERE stripe_customer_id=historical_capacity.customer_id)<>1
  OR (SELECT count(*) FROM public.soignants WHERE stripe_account_id=historical_capacity.destination_id)<>1
  OR (SELECT count(*) FROM public.stripe_connect_onboarding WHERE soignant_id=s)<>1
  OR NOT EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE soignant_id=s AND stripe_account_id=historical_capacity.destination_id
   AND statut='COMPLET' AND onboarding_complete IS TRUE AND charges_enabled IS TRUE AND payouts_enabled IS TRUE AND details_submitted IS TRUE)
  OR NOT EXISTS(SELECT 1 FROM public.mandats_facturation_signatures WHERE id=(j#>>'{actorProvenance,mandatId}')::uuid
   AND soignant_id=s AND version='1.4' AND revoked_at IS NULL)
  OR (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(s,e)
   AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
 THEN RAISE EXCEPTION 'REUSE_ACTORS_LINKS_MANDATE_REFUSED'; END IF;
 -- A est un Auth synthétique créé pour cette exécution, jamais un admin historique.
 IF NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=a AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
  AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
  AND u.created_at>=(j->>'issuedAt')::timestamptz AND u.created_at<=clock_timestamp()
  AND u.email='connect-test-'||a::text||'@example.invalid'
  AND u.raw_app_meta_data->>'role'='ADMIN_PLATEFORME'
  AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
  AND u.raw_app_meta_data->'is_test_playwright'='true'::jsonb
  AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=j->>'ownerMarker')
  OR EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=a)
 THEN RAISE EXCEPTION 'REUSE_FRESH_SYNTHETIC_ADMIN_REQUIRED'; END IF;
 SELECT jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
) INTO before_state;
 IF encode(extensions.digest(convert_to(before_state::text,'UTF8'),'sha256'),'hex')
  IS DISTINCT FROM j#>>'{historicalN,protectedSnapshotSha256}'
 THEN RAISE EXCEPTION 'REUSE_PROTECTED_BASELINE_CHANGED'; END IF;
 SELECT modifie_le INTO STRICT soignant_modified_before FROM public.soignants WHERE id=s;
 -- Horaires explicitement épinglés pour éviter de recopier 09h-13h sur N.
 IF week_start IS NULL OR week_end IS NULL OR past_start IS NULL OR past_end IS NULL OR future_start IS NULL OR future_end IS NULL
  OR extract(isodow FROM week_start)<>1 OR week_end<>week_start+6 OR week_end>=current_date
  OR past_start::date<>week_start OR past_end::date<>week_start OR past_end-past_start<>interval '4 hours'
  OR future_start::date<=current_date OR future_end::date<>future_start::date OR future_end-future_start<>interval '4 hours'
  OR future_start::date>current_date+21 OR past_start::date<current_date-35
  OR public.fn_est_jour_ferie(week_start) OR public.fn_est_jour_ferie(future_start::date)
  OR EXISTS(SELECT 1 FROM public.mission_creneaux k JOIN public.missions x ON x.id=k.mission_id
   WHERE x.soignant_assigne_id=s AND x.statut IN('ASSIGNEE','EN_COURS','TERMINEE')
    AND ((k.debut<past_end AND k.fin>past_start) OR (k.debut<future_end AND k.fin>future_start)))
 THEN RAISE EXCEPTION 'REUSE_CALENDAR_REFUSED'; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 -- Bloc de création dérivé du seed Connect ; triggers actifs, aucun override.
 INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
  duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
  choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
 VALUES(m,e,'RECETTE CONNECT TEST SYNTHETIQUE '||(j->>'runId'),'IDE',future_start,future_end,
  4,20,'EN_COURS',s,'LIBERAL',NULL,'LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
 UPDATE public.missions SET type_contrat_applique='LIBERAL' WHERE id=m;
 UPDATE public.mission_creneaux SET debut=past_start,fin=past_end WHERE mission_id=m AND type_creneau='PREVISIONNEL';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'REUSE_INITIAL_SLOT_NOT_UNIQUE'; END IF;
 INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
 VALUES(m,future_start,future_end,'PREVISIONNEL',false,2),(m,past_start,past_end,'EFFECTIF',false,3);
 INSERT INTO public.equipe_admin(id,user_id,nom,prenom,email,poste,actif,acces_groupes)
 VALUES(team,a,'SYNTHETIQUE','CONNECT REUSE TEST','connect-test-'||a::text||'@example.invalid','RECETTE CONNECT TEST SANS SESSION',true,
  ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 IF public.est_admin() IS NOT TRUE THEN RAISE EXCEPTION 'REUSE_CANONICAL_ADMIN_REFUSED'; END IF;
 r:=public.fn_admin_proposer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE',
  'RECETTE SYNTHETIQUE sans prestation ni attestation réelle — '||(j->>'runId'));
 IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva' IS DISTINCT FROM 'A_CONFIRMER'
 THEN RAISE EXCEPTION 'REUSE_TVA_PROPOSAL_REFUSED'; END IF;
 PERFORM set_config('request.jwt.claim.sub',s::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'role','authenticated')::text,true);
 r:=public.fn_confirmer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE');
 IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva' IS DISTINCT FROM 'CONFIRMEE'
 THEN RAISE EXCEPTION 'REUSE_TVA_CONFIRMATION_REFUSED'; END IF;
 UPDATE public.equipe_admin SET actif=false WHERE id=team AND user_id=a AND actif IS TRUE;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'REUSE_ADMIN_DEACTIVATION_REFUSED'; END IF;
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 IF public.est_admin() IS NOT FALSE OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE user_id=a AND actif)
  OR EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=a)
 THEN RAISE EXCEPTION 'REUSE_ADMIN_STILL_PRIVILEGED'; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=m AND etablissement_id=e AND soignant_assigne_id=s
  AND statut='EN_COURS' AND type_contrat_applique::text='LIBERAL' AND nb_creneaux=2
  AND duree_heures=8 AND duree_heures_effective=4 AND net_a_payer=160 AND montant_commission_ht=24
  AND statut_validation_tva='CONFIRMEE' AND nature_tva_declaree_par=a AND revue_tva_resolue_par=a
  AND nature_tva_confirmee_par=s AND fige_le IS NULL AND debut_le::date=week_start AND fin_le::date=future_start::date)
  OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.factures WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.paiements_mission WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='MISSION:'||m::text)
  OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e,a))
  OR EXISTS(SELECT 1 FROM net.http_request_queue)
  OR (SELECT count(*) FROM private.stripe_connect_test_capacities)<>1
  OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
 THEN RAISE EXCEPTION 'REUSE_UNEXPECTED_PREPARATION_EFFECT'; END IF;
 r:=public.fn_calculer_montant_periode(m,week_start,week_end);
 IF (r->>'montant_ht_periode')::numeric IS DISTINCT FROM 80 THEN RAISE EXCEPTION 'REUSE_PRORATA_REFUSED'; END IF;
 SELECT jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
) INTO after_state;
 IF after_state IS DISTINCT FROM before_state THEN RAISE EXCEPTION 'REUSE_PROTECTED_ROWS_CHANGED'; END IF;
 IF (SELECT modifie_le FROM public.soignants WHERE id=s) IS DISTINCT FROM transaction_timestamp()
  OR EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=s AND modifie_le IS DISTINCT FROM transaction_timestamp())
 THEN RAISE EXCEPTION 'REUSE_NONCANONICAL_PROFILE_TIMESTAMP'; END IF;
 PERFORM set_config('jolene.connect_reuse_receipt',jsonb_build_object('runId',j->>'runId','missionId',m,
  'adminId',a,'adminTeamId',team,'adminActive',false,'periodStart',week_start,'periodEnd',week_end,
  'honorairesExpected',80,'commissionExpected',14.4,'protectedSnapshotSha256',j#>>'{historicalN,protectedSnapshotSha256}',
  'soignantModifiedBefore',soignant_modified_before,'soignantModifiedAfter',transaction_timestamp(),
  'syntheticPreparation',true,'providerInvoked',false,'documentsGenerated',false,'capacityAllocated',false)::text,true);
END;
$reuse_new_mission$;$exact_preparation$;
 baseline jsonb;
 profile_time timestamptz;
 conversion_times jsonb;
 admin_metadata jsonb;
 receipt jsonb;
 overlap_start timestamptz;
 overlap_end timestamptz;
 expected text;
 i integer;
BEGIN
 baseline:=jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
 SELECT modifie_le INTO STRICT profile_time FROM public.soignants WHERE id=s;
 SELECT jsonb_agg(jsonb_build_object('id',id,'time',modifie_le) ORDER BY id) INTO conversion_times FROM public.suivi_conversion_3200h WHERE soignant_id=s;
 IF profile_time IS NULL OR profile_time>=transaction_timestamp()
 THEN RAISE EXCEPTION 'WITNESS_PROFILE_TIMESTAMP_NOT_HISTORICAL'; END IF;
 IF conversion_times IS NULL OR jsonb_array_length(conversion_times)<>1
 THEN RAISE EXCEPTION 'WITNESS_CONVERSION_ROW_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=s
  AND (modifie_le IS NULL OR modifie_le>=transaction_timestamp()))
 THEN RAISE EXCEPTION 'WITNESS_CONVERSION_TIMESTAMP_NOT_HISTORICAL'; END IF;
 SELECT raw_app_meta_data INTO STRICT admin_metadata FROM auth.users WHERE id=a;
 SELECT k.debut,k.fin INTO STRICT overlap_start,overlap_end
  FROM public.mission_creneaux k WHERE k.mission_id=hm AND k.type_creneau='PREVISIONNEL'
   AND k.debut<clock_timestamp();
 FOR i IN 0..4 LOOP
  expected:=CASE i WHEN 1 THEN 'REUSE_HISTORICAL_N_NOT_CLOSED'
   WHEN 2 THEN 'REUSE_FRESH_SYNTHETIC_ADMIN_REQUIRED' WHEN 3 THEN 'REUSE_CALENDAR_REFUSED'
   WHEN 4 THEN 'REUSE_OVERRIDE_REFUSED' END;
  BEGIN
   IF i=1 THEN UPDATE private.stripe_connect_test_capacities SET revoked_at=NULL WHERE id=hc;
   ELSIF i=2 THEN UPDATE auth.users SET raw_app_meta_data=jsonb_set(raw_app_meta_data,
    '{jolene_connect_fixture_owner}','"PG17_WRONG_OWNER"'::jsonb) WHERE id=a;
   ELSIF i=3 THEN PERFORM set_config('jolene.connect_reuse_manifest',jsonb_set(j,'{calendar}',
    (j->'calendar')||jsonb_build_object('periodStart',overlap_start::date,'periodEnd',overlap_start::date+6,
     'pastStart',overlap_start,'pastEnd',overlap_end))::text,true);
   ELSIF i=4 THEN PERFORM set_config('jolene.tva_mission_managed','true',true);
   END IF;
   EXECUTE preparation;
   IF i<>0 THEN RAISE EXCEPTION 'WITNESS_EXPECTED_REFUSAL_MISSING'; END IF;
   receipt:=current_setting('jolene.connect_reuse_receipt')::jsonb;
   IF receipt->>'missionId' IS DISTINCT FROM m::text OR receipt->'adminActive' IS DISTINCT FROM 'false'::jsonb
    OR receipt->'honorairesExpected' IS DISTINCT FROM '80'::jsonb
    OR (receipt->>'soignantModifiedBefore')::timestamptz IS DISTINCT FROM profile_time
    OR (receipt->>'soignantModifiedAfter')::timestamptz IS DISTINCT FROM transaction_timestamp()
   THEN RAISE EXCEPTION 'WITNESS_POSITIVE_RECEIPT_REQUIRED'; END IF;
   RAISE EXCEPTION USING ERRCODE='ZX001', MESSAGE='WITNESS_POSITIVE_ROLLBACK';
  EXCEPTION
   WHEN SQLSTATE 'ZX001' THEN IF i<>0 THEN RAISE; END IF;
   WHEN SQLSTATE 'P0001' THEN IF i=0 OR SQLERRM IS DISTINCT FROM expected THEN RAISE; END IF;
  END;
  IF (jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
)) IS DISTINCT FROM baseline
   OR (SELECT modifie_le FROM public.soignants WHERE id=s) IS DISTINCT FROM profile_time
   OR (SELECT jsonb_agg(jsonb_build_object('id',id,'time',modifie_le) ORDER BY id) FROM public.suivi_conversion_3200h WHERE soignant_id=s) IS DISTINCT FROM conversion_times
   OR (SELECT raw_app_meta_data FROM auth.users WHERE id=a) IS DISTINCT FROM admin_metadata
   OR EXISTS(SELECT 1 FROM public.missions WHERE id=m)
   OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id=m)
   OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team OR user_id=a)
   OR current_setting('jolene.connect_reuse_manifest')::jsonb IS DISTINCT FROM j
   OR NULLIF(current_setting('jolene.tva_mission_managed',true),'') IS NOT NULL
  THEN RAISE EXCEPTION 'WITNESS_CASE_ROLLBACK_CHANGED_STATE'; END IF;
 END LOOP;
END $witness$;
SELECT jsonb_build_object('scope','PG17_SYNTHETIC_ONLY','model_sha256','9168901ab6a48afbb8c530e07c8b49e21f07bb4650bd326dd7ff31b013d108dd',
 'positive',1,'refusals',4,'subtransactions_restored',true,'provider',false) AS witness;

-- CAPACITY OPERATOR MODELS: exact DO bodies; outer transaction remains synthetic and ROLLBACK-only.
-- Readback DO runs inside this writing fixture transaction: its readOnly=false is not hidden.
SET LOCAL standard_conforming_strings=on;
-- Retain one new mission for capacity cases; this is the same preparation DO already tested above.
DO $reuse_new_mission$
DECLARE
 j jsonb:=current_setting('jolene.connect_reuse_manifest')::jsonb;
 s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
 e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
 a uuid:=(j#>>'{new,adminId}')::uuid;
 m uuid:=(j#>>'{new,missionId}')::uuid;
 team uuid:=(j#>>'{new,adminTeamId}')::uuid;
 hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
 ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
 hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
 hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
 hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
 ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
 ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
 hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
 week_start date:=(j#>>'{calendar,periodStart}')::date;
 week_end date:=(j#>>'{calendar,periodEnd}')::date;
 past_start timestamptz:=(j#>>'{calendar,pastStart}')::timestamptz;
 past_end timestamptz:=(j#>>'{calendar,pastEnd}')::timestamptz;
 future_start timestamptz:=(j#>>'{calendar,futureStart}')::timestamptz;
 future_end timestamptz:=(j#>>'{calendar,futureEnd}')::timestamptz;
 historical_capacity private.stripe_connect_test_capacities;
 o private.stripe_connect_avant_transfert;
 before_state jsonb;
 after_state jsonb;
 catalogue jsonb;
 r jsonb;
 n text;
 v_count integer;
 soignant_modified_before timestamptz;
BEGIN
 -- Ne pas masquer un appel utilisateur préexistant en remplaçant son contexte.
 IF current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin')
  OR current_setting('server_version_num')::integer/10000<>17
  OR auth.uid() IS NOT NULL
  OR j->'schemaVersion' IS DISTINCT FROM '1'::jsonb
  OR j->>'purpose' IS DISTINCT FROM 'CONNECT_REFUND_REUSE_ACTORS_NEW_MISSION_V1'
  OR j->'ready' IS DISTINCT FROM 'true'::jsonb
  OR j->>'projectRef' IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
  OR COALESCE(j->>'sourceSha','') !~ '^[a-f0-9]{40}$'
  OR COALESCE(j->>'runId','') !~ '^connect-test-[a-z0-9-]{8,64}$'
  OR j->>'ownerMarker' IS DISTINCT FROM (j->>'runId')||':'||(j->>'sourceSha')
  OR j->>'issuedAt' IS NULL OR j->>'expiresAt' IS NULL
  OR (j->>'issuedAt')::timestamptz>clock_timestamp()
  OR (j->>'expiresAt')::timestamptz<=clock_timestamp()
  OR (j->>'expiresAt')::timestamptz-(j->>'issuedAt')::timestamptz>interval '4 hours'
  OR j->>'runId' IS NOT DISTINCT FROM j#>>'{actorProvenance,runId}'
  OR COALESCE(j#>>'{actorProvenance,sourceSha}','') !~ '^[a-f0-9]{40}$'
  OR COALESCE(j#>>'{actorProvenance,runId}','') !~ '^connect-test-[a-z0-9-]{8,64}$'
  OR j#>>'{actorProvenance,ownerMarker}' IS DISTINCT FROM (j#>>'{actorProvenance,runId}')||':'||(j#>>'{actorProvenance,sourceSha}')
  OR COALESCE(j#>>'{actorProvenance,manifestSha256}','') !~ '^[a-f0-9]{64}$'
  OR COALESCE(j#>>'{historicalN,proofSha256}','') !~ '^[a-f0-9]{64}$'
  OR COALESCE(j#>>'{historicalN,protectedSnapshotSha256}','') !~ '^[a-f0-9]{64}$'
  OR COALESCE(j#>>'{reviewedEvidence,reviewer}','')=''
 THEN RAISE EXCEPTION 'REUSE_CONTEXT_OR_PROVENANCE_REFUSED'; END IF;
 FOREACH n IN ARRAY ARRAY['protocolSha256','adminAuthIntentSha256','adminAuthReceiptSha256',
  'providerReadinessReceiptSha256','providerHistoryReceiptSha256','edgeGenerationReceiptSha256','calendarReceiptSha256'] LOOP
  IF COALESCE(j#>>ARRAY['reviewedEvidence',n],'') !~ '^[a-f0-9]{64}$'
  THEN RAISE EXCEPTION 'REUSE_REVIEWED_EVIDENCE_REQUIRED'; END IF;
 END LOOP;
 FOREACH n IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
  'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
  'jolene.tva_mission_managed','app.internal_operation','app.test_bypass_protections'] LOOP
  IF NULLIF(current_setting(n,true),'') IS NOT NULL THEN RAISE EXCEPTION 'REUSE_OVERRIDE_REFUSED'; END IF;
 END LOOP;
 IF (SELECT count(DISTINCT x) FROM unnest(ARRAY[s,e,a,m,team,hc,ho,hm,hh,hf,ht,ha,hteam]) x)<>13
  OR EXISTS(SELECT 1 FROM public.missions WHERE id=m OR intitule='RECETTE CONNECT TEST SYNTHETIQUE '||(j->>'runId'))
  OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team OR user_id=a)
  OR EXISTS(SELECT 1 FROM public.soignants WHERE id=a)
  OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=a)
  OR EXISTS(SELECT 1 FROM public.presences WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.factures WHERE mission_id=m)
 THEN RAISE EXCEPTION 'REUSE_NEW_IDENTIFIERS_REQUIRED'; END IF;
 -- Les modèles restent bornés à N seule : toute troisième histoire est refusée.
 LOCK TABLE private.stripe_connect_release_gate IN SHARE MODE;
 LOCK TABLE private.stripe_connect_test_capacities IN SHARE MODE;
 LOCK TABLE private.stripe_connect_avant_transfert IN SHARE MODE;
 IF (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
  OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
  OR (SELECT count(*) FROM private.stripe_connect_test_capacities)<>1
  OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
 THEN RAISE EXCEPTION 'REUSE_EXACT_CLOSED_N_REQUIRED'; END IF;
 SELECT * INTO STRICT historical_capacity FROM private.stripe_connect_test_capacities WHERE id=hc;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=ho;
 IF historical_capacity.enabled IS DISTINCT FROM FALSE OR historical_capacity.revoked_at IS NULL OR historical_capacity.revoked_at>clock_timestamp()
  OR historical_capacity.protocol<>'CONNECT_STAGING_TEST_V1' OR historical_capacity.project_ref<>'mejpriaetwgtcstbgfid'
  OR historical_capacity.platform_account_id<>'acct_1T9pt0EVhQ7cb53W'
  OR historical_capacity.livemode IS DISTINCT FROM FALSE OR historical_capacity.transfers_allowed IS DISTINCT FROM FALSE
  OR historical_capacity.max_checkouts<>1 OR historical_capacity.max_refunds<>1 OR historical_capacity.checkout_reserved_at IS NULL
  OR historical_capacity.refund_reserved_at IS NULL OR historical_capacity.claim_reserved_at IS NULL OR historical_capacity.operation_id IS DISTINCT FROM ho
  OR historical_capacity.etablissement_id IS DISTINCT FROM e OR historical_capacity.soignant_id IS DISTINCT FROM s
  OR historical_capacity.mission_id IS DISTINCT FROM hm OR historical_capacity.facture_honoraire_id IS DISTINCT FROM hh OR historical_capacity.facture_commission_id IS DISTINCT FROM hf
  OR historical_capacity.customer_id IS DISTINCT FROM j#>>'{actorProvenance,customerId}'
  OR historical_capacity.destination_id IS DISTINCT FROM j#>>'{actorProvenance,destinationId}'
  OR historical_capacity.destination_id IN('acct_1T9pt0EVhQ7cb53W','acct_1UKlZCEVhQI2aaZg')
  OR o.orientation IS DISTINCT FROM 'REFUND' OR o.refund_status IS DISTINCT FROM 'SUCCEEDED'
  OR o.refund_id IS DISTINCT FROM j#>>'{historicalN,refundId}' OR o.refund_id IS NULL
  OR o.session_id IS DISTINCT FROM j#>>'{historicalN,sessionId}' OR o.trace_id IS DISTINCT FROM ht
  OR o.succeeded_at IS NULL OR o.review_code IS NOT NULL OR o.owner_token IS NOT NULL OR o.lease_until IS NOT NULL
  OR o.livemode IS DISTINCT FROM FALSE OR NOT private.fn_connect_test_operation_connue(ho)
  OR NOT EXISTS(SELECT 1 FROM public.stripe_transfers WHERE id=ht AND statut='REMBOURSE'
   AND stripe_transfer_id IS NULL AND stripe_checkout_session_id=o.session_id)
  OR NOT EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=hteam AND user_id=ha AND actif IS FALSE)
 THEN RAISE EXCEPTION 'REUSE_HISTORICAL_N_NOT_CLOSED'; END IF;
 -- Catalogue identique au préflight historique (booléen Vault seulement, aucune valeur exportée).
 SELECT catalogue_source.catalogue INTO catalogue FROM (SELECT jsonb_build_object(
    'routines', (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,''),E'\n' ORDER BY p.oid::regprocedure::text))
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')),
    'triggers', (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text,E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth','storage')),
    'columns', (SELECT md5(string_agg(n.nspname::text||'.'||c.relname::text||'.'||a.attname::text||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),''),E'\n' ORDER BY n.nspname,c.relname,a.attnum))
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname IN ('public','private','auth','storage')),
    'commissionHelper',md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure)),
    'queuedRequests',(SELECT count(*)::int FROM net.http_request_queue),
    'activeCrons',(SELECT count(*)::int FROM cron.job WHERE active),
    'runningCrons',(SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')),
    'generationUrlAbsent',NOT EXISTS(SELECT 1 FROM public.parametres_litiges WHERE cle='generate_invoice_url' AND coalesce(length(valeur),0)>0),
    'supportStagingExact',coalesce((SELECT nullif(btrim(decrypted_secret),'')='https://mejpriaetwgtcstbgfid.supabase.co' FROM vault.decrypted_secrets WHERE name='supabase_url' LIMIT 1),false)
  ) AS catalogue) catalogue_source;
 IF catalogue IS DISTINCT FROM j->'catalogue'
  OR catalogue->'queuedRequests' IS DISTINCT FROM '0'::jsonb
  OR catalogue->'activeCrons' IS DISTINCT FROM '0'::jsonb
  OR catalogue->'runningCrons' IS DISTINCT FROM '0'::jsonb
  OR catalogue->'generationUrlAbsent' IS DISTINCT FROM 'true'::jsonb
  OR catalogue->'supportStagingExact' IS DISTINCT FROM 'true'::jsonb
  OR EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
  OR EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
  OR EXISTS(SELECT 1 FROM public.stripe_webhook_events WHERE traitement_commence_le IS NOT NULL AND traite_le IS NULL)
  OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e))
 THEN RAISE EXCEPTION 'REUSE_CATALOGUE_OR_QUIESCENCE_REFUSED'; END IF;
 -- E/S exacts, liens et mandat existants : aucune réparation de profil dans ce modèle.
 IF (SELECT count(*) FROM auth.users u WHERE u.id IN(s,e) AND u.deleted_at IS NULL
  AND u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
  AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
  AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=j#>>'{actorProvenance,ownerMarker}'
  AND u.email='connect-test-'||u.id::text||'@example.invalid'
  AND ((u.id=s AND u.raw_app_meta_data->>'role'='SOIGNANT')
   OR (u.id=e AND u.raw_app_meta_data->>'role'='ADMIN_ETABLISSEMENT' AND u.raw_app_meta_data->>'etablissement_id'=e::text)))<>2
  OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=s AND est_compte_test IS TRUE
   AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE' AND supprime_le IS NULL AND statut_compte::text='ACTIF'
   AND stripe_account_id=historical_capacity.destination_id AND type_exercice::text='LIBERAL'
   AND mandat_facturation_signe IS TRUE AND mandat_facturation_version='1.4')
  OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND est_compte_test IS TRUE
   AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE' AND supprime_le IS NULL AND stripe_customer_id=historical_capacity.customer_id)
  OR (SELECT count(*) FROM public.etablissements WHERE stripe_customer_id=historical_capacity.customer_id)<>1
  OR (SELECT count(*) FROM public.soignants WHERE stripe_account_id=historical_capacity.destination_id)<>1
  OR (SELECT count(*) FROM public.stripe_connect_onboarding WHERE soignant_id=s)<>1
  OR NOT EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE soignant_id=s AND stripe_account_id=historical_capacity.destination_id
   AND statut='COMPLET' AND onboarding_complete IS TRUE AND charges_enabled IS TRUE AND payouts_enabled IS TRUE AND details_submitted IS TRUE)
  OR NOT EXISTS(SELECT 1 FROM public.mandats_facturation_signatures WHERE id=(j#>>'{actorProvenance,mandatId}')::uuid
   AND soignant_id=s AND version='1.4' AND revoked_at IS NULL)
  OR (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(s,e)
   AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
 THEN RAISE EXCEPTION 'REUSE_ACTORS_LINKS_MANDATE_REFUSED'; END IF;
 -- A est un Auth synthétique créé pour cette exécution, jamais un admin historique.
 IF NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=a AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
  AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
  AND u.created_at>=(j->>'issuedAt')::timestamptz AND u.created_at<=clock_timestamp()
  AND u.email='connect-test-'||a::text||'@example.invalid'
  AND u.raw_app_meta_data->>'role'='ADMIN_PLATEFORME'
  AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
  AND u.raw_app_meta_data->'is_test_playwright'='true'::jsonb
  AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=j->>'ownerMarker')
  OR EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=a)
 THEN RAISE EXCEPTION 'REUSE_FRESH_SYNTHETIC_ADMIN_REQUIRED'; END IF;
 SELECT jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
) INTO before_state;
 IF encode(extensions.digest(convert_to(before_state::text,'UTF8'),'sha256'),'hex')
  IS DISTINCT FROM j#>>'{historicalN,protectedSnapshotSha256}'
 THEN RAISE EXCEPTION 'REUSE_PROTECTED_BASELINE_CHANGED'; END IF;
 SELECT modifie_le INTO STRICT soignant_modified_before FROM public.soignants WHERE id=s;
 -- Horaires explicitement épinglés pour éviter de recopier 09h-13h sur N.
 IF week_start IS NULL OR week_end IS NULL OR past_start IS NULL OR past_end IS NULL OR future_start IS NULL OR future_end IS NULL
  OR extract(isodow FROM week_start)<>1 OR week_end<>week_start+6 OR week_end>=current_date
  OR past_start::date<>week_start OR past_end::date<>week_start OR past_end-past_start<>interval '4 hours'
  OR future_start::date<=current_date OR future_end::date<>future_start::date OR future_end-future_start<>interval '4 hours'
  OR future_start::date>current_date+21 OR past_start::date<current_date-35
  OR public.fn_est_jour_ferie(week_start) OR public.fn_est_jour_ferie(future_start::date)
  OR EXISTS(SELECT 1 FROM public.mission_creneaux k JOIN public.missions x ON x.id=k.mission_id
   WHERE x.soignant_assigne_id=s AND x.statut IN('ASSIGNEE','EN_COURS','TERMINEE')
    AND ((k.debut<past_end AND k.fin>past_start) OR (k.debut<future_end AND k.fin>future_start)))
 THEN RAISE EXCEPTION 'REUSE_CALENDAR_REFUSED'; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 -- Bloc de création dérivé du seed Connect ; triggers actifs, aucun override.
 INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
  duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,
  choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente)
 VALUES(m,e,'RECETTE CONNECT TEST SYNTHETIQUE '||(j->>'runId'),'IDE',future_start,future_end,
  4,20,'EN_COURS',s,'LIBERAL',NULL,'LIBERAL','NOTE_HONORAIRES','DIRECT','HEBDO_ET_FINALE',false);
 UPDATE public.missions SET type_contrat_applique='LIBERAL' WHERE id=m;
 UPDATE public.mission_creneaux SET debut=past_start,fin=past_end WHERE mission_id=m AND type_creneau='PREVISIONNEL';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'REUSE_INITIAL_SLOT_NOT_UNIQUE'; END IF;
 INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre)
 VALUES(m,future_start,future_end,'PREVISIONNEL',false,2),(m,past_start,past_end,'EFFECTIF',false,3);
 INSERT INTO public.equipe_admin(id,user_id,nom,prenom,email,poste,actif,acces_groupes)
 VALUES(team,a,'SYNTHETIQUE','CONNECT REUSE TEST','connect-test-'||a::text||'@example.invalid','RECETTE CONNECT TEST SANS SESSION',true,
  ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 IF public.est_admin() IS NOT TRUE THEN RAISE EXCEPTION 'REUSE_CANONICAL_ADMIN_REFUSED'; END IF;
 r:=public.fn_admin_proposer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE',
  'RECETTE SYNTHETIQUE sans prestation ni attestation réelle — '||(j->>'runId'));
 IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva' IS DISTINCT FROM 'A_CONFIRMER'
 THEN RAISE EXCEPTION 'REUSE_TVA_PROPOSAL_REFUSED'; END IF;
 PERFORM set_config('request.jwt.claim.sub',s::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'role','authenticated')::text,true);
 r:=public.fn_confirmer_nature_tva_mission(m,'SOIN_THERAPEUTIQUE_EXONERE');
 IF r->'success' IS DISTINCT FROM 'true'::jsonb OR r->>'statut_validation_tva' IS DISTINCT FROM 'CONFIRMEE'
 THEN RAISE EXCEPTION 'REUSE_TVA_CONFIRMATION_REFUSED'; END IF;
 UPDATE public.equipe_admin SET actif=false WHERE id=team AND user_id=a AND actif IS TRUE;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'REUSE_ADMIN_DEACTIVATION_REFUSED'; END IF;
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 IF public.est_admin() IS NOT FALSE OR EXISTS(SELECT 1 FROM public.equipe_admin WHERE user_id=a AND actif)
  OR EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=a)
 THEN RAISE EXCEPTION 'REUSE_ADMIN_STILL_PRIVILEGED'; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=m AND etablissement_id=e AND soignant_assigne_id=s
  AND statut='EN_COURS' AND type_contrat_applique::text='LIBERAL' AND nb_creneaux=2
  AND duree_heures=8 AND duree_heures_effective=4 AND net_a_payer=160 AND montant_commission_ht=24
  AND statut_validation_tva='CONFIRMEE' AND nature_tva_declaree_par=a AND revue_tva_resolue_par=a
  AND nature_tva_confirmee_par=s AND fige_le IS NULL AND debut_le::date=week_start AND fin_le::date=future_start::date)
  OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.factures WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.paiements_mission WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=m)
  OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='MISSION:'||m::text)
  OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e,a))
  OR EXISTS(SELECT 1 FROM net.http_request_queue)
  OR (SELECT count(*) FROM private.stripe_connect_test_capacities)<>1
  OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
 THEN RAISE EXCEPTION 'REUSE_UNEXPECTED_PREPARATION_EFFECT'; END IF;
 r:=public.fn_calculer_montant_periode(m,week_start,week_end);
 IF (r->>'montant_ht_periode')::numeric IS DISTINCT FROM 80 THEN RAISE EXCEPTION 'REUSE_PRORATA_REFUSED'; END IF;
 SELECT jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
) INTO after_state;
 IF after_state IS DISTINCT FROM before_state THEN RAISE EXCEPTION 'REUSE_PROTECTED_ROWS_CHANGED'; END IF;
 IF (SELECT modifie_le FROM public.soignants WHERE id=s) IS DISTINCT FROM transaction_timestamp()
  OR EXISTS(SELECT 1 FROM public.suivi_conversion_3200h WHERE soignant_id=s AND modifie_le IS DISTINCT FROM transaction_timestamp())
 THEN RAISE EXCEPTION 'REUSE_NONCANONICAL_PROFILE_TIMESTAMP'; END IF;
 PERFORM set_config('jolene.connect_reuse_receipt',jsonb_build_object('runId',j->>'runId','missionId',m,
  'adminId',a,'adminTeamId',team,'adminActive',false,'periodStart',week_start,'periodEnd',week_end,
  'honorairesExpected',80,'commissionExpected',14.4,'protectedSnapshotSha256',j#>>'{historicalN,protectedSnapshotSha256}',
  'soignantModifiedBefore',soignant_modified_before,'soignantModifiedAfter',transaction_timestamp(),
  'syntheticPreparation',true,'providerInvoked',false,'documentsGenerated',false,'capacityAllocated',false)::text,true);
END;
$reuse_new_mission$;
DO $synthetic_documents$
DECLARE
 p jsonb:=current_setting('jolene.connect_reuse_manifest')::jsonb;
 j jsonb;
 w_s uuid:=(p#>>'{actorProvenance,soignantId}')::uuid;
 w_e uuid:=(p#>>'{actorProvenance,etablissementId}')::uuid;
 w_m uuid:=(p#>>'{new,missionId}')::uuid;
 w_h uuid:='77000000-0000-4000-8000-000000000001';
 w_c uuid;
 w_result jsonb;
 w_key text;
 w_started timestamptz:=clock_timestamp()-interval '1 second';
 w_pdf_declaration text:='PG17_SYNTHETIC_ONLY_NO_PDF_FILE_NEW_COHORT';
 w_xml_declaration text:='PG17_SYNTHETIC_ONLY_NO_XML_FILE_NEW_COHORT';
BEGIN
 -- Declared document rows and declaration digests only. No file exists; no generation/provider is proved.
 INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
  montant_ht,montant_tva,montant_ttc,taux_tva,statut,mandat_version,periode_debut,periode_fin,
  est_facture_finale_mission,quantite_heures_snapshot,taux_horaire_snapshot,pdf_s3_key,facturx_xml_url)
 VALUES(w_h,public.next_invoice_number(w_s),w_s,w_e,w_m,80,0,80,0,'EMISE','1.4',
  (p#>>'{calendar,periodStart}')::date,(p#>>'{calendar,periodEnd}')::date,false,4,20,
  'pg17-synthetic-only/new-no-file.pdf','pg17-synthetic-only/new-no-file.xml');
 INSERT INTO public.factures_honoraires_documents(facture_honoraire_id,pdf_s3_key,facturx_xml_url,pdf_sha256,xml_sha256,motif_generation)
 VALUES(w_h,'pg17-synthetic-only/new-no-file.pdf','pg17-synthetic-only/new-no-file.xml',
  encode(extensions.digest(convert_to(w_pdf_declaration,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(w_xml_declaration,'UTF8'),'sha256'),'hex'),'PG17_SYNTHETIC_ONLY_NO_DOCUMENT_BYTES');
 w_result:=public.fn_preparer_facture_commission_periode(w_h);
 IF w_result->'success' IS DISTINCT FROM 'true'::jsonb OR (w_result->>'montant_ttc')::numeric IS DISTINCT FROM 14.4
 THEN RAISE EXCEPTION 'WITNESS_NEW_COMMISSION_REFUSED'; END IF;
 w_c:=(w_result->>'facture_id')::uuid;
 j:=jsonb_build_object('schemaVersion',2,'ready',true,'purpose','CONNECT_STAGING_TEST_REUSE_CLOSED_N_V1',
  'evidenceScope','PG17_SYNTHETIC_ONLY','providerEvidence',false,'documentFilesExist',false,
  'windowStartsAt',w_started,'actorProvenance',p->'actorProvenance','catalogue',p->'catalogue',
  'historicalN',(p->'historicalN')||jsonb_build_object('paymentIntentId','pi_PG17SyntheticN','chargeId','ch_PG17SyntheticN',
   'litigeId',(SELECT litige_id FROM private.stripe_connect_avant_transfert WHERE id=(p#>>'{historicalN,operationId}')::uuid)),
  'fixture',jsonb_build_object('sourceSha',p->>'sourceSha','runId',p->>'runId','ownerMarker',p->>'ownerMarker',
   'adminId',p#>>'{new,adminId}','adminTeamId',p#>>'{new,adminTeamId}'),
  'reviewedEvidence',jsonb_build_object('independentReviewPath','PG17_SYNTHETIC_ONLY_NOT_EXTERNAL_REVIEW',
   'providerObservedAt',w_started),
  'capacity',jsonb_build_object('id','77000000-0000-4000-8000-000000000002',
   'protocol','CONNECT_STAGING_TEST_V1','project_ref','mejpriaetwgtcstbgfid','run_id','f1-PG17SyntheticReuse',
   'server_sha','01b135471e1e6ee7ee31439ffc248c8b8519260c','ui_sha','01b135471e1e6ee7ee31439ffc248c8b8519260c','expires_at',w_started+interval '1 hour',
   'etablissement_id',w_e,'soignant_id',w_s,'mission_id',w_m,'facture_honoraire_id',w_h,'facture_commission_id',w_c,
   'platform_account_id','acct_1T9pt0EVhQ7cb53W','customer_id',p#>>'{actorProvenance,customerId}',
   'destination_id',p#>>'{actorProvenance,destinationId}','soignant_cents',8000,'commission_cents',1440,'total_cents',9440));
 FOREACH w_key IN ARRAY ARRAY['encryptedEnvelopeSha256','preparedReceiptSha256','documentsReceiptSha256','preparationSqlSha256'] LOOP
  j:=jsonb_set(j,ARRAY['fixture',w_key],to_jsonb(encode(extensions.digest(convert_to(
   jsonb_build_object('scope','PG17_SYNTHETIC_ONLY','notExternalEvidence',true,'field',w_key,
    'preparationReceipt',current_setting('jolene.connect_reuse_receipt')::jsonb,
    'pdfDeclaration',w_pdf_declaration,'xmlDeclaration',w_xml_declaration)::text,'UTF8'),'sha256'),'hex')));
 END LOOP;
 FOREACH w_key IN ARRAY ARRAY['candidateSourceManifestSha256','closedInstallationReceiptSha256','edgeDeploymentReceiptSha256',
  'exactBuildReceiptSha256','servedBuildReceiptSha256','customerAccountOnboardingReceiptSha256','providerHistoryBalanceReceiptSha256',
  'pg17ReceiptSha256','operatorPreflightReceiptSha256'] LOOP
  j:=jsonb_set(j,ARRAY['reviewedEvidence',w_key],to_jsonb(encode(extensions.digest(convert_to(
   jsonb_build_object('scope','PG17_SYNTHETIC_ONLY','notExternalEvidence',true,'field',w_key,'syntheticInput',p)::text,'UTF8'),'sha256'),'hex')));
 END LOOP;
 PERFORM set_config('jolene.capacity_reuse_synthetic_manifest',j::text,true);
END $synthetic_documents$;
DO $capacity_witness$
DECLARE
 j jsonb:=current_setting('jolene.capacity_reuse_synthetic_manifest')::jsonb;
 s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
 e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
 a uuid:=(j#>>'{fixture,adminId}')::uuid;
 team uuid:=(j#>>'{fixture,adminTeamId}')::uuid;
 hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
 ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
 hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
 hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
 hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
 ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
 ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
 hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
 w_m uuid:=(j#>>'{capacity,mission_id}')::uuid;
 w_h uuid:=(j#>>'{capacity,facture_honoraire_id}')::uuid;
 w_c uuid:=(j#>>'{capacity,facture_commission_id}')::uuid;
 w_cap uuid:=(j#>>'{capacity,id}')::uuid;
 w_op uuid:='77000000-0000-4000-8000-000000000003';
 w_trace uuid:='77000000-0000-4000-8000-000000000004';
 w_litige uuid:='77000000-0000-4000-8000-000000000005';
 w_third uuid:='77000000-0000-4000-8000-000000000006';
 w_allocation_template constant text:=$exact_allocation$DO $reviewed_reuse_allocation$
DECLARE
  j constant jsonb := {{ALLOCATION_JSON_LITERAL}}::jsonb;
  manifest_sha constant text := '{{SHA256_EXACT_MANIFEST_BYTES}}';
  d constant text := '{{FINAL_D_SHA40}}';
  s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
  e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
  a uuid:=(j#>>'{fixture,adminId}')::uuid;
  team uuid:=(j#>>'{fixture,adminTeamId}')::uuid;
  hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
  ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
  hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
  hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
  hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
  ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
  ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
  hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
  cap_id uuid:=(j#>>'{capacity,id}')::uuid;
  new_capacity private.stripe_connect_test_capacities;
  started timestamptz:=(j->>'windowStartsAt')::timestamptz;
  catalogue jsonb;
  before_n jsonb;
  after_n jsonb;
  role_name text;
  evidence_key text;
  n integer;
BEGIN
  IF current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin')
    OR current_setting('server_version_num')::integer/10000<>17 OR auth.uid() IS NOT NULL
    OR j->'schemaVersion' IS DISTINCT FROM '2'::jsonb OR j->'ready' IS DISTINCT FROM 'true'::jsonb
    OR j->>'purpose' IS DISTINCT FROM 'CONNECT_STAGING_TEST_REUSE_CLOSED_N_V1'
    OR d !~ '^[a-f0-9]{40}$' OR manifest_sha !~ '^[a-f0-9]{64}$'
    OR cap_id IS NULL OR hc IS NULL OR cap_id=hc
    OR j#>>'{capacity,server_sha}' IS DISTINCT FROM d OR j#>>'{capacity,ui_sha}' IS DISTINCT FROM d
  THEN RAISE EXCEPTION 'OPERATOR_CONTEXT_REFUSED'; END IF;
  -- Ces champs fixes ne viennent jamais du navigateur ou des documents métier.
  new_capacity:=jsonb_populate_record(NULL::private.stripe_connect_test_capacities,
    (j->'capacity') || jsonb_build_object('source_manifest_sha256',manifest_sha,
      'enabled',false,'installed_at',clock_timestamp(),'livemode',false,
      'max_checkouts',1,'max_refunds',1,'transfers_allowed',false,
      'operation_id',NULL,'checkout_reserved_at',NULL,'refund_reserved_at',NULL,
      'claim_reserved_at',NULL,'revoked_at',NULL));
  IF new_capacity.etablissement_id IS DISTINCT FROM e OR new_capacity.soignant_id IS DISTINCT FROM s
    OR new_capacity.customer_id IS DISTINCT FROM j#>>'{actorProvenance,customerId}'
    OR new_capacity.destination_id IS DISTINCT FROM j#>>'{actorProvenance,destinationId}'
    OR new_capacity.protocol IS DISTINCT FROM 'CONNECT_STAGING_TEST_V1' OR new_capacity.project_ref IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
    OR new_capacity.platform_account_id IS DISTINCT FROM 'acct_1T9pt0EVhQ7cb53W'
    OR new_capacity.destination_id IN('acct_1T9pt0EVhQ7cb53W','acct_1UKlZCEVhQI2aaZg')
    OR (new_capacity.soignant_cents,new_capacity.commission_cents,new_capacity.total_cents) IS DISTINCT FROM (8000::bigint,1440::bigint,9440::bigint)
    OR started IS NULL OR new_capacity.expires_at IS NULL OR new_capacity.expires_at<>started+interval '1 hour'
    OR clock_timestamp()<started OR new_capacity.expires_at-clock_timestamp()>interval '1 hour'
    OR to_timestamp(floor(extract(epoch FROM new_capacity.expires_at)))-clock_timestamp()<interval '31 minutes'
    OR COALESCE(new_capacity.run_id,'') !~ '^f1-[A-Za-z0-9-]{1,80}$'
    OR COALESCE(j#>>'{fixture,sourceSha}','') !~ '^[a-f0-9]{40}$'
    OR COALESCE(j#>>'{fixture,runId}','') !~ '^connect-test-[a-z0-9-]{8,64}$'
    OR j#>>'{fixture,ownerMarker}' IS DISTINCT FROM (j#>>'{fixture,runId}')||':'||(j#>>'{fixture,sourceSha}')
    OR COALESCE(j#>>'{actorProvenance,sourceSha}','') !~ '^[a-f0-9]{40}$'
    OR COALESCE(j#>>'{actorProvenance,runId}','') !~ '^connect-test-[a-z0-9-]{8,64}$'
    OR j#>>'{actorProvenance,ownerMarker}' IS DISTINCT FROM (j#>>'{actorProvenance,runId}')||':'||(j#>>'{actorProvenance,sourceSha}')
    OR j#>>'{fixture,runId}' IS NOT DISTINCT FROM j#>>'{actorProvenance,runId}'
    OR COALESCE(j#>>'{actorProvenance,manifestSha256}','') !~ '^[a-f0-9]{64}$'
    OR COALESCE(j#>>'{historicalN,proofSha256}','') !~ '^[a-f0-9]{64}$'
    OR COALESCE(j#>>'{historicalN,protectedSnapshotSha256}','') !~ '^[a-f0-9]{64}$'
    OR (SELECT count(DISTINCT id) FROM unnest(ARRAY[s,e,a,team,hc,ho,hm,hh,hf,ht,ha,hteam,new_capacity.id,new_capacity.mission_id,new_capacity.facture_honoraire_id,new_capacity.facture_commission_id]) id)<>16
  THEN RAISE EXCEPTION 'OPERATOR_IDENTITY_OR_WINDOW_REFUSED'; END IF;
  FOREACH evidence_key IN ARRAY ARRAY['candidateSourceManifestSha256','closedInstallationReceiptSha256',
    'edgeDeploymentReceiptSha256','exactBuildReceiptSha256','servedBuildReceiptSha256',
    'customerAccountOnboardingReceiptSha256','providerHistoryBalanceReceiptSha256','pg17ReceiptSha256','operatorPreflightReceiptSha256'] LOOP
    IF COALESCE(j#>>ARRAY['reviewedEvidence',evidence_key],'') !~ '^[a-f0-9]{64}$'
    THEN RAISE EXCEPTION 'OPERATOR_EVIDENCE_REFUSED'; END IF;
  END LOOP;
  FOREACH evidence_key IN ARRAY ARRAY['encryptedEnvelopeSha256','preparedReceiptSha256','documentsReceiptSha256','preparationSqlSha256'] LOOP
    IF COALESCE(j#>>ARRAY['fixture',evidence_key],'') !~ '^[a-f0-9]{64}$'
    THEN RAISE EXCEPTION 'OPERATOR_EVIDENCE_REFUSED'; END IF;
  END LOOP;
  IF COALESCE(j#>>'{reviewedEvidence,independentReviewPath}','')=''
    OR j#>>'{reviewedEvidence,providerObservedAt}' IS NULL
    OR (j#>>'{reviewedEvidence,providerObservedAt}')::timestamptz>clock_timestamp()
    OR (j#>>'{reviewedEvidence,providerObservedAt}')::timestamptz<clock_timestamp()-interval '60 seconds'
  THEN RAISE EXCEPTION 'OPERATOR_FRESH_PROVIDER_EVIDENCE_REQUIRED'; END IF;
  LOCK TABLE private.stripe_connect_test_capacities IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE private.stripe_connect_release_gate IN SHARE MODE;
  LOCK TABLE private.stripe_connect_avant_transfert IN SHARE MODE;
  IF (SELECT count(*) FROM private.stripe_connect_test_capacities)<>1
    OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
    OR EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE id=new_capacity.id OR run_id=new_capacity.run_id)
    OR (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
    OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
    OR (SELECT count(*)=1 AND bool_and(
 h.enabled IS FALSE AND h.revoked_at IS NOT NULL AND h.revoked_at<=clock_timestamp()
 AND h.protocol='CONNECT_STAGING_TEST_V1' AND h.project_ref='mejpriaetwgtcstbgfid'
 AND h.platform_account_id='acct_1T9pt0EVhQ7cb53W' AND h.livemode IS FALSE
 AND h.transfers_allowed IS FALSE AND h.max_checkouts=1 AND h.max_refunds=1
 AND h.checkout_reserved_at IS NOT NULL AND h.refund_reserved_at IS NOT NULL AND h.claim_reserved_at IS NOT NULL
 AND h.soignant_id=s AND h.etablissement_id=e AND h.mission_id=hm
 AND h.facture_honoraire_id=hh AND h.facture_commission_id=hf
 AND h.customer_id=j#>>'{actorProvenance,customerId}' AND h.destination_id=j#>>'{actorProvenance,destinationId}'
 AND o.id=ho AND o.orientation='REFUND' AND o.refund_status='SUCCEEDED' AND o.livemode IS FALSE
 AND o.refund_id=j#>>'{historicalN,refundId}' AND o.session_id=j#>>'{historicalN,sessionId}'
 AND o.payment_intent_id=j#>>'{historicalN,paymentIntentId}' AND o.charge_id=j#>>'{historicalN,chargeId}'
 AND o.litige_id=(j#>>'{historicalN,litigeId}')::uuid
 AND o.succeeded_at IS NOT NULL AND o.review_code IS NULL AND o.owner_token IS NULL AND o.lease_until IS NULL
 AND t.id=ht AND t.statut='REMBOURSE' AND t.stripe_transfer_id IS NULL
 AND t.stripe_checkout_session_id=o.session_id AND t.stripe_payment_intent_id IS NULL AND t.stripe_charge_id IS NULL
 AND t.mission_id=hm AND t.facture_honoraire_id=hh AND t.facture_id=hf AND t.soignant_id=s AND t.etablissement_id=e
 AND old_admin.user_id=ha AND old_admin.actif IS FALSE)
 FROM private.stripe_connect_test_capacities h
 JOIN private.stripe_connect_avant_transfert o ON o.id=h.operation_id
 JOIN public.stripe_transfers t ON t.id=o.trace_id
 JOIN public.equipe_admin old_admin ON old_admin.id=hteam WHERE h.id=hc) IS NOT TRUE
  THEN RAISE EXCEPTION 'OPERATOR_EXACT_CLOSED_N_REQUIRED'; END IF;
  IF private.fn_connect_test_operation_connue(ho) IS NOT TRUE THEN RAISE EXCEPTION 'OPERATOR_EXACT_CLOSED_N_REQUIRED'; END IF;
  before_n:=-- Expression uniquement ; aliases PL/pgSQL j,s,e,a,team et hc/ho/hm/hh/hf/ht/ha/hteam.
-- Valeurs sensibles Auth exclues : ni password/hash, ni recovery token, ni JWT.
-- A/T neufs sont exclus ; toute autre équipe existante est conservée.
jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
  IF encode(extensions.digest(convert_to(before_n::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM j#>>'{historicalN,protectedSnapshotSha256}'
  THEN RAISE EXCEPTION 'OPERATOR_HISTORICAL_PIN_CHANGED'; END IF;
  SELECT c0.catalogue INTO catalogue FROM (SELECT jsonb_build_object(
    'routines', (SELECT md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,''),E'\n' ORDER BY p.oid::regprocedure::text))
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')),
    'triggers', (SELECT md5(string_agg(t.tgrelid::regclass::text||':'||pg_get_triggerdef(t.oid)||':'||t.tgenabled::text,E'\n' ORDER BY t.tgrelid::regclass::text,t.tgname))
      FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname IN ('public','private','auth','storage')),
    'columns', (SELECT md5(string_agg(n.nspname::text||'.'||c.relname::text||'.'||a.attname::text||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),''),E'\n' ORDER BY n.nspname,c.relname,a.attnum))
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attnum>0 AND NOT a.attisdropped AND n.nspname IN ('public','private','auth','storage')),
    'commissionHelper',md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure)),
    'queuedRequests',(SELECT count(*)::int FROM net.http_request_queue),
    'activeCrons',(SELECT count(*)::int FROM cron.job WHERE active),
    'runningCrons',(SELECT count(*)::int FROM cron.job_run_details WHERE end_time IS NULL AND status IN ('starting','running','connecting','sending')),
    'generationUrlAbsent',NOT EXISTS(SELECT 1 FROM public.parametres_litiges WHERE cle='generate_invoice_url' AND coalesce(length(valeur),0)>0),
    'supportStagingExact',coalesce((SELECT nullif(btrim(decrypted_secret),'')='https://mejpriaetwgtcstbgfid.supabase.co' FROM vault.decrypted_secrets WHERE name='supabase_url' LIMIT 1),false)
  ) AS catalogue) c0;
  IF catalogue IS DISTINCT FROM j->'catalogue' OR NOT (NOT EXISTS(SELECT 1 FROM net.http_request_queue)
 AND NOT EXISTS(SELECT 1 FROM cron.job WHERE active)
 AND NOT EXISTS(SELECT 1 FROM cron.job_run_details WHERE end_time IS NULL AND status IN('starting','running','connecting','sending'))
 AND NOT EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_webhook_events WHERE traitement_commence_le IS NOT NULL AND traite_le IS NULL)
 AND NOT EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e,a)))
    OR catalogue->'generationUrlAbsent' IS DISTINCT FROM 'true'::jsonb
    OR catalogue->'supportStagingExact' IS DISTINCT FROM 'true'::jsonb
  THEN RAISE EXCEPTION 'OPERATOR_CATALOGUE_OR_QUIESCENCE_REFUSED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.stripe_connect_test_capacities'::regclass
      AND relowner='postgres'::regrole AND relrowsecurity)
    OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.stripe_connect_test_capacities'::regclass)
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.stripe_connect_test_capacities'::regclass AND NOT tgisinternal)
    OR EXISTS(SELECT 1 FROM pg_proc WHERE oid IN(
      'private.fn_connect_test_scope(uuid,boolean)'::regprocedure,
      'private.fn_connect_test_cohorte(uuid,uuid)'::regprocedure)
      AND (proowner<>'postgres'::regrole OR NOT prosecdef))
  THEN RAISE EXCEPTION 'OPERATOR_CATALOGUE_REFUSED'; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(role_name,'private.stripe_connect_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_function_privilege(role_name,'private.fn_connect_test_scope(uuid,boolean)','EXECUTE')
      OR has_function_privilege(role_name,'private.fn_connect_test_cohorte(uuid,uuid)','EXECUTE')
    THEN RAISE EXCEPTION 'OPERATOR_CAPACITY_ACL_REFUSED'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM auth.users u WHERE u.id IN(s,e) AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
    AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
    AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=j#>>'{actorProvenance,ownerMarker}'
    AND u.email='connect-test-'||u.id::text||'@example.invalid'
    AND ((u.id=s AND u.raw_app_meta_data->>'role'='SOIGNANT') OR (u.id=e AND u.raw_app_meta_data->>'role'='ADMIN_ETABLISSEMENT'
      AND u.raw_app_meta_data->>'etablissement_id'=e::text)))<>2
    OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=s AND est_compte_test IS TRUE AND statut_compte::text='ACTIF'
      AND supprime_le IS NULL AND type_exercice::text='LIBERAL' AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE'
      AND stripe_account_id=new_capacity.destination_id AND mandat_facturation_signe IS TRUE AND mandat_facturation_version='1.4')
    OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND est_compte_test IS TRUE AND supprime_le IS NULL
      AND source_acquisition='RECETTE_CONNECT_TEST_SYNTHETIQUE' AND stripe_customer_id=new_capacity.customer_id)
    OR (SELECT count(*) FROM public.etablissements WHERE stripe_customer_id=new_capacity.customer_id)<>1
    OR (SELECT count(*) FROM public.soignants WHERE stripe_account_id=new_capacity.destination_id)<>1
    OR (SELECT count(*) FROM public.stripe_connect_onboarding WHERE soignant_id=s)<>1
    OR NOT EXISTS(SELECT 1 FROM public.stripe_connect_onboarding WHERE soignant_id=s AND stripe_account_id=new_capacity.destination_id
      AND statut='COMPLET' AND onboarding_complete AND charges_enabled AND payouts_enabled AND details_submitted)
    OR NOT EXISTS(SELECT 1 FROM public.mandats_facturation_signatures WHERE id=(j#>>'{actorProvenance,mandatId}')::uuid
      AND soignant_id=s AND version='1.4' AND revoked_at IS NULL)
    OR (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id IN(s,e)
      AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>2
    OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=a AND raw_app_meta_data->>'role'='ADMIN_PLATEFORME'
      AND raw_app_meta_data->'est_compte_test'='true'::jsonb AND raw_app_meta_data->'is_test_playwright'='true'::jsonb
      AND raw_app_meta_data->>'jolene_connect_fixture_owner'=j#>>'{fixture,ownerMarker}'
      AND email='connect-test-'||a::text||'@example.invalid')
    OR NOT EXISTS(SELECT 1 FROM public.equipe_admin WHERE id=team AND user_id=a AND actif IS FALSE)
    OR EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=a)
    OR NOT EXISTS(SELECT 1 FROM public.missions WHERE id=new_capacity.mission_id
      AND intitule='RECETTE CONNECT TEST SYNTHETIQUE '||(j#>>'{fixture,runId}') AND etablissement_id=e AND soignant_assigne_id=s
      AND statut_validation_tva='CONFIRMEE' AND nature_tva_declaree_par=a AND revue_tva_resolue_par=a AND nature_tva_confirmee_par=s)
  THEN RAISE EXCEPTION 'OPERATOR_SEPARATE_PROVENANCES_REFUSED'; END IF;
  IF EXISTS(SELECT 1 FROM public.missions WHERE (soignant_assigne_id=s OR etablissement_id=e) AND id NOT IN(hm,new_capacity.mission_id))
    OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE (soignant_id=s OR etablissement_id=e) AND id NOT IN(hh,new_capacity.facture_honoraire_id))
    OR EXISTS(SELECT 1 FROM public.factures WHERE etablissement_id=e AND id NOT IN(hf,new_capacity.facture_commission_id))
  THEN RAISE EXCEPTION 'OPERATOR_UNRECOGNIZED_ACTOR_HISTORY'; END IF;
  -- Absence d'adoption : la fixture produit des pièces, jamais un paiement.
  IF EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=new_capacity.mission_id
      OR facture_honoraire_id=new_capacity.facture_honoraire_id OR facture_id=new_capacity.facture_commission_id)
    OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key IN('FACTURE:'||new_capacity.facture_commission_id::text,'FACTURE:'||new_capacity.facture_honoraire_id::text,'MISSION:'||new_capacity.mission_id::text))
    OR EXISTS(SELECT 1 FROM public.paiements_soignant WHERE mission_id=new_capacity.mission_id)
    OR EXISTS(SELECT 1 FROM public.paiements_mission WHERE mission_id=new_capacity.mission_id)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=new_capacity.mission_id)
    OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=new_capacity.mission_id)
    OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires h JOIN public.factures f ON f.id=new_capacity.facture_commission_id
      JOIN public.missions m ON m.id=new_capacity.mission_id
      WHERE h.id=new_capacity.facture_honoraire_id AND h.statut='EMISE' AND f.statut='EMISE'
        AND h.stripe_payment_intent_id IS NULL AND f.stripe_payment_intent_id IS NULL
        AND h.date_paiement IS NULL AND f.date_paiement IS NULL AND f.stripe_invoice_id IS NULL
        AND f.stripe_hosted_url IS NULL AND f.chorus_pro_id IS NULL AND f.virement_confirme_le IS NULL
        AND h.type_document='FACTURE' AND h.nature_correction='ORIGINALE' AND f.type_document='FACTURE'
        AND h.pdf_s3_key IS NOT NULL AND h.facturx_xml_url IS NOT NULL
        AND EXISTS(SELECT 1 FROM public.factures_honoraires_documents docs WHERE docs.facture_honoraire_id=h.id
          AND docs.pdf_s3_key=h.pdf_s3_key AND docs.facturx_xml_url=h.facturx_xml_url
          AND docs.pdf_sha256 ~ '^[a-f0-9]{64}$' AND docs.xml_sha256 ~ '^[a-f0-9]{64}$')
        AND m.statut IN('EN_COURS','TERMINEE')
        AND (m.statut='TERMINEE' OR (h.est_facture_finale_mission IS FALSE AND h.periode_fin<current_date)))
  THEN RAISE EXCEPTION 'OPERATOR_HISTORY_OR_PAYABLE_REFUSED'; END IF;
  INSERT INTO private.stripe_connect_test_capacities SELECT (new_capacity).*;
  PERFORM private.fn_connect_test_scope(new_capacity.id,false);
  UPDATE private.stripe_connect_test_capacities SET enabled=true WHERE id=new_capacity.id AND enabled IS FALSE;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 THEN RAISE EXCEPTION 'OPERATOR_ACTIVATION_REFUSED'; END IF;
  PERFORM private.fn_connect_test_scope(new_capacity.id,true);
  after_n:=-- Expression uniquement ; aliases PL/pgSQL j,s,e,a,team et hc/ho/hm/hh/hf/ht/ha/hteam.
-- Valeurs sensibles Auth exclues : ni password/hash, ni recovery token, ni JWT.
-- A/T neufs sont exclus ; toute autre équipe existante est conservée.
jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
  IF after_n IS DISTINCT FROM before_n OR (SELECT count(*) FROM private.stripe_connect_test_capacities)<>2
    OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
    OR (SELECT count(*) FROM private.stripe_connect_test_capacities WHERE enabled)<>1
  THEN RAISE EXCEPTION 'OPERATOR_ALLOCATION_POSTCONDITION_REFUSED'; END IF;
  PERFORM set_config('jolene.capacity_reuse_receipt',jsonb_build_object('capacityId',new_capacity.id,'newCapacityEnabled',true,
    'historicalNPreserved',true,'capacityCount',2,'operationCount',1,'manifestSha256',manifest_sha,
    'providerInvoked',false,'transactionCommitted',false)::text,true);
END $reviewed_reuse_allocation$;$exact_allocation$;
 w_readback_template constant text:=$exact_readback$DO $reviewed_reuse_readback$
DECLARE
  j constant jsonb := {{ALLOCATION_JSON_LITERAL}}::jsonb;
  manifest_sha constant text := '{{SHA256_EXACT_MANIFEST_BYTES}}';
  d constant text := '{{FINAL_D_SHA40}}';
  s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
  e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
  a uuid:=(j#>>'{fixture,adminId}')::uuid;
  team uuid:=(j#>>'{fixture,adminTeamId}')::uuid;
  hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
  ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
  hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
  hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
  hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
  ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
  ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
  hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
  cap_id uuid:=(j#>>'{capacity,id}')::uuid;
  c private.stripe_connect_test_capacities;
  new_operation private.stripe_connect_avant_transfert;
  n_hash text;
  capacity_matches boolean;
  history_closed boolean;
  closed_terminal boolean:=false;
  known_sets boolean;
  gate_closed boolean;
  queues_quiet boolean;
  capacity_closed boolean;
BEGIN
  IF current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin')
    OR current_setting('server_version_num')::integer/10000<>17 OR auth.uid() IS NOT NULL
    OR j->'schemaVersion' IS DISTINCT FROM '2'::jsonb OR j->'ready' IS DISTINCT FROM 'true'::jsonb
    OR j->>'purpose' IS DISTINCT FROM 'CONNECT_STAGING_TEST_REUSE_CLOSED_N_V1'
    OR d !~ '^[a-f0-9]{40}$' OR manifest_sha !~ '^[a-f0-9]{64}$'
    OR cap_id IS NULL OR hc IS NULL OR cap_id=hc
    OR j#>>'{capacity,server_sha}' IS DISTINCT FROM d OR j#>>'{capacity,ui_sha}' IS DISTINCT FROM d
  THEN RAISE EXCEPTION 'OPERATOR_CONTEXT_REFUSED'; END IF;
  n_hash:=encode(extensions.digest(convert_to((-- Expression uniquement ; aliases PL/pgSQL j,s,e,a,team et hc/ho/hm/hh/hf/ht/ha/hteam.
-- Valeurs sensibles Auth exclues : ni password/hash, ni recovery token, ni JWT.
-- A/T neufs sont exclus ; toute autre équipe existante est conservée.
jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
))::text,'UTF8'),'sha256'),'hex');
  history_closed:=(SELECT count(*)=1 AND bool_and(
 h.enabled IS FALSE AND h.revoked_at IS NOT NULL AND h.revoked_at<=clock_timestamp()
 AND h.protocol='CONNECT_STAGING_TEST_V1' AND h.project_ref='mejpriaetwgtcstbgfid'
 AND h.platform_account_id='acct_1T9pt0EVhQ7cb53W' AND h.livemode IS FALSE
 AND h.transfers_allowed IS FALSE AND h.max_checkouts=1 AND h.max_refunds=1
 AND h.checkout_reserved_at IS NOT NULL AND h.refund_reserved_at IS NOT NULL AND h.claim_reserved_at IS NOT NULL
 AND h.soignant_id=s AND h.etablissement_id=e AND h.mission_id=hm
 AND h.facture_honoraire_id=hh AND h.facture_commission_id=hf
 AND h.customer_id=j#>>'{actorProvenance,customerId}' AND h.destination_id=j#>>'{actorProvenance,destinationId}'
 AND o.id=ho AND o.orientation='REFUND' AND o.refund_status='SUCCEEDED' AND o.livemode IS FALSE
 AND o.refund_id=j#>>'{historicalN,refundId}' AND o.session_id=j#>>'{historicalN,sessionId}'
 AND o.payment_intent_id=j#>>'{historicalN,paymentIntentId}' AND o.charge_id=j#>>'{historicalN,chargeId}'
 AND o.litige_id=(j#>>'{historicalN,litigeId}')::uuid
 AND o.succeeded_at IS NOT NULL AND o.review_code IS NULL AND o.owner_token IS NULL AND o.lease_until IS NULL
 AND t.id=ht AND t.statut='REMBOURSE' AND t.stripe_transfer_id IS NULL
 AND t.stripe_checkout_session_id=o.session_id AND t.stripe_payment_intent_id IS NULL AND t.stripe_charge_id IS NULL
 AND t.mission_id=hm AND t.facture_honoraire_id=hh AND t.facture_id=hf AND t.soignant_id=s AND t.etablissement_id=e
 AND old_admin.user_id=ha AND old_admin.actif IS FALSE)
 FROM private.stripe_connect_test_capacities h
 JOIN private.stripe_connect_avant_transfert o ON o.id=h.operation_id
 JOIN public.stripe_transfers t ON t.id=o.trace_id
 JOIN public.equipe_admin old_admin ON old_admin.id=hteam WHERE h.id=hc);
  SELECT * INTO c FROM private.stripe_connect_test_capacities WHERE id=cap_id;
  SELECT * INTO new_operation FROM private.stripe_connect_avant_transfert WHERE id=c.operation_id;
  capacity_matches:=c.id IS NOT NULL AND c.server_sha=d AND c.ui_sha=d AND c.source_manifest_sha256=manifest_sha
    AND (to_jsonb(c)-ARRAY['source_manifest_sha256','enabled','installed_at','livemode','max_checkouts','max_refunds',
      'transfers_allowed','operation_id','checkout_reserved_at','refund_reserved_at','claim_reserved_at','revoked_at'])
      =(to_jsonb(jsonb_populate_record(NULL::private.stripe_connect_test_capacities,j->'capacity'))
        -ARRAY['source_manifest_sha256','enabled','installed_at','livemode','max_checkouts','max_refunds',
          'transfers_allowed','operation_id','checkout_reserved_at','refund_reserved_at','claim_reserved_at','revoked_at'])
    AND c.livemode IS FALSE AND c.max_checkouts=1 AND c.max_refunds=1 AND c.transfers_allowed IS FALSE;
  known_sets:=NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE id NOT IN(hc,cap_id))
    AND NOT EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert x WHERE x.id<>ho AND (c.operation_id IS NULL OR x.id<>c.operation_id));
  IF new_operation.id IS NOT NULL AND new_operation.id<>ho THEN
    closed_terminal:=private.fn_connect_test_operation_connue(new_operation.id) AND new_operation.orientation='REFUND' AND new_operation.refund_status='SUCCEEDED'
      AND new_operation.refund_id IS NOT NULL AND new_operation.succeeded_at IS NOT NULL AND new_operation.review_code IS NULL
      AND new_operation.owner_token IS NULL AND new_operation.lease_until IS NULL AND new_operation.livemode IS FALSE
      AND new_operation.mission_id=(j#>>'{capacity,mission_id}')::uuid
      AND new_operation.facture_honoraire_id=(j#>>'{capacity,facture_honoraire_id}')::uuid
      AND new_operation.facture_commission_id=(j#>>'{capacity,facture_commission_id}')::uuid
      AND EXISTS(SELECT 1 FROM public.stripe_transfers t WHERE t.id=new_operation.trace_id AND t.statut='REMBOURSE'
        AND t.stripe_transfer_id IS NULL AND t.stripe_checkout_session_id=new_operation.session_id
        AND t.stripe_payment_intent_id=new_operation.payment_intent_id AND t.stripe_charge_id=new_operation.charge_id);
  END IF;
  SELECT count(*)=1 AND bool_and(protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
    INTO gate_closed FROM private.stripe_connect_release_gate;
  capacity_closed:=c.id IS NOT NULL AND c.enabled IS FALSE AND c.revoked_at IS NOT NULL AND c.revoked_at<=clock_timestamp();
  queues_quiet:=NOT EXISTS(SELECT 1 FROM net.http_request_queue)
 AND NOT EXISTS(SELECT 1 FROM cron.job WHERE active)
 AND NOT EXISTS(SELECT 1 FROM cron.job_run_details WHERE end_time IS NULL AND status IN('starting','running','connecting','sending'))
 AND NOT EXISTS(SELECT 1 FROM public.escrow_release_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_refunds_queue WHERE statut IN('EN_ATTENTE','EN_COURS'))
 AND NOT EXISTS(SELECT 1 FROM public.stripe_webhook_events WHERE traitement_commence_le IS NOT NULL AND traite_le IS NULL)
 AND NOT EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id IN(s,e,a));
  PERFORM set_config('jolene.capacity_reuse_readback',jsonb_build_object(
    'observedAt',clock_timestamp(),'readOnly',current_setting('transaction_read_only')='on',
    'gateClosed',COALESCE(gate_closed,false),
    'historicalNClosed',COALESCE(history_closed,false),'historicalNPinMatches',n_hash IS NOT DISTINCT FROM j#>>'{historicalN,protectedSnapshotSha256}',
    'historicalNObservedSha256',n_hash,'knownCapacityAndOperationSets',COALESCE(known_sets,false),
    'capacityCount',(SELECT count(*) FROM private.stripe_connect_test_capacities),'operationCount',(SELECT count(*) FROM private.stripe_connect_avant_transfert),
    'capacityMatchesManifest',COALESCE(capacity_matches,false),'capacity',to_jsonb(c),
    'operation',CASE WHEN new_operation.id IS NULL THEN NULL ELSE to_jsonb(new_operation)-'attempt_key'-'owner_token' END,
    'newRefundTerminalWithoutTransfer',COALESCE(closed_terminal,false),'sqlQueuesQuiescent',COALESCE(queues_quiet,false),
    'newCapacityClosed',COALESCE(capacity_closed,false),
    'sqlNormalClosureReady',COALESCE(gate_closed AND history_closed AND n_hash=j#>>'{historicalN,protectedSnapshotSha256}'
      AND known_sets AND capacity_matches AND capacity_closed AND closed_terminal AND queues_quiet
      AND (SELECT count(*) FROM private.stripe_connect_test_capacities)=2
      AND (SELECT count(*) FROM private.stripe_connect_avant_transfert)=2,false),
    'providerDrainProven',false)::text,true);
END $reviewed_reuse_readback$;$exact_readback$;
 w_revocation_template constant text:=$exact_revocation$DO $reviewed_reuse_revocation$
DECLARE
  j constant jsonb := {{ALLOCATION_JSON_LITERAL}}::jsonb;
  manifest_sha constant text := '{{SHA256_EXACT_MANIFEST_BYTES}}';
  d constant text := '{{FINAL_D_SHA40}}';
  s uuid:=(j#>>'{actorProvenance,soignantId}')::uuid;
  e uuid:=(j#>>'{actorProvenance,etablissementId}')::uuid;
  a uuid:=(j#>>'{fixture,adminId}')::uuid;
  team uuid:=(j#>>'{fixture,adminTeamId}')::uuid;
  hc uuid:=(j#>>'{historicalN,capacityId}')::uuid;
  ho uuid:=(j#>>'{historicalN,operationId}')::uuid;
  hm uuid:=(j#>>'{historicalN,missionId}')::uuid;
  hh uuid:=(j#>>'{historicalN,honorairesId}')::uuid;
  hf uuid:=(j#>>'{historicalN,commissionId}')::uuid;
  ht uuid:=(j#>>'{historicalN,traceId}')::uuid;
  ha uuid:=(j#>>'{historicalN,adminId}')::uuid;
  hteam uuid:=(j#>>'{historicalN,adminTeamId}')::uuid;
  cap_id uuid:=(j#>>'{capacity,id}')::uuid;
  before_n jsonb;
  after_n jsonb;
  before_cap private.stripe_connect_test_capacities;
  after_cap private.stripe_connect_test_capacities;
  n integer;
BEGIN
  IF current_user<>'postgres' OR session_user NOT IN('postgres','supabase_admin')
    OR current_setting('server_version_num')::integer/10000<>17 OR auth.uid() IS NOT NULL
    OR j->'schemaVersion' IS DISTINCT FROM '2'::jsonb OR j->'ready' IS DISTINCT FROM 'true'::jsonb
    OR j->>'purpose' IS DISTINCT FROM 'CONNECT_STAGING_TEST_REUSE_CLOSED_N_V1'
    OR d !~ '^[a-f0-9]{40}$' OR manifest_sha !~ '^[a-f0-9]{64}$'
    OR cap_id IS NULL OR hc IS NULL OR cap_id=hc
    OR j#>>'{capacity,server_sha}' IS DISTINCT FROM d OR j#>>'{capacity,ui_sha}' IS DISTINCT FROM d
  THEN RAISE EXCEPTION 'OPERATOR_CONTEXT_REFUSED'; END IF;
  SELECT * INTO STRICT before_cap FROM private.stripe_connect_test_capacities
    WHERE id=cap_id AND id<>hc AND project_ref='mejpriaetwgtcstbgfid' AND protocol='CONNECT_STAGING_TEST_V1'
      AND server_sha=d AND ui_sha=d AND source_manifest_sha256=manifest_sha
      AND platform_account_id='acct_1T9pt0EVhQ7cb53W' AND livemode IS FALSE FOR UPDATE;
  before_n:=-- Expression uniquement ; aliases PL/pgSQL j,s,e,a,team et hc/ho/hm/hh/hf/ht/ha/hteam.
-- Valeurs sensibles Auth exclues : ni password/hash, ni recovery token, ni JWT.
-- A/T neufs sont exclus ; toute autre équipe existante est conservée.
jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
  UPDATE private.stripe_connect_test_capacities SET enabled=false,revoked_at=COALESCE(revoked_at,clock_timestamp())
    WHERE id=before_cap.id AND id<>hc;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 THEN RAISE EXCEPTION 'OPERATOR_REVOCATION_TARGET_REFUSED'; END IF;
  SELECT * INTO STRICT after_cap FROM private.stripe_connect_test_capacities WHERE id=before_cap.id;
  IF (to_jsonb(after_cap)-ARRAY['enabled','revoked_at']) IS DISTINCT FROM (to_jsonb(before_cap)-ARRAY['enabled','revoked_at'])
    OR after_cap.enabled IS DISTINCT FROM FALSE OR after_cap.revoked_at IS NULL
    OR (before_cap.revoked_at IS NOT NULL AND after_cap.revoked_at IS DISTINCT FROM before_cap.revoked_at)
  THEN RAISE EXCEPTION 'OPERATOR_REVOCATION_POSTCONDITION_REFUSED'; END IF;
  after_n:=-- Expression uniquement ; aliases PL/pgSQL j,s,e,a,team et hc/ho/hm/hh/hf/ht/ha/hteam.
-- Valeurs sensibles Auth exclues : ni password/hash, ni recovery token, ni JWT.
-- A/T neufs sont exclus ; toute autre équipe existante est conservée.
jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
  PERFORM set_config('jolene.capacity_reuse_revocation',jsonb_build_object('capacityId',after_cap.id,
    'enabled',after_cap.enabled,'revokedAt',after_cap.revoked_at,'alreadyRevoked',before_cap.revoked_at IS NOT NULL,
    'historicalNUnchangedDuringRead',after_n IS NOT DISTINCT FROM before_n,
    'historicalNPinMatches',encode(extensions.digest(convert_to(after_n::text,'UTF8'),'sha256'),'hex') IS NOT DISTINCT FROM j#>>'{historicalN,protectedSnapshotSha256}',
    'providerDrainProven',false,'transactionCommitted',false)::text,true);
END $reviewed_reuse_revocation$;$exact_revocation$;
 w_manifest_sha text:=encode(extensions.digest(convert_to(j::text,'UTF8'),'sha256'),'hex');
 w_input jsonb;
 w_baseline jsonb;
 w_acl text;
 w_readback jsonb;
 w_receipt jsonb;
 w_revoked_at timestamptz;
 w_expected text;
 w_i integer;
BEGIN
 w_baseline:=jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
);
 IF encode(extensions.digest(convert_to(w_baseline::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM j#>>'{historicalN,protectedSnapshotSha256}'
 THEN RAISE EXCEPTION 'WITNESS_NEW_DOCUMENTS_CHANGED_N'; END IF;
 SELECT relacl::text INTO STRICT w_acl FROM pg_class WHERE oid='private.stripe_connect_test_capacities'::regclass;
 FOR w_i IN 0..7 LOOP
  w_input:=j;
  w_expected:=CASE WHEN w_i IN(1,2,3) THEN 'OPERATOR_EXACT_CLOSED_N_REQUIRED'
   WHEN w_i=4 THEN 'OPERATOR_CAPACITY_ACL_REFUSED' WHEN w_i=5 THEN 'OPERATOR_IDENTITY_OR_WINDOW_REFUSED'
   WHEN w_i IN(6,7) THEN 'CONNECT_REFUND_ORIENTATION_LOCKED' END;
  BEGIN
   IF w_i=1 THEN UPDATE private.stripe_connect_test_capacities SET revoked_at=NULL WHERE id=hc;
   ELSIF w_i=2 THEN
    INSERT INTO private.stripe_connect_test_capacities(id,protocol,project_ref,run_id,server_sha,ui_sha,source_manifest_sha256,
     expires_at,etablissement_id,soignant_id,mission_id,facture_honoraire_id,facture_commission_id,
     platform_account_id,customer_id,destination_id,soignant_cents,commission_cents,total_cents)
    VALUES(w_third,'CONNECT_STAGING_TEST_V1','mejpriaetwgtcstbgfid','f1-PG17SyntheticUnrecognized','01b135471e1e6ee7ee31439ffc248c8b8519260c','01b135471e1e6ee7ee31439ffc248c8b8519260c',
     w_manifest_sha,(j#>>'{capacity,expires_at}')::timestamptz,e,s,w_m,w_h,w_c,'acct_1T9pt0EVhQ7cb53W',
     j#>>'{actorProvenance,customerId}',j#>>'{actorProvenance,destinationId}',8000,1440,9440);
   ELSIF w_i=3 THEN w_input:=jsonb_set(j,'{historicalN,refundId}','null'::jsonb);
   ELSIF w_i=4 THEN GRANT SELECT ON private.stripe_connect_test_capacities TO authenticated;
   ELSIF w_i=5 THEN w_input:=jsonb_set(jsonb_set(j,'{windowStartsAt}',to_jsonb((j->>'windowStartsAt')::timestamptz-interval '2 hours')),
     '{capacity,expires_at}',to_jsonb((j#>>'{capacity,expires_at}')::timestamptz-interval '2 hours'));
   ELSIF w_i=6 THEN UPDATE public.stripe_transfers SET stripe_payment_intent_id=j#>>'{historicalN,paymentIntentId}' WHERE id=ht;
   ELSIF w_i=7 THEN UPDATE public.stripe_transfers SET stripe_charge_id=j#>>'{historicalN,chargeId}' WHERE id=ht;
   END IF;
   EXECUTE replace(replace(replace(w_allocation_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(w_input::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
   IF w_i<>0 THEN RAISE EXCEPTION 'WITNESS_CAPACITY_EXPECTED_REFUSAL_MISSING'; END IF;
   w_receipt:=current_setting('jolene.capacity_reuse_receipt')::jsonb;
   IF w_receipt->'newCapacityEnabled' IS DISTINCT FROM 'true'::jsonb
    OR w_receipt->'historicalNPreserved' IS DISTINCT FROM 'true'::jsonb
    OR w_receipt->>'manifestSha256' IS DISTINCT FROM w_manifest_sha
   THEN RAISE EXCEPTION 'WITNESS_ALLOCATION_RECEIPT_REQUIRED'; END IF;
   EXECUTE replace(replace(replace(w_readback_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(j::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
   w_readback:=current_setting('jolene.capacity_reuse_readback')::jsonb;
   IF w_readback->'capacityCount' IS DISTINCT FROM '2'::jsonb OR w_readback->'operationCount' IS DISTINCT FROM '1'::jsonb
    OR w_readback->'historicalNClosed' IS DISTINCT FROM 'true'::jsonb
    OR w_readback->'historicalNPinMatches' IS DISTINCT FROM 'true'::jsonb
    OR w_readback->'capacityMatchesManifest' IS DISTINCT FROM 'true'::jsonb
    OR w_readback->'knownCapacityAndOperationSets' IS DISTINCT FROM 'true'::jsonb
    OR w_readback->'sqlNormalClosureReady' IS DISTINCT FROM 'false'::jsonb
   THEN RAISE EXCEPTION 'WITNESS_ALLOCATED_READBACK_REQUIRED'; END IF;
   -- Terminal provider objects are DECLARED LOCAL FIXTURES, not checkout/refund execution.
   INSERT INTO public.stripe_payment_flow_claims(resource_key,flow,owner_token,stripe_checkout_session_id,stripe_payment_intent_id)
   VALUES('FACTURE:'||w_c::text,'CONNECT_INVOICE','connect-invoice:'||w_h::text,'cs_test_PG17SyntheticReuse','pi_PG17SyntheticReuse');
   INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,statut,gel_facture_scope,resolu_le,resolution)
   VALUES(w_litige,w_m,s,e,'SYSTEME','PG17_SYNTHETIC_ONLY refund history','FERME','AUCUN',clock_timestamp(),
    'PG17_SYNTHETIC_ONLY no provider observed');
   INSERT INTO public.stripe_transfers(id,mission_id,facture_id,facture_honoraire_id,soignant_id,etablissement_id,
    montant_total,montant_commission,montant_soignant,stripe_checkout_session_id,stripe_payment_intent_id,stripe_charge_id,statut)
   VALUES(w_trace,w_m,w_c,w_h,s,e,94.4,14.4,80,'cs_test_PG17SyntheticReuse','pi_PG17SyntheticReuse','ch_PG17SyntheticReuse','REMBOURSE');
   INSERT INTO private.stripe_connect_avant_transfert(id,attempt_key,mission_id,etablissement_id,soignant_id,
    facture_honoraire_id,facture_commission_id,customer_id,destination_id,soignant_cents,commission_cents,total_cents,
    session_id,trace_id,payment_intent_id,charge_id,livemode,orientation,litige_id,refund_id,refund_status,first_attempt_at,succeeded_at)
   VALUES(w_op,'PG17_SYNTHETIC_ONLY_REUSE',w_m,e,s,w_h,w_c,j#>>'{actorProvenance,customerId}',j#>>'{actorProvenance,destinationId}',
    8000,1440,9440,'cs_test_PG17SyntheticReuse',w_trace,'pi_PG17SyntheticReuse','ch_PG17SyntheticReuse',false,'REFUND',w_litige,
    're_PG17SyntheticReuse','SUCCEEDED',clock_timestamp(),clock_timestamp());
   UPDATE private.stripe_connect_test_capacities SET operation_id=w_op,checkout_reserved_at=clock_timestamp(),
    refund_reserved_at=clock_timestamp(),claim_reserved_at=clock_timestamp() WHERE id=w_cap;
   -- Emergency revocation must still close its exact target when N drifts. Roll this probe back.
   BEGIN
    UPDATE private.stripe_connect_test_capacities SET revoked_at=NULL WHERE id=hc;
    EXECUTE replace(replace(replace(w_revocation_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(j::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
    w_receipt:=current_setting('jolene.capacity_reuse_revocation')::jsonb;
    IF w_receipt->'historicalNPinMatches' IS DISTINCT FROM 'false'::jsonb
     OR w_receipt->'historicalNUnchangedDuringRead' IS DISTINCT FROM 'true'::jsonb
     OR w_receipt->'enabled' IS DISTINCT FROM 'false'::jsonb
    THEN RAISE EXCEPTION 'WITNESS_DRIFT_REVOCATION_REQUIRED'; END IF;
    RAISE EXCEPTION USING ERRCODE='ZX003',MESSAGE='WITNESS_DRIFT_PROBE_ROLLBACK';
   EXCEPTION WHEN SQLSTATE 'ZX003' THEN NULL;
   END;
   IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE id=w_cap AND enabled AND revoked_at IS NULL)
   THEN RAISE EXCEPTION 'WITNESS_DRIFT_PROBE_RESTORATION_REQUIRED'; END IF;
   -- A malformed request aimed at N must never revoke/adopt N.
   BEGIN
    w_input:=jsonb_set(j,'{capacity,id}',to_jsonb(hc));
    EXECUTE replace(replace(replace(w_revocation_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(w_input::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
    RAISE EXCEPTION 'WITNESS_REVOCATION_N_REFUSAL_MISSING';
   EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'OPERATOR_CONTEXT_REFUSED' THEN RAISE; END IF;
   END;
   EXECUTE replace(replace(replace(w_revocation_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(j::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
   w_receipt:=current_setting('jolene.capacity_reuse_revocation')::jsonb;
   w_revoked_at:=(w_receipt->>'revokedAt')::timestamptz;
   IF w_receipt->'alreadyRevoked' IS DISTINCT FROM 'false'::jsonb OR w_receipt->'historicalNPinMatches' IS DISTINCT FROM 'true'::jsonb
    OR w_receipt->'historicalNUnchangedDuringRead' IS DISTINCT FROM 'true'::jsonb OR w_revoked_at IS NULL
   THEN RAISE EXCEPTION 'WITNESS_FIRST_REVOCATION_REQUIRED'; END IF;
   EXECUTE replace(replace(replace(w_revocation_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(j::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
   w_receipt:=current_setting('jolene.capacity_reuse_revocation')::jsonb;
   IF w_receipt->'alreadyRevoked' IS DISTINCT FROM 'true'::jsonb
    OR (w_receipt->>'revokedAt')::timestamptz IS DISTINCT FROM w_revoked_at
   THEN RAISE EXCEPTION 'WITNESS_IDEMPOTENT_REVOCATION_REQUIRED'; END IF;
   EXECUTE replace(replace(replace(w_readback_template,'{{ALLOCATION_JSON_LITERAL}}',quote_literal(j::text)),'{{SHA256_EXACT_MANIFEST_BYTES}}',w_manifest_sha),'{{FINAL_D_SHA40}}','01b135471e1e6ee7ee31439ffc248c8b8519260c');
   w_readback:=current_setting('jolene.capacity_reuse_readback')::jsonb;
   IF w_readback->'capacityCount' IS DISTINCT FROM '2'::jsonb OR w_readback->'operationCount' IS DISTINCT FROM '2'::jsonb
    OR w_readback->'sqlNormalClosureReady' IS DISTINCT FROM 'true'::jsonb
    OR w_readback->'providerDrainProven' IS DISTINCT FROM 'false'::jsonb
    OR w_readback->'readOnly' IS DISTINCT FROM 'false'::jsonb
   THEN RAISE EXCEPTION 'WITNESS_TWO_HISTORIES_CLOSED_READBACK_REQUIRED'; END IF;
   RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='WITNESS_CAPACITY_POSITIVE_ROLLBACK';
  EXCEPTION
   WHEN SQLSTATE 'ZX001' THEN IF w_i<>0 THEN RAISE; END IF;
   WHEN SQLSTATE 'P0001' THEN IF w_i=0 OR SQLERRM IS DISTINCT FROM w_expected THEN RAISE; END IF;
  END;
  IF (jsonb_build_object(
 'authActors',(SELECT jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,
   'email_confirmed_at',u.email_confirmed_at,'deleted_at',u.deleted_at,'banned_until',u.banned_until,
   'app_metadata',u.raw_app_meta_data) ORDER BY u.id) FROM auth.users u WHERE u.id IN(s,e,ha)),
 -- Le trigger canonique de mission réécrit uniquement cette date technique ;
 -- tous les autres champs, dont les compteurs, restent dans l'empreinte exacte.
 'soignant',(SELECT to_jsonb(x)-'modifie_le' FROM public.soignants x WHERE x.id=s),
 'conversion',(SELECT jsonb_agg(to_jsonb(x)-'modifie_le' ORDER BY x.id) FROM public.suivi_conversion_3200h x WHERE x.soignant_id=s),
 'etablissement',(SELECT to_jsonb(x) FROM public.etablissements x WHERE x.id=e),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.membres_etablissement x WHERE x.etablissement_id=e OR x.user_id IN(s,e)),
 'preferences',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.utilisateur_id) FROM public.preferences_notifications x WHERE x.utilisateur_id IN(s,e)),
 'onboarding',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.soignant_id,x.stripe_account_id) FROM public.stripe_connect_onboarding x WHERE x.soignant_id=s),
 'mandats',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mandats_facturation_signatures x WHERE x.soignant_id=s),
 'adminRegistry',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.equipe_admin x WHERE x.id<>team AND x.user_id<>a),
 'capacity',(SELECT to_jsonb(x) FROM private.stripe_connect_test_capacities x WHERE x.id=hc),
 'operation',(SELECT to_jsonb(x) FROM private.stripe_connect_avant_transfert x WHERE x.id=ho),
 'mission',(SELECT to_jsonb(x) FROM public.missions x WHERE x.id=hm),
 'creneaux',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.mission_creneaux x WHERE x.mission_id=hm),
 'honoraires',(SELECT to_jsonb(x) FROM public.factures_honoraires x WHERE x.id=hh),
 'honorairesDocuments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.factures_honoraires_documents x WHERE x.facture_honoraire_id=hh),
 'commission',(SELECT to_jsonb(x) FROM public.factures x WHERE x.id=hf),
 'trace',(SELECT to_jsonb(x) FROM public.stripe_transfers x WHERE x.id=ht),
 'claims',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.resource_key) FROM public.stripe_payment_flow_claims x
   WHERE x.resource_key IN('MISSION:'||hm::text,'FACTURE:'||hf::text,'FACTURE:'||hh::text)),
 'litiges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.litiges x WHERE x.mission_id=hm),
 'paiementsSoignant',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_soignant x WHERE x.mission_id=hm),
 'paiementsMission',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_mission x WHERE x.mission_id=hm),
 'paiementsEscrow',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.paiements_escrow x WHERE x.mission_id=hm)
)) IS DISTINCT FROM w_baseline
   OR (SELECT count(*) FROM private.stripe_connect_test_capacities)<>1
   OR (SELECT count(*) FROM private.stripe_connect_avant_transfert)<>1
   OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=w_m)
   OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='FACTURE:'||w_c::text)
   OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=w_m)
   OR EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=w_h AND stripe_payment_intent_id IS NOT NULL)
   OR (SELECT relacl::text FROM pg_class WHERE oid='private.stripe_connect_test_capacities'::regclass) IS DISTINCT FROM w_acl
  THEN RAISE EXCEPTION 'WITNESS_CAPACITY_CASE_RESTORATION_REQUIRED'; END IF;
 END LOOP;
END $capacity_witness$;
SELECT jsonb_build_object('scope','PG17_SYNTHETIC_ONLY','allocationPositive',1,'allocationRefusals',5,'historicalTraceMutationRefusals',2,
 'revocationTargetRefusal',1,'revocationIdempotent',true,'revocationWhileNDrifts',true,'readbackTwoHistories',true,
 'subtransactionsRestored',true,'documentFilesExist',false,'provider',false,'readOnlyEnvelopeExecuted',false) AS capacity_witness;
ROLLBACK;

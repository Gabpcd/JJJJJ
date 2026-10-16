-- Delta de recette uniquement, hors migrations de production. Aucune capacité
-- n'est créée/activée et aucun appel fournisseur n'est effectué. L'exécuteur
-- doit d'abord vérifier l'identité Management du projet puis poser ce GUC local.
DO $v2_preflight$
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17
   OR current_setting('jolene.connect_test_project_ref',true) IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
   OR to_regclass('private.stripe_connect_test_capacities') IS NULL
   OR to_regprocedure('public.fn_connect_payout_demarrer(uuid,uuid)') IS NULL
   OR EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE enabled)
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
   OR EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE enabled OR revoked_at IS NULL)
 THEN RAISE EXCEPTION 'CONNECT_TEST_V2_INSTALLATION_REFUSED'; END IF;
END $v2_preflight$;

ALTER TABLE private.stripe_connect_test_capacities
 DROP CONSTRAINT stripe_connect_test_capacities_protocol_check,
 DROP CONSTRAINT stripe_connect_test_capacities_transfers_allowed_check,
 ADD COLUMN payouts_allowed boolean NOT NULL DEFAULT false,
 ADD COLUMN max_transfers smallint NOT NULL DEFAULT 0,
 ADD COLUMN max_payouts smallint NOT NULL DEFAULT 0,
 ADD COLUMN transfer_reserved_at timestamptz,
 ADD COLUMN transfer_id text,
 ADD COLUMN payout_reserved_at timestamptz,
 ADD COLUMN payout_id text,
 ADD CONSTRAINT connect_test_capability_profile CHECK (
   (protocol='CONNECT_STAGING_TEST_V1' AND NOT transfers_allowed AND NOT payouts_allowed AND max_transfers=0 AND max_payouts=0
     AND transfer_reserved_at IS NULL AND transfer_id IS NULL AND payout_reserved_at IS NULL AND payout_id IS NULL)
   OR (protocol='CONNECT_STAGING_STANDARD_TEST_V2' AND transfers_allowed AND payouts_allowed AND max_transfers=1 AND max_payouts=1)),
 ADD CONSTRAINT connect_test_transfer_receipt CHECK (
   (transfer_reserved_at IS NULL OR checkout_reserved_at IS NOT NULL)
   AND (transfer_id IS NULL OR (transfer_reserved_at IS NOT NULL AND transfer_id ~ '^tr_[A-Za-z0-9]+$'))),
 ADD CONSTRAINT connect_test_payout_receipt CHECK (
   (payout_reserved_at IS NULL OR transfer_id IS NOT NULL)
   AND (payout_id IS NULL OR (payout_reserved_at IS NOT NULL AND payout_id ~ '^po_[A-Za-z0-9]+$')));
CREATE UNIQUE INDEX connect_test_transfer_once ON private.stripe_connect_test_capacities(transfer_id) WHERE transfer_id IS NOT NULL;
CREATE UNIQUE INDEX connect_test_payout_once ON private.stripe_connect_test_capacities(payout_id) WHERE payout_id IS NOT NULL;

CREATE FUNCTION public.fn_connect_test_transfer_autoriser(p_operation_id uuid,p_server_sha text,p_manifest_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $v2$
DECLARE o private.stripe_connect_avant_transfert; c private.stripe_connect_test_capacities; s public.stripe_transfers;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE operation_id=o.id FOR UPDATE;
 c:=private.fn_connect_test_scope(c.id,true);
 SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=o.trace_id;
 IF c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2' OR NOT c.transfers_allowed OR c.max_transfers<>1
   OR c.server_sha IS DISTINCT FROM p_server_sha OR c.source_manifest_sha256 IS DISTINCT FROM p_manifest_sha256
   OR NOT private.fn_connect_test_operation_connue(o.id) OR o.orientation IS DISTINCT FROM 'TRANSFER'
   OR o.livemode IS DISTINCT FROM FALSE OR c.claim_reserved_at IS NULL OR c.refund_reserved_at IS NOT NULL
   OR o.refund_id IS NOT NULL OR c.transfer_id IS NOT NULL OR s.stripe_transfer_id IS NOT NULL
   OR c.transfer_reserved_at<clock_timestamp()-interval '20 hours'
 THEN RAISE EXCEPTION 'CONNECT_TEST_TRANSFER_CLOSED'; END IF;
 UPDATE private.stripe_connect_test_capacities SET transfer_reserved_at=COALESCE(transfer_reserved_at,clock_timestamp()) WHERE id=c.id;
 RETURN jsonb_build_object('operation_id',o.id,'allowed',true);
END $v2$;

CREATE FUNCTION public.fn_connect_test_payout_autoriser(p_trace_id uuid,p_transfer_id text,p_attempt integer,p_server_sha text,p_manifest_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $v2$
DECLARE o private.stripe_connect_avant_transfert; c private.stripe_connect_test_capacities; s public.stripe_transfers;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE trace_id=p_trace_id;
 o:=private.fn_connect_operation_verrouiller(o.id);
 SELECT * INTO STRICT c FROM private.stripe_connect_test_capacities WHERE operation_id=o.id FOR UPDATE;
 c:=private.fn_connect_test_scope(c.id,true);
 SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id;
 IF c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2' OR NOT c.payouts_allowed OR c.max_payouts<>1
   OR c.server_sha IS DISTINCT FROM p_server_sha OR c.source_manifest_sha256 IS DISTINCT FROM p_manifest_sha256
   OR NOT private.fn_connect_test_operation_connue(o.id) OR o.orientation IS DISTINCT FROM 'TRANSFER' OR o.livemode IS DISTINCT FROM FALSE
   OR p_attempt IS DISTINCT FROM 0 OR s.standard_payout_attempt<>0
   OR c.transfer_id IS NULL OR p_transfer_id IS DISTINCT FROM c.transfer_id OR s.stripe_transfer_id IS DISTINCT FROM c.transfer_id
   OR s.standard_payout_state IS DISTINCT FROM 'WAITING' OR s.standard_payout_account_id IS DISTINCT FROM c.destination_id
   OR s.stripe_payout_id IS NOT NULL OR c.payout_id IS NOT NULL OR c.refund_reserved_at IS NOT NULL
   OR c.payout_reserved_at<clock_timestamp()-interval '20 hours'
 THEN RAISE EXCEPTION 'CONNECT_TEST_PAYOUT_CLOSED'; END IF;
 UPDATE private.stripe_connect_test_capacities SET payout_reserved_at=COALESCE(payout_reserved_at,clock_timestamp()) WHERE id=c.id;
 RETURN jsonb_build_object('trace_id',s.id,'allowed',true);
END $v2$;

-- Le reçu est lié dans la transaction métier qui persiste l'objet fournisseur.
-- Une réponse perdue conserve la réservation et la même clé ; jamais d'adoption
-- d'un transfert/payout historique ou d'une seconde tentative bancaire.
CREATE FUNCTION private.fn_connect_test_recevoir_mouvements()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $v2$
DECLARE c private.stripe_connect_test_capacities; o private.stripe_connect_avant_transfert;
BEGIN
 SELECT * INTO o FROM private.stripe_connect_avant_transfert WHERE trace_id=NEW.id;
 IF NOT FOUND THEN RETURN NEW; END IF;
 SELECT * INTO c FROM private.stripe_connect_test_capacities WHERE operation_id=o.id FOR UPDATE;
 IF NOT FOUND OR c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2' THEN RETURN NEW; END IF;
 IF NOT private.fn_connect_test_operation_connue(o.id) OR o.livemode IS DISTINCT FROM FALSE THEN
   RAISE EXCEPTION 'CONNECT_TEST_MOVEMENT_SCOPE'; END IF;
 IF NEW.stripe_transfer_id IS NOT NULL THEN
   IF o.orientation IS DISTINCT FROM 'TRANSFER' OR c.transfer_reserved_at IS NULL
     OR c.transfer_id IS NOT NULL AND c.transfer_id IS DISTINCT FROM NEW.stripe_transfer_id
   THEN RAISE EXCEPTION 'CONNECT_TEST_TRANSFER_RECEIPT'; END IF;
   UPDATE private.stripe_connect_test_capacities SET transfer_id=NEW.stripe_transfer_id WHERE id=c.id;
 END IF;
 IF NEW.stripe_payout_id IS NOT NULL THEN
   IF c.payout_reserved_at IS NULL OR NEW.standard_payout_attempt<>0
     OR c.payout_id IS NOT NULL AND c.payout_id IS DISTINCT FROM NEW.stripe_payout_id
   THEN RAISE EXCEPTION 'CONNECT_TEST_PAYOUT_RECEIPT'; END IF;
   UPDATE private.stripe_connect_test_capacities SET payout_id=NEW.stripe_payout_id WHERE id=c.id;
 END IF;
 RETURN NEW;
END $v2$;
CREATE TRIGGER zzz_connect_test_recevoir_mouvements AFTER INSERT OR UPDATE OF stripe_transfer_id,stripe_payout_id
 ON public.stripe_transfers FOR EACH ROW EXECUTE FUNCTION private.fn_connect_test_recevoir_mouvements();

-- Fermeture/expiration ferme les nouveaux POST ; les objets déjà réservés
-- restent réconciliables. L'identité n'est jamais déduite d'un booléen client.
CREATE FUNCTION public.fn_connect_payouts_test_a_traiter(p_limit integer,p_capacity_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $v2$
DECLARE c private.stripe_connect_test_capacities;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 IF p_limit IS NULL OR p_limit<1 OR p_limit>5 THEN RAISE EXCEPTION 'CONNECT_TEST_PAYOUT_BATCH'; END IF;
 c:=private.fn_connect_test_scope(p_capacity_id,false);
 IF c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2' OR NOT private.fn_connect_test_operation_connue(c.operation_id)
   OR c.transfer_id IS NULL THEN RETURN '[]'::jsonb; END IF;
 RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id)),'[]'::jsonb)
   FROM public.stripe_transfers s JOIN private.stripe_connect_avant_transfert o ON o.trace_id=s.id
   WHERE o.id=c.operation_id AND o.orientation='TRANSFER' AND o.livemode IS FALSE
     AND s.stripe_transfer_id=c.transfer_id AND s.standard_payout_account_id=c.destination_id
     AND s.standard_payout_state IN('WAITING','SUBMITTED','FAILED')
     AND s.standard_payout_next_read_at<=clock_timestamp()
     AND (s.standard_payout_lease_until IS NULL OR s.standard_payout_lease_until<=clock_timestamp()));
END $v2$;

CREATE FUNCTION public.fn_connect_test_capacite_par_trace(p_trace_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $v2$
DECLARE c private.stripe_connect_test_capacities;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT cap.* INTO STRICT c FROM private.stripe_connect_test_capacities cap
   JOIN private.stripe_connect_avant_transfert o ON o.id=cap.operation_id WHERE o.trace_id=p_trace_id;
 c:=private.fn_connect_test_scope(c.id,false);
 IF c.protocol<>'CONNECT_STAGING_STANDARD_TEST_V2' OR NOT private.fn_connect_test_operation_connue(c.operation_id)
 THEN RAISE EXCEPTION 'CONNECT_TEST_PAYOUT_SCOPE'; END IF;
 RETURN public.fn_connect_test_capacite_lire(c.facture_honoraire_id);
END $v2$;

DO $v2_acl$
DECLARE r record;
BEGIN
 FOR r IN SELECT p.oid, p.oid::regprocedure::text signature, n.nspname, p.prosrc FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid IN (
     'public.fn_connect_test_transfer_autoriser(uuid,text,text)'::regprocedure,
     'public.fn_connect_test_payout_autoriser(uuid,text,integer,text,text)'::regprocedure,
     'public.fn_connect_payouts_test_a_traiter(integer,uuid)'::regprocedure,
     'public.fn_connect_test_capacite_par_trace(uuid)'::regprocedure,
     'private.fn_connect_test_recevoir_mouvements()'::regprocedure)
 LOOP
   EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.signature);
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',r.signature);
   IF r.nspname='public' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',r.signature); END IF;
   IF r.nspname='public' THEN
   INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
   VALUES(regexp_replace(r.signature,'^public[.]',''),'SERVICE_ONLY_REVOQUE',md5(r.prosrc),
     'Capacité staging TEST V2 exacte : un transfert et un payout, gate générale fermée, sans allocation.',clock_timestamp());
   END IF;
 END LOOP;
END $v2_acl$;

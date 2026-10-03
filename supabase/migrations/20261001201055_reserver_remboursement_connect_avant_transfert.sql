-- Candidat local, non appliqué. Aucun rattrapage ni changement des pièces.
-- Préconditions : paiement par pièce et ordre mission→trace→FH→commission.
-- Ce fichier a été créé par `supabase migration new`, CLI 2.95.4.
-- Le corps moteur est byte-identique à la fixture moteur 2cf6b7bb (hors commentaires).
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';
SET LOCAL search_path=public,pg_temp;
SET LOCAL TIME ZONE 'UTC';
DO $preflight$
DECLARE v_expected record; v_proc record;
BEGIN
  IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17
    OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role')
    OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated')
    OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    RAISE EXCEPTION 'CONNECT_MIGRATION_CONTEXT';
  END IF;
  IF to_regclass('private.stripe_connect_avant_transfert') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgname IN('trg_connect_garder_orientation','trg_connect_garder_operation')) THEN
    RAISE EXCEPTION 'CONNECT_MIGRATION_OBJECT_EXISTS';
  END IF;
  FOR v_expected IN SELECT * FROM (VALUES
    ('private.fn_connect_exiger_service()','fedd9c6a5ae20aaefe1e73c0614d129c',false,'plpgsql'),
    ('private.fn_connect_operation_verrouiller(uuid)','daad06e3d7fa97e32e73a5d306a22c1e',true,'plpgsql'),
    ('private.fn_connect_protocole_ouvert()','1ffaf109e628737771e18c0401ed6376',true,'plpgsql'),
    ('private.fn_connect_creation_autorisee(uuid)','b785cd6184643b4f5c96831320a899f4',true,'sql'),
    ('public.fn_connect_checkout_preparer(uuid,uuid,text)','a35da900f76db80473b197d798422f39',true,'plpgsql'),
    ('public.fn_connect_checkout_lier(uuid,text)','9cf5c6fa0ed65b5d8b7d3ac2a6675eaa',true,'plpgsql'),
    ('public.fn_connect_checkout_verifier(uuid,text)','f8bc60ffc9ad54ea69ce39b8f65cf672',true,'plpgsql'),
    ('public.fn_connect_avant_transfert_lire(text)','0402bda7bf0e9810aee422e603792140',true,'plpgsql'),
    ('public.fn_connect_avant_transfert_arbitrer(uuid,uuid,jsonb)','50e0e5e382878ec1e0013ceb4b87a843',true,'plpgsql'),
    ('public.fn_connect_remboursement_prendre(uuid,uuid)','8d406e7b86f733c420bc05fa7bc7971a',true,'plpgsql'),
    ('public.fn_connect_remboursement_demarrer(uuid,uuid)','4c43f80bab2ab55c2b2e7d0dc8cf4af2',true,'plpgsql'),
    ('public.fn_connect_remboursement_constater(uuid,uuid,jsonb)','f0650a8fe412cf693426f9a38ef68ab6',true,'plpgsql'),
    ('public.fn_connect_remboursements_a_traiter(integer)','c53e9f88b82b21dfe895c1e1e5611bbd',true,'plpgsql'),
    ('private.fn_connect_garder_orientation_trace()','81958dbe4016033ed3998c955fa6a258',true,'plpgsql'),
    ('private.fn_connect_garder_operation()','89c1b9a70d5f0387e21d80967271a8da',true,'plpgsql')) AS x(signature,corps,secdef,langage) LOOP
    IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname=split_part(v_expected.signature,'.',1)
        AND p.proname=split_part(split_part(v_expected.signature,'.',2),'(',1))
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory
        WHERE signature IN(v_expected.signature,replace(v_expected.signature,'public.',''))) THEN
      RAISE EXCEPTION 'CONNECT_MIGRATION_OVERLOAD_OR_INVENTORY (%)',v_expected.signature;
    END IF;
  END LOOP;
  FOR v_expected IN SELECT * FROM (VALUES
    ('public.fn_ecrire_audit_safe(uuid,text,text,text,uuid,text,jsonb,inet,text)','04cc44127e325b434445113e88ce38b7','1b1aeab3524ed41df492031b5eac9613','search_path=public','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'v',false),
    ('public.fn_protect_stripe_transfer()','89b4cf2f336aa6a4c07ef6fc26abfb8d','39b6e0f0439e4efc59ac4c6bfe0d1e08','search_path=public','{postgres=X/postgres,service_role=X/postgres}',true,'v',false),
    ('public.fn_stripe_payment_flow_claim(text,text,uuid,uuid)','4506013ff5a5c0df5761523a221d8977','82f09bcf1334fb9041ae9a1628e4cd42','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}',true,'v',false),
    ('public.fn_stripe_refunds_reels_a_traiter(timestamp with time zone,integer)','168f098df16a5cf2f4687227e02b5afe','233e9f651775a2ad05fa9ac91f970e86','search_path=""','{postgres=X/postgres,service_role=X/postgres}',false,'s',false),
    ('public.fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','c7b1356e671f49a19bf98cedf75f8249','9a50b2ad4d79d26e7244bb8e22cf0b85','search_path=public','{postgres=X/postgres,service_role=X/postgres}',true,'v',false),
    ('private.fn_garder_paiement_liberal_facture()','091e28306f35cab7cb16fe202ca890a0',NULL,'search_path=pg_catalog, public','{postgres=X/postgres}',true,'v',false),
    ('private.fn_garder_reservation_connect()','a464fef0ece749bfcf5fe52761552bb2',NULL,'search_path=pg_catalog, public','{postgres=X/postgres}',true,'v',false),
    ('public.fn_propage_stripe_payment_intent_trg()','b055f559832a40ceddf3dc326b7cce29','970a7e8cfaaba4f79930aaa06992bd73','search_path=public, extensions','{postgres=X/postgres,service_role=X/postgres}',true,'v',true),
    ('public.fn_preparer_facture_commission_periode(uuid)','57a21cb459d2a7eaedddf3d560f37425','59bfad8aa55638236e6aae5d4bc674c9','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}',true,'v',true),
    ('public.fn_preparer_commission_complement_honoraires(uuid)','2e285170947e879524316f0252347313','b61aefda7ac13ff6006a588acaacdce9','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}',true,'v',true),
    ('public.fn_preparer_commission_remplacement_honoraires(uuid)','3a15006bb68a7a44801e429aa1fb3e58','c736c66d76001b64ba425484f77c6ea2','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}',true,'v',true),
    ('public.fn_preparer_avoir_commission_honoraires(uuid)','972bff7ed6b0beedc598d2cb815f2130','4afd9dca4fea1d23414a797342cd1180','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}',true,'v',true),
    ('public.fn_mirror_teleportation_alerte_systeme()','f647d11f9ae7c512fe712934dd2a746f','5473b164e3030bd74b5c4849d3099b4a','search_path=pg_catalog, public','{postgres=X/postgres,service_role=X/postgres}',true,'v',false),
    ('public.fn_stripe_connect_rapprocher_local(uuid,uuid,uuid,uuid,uuid,text,text,text,text,integer,integer,integer,timestamp with time zone)','3be6ed641d4275e6232d475043fa6304','7f6e56bcf109b4f6901da91fb5dc9d7c','search_path=public, pg_temp','{postgres=X/postgres,service_role=X/postgres}',true,'v',true))
    AS x(signature,corps,definition,configuration,acl,secdef,volatilite,inventaire) LOOP
    SELECT * INTO v_proc FROM pg_proc WHERE oid=to_regprocedure(v_expected.signature);
    IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
      OR (v_expected.definition IS NOT NULL AND md5(pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM v_expected.definition)
      OR pg_get_userbyid(v_proc.proowner)<>'postgres'
      OR v_proc.prosecdef IS DISTINCT FROM v_expected.secdef
      OR v_proc.provolatile::text IS DISTINCT FROM v_expected.volatilite
      OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_expected.configuration]::text[]
      OR v_proc.proacl IS DISTINCT FROM v_expected.acl::aclitem[] THEN
      RAISE EXCEPTION 'CONNECT_MIGRATION_DEPENDENCY (%)',v_expected.signature;
    END IF;
    IF v_expected.inventaire AND (
      (SELECT count(*) FROM private.security_definer_inventory
        WHERE signature=replace(v_expected.signature,'public.','')
          AND categorie='SERVICE_ONLY_REVOQUE' AND definition_md5=v_expected.corps)<>1
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=v_expected.signature)) THEN
      RAISE EXCEPTION 'CONNECT_MIGRATION_DEPENDENCY_INVENTORY (%)',v_expected.signature;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.stripe_transfers'::regclass AND NOT tgisinternal)<>2
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.stripe_transfers'::regclass
      AND NOT tgisinternal AND tgenabled='O'
      AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_propage_stripe_payment_intent AFTER INSERT OR UPDATE OF stripe_payment_intent_id, mission_id ON public.stripe_transfers FOR EACH ROW EXECUTE FUNCTION fn_propage_stripe_payment_intent_trg()')
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.stripe_transfers'::regclass
      AND NOT tgisinternal AND tgenabled='O'
      AND pg_get_triggerdef(oid)='CREATE TRIGGER trg_protect_stripe_transfer BEFORE UPDATE ON public.stripe_transfers FOR EACH ROW EXECUTE FUNCTION fn_protect_stripe_transfer()')
    OR EXISTS(SELECT 1 FROM pg_rewrite WHERE ev_class='public.stripe_transfers'::regclass AND rulename<>'_RETURN') THEN
    RAISE EXCEPTION 'CONNECT_MIGRATION_TRACE_TRIGGERS';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.stripe_payment_flow_claims'::regclass
    AND tgenabled='O' AND NOT tgisinternal AND pg_get_triggerdef(oid)=
      'CREATE TRIGGER trg_reservation_connect_paiement BEFORE INSERT ON public.stripe_payment_flow_claims FOR EACH ROW EXECUTE FUNCTION private.fn_garder_reservation_connect()')
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.paiements_soignant'::regclass
    AND tgenabled='O' AND NOT tgisinternal AND pg_get_triggerdef(oid)=
      'CREATE TRIGGER trg_paiement_liberal_facture BEFORE INSERT OR UPDATE ON public.paiements_soignant FOR EACH ROW EXECUTE FUNCTION private.fn_garder_paiement_liberal_facture()') THEN
    RAISE EXCEPTION 'CONNECT_MIGRATION_PAYMENT_GUARDS';
  END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.journaux_audit'::regclass AND NOT tgisinternal AND (tgtype&4)<>0)<>1
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.journaux_audit'::regclass
      AND NOT tgisinternal AND tgenabled='O' AND pg_get_triggerdef(oid)=
      'CREATE TRIGGER trg_mirror_teleportation_alerte_systeme AFTER INSERT ON public.journaux_audit FOR EACH ROW EXECUTE FUNCTION fn_mirror_teleportation_alerte_systeme()')
    OR EXISTS(SELECT 1 FROM pg_rewrite WHERE ev_class='public.journaux_audit'::regclass AND rulename<>'_RETURN') THEN
    RAISE EXCEPTION 'CONNECT_MIGRATION_AUDIT_INSERT';
  END IF;
END;
$preflight$;

CREATE TABLE private.stripe_connect_avant_transfert (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 attempt_key text NOT NULL UNIQUE CHECK(length(attempt_key) BETWEEN 1 AND 240),
 mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE RESTRICT,
 etablissement_id uuid NOT NULL REFERENCES public.etablissements(id) ON DELETE RESTRICT,
 soignant_id uuid NOT NULL REFERENCES public.soignants(id) ON DELETE RESTRICT,
 facture_honoraire_id uuid NOT NULL REFERENCES public.factures_honoraires(id) ON DELETE RESTRICT,
 facture_commission_id uuid NOT NULL REFERENCES public.factures(id) ON DELETE RESTRICT,
 customer_id text NOT NULL CHECK(customer_id ~ '^cus_[A-Za-z0-9_]+$'),
 destination_id text NOT NULL CHECK(destination_id ~ '^acct_[A-Za-z0-9_]+$'),
 soignant_cents bigint NOT NULL CHECK(soignant_cents>0),
 commission_cents bigint NOT NULL CHECK(commission_cents>0),
 total_cents bigint NOT NULL CHECK(total_cents=soignant_cents+commission_cents AND total_cents<=9007199254740991),
 session_id text UNIQUE CHECK(session_id ~ '^cs_[A-Za-z0-9_]+$'),
 trace_id uuid REFERENCES public.stripe_transfers(id) ON DELETE RESTRICT,
 payment_intent_id text UNIQUE CHECK(payment_intent_id ~ '^pi_[A-Za-z0-9_]+$'),
 charge_id text UNIQUE CHECK(charge_id ~ '^ch_[A-Za-z0-9_]+$'),
 livemode boolean,
 orientation text CHECK(orientation IN('TRANSFER','REFUND')),
 litige_id uuid REFERENCES public.litiges(id) ON DELETE RESTRICT,
 refund_id text UNIQUE CHECK(refund_id ~ '^re_[A-Za-z0-9_]+$'),
 refund_status text NOT NULL DEFAULT 'READY' CHECK(refund_status IN('READY','PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED','REVIEW')),
 first_attempt_at timestamptz,
 owner_token uuid,
 lease_until timestamptz,
 next_read_at timestamptz NOT NULL DEFAULT now(),
 review_code text CHECK(review_code IN('CREATE_WINDOW_CLOSED','REFUND_FAILED','REFUND_CANCELED','REFUND_RETURNED_AFTER_SUCCESS','REFUND_REQUIRES_ACTION_AFTER_SUCCESS','REFUND_STATUS_CONTRADICTORY')),
 failure_balance_transaction_id text UNIQUE CHECK(failure_balance_transaction_id ~ '^txn_[A-Za-z0-9_]+$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 succeeded_at timestamptz,
 CHECK((orientation IS NULL AND payment_intent_id IS NULL AND charge_id IS NULL AND livemode IS NULL AND litige_id IS NULL)
    OR (orientation IS NOT NULL AND session_id IS NOT NULL AND trace_id IS NOT NULL AND payment_intent_id IS NOT NULL
        AND charge_id IS NOT NULL AND livemode IS NOT NULL AND ((orientation='REFUND' AND litige_id IS NOT NULL) OR (orientation='TRANSFER' AND litige_id IS NULL)))),
 CHECK(orientation IS NOT DISTINCT FROM 'REFUND' OR (refund_id IS NULL AND refund_status='READY' AND first_attempt_at IS NULL)),
 CHECK((owner_token IS NULL)=(lease_until IS NULL)),
 CHECK(refund_status='READY' OR refund_id IS NOT NULL OR (refund_status='REVIEW' AND review_code='CREATE_WINDOW_CLOSED'))
);
ALTER TABLE private.stripe_connect_avant_transfert ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.stripe_connect_avant_transfert FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX stripe_connect_avant_transfert_poll ON private.stripe_connect_avant_transfert(next_read_at,created_at)
 WHERE orientation='REFUND' AND refund_status IN('READY','PENDING','REQUIRES_ACTION','SUCCEEDED');

CREATE FUNCTION private.fn_connect_exiger_service() RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $f$
BEGIN
 IF COALESCE(auth.jwt()->>'role','')<>'service_role' THEN RAISE EXCEPTION 'CONNECT_SERVICE_REQUIRED' USING ERRCODE='42501'; END IF;
END;$f$;

-- Helper privé : mêmes verrous pour arbitre, reprise et finalisation. Ne jamais
-- appeler ce helper depuis un trigger de stripe_transfers (ST est déjà verrouillée).
CREATE FUNCTION private.fn_connect_operation_verrouiller(p_id uuid)
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
   OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=o.soignant_id AND est_compte_test IS FALSE)
   OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=o.etablissement_id AND est_compte_test IS FALSE)
   OR EXISTS(SELECT 1 FROM public.soignants WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)
   OR EXISTS(SELECT 1 FROM public.etablissements WHERE id IN(o.etablissement_id,o.soignant_id) AND est_compte_test IS DISTINCT FROM FALSE)
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

-- Le moteur reste fermé tant que la barrière de livraison n'est pas installée
-- et ouverte par une opération distincte revue. Aucun fallback sur erreur SQL.
CREATE FUNCTION private.fn_connect_protocole_ouvert()
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 IF to_regclass('private.stripe_connect_release_gate') IS NULL THEN RETURN FALSE; END IF;
 RETURN EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
   WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE);
END;$f$;

-- Les identités financières persistées restent lisibles après anonymisation.
-- Cette garde opérationnelle ne vaut que pour admission/arbitrage/nouveau POST.
CREATE FUNCTION private.fn_connect_creation_autorisee(p_id uuid)
 RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS $f$
 SELECT EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert o
   JOIN public.soignants s ON s.id=o.soignant_id JOIN public.etablissements e ON e.id=o.etablissement_id
   JOIN public.stripe_connect_onboarding b ON b.soignant_id=o.soignant_id
   WHERE o.id=p_id AND private.fn_connect_protocole_ouvert() AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE
     AND s.supprime_le IS NULL AND e.supprime_le IS NULL AND s.statut_compte::text='ACTIF'
     AND e.stripe_customer_id=o.customer_id AND b.statut='COMPLET' AND b.stripe_account_id=o.destination_id);
$f$;

CREATE FUNCTION public.fn_connect_checkout_preparer(p_facture_honoraire_id uuid,p_facture_commission_id uuid,p_cle_tentative text)
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
 -- Une insertion neuve a trace_id NULL et n'acquiert donc aucune ST tardive.
 IF o.trace_id IS NOT NULL THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONCURRENT_LINK'; END IF;
 o:=private.fn_connect_operation_verrouiller(o.id);
 END IF;
 IF NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
 RETURN jsonb_build_object('operation_id',o.id,'facture_honoraire_id',h.id,'facture_commission_id',c.id);
END;$f$;

CREATE FUNCTION public.fn_connect_checkout_lier(p_operation_id uuid,p_session_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; s public.stripe_transfers;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_operation_id;
 PERFORM 1 FROM public.missions WHERE id=o.mission_id FOR UPDATE;
 SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE id=p_operation_id;
 IF o.session_id IS NOT NULL AND o.session_id<>p_session_id THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONFLICT'; END IF;
 SELECT * INTO STRICT s FROM public.stripe_transfers WHERE stripe_checkout_session_id=p_session_id FOR UPDATE;
 o:=private.fn_connect_operation_verrouiller(o.id);
 IF o.session_id IS NOT NULL AND o.session_id<>p_session_id THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONFLICT'; END IF;
 IF s.mission_id IS DISTINCT FROM o.mission_id OR s.facture_honoraire_id IS DISTINCT FROM o.facture_honoraire_id
   OR s.facture_id IS DISTINCT FROM o.facture_commission_id OR s.stripe_transfer_id IS NOT NULL OR s.statut IS DISTINCT FROM 'EN_ATTENTE'
   OR NOT EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key='FACTURE:'||o.facture_commission_id::text
     AND flow='CONNECT_INVOICE' AND stripe_checkout_session_id=p_session_id)
 THEN RAISE EXCEPTION 'CONNECT_ADMISSION_TRACE'; END IF;
 IF NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
 UPDATE private.stripe_connect_avant_transfert SET session_id=p_session_id,trace_id=s.id WHERE id=o.id;
 -- ST exacte déjà verrouillée avant FH/C ; pas d'acquisition tardive d'une autre trace.
 o:=private.fn_connect_operation_verrouiller(o.id);
 RETURN jsonb_build_object('bound',true,'operation_id',o.id,'session_id',p_session_id);
END;$f$;

CREATE FUNCTION public.fn_connect_checkout_verifier(p_operation_id uuid,p_session_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 IF o.session_id IS DISTINCT FROM p_session_id OR o.orientation IS NOT NULL OR NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ADMISSION_CONFLICT'; END IF;
 RETURN jsonb_build_object('admitted',true,'operation_id',o.id,'session_id',p_session_id);
END;$f$;

CREATE FUNCTION public.fn_connect_avant_transfert_lire(p_session_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert;
BEGIN
 PERFORM private.fn_connect_exiger_service();
 SELECT * INTO o FROM private.stripe_connect_avant_transfert WHERE session_id=p_session_id;
 IF NOT FOUND OR o.orientation IS NULL THEN RETURN NULL; END IF;
 RETURN to_jsonb(o)-'attempt_key'-'owner_token'-'lease_until';
END;$f$;

CREATE FUNCTION public.fn_connect_avant_transfert_arbitrer(p_operation_id uuid,p_trace_id uuid,p_source jsonb)
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
 UPDATE private.stripe_connect_avant_transfert SET payment_intent_id=p_source->>'payment_intent_id',charge_id=p_source->>'charge_id',
   livemode=(p_source->>'livemode')::boolean,orientation=CASE WHEN l IS NULL THEN 'TRANSFER' ELSE 'REFUND' END,litige_id=l
 WHERE id=o.id RETURNING * INTO o;
 IF o.orientation='REFUND' THEN
   UPDATE public.stripe_transfers SET statut='EN_ATTENTE',erreur='Remboursement avant transfert en cours de rapprochement'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL;
 END IF;
 RETURN to_jsonb(o)-'attempt_key'-'owner_token'-'lease_until';
END;$f$;

CREATE FUNCTION public.fn_connect_remboursement_prendre(p_operation_id uuid,p_owner_token uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 IF o.orientation IS DISTINCT FROM 'REFUND' OR p_owner_token IS NULL THEN RAISE EXCEPTION 'CONNECT_REFUND_ORIENTATION'; END IF;
 IF o.lease_until>clock_timestamp() AND o.owner_token IS DISTINCT FROM p_owner_token THEN
   RETURN jsonb_build_object('acquired',false,'owner_token',p_owner_token);
 END IF;
 UPDATE private.stripe_connect_avant_transfert SET owner_token=p_owner_token,lease_until=clock_timestamp()+interval '15 minutes'
 WHERE id=o.id RETURNING * INTO o;
 RETURN jsonb_build_object('acquired',true,'owner_token',p_owner_token,'can_create',private.fn_connect_creation_autorisee(o.id),'operation',to_jsonb(o)-'attempt_key'-'owner_token'-'lease_until');
END;$f$;

CREATE FUNCTION public.fn_connect_remboursement_demarrer(p_operation_id uuid,p_owner_token uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; allowed boolean; a jsonb;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 IF o.orientation IS DISTINCT FROM 'REFUND' OR p_owner_token IS NULL OR o.owner_token IS DISTINCT FROM p_owner_token OR o.lease_until IS NULL OR o.lease_until<=clock_timestamp()
   OR o.refund_id IS NOT NULL OR o.refund_status<>'READY' THEN RAISE EXCEPTION 'CONNECT_REFUND_LEASE'; END IF;
 IF NOT private.fn_connect_creation_autorisee(o.id) THEN RAISE EXCEPTION 'CONNECT_ACCOUNT_NOT_OPERATIONAL'; END IF;
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

CREATE FUNCTION public.fn_connect_remboursement_constater(p_operation_id uuid,p_owner_token uuid,p_refund jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE o private.stripe_connect_avant_transfert; st text; a jsonb; touched integer; incident text; retour text;
BEGIN
 o:=private.fn_connect_operation_verrouiller(p_operation_id);
 st:=upper(p_refund->>'status');
 IF o.orientation IS DISTINCT FROM 'REFUND' OR o.first_attempt_at IS NULL OR p_owner_token IS NULL OR o.owner_token IS DISTINCT FROM p_owner_token
   OR o.lease_until IS NULL OR o.lease_until<=clock_timestamp() OR COALESCE(p_refund->>'id','')!~'^re_[A-Za-z0-9_]+$'
   OR (o.refund_id IS NOT NULL AND o.refund_id IS DISTINCT FROM p_refund->>'id')
   OR p_refund->>'payment_intent_id' IS DISTINCT FROM o.payment_intent_id OR p_refund->>'charge_id' IS DISTINCT FROM o.charge_id
   OR p_refund->>'currency' IS DISTINCT FROM 'eur' OR (p_refund->>'amount')::bigint IS DISTINCT FROM o.total_cents
   OR st IS NULL OR st NOT IN('PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED')
 THEN RAISE EXCEPTION 'CONNECT_REFUND_RECEIPT'; END IF;
 IF o.refund_status='REVIEW' THEN
   UPDATE private.stripe_connect_avant_transfert SET owner_token=NULL,lease_until=NULL WHERE id=o.id;
   RETURN jsonb_build_object('operation_id',o.id,'refund_id',o.refund_id,'status','REVIEW','review_code',o.review_code);
 END IF;
 IF o.refund_status IN('FAILED','CANCELED') AND st IS DISTINCT FROM o.refund_status THEN
   incident:='REFUND_STATUS_CONTRADICTORY';
   st:='REVIEW';
 END IF;
 IF o.refund_status='SUCCEEDED' AND st='PENDING' THEN st:='SUCCEEDED'; END IF;
 IF o.refund_status='SUCCEEDED' AND st IN('FAILED','CANCELED','REQUIRES_ACTION') THEN
   retour:=p_refund->>'failure_balance_transaction_id';
   IF st IN('FAILED','CANCELED') AND COALESCE(retour,'')!~'^txn_[A-Za-z0-9_]+$' THEN RAISE EXCEPTION 'CONNECT_REFUND_RETURN_NOT_PROVEN'; END IF;
   incident:=CASE WHEN st='REQUIRES_ACTION' THEN 'REFUND_REQUIRES_ACTION_AFTER_SUCCESS' ELSE 'REFUND_RETURNED_AFTER_SUCCESS' END;
   st:='REVIEW';
 END IF;
 UPDATE private.stripe_connect_avant_transfert SET refund_id=p_refund->>'id',refund_status=st WHERE id=o.id;
 IF st='SUCCEEDED' AND o.refund_status<>'SUCCEEDED' THEN
   UPDATE public.stripe_transfers SET statut='REMBOURSE',erreur='Paiement remboursé avant transfert après ouverture d’un litige'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL AND statut IN('EN_ATTENTE','ECHOUE','CHARGE_REUSSI');
   GET DIAGNOSTICS touched=ROW_COUNT;
   IF touched<>1 THEN RAISE EXCEPTION 'CONNECT_REFUND_TRACE_NOT_FINALIZED'; END IF;
   a:=public.fn_ecrire_audit_safe(o.etablissement_id,'SYSTEME','ADMIN_ACTION','factures_honoraires',o.facture_honoraire_id,NULL,
     jsonb_build_object('evenement','CONNECT_REMBOURSE_AVANT_TRANSFERT_POUR_LITIGE','operation_id',o.id,'litige_id',o.litige_id,
       'stripe_session_id',o.session_id,'stripe_payment_intent_id',o.payment_intent_id,'stripe_refund_id',p_refund->>'id'),NULL,'connect-pretransfer');
   IF (a->>'success')::boolean IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'CONNECT_REFUND_AUDIT_FAILED'; END IF;
 END IF;
 IF st IN('FAILED','CANCELED','REVIEW') AND o.refund_status IS DISTINCT FROM st THEN
   UPDATE public.stripe_transfers SET statut='ECHOUE',erreur='Le remboursement requiert un rapprochement ; aucun nouveau transfert autorisé'
   WHERE id=o.trace_id AND stripe_checkout_session_id=o.session_id AND stripe_transfer_id IS NULL AND statut IN('EN_ATTENTE','CHARGE_REUSSI','REMBOURSE','ECHOUE');
   GET DIAGNOSTICS touched=ROW_COUNT;
   IF touched<>1 THEN RAISE EXCEPTION 'CONNECT_REFUND_FAILURE_NOT_RECORDED'; END IF;
   a:=public.fn_ecrire_audit_safe(o.etablissement_id,'SYSTEME','ADMIN_ACTION','factures_honoraires',o.facture_honoraire_id,NULL,
     jsonb_build_object('evenement','CONNECT_REMBOURSEMENT_INCIDENT','operation_id',o.id,'stripe_refund_id',p_refund->>'id',
       'statut_courant',p_refund->>'status','incident',COALESCE(incident,'REFUND_'||st),'failure_balance_transaction_id',retour),NULL,'connect-pretransfer');
   IF (a->>'success')::boolean IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'CONNECT_REFUND_AUDIT_FAILED'; END IF;
 END IF;
 UPDATE private.stripe_connect_avant_transfert SET refund_id=p_refund->>'id',refund_status=st,
   succeeded_at=CASE WHEN st='SUCCEEDED' THEN COALESCE(succeeded_at,clock_timestamp()) ELSE succeeded_at END,
   failure_balance_transaction_id=COALESCE(failure_balance_transaction_id,retour),
   review_code=CASE WHEN incident IS NOT NULL THEN incident WHEN st='FAILED' THEN 'REFUND_FAILED' WHEN st='CANCELED' THEN 'REFUND_CANCELED' ELSE review_code END,
   owner_token=NULL,lease_until=NULL,next_read_at=clock_timestamp()+CASE WHEN st='SUCCEEDED' THEN interval '1 hour' ELSE interval '5 minutes' END
 WHERE id=o.id;
 RETURN jsonb_build_object('operation_id',o.id,'refund_id',p_refund->>'id','status',st,'review_code',COALESCE(incident,o.review_code));
END;$f$;

CREATE FUNCTION public.fn_connect_remboursements_a_traiter(p_limit integer DEFAULT 2)
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
     AND s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE
   ORDER BY o.next_read_at,o.created_at,o.id LIMIT p_limit
 ) x;
 RETURN r;
END;$f$;

-- Lire l'orientation sous verrou ST déjà tenu ; aucun autre verrou ici.
CREATE FUNCTION private.fn_connect_garder_orientation_trace() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 IF EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert o WHERE o.trace_id=OLD.id AND o.session_id=OLD.stripe_checkout_session_id
   AND o.orientation='REFUND' AND (NEW.stripe_checkout_session_id IS DISTINCT FROM OLD.stripe_checkout_session_id
     OR NEW.stripe_transfer_id IS NOT NULL OR NEW.statut IN('TRANSFERE','PAYE','CHARGE_REUSSI')
     OR (NEW.statut='REMBOURSE' AND o.refund_status<>'SUCCEEDED')
     OR ROW(NEW.facture_honoraire_id,NEW.facture_id,NEW.mission_id,NEW.soignant_id,NEW.etablissement_id,
       NEW.montant_soignant,NEW.montant_commission,NEW.montant_total,NEW.stripe_payment_intent_id,NEW.stripe_charge_id)
       IS DISTINCT FROM ROW(OLD.facture_honoraire_id,OLD.facture_id,OLD.mission_id,OLD.soignant_id,OLD.etablissement_id,
       OLD.montant_soignant,OLD.montant_commission,OLD.montant_total,OLD.stripe_payment_intent_id,OLD.stripe_charge_id)))
 THEN RAISE EXCEPTION 'CONNECT_REFUND_ORIENTATION_LOCKED'; END IF;
 RETURN NEW;
END;$f$;
CREATE TRIGGER trg_connect_garder_orientation BEFORE UPDATE ON public.stripe_transfers
 FOR EACH ROW EXECUTE FUNCTION private.fn_connect_garder_orientation_trace();

CREATE FUNCTION private.fn_connect_garder_operation() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
BEGIN
 IF (OLD.session_id IS NOT NULL AND NEW.session_id IS DISTINCT FROM OLD.session_id)
   OR (OLD.trace_id IS NOT NULL AND NEW.trace_id IS DISTINCT FROM OLD.trace_id)
   OR (OLD.first_attempt_at IS NOT NULL AND NEW.first_attempt_at IS DISTINCT FROM OLD.first_attempt_at)
   OR (OLD.refund_id IS NOT NULL AND NEW.refund_id IS DISTINCT FROM OLD.refund_id)
   OR (OLD.failure_balance_transaction_id IS NOT NULL AND NEW.failure_balance_transaction_id IS DISTINCT FROM OLD.failure_balance_transaction_id)
   OR (OLD.orientation IS NOT NULL AND (to_jsonb(NEW)-ARRAY['refund_id','refund_status','first_attempt_at','owner_token','lease_until','next_read_at','review_code','failure_balance_transaction_id','succeeded_at'])
     IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['refund_id','refund_status','first_attempt_at','owner_token','lease_until','next_read_at','review_code','failure_balance_transaction_id','succeeded_at']))
 THEN RAISE EXCEPTION 'CONNECT_OPERATION_IMMUTABLE'; END IF;
 RETURN NEW;
END;$f$;
CREATE TRIGGER trg_connect_garder_operation BEFORE UPDATE ON private.stripe_connect_avant_transfert
 FOR EACH ROW EXECUTE FUNCTION private.fn_connect_garder_operation();

-- ACL/inventaire à fermer après préflight complet. Aucun droit client implicite.
DO $acl$
DECLARE v_proc record;
BEGIN
 FOR v_proc IN SELECT p.oid,p.oid::regprocedure::text AS signature,n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='private' AND p.proname IN('fn_connect_exiger_service','fn_connect_protocole_ouvert','fn_connect_creation_autorisee','fn_connect_operation_verrouiller','fn_connect_garder_orientation_trace','fn_connect_garder_operation'))
 OR (n.nspname='public' AND p.proname IN('fn_connect_checkout_preparer','fn_connect_checkout_lier','fn_connect_checkout_verifier','fn_connect_avant_transfert_lire',
   'fn_connect_avant_transfert_arbitrer','fn_connect_remboursement_prendre','fn_connect_remboursement_demarrer','fn_connect_remboursement_constater','fn_connect_remboursements_a_traiter')) LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',v_proc.signature);
   IF v_proc.nspname='public' THEN
     EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',v_proc.signature);
     INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
     SELECT v_proc.signature,'SERVICE_ONLY_REVOQUE',md5(prosrc),'Arbitrage et remboursement du seul Checkout canonique admis avant transfert ; aucune reprise historique.',now()
     FROM pg_proc WHERE oid=v_proc.oid;
   END IF;
 END LOOP;
END;$acl$;

DO $postflight$
DECLARE v_expected record; v_proc record;
BEGIN
  FOR v_expected IN SELECT * FROM (VALUES
    ('private.fn_connect_exiger_service()','fedd9c6a5ae20aaefe1e73c0614d129c',false,'plpgsql'),
    ('private.fn_connect_operation_verrouiller(uuid)','daad06e3d7fa97e32e73a5d306a22c1e',true,'plpgsql'),
    ('private.fn_connect_protocole_ouvert()','1ffaf109e628737771e18c0401ed6376',true,'plpgsql'),
    ('private.fn_connect_creation_autorisee(uuid)','b785cd6184643b4f5c96831320a899f4',true,'sql'),
    ('public.fn_connect_checkout_preparer(uuid,uuid,text)','a35da900f76db80473b197d798422f39',true,'plpgsql'),
    ('public.fn_connect_checkout_lier(uuid,text)','9cf5c6fa0ed65b5d8b7d3ac2a6675eaa',true,'plpgsql'),
    ('public.fn_connect_checkout_verifier(uuid,text)','f8bc60ffc9ad54ea69ce39b8f65cf672',true,'plpgsql'),
    ('public.fn_connect_avant_transfert_lire(text)','0402bda7bf0e9810aee422e603792140',true,'plpgsql'),
    ('public.fn_connect_avant_transfert_arbitrer(uuid,uuid,jsonb)','50e0e5e382878ec1e0013ceb4b87a843',true,'plpgsql'),
    ('public.fn_connect_remboursement_prendre(uuid,uuid)','8d406e7b86f733c420bc05fa7bc7971a',true,'plpgsql'),
    ('public.fn_connect_remboursement_demarrer(uuid,uuid)','4c43f80bab2ab55c2b2e7d0dc8cf4af2',true,'plpgsql'),
    ('public.fn_connect_remboursement_constater(uuid,uuid,jsonb)','f0650a8fe412cf693426f9a38ef68ab6',true,'plpgsql'),
    ('public.fn_connect_remboursements_a_traiter(integer)','c53e9f88b82b21dfe895c1e1e5611bbd',true,'plpgsql'),
    ('private.fn_connect_garder_orientation_trace()','81958dbe4016033ed3998c955fa6a258',true,'plpgsql'),
    ('private.fn_connect_garder_operation()','89c1b9a70d5f0387e21d80967271a8da',true,'plpgsql')) AS x(signature,corps,secdef,langage) LOOP
    SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
      WHERE p.oid=to_regprocedure(v_expected.signature);
    IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
      OR pg_get_userbyid(v_proc.proowner)<>'postgres'
      OR v_proc.prosecdef IS DISTINCT FROM v_expected.secdef OR v_proc.lanname<>v_expected.langage
      OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
      OR v_proc.provolatile<>'v'
      OR v_proc.proacl IS DISTINCT FROM (CASE WHEN v_expected.signature LIKE 'public.%'
        THEN '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
        ELSE '{postgres=X/postgres}'::aclitem[] END) THEN
      RAISE EXCEPTION 'CONNECT_MIGRATION_INSTALLATION (%)',v_expected.signature;
    END IF;
    IF v_expected.signature LIKE 'public.%' AND (
      (SELECT count(*) FROM private.security_definer_inventory
        WHERE signature=replace(v_expected.signature,'public.','')
          AND categorie='SERVICE_ONLY_REVOQUE' AND definition_md5=v_expected.corps)<>1
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=v_expected.signature)) THEN
      RAISE EXCEPTION 'CONNECT_MIGRATION_INSTALLATION_INVENTORY (%)',v_expected.signature;
    END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM private.stripe_connect_avant_transfert)
    OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.stripe_connect_avant_transfert'::regclass
      AND relrowsecurity AND pg_get_userbyid(relowner)='postgres'
      AND relacl='{postgres=arwdDxtm/postgres}'::aclitem[])
    OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.stripe_connect_avant_transfert'::regclass)
    OR (SELECT count(*) FROM pg_constraint WHERE conrelid='private.stripe_connect_avant_transfert'::regclass AND contype='f' AND confdeltype='r')<>7
    OR (SELECT count(*) FROM pg_constraint WHERE conrelid='private.stripe_connect_avant_transfert'::regclass AND contype='u')<>6
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.stripe_transfers'::regclass AND NOT tgisinternal)<>3
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.stripe_transfers'::regclass
      AND NOT tgisinternal AND tgenabled='O' AND pg_get_triggerdef(oid)=
      'CREATE TRIGGER trg_connect_garder_orientation BEFORE UPDATE ON public.stripe_transfers FOR EACH ROW EXECUTE FUNCTION private.fn_connect_garder_orientation_trace()')
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.stripe_connect_avant_transfert'::regclass
      AND NOT tgisinternal AND tgenabled='O' AND pg_get_triggerdef(oid)=
      'CREATE TRIGGER trg_connect_garder_operation BEFORE UPDATE ON private.stripe_connect_avant_transfert FOR EACH ROW EXECUTE FUNCTION private.fn_connect_garder_operation()') THEN
    RAISE EXCEPTION 'CONNECT_MIGRATION_TABLE_OR_TRIGGER';
  END IF;
END;
$postflight$;
-- CANDIDAT SOURCE NON EXECUTE. Barrière fermée ; aucune RPC d'ouverture.
-- À composer atomiquement avec le moteur candidat avant son COMMIT final,
-- après son préflight des anciennes dépendances ; pas un déploiement isolé.
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
SET LOCAL search_path=public,pg_temp;
DO $barrier_preflight$
DECLARE v_expected record; v_proc record;
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::int/10000<>17 THEN
   RAISE EXCEPTION 'CONNECT_BARRIER_CONTEXT';
 END IF;
 IF to_regclass('private.stripe_connect_release_gate') IS NOT NULL
   OR to_regtype('private.stripe_connect_release_gate') IS NOT NULL
   OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN('fn_stripe_payment_flow_claim_connect_v1','fn_stripe_webhook_event_claim_connect_v1'))
   OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature IN(
     'fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)','public.fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)',
     'fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)','public.fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)')) THEN
   RAISE EXCEPTION 'CONNECT_BARRIER_OBJECT_EXISTS';
 END IF;
 FOR v_expected IN SELECT * FROM (VALUES
    ('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','4506013ff5a5c0df5761523a221d8977','82f09bcf1334fb9041ae9a1628e4cd42','search_path=public, pg_temp','jsonb'),
    ('fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','c7b1356e671f49a19bf98cedf75f8249','9a50b2ad4d79d26e7244bb8e22cf0b85','search_path=public','text')) AS x(signature,corps,definition,configuration,resultat) LOOP
   SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('public.'||v_expected.signature);
   IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
     OR md5(pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM v_expected.definition
     OR pg_get_userbyid(v_proc.proowner)<>'postgres' OR v_proc.prosecdef IS DISTINCT FROM TRUE
     OR v_proc.provolatile<>'v' OR v_proc.lanname<>'plpgsql' OR v_proc.prokind<>'f'
     OR pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.resultat
     OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_expected.configuration]::text[]
     OR v_proc.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
     RAISE EXCEPTION 'CONNECT_BARRIER_DEPENDENCY (%)',v_expected.signature;
   END IF;
   -- Absence actuellement observée ou entrée exacte ; aucune entrée contradictoire normalisée.
   IF EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature='public.'||v_expected.signature)
     OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=v_expected.signature
       AND (categorie IS DISTINCT FROM 'SERVICE_ONLY_REVOQUE' OR definition_md5 IS DISTINCT FROM v_expected.corps)) THEN
     RAISE EXCEPTION 'CONNECT_BARRIER_INVENTORY (%)',v_expected.signature;
   END IF;
 END LOOP;
END;
$barrier_preflight$;

CREATE TABLE private.stripe_connect_release_gate (
 protocol text PRIMARY KEY CHECK(protocol='CONNECT_PRETRANSFER_V1'),
 enabled boolean NOT NULL DEFAULT false,
 installed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.stripe_connect_release_gate ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.stripe_connect_release_gate FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.stripe_connect_release_gate(protocol,enabled) VALUES('CONNECT_PRETRANSFER_V1',false);

CREATE OR REPLACE FUNCTION "public"."fn_stripe_payment_flow_claim"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid" DEFAULT NULL::"uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
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
  IF p_flow IN ('CONNECT_MISSION','CONNECT_INVOICE') THEN
    RAISE EXCEPTION 'CONNECT_CLIENT_VERSION_REQUIRED' USING ERRCODE='55000';
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


ALTER FUNCTION "public"."fn_stripe_payment_flow_claim"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid", "p_mission_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_stripe_payment_flow_claim_connect_v1"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid" DEFAULT NULL::"uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
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
  IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
    WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'CONNECT_RELEASE_CLOSED' USING ERRCODE='55000';
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


ALTER FUNCTION "public"."fn_stripe_payment_flow_claim_connect_v1"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid", "p_mission_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_stripe_webhook_event_claim"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) RETURNS "text"
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
  IF p_event_type='checkout.session.completed' AND p_payload#>>'{object,metadata,type}'='CONNECT_MISSION_PAYMENT' THEN
    RAISE EXCEPTION 'CONNECT_CLIENT_VERSION_REQUIRED' USING ERRCODE='55000';
  END IF;

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


ALTER FUNCTION "public"."fn_stripe_webhook_event_claim"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_stripe_webhook_event_claim_connect_v1"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) RETURNS "text"
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
  IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
    WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'CONNECT_RELEASE_CLOSED' USING ERRCODE='55000';
  END IF;

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


ALTER FUNCTION "public"."fn_stripe_webhook_event_claim_connect_v1"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) OWNER TO "postgres";

DO $barrier_installation$
DECLARE v_expected record; v_proc record; v_updated integer;
BEGIN
 FOR v_expected IN SELECT * FROM (VALUES
    ('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','b745cc054c57ea9ec14a983676493fd6','search_path=public, pg_temp','jsonb'),
    ('fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)','7a1f62537ac10dc062b73d80412d5892','search_path=public, pg_temp','jsonb'),
    ('fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','4c483d30b449de51b38e5790c1a3f93b','search_path=public','text'),
    ('fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)','252e57ef9c2cd0cc6ed6b2591a0e51b5','search_path=public','text')) AS x(signature,corps,configuration,resultat) LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC,anon,authenticated,service_role',v_expected.signature);
   EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role',v_expected.signature);
   INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
   VALUES(v_expected.signature,'SERVICE_ONLY_REVOQUE',v_expected.corps,
     'Barrière de version Connect : anciens callers refusés, nouveau protocole fermé jusqu’à activation revue ; autres claims historiques inchangés.',now())
   ON CONFLICT(signature) DO UPDATE SET definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le
   WHERE private.security_definer_inventory.categorie='SERVICE_ONLY_REVOQUE'
     AND (private.security_definer_inventory.signature,private.security_definer_inventory.definition_md5)
       IN (('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','4506013ff5a5c0df5761523a221d8977'),('fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','c7b1356e671f49a19bf98cedf75f8249'));
   GET DIAGNOSTICS v_updated=ROW_COUNT;
   IF v_updated<>1 THEN RAISE EXCEPTION 'CONNECT_BARRIER_INVENTORY_INSTALLATION (%)',v_expected.signature; END IF;
   SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('public.'||v_expected.signature);
   IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
     OR pg_get_userbyid(v_proc.proowner)<>'postgres' OR v_proc.prosecdef IS DISTINCT FROM TRUE
     OR v_proc.provolatile<>'v' OR v_proc.lanname<>'plpgsql' OR v_proc.prokind<>'f'
     OR pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.resultat
     OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_expected.configuration]::text[]
     OR v_proc.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
     OR (SELECT count(*) FROM private.security_definer_inventory WHERE signature=v_expected.signature
       AND categorie='SERVICE_ONLY_REVOQUE' AND definition_md5=v_expected.corps)<>1 THEN
     RAISE EXCEPTION 'CONNECT_BARRIER_INSTALLATION (%)',v_expected.signature;
   END IF;
 END LOOP;
 IF (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
   OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.stripe_connect_release_gate'::regclass
     AND pg_get_userbyid(relowner)='postgres' AND relrowsecurity
     AND relacl='{postgres=arwdDxtm/postgres}'::aclitem[])
   OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.stripe_connect_release_gate'::regclass)
   OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.stripe_connect_release_gate'::regclass AND NOT tgisinternal)
   OR EXISTS(SELECT 1 FROM pg_rewrite WHERE ev_class='private.stripe_connect_release_gate'::regclass AND rulename<>'_RETURN') THEN
   RAISE EXCEPTION 'CONNECT_BARRIER_NOT_CLOSED';
 END IF;
END;
$barrier_installation$;
-- FRAGMENT NON EXECUTE : après moteur privé 2cf6b7bb et barrière fermée190fea,
-- avant leur unique COMMIT. Aucun BEGIN/COMMIT ni activation dans ce fragment.
-- Dépendances RO staging observées le 01/10/2026 à18:04 et18:06UTC.
SET LOCAL search_path=pg_catalog;
DO $suivi_preflight$
DECLARE v_expected record; v_proc record;
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17 THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_CONTEXTE';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='fn_suivi_remboursements_connect_facture')
   OR EXISTS(SELECT 1 FROM private.security_definer_inventory
     WHERE signature ~ '^(public[.])?fn_suivi_remboursements_connect_facture[(]') THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_EXISTANTE';
 END IF;
 IF to_regclass('private.stripe_connect_avant_transfert') IS NULL
   OR to_regclass('private.stripe_connect_release_gate') IS NULL THEN
   RAISE EXCEPTION 'SUIVI_MOTEUR_ABSENT';
 END IF;
 IF (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
     WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE) THEN
   RAISE EXCEPTION 'SUIVI_PROTOCOLE_NON_FERME';
 END IF;
 FOR v_expected IN SELECT * FROM (VALUES
    ('auth.uid()','cdef18c69c4f4cbbced2eaf81e628b49','ea3b41bf29e2ad573067939329aa088e','supabase_auth_admin',NULL,'{=X/supabase_auth_admin,supabase_auth_admin=X/supabase_auth_admin,dashboard_user=X/supabase_auth_admin}',false,'s','sql','uuid',NULL,NULL),
    ('public.est_admin()','ef86d65809c3f76a1ac08eb737796fad','7e2b7825e43b9ea73c540f5f1ca9b264','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',true,'s','sql','boolean','est_admin()','ADMIN_EST_ADMIN_VALIDE'),
    ('public.est_admin_valide()','7954bb4e079865c63c4ba1096bd1fc76','ac1b087cbbf231e4b0ac8523054c25bc','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',true,'s','sql','boolean','est_admin_valide()','ADMIN_EST_ADMIN_VALIDE'),
    ('public.fn_a_permission_etablissement(text,uuid)','1ee98c0e7094db4e98277b85ce71c6ec','324d479198251e9c91524f28496780ba','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s','plpgsql','boolean','fn_a_permission_etablissement(text,uuid)','MIXTE_TENANT_ADMIN'),
    ('public.fn_compte_auth_actif()','8246c4c1f1b0a8053adb176a06c96766','cba1336dbd147cadc94bc6baf06ceb43','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s','sql','boolean','fn_compte_auth_actif()','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('public.fn_role_etablissement_courant(uuid)','ceb4e333f4b7f69a3be422b9753b559a','c263e1db47a25c67de3a2308dc8aa81c','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s','plpgsql','text','fn_role_etablissement_courant(uuid)','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('public.mon_etablissement_id()','dc3ef839d2920fb33cf6d7b320842c10','c460c68169ff164cb109501d6dde885d','postgres','search_path=pg_catalog, public, auth','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',true,'s','sql','uuid','mon_etablissement_id()','RPC_UTILISATEUR_AUTH_INTERNE')) AS x(signature,corps,definition,proprietaire,configuration,acl,secdef,volatilite,langage,resultat,inventaire,categorie) LOOP
   SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(v_expected.signature);
   IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
     OR md5(pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM v_expected.definition
     OR pg_get_userbyid(v_proc.proowner) IS DISTINCT FROM v_expected.proprietaire
     OR v_proc.prosecdef IS DISTINCT FROM v_expected.secdef
     OR v_proc.provolatile IS DISTINCT FROM v_expected.volatilite::"char"
     OR v_proc.lanname IS DISTINCT FROM v_expected.langage
     OR v_proc.prokind IS DISTINCT FROM 'f'::"char"
     OR pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.resultat
     OR v_proc.proconfig IS DISTINCT FROM (CASE WHEN v_expected.configuration IS NULL THEN NULL::text[] ELSE ARRAY[v_expected.configuration]::text[] END)
     OR v_proc.proacl IS DISTINCT FROM v_expected.acl::aclitem[] THEN
     RAISE EXCEPTION 'SUIVI_DEPENDANCE_INATTENDUE (%)',v_expected.signature;
   END IF;
   IF v_expected.inventaire IS NOT NULL AND (
     (SELECT count(*) FROM private.security_definer_inventory
       WHERE signature=v_expected.inventaire AND categorie=v_expected.categorie
       AND definition_md5=v_expected.corps)<>1
     OR EXISTS(SELECT 1 FROM private.security_definer_inventory
       WHERE signature='public.'||v_expected.inventaire)) THEN
     RAISE EXCEPTION 'SUIVI_DEPENDANCE_INVENTAIRE (%)',v_expected.signature;
   END IF;
 END LOOP;
END;
$suivi_preflight$;

-- CANDIDAT DE LECTURE, NON MIGRE / NON EXECUTE.
-- A composer avec le schéma privé Connect avant transfert, après revue.
-- Aucun accès direct nouveau aux tables, aucun effet fournisseur.
CREATE FUNCTION public.fn_suivi_remboursements_connect_facture(
  p_facture_honoraire_id uuid,
  p_checkout_session_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $suivi$
DECLARE
  v_uid uuid := auth.uid();
  v_h public.factures_honoraires;
  v_s public.stripe_transfers;
  v_admin boolean;
  v_finance boolean;
  v_count bigint;
  v_paiement_statut text := NULL;
  v_operations jsonb;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès refusé.' USING ERRCODE = '42501';
  END IF;

  SELECT h.* INTO v_h FROM public.factures_honoraires h
  WHERE h.id = p_facture_honoraire_id;
  v_admin := public.est_admin_valide() IS TRUE;
  v_finance := v_admin OR (
    v_h.etablissement_id = public.mon_etablissement_id()
    AND public.fn_a_permission_etablissement('lecture_paiement', v_h.etablissement_id) IS TRUE
  );
  IF v_h.id IS NULL OR v_h.type_document IS DISTINCT FROM 'FACTURE'
     OR (v_h.soignant_id IS DISTINCT FROM v_uid AND v_finance IS NOT TRUE) THEN
    RAISE EXCEPTION 'Accès refusé.' USING ERRCODE = '42501';
  END IF;
  IF v_h.mission_id IS NULL THEN
    RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
  END IF;

  -- NULL demande l'historique. Une chaîne vide ou mal formée n'est jamais NULL.
  IF p_checkout_session_id IS NOT NULL AND (
    length(p_checkout_session_id) > 255 OR p_checkout_session_id !~ '^cs_[A-Za-z0-9_]+$'
  ) THEN
    RAISE EXCEPTION 'Session de paiement invalide.' USING ERRCODE = '22023';
  END IF;

  -- Ne pas affecter une trace ancienne sans FK à une facture par déduction.
  -- Une Session étrangère ou inconnue donne la même absence de trace propre.
  IF p_checkout_session_id IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM public.stripe_transfers s
    WHERE s.facture_honoraire_id = v_h.id
      AND s.stripe_checkout_session_id = p_checkout_session_id;
    IF v_count > 1 THEN
      RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
    ELSIF v_count = 1 THEN
      SELECT s.* INTO STRICT v_s FROM public.stripe_transfers s
      WHERE s.facture_honoraire_id = v_h.id
        AND s.stripe_checkout_session_id = p_checkout_session_id;
      IF v_s.mission_id IS DISTINCT FROM v_h.mission_id
         OR v_s.etablissement_id IS DISTINCT FROM v_h.etablissement_id
         OR v_s.soignant_id IS DISTINCT FROM v_h.soignant_id
         OR v_s.statut NOT IN ('EN_ATTENTE','CHARGE_REUSSI','TRANSFERE','PAYE','ECHOUE','REMBOURSE','ANNULEE')
         OR (SELECT count(*) FROM public.stripe_transfers s
             WHERE s.stripe_checkout_session_id = p_checkout_session_id) <> 1 THEN
        RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
      END IF;
      v_paiement_statut := v_s.statut;
    END IF;
  END IF;

  -- Toutes les lectures partagent le snapshot STABLE de l'appel. On valide la
  -- filiation persistée, pas l'affectation ou l'activité actuelles de la mission.
  -- Aucun appel au helper privé de mutation / admissibilité d'un nouveau POST.
  IF EXISTS (
    SELECT 1
    FROM private.stripe_connect_avant_transfert o
    LEFT JOIN public.stripe_transfers s ON s.id = o.trace_id
    LEFT JOIN public.factures c ON c.id = o.facture_commission_id
    WHERE o.facture_honoraire_id = v_h.id AND o.orientation = 'REFUND'
      AND (p_checkout_session_id IS NULL OR o.session_id = p_checkout_session_id)
      AND (
        o.mission_id IS DISTINCT FROM v_h.mission_id
        OR o.etablissement_id IS DISTINCT FROM v_h.etablissement_id
        OR o.soignant_id IS DISTINCT FROM v_h.soignant_id
        OR o.session_id IS NULL OR o.trace_id IS NULL
        OR s.id IS NULL OR s.facture_honoraire_id IS DISTINCT FROM v_h.id
        OR s.mission_id IS DISTINCT FROM o.mission_id
        OR s.etablissement_id IS DISTINCT FROM o.etablissement_id
        OR s.soignant_id IS DISTINCT FROM o.soignant_id
        OR s.facture_id IS DISTINCT FROM o.facture_commission_id
        OR s.stripe_checkout_session_id IS DISTINCT FROM o.session_id
        OR s.stripe_transfer_id IS NOT NULL
        OR (s.stripe_payment_intent_id IS NOT NULL AND s.stripe_payment_intent_id IS DISTINCT FROM o.payment_intent_id)
        OR (s.stripe_charge_id IS NOT NULL AND s.stripe_charge_id IS DISTINCT FROM o.charge_id)
        OR c.id IS NULL OR c.type_document IS DISTINCT FROM 'FACTURE'
        OR c.facture_honoraire_id IS DISTINCT FROM v_h.id
        OR c.mission_id IS DISTINCT FROM o.mission_id
        OR c.etablissement_id IS DISTINCT FROM o.etablissement_id
        OR round(v_h.montant_ttc * 100) IS DISTINCT FROM o.soignant_cents
        OR round(c.montant_ttc * 100) IS DISTINCT FROM o.commission_cents
        OR round(s.montant_soignant * 100) IS DISTINCT FROM o.soignant_cents
        OR round(s.montant_commission * 100) IS DISTINCT FROM o.commission_cents
        OR round(s.montant_total * 100) IS DISTINCT FROM o.total_cents
        OR o.soignant_cents <= 0 OR o.commission_cents <= 0
        OR o.total_cents IS DISTINCT FROM o.soignant_cents + o.commission_cents
        OR o.total_cents > 9007199254740991
        OR o.refund_status IS NULL
        OR o.refund_status NOT IN ('READY','PENDING','REQUIRES_ACTION','SUCCEEDED','FAILED','CANCELED','REVIEW')
        OR (o.refund_status = 'SUCCEEDED' AND (o.succeeded_at IS NULL OR o.review_code IS NOT NULL))
        OR s.statut IS DISTINCT FROM CASE
          WHEN o.refund_status = 'SUCCEEDED' THEN 'REMBOURSE'
          WHEN o.refund_status IN ('READY','PENDING','REQUIRES_ACTION') THEN 'EN_ATTENTE'
          WHEN o.refund_status IN ('FAILED','CANCELED','REVIEW') THEN 'ECHOUE'
          ELSE NULL END
        OR (o.review_code IS NOT NULL AND o.review_code NOT IN (
          'CREATE_WINDOW_CLOSED','REFUND_FAILED','REFUND_CANCELED',
          'REFUND_RETURNED_AFTER_SUCCESS','REFUND_REQUIRES_ACTION_AFTER_SUCCESS','REFUND_STATUS_CONTRADICTORY'))
        OR (SELECT count(*) FROM public.stripe_transfers sx
            WHERE sx.stripe_checkout_session_id = o.session_id) <> 1
      )
  ) THEN
    RAISE EXCEPTION 'Suivi de paiement indisponible.' USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id,
    'checkout_session_id', o.session_id,
    'statut', o.refund_status,
    'montant_honoraires_centimes', o.soignant_cents,
    'montant_commission_centimes', CASE WHEN v_finance IS TRUE THEN o.commission_cents ELSE NULL END,
    'montant_total_centimes', CASE WHEN v_finance IS TRUE THEN o.total_cents ELSE NULL END,
    'cree_le', o.created_at,
    'mis_a_jour_le', NULL,
    'succeeded_at', o.succeeded_at,
    'review_code', o.review_code
  ) ORDER BY o.created_at, o.id), '[]'::jsonb)
  INTO v_operations
  FROM private.stripe_connect_avant_transfert o
  WHERE o.facture_honoraire_id = v_h.id AND o.orientation = 'REFUND'
    AND (p_checkout_session_id IS NULL OR o.session_id = p_checkout_session_id);

  RETURN jsonb_build_object(
    'facture_honoraire_id', v_h.id,
    'mission_id', v_h.mission_id,
    'checkout_session_id_filtre', p_checkout_session_id,
    'source', 'CONNECT_AVANT_TRANSFERT',
    'visibilite_montants', CASE WHEN v_finance IS TRUE THEN 'TOTAL_ETABLISSEMENT' ELSE 'HONORAIRES' END,
    'paiement_statut', v_paiement_statut,
    'operations', v_operations,
    'lecture_complete', true
  );
END;
$suivi$;
ALTER FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) TO authenticated;
COMMENT ON FUNCTION public.fn_suivi_remboursements_connect_facture(uuid,text) IS
  'Lecture du suivi Connect avant transfert par facture autorisée et Session optionnelle exacte. Aucun effet financier, aucun secret fournisseur ; commissions et total réservés au périmètre établissement/admin.';

DO $suivi_installation$
DECLARE v_proc record;
BEGIN
 SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid=to_regprocedure('public.fn_suivi_remboursements_connect_facture(uuid,text)');
 IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM 'd2fd95bb65a2ba7f02089d8e53666893'
   OR pg_get_userbyid(v_proc.proowner)<>'postgres' OR v_proc.prosecdef IS DISTINCT FROM TRUE
   OR v_proc.provolatile<>'s' OR v_proc.prokind<>'f' OR v_proc.lanname<>'plpgsql'
   OR pg_get_function_result(v_proc.oid)<>'jsonb'
   OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
   OR v_proc.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}'::aclitem[]
   OR v_proc.proargnames IS DISTINCT FROM ARRAY['p_facture_honoraire_id','p_checkout_session_id']::text[]
   OR v_proc.pronargdefaults<>1 OR pg_get_expr(v_proc.proargdefaults,0) IS DISTINCT FROM 'NULL::text' THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_INATTENDUE';
 END IF;
 INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
 VALUES('fn_suivi_remboursements_connect_facture(uuid,text)','MIXTE_TENANT_ADMIN',
   'd2fd95bb65a2ba7f02089d8e53666893',
   'Lecture seule par facture : appelant actif, propriétaire soignant ou établissement avec lecture_paiement ou admin valide ; commission et total masqués au soignant.',now());
 IF (SELECT count(*) FROM private.security_definer_inventory
     WHERE signature='fn_suivi_remboursements_connect_facture(uuid,text)'
       AND categorie='MIXTE_TENANT_ADMIN' AND definition_md5='d2fd95bb65a2ba7f02089d8e53666893')<>1
   OR EXISTS(SELECT 1 FROM private.security_definer_inventory
     WHERE signature='public.fn_suivi_remboursements_connect_facture(uuid,text)') THEN
   RAISE EXCEPTION 'SUIVI_INSTALLATION_INVENTAIRE';
 END IF;
END;
$suivi_installation$;
COMMIT;

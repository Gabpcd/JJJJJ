-- CANDIDAT NON DEPLOYABLE : préflight LIVE / inventaire / ordre commission
-- encore à figer en migration après revue. Aucun bootstrap ni backfill.
-- Ce fichier n'est pas placé dans supabase/migrations et n'a pas été exécuté.
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

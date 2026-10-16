BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';
DO $preflight$
BEGIN
  IF current_user<>'postgres' OR to_regclass('private.stripe_connect_avant_transfert') IS NULL
    OR to_regprocedure('private.fn_connect_operation_verrouiller(uuid)') IS NULL
    OR to_regprocedure('private.fn_connect_creation_autorisee(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_PREREQUISITES';
  END IF;
END;$preflight$;

-- Le navigateur lit l'état Connect ; les Edge Functions authentifiées côté
-- serveur sont les seuls producteurs des références et capacités Stripe.
REVOKE INSERT,UPDATE,DELETE ON public.stripe_connect_onboarding FROM anon,authenticated;
DROP POLICY IF EXISTS pol_connect_insert ON public.stripe_connect_onboarding;
DROP POLICY IF EXISTS pol_connect_update ON public.stripe_connect_onboarding;
CREATE FUNCTION private.fn_connect_onboarding_exiger_serveur()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF current_user NOT IN ('postgres','supabase_admin','service_role')
     AND COALESCE(auth.jwt()->>'role','') <> 'service_role' THEN
    RAISE EXCEPTION 'CONNECT_ONBOARDING_SERVER_REQUIRED' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION private.fn_connect_onboarding_exiger_serveur() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER trg_connect_onboarding_serveur BEFORE INSERT OR UPDATE
ON public.stripe_connect_onboarding FOR EACH ROW EXECUTE FUNCTION private.fn_connect_onboarding_exiger_serveur();

-- Le ledger existant reste l'autorité : aucune table de soldes parallèle,
-- aucun changement des comptes manuels, aucune admission de l'historique.
ALTER TABLE public.stripe_transfers
  ADD COLUMN standard_payout_state text,
  ADD COLUMN standard_payout_account_id text,
  ADD COLUMN standard_payout_attempt integer NOT NULL DEFAULT 0,
  ADD COLUMN standard_payout_previous_id text,
  ADD COLUMN standard_payout_known_ids text[] NOT NULL DEFAULT '{}',
  ADD COLUMN standard_payout_first_post_at timestamptz,
  ADD COLUMN standard_payout_next_read_at timestamptz,
  ADD COLUMN standard_payout_owner uuid,
  ADD COLUMN standard_payout_lease_until timestamptz,
  ADD COLUMN standard_payout_error_code text,
  ADD CONSTRAINT stripe_transfers_standard_payout_state_check CHECK
    (standard_payout_state IN ('WAITING','SUBMITTED','PAID','FAILED','REVIEW')),
  ADD CONSTRAINT stripe_transfers_standard_payout_attempt_check CHECK (standard_payout_attempt BETWEEN 0 AND 3),
  ADD CONSTRAINT stripe_transfers_standard_payout_identity_check CHECK
    (standard_payout_state IS NULL OR (standard_payout_account_id IS NOT NULL AND facture_honoraire_id IS NOT NULL AND stripe_transfer_id IS NOT NULL));
CREATE INDEX stripe_transfers_standard_payout_due ON public.stripe_transfers(standard_payout_next_read_at)
WHERE standard_payout_state IN ('WAITING','SUBMITTED','FAILED');
CREATE UNIQUE INDEX stripe_transfers_standard_transfer_once ON public.stripe_transfers(stripe_transfer_id)
WHERE standard_payout_state IS NOT NULL;
CREATE UNIQUE INDEX stripe_transfers_standard_payout_once ON public.stripe_transfers(stripe_payout_id)
WHERE standard_payout_state IS NOT NULL AND stripe_payout_id IS NOT NULL;

CREATE FUNCTION private.fn_connect_admettre_payout_standard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o private.stripe_connect_avant_transfert;
BEGIN
  -- Le trigger est sous verrou ST : lire l'intention sans prendre ses verrous.
  -- Seul le flux nouvellement admis/lié/arbitré peut enfiler un versement.
  IF NEW.statut='TRANSFERE' AND NEW.standard_payout_state IS NULL
     AND NEW.stripe_payout_id IS NULL AND NEW.stripe_transfer_id IS NOT NULL
     AND (TG_OP='INSERT' OR OLD.statut IS DISTINCT FROM 'TRANSFERE') THEN
    SELECT * INTO o FROM private.stripe_connect_avant_transfert
      WHERE trace_id=NEW.id AND orientation='TRANSFER' AND session_id=NEW.stripe_checkout_session_id
        AND payment_intent_id=NEW.stripe_payment_intent_id AND charge_id=NEW.stripe_charge_id
        AND mission_id=NEW.mission_id AND soignant_id=NEW.soignant_id AND etablissement_id=NEW.etablissement_id
        AND facture_honoraire_id=NEW.facture_honoraire_id AND facture_commission_id=NEW.facture_id
        AND soignant_cents=round(NEW.montant_soignant*100)::bigint
        AND commission_cents=round(NEW.montant_commission*100)::bigint
        AND total_cents=round(NEW.montant_total*100)::bigint;
    IF FOUND THEN
      NEW.standard_payout_state:='WAITING';
      NEW.standard_payout_account_id:=o.destination_id;
      NEW.standard_payout_next_read_at:=clock_timestamp();
    END IF;
  END IF;
  RETURN NEW;
END;$$;
REVOKE ALL ON FUNCTION private.fn_connect_admettre_payout_standard() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER zzz_connect_admettre_payout_standard BEFORE INSERT OR UPDATE OF statut
ON public.stripe_transfers FOR EACH ROW EXECUTE FUNCTION private.fn_connect_admettre_payout_standard();

CREATE FUNCTION public.fn_connect_payouts_a_traiter(p_limit integer DEFAULT 5)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.fn_connect_exiger_service();
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id)), '[]'::jsonb)
    FROM (SELECT st.id FROM public.stripe_transfers st
      JOIN private.stripe_connect_avant_transfert o ON o.trace_id=st.id AND o.session_id=st.stripe_checkout_session_id
        AND o.destination_id=st.standard_payout_account_id AND o.orientation='TRANSFER' AND o.livemode IS TRUE
      JOIN public.soignants so ON so.id=st.soignant_id AND so.est_compte_test IS FALSE
      JOIN public.etablissements e ON e.id=st.etablissement_id AND e.est_compte_test IS FALSE
      WHERE st.standard_payout_state IN ('WAITING','SUBMITTED','FAILED')
        AND st.standard_payout_next_read_at<=clock_timestamp()
        AND (st.standard_payout_lease_until IS NULL OR st.standard_payout_lease_until<=clock_timestamp())
      ORDER BY st.standard_payout_next_read_at,st.id LIMIT LEAST(GREATEST(p_limit,1),10))s);
END;$$;

CREATE FUNCTION public.fn_connect_payout_prendre(p_trace_id uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.stripe_transfers; o private.stripe_connect_avant_transfert;
BEGIN
  PERFORM private.fn_connect_exiger_service();
  IF p_owner IS NULL THEN RAISE EXCEPTION 'CONNECT_PAYOUT_OWNER'; END IF;
  SELECT * INTO o FROM private.stripe_connect_avant_transfert WHERE trace_id=p_trace_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONNECT_PAYOUT_NOT_ADMITTED'; END IF;
  -- Ordre canonique mission→ST→FH→commission→intention, commun au webhook.
  o:=private.fn_connect_operation_verrouiller(o.id);
  SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id;
  IF s.standard_payout_state IS NULL OR s.standard_payout_state NOT IN ('WAITING','SUBMITTED','FAILED')
     OR (s.standard_payout_lease_until>clock_timestamp() AND s.standard_payout_owner IS DISTINCT FROM p_owner)
     OR s.standard_payout_next_read_at>clock_timestamp() THEN RETURN NULL; END IF;
  IF o.orientation IS DISTINCT FROM 'TRANSFER' OR o.destination_id IS DISTINCT FROM s.standard_payout_account_id
     OR o.trace_id IS DISTINCT FROM s.id OR s.stripe_transfer_id IS NULL THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_IDENTITY'; END IF;
  UPDATE public.stripe_transfers SET standard_payout_owner=p_owner,
    standard_payout_lease_until=clock_timestamp()+interval '5 minutes' WHERE id=s.id;
  RETURN jsonb_build_object('id',s.id,'missionId',s.mission_id,'soignantId',s.soignant_id,
    'etablissementId',s.etablissement_id,'factureHonoraireId',s.facture_honoraire_id,
    'accountId',s.standard_payout_account_id,'customerId',o.customer_id,'transferId',s.stripe_transfer_id,
    'paymentIntentId',s.stripe_payment_intent_id,'chargeId',s.stripe_charge_id,
    'amountCents',o.soignant_cents,'totalCents',o.total_cents,'livemode',o.livemode,
    'state',s.standard_payout_state,'attempt',s.standard_payout_attempt,
    'payoutId',s.stripe_payout_id,'previousPayoutId',s.standard_payout_previous_id,
    'firstPostAt',s.standard_payout_first_post_at);
END;$$;

CREATE FUNCTION public.fn_connect_payout_demarrer(p_trace_id uuid,p_owner uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.stripe_transfers; o private.stripe_connect_avant_transfert;
BEGIN
  PERFORM private.fn_connect_exiger_service();
  SELECT * INTO STRICT o FROM private.stripe_connect_avant_transfert WHERE trace_id=p_trace_id;
  o:=private.fn_connect_operation_verrouiller(o.id);
  SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id;
  IF s.standard_payout_owner IS DISTINCT FROM p_owner OR p_owner IS NULL OR s.standard_payout_lease_until<=clock_timestamp()
     OR s.standard_payout_state IS DISTINCT FROM 'WAITING' OR s.stripe_payout_id IS NOT NULL
     OR s.statut IS DISTINCT FROM 'TRANSFERE' OR o.orientation IS DISTINCT FROM 'TRANSFER' OR o.livemode IS DISTINCT FROM TRUE
     OR NOT private.fn_connect_creation_autorisee(o.id)
     OR s.stripe_reversal_statut IS DISTINCT FROM 'AUCUN' OR s.stripe_amount_reversed_cents<>0
     OR s.dispute_statut='OUVERT'
     OR EXISTS(SELECT 1 FROM public.litiges WHERE mission_id=s.mission_id
       AND (facture_id=s.facture_honoraire_id OR facture_id IS NULL)
       AND statut IN('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS','REVUE_ADMIN'))
     -- Le solde Connect appartient au soignant, pas à une seule mission.
     -- Aucun nouveau payout standard tant qu'un escrow de ce compte reste
     -- non terminal ou d'état inconnu, même sur une autre mission.
     OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE soignant_id=s.soignant_id
       AND (statut IS NULL OR statut NOT IN('PAYE','REMBOURSE'))) THEN RETURN FALSE; END IF;
  IF s.standard_payout_first_post_at < clock_timestamp()-interval '20 hours' THEN
    UPDATE public.stripe_transfers SET standard_payout_state='REVIEW',standard_payout_error_code='AMBIGUOUS_CREATE_EXPIRED',
      standard_payout_owner=NULL,standard_payout_lease_until=NULL WHERE id=s.id;
    RETURN FALSE;
  END IF;
  UPDATE public.stripe_transfers SET standard_payout_first_post_at=COALESCE(standard_payout_first_post_at,clock_timestamp())
    WHERE id=s.id;
  RETURN TRUE;
END;$$;

-- Un échec certain ne redevient créable qu'après relecture Stripe et retour
-- des fonds available par le worker. Une ambiguïté n'appelle jamais cette RPC.
CREATE FUNCTION public.fn_connect_payout_reessayer(p_trace_id uuid,p_owner uuid,p_previous_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.stripe_transfers;
BEGIN
  PERFORM private.fn_connect_exiger_service();
  SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id FOR UPDATE;
  IF s.standard_payout_owner IS DISTINCT FROM p_owner OR p_owner IS NULL OR s.standard_payout_lease_until<=clock_timestamp()
     OR s.standard_payout_state IS DISTINCT FROM 'FAILED' OR s.stripe_payout_id IS DISTINCT FROM p_previous_id
     OR s.standard_payout_attempt>=3 THEN RETURN FALSE; END IF;
  UPDATE public.stripe_transfers SET standard_payout_state='WAITING',standard_payout_previous_id=stripe_payout_id,
    stripe_payout_id=NULL,standard_payout_attempt=standard_payout_attempt+1,standard_payout_first_post_at=NULL,
    standard_payout_error_code=NULL WHERE id=s.id;
  RETURN TRUE;
END;$$;

CREATE FUNCTION public.fn_connect_payout_constater(p_trace_id uuid,p_account_id text,p_payout jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.stripe_transfers; st text:=p_payout->>'status'; pid text:=p_payout->>'id'; expected_live boolean;
BEGIN
  PERFORM private.fn_connect_exiger_service();
  SELECT * INTO STRICT s FROM public.stripe_transfers WHERE id=p_trace_id FOR UPDATE;
  SELECT livemode INTO STRICT expected_live FROM private.stripe_connect_avant_transfert WHERE trace_id=s.id;
  IF s.standard_payout_state IS NULL OR p_account_id IS DISTINCT FROM s.standard_payout_account_id
     OR COALESCE(pid,'')!~'^po_[A-Za-z0-9_]+$' OR st IS NULL OR st NOT IN('pending','in_transit','paid','failed','canceled')
     OR (p_payout->>'amount')::bigint IS DISTINCT FROM round(s.montant_soignant*100)::bigint
     OR p_payout->>'currency' IS DISTINCT FROM 'eur' OR p_payout#>>'{metadata,type}' IS DISTINCT FROM 'CONNECT_STANDARD_PAYOUT'
     OR p_payout#>>'{metadata,trace_id}' IS DISTINCT FROM s.id::text
     OR p_payout#>>'{metadata,transfer_id}' IS DISTINCT FROM s.stripe_transfer_id
     OR p_payout#>>'{metadata,mission_id}' IS DISTINCT FROM s.mission_id::text
     OR p_payout#>>'{metadata,soignant_id}' IS DISTINCT FROM s.soignant_id::text THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_IDENTITY'; END IF;
  IF p_payout->'livemode' IS DISTINCT FROM to_jsonb(expected_live) OR p_payout->'automatic' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_MODE'; END IF;
  IF p_payout#>>'{metadata,attempt}' IS DISTINCT FROM s.standard_payout_attempt::text THEN
    -- Une ancienne tentative connue ne peut ni solder ni écraser la courante.
    IF COALESCE(p_payout#>>'{metadata,attempt}','')~'^[0-3]$'
      AND (p_payout#>>'{metadata,attempt}')::integer<s.standard_payout_attempt
      AND st IN('failed','canceled') THEN RETURN jsonb_build_object('ignored',true); END IF;
    UPDATE public.stripe_transfers SET standard_payout_state='REVIEW',standard_payout_error_code='OLD_PAYOUT_CONTRADICTORY'
      WHERE id=s.id;
    RETURN jsonb_build_object('review',true);
  END IF;
  IF s.stripe_payout_id IS NOT NULL AND s.stripe_payout_id<>pid THEN RAISE EXCEPTION 'CONNECT_PAYOUT_DUPLICATE'; END IF;
  -- Un GET pending/in_transit commencé avant un webhook terminal peut finir
  -- après lui. Il ne remet jamais en cause le constat terminal du même objet.
  IF s.standard_payout_state IN('PAID','FAILED') AND st IN('pending','in_transit') THEN
    RETURN jsonb_build_object('ignored',true);
  END IF;
  IF (s.standard_payout_state='PAID' AND st<>'paid') OR (s.standard_payout_state='FAILED' AND st NOT IN('failed','canceled')) THEN
    UPDATE public.stripe_transfers SET standard_payout_state='REVIEW',standard_payout_error_code='PAYOUT_STATUS_CONTRADICTORY',
      statut=CASE WHEN statut='PAYE' THEN 'TRANSFERE' ELSE statut END,
      erreur='Le virement bancaire nécessite une vérification.'
      WHERE id=s.id;
    RETURN jsonb_build_object('review',true);
  END IF;
  UPDATE public.stripe_transfers SET stripe_payout_id=pid,
    standard_payout_known_ids=CASE WHEN pid=ANY(standard_payout_known_ids) THEN standard_payout_known_ids
      ELSE array_append(standard_payout_known_ids,pid) END,
    standard_payout_state=CASE WHEN st='paid' THEN 'PAID' WHEN st IN('failed','canceled') THEN 'FAILED' ELSE 'SUBMITTED' END,
    statut=CASE WHEN st='paid' AND statut='TRANSFERE' THEN 'PAYE' ELSE statut END,
    paye_le=CASE WHEN st='paid' THEN COALESCE(paye_le,clock_timestamp()) ELSE paye_le END,
    standard_payout_next_read_at=clock_timestamp()+CASE WHEN st IN('failed','canceled') THEN interval '1 day' ELSE interval '30 minutes' END,
    standard_payout_error_code=CASE WHEN st IN('failed','canceled') THEN 'PAYOUT_TERMINAL_FAILURE' ELSE NULL END
    WHERE id=s.id;
  IF (st='paid' AND s.standard_payout_state<>'PAID')
     OR (st IN('failed','canceled') AND s.standard_payout_state<>'FAILED') THEN
    INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details,navigateur_acteur)
    VALUES(s.soignant_id,'SYSTEME',CASE WHEN st='paid' THEN 'FINANCE_PAYOUT_PAID'
      ELSE 'FINANCE_PAYOUT_FAILED' END,
      'mission',s.mission_id,jsonb_build_object('evenement','CONNECT_STANDARD_PAYOUT_STATUS',
        'trace_id',s.id,'stripe_payout_id',pid,'statut',st,'tentative',s.standard_payout_attempt),
      'fn_connect_payout_constater');
  END IF;
  RETURN jsonb_build_object('recorded',true,'state',st);
END;$$;

-- Lecture fermée des IDs de payouts rattachés au ledger du compte exact.
-- Les metadata fournisseur seules ne suffisent pas à reconnaître un mouvement.
CREATE FUNCTION public.fn_connect_payout_est_connu(p_account_id text,p_payout jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.fn_connect_exiger_service();
  IF p_payout->>'currency' IS DISTINCT FROM 'eur' OR p_payout->'automatic' IS DISTINCT FROM 'false'::jsonb
    OR COALESCE(p_payout->>'id','')!~'^po_[A-Za-z0-9_]+$' THEN RETURN FALSE; END IF;
  IF p_payout#>>'{metadata,type}'='CONNECT_STANDARD_PAYOUT' THEN
    RETURN EXISTS(SELECT 1 FROM public.stripe_transfers s
      JOIN private.stripe_connect_avant_transfert o ON o.trace_id=s.id AND o.session_id=s.stripe_checkout_session_id
      WHERE s.standard_payout_account_id=p_account_id AND o.destination_id=p_account_id
        AND p_payout->'livemode'=to_jsonb(o.livemode)
        AND p_payout->>'id'=ANY(s.standard_payout_known_ids)
        AND p_payout#>>'{metadata,trace_id}'=s.id::text
        AND p_payout#>>'{metadata,transfer_id}'=s.stripe_transfer_id
        AND p_payout#>>'{metadata,mission_id}'=s.mission_id::text
        AND p_payout#>>'{metadata,soignant_id}'=s.soignant_id::text
        AND (p_payout->>'amount')::bigint=round(s.montant_soignant*100)::bigint);
  ELSIF p_payout#>>'{metadata,type}'='ESCROW_RELEASE' THEN
    RETURN EXISTS(SELECT 1 FROM public.paiements_escrow e
      JOIN public.stripe_connect_onboarding b ON b.soignant_id=e.soignant_id AND b.stripe_account_id=p_account_id
      WHERE e.stripe_payout_id=p_payout->>'id' AND p_payout#>>'{metadata,paiement_escrow_id}'=e.id::text
        AND p_payout#>>'{metadata,mission_id}'=e.mission_id::text
        AND p_payout#>>'{metadata,soignant_id}'=e.soignant_id::text
        AND (p_payout->>'amount')::bigint=e.honoraires_cents);
  END IF;
  RETURN FALSE;
END;$$;

CREATE FUNCTION public.fn_connect_payout_reporter(p_trace_id uuid,p_owner uuid,p_code text,p_review boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.fn_connect_exiger_service();
  IF p_code NOT IN('WAITING_FUNDS','WAITING_ACCOUNT','SOURCE_NOT_ACQUIRED','IDENTITY_MISMATCH',
    'PAGINATION_INCOMPLETE','UNKNOWN_ACCOUNT_PAYOUT','AMBIGUOUS_CREATE_EXPIRED','PROVIDER_OR_PERSISTENCE_ERROR','CHECKED') THEN
    RAISE EXCEPTION 'CONNECT_PAYOUT_ERROR_CODE'; END IF;
  UPDATE public.stripe_transfers SET standard_payout_next_read_at=clock_timestamp()+interval '30 minutes',
    standard_payout_owner=NULL,standard_payout_lease_until=NULL,
    standard_payout_error_code=CASE WHEN p_code='CHECKED' THEN standard_payout_error_code ELSE p_code END,
    standard_payout_state=CASE WHEN p_review THEN 'REVIEW' ELSE standard_payout_state END
  WHERE id=p_trace_id AND standard_payout_owner=p_owner;
END;$$;

DO $acl$
DECLARE p record;
BEGIN
  FOR p IN SELECT oid,regexp_replace(oid::regprocedure::text,'^public[.]','') AS signature,prosrc FROM pg_proc
    WHERE pronamespace='public'::regnamespace AND proname IN
      ('fn_connect_payouts_a_traiter','fn_connect_payout_prendre','fn_connect_payout_demarrer',
       'fn_connect_payout_reessayer','fn_connect_payout_constater','fn_connect_payout_est_connu','fn_connect_payout_reporter') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC,anon,authenticated',p.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role',p.signature);
    INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification)
    VALUES(p.signature,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'Versement bancaire du seul transfert standard admis : lecture, lease, CAS et constat fournisseur exact.');
  END LOOP;
END;$acl$;
COMMIT;

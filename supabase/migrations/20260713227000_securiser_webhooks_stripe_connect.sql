-- Webhooks Stripe plateforme + Connect : claim atomique et cycle payout escrow.
--
-- Un endpoint Connect de production peut recevoir des événements live ET test.
-- La source et le mode sont donc persistés après vérification de signature, et
-- le claim empêche deux livraisons concurrentes du même event.id d'exécuter la
-- logique financière en parallèle.

ALTER TABLE public.stripe_webhook_events
  ADD COLUMN IF NOT EXISTS source_webhook text,
  ADD COLUMN IF NOT EXISTS livemode boolean,
  ADD COLUMN IF NOT EXISTS traitement_commence_le timestamptz,
  ADD COLUMN IF NOT EXISTS tentatives integer NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.stripe_webhook_events'::regclass
      AND conname = 'stripe_webhook_events_source_check'
  ) THEN
    ALTER TABLE public.stripe_webhook_events
      ADD CONSTRAINT stripe_webhook_events_source_check
      CHECK (source_webhook IS NULL OR source_webhook IN ('PLATFORM', 'CONNECT'));
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_stripe_webhook_event_claim(
  p_event_id text,
  p_event_type text,
  p_payload jsonb,
  p_source_webhook text,
  p_livemode boolean
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted integer := 0;
  v_claimed integer := 0;
  v_traite_le timestamptz;
BEGIN
  IF NOT (
    public.est_admin()
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  ) THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
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

REVOKE ALL ON FUNCTION public.fn_stripe_webhook_event_claim(text, text, jsonb, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_stripe_webhook_event_claim(text, text, jsonb, text, boolean) TO service_role;

-- Associe un payout automatique aux seuls transfers que Stripe expose dans les
-- balance transactions de ce payout. La liste est construite par le webhook
-- sous le compte Connect (`Stripe-Account`) puis verrouillée ici pour empêcher
-- qu'un transfer soit rattaché concurremment à deux payouts différents.
CREATE OR REPLACE FUNCTION public.fn_stripe_lier_payout_transfers(
  p_stripe_payout_id text,
  p_soignant_id uuid,
  p_stripe_transfer_ids text[]
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated integer := 0;
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_stripe_payout_id, '')), '') IS NULL
     OR p_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Paramètres payout invalides' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(array_length(p_stripe_transfer_ids, 1), 0) = 0 THEN
    RETURN 0;
  END IF;

  PERFORM 1
  FROM public.stripe_transfers st
  WHERE st.soignant_id = p_soignant_id
    AND st.stripe_transfer_id = ANY(p_stripe_transfer_ids)
  FOR UPDATE;

  IF EXISTS (
    SELECT 1
    FROM public.stripe_transfers st
    WHERE st.soignant_id = p_soignant_id
      AND st.stripe_transfer_id = ANY(p_stripe_transfer_ids)
      AND st.stripe_payout_id IS NOT NULL
      AND st.stripe_payout_id <> p_stripe_payout_id
  ) THEN
    RAISE EXCEPTION 'Transfer déjà lié à un autre payout' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.stripe_transfers st
  SET stripe_payout_id = p_stripe_payout_id
  WHERE st.soignant_id = p_soignant_id
    AND st.stripe_transfer_id = ANY(p_stripe_transfer_ids)
    AND (st.stripe_payout_id IS NULL OR st.stripe_payout_id = p_stripe_payout_id);

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_stripe_lier_payout_transfers(text, uuid, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_stripe_lier_payout_transfers(text, uuid, text[]) TO service_role;

-- Confirme exactement le payout manuel créé pour un escrow. Toutes les écritures
-- (escrow, file, compteur de confiance) sont atomiques et idempotentes.
CREATE OR REPLACE FUNCTION public.fn_escrow_confirmer_payout(
  p_paiement_escrow_id uuid,
  p_stripe_payout_id text,
  p_stripe_account_id text,
  p_paye_le timestamptz DEFAULT now()
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.paiements_escrow%ROWTYPE;
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT pe.*
    INTO v_row
  FROM public.paiements_escrow pe
  JOIN public.stripe_connect_onboarding sco
    ON sco.soignant_id = pe.soignant_id
   AND sco.stripe_account_id = p_stripe_account_id
  WHERE pe.id = p_paiement_escrow_id
    AND pe.stripe_payout_id = p_stripe_payout_id
  FOR UPDATE OF pe;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Payout escrow incohérent' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.statut = 'PAYE' THEN
    RETURN false;
  END IF;

  IF v_row.statut <> 'RELEASE_PLANIFIE' THEN
    RAISE EXCEPTION 'Transition payout escrow invalide depuis %', v_row.statut
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.paiements_escrow
  SET statut = 'PAYE',
      paye_le = COALESCE(p_paye_le, now()),
      erreur = NULL,
      modifie_le = now()
  WHERE id = v_row.id;

  UPDATE public.escrow_release_queue
  SET statut = 'TRAITE',
      traite_le = now(),
      erreur = NULL
  WHERE paiement_escrow_id = v_row.id
    AND statut IN ('EN_COURS', 'EN_ATTENTE');

  PERFORM public.fn_escrow_incrementer_confiance(v_row.etablissement_id);
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_escrow_confirmer_payout(uuid, text, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_escrow_confirmer_payout(uuid, text, text, timestamptz) TO service_role;

-- Un payout peut échouer plusieurs jours après avoir été déclaré paid par Stripe.
-- La transition accepte donc RELEASE_PLANIFIE et PAYE, puis gèle/réinitialise la
-- confiance via la routine d'incident existante.
CREATE OR REPLACE FUNCTION public.fn_escrow_echouer_payout(
  p_paiement_escrow_id uuid,
  p_stripe_payout_id text,
  p_stripe_account_id text,
  p_detail text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.paiements_escrow%ROWTYPE;
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT pe.*
    INTO v_row
  FROM public.paiements_escrow pe
  JOIN public.stripe_connect_onboarding sco
    ON sco.soignant_id = pe.soignant_id
   AND sco.stripe_account_id = p_stripe_account_id
  WHERE pe.id = p_paiement_escrow_id
    AND pe.stripe_payout_id = p_stripe_payout_id
  FOR UPDATE OF pe;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Payout escrow incohérent' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.statut = 'ECHOUE' THEN
    RETURN false;
  END IF;

  IF v_row.statut NOT IN ('RELEASE_PLANIFIE', 'PAYE') THEN
    RAISE EXCEPTION 'Transition échec payout invalide depuis %', v_row.statut
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.fn_escrow_marquer_incident(
    v_row.id,
    'ECHEC',
    left(COALESCE(p_detail, 'payout Stripe échoué'), 500)
  );

  UPDATE public.escrow_release_queue
  SET statut = 'ECHEC',
      traite_le = now(),
      erreur = left(COALESCE(p_detail, 'payout Stripe échoué'), 500)
  WHERE paiement_escrow_id = v_row.id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_escrow_echouer_payout(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_escrow_echouer_payout(uuid, text, text, text) TO service_role;

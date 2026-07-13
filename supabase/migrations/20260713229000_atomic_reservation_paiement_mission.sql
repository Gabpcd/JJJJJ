-- Une autorisation Stripe de commission n'est durable que si la mission est
-- toujours publiable/attribuable au moment où la référence PaymentIntent est
-- enregistrée. Mission et paiement sont verrouillés dans la même transaction.

CREATE OR REPLACE FUNCTION public.fn_enregistrer_reservation_paiement_mission(
  p_mission_id uuid,
  p_etablissement_id uuid,
  p_montant_ht numeric,
  p_montant_tva numeric,
  p_montant_ttc numeric,
  p_stripe_payment_intent_id text,
  p_statut text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_mission record;
  v_paiement public.paiements_mission%ROWTYPE;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_mission_id IS NULL
     OR p_etablissement_id IS NULL
     OR NULLIF(btrim(p_stripe_payment_intent_id), '') IS NULL
     OR p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
     OR p_statut IS NULL
     OR p_statut NOT IN ('EN_ATTENTE', 'AUTORISE', 'ECHOUE')
     OR p_montant_ht IS NULL
     OR p_montant_tva IS NULL
     OR p_montant_ttc IS NULL
     OR p_montant_ht < 0
     OR p_montant_tva < 0
     OR p_montant_ttc <= 0 THEN
    RAISE EXCEPTION 'Réservation de paiement invalide' USING ERRCODE = '22023';
  END IF;

  SELECT m.id, m.etablissement_id, m.statut::text AS statut,
         m.soignant_assigne_id
    INTO v_mission
  FROM public.missions m
  WHERE m.id = p_mission_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_mission.etablissement_id IS DISTINCT FROM p_etablissement_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'MISSION_INTROUVABLE'
    );
  END IF;

  IF v_mission.statut IS DISTINCT FROM 'OUVERTE'
     OR v_mission.soignant_assigne_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'MISSION_STATE_CHANGED'
    );
  END IF;

  SELECT * INTO v_paiement
  FROM public.paiements_mission pm
  WHERE pm.mission_id = p_mission_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_paiement.statut IN ('CAPTURE', 'REMBOURSE') THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'PAIEMENT_TERMINAL_EXISTANT'
      );
    END IF;

    IF v_paiement.statut = 'AUTORISE'
       AND (
         v_paiement.stripe_payment_intent_id IS DISTINCT FROM p_stripe_payment_intent_id
         OR p_statut <> 'AUTORISE'
       ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'PAIEMENT_AUTORISE_EXISTANT'
      );
    END IF;

    UPDATE public.paiements_mission
    SET etablissement_id = p_etablissement_id,
        montant_ht = p_montant_ht,
        montant_tva = p_montant_tva,
        montant_ttc = p_montant_ttc,
        stripe_payment_intent_id = btrim(p_stripe_payment_intent_id),
        statut = p_statut
    WHERE id = v_paiement.id;
  ELSE
    INSERT INTO public.paiements_mission (
      mission_id,
      etablissement_id,
      montant_ht,
      montant_tva,
      montant_ttc,
      stripe_payment_intent_id,
      statut
    ) VALUES (
      p_mission_id,
      p_etablissement_id,
      p_montant_ht,
      p_montant_tva,
      p_montant_ttc,
      btrim(p_stripe_payment_intent_id),
      p_statut
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'stripe_payment_intent_id', btrim(p_stripe_payment_intent_id),
    'statut', p_statut
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_enregistrer_reservation_paiement_mission(
  uuid, uuid, numeric, numeric, numeric, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_enregistrer_reservation_paiement_mission(
  uuid, uuid, numeric, numeric, numeric, text, text
) TO service_role;

-- La protection UI ne suffit pas : toute porte d'attribution (candidature,
-- proposition directe ou affectation) doit refuser une mission financée par
-- réservation Stripe tant que l'autorisation n'est pas durablement confirmée.
CREATE OR REPLACE FUNCTION public.fn_exiger_reservation_avant_attribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_mode text;
  v_paiement public.paiements_mission%ROWTYPE;
BEGIN
  IF NEW.statut IS DISTINCT FROM 'ASSIGNEE'
     OR OLD.statut IS NOT DISTINCT FROM 'ASSIGNEE' THEN
    RETURN NEW;
  END IF;

  SELECT e.mode_paiement_commission
    INTO v_mode
  FROM public.etablissements e
  WHERE e.id = NEW.etablissement_id;

  IF v_mode IS DISTINCT FROM 'STRIPE_RESERVATION'
     OR COALESCE(NEW.montant_commission_ttc, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_paiement
  FROM public.paiements_mission pm
  WHERE pm.mission_id = NEW.id
  FOR UPDATE;

  IF NOT FOUND
     OR v_paiement.etablissement_id IS DISTINCT FROM NEW.etablissement_id
     OR v_paiement.stripe_payment_intent_id IS NULL
     OR v_paiement.statut NOT IN ('AUTORISE', 'CAPTURE')
     OR v_paiement.montant_ttc IS DISTINCT FROM NEW.montant_commission_ttc THEN
    RAISE EXCEPTION 'Autorisation Stripe requise avant attribution de la mission'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_exiger_reservation_avant_attribution()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_exiger_reservation_avant_attribution()
TO service_role;

DROP TRIGGER IF EXISTS trg_exiger_reservation_avant_attribution
ON public.missions;
CREATE TRIGGER trg_exiger_reservation_avant_attribution
BEFORE UPDATE OF statut, soignant_assigne_id ON public.missions
FOR EACH ROW
WHEN (
  NEW.statut = 'ASSIGNEE'::public.statut_mission
  AND OLD.statut IS DISTINCT FROM 'ASSIGNEE'::public.statut_mission
)
EXECUTE FUNCTION public.fn_exiger_reservation_avant_attribution();

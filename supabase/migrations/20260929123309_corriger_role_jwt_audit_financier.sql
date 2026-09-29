-- Définitions live prod et staging identiques, relues le 29/09/2026.
-- Corriger uniquement la lecture du rôle signé, sans changer les transitions,
-- les identités financières ni les ACL. Repli legacy conservé.

-- Définition avant correction : 2779c2523a80bdc4fe62bf60185882cb
CREATE OR REPLACE FUNCTION public.fn_ecrire_audit_safe(p_acteur_id uuid, p_type_acteur text, p_action text, p_type_ressource text, p_id_ressource uuid, p_cle_s3 text DEFAULT NULL::text, p_details jsonb DEFAULT NULL::jsonb, p_ip inet DEFAULT NULL::inet, p_navigateur text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_uid uuid := auth.uid();
  v_is_service boolean := COALESCE(NULLIF(auth.jwt()->>'role', ''), NULLIF(current_setting('request.jwt.claim.role', true), ''), '') = 'service_role';
  v_acteur_id uuid := p_acteur_id;
BEGIN
  -- Iter3 sec fix : empêcher impersonation cross-user dans audit log
  IF NOT v_is_service AND NOT est_admin() THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
    END IF;
    v_acteur_id := v_uid;
  END IF;

  -- FIX 05/07/2026 (recette escrow) : les colonnes s'appellent ip_acteur,
  -- navigateur_acteur, cle_s3_ressource — l'INSERT historique visait ip,
  -- navigateur, cle_s3 (inexistantes) → échec 100 % avalé par le catch.
  INSERT INTO journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details, ip_acteur, navigateur_acteur
  ) VALUES (
    v_acteur_id, p_type_acteur, p_action, p_type_ressource, p_id_ressource,
    p_cle_s3, p_details, p_ip, p_navigateur
  ) RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$
;

-- Définition avant correction : 38a9313a704880de64c898926fbb0d2c
CREATE OR REPLACE FUNCTION public.fn_escrow_confirmer_payout(p_paiement_escrow_id uuid, p_stripe_payout_id text, p_stripe_account_id text, p_paye_le timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.paiements_escrow%ROWTYPE;
BEGIN
  IF COALESCE(NULLIF(auth.jwt()->>'role', ''), NULLIF(current_setting('request.jwt.claim.role', true), ''), '') <> 'service_role' THEN
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
$function$
;

-- Définition avant correction : 4f054e7e0f3516fa0a659b80c0da1e5b
CREATE OR REPLACE FUNCTION public.fn_escrow_echouer_payout(p_paiement_escrow_id uuid, p_stripe_payout_id text, p_stripe_account_id text, p_detail text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.paiements_escrow%ROWTYPE;
BEGIN
  IF COALESCE(NULLIF(auth.jwt()->>'role', ''), NULLIF(current_setting('request.jwt.claim.role', true), ''), '') <> 'service_role' THEN
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
$function$
;

-- Définition avant correction : ac87b3689bff84cc6128e78abfa0c2dc
CREATE OR REPLACE FUNCTION public.fn_stripe_lier_payout_transfers(p_stripe_payout_id text, p_soignant_id uuid, p_stripe_transfer_ids text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_updated integer := 0;
BEGIN
  IF COALESCE(NULLIF(auth.jwt()->>'role', ''), NULLIF(current_setting('request.jwt.claim.role', true), ''), '') <> 'service_role' THEN
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
$function$
;

UPDATE private.security_definer_inventory i
SET definition_md5=md5(p.prosrc), recense_le=now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('fn_ecrire_audit_safe','fn_escrow_confirmer_payout','fn_escrow_echouer_payout','fn_stripe_lier_payout_transfers')
  AND i.signature=p.oid::regprocedure::text;

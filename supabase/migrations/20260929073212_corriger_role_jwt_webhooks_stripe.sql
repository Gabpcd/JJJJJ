-- Définitions relues en production et staging le 29/09/2026 (identiques).
-- PostgREST transmet le rôle dans request.jwt.claims. Préserver le repli legacy,
-- mais un rôle JSON présent reste prioritaire. Ne jamais lire user_metadata.

CREATE OR REPLACE FUNCTION public.fn_stripe_webhook_event_claim(p_event_id text, p_event_type text, p_payload jsonb, p_source_webhook text, p_livemode boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_stripe_webhook_event_is_new(p_event_id text, p_event_type text, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (est_admin() OR COALESCE(NULLIF(auth.jwt()->>'role', ''), NULLIF(current_setting('request.jwt.claim.role', true), ''), '') = 'service_role') THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.stripe_webhook_events (event_id, event_type, payload)
  VALUES (p_event_id, p_event_type, p_payload)
  ON CONFLICT (event_id) DO NOTHING;

  -- TRUE tant que l'event n'a PAS été traité avec succès (traite_le IS NULL) :
  -- couvre le nouvel event ET le retry Stripe d'un event qui avait échoué.
  -- FALSE seulement si déjà traité avec succès → idempotence.
  -- (Avant : « AND recu_le > NOW() - INTERVAL '1 minute' » faisait que tout retry
  -- Stripe arrivant >1 min après l'échec initial était faussement considéré
  -- « déjà traité » → l'edge renvoyait 200, Stripe arrêtait de réessayer, et le
  -- webhook en échec était définitivement perdu.)
  RETURN EXISTS (
    SELECT 1 FROM public.stripe_webhook_events
    WHERE event_id = p_event_id AND traite_le IS NULL
  );
END;
$function$;

UPDATE private.security_definer_inventory i
SET definition_md5=md5(p.prosrc), recense_le=now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND ((i.signature='fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)'
    AND p.oid='public.fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)'::regprocedure)
    OR (i.signature='fn_stripe_webhook_event_is_new(text,text,jsonb)'
    AND p.oid='public.fn_stripe_webhook_event_is_new(text,text,jsonb)'::regprocedure));

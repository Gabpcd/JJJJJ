-- Fix idempotence webhook Stripe : un webhook EN ÉCHEC re-livré par Stripe après
-- plus d'1 minute était définitivement perdu.
--
-- Cycle de vie (supabase/functions/stripe-webhook) :
--   1. fn_stripe_webhook_event_is_new insère la row (traite_le = NULL).
--   2. succès du traitement → traite_le = now() ; échec → traite_le reste NULL,
--      l'edge renvoie 500 → Stripe RÉESSAYE (backoff de plusieurs minutes).
--   3. au retry, is_new est rappelé.
--
-- Bug : l'ancien `RETURN EXISTS(... traite_le IS NULL AND recu_le > NOW() - '1 min')`
-- renvoyait FALSE dès que le retry arrivait >1 min après l'échec initial → l'edge
-- renvoyait 200 « already_processed » → Stripe arrêtait de réessayer → l'event
-- (un paiement !) était perdu sans jamais avoir été traité avec succès.
--
-- Fix : on traite tant que l'event n'a pas été traité AVEC SUCCÈS (traite_le IS NULL),
-- quel que soit l'âge. FALSE seulement si déjà traité → idempotence préservée.
-- Couvre le nouvel event ET le retry d'un échec.
--
-- Déjà appliqué + vérifié en prod (table stripe_webhook_events vide : 0 paiement
-- réel à ce stade — aucun risque sur des données existantes).

CREATE OR REPLACE FUNCTION public.fn_stripe_webhook_event_is_new(p_event_id text, p_event_type text, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.stripe_webhook_events (event_id, event_type, payload)
  VALUES (p_event_id, p_event_type, p_payload)
  ON CONFLICT (event_id) DO NOTHING;

  -- TRUE tant que l'event n'a PAS été traité avec succès (nouvel event OU retry
  -- d'un échec, quel que soit l'âge). FALSE seulement si déjà traité → idempotence.
  RETURN EXISTS (
    SELECT 1 FROM public.stripe_webhook_events
    WHERE event_id = p_event_id AND traite_le IS NULL
  );
END;
$function$;

-- Itération 4 — Fix S5 idempotence webhook Stripe
-- Risque : Stripe peut renvoyer le même webhook 2x (retry, duplicate, etc.)
-- Sans UNIQUE sur stripe_payment_intent_id, lookup matching peut faire double-update.
-- Sans table d'events, pas de garde stricte event_id.

-- 1) UNIQUE INDEX partial sur factures_honoraires.stripe_payment_intent_id
CREATE UNIQUE INDEX IF NOT EXISTS uniq_factures_honoraires_stripe_pi
  ON public.factures_honoraires(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- 2) UNIQUE INDEX partial sur paiements_mission.stripe_payment_intent_id
CREATE UNIQUE INDEX IF NOT EXISTS uniq_paiements_mission_stripe_pi
  ON public.paiements_mission(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- 3) Table stripe_webhook_events pour idempotence stricte par event.id
CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
  event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  recu_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  traite_le TIMESTAMPTZ,
  erreur TEXT,
  payload JSONB
);

ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_stripe_webhook_events_admin ON public.stripe_webhook_events;
CREATE POLICY pol_stripe_webhook_events_admin ON public.stripe_webhook_events
  FOR ALL USING (est_admin()) WITH CHECK (est_admin());

GRANT SELECT, INSERT, UPDATE ON public.stripe_webhook_events TO service_role;

-- 4) Helper RPC pour idempotence : retourne true si l'event est nouveau (à traiter)
-- Le webhook stripe-webhook/index.ts pourra appeler en début de fn :
--   if (!await rpc('fn_stripe_webhook_event_is_new', { p_event_id: event.id, p_event_type: event.type })) return 200;
CREATE OR REPLACE FUNCTION public.fn_stripe_webhook_event_is_new(p_event_id TEXT, p_event_type TEXT, p_payload JSONB DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.stripe_webhook_events (event_id, event_type, payload)
  VALUES (p_event_id, p_event_type, p_payload)
  ON CONFLICT (event_id) DO NOTHING;

  -- TRUE si l'INSERT a ajouté la row (= nouvel event)
  RETURN EXISTS (
    SELECT 1 FROM public.stripe_webhook_events
    WHERE event_id = p_event_id AND traite_le IS NULL AND recu_le > NOW() - INTERVAL '1 minute'
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_stripe_webhook_event_is_new(TEXT, TEXT, JSONB) TO service_role;

NOTIFY pgrst, 'reload schema';

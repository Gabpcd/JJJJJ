-- Swan envoie une enveloppe minimale et peut livrer le même eventId plusieurs
-- fois. Le journal ci-dessous est la seule source de déduplication. Il ne
-- contient ni IBAN, ni nom de contrepartie, ni référence bancaire.
CREATE TABLE IF NOT EXISTS public.swan_webhook_events (
  event_id text PRIMARY KEY,
  event_type text NOT NULL,
  resource_id text NOT NULL,
  project_id text NOT NULL,
  statut text NOT NULL DEFAULT 'RECU',
  tentatives integer NOT NULL DEFAULT 0,
  recu_le timestamptz NOT NULL DEFAULT now(),
  traitement_commence_le timestamptz,
  traite_le timestamptz,
  derniere_erreur text,
  transaction_snapshot jsonb,
  CONSTRAINT swan_webhook_events_statut_check
    CHECK (statut IN ('RECU', 'PROCESSING', 'TRAITE', 'IGNORE', 'ERREUR')),
  CONSTRAINT swan_webhook_events_tentatives_check
    CHECK (tentatives >= 0 AND tentatives <= 1000),
  CONSTRAINT swan_webhook_events_type_check
    CHECK (length(event_type) BETWEEN 1 AND 100),
  CONSTRAINT swan_webhook_events_event_id_check
    CHECK (
      length(event_id) BETWEEN 1 AND 200
      AND event_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
    ),
  CONSTRAINT swan_webhook_events_resource_id_check
    CHECK (
      length(resource_id) BETWEEN 1 AND 200
      AND resource_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
    ),
  CONSTRAINT swan_webhook_events_project_id_check
    CHECK (
      length(project_id) BETWEEN 1 AND 200
      AND project_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
    ),
  CONSTRAINT swan_webhook_events_snapshot_object_check
    CHECK (transaction_snapshot IS NULL OR jsonb_typeof(transaction_snapshot) = 'object')
);

ALTER TABLE public.swan_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swan_webhook_events FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.swan_webhook_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.swan_webhook_events TO service_role;

CREATE INDEX IF NOT EXISTS idx_swan_webhook_events_statut_recu
  ON public.swan_webhook_events (statut, recu_le)
  WHERE statut IN ('RECU', 'PROCESSING', 'ERREUR');

CREATE OR REPLACE FUNCTION public.fn_swan_webhook_reclamer(
  p_event_id text,
  p_event_type text,
  p_resource_id text,
  p_project_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_event public.swan_webhook_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_resource_id IS NULL OR p_project_id IS NULL
     OR p_event_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
     OR p_resource_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
     OR p_project_id !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'
     OR NULLIF(btrim(p_event_type), '') IS NULL OR length(p_event_type) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ENVELOPPE_INVALIDE');
  END IF;

  INSERT INTO public.swan_webhook_events (
    event_id, event_type, resource_id, project_id
  ) VALUES (
    p_event_id, btrim(p_event_type), p_resource_id, p_project_id
  ) ON CONFLICT (event_id) DO NOTHING;

  SELECT * INTO v_event
  FROM public.swan_webhook_events
  WHERE event_id = p_event_id
  FOR UPDATE;

  -- Un eventId ne peut jamais être réutilisé avec une autre enveloppe.
  IF v_event.event_type IS DISTINCT FROM btrim(p_event_type)
     OR v_event.resource_id IS DISTINCT FROM p_resource_id
     OR v_event.project_id IS DISTINCT FROM p_project_id THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EVENT_ID_REUTILISE');
  END IF;

  IF v_event.statut IN ('TRAITE', 'IGNORE') THEN
    RETURN jsonb_build_object('success', true, 'claim', 'DEJA_TRAITE', 'statut', v_event.statut);
  END IF;

  IF v_event.statut = 'PROCESSING'
     AND v_event.traitement_commence_le > now() - interval '2 minutes' THEN
    RETURN jsonb_build_object('success', true, 'claim', 'EN_COURS');
  END IF;

  UPDATE public.swan_webhook_events
  SET statut = 'PROCESSING',
      tentatives = tentatives + 1,
      traitement_commence_le = now(),
      derniere_erreur = NULL
  WHERE event_id = p_event_id;

  RETURN jsonb_build_object('success', true, 'claim', 'ACQUIS');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_swan_webhook_reclamer(text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_swan_webhook_reclamer(text, text, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_swan_webhook_finaliser(
  p_event_id text,
  p_statut text,
  p_transaction_snapshot jsonb DEFAULT NULL,
  p_error_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_snapshot_keys text[];
BEGIN
  IF p_statut NOT IN ('TRAITE', 'IGNORE', 'ERREUR') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'STATUT_INVALIDE');
  END IF;
  IF p_transaction_snapshot IS NOT NULL THEN
    IF jsonb_typeof(p_transaction_snapshot) <> 'object' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'SNAPSHOT_INVALIDE');
    END IF;
    SELECT array_agg(key ORDER BY key) INTO v_snapshot_keys
    FROM jsonb_object_keys(p_transaction_snapshot) AS key;
    IF NOT COALESCE(
      v_snapshot_keys <@ ARRAY[
        'account_id_matches', 'amount_cents', 'currency', 'event_status_matches',
        'id', 'status', 'type'
      ]::text[],
      true
    ) THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'SNAPSHOT_CHAMP_INTERDIT');
    END IF;
  END IF;

  UPDATE public.swan_webhook_events
  SET statut = p_statut,
      transaction_snapshot = p_transaction_snapshot,
      derniere_erreur = CASE
        WHEN p_statut = 'ERREUR' THEN left(COALESCE(NULLIF(btrim(p_error_code), ''), 'ERREUR_INCONNUE'), 200)
        ELSE NULL
      END,
      traite_le = CASE WHEN p_statut IN ('TRAITE', 'IGNORE') THEN now() ELSE NULL END
  WHERE event_id = p_event_id
    AND statut = 'PROCESSING';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CLAIM_ABSENT');
  END IF;
  RETURN jsonb_build_object('success', true, 'statut', p_statut);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_swan_webhook_finaliser(text, text, jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_swan_webhook_finaliser(text, text, jsonb, text)
  TO service_role;

COMMENT ON TABLE public.swan_webhook_events IS
  'Journal idempotent des enveloppes Swan. Aucune coordonnée bancaire ni identité de contrepartie.';

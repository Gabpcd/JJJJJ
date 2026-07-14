-- Verrou atomique multi-ressource entre les trois flux susceptibles d'encaisser
-- une même facture/mission : Checkout, prélèvement SEPA et Checkout Connect.
-- Une facture agrégée revendique aussi toutes les missions qui la référencent.

CREATE TABLE IF NOT EXISTS public.stripe_payment_flow_claims (
  resource_key text PRIMARY KEY,
  flow text NOT NULL CHECK (flow IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION', 'LEGACY_UNKNOWN')),
  owner_token text NOT NULL CHECK (length(owner_token) > 0),
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT stripe_payment_flow_claims_resource_key_check
    CHECK (resource_key ~ '^(FACTURE|MISSION):[0-9a-f-]{36}$')
);

CREATE INDEX IF NOT EXISTS idx_stripe_payment_flow_claims_session
  ON public.stripe_payment_flow_claims (stripe_checkout_session_id)
  WHERE stripe_checkout_session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stripe_payment_flow_claims_intent
  ON public.stripe_payment_flow_claims (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

ALTER TABLE public.stripe_payment_flow_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_payment_flow_claims FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.stripe_payment_flow_claims FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stripe_payment_flow_claims TO service_role;

COMMENT ON TABLE public.stripe_payment_flow_claims IS
  'Verrou financier durable multi-ressource facture/mission pour Checkout, SEPA et Connect.';

CREATE OR REPLACE FUNCTION public.fn_stripe_payment_flow_claim(
  p_flow text,
  p_owner_token text,
  p_facture_id uuid DEFAULT NULL,
  p_mission_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
  IF p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION')
     OR NULLIF(btrim(p_owner_token), '') IS NULL
     OR ((p_facture_id IS NULL) = (p_mission_id IS NULL)) THEN
    RAISE EXCEPTION 'Paramètres de claim Stripe invalides' USING ERRCODE = '22023';
  END IF;

  IF p_facture_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.factures f
      WHERE f.id = p_facture_id AND f.type_document = 'FACTURE' AND f.statut <> 'ANNULEE'
    ) THEN
      RAISE EXCEPTION 'Facture de claim introuvable ou non payable' USING ERRCODE = 'P0002';
    END IF;
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
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.missions m WHERE m.id = p_mission_id) THEN
      RAISE EXCEPTION 'Mission de claim introuvable' USING ERRCODE = 'P0002';
    END IF;
    v_resources := ARRAY['MISSION:' || p_mission_id::text];
  END IF;

  -- Toutes les fonctions prennent les verrous dans le même ordre lexical.
  -- Une facture agrégée et deux missions concurrentes ne peuvent donc ni se
  -- doubler, ni se deadlocker entre les inserts de claims.
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

  -- Si de nouvelles missions ont été rattachées à une facture après le bind,
  -- leurs claims viennent d'être insérés sans identifiant. Propager l'unique
  -- Session/PI existant garde toutes les ressources réconciliables et libérables
  -- par le même CAS.
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

REVOKE ALL ON FUNCTION public.fn_stripe_payment_flow_claim(text, text, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_payment_flow_claim(text, text, uuid, uuid) TO service_role;

-- Reprise contrôlée des factures historiques. Cette RPC ne devine jamais le
-- flux d'un paiement : l'Edge Function doit d'abord relire Stripe et vérifier
-- l'identité complète de la Session/du PaymentIntent (facture, établissement,
-- Customer, montant et devise). La RPC ne fait ensuite que le CAS atomique des
-- claims LEGACY_UNKNOWN vers le flux ainsi prouvé.
CREATE OR REPLACE FUNCTION public.fn_stripe_payment_flow_adopter_legacy(
  p_flow text,
  p_owner_token text,
  p_facture_id uuid,
  p_stripe_checkout_session_id text DEFAULT NULL,
  p_stripe_payment_intent_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_resources text[];
  v_resource text;
  v_stripe_lock_keys text[];
  v_legacy_owner_token text := 'legacy:' || p_facture_id::text;
  v_facture_payment_intent_id text;
  v_etablissement_id uuid;
  v_conflict public.stripe_payment_flow_claims%ROWTYPE;
  v_session_ids text[];
  v_intent_ids text[];
  v_legacy_count integer;
  v_desired_count integer;
  v_claim_count integer;
  v_audit jsonb;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  IF p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE')
     OR NULLIF(btrim(p_owner_token), '') IS NULL
     OR p_facture_id IS NULL
     OR (p_stripe_checkout_session_id IS NULL AND p_stripe_payment_intent_id IS NULL)
     OR (
       p_flow = 'SEPA_INVOICE'
       AND (
         p_stripe_checkout_session_id IS NOT NULL
         OR p_stripe_payment_intent_id IS NULL
       )
     )
     OR (
       p_stripe_checkout_session_id IS NOT NULL
       AND p_stripe_checkout_session_id !~ '^cs_(test|live)_[A-Za-z0-9]+$'
     )
     OR (
       p_stripe_payment_intent_id IS NOT NULL
       AND p_stripe_payment_intent_id !~ '^pi_[A-Za-z0-9]+$'
     ) THEN
    RAISE EXCEPTION 'Paramètres d''adoption Stripe legacy invalides' USING ERRCODE = '22023';
  END IF;

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

  FOREACH v_resource IN ARRAY v_resources LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(v_resource, 0));
  END LOOP;

  SELECT array_agg(lock_key ORDER BY lock_key)
  INTO v_stripe_lock_keys
  FROM unnest(ARRAY[
    CASE
      WHEN p_stripe_checkout_session_id IS NOT NULL
      THEN 'STRIPE_SESSION:' || p_stripe_checkout_session_id
    END,
    CASE
      WHEN p_stripe_payment_intent_id IS NOT NULL
      THEN 'STRIPE_INTENT:' || p_stripe_payment_intent_id
    END
  ]) AS locks(lock_key)
  WHERE lock_key IS NOT NULL;
  FOREACH v_resource IN ARRAY v_stripe_lock_keys LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(v_resource, 0));
  END LOOP;

  SELECT f.stripe_payment_intent_id, f.etablissement_id
  INTO v_facture_payment_intent_id, v_etablissement_id
  FROM public.factures f
  WHERE f.id = p_facture_id
    AND f.type_document = 'FACTURE'
    AND f.statut <> 'ANNULEE'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture legacy introuvable ou non payable' USING ERRCODE = 'P0002';
  END IF;
  IF v_facture_payment_intent_id IS NOT NULL
     AND v_facture_payment_intent_id IS DISTINCT FROM p_stripe_payment_intent_id THEN
    RAISE EXCEPTION 'PaymentIntent Stripe legacy différent de la facture' USING ERRCODE = '23514';
  END IF;

  -- Toute collision Connect, tout autre flux, ou même un owner legacy qui ne
  -- correspond pas exactement à la facture bloque l'adoption.
  SELECT c.*
  INTO v_conflict
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources)
    AND NOT (
      (c.flow = 'LEGACY_UNKNOWN' AND c.owner_token = v_legacy_owner_token)
      OR (c.flow = p_flow AND c.owner_token = p_owner_token)
    )
  ORDER BY c.resource_key
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Claim Stripe concurrent incompatible: %', v_conflict.resource_key
      USING ERRCODE = '40001';
  END IF;

  SELECT c.*
  INTO v_conflict
  FROM public.stripe_payment_flow_claims c
  WHERE (
      (
        p_stripe_checkout_session_id IS NOT NULL
        AND c.stripe_checkout_session_id = p_stripe_checkout_session_id
      )
      OR (
        p_stripe_payment_intent_id IS NOT NULL
        AND c.stripe_payment_intent_id = p_stripe_payment_intent_id
      )
    )
    AND NOT (
      (c.flow = 'LEGACY_UNKNOWN' AND c.owner_token = v_legacy_owner_token)
      OR (c.flow = p_flow AND c.owner_token = p_owner_token)
    )
  ORDER BY c.resource_key
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Objet Stripe déjà revendiqué par un autre paiement: %', v_conflict.resource_key
      USING ERRCODE = '23505';
  END IF;

  SELECT
    count(*) FILTER (
      WHERE c.flow = 'LEGACY_UNKNOWN' AND c.owner_token = v_legacy_owner_token
    ),
    count(*) FILTER (
      WHERE c.flow = p_flow AND c.owner_token = p_owner_token
    ),
    count(*),
    array_agg(DISTINCT c.stripe_checkout_session_id)
      FILTER (WHERE c.stripe_checkout_session_id IS NOT NULL),
    array_agg(DISTINCT c.stripe_payment_intent_id)
      FILTER (WHERE c.stripe_payment_intent_id IS NOT NULL)
  INTO
    v_legacy_count,
    v_desired_count,
    v_claim_count,
    v_session_ids,
    v_intent_ids
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources);

  IF v_legacy_count = 0 AND v_desired_count = 0 THEN
    RAISE EXCEPTION 'Aucun claim Stripe legacy à adopter' USING ERRCODE = 'P0002';
  END IF;
  IF COALESCE(array_length(v_session_ids, 1), 0) > 1
     OR COALESCE(array_length(v_intent_ids, 1), 0) > 1 THEN
    RAISE EXCEPTION 'Claims Stripe legacy incohérents' USING ERRCODE = '23514';
  END IF;
  IF COALESCE(array_length(v_session_ids, 1), 0) = 1
     AND v_session_ids[1] IS DISTINCT FROM p_stripe_checkout_session_id THEN
    RAISE EXCEPTION 'Checkout Session legacy différente de la preuve Stripe' USING ERRCODE = '23514';
  END IF;
  IF COALESCE(array_length(v_intent_ids, 1), 0) = 1
     AND v_intent_ids[1] IS DISTINCT FROM p_stripe_payment_intent_id THEN
    RAISE EXCEPTION 'PaymentIntent legacy différent de la preuve Stripe' USING ERRCODE = '23514';
  END IF;

  UPDATE public.stripe_payment_flow_claims c
  SET
    flow = p_flow,
    owner_token = p_owner_token,
    stripe_checkout_session_id = p_stripe_checkout_session_id,
    stripe_payment_intent_id = p_stripe_payment_intent_id,
    modifie_le = now()
  WHERE c.resource_key = ANY(v_resources)
    AND (
      (c.flow = 'LEGACY_UNKNOWN' AND c.owner_token = v_legacy_owner_token)
      OR (c.flow = p_flow AND c.owner_token = p_owner_token)
    );

  INSERT INTO public.stripe_payment_flow_claims (
    resource_key,
    flow,
    owner_token,
    stripe_checkout_session_id,
    stripe_payment_intent_id
  )
  SELECT
    r.resource_key,
    p_flow,
    p_owner_token,
    p_stripe_checkout_session_id,
    p_stripe_payment_intent_id
  FROM unnest(v_resources) AS r(resource_key)
  ON CONFLICT (resource_key) DO NOTHING;

  SELECT count(*)
  INTO v_claim_count
  FROM public.stripe_payment_flow_claims c
  WHERE c.resource_key = ANY(v_resources)
    AND c.flow = p_flow
    AND c.owner_token = p_owner_token
    AND c.stripe_checkout_session_id IS NOT DISTINCT FROM p_stripe_checkout_session_id
    AND c.stripe_payment_intent_id IS NOT DISTINCT FROM p_stripe_payment_intent_id;

  IF v_claim_count <> cardinality(v_resources) THEN
    RAISE EXCEPTION 'Adoption Stripe legacy non atomique' USING ERRCODE = '40001';
  END IF;

  v_audit := public.fn_ecrire_audit_safe(
    v_etablissement_id,
    'SYSTEME',
    'ADMIN_ACTION',
    'facture',
    p_facture_id,
    NULL,
    jsonb_build_object(
      'evenement', 'FACTURE_LEGACY_STRIPE_ADOPTEE',
      'flow', p_flow,
      'stripe_session_id', p_stripe_checkout_session_id,
      'stripe_payment_intent_id', p_stripe_payment_intent_id,
      'adoption_effective', v_legacy_count > 0
    ),
    NULL,
    'fn_stripe_payment_flow_adopter_legacy'
  );
  IF COALESCE(v_audit @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Audit adoption Stripe legacy non écrit';
  END IF;

  RETURN jsonb_build_object(
    'adopted', v_legacy_count > 0,
    'flow', p_flow,
    'owner_token', p_owner_token,
    'resources', v_resources,
    'stripe_checkout_session_id', p_stripe_checkout_session_id,
    'stripe_payment_intent_id', p_stripe_payment_intent_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_stripe_payment_flow_adopter_legacy(text, text, uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_payment_flow_adopter_legacy(text, text, uuid, text, text)
  TO service_role;

-- Backfill prioritaire des paiements Connect non terminés/remboursés.
INSERT INTO public.stripe_payment_flow_claims (
  resource_key, flow, owner_token, stripe_checkout_session_id, stripe_payment_intent_id, cree_le, modifie_le
)
SELECT DISTINCT ON (st.mission_id)
  'MISSION:' || st.mission_id::text,
  'CONNECT_MISSION',
  'connect:' || st.mission_id::text,
  st.stripe_checkout_session_id,
  st.stripe_payment_intent_id,
  COALESCE(st.cree_le, now()),
  now()
FROM public.stripe_transfers st
WHERE st.statut NOT IN ('REMBOURSE', 'ANNULEE')
ORDER BY st.mission_id, st.cree_le DESC NULLS LAST
ON CONFLICT (resource_key) DO NOTHING;

-- Backfill des factures déjà revendiquées. Une collision avec Connect reste
-- volontairement au bénéfice du claim Connect, qui couvre le montant groupé.
WITH invoice_claims AS (
  SELECT
    f.id AS facture_id,
    f.mission_id,
    'LEGACY_UNKNOWN'::text AS flow,
    'legacy:' || f.id::text AS owner_token,
    f.stripe_payment_intent_id,
    COALESCE(f.cree_le, now()) AS cree_le
  FROM public.factures f
  WHERE f.type_document = 'FACTURE'
    AND f.statut <> 'ANNULEE'
    AND (f.stripe_payment_intent_id IS NOT NULL OR f.stripe_hosted_url IS NOT NULL)
)
INSERT INTO public.stripe_payment_flow_claims (
  resource_key, flow, owner_token, stripe_payment_intent_id, cree_le, modifie_le
)
SELECT
  'FACTURE:' || facture_id::text,
  flow,
  owner_token,
  stripe_payment_intent_id,
  cree_le,
  now()
FROM invoice_claims
ON CONFLICT (resource_key) DO NOTHING;

WITH invoice_claims AS (
  SELECT
    f.id AS facture_id,
    'LEGACY_UNKNOWN'::text AS flow,
    'legacy:' || f.id::text AS owner_token,
    f.stripe_payment_intent_id,
    COALESCE(f.cree_le, now()) AS cree_le
  FROM public.factures f
  WHERE f.type_document = 'FACTURE'
    AND f.statut <> 'ANNULEE'
    AND (f.stripe_payment_intent_id IS NOT NULL OR f.stripe_hosted_url IS NOT NULL)
), linked_missions AS (
  SELECT ic.*, f.mission_id AS mission_id
  FROM invoice_claims ic
  JOIN public.factures f ON f.id = ic.facture_id
  WHERE f.mission_id IS NOT NULL
  UNION
  SELECT ic.*, m.id AS mission_id
  FROM invoice_claims ic
  JOIN public.missions m ON m.facture_id = ic.facture_id
)
INSERT INTO public.stripe_payment_flow_claims (
  resource_key, flow, owner_token, stripe_payment_intent_id, cree_le, modifie_le
)
SELECT
  'MISSION:' || mission_id::text,
  flow,
  owner_token,
  stripe_payment_intent_id,
  cree_le,
  now()
FROM linked_missions
ON CONFLICT (resource_key) DO NOTHING;

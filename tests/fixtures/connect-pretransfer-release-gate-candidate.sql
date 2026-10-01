-- CANDIDAT SOURCE NON EXECUTE. Barrière fermée ; aucune RPC d'ouverture.
-- À composer atomiquement avec le moteur candidat avant son COMMIT final,
-- après son préflight des anciennes dépendances ; pas un déploiement isolé.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
SET LOCAL search_path=public,pg_temp;
DO $barrier_preflight$
DECLARE v_expected record; v_proc record;
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::int/10000<>17 THEN
   RAISE EXCEPTION 'CONNECT_BARRIER_CONTEXT';
 END IF;
 IF to_regclass('private.stripe_connect_release_gate') IS NOT NULL
   OR to_regtype('private.stripe_connect_release_gate') IS NOT NULL
   OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname IN('fn_stripe_payment_flow_claim_connect_v1','fn_stripe_webhook_event_claim_connect_v1'))
   OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature IN(
     'fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)','public.fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)',
     'fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)','public.fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)')) THEN
   RAISE EXCEPTION 'CONNECT_BARRIER_OBJECT_EXISTS';
 END IF;
 FOR v_expected IN SELECT * FROM (VALUES
    ('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','4506013ff5a5c0df5761523a221d8977','82f09bcf1334fb9041ae9a1628e4cd42','search_path=public, pg_temp','jsonb'),
    ('fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','c7b1356e671f49a19bf98cedf75f8249','9a50b2ad4d79d26e7244bb8e22cf0b85','search_path=public','text')) AS x(signature,corps,definition,configuration,resultat) LOOP
   SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('public.'||v_expected.signature);
   IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
     OR md5(pg_get_functiondef(v_proc.oid)) IS DISTINCT FROM v_expected.definition
     OR pg_get_userbyid(v_proc.proowner)<>'postgres' OR v_proc.prosecdef IS DISTINCT FROM TRUE
     OR v_proc.provolatile<>'v' OR v_proc.lanname<>'plpgsql' OR v_proc.prokind<>'f'
     OR pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.resultat
     OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_expected.configuration]::text[]
     OR v_proc.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
     RAISE EXCEPTION 'CONNECT_BARRIER_DEPENDENCY (%)',v_expected.signature;
   END IF;
   -- Absence actuellement observée ou entrée exacte ; aucune entrée contradictoire normalisée.
   IF EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature='public.'||v_expected.signature)
     OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=v_expected.signature
       AND (categorie IS DISTINCT FROM 'SERVICE_ONLY_REVOQUE' OR definition_md5 IS DISTINCT FROM v_expected.corps)) THEN
     RAISE EXCEPTION 'CONNECT_BARRIER_INVENTORY (%)',v_expected.signature;
   END IF;
 END LOOP;
END;
$barrier_preflight$;

CREATE TABLE private.stripe_connect_release_gate (
 protocol text PRIMARY KEY CHECK(protocol='CONNECT_PRETRANSFER_V1'),
 enabled boolean NOT NULL DEFAULT false,
 installed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.stripe_connect_release_gate ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.stripe_connect_release_gate FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO private.stripe_connect_release_gate(protocol,enabled) VALUES('CONNECT_PRETRANSFER_V1',false);

CREATE OR REPLACE FUNCTION "public"."fn_stripe_payment_flow_claim"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid" DEFAULT NULL::"uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
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
  IF p_flow IN ('CONNECT_MISSION','CONNECT_INVOICE') THEN
    RAISE EXCEPTION 'CONNECT_CLIENT_VERSION_REQUIRED' USING ERRCODE='55000';
  END IF;
  IF p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION', 'CONNECT_INVOICE')
     OR NULLIF(btrim(p_owner_token), '') IS NULL
     OR ((p_facture_id IS NULL) = (p_mission_id IS NULL)) THEN
    RAISE EXCEPTION 'Paramètres de claim Stripe invalides' USING ERRCODE = '22023';
  END IF;

  IF p_facture_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.factures f
      WHERE f.id = p_facture_id
        AND f.type_document = 'FACTURE'
        AND f.statut <> 'ANNULEE'
    ) THEN
      RAISE EXCEPTION 'Facture de claim introuvable ou non payable' USING ERRCODE = 'P0002';
    END IF;
    IF p_flow = 'CONNECT_INVOICE' THEN
      v_resources := ARRAY['FACTURE:' || p_facture_id::text];
    ELSE
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
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.missions m WHERE m.id = p_mission_id) THEN
      RAISE EXCEPTION 'Mission de claim introuvable' USING ERRCODE = 'P0002';
    END IF;
    v_resources := ARRAY['MISSION:' || p_mission_id::text];
  END IF;

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


ALTER FUNCTION "public"."fn_stripe_payment_flow_claim"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid", "p_mission_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_stripe_payment_flow_claim_connect_v1"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid" DEFAULT NULL::"uuid", "p_mission_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
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
  IF p_flow IS NULL OR p_flow NOT IN ('CONNECT_MISSION','CONNECT_INVOICE') THEN
    RAISE EXCEPTION 'CONNECT_PROTOCOL_SCOPE' USING ERRCODE='22023';
  END IF;
  IF COALESCE(NULLIF(auth.jwt()->>'role',''),NULLIF(current_setting('request.jwt.claim.role',true),''),'')<>'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
    WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'CONNECT_RELEASE_CLOSED' USING ERRCODE='55000';
  END IF;
  IF p_flow NOT IN ('CHECKOUT_INVOICE', 'SEPA_INVOICE', 'CONNECT_MISSION', 'CONNECT_INVOICE')
     OR NULLIF(btrim(p_owner_token), '') IS NULL
     OR ((p_facture_id IS NULL) = (p_mission_id IS NULL)) THEN
    RAISE EXCEPTION 'Paramètres de claim Stripe invalides' USING ERRCODE = '22023';
  END IF;

  IF p_facture_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.factures f
      WHERE f.id = p_facture_id
        AND f.type_document = 'FACTURE'
        AND f.statut <> 'ANNULEE'
    ) THEN
      RAISE EXCEPTION 'Facture de claim introuvable ou non payable' USING ERRCODE = 'P0002';
    END IF;
    IF p_flow = 'CONNECT_INVOICE' THEN
      v_resources := ARRAY['FACTURE:' || p_facture_id::text];
    ELSE
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
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.missions m WHERE m.id = p_mission_id) THEN
      RAISE EXCEPTION 'Mission de claim introuvable' USING ERRCODE = 'P0002';
    END IF;
    v_resources := ARRAY['MISSION:' || p_mission_id::text];
  END IF;

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


ALTER FUNCTION "public"."fn_stripe_payment_flow_claim_connect_v1"("p_flow" "text", "p_owner_token" "text", "p_facture_id" "uuid", "p_mission_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_stripe_webhook_event_claim"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
  IF p_event_type='checkout.session.completed' AND p_payload#>>'{object,metadata,type}'='CONNECT_MISSION_PAYMENT' THEN
    RAISE EXCEPTION 'CONNECT_CLIENT_VERSION_REQUIRED' USING ERRCODE='55000';
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


ALTER FUNCTION "public"."fn_stripe_webhook_event_claim"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_stripe_webhook_event_claim_connect_v1"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
  IF p_event_type IS DISTINCT FROM 'checkout.session.completed'
    OR p_source_webhook IS DISTINCT FROM 'PLATFORM'
    OR p_payload#>>'{object,metadata,type}' IS DISTINCT FROM 'CONNECT_MISSION_PAYMENT' THEN
    RAISE EXCEPTION 'CONNECT_PROTOCOL_SCOPE' USING ERRCODE='22023';
  END IF;
  IF COALESCE(NULLIF(auth.jwt()->>'role',''),NULLIF(current_setting('request.jwt.claim.role',true),''),'')<>'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate
    WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'CONNECT_RELEASE_CLOSED' USING ERRCODE='55000';
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


ALTER FUNCTION "public"."fn_stripe_webhook_event_claim_connect_v1"("p_event_id" "text", "p_event_type" "text", "p_payload" "jsonb", "p_source_webhook" "text", "p_livemode" boolean) OWNER TO "postgres";

DO $barrier_installation$
DECLARE v_expected record; v_proc record; v_updated integer;
BEGIN
 FOR v_expected IN SELECT * FROM (VALUES
    ('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','b745cc054c57ea9ec14a983676493fd6','search_path=public, pg_temp','jsonb'),
    ('fn_stripe_payment_flow_claim_connect_v1(text,text,uuid,uuid)','7a1f62537ac10dc062b73d80412d5892','search_path=public, pg_temp','jsonb'),
    ('fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','4c483d30b449de51b38e5790c1a3f93b','search_path=public','text'),
    ('fn_stripe_webhook_event_claim_connect_v1(text,text,jsonb,text,boolean)','252e57ef9c2cd0cc6ed6b2591a0e51b5','search_path=public','text')) AS x(signature,corps,configuration,resultat) LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC,anon,authenticated,service_role',v_expected.signature);
   EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO service_role',v_expected.signature);
   INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
   VALUES(v_expected.signature,'SERVICE_ONLY_REVOQUE',v_expected.corps,
     'Barrière de version Connect : anciens callers refusés, nouveau protocole fermé jusqu’à activation revue ; autres claims historiques inchangés.',now())
   ON CONFLICT(signature) DO UPDATE SET definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le
   WHERE private.security_definer_inventory.categorie='SERVICE_ONLY_REVOQUE'
     AND (private.security_definer_inventory.signature,private.security_definer_inventory.definition_md5)
       IN (('fn_stripe_payment_flow_claim(text,text,uuid,uuid)','4506013ff5a5c0df5761523a221d8977'),('fn_stripe_webhook_event_claim(text,text,jsonb,text,boolean)','c7b1356e671f49a19bf98cedf75f8249'));
   GET DIAGNOSTICS v_updated=ROW_COUNT;
   IF v_updated<>1 THEN RAISE EXCEPTION 'CONNECT_BARRIER_INVENTORY_INSTALLATION (%)',v_expected.signature; END IF;
   SELECT p.*,l.lanname INTO v_proc FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('public.'||v_expected.signature);
   IF NOT FOUND OR md5(v_proc.prosrc) IS DISTINCT FROM v_expected.corps
     OR pg_get_userbyid(v_proc.proowner)<>'postgres' OR v_proc.prosecdef IS DISTINCT FROM TRUE
     OR v_proc.provolatile<>'v' OR v_proc.lanname<>'plpgsql' OR v_proc.prokind<>'f'
     OR pg_get_function_result(v_proc.oid) IS DISTINCT FROM v_expected.resultat
     OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_expected.configuration]::text[]
     OR v_proc.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
     OR (SELECT count(*) FROM private.security_definer_inventory WHERE signature=v_expected.signature
       AND categorie='SERVICE_ONLY_REVOQUE' AND definition_md5=v_expected.corps)<>1 THEN
     RAISE EXCEPTION 'CONNECT_BARRIER_INSTALLATION (%)',v_expected.signature;
   END IF;
 END LOOP;
 IF (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR NOT EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
   OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.stripe_connect_release_gate'::regclass
     AND pg_get_userbyid(relowner)='postgres' AND relrowsecurity
     AND relacl='{postgres=arwdDxtm/postgres}'::aclitem[])
   OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.stripe_connect_release_gate'::regclass)
   OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.stripe_connect_release_gate'::regclass AND NOT tgisinternal)
   OR EXISTS(SELECT 1 FROM pg_rewrite WHERE ev_class='private.stripe_connect_release_gate'::regclass AND rulename<>'_RETURN') THEN
   RAISE EXCEPTION 'CONNECT_BARRIER_NOT_CLOSED';
 END IF;
END;
$barrier_installation$;
COMMIT;

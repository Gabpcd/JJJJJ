-- ============================================================================
-- Sprint 4.5 PR 10 — Ping GPS périodique background (opt-in RGPD)
-- ============================================================================
-- Permet à un soignant en mission de partager sa position toutes les N minutes
-- pendant la durée de sa mission, via @capacitor-community/background-geolocation.
-- Strictement opt-in (consentement RGPD explicite, révocable à tout moment).
-- Les pings sont conservés 30 jours puis purgés automatiquement.
-- ============================================================================

-- 1. Consentement RGPD (table dédiée — séparable du profil pour audit RGPD)
CREATE TABLE IF NOT EXISTS public.consentements_ping_gps (
  soignant_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  consenti boolean NOT NULL DEFAULT false,
  consenti_le timestamptz,
  retire_le timestamptz,
  version_cgu text DEFAULT 'v1',
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.consentements_ping_gps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_consent_ping_select ON public.consentements_ping_gps;
CREATE POLICY pol_consent_ping_select ON public.consentements_ping_gps
  FOR SELECT TO authenticated
  USING (soignant_id = auth.uid() OR public.est_admin());

DROP POLICY IF EXISTS pol_consent_ping_deny_write ON public.consentements_ping_gps;
CREATE POLICY pol_consent_ping_deny_write ON public.consentements_ping_gps
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- 2. Table pings GPS
CREATE TABLE IF NOT EXISTS public.pings_gps_mission (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  soignant_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lat numeric(10, 7) NOT NULL,
  lng numeric(10, 7) NOT NULL,
  precision_m numeric(8, 2),
  vitesse_ms numeric(8, 2),
  cap_deg numeric(6, 2),
  altitude_m numeric(8, 2),
  source text NOT NULL DEFAULT 'BACKGROUND' CHECK (source IN ('BACKGROUND', 'FOREGROUND', 'POINTAGE_QR', 'POINTAGE_CODE')),
  mock_detected boolean DEFAULT false,
  horodatage timestamptz NOT NULL,
  recu_le timestamptz NOT NULL DEFAULT now(),
  terminal_id text
);

CREATE INDEX IF NOT EXISTS idx_pings_gps_mission ON public.pings_gps_mission(mission_id, horodatage DESC);
CREATE INDEX IF NOT EXISTS idx_pings_gps_soignant ON public.pings_gps_mission(soignant_id, horodatage DESC);
CREATE INDEX IF NOT EXISTS idx_pings_gps_purge ON public.pings_gps_mission(recu_le);

ALTER TABLE public.pings_gps_mission ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_pings_gps_select ON public.pings_gps_mission;
CREATE POLICY pol_pings_gps_select ON public.pings_gps_mission
  FOR SELECT TO authenticated
  USING (
    soignant_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = pings_gps_mission.mission_id
        AND m.etablissement_id = public.mon_etablissement_id()
    )
    OR public.est_admin()
  );

DROP POLICY IF EXISTS pol_pings_gps_deny_write ON public.pings_gps_mission;
CREATE POLICY pol_pings_gps_deny_write ON public.pings_gps_mission
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- 3. RPC : donner / retirer consentement
CREATE OR REPLACE FUNCTION public.fn_donner_consentement_ping_gps(
  p_consent boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  INSERT INTO public.consentements_ping_gps (soignant_id, consenti, consenti_le, retire_le, maj_le)
  VALUES (
    v_uid,
    p_consent,
    CASE WHEN p_consent THEN now() ELSE NULL END,
    CASE WHEN NOT p_consent THEN now() ELSE NULL END,
    now()
  )
  ON CONFLICT (soignant_id) DO UPDATE SET
    consenti = EXCLUDED.consenti,
    consenti_le = CASE WHEN EXCLUDED.consenti THEN COALESCE(public.consentements_ping_gps.consenti_le, now()) ELSE public.consentements_ping_gps.consenti_le END,
    retire_le = CASE WHEN NOT EXCLUDED.consenti THEN now() ELSE NULL END,
    maj_le = now();

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'RGPD_CONSENTEMENT_DONNE', 'consentement_ping_gps', v_uid,
    jsonb_build_object(
      'type', 'PING_GPS_BACKGROUND',
      'consenti', p_consent,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'consenti', p_consent,
    'horodatage', now()
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_donner_consentement_ping_gps(boolean) TO authenticated;

-- 4. RPC : enregistrer batch de pings GPS
CREATE OR REPLACE FUNCTION public.fn_enregistrer_pings_gps(
  p_mission_id uuid,
  p_pings jsonb,
  p_terminal_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_mission record;
  v_consent record;
  v_ping jsonb;
  v_inserts integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_pings IS NULL OR jsonb_typeof(p_pings) != 'array' OR jsonb_array_length(p_pings) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'PINGS_VIDE');
  END IF;

  -- Limite anti-flood : max 200 pings par batch
  IF jsonb_array_length(p_pings) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_PINGS');
  END IF;

  -- Mission + soignant assigné
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;
  IF v_mission.soignant_assigne_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Consentement RGPD strict
  SELECT * INTO v_consent FROM public.consentements_ping_gps WHERE soignant_id = v_uid;
  IF v_consent IS NULL OR NOT v_consent.consenti THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONSENTEMENT_MANQUANT');
  END IF;

  -- Fenêtre temporelle : pings acceptés uniquement entre debut_le -1h et fin_le +2h
  -- (au-delà : ignoré silencieusement, le client recevra success=true mais 0 insertions)
  FOR v_ping IN SELECT * FROM jsonb_array_elements(p_pings)
  LOOP
    DECLARE
      v_h timestamptz := (v_ping->>'horodatage')::timestamptz;
      v_lat numeric := (v_ping->>'lat')::numeric;
      v_lng numeric := (v_ping->>'lng')::numeric;
      v_prec numeric := NULLIF(v_ping->>'precision_m', '')::numeric;
      v_vit numeric := NULLIF(v_ping->>'vitesse_ms', '')::numeric;
      v_cap numeric := NULLIF(v_ping->>'cap_deg', '')::numeric;
      v_alt numeric := NULLIF(v_ping->>'altitude_m', '')::numeric;
      v_src text := COALESCE(v_ping->>'source', 'BACKGROUND');
      v_mock boolean := COALESCE((v_ping->>'mock_detected')::boolean, false);
    BEGIN
      IF v_h IS NULL OR v_lat IS NULL OR v_lng IS NULL THEN
        CONTINUE;
      END IF;
      IF v_h < v_mission.debut_le - INTERVAL '1 hour' OR v_h > v_mission.fin_le + INTERVAL '2 hours' THEN
        CONTINUE;
      END IF;
      IF v_lat < -90 OR v_lat > 90 OR v_lng < -180 OR v_lng > 180 THEN
        CONTINUE;
      END IF;

      INSERT INTO public.pings_gps_mission (
        mission_id, soignant_id, lat, lng, precision_m, vitesse_ms, cap_deg, altitude_m,
        source, mock_detected, horodatage, terminal_id
      ) VALUES (
        p_mission_id, v_uid, v_lat, v_lng, v_prec, v_vit, v_cap, v_alt,
        v_src, v_mock, v_h, p_terminal_id
      );
      v_inserts := v_inserts + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'inserts', v_inserts,
    'ignores', jsonb_array_length(p_pings) - v_inserts
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_pings_gps(uuid, jsonb, text) TO authenticated;

-- 5. Purge automatique 30 jours (RGPD minimisation)
CREATE OR REPLACE FUNCTION public.fn_purger_pings_gps_anciens()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM public.pings_gps_mission WHERE recu_le < now() - INTERVAL '30 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted > 0 THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', 'SYSTEME',
      'SYSTEM', 'fonction', NULL,
      jsonb_build_object(
        'evenement', 'PURGE_PINGS_GPS',
        'lignes_supprimees', v_deleted,
        'horodatage', now()
      )
    );
  END IF;
END;
$body$;

-- pg_cron : tous les jours à 3h du matin UTC
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_purger_pings_gps') WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'jolene_purger_pings_gps'
    );
    PERFORM cron.schedule(
      'jolene_purger_pings_gps',
      '0 3 * * *',
      'SELECT public.fn_purger_pings_gps_anciens()'
    );
  END IF;
END;
$body$;

-- 6. Audit migration
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT45_PR10_PING_GPS_INSTALLED',
    'pr', 'PR 10 Sprint 4.5',
    'description', 'Ping GPS background opt-in + consentement RGPD + purge 30j',
    'tables', jsonb_build_array('consentements_ping_gps', 'pings_gps_mission'),
    'cron', 'jolene_purger_pings_gps daily 3am UTC'
  )
);

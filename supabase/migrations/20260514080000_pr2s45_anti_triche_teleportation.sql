-- PR 2 Sprint 4.5 — Détection téléportation + alerte admin
--
-- Cron toutes les 15 min : compare les 2 derniers pointages de chaque
-- soignant actif. Si vitesse > 200 km/h entre 2 pointages cohérents
-- (même soignant, présences successives) → alerte admin niveau ALERTE
-- + trace journaux_audit TELEPORTATION_DETECTED.
--
-- AUCUNE suspension automatique (alerte admin pour validation manuelle).

-- ============================================================
-- 1. Helper : calcul vitesse entre 2 pointages
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_vitesse_entre_pointages(
  p_lat1 numeric, p_lng1 numeric, p_ts1 timestamptz,
  p_lat2 numeric, p_lng2 numeric, p_ts2 timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_distance_m numeric;
  v_duree_h numeric;
  v_vitesse_kmh numeric;
BEGIN
  IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL
     OR p_ts1 IS NULL OR p_ts2 IS NULL THEN
    RETURN jsonb_build_object('calculable', false);
  END IF;

  v_distance_m := public.fn_haversine_distance_m(p_lat1, p_lng1, p_lat2, p_lng2);
  v_duree_h := EXTRACT(EPOCH FROM (p_ts2 - p_ts1)) / 3600.0;

  IF v_duree_h <= 0 THEN
    RETURN jsonb_build_object('calculable', false, 'raison', 'duree_invalide');
  END IF;

  v_vitesse_kmh := (v_distance_m / 1000.0) / v_duree_h;

  RETURN jsonb_build_object(
    'calculable', true,
    'distance_m', v_distance_m,
    'duree_h', v_duree_h,
    'vitesse_kmh', v_vitesse_kmh,
    'teleportation', v_vitesse_kmh > 200
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_vitesse_entre_pointages(numeric, numeric, timestamptz, numeric, numeric, timestamptz)
  TO authenticated, service_role;

-- ============================================================
-- 2. RPC cron : détecte les téléportations dans les 24h
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_detecter_teleportations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_alertes_count int := 0;
  v_rec RECORD;
  v_vitesse jsonb;
  v_admin_ids uuid[];
BEGIN
  -- Pour chaque soignant ayant pointé dans les 24h, comparer les 2 derniers pointages
  FOR v_rec IN
    WITH pointages_recents AS (
      SELECT
        p.soignant_id,
        p.pointage_arrivee_le AS ts,
        p.arrivee_lat AS lat, p.arrivee_lng AS lng,
        p.mission_id, p.id AS presence_id,
        'arrivee' AS type_p
      FROM public.presences p
      WHERE p.pointage_arrivee_le > NOW() - INTERVAL '24 hours'
        AND p.arrivee_lat IS NOT NULL AND p.arrivee_lng IS NOT NULL
      UNION ALL
      SELECT
        p.soignant_id,
        p.pointage_depart_le AS ts,
        p.depart_lat AS lat, p.depart_lng AS lng,
        p.mission_id, p.id AS presence_id,
        'depart' AS type_p
      FROM public.presences p
      WHERE p.pointage_depart_le > NOW() - INTERVAL '24 hours'
        AND p.depart_lat IS NOT NULL AND p.depart_lng IS NOT NULL
    ),
    paires AS (
      SELECT
        a.soignant_id,
        a.ts AS ts1, a.lat AS lat1, a.lng AS lng1, a.mission_id AS mission1, a.type_p AS type1,
        LEAD(a.ts) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS ts2,
        LEAD(a.lat) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS lat2,
        LEAD(a.lng) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS lng2,
        LEAD(a.mission_id) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS mission2,
        LEAD(a.type_p) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS type2,
        LEAD(a.presence_id) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS presence2
      FROM pointages_recents a
    )
    SELECT * FROM paires
    WHERE ts2 IS NOT NULL
      AND NOT EXISTS (
        -- Skip si déjà alerté pour cette paire
        SELECT 1 FROM public.journaux_audit ja
        WHERE ja.action = 'SYSTEM'
          AND ja.details->>'evenement' = 'TELEPORTATION_DETECTED'
          AND ja.details->>'presence_id_destination' = paires.presence2::text
      )
  LOOP
    v_vitesse := public.fn_vitesse_entre_pointages(
      v_rec.lat1, v_rec.lng1, v_rec.ts1,
      v_rec.lat2, v_rec.lng2, v_rec.ts2
    );

    IF (v_vitesse->>'calculable')::boolean AND (v_vitesse->>'teleportation')::boolean THEN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_rec.soignant_id, 'SOIGNANT', 'SYSTEM', 'presence', v_rec.presence2,
        jsonb_build_object(
          'evenement', 'TELEPORTATION_DETECTED',
          'niveau', 'ALERTE',
          'soignant_id', v_rec.soignant_id,
          'mission_id_source', v_rec.mission1,
          'mission_id_destination', v_rec.mission2,
          'type_pointage_source', v_rec.type1,
          'type_pointage_destination', v_rec.type2,
          'presence_id_destination', v_rec.presence2,
          'ts_source', v_rec.ts1,
          'ts_destination', v_rec.ts2,
          'distance_m', v_vitesse->>'distance_m',
          'duree_h', v_vitesse->>'duree_h',
          'vitesse_kmh', v_vitesse->>'vitesse_kmh'
        )
      );

      v_alertes_count := v_alertes_count + 1;
    END IF;
  END LOOP;

  -- Si alertes : notification admins via externalisation_actions
  IF v_alertes_count > 0 THEN
    v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());
    IF array_length(v_admin_ids, 1) > 0 THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      SELECT 'EMAIL_NOTIF', jsonb_build_object(
        'destinataire_id', uid,
        'type', 'ALERTE_TELEPORTATION',
        'data', jsonb_build_object(
          'count', v_alertes_count,
          'lien_admin', 'https://app.jolene.app/admin/journaux-audit?evenement=TELEPORTATION_DETECTED'
        )
      ), 'CRON_ANTI_TRICHE', NULL FROM unnest(v_admin_ids) AS uid;
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      SELECT 'PUSH_NOTIF', jsonb_build_object(
        'destinataire_id', uid, 'type_evenement', 'ALERTE_ADMIN',
        'titre', '⚠️ ' || v_alertes_count || ' téléportation' || CASE WHEN v_alertes_count > 1 THEN 's' ELSE '' END || ' détectée' || CASE WHEN v_alertes_count > 1 THEN 's' ELSE '' END,
        'corps', 'Vitesse > 200 km/h entre pointages. Vérification requise.',
        'lien', '/admin/journaux-audit'
      ), 'CRON_ANTI_TRICHE', NULL FROM unnest(v_admin_ids) AS uid;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'alertes_count', v_alertes_count);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_detecter_teleportations() TO service_role;

-- ============================================================
-- 3. Cron toutes les 15 min
-- ============================================================
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_alerte_teleportation')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_alerte_teleportation');
    PERFORM cron.schedule(
      'jolene_alerte_teleportation',
      '*/15 * * * *',
      'SELECT public.fn_detecter_teleportations()'
    );
  END IF;
END $body$;

-- ============================================================
-- 4. Colonne alerte_mock_location sur presences (frontend signale)
-- ============================================================
ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS arrivee_mock_detected boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS depart_mock_detected boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.presences.arrivee_mock_detected IS
  'Frontend a détecté un signal mock GPS lors de l''arrivée '
  '(accuracy=0, coords parfaitement rondes, etc.). Pour alerte admin, '
  'pas de refus automatique car heuristique. Sprint 4.5 PR 2.';

-- 5. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT45_PR2_ANTI_TRICHE_INSTALLED',
    'pr', 'PR 2 Sprint 4.5',
    'rpcs', ARRAY['fn_vitesse_entre_pointages', 'fn_detecter_teleportations'],
    'cron', 'jolene_alerte_teleportation (*/15 min)',
    'note', 'Aucune suspension auto. Alertes admin uniquement.'
  )
);

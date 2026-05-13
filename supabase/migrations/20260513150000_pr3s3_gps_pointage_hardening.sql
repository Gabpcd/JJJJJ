-- PR 3 Sprint 3 — Hardening GPS / pointage (production-grade)
--
-- Audit Sprint 3 a révélé que les RPCs fn_pointer_arrivee + fn_pointer_depart
-- existaient mais :
--   1. AUCUN calcul de distance Haversine côté serveur
--   2. AUCUNE tolérance géographique enforcée
--   3. distance_etablissement_m + perimetre_gps_valide jamais calculés
--   4. AUCUN cron de validation auto à J+72h
--
-- Cette PR durcit le système :
--   - Helper public.fn_haversine_distance_m(lat1, lng1, lat2, lng2) → meters
--   - Colonne etablissements.tolerance_pointage_m (default 500)
--   - Colonne presences.valide_auto_72h_le (tracking validation auto)
--   - RPC fn_valider_presences_72h_auto() : valide automatiquement les
--     présences > 72h sans contestation. Idempotent. Appel via pg_cron.
--   - fn_pointer_arrivee + fn_pointer_depart : calcul distance + check
--     tolerance + storage distance_etablissement_m + perimetre_gps_valide
--
-- Compatibilité : signatures RPC identiques. Le code de secours
-- (p_code_arrivee / p_code_depart) reste prioritaire (bypass GPS check).

-- 1. Colonne tolerance par étab (default 500m, ajustable admin)
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS tolerance_pointage_m int NOT NULL DEFAULT 500
  CHECK (tolerance_pointage_m BETWEEN 50 AND 5000);

COMMENT ON COLUMN public.etablissements.tolerance_pointage_m IS
  'Tolérance en mètres entre la position GPS du soignant et l''adresse de '
  'l''étab pour qu''un pointage GPS soit accepté. Default 500m (URBAN_GPS_NOISE). '
  'Admin peut ajuster (entre 50 et 5000m).';

-- 2. Colonne tracking validation auto J+72h
ALTER TABLE public.presences
  ADD COLUMN IF NOT EXISTS valide_auto_72h_le timestamptz;

COMMENT ON COLUMN public.presences.valide_auto_72h_le IS
  'Date à laquelle la présence a été validée automatiquement par le cron '
  'J+72h en l''absence de contestation. Distinct de valide_le (validation '
  'manuelle par l''étab).';

-- 3. Helper Haversine — distance entre 2 points GPS en mètres
CREATE OR REPLACE FUNCTION public.fn_haversine_distance_m(
  p_lat1 numeric, p_lng1 numeric,
  p_lat2 numeric, p_lng2 numeric
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_r constant numeric := 6371000;  -- rayon Terre en m
  v_phi1 numeric;
  v_phi2 numeric;
  v_dphi numeric;
  v_dlambda numeric;
  v_a numeric;
  v_c numeric;
BEGIN
  IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN
    RETURN NULL;
  END IF;
  v_phi1 := radians(p_lat1);
  v_phi2 := radians(p_lat2);
  v_dphi := radians(p_lat2 - p_lat1);
  v_dlambda := radians(p_lng2 - p_lng1);
  v_a := sin(v_dphi/2) * sin(v_dphi/2) +
         cos(v_phi1) * cos(v_phi2) * sin(v_dlambda/2) * sin(v_dlambda/2);
  v_c := 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
  RETURN round(v_r * v_c);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_haversine_distance_m(numeric, numeric, numeric, numeric)
  TO authenticated, service_role;

-- 4. fn_pointer_arrivee durcie avec check distance
CREATE OR REPLACE FUNCTION public.fn_pointer_arrivee(
  p_mission_id uuid,
  p_lat numeric DEFAULT NULL,
  p_lng numeric DEFAULT NULL,
  p_precision numeric DEFAULT NULL,
  p_terminal_id text DEFAULT NULL,
  p_modele text DEFAULT NULL,
  p_code_arrivee text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_contrat RECORD;
  v_etab RECORD;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_methode text;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
  IF v_mission.soignant_assigne_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN '{"error":"Mission non active"}'::JSONB; END IF;

  SELECT * INTO v_contrat FROM contrats_mission
  WHERE mission_id = p_mission_id AND statut = 'SIGNE_COMPLET';
  IF v_contrat IS NULL THEN
    RETURN '{"error":"Le contrat doit être signé avant le pointage."}'::JSONB;
  END IF;

  IF EXISTS (SELECT 1 FROM presences WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
    RETURN '{"error":"Vous avez déjà pointé votre arrivée."}'::JSONB;
  END IF;

  -- Charger l'étab pour distance + tolerance
  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
  INTO v_etab
  FROM etablissements WHERE id = v_mission.etablissement_id;

  -- Cas 1 : code de secours fourni → bypass GPS, code prioritaire
  IF p_code_arrivee IS NOT NULL THEN
    IF p_code_arrivee != v_mission.code_arrivee THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT',
        'error', 'Code de pointage incorrect.');
    END IF;
    v_methode := 'CODE';
    v_perimetre_ok := true;
    v_distance_m := NULL;
  ELSE
    -- Cas 2 : pointage GPS — calcul distance Haversine
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      -- Étab sans adresse GPS : on accepte mais on flag perimetre = false
      v_distance_m := NULL;
      v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(
        p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric
      );
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement '
            || '(tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;

  INSERT INTO presences (
    mission_id, soignant_id, pointage_arrivee_le,
    arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
    arrivee_id_terminal, arrivee_modele_terminal,
    methode_pointage_arrivee,
    distance_etablissement_m, perimetre_gps_valide
  ) VALUES (
    p_mission_id, auth.uid(), NOW(),
    p_lat, p_lng, p_precision,
    p_terminal_id, p_modele,
    v_methode,
    v_distance_m, v_perimetre_ok
  );

  UPDATE missions SET statut = 'EN_COURS', modifie_le = NOW()
  WHERE id = p_mission_id AND statut = 'ASSIGNEE';

  RETURN jsonb_build_object('success', true, 'methode', v_methode,
    'distance_m', v_distance_m, 'perimetre_valide', v_perimetre_ok);
END;
$function$;

-- 5. fn_pointer_depart durcie similaire
CREATE OR REPLACE FUNCTION public.fn_pointer_depart(
  p_presence_id uuid,
  p_lat numeric DEFAULT NULL,
  p_lng numeric DEFAULT NULL,
  p_precision numeric DEFAULT NULL,
  p_terminal_id text DEFAULT NULL,
  p_modele text DEFAULT NULL,
  p_code_depart text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_presence RECORD;
  v_mission RECORD;
  v_etab RECORD;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_methode text;
BEGIN
  SELECT * INTO v_presence FROM presences WHERE id = p_presence_id;
  IF v_presence IS NULL THEN RETURN '{"error":"Présence introuvable"}'::JSONB; END IF;
  IF v_presence.soignant_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_presence.pointage_depart_le IS NOT NULL THEN
    RETURN '{"error":"Départ déjà pointé"}'::JSONB;
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = v_presence.mission_id;
  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
  INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

  IF p_code_depart IS NOT NULL THEN
    IF p_code_depart != v_mission.code_depart THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT',
        'error', 'Code de départ incorrect.');
    END IF;
    v_methode := 'CODE';
    v_perimetre_ok := true;
    v_distance_m := NULL;
  ELSE
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      v_distance_m := NULL;
      v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(
        p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric
      );
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement '
            || '(tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;

  UPDATE presences SET
    pointage_depart_le = NOW(),
    depart_lat = p_lat, depart_lng = p_lng,
    depart_precision_gps_m = p_precision,
    depart_id_terminal = p_terminal_id,
    depart_modele_terminal = p_modele,
    methode_pointage_depart = v_methode,
    distance_etablissement_m = COALESCE(distance_etablissement_m, v_distance_m),
    perimetre_gps_valide = CASE WHEN perimetre_gps_valide IS NOT TRUE THEN v_perimetre_ok ELSE perimetre_gps_valide END
  WHERE id = p_presence_id;

  RETURN jsonb_build_object('success', true, 'methode', v_methode,
    'distance_m', v_distance_m, 'perimetre_valide', v_perimetre_ok);
END;
$function$;

-- 6. Cron auto-validation J+72h
CREATE OR REPLACE FUNCTION public.fn_valider_presences_72h_auto()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
BEGIN
  -- Valide auto toutes les présences :
  --   - avec départ pointé > 72h
  --   - pas encore validées (valide_par_etablissement IS NULL ou false)
  --   - pas en litige (motif_litige IS NULL)
  --   - pas déjà auto-validées
  UPDATE public.presences
  SET valide_auto_72h_le = NOW(),
      valide_par_etablissement = true,
      valide_le = COALESCE(valide_le, NOW()),
      modifie_le = NOW()
  WHERE pointage_depart_le IS NOT NULL
    AND pointage_depart_le < NOW() - INTERVAL '72 hours'
    AND COALESCE(valide_par_etablissement, false) = false
    AND motif_litige IS NULL
    AND valide_auto_72h_le IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', 'SYSTEME',
      'SYSTEM', 'cron', NULL,
      jsonb_build_object(
        'evenement', 'PRESENCES_VALIDEES_AUTO_72H',
        'count', v_count,
        'exec_le', NOW()
      )
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'count_validees', v_count);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_valider_presences_72h_auto() TO service_role;

-- 7. Scheduler pg_cron (idempotent — drop d'abord si existe).
-- Note dollar-quoting : on utilise $body$ pour le DO block externe et garde
-- $$ pour la string cron.schedule (équivalent guillemets simples doublés).
-- C'est ce que le supabase CLI / db push parse correctement.
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_valider_presences_72h')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_valider_presences_72h');

    PERFORM cron.schedule(
      'jolene_valider_presences_72h',
      '15 */6 * * *',  -- toutes les 6h à minute 15
      'SELECT public.fn_valider_presences_72h_auto()'
    );
  END IF;
END $body$;

-- 8. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT3_PR3_GPS_POINTAGE_HARDENED',
    'pr', 'PR 3 Sprint 3',
    'modifications', ARRAY[
      'fn_haversine_distance_m helper créé',
      'etablissements.tolerance_pointage_m (default 500m)',
      'presences.valide_auto_72h_le',
      'fn_pointer_arrivee : check distance + tolerance + error_code HORS_PERIMETRE',
      'fn_pointer_depart : check distance + tolerance + error_code HORS_PERIMETRE',
      'fn_valider_presences_72h_auto : cron pg_cron 6h'
    ]
  )
);

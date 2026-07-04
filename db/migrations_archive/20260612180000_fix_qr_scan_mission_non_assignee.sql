-- Fix sécurité pointage QR : un soignant authentifié pouvait pointer sur une
-- mission SANS assigné. Cause : `v_mission.soignant_assigne_id != v_uid` vaut
-- NULL (donc non-vrai) quand soignant_assigne_id est NULL → le garde passait
-- et une presence était insérée sur une mission OUVERTE. Antipattern NULL
-- (famille Sprint 17), raté par le sweep 20260531130000 sur cette ligne.
-- Correctif : IS DISTINCT FROM + détection « non trouvée » via .id.
-- (Découvert par la réécriture des tests anti-triche du 12/06.)
-- Corps identique à la version prod, seule la ligne de garde change.

CREATE OR REPLACE FUNCTION public.fn_valider_scan_qr(
  p_token text,
  p_lat numeric DEFAULT NULL::numeric,
  p_lng numeric DEFAULT NULL::numeric,
  p_precision numeric DEFAULT NULL::numeric,
  p_terminal_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_qr RECORD;
  v_mission RECORD;
  v_etab RECORD;
  v_presence RECORD;
  v_type_detecte text;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_now timestamptz := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_qr FROM public.qr_codes_mission WHERE token = p_token AND actif = true;
  IF v_qr IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_INVALIDE',
                                'error', 'QR non valide ou déjà invalidé.');
  END IF;

  IF v_qr.expire_le < v_now THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_EXPIRE',
                                'error', 'Ce QR a expiré. Demandez à l''établissement de régénérer.');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_qr.mission_id;
  -- FIX : IS DISTINCT FROM (sémantique NULL correcte) — refuse aussi les
  -- missions sans assigné, qui passaient le garde `!=` (NULL ≠ TRUE).
  IF v_mission.id IS NULL OR v_mission.soignant_assigne_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'QR_MISSION_AUTRE',
                                'error', 'Ce QR ne correspond pas à votre mission active.');
  END IF;

  -- Cohérence temporelle
  IF v_now < v_mission.debut_le - INTERVAL '1 hour' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HEURE_TROP_TOT',
                                'error', 'Trop tôt pour pointer. Mission démarre à ' ||
                                  to_char(v_mission.debut_le, 'DD/MM HH24:MI') || '.');
  END IF;
  IF v_now > COALESCE(v_mission.fin_le, v_now + INTERVAL '1 day') + INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HEURE_TROP_TARD',
                                'error', 'Trop tard pour pointer. Mission terminée depuis plus de 2 heures.');
  END IF;

  -- Détecter le type de pointage selon presences existantes
  SELECT * INTO v_presence FROM public.presences
  WHERE mission_id = v_mission.id AND soignant_id = v_uid LIMIT 1;

  IF v_qr.type = 'ARRIVEE' THEN
    v_type_detecte := 'ARRIVEE';
  ELSIF v_qr.type = 'DEPART' THEN
    v_type_detecte := 'DEPART';
  ELSE
    -- UNIVERSEL : pas de presence → ARRIVEE, sinon DEPART
    v_type_detecte := CASE WHEN v_presence IS NULL THEN 'ARRIVEE' ELSE 'DEPART' END;
  END IF;

  -- Vérif double pointage / cohérence départ > arrivée + 30 min
  IF v_type_detecte = 'ARRIVEE' AND v_presence.id IS NOT NULL AND v_presence.pointage_arrivee_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_POINTE',
                                'error', 'Vous avez déjà pointé votre arrivée.');
  END IF;
  IF v_type_detecte = 'DEPART' THEN
    IF v_presence IS NULL OR v_presence.pointage_arrivee_le IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_SANS_ARRIVEE',
                                  'error', 'Vous devez d''abord pointer votre arrivée.');
    END IF;
    IF v_presence.pointage_depart_le IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_DEJA_POINTE',
                                  'error', 'Vous avez déjà pointé votre départ.');
    END IF;
    IF v_now < v_presence.pointage_arrivee_le + INTERVAL '30 minutes' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEPART_TROP_RAPIDE',
                                  'error', 'Vous ne pouvez pointer votre départ moins de 30 minutes après l''arrivée.');
    END IF;
  END IF;

  -- Double sécurité GPS : calcul distance si coords fournies (non bloquant)
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 100) AS tolerance_m
    INTO v_etab FROM public.etablissements WHERE id = v_mission.etablissement_id;
    IF v_etab.adresse_lat IS NOT NULL AND v_etab.adresse_lng IS NOT NULL THEN
      v_distance_m := public.fn_haversine_distance_m(
        p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= GREATEST(v_etab.tolerance_m, 1000);
      -- Si distance > 1 km : alerte admin mais pas bloquant (QR = source de vérité)
      IF v_distance_m > 1000 THEN
        INSERT INTO public.journaux_audit (
          acteur_id, type_acteur, action, type_ressource, id_ressource, details
        ) VALUES (
          v_uid, 'SOIGNANT', 'SYSTEM', 'presence', v_mission.id,
          jsonb_build_object(
            'evenement', 'QR_SCAN_GPS_ELOIGNE',
            'niveau', 'WARNING',
            'mission_id', v_mission.id,
            'distance_m', v_distance_m,
            'qr_id', v_qr.id
          )
        );
      END IF;
    END IF;
  END IF;

  -- Insert ou Update presence
  IF v_type_detecte = 'ARRIVEE' THEN
    IF v_presence IS NULL THEN
      INSERT INTO public.presences (
        mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        arrivee_id_terminal,
        methode_pointage_arrivee, qr_token_arrivee,
        distance_etablissement_m, perimetre_gps_valide
      ) VALUES (
        v_mission.id, v_uid, v_now,
        p_lat, p_lng, p_precision,
        p_terminal_id,
        'QR', p_token,
        v_distance_m, v_perimetre_ok
      );
    ELSE
      UPDATE public.presences SET
        pointage_arrivee_le = v_now,
        arrivee_lat = p_lat, arrivee_lng = p_lng,
        arrivee_precision_gps_m = p_precision,
        arrivee_id_terminal = p_terminal_id,
        methode_pointage_arrivee = 'QR',
        qr_token_arrivee = p_token,
        distance_etablissement_m = COALESCE(v_distance_m, distance_etablissement_m),
        perimetre_gps_valide = COALESCE(v_perimetre_ok, perimetre_gps_valide)
      WHERE id = v_presence.id;
    END IF;
    UPDATE public.missions SET statut = 'EN_COURS', modifie_le = NOW()
    WHERE id = v_mission.id AND statut = 'ASSIGNEE';
  ELSE  -- DEPART
    UPDATE public.presences SET
      pointage_depart_le = v_now,
      depart_lat = p_lat, depart_lng = p_lng,
      depart_precision_gps_m = p_precision,
      depart_id_terminal = p_terminal_id,
      methode_pointage_depart = 'QR',
      qr_token_depart = p_token,
      distance_etablissement_m = COALESCE(distance_etablissement_m, v_distance_m),
      perimetre_gps_valide = COALESCE(perimetre_gps_valide, v_perimetre_ok)
    WHERE id = v_presence.id;
  END IF;

  -- Incrémenter compteur QR
  UPDATE public.qr_codes_mission SET
    nb_scans = nb_scans + 1, dernier_scan_le = v_now
  WHERE id = v_qr.id;

  RETURN jsonb_build_object(
    'success', true,
    'methode_detectee', v_type_detecte,
    'mission_id', v_mission.id,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'horodatage', v_now
  );
END;
$body$;

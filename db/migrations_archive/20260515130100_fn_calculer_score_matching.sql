-- Sprint 13-A PR 2 — RPC fn_calculer_score_matching
--
-- Calcule le score matching d'une mission pour un soignant donné.
-- Retourne score 0-100 + breakdown détaillé par critère.
--
-- Algorithme :
-- 1. Filtres durs (binaires, retour 0 si KO) :
--    - profession compatible (mission.profession_requise = soignant.profession)
--    - mission ouverte (statut = OUVERTE) — checked at fetch level
--    - distance < 50 km (Haversine)
-- 2. Filtres softs (poids, total 100) :
--    - tarif horaire (25) : taux_horaire_base vs moyenne profession
--    - distance (25) : score décroissant avec distance (50 si distance 0, 0 si distance 50km)
--    - score étab (20) : score_qualite étab / 100
--    - urgence (15) : bonus si mission urgente (engagement)
--    - score soignant (15) : pénalité si score_fiabilite faible (cohérence inverse)
--
-- Pondérations à affiner Sprint 13-C selon analytics réels.

CREATE OR REPLACE FUNCTION public.fn_calculer_score_matching(
  p_soignant_id uuid,
  p_mission_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant record;
  v_mission record;
  v_etab record;
  v_distance_km numeric;
  v_score_tarif integer := 0;
  v_score_distance integer := 0;
  v_score_etab integer := 0;
  v_score_urgence integer := 0;
  v_score_soignant_fiabilite integer := 0;
  v_score_global integer := 0;
  v_breakdown jsonb;
BEGIN
  -- Récup soignant
  SELECT id, profession, adresse_lat, adresse_lng, score_fiabilite, type_contrat
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id;

  IF v_soignant.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'soignant_introuvable'));
  END IF;

  -- Récup mission + étab
  SELECT m.id, m.profession_requise, m.etablissement_id, m.taux_horaire_base,
         m.statut, m.est_urgente, m.debut_le, m.fin_le, m.duree_heures
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id;

  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'mission_introuvable'));
  END IF;

  -- Filtre dur : profession compatible
  IF v_mission.profession_requise IS NOT NULL
     AND v_soignant.profession IS NOT NULL
     AND v_mission.profession_requise <> v_soignant.profession THEN
    RETURN jsonb_build_object(
      'score', 0,
      'breakdown', jsonb_build_object('filtre_dur_ko', 'profession_incompatible')
    );
  END IF;

  SELECT id, adresse_lat, adresse_lng, score_qualite
    INTO v_etab
    FROM public.etablissements
   WHERE id = v_mission.etablissement_id;

  -- Filtre dur : distance < 50 km (si coordonnées disponibles)
  IF v_soignant.adresse_lat IS NOT NULL
     AND v_soignant.adresse_lng IS NOT NULL
     AND v_etab.adresse_lat IS NOT NULL
     AND v_etab.adresse_lng IS NOT NULL THEN
    -- Haversine simplifiée (km)
    v_distance_km := 6371 * acos(
      cos(radians(v_soignant.adresse_lat)) * cos(radians(v_etab.adresse_lat))
      * cos(radians(v_etab.adresse_lng) - radians(v_soignant.adresse_lng))
      + sin(radians(v_soignant.adresse_lat)) * sin(radians(v_etab.adresse_lat))
    );

    IF v_distance_km > 50 THEN
      RETURN jsonb_build_object(
        'score', 0,
        'breakdown', jsonb_build_object(
          'filtre_dur_ko', 'distance_excessive',
          'distance_km', round(v_distance_km, 1)
        )
      );
    END IF;
  ELSE
    v_distance_km := NULL;
  END IF;

  -- ─── Filtres softs ───

  -- Score tarif (25) : taux > 30€/h = 25, dégressif sous 30
  v_score_tarif := LEAST(25, GREATEST(0,
    CASE
      WHEN v_mission.taux_horaire_base IS NULL THEN 12
      WHEN v_mission.taux_horaire_base >= 30 THEN 25
      ELSE round(v_mission.taux_horaire_base / 30.0 * 25)::integer
    END
  ));

  -- Score distance (25) : 25 si < 5km, dégressif jusqu'à 0 à 50km
  v_score_distance := CASE
    WHEN v_distance_km IS NULL THEN 12  -- neutral si données manquantes
    WHEN v_distance_km < 5 THEN 25
    WHEN v_distance_km >= 50 THEN 0
    ELSE round(25 * (1 - (v_distance_km - 5) / 45.0))::integer
  END;

  -- Score étab qualité (20)
  v_score_etab := LEAST(20, GREATEST(0,
    CASE
      WHEN v_etab.score_qualite IS NULL THEN 10
      ELSE round(v_etab.score_qualite / 100.0 * 20)::integer
    END
  ));

  -- Score urgence (15) : bonus si urgent
  v_score_urgence := CASE WHEN v_mission.est_urgente THEN 15 ELSE 0 END;

  -- Score soignant fiabilité (15) : soignants fiables = missions de qualité
  -- Convention : score_fiabilite [0-100], défaut 50
  v_score_soignant_fiabilite := LEAST(15, GREATEST(0,
    CASE
      WHEN v_soignant.score_fiabilite IS NULL THEN 8
      ELSE round(COALESCE(v_soignant.score_fiabilite, 50) / 100.0 * 15)::integer
    END
  ));

  v_score_global := v_score_tarif + v_score_distance + v_score_etab
                  + v_score_urgence + v_score_soignant_fiabilite;

  v_breakdown := jsonb_build_object(
    'tarif', v_score_tarif,
    'distance', v_score_distance,
    'etablissement', v_score_etab,
    'urgence', v_score_urgence,
    'soignant_fiabilite', v_score_soignant_fiabilite,
    'distance_km', CASE WHEN v_distance_km IS NULL THEN NULL ELSE round(v_distance_km, 1) END
  );

  RETURN jsonb_build_object(
    'score', LEAST(100, GREATEST(0, v_score_global)),
    'breakdown', v_breakdown
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_score_matching(uuid, uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_calculer_score_matching(uuid, uuid) IS
'Sprint 13-A : calcule score matching 0-100 soignant×mission. Filtres durs (profession, distance <50km) + softs (tarif 25, distance 25, etab 20, urgence 15, fiabilité soignant 15).';

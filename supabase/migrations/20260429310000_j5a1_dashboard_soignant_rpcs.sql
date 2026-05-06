-- J5.A.1 — 3 nouvelles RPCs pour dashboard soignant addictif :
--   * fn_suggestions_missions_pour_soignant : 5 missions matchant, tri urgence > distance > score étab > récence
--   * fn_top_etablissements_soignant : top 3 étabs avec qui ce soignant a le plus bossé (missions TERMINEE)
--   * fn_repartition_heures_soignant(p_periode_jours) : agrégat jour/nuit/dim/férié pour PieChart

CREATE OR REPLACE FUNCTION public.fn_suggestions_missions_pour_soignant(p_limit INTEGER DEFAULT 5)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_result JSONB;
  v_limit INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 5), 1), 10);

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;

  WITH candidates AS (
    SELECT m.id, m.intitule, m.profession_requise, m.specialite_medicale_requise,
      m.taux_horaire_base, m.debut_le, m.fin_le, m.est_urgente, m.cree_le,
      m.etablissement_id,
      e.nom AS etab_nom, e.adresse_ville AS etab_ville,
      e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng,
      (SELECT ROUND(AVG(note)::NUMERIC, 2) FROM evaluations ev
       JOIN missions m2 ON m2.id = ev.mission_id
       WHERE m2.etablissement_id = m.etablissement_id AND ev.note IS NOT NULL) AS etab_note_moyenne,
      CASE
        WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
          ROUND((6371 * 2 * asin(sqrt(
            power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
            cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
            power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
          )))::NUMERIC, 1)
        ELSE NULL
      END AS distance_km
    FROM missions m
    LEFT JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > NOW()
      AND public.fn_soignant_compatible_mission(
        v_soignant.profession, v_soignant.specialite_medicale,
        m.profession_requise, m.specialite_medicale_requise,
        COALESCE(m.accepte_non_specialises, true)
      ) = true
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = m.id AND c.soignant_id = v_uid
      )
      AND (
        v_soignant.rayon_deplacement_km IS NULL
        OR e.adresse_lat IS NULL OR v_soignant.adresse_lat IS NULL OR
        (6371 * 2 * asin(sqrt(
          power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
          cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
          power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
        ))) <= v_soignant.rayon_deplacement_km
      )
      AND COALESCE(m.taux_horaire_base, 0) >= COALESCE(v_soignant.taux_horaire_minimum, 0)
  ),
  ranked AS (
    SELECT *,
      ROW_NUMBER() OVER (ORDER BY
        est_urgente DESC,
        distance_km ASC NULLS LAST,
        etab_note_moyenne DESC NULLS LAST,
        cree_le DESC
      ) AS rn
    FROM candidates
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'intitule', r.intitule,
    'profession_requise', r.profession_requise::text,
    'specialite_medicale_requise', r.specialite_medicale_requise,
    'taux_horaire_base', r.taux_horaire_base,
    'debut_le', r.debut_le,
    'fin_le', r.fin_le,
    'est_urgente', r.est_urgente,
    'etablissement_id', r.etablissement_id,
    'etab_nom', r.etab_nom,
    'etab_ville', r.etab_ville,
    'etab_note_moyenne', r.etab_note_moyenne,
    'distance_km', r.distance_km
  ) ORDER BY r.rn), '[]'::jsonb)
  INTO v_result
  FROM (SELECT * FROM ranked WHERE rn <= v_limit) r;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_suggestions_missions_pour_soignant(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_top_etablissements_soignant(p_limit INTEGER DEFAULT 3)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
  v_limit INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 3), 1), 10);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'etablissement_id', etablissement_id,
    'nom', nom,
    'ville', ville,
    'logo_url', logo_url,
    'nb_missions', nb_missions,
    'derniere_mission_le', derniere_mission_le
  ) ORDER BY nb_missions DESC, derniere_mission_le DESC NULLS LAST), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      m.etablissement_id,
      e.nom,
      e.adresse_ville AS ville,
      e.logo_url,
      count(*) AS nb_missions,
      max(m.fin_le) AS derniere_mission_le
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.soignant_assigne_id = v_uid AND m.statut = 'TERMINEE'
    GROUP BY m.etablissement_id, e.nom, e.adresse_ville, e.logo_url
    ORDER BY count(*) DESC, max(m.fin_le) DESC NULLS LAST
    LIMIT v_limit
  ) t;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_top_etablissements_soignant(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_repartition_heures_soignant(p_periode_jours INTEGER DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_periode INTEGER;
  v_since TIMESTAMPTZ;
  v_total NUMERIC;
  v_nuit NUMERIC;
  v_dimanche NUMERIC;
  v_ferie NUMERIC;
  v_jour NUMERIC;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_periode := GREATEST(COALESCE(p_periode_jours, 30), 1);
  v_since := NOW() - (v_periode || ' days')::interval;

  SELECT
    COALESCE(SUM(duree_heures), 0),
    COALESCE(SUM(heures_nuit), 0),
    COALESCE(SUM(heures_dimanche), 0),
    COALESCE(SUM(heures_ferie), 0)
  INTO v_total, v_nuit, v_dimanche, v_ferie
  FROM missions
  WHERE soignant_assigne_id = v_uid
    AND statut = 'TERMINEE'
    AND fin_le >= v_since;

  v_jour := GREATEST(v_total - (v_nuit + v_dimanche + v_ferie), 0);

  RETURN jsonb_build_object(
    'total_heures', ROUND(v_total::numeric, 1),
    'periode_jours', v_periode,
    'jour', ROUND(v_jour::numeric, 1),
    'nuit', ROUND(v_nuit::numeric, 1),
    'dimanche', ROUND(v_dimanche::numeric, 1),
    'ferie', ROUND(v_ferie::numeric, 1)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_repartition_heures_soignant(INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';

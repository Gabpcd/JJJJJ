-- J5.B.1.A — fn_rechercher_soignants_etab : recherche soignants côté étab.
-- RGPD-compliant : prénom + initiale nom, pas de coordonnées (téléphone/email/RPPS) avant contact.
-- Seuil <3 missions terminées : score_fiabilite masqué (NULL). Idem note si <3 évaluations.
-- Filtres dynamiques tous nullables. Distance Haversine (km) si étab a des coords.
-- Tri : score décroissant (NULL fin), puis note décroissante, puis missions terminées.

CREATE OR REPLACE FUNCTION public.fn_rechercher_soignants_etab(
  p_profession TEXT DEFAULT NULL,
  p_specialites TEXT[] DEFAULT NULL,
  p_ville TEXT DEFAULT NULL,
  p_distance_max_km INTEGER DEFAULT NULL,
  p_type_exercice TEXT DEFAULT NULL,
  p_note_min NUMERIC DEFAULT NULL,
  p_score_min INTEGER DEFAULT NULL,
  p_experience_min INTEGER DEFAULT NULL,
  p_disponible_urgence BOOLEAN DEFAULT NULL,
  p_documents_valides BOOLEAN DEFAULT NULL,
  p_recherche_texte TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID;
  v_etab_lat NUMERIC;
  v_etab_lng NUMERIC;
  v_limit INTEGER;
  v_offset INTEGER;
  v_result JSONB;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé : étab requis');
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  IF v_etab_id IS NOT NULL AND p_distance_max_km IS NOT NULL THEN
    SELECT adresse_lat, adresse_lng INTO v_etab_lat, v_etab_lng
    FROM etablissements WHERE id = v_etab_id;
  END IF;

  WITH filtered AS (
    SELECT
      s.id, s.prenom, s.nom, s.profession, s.specialite_medicale,
      s.type_exercice, s.score_fiabilite, s.note_moyenne, s.nb_evaluations,
      s.total_missions_terminees, s.annees_experience, s.specialites,
      s.bio, s.avatar_url, s.rpps_verifie, s.tous_documents_valides,
      s.disponible_urgence, s.adresse_ville,
      s.priorite_missions_urgentes, s.badge_ambassadeur,
      CASE
        WHEN v_etab_lat IS NOT NULL AND s.adresse_lat IS NOT NULL THEN
          ROUND((6371 * 2 * asin(sqrt(
            power(sin(radians(s.adresse_lat - v_etab_lat) / 2), 2) +
            cos(radians(v_etab_lat)) * cos(radians(s.adresse_lat)) *
            power(sin(radians(s.adresse_lng - v_etab_lng) / 2), 2)
          )))::NUMERIC, 1)
        ELSE NULL
      END AS distance_km
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND (p_profession IS NULL OR p_profession = '' OR s.profession::TEXT = p_profession)
      AND (p_specialites IS NULL OR array_length(p_specialites, 1) IS NULL OR s.specialites && p_specialites)
      AND (p_ville IS NULL OR p_ville = '' OR s.adresse_ville ILIKE '%' || p_ville || '%')
      AND (p_type_exercice IS NULL OR p_type_exercice = '' OR COALESCE(s.type_exercice, 'SALARIE') = p_type_exercice)
      AND (p_note_min IS NULL OR (COALESCE(s.nb_evaluations, 0) >= 3 AND COALESCE(s.note_moyenne, 0) >= p_note_min))
      AND (p_score_min IS NULL OR (COALESCE(s.total_missions_terminees, 0) >= 3 AND COALESCE(s.score_fiabilite, 0) >= p_score_min))
      AND (p_experience_min IS NULL OR COALESCE(s.annees_experience, 0) >= p_experience_min)
      AND (p_disponible_urgence IS NULL OR COALESCE(s.disponible_urgence, false) = p_disponible_urgence)
      AND (p_documents_valides IS NULL OR COALESCE(s.tous_documents_valides, false) = p_documents_valides)
      AND (p_recherche_texte IS NULL OR p_recherche_texte = '' OR
           s.prenom ILIKE '%' || p_recherche_texte || '%' OR
           COALESCE(s.bio, '') ILIKE '%' || p_recherche_texte || '%')
  ),
  with_distance AS (
    SELECT * FROM filtered
    WHERE p_distance_max_km IS NULL
       OR distance_km IS NULL
       OR distance_km <= p_distance_max_km
  ),
  ranked AS (
    SELECT *,
      ROW_NUMBER() OVER (ORDER BY
        CASE WHEN COALESCE(total_missions_terminees, 0) >= 3 THEN score_fiabilite ELSE -1 END DESC NULLS LAST,
        CASE WHEN COALESCE(nb_evaluations, 0) >= 3 THEN note_moyenne ELSE -1 END DESC NULLS LAST,
        COALESCE(total_missions_terminees, 0) DESC,
        id
      ) AS rn,
      COUNT(*) OVER () AS total_count
    FROM with_distance
  ),
  paged AS (
    SELECT * FROM ranked
    WHERE rn > v_offset AND rn <= v_offset + v_limit
  )
  SELECT jsonb_build_object(
    'soignants', COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'prenom', p.prenom,
      'nom_initiale', LEFT(p.nom, 1) || '.',
      'profession', p.profession::TEXT,
      'specialite_medicale', p.specialite_medicale,
      'type_exercice', COALESCE(p.type_exercice, 'SALARIE'),
      'score_fiabilite', CASE WHEN COALESCE(p.total_missions_terminees, 0) >= 3 THEN p.score_fiabilite ELSE NULL END,
      'note_moyenne', CASE WHEN COALESCE(p.nb_evaluations, 0) >= 3 THEN p.note_moyenne ELSE NULL END,
      'nb_evaluations', COALESCE(p.nb_evaluations, 0),
      'total_missions_terminees', COALESCE(p.total_missions_terminees, 0),
      'annees_experience', p.annees_experience,
      'specialites', COALESCE(p.specialites, ARRAY[]::TEXT[]),
      'bio_extrait', LEFT(COALESCE(p.bio, ''), 200),
      'avatar_url', p.avatar_url,
      'rpps_verifie', COALESCE(p.rpps_verifie, false),
      'tous_documents_valides', COALESCE(p.tous_documents_valides, false),
      'disponible_urgence', COALESCE(p.disponible_urgence, false),
      'ville', p.adresse_ville,
      'distance_km', p.distance_km,
      'priorite_missions_urgentes', COALESCE(p.priorite_missions_urgentes, false),
      'badge_ambassadeur', COALESCE(p.badge_ambassadeur, false)
    ) ORDER BY p.rn), '[]'::jsonb),
    'count_total', COALESCE(MAX(p.total_count), 0),
    'limit', v_limit,
    'offset', v_offset
  ) INTO v_result
  FROM paged p;

  RETURN COALESCE(v_result, jsonb_build_object('soignants', '[]'::jsonb, 'count_total', 0, 'limit', v_limit, 'offset', v_offset));
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_rechercher_soignants_etab(
  TEXT, TEXT[], TEXT, INTEGER, TEXT, NUMERIC, INTEGER, INTEGER, BOOLEAN, BOOLEAN, TEXT, INTEGER, INTEGER
) TO authenticated;

NOTIFY pgrst, 'reload schema';


DROP FUNCTION IF EXISTS public.fn_recommander_soignants(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.fn_recommander_soignants(
    p_mission_id UUID,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    prenom TEXT,
    nom TEXT,
    profession type_profession,
    score_fiabilite NUMERIC,
    distance_km NUMERIC,
    missions_etab INTEGER,
    score_matching NUMERIC,
    est_favori BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mission RECORD;
    v_etab RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE missions.id = p_mission_id;
    SELECT * INTO v_etab FROM etablissements WHERE etablissements.id = v_mission.etablissement_id;

    RETURN QUERY
    SELECT
        s.id,
        s.prenom, s.nom, s.profession,
        s.score_fiabilite,
        ROUND(
            (CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
                6371 * ACOS(
                    COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                    COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                    SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
                )
            ELSE 999 END)::numeric
        , 1) AS distance_km,
        (SELECT COUNT(*)::INTEGER FROM missions m2
         WHERE m2.soignant_assigne_id = s.id
           AND m2.etablissement_id = v_mission.etablissement_id
           AND m2.statut = 'TERMINEE') AS missions_etab,
        ROUND(
            (s.score_fiabilite * 0.4
            + LEAST(100, (SELECT COUNT(*) FROM missions m3
                WHERE m3.soignant_assigne_id = s.id
                  AND m3.etablissement_id = v_mission.etablissement_id
                  AND m3.statut = 'TERMINEE') * 10) * 0.3
            + CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
                GREATEST(0, 100 - (6371 * ACOS(
                    COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                    COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                    SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
                )))
              ELSE 0 END * 0.3
            + CASE WHEN EXISTS (
                SELECT 1 FROM favoris f
                WHERE f.soignant_id = s.id
                  AND f.etablissement_id = v_mission.etablissement_id
              ) THEN 20 ELSE 0 END)::numeric
        , 1) AS score_matching,
        EXISTS (
            SELECT 1 FROM favoris f
            WHERE f.soignant_id = s.id
              AND f.etablissement_id = v_mission.etablissement_id
        ) AS est_favori
    FROM soignants s
    WHERE s.profession = v_mission.profession_requise
      AND s.supprime_le IS NULL
      AND s.tous_documents_valides = TRUE
      AND s.id NOT IN (
          SELECT m4.soignant_assigne_id FROM missions m4
          WHERE m4.soignant_assigne_id IS NOT NULL
            AND m4.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m4.debut_le < v_mission.fin_le
            AND m4.fin_le > v_mission.debut_le
      )
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
    ORDER BY score_matching DESC
    LIMIT p_limit;
END;
$$;

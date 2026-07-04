-- Documents — étape 2b : gating PER-MISSION sur la DÉCOUVERTE établissement.
--
-- Ces fonctions excluaient les soignants sur le flag global `tous_documents_valides`
-- → un Mixte sans docs libéraux était retiré de TOUTES les recommandations, y compris
-- pour des missions salariées où il est éligible. On remplace le filtre par le check
-- per-mission fn_documents_ok_pour_mission :
--   • listes rattachées à UNE mission → régime de la mission (type_contrat_recherche) ;
--   • listes étab-level (pool/top/compteur, pas de mission unique) → 'TOUS' = sens le
--     moins exigeant (salarié). L'acceptation re-gate ensuite par régime (étape 2a).
-- Gain : réinjecte les soignants valides dans le pool de matching (remplissage).
-- La colonne informative tous_documents_valides des projections est conservée.

-- 1) Reco par mission
CREATE OR REPLACE FUNCTION public.fn_recommander_soignants(p_mission_id uuid, p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, prenom text, nom text, profession type_profession, score_fiabilite integer, distance_km numeric, missions_etab integer, missions_etablissement integer, score_matching numeric, est_favori boolean, type_exercice text, note_moyenne numeric, nb_evaluations integer, tous_documents_valides boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_mission RECORD;
    v_etab RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE missions.id = p_mission_id;
    IF v_mission IS NULL THEN RETURN; END IF;
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM v_mission.etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : mission non détenue par votre établissement' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_etab FROM etablissements WHERE etablissements.id = v_mission.etablissement_id;
    RETURN QUERY
    SELECT
        s.id, s.prenom, s.nom, s.profession,
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END,
        ROUND((CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
            )))
        ELSE 999 END)::NUMERIC, 1),
        (SELECT COUNT(*)::INTEGER FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = v_mission.etablissement_id AND m2.statut = 'TERMINEE'),
        (SELECT COUNT(*)::INTEGER FROM missions m2b WHERE m2b.soignant_assigne_id = s.id AND m2b.etablissement_id = v_mission.etablissement_id AND m2b.statut = 'TERMINEE') AS missions_etablissement,
        ROUND((COALESCE(s.score_fiabilite, 0) * 0.3
            + COALESCE(s.note_moyenne, 3) * 20 * 0.2
            + LEAST(100, (SELECT COUNT(*) FROM missions m3 WHERE m3.soignant_assigne_id = s.id AND m3.etablissement_id = v_mission.etablissement_id AND m3.statut = 'TERMINEE') * 10) * 0.2
            + CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
                GREATEST(0, 100 - (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                    COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                    COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                    SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
                )))))
              ELSE 0 END * 0.2
            + CASE WHEN EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id) THEN 20 ELSE 0 END
        )::NUMERIC, 1),
        EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id),
        COALESCE(s.type_exercice, 'SALARIE'),
        CASE WHEN COALESCE(s.nb_evaluations, 0) >= 3 THEN s.note_moyenne ELSE NULL END,
        COALESCE(s.nb_evaluations, 0),
        s.tous_documents_valides
    FROM soignants s
    WHERE s.profession = v_mission.profession_requise
      AND s.supprime_le IS NULL
      AND fn_documents_ok_pour_mission(s.id, v_mission.type_contrat_recherche::text)
      AND (v_mission.type_contrat_recherche IS NULL OR v_mission.type_contrat_recherche = 'TOUS' OR s.type_exercice = 'MIXTE'
          OR (v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice, 'SALARIE') IN ('SALARIE', 'MIXTE'))
          OR (v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')))
      AND (s.adresse_lat IS NULL OR v_etab.adresse_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
              COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
              SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
          )))) <= COALESCE(s.rayon_deplacement_km, 50))
      AND s.id NOT IN (
          SELECT m4.soignant_assigne_id FROM missions m4
          WHERE m4.soignant_assigne_id IS NOT NULL AND m4.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m4.debut_le < v_mission.fin_le AND m4.fin_le > v_mission.debut_le
      )
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
    ORDER BY est_favori DESC, score_matching DESC
    LIMIT p_limit;
END;
$function$;

-- 2) Pool urgence par mission
CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
 RETURNS TABLE(soignant_id uuid, id uuid, prenom text, nom text, score_fiabilite integer, distance_km numeric, urgence_rayon_km integer, telephone text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
BEGIN
    SELECT m.id, m.profession_requise, m.type_contrat_recherche, e.id AS etablissement_id, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    INTO v_mission FROM missions m JOIN etablissements e ON e.id = m.etablissement_id WHERE m.id = p_mission_id;
    IF NOT FOUND THEN RETURN; END IF;
    IF NOT (est_admin() OR COALESCE(v_mission.etablissement_id = mon_etablissement_id(), false)) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT s.id AS soignant_id, s.id, s.prenom::TEXT, s.nom::TEXT,
        COALESCE(s.score_fiabilite, 0)::INTEGER,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
                SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER, s.telephone::TEXT
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE AND s.supprime_le IS NULL
      AND fn_documents_ok_pour_mission(s.id, v_mission.type_contrat_recherche::text) AND s.profession = v_mission.profession_requise
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
      AND NOT EXISTS (SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le)
      AND (s.adresse_lat IS NULL OR v_mission.etab_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(v_mission.etab_lat)) * COS(RADIANS(s.adresse_lat)) *
              COS(RADIANS(s.adresse_lng) - RADIANS(v_mission.etab_lng)) +
              SIN(RADIANS(v_mission.etab_lat)) * SIN(RADIANS(s.adresse_lat))
          )))) <= COALESCE(s.urgence_rayon_km, 15))
    ORDER BY s.score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;

-- 3) Pool urgence étab-level (pas de mission unique) → défaut 'TOUS' (salarié).
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
 RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_etab RECORD;
BEGIN
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : pool urgence réservé à l''établissement' USING ERRCODE = '42501';
    END IF;
    SELECT e.id, e.adresse_lat, e.adresse_lng INTO v_etab FROM etablissements e WHERE e.id = p_etablissement_id;
    IF NOT FOUND THEN RETURN; END IF;
    RETURN QUERY
    SELECT
        s.id AS soignant_id,
        s.prenom::TEXT, s.nom::TEXT, s.profession::TEXT,
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END AS score_fiabilite,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER AS pool_urgence_rayon_km,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_etab.adresse_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_etab.adresse_lng)) +
                SIN(RADIANS(v_etab.adresse_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END AS distance_km,
        (SELECT COUNT(*)::BIGINT FROM missions m WHERE m.soignant_assigne_id = s.id AND COALESCE(m.est_urgente, FALSE) = TRUE AND m.statut = 'TERMINEE') AS missions_urgence_terminees,
        EXISTS(SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le) AS en_mission_maintenant,
        (SELECT MAX(m2.fin_le) FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = p_etablissement_id AND m2.statut = 'TERMINEE') AS derniere_mission_chez_nous,
        s.bio::TEXT, s.avatar_url::TEXT,
        EXISTS(SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = p_etablissement_id) AS est_favori
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE
      AND s.supprime_le IS NULL
      AND fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND NOT fn_est_exclu(s.id, p_etablissement_id)
      AND (
          s.profession IN (
              SELECT DISTINCT m.profession_requise FROM missions m
              WHERE m.etablissement_id = p_etablissement_id
              AND m.statut IN ('OUVERTE','ASSIGNEE','EN_COURS','ABSENCE','LITIGE')
          )
          OR NOT EXISTS (
              SELECT 1 FROM missions m WHERE m.etablissement_id = p_etablissement_id
              AND m.statut IN ('OUVERTE','ASSIGNEE','EN_COURS','ABSENCE','LITIGE')
          )
      )
    ORDER BY score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$;

-- 4) Top soignants (plateforme, par profession, pas de mission) → 'TOUS'.
CREATE OR REPLACE FUNCTION public.fn_top_soignants(p_profession text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, prenom text, nom text, profession text, note_moyenne numeric, nb_evaluations integer, score_fiabilite integer, total_missions_terminees integer)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.id, s.prenom, s.nom, s.profession::TEXT, s.note_moyenne, s.nb_evaluations,
           ROUND(COALESCE(s.score_fiabilite, 0))::integer AS score_fiabilite,
           s.total_missions_terminees
    FROM soignants s
    WHERE s.supprime_le IS NULL
    AND fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND (p_profession IS NULL OR s.profession::TEXT = p_profession)
    ORDER BY s.note_moyenne DESC NULLS LAST, s.score_fiabilite DESC, s.total_missions_terminees DESC
    LIMIT p_limit;
END;
$function$;

-- 5) Compteur soignants disponibles (étab-level) → 'TOUS'.
CREATE OR REPLACE FUNCTION public.fn_compteur_soignants_disponibles(p_etablissement_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(DISTINCT s.id) INTO v_count
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND s.derniere_activite_le > NOW() - INTERVAL '7 days'
      AND fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND s.profession IN (
          SELECT DISTINCT profession_requise FROM missions
          WHERE etablissement_id = p_etablissement_id AND statut = 'OUVERTE'
      )
      AND NOT fn_est_exclu(s.id, p_etablissement_id);
    RETURN jsonb_build_object('disponibles', v_count);
END;
$function$;

-- Itération 3 — Audit "patterns de failles connues" : 13 fixes critiques
--
-- 12 RPCs SECURITY DEFINER sans check d'autorisation (cross-tenant leaks/escalade)
-- + 1 idempotence credits_etablissement (double spend potentiel parrainage)
--
-- Bugs détectés et fixés :
-- 1. fn_auto_transitions_missions : INSERT massif → REVOKE authenticated (cron only)
-- 2. fn_auto_terminer_missions : UPDATE massif → REVOKE authenticated (cron only)
-- 3. fn_lister_missions_a_facturer : leak liste globale → REVOKE (cron only)
-- 4. fn_cumul_factures_mission : leak finance mission tierce → REVOKE (edge fn only)
-- 5. fn_verifier_pre_facturation : leak audit pré-facture tierce → REVOKE (edge fn only)
-- 6. fn_matching_soignants : leak matching → REVOKE (interne)
-- 7. fn_analytics_etablissement : leak KPIs étab tiers → check propriétaire/admin
-- 8. fn_alerte_cddu_repetitif : leak fréquences → check propriétaire
-- 9. fn_pool_urgence_etablissement : leak pool tiers → check propriétaire
-- 10. fn_recommander_soignants : leak soignants tiers → check propriétaire mission
-- 11. fn_user_id_pour_etablissement : impersonation → check auth.uid IS NOT NULL
-- 12. fn_ecrire_audit_safe : impersonation logs audit → force acteur_id = auth.uid()
-- 13. credits_etablissement : pas d'UNIQUE → 2 crédits possibles pour même parrainage

-- ─────────────────────────────────────────────────────
-- A. REVOKE authenticated sur RPCs internes/cron uniquement
-- ─────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.fn_auto_transitions_missions() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_auto_terminer_missions() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_lister_missions_a_facturer(date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_cumul_factures_mission(uuid, date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_verifier_pre_facturation(uuid, date, date) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_matching_soignants(uuid) FROM authenticated;

-- ─────────────────────────────────────────────────────
-- B. Patch fn_analytics_etablissement : check étab propriétaire OU admin
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_analytics_etablissement(p_etablissement_id uuid, p_mois integer DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_debut DATE;
  v_result JSONB;
  v_taux_remplissage NUMERIC;
  v_cout_heure_moyen NUMERIC;
  v_turnover NUMERIC;
  v_missions_par_mois JSONB;
  v_top_professions JSONB;
  v_soignants_recurrents JSONB;
BEGIN
  IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
    RETURN jsonb_build_object('error', 'Accès refusé : analytics réservées au propriétaire de l''établissement');
  END IF;

  v_debut := (CURRENT_DATE - (p_mois || ' months')::INTERVAL)::DATE;

  SELECT ROUND(COALESCE(
    COUNT(*) FILTER(WHERE soignant_assigne_id IS NOT NULL) * 100.0 / NULLIF(COUNT(*), 0)
  , 0), 1) INTO v_taux_remplissage
  FROM missions WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut;

  SELECT ROUND(COALESCE(AVG(CASE WHEN duree_heures > 0 THEN total_brut / duree_heures END), 0), 2) INTO v_cout_heure_moyen
  FROM missions WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND debut_le >= v_debut;

  SELECT ROUND(COALESCE(
    COUNT(DISTINCT soignant_assigne_id) FILTER(WHERE statut = 'TERMINEE') * 1.0 / NULLIF(COUNT(*) FILTER(WHERE statut = 'TERMINEE'), 0)
  , 0), 2) INTO v_turnover
  FROM missions WHERE etablissement_id = p_etablissement_id AND debut_le >= v_debut;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', mois, 'total', total, 'terminees', terminees, 'gmv', gmv
  ) ORDER BY mois), '[]'::jsonb) INTO v_missions_par_mois
  FROM (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS mois,
      COUNT(*) AS total,
      COUNT(*) FILTER(WHERE statut = 'TERMINEE') AS terminees,
      ROUND(COALESCE(SUM(total_brut) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS gmv
    FROM missions WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('profession', profession, 'nb', nb)), '[]'::jsonb) INTO v_top_professions
  FROM (
    SELECT profession_requise AS profession, COUNT(*) AS nb FROM missions
    WHERE etablissement_id = p_etablissement_id AND cree_le >= v_debut
    GROUP BY profession_requise ORDER BY nb DESC LIMIT 10
  ) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('soignant_id', soignant_id, 'nb_missions', nb_missions)), '[]'::jsonb) INTO v_soignants_recurrents
  FROM (
    SELECT soignant_assigne_id AS soignant_id, COUNT(*) AS nb_missions FROM missions
    WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND debut_le >= v_debut
      AND soignant_assigne_id IS NOT NULL
    GROUP BY soignant_assigne_id HAVING COUNT(*) > 1 ORDER BY nb_missions DESC LIMIT 10
  ) sub;

  v_result := jsonb_build_object(
    'taux_remplissage', v_taux_remplissage, 'cout_heure_moyen', v_cout_heure_moyen,
    'turnover', v_turnover, 'missions_par_mois', v_missions_par_mois,
    'top_professions', v_top_professions, 'soignants_recurrents', v_soignants_recurrents
  );
  RETURN v_result;
END;
$$;

-- ─────────────────────────────────────────────────────
-- C. Patch fn_alerte_cddu_repetitif : check étab propriétaire
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_alerte_cddu_repetitif(p_soignant_id uuid, p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_jours INTEGER;
BEGIN
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : alerte réservée à l''établissement' USING ERRCODE = '42501';
    END IF;

    SELECT COUNT(DISTINCT debut_le::DATE) INTO v_jours
    FROM missions
    WHERE soignant_assigne_id = p_soignant_id
      AND etablissement_id = p_etablissement_id
      AND statut = 'TERMINEE'
      AND debut_le > NOW() - INTERVAL '365 days';

    RETURN jsonb_build_object(
        'jours_12_mois', v_jours,
        'alerte', v_jours > 150,
        'message', CASE
            WHEN v_jours > 150 THEN 'Risque de requalification en CDI — ' || v_jours || ' jours travaillés sur 12 mois'
            ELSE NULL
        END
    );
END;
$function$;

-- ─────────────────────────────────────────────────────
-- D. Patch fn_pool_urgence_etablissement : check étab propriétaire
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_etab RECORD;
BEGIN
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : pool urgence réservé à l''établissement' USING ERRCODE = '42501';
    END IF;

    SELECT e.id, e.adresse_lat, e.adresse_lng INTO v_etab
    FROM etablissements e WHERE e.id = p_etablissement_id;
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
      AND s.tous_documents_valides = TRUE
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

-- ─────────────────────────────────────────────────────
-- E. Patch fn_recommander_soignants : check étab propriétaire de la mission
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_recommander_soignants(p_mission_id uuid, p_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, prenom text, nom text, profession type_profession, score_fiabilite integer, distance_km numeric, missions_etab integer, missions_etablissement integer, score_matching numeric, est_favori boolean, type_exercice text, note_moyenne numeric, nb_evaluations integer, tous_documents_valides boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
      AND s.tous_documents_valides = TRUE
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

-- ─────────────────────────────────────────────────────
-- F. Patch fn_user_id_pour_etablissement : check auth.uid IS NOT NULL
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_user_id_pour_etablissement(p_etablissement_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
STABLE
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;
  SELECT id INTO v_user_id FROM auth.users
  WHERE (raw_app_meta_data ->> 'etablissement_id')::uuid = p_etablissement_id
  LIMIT 1;
  RETURN v_user_id;
END;
$$;

-- ─────────────────────────────────────────────────────
-- G. Patch fn_ecrire_audit_safe : empêcher impersonation cross-user
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ecrire_audit_safe(
  p_acteur_id uuid, p_type_acteur text, p_action text,
  p_type_ressource text, p_id_ressource uuid,
  p_cle_s3 text DEFAULT NULL, p_details jsonb DEFAULT NULL,
  p_ip inet DEFAULT NULL, p_navigateur text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
  v_uid uuid := auth.uid();
  v_is_service boolean := COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_acteur_id uuid := p_acteur_id;
BEGIN
  -- Iter3 sec fix : empêcher impersonation cross-user dans audit log
  IF NOT v_is_service AND NOT est_admin() THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
    END IF;
    v_acteur_id := v_uid;
  END IF;

  INSERT INTO journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3, details, ip, navigateur
  ) VALUES (
    v_acteur_id, p_type_acteur, p_action, p_type_ressource, p_id_ressource,
    p_cle_s3, p_details, p_ip, p_navigateur
  ) RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ─────────────────────────────────────────────────────
-- H. Idempotence credits_etablissement : un parrainage = un crédit max
-- ─────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uniq_credits_etab_parrainage
  ON public.credits_etablissement(parrainage_id)
  WHERE parrainage_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';

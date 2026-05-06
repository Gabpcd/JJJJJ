-- J5.B.2.A — Dashboard étab : alertes + stats compléments + évolution missions

-- 1) RPC fn_alertes_dashboard_etab : missions 48h sans candidature + contrats SALARIE J-1 à uploader
CREATE OR REPLACE FUNCTION public.fn_alertes_dashboard_etab()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID;
  v_missions_orphelines JSONB;
  v_contrats_a_uploader JSONB;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
  END IF;

  -- Missions OUVERTE > 48h sans aucune candidature, début à venir
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'profession_requise', m.profession_requise::text,
    'debut_le', m.debut_le,
    'cree_le', m.cree_le,
    'taux_horaire_base', m.taux_horaire_base,
    'est_urgente', COALESCE(m.est_urgente, false),
    'jours_sans_candidature', EXTRACT(EPOCH FROM (NOW() - m.cree_le)) / 86400.0
  ) ORDER BY m.debut_le ASC), '[]'::jsonb)
  INTO v_missions_orphelines
  FROM missions m
  WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
    AND m.statut = 'OUVERTE'
    AND m.cree_le < NOW() - INTERVAL '48 hours'
    AND m.debut_le > NOW()
    AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id);

  -- Missions SALARIE J-1 sans contrat travail uploadé (étab-scope)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'debut_le', m.debut_le,
    'soignant_prenom', s.prenom,
    'soignant_nom_initiale', LEFT(s.nom, 1) || '.',
    'heures_avant_debut', ROUND((EXTRACT(EPOCH FROM (m.debut_le - NOW())) / 3600.0)::numeric, 1)
  ) ORDER BY m.debut_le ASC), '[]'::jsonb)
  INTO v_contrats_a_uploader
  FROM missions m
  JOIN soignants s ON s.id = m.soignant_assigne_id
  WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
    AND m.statut IN ('ASSIGNEE','EN_COURS')
    AND m.type_contrat_applique = 'SALARIE'
    AND m.debut_le >= NOW()
    AND m.debut_le < NOW() + INTERVAL '48 hours'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM contrats_travail_missions ct WHERE ct.mission_id = m.id);

  RETURN jsonb_build_object(
    'missions_sans_candidature_48h', v_missions_orphelines,
    'contrats_travail_a_uploader', v_contrats_a_uploader,
    'count_total',
      jsonb_array_length(v_missions_orphelines) + jsonb_array_length(v_contrats_a_uploader)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_alertes_dashboard_etab() TO authenticated;

-- 2) RPC fn_stats_etab_complements : compteurs supplémentaires pour les 3 composants existants
CREATE OR REPLACE FUNCTION public.fn_stats_etab_complements()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID;
  v_debut_mois TIMESTAMPTZ;
  v_debut_mois_precedent TIMESTAMPTZ;
  v_fin_mois_precedent TIMESTAMPTZ;
  v_soignants_mois_precedent INT;
  v_cout_brut_ce_mois NUMERIC;
  v_heures_ce_mois NUMERIC;
  v_missions_pourvues_ce_mois INT;
  v_missions_publiees_ce_mois INT;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  END IF;

  v_debut_mois := DATE_TRUNC('month', NOW());
  v_debut_mois_precedent := DATE_TRUNC('month', NOW() - INTERVAL '1 month');
  v_fin_mois_precedent := v_debut_mois;

  SELECT COUNT(DISTINCT soignant_assigne_id) INTO v_soignants_mois_precedent
  FROM missions
  WHERE (v_etab_id IS NULL OR etablissement_id = v_etab_id)
    AND soignant_assigne_id IS NOT NULL
    AND statut IN ('ASSIGNEE','EN_COURS','TERMINEE')
    AND debut_le >= v_debut_mois_precedent AND debut_le < v_fin_mois_precedent;

  SELECT COALESCE(SUM(total_brut), 0), COALESCE(SUM(duree_heures), 0)
  INTO v_cout_brut_ce_mois, v_heures_ce_mois
  FROM missions
  WHERE (v_etab_id IS NULL OR etablissement_id = v_etab_id)
    AND statut = 'TERMINEE' AND fin_le >= v_debut_mois;

  SELECT
    COUNT(*) FILTER (WHERE statut IN ('ASSIGNEE','EN_COURS','TERMINEE')),
    COUNT(*)
  INTO v_missions_pourvues_ce_mois, v_missions_publiees_ce_mois
  FROM missions
  WHERE (v_etab_id IS NULL OR etablissement_id = v_etab_id)
    AND cree_le >= v_debut_mois;

  RETURN jsonb_build_object(
    'soignants_mois_precedent', v_soignants_mois_precedent,
    'cout_brut_ce_mois', v_cout_brut_ce_mois,
    'heures_ce_mois', v_heures_ce_mois,
    'missions_pourvues_ce_mois', v_missions_pourvues_ce_mois,
    'missions_publiees_ce_mois', v_missions_publiees_ce_mois
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_stats_etab_complements() TO authenticated;

-- 3) RPC fn_evolution_missions_etab : 6 derniers mois (publiées / assignées / terminées)
CREATE OR REPLACE FUNCTION public.fn_evolution_missions_etab()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID;
  v_result JSONB;
  v_six_mois_ago DATE;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  END IF;

  v_six_mois_ago := DATE_TRUNC('month', NOW() - INTERVAL '5 months')::DATE;

  WITH mois_serie AS (
    SELECT (v_six_mois_ago + (n || ' months')::interval)::date AS mois_debut,
           (v_six_mois_ago + ((n+1) || ' months')::interval)::date AS mois_fin,
           TO_CHAR(v_six_mois_ago + (n || ' months')::interval, 'YYYY-MM') AS mois_label
    FROM generate_series(0, 5) AS n
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', ms.mois_label,
    'publiees', (
      SELECT COUNT(*) FROM missions m
      WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
        AND m.cree_le >= ms.mois_debut AND m.cree_le < ms.mois_fin
    ),
    'assignees', (
      SELECT COUNT(*) FROM missions m
      WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
        AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE')
        AND m.cree_le >= ms.mois_debut AND m.cree_le < ms.mois_fin
    ),
    'terminees', (
      SELECT COUNT(*) FROM missions m
      WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
        AND m.statut = 'TERMINEE'
        AND m.fin_le >= ms.mois_debut AND m.fin_le < ms.mois_fin
    )
  ) ORDER BY ms.mois_label), '[]'::jsonb)
  INTO v_result
  FROM mois_serie ms;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_evolution_missions_etab() TO authenticated;

NOTIFY pgrst, 'reload schema';

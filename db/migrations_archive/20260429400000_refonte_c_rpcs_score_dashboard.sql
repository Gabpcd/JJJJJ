-- Refonte.C — RPCs pour pages score (soignant + étab)

-- 1) fn_evolution_score_soignant : 6 derniers snapshots breakdown (1 par mois max) pour graph LineChart
CREATE OR REPLACE FUNCTION public.fn_evolution_score_soignant(p_limit INT DEFAULT 6)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
  v_limit INT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 6), 1), 50);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', mois_label, 'score', ROUND(score::numeric, 1),
    'niveau', niveau, 'cree_le', cree_le
  ) ORDER BY mois_label ASC), '[]'::jsonb) INTO v_result
  FROM (
    SELECT DISTINCT ON (TO_CHAR(cree_le, 'YYYY-MM'))
      TO_CHAR(cree_le, 'YYYY-MM') AS mois_label,
      score_total AS score, niveau::text AS niveau, cree_le
    FROM scoring_breakdown
    WHERE soignant_id = v_uid AND cree_le >= NOW() - (v_limit || ' months')::interval
    ORDER BY TO_CHAR(cree_le, 'YYYY-MM'), cree_le DESC
  ) t;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_evolution_score_soignant(INT) TO authenticated;

-- 2) fn_mon_breakdown_actuel : dernier snapshot
CREATE OR REPLACE FUNCTION public.fn_mon_breakdown_actuel()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT to_jsonb(b.*) INTO v_result FROM scoring_breakdown b
  WHERE b.soignant_id = v_uid ORDER BY b.cree_le DESC LIMIT 1;
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mon_breakdown_actuel() TO authenticated;

-- 3) fn_mon_score_etab : composantes calculées on-the-fly pour breakdown UI
CREATE OR REPLACE FUNCTION public.fn_mon_score_etab()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID := mon_etablissement_id();
  v_result JSONB;
  v_since TIMESTAMPTZ := NOW() - INTERVAL '12 months';
  v_nb_notations INT;
  v_notation_pct NUMERIC;
  v_total_factures INT;
  v_factures_a_temps INT;
  v_paiement_pct NUMERIC;
  v_nb_litiges INT;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_pct
  FROM notations_missions
  WHERE note_id = v_etab_id AND sens = 'SOIGNANT_VERS_ETAB' AND cree_le >= v_since AND masque = false;

  IF v_nb_notations < 3 OR v_notation_pct IS NULL THEN v_notation_pct := NULL;
  ELSE v_notation_pct := GREATEST(0, LEAST(100, (v_notation_pct - 1) * 25)); END IF;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE date_paiement IS NOT NULL AND date_paiement <= date_echeance)
  INTO v_total_factures, v_factures_a_temps
  FROM factures
  WHERE etablissement_id = v_etab_id AND statut = 'PAYEE' AND COALESCE(date_emission, cree_le) >= v_since;

  IF v_total_factures = 0 THEN v_paiement_pct := NULL;
  ELSE v_paiement_pct := (v_factures_a_temps::NUMERIC / v_total_factures) * 100; END IF;

  SELECT COUNT(*) INTO v_nb_litiges FROM litiges
  WHERE etablissement_id = v_etab_id
    AND statut IN ('RESOLU_SOIGNANT', 'RESOLU_FAVEUR_SOIGNANT')
    AND COALESCE(resolu_le, NOW()) >= v_since;

  SELECT jsonb_build_object(
    'score_qualite', e.score_qualite, 'niveau', e.niveau,
    'composantes', jsonb_build_object(
      'notation_pct', v_notation_pct, 'nb_notations', v_nb_notations,
      'paiement_pct', v_paiement_pct, 'nb_factures', v_total_factures,
      'nb_litiges_perdus', v_nb_litiges
    )
  ) INTO v_result FROM etablissements e WHERE e.id = v_etab_id;

  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mon_score_etab() TO authenticated;

-- 4) fn_score_etab_public : récupère score d'un étab pour soignant ayant eu une mission avec lui
CREATE OR REPLACE FUNCTION public.fn_score_etab_public(p_etab_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_a_eu_mission BOOLEAN := false;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT EXISTS (SELECT 1 FROM missions WHERE etablissement_id = p_etab_id AND soignant_assigne_id = v_uid)
  INTO v_a_eu_mission;
  IF NOT v_a_eu_mission AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  SELECT jsonb_build_object(
    'etablissement_id', e.id, 'nom', e.nom,
    'score_qualite', e.score_qualite, 'niveau', e.niveau
  ) INTO v_result FROM etablissements e WHERE e.id = p_etab_id;
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_score_etab_public(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Sprint 6 PR 3 — RPC évaluations soignant avec filtres + stats (P1-3)
-- ============================================================================
-- Page /soignant/evaluations dédiée nécessite filtres (période, note, étab)
-- + KPIs (note moyenne, total, % 5★, évolution 6 mois) + pagination.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_mes_notations_recues_avec_stats(
  p_periode text DEFAULT 'TOUT',         -- '3M' | '6M' | '12M' | 'TOUT'
  p_note_min int DEFAULT NULL,           -- 1..5
  p_etablissement_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid := public.mon_etablissement_id();
  v_target_id uuid;
  v_target_sens public.sens_notation;
  v_seuil_periode timestamptz;
  v_total int;
  v_notations jsonb;
  v_stats jsonb;
  v_etabs_disponibles jsonb;
  v_evolution jsonb;
  v_limit int;
BEGIN
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);

  IF v_etab_id IS NOT NULL THEN
    v_target_id := v_etab_id;
    v_target_sens := 'SOIGNANT_VERS_ETAB';
  ELSIF v_uid IS NOT NULL THEN
    v_target_id := v_uid;
    v_target_sens := 'ETAB_VERS_SOIGNANT';
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_seuil_periode := CASE p_periode
    WHEN '3M' THEN now() - INTERVAL '3 months'
    WHEN '6M' THEN now() - INTERVAL '6 months'
    WHEN '12M' THEN now() - INTERVAL '12 months'
    ELSE '1900-01-01'::timestamptz
  END;

  -- Total filtré
  SELECT COUNT(*) INTO v_total
  FROM public.notations_missions n
  JOIN public.missions m ON m.id = n.mission_id
  WHERE n.note_id = v_target_id
    AND n.sens = v_target_sens
    AND n.masque = false
    AND n.cree_le > v_seuil_periode
    AND (p_note_min IS NULL OR ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1) >= p_note_min)
    AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id);

  -- Liste paginée
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'mission_id', x.mission_id,
    'mission_intitule', x.mission_intitule,
    'mission_fin_le', x.mission_fin_le,
    'etablissement_id', x.etablissement_id,
    'etablissement_nom', x.etablissement_nom,
    'critere_1', x.critere_1,
    'critere_2', x.critere_2,
    'critere_3', x.critere_3,
    'critere_4', x.critere_4,
    'note_moyenne', ROUND(((x.critere_1 + x.critere_2 + x.critere_3 + x.critere_4) / 4.0)::numeric, 1),
    'commentaire', x.commentaire,
    'signale', x.signale,
    'cree_le', x.cree_le
  ) ORDER BY x.cree_le DESC), '[]'::jsonb)
  INTO v_notations
  FROM (
    SELECT n.id, n.mission_id, m.intitule AS mission_intitule, m.fin_le AS mission_fin_le,
           m.etablissement_id, e.nom AS etablissement_nom,
           n.critere_1, n.critere_2, n.critere_3, n.critere_4, n.commentaire, n.signale, n.cree_le
    FROM public.notations_missions n
    JOIN public.missions m ON m.id = n.mission_id
    LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE n.note_id = v_target_id
      AND n.sens = v_target_sens
      AND n.masque = false
      AND n.cree_le > v_seuil_periode
      AND (p_note_min IS NULL OR ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1) >= p_note_min)
      AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id)
    ORDER BY n.cree_le DESC
    LIMIT v_limit OFFSET p_offset
  ) x;

  -- Stats globales (toutes périodes, pas de filtres pour avoir une vue globale)
  SELECT jsonb_build_object(
    'note_moyenne_globale', COALESCE(ROUND(AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1), 0),
    'total_evaluations', COUNT(*),
    'pct_5_etoiles', CASE WHEN COUNT(*) > 0
      THEN ROUND(100.0 * SUM(CASE WHEN (n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) >= 19 THEN 1 ELSE 0 END) / COUNT(*), 1)
      ELSE 0 END
  )
  INTO v_stats
  FROM public.notations_missions n
  WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false;

  -- Évolution 6 derniers mois (note moyenne par mois)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', to_char(x.mois, 'YYYY-MM'),
    'note_moyenne', ROUND(x.moyenne::numeric, 1),
    'nb', x.nb
  ) ORDER BY x.mois), '[]'::jsonb)
  INTO v_evolution
  FROM (
    SELECT date_trunc('month', n.cree_le) AS mois,
           AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0) AS moyenne,
           COUNT(*) AS nb
    FROM public.notations_missions n
    WHERE n.note_id = v_target_id
      AND n.sens = v_target_sens
      AND n.masque = false
      AND n.cree_le > now() - INTERVAL '6 months'
    GROUP BY 1
  ) x;

  -- Liste étabs ayant évalué le soignant (pour dropdown filtre)
  -- (uniquement pour sens ETAB_VERS_SOIGNANT, sinon liste les soignants — moins pertinent côté soignant)
  IF v_target_sens = 'ETAB_VERS_SOIGNANT' THEN
    SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', e.id, 'nom', e.nom)), '[]'::jsonb)
    INTO v_etabs_disponibles
    FROM public.notations_missions n
    JOIN public.missions m ON m.id = n.mission_id
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false;
  ELSE
    v_etabs_disponibles := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', v_limit,
    'offset', p_offset,
    'notations', v_notations,
    'stats', v_stats,
    'evolution_6m', v_evolution,
    'etabs_disponibles', v_etabs_disponibles
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_mes_notations_recues_avec_stats(text, int, uuid, int, int) TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT6_PR3_RPC_EVALUATIONS_STATS_INSTALLED',
    'pr', 'PR 3 Sprint 6',
    'rpc', 'fn_mes_notations_recues_avec_stats'
  )
);

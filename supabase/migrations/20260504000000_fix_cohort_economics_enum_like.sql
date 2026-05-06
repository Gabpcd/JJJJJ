-- Fix fn_admin_cohort_economics : statut est un enum `statut_mission`,
-- l'opérateur LIKE ne supporte pas les enums. Remplacer par IN(...) exact.
--
-- Erreur avant fix :
-- ERROR 42883: operator does not exist: statut_mission ~~ unknown
-- HINT: No operator matches the given name and argument types.

CREATE OR REPLACE FUNCTION public.fn_admin_cohort_economics(p_mois integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debut DATE := (CURRENT_DATE - (p_mois || ' months')::INTERVAL)::DATE;
  v_result JSONB;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès admin uniquement');
  END IF;

  WITH monthly_signups AS (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS cohorte,
      COUNT(*) FILTER(WHERE TRUE) AS nouveaux_soignants
    FROM soignants WHERE cree_le >= v_debut AND supprime_le IS NULL
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ),
  monthly_etab AS (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS cohorte,
      COUNT(*) AS nouveaux_etabs
    FROM etablissements WHERE cree_le >= v_debut AND supprime_le IS NULL
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ),
  monthly_missions AS (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS mois,
      COUNT(*) AS total_missions,
      COUNT(*) FILTER(WHERE statut = 'TERMINEE') AS missions_terminees,
      COUNT(*) FILTER(WHERE statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')) AS missions_annulees,
      ROUND(COALESCE(SUM(total_brut) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS gmv,
      ROUND(COALESCE(SUM(montant_commission_ht) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS commission_ht,
      ROUND(COALESCE(SUM(montant_commission_ttc) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS commission_ttc,
      COUNT(DISTINCT soignant_assigne_id) FILTER(WHERE statut = 'TERMINEE') AS soignants_actifs,
      COUNT(DISTINCT etablissement_id) FILTER(WHERE statut = 'TERMINEE') AS etabs_actifs,
      ROUND(COALESCE(AVG(duree_heures) FILTER(WHERE statut = 'TERMINEE'), 0), 1) AS duree_moyenne_h
    FROM missions WHERE cree_le >= v_debut
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ),
  retention AS (
    SELECT m1.mois,
      COUNT(DISTINCT m1.sid) AS actifs,
      COUNT(DISTINCT m2.sid) AS retenus_mois_suivant
    FROM (
      SELECT DISTINCT TO_CHAR(debut_le, 'YYYY-MM') AS mois, soignant_assigne_id AS sid
      FROM missions WHERE statut = 'TERMINEE' AND debut_le >= v_debut
    ) m1
    LEFT JOIN (
      SELECT DISTINCT TO_CHAR(debut_le, 'YYYY-MM') AS mois, soignant_assigne_id AS sid
      FROM missions WHERE statut = 'TERMINEE' AND debut_le >= v_debut
    ) m2 ON m2.sid = m1.sid AND m2.mois = TO_CHAR((TO_DATE(m1.mois, 'YYYY-MM') + INTERVAL '1 month'), 'YYYY-MM')
    GROUP BY m1.mois
  ),
  unit_eco AS (
    SELECT
      ROUND(COALESCE(SUM(montant_commission_ttc) / NULLIF(COUNT(DISTINCT etablissement_id), 0), 0), 2) AS arpu_etab,
      ROUND(COALESCE(SUM(total_brut) / NULLIF(COUNT(DISTINCT soignant_assigne_id), 0), 0), 2) AS rev_per_soignant,
      ROUND(COALESCE(SUM(montant_commission_ht) / NULLIF(COUNT(*), 0), 0), 2) AS commission_par_mission,
      ROUND(COALESCE(AVG(CASE WHEN duree_heures > 0 THEN montant_commission_ht / duree_heures END), 0), 2) AS commission_par_heure,
      ROUND(COALESCE(AVG(CASE WHEN duree_heures > 0 THEN total_brut / duree_heures END), 0), 2) AS gmv_par_heure,
      ROUND(COUNT(*) FILTER(WHERE statut = 'TERMINEE') * 100.0 / NULLIF(COUNT(*), 1), 1) AS taux_completion,
      ROUND(COUNT(*) FILTER(WHERE statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')) * 100.0 / NULLIF(COUNT(*), 1), 1) AS taux_annulation
    FROM missions WHERE cree_le >= v_debut AND statut = 'TERMINEE'
  ),
  totals AS (
    SELECT
      (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL) AS total_soignants,
      (SELECT COUNT(*) FROM etablissements WHERE supprime_le IS NULL) AS total_etabs,
      (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE') AS total_missions_terminees,
      (SELECT ROUND(COALESCE(SUM(total_brut), 0), 2) FROM missions WHERE statut = 'TERMINEE') AS gmv_total,
      (SELECT ROUND(COALESCE(SUM(montant_commission_ttc), 0), 2) FROM missions WHERE statut = 'TERMINEE') AS revenue_total
  )
  SELECT jsonb_build_object(
    'cohortes_mensuelles', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'mois', mm.mois, 'nouveaux_soignants', COALESCE(ms.nouveaux_soignants, 0),
        'nouveaux_etabs', COALESCE(me.nouveaux_etabs, 0),
        'missions', COALESCE(mm.total_missions, 0),
        'missions_terminees', COALESCE(mm.missions_terminees, 0),
        'gmv', COALESCE(mm.gmv, 0),
        'commission_ht', COALESCE(mm.commission_ht, 0),
        'commission_ttc', COALESCE(mm.commission_ttc, 0),
        'soignants_actifs', COALESCE(mm.soignants_actifs, 0),
        'etabs_actifs', COALESCE(mm.etabs_actifs, 0),
        'duree_moyenne_h', COALESCE(mm.duree_moyenne_h, 0)
      ) ORDER BY mm.mois), '[]'::jsonb)
      FROM monthly_missions mm
      LEFT JOIN monthly_signups ms ON ms.cohorte = mm.mois
      LEFT JOIN monthly_etab me ON me.cohorte = mm.mois
    ),
    'retention_mensuelle', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'mois', r.mois, 'actifs', r.actifs, 'retenus', r.retenus_mois_suivant,
        'taux_retention', CASE WHEN r.actifs > 0 THEN ROUND(r.retenus_mois_suivant * 100.0 / r.actifs, 1) ELSE 0 END
      ) ORDER BY r.mois), '[]'::jsonb)
      FROM retention r
    ),
    'unit_economics', (SELECT row_to_json(ue)::jsonb FROM unit_eco ue),
    'totals', (SELECT row_to_json(t)::jsonb FROM totals t)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';

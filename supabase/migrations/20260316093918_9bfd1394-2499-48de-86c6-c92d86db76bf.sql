
-- fn_admin_kpi : retourne les KPI globaux pour le dashboard admin
CREATE OR REPLACE FUNCTION public.fn_admin_kpi()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
  debut_semaine timestamp with time zone := date_trunc('week', now());
  debut_mois timestamp with time zone := date_trunc('month', now());
BEGIN
  SELECT jsonb_build_object(
    'soignants_total', (SELECT count(*) FROM soignants),
    'soignants_semaine', (SELECT count(*) FROM soignants WHERE cree_le >= debut_semaine),
    'etablissements_total', (SELECT count(*) FROM etablissements WHERE supprime_le IS NULL),
    'etablissements_semaine', (SELECT count(*) FROM etablissements WHERE supprime_le IS NULL AND cree_le >= debut_semaine),
    'missions_terminees_total', (SELECT count(*) FROM missions WHERE statut = 'TERMINEE'),
    'missions_terminees_mois', (SELECT count(*) FROM missions WHERE statut = 'TERMINEE' AND modifie_le >= debut_mois),
    'missions_ouvertes', (SELECT count(*) FROM missions WHERE statut = 'OUVERTE'),
    'ca_commissions_ht_mois', COALESCE((SELECT sum(montant_commission_ht) FROM missions WHERE statut = 'TERMINEE' AND modifie_le >= debut_mois), 0),
    'ca_commissions_ht_total', COALESCE((SELECT sum(montant_commission_ht) FROM missions WHERE statut = 'TERMINEE'), 0),
    'taux_acceptation_mois', (
      SELECT CASE WHEN count(*) > 0
        THEN round(count(*) FILTER (WHERE statut IN ('ASSIGNEE','EN_COURS','TERMINEE'))::numeric / count(*)::numeric * 100)
        ELSE 0 END
      FROM missions WHERE cree_le >= debut_mois
    ),
    'score_fiabilite_moyen', COALESCE((SELECT round(avg(score_fiabilite)) FROM soignants WHERE score_fiabilite IS NOT NULL), 0)
  ) INTO result;
  RETURN result;
END;
$$;

-- fn_admin_graphiques : retourne les données pour les graphiques admin
CREATE OR REPLACE FUNCTION public.fn_admin_graphiques()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'missions_par_semaine', COALESCE((
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.semaine)
      FROM (
        SELECT date_trunc('week', modifie_le)::date AS semaine, count(*) AS total
        FROM missions
        WHERE statut = 'TERMINEE' AND modifie_le >= now() - interval '12 weeks'
        GROUP BY 1
        ORDER BY 1
      ) t
    ), '[]'::jsonb),
    'ca_par_mois', COALESCE((
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.mois)
      FROM (
        SELECT date_trunc('month', modifie_le)::date AS mois, COALESCE(sum(montant_commission_ht), 0) AS ca_ht
        FROM missions
        WHERE statut = 'TERMINEE' AND modifie_le >= now() - interval '6 months'
        GROUP BY 1
        ORDER BY 1
      ) t
    ), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

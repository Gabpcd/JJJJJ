CREATE OR REPLACE FUNCTION fn_admin_kpi()
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
    -- CA gagné = missions terminées avec contrat signé
    'ca_commissions_ht_mois', COALESCE((
      SELECT sum(m.montant_commission_ht)
      FROM missions m
      WHERE m.statut = 'TERMINEE'
        AND m.modifie_le >= debut_mois
        AND EXISTS (SELECT 1 FROM contrats_mission c WHERE c.mission_id = m.id AND c.statut = 'SIGNE_COMPLET')
    ), 0),
    'ca_commissions_ht_total', COALESCE((
      SELECT sum(m.montant_commission_ht)
      FROM missions m
      WHERE m.statut = 'TERMINEE'
        AND EXISTS (SELECT 1 FROM contrats_mission c WHERE c.mission_id = m.id AND c.statut = 'SIGNE_COMPLET')
    ), 0),
    -- CA potentiel = missions pourvues (assignées + en cours + terminées), pas les ouvertes
    'ca_potentiel_mois', COALESCE((
      SELECT sum(montant_commission_ht)
      FROM missions
      WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        AND debut_le >= debut_mois
    ), 0),
    'ca_potentiel_total', COALESCE((
      SELECT sum(montant_commission_ht)
      FROM missions
      WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    ), 0),
    -- CA encaissé = factures payées
    'ca_encaisse_total', COALESCE((
      SELECT sum(montant_ht) FROM factures WHERE statut = 'PAYEE'
    ), 0),
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
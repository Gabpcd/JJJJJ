
CREATE OR REPLACE FUNCTION public.fn_admin_conformite()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT est_admin() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;

    RETURN jsonb_build_object(
        'violations_repos_11h', (SELECT COUNT(*) FROM conformite_travail WHERE resultat != 'CONFORME' AND controle_le > NOW() - INTERVAL '30 days'),
        'alertes_48h', (SELECT COUNT(*) FROM soignants s WHERE (SELECT COALESCE(SUM(duree_heures),0) FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut IN ('ASSIGNEE', 'EN_COURS') AND m.debut_le > DATE_TRUNC('week', NOW())) > 44),
        'docs_expires', (SELECT COUNT(*) FROM documents_soignants WHERE statut_verification = 'EXPIRE' AND supprime_le IS NULL),
        'docs_en_attente', (SELECT COUNT(*) FROM documents_soignants WHERE statut_verification = 'EN_ATTENTE' AND supprime_le IS NULL),
        'cddu_repetitifs', COALESCE((SELECT COUNT(*) FROM (SELECT 1 FROM missions WHERE statut = 'TERMINEE' GROUP BY soignant_assigne_id, etablissement_id HAVING COUNT(DISTINCT debut_le::DATE) > 150) sub), 0),
        'soignants_sans_docs', (SELECT COUNT(*) FROM soignants WHERE tous_documents_valides = FALSE AND supprime_le IS NULL),
        'missions_sans_contrat', (SELECT COUNT(*) FROM missions m WHERE m.statut IN ('ASSIGNEE', 'EN_COURS') AND NOT EXISTS (SELECT 1 FROM contrats_mission c WHERE c.mission_id = m.id AND c.statut = 'SIGNE_COMPLET'))
    );
END;
$$;

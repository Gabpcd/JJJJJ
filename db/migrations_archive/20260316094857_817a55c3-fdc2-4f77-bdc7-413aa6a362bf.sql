
CREATE OR REPLACE FUNCTION public.fn_admin_conformite_detail(p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT est_admin() THEN RETURN '[]'::jsonb; END IF;

  CASE p_type
    WHEN 'violations_repos_11h' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.controle_le DESC)
        FROM (
          SELECT ct.id, ct.type_controle, ct.resultat, ct.controle_le,
                 ct.details_violation,
                 s.prenom || ' ' || s.nom AS soignant_nom,
                 m.intitule AS mission_intitule,
                 e.nom AS etablissement_nom
          FROM conformite_travail ct
          JOIN soignants s ON s.id = ct.soignant_id
          JOIN missions m ON m.id = ct.mission_id
          JOIN etablissements e ON e.id = m.etablissement_id
          WHERE ct.resultat != 'CONFORME' AND ct.controle_le > NOW() - INTERVAL '30 days'
          ORDER BY ct.controle_le DESC LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'alertes_48h' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t))
        FROM (
          SELECT s.id, s.prenom || ' ' || s.nom AS soignant_nom, s.profession,
                 COALESCE(SUM(m.duree_heures), 0) AS heures_semaine
          FROM soignants s
          JOIN missions m ON m.soignant_assigne_id = s.id
            AND m.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m.debut_le > DATE_TRUNC('week', NOW())
          GROUP BY s.id, s.prenom, s.nom, s.profession
          HAVING SUM(m.duree_heures) > 44
          ORDER BY SUM(m.duree_heures) DESC LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'docs_expires' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t))
        FROM (
          SELECT d.id, d.type_document, d.nom_fichier, d.valide_jusqua,
                 s.prenom || ' ' || s.nom AS soignant_nom, s.profession
          FROM documents_soignants d
          JOIN soignants s ON s.id = d.soignant_id
          WHERE d.statut_verification = 'EXPIRE' AND d.supprime_le IS NULL
          ORDER BY d.valide_jusqua ASC LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'docs_en_attente' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t))
        FROM (
          SELECT d.id, d.type_document, d.nom_fichier, d.televerse_le,
                 s.prenom || ' ' || s.nom AS soignant_nom, s.profession
          FROM documents_soignants d
          JOIN soignants s ON s.id = d.soignant_id
          WHERE d.statut_verification = 'EN_ATTENTE' AND d.supprime_le IS NULL
          ORDER BY d.televerse_le DESC LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'cddu_repetitifs' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t))
        FROM (
          SELECT s.prenom || ' ' || s.nom AS soignant_nom, e.nom AS etablissement_nom,
                 COUNT(*) AS nb_missions,
                 MIN(m.debut_le)::date AS premiere_mission,
                 MAX(m.fin_le)::date AS derniere_mission
          FROM missions m
          JOIN soignants s ON s.id = m.soignant_assigne_id
          JOIN etablissements e ON e.id = m.etablissement_id
          WHERE m.statut = 'TERMINEE'
          GROUP BY m.soignant_assigne_id, m.etablissement_id, s.prenom, s.nom, e.nom
          HAVING COUNT(DISTINCT m.debut_le::DATE) > 150
          ORDER BY COUNT(*) DESC LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'soignants_sans_docs' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t))
        FROM (
          SELECT s.id, s.prenom || ' ' || s.nom AS soignant_nom, s.profession,
                 s.cree_le, s.email
          FROM soignants s
          WHERE s.tous_documents_valides = FALSE AND s.supprime_le IS NULL
          ORDER BY s.cree_le DESC LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'missions_sans_contrat' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t))
        FROM (
          SELECT m.id, m.intitule, m.debut_le, m.fin_le, m.statut,
                 e.nom AS etablissement_nom,
                 s.prenom || ' ' || s.nom AS soignant_nom
          FROM missions m
          JOIN etablissements e ON e.id = m.etablissement_id
          LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
          WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
            AND NOT EXISTS (SELECT 1 FROM contrats_mission c WHERE c.mission_id = m.id AND c.statut = 'SIGNE_COMPLET')
          ORDER BY m.debut_le ASC LIMIT 50
        ) t
      ), '[]'::jsonb);

    ELSE
      RETURN '[]'::jsonb;
  END CASE;
END;
$$;

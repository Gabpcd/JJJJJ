-- Autoriser l'envoi de messages mission aussi quand la mission est terminée
DROP POLICY IF EXISTS pol_msg_insert ON public.messages_mission;

CREATE POLICY pol_msg_insert
ON public.messages_mission
FOR INSERT
TO authenticated
WITH CHECK (
  (auteur_id = auth.uid())
  AND (
    est_admin()
    OR (
      mission_id IN (
        SELECT missions.id
        FROM public.missions
        WHERE (
          (
            (missions.soignant_assigne_id = auth.uid())
            OR (missions.etablissement_id = mon_etablissement_id())
          )
          AND missions.statut = ANY (ARRAY['ASSIGNEE'::statut_mission, 'EN_COURS'::statut_mission, 'TERMINEE'::statut_mission])
        )
      )
    )
  )
);

-- Enrichir les détails conformité avec les IDs et une mission liée pour rendre les lignes cliquables partout
CREATE OR REPLACE FUNCTION public.fn_admin_conformite_detail(p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN '[]'::jsonb;
  END IF;

  CASE p_type
    WHEN 'violations_repos_11h' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.controle_le DESC)
        FROM (
          SELECT
            ct.id,
            ct.type_controle,
            ct.resultat,
            ct.controle_le,
            ct.details_violation,
            ct.soignant_id,
            ct.mission_id,
            m.etablissement_id,
            s.prenom || ' ' || s.nom AS soignant_nom,
            m.intitule AS mission_intitule,
            e.nom AS etablissement_nom
          FROM public.conformite_travail ct
          JOIN public.soignants s ON s.id = ct.soignant_id
          JOIN public.missions m ON m.id = ct.mission_id
          JOIN public.etablissements e ON e.id = m.etablissement_id
          WHERE ct.resultat <> 'CONFORME'
            AND ct.controle_le > NOW() - INTERVAL '30 days'
          ORDER BY ct.controle_le DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'alertes_48h' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.heures_semaine DESC)
        FROM (
          SELECT
            s.id AS soignant_id,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            hs.heures_semaine,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM (
            SELECT
              m.soignant_assigne_id,
              COALESCE(SUM(m.duree_heures), 0) AS heures_semaine
            FROM public.missions m
            WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
              AND m.debut_le > DATE_TRUNC('week', NOW())
            GROUP BY m.soignant_assigne_id
            HAVING SUM(m.duree_heures) > 44
          ) hs
          JOIN public.soignants s ON s.id = hs.soignant_assigne_id
          LEFT JOIN LATERAL (
            SELECT
              m2.id AS mission_id,
              m2.intitule AS mission_intitule,
              m2.etablissement_id,
              e2.nom AS etablissement_nom
            FROM public.missions m2
            LEFT JOIN public.etablissements e2 ON e2.id = m2.etablissement_id
            WHERE m2.soignant_assigne_id = s.id
              AND m2.statut IN ('ASSIGNEE', 'EN_COURS')
              AND m2.debut_le > DATE_TRUNC('week', NOW())
            ORDER BY m2.debut_le ASC
            LIMIT 1
          ) rm ON TRUE
          ORDER BY hs.heures_semaine DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'docs_expires' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.valide_jusqua ASC)
        FROM (
          SELECT
            d.id,
            d.soignant_id,
            d.type_document,
            d.nom_fichier,
            d.valide_jusqua,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM public.documents_soignants d
          JOIN public.soignants s ON s.id = d.soignant_id
          LEFT JOIN LATERAL (
            SELECT
              m.id AS mission_id,
              m.intitule AS mission_intitule,
              m.etablissement_id,
              e.nom AS etablissement_nom
            FROM public.missions m
            LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.soignant_assigne_id = d.soignant_id
            ORDER BY
              CASE
                WHEN m.statut IN ('EN_COURS', 'ASSIGNEE') THEN 0
                WHEN m.statut = 'TERMINEE' THEN 1
                ELSE 2
              END,
              m.debut_le DESC
            LIMIT 1
          ) rm ON TRUE
          WHERE d.statut_verification = 'EXPIRE'
            AND d.supprime_le IS NULL
          ORDER BY d.valide_jusqua ASC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'docs_en_attente' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.televerse_le DESC)
        FROM (
          SELECT
            d.id,
            d.soignant_id,
            d.type_document,
            d.nom_fichier,
            d.televerse_le,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM public.documents_soignants d
          JOIN public.soignants s ON s.id = d.soignant_id
          LEFT JOIN LATERAL (
            SELECT
              m.id AS mission_id,
              m.intitule AS mission_intitule,
              m.etablissement_id,
              e.nom AS etablissement_nom
            FROM public.missions m
            LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.soignant_assigne_id = d.soignant_id
            ORDER BY
              CASE
                WHEN m.statut IN ('EN_COURS', 'ASSIGNEE') THEN 0
                WHEN m.statut = 'TERMINEE' THEN 1
                ELSE 2
              END,
              m.debut_le DESC
            LIMIT 1
          ) rm ON TRUE
          WHERE d.statut_verification = 'EN_ATTENTE'
            AND d.supprime_le IS NULL
          ORDER BY d.televerse_le DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'cddu_repetitifs' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.nb_missions DESC)
        FROM (
          SELECT
            base.soignant_id,
            base.etablissement_id,
            base.soignant_nom,
            base.etablissement_nom,
            base.nb_missions,
            base.premiere_mission,
            base.derniere_mission,
            rm.mission_id,
            rm.mission_intitule
          FROM (
            SELECT
              m.soignant_assigne_id AS soignant_id,
              m.etablissement_id,
              s.prenom || ' ' || s.nom AS soignant_nom,
              e.nom AS etablissement_nom,
              COUNT(*) AS nb_missions,
              MIN(m.debut_le)::date AS premiere_mission,
              MAX(m.fin_le)::date AS derniere_mission
            FROM public.missions m
            JOIN public.soignants s ON s.id = m.soignant_assigne_id
            JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.statut = 'TERMINEE'
            GROUP BY m.soignant_assigne_id, m.etablissement_id, s.prenom, s.nom, e.nom
            HAVING COUNT(DISTINCT m.debut_le::date) > 150
          ) base
          LEFT JOIN LATERAL (
            SELECT
              m2.id AS mission_id,
              m2.intitule AS mission_intitule
            FROM public.missions m2
            WHERE m2.soignant_assigne_id = base.soignant_id
              AND m2.etablissement_id = base.etablissement_id
            ORDER BY m2.fin_le DESC
            LIMIT 1
          ) rm ON TRUE
          ORDER BY base.nb_missions DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'soignants_sans_docs' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.cree_le DESC)
        FROM (
          SELECT
            s.id AS soignant_id,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            s.cree_le,
            s.email,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM public.soignants s
          LEFT JOIN LATERAL (
            SELECT
              m.id AS mission_id,
              m.intitule AS mission_intitule,
              m.etablissement_id,
              e.nom AS etablissement_nom
            FROM public.missions m
            LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.soignant_assigne_id = s.id
            ORDER BY
              CASE
                WHEN m.statut IN ('EN_COURS', 'ASSIGNEE') THEN 0
                WHEN m.statut = 'TERMINEE' THEN 1
                ELSE 2
              END,
              m.debut_le DESC
            LIMIT 1
          ) rm ON TRUE
          WHERE s.tous_documents_valides = FALSE
            AND s.supprime_le IS NULL
          ORDER BY s.cree_le DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'missions_sans_contrat' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.debut_le ASC)
        FROM (
          SELECT
            m.id AS mission_id,
            m.id,
            m.intitule,
            m.debut_le,
            m.fin_le,
            m.statut,
            m.etablissement_id,
            s.id AS soignant_id,
            e.nom AS etablissement_nom,
            s.prenom || ' ' || s.nom AS soignant_nom
          FROM public.missions m
          JOIN public.etablissements e ON e.id = m.etablissement_id
          LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
          WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
            AND NOT EXISTS (
              SELECT 1
              FROM public.contrats_mission c
              WHERE c.mission_id = m.id
                AND c.statut = 'SIGNE_COMPLET'
            )
          ORDER BY m.debut_le ASC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    ELSE
      RETURN '[]'::jsonb;
  END CASE;
END;
$function$;
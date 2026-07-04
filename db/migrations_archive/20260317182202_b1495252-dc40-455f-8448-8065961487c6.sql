
-- Fonction d'assignation admin: permet d'assigner un soignant spécifique à une mission
CREATE OR REPLACE FUNCTION public.fn_assigner_mission_admin(p_mission_id UUID, p_soignant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_etab RECORD;
    v_type_contrat TEXT;
    v_numero TEXT;
    v_html TEXT;
    v_heures_semaine NUMERIC;
    v_debut_semaine TIMESTAMPTZ;
    v_fin_semaine TIMESTAMPTZ;
BEGIN
    -- Vérifier que l'appelant est admin ou admin_etablissement
    IF NOT (est_admin() OR est_admin_etablissement()) THEN
        RETURN '{"error":"Non autorisé"}'::JSONB;
    END IF;

    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN '{"error":"Cette mission n''est plus disponible"}'::JSONB; END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN '{"error":"Soignant introuvable"}'::JSONB; END IF;

    SELECT * INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

    -- Vérification 48h hebdomadaires pour le soignant cible
    v_debut_semaine := DATE_TRUNC('week', v_mission.debut_le);
    v_fin_semaine := v_debut_semaine + INTERVAL '7 days';

    SELECT COALESCE(SUM(duree_heures), 0) INTO v_heures_semaine
    FROM missions
    WHERE soignant_assigne_id = p_soignant_id
      AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
      AND debut_le >= v_debut_semaine
      AND debut_le < v_fin_semaine;

    IF v_heures_semaine + COALESCE(v_mission.duree_heures, 0) > 48 THEN
        RETURN jsonb_build_object('error',
            'Assigner cette mission ferait dépasser 48h/semaine pour ce soignant (' ||
            ROUND(v_heures_semaine, 1) || 'h déjà planifiées). Art. L.3121-20 du Code du travail.');
    END IF;

    v_type_contrat := CASE WHEN v_soignant.type_contrat = 'LIBERAL' THEN 'REMPLACEMENT_LIBERAL' ELSE 'CDDU' END;

    UPDATE missions SET
        soignant_assigne_id = p_soignant_id,
        statut = 'ASSIGNEE',
        modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';

    v_numero := fn_generer_numero_contrat(v_type_contrat);

    SELECT contenu_html INTO v_html
    FROM templates_contrat
    WHERE type_contrat = v_type_contrat AND est_actif = TRUE
    LIMIT 1;

    IF v_html IS NOT NULL THEN
        v_html := REPLACE(v_html, '{{etablissement_nom}}', COALESCE(v_etab.nom, ''));
        v_html := REPLACE(v_html, '{{etablissement_siret}}', COALESCE(v_etab.siret, ''));
        v_html := REPLACE(v_html, '{{etablissement_finess}}', COALESCE(v_etab.finess, 'N/A'));
        v_html := REPLACE(v_html, '{{etablissement_adresse}}', COALESCE(v_etab.adresse_rue || ', ' || v_etab.adresse_code_postal || ' ' || v_etab.adresse_ville, ''));
        v_html := REPLACE(v_html, '{{soignant_prenom}}', COALESCE(v_soignant.prenom, ''));
        v_html := REPLACE(v_html, '{{soignant_nom}}', COALESCE(v_soignant.nom, ''));
        v_html := REPLACE(v_html, '{{soignant_rpps}}', COALESCE(v_soignant.numero_rpps, ''));
        v_html := REPLACE(v_html, '{{soignant_siret}}', COALESCE(v_soignant.siret_liberal, ''));
        v_html := REPLACE(v_html, '{{profession}}', COALESCE(v_soignant.profession::TEXT, ''));
        v_html := REPLACE(v_html, '{{service}}', COALESCE(v_mission.service, ''));
        v_html := REPLACE(v_html, '{{debut_date}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{debut_heure}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
        v_html := REPLACE(v_html, '{{fin_date}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{fin_heure}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
        v_html := REPLACE(v_html, '{{duree_heures}}', COALESCE(v_mission.duree_heures::TEXT, ''));
        v_html := REPLACE(v_html, '{{taux_horaire}}', COALESCE(v_mission.taux_horaire_base::TEXT, ''));
        v_html := REPLACE(v_html, '{{numero_contrat}}', v_numero);
        v_html := REPLACE(v_html, '{{date_signature}}', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
        v_html := REPLACE(v_html, '{{lieu}}', COALESCE(v_etab.adresse_ville, ''));
    END IF;

    INSERT INTO contrats_mission (
        mission_id, etablissement_id, soignant_id,
        type_contrat, numero_contrat, contenu_html, statut
    ) VALUES (
        p_mission_id, v_mission.etablissement_id, p_soignant_id,
        v_type_contrat, v_numero, v_html, 'EN_ATTENTE_SIGNATURES'
    );

    RETURN jsonb_build_object('success', true, 'contrat_numero', v_numero);
END;
$$;

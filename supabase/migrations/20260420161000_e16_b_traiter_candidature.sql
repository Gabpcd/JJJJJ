-- ============================================================
-- E16 — Micro-passe 1B : fn_traiter_candidature lit choix soignant
-- ============================================================
-- Supprime le fallback CASE arbitraire qui figeait SALARIE/CDDU
-- pour tous les soignants MIXTE, cause du bug URSSAF E16.
-- Lit candidature.type_contrat_choisi et persiste sur missions
-- les 4 champs cohérents : type_contrat_applique,
-- choix_contrat_soignant, type_paiement_soignant,
-- mode_paiement_soignant.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_traiter_candidature(
  p_candidature_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_cand RECORD; v_mission RECORD; v_soignant RECORD; v_etab RECORD;
    v_jours_avant NUMERIC; v_rcp_valide BOOLEAN;
    v_heures_semaine NUMERIC; v_debut_semaine TIMESTAMPTZ; v_fin_semaine TIMESTAMPTZ;
    v_type_contrat TEXT; v_numero TEXT; v_html TEXT;
    v_choix_applique TEXT;
    v_type_paiement TEXT; v_mode_paiement TEXT;
BEGIN
    SELECT * INTO v_cand FROM candidatures WHERE id = p_candidature_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Candidature introuvable'); END IF;

    SELECT * INTO v_mission FROM missions WHERE id = v_cand.mission_id;
    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Non autorisé');
    END IF;

    IF p_decision = 'ACCEPTEE' THEN
        SELECT * INTO v_soignant FROM soignants WHERE id = v_cand.soignant_id;
        SELECT * INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

        IF v_soignant.profession != v_mission.profession_requise THEN
            RETURN jsonb_build_object('error', 'Ce soignant est ' || v_soignant.profession::TEXT || ', la mission requiert un(e) ' || v_mission.profession_requise::TEXT || '.');
        END IF;

        IF fn_est_exclu(v_cand.soignant_id, v_mission.etablissement_id) THEN
            RETURN jsonb_build_object('error', 'Ce soignant est dans la liste d''exclusions.');
        END IF;

        IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') = 'LIBERAL' THEN
            RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.');
        END IF;
        IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
            RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.');
        END IF;

        -- E16 : déterminer le choix applique
        -- 1. Cas MIXTE × TOUS : EXIGE choix persisté dans candidature
        IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
            IF v_cand.type_contrat_choisi IS NULL OR v_cand.type_contrat_choisi NOT IN ('SALARIE', 'LIBERAL') THEN
                RETURN jsonb_build_object(
                    'error', 'E16_CANDIDATURE_ORPHELINE',
                    'message', 'Candidature soumise avant correctif E16 : demander au soignant de re-candidater avec son choix de contrat (salarié ou libéral).',
                    'candidature_id', p_candidature_id
                );
            END IF;
            v_choix_applique := v_cand.type_contrat_choisi;
        -- 2. Autres cas : déduire déterministe (mission force OU soignant n'a qu'un type)
        ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN
            v_choix_applique := 'SALARIE';
        ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
            v_choix_applique := 'LIBERAL';
        ELSIF v_cand.type_contrat_choisi IN ('SALARIE', 'LIBERAL') THEN
            -- Si candidature a un choix persisté (ex. via fn_postuler_mission v2), on le respecte
            v_choix_applique := v_cand.type_contrat_choisi;
        ELSE
            -- Mission TOUS × soignant SALARIE pur OU LIBERAL pur
            v_choix_applique := COALESCE(v_soignant.type_exercice, 'SALARIE');
        END IF;

        -- Docs si < 7 jours
        v_jours_avant := EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 86400;
        IF v_jours_avant < 7 THEN
            IF v_soignant.tous_documents_valides IS NOT TRUE THEN
                RETURN jsonb_build_object('error', 'Documents non validés et mission < 7 jours.');
            END IF;
            SELECT EXISTS(
                SELECT 1 FROM documents_soignants
                WHERE soignant_id = v_cand.soignant_id AND type_document = 'RCP_ASSURANCE'
                AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
                AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
            ) INTO v_rcp_valide;
            IF NOT v_rcp_valide THEN
                RETURN jsonb_build_object('error', 'RCP expirée ou manquante.');
            END IF;
        END IF;

        -- Plafond 48h applicable seulement si mode salarié appliqué
        IF v_choix_applique = 'SALARIE' THEN
            v_debut_semaine := DATE_TRUNC('week', v_mission.debut_le);
            v_fin_semaine := v_debut_semaine + INTERVAL '7 days';
            SELECT COALESCE(SUM(duree_heures), 0) INTO v_heures_semaine
            FROM missions WHERE soignant_assigne_id = v_cand.soignant_id
              AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
              AND debut_le >= v_debut_semaine AND debut_le < v_fin_semaine;
            IF v_heures_semaine + COALESCE(v_mission.duree_heures, 0) > 48 THEN
                RETURN jsonb_build_object('error', 'Dépasse 48h/semaine (' || ROUND(v_heures_semaine, 1) || 'h planifiées).');
            END IF;
        END IF;

        -- E16 : dérivation cohérente des 4 champs missions selon v_choix_applique
        IF v_choix_applique = 'LIBERAL' THEN
            v_type_contrat := 'REMPLACEMENT_LIBERAL';
            v_type_paiement := 'NOTE_HONORAIRES';
            v_mode_paiement := 'STRIPE_CONNECT';
        ELSE
            v_type_contrat := 'CDDU';
            v_type_paiement := 'BULLETIN_PAIE';
            v_mode_paiement := 'DIRECT';
        END IF;

        -- Accept + reject others
        UPDATE candidatures SET statut = 'ACCEPTEE', traite_le = NOW() WHERE id = p_candidature_id;
        UPDATE candidatures SET statut = 'REFUSEE', motif_refus = 'Un autre candidat a été sélectionné', traite_le = NOW()
        WHERE mission_id = v_cand.mission_id AND id != p_candidature_id AND statut = 'EN_ATTENTE';

        UPDATE missions SET
            soignant_assigne_id = v_cand.soignant_id,
            statut = 'ASSIGNEE',
            type_contrat_applique = v_choix_applique::type_contrat_applique_enum,
            choix_contrat_soignant = v_choix_applique,
            type_paiement_soignant = v_type_paiement,
            mode_paiement_soignant = v_mode_paiement,
            modifie_le = NOW()
        WHERE id = v_cand.mission_id;

        v_numero := fn_generer_numero_contrat(v_type_contrat);

        SELECT contenu_html INTO v_html FROM templates_contrat
        WHERE type_contrat = v_type_contrat AND est_actif = TRUE LIMIT 1;

        IF v_html IS NOT NULL THEN
            v_html := REPLACE(v_html, '{{etablissement_nom}}', fn_html_escape(v_etab.nom));
            v_html := REPLACE(v_html, '{{etablissement_siret}}', fn_html_escape(v_etab.siret));
            v_html := REPLACE(v_html, '{{etablissement_finess}}', fn_html_escape(COALESCE(v_etab.finess, 'N/A')));
            v_html := REPLACE(v_html, '{{etablissement_adresse}}', fn_html_escape(COALESCE(v_etab.adresse_rue || ', ' || v_etab.adresse_code_postal || ' ' || v_etab.adresse_ville, '')));
            v_html := REPLACE(v_html, '{{soignant_prenom}}', fn_html_escape(v_soignant.prenom));
            v_html := REPLACE(v_html, '{{soignant_nom}}', fn_html_escape(v_soignant.nom));
            v_html := REPLACE(v_html, '{{soignant_rpps}}', fn_html_escape(COALESCE(v_soignant.numero_rpps, '')));
            v_html := REPLACE(v_html, '{{profession}}', fn_html_escape(COALESCE(v_soignant.profession::TEXT, '')));
            v_html := REPLACE(v_html, '{{debut_date}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
            v_html := REPLACE(v_html, '{{debut_heure}}', TO_CHAR(v_mission.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
            v_html := REPLACE(v_html, '{{fin_date}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
            v_html := REPLACE(v_html, '{{fin_heure}}', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'));
            v_html := REPLACE(v_html, '{{duree_heures}}', COALESCE(v_mission.duree_heures::TEXT, ''));
            v_html := REPLACE(v_html, '{{taux_horaire}}', COALESCE(v_mission.taux_horaire_base::TEXT, ''));
            v_html := REPLACE(v_html, '{{numero_contrat}}', fn_html_escape(v_numero));
            v_html := REPLACE(v_html, '{{date_signature}}', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'));
            v_html := REPLACE(v_html, '{{lieu}}', fn_html_escape(COALESCE(v_etab.adresse_ville, '')));
        END IF;

        INSERT INTO contrats_mission (mission_id, etablissement_id, soignant_id,
            type_contrat, numero_contrat, contenu_html, statut
        ) VALUES (v_cand.mission_id, v_mission.etablissement_id, v_cand.soignant_id,
            v_type_contrat, v_numero, v_html, 'EN_ATTENTE_SIGNATURES');

        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_cand.soignant_id, 'CANDIDATURE_ACCEPTEE', 'Candidature acceptee',
            'Votre candidature pour "' || fn_html_escape(v_mission.intitule) || '" a ete acceptee. Signez votre contrat.',
            '/soignant/missions', 'SOIGNANT');

    ELSIF p_decision = 'REFUSEE' THEN
        UPDATE candidatures SET statut = 'REFUSEE', motif_refus = p_motif, traite_le = NOW() WHERE id = p_candidature_id;

        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_cand.soignant_id, 'CANDIDATURE_REFUSEE', 'Candidature non retenue',
            'Votre candidature pour "' || fn_html_escape(v_mission.intitule) || '" n''a pas ete retenue.' ||
            CASE WHEN p_motif IS NOT NULL THEN ' Motif : ' || fn_html_escape(p_motif) ELSE '' END,
            '/soignant/missions', 'SOIGNANT');
    ELSE
        RETURN jsonb_build_object('error', 'Décision invalide');
    END IF;

    RETURN jsonb_build_object('success', true, 'choix_applique', v_choix_applique);
END;
$function$;

COMMENT ON FUNCTION public.fn_traiter_candidature(uuid, text, text) IS
  'E16 — Lit candidature.type_contrat_choisi, RAISE E16_CANDIDATURE_ORPHELINE si MIXTE×TOUS sans choix, persiste 4 champs missions cohérents.';

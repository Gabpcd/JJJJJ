-- Lot 1 launch blockers (1/3) — Activation soignant :
-- ① Soft-gating documents : la candidature est TOUJOURS possible (le blocage
--    documents reste à l'ACCEPTATION par l'établissement pour les missions < 7 jours,
--    et à l'assignation directe PREMIER_ARRIVE). Nudge RAPPEL_DOCUMENTS automatique.
-- ② Préférence de contrat MIXTE mémorisée (soignants.preference_contrat_mixte) :
--    plus de dialog à chaque candidature.
-- ③ Fix race condition fn_accepter_mission : l'UPDATE ne vérifiait pas ROW_COUNT —
--    deux soignants simultanés recevaient tous deux "success" sur le pool urgence.

-- ② Colonne préférence contrat (soignants MIXTE)
ALTER TABLE public.soignants ADD COLUMN IF NOT EXISTS preference_contrat_mixte text
  CHECK (preference_contrat_mixte IN ('SALARIE','LIBERAL'));

-- ① + ② fn_postuler_mission
CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_soignant RECORD; v_rcp_valide BOOLEAN; v_choix_final TEXT;
    v_compatible BOOLEAN; v_specialite_label TEXT; v_choix_effectif TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'CANDIDATURE' THEN RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
      RETURN jsonb_build_object('error',
        'Votre compte est ' || v_soignant.statut_compte::text || '. Vous ne pouvez plus candidater. Pour faire un recours, écrivez à bonjour@jolene.app.');
    END IF;

    v_compatible := fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
      v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises);

    IF NOT v_compatible THEN
      IF v_mission.profession_requise = 'MEDECIN' AND v_mission.specialite_medicale_requise IS NOT NULL
         AND v_soignant.profession = 'MEDECIN' THEN
        SELECT label INTO v_specialite_label FROM specialites_medicales WHERE code = v_mission.specialite_medicale_requise;
        RETURN jsonb_build_object('error', 'Cette mission requiert la spécialité ' ||
          COALESCE(v_specialite_label, v_mission.specialite_medicale_requise) || '.');
      ELSIF v_mission.profession_requise IN ('IBODE', 'IADE') AND v_soignant.profession = 'IDE'
            AND COALESCE(v_mission.accepte_non_specialises, true) = false THEN
        RETURN jsonb_build_object('error', 'Cette mission ' || v_mission.profession_requise::text || ' n''accepte pas les IDE non spécialisés.');
      ELSE
        RETURN jsonb_build_object('error', 'Votre profession ne correspond pas à la mission requise (' || v_mission.profession_requise::text || ').');
      END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.'); END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.'); END IF;

    -- MIXTE + TOUS : le choix explicite prime, sinon la préférence mémorisée du profil.
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Veuillez choisir votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    END IF;

    IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_final := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_final := 'LIBERAL';
    ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_final := v_choix_effectif;
    ELSE v_choix_final := COALESCE(v_soignant.type_exercice, 'SALARIE'); END IF;

    -- RCP : exigence légale conservée pour candidater en libéral.
    IF v_choix_final = 'LIBERAL' THEN
        SELECT EXISTS(SELECT 1 FROM documents_soignants WHERE soignant_id = auth.uid() AND type_document = 'RCP_ASSURANCE'
            AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
            AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
        IF NOT v_rcp_valide THEN
            RETURN jsonb_build_object('error', 'Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée — obligatoire pour candidater en libéral. Téléversez-la dans vos documents (ou candidatez en salarié si la mission le permet).');
        END IF;
    END IF;

    -- Soft-gating : plus de blocage documents à la candidature (le contrôle reste à
    -- l'acceptation pour les missions < 7 jours, cf. fn_traiter_candidature).

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission'); END IF;

    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, auth.uid(), fn_html_escape(p_message), 'EN_ATTENTE', v_choix_final);

    -- Nudge documents : la candidature part, mais l'acceptation exigera des documents
    -- validés si la mission démarre sous 7 jours. Max 1 rappel / 24h.
    IF v_soignant.tous_documents_valides IS NOT TRUE THEN
        IF NOT EXISTS (
            SELECT 1 FROM notifications
            WHERE destinataire_id = auth.uid() AND type = 'RAPPEL_DOCUMENTS'
              AND cree_le > NOW() - INTERVAL '24 hours'
        ) THEN
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (auth.uid(), 'RAPPEL_DOCUMENTS', 'Validez vos documents pour être accepté',
                'Votre candidature est envoyée ! Pour que l''établissement puisse vous accepter, vos documents doivent être validés (vérification automatique en quelques minutes).',
                '/soignant/mes-documents', 'SOIGNANT');
        END IF;
        RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final, 'docs_a_completer', TRUE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final);
END;
$function$;

-- ② + ③ fn_accepter_mission (PREMIER_ARRIVE)
CREATE OR REPLACE FUNCTION public.fn_accepter_mission(p_mission_id uuid, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_type_paiement TEXT;
    v_mode_paiement TEXT;
    v_type_contrat_gen TEXT;
    v_numero_contrat TEXT;
    v_contrat_id UUID;
    v_choix_effectif TEXT;
    v_rows INT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'PREMIER_ARRIVE' THEN RETURN jsonb_build_object('error', 'Cette mission nécessite une candidature'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Profession incompatible.');
    END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux salariés.');
    END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux libéraux.');
    END IF;

    -- MIXTE + TOUS → choix explicite ou préférence mémorisée
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Choisissez votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD / bulletin de paie)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    ELSE
        v_choix_effectif := p_choix_contrat;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    -- Assignation immédiate = travail imminent : documents validés obligatoires (légal).
    IF v_soignant.tous_documents_valides IS NOT TRUE THEN
        RETURN jsonb_build_object('error', 'Vos documents doivent être validés pour accepter une mission en direct. Téléversez-les dans Mes documents — la vérification automatique prend quelques minutes.');
    END IF;

    -- Déterminer type paiement
    IF v_soignant.type_exercice = 'LIBERAL' OR (v_soignant.type_exercice = 'MIXTE' AND (v_choix_effectif = 'LIBERAL' OR v_mission.type_contrat_recherche = 'LIBERAL')) THEN
        v_type_paiement := 'NOTE_HONORAIRES';
        v_mode_paiement := 'STRIPE_CONNECT';
        v_type_contrat_gen := 'LIBERAL';
    ELSE
        v_type_paiement := 'BULLETIN_PAIE';
        v_mode_paiement := 'DIRECT';
        v_type_contrat_gen := 'CDD';
    END IF;

    -- Claim atomique : si un autre soignant a pris la mission entre le SELECT et ici,
    -- l'UPDATE ne touche aucune ligne → on s'arrête (fix race condition pool urgence).
    UPDATE missions SET
        soignant_assigne_id = auth.uid(), statut = 'ASSIGNEE',
        choix_contrat_soignant = v_choix_effectif,
        type_paiement_soignant = v_type_paiement,
        mode_paiement_soignant = v_mode_paiement,
        modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RETURN jsonb_build_object('error', 'Cette mission vient d''être prise par un autre soignant (déjà prise).');
    END IF;

    v_numero_contrat := fn_generer_numero_contrat_safe(v_type_contrat_gen);

    INSERT INTO contrats_mission (
        mission_id, etablissement_id, soignant_id,
        type_contrat, numero_contrat, statut
    ) VALUES (
        p_mission_id, v_mission.etablissement_id, auth.uid(),
        v_type_contrat_gen, v_numero_contrat, 'EN_ATTENTE_SIGNATURES'
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_contrat_id;

    IF v_contrat_id IS NULL THEN
        SELECT id INTO v_contrat_id FROM contrats_mission
        WHERE mission_id = p_mission_id
        ORDER BY cree_le DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'contrat_id', v_contrat_id,
        'contrat_numero', v_numero_contrat,
        'type_paiement', v_type_paiement,
        'mode_paiement', v_mode_paiement
    );
END;
$function$;

-- ① fn_traiter_candidature : message explicite + re-nudge automatique du soignant
-- quand l'acceptation échoue pour documents non validés (mission < 7 jours).
-- Corps intégralement repris de la version prod, seule la branche docs change.
CREATE OR REPLACE FUNCTION public.fn_traiter_candidature(p_candidature_id uuid, p_decision text, p_motif text DEFAULT NULL::text)
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

        IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
            IF v_cand.type_contrat_choisi IS NULL OR v_cand.type_contrat_choisi NOT IN ('SALARIE', 'LIBERAL') THEN
                RETURN jsonb_build_object(
                    'error', 'E16_CANDIDATURE_ORPHELINE',
                    'message', 'Candidature soumise avant correctif E16 : demander au soignant de re-candidater avec son choix de contrat (salarié ou libéral).',
                    'candidature_id', p_candidature_id
                );
            END IF;
            v_choix_applique := v_cand.type_contrat_choisi;
        ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN
            v_choix_applique := 'SALARIE';
        ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
            v_choix_applique := 'LIBERAL';
        ELSIF v_cand.type_contrat_choisi IN ('SALARIE', 'LIBERAL') THEN
            v_choix_applique := v_cand.type_contrat_choisi;
        ELSE
            v_choix_applique := COALESCE(v_soignant.type_exercice, 'SALARIE');
        END IF;

        -- Docs si < 7 jours : blocage conservé (légal) mais message actionnable
        -- + relance automatique du soignant (max 1 / 6h).
        v_jours_avant := EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 86400;
        IF v_jours_avant < 7 THEN
            IF v_soignant.tous_documents_valides IS NOT TRUE THEN
                INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
                SELECT v_cand.soignant_id, 'RAPPEL_DOCUMENTS', 'Un établissement veut vous accepter !',
                    'L''établissement a tenté d''accepter votre candidature pour "' || fn_html_escape(v_mission.intitule) || '" mais vos documents ne sont pas encore validés. Validez-les vite pour décrocher la mission.',
                    '/soignant/mes-documents', 'SOIGNANT'
                WHERE NOT EXISTS (
                    SELECT 1 FROM notifications
                    WHERE destinataire_id = v_cand.soignant_id AND type = 'RAPPEL_DOCUMENTS'
                      AND cree_le > NOW() - INTERVAL '6 hours');
                RETURN jsonb_build_object('error', 'Les documents de ce soignant sont en cours de vérification — il vient d''être relancé automatiquement. Réessayez dès que son badge documents passe au vert.');
            END IF;
            -- RCP exigée uniquement pour une mission en LIBÉRAL (un salarié est couvert par l'employeur).
            IF v_choix_applique = 'LIBERAL' THEN
                SELECT EXISTS(
                    SELECT 1 FROM documents_soignants
                    WHERE soignant_id = v_cand.soignant_id AND type_document = 'RCP_ASSURANCE'
                    AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
                    AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
                ) INTO v_rcp_valide;
                IF NOT v_rcp_valide THEN
                    RETURN jsonb_build_object('error', 'RCP expirée ou manquante — obligatoire pour une mission en libéral.');
                END IF;
            END IF;
        END IF;

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

        IF v_choix_applique = 'LIBERAL' THEN
            v_type_contrat := 'REMPLACEMENT_LIBERAL';
            v_type_paiement := 'NOTE_HONORAIRES';
            v_mode_paiement := 'STRIPE_CONNECT';
        ELSE
            v_type_contrat := 'CDD';
            v_type_paiement := 'BULLETIN_PAIE';
            v_mode_paiement := 'DIRECT';
        END IF;

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

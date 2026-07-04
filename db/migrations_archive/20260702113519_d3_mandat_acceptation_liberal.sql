-- D3 (Lot 6c) — Pipeline par type_exercice, côté mandat :
-- 1. À l'ACCEPTATION d'une candidature LIBERALE d'un soignant sans mandat →
--    notification deep-link « Signe ton mandat pour confirmer ta mission »
--    (la paperasse couplée au pic de motivation).
-- 2. Gate : une mission LIBERALE ne peut pas DÉMARRER (ASSIGNEE → EN_COURS)
--    sans mandat signé — zéro cas « mission faite, facture impossible ».
-- Le mandat n'est JAMAIS exigé sur un chemin salarié (art. 289 I-2 CGI).

-- 1) Gate au démarrage
CREATE OR REPLACE FUNCTION public.fn_trg_verifier_mandat_avant_debut()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $fn_vmad$
BEGIN
  IF NEW.type_contrat_applique = 'LIBERAL' AND NEW.soignant_assigne_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM soignants s
      WHERE s.id = NEW.soignant_assigne_id AND s.mandat_facturation_signe IS TRUE
    ) THEN
      RAISE EXCEPTION 'Mandat de facturation non signé — signe-le (Profil > Mandat de facturation, 1 min) pour démarrer cette mission libérale. Sans lui, Jolene ne peut pas émettre tes factures d''honoraires.';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn_vmad$;

DROP TRIGGER IF EXISTS trg_verifier_mandat_avant_debut ON public.missions;
CREATE TRIGGER trg_verifier_mandat_avant_debut
  BEFORE UPDATE OF statut ON public.missions
  FOR EACH ROW
  WHEN (NEW.statut = 'EN_COURS'::statut_mission AND OLD.statut = 'ASSIGNEE'::statut_mission)
  EXECUTE FUNCTION public.fn_trg_verifier_mandat_avant_debut();

-- 2) fn_traiter_candidature : ajout du bloc « D3 : la paperasse couplée au pic
--    de motivation » après la notification CANDIDATURE_ACCEPTEE. Corps intégral
--    ci-dessous (extrait de la prod post-application — source de vérité).

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
    v_rows INT;
BEGIN
    SELECT * INTO v_cand FROM candidatures WHERE id = p_candidature_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Candidature introuvable'); END IF;

    SELECT * INTO v_mission FROM missions WHERE id = v_cand.mission_id;
    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Non autorisé');
    END IF;

    -- Idempotence : ne traiter qu'une candidature encore en attente. Empêche la
    -- ré-acceptation (qui régénérait un 2e contrat + une 2e notification).
    IF v_cand.statut <> 'EN_ATTENTE' THEN
        RETURN jsonb_build_object('error', 'Cette candidature a déjà été traitée.');
    END IF;

    IF p_decision = 'ACCEPTEE' THEN
        SELECT * INTO v_soignant FROM soignants WHERE id = v_cand.soignant_id;
        SELECT * INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

        -- Compatibilité hiérarchique (alignée sur la candidature) au lieu de l'égalité stricte.
        IF NOT fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
               v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises) THEN
            RETURN jsonb_build_object('error', 'Ce soignant (' || v_soignant.profession::TEXT || ') n''est pas compatible avec la mission requise (' || v_mission.profession_requise::TEXT || ').');
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

        -- Claim ATOMIQUE de la mission AVANT de toucher les candidatures : si une autre
        -- acceptation a déjà pris la mission, on s'arrête proprement (aucune candidature modifiée).
        UPDATE missions SET
            soignant_assigne_id = v_cand.soignant_id,
            statut = 'ASSIGNEE',
            type_contrat_applique = v_choix_applique::type_contrat_applique_enum,
            choix_contrat_soignant = v_choix_applique,
            type_paiement_soignant = v_type_paiement,
            mode_paiement_soignant = v_mode_paiement,
            modifie_le = NOW()
        WHERE id = v_cand.mission_id AND statut = 'OUVERTE';
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows = 0 THEN
            RETURN jsonb_build_object('error', 'Cette mission a déjà été attribuée ou n''est plus ouverte.');
        END IF;

        UPDATE candidatures SET statut = 'ACCEPTEE', traite_le = NOW() WHERE id = p_candidature_id;
        UPDATE candidatures SET statut = 'REFUSEE', motif_refus = 'Un autre candidat a été sélectionné', traite_le = NOW()
        WHERE mission_id = v_cand.mission_id AND id != p_candidature_id AND statut = 'EN_ATTENTE';

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
            v_html := REPLACE(v_html, '{{retrocession_pct}}', COALESCE(v_mission.retrocession_pct::TEXT, ''));
            v_html := REPLACE(v_html, '{{mode_remuneration}}', CASE WHEN v_mission.mode_remuneration = 'RETROCESSION' THEN 'Rétrocession d''honoraires' ELSE 'Taux horaire' END);
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

        -- D3 : la paperasse couplée au pic de motivation — mission LIBERALE
        -- acceptée + mandat non signé → deep-link vers la sheet de signature.
        -- (La mission ne pourra pas démarrer sans : trg_verifier_mandat_avant_debut.)
        IF v_choix_applique = 'LIBERAL' AND COALESCE(v_soignant.mandat_facturation_signe, false) IS NOT TRUE THEN
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_cand.soignant_id, 'CONTRAT_A_SIGNER', '✍️ Signe ton mandat pour confirmer ta mission',
                'Tu viens d''être accepté(e) sur « ' || fn_html_escape(v_mission.intitule) || ' » en libéral. Signe ton mandat de facturation (1 min) : sans lui, Jolene ne peut pas émettre tes factures d''honoraires ni déclencher ton paiement.',
                '/soignant/mandat-facturation', 'SOIGNANT');
        END IF;

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

GRANT EXECUTE ON FUNCTION public.fn_traiter_candidature(uuid, text, text) TO authenticated, service_role;

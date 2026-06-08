-- AUDIT RGPD — complétude de la suppression/anonymisation du compte soignant.
-- fn_supprimer_mon_compte oubliait plusieurs PII sensibles :
--   • numero_securite_sociale (NIR PRIMAIRE) — seul numero_secu était effacé !
--   • champs d'identité de naissance (lieu_naissance_commune/departement, pays_naissance,
--     nationalite, sexe)
--   • pings_gps_mission (localisation granulaire), consentements_ping_gps
--   • scans_pointage : latitude/longitude/precision_gps/id_terminal/ip_address (PII
--     localisation + device + IP) — on anonymise mais on garde la preuve de pointage.
-- On recrée la fonction complète avec ces ajouts (le wrapper rate-limited délègue ici).
CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_missions_futures INTEGER;
    v_hash TEXT;
    v_uid UUID := auth.uid();
BEGIN
    SELECT COUNT(*) INTO v_missions_futures FROM missions
    WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE','EN_COURS') AND fin_le > NOW();
    IF v_missions_futures > 0 THEN
        RETURN jsonb_build_object('error', 'Vous avez ' || v_missions_futures || ' mission(s) en cours.');
    END IF;

    v_hash := encode(digest(v_uid::TEXT || NOW()::TEXT, 'sha256'), 'hex');

    -- Anonymiser le profil soignant (★ ajout NIR primaire + identité naissance ★)
    UPDATE soignants SET
        prenom = 'Soignant', nom = 'Supprimé',
        email = v_hash || '@supprime.jolene.app',
        telephone = NULL, adresse_rue = NULL, adresse_ville = NULL,
        adresse_code_postal = NULL, numero_secu = NULL,
        numero_securite_sociale = NULL,
        lieu_naissance_commune = NULL, lieu_naissance_departement = NULL,
        pays_naissance = NULL, nationalite = NULL, sexe = NULL,
        date_naissance = NULL, siret_liberal = NULL,
        numero_tva = NULL, bio = NULL, specialites = NULL,
        avatar_url = NULL, adresse_lat = NULL, adresse_lng = NULL,
        numero_rpps = NULL, numero_adeli = NULL,
        iban_last4 = NULL, stripe_account_id = NULL,
        psc_sub = NULL, psc_linked_le = NULL, psc_last_login = NULL,
        mandat_facturation_signe = FALSE, mandat_facturation_signe_le = NULL,
        sms_actif = FALSE, sms_consent_le = NULL,
        supprime_le = NOW()
    WHERE id = v_uid;

    UPDATE evaluations SET commentaire = NULL
    WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

    DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
    DELETE FROM tokens_calendrier WHERE soignant_id = v_uid;

    UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

    DELETE FROM attestations_heures_externes WHERE soignant_id = v_uid;
    DELETE FROM favoris_soignant_etab WHERE soignant_id = v_uid;
    DELETE FROM reclamations_scoring WHERE soignant_id = v_uid;
    DELETE FROM notifications WHERE destinataire_id = v_uid;

    UPDATE parrainages SET parrain_id = NULL WHERE parrain_id = v_uid;
    UPDATE parrainages SET filleul_id = NULL WHERE filleul_id = v_uid;

    -- GPS presences
    UPDATE presences SET
        arrivee_lat = NULL, arrivee_lng = NULL,
        depart_lat = NULL, depart_lng = NULL,
        arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
        arrivee_id_terminal = NULL, depart_id_terminal = NULL,
        arrivee_modele_terminal = NULL, depart_modele_terminal = NULL
    WHERE soignant_id = v_uid;

    -- ★ GPS granulaire + consentements (oubliés) ★
    DELETE FROM pings_gps_mission WHERE soignant_id = v_uid;
    DELETE FROM consentements_ping_gps WHERE soignant_id = v_uid;
    -- ★ scans de pointage : anonymiser localisation/device/IP, garder la preuve ★
    UPDATE scans_pointage SET
        latitude = NULL, longitude = NULL, precision_gps_m = NULL,
        id_terminal = NULL, ip_address = NULL, distance_etablissement_m = NULL
    WHERE soignant_id = v_uid;

    UPDATE documents_soignants SET supprime_le = NOW() WHERE soignant_id = v_uid;
    UPDATE partages_rib SET actif = FALSE WHERE soignant_id = v_uid;

    UPDATE stripe_connect_onboarding SET
        stripe_account_id = 'SUPPRIME_' || LEFT(v_hash, 20),
        iban_last4 = NULL, erreur_onboarding = NULL
    WHERE soignant_id = v_uid;

    UPDATE candidatures SET message = NULL WHERE soignant_id = v_uid;

    UPDATE contrats_mission SET
        signature_ip_soignant = NULL,
        signature_navigateur_soignant = NULL,
        signature_image_soignant = NULL
    WHERE soignant_id = v_uid;

    DELETE FROM conversions_liberal WHERE soignant_id = v_uid;
    DELETE FROM heures_externes WHERE soignant_id = v_uid;
    DELETE FROM pauses_presence WHERE soignant_id = v_uid;
    DELETE FROM souscriptions_prevoyance WHERE soignant_id = v_uid;
    DELETE FROM suivi_conversion_3200h WHERE soignant_id = v_uid;

    DELETE FROM mandats_facturation_signatures WHERE soignant_id = v_uid;
    DELETE FROM cessions_creance WHERE soignant_id = v_uid;
    UPDATE factures_honoraires SET soignant_id = v_uid WHERE soignant_id = v_uid;
    DELETE FROM factor_advances WHERE soignant_id = v_uid;
    DELETE FROM psc_auth_sessions WHERE cree_le < NOW();
    DELETE FROM email_queue WHERE destinataire_id = v_uid;

    UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL WHERE destinataire_id = v_uid;
    DELETE FROM cotisations_sociales WHERE soignant_id = v_uid;
    DELETE FROM conformite_travail WHERE soignant_id = v_uid;
    UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
    UPDATE stripe_transfers SET soignant_id = NULL WHERE soignant_id = v_uid;
    UPDATE paiements_soignant SET soignant_id = NULL WHERE soignant_id = v_uid;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (v_uid, 'SOIGNANT', 'RGPD_SUPPRESSION_COMPTE', 'soignant', v_uid,
        jsonb_build_object('anonymise', true, 'tables_nettoyees', ARRAY[
            'soignants','evaluations','tokens_push','tokens_calendrier','messages_mission','messages_chat',
            'attestations_heures_externes','favoris','reclamations_scoring','parrainages','notifications',
            'presences','pings_gps_mission','consentements_ping_gps','scans_pointage',
            'documents_soignants','partages_rib','stripe_connect_onboarding','candidatures',
            'contrats_mission','conversions_liberal','heures_externes','pauses_presence',
            'souscriptions_prevoyance','suivi_conversion_3200h',
            'mandats_facturation_signatures','cessions_creance','factures_honoraires','factor_advances',
            'email_queue','sms_envoyes','cotisations_sociales','conformite_travail',
            'messages_litige','stripe_transfers','paiements_soignant']));

    RETURN jsonb_build_object('success', true, 'message', 'Votre compte a été supprimé et vos données anonymisées.');
END;
$function$;

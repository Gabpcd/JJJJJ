-- Définition LIVE relevée le 25/09/2026 + isolation PSC de la migration précédente.
-- La garde des écritures de profil rétablissait supprime_le et les identifiants
-- vérifiés pendant la suppression utilisateur. Contexte interne borné au seul
-- UPDATE d’anonymisation ; aucune protection de la table n’est retirée.
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
    v_supprime_le timestamptz;
    v_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
    v_bank_update text := COALESCE(current_setting('jolene.bank_server_update', true), '');
    v_liberal_transition text := COALESCE(current_setting('jolene.liberal_transition', true), '');
    v_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
    SELECT supprime_le INTO v_supprime_le FROM public.soignants WHERE id = v_uid FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Aucun profil soignant lié à ce compte'); END IF;
    IF v_supprime_le IS NOT NULL THEN RETURN jsonb_build_object('success', true, 'deja_anonymise', true); END IF;
    SELECT COUNT(*) INTO v_missions_futures FROM missions
    WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE','EN_COURS') AND fin_le > NOW();
    IF v_missions_futures > 0 THEN
        RETURN jsonb_build_object('error', 'Vous avez ' || v_missions_futures || ' mission(s) en cours.');
    END IF;
    v_hash := encode(digest(v_uid::TEXT || NOW()::TEXT, 'sha256'), 'hex');
    PERFORM set_config('jolene.system_update', 'true', true);
    PERFORM set_config('jolene.bank_server_update', 'true', true);
    PERFORM set_config('jolene.liberal_transition', 'true', true);
    PERFORM set_config('jolene.siret_liberal_reset', 'true', true);
    BEGIN
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
        iban_last4 = NULL, iban_virement = NULL, iban_titulaire = NULL,
        iban_source_document_id = NULL, iban_identite_document_id = NULL,
        iban_source_s3_cle = NULL, iban_empreinte_sha256 = NULL,
        iban_verifie_le = NULL, iban_titulaire_coherent = false,
        stripe_account_id = NULL,
        rpps_verifie = false, adeli_verifie = false,
        identite_verifiee = false, diplome_verifie = false, tous_documents_valides = false,
        siret_liberal_verifie = false, siret_liberal_verifie_le = NULL,
        siret_liberal_raison_sociale = NULL, siret_liberal_coherence_identite = NULL,
        psc_sub = NULL, psc_linked_le = NULL, psc_last_login = NULL,
        mandat_facturation_signe = FALSE, mandat_facturation_signe_le = NULL,
        sms_actif = FALSE, sms_consent_le = NULL,
        supprime_le = NOW()
    WHERE id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('jolene.system_update', v_system_update, true);
      PERFORM set_config('jolene.bank_server_update', v_bank_update, true);
      PERFORM set_config('jolene.liberal_transition', v_liberal_transition, true);
      PERFORM set_config('jolene.siret_liberal_reset', v_siret_reset, true);
      RAISE;
    END;
    PERFORM set_config('jolene.system_update', v_system_update, true);
    PERFORM set_config('jolene.bank_server_update', v_bank_update, true);
    PERFORM set_config('jolene.liberal_transition', v_liberal_transition, true);
    PERFORM set_config('jolene.siret_liberal_reset', v_siret_reset, true);
    -- Une suppression ne peut jamais annoncer un succès avec un profil encore actif.
    IF NOT EXISTS (SELECT 1 FROM public.soignants WHERE id=v_uid AND supprime_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Anonymisation non confirmée';
    END IF;
    UPDATE evaluations SET commentaire = NULL WHERE evaluateur_id = v_uid OR evalue_id = v_uid;
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
    UPDATE presences SET
        arrivee_lat = NULL, arrivee_lng = NULL, depart_lat = NULL, depart_lng = NULL,
        arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
        arrivee_id_terminal = NULL, depart_id_terminal = NULL,
        arrivee_modele_terminal = NULL, depart_modele_terminal = NULL
    WHERE soignant_id = v_uid;
    DELETE FROM pings_gps_mission WHERE soignant_id = v_uid;
    DELETE FROM consentements_ping_gps WHERE soignant_id = v_uid;
    UPDATE scans_pointage SET
        latitude = NULL, longitude = NULL, precision_gps_m = NULL,
        id_terminal = NULL, ip_address = NULL, distance_etablissement_m = NULL
    WHERE soignant_id = v_uid;
    UPDATE documents_soignants SET supprime_le = NOW() WHERE soignant_id = v_uid;
    UPDATE partages_rib SET actif = FALSE WHERE soignant_id = v_uid;
    UPDATE stripe_connect_onboarding SET
        stripe_account_id = 'SUPPRIME_' || LEFT(v_hash, 20), iban_last4 = NULL, erreur_onboarding = NULL
    WHERE soignant_id = v_uid;
    UPDATE candidatures SET message = NULL WHERE soignant_id = v_uid;
    UPDATE contrats_mission SET
        signature_ip_soignant = NULL, signature_navigateur_soignant = NULL, signature_image_soignant = NULL
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
    -- Une tentative PSC est anonyme jusqu'au callback et n'appartient pas
    -- à ce compte. Son expiration est traitée par le nettoyeur PSC dédié.
    -- La suppression d'un soignant ne doit interrompre aucune autre connexion.
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

NOTIFY pgrst, 'reload schema';

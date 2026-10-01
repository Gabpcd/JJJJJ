-- Définition LIVE production/staging identique, relevée le 01/10/2026 à 13:04 UTC.
-- Aucun paiement ni transfert n’est modifié par cette migration.
DO $preflight$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fn_supprimer_compte_rate_limited()', 'f283e828e173bf12d8f633be28431c97', 'f283e828e173bf12d8f633be28431c97', '3a69aaead63b899fd3ba4b0b3019fb90', '3a69aaead63b899fd3ba4b0b3019fb90', 'search_path=""', 'RPC_UTILISATEUR_AUTH_INTERNE', 'UID obligatoire ; reçu privé confirmé autorise la reprise idempotente ; sinon limitation 1/jour puis suppression du seul compte propre. Source : 20260925150546_suppression_compte_preuve_privee.sql'),
    ('fn_supprimer_mon_compte()', '71254d2065c67c11ce0460368f20d01f', 'f3af23aeeb4e30aba07e422c0e819aeb', '00be7830b9451307f272afd114a8be11', '9b50372ce3ebd43e8f6e0302f92b46b9', 'search_path=public, extensions', 'RPC_UTILISATEUR_AUTH_INTERNE', 'UID égal au profil soignant ciblé, verrou et refus des missions en cours/futures ; preuve privée d’anonymisation. La suspension ne supprime pas le droit de demander sa propre suppression. Source : 20260925150546_suppression_compte_preuve_privee.sql')
  ) AS attendu(signature,ancien_corps,nouveau_corps,ancienne_definition,nouvelle_definition,configuration,categorie,justification) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.'||r.signature);
    IF NOT FOUND OR md5(p.prosrc) NOT IN (r.ancien_corps,r.nouveau_corps)
      OR md5(pg_get_functiondef(p.oid)) NOT IN (r.ancienne_definition,r.nouvelle_definition)
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]
      OR (SELECT count(*) FROM private.security_definer_inventory WHERE signature=r.signature)<>1
      OR NOT EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=r.signature
        AND categorie=r.categorie AND definition_md5=md5(p.prosrc) AND justification=r.justification)
      OR EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature='public.'||r.signature) THEN
      RAISE EXCEPTION 'Suppression : corps, droits ou inventaire inattendus (%)',r.signature;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_attribute WHERE attrelid IN
      ('public.paiements_soignant'::regclass,'public.stripe_transfers'::regclass)
      AND attname='soignant_id' AND attnotnull AND atttypid='uuid'::regtype AND NOT attisdropped)<>2 THEN
    RAISE EXCEPTION 'Suppression : contraintes financières inattendues';
  END IF;
END;
$preflight$;

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
    IF private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT') THEN
      RETURN jsonb_build_object('success', true, 'deja_anonymise', true);
    END IF;
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
    -- Le profil est anonymisé et conservé par son id. Les références des pièces
    -- et règlements restent inchangées : aucune réattribution de l’historique.
    -- Les deux colonnes soignant_id sont NOT NULL ; aucune écriture ici.
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
            'messages_litige'],
            'tables_financieres_conservees', ARRAY['stripe_transfers','paiements_soignant']));
    INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
    SELECT id,'SOIGNANT',supprime_le,email FROM public.soignants WHERE id=v_uid
    ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
    IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT') THEN RAISE EXCEPTION 'Anonymisation soignant non confirmée'; END IF;
    RETURN jsonb_build_object('success', true, 'message', 'Votre compte a été supprimé et vos données anonymisées.');
END;
$function$;

-- Seule l’empreinte du corps change ; catégorie, justification et date restent intactes.
UPDATE private.security_definer_inventory
SET definition_md5='f3af23aeeb4e30aba07e422c0e819aeb'
WHERE signature='fn_supprimer_mon_compte()'
  AND categorie='RPC_UTILISATEUR_AUTH_INTERNE'
  AND definition_md5 IN ('71254d2065c67c11ce0460368f20d01f','f3af23aeeb4e30aba07e422c0e819aeb');

DO $postflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid='public.fn_supprimer_mon_compte()'::regprocedure;
  IF md5(p.prosrc) IS DISTINCT FROM 'f3af23aeeb4e30aba07e422c0e819aeb'
    OR md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM '9b50372ce3ebd43e8f6e0302f92b46b9'
    OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]
    OR (SELECT count(*) FROM private.security_definer_inventory WHERE signature='fn_supprimer_mon_compte()'
      AND categorie='RPC_UTILISATEUR_AUTH_INTERNE' AND definition_md5='f3af23aeeb4e30aba07e422c0e819aeb')<>1 THEN
    RAISE EXCEPTION 'Suppression : contrôle final du corps, des droits ou de l’inventaire refusé';
  END IF;
  IF md5(pg_get_functiondef('public.fn_supprimer_compte_rate_limited()'::regprocedure))<>'3a69aaead63b899fd3ba4b0b3019fb90' THEN
    RAISE EXCEPTION 'Suppression : wrapper utilisateur modifié';
  END IF;
END;
$postflight$;

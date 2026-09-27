-- Migration de suivi : la première correction a déjà été appliquée en staging.
-- Version distincte pour installer le même backend que celui validé par la recette.
-- Définition LIVE relevée le 25/09/2026 + isolation PSC de la migration précédente.
-- La garde des écritures de profil rétablissait supprime_le et les identifiants
-- vérifiés pendant la suppression utilisateur. Contexte interne borné au seul
-- UPDATE d’anonymisation ; aucune protection de la table n’est retirée.
-- supprime_le sert aussi à la suspension réversible. Seul un reçu privé écrit
-- à la fin du nettoyage, avec le profil correspondant, permet une reprise Auth.
CREATE TABLE IF NOT EXISTS private.suppressions_compte_confirmees (
 utilisateur_id uuid NOT NULL,
 type_profil text NOT NULL CHECK(type_profil IN ('SOIGNANT','ETABLISSEMENT')),
 anonymise_le timestamptz NOT NULL,
 email_anonymise text NOT NULL,
 PRIMARY KEY(utilisateur_id,type_profil)
);
ALTER TABLE private.suppressions_compte_confirmees ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.suppressions_compte_confirmees FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.fn_anonymisation_compte_confirmee(p_uid uuid,p_type text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $preuve$
 SELECT CASE p_type
 WHEN 'SOIGNANT' THEN EXISTS (
   SELECT 1 FROM private.suppressions_compte_confirmees r JOIN public.soignants s ON s.id=r.utilisateur_id
   WHERE r.utilisateur_id=p_uid AND r.type_profil=p_type AND s.supprime_le=r.anonymise_le
     AND s.email=r.email_anonymise AND s.email ~ '^[a-f0-9]{64}@supprime[.]jolene[.]app$'
     AND to_jsonb(s) @> '{"prenom":"Soignant","nom":"Supprimé","telephone":null,"numero_rpps":null,"numero_adeli":null,
       "numero_secu":null,"numero_securite_sociale":null,"iban_virement":null,"iban_titulaire":null,"iban_last4":null,
       "stripe_account_id":null,"psc_sub":null,"rpps_verifie":false,"adeli_verifie":false,"identite_verifiee":false}'::jsonb
 )
 WHEN 'ETABLISSEMENT' THEN EXISTS (
   SELECT 1 FROM private.suppressions_compte_confirmees r JOIN public.etablissements e ON e.id=r.utilisateur_id
   WHERE r.utilisateur_id=p_uid AND r.type_profil=p_type AND e.supprime_le=r.anonymise_le
     AND e.email_contact=r.email_anonymise AND e.email_contact ~ '^[a-f0-9]{64}@supprime[.]jolene[.]app$'
     AND to_jsonb(e) @> '{"nom":"Établissement supprimé","telephone_contact":null,"finess":null,"peut_publier_missions":false,"stripe_sepa_payment_method_id":null}'::jsonb
     AND e.bloque_auto_raisons @> '["COMPTE_SUPPRIME_RGPD"]'::jsonb
 ) ELSE false END
$preuve$;
REVOKE ALL ON FUNCTION private.fn_anonymisation_compte_confirmee(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_anonymisation_compte_confirmee(p_utilisateur_id uuid,p_type_profil text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $preuve$ SELECT private.fn_anonymisation_compte_confirmee(p_utilisateur_id,p_type_profil) $preuve$;
REVOKE ALL ON FUNCTION public.fn_anonymisation_compte_confirmee(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_anonymisation_compte_confirmee(uuid,text) TO service_role;

-- Un établissement suspendu n'a plus les permissions d'édition ordinaires.
-- Ce contexte privé, inaccessible au client, autorise uniquement l'UPDATE
-- effectué par sa RPC d'anonymisation dans ce backend et cette transaction.
CREATE TABLE IF NOT EXISTS private.suppression_etablissement_context (
 backend_pid integer NOT NULL,
 transaction_id bigint NOT NULL,
 utilisateur_id uuid NOT NULL,
 PRIMARY KEY(backend_pid,transaction_id,utilisateur_id)
);
ALTER TABLE private.suppression_etablissement_context ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.suppression_etablissement_context FROM PUBLIC,anon,authenticated,service_role;

-- Définition LIVE du 25/09/2026, garde d'édition conservée hors nettoyage privé.
CREATE OR REPLACE FUNCTION public.fn_protect_etablissement_storage_paths()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;
  IF NEW.id=auth.uid() AND NEW.supprime_le IS NOT NULL
     AND EXISTS (SELECT 1 FROM private.suppression_etablissement_context c
       WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()
         AND c.utilisateur_id=auth.uid()) THEN
    RETURN NEW;
  END IF;
  IF NOT public.fn_a_permission_etablissement('profil_etab', NEW.id) THEN
    RAISE EXCEPTION 'Permission profil etablissement requise' USING ERRCODE = '42501';
  END IF;

  IF NEW.rib_s3_key IS DISTINCT FROM OLD.rib_s3_key
     AND NEW.rib_s3_key IS NOT NULL
     AND NEW.rib_s3_key NOT LIKE NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Chemin RIB non autorise' USING ERRCODE = '42501';
  END IF;
  IF NEW.representant_piece_s3_key IS DISTINCT FROM OLD.representant_piece_s3_key
     AND NEW.representant_piece_s3_key IS NOT NULL
     AND NEW.representant_piece_s3_key NOT LIKE NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Chemin piece identite non autorise' USING ERRCODE = '42501';
  END IF;
  IF NEW.justificatif_fonction_s3_key IS DISTINCT FROM OLD.justificatif_fonction_s3_key
     AND NEW.justificatif_fonction_s3_key IS NOT NULL
     AND NEW.justificatif_fonction_s3_key NOT LIKE NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Chemin justificatif non autorise' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

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
    INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
    SELECT id,'SOIGNANT',supprime_le,email FROM public.soignants WHERE id=v_uid
    ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
    IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'SOIGNANT') THEN RAISE EXCEPTION 'Anonymisation soignant non confirmée'; END IF;
    RETURN jsonb_build_object('success', true, 'message', 'Votre compte a été supprimé et vos données anonymisées.');
END;
$function$;



-- Fonction établissement LIVE, avec reçu final et contexte restauré.
CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions_actives int;
  v_factures_impayees int;
  v_hash text;
  v_interne text := COALESCE(current_setting('app.internal_operation',true),'');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT id INTO v_etab_id FROM etablissements WHERE id = v_uid FOR UPDATE;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun établissement lié à ce compte');
  END IF;

  IF private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success',true,'deja_anonymise',true);
  END IF;

  -- Garde-fou : missions actives
  SELECT count(*) INTO v_missions_actives FROM missions
   WHERE etablissement_id = v_etab_id
     AND statut IN ('OUVERTE','ASSIGNEE','EN_COURS','LITIGE')
     AND fin_le > NOW();
  IF v_missions_actives > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('Vous avez %s mission(s) ouverte(s) ou en cours.', v_missions_actives));
  END IF;

  -- Garde-fou : factures impayées (la suppression n'efface pas une dette)
  SELECT count(*) INTO v_factures_impayees FROM factures
   WHERE etablissement_id = v_etab_id AND statut IN ('EN_ATTENTE','EN_RETARD');
  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('%s facture(s) impayée(s). Réglez-les avant suppression.', v_factures_impayees));
  END IF;

  -- Bypass trigger fn_protect_etablissement_commercial pour anonymisation
  PERFORM set_config('app.internal_operation', 'true', true);
  v_hash := encode(extensions.digest(v_etab_id::text || NOW()::text, 'sha256'), 'hex');

  BEGIN
  INSERT INTO private.suppression_etablissement_context(backend_pid,transaction_id,utilisateur_id)
  VALUES(pg_backend_pid(),txid_current(),v_uid);
  -- Anonymisation établissement
  UPDATE etablissements SET
    nom = 'Établissement supprimé',
    siret = '99' || LPAD(LEFT(REGEXP_REPLACE(v_hash, '[^0-9]', '', 'g'), 12), 12, '0'),
    finess = NULL,
    email_contact = v_hash || '@supprime.jolene.app',
    telephone_contact = NULL,
    adresse_rue = '[SUPPRIMÉ]',
    adresse_ville = '[SUPPRIMÉ]',
    adresse_code_postal = '00000',
    adresse_departement = NULL, adresse_lat = NULL, adresse_lng = NULL,
    description = NULL, logo_url = NULL, horaires_ouverture = NULL,
    contrat_url = NULL,
    siret_raison_sociale = NULL, siret_categorie_juridique = NULL,
    siret_code_naf = NULL, siret_est_actif = false,
    chorus_pro_actif = false, chorus_pro_identifiant = NULL,
    sms_actif = false, sms_consent_le = NULL,
    peut_publier_missions = false,
    bloque_auto_le = NOW(),
    bloque_auto_raisons = jsonb_build_array('COMPTE_SUPPRIME_RGPD'),
    supprime_le = NOW(),
    stripe_sepa_payment_method_id = NULL
  WHERE id = v_etab_id;

  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.internal_operation',v_interne,true);
    RAISE;
  END;
  DELETE FROM private.suppression_etablissement_context
  WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current() AND utilisateur_id=v_uid;
  PERFORM set_config('app.internal_operation',v_interne,true);

  -- Tables liées
  DELETE FROM admins_groupe_sante WHERE utilisateur_id = v_uid;
  DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
  DELETE FROM notifications WHERE destinataire_id = v_uid;

  UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

  UPDATE evaluations SET commentaire = NULL
   WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

  DELETE FROM exclusions WHERE exclu_par = v_uid OR exclu_id = v_uid;

  UPDATE partages_rib SET actif = false, expire_le = NOW()
   WHERE etablissement_id = v_etab_id;

  -- Contrats : on conserve (preuves légales) mais anonymise IP/UA
  UPDATE contrats_mission SET
    signature_ip_etablissement = NULL,
    signature_navigateur_etablissement = NULL,
    signature_image_etablissement = NULL
   WHERE etablissement_id = v_etab_id;

  DELETE FROM email_queue WHERE destinataire_id = v_uid;
  UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL
   WHERE destinataire_id = v_uid;

  DELETE FROM calendar_events_sync WHERE connection_id IN
    (SELECT id FROM calendar_connections WHERE utilisateur_id = v_uid);
  DELETE FROM calendar_connections WHERE utilisateur_id = v_uid;
  DELETE FROM api_keys WHERE etablissement_id = v_etab_id;

  -- Audit (type_acteur ADMIN_ETABLISSEMENT, action RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT)
  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (v_uid, 'ADMIN_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT', 'etablissement', v_etab_id,
    jsonb_build_object('anonymise', true));

  INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
  SELECT id,'ETABLISSEMENT',supprime_le,email_contact FROM public.etablissements WHERE id=v_etab_id
  ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
  IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN RAISE EXCEPTION 'Anonymisation établissement non confirmée'; END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Établissement anonymisé. Factures conservées 10 ans (LPF L102 B).',
    'etablissement_id', v_etab_id
  );
END;
$function$
;

-- Une finalisation déjà prouvée ne consomme pas une seconde demande 1/jour.
CREATE OR REPLACE FUNCTION public.fn_supprimer_compte_rate_limited()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $wrapper$
DECLARE uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
 IF private.fn_anonymisation_compte_confirmee(uid,'SOIGNANT') THEN
   RETURN jsonb_build_object('success',true,'deja_anonymise',true);
 END IF;
 IF public.fn_verifier_rate_limit(uid::text,'supprimer_compte',1,86400) IS DISTINCT FROM true THEN
   RETURN jsonb_build_object('error','Demande de suppression déjà en cours.');
 END IF;
 RETURN public.fn_supprimer_mon_compte();
END $wrapper$;

-- Une finalisation déjà prouvée ne consomme pas une seconde demande 1/jour.
CREATE OR REPLACE FUNCTION public.fn_supprimer_compte_etablissement_rate_limited()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $wrapper$
DECLARE uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
 IF private.fn_anonymisation_compte_confirmee(uid,'ETABLISSEMENT') THEN
   RETURN jsonb_build_object('success',true,'deja_anonymise',true);
 END IF;
 IF public.fn_verifier_rate_limit(uid::text,'supprimer_compte_etablissement',1,86400) IS DISTINCT FROM true THEN
   RETURN jsonb_build_object('error','Demande de suppression déjà en cours.');
 END IF;
 RETURN public.fn_supprimer_mon_compte_etablissement();
END $wrapper$;

NOTIFY pgrst, 'reload schema';

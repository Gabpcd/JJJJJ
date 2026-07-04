-- Fix fn_modifier_mon_profil — 3 bugs corrigés simultanément :
--
-- 1. Audit action invalide → 400 sur tous les saves
--    L'action 'PROFIL_MODIFICATION' n'est pas dans la check constraint
--    journaux_audit_action_check (qui exige 'MODIFICATION_PROFIL', l'inverse).
--    Conséquence : chaque appel à fn_modifier_mon_profil échouait avec
--    "violates check constraint" → 400 PostgREST → message UI traduit en
--    "La valeur saisie est hors des limites autorisées" (extraireMessageErreur).
--
-- 2. Champs prenom / nom / numero_rpps absents du UPDATE
--    Le RPC acceptait les paramètres mais ne les écrivait pas. La vérification
--    RPPS inline (R3.1) ne pouvait donc pas persister le numéro saisi avant
--    d'appeler verify-rpps.
--
-- 3. Pas de UPSERT pour les comptes sans row soignants
--    test@jolene.app et autres comptes sans inscription complète : l'UPDATE
--    affectait 0 rows en silence, aucune modification persistée.
--
-- Fix :
-- - Action audit : 'PROFIL_MODIFICATION' → 'MODIFICATION_PROFIL'
-- - Audit wrappé dans BEGIN/EXCEPTION (ne doit jamais bloquer le UPDATE)
-- - Ajout de prenom, nom, numero_rpps au UPDATE (avec garde sur les triggers
--   de protection : prenom/nom protégés si identite_verifiee=true ; rpps si
--   rpps_verifie=true)
-- - INSERT préalable si row inexistante (UPSERT logique)

CREATE OR REPLACE FUNCTION public.fn_modifier_mon_profil(
  p_prenom text DEFAULT NULL,
  p_nom text DEFAULT NULL,
  p_telephone text DEFAULT NULL,
  p_date_naissance date DEFAULT NULL,
  p_adresse_rue text DEFAULT NULL,
  p_adresse_ville text DEFAULT NULL,
  p_adresse_code_postal text DEFAULT NULL,
  p_adresse_lat numeric DEFAULT NULL,
  p_adresse_lng numeric DEFAULT NULL,
  p_rayon_deplacement_km integer DEFAULT NULL,
  p_numero_rpps text DEFAULT NULL,
  p_numero_adeli text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL,
  p_types_contrat text[] DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_annees_experience integer DEFAULT NULL,
  p_specialites text[] DEFAULT NULL,
  p_taux_horaire_minimum numeric DEFAULT NULL,
  p_type_exercice text DEFAULT NULL,
  p_ville_recherche text DEFAULT NULL,
  p_ville_urgence text DEFAULT NULL,
  p_disponible_urgence boolean DEFAULT NULL,
  p_urgence_rayon_km integer DEFAULT NULL,
  p_attestation_cumul_activite boolean DEFAULT NULL,
  p_est_cumul_activite boolean DEFAULT NULL,
  p_est_salarie_etablissement boolean DEFAULT NULL,
  p_consentement_gps boolean DEFAULT NULL,
  p_types_contrat_acceptes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
  v_champs_modifies jsonb := '[]'::jsonb;
  v_existe boolean;
  v_email text;
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

    PERFORM set_config('jolene.rpc_update', 'true', true);

    SELECT EXISTS(SELECT 1 FROM soignants WHERE id = v_uid) INTO v_existe;

    IF NOT v_existe THEN
      SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
      INSERT INTO soignants (id, email, prenom, nom, telephone, date_naissance, numero_rpps, numero_adeli)
      VALUES (
        v_uid,
        COALESCE(v_email, 'inconnu@jolene.app'),
        COALESCE(p_prenom, ''),
        COALESCE(p_nom, ''),
        p_telephone,
        p_date_naissance,
        p_numero_rpps,
        p_numero_adeli
      );
    END IF;

    UPDATE soignants SET
        prenom = CASE
            WHEN identite_verifiee = TRUE THEN prenom
            ELSE COALESCE(p_prenom, prenom)
        END,
        nom = CASE
            WHEN identite_verifiee = TRUE THEN nom
            ELSE COALESCE(p_nom, nom)
        END,
        telephone = COALESCE(p_telephone, telephone),
        date_naissance = COALESCE(p_date_naissance, date_naissance),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        rayon_deplacement_km = COALESCE(p_rayon_deplacement_km, rayon_deplacement_km),
        numero_rpps = CASE
            WHEN rpps_verifie = TRUE THEN numero_rpps
            ELSE COALESCE(p_numero_rpps, numero_rpps)
        END,
        numero_adeli = COALESCE(p_numero_adeli, numero_adeli),
        avatar_url = COALESCE(p_avatar_url, avatar_url),
        types_contrat_acceptes = CASE
            WHEN p_types_contrat_acceptes IS NOT NULL THEN p_types_contrat_acceptes
            WHEN p_types_contrat IS NOT NULL THEN array_to_string(p_types_contrat, ',')
            ELSE types_contrat_acceptes END,
        bio = COALESCE(p_bio, bio),
        annees_experience = COALESCE(p_annees_experience, annees_experience),
        specialites = COALESCE(p_specialites, specialites),
        taux_horaire_minimum = COALESCE(p_taux_horaire_minimum, taux_horaire_minimum),
        type_exercice = COALESCE(p_type_exercice, type_exercice),
        ville_recherche = COALESCE(p_ville_recherche, ville_recherche),
        ville_urgence = COALESCE(p_ville_urgence, ville_urgence),
        disponible_urgence = COALESCE(p_disponible_urgence, disponible_urgence),
        urgence_rayon_km = COALESCE(p_urgence_rayon_km, urgence_rayon_km),
        attestation_cumul_activite = COALESCE(p_attestation_cumul_activite, attestation_cumul_activite),
        est_cumul_activite = COALESCE(p_est_cumul_activite, est_cumul_activite),
        est_salarie_etablissement = COALESCE(p_est_salarie_etablissement, est_salarie_etablissement),
        consentement_gps = COALESCE(p_consentement_gps, consentement_gps),
        attestation_cumul_le = CASE WHEN p_attestation_cumul_activite = TRUE THEN NOW() ELSE attestation_cumul_le END,
        consentement_gps_le = CASE WHEN p_consentement_gps IS NOT NULL THEN NOW() ELSE consentement_gps_le END,
        modifie_le = NOW()
    WHERE id = v_uid;

    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    IF p_prenom IS NOT NULL OR p_nom IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identite"'::jsonb; END IF;
    IF p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"telephone"'::jsonb; END IF;
    IF p_date_naissance IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"date_naissance"'::jsonb; END IF;
    IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL OR p_adresse_lat IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
    IF p_numero_rpps IS NOT NULL OR p_numero_adeli IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identifiants_professionnels"'::jsonb; END IF;
    IF p_type_exercice IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"type_exercice"'::jsonb; END IF;
    IF p_consentement_gps IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"consentement_gps"'::jsonb; END IF;

    BEGIN
      PERFORM fn_ecrire_audit(
        v_uid, 'SOIGNANT', 'MODIFICATION_PROFIL',
        'soignant', v_uid, NULL,
        jsonb_build_object('champs_modifies', v_champs_modifies),
        v_ip, v_user_agent
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    RETURN jsonb_build_object('success', TRUE);
END;
$function$;

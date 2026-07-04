-- Fix bug 400 sur fn_modifier_mon_profil pour les comptes sans row
-- soignants encore créée (cas test@jolene.app, comptes pré-existants
-- avant register-soignant, etc.) :
--
-- L'INSERT du UPSERT ajouté en R3.3 ne fournit pas de valeur pour
-- profession (NOT NULL) → contrainte violée → 400. Logs Postgres :
--   ERROR: null value in column "profession" of relation "soignants"
--
-- Fix en 3 volets :
--
-- 1) Rendre soignants.profession NULLABLE
--    Sémantique : un soignant peut exister sans profession définie
--    pendant la phase d'onboarding (avant vérification RPPS pour les
--    professions à RPPS, ou avant choix manuel pour AS/AES). Le code
--    frontend gère déjà cet état (Phase 1 audit a confirmé plusieurs
--    guards `!soignant.profession`).
--
-- 2) Ajouter p_profession à fn_modifier_mon_profil
--    Permet à la page Profil de définir / modifier la profession
--    quand elle n'est pas encore vérifiée par RPPS. Utilisé par le
--    wizard adaptatif côté frontend (cas no-profession).
--
-- 3) Mettre à jour fn_protect_soignant_verification pour autoriser
--    le changement de profession quand OLD.profession IS NULL
--    (premier set par le wizard). Lock toujours actif après set.

ALTER TABLE soignants ALTER COLUMN profession DROP NOT NULL;

-- Drop l'ancienne signature 28 args avant créer la nouvelle 29 args
-- pour éviter ambiguïté PostgREST (fonction non unique).
DROP FUNCTION IF EXISTS public.fn_modifier_mon_profil(
  text, text, text, date, text, text, text, numeric, numeric, integer,
  text, text, text, text[], text, integer, text[], numeric, text, text,
  text, boolean, integer, boolean, boolean, boolean, boolean, text
);

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
  p_types_contrat_acceptes text DEFAULT NULL,
  p_profession text DEFAULT NULL
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
      INSERT INTO soignants (
        id, email, prenom, nom, telephone, date_naissance,
        numero_rpps, numero_adeli, profession
      )
      VALUES (
        v_uid,
        COALESCE(v_email, 'inconnu@jolene.app'),
        COALESCE(p_prenom, ''),
        COALESCE(p_nom, ''),
        p_telephone,
        p_date_naissance,
        p_numero_rpps,
        p_numero_adeli,
        CASE WHEN p_profession IS NOT NULL THEN p_profession::type_profession ELSE NULL END
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
        profession = CASE
            -- Profession verrouillée une fois définie (vérifiée RPPS ou choisie).
            -- Premier set autorisé via le wizard quand profession est NULL.
            WHEN profession IS NOT NULL THEN profession
            WHEN p_profession IS NOT NULL THEN p_profession::type_profession
            ELSE NULL
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
    IF p_profession IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"profession"'::jsonb; END IF;

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

-- Update trigger fn_protect_soignant_verification : autoriser le set initial
-- de profession quand OLD.profession IS NULL. Lock toujours actif après.
CREATE OR REPLACE FUNCTION public.fn_protect_soignant_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF est_admin() THEN RETURN NEW; END IF;

    IF COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
        RETURN NEW;
    END IF;

    IF COALESCE(current_setting('jolene.rpc_update', true), '') = 'true' THEN
        IF OLD.id = auth.uid() THEN
            NEW.diplome_verifie := OLD.diplome_verifie;
            NEW.identite_verifiee := OLD.identite_verifiee;
            NEW.tous_documents_valides := OLD.tous_documents_valides;
            NEW.rpps_verifie := OLD.rpps_verifie;
            NEW.rpps_verifie_le := OLD.rpps_verifie_le;
            NEW.rpps_nom_api := OLD.rpps_nom_api;
            NEW.rpps_prenom_api := OLD.rpps_prenom_api;
            NEW.rpps_profession_api := OLD.rpps_profession_api;
            NEW.statut_verification_aria := OLD.statut_verification_aria;
            -- Profession : verrouillée UNIQUEMENT si déjà définie (premier set autorisé via RPC)
            IF OLD.profession IS NOT NULL THEN
                NEW.profession := OLD.profession;
            END IF;
            NEW.score_fiabilite := OLD.score_fiabilite;
            NEW.note_moyenne := OLD.note_moyenne;
            NEW.total_absences := OLD.total_absences;
            NEW.total_retards_pointage := OLD.total_retards_pointage;
            NEW.total_missions_annulees := OLD.total_missions_annulees;
            NEW.total_missions_terminees := OLD.total_missions_terminees;
            NEW.heures_cumulees := OLD.heures_cumulees;
            NEW.heures_plateforme := OLD.heures_plateforme;
            NEW.stripe_account_id := OLD.stripe_account_id;
            NEW.supprime_le := OLD.supprime_le;
            NEW.parraine_par := OLD.parraine_par;
            IF OLD.rpps_verifie = TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
            IF OLD.identite_verifiee = TRUE THEN NEW.nom := OLD.nom; NEW.prenom := OLD.prenom; END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.id = auth.uid() THEN
        NEW.diplome_verifie := OLD.diplome_verifie;
        NEW.identite_verifiee := OLD.identite_verifiee;
        NEW.tous_documents_valides := OLD.tous_documents_valides;
        NEW.rpps_verifie := OLD.rpps_verifie;
        NEW.rpps_verifie_le := OLD.rpps_verifie_le;
        NEW.rpps_nom_api := OLD.rpps_nom_api;
        NEW.rpps_prenom_api := OLD.rpps_prenom_api;
        NEW.rpps_profession_api := OLD.rpps_profession_api;
        NEW.statut_verification_aria := OLD.statut_verification_aria;
        IF OLD.rpps_verifie = TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
        IF OLD.identite_verifiee = TRUE THEN NEW.nom := OLD.nom; NEW.prenom := OLD.prenom; END IF;
        IF OLD.profession IS NOT NULL THEN
            NEW.profession := OLD.profession;
        END IF;
        NEW.type_exercice := OLD.type_exercice;
        NEW.statut_liberal := OLD.statut_liberal;
        NEW.score_fiabilite := OLD.score_fiabilite;
        NEW.note_moyenne := OLD.note_moyenne;
        NEW.total_absences := OLD.total_absences;
        NEW.total_retards_pointage := OLD.total_retards_pointage;
        NEW.total_missions_annulees := OLD.total_missions_annulees;
        NEW.total_missions_terminees := OLD.total_missions_terminees;
        NEW.heures_cumulees := OLD.heures_cumulees;
        NEW.heures_plateforme := OLD.heures_plateforme;
        NEW.eligible_conversion_3200h := OLD.eligible_conversion_3200h;
        NEW.validation_3200h_statut := OLD.validation_3200h_statut;
        NEW.stripe_account_id := OLD.stripe_account_id;
        NEW.supprime_le := OLD.supprime_le;
        NEW.parraine_par := OLD.parraine_par;
    END IF;

    RETURN NEW;
END;
$function$;

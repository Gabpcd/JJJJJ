-- ─── RGPD : Combler les gaps d'audit sur les opérations sensibles ───
--
-- Audit externe : plusieurs fonctions qui modifient des données personnelles
-- ou financières n'écrivaient rien dans journaux_audit. Violation Art. 32 RGPD.
--
-- Fonctions corrigées :
--   1. fn_modifier_tva_liberal       (modification TVA soignant libéral)
--   2. fn_creer_litige               (création d'un litige)
--   3. fn_modifier_mon_profil        (modification données personnelles soignant)
--   4. fn_modifier_mon_etablissement (modification coordonnées établissement)
--
-- Chaque fonction capture désormais l'IP et le User-Agent depuis les en-têtes
-- HTTP via `current_setting('request.headers')` (exposé par PostgREST) — pas
-- de changement côté frontend.

-- ─── 1. fn_modifier_tva_liberal ───
CREATE OR REPLACE FUNCTION public.fn_modifier_tva_liberal(p_assujetti_tva boolean, p_numero_tva text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ancien_assujetti BOOLEAN;
  v_ancien_numero TEXT;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  SELECT assujetti_tva, numero_tva INTO v_ancien_assujetti, v_ancien_numero
  FROM soignants WHERE id = auth.uid();

  UPDATE soignants
  SET assujetti_tva = p_assujetti_tva,
      numero_tva = CASE WHEN p_assujetti_tva THEN p_numero_tva ELSE NULL END,
      modifie_le = now()
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    auth.uid(), 'SOIGNANT', 'TVA_MODIFICATION',
    'soignant', auth.uid(), NULL,
    jsonb_build_object(
      'ancien_assujetti', v_ancien_assujetti,
      'nouveau_assujetti', p_assujetti_tva,
      'ancien_numero', v_ancien_numero,
      'nouveau_numero', CASE WHEN p_assujetti_tva THEN p_numero_tva ELSE NULL END
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- ─── 2. fn_creer_litige ───
CREATE OR REPLACE FUNCTION public.fn_creer_litige(p_mission_id uuid, p_presence_id uuid DEFAULT NULL::uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_user_id UUID := auth.uid();
    v_qui TEXT;
    v_motif_safe TEXT;
    v_final_presence_id UUID;
    v_litige_id UUID;
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.soignant_assigne_id = v_user_id THEN v_qui := 'SOIGNANT';
    ELSIF mon_etablissement_id() = v_mission.etablissement_id THEN v_qui := 'ETABLISSEMENT';
    ELSIF est_admin() THEN v_qui := 'ETABLISSEMENT';
    ELSE RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
    IF EXISTS(SELECT 1 FROM litiges WHERE mission_id = p_mission_id AND statut NOT IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME')) THEN
        RETURN jsonb_build_object('error', 'Un litige est déjà ouvert pour cette mission');
    END IF;
    v_motif_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_motif), ''), 'Contestation'), '<[^>]*>', '', 'g'), 2000);
    v_final_presence_id := p_presence_id;
    IF v_final_presence_id IS NULL THEN
        SELECT id INTO v_final_presence_id FROM presences WHERE mission_id = p_mission_id ORDER BY cree_le DESC LIMIT 1;
    END IF;
    INSERT INTO litiges (mission_id, presence_id, soignant_id, etablissement_id, initie_par, motif, statut)
    VALUES (p_mission_id, v_final_presence_id, v_mission.soignant_assigne_id, v_mission.etablissement_id, v_qui, v_motif_safe, 'OUVERT')
    RETURNING id INTO v_litige_id;

    IF v_mission.statut = 'EN_COURS' THEN
        UPDATE missions SET statut = 'LITIGE' WHERE id = p_mission_id;
    END IF;

    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    PERFORM fn_ecrire_audit(
      v_user_id, v_qui, 'LITIGE_CREATION',
      'litige', v_litige_id, NULL,
      jsonb_build_object(
        'mission_id', p_mission_id,
        'presence_id', v_final_presence_id,
        'motif', v_motif_safe
      ),
      v_ip, v_user_agent
    );

    RETURN jsonb_build_object('success', TRUE, 'message', 'Litige ouvert', 'litige_id', v_litige_id);
END;
$function$;

-- ─── 3. fn_modifier_mon_profil ───
-- Audit interne backend (source de vérité, ne dépend pas du frontend)
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_profil(p_prenom text DEFAULT NULL::text, p_nom text DEFAULT NULL::text, p_telephone text DEFAULT NULL::text, p_date_naissance date DEFAULT NULL::date, p_adresse_rue text DEFAULT NULL::text, p_adresse_ville text DEFAULT NULL::text, p_adresse_code_postal text DEFAULT NULL::text, p_adresse_lat numeric DEFAULT NULL::numeric, p_adresse_lng numeric DEFAULT NULL::numeric, p_rayon_deplacement_km integer DEFAULT NULL::integer, p_numero_rpps text DEFAULT NULL::text, p_numero_adeli text DEFAULT NULL::text, p_avatar_url text DEFAULT NULL::text, p_types_contrat text[] DEFAULT NULL::text[], p_bio text DEFAULT NULL::text, p_annees_experience integer DEFAULT NULL::integer, p_specialites text[] DEFAULT NULL::text[], p_taux_horaire_minimum numeric DEFAULT NULL::numeric, p_type_exercice text DEFAULT NULL::text, p_ville_recherche text DEFAULT NULL::text, p_ville_urgence text DEFAULT NULL::text, p_disponible_urgence boolean DEFAULT NULL::boolean, p_urgence_rayon_km integer DEFAULT NULL::integer, p_attestation_cumul_activite boolean DEFAULT NULL::boolean, p_est_cumul_activite boolean DEFAULT NULL::boolean, p_est_salarie_etablissement boolean DEFAULT NULL::boolean, p_consentement_gps boolean DEFAULT NULL::boolean, p_types_contrat_acceptes text DEFAULT NULL::text)
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
BEGIN
    IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

    PERFORM set_config('jolene.rpc_update', 'true', true);

    UPDATE soignants SET
        telephone = COALESCE(p_telephone, telephone),
        date_naissance = COALESCE(p_date_naissance, date_naissance),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        rayon_deplacement_km = COALESCE(p_rayon_deplacement_km, rayon_deplacement_km),
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

    IF p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"telephone"'::jsonb; END IF;
    IF p_date_naissance IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"date_naissance"'::jsonb; END IF;
    IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
    IF p_numero_rpps IS NOT NULL OR p_numero_adeli IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identifiants_professionnels"'::jsonb; END IF;
    IF p_type_exercice IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"type_exercice"'::jsonb; END IF;
    IF p_consentement_gps IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"consentement_gps"'::jsonb; END IF;

    PERFORM fn_ecrire_audit(
      v_uid, 'SOIGNANT', 'PROFIL_MODIFICATION',
      'soignant', v_uid, NULL,
      jsonb_build_object('champs_modifies', v_champs_modifies),
      v_ip, v_user_agent
    );

    RETURN jsonb_build_object('success', TRUE);
END;
$function$;

-- ─── 4. fn_modifier_mon_etablissement ───
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_etablissement(p_nom text DEFAULT NULL::text, p_finess text DEFAULT NULL::text, p_adresse_rue text DEFAULT NULL::text, p_adresse_ville text DEFAULT NULL::text, p_adresse_code_postal text DEFAULT NULL::text, p_adresse_departement text DEFAULT NULL::text, p_email_contact text DEFAULT NULL::text, p_telephone text DEFAULT NULL::text, p_adresse_lat numeric DEFAULT NULL::numeric, p_adresse_lng numeric DEFAULT NULL::numeric, p_taux_majoration_nuit numeric DEFAULT NULL::numeric, p_taux_majoration_dimanche numeric DEFAULT NULL::numeric, p_taux_majoration_ferie numeric DEFAULT NULL::numeric, p_couleur_theme text DEFAULT NULL::text, p_convention_collective text DEFAULT NULL::text, p_mode_paiement_commission text DEFAULT NULL::text, p_logo_url text DEFAULT NULL::text, p_contrat_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
    v_champs_modifies jsonb := '[]'::jsonb;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Établissement non trouvé"}'::JSONB;
    END IF;

    IF p_couleur_theme IS NOT NULL AND p_couleur_theme !~ '^#[0-9a-fA-F]{6}$' THEN
        RETURN '{"error":"Couleur invalide (format #RRGGBB)"}'::JSONB;
    END IF;

    UPDATE etablissements SET
        nom = COALESCE(p_nom, nom),
        finess = COALESCE(p_finess, finess),
        adresse_rue = COALESCE(p_adresse_rue, adresse_rue),
        adresse_ville = COALESCE(p_adresse_ville, adresse_ville),
        adresse_code_postal = COALESCE(p_adresse_code_postal, adresse_code_postal),
        adresse_departement = COALESCE(p_adresse_departement, adresse_departement),
        email_contact = COALESCE(p_email_contact, email_contact),
        telephone_contact = COALESCE(p_telephone, telephone_contact),
        adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
        adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
        taux_majoration_nuit_pourcent = COALESCE(p_taux_majoration_nuit, taux_majoration_nuit_pourcent),
        taux_majoration_dimanche_pourcent = COALESCE(p_taux_majoration_dimanche, taux_majoration_dimanche_pourcent),
        taux_majoration_ferie_pourcent = COALESCE(p_taux_majoration_ferie, taux_majoration_ferie_pourcent),
        couleur_theme = COALESCE(p_couleur_theme, couleur_theme),
        convention_collective = COALESCE(p_convention_collective, convention_collective),
        mode_paiement_commission = COALESCE(p_mode_paiement_commission, mode_paiement_commission),
        logo_url = COALESCE(p_logo_url, logo_url),
        contrat_url = COALESCE(p_contrat_url, contrat_url),
        contrat_uploade_le = CASE WHEN p_contrat_url IS NOT NULL THEN NOW() ELSE contrat_uploade_le END,
        modifie_le = NOW()
    WHERE id = v_etab_id;

    BEGIN
      v_headers := current_setting('request.headers', true)::jsonb;
      v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
      v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
      v_ip := NULL; v_user_agent := NULL;
    END;

    IF p_nom IS NOT NULL OR p_finess IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identite"'::jsonb; END IF;
    IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
    IF p_email_contact IS NOT NULL OR p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"contact"'::jsonb; END IF;
    IF p_taux_majoration_nuit IS NOT NULL OR p_taux_majoration_dimanche IS NOT NULL OR p_taux_majoration_ferie IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"taux_majoration"'::jsonb; END IF;
    IF p_convention_collective IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"convention_collective"'::jsonb; END IF;

    PERFORM fn_ecrire_audit(
      auth.uid(), 'ADMIN_ETABLISSEMENT', 'ETABLISSEMENT_MODIFICATION',
      'etablissement', v_etab_id, NULL,
      jsonb_build_object('champs_modifies', v_champs_modifies),
      v_ip, v_user_agent
    );

    RETURN '{"success":true}'::JSONB;
END;
$function$;

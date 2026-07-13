-- P0 identité soignant : une preuve officielle reste liée aux traits et à la
-- date de naissance qui ont été vérifiés. Toute correction ultérieure du
-- profil est autorisée, mais invalide les anciennes preuves et impose une
-- nouvelle vérification.

-- Les invalidations internes déclenchées par un changement d'identité doivent
-- pouvoir rétrograder un document, sans ouvrir ce droit au client.
CREATE OR REPLACE FUNCTION public.dec_proteger_validation_documents()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR public.est_admin()
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN
    RAISE EXCEPTION 'Seul un administrateur peut modifier le statut de vérification';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_proteger_document_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR public.est_admin()
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification
     OR NEW.verifie_par IS DISTINCT FROM OLD.verifie_par
     OR NEW.verifie_le IS DISTINCT FROM OLD.verifie_le
     OR NEW.valide_depuis IS DISTINCT FROM OLD.valide_depuis
     OR NEW.valide_jusqua IS DISTINCT FROM OLD.valide_jusqua
     OR NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet
     OR NEW.est_critique IS DISTINCT FROM OLD.est_critique
     OR NEW.resultat_ia IS DISTINCT FROM OLD.resultat_ia
     OR NEW.score_confiance_ia IS DISTINCT FROM OLD.score_confiance_ia
     OR NEW.nom_extrait_ia IS DISTINCT FROM OLD.nom_extrait_ia
     OR NEW.prenom_extrait_ia IS DISTINCT FROM OLD.prenom_extrait_ia
     OR NEW.coherence_nom IS DISTINCT FROM OLD.coherence_nom THEN
    RAISE EXCEPTION 'Modification des champs de vérification interdite'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
    RAISE EXCEPTION 'Modification du propriétaire interdite';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.dec_proteger_validation_documents() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_proteger_document_verification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_proteger_validation_documents() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_proteger_document_verification() TO service_role;

-- Le garde-fou continue de protéger tous les champs de confiance. Il ne fige
-- plus nom/prénom : le trigger d'invalidation ci-dessous permet une correction
-- légitime tout en révoquant immédiatement les preuves devenues obsolètes.
CREATE OR REPLACE FUNCTION public.fn_protect_soignant_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL OR public.est_admin() THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN RETURN NEW; END IF;

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
      NEW.coherence_identite := OLD.coherence_identite;
      NEW.coherence_details := OLD.coherence_details;
      NEW.scolarite_formation := OLD.scolarite_formation;
      NEW.scolarite_annee_validee := OLD.scolarite_annee_validee;
      NEW.scolarite_profession_autorisee := OLD.scolarite_profession_autorisee;
      NEW.scolarite_verifiee := OLD.scolarite_verifiee;
      NEW.scolarite_verifiee_le := OLD.scolarite_verifiee_le;
      NEW.licence_remplacement_verifiee := OLD.licence_remplacement_verifiee;
      NEW.licence_remplacement_le := OLD.licence_remplacement_le;
      NEW.licence_remplacement_valide_jusqua := OLD.licence_remplacement_valide_jusqua;
      NEW.licence_remplacement_specialite := OLD.licence_remplacement_specialite;
      IF OLD.profession IS NOT NULL THEN NEW.profession := OLD.profession; END IF;
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
      IF OLD.rpps_verifie IS TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
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
    NEW.coherence_identite := OLD.coherence_identite;
    NEW.coherence_details := OLD.coherence_details;
    NEW.scolarite_formation := OLD.scolarite_formation;
    NEW.scolarite_annee_validee := OLD.scolarite_annee_validee;
    NEW.scolarite_profession_autorisee := OLD.scolarite_profession_autorisee;
    NEW.scolarite_verifiee := OLD.scolarite_verifiee;
    NEW.scolarite_verifiee_le := OLD.scolarite_verifiee_le;
    NEW.licence_remplacement_verifiee := OLD.licence_remplacement_verifiee;
    NEW.licence_remplacement_le := OLD.licence_remplacement_le;
    NEW.licence_remplacement_valide_jusqua := OLD.licence_remplacement_valide_jusqua;
    NEW.licence_remplacement_specialite := OLD.licence_remplacement_specialite;
    IF OLD.rpps_verifie IS TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
    IF OLD.profession IS NOT NULL THEN NEW.profession := OLD.profession; END IF;
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
$$;

REVOKE ALL ON FUNCTION public.fn_protect_soignant_verification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_soignant_verification() TO service_role;

-- Le garde symétrique ADELI accepte uniquement la cascade interne contrôlée ;
-- un utilisateur ne peut toujours ni valider ni remplacer son propre ADELI.
CREATE OR REPLACE FUNCTION public.fn_protect_adeli_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.role() = 'service_role'
     OR auth.uid() IS NULL
     OR public.est_admin()
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
    RETURN NEW;
  END IF;
  IF OLD.id = auth.uid() THEN
    NEW.adeli_verifie := OLD.adeli_verifie;
    NEW.adeli_verifie_le := OLD.adeli_verifie_le;
    NEW.adeli_nom_api := OLD.adeli_nom_api;
    NEW.adeli_prenom_api := OLD.adeli_prenom_api;
    NEW.adeli_profession_api := OLD.adeli_profession_api;
    IF OLD.adeli_verifie IS TRUE THEN
      NEW.numero_adeli := OLD.numero_adeli;
      NEW.profession := OLD.profession;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_protect_adeli_verification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_adeli_verification() TO service_role;

-- Mise à jour atomique appelée uniquement par verify-document. La ligne du
-- profil est verrouillée : si une date existe déjà, elle doit être exactement
-- égale à celle de la pièce et n'est jamais écrasée.
CREATE OR REPLACE FUNCTION public.fn_preparer_identite_document(
  p_soignant_id uuid,
  p_date_naissance date,
  p_sexe text DEFAULT NULL,
  p_lieu_naissance text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_soignant public.soignants%ROWTYPE;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Accès réservé au service de vérification' USING ERRCODE = '42501';
  END IF;
  IF p_soignant_id IS NULL OR p_date_naissance IS NULL THEN
    RETURN jsonb_build_object('date_naissance_correspond', false, 'error_code', 'IDENTITE_INCOMPLETE');
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('date_naissance_correspond', false, 'error_code', 'SOIGNANT_INTROUVABLE');
  END IF;
  IF v_soignant.date_naissance IS NOT NULL
     AND v_soignant.date_naissance IS DISTINCT FROM p_date_naissance THEN
    RETURN jsonb_build_object('date_naissance_correspond', false, 'error_code', 'DATE_NAISSANCE_INCOHERENTE');
  END IF;

  UPDATE public.soignants
  SET date_naissance = COALESCE(date_naissance, p_date_naissance),
      sexe = CASE
        WHEN sexe IS NULL AND p_sexe IN ('M', 'F') THEN p_sexe
        ELSE sexe
      END,
      lieu_naissance_commune = CASE
        WHEN lieu_naissance_commune IS NULL AND NULLIF(btrim(p_lieu_naissance), '') IS NOT NULL
          THEN left(btrim(p_lieu_naissance), 120)
        ELSE lieu_naissance_commune
      END,
      modifie_le = now()
  WHERE id = p_soignant_id;

  RETURN jsonb_build_object('date_naissance_correspond', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_preparer_identite_document(uuid, date, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_identite_document(uuid, date, text, text)
  TO service_role;

-- Toute modification d'un trait d'identité rend les pièces précédemment
-- vérifiées obsolètes. Les documents restent conservés mais passent en revue.
CREATE OR REPLACE FUNCTION public.fn_invalider_preuves_identite_sur_changement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_previous_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
  v_previous_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');
  v_documents_invalides integer := 0;
  v_champs text[] := ARRAY[]::text[];
  v_nom_prenom_modifie boolean;
BEGIN
  IF NEW.prenom IS NOT DISTINCT FROM OLD.prenom
     AND NEW.nom IS NOT DISTINCT FROM OLD.nom
     AND NEW.date_naissance IS NOT DISTINCT FROM OLD.date_naissance THEN
    RETURN NEW;
  END IF;

  IF NEW.prenom IS DISTINCT FROM OLD.prenom THEN v_champs := array_append(v_champs, 'prenom'); END IF;
  IF NEW.nom IS DISTINCT FROM OLD.nom THEN v_champs := array_append(v_champs, 'nom'); END IF;
  IF NEW.date_naissance IS DISTINCT FROM OLD.date_naissance THEN v_champs := array_append(v_champs, 'date_naissance'); END IF;
  v_nom_prenom_modifie := NEW.prenom IS DISTINCT FROM OLD.prenom
    OR NEW.nom IS DISTINCT FROM OLD.nom;

  PERFORM set_config('jolene.system_update', 'true', true);
  PERFORM set_config('jolene.siret_liberal_reset', 'true', true);
  BEGIN
    UPDATE public.documents_soignants
    SET statut_verification = 'EN_ATTENTE',
        motif_rejet = 'Profil d’identité modifié après vérification — nouvelle vérification de la preuve requise.',
        verifie_le = NULL,
        verifie_par = NULL,
        valide_depuis = NULL,
        valide_jusqua = NULL,
        modifie_le = now()
    WHERE soignant_id = NEW.id
      AND statut_verification = 'VERIFIE'
      AND supprime_le IS NULL;
    GET DIAGNOSTICS v_documents_invalides = ROW_COUNT;

    UPDATE public.soignants
    SET identite_verifiee = false,
        diplome_verifie = false,
        tous_documents_valides = false,
        statut_verification_aria = 'EN_ATTENTE',
        siret_liberal_verifie = false,
        siret_liberal_verifie_le = NULL,
        siret_liberal_raison_sociale = NULL,
        siret_liberal_coherence_identite = NULL,
        rpps_verifie = CASE WHEN v_nom_prenom_modifie THEN false ELSE rpps_verifie END,
        rpps_verifie_le = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_verifie_le END,
        rpps_nom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_nom_api END,
        rpps_prenom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_prenom_api END,
        rpps_profession_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_profession_api END,
        adeli_verifie = CASE WHEN v_nom_prenom_modifie THEN false ELSE adeli_verifie END,
        adeli_verifie_le = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_verifie_le END,
        adeli_nom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_nom_api END,
        adeli_prenom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_prenom_api END,
        adeli_profession_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_profession_api END,
        specialite_verifiee = CASE WHEN v_nom_prenom_modifie THEN false ELSE specialite_verifiee END,
        specialite_verifiee_le = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_verifiee_le END,
        specialite_medicale = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_medicale END,
        specialite_code = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_code END,
        specialite_source = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_source END,
        coherence_identite = 'EN_ATTENTE_REVUE',
        coherence_details = jsonb_build_object(
          'raison', 'PROFIL_IDENTITE_MODIFIE',
          'champs_modifies', to_jsonb(v_champs),
          'documents_invalides', v_documents_invalides,
          'invalide_le', now()
        ),
        modifie_le = now()
    WHERE id = NEW.id;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('jolene.siret_liberal_reset', v_previous_siret_reset, true);
    PERFORM set_config('jolene.system_update', v_previous_system_update, true);
    RAISE;
  END;
  PERFORM set_config('jolene.siret_liberal_reset', v_previous_siret_reset, true);
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := NEW.id,
    p_type_acteur := CASE WHEN auth.uid() = NEW.id THEN 'SOIGNANT' ELSE 'SYSTEME' END,
    p_action := 'IDENTITE_PROFIL_MODIFIEE',
    p_type_ressource := 'soignant',
    p_id_ressource := NEW.id,
    p_details := jsonb_build_object(
      'champs_modifies', to_jsonb(v_champs),
      'preuves_identite_invalidees', v_documents_invalides
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invalider_preuves_identite_sur_changement ON public.soignants;
CREATE TRIGGER trg_invalider_preuves_identite_sur_changement
AFTER UPDATE OF prenom, nom, date_naissance ON public.soignants
FOR EACH ROW
WHEN (
  NEW.prenom IS DISTINCT FROM OLD.prenom
  OR NEW.nom IS DISTINCT FROM OLD.nom
  OR NEW.date_naissance IS DISTINCT FROM OLD.date_naissance
)
EXECUTE FUNCTION public.fn_invalider_preuves_identite_sur_changement();

REVOKE ALL ON FUNCTION public.fn_invalider_preuves_identite_sur_changement()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_invalider_preuves_identite_sur_changement()
  TO service_role;

-- Le parcours profil autorise maintenant une correction réelle de nom/prénom.
-- Le trigger précédent se charge de la révocation, y compris lorsque
-- identite_verifiee était encore faux (cas AS/AES avec CNI déjà vérifiée).
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
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
  v_champs_modifies jsonb := '[]'::jsonb;
  v_existe boolean;
  v_email text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  IF p_prenom IS NOT NULL AND NULLIF(btrim(p_prenom), '') IS NULL THEN
    RETURN jsonb_build_object('error', 'Le prénom ne peut pas être vide');
  END IF;
  IF p_nom IS NOT NULL AND NULLIF(btrim(p_nom), '') IS NULL THEN
    RETURN jsonb_build_object('error', 'Le nom ne peut pas être vide');
  END IF;

  PERFORM set_config('jolene.rpc_update', 'true', true);
  SELECT EXISTS(SELECT 1 FROM public.soignants WHERE id = v_uid) INTO v_existe;

  IF NOT v_existe THEN
    SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
    INSERT INTO public.soignants (
      id, email, prenom, nom, telephone, date_naissance,
      numero_rpps, numero_adeli, profession
    ) VALUES (
      v_uid,
      COALESCE(v_email, 'inconnu@jolene.app'),
      COALESCE(NULLIF(btrim(p_prenom), ''), ''),
      COALESCE(NULLIF(btrim(p_nom), ''), ''),
      p_telephone,
      p_date_naissance,
      p_numero_rpps,
      p_numero_adeli,
      CASE WHEN p_profession IS NOT NULL THEN p_profession::public.type_profession ELSE NULL END
    );
  END IF;

  UPDATE public.soignants SET
    prenom = COALESCE(NULLIF(btrim(p_prenom), ''), prenom),
    nom = COALESCE(NULLIF(btrim(p_nom), ''), nom),
    profession = CASE
      WHEN profession IS NOT NULL THEN profession
      WHEN p_profession IS NOT NULL THEN p_profession::public.type_profession
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
      WHEN rpps_verifie IS TRUE THEN numero_rpps
      ELSE COALESCE(p_numero_rpps, numero_rpps)
    END,
    numero_adeli = CASE
      WHEN adeli_verifie IS TRUE THEN numero_adeli
      ELSE COALESCE(p_numero_adeli, numero_adeli)
    END,
    avatar_url = COALESCE(p_avatar_url, avatar_url),
    types_contrat_acceptes = CASE
      WHEN p_types_contrat_acceptes IS NOT NULL THEN p_types_contrat_acceptes
      WHEN p_types_contrat IS NOT NULL THEN array_to_string(p_types_contrat, ',')
      ELSE types_contrat_acceptes
    END,
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
    attestation_cumul_le = CASE
      WHEN p_attestation_cumul_activite IS TRUE THEN now()
      ELSE attestation_cumul_le
    END,
    consentement_gps_le = CASE
      WHEN p_consentement_gps IS NOT NULL THEN now()
      ELSE consentement_gps_le
    END,
    modifie_le = now()
  WHERE id = v_uid;

  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(btrim(split_part(COALESCE(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
    v_user_agent := NULL;
  END;

  IF p_prenom IS NOT NULL OR p_nom IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identite"'::jsonb; END IF;
  IF p_telephone IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"telephone"'::jsonb; END IF;
  IF p_date_naissance IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"date_naissance"'::jsonb; END IF;
  IF p_adresse_rue IS NOT NULL OR p_adresse_ville IS NOT NULL OR p_adresse_lat IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"adresse"'::jsonb; END IF;
  IF p_numero_rpps IS NOT NULL OR p_numero_adeli IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"identifiants_professionnels"'::jsonb; END IF;
  IF p_type_exercice IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"type_exercice"'::jsonb; END IF;
  IF p_consentement_gps IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"consentement_gps"'::jsonb; END IF;
  IF p_profession IS NOT NULL THEN v_champs_modifies := v_champs_modifies || '"profession"'::jsonb; END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'MODIFICATION_PROFIL',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('champs_modifies', v_champs_modifies),
    p_ip := v_ip,
    p_navigateur := v_user_agent
  );
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_modifier_mon_profil(
  text, text, text, date, text, text, text, numeric, numeric, integer,
  text, text, text, text[], text, integer, text[], numeric, text, text,
  text, boolean, integer, boolean, boolean, boolean, boolean, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_modifier_mon_profil(
  text, text, text, date, text, text, text, numeric, numeric, integer,
  text, text, text, text[], text, integer, text[], numeric, text, text,
  text, boolean, integer, boolean, boolean, boolean, boolean, text, text
) TO authenticated, service_role;

-- Comparaison déterministe des traits d'identité. Les noms de famille doivent
-- partager exactement tous les tokens du libellé le plus court et au moins un
-- prénom complet doit être commun. Un booléen produit précédemment par l'IA ne
-- constitue jamais, à lui seul, une preuve réutilisable après modification du
-- profil.
CREATE OR REPLACE FUNCTION public.fn_noms_personne_correspondent(
  p_nom_attendu text,
  p_prenom_attendu text,
  p_nom_extrait text,
  p_prenom_extrait text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, public
AS $$
  WITH valeurs AS (
    SELECT
      regexp_split_to_array(NULLIF(btrim(regexp_replace(public.fn_normaliser_nom(p_nom_attendu), '[^a-z0-9]+', ' ', 'g')), ''), ' +') AS nom_attendu,
      regexp_split_to_array(NULLIF(btrim(regexp_replace(public.fn_normaliser_nom(p_nom_extrait), '[^a-z0-9]+', ' ', 'g')), ''), ' +') AS nom_extrait,
      regexp_split_to_array(NULLIF(btrim(regexp_replace(public.fn_normaliser_nom(p_prenom_attendu), '[^a-z0-9]+', ' ', 'g')), ''), ' +') AS prenom_attendu,
      regexp_split_to_array(NULLIF(btrim(regexp_replace(public.fn_normaliser_nom(p_prenom_extrait), '[^a-z0-9]+', ' ', 'g')), ''), ' +') AS prenom_extrait
  ), controle AS (
    SELECT *,
      CASE WHEN cardinality(nom_attendu) <= cardinality(nom_extrait)
        THEN nom_attendu <@ nom_extrait ELSE nom_extrait <@ nom_attendu END AS nom_ok,
      EXISTS (
        SELECT 1 FROM unnest(prenom_attendu) AS attendu(token)
        WHERE attendu.token = ANY(prenom_extrait)
      ) AS prenom_ok
    FROM valeurs
  )
  SELECT COALESCE(
    cardinality(nom_attendu) > 0
    AND cardinality(nom_extrait) > 0
    AND cardinality(prenom_attendu) > 0
    AND cardinality(prenom_extrait) > 0
    AND nom_ok AND prenom_ok,
    false
  )
  FROM controle;
$$;

REVOKE ALL ON FUNCTION public.fn_noms_personne_correspondent(text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_noms_personne_correspondent(text, text, text, text)
  TO service_role;

-- Cohérence documentaire indépendante de la présence d'un RPPS : les AS/AES
-- peuvent donc obtenir identite_verifiee avec une pièce officielle concordante.
CREATE OR REPLACE FUNCTION public.fn_verifier_coherence_identite(p_soignant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_soignant public.soignants%ROWTYPE;
  v_doc_identite public.documents_soignants%ROWTYPE;
  v_date_document date;
  v_date_brute text;
  v_doc_found boolean := false;
  v_nom_ok boolean := false;
  v_date_ok boolean := false;
  v_all_ok boolean := false;
  v_details jsonb;
  v_previous_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
BEGIN
  SELECT * INTO v_soignant FROM public.soignants WHERE id = p_soignant_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;

  SELECT * INTO v_doc_identite
  FROM public.documents_soignants
  WHERE soignant_id = p_soignant_id
    AND type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
    AND statut_verification = 'VERIFIE'
    AND supprime_le IS NULL
  ORDER BY COALESCE(verifie_le, televerse_le) DESC, televerse_le DESC
  LIMIT 1;
  v_doc_found := FOUND;

  IF v_doc_found THEN
    v_nom_ok := public.fn_noms_personne_correspondent(
      v_soignant.nom,
      v_soignant.prenom,
      v_doc_identite.nom_extrait_ia,
      v_doc_identite.prenom_extrait_ia
    );
    v_date_brute := v_doc_identite.resultat_ia->>'date_naissance_extraite';
    IF v_date_brute ~ '^\d{4}-\d{2}-\d{2}$' THEN
      BEGIN
        v_date_document := v_date_brute::date;
        IF to_char(v_date_document, 'YYYY-MM-DD') IS DISTINCT FROM v_date_brute THEN
          v_date_document := NULL;
        END IF;
      EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
        v_date_document := NULL;
      END;
    END IF;
    v_date_ok := v_soignant.date_naissance IS NOT NULL
      AND v_date_document IS NOT NULL
      AND v_soignant.date_naissance = v_date_document;
  END IF;

  v_all_ok := v_doc_found AND v_nom_ok AND v_date_ok;
  v_details := jsonb_build_object(
    'type_document', CASE WHEN v_doc_identite.id IS NULL THEN NULL ELSE v_doc_identite.type_document::text END,
    'document_id', v_doc_identite.id,
    'nom_prenom_correspondent', v_nom_ok,
    'date_naissance_correspond', v_date_ok,
    'verifie_le', now()
  );

  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET coherence_identite = CASE
        WHEN v_doc_identite.id IS NULL THEN 'NON_VERIFIE'
        WHEN v_all_ok THEN 'COHERENT'
        ELSE 'INCOHERENT'
      END,
      coherence_details = v_details,
      identite_verifiee = v_all_ok,
      modifie_le = now()
  WHERE id = p_soignant_id;
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);

  IF NOT v_all_ok AND v_doc_identite.id IS NOT NULL THEN
    INSERT INTO public.file_revue_manuelle (
      type_entite, id_entite, service_en_echec, motif_echec,
      donnees_originales, statut, priorite
    ) VALUES (
      'SOIGNANT', p_soignant_id, 'COHERENCE_IDENTITE',
      'La pièce d''identité ne correspond pas exactement au nom, au prénom et à la date de naissance du profil.',
      v_details, 'EN_ATTENTE', 4
    ) ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('coherent', v_all_ok, 'details', v_details);
END;
$$;

CREATE OR REPLACE FUNCTION public.dec_check_coherence_apres_doc_identite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR') THEN
      PERFORM public.fn_verifier_coherence_identite(OLD.soignant_id);
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR') THEN
      PERFORM public.fn_verifier_coherence_identite(NEW.soignant_id);
    END IF;
    RETURN NEW;
  END IF;

  -- En AFTER UPDATE, la ligne visible est déjà NEW. Recalculer l'ancien
  -- propriétaire couvre aussi le retrait d'une preuve (type changé, suppression
  -- logique ou réaffectation). Le nouveau propriétaire est recalculé séparément
  -- uniquement lorsqu'il ne coïncide pas avec le premier calcul.
  IF OLD.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR') THEN
    PERFORM public.fn_verifier_coherence_identite(OLD.soignant_id);
  END IF;
  IF NEW.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
     AND (
       OLD.type_document NOT IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
       OR OLD.soignant_id IS DISTINCT FROM NEW.soignant_id
     ) THEN
    PERFORM public.fn_verifier_coherence_identite(NEW.soignant_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_coherence_doc_identite ON public.documents_soignants;
CREATE TRIGGER trg_check_coherence_doc_identite
AFTER INSERT OR DELETE OR UPDATE OF
  soignant_id,
  type_document,
  statut_verification,
  supprime_le,
  verifie_le,
  televerse_le,
  resultat_ia,
  nom_extrait_ia,
  prenom_extrait_ia,
  coherence_nom
ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.dec_check_coherence_apres_doc_identite();

REVOKE ALL ON FUNCTION public.fn_verifier_coherence_identite(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dec_check_coherence_apres_doc_identite() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verifier_coherence_identite(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.dec_check_coherence_apres_doc_identite() TO service_role;

-- Une exigence « CARTE_IDENTITE » désigne juridiquement une pièce officielle,
-- et peut donc être satisfaite par une CNI, un passeport ou un titre de séjour.
-- Les autres types restent strictement égaux.
CREATE OR REPLACE FUNCTION public.fn_type_document_preuve_compatible(
  p_type_requis public.type_document,
  p_type_fourni public.type_document
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_type_requis IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
      THEN p_type_fourni IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
    ELSE p_type_fourni = p_type_requis
  END;
$$;

REVOKE ALL ON FUNCTION public.fn_type_document_preuve_compatible(
  public.type_document, public.type_document
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_type_document_preuve_compatible(
  public.type_document, public.type_document
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission(
  p_soignant_id uuid,
  p_type_contrat text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_profession public.type_profession;
  v_identifiant_officiel boolean;
  v_regime_liberal boolean;
  v_liberal_actif boolean;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN false; END IF;

  -- Fonction interne uniquement. Les triggers/RPC SECURITY DEFINER conservent
  -- comme current_user leur propriétaire privilégié et peuvent évaluer le
  -- soignant concerné; le service role est le seul rôle API autorisé.
  IF current_user NOT IN ('postgres', 'supabase_admin', 'service_role')
     AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Calcul documentaire réservé au service interne.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT profession,
         COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false),
         COALESCE(statut_compte::text, 'ACTIF') = 'ACTIF'
           AND COALESCE(type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')
           AND statut_liberal = 'ACTIF'
           AND siret_liberal ~ '^[0-9]{14}$'
           AND siret_liberal_verifie IS TRUE
           AND siret_liberal_verifie_le IS NOT NULL
           AND siret_liberal_coherence_identite IS TRUE
    INTO v_profession, v_identifiant_officiel, v_liberal_actif
  FROM public.soignants
  WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND OR v_profession IS NULL THEN RETURN false; END IF;

  v_regime_liberal := upper(COALESCE(p_type_contrat, 'SALARIE')) = 'LIBERAL';
  IF v_regime_liberal AND NOT COALESCE(v_liberal_actif, false) THEN
    RETURN false;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1
    FROM public.documents_requis_par_profession drp
    WHERE drp.profession = v_profession
      AND drp.est_critique IS TRUE
      AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal)
      )
      AND NOT (
        (drp.type_document = 'RPPS_ADELI' AND v_identifiant_officiel)
        OR (
          drp.type_document NOT IN ('RPPS_ADELI', 'DIPLOME')
          AND EXISTS (
            SELECT 1
            FROM public.documents_soignants ds
            WHERE ds.soignant_id = p_soignant_id
              AND public.fn_type_document_preuve_compatible(
                drp.type_document,
                ds.type_document
              )
              AND ds.statut_verification = 'VERIFIE'
              AND ds.supprime_le IS NULL
              AND (
                drp.a_expiration IS FALSE
                OR (ds.valide_jusqua IS NOT NULL AND ds.valide_jusqua > current_date)
              )
          )
        )
        OR (
          drp.type_document = 'DIPLOME'
          AND EXISTS (
            SELECT 1
            FROM public.documents_soignants ds
            WHERE ds.soignant_id = p_soignant_id
              AND ds.type_document = 'DIPLOME'
              AND ds.statut_verification = 'VERIFIE'
              AND ds.supprime_le IS NULL
          )
        )
      )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_documents_ok_pour_mission(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_documents_ok_pour_mission(uuid, text)
  TO service_role;

-- Cette fonction de recalcul n'est jamais appelée directement par le front :
-- les triggers et RPC serveur la déclenchent sous leur propriétaire. Retirer
-- authenticated ferme l'écriture BOLA d'un cache documentaire arbitraire.
REVOKE ALL ON FUNCTION public.fn_calculer_tous_documents_valides(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_calculer_tous_documents_valides(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.dec_verifier_docs_jusqua_fin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_type_manquant public.type_document;
  v_regime_liberal boolean;
  v_verifier boolean := false;
BEGIN
  IF NEW.statut = 'ASSIGNEE' AND NEW.soignant_assigne_id IS NOT NULL THEN
    IF TG_OP = 'INSERT' THEN
      v_verifier := true;
    ELSE
      v_verifier := OLD.statut IS DISTINCT FROM NEW.statut
        OR OLD.soignant_assigne_id IS DISTINCT FROM NEW.soignant_assigne_id
        OR OLD.type_contrat_applique IS DISTINCT FROM NEW.type_contrat_applique;
    END IF;
  END IF;

  IF v_verifier THEN
    IF NEW.type_contrat_applique IS NULL THEN
      RAISE EXCEPTION 'Le contrat appliqué doit être déterminé avant l''affectation.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_regime_liberal := upper(COALESCE(NEW.type_contrat_applique::text, 'SALARIE')) = 'LIBERAL';

    IF NOT public.fn_documents_ok_pour_mission(
      NEW.soignant_assigne_id,
      NEW.type_contrat_applique::text
    ) THEN
      RAISE EXCEPTION 'Les documents obligatoires ne sont pas tous vérifiés pour le contrat attribué.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT drp.type_document
      INTO v_type_manquant
    FROM public.documents_requis_par_profession drp
    JOIN public.soignants s
      ON s.id = NEW.soignant_assigne_id
     AND s.profession = drp.profession
     AND s.supprime_le IS NULL
    WHERE drp.est_critique IS TRUE
      AND drp.type_document NOT IN ('RPPS_ADELI', 'DIPLOME')
      AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal)
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.documents_soignants ds
        WHERE ds.soignant_id = NEW.soignant_assigne_id
          AND public.fn_type_document_preuve_compatible(
            drp.type_document,
            ds.type_document
          )
          AND ds.statut_verification = 'VERIFIE'
          AND ds.supprime_le IS NULL
          AND (
            drp.a_expiration IS FALSE
            OR (
              ds.valide_jusqua IS NOT NULL
              AND ds.valide_jusqua >= NEW.fin_le::date
            )
          )
      )
    LIMIT 1;

    IF v_type_manquant IS NOT NULL THEN
      RAISE EXCEPTION 'Aucun document vérifié de type « % » ne couvre la mission jusqu’au %. Veuillez le renouveler.',
        v_type_manquant,
        to_char(NEW.fin_le, 'DD/MM/YYYY')
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.dec_verifier_docs_jusqua_fin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_verifier_docs_jusqua_fin() TO service_role;

DROP TRIGGER IF EXISTS dec_docs_fin_mission ON public.missions;
CREATE TRIGGER dec_docs_fin_mission
BEFORE INSERT OR UPDATE ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_docs_jusqua_fin();

CREATE OR REPLACE FUNCTION public.fn_verifier_documents_expirants()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_count integer := 0;
  v_doc record;
  v_sid uuid;
BEGIN
  FOR v_doc IN
    SELECT d.id, d.soignant_id, d.type_document, d.valide_jusqua, s.prenom, s.email
    FROM public.documents_soignants d
    JOIN public.soignants s ON s.id = d.soignant_id
    WHERE d.valide_jusqua IS NOT NULL
      AND d.valide_jusqua BETWEEN current_date AND current_date + 30
      AND d.supprime_le IS NULL
      AND d.statut_verification = 'VERIFIE'
      AND d.rappel_j30_envoye IS FALSE
  LOOP
    UPDATE public.documents_soignants SET rappel_j30_envoye = true WHERE id = v_doc.id;
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_doc.soignant_id, 'DOCUMENT_EXPIRANT', 'Document bientôt expiré ⚠️',
      'Votre ' || v_doc.type_document || ' expire le ' || v_doc.valide_jusqua,
      '/soignant/documents', 'SOIGNANT'
    );
    v_count := v_count + 1;
  END LOOP;

  FOR v_doc IN
    SELECT d.id, d.soignant_id, d.type_document, d.valide_jusqua
    FROM public.documents_soignants d
    WHERE d.valide_jusqua IS NOT NULL
      AND d.valide_jusqua BETWEEN current_date AND current_date + 7
      AND d.supprime_le IS NULL
      AND d.rappel_j7_envoye IS FALSE
  LOOP
    UPDATE public.documents_soignants SET rappel_j7_envoye = true WHERE id = v_doc.id;
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_doc.soignant_id, 'DOCUMENT_EXPIRANT', '⚠️ Document expire dans 7 jours',
      'Votre ' || v_doc.type_document || ' expire le ' || v_doc.valide_jusqua || '. Renouvelez-le maintenant.',
      '/soignant/documents', 'SOIGNANT'
    );
    v_count := v_count + 1;
  END LOOP;

  FOR v_sid IN
    SELECT DISTINCT d.soignant_id
    FROM public.documents_soignants d
    JOIN public.soignants s ON s.id = d.soignant_id
    JOIN public.documents_requis_par_profession r
      ON r.profession = s.profession
     AND public.fn_type_document_preuve_compatible(r.type_document, d.type_document)
    WHERE d.valide_jusqua < current_date
      AND d.supprime_le IS NULL
      AND r.est_critique IS TRUE
  LOOP
    PERFORM public.fn_calculer_tous_documents_valides(v_sid);
  END LOOP;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_verifier_documents_expirants() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verifier_documents_expirants() TO service_role;

-- ---------------------------------------------------------------------------
-- Droits étudiants : la source documentaire reste l'unique source de vérité
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_recalculer_preuves_etudiant(p_soignant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_profession public.type_profession;
  v_scolarite_doc_id uuid;
  v_scolarite_formation text;
  v_scolarite_annee integer;
  v_scolarite_verifiee_le timestamptz;
  v_licence_doc_id uuid;
  v_licence_verifiee_le timestamptz;
  v_licence_valide_jusqua date;
  v_licence_specialite text;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true),
    ''
  );
BEGIN
  IF p_soignant_id IS NULL THEN
    RETURN;
  END IF;

  SELECT s.profession
  INTO v_profession
  FROM public.soignants s
  WHERE s.id = p_soignant_id
    AND s.supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT
    ds.id,
    x.formation,
    x.annee_validee,
    ds.verifie_le
  INTO
    v_scolarite_doc_id,
    v_scolarite_formation,
    v_scolarite_annee,
    v_scolarite_verifiee_le
  FROM public.documents_soignants ds
  CROSS JOIN LATERAL (
    SELECT
      upper(NULLIF(btrim(ds.resultat_ia->>'scolarite_formation'), '')) AS formation,
      CASE
        WHEN COALESCE(ds.resultat_ia->>'scolarite_annee_validee', '') ~ '^\d{1,2}$'
          THEN (ds.resultat_ia->>'scolarite_annee_validee')::integer
        ELSE NULL
      END AS annee_validee
  ) x
  WHERE ds.soignant_id = p_soignant_id
    AND ds.type_document = 'ATTESTATION_SCOLARITE'
    AND ds.statut_verification = 'VERIFIE'
    AND ds.supprime_le IS NULL
    AND ds.verifie_le IS NOT NULL
    AND ds.coherence_nom IS TRUE
    AND ds.valide_depuis IS NOT NULL
    AND ds.valide_depuis BETWEEN current_date - 400 AND current_date
    AND (ds.valide_jusqua IS NULL OR ds.valide_jusqua > current_date)
    AND COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'
    AND COALESCE(ds.resultat_ia->>'type_correspond', 'false') = 'true'
    AND COALESCE(ds.resultat_ia->>'document_lisible', 'false') = 'true'
    AND COALESCE(ds.resultat_ia->>'document_complet', 'false') = 'true'
    AND x.formation = ANY (ARRAY[
      'IFSI', 'IFAS', 'MEDECINE_DFGSM', 'MEDECINE_DFASM', 'PHARMACIE',
      'MAIEUTIQUE', 'ODONTOLOGIE', 'KINE', 'ERGOTHERAPIE',
      'PSYCHOMOTRICITE', 'MANIP_RADIO'
    ])
    AND x.annee_validee BETWEEN 0 AND CASE x.formation
      WHEN 'IFSI' THEN 3
      WHEN 'IFAS' THEN 1
      WHEN 'MEDECINE_DFGSM' THEN 3
      WHEN 'MEDECINE_DFASM' THEN 3
      WHEN 'PHARMACIE' THEN 9
      WHEN 'MAIEUTIQUE' THEN 6
      WHEN 'ODONTOLOGIE' THEN 9
      WHEN 'KINE' THEN 5
      WHEN 'ERGOTHERAPIE' THEN 3
      WHEN 'PSYCHOMOTRICITE' THEN 3
      WHEN 'MANIP_RADIO' THEN 3
      ELSE -1
    END
    AND EXISTS (
      SELECT 1
      FROM public.fn_professions_autorisees_scolarite(
        x.formation,
        x.annee_validee
      ) AS autorisee(profession)
      WHERE autorisee.profession = v_profession
    )
  ORDER BY ds.valide_depuis DESC, ds.verifie_le DESC, ds.id DESC
  LIMIT 1;

  SELECT
    ds.id,
    ds.verifie_le,
    ds.valide_jusqua,
    left(btrim(ds.resultat_ia->>'licence_remplacement_specialite'), 200)
  INTO
    v_licence_doc_id,
    v_licence_verifiee_le,
    v_licence_valide_jusqua,
    v_licence_specialite
  FROM public.documents_soignants ds
  WHERE ds.soignant_id = p_soignant_id
    AND v_profession = 'MEDECIN'
    AND ds.type_document = 'LICENCE_REMPLACEMENT'
    AND ds.statut_verification = 'VERIFIE'
    AND ds.supprime_le IS NULL
    AND ds.verifie_le IS NOT NULL
    AND ds.coherence_nom IS TRUE
    AND ds.valide_depuis IS NOT NULL
    AND ds.valide_depuis <= current_date
    AND ds.valide_jusqua IS NOT NULL
    AND ds.valide_jusqua > current_date
    AND ds.valide_jusqua <= (ds.valide_depuis + interval '13 months')::date
    AND NULLIF(btrim(ds.resultat_ia->>'licence_remplacement_specialite'), '') IS NOT NULL
    AND COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'
    AND COALESCE(ds.resultat_ia->>'type_correspond', 'false') = 'true'
    AND COALESCE(ds.resultat_ia->>'document_lisible', 'false') = 'true'
    AND COALESCE(ds.resultat_ia->>'document_complet', 'false') = 'true'
  ORDER BY ds.valide_jusqua DESC, ds.verifie_le DESC, ds.id DESC
  LIMIT 1;

  -- Le garde-fou de profil n'accepte ces champs serveur que pendant cette
  -- cascade bornée. La valeur est restaurée avant de rendre la main.
  PERFORM set_config('jolene.system_update', 'true', true);
  BEGIN
    UPDATE public.soignants s
    SET scolarite_formation = CASE
          WHEN v_scolarite_doc_id IS NOT NULL THEN v_scolarite_formation
          ELSE NULL
        END,
        scolarite_annee_validee = CASE
          WHEN v_scolarite_doc_id IS NOT NULL THEN v_scolarite_annee
          ELSE NULL
        END,
        scolarite_profession_autorisee = CASE
          WHEN v_scolarite_doc_id IS NOT NULL THEN v_profession
          ELSE NULL
        END,
        scolarite_verifiee = v_scolarite_doc_id IS NOT NULL,
        scolarite_verifiee_le = CASE
          WHEN v_scolarite_doc_id IS NOT NULL THEN v_scolarite_verifiee_le
          ELSE NULL
        END,
        licence_remplacement_verifiee = v_licence_doc_id IS NOT NULL,
        licence_remplacement_le = CASE
          WHEN v_licence_doc_id IS NOT NULL THEN v_licence_verifiee_le
          ELSE NULL
        END,
        licence_remplacement_valide_jusqua = CASE
          WHEN v_licence_doc_id IS NOT NULL THEN v_licence_valide_jusqua
          ELSE NULL
        END,
        licence_remplacement_specialite = CASE
          WHEN v_licence_doc_id IS NOT NULL THEN v_licence_specialite
          ELSE NULL
        END,
        modifie_le = now()
    WHERE s.id = p_soignant_id;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config(
      'jolene.system_update',
      v_previous_system_update,
      true
    );
    RAISE;
  END;
  PERFORM set_config(
    'jolene.system_update',
    v_previous_system_update,
    true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_recalculer_preuves_etudiant(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_recalculer_preuves_etudiant(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_trg_recalculer_preuves_etudiant_document()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.type_document IN ('ATTESTATION_SCOLARITE', 'LICENCE_REMPLACEMENT') THEN
      PERFORM public.fn_recalculer_preuves_etudiant(OLD.soignant_id);
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.type_document IN ('ATTESTATION_SCOLARITE', 'LICENCE_REMPLACEMENT') THEN
      PERFORM public.fn_recalculer_preuves_etudiant(NEW.soignant_id);
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.type_document IN ('ATTESTATION_SCOLARITE', 'LICENCE_REMPLACEMENT') THEN
    PERFORM public.fn_recalculer_preuves_etudiant(OLD.soignant_id);
  END IF;
  IF NEW.type_document IN ('ATTESTATION_SCOLARITE', 'LICENCE_REMPLACEMENT')
     AND (
       OLD.type_document NOT IN ('ATTESTATION_SCOLARITE', 'LICENCE_REMPLACEMENT')
       OR OLD.soignant_id IS DISTINCT FROM NEW.soignant_id
     ) THEN
    PERFORM public.fn_recalculer_preuves_etudiant(NEW.soignant_id);
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_trg_recalculer_preuves_etudiant_document()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_recalculer_preuves_etudiant_document()
  TO service_role;

DROP TRIGGER IF EXISTS trg_recalculer_preuves_etudiant_document_insert_delete
  ON public.documents_soignants;
CREATE TRIGGER trg_recalculer_preuves_etudiant_document_insert_delete
AFTER INSERT OR DELETE ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_recalculer_preuves_etudiant_document();

DROP TRIGGER IF EXISTS trg_recalculer_preuves_etudiant_document_update
  ON public.documents_soignants;
CREATE TRIGGER trg_recalculer_preuves_etudiant_document_update
AFTER UPDATE OF
  soignant_id,
  type_document,
  statut_verification,
  supprime_le,
  valide_depuis,
  valide_jusqua,
  verifie_le,
  resultat_ia,
  coherence_nom
ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_recalculer_preuves_etudiant_document();

CREATE OR REPLACE FUNCTION public.fn_trg_recalculer_preuves_etudiant_profession()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.fn_recalculer_preuves_etudiant(NEW.id);
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_trg_recalculer_preuves_etudiant_profession()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_recalculer_preuves_etudiant_profession()
  TO service_role;

DROP TRIGGER IF EXISTS trg_recalculer_preuves_etudiant_profession
  ON public.soignants;
CREATE TRIGGER trg_recalculer_preuves_etudiant_profession
AFTER UPDATE OF profession ON public.soignants
FOR EACH ROW
WHEN (OLD.profession IS DISTINCT FROM NEW.profession)
EXECUTE FUNCTION public.fn_trg_recalculer_preuves_etudiant_profession();

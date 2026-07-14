-- Modération documentaire soignant : une décision humaine ne peut plus être
-- un simple changement de statut. La RPC revalide sous verrou le document, sa
-- source Storage, le profil et les champs métier saisis par l'administrateur.
-- Le snapshot de décision et la source sont écrits dans le même audit que le
-- verdict. Aucune donnée de démonstration n'est modifiée par cette migration.

CREATE SCHEMA IF NOT EXISTS private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_date_iso_moderation(p_value text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
DECLARE
  v_date date;
  v_value text := NULLIF(btrim(p_value), '');
BEGIN
  IF v_value IS NULL OR v_value !~ '^\d{4}-\d{2}-\d{2}$' THEN
    RETURN NULL;
  END IF;
  BEGIN
    v_date := v_value::date;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RETURN NULL;
  END;
  IF to_char(v_date, 'YYYY-MM-DD') IS DISTINCT FROM v_value THEN
    RETURN NULL;
  END IF;
  RETURN v_date;
END;
$$;

CREATE OR REPLACE FUNCTION private.fn_iban_valide_moderation(p_iban text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
DECLARE
  v_iban text := upper(regexp_replace(COALESCE(p_iban, ''), '[^A-Za-z0-9]', '', 'g'));
  v_rearrange text;
  v_char text;
  v_numeric text;
  v_reste integer := 0;
  i integer;
  j integer;
BEGIN
  IF v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'
     OR length(v_iban) < 15
     OR length(v_iban) > 34 THEN
    RETURN false;
  END IF;
  v_rearrange := substr(v_iban, 5) || substr(v_iban, 1, 4);
  FOR i IN 1..length(v_rearrange) LOOP
    v_char := substr(v_rearrange, i, 1);
    IF v_char ~ '^[0-9]$' THEN
      v_numeric := v_char;
    ELSE
      v_numeric := (ascii(v_char) - 55)::text;
    END IF;
    FOR j IN 1..length(v_numeric) LOOP
      v_reste := (v_reste * 10 + substr(v_numeric, j, 1)::integer) % 97;
    END LOOP;
  END LOOP;
  RETURN v_reste = 1;
END;
$$;

REVOKE ALL ON FUNCTION private.fn_date_iso_moderation(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fn_iban_valide_moderation(text)
  FROM PUBLIC, anon, authenticated, service_role;

-- Même un administrateur AAL2 ne peut plus contourner la RPC par un UPDATE
-- direct de la table. Les écritures serveur automatiques et les cascades
-- internes restent autorisées, ainsi que la transaction de modération bornée.
CREATE OR REPLACE FUNCTION public.fn_proteger_document_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_role text := COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    auth.jwt() ->> 'role',
    ''
  );
BEGIN
  IF v_role = 'service_role'
     OR auth.uid() IS NULL
     OR COALESCE(current_setting('jolene.system_update', true), '') = 'true'
     OR COALESCE(current_setting('jolene.document_server_update', true), '') = 'true'
     OR COALESCE(current_setting('jolene.document_moderation_rpc', true), '') = 'true' THEN
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
     OR NEW.coherence_nom IS DISTINCT FROM OLD.coherence_nom
     OR NEW.verification_attempt_id IS DISTINCT FROM OLD.verification_attempt_id THEN
    RAISE EXCEPTION 'Les champs de vérification documentaire ne sont modifiables que par le parcours sécurisé'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
    RAISE EXCEPTION 'Modification du propriétaire interdite'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_proteger_document_verification()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_proteger_document_verification()
  TO service_role;

-- Variante contextualisée appelée par l'interface de modération. La surcharge
-- historique à trois paramètres est redéfinie plus bas comme hard stop.
CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document(
  p_document_id uuid,
  p_action text,
  p_motif text,
  p_validation_manuelle jsonb,
  p_raison_override text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_action text := upper(NULLIF(btrim(p_action), ''));
  v_validation jsonb := COALESCE(p_validation_manuelle, '{}'::jsonb);
  v_doc public.documents_soignants%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_heures public.heures_externes%ROWTYPE;
  v_expected_doc_modifie timestamptz;
  v_expected_soignant_modifie timestamptz;
  v_nom_extrait text;
  v_prenom_extrait text;
  v_date_naissance date;
  v_date_emission date;
  v_date_expiration date;
  v_date_emission_raw text;
  v_date_expiration_raw text;
  v_profession_certifiee text;
  v_type_identifiant text;
  v_numero_professionnel text;
  v_numero_attendu text;
  v_iban text;
  v_iban_normalise text;
  v_iban_last4 text;
  v_liaison_bancaire jsonb;
  v_exige_expiration boolean := false;
  v_diplome_compatible boolean := false;
  v_diplome_etranger boolean := false;
  v_formation text;
  v_annee_validee integer;
  v_specialite_licence text;
  v_override_requis boolean := false;
  v_ai_indisponible boolean := false;
  v_source text;
  v_raison_override text := NULLIF(btrim(p_raison_override), '');
  v_snapshot jsonb;
  v_resultat_final jsonb;
  v_previous_moderation text := COALESCE(
    current_setting('jolene.document_moderation_rpc', true),
    ''
  );
  v_row_count integer := 0;
  v_allowed_key text;
BEGIN
  -- est_admin() impose déjà rôle app_metadata, compte actif, registre
  -- equipe_admin complet et AAL2. Le contrôle AAL explicite protège aussi
  -- contre une future régression de cette fonction partagée.
  IF v_uid IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorisé requis'
      USING ERRCODE = '42501';
  END IF;
  IF p_document_id IS NULL OR v_action NOT IN ('VALIDER', 'REJETER') THEN
    RAISE EXCEPTION 'Action de modération invalide'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(v_validation) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Contexte de modération invalide'
      USING ERRCODE = '22023';
  END IF;

  -- Liste blanche : empêche de journaliser ou conserver par mégarde un champ
  -- arbitraire/sensible fourni par le navigateur.
  SELECT key INTO v_allowed_key
  FROM jsonb_object_keys(v_validation) AS keys(key)
  WHERE key <> ALL (ARRAY[
    'expected_document_modifie_le', 'expected_soignant_modifie_le',
    'expected_statut', 'expected_type_document', 'expected_soignant_id',
    'expected_s3_bucket', 'expected_s3_cle', 'expected_s3_version_id',
    'document_lisible', 'document_complet', 'type_document_confirme',
    'antifraude_verifiee', 'override_confirme', 'nom_extrait',
    'prenom_extrait', 'date_naissance', 'date_emission', 'date_expiration',
    'profession_certifiee', 'diplome_etranger',
    'type_identifiant_professionnel', 'numero_professionnel', 'iban',
    'scolarite_formation', 'scolarite_annee_validee',
    'licence_remplacement_specialite', 'employeur_extrait',
    'periode_debut_extraite', 'periode_fin_extraite', 'heures_extraites'
  ]::text[])
  LIMIT 1;
  IF v_allowed_key IS NOT NULL THEN
    RAISE EXCEPTION 'Champ de modération non autorisé : %', v_allowed_key
      USING ERRCODE = '22023';
  END IF;

  IF NULLIF(v_validation ->> 'expected_document_modifie_le', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_soignant_modifie_le', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_statut', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_type_document', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_soignant_id', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_s3_bucket', '') IS NULL
     OR NULLIF(v_validation ->> 'expected_s3_cle', '') IS NULL THEN
    RAISE EXCEPTION 'Snapshot CAS incomplet : rechargez la file de modération'
      USING ERRCODE = '22023';
  END IF;
  BEGIN
    v_expected_doc_modifie := (v_validation ->> 'expected_document_modifie_le')::timestamptz;
    v_expected_soignant_modifie := (v_validation ->> 'expected_soignant_modifie_le')::timestamptz;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Snapshot CAS invalide : rechargez la file de modération'
      USING ERRCODE = '22023';
  END;

  SELECT * INTO v_doc
  FROM public.documents_soignants
  WHERE id = p_document_id
  FOR UPDATE;
  IF NOT FOUND OR v_doc.supprime_le IS NOT NULL THEN
    RAISE EXCEPTION 'Document introuvable ou supprimé' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_doc.soignant_id AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil soignant introuvable' USING ERRCODE = 'P0002';
  END IF;

  IF v_doc.modifie_le IS DISTINCT FROM v_expected_doc_modifie
     OR v_soignant.modifie_le IS DISTINCT FROM v_expected_soignant_modifie
     OR v_doc.statut_verification::text IS DISTINCT FROM v_validation ->> 'expected_statut'
     OR v_doc.type_document::text IS DISTINCT FROM v_validation ->> 'expected_type_document'
     OR v_doc.soignant_id::text IS DISTINCT FROM v_validation ->> 'expected_soignant_id'
     OR v_doc.s3_bucket IS DISTINCT FROM v_validation ->> 'expected_s3_bucket'
     OR v_doc.s3_cle IS DISTINCT FROM v_validation ->> 'expected_s3_cle'
     OR v_doc.s3_version_id IS DISTINCT FROM NULLIF(v_validation ->> 'expected_s3_version_id', '') THEN
    RAISE EXCEPTION 'Le document, sa source ou le profil a changé : rechargez avant de décider'
      USING ERRCODE = '40001';
  END IF;
  IF v_doc.statut_verification NOT IN (
       'EN_ATTENTE', 'REVUE_MANUELLE_REQUISE', 'API_INDISPONIBLE'
     )
     OR v_doc.verification_attempt_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ce document n’est plus disponible pour une décision manuelle'
      USING ERRCODE = '40001';
  END IF;

  v_snapshot := jsonb_build_object(
    'document', jsonb_build_object(
      'id', v_doc.id,
      'modifie_le', v_doc.modifie_le,
      'statut', v_doc.statut_verification,
      'type_document', v_doc.type_document,
      's3_bucket', v_doc.s3_bucket,
      's3_cle', v_doc.s3_cle,
      's3_version_id', v_doc.s3_version_id,
      'type_mime', v_doc.type_mime,
      'taille_octets', v_doc.taille_octets,
      'motif_precedent', v_doc.motif_rejet,
      'resultat_ia_present', v_doc.resultat_ia IS NOT NULL
    ),
    'profil', jsonb_build_object(
      'id', v_soignant.id,
      'modifie_le', v_soignant.modifie_le,
      'nom', v_soignant.nom,
      'prenom', v_soignant.prenom,
      'date_naissance', v_soignant.date_naissance,
      'profession', v_soignant.profession,
      'rpps_verifie', COALESCE(v_soignant.rpps_verifie, false),
      'adeli_verifie', COALESCE(v_soignant.adeli_verifie, false)
    )
  );

  IF v_action = 'REJETER' THEN
    IF char_length(btrim(COALESCE(p_motif, ''))) < 10
       OR char_length(btrim(COALESCE(p_motif, ''))) > 1000 THEN
      RAISE EXCEPTION 'Le motif de rejet doit contenir entre 10 et 1000 caractères'
        USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('jolene.document_moderation_rpc', 'true', true);
    BEGIN
      UPDATE public.documents_soignants
      SET statut_verification = 'REJETE',
          verifie_par = v_uid,
          verifie_le = now(),
          motif_rejet = btrim(p_motif),
          valide_depuis = NULL,
          valide_jusqua = NULL,
          verification_attempt_id = NULL,
          resultat_ia = COALESCE(resultat_ia, '{}'::jsonb) || jsonb_build_object(
            'verdict_serveur', 'REJETE',
            'motif_serveur', btrim(p_motif),
            'source_validation', 'ADMIN_REJET'
          ),
          modifie_le = now()
      WHERE id = v_doc.id
        AND modifie_le = v_expected_doc_modifie
        AND statut_verification = v_doc.statut_verification
        AND verification_attempt_id IS NULL;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      IF v_row_count IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Décision concurrente détectée' USING ERRCODE = '40001';
      END IF;

      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource,
        cle_s3_ressource, details
      ) VALUES (
        v_uid, 'ADMIN', 'MODERATION_DOCUMENT', 'document', v_doc.id,
        v_doc.s3_cle,
        jsonb_build_object(
          'decision', 'REJETER',
          'source', 'ADMIN_REJET',
          'motif', btrim(p_motif),
          'snapshot', v_snapshot
        )
      );

      UPDATE public.file_revue_manuelle
      SET statut = 'RESOLU_MANUELLEMENT',
          assigne_a = v_uid,
          notes_resolution = left('Document rejeté : ' || btrim(p_motif), 1000),
          revu_le = COALESCE(revu_le, now()),
          resolu_le = now()
      WHERE id_entite = v_doc.id
        AND type_entite = 'TELEVERSEMENT_DOCUMENT'
        AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE');

      PERFORM public.fn_calculer_tous_documents_valides(v_doc.soignant_id);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config(
        'jolene.document_moderation_rpc',
        v_previous_moderation,
        true
      );
      RAISE;
    END;
    PERFORM set_config(
      'jolene.document_moderation_rpc',
      v_previous_moderation,
      true
    );
    RETURN jsonb_build_object('success', true, 'action', 'REJETER');
  END IF;

  -- Toute validation exige une revue visuelle explicite et une identité lue.
  IF v_validation -> 'document_lisible' IS DISTINCT FROM 'true'::jsonb
     OR v_validation -> 'document_complet' IS DISTINCT FROM 'true'::jsonb
     OR v_validation -> 'type_document_confirme' IS DISTINCT FROM 'true'::jsonb
     OR v_validation -> 'antifraude_verifiee' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'Lisibilité, complétude, type et contrôle antifraude doivent être confirmés'
      USING ERRCODE = '23514';
  END IF;

  v_nom_extrait := NULLIF(left(btrim(v_validation ->> 'nom_extrait'), 200), '');
  v_prenom_extrait := NULLIF(left(btrim(v_validation ->> 'prenom_extrait'), 200), '');
  IF NOT public.fn_noms_personne_correspondent(
    v_soignant.nom,
    v_soignant.prenom,
    v_nom_extrait,
    v_prenom_extrait
  ) THEN
    RAISE EXCEPTION 'Le nom et le prénom lus ne correspondent pas au profil'
      USING ERRCODE = '23514';
  END IF;

  v_date_emission_raw := NULLIF(btrim(v_validation ->> 'date_emission'), '');
  v_date_expiration_raw := NULLIF(btrim(v_validation ->> 'date_expiration'), '');
  v_date_emission := private.fn_date_iso_moderation(v_date_emission_raw);
  v_date_expiration := private.fn_date_iso_moderation(v_date_expiration_raw);
  IF v_date_emission_raw IS NOT NULL AND v_date_emission IS NULL THEN
    RAISE EXCEPTION 'Date d’émission invalide' USING ERRCODE = '22023';
  END IF;
  IF v_date_expiration_raw IS NOT NULL AND v_date_expiration IS NULL THEN
    RAISE EXCEPTION 'Date d’expiration invalide' USING ERRCODE = '22023';
  END IF;
  IF v_date_emission > current_date THEN
    RAISE EXCEPTION 'La date d’émission ne peut pas être future' USING ERRCODE = '23514';
  END IF;
  IF v_date_expiration IS NOT NULL AND v_date_expiration <= current_date THEN
    RAISE EXCEPTION 'Un document expiré ne peut pas être validé' USING ERRCODE = '23514';
  END IF;
  IF v_date_emission IS NOT NULL
     AND v_date_expiration IS NOT NULL
     AND v_date_expiration < v_date_emission THEN
    RAISE EXCEPTION 'La date d’expiration précède la date d’émission'
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(bool_or(drp.a_expiration), false)
  INTO v_exige_expiration
  FROM public.documents_requis_par_profession drp
  WHERE drp.profession = v_soignant.profession
    AND public.fn_type_document_preuve_compatible(
      drp.type_document,
      v_doc.type_document
    );
  v_exige_expiration := COALESCE(v_exige_expiration, false)
    OR v_doc.type_document IN (
      'CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR',
      'RCP_ASSURANCE', 'LICENCE_REMPLACEMENT'
    );
  IF v_exige_expiration AND v_date_expiration IS NULL THEN
    RAISE EXCEPTION 'La date d’expiration est obligatoire pour ce document'
      USING ERRCODE = '23514';
  END IF;

  IF v_doc.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR') THEN
    v_date_naissance := private.fn_date_iso_moderation(
      v_validation ->> 'date_naissance'
    );
    IF v_date_naissance IS NULL
       OR v_date_naissance < DATE '1900-01-01'
       OR v_date_naissance >= current_date THEN
      RAISE EXCEPTION 'Date de naissance absente ou non plausible'
        USING ERRCODE = '23514';
    END IF;
    IF v_soignant.date_naissance IS NOT NULL
       AND v_soignant.date_naissance IS DISTINCT FROM v_date_naissance THEN
      RAISE EXCEPTION 'La date de naissance du document contredit le profil'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document IN ('DIPLOME', 'AUTORISATION_EXERCICE') THEN
    v_profession_certifiee := upper(NULLIF(btrim(
      v_validation ->> 'profession_certifiee'
    ), ''));
    IF NOT EXISTS (
      SELECT 1
      FROM unnest(enum_range(NULL::public.type_profession)) AS p(profession)
      WHERE p.profession::text = v_profession_certifiee
    ) THEN
      RAISE EXCEPTION 'Profession certifiée absente ou inconnue'
        USING ERRCODE = '23514';
    END IF;
    v_diplome_compatible := CASE v_soignant.profession::text
      WHEN 'IDE' THEN v_profession_certifiee IN ('IDE', 'IADE', 'IBODE')
      WHEN 'IADE' THEN v_profession_certifiee = 'IADE'
      WHEN 'IBODE' THEN v_profession_certifiee = 'IBODE'
      ELSE v_profession_certifiee = v_soignant.profession::text
    END;
    IF NOT v_diplome_compatible THEN
      RAISE EXCEPTION 'La qualification certifiée ne correspond pas à la profession du profil'
        USING ERRCODE = '23514';
    END IF;

    v_diplome_etranger := COALESCE(
      (v_validation ->> 'diplome_etranger')::boolean,
      false
    );
    IF v_doc.type_document = 'DIPLOME'
       AND v_diplome_etranger
       AND NOT EXISTS (
         SELECT 1
         FROM public.documents_soignants autorisation
         WHERE autorisation.soignant_id = v_doc.soignant_id
           AND autorisation.type_document = 'AUTORISATION_EXERCICE'
           AND autorisation.statut_verification = 'VERIFIE'
           AND autorisation.supprime_le IS NULL
           AND (
             autorisation.valide_jusqua IS NULL
             OR autorisation.valide_jusqua > current_date
           )
           AND CASE v_soignant.profession::text
             WHEN 'IDE' THEN upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) IN ('IDE', 'IADE', 'IBODE')
             WHEN 'IADE' THEN upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) = 'IADE'
             WHEN 'IBODE' THEN upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) = 'IBODE'
             ELSE upper(COALESCE(
               autorisation.resultat_ia ->> 'profession_certifiee', ''
             )) = v_soignant.profession::text
           END
       ) THEN
      RAISE EXCEPTION 'Un diplôme étranger exige une autorisation d’exercice vérifiée et concordante'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'RPPS_ADELI' THEN
    v_type_identifiant := upper(NULLIF(btrim(
      v_validation ->> 'type_identifiant_professionnel'
    ), ''));
    v_numero_professionnel := regexp_replace(
      COALESCE(v_validation ->> 'numero_professionnel', ''),
      '[^0-9]',
      '',
      'g'
    );
    IF v_type_identifiant = 'RPPS' THEN
      v_numero_attendu := regexp_replace(COALESCE(v_soignant.numero_rpps, ''), '[^0-9]', '', 'g');
      IF COALESCE(v_soignant.rpps_verifie, false) IS NOT TRUE
         OR v_numero_professionnel !~ '^\d{11}$'
         OR v_numero_professionnel IS DISTINCT FROM v_numero_attendu THEN
        RAISE EXCEPTION 'RPPS non vérifié ou différent du profil'
          USING ERRCODE = '23514';
      END IF;
    ELSIF v_type_identifiant = 'ADELI' THEN
      v_numero_attendu := regexp_replace(COALESCE(v_soignant.numero_adeli, ''), '[^0-9]', '', 'g');
      IF COALESCE(v_soignant.adeli_verifie, false) IS NOT TRUE
         OR v_numero_professionnel !~ '^\d{9}$'
         OR v_numero_professionnel IS DISTINCT FROM v_numero_attendu THEN
        RAISE EXCEPTION 'ADELI non vérifié ou différent du profil'
          USING ERRCODE = '23514';
      END IF;
    ELSE
      RAISE EXCEPTION 'Type d’identifiant professionnel invalide'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'RIB' THEN
    v_iban := v_validation ->> 'iban';
    IF NOT private.fn_iban_valide_moderation(v_iban) THEN
      RAISE EXCEPTION 'IBAN invalide (format ou checksum ISO 13616)'
        USING ERRCODE = '23514';
    END IF;
    v_iban_normalise := upper(regexp_replace(v_iban, '[^A-Za-z0-9]', '', 'g'));
    v_iban_last4 := right(v_iban_normalise, 4);
    IF NULLIF(btrim(v_soignant.iban_virement), '') IS NOT NULL
       AND upper(regexp_replace(v_soignant.iban_virement, '[^A-Za-z0-9]', '', 'g'))
         IS DISTINCT FROM v_iban_normalise THEN
      RAISE EXCEPTION 'L’IBAN du RIB diffère de l’IBAN de versement enregistré'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'ATTESTATION_SCOLARITE' THEN
    v_formation := upper(NULLIF(btrim(
      v_validation ->> 'scolarite_formation'
    ), ''));
    BEGIN
      v_annee_validee := (v_validation ->> 'scolarite_annee_validee')::integer;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      v_annee_validee := NULL;
    END;
    IF v_date_emission IS NULL
       OR v_date_emission < current_date - 400
       OR v_date_emission > current_date THEN
      RAISE EXCEPTION 'L’attestation de scolarité doit dater de moins de 400 jours'
        USING ERRCODE = '23514';
    END IF;
    IF v_formation IS NULL OR v_annee_validee IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.fn_professions_autorisees_scolarite(
           v_formation,
           v_annee_validee
         ) AS autorisee(profession)
         WHERE autorisee.profession = v_soignant.profession
       ) THEN
      RAISE EXCEPTION 'La formation ou l’année validée ne permet pas la profession du profil'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document = 'LICENCE_REMPLACEMENT' THEN
    v_specialite_licence := NULLIF(left(btrim(
      v_validation ->> 'licence_remplacement_specialite'
    ), 200), '');
    IF v_soignant.profession IS DISTINCT FROM 'MEDECIN'
       OR v_date_emission IS NULL
       OR v_date_expiration IS NULL
       OR v_date_expiration > (v_date_emission + interval '13 months')::date
       OR v_specialite_licence IS NULL THEN
      RAISE EXCEPTION 'Licence de remplacement non concordante, incomplète ou hors validité'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF v_doc.type_document::text IN (
    'BULLETIN_PAIE', 'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL'
  ) THEN
    SELECT * INTO v_heures
    FROM public.heures_externes
    WHERE document_id = v_doc.id
      AND soignant_id = v_doc.soignant_id
    FOR SHARE;
    IF NOT FOUND
       OR public.fn_normaliser_nom(v_heures.employeur_nom)
         IS DISTINCT FROM public.fn_normaliser_nom(
           v_validation ->> 'employeur_extrait'
         )
       OR v_heures.date_debut IS DISTINCT FROM private.fn_date_iso_moderation(
         v_validation ->> 'periode_debut_extraite'
       )
       OR v_heures.date_fin IS DISTINCT FROM private.fn_date_iso_moderation(
         v_validation ->> 'periode_fin_extraite'
       )
       OR v_heures.heures_declarees IS DISTINCT FROM
         NULLIF(v_validation ->> 'heures_extraites', '')::numeric
       OR v_heures.type_preuve IS DISTINCT FROM v_doc.type_document::text THEN
      RAISE EXCEPTION 'Employeur, période ou heures non concordants avec la déclaration'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  v_ai_indisponible := v_doc.statut_verification = 'API_INDISPONIBLE'
    OR v_doc.resultat_ia IS NULL
    OR v_doc.resultat_ia ? 'erreur_anthropic'
    OR v_doc.resultat_ia ? 'erreur_parse';
  v_override_requis := NOT v_ai_indisponible AND (
    upper(COALESCE(v_doc.resultat_ia ->> 'verdict', '')) = 'REJETE'
    OR upper(COALESCE(v_doc.resultat_ia ->> 'verdict_serveur', '')) = 'REJETE'
    OR v_doc.resultat_ia -> 'type_correspond' = 'false'::jsonb
    OR v_doc.resultat_ia -> 'document_lisible' = 'false'::jsonb
    OR v_doc.resultat_ia -> 'document_complet' = 'false'::jsonb
    OR v_doc.resultat_ia -> 'nom_correspond' = 'false'::jsonb
    OR v_doc.coherence_nom IS FALSE
    OR (
      jsonb_typeof(v_doc.resultat_ia -> 'indices_falsification') = 'array'
      AND jsonb_array_length(v_doc.resultat_ia -> 'indices_falsification') > 0
    )
  );
  IF v_raison_override IS NOT NULL THEN
    v_override_requis := true;
  END IF;
  IF v_override_requis AND (
    v_validation -> 'override_confirme' IS DISTINCT FROM 'true'::jsonb
    OR char_length(v_raison_override) < 30
    OR char_length(v_raison_override) > 1000
  ) THEN
    RAISE EXCEPTION 'Une dérogation exceptionnelle confirmée et motivée (30 à 1000 caractères) est obligatoire'
      USING ERRCODE = '23514';
  END IF;
  v_source := CASE
    WHEN v_override_requis THEN 'ADMIN_OVERRIDE_EXCEPTIONNEL'
    WHEN v_ai_indisponible THEN 'ADMIN_SAISIE_MANUELLE'
    ELSE 'ADMIN_REVUE_IA'
  END;

  -- Les champs manuels nécessaires aux règles dérivées sont persistés dans
  -- resultat_ia, mais jamais l'IBAN complet. Le suffixe historique de colonne
  -- reste inchangé pour compatibilité avec les recalculs existants.
  v_resultat_final := (
    COALESCE(v_doc.resultat_ia, '{}'::jsonb)
      - 'iban'
      - 'iban_extrait'
      - 'raw_text'
  ) || jsonb_strip_nulls(jsonb_build_object(
    'verdict_serveur', 'VERIFIE',
    'motif_serveur', NULL,
    'source_validation', v_source,
    'revue_manuelle_le', now(),
    'type_correspond', true,
    'document_lisible', true,
    'document_complet', true,
    'antifraude_manuelle_verifiee', true,
    'nom_correspond', true,
    'nom_extrait', v_nom_extrait,
    'prenom_extrait', v_prenom_extrait,
    'date_naissance_extraite', v_date_naissance,
    'date_emission', v_date_emission,
    'date_expiration', v_date_expiration,
    'profession_certifiee', v_profession_certifiee,
    'diplome_etranger', CASE
      WHEN v_doc.type_document = 'DIPLOME' THEN v_diplome_etranger
      ELSE NULL
    END,
    'type_identifiant_professionnel', v_type_identifiant,
    'numero_professionnel_extrait', v_numero_professionnel,
    'iban_last4', v_iban_last4,
    'iban_valide', CASE WHEN v_doc.type_document = 'RIB' THEN true ELSE NULL END,
    'iban_preuve_hash_v1', CASE
      WHEN v_doc.type_document = 'RIB' THEN encode(
        extensions.digest(
          convert_to(v_iban_normalise || ':' || v_doc.id::text, 'UTF8'),
          'sha256'
        ),
        'hex'
      )
      ELSE NULL
    END,
    'scolarite_formation', v_formation,
    'scolarite_annee_validee', v_annee_validee,
    'licence_remplacement_specialite', v_specialite_licence,
    'employeur_extrait', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.employeur_nom END,
    'periode_debut_extraite', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.date_debut END,
    'periode_fin_extraite', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.date_fin END,
    'heures_extraites', CASE WHEN v_heures.id IS NULL THEN NULL ELSE v_heures.heures_declarees END
  ));

  PERFORM set_config('jolene.document_moderation_rpc', 'true', true);
  BEGIN
    IF v_doc.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
       AND v_soignant.date_naissance IS NULL THEN
      UPDATE public.soignants
      SET date_naissance = v_date_naissance,
          modifie_le = now()
      WHERE id = v_soignant.id
        AND modifie_le = v_expected_soignant_modifie
        AND date_naissance IS NULL;
      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      IF v_row_count IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Le profil a changé pendant la décision'
          USING ERRCODE = '40001';
      END IF;
    END IF;

    UPDATE public.documents_soignants
    SET statut_verification = 'VERIFIE',
        verifie_par = v_uid,
        verifie_le = now(),
        motif_rejet = NULL,
        valide_depuis = v_date_emission,
        valide_jusqua = v_date_expiration,
        resultat_ia = v_resultat_final,
        nom_extrait_ia = v_nom_extrait,
        prenom_extrait_ia = v_prenom_extrait,
        coherence_nom = true,
        verification_attempt_id = NULL,
        modifie_le = now()
    WHERE id = v_doc.id
      AND modifie_le = v_expected_doc_modifie
      AND statut_verification = v_doc.statut_verification
      AND verification_attempt_id IS NULL;
    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    IF v_row_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'Décision concurrente détectée' USING ERRCODE = '40001';
    END IF;

    IF v_doc.type_document = 'RIB' THEN
      -- L'IBAN complet n'est jamais persisté dans resultat_ia ni dans l'audit.
      -- Il est transmis en mémoire à la liaison service-role, qui le rattache à
      -- cette version exacte du RIB et à la pièce d'identité courante.
      -- Cette fonction est créée par la migration de durcissement suivante.
      -- La résolution dynamique évite une dépendance d'ordre au moment du
      -- CREATE FUNCTION, tout en conservant l'appel dans la même transaction.
      EXECUTE
        'SELECT public.fn_lier_iban_verifie_document($1, $2, $3)'
      INTO v_liaison_bancaire
      USING v_doc.id, v_doc.s3_cle, v_iban_normalise;
      IF COALESCE((v_liaison_bancaire ->> 'success')::boolean, false) IS NOT TRUE
         AND COALESCE(v_liaison_bancaire ->> 'error_code', '') NOT IN (
           'IDENTITE_VERIFIEE_REQUISE',
           'IDENTITE_COURANTE_REQUISE'
         ) THEN
        RAISE EXCEPTION 'Le RIB validé ne peut pas être lié au compte de versement'
          USING ERRCODE = '23514';
      END IF;
    END IF;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource,
      cle_s3_ressource, details
    ) VALUES (
      v_uid, 'ADMIN', 'MODERATION_DOCUMENT', 'document', v_doc.id,
      v_doc.s3_cle,
      jsonb_build_object(
        'decision', 'VALIDER',
        'source', v_source,
        'snapshot', v_snapshot,
        'champs_confirmes', jsonb_strip_nulls(jsonb_build_object(
          'nom_extrait', v_nom_extrait,
          'prenom_extrait', v_prenom_extrait,
          'date_naissance', v_date_naissance,
          'date_emission', v_date_emission,
          'date_expiration', v_date_expiration,
          'profession_certifiee', v_profession_certifiee,
          'type_identifiant_professionnel', v_type_identifiant,
          'numero_professionnel', v_numero_professionnel,
          'iban_last4', v_iban_last4,
          'scolarite_formation', v_formation,
          'scolarite_annee_validee', v_annee_validee,
          'licence_specialite', v_specialite_licence
        )),
        'override_raison', v_raison_override
      )
    );

    UPDATE public.file_revue_manuelle
    SET statut = 'RESOLU_MANUELLEMENT',
        assigne_a = v_uid,
        notes_resolution = left(
          CASE
            WHEN v_override_requis THEN 'Validation exceptionnelle : ' || v_raison_override
            ELSE 'Validation documentaire après revue contextualisée (' || v_source || ')'
          END,
          1000
        ),
        revu_le = COALESCE(revu_le, now()),
        resolu_le = now()
    WHERE id_entite = v_doc.id
      AND type_entite = 'TELEVERSEMENT_DOCUMENT'
      AND statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE');

    PERFORM public.fn_calculer_tous_documents_valides(v_doc.soignant_id);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config(
      'jolene.document_moderation_rpc',
      v_previous_moderation,
      true
    );
    RAISE;
  END;
  PERFORM set_config(
    'jolene.document_moderation_rpc',
    v_previous_moderation,
    true
  );

  RETURN jsonb_build_object(
    'success', true,
    'action', 'VALIDER',
    'source', v_source
  );
END;
$$;

-- L'ancienne signature reste résoluble pour ne pas casser PostgREST ni les
-- appels historiques, mais toute mutation sans snapshot contextualisé échoue
-- avant le moindre DML (notamment l'ancien ajout admin avec p_valider=true).
CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document(
  p_document_id uuid,
  p_action text,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorisé requis'
      USING ERRCODE = '42501';
  END IF;
  RAISE EXCEPTION 'Contexte documentaire obligatoire : rechargez la modération et utilisez la revue détaillée'
    USING ERRCODE = '22023';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_moderer_document(
  uuid, text, text, jsonb, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_moderer_document(
  uuid, text, text, jsonb, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_admin_moderer_document(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_moderer_document(uuid, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.fn_admin_moderer_document(
  uuid, text, text, jsonb, text
) IS
  'Décision documentaire admin AAL2 : snapshot/CAS, contrôle métier par type, audit atomique et dérogation exceptionnelle motivée.';

NOTIFY pgrst, 'reload schema';

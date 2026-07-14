-- Modération documentaire soignant : tests transactionnels et adversariaux.
-- Toutes les fixtures et décisions sont annulées par le ROLLBACK final.

\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_admin constant uuid := 'ad620000-0000-4000-8000-000000000001';
  v_soignant constant uuid := 'ad620000-0000-4000-8000-000000000002';
  v_identite constant uuid := 'ad620000-0000-4000-8000-000000000101';
  v_diplome constant uuid := 'ad620000-0000-4000-8000-000000000102';
  v_rib constant uuid := 'ad620000-0000-4000-8000-000000000103';
  v_override constant uuid := 'ad620000-0000-4000-8000-000000000104';
  v_rejet constant uuid := 'ad620000-0000-4000-8000-000000000105';
  v_stale constant uuid := 'ad620000-0000-4000-8000-000000000106';
  v_context jsonb;
  v_result jsonb;
  v_failed boolean;
  v_doc_modifie timestamptz;
  v_soignant_modifie timestamptz;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixtures transactionnelles modération documentaire 62000',
    true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_admin,
      '00000000-0000-0000-0000-000000000000',
      'admin-document-62000@test.local',
      'authenticated',
      'authenticated',
      '{"role":"ADMIN_PLATEFORME"}',
      now()
    ),
    (
      v_soignant,
      '00000000-0000-0000-0000-000000000000',
      'iade-document-62000@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    );

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin,
    'Document',
    'Admin',
    'admin-document-62000@test.local',
    true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, date_naissance, profession,
    numero_rpps, rpps_verifie, modifie_le
  ) VALUES (
    v_soignant,
    'Marie',
    'Lefevre',
    'iade-document-62000@test.local',
    DATE '1990-03-02',
    'IADE',
    '10101234567',
    true,
    clock_timestamp()
  );

  -- Le trigger de remplacement ne conserve qu'une preuve courante par classe.
  -- Les scénarios override/rejet/CAS utilisent donc des types distincts afin
  -- de tester la modération elle-même, sans se remplacer entre eux à l'INSERT.
  INSERT INTO public.documents_soignants (
    id, soignant_id, type_document, libelle, s3_bucket, s3_cle,
    s3_version_id, nom_fichier, type_mime, taille_octets,
    statut_verification, resultat_ia, motif_rejet, modifie_le
  ) VALUES
    (
      v_identite, v_soignant, 'CARTE_IDENTITE', 'Fixture identité',
      'jolene-documents', 'tests/62000/identite.pdf', 'v1',
      'identite.pdf', 'application/pdf', 1200, 'EN_ATTENTE',
      '{"erreur_anthropic":{"status":"timeout"}}', NULL, clock_timestamp()
    ),
    (
      v_diplome, v_soignant, 'DIPLOME', 'Fixture diplôme',
      'jolene-documents', 'tests/62000/diplome.pdf', 'v1',
      'diplome.pdf', 'application/pdf', 1200, 'EN_ATTENTE',
      '{"verdict":"EN_ATTENTE","indices_falsification":[]}', NULL, clock_timestamp()
    ),
    (
      v_rib, v_soignant, 'RIB', 'Fixture RIB',
      'jolene-documents', 'tests/62000/rib.pdf', 'v1',
      'rib.pdf', 'application/pdf', 1200, 'EN_ATTENTE',
      '{"erreur_anthropic":{"status":"timeout"}}', NULL, clock_timestamp()
    ),
    (
      v_override, v_soignant, 'AUTRE', 'Fixture override',
      'jolene-documents', 'tests/62000/override.pdf', 'v1',
      'override.pdf', 'application/pdf', 1200, 'EN_ATTENTE',
      '{"verdict":"REJETE","verdict_serveur":"REJETE","indices_falsification":["police incoherente"]}',
      'Indice automatique à examiner', clock_timestamp()
    ),
    (
      v_rejet, v_soignant, 'CASIER_JUDICIAIRE', 'Fixture rejet',
      'jolene-documents', 'tests/62000/rejet.pdf', 'v1',
      'rejet.pdf', 'application/pdf', 1200, 'EN_ATTENTE',
      NULL, NULL, clock_timestamp()
    ),
    (
      v_stale, v_soignant, 'ATTESTATION_URSSAF', 'Fixture CAS',
      'jolene-documents', 'tests/62000/stale.pdf', 'v1',
      'stale.pdf', 'application/pdf', 1200, 'EN_ATTENTE',
      NULL, NULL, clock_timestamp()
    );

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  SELECT d.modifie_le, s.modifie_le
  INTO v_doc_modifie, v_soignant_modifie
  FROM public.documents_soignants d
  JOIN public.soignants s ON s.id = d.soignant_id
  WHERE d.id = v_identite;
  v_context := jsonb_build_object(
    'expected_document_modifie_le', v_doc_modifie,
    'expected_soignant_modifie_le', v_soignant_modifie,
    'expected_statut', 'EN_ATTENTE',
    'expected_type_document', 'CARTE_IDENTITE',
    'expected_soignant_id', v_soignant,
    'expected_s3_bucket', 'jolene-documents',
    'expected_s3_cle', 'tests/62000/identite.pdf',
    'expected_s3_version_id', 'v1',
    'document_lisible', true,
    'document_complet', true,
    'type_document_confirme', true,
    'antifraude_verifiee', true,
    'override_confirme', false,
    'nom_extrait', 'LEFEVRE',
    'prenom_extrait', 'Marie',
    'date_naissance', '1990-03-02',
    'date_expiration', '2031-03-01'
  );

  -- Un compte admin AAL1 ne peut ni valider ni rejeter.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_moderer_document(
      v_identite, 'VALIDER', NULL, v_context, NULL
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MOD-DOC-T1 : AAL1 a validé un document';
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );

  -- L'ancienne signature est un hard stop, même pour le bon admin.
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_moderer_document(v_identite, 'VALIDER', NULL);
  EXCEPTION WHEN invalid_parameter_value THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MOD-DOC-T2 : ancienne signature encore permissive';
  END IF;

  -- Timeout IA : la saisie manuelle complète est validée et auditée.
  v_result := public.fn_admin_moderer_document(
    v_identite, 'VALIDER', NULL, v_context, NULL
  );
  IF v_result->>'success' <> 'true'
     OR v_result->>'source' <> 'ADMIN_SAISIE_MANUELLE'
     OR NOT EXISTS (
       SELECT 1
       FROM public.documents_soignants d
       WHERE d.id = v_identite
         AND d.statut_verification = 'VERIFIE'
         AND d.nom_extrait_ia = 'LEFEVRE'
         AND d.prenom_extrait_ia = 'Marie'
         AND d.resultat_ia->>'date_naissance_extraite' = '1990-03-02'
         AND d.resultat_ia->>'source_validation' = 'ADMIN_SAISIE_MANUELLE'
     )
     OR NOT EXISTS (
       SELECT 1
       FROM public.journaux_audit j
       WHERE j.id_ressource = v_identite
         AND j.action = 'MODERATION_DOCUMENT'
         AND j.details->>'source' = 'ADMIN_SAISIE_MANUELLE'
         AND j.details->'snapshot'->'document'->>'s3_version_id' = 'v1'
     ) THEN
    RAISE EXCEPTION 'MOD-DOC-T3 : décision manuelle non atomique : %', v_result;
  END IF;

  -- Un diplôme IDE ne prouve jamais un profil IADE ; le diplôme IADE exact oui.
  SELECT d.modifie_le, s.modifie_le
  INTO v_doc_modifie, v_soignant_modifie
  FROM public.documents_soignants d
  JOIN public.soignants s ON s.id = d.soignant_id
  WHERE d.id = v_diplome;
  v_context := jsonb_build_object(
    'expected_document_modifie_le', v_doc_modifie,
    'expected_soignant_modifie_le', v_soignant_modifie,
    'expected_statut', 'EN_ATTENTE',
    'expected_type_document', 'DIPLOME',
    'expected_soignant_id', v_soignant,
    'expected_s3_bucket', 'jolene-documents',
    'expected_s3_cle', 'tests/62000/diplome.pdf',
    'expected_s3_version_id', 'v1',
    'document_lisible', true,
    'document_complet', true,
    'type_document_confirme', true,
    'antifraude_verifiee', true,
    'override_confirme', false,
    'nom_extrait', 'LEFEVRE',
    'prenom_extrait', 'Marie',
    'profession_certifiee', 'IDE',
    'diplome_etranger', false
  );
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_moderer_document(
      v_diplome, 'VALIDER', NULL, v_context, NULL
    );
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed OR EXISTS (
    SELECT 1 FROM public.documents_soignants
    WHERE id = v_diplome AND statut_verification = 'VERIFIE'
  ) THEN
    RAISE EXCEPTION 'MOD-DOC-T4 : diplôme IDE accepté pour IADE';
  END IF;
  v_context := jsonb_set(v_context, '{profession_certifiee}', '"IADE"');
  v_result := public.fn_admin_moderer_document(
    v_diplome, 'VALIDER', NULL, v_context, NULL
  );
  IF v_result->>'success' <> 'true' THEN
    RAISE EXCEPTION 'MOD-DOC-T5 : diplôme IADE exact refusé : %', v_result;
  END IF;

  -- Le checksum IBAN est recalculé et l'IBAN complet n'est jamais persisté.
  SELECT d.modifie_le, s.modifie_le
  INTO v_doc_modifie, v_soignant_modifie
  FROM public.documents_soignants d
  JOIN public.soignants s ON s.id = d.soignant_id
  WHERE d.id = v_rib;
  v_context := jsonb_build_object(
    'expected_document_modifie_le', v_doc_modifie,
    'expected_soignant_modifie_le', v_soignant_modifie,
    'expected_statut', 'EN_ATTENTE',
    'expected_type_document', 'RIB',
    'expected_soignant_id', v_soignant,
    'expected_s3_bucket', 'jolene-documents',
    'expected_s3_cle', 'tests/62000/rib.pdf',
    'expected_s3_version_id', 'v1',
    'document_lisible', true,
    'document_complet', true,
    'type_document_confirme', true,
    'antifraude_verifiee', true,
    'override_confirme', false,
    'nom_extrait', 'LEFEVRE',
    'prenom_extrait', 'Marie',
    'iban', 'FR7630006000011234567890188'
  );
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_moderer_document(
      v_rib, 'VALIDER', NULL, v_context, NULL
    );
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MOD-DOC-T6 : IBAN au checksum invalide accepté';
  END IF;
  v_context := jsonb_set(
    v_context,
    '{iban}',
    '"FR7630006000011234567890189"'
  );
  v_result := public.fn_admin_moderer_document(
    v_rib, 'VALIDER', NULL, v_context, NULL
  );
  IF v_result->>'success' <> 'true'
     OR NOT EXISTS (
       SELECT 1
       FROM public.documents_soignants d
       WHERE d.id = v_rib
         AND d.resultat_ia->>'iban_last4' = '0189'
         AND d.resultat_ia->>'iban_valide' = 'true'
         AND d.resultat_ia::text NOT LIKE '%FR7630006%'
     )
     OR EXISTS (
       SELECT 1
       FROM public.journaux_audit j
       WHERE j.id_ressource = v_rib
         AND j.details::text LIKE '%FR7630006%'
     ) THEN
    RAISE EXCEPTION 'MOD-DOC-T7 : IBAN non validé ou persisté en clair : %', v_result;
  END IF;

  -- Un signal explicite de falsification impose confirmation + motif long.
  SELECT d.modifie_le, s.modifie_le
  INTO v_doc_modifie, v_soignant_modifie
  FROM public.documents_soignants d
  JOIN public.soignants s ON s.id = d.soignant_id
  WHERE d.id = v_override;
  v_context := jsonb_build_object(
    'expected_document_modifie_le', v_doc_modifie,
    'expected_soignant_modifie_le', v_soignant_modifie,
    'expected_statut', 'EN_ATTENTE',
    'expected_type_document', 'AUTRE',
    'expected_soignant_id', v_soignant,
    'expected_s3_bucket', 'jolene-documents',
    'expected_s3_cle', 'tests/62000/override.pdf',
    'expected_s3_version_id', 'v1',
    'document_lisible', true,
    'document_complet', true,
    'type_document_confirme', true,
    'antifraude_verifiee', true,
    'override_confirme', false,
    'nom_extrait', 'LEFEVRE',
    'prenom_extrait', 'Marie'
  );
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_moderer_document(
      v_override, 'VALIDER', NULL, v_context, NULL
    );
  EXCEPTION WHEN check_violation THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MOD-DOC-T8 : override non motivé accepté';
  END IF;
  v_context := jsonb_set(v_context, '{override_confirme}', 'true');
  v_result := public.fn_admin_moderer_document(
    v_override,
    'VALIDER',
    NULL,
    v_context,
    'Le document original signé a été comparé au registre ; le filigrane officiel explique la police signalée.'
  );
  IF v_result->>'source' <> 'ADMIN_OVERRIDE_EXCEPTIONNEL'
     OR NOT EXISTS (
       SELECT 1 FROM public.journaux_audit j
       WHERE j.id_ressource = v_override
         AND j.details->>'source' = 'ADMIN_OVERRIDE_EXCEPTIONNEL'
         AND length(j.details->>'override_raison') >= 30
     ) THEN
    RAISE EXCEPTION 'MOD-DOC-T9 : override non tracé : %', v_result;
  END IF;

  -- Le rejet exige lui aussi le snapshot CAS et produit un audit atomique.
  SELECT d.modifie_le, s.modifie_le
  INTO v_doc_modifie, v_soignant_modifie
  FROM public.documents_soignants d
  JOIN public.soignants s ON s.id = d.soignant_id
  WHERE d.id = v_rejet;
  v_context := jsonb_build_object(
    'expected_document_modifie_le', v_doc_modifie,
    'expected_soignant_modifie_le', v_soignant_modifie,
    'expected_statut', 'EN_ATTENTE',
    'expected_type_document', 'CASIER_JUDICIAIRE',
    'expected_soignant_id', v_soignant,
    'expected_s3_bucket', 'jolene-documents',
    'expected_s3_cle', 'tests/62000/rejet.pdf',
    'expected_s3_version_id', 'v1'
  );
  v_result := public.fn_admin_moderer_document(
    v_rejet,
    'REJETER',
    'Le document ne correspond pas au justificatif demandé.',
    v_context,
    NULL
  );
  IF v_result->>'success' <> 'true'
     OR NOT EXISTS (
       SELECT 1 FROM public.documents_soignants
       WHERE id = v_rejet AND statut_verification = 'REJETE'
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.journaux_audit
       WHERE id_ressource = v_rejet
         AND details->>'decision' = 'REJETER'
     ) THEN
    RAISE EXCEPTION 'MOD-DOC-T10 : rejet contextualisé incomplet : %', v_result;
  END IF;

  -- Une version périmée du snapshot est refusée sans mutation.
  SELECT d.modifie_le, s.modifie_le
  INTO v_doc_modifie, v_soignant_modifie
  FROM public.documents_soignants d
  JOIN public.soignants s ON s.id = d.soignant_id
  WHERE d.id = v_stale;
  v_context := jsonb_build_object(
    'expected_document_modifie_le', v_doc_modifie,
    'expected_soignant_modifie_le', v_soignant_modifie,
    'expected_statut', 'EN_ATTENTE',
    'expected_type_document', 'ATTESTATION_URSSAF',
    'expected_soignant_id', v_soignant,
    'expected_s3_bucket', 'jolene-documents',
    'expected_s3_cle', 'tests/62000/stale.pdf',
    'expected_s3_version_id', 'v1'
  );
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE public.documents_soignants
  SET modifie_le = clock_timestamp()
  WHERE id = v_stale;
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_moderer_document(
      v_stale,
      'REJETER',
      'Document obsolète pour le test de concurrence.',
      v_context,
      NULL
    );
  EXCEPTION WHEN serialization_failure THEN
    v_failed := true;
  END;
  IF NOT v_failed OR EXISTS (
    SELECT 1 FROM public.documents_soignants
    WHERE id = v_stale AND statut_verification = 'REJETE'
  ) THEN
    RAISE EXCEPTION 'MOD-DOC-T11 : snapshot périmé accepté';
  END IF;

  -- Enfin, même l'admin AAL2 ne peut pas modifier directement le verdict.
  v_failed := false;
  BEGIN
    UPDATE public.documents_soignants
    SET statut_verification = 'VERIFIE'
    WHERE id = v_stale;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MOD-DOC-T12 : UPDATE direct admin accepté';
  END IF;
END;
$test$;

ROLLBACK;

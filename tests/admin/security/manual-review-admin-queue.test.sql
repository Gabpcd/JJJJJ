-- File de revue manuelle admin : AAL2, CAS, idempotence et trois services.
-- Toutes les fixtures et mutations sont annulees.
BEGIN;

DO $fixtures$
DECLARE
  v_admin uuid := '72000000-0000-4000-8000-000000000001';
  v_etab_rib uuid := '72000000-0000-4000-8000-000000000002';
  v_etab_finess uuid := '72000000-0000-4000-8000-000000000003';
  v_soignant uuid := '72000000-0000-4000-8000-000000000004';
  v_soignant_rejet uuid := '72000000-0000-4000-8000-000000000005';
  v_etab_finess_rejet uuid := '72000000-0000-4000-8000-000000000006';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_admin, '00000000-0000-0000-0000-000000000000',
      'revue-admin@test.local', 'authenticated', 'authenticated',
      '{"role":"ADMIN_PLATEFORME"}', now()
    ),
    (
      v_soignant, '00000000-0000-0000-0000-000000000000',
      'revue-soignant@test.local', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}', now()
    );

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin, 'Revue', 'Admin', 'revue-admin@test.local', true, ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  INSERT INTO public.etablissements (
    id, nom, siret, finess, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, siret_verifie,
    verification_source_version, rib_s3_key, rib_ia_resultat,
    rib_ia_coherent, est_compte_test
  ) VALUES
    (
      v_etab_rib, 'Etablissement revue RIB', '72000000000002', '720000002',
      'CLINIQUE_PRIVEE', '2 rue du Test', 'Paris', '75002',
      'revue-rib@test.local', true, 5,
      v_etab_rib::text || '/rib-etablissement-revue.pdf',
      '{"verdict_final":"EN_ATTENTE"}'::jsonb, NULL, true
    ),
    (
      v_etab_finess, 'Etablissement revue FINESS', '72000000000003', NULL,
      'CLINIQUE_PRIVEE', '3 rue du Test', 'Paris', '75003',
      'revue-finess@test.local', true, 8, NULL, NULL, NULL, true
    );

  INSERT INTO public.etablissements (
    id, nom, siret, finess, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, siret_verifie,
    verification_source_version, finess_verifie, finess_verifie_le,
    finess_raison_sociale, finess_categorie, finess_secteur,
    finess_est_public, statut_verification, peut_publier_missions,
    est_compte_test
  ) VALUES (
    v_etab_finess_rejet, 'Etablissement rejet FINESS', '72000000000006',
    '720000006', 'CLINIQUE_PRIVEE', '6 rue du Test', 'Paris', '75006',
    'revue-finess-rejet@test.local', true, 9, true, now(),
    'Etablissement rejet FINESS', 'Etablissement de sante', 'Prive',
    false, 'VERIFIE', true, true
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, date_naissance, profession, type_contrat,
    statut_liberal, modifie_le, est_compte_test
  ) VALUES
    (
      v_soignant, 'Alice', 'Revue', 'revue-soignant@test.local',
      '1988-05-12', 'IDE', 'SALARIE', 'EN_COURS',
      '2026-07-14 05:00:00+00', true
    ),
    (
      v_soignant_rejet, 'Bob', 'Rejet', 'revue-soignant-rejet@test.local',
      '1985-04-11', 'IDE', 'SALARIE', 'EN_COURS',
      '2026-07-14 05:01:00+00', true
    );

  INSERT INTO public.file_revue_manuelle (
    id, type_entite, id_entite, service_en_echec, motif_echec,
    donnees_originales, statut, priorite, cree_le, expire_le
  ) VALUES
    (
      '72000000-0000-4000-8000-000000000011', 'ETABLISSEMENT', v_etab_rib,
      'VERIFY_RIB_ETABLISSEMENT',
      'Le controle automatique du RIB doit etre revu manuellement.',
      jsonb_build_object(
        'verification_source_version', 4,
        'verification_source_version_apres_verdict', 5,
        'rib_s3_key', v_etab_rib::text || '/rib-etablissement-revue.pdf',
        'rib_source_sha256_v1', repeat('a', 64),
        'iban_last4', '0189'
      ),
      'EN_ATTENTE', 5, '-infinity'::timestamptz, now() + interval '7 days'
    ),
    (
      '72000000-0000-4000-8000-000000000012', 'ETABLISSEMENT', v_etab_finess,
      'VERIFY_FINESS_RECOUPEMENT',
      'Le FINESS officiel actif necessite un recoupement humain.',
      jsonb_build_object(
        'verification_source_version', 8,
        'finess_candidat', '720000003',
        'finess_canonique_avant', NULL,
        'siret_profil', '72000000000003',
        'siret_profil_verifie', true,
        'donnees_officielles_candidat', jsonb_build_object(
          'raison_sociale', 'Etablissement revue FINESS',
          'actif', true,
          'categorie_label', 'Etablissement de sante',
          'secteur_label', 'Prive',
          'est_public', false
        ),
        'recoupement', jsonb_build_object('mode', 'REVUE_HUMAINE')
      ),
      'EN_ATTENTE', 5, '-infinity'::timestamptz, now() + interval '7 days'
    ),
    (
      '72000000-0000-4000-8000-000000000013', 'SOIGNANT', v_soignant,
      'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE',
      'Le registre ne publie pas la naissance du titulaire du SIRET.',
      jsonb_build_object(
        'siret_candidat', '72000000000004',
        'siret_canonique_avant', NULL,
        'preuve_deja_verifiee', false,
        'prenom_declare', 'Alice',
        'nom_declare', 'Revue',
        'date_naissance_declaree', '1988-05-12',
        'statut_liberal', 'EN_COURS',
        'type_contrat', 'SALARIE',
        'profil_modifie_le', '2026-07-14T05:00:00Z',
        'raison_sociale_officielle', 'Alice Revue',
        'siret_officiel_actif', true,
        'activite_officielle_sante', true,
        'source_officielle', 'API Recherche Entreprises / INSEE'
      ),
      'EN_ATTENTE', 5, '-infinity'::timestamptz, now() + interval '7 days'
    ),
    (
      '72000000-0000-4000-8000-000000000014', 'SOIGNANT', v_soignant_rejet,
      'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE',
      'Le titulaire du second SIRET doit etre rejete apres revue.',
      jsonb_build_object(
        'siret_candidat', '72000000000005',
        'siret_canonique_avant', NULL,
        'prenom_declare', 'Bob',
        'nom_declare', 'Rejet',
        'date_naissance_declaree', '1985-04-11',
        'statut_liberal', 'EN_COURS',
        'type_contrat', 'SALARIE',
        'profil_modifie_le', '2026-07-14T05:01:00Z',
        'raison_sociale_officielle', 'Bob Rejet',
        'siret_officiel_actif', true,
        'activite_officielle_sante', true,
        'source_officielle', 'API Recherche Entreprises / INSEE'
      ),
      'EN_ATTENTE', 5, '-infinity'::timestamptz, now() + interval '7 days'
    ),
    (
      '72000000-0000-4000-8000-000000000015', 'ETABLISSEMENT', v_etab_finess_rejet,
      'VERIFY_FINESS_RECOUPEMENT',
      'Le FINESS canonique courant doit etre rejete apres controle humain.',
      jsonb_build_object(
        'verification_source_version', 9,
        'finess_candidat', '720000006',
        'finess_canonique_avant', '720000006',
        'siret_profil', '72000000000006',
        'siret_profil_verifie', true,
        'donnees_officielles_candidat', jsonb_build_object(
          'raison_sociale', 'Etablissement rejet FINESS',
          'actif', true,
          'categorie_label', 'Etablissement de sante',
          'secteur_label', 'Prive',
          'est_public', false
        ),
        'recoupement', jsonb_build_object('mode', 'REVUE_HUMAINE')
      ),
      'EN_ATTENTE', 5, '-infinity'::timestamptz, now() + interval '7 days'
    );
END;
$fixtures$;

DO $securite_et_comportement$
DECLARE
  v_rib uuid := '72000000-0000-4000-8000-000000000011';
  v_finess uuid := '72000000-0000-4000-8000-000000000012';
  v_siret uuid := '72000000-0000-4000-8000-000000000013';
  v_siret_rejet uuid := '72000000-0000-4000-8000-000000000014';
  v_finess_rejet uuid := '72000000-0000-4000-8000-000000000015';
  v_doc_identite uuid := '72000000-0000-4000-8000-000000000021';
  v_liste jsonb;
  v_fixture_count bigint;
  v_token text;
  v_resultat jsonb;
BEGIN
  IF has_table_privilege(
       'authenticated', 'public.file_revue_manuelle', 'SELECT'
     ) IS DISTINCT FROM FALSE
     OR has_table_privilege(
       'authenticated', 'private.revue_manuelle_decisions', 'SELECT'
     ) IS DISTINCT FROM FALSE
     OR has_function_privilege(
       'authenticated',
       'public.fn_admin_lister_revues_manuelles(integer)',
       'EXECUTE'
     ) IS DISTINCT FROM TRUE
     OR has_function_privilege(
       'authenticated',
       'public.fn_admin_decider_revue_manuelle(uuid,text,text,text,jsonb)',
       'EXECUTE'
     ) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Exposition SQL de la file ou des RPC invalide';
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"72000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',
    true
  );
  BEGIN
    PERFORM public.fn_admin_lister_revues_manuelles(500);
    RAISE EXCEPTION 'Une session AAL1 a lu la file de revue';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"72000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
    true
  );
  -- Les fixtures ont la priorité maximale et `cree_le = -infinity` : elles
  -- restent en tête de la page maximale, indépendamment de la file staging.
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT count(*)
  INTO v_fixture_count
  FROM jsonb_array_elements(COALESCE(v_liste->'revues', '[]'::jsonb)) AS item
  WHERE item->>'id' IN (
    v_rib::text,
    v_finess::text,
    v_siret::text,
    v_siret_rejet::text,
    v_finess_rejet::text
  );
  IF v_liste->>'success' IS DISTINCT FROM 'true'
     OR v_fixture_count IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'Projection de file incomplete: %', v_liste;
  END IF;
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_rib::text;
  IF COALESCE(v_token, '') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Jeton CAS RIB absent: %', v_liste;
  END IF;

  -- Un retry producteur invalide le snapshot lu par l'admin.
  UPDATE public.file_revue_manuelle
  SET motif_echec = motif_echec || ' Nouvelle tentative.'
  WHERE id = v_rib;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_rib, 'APPROUVER', 'RIB lisible et titulaire confirme.', v_token,
      '{"iban":"FR7630006000011234567890189"}'::jsonb
    );
    RAISE EXCEPTION 'Un jeton CAS obsolete a ete accepte';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;

  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_rib::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_rib, 'APPROUVER', 'RIB lisible et titulaire confirme.', v_token,
      '{"iban":"FR7630006000011234567890189"}'::jsonb
    );
    RAISE EXCEPTION 'Un RIB sans objet Storage courant a ete approuve';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  UPDATE public.file_revue_manuelle
  SET donnees_originales = jsonb_set(
    donnees_originales,
    '{rib_source_sha256_v1}',
    '"invalide"'::jsonb
  )
  WHERE id = v_rib;
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_rib::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_rib, 'APPROUVER', 'RIB lisible et titulaire confirme.', v_token,
      '{"iban":"FR7630006000011234567890189"}'::jsonb
    );
    RAISE EXCEPTION 'Un snapshot RIB sans SHA-256 valide a ete approuve';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  UPDATE public.file_revue_manuelle
  SET donnees_originales = jsonb_set(
    donnees_originales,
    '{rib_source_sha256_v1}',
    to_jsonb(repeat('a', 64))
  )
  WHERE id = v_rib;

  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES (
    'jolene-documents',
    '72000000-0000-4000-8000-000000000002/rib-etablissement-revue.pdf',
    '{"mimetype":"application/pdf"}'::jsonb
  );
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_rib::text;
  v_resultat := public.fn_admin_decider_revue_manuelle(
    v_rib, 'APPROUVER', 'RIB lisible et titulaire confirme.', v_token,
    '{"iban":"FR7630006000011234567890189"}'::jsonb
  );
  IF v_resultat->>'success' IS DISTINCT FROM 'true'
     OR v_resultat->>'idempotent' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Approbation RIB echouee: %', v_resultat;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.etablissements
    WHERE id = '72000000-0000-4000-8000-000000000002'
      AND rib_ia_coherent IS TRUE
      AND iban_last4 = '0189'
      AND rib_verifie_s3_key = rib_s3_key
      AND rib_verifie_source_version = verification_source_version
  ) OR NOT EXISTS (
    SELECT 1 FROM public.file_revue_manuelle
    WHERE id = v_rib AND statut = 'RESOLU_MANUELLEMENT'
      AND resolu_le IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM private.revue_manuelle_decisions
    WHERE revue_id = v_rib AND decision = 'APPROUVER'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.journaux_audit
    WHERE id_ressource = v_rib AND action = 'ADMIN_ACTION'
      AND details->>'sous_action' = 'DECISION_REVUE_MANUELLE'
  ) THEN
    RAISE EXCEPTION 'Etat, provenance ou audit RIB incomplet';
  END IF;

  v_resultat := public.fn_admin_decider_revue_manuelle(
    v_rib, 'APPROUVER', 'Retry de la meme decision RIB.', v_token,
    '{"iban":"FR7630006000011234567890189"}'::jsonb
  );
  IF v_resultat->>'success' IS DISTINCT FROM 'true'
     OR v_resultat->>'idempotent' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Retry idempotent RIB refuse: %', v_resultat;
  END IF;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_rib, 'REJETER', 'Tentative de verdict contraire.', v_token, '{}'::jsonb
    );
    RAISE EXCEPTION 'Un second verdict contraire a ete accepte';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;

  -- Le recoupement FINESS applique le candidat officiel seulement apres revue.
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_finess::text;
  v_resultat := public.fn_admin_decider_revue_manuelle(
    v_finess, 'APPROUVER', 'FINESS actif et rattachement confirme.', v_token, '{}'::jsonb
  );
  IF v_resultat->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
    SELECT 1 FROM public.etablissements
    WHERE id = '72000000-0000-4000-8000-000000000003'
      AND finess = '720000003'
      AND finess_verifie IS TRUE
      AND finess_raison_sociale = 'Etablissement revue FINESS'
  ) THEN
    RAISE EXCEPTION 'Approbation FINESS echouee: %', v_resultat;
  END IF;

  -- Un rejet du FINESS canonique révoque la preuve et la publication.
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_finess_rejet::text;
  v_resultat := public.fn_admin_decider_revue_manuelle(
    v_finess_rejet, 'REJETER', 'FINESS canonique non confirme apres controle.', v_token, '{}'::jsonb
  );
  IF v_resultat->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
    SELECT 1 FROM public.etablissements
    WHERE id = '72000000-0000-4000-8000-000000000006'
      AND finess = '720000006'
      AND finess_verifie IS FALSE
      AND finess_verifie_le IS NULL
      AND finess_raison_sociale IS NULL
      AND statut_verification = 'EN_COURS'
      AND peut_publier_missions IS FALSE
      AND verifie_le IS NULL
  ) THEN
    RAISE EXCEPTION 'Le rejet FINESS canonique n a pas revoque la publication: %', v_resultat;
  END IF;

  -- L'approbation SIRET exige une pièce précise, courante et concordante.
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_siret::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_siret, 'APPROUVER', 'Identite supposee sans preuve documentaire.', v_token, '{}'::jsonb
    );
    RAISE EXCEPTION 'Un SIRET sans piece d identite a ete approuve';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  INSERT INTO public.documents_soignants (
    id, soignant_id, type_document, s3_cle, nom_fichier, type_mime,
    taille_octets, valide_depuis, valide_jusqua, statut_verification,
    verifie_par, verifie_le, resultat_ia, nom_extrait_ia,
    prenom_extrait_ia, coherence_nom
  ) VALUES (
    v_doc_identite, '72000000-0000-4000-8000-000000000004',
    'CARTE_IDENTITE',
    '72000000-0000-4000-8000-000000000004/identite-expiree.pdf',
    'identite-expiree.pdf', 'application/pdf', 2048,
    current_date - 10, current_date - 1, 'VERIFIE',
    '72000000-0000-4000-8000-000000000001', now(),
    jsonb_build_object(
      'verdict_serveur', 'VERIFIE',
      'date_naissance_extraite', '1988-05-12'
    ),
    'Revue', 'Alice', true
  );
  UPDATE public.file_revue_manuelle f
  SET donnees_originales = jsonb_set(
    f.donnees_originales, '{profil_modifie_le}', to_jsonb(s.modifie_le)
  )
  FROM public.soignants s
  WHERE f.id = v_siret AND s.id = f.id_entite;
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_siret::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_siret, 'APPROUVER', 'Identite expiree a ne pas accepter.', v_token, '{}'::jsonb
    );
    RAISE EXCEPTION 'Une piece d identite expiree a autorise le SIRET';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  -- La date d'expiration est exclusive : une piece valable jusqu'a aujourd'hui
  -- n'autorise deja plus une nouvelle activation liberale.
  UPDATE public.documents_soignants
  SET valide_jusqua = current_date,
      nom_extrait_ia = 'Revue',
      modifie_le = now()
  WHERE id = v_doc_identite;
  UPDATE public.file_revue_manuelle f
  SET donnees_originales = jsonb_set(
    f.donnees_originales, '{profil_modifie_le}', to_jsonb(s.modifie_le)
  )
  FROM public.soignants s
  WHERE f.id = v_siret AND s.id = f.id_entite;
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_siret::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_siret, 'APPROUVER', 'Identite expirant aujourd hui a refuser.', v_token, '{}'::jsonb
    );
    RAISE EXCEPTION 'Une piece expirant aujourd hui a autorise le SIRET';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  UPDATE public.documents_soignants
  SET valide_jusqua = current_date + 1,
      nom_extrait_ia = 'Autre',
      modifie_le = now()
  WHERE id = v_doc_identite;
  UPDATE public.file_revue_manuelle f
  SET donnees_originales = jsonb_set(
    f.donnees_originales, '{profil_modifie_le}', to_jsonb(s.modifie_le)
  )
  FROM public.soignants s
  WHERE f.id = v_siret AND s.id = f.id_entite;
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_siret::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_siret, 'APPROUVER', 'Identite incoherente a ne pas accepter.', v_token, '{}'::jsonb
    );
    RAISE EXCEPTION 'Une piece d identite incoherente a autorise le SIRET';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  UPDATE public.documents_soignants
  SET nom_extrait_ia = 'Revue',
      modifie_le = now()
  WHERE id = v_doc_identite;
  UPDATE public.file_revue_manuelle f
  SET donnees_originales = jsonb_set(
    f.donnees_originales, '{profil_modifie_le}', to_jsonb(s.modifie_le)
  )
  FROM public.soignants s
  WHERE f.id = v_siret AND s.id = f.id_entite;
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_siret::text;
  BEGIN
    PERFORM public.fn_admin_decider_revue_manuelle(
      v_siret, 'APPROUVER', 'Identite sans objet Storage a refuser.', v_token, '{}'::jsonb
    );
    RAISE EXCEPTION 'Une piece sans objet Storage exact a autorise le SIRET';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES (
    'jolene-documents',
    '72000000-0000-4000-8000-000000000004/identite-expiree.pdf',
    '{"mimetype":"application/pdf"}'::jsonb
  );
  v_resultat := public.fn_admin_decider_revue_manuelle(
    v_siret, 'APPROUVER', 'Identite courante et titulaire SIRET demontres.', v_token, '{}'::jsonb
  );
  IF v_resultat->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = '72000000-0000-4000-8000-000000000004'
      AND siret_liberal = '72000000000004'
      AND siret_liberal_verifie IS TRUE
      AND siret_liberal_coherence_identite IS TRUE
      AND siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'
      AND siret_liberal_preuve_siret = siret_liberal
      AND siret_liberal_preuve_identite_document_id = v_doc_identite
      AND siret_liberal_preuve_identite_storage_object_id IS NOT NULL
      AND siret_liberal_preuve_identite_empreinte_sha256 ~ '^[0-9a-f]{64}$'
  ) OR NOT EXISTS (
    SELECT 1 FROM private.revue_manuelle_decisions
    WHERE revue_id = v_siret AND decision = 'APPROUVER'
  ) THEN
    RAISE EXCEPTION 'Approbation SIRET avec preuve courante echouee: %', v_resultat;
  END IF;

  IF private.fn_preuve_identite_siret_manuelle_courante(
       '72000000-0000-4000-8000-000000000004'
     ) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'La provenance SIRET approuvee n est pas relue comme courante';
  END IF;

  -- Une revocation (le mecanisme aussi utilise lors d'un remplacement) retire
  -- immediatement la provenance et rend toute nouvelle activation impossible.
  UPDATE public.documents_soignants
  SET revoque_le = now(),
      revoque_raison = 'REMPLACEMENT',
      modifie_le = now()
  WHERE id = v_doc_identite;
  IF NOT EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = '72000000-0000-4000-8000-000000000004'
      AND siret_liberal_verifie IS FALSE
      AND siret_liberal_verifie_le IS NULL
      AND siret_liberal_coherence_identite IS NULL
      AND siret_liberal_source_verification IS NULL
      AND siret_liberal_preuve_identite_document_id IS NULL
      AND tous_documents_valides IS FALSE
  ) THEN
    RAISE EXCEPTION 'La revocation de la piece n a pas revoque la preuve SIRET';
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"72000000-0000-4000-8000-000000000004","role":"authenticated","aal":"aal1"}',
    true
  );
  v_resultat := public.fn_activer_liberal();
  IF v_resultat->>'success' IS DISTINCT FROM 'false'
     OR v_resultat->>'error_code' IS DISTINCT FROM 'SIRET_LIBERAL_NON_VERIFIE' THEN
    RAISE EXCEPTION 'Une activation avec preuve revoquee n a pas echoue: %', v_resultat;
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    '{"sub":"72000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',
    true
  );

  -- Un rejet SIRET séparé ne remplace jamais le canonique par le candidat.
  v_liste := public.fn_admin_lister_revues_manuelles(500);
  SELECT item->>'jeton_cas' INTO v_token
  FROM jsonb_array_elements(v_liste->'revues') AS item
  WHERE item->>'id' = v_siret_rejet::text;
  v_resultat := public.fn_admin_decider_revue_manuelle(
    v_siret_rejet, 'REJETER', 'Identite du titulaire non demontree.', v_token, '{}'::jsonb
  );
  IF v_resultat->>'success' IS DISTINCT FROM 'true' OR EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = '72000000-0000-4000-8000-000000000005'
      AND siret_liberal IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM private.revue_manuelle_decisions
    WHERE revue_id = v_siret_rejet AND decision = 'REJETER'
  ) THEN
    RAISE EXCEPTION 'Rejet SIRET non canonique: %', v_resultat;
  END IF;
END;
$securite_et_comportement$;

ROLLBACK;

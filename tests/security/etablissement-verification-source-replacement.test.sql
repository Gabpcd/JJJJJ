\set ON_ERROR_STOP on

-- Test transactionnel du conflit entre les deux BEFORE UPDATE triggers.
-- Usage : supabase db query --local --file tests/security/etablissement-verification-source-replacement.test.sql
BEGIN;

DO $test$
DECLARE
  v_user uuid := 'ffffffff-7132-4000-8000-000000000001';
  v_etab uuid := 'ffffffff-7132-4000-8000-000000000002';
  v_signature_le timestamptz;
  v_row public.etablissements%ROWTYPE;
  v_blocked boolean;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES (
    v_user,
    '00000000-0000-0000-0000-000000000000',
    'trigger-etablissement@test.local',
    'authenticated',
    'authenticated',
    jsonb_build_object('role', 'ETABLISSEMENT', 'etablissement_id', v_etab),
    now()
  );

  INSERT INTO public.etablissements (
    id, nom, siret, finess, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test,
    representant_nom, representant_prenom, representant_piece_s3_key,
    representant_piece_type_document, representant_piece_type_mime,
    representant_identite_verifiee, representant_identite_verifiee_le,
    representant_identite_resultat_ia,
    justificatif_fonction_s3_key, justificatif_fonction_type,
    justificatif_fonction_type_mime, justificatif_fonction_verifie,
    justificatif_fonction_verifie_le, justificatif_fonction_resultat_ia,
    rattachement_verifie, rattachement_verifie_le, rattachement_methode,
    rib_s3_key, rib_ia_resultat, rib_ia_coherent, rib_ia_verifie_le, iban_last4,
    verification_source_version, rib_verifie_s3_key, rib_verifie_source_version,
    contrat_url, contrat_uploade_le, contrat_valide, contrat_ia_resultat,
    contrat_ia_coherent, contrat_ia_verifie_le,
    siret_verifie, siret_verifie_le, siret_raison_sociale,
    siret_categorie_juridique, siret_code_naf, siret_est_actif,
    finess_verifie, finess_verifie_le, finess_raison_sociale,
    finess_categorie, finess_secteur, finess_est_public,
    statut_verification, peut_publier_missions, verifie_le, verifie_par,
    contrat_service_signe, contrat_service_signe_le
  ) VALUES (
    v_etab, 'Clinique Trigger', '99999999999983', '999999983',
    'CLINIQUE_PRIVEE', '1 rue Trigger', 'Paris', '75001',
    'trigger-etablissement@test.local', true,
    'Martin', 'Alice', v_etab::text || '/identite/ancienne.pdf',
    'CARTE_IDENTITE', 'application/pdf', true, now(), '{"verdict":"VERIFIE"}',
    v_etab::text || '/fonction/ancienne.pdf', 'KBIS', 'application/pdf',
    true, now(), '{"verdict":"VERIFIE"}',
    true, now(), 'JUSTIFICATIF',
    v_etab::text || '/rib/ancien.pdf', '{"verdict":"CONFORME"}', true, now(), '1234',
    0, v_etab::text || '/rib/ancien.pdf', 0,
    v_etab::text || '/contrat/ancien.pdf', now(), true, '{"verdict":"CONFORME"}', true, now(),
    true, now(), 'CLINIQUE TRIGGER', '5710', '8610Z', true,
    true, now(), 'CLINIQUE TRIGGER', '1100', 'PRIVE', false,
    'EN_COURS', false, NULL, NULL, false, NULL
  );

  INSERT INTO public.contrats_service_signatures (
    etablissement_id, version, ip_address, user_agent, contenu_hash,
    signature_s3_key
  ) VALUES (
    v_etab, 'v1.0', '127.0.0.1', 'test-sql', repeat('a', 64),
    v_user::text || '/signatures/contrat-service-test.png'
  ) RETURNING signed_at INTO v_signature_le;

  -- Mise en état vérifié par le contexte serveur de la fixture.
  UPDATE public.etablissements
  SET contrat_service_signe = true,
      contrat_service_signe_le = v_signature_le,
      statut_verification = 'VERIFIE',
      peut_publier_missions = true,
      verifie_le = now(),
      verifie_par = v_user
  WHERE id = v_etab;

  -- 1. Un établissement vérifié peut remplacer son RIB. L'UPDATE ne doit pas
  -- être bloqué par le protector et les deux niveaux de verdict sont révoqués.
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user, 'role', 'authenticated'
  )::text, true);
  SET LOCAL role = 'authenticated';
  UPDATE public.etablissements
  SET rib_s3_key = v_etab::text || '/rib/nouveau.pdf'
  WHERE id = v_etab;
  SET LOCAL role = 'postgres';

  SELECT * INTO v_row FROM public.etablissements WHERE id = v_etab;
  IF v_row.rib_ia_resultat IS NOT NULL OR v_row.rib_ia_coherent IS NOT NULL
     OR v_row.rib_ia_verifie_le IS NOT NULL OR v_row.iban_last4 IS NOT NULL
     OR v_row.rib_verifie_s3_key IS NOT NULL
     OR v_row.rib_verifie_source_version IS NOT NULL
     OR v_row.statut_verification <> 'EN_COURS'
     OR v_row.peut_publier_missions IS NOT FALSE
     OR v_row.verifie_le IS NOT NULL OR v_row.verifie_par IS NOT NULL THEN
    RAISE EXCEPTION 'RIB: remplacement non révoqué canoniquement';
  END IF;

  -- Réinitialisation serveur, en deux écritures : changement de source puis
  -- pose du nouveau verdict. Le normalizer révoque toujours la première.
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE public.etablissements
  SET rib_s3_key = v_etab::text || '/rib/valide.pdf'
  WHERE id = v_etab;
  UPDATE public.etablissements
  SET rib_ia_resultat = '{"verdict":"CONFORME"}', rib_ia_coherent = true,
      rib_ia_verifie_le = now(), iban_last4 = '5678',
      rib_verifie_s3_key = rib_s3_key,
      rib_verifie_source_version = verification_source_version,
      statut_verification = 'VERIFIE', peut_publier_missions = true,
      verifie_le = now(), verifie_par = v_user
  WHERE id = v_etab;

  -- 2. Le changement de SIRET doit aussi passer lorsque l'ancien rattachement
  -- reste théoriquement déductible du justificatif : l'invalidation de la
  -- source prime sur ce recalcul et remet explicitement le rattachement à zéro.
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user, 'role', 'authenticated'
  )::text, true);
  SET LOCAL role = 'authenticated';
  UPDATE public.etablissements
  SET siret = '99999999999991'
  WHERE id = v_etab;
  SET LOCAL role = 'postgres';

  SELECT * INTO v_row FROM public.etablissements WHERE id = v_etab;
  IF v_row.siret_verifie IS NOT FALSE OR v_row.siret_verifie_le IS NOT NULL
     OR v_row.siret_raison_sociale IS NOT NULL OR v_row.dirigeants IS NOT NULL
     OR v_row.rattachement_verifie IS NOT FALSE
     OR v_row.rattachement_verifie_le IS NOT NULL
     OR v_row.rattachement_methode <> 'ADMIN'
     OR v_row.rib_ia_resultat IS NOT NULL
     OR v_row.rib_ia_coherent IS NOT NULL
     OR v_row.rib_ia_verifie_le IS NOT NULL
     OR v_row.rib_verifie_s3_key IS NOT NULL
     OR v_row.rib_verifie_source_version IS NOT NULL
     OR v_row.statut_verification <> 'EN_COURS'
     OR v_row.peut_publier_missions IS NOT FALSE THEN
    RAISE EXCEPTION 'SIRET: remplacement non révoqué canoniquement';
  END IF;

  -- Reconstitution serveur en écritures séparées : le verdict SIRET modifie
  -- les dirigeants, puis le rattachement est recalculé, puis l'admin promeut.
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE public.etablissements
  SET siret_verifie = true, siret_verifie_le = now(),
      siret_raison_sociale = 'CLINIQUE TRIGGER',
      siret_categorie_juridique = '5710', siret_code_naf = '8610Z',
      siret_est_actif = true,
      dirigeants = '[{"type_dirigeant":"Personne physique","nom":"Martin","prenoms":"Alice"}]'
  WHERE id = v_etab;
  UPDATE public.etablissements
  SET rattachement_verifie = true, rattachement_verifie_le = now(),
      rattachement_methode = 'AUTO_DIRIGEANT'
  WHERE id = v_etab;
  UPDATE public.etablissements
  SET statut_verification = 'VERIFIE', peut_publier_missions = true,
      verifie_le = now(), verifie_par = v_user
  WHERE id = v_etab;

  -- 3. Même garantie pour une pièce d'identité : identité et rattachement sont
  -- révoqués, sans échec de l'UPDATE authentifié.
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user, 'role', 'authenticated'
  )::text, true);
  SET LOCAL role = 'authenticated';
  UPDATE public.etablissements
  SET representant_piece_s3_key = v_etab::text || '/identite/nouvelle.pdf'
  WHERE id = v_etab;
  SET LOCAL role = 'postgres';

  SELECT * INTO v_row FROM public.etablissements WHERE id = v_etab;
  IF v_row.representant_identite_verifiee IS NOT FALSE
     OR v_row.representant_identite_verifiee_le IS NOT NULL
     OR v_row.representant_identite_resultat_ia IS NOT NULL
     OR v_row.rattachement_verifie IS NOT FALSE
     OR v_row.rattachement_verifie_le IS NOT NULL
     OR v_row.rattachement_methode <> 'ADMIN'
     OR v_row.statut_verification <> 'EN_COURS'
     OR v_row.peut_publier_missions IS NOT FALSE THEN
    RAISE EXCEPTION 'Identité: remplacement non révoqué canoniquement';
  END IF;

  -- 4. Les trois autres familles documentaires suivent la même règle : la
  -- source reste modifiable, mais jamais avec son ancien résultat serveur.
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user, 'role', 'authenticated'
  )::text, true);
  SET LOCAL role = 'authenticated';
  UPDATE public.etablissements
  SET justificatif_fonction_s3_key = v_etab::text || '/fonction/nouveau.pdf'
  WHERE id = v_etab;
  UPDATE public.etablissements
  SET contrat_url = v_etab::text || '/contrat/nouveau.pdf'
  WHERE id = v_etab;
  UPDATE public.etablissements
  SET finess = '999999991'
  WHERE id = v_etab;
  SET LOCAL role = 'postgres';

  SELECT * INTO v_row FROM public.etablissements WHERE id = v_etab;
  IF v_row.justificatif_fonction_verifie IS NOT FALSE
     OR v_row.justificatif_fonction_verifie_le IS NOT NULL
     OR v_row.justificatif_fonction_resultat_ia IS NOT NULL THEN
    RAISE EXCEPTION 'Justificatif: remplacement non révoqué canoniquement';
  END IF;
  IF v_row.contrat_valide IS NOT FALSE OR v_row.contrat_ia_resultat IS NOT NULL
     OR v_row.contrat_ia_coherent IS NOT NULL
     OR v_row.contrat_ia_verifie_le IS NOT NULL
     OR v_row.contrat_uploade_le IS NULL THEN
    RAISE EXCEPTION 'Contrat uploadé: remplacement non révoqué canoniquement';
  END IF;
  IF v_row.finess_verifie IS NOT FALSE OR v_row.finess_verifie_le IS NOT NULL
     OR v_row.finess_raison_sociale IS NOT NULL
     OR v_row.finess_categorie IS NOT NULL
     OR v_row.finess_secteur IS NOT NULL
     OR v_row.finess_est_public IS NOT NULL THEN
    RAISE EXCEPTION 'FINESS: remplacement non révoqué canoniquement';
  END IF;

  -- 5. Une GUC posée dans la session ne doit jamais autoriser l'écriture d'un
  -- verdict serveur. Le SQLSTATE 42501 prouve que le contrôle précède la GUC.
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user, 'role', 'authenticated'
  )::text, true);
  PERFORM set_config('app.internal_operation', 'true', true);
  SET LOCAL role = 'authenticated';
  v_blocked := false;
  BEGIN
    UPDATE public.etablissements SET siret_verifie = false WHERE id = v_etab;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Un utilisateur a modifié siret_verifie via la GUC interne';
  END IF;

  v_blocked := false;
  BEGIN
    UPDATE public.etablissements
    SET contrat_service_signe = false, contrat_service_signe_le = NULL
    WHERE id = v_etab;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Un utilisateur a modifié le contrat signé sans révoquer la preuve';
  END IF;

  v_blocked := false;
  BEGIN
    UPDATE public.etablissements
    SET statut_verification = 'SUSPENDU'
    WHERE id = v_etab;
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Un utilisateur a modifié directement le statut';
  END IF;
  SET LOCAL role = 'postgres';

  -- 6. Le service role conserve sa capacité à écrire les verdicts.
  PERFORM set_config('app.internal_operation', 'false', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE public.etablissements
  SET siret_verifie = false, siret_verifie_le = NULL
  WHERE id = v_etab;
  IF (SELECT siret_verifie FROM public.etablissements WHERE id = v_etab) IS NOT FALSE THEN
    RAISE EXCEPTION 'Le service role ne peut plus écrire les verdicts';
  END IF;
END;
$test$;

ROLLBACK;

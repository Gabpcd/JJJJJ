-- P0 identité soignant — scénarios comportementaux transactionnels.
-- Usage : psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--   -f tests/admin/security/soignant-identity-hardening.test.sql

\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_as uuid := gen_random_uuid();
  v_passport uuid := gen_random_uuid();
  v_titre uuid := gen_random_uuid();
  v_dob_mismatch uuid := gen_random_uuid();
  v_delete uuid := gen_random_uuid();
  v_move_from uuid := gen_random_uuid();
  v_move_to uuid := gen_random_uuid();
  v_move_doc uuid;
  v_id uuid;
  v_type public.type_document;
  v_result jsonb;
  v_rpps text;
  v_specialite_code text;
  v_specialite_label text;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true),
    ''
  );
BEGIN
  -- AS + CNI : la pièce suffit à vérifier l'identité, sans RPPS.
  INSERT INTO public.soignants(id, prenom, nom, email, date_naissance, profession)
  VALUES (v_as, 'Marie', 'Lefèvre', 'identity-as-' || v_as::text || '@test.local', DATE '1990-05-12', 'AS');

  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom, verifie_le
  ) VALUES (
    v_as, 'CARTE_IDENTITE', v_as::text || '/documents/cni.pdf', 'cni.pdf', 'VERIFIE',
    jsonb_build_object('date_naissance_extraite', '1990-05-12'),
    'LEFEVRE', 'Marie', true, now()
  );

  -- Toute preuve rattachée aux anciens traits doit suivre la même cascade, pas
  -- seulement la pièce d'identité.
  FOREACH v_type IN ARRAY ARRAY[
    'DIPLOME'::public.type_document,
    'AUTORISATION_EXERCICE'::public.type_document,
    'RPPS_ADELI'::public.type_document,
    'RIB'::public.type_document,
    'RCP_ASSURANCE'::public.type_document,
    'ATTESTATION_URSSAF'::public.type_document
  ] LOOP
    INSERT INTO public.documents_soignants(
      soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
      resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom, verifie_le
    ) VALUES (
      v_as, v_type, v_as::text || '/documents/' || lower(v_type::text) || '.pdf',
      lower(v_type::text) || '.pdf', 'VERIFIE', '{}'::jsonb,
      'LEFEVRE', 'Marie', true, now()
    );
  END LOOP;

  SELECT sm.code, sm.label
  INTO v_specialite_code, v_specialite_label
  FROM public.specialites_medicales sm
  WHERE sm.actif IS TRUE
  ORDER BY sm.code
  LIMIT 1;
  IF v_specialite_code IS NULL OR v_specialite_label IS NULL THEN
    RAISE EXCEPTION 'IDENTITE-FIXTURE: aucune spécialité médicale active';
  END IF;

  UPDATE public.soignants
  SET diplome_verifie = true,
      siret_liberal = '73282932000074',
      siret_liberal_verifie = true,
      siret_liberal_verifie_le = now(),
      siret_liberal_raison_sociale = 'MARIE LEFEVRE',
      siret_liberal_coherence_identite = true,
      specialite_medicale = v_specialite_code,
      specialite_code = v_specialite_code,
      specialite_source = 'RPPS',
      specialite_verifiee = true,
      specialite_verifiee_le = now(),
      specialite_medicale_declaree = 'Médecine générale'
  WHERE id = v_as;

  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_as) IS NOT TRUE THEN
    RAISE EXCEPTION 'IDENTITE-T1: une CNI concordante doit vérifier le profil AS sans RPPS';
  END IF;

  -- Correction légitime : elle passe, mais la CNI et le statut sont révoqués.
  UPDATE public.soignants SET nom = 'Martin' WHERE id = v_as;
  IF (SELECT nom FROM public.soignants WHERE id = v_as) <> 'Martin' THEN
    RAISE EXCEPTION 'IDENTITE-T2: la correction du nom a été bloquée';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.documents_soignants
    WHERE soignant_id = v_as AND type_document = 'CARTE_IDENTITE'
      AND statut_verification = 'VERIFIE'
  ) THEN
    RAISE EXCEPTION 'IDENTITE-T3: la CNI est restée vérifiée après changement du nom';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.documents_soignants
    WHERE soignant_id = v_as AND statut_verification = 'VERIFIE'
  ) THEN
    RAISE EXCEPTION 'IDENTITE-T3B: une preuve liée aux anciens traits est restée vérifiée';
  END IF;
  IF (SELECT diplome_verifie FROM public.soignants WHERE id = v_as) IS NOT FALSE THEN
    RAISE EXCEPTION 'IDENTITE-T3C: diplome_verifie est resté actif après changement du nom';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = v_as
      AND (
        siret_liberal_verifie IS TRUE
        OR siret_liberal_verifie_le IS NOT NULL
        OR siret_liberal_raison_sociale IS NOT NULL
        OR siret_liberal_coherence_identite IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'IDENTITE-T3F: la preuve SIRET liée aux anciens traits est restée active';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = v_as
      AND (specialite_medicale IS NOT NULL OR specialite_code IS NOT NULL
        OR specialite_source IS NOT NULL OR specialite_verifiee IS TRUE)
  ) THEN
    RAISE EXCEPTION 'IDENTITE-T3D: la spécialité RPPS liée aux anciens traits est restée active';
  END IF;
  IF (SELECT specialite_medicale_declaree FROM public.soignants WHERE id = v_as)
       IS DISTINCT FROM 'Médecine générale' THEN
    RAISE EXCEPTION 'IDENTITE-T3E: la spécialité déclarative a été effacée';
  END IF;
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_as) IS NOT FALSE
     OR (SELECT coherence_identite FROM public.soignants WHERE id = v_as) <> 'EN_ATTENTE_REVUE' THEN
    RAISE EXCEPTION 'IDENTITE-T4: les indicateurs identité n''ont pas été invalidés';
  END IF;

  -- Passeport et titre de séjour suivent exactement la même cascade.
  FOREACH v_type IN ARRAY ARRAY[
    'PASSEPORT'::public.type_document,
    'TITRE_SEJOUR'::public.type_document
  ] LOOP
    v_id := CASE WHEN v_type = 'PASSEPORT' THEN v_passport ELSE v_titre END;
    INSERT INTO public.soignants(id, prenom, nom, email, date_naissance, profession)
    VALUES (v_id, 'Samira', 'Benali', 'identity-' || lower(v_type::text) || '-' || v_id::text || '@test.local', DATE '1988-09-23', 'AES');
    INSERT INTO public.documents_soignants(
      soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
      resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom, verifie_le
    ) VALUES (
      v_id, v_type, v_id::text || '/documents/' || lower(v_type::text) || '.pdf',
      lower(v_type::text) || '.pdf', 'VERIFIE',
      jsonb_build_object('date_naissance_extraite', '1988-09-23'),
      'BENALI', 'Samira', true, now()
    );
    IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_id) IS NOT TRUE THEN
      RAISE EXCEPTION 'IDENTITE-T5: % concordant n''a pas vérifié le profil', v_type;
    END IF;
    IF public.fn_type_document_preuve_compatible('CARTE_IDENTITE', v_type) IS NOT TRUE THEN
      RAISE EXCEPTION 'IDENTITE-T5B: % ne satisfait pas l''exigence de pièce officielle', v_type;
    END IF;
  END LOOP;

  -- Le cache doit suivre les colonnes sources réellement relues par le calcul,
  -- puis la suppression logique de la preuve.
  UPDATE public.documents_soignants
  SET resultat_ia = jsonb_build_object('date_naissance_extraite', '1988-09-24')
  WHERE soignant_id = v_titre AND type_document = 'TITRE_SEJOUR';
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_titre) IS NOT FALSE THEN
    RAISE EXCEPTION 'IDENTITE-T9: une date source contradictoire a laissé le cache identité actif';
  END IF;

  UPDATE public.documents_soignants
  SET resultat_ia = jsonb_build_object('date_naissance_extraite', '1988-09-23')
  WHERE soignant_id = v_titre AND type_document = 'TITRE_SEJOUR';
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_titre) IS NOT TRUE THEN
    RAISE EXCEPTION 'IDENTITE-T10: la correction de la source n''a pas recalculé le cache identité';
  END IF;

  UPDATE public.documents_soignants
  SET supprime_le = now()
  WHERE soignant_id = v_titre AND type_document = 'TITRE_SEJOUR';
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_titre) IS NOT FALSE THEN
    RAISE EXCEPTION 'IDENTITE-T11: une preuve supprimée logiquement est restée active dans le cache';
  END IF;

  -- Une suppression physique interne doit produire exactement la même
  -- invalidation, même si elle ne passe pas par une transition de statut.
  INSERT INTO public.soignants(id, prenom, nom, email, date_naissance, profession)
  VALUES (v_delete, 'Nora', 'Petit', 'identity-delete-' || v_delete::text || '@test.local', DATE '1985-04-03', 'AS');
  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom, verifie_le
  ) VALUES (
    v_delete, 'PASSEPORT', v_delete::text || '/documents/passport.pdf',
    'passport.pdf', 'VERIFIE',
    jsonb_build_object('date_naissance_extraite', '1985-04-03'),
    'PETIT', 'Nora', true, now()
  );
  DELETE FROM public.documents_soignants
  WHERE soignant_id = v_delete AND type_document = 'PASSEPORT';
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_delete) IS NOT FALSE THEN
    RAISE EXCEPTION 'IDENTITE-T12: une preuve supprimée physiquement est restée active dans le cache';
  END IF;

  -- Une réaffectation interne retire la preuve à OLD et l'ajoute à NEW. Les deux
  -- profils doivent être recalculés dans la même transaction, une seule fois.
  INSERT INTO public.soignants(id, prenom, nom, email, date_naissance, profession)
  VALUES
    (v_move_from, 'Leïla', 'Robert', 'identity-move-from-' || v_move_from::text || '@test.local', DATE '1992-06-14', 'AS'),
    (v_move_to, 'Leïla', 'Robert', 'identity-move-to-' || v_move_to::text || '@test.local', DATE '1992-06-14', 'AS');
  INSERT INTO public.documents_soignants(
    soignant_id, type_document, s3_cle, nom_fichier, statut_verification,
    resultat_ia, nom_extrait_ia, prenom_extrait_ia, coherence_nom, verifie_le
  ) VALUES (
    v_move_from, 'CARTE_IDENTITE', v_move_from::text || '/documents/cni.pdf',
    'cni.pdf', 'VERIFIE',
    jsonb_build_object('date_naissance_extraite', '1992-06-14'),
    'ROBERT', 'Leïla', true, now()
  ) RETURNING id INTO v_move_doc;

  UPDATE public.documents_soignants
  SET soignant_id = v_move_to
  WHERE id = v_move_doc;
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_move_from) IS NOT FALSE THEN
    RAISE EXCEPTION 'IDENTITE-T13: l''ancien propriétaire a conservé la preuve transférée';
  END IF;
  IF (SELECT identite_verifiee FROM public.soignants WHERE id = v_move_to) IS NOT TRUE THEN
    RAISE EXCEPTION 'IDENTITE-T14: le nouveau propriétaire n''a pas reçu la preuve transférée';
  END IF;

  -- Un changement nom/prénom révoque aussi le registre professionnel, car sa
  -- vérification portait sur les anciens traits.
  v_rpps := '1' || right(lpad(regexp_replace(v_passport::text, '[^0-9]', '', 'g'), 10, '0'), 10);
  UPDATE public.soignants
  SET numero_rpps = v_rpps,
      rpps_verifie = true,
      rpps_verifie_le = now(),
      rpps_nom_api = 'BENALI',
      rpps_prenom_api = 'Samira',
      rpps_profession_api = 'IDE'
  WHERE id = v_passport;
  UPDATE public.soignants SET prenom = 'Sarah' WHERE id = v_passport;
  IF (SELECT rpps_verifie FROM public.soignants WHERE id = v_passport) IS NOT FALSE THEN
    RAISE EXCEPTION 'IDENTITE-T5C: le RPPS lié aux anciens traits est resté vérifié';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.documents_soignants
    WHERE soignant_id = v_passport AND statut_verification = 'VERIFIE'
      AND type_document = 'PASSEPORT'
  ) THEN
    RAISE EXCEPTION 'IDENTITE-T5D: le passeport est resté vérifié après changement du prénom';
  END IF;

  -- La RPC atomique ne remplace jamais une date déjà renseignée et contraire.
  INSERT INTO public.soignants(id, prenom, nom, email, date_naissance, profession)
  VALUES (
    v_dob_mismatch, 'Alice', 'Durand',
    'identity-dob-' || v_dob_mismatch::text || '@test.local', DATE '1991-01-02', 'AS'
  );
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'role', 'service_role', 'sub', '00000000-0000-0000-0000-000000000000'
  )::text, true);
  v_result := public.fn_preparer_identite_document(
    v_dob_mismatch, DATE '1991-01-03', 'F', 'Paris'
  );
  IF COALESCE((v_result->>'date_naissance_correspond')::boolean, true) IS NOT FALSE
     OR v_result->>'error_code' <> 'DATE_NAISSANCE_INCOHERENTE' THEN
    RAISE EXCEPTION 'IDENTITE-T6: une date contradictoire a été acceptée: %', v_result;
  END IF;
  IF (SELECT date_naissance FROM public.soignants WHERE id = v_dob_mismatch) <> DATE '1991-01-02' THEN
    RAISE EXCEPTION 'IDENTITE-T7: la date du profil a été écrasée par le document';
  END IF;

  -- Simulation du trigger document imbriqué dans la cascade identité : le
  -- recalcul ne doit surtout pas vider la garde système posée par l'appelant.
  PERFORM set_config('jolene.system_update', 'true', true);
  PERFORM public.fn_recalculer_preuves_etudiant(v_as);
  IF current_setting('jolene.system_update', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'IDENTITE-T8: le recalcul imbriqué a perdu la garde système externe';
  END IF;
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);
END;
$test$;

ROLLBACK;

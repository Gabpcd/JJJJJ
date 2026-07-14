-- Heures externes P0 : tests transactionnels de propriété, CAS, provenance et
-- anti-cumul. Toutes les fixtures sont annulées par le ROLLBACK final.
\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_admin constant uuid := 'ee690000-0000-4000-8000-000000000001';
  v_soignant constant uuid := 'ee690000-0000-4000-8000-000000000002';
  v_path_1 constant text :=
    'ee690000-0000-4000-8000-000000000002/heures-externes/1720936800000_preuve-1.pdf';
  v_path_overlap constant text :=
    'ee690000-0000-4000-8000-000000000002/heures-externes/1720936800001_preuve-overlap.pdf';
  v_path_2 constant text :=
    'ee690000-0000-4000-8000-000000000002/heures-externes/1720936800002_preuve-2.pdf';
  v_hash constant text := repeat('a', 64);
  v_result jsonb;
  v_snapshot jsonb;
  v_id_1 uuid;
  v_id_2 uuid;
  v_failed boolean;
  v_compteur record;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixtures transactionnelles heures externes P0 69000',
    true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_admin,
      '00000000-0000-0000-0000-000000000000',
      'admin-heures-69000@test.local',
      'authenticated',
      'authenticated',
      '{"role":"ADMIN_PLATEFORME"}',
      now()
    ),
    (
      v_soignant,
      '00000000-0000-0000-0000-000000000000',
      'soignant-heures-69000@test.local',
      'authenticated',
      'authenticated',
      '{"role":"SOIGNANT"}',
      now()
    );

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin,
    'Heures',
    'Admin',
    'admin-heures-69000@test.local',
    true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, modifie_le
  ) VALUES (
    v_soignant,
    'Marie',
    'Lefevre',
    'soignant-heures-69000@test.local',
    'IDE',
    now()
  );
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);

  INSERT INTO storage.objects (
    id, bucket_id, name, owner_id, metadata
  ) VALUES
    (
      'ee690000-0000-4000-8000-000000000101',
      'jolene-documents', v_path_1, v_soignant::text,
      '{"size":1200,"mimetype":"application/pdf"}'::jsonb
    ),
    (
      'ee690000-0000-4000-8000-000000000102',
      'jolene-documents', v_path_overlap, v_soignant::text,
      '{"size":1200,"mimetype":"application/pdf"}'::jsonb
    ),
    (
      'ee690000-0000-4000-8000-000000000103',
      'jolene-documents', v_path_2, v_soignant::text,
      '{"size":1200,"mimetype":"application/pdf"}'::jsonb
    );

  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );

  -- Une URL déclarative sans objet exact possédé est refusée.
  v_result := public.fn_declarer_heures_externes_soignant(
    'CHU Test', 'HOPITAL_PUBLIC', DATE '2020-01-01', DATE '2020-12-31',
    1600,
    v_soignant::text || '/heures-externes/1720936800099_absente.pdf',
    'absente.pdf'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'PREUVE_STORAGE_INVALIDE' THEN
    RAISE EXCEPTION 'HEX-P0-T1 : preuve Storage absente acceptée : %', v_result;
  END IF;

  -- Même en simulant la ligne complète, un INSERT direct ne peut fournir le
  -- verdict ni les heures validées : le trigger serveur bloque tout le DML.
  v_failed := false;
  BEGIN
    INSERT INTO public.heures_externes_soignants (
      soignant_id, etablissement_nom, date_debut, date_fin,
      heures_declarees, attestation_url, statut_validation, valide_le
    ) VALUES (
      v_soignant, 'Injection', DATE '2018-01-01', DATE '2018-12-31',
      3200, v_path_1, 'VALIDE', now()
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF v_failed IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'HEX-P0-T2 : INSERT direct avec verdict accepté';
  END IF;

  v_result := public.fn_declarer_heures_externes_soignant(
    'CHU Test', 'HOPITAL_PUBLIC', DATE '2020-01-01', DATE '2020-12-31',
    1600, v_path_1, 'preuve-1.pdf'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'HEX-P0-T3 : déclaration propriétaire refusée : %', v_result;
  END IF;
  v_id_1 := (v_result->>'id')::uuid;

  IF NOT EXISTS (
    SELECT 1
    FROM public.heures_externes_soignants h
    WHERE h.id = v_id_1
      AND h.soignant_id = v_soignant
      AND h.statut_validation = 'EN_ATTENTE'
      AND h.valide_par IS NULL
      AND h.valide_le IS NULL
      AND h.heures_extraites_ia IS NULL
      AND h.source_validation_serveur IS NULL
      AND h.empreinte_preuve_sha256 IS NULL
  ) THEN
    RAISE EXCEPTION 'HEX-P0-T4 : la RPC n a pas forcé EN_ATTENTE/NULL';
  END IF;

  v_result := public.fn_declarer_heures_externes_soignant(
    'Clinique concurrente', 'CLINIQUE_PRIVEE',
    DATE '2020-06-01', DATE '2021-01-31', 1600,
    v_path_overlap, 'preuve-overlap.pdf'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'PERIODE_CHEVAUCHANTE' THEN
    RAISE EXCEPTION 'HEX-P0-T5 : période chevauchante acceptée : %', v_result;
  END IF;

  SELECT private.fn_snapshot_heures_externes(h)
  INTO v_snapshot
  FROM public.heures_externes_soignants h
  WHERE h.id = v_id_1;

  -- Le finaliseur n'est pas seulement caché par les GRANT : sa garde interne
  -- refuse également tout JWT utilisateur, même si la fonction est invoquée
  -- depuis un contexte SQL privilégié pendant ce test.
  v_failed := false;
  BEGIN
    PERFORM public.fn_service_finaliser_heures_externes(
      v_id_1, v_snapshot, v_hash, 'EN_ATTENTE', false,
      1600, true, '{"verdict":"VERIFIE"}'::jsonb,
      'Appel utilisateur interdit'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF v_failed IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'HEX-P0-T5B : un JWT utilisateur a appelé le finaliseur';
  END IF;

  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  v_failed := false;
  BEGIN
    PERFORM public.fn_service_finaliser_heures_externes(
      v_id_1, v_snapshot, v_hash, 'VALIDE', false,
      1600, true, '{"verdict":"VERIFIE"}'::jsonb, 'Auto valide interdit'
    );
  EXCEPTION WHEN invalid_parameter_value THEN
    v_failed := true;
  END;
  IF v_failed IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'HEX-P0-T6 : le finaliseur IA a accepté VALIDE';
  END IF;

  v_result := public.fn_service_finaliser_heures_externes(
    v_id_1, v_snapshot, v_hash, 'EN_ATTENTE', false,
    1600, true, '{"verdict":"VERIFIE"}'::jsonb,
    'Contrôles concordants, revue humaine requise.'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'statut' IS DISTINCT FROM 'EN_ATTENTE'
     OR NOT EXISTS (
       SELECT 1
       FROM public.heures_externes_soignants h
       WHERE h.id = v_id_1
         AND h.source_validation_serveur = 'IA_REVUE'
         AND h.empreinte_preuve_sha256 = v_hash
         AND h.statut_validation = 'EN_ATTENTE'
     ) THEN
    RAISE EXCEPTION 'HEX-P0-T7 : finalisation pending non atomique : %', v_result;
  END IF;

  -- Le snapshot périmé échoue fermé, même avec le bon service_role.
  v_result := public.fn_service_finaliser_heures_externes(
    v_id_1,
    jsonb_set(v_snapshot, '{heures_declarees}', '3200'::jsonb),
    v_hash, 'EN_ATTENTE', false, 1600, true,
    '{"verdict":"VERIFIE"}'::jsonb, 'Snapshot périmé'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'CONFLIT_SOURCE' THEN
    RAISE EXCEPTION 'HEX-P0-T8 : snapshot périmé accepté : %', v_result;
  END IF;

  -- AAL1 ne peut pas rendre une décision, même avec un compte admin enregistré.
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_failed := false;
  BEGIN
    PERFORM public.fn_admin_valider_heures_externes(
      v_id_1, 'VALIDE', 'Preuve examinée manuellement'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF v_failed IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'HEX-P0-T9 : un admin AAL1 a validé les heures';
  END IF;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  v_result := public.fn_admin_valider_heures_externes(
    v_id_1, 'VALIDE', 'Preuve examinée manuellement'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR NOT EXISTS (
       SELECT 1
       FROM public.heures_externes_soignants h
       WHERE h.id = v_id_1
         AND h.statut_validation = 'VALIDE'
         AND h.source_validation_serveur = 'ADMIN_AAL2'
         AND h.valide_par = v_admin
     ) THEN
    RAISE EXCEPTION 'HEX-P0-T10 : décision AAL2 refusée : %', v_result;
  END IF;

  -- Une copie binaire sur une autre période reste visible mais ne peut jamais
  -- être validée en plus de la première.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  v_result := public.fn_declarer_heures_externes_soignant(
    'CHU Test 2', 'HOPITAL_PUBLIC', DATE '2022-01-01', DATE '2022-12-31',
    1600, v_path_2, 'preuve-2.pdf'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'HEX-P0-T11 : seconde période légitime refusée : %', v_result;
  END IF;
  v_id_2 := (v_result->>'id')::uuid;
  SELECT private.fn_snapshot_heures_externes(h)
  INTO v_snapshot
  FROM public.heures_externes_soignants h
  WHERE h.id = v_id_2;

  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_result := public.fn_service_finaliser_heures_externes(
    v_id_2, v_snapshot, v_hash, 'EN_ATTENTE', false,
    1600, true, '{"verdict":"VERIFIE"}'::jsonb,
    'Copie binaire à revoir'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'preuve_dupliquee' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'HEX-P0-T12 : doublon binaire non détecté : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );
  v_result := public.fn_admin_valider_heures_externes(
    v_id_2, 'VALIDE', 'Tentative doublon'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'PREUVE_DUPLIQUEE' THEN
    RAISE EXCEPTION 'HEX-P0-T13 : doublon binaire validé : %', v_result;
  END IF;

  -- Le compteur n'additionne que la ligne avec provenance admin et snapshot
  -- courant ; la copie pending ne peut donc pas gonfler le seuil de 3 200 h.
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_soignant, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  SELECT * INTO v_compteur
  FROM public.fn_compteur_heures_soignant(v_soignant);
  IF v_compteur.heures_externes_validees IS DISTINCT FROM 1600
     OR v_compteur.heures_totales IS DISTINCT FROM 1600
     OR v_compteur.eligible_free_transition IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'HEX-P0-T14 : compteur gonflé ou provenance ignorée : %',
      row_to_json(v_compteur);
  END IF;

  v_failed := false;
  BEGIN
    UPDATE public.heures_externes_soignants
    SET heures_declarees = 3200,
        statut_validation = 'VALIDE'
    WHERE id = v_id_2;
  EXCEPTION WHEN insufficient_privilege THEN
    v_failed := true;
  END;
  IF v_failed IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'HEX-P0-T15 : UPDATE direct des heures/verdict accepté';
  END IF;

  IF NOT EXISTS (
       SELECT 1 FROM public.journaux_audit
       WHERE id_ressource = v_id_1
         AND action = 'HEURES_EXTERNES_DECLAREES'
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.journaux_audit
       WHERE id_ressource = v_id_1
         AND action = 'VERIFICATION_DOCUMENT'
         AND details->>'sous_action' = 'HEURES_EXTERNES_VERIFICATION_AUTO'
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.journaux_audit
       WHERE id_ressource = v_id_1
         AND action = 'HEURES_EXTERNES_VALIDATION_MANUELLE'
     ) THEN
    RAISE EXCEPTION 'HEX-P0-T16 : audit obligatoire absent';
  END IF;
END;
$test$;

ROLLBACK;

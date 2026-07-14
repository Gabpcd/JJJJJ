-- Régressions des fonctions signalées par `supabase db lint --linked`.
-- Prérequis : migration 20260714003439 appliquée.
-- Lecture catalogue + appels sans identité uniquement ; aucune donnée métier.

\set ON_ERROR_STOP on
BEGIN;

DO $catalogue$
DECLARE
  v_bad text;
  v_count integer;
  v_definition text;
BEGIN
  SELECT count(*)
    INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.oid = ANY(ARRAY[
       'public.fn_verifier_coherence_documents(uuid)'::regprocedure,
       'public.fn_annuler_mission_etab(uuid,text,text)'::regprocedure,
       'public.fn_valider_presences_lot(uuid[])'::regprocedure,
       'public.fn_modifier_tolerance_pointage_etab(integer)'::regprocedure,
       'public.fn_cloturer_litige(uuid,text)'::regprocedure,
       'public.fn_cloturer_litige_avec_payload(uuid,jsonb)'::regprocedure,
       'public.fn_trg_litige_accord_mutuel()'::regprocedure,
       'public.fn_trg_litige_gel_degel_facture()'::regprocedure,
       'public.fn_admin_resoudre_alerte(uuid)'::regprocedure,
       'public.fn_detecter_teleportations()'::regprocedure,
       'public.fn_escalade_remplacement_non_pourvu()'::regprocedure,
       'public.fn_alerte_reclamations_pending_old()'::regprocedure
     ]::oid[])
     AND p.prosecdef
     AND p.proconfig @> ARRAY['search_path=public']::text[];
  IF v_count IS DISTINCT FROM 12 THEN
    RAISE EXCEPTION 'Runtime lint: une signature ou un search_path a changé (%/12)', v_count;
  END IF;

  -- Le contact qualifie désormais toutes ses dépendances et conserve donc le
  -- search_path vide, plus strict que l'ancien "public, extensions".
  SELECT count(*)
    INTO v_count
    FROM pg_proc p
   WHERE p.oid = 'public.fn_envoyer_message_contact(text,text,text)'::regprocedure
     AND p.prosecdef
     AND p.proconfig
       && ARRAY['search_path=', 'search_path=""']::text[];
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'Runtime lint: SECURITY DEFINER/search_path du contact altéré';
  END IF;

  -- Le protector a volontairement search_path=pg_catalog, public.
  SELECT count(*)
    INTO v_count
    FROM pg_proc p
   WHERE p.oid = 'public.fn_protect_etablissement_commercial()'::regprocedure
     AND p.prosecdef
     AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[];
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'Runtime lint: SECURITY DEFINER/search_path du protector altéré';
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ')
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = ANY(ARRAY[
       'fn_verifier_coherence_documents',
       'fn_annuler_mission_etab',
       'fn_valider_presences_lot',
       'fn_modifier_tolerance_pointage_etab',
       'fn_cloturer_litige',
       'fn_cloturer_litige_avec_payload',
       'fn_admin_resoudre_alerte',
       'fn_envoyer_message_contact',
       'fn_detecter_teleportations',
       'fn_escalade_remplacement_non_pourvu',
       'fn_alerte_reclamations_pending_old'
     ])
     AND (
       p.prosrc LIKE '%v_mission.type_contrat::text%'
       OR p.prosrc LIKE '%DELETE FROM _validees_lot%'
       OR p.prosrc LIKE '%mis_a_jour_le = now()%'
       OR p.prosrc LIKE '%resolu_par = ''ADMIN''%'
       OR p.prosrc LIKE '%resolu_par = ''ACCORD_MUTUEL''%'
       OR p.prosrc LIKE '%ARRAY(SELECT id FROM public.fn_list_admin_user_ids())%'
       OR p.prosrc LIKE '%v_problemes || ''Un ou plusieurs documents%'
     );
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Runtime lint: fragments invalides présents dans %', v_bad;
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_protect_etablissement_commercial()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'OLD[.]statut_verification = ''VERIFIE''')
       IS DISTINCT FROM true
     OR (v_definition ~ 'NEW[.]statut_verification = ''EN_COURS''')
       IS DISTINCT FROM true
     OR (v_definition ~ 'NEW[.]peut_publier_missions IS FALSE')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: rétrogradation canonique établissement non admise';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_valider_presences_lot(uuid[])'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_a_permission_etablissement[(]''pointage'', v_etab_id[)] IS NOT TRUE')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: permission pointage absente de la validation par lot';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_modifier_tolerance_pointage_etab(integer)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_a_permission_etablissement[(]''profil_etab'', v_etab_id[)] IS NOT TRUE')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: permission profil_etab absente de la tolérance GPS';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_cloturer_litige(uuid,text)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_compte_auth_actif[(][)] IS NOT TRUE')
       IS DISTINCT FROM true
     OR COALESCE(regexp_count(v_definition, '''contrats'''), 0) < 3
     OR (v_definition ~ '''CLOTURE''') IS DISTINCT FROM false
     OR (v_definition ~ '''RESOLU_ADMIN''') IS DISTINCT FROM true
     OR (v_definition ~ '''RESOLU_ACCORD_PARTIES''') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: garde/statuts de clôture litige non canoniques';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_cloturer_litige_avec_payload(uuid,jsonb)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_compte_auth_actif[(][)] IS NOT TRUE')
       IS DISTINCT FROM true
     OR (v_definition ~ '''contrats''') IS DISTINCT FROM true
     OR (v_definition ~ 'FOR UPDATE') IS DISTINCT FROM true
     OR (v_definition ~ 'p_payload IS DISTINCT FROM v_litige[.]payload_modifications')
       IS DISTINCT FROM true
     OR (v_definition ~ 'statut = ''RESOLU''') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Runtime lint: consentement payload non transactionnel';
  END IF;

  IF (v_definition ~ 'MODIFICATION_HORAIRES') IS DISTINCT FROM true
     OR (v_definition ~ 'ACCORD_SANS_MODIFICATION') IS DISTINCT FROM true
     OR (v_definition ~ 'Schéma de proposition invalide') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: schéma du payload non borné';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_confirmer_accord_partie(uuid)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_cloturer_litige[(]p_litige_id, NULL[)]')
       IS DISTINCT FROM true
     OR (v_definition ~ 'UPDATE[[:space:]]+(public[.])?litiges')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Runtime lint: confirmation legacy hors chemin canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_proposer_accord_partie(uuid)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_compte_auth_actif[(][)] IS NOT TRUE')
       IS DISTINCT FROM true
     OR (v_definition ~ '''contrats''') IS DISTINCT FROM true
     OR (v_definition ~ 'FOR UPDATE') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: proposition de médiation non verrouillée';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_trg_litige_gel_degel_facture()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ '''RESOLU''') IS DISTINCT FROM false
     OR (v_definition ~ '''CLOTURE''') IS DISTINCT FROM false
     OR (v_definition ~ '''CONTESTEE''') IS DISTINCT FROM false
     OR (v_definition ~ '''RESOLU_ACCORD_PARTIES''') IS DISTINCT FROM true
     OR (v_definition ~ '''RESOLU_FAVEUR_SOIGNANT''') IS DISTINCT FROM true
     OR (v_definition ~ '''RESOLU_FAVEUR_ETAB''') IS DISTINCT FROM true
     OR (v_definition ~ '''RESOLU_PARTAGE''') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: statuts de dégel facture non canoniques';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.fn_alerte_reclamations_pending_old()',
    'EXECUTE'
  ) IS DISTINCT FROM false
  OR has_function_privilege(
    'authenticated',
    'public.fn_detecter_teleportations()',
    'EXECUTE'
  ) IS DISTINCT FROM false
  OR has_function_privilege(
    'authenticated',
    'public.fn_escalade_remplacement_non_pourvu()',
    'EXECUTE'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Runtime lint: ACL service_role-only élargie';
  END IF;

  IF has_table_privilege('anon', 'public.litiges', 'UPDATE')
       IS DISTINCT FROM false
     OR has_table_privilege('authenticated', 'public.litiges', 'UPDATE')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Runtime lint: UPDATE direct des litiges encore exposé';
  END IF;

  -- Le seul consommateur frontend appelle la cohérence sans argument : on
  -- conserve EXECUTE à authenticated, le garde anti-BOLA assurant le self-only.
  IF has_function_privilege(
    'authenticated',
    'public.fn_verifier_coherence_documents(uuid)',
    'EXECUTE'
  ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Runtime lint: flux documentaire frontend privé de son RPC';
  END IF;
END;
$catalogue$;

DO $runtime_sans_identite$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  BEGIN
    PERFORM public.fn_verifier_coherence_documents(
      'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid
    );
    RAISE EXCEPTION 'Runtime lint: accès documentaire anonyme accepté';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  v_result := public.fn_valider_presences_lot(ARRAY[]::uuid[]);
  IF v_result->>'error' IS DISTINCT FROM 'Non autorisé' THEN
    RAISE EXCEPTION 'Runtime lint: garde présences inattendue: %', v_result;
  END IF;

  v_result := public.fn_modifier_tolerance_pointage_etab(100);
  IF v_result->>'error_code' IS DISTINCT FROM 'NON_AUTHENTIFIE' THEN
    RAISE EXCEPTION 'Runtime lint: garde tolérance inattendue: %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
    NULL
  );
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'Runtime lint: garde litige inattendue: %', v_result;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.fn_list_admin_user_ids() AS admins(admin_user_id)
     WHERE admin_user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Runtime lint: source admin SETOF uuid mal typée';
  END IF;
END;
$runtime_sans_identite$;

DO $runtime_anti_bola$
DECLARE
  v_uid uuid := '11111111-1111-4111-8111-111111111111'::uuid;
  v_banned_uid uuid := '11111111-1111-4111-8111-111111111112'::uuid;
  v_deleted_uid uuid := '11111111-1111-4111-8111-111111111113'::uuid;
  v_tiers_uid uuid := '11111111-1111-4111-8111-111111111114'::uuid;
  v_etab_tiers uuid := '11111111-1111-4111-8111-111111111115'::uuid;
  v_mission_tiers uuid := '11111111-1111-4111-8111-111111111116'::uuid;
  v_litige_tiers uuid := '11111111-1111-4111-8111-111111111117'::uuid;
  v_cible uuid := '22222222-2222-4222-8222-222222222222'::uuid;
  v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('app.internal_operation', '', true);
  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixtures transactionnelles runtime anti-BOLA litige tiers',
    true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data,
    email_confirmed_at, banned_until, deleted_at
  ) VALUES
    (v_uid, '00000000-0000-0000-0000-000000000000',
     'runtime-active@test.local', 'authenticated', 'authenticated',
     '{"role":"SOIGNANT"}', now(), NULL, NULL),
    (v_banned_uid, '00000000-0000-0000-0000-000000000000',
     'runtime-banned@test.local', 'authenticated', 'authenticated',
     '{"role":"SOIGNANT"}', now(), now() + interval '1 day', NULL),
    (v_deleted_uid, '00000000-0000-0000-0000-000000000000',
     'runtime-deleted@test.local', 'authenticated', 'authenticated',
     '{"role":"SOIGNANT"}', now(), NULL, now()),
    (v_tiers_uid, '00000000-0000-0000-0000-000000000000',
     'runtime-tiers@test.local', 'authenticated', 'authenticated',
     '{"role":"SOIGNANT"}', now(), NULL, NULL);

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_compte_test
  ) VALUES (
    v_etab_tiers, 'Fixture runtime anti-BOLA', '99140000000501',
    'CLINIQUE_PRIVEE', '6 rue du Test', 'Paris', '75006',
    'runtime-etablissement-tiers@test.local', true
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, est_compte_test
  ) VALUES (
    v_tiers_uid, 'Runtime', 'Tiers',
    'runtime-tiers@test.local', 'IDE', true
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, type_contrat_recherche, mode_attribution
  ) VALUES (
    v_mission_tiers, v_etab_tiers, 'Fixture runtime litige tiers', 'IDE',
    now() + interval '20 years', now() + interval '20 years 8 hours',
    8, 20, 'OUVERTE', 'SALARIE', 'CANDIDATURE'
  );

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id,
    initie_par, motif, type_litige, statut
  ) VALUES (
    v_litige_tiers, v_mission_tiers, v_tiers_uid, v_etab_tiers,
    'SYSTEME', 'Fixture autonome de non-divulgation anti-BOLA',
    'COMPORTEMENT_SOIGNANT', 'OUVERT'
  );

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);

  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_uid,
      'role', 'authenticated',
      'aal', 'aal1'
    )::text,
    true
  );

  -- Le flux frontend sans argument reste autorisé pour son propre dossier.
  v_result := public.fn_verifier_coherence_documents(NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Soignant introuvable' THEN
    RAISE EXCEPTION 'Runtime lint: appel documentaire self inattendu: %', v_result;
  END IF;

  BEGIN
    PERFORM public.fn_verifier_coherence_documents(v_cible);
    RAISE EXCEPTION 'Runtime lint: BOLA documentaire acceptée';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Un utilisateur non lié ne doit jamais distinguer un UUID tiers absent du
  -- litige autonome existant, quel que soit son statut interne.
  v_result := public.fn_cloturer_litige(v_litige_tiers, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Litige introuvable ou accès refusé' THEN
    RAISE EXCEPTION 'Runtime lint: fuite de statut du litige tiers: %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_banned_uid::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_banned_uid, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM public.fn_verifier_coherence_documents(NULL);
    RAISE EXCEPTION 'Runtime lint: compte banni accepté sur documents';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
  v_result := public.fn_cloturer_litige(v_cible, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'Runtime lint: compte banni accepté sur litige: %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_cible,
    '{"type":"ACCORD_SANS_MODIFICATION","modifications":{},"justification":"Test compte banni"}'::jsonb
  );
  IF v_result->>'error' IS DISTINCT FROM 'Non authentifié' THEN
    RAISE EXCEPTION 'Runtime lint: compte banni accepté sur payload litige: %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_deleted_uid::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_deleted_uid, 'role', 'authenticated', 'aal', 'aal1'
    )::text,
    true
  );
  BEGIN
    PERFORM public.fn_verifier_coherence_documents(NULL);
    RAISE EXCEPTION 'Runtime lint: compte supprimé accepté sur documents';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
  v_result := public.fn_cloturer_litige(v_cible, NULL);
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'Runtime lint: compte supprimé accepté sur litige: %', v_result;
  END IF;
END;
$runtime_anti_bola$;

ROLLBACK;

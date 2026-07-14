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
  IF v_count <> 12 THEN
    RAISE EXCEPTION 'Runtime lint: une signature ou un search_path a changé (%/12)', v_count;
  END IF;

  -- Le contact utilise aussi net/http et conserve extensions dans son path.
  SELECT count(*)
    INTO v_count
    FROM pg_proc p
   WHERE p.oid = 'public.fn_envoyer_message_contact(text,text,text)'::regprocedure
     AND p.prosecdef
     AND p.proconfig @> ARRAY['search_path=public, extensions']::text[];
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Runtime lint: SECURITY DEFINER/search_path du contact altéré';
  END IF;

  -- Le protector a volontairement search_path=pg_catalog, public.
  SELECT count(*)
    INTO v_count
    FROM pg_proc p
   WHERE p.oid = 'public.fn_protect_etablissement_commercial()'::regprocedure
     AND p.prosecdef
     AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[];
  IF v_count <> 1 THEN
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
  IF v_definition !~ 'OLD[.]statut_verification = ''VERIFIE'''
     OR v_definition !~ 'NEW[.]statut_verification = ''EN_COURS'''
     OR v_definition !~ 'NEW[.]peut_publier_missions IS FALSE' THEN
    RAISE EXCEPTION 'Runtime lint: rétrogradation canonique établissement non admise';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_valider_presences_lot(uuid[])'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_a_permission_etablissement[(]''pointage'', v_etab_id[)] IS NOT TRUE' THEN
    RAISE EXCEPTION 'Runtime lint: permission pointage absente de la validation par lot';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_modifier_tolerance_pointage_etab(integer)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_a_permission_etablissement[(]''profil_etab'', v_etab_id[)] IS NOT TRUE' THEN
    RAISE EXCEPTION 'Runtime lint: permission profil_etab absente de la tolérance GPS';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_cloturer_litige(uuid,text)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_compte_auth_actif[(][)] IS NOT TRUE'
     OR regexp_count(v_definition, '''contrats''') < 3
     OR v_definition ~ '''CLOTURE'''
     OR v_definition !~ '''RESOLU_ADMIN'''
     OR v_definition !~ '''RESOLU_ACCORD_PARTIES''' THEN
    RAISE EXCEPTION 'Runtime lint: garde/statuts de clôture litige non canoniques';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_cloturer_litige_avec_payload(uuid,jsonb)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_compte_auth_actif[(][)] IS NOT TRUE'
     OR v_definition !~ '''contrats'''
     OR v_definition !~ 'FOR UPDATE'
     OR v_definition !~ 'p_payload IS DISTINCT FROM v_litige[.]payload_modifications'
     OR v_definition ~ 'statut = ''RESOLU''' THEN
    RAISE EXCEPTION 'Runtime lint: consentement payload non transactionnel';
  END IF;

  IF v_definition !~ 'MODIFICATION_HORAIRES'
     OR v_definition !~ 'ACCORD_SANS_MODIFICATION'
     OR v_definition !~ 'Schéma de proposition invalide' THEN
    RAISE EXCEPTION 'Runtime lint: schéma du payload non borné';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_confirmer_accord_partie(uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_cloturer_litige[(]p_litige_id, NULL[)]'
     OR v_definition ~ 'UPDATE[[:space:]]+(public[.])?litiges' THEN
    RAISE EXCEPTION 'Runtime lint: confirmation legacy hors chemin canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_proposer_accord_partie(uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition !~ 'fn_compte_auth_actif[(][)] IS NOT TRUE'
     OR v_definition !~ '''contrats'''
     OR v_definition !~ 'FOR UPDATE' THEN
    RAISE EXCEPTION 'Runtime lint: proposition de médiation non verrouillée';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_trg_litige_gel_degel_facture()'::regprocedure
  ) INTO v_definition;
  IF v_definition ~ '''RESOLU'''
     OR v_definition ~ '''CLOTURE'''
     OR v_definition ~ '''CONTESTEE'''
     OR v_definition !~ '''RESOLU_ACCORD_PARTIES'''
     OR v_definition !~ '''RESOLU_FAVEUR_SOIGNANT'''
     OR v_definition !~ '''RESOLU_FAVEUR_ETAB'''
     OR v_definition !~ '''RESOLU_PARTAGE''' THEN
    RAISE EXCEPTION 'Runtime lint: statuts de dégel facture non canoniques';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.fn_alerte_reclamations_pending_old()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.fn_detecter_teleportations()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.fn_escalade_remplacement_non_pourvu()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Runtime lint: ACL service_role-only élargie';
  END IF;

  IF has_table_privilege('anon', 'public.litiges', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.litiges', 'UPDATE') THEN
    RAISE EXCEPTION 'Runtime lint: UPDATE direct des litiges encore exposé';
  END IF;

  -- Le seul consommateur frontend appelle la cohérence sans argument : on
  -- conserve EXECUTE à authenticated, le garde anti-BOLA assurant le self-only.
  IF NOT has_function_privilege(
    'authenticated',
    'public.fn_verifier_coherence_documents(uuid)',
    'EXECUTE'
  ) THEN
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
  IF v_result->>'error' <> 'Non autorisé' THEN
    RAISE EXCEPTION 'Runtime lint: garde présences inattendue: %', v_result;
  END IF;

  v_result := public.fn_modifier_tolerance_pointage_etab(100);
  IF v_result->>'error_code' <> 'NON_AUTHENTIFIE' THEN
    RAISE EXCEPTION 'Runtime lint: garde tolérance inattendue: %', v_result;
  END IF;

  v_result := public.fn_cloturer_litige(
    'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid,
    NULL
  );
  IF v_result->>'error' <> 'Accès refusé' THEN
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
  v_cible uuid := '22222222-2222-4222-8222-222222222222'::uuid;
  v_litige_tiers uuid;
  v_result jsonb;
BEGIN
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
     '{"role":"SOIGNANT"}', now(), NULL, now());

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
  IF v_result->>'error' <> 'Soignant introuvable' THEN
    RAISE EXCEPTION 'Runtime lint: appel documentaire self inattendu: %', v_result;
  END IF;

  BEGIN
    PERFORM public.fn_verifier_coherence_documents(v_cible);
    RAISE EXCEPTION 'Runtime lint: BOLA documentaire acceptée';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  -- Si la base contient un litige, un utilisateur synthétique non lié ne doit
  -- jamais distinguer un UUID tiers absent d'un litige existant/clôturé.
  SELECT l.id
    INTO v_litige_tiers
    FROM public.litiges l
   WHERE l.soignant_id IS DISTINCT FROM v_uid
   LIMIT 1;

  IF v_litige_tiers IS NOT NULL THEN
    v_result := public.fn_cloturer_litige(v_litige_tiers, NULL);
    IF v_result->>'error' <> 'Litige introuvable ou accès refusé' THEN
      RAISE EXCEPTION 'Runtime lint: fuite de statut du litige tiers: %', v_result;
    END IF;
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
  IF v_result->>'error' <> 'Accès refusé' THEN
    RAISE EXCEPTION 'Runtime lint: compte banni accepté sur litige: %', v_result;
  END IF;
  v_result := public.fn_cloturer_litige_avec_payload(
    v_cible,
    '{"type":"ACCORD_SANS_MODIFICATION","modifications":{},"justification":"Test compte banni"}'::jsonb
  );
  IF v_result->>'error' <> 'Non authentifié' THEN
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
  IF v_result->>'error' <> 'Accès refusé' THEN
    RAISE EXCEPTION 'Runtime lint: compte supprimé accepté sur litige: %', v_result;
  END IF;
END;
$runtime_anti_bola$;

ROLLBACK;

-- Tests adversariaux P0 securite (a executer sur une base locale migree).
-- Tout est transactionnel et rollbacke, aucune donnee demo n'est modifiee.
BEGIN;

DO $catalogue$
DECLARE
  v_policy text;
  v_definition text;
BEGIN
  IF has_function_privilege(
       'authenticated', 'public.fn_purger_demo()', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: authenticated peut encore executer fn_purger_demo';
  END IF;
  IF has_function_privilege(
       'authenticated', 'public.fn_admin_invocations_purge()', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: authenticated peut encore purger admin_invocations';
  END IF;
  IF has_function_privilege(
       'authenticated', 'public.fn_purger_gps_ancien()', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: authenticated peut encore purger les traces GPS';
  END IF;
  IF has_function_privilege(
       'service_role', 'public.fn_purger_gps_ancien()', 'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: le cron service_role ne peut plus purger les traces GPS';
  END IF;
  IF has_table_privilege(
       'authenticated', 'public.api_keys', 'SELECT'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: api_keys reste lisible directement';
  END IF;
  IF has_function_privilege(
       'authenticated', 'public.fn_verifier_api_key(text,text)', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: verifier_api_key doit rester service_role-only';
  END IF;
  IF has_function_privilege(
       'authenticated', 'public.fn_lister_api_keys(uuid)', 'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: listing API sur projection sure inaccessible';
  END IF;
  IF has_function_privilege(
       'authenticated', 'public.fn_supprimer_mes_tokens_push()', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: ancien logout peut encore supprimer tous les tokens push';
  END IF;
  IF has_function_privilege(
       'authenticated', 'public.fn_desactiver_mon_token_push(text)', 'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: logout appareil courant inaccessible';
  END IF;
  IF has_table_privilege('authenticated', 'public.types_comptes_auth', 'SELECT')
       IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated',
       'public.fn_reserver_type_compte(uuid,text,uuid)',
       'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: reservation de famille de compte exposee au client';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.membres_etablissement'::regclass
      AND tgname = 'trg_protect_famille_compte_membre_etablissement'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'P0: une invitation peut encore croiser les familles de compte';
  END IF;
  IF has_column_privilege('authenticated', 'public.soignants', 'score_fiabilite', 'UPDATE')
       IS DISTINCT FROM false
     OR has_column_privilege('authenticated', 'public.soignants', 'rpps_verifie', 'UPDATE')
       IS DISTINCT FROM false
     OR has_column_privilege('authenticated', 'public.soignants', 'stripe_account_id', 'UPDATE')
       IS DISTINCT FROM false
     OR has_column_privilege('authenticated', 'public.soignants', 'est_compte_test', 'UPDATE')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: une colonne soignant serveur reste modifiable directement';
  END IF;
  IF has_column_privilege(
       'authenticated', 'public.soignants', 'sms_actif', 'UPDATE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: les preferences soignant legitimes ne sont plus modifiables';
  END IF;
  IF has_column_privilege('authenticated', 'public.etablissements', 'peut_publier_missions', 'UPDATE')
       IS DISTINCT FROM false
     OR has_column_privilege('authenticated', 'public.etablissements', 'siret_verifie', 'UPDATE')
       IS DISTINCT FROM false
     OR has_column_privilege('authenticated', 'public.etablissements', 'stripe_customer_id', 'UPDATE')
       IS DISTINCT FROM false
     OR has_column_privilege('authenticated', 'public.etablissements', 'est_compte_test', 'UPDATE')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: une colonne etablissement serveur reste modifiable directement';
  END IF;
  IF has_column_privilege(
       'authenticated', 'public.etablissements', 'sms_actif', 'UPDATE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: les preferences etablissement legitimes ne sont plus modifiables';
  END IF;

  SELECT pg_get_expr(p.polqual, p.polrelid) INTO v_policy
  FROM pg_policy p
  WHERE p.polrelid = 'public.soignants'::regclass AND p.polname = 'pol_soig_select';
  IF v_policy IS NULL OR v_policy !~ 'auth.uid' OR v_policy ~ '(missions|candidatures)' THEN
    RAISE EXCEPTION 'P0: pol_soig_select autorise encore une relation etablissement: %', v_policy;
  END IF;

  IF to_regclass('public.vue_soignants_etablissement') IS NOT NULL
     OR to_regclass('public.vue_etablissements_soignant') IS NOT NULL THEN
    RAISE EXCEPTION 'P0: une vue SECURITY DEFINER de partage reste exposee';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.fn_interlocuteurs_conversations(uuid[])',
    'EXECUTE'
  ) IS DISTINCT FROM true
  OR has_function_privilege(
    'anon',
    'public.fn_interlocuteurs_conversations(uuid[])',
    'EXECUTE'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: ACL invalide sur la projection des interlocuteurs de messagerie';
  END IF;
  SELECT pg_get_functiondef(
    'public.fn_interlocuteurs_conversations(uuid[])'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'participant_1_id = v_uid') IS DISTINCT FROM true
     OR (v_definition ~ 'participant_2_id = v_uid') IS DISTINCT FROM true
     OR (v_definition ~ 'fn_compte_auth_actif') IS DISTINCT FROM true
     OR (v_definition ~ 'cardinality\(p_conversation_ids\) > 100') IS DISTINCT FROM true
     OR (v_definition ~* '(email_contact|telephone_contact|numero_rpps|stripe_)')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: projection interlocuteurs trop large ou non bornee';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'soignants'
      AND p.polname = 'pol_compte_auth_actif_restrictive'
      AND p.polpermissive = false
  ) THEN
    RAISE EXCEPTION 'P0: policy restrictive compte actif absente';
  END IF;

  SELECT pg_get_functiondef('public.fn_purger_gps_ancien()'::regprocedure)
  INTO v_definition;
  IF (v_definition ~* '90 days') IS DISTINCT FROM true
     OR (v_definition ~ 'arrivee_ip = NULL') IS DISTINCT FROM true
     OR (v_definition ~ 'depart_ip = NULL') IS DISTINCT FROM true
     OR (v_definition ~ 'arrivee_id_terminal = NULL') IS DISTINCT FROM true
     OR (v_definition ~ 'depart_modele_terminal = NULL') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: purge GPS incomplete ou retention differente de 90 jours';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_verifier_rate_limit(text,text,integer,integer)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'pg_advisory_xact_lock') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: rate-limit distribue non serialise';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tokens_push'::regclass
      AND conname = 'tokens_push_token_key'
      AND contype = 'u'
  ) OR EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tokens_push'::regclass
      AND conname = 'tokens_push_utilisateur_id_token_key'
  ) THEN
    RAISE EXCEPTION 'P0: unicite globale du token push non appliquee';
  END IF;
  SELECT pg_get_functiondef('public.fn_upsert_token_push(text,text)'::regprocedure)
  INTO v_definition;
  IF (v_definition ~ 'ON CONFLICT \(token\)') IS DISTINCT FROM true
     OR (v_definition ~ 'fn_compte_auth_actif') IS DISTINCT FROM true
     OR (v_definition ~ 'utilisateur_id = EXCLUDED.utilisateur_id') IS DISTINCT FROM true
     OR (v_definition ~ 'push[.]services[.]mozilla') IS DISTINCT FROM true
     OR (v_definition ~ 'v_endpoint !~ ''\^https://''') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: upsert push ne reaffecte pas surement un appareil';
  END IF;
  SELECT pg_get_functiondef('public.fn_desactiver_mon_token_push(text)'::regprocedure)
  INTO v_definition;
  IF (v_definition ~ 'utilisateur_id = v_uid') IS DISTINCT FROM true
     OR (v_definition ~ 'scope.*CURRENT_DEVICE') IS DISTINCT FROM true
     OR (v_definition ~* 'DELETE FROM') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: logout push non limite a l appareil courant';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.journaux_audit'::regclass
      AND tgname = 'trg_mirror_teleportation_alerte_systeme'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'P0: miroir teleportation vers alertes_systeme absent';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.missions'::regclass
      AND tgname = 'trg_p0_rbac_missions'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.membres_etablissement'::regclass
      AND tgname = 'trg_p0_rbac_membres_etablissement'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'P0: garde RBAC des RPC SECURITY DEFINER absent';
  END IF;
  SELECT pg_get_functiondef(
    'public.fn_enforce_etablissement_rbac_trigger()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_a_permission_etablissement') IS DISTINCT FROM true
     OR (v_definition ~ 'fn_role_etablissement_courant') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: garde RBAC trigger incomplet';
  END IF;
  SELECT pg_get_functiondef(
    'public.fn_admin_traiter_alerte_pointage(uuid,text,text)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'ADMIN_SUSPENSION_REVIEW') IS DISTINCT FROM true
     OR (v_definition ~ 'SUSPENSION_REVIEW_CREATED') IS DISTINCT FROM true
     OR (v_definition ~ 'automatic_suspension') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: proposition suspension sans effet tracable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.prosrc LIKE '%https://app.jolene.app%'
  ) THEN
    RAISE EXCEPTION 'P0: une fonction DB emet encore un Universal Link via app.jolene.app';
  END IF;
END;
$catalogue$;

DO $admin_aal$
DECLARE
  v_admin uuid := 'ffffffff-1111-4000-8000-000000000001';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES (
    v_admin, '00000000-0000-0000-0000-000000000000', 'p0-admin@test.local',
    'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now()
  );
  INSERT INTO public.equipe_admin(user_id, nom, prenom, email, actif, acces_groupes)
  VALUES (
    v_admin,
    'P0',
    'Admin',
    'p0-admin@test.local',
    true,
    ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[]
  );

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  IF public.est_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: admin aal1 accepte';
  END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF public.est_admin() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'P0: admin actif aal2 refuse';
  END IF;

  UPDATE public.equipe_admin SET actif = false WHERE user_id = v_admin;
  IF public.est_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: admin equipe_admin inactif accepte';
  END IF;
END;
$admin_aal$;

DO $membre_revoque$
DECLARE
  v_user uuid := 'ffffffff-1111-4000-8000-000000000002';
  v_etab uuid := 'ffffffff-1111-4000-8000-000000000003';
BEGIN
  INSERT INTO auth.users(id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
  VALUES (v_user, '00000000-0000-0000-0000-000000000000', 'p0-membre@test.local',
          'authenticated', 'authenticated', '{"role":"ETABLISSEMENT"}', now());
  INSERT INTO public.etablissements(
    id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal,
    email_contact, est_compte_test
  ) VALUES (
    v_etab, 'P0 Etablissement', '99999999999991', 'CLINIQUE_PRIVEE',
    '1 rue P0', 'Paris', '75001', 'p0-etab@test.local', true
  );
  INSERT INTO public.membres_etablissement(etablissement_id, user_id, role, actif)
  VALUES (v_etab, v_user, 'LECTURE_SEULE', true);

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  IF public.mon_etablissement_id() IS DISTINCT FROM v_etab THEN
    RAISE EXCEPTION 'P0: membre actif non reconnu';
  END IF;
  IF public.fn_a_permission_etablissement('missions', v_etab)
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'P0: LECTURE_SEULE peut muter les missions';
  END IF;

  UPDATE public.membres_etablissement SET actif = false WHERE user_id = v_user;
  IF public.mon_etablissement_id() IS NOT NULL THEN
    RAISE EXCEPTION 'P0: membre revoque conserve mon_etablissement_id';
  END IF;
END;
$membre_revoque$;

ROLLBACK;

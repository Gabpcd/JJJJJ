-- Régressions du solde PL/pgSQL pré-lancement.
-- Prérequis : migrations jusqu'à 20260714073000 appliquées.

\set ON_ERROR_STOP on
BEGIN;

CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;

CREATE TEMP TABLE jolene_lint_residuel_issues ON COMMIT DROP AS
WITH signatures(signature) AS (
  VALUES
    ('public.fn_admin_bfa_detail_groupe(uuid,integer)'),
    ('public.fn_admin_lever_suspension(uuid,text)'),
    ('public.fn_admin_reset_test_account(text)'),
    ('public.fn_annuler_mission(uuid,text)'),
    ('public.fn_annuler_mission_etab(uuid,text,text)'),
    ('public.fn_annuler_mission_etablissement(uuid,text)'),
    ('public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'),
    ('public.fn_calculer_remuneration_mission(timestamp with time zone,timestamp with time zone,numeric,uuid,uuid)'),
    ('public.fn_calculer_score_soignant(uuid)'),
    ('public.fn_charger_demo_investisseur()'),
    ('public.fn_commission_info_etablissement()'),
    ('public.fn_creer_serie(text,text,type_profession,text,numeric,boolean,integer,jsonb)'),
    ('public.fn_email_factures_impayees()'),
    ('public.fn_envoyer_rappels_notation_j1()'),
    ('public.fn_modifier_preferences_notifications(boolean,boolean,boolean,boolean,jsonb)'),
    ('public.fn_parrainage_verifier_seuils(uuid)'),
    ('public.fn_souscrire_prevoyance(uuid,text)'),
    ('private.fn_admin_creer_compte_employe_interne_lancement(text,text,text,text,text,numeric,text[])')
)
SELECT
  s.signature,
  c.level,
  c.sqlstate,
  c.message,
  c.lineno
FROM signatures s
CROSS JOIN LATERAL extensions.plpgsql_check_function_tb(
  s.signature::regprocedure,
  fatal_errors => false
) c
WHERE c.level IN ('error', 'warning');

DO $lint$
BEGIN
  IF EXISTS (SELECT 1 FROM jolene_lint_residuel_issues) THEN
    RAISE EXCEPTION 'Lint PL/pgSQL résiduel : %', (
      SELECT jsonb_agg(to_jsonb(i)) FROM jolene_lint_residuel_issues i
    );
  END IF;
END;
$lint$;

DO $catalogue$
DECLARE
  v_definition text;
  v_signature regprocedure;
BEGIN
  SELECT pg_get_functiondef(
    'public.fn_parrainage_verifier_seuils(uuid)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_list_admin_user_ids[(][)] AS admins[(]admin_user_id[)]')
       IS DISTINCT FROM true
     OR (v_definition ~ '''ADMIN''') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Source admin du parrainage non canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_calculer_score_soignant(uuid)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'FROM public[.]notations_missions') IS DISTINCT FROM true
     OR (v_definition ~ 'ETAB_VERS_SOIGNANT') IS DISTINCT FROM true
     OR (v_definition ~ 'publie_le IS NOT NULL') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Source des notations soignant non canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_charger_demo_investisseur()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ '''PRESERVATION''') IS DISTINCT FROM true
     OR (v_definition ~* '\m(INSERT|UPDATE|DELETE)\M') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'RPC demo destructive ou mode preservation absent';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_envoyer_rappels_notation_j1()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'private[.]fn_controler_rappels_notation_j1[(][)]')
       IS DISTINCT FROM true
     OR (v_definition ~ 'INSERT INTO public[.]notifications_notation_j1')
       IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Rappels notation hors du contrôleur HTTP canonique';
  END IF;

  SELECT pg_get_functiondef(
    'private.fn_controler_rappels_notation_j1()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'status_code BETWEEN 200 AND 299')
       IS DISTINCT FROM true
     OR (v_definition ~ 'COALESCE[(]v_dispatch[.]timed_out, false[)] IS FALSE')
       IS DISTINCT FROM true
     OR (v_definition ~ 'v_dispatch[.]error_msg IS NULL')
       IS DISTINCT FROM true
     OR (v_definition ~ 'INSERT INTO public[.]notifications_notation_j1')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Succès des rappels non conditionné par une réponse HTTP 2xx';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_email_factures_impayees()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'email_contact') IS DISTINCT FROM true
     OR (v_definition ~ 'date_echeance < CURRENT_DATE') IS DISTINCT FROM true
     OR (v_definition ~ '''EN_RETARD''') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Selection des factures impayees non canonique';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_commission_info_etablissement()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'fn_compte_auth_actif[(][)] IS NOT TRUE')
       IS DISTINCT FROM true
     OR (v_definition ~ '''lecture_paiement''') IS DISTINCT FROM true
     OR (v_definition ~ 'e[.]id = v_etab_id') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Accès aux commissions non borné par lecture_paiement';
  END IF;

  IF (
    SELECT p.provolatile
    FROM pg_proc p
    WHERE p.oid = 'public.fn_calculer_heures_majorees(timestamp with time zone,timestamp with time zone)'::regprocedure
  ) IS DISTINCT FROM 's' THEN
    RAISE EXCEPTION 'Calcul des heures majorees doit etre STABLE';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_annuler_mission(uuid,text)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'auth[.]uid[(][)] IS NULL') IS DISTINCT FROM true
     OR (v_definition ~ 'IS DISTINCT FROM v_etab_id') IS DISTINCT FROM true
     OR (v_definition ~ 'IS DISTINCT FROM auth[.]uid[(][)]')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Garde fail-closed absente de fn_annuler_mission';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_annuler_mission_etab(uuid,text,text)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'etablissement_id IS DISTINCT FROM public[.]mon_etablissement_id')
       IS DISTINCT FROM true
     OR (v_definition ~ 'fn_a_permission_etablissement[(][[:space:]]*''missions''[[:space:]]*,[[:space:]]*v_mission[.]etablissement_id[[:space:]]*[)] IS NOT TRUE')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Garde fail-closed absente de fn_annuler_mission_etab';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_annuler_mission_etablissement(uuid,text)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'etablissement_id IS DISTINCT FROM public[.]mon_etablissement_id')
       IS DISTINCT FROM true
     OR (v_definition ~ 'fn_a_permission_etablissement[(][[:space:]]*''missions''[[:space:]]*,[[:space:]]*v_mission[.]etablissement_id[[:space:]]*[)] IS NOT TRUE')
       IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Garde fail-closed absente de fn_annuler_mission_etablissement';
  END IF;

  IF has_function_privilege(
       'anon', 'public.fn_annuler_mission(uuid,text)', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated', 'public.fn_annuler_mission(uuid,text)', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'service_role', 'public.fn_annuler_mission(uuid,text)', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'RPC legacy fn_annuler_mission encore exposee';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(
        COALESCE(p.proacl, acldefault('f', p.proowner))
      ) acl
     WHERE p.oid = 'public.fn_annuler_mission(uuid,text)'::regprocedure
       AND acl.grantee = 0
       AND acl.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC execute encore present sur fn_annuler_mission';
  END IF;

  IF has_function_privilege(
       'anon', 'public.fn_souscrire_prevoyance(uuid,text)', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated', 'public.fn_souscrire_prevoyance(uuid,text)', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'service_role', 'public.fn_souscrire_prevoyance(uuid,text)', 'EXECUTE'
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Souscription prevoyance legacy encore exposee';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'private.fn_admin_creer_compte_employe_interne_lancement(text,text,text,text,text,numeric,text[])',
    'EXECUTE'
  ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Implémentation privée de création admin exposée';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.fn_admin_creer_compte_employe(text,text,text,text,text,numeric,text[])',
    'EXECUTE'
  ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Wrapper admin de lancement devenu inaccessible';
  END IF;

  SELECT pg_get_functiondef(
    'private.fn_contrat_lie_compte_test(uuid,uuid,uuid)'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'm[.]etablissement_id IS DISTINCT FROM p_etablissement_id')
       IS DISTINCT FROM true
     OR (v_definition ~ 'm[.]soignant_assigne_id IS DISTINCT FROM p_soignant_id')
       IS DISTINCT FROM true
     OR (v_definition ~ 'e_contrat[.]est_compte_test IS TRUE') IS DISTINCT FROM true
     OR (v_definition ~ 's_contrat[.]est_compte_test IS TRUE') IS DISTINCT FROM true
     OR (v_definition ~ 'e_mission[.]est_compte_test IS TRUE') IS DISTINCT FROM true
     OR (v_definition ~ 's_mission[.]est_compte_test IS TRUE') IS DISTINCT FROM true
     OR (v_definition ~ '[)], true[)];') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Helper contrats test non sourcé ou non fail-closed';
  END IF;

  IF (
    SELECT p.prosecdef
       AND p.provolatile = 's'
       AND EXISTS (
         SELECT 1
         FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) setting
         WHERE setting IN ('search_path=', 'search_path=""')
       )
    FROM pg_proc p
    WHERE p.oid = 'private.fn_contrat_lie_compte_test(uuid,uuid,uuid)'::regprocedure
  ) IS DISTINCT FROM true
     OR has_function_privilege(
       'anon', 'private.fn_contrat_lie_compte_test(uuid,uuid,uuid)', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated', 'private.fn_contrat_lie_compte_test(uuid,uuid,uuid)', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'service_role', 'private.fn_contrat_lie_compte_test(uuid,uuid,uuid)', 'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Helper contrats test : attributs ou ACL non minimaux';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.dec_email_contrat_a_signer()'::regprocedure,
    'public.dec_email_contrat_signe_complet()'::regprocedure,
    'public.dec_notif_signature_soignant_recue()'::regprocedure,
    'public.dec_push_contrat_a_signer()'::regprocedure,
    'public.dec_push_contrat_signe_complet()'::regprocedure
  ] LOOP
    SELECT pg_get_functiondef(v_signature) INTO v_definition;
    IF regexp_count(v_definition, 'private[.]fn_contrat_lie_compte_test')
         IS DISTINCT FROM 1
       OR (v_definition ~ 'IS NOT FALSE[[:space:]]+THEN[[:space:]]+RETURN NEW')
         IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Early return contrat test absent de %', v_signature;
    END IF;
    IF (
      SELECT p.prosecdef
         AND EXISTS (
           SELECT 1
           FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) setting
           WHERE setting IN ('search_path=', 'search_path=""')
         )
      FROM pg_proc p
      WHERE p.oid = v_signature
    ) IS DISTINCT FROM true
       OR has_function_privilege('anon', v_signature, 'EXECUTE')
         IS DISTINCT FROM false
       OR has_function_privilege('authenticated', v_signature, 'EXECUTE')
         IS DISTINCT FROM false
       OR has_function_privilege('service_role', v_signature, 'EXECUTE')
         IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Trigger contrat % : attributs ou ACL non minimaux', v_signature;
    END IF;
  END LOOP;

  SELECT pg_get_functiondef(
    'private.dec_bloquer_notification_admin_compte_test()'::regprocedure
  ) INTO v_definition;
  IF (v_definition ~ 'NEW[.]type_destinataire = ''ADMIN''') IS DISTINCT FROM true
     OR (v_definition ~ 's[.]id = auth[.]uid[(][)]') IS DISTINCT FROM true
     OR (v_definition ~ 's[.]est_compte_test IS TRUE') IS DISTINCT FROM true
     OR (v_definition ~ 'RETURN NULL') IS DISTINCT FROM true
     OR NOT EXISTS (
       SELECT 1
       FROM pg_trigger t
       WHERE t.tgrelid = 'public.notifications'::regclass
         AND t.tgname = 'trg_bloquer_notification_admin_compte_test'
         AND t.tgfoid = 'private.dec_bloquer_notification_admin_compte_test()'::regprocedure
         AND t.tgenabled = 'O'
         AND t.tgtype = 7 -- ROW (1) + BEFORE (2) + INSERT (4)
         AND NOT t.tgisinternal
     ) THEN
    RAISE EXCEPTION 'Garde notifications ADMIN des comptes test absent';
  END IF;

  IF (
    SELECT p.prosecdef
       AND EXISTS (
         SELECT 1
         FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) setting
         WHERE setting IN ('search_path=', 'search_path=""')
       )
    FROM pg_proc p
    WHERE p.oid = 'private.dec_bloquer_notification_admin_compte_test()'::regprocedure
  ) IS DISTINCT FROM true
     OR has_function_privilege(
       'anon', 'private.dec_bloquer_notification_admin_compte_test()', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated', 'private.dec_bloquer_notification_admin_compte_test()', 'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'service_role', 'private.dec_bloquer_notification_admin_compte_test()', 'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'ACL du garde notifications test non minimale';
  END IF;
END;
$catalogue$;

-- Appels uniquement sur un identifiant généré et vérifié absent de toutes les
-- tables métier consultées, ou sur des branches sans DML.
DO $runtime_lecture_seule$
DECLARE
  v_result jsonb;
  v_heures record;
  v_absent_id uuid;
BEGIN
  -- Rend ce test autonome même lorsqu'il est concaténé après une suite qui a
  -- simulé un JWT dans la même transaction de validation.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);

  LOOP
    v_absent_id := gen_random_uuid();
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.etablissements WHERE id = v_absent_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.soignants WHERE id = v_absent_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.missions WHERE id = v_absent_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.parrainages WHERE id = v_absent_id
    );
  END LOOP;

  SELECT * INTO v_heures
  FROM public.fn_calculer_heures_majorees(
    '2026-01-06 22:00 Europe/Paris'::timestamptz,
    '2026-01-06 22:15 Europe/Paris'::timestamptz
  );
  IF v_heures.heures_nuit IS DISTINCT FROM 0.25
     OR v_heures.heures_dimanche IS DISTINCT FROM 0
     OR v_heures.heures_ferie IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'Calcul quart heure de nuit inattendu : %', row_to_json(v_heures);
  END IF;

  v_result := public.fn_calculer_remuneration_mission(
    now(),
    now(),
    20,
    v_absent_id,
    NULL
  );
  IF v_result->>'type_contrat' IS DISTINCT FROM 'CDD' THEN
    RAISE EXCEPTION 'Type contrat initial inattendu : %', v_result;
  END IF;

  v_result := public.fn_calculer_score_soignant(v_absent_id);
  IF v_result->>'error' IS DISTINCT FROM 'Soignant introuvable' THEN
    RAISE EXCEPTION 'Garde score inattendue : %', v_result;
  END IF;

  v_result := public.fn_admin_reset_test_account('ROLE_INCONNU');
  IF v_result->>'error' IS DISTINCT FROM 'Rôle invalide' THEN
    RAISE EXCEPTION 'Garde reset test inattendue : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission(
    v_absent_id,
    NULL
  );
  IF v_result->>'error' IS DISTINCT FROM 'Mission introuvable' THEN
    RAISE EXCEPTION 'Garde annulation legacy inattendue : %', v_result;
  END IF;

  PERFORM public.fn_parrainage_verifier_seuils(v_absent_id);

  v_result := public.fn_souscrire_prevoyance(
    v_absent_id,
    NULL
  );
  IF v_result->>'error' IS DISTINCT FROM 'Acces refuse' THEN
    RAISE EXCEPTION 'Garde prévoyance inattendue : %', v_result;
  END IF;

  IF private.fn_contrat_lie_compte_test(
       v_absent_id, v_absent_id, v_absent_id
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Helper contrats test non fail-closed sur provenance absente';
  END IF;
END;
$runtime_lecture_seule$;

-- La protection anti-abus ne bloque que la file ADMIN lorsqu'un soignant test
-- est l'appelant. Sa propre notification reste persistée et un soignant réel
-- conserve exactement le chemin ADMIN historique.
DO $notifications_admin_test$
DECLARE
  v_soignant_id uuid := gen_random_uuid();
  v_admin_id uuid := gen_random_uuid();
  v_email text;
BEGIN
  v_email := 'runtime-notification-test-' || v_soignant_id::text || '@test.local';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  INSERT INTO auth.users(
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES (
    v_soignant_id, '00000000-0000-0000-0000-000000000000',
    v_email, 'authenticated', 'authenticated',
    '{"role":"SOIGNANT"}'::jsonb, now()
  );
  INSERT INTO public.soignants(
    id, prenom, nom, email, profession, est_compte_test, statut_compte
  ) VALUES (
    v_soignant_id, 'Runtime', 'Notification', v_email,
    'IDE', true, 'ACTIF'
  );

  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_soignant_id, 'role', 'authenticated')::text,
    true
  );

  INSERT INTO public.notifications(
    destinataire_id, type_destinataire, type, titre, corps
  ) VALUES (
    v_admin_id, 'ADMIN', 'MESSAGE_ADMIN',
    'Runtime admin test bloquée', 'Cette ligne ne doit pas être persistée.'
  );
  INSERT INTO public.notifications(
    destinataire_id, type_destinataire, type, titre, corps
  ) VALUES (
    v_soignant_id, 'SOIGNANT', 'SYSTEM',
    'Runtime soignant test conservée', 'Cette ligne doit être persistée.'
  );

  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE destinataire_id = v_admin_id
      AND titre = 'Runtime admin test bloquée'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE destinataire_id = v_soignant_id
      AND titre = 'Runtime soignant test conservée'
  ) THEN
    RAISE EXCEPTION 'Garde ADMIN test trop permissive ou trop large';
  END IF;

  -- Simule la bascule post-lancement sans affaiblir le verrou pré-lancement :
  -- le trigger est neutralisé uniquement pour cette ligne sous ROLLBACK.
  SET CONSTRAINTS ALL IMMEDIATE;
  ALTER TABLE public.soignants
    DISABLE TRIGGER trg_forcer_compte_test_prelaunch;
  UPDATE public.soignants
     SET est_compte_test = false
   WHERE id = v_soignant_id;
  ALTER TABLE public.soignants
    ENABLE TRIGGER trg_forcer_compte_test_prelaunch;
  INSERT INTO public.notifications(
    destinataire_id, type_destinataire, type, titre, corps
  ) VALUES (
    v_admin_id, 'ADMIN', 'MESSAGE_ADMIN',
    'Runtime admin réel conservée', 'Cette ligne doit être persistée.'
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE destinataire_id = v_admin_id
      AND titre = 'Runtime admin réel conservée'
  ) THEN
    RAISE EXCEPTION 'Garde ADMIN test a modifié le comportement non-test';
  END IF;

  DELETE FROM public.notifications
   WHERE destinataire_id IN (v_soignant_id, v_admin_id)
     AND titre IN (
       'Runtime soignant test conservée',
       'Runtime admin réel conservée'
     );
  DELETE FROM public.soignants WHERE id = v_soignant_id;
  DELETE FROM auth.users WHERE id = v_soignant_id;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$notifications_admin_test$;

-- Preuve adverse BOLA sur fixtures autonomes. Les utilisateurs, les deux
-- etablissements et la mission cible sont propres a ce test et integralement
-- annules par le ROLLBACK final : aucune donnee de demonstration n'est requise
-- ni modifiee.
DO $bola_annulation$
DECLARE
  v_etab_cible_id uuid := 'b01a0000-0000-4000-8000-000000000001'::uuid;
  v_etab_tiers_id uuid := 'b01a0000-0000-4000-8000-000000000002'::uuid;
  v_mission_id uuid := 'b01a0000-0000-4000-8000-000000000003'::uuid;
  v_soignant_id uuid := 'b01a0000-0000-4000-8000-000000000004'::uuid;
  v_cross_etab_user_id uuid := 'b01a0000-0000-4000-8000-000000000005'::uuid;
  v_mission record;
  v_result jsonb;
  v_statut_apres public.statut_mission;
  v_modifie_apres timestamptz;
BEGIN
  -- L'insertion des fixtures s'effectue sous le rôle serveur et avec un motif
  -- de seed borné à cette transaction. Les gardes de création de mission ne
  -- sont donc jamais contournables par un JWT utilisateur.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (
      v_soignant_id, '00000000-0000-0000-0000-000000000000',
      'bola-soignant@runtime.test', 'authenticated', 'authenticated',
      '{"role":"SOIGNANT"}'::jsonb, now()
    ),
    (
      v_cross_etab_user_id, '00000000-0000-0000-0000-000000000000',
      'bola-etablissement@runtime.test', 'authenticated', 'authenticated',
      '{"role":"ADMIN_ETABLISSEMENT"}'::jsonb, now()
    );

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact
  ) VALUES
    (
      v_etab_cible_id, 'Fixture BOLA cible', '99140000000001',
      'CLINIQUE_PRIVEE', '1 rue du Test', 'Paris', '75001',
      'bola-cible@runtime.test'
    ),
    (
      v_etab_tiers_id, 'Fixture BOLA tiers', '99140000000002',
      'CLINIQUE_PRIVEE', '2 rue du Test', 'Lyon', '69001',
      'bola-tiers@runtime.test'
    );

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, actif
  ) VALUES (
    v_etab_tiers_id, v_cross_etab_user_id, 'RH', true
  );

  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Fixture transactionnelle anti-BOLA annulation mission',
    true
  );
  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id, type_contrat_recherche, mode_attribution
  ) VALUES (
    v_mission_id, v_etab_cible_id, 'Fixture anti-BOLA annulation', 'IDE',
    now() + interval '7 days', now() + interval '7 days 8 hours',
    8, 20, 'OUVERTE', NULL, 'SALARIE', 'CANDIDATURE'
  );
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);

  SELECT m.id, m.etablissement_id, m.soignant_assigne_id,
         m.statut, m.modifie_le
    INTO v_mission
    FROM public.missions m
   WHERE m.id = v_mission_id;

  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_soignant_id, 'role', 'authenticated')::text,
    true
  );

  IF auth.uid() IS DISTINCT FROM v_soignant_id
     OR public.mon_etablissement_id() IS NOT NULL THEN
    RAISE EXCEPTION 'Contexte JWT soignant adverse invalide';
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission.id,
    'AUTRE',
    'Tentative adverse soignant sans etablissement'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'BOLA soignant acceptee par fn_annuler_mission_etab : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etablissement(
    v_mission.id,
    'Tentative adverse soignant'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Cette mission ne vous appartient pas' THEN
    RAISE EXCEPTION 'BOLA soignant acceptee par fn_annuler_mission_etablissement : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission(
    v_mission.id,
    'Tentative adverse soignant'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Accès refusé' THEN
    RAISE EXCEPTION 'BOLA soignant acceptee par fn_annuler_mission legacy : %', v_result;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_cross_etab_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_cross_etab_user_id, 'role', 'authenticated'
    )::text,
    true
  );

  IF auth.uid() IS DISTINCT FROM v_cross_etab_user_id
     OR public.mon_etablissement_id() IS DISTINCT FROM v_etab_tiers_id
     OR public.mon_etablissement_id() IS NOT DISTINCT FROM v_mission.etablissement_id THEN
    RAISE EXCEPTION 'Contexte JWT etablissement adverse invalide';
  END IF;

  v_result := public.fn_annuler_mission_etab(
    v_mission.id,
    'AUTRE',
    'Tentative adverse depuis un autre etablissement'
  );
  IF v_result->>'error_code' IS DISTINCT FROM 'NON_AUTORISE' THEN
    RAISE EXCEPTION 'BOLA cross-etab acceptee par fn_annuler_mission_etab : %', v_result;
  END IF;

  v_result := public.fn_annuler_mission_etablissement(
    v_mission.id,
    'Tentative adverse cross-etab'
  );
  IF v_result->>'error' IS DISTINCT FROM 'Cette mission ne vous appartient pas' THEN
    RAISE EXCEPTION 'BOLA cross-etab acceptee par fn_annuler_mission_etablissement : %', v_result;
  END IF;

  SELECT m.statut, m.modifie_le
    INTO v_statut_apres, v_modifie_apres
    FROM public.missions m
   WHERE m.id = v_mission.id;

  IF v_statut_apres IS DISTINCT FROM v_mission.statut
     OR v_modifie_apres IS DISTINCT FROM v_mission.modifie_le THEN
    RAISE EXCEPTION 'Mission modifiee par une tentative BOLA';
  END IF;

  -- Une suite SQL peut concatener plusieurs fichiers avant le ROLLBACK final.
  -- Nettoyer explicitement les fixtures empeche alors le test suivant de les
  -- selectionner. Le role serveur sans utilisateur ne sert qu'a ce nettoyage.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  DELETE FROM public.missions
   WHERE id = v_mission_id;
  DELETE FROM public.membres_etablissement
   WHERE etablissement_id = v_etab_tiers_id
     AND user_id = v_cross_etab_user_id;
  DELETE FROM public.etablissements
   WHERE id IN (v_etab_cible_id, v_etab_tiers_id);
  DELETE FROM auth.users
   WHERE id IN (v_soignant_id, v_cross_etab_user_id);

  IF EXISTS (SELECT 1 FROM public.missions WHERE id = v_mission_id)
     OR EXISTS (
       SELECT 1
       FROM public.membres_etablissement
       WHERE etablissement_id = v_etab_tiers_id
         AND user_id = v_cross_etab_user_id
     )
     OR EXISTS (
       SELECT 1
       FROM public.etablissements
       WHERE id IN (v_etab_cible_id, v_etab_tiers_id)
     )
     OR EXISTS (
       SELECT 1
       FROM auth.users
       WHERE id IN (v_soignant_id, v_cross_etab_user_id)
     ) THEN
    RAISE EXCEPTION 'Nettoyage des fixtures BOLA incomplet';
  END IF;

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$bola_annulation$;

DO $classement_and_security_inventory$
DECLARE
  v_bad text;
  v_definition text;
BEGIN
  IF has_function_privilege(
       'anon',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'service_role',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'fn_dans_fenetre_retractation reste exposée hors service_role';
  END IF;

  SELECT pg_get_functiondef(
    'public.fn_top_soignants(text,integer)'::regprocedure
  ) INTO v_definition;
  IF v_definition NOT LIKE '%LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)%'
     OR v_definition NOT LIKE '%LIMIT v_limit%'
     OR pg_get_function_result(
       'public.fn_top_soignants(text,integer)'::regprocedure
     ) NOT LIKE '%prenom text%nom text%' THEN
    RAISE EXCEPTION 'Classement non borné ou identité incomplète';
  END IF;

  SELECT string_agg(r.signature, ', ' ORDER BY r.signature)
  INTO v_bad
  FROM (VALUES
    (
      'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
      'public.fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)'::regprocedure
    ),
    (
      'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
      'public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure
    ),
    (
      'fn_diagnostic_coherence_financiere()',
      'public.fn_diagnostic_coherence_financiere()'::regprocedure
    ),
    (
      'fn_marquer_messages_lus(uuid)',
      'public.fn_marquer_messages_lus(uuid)'::regprocedure
    ),
    (
      'fn_obligations_financieres()',
      'public.fn_obligations_financieres()'::regprocedure
    ),
    (
      'fn_paiements_etablissement()',
      'public.fn_paiements_etablissement()'::regprocedure
    ),
    (
      'fn_top_soignants(text,integer)',
      'public.fn_top_soignants(text,integer)'::regprocedure
    ),
    (
      'fn_dans_fenetre_retractation(uuid)',
      'public.fn_dans_fenetre_retractation(uuid)'::regprocedure
    )
  ) AS r(signature, procedure_oid)
  JOIN private.security_definer_inventory i ON i.signature = r.signature
  JOIN pg_proc p ON p.oid = r.procedure_oid
  WHERE md5(p.prosrc) IS DISTINCT FROM i.definition_md5;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Empreintes SECURITY DEFINER incohérentes : %', v_bad;
  END IF;
END;
$classement_and_security_inventory$;

ROLLBACK;

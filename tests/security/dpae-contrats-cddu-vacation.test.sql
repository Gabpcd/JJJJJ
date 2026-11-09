-- ═══════════════════════════════════════════════════════════════════════════
-- Régression B9 : la DPAE couvre les contrats CDDU et VACATION
-- (migration 20261108223500_dpae_contrats_cddu_vacation).
--
-- ⚠️  JAMAIS EN PROD. Staging CI exclusivement : job « sql-transaction » de
--     validate-pr.yml, après la migration candidate, sous SAVEPOINT puis
--     ROLLBACK global ; un sous-bloc annulé par sentinelle rend aussi la suite
--     autonome face aux wrappers qui retirent BEGIN/ROLLBACK. Vraies routines,
--     vrais triggers, comptes fictifs TEST ; aucun fournisseur ; zéro
--     persistance.
--
-- Ce qu'il prouve sur la base réelle :
--   - le helper public.fn_type_contrat_salarie(text) : table de vérité
--     (CDD, SALARIE, CDDU, VACATION vrais ; REMPLACEMENT_LIBERAL, LIBERAL
--     faux ; NULL → NULL), IMMUTABLE, SECURITY INVOKER, search_path vide,
--     EXECUTE refusé à anon ;
--   - les cinq fonctions redéfinies : SECURITY DEFINER, propriétaire
--     postgres, search_path et droits attendus, un seul appel au helper, plus
--     aucune liste héritée « 'CDD', 'CDD' » ; inventaire SECURITY DEFINER des
--     trois RPC recensées aligné sur le corps installé ;
--   - fn_mes_dpae appelée par le soignant (rôle authenticated) liste ses
--     contrats signés CDD, CDDU et VACATION, jamais REMPLACEMENT_LIBERAL ni un
--     contrat non signé ; anon n'y a pas accès.
-- Les quatre autres comportements (rappel, pointage, annulation, audit de
-- signature) sont prouvés avant/après sur les corps LIVE par le banc PG17
-- tests/security/dpae-contrats-cddu-vacation-isolated.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '3s';

DO $dpae_salarie$
DECLARE
  e uuid := '99108000-0000-4000-8000-000000000001';
  s uuid := '99108000-0000-4000-8000-000000000002';
  m uuid := '99108000-0000-4000-8000-000000000011';
  v_helper constant regprocedure := 'public.fn_type_contrat_salarie(text)'::regprocedure;
  f record;
  r jsonb;
  v_ids text[];
  refuse boolean;
BEGIN
  IF session_user NOT IN ('postgres', 'supabase_admin') OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'DPAE_SALARIE_CONTEXTE_NON_ISOLE';
  END IF;

  -- ── 1. Helper : attributs, droits, table de vérité ────────────────────────
  IF (SELECT p.provolatile FROM pg_proc p WHERE p.oid = v_helper) IS DISTINCT FROM 'i'
    OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_helper) IS DISTINCT FROM false
    OR (SELECT p.proconfig FROM pg_proc p WHERE p.oid = v_helper) IS DISTINCT FROM ARRAY['search_path=""']::text[]
    OR (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid = v_helper) IS DISTINCT FROM 'postgres'
    OR has_function_privilege('anon', v_helper, 'EXECUTE')
    OR NOT has_function_privilege('authenticated', v_helper, 'EXECUTE')
    OR NOT has_function_privilege('service_role', v_helper, 'EXECUTE')
  THEN RAISE EXCEPTION 'DPAE_SALARIE_HELPER_ATTRIBUTS'; END IF;
  IF public.fn_type_contrat_salarie('CDD') IS NOT TRUE
    OR public.fn_type_contrat_salarie('SALARIE') IS NOT TRUE
    OR public.fn_type_contrat_salarie('CDDU') IS NOT TRUE
    OR public.fn_type_contrat_salarie('VACATION') IS NOT TRUE
    OR public.fn_type_contrat_salarie('REMPLACEMENT_LIBERAL') IS NOT FALSE
    OR public.fn_type_contrat_salarie('LIBERAL') IS NOT FALSE
    OR public.fn_type_contrat_salarie(NULL) IS NOT NULL
  THEN RAISE EXCEPTION 'DPAE_SALARIE_HELPER_TABLE_DE_VERITE'; END IF;

  -- ── 2. Les cinq fonctions installées ──────────────────────────────────────
  FOR f IN SELECT * FROM (VALUES
    ('fn_mes_dpae()', ARRAY['search_path=public']::text[], true, 'RPC_UTILISATEUR_AUTH_INTERNE'),
    ('fn_rappel_dpae_quotidien()', ARRAY['search_path=public']::text[], false, NULL),
    ('fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text)', ARRAY['search_path=public']::text[], true, 'RPC_UTILISATEUR_AUTH_INTERNE'),
    ('fn_annuler_candidature_soignant(uuid,text,text,text)', ARRAY['search_path=public']::text[], true, 'RPC_UTILISATEUR_AUTH_INTERNE'),
    ('dec_email_contrat_signe_complet()', ARRAY['search_path=""']::text[], false, NULL)
  ) AS t(signature, config, authenticated_execute, categorie) LOOP
    IF NOT EXISTS (
      SELECT FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.' || f.signature)
         AND p.prosecdef
         AND pg_get_userbyid(p.proowner) = 'postgres'
         AND p.proconfig IS NOT DISTINCT FROM f.config
         AND (length(p.prosrc) - length(replace(p.prosrc, 'public.fn_type_contrat_salarie(', '')))
             / length('public.fn_type_contrat_salarie(') = 1
         AND strpos(p.prosrc, 'IN (''CDD'', ''CDD''') = 0)
    THEN RAISE EXCEPTION 'DPAE_SALARIE_CORPS_INSTALLE: %', f.signature; END IF;
    IF has_function_privilege('anon', to_regprocedure('public.' || f.signature), 'EXECUTE')
      OR has_function_privilege('authenticated', to_regprocedure('public.' || f.signature), 'EXECUTE')
         IS DISTINCT FROM f.authenticated_execute
      OR NOT has_function_privilege('service_role', to_regprocedure('public.' || f.signature), 'EXECUTE')
    THEN RAISE EXCEPTION 'DPAE_SALARIE_DROITS: %', f.signature; END IF;
    IF f.categorie IS NOT NULL AND NOT EXISTS (
      SELECT FROM private.security_definer_inventory i
      JOIN pg_proc p ON p.oid = to_regprocedure('public.' || f.signature)
       WHERE i.signature = f.signature AND i.categorie = f.categorie
         AND i.definition_md5 = md5(p.prosrc))
    THEN RAISE EXCEPTION 'DPAE_SALARIE_INVENTAIRE: %', f.signature; END IF;
  END LOOP;

  -- ── 3. fn_mes_dpae sur la base réelle, rôle authenticated ────────────────
  IF EXISTS (SELECT 1 FROM auth.users WHERE id IN (e, s))
    OR EXISTS (SELECT 1 FROM public.soignants WHERE id = s)
    OR EXISTS (SELECT 1 FROM public.etablissements WHERE id = e OR siret = '99108000000001')
    OR EXISTS (SELECT 1 FROM public.missions WHERE id = m)
    OR EXISTS (SELECT 1 FROM public.contrats_mission WHERE id::text LIKE '99108000-0000-4000-8000-%'
                 OR numero_contrat LIKE 'RECETTE-DPAE-SALARIE-%')
  THEN RAISE EXCEPTION 'DPAE_SALARIE_FIXTURE_COLLISION'; END IF;

  BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    PERFORM set_config('jolene.admin_seed_override_reason', 'Recette DPAE CDDU/VACATION : fixtures annulées', true);
    INSERT INTO auth.users(id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at)
    VALUES
      (e, '00000000-0000-0000-0000-000000000000', 'dpae-salarie-1@example.invalid',
       'authenticated', 'authenticated', jsonb_build_object('role', 'ADMIN_ETABLISSEMENT', 'is_test_playwright', true), now()),
      (s, '00000000-0000-0000-0000-000000000000', 'dpae-salarie-2@example.invalid',
       'authenticated', 'authenticated', jsonb_build_object('role', 'SOIGNANT', 'is_test_playwright', true), now());
    INSERT INTO public.soignants(id, email, prenom, nom, profession, type_exercice, est_compte_test)
    VALUES (s, 'dpae-salarie-2@example.invalid', 'Recette', 'DPAE', 'IDE', 'SALARIE', true);
    INSERT INTO public.etablissements(id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact, est_compte_test)
    VALUES (e, 'Recette DPAE salariés', '99108000000001', 'CLINIQUE_PRIVEE', 'Test', 'Paris', '75001',
            'dpae-salarie-1@example.invalid', true);
    INSERT INTO public.missions(id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures,
      taux_horaire_base, statut, soignant_assigne_id, type_contrat_recherche, type_contrat_applique, type_paiement_soignant)
    VALUES (m, e, 'Mission DPAE fictive', 'IDE', '2035-07-18 09:00:00+02', '2035-07-18 17:00:00+02', 8, 20,
            'TERMINEE', s, 'SALARIE', 'SALARIE', 'BULLETIN_PAIE');
    INSERT INTO public.contrats_mission(id, mission_id, etablissement_id, soignant_id, type_contrat, numero_contrat, statut)
    VALUES
      ('99108000-0000-4000-8000-000000000021', m, e, s, 'CDD', 'RECETTE-DPAE-SALARIE-1', 'SIGNE_COMPLET'),
      ('99108000-0000-4000-8000-000000000022', m, e, s, 'CDDU', 'RECETTE-DPAE-SALARIE-2', 'SIGNE_COMPLET'),
      ('99108000-0000-4000-8000-000000000023', m, e, s, 'VACATION', 'RECETTE-DPAE-SALARIE-3', 'SIGNE_COMPLET'),
      ('99108000-0000-4000-8000-000000000024', m, e, s, 'REMPLACEMENT_LIBERAL', 'RECETTE-DPAE-SALARIE-4', 'SIGNE_COMPLET'),
      ('99108000-0000-4000-8000-000000000025', m, e, s, 'CDDU', 'RECETTE-DPAE-SALARIE-5', 'EN_ATTENTE_SIGNATURES');

    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', s::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', s, 'role', 'authenticated')::text, true);
    r := public.fn_mes_dpae();
    EXECUTE 'RESET ROLE';
    SELECT array_agg(x->>'contrat_id' ORDER BY x->>'contrat_id') INTO v_ids
      FROM jsonb_array_elements(r->'dpae') x;
    IF r->>'success' IS DISTINCT FROM 'true'
      OR v_ids IS DISTINCT FROM ARRAY['99108000-0000-4000-8000-000000000021',
                                      '99108000-0000-4000-8000-000000000022',
                                      '99108000-0000-4000-8000-000000000023']
      OR EXISTS (SELECT FROM jsonb_array_elements(r->'dpae') x
                  WHERE x->>'type_contrat' NOT IN ('CDD', 'CDDU', 'VACATION')
                     OR x->>'statut_contrat' IS DISTINCT FROM 'SIGNE_COMPLET')
    THEN RAISE EXCEPTION 'DPAE_SALARIE_LISTE_SOIGNANT: %', r; END IF;

    -- Sans identité : refus structuré existant, inchangé.
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
    r := public.fn_mes_dpae();
    EXECUTE 'RESET ROLE';
    IF r IS DISTINCT FROM '{"success": false, "error_code": "NON_AUTHENTIFIE"}'::jsonb THEN
      RAISE EXCEPTION 'DPAE_SALARIE_SANS_IDENTITE: %', r;
    END IF;

    -- anon : ni la liste ni le helper.
    EXECUTE 'SET LOCAL ROLE anon';
    refuse := false;
    BEGIN PERFORM public.fn_mes_dpae();
    EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
    EXECUTE 'RESET ROLE';
    IF NOT refuse THEN RAISE EXCEPTION 'DPAE_SALARIE_LISTE_ANON'; END IF;
    EXECUTE 'SET LOCAL ROLE anon';
    refuse := false;
    BEGIN PERFORM public.fn_type_contrat_salarie('CDD');
    EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
    EXECUTE 'RESET ROLE';
    IF NOT refuse THEN RAISE EXCEPTION 'DPAE_SALARIE_HELPER_ANON'; END IF;

    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
    RAISE EXCEPTION 'DPAE_SALARIE_ROLLBACK' USING ERRCODE = 'ZX108';
  EXCEPTION WHEN SQLSTATE 'ZX108' THEN
    IF SQLERRM <> 'DPAE_SALARIE_ROLLBACK' THEN RAISE; END IF;
  END;

  IF EXISTS (SELECT 1 FROM public.contrats_mission WHERE numero_contrat LIKE 'RECETTE-DPAE-SALARIE-%')
    OR EXISTS (SELECT 1 FROM auth.users WHERE id IN (e, s))
  THEN RAISE EXCEPTION 'DPAE_SALARIE_FIXTURES_NON_ANNULEES'; END IF;
  RAISE NOTICE 'DPAE CDDU/VACATION : helper, cinq corps, inventaire et liste soignant vérifiés (fixtures annulées)';
END;
$dpae_salarie$;

ROLLBACK;

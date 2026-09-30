-- Exécute le vrai helper puis le corps LIVE migré du health-check, sur des
-- tables temporaires et une horloge explicite. Aucun cron ni fournisseur appelé.
BEGIN;
DO $test$
DECLARE
  v_definition text; v_case record; v_result jsonb; v_cron jsonb; v_rejete boolean;
BEGIN
  BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  IF private.fn_echeance_cron_chorus('0 7-22/2 * * *', '2026-09-29 21:00:01+00')
      IS DISTINCT FROM '2026-09-30 08:00:00+00'::timestamptz
    OR private.fn_echeance_cron_chorus('0 7-22/2 * * *', '2026-09-30 07:00:01+00')
      IS DISTINCT FROM '2026-09-30 10:00:00+00'::timestamptz THEN
    RAISE EXCEPTION 'Échéance Chorus incorrecte';
  END IF;
  -- Indépendant du fuseau de la connexion : le cron observé est en UTC/GMT.
  PERFORM set_config('TimeZone', 'Pacific/Auckland', true);
  IF private.fn_echeance_cron_chorus('0 7-22/2 * * *', '2026-10-24 21:00:01+00')
      IS DISTINCT FROM '2026-10-25 08:00:00+00'::timestamptz THEN
    RAISE EXCEPTION 'Échéance dépendante du fuseau session';
  END IF;
  PERFORM set_config('TimeZone', 'UTC', true);
  v_rejete := false;
  BEGIN PERFORM private.fn_echeance_cron_chorus('0 7-22/2 * * 1-5', now());
  EXCEPTION WHEN invalid_parameter_value THEN v_rejete := true; END;
  IF NOT v_rejete THEN RAISE EXCEPTION 'Expression cron non auditée acceptée'; END IF;
  IF has_function_privilege('authenticated', 'private.fn_echeance_cron_chorus(text,timestamptz)', 'EXECUTE')
    OR has_function_privilege('anon', 'private.fn_echeance_cron_chorus(text,timestamptz)', 'EXECUTE')
    OR has_function_privilege('service_role', 'private.fn_echeance_cron_chorus(text,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Helper privé exposé';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p ON p.oid = 'public.fn_check_crons_health()'::regprocedure
    WHERE i.signature = 'fn_check_crons_health()' AND i.definition_md5 = md5(p.prosrc)) THEN
    RAISE EXCEPTION 'Empreinte health-check non actualisée';
  END IF;

  CREATE TEMP TABLE recette_cron_jobs(jobid bigint, jobname text, schedule text, active boolean) ON COMMIT DROP;
  CREATE TEMP TABLE recette_cron_runs(runid bigint PRIMARY KEY, jobid bigint, start_time timestamptz, end_time timestamptz, status text, return_message text) ON COMMIT DROP;
  CREATE TEMP TABLE recette_cron_cache(LIKE private.cron_job_latest_run_cache INCLUDING ALL) ON COMMIT DROP;
  CREATE TEMP TABLE recette_cron_alertes(type_alerte text, source text) ON COMMIT DROP;
  EXECUTE $stub$
    CREATE FUNCTION pg_temp.recette_emettre_alerte(text,text,text,text,jsonb) RETURNS uuid LANGUAGE plpgsql AS $emetteur$
    BEGIN INSERT INTO pg_temp.recette_cron_alertes VALUES ($1,$3); RETURN '99023000-0000-4000-8000-000000000001'; END;
    $emetteur$;
  $stub$;

  -- Copie temporaire de la fonction installée : seule l'horloge, les relations
  -- pg_cron/cache et la sortie d'alertes sont isolées. Le calcul et le helper
  -- de production restent ceux de la migration, sans réécriture du scénario.
  v_definition := pg_get_functiondef('public.fn_check_crons_health()'::regprocedure);
  v_definition := replace(v_definition, 'public.fn_check_crons_health()', 'pg_temp.recette_check_crons_health()');
  v_definition := replace(v_definition, 'cron.job_run_details ', 'pg_temp.recette_cron_runs ');
  v_definition := replace(v_definition, 'cron.job ', 'pg_temp.recette_cron_jobs ');
  v_definition := replace(v_definition, 'private.cron_job_latest_run_cache', 'pg_temp.recette_cron_cache');
  v_definition := replace(v_definition, 'public.fn_emettre_alerte_monitoring', 'pg_temp.recette_emettre_alerte');
  v_definition := replace(v_definition, 'pg_catalog.now()', '(current_setting(''jolene.recette_cron_now'')::timestamptz)');
  IF v_definition LIKE '%FROM cron.job%' OR v_definition LIKE '%JOIN cron.job%' OR v_definition LIKE '%private.cron_job_latest_run_cache%'
    OR v_definition LIKE '%public.fn_emettre_alerte_monitoring%' THEN RAISE EXCEPTION 'Isolation de recette incomplète'; END IF;
  EXECUTE v_definition;

  INSERT INTO recette_cron_jobs VALUES
    (1, 'sync-chorus-status-hourly', '0 7-22/2 * * *', true),
    (2, 'recette-cadence-deux-heures', '20 */2 * * *', true),
    (3, 'recette-cadence-cinq-minutes', '1-59/5 * * * *', true);

  FOR v_case IN SELECT * FROM (VALUES
    ('minuit', '2026-09-30 00:00:00+00', '2026-09-29 21:00:00+00', 'succeeded', false),
    ('nuit-apres-seuil-historique', '2026-09-30 00:08:00+00', '2026-09-29 21:00:00+00', 'succeeded', false),
    ('avant-premier-passage', '2026-09-30 06:59:00+00', '2026-09-29 21:00:00+00', 'succeeded', false),
    ('premier-horaire', '2026-09-30 07:00:00+00', '2026-09-29 21:00:00+00', 'succeeded', false),
    ('borne-tolerance', '2026-09-30 08:00:00+00', '2026-09-29 21:00:00+00', 'succeeded', false),
    ('premier-passage-manque', '2026-09-30 08:01:00+00', '2026-09-29 21:00:00+00', 'succeeded', true),
    ('premier-passage-reussi', '2026-09-30 08:01:00+00', '2026-09-30 07:00:00+00', 'succeeded', false),
    ('retard-journee', '2026-09-30 10:01:00+00', '2026-09-30 07:00:00+00', 'succeeded', true),
    ('dernier-passage-soir-manque', '2026-09-30 00:08:00+00', '2026-09-29 19:00:00+00', 'succeeded', true),
    ('matin-en-cours', '2026-09-30 07:01:00+00', '2026-09-30 07:00:00+00', 'running', false),
    ('execution-bloquee', '2026-09-30 10:01:00+00', '2026-09-30 07:00:00+00', 'running', true),
    ('echec-conserve', '2026-09-30 07:01:00+00', '2026-09-30 07:00:00+00', 'failed', false),
    ('jamais-execute-conserve', '2026-09-30 07:01:00+00', NULL, NULL, true)
  ) x(nom, instant, demarrage, statut, retard) LOOP
    DELETE FROM recette_cron_runs; DELETE FROM recette_cron_cache; DELETE FROM recette_cron_alertes;
    PERFORM set_config('jolene.recette_cron_now', v_case.instant, true);
    INSERT INTO recette_cron_runs VALUES (1,1,v_case.demarrage::timestamptz,
      CASE WHEN v_case.statut IN ('succeeded','failed') THEN v_case.demarrage::timestamptz + interval '1 second' END,v_case.statut,'fixture');
    -- Seuils historiques exacts 3h et 15min, puis une seconde de dépassement.
    INSERT INTO recette_cron_runs VALUES
      (2,2,v_case.instant::timestamptz - interval '3 hours 1 second',v_case.instant::timestamptz - interval '3 hours','succeeded','fixture'),
      (3,3,v_case.instant::timestamptz - interval '15 minutes 1 second',v_case.instant::timestamptz - interval '15 minutes','succeeded','fixture');
    v_result := pg_temp.recette_check_crons_health();
    SELECT c INTO v_cron FROM jsonb_array_elements(v_result->'crons') c WHERE c->>'jobname'='sync-chorus-status-hourly';
    IF (v_cron->>'retard')::boolean IS DISTINCT FROM v_case.retard THEN RAISE EXCEPTION 'Retard Chorus incorrect : % / %', v_case.nom, v_cron; END IF;
    IF EXISTS(SELECT 1 FROM recette_cron_alertes WHERE source LIKE 'recette-cadence-%') THEN RAISE EXCEPTION 'Seuil autre cadence modifié'; END IF;
    IF (SELECT count(*) FROM recette_cron_alertes WHERE source='sync-chorus-status-hourly') <> CASE WHEN v_case.retard OR v_case.statut='failed' THEN 1 ELSE 0 END THEN
      RAISE EXCEPTION 'Émission alerte incorrecte : %',v_case.nom;
    END IF;
    IF v_case.statut='failed' AND NOT EXISTS(SELECT 1 FROM recette_cron_alertes WHERE type_alerte='CRON_FAILED') THEN RAISE EXCEPTION 'Échec masqué'; END IF;
    UPDATE recette_cron_runs SET start_time=start_time-interval '1 second',end_time=end_time-interval '1 second' WHERE jobid IN(2,3);
    DELETE FROM recette_cron_alertes;
    PERFORM pg_temp.recette_check_crons_health();
    IF (SELECT count(*) FROM recette_cron_alertes WHERE source LIKE 'recette-cadence-%' AND type_alerte='CRON_RETARD') <> 2 THEN RAISE EXCEPTION 'Retard réel autre cadence masqué'; END IF;
  END LOOP;
  RAISE EXCEPTION 'ROLLBACK_MONITORING_CHORUS' USING ERRCODE='ZX230';
  EXCEPTION WHEN SQLSTATE 'ZX230' THEN NULL;
  END;
END;
$test$;
ROLLBACK;

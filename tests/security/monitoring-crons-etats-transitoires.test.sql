-- Corps de la fonction réellement installée, tables temporaires et émetteur
-- local : aucun job réel exécuté, aucune alerte réelle émise ou résolue.
BEGIN;
DO $test$
DECLARE
  v_definition text; v_case record; v_result jsonb; v_cron jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

    CREATE TEMP TABLE recette_cron_jobs(jobid bigint, jobname text, schedule text, active boolean) ON COMMIT DROP;
    CREATE TEMP TABLE recette_cron_runs(runid bigint PRIMARY KEY, jobid bigint, start_time timestamptz, end_time timestamptz, status text, return_message text) ON COMMIT DROP;
    CREATE TEMP TABLE recette_cron_cache(LIKE private.cron_job_latest_run_cache INCLUDING ALL) ON COMMIT DROP;
    CREATE TEMP TABLE recette_cron_alertes(type_alerte text, source text) ON COMMIT DROP;
    EXECUTE $stub$
      CREATE FUNCTION pg_temp.recette_emettre_alerte(text,text,text,text,jsonb) RETURNS uuid LANGUAGE plpgsql AS $emetteur$
      BEGIN INSERT INTO pg_temp.recette_cron_alertes VALUES ($1,$3); RETURN '99023200-0000-4000-8000-000000000001'; END;
      $emetteur$;
    $stub$;
    v_definition := pg_get_functiondef('public.fn_check_crons_health()'::regprocedure);
    v_definition := replace(v_definition, 'public.fn_check_crons_health()', 'pg_temp.recette_check_crons_health()');
    v_definition := replace(v_definition, 'cron.job_run_details ', 'pg_temp.recette_cron_runs ');
    v_definition := replace(v_definition, 'cron.job ', 'pg_temp.recette_cron_jobs ');
    v_definition := replace(v_definition, 'private.cron_job_latest_run_cache', 'pg_temp.recette_cron_cache');
    v_definition := replace(v_definition, 'public.fn_emettre_alerte_monitoring', 'pg_temp.recette_emettre_alerte');
    IF v_definition LIKE '%cron.job%' OR v_definition LIKE '%private.cron_job_latest_run_cache%'
      OR v_definition LIKE '%public.fn_emettre_alerte_monitoring%' THEN RAISE EXCEPTION 'Isolation de recette incomplète'; END IF;
    EXECUTE v_definition;

    -- Les cinq sources réellement faussement alertées le 01/10, mêmes cadences.
    INSERT INTO recette_cron_jobs VALUES
      (1, 'email-cron-hourly-immediate', '* * * * *', true),
      (2, 'messagerie-cleanup', '* * * * *', true),
      (3, 'auto-transitions-missions', '*/10 * * * *', true),
      (4, 'vagues-notification-urgentes', '*/15 * * * *', true),
      (5, 'jolene_verifier_pointages_incoherents', '*/30 * * * *', true);

    -- Témoin rouge : même corps avant correctif. Les cinq faux retards sont
    -- reproduits, puis leur absence est exigée avec la fonction migrée.
    EXECUTE replace(replace(v_definition, 'pg_temp.recette_check_crons_health()',
      'pg_temp.recette_ancien_check_crons_health()'),
      '''starting'', ''connecting'', ''sending'', ''running''', '''starting'', ''running''');
    INSERT INTO recette_cron_runs SELECT jobid,jobid,NULL,NULL,'connecting','fixture' FROM recette_cron_jobs;
    v_result := pg_temp.recette_ancien_check_crons_health();
    IF (SELECT count(*) FROM recette_cron_alertes WHERE type_alerte='CRON_RETARD')<>5 THEN
      RAISE EXCEPTION 'Le témoin historique ne reproduit pas les cinq faux retards';
    END IF;

    FOR v_case IN SELECT * FROM (VALUES
      ('starting', NULL::interval, false),
      ('connecting', NULL::interval, false),
      ('sending', NULL::interval, false),
      ('running', interval '1 second', false),
      ('starting', interval '2 hours', true),
      ('connecting', interval '2 hours', true),
      ('sending', interval '2 hours', true),
      ('running', interval '2 hours', true),
      ('succeeded', interval '1 second', false),
      ('succeeded', interval '2 hours', true),
      ('failed', interval '1 second', false),
      (NULL, NULL::interval, true)
    ) c(statut, anciennete, retard) LOOP
      DELETE FROM recette_cron_runs; DELETE FROM recette_cron_cache; DELETE FROM recette_cron_alertes;
      -- Un précédent succès existe déjà : le dernier run transitoire ne doit
      -- pas être interprété comme « jamais » quand il le remplace dans le cache.
      INSERT INTO recette_cron_runs
      SELECT jobid,jobid,now()-interval '2 minutes',now()-interval '1 minute','succeeded','fixture'
      FROM recette_cron_jobs;
      PERFORM pg_temp.recette_check_crons_health();
      INSERT INTO recette_cron_runs
      SELECT jobid+5,jobid,now()-v_case.anciennete,
        CASE WHEN v_case.statut IN ('succeeded','failed') THEN now()-v_case.anciennete END,
        v_case.statut,'fixture'
      FROM recette_cron_jobs;
      v_result := pg_temp.recette_check_crons_health();
      IF jsonb_array_length(v_result->'crons') <> 5 THEN RAISE EXCEPTION 'Sources de recette manquantes'; END IF;
      FOR v_cron IN SELECT * FROM jsonb_array_elements(v_result->'crons') LOOP
        IF (v_cron->>'retard')::boolean IS DISTINCT FROM v_case.retard THEN
          RAISE EXCEPTION 'Mauvais retard pour statut %, ancienneté % : %', v_case.statut, v_case.anciennete, v_cron;
        END IF;
        IF (v_cron->>'echec')::boolean IS DISTINCT FROM (v_case.statut='failed') THEN RAISE EXCEPTION 'Échec altéré'; END IF;
      END LOOP;
      IF (SELECT count(*) FROM recette_cron_alertes) <> (CASE WHEN v_case.retard OR v_case.statut='failed' THEN 5 ELSE 0 END) THEN
        RAISE EXCEPTION 'Émission incorrecte pour % : %', v_case, v_result;
      END IF;
      IF v_case.statut='failed' AND (SELECT count(*) FROM recette_cron_alertes WHERE type_alerte='CRON_FAILED')<>5 THEN RAISE EXCEPTION 'Échec masqué'; END IF;
      -- Le même runid est finalisé par pg_cron : le cache doit suivre l'état.
      UPDATE recette_cron_runs SET start_time=now()-interval '1 second',end_time=now(),status='succeeded' WHERE runid>5;
      DELETE FROM recette_cron_alertes;
      v_result := pg_temp.recette_check_crons_health();
      IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'crons') c
        WHERE c->>'dernier_statut'<>'succeeded' OR (c->>'retard')::boolean OR (c->>'echec')::boolean)
        OR EXISTS(SELECT 1 FROM recette_cron_alertes) THEN RAISE EXCEPTION 'Reprise du même runid non visible'; END IF;
    END LOOP;

    IF has_function_privilege('anon','public.fn_check_crons_health()','EXECUTE')
      OR has_function_privilege('authenticated','public.fn_check_crons_health()','EXECUTE')
      OR NOT has_function_privilege('service_role','public.fn_check_crons_health()','EXECUTE') THEN RAISE EXCEPTION 'ACL modifiées'; END IF;
    IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p ON p.oid='public.fn_check_crons_health()'::regprocedure
      WHERE i.signature='fn_check_crons_health()' AND i.definition_md5=md5(p.prosrc)
        AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres' AND p.proconfig=ARRAY['search_path=public, extensions']) THEN
      RAISE EXCEPTION 'Contexte ou empreinte de fonction incorrect';
    END IF;
    RAISE EXCEPTION 'ROLLBACK_MONITORING_TRANSITOIRE' USING ERRCODE='ZX232';
  EXCEPTION WHEN SQLSTATE 'ZX232' THEN NULL;
  END;
END;
$test$;
ROLLBACK;

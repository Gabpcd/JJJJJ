-- La vraie fonction migrée s'exécute sur des relations temporaires.
-- Aucun cron réel n'est créé, exécuté ou acquitté.
BEGIN;
DO $test$
DECLARE
  v_definition text;
  v_result jsonb;
  v_rejete boolean := false;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

    CREATE TEMP TABLE recette_auto_jobs(jobid bigint, jobname text) ON COMMIT DROP;
    CREATE TEMP TABLE recette_auto_runs(runid bigint, jobid bigint, status text, start_time timestamptz, end_time timestamptz) ON COMMIT DROP;
    CREATE TEMP TABLE recette_auto_alertes(id int, source text, type_alerte text, derniere_occurrence timestamptz, resolu_le timestamptz, resolu_motif text) ON COMMIT DROP;

    v_definition := pg_get_functiondef('public.fn_auto_resoudre_alertes_crons()'::regprocedure);
    v_definition := replace(v_definition, 'public.fn_auto_resoudre_alertes_crons()', 'pg_temp.recette_auto_resoudre_alertes_crons()');
    v_definition := replace(v_definition, 'cron.job_run_details', 'pg_temp.recette_auto_runs');
    v_definition := replace(v_definition, 'cron.job', 'pg_temp.recette_auto_jobs');
    v_definition := replace(v_definition, 'alertes_systeme', 'pg_temp.recette_auto_alertes');
    IF v_definition LIKE '%cron.job%' OR v_definition LIKE '%alertes_systeme%' THEN
      RAISE EXCEPTION 'Relations réelles présentes dans la recette';
    END IF;
    EXECUTE v_definition;

    INSERT INTO recette_auto_jobs VALUES
      (1, 'jolene_auto_resoudre_alertes'), (2, 'recette-autre-cron');
    INSERT INTO recette_auto_alertes VALUES
      (1, 'jolene_auto_resoudre_alertes', 'CRON_FAILED', now() - interval '4 hours', NULL, NULL),
      (2, 'recette-autre-cron', 'CRON_FAILED', now() - interval '4 hours', NULL, NULL),
      (3, 'ancien-cron-retire', 'CRON_FAILED', now() - interval '73 hours', NULL, NULL),
      (4, 'cron-retire-recent', 'CRON_FAILED', now() - interval '2 hours', NULL, NULL),
      (5, 'jolene_auto_resoudre_alertes', 'TRIPWIRE_PREMIER_EURO', now() - interval '80 hours', NULL, NULL);
    INSERT INTO recette_auto_runs VALUES
      (1, 1, 'failed', now() - interval '5 hours', now() - interval '5 hours' + interval '1 second'),
      (2, 1, 'succeeded', now() - interval '2 hours', now() - interval '2 hours' + interval '1 second'),
      (3, 1, 'running', now(), NULL),
      (4, 2, 'succeeded', now() - interval '2 hours', now() - interval '2 hours' + interval '1 second'),
      (5, 2, 'running', now(), NULL);

    v_result := pg_temp.recette_auto_resoudre_alertes_crons();
    IF (v_result->>'resolues')::int <> 2 OR NOT EXISTS (
      SELECT 1 FROM recette_auto_alertes WHERE id=1 AND resolu_motif='auto: cron repassé vert'
    ) THEN RAISE EXCEPTION 'Le propre run running cache encore son succès terminé'; END IF;
    IF EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id IN (2,4,5) AND resolu_le IS NOT NULL)
      OR NOT EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id=3 AND resolu_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Autre cron en cours, délai orphelin ou alerte financière altéré';
    END IF;
    v_result := pg_temp.recette_auto_resoudre_alertes_crons();
    IF (v_result->>'resolues')::int <> 0 THEN RAISE EXCEPTION 'Résolution non idempotente'; END IF;

    -- Un échec terminé plus récent empêche de retenir le succès précédent.
    UPDATE recette_auto_alertes SET resolu_le=NULL,resolu_motif=NULL WHERE id=1;
    INSERT INTO recette_auto_runs VALUES (6,1,'failed',now()-interval '1 hour',now()-interval '1 hour'+interval '1 second');
    PERFORM pg_temp.recette_auto_resoudre_alertes_crons();
    IF EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id=1 AND resolu_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Le dernier échec terminé a été masqué';
    END IF;

    -- Ni un succès antérieur à l'alerte, ni une absence de run terminé
    -- ne peuvent résoudre l'incident. Un statut succeeded incomplet non plus.
    DELETE FROM recette_auto_runs WHERE jobid=1 AND status='failed';
    UPDATE recette_auto_alertes SET derniere_occurrence=now()-interval '1 hour' WHERE id=1;
    PERFORM pg_temp.recette_auto_resoudre_alertes_crons();
    IF EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id=1 AND resolu_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Un succès trop ancien a résolu l’alerte';
    END IF;
    DELETE FROM recette_auto_runs WHERE jobid=1 AND status='succeeded';
    INSERT INTO recette_auto_runs VALUES (7,1,'succeeded',now()-interval '30 minutes',NULL);
    PERFORM pg_temp.recette_auto_resoudre_alertes_crons();
    IF EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id=1 AND resolu_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Un run non terminé a résolu l’alerte';
    END IF;

    -- Deux débuts identiques sont départagés par le runid le plus récent.
    INSERT INTO recette_auto_runs VALUES
      (8,1,'succeeded',now()-interval '20 minutes',now()-interval '19 minutes'),
      (9,1,'failed',now()-interval '20 minutes',now()-interval '19 minutes');
    PERFORM pg_temp.recette_auto_resoudre_alertes_crons();
    IF EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id=1 AND resolu_le IS NOT NULL) THEN
      RAISE EXCEPTION 'Un succès ex aequo a masqué le dernier échec';
    END IF;

    -- Les autres tâches conservent leur reprise normale après succès.
    UPDATE recette_auto_runs SET status='succeeded',end_time=now()+interval '1 second' WHERE runid=5;
    PERFORM pg_temp.recette_auto_resoudre_alertes_crons();
    IF NOT EXISTS (SELECT 1 FROM recette_auto_alertes WHERE id=2 AND resolu_le IS NOT NULL) THEN
      RAISE EXCEPTION 'La reprise des autres crons est cassée';
    END IF;

    -- Un sub NULL est précisément le contexte cron autorisé : utiliser un
    -- utilisateur non administrateur, sans modifier la garde de production.
    PERFORM set_config('request.jwt.claim.sub', '69000000-0000-4000-8000-000000000097', true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', '{"sub":"69000000-0000-4000-8000-000000000097","role":"authenticated"}', true);
    BEGIN
      PERFORM pg_temp.recette_auto_resoudre_alertes_crons();
    EXCEPTION WHEN insufficient_privilege THEN v_rejete := true;
    END;
    IF NOT v_rejete THEN RAISE EXCEPTION 'Garde cron/admin perdue'; END IF;

    IF has_function_privilege('anon','public.fn_auto_resoudre_alertes_crons()','EXECUTE')
      OR has_function_privilege('authenticated','public.fn_auto_resoudre_alertes_crons()','EXECUTE')
      OR NOT has_function_privilege('service_role','public.fn_auto_resoudre_alertes_crons()','EXECUTE') THEN
      RAISE EXCEPTION 'ACL auto-résolution modifiées';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc
      WHERE oid='public.fn_auto_resoudre_alertes_crons()'::regprocedure AND prosecdef
        AND pg_get_userbyid(proowner)='postgres' AND proconfig=ARRAY['search_path=public, extensions']) THEN
      RAISE EXCEPTION 'Contexte SECURITY DEFINER modifié';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
        ON p.oid='public.fn_auto_resoudre_alertes_crons()'::regprocedure
      WHERE i.signature='fn_auto_resoudre_alertes_crons()' AND i.definition_md5=md5(p.prosrc)
    ) THEN RAISE EXCEPTION 'Empreinte inventaire non actualisée'; END IF;

    RAISE EXCEPTION 'ROLLBACK_AUTO_RESOLUTION' USING ERRCODE='ZX231';
  EXCEPTION WHEN SQLSTATE 'ZX231' THEN NULL;
  END;
END;
$test$;
ROLLBACK;

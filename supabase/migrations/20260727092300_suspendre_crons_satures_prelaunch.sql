-- Hotfix App Review 27/07/2026.
--
-- Ces appels pg_net étaient soit non authentifiés, soit en échec 401/403,
-- avec des exécutions d'environ une minute qui se chevauchaient. Ils
-- saturaient la base au point de faire expirer fn_get_my_role juste après une
-- authentification réussie. Aucun de ces traitements n'est requis pour servir
-- l'app ou pour contacter un utilisateur ; les traitements d'acquisition
-- restent en mode silencieux et pourront être replanifiés après correction de
-- leur authentification de service.
DO $cron$
DECLARE
  v_job record;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension
    WHERE extname = 'pg_cron'
  ) THEN
    RETURN;
  END IF;

  FOR v_job IN
    SELECT jobid
    FROM cron.job
    WHERE jobname IN (
      'warm-edge-functions',
      'jolene_process_externalisations',
      'enrich-prospects-soignant',
      'jolene_sourcing_rpps_watchdog',
      'escrow-release'
    )
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron indisponible : suspension différée';
END;
$cron$;

-- L'enrichissement Annuaire Santé reste strictement silencieux : il complète
-- des fiches internes et n'envoie aucun message. Les anciens jobs sont recréés
-- après le correctif Edge qui supprime le count exact de la file RPPS (plus de
-- 1,6 M de lignes) et utilise l'index partiel d'attente.
DO $cron$
DECLARE
  v_job record;
BEGIN
  FOR v_job IN
    SELECT jobid
    FROM cron.job
    WHERE jobname IN ('enrich-prospects-etab', 'enrich-prospects-soignant')
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;

  PERFORM cron.schedule(
    'enrich-prospects-etab',
    '*/2 * * * *',
    $job$
      SELECT net.http_post(
        url := rtrim((
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'supabase_url'
          LIMIT 1
        ), '/') || '/functions/v1/enrich-prospects-annuaire',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            SELECT decrypted_secret
            FROM vault.decrypted_secrets
            WHERE name = 'service_role_key'
            LIMIT 1
          )
        ),
        body := '{"cible":"ETABLISSEMENT","limite":50}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );

  PERFORM cron.schedule(
    'enrich-prospects-soignant',
    '1-59/2 * * * *',
    $job$
      SELECT net.http_post(
        url := rtrim((
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'supabase_url'
          LIMIT 1
        ), '/') || '/functions/v1/enrich-prospects-annuaire',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            SELECT decrypted_secret
            FROM vault.decrypted_secrets
            WHERE name = 'service_role_key'
            LIMIT 1
          )
        ),
        body := '{"cible":"SOIGNANT","limite":50}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron ou vault indisponible : enrichissement non planifie';
END;
$cron$;

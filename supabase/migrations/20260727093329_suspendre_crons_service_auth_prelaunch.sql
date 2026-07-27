-- Les appels Edge utilisant le secret de service Vault sont temporairement
-- suspendus tant que SB_SECRET_KEY n'est pas synchronisé côté Edge Functions.
-- En pré-lancement, aucune transaction réelle ni aucun envoi automatique ne
-- doit dépendre de ces jobs en échec.
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
      'process-stripe-refunds-15min',
      'email-cron-hourly-immediate',
      'email-cron-daily',
      'escrow-debit-echeance',
      'enrich-prospects-etab'
    )
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron indisponible : suspension différée';
END;
$cron$;

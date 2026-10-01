-- Source LIVE production relue le 01/10/2026 ; md5(prosrc) 068f255587c15c2950d9db8a6f7ead83.
-- pg_cron 1.6.4 écrit connecting/sending sans start_time/end_time avant running.
-- Aucune résolution d'alerte ni modification de cadence ou de privilège.
DO $preflight$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_check_crons_health()'::regprocedure)
    IS DISTINCT FROM '068f255587c15c2950d9db8a6f7ead83' THEN
    RAISE EXCEPTION 'fn_check_crons_health a changé : relire la définition LIVE';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_check_crons_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_results jsonb := '[]'::jsonb;
  v_cron record;
  v_intervalle_attendu interval;
  v_retard boolean;
  v_alertes_emises integer := 0;
BEGIN
  IF NOT public.fn_est_contexte_cron_ou_admin() THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Accès refusé');
  END IF;

  -- Le cache contient déjà tous les jobs historiques. Cette mise à jour ne
  -- parcourt que les runid ajoutés depuis le dernier appel (index PK natif).
  WITH watermark AS (
    SELECT COALESCE(pg_catalog.max(c.runid), 0) AS runid
    FROM private.cron_job_latest_run_cache c
  ),
  latest_ids AS MATERIALIZED (
    SELECT r.jobid, pg_catalog.max(r.runid) AS runid
    FROM cron.job_run_details r
    CROSS JOIN watermark w
    WHERE r.runid > w.runid
    GROUP BY r.jobid
  )
  INSERT INTO private.cron_job_latest_run_cache AS cache (
    jobid,
    runid,
    start_time,
    end_time,
    status,
    return_message,
    maj_le
  )
  SELECT
    l.jobid,
    d.runid,
    d.start_time,
    d.end_time,
    d.status,
    d.return_message,
    pg_catalog.now()
  FROM latest_ids l
  JOIN cron.job_run_details d ON d.runid = l.runid
  ON CONFLICT (jobid) DO UPDATE
  SET runid = EXCLUDED.runid,
      start_time = EXCLUDED.start_time,
      end_time = EXCLUDED.end_time,
      status = EXCLUDED.status,
      return_message = EXCLUDED.return_message,
      maj_le = EXCLUDED.maj_le
  WHERE EXCLUDED.runid > cache.runid;

  -- pg_cron passe par starting/connecting/sending puis running, avant de
  -- finaliser le même runid. On rafraîchit donc aussi les runid déjà connus,
  -- sinon un appel effectué pendant l'exécution resterait figé sur `running`.
  UPDATE private.cron_job_latest_run_cache AS cache
  SET start_time = d.start_time,
      end_time = d.end_time,
      status = d.status,
      return_message = d.return_message,
      maj_le = pg_catalog.now()
  FROM cron.job_run_details d
  WHERE d.runid = cache.runid
    AND (
      cache.start_time IS DISTINCT FROM d.start_time
      OR cache.end_time IS DISTINCT FROM d.end_time
      OR cache.status IS DISTINCT FROM d.status
      OR cache.return_message IS DISTINCT FROM d.return_message
    );

  FOR v_cron IN
    SELECT
      j.jobid,
      j.jobname,
      j.schedule,
      c.start_time AS dernier_demarrage,
      c.end_time AS dernier_run,
      c.status AS dernier_statut,
      c.return_message AS dernier_message
    FROM cron.job j
    LEFT JOIN private.cron_job_latest_run_cache c ON c.jobid = j.jobid
    WHERE j.active = true
  LOOP
    -- Marge d'alerte = environ 1,5 à 3 périodes selon la fréquence. Les
    -- champs sont interprétés par position afin de couvrir également les
    -- expressions réelles `1-59/5`, `3,18,33,48`, `7 * * * *`, etc.
    v_intervalle_attendu := CASE
      -- Mois explicite : annuel ; jour du mois explicite : mensuel ; jour de
      -- semaine explicite : hebdomadaire. Cet ordre évite de classer un cron
      -- annuel comme mensuel.
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 4) <> '*' THEN interval '370 days'
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 3) <> '*' THEN interval '32 days'
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 5) <> '*' THEN interval '8 days'

      -- Heure `*` : cron intra-horaire ou horaire.
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 2) = '*' THEN
        CASE
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) = '*' THEN interval '5 minutes'
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) LIKE '%/5%' THEN interval '15 minutes'
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) LIKE '%/10%' THEN interval '30 minutes'
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) LIKE '%/15%' THEN interval '45 minutes'
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) LIKE '%/20%' THEN interval '60 minutes'
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) LIKE '%/30%' THEN interval '90 minutes'
          WHEN pg_catalog.split_part(v_cron.schedule, ' ', 1) LIKE '%,%' THEN interval '45 minutes'
          ELSE interval '90 minutes'
        END

      -- Heures répétées dans la journée ; le reste est quotidien, y compris
      -- les listes d'heures telles que `4,5`.
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 2) LIKE '%/2%' THEN interval '3 hours'
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 2) LIKE '%/6%' THEN interval '9 hours'
      WHEN pg_catalog.split_part(v_cron.schedule, ' ', 2) LIKE '%-%/%' THEN interval '12 hours'
      ELSE interval '26 hours'
    END;

    -- Les crons rares encore jamais exécutés ne sont pas faussement signalés.
    -- Un run normalement en cours n'est ni « jamais exécuté », ni en retard :
    -- connecting/sending peuvent avoir start_time et end_time NULL (pg_cron 1.6.4).
    -- Il ne devient tardif que si sa durée mesurable dépasse la fenêtre attendue.
    IF v_cron.dernier_statut IN ('starting', 'connecting', 'sending', 'running') THEN
      v_retard := v_cron.dernier_demarrage IS NOT NULL
        AND v_cron.dernier_demarrage < pg_catalog.now() - v_intervalle_attendu;
    ELSIF v_cron.jobname = 'sync-chorus-status-hourly'
      AND v_cron.dernier_run IS NOT NULL THEN
      v_retard := pg_catalog.now() >
        private.fn_echeance_cron_chorus(v_cron.schedule, v_cron.dernier_run);
    ELSE
      v_retard := (
        v_cron.dernier_run IS NOT NULL
        AND v_cron.dernier_run < pg_catalog.now() - v_intervalle_attendu
      ) OR (
        v_cron.dernier_run IS NULL
        AND v_intervalle_attendu <= interval '2 days'
      );
    END IF;

    IF v_cron.dernier_statut = 'failed' THEN
      PERFORM public.fn_emettre_alerte_monitoring(
        'CRON_FAILED',
        'CRITICAL',
        v_cron.jobname,
        pg_catalog.format(
          'Cron "%s" a échoué : %s',
          v_cron.jobname,
          COALESCE(pg_catalog.substring(v_cron.dernier_message, 1, 200), '?')
        ),
        pg_catalog.jsonb_build_object(
          'jobid', v_cron.jobid,
          'schedule', v_cron.schedule,
          'dernier_run', v_cron.dernier_run
        )
      );
      v_alertes_emises := v_alertes_emises + 1;
    ELSIF v_retard AND v_cron.jobname NOT IN ('calculer-bfa-annuel') THEN
      PERFORM public.fn_emettre_alerte_monitoring(
        'CRON_RETARD',
        'WARNING',
        v_cron.jobname,
        pg_catalog.format(
          'Cron "%s" en retard (dernier run : %s)',
          v_cron.jobname,
          COALESCE(v_cron.dernier_run::text, 'jamais')
        ),
        pg_catalog.jsonb_build_object(
          'jobid', v_cron.jobid,
          'schedule', v_cron.schedule,
          'dernier_run', v_cron.dernier_run
        )
      );
      v_alertes_emises := v_alertes_emises + 1;
    END IF;

    v_results := v_results || pg_catalog.jsonb_build_object(
      'jobid', v_cron.jobid,
      'jobname', v_cron.jobname,
      'schedule', v_cron.schedule,
      'dernier_demarrage', v_cron.dernier_demarrage,
      'dernier_run', v_cron.dernier_run,
      'dernier_statut', v_cron.dernier_statut,
      'retard', v_retard,
      'echec', v_cron.dernier_statut = 'failed'
    );
  END LOOP;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'crons', v_results,
    'alertes_emises', v_alertes_emises
  );
END;
$function$;

UPDATE private.security_definer_inventory i
SET definition_md5 = md5(p.prosrc), recense_le = now()
FROM pg_proc p
WHERE p.oid = 'public.fn_check_crons_health()'::regprocedure
  AND i.signature = 'fn_check_crons_health()';

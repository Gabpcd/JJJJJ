-- Incident 02/11/2026 (01:34 → 03:45 UTC) : le contrôle des crons Edge
-- joignait private.cron_edge_execution_log à net._http_response sur `id`,
-- colonne SANS index côté pg_net (seul `created` est indexé). Chaque passage
-- (toutes les 5 min) balayait la table entière (148 Mo de réponses sur 6 h),
-- dépassait le statement_timeout de 120 s et monopolisait le CPU partagé de
-- l'instance : les autres crons tombaient en « job startup timeout », les RPC
-- de la CI expiraient (global setup Playwright, 57014) et un simple
-- `count(*)` sur notifications prenait 27 s. Mettre le job en pause a rendu la
-- base réactive en moins d'une minute (0,34 s pour la même requête).
--
-- Définition de départ : LIVE (pg_get_functiondef du 02/11/2026), identique à
-- 20260729121442 ; seule la jointure change. Une réponse pg_net est insérée
-- (`created` = now()) après la demande, au plus tard timeout 55 s + file ;
-- le contrôleur attend lui-même 10 min avant de conclure. La fenêtre
-- [demande_le - 1 min, demande_le + 15 min] est donc toujours englobante et
-- permet un parcours par _http_response_created_idx au lieu d'un balayage.

CREATE OR REPLACE FUNCTION private.fn_controler_crons_edge_critiques()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_run record;
  v_ok integer := 0;
  v_echecs integer := 0;
  v_attente integer := 0;
BEGIN
  FOR v_run IN
    SELECT l.request_id,
           l.job_name,
           l.demande_le,
           r.status_code,
           r.timed_out,
           r.error_msg
      FROM private.cron_edge_execution_log l
      -- net._http_response n'a pas d'index sur id : borner `created` autour de
      -- la demande rend la jointure indexable (incident 02/11/2026).
      LEFT JOIN net._http_response r
        ON r.id = l.request_id
       AND r.created >= l.demande_le - interval '1 minute'
       AND r.created <  l.demande_le + interval '15 minutes'
     WHERE l.controle_le IS NULL
       -- Une réponse déjà disponible peut être contrôlée immédiatement par le
       -- workflow post-déploiement. Sans réponse, on attend 30 secondes avant
       -- de conclure à un incident de transport.
       AND (
         r.id IS NOT NULL
         OR l.demande_le < now() - interval '30 seconds'
       )
     ORDER BY l.demande_le
     LIMIT 200
  LOOP
    IF v_run.status_code IS NULL
       AND v_run.demande_le > now() - interval '10 minutes' THEN
      v_attente := v_attente + 1;
      CONTINUE;
    END IF;

    UPDATE private.cron_edge_execution_log
       SET controle_le = now(),
           statut_http = v_run.status_code,
           erreur_transport = left(v_run.error_msg, 500)
     WHERE request_id = v_run.request_id;

    IF v_run.status_code BETWEEN 200 AND 299
       AND COALESCE(v_run.timed_out, false) IS FALSE
       AND v_run.error_msg IS NULL THEN
      v_ok := v_ok + 1;
    ELSE
      v_echecs := v_echecs + 1;
      PERFORM public.fn_emettre_alerte_monitoring(
        'CRON_EDGE_HTTP_FAILED',
        'CRITICAL',
        v_run.job_name,
        format(
          'Le cron Edge "%s" a échoué (HTTP %s, transport=%s)',
          v_run.job_name,
          COALESCE(v_run.status_code::text, 'aucune réponse'),
          COALESCE(left(v_run.error_msg, 160), 'sans détail')
        ),
        jsonb_build_object(
          'request_id', v_run.request_id,
          'status_code', v_run.status_code,
          'timed_out', v_run.timed_out,
          'demande_le', v_run.demande_le
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', v_echecs = 0,
    'ok', v_ok,
    'echecs', v_echecs,
    'en_attente', v_attente
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_controler_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;

-- Réactiver le contrôle mis en pause pendant l'incident, uniquement là où les
-- crons Edge critiques sont effectivement activés (prod) : une base de preview
-- ou un environnement où 20260925111647 les a laissés inactifs reste inchangé.
DO $cron$
DECLARE
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RETURN;
  END IF;

  SELECT j.jobid INTO v_job_id
    FROM cron.job j
   WHERE j.jobname = 'jolene-monitor-crons-edge-critiques'
     AND j.active = false
     AND EXISTS (
       SELECT 1 FROM cron.job e
        WHERE e.jobname = 'email-cron-hourly-immediate'
          AND e.active = true
     );

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.alter_job(job_id := v_job_id, active := true);
  END IF;
END
$cron$;

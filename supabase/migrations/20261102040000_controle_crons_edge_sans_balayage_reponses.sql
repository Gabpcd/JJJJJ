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
-- 20260729121442. Deux changements :
--   1. jointure bornée. Une réponse pg_net est insérée (`created` = now())
--      après la demande, au plus tard timeout 55 s + file ; le contrôleur
--      attend lui-même 10 min avant de conclure. La fenêtre
--      [demande_le - 1 min, demande_le + 15 min) est donc toujours englobante
--      et permet un parcours par _http_response_created_idx ;
--   2. verrou du gap TTL (revue B8 de la PR #1105). pg_net purge
--      net._http_response après `pg_net.ttl` (6 h). Une demande plus ancienne
--      sans réponse n'est pas un échec de transport, elle est incontrôlable :
--      elle est marquée explicitement (`erreur_transport` NON_CONTROLABLE,
--      compteur `non_controlables`), jamais comptée en `echecs` ni remontée en
--      alerte CRITICAL « aucune réponse ». Sans ce verrou, tout arriéré plus
--      vieux que le TTL (pause du contrôleur, panne) produirait de fausses
--      alertes et ferait échouer le gate `.echecs == 0` de deploy-supabase.

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
  v_non_controlables integer := 0;
  -- Durée de rétention des réponses pg_net (défaut de l'extension : 6 h).
  v_ttl interval := COALESCE(
    NULLIF(pg_catalog.current_setting('pg_net.ttl', true), '')::interval,
    interval '6 hours'
  );
BEGIN
  FOR v_run IN
    SELECT l.request_id,
           l.job_name,
           l.demande_le,
           r.status_code,
           r.timed_out,
           r.error_msg,
           (r.id IS NOT NULL) AS reponse_presente
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

    -- Demande plus ancienne que la rétention pg_net et sans réponse : la
    -- réponse a été purgée, le contrôle est impossible. Marquage explicite,
    -- sans alerte ni échec (verrou du gap TTL, voir en-tête).
    IF NOT v_run.reponse_presente
       AND v_run.demande_le < now() - v_ttl THEN
      UPDATE private.cron_edge_execution_log
         SET controle_le = now(),
             statut_http = NULL,
             erreur_transport = format(
               'NON_CONTROLABLE: réponse pg_net purgée (pg_net.ttl = %s), demande antérieure à %s',
               v_ttl, now() - v_ttl
             )
       WHERE request_id = v_run.request_id;
      v_non_controlables := v_non_controlables + 1;
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
    'en_attente', v_attente,
    'non_controlables', v_non_controlables
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_controler_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;

-- Acquitter l'arriéré accumulé pendant l'incident puis la pause du contrôleur
-- (job 123 inactif depuis 03:41 UTC) : ~530 lignes au 02/11 07:20 UTC, +90/h.
-- Contrôlées a posteriori, les plus anciennes auraient perdu leur réponse
-- (purge pg_net 6 h) → fausses alertes CRITICAL « aucune réponse », et les
-- 17 échecs réels de la fenêtre d'incident (déjà instruits dans
-- docs/incidents/2026-11-02-cron-controle-edge-cpu.md) feraient échouer le gate
-- `.echecs == 0` de deploy-supabase, qui laisse alors les crons critiques en
-- pause. Le statut HTTP et l'erreur de transport sont conservés quand la
-- réponse existe encore ; seules les lignes en attente au moment de la
-- migration sont concernées (les sondes du déploiement sont postérieures).
DO $arriere$
DECLARE
  v_n integer;
BEGIN
  IF pg_catalog.to_regclass('private.cron_edge_execution_log') IS NULL
     OR pg_catalog.to_regclass('net._http_response') IS NULL THEN
    RETURN;
  END IF;

  UPDATE private.cron_edge_execution_log l
     SET controle_le = now(),
         statut_http = s.status_code,
         erreur_transport = left(
           'NON_CONTROLE: contrôleur en pause (incident CPU 02/11/2026), acquitté par 20261102040000'
           || CASE WHEN s.reponse_presente THEN '' ELSE ' ; réponse pg_net purgée' END
           || COALESCE(' ; transport=' || s.error_msg, ''),
           500)
    FROM (
      SELECT l2.request_id,
             r.status_code,
             r.error_msg,
             (r.id IS NOT NULL) AS reponse_presente
        FROM private.cron_edge_execution_log l2
        LEFT JOIN net._http_response r
          ON r.id = l2.request_id
         AND r.created >= l2.demande_le - interval '1 minute'
         AND r.created <  l2.demande_le + interval '15 minutes'
       WHERE l2.controle_le IS NULL
         AND l2.demande_le < now()
    ) s
   WHERE s.request_id = l.request_id
     AND l.controle_le IS NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'Contrôle des crons Edge : arriéré acquitté, % ligne(s).', v_n;
END
$arriere$;

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

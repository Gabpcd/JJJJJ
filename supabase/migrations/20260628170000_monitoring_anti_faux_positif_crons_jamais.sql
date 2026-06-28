-- Monitoring — anti faux-positifs sur crons « jamais exécutés ».
--
-- Le monitoring restauré (20260628150000) a immédiatement émis des alertes
-- CRON_RETARD « dernier run : jamais » pour des crons MENSUELS / ANNUELS qui
-- n'ont simplement pas encore atteint leur première date d'exécution
-- (auto-facturation-mensuelle `0 2 1 * *`, recalculer-paliers-commission
-- `0 1 1 * *`, calculer-bfa-annuel `0 3 2 1 *`). Ce bruit de faux positifs
-- (CRITICAL/WARNING) noie les vraies alertes → alert fatigue, exactement ce qui
-- avait laissé le monitoring mourir en silence.
--
-- Fix : un cron JAMAIS exécuté n'est « en retard » que s'il est assez fréquent
-- pour avoir déjà dû tourner (intervalle attendu <= 2 jours). Les crons basse
-- fréquence (hebdo/mensuel/annuel) sans run ne déclenchent plus d'alerte tant
-- qu'ils n'ont pas eu leur première échéance. Un échec réel reste capté par la
-- branche 'failed' dès la première exécution.
--
-- Déjà appliqué en prod via MCP. Housekeeping associé (one-time, hors migration) :
-- résolution des alertes stale/faux-positifs déjà émises.

CREATE OR REPLACE FUNCTION public.fn_check_crons_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_results jsonb := '[]'::jsonb; v_cron RECORD; v_dernier_run TIMESTAMPTZ;
  v_dernier_statut TEXT; v_dernier_msg TEXT; v_intervalle_attendu INTERVAL;
  v_retard BOOLEAN; v_alertes_emises INT := 0;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  FOR v_cron IN SELECT jobid, jobname, schedule FROM cron.job WHERE active = true LOOP
    SELECT end_time, status, return_message INTO v_dernier_run, v_dernier_statut, v_dernier_msg
    FROM cron.job_run_details WHERE jobid = v_cron.jobid ORDER BY end_time DESC LIMIT 1;
    v_intervalle_attendu := CASE
      WHEN v_cron.schedule LIKE '*/5%' THEN INTERVAL '15 minutes'
      WHEN v_cron.schedule LIKE '*/10%' THEN INTERVAL '30 minutes'
      WHEN v_cron.schedule LIKE '*/15%' THEN INTERVAL '45 minutes'
      WHEN v_cron.schedule LIKE '0 * * * *' THEN INTERVAL '90 minutes'
      WHEN v_cron.schedule LIKE '15 * * * *' THEN INTERVAL '90 minutes'
      WHEN v_cron.schedule LIKE '0 % * * *' THEN INTERVAL '26 hours'
      WHEN v_cron.schedule LIKE '0 % % * *' THEN INTERVAL '32 days'
      WHEN v_cron.schedule LIKE '0 % * * 0' THEN INTERVAL '8 days'
      ELSE INTERVAL '40 days' END;
    -- Un cron JAMAIS exécuté (v_dernier_run IS NULL) n'est « en retard » que s'il est
    -- assez fréquent pour avoir déjà dû tourner (intervalle <= 2 jours). Sinon (mensuel,
    -- annuel, hebdo) c'est normal qu'il n'ait pas encore tourné après sa création.
    v_retard := (v_dernier_run IS NOT NULL AND v_dernier_run < NOW() - v_intervalle_attendu)
             OR (v_dernier_run IS NULL AND v_intervalle_attendu <= INTERVAL '2 days');
    IF v_dernier_statut = 'failed' THEN
      PERFORM fn_emettre_alerte_monitoring('CRON_FAILED', 'CRITICAL', v_cron.jobname,
        format('Cron "%s" a échoué : %s', v_cron.jobname, COALESCE(SUBSTRING(v_dernier_msg, 1, 200), '?')),
        jsonb_build_object('jobid', v_cron.jobid, 'schedule', v_cron.schedule, 'dernier_run', v_dernier_run));
      v_alertes_emises := v_alertes_emises + 1;
    ELSIF v_retard AND v_cron.jobname NOT IN ('calculer-bfa-annuel') THEN
      PERFORM fn_emettre_alerte_monitoring('CRON_RETARD', 'WARNING', v_cron.jobname,
        format('Cron "%s" en retard (dernier run : %s)', v_cron.jobname, COALESCE(v_dernier_run::text, 'jamais')),
        jsonb_build_object('jobid', v_cron.jobid, 'schedule', v_cron.schedule, 'dernier_run', v_dernier_run));
      v_alertes_emises := v_alertes_emises + 1;
    END IF;
    v_results := v_results || jsonb_build_object('jobid', v_cron.jobid, 'jobname', v_cron.jobname,
      'schedule', v_cron.schedule, 'dernier_run', v_dernier_run, 'dernier_statut', v_dernier_statut,
      'retard', v_retard, 'echec', v_dernier_statut = 'failed');
  END LOOP;
  RETURN jsonb_build_object('success', true, 'crons', v_results, 'alertes_emises', v_alertes_emises);
END;
$function$;

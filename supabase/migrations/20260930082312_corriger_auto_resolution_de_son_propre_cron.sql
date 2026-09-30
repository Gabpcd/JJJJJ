-- Définition LIVE relue le 30/09/2026 : md5 7783733961ba50b6bd0c8b80c5645f32.
-- Aucun acquittement de données historiques dans la migration ; le cron
-- appliquera normalement le même cycle de résolution aux succès démontrés.
DO $guard$
BEGIN
  IF md5(pg_get_functiondef('public.fn_auto_resoudre_alertes_crons()'::regprocedure))
       <> '7783733961ba50b6bd0c8b80c5645f32' THEN
    RAISE EXCEPTION 'La définition LIVE auto-résolution a changé : réexaminer avant migration';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.fn_auto_resoudre_alertes_crons()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_alerte RECORD; v_last_status text; v_last_run timestamptz; v_job_exists boolean; v_n int := 0;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  FOR v_alerte IN SELECT id, source, derniere_occurrence FROM alertes_systeme
                  WHERE resolu_le IS NULL AND type_alerte LIKE 'CRON%' LOOP
    SELECT true, d.status, d.start_time INTO v_job_exists, v_last_status, v_last_run
    FROM cron.job j
    LEFT JOIN LATERAL (
      SELECT status, start_time
      FROM cron.job_run_details
      WHERE jobid = j.jobid
        -- Pendant sa propre exécution, pg_cron affiche toujours « running ».
        -- Seul ce job utilise donc sa dernière exécution TERMINÉE : un ancien
        -- échec ne disparaît qu'après un succès ultérieur, jamais sur « running ».
        AND (j.jobname <> 'jolene_auto_resoudre_alertes'
          OR (status IN ('succeeded', 'failed') AND end_time IS NOT NULL))
      ORDER BY start_time DESC, runid DESC
      LIMIT 1
    ) d ON true
    WHERE j.jobname = v_alerte.source
    LIMIT 1;

    IF v_job_exists AND v_last_status = 'succeeded' AND v_last_run > v_alerte.derniere_occurrence THEN
      UPDATE alertes_systeme SET resolu_le = now(), resolu_motif = 'auto: cron repassé vert' WHERE id = v_alerte.id;
      v_n := v_n + 1;
    ELSIF v_job_exists IS NULL AND v_alerte.derniere_occurrence < now() - INTERVAL '72 hours' THEN
      -- cron décommissionné (plus dans cron.job) + fenêtre de grâce écoulée
      UPDATE alertes_systeme SET resolu_le = now(), resolu_motif = 'auto: cron décommissionné (orphelin, >72h)' WHERE id = v_alerte.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'resolues', v_n);
END;
$function$;


UPDATE private.security_definer_inventory
SET definition_md5 = md5(p.prosrc)
FROM pg_proc p
WHERE p.oid = 'public.fn_auto_resoudre_alertes_crons()'::regprocedure
  AND signature = 'fn_auto_resoudre_alertes_crons()';

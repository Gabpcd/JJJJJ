BEGIN;

-- Le précédent health-check relisait toute la table cron.job_run_details une
-- fois par cron actif (52 scans en production). La table appartient à
-- supabase_admin, donc une migration applicative ne peut pas lui ajouter
-- d'index. Cette version exacte effectue un seul scan, agrège le dernier runid
-- de chaque job puis rejoint la clé primaire existante. Mesuré à ~78 ms sur
-- 168 000 exécutions, contre plus de 15 s auparavant.
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

  FOR v_cron IN
    WITH latest_ids AS MATERIALIZED (
      SELECT r.jobid, pg_catalog.max(r.runid) AS runid
      FROM cron.job_run_details r
      GROUP BY r.jobid
    )
    SELECT
      j.jobid,
      j.jobname,
      j.schedule,
      d.end_time AS dernier_run,
      d.status AS dernier_statut,
      d.return_message AS dernier_message
    FROM cron.job j
    LEFT JOIN latest_ids l ON l.jobid = j.jobid
    LEFT JOIN cron.job_run_details d ON d.runid = l.runid
    WHERE j.active = true
  LOOP
    v_intervalle_attendu := CASE
      WHEN v_cron.schedule LIKE '*/5%' THEN interval '15 minutes'
      WHEN v_cron.schedule LIKE '*/10%' THEN interval '30 minutes'
      WHEN v_cron.schedule LIKE '*/15%' THEN interval '45 minutes'
      WHEN v_cron.schedule LIKE '0 * * * *' THEN interval '90 minutes'
      WHEN v_cron.schedule LIKE '15 * * * *' THEN interval '90 minutes'
      WHEN v_cron.schedule LIKE '0 % * * *' THEN interval '26 hours'
      WHEN v_cron.schedule LIKE '0 % % * *' THEN interval '32 days'
      WHEN v_cron.schedule LIKE '0 % * * 0' THEN interval '8 days'
      ELSE interval '40 days'
    END;

    -- Les crons rares encore jamais exécutés ne sont pas faussement signalés.
    -- Un échec réel reste détecté dès la première exécution.
    v_retard := (
      v_cron.dernier_run IS NOT NULL
      AND v_cron.dernier_run < pg_catalog.now() - v_intervalle_attendu
    ) OR (
      v_cron.dernier_run IS NULL
      AND v_intervalle_attendu <= interval '2 days'
    );

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

REVOKE ALL ON FUNCTION public.fn_check_crons_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_check_crons_health() TO service_role;

COMMENT ON FUNCTION public.fn_check_crons_health() IS
  'Contrôle exact des crons actifs en un seul scan de job_run_details; réservé au contexte cron ou administrateur.';

INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
SELECT
  'fn_check_crons_health()',
  'SERVICE_ONLY_REVOQUE',
  pg_catalog.md5(p.prosrc),
  'Health-check interne exact en un scan global des exécutions cron; accès réservé au service_role et aux appels administrateur imbriqués.',
  pg_catalog.now()
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.fn_check_crons_health()'::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_fn_check_crons_health_inventory$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM private.security_definer_inventory i
    JOIN pg_catalog.pg_proc p
      ON p.oid = 'public.fn_check_crons_health()'::pg_catalog.regprocedure
    WHERE i.signature = 'fn_check_crons_health()'
      AND i.definition_md5 = pg_catalog.md5(p.prosrc)
  ) THEN
    RAISE EXCEPTION
      'Inventaire SECURITY DEFINER non synchronisé pour fn_check_crons_health()';
  END IF;
END;
$assert_fn_check_crons_health_inventory$;

COMMIT;

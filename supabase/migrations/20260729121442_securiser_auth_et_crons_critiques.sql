-- Authentification et exploitation des crons Edge critiques.
--
-- Incident constaté le 29/07/2026 :
--   * pg_cron envoyait le secret Vault `service_role_key` ;
--   * certaines Edge Functions s'arrêtaient sur SUPABASE_SECRET_KEY avant de
--     comparer Vault ;
--   * `litige-escalation-cron` répondait donc 401 tandis que pg_cron déclarait
--     le simple enqueue pg_net « succeeded ».
--
-- Cette migration crée une identité d'automatisation dédiée, recapture les
-- huit jobs indispensables mais les laisse INACTIFS. Ils ne pourront être
-- activés qu'après déploiement des fonctions, sondes d'authentification sans
-- effet métier et confirmation explicite.

BEGIN;

CREATE SCHEMA IF NOT EXISTS private AUTHORIZATION postgres;

DO $vault_secret$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM vault.decrypted_secrets
     WHERE name = 'cron_automations_key'
  ) THEN
    PERFORM vault.create_secret(
      'jolene_cron_' || encode(extensions.gen_random_bytes(32), 'hex'),
      'cron_automations_key',
      'Secret dédié aux appels pg_cron vers les Edge Functions Jolene'
    );
  END IF;
END
$vault_secret$;

CREATE OR REPLACE FUNCTION private.fn_lire_secret_cron_automations()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT ds.decrypted_secret
    FROM vault.decrypted_secrets ds
   WHERE ds.name = 'cron_automations_key'
   LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION private.fn_lire_secret_cron_automations()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lire_secret_cron_automations()
  TO service_role;

-- Wrapper PostgREST SECURITY INVOKER : la lecture privilégiée du Vault reste
-- dans private et n'ajoute pas un SECURITY DEFINER à la surface API.
GRANT USAGE ON SCHEMA private TO service_role;
CREATE OR REPLACE FUNCTION public.fn_lire_secret_cron_automations()
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_lire_secret_cron_automations();
$function$;

REVOKE ALL ON FUNCTION public.fn_lire_secret_cron_automations()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lire_secret_cron_automations()
  TO service_role;
COMMENT ON FUNCTION public.fn_lire_secret_cron_automations() IS
  'Wrapper service_role vers le secret Vault cron privé ; jamais accessible au client.';

CREATE TABLE IF NOT EXISTS private.cron_edge_execution_log (
  request_id bigint PRIMARY KEY,
  job_name text NOT NULL,
  endpoint text NOT NULL,
  est_sonde_auth boolean NOT NULL DEFAULT false,
  demande_le timestamptz NOT NULL DEFAULT now(),
  controle_le timestamptz,
  statut_http integer,
  erreur_transport text,
  CONSTRAINT cron_edge_execution_log_job_non_vide
    CHECK (btrim(job_name) <> ''),
  CONSTRAINT cron_edge_execution_log_endpoint_non_vide
    CHECK (btrim(endpoint) <> '')
);

CREATE INDEX IF NOT EXISTS idx_cron_edge_execution_log_a_controler
  ON private.cron_edge_execution_log (demande_le)
  WHERE controle_le IS NULL;

REVOKE ALL ON TABLE private.cron_edge_execution_log
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE private.cron_edge_execution_log TO service_role;

CREATE OR REPLACE FUNCTION private.fn_appeler_edge_critique(
  p_job_name text,
  p_est_sonde_auth boolean DEFAULT false
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_endpoint text;
  v_body jsonb := '{}'::jsonb;
  v_url text;
  v_secret text;
  v_request_id bigint;
BEGIN
  -- Allowlist fermée : aucun endpoint arbitraire ni SSRF n'est possible.
  CASE p_job_name
    WHEN 'litige-escalation-cron' THEN
      v_endpoint := 'litige-escalation-cron';
    WHEN 'email-cron-hourly-immediate' THEN
      v_endpoint := 'email-cron';
      v_body := '{"mode":"hourly"}'::jsonb;
    WHEN 'email-cron-daily' THEN
      v_endpoint := 'email-cron';
      v_body := '{"mode":"daily"}'::jsonb;
    WHEN 'process-stripe-refunds-15min' THEN
      v_endpoint := 'process-stripe-refunds';
    WHEN 'escrow-debit-echeance' THEN
      v_endpoint := 'escrow-debit-echeance';
    WHEN 'escrow-release' THEN
      v_endpoint := 'escrow-release';
    WHEN 'jolene_process_externalisations' THEN
      v_endpoint := 'process-externalisation-actions';
    WHEN 'weekly-invoicing-cron' THEN
      v_endpoint := 'weekly-invoicing-cron';
    ELSE
      RAISE EXCEPTION 'Job Edge critique non autorisé : %', p_job_name
        USING ERRCODE = '22023';
  END CASE;

  SELECT rtrim(ds.decrypted_secret, '/')
    INTO v_url
    FROM vault.decrypted_secrets ds
   WHERE ds.name = 'supabase_url'
   LIMIT 1;

  SELECT ds.decrypted_secret
    INTO v_secret
    FROM vault.decrypted_secrets ds
   WHERE ds.name = 'cron_automations_key'
   LIMIT 1;

  IF v_url IS NULL OR v_url = '' OR v_secret IS NULL OR v_secret = '' THEN
    RAISE EXCEPTION 'Configuration Vault cron incomplète'
      USING ERRCODE = '55000';
  END IF;

  SELECT net.http_post(
    url := v_url || '/functions/v1/' || v_endpoint,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-jolene-cron-secret', v_secret,
      'x-jolene-cron-probe',
        CASE WHEN p_est_sonde_auth THEN 'auth-only' ELSE 'execute' END
    ),
    body := v_body,
    timeout_milliseconds := 55000
  ) INTO v_request_id;

  INSERT INTO private.cron_edge_execution_log (
    request_id,
    job_name,
    endpoint,
    est_sonde_auth
  ) VALUES (
    v_request_id,
    p_job_name,
    v_endpoint,
    p_est_sonde_auth
  );

  RETURN v_request_id;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_appeler_edge_critique(text, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_appeler_edge_critique(text, boolean)
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_sonder_crons_edge_critiques()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_job text;
  v_request_id bigint;
  v_result jsonb := '{}'::jsonb;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'litige-escalation-cron',
    'email-cron-hourly-immediate',
    'email-cron-daily',
    'process-stripe-refunds-15min',
    'escrow-debit-echeance',
    'escrow-release',
    'jolene_process_externalisations',
    'weekly-invoicing-cron'
  ]::text[]
  LOOP
    v_request_id := private.fn_appeler_edge_critique(v_job, true);
    v_result := v_result || jsonb_build_object(v_job, v_request_id);
  END LOOP;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_sonder_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_sonder_crons_edge_critiques()
  TO service_role;

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
      LEFT JOIN net._http_response r ON r.id = l.request_id
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
GRANT EXECUTE ON FUNCTION private.fn_controler_crons_edge_critiques()
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_etat_sondes_crons_edge_critiques(
  p_sondes jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_job text;
  v_request_id bigint;
  v_status_code integer;
  v_timed_out boolean;
  v_error_msg text;
  v_ok integer := 0;
  v_echecs integer := 0;
  v_attente integer := 0;
  v_jobs jsonb := '{}'::jsonb;
BEGIN
  IF jsonb_typeof(p_sondes) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Objet de sondes requis' USING ERRCODE = '22023';
  END IF;

  FOREACH v_job IN ARRAY ARRAY[
    'litige-escalation-cron',
    'email-cron-hourly-immediate',
    'email-cron-daily',
    'process-stripe-refunds-15min',
    'escrow-debit-echeance',
    'escrow-release',
    'jolene_process_externalisations',
    'weekly-invoicing-cron'
  ]::text[]
  LOOP
    BEGIN
      v_request_id := NULLIF(p_sondes ->> v_job, '')::bigint;
    EXCEPTION
      WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RAISE EXCEPTION 'Identifiant de sonde invalide pour %', v_job
          USING ERRCODE = '22023';
    END;

    IF v_request_id IS NULL OR NOT EXISTS (
      SELECT 1
        FROM private.cron_edge_execution_log l
       WHERE l.request_id = v_request_id
         AND l.job_name = v_job
         AND l.est_sonde_auth IS TRUE
         AND l.demande_le > now() - interval '30 minutes'
    ) THEN
      RAISE EXCEPTION 'Sonde récente exacte absente pour %', v_job
        USING ERRCODE = '55000';
    END IF;

    SELECT r.status_code, r.timed_out, r.error_msg
      INTO v_status_code, v_timed_out, v_error_msg
      FROM net._http_response r
     WHERE r.id = v_request_id;

    IF NOT FOUND THEN
      v_attente := v_attente + 1;
      v_jobs := v_jobs || jsonb_build_object(
        v_job,
        jsonb_build_object('request_id', v_request_id, 'etat', 'EN_ATTENTE')
      );
    ELSIF v_status_code BETWEEN 200 AND 299
       AND COALESCE(v_timed_out, false) IS FALSE
       AND v_error_msg IS NULL THEN
      v_ok := v_ok + 1;
      v_jobs := v_jobs || jsonb_build_object(
        v_job,
        jsonb_build_object(
          'request_id', v_request_id,
          'etat', 'OK',
          'status_code', v_status_code
        )
      );
    ELSE
      v_echecs := v_echecs + 1;
      v_jobs := v_jobs || jsonb_build_object(
        v_job,
        jsonb_build_object(
          'request_id', v_request_id,
          'etat', 'ECHEC',
          'status_code', v_status_code
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ready', v_attente = 0,
    'success', v_attente = 0 AND v_echecs = 0 AND v_ok = 8,
    'ok', v_ok,
    'echecs', v_echecs,
    'en_attente', v_attente,
    'jobs', v_jobs
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_etat_sondes_crons_edge_critiques(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_etat_sondes_crons_edge_critiques(jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_activer_crons_edge_critiques(
  p_sondes jsonb,
  p_confirmation text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_job text;
  v_job_id bigint;
  v_actives text[] := ARRAY[]::text[];
  v_etat_final jsonb;
BEGIN
  IF p_confirmation IS DISTINCT FROM 'AUTH_PROBES_OK' THEN
    RAISE EXCEPTION 'Confirmation AUTH_PROBES_OK requise'
      USING ERRCODE = '22023';
  END IF;

  IF (
    private.fn_etat_sondes_crons_edge_critiques(p_sondes) ->> 'success'
  )::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Les huit sondes auth exactes ne sont pas toutes en succès'
      USING ERRCODE = '55000';
  END IF;

  FOREACH v_job IN ARRAY ARRAY[
    'litige-escalation-cron',
    'email-cron-hourly-immediate',
    'email-cron-daily',
    'process-stripe-refunds-15min',
    'escrow-debit-echeance',
    'escrow-release',
    'jolene_process_externalisations',
    'weekly-invoicing-cron'
  ]::text[]
  LOOP
    IF NOT EXISTS (
      SELECT 1
        FROM private.cron_edge_execution_log l
        JOIN net._http_response r ON r.id = l.request_id
       WHERE l.request_id = (p_sondes ->> v_job)::bigint
         AND l.job_name = v_job
         AND l.est_sonde_auth IS TRUE
         AND l.demande_le > now() - interval '30 minutes'
         AND r.status_code BETWEEN 200 AND 299
         AND COALESCE(r.timed_out, false) IS FALSE
         AND r.error_msg IS NULL
    ) THEN
      RAISE EXCEPTION 'Sonde auth récente absente ou en échec pour %', v_job
        USING ERRCODE = '55000';
    END IF;

    SELECT j.jobid INTO v_job_id
      FROM cron.job j
     WHERE j.jobname = v_job;
    IF v_job_id IS NULL THEN
      RAISE EXCEPTION 'Job critique absent : %', v_job
        USING ERRCODE = '55000';
    END IF;
    PERFORM cron.alter_job(job_id := v_job_id, active := true);
    v_actives := array_append(v_actives, v_job);
  END LOOP;

  SELECT j.jobid INTO v_job_id
    FROM cron.job j
   WHERE j.jobname = 'jolene-monitor-crons-edge-critiques';
  IF v_job_id IS NULL THEN
    RAISE EXCEPTION 'Monitor cron Edge absent' USING ERRCODE = '55000';
  END IF;
  PERFORM cron.alter_job(job_id := v_job_id, active := true);
  v_actives := array_append(v_actives, 'jolene-monitor-crons-edge-critiques');

  -- Cette vérification s'exécute dans la même transaction que les neuf
  -- alter_job : toute anomalie (y compris acquisition active) annule donc
  -- l'activation complète, sans état partiel.
  v_etat_final := private.fn_etat_activation_crons_edge_critiques();
  IF (v_etat_final ->> 'success')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'État cron final invalide : %', v_etat_final
      USING ERRCODE = '55000';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'jobs_actives', v_actives,
    'etat_final', v_etat_final
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_activer_crons_edge_critiques(jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_activer_crons_edge_critiques(jsonb, text)
  TO service_role;

COMMENT ON FUNCTION private.fn_activer_crons_edge_critiques(jsonb, text) IS
  'Activation explicite post-déploiement : exige les huit identifiants exacts de sondes auth-only HTTP 2xx récentes.';

CREATE OR REPLACE FUNCTION private.fn_etat_activation_crons_edge_critiques()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_critiques text[] := ARRAY[
    'litige-escalation-cron',
    'email-cron-hourly-immediate',
    'email-cron-daily',
    'process-stripe-refunds-15min',
    'escrow-debit-echeance',
    'escrow-release',
    'jolene_process_externalisations',
    'weekly-invoicing-cron',
    'jolene-monitor-crons-edge-critiques'
  ]::text[];
  v_acquisition text[] := ARRAY[
    'warm-edge-functions',
    'jolene_acquisition_brouillons',
    'jolene_sourcing_rpps_hebdo',
    'jolene_sourcing_finess_hebdo',
    'enrich-prospects-etab',
    'enrich-prospects-soignant',
    'jolene_sourcing_rpps_watchdog',
    'jolene_prospection_compteurs_quotidien',
    'jolene_acquisition_bmo_mensuel',
    'jolene_acquisition_boamp_quotidien'
  ]::text[];
  v_actifs text[];
  v_manquants text[];
  v_acquisition_active text[];
BEGIN
  SELECT COALESCE(array_agg(nom ORDER BY nom), ARRAY[]::text[])
    INTO v_actifs
    FROM unnest(v_critiques) AS attendu(nom)
   WHERE EXISTS (
     SELECT 1 FROM cron.job j
      WHERE j.jobname = attendu.nom AND j.active IS TRUE
   );

  SELECT COALESCE(array_agg(nom ORDER BY nom), ARRAY[]::text[])
    INTO v_manquants
    FROM unnest(v_critiques) AS attendu(nom)
   WHERE NOT EXISTS (
     SELECT 1 FROM cron.job j
      WHERE j.jobname = attendu.nom AND j.active IS TRUE
   );

  SELECT COALESCE(array_agg(j.jobname ORDER BY j.jobname), ARRAY[]::text[])
    INTO v_acquisition_active
    FROM cron.job j
   WHERE j.jobname = ANY(v_acquisition)
     AND j.active IS TRUE;

  RETURN jsonb_build_object(
    'success',
      cardinality(v_actifs) = 9
      AND cardinality(v_manquants) = 0
      AND cardinality(v_acquisition_active) = 0,
    'critiques_actifs', to_jsonb(v_actifs),
    'critiques_manquants', to_jsonb(v_manquants),
    'acquisition_active', to_jsonb(v_acquisition_active)
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_etat_activation_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_etat_activation_crons_edge_critiques()
  TO service_role;

-- Barrière de redéploiement : une migration n'est exécutée qu'une fois, donc
-- les jobs activés lors d'un précédent déploiement resteraient autrement
-- actifs pendant le remplacement progressif des Edge Functions. Le workflow
-- appelle cette primitive avant chaque nouveau déploiement de code.
CREATE OR REPLACE FUNCTION private.fn_desactiver_crons_edge_critiques()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_job text;
  v_job_id bigint;
  v_critiques text[] := ARRAY[
    'litige-escalation-cron',
    'email-cron-hourly-immediate',
    'email-cron-daily',
    'process-stripe-refunds-15min',
    'escrow-debit-echeance',
    'escrow-release',
    'jolene_process_externalisations',
    'weekly-invoicing-cron',
    'jolene-monitor-crons-edge-critiques'
  ]::text[];
  v_acquisition text[] := ARRAY[
    'warm-edge-functions',
    'jolene_acquisition_brouillons',
    'jolene_sourcing_rpps_hebdo',
    'jolene_sourcing_finess_hebdo',
    'enrich-prospects-etab',
    'enrich-prospects-soignant',
    'jolene_sourcing_rpps_watchdog',
    'jolene_prospection_compteurs_quotidien',
    'jolene_acquisition_bmo_mensuel',
    'jolene_acquisition_boamp_quotidien'
  ]::text[];
  v_desactives text[] := ARRAY[]::text[];
  v_acquisition_desactivee text[] := ARRAY[]::text[];
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  FOREACH v_job IN ARRAY v_critiques
  LOOP
    v_job_id := NULL;
    SELECT j.jobid
      INTO v_job_id
      FROM cron.job j
     WHERE j.jobname = v_job;

    IF v_job_id IS NULL THEN
      v_manquants := array_append(v_manquants, v_job);
    ELSE
      PERFORM cron.alter_job(job_id := v_job_id, active := false);
      v_desactives := array_append(v_desactives, v_job);
    END IF;
  END LOOP;

  IF cardinality(v_manquants) > 0 THEN
    RAISE EXCEPTION 'Jobs Edge critiques absents avant déploiement : %',
      array_to_string(v_manquants, ', ')
      USING ERRCODE = '55000';
  END IF;

  FOREACH v_job IN ARRAY v_acquisition
  LOOP
    v_job_id := NULL;
    SELECT j.jobid
      INTO v_job_id
      FROM cron.job j
     WHERE j.jobname = v_job;

    IF v_job_id IS NOT NULL THEN
      PERFORM cron.alter_job(job_id := v_job_id, active := false);
      v_acquisition_desactivee :=
        array_append(v_acquisition_desactivee, v_job);
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM cron.job j
     WHERE j.jobname = ANY(v_critiques || v_acquisition)
       AND j.active IS TRUE
  ) THEN
    RAISE EXCEPTION 'Au moins un job interdit reste actif avant déploiement'
      USING ERRCODE = '55000';
  END IF;

  RETURN jsonb_build_object(
    'success', cardinality(v_desactives) = 9,
    'critiques_desactives', to_jsonb(v_desactives),
    'acquisition_desactivee', to_jsonb(v_acquisition_desactivee)
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_desactiver_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_desactiver_crons_edge_critiques()
  TO service_role;

-- Les wrappers publics restent SECURITY INVOKER. PostgREST peut ainsi les
-- exposer au workflow, mais seul service_role possède USAGE sur private et
-- EXECUTE sur les fonctions internes ; anon/authenticated sont explicitement
-- révoqués. Ils n'ajoutent aucun SECURITY DEFINER exposé à l'API.
GRANT USAGE ON SCHEMA private TO service_role;

CREATE OR REPLACE FUNCTION public.fn_ops_sonder_crons_edge_critiques()
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_sonder_crons_edge_critiques();
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_desactiver_crons_edge_critiques()
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_desactiver_crons_edge_critiques();
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_etat_sondes_crons_edge_critiques(
  p_sondes jsonb
) RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_etat_sondes_crons_edge_critiques(p_sondes);
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_controler_crons_edge_critiques()
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_controler_crons_edge_critiques();
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_activer_crons_edge_critiques(
  p_sondes jsonb,
  p_confirmation text
) RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_activer_crons_edge_critiques(p_sondes, p_confirmation);
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_etat_activation_crons_edge_critiques()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_etat_activation_crons_edge_critiques();
$function$;

REVOKE ALL ON FUNCTION public.fn_ops_sonder_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ops_desactiver_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ops_etat_sondes_crons_edge_critiques(jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ops_controler_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ops_activer_crons_edge_critiques(jsonb, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_ops_etat_activation_crons_edge_critiques()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_ops_sonder_crons_edge_critiques()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_ops_desactiver_crons_edge_critiques()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_ops_etat_sondes_crons_edge_critiques(jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_ops_controler_crons_edge_critiques()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_ops_activer_crons_edge_critiques(jsonb, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_ops_etat_activation_crons_edge_critiques()
  TO service_role;

-- Recapture idempotente : aucun appel HTTP ne peut partir avant l'activation
-- explicite, car chaque job est rendu inactif dans la même transaction.
DO $cron_jobs$
DECLARE
  v_spec record;
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RAISE NOTICE 'pg_cron absent : recapture des jobs différée';
    RETURN;
  END IF;

  FOR v_spec IN
    SELECT *
      FROM (VALUES
        ('litige-escalation-cron', '0 7 * * *'),
        ('email-cron-hourly-immediate', '7 * * * *'),
        ('email-cron-daily', '17 5 * * *'),
        ('process-stripe-refunds-15min', '3,18,33,48 * * * *'),
        ('escrow-debit-echeance', '11 * * * *'),
        ('escrow-release', '8,23,38,53 * * * *'),
        ('jolene_process_externalisations', '1-59/5 * * * *'),
        -- Deux créneaux UTC et une condition Europe/Paris assurent 06:00
        -- toute l'année malgré les changements heure d'été/heure d'hiver.
        ('weekly-invoicing-cron', '0 4,5 * * *')
      ) AS specs(job_name, schedule)
  LOOP
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = v_spec.job_name) THEN
      PERFORM cron.unschedule(v_spec.job_name);
    END IF;

    v_job_id := cron.schedule(
      v_spec.job_name,
      v_spec.schedule,
      CASE
        WHEN v_spec.job_name = 'weekly-invoicing-cron' THEN format(
          'SELECT private.fn_appeler_edge_critique(%L, false) WHERE EXTRACT(HOUR FROM now() AT TIME ZONE %L) = 6',
          v_spec.job_name,
          'Europe/Paris'
        )
        ELSE format(
          'SELECT private.fn_appeler_edge_critique(%L, false)',
          v_spec.job_name
        )
      END
    );
    PERFORM cron.alter_job(job_id := v_job_id, active := false);
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM cron.job
     WHERE jobname = 'jolene-monitor-crons-edge-critiques'
  ) THEN
    PERFORM cron.unschedule('jolene-monitor-crons-edge-critiques');
  END IF;
  v_job_id := cron.schedule(
    'jolene-monitor-crons-edge-critiques',
    '4-59/5 * * * *',
    'SELECT private.fn_controler_crons_edge_critiques()'
  );
  PERFORM cron.alter_job(job_id := v_job_id, active := false);

  -- Le lancement n'a pas besoin des traitements d'acquisition. On conserve
  -- leur définition pour une réactivation future revue, mais aucun d'eux ne
  -- doit repartir implicitement avec les crons métier critiques.
  FOR v_job_id IN
    SELECT j.jobid
      FROM cron.job j
     WHERE j.jobname IN (
       'warm-edge-functions',
       'jolene_acquisition_brouillons',
       'jolene_sourcing_rpps_hebdo',
       'jolene_sourcing_finess_hebdo',
       'enrich-prospects-etab',
       'enrich-prospects-soignant',
       'jolene_sourcing_rpps_watchdog',
       'jolene_prospection_compteurs_quotidien',
       'jolene_acquisition_bmo_mensuel',
       'jolene_acquisition_boamp_quotidien'
     )
  LOOP
    PERFORM cron.alter_job(job_id := v_job_id, active := false);
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM cron.job
     WHERE jobname IN (
       'litige-escalation-cron',
       'email-cron-hourly-immediate',
       'email-cron-daily',
       'process-stripe-refunds-15min',
       'escrow-debit-echeance',
       'escrow-release',
       'jolene_process_externalisations',
       'weekly-invoicing-cron',
       'jolene-monitor-crons-edge-critiques'
     )
       AND active IS TRUE
  ) THEN
    RAISE EXCEPTION 'Un job Edge critique a été activé avant les sondes';
  END IF;
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron indisponible : recapture des jobs différée';
END
$cron_jobs$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Exclusion fail-closed des comptes test avant tout effet financier/externe
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION private.fn_json_uuid(p_value text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path TO ''
AS $function$
BEGIN
  RETURN p_value::uuid;
EXCEPTION
  WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_json_uuid(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_json_uuid(text) TO service_role;

CREATE OR REPLACE FUNCTION private.fn_compte_operationnel_est_reel(
  p_utilisateur_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT p_utilisateur_id IS NOT NULL
     AND (
       EXISTS (
         SELECT 1 FROM public.soignants s
          WHERE s.id = p_utilisateur_id
            AND s.est_compte_test IS FALSE
            AND s.supprime_le IS NULL
       )
       OR EXISTS (
         SELECT 1 FROM public.etablissements e
          WHERE e.id = p_utilisateur_id
            AND e.est_compte_test IS FALSE
            AND e.supprime_le IS NULL
       )
       OR EXISTS (
         SELECT 1 FROM public.equipe_admin ea
          WHERE ea.user_id = p_utilisateur_id
            AND ea.actif IS TRUE
       )
     );
$function$;

REVOKE ALL ON FUNCTION private.fn_compte_operationnel_est_reel(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_compte_operationnel_est_reel(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_mission_est_reelle(p_mission_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE m.id = p_mission_id
       AND e.est_compte_test IS FALSE
       AND COALESCE(s.est_compte_test, false) IS FALSE
  ), false);
$function$;

REVOKE ALL ON FUNCTION private.fn_mission_est_reelle(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_mission_est_reelle(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_mission_est_reelle_pour_service(
  p_mission_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_mission_est_reelle(p_mission_id);
$function$;

REVOKE ALL ON FUNCTION public.fn_mission_est_reelle_pour_service(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mission_est_reelle_pour_service(uuid)
  TO service_role;

-- Réservation durable des SMS avant l'appel Twilio. Contrairement aux emails,
-- l'API Messages ne fournit pas ici de reprise fournisseur par clé : un appel
-- réseau au résultat indéterminé ne doit donc jamais être relancé
-- automatiquement. L'état EN_COURS/INDETERMINE reste bloqué jusqu'à
-- réconciliation manuelle, ce qui privilégie l'absence de doublon.
CREATE TABLE IF NOT EXISTS private.sms_dispatch_idempotency (
  idempotency_key text PRIMARY KEY
    CHECK (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'),
  request_fingerprint text NOT NULL
    CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  statut text NOT NULL
    CHECK (statut IN ('EN_COURS', 'ENVOYE', 'ERREUR', 'INDETERMINE')),
  provider_id text,
  derniere_erreur text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON TABLE private.sms_dispatch_idempotency
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.fn_reserver_envoi_sms_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ligne private.sms_dispatch_idempotency%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'
     OR p_request_fingerprint IS NULL
     OR p_request_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Clé ou empreinte SMS idempotente invalide'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key, 284771)
  );

  SELECT *
    INTO v_ligne
    FROM private.sms_dispatch_idempotency
   WHERE idempotency_key = p_idempotency_key
   FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO private.sms_dispatch_idempotency (
      idempotency_key,
      request_fingerprint,
      statut
    ) VALUES (
      p_idempotency_key,
      p_request_fingerprint,
      'EN_COURS'
    );
    RETURN jsonb_build_object('statut', 'RESERVE');
  END IF;

  IF v_ligne.request_fingerprint <> p_request_fingerprint THEN
    RETURN jsonb_build_object('statut', 'CONFLIT');
  END IF;

  IF v_ligne.statut = 'ENVOYE' THEN
    RETURN jsonb_build_object(
      'statut', 'DEJA_ENVOYE',
      'provider_id', v_ligne.provider_id
    );
  END IF;

  IF v_ligne.statut IN ('EN_COURS', 'INDETERMINE') THEN
    RETURN jsonb_build_object(
      'statut', v_ligne.statut,
      'provider_id', v_ligne.provider_id
    );
  END IF;

  -- Seul un échec fournisseur explicitement finalisé peut être repris.
  UPDATE private.sms_dispatch_idempotency
     SET statut = 'EN_COURS',
         provider_id = NULL,
         derniere_erreur = NULL,
         modifie_le = now()
   WHERE idempotency_key = p_idempotency_key;

  RETURN jsonb_build_object('statut', 'RESERVE');
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_reserver_envoi_sms_idempotent(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_reserver_envoi_sms_idempotent(text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_finaliser_envoi_sms_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text,
  p_statut text,
  p_provider_id text DEFAULT NULL,
  p_erreur text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF p_statut NOT IN ('ENVOYE', 'ERREUR', 'INDETERMINE') THEN
    RAISE EXCEPTION 'Statut final SMS invalide'
      USING ERRCODE = '22023';
  END IF;

  UPDATE private.sms_dispatch_idempotency
     SET statut = p_statut,
         provider_id = CASE
           WHEN p_statut IN ('ENVOYE', 'INDETERMINE') THEN p_provider_id
           ELSE NULL
         END,
         derniere_erreur = CASE
           WHEN p_statut = 'ENVOYE' THEN NULL
           ELSE left(COALESCE(p_erreur, 'Résultat fournisseur inconnu'), 2000)
         END,
         modifie_le = now()
   WHERE idempotency_key = p_idempotency_key
     AND request_fingerprint = p_request_fingerprint
     AND statut = 'EN_COURS';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservation SMS introuvable, incohérente ou déjà finale'
      USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_finaliser_envoi_sms_idempotent(
  text,
  text,
  text,
  text,
  text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_finaliser_envoi_sms_idempotent(
  text,
  text,
  text,
  text,
  text
) TO service_role;

-- Wrappers Data API sans élévation supplémentaire.
CREATE OR REPLACE FUNCTION public.fn_reserver_envoi_sms_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text
) RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_reserver_envoi_sms_idempotent(
    p_idempotency_key,
    p_request_fingerprint
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_finaliser_envoi_sms_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text,
  p_statut text,
  p_provider_id text DEFAULT NULL,
  p_erreur text DEFAULT NULL
) RETURNS void
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_finaliser_envoi_sms_idempotent(
    p_idempotency_key,
    p_request_fingerprint,
    p_statut,
    p_provider_id,
    p_erreur
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_reserver_envoi_sms_idempotent(text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_finaliser_envoi_sms_idempotent(
  text,
  text,
  text,
  text,
  text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_envoi_sms_idempotent(text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_finaliser_envoi_sms_idempotent(
  text,
  text,
  text,
  text,
  text
) TO service_role;

-- Même verrou durable pour les push internes. Un envoi multi-token peut être
-- partiellement accepté avant une erreur d'un autre fournisseur ; un tel état
-- reste INDETERMINE et n'est jamais rejoué automatiquement.
CREATE TABLE IF NOT EXISTS private.push_dispatch_idempotency (
  idempotency_key text PRIMARY KEY
    CHECK (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'),
  request_fingerprint text NOT NULL
    CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  statut text NOT NULL
    CHECK (statut IN ('EN_COURS', 'ENVOYE', 'ERREUR', 'INDETERMINE')),
  provider_id text,
  derniere_erreur text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON TABLE private.push_dispatch_idempotency
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.fn_reserver_envoi_push_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ligne private.push_dispatch_idempotency%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'
     OR p_request_fingerprint IS NULL
     OR p_request_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Clé ou empreinte push idempotente invalide'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key, 628031)
  );

  SELECT *
    INTO v_ligne
    FROM private.push_dispatch_idempotency
   WHERE idempotency_key = p_idempotency_key
   FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO private.push_dispatch_idempotency (
      idempotency_key,
      request_fingerprint,
      statut
    ) VALUES (
      p_idempotency_key,
      p_request_fingerprint,
      'EN_COURS'
    );
    RETURN jsonb_build_object('statut', 'RESERVE');
  END IF;

  IF v_ligne.request_fingerprint <> p_request_fingerprint THEN
    RETURN jsonb_build_object('statut', 'CONFLIT');
  END IF;
  IF v_ligne.statut = 'ENVOYE' THEN
    RETURN jsonb_build_object(
      'statut', 'DEJA_ENVOYE',
      'provider_id', v_ligne.provider_id
    );
  END IF;
  IF v_ligne.statut IN ('EN_COURS', 'INDETERMINE') THEN
    RETURN jsonb_build_object(
      'statut', v_ligne.statut,
      'provider_id', v_ligne.provider_id
    );
  END IF;

  UPDATE private.push_dispatch_idempotency
     SET statut = 'EN_COURS',
         provider_id = NULL,
         derniere_erreur = NULL,
         modifie_le = now()
   WHERE idempotency_key = p_idempotency_key;
  RETURN jsonb_build_object('statut', 'RESERVE');
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_reserver_envoi_push_idempotent(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_reserver_envoi_push_idempotent(text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_finaliser_envoi_push_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text,
  p_statut text,
  p_provider_id text DEFAULT NULL,
  p_erreur text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF p_statut NOT IN ('ENVOYE', 'ERREUR', 'INDETERMINE') THEN
    RAISE EXCEPTION 'Statut final push invalide'
      USING ERRCODE = '22023';
  END IF;

  UPDATE private.push_dispatch_idempotency
     SET statut = p_statut,
         provider_id = CASE
           WHEN p_statut IN ('ENVOYE', 'INDETERMINE') THEN p_provider_id
           ELSE NULL
         END,
         derniere_erreur = CASE
           WHEN p_statut = 'ENVOYE' THEN NULL
           ELSE left(COALESCE(p_erreur, 'Résultat fournisseur inconnu'), 2000)
         END,
         modifie_le = now()
   WHERE idempotency_key = p_idempotency_key
     AND request_fingerprint = p_request_fingerprint
     AND statut = 'EN_COURS';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservation push introuvable, incohérente ou déjà finale'
      USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_finaliser_envoi_push_idempotent(
  text,
  text,
  text,
  text,
  text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_finaliser_envoi_push_idempotent(
  text,
  text,
  text,
  text,
  text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_reserver_envoi_push_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text
) RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_reserver_envoi_push_idempotent(
    p_idempotency_key,
    p_request_fingerprint
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_finaliser_envoi_push_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text,
  p_statut text,
  p_provider_id text DEFAULT NULL,
  p_erreur text DEFAULT NULL
) RETURNS void
LANGUAGE sql
VOLATILE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.fn_finaliser_envoi_push_idempotent(
    p_idempotency_key,
    p_request_fingerprint,
    p_statut,
    p_provider_id,
    p_erreur
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_reserver_envoi_push_idempotent(text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_finaliser_envoi_push_idempotent(
  text,
  text,
  text,
  text,
  text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_envoi_push_idempotent(text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_finaliser_envoi_push_idempotent(
  text,
  text,
  text,
  text,
  text
) TO service_role;

-- Défense centrale de tous les parcours litige, y compris les parcours manuels
-- hors des quatre RPC cron : la notification in-app reste disponible pour les
-- tests fonctionnels, mais aucune file email/SMS externe n'est créée lorsque
-- la mission n'est pas canoniquement réelle.
CREATE OR REPLACE FUNCTION public.fn_litige_push_notification(
  p_destinataire_id uuid,
  p_type_destinataire text,
  p_type_notif text,
  p_titre text,
  p_corps text,
  p_litige_id uuid,
  p_email_data jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_telephone text;
  v_sms_eligible boolean;
  v_sms_contenu text;
  v_lien text;
  v_mission_reelle boolean := false;
BEGIN
  v_lien := CASE p_type_destinataire
    WHEN 'SOIGNANT' THEN '/soignant/litiges'
    WHEN 'ETABLISSEMENT' THEN '/etablissement/litiges'
    WHEN 'ADMIN' THEN '/admin/moderation'
    ELSE NULL
  END;

  INSERT INTO public.notifications (
    destinataire_id,
    type_destinataire,
    type,
    titre,
    corps,
    id_ressource,
    type_ressource,
    lien
  ) VALUES (
    p_destinataire_id,
    p_type_destinataire,
    p_type_notif,
    p_titre,
    p_corps,
    p_litige_id,
    'litige',
    v_lien
  );

  SELECT private.fn_mission_est_reelle(l.mission_id)
    INTO v_mission_reelle
    FROM public.litiges l
   WHERE l.id = p_litige_id;

  IF v_mission_reelle IS DISTINCT FROM true THEN
    RETURN;
  END IF;

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    p_type_notif,
    p_destinataire_id,
    p_email_data || jsonb_build_object(
      'litige_id', p_litige_id,
      'url_litige', v_lien
    )
  );

  v_sms_eligible := p_type_notif IN (
    'LITIGE_OUVERTURE',
    'REMBOURSEMENT_CONFIRME',
    'LITIGE_RAPPEL_J1',
    'LITIGE_RAPPEL_J3',
    'LITIGE_RAPPEL_J5'
  );

  IF NOT v_sms_eligible THEN
    RETURN;
  END IF;

  IF p_type_destinataire = 'SOIGNANT' THEN
    SELECT s.telephone
      INTO v_telephone
      FROM public.soignants s
     WHERE s.id = p_destinataire_id;
  ELSIF p_type_destinataire = 'ETABLISSEMENT' THEN
    SELECT e.telephone_contact
      INTO v_telephone
      FROM public.etablissements e
     WHERE e.id = p_destinataire_id;
  END IF;

  IF v_telephone IS NULL OR length(trim(v_telephone)) < 10 THEN
    RETURN;
  END IF;

  v_sms_contenu := CASE p_type_notif
    WHEN 'LITIGE_OUVERTURE' THEN
      'un litige '
        || COALESCE(p_email_data ->> 'type_litige', '')
        || ' a été ouvert sur votre mission. Répondez sous 72h.'
    WHEN 'REMBOURSEMENT_CONFIRME' THEN
      'remboursement de '
        || COALESCE(p_email_data ->> 'montant', '?')
        || '€ effectué (avoir '
        || COALESCE(p_email_data ->> 'numero_avoir', '')
        || '). Délai bancaire 2-5j.'
    WHEN 'LITIGE_RAPPEL_J1' THEN
      'litige en attente depuis 1j. Répondez sous 24h pour éviter l''escalade.'
    WHEN 'LITIGE_RAPPEL_J3' THEN
      'litige en attente depuis 3j. Réponse urgente requise.'
    WHEN 'LITIGE_RAPPEL_J5' THEN
      'litige en attente depuis 5j ouvrés. Escalade imminente.'
    ELSE p_corps
  END;

  INSERT INTO public.email_queue (type, destinataire_id, data)
  VALUES (
    'SMS_' || p_type_notif,
    p_destinataire_id,
    jsonb_build_object(
      'telephone', v_telephone,
      'contenu', v_sms_contenu,
      'litige_id', p_litige_id
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_litige_push_notification(
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_litige_push_notification(
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  jsonb
) TO service_role;

-- Les quatre RPC du cron litiges doivent ignorer une mission test AVANT toute
-- mutation de litige, notification, email ou SMS. Le filtre canonique porte
-- sur la mission et ses deux comptes, pas sur un champ fourni par le client.
CREATE OR REPLACE FUNCTION public.fn_auto_creation_litiges_presence()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_delai_pointage_h integer;
  v_nb_abs integer := 0;
  v_nb_dep integer := 0;
  v_presence record;
  v_litige_id uuid;
  v_type_litige public.type_litige;
  v_motif text;
  v_notif_corps text;
BEGIN
  SELECT pl.valeur::integer
    INTO v_delai_pointage_h
    FROM public.parametres_litiges pl
   WHERE pl.cle = 'delai_contestation_pointage_h';

  FOR v_presence IN
    SELECT p.id AS presence_id,
           p.mission_id,
           p.soignant_id,
           p.heures_reelles,
           m.duree_heures,
           m.etablissement_id,
           m.soignant_assigne_id
      FROM public.presences p
      JOIN public.missions m ON m.id = p.mission_id
     WHERE private.fn_mission_est_reelle(p.mission_id)
       AND p.valide_par_etablissement IS TRUE
       AND p.valide_le IS NOT NULL
       AND p.valide_le <
         now() - make_interval(hours => v_delai_pointage_h)
       AND p.motif_litige IS NOT NULL
       AND p.litige_auto_cree_le IS NULL
  LOOP
    IF v_presence.heures_reelles IS NULL
       OR v_presence.heures_reelles = 0 THEN
      v_type_litige := 'ABSENCE_SOIGNANT';
      v_motif :=
        'Auto-création : soignant marqué absent sans contestation dans les 48h';
      v_notif_corps :=
        'Votre établissement a signalé une absence. Répondez sous 72h pour éviter l''escalade automatique.';
    ELSIF v_presence.duree_heures IS NOT NULL
      AND v_presence.duree_heures > 0
      AND v_presence.heures_reelles < v_presence.duree_heures * 0.80
    THEN
      v_type_litige := 'DEPART_ANTICIPE';
      v_motif := format(
        'Auto-création : départ anticipé (%sh effectuées sur %sh prévues, soit %s %%).',
        v_presence.heures_reelles,
        v_presence.duree_heures,
        round(
          (v_presence.heures_reelles / v_presence.duree_heures) * 100
        )
      );
      v_notif_corps :=
        'Votre établissement a signalé un départ anticipé. Répondez sous 72h pour éviter l''escalade automatique.';
    ELSE
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1
        FROM public.litiges l
       WHERE l.mission_id = v_presence.mission_id
         AND l.type_litige = v_type_litige
         AND l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION')
    ) THEN
      UPDATE public.presences
         SET litige_auto_cree_le = now()
       WHERE id = v_presence.presence_id;
      CONTINUE;
    END IF;

    INSERT INTO public.litiges (
      mission_id,
      soignant_id,
      etablissement_id,
      presence_id,
      initie_par,
      motif,
      statut,
      type_litige,
      est_informatif
    ) VALUES (
      v_presence.mission_id,
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      v_presence.etablissement_id,
      v_presence.presence_id,
      'SYSTEME',
      v_motif,
      'OUVERT',
      v_type_litige,
      false
    )
    RETURNING id INTO v_litige_id;

    UPDATE public.presences
       SET litige_auto_cree_le = now()
     WHERE id = v_presence.presence_id;

    PERFORM public.fn_ecrire_audit(
      NULL,
      'SYSTEM',
      'LITIGE_AUTO_CREATION',
      'litige',
      v_litige_id,
      NULL,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'presence_id', v_presence.presence_id,
        'heures_reelles', v_presence.heures_reelles,
        'duree_heures_prevues', v_presence.duree_heures,
        'raison', CASE v_type_litige
          WHEN 'ABSENCE_SOIGNANT' THEN
            'Absence non contestée dans les 48h post-validation présence'
          WHEN 'DEPART_ANTICIPE' THEN
            'Départ anticipé (< 80 % heures prévues) non contesté dans les 48h'
        END
      ),
      NULL,
      NULL
    );

    PERFORM public.fn_litige_push_notification(
      COALESCE(v_presence.soignant_assigne_id, v_presence.soignant_id),
      'SOIGNANT',
      'LITIGE_OUVERTURE',
      'Litige ouvert sur votre mission',
      v_notif_corps,
      v_litige_id,
      jsonb_build_object(
        'type_litige', v_type_litige,
        'mission_id', v_presence.mission_id,
        'auto_cree', true
      )
    );

    IF v_type_litige = 'ABSENCE_SOIGNANT' THEN
      v_nb_abs := v_nb_abs + 1;
    ELSE
      v_nb_dep := v_nb_dep + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'litiges_crees', v_nb_abs + v_nb_dep,
    'absence_soignant', v_nb_abs,
    'depart_anticipe', v_nb_dep
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_litiges()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_litige record;
  v_destinataire_id uuid;
  v_destinataire_type text;
  v_age_h integer;
  v_rappel_key text;
  v_rappel_libelle text;
  v_nb_rappels integer := 0;
BEGIN
  FOR v_litige IN
    SELECT l.id,
           l.mission_id,
           l.soignant_id,
           l.etablissement_id,
           l.initie_par,
           l.cree_le,
           l.reponse,
           l.type_litige,
           l.derniers_rappels_envoyes
      FROM public.litiges l
     WHERE private.fn_mission_est_reelle(l.mission_id)
       AND l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND NOT l.est_informatif
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
  LOOP
    v_age_h :=
      extract(epoch FROM now() - v_litige.cree_le)::integer / 3600;

    IF v_age_h >= 120
       AND NOT (v_litige.derniers_rappels_envoyes ? 'J+5') THEN
      v_rappel_key := 'J+5';
      v_rappel_libelle := 'Rappel litige 5 jours — dernière relance';
    ELSIF v_age_h >= 72
      AND NOT (v_litige.derniers_rappels_envoyes ? 'J+3') THEN
      v_rappel_key := 'J+3';
      v_rappel_libelle := 'Rappel litige 3 jours';
    ELSIF v_age_h >= 24
      AND NOT (v_litige.derniers_rappels_envoyes ? 'J+1') THEN
      v_rappel_key := 'J+1';
      v_rappel_libelle := 'Rappel litige 1 jour';
    ELSE
      CONTINUE;
    END IF;

    IF v_litige.initie_par = 'SOIGNANT' THEN
      v_destinataire_id := v_litige.etablissement_id;
      v_destinataire_type := 'ETABLISSEMENT';
    ELSE
      v_destinataire_id := v_litige.soignant_id;
      v_destinataire_type := 'SOIGNANT';
    END IF;

    IF v_destinataire_id IS NULL THEN
      CONTINUE;
    END IF;

    PERFORM public.fn_litige_push_notification(
      v_destinataire_id,
      v_destinataire_type,
      'LITIGE_RAPPEL_' || replace(v_rappel_key, '+', ''),
      v_rappel_libelle,
      'Un litige est en attente de votre réponse depuis '
        || v_age_h
        || 'h. Répondez pour éviter l''escalade.',
      v_litige.id,
      jsonb_build_object(
        'type_litige', v_litige.type_litige,
        'mission_id', v_litige.mission_id,
        'age_heures', v_age_h,
        'rappel', v_rappel_key
      )
    );

    UPDATE public.litiges
       SET derniers_rappels_envoyes = derniers_rappels_envoyes
         || jsonb_build_object(v_rappel_key, now())
     WHERE id = v_litige.id;

    v_nb_rappels := v_nb_rappels + 1;
  END LOOP;

  RETURN jsonb_build_object('rappels_envoyes', v_nb_rappels);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_litiges_escalader_auto()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_delai_liberal_h integer;
  v_delai_salarie_j_ouvres integer;
  v_nb_escalades integer := 0;
  v_litige record;
  v_admin_id uuid;
BEGIN
  SELECT pl.valeur::integer
    INTO v_delai_liberal_h
    FROM public.parametres_litiges pl
   WHERE pl.cle = 'delai_escalade_liberal_h';
  SELECT pl.valeur::integer
    INTO v_delai_salarie_j_ouvres
    FROM public.parametres_litiges pl
   WHERE pl.cle = 'delai_escalade_salarie_jours_ouvres';

  FOR v_litige IN
    SELECT l.id,
           l.mission_id,
           l.soignant_id,
           l.etablissement_id,
           l.type_litige,
           l.cree_le,
           CASE
             WHEN m.type_contrat_applique = 'SALARIE' THEN true
             WHEN m.type_contrat_applique = 'LIBERAL' THEN false
             ELSE COALESCE(s.est_salarie_etablissement, false)
           END AS est_salarie
      FROM public.litiges l
      LEFT JOIN public.soignants s ON s.id = l.soignant_id
      LEFT JOIN public.missions m ON m.id = l.mission_id
     WHERE private.fn_mission_est_reelle(l.mission_id)
       AND l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
       AND NOT l.est_informatif
       AND (
         (
           CASE
             WHEN m.type_contrat_applique = 'SALARIE' THEN true
             WHEN m.type_contrat_applique = 'LIBERAL' THEN false
             ELSE COALESCE(s.est_salarie_etablissement, false)
           END = false
           AND l.cree_le <
             now() - make_interval(hours => v_delai_liberal_h)
         )
         OR
         (
           CASE
             WHEN m.type_contrat_applique = 'SALARIE' THEN true
             WHEN m.type_contrat_applique = 'LIBERAL' THEN false
             ELSE COALESCE(s.est_salarie_etablissement, false)
           END = true
           AND l.cree_le < public.fn_ajouter_jours_ouvres(
             now(),
             -v_delai_salarie_j_ouvres
           )
         )
       )
  LOOP
    UPDATE public.litiges
       SET statut = 'EN_MEDIATION',
           escalade_auto_le = now(),
           escalade_auto_motif = CASE
             WHEN v_litige.est_salarie THEN
               'Pas de réponse dans le délai salarié (5 jours ouvrés)'
             ELSE 'Pas de réponse dans le délai libéral (72h)'
           END
     WHERE id = v_litige.id;

    PERFORM public.fn_ecrire_audit(
      NULL,
      'SYSTEM',
      'LITIGE_ESCALADE_AUTO',
      'litige',
      v_litige.id,
      NULL,
      jsonb_build_object(
        'type_litige', v_litige.type_litige,
        'mission_id', v_litige.mission_id,
        'est_salarie', v_litige.est_salarie
      ),
      NULL,
      NULL
    );

    FOR v_admin_id IN
      SELECT * FROM public.fn_list_admin_user_ids()
    LOOP
      PERFORM public.fn_litige_push_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_ESCALADE_ADMIN',
        'Litige escaladé : ' || v_litige.type_litige,
        'Un litige '
          || v_litige.type_litige
          || ' sur mission '
          || v_litige.mission_id::text
          || ' a été auto-escaladé en médiation.',
        v_litige.id,
        jsonb_build_object(
          'type_litige', v_litige.type_litige,
          'mission_id', v_litige.mission_id,
          'prioritaire', true
        )
      );
    END LOOP;

    v_nb_escalades := v_nb_escalades + 1;
  END LOOP;

  RETURN jsonb_build_object('escalades', v_nb_escalades);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_alerter_mediation_prioritaire()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_delai_j integer;
  v_nb_alertes integer := 0;
  v_litige record;
  v_admin_id uuid;
BEGIN
  SELECT pl.valeur::integer
    INTO v_delai_j
    FROM public.parametres_litiges pl
   WHERE pl.cle = 'delai_mediation_alerte_prioritaire_j';

  FOR v_litige IN
    SELECT l.id,
           l.mission_id,
           l.type_litige,
           l.escalade_auto_le
      FROM public.litiges l
     WHERE private.fn_mission_est_reelle(l.mission_id)
       AND l.statut = 'EN_MEDIATION'
       AND l.escalade_auto_le IS NOT NULL
       AND l.escalade_auto_le < now() - make_interval(days => v_delai_j)
       AND NOT (l.derniers_rappels_envoyes ? 'MEDIATION_7J')
  LOOP
    FOR v_admin_id IN
      SELECT * FROM public.fn_list_admin_user_ids()
    LOOP
      PERFORM public.fn_litige_push_notification(
        v_admin_id,
        'ADMIN',
        'LITIGE_MEDIATION_PRIORITAIRE',
        'Litige en médiation depuis > ' || v_delai_j || ' jours',
        'Le litige '
          || v_litige.type_litige
          || ' sur mission '
          || v_litige.mission_id::text
          || ' est en médiation sans action admin depuis plus de '
          || v_delai_j
          || ' jours.',
        v_litige.id,
        jsonb_build_object(
          'type_litige', v_litige.type_litige,
          'mission_id', v_litige.mission_id,
          'jours_depuis_escalade', v_delai_j,
          'prioritaire', true
        )
      );
    END LOOP;

    UPDATE public.litiges
       SET derniers_rappels_envoyes = derniers_rappels_envoyes
         || jsonb_build_object('MEDIATION_7J', now())
     WHERE id = v_litige.id;

    v_nb_alertes := v_nb_alertes + 1;
  END LOOP;

  RETURN jsonb_build_object('alertes_mediation', v_nb_alertes);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_auto_creation_litiges_presence()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_envoyer_rappels_litiges()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_litiges_escalader_auto()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_alerter_mediation_prioritaire()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_auto_creation_litiges_presence()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_rappels_litiges()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_litiges_escalader_auto()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_alerter_mediation_prioritaire()
  TO service_role;

-- Deux tâches SQL déjà actives en production produisent des alertes admin.
-- Elles restent utiles au lancement, mais leurs sélections excluent désormais
-- les fixtures avant audit, pénalité ou externalisation.
CREATE OR REPLACE FUNCTION public.fn_alerte_reclamations_pending_old()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_count integer;
  v_liste jsonb;
  v_admin_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  SELECT count(*),
         jsonb_agg(
           jsonb_build_object(
             'id', r.id,
             'evenement_type', r.evenement_type,
             'contesteur_id', r.contesteur_id,
             'motif_categorie', r.motif_categorie,
             'texte_libre', left(r.texte_libre, 100),
             'cree_le', r.cree_le,
             'jours_attente',
               extract(epoch FROM (now() - r.cree_le)) / 86400
           )
           ORDER BY r.cree_le ASC
         )
    INTO v_count, v_liste
    FROM public.reclamations_score r
   WHERE r.statut = 'PENDING'
     AND r.cree_le < now() - interval '14 days'
     AND private.fn_compte_operationnel_est_reel(r.contesteur_id);

  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'count', 0);
  END IF;

  SELECT COALESCE(array_agg(admin_user_id), ARRAY[]::uuid[])
    INTO v_admin_ids
    FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);

  IF cardinality(v_admin_ids) > 0 THEN
    INSERT INTO public.externalisation_actions (
      type_action,
      payload,
      source,
      source_id
    )
    SELECT 'EMAIL_NOTIF',
           jsonb_build_object(
             'destinataire_id', uid,
             'type', 'ALERTE_RECLAMATIONS_PENDING',
             'data', jsonb_build_object(
               'count', v_count,
               'liste', v_liste,
               'lien_admin',
                 'https://jolene.app/admin/reclamations-score'
             )
           ),
           'CRON_ALERTES',
           NULL
      FROM unnest(v_admin_ids) AS admins(uid);

    INSERT INTO public.externalisation_actions (
      type_action,
      payload,
      source,
      source_id
    )
    SELECT 'PUSH_NOTIF',
           jsonb_build_object(
             'destinataire_id', uid,
             'type_evenement', 'ALERTE_ADMIN',
             'titre',
               '⚠️ '
                 || v_count
                 || ' réclamation'
                 || CASE WHEN v_count > 1 THEN 's' ELSE '' END
                 || ' en attente > 14j',
             'corps', 'Examen requis.',
             'lien', '/admin/reclamations-score'
           ),
           'CRON_ALERTES',
           NULL
      FROM unnest(v_admin_ids) AS admins(uid);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'count', v_count,
    'admins_notifies', cardinality(v_admin_ids)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_detecter_teleportations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_alertes_count integer := 0;
  v_rec record;
  v_vitesse jsonb;
  v_admin_ids uuid[] := ARRAY[]::uuid[];
  v_soignants_affectes uuid[] := ARRAY[]::uuid[];
  v_sid uuid;
BEGIN
  FOR v_rec IN
    WITH pointages_recents AS (
      SELECT p.soignant_id,
             p.pointage_arrivee_le AS ts,
             p.arrivee_lat AS lat,
             p.arrivee_lng AS lng,
             p.mission_id,
             p.id AS presence_id,
             'arrivee' AS type_p
        FROM public.presences p
       WHERE private.fn_mission_est_reelle(p.mission_id)
         AND p.pointage_arrivee_le > now() - interval '24 hours'
         AND p.arrivee_lat IS NOT NULL
         AND p.arrivee_lng IS NOT NULL
      UNION ALL
      SELECT p.soignant_id,
             p.pointage_depart_le AS ts,
             p.depart_lat AS lat,
             p.depart_lng AS lng,
             p.mission_id,
             p.id AS presence_id,
             'depart' AS type_p
        FROM public.presences p
       WHERE private.fn_mission_est_reelle(p.mission_id)
         AND p.pointage_depart_le > now() - interval '24 hours'
         AND p.depart_lat IS NOT NULL
         AND p.depart_lng IS NOT NULL
    ),
    paires AS (
      SELECT a.soignant_id,
             a.ts AS ts1,
             a.lat AS lat1,
             a.lng AS lng1,
             a.mission_id AS mission1,
             a.type_p AS type1,
             lead(a.ts) OVER (
               PARTITION BY a.soignant_id ORDER BY a.ts
             ) AS ts2,
             lead(a.lat) OVER (
               PARTITION BY a.soignant_id ORDER BY a.ts
             ) AS lat2,
             lead(a.lng) OVER (
               PARTITION BY a.soignant_id ORDER BY a.ts
             ) AS lng2,
             lead(a.mission_id) OVER (
               PARTITION BY a.soignant_id ORDER BY a.ts
             ) AS mission2,
             lead(a.type_p) OVER (
               PARTITION BY a.soignant_id ORDER BY a.ts
             ) AS type2,
             lead(a.presence_id) OVER (
               PARTITION BY a.soignant_id ORDER BY a.ts
             ) AS presence2
        FROM pointages_recents a
    )
    SELECT *
      FROM paires
     WHERE ts2 IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
           FROM public.journaux_audit ja
          WHERE ja.action = 'SYSTEM'
            AND ja.details ->> 'evenement' = 'TELEPORTATION_DETECTED'
            AND ja.details ->> 'presence_id_destination' =
              paires.presence2::text
       )
  LOOP
    v_vitesse := public.fn_vitesse_entre_pointages(
      v_rec.lat1,
      v_rec.lng1,
      v_rec.ts1,
      v_rec.lat2,
      v_rec.lng2,
      v_rec.ts2
    );
    IF (v_vitesse ->> 'calculable')::boolean
       AND (v_vitesse ->> 'teleportation')::boolean THEN
      INSERT INTO public.journaux_audit (
        acteur_id,
        type_acteur,
        action,
        type_ressource,
        id_ressource,
        details
      ) VALUES (
        v_rec.soignant_id,
        'SOIGNANT',
        'SYSTEM',
        'presence',
        v_rec.presence2,
        jsonb_build_object(
          'evenement', 'TELEPORTATION_DETECTED',
          'niveau', 'ALERTE',
          'soignant_id', v_rec.soignant_id,
          'mission_id_source', v_rec.mission1,
          'mission_id_destination', v_rec.mission2,
          'type_pointage_source', v_rec.type1,
          'type_pointage_destination', v_rec.type2,
          'presence_id_destination', v_rec.presence2,
          'ts_source', v_rec.ts1,
          'ts_destination', v_rec.ts2,
          'distance_m', v_vitesse ->> 'distance_m',
          'duree_h', v_vitesse ->> 'duree_h',
          'vitesse_kmh', v_vitesse ->> 'vitesse_kmh'
        )
      );

      UPDATE public.presences
         SET alerte_teleportation = true,
             modifie_le = now()
       WHERE id = v_rec.presence2;

      IF NOT EXISTS (
        SELECT 1
          FROM public.evenements_score_soignant e
         WHERE e.type_evenement = 'FRAUDE_GPS'
           AND e.details ->> 'presence_id_destination' =
             v_rec.presence2::text
      ) THEN
        INSERT INTO public.evenements_score_soignant (
          soignant_id,
          type_evenement,
          points,
          motif,
          contestable,
          mission_id,
          details
        ) VALUES (
          v_rec.soignant_id,
          'FRAUDE_GPS',
          -10,
          'Téléportation détectée (vitesse > 200 km/h entre deux pointages GPS)',
          true,
          v_rec.mission2,
          jsonb_build_object(
            'presence_id_destination', v_rec.presence2,
            'mission_id_source', v_rec.mission1,
            'mission_id_destination', v_rec.mission2,
            'vitesse_kmh', v_vitesse ->> 'vitesse_kmh',
            'distance_m', v_vitesse ->> 'distance_m',
            'duree_h', v_vitesse ->> 'duree_h',
            'ts_source', v_rec.ts1,
            'ts_destination', v_rec.ts2
          )
        );
        IF NOT (v_rec.soignant_id = ANY(v_soignants_affectes)) THEN
          v_soignants_affectes := array_append(
            v_soignants_affectes,
            v_rec.soignant_id
          );
        END IF;
      END IF;

      v_alertes_count := v_alertes_count + 1;
    END IF;
  END LOOP;

  IF array_length(v_soignants_affectes, 1) > 0 THEN
    FOREACH v_sid IN ARRAY v_soignants_affectes
    LOOP
      PERFORM public.fn_calculer_score_fiabilite_v2(
        v_sid,
        'fraude_gps'
      );
    END LOOP;
  END IF;

  IF v_alertes_count > 0 THEN
    SELECT COALESCE(array_agg(admin_user_id), ARRAY[]::uuid[])
      INTO v_admin_ids
      FROM public.fn_list_admin_user_ids() AS admins(admin_user_id);

    IF cardinality(v_admin_ids) > 0 THEN
      INSERT INTO public.externalisation_actions (
        type_action,
        payload,
        source,
        source_id
      )
      SELECT 'EMAIL_NOTIF',
             jsonb_build_object(
               'destinataire_id', uid,
               'type', 'ALERTE_TELEPORTATION',
               'data', jsonb_build_object(
                 'count', v_alertes_count,
                 'lien_admin',
                   'https://app.jolene.app/admin/journaux-audit?evenement=TELEPORTATION_DETECTED'
               )
             ),
             'CRON_ANTI_TRICHE',
             NULL
        FROM unnest(v_admin_ids) AS admins(uid);

      INSERT INTO public.externalisation_actions (
        type_action,
        payload,
        source,
        source_id
      )
      SELECT 'PUSH_NOTIF',
             jsonb_build_object(
               'destinataire_id', uid,
               'type_evenement', 'ALERTE_ADMIN',
               'titre',
                 '⚠️ '
                   || v_alertes_count
                   || ' téléportation'
                   || CASE
                        WHEN v_alertes_count > 1 THEN 's' ELSE ''
                      END
                   || ' détectée'
                   || CASE
                        WHEN v_alertes_count > 1 THEN 's' ELSE ''
                      END,
               'corps',
                 'Vitesse > 200 km/h entre pointages. Pénalité -10 appliquée (contestable). Vérification requise.',
               'lien', '/admin/journaux-audit'
             ),
             'CRON_ANTI_TRICHE',
             NULL
        FROM unnest(v_admin_ids) AS admins(uid);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'alertes_count', v_alertes_count,
    'soignants_penalises',
      COALESCE(array_length(v_soignants_affectes, 1), 0)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_alerte_reclamations_pending_old()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_detecter_teleportations()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_alerte_reclamations_pending_old()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_detecter_teleportations()
  TO service_role;

CREATE OR REPLACE FUNCTION private.fn_externalisation_est_reelle(
  p_action public.externalisation_actions
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_second_id uuid;
BEGIN
  -- La provenance canonique prime toujours sur les IDs du payload. Sinon une
  -- alerte admin d'un litige test pourrait être classée réelle en ajoutant un
  -- destinataire admin réel ou un mission_id sans rapport.
  IF p_action.source = 'LITIGE_EXEC' AND p_action.source_id IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1
        FROM public.litiges l
       WHERE l.id = p_action.source_id
         AND private.fn_mission_est_reelle(l.mission_id)
    );
  END IF;

  IF p_action.source = 'ANNULATION_MISSION' THEN
    v_id := private.fn_json_uuid(p_action.payload ->> 'mission_id');
    IF v_id IS NULL OR p_action.source_id IS NULL THEN
      RETURN false;
    END IF;

    -- Les annulations établissement utilisent mission_id comme source_id,
    -- tandis que l'historique soignant utilise candidature_id. Dans ce second
    -- cas, la candidature doit confirmer exactement la mission du payload.
    IF p_action.source_id <> v_id
       AND NOT EXISTS (
         SELECT 1
           FROM public.candidatures c
          WHERE c.id = p_action.source_id
            AND c.mission_id = v_id
       ) THEN
      RETURN false;
    END IF;

    RETURN private.fn_mission_est_reelle(v_id);
  END IF;

  -- Mission explicite hors provenance canonique déjà traitée.
  v_id := private.fn_json_uuid(p_action.payload ->> 'mission_id');
  IF v_id IS NOT NULL THEN
    RETURN private.fn_mission_est_reelle(v_id);
  END IF;

  -- Parrainage : les deux bénéficiaires doivent être de vrais comptes.
  v_id := private.fn_json_uuid(p_action.payload ->> 'parrain_id');
  v_second_id := private.fn_json_uuid(p_action.payload ->> 'filleul_id');
  IF v_id IS NOT NULL OR v_second_id IS NOT NULL THEN
    RETURN private.fn_compte_operationnel_est_reel(v_id)
       AND private.fn_compte_operationnel_est_reel(v_second_id);
  END IF;

  -- Seule classe système admin sans UUID historiquement émise :
  -- fn_creer_reclamation_score. Elle est autorisée uniquement si toutes les
  -- liaisons exactes vers la réclamation canonique concordent et si le
  -- contesteur est un compte réel. Le worker résout ensuite des UUID admin
  -- actifs et complets avant send-email.
  IF p_action.type_action = 'EMAIL_NOTIF'
     AND p_action.source = 'AUTRE'
     AND p_action.source_id IS NOT NULL
     AND p_action.payload ->> 'destinataire_role' = 'ADMIN'
     AND p_action.payload ->> 'type' = 'RECLAMATION_SCORE_NOUVELLE'
     AND private.fn_json_uuid(
       p_action.payload #>> '{data,reclamation_id}'
     ) = p_action.source_id THEN
    RETURN EXISTS (
      SELECT 1
        FROM public.reclamations_score r
       WHERE r.id = p_action.source_id
         AND r.contesteur_id = private.fn_json_uuid(
           p_action.payload #>> '{data,contesteur_id}'
         )
         AND r.evenement_type = p_action.payload #>> '{data,evenement_type}'
         AND r.motif_categorie = p_action.payload #>> '{data,motif_categorie}'
         AND private.fn_compte_operationnel_est_reel(r.contesteur_id)
    );
  END IF;

  -- Toute autre cible par rôle est ambiguë et reste bloquée. Les
  -- notifications ordinaires doivent fournir un destinataire UUID canonique.
  IF p_action.payload ? 'destinataire_role' THEN
    RETURN false;
  END IF;

  -- Notifications : le destinataire doit être réel ou administrateur actif.
  v_id := private.fn_json_uuid(p_action.payload ->> 'destinataire_id');
  IF v_id IS NOT NULL THEN
    RETURN private.fn_compte_operationnel_est_reel(v_id);
  END IF;

  -- Avoir / facture : rattachement par JOIN, jamais par une adresse ou un
  -- montant fourni dans le payload.
  v_id := COALESCE(
    private.fn_json_uuid(p_action.payload ->> 'avoir_id'),
    private.fn_json_uuid(p_action.payload ->> 'facture_id')
  );
  IF v_id IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1
        FROM public.factures_honoraires f
        JOIN public.etablissements e ON e.id = f.etablissement_id
        LEFT JOIN public.soignants s ON s.id = f.soignant_id
       WHERE f.id = v_id
         AND e.est_compte_test IS FALSE
         AND COALESCE(s.est_compte_test, false) IS FALSE
    );
  END IF;

  -- Contrat DPAE : rattachement canonique à sa mission.
  v_id := private.fn_json_uuid(p_action.payload ->> 'contrat_id');
  IF v_id IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1
        FROM public.contrats_mission c
       WHERE c.id = v_id
         AND private.fn_mission_est_reelle(c.mission_id)
    );
  END IF;

  -- OTP téléphone : seul le propriétaire canonique de la ligne OTP compte.
  IF p_action.type_action = 'SMS_NOTIF' AND p_action.source_id IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1
        FROM public.otps_telephone otp
       WHERE otp.id = p_action.source_id
         AND private.fn_compte_operationnel_est_reel(otp.user_id)
    );
  END IF;

  RETURN false;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_externalisation_est_reelle(
  public.externalisation_actions
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_externalisation_est_reelle(
  public.externalisation_actions
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_escrow_debits_a_echeance(
  p_limit integer DEFAULT 50
) RETURNS SETOF public.paiements_escrow
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT pe.*
    FROM public.paiements_escrow pe
    JOIN public.etablissements e ON e.id = pe.etablissement_id
    JOIN public.soignants s ON s.id = pe.soignant_id
   WHERE pe.statut = 'INITIE'
     AND pe.debit_prevu_le <= now()
     AND pe.tentatives_debit < 3
     AND e.est_compte_test IS FALSE
     AND s.est_compte_test IS FALSE
   ORDER BY pe.debit_prevu_le ASC
   LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_debits_a_echeance(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_debits_a_echeance(integer)
  TO service_role;
COMMENT ON FUNCTION public.fn_escrow_debits_a_echeance(integer) IS
  'Débits échéants réels uniquement ; les comptes test restent hors sélection et ne changent pas de statut.';

CREATE OR REPLACE FUNCTION public.fn_escrow_releases_a_traiter(
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  queue_id uuid,
  paiement_escrow_id uuid,
  mission_id uuid,
  soignant_id uuid,
  etablissement_id uuid,
  honoraires_cents integer,
  escrow_statut text,
  tentatives integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT q.id,
         q.paiement_escrow_id,
         q.mission_id,
         pe.soignant_id,
         pe.etablissement_id,
         pe.honoraires_cents,
         pe.statut,
         q.tentatives
    FROM public.escrow_release_queue q
    JOIN public.paiements_escrow pe ON pe.id = q.paiement_escrow_id
    JOIN public.etablissements e ON e.id = pe.etablissement_id
    JOIN public.soignants s ON s.id = pe.soignant_id
   WHERE q.statut IN ('EN_ATTENTE', 'EN_COURS')
     AND q.prochaine_tentative_le <= now()
     AND (
       (pe.statut = 'DEBITE' AND q.tentatives < 5)
       OR pe.statut = 'RELEASE_PLANIFIE'
     )
     AND e.est_compte_test IS FALSE
     AND s.est_compte_test IS FALSE
   ORDER BY q.prochaine_tentative_le ASC
   LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_escrow_releases_a_traiter(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_releases_a_traiter(integer)
  TO service_role;
COMMENT ON FUNCTION public.fn_escrow_releases_a_traiter(integer) IS
  'Releases réelles uniquement ; les comptes test restent hors sélection et ne changent pas de statut.';

CREATE OR REPLACE FUNCTION public.fn_stripe_refunds_reels_a_traiter(
  p_lease_before timestamptz,
  p_limit integer DEFAULT 10
) RETURNS SETOF public.stripe_refunds_queue
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT q.*
    FROM public.stripe_refunds_queue q
    LEFT JOIN public.paiements_escrow pe
      ON pe.id = q.paiement_escrow_id
    LEFT JOIN public.factures_honoraires f
      ON f.id = q.facture_origine_id
    JOIN public.etablissements e
      ON e.id = COALESCE(pe.etablissement_id, f.etablissement_id)
    LEFT JOIN public.soignants s
      ON s.id = COALESCE(pe.soignant_id, f.soignant_id)
   WHERE q.statut IN ('EN_ATTENTE', 'EN_COURS')
     AND (q.dernier_essai_le IS NULL OR q.dernier_essai_le < p_lease_before)
     AND e.est_compte_test IS FALSE
     AND COALESCE(s.est_compte_test, false) IS FALSE
   ORDER BY q.cree_le ASC
   LIMIT p_limit;
$function$;

REVOKE ALL ON FUNCTION public.fn_stripe_refunds_reels_a_traiter(
  timestamptz,
  integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_refunds_reels_a_traiter(
  timestamptz,
  integer
) TO service_role;
COMMENT ON FUNCTION public.fn_stripe_refunds_reels_a_traiter(
  timestamptz,
  integer
) IS 'Remboursements Stripe de comptes réels uniquement, résolus par JOIN sur la source canonique.';

CREATE OR REPLACE FUNCTION public.fn_externalisations_a_traiter(
  p_limit integer DEFAULT 50,
  p_worker_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
  v_actions jsonb;
  v_count integer;
  v_exclues_non_reelles integer;
  v_worker text := COALESCE(
    p_worker_id,
    'worker_' || substring(md5(random()::text), 1, 8)
  );
BEGIN
  SELECT count(*) INTO v_exclues_non_reelles
    FROM public.externalisation_actions a
   WHERE (
       (a.statut = 'PENDING'
         AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
       OR (a.statut = 'PENDING_AIFE'
         AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
       OR (a.statut = 'PROCESSING'
         AND a.cron_lock_at < now() - interval '10 minutes')
     )
     AND private.fn_externalisation_est_reelle(a) IS FALSE;

  WITH selectionnees AS (
    SELECT a.id
      FROM public.externalisation_actions a
     WHERE (
         (a.statut = 'PENDING'
           AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
         OR (a.statut = 'PENDING_AIFE'
           AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
         OR (a.statut = 'PROCESSING'
           AND a.cron_lock_at < now() - interval '10 minutes')
       )
       AND private.fn_externalisation_est_reelle(a) IS TRUE
     ORDER BY a.cree_le ASC
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.externalisation_actions a
     SET statut = 'PROCESSING',
         cron_lock_at = now(),
         cron_lock_par = v_worker
    FROM selectionnees s
   WHERE a.id = s.id;

  SELECT jsonb_agg(jsonb_build_object(
           'id', a.id,
           'type_action', a.type_action,
           'payload', a.payload,
           'source', a.source,
           'source_id', a.source_id,
           'tentatives', a.tentatives
         )),
         count(*)
    INTO v_actions, v_count
    FROM public.externalisation_actions a
   WHERE a.cron_lock_par = v_worker
     AND a.statut = 'PROCESSING'
     AND a.cron_lock_at > now() - interval '5 seconds';

  RETURN jsonb_build_object(
    'success', true,
    'worker_id', v_worker,
    'count', COALESCE(v_count, 0),
    'excluded_non_real', COALESCE(v_exclues_non_reelles, 0),
    'actions', COALESCE(v_actions, '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_externalisations_a_traiter(integer, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_externalisations_a_traiter(integer, text)
  TO service_role;
COMMENT ON FUNCTION public.fn_externalisations_a_traiter(integer, text) IS
  'Worker fail-closed : seules les actions rattachées par JOIN à un compte réel ou à un admin actif sont verrouillées.';

CREATE OR REPLACE FUNCTION public.fn_compter_files_finance_exclues_test()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'escrow_debits', (
      SELECT count(*)
        FROM public.paiements_escrow pe
        JOIN public.etablissements e ON e.id = pe.etablissement_id
        JOIN public.soignants s ON s.id = pe.soignant_id
       WHERE pe.statut = 'INITIE'
         AND pe.debit_prevu_le <= now()
         AND (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
    ),
    'escrow_releases', (
      SELECT count(*)
        FROM public.escrow_release_queue q
        JOIN public.paiements_escrow pe ON pe.id = q.paiement_escrow_id
        JOIN public.etablissements e ON e.id = pe.etablissement_id
        JOIN public.soignants s ON s.id = pe.soignant_id
       WHERE q.statut IN ('EN_ATTENTE', 'EN_COURS')
         AND (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
    ),
    'stripe_refunds', (
      SELECT count(*)
        FROM public.stripe_refunds_queue q
        LEFT JOIN public.paiements_escrow pe
          ON pe.id = q.paiement_escrow_id
        LEFT JOIN public.factures_honoraires f
          ON f.id = q.facture_origine_id
        JOIN public.etablissements e
          ON e.id = COALESCE(pe.etablissement_id, f.etablissement_id)
        LEFT JOIN public.soignants s
          ON s.id = COALESCE(pe.soignant_id, f.soignant_id)
       WHERE q.statut IN ('EN_ATTENTE', 'EN_COURS')
         AND (
           e.est_compte_test IS TRUE
           OR COALESCE(s.est_compte_test, false) IS TRUE
         )
    )
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_compter_files_finance_exclues_test()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_compter_files_finance_exclues_test()
  TO service_role;

-- Inventaire strictement en lecture des identifiants Stripe déjà enregistrés
-- sur des fixtures. Il ne contacte pas Stripe et ne supprime, ne rembourse, ne
-- désactive ni ne modifie aucun objet : chaque traitement restera soumis à une
-- revue explicite après comparaison au Dashboard Stripe live.
CREATE OR REPLACE FUNCTION public.fn_ops_inventorier_objets_stripe_test()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  WITH objets AS (
    SELECT 'customer'::text AS type_objet,
           e.stripe_customer_id AS stripe_id,
           'etablissements'::text AS source_table,
           e.id AS source_id
      FROM public.etablissements e
     WHERE e.est_compte_test IS TRUE
       AND e.stripe_customer_id IS NOT NULL
    UNION ALL
    SELECT 'connect_account', o.stripe_account_id, 'stripe_connect_onboarding', o.id
      FROM public.stripe_connect_onboarding o
      JOIN public.soignants s ON s.id = o.soignant_id
     WHERE s.est_compte_test IS TRUE
       AND o.stripe_account_id IS NOT NULL
    UNION ALL
    SELECT 'payment_intent', pe.stripe_payment_intent_id, 'paiements_escrow', pe.id
      FROM public.paiements_escrow pe
      JOIN public.etablissements e ON e.id = pe.etablissement_id
      JOIN public.soignants s ON s.id = pe.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND pe.stripe_payment_intent_id IS NOT NULL
    UNION ALL
    SELECT 'charge', pe.stripe_charge_id, 'paiements_escrow', pe.id
      FROM public.paiements_escrow pe
      JOIN public.etablissements e ON e.id = pe.etablissement_id
      JOIN public.soignants s ON s.id = pe.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND pe.stripe_charge_id IS NOT NULL
    UNION ALL
    SELECT 'payout', pe.stripe_payout_id, 'paiements_escrow', pe.id
      FROM public.paiements_escrow pe
      JOIN public.etablissements e ON e.id = pe.etablissement_id
      JOIN public.soignants s ON s.id = pe.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND pe.stripe_payout_id IS NOT NULL
    UNION ALL
    SELECT 'payment_intent', f.stripe_payment_intent_id, 'factures', f.id
      FROM public.factures f
      JOIN public.etablissements e ON e.id = f.etablissement_id
     WHERE e.est_compte_test IS TRUE
       AND f.stripe_payment_intent_id IS NOT NULL
    UNION ALL
    SELECT 'payment_intent', f.stripe_payment_intent_id, 'factures_honoraires', f.id
      FROM public.factures_honoraires f
      JOIN public.etablissements e ON e.id = f.etablissement_id
      LEFT JOIN public.soignants s ON s.id = f.soignant_id
     WHERE (
         e.est_compte_test IS TRUE
         OR COALESCE(s.est_compte_test, false) IS TRUE
       )
       AND f.stripe_payment_intent_id IS NOT NULL
    UNION ALL
    SELECT 'payment_intent', p.stripe_payment_intent_id, 'paiements_mission', p.id
      FROM public.paiements_mission p
      JOIN public.missions m ON m.id = p.mission_id
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE (
         e.est_compte_test IS TRUE
         OR COALESCE(s.est_compte_test, false) IS TRUE
       )
       AND p.stripe_payment_intent_id IS NOT NULL
    UNION ALL
    SELECT 'charge', p.stripe_charge_id, 'paiements_mission', p.id
      FROM public.paiements_mission p
      JOIN public.missions m ON m.id = p.mission_id
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE (
         e.est_compte_test IS TRUE
         OR COALESCE(s.est_compte_test, false) IS TRUE
       )
       AND p.stripe_charge_id IS NOT NULL
    UNION ALL
    SELECT 'payment_intent', st.stripe_payment_intent_id, 'stripe_transfers', st.id
      FROM public.stripe_transfers st
      JOIN public.etablissements e ON e.id = st.etablissement_id
      JOIN public.soignants s ON s.id = st.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND st.stripe_payment_intent_id IS NOT NULL
    UNION ALL
    SELECT 'charge', st.stripe_charge_id, 'stripe_transfers', st.id
      FROM public.stripe_transfers st
      JOIN public.etablissements e ON e.id = st.etablissement_id
      JOIN public.soignants s ON s.id = st.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND st.stripe_charge_id IS NOT NULL
    UNION ALL
    SELECT 'transfer', st.stripe_transfer_id, 'stripe_transfers', st.id
      FROM public.stripe_transfers st
      JOIN public.etablissements e ON e.id = st.etablissement_id
      JOIN public.soignants s ON s.id = st.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND st.stripe_transfer_id IS NOT NULL
    UNION ALL
    SELECT 'payout', st.stripe_payout_id, 'stripe_transfers', st.id
      FROM public.stripe_transfers st
      JOIN public.etablissements e ON e.id = st.etablissement_id
      JOIN public.soignants s ON s.id = st.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND st.stripe_payout_id IS NOT NULL
    UNION ALL
    SELECT 'checkout_session', st.stripe_checkout_session_id, 'stripe_transfers', st.id
      FROM public.stripe_transfers st
      JOIN public.etablissements e ON e.id = st.etablissement_id
      JOIN public.soignants s ON s.id = st.soignant_id
     WHERE (e.est_compte_test IS TRUE OR s.est_compte_test IS TRUE)
       AND st.stripe_checkout_session_id IS NOT NULL
    UNION ALL
    SELECT 'refund', q.stripe_refund_id, 'stripe_refunds_queue', q.id
      FROM public.stripe_refunds_queue q
      LEFT JOIN public.paiements_escrow pe ON pe.id = q.paiement_escrow_id
      LEFT JOIN public.factures_honoraires f ON f.id = q.facture_origine_id
      JOIN public.etablissements e
        ON e.id = COALESCE(pe.etablissement_id, f.etablissement_id)
      LEFT JOIN public.soignants s
        ON s.id = COALESCE(pe.soignant_id, f.soignant_id)
     WHERE (
         e.est_compte_test IS TRUE
         OR COALESCE(s.est_compte_test, false) IS TRUE
       )
       AND q.stripe_refund_id IS NOT NULL
  ),
  uniques AS (
    SELECT o.type_objet,
           o.stripe_id,
           jsonb_agg(
             jsonb_build_object(
               'table', o.source_table,
               'id', o.source_id
             )
             ORDER BY o.source_table, o.source_id
           ) AS sources
      FROM objets o
     WHERE btrim(o.stripe_id) <> ''
     GROUP BY o.type_objet, o.stripe_id
  ),
  comptes AS (
    SELECT u.type_objet, count(*)::integer AS nombre
      FROM uniques u
     GROUP BY u.type_objet
  )
  SELECT jsonb_build_object(
    'generated_at', now(),
    'mode', 'READ_ONLY_REVIEW_REQUIRED',
    'destructive_action_taken', false,
    'total_objets', (SELECT count(*) FROM uniques),
    'par_type', COALESCE(
      (SELECT jsonb_object_agg(c.type_objet, c.nombre ORDER BY c.type_objet)
         FROM comptes c),
      '{}'::jsonb
    ),
    'objets', COALESCE(
      (SELECT jsonb_agg(
         jsonb_build_object(
           'type', u.type_objet,
           'stripe_id', u.stripe_id,
           'sources', u.sources
         )
         ORDER BY u.type_objet, u.stripe_id
       ) FROM uniques u),
      '[]'::jsonb
    )
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_ops_inventorier_objets_stripe_test()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ops_inventorier_objets_stripe_test()
  TO service_role;
COMMENT ON FUNCTION public.fn_ops_inventorier_objets_stripe_test() IS
  'Inventaire read-only des IDs Stripe liés aux fixtures; toute action Stripe exige une revue séparée.';

-- ACL ciblées : ces helpers SECURITY DEFINER sont des primitives internes,
-- jamais des RPC client. Les retirer aux utilisateurs supprime cinq alertes
-- réelles sans casser les RPC publiques dont ils sont les sous-routines.
REVOKE ALL ON FUNCTION public.fn_doit_notifier(
  uuid,
  public.type_evenement_notification,
  public.canal_notification
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_doit_notifier(
  uuid,
  public.type_evenement_notification,
  public.canal_notification
) TO service_role;

REVOKE ALL ON FUNCTION public.fn_sms_doit_envoyer(uuid, text, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sms_doit_envoyer(uuid, text, integer)
  TO service_role;

REVOKE ALL ON FUNCTION public.fn_generer_numero_contrat_safe(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_generer_numero_contrat_safe(text)
  TO service_role;

REVOKE ALL ON FUNCTION public.fn_conflit_planning_soignant(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conflit_planning_soignant(uuid, uuid)
  TO service_role;

REVOKE ALL ON FUNCTION public.fn_calculer_score_matching(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_calculer_score_matching(uuid, uuid)
  TO service_role;

-- Les RPC anonymes ci-dessous sont intentionnelles : contenu d'aide/référence,
-- recherche de missions publiques déjà filtrée et hook pre-request. Elles ne
-- doivent pas être révoquées pour « faire baisser » artificiellement le lint.
COMMENT ON FUNCTION public.fn_apercu_marche_profession(
  text,
  double precision,
  double precision,
  integer
) IS 'SECURITY DEFINER anonyme revue : agrégats marché publics, aucune donnée personnelle.';
COMMENT ON FUNCTION public.fn_mission_publique(uuid) IS
  'SECURITY DEFINER anonyme revue : fiche publique filtrée, comptes test exclus.';
COMMENT ON FUNCTION public.fn_missions_publiques_recherche(text, text) IS
  'SECURITY DEFINER anonyme revue : recherche publique filtrée, comptes test exclus.';
COMMENT ON FUNCTION public.fn_pre_request_compte_actif() IS
  'SECURITY DEFINER anonyme revue : hook PostgREST pre-request, aucun résultat métier exposé.';
COMMENT ON FUNCTION public.fn_professions_autorisees_scolarite(text, integer) IS
  'SECURITY DEFINER anonyme revue : référentiel public.';
COMMENT ON FUNCTION public.fn_rechercher_aide(text, text) IS
  'SECURITY DEFINER anonyme revue : centre d aide public.';
COMMENT ON FUNCTION public.fn_types_exercice_autorises(text) IS
  'SECURITY DEFINER anonyme revue : référentiel public.';

-- Inventaire figé des 422 fonctions uniques derrière les 429 lignes advisor
-- (7 fonctions sont comptées à la fois par anon et authenticated dans l'UI).
-- Une signature ou définition ajoutée/modifiée ultérieurement doit être revue
-- et explicitement recapturée par une nouvelle migration.
CREATE TABLE IF NOT EXISTS private.security_definer_inventory (
  signature text PRIMARY KEY,
  categorie text NOT NULL,
  definition_md5 text NOT NULL,
  justification text NOT NULL,
  recense_le timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT security_definer_inventory_categorie_check CHECK (
    categorie IN (
      'PUBLIC_VOLONTAIRE',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'MIXTE_TENANT_ADMIN',
      'ADMIN_EST_ADMIN_VALIDE',
      'SERVICE_ONLY_REVOQUE'
    )
  )
);

REVOKE ALL ON TABLE private.security_definer_inventory
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE private.security_definer_inventory TO service_role;

-- Les wrappers publics SECURITY INVOKER n'élèvent aucun privilège. Leur seul
-- appelant autorisé, service_role, doit donc conserver USAGE sur private et
-- EXECUTE uniquement sur les primitives explicitement listées.
DO $assert_service_role_private_access$
DECLARE
  v_signature text;
BEGIN
  IF NOT has_schema_privilege('service_role', 'private', 'USAGE') THEN
    RAISE EXCEPTION 'service_role sans USAGE sur le schéma private';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.fn_lire_secret_cron_automations()',
    'private.fn_sonder_crons_edge_critiques()',
    'private.fn_desactiver_crons_edge_critiques()',
    'private.fn_etat_sondes_crons_edge_critiques(jsonb)',
    'private.fn_controler_crons_edge_critiques()',
    'private.fn_activer_crons_edge_critiques(jsonb,text)',
    'private.fn_etat_activation_crons_edge_critiques()',
    'private.fn_reserver_envoi_sms_idempotent(text,text)',
    'private.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)',
    'private.fn_reserver_envoi_push_idempotent(text,text)',
    'private.fn_finaliser_envoi_push_idempotent(text,text,text,text,text)',
    'private.fn_mission_est_reelle(uuid)',
    'private.fn_externalisation_est_reelle(public.externalisation_actions)'
  ]::text[]
  LOOP
    IF NOT has_function_privilege('service_role', v_signature, 'EXECUTE') THEN
      RAISE EXCEPTION 'service_role sans EXECUTE sur %', v_signature;
    END IF;
  END LOOP;
END
$assert_service_role_private_access$;

COMMIT;

-- Sources historiques byte-identiques ; jamais remplacées par la candidate.
CREATE OR REPLACE FUNCTION "public"."fn_generer_facture_honoraires_mission"("p_mission_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_numero TEXT;
    v_facture_id UUID;
    v_existing_id UUID;
    v_periode_debut DATE;
    v_periode_fin DATE;
BEGIN
    SELECT m.*, e.nom AS etab_nom
    INTO v_mission
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_mission_id AND m.statut = 'TERMINEE';

    IF v_mission IS NULL THEN
        RETURN '{"error":"Mission introuvable ou non terminée"}'::JSONB;
    END IF;

    IF v_mission.soignant_assigne_id IS NULL THEN
        RETURN '{"error":"Aucun soignant assigné"}'::JSONB;
    END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
    IF v_soignant IS NULL THEN
        RETURN '{"error":"Soignant introuvable"}'::JSONB;
    END IF;

    IF NOT COALESCE(v_soignant.mandat_facturation_signe, FALSE) THEN
        RETURN '{"error":"Le soignant n''a pas encore signé le mandat de facturation"}'::JSONB;
    END IF;

    SELECT id INTO v_existing_id FROM factures_honoraires WHERE mission_id = p_mission_id LIMIT 1;
    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'facture_id', v_existing_id, 'message', 'Facture déjà existante');
    END IF;

    v_numero := 'FH-' || to_char(now(), 'YYYY-MM') || '-' || lpad(
        (COALESCE((SELECT COUNT(*) FROM factures_honoraires WHERE date_emission >= date_trunc('month', now())), 0) + 1)::TEXT,
        4, '0'
    );

    -- Période de la facture = bornes de la mission (NOT NULL en base)
    v_periode_debut := COALESCE(v_mission.debut_le::date, CURRENT_DATE);
    v_periode_fin := COALESCE(v_mission.fin_le::date, v_mission.debut_le::date, CURRENT_DATE);

    INSERT INTO factures_honoraires (
        numero_facture, soignant_id, etablissement_id, mission_id,
        montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
        date_emission, date_echeance, statut, mandat_version,
        periode_debut, periode_fin,
        numero_semaine_iso, annee_iso
    ) VALUES (
        v_numero,
        v_mission.soignant_assigne_id,
        v_mission.etablissement_id,
        p_mission_id,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        TRUE,
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        'EMISE',
        v_soignant.mandat_facturation_version,
        v_periode_debut,
        v_periode_fin,
        EXTRACT(WEEK FROM v_periode_debut)::smallint,
        EXTRACT(ISOYEAR FROM v_periode_debut)::smallint
    ) RETURNING id INTO v_facture_id;

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$$;



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
    'jolene_crm_generer_taches',
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
    'jolene_crm_generer_taches',
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

CREATE OR REPLACE FUNCTION private.fn_reconcilier_crons_edge_critiques_inactifs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_spec record;
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'pg_cron_absent'
    );
  END IF;

  FOR v_spec IN
    SELECT *
      FROM (VALUES
        ('litige-escalation-cron', '0 7 * * *'),
        ('email-cron-hourly-immediate', '* * * * *'),
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
       'jolene_crm_generer_taches',
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

  RETURN jsonb_build_object(
    'success', true,
    'jobs_critiques', 9,
    'jobs_actifs', 0
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'pg_cron_indisponible',
      'sqlstate', SQLSTATE
    );
END;
$function$;
REVOKE ALL ON FUNCTION private.fn_appeler_edge_critique(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_appeler_edge_critique(text,boolean) TO service_role;
REVOKE ALL ON FUNCTION private.fn_sonder_crons_edge_critiques() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_sonder_crons_edge_critiques() TO service_role;
REVOKE ALL ON FUNCTION private.fn_etat_sondes_crons_edge_critiques(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_etat_sondes_crons_edge_critiques(jsonb) TO service_role;
REVOKE ALL ON FUNCTION private.fn_activer_crons_edge_critiques(jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_activer_crons_edge_critiques(jsonb,text) TO service_role;
REVOKE ALL ON FUNCTION private.fn_etat_activation_crons_edge_critiques() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_etat_activation_crons_edge_critiques() TO service_role;
REVOKE ALL ON FUNCTION private.fn_desactiver_crons_edge_critiques() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_desactiver_crons_edge_critiques() TO service_role;
REVOKE ALL ON FUNCTION private.fn_reconcilier_crons_edge_critiques_inactifs() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_reconcilier_crons_edge_critiques_inactifs() TO service_role;

CREATE OR REPLACE FUNCTION "public"."fn_trg_auto_facture_honoraires"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_mandat_signe boolean;
  v_existing_id uuid;
  v_regime text;
BEGIN
  IF NEW.statut <> 'TERMINEE' OR OLD.statut IS NOT DISTINCT FROM 'TERMINEE' THEN
    RETURN NEW;
  END IF;

  v_regime := COALESCE(
    NEW.type_contrat_applique::text,
    CASE WHEN NEW.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL' ELSE 'SALARIE' END
  );
  IF v_regime <> 'LIBERAL' OR NEW.soignant_assigne_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.mode_remuneration = 'RETROCESSION' AND NEW.montant_honoraires_bruts IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(mandat_facturation_signe, false)
    INTO v_mandat_signe
    FROM public.soignants
   WHERE id = NEW.soignant_assigne_id;
  IF NOT COALESCE(v_mandat_signe, false) THEN RETURN NEW; END IF;

  SELECT id INTO v_existing_id
    FROM public.factures_honoraires WHERE mission_id = NEW.id LIMIT 1;
  IF v_existing_id IS NULL THEN
    PERFORM public.fn_generer_facture_honoraires_mission(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_trg_auto_facture_honoraires() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER trg_auto_facture_honoraires AFTER UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION public.fn_trg_auto_facture_honoraires();

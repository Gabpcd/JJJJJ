-- Incident 09/11/2026 (08:06 → 10:16 UTC) : les crons Edge critiques
-- (e-mails immédiats, débit et libération escrow, remboursements Stripe,
-- honoraires, externalisations) échouaient presque à chaque passage sur
--   duplicate key value violates unique constraint "cron_edge_execution_log_pkey"
--
-- Cause : Postgres a redémarré à 08:05:04 UTC. Les tables de pg_net sont
-- UNLOGGED, leur séquence `net.http_request_queue_id_seq` aussi : après un
-- redémarrage non propre, elle repart de 1. Or private.cron_edge_execution_log
-- garde depuis fin juillet 120 636 demandes, clé primaire `request_id` (jusqu'à
-- 163 236) : chaque nouvel identifiant pg_net retombait sur une ligne déjà
-- journalisée, l'INSERT échouait et annulait l'appel Edge. Le déploiement de
-- #1124 a ensuite désactivé les crons et n'a pas pu les réactiver, la sonde
-- tombant sur la même clé (request_id 189).
--
-- Rétablissement en prod (SQL direct d'incident, garde-fous 9.0) :
--   SELECT setval('net.http_request_queue_id_seq', 1000000, true);
-- puis relance de l'étape « Sonder puis activer » du run deploy-supabase
-- 42598226981 : 10 crons critiques actifs, acquisition inactive, passages de
-- 10:16 UTC réussis. Cette migration recapture ce correctif le jour même et le
-- rend durable : le prochain redémarrage remettrait la séquence à 1.
--
-- Définition de départ : LIVE (pg_get_functiondef du 09/11/2026 10:20 UTC) de
-- private.fn_appeler_edge_critique, seul écrivain du journal. Un seul
-- changement : l'appel à private.fn_resynchroniser_sequence_pg_net() avant
-- net.http_post.
--
-- Pourquoi une garde plutôt qu'une nouvelle clé : les lecteurs du journal
-- (contrôleur, état des sondes, activation) relient une ligne à sa réponse par
-- `request_id`. Tant que ces identifiants ne sont pas uniques dans le temps,
-- une clé composite déplacerait seulement l'ambiguïté vers ces jointures. La
-- garde rétablit l'invariant dont ils dépendent : tout identifiant pg_net
-- nouveau est strictement supérieur à tout identifiant déjà journalisé.

CREATE OR REPLACE FUNCTION private.fn_resynchroniser_sequence_pg_net()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_max_journal bigint;
  v_courant bigint;
  v_appele boolean;
  v_cible bigint;
BEGIN
  -- Sans pg_net (branches preview, bancs isolés), rien à resynchroniser.
  IF pg_catalog.to_regclass('net.http_request_queue_id_seq') IS NULL THEN
    RETURN NULL;
  END IF;

  -- Sérialise les appels concurrents jusqu'à la fin de la transaction : un
  -- appel ne lit l'état qu'après l'INSERT validé du précédent, et la séquence
  -- ne recule jamais. Le verrou est réentrant (la sonde appelle 9 fois dans
  -- la même transaction).
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('jolene:pg_net:request_id')
  );

  -- Parcours de l'index de clé primaire : coût constant.
  SELECT max(l.request_id)
    INTO v_max_journal
    FROM private.cron_edge_execution_log l;

  IF v_max_journal IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT s.last_value, s.is_called
    INTO v_courant, v_appele
    FROM net.http_request_queue_id_seq s;

  -- Dernier identifiant réellement émis : si `is_called` est faux, le prochain
  -- nextval rendra `last_value` lui-même.
  IF NOT v_appele THEN
    v_courant := v_courant - 1;
  END IF;

  -- En régime normal, la séquence est toujours au-dessus du journal (tout
  -- identifiant journalisé en sort). Elle n'y repasse que si elle a été
  -- remise à zéro : on saute alors bien au-delà, pour qu'un appel pg_net
  -- concurrent hors de ce verrou ne puisse pas croiser le saut.
  IF v_courant < v_max_journal THEN
    v_cible := v_max_journal + 100000;
    PERFORM pg_catalog.setval('net.http_request_queue_id_seq', v_cible, true);
    RAISE WARNING 'Séquence pg_net remise à zéro (% < %) : resynchronisée à %. Voir docs/incidents/2026-11-09-sequence-pg-net-journal-crons.md',
      v_courant, v_max_journal, v_cible;
    RETURN v_cible;
  END IF;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_resynchroniser_sequence_pg_net() FROM PUBLIC;
DO $grants$
BEGIN
  IF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON FUNCTION private.fn_resynchroniser_sequence_pg_net() FROM anon;
  END IF;
  IF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON FUNCTION private.fn_resynchroniser_sequence_pg_net() FROM authenticated;
  END IF;
END
$grants$;

CREATE OR REPLACE FUNCTION private.fn_appeler_edge_critique(p_job_name text, p_est_sonde_auth boolean DEFAULT false)
 RETURNS bigint
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
    WHEN 'honoraires-emission-demandes' THEN
      v_endpoint := 'weekly-invoicing-cron';
      v_body := jsonb_build_object('mode','demandes');
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

  -- Incident 09/11/2026 : après un redémarrage, la séquence UNLOGGED de
  -- pg_net repart de 1 et ses identifiants retombaient sur des lignes déjà
  -- journalisées (clé primaire request_id).
  PERFORM private.fn_resynchroniser_sequence_pg_net();

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

-- Rattrapage immédiat (no-op en prod, déjà à 1 000 000 depuis le correctif
-- d'incident ; utile si un redémarrage survient avant le prochain appel).
DO $rattrapage$
BEGIN
  IF pg_catalog.to_regclass('private.cron_edge_execution_log') IS NOT NULL THEN
    PERFORM private.fn_resynchroniser_sequence_pg_net();
  END IF;
END
$rattrapage$;

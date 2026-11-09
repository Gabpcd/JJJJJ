-- Incident 09/11/2026 : après un redémarrage de Postgres, la séquence UNLOGGED
-- de pg_net repart de 1 et les crons Edge critiques échouaient sur la clé
-- primaire de private.cron_edge_execution_log. Banc PostgreSQL 17 isolé :
-- pg_net, Vault et le journal sont reproduits avec leurs noms réels.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE SCHEMA private;
CREATE SCHEMA net;
CREATE SCHEMA vault;

CREATE TABLE vault.decrypted_secrets(name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES
  ('supabase_url', 'https://exemple.supabase.co/'),
  ('cron_automations_key', 'secret-de-banc');

-- Comme pg_net : file UNLOGGED, identifiant issu de net.http_request_queue_id_seq.
CREATE UNLOGGED TABLE net.http_request_queue(
  id bigserial PRIMARY KEY,
  url text NOT NULL,
  headers jsonb,
  body jsonb
);
CREATE FUNCTION net.http_post(url text, headers jsonb, body jsonb, timeout_milliseconds integer)
RETURNS bigint LANGUAGE sql AS $f$
  INSERT INTO net.http_request_queue(url, headers, body) VALUES (url, headers, body) RETURNING id
$f$;

-- Définition de 20260729121442.
CREATE TABLE private.cron_edge_execution_log (
  request_id bigint PRIMARY KEY,
  job_name text NOT NULL,
  endpoint text NOT NULL,
  est_sonde_auth boolean NOT NULL DEFAULT false,
  demande_le timestamptz NOT NULL DEFAULT now(),
  controle_le timestamptz,
  statut_http integer,
  erreur_transport text
);

-- Journal ancien (août), séquence neuve : l'état de la prod le 09/11 à 08:06.
INSERT INTO private.cron_edge_execution_log(request_id, job_name, endpoint, demande_le, controle_le, statut_http)
SELECT g, 'escrow-release', 'escrow-release', timestamptz '2026-08-12 00:00+00' + g * interval '1 minute', now(), 200
  FROM generate_series(1, 500) g;

\ir ../../supabase/migrations/20261109102500_sequence_pg_net_journal_crons_edge.sql

DO $t$
DECLARE
  v_last bigint;
  v_id bigint;
  v_suivant bigint;
  v_ids bigint[] := '{}';
  v_job text;
BEGIN
  -- 1. Le rattrapage de la migration a déjà sorti la séquence du journal.
  SELECT last_value INTO v_last FROM net.http_request_queue_id_seq;
  IF v_last <= 500 THEN
    RAISE EXCEPTION 'RATTRAPAGE_ABSENT : séquence à %', v_last;
  END IF;

  -- 2. Nouveau redémarrage simulé : l'appel ne doit plus heurter la clé.
  PERFORM setval('net.http_request_queue_id_seq', 1, false);
  v_id := private.fn_appeler_edge_critique('escrow-release');
  IF v_id <= 500 THEN
    RAISE EXCEPTION 'COLLISION_POSSIBLE : identifiant % sous le journal', v_id;
  END IF;
  IF NOT EXISTS (SELECT FROM private.cron_edge_execution_log WHERE request_id = v_id AND job_name = 'escrow-release' AND NOT est_sonde_auth) THEN
    RAISE EXCEPTION 'JOURNAL_ABSENT pour %', v_id;
  END IF;

  -- 3. Régime normal : aucun saut, la séquence avance d'un pas.
  v_suivant := private.fn_appeler_edge_critique('email-cron-hourly-immediate');
  IF v_suivant <> v_id + 1 THEN
    RAISE EXCEPTION 'SAUT_EN_REGIME_NORMAL : % puis %', v_id, v_suivant;
  END IF;

  -- 3 bis. Séquence non appelée posée exactement sur le maximum du journal :
  --    le prochain nextval rendrait ce maximum, la garde doit sauter.
  PERFORM setval('net.http_request_queue_id_seq', v_suivant, false);
  v_suivant := private.fn_appeler_edge_critique('process-stripe-refunds-15min');
  IF v_suivant <= v_id + 1 THEN
    RAISE EXCEPTION 'IS_CALLED_IGNORE : identifiant %', v_suivant;
  END IF;

  -- 4. Sonde de deploy-supabase : 9 appels dans une même transaction, juste
  --    après un redémarrage. Identifiants distincts, tous au-dessus du journal.
  PERFORM setval('net.http_request_queue_id_seq', 1, false);
  FOREACH v_job IN ARRAY ARRAY[
    'litige-escalation-cron', 'email-cron-hourly-immediate', 'email-cron-daily',
    'process-stripe-refunds-15min', 'escrow-debit-echeance', 'escrow-release',
    'jolene_process_externalisations', 'weekly-invoicing-cron', 'honoraires-emission-demandes'
  ] LOOP
    v_ids := v_ids || private.fn_appeler_edge_critique(v_job, true);
  END LOOP;
  IF (SELECT count(DISTINCT x) FROM unnest(v_ids) x) <> 9
     OR (SELECT min(x) FROM unnest(v_ids) x) <= v_suivant THEN
    RAISE EXCEPTION 'SONDE_INVALIDE : %', v_ids;
  END IF;

  -- 5. L'allowlist fermée est conservée.
  BEGIN
    PERFORM private.fn_appeler_edge_critique('job-inconnu');
    RAISE EXCEPTION 'ALLOWLIST_OUVERTE';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- 6. La garde n'est pas exécutable par PUBLIC.
  IF EXISTS (
    SELECT FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = 'private.fn_resynchroniser_sequence_pg_net()'::regprocedure
       AND a.grantee = 0
  ) THEN
    RAISE EXCEPTION 'GARDE_EXECUTABLE_PAR_PUBLIC';
  END IF;
END
$t$;

-- 7. Sans pg_net (branches preview), la garde est un no-op sans erreur.
DROP TABLE net.http_request_queue CASCADE;
DO $t$
BEGIN
  IF private.fn_resynchroniser_sequence_pg_net() IS NOT NULL THEN
    RAISE EXCEPTION 'GARDE_SANS_PG_NET';
  END IF;
END
$t$;

SELECT 'sequence-pg-net-journal-crons : 8 scénarios OK' AS resultat;

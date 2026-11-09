-- Banc PG17 isolé B5b : le préflight refuse un corps qui n'est plus le corps LIVE.
-- Première application : doit réussir (marqueur sur stdout). Seconde
-- application dans la même transaction : les corps ne sont plus ceux relus en
-- production, le préflight doit lever VISIBILITE_ETAB_PREFLIGHT_SOURCE_DRIFT
-- sur la première RPC, avant toute redéfinition. Ce script DOIT échouer ; le
-- workflow vérifie le code de sortie, le marqueur et le message exact.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'visibilite_etab_rejeu'
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
\ir fixtures/visibilite-etablissement-permission-banc.sql

\ir ../../supabase/migrations/20261102210943_visibilite_etablissement_par_permission.sql
DO $premiere$ BEGIN
  IF EXISTS (
    SELECT FROM private.security_definer_inventory i
    JOIN pg_proc p ON p.oid = to_regprocedure('public.' || i.signature)
    WHERE md5(p.prosrc) IS DISTINCT FROM i.definition_md5
  ) OR (SELECT count(*) FROM private.security_definer_inventory) <> 3
  THEN RAISE EXCEPTION 'VISIBILITE_ETAB_PREMIERE_APPLICATION_INCOHERENTE'; END IF;
END $premiere$;
SELECT 'VISIBILITE_ETAB_PREMIERE_APPLICATION_OK' AS marqueur;

\ir ../../supabase/migrations/20261102210943_visibilite_etablissement_par_permission.sql
SELECT 'VISIBILITE_ETAB_REJEU_ACCEPTE' AS marqueur;
ROLLBACK;

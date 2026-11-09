-- Banc PG17 isolé (B9) : les gardes de la migration DPAE refusent un rejeu et
-- un corps LIVE dérivé. Ce script DOIT échouer ; le workflow vérifie le code
-- de sortie, le marqueur de préparation (stdout) et le message exact (stderr).
-- Scénario passé par psql -v scenario=… :
--   * rejeu : seconde application après une première réussie → le préflight
--     lève DPAE_SALARIE_PREFLIGHT_HELPER_DEJA_PRESENT ;
--   * rejeu_sans_helper : première application, helper supprimé, nouvelle
--     transaction simulée (capture supprimée) → les corps ne portent plus
--     l'ancienne liste : DPAE_SALARIE_PREFLIGHT_SOURCE_DRIFT: fn_mes_dpae() ;
--   * corps_derive : le corps LIVE de fn_rappel_dpae_quotidien diffère hors de
--     la liste (préflight satisfait) → la garde md5 calculée du postflight lève
--     DPAE_SALARIE_POSTFLIGHT_CORPS_OU_ATTRIBUTS: fn_rappel_dpae_quotidien().
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_catalog.set_config('banc.scenario', :'scenario', true) AS scenario;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_setting('banc.scenario', true) NOT IN ('rejeu', 'rejeu_sans_helper', 'corps_derive')
    OR current_database() IS DISTINCT FROM ('dpae_salarie_' || current_setting('banc.scenario', true))
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'DPAE_SALARIE_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
\ir fixtures/dpae-contrats-cddu-vacation-banc.sql

SELECT current_setting('banc.scenario') = 'corps_derive' AS sc_derive,
       current_setting('banc.scenario') = 'rejeu_sans_helper' AS sc_sans_helper \gset

\if :sc_derive
-- Dérive hors liste : une ligne du corps LIVE change, la liste reste l'ancienne.
DO $derive$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.fn_rappel_dpae_quotidien()'::regprocedure);
  IF strpos(v_def, 'v_count := v_count + 1;') = 0 THEN
    RAISE EXCEPTION 'DPAE_SALARIE_DERIVE_ANCRE_ABSENTE';
  END IF;
  EXECUTE replace(v_def, 'v_count := v_count + 1;', 'v_count := v_count + 1; -- dérive hors liste');
END $derive$;
SELECT 'DPAE_SALARIE_CORPS_DERIVE_PRET' AS marqueur;
\else
\ir ../../supabase/migrations/20261108223500_dpae_contrats_cddu_vacation.sql
DO $premiere$ BEGIN
  IF to_regprocedure('public.fn_type_contrat_salarie(text)') IS NULL
    OR EXISTS (
      SELECT FROM private.security_definer_inventory i
      JOIN pg_proc p ON p.oid = to_regprocedure('public.' || i.signature)
      WHERE md5(p.prosrc) IS DISTINCT FROM i.definition_md5)
    OR (SELECT count(*) FROM private.security_definer_inventory) <> 3
    OR (SELECT count(*) FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace
           AND strpos(p.prosrc, 'public.fn_type_contrat_salarie(') > 0) <> 5
  THEN RAISE EXCEPTION 'DPAE_SALARIE_PREMIERE_APPLICATION_INCOHERENTE'; END IF;
END $premiere$;
SELECT 'DPAE_SALARIE_PREMIERE_APPLICATION_OK' AS marqueur;
\if :sc_sans_helper
DROP FUNCTION public.fn_type_contrat_salarie(text);
DROP TABLE _dpae_salarie_avant;
SELECT 'DPAE_SALARIE_REJEU_SANS_HELPER_PRET' AS marqueur;
\else
SELECT 'DPAE_SALARIE_REJEU_PRET' AS marqueur;
\endif
\endif

\ir ../../supabase/migrations/20261108223500_dpae_contrats_cddu_vacation.sql
SELECT 'DPAE_SALARIE_MIGRATION_ACCEPTEE' AS marqueur;
ROLLBACK;

-- Banc PG17 isolé B9 « gardes NULL » : les gardes calculées des deux
-- migrations refusent un rejeu et un corps LIVE dérivé. Ce script DOIT
-- échouer ; le workflow vérifie le code de sortie, le marqueur de préparation
-- (stdout) et le message exact (stderr). Scénario passé par psql -v scenario=… :
--   * rejeu : les deux migrations appliquées, nouvelle transaction simulée
--     (table temporaire de capture supprimée), puis 20261109010957 rejouée →
--     les corps ne portent plus la garde LIVE :
--     GARDES_NULL_PREFLIGHT_SOURCE_DRIFT: fn_valider_alerte_presence(uuid) ;
--   * corps_derive : le corps LIVE de fn_annuler_serie diffère hors de la
--     garde (inventaire recapturé, préflight satisfait) → la garde md5
--     calculée du postflight lève
--     GARDES_NULL_POSTFLIGHT_CORPS_OU_ATTRIBUTS: fn_annuler_serie(uuid) ;
--   * rejeu_verrou : les deux migrations appliquées, puis 20261109020404
--     rejouée → authenticated n'a plus EXECUTE :
--     VERROU_FACTURE_PREFLIGHT_ACL_DRIFT: fn_generer_facture(uuid).
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_catalog.set_config('banc.scenario', :'scenario', true) AS scenario;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_setting('banc.scenario', true) NOT IN ('rejeu', 'corps_derive', 'rejeu_verrou')
    OR current_database() IS DISTINCT FROM ('gardes_null_' || current_setting('banc.scenario', true))
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'GARDES_NULL_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
\ir fixtures/visibilite-etablissement-permission-banc.sql
\ir fixtures/gardes-null-security-definer-banc.sql

SELECT current_setting('banc.scenario') = 'corps_derive' AS sc_derive,
       current_setting('banc.scenario') = 'rejeu_verrou' AS sc_verrou \gset

\if :sc_derive
-- Dérive hors garde : une ligne du corps LIVE change, la garde reste la garde
-- LIVE ; l'inventaire suit la dérive (sinon le préflight la refuserait déjà).
DO $derive$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.fn_annuler_serie(uuid)'::regprocedure);
  IF strpos(v_def, 'RETURN jsonb_build_object(''success'', true, ''missions_annulees'', v_count);') = 0 THEN
    RAISE EXCEPTION 'GARDES_NULL_DERIVE_ANCRE_ABSENTE';
  END IF;
  EXECUTE replace(v_def,
    'RETURN jsonb_build_object(''success'', true, ''missions_annulees'', v_count);',
    'RETURN jsonb_build_object(''success'', true, ''missions_annulees'', v_count); -- dérive hors garde');
  UPDATE private.security_definer_inventory i
     SET definition_md5 = md5(p.prosrc)
    FROM pg_proc p
   WHERE p.oid = 'public.fn_annuler_serie(uuid)'::regprocedure
     AND i.signature = 'fn_annuler_serie(uuid)';
END $derive$;
SELECT 'GARDES_NULL_CORPS_DERIVE_PRET' AS marqueur;
\ir ../../supabase/migrations/20261109010957_gardes_null_security_definer.sql
\else
\ir ../../supabase/migrations/20261109010957_gardes_null_security_definer.sql
\ir ../../supabase/migrations/20261109020404_verrou_double_facturation_generer_facture.sql
DO $premiere$ BEGIN
  IF EXISTS (
      SELECT FROM private.security_definer_inventory i
      JOIN pg_proc p ON p.oid = to_regprocedure('public.' || i.signature)
      WHERE i.justification = 'fixture gardes NULL'
        AND md5(p.prosrc) IS DISTINCT FROM i.definition_md5)
    OR has_function_privilege('authenticated', 'public.fn_generer_facture(uuid)', 'EXECUTE')
  THEN RAISE EXCEPTION 'GARDES_NULL_PREMIERE_APPLICATION_INCOHERENTE'; END IF;
END $premiere$;
SELECT 'GARDES_NULL_PREMIERE_APPLICATION_OK' AS marqueur;
\if :sc_verrou
SELECT 'GARDES_NULL_REJEU_VERROU_PRET' AS marqueur;
\ir ../../supabase/migrations/20261109020404_verrou_double_facturation_generer_facture.sql
\else
-- Nouvelle transaction simulée : la capture ON COMMIT DROP n'existe plus.
DROP TABLE _gardes_null_avant;
SELECT 'GARDES_NULL_REJEU_PRET' AS marqueur;
\ir ../../supabase/migrations/20261109010957_gardes_null_security_definer.sql
\endif
\endif

SELECT 'GARDES_NULL_MIGRATION_ACCEPTEE' AS marqueur;
ROLLBACK;

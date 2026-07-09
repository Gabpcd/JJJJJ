-- ═══════════════════════════════════════════════════════════════════════════
-- Test non-régression : INSERT réel dans journaux_audit, vérification, ROLLBACK.
--
-- ⚠️  JAMAIS EN PROD. Ce script est réservé à une base locale (supabase db
--     start), une branche Supabase ou la CI. La transaction est intégralement
--     annulée (ROLLBACK final) : zéro persistance — même pattern que les
--     vérifs zéro-persistance des sessions précédentes.
--
-- Ce qu'il prouve : les colonnes réelles de journaux_audit acceptent l'INSERT
-- exact que fait fn_ecrire_audit_safe (incident du 05/07 : la fonction visait
-- des colonnes inexistantes et 74 call sites n'écrivaient jamais d'audit).
-- Les valeurs SYSTEM/SYSTEM respectent journaux_audit_action_check et
-- journaux_audit_type_acteur_check.
--
-- Usage :
--   psql "$SUPABASE_DB_URL_LOCALE" -v ON_ERROR_STOP=1 \
--        -f tests/non-regression/sql/audit-insert.test.sql
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.journaux_audit
  (acteur_id, type_acteur, action, type_ressource, id_ressource,
   cle_s3_ressource, details, ip_acteur, navigateur_acteur)
VALUES
  (NULL, 'SYSTEM', 'SYSTEM', 'TEST_NON_REGRESSION', NULL,
   NULL, '{"test": "non-regression-audit-insert"}'::jsonb, NULL, 'schema-guard');

DO $verif$
DECLARE
  v_nb integer;
BEGIN
  SELECT count(*) INTO v_nb
  FROM public.journaux_audit
  WHERE type_ressource = 'TEST_NON_REGRESSION'
    AND details ->> 'test' = 'non-regression-audit-insert';

  IF v_nb <> 1 THEN
    RAISE EXCEPTION 'audit-insert.test.sql : % ligne(s) trouvée(s) au lieu de 1', v_nb;
  END IF;

  RAISE NOTICE 'audit-insert.test.sql : INSERT journaux_audit OK (1 ligne, rollback à suivre)';
END;
$verif$;

ROLLBACK;

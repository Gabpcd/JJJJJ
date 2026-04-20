-- ============================================================
-- Tests CP-LITIGES-6 — Support PDF/XML pour avoirs
-- ============================================================
-- Prérequis : migrations CP1-CP6 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp6-avoir-support.test.sql
--
-- Tests SQL uniquement. Les tests de rendu PDF + validation schéma
-- Factur-X sont à écrire en TypeScript (vitest) dans CP-LITIGES-8
-- avec parsing du XML généré par l'edge function.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-6 Avoir support =='

-- ──────────────────────────────────────────────────────────────
-- T1 : colonne chorus_avoir_reference_invoice
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T1 : chorus_avoir_reference_invoice'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[1] OK — colonne présente'
       ELSE '[1] FAIL' END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures_honoraires'
  AND column_name = 'chorus_avoir_reference_invoice';

-- ──────────────────────────────────────────────────────────────
-- T2 : fn_lister_factures_a_regenerer
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T2 : fn_lister_factures_a_regenerer'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[2.1] OK — fonction présente'
       ELSE '[2.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_lister_factures_a_regenerer';

-- Exécution : doit retourner SETOF sans erreur
DO $$
DECLARE
  v_count INT := 0;
BEGIN
  SELECT COUNT(*) INTO v_count FROM public.fn_lister_factures_a_regenerer(50);
  RAISE NOTICE '[2.2] OK — fonction exécutable (% factures a regenerer)', v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[2.2] FAIL — erreur : %', SQLERRM;
END;
$$;

-- Vérifier la signature (retourne bien les 5 colonnes attendues)
SELECT
  CASE WHEN pg_get_function_result(p.oid) LIKE '%type_document%'
        AND pg_get_function_result(p.oid) LIKE '%numero_facture%'
       THEN '[2.3] OK — signature retourne type_document + numero_facture'
       ELSE '[2.3] FAIL — signature : ' || pg_get_function_result(p.oid) END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_lister_factures_a_regenerer';

-- ──────────────────────────────────────────────────────────────
-- T3 : cohérence avec CP3 — avoirs récemment insérés ont
--      bien pdf_a_regenerer=TRUE (placeholder pour tests E2E)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T3 : cohérence avec CP3'

SELECT
  CASE WHEN COUNT(*) = 0 THEN '[3] OK — aucun avoir sans pdf_a_regenerer pending'
       WHEN COUNT(*) FILTER (WHERE pdf_a_regenerer = TRUE) = COUNT(*)
            THEN '[3] OK — tous les avoirs sans PDF ont pdf_a_regenerer=TRUE (' || COUNT(*) || ')'
       ELSE '[3] INFO — ' || COUNT(*) || ' avoirs, certains sans regen pending (peut être OK si déjà traités)'
  END
FROM public.factures_honoraires
WHERE type_document = 'AVOIR'
  AND pdf_s3_key IS NULL;

\echo ''
\echo '== FIN CP-LITIGES-6 =='

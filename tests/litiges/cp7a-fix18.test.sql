-- ============================================================
-- Tests CP-LITIGES-7a FIX 18 — Regen PDF immédiat via pg_net
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 18 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix18.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 18 =='

-- [1] Extension pg_net installée dans le schéma extensions
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[18.1] OK — extension pg_net présente'
  ELSE '[18.1] FAIL — pg_net manquant'
END
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'pg_net'
  AND n.nspname = 'extensions';

-- [2] Fonction net.http_post accessible
SELECT CASE
  WHEN COUNT(*) >= 1
    THEN '[18.2] OK — net.http_post accessible'
  ELSE '[18.2] FAIL — net.http_post introuvable'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'net'
  AND p.proname = 'http_post';

-- [3] Paramètre generate_invoice_url seedé
SELECT CASE
  WHEN COUNT(*) = 1 AND MAX(length(valeur)) > 10
    THEN '[18.3] OK — parametres_litiges.generate_invoice_url seedé'
  ELSE '[18.3] FAIL — clé absente ou vide'
END
FROM public.parametres_litiges
WHERE cle = 'generate_invoice_url';

-- [4] Helper fn_trigger_regen_pdf_immediate existe (signature UUID)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[18.4] OK — fn_trigger_regen_pdf_immediate(UUID) présente'
  ELSE '[18.4] FAIL'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_trigger_regen_pdf_immediate';

-- [5] Helper est SECURITY DEFINER + retourne BIGINT
SELECT CASE
  WHEN prosecdef = TRUE AND t.typname = 'int8'
    THEN '[18.5] OK — SECURITY DEFINER + retour BIGINT'
  ELSE '[18.5] FAIL — secdef=' || prosecdef || ', retour=' || t.typname
END
FROM pg_proc p
JOIN pg_type t ON t.oid = p.prorettype
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_trigger_regen_pdf_immediate';

-- [6] Helper renvoie NULL si facture_id NULL (sans exception)
DO $$
DECLARE v_ret BIGINT;
BEGIN
  SELECT public.fn_trigger_regen_pdf_immediate(NULL) INTO v_ret;
  IF v_ret IS NULL THEN
    RAISE NOTICE '[18.6] OK — helper retourne NULL sur input NULL';
  ELSE
    RAISE NOTICE '[18.6] FAIL — attendu NULL, reçu %', v_ret;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[18.6] FAIL — exception inattendue : %', SQLERRM;
END $$;

-- [7] fn_admin_resoudre_litige appelle fn_trigger_regen_pdf_immediate
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[18.7] OK — fn_admin_resoudre_litige contient l''appel pg_net'
  ELSE '[18.7] FAIL — appel fn_trigger_regen_pdf_immediate absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_resoudre_litige'
  AND p.prosrc LIKE '%fn_trigger_regen_pdf_immediate%';

-- [8] fn_admin_resoudre_litige consigne regen_pdf_request_ids dans l'audit
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[18.8] OK — audit JSONB enrichi avec regen_pdf_request_ids'
  ELSE '[18.8] FAIL — clé regen_pdf_request_ids absente du source'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_resoudre_litige'
  AND p.prosrc LIKE '%regen_pdf_request_ids%';

-- [9] fn_lister_factures_a_regenerer filtre modifie_le < NOW() - 1 hour
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[18.9] OK — fn_lister_factures_a_regenerer filtre modifie_le < NOW() - 1h'
  ELSE '[18.9] FAIL — filtre 1h absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_lister_factures_a_regenerer'
  AND p.prosrc LIKE '%INTERVAL ''1 hour''%';

-- [10] Helper accessible en service_role (GRANT EXECUTE)
SELECT CASE
  WHEN has_function_privilege('service_role', p.oid, 'EXECUTE')
    THEN '[18.10] OK — service_role peut exécuter fn_trigger_regen_pdf_immediate'
  ELSE '[18.10] FAIL — privilège EXECUTE manquant'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_trigger_regen_pdf_immediate';

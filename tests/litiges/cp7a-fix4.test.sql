-- ============================================================
-- Tests CP-LITIGES-7a FIX 4 — Cohérence clé rate_limit
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 4 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix4.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 4 =='

-- [1] Le seed sous la nouvelle clé existe avec la valeur 3
SELECT CASE
  WHEN COUNT(*) = 1 AND MIN(valeur) = '3'
    THEN '[4.1] OK — rate_limit_litiges_par_heure présent avec valeur=3'
  WHEN COUNT(*) = 1
    THEN '[4.1] WARN — présent mais valeur=' || MIN(valeur) || ' (attendu 3)'
  ELSE '[4.1] FAIL — ' || COUNT(*) || ' ligne(s) (attendu 1)'
END
FROM public.parametres_litiges
WHERE cle = 'rate_limit_litiges_par_heure';

-- [2] Aucune ligne résiduelle sous l'ancienne clé
SELECT CASE
  WHEN COUNT(*) = 0
    THEN '[4.2] OK — aucune ligne sous rate_limit_litiges_par_24h'
  ELSE '[4.2] FAIL — ' || COUNT(*) || ' ligne(s) résiduelle(s) sous ancienne clé'
END
FROM public.parametres_litiges
WHERE cle = 'rate_limit_litiges_par_24h';

-- [3] Aucune fonction pg_proc ne référence l'ancienne clé
SELECT CASE
  WHEN COUNT(*) = 0
    THEN '[4.3] OK — aucune fonction ne lit rate_limit_litiges_par_24h'
  ELSE '[4.3] FAIL — ' || COUNT(*) || ' fonction(s) référencent l''ancienne clé : '
       || string_agg(n.nspname || '.' || p.proname, ', ')
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosrc ILIKE '%rate_limit_litiges_par_24h%';

-- [4] Au moins une fonction (fn_ouvrir_litige_rate_limited 3-arg) référence
-- la nouvelle clé
SELECT CASE
  WHEN COUNT(*) >= 1
    THEN '[4.4] OK — ' || COUNT(*) || ' fonction(s) lisent rate_limit_litiges_par_heure'
  ELSE '[4.4] FAIL — aucune fonction ne lit la nouvelle clé'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosrc ILIKE '%rate_limit_litiges_par_heure%';

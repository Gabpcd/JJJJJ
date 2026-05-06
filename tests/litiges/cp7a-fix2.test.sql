-- ============================================================
-- Tests CP-LITIGES-7a FIX 2 — Audit wrapper legacy 2-arg
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 2 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix2.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 2 =='

-- [1] Wrapper 2-arg existe toujours
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[2.1] OK — wrapper 2-arg fn_ouvrir_litige_rate_limited(UUID, TEXT) présent'
  ELSE '[2.1] FAIL — absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_ouvrir_litige_rate_limited'
  AND pg_get_function_identity_arguments(p.oid) = 'p_mission_id uuid, p_motif text';

-- [2] Signature 3-arg existe aussi (pas cassée par le CREATE OR REPLACE du 2-arg)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[2.2] OK — signature 3-arg (UUID, type_litige, TEXT) intacte'
  ELSE '[2.2] FAIL — absente'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_ouvrir_litige_rate_limited'
  AND pg_get_function_identity_arguments(p.oid) LIKE '%type_litige%';

-- [3] Corps du wrapper 2-arg contient fn_ecrire_audit + LITIGE_OUVERTURE_LEGACY
SELECT CASE
  WHEN prosrc ILIKE '%fn_ecrire_audit%'
   AND prosrc ILIKE '%LITIGE_OUVERTURE_LEGACY%'
    THEN '[2.3] OK — corps du wrapper contient audit LITIGE_OUVERTURE_LEGACY'
  ELSE '[2.3] FAIL — fn_ecrire_audit ou LITIGE_OUVERTURE_LEGACY absent du corps'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_ouvrir_litige_rate_limited'
  AND pg_get_function_identity_arguments(p.oid) = 'p_mission_id uuid, p_motif text';

-- [4] Corps du wrapper 2-arg conserve le RAISE WARNING DEPRECATED
SELECT CASE
  WHEN prosrc ILIKE '%DEPRECATED%'
   AND prosrc ILIKE '%RAISE WARNING%'
    THEN '[2.4] OK — RAISE WARNING DEPRECATED conservé'
  ELSE '[2.4] FAIL — RAISE WARNING DEPRECATED manquant'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_ouvrir_litige_rate_limited'
  AND pg_get_function_identity_arguments(p.oid) = 'p_mission_id uuid, p_motif text';

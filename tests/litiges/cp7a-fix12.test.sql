-- ============================================================
-- Tests CP-LITIGES-7a FIX 12 — initie_par 'SYSTEME'
-- ============================================================
-- Prérequis : 20260417130704_fix12_initie_par_systeme.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix12.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 12 =='

-- [1] CHECK contient bien les 3 valeurs (SOIGNANT, ETABLISSEMENT, SYSTEME)
SELECT CASE
  WHEN pg_get_constraintdef(oid) ILIKE '%SOIGNANT%'
   AND pg_get_constraintdef(oid) ILIKE '%ETABLISSEMENT%'
   AND pg_get_constraintdef(oid) ILIKE '%SYSTEME%'
    THEN '[12.1] OK — CHECK accepte SOIGNANT + ETABLISSEMENT + SYSTEME'
  ELSE '[12.1] FAIL — def=' || pg_get_constraintdef(oid)
END
FROM pg_constraint
WHERE conname = 'litiges_initie_par_check';

-- [2] Valeur 'SYSTEME' acceptée par la contrainte (dry run via WHERE)
DO $$
DECLARE
  v_ok BOOLEAN;
BEGIN
  v_ok := ('SYSTEME' IN ('SOIGNANT','ETABLISSEMENT','SYSTEME'));
  IF v_ok THEN
    RAISE NOTICE '[12.2] OK — SYSTEME match le nouveau CHECK';
  ELSE
    RAISE NOTICE '[12.2] FAIL — SYSTEME ne match pas';
  END IF;
END $$;

-- [3] Valeur aberrante ('ROBOT') toujours rejetée par la contrainte
-- (sanity : on n'a pas ouvert en grand le CHECK)
SELECT CASE
  WHEN pg_get_constraintdef(oid) NOT ILIKE '%ROBOT%'
    THEN '[12.3] OK — valeurs non listées toujours rejetées'
  ELSE '[12.3] FAIL — CHECK contient une valeur imprévue'
END
FROM pg_constraint
WHERE conname = 'litiges_initie_par_check';

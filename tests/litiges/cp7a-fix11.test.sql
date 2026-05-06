-- ============================================================
-- Tests CP-LITIGES-7a FIX 11 — presences.litige_auto_cree_le
-- ============================================================
-- Prérequis : 20260417130703_fix11_presences_litige_auto.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix11.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 11 =='

-- [1] Colonne présente avec bon type (timestamp with time zone) + nullable
SELECT CASE
  WHEN data_type = 'timestamp with time zone' AND is_nullable = 'YES'
    THEN '[11.1] OK — presences.litige_auto_cree_le TIMESTAMPTZ nullable'
  ELSE '[11.1] FAIL — type=' || data_type || ' nullable=' || is_nullable
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'presences'
  AND column_name = 'litige_auto_cree_le';

-- [2] Pas de valeur par défaut (doit rester NULL à l'insertion)
SELECT CASE
  WHEN column_default IS NULL
    THEN '[11.2] OK — pas de default (NULL à l''insertion)'
  ELSE '[11.2] FAIL — default=' || column_default
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'presences'
  AND column_name = 'litige_auto_cree_le';

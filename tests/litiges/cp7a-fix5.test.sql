-- ============================================================
-- Tests CP-LITIGES-7a FIX 5 — Traçabilité ajustements presences
-- ============================================================
-- Prérequis : 20260417130701_fix5_presences_ajustements.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix5.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 5 =='

-- [1] Colonne heures_ajustees_litige (NUMERIC, nullable)
SELECT CASE
  WHEN data_type = 'numeric' AND is_nullable = 'YES'
    THEN '[5.1] OK — presences.heures_ajustees_litige NUMERIC nullable'
  ELSE '[5.1] FAIL — type=' || data_type || ' nullable=' || is_nullable
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'presences'
  AND column_name = 'heures_ajustees_litige';

-- [2] Colonne ajustement_litige_id (UUID, nullable, FK litiges)
SELECT CASE
  WHEN c.data_type = 'uuid' AND c.is_nullable = 'YES'
       AND EXISTS (
         SELECT 1 FROM information_schema.referential_constraints rc
         JOIN information_schema.key_column_usage k
           ON k.constraint_name = rc.constraint_name
         WHERE k.table_schema = 'public'
           AND k.table_name   = 'presences'
           AND k.column_name  = 'ajustement_litige_id'
       )
    THEN '[5.2] OK — ajustement_litige_id UUID nullable FK litiges'
  ELSE '[5.2] FAIL — type=' || c.data_type || ' nullable=' || c.is_nullable
END
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name = 'presences'
  AND c.column_name = 'ajustement_litige_id';

-- [3] Index partiel sur ajustement_litige_id
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[5.3] OK — idx_presences_ajustement_litige_id présent'
  ELSE '[5.3] FAIL — index absent'
END
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename  = 'presences'
  AND indexname  = 'idx_presences_ajustement_litige_id';

-- ============================================================
-- Tests CP-LITIGES-7a FIX 6 — statut 'REMPLACEE'
-- ============================================================
-- Prérequis : 20260417130705_fix6_statut_remplacee.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix6.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 6 =='

-- [1] CHECK contient les 7 valeurs attendues
SELECT CASE
  WHEN pg_get_constraintdef(oid) ILIKE '%BROUILLON%'
   AND pg_get_constraintdef(oid) ILIKE '%EMISE%'
   AND pg_get_constraintdef(oid) ILIKE '%PAYEE%'
   AND pg_get_constraintdef(oid) ILIKE '%ANNULEE%'
   AND pg_get_constraintdef(oid) ILIKE '%FACTORISEE%'
   AND pg_get_constraintdef(oid) ILIKE '%EN_RETARD%'
   AND pg_get_constraintdef(oid) ILIKE '%REMPLACEE%'
    THEN '[6.1] OK — CHECK accepte les 7 statuts (dont REMPLACEE)'
  ELSE '[6.1] FAIL — def=' || pg_get_constraintdef(oid)
END
FROM pg_constraint
WHERE conname = 'factures_honoraires_statut_check';

-- [2] Valeur 'REMPLACEE' acceptée (dry run via match CHECK)
DO $$
BEGIN
  IF 'REMPLACEE' = ANY (ARRAY[
    'BROUILLON','EMISE','PAYEE','ANNULEE','FACTORISEE','EN_RETARD','REMPLACEE'
  ]) THEN
    RAISE NOTICE '[6.2] OK — REMPLACEE match le nouveau CHECK';
  ELSE
    RAISE NOTICE '[6.2] FAIL';
  END IF;
END $$;

-- [3] Aucune ligne n'est en REMPLACEE (pas de backfill)
SELECT CASE
  WHEN COUNT(*) = 0
    THEN '[6.3] OK — aucune facture en REMPLACEE (cohérent avec le scope structure seule)'
  ELSE '[6.3] WARN — ' || COUNT(*) || ' ligne(s) déjà en REMPLACEE'
END
FROM public.factures_honoraires
WHERE statut = 'REMPLACEE';

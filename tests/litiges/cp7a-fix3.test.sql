-- ============================================================
-- Tests CP-LITIGES-7a FIX 3 — missions.type_contrat_applique
-- ============================================================
-- Prérequis : 20260417130702_fix3_missions_type_contrat.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix3.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 3 =='

-- [1] Enum type_contrat_applique_enum = {LIBERAL, SALARIE}
SELECT CASE
  WHEN COUNT(*) = 2
   AND bool_and(enumlabel IN ('LIBERAL','SALARIE'))
    THEN '[3.1] OK — enum type_contrat_applique_enum = 2 valeurs {LIBERAL, SALARIE}'
  ELSE '[3.1] FAIL — ' || COUNT(*) || ' valeurs : '
       || string_agg(enumlabel, ',' ORDER BY enumlabel)
END
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'type_contrat_applique_enum';

-- [2] Colonne missions.type_contrat_applique (USER-DEFINED, nullable)
SELECT CASE
  WHEN data_type = 'USER-DEFINED'
   AND udt_name = 'type_contrat_applique_enum'
   AND is_nullable = 'YES'
    THEN '[3.2] OK — missions.type_contrat_applique enum nullable'
  ELSE '[3.2] FAIL — type=' || data_type || ' udt=' || udt_name
       || ' nullable=' || is_nullable
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'missions'
  AND column_name = 'type_contrat_applique';

-- [3] Backfill sanity : toutes les lignes sont LIBERAL, SALARIE ou NULL
-- (CHECK implicite via enum) ; et le backfill n'a pas créé de valeur
-- aberrante. Si des missions assignées existent avec un type_paiement_
-- soignant non NULL, on doit voir au moins une ligne backfillée.
SELECT CASE
  WHEN (
    SELECT COUNT(*) FROM public.missions
     WHERE soignant_assigne_id IS NOT NULL
       AND type_paiement_soignant IN ('NOTE_HONORAIRES','BULLETIN_PAIE')
  ) = 0
    THEN '[3.3] SKIP — aucune mission assignée avec type_paiement_soignant renseigné'
  WHEN (
    SELECT COUNT(*) FROM public.missions
     WHERE soignant_assigne_id IS NOT NULL
       AND type_paiement_soignant IN ('NOTE_HONORAIRES','BULLETIN_PAIE')
       AND type_contrat_applique IS NOT NULL
  ) > 0
    THEN '[3.3] OK — backfill effectif sur missions assignées'
  ELSE '[3.3] FAIL — aucune mission backfillée alors que des candidates existent'
END;

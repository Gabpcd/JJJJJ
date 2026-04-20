-- ============================================================
-- Tests CP-LITIGES-1 — DDL extension système litiges
-- ============================================================
-- Prérequis : migration 20260417130000_cp_litiges_1_ddl.sql appliquée.
-- Usage :
--   psql "$DB_URL" -f tests/litiges/cp1-ddl.test.sql
--
-- Valide :
--   1. 5 enums créés avec bonnes valeurs
--   2. 8 colonnes sur litiges, 8 sur factures_honoraires, 2 sur missions
--   3. Table parametres_litiges + 13 lignes seed
--   4. 9 index créés + 1 unique partiel
--   5. Backfill type_legacy=TRUE sur litiges existants
--   6. RLS parametres_litiges (admin only en write)
--   7. Trigger immutabilité verrouille type_document + facture_precedente_id
--   8. montant_signe GENERATED fonctionne
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-1 DDL =='

-- ──────────────────────────────────────────────────────────────
-- TEST 1 : enums créés avec bon cardinal
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T1 : enums créés'

SELECT
  CASE WHEN COUNT(*) = 5 THEN '[1.1] OK — 5 catégories'
       ELSE '[1.1] FAIL — ' || COUNT(*) || ' valeurs (attendu 5)' END
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'categorie_litige';

SELECT
  CASE WHEN COUNT(*) = 12 THEN '[1.2] OK — 12 types litige'
       ELSE '[1.2] FAIL — ' || COUNT(*) || ' valeurs (attendu 12)' END
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'type_litige';

SELECT
  CASE WHEN COUNT(*) = 4 THEN '[1.3] OK — 4 statuts litige facture'
       ELSE '[1.3] FAIL — ' || COUNT(*) || ' valeurs (attendu 4)' END
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'statut_litige_facture';

SELECT
  CASE WHEN COUNT(*) = 2 THEN '[1.4] OK — 2 types document'
       ELSE '[1.4] FAIL — ' || COUNT(*) || ' valeurs (attendu 2)' END
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'type_document_facture';

SELECT
  CASE WHEN COUNT(*) = 3 THEN '[1.5] OK — 3 modes remboursement'
       ELSE '[1.5] FAIL — ' || COUNT(*) || ' valeurs (attendu 3)' END
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'mode_remboursement_avoir';

-- ──────────────────────────────────────────────────────────────
-- TEST 2 : colonnes litiges (8 nouvelles)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T2 : colonnes litiges'

SELECT
  CASE WHEN COUNT(*) = 8 THEN '[2] OK — 8 colonnes ajoutées sur litiges'
       ELSE '[2] FAIL — ' || COUNT(*) || ' colonnes trouvées (attendu 8) : ' ||
            string_agg(column_name, ', ') END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'litiges'
  AND column_name IN (
    'type_litige', 'categorie_litige', 'facture_id', 'est_informatif',
    'type_legacy', 'montant_tresorerie_bloquee', 'derniers_rappels_envoyes',
    'escalade_auto_le'
  );

-- Vérifier escalade_auto_motif aussi (9e colonne)
SELECT
  CASE WHEN COUNT(*) = 1 THEN '[2bis] OK — escalade_auto_motif présent'
       ELSE '[2bis] FAIL — escalade_auto_motif manquant' END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'litiges' AND column_name = 'escalade_auto_motif';

-- ──────────────────────────────────────────────────────────────
-- TEST 3 : colonnes factures_honoraires (8 nouvelles : 7 + montant_signe)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T3 : colonnes factures_honoraires'

SELECT
  CASE WHEN COUNT(*) = 8 THEN '[3] OK — 8 colonnes ajoutées sur factures_honoraires'
       ELSE '[3] FAIL — ' || COUNT(*) || ' colonnes : ' || string_agg(column_name, ', ') END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures_honoraires'
  AND column_name IN (
    'type_document', 'statut_litige', 'litige_id', 'facture_precedente_id',
    'mode_remboursement', 'date_remboursement', 'reference_remboursement', 'montant_signe'
  );

-- Vérifier montant_signe est bien GENERATED
SELECT
  CASE WHEN is_generated = 'ALWAYS' THEN '[3bis] OK — montant_signe est GENERATED'
       ELSE '[3bis] FAIL — montant_signe is_generated = ' || is_generated END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'factures_honoraires' AND column_name = 'montant_signe';

-- ──────────────────────────────────────────────────────────────
-- TEST 4 : colonnes missions (2 nouvelles)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T4 : colonnes missions'

SELECT
  CASE WHEN COUNT(*) = 2 THEN '[4] OK — regularisation_sociale_requise + commission_a_recalculer'
       ELSE '[4] FAIL — ' || COUNT(*) || ' colonnes' END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'missions'
  AND column_name IN ('regularisation_sociale_requise', 'commission_a_recalculer');

-- ──────────────────────────────────────────────────────────────
-- TEST 5 : table parametres_litiges + seed
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T5 : parametres_litiges'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[5.1] OK — table parametres_litiges existe'
       ELSE '[5.1] FAIL — table absente' END
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'parametres_litiges';

SELECT
  CASE WHEN COUNT(*) = 13 THEN '[5.2] OK — 13 lignes seed'
       ELSE '[5.2] FAIL — ' || COUNT(*) || ' lignes (attendu 13)' END
FROM public.parametres_litiges;

-- Vérifier quelques clés essentielles
SELECT
  CASE WHEN COUNT(*) = 4 THEN '[5.3] OK — 4 clés essentielles présentes'
       ELSE '[5.3] FAIL — ' || COUNT(*) || ' clés trouvées' END
FROM public.parametres_litiges
WHERE cle IN (
  'delai_contestation_pointage_h',
  'delai_escalade_liberal_h',
  'seuil_tresorerie_alerte_euros',
  'delai_stripe_refund_auto_j'
);

-- ──────────────────────────────────────────────────────────────
-- TEST 6 : index créés (10 au total)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T6 : index'

SELECT
  CASE WHEN COUNT(*) = 10 THEN '[6] OK — 10 index créés'
       ELSE '[6] FAIL — ' || COUNT(*) || ' index : ' || string_agg(indexname, ', ') END
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'idx_litiges_type_statut_ouverts',
    'idx_litiges_categorie_ouverts',
    'idx_litiges_facture_id',
    'idx_litiges_escalade_auto',
    'idx_fh_litige_id',
    'idx_fh_statut_litige',
    'idx_fh_facture_precedente',
    'idx_fh_type_document',
    'uq_litige_mission_type_ouvert',
    'parametres_litiges_pkey'
  );

-- ──────────────────────────────────────────────────────────────
-- TEST 7 : backfill type_legacy
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T7 : backfill'

SELECT
  CASE WHEN COUNT(*) FILTER (WHERE type_legacy = FALSE) = 0
       THEN '[7.1] OK — aucun litige existant sans type_legacy=TRUE'
       ELSE '[7.1] FAIL — ' || COUNT(*) FILTER (WHERE type_legacy = FALSE)
            || ' litiges avec type_legacy=FALSE' END
FROM public.litiges;

SELECT
  CASE WHEN COUNT(*) FILTER (WHERE type_litige = 'AUTRE') = COUNT(*)
       THEN '[7.2] OK — tous les litiges existants en type=AUTRE'
       ELSE '[7.2] FAIL — litiges avec type différent détectés' END
FROM public.litiges;

-- ──────────────────────────────────────────────────────────────
-- TEST 8 : RLS parametres_litiges
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T8 : RLS parametres_litiges'

SELECT
  CASE WHEN rowsecurity = TRUE THEN '[8.1] OK — RLS activé'
       ELSE '[8.1] FAIL — RLS désactivé' END
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'parametres_litiges';

SELECT
  CASE WHEN COUNT(*) = 4 THEN '[8.2] OK — 4 policies (select/insert/update/delete)'
       ELSE '[8.2] FAIL — ' || COUNT(*) || ' policies' END
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'parametres_litiges';

-- ──────────────────────────────────────────────────────────────
-- TEST 9 : montant_signe GENERATED fonctionne
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T9 : montant_signe GENERATED'
-- On utilise un scénario existant en lecture seule : toutes les factures
-- existantes sont des FACTURES (backfill DEFAULT='FACTURE'), donc
-- montant_signe doit strictement égaler montant_ht.

SELECT
  CASE WHEN COUNT(*) FILTER (WHERE montant_signe <> montant_ht) = 0
       THEN '[9] OK — montant_signe = montant_ht pour toutes les FACTURE existantes'
       ELSE '[9] FAIL — ' || COUNT(*) FILTER (WHERE montant_signe <> montant_ht)
            || ' lignes avec désynchronisation' END
FROM public.factures_honoraires
WHERE type_document = 'FACTURE';

-- ──────────────────────────────────────────────────────────────
-- TEST 10 : extension trigger immutabilité (metadata only)
-- ──────────────────────────────────────────────────────────────
-- NB : en contexte psql local, auth.uid() est NULL → le trigger bypass
-- automatiquement. Impossible de déclencher le RAISE EXCEPTION sans
-- simuler un JWT authenticated. On valide ici :
--   (a) le trigger trg_fh_immutability existe toujours sur la table
--   (b) la source de la fonction contient les 2 nouveaux verrous
-- Le vrai test comportemental se fera en TypeScript (vitest) avec
-- un contexte authenticated simulé, en CP-LITIGES-8.
\echo ''
\echo '-- T10 : extension trigger immutabilité'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[10.1] OK — trigger trg_fh_immutability toujours attaché'
       ELSE '[10.1] FAIL — trigger manquant ou dupliqué (' || COUNT(*) || ')' END
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'factures_honoraires'
  AND t.tgname = 'trg_fh_immutability'
  AND NOT t.tgisinternal;

SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%type_document verrouillé%'
       THEN '[10.2] OK — verrou type_document présent dans la fonction'
       ELSE '[10.2] FAIL — verrou type_document absent' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'fn_protect_facture_honoraire_immutability';

SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%facture_precedente_id verrouillé%'
       THEN '[10.3] OK — verrou facture_precedente_id présent dans la fonction'
       ELSE '[10.3] FAIL — verrou facture_precedente_id absent' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'fn_protect_facture_honoraire_immutability';

\echo ''
\echo '== FIN CP-LITIGES-1 =='

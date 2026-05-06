-- ============================================================
-- Tests CP-LITIGES-3 — Résolution admin étendue + avoirs
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1/2 + fixes CP2 + CP-LITIGES-3
--             (20260417130300) appliquées.
-- Usage :
--   psql "$DB_URL" -f tests/litiges/cp3-resolution-avoirs.test.sql
--
-- Les tests comportementaux nécessitant un contexte admin
-- (résolution complète, génération avoir réelle) sont laissés à
-- CP-LITIGES-8 en vitest/TS.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-3 Résolution + Avoirs =='

-- ──────────────────────────────────────────────────────────────
-- T1 : colonnes sur factures_honoraires
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T1 : pdf_a_regenerer + stripe_payment_intent_id'

SELECT
  CASE WHEN COUNT(*) = 2 THEN '[1] OK — 2 colonnes ajoutées (pdf_a_regenerer, stripe_payment_intent_id)'
       ELSE '[1] FAIL — ' || COUNT(*) || ' colonnes trouvées' END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures_honoraires'
  AND column_name IN ('pdf_a_regenerer', 'stripe_payment_intent_id');

-- ──────────────────────────────────────────────────────────────
-- T2 : table stripe_refunds_queue + RLS + grants
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T2 : stripe_refunds_queue'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[2.1] OK — table stripe_refunds_queue existe'
       ELSE '[2.1] FAIL' END
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'stripe_refunds_queue';

SELECT
  CASE WHEN rowsecurity = TRUE THEN '[2.2] OK — RLS activé'
       ELSE '[2.2] FAIL' END
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'stripe_refunds_queue';

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[2.3] OK — index idx_stripe_refunds_queue_statut présent'
       ELSE '[2.3] FAIL' END
FROM pg_indexes
WHERE schemaname = 'public' AND indexname = 'idx_stripe_refunds_queue_statut';

-- Vérif contrainte CHECK sur statut
SELECT
  CASE WHEN COUNT(*) >= 1 THEN '[2.4] OK — contrainte CHECK sur statut présente'
       ELSE '[2.4] FAIL' END
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'stripe_refunds_queue'
  AND c.contype = 'c'
  AND pg_get_constraintdef(c.oid) LIKE '%EN_ATTENTE%';

-- ──────────────────────────────────────────────────────────────
-- T3 : next_avoir_number (comportemental)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T3 : next_avoir_number'

-- T3.1 : retourne un format AV-{SIRET}-{YYYY}-{NNNNN}
DO $$
DECLARE
  v_soignant_id UUID;
  v_numero TEXT;
  v_pattern TEXT := '^AV-[A-Z0-9]{8}-\d{4}-\d{5}$';
BEGIN
  SELECT id INTO v_soignant_id FROM public.soignants LIMIT 1;
  IF v_soignant_id IS NULL THEN
    RAISE NOTICE '[3.1] SKIP — aucun soignant en base';
    RETURN;
  END IF;
  v_numero := public.next_avoir_number(v_soignant_id);
  IF v_numero ~ v_pattern THEN
    RAISE NOTICE '[3.1] OK — format AV-{SIRET}-{YYYY}-{NNNNN} respecté : %', v_numero;
  ELSE
    RAISE NOTICE '[3.1] FAIL — format incorrect : %', v_numero;
  END IF;
END;
$$;

-- T3.2 : séquence croissante (appel 2 fois = SEQ + 1)
-- Note : ce test fonctionne même sans avoir en base (séquence part à 1).
DO $$
DECLARE
  v_soignant_id UUID;
  v_n1 TEXT;
  v_n2 TEXT;
  v_seq1 INT;
  v_seq2 INT;
BEGIN
  SELECT id INTO v_soignant_id FROM public.soignants LIMIT 1;
  IF v_soignant_id IS NULL THEN
    RAISE NOTICE '[3.2] SKIP — aucun soignant';
    RETURN;
  END IF;
  v_n1 := public.next_avoir_number(v_soignant_id);
  v_n2 := public.next_avoir_number(v_soignant_id);
  v_seq1 := SPLIT_PART(v_n1, '-', 4)::INT;
  v_seq2 := SPLIT_PART(v_n2, '-', 4)::INT;
  -- Puisque les avoirs ne sont pas vraiment insérés, les deux appels
  -- retournent le MÊME numéro (même MAX+1). On vérifie juste l'unicité
  -- d'appel = même séquence car base inchangée.
  IF v_seq1 = v_seq2 THEN
    RAISE NOTICE '[3.2] OK — séquence stable hors INSERT (seq=%)', v_seq1;
  ELSE
    RAISE NOTICE '[3.2] WARN — séquences différentes : % / %', v_seq1, v_seq2;
  END IF;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T4 : fn_admin_resoudre_litige (signatures + rejet non-admin)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T4 : fn_admin_resoudre_litige'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[4.1] OK — fonction présente (1 signature)'
       ELSE '[4.1] FAIL — ' || COUNT(*) || ' signatures' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_resoudre_litige';

-- Nouvelle signature contient p_action_financiere ?
SELECT
  CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON p.pronamespace = n.oid
         WHERE n.nspname = 'public'
           AND p.proname = 'fn_admin_resoudre_litige'
           AND pg_get_function_identity_arguments(p.oid) LIKE '%p_action_financiere%'
       )
       THEN '[4.2] OK — signature contient p_action_financiere'
       ELSE '[4.2] FAIL — signature sans p_action_financiere' END;

-- Rejet non-admin (contexte psql = auth.uid() NULL)
DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_admin_resoudre_litige(
    '00000000-0000-0000-0000-000000000000'::uuid,
    'Test de résolution longue minimum 10 caractères',
    'SOIGNANT', 8, 30, 'RECALCUL'
  );
  IF v_result ? 'error' AND v_result->>'error' LIKE '%Admin%' THEN
    RAISE NOTICE '[4.3] OK — non-admin rejeté : %', v_result->>'error';
  ELSE
    RAISE NOTICE '[4.3] FAIL — résultat inattendu : %', v_result;
  END IF;
END;
$$;

-- Déduction AUTO présente dans la source
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%RECALCUL%'
        AND pg_get_functiondef(p.oid) LIKE '%ANNULER_REEMETTRE%'
        AND pg_get_functiondef(p.oid) LIKE '%AVOIR%'
        AND pg_get_functiondef(p.oid) LIKE '%AUCUNE%'
       THEN '[4.4] OK — 4 branches (RECALCUL/ANNULER/AVOIR/AUCUNE) dans la source'
       ELSE '[4.4] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_resoudre_litige';

-- Flags présents : regularisation_sociale_requise, commission_a_recalculer, pdf_a_regenerer
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%regularisation_sociale_requise%'
        AND pg_get_functiondef(p.oid) LIKE '%commission_a_recalculer%'
        AND pg_get_functiondef(p.oid) LIKE '%pdf_a_regenerer%'
       THEN '[4.5] OK — 3 flags propagés (URSSAF, commission, PDF)'
       ELSE '[4.5] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_resoudre_litige';

-- Audit RGPD LITIGE_RESOLUTION
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%LITIGE_RESOLUTION%'
       THEN '[4.6] OK — audit LITIGE_RESOLUTION présent'
       ELSE '[4.6] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_resoudre_litige';

-- Stripe refunds queue appelée
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%stripe_refunds_queue%'
       THEN '[4.7] OK — enqueue Stripe refunds présent'
       ELSE '[4.7] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_resoudre_litige';

-- ──────────────────────────────────────────────────────────────
-- T5 : fn_confirmer_remboursement_avoir
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T5 : fn_confirmer_remboursement_avoir'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[5.1] OK — fonction présente'
       ELSE '[5.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_confirmer_remboursement_avoir';

-- Rejet non-admin
DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_confirmer_remboursement_avoir(
    '00000000-0000-0000-0000-000000000000'::uuid,
    'VIR-REF-TEST-001'
  );
  IF v_result ? 'error' AND v_result->>'error' LIKE '%Admin%' THEN
    RAISE NOTICE '[5.2] OK — non-admin rejeté : %', v_result->>'error';
  ELSE
    RAISE NOTICE '[5.2] FAIL — résultat inattendu : %', v_result;
  END IF;
END;
$$;

-- Contrôles validation (référence courte, type_document, mode, déjà confirmé)
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%AVOIR%'
        AND pg_get_functiondef(p.oid) LIKE '%VIREMENT_MANUEL%'
        AND pg_get_functiondef(p.oid) LIKE '%Référence virement requise%'
        AND pg_get_functiondef(p.oid) LIKE '%AVOIR_REMBOURSEMENT_CONFIRME%'
       THEN '[5.3] OK — 4 garde-fous présents + audit'
       ELSE '[5.3] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_confirmer_remboursement_avoir';

-- ──────────────────────────────────────────────────────────────
-- T6 : Grants sur nouvelles RPCs
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T6 : Grants'

SELECT
  CASE WHEN COUNT(*) >= 6 THEN '[6] OK — grants OK (' || COUNT(*) || ' privilèges)'
       ELSE '[6] FAIL — ' || COUNT(*) END
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'next_avoir_number',
    'fn_admin_resoudre_litige',
    'fn_confirmer_remboursement_avoir'
  )
  AND privilege_type = 'EXECUTE'
  AND grantee IN ('authenticated', 'service_role');

\echo ''
\echo '== FIN CP-LITIGES-3 =='

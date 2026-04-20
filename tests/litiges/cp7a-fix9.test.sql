-- ============================================================
-- Tests CP-LITIGES-7a FIX 9 — Avoir commission étab
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 9 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix9.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 9 =='

-- [1] Colonne type_document sur factures
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[9.1] OK — factures.type_document présent'
  ELSE '[9.1] FAIL — ' || COUNT(*) || ' match'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures'
  AND column_name = 'type_document';

-- [2] Colonne facture_precedente_id sur factures
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[9.2] OK — factures.facture_precedente_id présent'
  ELSE '[9.2] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures'
  AND column_name = 'facture_precedente_id';

-- [3] Colonne montant_signe (GENERATED) sur factures
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[9.3] OK — factures.montant_signe présent'
  ELSE '[9.3] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures'
  AND column_name = 'montant_signe';

-- [4] CHECK constraint factures_type_document_check
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[9.4] OK — factures_type_document_check présente'
  ELSE '[9.4] FAIL — ' || COUNT(*) || ' match'
END
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND table_name = 'factures'
  AND constraint_name = 'factures_type_document_check';

-- [5] Fonction next_avoir_commission_number(UUID) existe
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[9.5] OK — next_avoir_commission_number(UUID) présente'
  ELSE '[9.5] FAIL'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'next_avoir_commission_number';

-- [6] Fonction next_facture_complementaire_number(UUID) existe
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[9.6] OK — next_facture_complementaire_number(UUID) présente'
  ELSE '[9.6] FAIL'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'next_facture_complementaire_number';

-- [7] fn_recalculer retourne les clés FIX 9
DO $$
DECLARE v_result JSONB;
BEGIN
  SELECT public.fn_recalculer_commissions_post_litige() INTO v_result;
  IF v_result ? 'processed_unbilled'
     AND v_result ? 'avoirs_commission_emis'
     AND v_result ? 'factures_complementaires_emises'
     AND v_result ? 'deferred_to_fix9_billed'
  THEN
    RAISE NOTICE '[9.7] OK — JSONB contient les 4 clés FIX 8+9 : %', v_result;
  ELSE
    RAISE NOTICE '[9.7] FAIL — clés manquantes : %', v_result;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[9.7] FAIL — exception : %', SQLERRM;
END $$;

-- [8] Comportemental : mission déjà facturée, delta > 0 → AVOIR créé
DO $$
DECLARE
  v_mission_id UUID;
  v_etab_id UUID;
  v_facture_id UUID;
  v_old_ht NUMERIC(12,2);
  v_flag_after BOOLEAN;
  v_avoir_count INT;
BEGIN
  SELECT m.id, m.etablissement_id, m.facture_id, m.montant_commission_ht
    INTO v_mission_id, v_etab_id, v_facture_id, v_old_ht
    FROM public.missions m
   WHERE m.facture_id IS NOT NULL
     AND COALESCE(m.commission_facturee, FALSE) = TRUE
     AND m.commission_a_recalculer = FALSE
     AND m.montant_commission_ht > 0
   LIMIT 1;

  IF v_mission_id IS NULL THEN
    RAISE NOTICE '[9.8] SKIP — aucune mission facturée éligible';
    RETURN;
  END IF;

  UPDATE public.missions
     SET commission_a_recalculer = TRUE,
         montant_commission_ht = v_old_ht + 50
   WHERE id = v_mission_id;

  SELECT COUNT(*) INTO v_avoir_count
    FROM public.factures
   WHERE type_document = 'AVOIR' AND facture_precedente_id = v_facture_id;

  PERFORM public.fn_recalculer_commissions_post_litige();

  SELECT commission_a_recalculer INTO v_flag_after
    FROM public.missions WHERE id = v_mission_id;

  DECLARE v_avoir_count_after INT;
  BEGIN
    SELECT COUNT(*) INTO v_avoir_count_after
      FROM public.factures
     WHERE type_document = 'AVOIR' AND facture_precedente_id = v_facture_id;

    IF v_flag_after = FALSE AND v_avoir_count_after > v_avoir_count THEN
      RAISE NOTICE '[9.8] OK — AVOIR commission créé, flag reset (mission %)', v_mission_id;
    ELSE
      RAISE NOTICE '[9.8] FAIL — flag=%, avoirs avant=%, après=%',
        v_flag_after, v_avoir_count, v_avoir_count_after;
    END IF;
  END;

  -- Nettoyage
  DELETE FROM public.factures
   WHERE type_document = 'AVOIR' AND facture_precedente_id = v_facture_id
     AND numero_facture LIKE 'AVC-%';
  UPDATE public.missions
     SET montant_commission_ht = v_old_ht,
         commission_a_recalculer = FALSE
   WHERE id = v_mission_id;
END $$;

-- [9] Comportemental : delta = 0 → pas de document, flag reset
DO $$
DECLARE
  v_mission_id UUID;
  v_facture_id UUID;
  v_doc_count_before INT;
  v_doc_count_after INT;
  v_flag_after BOOLEAN;
BEGIN
  SELECT m.id, m.facture_id
    INTO v_mission_id, v_facture_id
    FROM public.missions m
   WHERE m.facture_id IS NOT NULL
     AND COALESCE(m.commission_facturee, FALSE) = TRUE
     AND m.commission_a_recalculer = FALSE
   LIMIT 1;

  IF v_mission_id IS NULL THEN
    RAISE NOTICE '[9.9] SKIP — aucune mission facturée éligible';
    RETURN;
  END IF;

  SELECT COUNT(*) INTO v_doc_count_before
    FROM public.factures
   WHERE facture_precedente_id = v_facture_id;

  UPDATE public.missions SET commission_a_recalculer = TRUE
   WHERE id = v_mission_id;

  PERFORM public.fn_recalculer_commissions_post_litige();

  SELECT commission_a_recalculer INTO v_flag_after
    FROM public.missions WHERE id = v_mission_id;

  SELECT COUNT(*) INTO v_doc_count_after
    FROM public.factures
   WHERE facture_precedente_id = v_facture_id;

  IF v_flag_after = FALSE AND v_doc_count_after = v_doc_count_before THEN
    RAISE NOTICE '[9.9] OK — delta=0, pas de document, flag reset (mission %)', v_mission_id;
  ELSE
    RAISE NOTICE '[9.9] FAIL — flag=%, docs avant=%, après=%',
      v_flag_after, v_doc_count_before, v_doc_count_after;
  END IF;

  -- Nettoyage
  UPDATE public.missions SET commission_a_recalculer = FALSE
   WHERE id = v_mission_id;
END $$;

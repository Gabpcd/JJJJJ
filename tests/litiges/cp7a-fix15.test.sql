-- ============================================================
-- Tests CP-LITIGES-7a FIX 15 — submit-to-chorus support AVOIR
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 15 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix15.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 15 =='

-- [1] Colonne type_document sur chorus_submissions
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[15.1] OK — chorus_submissions.type_document présent'
  ELSE '[15.1] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'chorus_submissions'
  AND column_name = 'type_document';

-- [2] CHECK constraint sur type_document
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[15.2] OK — chorus_submissions_type_document_check présente'
  ELSE '[15.2] FAIL — ' || COUNT(*) || ' match'
END
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND table_name = 'chorus_submissions'
  AND constraint_name = 'chorus_submissions_type_document_check';

-- [3] Colonne avoir_reference_invoice sur chorus_submissions
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[15.3] OK — chorus_submissions.avoir_reference_invoice présent'
  ELSE '[15.3] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'chorus_submissions'
  AND column_name = 'avoir_reference_invoice';

-- [4] Index partiel idx_chorus_sub_avoir
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[15.4] OK — index idx_chorus_sub_avoir présent'
  ELSE '[15.4] FAIL'
END
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname = 'idx_chorus_sub_avoir';

-- [5] Défaut type_document = 'FACTURE'
SELECT CASE
  WHEN column_default = '''FACTURE''::text'
    THEN '[15.5] OK — DEFAULT FACTURE'
  ELSE '[15.5] FAIL — default=' || COALESCE(column_default, 'NULL')
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'chorus_submissions'
  AND column_name = 'type_document';

-- [6] CHECK accepte 'AVOIR'
DO $$
DECLARE
  v_fh_id UUID;
  v_probe UUID;
BEGIN
  SELECT id INTO v_fh_id
    FROM public.factures_honoraires LIMIT 1;
  IF v_fh_id IS NULL THEN
    RAISE NOTICE '[15.6] SKIP — pas de facture_honoraire';
    RETURN;
  END IF;

  INSERT INTO public.chorus_submissions (
    invoice_id, submission_type, type_document, status
  ) VALUES (
    v_fh_id, 'SAISIE_API', 'AVOIR', 'pending_credentials'
  ) RETURNING id INTO v_probe;

  RAISE NOTICE '[15.6] OK — CHECK accepte type_document=AVOIR';
  DELETE FROM public.chorus_submissions WHERE id = v_probe;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[15.6] FAIL — %', SQLERRM;
END $$;

-- [7] chorus_avoir_reference_invoice existe sur factures_honoraires (CP6)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[15.7] OK — factures_honoraires.chorus_avoir_reference_invoice présent'
  ELSE '[15.7] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures_honoraires'
  AND column_name = 'chorus_avoir_reference_invoice';

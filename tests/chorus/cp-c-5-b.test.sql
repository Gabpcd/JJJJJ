-- ============================================================
-- Tests CP-C-5 B — Chorus Pro submit-to-chorus (E15 Phase 1)
-- ============================================================
-- Prérequis : edge functions chorus-pro-deposit v191+, submit-to-chorus v50+,
--             generate-invoice v52+, _shared/piste-client.ts, _shared/facturx-builder.ts
-- Usage     : psql "$DB_URL" -f tests/chorus/cp-c-5-b.test.sql
--
-- Scope limité : tests DB uniquement (RLS, INSERT, idempotence, schéma).
-- Tests live PISTE API attendent débloquage 403 par support Chorus Pro.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-C-5 B — Chorus Pro DB layer =='

-- ------------------------------------------------------------
-- [1] Structure chorus_submissions : colonnes attendues présentes
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) = 12 THEN '[1.1] OK — 12 colonnes attendues'
  ELSE '[1.1] FAIL — attendu 12, trouvé ' || COUNT(*)
END AS t1_structure
FROM information_schema.columns
WHERE table_schema='public' AND table_name='chorus_submissions'
AND column_name IN (
  'id','invoice_id','piste_request_id','payload_xml','response_raw',
  'submission_type','status','error_code','error_message',
  'submitted_at','last_checked_at','created_at','type_document','avoir_reference_invoice'
);

-- ------------------------------------------------------------
-- [2] RLS chorus_submissions : 3 policies (INSERT service / SELECT own / UPDATE admin)
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) >= 3 THEN '[2.1] OK — ' || COUNT(*) || ' policies RLS sur chorus_submissions'
  ELSE '[2.1] FAIL — policies manquantes'
END AS t2_rls_subs
FROM pg_policies
WHERE schemaname='public' AND tablename='chorus_submissions';

-- ------------------------------------------------------------
-- [3] RLS chorus_pro_config : 4 policies (SELECT/INSERT/UPDATE/DELETE)
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) >= 4 THEN '[3.1] OK — ' || COUNT(*) || ' policies RLS sur chorus_pro_config'
  ELSE '[3.1] FAIL'
END AS t3_rls_config
FROM pg_policies
WHERE schemaname='public' AND tablename='chorus_pro_config';

-- [4] Idempotence : statut 'submitted' = terminal (submit-to-chorus SKIP)
BEGIN;
SET session_replication_role = 'replica';

INSERT INTO public.chorus_submissions (id, invoice_id, submission_type, type_document, status, submitted_at)
VALUES ('c5b00001-0000-0000-0000-000000000004', gen_random_uuid(), 'DEPOT_PDF_API', 'FACTURE', 'submitted', NOW());

SELECT CASE
  WHEN (SELECT status FROM public.chorus_submissions WHERE id='c5b00001-0000-0000-0000-000000000004') = 'submitted'
  THEN '[4.1] OK — fixture submitted insérée (submit-to-chorus SKIP en TypeScript)'
  ELSE '[4.1] FAIL'
END;

SET session_replication_role = 'origin';
ROLLBACK;

-- [5] Mode AVOIR : avoir_reference_invoice propagé
BEGIN;
SET session_replication_role = 'replica';

INSERT INTO public.chorus_submissions (id, invoice_id, submission_type, type_document, avoir_reference_invoice, status)
VALUES ('c5b00001-0000-0000-0000-000000000005', gen_random_uuid(), 'DEPOT_PDF_API', 'AVOIR', 'F-TEST-2026-001', 'pending');

SELECT CASE
  WHEN (SELECT avoir_reference_invoice FROM public.chorus_submissions WHERE id='c5b00001-0000-0000-0000-000000000005') = 'F-TEST-2026-001'
  THEN '[5.1] OK — avoir_reference_invoice propagé'
  ELSE '[5.1] FAIL'
END;

SET session_replication_role = 'origin';
ROLLBACK;

-- [6] Mode FACTURE standard : status='pending' accepté
BEGIN;
SET session_replication_role = 'replica';

INSERT INTO public.chorus_submissions (id, invoice_id, submission_type, type_document, status)
VALUES ('c5b00001-0000-0000-0000-000000000006', gen_random_uuid(), 'DEPOT_PDF_API', 'FACTURE', 'pending');

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM public.chorus_submissions WHERE id='c5b00001-0000-0000-0000-000000000006' AND status='pending')
  THEN '[6.1] OK — chorus_submissions accepte status=pending'
  ELSE '[6.1] FAIL'
END;

SET session_replication_role = 'origin';
ROLLBACK;

-- ------------------------------------------------------------
-- [7] enum type_document_facture : FACTURE + AVOIR présents
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) = 2 THEN '[7.1] OK — enum type_document_facture (FACTURE + AVOIR)'
  ELSE '[7.1] FAIL'
END
FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid
WHERE t.typname='type_document_facture' AND e.enumlabel IN ('FACTURE','AVOIR');

\echo ''
\echo '== Fin tests CP-C-5 B =='

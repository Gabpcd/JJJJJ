-- ============================================================
-- Tests CP-LITIGES-7a FIX 16 — Attachment PDF dans AVOIR_EMIS
-- ============================================================
-- Prérequis : edge function send-email déployée avec FIX 16.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix16.test.sql
-- ============================================================
-- FIX 16 est une modification de l'edge function send-email
-- (TypeScript), pas de migration SQL. Les tests ci-dessous
-- valident les pré-requis structurels nécessaires.
-- ============================================================
-- Test end-to-end : envoyer un AVOIR_EMIS via curl :
--
--   curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
--     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
--     -H "Content-Type: application/json" \
--     -d '{
--       "type": "AVOIR_EMIS",
--       "destinataire_id": "<soignant_uuid>",
--       "data": {
--         "avoir_id": "<avoir_uuid>",
--         "numero_avoir": "AV-TEST-001",
--         "numero_facture_origine": "FH-TEST-001",
--         "montant_avoir": "150.00",
--         "mode_remboursement_texte": "Virement sous 7 jours ouvrés"
--       }
--     }'
--
-- Vérifier dans la boîte mail que le PDF est attaché.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 16 =='

-- [1] Colonne pdf_s3_key sur factures_honoraires (nécessaire pour le download)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[16.1] OK — factures_honoraires.pdf_s3_key présent'
  ELSE '[16.1] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures_honoraires'
  AND column_name = 'pdf_s3_key';

-- [2] Bucket jolene-documents existe
SELECT CASE
  WHEN COUNT(*) >= 1
    THEN '[16.2] OK — bucket jolene-documents présent'
  ELSE '[16.2] FAIL — bucket absent'
END
FROM storage.buckets
WHERE id = 'jolene-documents';

-- [3] Table emails_envoyes existe (logging)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[16.3] OK — table emails_envoyes présente'
  ELSE '[16.3] FAIL'
END
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'emails_envoyes';

-- [4] Un avoir type_document='AVOIR' avec pdf_s3_key renseigné (si données exist)
DO $$
DECLARE v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM public.factures_honoraires
   WHERE type_document = 'AVOIR'
     AND pdf_s3_key IS NOT NULL;

  IF v_count > 0 THEN
    RAISE NOTICE '[16.4] OK — % avoirs avec PDF prêt (attachment possible)', v_count;
  ELSE
    RAISE NOTICE '[16.4] SKIP — aucun avoir avec pdf_s3_key en base (normal en dev)';
  END IF;
END $$;

\echo ''
\echo '== FIX 16 tests structurels terminés =='
\echo 'Test e2e attachment : voir commande curl dans l en-tete du fichier'

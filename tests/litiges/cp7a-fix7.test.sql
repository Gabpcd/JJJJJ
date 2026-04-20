-- ============================================================
-- Tests CP-LITIGES-7a FIX 7 — Tampons ANNULEE / REMPLACEE PDF
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 6 appliquées + edge function
--             generate-invoice/index.ts déployée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix7.test.sql
-- ============================================================
-- Note : le rendu visuel des tampons ne peut pas être testé côté SQL.
-- Les assertions ci-dessous valident uniquement les pré-requis structurels.
-- Cf. docs/tests-annulation/README.md pour le smoke-test visuel manuel.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 7 =='

-- [1] statut 'REMPLACEE' accepté par le CHECK constraint
DO $$
DECLARE
  v_soignant_id UUID;
  v_etab_id UUID;
  v_probe UUID;
BEGIN
  SELECT id INTO v_soignant_id FROM public.soignants LIMIT 1;
  SELECT id INTO v_etab_id FROM public.etablissements LIMIT 1;
  IF v_soignant_id IS NULL OR v_etab_id IS NULL THEN
    RAISE NOTICE '[7.1] SKIP — pas de soignant/etab';
    RETURN;
  END IF;

  INSERT INTO public.factures_honoraires (
    soignant_id, etablissement_id, numero_facture,
    montant_ht, montant_tva, montant_ttc, statut
  ) VALUES (
    v_soignant_id, v_etab_id,
    'FH-TEST-FIX7-' || substring(gen_random_uuid()::text, 1, 8),
    100, 20, 120, 'REMPLACEE'
  ) RETURNING id INTO v_probe;

  RAISE NOTICE '[7.1] OK — statut REMPLACEE accepté par CHECK';

  DELETE FROM public.factures_honoraires WHERE id = v_probe;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[7.1] FAIL — %', SQLERRM;
END $$;

-- [2] Colonne facture_precedente_id sur factures_honoraires (reverse lookup)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[7.2] OK — factures_honoraires.facture_precedente_id présent'
  ELSE '[7.2] FAIL'
END
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'factures_honoraires'
  AND column_name = 'facture_precedente_id';

-- [3] Index idx_fh_facture_precedente (perf reverse lookup REMPLACEE)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[7.3] OK — index idx_fh_facture_precedente présent'
  ELSE '[7.3] FAIL'
END
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname = 'idx_fh_facture_precedente';

-- [4] Reverse lookup successeur fonctionnel (si données présentes)
DO $$
DECLARE
  v_found INT;
BEGIN
  SELECT COUNT(*) INTO v_found
    FROM public.factures_honoraires f
    JOIN public.factures_honoraires s ON s.facture_precedente_id = f.id
   WHERE f.statut = 'REMPLACEE';

  IF v_found > 0 THEN
    RAISE NOTICE '[7.4] OK — % factures REMPLACEE avec successeur chaîné', v_found;
  ELSE
    RAISE NOTICE '[7.4] SKIP — aucune facture REMPLACEE chaînée en base (normal en dev)';
  END IF;
END $$;

\echo ''
\echo '== FIX 7 tests structurels terminés =='
\echo 'Rendu visuel : suivre docs/tests-annulation/README.md'

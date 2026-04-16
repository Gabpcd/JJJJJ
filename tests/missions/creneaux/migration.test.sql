-- ============================================================
-- migration.test.sql
-- Post-migration verification tests for CP3
-- Run AFTER the migration has been applied
-- ============================================================

-- ── Test 1: 265 créneaux created (268 - 3 skipped) ──
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM mission_creneaux;
  IF v_count != 265 THEN RAISE EXCEPTION 'TEST 1 FAIL — expected 265 créneaux, got %', v_count; END IF;
  RAISE NOTICE 'TEST 1 PASS — 265 créneaux created';
END $$;

-- ── Test 2: All migrated missions have exactly 1 créneau ──
DO $$
DECLARE v_multi integer;
BEGIN
  SELECT COUNT(*) INTO v_multi FROM (
    SELECT mission_id, COUNT(*) as cnt FROM mission_creneaux GROUP BY mission_id HAVING COUNT(*) > 1
  ) sub;
  IF v_multi != 0 THEN RAISE EXCEPTION 'TEST 2 FAIL — % missions have >1 créneau', v_multi; END IF;
  RAISE NOTICE 'TEST 2 PASS — all migrated missions have exactly 1 créneau';
END $$;

-- ── Test 3: debut_le/fin_le match créneau for all migrated missions ──
DO $$
DECLARE v_mismatch integer;
BEGIN
  SELECT COUNT(*) INTO v_mismatch
  FROM missions m
  JOIN mission_creneaux mc ON mc.mission_id = m.id
  WHERE m.debut_le != mc.debut OR m.fin_le != mc.fin;
  IF v_mismatch != 0 THEN RAISE EXCEPTION 'TEST 3 FAIL — % debut/fin mismatches', v_mismatch; END IF;
  RAISE NOTICE 'TEST 3 PASS — debut_le/fin_le coherent with créneaux';
END $$;

-- ── Test 4: nb_creneaux = 1 for all migrated missions ──
DO $$
DECLARE v_wrong integer;
BEGIN
  SELECT COUNT(*) INTO v_wrong FROM missions
  WHERE id IN (SELECT mission_id FROM mission_creneaux)
    AND nb_creneaux != 1;
  IF v_wrong != 0 THEN RAISE EXCEPTION 'TEST 4 FAIL — % missions with nb_creneaux != 1', v_wrong; END IF;
  RAISE NOTICE 'TEST 4 PASS — nb_creneaux = 1 for all migrated missions';
END $$;

-- ── Test 5: 3 skipped missions have nb_creneaux = 0 ──
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count FROM missions
  WHERE id IN ('ac4754fc-f0f9-421b-b871-49b3e3781275', 'c9c30b78-66a6-4aac-bbec-ecb64fff58d9', 'e49e0b77-fa70-4a13-b71b-730209d72465')
    AND nb_creneaux = 0;
  IF v_count != 3 THEN RAISE EXCEPTION 'TEST 5 FAIL — expected 3 skipped with nb=0, got %', v_count; END IF;
  RAISE NOTICE 'TEST 5 PASS — 3 skipped missions have nb_creneaux = 0';
END $$;

-- ── Test 6: duree_heures unchanged from pre-migration ──
DO $$
DECLARE v_mismatch integer;
BEGIN
  SELECT COUNT(*) INTO v_mismatch
  FROM missions m JOIN missions_snapshot_pre_cp3 s ON m.id = s.id
  WHERE m.duree_heures IS DISTINCT FROM s.duree_heures;
  IF v_mismatch != 0 THEN RAISE EXCEPTION 'TEST 6 FAIL — % duree_heures changed', v_mismatch; END IF;
  RAISE NOTICE 'TEST 6 PASS — duree_heures identical to pre-migration (0 changes)';
END $$;

-- ── Test 7: SERIE_DEMO_001 → 1 mission_series row, 8 missions linked ──
DO $$
DECLARE
  v_series_count integer;
  v_linked integer;
BEGIN
  SELECT COUNT(*) INTO v_series_count FROM mission_series;
  IF v_series_count != 1 THEN RAISE EXCEPTION 'TEST 7a FAIL — expected 1 series, got %', v_series_count; END IF;

  SELECT COUNT(*) INTO v_linked FROM missions WHERE serie_id IS NOT NULL;
  IF v_linked != 8 THEN RAISE EXCEPTION 'TEST 7b FAIL — expected 8 linked, got %', v_linked; END IF;

  RAISE NOTICE 'TEST 7 PASS — 1 série created, 8 missions linked';
END $$;

-- ── Test 8: No description still contains [SERIE_ID:...] ──
DO $$
DECLARE v_remaining integer;
BEGIN
  SELECT COUNT(*) INTO v_remaining FROM missions WHERE description LIKE '%[SERIE_ID:%';
  IF v_remaining != 0 THEN RAISE EXCEPTION 'TEST 8 FAIL — % descriptions still contain tag', v_remaining; END IF;
  RAISE NOTICE 'TEST 8 PASS — all [SERIE_ID:...] tags cleaned from descriptions';
END $$;

-- ── Test 9: serie_id FK integrity ──
DO $$
DECLARE v_orphan integer;
BEGIN
  SELECT COUNT(*) INTO v_orphan FROM missions
  WHERE serie_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM mission_series WHERE id = missions.serie_id);
  IF v_orphan != 0 THEN RAISE EXCEPTION 'TEST 9 FAIL — % orphan serie_id references', v_orphan; END IF;
  RAISE NOTICE 'TEST 9 PASS — all serie_id references valid';
END $$;

-- ── Test 10: Financial non-regression — 5 random TERMINEE missions ──
DO $$
DECLARE
  v_mismatch integer;
BEGIN
  SELECT COUNT(*) INTO v_mismatch
  FROM missions m
  JOIN missions_snapshot_pre_cp3 s ON m.id = s.id
  WHERE m.statut = 'TERMINEE'
    AND (m.total_brut IS DISTINCT FROM s.total_brut
      OR m.net_a_payer IS DISTINCT FROM s.net_a_payer
      OR m.montant_commission_ht IS DISTINCT FROM s.montant_commission_ht);
  IF v_mismatch != 0 THEN RAISE EXCEPTION 'TEST 10 FAIL — % TERMINEE missions with changed financials!', v_mismatch; END IF;
  RAISE NOTICE 'TEST 10 PASS — all TERMINEE missions have identical financials';
END $$;

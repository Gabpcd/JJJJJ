-- ============================================================
-- constraints.test.sql
-- Tests for mission_creneaux + mission_series constraints
-- Run via: psql or Supabase MCP execute_sql
-- Each test is a DO block that raises NOTICE on success
-- ============================================================

-- Setup: create a test mission for all constraint tests
DO $$
DECLARE
  v_etab_id uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;
  IF v_etab_id IS NULL THEN
    RAISE EXCEPTION 'No etablissement found for test';
  END IF;

  INSERT INTO missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, statut)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    v_etab_id,
    'TEST_CRENEAUX_CONSTRAINTS',
    'IDE'::type_profession,
    '2026-05-01 07:00:00+02',
    '2026-05-01 19:00:00+02',
    25.00,
    'OUVERTE'
  );
  RAISE NOTICE 'SETUP OK — test mission created';
END $$;

-- ── Test 1: fin > debut (should pass) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 07:00:00+02', '2026-05-01 12:00:00+02', 1);
  RAISE NOTICE 'TEST 1 PASS — valid créneau inserted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid AND ordre = 1;
END $$;

-- ── Test 2: fin <= debut (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 12:00:00+02', '2026-05-01 07:00:00+02', 1);
  RAISE EXCEPTION 'TEST 2 FAIL — should have been rejected';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'TEST 2 PASS — fin < debut rejected (check_violation)';
END $$;

-- ── Test 3: créneau > 24h (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 07:00:00+02', '2026-05-02 08:00:00+02', 1);
  RAISE EXCEPTION 'TEST 3 FAIL — should have been rejected';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'TEST 3 PASS — >24h créneau rejected';
END $$;

-- ── Test 4: créneau exactly 24h (should pass) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 07:00:00+02', '2026-05-02 07:00:00+02', 1);
  RAISE NOTICE 'TEST 4 PASS — exactly 24h créneau accepted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid AND ordre = 1;
END $$;

-- ── Test 5: duplicate ordre (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 07:00:00+02', '2026-05-01 12:00:00+02', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 14:00:00+02', '2026-05-01 19:00:00+02', 1);
  RAISE EXCEPTION 'TEST 5 FAIL — should have been rejected';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'TEST 5 PASS — duplicate ordre rejected';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 6: nb_creneaux CHECK on missions (max 6) ──
DO $$
DECLARE v_etab_id uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;
  -- nb_creneaux = 7 should fail
  BEGIN
    INSERT INTO missions (etablissement_id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, statut, nb_creneaux)
    VALUES (v_etab_id, 'TEST_NB7', 'IDE'::type_profession, '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25, 'OUVERTE', 7);
    RAISE EXCEPTION 'TEST 6a FAIL — nb_creneaux=7 should have been rejected';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'TEST 6a PASS — nb_creneaux=7 rejected by CHECK';
  END;
  -- nb_creneaux = 6 should pass
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, statut, nb_creneaux)
  VALUES ('bbbbbbbb-0000-0000-0000-000000000001'::uuid, v_etab_id, 'TEST_NB6', 'IDE'::type_profession, '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25, 'OUVERTE', 6);
  RAISE NOTICE 'TEST 6b PASS — nb_creneaux=6 accepted';
  DELETE FROM missions WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001'::uuid;
  -- nb_creneaux = -1 should fail
  BEGIN
    INSERT INTO missions (etablissement_id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, statut, nb_creneaux)
    VALUES (v_etab_id, 'TEST_NEG', 'IDE'::type_profession, '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25, 'OUVERTE', -1);
    RAISE EXCEPTION 'TEST 6c FAIL — nb_creneaux=-1 should have been rejected';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'TEST 6c PASS — nb_creneaux=-1 rejected by CHECK';
  END;
END $$;

-- ── Test 7: overlapping créneaux in same mission (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 07:00:00+02', '2026-05-01 12:00:00+02', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 11:00:00+02', '2026-05-01 15:00:00+02', 2);
  RAISE EXCEPTION 'TEST 7 FAIL — overlapping créneau should have been rejected';
EXCEPTION WHEN exclusion_violation THEN
  RAISE NOTICE 'TEST 7 PASS — overlapping créneau rejected';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 8: non-overlapping créneaux (should pass) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 07:00:00+02', '2026-05-01 12:00:00+02', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 14:00:00+02', '2026-05-01 19:00:00+02', 2);
  RAISE NOTICE 'TEST 8 PASS — two non-overlapping créneaux accepted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 9: type_pause must be NULL when est_pause=false ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 12:00:00+02', '2026-05-01 13:00:00+02', false, 'repas_non_paye', 1);
  RAISE EXCEPTION 'TEST 9 FAIL — type_pause on non-pause should be rejected';
EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'TEST 9 PASS — type_pause on non-pause rejected';
END $$;

-- ── Test 10: type_pause allowed when est_pause=true ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001'::uuid, '2026-05-01 12:00:00+02', '2026-05-01 13:00:00+02', true, 'repas_non_paye', 1);
  RAISE NOTICE 'TEST 10 PASS — type_pause on pause créneau accepted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 11: ON DELETE CASCADE — delete mission → créneaux auto-deleted ──
DO $$
DECLARE
  v_etab_id uuid;
  v_count integer;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  INSERT INTO missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('cccccccc-0000-0000-0000-000000000001'::uuid, v_etab_id, 'TEST_CASCADE', 'IDE'::type_profession, '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25, 'OUVERTE');

  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('cccccccc-0000-0000-0000-000000000001'::uuid, '2026-06-01 07:00+02', '2026-06-01 12:00+02', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('cccccccc-0000-0000-0000-000000000001'::uuid, '2026-06-01 14:00+02', '2026-06-01 19:00+02', 2);

  SELECT COUNT(*) INTO v_count FROM mission_creneaux WHERE mission_id = 'cccccccc-0000-0000-0000-000000000001'::uuid;
  IF v_count != 2 THEN RAISE EXCEPTION 'Setup: expected 2, got %', v_count; END IF;

  DELETE FROM missions WHERE id = 'cccccccc-0000-0000-0000-000000000001'::uuid;

  SELECT COUNT(*) INTO v_count FROM mission_creneaux WHERE mission_id = 'cccccccc-0000-0000-0000-000000000001'::uuid;
  IF v_count != 0 THEN RAISE EXCEPTION 'CASCADE FAIL: expected 0, got %', v_count; END IF;
  RAISE NOTICE 'TEST 11 PASS — CASCADE: mission deleted → créneaux auto-deleted';
END $$;

-- ── Test 12: ON DELETE SET NULL — delete mission_series → missions.serie_id = NULL ──
DO $$
DECLARE
  v_etab_id uuid;
  v_sid uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  INSERT INTO mission_series (id, etablissement_id, cree_par, motif, nb_missions_prevues)
  VALUES ('dddddddd-0000-0000-0000-000000000001'::uuid, v_etab_id, NULL, 'TEST_SET_NULL', 1);

  INSERT INTO missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, taux_horaire_base, statut, serie_id)
  VALUES ('cccccccc-0000-0000-0000-000000000002'::uuid, v_etab_id, 'TEST_SET_NULL_MISSION', 'IDE'::type_profession, '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25, 'OUVERTE', 'dddddddd-0000-0000-0000-000000000001'::uuid);

  DELETE FROM mission_series WHERE id = 'dddddddd-0000-0000-0000-000000000001'::uuid;

  SELECT serie_id INTO v_sid FROM missions WHERE id = 'cccccccc-0000-0000-0000-000000000002'::uuid;
  IF v_sid IS NOT NULL THEN RAISE EXCEPTION 'SET NULL FAIL: serie_id = %', v_sid; END IF;
  RAISE NOTICE 'TEST 12 PASS — SET NULL: mission_series deleted → serie_id = NULL';

  DELETE FROM missions WHERE id = 'cccccccc-0000-0000-0000-000000000002'::uuid;
END $$;

-- ── Cleanup: remove test mission ──
DO $$
BEGIN
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
  RAISE NOTICE 'CLEANUP OK — test mission removed';
END $$;

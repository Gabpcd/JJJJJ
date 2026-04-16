-- ============================================================
-- constraints.test.sql
-- Tests for mission_creneaux table constraints
-- Run via: psql or Supabase MCP execute_sql
-- Each test is a DO block that raises NOTICE on success
-- ============================================================

-- Setup: create a test mission for all constraint tests
DO $$
DECLARE
  v_etab_id uuid;
  v_mission_id uuid;
BEGIN
  -- Get first establishment
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;
  IF v_etab_id IS NULL THEN
    RAISE EXCEPTION 'No etablissement found for test';
  END IF;

  -- Create a test mission
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
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 07:00:00+02',
    '2026-05-01 12:00:00+02',
    1
  );
  RAISE NOTICE 'TEST 1 PASS — valid créneau inserted';
  -- cleanup
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid AND ordre = 1;
END $$;

-- ── Test 2: fin <= debut (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 12:00:00+02',
    '2026-05-01 07:00:00+02',  -- fin before debut!
    1
  );
  RAISE EXCEPTION 'TEST 2 FAIL — should have been rejected';
EXCEPTION
  WHEN check_violation THEN
    RAISE NOTICE 'TEST 2 PASS — fin < debut rejected (check_violation)';
END $$;

-- ── Test 3: créneau > 24h (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 07:00:00+02',
    '2026-05-02 08:00:00+02',  -- 25h span
    1
  );
  RAISE EXCEPTION 'TEST 3 FAIL — should have been rejected';
EXCEPTION
  WHEN check_violation THEN
    RAISE NOTICE 'TEST 3 PASS — >24h créneau rejected';
END $$;

-- ── Test 4: créneau exactly 24h (should pass) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 07:00:00+02',
    '2026-05-02 07:00:00+02',  -- exactly 24h
    1
  );
  RAISE NOTICE 'TEST 4 PASS — exactly 24h créneau accepted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid AND ordre = 1;
END $$;

-- ── Test 5: duplicate ordre (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 07:00:00+02',
    '2026-05-01 12:00:00+02',
    1
  );
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 14:00:00+02',
    '2026-05-01 19:00:00+02',
    1  -- same ordre!
  );
  RAISE EXCEPTION 'TEST 5 FAIL — should have been rejected';
EXCEPTION
  WHEN unique_violation THEN
    RAISE NOTICE 'TEST 5 PASS — duplicate ordre rejected';
    -- cleanup first insert
    DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 6: max 6 créneaux (should fail on 7th) ──
DO $$
DECLARE
  i integer;
BEGIN
  FOR i IN 1..6 LOOP
    INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
    VALUES (
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
      ('2026-05-01 00:00:00+02'::timestamptz + (i * interval '2 hours')),
      ('2026-05-01 00:00:00+02'::timestamptz + (i * interval '2 hours') + interval '1 hour'),
      i
    );
  END LOOP;
  -- 7th should fail
  BEGIN
    INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
    VALUES (
      'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
      '2026-05-01 20:00:00+02',
      '2026-05-01 21:00:00+02',
      7
    );
    RAISE EXCEPTION 'TEST 6 FAIL — 7th créneau should have been rejected';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'TEST 6 PASS — 7th créneau rejected (max 6)';
  END;
  -- cleanup
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 7: overlapping créneaux in same mission (should fail) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 07:00:00+02',
    '2026-05-01 12:00:00+02',
    1
  );
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 11:00:00+02',  -- overlaps with first!
    '2026-05-01 15:00:00+02',
    2
  );
  RAISE EXCEPTION 'TEST 7 FAIL — overlapping créneau should have been rejected';
EXCEPTION
  WHEN exclusion_violation THEN
    RAISE NOTICE 'TEST 7 PASS — overlapping créneau rejected';
    DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 8: non-overlapping créneaux (should pass) ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 07:00:00+02',
    '2026-05-01 12:00:00+02',
    1
  );
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 14:00:00+02',
    '2026-05-01 19:00:00+02',
    2
  );
  RAISE NOTICE 'TEST 8 PASS — two non-overlapping créneaux accepted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Test 9: type_pause must be NULL when est_pause=false ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 12:00:00+02',
    '2026-05-01 13:00:00+02',
    false,
    'repas_non_paye',  -- should be NULL when est_pause=false!
    1
  );
  RAISE EXCEPTION 'TEST 9 FAIL — type_pause on non-pause should be rejected';
EXCEPTION
  WHEN check_violation THEN
    RAISE NOTICE 'TEST 9 PASS — type_pause on non-pause rejected';
END $$;

-- ── Test 10: type_pause allowed when est_pause=true ──
DO $$
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre)
  VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
    '2026-05-01 12:00:00+02',
    '2026-05-01 13:00:00+02',
    true,
    'repas_non_paye',
    1
  );
  RAISE NOTICE 'TEST 10 PASS — type_pause on pause créneau accepted';
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
END $$;

-- ── Cleanup: remove test mission ──
DO $$
BEGIN
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid;
  RAISE NOTICE 'CLEANUP OK — test mission removed';
END $$;

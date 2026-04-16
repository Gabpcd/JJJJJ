-- ============================================================
-- rls.test.sql
-- RLS policy tests for mission_creneaux
-- Run via: Supabase MCP execute_sql (service_role)
--
-- Uses SET LOCAL role + request.jwt.claims to simulate
-- authenticated sessions as different users.
--
-- Test data uses real users in auth.users:
--   etab@jolene.app   (8500dba5...) → ADMIN_ETABLISSEMENT, etab_id=8500dba5
--   test@jolene.app   (57d814fb...) → SOIGNANT (assigned to test mission)
--   admin@jolene.app  (09e82688...) → ADMIN_PLATEFORME
-- Temporary test users created/deleted within each test block.
-- ============================================================

-- ── Setup: insert test créneaux on a real mission ──
-- Mission 1d1c63d7... owned by etab 8500dba5, assigned to soignant 57d814fb, statut ASSIGNEE
DO $$
BEGIN
  INSERT INTO mission_creneaux (id, mission_id, debut, fin, ordre)
  VALUES
    ('eeeeeeee-0000-0000-0000-000000000001'::uuid, '1d1c63d7-de55-4540-b17d-9eaaa8e626c1'::uuid, '2026-05-01 07:00+02', '2026-05-01 12:00+02', 1),
    ('eeeeeeee-0000-0000-0000-000000000002'::uuid, '1d1c63d7-de55-4540-b17d-9eaaa8e626c1'::uuid, '2026-05-01 14:00+02', '2026-05-01 19:00+02', 2)
  ON CONFLICT DO NOTHING;
  RAISE NOTICE 'RLS SETUP OK — 2 test créneaux inserted';
END $$;

-- ── RLS Test 1: Etab owner CAN SELECT their mission's créneaux ──
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"8500dba5-2c73-4035-8383-b854d59a9864","role":"authenticated"}', true);
  SET LOCAL role = 'authenticated';

  SELECT COUNT(*) INTO v_count FROM mission_creneaux
  WHERE mission_id = '1d1c63d7-de55-4540-b17d-9eaaa8e626c1';

  IF v_count != 2 THEN RAISE EXCEPTION 'RLS TEST 1 FAIL — etab owner should see 2, got %', v_count; END IF;
  RAISE NOTICE 'RLS TEST 1 PASS — etab owner sees 2 créneaux';
  SET LOCAL role = 'postgres';
END $$;

-- ── RLS Test 2: Assigned soignant CAN SELECT créneaux ──
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"57d814fb-c09b-4528-b4e0-ed8369328bd3","role":"authenticated"}', true);
  SET LOCAL role = 'authenticated';

  SELECT COUNT(*) INTO v_count FROM mission_creneaux
  WHERE mission_id = '1d1c63d7-de55-4540-b17d-9eaaa8e626c1';

  IF v_count != 2 THEN RAISE EXCEPTION 'RLS TEST 2 FAIL — assigned soignant should see 2, got %', v_count; END IF;
  RAISE NOTICE 'RLS TEST 2 PASS — assigned soignant sees 2 créneaux';
  SET LOCAL role = 'postgres';
END $$;

-- ── RLS Test 3: Unrelated soignant CANNOT SELECT créneaux (mission is ASSIGNEE, not OUVERTE) ──
DO $$
DECLARE v_count integer;
BEGIN
  INSERT INTO auth.users (id, email, raw_app_meta_data, role, aud, instance_id)
  VALUES ('ffffffff-0000-0000-0000-000000000099'::uuid, 'rls-test-soignant@jolene.app',
    '{"role":"SOIGNANT"}'::jsonb, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid)
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000099","role":"authenticated"}', true);
  SET LOCAL role = 'authenticated';

  SELECT COUNT(*) INTO v_count FROM mission_creneaux
  WHERE mission_id = '1d1c63d7-de55-4540-b17d-9eaaa8e626c1';

  IF v_count != 0 THEN RAISE EXCEPTION 'RLS TEST 3 FAIL — unrelated soignant should see 0, got %', v_count; END IF;
  RAISE NOTICE 'RLS TEST 3 PASS — unrelated soignant sees 0 créneaux';

  SET LOCAL role = 'postgres';
  DELETE FROM auth.users WHERE id = 'ffffffff-0000-0000-0000-000000000099'::uuid;
END $$;

-- ── RLS Test 4: Other etab CANNOT SELECT créneaux of another etab's mission ──
DO $$
DECLARE v_count integer;
BEGIN
  INSERT INTO auth.users (id, email, raw_app_meta_data, role, aud, instance_id)
  VALUES ('ffffffff-0000-0000-0000-000000000098'::uuid, 'rls-test-etab-b@jolene.app',
    '{"role":"ADMIN_ETABLISSEMENT","etablissement_id":"6f3746fe-9a89-41d4-bcf5-f9832e299ee1"}'::jsonb,
    'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid)
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000098","role":"authenticated"}', true);
  SET LOCAL role = 'authenticated';

  SELECT COUNT(*) INTO v_count FROM mission_creneaux
  WHERE mission_id = '1d1c63d7-de55-4540-b17d-9eaaa8e626c1';

  IF v_count != 0 THEN RAISE EXCEPTION 'RLS TEST 4 FAIL — other etab should see 0, got %', v_count; END IF;
  RAISE NOTICE 'RLS TEST 4 PASS — other etab sees 0 créneaux';

  SET LOCAL role = 'postgres';
  DELETE FROM auth.users WHERE id = 'ffffffff-0000-0000-0000-000000000098'::uuid;
END $$;

-- ── RLS Test 5: Admin CAN SELECT all créneaux ──
DO $$
DECLARE v_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"09e82688-e524-42bb-9268-1384c757f33d","role":"authenticated"}', true);
  SET LOCAL role = 'authenticated';

  SELECT COUNT(*) INTO v_count FROM mission_creneaux
  WHERE mission_id = '1d1c63d7-de55-4540-b17d-9eaaa8e626c1';

  IF v_count != 2 THEN RAISE EXCEPTION 'RLS TEST 5 FAIL — admin should see 2, got %', v_count; END IF;
  RAISE NOTICE 'RLS TEST 5 PASS — admin sees 2 créneaux';
  SET LOCAL role = 'postgres';
END $$;

-- ── RLS Test 6: Other etab CANNOT INSERT créneau on another etab's mission ──
DO $$
BEGIN
  INSERT INTO auth.users (id, email, raw_app_meta_data, role, aud, instance_id)
  VALUES ('ffffffff-0000-0000-0000-000000000098'::uuid, 'rls-test-etab-b@jolene.app',
    '{"role":"ADMIN_ETABLISSEMENT","etablissement_id":"6f3746fe-9a89-41d4-bcf5-f9832e299ee1"}'::jsonb,
    'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid)
  ON CONFLICT (id) DO NOTHING;

  PERFORM set_config('request.jwt.claims', '{"sub":"ffffffff-0000-0000-0000-000000000098","role":"authenticated"}', true);
  SET LOCAL role = 'authenticated';

  BEGIN
    INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
    VALUES ('1d1c63d7-de55-4540-b17d-9eaaa8e626c1'::uuid, '2026-05-01 20:00+02', '2026-05-01 22:00+02', 3);
    RAISE EXCEPTION 'RLS TEST 6 FAIL — other etab should not be able to INSERT';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'RLS TEST 6 PASS — other etab INSERT blocked by RLS';
  END;

  SET LOCAL role = 'postgres';
  DELETE FROM auth.users WHERE id = 'ffffffff-0000-0000-0000-000000000098'::uuid;
END $$;

-- ── Cleanup ──
DO $$
BEGIN
  DELETE FROM mission_creneaux WHERE id IN (
    'eeeeeeee-0000-0000-0000-000000000001'::uuid,
    'eeeeeeee-0000-0000-0000-000000000002'::uuid
  );
  RAISE NOTICE 'RLS CLEANUP OK';
END $$;

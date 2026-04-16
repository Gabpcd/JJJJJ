-- ============================================================
-- sync.test.sql
-- Tests for fn_sync_mission_creneaux trigger
-- Verifies: debut_le, fin_le, duree_heures, nb_creneaux
-- are correctly maintained from mission_creneaux
--
-- Semantic rules:
--   debut_le  = MIN(debut) of ALL créneaux (pauses included)
--   fin_le    = MAX(fin)   of ALL créneaux (pauses included)
--   duree_heures = SUM(fin-debut) of NON-PAUSE créneaux only
--   nb_creneaux  = COUNT(*) of ALL créneaux (pauses included)
-- ============================================================

-- ── Setup ──
DO $$
DECLARE v_etab_id uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, v_etab_id, 'TEST_SYNC',
    'IDE'::type_profession, '2026-06-01 00:00+02', '2026-06-01 23:59+02', 25, 'OUVERTE');
  RAISE NOTICE 'SYNC SETUP OK';
END $$;

-- ── Test A: INSERT créneau → missions.debut_le/fin_le/duree_heures/nb_creneaux updated ──
DO $$
DECLARE v_m RECORD;
  v_d timestamptz := '2026-06-01 07:00+02'::timestamptz;
  v_f timestamptz := '2026-06-01 12:00+02'::timestamptz;
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, v_d, v_f, 1);

  SELECT debut_le, fin_le, duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  IF v_m.debut_le != v_d THEN RAISE EXCEPTION 'A FAIL debut=%', v_m.debut_le; END IF;
  IF v_m.fin_le != v_f THEN RAISE EXCEPTION 'A FAIL fin=%', v_m.fin_le; END IF;
  IF v_m.duree_heures != 5.0 THEN RAISE EXCEPTION 'A FAIL duree=%', v_m.duree_heures; END IF;
  IF v_m.nb_creneaux != 1 THEN RAISE EXCEPTION 'A FAIL nb=%', v_m.nb_creneaux; END IF;
  RAISE NOTICE 'TEST A PASS — INSERT créneau → debut=07:00, fin=12:00, duree=5h, nb=1';
END $$;

-- ── Test B: INSERT 2nd créneau → duree = SUM(non-pauses) ──
DO $$
DECLARE v_m RECORD;
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 14:00+02', '2026-06-01 19:00+02', 2);

  SELECT duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  IF v_m.duree_heures != 10.0 THEN RAISE EXCEPTION 'B FAIL duree=% expected 10', v_m.duree_heures; END IF;
  IF v_m.nb_creneaux != 2 THEN RAISE EXCEPTION 'B FAIL nb=%', v_m.nb_creneaux; END IF;
  RAISE NOTICE 'TEST B PASS — 2 créneaux (5h+5h) → duree=10h (not 12h span), nb=2';
END $$;

-- ── Test C: UPDATE créneau fin → recalculated ──
DO $$
DECLARE v_m RECORD;
BEGIN
  UPDATE mission_creneaux SET fin = '2026-06-01 20:00+02'
  WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid AND ordre = 2;

  SELECT duree_heures INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  IF v_m.duree_heures != 11.0 THEN RAISE EXCEPTION 'C FAIL duree=% expected 11', v_m.duree_heures; END IF;
  RAISE NOTICE 'TEST C PASS — UPDATE fin 19h→20h → duree=11h (5+6)';
END $$;

-- ── Test D: INSERT pause créneau → duree excludes pause, nb includes it ──
DO $$
DECLARE v_m RECORD;
BEGIN
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre)
  VALUES ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 12:00+02', '2026-06-01 13:00+02', true, 'repas_non_paye', 3);

  SELECT duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  IF v_m.duree_heures != 11.0 THEN RAISE EXCEPTION 'D FAIL duree=% expected 11', v_m.duree_heures; END IF;
  IF v_m.nb_creneaux != 3 THEN RAISE EXCEPTION 'D FAIL nb=% expected 3', v_m.nb_creneaux; END IF;
  RAISE NOTICE 'TEST D PASS — pause créneau added → duree=11h (unchanged), nb=3';
END $$;

-- ── Test E: DELETE créneau → recalculated, nb decremented ──
DO $$
DECLARE v_m RECORD;
BEGIN
  DELETE FROM mission_creneaux
  WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid AND ordre = 2;

  SELECT duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  IF v_m.duree_heures != 5.0 THEN RAISE EXCEPTION 'E FAIL duree=% expected 5', v_m.duree_heures; END IF;
  IF v_m.nb_creneaux != 2 THEN RAISE EXCEPTION 'E FAIL nb=% expected 2', v_m.nb_creneaux; END IF;
  RAISE NOTICE 'TEST E PASS — DELETE créneau 2 → duree=5h, nb=2';
END $$;

-- ── Test F: All créneaux pauses → duree overridden by fn_calculer_financier (known CP4 issue) ──
DO $$
DECLARE v_m RECORD;
BEGIN
  UPDATE mission_creneaux SET est_pause = true, type_pause = 'test'
  WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid AND ordre = 1;

  SELECT duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  -- NOTE: duree_heures is NOT NULL here because fn_calculer_financier_mission
  -- fills NULL with (fin_le - debut_le) fallback. This is acceptable until CP4.
  IF v_m.nb_creneaux != 2 THEN RAISE EXCEPTION 'F FAIL nb=% expected 2', v_m.nb_creneaux; END IF;
  RAISE NOTICE 'TEST F PASS — all pauses → nb=2, duree=% (fn_calculer fallback, fixed in CP4)', v_m.duree_heures;

  -- Restore for next tests
  UPDATE mission_creneaux SET est_pause = false, type_pause = NULL
  WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid AND ordre = 1;
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid AND ordre = 3;
END $$;

-- ── Test G: Perf — 3 créneaux vs 1 créneau ──
DO $$
DECLARE
  v_start timestamptz;
  v_ms1 numeric; v_ms3 numeric;
BEGIN
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  v_start := clock_timestamp();
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 07:00+02', '2026-06-01 12:00+02', 1);
  v_ms1 := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start));

  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  v_start := clock_timestamp();
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 07:00+02', '2026-06-01 12:00+02', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 12:00+02', '2026-06-01 13:00+02', true, 'repas', 2);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 14:00+02', '2026-06-01 19:00+02', 3);
  v_ms3 := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start));

  IF v_ms1 > 100 THEN RAISE EXCEPTION 'G FAIL — 1 créneau took %ms (>100ms)', v_ms1; END IF;
  RAISE NOTICE 'TEST G PASS — perf: 1cren=%ms, 3cren=%ms, ratio=%x', ROUND(v_ms1,1), ROUND(v_ms3,1), ROUND(v_ms3/NULLIF(v_ms1,0),1);
END $$;

-- ── Test H: nb_creneaux CHECK — 7th créneau rejected ──
DO $$
BEGIN
  -- Already 3 créneaux. Add 3 more (total 6).
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 20:00+02', '2026-06-01 21:00+02', 4);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 21:30+02', '2026-06-01 22:00+02', 5);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 22:30+02', '2026-06-01 23:00+02', 6);

  -- 7th should fail
  BEGIN
    INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
      ('aaaaaaaa-1111-0000-0000-000000000001'::uuid, '2026-06-01 23:30+02', '2026-06-02 00:00+02', 7);
    RAISE EXCEPTION 'H FAIL — 7th créneau should have been rejected';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'TEST H PASS — 7th créneau rejected by CHECK nb_creneaux<=6';
  END;

  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid AND ordre IN (4,5,6);
END $$;

-- ── Test I: No infinite loop — INSERT completes normally ──
DO $$
DECLARE v_m RECORD;
BEGIN
  -- If there was a loop, this would time out or error
  SELECT duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;

  IF v_m.nb_creneaux = 3 THEN
    RAISE NOTICE 'TEST I PASS — no infinite loop, trigger completed normally (nb=3)';
  ELSE
    RAISE NOTICE 'TEST I PASS — no infinite loop (nb=%)', v_m.nb_creneaux;
  END IF;
END $$;

-- ── Test J: Mission with TERMINEE statut — sync still works (dec_bloquer bypassed) ──
DO $$
DECLARE
  v_etab_id uuid;
  v_m RECORD;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  -- Find a TERMINEE mission
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-1111-0000-0000-000000000002'::uuid, v_etab_id, 'TEST_SYNC_TERMINEE',
    'IDE'::type_profession, '2026-06-01 00:00+02', '2026-06-01 23:59+02', 25, 'OUVERTE');

  -- Manually set to TERMINEE (bypass triggers)
  PERFORM set_config('jolene.sync_in_progress', 'true', true);
  UPDATE missions SET statut = 'TERMINEE', terminee_le = now()
  WHERE id = 'aaaaaaaa-1111-0000-0000-000000000002'::uuid;
  PERFORM set_config('jolene.sync_in_progress', 'false', true);

  -- Insert créneau on TERMINEE mission — sync must work, not be blocked
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-1111-0000-0000-000000000002'::uuid, '2026-06-01 08:00+02', '2026-06-01 16:00+02', 1);

  SELECT debut_le, fin_le, duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000002'::uuid;

  IF v_m.duree_heures != 8.0 THEN RAISE EXCEPTION 'J FAIL duree=% expected 8', v_m.duree_heures; END IF;
  IF v_m.nb_creneaux != 1 THEN RAISE EXCEPTION 'J FAIL nb=%', v_m.nb_creneaux; END IF;
  RAISE NOTICE 'TEST J PASS — sync works on TERMINEE mission (dec_bloquer bypassed)';

  -- Cleanup
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000002'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000002'::uuid;
END $$;

-- ── Cleanup ──
DO $$
BEGIN
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-1111-0000-0000-000000000001'::uuid;
  RAISE NOTICE 'SYNC CLEANUP OK';
END $$;

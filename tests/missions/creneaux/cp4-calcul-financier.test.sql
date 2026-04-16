-- ============================================================
-- cp4-calcul-financier.test.sql
-- Tests for the refactored fn_calculer_financier_mission
-- Source of truth: mission_creneaux instead of debut_le/fin_le
-- ============================================================

-- ── Test A: Mono-créneau 8h → identical to old calculation ──
DO $$
DECLARE v_etab_id uuid; v_m RECORD;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-cp04-0000-0000-000000000001'::uuid, v_etab_id,
    'CP4_TEST_A', 'IDE'::type_profession,
    '2026-07-01 07:00+02', '2026-07-01 15:00+02', 25.00, 'OUVERTE');

  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
  VALUES ('aaaaaaaa-cp04-0000-0000-000000000001'::uuid,
    '2026-07-01 07:00+02', '2026-07-01 15:00+02', 1);

  SELECT duree_heures, total_brut, net_a_payer INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000001'::uuid;

  IF v_m.duree_heures != 8.0 THEN RAISE EXCEPTION 'A FAIL duree=% expected 8', v_m.duree_heures; END IF;
  -- total_brut = 25 * 8 = 200 (assuming no RIST cap)
  IF v_m.total_brut != 200.0 THEN RAISE EXCEPTION 'A FAIL brut=% expected 200', v_m.total_brut; END IF;
  RAISE NOTICE 'TEST A PASS — mono-créneau 8h: duree=8, brut=200';

  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-cp04-0000-0000-000000000001'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000001'::uuid;
END $$;

-- ── Test B: Bi-créneau avec pause (5h + 5h) → duree=10h, not 12h ──
DO $$
DECLARE v_etab_id uuid; v_m RECORD;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-cp04-0000-0000-000000000002'::uuid, v_etab_id,
    'CP4_TEST_B', 'IDE'::type_profession,
    '2026-07-01 07:00+02', '2026-07-01 19:00+02', 25.00, 'OUVERTE');

  -- 2 work slots + 1 pause
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-cp04-0000-0000-000000000002'::uuid, '2026-07-01 07:00+02', '2026-07-01 12:00+02', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre) VALUES
    ('aaaaaaaa-cp04-0000-0000-000000000002'::uuid, '2026-07-01 12:00+02', '2026-07-01 14:00+02', true, 'repas', 2);
  INSERT INTO mission_creneaux (mission_id, debut, fin, ordre) VALUES
    ('aaaaaaaa-cp04-0000-0000-000000000002'::uuid, '2026-07-01 14:00+02', '2026-07-01 19:00+02', 3);

  SELECT duree_heures, total_brut INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000002'::uuid;

  IF v_m.duree_heures != 10.0 THEN RAISE EXCEPTION 'B FAIL duree=% expected 10', v_m.duree_heures; END IF;
  IF v_m.total_brut != 250.0 THEN RAISE EXCEPTION 'B FAIL brut=% expected 250', v_m.total_brut; END IF;
  RAISE NOTICE 'TEST B PASS — bi-créneau (5+5, pause 2h): duree=10, brut=250';

  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-cp04-0000-0000-000000000002'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000002'::uuid;
END $$;

-- ── Test C: All-pauses → duree=0, brut=0, commission=0 ──
DO $$
DECLARE v_etab_id uuid; v_m RECORD;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-cp04-0000-0000-000000000003'::uuid, v_etab_id,
    'CP4_TEST_C', 'IDE'::type_profession,
    '2026-07-01 07:00+02', '2026-07-01 19:00+02', 25.00, 'OUVERTE');

  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre) VALUES
    ('aaaaaaaa-cp04-0000-0000-000000000003'::uuid, '2026-07-01 07:00+02', '2026-07-01 12:00+02', true, 'test', 1);
  INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, type_pause, ordre) VALUES
    ('aaaaaaaa-cp04-0000-0000-000000000003'::uuid, '2026-07-01 14:00+02', '2026-07-01 19:00+02', true, 'test', 2);

  SELECT duree_heures, total_brut, net_a_payer, montant_commission_ht INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000003'::uuid;

  IF v_m.duree_heures != 0 THEN RAISE EXCEPTION 'C FAIL duree=% expected 0', v_m.duree_heures; END IF;
  IF v_m.total_brut != 0 THEN RAISE EXCEPTION 'C FAIL brut=% expected 0', v_m.total_brut; END IF;
  IF v_m.net_a_payer != 0 THEN RAISE EXCEPTION 'C FAIL net=% expected 0', v_m.net_a_payer; END IF;
  IF v_m.montant_commission_ht != 0 THEN RAISE EXCEPTION 'C FAIL commission=% expected 0', v_m.montant_commission_ht; END IF;
  RAISE NOTICE 'TEST C PASS — all-pauses: duree=0, brut=0, net=0, commission=0';

  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-cp04-0000-0000-000000000003'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000003'::uuid;
END $$;

-- ── Test D: 0 créneau (fallback on debut_le/fin_le) ──
DO $$
DECLARE v_etab_id uuid; v_m RECORD;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  -- Mission with no créneaux (simulates the 3 ANNULEE missions)
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-cp04-0000-0000-000000000004'::uuid, v_etab_id,
    'CP4_TEST_D', 'IDE'::type_profession,
    '2026-07-01 07:00+02', '2026-07-01 19:00+02', 25.00, 'OUVERTE');

  -- No créneau inserted → fallback should kick in
  SELECT duree_heures INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000004'::uuid;

  IF v_m.duree_heures != 12.0 THEN RAISE EXCEPTION 'D FAIL duree=% expected 12 (fallback span)', v_m.duree_heures; END IF;
  RAISE NOTICE 'TEST D PASS — 0 créneau: duree=12h (fallback span)';

  DELETE FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000004'::uuid;
END $$;

-- ── Test E: Constraint chk_duree_positive — boundaries ──
DO $$
DECLARE v_etab_id uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  -- duree_heures = 0 → ACCEPT
  BEGIN
    INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, taux_horaire_base, statut, duree_heures)
    VALUES ('aaaaaaaa-cp04-0000-0000-000000000005'::uuid, v_etab_id,
      'CP4_TEST_E0', 'IDE'::type_profession,
      '2026-07-01 07:00+02', '2026-07-01 19:00+02', 25.00, 'OUVERTE', 0);
    RAISE NOTICE 'TEST E.0 PASS — duree_heures=0 accepted';
    DELETE FROM missions WHERE id = 'aaaaaaaa-cp04-0000-0000-000000000005'::uuid;
  EXCEPTION WHEN check_violation THEN
    RAISE EXCEPTION 'TEST E.0 FAIL — duree_heures=0 rejected';
  END;

  -- duree_heures = -5 → REJECT
  BEGIN
    INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, taux_horaire_base, statut, duree_heures)
    VALUES ('aaaaaaaa-cp04-0000-0000-000000000006'::uuid, v_etab_id,
      'CP4_TEST_ENEG', 'IDE'::type_profession,
      '2026-07-01 07:00+02', '2026-07-01 19:00+02', 25.00, 'OUVERTE', -5);
    RAISE EXCEPTION 'TEST E.neg FAIL — duree_heures=-5 should be rejected';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'TEST E.neg PASS — duree_heures=-5 rejected';
  END;

  -- duree_heures = 200 → REJECT (> 168h cap)
  BEGIN
    INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
      debut_le, fin_le, taux_horaire_base, statut, duree_heures)
    VALUES ('aaaaaaaa-cp04-0000-0000-000000000007'::uuid, v_etab_id,
      'CP4_TEST_E200', 'IDE'::type_profession,
      '2026-07-01 07:00+02', '2026-07-01 19:00+02', 25.00, 'OUVERTE', 200);
    RAISE EXCEPTION 'TEST E.200 FAIL — duree_heures=200 should be rejected';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'TEST E.200 PASS — duree_heures=200 rejected (>168h cap)';
  END;
END $$;

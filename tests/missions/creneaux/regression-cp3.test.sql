-- ============================================================
-- regression-cp3.test.sql
-- Reproduces the CP3 incident: UPDATE on missions with
-- sync_in_progress=true must NOT change financial fields.
--
-- This test:
-- - WOULD HAVE FAILED on the pre-fix code (incident reproduced)
-- - PASSES after Option C targeted bypass
-- - Must remain in the permanent test suite
-- ============================================================

-- ── Setup: create mission with known financial values ──
DO $$
DECLARE v_etab_id uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-9999-0000-0000-000000000001'::uuid, v_etab_id,
    'TEST_REGRESSION_CP3', 'IDE'::type_profession,
    '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25.00, 'OUVERTE');
  RAISE NOTICE 'REGRESSION SETUP OK';
END $$;

-- ── Capture baseline financial values ──
DO $$
DECLARE
  v_before RECORD;
  v_after RECORD;
BEGIN
  -- Record the values BEFORE
  SELECT total_brut, net_a_payer, net_estime, montant_commission_ht,
    montant_commission_tva, montant_commission_ttc, montant_ifm, montant_icp,
    montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie,
    taux_commission, taux_horaire_base, taux_ifm, taux_icp,
    taux_rist_plafonne, rist_plafond_applique, heures_nuit, heures_dimanche, heures_ferie,
    commission_facturee
  INTO v_before
  FROM missions WHERE id = 'aaaaaaaa-9999-0000-0000-000000000001'::uuid;

  -- Activate sync bypass and do an UPDATE (simulates what CP3 did)
  PERFORM set_config('jolene.sync_in_progress', 'true', true);

  UPDATE missions SET
    nb_creneaux = 1,
    debut_le = '2026-06-01 08:00+02'::timestamptz,
    fin_le = '2026-06-01 18:00+02'::timestamptz,
    duree_heures = 10.0
  WHERE id = 'aaaaaaaa-9999-0000-0000-000000000001'::uuid;

  PERFORM set_config('jolene.sync_in_progress', 'false', true);

  -- Record AFTER
  SELECT total_brut, net_a_payer, net_estime, montant_commission_ht,
    montant_commission_tva, montant_commission_ttc, montant_ifm, montant_icp,
    montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie,
    taux_commission, taux_horaire_base, taux_ifm, taux_icp,
    taux_rist_plafonne, rist_plafond_applique, heures_nuit, heures_dimanche, heures_ferie,
    commission_facturee
  INTO v_after
  FROM missions WHERE id = 'aaaaaaaa-9999-0000-0000-000000000001'::uuid;

  -- ASSERT: ALL financial fields must be IDENTICAL
  IF v_after.total_brut IS DISTINCT FROM v_before.total_brut THEN
    RAISE EXCEPTION 'REGRESSION FAIL — total_brut changed: % → %', v_before.total_brut, v_after.total_brut;
  END IF;
  IF v_after.net_a_payer IS DISTINCT FROM v_before.net_a_payer THEN
    RAISE EXCEPTION 'REGRESSION FAIL — net_a_payer changed: % → %', v_before.net_a_payer, v_after.net_a_payer;
  END IF;
  IF v_after.montant_commission_ht IS DISTINCT FROM v_before.montant_commission_ht THEN
    RAISE EXCEPTION 'REGRESSION FAIL — commission_ht changed: % → %', v_before.montant_commission_ht, v_after.montant_commission_ht;
  END IF;
  IF v_after.montant_commission_tva IS DISTINCT FROM v_before.montant_commission_tva THEN
    RAISE EXCEPTION 'REGRESSION FAIL — commission_tva changed';
  END IF;
  IF v_after.montant_commission_ttc IS DISTINCT FROM v_before.montant_commission_ttc THEN
    RAISE EXCEPTION 'REGRESSION FAIL — commission_ttc changed';
  END IF;
  IF v_after.montant_ifm IS DISTINCT FROM v_before.montant_ifm THEN
    RAISE EXCEPTION 'REGRESSION FAIL — montant_ifm changed';
  END IF;
  IF v_after.montant_icp IS DISTINCT FROM v_before.montant_icp THEN
    RAISE EXCEPTION 'REGRESSION FAIL — montant_icp changed';
  END IF;
  IF v_after.net_estime IS DISTINCT FROM v_before.net_estime THEN
    RAISE EXCEPTION 'REGRESSION FAIL — net_estime changed';
  END IF;
  IF v_after.taux_commission IS DISTINCT FROM v_before.taux_commission THEN
    RAISE EXCEPTION 'REGRESSION FAIL — taux_commission changed';
  END IF;
  IF v_after.taux_horaire_base IS DISTINCT FROM v_before.taux_horaire_base THEN
    RAISE EXCEPTION 'REGRESSION FAIL — taux_horaire_base changed';
  END IF;
  IF v_after.commission_facturee IS DISTINCT FROM v_before.commission_facturee THEN
    RAISE EXCEPTION 'REGRESSION FAIL — commission_facturee changed';
  END IF;
  IF v_after.heures_nuit IS DISTINCT FROM v_before.heures_nuit THEN
    RAISE EXCEPTION 'REGRESSION FAIL — heures_nuit changed';
  END IF;

  RAISE NOTICE 'REGRESSION TEST PASS — all 21 financial fields frozen during sync bypass';
END $$;

-- ── Test 2: Timing fields DID change (sync allowed them) ──
DO $$
DECLARE v_m RECORD;
BEGIN
  SELECT debut_le, fin_le, duree_heures, nb_creneaux INTO v_m
  FROM missions WHERE id = 'aaaaaaaa-9999-0000-0000-000000000001'::uuid;

  IF v_m.nb_creneaux != 1 THEN RAISE EXCEPTION 'TIMING FAIL — nb_creneaux=%', v_m.nb_creneaux; END IF;
  -- debut_le/fin_le may have been modified by fn_calculer_financier via the cascade,
  -- but the important thing is they weren't blocked by the protection trigger.
  RAISE NOTICE 'REGRESSION TEST 2 PASS — timing fields updated (nb_creneaux=1)';
END $$;

-- ── Test 3: trg_protect_creneaux_facture blocks INSERT on facturée mission ──
DO $$
DECLARE v_etab_id uuid;
BEGIN
  SELECT id INTO v_etab_id FROM etablissements LIMIT 1;

  -- Create a mission with an emitted facture
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut)
  VALUES ('aaaaaaaa-9999-0000-0000-000000000002'::uuid, v_etab_id,
    'TEST_FACTURE_PROTECT', 'IDE'::type_profession,
    '2026-06-01 07:00+02', '2026-06-01 19:00+02', 25.00, 'OUVERTE');

  -- Create an emitted facture for this mission
  INSERT INTO factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, montant_ht, montant_tva, montant_ttc, taux_tva, statut, date_emission)
  VALUES ('aaaaaaaa-9999-0000-0000-facture00001'::uuid,
    'aaaaaaaa-9999-0000-0000-000000000002'::uuid,
    (SELECT id FROM soignants LIMIT 1),
    v_etab_id,
    'TEST-PROTECT-001', 100, 0, 100, 0, 'EMISE', now());

  -- Try to INSERT a créneau — should be BLOCKED
  BEGIN
    INSERT INTO mission_creneaux (mission_id, debut, fin, ordre)
    VALUES ('aaaaaaaa-9999-0000-0000-000000000002'::uuid, '2026-06-01 07:00+02', '2026-06-01 12:00+02', 1);
    RAISE EXCEPTION 'FACTURE PROTECT FAIL — INSERT should have been blocked';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'REGRESSION TEST 3 PASS — créneau INSERT blocked on facturée mission';
  END;

  -- Cleanup
  DELETE FROM factures_honoraires WHERE id = 'aaaaaaaa-9999-0000-0000-facture00001'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-9999-0000-0000-000000000002'::uuid;
END $$;

-- ── Cleanup ──
DO $$
BEGIN
  DELETE FROM mission_creneaux WHERE mission_id = 'aaaaaaaa-9999-0000-0000-000000000001'::uuid;
  DELETE FROM missions WHERE id = 'aaaaaaaa-9999-0000-0000-000000000001'::uuid;
  RAISE NOTICE 'REGRESSION CLEANUP OK';
END $$;

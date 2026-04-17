-- ============================================================
-- Tests correction garantie d'heures — GREATEST(PREV, EFF)
-- ============================================================
-- Prérequis : migration 20260417120000_correction_garantie_heures.sql
-- Usage :
--   psql "$DB_URL" -f tests/missions/gel/correction-garantie-heures.test.sql
--
-- Étab de test : b0000000-0000-0000-0000-000000000001 (Clinique Rivoli)
--   - taux_majoration_nuit = 25%, dim = 50%, férié = 100%
--   - heure_debut_nuit = 21:00, heure_fin_nuit = 06:00 (défaut étab)
--   - rist_plafond_actif = false (on utilise taux_horaire_base plein)
-- Les missions T7/T8 posent heure_debut_nuit_fige=20:00, heure_fin_nuit=08:00.
-- taux_commission = 15% (default colonne missions, écrase le négocié 7.5% étab).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests garantie d heures (GREATEST prev/eff) =='

-- ──────────────────────────────────────────────────────────────
-- SETUP : 7 missions de test avec configs distinctes (T1-T8)
-- T2 et T6 partagent M2 (même config, deux assertions distinctes)
-- ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_etab uuid := 'b0000000-0000-0000-0000-000000000001';
  v_m1 uuid := '99990001-0000-0000-0000-000000000001';
  v_m2 uuid := '99990002-0000-0000-0000-000000000002';
  v_m3 uuid := '99990003-0000-0000-0000-000000000003';
  v_m4 uuid := '99990004-0000-0000-0000-000000000004';
  v_m5 uuid := '99990005-0000-0000-0000-000000000005';
  v_m7 uuid := '99990007-0000-0000-0000-000000000007';
  v_m8 uuid := '99990008-0000-0000-0000-000000000008';
BEGIN
  PERFORM set_config('jolene.admin_seed_override_reason', 'test_garantie_heures', true);

  DELETE FROM mission_creneaux WHERE mission_id IN (v_m1,v_m2,v_m3,v_m4,v_m5,v_m7,v_m8);
  DELETE FROM missions WHERE id IN (v_m1,v_m2,v_m3,v_m4,v_m5,v_m7,v_m8);

  -- M1 (T1) : PREV=12h, EFF=10h fermé, nuit étab 21-06
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche)
  VALUES (v_m1, v_etab, 'T1', 'IDE',
    '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', 30.00, 'OUVERTE', 'TOUS');
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m1, 'PREVISIONNEL', '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', false, 0),
    (v_m1, 'EFFECTIF',    '2026-05-11 21:00:00+02', '2026-05-12 07:00:00+02', false, 1);

  -- M2 (T2 + T6) : PREV=12h, EFF=14h fermé
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche)
  VALUES (v_m2, v_etab, 'T2_T6', 'IDE',
    '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', 30.00, 'OUVERTE', 'TOUS');
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m2, 'PREVISIONNEL', '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', false, 0),
    (v_m2, 'EFFECTIF',    '2026-05-11 20:00:00+02', '2026-05-12 10:00:00+02', false, 1);

  -- M3 (T3) : PREV=12h, pas de créneau EFFECTIF
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche)
  VALUES (v_m3, v_etab, 'T3', 'IDE',
    '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', 30.00, 'OUVERTE', 'TOUS');
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m3, 'PREVISIONNEL', '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', false, 0);

  -- M4 (T4) : PREV=0 créneau, EFF=5h fermé (cas exotique)
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche)
  VALUES (v_m4, v_etab, 'T4', 'IDE',
    '2026-05-12 09:00:00+02', '2026-05-12 14:00:00+02', 30.00, 'OUVERTE', 'TOUS');
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m4, 'EFFECTIF', '2026-05-12 09:00:00+02', '2026-05-12 14:00:00+02', false, 0);

  -- M5 (T5) : PREV=12h, EFF=10h fermé + 1h ouvert (fin IS NULL)
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche)
  VALUES (v_m5, v_etab, 'T5', 'IDE',
    '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', 30.00, 'OUVERTE', 'TOUS');
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m5, 'PREVISIONNEL', '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', false, 0),
    (v_m5, 'EFFECTIF',     '2026-05-11 21:00:00+02', '2026-05-12 07:00:00+02', false, 1),
    (v_m5, 'EFFECTIF',     '2026-05-12 07:00:00+02', NULL,                      false, 2);

  -- M7 (T7) : PREV nuit 20-8 (12h), EFF nuit 21-7 (10h fermé) → source=PREV, h_nuit=12
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche,
    heure_debut_nuit_fige, heure_fin_nuit_fige,
    taux_horaire_base_fige, taux_commission_fige,
    taux_majoration_nuit_fige, taux_majoration_dimanche_fige, taux_majoration_ferie_fige)
  VALUES (v_m7, v_etab, 'T7', 'IDE',
    '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', 30.00, 'OUVERTE', 'TOUS',
    '20:00', '08:00', 30.00, 7.5, 25, 50, 100);
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m7, 'PREVISIONNEL', '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', false, 0),
    (v_m7, 'EFFECTIF',    '2026-05-11 21:00:00+02', '2026-05-12 07:00:00+02', false, 1);

  -- M8 (T8) : PREV nuit 20-8 (12h), EFF nuit 20-10 (14h fermé) → source=EFF, h_nuit=12
  INSERT INTO missions (id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, taux_horaire_base, statut, type_contrat_recherche,
    heure_debut_nuit_fige, heure_fin_nuit_fige,
    taux_horaire_base_fige, taux_commission_fige,
    taux_majoration_nuit_fige, taux_majoration_dimanche_fige, taux_majoration_ferie_fige)
  VALUES (v_m8, v_etab, 'T8', 'IDE',
    '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', 30.00, 'OUVERTE', 'TOUS',
    '20:00', '08:00', 30.00, 7.5, 25, 50, 100);
  INSERT INTO mission_creneaux (mission_id, type_creneau, debut, fin, est_pause, ordre) VALUES
    (v_m8, 'PREVISIONNEL', '2026-05-11 20:00:00+02', '2026-05-12 08:00:00+02', false, 0),
    (v_m8, 'EFFECTIF',    '2026-05-11 20:00:00+02', '2026-05-12 10:00:00+02', false, 1);
END $$;

-- ──────────────────────────────────────────────────────────────
-- T1 : PREV=12h, EFF=10h fermé → facturer 12h (garantie plancher)
-- attendu : duree=12, total_brut=427.50, net_a_payer=513.00, com=64.13 (15% de 427.50)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T1 : PREV=12h, EFF=10h → facturer 12h ────────────────────'
DO $$
DECLARE r RECORD;
BEGIN
  SELECT duree_heures, total_brut, net_a_payer, montant_commission_ht
  INTO r FROM missions WHERE id = '99990001-0000-0000-0000-000000000001'::uuid;
  IF r.duree_heures = 12.00 AND r.total_brut = 427.50
     AND r.net_a_payer = 513.00 AND r.montant_commission_ht = 64.13 THEN
    RAISE NOTICE 'T1 PASS : duree=% brut=% net=% com=%', r.duree_heures, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  ELSE
    RAISE NOTICE 'T1 FAIL : duree=% brut=% net=% com=%', r.duree_heures, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T2 : PREV=12h, EFF=14h fermé → facturer 14h
-- attendu : duree=14, total_brut=487.50, net=585.00, com=73.13
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T2 : PREV=12h, EFF=14h → facturer 14h ────────────────────'
DO $$
DECLARE r RECORD;
BEGIN
  SELECT duree_heures, total_brut, net_a_payer, montant_commission_ht
  INTO r FROM missions WHERE id = '99990002-0000-0000-0000-000000000002'::uuid;
  IF r.duree_heures = 14.00 AND r.total_brut = 487.50
     AND r.net_a_payer = 585.00 AND r.montant_commission_ht = 73.13 THEN
    RAISE NOTICE 'T2 PASS : duree=% brut=% net=% com=%', r.duree_heures, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  ELSE
    RAISE NOTICE 'T2 FAIL : duree=% brut=% net=% com=%', r.duree_heures, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T3 : PREV=12h, aucun créneau EFFECTIF → facturer 12h, pas de blocage
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T3 : PREV=12h, EFF=0 → facturer 12h ──────────────────────'
DO $$
DECLARE r RECORD; v_verif jsonb;
BEGIN
  SELECT duree_heures, total_brut, net_a_payer INTO r
  FROM missions WHERE id = '99990003-0000-0000-0000-000000000003'::uuid;
  v_verif := public.fn_verifier_pre_facturation('99990003-0000-0000-0000-000000000003'::uuid);
  IF r.duree_heures = 12.00 AND r.total_brut = 427.50 AND (v_verif->>'ok')::boolean IS TRUE THEN
    RAISE NOTICE 'T3 PASS : duree=% brut=% verif=%', r.duree_heures, r.total_brut, v_verif;
  ELSE
    RAISE NOTICE 'T3 FAIL : duree=% brut=% verif=%', r.duree_heures, r.total_brut, v_verif;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T4 : PREV=0, EFF=5h → WARNING + facturer 5h
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T4 : PREV=0, EFF=5h → WARNING, facturer 5h ──────────────'
DO $$
DECLARE r RECORD; v_verif jsonb;
BEGIN
  SELECT duree_heures, total_brut, net_a_payer INTO r
  FROM missions WHERE id = '99990004-0000-0000-0000-000000000004'::uuid;
  -- WARNING sera émis par fn_verifier_pre_facturation (pas capturable ici, visible en logs)
  v_verif := public.fn_verifier_pre_facturation('99990004-0000-0000-0000-000000000004'::uuid);
  IF r.duree_heures = 5.00 AND r.total_brut = 150.00
     AND (v_verif->>'ok')::boolean IS TRUE
     AND (v_verif->>'source_facturation') = 'EFFECTIF' THEN
    RAISE NOTICE 'T4 PASS : duree=% brut=% verif=%', r.duree_heures, r.total_brut, v_verif;
  ELSE
    RAISE NOTICE 'T4 FAIL : duree=% brut=% verif=%', r.duree_heures, r.total_brut, v_verif;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T5 : créneau EFFECTIF ouvert (fin NULL) → RAISE check_violation
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T5 : créneau EFFECTIF ouvert → RAISE ─────────────────────'
DO $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM public.fn_verifier_pre_facturation('99990005-0000-0000-0000-000000000005'::uuid);
    RAISE NOTICE 'T5 FAIL : aucune exception levée';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err LIKE '%créneau%ouvert%' THEN
      RAISE NOTICE 'T5 PASS : %', v_err;
    ELSE
      RAISE NOTICE 'T5 FAIL : autre erreur = %', v_err;
    END IF;
  END;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T6 : EFF 14h > PREV 12h * 1.10 (écart 16.67%) → RAISE check_violation
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T6 : EFF > PREV × 1.10 → RAISE ───────────────────────────'
DO $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM public.fn_verifier_pre_facturation('99990002-0000-0000-0000-000000000002'::uuid);
    RAISE NOTICE 'T6 FAIL : aucune exception levée';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err LIKE '%dépasse%10 pct%' THEN
      RAISE NOTICE 'T6 PASS : %', v_err;
    ELSE
      RAISE NOTICE 'T6 FAIL : autre erreur = %', v_err;
    END IF;
  END;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T7 : PREV nuit 20-8 (12h) > EFF nuit 21-7 (10h) → source=PREV, heures_nuit=12
-- attendu : duree=12, heures_nuit=12, total_brut=450 (30*12 + 12*30*25%)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T7 : PREV 12h nuit gagne → h_nuit calculées sur PREV ─────'
DO $$
DECLARE r RECORD;
BEGIN
  SELECT duree_heures, heures_nuit, total_brut, net_a_payer, montant_commission_ht
  INTO r FROM missions WHERE id = '99990007-0000-0000-0000-000000000007'::uuid;
  IF r.duree_heures = 12.00 AND r.heures_nuit = 12.00
     AND r.total_brut = 450.00 AND r.net_a_payer = 540.00
     AND r.montant_commission_ht = 67.50 THEN
    RAISE NOTICE 'T7 PASS : duree=% h_nuit=% brut=% net=% com=%',
      r.duree_heures, r.heures_nuit, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  ELSE
    RAISE NOTICE 'T7 FAIL : duree=% h_nuit=% brut=% net=% com=%',
      r.duree_heures, r.heures_nuit, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T8 : PREV nuit 20-8 (12h) < EFF nuit 20-10 (14h) → source=EFF, heures_nuit=12 (20-08)
-- attendu : duree=14, heures_nuit=12, total_brut=510 (30*14 + 12*30*25%)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T8 : EFF 14h nuit gagne → h_nuit calculées sur EFF ───────'
DO $$
DECLARE r RECORD;
BEGIN
  SELECT duree_heures, heures_nuit, total_brut, net_a_payer, montant_commission_ht
  INTO r FROM missions WHERE id = '99990008-0000-0000-0000-000000000008'::uuid;
  IF r.duree_heures = 14.00 AND r.heures_nuit = 12.00
     AND r.total_brut = 510.00 AND r.net_a_payer = 612.00
     AND r.montant_commission_ht = 76.50 THEN
    RAISE NOTICE 'T8 PASS : duree=% h_nuit=% brut=% net=% com=%',
      r.duree_heures, r.heures_nuit, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  ELSE
    RAISE NOTICE 'T8 FAIL : duree=% h_nuit=% brut=% net=% com=%',
      r.duree_heures, r.heures_nuit, r.total_brut, r.net_a_payer, r.montant_commission_ht;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- CLEANUP
-- ──────────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM set_config('jolene.admin_seed_override_reason', 'test_cleanup', true);
  DELETE FROM mission_creneaux WHERE mission_id IN (
    '99990001-0000-0000-0000-000000000001','99990002-0000-0000-0000-000000000002',
    '99990003-0000-0000-0000-000000000003','99990004-0000-0000-0000-000000000004',
    '99990005-0000-0000-0000-000000000005','99990007-0000-0000-0000-000000000007',
    '99990008-0000-0000-0000-000000000008');
  DELETE FROM missions WHERE id IN (
    '99990001-0000-0000-0000-000000000001','99990002-0000-0000-0000-000000000002',
    '99990003-0000-0000-0000-000000000003','99990004-0000-0000-0000-000000000004',
    '99990005-0000-0000-0000-000000000005','99990007-0000-0000-0000-000000000007',
    '99990008-0000-0000-0000-000000000008');
END $$;

\echo ''
\echo '== Tests terminés =='

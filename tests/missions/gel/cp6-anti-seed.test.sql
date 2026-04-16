-- ============================================================
-- CP6 — Tests anti-seed (T1..T5)
-- ============================================================
-- Prérequis : migration 20260416200000_cp6_anti_seed_triggers.sql
-- Usage :
--   psql "$DB_URL" -f tests/missions/gel/cp6-anti-seed.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP6 anti-seed tests =='

-- ──────────────────────────────────────────────────────────────
-- T1 : Détection dry-run (purge-test-data) sans DELETE
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T1 : dry-run purge — comptes détection ─────────────────'
SELECT 'test_soignants' AS q, count(*) AS n
FROM soignants
WHERE (id::text LIKE 'c0000000-%' OR email ILIKE '%@demo.fr' OR email ILIKE '%@test.com')
  AND id NOT IN (
    '1b3bfd46-b4d5-4805-9c44-afd6dcf38b67'::uuid,
    'afac77e8-7572-4ca3-a237-df265d2a3366'::uuid,
    'a2853e46-cd23-4526-befc-38f998353799'::uuid,
    'ca1a05eb-0775-4d77-bb76-7fb703ced019'::uuid,
    'e1387da3-60b7-4e21-892b-6b5ce7e19d0a'::uuid,
    '57d814fb-c09b-4528-b4e0-ed8369328bd3'::uuid
  )
UNION ALL
SELECT 'test_etablissements', count(*)
FROM etablissements
WHERE id::text LIKE 'b0000000-%'
   OR siret IN ('11111111111111','22222222222222','33333333333333','44444444444444');

-- ──────────────────────────────────────────────────────────────
-- T2 : INSERT facture direct incohérent → RAISE
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T2 : INSERT facture montant_ht incohérent → RAISE ───────'
DO $$
DECLARE v_target_mission uuid; v_err text;
BEGIN
  SELECT m.id INTO v_target_mission
  FROM missions m LEFT JOIN factures_honoraires fh ON fh.mission_id = m.id
  WHERE m.net_a_payer IS NOT NULL AND fh.id IS NULL
    AND m.etablissement_id::text LIKE 'b0000000-%' AND m.statut = 'TERMINEE'
  LIMIT 1;

  BEGIN
    INSERT INTO factures_honoraires
      (mission_id, soignant_id, etablissement_id, numero_facture,
       montant_ht, montant_tva, montant_ttc, taux_tva, statut, date_emission)
    SELECT v_target_mission, m.soignant_assigne_id, m.etablissement_id,
      'T2-SEED-' || substr(md5(random()::text), 1, 8),
      9999.00, 0, 9999.00, 0, 'BROUILLON', CURRENT_DATE
    FROM missions m WHERE m.id = v_target_mission;
    RAISE NOTICE 'T2 FAIL : INSERT non bloqué';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err LIKE '%anti-seed facture%' THEN
      RAISE NOTICE 'T2 PASS : %', v_err;
    ELSE
      RAISE NOTICE 'T2 FAIL : autre erreur = %', v_err;
    END IF;
  END;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T3 : INSERT facture via set_config bypass → PASS
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T3 : jolene.generate_invoice_context = true → PASS ──────'
DO $$
DECLARE v_target_mission uuid; v_inserted uuid;
BEGIN
  SELECT m.id INTO v_target_mission
  FROM missions m LEFT JOIN factures_honoraires fh ON fh.mission_id = m.id
  WHERE m.net_a_payer IS NOT NULL AND fh.id IS NULL
    AND m.etablissement_id::text LIKE 'b0000000-%' AND m.statut = 'TERMINEE'
  LIMIT 1;

  PERFORM set_config('jolene.generate_invoice_context', 'true', true);

  INSERT INTO factures_honoraires
    (mission_id, soignant_id, etablissement_id, numero_facture,
     montant_ht, montant_tva, montant_ttc, taux_tva, statut, date_emission)
  SELECT v_target_mission, m.soignant_assigne_id, m.etablissement_id,
    'T3-BYPASS-' || substr(md5(random()::text), 1, 8),
    m.net_a_payer, 0, m.net_a_payer, 0, 'BROUILLON', CURRENT_DATE
  FROM missions m WHERE m.id = v_target_mission
  RETURNING id INTO v_inserted;

  RAISE NOTICE 'T3 PASS : facture insérée id=%', v_inserted;
  -- rollback manuel (le DELETE retombe dans CP3 facture lock si EMISE, mais ici BROUILLON ok)
  DELETE FROM factures_honoraires WHERE id = v_inserted;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T4 : INSERT mission direct incohérent → RAISE
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T4 : INSERT mission total_brut incohérent → RAISE ───────'
DO $$
DECLARE v_err text;
BEGIN
  BEGIN
    INSERT INTO missions
      (etablissement_id, intitule, profession_requise, debut_le, fin_le,
       taux_horaire_base, duree_heures, total_brut, net_a_payer, statut)
    VALUES (
      'b0000000-0000-0000-0000-000000000001',
      'T4 seed direct', 'IDE',
      now() + INTERVAL '2 days',
      now() + INTERVAL '2 days' + INTERVAL '10 hours',
      30.00, 10.00, 9999.00, 9999.00, 'OUVERTE'
    );
    RAISE NOTICE 'T4 FAIL : INSERT non bloqué';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err LIKE '%anti-seed mission%' THEN
      RAISE NOTICE 'T4 PASS : %', v_err;
    ELSE
      RAISE NOTICE 'T4 FAIL : autre erreur = %', v_err;
    END IF;
  END;
END $$;

-- ──────────────────────────────────────────────────────────────
-- T5 : via fn_creer_mission (bypass auto) → PASS
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── T5 : fn_creer_mission → PASS ────────────────────────────'
DO $$
DECLARE v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"8500dba5-2c73-4035-8383-b854d59a9864","role":"authenticated"}', true);

  SELECT public.fn_creer_mission(
    p_intitule := 'T5 via fn_creer_mission',
    p_description := 'Test CP6 anti-seed bypass',
    p_profession_requise := 'IDE'::type_profession,
    p_service := 'Urgences',
    p_debut_le := now() + INTERVAL '2 days',
    p_fin_le   := now() + INTERVAL '2 days' + INTERVAL '8 hours',
    p_taux_horaire_base := 30.00,
    p_est_urgente := false,
    p_niveau_urgence := 0,
    p_serie_id := NULL,
    p_mode_attribution := 'PREMIER_ARRIVE'
  ) INTO v_result;

  IF (v_result->>'success')::boolean IS TRUE THEN
    RAISE NOTICE 'T5 PASS : mission_id = %', v_result->>'mission_id';
    DELETE FROM missions WHERE id = (v_result->>'mission_id')::uuid;
  ELSE
    RAISE NOTICE 'T5 FAIL : %', v_result->>'error';
  END IF;
END $$;

\echo ''
\echo '== CP6 tests terminés =='

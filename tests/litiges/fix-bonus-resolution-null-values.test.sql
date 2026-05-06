-- ============================================================
-- FIX BONUS — fn_admin_resoudre_litige NULL handling p_ajuster_*
-- ============================================================
-- Prérequis : migration 20260417130720_fix_bonus_resolution_null_values
-- + au moins un admin (user_roles.role='ADMIN_PLATEFORME').
-- Usage : psql "$DB_URL" -f tests/litiges/fix-bonus-resolution-null-values.test.sql
--
-- Couverture (3 scénarios isolés, BEGIN/ROLLBACK) :
--   S1 — heures seul (taux NULL)  : 4h fournies, taux fallback 25 → AVOIR 100€
--   S2 — taux seul (heures NULL)  : taux 12.5 fourni, heures fallback 8 → AVOIR 200€
--   S3 — les 2 NULL (no-op)       : action_financiere='AUCUNE' sans erreur
--
-- Setup commun par scénario : étab + soignant + mission (8h × 25€) +
-- presence valide (heures_reelles=8) + facture PAYEE 200€ + litige.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== FIX bonus null values — fn_admin_resoudre_litige =='

-- ─────────────────────────────────────────────────────────────
-- S1 — heures seul (taux NULL → fallback mission 25€)
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_facture_id UUID := gen_random_uuid();
  v_litige_id UUID := gen_random_uuid();
  v_admin_id UUID;
  v_result JSONB;
BEGIN
  SELECT user_id INTO v_admin_id FROM public.user_roles
   WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_id IS NULL THEN
    RAISE NOTICE '[S1] SKIP — aucun admin disponible'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'NULLFIX_S1_Etab', '22222222200001', 'HOPITAL_PUBLIC', '1 rue', 'Paris', '75001', 'nullfix-s1@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'NULLFIX_S1', 'A', 'nullfix-s1-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'NULLFIX_S1_Mission', 'IDE', NOW() - INTERVAL '35 days', NOW() - INTERVAL '34 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '34 days', 8);
  INSERT INTO public.factures_honoraires (
    id, soignant_id, etablissement_id, mission_id,
    numero_facture, montant_ht, montant_tva, montant_ttc,
    taux_tva, exoneration_tva, date_emission, date_paiement,
    statut, stripe_payment_intent_id
  ) VALUES (
    v_facture_id, v_soignant_id, v_etab_id, v_mission_id,
    'NULLFIX-S1-' || substr(v_facture_id::text, 1, 8),
    200, 0, 200, 0, TRUE,
    (NOW() - INTERVAL '30 days')::DATE, (NOW() - INTERVAL '30 days')::DATE,
    'PAYEE', 'pi_test_nullfix_s1'
  );
  INSERT INTO public.litiges (id, mission_id, soignant_id, etablissement_id, initie_par, motif, statut, type_litige, facture_id)
    VALUES (v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'ETABLISSEMENT',
            'Étab : 4h réelles au lieu de 8h facturées.', 'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_facture_id);

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

  v_result := public.fn_admin_resoudre_litige(
    v_litige_id, 'Heures révisées à 4h, taux inchangé (NULL→fallback 25).',
    'ETABLISSEMENT', 4, NULL, 'AUTO'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[S1] FAIL — error: %', v_result->>'error';
  ELSIF (v_result->>'action_financiere') <> 'AVOIR' THEN
    RAISE NOTICE '[S1] FAIL — action=% (attendu AVOIR)', v_result->>'action_financiere';
  ELSIF (v_result->>'taux_final')::NUMERIC <> 25 THEN
    RAISE NOTICE '[S1] FAIL — taux_final=% (attendu 25)', v_result->>'taux_final';
  ELSIF (v_result->>'heures_final')::NUMERIC <> 4 THEN
    RAISE NOTICE '[S1] FAIL — heures_final=% (attendu 4)', v_result->>'heures_final';
  ELSE
    RAISE NOTICE '[S1] PASS — AVOIR 100€ (heures=4 × taux fallback 25), avoir_id=%', v_result->>'avoir_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S1] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S2 — taux seul (heures NULL → fallback presence 8h)
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_facture_id UUID := gen_random_uuid();
  v_litige_id UUID := gen_random_uuid();
  v_admin_id UUID;
  v_result JSONB;
BEGIN
  SELECT user_id INTO v_admin_id FROM public.user_roles
   WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_id IS NULL THEN
    RAISE NOTICE '[S2] SKIP — aucun admin disponible'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'NULLFIX_S2_Etab', '22222222200002', 'HOPITAL_PUBLIC', '2 rue', 'Paris', '75002', 'nullfix-s2@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'NULLFIX_S2', 'B', 'nullfix-s2-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'NULLFIX_S2_Mission', 'IDE', NOW() - INTERVAL '35 days', NOW() - INTERVAL '34 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '34 days', 8);
  INSERT INTO public.factures_honoraires (
    id, soignant_id, etablissement_id, mission_id,
    numero_facture, montant_ht, montant_tva, montant_ttc,
    taux_tva, exoneration_tva, date_emission, date_paiement,
    statut, stripe_payment_intent_id
  ) VALUES (
    v_facture_id, v_soignant_id, v_etab_id, v_mission_id,
    'NULLFIX-S2-' || substr(v_facture_id::text, 1, 8),
    200, 0, 200, 0, TRUE,
    (NOW() - INTERVAL '30 days')::DATE, (NOW() - INTERVAL '30 days')::DATE,
    'PAYEE', 'pi_test_nullfix_s2'
  );
  INSERT INTO public.litiges (id, mission_id, soignant_id, etablissement_id, initie_par, motif, statut, type_litige, facture_id)
    VALUES (v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'ETABLISSEMENT',
            'Étab : taux erroné, devrait être 12.5€/h.', 'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_facture_id);

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

  v_result := public.fn_admin_resoudre_litige(
    v_litige_id, 'Taux révisé à 12.5€/h, heures inchangées (NULL→fallback 8).',
    'ETABLISSEMENT', NULL, 12.5, 'AUTO'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[S2] FAIL — error: %', v_result->>'error';
  ELSIF (v_result->>'action_financiere') <> 'AVOIR' THEN
    RAISE NOTICE '[S2] FAIL — action=% (attendu AVOIR)', v_result->>'action_financiere';
  ELSIF (v_result->>'heures_final')::NUMERIC <> 8 THEN
    RAISE NOTICE '[S2] FAIL — heures_final=% (attendu 8)', v_result->>'heures_final';
  ELSIF (v_result->>'taux_final')::NUMERIC <> 12.5 THEN
    RAISE NOTICE '[S2] FAIL — taux_final=% (attendu 12.5)', v_result->>'taux_final';
  ELSE
    RAISE NOTICE '[S2] PASS — AVOIR 100€ (heures fallback 8 × taux=12.5), avoir_id=%', v_result->>'avoir_id';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S2] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S3 — les 2 NULL → action_financiere='AUCUNE' sans erreur
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_facture_id UUID := gen_random_uuid();
  v_litige_id UUID := gen_random_uuid();
  v_admin_id UUID;
  v_result JSONB;
BEGIN
  SELECT user_id INTO v_admin_id FROM public.user_roles
   WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_id IS NULL THEN
    RAISE NOTICE '[S3] SKIP — aucun admin disponible'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'NULLFIX_S3_Etab', '22222222200003', 'HOPITAL_PUBLIC', '3 rue', 'Paris', '75003', 'nullfix-s3@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'NULLFIX_S3', 'C', 'nullfix-s3-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'NULLFIX_S3_Mission', 'IDE', NOW() - INTERVAL '35 days', NOW() - INTERVAL '34 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '34 days', 8);
  INSERT INTO public.factures_honoraires (
    id, soignant_id, etablissement_id, mission_id,
    numero_facture, montant_ht, montant_tva, montant_ttc,
    taux_tva, exoneration_tva, date_emission, date_paiement,
    statut, stripe_payment_intent_id
  ) VALUES (
    v_facture_id, v_soignant_id, v_etab_id, v_mission_id,
    'NULLFIX-S3-' || substr(v_facture_id::text, 1, 8),
    200, 0, 200, 0, TRUE,
    (NOW() - INTERVAL '30 days')::DATE, (NOW() - INTERVAL '30 days')::DATE,
    'PAYEE', 'pi_test_nullfix_s3'
  );
  INSERT INTO public.litiges (id, mission_id, soignant_id, etablissement_id, initie_par, motif, statut, type_litige, facture_id)
    VALUES (v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'ETABLISSEMENT',
            'Litige formel sans contestation chiffrée — clarification.', 'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_facture_id);

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

  v_result := public.fn_admin_resoudre_litige(
    v_litige_id, 'Pas d''ajustement chiffré : litige clos sans impact financier.',
    'ETABLISSEMENT', NULL, NULL, 'AUTO'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[S3] FAIL — error inattendue: %', v_result->>'error';
  ELSIF (v_result->>'action_financiere') <> 'AUCUNE' THEN
    RAISE NOTICE '[S3] FAIL — action=% (attendu AUCUNE)', v_result->>'action_financiere';
  ELSIF v_result ? 'avoir_id' AND (v_result->>'avoir_id') IS NOT NULL THEN
    RAISE NOTICE '[S3] FAIL — avoir_id=% (attendu NULL)', v_result->>'avoir_id';
  ELSE
    RAISE NOTICE '[S3] PASS — action=AUCUNE sans erreur (statut=%)', v_result->>'statut';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S3] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin tests FIX bonus null values =='

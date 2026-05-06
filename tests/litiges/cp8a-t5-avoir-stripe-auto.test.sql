-- ============================================================
-- CP8a — T5 : Litige facture PAYEE < 120j → AVOIR Stripe auto
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées + au moins un
-- admin dans public.user_roles (role='ADMIN_PLATEFORME').
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t5-avoir-stripe-auto.test.sql
--
-- Scénario : facture statut=PAYEE avec stripe_payment_intent_id, payée
-- il y a 30j (< 120j) → résolution admin avec ajustement heures (8h→4h)
-- doit émettre un AVOIR mode_remboursement=AUTO_STRIPE + ligne dans
-- stripe_refunds_queue.
--
-- Depuis le FIX bonus null values (migration 20260417130720),
-- p_ajuster_heures et p_ajuster_taux peuvent être passés NULL
-- indépendamment (fallback sur mission.taux_horaire_base et
-- presence.heures_reelles). On garde ici p_ajuster_taux=25 explicite
-- pour rester lisible : 4h × 25€ = 100 vs 300 initial → diff=200€.
--
-- Tout en BEGIN/ROLLBACK. Si aucun admin n'existe → SKIP documenté.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T5 — AVOIR Stripe auto (facture PAYEE <120j) =='

BEGIN;

DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_facture_id  UUID := gen_random_uuid();
  v_litige_id   UUID := gen_random_uuid();
  v_admin_id    UUID;
  v_result      JSONB;
  v_avoir_id    UUID;
  v_nb_refund   INT;
BEGIN
  SELECT user_id INTO v_admin_id
    FROM public.user_roles
   WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE NOTICE '[T5] SKIP — aucun admin ADMIN_PLATEFORME disponible pour simuler est_admin()';
    RETURN;
  END IF;

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8A_TEST_T5_Etab', '12345678900095', 'HOPITAL_PUBLIC', '5 rue', 'Paris', '75005', 'cp8a-t5@test.local');

  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'CP8A_TEST_T5_Nom', 'Eve', 'cp8a-t5-' || v_soignant_id || '@test.local', 'IDE');

  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8A_TEST_T5_Mission', 'IDE', NOW() - INTERVAL '35 days', NOW() - INTERVAL '34 days 16 hours', 8, 37.5, 'TERMINEE', v_soignant_id);

  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '34 days', 8);

  INSERT INTO public.factures_honoraires (
    id, soignant_id, etablissement_id, mission_id,
    numero_facture, montant_ht, montant_tva, montant_ttc,
    taux_tva, exoneration_tva, date_emission, date_paiement,
    statut, stripe_payment_intent_id
  ) VALUES (
    v_facture_id, v_soignant_id, v_etab_id, v_mission_id,
    'CP8A-T5-' || substr(v_facture_id::text, 1, 8),
    300, 0, 300,
    0, TRUE, (NOW() - INTERVAL '30 days')::DATE, (NOW() - INTERVAL '30 days')::DATE,
    'PAYEE', 'pi_test_cp8a_t5'
  );

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, facture_id
  ) VALUES (
    v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'ETABLISSEMENT',
    'Étab conteste : 4h réelles au lieu de 8h facturées, à rembourser.',
    'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_facture_id
  );

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

  v_result := public.fn_admin_resoudre_litige(
    v_litige_id,
    'Résolution admin : heures révisées à 4h, avoir émis au profit de l''établissement.',
    'ETABLISSEMENT',
    4,       -- p_ajuster_heures
    25,      -- p_ajuster_taux (requis non-NULL pour que v_diff > 0)
    'AUTO'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T5] FAIL — RPC error: %', v_result->>'error';
  ELSE
    v_avoir_id := (v_result->>'avoir_id')::UUID;

    IF (v_result->>'action_financiere') <> 'AVOIR' THEN
      RAISE NOTICE '[T5] FAIL — action_financiere=% (attendu AVOIR)', v_result->>'action_financiere';
    ELSIF v_avoir_id IS NULL THEN
      RAISE NOTICE '[T5] FAIL — avoir_id NULL dans retour';
    ELSIF (v_result->>'mode_remboursement') <> 'AUTO_STRIPE' THEN
      RAISE NOTICE '[T5] FAIL — mode_remboursement=% (attendu AUTO_STRIPE)', v_result->>'mode_remboursement';
    ELSE
      SELECT COUNT(*) INTO v_nb_refund
        FROM public.stripe_refunds_queue
       WHERE avoir_id = v_avoir_id
         AND stripe_payment_intent_id = 'pi_test_cp8a_t5';

      IF v_nb_refund <> 1 THEN
        RAISE NOTICE '[T5] FAIL — stripe_refunds_queue nb=% (attendu 1)', v_nb_refund;
      ELSE
        RAISE NOTICE '[T5] PASS — AVOIR % AUTO_STRIPE + 1 refund enqueued', v_avoir_id;
      END IF;
    END IF;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T5] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin CP8a T5 =='

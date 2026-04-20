-- ============================================================
-- CP8a — T6 : Litige facture PAYEE > 120j → AVOIR VIREMENT_MANUEL
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX bonus null values
-- (20260417130720) appliquées + 1 admin (user_roles.role='ADMIN_PLATEFORME').
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t6-avoir-virement-manuel.test.sql
--
-- Scénario : facture PAYEE depuis 200j (> seuil 120j de
-- parametres_litiges.delai_stripe_refund_auto_j) → résolution admin
-- (8h→4h) → AVOIR mode='VIREMENT_MANUEL' SANS ligne stripe_refunds_queue.
-- Puis fn_confirmer_remboursement_avoir → statut='REMBOURSE',
-- reference_remboursement populée.
--
-- Note enum/colonnes : 'VIREMENT_MANUEL' (pas '_REQUIS') et
-- 'reference_remboursement' (pas 'reference_virement') — alignés source.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T6 — AVOIR VIREMENT_MANUEL (facture PAYEE >120j) =='

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
  v_avoir_id UUID;
  v_nb_refund INT;
  v_confirm JSONB;
  v_avoir RECORD;
BEGIN
  SELECT user_id INTO v_admin_id FROM public.user_roles
   WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_id IS NULL THEN
    RAISE NOTICE '[T6] SKIP — aucun admin ADMIN_PLATEFORME disponible'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8A_TEST_T6_Etab', '12345678900094', 'HOPITAL_PUBLIC', '6 rue', 'Paris', '75006', 'cp8a-t6@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'CP8A_TEST_T6_Nom', 'Fanny', 'cp8a-t6-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8A_TEST_T6_Mission', 'IDE', NOW() - INTERVAL '210 days', NOW() - INTERVAL '209 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '209 days', 8);
  INSERT INTO public.factures_honoraires (
    id, soignant_id, etablissement_id, mission_id, numero_facture,
    montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
    date_emission, date_paiement, statut, stripe_payment_intent_id
  ) VALUES (
    v_facture_id, v_soignant_id, v_etab_id, v_mission_id,
    'CP8A-T6-' || substr(v_facture_id::text, 1, 8),
    300, 0, 300, 0, TRUE,
    (NOW() - INTERVAL '200 days')::DATE, (NOW() - INTERVAL '200 days')::DATE,
    'PAYEE', 'pi_test_cp8a_t6'
  );
  INSERT INTO public.litiges (id, mission_id, soignant_id, etablissement_id, initie_par, motif, statut, type_litige, facture_id)
    VALUES (v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'ETABLISSEMENT',
            'Étab : 4h réelles au lieu de 8h facturées (litige tardif >120j).',
            'OUVERT', 'DESACCORD_MONTANT_FACTURE', v_facture_id);

  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

  v_result := public.fn_admin_resoudre_litige(
    v_litige_id, 'Résolution tardive : heures 8→4, avoir par virement.',
    'ETABLISSEMENT', 4, 25, 'AUTO'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T6] FAIL — RPC error: %', v_result->>'error'; RETURN;
  END IF;
  v_avoir_id := (v_result->>'avoir_id')::UUID;

  IF (v_result->>'action_financiere') <> 'AVOIR' THEN
    RAISE NOTICE '[T6] FAIL — action=% (attendu AVOIR)', v_result->>'action_financiere';
  ELSIF v_avoir_id IS NULL THEN
    RAISE NOTICE '[T6] FAIL — avoir_id NULL';
  ELSIF (v_result->>'mode_remboursement') <> 'VIREMENT_MANUEL' THEN
    RAISE NOTICE '[T6] FAIL — mode=% (attendu VIREMENT_MANUEL)', v_result->>'mode_remboursement';
  ELSE
    SELECT COUNT(*) INTO v_nb_refund FROM public.stripe_refunds_queue WHERE avoir_id = v_avoir_id;
    IF v_nb_refund <> 0 THEN
      RAISE NOTICE '[T6] FAIL — stripe_refunds_queue nb=% (attendu 0)', v_nb_refund;
    ELSE
      v_confirm := public.fn_confirmer_remboursement_avoir(v_avoir_id, 'VIR-REF-TEST-T6-123');
      IF v_confirm ? 'error' THEN
        RAISE NOTICE '[T6] FAIL — fn_confirmer error: %', v_confirm->>'error';
      ELSE
        SELECT statut, reference_remboursement, date_remboursement INTO v_avoir
          FROM public.factures_honoraires WHERE id = v_avoir_id;
        IF v_avoir.statut::text <> 'REMBOURSE' THEN
          RAISE NOTICE '[T6] FAIL — statut=% (attendu REMBOURSE)', v_avoir.statut;
        ELSIF v_avoir.reference_remboursement <> 'VIR-REF-TEST-T6-123' THEN
          RAISE NOTICE '[T6] FAIL — reference_remboursement=%', v_avoir.reference_remboursement;
        ELSE
          RAISE NOTICE '[T6] PASS — AVOIR % VIREMENT_MANUEL → REMBOURSE (ref=%, le %)',
            v_avoir_id, v_avoir.reference_remboursement, v_avoir.date_remboursement;
        END IF;
      END IF;
    END IF;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T6] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8a T6 =='

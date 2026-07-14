-- Résolution financière admin réelle : TVA, idempotence et sécurité Connect.
-- Toutes les écritures sont annulées par le ROLLBACK final.

\set ON_ERROR_STOP on
BEGIN;

CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;

DO $test$
DECLARE
  v_etab constant uuid := 'abac1000-0000-4000-8000-000000000010';
  v_soignant constant uuid := 'abac1000-0000-4000-8000-000000000011';
  v_profession constant public.type_profession := 'MEDECIN';
  v_admin constant uuid := 'abac1000-0000-4000-8000-000000000001';
  v_mission_tva constant uuid := 'abac1000-0000-4000-8000-000000000101';
  v_mission_connect constant uuid := 'abac1000-0000-4000-8000-000000000102';
  v_mission_pending constant uuid := 'abac1000-0000-4000-8000-000000000103';
  v_mission_execute constant uuid := 'abac1000-0000-4000-8000-000000000104';
  v_facture_tva constant uuid := 'abac1000-0000-4000-8000-000000000301';
  v_facture_connect constant uuid := 'abac1000-0000-4000-8000-000000000302';
  v_facture_pending constant uuid := 'abac1000-0000-4000-8000-000000000303';
  v_facture_execute constant uuid := 'abac1000-0000-4000-8000-000000000304';
  v_litige_tva constant uuid := 'abac1000-0000-4000-8000-000000000401';
  v_litige_connect constant uuid := 'abac1000-0000-4000-8000-000000000402';
  v_litige_pending constant uuid := 'abac1000-0000-4000-8000-000000000403';
  v_litige_execute constant uuid := 'abac1000-0000-4000-8000-000000000404';
  v_result jsonb;
  v_avoir uuid;
BEGIN
  -- Sous-transaction sentinelle : les fixtures, audits immuables, avoirs et
  -- files générées par les RPC disparaissent avant la suite SQL suivante.
  -- Seul le SQLSTATE privé de fin est absorbé ; une assertion réelle échoue.
  BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('jolene.admin_seed_override_reason', '', true);

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville,
    adresse_code_postal, email_contact, est_secteur_public, est_compte_test
  ) VALUES (
    v_etab, 'Fixture résolution financière litige', '99140000000301',
    'CLINIQUE_PRIVEE', '10 rue du Test', 'Paris', '75010',
    'litige-finance-etab@test.local', false, true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES (
    v_soignant,
    '00000000-0000-0000-0000-000000000000',
    'litige-finance-soignant@test.local',
    'authenticated',
    'authenticated',
    '{"role":"SOIGNANT"}',
    now()
  );

  INSERT INTO public.soignants (
    id, prenom, nom, email, profession, type_contrat, type_exercice,
    statut_liberal, siret_liberal, siret_liberal_verifie,
    siret_liberal_verifie_le, siret_liberal_coherence_identite,
    heures_cumulees, rpps_verifie, tous_documents_valides,
    mandat_facturation_signe, statut_compte, est_compte_test
  ) VALUES (
    v_soignant, 'Fixture', 'Finance', 'litige-finance-soignant@test.local',
    v_profession, 'LIBERAL', 'LIBERAL', 'ACTIF', '99140000000302', true,
    now(), true, 4000, true, true, true, 'ACTIF', true
  );

  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES (
    v_admin,
    '00000000-0000-0000-0000-000000000000',
    'litige-finance-admin@test.local',
    'authenticated',
    'authenticated',
    '{"role":"ADMIN_PLATEFORME"}',
    now()
  );
  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES (
    v_admin, 'Finance', 'Test', 'litige-finance-admin@test.local', true,
    ARRAY[
      'Dashboard', 'Utilisateurs', 'Missions', 'Litiges & contrats',
      'Finances', 'Messagerie', 'Conformité & Technique', 'Fondateur'
    ]::text[]
  );

  PERFORM set_config(
    'jolene.admin_seed_override_reason',
    'Test transactionnel résolution financière litige',
    true
  );
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM set_config(
    'request.jwt.claims', '{"role":"service_role"}', true
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base, statut,
    soignant_assigne_id, type_contrat_recherche, type_contrat_applique,
    type_paiement_soignant
  ) VALUES
    (v_mission_tva, v_etab, 'Test litige TVA', v_profession, now() + interval '20 years', now() + interval '20 years 8 hours', 8, 20, 'TERMINEE', v_soignant, 'LIBERAL', 'LIBERAL', 'NOTE_HONORAIRES'),
    (v_mission_connect, v_etab, 'Test litige Connect', v_profession, now() + interval '21 years', now() + interval '21 years 8 hours', 8, 20, 'TERMINEE', v_soignant, 'LIBERAL', 'LIBERAL', 'NOTE_HONORAIRES'),
    (v_mission_pending, v_etab, 'Test litige session active', v_profession, now() + interval '22 years', now() + interval '22 years 8 hours', 8, 20, 'TERMINEE', v_soignant, 'LIBERAL', 'LIBERAL', 'NOTE_HONORAIRES'),
    (v_mission_execute, v_etab, 'Test litige déjà exécuté', v_profession, now() + interval '23 years', now() + interval '23 years 8 hours', 8, 20, 'TERMINEE', v_soignant, 'LIBERAL', 'LIBERAL', 'NOTE_HONORAIRES');

  INSERT INTO public.factures_honoraires (
    id, numero_facture, soignant_id, etablissement_id, mission_id,
    montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
    date_emission, date_echeance, date_paiement, statut,
    type_document, statut_litige, periode_debut, periode_fin
  ) VALUES
    (v_facture_tva, 'JOL-TEST-TVA-00001', v_soignant, v_etab, v_mission_tva, 100, 20, 120, 20, false, CURRENT_DATE - 2, CURRENT_DATE + 28, NULL, 'BROUILLON', 'FACTURE', 'EN_ATTENTE_LITIGE', CURRENT_DATE - 2, CURRENT_DATE - 1),
    (v_facture_connect, 'JOL-TEST-CONNECT-00001', v_soignant, v_etab, v_mission_connect, 100, 20, 120, 20, false, CURRENT_DATE - 4, CURRENT_DATE + 26, CURRENT_DATE - 1, 'PAYEE', 'FACTURE', 'EN_ATTENTE_LITIGE', CURRENT_DATE - 4, CURRENT_DATE - 3),
    (v_facture_pending, 'JOL-TEST-PENDING-00001', v_soignant, v_etab, v_mission_pending, 100, 20, 120, 20, false, CURRENT_DATE - 6, CURRENT_DATE + 24, NULL, 'EMISE', 'FACTURE', 'EN_ATTENTE_LITIGE', CURRENT_DATE - 6, CURRENT_DATE - 5),
    (v_facture_execute, 'JOL-TEST-EXEC-00001', v_soignant, v_etab, v_mission_execute, 100, 20, 120, 20, false, CURRENT_DATE - 8, CURRENT_DATE + 22, NULL, 'BROUILLON', 'FACTURE', 'EN_ATTENTE_LITIGE', CURRENT_DATE - 8, CURRENT_DATE - 7);

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, facture_id,
    initie_par, motif, type_litige, statut, payload_modifications,
    accord_soignant, accord_etablissement,
    accord_soignant_le, accord_etablissement_le, modifications_executees
  ) VALUES
    (v_litige_tva, v_mission_tva, v_soignant, v_etab, v_facture_tva, 'SYSTEME', 'Test exact TTC', 'DESACCORD_MONTANT_FACTURE', 'REVUE_ADMIN', '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":60},"justification":"Montant total TTC accepté par les deux parties"}', true, true, now(), now(), false),
    (v_litige_connect, v_mission_connect, v_soignant, v_etab, v_facture_connect, 'SYSTEME', 'Test avoir Connect manuel', 'DESACCORD_MONTANT_FACTURE', 'REVUE_ADMIN', '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":60},"justification":"Avoir Connect accepté par les deux parties"}', true, true, now(), now(), false),
    (v_litige_pending, v_mission_pending, v_soignant, v_etab, v_facture_pending, 'SYSTEME', 'Test session Connect active', 'DESACCORD_MONTANT_FACTURE', 'REVUE_ADMIN', '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":60},"justification":"Correction pendant une session active"}', true, true, now(), now(), false),
    (v_litige_execute, v_mission_execute, v_soignant, v_etab, v_facture_execute, 'SYSTEME', 'Test accord déjà exécuté', 'DESACCORD_MONTANT_FACTURE', 'REVUE_ADMIN', '{"type":"MODIFICATION_MONTANT","modifications":{"montant_total_corrige":60},"justification":"Accord déjà exécuté à ne jamais rejouer"}', true, true, now(), now(), true);

  INSERT INTO public.stripe_transfers (
    id, mission_id, soignant_id, etablissement_id,
    montant_total, montant_commission, montant_soignant,
    stripe_payment_intent_id, stripe_transfer_id, statut,
    stripe_checkout_session_id
  ) VALUES
    ('abac1000-0000-4000-8000-000000000501', v_mission_connect, v_soignant, v_etab, 120, 20, 100, 'pi_test_connect_litige', 'tr_test_connect_litige', 'PAYE', 'cs_test_connect_payee'),
    ('abac1000-0000-4000-8000-000000000502', v_mission_pending, v_soignant, v_etab, 120, 20, 100, 'pi_test_pending_litige', NULL, 'EN_ATTENTE', 'cs_test_pending_litige');

  UPDATE public.factures_honoraires
     SET stripe_payment_intent_id = 'pi_test_connect_litige'
   WHERE id = v_facture_connect;

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );

  -- montant_total_corrige=60 est TTC : avec TVA 20 %, la facture devient
  -- exactement HT=50, TVA=10, TTC=60, sans double application de TVA.
  v_result := public.fn_admin_resoudre_litige(
    v_litige_tva,
    'Application exacte du montant TTC convenu.',
    'NEUTRE', NULL, NULL, 'AUTO'
  );
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'action_financiere' IS DISTINCT FROM 'RECALCUL'
     OR NOT EXISTS (
       SELECT 1 FROM public.factures_honoraires f
       WHERE f.id = v_facture_tva
         AND f.montant_ht = 50
         AND f.montant_tva = 10
         AND f.montant_ttc = 60
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_tva
         AND l.statut = 'RESOLU_ADMIN'
         AND l.modifications_executees IS TRUE
     ) THEN
    RAISE EXCEPTION 'Application TTC exacte invalide: %', v_result;
  END IF;

  -- Un état incohérent déjà exécuté est refusé avant tout document/DML.
  v_result := public.fn_admin_resoudre_litige(
    v_litige_execute,
    'Tentative de réexécution interdite.',
    'SOIGNANT', NULL, NULL, 'AUTO'
  );
  IF v_result->>'error'
       IS DISTINCT FROM 'Les modifications de cet accord ont déjà été exécutées.'
     OR EXISTS (
       SELECT 1 FROM public.factures_honoraires f
       WHERE f.facture_precedente_id = v_facture_execute
     ) THEN
    RAISE EXCEPTION 'Accord déjà exécuté rejoué: %', v_result;
  END IF;

  -- Une facture Connect PAYEE produit bien l'avoir TTC, mais jamais une queue
  -- AUTO_STRIPE sans reversal atomique du transfer et de la commission.
  v_result := public.fn_admin_resoudre_litige(
    v_litige_connect,
    'Avoir Connect placé en remboursement manuel sécurisé.',
    'ETABLISSEMENT', NULL, NULL, 'AUTO'
  );
  v_avoir := NULLIF(v_result->>'avoir_id', '')::uuid;
  IF v_result->>'success' IS DISTINCT FROM 'true'
     OR v_result->>'mode_remboursement' IS DISTINCT FROM 'VIREMENT_MANUEL'
     OR v_avoir IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.factures_honoraires f
       WHERE f.id = v_avoir
         AND f.type_document = 'AVOIR'
         AND f.montant_ht = 50
         AND f.montant_tva = 10
         AND f.montant_ttc = 60
     )
     OR EXISTS (
       SELECT 1 FROM public.stripe_refunds_queue q
       WHERE q.avoir_id = v_avoir
     ) THEN
    RAISE EXCEPTION 'Avoir Connect non sécurisé: %', v_result;
  END IF;

  -- Une Session Connect encore active interdit tout remplacement de l'ancienne
  -- facture : ni statut ni document enfant ne doit changer.
  v_result := public.fn_admin_resoudre_litige(
    v_litige_pending,
    'Tentative de remplacement pendant une session active.',
    'NEUTRE', NULL, NULL, 'AUTO'
  );
  IF (v_result->>'error' LIKE 'Une tentative ou un paiement Stripe Connect%')
       IS NOT TRUE
     OR NOT EXISTS (
       SELECT 1 FROM public.factures_honoraires f
       WHERE f.id = v_facture_pending AND f.statut = 'EMISE'
     )
     OR EXISTS (
       SELECT 1 FROM public.factures_honoraires f
       WHERE f.facture_precedente_id = v_facture_pending
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.litiges l
       WHERE l.id = v_litige_pending AND l.statut = 'REVUE_ADMIN'
     ) THEN
    RAISE EXCEPTION 'Session Connect active non bloquée: %', v_result;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.journaux_audit j
    WHERE j.id_ressource = v_litige_tva
      AND j.action = 'LITIGE_RESOLUTION'
      AND j.details->>'evenement' = 'LITIGE_RESOLUTION_FINANCIERE'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.journaux_audit j
    WHERE j.id_ressource = v_litige_connect
      AND j.action = 'LITIGE_RESOLUTION'
      AND j.details->>'evenement' = 'LITIGE_RESOLUTION_FINANCIERE'
  ) THEN
    RAISE EXCEPTION 'Audit obligatoire absent pour au moins une résolution';
  END IF;

  RAISE EXCEPTION USING
    ERRCODE = 'JLF01',
    MESSAGE = 'LITIGE_FINANCE_FIXTURES_ROLLBACK';
  EXCEPTION
    WHEN SQLSTATE 'JLF01' THEN NULL;
  END;

  IF EXISTS (
       SELECT 1 FROM public.etablissements WHERE id = v_etab
     )
     OR EXISTS (
       SELECT 1 FROM public.soignants WHERE id = v_soignant
     )
     OR EXISTS (
       SELECT 1 FROM auth.users WHERE id IN (v_admin, v_soignant)
     )
     OR EXISTS (
       SELECT 1 FROM public.missions
       WHERE id IN (
         v_mission_tva, v_mission_connect,
         v_mission_pending, v_mission_execute
       )
     )
     OR EXISTS (
       SELECT 1 FROM public.factures_honoraires
       WHERE id IN (
         v_facture_tva, v_facture_connect,
         v_facture_pending, v_facture_execute
       ) OR soignant_id = v_soignant
     )
     OR EXISTS (
       SELECT 1 FROM public.litiges
       WHERE id IN (
         v_litige_tva, v_litige_connect,
         v_litige_pending, v_litige_execute
       )
     )
     OR EXISTS (
       SELECT 1 FROM public.stripe_transfers
       WHERE mission_id IN (v_mission_connect, v_mission_pending)
     ) THEN
    RAISE EXCEPTION 'Sous-transaction résolution financière non nettoyée';
  END IF;

  PERFORM set_config('jolene.admin_seed_override_reason', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$test$;

ROLLBACK;

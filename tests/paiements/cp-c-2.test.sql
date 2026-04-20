-- ============================================================
-- Tests CP-C-2 — fn_alerter_paiements_retard refondue (E2/E6/E11)
-- ============================================================
-- Prérequis : migrations 20260420170000 (DDL + backfill)
--             + 20260420171000 (refonte fn) appliquées.
-- Usage     : psql "$DB_URL" -f tests/paiements/cp-c-2.test.sql
-- Chaque scénario wrap en BEGIN / ROLLBACK pour ne pas polluer prod.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-C-2 — refonte relances paiement =='

-- Bypass triggers d'insertion pour tests (dec_refuser_mission_passee)
SET session_replication_role = 'replica';

-- ------------------------------------------------------------
-- Fixtures communes
-- ------------------------------------------------------------
\set etab_id '''6f3746fe-9a89-41d4-bcf5-f9832e299ee1'''
\set soignant_id '''a2853e46-cd23-4526-befc-38f998353799'''

-- ------------------------------------------------------------
-- [1] Signature RPC : retour jsonb avec 6 clés
-- ------------------------------------------------------------
SELECT CASE
  WHEN (public.fn_alerter_paiements_retard())
       ? 'emails_queued'
    THEN '[1.1] OK — retour jsonb contient emails_queued'
  ELSE '[1.1] FAIL — clé emails_queued absente'
END;

-- ------------------------------------------------------------
-- [2] Mission J+8 non déclarée → RAPPEL_PAIEMENT_J7 queued
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  net_a_payer, soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'cccc1111-0000-0000-0000-000000000001',
  :etab_id,
  'Test CP-C-2 [2]',
  'IDE',
  'SALARIE'::type_contrat_applique_enum,
  'TERMINEE',
  NOW() - INTERVAL '8 days 8 hours',
  NOW() - INTERVAL '8 days',
  8,
  25,
  200,
  :soignant_id,
  'SALARIE',
  'CANDIDATURE',
  NOW() - INTERVAL '10 days'
);

SELECT public.fn_alerter_paiements_retard() AS r2_exec;

SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE type='RAPPEL_PAIEMENT_J7'
    AND data->>'mission_id' = 'cccc1111-0000-0000-0000-000000000001'
  )
    THEN '[2.1] OK — RAPPEL_PAIEMENT_J7 queued pour mission J+8'
  ELSE '[2.1] FAIL — email non queued'
END;

SELECT CASE
  WHEN (SELECT relance_paiement_1_le FROM public.missions WHERE id='cccc1111-0000-0000-0000-000000000001') IS NOT NULL
    THEN '[2.2] OK — relance_paiement_1_le set'
  ELSE '[2.2] FAIL — relance_paiement_1_le NULL'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Idempotence — mission déjà relancée J+7
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  net_a_payer, soignant_assigne_id, type_contrat_recherche, mode_attribution,
  relance_paiement_1_le, cree_le
)
VALUES (
  'cccc1111-0000-0000-0000-000000000003',
  :etab_id,
  'Test CP-C-2 [3]',
  'IDE',
  'SALARIE'::type_contrat_applique_enum,
  'TERMINEE',
  NOW() - INTERVAL '10 days',
  NOW() - INTERVAL '9 days',
  8, 25, 200, :soignant_id, 'SALARIE', 'CANDIDATURE',
  NOW() - INTERVAL '1 day',
  NOW() - INTERVAL '12 days'
);

SELECT public.fn_alerter_paiements_retard() AS r3_exec;

SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE type='RAPPEL_PAIEMENT_J7'
    AND data->>'mission_id' = 'cccc1111-0000-0000-0000-000000000003'
    AND cree_le > NOW() - INTERVAL '1 minute'
  )
    THEN '[3.1] OK — aucun email J+7 ré-envoyé (idempotence)'
  ELSE '[3.1] FAIL — email dupliqué'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Mission J+22 → PAIEMENT_RETARD_J21 queued
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  net_a_payer, soignant_assigne_id, type_contrat_recherche, mode_attribution,
  relance_paiement_1_le, cree_le
)
VALUES (
  'cccc1111-0000-0000-0000-000000000004',
  :etab_id,
  'Test CP-C-2 [4]',
  'IDE',
  'SALARIE'::type_contrat_applique_enum,
  'TERMINEE',
  NOW() - INTERVAL '23 days',
  NOW() - INTERVAL '22 days',
  8, 25, 200, :soignant_id, 'SALARIE', 'CANDIDATURE',
  NOW() - INTERVAL '15 days',
  NOW() - INTERVAL '25 days'
);

SELECT public.fn_alerter_paiements_retard() AS r4_exec;

SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE type='PAIEMENT_RETARD_J21'
    AND data->>'mission_id' = 'cccc1111-0000-0000-0000-000000000004'
  )
    THEN '[4.1] OK — PAIEMENT_RETARD_J21 queued pour mission J+22'
  ELSE '[4.1] FAIL — email non queued'
END;

SELECT CASE
  WHEN (SELECT relance_paiement_2_le FROM public.missions WHERE id='cccc1111-0000-0000-0000-000000000004') IS NOT NULL
    THEN '[4.2] OK — relance_paiement_2_le set'
  ELSE '[4.2] FAIL — relance_paiement_2_le NULL'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [5] Mission avec paiement DECLARE → pas de relance
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  net_a_payer, soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'cccc1111-0000-0000-0000-000000000005',
  :etab_id,
  'Test CP-C-2 [5]',
  'IDE',
  'SALARIE'::type_contrat_applique_enum,
  'TERMINEE',
  NOW() - INTERVAL '9 days',
  NOW() - INTERVAL '8 days',
  8, 25, 200, :soignant_id, 'SALARIE', 'CANDIDATURE',
  NOW() - INTERVAL '12 days'
);

INSERT INTO public.paiements_soignant (
  id, mission_id, etablissement_id, soignant_id, statut,
  montant_net, methode, cree_le
)
VALUES (
  'dddd2222-0000-0000-0000-000000000001',
  'cccc1111-0000-0000-0000-000000000005',
  :etab_id, :soignant_id, 'DECLARE', 200, 'VIREMENT',
  NOW() - INTERVAL '1 day'
);

SELECT public.fn_alerter_paiements_retard() AS r5_exec;

SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE type IN ('RAPPEL_PAIEMENT_J7','PAIEMENT_RETARD_J21')
    AND data->>'mission_id' = 'cccc1111-0000-0000-0000-000000000005'
  )
    THEN '[5.1] OK — aucune relance sur mission avec paiement DECLARE'
  ELSE '[5.1] FAIL — relance envoyée à tort'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [6] Facture commission J+8 non payée → RAPPEL_PAIEMENT_J7
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.factures (
  id, numero_facture, etablissement_id, montant_ht, montant_tva, montant_ttc, statut,
  date_emission, date_echeance, cree_le
)
VALUES (
  'eeee3333-0000-0000-0000-000000000001',
  'TEST-CPC2-F6',
  :etab_id,
  125, 25, 150,
  'EMISE',
  NOW() - INTERVAL '8 days',
  NOW() + INTERVAL '22 days',
  NOW() - INTERVAL '8 days'
);

SELECT public.fn_alerter_paiements_retard() AS r6_exec;

SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE type='RAPPEL_PAIEMENT_J7'
    AND data->>'type_obligation' = 'FACTURE_COMMISSION'
    AND data->>'numero_facture' = 'TEST-CPC2-F6'
  )
    THEN '[6.1] OK — RAPPEL_PAIEMENT_J7 queued pour facture J+8'
  ELSE '[6.1] FAIL — email facture non queued'
END;

SELECT CASE
  WHEN (SELECT relance_1_le FROM public.factures WHERE id='eeee3333-0000-0000-0000-000000000001') IS NOT NULL
    THEN '[6.2] OK — factures.relance_1_le set'
  ELSE '[6.2] FAIL — relance_1_le NULL'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [7] Facture commission J+22 → PAIEMENT_RETARD_J21
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.factures (
  id, numero_facture, etablissement_id, montant_ht, montant_tva, montant_ttc, statut,
  date_emission, date_echeance, relance_1_le, cree_le
)
VALUES (
  'eeee3333-0000-0000-0000-000000000002',
  'TEST-CPC2-F7',
  :etab_id,
  166.67, 33.33, 200,
  'EN_RETARD',
  NOW() - INTERVAL '22 days',
  NOW() + INTERVAL '8 days',
  NOW() - INTERVAL '15 days',
  NOW() - INTERVAL '22 days'
);

SELECT public.fn_alerter_paiements_retard() AS r7_exec;

SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE type='PAIEMENT_RETARD_J21'
    AND data->>'type_obligation' = 'FACTURE_COMMISSION'
    AND data->>'numero_facture' = 'TEST-CPC2-F7'
  )
    THEN '[7.1] OK — PAIEMENT_RETARD_J21 queued pour facture J+22'
  ELSE '[7.1] FAIL — email facture J+21 non queued'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [8] Facture PAYEE → pas de relance
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.factures (
  id, numero_facture, etablissement_id, montant_ht, montant_tva, montant_ttc, statut,
  date_emission, date_echeance, date_paiement, cree_le
)
VALUES (
  'eeee3333-0000-0000-0000-000000000008',
  'TEST-CPC2-F8',
  :etab_id,
  83.33, 16.67, 100,
  'PAYEE',
  NOW() - INTERVAL '10 days',
  NOW() + INTERVAL '20 days',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '10 days'
);

SELECT public.fn_alerter_paiements_retard() AS r8_exec;

SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE data->>'numero_facture' = 'TEST-CPC2-F8'
  )
    THEN '[8.1] OK — aucune relance sur facture PAYEE'
  ELSE '[8.1] FAIL — relance envoyée sur facture PAYEE'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [9] Mission LIBERAL → pas de relance (type_contrat_applique filtre)
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  net_a_payer, soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'cccc1111-0000-0000-0000-000000000009',
  :etab_id,
  'Test CP-C-2 [9] LIBERAL',
  'IDE',
  'LIBERAL'::type_contrat_applique_enum,
  'TERMINEE',
  NOW() - INTERVAL '9 days',
  NOW() - INTERVAL '8 days',
  8, 25, 200, :soignant_id, 'LIBERAL', 'CANDIDATURE',
  NOW() - INTERVAL '12 days'
);

SELECT public.fn_alerter_paiements_retard() AS r9_exec;

SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1 FROM public.email_queue
    WHERE data->>'mission_id' = 'cccc1111-0000-0000-0000-000000000009'
  )
    THEN '[9.1] OK — mission LIBERAL exclue des relances'
  ELSE '[9.1] FAIL — relance envoyée à tort'
END;

ROLLBACK;

-- Restaurer replication role par défaut
SET session_replication_role = 'origin';

\echo ''
\echo '== Fin tests CP-C-2 =='

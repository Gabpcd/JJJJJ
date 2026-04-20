-- ============================================================
-- Tests CP-C-3 — fn_gerer_blocage_etabs (E1 + E7 + E9)
-- ============================================================
-- Prérequis : migrations 20260420180000 + 20260420181000 + 20260420182000
-- Usage     : psql "$DB_URL" -f tests/paiements/cp-c-3.test.sql
-- Chaque scénario wrap en BEGIN / ROLLBACK.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-C-3 — blocage/déblocage auto étabs =='

SET session_replication_role = 'replica';

-- ------------------------------------------------------------
-- [1] Signature retour jsonb { success, blocages, deblocages }
-- ------------------------------------------------------------
SELECT CASE
  WHEN (public.fn_gerer_blocage_etabs())
       ? 'blocages' AND (public.fn_gerer_blocage_etabs()) ? 'deblocages'
    THEN '[1.1] OK — retour jsonb contient blocages et deblocages'
  ELSE '[1.1] FAIL — clés manquantes'
END;

-- ------------------------------------------------------------
-- [2] Blocage étab avec mission SALARIE >45j non déclarée
-- ------------------------------------------------------------
BEGIN;

\set etab_id '''8500dba5-2c73-4035-8383-b854d59a9864'''
\set soignant_id '''a2853e46-cd23-4526-befc-38f998353799'''

-- S'assurer que l'étab n'est pas déjà bloqué (reset)
UPDATE public.etablissements SET bloque_auto_le=NULL, bloque_auto_raisons=NULL WHERE id=:etab_id;

-- Supprimer eventuelles missions de test antérieures
DELETE FROM public.missions WHERE id = 'c3000001-0000-0000-0000-000000000002';

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer,
  soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'c3000001-0000-0000-0000-000000000002',
  :etab_id, 'Test CP-C-3 [2]', 'IDE',
  'SALARIE'::type_contrat_applique_enum, 'TERMINEE',
  NOW() - INTERVAL '47 days', NOW() - INTERVAL '46 days',
  8, 25, 200, :soignant_id, 'SALARIE', 'CANDIDATURE',
  NOW() - INTERVAL '50 days'
);

SELECT public.fn_gerer_blocage_etabs() AS t2_result;

SELECT
  CASE WHEN (SELECT bloque_auto_le FROM public.etablissements WHERE id=:etab_id) IS NOT NULL THEN '[2.1] OK' ELSE '[2.1] FAIL' END AS t2_1_bloque,
  CASE WHEN (SELECT bloque_auto_raisons->>'paiements_retard_nb' FROM public.etablissements WHERE id=:etab_id) = '1' THEN '[2.2] OK' ELSE '[2.2] FAIL' END AS t2_2_raisons,
  CASE WHEN EXISTS (SELECT 1 FROM public.historique_blocages_etablissements WHERE etablissement_id=:etab_id AND action='BLOCAGE' AND cree_le > NOW() - INTERVAL '1 minute') THEN '[2.3] OK' ELSE '[2.3] FAIL' END AS t2_3_historique,
  CASE WHEN EXISTS (SELECT 1 FROM public.email_queue WHERE type='PUBLICATION_SUSPENDUE' AND destinataire_id=:etab_id AND statut='EN_ATTENTE' AND cree_le > NOW() - INTERVAL '1 minute') THEN '[2.4] OK' ELSE '[2.4] FAIL' END AS t2_4_email;

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Blocage étab avec facture commission >45j impayée
-- ------------------------------------------------------------
BEGIN;

UPDATE public.etablissements SET bloque_auto_le=NULL, bloque_auto_raisons=NULL WHERE id=:etab_id;
DELETE FROM public.factures WHERE numero_facture='TEST-C3-F3';

INSERT INTO public.factures (id, numero_facture, etablissement_id, montant_ht, montant_tva, montant_ttc, statut, date_emission, cree_le)
VALUES ('c3000002-0000-0000-0000-000000000003', 'TEST-C3-F3', :etab_id,
  125, 25, 150, 'EMISE', NOW() - INTERVAL '46 days', NOW() - INTERVAL '46 days');

SELECT public.fn_gerer_blocage_etabs() AS t3_result;

SELECT
  CASE WHEN (SELECT bloque_auto_le FROM public.etablissements WHERE id=:etab_id) IS NOT NULL THEN '[3.1] OK' ELSE '[3.1] FAIL' END AS t3_1,
  CASE WHEN (SELECT bloque_auto_raisons->>'factures_retard_nb' FROM public.etablissements WHERE id=:etab_id) = '1' THEN '[3.2] OK' ELSE '[3.2] FAIL' END AS t3_2;

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Idempotence — étab déjà bloqué
-- ------------------------------------------------------------
BEGIN;

UPDATE public.etablissements SET bloque_auto_le=NOW() - INTERVAL '1 day',
  bloque_auto_raisons='{"paiements_retard_nb":1}'::jsonb
WHERE id=:etab_id;

SELECT (public.fn_gerer_blocage_etabs())->>'blocages' AS t4_blocages;

-- Doit être 0 (étab déjà bloqué, pas re-bloqué)
SELECT CASE
  WHEN (SELECT COUNT(*) FROM public.historique_blocages_etablissements WHERE etablissement_id=:etab_id AND action='BLOCAGE' AND cree_le > NOW() - INTERVAL '1 minute') = 0
    THEN '[4.1] OK — pas de double blocage'
  ELSE '[4.1] FAIL'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [5] Déblocage auto après régularisation
-- ------------------------------------------------------------
BEGIN;

-- Étab pré-bloqué, 0 retard effectif
UPDATE public.etablissements SET bloque_auto_le=NOW() - INTERVAL '2 days',
  bloque_auto_raisons='{"paiements_retard_nb":1,"factures_retard_nb":0}'::jsonb
WHERE id=:etab_id;

SELECT (public.fn_gerer_blocage_etabs())->>'deblocages' AS t5_deblocages;

SELECT
  CASE WHEN (SELECT bloque_auto_le FROM public.etablissements WHERE id=:etab_id) IS NULL THEN '[5.1] OK' ELSE '[5.1] FAIL' END AS t5_1,
  CASE WHEN EXISTS (SELECT 1 FROM public.historique_blocages_etablissements WHERE etablissement_id=:etab_id AND action='DEBLOCAGE' AND cree_le > NOW() - INTERVAL '1 minute') THEN '[5.2] OK' ELSE '[5.2] FAIL' END AS t5_2,
  CASE WHEN EXISTS (SELECT 1 FROM public.email_queue WHERE type='PUBLICATION_REACTIVEE' AND destinataire_id=:etab_id AND statut='EN_ATTENTE' AND cree_le > NOW() - INTERVAL '1 minute') THEN '[5.3] OK' ELSE '[5.3] FAIL' END AS t5_3;

ROLLBACK;

-- ------------------------------------------------------------
-- [6] Étab SUSPENDU manuel exclu du blocage auto
-- ------------------------------------------------------------
BEGIN;

UPDATE public.etablissements SET statut_verification='SUSPENDU', bloque_auto_le=NULL WHERE id=:etab_id;

-- Création mission >45j
INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base, net_a_payer,
  soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'c3000003-0000-0000-0000-000000000006',
  :etab_id, 'Test CP-C-3 [6]', 'IDE',
  'SALARIE'::type_contrat_applique_enum, 'TERMINEE',
  NOW() - INTERVAL '47 days', NOW() - INTERVAL '46 days',
  8, 25, 200, :soignant_id, 'SALARIE', 'CANDIDATURE',
  NOW() - INTERVAL '50 days'
);

SELECT public.fn_gerer_blocage_etabs();

-- Vérifier : pas bloqué (filtre statut_verification='VERIFIE' exclut SUSPENDU)
SELECT CASE
  WHEN (SELECT bloque_auto_le FROM public.etablissements WHERE id=:etab_id) IS NULL
    THEN '[6.1] OK — SUSPENDU non bloqué par auto'
  ELSE '[6.1] FAIL'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [7] fn_creer_mission refuse si bloque_auto_le set
-- ------------------------------------------------------------
-- Nécessite contexte JWT étab, skip en automatique
-- (validation en checklist manuelle M3)
\echo '[7] À valider en checklist manuelle (contexte JWT étab requis)'

SET session_replication_role = 'origin';

\echo ''
\echo '== Fin tests CP-C-3 =='

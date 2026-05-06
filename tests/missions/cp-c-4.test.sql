-- ============================================================
-- Tests CP-C-4 — fn_auto_transitions_missions + statut EXPIREE
-- ============================================================
-- Prérequis : migrations 20260420190000/190001/190002 appliquées
-- Usage     : psql "$DB_URL" -f tests/missions/cp-c-4.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-C-4 — statut EXPIREE + transition auto =='

SET session_replication_role = 'replica';

\set etab_id '''8500dba5-2c73-4035-8383-b854d59a9864'''
\set soignant_id '''a2853e46-cd23-4526-befc-38f998353799'''

-- ------------------------------------------------------------
-- [1] Mission OUVERTE debut_le -2h → EXPIREE + candidature REFUSEE + notif
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'c4000001-0000-0000-0000-000000000001',
  :etab_id, 'Test CP-C-4 [1]', 'IDE', NULL, 'OUVERTE',
  NOW() - INTERVAL '3 hours', NOW() - INTERVAL '2 hours',
  1, 25, NULL, 'TOUS', 'CANDIDATURE', NOW() - INTERVAL '2 days'
);

INSERT INTO public.candidatures (id, mission_id, soignant_id, statut)
VALUES ('c4000001-1000-0000-0000-000000000001', 'c4000001-0000-0000-0000-000000000001', :soignant_id, 'EN_ATTENTE');

SELECT public.fn_auto_transitions_missions() AS r1;

SELECT
  CASE WHEN (SELECT statut FROM public.missions WHERE id='c4000001-0000-0000-0000-000000000001')::text = 'EXPIREE' THEN '[1.1] OK mission EXPIREE' ELSE '[1.1] FAIL' END,
  CASE WHEN (SELECT statut FROM public.candidatures WHERE id='c4000001-1000-0000-0000-000000000001') = 'REFUSEE' THEN '[1.2] OK candidature REFUSEE' ELSE '[1.2] FAIL' END,
  CASE WHEN EXISTS (SELECT 1 FROM public.notifications WHERE type='MISSION_NON_POURVUE' AND id_ressource='c4000001-0000-0000-0000-000000000001' AND cree_le > NOW() - INTERVAL '1 minute') THEN '[1.3] OK notification' ELSE '[1.3] FAIL' END;

ROLLBACK;

-- ------------------------------------------------------------
-- [2] Mission OUVERTE debut_le = NOW() → non expirée (seuil 1h pas atteint)
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'c4000002-0000-0000-0000-000000000002',
  :etab_id, 'Test CP-C-4 [2]', 'IDE', NULL, 'OUVERTE',
  NOW() + INTERVAL '1 hour', NOW() + INTERVAL '9 hours',
  8, 25, NULL, 'TOUS', 'CANDIDATURE', NOW()
);

SELECT public.fn_auto_transitions_missions();

SELECT CASE
  WHEN (SELECT statut FROM public.missions WHERE id='c4000002-0000-0000-0000-000000000002')::text = 'OUVERTE'
  THEN '[2.1] OK mission future reste OUVERTE'
  ELSE '[2.1] FAIL'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Mission ASSIGNEE (hors cible EXPIREE)
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'c4000003-0000-0000-0000-000000000003',
  :etab_id, 'Test CP-C-4 [3]', 'IDE', 'SALARIE'::type_contrat_applique_enum, 'ASSIGNEE',
  NOW() - INTERVAL '3 hours', NOW() - INTERVAL '2 hours',
  1, 25, :soignant_id, 'SALARIE', 'CANDIDATURE', NOW() - INTERVAL '2 days'
);

SELECT public.fn_auto_transitions_missions();

-- ASSIGNEE avec fin_le passée → TERMINEE (comportement existant, pas EXPIREE)
SELECT CASE
  WHEN (SELECT statut FROM public.missions WHERE id='c4000003-0000-0000-0000-000000000003')::text = 'TERMINEE'
  THEN '[3.1] OK ASSIGNEE -> TERMINEE (pas EXPIREE)'
  ELSE '[3.1] FAIL statut = ' || (SELECT statut::text FROM public.missions WHERE id='c4000003-0000-0000-0000-000000000003')
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Idempotence — mission déjà EXPIREE ne repasse pas par la boucle
-- ------------------------------------------------------------
BEGIN;

INSERT INTO public.missions (
  id, etablissement_id, intitule, profession_requise, type_contrat_applique,
  statut, debut_le, fin_le, duree_heures, taux_horaire_base,
  soignant_assigne_id, type_contrat_recherche, mode_attribution, cree_le
)
VALUES (
  'c4000004-0000-0000-0000-000000000004',
  :etab_id, 'Test CP-C-4 [4]', 'IDE', NULL, 'EXPIREE',
  NOW() - INTERVAL '5 hours', NOW() - INTERVAL '4 hours',
  1, 25, NULL, 'TOUS', 'CANDIDATURE', NOW() - INTERVAL '2 days'
);

SELECT (public.fn_auto_transitions_missions())->>'ouverte_to_expiree' AS ouverte_to_expiree;

-- Aucune nouvelle notification créée
SELECT CASE
  WHEN (SELECT COUNT(*) FROM public.notifications WHERE id_ressource='c4000004-0000-0000-0000-000000000004' AND cree_le > NOW() - INTERVAL '1 minute') = 0
  THEN '[4.1] OK pas de notif dupliquée'
  ELSE '[4.1] FAIL notif redondante'
END;

ROLLBACK;

SET session_replication_role = 'origin';

\echo ''
\echo '== Fin tests CP-C-4 =='

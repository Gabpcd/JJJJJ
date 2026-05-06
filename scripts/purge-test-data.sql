-- ============================================================
-- CP6 — Purge Test Data (dry-run par défaut)
-- ============================================================
-- Usage :
--   Dry-run (aucune suppression) :
--     psql "$DB_URL" -f scripts/purge-test-data.sql
--
--   Exécution réelle (DELETE) :
--     psql "$DB_URL" -v execute=1 -f scripts/purge-test-data.sql
--
-- Idempotent : ré-exécutable sans effet (détection = 0 après purge).
--
-- Critères de détection (test data) :
--   soignants      : id LIKE 'c0000000-%' OR email LIKE '%@demo.fr'
--                    OR email LIKE '%@test.com'
--   etablissements : id LIKE 'b0000000-%'
--                    OR siret IN ('11111111111111', '22222222222222',
--                                 '33333333333333', '44444444444444')
--   missions       : etablissement_id IN test_etabs
--   factures, créneaux, scans, etc. : en cascade depuis missions/factures
--
-- Comptes réels PRÉSERVÉS (liste blanche UUID) :
--   1b3bfd46-b4d5-4805-9c44-afd6dcf38b67 — Gabrielle Picard (t3@t4.com)
--   afac77e8-7572-4ca3-a237-df265d2a3366 — Gabrielle Picard (g@g.com)
--   a2853e46-cd23-4526-befc-38f998353799 — Gab P (b@b.com)
--   ca1a05eb-0775-4d77-bb76-7fb703ced019 — A B (b@l.com)
--   e1387da3-60b7-4e21-892b-6b5ce7e19d0a — NJ LK (jh@lk.com)
--   57d814fb-c09b-4528-b4e0-ed8369328bd3 — Gabrielle Picard (test@jolene.app)
--
-- Ordre de suppression (FK dependency, enfants avant parents) :
--   1. Enfants de factures_honoraires
--      (cessions_creance, chorus_submissions, factor_advances,
--       invoice_audit_log)
--   2. Enfants de missions & mission_creneaux
--      (scans_pointage, mission_creneaux, presences, reclamations,
--       reclamations_scoring, contrats_mission, candidatures,
--       evaluations, conversations, messages_mission,
--       cotisations_sociales, conformite_travail, assurances_mission,
--       calendar_events_sync, paiements_mission, paiements_soignant,
--       partages_rib, shift_affectations, stripe_transfers,
--       factures, factures_honoraires)
--   3. missions puis mission_series
--   4. Enfants soignants
--      (attestations_heures_externes, documents_soignants,
--       heures_externes, mandats_facturation_signatures,
--       pauses_presence, souscriptions_prevoyance,
--       stripe_connect_onboarding, suivi_conversion_3200h,
--       conversions_liberal)
--   5. soignants
--   6. Enfants etablissements
--      (api_keys, assurance_config, bfa_suivi, chorus_pro_config,
--       equipes, shifts)
--   7. etablissements
-- ============================================================

\set ON_ERROR_STOP on
\timing off

\echo ''
\echo '============================================================'
\echo 'CP6 — Purge Test Data'
\echo '============================================================'

-- ──────────────────────────────────────────────────────────────
-- 1. Détection (TEMP TABLES)
-- ──────────────────────────────────────────────────────────────
BEGIN;

CREATE TEMP TABLE _preserve_soignants (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _preserve_soignants VALUES
  ('1b3bfd46-b4d5-4805-9c44-afd6dcf38b67'),
  ('afac77e8-7572-4ca3-a237-df265d2a3366'),
  ('a2853e46-cd23-4526-befc-38f998353799'),
  ('ca1a05eb-0775-4d77-bb76-7fb703ced019'),
  ('e1387da3-60b7-4e21-892b-6b5ce7e19d0a'),
  ('57d814fb-c09b-4528-b4e0-ed8369328bd3');

CREATE TEMP TABLE _test_soignants (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _test_soignants
SELECT s.id
FROM soignants s
WHERE (
    s.id::text LIKE 'c0000000-%'
    OR s.email ILIKE '%@demo.fr'
    OR s.email ILIKE '%@test.com'
  )
  AND s.id NOT IN (SELECT id FROM _preserve_soignants);

CREATE TEMP TABLE _test_etablissements (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _test_etablissements
SELECT e.id
FROM etablissements e
WHERE e.id::text LIKE 'b0000000-%'
   OR e.siret IN ('11111111111111','22222222222222','33333333333333','44444444444444');

CREATE TEMP TABLE _test_missions (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _test_missions
SELECT m.id
FROM missions m
WHERE m.etablissement_id IN (SELECT id FROM _test_etablissements)
   OR m.soignant_assigne_id IN (SELECT id FROM _test_soignants);

CREATE TEMP TABLE _test_mission_creneaux (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _test_mission_creneaux
SELECT mc.id FROM mission_creneaux mc WHERE mc.mission_id IN (SELECT id FROM _test_missions);

CREATE TEMP TABLE _test_factures_honoraires (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _test_factures_honoraires
SELECT fh.id FROM factures_honoraires fh WHERE fh.mission_id IN (SELECT id FROM _test_missions);

CREATE TEMP TABLE _test_mission_series (id uuid PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO _test_mission_series
SELECT ms.id FROM mission_series ms WHERE ms.etablissement_id IN (SELECT id FROM _test_etablissements);

-- ──────────────────────────────────────────────────────────────
-- 2. Rapport détection (toujours affiché)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '── Rapport détection ──────────────────────────────────────'
SELECT 'soignants (test)'     AS ressource, (SELECT count(*) FROM _test_soignants)     AS nb_cibles
UNION ALL SELECT 'etablissements (test)',    (SELECT count(*) FROM _test_etablissements)
UNION ALL SELECT 'missions (test)',          (SELECT count(*) FROM _test_missions)
UNION ALL SELECT 'mission_creneaux (test)',  (SELECT count(*) FROM _test_mission_creneaux)
UNION ALL SELECT 'factures_honoraires (test)', (SELECT count(*) FROM _test_factures_honoraires)
UNION ALL SELECT 'mission_series (test)',    (SELECT count(*) FROM _test_mission_series);

\echo ''
\echo '── Conservés (liste blanche) ──────────────────────────────'
SELECT s.id, s.email, s.prenom, s.nom
FROM soignants s
JOIN _preserve_soignants p ON p.id = s.id
ORDER BY s.cree_le;

\echo ''
\echo '── Totaux base avant purge ───────────────────────────────'
SELECT 'soignants (total)'      AS ressource, count(*) AS n FROM soignants
UNION ALL SELECT 'etablissements (total)', count(*) FROM etablissements
UNION ALL SELECT 'missions (total)',       count(*) FROM missions
UNION ALL SELECT 'factures_honoraires (total)', count(*) FROM factures_honoraires
UNION ALL SELECT 'mission_creneaux (total)', count(*) FROM mission_creneaux
UNION ALL SELECT 'scans_pointage (total)', count(*) FROM scans_pointage
UNION ALL SELECT 'presences (total)',      count(*) FROM presences;

\echo ''
\echo '── Échantillons (5 missions cibles) ──────────────────────'
SELECT m.id, m.intitule, m.statut, m.etablissement_id, m.debut_le::date AS debut
FROM missions m
WHERE m.id IN (SELECT id FROM _test_missions)
ORDER BY m.debut_le
LIMIT 5;

\echo ''
\echo '── Échantillons (5 soignants cibles) ─────────────────────'
SELECT s.id, s.email, s.prenom, s.nom
FROM soignants s
WHERE s.id IN (SELECT id FROM _test_soignants)
ORDER BY s.cree_le
LIMIT 5;

-- ──────────────────────────────────────────────────────────────
-- 3. Exécution (si -v execute=1)
-- ──────────────────────────────────────────────────────────────
\if :{?execute}
\echo ''
\echo '============================================================'
\echo '>>> MODE EXÉCUTION — DELETE en cours'
\echo '============================================================'

-- Désactivation triggers USER (CP5a gel, CP3 facture lock, etc.)
ALTER TABLE public.scans_pointage      DISABLE TRIGGER USER;
ALTER TABLE public.mission_creneaux    DISABLE TRIGGER USER;
ALTER TABLE public.factures_honoraires DISABLE TRIGGER USER;
ALTER TABLE public.missions            DISABLE TRIGGER USER;
ALTER TABLE public.soignants           DISABLE TRIGGER USER;
ALTER TABLE public.etablissements      DISABLE TRIGGER USER;

-- ── 3.1. Enfants de factures_honoraires ──
DELETE FROM cessions_creance    WHERE facture_honoraire_id IN (SELECT id FROM _test_factures_honoraires);
DELETE FROM chorus_submissions  WHERE invoice_id           IN (SELECT id FROM _test_factures_honoraires);
DELETE FROM invoice_audit_log   WHERE invoice_id           IN (SELECT id FROM _test_factures_honoraires);

-- ── 3.2. Enfants de missions / mission_creneaux ──
DELETE FROM scans_pointage      WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM factor_advances     WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM mission_creneaux    WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM presences           WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM reclamations_scoring WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM reclamations        WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM litiges             WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM contrats_mission    WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM candidatures        WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM evaluations         WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM conversations       WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM messages_mission    WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM cotisations_sociales WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM conformite_travail  WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM assurances_mission  WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM calendar_events_sync WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM paiements_mission   WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM paiements_soignant  WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM partages_rib        WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM shift_affectations  WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM stripe_transfers    WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM factures            WHERE mission_id IN (SELECT id FROM _test_missions);
DELETE FROM factures_honoraires WHERE id         IN (SELECT id FROM _test_factures_honoraires);

-- ── 3.3. missions puis mission_series ──
DELETE FROM missions            WHERE id IN (SELECT id FROM _test_missions);
DELETE FROM mission_series      WHERE id IN (SELECT id FROM _test_mission_series);

-- ── 3.4. Enfants soignants (tables orphelines après missions) ──
DELETE FROM attestations_heures_externes  WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM documents_soignants           WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM heures_externes               WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM mandats_facturation_signatures WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM pauses_presence               WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM souscriptions_prevoyance      WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM stripe_connect_onboarding     WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM suivi_conversion_3200h        WHERE soignant_id IN (SELECT id FROM _test_soignants);
DELETE FROM conversions_liberal           WHERE soignant_id IN (SELECT id FROM _test_soignants);

-- ── 3.5. soignants ──
DELETE FROM soignants WHERE id IN (SELECT id FROM _test_soignants);

-- ── 3.6. Enfants etablissements ──
DELETE FROM api_keys         WHERE etablissement_id IN (SELECT id FROM _test_etablissements);
DELETE FROM assurance_config WHERE etablissement_id IN (SELECT id FROM _test_etablissements);
DELETE FROM bfa_suivi        WHERE etablissement_id IN (SELECT id FROM _test_etablissements);
DELETE FROM chorus_pro_config WHERE etablissement_id IN (SELECT id FROM _test_etablissements);
DELETE FROM equipes          WHERE etablissement_id IN (SELECT id FROM _test_etablissements);
DELETE FROM shifts           WHERE etablissement_id IN (SELECT id FROM _test_etablissements);

-- ── 3.7. etablissements ──
DELETE FROM etablissements WHERE id IN (SELECT id FROM _test_etablissements);

-- Réactivation triggers USER
ALTER TABLE public.scans_pointage      ENABLE TRIGGER USER;
ALTER TABLE public.mission_creneaux    ENABLE TRIGGER USER;
ALTER TABLE public.factures_honoraires ENABLE TRIGGER USER;
ALTER TABLE public.missions            ENABLE TRIGGER USER;
ALTER TABLE public.soignants           ENABLE TRIGGER USER;
ALTER TABLE public.etablissements      ENABLE TRIGGER USER;

\echo ''
\echo '── Totaux base après purge ───────────────────────────────'
SELECT 'soignants (total)'      AS ressource, count(*) AS n FROM soignants
UNION ALL SELECT 'etablissements (total)', count(*) FROM etablissements
UNION ALL SELECT 'missions (total)',       count(*) FROM missions
UNION ALL SELECT 'factures_honoraires (total)', count(*) FROM factures_honoraires
UNION ALL SELECT 'mission_creneaux (total)', count(*) FROM mission_creneaux
UNION ALL SELECT 'scans_pointage (total)', count(*) FROM scans_pointage
UNION ALL SELECT 'presences (total)',      count(*) FROM presences;

\echo ''
\echo '>>> Purge terminée. Commit en cours...'
COMMIT;

\else
\echo ''
\echo '============================================================'
\echo '>>> MODE DRY-RUN — aucune ligne supprimée'
\echo '>>> Pour exécuter : psql ... -v execute=1 -f scripts/purge-test-data.sql'
\echo '============================================================'
ROLLBACK;

\endif

\echo ''
\echo 'Fin CP6 purge-test-data.'

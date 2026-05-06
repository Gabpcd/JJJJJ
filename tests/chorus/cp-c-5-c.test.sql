-- ============================================================
-- Tests CP-C-5 C — sync-chorus-status (E15 Phase 2)
-- ============================================================
-- Prérequis : migrations 20260421120000 (CHECK CHORUS_* + cron)
--             + sync-chorus-status edge function déployée
-- Usage     : psql "$DB_URL" -f tests/chorus/cp-c-5-c.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-C-5 C — sync-chorus-status =='

-- [1] CHECK accepte les 5 types CHORUS_*
BEGIN;
SET session_replication_role = 'replica';

INSERT INTO public.notifications (id, destinataire_id, type, titre, corps, type_destinataire)
VALUES
  (gen_random_uuid(), gen_random_uuid(), 'CHORUS_DEPOSEE', 'Test', 'Corps', 'SOIGNANT'),
  (gen_random_uuid(), gen_random_uuid(), 'CHORUS_MISE_A_DISPOSITION', 'Test', 'Corps', 'ETABLISSEMENT'),
  (gen_random_uuid(), gen_random_uuid(), 'CHORUS_PAIEMENT_EN_COURS', 'Test', 'Corps', 'SOIGNANT'),
  (gen_random_uuid(), gen_random_uuid(), 'CHORUS_PAIEMENT_COMPTABILISE', 'Test', 'Corps', 'SOIGNANT'),
  (gen_random_uuid(), gen_random_uuid(), 'CHORUS_REJETEE', 'Test', 'Corps', 'ADMIN');

SELECT '[1.1] OK — 5 types CHORUS_* acceptés par CHECK' AS t1;

SET session_replication_role = 'origin';
ROLLBACK;

-- [1.2] Type inventé → CHECK violation (preuve filtrage)
BEGIN;
SET session_replication_role = 'replica';
DO $$
BEGIN
  BEGIN
    INSERT INTO public.notifications (id, destinataire_id, type, titre, corps, type_destinataire)
    VALUES (gen_random_uuid(), gen_random_uuid(), 'CHORUS_INVENTE', 'Test', 'Corps', 'SOIGNANT');
    RAISE EXCEPTION '[1.2] FAIL — CHECK devrait rejeter CHORUS_INVENTE';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '[1.2] OK — CHECK rejette CHORUS_INVENTE';
  END;
END $$;
SET session_replication_role = 'origin';
ROLLBACK;

-- [2] Anti-spam 24h : query de déduplication retourne bien les existants
BEGIN;
SET session_replication_role = 'replica';

\set etab_id '''8500dba5-2c73-4035-8383-b854d59a9864'''
\set soignant_id '''a2853e46-cd23-4526-befc-38f998353799'''
\set fh_id '''c5c00002-0000-0000-0000-000000000001'''

-- Notification récente (1h)
INSERT INTO public.notifications (id, destinataire_id, type, titre, corps, type_destinataire, type_ressource, id_ressource, cree_le)
VALUES (gen_random_uuid(), :soignant_id, 'CHORUS_DEPOSEE', 'Test', 'Corps', 'SOIGNANT', 'facture_honoraire', :fh_id, NOW() - INTERVAL '1 hour');

-- Query anti-spam (24h) : doit retourner 1 row
SELECT CASE
  WHEN (SELECT COUNT(*) FROM public.notifications
    WHERE type='CHORUS_DEPOSEE'
    AND id_ressource=:fh_id
    AND type_ressource='facture_honoraire'
    AND cree_le > NOW() - INTERVAL '24 hours'
  ) = 1
  THEN '[2.1] OK — anti-spam détecte notif récente (1h)'
  ELSE '[2.1] FAIL'
END;

SET session_replication_role = 'origin';
ROLLBACK;

-- [2.2] Notification ancienne (25h) : anti-spam ne la compte pas comme récente
BEGIN;
SET session_replication_role = 'replica';

INSERT INTO public.notifications (id, destinataire_id, type, titre, corps, type_destinataire, type_ressource, id_ressource, cree_le)
VALUES (gen_random_uuid(), '8500dba5-2c73-4035-8383-b854d59a9864', 'CHORUS_DEPOSEE', 'Test', 'Corps', 'SOIGNANT',
  'facture_honoraire', 'c5c00002-0000-0000-0000-000000000001', NOW() - INTERVAL '25 hours');

SELECT CASE
  WHEN (SELECT COUNT(*) FROM public.notifications
    WHERE type='CHORUS_DEPOSEE'
    AND id_ressource='c5c00002-0000-0000-0000-000000000001'
    AND type_ressource='facture_honoraire'
    AND cree_le > NOW() - INTERVAL '24 hours'
  ) = 0
  THEN '[2.2] OK — anti-spam ignore notif 25h (hors fenêtre)'
  ELSE '[2.2] FAIL'
END;

SET session_replication_role = 'origin';
ROLLBACK;

-- [3] Query éligibilité sync : filtre correctement sur status + last_checked_at
BEGIN;
SET session_replication_role = 'replica';

INSERT INTO public.chorus_submissions (id, invoice_id, submission_type, type_document, status, piste_request_id, last_checked_at)
VALUES
  ('c5c00003-0000-0000-0000-00000000000a', gen_random_uuid(), 'DEPOT_PDF_API', 'FACTURE', 'submitted', 'FLUX-A', NOW() - INTERVAL '2 hours'),
  ('c5c00003-0000-0000-0000-00000000000b', gen_random_uuid(), 'DEPOT_PDF_API', 'FACTURE', 'submitted', 'FLUX-B', NOW() - INTERVAL '30 minutes'),
  ('c5c00003-0000-0000-0000-00000000000c', gen_random_uuid(), 'DEPOT_PDF_API', 'FACTURE', 'accepted', 'FLUX-C', NOW() - INTERVAL '2 hours'),
  ('c5c00003-0000-0000-0000-00000000000d', gen_random_uuid(), 'DEPOT_PDF_API', 'FACTURE', 'pending', 'FLUX-D', NULL);

SELECT
  array_agg(id::text ORDER BY id) AS eligibles
FROM public.chorus_submissions
WHERE status IN ('pending', 'submitted')
AND piste_request_id IS NOT NULL
AND (last_checked_at IS NULL OR last_checked_at < NOW() - INTERVAL '1 hour')
AND id::text LIKE 'c5c00003%';

-- Attendu : [A (2h), D (NULL)] — B (30 min) et C (accepted) exclus

SELECT CASE
  WHEN (
    SELECT COUNT(*) FROM public.chorus_submissions
    WHERE status IN ('pending', 'submitted')
    AND piste_request_id IS NOT NULL
    AND (last_checked_at IS NULL OR last_checked_at < NOW() - INTERVAL '1 hour')
    AND id::text LIKE 'c5c00003%'
  ) = 2
  THEN '[3.1] OK — query éligibilité retourne A + D (2 rows)'
  ELSE '[3.1] FAIL'
END;

SET session_replication_role = 'origin';
ROLLBACK;

-- [5] Cron actif
SELECT CASE
  WHEN EXISTS (SELECT 1 FROM cron.job WHERE jobname='sync-chorus-status-hourly' AND active=TRUE)
  THEN '[5.1] OK — cron sync-chorus-status-hourly actif'
  ELSE '[5.1] FAIL'
END;

SELECT CASE
  WHEN (SELECT schedule FROM cron.job WHERE jobname='sync-chorus-status-hourly') = '0 7-22/2 * * *'
  THEN '[5.2] OK — schedule 0 7-22/2 * * *'
  ELSE '[5.2] FAIL'
END;

\echo ''
\echo '== Fin tests CP-C-5 C =='

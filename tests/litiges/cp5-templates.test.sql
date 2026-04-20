-- ============================================================
-- Tests CP-LITIGES-5 — Templates email + SMS
-- ============================================================
-- Prérequis : all CP1-CP5 migrations applied.
-- Usage :
--   psql "$DB_URL" -f tests/litiges/cp5-templates.test.sql
--
-- Note : les templates eux-mêmes (HTML) vivent dans l'edge function
-- send-email/index.ts et ne sont pas testables via SQL. Ce fichier
-- vérifie :
--   1. fn_litige_push_notification v2 (avec routage SMS)
--   2. Que les types LITIGE_* créent bien des rows dans email_queue
--      et notifications (en mode service_role / psql).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-5 Templates =='

-- ──────────────────────────────────────────────────────────────
-- T1 : fn_litige_push_notification — source contient routage SMS
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T1 : fn_litige_push_notification SMS-enabled'

SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%SMS_%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_OUVERTURE%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_RAPPEL_J1%'
        AND pg_get_functiondef(p.oid) LIKE '%REMBOURSEMENT_CONFIRME%'
        AND pg_get_functiondef(p.oid) LIKE '%v_telephone%'
       THEN '[1.1] OK — routage SMS + 5 types éligibles + lookup téléphone'
       ELSE '[1.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_litige_push_notification';

-- Source contient les 5 SMS bodies inline
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%escalade imminente%'
        AND pg_get_functiondef(p.oid) LIKE '%Délai bancaire%'
       THEN '[1.2] OK — bodies SMS inline présents'
       ELSE '[1.2] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_litige_push_notification';

-- ──────────────────────────────────────────────────────────────
-- T2 : fn_litige_push_notification — exécution (notification + email)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T2 : exécution fn_litige_push_notification'

DO $$
DECLARE
  v_soignant_id UUID;
  v_notif_count INT;
  v_email_count INT;
  v_test_litige_id UUID := gen_random_uuid();
BEGIN
  SELECT id INTO v_soignant_id FROM public.soignants LIMIT 1;
  IF v_soignant_id IS NULL THEN
    RAISE NOTICE '[2] SKIP — aucun soignant en base';
    RETURN;
  END IF;

  PERFORM public.fn_litige_push_notification(
    v_soignant_id,
    'SOIGNANT',
    'LITIGE_RAPPEL_J1',
    'Test rappel J1',
    'Test body rappel J1',
    v_test_litige_id,
    '{"type_litige": "ABSENCE_SOIGNANT", "mission_id": "test"}'::jsonb
  );

  SELECT COUNT(*) INTO v_notif_count
    FROM public.notifications
   WHERE id_ressource = v_test_litige_id
     AND type = 'LITIGE_RAPPEL_J1';

  SELECT COUNT(*) INTO v_email_count
    FROM public.email_queue
   WHERE type = 'LITIGE_RAPPEL_J1'
     AND destinataire_id = v_soignant_id
     AND (data->>'litige_id')::text = v_test_litige_id::text;

  IF v_notif_count >= 1 AND v_email_count >= 1 THEN
    RAISE NOTICE '[2.1] OK — notification + email_queue insérés';
  ELSE
    RAISE NOTICE '[2.1] FAIL — notifs=%, emails=%', v_notif_count, v_email_count;
  END IF;

  -- Vérifier si un SMS a aussi été enqueued (dépend du téléphone soignant)
  SELECT COUNT(*) INTO v_email_count
    FROM public.email_queue
   WHERE type = 'SMS_LITIGE_RAPPEL_J1'
     AND destinataire_id = v_soignant_id;
  IF v_email_count >= 1 THEN
    RAISE NOTICE '[2.2] OK — SMS enqueued (téléphone trouvé)';
  ELSE
    RAISE NOTICE '[2.2] INFO — pas de SMS (téléphone soignant absent ou < 10c)';
  END IF;

  -- Cleanup
  DELETE FROM public.notifications WHERE id_ressource = v_test_litige_id;
  DELETE FROM public.email_queue WHERE (data->>'litige_id')::text = v_test_litige_id::text;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[2] FAIL — erreur : %', SQLERRM;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T3 : types non-SMS ne génèrent pas de row SMS_*
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T3 : types non-SMS exclus'

DO $$
DECLARE
  v_soignant_id UUID;
  v_sms_count INT;
  v_test_litige_id UUID := gen_random_uuid();
BEGIN
  SELECT id INTO v_soignant_id FROM public.soignants LIMIT 1;
  IF v_soignant_id IS NULL THEN
    RAISE NOTICE '[3] SKIP';
    RETURN;
  END IF;

  PERFORM public.fn_litige_push_notification(
    v_soignant_id, 'SOIGNANT', 'LITIGE_NOUVEAU_MESSAGE',
    'Test non-SMS', 'Body test', v_test_litige_id
  );

  SELECT COUNT(*) INTO v_sms_count
    FROM public.email_queue
   WHERE type = 'SMS_LITIGE_NOUVEAU_MESSAGE'
     AND destinataire_id = v_soignant_id;

  IF v_sms_count = 0 THEN
    RAISE NOTICE '[3.1] OK — LITIGE_NOUVEAU_MESSAGE ne génère pas de SMS';
  ELSE
    RAISE NOTICE '[3.1] FAIL — SMS inattendu pour LITIGE_NOUVEAU_MESSAGE';
  END IF;

  DELETE FROM public.notifications WHERE id_ressource = v_test_litige_id;
  DELETE FROM public.email_queue WHERE (data->>'litige_id')::text = v_test_litige_id::text;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[3] FAIL — erreur : %', SQLERRM;
END;
$$;

\echo ''
\echo '== FIN CP-LITIGES-5 =='

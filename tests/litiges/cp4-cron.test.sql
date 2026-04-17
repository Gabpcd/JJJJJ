-- ============================================================
-- Tests CP-LITIGES-4 — Cron escalade + auto-création
-- ============================================================
-- Prérequis : migrations CP1/2/3 + fixes CP2 + CP4 (20260417130400).
-- Usage :
--   psql "$DB_URL" -f tests/litiges/cp4-cron.test.sql
--
-- Tests comportementaux complets (E2E avec données admin) en CP-LITIGES-8.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-4 Cron =='

-- ──────────────────────────────────────────────────────────────
-- T1 : fn_list_admin_user_ids (helper interne)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T1 : fn_list_admin_user_ids'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[1.1] OK — fonction présente'
       ELSE '[1.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_list_admin_user_ids';

-- Exécute la fonction (pas d'erreur même si aucun admin)
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM public.fn_list_admin_user_ids();
  RAISE NOTICE '[1.2] OK — fonction exécutable (% admins trouvés)', v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[1.2] FAIL — erreur : %', SQLERRM;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T2 : fn_litige_push_notification
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T2 : fn_litige_push_notification'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[2.1] OK — fonction présente'
       ELSE '[2.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_litige_push_notification';

-- Source contient les 2 INSERT (notifications + email_queue)
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%INSERT INTO public.notifications%'
        AND pg_get_functiondef(p.oid) LIKE '%INSERT INTO public.email_queue%'
       THEN '[2.2] OK — INSERT dans notifications + email_queue'
       ELSE '[2.2] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_litige_push_notification';

-- ──────────────────────────────────────────────────────────────
-- T3 : fn_litiges_escalader_auto
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T3 : fn_litiges_escalader_auto'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[3.1] OK — fonction présente'
       ELSE '[3.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_litiges_escalader_auto';

-- Source : lit paramètres + check salarié + appelle fn_ajouter_jours_ouvres
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%delai_escalade_liberal_h%'
        AND pg_get_functiondef(p.oid) LIKE '%delai_escalade_salarie_jours_ouvres%'
        AND pg_get_functiondef(p.oid) LIKE '%fn_ajouter_jours_ouvres%'
        AND pg_get_functiondef(p.oid) LIKE '%EN_MEDIATION%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_ESCALADE_AUTO%'
       THEN '[3.2] OK — logique complète (params + salarié + audit)'
       ELSE '[3.2] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_litiges_escalader_auto';

-- Exécute la fonction sur la base (aucun litige éligible → escalades=0)
DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_litiges_escalader_auto();
  IF v_result ? 'escalades' THEN
    RAISE NOTICE '[3.3] OK — exécution réussie (escalades=%)', v_result->>'escalades';
  ELSE
    RAISE NOTICE '[3.3] FAIL — réponse inattendue : %', v_result;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[3.3] FAIL — erreur : %', SQLERRM;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T4 : fn_auto_creation_litiges_presence
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T4 : fn_auto_creation_litiges_presence'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[4.1] OK — fonction présente'
       ELSE '[4.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_auto_creation_litiges_presence';

-- Source : check motif_litige + heures_reelles=0 + NOT EXISTS litige
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%motif_litige IS NOT NULL%'
        AND pg_get_functiondef(p.oid) LIKE '%heures_reelles IS NULL OR p.heures_reelles = 0%'
        AND pg_get_functiondef(p.oid) LIKE '%ABSENCE_SOIGNANT%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_AUTO_CREATION%'
       THEN '[4.2] OK — conditions + audit présents'
       ELSE '[4.2] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_auto_creation_litiges_presence';

-- Exécute
DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_auto_creation_litiges_presence();
  IF v_result ? 'litiges_crees' THEN
    RAISE NOTICE '[4.3] OK — exécution (litiges_crees=%)', v_result->>'litiges_crees';
  ELSE
    RAISE NOTICE '[4.3] FAIL — réponse inattendue : %', v_result;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[4.3] FAIL — erreur : %', SQLERRM;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T5 : fn_envoyer_rappels_litiges
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T5 : fn_envoyer_rappels_litiges'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[5.1] OK — fonction présente'
       ELSE '[5.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_envoyer_rappels_litiges';

-- Source : 3 paliers + idempotence
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%J+1%'
        AND pg_get_functiondef(p.oid) LIKE '%J+3%'
        AND pg_get_functiondef(p.oid) LIKE '%J+5%'
        AND pg_get_functiondef(p.oid) LIKE '%derniers_rappels_envoyes%'
       THEN '[5.2] OK — 3 paliers + idempotence'
       ELSE '[5.2] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_envoyer_rappels_litiges';

DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_envoyer_rappels_litiges();
  IF v_result ? 'rappels_envoyes' THEN
    RAISE NOTICE '[5.3] OK — exécution (rappels_envoyes=%)', v_result->>'rappels_envoyes';
  ELSE
    RAISE NOTICE '[5.3] FAIL';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[5.3] FAIL — erreur : %', SQLERRM;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T6 : fn_alerter_mediation_prioritaire
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T6 : fn_alerter_mediation_prioritaire'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[6.1] OK — fonction présente'
       ELSE '[6.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_alerter_mediation_prioritaire';

-- Source : check EN_MEDIATION + > 7j + MEDIATION_7J idempotence
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%EN_MEDIATION%'
        AND pg_get_functiondef(p.oid) LIKE '%delai_mediation_alerte_prioritaire_j%'
        AND pg_get_functiondef(p.oid) LIKE '%MEDIATION_7J%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_MEDIATION_PRIORITAIRE%'
       THEN '[6.2] OK — conditions + idempotence + type notif'
       ELSE '[6.2] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_alerter_mediation_prioritaire';

DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_alerter_mediation_prioritaire();
  IF v_result ? 'alertes_mediation' THEN
    RAISE NOTICE '[6.3] OK — exécution (alertes_mediation=%)', v_result->>'alertes_mediation';
  ELSE
    RAISE NOTICE '[6.3] FAIL';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[6.3] FAIL — erreur : %', SQLERRM;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T7 : grants service_role (pas authenticated, ce sont des crons)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T7 : grants service_role'

SELECT
  CASE WHEN COUNT(*) = 4 THEN '[7] OK — 4 RPCs cron granted à service_role'
       ELSE '[7] FAIL — ' || COUNT(*) END
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'fn_litiges_escalader_auto',
    'fn_auto_creation_litiges_presence',
    'fn_envoyer_rappels_litiges',
    'fn_alerter_mediation_prioritaire'
  )
  AND privilege_type = 'EXECUTE'
  AND grantee = 'service_role';

\echo ''
\echo '== FIN CP-LITIGES-4 =='

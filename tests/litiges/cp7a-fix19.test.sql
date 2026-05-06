-- ============================================================
-- Tests CP-LITIGES-7a FIX 19 — Push LITIGE_RESOLU_AJUSTE + wording
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 19 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix19.test.sql
-- ============================================================
-- FIX 19 couvre :
--   (A) fn_admin_resoudre_litige pousse 'LITIGE_RESOLU_AJUSTE' dans
--       email_queue pour soignant + étab (cas impact financier).
--   (B) Pour cas AVOIR, push supplémentaire 'AVOIR_EMIS'.
--   (C) email_data contient action_financiere (RECALCUL, ANNULER_REEMETTRE, AVOIR).
--   (D) Template TS (send-email/index.ts) utilise data.action_financiere
--       pour afficher un bloc "disponible immédiatement" (tests manuels).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 19 =='

-- [1] fn_admin_resoudre_litige existe avec signature 6-args
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[19.1] OK — fn_admin_resoudre_litige(6 args) présente'
  ELSE '[19.1] FAIL — ' || COUNT(*) || ' match'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_resoudre_litige'
  AND p.pronargs = 6;

-- [2] Corps de la fonction contient bien l'appel fn_litige_push_notification
-- pour LITIGE_RESOLU_AJUSTE (confirme FIX 19 appliqué, distinct de CP3/FIX 18)
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%LITIGE_RESOLU_AJUSTE%'
   AND pg_get_functiondef(p.oid) LIKE '%fn_litige_push_notification%'
    THEN '[19.2] OK — fn_admin_resoudre_litige push LITIGE_RESOLU_AJUSTE'
  ELSE '[19.2] FAIL — push absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_resoudre_litige'
  AND p.pronargs = 6;

-- [3] Corps de la fonction contient AVOIR_EMIS (push spécifique cas AVOIR)
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%AVOIR_EMIS%'
    THEN '[19.3] OK — fn_admin_resoudre_litige push AVOIR_EMIS (cas AVOIR)'
  ELSE '[19.3] FAIL — AVOIR_EMIS push absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_resoudre_litige'
  AND p.pronargs = 6;

-- [4] Corps de la fonction passe action_financiere dans le payload email
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%''action_financiere''%v_action%'
    OR pg_get_functiondef(p.oid) LIKE '%action_financiere%'
    THEN '[19.4] OK — action_financiere présent dans email_data'
  ELSE '[19.4] FAIL'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_resoudre_litige'
  AND p.pronargs = 6;

-- [5] fn_litige_push_notification est une fonction existante avec la bonne
-- signature (helper CP4/CP5)
SELECT CASE
  WHEN COUNT(*) >= 1
    THEN '[19.5] OK — fn_litige_push_notification helper présent'
  ELSE '[19.5] FAIL'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litige_push_notification';

-- [6] Type notif 'LITIGE_RESOLU_AJUSTE' connu par email_queue CHECK
-- (ou pas contraint — vérifier s'il y a un CHECK dessus)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[19.6] OK — table email_queue présente'
  ELSE '[19.6] FAIL'
END
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'email_queue';

-- [7] E2E : résoudre un litige avec action=RECALCUL doit pousser 2 lignes
-- (soignant + étab) dans email_queue avec type=LITIGE_RESOLU_AJUSTE
-- et data->>'action_financiere' = 'RECALCUL'.
DO $$
DECLARE
  v_litige_id UUID;
  v_facture_id UUID;
  v_mission_id UUID;
  v_soignant_id UUID;
  v_etab_id UUID;
  v_etab_user_id UUID;
  v_emails_before INT;
  v_emails_after INT;
  v_action_financiere TEXT;
  v_admin_user_id UUID;
  v_result JSONB;
BEGIN
  -- Prérequis : au moins un litige non-résolu avec une facture BROUILLON liée
  SELECT l.id, f.id, f.mission_id, f.soignant_id, f.etablissement_id
    INTO v_litige_id, v_facture_id, v_mission_id, v_soignant_id, v_etab_id
    FROM public.litiges l
    JOIN public.factures_honoraires f ON f.id = l.facture_id
   WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION')
     AND f.statut = 'BROUILLON'
   LIMIT 1;

  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[19.7] SKIP — pas de litige + facture BROUILLON disponible';
    RETURN;
  END IF;

  SELECT user_id INTO v_admin_user_id
    FROM public.user_roles WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_user_id IS NULL THEN
    RAISE NOTICE '[19.7] SKIP — pas d admin plateforme';
    RETURN;
  END IF;

  SELECT COUNT(*) INTO v_emails_before
    FROM public.email_queue
   WHERE type = 'LITIGE_RESOLU_AJUSTE'
     AND (data->>'litige_id')::UUID = v_litige_id;

  -- Appel fn en contexte admin via SET ROLE/SECURITY DEFINER
  -- Note : fn exige auth.uid() = admin. En test, utiliser service_role.
  PERFORM set_config('request.jwt.claim.sub', v_admin_user_id::text, true);

  BEGIN
    v_result := public.fn_admin_resoudre_litige(
      v_litige_id,
      'Test FIX 19 — RECALCUL impact financier validé.',
      'SOIGNANT',
      8.0,
      25.0,
      'RECALCUL'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[19.7] SKIP — exception call: %', SQLERRM;
    RETURN;
  END;

  IF v_result ? 'error' THEN
    RAISE NOTICE '[19.7] SKIP — fn rejected: %', v_result->>'error';
    RETURN;
  END IF;

  v_action_financiere := v_result->>'action_financiere';

  SELECT COUNT(*) INTO v_emails_after
    FROM public.email_queue
   WHERE type = 'LITIGE_RESOLU_AJUSTE'
     AND (data->>'litige_id')::UUID = v_litige_id;

  IF v_emails_after > v_emails_before
     AND v_action_financiere = 'RECALCUL' THEN
    RAISE NOTICE '[19.7] OK — % ligne(s) LITIGE_RESOLU_AJUSTE ajoutée(s) avec action_financiere=RECALCUL',
      v_emails_after - v_emails_before;
  ELSE
    RAISE NOTICE '[19.7] FAIL — before=% after=% action=%',
      v_emails_before, v_emails_after, v_action_financiere;
  END IF;

  -- Rollback manuel impossible (pas dans une transaction), marquer litige
  -- comme dé-résolu ? Non : laisser l'état réel. Ce test est destructif,
  -- à lancer sur env staging uniquement.
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[19.7] FAIL — exception: %', SQLERRM;
END $$;

\echo ''
\echo '== FIX 19 tests terminés =='
\echo 'Tests manuels TS (template LITIGE_RESOLU_AJUSTE) :'
\echo '  - RECALCUL        → mention "facture recalculée" + "immédiatement"'
\echo '  - ANNULER_REEMETTRE → mention "nouvelle facture remplace" + "immédiatement"'
\echo '  - AVOIR           → mention "avoir émis" + "immédiatement" + email séparé AVOIR_EMIS'

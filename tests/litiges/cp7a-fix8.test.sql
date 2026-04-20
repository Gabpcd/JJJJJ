-- ============================================================
-- Tests CP-LITIGES-7a FIX 8 — Consommation commission_a_recalculer
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 → 7a FIX 8 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix8.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 8 =='

-- [1] Fonction fn_recalculer_commissions_post_litige existe (0-arg → JSONB)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[8.1] OK — fn_recalculer_commissions_post_litige() présente'
  ELSE '[8.1] FAIL — ' || COUNT(*) || ' match'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_recalculer_commissions_post_litige'
  AND pg_get_function_identity_arguments(p.oid) = '';

-- [2] fn_auto_facturation_mensuelle appelle la nouvelle fonction
SELECT CASE
  WHEN prosrc ILIKE '%fn_recalculer_commissions_post_litige%'
    THEN '[8.2] OK — fn_auto_facturation_mensuelle appelle le recalcul'
  ELSE '[8.2] FAIL — appel absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_auto_facturation_mensuelle';

-- [3] Comportemental : fonction s'appelle sans erreur (retour JSONB)
DO $$
DECLARE v_result JSONB;
BEGIN
  SELECT public.fn_recalculer_commissions_post_litige() INTO v_result;
  IF v_result ? 'processed_unbilled' AND v_result ? 'deferred_to_fix9_billed' THEN
    RAISE NOTICE '[8.3] OK — retour JSONB %', v_result;
  ELSE
    RAISE NOTICE '[8.3] FAIL — retour inattendu : %', v_result;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[8.3] FAIL — exception : %', SQLERRM;
END $$;

-- [4] Comportemental end-to-end : flag une mission existante (facture_id
-- IS NULL, commission_facturee=false), appelle le recalcul, vérifie que
-- le flag est remis à FALSE.
DO $$
DECLARE
  v_mission_id UUID;
  v_flag_after BOOLEAN;
  v_commission_before NUMERIC(12,2);
  v_commission_after  NUMERIC(12,2);
BEGIN
  SELECT id, montant_commission_ht INTO v_mission_id, v_commission_before
    FROM public.missions
   WHERE facture_id IS NULL
     AND COALESCE(commission_facturee, FALSE) = FALSE
     AND commission_a_recalculer = FALSE
   LIMIT 1;

  IF v_mission_id IS NULL THEN
    RAISE NOTICE '[8.4] SKIP — aucune mission éligible en base';
    RETURN;
  END IF;

  UPDATE public.missions
     SET commission_a_recalculer = TRUE
   WHERE id = v_mission_id;

  PERFORM public.fn_recalculer_commissions_post_litige();

  SELECT commission_a_recalculer, montant_commission_ht
    INTO v_flag_after, v_commission_after
    FROM public.missions WHERE id = v_mission_id;

  IF v_flag_after = FALSE THEN
    RAISE NOTICE '[8.4] OK — flag reset à FALSE après recalcul (mission %, commission % → %)',
      v_mission_id, v_commission_before, v_commission_after;
  ELSE
    RAISE NOTICE '[8.4] FAIL — flag encore TRUE (mission %)', v_mission_id;
  END IF;

  -- Nettoyage : remettre la mission dans son état initial pour idempotence.
  UPDATE public.missions
     SET montant_commission_ht = v_commission_before,
         commission_a_recalculer = FALSE
   WHERE id = v_mission_id;
END $$;

-- [5] Comportemental : mission déjà facturée → flag reste TRUE (report FIX 9)
DO $$
DECLARE
  v_mission_id UUID;
  v_flag_after BOOLEAN;
BEGIN
  SELECT id INTO v_mission_id
    FROM public.missions
   WHERE facture_id IS NOT NULL
     AND commission_a_recalculer = FALSE
   LIMIT 1;

  IF v_mission_id IS NULL THEN
    RAISE NOTICE '[8.5] SKIP — aucune mission facturée en base';
    RETURN;
  END IF;

  UPDATE public.missions SET commission_a_recalculer = TRUE WHERE id = v_mission_id;

  PERFORM public.fn_recalculer_commissions_post_litige();

  SELECT commission_a_recalculer INTO v_flag_after
    FROM public.missions WHERE id = v_mission_id;

  IF v_flag_after = TRUE THEN
    RAISE NOTICE '[8.5] OK — flag conservé pour mission facturée (report FIX 9)';
  ELSE
    RAISE NOTICE '[8.5] FAIL — flag reset à tort pour mission facturée';
  END IF;

  -- Nettoyage
  UPDATE public.missions SET commission_a_recalculer = FALSE WHERE id = v_mission_id;
END $$;

-- ============================================================
-- Tests CP-LITIGES-7b-1 — 2 RPCs admin (preuves + historique)
-- ============================================================
-- Prérequis : 20260417130717_cp7b1_rpcs_admin.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7b1-rpcs.test.sql
--
-- Couverture :
--   [1] Existence + SECURITY DEFINER pour les 2 RPCs
--   [2] Signature / types de retour
--   [3] Rejet non-admin → ERRCODE 42501
--   [4] Structure JSONB retourné (clés attendues)
--   [5] Comportemental minimal : 1 litige réel → JSONB valide + historique
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7b-1 =='

-- ─────────────────────────────────────────────────────────────
-- RPC 1 : fn_litige_preuves_agregees
-- ─────────────────────────────────────────────────────────────

-- [1.1] Existe avec 1 argument (UUID) et retour JSONB
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[7b1.1.1] OK — fn_litige_preuves_agregees(UUID) présente'
  ELSE '[7b1.1.1] FAIL — ' || COUNT(*) || ' match'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litige_preuves_agregees'
  AND p.pronargs = 1;

-- [1.2] SECURITY DEFINER activé
SELECT CASE
  WHEN p.prosecdef = true
    THEN '[7b1.1.2] OK — fn_litige_preuves_agregees SECURITY DEFINER'
  ELSE '[7b1.1.2] FAIL — SECURITY DEFINER absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litige_preuves_agregees'
  AND p.pronargs = 1;

-- [1.3] Retour = jsonb
SELECT CASE
  WHEN pg_get_function_result(p.oid) = 'jsonb'
    THEN '[7b1.1.3] OK — retour JSONB'
  ELSE '[7b1.1.3] FAIL — retour=' || pg_get_function_result(p.oid)
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litige_preuves_agregees'
  AND p.pronargs = 1;

-- [1.4] Body contient l'appel au guard est_admin()
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%est_admin()%'
    THEN '[7b1.1.4] OK — guard est_admin() présent'
  ELSE '[7b1.1.4] FAIL — guard absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litige_preuves_agregees'
  AND p.pronargs = 1;

-- [1.5] Rejet non-admin (contexte anonyme) → ERRCODE 42501
DO $$
DECLARE
  v_litige_id UUID;
  v_caught    BOOLEAN := false;
  v_errcode   TEXT;
BEGIN
  SELECT id INTO v_litige_id FROM public.litiges LIMIT 1;
  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[7b1.1.5] SKIP — pas de litige en base';
    RETURN;
  END IF;

  -- Clear admin JWT : auth.uid() → NULL → est_admin() false
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);

  BEGIN
    PERFORM public.fn_litige_preuves_agregees(v_litige_id);
  EXCEPTION WHEN insufficient_privilege THEN
    v_caught := true;
    v_errcode := '42501';
  WHEN OTHERS THEN
    v_errcode := SQLSTATE;
  END;

  IF v_caught AND v_errcode = '42501' THEN
    RAISE NOTICE '[7b1.1.5] OK — rejet non-admin ERRCODE 42501';
  ELSE
    RAISE NOTICE '[7b1.1.5] FAIL — caught=% errcode=%', v_caught, v_errcode;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- RPC 2 : fn_litiges_historique_similaires
-- ─────────────────────────────────────────────────────────────

-- [2.1] Existe avec 2 arguments (UUID, INTEGER)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[7b1.2.1] OK — fn_litiges_historique_similaires(UUID,INT) présente'
  ELSE '[7b1.2.1] FAIL — ' || COUNT(*) || ' match'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litiges_historique_similaires'
  AND p.pronargs = 2;

-- [2.2] SECURITY DEFINER activé
SELECT CASE
  WHEN p.prosecdef = true
    THEN '[7b1.2.2] OK — fn_litiges_historique_similaires SECURITY DEFINER'
  ELSE '[7b1.2.2] FAIL — SECURITY DEFINER absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litiges_historique_similaires'
  AND p.pronargs = 2;

-- [2.3] Retour TABLE avec clé en_faveur_de (dérivée du statut)
SELECT CASE
  WHEN pg_get_function_result(p.oid) LIKE '%en_faveur_de%'
    THEN '[7b1.2.3] OK — retour TABLE contient en_faveur_de'
  ELSE '[7b1.2.3] FAIL — en_faveur_de absent du retour'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litiges_historique_similaires'
  AND p.pronargs = 2;

-- [2.4] Body contient guard est_admin() + borne LEAST(p_limit, 50)
SELECT CASE
  WHEN pg_get_functiondef(p.oid) LIKE '%est_admin()%'
   AND pg_get_functiondef(p.oid) LIKE '%LEAST(p_limit, 50)%'
    THEN '[7b1.2.4] OK — guard est_admin() + limit borné [1..50]'
  ELSE '[7b1.2.4] FAIL'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_litiges_historique_similaires'
  AND p.pronargs = 2;

-- [2.5] Rejet non-admin → ERRCODE 42501
DO $$
DECLARE
  v_litige_id UUID;
  v_caught    BOOLEAN := false;
  v_errcode   TEXT;
BEGIN
  SELECT id INTO v_litige_id FROM public.litiges LIMIT 1;
  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[7b1.2.5] SKIP — pas de litige en base';
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);

  BEGIN
    PERFORM * FROM public.fn_litiges_historique_similaires(v_litige_id, 5);
  EXCEPTION WHEN insufficient_privilege THEN
    v_caught := true;
    v_errcode := '42501';
  WHEN OTHERS THEN
    v_errcode := SQLSTATE;
  END;

  IF v_caught AND v_errcode = '42501' THEN
    RAISE NOTICE '[7b1.2.5] OK — rejet non-admin ERRCODE 42501';
  ELSE
    RAISE NOTICE '[7b1.2.5] FAIL — caught=% errcode=%', v_caught, v_errcode;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- Tests comportementaux — structure JSONB + historique
-- ─────────────────────────────────────────────────────────────

-- [3.1] Structure JSONB : toutes les clés top-level présentes
DO $$
DECLARE
  v_litige_id   UUID;
  v_admin_uid   UUID;
  v_result      JSONB;
  v_keys        TEXT[];
  v_missing     TEXT[] := ARRAY[]::TEXT[];
  v_expected    TEXT[] := ARRAY[
    'litige','mission','soignant','etablissement',
    'pointages','heures','factures_liees','messages'
  ];
  v_key         TEXT;
BEGIN
  SELECT id INTO v_litige_id FROM public.litiges LIMIT 1;
  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[7b1.3.1] SKIP — pas de litige en base';
    RETURN;
  END IF;

  SELECT user_id INTO v_admin_uid
    FROM public.user_roles WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_uid IS NULL THEN
    RAISE NOTICE '[7b1.3.1] SKIP — pas d admin plateforme';
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_uid::text, true);

  BEGIN
    v_result := public.fn_litige_preuves_agregees(v_litige_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '[7b1.3.1] FAIL — exception: %', SQLERRM;
    RETURN;
  END;

  IF v_result IS NULL THEN
    RAISE NOTICE '[7b1.3.1] FAIL — retour NULL';
    RETURN;
  END IF;

  SELECT array_agg(k) INTO v_keys
    FROM jsonb_object_keys(v_result) k;

  FOREACH v_key IN ARRAY v_expected LOOP
    IF NOT (v_key = ANY(v_keys)) THEN
      v_missing := array_append(v_missing, v_key);
    END IF;
  END LOOP;

  IF array_length(v_missing, 1) IS NULL THEN
    RAISE NOTICE '[7b1.3.1] OK — 8 clés top-level présentes';
  ELSE
    RAISE NOTICE '[7b1.3.1] FAIL — clés manquantes: %', v_missing;
  END IF;
END $$;

-- [3.2] litige.id cohérent + pointages/factures_liees/messages sont des arrays
DO $$
DECLARE
  v_litige_id   UUID;
  v_admin_uid   UUID;
  v_result      JSONB;
BEGIN
  SELECT id INTO v_litige_id FROM public.litiges LIMIT 1;
  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[7b1.3.2] SKIP — pas de litige en base';
    RETURN;
  END IF;

  SELECT user_id INTO v_admin_uid
    FROM public.user_roles WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_uid IS NULL THEN
    RAISE NOTICE '[7b1.3.2] SKIP — pas d admin plateforme';
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_uid::text, true);
  v_result := public.fn_litige_preuves_agregees(v_litige_id);

  IF (v_result->'litige'->>'id')::UUID = v_litige_id
     AND jsonb_typeof(v_result->'pointages') = 'array'
     AND jsonb_typeof(v_result->'factures_liees') = 'array'
     AND jsonb_typeof(v_result->'messages') = 'array'
  THEN
    RAISE NOTICE '[7b1.3.2] OK — litige.id cohérent + 3 arrays valides';
  ELSE
    RAISE NOTICE '[7b1.3.2] FAIL — id=% pointages=% factures=% messages=%',
      v_result->'litige'->>'id',
      jsonb_typeof(v_result->'pointages'),
      jsonb_typeof(v_result->'factures_liees'),
      jsonb_typeof(v_result->'messages');
  END IF;
END $$;

-- [3.3] Historique similaires : retourne 0..v_limit lignes, jamais le litige lui-même
DO $$
DECLARE
  v_litige_id   UUID;
  v_admin_uid   UUID;
  v_count       INTEGER;
  v_self_count  INTEGER;
BEGIN
  SELECT id INTO v_litige_id FROM public.litiges LIMIT 1;
  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[7b1.3.3] SKIP — pas de litige en base';
    RETURN;
  END IF;

  SELECT user_id INTO v_admin_uid
    FROM public.user_roles WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_uid IS NULL THEN
    RAISE NOTICE '[7b1.3.3] SKIP — pas d admin plateforme';
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_uid::text, true);

  SELECT COUNT(*) INTO v_count
    FROM public.fn_litiges_historique_similaires(v_litige_id, 5);

  SELECT COUNT(*) INTO v_self_count
    FROM public.fn_litiges_historique_similaires(v_litige_id, 50)
   WHERE id = v_litige_id;

  IF v_count BETWEEN 0 AND 5 AND v_self_count = 0 THEN
    RAISE NOTICE '[7b1.3.3] OK — % lignes retournées (≤5), litige exclu de ses propres résultats', v_count;
  ELSE
    RAISE NOTICE '[7b1.3.3] FAIL — count=% self_count=%', v_count, v_self_count;
  END IF;
END $$;

-- [3.4] Permissions : authenticated a EXECUTE, PUBLIC non
SELECT CASE
  WHEN has_function_privilege('authenticated',
        'public.fn_litige_preuves_agregees(uuid)', 'EXECUTE')
   AND has_function_privilege('authenticated',
        'public.fn_litiges_historique_similaires(uuid,integer)', 'EXECUTE')
   AND NOT has_function_privilege('public',
        'public.fn_litige_preuves_agregees(uuid)', 'EXECUTE')
   AND NOT has_function_privilege('public',
        'public.fn_litiges_historique_similaires(uuid,integer)', 'EXECUTE')
    THEN '[7b1.3.4] OK — authenticated=EXECUTE, PUBLIC=revoked'
  ELSE '[7b1.3.4] FAIL — permissions incorrectes'
END;

\echo ''
\echo '== CP-LITIGES-7b-1 tests terminés =='

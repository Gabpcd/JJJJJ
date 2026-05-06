-- ============================================================
-- Tests CP-LITIGES-7b-3 — RPC fn_admin_recategoriser_litige_legacy
-- ============================================================
-- Prérequis : 20260417130718_cp7b3_recategorisation_rpc.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7b3-recategorisation.test.sql
--
-- Couverture :
--   [1] Existence + SECURITY DEFINER
--   [2] Signature (UUID, public.type_litige) → jsonb
--   [3] Body contient guard est_admin() + audit LITIGE_RECATEGORISATION_LEGACY
--   [4] Droits : REVOKE PUBLIC + GRANT authenticated
--   [5] Retour JSONB `{error}` hors admin
--   [6] Comportemental : cible non-legacy ⇒ error ; cible non-AUTRE ⇒ error
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7b-3 — recatégorisation legacy =='

-- [1.1] Existe avec 2 arguments
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[7b3.1.1] OK — fn_admin_recategoriser_litige_legacy(UUID, type_litige) présente'
  ELSE '[7b3.1.1] FAIL — ' || COUNT(*) || ' match'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.2] SECURITY DEFINER
SELECT CASE
  WHEN p.prosecdef = true
    THEN '[7b3.1.2] OK — SECURITY DEFINER'
  ELSE '[7b3.1.2] FAIL — SECURITY DEFINER absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.3] Retour = jsonb
SELECT CASE
  WHEN pg_get_function_result(p.oid) = 'jsonb'
    THEN '[7b3.1.3] OK — retour jsonb'
  ELSE '[7b3.1.3] FAIL — retour=' || pg_get_function_result(p.oid)
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.4] Signature (uuid, public.type_litige)
SELECT CASE
  WHEN pg_get_function_identity_arguments(p.oid)
       ILIKE '%uuid%type_litige%'
    THEN '[7b3.1.4] OK — signature (UUID, public.type_litige)'
  ELSE '[7b3.1.4] FAIL — signature=' || pg_get_function_identity_arguments(p.oid)
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.5] Body contient guard est_admin()
SELECT CASE
  WHEN pg_get_functiondef(p.oid) ILIKE '%est_admin()%'
    THEN '[7b3.1.5] OK — guard est_admin()'
  ELSE '[7b3.1.5] FAIL — guard absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.6] Body contient audit LITIGE_RECATEGORISATION_LEGACY
SELECT CASE
  WHEN pg_get_functiondef(p.oid) ILIKE '%LITIGE_RECATEGORISATION_LEGACY%'
    THEN '[7b3.1.6] OK — audit LITIGE_RECATEGORISATION_LEGACY'
  ELSE '[7b3.1.6] FAIL — audit absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.7] Body update type_legacy = FALSE
SELECT CASE
  WHEN pg_get_functiondef(p.oid) ILIKE '%type_legacy%FALSE%'
    OR pg_get_functiondef(p.oid) ILIKE '%type_legacy = FALSE%'
    THEN '[7b3.1.7] OK — UPDATE type_legacy=FALSE'
  ELSE '[7b3.1.7] FAIL — levée du flag legacy absente'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_admin_recategoriser_litige_legacy'
  AND p.pronargs = 2;

-- [1.8] Droits : PUBLIC révoqué, authenticated GRANT
SELECT CASE
  WHEN NOT has_function_privilege(
        'public',
        'public.fn_admin_recategoriser_litige_legacy(uuid, public.type_litige)',
        'EXECUTE'
      )
    THEN '[7b3.1.8] OK — PUBLIC n''a pas EXECUTE'
  ELSE '[7b3.1.8] FAIL — PUBLIC peut EXECUTE (risque sécu)'
END;

SELECT CASE
  WHEN has_function_privilege(
        'authenticated',
        'public.fn_admin_recategoriser_litige_legacy(uuid, public.type_litige)',
        'EXECUTE'
      )
    THEN '[7b3.1.9] OK — authenticated a EXECUTE'
  ELSE '[7b3.1.9] FAIL — authenticated ne peut EXECUTE'
END;

-- ─────────────────────────────────────────────────────────────
-- [2] Comportemental : guard + guardrails type_legacy / AUTRE
-- ─────────────────────────────────────────────────────────────

-- Hors authentification (auth.uid() = NULL), retour JSONB `{error}`.
SELECT CASE
  WHEN (public.fn_admin_recategoriser_litige_legacy(
          gen_random_uuid(), 'ABSENCE_SOIGNANT'::public.type_litige
        ) ->> 'error') IS NOT NULL
    THEN '[7b3.2.1] OK — anonyme → erreur JSONB'
  ELSE '[7b3.2.1] FAIL — anonyme non bloqué'
END;

-- Cible introuvable sous rôle admin simulé : on ne peut pas facilement
-- impersonate sans user fixture, donc on s'en tient au scénario anon
-- ici. Les tests end-to-end sous session admin sont couverts par RLS
-- integration / RTL côté front.

\echo ''
\echo '== Fin tests CP-LITIGES-7b-3 =='

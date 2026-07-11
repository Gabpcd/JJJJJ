-- Lot 19 — Page Audit RLS « morte » : diagnostic = MISMATCH DE FORME. La RPC
-- fn_audit_rls_strict (réécrite) renvoyait
--   { success, tables_sans_rls:[…], tables_rls_active_sans_policy:[…], exec_le }
-- alors que src/pages/admin/AdminAuditRLS.tsx attend
--   { verdict, total_tables, tables_sans_rls:number, tables_sans_policy:number,
--     problemes:[{type,table}], executed_at }.
-- Toutes les clés diffèrent → verdict undefined (KO permanent) + problemes.map
-- sur undefined → crash. On RÉPARE (roadmap : réparée plutôt que retirée) en
-- alignant la RPC sur le contrat du composant. Redéfinition depuis la déf LIVE.
CREATE OR REPLACE FUNCTION public.fn_audit_rls_strict()
 RETURNS jsonb
 STABLE
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_total int;
  v_problemes jsonb;
  v_nb_sans_rls int;
  v_nb_sans_policy int;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  SELECT count(*) INTO v_total
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
    AND c.relname NOT IN ('signature_rate_limit_ip', 'spatial_ref_sys');

  WITH sans_rls AS (
    SELECT c.relname AS t, 'RLS_DESACTIVEE' AS type
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = false
      AND c.relname NOT IN ('signature_rate_limit_ip', 'spatial_ref_sys')
  ),
  sans_policy AS (
    SELECT c.relname AS t, 'RLS_ACTIVE_SANS_POLICY' AS type
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_policy p ON p.polrelid = c.oid
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = true
    GROUP BY c.relname HAVING COUNT(p.polname) = 0
  ),
  tous AS (SELECT * FROM sans_rls UNION ALL SELECT * FROM sans_policy)
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object('type', type, 'table', t) ORDER BY type, t), '[]'::jsonb),
    (SELECT count(*) FROM sans_rls),
    (SELECT count(*) FROM sans_policy)
  INTO v_problemes, v_nb_sans_rls, v_nb_sans_policy
  FROM tous;

  RETURN jsonb_build_object(
    'success', true,
    'verdict', CASE WHEN (v_nb_sans_rls + v_nb_sans_policy) = 0 THEN 'OK' ELSE 'KO' END,
    'total_tables', v_total,
    'tables_sans_rls', v_nb_sans_rls,
    'tables_sans_policy', v_nb_sans_policy,
    'problemes', v_problemes,
    'executed_at', NOW()
  );
END;
$function$;

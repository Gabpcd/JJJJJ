# Page admin /admin/audit-rls (Sprint 7)

> Fix **P1-11** audit Sprint 5. Expose `fn_audit_rls_strict` Sprint 3 dans une page admin avec KPIs et actions.

## Route

`/admin/audit-rls` (RouteProtegee `ADMIN_PLATEFORME`).

## Composant

`AdminAuditRLS` (`src/pages/admin/AdminAuditRLS.tsx`).

## Sections

1. **3 KPI cards** :
   - Verdict global (success si 0 problème, destructive sinon)
   - Tables sans RLS (rouge)
   - RLS active sans policy (orange)

2. **Liste tables sans RLS** (si > 0) — recommandation `ALTER TABLE … ENABLE ROW LEVEL SECURITY`

3. **Liste RLS active sans policy** (si > 0) — recommandation : ajouter policies ou désactiver RLS

4. **Actions** :
   - "Rerun audit" → relance `fn_audit_rls_strict`
   - "Exporter JSON" → download rapport en local

## RPC backend (Sprint 3)

```sql
CREATE OR REPLACE FUNCTION public.fn_audit_rls_strict()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
  v_tables_sans_rls jsonb;
  v_tables_rls_sans_policy jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  -- Tables sans RLS (exclut spatial_ref_sys, signature_rate_limit_ip)
  SELECT jsonb_agg(c.relname) INTO v_tables_sans_rls
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = false
    AND c.relname NOT IN ('signature_rate_limit_ip', 'spatial_ref_sys');

  -- Tables RLS active mais 0 policy
  SELECT jsonb_agg(jsonb_build_object('table', t.table_name, 'policies', t.cnt))
  INTO v_tables_rls_sans_policy
  FROM (...) t;

  RETURN jsonb_build_object(
    'success', true,
    'tables_sans_rls', COALESCE(v_tables_sans_rls, '[]'::jsonb),
    'tables_rls_active_sans_policy', COALESCE(v_tables_rls_sans_policy, '[]'::jsonb),
    'exec_le', NOW()
  );
END; $$;
```

## Cas d'usage

1. Après chaque migration ajoutant une table → rerun audit
2. Avant chaque release prod → check RLS strict
3. Lors d'un incident sécurité → exporter rapport pour DPIA

## Limitations

- Ne vérifie pas la qualité des policies (logique métier RLS)
- Uniquement présence/absence
- Tables exclues : `signature_rate_limit_ip` (rate limit IP par design), `spatial_ref_sys` (PostGIS read-only)

# Security Checklist — Jolene

## Edge Functions

- **Aucune edge function de test ou debug ne doit être déployée en prod.** Pour invoquer des edge functions en interne (tests, cron, admin), utiliser `pg_net` depuis une RPC `SECURITY DEFINER` restreinte aux admins, ou le bypass `service_role` avec `service_role_reason` obligatoire.
- **verify_jwt = false** : chaque function avec `verify_jwt = false` dans `config.toml` doit implémenter sa propre validation d'auth (Bearer token check, service_role check, ou endpoint public intentionnel comme `calendar-feed`).
- **Incident P1bis (2026-04-15)** : une edge function proxy `test-invoke-generate-invoice` a été déployée temporairement en prod sans auth pour tester `generate-invoice`. Neutralisée immédiatement (verify_jwt=true + corps 403). **À supprimer définitivement** via le dashboard Supabase.

## GRANTs

- **Toute migration `CREATE FUNCTION` doit inclure les `GRANT EXECUTE`** pour `authenticated` et/ou `service_role` selon le cas d'usage.
- **Toute migration `CREATE TABLE` doit inclure les `GRANT SELECT/INSERT/UPDATE`** pour les roles appropriés.
- Pattern : vérifier après chaque PR avec `has_function_privilege()` et `information_schema.role_table_grants`.

## Service Role

- Le service_role key ne doit JAMAIS circuler hors du runtime Supabase (pas dans les logs SQL, pas dans les réponses HTTP, pas dans les commits).
- Le bypass service_role dans `generate-invoice` requiert un `service_role_reason` validé par pattern + rate limit 10/min.

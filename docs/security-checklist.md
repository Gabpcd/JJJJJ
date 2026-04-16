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

## Protection anti-seed (CP6)

Depuis la migration `20260416200000_cp6_anti_seed_triggers.sql`, deux triggers `BEFORE INSERT` bloquent toute donnée de test injectée hors des flux métier :

- **`factures_honoraires`** : `fn_anti_seed_facture_honoraire` exige `|montant_ht - mission.net_a_payer| <= 0.50€`. Toute facture injectée avec un montant incohérent est refusée.
- **`missions`** : `fn_anti_seed_mission` exige, si `total_brut`/`net_a_payer` sont posés à l'INSERT, une cohérence `taux × duree` à ±1€. L'insertion avec `total_brut = NULL` (parcours `fn_creer_mission` + sync trigger) est autorisée.

### Bypass légitimes

| Bypass | Setting | Usage |
|---|---|---|
| Flux `generate-invoice` | `jolene.generate_invoice_context = 'true'` | Edge function (wrapper RPC à créer si besoin) |
| Flux `fn_creer_mission` | `jolene.creer_mission_context = 'true'` | Déjà posé par `fn_creer_mission` |
| Admin override | `jolene.admin_seed_override_reason` (texte non vide) | Toute insertion admin doit poser une raison ; log auto dans `journaux_audit` action `OVERRIDE_ANTI_SEED` |

### Purge des données de test

Le script `scripts/purge-test-data.sql` permet de nettoyer les comptes de test (`@demo.fr`, `@test.com`, UUIDs `c0000000-*` / `b0000000-*`, SIRETs factices `111…444`) en mode dry-run par défaut, ou avec `-v execute=1` pour DELETE effectif.

- **Liste blanche UUID** (comptes Gabrielle) intégrée dans le script.
- **Idempotent** : ré-exécution sans effet après purge.
- **Ordre FK** : enfants `factures_honoraires` / `missions` / `soignants` / `etablissements` supprimés avant les parents, avec `DISABLE TRIGGER USER` pour contourner les garde-fous CP5a/CP5b/CP3.

### Rappels

- **Ne JAMAIS** seeder directement `factures_honoraires` ou `missions` (total_brut/net_a_payer) dans les migrations : ajouter les nouvelles fixtures via `fn_creer_mission` + `generate-invoice` dans les tests uniquement.
- **Toute nouvelle action** ajoutée à `journaux_audit.action` doit être ajoutée au `CHECK` constraint dans la migration qui l'introduit.

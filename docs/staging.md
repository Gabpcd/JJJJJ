# Environnement Staging — Jolene

Date : 2026-05-04

## Vue d'ensemble

Le projet Supabase **`jolene-staging`** (`mejpriaetwgtcstbgfid`) est une copie
isolée du schéma prod, dédiée aux **tests de charge k6** et aux validations
non-prod. **Aucune donnée prod n'est copiée** : staging part d'un schéma
vierge + seeds de test.

| Composant | Prod | Staging |
|---|---|---|
| Project ref | `flripxtsyegjshnhzjkz` | `mejpriaetwgtcstbgfid` |
| URL | `https://flripxtsyegjshnhzjkz.supabase.co` | `https://mejpriaetwgtcstbgfid.supabase.co` |
| Frontend | `jolene.app` (Vercel prod) | Pas de Vercel staging — tests API only |
| Workflow deploy | `deploy-supabase.yml` (auto sur push main) | `deploy-supabase-staging.yml` (manuel) |
| Données | Réelles (utilisateurs, missions) | `playwright-*` + `loadtest-*` uniquement |

## Stratégie bootstrap : dump prod → apply staging

**Pourquoi pas `supabase db push` from-scratch ?** Les migrations Lovable
historiques (depuis mars 2026) ALTER des tables qui n'existent pas dans un
schéma vierge — le schéma initial a été créé hors-CLI via le dashboard
Lovable, puis seulement les modifications incrémentales ont été versionnées
en migrations. `db push` from-scratch crashe sur la 1re migration
(`20260311115120_*` : `ALTER POLICY ON public.missions...`).

**Solution** : le workflow `deploy-supabase-staging.yml` :
1. Se link à PROD avec les credentials prod
2. `supabase db dump --linked` → snapshot du schéma live (schema-only, pas de data)
3. `supabase db dump --schema supabase_migrations --data-only` → tracking versions
4. Apply les 2 dumps sur staging via `psql` direct (db.$REF.supabase.co:5432)
5. Re-exécute la migration `20260503050000_playwright_seed_test_accounts.sql`
   pour seeder les comptes test (le dump exclut le schéma `auth` par défaut)
6. Optionnel : seed 500 missions [loadtest] via `tests/load/seed/seed-staging.sql`

**Aucune donnée prod n'est copiée** — uniquement le schéma (tables, fonctions,
RLS, triggers, types).

## Setup initial — actions Gabrielle

### 1. Ajouter les secrets GitHub

Settings → Secrets and variables → Actions → New repository secret.

**Secrets PROD (déjà présents pour `deploy-supabase.yml`)** — réutilisés en
lecture par le workflow staging pour dumper le schéma :

| Nom du secret | Valeur |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | (déjà existant) |
| `SUPABASE_PROJECT_REF` | `flripxtsyegjshnhzjkz` |
| `SUPABASE_DB_PASSWORD` | (déjà existant) |

**Secrets STAGING à ajouter** :

| Nom du secret | Valeur | Où la trouver |
|---|---|---|
| `STAGING_SUPABASE_PROJECT_REF` | `mejpriaetwgtcstbgfid` | Project ID staging |
| `STAGING_SUPABASE_ACCESS_TOKEN` | `sbp_...` | Dashboard Supabase → Account → Access Tokens → Generate |
| `STAGING_SUPABASE_DB_PASSWORD` | `********` | Dashboard staging → Project Settings → Database → Connection string |
| `STAGING_SUPABASE_URL` | `https://mejpriaetwgtcstbgfid.supabase.co` | Dashboard staging → Project Settings → API |
| `STAGING_SUPABASE_ANON_KEY` | `eyJhbG...` | Dashboard staging → Project Settings → API → anon public |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | `eyJhbG...` | Dashboard staging → Project Settings → API → service_role (secret) |
| `LOAD_TEST_PASSWORD` | `Playwright!Test2026` | Mot de passe hardcodé dans la migration de seed (NE PAS changer) |

### 2. Lancer le bootstrap staging

Actions → **Deploy Supabase STAGING (bootstrap from prod schema dump)** → Run workflow

Inputs (1re exécution) :
- `reset_first` = `true` (DESTRUCTIF : DROP/recreate `public` + `supabase_migrations`)
- `skip_functions` = `false` (déployer aussi les 40 edge functions)
- `seed_load_test_data` = `true` (seed les 500 missions pour scenario F)

Durée attendue : 5-10 min.

À la fin, vérifier dans le job summary + logs :
- ✅ Schéma prod dumpé (~1-3 MB de SQL)
- ✅ Apply sur staging sans erreur
- ✅ `Verify staging bootstrap` step affiche `Tables public ≥ 20`,
  `Comptes Playwright = 2`
- ✅ Edge functions déployées
- ✅ 500 missions [loadtest] (si seed activé)

### 3. Re-runs (mises à jour)

Quand le schéma prod évolue (nouvelles migrations sur main) et qu'on veut
synchroniser staging :

Actions → **Deploy Supabase STAGING** → Run workflow avec :
- `reset_first` = `true` (recommandé pour partir d'un état propre)
- `seed_load_test_data` = `true` si on veut re-seed les missions test
- `skip_functions` = `false` (re-deploy edge fns)

### 3. Lancer les tests de charge

Actions → **Load tests (k6)** → Run workflow

Inputs :
- `scenario` = choisir parmi `01-inscription-bloc`, `02-login-simultane`,
  `03-recherche-missions`, `04-candidatures-simultanees`,
  `05-dashboard-concurrent`, `06-cron-weekly-invoicing`, `all`
- `vus_override` (optionnel) : forcer un VU count différent du défaut
- `duration_override` (optionnel) : forcer une durée différente

Voir `docs/tests-charge.md` pour l'interprétation des résultats.

## Re-bootstrap staging (reset complet)

Si staging part en cacahuète et qu'on veut tout reset :

**Option 1 — via le workflow** (recommandé) :

Actions → **Deploy Supabase STAGING** → Run workflow avec
`reset_first=true` + `seed_load_test_data=true`. Le workflow fait :
```sql
DROP SCHEMA IF EXISTS public CASCADE;
DROP SCHEMA IF EXISTS supabase_migrations CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres, service_role;
```
puis ré-applique le dump prod.

**Option 2 — nuke complet du projet** :

Dashboard staging → Project Settings → Pause project → Delete project →
recréer un projet `jolene-staging`. Mettre à jour les secrets GitHub avec
les nouveaux credentials. Puis re-run le workflow.

Note : l'auth schema (auth.users, auth.identities) n'est PAS reset par
l'option 1 — si des comptes pourrissent, supprimer manuellement via
SQL Editor :
```sql
DELETE FROM auth.users WHERE email LIKE 'loadtest-%@jolene.app' OR email LIKE 'playwright-%@jolene.app';
```
(la migration de seed les recréera proprement).

## Cleanup post-tests

Après une campagne de tests, nettoyer pour éviter d'empiler les `[loadtest]` :

Dashboard staging → SQL Editor → Run le contenu de `tests/load/seed/cleanup-staging.sql`.

Cela supprime :
- Toutes les missions/candidatures/factures `[loadtest]%`
- Tous les comptes `loadtest-*@jolene.app`

Préserve :
- `playwright-soignant@jolene.app`, `playwright-etab@jolene.app` (comptes test fixes)
- Le schéma + edge functions

## Sécurité

- Le service_role key staging **ne doit JAMAIS être commité** ni utilisé côté
  browser. Uniquement dans secrets GitHub Actions.
- L'URL staging peut être partagée publiquement (rien de sensible) — mais
  préférer la garder discrète pour éviter le scraping.
- Pas de production data ⇒ pas de risque RGPD si une fuite arrive.

## Différences techniques avec prod

| Aspect | Prod | Staging |
|---|---|---|
| Cron pg_cron actifs | Oui (weekly-invoicing, litiges, monitoring) | À vérifier — désactiver si pollue les tests |
| Stripe webhooks | Live keys | Test keys (configurer dans secrets staging si besoin) |
| Twilio SMS | Live | Désactivé ou test sandbox (vérifier) |
| Email transactional (Resend) | Live | Désactivé recommandé pour ne pas spammer |
| Sentry DSN | Prod project | Différent project ou désactivé |

⚠️ **Action Gabrielle post-bootstrap** : vérifier dans Dashboard staging →
Database → Cron Jobs si les crons hérités du schéma sont actifs et les
désactiver/ré-écrire vers no-op pour ne pas polluer les mesures de tests.

## Troubleshooting

| Symptôme | Cause probable | Fix |
|---|---|---|
| `relation public.missions does not exist` | Bootstrap from-scratch via `db push` (mauvaise stratégie) | Utiliser le workflow `deploy-supabase-staging.yml` qui dump prod (la migration history seule ne marche pas, cf. baseline Lovable) |
| `psql: connection refused` ou `db.<ref>.supabase.co timeout` | Direct port 5432 bloqué pour ce projet | Vérifier dashboard → Project Settings → Database que "Direct connection" est ON (devrait par défaut) |
| `psql: password authentication failed` | `STAGING_SUPABASE_DB_PASSWORD` wrong | Re-copier depuis Dashboard staging → Settings → Database → Reset password si oublié |
| `supabase db dump` fail sur prod | `SUPABASE_DB_PASSWORD` (prod) erroné | Vérifier secret prod, pas staging |
| Edge fn deploy fail "permission denied" | `STAGING_SUPABASE_ACCESS_TOKEN` insuffisant | Régénérer un token avec scope full |
| k6 fail "401 Unauthorized" | `STAGING_SUPABASE_ANON_KEY` faux | Re-copier depuis dashboard staging → API |
| Scenario D fail "playwright-etab non seedé" | Step "Re-execute playwright seed migration" a planté | Re-run deploy-staging — vérifier que la migration 20260503050000 finit OK |
| Scenario F fail "0 missions seedées" | `seed_load_test_data=false` au bootstrap | Re-run deploy-staging avec `seed_load_test_data=true` |
| `duplicate key violates unique constraint` au step apply schema | Staging déjà bootstrap — re-run sans `reset_first` | Lancer avec `reset_first=true` pour partir propre |

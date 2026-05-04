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

## Setup initial — actions Gabrielle

### 1. Ajouter les secrets GitHub

Settings → Secrets and variables → Actions → New repository secret.

| Nom du secret | Valeur | Où la trouver |
|---|---|---|
| `STAGING_SUPABASE_PROJECT_REF` | `mejpriaetwgtcstbgfid` | Project ID staging |
| `STAGING_SUPABASE_ACCESS_TOKEN` | `sbp_...` | Dashboard Supabase → Account → Access Tokens → Generate |
| `STAGING_SUPABASE_DB_PASSWORD` | `********` | Dashboard staging → Project Settings → Database → Connection string (password) |
| `STAGING_SUPABASE_URL` | `https://mejpriaetwgtcstbgfid.supabase.co` | Dashboard staging → Project Settings → API |
| `STAGING_SUPABASE_ANON_KEY` | `eyJhbG...` | Dashboard staging → Project Settings → API → anon public |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | `eyJhbG...` | Dashboard staging → Project Settings → API → service_role (secret) |
| `LOAD_TEST_PASSWORD` | (réutilise `PLAYWRIGHT_TEST_PASSWORD`) | Définir une valeur unique min 12 chars |

### 2. Lancer le bootstrap staging

Actions → **Deploy Supabase STAGING** → Run workflow

Inputs :
- `skip_functions` = `false` (déployer aussi les edge functions)
- `seed_load_test_data` = `true` (seed les 500 missions pour scenario F)

Durée attendue : 5-10 min (333 migrations + 40 edge functions).

À la fin, vérifier dans le job summary :
- ✅ Migrations SQL appliquées
- ✅ 500 missions [loadtest] seedées
- ✅ Edge functions déployées

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

1. Dashboard staging → Database → Backups → "Reset database" (ou supprimer/recréer
   le projet entièrement si nécessaire).
2. Re-run le workflow `deploy-supabase-staging.yml` avec `seed_load_test_data=true`.

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
| `db push` fail "Tenant or user not found" | Pooler Supavisor + GitHub Actions | Le step heal-drift utilise déjà l'API Management. Vérifier que `SUPABASE_DB_PASSWORD` est correct. |
| Edge fn deploy fail "permission denied" | `STAGING_SUPABASE_ACCESS_TOKEN` insuffisant | Régénérer un token avec scope full |
| k6 fail "401 Unauthorized" | `STAGING_SUPABASE_ANON_KEY` faux | Re-copier depuis dashboard → API |
| Scenario D fail "playwright-etab non seedé" | Migration 20260503050000 pas appliquée | Re-run deploy-staging — vérifier dans logs que les 333 migrations sont OK |

# Tests de charge k6 — Jolene

Tests de charge **API pure** (pas de frontend) ciblant le projet **staging**
(`mejpriaetwgtcstbgfid`). Vercel scale automatiquement, donc on cible
uniquement les goulets d'étranglement potentiels : Supabase auth, RPCs PostgREST,
edge functions.

## Structure

```
tests/load/
├── helpers/
│   ├── auth.js     # login/signup Supabase API direct + headers
│   └── data.js     # génération comptes, filtres, randoms
├── scenarios/
│   ├── 01-inscription-bloc.js          # 100 VUs signup
│   ├── 02-login-simultane.js           # 50 VUs login
│   ├── 03-recherche-missions.js        # 200 VUs RPC recherche
│   ├── 04-candidatures-simultanees.js  # 50 VUs postuler 1 mission (race)
│   ├── 05-dashboard-concurrent.js      # 100 VUs RPC dashboard
│   └── 06-cron-weekly-invoicing.js     # 1 VU invoke cron (500 missions)
├── seed/
│   ├── seed-staging.sql       # 500 missions [loadtest] TERMINEE pour scenario F
│   └── cleanup-staging.sql    # purge missions + comptes loadtest-*
└── results/                    # JSON outputs k6 (gitignored)
```

## Lancement

**Toujours via le workflow `load-tests.yml` — JAMAIS contre la prod.**

1. Setup staging (1× au début) : Actions → "Deploy Supabase STAGING" → Run
   workflow (avec `seed_load_test_data=true` si scenario F).
2. Run scénario : Actions → "Load tests (k6)" → Run workflow → choisir scénario.
3. Récupérer artifacts JSON.

### Local (dev)

```bash
# Installer k6 : https://k6.io/docs/get-started/installation/
brew install k6  # macOS
# ou : curl -L https://github.com/grafana/k6/releases/latest/download/k6-linux-amd64.tar.gz | tar xz

export STAGING_SUPABASE_URL=https://mejpriaetwgtcstbgfid.supabase.co
export STAGING_SUPABASE_ANON_KEY=<anon staging>
export STAGING_SUPABASE_SERVICE_ROLE_KEY=<service_role staging>
export LOAD_TEST_PASSWORD=<password compte test>

k6 run tests/load/scenarios/03-recherche-missions.js
```

## Cibles de performance

Voir `docs/tests-charge.md`.

## Cleanup

Après une session de tests :

```sql
-- Via SQL Editor staging
\i tests/load/seed/cleanup-staging.sql
```

## Convention de seeding

- Missions test : `intitule LIKE '[loadtest]%'`
- Comptes auth créés : `email LIKE 'loadtest-%@jolene.app'`
- Comptes test fixes (PRESERVÉS) : `playwright-soignant@jolene.app`,
  `playwright-etab@jolene.app`

# Tests de charge — Jolene

Date : 2026-05-04

## Objectif

Valider que la stack Supabase de Jolene tient un **lancement public viral**
post-LinkedIn : 100-500 visiteurs en quelques heures, pics 50-100 utilisateurs
simultanés, 50 candidatures sur 1 mission populaire, cron weekly-invoicing
sur 500-1000 missions.

**Ce qu'on teste** : Supabase auth, RPCs PostgREST, edge functions sur le
projet **staging** (`mejpriaetwgtcstbgfid`).

**Ce qu'on ne teste pas** : Vercel frontend (scale auto), CDN assets,
intégrations tiers (Stripe, Twilio, Resend) — out of scope load test.

## Outillage

- **k6** (Grafana) — scripts JS, exécution Go performante
- Workflow CI : `.github/workflows/load-tests.yml`
- Scripts : `tests/load/scenarios/*.js`

## Procédure complète

### 1. Pré-requis (1×)

Voir `docs/staging.md` :
- Secrets GitHub configurés
- Workflow `deploy-supabase-staging.yml` exécuté avec `seed_load_test_data=true`

### 2. Lancer un scénario

GitHub Actions → **Load tests (k6)** → Run workflow → choisir scénario.

### 3. Analyser le rapport

- Logs du job : `k6 run` affiche un summary inline (passes/failures, p50/p95/p99)
- Artifact `k6-results-<scenario>-<runId>.zip` : JSON détaillé par metric
- Si threshold dépassé → job rouge → cf. plan d'action ci-dessous

## Les 6 scénarios

### A — Inscription en bloc (`01-inscription-bloc.js`)

| Aspect | Valeur |
|---|---|
| VUs | 100 (ramp 30s → plateau 1min → ramp-down) |
| Endpoint | `POST /auth/v1/signup` |
| Cible | 95%+ succès, p95 < 3s, p99 < 5s |
| Mesure | Capacité brute auth Supabase (gotrue) |

⚠️ **Note** : on test `/auth/v1/signup` direct, pas `register-soignant` edge fn
(rate limit 5 req/IP/10min anti-abuse). Le wrapper edge fn est testé en E2E.

### B — Login simultané (`02-login-simultane.js`)

| Aspect | Valeur |
|---|---|
| VUs | 50 sur pool 2 comptes test fixes |
| Endpoint | `POST /auth/v1/token?grant_type=password` |
| Cible | 100% succès, p95 < 1s, p99 < 2s |

### C — Recherche missions massive (`03-recherche-missions.js`)

| Aspect | Valeur |
|---|---|
| VUs | 200 (ramp 30s → plateau 1.5min → ramp-down) |
| Endpoint | `POST /rest/v1/rpc/fn_missions_publiques_recherche` |
| Cible | 100% succès, p50 < 400ms, p95 < 1s, p99 < 2s |
| Mesure | RPC PostgREST anon avec filtres variés (profession × ville) |

### D — Candidatures simultanées (`04-candidatures-simultanees.js`)

| Aspect | Valeur |
|---|---|
| VUs | 50, 1 itération chacun |
| Endpoint | `POST /rest/v1/rpc/fn_postuler_mission` |
| Cible | Pas de 5xx, pas de doublon en DB |
| Mesure | Race condition sur 1 mission populaire |

Le `teardown()` vérifie que `count(distinct soignant_id) = count(*)` dans
`candidatures` pour la mission test → fail si doublon (race non protégée).

**Si fail** = la contrainte UNIQUE sur `(mission_id, soignant_id)` est manquante
ou défaillante → fix CRITIQUE en migration repo.

### E — Dashboard concurrent (`05-dashboard-concurrent.js`)

| Aspect | Valeur |
|---|---|
| VUs | 100 |
| Endpoint | `POST /rest/v1/rpc/fn_dashboard_soignant_complet` |
| Cible | 100% succès, p95 < 2s, p99 < 3.5s |
| Mesure | RPC complexe (stats + missions disponibles + alertes + matching) |

### F — Cron weekly invoicing (`06-cron-weekly-invoicing.js`)

| Aspect | Valeur |
|---|---|
| VUs | 1, 1 itération (le cron est mono-instance par design) |
| Endpoint | `POST /functions/v1/weekly-invoicing-cron` (auth service_role) |
| Cible | < 10 min pour 500 missions, 0% échec |
| Mesure | Edge fn + RPC `fn_lister_missions_a_facturer` + `generate-invoice` x500 |

Pré-requis : `seed_load_test_data=true` dans deploy-staging (seed les 500 missions).

## Métriques k6 — interprétation rapide

| Metric | Sens | Cible "santé" |
|---|---|---|
| `http_reqs` (rate) | req/s soutenu | dépend du scénario |
| `http_req_duration p(50)` | médiane | < 500ms idéal |
| `http_req_duration p(95)` | 95% des reqs | < 1.5s idéal |
| `http_req_duration p(99)` | 99% des reqs | < 3s idéal |
| `http_req_failed` (rate) | % HTTP errors | < 1% pour usage normal |
| `iteration_duration` | temps complet 1 itération VU | dépend du scénario |
| `vus` | VUs actifs | doit suivre la rampe configurée |

## Plan d'action si bottleneck

### Recherche missions p95 > 1s (scenario C)

**Cause probable** : `fn_missions_publiques_recherche` fait un seq scan sur
la table `missions` faute d'index sur `(statut, profession_requise, ville)`.

**Fix** : créer une migration `supabase/migrations/YYYYMMDDXXXXXX_idx_missions_recherche.sql` :

```sql
CREATE INDEX IF NOT EXISTS idx_missions_recherche
ON public.missions (statut, profession_requise, ville)
WHERE statut = 'OUVERTE';

NOTIFY pgrst, 'reload schema';
```

Puis re-deploy staging et re-run scenario C → comparer p95.

### Dashboard p95 > 2s (scenario E)

**Cause probable** : RPC `fn_dashboard_soignant_complet` exécute 5-10 sous-requêtes
agrégées séquentiellement (stats notations, missions disponibles, alertes…).

**Options** :
1. Indexes sur les tables filles (`notations.evaluateur_id`, `candidatures.soignant_id`)
2. Materialized view `mv_dashboard_soignant` rafraîchie toutes les 5min via pg_cron
3. Cache HTTP côté client (React Query staleTime: 60_000) — déjà en place ?

### Inscription rate-limited (scenario A)

**Cause** : Supabase auth `/signup` rate limit (~30 req/min/IP par défaut).

**Action** : si le rate limit kick au-delà de 50% des requêtes, demander à
Supabase support d'augmenter le quota pour le projet prod (justifier par
"campagne de lancement publique").

### Candidatures avec doublons (scenario D — CRITIQUE)

**Si le teardown échoue avec "doublons détectés"** : la contrainte UNIQUE
sur `candidatures(mission_id, soignant_id)` est manquante ou désactivée.

**Fix immédiat** :

```sql
ALTER TABLE public.candidatures
  ADD CONSTRAINT candidatures_mission_soignant_unique UNIQUE (mission_id, soignant_id);
```

⚠️ Vérifier d'abord qu'aucun doublon n'existe en prod avant d'appliquer
(migration : `DELETE FROM candidatures WHERE id NOT IN (SELECT MIN(id) FROM candidatures GROUP BY mission_id, soignant_id);`).

### Cron weekly > 10 min (scenario F)

**Causes possibles** :
1. Pas de batch — chaque mission = 1 INSERT facture sériel
2. Génération PDF synchrone (lourd)
3. RPC `fn_generer_facture_mensuelle` avec scan complet à chaque appel

**Optimisations** :
- Paralléliser dans l'edge fn (`Promise.all` par batch de 10)
- Décaler la génération PDF en async post-cron
- Batch INSERT factures + COMMIT par 50

## Capacités estimées prod (extrapolation)

⚠️ Compute tier staging vs prod peut différer. Si staging = `nano` et prod =
`small`, les mesures staging sont une **borne basse pessimiste** de la prod.
Vérifier le tier dans Dashboard → Project Settings → Compute and Disk.

| Scenario | Capacité staging mesurée (à remplir) | Capacité prod estimée (×N) |
|---|---|---|
| A — signup | TBD | TBD |
| B — login | TBD | TBD |
| C — recherche | TBD | TBD |
| D — candidatures | TBD | TBD |
| E — dashboard | TBD | TBD |
| F — cron | TBD | TBD |

## Plan d'action si dépassement seuil en prod

1. **Monitoring temps réel** : dashboard Sentry + Supabase logs activés
2. **Alertes** : `fn_check_crons_health()`, `fn_check_stripe_webhook_health()`
   (déjà déployées en prod)
3. **Scaling** : si CPU DB > 80% soutenu → Dashboard Supabase → Compute upgrade
   `small` → `medium` (1 click, restart < 30s)
4. **Read replicas** (si pic lecture lourd, ex. recherche missions) — feature
   Supabase Pro+
5. **Edge fn auto-scaling** : géré nativement par Deno Deploy (pas d'action)

## Historique des runs

| Date | Scénario | Résultat | Bottleneck identifié | Fix appliqué |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD |

À remplir après chaque campagne de tests.

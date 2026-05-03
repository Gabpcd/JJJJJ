# Setup Sentry — Jolene

Date dernière mise à jour : 2026-05-03

Ce document explique comment activer, configurer et opérer Sentry pour le frontend Jolene (web + mobile Capacitor).

## TL;DR — état du code

Le code est **prêt en production**. Il manque uniquement les variables d'environnement côté Vercel :

| Variable | Type | Côté | Rôle |
|---|---|---|---|
| `VITE_SENTRY_DSN` | publique | Vercel (Production + Preview) | Point d'envoi des events depuis le navigateur |
| `SENTRY_AUTH_TOKEN` | secret | Vercel (Production uniquement) | Upload des sourcemaps au build |
| `SENTRY_UPLOAD_ENABLED` | `"true"` | Vercel (Production uniquement) | **Active réellement l'upload sourcemaps**. À ne mettre qu'APRÈS création du projet Sentry, sinon le build affiche `error: Project not found` (non bloquant mais anxiogène). |
| `SENTRY_ORG` | (optionnel, défaut `jolene`) | Vercel | Org Sentry |
| `SENTRY_PROJECT` | (optionnel, défaut `jolene-frontend`) | Vercel | Projet Sentry |

> **`VITE_SENTRY_DSN` n'est pas un secret.** Le DSN apparaît dans le bundle JS public — c'est le comportement normal Sentry. Le rate-limiting se fait côté Sentry par projet.

## Activation step-by-step

### 1. Créer le projet Sentry

1. https://sentry.io → crée une org `jolene` (ou rejoindre l'existante)
2. Create Project → React → name `jolene-frontend`
3. Récupérer le DSN (`https://abc123@o000000.ingest.sentry.io/000000`)

### 2. Créer un Auth Token

1. https://sentry.io → User Settings → Auth Tokens
2. Create Token avec scopes : `project:releases`, `org:read`, `project:read`
3. Copier le token (visible une seule fois)

### 3. Configurer Vercel

Dashboard Vercel → Project `jolene` → Settings → Environment Variables

| Variable | Value | Environments |
|---|---|---|
| `VITE_SENTRY_DSN` | `https://abc...@oXX.ingest.sentry.io/XXX` | Production, Preview, Development |
| `SENTRY_AUTH_TOKEN` | (token créé étape 2) | Production |
| `SENTRY_UPLOAD_ENABLED` | `true` | Production |
| `SENTRY_ORG` | `jolene` | Production |
| `SENTRY_PROJECT` | `jolene-frontend` | Production |

> **Important** : ne définir `SENTRY_UPLOAD_ENABLED=true` qu'après avoir créé le projet Sentry (étape 1). Sinon le build Vercel affiche un log rouge `error: Project not found` (non bloquant — le deploy passe en READY — mais visuellement perturbant).

Redeploy le dernier commit `main` pour appliquer.

### 4. Vérifier la chaîne

1. Se connecter sur https://jolene.app/admin/status (compte `admin@jolene.app`)
2. Section **Outils diagnostic** → cliquer **"Déclencher erreur test Sentry"**
3. Vérifier dans Sentry dashboard que l'event apparaît avec :
   - User context (email admin)
   - Tag `environment: production`
   - Tag `test: true`
   - Stack trace **désobfusquée** (sourcemaps OK = lignes/fichiers TS lisibles)
   - Release : SHA git court Vercel

> Filtrer les events `test:true` du dashboard principal : `event.tags.test:true` dans la search bar Sentry → "Save as filter".

## Configuration appliquée (référence)

### `src/main.tsx` (Sentry.init)

- **DSN conditionnel** : Sentry.init n'est appelé que si `VITE_SENTRY_DSN` est défini → pas de bruit en dev local
- **Release** : `__APP_VERSION__` injecté par Vite (SHA git court Vercel ou `dev-YYYY-MM-DD`)
- **Replay RGPD-friendly** : `maskAllText: true`, `maskAllInputs: true`, `blockAllMedia: true` → la structure DOM est capturée mais aucun contenu utilisateur (emails, RPPS, montants, messages chat) ne fuite
- **`tracesSampler` adaptatif** :
  - `/`, `/connexion`, `/inscription/*`, `/aide/*` → 5 % (pages publiques fréquentes)
  - tout le reste → 20 % (pages auth)
  - erreurs → 100 % via `replaysOnErrorSampleRate`
- **`ignoreErrors`** :
  - ResizeObserver loop (Chrome bug bénin)
  - Non-Error promise rejection
  - AbortError, NetworkError, Failed to fetch (network glitches transitoires)
  - Script error (scripts tiers cross-origin)
- **`denyUrls`** :
  - `chrome-extension://`, `moz-extension://`, `safari-(web-)extension://`
  - `localhost`, `127.0.0.1`
- **`beforeSend` (PII scrubbing)** :
  - Emails → `[email-redacted]`
  - JWT → `[jwt-redacted]`
  - RPPS (11 chiffres) → `[rpps-redacted]`
  - Query params sensibles (`email`, `token`, `access_token`, `refresh_token`, `recovery_token`, `rpps`) → `[redacted]`
  - Hash recovery (`#access_token=...`) → `#[redacted]`
  - Headers `Authorization`, `Cookie` retirés

### `src/lib/logger.ts`

`logger.error(message, error)` pousse vers Sentry :
- Si `error instanceof Error` → `Sentry.captureException`
- Sinon → `Sentry.captureMessage` avec `level: 'error'`
- `logger.warn` ajoute un breadcrumb `level: warning` (pas d'event)

### `src/lib/handleError.ts`

`handleError` et `handleErrorSilent` poussent vers Sentry :
- `handleError` → toast utilisateur + `Sentry.captureException` level `error`
- `handleErrorSilent` → log dev only + `Sentry.captureException` level `warning`

Tous les `.then(undefined, (err) => handleErrorSilent(err, 'contexte'))` apparaîtront dans Sentry avec le tag `contexte`.

### `vite.config.ts` (sentryVitePlugin)

- Conditionnel sur `SENTRY_AUTH_TOKEN` (skip en dev local)
- `release: { name: APP_VERSION, create: true, finalize: true }` → crée la release dans Sentry et marque les sourcemaps
- Sourcemaps uploadées depuis `./dist/**` à chaque build
- `errorHandler` non-bloquant si l'org/project n'existe pas (le build ne casse pas)

## Inviter Gabrielle (et autres collègues)

1. https://sentry.io → Settings → Members → Invite Member
2. Email collègue
3. Role : **Member** (lecture + résolution issues, pas admin org)
4. Team : `jolene` (ou créer une team `prod-alerts` pour cibler les notifs)

## Configurer une alerte email

Settings → Alerts → Create Alert :

```
Project: jolene-frontend
When: An issue is seen
If:
  - the issue's level is equal to error
  - the issue is unresolved
  - 5 events occur in 1 hour
  - tag environment equals production
  - tag test does not equal true
Action: Send notification to gabrielle@jolene.app
```

Pour les alertes critiques (paiement, auth) :

```
If:
  - tag composant equals AuthContext OR tag composant equals Stripe
  - 1 event occurs in 5 minutes
Action: Send notification immédiate
```

## Lire les issues

Filtres de tri utiles :

| Filtre | Usage |
|---|---|
| `is:unresolved` | À traiter en priorité |
| `tag:source:logger` | Erreurs catchées via `logger.error` |
| `tag:source:handleError` | Erreurs catchées via `handleError(Silent)` |
| `tag:contexte:*` | Contexte métier (ex. `MissionsSoignant.heuresSemaine`) |
| `level:error` | Erreurs (vs warnings, info) |
| `tag:test:true` | À exclure du dashboard principal |

Pour chaque issue :
1. **Stack trace** : doit être désobfusquée (lignes TS visibles)
2. **Replay** (si erreur déclenchée pendant session) : voir le contexte UI sans contenu PII
3. **User context** : `id` (Supabase user UUID) + email (peut être redacted selon scope)
4. **Breadcrumbs** : navigation, console, requêtes (URLs scrubbées des params sensibles)

## Quotas et plan

- **Plan Free** : 5 000 events/mois
- **Plan Team** : 50 000 events/mois (~26 €/mois)
- Les samples (5/20 %) sur traces consomment du quota performance, pas du quota erreurs

Optimisation : si le quota free est dépassé fréquemment, ajuster :
- `tracesSampler` plus bas (3 % public, 10 % auth)
- Ajouter des `ignoreErrors` patterns issus des issues les plus bruyantes

## Dépannage

| Symptôme | Cause probable | Fix |
|---|---|---|
| Aucun event en prod | DSN non configurée | Vérifier `VITE_SENTRY_DSN` côté Vercel |
| Stack traces minifiées | `SENTRY_AUTH_TOKEN` manquant ou `SENTRY_UPLOAD_ENABLED` non setté | Vérifier upload sourcemaps dans logs Vercel build |
| Build Vercel affiche `error: Project not found` (rouge) | `SENTRY_UPLOAD_ENABLED=true` mais projet Sentry pas créé | Créer le projet Sentry (étape 1) ou retirer `SENTRY_UPLOAD_ENABLED` temporairement |
| Release `unknown` | `__APP_VERSION__` non injectée | Vérifier `vite.config.ts` define + redeploy |
| Tile "Sentry Dégradé" sur `/admin/healthcheck` | DSN non configurée | Voir étape 3 |
| Trop de bruit ResizeObserver | `ignoreErrors` non appliqué | Vérifier déploiement code récent |

## Filtrer les events `test:true` du dashboard

Sentry UI → Settings → Inbound Filters → Custom :
- Add filter : `test:true` → drop event before storage
  → ces tests ne consomment plus le quota

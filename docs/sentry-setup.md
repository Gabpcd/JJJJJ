# Setup Sentry — Jolene

Date dernière mise à jour : 2026-10-02

Ce document décrit la configuration Sentry du frontend Jolene et la vérification des traces. Les constats ci-dessous concernent le web de production ; ils ne valident pas les applications mobiles Capacitor.

## État vérifié et limite restante

Le projet existant est **`jolene-app`**, dans l'organisation **`jolene-z6`** : [console Sentry Jolene](https://jolene-z6.sentry.io/).

Le 1er octobre 2026, `SENTRY_ORG=jolene-z6` et `SENTRY_PROJECT=jolene-app` ont été enregistrés dans Vercel pour Production et Preview ; `SENTRY_UPLOAD_ENABLED=true` a été confirmé pour Production. Les uploads privés de cartes ont été confirmés pour les releases `f82f5d05` (1 029 fichiers) et `58fd2931` (1 025 fichiers). Les contrôles publics ont retrouvé l'identifiant de release et un debug ID dans le JavaScript ; les cartes interrogées publiquement renvoyaient HTTP 404.

**La lisibilité d'une trace reste non prouvée.** L'unique événement de diagnostic autorisé a bien été reçu, mais concernait la release antérieure `083abf7a` et sa trace était minifiée. Aucun événement de la release `f82f5d05` n'était disponible lors du contrôle suivant. Le contrôle public du 2 octobre a retrouvé le marqueur de version `88ecd` et un debug ID ; il ne prouve ni l'upload privé de cette version ni la désobfuscation d'un événement. La session Sentry avait expiré : une nouvelle lecture authentifiée reste nécessaire.

Un déploiement Vercel `READY`, un client Sentry configuré, une tentative d'envoi ou un upload réussi ne suffisent pas, seuls, à valider la lisibilité des traces. Aucun nouveau test d'envoi n'a été effectué pour cette mise à jour documentaire.

## Configuration de référence

Dashboard Vercel → Project `jolene` → Settings → Environment Variables. Ne pas recréer d'organisation ou de projet pour poursuivre cette vérification.

| Variable | Valeur ou provenance | Environnement concerné | Rôle |
|---|---|---|---|
| `VITE_SENTRY_DSN` | DSN du projet existant, sans le recopier dans les preuves | Production ; autres environnements selon leur configuration | Point d'envoi des événements depuis le navigateur |
| `SENTRY_AUTH_TOKEN` | Secret de compilation géré dans Vercel, jamais dans ce document ni dans le frontend | Production | Authentifie l'upload privé des cartes |
| `SENTRY_UPLOAD_ENABLED` | `true` confirmé | Production | Active l'upload lorsque le secret de compilation est également présent |
| `SENTRY_ORG` | `jolene-z6` confirmé | Production, Preview | Organisation destinataire |
| `SENTRY_PROJECT` | `jolene-app` confirmé | Production, Preview | Projet destinataire |

`VITE_SENTRY_DSN` fait partie de la configuration publique du navigateur. `SENTRY_AUTH_TOKEN` doit rester côté compilation. La présence de l'organisation et du projet en Preview ne prouve pas un upload Preview ; les uploads confirmés ci-dessus concernent Production. Les simulations qui désactivent volontairement Sentry ne valident pas sa réception réelle.

Le code conserve des valeurs de repli historiques (`jolene` / `jolene-frontend`) : elles ne désignent pas la destination configurée. Vérifier les variables explicites de l'environnement concerné avant de conclure à une erreur de projet. Les preuves actuelles ne justifient pas de modifier les secrets ou de relancer un déploiement.

## Vérifier les traces d'une version concordante

1. Se reconnecter à la [console de l'organisation `jolene-z6`](https://jolene-z6.sentry.io/) et sélectionner le projet `jolene-app`.
2. Relever la release du déploiement à vérifier. Le web de production utilise les huit premiers caractères du SHA Git Vercel ; le runtime et l'upload reçoivent le même identifiant défini dans `vite.config.ts`.
3. Dans les [cartes du projet](https://jolene-z6.sentry.io/settings/projects/jolene-app/source-maps/), vérifier la réception des artefacts correspondant à cette version. Conserver la release, la référence du bundle et l'heure du constat, sans secrets. Un ancien bundle reçu ne prouve pas l'upload d'une version plus récente.
4. Dans les événements existants, filtrer le projet, l'environnement `production`, une période appropriée et `release:<identifiant exact>`. Ouvrir un événement qui possède une stack trace. Vérifier sa release et, lorsqu'il est disponible, le debug ID du fichier avec celui de l'artefact correspondant ; le nombre de fichiers uploadés ne suffit pas à établir cette correspondance.
5. Constater dans cet événement des fichiers source et des lignes lisibles, puis conserver sa référence, la release et le résultat. Si aucun événement correspondant n'existe, ou si la trace reste minifiée, garder le statut **« lisibilité non vérifiée »** et préciser le point manquant. Ne pas utiliser l'ancien événement `083abf7a` pour valider les cartes d'une autre release.

La marche normale ci-dessus consulte les événements déjà présents et ne crée pas d'événement. Si un nouveau diagnostic est autorisé séparément, le bouton **« Tester Sentry »** de `/admin/status` affiche seulement une tentative d'envoi et sa référence éventuelle. Sa réception, sa version et la lisibilité de sa trace doivent ensuite être constatées dans Sentry. Le statut local **« Réception des événements non vérifiée »** décrit uniquement la configuration du client et reste indépendant du constat dans la console ; il ne signale pas à lui seul une panne.

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

- Upload conditionnel sur `SENTRY_UPLOAD_ENABLED=true` **et** la présence de `SENTRY_AUTH_TOKEN` ; sans les deux, les cartes de production ne sont pas générées.
- `release: { name: APP_VERSION, create: true, finalize: true }` utilise la même valeur que `Sentry.init({ release })` dans `src/main.tsx`.
- Quand l'upload est actif, les cartes sont générées en mode `hidden`, envoyées depuis `./dist/**`, puis supprimées du dossier de livraison avec `filesToDeleteAfterUpload`.
- `errorHandler` est non bloquant : le statut Vercel `READY` ne prouve pas un upload réussi. Vérifier le résultat de l'upload et les artefacts reçus dans Sentry pour la version concernée.

## Inviter Gabrielle (et autres collègues)

1. https://sentry.io → Settings → Members → Invite Member
2. Email collègue
3. Role : **Member** (lecture + résolution issues, pas admin org)
4. Team : `jolene` (ou créer une team `prod-alerts` pour cibler les notifs)

## Configurer une alerte email

Settings → Alerts → Create Alert :

```
Project: jolene-app
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
1. **Stack trace** : vérifier les fichiers source et lignes lisibles pour la release exacte ; une trace minifiée reste non validée.
2. **Replay** (si erreur déclenchée pendant session) : voir le contexte UI sans contenu PII
3. **User context** : utiliser seulement le contexte nécessaire au diagnostic ; la présence d'un email n'est pas un critère de validation des traces.
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
| Stack traces minifiées | Artefacts absents, mauvais projet ou événement d'une autre version | Vérifier la release de l'événement, son debug ID et les cartes reçues dans `jolene-z6` / `jolene-app` avant toute reconfiguration |
| Upload affiche `error: Project not found` | Destination de compilation incorrecte ou accès insuffisant au projet existant | Vérifier `SENTRY_ORG=jolene-z6`, `SENTRY_PROJECT=jolene-app` et les droits de compilation, sans recopier le secret ni recréer le projet |
| Release `unknown` | `__APP_VERSION__` non injectée | Vérifier `vite.config.ts` define + redeploy |
| Diagnostic Sentry indique « Réception des événements non vérifiée » | Le statut local décrit la configuration, pas la réception | Suivre la vérification par release concordante dans Sentry ; ne pas traiter ce libellé seul comme une panne |
| Trop de bruit ResizeObserver | `ignoreErrors` non appliqué | Vérifier déploiement code récent |

## Filtrer les events `test:true` du dashboard

Pour la consultation courante, exclure de l’affichage les événements dont le tag `test` vaut `true`. Pour retrouver un diagnostic déjà envoyé, filtrer sur ce tag et la release attendue. Ne pas confondre ce filtre d'affichage avec un filtre d'ingestion qui supprimerait l'événement avant sa réception et empêcherait sa vérification.

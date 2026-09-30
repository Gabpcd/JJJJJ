# Diagnostic Sentry et préparation de la reprise — 30 septembre 2026

Le diagnostic admin distingue désormais l'absence de configuration, un client
indisponible et une tentative d'envoi. Il ne présente plus l'appel au SDK comme
une réception confirmée. La carte Sentry reste « Non vérifié », y compris après
le test et après rechargement. Une référence locale valide facilite la recherche
dans Sentry ; elle ne prouve pas la livraison.

La procédure de sauvegarde corrige l'affirmation selon laquelle PITR serait
automatiquement inclus et actif avec Pro. Elle décrit un exercice isolé, la
sauvegarde des objets Storage, les mesures RPO/RTO et les effets sortants à
neutraliser avant toute restauration. Aucun exercice réel n'a été réalisé ici.

## Vérifications acquises

| Vérification | Résultat et portée |
|---|---|
| Tests composants diagnostic + healthcheck | 14/14 ; états SDK absents/désactivés, tentative, erreur et reprise |
| Projection des métadonnées de sauvegarde | 8/8 tests Node ; sans réseau ni secrets |
| TypeScript, ESLint des fichiers modifiés, diff | Réussis |
| Build frontend local | Réussi ; configuration Supabase et Sentry fictive, aucun upload de sourcemaps |
| Frontend sans DSN | 5/5 scénarios, un par format |
| Frontend configuré, transport simulé HTTP 200 et 500 | 10/10 scénarios, deux par format |

Formats : iPhone, Android, iPad portrait, iPad paysage et ordinateur ; rôle admin
sur la page réelle `/admin/status`. Les scénarios exécutent le bouton, contrôlent
les messages et la carte, revérifient les services puis rechargent la page. Ils
vérifient aussi l'absence de débordement horizontal, d'erreur JavaScript et de
requête inattendue. Captures et arbres accessibles sont conservés localement.

Les API métier sont simulées. Pour les dix cas configurés, le SDK Sentry réel
envoie vers un serveur HTTP **local fictif**, avec réponses 200 ou 500. Le test
contrôle l'exception, ses tags et son identifiant, sans contacter Sentry. Une
origine virtuelle servie entièrement depuis la preview évite le filtre SDK des
traces `localhost`. Les permissions de réseau local sont limitées au contexte
Chromium jetable de cette simulation. Les premiers essais avec interception de
transport ont révélé une course WebKit au rechargement ; le serveur local permet
de conserver le transport réel du SDK et le contrôle des erreurs navigateur.

Ces résultats ne prouvent ni une réception chez Sentry, ni une alerte reçue et
acquittée, ni des droits console, ni une restauration Supabase, ni le comportement
sur appareils physiques. Aucun événement de production, charge de production,
paiement, livraison mobile ou modification de sauvegarde n'a été déclenché.

## Rejouer la simulation

La recette habituelle sans DSN utilise
`e2e/recette-complete-admin-sentry.spec.ts` avec
`e2e/playwright.recette-complete.config.ts`. Pour la variante configurée, bâtir
une preview isolée avec les valeurs fictives suivantes :

```sh
VITE_SUPABASE_URL=http://127.0.0.1:8891 \
VITE_SUPABASE_PUBLISHABLE_KEY=simulation \
VITE_SENTRY_DSN=http://recette@127.0.0.1:18997/1 \
VITE_ENV=simulation SENTRY_UPLOAD_ENABLED=false npm run build

npm run preview -- --host 127.0.0.1 --port 8896 --strictPort
```

Dans un autre terminal, avec les navigateurs Playwright disponibles :

```sh
RECETTE_SENTRY_CONFIGURE=1 \
PLAYWRIGHT_BASE_URL=http://127.0.0.1:8896 \
RECETTE_RESULTS_DIR=/private/tmp/jolene-operations-ui-configure-valide \
npx playwright test --config e2e/playwright.recette-complete.config.ts \
  e2e/recette-complete-admin-sentry.spec.ts
```

Le port local 18997 doit être libre. La configuration impose un seul worker.
Sans DSN, reconstruire avec `VITE_SENTRY_DSN=` et omettre
`RECETTE_SENTRY_CONFIGURE=1`. Utiliser les exécutables de navigateur déjà installés
si nécessaire ; aucune installation n'est requise par cette recette.

## Preuves et travail restant

Résultats de cette exécution :

- `/private/tmp/jolene-operations-ui-absent-final/results.json` — 5/5 ;
- `/private/tmp/jolene-operations-ui-configure-valide/results.json` — 10/10 ;
- `/private/tmp/jolene-audit-capacite-lancement-20260930.md` — audit borné des sept
  réserves opérationnelles et de capacité, distinctes des vérifications CI.

Après merge, le workflow manuel `backup-status.yml` pourra relever les seules
métadonnées de sauvegarde autorisées en lecture seule. Une configuration présente
ne démontrera toujours pas la restauration. Les preuves de réception Sentry,
notification hors cockpit, copie Storage, reprise isolée, charge représentative
et couverture de support restent à établir selon les procédures documentées.

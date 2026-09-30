# Navigation depuis une candidature reçue — 30 septembre 2026

Ce lot frontend conserve la destination `/etablissement/missions/<uuid>` à travers une reconnexion et relit la candidature quand le clic natif vise une fiche déjà montée. Le retour post-connexion n'accepte ni origine externe, ni paramètres, ni fragment, ni autre action. Les permissions de route et les RLS restent inchangées.

Un clic natif retenu peut être consommé pendant la connexion, avant la fin de la résolution de rôle ou de la biométrie. La page de connexion ne doit plus naviguer après son démontage : la destination choisie par ce clic reste prioritaire. Le clic sur la même fiche déclenche une relecture sans nouvelle entrée d'historique.

## Vérifications locales

- 82 tests Vitest ciblés verts : retour canonique et refus d'autres destinations, rôles soignant/groupe inchangés, connexion standard et biométrique, actualisation et reprise native. Cinq témoins échouaient avant la correction initiale.
- Témoin frontend rouge supplémentaire : clic retenu avant listener, puis résolution de rôle libérée après navigation mission ; l'ancienne continuation revenait au tableau de bord. La même simulation passe après la garde de montage.
- 30 simulations Playwright vertes, sans retry : principal et membre RH, chacun sur la même fiche, après reconnexion/reload, et avec clic retenu/rôle retardé, dans les cinq formats iPhone, Android, iPad portrait, iPad paysage et ordinateur. Captures CSS, snapshots ARIA avant/après, route finale et contrôles console sans filtre.
- `tsc -b`, build avec URL/clé publiques fictives, `git diff --check` et les 17 garde-fous locaux verts.

Commande unitaire :

```sh
node_modules/.bin/vitest run src/components/RouteProtegee.test.tsx src/pages/PageConnexion.role-resolution.test.tsx src/components/ListeCandidatures.test.tsx src/lib/pushNative.registration.test.ts src/lib/pushNative.test.ts src/components/NativeSessionResume.test.tsx src/lib/navigationNotification.test.ts
```

La simulation utilise un build local avec `VITE_SUPABASE_URL=http://127.0.0.1:54321`, `VITE_SUPABASE_PUBLISHABLE_KEY=recette-fictive`, `SENTRY_UPLOAD_ENABLED=false` et `VITE_SENTRY_DSN=''`. Après preview local :

```sh
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18481 RECETTE_RESULTS_DIR=/private/tmp/candidature-liens-ui-final node_modules/.bin/playwright test --config e2e/playwright.recette-complete.config.ts e2e/recette-complete-notification-candidature.spec.ts --trace=off --workers=1
```

Preuves locales : `/private/tmp/candidature-liens-ui-final/results.json`, captures et ARIA du même dossier ; journaux `/private/tmp/candidature-liens-unit-red.log`, `candidature-liens-unit-green.log`, `candidature-liens-retention-red.log`, `candidature-liens-tsc.log`, `candidature-liens-guards.log` et `candidature-liens-build.log`.

Une première matrice comptait 19/20 : le scénario iPhone principal atteignait la mission mais le contrôle console détectait `Importing a module script failed` / ErrorBoundary autour du reload. Cette preuve est conservée dans `/private/tmp/candidature-liens-ui-mobile/` et son journal `.log`. La fixture attend maintenant la fin des chargements réseau avant de détruire le document par reload ; aucune erreur de module n'est filtrée. Les 30 scénarios finaux passent avec ce déroulement. Ce constat ne prouve pas l'absence de tout incident d'import sur appareil physique.

## Limites maintenues

Ces simulations utilisent un backend et un bridge Capacitor fictifs. Elles n'exécutent ni SQL, ni acceptation de candidature, ni paiement, ni livraison APNs/FCM/Web réelle. La biométrie est couverte par test unitaire, pas par capteur physique. Le Service Worker Web n'est pas exercé par cette recette ; aucun correctif `notificationclick` n'est inclus.

Le membre RH est simulé dans son établissement canonique. Les comptes ADMIN_GROUPE et les membres d'un établissement secondaire ne gagnent aucun accès : une future sélection des destinataires push doit respecter le scope de lecture `mon_etablissement_id()`, et pas seulement l'appartenance à une équipe. Le raccord serveur CANDIDATURE_RECUE demeure un lot séparé ; ce commit ne le remplace pas et ne valide pas la suppression de l'alerte locale dépendante de ce raccord.

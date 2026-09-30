# Résolution administrative : retours dans le dialogue

Le toast de refus pouvait recouvrir « Valider la résolution », notamment sur iPad paysage. `LitigeResolutionModal` présente maintenant les erreurs dans le dialogue (`role=alert`, focus et description du bouton), ainsi que la confirmation de succès (`role=status`). Les textes de décision, les règles, les calculs et les toasts globaux ne changent pas.

Un refus conserve la saisie et autorise un réessai immédiat. Le verrou synchrone bloque les doubles clics et la fermeture pendant l'appel ; après un succès confirmé, le bouton reste désactivé. Chaque ouverture et chaque dossier possède un formulaire neuf. Une réponse tardive d'un formulaire démonté ne modifie pas le dossier suivant. Une réponse sans `success: true` n'annonce pas de réussite. La sécurisation d'une facture émise précède toujours la même RPC de résolution.

## Vérifications locales

Base : `2bfd1fe2`, branche isolée `fix/retour-resolution-litige-inline`. Dépendances locales existantes réutilisées, aucune installation.

```sh
node_modules/.bin/vitest run \
  src/components/admin/litiges/LitigeResolutionModal.feedback.test.tsx \
  src/components/admin/litiges/LitigeResolutionModal.test.ts \
  tests/admin/security/litige-admin-financial-resolution-hardening.test.ts \
  tests/admin/security/litige-agreement-hardening.test.ts
node_modules/.bin/tsc -b --pretty false
VITE_SUPABASE_URL=http://127.0.0.1:8891 \
VITE_SUPABASE_PUBLISHABLE_KEY=simulation-publishable-key \
VITE_SENTRY_DSN= node_modules/.bin/vite build --target es2020
node_modules/.bin/vite preview --host 127.0.0.1 --port 8898 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:8898 \
RECETTE_RESULTS_DIR=/private/tmp/jolene-litige-inline-ui-final-verifie \
node_modules/.bin/playwright test \
  --config e2e/playwright.recette-complete.config.ts \
  e2e/recette-complete-admin-litige-garde.spec.ts
```

- 27 tests ciblés : refus salarié/libéral, réessai, message accessible, absence de toast, doubles clics, réponse tardive/changement de dossier, réouverture, réponse incomplète, rejet transport et refus de sécurisation du paiement. `Failed to fetch` reçu dans `error.message` comme une exception rejetée reste uniquement dans le logger ; le formulaire affiche un message français générique et permet un réessai. Les messages métier `result.error` restent inchangés.
- 17 contrôles additionnels `tests/invoicing/mandate-v14-corrections.test.ts` passent avec `--config vitest.invoicing.config.ts`.
- TypeScript et build de vérification ES2020 passent. Le build conserve l'avertissement existant sur la taille de certains chunks.
- La recette utilise la vraie route `/admin/litiges`, le vrai dialogue et les vrais contrôles Radix, avec réponses API et session fictives. Les erreurs de console et de page sont toutes collectées, sans filtre de contenu.
- Matrice finale : **10/10**, aucun test sauté, instable ou inattendu, zéro erreur de console/page. Deux scénarios, salarié et libéral, sur iPhone WebKit, Android Chromium, iPad portrait/paysage WebKit et ordinateur Chromium. Interaction tactile sur téléphones/tablettes et double clic souris sur ordinateur pendant une réponse retenue, refus puis réessai sans sommeil ni clic forcé, une seule mutation par tentative, confirmation, reset entre dossiers et après fermeture, puis rechargement du dossier résolu.

## Preuves et limites

Rapport et captures : `/private/tmp/jolene-litige-inline-ui-final-verifie/`. Les captures du refus et du succès existent pour chaque format ; les états ARIA couvrent aussi la réinitialisation et la reprise après rechargement. Le test vérifie les rectangles du message et du bouton pour exclure le chevauchement.

Simulation frontend locale uniquement. Aucun compte créé, aucune mutation distante, aucune résolution financière réelle, aucun appel Stripe, aucune livraison, aucun push. Ce lot ne prouve pas le backend, un paiement ou un remboursement. Les gardes SQL sont traitées par le lot distinct. Aucune revue CLI ni revendication de revue indépendante B8.

L'essai exploratoire a détecté un sélecteur de test incorrect : pendant l'appel, le bouton est nommé « Résolution… » et non « Valider la résolution ». Le sélecteur a été corrigé ; aucune erreur de console ou assertion fonctionnelle n'a été masquée.

La première matrice complète a révélé le bouton sous le pli après focus de l’erreur sur iPad paysage/libéral (9/10). Le défilement vise désormais tout le bloc retour et actions ; les assertions de visibilité sont conservées et étendues au succès. Preuve du défaut intermédiaire : `/private/tmp/jolene-litige-inline-ui-final/`.

Une seconde matrice a réussi 9/10 ; un clic souris émulé sur iPhone n’a pas ouvert le second dossier. L’essai ciblé a aussi rencontré un hit-test HTML au double clic, avant toute mutation. La recette utilise désormais les gestes tactiles Playwright sur appareils tactiles et les clics souris sur ordinateur, vérifie la fermeture complète du dialogue puis l’expansion de la carte, sans sommeil, clic forcé ni nouvelle tentative automatique. Les deux parcours tactiles iPhone ont passé la vérification ciblée. Ces gestes restent émulés, sans preuve d’appareil physique. Rapports intermédiaires : `/private/tmp/jolene-litige-inline-ui-valide/`, `/private/tmp/jolene-litige-inline-ui-navigation/` et `/private/tmp/jolene-litige-inline-ui-tactile/`. Les traces exploratoires redondantes ont été supprimées pour économiser le disque ; rapports et captures sont conservés.

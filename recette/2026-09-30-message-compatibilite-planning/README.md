# Message de compatibilité du planning — 30 septembre 2026

Base : `a215788777d94a1f6225e9b46a8795d273763e24`. Lot descriptif séparé de la PR #1000.

## Constat et portée

La route `/soignant/missions/:id` monte `DetailMissionSoignant`, puis
`BlocConformite`. Son succès combine uniquement les contrôles du repos, du plafond
hebdomadaire et du chevauchement. Le composant ne connaît ni la validation du
dossier documentaire ni la décision de l'établissement.

La phrase « Tout est conforme. Vous pouvez accepter cette mission. » était donc
visible pour une candidature encore en attente, avec des documents non validés.
Elle devient « Ces horaires sont compatibles avec votre planning. ».

Le diff produit contient cette unique substitution. Conditions, seuils, callbacks,
règles et rappels documentaires, textes réglementaires et branche conditionnelle
du choix de contrat sont inchangés. Une assertion comparant intégralement le
fichier avec celui de la base après cette seule substitution a passé.

## Vérifications

- Les six tests existants de `BlocConformite` passent. Les assertions ajoutées
  vérifient le nouveau texte sur succès, l'absence de l'ancienne promesse et
  l'absence du nouveau message en cas d'indisponibilité, plafond conditionnel ou
  repos insuffisant.
- `tsc -b --pretty false` et le contrôle TypeScript des deux fichiers E2E passent.
- Recette D réutilisée depuis `41e056d0198b98125f026d276f5ce3b136d93676`, avec
  assertions supplémentaires archivées dans `assertions-message.patch` : présence
  du nouveau texte et absence de l'ancien avant candidature, après envoi et après
  rechargement, pour les deux AS salariés aux documents non validés.
- Trois scénarios par format : les deux candidatures et leur lecture établissement,
  erreur persistante/réessai/planning périmé/rechargement, refus d'un établissement
  tiers. iPhone, Android, iPad portrait, iPad paysage, ordinateur : 15 scénarios
  distincts réussis. Les captures de l'état en attente ont été relues sur les cinq
  formats ; les captures de recette vérifient aussi l'absence de débordement horizontal.
- Relecture croisée de portée par l'agent capacité : aucun finding. Ce n'est pas
  une revue B8 à contexte vierge.

La première passe a donné 13 succès et 2 échecs `ENOSPC` : écriture/attachement des
preuves du refus tiers iPhone et fermeture/trace du parcours deux AS Android.
Après libération d'espace et vérification d'écriture, seuls ces deux scénarios
ont été rejoués et ont passé, sans changement de code ni de test. Les résultats
initiaux restent conservés. `validation.json` contient les chemins et empreintes
des trois rapports, ainsi que leurs compteurs exacts.

## Preuves et reproduction

Les captures, snapshots ARIA et journaux sont conservés dans :

- `/private/tmp/jolene-message-compatibilite-5formats-20260930`
- `/private/tmp/jolene-message-compatibilite-reprise-iphone-20260930`
- `/private/tmp/jolene-message-compatibilite-reprise-android-20260930`

Le premier dossier contient aussi `harness/` : les deux fichiers de recette
effectivement exécutés, retirés ensuite du checkout pour garder le lot produit
indépendant du lot D. Le helper est inchangé par rapport à `41e056d0` ; le patch
versionné restitue les seules assertions ajoutées à sa spec. Restaurer ces deux
fichiers dans leurs chemins `e2e/` du commit de fixtures, puis appliquer le patch
permet de rejouer la même recette.

```sh
node node_modules/vitest/vitest.mjs run src/components/BlocConformite.test.tsx
node node_modules/typescript/bin/tsc -b --pretty false
VITE_SUPABASE_URL=http://127.0.0.1:8891 VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_simulation_candidatures node node_modules/vite/bin/vite.js --host 127.0.0.1 --port 18460 --strictPort
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18460 RECETTE_RESULTS_DIR=/private/tmp/message-compatibilite-nouvelle-recette node node_modules/@playwright/test/cli.js test --config=e2e/playwright.recette-complete.config.ts recette-complete-candidatures-deux-as.spec.ts
```

## Limites

Simulation locale avec réponses API interceptées, profils fictifs et WebSockets
fermés volontairement. Le badge de notifications en mode dégradé visible sur les
captures découle de ce dernier choix. Les 15 journaux réussis ne contiennent aucun
appel externe, appel inconnu ou erreur JavaScript. Aucun compte distant, aucune
acceptation, aucun contrat, aucune signature ni opération de paiement n'ont été
créés. Ces preuves ne constituent ni une recette backend réelle, ni un contrôle
de production, ni un essai sur appareil physique. Aucun push, merge, déploiement
ou livraison mobile dans ce lot.

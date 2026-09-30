# Lien de la console Sentry — 30 septembre 2026

Le lien « Sentry » de la page admin « État du système » cible désormais `https://jolene-z6.sentry.io/`. Cette organisation et la correspondance du projet public ont été constatées séparément par le coordinateur ; cette recette ne se connecte pas à la console. Base : `a215788777d94a1f6225e9b46a8795d273763e24`.

## Portée

Une seule URL produit remplacée. Les diagnostics, messages, autres fournisseurs, `target="_blank"` et `rel="noopener noreferrer"` sont inchangés. La recette existante vérifie le `href` avant et après rechargement sans cliquer le lien.

## Validation locale

- Cinq simulations, cinq succès au premier passage : iPhone, Android, iPad portrait/paysage, ordinateur ; zéro retry, saut ou erreur inattendue.
- Source Vite locale sur `127.0.0.1:18461`, DSN Sentry vide, fournisseur non contacté ; API simulées. Le test conserve le bouton diagnostic désactivé, zéro événement, « Non vérifié », les assertions d’erreurs/requêtes inconnues et l’absence de débordement horizontal.
- Commande ciblée : `RECETTE_SENTRY_CONFIGURE=0 node_modules/.bin/playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-admin-sentry.spec.ts` (base URL et navigateurs locaux explicités dans la configuration d’exécution).
- `node_modules/.bin/tsc -b` et `git diff --check` : code 0.
- Relecture croisée indépendante du diff : aucun P1/P2, sans exécution de test ni revue CLI.

Rapport source : `/private/tmp/jolene-sentry-lien-console-5formats/results.json`, SHA256 `26d1f7a4b14cb53b2bdb65cda876e6058d4d1f0a10a3a61448b1d7ed646f613d`.

Preuves durables filtrées : `audits/2026-09-30-preparation-nationale/preuves/lien-console-sentry/` dans le dossier projet Jolene : résumé JSON, arbres ARIA des cinq formats, deux captures iPad après rechargement inspectées et manifeste SHA256. Les autres fournisseurs affichés verts dans ces captures sont simulés et ne constituent pas une vérification de leurs services. Le « ! » de notification provient du canal Realtime fermé par la simulation.

## Limites

Cette recette vérifie la destination du lien et sa persistance au rechargement. Elle ne prouve ni les droits d’accès à la console, ni la réception d’événements, ni le déclenchement d’alertes Sentry. Aucun compte distant, événement fournisseur ou appareil physique ; aucun push ni livraison.

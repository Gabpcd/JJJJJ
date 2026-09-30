# Monitoring Chorus : pause nocturne — 30 septembre 2026

## Diagnostic LIVE en lecture seule

`fn_check_crons_health()` (empreinte initiale
`7cecfb0d3faec3cafbb8c1cd7c2bfb98`) classait toute expression horaire contenant
`/2` avec un seuil fixe de trois heures. Or `sync-chorus-status-hourly` est actif
avec `0 7-22/2 * * *`, fuseau pg_cron `GMT` : passages à 7, 9, 11, 13, 15, 17, 19
et 21 heures UTC. Le passage de 21 h était donc déclaré tardif après minuit,
pendant une pause prévue de dix heures.

Lecture du 30/09 à 07:32 UTC : dernier passage `succeeded` à 07:00:00.772063,
cache déjà actualisé à 07:03:07. L'alerte créée à 00:08:06.872432 avait neuf
occurrences, la dernière à 06:30:00. Les sept alertes nocturnes précédentes étaient
toutes auto-résolues à 08:20 UTC, sans acquittement manuel. Ce cycle se répète.

L'auto-résolution est planifiée `20 */2 * * *`, donc son passage à 06:20 précède
la reprise, et le suivant est à 08:20. Elle exige un dernier passage réussi
postérieur à `derniere_occurrence`. `fn_admin_health_check()` retourne séparément
l'état actuel du cron et toutes les alertes non résolues. Le frontend affiche
fidèlement ces deux informations ; il ne résout pas les alertes en lisant.

La documentation primaire décrit la syntaxe et le fuseau configurable du moteur :
[pg_cron](https://github.com/citusdata/pg_cron#cron-syntax).

## Correction bornée

Le helper privé `fn_echeance_cron_chorus(schedule, dernier_run)` exige exactement
l'expression auditée, puis calcule le prochain passage UTC et ajoute une heure de
tolérance. Après le passage de 21 h, le retard commence après 08:00 le lendemain ;
après celui de 07 h, après 10:00. Un passage de 21 h manqué reste tardif toute la
nuit : la pause n'efface pas un retard déjà réel.

La fonction reçoit le `schedule` réellement lu dans `cron.job`. Une expression
future différente est refusée explicitement et devra être accompagnée d'une
recette ; le helper ne prétend pas interpréter toute la syntaxe cron.

Seule la branche Chorus après un passage terminé change. Les durées d'exécution
`starting/running`, les autres cadences, `CRON_FAILED`, le cas jamais exécuté,
les ACL de la RPC et son cache restent conservés. L'empreinte de l'inventaire
`SECURITY DEFINER` est actualisée. Aucun horaire cron, appel Chorus, traitement
financier ou comportement d'auto-résolution n'est modifié. Aucune alerte historique
n'est acquittée ou résolue par la migration.

## Validation

- Lecture des fonctions LIVE, horaires, historiques et cache uniquement ; aucun
  appel aux fonctions de monitoring mutantes pendant l'audit.
- Expression d'échéance exécutée en SQL `SELECT` pur : **9/9** cas conformes,
  minuit, nuit, 06:59, 07:00, borne 08:00, absence à 08:01, nouveau succès à 07 h,
  retard en journée et dernier passage du soir manqué.
- TypeScript vert, tests ciblés monitoring/inventaire **10/10**, guards **17/17**.
- Playwright **5/5**, iPhone, Android, iPad portrait/paysage et ordinateur :
  pause nocturne sans alerte, rechargement, vrai retard, rechargement puis état
  repris après auto-résolution simulée. Aucun clic « Résoudre ». Tous les appels
  des panneaux de services sont simulés, réseau externe bloqué.
- Frontend identique à e7 : réutilisation du build web local créé pour la recette
  export (mêmes fichiers applicatifs), sans nouveau build mobile.

Commandes locales :

```sh
node node_modules/typescript/bin/tsc -b
node node_modules/vitest/vitest.mjs run tests/admin/security/presence-and-score-runtime.test.ts tests/admin/security/security-definer-manifest.test.ts
bash tests/non-regression/guards.sh
RECETTE_RESULTS_DIR=/private/tmp/jolene-monitoring-chorus-simulation PLAYWRIGHT_BASE_URL=http://127.0.0.1:8897 node node_modules/@playwright/test/cli.js test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-admin-cron-chorus.spec.ts
```

La suite `tests/security/monitoring-chorus-plage-nocturne.test.sql`, raccordée à
`validate-pr`, exécute le vrai helper puis une copie temporaire du corps installé
de `fn_check_crons_health`. Seules ses tables de jobs/runs/cache, sa sortie
alertes et son horloge sont remplacées par des fixtures temporaires. Treize
scénarios couvrent aussi exécution en cours/bloquée, échec et absence d'historique.
Les seuils historiques trois heures et quinze minutes des autres cadences sont
vérifiés à la borne et une seconde après. Les DDL/fixtures sont annulés par
sous-transaction sentinelle puis rollback externe.

**Cette suite SQL complète reste à exécuter en CI après intégration du correctif
transactionnel de validation des PR.** Les neuf expressions SQL pures et les
réponses simulées du frontend ne la remplacent pas. La revue fraîche B8 reste à
obtenir. Aucune publication ou livraison production n'est revendiquée.

Preuves locales : `/private/tmp/jolene-monitoring-chorus-simulation` (résultats,
ARIA, captures nuit/retard des cinq formats). Pas de dispositif physique testé,
pas de DDL distant appliqué, pas d'appel fournisseur réel et pas de livraison
mobile/OTA/store.

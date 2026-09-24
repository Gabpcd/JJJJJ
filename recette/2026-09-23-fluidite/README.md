# Pièces de recette — fluidité du 23 septembre 2026

Lire d’abord la [synthèse et les assertions](../../docs/recettes/2026-09-23-fluidite.md), puis la [revue indépendante](../../docs/recettes/2026-09-23-fluidite-review.md).

- `avant/` : trois arbres ARIA de reproduction locale, un arbre de l’annuaire de production sans donnée personnelle et deux traces d’événements du clic Swipe.
- `apres/` : snapshots ARIA exacts WebKit, en 390 et 1440, issus de fixtures locales. Les scénarios sont également exécutés sous Chromium.
- `resultats/` : rapports JSON Playwright finaux validés avant copie ; les sorties de simple listing ne sont pas des résultats de test.
- `captures/` : huit artefacts inspectés, destinés à la lecture humaine. Ils ne remplacent pas les assertions.
- `manifest.json` : origine et SHA-256 des copies octet pour octet. Les sources temporaires avant/après sont nommées pour la traçabilité, sans compte réel ni secret.

Les données après correction sont simulées. `Résidence Camille`, `JO-ABC123`, les montants et les missions n’attestent aucune opération réelle. Les liens de partage visibles dans les arbres n’ont pas été envoyés. La navigation mobile WebKit/Pixel correspond à une émulation navigateur ; la validation native complète et le contrôle après déploiement restent distincts.

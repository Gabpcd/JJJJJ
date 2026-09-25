# Stabilisation ciblée de la recette CI — 25 septembre 2026

Les trois scénarios concernés passent dans les cinq formats : **15/15, zéro retry, zéro cas ignoré**. Il s’agit d’une correction des données et de la synchronisation de la simulation ; aucun filtre du produit n’est modifié.

## Causes établies

1. La mission de la fixture soignant commençait à l’heure courante plus sept jours, pour huit heures. Dans le run GitHub 36146638467, ce créneau traversait la nuit à Paris. La recherche sauvegardée `horaire: JOUR` l’excluait correctement. Le créneau fictif est désormais fixé à 08–16 h UTC, dans la journée à Paris en hiver comme en été. Le test vérifie Paris dans le formulaire, IDE dans la requête, Jour actif et la mission visible ; Nuit retire réellement la mission et Jour la réaffiche.
2. La boucle `getByRole('tab').all()` pouvait retourner zéro onglet avant hydratation. La trace iPad paysage le démontre avant une navigation qui annulait les requêtes de la page précédente. Les trois onglets missions, quatre présences et deux litiges sont maintenant exigés, cliqués par leur nom et vérifiés par leur contenu exact.
3. Le marqueur prêt du tableau de bord établissement pouvait précéder les chargements du cadre de navigation. La trace iPad portrait montre les RPC de permissions/messages annulés par le changement de document. Le helper attend ces deux appels et leur stabilisation. Les deux helpers redémarrent leur fenêtre de calme réseau lorsqu’un nouveau document commence à charger.

Les erreurs de page sont toujours collectées et doivent rester absentes. Aucun filtre d’erreur, retry, allongement de timeout ou retrait d’assertion métier n’a été ajouté.

## Preuves et portée

Serveur statique simulé `127.0.0.1:8902`, APIs strictement interceptées, aucun compte réel ni appel de production. Formats : iPad portrait 820×1180, iPad paysage 1180×820, iPhone 390×844, Android et ordinateur 1440×900. Un worker, retries zéro.

- Soignant : navigation après inscription + sauvegarde/réapplication de recherche, **10/10**.
- Établissement : connexion minimale, rubriques et alias du scénario existant, **5/5**.
- TypeScript global et ESLint des trois fichiers : verts.
- Relecture indépendante des trois fichiers : aucun P1/P2 démontré.

[Résultats détaillés](assets/2026-09-25-stabilisation-ci/resultats-cibles.json), [diagnostic extrait des traces CI](assets/2026-09-25-stabilisation-ci/diagnostic-traces-ci.json), [ARIA iPad portrait soignant](assets/2026-09-25-stabilisation-ci/soignant-ipad-portrait.txt), [ARIA iPad paysage soignant](assets/2026-09-25-stabilisation-ci/soignant-ipad-paysage.txt), [ARIA établissement portrait](assets/2026-09-25-stabilisation-ci/etablissement-ipad-portrait.txt), [ARIA établissement paysage](assets/2026-09-25-stabilisation-ci/etablissement-ipad-paysage.txt).

Cette passe ciblée ne remplace pas la matrice intégrale de la prochaine CI, ne prouve pas la performance du backend réel et ne constitue pas une recette native. Les passes diagnostiques interrompues avant correction ne sont pas comptées comme vertes.

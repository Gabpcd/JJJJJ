# Résumé k6 : options consolidées du moteur

Le run E100 `36694359901` utilise k6 2.3.0. Son moteur annonce 100 VUs
constants pendant 1m0s (arrêt gracieux 15s), alors que notre ligne « Configuration
effective » affiche `{}`. Le défaut est dans la source du rapport : il sérialise
`options.scenarios` de l'export JavaScript, que k6 réinjecte au démarrage des
instances via `Bundle.populateOptions`. Cet export n'est pas l'API documentée
pour relire les options consolidées à la fin de l'exécution.

Les résumés C et E lisent désormais `k6/execution.test.options` uniquement dans
`handleSummary`. Cette API retourne les options consolidées et dérivées ; son
implémentation convertit explicitement les options Go en objet JSON JavaScript.
La projection ne conserve que les paramètres d'exécution et les étapes de rampe,
jamais `env`, tags, options navigateur ou nouveaux champs inconnus. Les autres
exports JSON restent inchangés. Les définitions de scénarios, seuils, durées,
préflights, requêtes et nettoyages ne sont pas modifiés.

Sources primaires consultées : [options consolidées](https://grafana.com/docs/k6/latest/javascript-api/k6-execution/#test),
[réinjection de l'export](https://github.com/grafana/k6/blob/master/internal/js/bundle.go),
[conversion des options en JSON](https://github.com/grafana/k6/blob/master/internal/js/modules/k6/execution/execution.go).

Le banc Node reproduit un export de scénarios devenu vide, conserve une source
moteur distincte et vérifie le résumé final C/E, sans requête HTTP. Il vérifie
également l'absence de lecture de l'API durant init, l'immuabilité des seuils et
l'exclusion des canaris de secrets. Une source absente affiche « non disponible ».
Preuve : `/private/tmp/jolene-k6-resume-node.txt`.

Aucune nouvelle campagne k6 ni connexion staging n'a été exécutée. Les simulations
frontend locales à réponses fictives sont conservées dans
`/private/tmp/jolene-k6-resume-ui/results.json`. Ce contrôle de restitution ne
remplace pas la preuve réelle E100 déjà obtenue et ne prétend pas rejouer k6.

Validation : 107/107 tests Node du banc CI, 10/10 parcours frontend fictifs
(deux identités × cinq formats), TypeScript et ESLint ciblé verts. Le rendu
recalculé localement depuis les agrégats et la configuration moteur du run E100
est dans `/private/tmp/jolene-k6-resume-replay.txt` ; ce n’est pas un nouveau run.

# Recettes de charge API staging

Destination unique : `https://mejpriaetwgtcstbgfid.supabase.co`. Les scripts refusent toute autre URL. Aucune charge de production n’est autorisée par cet outillage.

Le document de référence est [docs/tests-charge.md](../../docs/tests-charge.md) : prérequis métier, paramètres, limites et état exact des scénarios.

- C (`03-recherche-missions`) : lecture publique ; exige le catalogue quantifié visible au préflight (500 missions avec la préparation CI).
- E (`05-dashboard-concurrent`) : lectures sur un profil soignant staging ; exige un vrai profil métier au préflight.
- A/B : charge Auth ; A crée des comptes et nécessite une isolation préalable des envois email.
- D/F : suspendus avec échec explicite avant toute requête, car les anciens scripts pouvaient annoncer un succès sans acte métier. `all` n’est donc pas une campagne verte attendue.

Le workflow manuel `Load tests (k6)` reçoit les overrides VUs et durée. Les scénarios actifs les appliquent via `helpers/options.js`. Pour une durée explicite, la charge utilise des VUs constants pendant cette durée totale (maximum 15 minutes), sans rampe supplémentaire.

Les anciens `seed/seed-staging.sql` et `seed/cleanup-staging.sql` concernent des scénarios historiques : ils ne doivent pas être lancés automatiquement pour contourner les préflights.

Pour C, utiliser le nouveau `scripts/ci/prepare-load-fixtures.mjs prepare`, puis `cleanup` dans une étape CI `always()`. Il crée 100–1000 missions (500 par défaut), 10 établissements fictifs sans Auth, écrit les IDs avant le réseau et vérifie leur visibilité anonyme. Il refuse la production, les crons actifs et toute suppression hors manifeste ou avec dépendance tierce. Configuration détaillée dans le document de référence.

Un verrou SQL par run sérialise préparation et nettoyage ; un reçu immuable dans le journal staging bloque une préparation qui arriverait après le nettoyage. Ce reçu système reste volontairement conservé. Le nettoyage est rejoué au maximum trois fois pour un échec transitoire ; sans confirmation, le manifeste n’est pas marqué nettoyé. Les triggers utilisateur de préparation sont suspendus sous verrou exclusif puis restaurés avant commit ; les FK restent actives. Aucun changement durable de schéma ni effacement du journal.

`seed/verify-fixtures-local.mjs` est une probe SQL facultative hors réseau, pour un environnement disposant déjà de PGlite (`PGLITE_MODULE` permet son chemin). Elle utilise un schéma minimal, les vraies fonctions de recherche/miroir d’audit, un déclencheur témoin et des FK. Elle vérifie le verrou et les deux ordres d’arrivée, dans une seule session. Elle ne remplace pas la préparation/validation sur le schéma staging complet ni une épreuve de concurrence réelle.

Pour vérifier l’outillage localement **sans réseau**, sans k6, sans compte et sans secret :

```bash
node --test tests/node/load-tests.node.mjs tests/node/prepare-load-fixtures.node.mjs
```

Les sorties d’une campagne k6 réelle sont stockées sous `tests/load/results/` puis jointes aux artefacts GitHub. Une recette de scripts en mémoire n’est pas une mesure de performance du service.

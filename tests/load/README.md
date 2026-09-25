# Recettes de charge API staging

Destination unique : `https://mejpriaetwgtcstbgfid.supabase.co`. Les scripts refusent toute autre URL. Aucune charge de production n’est autorisée par cet outillage.

Le document de référence est [docs/tests-charge.md](../../docs/tests-charge.md) : prérequis métier, paramètres, limites et état exact des scénarios.

- C (`03-recherche-missions`) : lecture publique ; exige une mission visible au préflight.
- E (`05-dashboard-concurrent`) : lectures sur un profil soignant staging ; exige un vrai profil métier au préflight.
- A/B : charge Auth ; A crée des comptes et nécessite une isolation préalable des envois email.
- D/F : suspendus avec échec explicite avant toute requête, car les anciens scripts pouvaient annoncer un succès sans acte métier. `all` n’est donc pas une campagne verte attendue.

Le workflow manuel `Load tests (k6)` reçoit les overrides VUs et durée. Les scénarios actifs les appliquent via `helpers/options.js`. Pour une durée explicite, la charge utilise des VUs constants pendant cette durée totale (maximum 15 minutes), sans rampe supplémentaire.

Le dossier `seed/` contient des scripts historiques : leur présence ne prouve ni l’éligibilité des profils ni la facturabilité du lot. Ils ne doivent pas être lancés automatiquement pour contourner les préflights.

Pour vérifier l’outillage localement **sans réseau**, sans k6, sans compte et sans secret :

```bash
node --test tests/node/load-tests.node.mjs
```

Les sorties d’une campagne k6 réelle sont stockées sous `tests/load/results/` puis jointes aux artefacts GitHub. Une recette de scripts en mémoire n’est pas une mesure de performance du service.

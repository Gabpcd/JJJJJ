# Lire le statut des stores

Le workflow **Mobile store status (read only)** se lance manuellement depuis GitHub Actions après fusion de ces fichiers sur `main` :

```sh
gh workflow run mobile-store-status.yml --ref main
```

Il ne déclenche ni build, ni upload, ni soumission, ni publication. Il ne dépend pas d'une session Safari. Il n'est ni récurrent ni lié automatiquement aux événements de livraison.

Commande équivalente dans un environnement où les secrets sont déjà injectés :

```sh
bundle exec ruby scripts/mobile/store-status.rb /chemin/rapport-store
```

Noms des secrets existants utilisés : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`, `GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64`. Ne pas passer leur contenu dans les arguments de commande. Les clés restent en mémoire, ne sont pas copiées dans les rapports et ne sont jamais imprimées.

Le script utilise `Spaceship::ConnectAPI::Token` et `Google::Auth::ServiceAccountCredentials`, déjà fournis par les dépendances Fastlane verrouillées dans `Gemfile.lock`. Aucun changement des lanes de soumission ou des versions des gems.

## Résultat

- Rapport JSON expurgé et résumé Markdown disponibles dans les artefacts GitHub et le résumé du job, datés en UTC.
- iOS : version marketing, build associé, état Apple de la version, type de sortie, état de publication progressive lorsqu'il existe, dates de création/téléversement. Les builds en traitement sont aussi listés avec leur version marketing et leur état de traitement.
- Android : releases de la piste `production`, nom de release lorsqu'il est numérique, versionCodes actifs et état du cycle de validation/publication.
- Une lecture refusée devient `unavailable` avec un code générique (`http_401`, `http_403`, etc.), sans corps d'erreur fournisseur. Un état inconnu ou une pagination tronquée devient `partial`. Ces deux situations font échouer le job afin de signaler le diagnostic incomplet, tout en conservant les résultats de l'autre store.
- Une liste vide n'est jamais décrite comme une version publiée.

Les états Apple `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`, `READY_FOR_SALE`/`READY_FOR_DISTRIBUTION` sont distincts. Un build `VALID` est un build traité, pas une preuve de publication. De même, le statut Google `APPROVED_NOT_PUBLISHED` reste distinct de `PUBLISHED`.

## Limites

Google n'expose ici ni date de changement d'état ni version marketing garantie : le nom de release est un libellé, même quand Jolene le nomme comme sa version. L'horodatage du rapport indique la date de lecture. L'API renvoie au plus 20 releases et exclut les obsolètes. Son état `PUBLISHED` inclut une publication complète, partielle ou suspendue pouvant reprendre ; il ne prouve donc pas un déploiement à 100 %.

Pour Apple, la collecte est bornée à cinq pages par collection ; un éventuel dépassement est signalé. Les rapports contiennent seulement les champs autorisés : ni notes de review, ni metadata libre, ni identifiants de compte, ni corps d'erreur, ni jetons. Aucun succès de collecte ne vaut garantie de propagation sur chaque appareil ou pays.

## Garantie de lecture seule et tests

Toutes les requêtes de statut sont des GET vers une liste fermée d'endpoints Apple/Google. Les redirections et liens de pagination vers un autre endpoint sont refusés. Aucun appel à `/edits`, aucune écriture de release. L'unique POST est l'échange OAuth Google réalisé par la bibliothèque d'authentification, sur une URL fixe.

Le workflow est manuel et lit toujours le code de `main`, même lorsqu'il est lancé depuis une autre branche. Il dispose de `contents: read` uniquement. L'étape de tests n'a pas de secrets ; seuls les champs expurgés sont archivés.

```sh
bundle exec ruby scripts/mobile/store-status.test.rb
```

Les huit contrôles fonctionnent sans réseau et sans credentials : liens version/build Apple, séparation approbation/publication Google, états inconnus (dont type de sortie et publication progressive iOS), expurgation JSON/Markdown, réponses malformées, corps d'erreur sensibles, endpoints/redirections/pagination et méthodes GET.

## Sources officielles consultées le 28 septembre 2026

- [Apple — versions App Store d'une app](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-appstoreversions)
- [Apple — liste des builds](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-builds)
- [Apple — jetons App Store Connect](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests)
- [Google — lecture des releases sans transaction edit](https://developers.google.com/android-publisher/api-ref/rest/v3/applications.tracks.releases/list)
- [Google — structure et états des releases](https://developers.google.com/android-publisher/api-ref/rest/v3/applications.tracks.releases)
- [Google — authentification compte technique OAuth](https://developers.google.com/identity/protocols/oauth2/service-account)

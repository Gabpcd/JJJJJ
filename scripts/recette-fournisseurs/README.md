# Préparation de la recette fournisseurs

Ces bibliothèques préparent une future recette isolée. Elles ne contactent aucun fournisseur, ne créent aucun compte, ne déplacent aucun fonds et ne modifient ni les exclusions de fixtures ni le verrou de l'ancien harnais financier. Aucun parcours réel SMS/signature/paiement n'est validé par leur réussite.

## Vérification locale

```sh
node --test tests/node/recette-fournisseurs-manifest.node.mjs tests/node/recette-fournisseurs-preflight.node.mjs
```

Ces tests n'utilisent ni secrets ni réseau. Le préflight est une bibliothèque importable, pas une commande opérationnelle ; son exécution directe refuse de produire un succès. `validatePreflightMetadata` vérifie les métadonnées fournies par un futur collecteur. Même un résultat `METADONNEES_COHERENTES` conserve `readyForTransports: false` et `integratedFlowReady: false`.

## Journal de ressources

`createManifest` crée exclusivement un nouveau répertoire privé. `openManifest` reprend le même contexte exact : projet staging autorisé, identifiant d'exécution, commit et compte Stripe de test attendu. Chaque intention est enregistrée avant l'appel que ferait un futur adaptateur. La clé d'idempotence reste stable lors d'une reprise.

Les révisions sont écrites, synchronisées puis liées sans écrasement. Une écriture concurrente ou incertaine impose une relecture ; aucun échec n'autorise à supposer qu'une création distante n'a pas eu lieu. Une opération en cours ne peut pas être redémarrée automatiquement : le futur moteur devra d'abord prouver l'arrêt de l'ancien worker et réconcilier son résultat.

`close` bloque toute nouvelle création et conserve les réponses tardives. Cette fermeture n'est pas un verdict de nettoyage. Un reçu de suppression ne peut être enregistré qu'après fermeture et après résolution des enfants ; un enfant ambigu bloque son parent. Les identifiants restent dans l'historique après leur suppression confirmée.

`confirmCreated` et `confirmRemoved` ne prouvent que la cohérence du reçu fourni. L'adaptateur devra relire la ressource sur le compte de test attendu pour prouver sa propriété et son résultat réel. La chaîne de hachage détecte les corruptions ordinaires, pas la réécriture malveillante de l'ensemble du journal par le même utilisateur système. Conserver le répertoire privé est indispensable pour conserver le verrou de fermeture.

## Préflight

Les références attendues doivent venir du commit relu, jamais être copiées depuis les valeurs observées. Les métadonnées observées doivent être fraîches et contenir les inventaires exacts des migrations et fonctions, leurs empreintes, les gardes de cohortes, les états des crons/files et l'identité du compte de test. Les noms de secrets ou un nom de compte ne prouvent pas leur configuration : présence, routage et mode doivent être vérifiés par le futur collecteur sans exporter les valeurs secrètes.

Une donnée absente, inconnue, incohérente, trop ancienne ou de production produit `NON_PRET`. Les erreurs ne reprennent ni le contenu fourni ni les exceptions de fournisseurs.

## Travail restant avant une exécution

- Collecteur en lecture seule, liant les preuves à la source relue et à l'environnement exact ; aucun contournement des droits manquants.
- Adaptateurs de transport limités aux ressources du journal et preuve d'idempotence réelle de chaque API.
- Réconciliation des résultats ambigus, inventaire complet des descendants, nettoyage repris après perte d'un runner et gestion explicite des résidus non supprimables.
- Verrou du moteur, stockage durable protégé du journal et preuve d'arrêt d'un worker précédent.
- Modèle d'acteurs admissibles et isolés pour un cycle intégré, sans requalifier les fixtures ni désactiver leurs exclusions.

La réception d'un SMS, les signatures, les événements de paiement et leur rapprochement restent des preuves distinctes à obtenir sur les mêmes objets du futur parcours intégré.

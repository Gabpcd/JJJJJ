# Préparation de la recette fournisseurs

Ces bibliothèques et l'inventaire en lecture seule préparent une future recette isolée. Les bibliothèques restent hors réseau ; le collecteur décrit ci-dessous lit uniquement des métadonnées Supabase et Stripe test. Aucun compte n'est créé, aucun fonds n'est déplacé et ni les exclusions de fixtures ni le verrou de l'ancien harnais financier ne sont modifiés. Aucun parcours réel SMS/signature/paiement n'est validé par leur réussite.

## Vérification locale

```sh
node --test tests/node/recette-fournisseurs-manifest.node.mjs tests/node/recette-fournisseurs-preflight.node.mjs
node --test tests/node/recette-fournisseurs-collector.node.mjs
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

- Compléter l'inventaire ci-dessous par la comparaison exacte des définitions déployées et les attestations de configuration manquantes ; aucun contournement des droits manquants.
- Adaptateurs de transport limités aux ressources du journal et preuve d'idempotence réelle de chaque API.
- Réconciliation des résultats ambigus, inventaire complet des descendants, nettoyage repris après perte d'un runner et gestion explicite des résidus non supprimables.
- Verrou du moteur, stockage durable protégé du journal et preuve d'arrêt d'un worker précédent.
- Modèle d'acteurs admissibles et isolés pour un cycle intégré, sans requalifier les fixtures ni désactiver leurs exclusions.

La réception d'un SMS, les signatures, les événements de paiement et leur rapprochement restent des preuves distinctes à obtenir sur les mêmes objets du futur parcours intégré.

## Inventaire manuel en lecture seule

Le workflow `.github/workflows/recette-fournisseurs-preflight.yml` se lance uniquement manuellement sur la référence relue. Il exécute les tests hors réseau puis `collect-preflight.mjs`, avec `RECETTE_CANDIDATE_SHA` égal au SHA du checkout GitHub. Il utilise les secrets existants `STAGING_SUPABASE_ACCESS_TOKEN` et `STRIPE_TEST_SECRET_KEY` ; aucun secret n'est demandé par argument ni écrit dans le rapport. Le groupe de concurrence est partagé avec les écritures staging pour éviter un chevauchement de ces workflows.

La cible est fixée à `mejpriaetwgtcstbgfid` et le compte Stripe test attendu à `acct_1T9pt0EVhQ7cb53W`. Aucun paramètre ne permet de les rediriger. La commande n'appelle ni RPC métier, ni Edge, ni transport SMS/paiement. Les seuls POST passent des SELECT fixes à Management API avec `read_only: true`. Les autres appels sont des GET, sans redirection HTTP. Le collecteur ne lit pas `vault.decrypted_secrets` et n'exporte ni valeur/digest de secret, ni URL arbitraire, ni corps d'erreur, ni donnée de compte Stripe.

L'artifact `recette-fournisseurs-preflight.json` contient :

- SHA et empreintes des fichiers sources **commités**, versions des migrations attendues et appliquées, comparaison de leurs listes ;
- présence, version et réglage JWT des sept Edge requises ; empreintes MD5 observées des quatre fonctions SQL sensibles, sans leur définition ;
- présence des seuls noms de configuration attendus ; comptages des crons et deux files financières, sans leurs commandes, identifiants ou données métier ;
- confirmation du compte Stripe et de `livemode=false`, routes webhook exactes vers staging et couverture d'événements, avec pagination bornée.

Ce n'est **pas un inventaire de contenu déployé complet** : les hash locaux ne sont pas comparés aux bundles Edge, les MD5 SQL ne disposent pas encore d'une référence canonique issue de la candidate, l'égalité des valeurs Vault et des signing secrets n'est pas vérifiée, la portée Connect n'est pas déduite d'une URL, les files ne sont pas classées par propriétaire, les cohortes ne sont pas attestées et aucun SMS n'est reçu. Les lectures ne forment pas un snapshot transactionnel. Une liste de noms de secrets ne garantit pas que leurs valeurs sont utilisables.

Ces inconnues sont explicites : la commande termine toujours avec **code 2 / `NON_PRET`**, même si les lectures disponibles réussissent. Le workflow apparaît donc rouge et conserve l'artifact expurgé ; ce rouge attendu ne signifie pas qu'un paiement a échoué. `readyForTransports` et `integratedFlowReady` restent `false`. La bibliothèque pure `preflight.mjs` conserve son contrat et son refus d'exécution directe ; aucune donnée inconnue du collecteur n'est convertie en attestation positive pour ce validateur.

Références des API consultées le 28 septembre 2026 : [requête Supabase avec read_only](https://supabase.com/docs/reference/api/v1-run-a-query), [liste Edge](https://supabase.com/docs/reference/api/v1-list-all-functions), [liste des secrets](https://supabase.com/docs/reference/api/v1-list-all-secrets), [balance Stripe](https://docs.stripe.com/api/balance/balance_retrieve), [webhooks Stripe](https://docs.stripe.com/api/webhook_endpoints/list). Le collecteur ne lance aucune des opérations de création, déploiement ou configuration documentées à côté de ces lectures.

## Raccordement manuel des webhooks TEST

Après la configuration de la clé TEST, le workflow `configure-stripe-webhooks-staging.yml` actualise cinq fonctions du parcours de paiement/facturation puis crée deux endpoints Stripe sur le staging fixé. Il conserve les réglages JWT déjà observés et les authentifications internes. Aucun cron ni paiement n'est déclenché. Il vérifie que les paiements par carte et les transferts sont actifs sur le compte de test ; le collecteur en lecture seule expose désormais ces capacités, sans données d'identité.

Les signatures plateforme et Connect sont distinctes et envoyées directement aux secrets Supabase, sans fichier ni artifact contenant leurs valeurs. Deux sondes signées d'un type volontairement non traité vérifient le bon secret et le rejet du secret opposé, avant toute écriture métier. Elles ne proviennent pas de Stripe et ne constituent pas une preuve de livraison de webhook réel ou de paiement.

Une configuration préexistante ou une réponse ambiguë bloque toute nouvelle installation. Le rapport conserve les tentatives et identifiants connus ; ne pas relancer en supprimant les gardes. Réconcilier les endpoints par projet, route et `metadata.setup_run`, ainsi que le statut de la première écriture, avant toute éventuelle reprise. Le workflow ne supprime aucun endpoint et ne remplace aucun secret existant. Le contrôle du nom `STRIPE_SECRET_KEY` ne prouve pas à lui seul l'identité de la clé chargée par les handlers ; cette attestation reste obligatoire avant la recette financière.

`WEBHOOK_SIGNATURES_CONFIGURED` signifie seulement que le raccordement et ses signatures sont vérifiés. `integratedFlowReady` reste `false` : le paiement, son retour frontend, le remboursement depuis le litige et le rapprochement des mêmes objets Stripe TEST restent à exécuter. La consigne de simulation frontend systématique est enregistrée dans `CLAUDE.md`.

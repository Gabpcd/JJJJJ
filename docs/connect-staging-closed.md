# Préparation fermée de Connect en staging

Ce job prépare le schéma de la recette, sans ouvrir le paiement. Il peut exécuter la migration complète 1017, la vérifier après ROLLBACK, puis l'installer en une seule transaction avec son registre, une table privée d'allocation TEST vide et le supplément d'admission fermé. Il ne crée aucun acteur, capacité active, Checkout, Refund ou transfert. Il ne déploie pas d'Edge et ne configure aucune clé ni aucun webhook.

Le contrat autorise uniquement l'installation fermée du candidat `ee3fc8d5de227495a0ad6dbbe8810a97aff2a3c2` : `ready:true`, `protocolEnabled:false`, `capabilityEnabled:false`. Le préparateur de comptes et son contrat CI restent `ready:false`. Les tests Node de l'exécuteur vérifient ses refus avec des transports simulés ; les preuves PostgreSQL réelles du candidat sont distinctes et liées ci-dessous.

Le 2 octobre 2026, [Validate PR 36949937894](https://github.com/Gabpcd/JJJJJ/actions/runs/36949937894) a réussi sur ce SHA, avec seed exact sous SAVEPOINT/ROLLBACK puis relecture indépendante, référence PostgreSQL 17 et épreuve réelle du delta de schéma staging annulée. Le [run PostgreSQL 17 36949937876](https://github.com/Gabpcd/JJJJJ/actions/runs/36949937876) a également réussi sur ce même SHA. Ces deux runs, leur conclusion, leur dépôt et leur SHA seront relus au dispatch ; les artefacts ne remplacent pas les contrôles frais sur staging.

Les octets Git du candidat ont été recalculés et comparés à l'artefact `connect-catalogue-proof.json`. Le générateur d'admission de l'exécuteur est identique à celui du candidat. Les pins suivants autorisent un seul état source :

| Élément | Empreinte attendue |
| --- | --- |
| Arbre candidat | `3b0b93fd01b4568606c2444da3fd13a4620934ed` |
| Migration SHA256 | `44738cc509c424afa368ec255c49a75b4b2d4c5f3b9542b463093262ab06da2c` |
| Table TEST SHA256 | `3d72d036f0b635a083cd2a505f13f48f436dabccd24f8fc355e9540bf097ec79` |
| Admission générée SHA256 | `c9330111e10c6ddfcd39e8e27b31fd6fa3198b09cb060c0897ef189e5f8f8013` |
| Manifeste SHA256 | `e21e8a8e0b11541e5c42c23f66c207ec0cc79a6c4ed931ad0239164d83f14fcd` |
| Catalogue avant / registre avant | `bbafebd8e479c324a2538cc1b12ca993` / `d3824d9095fc97d300b8e904b9d65609` |
| Catalogue après / registre après | `dfc9a0e06a02d989b3ebdaa55c028eb0` / `bef8b9e4d15b2a26a6a62b8dd4996fae` |

## Source de confiance et déclenchement futur

L'exécuteur doit être intégré seul à main après revue, sans fusionner pour cela la migration financière candidate. Le workflow `connect-staging-closed.yml` s'exécute manuellement sur le SHA main exact qui porte son contrat. Le candidat est un SHA explicitement inscrit dans ce contrat, lié à son arbre Git, aux SHA256 de la migration, de la table et du supplément SQL généré et aux identifiants de runs CI revus. Un autre SHA vert, une branche, un rerun du workflow ou un fork sont refusés. Le candidat n'exécute aucun script : seuls son arbre, sa liste de migrations et les octets des sources SQL désignées sont lus ; le générateur relu de main produit le supplément sans exécuter de script du candidat.

Le manifeste est le SHA256 du JSON canonique `{candidate:{sha,tree},migrationSha256,capacitySha256,admissionSha256}`. Le contrat et les quatre inputs de dispatch doivent correspondre exactement. Un changement du candidat ou du catalogue exige une nouvelle preuve et une revue explicite des pins ; aucun recalage automatique n'est fourni.

La seule destination est `mejpriaetwgtcstbgfid`, sous `jolene-supabase-staging-writes`, `queue:max`, `cancel-in-progress:false`. Les métadonnées Management doivent confirmer projet, région, santé et host canonique. Le seul secret métier reçu est `STAGING_SUPABASE_ACCESS_TOKEN`, jamais envoyé à GitHub ni à un processus enfant. `GITHUB_TOKEN` ne sert qu'aux lectures du dépôt et des runs. Aucun secret DB, service_role ou Stripe n'est demandé.

## Transaction contrôlée

1. Relire main, l'arbre distant du candidat et chaque run CI explicitement désigné. Vérifier la migration, la table et le supplément généré par empreinte et le checkout propre.
2. Acquérir le catalogue en `BEGIN READ ONLY`, UTC, search_path=pg_catalog et timeout20 s : empreinte des corps/droits/objets public/private/auth et de l'inventaire, registre exhaustif, empreinte entière des 16 tables métier/fichiers différés. Aucun contenu de ligne, code SQL ni secret ne sort.
3. Exiger que le registre correspond exactement aux migrations du candidat, sauf 20261001201055 qui doit seule manquer. Toute migration additionnelle, préexistence partielle du moteur/tableTEST, empreinte ou activité inattendue refuse. Les crons, requêtes pg_net, releases/refunds actifs, actions PROCESSING, traces Connect en cours et autres sessionsDB actives doivent être absents. Les anciennes actions différées PENDING sont conservées intégralement et comparées, jamais décalées/claimées.
4. Sous transaction, verrouiller le registre, recontrôler les empreintes, exécuter le vrai corps de migration (ses pré/contrôle finals restent intacts), installer la tableTEST vide puis son supplément d’admission fermé et inscrire la migration. Vérifier le catalogue après migration attendu, barrière fermée, tables moteur et TEST vides, données métier identiques. Annuler toute cette transaction. Confirmer séparément le retour exact au catalogue initial.
5. Relire main. Enregistrer l'intention de COMMIT dans le rapport privé avant un unique POST du même assemblage. Le COMMIT ne peut être atteint qu'après les mêmes assertions. Relire ensuite le catalogue après migration attendu et le registre. Un résultat de transport incertain reste rouge même si une lecture constate ensuite le schéma fermé ; ne jamais renvoyer automatiquement la transaction ou tenter un rollback compensatoire.

Les empreintes structurelles attendues doivent être préparées dans une base PG17 à partir des sources réelles et confrontées au catalogue staging frais, pas inventées ni apprises aveuglément pour obtenir du vert. Le registre attendu inclut la ligne exacte `{version,name,statements:[sourceOriginale]}`. Une divergence de forme du registre doit être traitée avant activation. L'exécuteur ne répare ni ne bascule l'historique.

Les options des relations appartiennent aussi à cette empreinte, triées dans un ordre canonique. Une modification de `security_invoker` ou `security_barrier` d'une vue doit donc être détectée même si sa définition et ses ACL ne changent pas. Le candidat #1017 porte les mutations négatives PostgreSQL 17 correspondantes ; leur preuve réelle appartient aux runs épinglés, et non aux seuls tests de transport de ce lot. Les pins retenus incluent ces options.

## Table TEST et suite indispensable

`private.stripe_connect_test_capacities` est installée vide, propriétaire postgres, RLS et sans droit de table via l'API. Le supplément du candidat #1017 fournit seulement les RPC service bornés décrits dans son document `docs/connect-staging-admission.md`. Ce document, la table de capacité, le SQL d'admission, la migration financière et les handlers restent dans le candidat distinct ; aucun n'est livré par ce petit lot. Il réserve une capacité, les SHA, les acteurs/pièces/objets Stripe exacts, `livemode=false`, au maximum un Checkout et un Refund, zéro transfert et une opération unique. Aucun enregistrement de capacité n'est installé, et le contrôle final refuse toute ligne.

Les handlers ne sont pas déployés par cet exécuteur. L'allocation d'une capacité, les identités Stripe TEST et la configuration `CONNECT_STAGING_TEST_RUN` seront des opérations distinctes revues, après PostgreSQL 17 et avant la recette frontend. Préserver `est_compte_test=true`, les gardes des autres comptes et la porte générale fermée. Une révocation interdit une nouvelle autorisation de POST ; une requête déjà en vol doit être rapprochée ensuite. La consommation de budget ne vaut jamais autorisation permanente.

Le scénario concret reste : une facture identifiée et sa commission réellement générées ; bouton Payer pour ouvrir une Session ; dans un second onglet, bouton Contester de la même facture et RPC canonique à quatre arguments ; confirmer une fois la Session encore ouverte. Le Wizard n'appelle pas l'expirationStripe ; l'expiration appartient à la résolution admin, exclue ici. Si la fenêtre canonique refuse, si la Session n'est plus ouverte ou si le litige exact n'est pas acquis, aucun nouveau Checkout ni faux état ne compense l'échec.

Après ces raccords et leur preuve PG17, la recette réelle utilisera les endpoints TEST déjà configurés et l'UI exacte, sans mocks. Le premier cas est pending→succeeded avec un unique Refund ; les autres rôles/formats observent les mêmes objets et reloads. Le circuit escrow historique ne prouve pas ce circuit. Le détail et les réserves du contrat source séparé restent requis avant cette première confirmation.

## Limites du gel

Les épreuves staging ont appliqué puis annulé leurs transactions ; aucune installation persistante ni activation financière n'a été exécutée par cette préparation de contrat. L'installation de la table vide ne valide ni ses futurs droits d'allocation ni une admission Stripe TEST. Aucun fournisseur, frontend ou appareil physique n'est prouvé par ce lot. Le workflow PostgreSQL du candidat #1017 possède deux entrées de matrice, chacune avec une base et des rôles neufs : moteur initial puis admission TEST. Ce workflow et ses témoins ne sont pas inclus dans le lot exécuteur destiné à main. Leurs résultats réels sont ceux des runs épinglés. Les fonctions Edge candidates doivent ensuite être actualisées par un déploiement borné distinct, sans utiliser les workflows qui réinstallent les clés/webhooks ou réinitialisent staging.

L'API Management SQL est documentée en version bêta ; une réponse inattendue ferme le run ([référence officielle](https://supabase.com/docs/reference/api/v1-run-a-query)). Le rapport publié contient uniquement SHA, phases, codes fermés et booléens. Ni SQL, ni catalogue brut, ni données métier, ni credentials ne deviennent un artefact. Le dépôt est public.

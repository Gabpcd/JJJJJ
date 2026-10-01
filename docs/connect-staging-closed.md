# Préparation fermée de Connect en staging

Ce job prépare le schéma de la recette, sans ouvrir le paiement. Il peut exécuter la migration complète 1017, la vérifier après ROLLBACK, puis l'installer en une seule transaction avec son registre et une table privée d'allocation TEST vide. Il ne crée aucun acteur, capacité active, Checkout, Refund ou transfert. Il ne déploie pas d'Edge et ne configure aucune clé ni aucun webhook.

Le contrat livré est `ready:false`, avec candidat/manifeste/catalogues absents. Il refuse donc avant le premier appel réseau et avant l'étape recevant les secrets. Les 42 tests Node s'exécutent aussi dans Validate PR, indépendamment de cette fermeture. Les tests de transport utilisent des réponses simulées ; le parser du véritable assemblage n'est pas une exécution PostgreSQL.

## Source de confiance et déclenchement futur

L'exécuteur doit être intégré seul à main après revue, sans fusionner pour cela la migration financière candidate. Le workflow `connect-staging-closed.yml` s'exécute manuellement sur le SHA main exact qui porte son contrat. Le candidat est un SHA explicitement inscrit dans ce contrat, lié à son arbre Git, aux SHA256 des deux sources SQL et aux identifiants de runs CI revus. Un autre SHA vert, une branche, un rerun du workflow ou un fork sont refusés. Le candidat n'exécute aucun script : seuls son arbre, sa liste de migrations et les octets de la migration désignée sont lus.

Le manifeste est le SHA256 du JSON canonique `{candidate:{sha,tree},migrationSha256,capacitySha256}`. Le contrat et les quatre inputs de dispatch doivent correspondre exactement. Le prochain SHA 1017 vert doit être relu avant d'y renseigner ces pins ; aucun recalage automatique n'est fourni.

La seule destination est `mejpriaetwgtcstbgfid`, sous `jolene-supabase-staging-writes`, `queue:max`, `cancel-in-progress:false`. Les métadonnées Management doivent confirmer projet, région, santé et host canonique. Le seul secret métier reçu est `STAGING_SUPABASE_ACCESS_TOKEN`, jamais envoyé à GitHub ni à un processus enfant. `GITHUB_TOKEN` ne sert qu'aux lectures du dépôt et des runs. Aucun secret DB, service_role ou Stripe n'est demandé.

## Transaction contrôlée

1. Relire main, l'arbre distant du candidat et chaque run CI explicitement désigné. Vérifier les deux fichiers par empreinte et le checkout propre.
2. Acquérir le catalogue en `BEGIN READ ONLY`, UTC, search_path=pg_catalog et timeout20 s : empreinte des corps/droits/objets public/private/auth et de l'inventaire, registre exhaustif, empreinte entière des 16 tables métier/fichiers différés. Aucun contenu de ligne, code SQL ni secret ne sort.
3. Exiger que le registre correspond exactement aux migrations du candidat, sauf 20261001171439 qui doit seule manquer. Toute migration additionnelle, préexistence partielle du moteur/tableTEST, empreinte ou activité inattendue refuse. Les crons, requêtes pg_net, releases/refunds actifs, actions PROCESSING, traces Connect en cours et autres sessionsDB actives doivent être absents. Les anciennes actions différées PENDING sont conservées intégralement et comparées, jamais décalées/claimées.
4. Sous transaction, verrouiller le registre, recontrôler les empreintes, exécuter le vrai corps de migration (ses pré/contrôle finals restent intacts), installer la tableTEST vide puis inscrire la migration. Vérifier le catalogue après migration attendu, barrière fermée, tables moteur et TEST vides, données métier identiques. Annuler toute cette transaction. Confirmer séparément le retour exact au catalogue initial.
5. Relire main. Enregistrer l'intention de COMMIT dans le rapport privé avant un unique POST du même assemblage. Le COMMIT ne peut être atteint qu'après les mêmes assertions. Relire ensuite le catalogue après migration attendu et le registre. Un résultat de transport incertain reste rouge même si une lecture constate ensuite le schéma fermé ; ne jamais renvoyer automatiquement la transaction ou tenter un rollback compensatoire.

Les empreintes structurelles attendues doivent être préparées dans une base PG17 à partir des sources réelles et confrontées au catalogue staging frais, pas inventées ni apprises aveuglément pour obtenir du vert. Le registre attendu inclut la ligne exacte `{version,name,statements:[sourceOriginale]}`. Une divergence de forme du registre doit être traitée avant activation. L'exécuteur ne répare ni ne bascule l'historique.

## Table TEST et suite indispensable

`private.stripe_connect_test_capacities` est installée vide, propriétaire postgres, RLS, sans policy ni droit API et sans RPC. Sa structure réserve un run, les SHA, les acteurs/pièces/objets Stripe exacts, `livemode=false`, au maximum un Checkout et un Refund, zéro transfert et la liaison unique à une opération. Aucun composant du moteur ou des handlers ne la consulte dans ce lot. Une ligne éventuelle ne constitue donc pas une admission ; le contrôle final refuse même toute ligne.

Le lot suivant doit matérialiser l'allocation fermée et ses consommateurs sous revue, puis seulement autoriser la capacité de ce run : claims dédiés, admissionSQL et revalidation avant chaque création, budgets atomiques, webhook/worker exactsTEST. Il doit préserver `est_compte_test=true`, les gardes des autres comptes et le protocole général fermé. Il doit distinguer révocation avant autorisation de POST (refus) et requête déjà autorisée ou en cours (drain puis constat). La consommation de budget ne vaut jamais autorisation permanente.

Le scénario concret reste : une facture identifiée et sa commission réellement générées ; bouton Payer pour ouvrir une Session ; dans un second onglet, bouton Contester de la même facture et RPC canonique à quatre arguments ; confirmer une fois la Session encore ouverte. Le Wizard n'appelle pas l'expirationStripe ; l'expiration appartient à la résolution admin, exclue ici. Si la fenêtre canonique refuse, si la Session n'est plus ouverte ou si le litige exact n'est pas acquis, aucun nouveau Checkout ni faux état ne compense l'échec.

Après ces raccords et leur preuve PG17, la recette réelle utilisera les endpoints TEST déjà configurés et l'UI exacte, sans mocks. Le premier cas est pending→succeeded avec un unique Refund ; les autres rôles/formats observent les mêmes objets et reloads. Le circuit escrow historique ne prouve pas ce circuit. Le détail et les réserves du contrat source séparé restent requis avant cette première confirmation.

## Limites du gel

Aucune activation ni application staging/prod n'a eu lieu. L'installation de la table vide ne valide ni ses futurs droits d'allocation ni une admission Stripe TEST. Aucun fournisseur, frontend, RLS distant ou appareil physique n'est prouvé par ce lot. La validation du véritable assemblage sous PostgreSQL reste à raccorder avant ouverture du contrat. Les fonctions Edge et le générateur staging doivent ensuite être actualisés par un déploiement borné distinct, sans utiliser les workflows qui réinstallent les clés/webhooks ou réinitialisent staging.

L'API Management SQL est documentée en version bêta ; une réponse inattendue ferme le run ([référence officielle](https://supabase.com/docs/reference/api/v1-run-a-query)). Le rapport publié contient uniquement SHA, phases, codes fermés et booléens. Ni SQL, ni catalogue brut, ni données métier, ni credentials ne deviennent un artefact. Le dépôt est public.

# Tableau de bord établissement : périmètre unique

Le tableau de bord pouvait afficher un contenu principal vide après connexion. Il résolvait un périmètre absent, puis montait `AccesEtablissement` avec des enfants nuls. Ce composant relançait une résolution indépendante ; si le cache contenait alors un établissement, il rendait ces enfants nuls. Le rôle signé `ADMIN_ETABLISSEMENT` sans identifiant de périmètre et un RPC concurrent en erreur suffisent à reproduire ce chemin.

`EtatAccesEtablissement` reçoit désormais le périmètre déjà résolu par la page. Le composant `AccesEtablissement` conserve son propre hook pour les autres consommateurs. Les branches d'affichage, le bouton de reprise, les protections Auth/RLS, le cache, les délais et les requêtes métier sont inchangés. Aucun identifiant d'établissement n'est déduit d'un rôle ou d'une identité supplémentaire.

## Témoin avant correction

Sur le build admin conservé, les fichiers App/Auth/rôle/périmètre/tableau de bord sont identiques à la base `18dd15ae69b3ac88763bc4d157a6b6abc05d6955`. Six parcours Android font échouer successivement un des six RPC rôle concurrents : réponse 503 après 1 200 ms, autres réponses après 100 ms. Le cas d'indice 4 présente un `#main-content` exactement vide ; les cinq autres passent. Capture, trace et HTML vide sont conservés. Le témoin n'a été ni réécrit ni remplacé après correction.

## Vérifications du candidat

- 26 tests unitaires : tableau de bord, `useRole`, `useEtablissementScope`. La régression unitaire simule une seconde lecture qui verrait un autre cache et vérifie que le bouton appelle bien la reprise de la page.
- TypeScript application et spec : succès ; build réel : succès ; 17 garde-fous : succès.
- 20 parcours frontend, soit quatre scénarios sur iPhone, Android, iPad portrait, iPad paysage et ordinateur : scope valide puis perdu (réponse 200 avec identifiant nul), indisponibilité 503 puis reprise, compte minimal avec navigation vers la préparation de mission, réponses concurrentes divergentes. Chaque scénario recharge ensuite la page. Aucun retry, skip ou flaky ; durée 80,641 s.
- Clics/taps normaux, aucune interaction forcée, aucun CSS injecté. Captures viewport et arbres ARIA conservés ; des captures représentatives des cinq formats ont été inspectées.

Le banc ferme les WebSockets et les service workers ; les requêtes externes sont refusées, hors ressources explicitement remplacées localement par le helper existant. Les RPC autorisés sont listés. Les appels d'audit de connexion et de présence sont des réponses inertes simulées ; aucune écriture métier ne sort du navigateur. Les réponses 503 injectées sont conservées dans le rapport avec toutes les sorties console. Seules leurs erreurs réseau attendues sont distinguées des autres erreurs, qui font échouer la recette.

## Preuves et limites

Dossier local : `/private/tmp/jolene-dashboard-blanc-preuves-20261001`, avec `validation.json`, `SOURCES.sha256`, `SHA256SUMS`, `rouge-v1.json`, `matrice-finale/results.json` et les captures. Build corrigé : `/private/tmp/jolene-dashboard-scope-dist-20261001`. Le preview 18490 est arrêté.

Les premiers contrôles incomplets du checkout sparse et l'interdiction système initiale de lancer le navigateur sont conservés séparément. Les fichiers suivis manquants ont été matérialisés avant les contrôles complets. Un premier pilote frontend a aussi identifié un RPC de lecture déjà présent dans le helper mais omis de la liste locale : il a été ajouté explicitement, sans changement produit.

La revue source indépendante de V11 porte sur le partage de l'état, pas sur une exécution indépendante. Cette recette est une simulation de réponses ; elle ne reproduit pas nécessairement toutes les causes du flaky de connexion distant. Aucun compte réel, backend cloud, fournisseur, appareil physique ou livraison mobile n'a été utilisé. La CI et la revue de l'intégration exacte restent à terminer avant fusion.

## Injection déterministe après le rouge CI Android du 01/10

Le job `110439094564` sur la PR au head `60240b8e` a passé 141 scénarios sur 142. Le seul rouge attendait une réponse 503 au cinquième appel rôle. La trace contient exactement quatre appels, tous 200, et la capture montre le dashboard correctement rendu. Le cache partagé peut être rempli avant le montage des autres consommateurs : un numéro global de requête n'est donc pas un déclencheur fiable. L'artefact et la première campagne locale restent conservés ; ce rouge ne démontre pas une nouvelle panne du produit.

Le scénario divergent part désormais d'un état sans rattachement explicitement affiché après les réponses 503. Un premier clic/tap réel sur Réessayer retient sa lecture ; un second clic/tap obtient une réponse valide. Le test exige alors le dashboard prêt et un contenu principal non vide, libère la première réponse, revérifie l'écran puis recharge. Aucun timeout, retry, contrôle réseau ou assertion d'écran n'est allégé. Il ne dépend plus du nombre d'appels initiaux.

Sur l'ancien build conservé, ce même scénario échoue bien après le second succès RPC : l'ancien wrapper rend ses enfants nuls, la capture montre le main blanc et l'assertion `dashboard-etablissement-ready` échoue. Sur le build corrigé conservé, les 20 parcours des cinq formats passent en 80,305 s, sans retry, skip ou flaky ; 40 captures sont conservées et celles de la reprise concurrente ont été inspectées sur les cinq formats. Les deux builds et leurs sources sont ceux de la preuve initiale ; aucun produit n'a été changé ou rebâti pour ce complément.

Le navigateur annule l'ancienne requête lors de la seconde reprise, ce que le rapport trace séparément (`abandonnee`). Cela ne prouve pas qu'une réponse tardive a été reçue par le navigateur. Un nouveau test du vrai `useRole` livre volontairement l'ancienne erreur malgré l'AbortSignal et vérifie que ni l'état de la page ni le cache partagé ne sont remplacés. 27 tests unitaires et les contrôles TypeScript application/spec passent. La revue source indépendante V11 n'a relevé aucun blocage ; la nouvelle CI Linux reste requise.

Preuves de ce complément : `/private/tmp/jolene-dashboard-injection-preuves-20261001` (`rouge-ancien`, `pilote-corrige`, `matrice-finale`, `reseau-ci-initial.json`, `validation.json`, `SHA256SUMS`). Le preview 18490 a été arrêté après la campagne.

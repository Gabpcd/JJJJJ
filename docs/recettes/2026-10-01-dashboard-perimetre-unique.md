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

# Revue indépendante — fluidité et exploration

Comparaison : branche `fix/fluidite-mobile-etats-comptes`, arbre de travail du 23 septembre 2026, base `29d383b5`.
Revue en lecture seule du dépôt. Aucun navigateur ou simulateur piloté. Instructions lues : `CLAUDE.md`, `INSTRUCTIONS.md`, `.claude/skills/verify-recette/SKILL.md`.

## Verdict final de revue de code : CLÔTURABLE

Les P2 relevés ont été corrigés et relus. Aucun P1/P2 ouvert dans le périmètre inspecté. Ce verdict porte sur la revue de code ; les vérifications CI et la recette finale du device restent à joindre par l’agent principal.

### [P2 résolu] Rafraîchir les données du profil dans la navigation désormais persistante

Emplacement introduisant la régression : `src/components/LayoutApp.tsx:28-35` (cadre persistant), `src/App.tsx:309` (routes soignant imbriquées). Lecteur concerné : `src/components/BarreNavigation.tsx:308-328`.

`BarreNavigation` charge `statut_liberal`, `type_exercice`, nom et avatar dans un effet dépendant uniquement de `[role, user]`. Avant ce changement, la navigation était remontée par chaque page. Elle reste maintenant montée après une sauvegarde du profil ou une activation libérale et un retour vers un autre onglet. L'identité Auth reste volontairement stable : les mutations métier ne changent pas `user`.

Reproduction par chaîne de code :
1. Se connecter avec un profil salarié éligible au libéral ; la navigation initialise `isLiberal=false` et affiche « Passer en libéral ».
2. Dans `/soignant/profil`, enregistrer un mode LIBERAL/MIXTE : `ProfilSoignant.tsx:253-273` appelle `fn_modifier_mon_profil`, puis `refresh()` augmente seulement le compteur local `refreshKey`. Ou terminer `/soignant/passer-en-liberal` : `FinaliserInstallationLiberal.tsx:145-157` appelle `fn_activer_liberal`, puis relit seulement son état local.
3. Revenir à l'accueil ou aux revenus : le même `BarreNavigation` conserve l'ancien état. Les liens desktop « Stripe Connect » et « Mandat facturation » restent absents et le parcours libéral reste affiché jusqu'au rechargement complet.

Le correctif relu remplace les états figés par des données de query et des valeurs dérivées. Il invalide les lectures après mutations. Le scénario LIBERAL→SALARIE est explicitement couvert, ainsi que l’activation libérale, l’édition du profil, l’avatar/logo et le nom établissement.

## Relecture du correctif

La navigation utilise désormais une query `navigation-profil` indexée par utilisateur, rôle et établissement. Le mode libéral et les liens sont dérivés des données dans les deux sens. Les mutations du profil, l’activation libérale, l’avatar/logo et le nom établissement invalident les clés concernées. Le périmètre établissement est lu dans `useEtablissementScope`, et non dans la valeur d’argument du hook permissions. Cette partie est corrigée.

Vérification indépendante supplémentaire : **25/25 tests réussis**, répartis entre `BarreNavigation.test.tsx` (16), `useEtablissementScope.test.ts` (5) et `ProfilEtablissement.sepa.test.tsx` (4). Le test SALARIE→LIBERAL→SALARIE confirme les liens exacts et la conservation du même élément de navigation.

### [P2 résolu] Invalider les lectures Explorer après modification des documents

État relevé avant correction : `useExplorationMissions.ts:117-127` conservait la RCP pendant 60 secondes, sans invalidation depuis `DocumentsSoignant`. La fonction de rafraîchissement Explorer (`:145-147`) ne relit que les missions si le profil n’est pas en erreur.

Reproduction : ouvrir Explorer avec une RCP valide ; supprimer ou remplacer ce document dans Documents ; revenir à Explorer en moins de 60 secondes. Le cache conserve alors l’ancienne RCP et le statut `tous_documents_valides`, et un pull-to-refresh ne les actualise pas. L’état peut rester affiché jusqu’à un nouveau montage/focus après expiration. Les gates serveur demeurent actifs, mais les alertes du dossier deviennent obsolètes à cause du nouveau cache.

Correction vérifiée : `DocumentsSoignant.charger()` invalide désormais les lectures `explorer-profil` et `explorer-rcp` du seul utilisateur courant après succès, y compris après upload, suppression, revérification et polling. La lecture RCP filtre aussi `supprime_le IS NULL` : les anciens justificatifs supprimés ne sont plus réutilisés. Le test de suppression confirme l’invalidation du compte concerné et la préservation du cache d’un autre compte. La suite Documents (8 tests) et Explorer (6 tests avant ajout du cas RCP) a été relancée indépendamment : 14/14 réussis. Après ajout du scénario RCP supprimée puis remplacée, nouvelle exécution indépendante du hook Explorer : **7/7 réussis** (17:10:57).

## Vérifications effectuées

Commande :

```sh
npx vitest run src/components/ScrollToTop.test.tsx src/components/LayoutApp.navigation.test.tsx src/components/swipe/StackCards.gestures.test.tsx src/hooks/useExplorationMissions.test.tsx src/hooks/useMemoireExploration.test.tsx src/components/MissionsPubliques.test.tsx src/pages/Etablissement.exploration.test.tsx src/pages/RechercheMissions.navigation.test.tsx --maxWorkers=1 --minWorkers=1
```

Résultat : **8 fichiers, 55 tests réussis**, 17,56 s. Ces tests couvrent shell persistant, retour et scroll différé, gestes courts/horizontaux/verticaux/annulés, erreurs et cache Explorer, isolation des comptes, absence de requêtes métier avant dossier établissement, recherche publique vide/en panne/annulée/périmée et reprise.

Constats complémentaires :
- Les mêmes rôles autorisés protègent les routes déplacées sous AppShell ; `RouteProtegee` conserve les vérifications de session, confirmation email, rôle serveur et redirections du profil incomplet.
- `AccesEtablissement` ne monte pas les rubriques métier sans scope. Le `Fragment` indexé par utilisateur et établissement évite la réutilisation d'états de la rubrique entre deux périmètres.
- Les gates candidature/publication ne sont pas retirés par ces changements.
- Le stockage des critères Explorer est isolé par compte ; la page est indexée par `user.id`, et le cache est vidé à la déconnexion.
- Le déplacement de rémunération dans le détail conserve les conditions, montants et actions existants.
- L'extraction Leaflet conserve les actions et utilise `textContent` pour les contenus de popup. Le lien mission préserve les clics modifiés et évite un rechargement document pour le clic simple.

## Symptômes WebKit signalés : diagnostic limité au code

### ResizeObserver loop

La dernière version de `ScrollToTop` observe `#app-route-content`, le conteneur stable autour d’`AppRoutes`, avec `document.body` en repli. Le conteneur permet de suivre la hauteur des listes chargées après la navigation, contrairement au body à hauteur fixe. L’observation reste limitée à une restauration non achevée et s’arrête dès la position atteinte, sur interaction ou après trois secondes. Sur un premier chargement à 0, elle s’arrête immédiatement.

`SelectProfession` mesure désormais la largeur du bouton avant chaque ouverture du Popover et transmet une largeur numérique fixe, au lieu de dépendre de la variable de dimensionnement Radix. La contrainte de largeur au viewport reste présente, et chaque réouverture remesure le bouton. Cette modification retire une dépendance de dimensionnement susceptible d’entretenir la boucle Safari ; la disparition du symptôme exige la recette WebKit de l’agent principal. Aucun masquage global des erreurs n’a été ajouté.

### AbortError « Lock was stolen »

Le SDK Auth installé définit `lockAcquireTimeout=5000` (`node_modules/@supabase/auth-js/src/GoTrueClient.ts:177`) et utilise `navigator.locks.request(..., {steal:true})` pour récupérer le verrou (`src/lib/locks.ts:199-224` dans ce paquet). Le client public dispose d'un `storageKey` distinct (`jolene-public-search`), sans persistance ni refresh. Le hook public n'ajoute donc pas de verrou Auth partagé. `AuthContext` possède un `getSession().then(...)` sans traitement du rejet, préexistant au diff, qui peut exposer le rejet d'un verrou lors d'un reload. La cause navigateur exacte reste à établir avec le scénario E2E ; supprimer globalement les erreurs ne constituerait pas une correction.

La recette E2E WebKit, les deux viewports établissement et la validation finale du device restent réalisés par l'agent principal. La revue de code ne remplace pas ces preuves.

## Dernière relecture bornée

Les cinq derniers changements demandés ont été relus, sans modification des fichiers produit ni pilotage du navigateur ou du simulateur. Aucun nouveau P1/P2 démontré ; verdict **CLÔTURABLE côté revue de code** maintenu.

- `ScrollToTop.tsx` : cible d’observation stable présente dans `App.tsx` ; arrêt et nettoyage de la restauration conservés. Les callbacks ne modifient pas le contenu observé.
- `SelectProfession.tsx` : largeur mesurée avant ouverture, bouton avec ref transmise, limite viewport conservée ; sélection et fermeture inchangées. Le Drawer mobile conserve son comportement.
- `index.css` : `flex: none` et padding appliqués aux cartes Auth natives iOS/Android par les sélecteurs de plateforme ; aucune extension de ces règles aux pages web. La police système iOS dispose d’une pile de repli explicite.
- `vite.config.ts` : la transformation HTML retire uniquement les liens Google Fonts lorsque `VITE_NATIVE_BUILD=true`. Les trois liens présents dans `index.html` correspondent au motif ; le build web conserve son HTML et les polices natives ont des replis CSS.
- `DocumentsSoignant.tsx` : un mode d’exercice absent n’est plus assimilé à salarié. Les justificatifs communs restent affichés, une notice mène au profil et le texte de succès ne prétend plus que tous les documents obligatoires sont à jour. Aucune modification des gates serveur ni des permissions.

Cette dernière passe est une lecture de code. Aucune nouvelle exécution de tests n’a été lancée pendant la CI locale et la recette iOS menées en parallèle par l’agent principal. Les exécutions indépendantes précédentes sont celles détaillées plus haut.

## Complément — score inconnu en exploration, après `020ffac`

Revue ciblée du diff non commité sur `src/lib/explorationInscription.ts`, `src/components/swipe/CardMissionSwipe.tsx` et `src/components/swipe/ModalDetailMissionSwipe.tsx`, ainsi que de leurs tests. **CLÔTURABLE côté code**, aucun P1/P2 relevé.

Le mapper d’inscription ne fabrique plus un score de matching de zéro lorsqu’aucun calcul n’a eu lieu : il renvoie `null`. Le type de payload admet cette absence. Les deux rendus vérifient `score != null`, de sorte que zéro reste une valeur connue. Pour un score inconnu, le badge, la phrase de score dans le nom accessible de la carte et les sections « Pourquoi » sont absents. Les scores calculés 0 et 85 conservent leur badge, leur libellé accessible et leur explication. Les routes des profils complets conservent les scores renvoyés par leur RPC ; les autres usages du payload ne font pas d’arithmétique sur le score.

Les badges urgence/paiement rapide restent présents avec leurs conditions existantes ; ouverture du détail et candidature ne changent pas. Aucun contrôle d’accès, tarif ou calcul financier n’est modifié. Le déplacement visuel des badges vers la droite n’introduit pas de défaut démontré à la lecture.

Vérification indépendante exécutée à 17:46:56 : `npx vitest run src/lib/explorationInscription.test.ts src/components/swipe/MissionScore.test.tsx --maxWorkers=1 --minWorkers=1` : **2 fichiers, 9/9 tests réussis, 3,54 s**. Les tests incluent le mapper paginé, les cas null/0/85 sur carte et détail, le nom accessible, l’ouverture de carte et les badges conservés.

La tâche principale rapporte une CI **1 500/1 500 verte sur `020ffac159c76d32fbde603126d322469a78ed1b`**, antérieure à ce complément. Ce résultat n’est pas attribué au prochain commit. Son nouveau passage CI et le smoke natif après reconstruction restent à attendre.

Complément natif communiqué par la tâche principale, sur iPhone 16 Pro Max simulé / iOS 18.6, bundle isolé `app.jolene.recette`, API locale 8781 : probe signup XCTest vert (18 s), inscription soignant avec clavier/sélecteur puis Explorer verte (26,55 s), cinq onglets et Parrainage observés par taps/captures ; inscription établissement minimale, cinq onglets et saisie du titre mission sans dossier : un XCTest vert (114,21 s). Aucun total de tests natifs non confirmé n’est déduit de ces observations. **Documents n’a pas été testé nativement** : aucun lien dans le menu du compte minimal et aucune association deeplink du bundle temporaire. Cette rubrique dispose de sa couverture WebKit/Chromium 390/1440. Les observations sur simulateur ne valent ni recette sur appareil physique, ni preuve du backend live, ni validation native du nouveau correctif de score.


## Preuves finales rattachées par la tâche principale

Après la revue indépendante ci-dessus, reconstruction native réussie et smoke `testExplorerMisAJour` vert (1 test, zéro échec, 45,92 s) : aucun score fictif, ouverture et fermeture du détail par tap. Les trois scénarios Swipe Chromium/Pixel/WebKit iPhone sont également verts après ce complément (23,4 s), ainsi que TypeScript. Les captures finales et arbres sont archivés dans [natif](../../recette/2026-09-23-fluidite/natif/). Cela complète la limite native signalée ci-dessus ; le nouveau passage CI reste distinct du résultat de `020ffac`.

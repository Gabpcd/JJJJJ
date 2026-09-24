# Recette native iOS — 23 septembre 2026

Application détenue de recette `app.jolene.recette`, version du conteneur 1.0.4/build 9999 (les assets frontend correspondent à la correction prévue pour 1.0.5/22), dans `/private/tmp/jolene-native-recette-20260923`. Simulateur iPhone 16 Pro Max, iOS 18.6, identifiant E65C6EA3-B3BD-4411-B9C5-38B29E8826CB. L’application est une copie locale ; le backend est une simulation Python sur `http://127.0.0.1:8781`. Aucun compte utilisateur réel, donnée de production, publication de mission, candidature réelle, message ou opération de paiement n’a été utilisé.

## Résultats constatés

- `testInscriptionEtNavigation` : **1 test passé**, 26,55 secondes. Saisie native email/mot de passe, sélecteur natif de profession IDE, acceptation CGU, création du compte simulé puis arrivée sur Explorer. Preuves : `soignant-explorer.png` et `soignant-explorer.txt`, ainsi que le sélecteur natif. Résultat source : `/private/tmp/jolene-native-recette-20260923/signup.xcresult`.
- Cinq onglets soignant visités par leurs boutons natifs : Accueil, Mes missions, Revenus, Profil, Explorer. La barre de navigation est présente à chaque écran. Parrainage affiche bien l’absence de lien pour le dossier non créé, avec retour vers l’exploration. Captures et arbres : `soignant-onglet-*.png`, `soignant-onglet-*-accessibilite.txt`, `soignant-parrainage.png`, `soignant-parrainage-accessibilite.txt`. Le scénario `navigation-v4.xcresult` a ensuite échoué sur une tentative d’ouverture directe de Documents via un lien universel dans le bundle de recette : la route n’a pas été reçue et l’application a redémarré sur Explorer. Il ne constitue donc pas une suite entièrement verte et ne valide pas Documents nativement. Ce lien de recette n’est pas associé au domaine réel. Aucun comportement du build signé n’en est déduit.
- `testEtablissementCinqOngletsEtPreparation` : **1 test passé**, 114,21 secondes. Déconnexion du compte simulé soignant, inscription minimale établissement, cinq onglets Missions/Publier/Messages/Menu/Accueil par taps, retour au formulaire Publier et saisie de l’intitulé. Le formulaire est accessible sans dossier préalable. Aucune publication. Source : `/private/tmp/jolene-native-recette-20260923/etablissement.xcresult`. Captures et arbres `etablissement-*`.

## Captures clavier

`etablissement-formulaire-mission-clavier.png` provient de `XCUIScreen.main.screenshot()` et montre le clavier iOS AZERTY, le champ saisi et le formulaire. Les captures de champ de mot de passe montrent une zone noire à l’emplacement du clavier, avec `app.screenshot()` comme avec `XCUIScreen.main.screenshot()` ; l’arbre d’accessibilité contient bien Keyboard et les saisies réussissent. Elles ne servent pas à valider visuellement le rendu du clavier sécurisé. L’assertion `app.keyboards.firstMatch.exists` a réussi pendant l’inscription établissement.

## Portée et limites

Ces vérifications portent sur la navigation et les états de comptes incomplets dans le véritable conteneur iOS/WKWebView, avec données simulées. Ce ne sont ni des tests de paiement/contrat réels ni une mesure de FPS sur un iPhone physique. Documents est couvert par les tests navigateur Chromium/WebKit de la recette principale, pas par ce scénario natif. L’invitation aux notifications a été fermée par « Plus tard » ; aucune autorisation système n’a été accordée.

Le premier lot de captures Explorer contient encore le badge de score fictif 0/100 ; il a servi à identifier le correctif complémentaire. Le smoke final sur les assets corrigés a passé : `testExplorerMisAJour`, **1 test, 0 échec, 45,92 secondes**, résultat `/private/tmp/jolene-native-recette-20260923/explorer-final.xcresult`. Il vérifie que le bouton de mission n’annonce plus « score 0 » et qu’aucun badge 0/100 n’apparaît, puis ouvre et ferme le détail par taps. Captures finales : `soignant-explorer-sans-score-fictif.png` et `soignant-detail-swipe.png`, chacune accompagnée de son arbre `*-accessibilite.txt`.

## Exécution

Correction de l’outillage exclusivement dans la copie temporaire : ajout `PRODUCT_NAME = "$(TARGET_NAME)"` aux deux configurations de la cible `JoleneRecetteUITests`. Aucun fichier du dépôt produit n’a été modifié pour ces tests.

```sh
cd /private/tmp/jolene-native-recette-20260923
xcodebuild test -project ios/App/App.xcodeproj -scheme JoleneRecette \
  -destination 'platform=iOS Simulator,id=E65C6EA3-B3BD-4411-B9C5-38B29E8826CB' \
  -derivedDataPath /private/tmp/jolene-native-recette-20260923/DerivedData \
  -resultBundlePath /private/tmp/jolene-native-recette-20260923/etablissement.xcresult \
  -parallel-testing-enabled NO -skipPackageUpdates \
  -only-testing:JoleneRecetteUITests/NavigationTests/testEtablissementCinqOngletsEtPreparation \
  CODE_SIGNING_ALLOWED=NO
```

Le smoke final utilise la même commande, avec `-only-testing:JoleneRecetteUITests/NavigationTests/testExplorerMisAJour` et le résultat `explorer-final.xcresult`.

Le chemin `.xcresult` doit être neuf à chaque exécution. Source temporaire des tests : `/private/tmp/jolene-native-recette-20260923/ios/App/JoleneRecetteUITests/NavigationTests.swift`.

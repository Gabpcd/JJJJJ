# iPhone et iPad — pilote existant

Projet XCTest UI autonome : compile uniquement le runner de vérification, puis
active l’application Expo Go déjà installée (`host.exp.Exponent`). Il ne compile
pas Jolene, n’installe pas de nouvelle version de Jolene et ne réinitialise aucune
donnée. Le runner CI ouvre l’URL `exp://` du bundle préparé avant le test portrait.

Sur iPad, les deux méthodes suivantes de `NativePilotTests` s’exécutent séparément,
dans cet ordre, sur le même simulateur et la même expérience Expo Go :

- `testPortraitConsultation` prépare Expo Go puis vérifie la connexion démo,
  les 30 missions, les filtres Libéral (10) et CDD (20), la recherche sans résultat,
  la remise à zéro des filtres (30), le défilement vers la mission 16, son détail,
  le retour par geste avec position conservée, la reprise après Home/activation,
  puis les parcours détaillés ci-dessous et les déconnexions avec confirmation native.
- `testLandscapeConsultation` reprend l’expérience laissée déconnectée par le
  portrait. Il vérifie les 30 missions, la mission 16 après défilement, son détail,
  le retour par geste avec position conservée, puis les mêmes parcours supplémentaires.

Sur un simulateur iPhone neuf distinct, `testIphoneConsultation` appelle le même
parcours portrait partagé, avec toutes les mêmes assertions. Seuls le nom de
l’appareil dans le diagnostic d’orientation et le préfixe des captures changent.
Le paysage reste propre à l’iPad. Cette méthode remplace le pilotage Maestro de
l’iPhone ; elle ne modifie pas l’application ni la préparation Expo validée en
portrait sur iPad.

Les trois formats iOS exécutent ensuite les mêmes étapes :

- Changer d’onglet puis retrouver la mission 16 à la même position ; ouvrir sa
  candidature, lire le planning, vérifier que l’envoi est désactivé avant
  confirmation, confirmer, relire le résultat fictif avec « Actualiser le dossier ».
- Retrouver cette candidature dans « Mes missions », ouvrir son dossier, utiliser
  « Voir mes missions » pour revenir à la liste, puis retrouver la pile et la
  position de l’exploration par les gestes de retour.
- Modifier la biographie, enregistrer, vérifier la confirmation et la fermeture
  du clavier, changer d’onglet, revenir et tirer pour actualiser avant de relire
  la valeur conservée. La sauvegarde reste uniquement en mémoire de démonstration.
- Après déconnexion, ouvrir le compte établissement fictif, vérifier son identité,
  filtrer ses 12 missions pour obtenir les 2 ouvertes, ouvrir la mission 1,
  contrôler ses deux créneaux, revenir par geste avec filtre et carte conservés,
  puis consulter son rôle et sa permission de lecture avant déconnexion.
- Ouvrir le formulaire fictif médecin/interne, passer du deuxième au troisième
  cycle, constater la disparition de l’année et l’absence d’équivalence AS,
  enregistrer le brouillon puis terminer. Le profil médecin doit voir une liste
  vide : les fixtures IDE ne lui deviennent pas accessibles. Cela ne prouve
  aucune qualification professionnelle ni validation documentaire.

Les boutons de démonstration de la connexion restent atteints par un défilement
borné dans `login-scroll`, notamment sur iPad paysage. Aucun scénario n’est sauté
si un contrôle n’est pas visible. Le scénario Android
`mobile-native/maestro/consultation.yaml` reprend les mêmes assertions fonctionnelles,
avec retour système Android et reprise de l’expérience existante par son URL.
Le formulaire public de création de compte et l’envoi d’email de confirmation
ne sont pas couverts par ces scénarios sans réseau.

La préparation portrait traite l’éventuelle confirmation système Open/Ouvrir
avant d’activer Expo. Elle exige le tutoriel de l’installation neuve, tape une
seule fois sur le vrai bouton natif Continue et exige sa disparition. Le libellé
SDK visible derrière la feuille ne suffit pas. Dans le menu Expo SDK 57,
« Tools button » est un texte distinct du `Toggle` sans libellé : le test cible
le switch natif visible sur cette ligne, vérifie sa valeur 0/1 et ne le tape que
s’il est activé. Il exige ensuite la valeur 0 avant de fermer le menu par le
bouton `xmark`. Aucune coordonnée absolue ni modification de préférences cachée.

Les gestes de défilement et de retour utilisent les coordonnées relatives des
vues natives dans leur orientation courante. Aucun fallback vers un bouton de
retour, relancement, rechargement ou réessai ne masque un échec du parcours.
L’activation après Home reprend l’expérience existante. Chaque test dispose de
600 secondes maximum pour les trois parcours de démonstration. La préparation attend jusqu’à 120 secondes le tutoriel ;
les autres attentes et les boucles de défilement sont bornées.

Depuis la racine du dépôt, avec le simulateur iPad déjà démarré et l’URL ouverte :

```sh
xcodebuild test \
  -project mobile-native/ios-ui-tests/NativePilotUITests.xcodeproj \
  -scheme NativePilotUITests \
  -destination "platform=iOS Simulator,id=$JOLENE_IPAD_UDID" \
  -derivedDataPath "$JOLENE_XCTEST_OUTPUT/DerivedData" \
  -resultBundlePath "$JOLENE_XCTEST_OUTPUT/portrait.xcresult" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:NativePilotUITests/NativePilotTests/testPortraitConsultation \
  CODE_SIGNING_ALLOWED=NO

# Exécuter seulement après la réussite du portrait, sans rouvrir ni réinitialiser l’expérience.
xcodebuild test \
  -project mobile-native/ios-ui-tests/NativePilotUITests.xcodeproj \
  -scheme NativePilotUITests \
  -destination "platform=iOS Simulator,id=$JOLENE_IPAD_UDID" \
  -derivedDataPath "$JOLENE_XCTEST_OUTPUT/DerivedData" \
  -resultBundlePath "$JOLENE_XCTEST_OUTPUT/landscape.xcresult" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:NativePilotUITests/NativePilotTests/testLandscapeConsultation \
  CODE_SIGNING_ALLOWED=NO
```

Pour l’iPhone, utiliser la première commande avec son propre simulateur
`JOLENE_IPHONE_UDID`, un résultat distinct `iphone-portrait.xcresult` et
`-only-testing:NativePilotUITests/NativePilotTests/testIphoneConsultation`.
Ne pas exécuter tous les tests ensemble : chacun des deux tests portrait suppose
une installation Expo Go neuve, tandis que le paysage reprend la session iPad.

Pour chaque résultat (ici le portrait iPad) :

```sh
xcrun xcresulttool get test-results summary \
  --path "$JOLENE_XCTEST_OUTPUT/portrait.xcresult" \
  > "$JOLENE_XCTEST_OUTPUT/portrait-summary.json"
xcrun xcresulttool export attachments \
  --path "$JOLENE_XCTEST_OUTPUT/portrait.xcresult" \
  --output-path "$JOLENE_XCTEST_OUTPUT/portrait-attachments"
```

La preuve exige `passedTests: 1`, `failedTests: 0`, `skippedTests: 0` pour chacune
des invocations. Captures conservées dans le résultat :

- iPhone portrait : `iphone-portrait-connexion`, `iphone-portrait-missions`,
  `iphone-portrait-detail`, `iphone-portrait-retour`.
- iPad portrait : `ipad-portrait-connexion`, `ipad-portrait-missions`,
  `ipad-portrait-detail`, `ipad-portrait-retour`.
- iPad paysage : `ipad-paysage-connexion`, `ipad-paysage-liste`,
  `ipad-paysage-detail`, `ipad-paysage-retour`.

Chaque format conserve aussi les suffixes suivants, précédés de son préfixe
(`iphone-portrait-`, `ipad-portrait-`, `ipad-paysage-`) :

- `candidature-confirmee`, `mes-missions`, `dossier-relu`, `profil-relu` ;
- `etablissement-accueil`, `etablissement-missions`, `etablissement-planning`,
  `etablissement-retour`, `etablissement-acces` ;
- `inscription-internat`, `inscription-terminee`.

Android utilise ces mêmes suffixes sans préfixe, en plus de `connexion`,
`missions`, `detail` et `retour`. Les fichiers décrivent les assertions attendues ;
seuls les résultats de l’exécution CI et leurs captures attestent leur réussite.

Chaque capture utilise `XCTAttachment(screenshot: XCUIScreen.main.screenshot())` :
l’écran iOS entier est conservé avec ses métadonnées d’orientation, sans recadrage,
rotation ni traitement des pixels. Chaque capture est accompagnée de la
hiérarchie d’accessibilité de l’application. En cas d’échec réellement enregistré
(`totalFailureCount > 0`, assertions ou exceptions), le résultat conserve aussi
l’écran système et la hiérarchie SpringBoard. `hasSucceeded` n’est pas utilisé
pendant le teardown, car le test n’est pas encore déclaré terminé à cet instant. Utiliser `attachments/manifest.json`, `exportedFileName` et
`suggestedHumanReadableName` pour exporter les PNG nommés, sans présumer les noms
générés par Xcode.

Ces tests prouvent uniquement le parcours natif du pilote sur simulateur avec
données fictives. Ils ne prouvent ni un paiement, ni une intégration STAGING,
ni le comportement d’un appareil physique, ni les autres écrans de Jolene.

Références : [contrôles Expo Go SDK 57](https://github.com/expo/expo/blob/sdk-57/apps/expo-go/ios/Exponent/DevMenu/SwiftUI/DevMenuButtons.swift),
[en-tête Expo Go](https://github.com/expo/expo/blob/sdk-57/apps/expo-go/ios/Exponent/DevMenu/SwiftUI/HeaderView.swift),
[application externe XCTest](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(bundleidentifier:)),
[activation](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/activate()),
[orientation](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/orientation),
[geste relatif](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press(forduration:thendragto:)),
[capture attachée](https://developer.apple.com/documentation/xctest/xctattachment/init(screenshot:)).

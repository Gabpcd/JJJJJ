# iPad portrait et paysage — pilote existant

Projet XCTest UI autonome : compile uniquement le runner de vérification, puis
active l’application Expo Go déjà installée (`host.exp.Exponent`). Il ne compile
pas Jolene, n’installe pas de nouvelle version de Jolene et ne réinitialise aucune
donnée. Le runner CI ouvre l’URL `exp://` du bundle préparé avant le test portrait.

Les deux méthodes de `NativePilotTests` s’exécutent séparément, dans cet ordre,
sur le même simulateur et la même expérience Expo Go :

- `testPortraitConsultation` prépare Expo Go puis vérifie la connexion démo,
  les 30 missions, les filtres Libéral (10) et CDD (20), la recherche sans résultat,
  la remise à zéro des filtres (30), le défilement vers la mission 16, son détail,
  le retour par geste avec position conservée, la reprise après Home/activation,
  puis la déconnexion avec confirmation native.
- `testLandscapeConsultation` reprend l’expérience laissée déconnectée par le
  portrait. Il vérifie les 30 missions, la mission 16 après défilement, son détail,
  le retour par geste avec position conservée, puis la déconnexion.

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
300 secondes maximum. La préparation attend jusqu’à 120 secondes le tutoriel ;
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

Pour chaque résultat (ici le portrait) :

```sh
xcrun xcresulttool get test-results summary \
  --path "$JOLENE_XCTEST_OUTPUT/portrait.xcresult" \
  > "$JOLENE_XCTEST_OUTPUT/portrait-summary.json"
xcrun xcresulttool export attachments \
  --path "$JOLENE_XCTEST_OUTPUT/portrait.xcresult" \
  --output-path "$JOLENE_XCTEST_OUTPUT/portrait-attachments"
```

La preuve exige `passedTests: 1`, `failedTests: 0`, `skippedTests: 0` pour chacune
des deux invocations. Captures conservées dans le résultat :

- Portrait : `ipad-portrait-connexion`, `ipad-portrait-missions`,
  `ipad-portrait-detail`, `ipad-portrait-retour`.
- Paysage : `ipad-paysage-connexion`, `ipad-paysage-liste`,
  `ipad-paysage-detail`, `ipad-paysage-retour`.

Chaque capture est accompagnée d’un dump d’accessibilité. En cas d’échec, le
résultat conserve aussi la vue de l’application, l’écran système et la hiérarchie
SpringBoard. Utiliser `attachments/manifest.json`, `exportedFileName` et
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

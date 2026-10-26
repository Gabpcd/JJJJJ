# iPad paysage — pilote existant

Projet XCTest UI autonome : compile uniquement le runner de vérification, puis
active l’application Expo Go déjà installée (`host.exp.Exponent`). Il ne compile
pas Jolene, n’installe pas de nouvelle version de Jolene et ne réinitialise aucune
donnée. Le scénario portrait précédent doit avoir quitté la démo, en laissant
le pilote chargé dans Expo Go.

Le test unique passe en paysage, ouvre la démo avec un seul tap, vérifie les
30 missions, descend jusqu’à la mission 16, ouvre son détail, revient par geste,
vérifie la conservation du défilement puis se déconnecte avec l’alerte native.
Les gestes utilisent les coordonnées relatives des vues XCTest en paysage.
Aucun fallback vers un tap de retour et aucune relance du pilote ne masquent un
échec du geste.

Depuis la racine du dépôt, avec le simulateur iPad déjà démarré :

```sh
xcodebuild test \
  -project mobile-native/ios-ui-tests/NativePilotUITests.xcodeproj \
  -scheme NativePilotUITests \
  -destination "platform=iOS Simulator,id=$JOLENE_IPAD_UDID" \
  -derivedDataPath "$JOLENE_XCTEST_OUTPUT/DerivedData" \
  -resultBundlePath "$JOLENE_XCTEST_OUTPUT/landscape.xcresult" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:NativePilotUITests/NativePilotLandscapeTests/testLandscapeConsultation \
  CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool get test-results summary \
  --path "$JOLENE_XCTEST_OUTPUT/landscape.xcresult" \
  > "$JOLENE_XCTEST_OUTPUT/xctest-summary.json"
xcrun xcresulttool export attachments \
  --path "$JOLENE_XCTEST_OUTPUT/landscape.xcresult" \
  --output-path "$JOLENE_XCTEST_OUTPUT/attachments"
```

La preuve exige `passedTests: 1`, `failedTests: 0`, `skippedTests: 0` dans le résumé
Xcode (les noms exacts du format sont ceux retournés par `xcresulttool`). Les
captures conservées dans le résultat sont nommées `ipad-paysage-connexion`,
`ipad-paysage-liste`, `ipad-paysage-detail` et `ipad-paysage-retour`. Chaque capture
est accompagnée d’un dump d’accessibilité. Utiliser `attachments/manifest.json`,
`exportedFileName` et `suggestedHumanReadableName` pour les exporter en fichiers
PNG nommés, sans présumer le nom généré par Xcode.

Références Apple : [application externe](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(bundleidentifier:)),
[orientation](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/orientation),
[geste relatif](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press(forduration:thendragto:)),
[capture attachée](https://developer.apple.com/documentation/xctest/xctattachment/init(screenshot:)).

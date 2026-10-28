# iPhone et iPad — pilote existant

Projet XCTest UI autonome : compile uniquement le runner de vérification, puis
ouvre l’expérience dans Expo Go déjà installé (`host.exp.Exponent`). Il ne compile
pas Jolene, n’installe pas de nouvelle version de Jolene et ne réinitialise aucune
donnée. Le runner CI prépare le bundle local puis lance Expo Go une seule fois
avec `--initialUrl exp://127.0.0.1:8090`, argument reconnu par Expo Go SDK 57.
XCTest active une seule fois le processus déjà ouvert pour attendre sa disponibilité
aux événements, sans seconde ouverture d’URL ni relancement.
La feuille « Enter URL » d’Expo Home ne fait pas partie du parcours Jolene.

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
  position de l’exploration par les gestes de retour. Dans l’historique, ouvrir
  aussi une mission annulée ayant une ancienne candidature acceptée : la carte
  et le dossier doivent afficher l’annulation, sans attribution active, nouvelle
  candidature ni bouton de reprise des anciens emails. Revenir à la liste par
  « Voir mes missions », puis à l’onglet Candidatures.
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

La préparation transmet l’URL locale au lancement initial, sans transaction
`simctl openurl` ni `XCUIApplication.open`. Elle passe trois préférences temporaires
au processus Expo Go : `-EXDevMenuIsOnboardingFinished YES`,
`-EXDevMenuShowsAtLaunch NO` et `-EXDevMenuShowFloatingActionButton NO`.
Ces clés sont lues par Expo Go SDK 57 ; Apple les place dans `NSArgumentDomain`,
sans modification directe du fichier de préférences ni des données Jolene.
XCTest exige le processus déjà au premier plan, appelle `activate()` une seule
fois pour garantir qu’il est prêt à recevoir les événements, puis vérifie
l’absence du tutoriel et du menu Expo et la présence de la connexion Jolene.
Le premier tap métier et son résultat restent vérifiés par chaque scénario.
Cette préparation ne teste pas le bouton Continue d’Expo Go.

Le tutoriel système du clavier, s’il apparaît, est traité au premier champ Jolene
de chaque scénario neuf avec le même contrôle identifié et borné à 3 secondes.

Les gestes de défilement et de retour utilisent les coordonnées relatives des
vues natives dans leur orientation courante. Aucun fallback vers un bouton de
retour, relancement, rechargement ou réessai ne masque un échec du parcours.
L’activation après Home reprend l’expérience existante. Chaque test dispose de
600 secondes maximum pour les trois parcours de démonstration. La préparation attend jusqu’à 120 secondes la connexion sans surcouche Expo ;
les autres attentes et les boucles de défilement sont bornées.

Depuis la racine du dépôt, avec le simulateur iPad démarré, Expo Go installé et le bundle local prêt :

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

Chaque format conserve 16 captures au total, dont les suffixes supplémentaires suivants, précédés de son préfixe
(`iphone-portrait-`, `ipad-portrait-`, `ipad-paysage-`) :

- `candidature-confirmee`, `mes-missions`, `dossier-relu`, `mission-annulee`, `profil-relu` ;
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

Références : [préférences Expo Go SDK 57 verrouillées](https://github.com/expo/expo/blob/1f504df4abcc9de37c215b5f741c6b1da245c839/apps/expo-go/ios/Exponent/DevMenu/DevMenuPreferences.swift),
[préférences temporaires par arguments Apple](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html#//apple_ref/doc/uid/10000059i-CH2-SW4),
[contrôles Expo Go SDK 57](https://github.com/expo/expo/blob/sdk-57/apps/expo-go/ios/Exponent/DevMenu/SwiftUI/DevMenuButtons.swift),
[en-tête Expo Go](https://github.com/expo/expo/blob/sdk-57/apps/expo-go/ios/Exponent/DevMenu/SwiftUI/HeaderView.swift),
[application externe XCTest](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(bundleidentifier:)),
[activation](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/activate()),
[orientation](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/orientation),
[geste relatif](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press(forduration:thendragto:)),
[capture attachée](https://developer.apple.com/documentation/xctest/xctattachment/init(screenshot:)).


## Scénario Documents séparé — préparation du 27 octobre

Le sélecteur du runner conserve `consultation` par défaut. Le workflow distinct
`.github/workflows/native-documents.yml` sélectionne explicitement
`NATIVE_PILOT_SCENARIO=documents` et `EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO=1`,
toujours avec `EXPO_PUBLIC_JOLENE_MODE=demo` et sans clé ni URL de backend.
Il n’exécute pas les candidatures, le profil établissement ou l’inscription avant
les justificatifs. Le workflow consultation existant reste indépendant.

Le scénario Documents modifie volontairement son dossier en mémoire. Chaque
format a donc son propre job CI neuf : aucun reset caché, aucun dossier préparé
par le portrait, aucune dépendance entre les trois invocations iOS.

| Format | `IOS_DEVICE_FAMILY` | `NATIVE_DOCUMENTS_ORIENTATION` | Méthode XCTest |
| --- | --- | --- | --- |
| iPhone portrait | `iphone` | `portrait` | `testDocumentsIphonePortrait` |
| iPad portrait | `ipad` | `portrait` | `testDocumentsIpadPortrait` |
| iPad paysage | `ipad` | `landscape` | `testDocumentsIpadLandscape` |

Android utilise `documents-run.yaml` : préparation Expo Go initiale, connexion au
compte fictif, puis `documents-demo.yaml`. Le paysage Android n’est pas annoncé.
Les méthodes Documents iOS partagent la préparation Expo Go existante, puis
choisissent l’orientation demandée avant la première assertion Documents.
La confirmation système Open/Ouvrir n’est ni ignorée ni traitée après un échec métier.

Le dossier exige les états Vérifié, Rejeté et En attente de vérification.
La revue humaine d’une pièce rejetée doit devenir **En cours de vérification**,
pas Vérifié. La première sélection de remplacement est annulée et conserve
l’ancien libellé. La deuxième remplace le diplôme et reçoit séparément son statut
fictif. Le troisième fichier simule une réponse interrompue après l’écriture :
le nouvel envoi doit être désactivé ; actualiser puis vérifier l’envoi précédent
retrouve la pièce sans la renvoyer et la laisse non vérifiée. Après retrait
confirmé, cette pièce disparaît. Le retour natif, le changement d’onglet et
Home/reprise doivent conserver exactement ces états. La déconnexion finale
est confirmée et aucun dossier authentifié ne reste affiché.

Huit captures et leurs hiérarchies sont requises, avec les suffixes suivants :

1. `documents-statuts`
2. `documents-revue-humaine`
3. `documents-remplacement-annule`
4. `documents-remplacement-confirme`
5. `documents-envoi-incertain`
6. `documents-envoi-reconcilie`
7. `documents-retrait-confirme`
8. `documents-reprise`

Les noms iOS commencent par `iphone-portrait-`, `ipad-portrait-` ou
`ipad-paysage-`. Android conserve les suffixes seuls. Le runner vérifie les huit
fichiers, leur unicité et leur orientation en tenant compte des métadonnées PNG.
`scenario.json` et `result.json` identifient le scénario et l’orientation attendus.
Chaque méthode XCTest reste bornée à **600 secondes**, son processus xcodebuild
à **900 secondes** ; le scénario Maestro Documents est borné à **600 secondes**.
Un résultat doit contenir exactement un test réussi sans échec ni exclusion.

Les tests purs `scripts/native-scenarios.node.test.mjs` sont inclus par le script
`npm test` existant. Ils vérifient le maintien du scénario consultation par défaut,
les quatre sélections Documents indépendantes, les méthodes et captures requises,
et le refus des modes, injections et orientations incompatibles avant le démarrage
des outils. Ils ne remplacent pas les quatre campagnes UI.

Cette préparation n’a pas été exécutée. Avant de l’intégrer, ajouter les quatre
paquets Expo et leur lockfile, relire le diff puis exécuter les contrôles coordonnés
par root. Les PNG sélectionnés sont synthétiques : ces scénarios ne prouvent pas
la caméra, les autorisations système, un choix de fichier personnel, l’ouverture
d’un original dans Safari/Chrome, une vérification professionnelle ou une opération
STAGING. Aucun bouton d’original fictif n’est affiché.

La saisie du code de signature exige un clavier natif présent et un champ
entièrement visible au-dessus de sa barre accessoire avant de taper les six
chiffres en une fois. Les assertions relisent exactement les six chiffres avant
le passage en arrière-plan et avant la signature. Le champ Contrat utilise les
insets clavier du ScrollView iOS, sans décalage fixe de 90 points.

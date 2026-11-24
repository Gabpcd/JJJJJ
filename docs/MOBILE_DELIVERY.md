# Distribution mobile

Les livraisons mobiles sont **exclusivement manuelles**. Un merge sur `main`,
un déploiement Vercel ou la fin d'un contrôle ne déclenche ni build de distribution,
ni soumission aux stores, ni publication OTA. Les builds de vérification CI,
les tests et les déploiements web/backend continuent normalement.

Depuis le lot 6 (`docs/mobile-swift/DECISIONS_LOT6.md`), chaque plateforme a sa chaîne :

| Plateforme | Envoi | Soumission | OTA |
|---|---|---|---|
| Android, coquille Capacitor (`android/`) | `mobile-delivery.yml`, mode `native` | même run, Google Play | `mobile-delivery.yml`, mode `ota` |
| iOS, app Swift (`ios-native/`) | `ios-native-testflight.yml` (`docs/mobile-swift/TESTFLIGHT.md`) | `ios-native-app-store.yml` (`docs/mobile-swift/APP_STORE.md`) | aucune (Apple 2.5.2) |

La coquille Capacitor iOS (`ios/`, 1.0.7 build 24) est gelée : plus aucun workflow ne la
construit ni ne la soumet. Le reste de ce document décrit `mobile-delivery.yml`, donc Android.

Le workflow `mobile-delivery.yml` attend Validate PR, Playwright, Lighthouse,
Android native simulation et Vercel, sur le même commit de `main`.
Il ignore les PR et un commit dépassé par un main
plus récent. Les secrets de signature ne sont accessibles qu'aux jobs de livraison.

## Versions et tags

`config/mobile-release.json` est scindé par plateforme. La section `android` porte la version
et le `versionCode` de la coquille ; la section `ios` porte la version de l'app Swift et son
build minimal (le numéro de build iOS est attribué à l'envoi TestFlight).
`npm run check:mobile-version` vérifie l'alignement avec `android/app/build.gradle` et
`ios-native/Config/Base.xcconfig`, et le gel de `ios/`.

Les tags sont scindés et aucun n'exige l'autre plateforme :
`mobile-native-source-android-N` fige le commit d'une livraison Android dès son début,
`mobile-native-android-N` consigne sa soumission à Google Play et sert de base aux OTA,
`mobile-native-ios-N` consigne la soumission du build Swift `N` à la revue Apple.
Les tags communs `mobile-native-20` à `mobile-native-24` restent comme historique.

## Nouveau build Android

Incrémenter la section `android` de `config/mobile-release.json`, `versionCode` et
`versionName` de `android/app/build.gradle`, et écrire le changelog Android
(`fastlane/metadata/android/fr-FR/changelogs/<versionCode>.txt`). Après recette,
revue fraîche et merge, lancer explicitement le workflow sur `main` avec le mode
`native`. Ce lancement construit le bundle signé et le soumet à Google Play.
Le mode par défaut `check` vérifie les prérequis sans construire ni publier.
Un workflow désactivé doit être réactivé seulement après présence de ces déclencheurs
manuels sur `main` ; sa réactivation ne constitue pas un lancement.
Google suit le réglage de publication gérée du compte. Aucun délai de validation
des stores n'est garanti par cette automatisation.

Un workflow vert peut ne rien livrer : consulter le résumé `Delivery` pour
identifier `native`, `ota` ou `none` et le commit concerné. Sans nouvel incrément
de version native ni correction compatible revue `mobile:ota`, aucun build
n'est soumis. « Soumis », « approuvé » et « disponible dans le store » sont des
états distincts ; les tags de livraison prouvent la soumission, pas sa validation.

Le bundle AAB est conservé 30 jours dans les artefacts GitHub, pas dans les releases
publiques. Google Play est interrogé avant chaque nouvel upload pour réutiliser un
`versionCode` déjà reçu. Un échec après upload mais avant soumission reste
une erreur visible à examiner ; il n'est jamais présenté comme une livraison.

## Correctifs compatibles sans nouveau téléchargement du store (Android seul)

Le build 20 introduit le client Capawesome Live Update, auto-hébergé sur GitHub
Releases. Il faut donc installer cette version native une première fois.

Le mode manuel `ota` publie seulement un correctif compatible. Il ne se transforme
jamais en build natif si le runtime requis manque. Un merge, même avec le label,
ne publie rien automatiquement.

Une OTA ne vise qu'Android. Elle est refusée :

- sur un runtime que la coquille iOS a aussi porté (build 24 ou moins) : le client ne
  compare que le bundle, la version et le build, le manifeste atteindrait donc les iPhone
  restés en 1.0.7 ;
- dès qu'un fichier a changé sous `ios-native/`, `ios/`, `android/`, la configuration ou
  les dépendances depuis le runtime `mobile-native-android-N` ;
- pour iOS natif, dans tous les cas.

Le label de PR `mobile:ota` est une décision de revue explicite : uniquement des
correctifs compatibles et des ajustements visuels, sans nouvelle fonctionnalité.
Le workflow contrôle tous les changements depuis le runtime natif : chaque PR
qui modifie le client doit avoir ce label. Une modification de plugin, de
dépendance, de configuration native, d'authentification, de paiement ou de
consentement exige une nouvelle version store. Un label ne remplace pas la recette.

Le ZIP et le manifeste sont signés avec une clé RSA privée conservée en secret
GitHub. Seule la clé publique est embarquée. Le manifeste authentifié impose le
bundle ID, la version et le numéro du build natif. L'archive est vérifiée une
seconde fois par le plugin natif (SHA-256 + signature). Aucun service Capawesome
Cloud, abonnement ou compte utilisateur n'est requis.

Le téléchargement se fait après affichage de la route, sans interrompre une
saisie. L'activation attend un redémarrage de l'app. Sans réseau, sans manifeste
ou avec une signature incorrecte, la version présente reste utilisable. Si une
nouvelle version ne signale pas un démarrage réussi dans les 30 secondes, le
plugin la révoque et recharge le bundle embarqué au timeout. Une
version ayant échoué est bloquée sur l'appareil.

Pour retirer un correctif, publier un nouveau commit correctif signé après la
même recette. Ne jamais modifier le ZIP d'un SHA existant. Le manifeste est
publié en dernier afin de ne pas désigner une archive absente.

## Secrets nécessaires

- Communs : `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`,
  `VITE_STRIPE_PUBLISHABLE_KEY`, `VITE_SENTRY_DSN`, `GOOGLE_SERVICES_JSON_BASE64`.
- OTA : `MOBILE_UPDATE_PRIVATE_KEY` (PEM correspondant à la clé publique du dépôt).
- Android : `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_PASSWORD`,
  `GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64` (autorisé uniquement sur Jolene).
- Apple (workflows de l'app Swift seulement) : `IOS_DISTRIBUTION_P12_BASE64`,
  `IOS_CERTIFICATE_PASSWORD`, `IOS_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_PRIVATE_KEY_BASE64`.

Ne jamais placer une clé privée dans `VITE_*`, le dépôt, les artefacts de build
ou une release. Les profils et certificats sont supprimés du runner en fin de job.

Documentation : [Live Update](https://capawesome.io/docs/sdks/capacitor/live-update/),
[signature](https://capawesome.io/docs/cloud/live-updates/code-signing/),
[Apple 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements),
[fastlane Apple](https://docs.fastlane.tools/actions/upload_to_app_store/),
[fastlane Google](https://docs.fastlane.tools/actions/upload_to_play_store/).

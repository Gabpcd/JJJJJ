# Distribution mobile

Le workflow `mobile-delivery.yml` attend Validate PR, Playwright, Lighthouse et Vercel,
sur le même commit de `main`. Il ignore les PR et un commit dépassé par un main
plus récent. Les secrets de signature ne sont accessibles qu'aux jobs de livraison.

## Nouveau build stores

Incrémenter `config/mobile-release.json`, les versions iOS/Android et écrire
`config/mobile-release-notes.txt` ainsi que le changelog Android. Après recette,
revue fraîche et merge, le workflow construit les deux binaires signés et les
soumet à Apple/Google. Apple conserve la publication manuelle après approbation.
Google suit le réglage de publication gérée du compte. Aucun délai de validation
des stores n'est garanti par cette automatisation.

Une livraison n'est terminée que lorsque les deux soumissions ont réussi. Le tag
`mobile-native-N` conserve le commit de référence de ce runtime. Les IPA/AAB sont
conservés 30 jours dans les artefacts GitHub, pas dans les releases publiques.
Le tag `mobile-native-source-N` fige le commit dès le début. Les tags
`mobile-native-ios-N` / `mobile-native-android-N` permettent de reprendre une
livraison partielle. Les stores sont interrogés avant chaque nouvel upload pour
réutiliser un build déjà reçu. Un échec après upload mais avant soumission reste
une erreur visible à examiner ; il n'est jamais présenté comme une livraison.

## Correctifs compatibles sans nouveau téléchargement du store

Le build 20 introduit le client Capawesome Live Update, auto-hébergé sur GitHub
Releases. Il faut donc installer cette version native une première fois.

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
- Apple : `IOS_DISTRIBUTION_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
  `IOS_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`.

Ne jamais placer une clé privée dans `VITE_*`, le dépôt, les artefacts de build
ou une release. Les profils et certificats sont supprimés du runner en fin de job.

Documentation : [Live Update](https://capawesome.io/docs/sdks/capacitor/live-update/),
[signature](https://capawesome.io/docs/cloud/live-updates/code-signing/),
[Apple 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements),
[fastlane Apple](https://docs.fastlane.tools/actions/upload_to_app_store/),
[fastlane Google](https://docs.fastlane.tools/actions/upload_to_play_store/).

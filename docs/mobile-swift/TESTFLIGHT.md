# TestFlight interne de l'app Swift (`ios-native/`)

Workflow : `.github/workflows/ios-native-testflight.yml` (« iOS Swift — TestFlight interne »).
Gardes et numérotation : `scripts/mobile/ios-native-testflight.mjs`, testés par
`tests/node/ios-native-testflight.node.mjs` (job `validate-pr`, étape « Garde de livraison mobile »).

## Ce que fait le workflow, et ce qu'il ne fait jamais

Il archive la cible `Jolene` en Release, la signe pour l'App Store, contrôle le binaire puis l'envoie
sur TestFlight pour les **testeurs internes** de l'app App Store Connect `6774672845` (`app.jolene`).

Il ne fait **jamais** : de soumission à la revue Apple, de distribution à des testeurs externes, de
modification de la fiche App Store, de mise en vente. La lane fastlane `ios testflight_native` se
limite à `upload_to_testflight` avec `skip_submission: true` et `distribute_external: false` ; un test
node échoue si le workflow ou la lane mentionnent `upload_to_app_store`, `submit_for_review`,
`deliver`, `distribute_external: true` ou des groupes de testeurs.

La coquille Capacitor (`ios/`, 1.0.x) et Android restent livrées par `mobile-delivery.yml`, que ce
workflow ne touche pas.

## Lancer un envoi

1. Le commit voulu doit être sur `main` (le workflow refuse toute autre branche et tout autre
   déclencheur).
2. GitHub → Actions → « iOS Swift — TestFlight interne » → *Run workflow*, branche `main`.
   Le champ « Numéro de build » est facultatif : laissez-le vide dans le cas courant.
   En ligne de commande : `gh workflow run ios-native-testflight.yml --ref main`
   (ou `-f build_number=31` pour imposer un numéro).
3. Trois jobs s'enchaînent :
   - `preparer` (Ubuntu) : gardes du dépôt, puis calcul du numéro de build en lecture seule dans
     App Store Connect ;
   - `envoyer` (macOS 26, Xcode 26.4.1) : trousseau temporaire, garde du profil, garde des réglages
     résolus, archive signée, export `app-store-connect`, gardes du binaire et de la signature,
     relecture d'App Store Connect, envoi ;
   - `traitement` (Ubuntu) : attend jusqu'à 60 minutes que le build passe à `VALID` dans App Store
     Connect.
4. Un seul envoi à la fois : un second déclenchement attend la fin du premier (groupe de
   concurrence `ios-native-testflight`, sans annulation).

L'IPA et les journaux `xcodebuild` sont conservés 14 jours dans l'artefact
`ios-native-testflight-<build>-<sha>`.

## Numérotation

- **Version** : `MARKETING_VERSION` de `ios-native/Config/Base.xcconfig`, aujourd'hui `2.0.0`
  (décision du plan, lot 6). Le workflow ne la surcharge pas. La garde `identite` exige au moins
  2.0.0 et une version supérieure à celle de la coquille Capacitor (`config/mobile-release.json`).
- **Build** : `CFBundleVersion`, injecté par `xcodebuild CURRENT_PROJECT_VERSION=<N>`. La valeur
  `CURRENT_PROJECT_VERSION = 25` de `Base.xcconfig` n'est qu'un défaut pour les builds locaux.
  - Champ vide : `N = max(dernier build App Store Connect de l'app 6774672845, plancher) + 1`,
    en ordre numérique, sur **tous** les builds de l'app : toutes versions, Capacitor compris,
    expirés et en traitement compris.
  - Champ rempli : le numéro est refusé s'il n'est pas un entier positif, s'il est inférieur ou égal
    au plancher, s'il dépasse le dernier build connu de plus de 50, ou s'il existe déjà dans App Store
    Connect. La borne haute protège d'une faute de frappe (3100 pour 31) qui relèverait définitivement
    le plancher de tous les builds suivants.
  - **Plancher** : `max(24, buildNumber de config/mobile-release.json)`. 24 est le dernier build
    Capacitor publié (1.0.7) ; si la coquille réserve un numéro plus haut pour une 1.0.8, TestFlight
    ne peut pas le prendre.
  - Le numéro est relu dans App Store Connect juste avant l'envoi (`verify-free`).
- **`config/mobile-release.json` n'est pas scindé** : il reste la source des versions Capacitor
  (iOS 1.0.x et Android), lu tel quel par `delivery-plan.mjs`, `release-state.mjs`,
  `check-mobile-build-alignment.mjs` et `fastlane/Fastfile`. Pour l'app Swift, la version vient du
  xcconfig et le build est dérivé d'App Store Connect : un second champ dans le JSON pourrait
  diverger. La scission par plateforme reste prévue au lot 6, avec la bascule de
  `mobile-delivery.yml`.
- **Retour arrière Capacitor** : une 1.0.8 de secours doit prendre un `buildNumber` supérieur au
  dernier build TestFlight Swift (lisible dans App Store Connect ou dans le résumé du job
  `preparer`).

## Les gardes

Chaque refus s'affiche sous la forme `[garde] message (voir docs/mobile-swift/TESTFLIGHT.md, garde « … »)`
et arrête le job avant l'envoi. Aucune garde ne se désactive par une option.

| Garde | Quand | Ce qu'elle vérifie | Si elle échoue |
|---|---|---|---|
| `numerotation` | `preparer`, puis juste avant l'envoi | Numéro entier, supérieur au plancher, au plus dernier build + 50, absent d'App Store Connect ; l'app 6774672845 a bien le bundle `app.jolene`. | Laisser le champ vide ou choisir un numéro libre. |
| `environnement` | dépôt, réglages, binaire | `Production.xcconfig` commence par `#include "Base.xcconfig"` (sinon Base écraserait la production) ; `JOLENE_ENVIRONMENT = production`, URL `https://flripxtsyegjshnhzjkz.supabase.co`, clé `sb_publishable_…` (jamais `sb_secret_`), aucune mention du projet STAGING `mejpriaetwgtcstbgfid` ; la configuration Release du projet repose sur `Production.xcconfig` ; le scheme archive en Release ; l'Info.plist lit ces valeurs par `$(…)` et non par une valeur figée. Dans le binaire : `JoleneEnvironment = production`. | Corriger `Production.xcconfig` ou l'Info.plist. Rappel : en Release, `-JOLENE_MODE` et `JOLENE_MODE` sont ignorés (`AppContainer`), seul l'Info.plist fait foi. |
| `chiffrement` | dépôt, binaire | `ITSAppUsesNonExemptEncryption = false`. Sans cette clé, le build reste en « conformité export manquante » et les testeurs ne peuvent pas l'installer. | Rétablir la clé dans `ios-native/Jolene/Info.plist`. |
| `identite` | dépôt | Bundle `app.jolene`, équipe `GDU5AA28M9`, signature manuelle, version ≥ 2.0.0 et supérieure à Capacitor ; `Production.xcconfig` relaie `CODE_SIGN_IDENTITY` et `PROVISIONING_PROFILE_SPECIFIER` depuis `JOLENE_CODE_SIGN_IDENTITY` et `JOLENE_PROVISIONING_PROFILE`. | Ce relais évite d'appliquer le profil aux cibles des packages SPM, qui le refusent ; ne pas le remplacer par une surcharge en ligne de commande. |
| `entitlements` | dépôt | `Jolene.entitlements` déclare `aps-environment = $(APS_ENVIRONMENT)` et des associated domains. | — |
| `confidentialite` | dépôt, binaire | `PrivacyInfo.xcprivacy` existe, est copié dans les ressources de la cible et se trouve à la racine de `Jolene.app` ; `NSPrivacyTracking = false` ; chaque catégorie d'API « required reason » a des raisons valides selon Apple ; chaque catégorie **utilisée** par le code Swift de l'app et de ses packages (`UserDefaults`, horodatages de fichiers, `ContinuousClock`/uptime, espace disque, claviers actifs) est déclarée. Une API non déclarée fait refuser l'envoi (ITMS-91053). | Ajouter la catégorie et la raison exacte dans le manifeste. La détection est volontairement large : un faux positif ne demande qu'une déclaration. |
| `icone` | dépôt, binaire | Une icône 1024 × 1024 est déclarée dans `AppIcon.appiconset`, sans canal alpha (ITMS-90717) ; le binaire contient `Assets.car` et `CFBundleIconName = AppIcon`. | Remplacer le PNG par une version opaque en 1024 × 1024. |
| `profil` | `envoyer`, avant l'archive | Profil nommé « Jolene App Store Distribution », équipe `GDU5AA28M9`, App ID `GDU5AA28M9.app.jolene`, profil App Store (`beta-reports-active`, sans appareils, `get-task-allow = false`), non expiré (alerte à moins de 30 jours) ; il **couvre chaque entitlement** de `Jolene.entitlements` résolu en production (`aps-environment = production`, `applinks:jolene.app`, `webcredentials:jolene.app`, ou `*`) ; il autorise le certificat « Apple Distribution: Jolene App (GDU5AA28M9) » **et précisément celui du .p12** (empreinte SHA-1). Une empreinte absente ou illisible fait échouer la garde : le contrôle n'est jamais sauté. | Régénérer le profil pour l'App ID `app.jolene` avec Push et Associated Domains sur developer.apple.com, puis remplacer `IOS_PROFILE_BASE64`. |
| `reglages` | `envoyer`, avant l'archive | Réglages Release **résolus** par `xcodebuild -showBuildSettings` : identité et profil attendus, `CURRENT_PROJECT_VERSION = N`, entitlements et Info.plist attendus, icône `AppIcon`, pas de `DEBUG` dans `SWIFT_ACTIVE_COMPILATION_CONDITIONS` ni de `-D DEBUG` dans `OTHER_SWIFT_FLAGS` (sinon les surcharges démo seraient compilées), pas de `SWIFT_OPTIMIZATION_LEVEL = -Onone`, valeurs de production. | Corriger le xcconfig ou le projet (`xcodegen generate` depuis `ios-native/project.yml`). |
| `binaire` | `envoyer`, sur l'IPA exportée | Bundle, version et build de l'Info.plist compilé, plus les gardes `environnement`, `chiffrement`, `icone` et `confidentialite` rejouées sur le binaire. | — |
| `signature` | `envoyer`, sur l'IPA exportée | `codesign --verify --deep --strict` ; signataire « Apple Distribution: Jolene App (GDU5AA28M9) » ; profil embarqué « Jolene App Store Distribution » dont l'UUID est **celui validé à l'étape `profil`**, sans appareils ; entitlements **signés** : production, associated domains, `application-identifier`, `get-task-allow = false`, `beta-reports-active = true`. | Contrôler le .p12 et le profil. |
| `traitement` | `traitement`, après l'envoi | Le build `N` apparaît dans App Store Connect et passe à `VALID`, non expiré, avec une conformité export `false`. `INVALID` ou `FAILED` arrête le job. | Lire l'e-mail d'App Store Connect (codes ITMS), corriger, relancer avec un nouveau numéro. |

## Secrets et hygiène

Seuls les six secrets existants sont utilisés (`IOS_DISTRIBUTION_P12_BASE64`,
`IOS_CERTIFICATE_PASSWORD`, `IOS_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_PRIVATE_KEY_BASE64`) ; un test node le vérifie. `prepare-ci-signing.mjs ios` les décode dans
`$RUNNER_TEMP/jolene-signing` (droits 0600). Le trousseau temporaire a un mot de passe aléatoire,
masqué dans les journaux. La dernière étape, en `if: always()`, supprime le trousseau, le matériel de
signature, les profils installés et la clé App Store Connect écrite par fastlane, y compris en cas
d'échec. Le script n'affiche jamais une valeur secrète : il signe localement un jeton ES256 de
15 minutes et ne lit l'API App Store Connect qu'en lecture.

## Ce qui reste manuel

1. **Testeurs internes** (une fois) : App Store Connect → app Jolene → TestFlight → *Internal
   Testing* → créer un groupe (par exemple « Équipe Jolene »), activer la distribution automatique et
   ajouter les membres. Un testeur interne doit avoir un rôle dans *Users and Access* de l'équipe
   App Store Connect. Sans distribution automatique, ajoutez chaque build au groupe à la main.
2. **Installation sur iPhone** : installer l'app TestFlight d'Apple, accepter l'invitation reçue par
   e-mail avec l'Apple ID du compte testeur, puis installer « Jolene » 2.0.0 (N). Le build TestFlight
   remplace sur l'appareil l'app App Store 1.0.7 : la session web n'est pas reprise, il faut se
   reconnecter (plan §6). Pour revenir à 1.0.7, supprimez l'app puis réinstallez-la depuis l'App Store.
3. **Notes de test** (« What to Test ») : facultatives, à saisir dans TestFlight si besoin.
4. **Recette** : un envoi réussi ne prouve que la chaîne de livraison (signature, gardes, traitement
   Apple). La recette device (connexion de production, push de production, Universal Links,
   Face ID) reste à conduire sur l'iPhone et à consigner selon `docs/mobile-swift/RECETTE_DEVICE_LOT1.md`.
   CLAUDE.md distingue toujours simulation, environnement de test, production et appareil physique.
5. **Revue Apple et mise en vente** : hors périmètre. Elles passeront par la bascule du lot 6
   (`mobile-delivery.yml`), jamais par ce workflow.

## Vérification locale sans signature

```bash
node scripts/mobile/ios-native-testflight.mjs depot
xcodebuild archive -project ios-native/Jolene.xcodeproj -scheme Jolene -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Jolene.xcarchive \
  -derivedDataPath /tmp/jolene-derived CURRENT_PROJECT_VERSION=25 CODE_SIGNING_ALLOWED=NO
node scripts/mobile/ios-native-testflight.mjs bundle /tmp/Jolene.xcarchive/Products/Applications/Jolene.app --build 25
node --test tests/node/ios-native-testflight.node.mjs
```

Supprimez ensuite le dossier DerivedData (`/tmp/jolene-derived` dans l'exemple).

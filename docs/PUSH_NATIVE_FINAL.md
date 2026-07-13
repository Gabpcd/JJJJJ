# Push natif iOS et Android — runbook de production

État vérifié le 13/07/2026.

## Architecture effective

| Plateforme | Token enregistré par l'app | Transport serveur | Secrets serveur |
|---|---|---|---|
| Web | abonnement Web Push | VAPID/Web Push | `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` |
| iOS | token APNs brut | APNs HTTP/2 direct | `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` |
| Android | token FCM | FCM HTTP v1 | `FIREBASE_SERVICE_ACCOUNT_JSON` |

Le choix iOS est volontaire : `supabase/functions/send-push` envoie d'abord
directement via APNs. Il ne faut donc pas remplacer le token APNs enregistré
par un token FCM iOS sans modifier simultanément le transport serveur.

`@capacitor/push-notifications` fournit précisément le bon token sur chaque
plateforme. L'initialisation est faite depuis `AuthContext` pour une connexion
classique comme pour une session restaurée, PSC ou biométrique. Au logout, les
tokens du compte sont supprimés en base et les listeners locaux sont retirés.

## Configuration iOS hors repo

1. Dans Apple Developer, vérifier l'App ID explicite **Jolene** `app.jolene`,
   l'équipe `FPQ78HDF4Y`, Push Notifications et Associated Domains.
2. Créer une clé APNs `.p8`, puis poser son contenu et ses identifiants dans les
   secrets Supabase : `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`.
3. Vérifier `APNS_BUNDLE_ID=app.jolene` et choisir l'environnement APNs adapté
   (`sandbox` pour un build Debug, `production` pour TestFlight/App Store).
4. Dans Xcode, sélectionner l'équipe et laisser le provisioning automatique
   produire un profil contenant `aps-environment` et Associated Domains.

Le repo contient déjà `App.entitlements` et les relais AppDelegate nécessaires.
Les notifications visibles n'exigent pas de mode d'exécution en arrière-plan ;
aucun `UIBackgroundModes` superflu n'est déclaré. Aucun
`GoogleService-Info.plist` n'est requis pour le transport APNs direct.

Le projet est SPM : ouvrir `ios/App/App.xcodeproj`, pas un `.xcworkspace`.

## Configuration Android hors repo

1. L'application Firebase Android `app.jolene` est créée dans le projet
   `jolene-app-d91fd`. Ses certificats SHA-1 et SHA-256 sont enregistrés.
2. Le `google-services.json` officiel est déposé localement dans
   `android/app/` et reste gitignoré. En CI, fournir plutôt
   `GOOGLE_SERVICES_JSON[_BASE64]` au script de build.
3. `FIREBASE_SERVICE_ACCOUNT_JSON` est configuré côté Supabase pour l'envoi
   FCM ; ce secret serveur ne remplace pas le fichier de configuration client.
4. Le keystore d'upload et `android/keystore.properties` sont configurés hors
   Git. L'empreinte SHA-256 du certificat d'upload est
   `4B:43:18:5D:0F:67:C3:1F:A7:E9:0D:69:7D:5B:AF:D0:D6:DE:95:8C:66:27:8B:5D:22:79:66:31:6D:5D:69:B2`.
5. L'empreinte réellement utilisée pour les installations Google Play est
   celle de **Play App Signing** :
   `18:6E:1F:3A:56:5D:DC:F0:88:0D:DD:58:EB:AF:D9:79:6C:88:7E:E9:61:81:0E:70:A8:3C:78:C3:0A:E8:EE:06`.
   Elle est distincte de la clé d'upload et a servi à générer
   `assetlinks.json`.

Les six NotificationChannel Jolene sont créés au démarrage. Le canal urgence
utilise le son de notification système ; les payloads serveur envoient
également `sound: default`.

## Build

Le 13/07/2026, l'archive iOS **Jolene** `1.0 (4)` a été produite avec Xcode
26.5, re-signée avec le certificat Apple Distribution de l'équipe
`FPQ78HDF4Y` et `aps-environment=production`, puis
acceptée par App Store Connect. Le lint Android Release passe avec SDK 36 et
Gradle 8.14.5. Firebase Android, la signature d'upload et l'empreinte Play App
Signing sont configurés : `lintRelease` et `bundleRelease` passent, et l'AAB
signé Jolene `1.0` (`versionCode 2`) est généré dans
`android/app/build/outputs/bundle/release/app-release.aab`.

```bash
# Prépare les secrets Android, valide App Links, construit le web et synchronise.
npm run build:mobile

# Android (SDK 36 + keystore requis)
cd android && ./gradlew lintRelease bundleRelease
```

```bash
# Xcode 26 installé localement sur ce Mac
DEVELOPER_DIR=/Users/gabrielle/Downloads/Xcode.app/Contents/Developer \
  xcodebuild -project ios/App/App.xcodeproj -scheme App \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/<date>/Jolene.xcarchive" \
  archive

# Export App Store (configuration non secrète versionnée)
DEVELOPER_DIR=/Users/gabrielle/Downloads/Xcode.app/Contents/Developer \
  xcodebuild -exportArchive \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/<date>/Jolene.xcarchive" \
  -exportPath "$HOME/Desktop/Jolene-AppStore" \
  -exportOptionsPlist ios/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

Pour éviter une demande de trousseau dans les exécutions headless SwiftPM,
ajouter `-packageAuthorizationProvider netrc -scmProvider system`.

## Recette obligatoire sur appareils réels

- permission refusée puis accordée depuis les réglages ;
- token `IOS` ou `ANDROID` présent dans `tokens_push` ;
- notification reçue app ouverte, en arrière-plan et tuée ;
- son/vibration et bon canal Android ;
- tap sur candidature, mission, contrat, facture et litige vers la route du
  rôle connecté ;
- changement de compte sur un même téléphone sans réception croisée ;
- suppression/rotation d'un token invalide.

Les simulateurs ne valident ni le provisioning APNs réel, ni le comportement
OEM Android : TestFlight et la piste Play Internal restent indispensables.

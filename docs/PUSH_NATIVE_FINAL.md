# Push natif iOS et Android — runbook de production

État vérifié le 12/07/2026.

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

1. Dans Apple Developer, vérifier l'App ID explicite `app.jolene`, l'équipe
   `5D9L5FQQ86`, Push Notifications et Associated Domains.
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

1. Dans Firebase, créer l'application Android avec le package `app.jolene`.
2. Déposer `google-services.json` dans `android/app/` ou fournir
   `GOOGLE_SERVICES_JSON[_BASE64]` au script de build.
3. Configurer `FIREBASE_SERVICE_ACCOUNT_JSON` côté Supabase pour l'envoi FCM.
4. Créer le keystore d'upload et `android/keystore.properties` avec
   `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
5. Récupérer l'empreinte SHA-256 réellement utilisée par Play App Signing et
   fournir `ANDROID_SHA256_CERT_FINGERPRINTS` avant le build et le déploiement
   web d'`assetlinks.json`.

Les six NotificationChannel Jolene sont créés au démarrage. Le canal urgence
utilise le son de notification système ; les payloads serveur envoient
également `sound: default`.

## Build

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
  -configuration Release -destination 'generic/platform=iOS' archive
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

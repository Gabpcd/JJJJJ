# Capacitor production — état natif iOS et Android

État vérifié le 13/07/2026. La source de vérité des versions reste
`package.json`; `npx cap sync` régénère les fichiers natifs gérés par Capacitor.

## Plugins structurants

| Plugin | Usage |
|---|---|
| `@capacitor/app` | cycle de vie, Universal Links/App Links, bouton retour |
| `@capacitor/barcode-scanner` | scan QR natif iOS/Android |
| `@capacitor/camera` | photo et sélection de documents |
| `@capacitor/geolocation` | position ponctuelle au pointage ou sur action « me localiser » du profil/adresse |
| `@capacitor/network` | démarrage et synchronisation hors-ligne |
| `@capacitor/push-notifications` | token APNs sur iOS, token FCM sur Android |
| `@capacitor/splash-screen` | splash natif, avec filet de sortie à 1,8 s |
| `@capgo/capacitor-native-biometric` | déverrouillage biométrique |

Le plugin de géolocalisation en arrière-plan et son code mort ont été retirés.
Jolene ne demande ni localisation permanente iOS, ni
`ACCESS_BACKGROUND_LOCATION` Android.

## Wrappers applicatifs

- `src/lib/camera.ts` utilise le scanner officiel Capacitor en QR-only sur le
  natif et conserve `html5-qrcode` pour le web.
- `src/lib/geoloc.ts` effectue une acquisition ponctuelle, déclenchée par un
  pointage ou une demande volontaire de localisation du profil/adresse.
- `src/lib/nativeLinks.ts` n'accepte que les hôtes exacts `jolene.app`,
  `www.jolene.app`, `app.jolene.app` ou un chemin interne, en conservant query
  string et fragment. Les associations OS restent limitées au domaine canonique
  `jolene.app` ; `app.jolene.app` sert uniquement aux anciens payloads in-app.
- `src/lib/pushNative.ts` initialise le push pour toute session, y compris une
  session restaurée, PSC ou biométrique. Les liens de notification passent par
  la même liste d'origines autorisées.

## Permissions réellement déclarées

iOS (`ios/App/App/Info.plist`) : caméra, photothèque en lecture, localisation
« When In Use » et Face ID. Aucun mode d'arrière-plan n'est déclaré. Le manifest
de confidentialité `PrivacyInfo.xcprivacy` est membre de la cible App et se
retrouve à la racine du bundle produit.

Android (`android/app/src/main/AndroidManifest.xml`) : internet, caméra,
localisation fine/approximative, notifications, état réseau, wake lock et
réception après redémarrage. Aucune permission de stockage large ni de
localisation en arrière-plan n'est demandée.

## Deep links

Les chemins stores couverts sont :

- `/reset-password`
- `/auth/psc/callback`
- `/etab/invitation/*`
- `/mission/*`
- `/contrat/*`
- `/soignant/missions*`
- `/etablissement/missions*`

La configuration iOS est dans `App.entitlements` et l'AASA public. Android
utilise un intent filter `autoVerify` et `assetlinks.json`. Toute combinaison
host/chemin non autorisée est refusée de nouveau côté TypeScript.

## Commandes de vérification

```bash
npm run build
npx cap sync
npx tsc --noEmit
npx vitest run src/lib/nativeLinks.test.ts src/lib/pushNative.test.ts
```

Le projet iOS utilise Swift Package Manager et s'ouvre avec
`ios/App/App.xcodeproj`. Sur ce Mac, Xcode 26 est installé hors du chemin
sélectionné globalement ; utiliser sans modifier la machine :

```bash
DEVELOPER_DIR=/Users/gabrielle/Downloads/Xcode.app/Contents/Developer \
  xcodebuild -resolvePackageDependencies \
  -project ios/App/App.xcodeproj -scheme App \
  -packageAuthorizationProvider netrc -scmProvider system
```

Pour Android, la signature d'upload, le `google-services.json` local gitignoré
et l'empreinte Play App Signing sont désormais configurés. `assetlinks.json`
est généré avec l'empreinte de signature Play. Avec Android SDK 36,
`lintRelease` et `bundleRelease` passent ; l'AAB signé produit est Jolene
`1.0` (`versionCode 7`).

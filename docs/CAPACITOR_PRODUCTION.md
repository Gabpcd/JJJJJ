# Capacitor production — architecture plugins + permissions

> Sprint 4. État des wrappers natifs Jolene pour iOS + Android via Capacitor.

## Plugins installés

| Plugin | Version | Usage |
|---|---|---|
| `@capacitor/core` | ^8.2.0 | Bridge JS ↔ natif |
| `@capacitor/cli` | ^8.2.0 | CLI build/sync |
| `@capacitor/ios` | ^8.2.0 | Cible iOS |
| `@capacitor/android` | ^8.2.0 | Cible Android |
| `@capacitor/app` | ^8.1.0 | Lifecycle (background, deeplinks) |
| `@capacitor/browser` | ^8.0.3 | InAppBrowser (Stripe Connect, PSC) |
| `@capacitor/camera` | ^8.0.2 | Photo + galerie |
| `@capacitor/geolocation` | ^8.1.0 | GPS pointage |
| `@capacitor/haptics` | ^8.0.2 | Vibration feedback |
| `@capacitor/keyboard` | ^8.0.2 | Keyboard show/hide events |
| `@capacitor/network` | ^8.0.1 | Détection connectivité (**Sprint 4 PR 4**) |
| `@capacitor/preferences` | ^8.0.1 | Storage local sécurisé |
| `@capacitor/push-notifications` | ^8.0.3 | Push FCM/APNS |
| `@capacitor/share` | ^8.0.1 | Partage natif |
| `@capacitor/splash-screen` | ^8.0.1 | Splash app |
| `@capacitor/status-bar` | ^8.0.2 | Style status bar |
| `@capacitor-mlkit/barcode-scanning` | ^8.1.0 | QR scanner natif (**Sprint 4 PR 4**) |

## Wrappers unifiés (Sprint 4)

### `src/lib/geoloc.ts` (PR 5 S4)
- `getCurrentPosition(options)` : isNative → `@capacitor/geolocation`, sinon `navigator.geolocation`
- `JoleneGeolocResult` standardisé
- `JoleneGeolocError` : PERMISSION_DENIED / POSITION_UNAVAILABLE / TIMEOUT / UNSUPPORTED / UNKNOWN
- `checkGeolocPermission()` / `requestGeolocPermission()`

### `src/lib/camera.ts` (PR 6 S4)
- `prendrePhoto(options)` : isNative → `@capacitor/camera` DataUrl, sinon input file
- `scannerQr()` : isNative → `@capacitor-mlkit/barcode-scanning`, sinon `null` (caller utilise `ScannerQRPointage` web)
- `JoleneCameraError` : PERMISSION_DENIED / CANCELLED / UNSUPPORTED / UNKNOWN

### `src/lib/pushNative.ts` (existant + amélioré PR 7 S4)
- `initNativePush(userId)` : permission + register + listeners
- Listener `pushNotificationReceived` (foreground) → dispatch `jolene:push-foreground` CustomEvent
- Listener `pushNotificationActionPerformed` (tap) → `navigationPathForEvent` smart routing par type_evenement

## Permissions iOS — `ios/App/App/Info.plist`

Sprint 4 PR 4 ajouts :
- `NSLocationWhenInUseUsageDescription` (déjà OK avant)
- `NSCameraUsageDescription` (déjà OK)
- `NSPhotoLibraryUsageDescription` (déjà OK)
- `NSLocalNotificationUsageDescription` (déjà OK)
- **`NSPhotoLibraryAddUsageDescription`** (PR 4 S4) — enregistrer justificatifs
- **`UIBackgroundModes ['remote-notification']`** (PR 4 S4) — bloquant push iOS background

À ajouter au Sprint final via Xcode :
- Capability Push Notifications → génère `App.entitlements` avec `aps-environment`
- Background Modes → cocher "Remote notifications"

## Permissions Android — `android/app/src/main/AndroidManifest.xml`

Sprint 4 PR 4 ajouts :
- `INTERNET` (déjà OK)
- `CAMERA` (déjà OK)
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` (déjà OK)
- `POST_NOTIFICATIONS` (déjà OK — Android 13+ runtime permission)
- `READ_EXTERNAL_STORAGE` (déjà OK)
- **`WAKE_LOCK`** (PR 4 S4) — robustesse FCM en Doze mode
- **`RECEIVE_BOOT_COMPLETED`** (PR 4 S4) — re-registration FCM au boot
- **`ACCESS_NETWORK_STATE`** (PR 4 S4) — détection connectivité offline queue

## Notification channels Android (PR 7 S4)

Déclarés dans `MainActivity.onCreate` (requis Android 8+) :

| `channel_id` | Importance | Caractéristiques |
|---|---|---|
| `jolene_urgence` | HIGH | Vibration + son personnalisé + badge |
| `jolene_info` | DEFAULT | Vibration + badge |
| `jolene_paiement` | DEFAULT | Badge ON |
| `jolene_messagerie` | HIGH | Vibration légère (150 ms) + badge |
| `jolene_signature` | HIGH | Vibration pattern (200/100/200) + badge |
| `jolene_pointage` | DEFAULT | Vibration + badge OFF |

Le `send-push` edge function (PR 1 S4) mappe `type_evenement` vers le
bon channel_id via le helper `channelForType` côté Deno.

## Lifecycle et listeners

| Event | Source | Comportement |
|---|---|---|
| `appStateChange` | `@capacitor/app` | Pause/resume → sync horsLigne queue |
| `appUrlOpen` | `@capacitor/app` | Deep links (universalLinks iOS, app links Android) |
| `backButton` | `@capacitor/app` | Android : custom handler navigation back |
| `pushNotificationReceived` | `@capacitor/push-notifications` | Foreground → CustomEvent toast |
| `pushNotificationActionPerformed` | `@capacitor/push-notifications` | Tap → smart nav |
| `keyboardWillShow` / `keyboardDidHide` | `@capacitor/keyboard` | Layout adjust |
| `networkStatusChange` | `@capacitor/network` | Online/offline → bandeau + sync |

## Best practices

### Tests
- Sur iOS : Xcode Simulator iPhone 15 + iPad Pro
- Sur Android : Android Studio AVD Pixel 7 + tablette
- TestFlight pour les tests devices réels iOS
- Internal testing Play Console pour Android

### Build CI
À configurer Sprint final :
- GitHub Actions workflow `.github/workflows/build-mobile.yml`
- Trigger : tag `v*` ou manuel
- Jobs : iOS (macOS runner, xcodebuild archive) + Android (ubuntu, gradle bundleRelease)
- Artifacts : `.ipa` + `.aab` uploadés
- Optionnel : Fastlane pour automatiser l'upload TestFlight + Play Console

### Performance
- Lazy loading composants (cf. `lazy()` dans App.tsx) → réduit le bundle initial
- Service worker pour assets statiques (déjà en place)
- Compression images via `@capacitor/camera` quality:80

### Sécurité
- `@capacitor/preferences` pour storage sensible (jamais localStorage pour tokens)
- Validation tous deep links côté frontend (path absolu jolene.app uniquement)
- Pas de stocker `service_role_key` côté client — uniquement edge functions

## Roadmap post-Sprint final

- `@capacitor/biometric-auth` pour Face ID / fingerprint sur signature OTP
- `@capacitor-community/native-audio` pour son urgence custom plus reliable
- Background fetch pour sync presences hors-ligne sans wake-up app
- Universal Links iOS + App Links Android pour deep linking depuis emails/SMS

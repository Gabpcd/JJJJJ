# Audit Firebase / Notifications push natives — diagnostic

> **ARCHIVÉ — ne pas utiliser comme checklist de release.** Ce diagnostic
> décrit l'état du 13/05/2026 avant l'implémentation APNs/FCM. L'état courant et
> les seuls prérequis de soumission sont dans `docs/PUSH_NATIVE_FINAL.md` et
> `docs/store-readiness.md`. En particulier, iOS utilise APNs direct : aucun
> `GoogleService-Info.plist` ni mode `remote-notification` n'est requis pour les
> notifications visibles de Jolene.

> Date : 2026-05-13. État actuel des push iOS/Android natives via
> Firebase / FCM / APNS pour le wrapper Capacitor Jolene.
> Audit-only, aucun fix appliqué.

## TL;DR

**Côté code Jolene** : 80% en place (Capacitor plugin installé + flow d'inscription token correct + permissions Android présentes).

**Côté infra Firebase** : **0% configuré**. Aucun fichier de config Firebase dans le repo, aucun secret Firebase Admin SDK côté Supabase, et le backend `send-push` n'envoie QUE via Web Push VAPID (donc les tokens FCM natifs Android/iOS ne sont pas utilisables actuellement).

**Bloquants pour le launch mobile** :
1. `android/app/google-services.json` manquant → FCM Android non opérationnel
2. iOS Push capability + p8 APNS key non configurés → APNS non opérationnel
3. `send-push` ne dispatch pas vers FCM (HTTP v1) ni APNS (HTTP/2) → même avec les configs ci-dessus, les tokens natifs seraient stockés mais aucun push reçu

---

## 1. Projet Firebase

| Élément | État | Détail |
|---|---|---|
| `firebase.json` racine | ❌ Absent | Aucun fichier Firebase config dans le repo |
| `.firebaserc` | ❌ Absent | Aucun projet Firebase associé via Firebase CLI |
| Référence indirecte | ⚠️ Trouvée | Le commentaire dans `send-push/index.ts` mentionne "FIREBASE_VAPID_KEY = clé publique VAPID" — suggère qu'un projet Firebase existe côté console (utilisé pour générer la paire VAPID web push) mais aucune autre référence |

**Verdict** : Un projet Firebase peut exister côté console, mais :
- Aucune config locale, donc pas de génération automatique de fichiers
- Pas de Firebase Admin SDK installé
- Pas de service account JSON

**À faire post-audit** :
- Créer / identifier le projet Firebase Console (vérifier avec Gabrielle s'il existe déjà)
- Récupérer le project ID, télécharger `google-services.json` + `GoogleService-Info.plist`
- Générer une clé service account JSON pour `send-push` backend

---

## 2. Android — `google-services.json`

| Élément | État | Détail |
|---|---|---|
| `android/app/google-services.json` | ❌ Absent | Fichier non présent |
| `android/app/build.gradle` | ✅ Prêt | Charge conditionnellement le fichier (`def servicesJSON = file('google-services.json')`) — si absent : warning "Push Notifications won't work" |
| `android/build.gradle` racine | ✅ Configuré | `classpath 'com.google.gms:google-services:4.4.4'` présent |
| Plugin `google-services` activé | ⚠️ Conditionnel | `apply plugin: 'com.google.gms.google-services'` à l'intérieur du `if (servicesJSON.exists())` |

**Verdict** : Le build Gradle est correctement préparé. Il suffit de **déposer le fichier `google-services.json` téléchargé depuis Firebase Console** dans `android/app/` et de rebuild l'app pour que FCM s'active.

**Sans ce fichier** :
- L'app Android compile et tourne, mais `PushNotifications.register()` retourne une erreur ou aucun token
- `fn_upsert_token_push` n'est jamais appelé avec un token FCM valide

---

## 3. iOS — APNS configuration

| Élément | État | Détail |
|---|---|---|
| `ios/App/App/App.entitlements` | ❌ Absent | Aucun fichier entitlements (donc pas de `aps-environment`) |
| `ios/App/App/GoogleService-Info.plist` | ❌ Absent | Fichier Firebase iOS non présent |
| Push capability dans `project.pbxproj` | ❌ Absent | Aucune mention `aps-environment` ni `com.apple.Push` |
| `Info.plist` `UIBackgroundModes` | ❌ Absent | Pas de `<key>UIBackgroundModes</key>` avec `remote-notification` |
| `Info.plist` `NSLocalNotificationUsageDescription` | ✅ Présent | Description locale OK |

**Verdict** : **APNS complètement non configuré côté iOS**.

Pour activer iOS push natif il faut :
1. Ouvrir le projet dans Xcode (`ios/App/App.xcworkspace`)
2. Cible "App" → Signing & Capabilities → "+ Capability" → **Push Notifications**
3. "+ Capability" → **Background Modes** → cocher **Remote notifications**
4. (Capacitor va générer/mettre à jour `App.entitlements` automatiquement)
5. Générer une **APNs Authentication Key (.p8)** sur https://developer.apple.com/account → Keys → "+"
   - Cocher "Apple Push Notifications service (APNs)"
   - Télécharger le fichier `.p8`, noter le **Key ID** et le **Team ID**
6. Uploader le fichier `.p8` dans Firebase Console : Project Settings → Cloud Messaging → Apple app configuration → APNs Authentication Key
   - Renseigner Key ID + Team ID
7. Télécharger `GoogleService-Info.plist` depuis Firebase Console et le déposer dans `ios/App/App/`

Sans ces étapes, sur iOS :
- `PushNotifications.register()` échoue ou retourne un token APNS qui n'est pas convertible en token FCM
- Aucun push reçu

---

## 4. Capacitor push plugin

| Élément | État | Détail |
|---|---|---|
| `@capacitor/push-notifications` dans `package.json` | ✅ Présent | Version `^8.0.3` |
| `src/lib/pushNative.ts` initialisation | ✅ Correct | `checkPermissions` → `requestPermissions` → `register` → `addListener('registration')` |
| Token enregistré backend | ✅ Correct | Appel `supabase.rpc('fn_upsert_token_push', { p_token, p_plateforme: 'IOS'/'ANDROID' })` |
| Appelé après login | ✅ Présent | `src/pages/PageConnexion.tsx:96` : `import('@/lib/pushNative').then(m => m.initNativePush(u.id))` |
| Listener `pushNotificationActionPerformed` | ✅ Présent | Cf. PR 4 Sprint 3 (gère navigation au tap notification) |
| Distinction native vs web | ✅ OK | `isNative()` guard dans `pushNative.ts`, `DemandePermissionPush.tsx` gère uniquement le web |

**Verdict** : **Code frontend bien câblé**. Dès que l'infra Firebase sera en place, les tokens natifs commenceront à arriver dans `tokens_push` automatiquement.

---

## 5. Backend `send-push`

| Élément | État | Détail |
|---|---|---|
| Firebase Admin SDK | ❌ Non utilisé | Pas de `npm:firebase-admin` import |
| Variable `FIREBASE_SERVICE_ACCOUNT_JSON` (Supabase Vault) | ❌ Non référencée | Aucune mention dans le code |
| Dispatch Web Push (VAPID) | ✅ Présent | Utilise `npm:web-push@3.6.7` avec `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY` + `VAPID_SUBJECT` |
| Dispatch FCM HTTP v1 | ❌ Absent | Aucun appel `https://fcm.googleapis.com/v1/projects/.../messages:send` |
| Dispatch APNS HTTP/2 direct | ❌ Absent | Aucun appel `https://api.push.apple.com/3/device/...` |
| Routing par plateforme | ❌ Absent | Tous les tokens sont traités comme Web Push (endpoint + p256dh + auth_key). Les tokens FCM bruts (plateforme IOS/ANDROID) ne fonctionneront pas. |

**Verdict** : **`send-push` n'envoie QUE via Web Push VAPID**. Conséquence :
- Les soignants/étabs sur PWA Web (Chrome Desktop, Safari iOS 16.4+ PWA installée) reçoivent les push.
- **Les soignants/étabs sur app Capacitor iOS ou Android ne reçoivent rien**, même si leur token est enregistré dans `tokens_push`.

**Pour activer FCM/APNS** il faudra :
- Installer `firebase-admin` côté edge function (ou utiliser l'API REST directement)
- Ajouter `FIREBASE_SERVICE_ACCOUNT_JSON` dans Supabase Vault (download depuis Firebase Console → Project Settings → Service accounts → "Generate new private key")
- Dans `send-push`, dispatcher selon `tokens_push.plateforme` :
  - `WEB` → web-push (déjà OK)
  - `IOS` ou `ANDROID` → FCM HTTP v1 send (le dispatch APNS est géré par FCM en interne grâce à la p8 key uploadée)

---

## 6. Permissions natives iOS/Android

### Android `AndroidManifest.xml`

| Permission | État | Note |
|---|---|---|
| `INTERNET` | ✅ Présent | Requis pour FCM |
| `POST_NOTIFICATIONS` | ✅ Présent | Android 13+ runtime permission |
| `ACCESS_FINE_LOCATION` | ✅ | (pour GPS pointage) |
| `ACCESS_COARSE_LOCATION` | ✅ | (idem) |
| `CAMERA` | ✅ | (documents) |
| `READ_EXTERNAL_STORAGE` | ✅ | (upload docs) |
| `WAKE_LOCK` | ❌ Absent | Non strictement requis pour FCM moderne, mais recommandé pour Doze mode |
| `RECEIVE_BOOT_COMPLETED` | ❌ Absent | Non strictement requis avec FCM v1, mais utile pour re-registration au boot |

### iOS `Info.plist`

| Clé | État | Note |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | ✅ Présent | (GPS pointage) |
| `NSCameraUsageDescription` | ✅ | (docs) |
| `NSPhotoLibraryUsageDescription` | ✅ | (docs) |
| `NSLocalNotificationUsageDescription` | ✅ | (notifications locales) |
| `UIBackgroundModes` avec `remote-notification` | ❌ **Absent** | Bloquant pour push background iOS |
| `aps-environment` (entitlement) | ❌ Absent | Bloquant — APNS ne fonctionne pas |

---

## Récap des manques (à fixer en Sprint 4)

### P0 (bloquant push natif)
1. **Android `google-services.json`** : créer/identifier projet Firebase, télécharger fichier, déposer dans `android/app/`
2. **iOS Push capability** : activer Push Notifications + Background Modes (remote-notification) dans Xcode → génère `App.entitlements`
3. **iOS p8 APNS** : créer la clé sur developer.apple.com, uploader dans Firebase Console
4. **iOS `GoogleService-Info.plist`** : télécharger depuis Firebase Console, déposer dans `ios/App/App/`
5. **Backend Firebase Admin SDK** : ajouter `FIREBASE_SERVICE_ACCOUNT_JSON` en Vault, refacto `send-push` pour dispatcher FCM HTTP v1 (qui prend en charge APNS via la p8 uploadée)

### P1 (qualité / robustesse)
6. **Android `WAKE_LOCK`** + **`RECEIVE_BOOT_COMPLETED`** : ajouter dans AndroidManifest pour robustesse Doze mode
7. **Notification channels Android** : déclarer channels par type (urgence, info, paiement) dans `MainActivity` Java
8. **iOS rich notifications** : extension UNNotificationServiceExtension pour images/actions
9. **Test smoke E2E** : tester réception push via TestFlight (iOS) et Internal Sharing (Android)

### P2 (nice to have)
10. **Firebase Console alerting** : webhook Slack si > 5% des push échouent
11. **Topic subscriptions** : pour les soignants matchant un filtre, abonner à un topic FCM plutôt qu'envoyer 1 push par device

---

## Configuration cible (résumé pour mail Firebase Console)

À mettre dans Supabase Vault après création du projet Firebase :
- `FIREBASE_SERVICE_ACCOUNT_JSON` : contenu complet du service account JSON (cf. Firebase Console → Project Settings → Service accounts → Generate new private key)
- `FIREBASE_PROJECT_ID` : ID du projet (ex: `jolene-mobile-prod`)

À déposer dans le repo :
- `android/app/google-services.json` (gitignored mais déployé via CI/CD secret)
- `ios/App/App/GoogleService-Info.plist` (idem)
- `ios/App/App/App.entitlements` (généré par Xcode, commité)

Côté Apple Developer :
- APNs Authentication Key (.p8) — gardé localement, uploadé dans Firebase Console (Firebase Cloud Messaging dispatche vers APNS automatiquement)

Estimation effort : **1-2 jours** pour Gabrielle (Firebase Console + Xcode + uploads) + **0.5 jour** pour refacto `send-push` côté code.

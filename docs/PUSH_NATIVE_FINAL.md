# Push natif iOS + Android — architecture et procédure Sprint final

> Sprint 4 a préparé tout le code multi-plateforme. Ce doc trace la
> procédure complète à exécuter au Sprint final pour activer les push
> natifs.

## Architecture `send-push`

Le edge function `supabase/functions/send-push/index.ts` (refacto Sprint 4 PR 1)
dispatche selon `tokens_push.plateforme` :

| `plateforme` | Canal | Lib | Auth |
|---|---|---|---|
| `WEB` | Web Push RFC 8030 | `web-push@3.6.7` | `VAPID_PUBLIC_KEY` + `VAPID_PRIVATE_KEY` |
| `IOS` | FCM HTTP v1 → APNS | OAuth2 service account JWT inline | `FIREBASE_SERVICE_ACCOUNT_JSON` |
| `ANDROID` | FCM HTTP v1 | OAuth2 service account JWT inline | `FIREBASE_SERVICE_ACCOUNT_JSON` |

Le JWT OAuth2 est signé via Web Crypto API (RSASSA-PKCS1-v1_5) sans
dépendance externe Deno. Token caché 50 min.

**Fallback gracieux** : si `FIREBASE_SERVICE_ACCOUNT_JSON` absent :
- Tokens IOS/ANDROID skip avec `console.warn` count
- Web Push continue à fonctionner sans régression
- Réponse JSON inclut `{ fcm_configured: false, skippedFcm: N }`

## Variables d'env requises (Supabase Vault)

À ajouter au Sprint final :

```
FIREBASE_SERVICE_ACCOUNT_JSON = '{"type":"service_account","project_id":"jolene-mobile-prod","private_key":"-----BEGIN PRIVATE KEY-----\\n..."...}'
FIREBASE_PROJECT_ID = jolene-mobile-prod  # optionnel, lu depuis SA JSON sinon
```

Déjà présentes :
```
VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY
VAPID_SUBJECT = mailto:contact@jolene.app
```

## Procédure complète Sprint final

### Étape 1 — Créer projet Firebase Console
1. https://console.firebase.google.com/ → "Add project"
2. Nom : "Jolene Mobile" (ou similaire)
3. Activer Google Analytics : optionnel
4. Project ID : `jolene-mobile-prod`

### Étape 2 — Activer Cloud Messaging
1. Project Settings → Cloud Messaging
2. Cloud Messaging API (V1) déjà activée par défaut sur les nouveaux projets

### Étape 3 — Configuration Android
1. Firebase Console → "Add app" → Android
2. Package name : `app.jolene` (= `applicationId` Gradle, cf. `capacitor.config.ts`)
3. Télécharger `google-services.json`
4. Déposer dans `android/app/google-services.json`
5. Le build Gradle est déjà configuré (cf. `android/app/build.gradle` + `android/build.gradle` Sprint 4)

### Étape 4 — Compte Apple Developer Program
1. https://developer.apple.com/programs/ → S'inscrire (99 USD/an)
2. Renseigner identité légale Jolene SASU
3. Validation Apple sous 24-48h

### Étape 5 — Configuration App ID Apple + Capabilities
1. https://developer.apple.com/account → Identifiers → "+" → App IDs
2. Bundle ID : `app.jolene` (cf. `capacitor.config.ts`)
3. Activer les Capabilities :
   - Push Notifications (P0)
   - Sign In with Apple (P1)
   - Time Sensitive Notifications (P1)
   - Communication Notifications (P2)
   - Associated Domains (pour deep links Jolene)
4. Save

### Étape 6 — Créer APNs Auth Key (.p8)
1. Apple Developer → Keys → "+"
2. Cocher "Apple Push Notifications service (APNs)"
3. Télécharger le fichier `AuthKey_XXXXXXXXXX.p8` (UN seul download possible !)
4. Noter le **Key ID** (10 chars) et le **Team ID** (visible en haut à droite du compte)

### Étape 7 — Upload p8 dans Firebase Console
1. Firebase Console → Project Settings → Cloud Messaging
2. Section "Apple app configuration" → APNs Authentication Key
3. Upload le `.p8` + saisir Key ID + Team ID
4. Save → FCM va dispatcher APNS automatiquement

### Étape 8 — Configuration iOS dans Xcode
1. Ouvrir `ios/App/App.xcworkspace` dans Xcode
2. Cible "App" → Signing & Capabilities → "+ Capability"
   - Push Notifications
   - Background Modes → cocher "Remote notifications"
3. (Capacitor génère/met à jour `App.entitlements` automatiquement)
4. Vérifier `Info.plist` : `UIBackgroundModes` contient `remote-notification` (déjà ajouté Sprint 4 PR 4)

### Étape 9 — Télécharger `GoogleService-Info.plist`
1. Firebase Console → "Add app" → iOS
2. Bundle ID : `app.jolene`
3. Télécharger `GoogleService-Info.plist`
4. Déposer dans `ios/App/App/GoogleService-Info.plist`
5. Dans Xcode : drag & drop dans le projet (cible App)

### Étape 10 — Générer service account JSON Firebase
1. Firebase Console → Project Settings → Service accounts
2. "Generate new private key" → télécharger JSON
3. Copier le contenu intégral du JSON
4. Supabase Dashboard → Project Settings → Edge Functions → Secrets :
   ```
   FIREBASE_SERVICE_ACCOUNT_JSON = <coller le JSON complet>
   FIREBASE_PROJECT_ID = jolene-mobile-prod
   ```
5. Save → le worker `send-push` va switcher en mode multi-plateforme au prochain appel

### Étape 11 — `npx cap sync`
```bash
npx cap sync ios
npx cap sync android
```

### Étape 12 — Compte Google Play Console
1. https://play.google.com/console → S'inscrire (25 USD one-time)
2. Créer fiche app "Jolene"
3. Internal testing track → ajouter testeurs internes

### Étape 13 — Build & soumissions

**iOS** :
```bash
npx cap copy ios
cd ios/App
xcodebuild -workspace App.xcworkspace -scheme App -archivePath ./Jolene.xcarchive archive
# Upload via Xcode Organizer → App Store Connect → TestFlight
```

**Android** :
```bash
npx cap copy android
cd android
./gradlew bundleRelease
# Upload AAB via Play Console → Internal testing
```

### Étape 14 — Tests sur devices réels
- TestFlight : inviter les comptes test
- Play Console Internal : ajouter testeurs
- Vérifier :
  - [ ] Inscription → permission push demandée
  - [ ] Login → token enregistré dans `tokens_push` (vérifier en MCP)
  - [ ] Mission urgente → push reçu < 30s
  - [ ] Tap notification → navigation vers écran cible (cf. PR 7 S4 `navigationPathForEvent`)
  - [ ] App background → notification visible
  - [ ] App killed → tap notification ouvre app sur bon écran
  - [ ] Logout → token supprimé (cf. PR 4 S3 `fn_supprimer_mes_tokens_push`)

### Étape 15 — Soumission production stores
- TestFlight → submit for App Store Review
- Play Console Internal → Closed → Open → Production

## Troubleshooting commun

### Pas de token reçu côté Android
- Vérifier `android/app/google-services.json` est bien présent
- `cat android/app/build.gradle` doit avoir `apply plugin: 'com.google.gms.google-services'` actif
- Logcat : chercher `[PUSH] Registered with token` (logger.debug Capacitor)

### Pas de token reçu côté iOS
- Vérifier Capabilities Push Notifications activée (Xcode → Signing & Capabilities)
- Vérifier `App.entitlements` contient `aps-environment` = `production`
- Vérifier p8 + Key ID + Team ID corrects dans Firebase Console
- Tester avec `Background Modes → Remote notifications` activé

### `skippedFcm > 0` dans la réponse send-push
- `FIREBASE_SERVICE_ACCOUNT_JSON` absent ou invalide en Supabase Vault
- Vérifier les logs edge function : `[send-push] FIREBASE_SERVICE_ACCOUNT_JSON parse/auth failed`
- Re-coller le JSON complet (incluant les newlines `\n` dans private_key)

### Push reçu mais ne navigue pas
- Vérifier `data.lien` dans le payload FCM
- Sinon vérifier `data.type_evenement` matche un cas dans `navigationPathForEvent` (PR 7 S4)
- En foreground : pas de nav auto (intentionnel) → écouter `jolene:push-foreground` CustomEvent

### Notification Android sans son ni vibration
- Vérifier les channels créés dans `MainActivity.onCreate` (PR 7 S4)
- Vérifier `channel_id` dans le payload FCM (cf. `channelForType` helper PR 1 S4)
- Configurer manuellement dans Paramètres Android → Notifications

## App ID unifié (Sprint Capacitor — finalisation)

L'identifiant **`app.jolene`** est désormais l'App ID **permanent** (non modifiable
après publication store), aligné sur les 4 sources :

| Source | Champ | Valeur |
|---|---|---|
| `capacitor.config.ts` | `appId` | `app.jolene` |
| `android/app/build.gradle` | `applicationId` | `app.jolene` |
| `ios/App/App.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` (Debug + Release) | `app.jolene` |
| `public/.well-known/assetlinks.json` | `package_name` | `app.jolene` |

**Note Android namespace** : le `namespace` Gradle (`app.jolene.android`) et le
package Java de `MainActivity` restent inchangés — c'est **légitime et voulu**
sous AGP 8 : `applicationId` = identité store (ce que voient Firebase/Play),
`namespace` = package interne des classes générées (R/BuildConfig, invisible
des stores). Les déplacer casserait le build sans bénéfice.

**Note `App.entitlements`** : ce fichier N'EST PAS dans le repo. Il est généré
**automatiquement par Xcode** quand Gabrielle active la capability *Push
Notifications* (étape 8 ci-dessus). C'est le comportement attendu — ne pas le
créer à la main.

## ✅ Runbook checklist — actions Gabrielle restantes

> Le code est 100% prêt (App ID unifié, AppDelegate APNs, Info.plist, send-push FCM).
> Il ne reste QUE des actions console/Xcode ci-dessous.

### A. Firebase Console (projet EXISTANT — `FIREBASE_SERVICE_ACCOUNT_JSON` déjà en place)
- [ ] **App iOS** : Project Settings → Add app → iOS → Bundle ID **`app.jolene`** → télécharger `GoogleService-Info.plist`
- [ ] Déposer le fichier dans **`ios/App/App/GoogleService-Info.plist`** (gitignoré — ne pas commit) + drag&drop dans Xcode (cible App)
- [ ] **App Android** : Add app → Android → Package name **`app.jolene`** → télécharger `google-services.json`
- [ ] Déposer dans **`android/app/google-services.json`** (gitignoré)

### B. Clé APNs (Apple Developer → Firebase)
- [ ] Apple Developer → Certificates/Identifiers → **Identifiers** → créer App ID **`app.jolene`** avec capability **Push Notifications**
- [ ] Apple Developer → **Keys** → "+" → cocher **APNs** → télécharger `AuthKey_XXXXXXXX.p8` (1 seul téléchargement !) + noter **Key ID** et **Team ID**
- [ ] Firebase Console → Project Settings → Cloud Messaging → **Apple app configuration** → uploader le `.p8` + Key ID + Team ID

### C. Xcode (sur le Mac)
- [ ] `npx cap sync ios` (copie config + plugins)
- [ ] Ouvrir `ios/App/App.xcworkspace`
- [ ] Cible App → Signing & Capabilities → vérifier **Team** (compte Apple Developer) + Bundle ID = `app.jolene`
- [ ] "+ Capability" → **Push Notifications** (génère `App.entitlements` avec `aps-environment`)
- [ ] "+ Capability" → **Background Modes** → cocher **Remote notifications** (déjà dans Info.plist via `UIBackgroundModes`, la capability le rend actif)

### D. Build & soumission
- [ ] **iOS** : Xcode → Product → Archive → Distribute App → App Store Connect → TestFlight
- [ ] **Android** : `npx cap sync android` puis `cd android && ./gradlew bundleRelease` → upload `.aab` dans Play Console → Internal testing

### E. Vérification fonctionnelle (post-install device réel)
- [ ] Login sur l'app → permission push demandée → token enregistré dans `tokens_push` (vérifier en MCP : `SELECT plateforme, COUNT(*) FROM tokens_push GROUP BY plateforme`)
- [ ] Envoyer une mission urgente → push reçu < 30s
- [ ] Tap notification → ouvre le bon écran (cf. `navigationPathForEvent`)

## Roadmap post-Sprint final

- iOS rich notifications (UNNotificationServiceExtension pour images/actions)
- Topic subscriptions FCM (broadcast pool urgence sans envoyer 1 push par device)
- Webhook Firebase Console → Slack si > 5% des push échouent
- A/B tester les titres/corps de notifications via Firebase Remote Config

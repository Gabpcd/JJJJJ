# Plan de l'application native Swift Jolene

> Proposition rédigée le 1er novembre 2026 par Claude Code à partir d'une
> cartographie du dépôt (cinq lecteurs), de trois propositions d'architecture
> indépendantes et d'un jury contradictoire. Les neuf décisions de la section 10
> ont été tranchées par Gabrielle le 1er novembre 2026 (toutes les
> recommandations suivies) : voir `docs/mobile-swift/DECISIONS_LOT0.md`.

Document destiné à Gabrielle. Il est rédigé à partir du verdict du jury (approche A retenue, avec greffes des approches B et C) et des cartographies du dépôt. Tous les chemins cités existent dans le dépôt, sauf ceux explicitement marqués « à créer ».

## 1. Résumé

L'application mobile actuellement publiée sur l'App Store et le Play Store est une coquille Capacitor (bundle `app.jolene`, version 1.0.7, build 24, Team `GDU5AA28M9`). Elle embarque toute l'application web dans une WKWebView. Le pilote construit en parallèle dans `mobile-native/` est en React Native/Expo, pas en Swift, et n'a atteint aucune preuve d'intégration STAGING. Le backend Supabase (RPC Postgres, edge functions, Storage, Auth, Realtime) est complet et consommable tel quel par un client natif.

Recommandation : réécrire le client iOS en SwiftUI, dans un nouveau dossier `ios-native/` (à créer), en reprenant à l'identique l'identité store, les entitlements, l'AASA et le contrat push. Le backend n'est pas touché. Android reste la coquille Capacitor publiée pendant tout le chantier. Le pilote React Native est gelé immédiatement, puis archivé après extraction de ce qui a valeur de spécification.

Premier jalon : un lot 0 de deux semaines environ qui livre le socle Xcode, la chaîne de preuve (tests unitaires, XCUITest démo, CI macOS) et une première connexion réelle sur STAGING. Ce lot se termine par une porte go/no-go écrite sur supabase-swift. Aucune soumission store avant la parité soignant et établissement terrain.

## 2. État des lieux factuel

### 2.1 Application publiée (coquille Capacitor)

Identité iOS réelle, lue dans `ios/App/App.xcodeproj/project.pbxproj` : bundle `app.jolene` (l.318), Team `GDU5AA28M9` (l.308), version 1.0.7 (l.316), build 24 (l.307), cible iOS 15.0 (l.239), universel iPhone et iPad (l.322). Apple ID App Store `6774672845` (`src/components/NativeStoreUpdate.tsx` l.12). Source de version unique : `config/mobile-release.json` (1.0.7 / 24), vérifiée par `scripts/check-mobile-build-alignment.mjs`.

Android : `android/app/build.gradle` l.75-79, applicationId `app.jolene`, versionCode 24, versionName 1.0.7, FCM, six canaux de notification dans `android/app/src/main/java/app/jolene/android/MainActivity.java`.

Ce qui doit être repris à l'identique :
- `ios/App/App/App.entitlements` : `aps-environment`, `applinks:jolene.app`, `webcredentials:jolene.app`.
- `ios/App/App/Info.plist` : huit chaînes d'usage en français, `ITSAppUsesNonExemptEncryption=false`, `CFBundleDevelopmentRegion fr`.
- `ios/App/App/PrivacyInfo.xcprivacy` : types de données déclarés, à recalculer pour les raisons d'API.
- `ios/ExportOptions-AppStore.plist` : signature manuelle « Apple Distribution: Jolene App (GDU5AA28M9) », profil « Jolene App Store Distribution ».
- `public/.well-known/apple-app-site-association` : quinze motifs de chemins pour deux Team ID (`GDU5AA28M9` courant, `FPQ78HDF4Y` hérité).

Push iOS : APNs direct, sans Firebase. Le token APNs brut est enregistré par la RPC `fn_upsert_token_push(p_token, p_plateforme)` (`supabase/migrations/20260712230000_p0_securite_auth_rls.sql` l.1605) et consommé par `supabase/functions/send-push/index.ts` via `supabase/functions/_shared/apns-client.ts`. La table de routage des taps est `navigationPathForEvent` dans `src/lib/pushNative.ts`.

Session : stockée dans le localStorage de la WKWebView (`src/integrations/supabase/auth-storage.ts`). Biométrie : `src/lib/biometric.ts` stocke le refresh token dans le trousseau via le plugin Capgo. Point important vérifié : `src/pages/PageConnexion.tsx` appelle `enableBiometric` au login par mot de passe (l.161) mais jamais après `refreshSession` (l.194). Le token stocké est donc consommé et tourné dès la première reconnexion biométrique. Il ne peut pas être récupéré par l'app Swift.

Mise à jour OTA : `src/lib/mobileUpdates.ts`, manifest signé avec `config/mobile-update-public.pem`, publié par `scripts/mobile/publish-update.mjs`. Ce canal disparaît pour iOS en natif (règle Apple 2.5.2) et reste pour Android.

Documents périmées à marquer comme telles dès le lot 0 : `docs/store-readiness.md`, `docs/PUSH_NATIVE_FINAL.md`, `docs/CAPACITOR_PRODUCTION.md` (Team `FPQ78HDF4Y`, « 1.0 (16) », signature bloquée). L'état réel est 1.0.7 (24) publié sous `GDU5AA28M9`, comme vous l'avez confirmé.

### 2.2 Pilote React Native (mobile-native/)

Le pilote `mobile-native/` cible le bundle `app.jolene.nativepilot` et uniquement le projet STAGING. Chiffres confirmés : environ 9 600 lignes TypeScript applicatives, 4 200 lignes de tests, 1 720 lignes de Swift (`mobile-native/ios-ui-tests/NativePilotUITests/NativePilotTests.swift`, `mobile-native/ios-auth-ui-tests/NativeAuthUITests/NativeAuthTests.swift`, `mobile-native/ios-ui-tests/UIKitOtpReference/UIKitOtpReference.swift`).

Niveau de preuve réel : simulation sur fixtures fictives uniquement. Aucun parcours n'a atteint STAGING (`mobile-native/MIGRATION.md`). Le pointage n'a jamais été exécuté nativement (`mobile-native/PRESENCE-SCENARIO-PREPARATION.md`). La campagne Auth STAGING est prête (`mobile-native/AUTH_STAGING.md`, `.github/workflows/native-auth-staging.yml`) mais jamais lancée.

Dette révélée par la CI : patch du cœur React Native 0.86.3 issu d'une PR upstream non fusionnée, appliqué par `mobile-native/scripts/rn-text-input-patch.cjs` avec compilation forcée depuis les sources (`mobile-native/patches/`, `mobile-native/plugins/`), jobs iOS plafonnés à 140 minutes sur macos-26 (`.github/workflows/native-pilot.yml` l.89-90), touchers annulés par BackBoard sans cause établie.

Ce qui a valeur de spécification : les contrats de données (`mobile-native/src/data/types.ts`, `mobile-native/src/workflows/*/types.ts`, `mobile-native/src/account/types.ts`, `mobile-native/src/establishment/types.ts`), les journaux de reçus durables (`mobile-native/src/documents/uploadJournal.ts`, `mobile-native/src/workflows/presence/attemptJournal.ts`), la politique de configuration (`mobile-native/src/session/config.ts`), le contrôleur de session à epoch (`mobile-native/src/session/controller.ts`), les fixtures démo (`mobile-native/src/data/demoGateway.ts`, `mobile-native/src/contracts/demoFixture.ts`, `mobile-native/src/workflows/documents/demoScenario.ts`, `mobile-native/src/workflows/presence/demoGateway.ts`), les helpers XCUITest et le champ OTP UIKit.

Limite importante : le pilote ne couvre que le second système de pointage du web. `mobile-native/src/workflows/presence/supabaseGateway.ts` n'appelle que `fn_scanner_code_pointage` (l.367), `fn_etat_pointage_mission` (l.225) et `fn_contrat_signe_pour_pointage` (l.221). Il n'appelle jamais `fn_pointer_arrivee`, `fn_pointer_depart` ni `fn_valider_scan_qr`. Son QR encode le code à six chiffres (`mobile-native/src/ui/presence/qr.ts`) alors que le QR affiché par l'établissement web encode un token de `fn_generer_qr_mission` (`src/components/etablissement/QRPointageEtab.tsx` l.88) validé par `fn_valider_scan_qr` et rejoué par `src/lib/qr-offline-queue.ts`.

### 2.3 Backend à conserver

Le client web appelle environ 339 RPC distinctes, 43 edge functions, 44 tables sous RLS, 5 buckets Storage et 5 tables Realtime. Les signatures sont dans `src/integrations/supabase/types.ts` et `supabase/schema/public.sql`. Les classes d'authentification sont dans `supabase/SECURITY_DEFINER_MANIFEST.json` et `supabase/EDGE_AUTH_MANIFEST.json`.

Points vérifiés qui confirment qu'aucune réécriture n'est nécessaire :
- Les edge functions retombent sur `https://jolene.app` quand l'en-tête Origin est absent (`supabase/functions/_shared/cors.ts`). Un client URLSession n'envoie pas d'Origin : c'est le comportement voulu.
- Turnstile n'est pas vérifié par `register-soignant` ni `register-etablissement`. Seule `supabase/functions/contact-form/index.ts` importe `supabase/functions/_shared/verify-turnstile.ts`. `supabase/functions/register-soignant/index.ts` l.231-234 indique que le token est consommé par `supabase.auth.signUp` et ne doit pas être revalidé. Le build natif livre déjà `VITE_TURNSTILE_SITE_KEY=''` (`.github/workflows/mobile-delivery.yml` l.75) et `src/components/CaptchaTurnstile.tsx` l.12 exempte le natif. L'inconnue réelle est le réglage « captcha protection » de GoTrue dans le dashboard Supabase, non visible dans le dépôt.
- `fn_admission_otp_signature_recette` n'existe pas en production. Elle est définie dans `scripts/ci/sms-signature-staging.sql` l.121 et installée sur STAGING par `scripts/ci/install-sms-staging-closed-sql.mjs`. C'est un dispositif de recette STAGING, pas un contrat de production.
- Le pointage web repose sur deux systèmes : token QR (`fn_generer_qr_mission` puis `fn_valider_scan_qr`, file hors-ligne `src/lib/qr-offline-queue.ts` où un QR expiré n'est jamais remis en file, l.84) et code rotatif (`fn_scanner_code_pointage`, `supabase/migrations/20261017165819_garantir_rotation_code_pointage.sql`). Les deux doivent être reproduits.

### 2.4 Chaîne de livraison

Livraison manuelle uniquement : `.github/workflows/mobile-delivery.yml` (workflow_dispatch sur main, modes check / native / ota). Gardes : `scripts/mobile/delivery-plan.mjs` (build strictement supérieur aux tags existants, l.78 ; diff natif sur `ios`, `android`, `package.json`, `capacitor.config.ts`, `config`, `scripts/mobile`, l.90), `scripts/mobile/delivery-plan-backend.mjs` (preuve de déploiement Supabase), `scripts/mobile/release-state.mjs` (l'action `complete` exige les deux tags `mobile-native-ios-N` et `mobile-native-android-N`). Signature : `scripts/mobile/prepare-ci-signing.mjs`. Soumission : `fastlane/Fastfile` lane `ios submit` avec garde `fastlane/ios_review_submission.rb`. Statut stores en lecture seule : `.github/workflows/mobile-store-status.yml`, `scripts/mobile/store-status.rb`.

Conséquence structurante : un tag `mobile-native-25` ne pourra jamais être posé sans build Android 25. La scission iOS Swift / Android Capacitor des tags et de la matrice est obligatoire dès la première livraison Swift, pas en fin de chantier.

## 3. Approche retenue et pourquoi

### 3.1 Approche retenue : réécriture SwiftUI complète, parcours soignant d'abord

L'app iOS est réécrite en Swift (SwiftUI, UIKit ciblé pour le champ OTP et le scanner), dans `ios-native/` (à créer), sur le SDK éditeur supabase-swift. Le backend est consommé sans modification. L'app vit en TestFlight sur le même App ID pendant tout le chantier, ce qui valide push, Universal Links et Keychain dans les conditions exactes de la production. Elle ne remplace 1.0.7 sur l'App Store qu'après parité soignant signée et établissement terrain couvert. Les autres rôles sont renvoyés vers jolene.app.

Pourquoi cette approche gagne :
- Chaque hypothèse structurante est vérifiable dans le dépôt et tient : RPC et edge confirmés, AASA inchangée, identité store reprise à l'identique.
- Elle respecte vos contraintes à la lettre : Swift, pas de WebView comme coquille, backend intact, petite équipe, un seul langage, un SDK éditeur, pas de patch de framework.
- Elle coûte le moins à maintenir à deux ans.
- Elle ne recule sur aucune preuve acquise : aucun parcours du pilote RN n'a atteint STAGING.

Son vrai prix est le temps : pas de remplacement de 1.0.7 avant l'enchaînement des lots 0 à 6, et un TestFlight sans pointage avant la fin du lot 2. C'est acceptable parce que la coquille publiée continue de servir iOS et Android pendant tout le chantier.

Trois corrections appliquées au plan A d'origine :
1. L'inscription native ne dépend pas de Turnstile côté edge mais de l'état de la protection captcha GoTrue. C'est un test à faire sur STAGING au lot 0, pas un chantier backend.
2. `fn_admission_otp_signature_recette` est nommée comme dispositif STAGING dans les critères de sortie, jamais comme contrat de production.
3. Le pointage reproduit les deux systèmes QR du web, pas seulement celui du pilote RN.

Greffes retenues des approches B et C : table de routage AASA exhaustive testée au lot 0, suppression de compte native dès le premier TestFlight, garde Apple 4.2 écrite comme critère de sortie du lot 6, drapeau distant `fn_param_bool` (sous réserve de votre décision), WKWebView bornée pour la longue traîne (sous réserve de votre décision), test CI de dérive des contrats RPC, jeu unique de fixtures JSON, plans XCUITest par domaine, porte go/no-go écrite à la fin du lot 0, flows Maestro conservés par tag.

### 3.2 Alternatives écartées

Approche B, Swift hybride (cœur natif plus WKWebView authentifiée). La plus rapide vers un TestFlight utilisable et la seule à ne jamais faire régresser un utilisateur. Mais son mécanisme central est fragile : supabase-js (`package.json`, `^2.99`) rafraîchit une session expirée lors d'un `getSession()` indépendamment de `autoRefreshToken`, ce qui fait tourner le refresh token rotatif et invalide celui du natif. Elle impose trois branches de plateforme dans le front et un pont JS à maintenir pendant deux ans. Une WKWebView dans l'app Swift est la coquille que vous rejetez. Ses meilleures idées sont greffées sur A.

Approche C, socle Kotlin Multiplatform plus SwiftUI plus Compose. Seule approche qui couvre réellement Android, et honnête sur son point de bascule. Mais rien dans le dépôt ne permet de vérifier ses prémisses : aucun fichier Kotlin, aucune mention de supabase-kt ni de SKIE. Elle exige deux développeurs dont un Kotlin, Gradle et JDK sur le runner macOS, deux langages à déboguer. Le cœur métier serait en Kotlin, seules les vues en Swift. Elle ne se justifie que si vous demandez Android natif à court terme, ce que vous n'avez pas demandé.

Continuer le pilote React Native jusqu'à parité. Le dépôt prouve lui-même sa dette : patch non fusionné du cœur RN 0.86.3 à reporter à chaque montée de version, 140 minutes de macOS par job, touchers annulés non expliqués, rendu non natif. Ce n'est pas du Swift. Écarté.

## 4. Architecture cible Swift

### 4.1 Modules

Dossier racine `ios-native/` (à créer), et non `ios/` que `scripts/mobile/delivery-plan.mjs` l.90 diffe encore pour la coquille Capacitor. Il contient `Jolene.xcodeproj` et trois packages Swift locaux :

- `Packages/JoleneCore` (zéro UIKit ni SwiftUI) : modèles Codable dérivés de `src/integrations/supabase/types.ts` et des projections du pilote ; enums à valeurs associées pour les résultats de candidature (confirmed / choice / rejected / unconfirmed) et de scan de présence ; règles pures portées depuis `src/lib` (`disponibilite-pointage.ts`, `heures-hebdomadaires-mission.ts`, `completude-planning-mission.ts`, `format-mission.ts`, `date-heure-paris.ts`, `geo.ts`, `profession-hierarchy.ts`, `documentUpload.ts`, `luhn.ts`, `nativeLinks.ts`, `nativeResume.ts`, `pushNative.ts`) et depuis `src/components/planning/planning-candidat.ts` et `selection-serie-candidat.ts`, testées avec des vecteurs JSON exportés des tests vitest existants ; protocols de ports par domaine (auth, missions, présence, documents, contrats, compte, stockage sécurisé, horloge, GPS) ; journaux de reçus durables en Keychain avec les phases prepared / started / refused / not_sent et la règle « aucun renvoi automatique, réconciliation par relecture » ; contrôleur de session (actor) avec epoch d'identité et invalidation de tous les caches au changement d'identité.
- `Packages/JoleneSupabase` : implémentations des ports via supabase-swift (Auth PKCE avec stockage Keychain personnalisé, PostgREST, Functions, Storage avec préfixe `auth.uid()/`, Realtime v2 sur `notifications`, `messages_chat`, `typing_status`, `presence_status`, `conversations`) ; garde d'environnement qui n'accepte que `demo`, `staging` et `production`, exige une clé `sb_publishable_`, refuse toute clé secrète et affiche un écran bloquant sinon ; second client sans persistance pour les cinq RPC publiques ; implémentations Demo alimentées par les fixtures JSON.
- `Packages/JoleneDesign` : jetons (couleurs déjà présentes dans `android/` et `ios/App/App/Assets.xcassets`), composants SwiftUI, champ OTP UIKit repris de `mobile-native/ios-ui-tests/UIKitOtpReference/UIKitOtpReference.swift`, clavier mappé depuis `src/lib/inputMobile.ts`.

Cible app `Jolene` : TabView Accueil / Explorer / Mes missions / Revenus / Profil, calquée sur `src/components/BarreNavigation.tsx` l.33-37 ; NavigationStack par onglet ; routeur de liens ; coordinateur push ; cycle de vie de scène (reprise après 30 minutes selon `src/lib/nativeResume.ts`).

Cibles de test : `JoleneCoreTests` (vecteurs JSON), `JoleneSupabaseTests` (transports injectés, erreurs PostgREST PGRST202 et 300 à 303 traitées comme refus définitifs), `JoleneUITests` (XCUITest, helpers repris de `NativePilotTests.swift` : `assertMissionsTabLabelFits`, `backGesture`, `scrollTo`, `record`), plans de test `Demo` et `Staging` découpés par domaine.

### 4.2 SDK et configuration

supabase-swift est le seul SDK réseau. Pas de Firebase. Sentry Cocoa au lot 3. Configuration par xcconfig (Base, Staging, Production) avec URL Supabase, clé publishable, environnement et `APS_ENVIRONMENT`. Deux schemes, `Jolene` et `Jolene-Staging`, tous deux sur le bundle `app.jolene` pour que push, Universal Links et Keychain soient testés à l'identique. `Info.plist`, entitlements et `PrivacyInfo.xcprivacy` sont copiés de `ios/App/App/` puis révisés.

Porte go/no-go à la fin du lot 0, avec mesures écrites : support réel des clés `sb_publishable_`, du PKCE et du stockage Keychain personnalisé par supabase-swift, temps de build CI. Si une de ces mesures échoue, la contrainte est consignée avant de figer la session.

### 4.3 Authentification et session

Connexion par email et mot de passe. Session complète conservée en Keychain par supabase-swift (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, pas de sauvegarde iCloud). Biométrie : LocalAuthentication protège l'accès au Keychain. On ne copie pas le schéma Capgo du refresh token stocké à part, qui est un défaut latent de l'app publiée.

Rôle résolu par `fn_get_my_role` avec raccourci `app_metadata` (`src/hooks/useRole.ts`) et repli legacy de `src/hooks/useEtablissementScope.ts`. Rôles ADMIN_PLATEFORME et ADMIN_GROUPE : écran de renvoi vers jolene.app, aucune RPC `fn_admin_*` embarquée.

Callbacks email : Universal Links `/inscription/confirmer` et `/reset-password`, trois formats (PKCE `code`, `token_hash`, implicit) portés depuis `extraireRecoveryCredentials` de `src/lib/nativeLinks.ts`. Pro Santé Connect : `ASWebAuthenticationSession` vers `psc-authorize`, retour par `/auth/psc/callback` puis `verifyOTP` de type magiclink, jamais `signInWithOAuth`. PSC masqué par drapeau serveur tant que les credentials ANS ne sont pas en place (`docs/PSC-BASCULE-PROD.md`).

### 4.4 Données

Chaque gateway relit l'objet après mutation (règle « aucun succès fabriqué »). Reçu durable écrit avant tout upload Storage et avant tout scan de pointage. Montants, net estimé et règles juridiques restent des valeurs serveur jamais recalculées. Test CI de dérive des contrats : un script qui lit `src/integrations/supabase/types.ts` et échoue si une RPC consommée par le client Swift a changé de signature. Les 32 RPC absentes de `supabase/SECURITY_DEFINER_MANIFEST.json` sont classées avant consommation.

### 4.5 Capacités natives

VisionKit ou AVFoundation pour le QR, CoreLocation When In Use, PHPicker et caméra avec conversion HEIC vers JPEG obligatoire (`src/lib/documentUpload.ts` refuse le HEIC), EventKit pour le calendrier, PDFKit pour les contrats serveur (jamais régénérés côté client), `UIActivityViewController` pour les partages, `SFSafariViewController` pour Stripe Connect hosted et les pages légales, NWPathMonitor pour la file hors-ligne, `UNUserNotificationCenter` pour le push. Aucun `UIBackgroundModes`, aucun scheme custom.

### 4.6 Mode démo

Argument de lancement `-JOLENE_MODE demo`. Un seul jeu de fixtures JSON versionné hors du code applicatif, exporté du pilote (30 missions, contrat fictif rendu par `supabase/functions/_shared/cdd-employeur.ts`, monde de pointage avec codes 123456 / 654321 / 100001 / 100002, horloge fixée), chargé par les gateways Demo et par les XCUITest. Un test prouve qu'aucune requête réseau ne part en mode démo.

### 4.7 Preuves et XCTest

Cinq niveaux de preuve hérités du pilote : tests injectés, démo simulateur, STAGING, fournisseurs TEST, appareil physique. Un lot n'est livré que si les niveaux exigés par ses critères de sortie sont acquis. Mergé n'est pas livré. La preuve est une assertion, jamais une capture seule. Convention d'`accessibilityIdentifier` reprise du pilote (`tab-*`, `login-scroll`, `contract-otp`). Plans XCUITest découpés par domaine, chacun sous 15 minutes, avec `build-for-testing` partagé. Diagnostics backboardd repris de `mobile-native/scripts/ios-failure-diagnostics.mjs`.

### 4.8 CI macOS

Nouveau workflow `.github/workflows/ios-swift-ci.yml` (à créer) sur macos-26 : résolution SPM en cache, `build-for-testing`, puis `test-without-building` sur trois destinations (iPhone, iPad portrait, iPad paysage), export xcresult, contrôle d'orientation des captures (`mobile-native/scripts/png-dimensions.mjs` repris), timeout de job 60 minutes. Workflow STAGING séparé en workflow_dispatch protégé, reprenant `mobile-native/scripts/auth-staging/policy.mjs` et `inject-xctestrun.py`. Livraison : `mobile-delivery.yml` conservé, job iOS réécrit pour `xcodebuild archive` du projet Swift, `fastlane ios submit` inchangé, aucune soumission automatique.

## 5. Plan par lots

Ordre de priorité : parcours soignant cœur d'abord, pointage au lot 2, établissement terrain avant la bascule. Les durées sont des ordres de grandeur pour un développeur iOS assisté par agents, hors délai de revue Apple.

### Lot 0 : socle, décisions et chaîne de preuve (environ 2 semaines)

Périmètre : création de `ios-native/`, garde d'environnement, client supabase-swift avec Keychain, contrôleur de session à epoch, résolution de rôle, TabView, écran de connexion, liste de missions en démo, table de routage AASA exhaustive, workflow CI, export des vecteurs golden, document des contrats RPC soignant, mémo de décisions, gel des workflows `native-*.yml`, marquage des trois docs périmées, test captcha GoTrue sur STAGING, vérification APNs.

Critères de sortie :
- `xcodebuild test` vert sur macos-26 pour `JoleneCoreTests` et `JoleneUITests` sur iPhone, iPad portrait et iPad paysage.
- Connexion STAGING exécutée une fois via le protocole hérité de `mobile-native/AUTH_STAGING.md`, avec assertion sur l'écran Accueil et sur le rôle renvoyé par `fn_get_my_role`.
- Garde d'environnement testée : refus d'une clé secrète et d'un ref hors allowlist.
- Au moins 200 vecteurs golden importés et verts pour dates, format de mission, heures hebdomadaires et disponibilité de pointage.
- Table de routage testée unitairement sur les quinze motifs de `public/.well-known/apple-app-site-association`, dont `/admin/*` et `/groupe/*` vers Safari.
- Un `signUp` STAGING depuis un client sans `captchaToken` exécuté et son résultat consigné.
- Un envoi APNs sandbox prouve que les secrets Supabase correspondent à `GDU5AA28M9`.
- Porte go/no-go supabase-swift signée.
- Aucune modification sous `ios/`, `android/`, `capacitor.config.ts`, `supabase/`.

### Lot 1 : soignant, session, tableau de bord, exploration, candidature, mes missions, suppression de compte (environ 4 semaines)

Périmètre : connexion, déconnexion, biométrie, reset mot de passe par Universal Link, reprise après 30 minutes, tableau de bord (`fn_dashboard_soignant_complet`), Explorer liste, filtres, détail, favoris, distance (MapKit en lecture, swipe reporté au lot 4), candidature complète via `fn_confirmer_action_planning_v1`, annulation avec justificatif, Mes missions avec ajout au calendrier, suppression de compte via l'edge `supabase/functions/delete-account/index.ts` (exigence Apple 5.1.1, remontée du lot 3 au lot 1).

Critères de sortie :
- XCUITest démo verts sur trois formats, plans découpés par domaine.
- STAGING : candidature réelle posée puis relue, annulation relue, proposition acceptée relue, suppression de compte sur un compte TEST jetable vérifiée en SQL.
- `fn_ecrire_audit_safe` émis pour connexion et candidature, vérifié par requête STAGING.
- Vecteurs golden planning candidat, sélection de série et complétude verts.
- Matrice de parité soignant (`docs/mobile-swift/PARITE_SOIGNANT.md`, à créer, une ligne par route de `src/App.tsx` l.309-344 et l.384-418) renseignée à 45 % au moins.
- TestFlight interne 2.0.0 (25) installé sur un iPhone physique, Universal Link de reset testé et consigné.

### Lot 2 : pointage, documents, contrats OTP (environ 5 semaines)

Périmètre, pointage : arrivée, départ, pauses via `fn_pointer_*` avec les mêmes paramètres (`p_lat`, `p_lng`, `p_precision`, `p_terminal_id`, `p_modele`, `p_code_arrivee`) ; les deux systèmes QR : token de `fn_generer_qr_mission` validé par `fn_valider_scan_qr` avec file hors-ligne à sémantique identique à `src/lib/qr-offline-queue.ts`, et code rotatif via `fn_scanner_code_pointage` ; code de secours ; consentement GPS ; fenêtre de 15 minutes de `src/lib/disponibilite-pointage.ts` ; identifiant terminal persistant ; journal d'essai durable ; ouverture de litige depuis une présence ; notation rapide. Documents : exigences par profession, PHPicker, caméra, Fichiers, HEIC vers JPEG, upload bucket `jolene-documents` sous `auth.uid()/`, reçu avant upload, appel `verify-document` une seule fois, remplacement, revue humaine. Contrats : liste, lecture HTML sanitisée ou PDF serveur, consentement lié à la révision affichée, OTP SMS avec champ UIKit, compte à rebours 72 h, certificat, partage.

Critères de sortie :
- STAGING : scan de code rotatif accepté par `fn_scanner_code_pointage` et relu dans `scans_pointage` ; scan d'un QR généré par `fn_generer_qr_mission` accepté par `fn_valider_scan_qr` ; arrivée et départ relus via `fn_etat_pointage_mission` avec précision GPS comparée à une présence issue de la coquille.
- Upload réel plus ligne `documents_soignants` plus `verify-document` déclenchée une seule fois, vérifié en SQL et logs.
- Signature OTP réelle sur STAGING via le dispositif de recette `fn_admission_otp_signature_recette` installé par `scripts/ci/install-sms-staging-closed-sql.mjs`, puis relecture de la signature dans `signatures_contrats`.
- File hors-ligne testée avec coupure réseau simulée par port injecté ; QR expiré jamais remis en file.
- Vecteurs golden disponibilité de pointage, synthèse de présence et classement de document verts.
- Recette sur iPhone physique consignée dans `docs/mobile-swift/RECETTE_DEVICE_LOT2.md` (à créer) : QR, GPS refusé puis accordé, HEIC, arrêt forcé pendant un envoi puis réconciliation sans doublon.
- Aucun wording contractuel nouveau : les textes de consentement et de contrat sont ceux du web, revue par vous sur les écrans de signature.

### Lot 3 : push APNs, inscription et PSC, profil et compte, revenus et Connect, Universal Links complets (environ 4 semaines)

Périmètre : enregistrement du token APNs hex via `fn_upsert_token_push` à chaque session et retour au premier plan, désactivation au logout, routage des taps par la table portée de `src/lib/pushNative.ts`, préférences par canal ; inscription soignant par `signUp` PKCE puis `register-soignant` ; PSC si credentials ANS présents ; profil, avatar, adresse, changement de mot de passe, thème, export RGPD ; revenus en lecture, confirmation et contestation de paiement déclaré, IBAN, onboarding Connect hosted via `SFSafariViewController` avec retour `/soignant/stripe-connect` ; Sentry Cocoa.

Critères de sortie :
- Push réel reçu sur iPhone physique depuis `send-push` en sandbox, tap ouvrant l'écran attendu pour au moins six types d'événements ; table de routage testée unitairement sur les cas de `src/lib/pushNative.test.ts`.
- Inscription STAGING complète de bout en bout par Universal Link : email reçu, PKCE échangé, profil créé.
- Onboarding Connect STAGING ouvert et retour dans l'app par Universal Link.
- Sentry reçoit un crash de test taggé release 2.0.0 (25).
- TestFlight externe ouvert à une cohorte de soignants pilotes.

### Lot 4 : parité soignant, bêta externe et parcours secondaires (environ 3 semaines)

Périmètre : swipe natif, filtres sauvegardés, disponibilités, parrainage par Universal Link, litiges, réclamations, messagerie Realtime, bulletins en lecture, évaluations, pool urgence. Renvoi explicite vers jolene.app pour ce qui reste web (premium, prévoyance, mandat, avances, charges sociales), soit par Safari, soit par la WebView bornée si vous la retenez.

Critères de sortie :
- 100 % des lignes de la matrice de parité statuées (natif / renvoi web assumé / abandonné), zéro ligne « abandonné » sur les onze parcours cœur, matrice signée par vous.
- Crash-free sessions supérieur ou égal à 99,5 % sur 14 jours de bêta.
- STAGING : message envoyé et reçu en Realtime entre deux comptes TEST, litige ouvert et relu.
- Aucun retour bêta bloquant ouvert.

### Lot 5 : établissement terrain et renvoi web pour le reste (environ 5 semaines)

Périmètre : rôle ADMIN_ETABLISSEMENT, y compris comptes legacy (`app_metadata.role = 'ETABLISSEMENT'` et repli `etablissementId = user.id` de `src/hooks/useEtablissementScope.ts`), permissions avec les clés réelles de `src/hooks/useEtabPermissions.ts` l.7-19 et non celles de `docs/EQUIPE_ETAB.md` ; tableau de bord en liste d'actions prioritaires sans graphiques ; candidatures via `fn_traiter_candidature_planning_v1` ; présences (validation, lot, contestation, QR plein écran et code rotatif rafraîchi, écran sans veille) ; contrats et signature OTP ; messagerie ; publication « mission simple ou urgente » via `fn_creer_mission_multi_jours_v4`, dérivation de planning portée de `src/lib/planning-derive.ts` avec golden, règles juridiques uniquement serveur ; profil minimal et déconnexion. Facturation, SEPA, Chorus, RH, export paie, équipe, API, récurrence avancée : renvoi web.

Critères de sortie :
- XCUITest démo établissement sur trois formats.
- STAGING : candidature acceptée relue, présence validée relue, QR généré par `fn_generer_qr_mission` décodé depuis la capture (script `mobile-native/scripts/verify-presence-qr.mjs` repris), mission simple créée et relue.
- Compte legacy mono-établissement testé sur STAGING ; membre POINTAGE_ONLY ne voit que ce que `fn_mes_permissions_etab` autorise.
- Aucune règle juridique en dur : revue de code ciblée et test qui refuse tout littéral de la table paramétrée des modes d'exercice.
- Matrice `docs/mobile-swift/PARITE_ETABLISSEMENT.md` (à créer) statuée et signée.

### Lot 6 : bascule App Store, remplacement de 1.0.7 par 2.0.0 (environ 2 semaines, plus délai de revue Apple)

Périmètre : `config/mobile-release.json` scindé par plateforme (iOS 2.0.0 / 25 ou plus, Android 1.0.x) ; `mobile-delivery.yml` avec job iOS en `xcodebuild archive` du projet Swift et `exportArchive` via `ios/ExportOptions-AppStore.plist` ; `scripts/check-mobile-build-alignment.mjs` pointé vers le nouveau projet ; `scripts/mobile/delivery-plan.mjs` avec `ios-native` dans les chemins natifs et interdiction de tout diff `ios-native` en mode ota ; `scripts/mobile/release-state.mjs` avec tags scindés `mobile-native-ios-N` / `mobile-native-android-N` sans exiger les deux ; captures iPhone et iPad refaites depuis l'app Swift (les scripts de captures existants photographient le site web) ; App Privacy recalculée ; notes de review et notes de version annonçant la reconnexion et le ré-enrôlement Face ID ; écran d'accueil post-mise à jour ; déploiement progressif sur 7 jours ; suivi par `mobile-store-status.yml`.

Critères de sortie :
- Garde Apple 4.2 écrite et respectée : aucune soumission sans pointage, tableau de bord et missions natifs.
- Garde fastlane OK (version supérieure à 1.0.7, build supérieur à 24, `uses_non_exempt_encryption=false`).
- AASA inchangée, Universal Links vérifiés sur le build de production (reset, invitation, PSC, Stripe Connect).
- Push de production reçu sur un token enregistré par 2.0.0.
- Phased release non interrompue, crash-free supérieur ou égal à 99,5 %, taux de reconnexion suivi via `fn_audit_connexion`.
- Plan de retour arrière écrit et testé une fois : `ios/` Capacitor reste buildable et une 1.0.8 (26) peut être soumise sous 24 h.
- Aucune soumission automatique.

### Lot 7 : nettoyage (environ 1 semaine, après un cycle de production stable de 2.x)

Périmètre : suppression de `ios/` (projet Xcode Capacitor, `ios/App/CapApp-SPM/Package.swift`, `ios/debug.xcconfig`), déplacement de `ExportOptions-AppStore.plist` sous `ios-native/` ; `capacitor.config.ts`, dépendances Capacitor et wrappers `src/lib` conservés pour Android seul avec commentaire de périmètre ; docs périmées archivées avec en-tête « périmé, voir docs/mobile-swift/ » ; `docs/MOBILE_DELIVERY.md` scindé iOS Swift / Android Capacitor ; suppression de `mobile-native/` de main après tag d'archive ; suppression des workflows `native-*.yml` ; mémo Android.

Critères de sortie :
- `mobile-delivery.yml` fonctionne séparément pour iOS Swift et Android Capacitor.
- CI web inchangée verte ; aucune référence à `ios/App` dans `scripts/`.
- Décision Android consignée.

## 6. Continuité store

Bundle et Team : `app.jolene` et `GDU5AA28M9`, repris à l'identique dans le nouveau projet. Même enregistrement App Store Connect (Apple ID `6774672845`), même fiche, mêmes URL, mêmes comptes de review (`docs/STORE_METADATA_FR.md`). Le profil « Jolene App Store Distribution » doit être vérifié au lot 0 : s'il ne couvre pas Push et Associated Domains pour le nouveau projet, le régénérer pour le même App ID. Secrets GitHub réutilisés : `IOS_DISTRIBUTION_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`.

Push APNs : même topic `app.jolene`, même clé .p8 dans Supabase, même contrat de token (device token APNs hex brut vers `fn_upsert_token_push` avec plateforme `IOS`), même payload (`type_evenement`, `lien`, `mission_id`, `contrat_id`, `facture_id`, `litige_id`). Vérification au lot 0 que `APNS_TEAM_ID` et `APNS_KEY_ID` correspondent à `GDU5AA28M9` et non au Team hérité. L'ancien token de la WebView reste dans `tokens_push` jusqu'au 410 APNs ; le nouveau est enregistré à la première session 2.0.0. Aucune action backend.

Universal Links : `public/.well-known/apple-app-site-association` inchangée. Les emails, SMS et payloads push déjà émis pointent sur ces chemins. L'app Swift gère tous les chemins listés dès la bascule : natif si l'écran existe, sinon écran de renvoi vers Safari. L'entrée `FPQ78HDF4Y` reste jusqu'à décision explicite, elle est inoffensive.

Versions : 2.0.0 (25) minimum, imposé par `scripts/mobile/delivery-plan.mjs` l.78 et par la garde `replacement_version` de `fastlane/ios_review_submission.rb`. Builds TestFlight 25 à N sur le même App ID. `config/mobile-release.json` scindé par plateforme au lot 6.

Migration des sessions : la session vit dans le localStorage de la WKWebView, illisible par Swift. La reconnexion unique est inévitable. Le refresh token biométrique Capgo ne vaut rien (tourné dès la première reconnexion, `src/pages/PageConnexion.tsx` l.161 et l.194). Le ré-enrôlement Face ID est la seule voie honnête. Les deux sont annoncés dans les notes de version et par un écran post-mise à jour. Le taux de reconnexion est suivi via `fn_audit_connexion`.

Retour arrière : `ios/` Capacitor reste buildable jusqu'au lot 7. Une 1.0.8 (26) peut être re-soumise. Pas de retrait de 2.0.0 sans votre décision. Tout changement d'App Privacy, de notes de review ou de captures est une opération manuelle dans App Store Connect sous votre compte, consignée dans `docs/mobile-swift/` (à créer).

## 7. Android : décision proposée

La coquille Capacitor reste seule sur le Play Store pendant tout le chantier iOS, y compris les mises à jour OTA. Aucun jumeau Kotlin n'est ouvert en parallèle.

Raisons : une seule personne décide et recette ; deux réécritures natives simultanées doubleraient la surface de preuve (`CLAUDE.md` l.9-13 impose iPhone, Android et iPad) sans doubler la capacité ; l'app Play Store fonctionne et continue de recevoir les évolutions web par OTA signé, seul canal qui ne régresse pas pendant le chantier ; la décision Kotlin doit se prendre sur des données d'usage (part des sessions Android, rôle POINTAGE_ONLY réellement utilisé) que le dépôt ne contient pas.

Conséquences concrètes : `capacitor.config.ts`, les plugins Capacitor, les wrappers `src/lib` (`platform.ts`, `camera.ts`, `geoloc.ts`, `pushNative.ts`), l'OTA, la lane fastlane android et `.github/workflows/android-native-recette.yml` restent vivants ; interdiction d'ajouter un plugin natif Android pendant le chantier ; les gardes `isNative()` du web ne sont pas retirées ; la recette Android des parcours web continue via `e2e/playwright.recette-complete.config.ts`. Les flows `mobile-native/maestro/` sont conservés par tag git comme base d'un futur jumeau Android.

Point de revue : à la fin du lot 7, go/no-go avec trois options chiffrées (Kotlin jumeau de JoleneCore, maintien Capacitor durable, Kotlin limité au pointage terrain). Si Kotlin est lancé, il réutilise JoleneCore comme spécification : mêmes vecteurs golden, mêmes contrats RPC, mêmes identifiants d'accessibilité. Le contrat push Android reste FCM v1 via `send-push`.

## 8. Sort du pilote RN et de la coquille Capacitor

### 8.1 Pilote React Native

Gel immédiat, dès la première semaine : désactivation de `.github/workflows/native-pilot.yml`, `native-documents.yml`, `native-contracts.yml`, `native-presence.yml`, `native-auth-staging.yml`, `native-uikit-otp-reference.yml`. La campagne Auth STAGING n'est pas lancée sur le pilote RN ; elle est faite sur le premier binaire Swift au lot 0. Aucun travail produit n'y est plus accepté.

Extraction au lot 0 vers `ios-native/` et `scripts/mobile/` : types vers Codable ; fixtures vers JSON ; helpers XCUITest et `UIKitOtpReference.swift` vers les cibles de test et le package design ; convention d'identifiants d'accessibilité ; `mobile-native/AUTH_STAGING.md`, `mobile-native/scripts/auth-staging/`, `png-dimensions.mjs`, `verify-presence-qr.mjs`, `contracts-home-oracle.mjs`, `ios-failure-diagnostics.mjs` ; scénarios pas à pas de `mobile-native/ios-ui-tests/README.md`, `PRESENCE-SCENARIO-PREPARATION.md` et `MIGRATION.md` ; règles d'architecture de `mobile-native/AGENTS.md` vers `docs/mobile-swift/PRINCIPES.md` (à créer).

Jeté : `App.tsx`, `src/ui/`, `SessionProvider`, adaptateurs Expo, chunking SecureStore, `rn-text-input-patch.cjs`, `patches/`, `plugins/`, `ios-compiled-client.mjs`, `metro-http.mjs`, diagnostics de navigation, `package.json` et lockfile RN.

Retrait du dépôt : tag d'archive git sur le dernier commit contenant `mobile-native/`, puis suppression de main au lot 7. Les flows Maestro restent consultables par le tag.

### 8.2 Coquille Capacitor

iOS : la coquille 1.0.7 (24) reste l'app de l'App Store et la référence de parité jusqu'au lot 6. Aucun nouveau développement iOS ne lui est destiné, sauf correctif de sécurité ou de conformité store livré en 1.0.x via le workflow actuel. Le dossier `ios/` reste buildable comme plan de retour arrière pendant un cycle de production de 2.x, puis est supprimé au lot 7.

Android : la coquille reste publiée et maintenue (voir section 7). `capacitor.config.ts`, les dépendances, les wrappers, l'OTA et la lane Android ne sont pas supprimés. La liste de diff natif de `scripts/mobile/delivery-plan.mjs` l.90 est complétée par `ios-native` au lot 6.

Backend : les points où la coquille « fuit » côté serveur (origines `capacitor://localhost` dans `supabase/functions/_shared/cors.ts`, `register-soignant`, `send-email`, `stripe-connect-onboard`) restent tels quels. Un client sans Origin retombe sur `https://jolene.app`. Vérification fonction par fonction sur STAGING au lot 3, aucune réécriture.

## 9. Risques et parades

- Une seule fiche App Store, donc un seul binaire. Bascule avant parité réelle : régression des établissements iOS et risque de rejet Apple 2.1 / 4.2. Parade : matrice de parité signée par rôle, renvoi web explicite, établissement terrain livré avant la bascule, garde 4.2 écrite au lot 6.
- Pointage juridiquement sensible. Toute divergence de payload, de fenêtre de 15 minutes, d'expiration des scans ou de renvoi automatique produit de faux pointages. Parade : vecteurs golden partagés TS / Swift, journal d'essai durable, recette appareil physique obligatoire, comparaison ligne à ligne avec une présence de la coquille, règles de périmètre laissées au serveur.
- Dérive silencieuse des contrats RPC (339 RPC appelées sans type, 32 hors manifeste). Parade : document de contrats extrait de `supabase/schema/public.sql`, test CI de dérive sur `types.ts`, tests de décodage sur réponses STAGING enregistrées.
- Clé APNs liée au Team hérité. Parade : envoi sandbox au lot 0, avant d'attribuer tout échec push à l'app Swift.
- Rupture de session et ré-enrôlement Face ID à la mise à jour. Parade : notes de version, écran post-mise à jour, suivi du taux de reconnexion via `fn_audit_connexion`, déploiement progressif.
- Cible iOS 16 : exclusion des iPhone restés en iOS 15. Parade : décision sur les données Sentry et App Store Connect au lot 0 ; sinon iOS 15 avec `NavigationView`.
- Captcha GoTrue activé un jour dans le dashboard : l'inscription native casse. Parade : test d'inscription STAGING en CI ; décision backend (App Attest ou DeviceCheck) instruite mais hors périmètre du client.
- Stripe et PSC supposent un navigateur. Parade : Connect et Checkout hosted via `SFSafariViewController` avec retour par Universal Link ; toute évolution des edge Stripe relève du tiering B9 avec go humain ; PSC masqué par drapeau si credentials absents.
- Perte de l'OTA iOS : chaque correctif passe par la revue Apple. Parade : releases plus fréquentes, phased release, drapeau distant via `fn_param_bool` (`src/hooks/useParamBool.ts`) pour désactiver un écran cassé, sous réserve de votre décision.
- Duplication de règles métier (environ 25 modules de `src/lib`). Parade : vecteurs golden exportés automatiquement et exécutés des deux côtés ; liste des candidats à déplacer en RPC (complétude planning, classes de justificatifs, validation profil).
- Coût CI macOS et flakiness XCUITest. Parade : plans découpés par domaine sous 15 minutes, `build-for-testing` partagé, timeout 60 minutes, aucune compilation de framework tiers.
- Deux chantiers mobiles ouverts par inertie. Parade : gel des workflows `native-*.yml` en semaine 1 et règle écrite : aucun travail iOS hors `ios-native/` sauf sécurité et conformité.
- Manifest de confidentialité à recalculer pour supabase-swift et Sentry Cocoa. Parade : révision de `PrivacyInfo.xcprivacy` et d'App Privacy au lot 3, avant toute soumission.
- Comptes établissement legacy exclus par un client qui ne gère que `app_metadata.etablissement_id`. Parade : repli de `useEtablissementScope.ts` porté, test STAGING dédié au lot 5.
- WebView bornée, si retenue : ne jamais injecter de refresh token côté web, data store non persistant par epoch, projet Playwright « embarqué » et tests vitest sur toute branche de plateforme ajoutée au front.

## 10. Décisions (tranchées le 1er novembre 2026, voir `docs/mobile-swift/DECISIONS_LOT0.md`)

1. Android : la coquille Capacitor reste seule sur le Play Store, OTA compris, pendant tout le chantier iOS, sans jumeau Kotlin avant un cycle stable de 2.x ? Recommandation : oui.
2. Remplacement en place : l'app Swift reprend `app.jolene`, Team `GDU5AA28M9`, App Store ID `6774672845`, en 2.0.0 (build 25 ou plus), et ne remplace 1.0.7 qu'après parité soignant et établissement terrain signées, les autres rôles étant renvoyés vers jolene.app ? Recommandation : oui.
3. Longue traîne soignant (mandat, avances, bulletins, charges sociales) : acceptez-vous une WKWebView authentifiée bornée dans l'app Swift (access token seul, jamais de refresh token côté web, data store non persistant), retirée lot par lot, ou tout renvoi passe par Safari avec reconnexion ? Recommandation : WebView bornée.
4. Cible iOS 16 minimum, contre 15.0 aujourd'hui (`project.pbxproj` l.239) ? Recommandation : oui, après lecture des versions iOS dans Sentry et App Store Connect ; sinon iOS 15 avec `NavigationView`.
5. Gel immédiat du pilote React Native : désactivation des six workflows `native-*.yml`, tag d'archive, extraction puis suppression de `mobile-native/` de main au lot 7 ? Recommandation : oui.
6. Avant tout code d'inscription native : exécuter un `signUp` STAGING puis production depuis un client sans `captchaToken` pour fixer l'état de la protection captcha GoTrue ? Recommandation : oui, c'est un test, pas un chantier backend.
7. Vérifier dans les secrets Supabase que `APNS_TEAM_ID` et `APNS_KEY_ID` correspondent à `GDU5AA28M9` par un envoi sandbox avant le lot 0 ? Recommandation : oui.
8. iPad : conserver le binaire universel avec rendu adaptatif, sans design iPad dédié, pour ne changer ni la fiche ni la règle de recette de `CLAUDE.md` ? Recommandation : oui.
9. Drapeau distant `fn_param_bool` pour désactiver un écran natif cassé et afficher un renvoi web, en remplacement de l'OTA perdu ? Recommandation : oui, car cela touche le comportement livré et demande votre accord.

## 11. Deux premières semaines : actions concrètes

Rien de ce qui suit ne touche le backend, les stores, `ios/`, `android/` ni `capacitor.config.ts`. Aucune livraison.

Semaine 1, socle.

Jours 1 et 2 : mémo de décisions `docs/mobile-swift/DECISIONS_LOT0.md` (à créer) reprenant les neuf questions de la section 10. Désactivation des six workflows `native-*.yml` et tag d'archive du pilote. Bandeau « périmé » en tête de `docs/store-readiness.md`, `docs/PUSH_NATIVE_FINAL.md` et `docs/CAPACITOR_PRODUCTION.md`. Envoi APNs sandbox pour vérifier le Team de la clé .p8 dans Supabase. Lecture des notes de review et comptes démo réels dans App Store Connect.

Jours 1 à 2 : création de `ios-native/Jolene.xcodeproj` (cible SwiftUI, bundle `app.jolene`, Team `GDU5AA28M9`, famille 1,2, version 2.0.0, build 25). Copie de `Info.plist`, `App.entitlements`, `PrivacyInfo.xcprivacy`, icône et splash depuis `ios/App/App/`. Fichiers xcconfig Base, Staging, Production. Schemes `Jolene` et `Jolene-Staging`.

Jours 2 et 3 : packages SPM locaux `JoleneCore`, `JoleneSupabase` (dépendance supabase-swift), `JoleneDesign` (champ OTP repris de `UIKitOtpReference.swift`). Spike de deux heures sur STAGING : supabase-swift accepte-t-il la clé `sb_publishable_` et le PKCE avec stockage Keychain personnalisé. Résultat consigné pour la porte go/no-go.

Jours 3 et 4 : modèles Mission, Créneau, Candidature, Soignant, Rôle ; contrôleur de session à epoch ; ports ; règles dates, format de mission, heures hebdomadaires, disponibilité de pointage. Script `scripts/mobile/export-golden-vectors.mjs` (à créer) lisant les tests vitest ciblés et écrivant les JSON. Premier jeu de 200 vecteurs au moins.

Jours 4 et 5 : écran de connexion (identifiants `login-email`, `login-password`, `login-submit`, `login-scroll`), TabView (`tab-accueil`, `tab-explorer`, `tab-missions`, `tab-revenus`, `tab-profil`), liste et détail de missions sur la gateway Demo (fixtures exportées de `mobile-native/src/data/demoGateway.ts`), écran de renvoi pour les rôles non soignants, mode démo avec test prouvant qu'aucune requête réseau ne part. Workflow `.github/workflows/ios-swift-ci.yml` (à créer), trois destinations, xcresult en artefact.

Semaine 2, première preuve STAGING et contrats.

Jours 6 et 7 : scheme `Jolene-Staging` : connexion réelle, restauration de session après arrêt, `fn_get_my_role`, liste de missions STAGING paginée, détail avec créneaux, déconnexion. Plan de test Staging et scripts repris de `mobile-native/scripts/auth-staging/`. Workflow STAGING en workflow_dispatch sur environnement protégé. Exécution une fois avec assertions : écran Accueil visible, rôle SOIGNANT, au moins une mission listée, aucune valeur saisie dans les logs. Test du `signUp` sans `captchaToken` sur STAGING.

Jour 8 : `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md` (à créer) : signatures SQL exactes extraites de `supabase/schema/public.sql` et des migrations pour `fn_get_my_role`, `fn_mon_profil_soignant_complet`, `fn_dashboard_soignant_complet`, `fn_confirmer_action_planning_v1`, `fn_etablissements_safe`, `fn_suggestions_missions_pour_soignant`, `fn_pointer_arrivee`, `fn_pointer_depart`, `fn_scanner_code_pointage`, `fn_valider_scan_qr`, `fn_generer_qr_mission`, `fn_etat_pointage_mission`, `fn_upsert_token_push`, `fn_envoyer_otp_signature`, `fn_signer_contrat_otp`, `fn_remplacer_document_soignant`, avec classe d'authentification du manifeste et exemple de réponse STAGING enregistré. Premier jet du test CI de dérive des signatures.

Jour 9 : Universal Links minimum : `onOpenURL` et `NSUserActivity`, normalisation portée de `src/lib/nativeLinks.ts`, tests unitaires sur les cas de `src/lib/nativeLinks.test.ts`, table de routage des quinze motifs AASA testée, écran de renvoi Safari pour les chemins non natifs. Squelette du coordinateur push sous drapeau, sans prompt système. `docs/mobile-swift/PRINCIPES.md` (à créer).

Jour 10 : revue. PR « ios-native : socle lot 0 » avec CI verte. Matrice `docs/mobile-swift/PARITE_SOIGNANT.md` (à créer) initialisée, une ligne par route de `src/App.tsx` l.309-344 et l.384-418, statut « à faire ». Note go/no-go supabase-swift d'une page avec les mesures. Validation avec vous du périmètre du lot 1 avant d'engager quatre semaines.

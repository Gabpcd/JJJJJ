# Sentry Cocoa dans l'app iOS Swift (`ios-native/`) — lot 3, T15

Rapport de crash de l'app Swift : crashs et blocages de l'interface (*app hangs*), **sans donnée personnelle**
(décision D21 de `docs/mobile-swift/DECISIONS_LOT3.md`, blueprint `docs/mobile-swift/LOT3_PLAN.md` §3 T15). Le web garde
son propre projet `jolene-app` (`docs/sentry-setup.md`) ; l'app iOS aura un projet séparé, `jolene-ios`, dans
l'organisation `jolene-z6`, que Gabrielle doit créer.

Critère du plan (lu en T17) : « Sentry reçoit un crash de test taggé release 2.0.0 (25) ». Cette tranche livre le code,
les tests et le câblage de livraison. Elle ne prouve aucune réception réelle : aucun DSN n'existe encore, et **aucun
appel réseau vers Sentry** n'a été fait.

## 1. Version retenue : `sentry-cocoa` 9.32.0 (`exactVersion`)

| Critère | Constat |
|---|---|
| Publiée depuis au moins deux semaines | 9.32.0, publiée le 29/10/2026, soit 18 jours avant l'ouverture de la tranche (16/11/2026). Les versions suivantes sont trop récentes : 9.33.0 (04/11) et 9.34.0 (12/11). Révision épinglée dans `Package.resolved` : `4e1e4ba9ce329f91ad6bfb63bab6da576a3f348c`, qui est bien le tag `9.32.0`. |
| Xcode 16.4 en local | Xcode 16.4 (Swift 6.1.2) lit `Package@swift-6.1.swift` (*tools* 6.1). Le binaire `Sentry.xcframework` est compilé avec **Swift 6.1.2** : en-tête `swift-compiler-version` du `.swiftinterface`. Résolution SPM, `build-for-testing` et XCUITest démo ont été vérifiés en local (`REVUES_LOT3.md`, section L3-T15). |
| Xcode 26.4.1 en CI | Xcode 26.4.1 lit `Package@swift-6.2.swift`, qui expose le même produit `Sentry` sur le même binaire. Un compilateur plus récent lit les interfaces produites par Swift 6.1.2. Le build CI n'a pas été lancé localement : la CI de la PR le prouvera. |
| Cible iOS | Le paquet exige iOS 15 au minimum ; l'app est en iOS 16. |
| Correctifs utiles | 9.31.0 : état de l'application résolu correctement quand le SDK démarre depuis `App.init` en SwiftUI. Avant ce correctif, le suivi des app hangs pouvait signaler un blocage fatal avec un fil principal inactif (#8988), or c'est précisément notre point de démarrage. 9.32.0 : plus d'interblocage dans le traitement des `NSException` (#9463). |

**Produit choisi : `Sentry`.** C'est le `Sentry.xcframework` **statique** plus `SentryCppHelper`, importé par la seule
cible app. `Sentry-Dynamic` n'est pas utilisé : il ajouterait un framework dynamique au lancement, sans gain pour nous.

**Coût CI à connaître.** À la résolution, SPM télécharge les **sept** xcframeworks binaires que déclare le paquet,
utilisés ou non, soit environ 3,3 Go au total, dont 372 Mo pour le produit retenu. Le cache `spm-xcodebuild-…`
d'`ios-swift-ci.yml` (clé : `Package.resolved`) les absorbe après le premier run de chaque clé. En revanche, ce
premier run et chaque montée de version téléchargent ces 3,3 Go.

**Mise à jour.** Toute nouvelle version doit avoir au moins deux semaines. Il faut vérifier que l'interface est
compilée par un Swift lisible en local, et relire le CHANGELOG (options renommées ou dépréciées, comportement de
`beforeSend`). Ensuite : `xcodegen generate`, puis `xcodebuild -resolvePackageDependencies`, puis les tests de ce
document.

## 2. Architecture

| Élément | Rôle |
|---|---|
| `JoleneCore/Crash/ConfigurationCrash.swift` | Décision de démarrage (`auLancement`), release, validation du DSN, réglages (`ReglagesCrash`), crash de test. Aucun import de Sentry. Le DSN n'est jamais restitué par une description ni par un `dump`. |
| `JoleneCore/Crash/CrashScrubber.swift` | Nettoyage pur des textes et des dictionnaires (§4). |
| `JoleneCore/Ports/Lot3Ports.swift` | Port `CrashReportingPort` (T1) : `demarrer(environnement:release:)`, `utilisateur(id:)`. |
| `Jolene/Composition/CrashReporting.swift` | **Seul fichier qui importe Sentry.** Il démarre au lancement, applique les réglages un par un et branche `beforeSend` et `beforeBreadcrumb` sur `CrashScrubber`. |
| `Jolene/JoleneApp.swift` | `init()` démarre Sentry **avant** le conteneur, puis remet le port à `AppContainer(crashReporting:)`. |
| `Jolene/Composition/AppContainer.swift` | `environnementDeLancement` est partagé avec `CrashReporting` : même lecture de l'environnement, surcharges DEBUG comprises. Le port n'est remis à la session qu'en staging et en production, **jamais en démo**. |
| `JoleneCore/Session/SessionStore.swift` | Pose l'identifiant utilisateur seul au `.ready` d'une nouvelle identité. Le retire (`nil`) à chaque fin d'identité : déconnexion, fin de compte, session effacée par le SDK. Le conserve sur une fin transitoire. Ne le pose pas pour un espace bloqué. |

## 3. Quand Sentry démarre, et avec quels réglages

Sentry démarre seulement si **toutes** ces conditions sont réunies ; sinon aucun adaptateur n'est construit :

- mode `staging` ou `production` accepté par la garde d'environnement. Jamais en démo ; jamais pour un mode inconnu
  ni pour un environnement refusé (clé absente ou secrète, projet hors liste), qui n'ouvrent que l'écran bloquant ;
- DSN `https://<clé publique>@<hôte>/<projet>` présent dans l'Info.plist (`JoleneSentryDSN`, alimenté par
  `$(JOLENE_SENTRY_DSN)`). Une valeur vide, faite de blancs, non résolue ou mal formée laisse Sentry **désactivé** ;
- release lisible dans le bundle : `<CFBundleIdentifier>@<CFBundleShortVersionString>+<CFBundleVersion>`, soit
  `app.jolene@2.0.0+25`. Elle n'est jamais codée en dur.

Environnement Sentry : le mode de l'app (`staging` ou `production`).

| Option Sentry | Valeur | Raison |
|---|---|---|
| `sendDefaultPii` | `false` | Aucune donnée personnelle ajoutée par le SDK (adresse IP, etc.). |
| `attachScreenshot`, `attachViewHierarchy` | `false` | Ni capture d'écran ni hiérarchie de vues (données de santé, identité, IBAN à l'écran). |
| `enableNetworkBreadcrumbs`, `enableCaptureFailedRequests` | `false` | Ni URL de rappel, ni requête, ni réponse. |
| `tracesSampleRate` | `0` | Pas de traces de performance. |
| `enableAutoSessionTracking` | `true` | Valeur par défaut de Sentry, posée explicitement : le lot 4 mesure le taux de sessions sans crash (≥ 99,5 %). |
| `enableAppHangTracking` | `true` | Détection des blocages de l'interface. |
| `beforeSend`, `beforeBreadcrumb` | `CrashScrubber` | §4. |
| `enableNetworkTracking` | `false` | **Au-delà du blueprint.** Aucune instrumentation des requêtes réseau. |
| `tracePropagationTargets` | `[]` | **Au-delà du blueprint.** Aucun en-tête `sentry-trace` ni `baggage` vers Supabase, `api-adresse.data.gouv.fr` ou Stripe (l'en-tête `baggage` porterait la clé publique, la release et l'environnement). |
| `sessionReplay.sessionSampleRate`, `.onErrorSampleRate` | `0` | **Au-delà du blueprint.** Valeurs par défaut, posées explicitement : aucune relecture de session. |

Les réglages vivent dans `ConfigurationCrash.reglages`, que testent `CrashReportingTests`. Une garde statique du même
test vérifie que `CrashReporting.swift` applique chacun d'eux. Sentry ne reçoit ni données de profilage, ni MetricKit,
ni journaux, ni retours utilisateur (valeurs par défaut du SDK, que nous ne modifions pas).

## 4. Nettoyage (`CrashScrubber`)

Ce traitement s'applique à chaque événement et à chaque fil d'Ariane, crashs de la session précédente compris (ils
passent par `beforeSend` à la relance).

- **Masqués**, avec le texte `[masqué]`, partout dans un texte :
  - les paramètres `token_hash`, `code`, `access_token` et `refresh_token`, qu'ils soient en requête, en fragment,
    encodés (`%3F…%3D`) ou en JSON ;
  - les jetons `Bearer` et les JWT ;
  - les adresses e-mail, y compris encodées (`%40`) ;
  - les IBAN : compacts ou par groupes de quatre, toutes casses, sans contrôle mod 97 (un IBAN mal saisi reste une
    donnée bancaire).
- **Dictionnaires** (`extra`, contextes, données des fils d'Ariane) : parcourus en profondeur. La valeur texte d'une clé
  sensible (`token_hash`, `code`, `access_token`, `refresh_token`, `email`, `iban`, `password`, `mot_de_passe`) est
  masquée ; les nombres sont conservés, car un `code` numérique est un code d'erreur.
- **Retirés** : le nom de l'appareil (contexte `device`, qui porte souvent le prénom), la requête de l'événement et le
  nom du serveur. L'utilisateur est réduit à son seul identifiant.
- **Rejetés** : les fils d'Ariane réseau (`http`), par défense en profondeur puisque ces fils sont déjà coupés.
- `error_code`, `status_code`, `barcode` et les UUID de mission restent lisibles. Masquer trop est accepté (un
  hexadécimal pris pour un IBAN) ; laisser passer une donnée ne l'est pas.

À régler côté serveur par Gabrielle (§7) : « Prevent Storing of IP Addresses » et le *Data Scrubber* du projet, en
seconde barrière.

## 5. DSN : jamais dans le dépôt

- `Config/Base.xcconfig` définit `JOLENE_SENTRY_DSN =` **vide**. Staging et Production l'héritent vide.
  `Jolene/Info.plist` lit `JoleneSentryDSN = $(JOLENE_SENTRY_DSN)`. Deux gardes le vérifient :
  `CrashReportingTests.testDSNJamaisVersionne` et `tests/node/ios-native-testflight.node.mjs`.
- **TestFlight** (`.github/workflows/ios-native-testflight.yml`) : seule l'étape « Archive Release signée » lit le
  secret de dépôt **facultatif** `SENTRY_DSN_IOS` et le passe à `xcodebuild` en `JOLENE_SENTRY_DSN="${SENTRY_DSN_IOS:-}"`.
  Si le secret manque, la valeur est vide : le build part **sans Sentry, sans échec**. Le secret n'est jamais affiché,
  et GitHub masque sa valeur dans les journaux de la console.
- **En local** (recette du crash de test) :
  - en ligne de commande, passer le réglage à `xcodebuild … JOLENE_SENTRY_DSN='https://…'` ;
  - depuis Xcode, ajouter temporairement dans `Config/Staging.xcconfig` la ligne
    `JOLENE_SENTRY_DSN = https:/$()/<clé>@<hôte>/<projet>`. Dans un xcconfig, `//` ouvre un commentaire, d'où `$()`.
    Cette ligne **ne doit jamais être commitée** : les deux gardes ci-dessus rougissent si elle l'est.
- **Exposition.** Un DSN est une clé d'**envoi** seulement : elle ne donne aucun accès en lecture, et toute app livrée
  la porte dans son Info.plist. Elle reste hors du dépôt par principe. Les artefacts du workflow TestFlight (IPA et
  `archive.log`, privés au dépôt, conservés 14 jours) la contiennent forcément.

## 6. Crash de test (DEBUG, recette T17)

Prérequis :

- un build Debug « Jolene-Staging » avec la clé publishable STAGING (`Staging.xcconfig`, non versionnée) et un DSN
  (§5) ;
- l'app installée sur un simulateur ou sur l'iPhone.

1. Lancer l'app **sans débogueur**, sinon le débogueur intercepte le crash, avec l'argument `-JOLENE_SENTRY_CRASH_TEST` :
   - simulateur : `xcrun simctl launch <udid> app.jolene -JOLENE_SENTRY_CRASH_TEST` ;
   - iPhone : `xcrun devicectl device process launch --device <id> app.jolene -JOLENE_SENTRY_CRASH_TEST`.

   L'app plante une fois, deux secondes après son démarrage.
2. Relancer l'app normalement, depuis l'écran d'accueil et sans l'argument : l'événement part à ce lancement.
3. Lire l'événement dans `jolene-ios`. Attendu :
   - release `app.jolene@2.0.0+25` ;
   - environnement `staging` ;
   - utilisateur réduit à son identifiant, si une session était prête ;
   - ni e-mail, ni jeton, ni `token_hash`, ni IBAN, ni capture d'écran, ni fil d'Ariane réseau.

   Consigner le résultat dans `RECETTE_DEVICE_LOT3.md` §5.

L'argument est **ignoré** en démo, sans DSN, pour un environnement refusé et dans un build Release, où il n'est pas
compilé (garde : `SentrySDK.crash()` n'existe que sous `#if DEBUG`).

## 7. Ce qui reste manuel (Gabrielle)

1. Créer le projet Sentry `jolene-ios` (plateforme Apple iOS) dans l'organisation `jolene-z6` et copier son DSN.
   Régler le projet : activer « Prevent Storing of IP Addresses », garder le *Data Scrubber* actif et configurer les
   alertes.
2. Créer le secret de dépôt GitHub `SENTRY_DSN_IOS` avec ce DSN : Settings → Secrets and variables → Actions → *New
   repository secret*. Sans lui, les builds TestFlight partent sans Sentry.
3. Recette du crash de test (§6), puis lecture de l'événement (T17).
4. Symbolication, hors de cette tranche : sans envoi des dSYM, les piles des builds TestFlight restent non
   symbolisées. Plus tard (lot 6) : envoi par `sentry-cli` avec un jeton `SENTRY_AUTH_TOKEN` propre au projet iOS, ou
   envoi manuel des dSYM de l'archive.
5. App Privacy d'App Store Connect (lot 6). Le manifeste de l'app déclare déjà `CrashData`, `PerformanceData`,
   `OtherDiagnosticData` et `UserID`, liés à l'utilisateur.

## 8. Manifeste de confidentialité

Le manifeste du SDK est embarqué : `Jolene.app/Frameworks/Sentry.framework/PrivacyInfo.xcprivacy`, constaté sur le
`build-for-testing` Debug simulateur de la tranche. Xcode l'agrège au rapport de confidentialité de l'archive.

Ce manifeste déclare :

- les API à motif obligatoire `UserDefaults` (CA92.1), `SystemBootTime` (35F9.1) et `FileTimestamp` (C617.1) ;
- les données `CrashData`, `PerformanceData` et `OtherDiagnosticData`.

Le manifeste de l'app (`Jolene/PrivacyInfo.xcprivacy`, lot 0) déclare déjà ces trois API avec les mêmes motifs, et ces
trois types de données comme liés à l'utilisateur, ce qui est exact puisque l'identifiant est posé. **Il n'a donc pas
été modifié.**

## 9. Tests

- `JoleneCore` (`swift test`) :
  - `CrashScrubberTests` : nettoyage ;
  - `CrashReportingTests` : démarrage, refus, release, réglages, identifiant de session, et gardes statiques de la
    cible app (import isolé, démarrage avant le conteneur, démo sans port, crash de test sous DEBUG, DSN non versionné).
- Sentinelle réseau de la démo, inchangée : les XCUITest démo lisent toujours « 0 requête » (`network-sentinel`),
  puisque Sentry ne démarre jamais en démo.
- Node : `tests/node/ios-native-testflight.node.mjs`. Le secret est facultatif, lu par l'archive seule, jamais exigé
  ni affiché ; le DSN n'est pas versionné.

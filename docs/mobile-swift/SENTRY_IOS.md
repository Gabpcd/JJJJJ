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
| Xcode 26.4.1 en CI | Xcode 26.4.1 lit `Package@swift-6.2.swift`, qui expose le même produit `Sentry` sur le même binaire. Un compilateur plus récent lit les interfaces produites par Swift 6.1.2. Le build CI n'a pas été lancé localement : la CI de la PR le prouvera. Sa résolution épingle en plus KSCrash (ci-dessous). |
| Cible iOS | Le paquet exige iOS 15 au minimum ; l'app est en iOS 16. |
| Correctifs utiles | 9.31.0 : état de l'application résolu correctement quand le SDK démarre depuis `App.init` en SwiftUI. Avant ce correctif, le suivi des app hangs pouvait signaler un blocage fatal avec un fil principal inactif (#8988), or c'est précisément notre point de démarrage. 9.32.0 : plus d'interblocage dans le traitement des `NSException` (#9463). |

**Produit choisi : `Sentry`.** C'est le `Sentry.xcframework` **statique** plus `SentryCppHelper`, importé par la seule
cible app. `Sentry-Dynamic` n'est pas utilisé : il ajouterait un framework dynamique au lancement, sans gain pour nous.

**KSCrash : déclaré par Sentry, épinglé par SwiftPM 6.2, jamais lié à l'app** (revue B8 de la vague 5, M1). Constat
dans les manifestes de la révision `4e1e4ba9` (tag `9.32.0`) :

- `Package@swift-6.2.swift` et `Package@swift-6.1.swift` déclarent tous deux, sans condition,
  `.package(url: "https://github.com/getsentry/KSCrash.git", revision: "18a633dec20c265f03386294f9d82d208bb13094")`.
  `Package.swift` (outils 6.0) ne le déclare que sous la variable d'environnement `SDK_V10=1`.
- Dans le manifeste 6.2, les produits `Recording` et `RecordingCore` de KSCrash sont des dépendances de `SentrySwift`,
  `_SentryPrivate` et `SentryObjCInternal`, sous la condition `.when(traits: ["V10"])`. Le trait `V10` est réservé au
  développement de Sentry. Le paquet ne déclare aucun trait par défaut, et `project.yml` n'en active aucun.
- Dans le manifeste 6.1, aucune cible n'en dépend hors `SDK_V10=1` (`kscrashSwiftDependencies` vide).
- **Constat CI (run 43959073553, Xcode 26.4.1 build 17E202, artefact `package-resolved-*-6a145748…`) : SwiftPM 6.2
  élague les dépendances gardées par un trait désactivé, il ne les épingle pas.** L'hypothèse inverse du premier
  correctif (ajouter un pin `kscrash`) était fausse : Xcode 26.4.1 retire `kscrash`, mais aussi
  `opentelemetry-swift-core` et `swift-atomics`, que Xcode 16.4 (SwiftPM 6.1, en local) épinglait, et recalcule
  `originHash` (`97a49726…`). Le `Package.resolved` versionné est **copié tel quel de l'artefact de la CI** : 8 pins, ni
  `kscrash`, ni `opentelemetry-swift-core`, ni `swift-atomics`. C'est celui que lit l'archive TestFlight avec
  `-onlyUsePackageVersionsFromResolvedFile`. Ne jamais committer le fichier réécrit par Xcode 16.4 en local (il remet
  ces trois pins) : en cas de doute, l'étape « Package.resolved de l'app inchangé » publie le bon fichier en artefact.
- **Jamais lié à l'app.** Le produit `Sentry` que la cible app importe est le binaire `Sentry.xcframework` plus
  `SentryCppHelper`, qui n'a aucune dépendance. Les cibles qui dépendent de KSCrash relèvent du produit compilé depuis
  les sources, `SentrySPM`, que l'app n'importe pas. Activer le trait `V10` ne lierait donc pas KSCrash à notre produit.
  Une seule chose le lierait : la variable `SDK_V10=1` à l'évaluation du manifeste, qui remplace le produit binaire
  `Sentry` par une compilation depuis les sources liée à KSCrash sans condition. Aucun workflow ni xcconfig ne la pose.
  Sous Xcode 26.4.1, SwiftPM n'épingle même pas KSCrash (élagué, voir ci-dessus) ; sous Xcode 16.4, il le clone sans
  compiler ni lier aucune de ses cibles.

**Le `Package.resolved` de référence est donc celui qu'écrit Xcode 26.4.1.** C'est la version que vérifie
`ios-swift-ci.yml` et que lit l'archive TestFlight (`-onlyUsePackageVersionsFromResolvedFile`, même toolchain : garde
`ios-native-testflight.node.mjs`). Sans le pin `kscrash`, cette option ferait échouer la résolution de l'archive. La
vérification locale (Xcode 16.4) ne vaut que pour les paquets qu'elle résout : elle ne prouve rien sur ce pin. Personne
n'a vérifié si une résolution sous Xcode 16.4 retire le pin ou modifie `originHash` : ne jamais committer un
`Package.resolved` réécrit par Xcode 16.4. `originHash` n'a pas été modifié en ajoutant le pin : il dépend des
dépendances racines, inchangées. Si la CI le réécrit quand même, l'étape le dit (diagnostic ci-dessous).

**Coût CI à connaître.** À la résolution, SPM télécharge les **sept** xcframeworks binaires que déclare le paquet,
utilisés ou non, soit environ 3,3 Go au total, dont 372 Mo pour le produit retenu. Le cache `spm-xcodebuild-…`
d'`ios-swift-ci.yml` (clé : `Package.resolved`) les absorbe après le premier run de chaque clé. En revanche, ce
premier run et chaque montée de version téléchargent ces 3,3 Go.

**Mise à jour.** Toute nouvelle version doit avoir au moins deux semaines. Il faut vérifier que l'interface est
compilée par un Swift lisible en local, et relire le CHANGELOG (options renommées ou dépréciées, comportement de
`beforeSend`). Il faut aussi relire les en-têtes publics `SentryEvent.h`, `SentryMessage.h`, `SentryException.h`,
`SentryMechanism.h` et `SentryBreadcrumb.h`, puis classer chaque propriété nouvelle dans le recensement de
`CrashReportingTests` (§4) ; la garde `testRecensementDeLaVersionEpinglee` rougit tant que ce n'est pas fait. Ensuite :
`xcodegen generate`, puis `xcodebuild -resolvePackageDependencies` **sous Xcode 26.4.1**, puis les tests de ce document.
Le `Package.resolved` de l'app est commité tel que cette résolution l'écrit. L'étape « Package.resolved de l'app inchangé
après la résolution SPM » d'`ios-swift-ci.yml` (`git diff --exit-code`, revue B8 n°1, m4) échoue si la CI le réécrit.
Elle se diagnostique seule (revue B8 de la vague 5, M1) : elle imprime le diff, puis l'étape suivante publie aussitôt,
sur échec seulement, l'artefact `package-resolved-<format>-<sha>`. Cet artefact contient le `Package.resolved` résolu
par la CI, le diff et la version d'Xcode. **Correctif : committer tel quel le `Package.resolved` de cet artefact**,
puis relancer la CI. Faute de Mac sous Xcode 26.4.1, c'est aussi la façon d'obtenir le fichier de référence après une
montée de version. Les éclats tournent quand même (socle compris), si bien que la dérive ne masque aucun résultat de
test.

## 2. Architecture

| Élément | Rôle |
|---|---|
| `JoleneCore/Crash/ConfigurationCrash.swift` | Décision de démarrage (`auLancement`), release, validation du DSN, réglages (`ReglagesCrash`), crash de test. Aucun import de Sentry. Le DSN n'est jamais restitué par une description ni par un `dump`. |
| `JoleneCore/Crash/CrashScrubber.swift` | Nettoyage pur des textes et des dictionnaires (§4). |
| `JoleneCore/Ports/Lot3Ports.swift` | Port `CrashReportingPort` (T1) : `demarrer(environnement:release:)`, `utilisateur(id:)`. |
| `Jolene/Composition/CrashReporting.swift` | **Seul fichier qui importe Sentry.** Il démarre au lancement, applique les réglages un par un et branche `beforeSend` et `beforeBreadcrumb` sur `CrashScrubber`. |
| `Jolene/JoleneApp.swift` | `init()` démarre Sentry **avant** le conteneur, puis remet le port à `AppContainer(crashReporting:)`. |
| `Jolene/Composition/AppContainer.swift` | `environnementDeLancement` est partagé avec `CrashReporting` : même lecture de l'environnement, surcharges DEBUG comprises. Le port n'est remis à la session qu'en staging et en production, **jamais en démo**. |
| `JoleneCore/Session/SessionStore.swift` | Pose l'identifiant utilisateur seul au `.ready` d'une nouvelle identité ; une revalidation, même hors ligne, garde l'espace prêt et ne le repose pas. L'identifiant n'existe que pendant un espace prêt (revue B8 n°1, M2) : il est retiré (`nil`) par toute publication de `.blocked` ou de `.signedOut` (déconnexion, fin de compte, session effacée par le SDK, connexion refusée, fin transitoire), et avant toute ouverture d'identité (`signIn`, `ouvrirIdentiteInscription`). Depuis un espace prêt, une fin transitoire n'arrive qu'avec une autre identité : l'identifiant d'un compte ne suit jamais le compte suivant, même vers un espace bloqué (lien de confirmation d'un autre compte, `.session` d'une autre identité). |

## 3. Quand Sentry démarre, et avec quels réglages

Sentry démarre seulement si **toutes** ces conditions sont réunies ; sinon aucun adaptateur n'est construit :

- mode `staging` ou `production` accepté par la garde d'environnement. Jamais en démo ; jamais pour un mode inconnu
  ni pour un environnement refusé (clé absente ou secrète, projet hors liste), qui n'ouvrent que l'écran bloquant ;
- DSN `https://<clé publique>@<hôte>/<projet>` présent dans l'Info.plist (`JoleneSentryDSN`, alimenté par
  `$(JOLENE_SENTRY_DSN)`). Une valeur vide, faite de blancs, non résolue ou mal formée laisse Sentry **désactivé**, comme un
  DSN qui porte un mot de passe (`<clé>:<secret>@`, ancien format à clé secrète : revue B8 n°1, m6). L'hôte n'est pas
  encore restreint (§5, région de données) ;
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

**Propriétés traitées** (`CrashReporting.swift`). Chaque propriété publique des objets reçus par les rappels (Sentry
9.32.0) est soit traitée, soit conservée pour une raison écrite. Le recensement vit dans `CrashReportingTests` ; une garde
statique vérifie la ligne de code de chaque propriété traitée et refuse toute réécriture non recensée (revue B8 n°1, M1 et
m3).

| Objet | Traitées | Conservées telles quelles |
|---|---|---|
| `Event` | `message`, `exceptions`, `breadcrumbs`, `tags`, `extra`, `context`, `transaction`, `fingerprint`, `logger` nettoyés ; `request`, `serverName` retirés ; `user` réduit à l'identifiant | `eventId`, `error` (jamais sérialisé), dates, `level`, `platform`, `releaseName`, `dist`, `environment`, `type`, `sdk`, `modules`, `threads`, `stacktrace`, `debugMeta` |
| `SentryMessage` | `formatted`, `message`, `params` | — |
| `Exception` | `value`, `type`, `mechanism` | `module`, `threadId`, `stacktrace` |
| `Mechanism` | `desc` (texte) ; `data` (dictionnaire), où Sentry 9.32.0 range les `crash_info_messages`, c'est-à-dire les messages du runtime Swift dont le texte d'un `fatalError` (`SentryCrashReportConverter.m` l.501-511) | `type`, `handled`, `synthetic`, `helpLink`, `meta` (signal, exception Mach, domaine et code NSError) |
| `Breadcrumb` | `category` et `type` (filtre réseau), `message`, `data` | `level`, `timestamp`, `origin` |

**Règles** (`CrashScrubber`, JoleneCore) :

- **Masqués**, avec le texte `[masqué]`, partout dans un texte :
  - la valeur d'un paramètre sensible :
    - tout nom qui finit par `token`, `token_hash`, `password`, `mot_de_passe`, `otp` ou `otp_code`, séparateurs `_` et
      `-` facultatifs et camelCase compris : `token`, `access_token`, `refresh_token`, `provider_token`,
      `provider_refresh_token`, `refreshToken`, `tokenHash`, `motDePasse`, `otpCode`, `p_otp_code` (code reçu par SMS
      pour signer un contrat, `fn_signer_contrat_otp`)… ;
    - les noms exacts `code`, `email` et `iban`, avec ou sans le préfixe `p_` des paramètres RPC : `p_code` est le code
      QR de pointage (`fn_scanner_code_pointage`) ;
  - cette valeur est masquée sous toutes ses formes : en requête ou en fragment, encodée une ou deux fois (`%3F…%3D`,
    `%253F…%253D`), en JSON (échappé `\"refresh_token\":\"…\"` ou non, valeur texte **ou nombre** : `{"code":123456}`),
    dans une description Swift (`refreshToken: "…"`, `tokenHash: Optional("…")`, `code: 123456`), et jusqu'à la fin du
    texte si la valeur est coupée. Dans un texte, rien ne distingue un code d'erreur d'un code OTP ou de pointage : tout
    nombre sous `code` y est masqué (revue B8 de la vague 5, m3), `Code=-1009` d'une description de `NSError` compris.
    Le code d'erreur reste lisible dans `mechanism.meta`, conservé tel quel ;
  - les jetons `Bearer` et les JWT ;
  - les adresses e-mail, y compris encodées (`%40`, `%2540`) et internationalisées : partie locale et domaine en lettres
    de toute écriture, accents composés ou décomposés compris (`josé@example.fr`, `zoë@exämple.fr` ; revue B8 de la
    vague 5, m3) ;
  - les IBAN : compacts, ou par groupes de quatre séparés par une espace, une espace insécable (U+00A0, U+202F) ou un
    tiret, toutes casses, sans contrôle mod 97 (un IBAN mal saisi reste une donnée bancaire).
- **Dictionnaires** (`extra`, contextes, `mechanism.data`, données des fils d'Ariane) : parcourus en profondeur. Une clé
  est sensible si, sans casse, sans le préfixe `p_` et sans séparateur, elle vaut `code`, `email` ou `iban`, ou finit par
  `token`, `tokenhash`, `password`, `motdepasse`, `otp` ou `otpcode`. **Toute** valeur d'une clé sensible est masquée,
  qu'il s'agisse d'un texte, d'un tableau, d'un dictionnaire ou d'un nombre, à une exception près : un nombre sous la clé
  exacte `code`, clé structurée qui porte un code d'erreur NSError ou HTTP. `p_code` et `otp` numériques sont masqués.
- **Retirés** : le nom de l'appareil (contexte `device`, qui porte souvent le prénom), la requête de l'événement et le
  nom du serveur. L'utilisateur est réduit à son seul identifiant.
- **Rejetés** : les fils d'Ariane réseau (`http`), par défense en profondeur puisque ces fils sont déjà coupés.
- **Coût borné** (revue B8 n°1, m1) : un texte de plus de 8 192 caractères est tronqué avant traitement et se termine
  par `…[tronqué]`. **Le mot que la limite coupe est retiré en entier**, jusqu'au dernier blanc (revue B8 de la vague 5,
  m3). Coupés, une adresse (`jean.dupont@exam`), un JWT sans signature ou une valeur encodée ne seraient plus reconnus, et
  leur début survivrait. Un texte sans aucun blanc avant la limite se réduit donc au marqueur. Seule limite connue : un IBAN
  à groupes coupé avant la fin de son deuxième groupe garde le pays, la clé et au plus le code banque (`FR76 3000`), qui
  n'identifient personne. Les expressions sont compilées une seule fois. Aucun motif n'essaie chaque position du texte avec un
  retour arrière non borné : les motifs sont ancrés sur un caractère précis ou sur une borne explicite, et l'adresse
  e-mail est cherchée à partir de son arobase. La garde est `CrashScrubberTests.testHuitMilleCaracteresAdversesTraitesSousLeSeuil` :
  dix textes adverses d'au moins 8 000 caractères, plus un texte réaliste, doivent chacun passer sous **100 ms**. Quatre de
  ces textes viennent de la vague 5 : noms OTP, codes de pointage, adresse non ASCII, mot coupé de 9 000 caractères. On
  retient le plus court de trois passages, si bien qu'une préemption passagère du simulateur ou du runner ne fait pas
  échouer le test. Mesures sur MacBook avec Xcode 16.4, en Debug, par texte : de 0,7 à 8,6 ms en `swift test` macOS, et de
  1,1 à 3,3 ms sur le simulateur iPhone 16 (iOS 18.6). Avant la correction, ces textes prenaient de 1,5 à 2,1 s. Après les
  règles de la vague 5 : de 0,6 à 6,0 ms en `swift test` macOS (simulateur non remesuré).
- `error_code`, `status_code`, `barcode`, `token_type`, `codeEtablissement`, `p_code_postal`, `codePostal` et les UUID de
  mission restent lisibles, même ceux qui commencent par deux lettres et deux chiffres. Masquer trop est accepté (un
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
- **En local** (recette du crash de test) : le DSN passe **en ligne de commande seulement**
  (`xcodebuild … JOLENE_SENTRY_DSN='https://…'`), **jamais dans un fichier**. Les trois xcconfig (`Base`, `Staging`,
  `Production`) sont versionnés, `Staging.xcconfig` compris : une ligne posée « temporairement » finit tôt ou tard dans
  un commit (revue B8 n°1, m5). Il n'y a donc pas de procédure depuis l'éditeur d'Xcode : on construit avec
  `xcodebuild`, puis on lance l'app sans débogueur (§6). Par exemple, pour le simulateur :

  ```sh
  xcodebuild build -project ios-native/Jolene.xcodeproj -scheme Jolene-Staging -configuration Debug \
    -sdk iphonesimulator -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath <dossier> \
    JOLENE_SUPABASE_PUBLISHABLE_KEY='sb_publishable_…' JOLENE_SENTRY_DSN='https://…'
  ```

  Le DSN et la clé ne doivent pas rester dans l'historique du shell : préfixer la commande d'une espace, si le shell est
  réglé pour ignorer ces lignes, ou lire les valeurs depuis le trousseau dans des variables d'environnement. Les deux
  gardes ci-dessus rougissent si un xcconfig versionné porte un DSN ; une garde node vérifie aussi que ce document n'en
  propose jamais l'écriture (`ios-native-testflight.node.mjs`).
- **Format accepté** : `https://<clé publique>@<hôte>/<projet>`. Un DSN qui porte un mot de passe (`<clé>:<secret>@`) est
  refusé, et Sentry reste désactivé (`ConfigurationCrash.dsnValide`, revue B8 n°1, m6).
- **Région de données, restriction d'hôte à venir.** L'hôte du DSN n'est pas encore restreint. **Gabrielle doit
  confirmer la région de données de l'organisation `jolene-z6`** ; la région UE est recommandée pour des données de
  santé, même pseudonymisées. Un projet de la région UE envoie à `o<id>.ingest.de.sentry.io`. Une fois la région
  confirmée, `dsnValide` n'acceptera que l'hôte de cette région, avec son test (suite de la revue B8 n°1, m6).
- **Exposition.** Un DSN est une clé d'**envoi** seulement : elle ne donne aucun accès en lecture, et toute app livrée
  la porte dans son Info.plist. Elle reste hors du dépôt par principe. Les artefacts du workflow TestFlight (IPA et
  `archive.log`, privés au dépôt, conservés 14 jours) la contiennent forcément.

## 6. Crash de test (DEBUG, recette T17)

Prérequis :

- un build Debug « Jolene-Staging » fait en ligne de commande, avec la clé publishable STAGING et le DSN passés en
  arguments de `xcodebuild` (commande du §5). Ni l'une ni l'autre n'est écrite dans `Staging.xcconfig`, qui est
  versionnée ;
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

1. Confirmer la **région de données** de l'organisation `jolene-z6` (UE recommandée pour des données de santé, §5).
   La restriction de l'hôte du DSN à cette région suivra, avec son test.
2. Créer le projet Sentry `jolene-ios` (plateforme Apple iOS) dans l'organisation `jolene-z6` et copier son DSN.
   Régler le projet : activer « Prevent Storing of IP Addresses », garder le *Data Scrubber* actif et configurer les
   alertes.
3. Créer le secret de dépôt GitHub `SENTRY_DSN_IOS` avec ce DSN : Settings → Secrets and variables → Actions → *New
   repository secret*. Sans lui, les builds TestFlight partent sans Sentry.
4. Recette du crash de test (§6), puis lecture de l'événement (T17).
5. Symbolication, hors de cette tranche : sans envoi des dSYM, les piles des builds TestFlight restent non
   symbolisées. Plus tard (lot 6) : envoi par `sentry-cli` avec un jeton `SENTRY_AUTH_TOKEN` propre au projet iOS, ou
   envoi manuel des dSYM de l'archive.
6. App Privacy d'App Store Connect (lot 6). Le manifeste de l'app déclare déjà `CrashData`, `PerformanceData`,
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
  - `CrashScrubberTests` : nettoyage, faux négatifs de la revue B8 n°1 (m2), coût borné et troncature (m1) ; faux
    négatifs de la revue B8 de la vague 5 (m3) : adresses non ASCII, codes OTP, `p_code`, nombres sous `code` dans un
    texte, mot coupé par la troncature ;
  - `CrashReportingTests` : démarrage, refus (DSN à mot de passe compris), release, réglages, identifiant de session
    (changement d'identité vers un espace bloqué, M2 ; retrait au début de `signIn` relevé au moment même de l'appel
    d'authentification, revue B8 de la vague 5, m2), et gardes statiques de la cible app (import isolé, démarrage avant
    le conteneur, démo sans port, crash de test sous DEBUG, DSN non versionné, recensement des propriétés traitées par
    `beforeSend` et `beforeBreadcrumb`, M1 et m3).
- Sentinelle réseau de la démo, inchangée : les XCUITest démo lisent toujours « 0 requête » (`network-sentinel`),
  puisque Sentry ne démarre jamais en démo.
- Node :
  - `tests/node/ios-native-testflight.node.mjs` : le secret est facultatif, lu par l'archive seule, jamais exigé ni
    affiché ; le DSN n'est pas versionné, et ce document ne propose jamais de l'écrire dans un fichier (m5) ; l'archive lit
    le `Package.resolved` sous la même toolchain et avec la même clé de cache qu'`ios-swift-ci.yml`, sans le réécrire,
    pin `kscrash` compris (revue B8 de la vague 5, M1) ;
  - `tests/node/ios-swift-ci-eclats.node.mjs` : le `Package.resolved` de l'app est vérifié juste après la résolution
    SPM, avant les éclats (m4). Revue B8 de la vague 5 : une dérive fait toujours échouer l'étape, après copie du fichier
    résolu ; l'artefact `package-resolved-<format>-<sha>` est publié juste après, sur échec seulement ; le pin `kscrash`
    est exigé (M1). Le socle porte la même condition que les autres éclats (m1).

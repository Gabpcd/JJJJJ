# Porte go/no-go du lot 0 (plan §4.2, §5 lot 0, décisions 4, 6 et 7)

Gabarit à remplir avant de figer la session et d'engager les quatre semaines du lot 1.
Chaque ligne donne la **mesure** attendue, **où la lire** (preuve, jamais un souvenir) et
le **verdict** à écrire : `go`, `go avec contrainte consignée` ou `no-go`. Une mesure non
lue reste « non mesurée » ; elle ne vaut ni go ni no-go. Le plan §4.2 : « si une de ces
mesures échoue, la contrainte est consignée avant de figer la session ».

Signature finale : Gabrielle, date, SHA de main relu.

Lecture des verdicts : « mesurée en local » = niveau 1 (tests à ports injectés, machine de
recette Xcode 16.4 / iOS 18.6, 2026-11-01) ; elle ne remplace ni le run CI macos-26 ni la
preuve STAGING (niveau 3), qui restent « non mesurée » tant que l'artefact n'existe pas.
Chaque preuve nomme sa destination réelle (macOS `swift test`, simulateur iPhone, iPad).

## 1. supabase-swift (plan §4.2, §11 jours 2-3)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 1.1 | Une clé `sb_publishable_…` est acceptée par `SupabaseClient` : connexion email + mot de passe réussie sur STAGING, `fn_get_my_role` répond `SOIGNANT`. | Artefact `ios-swift-staging-iphone-<sha>` (`xctest-summary.json` : `Passed`, `failedTests: 0`) et résumé du job « Connexion STAGING — iPhone » de `ios-swift-staging.yml`. Test `JoleneUITests/StagingConnexionTests` (écrit 2026-11-01 : Accueil, `profile-role` contient `SOIGNANT`, restauration après arrêt, déconnexion, aucune restauration après déconnexion). | non mesurée (test écrit, jamais exécuté : le workflow exige un dispatch manuel sur `main` par Gabrielle avec `JOLENE_NATIVE_AUTH_REVIEWED_SHA`) |
| 1.2 | PKCE : le flux email (`/inscription/confirmer`, `/reset-password`) échange un `code` sans `signInWithOAuth`. | Test unitaire `AuthCallbackCredentials` dans `JoleneCoreTests` (vecteurs de `src/lib/nativeLinks.test.ts`) ; échange réel au lot 1 par Universal Link. | non mesurée |
| 1.3 | Stockage Keychain personnalisé : `KeychainSessionStorage` (`JoleneSupabase/Keychain`) conforme à `AuthLocalStorage`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, sans synchronisation iCloud ; session restaurée après arrêt du processus. | `swift test` JoleneSupabase (journal `joleneSupabase-tests.log` de l'artefact `ios-swift-packages-<sha>`) ; phase « restauration après arrêt » de `StagingConnexionTests`. | mesurée en local (macOS, `swift test` JoleneSupabase 2026-11-01 : 76 tests, 0 échec, dont `KeychainSessionStorageTests`) ; restauration réelle après arrêt : non mesurée (STAGING) |
| 1.4 | Erreurs PostgREST `PGRST202`, `300` à `303` traitées comme refus définitifs sans renvoi. | Tests à transport injecté dans `JoleneSupabaseTests` (`SupabaseErrorMappingTests`, 7 tests). | mesurée en local (macOS, 2026-11-01 : vert dans les 76 tests JoleneSupabase) ; CI macos-26 : non mesurée |
| 1.5 | Garde d'environnement : clé secrète refusée, ref hors allowlist refusé, mode démo sans URL ni clé, mode inconnu refusé, surcharges ignorées hors DEBUG. | `JoleneCoreTests/EnvironmentTests.swift` (14 tests, créé à la relecture lot 0 : la référence antérieure visait un fichier inexistant), `JoleneSupabaseTests/SupabaseGatewaysTests` (garde avant construction du client), `JoleneUITests/EnvironmentGuardTests` (écran `env-blocked`, simulateur). | mesurée en local (macOS `swift test` JoleneCore 2026-11-01 : 145 tests, 0 échec ; simulateur iPhone iOS 18.6 : voir 2.1) ; CI macos-26 : non mesurée |

## 2. Chaîne CI (plan §4.8, §11 jours 4-5)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 2.1 | `ios-swift-ci.yml` vert sur une PR : jobs « Cœur », « Packages » (swift test macOS, concurrence stricte, 0 avertissement), « UI — iphone / ipad-portrait / ipad-landscape » (XCUITest démo **plus `JoleneCoreTests` et `JoleneDesignTests` sur le simulateur**, `StagingConnexionTests` exclu). | Onglet Checks de la PR « ios-native : socle lot 0 » ; résumé de chaque job UI (cibles exécutées, total ≥ 100). | **mesurée 2026-11-02, verte** : run `ios-swift-ci.yml` 41392954430 (PR #1106, commit `c20bbed2` — branche squashée en un commit le 02/11 pour le contrôle GitGuardian, runs conservés —, macos-26, Xcode 26.4.1, iOS 26.2) — Cœur, Packages, UI iphone / ipad-portrait / ipad-landscape tous verts, 152 tests simulateur par format (151 + 1 UI démo), captures en bonne orientation. Trois corrections de test ont été nécessaires sur iPad (runs 41388247632 → 41391523491) : apostrophes dans le résumé xcresult, `isHittable` d'une `List`/`ScrollView` SwiftUI invalide sur iPad (`containerVisible`), focus du mot de passe par Retour sur l'email en paysage |
| 2.2 | Temps de build CI : durée de `build-for-testing` par job UI (secondes) et durée totale du job ; seuil d'alerte 20 min de build, plafond 60 min de job. | Ligne « durée build-for-testing » du résumé de chaque job UI (`GITHUB_STEP_SUMMARY`) ; durée du job dans l'interface Actions. Noter cache SPM chaud / froid. | non mesurée |
| 2.3 | Au moins 200 vecteurs golden importés et verts (dates, format de mission, heures hebdomadaires, disponibilité de pointage), produits contre `date-fns` réel (plus de shim), sans entrée dupliquée. | Journal `joleneCore-tests.log` : nombre de tests exécutés ; `git diff --exit-code` du job « Cœur » après `export-golden-vectors.mjs`. | mesurée en local 2026-11-01 : 1 337 vecteurs (533 + 222 + 419 + 163), export idempotent (`git diff` vide après réexport), `format-mission.json` identique avec `date-fns` 3.6.0 réel ; CI : non mesurée |
| 2.4 | Contrats RPC sans dérive (16 RPC, `ios-native/rpc-contracts.json`). | Étape « Contrats RPC sans dérive » du job « Cœur » ; `node scripts/mobile/check-rpc-contracts.mjs` en local. | mesurée en local 2026-11-01 : « 16 RPC, aucune dérive » ; CI : non mesurée |
| 2.5 | Captures XCUITest dans l'orientation attendue sur les trois formats (nombre de captures > 0 par format). | `orientation.json` et résumé du job UI ; un run à zéro capture ne prouve pas l'orientation. | non mesurée |
| 2.6 | Aucune requête réseau en mode démo. | `DemoConsultationTests` (sentinelle `network-sentinel` = « 0 requête », simulateur) et `DemoNoNetworkTests` (introspection des sources JoleneCore, macOS). | mesurée en local 2026-11-01 (macOS pour `DemoNoNetworkTests` ; iPhone iOS 18.6 pour la sentinelle, voir « recette locale ») ; CI : non mesurée |

Recette locale 2026-11-01 (Xcode 16.4, simulateur « Jolene iPhone 16 Pro Max 18.6 », mêmes
drapeaux `xcodebuild` que le job UI, orientation portrait) : voir la ligne « Résultat
simulateur iPhone » ci-dessous, complétée par l'agent de corrections après exécution.

- Résultat simulateur iPhone (2026-11-01, `xcodebuild test-without-building … -only-testing:JoleneUITests
  -only-testing:JoleneCoreTests -only-testing:JoleneDesignTests -skip-testing:JoleneUITests/StagingConnexionTests`) :
  xcresult `Passed`, 152 tests, 152 réussis, 0 échoué, 0 ignoré = `JoleneCoreTests` 145 (dont vecteurs golden,
  fuseau Europe/Paris sous Foundation iOS, `EnvironmentTests`), `JoleneDesignTests` 5 (règle OTP, clavier),
  `JoleneUITests` 2 (`DemoConsultationTests` : 30 missions, détail, sentinelle « 0 requête », déconnexion ;
  `EnvironmentGuardTests` : `env-blocked`). `build-for-testing` : TEST BUILD SUCCEEDED, 0 avertissement
  sous `ios-native/`. iPad portrait / paysage : mesurés en CI (run 41392954430, verts), non en local.

## 3. signUp sans captchaToken (décision 6)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 3.1 | STAGING : code HTTP et corps de `POST /auth/v1/signup` depuis un client sans `captchaToken` (email jetable `@example.invalid`). Attendu si la protection captcha GoTrue est active : `400`/`422` avec mention captcha ; sinon `200` avec utilisateur créé. | Artefact `ios-swift-signup-sans-captcha-<sha>` (`signup-sans-captcha.json` : `httpStatus`, `captchaRefuse`, `body` sans jeton) du job « signUp sans captchaToken — STAGING ». | non mesurée |
| 3.2 | Production : même appel, exécuté **manuellement par Gabrielle** (jamais depuis un workflow : création d'un compte sur la base de production). Consigner code et corps ici, sans jeton. | Saisie manuelle : date, code HTTP, extrait du corps. | non mesurée |
| 3.3 | Nettoyage : le compte jetable STAGING éventuellement créé est supprimé (tableau de bord Auth STAGING). | Note manuscrite avec l'email jetable et la date. | non mesurée |

Conséquence : si 3.1 ou 3.2 renvoie un refus captcha, l'inscription native (lot 3) doit
intégrer un fournisseur captcha ou une exemption serveur ; décision à instruire avant le lot 3.

## 4. APNs sandbox (décision 7)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 4.1 | Les secrets Supabase `APNS_TEAM_ID` et `APNS_KEY_ID` correspondent à l'équipe `GDU5AA28M9` (identité store, `Config/Base.xcconfig`). Point d'attention : `docs/PUSH_NATIVE_FINAL.md` l.32 et l.74 citent l'équipe `FPQ78HDF4Y`, également présente dans `public/.well-known/apple-app-site-association`. | Sonde `apns-probe.yml` (edge `apns-probe`, jeton fournisseur signé avec les secrets, appel APNs sans token d'appareil) sur `sandbox` et `production` ; comparer au Team ID affiché dans Apple Developer. | mesurée 2026-11-01 (run 41357557527) : **NON** — `auth_ok` sur les deux hôtes (Apple accepte le jeton, HTTP 400 `BadDeviceToken` attendu) mais `team_id_correspond=false` ; l'empreinte SHA-256 de `APNS_TEAM_ID` est celle de `FPQ78HDF4Y` (équipe d'origine avant le transfert du 07/09/2026). À faire par Gabrielle : nouvelle clé APNs sous `GDU5AA28M9`, rotation de `APNS_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` (prod et staging), puis relance de la sonde (mode témoin `temoin=true`, PR #1102, attend `topic_refuse`). **Témoin mesuré 2026-11-02 (run 41454572139, PR #1102 mergée)** : sur `sandbox` et `production`, Apple répond `400 BadDeviceToken` au topic inexistant `app.jolene.sonde-inexistante` (verdict `auth_ok`, pas `topic_refuse`) ; le workflow échoue comme prévu. Conclusion : avec la clé actuelle, la sonde nominale ne prouve que la signature du jeton fournisseur, pas l'autorisation de l'équipe sur `app.jolene` ; seule la rotation de la clé sous `GDU5AA28M9` puis l'envoi sandbox réel (4.2) tranchera |
| 4.2 | Un envoi sandbox via `supabase/functions/send-push` (`APNS_ENVIRONMENT=sandbox`) vers un token de build Debug aboutit (`200` APNs, notification reçue sur l'appareil). | Journal de l'edge `send-push` (Supabase → Logs), notification visible sur l'iPhone, `tokens_push` relue. Niveau 5 (appareil physique). | non mesurée |
| 4.3 | Entitlement `aps-environment` du projet Swift : `development` en Debug, `production` en Release (`Config/*.xcconfig`, `Jolene.entitlements`). | `ios-native/Config/Base.xcconfig`, `Staging.xcconfig`, `Production.xcconfig`. | non mesurée |

## 5. Cible iOS minimale (décision 4)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 5.1 | Répartition des versions iOS des sessions Sentry sur 30 jours : part des sessions sous iOS 16. | Console Sentry `jolene-z6` → projet `jolene-app` → Discover, filtre `os.name:iOS`, colonne `os.version` (`docs/sentry-setup.md`). Le projet web ne reçoit que les sessions de la coquille Capacitor : préciser la couverture. | non mesurée |
| 5.2 | Répartition des versions iOS des installations App Store Connect (app 6774672845) sur 30 jours. | App Store Connect → Analytics → Métriques → Installations, dimension « Version iOS ». | non mesurée |
| 5.3 | Décision : iOS 16 minimum (`IPHONEOS_DEPLOYMENT_TARGET = 16.0`, `NavigationStack`) ou iOS 15 (`NavigationView`). | `DECISIONS_LOT0.md` décision 4, `Config/Base.xcconfig`. | non mesurée |

## 6. Critères de sortie du lot 0 restants (plan §5)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 6.1 | Table de routage testée unitairement sur les quinze motifs AASA, dont `/admin/*` et `/groupe/*` vers Safari. | `JoleneCoreTests` (`LinksAASATests`, `LinksRouterTests`), `AASAPatterns.swift` comparé à `public/.well-known/apple-app-site-association`. | mesurée en local (macOS `swift test` 2026-11-01, vert) ; CI : non mesurée |
| 6.2 | Connexion STAGING exécutée une fois avec assertion sur l'écran Accueil et sur le rôle `fn_get_my_role`. | `ios-swift-staging.yml`, artefact `xctest-summary.json` et `xctest-excerpt.redacted.log` ; test `StagingConnexionTests` présent (le job `politique` ne refuse plus de tourner). | non mesurée (à exécuter par Gabrielle : dispatch sur `main`, variable `JOLENE_NATIVE_AUTH_REVIEWED_SHA`, environnement protégé `native-staging-auth`) |
| 6.3 | Aucune modification sous `ios/`, `android/`, `capacitor.config.ts`, `supabase/`. | `git diff --stat main...HEAD -- ios android capacitor.config.ts supabase` vide. | mesurée en local 2026-11-01 sur `feat/ios-native-lot0` : diff vide (également vide pour `mobile-native/`) |
| 6.4 | Workflows `native-*.yml` gelés et tag d'archive du pilote posé (décision 5). | `.github/workflows/`, `git tag`. | mesurée 2026-11-02 : **fait** — PR #1100 (01/11) : six workflows RN en `workflow_dispatch` seul avec bandeau « GELÉ », désactivés côté GitHub (`disabled_manually`), bandeaux « PÉRIMÉ » dans `docs/store-readiness.md`, `docs/PUSH_NATIVE_FINAL.md`, `docs/CAPACITOR_PRODUCTION.md` ; tag `archive/mobile-native-rn-pilot` → `412b1cac` (dernier merge du pilote, PR #1098). `android-native-recette.yml` (Capacitor, décision 1) reste actif. Suppression de `mobile-native/` au lot 7 |
| 6.5 | Mémo de décisions `DECISIONS_LOT0.md` complet (neuf questions tranchées). | `docs/mobile-swift/DECISIONS_LOT0.md`. | mesurée : 9/9 « à valider », aucune décision signée par Gabrielle |

## Verdict global

| Décision | Verdict | Contrainte consignée | Signature |
|---|---|---|---|
| Engager le lot 1 (quatre semaines) sur supabase-swift 2.55.5, iOS 16, PKCE + Keychain | (vide : le lot 0 n'est pas « livré » — 1.1, 3.x, 4.x, 5.x, 6.2 et 6.4 restent non mesurés ou non faits ; aucun artefact STAGING n'existe) | | |

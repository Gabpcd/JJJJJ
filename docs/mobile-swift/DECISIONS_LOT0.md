# Décisions du lot 0 — application iOS Swift native

> Tranchées par Gabrielle le 1er novembre 2026, en séance avec Claude Code, sur
> les neuf questions de la section 10 de `docs/PLAN_APP_NATIVE_SWIFT.md`.
> Toutes les recommandations du plan ont été suivies. Ce mémo fait foi ; le
> plan n'est pas réécrit.

| # | Question | Décision | Conséquence immédiate |
|---|----------|----------|-----------------------|
| 1 | Android pendant le chantier iOS | **Capacitor seul sur le Play Store, OTA compris. Aucun jumeau Kotlin avant un cycle 2.x stable.** | Aucun plugin natif Android ajouté ; `android/`, `capacitor.config.ts`, OTA et lane fastlane android restent vivants. Revue go/no-go Kotlin à la fin du lot 7. |
| 2 | Remplacement en place | **Oui.** Bundle `app.jolene`, Team `GDU5AA28M9`, App Store ID `6774672845`, version 2.0.0 build ≥ 25. | TestFlight sur le même App ID pendant tout le chantier. Bascule App Store uniquement après parité soignant et établissement terrain signées (lots 4 et 5). Autres rôles renvoyés vers jolene.app. |
| 3 | Longue traîne soignant | **WKWebView authentifiée bornée**, retirée lot par lot. | Access token seul injecté, jamais de refresh token côté web ; data store non persistant invalidé par epoch de session ; projet Playwright « embarqué » et tests vitest sur toute branche de plateforme ajoutée au front. |
| 4 | Cible iOS minimale | **iOS 16**, sous réserve de lecture des versions réelles (Sentry, App Store Connect) au lot 0. | `IPHONEOS_DEPLOYMENT_TARGET = 16.0`, `NavigationStack`. Si plus de 2 % des sessions iOS sont en iOS 15, repli iOS 15 avec `NavigationView` consigné ici. |
| 5 | Pilote React Native | **Gel immédiat.** | Six workflows `native-*.yml` passés en `workflow_dispatch` seul et désactivés côté GitHub ; tag d'archive `archive/mobile-native-rn-pilot` posé sur le dernier commit de main contenant le pilote ; extraction au lot 0 (fixtures, helpers XCTest, champ OTP UIKit, scripts) ; suppression de `mobile-native/` au lot 7. |
| 6 | Captcha GoTrue | **Oui**, test `signUp` sans `captchaToken` sur STAGING puis production avant tout code d'inscription native. | Exécuté en CI STAGING au lot 0 (jour 7), résultat consigné dans `docs/mobile-swift/PORTE_LOT0.md`. |
| 7 | Vérification APNs | **Oui**, avant le lot 0. | Envoi sandbox via `send-push` ; une réponse APNs `BadDeviceToken` prouve que la clé .p8 et `APNS_TEAM_ID` sont acceptés, `InvalidProviderToken` prouve le contraire. Résultat consigné dans `PORTE_LOT0.md`. |
| 8 | iPad | **Binaire universel, rendu adaptatif, pas de design iPad dédié.** | Famille d'appareils 1,2 ; XCUITest sur iPhone, iPad portrait et iPad paysage comme l'exige `CLAUDE.md`. |
| 9 | Drapeau distant | **Oui.** `fn_param_bool` (`src/hooks/useParamBool.ts`) pour désactiver un écran natif cassé et afficher un renvoi web. | Clés `ios_natif_<ecran>_actif`, lues au démarrage et au retour au premier plan ; aucune nouvelle RPC. |

## Règles qui découlent de ces décisions

- Aucun travail iOS hors `ios-native/`, sauf correctif de sécurité ou de conformité store livré en 1.0.x par la coquille Capacitor.
- Aucune modification sous `ios/`, `android/`, `capacitor.config.ts` ni `supabase/` pendant le lot 0.
- Mergé n'est pas livré : chaque lot n'est clos que lorsque ses critères de sortie (section 5 du plan) sont tous acquis, preuves à l'appui.
- Les montants, le net estimé et les règles juridiques restent des valeurs serveur, jamais recalculées dans l'app.

## Mandat d'exécution

Gabrielle a demandé le 1er novembre 2026 que les lots s'enchaînent sans interruption, avec merge sur main dès que la CI est verte, sans validation intermédiaire de sa part, hors catégories B9 de `CLAUDE.md` (paiements, migrations destructives, RLS/auth, légal utilisateur, données prod) qui attendent toujours un go explicite.

## Mise en œuvre par le socle lot 0 (état au 02/11/2026, branche `feat/ios-native-lot0`)

Pour chaque décision : la recommandation du plan, ce que le socle du lot 0 suppose déjà dans le
code (afin qu'aucune décision implicite ne reste cachée) et l'état de mise en œuvre. Les
décisions elles-mêmes sont celles du tableau ci-dessus ; les preuves sont dans `PORTE_LOT0.md`.

| # | Question (plan §10) | Recommandation du plan | Hypothèse prise par le socle lot 0 | Statut de mise en œuvre |
|---|---|---|---|---|
| 1 | Android reste sur la coquille Capacitor (OTA compris) pendant tout le chantier iOS | oui | Aucune modification sous `android/`, `ios/`, `capacitor.config.ts` ; `mobile-delivery.yml` intact | décision prise le 01/11/2026 (PR #1100) |
| 2 | Remplacement en place : `app.jolene`, Team `GDU5AA28M9`, App Store ID 6774672845, 2.0.0 (build 25) | oui | `ios-native/Config/Base.xcconfig` : `PRODUCT_BUNDLE_IDENTIFIER = app.jolene`, `DEVELOPMENT_TEAM = GDU5AA28M9`, `MARKETING_VERSION = 2.0.0`, `CURRENT_PROJECT_VERSION = 25` | décision prise le 01/11/2026 (PR #1100) |
| 3 | Longue traîne soignant : WKWebView bornée ou renvoi Safari | WebView bornée | Lot 0 : `JoleneRoute.safari(URL)` et `.etablissement(URL)` renvoient vers `https://jolene.app` (Safari) ; aucune WebView n'est écrite. La matrice `PARITE_SOIGNANT.md` marque « renvoi web proposé » pour premium, prévoyance, mandat, charges | décision prise le 01/11/2026 (PR #1100) |
| 4 | Cible iOS 16 minimum (contre 15.0 aujourd'hui) | oui, après lecture Sentry / App Store Connect | `IPHONEOS_DEPLOYMENT_TARGET = 16.0`, packages `.iOS(.v16)`, `NavigationStack` dans `MainTabView` et `MissionsListScreen`. Mesures 5.1 et 5.2 de `PORTE_LOT0.md` non lues | décision prise le 01/11/2026 (PR #1100) |
| 5 | Gel du pilote React Native : workflows `native-*.yml` désactivés, tag d'archive, suppression de `mobile-native/` au lot 7 | oui | **Fait** (PR #1100 du 01/11 + tag posé le 02/11) : les six workflows `native-*.yml` sont en `workflow_dispatch` seul avec bandeau « GELÉ » et désactivés côté GitHub (`disabled_manually`) ; bandeaux « PÉRIMÉ » posés dans `docs/store-readiness.md`, `docs/PUSH_NATIVE_FINAL.md`, `docs/CAPACITOR_PRODUCTION.md` ; tag `archive/mobile-native-rn-pilot` → `412b1cac` (dernier merge du pilote, PR #1098). Reste au lot 7 : suppression de `mobile-native/`. `ios-swift-staging.yml` réutilise `mobile-native/scripts/auth-staging/*` et `ios-ci-toolchain.mjs` sans les modifier (ils doivent donc rester sur `main` jusqu'au lot 7) | décision prise le 01/11/2026 (PR #1100) |
| 6 | `signUp` STAGING puis production sans `captchaToken` avant tout code d'inscription | oui | Job `signup-sans-captcha` de `ios-swift-staging.yml` (STAGING seulement, email jetable `@example.invalid`, jetons retirés de l'artefact). Production : exécution manuelle par Gabrielle uniquement (CLAUDE.md B9, création d'un compte réel) | décision prise le 01/11/2026 (PR #1100) |
| 7 | Vérifier `APNS_TEAM_ID` / `APNS_KEY_ID` = `GDU5AA28M9` par un envoi sandbox | oui | **Vérifié par sonde le 01/11/2026, résultat négatif** : `apns-probe.yml` (run 41357557527) obtient `auth_ok` sur sandbox et production (jeton accepté par Apple) mais `team_id_correspond=false` ; l'empreinte du secret `APNS_TEAM_ID` est celle de `FPQ78HDF4Y`, équipe d'origine avant le transfert de `app.jolene` vers `GDU5AA28M9` (07/09/2026). Les notifications iOS de l'app Swift ne partiront pas tant que les secrets ne sont pas réémis. **À faire par Gabrielle** : créer une clé APNs sous `GDU5AA28M9` (Apple Developer → Keys), tourner `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` dans Supabase prod et staging, relancer la sonde (mode témoin `temoin=true` de la PR #1102 : attend `topic_refuse`, preuve que le contrôle d'équipe discrimine). L'envoi sandbox vers un appareil physique (critère 4.2) reste niveau 5 | décision prise le 01/11/2026 (PR #1100) |
| 8 | iPad : binaire universel, rendu adaptatif, sans design dédié | oui | `TARGETED_DEVICE_FAMILY = 1,2` ; `JoleneUITests` exécutés sur iPad portrait et paysage (`JOLENE_UI_ORIENTATION`), même scénario que l'iPhone | décision prise le 01/11/2026 (PR #1100) |
| 9 | Drapeau distant `fn_param_bool` pour désactiver un écran natif cassé | oui | Aucun drapeau consommé au lot 0 (aucune RPC `fn_param_*` dans `rpc-contracts.json`). À ajouter à `RPC_SUIVIES` de `scripts/mobile/check-rpc-contracts.mjs` au lot qui le consomme | décision prise le 01/11/2026 (PR #1100) |

## Hypothèses techniques posées par le socle (porte go/no-go, `PORTE_LOT0.md`)

- supabase-swift épinglé en `exact: "2.55.5"` (dernière version en swift-tools 6.1 ; 2.55.6
  exige Xcode 26). PKCE (`flowType: .pkce`), stockage `KeychainSessionStorage`
  (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`),
  en-tête `X-Client-Info: jolene-ios/2.0.0`. Preuve locale : tests à transport injecté
  (`JoleneSupabaseTests`), aucune preuve STAGING encore (mesure 1.1).
- Swift 5 avec `SWIFT_STRICT_CONCURRENCY = complete` sur la cible app ; les trois packages
  portent `swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]` sur chaque cible
  (sources et tests), et le job « Packages » de `ios-swift-ci.yml` recompile les cibles
  Jolene avec `-Xswiftc -strict-concurrency=complete` en exigeant 0 avertissement hors
  `.build/checkouts/` (relecture lot 0 : avant cette correction, la CI ne passait aucun
  drapeau et la phrase ci-dessus n'était pas vérifiée). Preuve locale 2026-11-01 : `swift
  test` JoleneCore 145 tests / JoleneSupabase 76 tests, 0 échec, 0 avertissement.
- Toolchain CI : Xcode 26.4.1 (17E202), runtime iOS 26.2, simulateurs « iPhone 17 » et
  « iPad (A16) » ; toolchain locale de recette : Xcode 16.4 / Swift 6.1.2, simulateurs
  iOS 18.6. Le premier run `ios-swift-ci.yml` sur GitHub Actions reste à observer.
- Mode démo : fixtures JSON exportées par `scripts/mobile/export-demo-fixtures.mjs`,
  horloge fixée `2026-11-02T00:00:00Z`, sentinelle `URLProtocol` qui compte toute
  requête (assertion « 0 requête » dans `DemoConsultationTests`).

## Écarts assumés du port Swift (relecture lot 0)

- **Ordre des missions** : `est_urgente.desc.nullsfirst` explicite, identique à la requête
  supabase-js du pilote et du web (`.order('est_urgente', { ascending: false })` sans suffixe
  = NULLS FIRST par défaut Postgres sur un DESC). `est_urgente`, `statut`, `profession` et
  `tous_documents_valides` sont NULLables : le décodage Swift tolère NULL (`false`, `""`)
  au lieu d'échouer sur la page entière.
- **Créneau PREVISIONNEL à date illisible** : le web lève (`instantJolene`) ; le port marque le
  planning non exact (fail-closed, message « ne peut pas être vérifié ») et ne compte que les
  heures lisibles. `PlanningCandidatRules` délègue `creneauxPrevisionnels` et
  `ajouterRepliMissionPonctuelle` à `DisponibilitePointage` (une seule implémentation, celle
  des vecteurs golden), comme `planning-candidat.ts` importe `disponibilite-pointage.ts`.
- **Rôle `INCONNU`** : voir `PRINCIPES.md` §5 (renvoi web, repli `parcours_inscription` porté au lot 3).
- **Surcharges de lancement** (`-JOLENE_MODE`, `JOLENE_MODE`, `JOLENE_FORCE_BAD_KEY`) et
  sentinelle réseau : DEBUG uniquement ; en Release seul l'Info.plist (xcconfig) fait foi et un
  mode inconnu ou absent affiche l'écran bloquant au lieu de retomber sur la production.

## Ce qui n'est pas une décision de ce mémo

Toute règle juridique exposée à l'utilisateur (modes d'exercice, avertissements, wording
contractuel) relève du HARD STOP n°4 de `CLAUDE.md` : elle n'est ni tranchée ici ni
implémentée au lot 0. Les montants et règles affichés par l'app sont des valeurs serveur.

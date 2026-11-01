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

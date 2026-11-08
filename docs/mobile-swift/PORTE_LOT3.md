# Porte go/no-go du lot 3 (plan §5 « Lot 3 », l.196-200 ; `DECISIONS_LOT3.md`)

Squelette créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT3_PLAN.md` §3 T0), rempli par T17.
Chaque ligne donne la **mesure** attendue, **où la lire** (preuve, jamais un souvenir) et le **verdict** à écrire :
`go`, `go avec contrainte consignée` ou `no-go`. Une mesure non lue reste « non mesurée » ; elle ne vaut ni go ni
no-go. Les critères sont ceux du plan **amendés** par `docs/mobile-swift/DECISIONS_LOT3.md` (section « Critères de
sortie du plan amendés ») ; le plan lui-même n'est pas réécrit.

Signature finale : Gabrielle, date, SHA de `main` relu.

Lecture des niveaux (`PRINCIPES.md` §7) : niveaux 1-2 = tests à ports injectés et XCUITest démo (CI
`ios-swift-ci.yml`, trois formats) ; niveau 3 = STAGING relu (`ios-swift-lot3-staging.yml`, fixture D5 et cohorte
non-test D5-R, go B9 au dispatch) ; niveau 5 = iPhone physique (`RECETTE_DEVICE_LOT3.md`). Aucun niveau ne prouve
les autres.

## 1. Push APNs (critère l.196)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 1.1 | Table de routage portée de `navigationPathForEvent`, verte sur les cas de `src/lib/pushNative.test.ts`. | Vecteurs golden de T2 (`RulesGoldenTests`), job « Cœur » de `ios-swift-ci.yml`. | non mesurée |
| 1.2 | Tap simulé à froid et à chaud (`-JOLENE_SIMULER_PUSH`) ouvrant l'écran attendu sur six types au moins. | `DemoPushTests` (T5), trois formats. | non mesurée |
| 1.3 | `fn_upsert_token_push` puis `fn_desactiver_mon_token_push` relus sur STAGING (`tokens_push.plateforme = 'IOS'`, `actif` vrai puis faux). | `StagingLot3Tests` (T16). | non mesurée |
| 1.4 | Push sandbox réel reçu et tapé sur iPhone pour six types, `tokens_push.actif` relu après chaque envoi. | `RECETTE_DEVICE_LOT3.md` §2 ; préalables : clé APNs sous `GDU5AA28M9`, `APNS_ENVIRONMENT = sandbox` STAGING, cohorte D5-R. | non mesurée |

## 2. Inscription (critère l.197, amendé : lien `token_hash` vérifié dans l'app)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 2.1 | Flux complet en démo (compte, confirmation `token_hash`, complétion, bascule vers l'espace soignant). | `DemoInscriptionTests` (T7, T8). | non mesurée |
| 2.2 | STAGING niveau 3 : `signUp` de l'app, `token_hash` relu en SQL puis injecté, `register-soignant`, ligne `soignants` relue, compte jetable nettoyé. | `StagingLot3Tests` (T16). | non mesurée |
| 2.3 | Universal Link de confirmation depuis Mail iOS, adresse de Gabrielle. | `RECETTE_DEVICE_LOT3.md` §3 ; préalables : modèle « Confirm signup » au format `token_hash`, Redirect URLs, captcha mesuré (`PORTE_LOT0.md` 3.1/3.2, D25). | non mesurée |

## 3. Stripe Connect (critère l.198)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 3.1 | En-tête `Origin: https://jolene.app` envoyé ; statuts et compte test conformes à la fiche de contrat. | `SupabaseStripeConnectGatewayTests`, `DemoStripeTests` (T14a). | non mesurée |
| 3.2 | STAGING : compte test → `TEST_ACCOUNT_PAYMENT_DISABLED` ; cohorte D5-R → URL d'onboarding obtenue. | `StagingLot3Tests` (T16). | non mesurée |
| 3.3 | Retour dans l'app par Universal Link sur iPhone en **iOS ≥ 17.4**, statut relu avec `force=true`. | `RECETTE_DEVICE_LOT3.md` §4 (Stripe TEST, valeurs saisies par Gabrielle). | non mesurée |

## 4. Sentry (critère l.199)

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 4.1 | Démarrage, nettoyage (`CrashScrubber`) et désactivation en démo testés. | `CrashScrubberTests`, `CrashReportingTests` (T15). | non mesurée |
| 4.2 | Crash de test reçu dans le projet `jolene-ios`, release 2.0.0 (25), sans PII. | `RECETTE_DEVICE_LOT3.md` §5 ; préalable : projet et DSN (§6.5 du blueprint). | non mesurée |

## 5. Profil, compte, revenus, paiements, IBAN

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 5.1 | Profil relu après modification ; aucune clé sensible décodée (`Mirror`). | `ProfilCompletTests`, `SupabaseProfilGatewayTests`, `StagingLot3Tests` (T9, T16). | non mesurée |
| 5.2 | Avatar : objet Storage et `avatar_url` relus ; HEIC réel converti. | `StagingLot3Tests`, `RECETTE_DEVICE_LOT3.md` §6 (T10). | non mesurée |
| 5.3 | Mot de passe, thème, export RGPD non vide. | `DemoCompteLot3Tests`, `StagingLot3Tests` (T11). | non mesurée |
| 5.4 | Revenus : montants égaux aux vecteurs golden, sept états escrow, colonnes de `MesGains.tsx` l.95 exactement. | `DemoRevenusTests`, vecteurs golden (T2, T12). | non mesurée |
| 5.5 | Paiement `DECLARE` confirmé puis `CONFIRME` relu ; contestation après **B3** : `CONTESTE` + litige + notification relus. | `StagingLot3Tests` (T13, T16) ; B3 mergée (go B9). | non mesurée |
| 5.6 | IBAN : `iban_last4` relu ; aucun faux succès sur `error_code` sans `error`. | `SupabaseIbanGatewayTests`, `StagingLot3Tests` (T14b, T16). | non mesurée |

## 6. Conditions transverses

| # | Mesure | Où lire | Verdict |
|---|---|---|---|
| 6.1 | Contrats RPC sans dérive (41 RPC au T0 du lot 3) et fiches confrontées aux sources. | `node scripts/mobile/check-rpc-contracts.mjs` ; `tests/node/check-rpc-contracts-lot3.node.mjs` (étape « Garde de livraison mobile »). | non mesurée (CI) |
| 6.2 | Go B9 obtenus pour B3, T7, T8, T12, T13, T14a, T14b et le dispatch de T16. | PR correspondantes (commentaire de Gabrielle). | non mesurée |
| 6.3 | Textes HARD STOP validés ou restés verbatim web avec leur source. | `DECISIONS_LOT3.md` « HARD STOP n°4 » ; tests de textes des tranches. | non mesurée |
| 6.4 | `docs/mobile-swift/PARITE_SOIGNANT.md` : lignes du lot 3 statuées avec preuve. | Matrice de parité. | non mesurée |
| 6.5 | TestFlight externe ouvert (décision explicite de Gabrielle, build parlant à la production). | App Store Connect. | non mesurée |
| 6.6 | Universal Links soignant complets (T3 = T3a + T3b, revue L3-T3 mineur 7) : coordinateur unique des liens et des taps, lien reçu avant `.ready` rejoué une fois, écran natif livré sinon renvoi web canonique par `SFSafariViewController`, `?code=` du reset refusé (option B). | `DeepLinkIntentTests`, `DestinationLienTests`, `LinksRouterTests` (job « Cœur ») ; `DemoLiensLot3Tests` trois formats ; lien réel depuis Mail sur iPhone (`RECETTE_DEVICE_LOT3.md`). | non mesurée |

## Verdict global

| Décision | Verdict | Contrainte consignée | Signature |
|---|---|---|---|
| Clore le lot 3 et engager le lot 4 | (vide tant que les mesures ci-dessus ne sont pas lues) | | |

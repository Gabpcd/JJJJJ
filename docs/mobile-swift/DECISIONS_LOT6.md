# Décisions du lot 6 — soumission App Store de l'app Swift et publication Android séparée

> Rédigé le 24 novembre 2026 sur la branche `lot6/preparation`. Ce mémo fait foi pour le lot 6 ;
> `docs/PLAN_APP_NATIVE_SWIFT.md` n'est amendé que par renvois datés. Plan en tranches et état de
> chaque élément : `docs/mobile-swift/LOT6_PLAN.md`. Mode d'emploi de la soumission :
> `docs/mobile-swift/APP_STORE.md`.

## D1 — Décision de la fondatrice (24/11/2026)

Texte consigné mot pour mot :

> « je n'ai pas besoin de passer par des testeurs internes. On est en prod directement, termine les lots afin de soumettre A APPLE et a GOOGLE PLAY »

Conséquences :

1. **La bêta externe TestFlight est abandonnée**, ainsi que le critère « crash-free sessions ≥ 99,5 % sur
   14 jours de bêta » et « aucun retour bêta bloquant ouvert » du lot 4 (plan §5, l.208 et l.210), et la
   ligne « TestFlight externe ouvert à une cohorte de soignants pilotes » du lot 3 (l.200).
   `docs/mobile-swift/BETA_LOT4.md` reste un squelette non rempli.
2. **La soumission se fait dès que les lots 4 et 5 sont sur `main`.** La condition est vérifiée par le code,
   sur la source du build soumis (D8), pas par une date. *Précision après la revue de #1177 (M2) : le code
   exige aussi qu'il ne reste aucun port en attente des lots 1 à 3. Aujourd'hui, `recovery` (lot 1) reste
   en attente : la soumission est bloquée tant qu'il n'est pas câblé ou accepté par écrit (« En attente »,
   n° 8).*
3. **La soumission reste un geste manuel** : un workflow lancé à la main depuis `main`, avec une phrase de
   confirmation. Aucun merge, aucun push, aucune fin de workflow ne soumet quoi que ce soit.

Ce que la décision ne change pas : les critères de sortie du lot 6 qui portent sur la production (liens
universels et push sur le build de production, suivi de la publication progressive) et la recette sur
appareil exigée par `CLAUDE.md`. Sans bêta, le premier signal d'usage réel vient de la publication
progressive : 1 % des appareils en mise à jour automatique le premier jour (source A3).

## État constaté le 24/11/2026 (lecture seule)

| Fait | Source |
|---|---|
| App Store et Play Store servent 1.0.7 (24), coquille Capacitor du 5 octobre | constat transmis à l'ouverture du lot ; tags `mobile-native-ios-24` et `mobile-native-android-24` sur `bf1c0ebf` |
| TestFlight contient 2.0.0 builds 25 à 31 | constat transmis ; sept runs réussis de `ios-native-testflight.yml` relus par l'API GitHub, artefacts `ios-native-testflight-29…31-<commit>` |
| Aucune OTA depuis le 5 octobre | aucun run `ota` ni `native` de `mobile-delivery.yml` depuis ; un run du 24/11 à 12:25 UTC n'a exécuté que le job `plan` (vérification, rien construit ni publié) |
| Sur `main` (`f6e6be49`), le lot 4 a onze ports non câblés et le lot 5 deux | `DemoWorldTests.portsEnAttenteLot4` et `portsEnAttenteLot5` |
| Le secret facultatif `SENTRY_DSN_IOS` n'existe pas | liste des noms de secrets du dépôt (`gh secret list`) ; les builds 25 à 31 sont donc partis sans Sentry |

## D2 — Deux chaînes séparées

| Plateforme | Envoi | Soumission | OTA |
|---|---|---|---|
| iOS, app Swift (`ios-native/`) | `ios-native-testflight.yml` (existant, inchangé) | `ios-native-app-store.yml` (nouveau) : soumet un build TestFlight déjà VALID | aucune, jamais (Apple 2.5.2, source A1) |
| Android, coquille Capacitor (`android/`) | `mobile-delivery.yml` mode `native` | même run : Google Play, piste production | `mobile-delivery.yml` mode `ota` |
| iOS, coquille Capacitor (`ios/`) | plus aucun | plus aucun | plus aucune (D5) |

**Écart avec le plan** (§5 « Lot 6 », l.225) : le plan faisait archiver le projet Swift par le job iOS de
`mobile-delivery.yml`. L'archive signée et ses douze gardes existent déjà dans `ios-native-testflight.yml`
(lot 1) ; les dupliquer aurait créé deux chemins de signature. `mobile-delivery.yml` devient donc Android
seul, et la soumission iOS part d'un build déjà traité par Apple.

## D3 — `config/mobile-release.json` scindé par plateforme

```json
{
  "ios": { "runtime": "swift", "marketingVersion": "2.0.0", "minimumBuildNumber": 32 },
  "android": { "runtime": "capacitor", "marketingVersion": "1.0.7", "buildNumber": 24 }
}
```

- **iOS** : la version est celle de `ios-native/Config/Base.xcconfig` (égalité vérifiée). Le numéro de build
  n'est pas figé : il est attribué à l'envoi TestFlight depuis App Store Connect. `minimumBuildNumber` est un
  plancher : 32, parce que TestFlight contient déjà 25 à 31, tous construits avant la clôture des lots 4 et 5.
  Aucun build inférieur ne peut être envoyé ni soumis.
- **Android** : `versionName` et `versionCode` de `android/app/build.gradle` (égalité vérifiée). La branche
  ne change pas la version : passer à 1.0.8 (25) est une PR de release à part (D10).
- L'ancien format à plat est refusé avec un message explicite, par tous les lecteurs
  (`scripts/mobile/release-config.mjs`).
- La coquille Capacitor iOS est **gelée** à 1.0.7 (24) : `check-mobile-build-alignment.mjs` échoue si `ios/`
  change de version, tant que le dossier existe.

## D4 — Tags scindés, jamais « les deux »

| Tag | Posé par | Sens |
|---|---|---|
| `mobile-native-source-android-N` | `mobile-delivery.yml`, job `reserve-native` | commit figé d'une livraison Android |
| `mobile-native-android-N` | `mobile-delivery.yml`, après la soumission Google Play | runtime Android N soumis ; base des OTA |
| `mobile-native-ios-N` | `ios-native-app-store.yml`, job `consigner` | build Swift N soumis à la revue, sur son commit source |

**Préfixe partagé, à connaître.** Les tags `mobile-native-ios-20…24` existants sont ceux de la coquille
Capacitor (avant la scission) ; les tags `mobile-native-ios-N` posés désormais, avec N ≥ 32
(`ios.minimumBuildNumber`), sont ceux de l'app Swift. Les deux familles portent le même préfixe et ne se
distinguent que par le numéro : les numéros 25 à 31 n'ont pas de tag (builds TestFlight non soumis).
Aucun lecteur ne mélange les deux aujourd'hui : le planificateur Android ignore les tags iOS, et
`release-state.mjs record ios` refuse un numéro inférieur à 32.

Les tags communs `mobile-native-20…24` et `mobile-native-source-20…24` restent comme historique. Ils ne
sont plus créés ; l'action `complete` de `release-state.mjs`, qui exigeait les deux plateformes, est
remplacée par un refus explicite. Les numéros iOS et Android sont désormais indépendants : un tag iOS ne
bloque ni ne débloque une livraison Android.

## D5 — OTA : Android seul

Trois verrous, chacun testé :

1. **iOS natif refusé par le planificateur** dans tous les modes (`MOBILE_DELIVERY_PLATFORM=ios`), et
   l'app Swift ne contient aucun client de mise à jour à chaud (garde sur `ios-native/`, rejouée sur la
   source du build à la soumission).
2. **Tout diff sous `ios-native/` interdit l'OTA** (plan, l.225) : un changement de l'app Swift exige un
   build store.
3. **OTA refusée sur un runtime que la coquille iOS a aussi porté.** Le client de mise à jour ne compare
   que le bundle, la version et le build (`src/lib/mobileUpdates.ts`, l.39-43). Un manifeste publié pour
   le build 24 atteindrait donc aussi les iPhone restés en 1.0.7 (24), sans recette iOS. L'OTA n'est
   possible qu'à partir d'un `versionCode` Android supérieur à 24.

**Conséquence pratique, à connaître** : la règle préexistante de `delivery-plan.mjs` n'autorise une OTA
que si tous les fichiers modifiés depuis le runtime sont sous `src/`, `public/`, `tests/`, `e2e/` ou
`docs/`, et si chaque PR qui touche le client porte le label `mobile:ota`. Tant que le chantier Swift
merge sur `main`, une OTA Android n'est donc possible que juste après un build natif. Je n'ai pas
assoupli cette règle : elle protège l'authentification, le paiement et le consentement. La rendre
indifférente aux chemins sans effet sur le runtime Android (`ios-native/`, `.github/`, `supabase/`) est
une décision à part (« En attente », n° 6).

## D6 — Coquille Capacitor iOS : gelée, plus livrée

- Le job iOS de `mobile-delivery.yml` est supprimé (plus de `xcodebuild` sur `ios/App`, plus de secrets
  Apple dans ce workflow).
- La lane `fastlane ios submit` (coquille) est remplacée par un refus explicite.
- `config/mobile-release-notes.txt` (notes de la coquille iOS) est supprimé.
- **Retour arrière** : le plan (l.233, §6) prévoyait « une 1.0.8 (26) soumise sous 24 h ». Ce n'est plus
  exact : les builds 25 à 31 sont pris par TestFlight, et un retour après la mise en vente de 2.0.0
  devrait porter un numéro de version supérieur à 2.0.0 (non vérifié : la page Apple « Create a new
  version » dit seulement « incremental », source A9). La procédure est écrite dans
  `LOT6_PLAN.md` (tranche T7) et **n'a pas été testée**.

## D7 — Soumission App Store : ce que fait le workflow

- Entrées : mode (`verifier` par défaut, `soumettre`), numéro du build, phrase `SOUMETTRE 2.0.0 (N)`
  (exigée en mode `soumettre`), mode de publication. Le mode `verifier` joue toutes les gardes et
  s'arrête avant la lane et le tag (revue M3 de #1177).
- Gardes en lecture seule, dans l'ordre : `entrees`, `notes`, gardes du dépôt du TestFlight, `provenance`,
  `ci-ios`, `lots`, `apple-4.2`, `ota`, backend de production déployé, `build`. Détail : `APP_STORE.md`.
- La lane refuse de tourner hors du job `soumettre` de ce workflow, sans le verdict des gardes de la même
  tentative ou sans la phrase exacte ; une relance partielle est refusée (revue m5 et m8 de #1177).
- Écriture chez Apple : la lane `ios submit_native`, protégée par la garde existante
  `fastlane/ios_review_submission.rb` (version supérieure à la version en vente, build VALID, non expiré,
  `usesNonExemptEncryption = false`, une seule soumission en cours).
- **Publication progressive** sur sept jours, toujours (source A3).
- **Mise en vente après approbation** : `automatique` par défaut (comportement de la coquille jusqu'ici,
  `docs/MOBILE_DELIVERY.md`) ou `manuelle` (la version attend en « Pending Developer Release », source A8).
- **La fiche n'est pas touchée**, sauf le champ « Nouveautés » fr-FR, lu dans
  `config/mobile-release-notes-ios.txt`. Les captures, la description, les notes pour la revue, la
  confidentialité et la classification se saisissent dans App Store Connect.
- **Texte des « Nouveautés »** : proposé dans le fichier, il annonce la reconnexion et la réactivation de
  Face ID (plan, l.225). Il est validé par la fondatrice à la revue de la PR ; ce n'est pas un texte
  juridique.

## D8 — « Lots 4 et 5 sur main » et garde Apple 4.2 : vérifiés sur la source du build

Le workflow retrouve le commit dont le build est issu (artefact `ios-native-testflight-<N>-<commit>` du
run TestFlight), exige qu'il appartienne à `main`, puis lit cette source :

- **`ci-ios`** (revue M1 de #1177) : le dernier run de `ios-swift-ci.yml` sur ce commit exact de `main`
  est réussi. Les listes de ports ne sont vraies que si `testAucunPortNonCable` passe ; or les checks
  requis de `main` n'incluent pas ce workflow, et le build 31 (`95a987f2`) est parti sur TestFlight avec
  un run iOS annulé. Aucun repli sur un ancêtre.
- **`lots`** : les cinq listes `DemoWorldTests.portsEnAttenteLot1` à `portsEnAttenteLot5` sont vides
  (revue M2 de #1177 : la première version n'exigeait que les lots 4 et 5 et laissait passer
  `recovery`, lot 1). Ce sont les listes que les lots eux-mêmes vident à leur clôture (`PRINCIPES.md`
  §2). Aucune exception en dur : `recovery` bloque la soumission tant qu'il n'est pas câblé ou accepté
  par une décision écrite de la fondatrice (`LOT6_PLAN.md` §2).
- **`apple-4.2`** (source A1) : les ports `dashboard`, `mesMissions`, `presence` et `pointage` sont câblés ;
  les écrans natifs du tableau de bord, de Mes missions et du pointage existent et les onglets les
  montent ; le client appelle `fn_dashboard_soignant_complet` et `fn_scanner_code_pointage` ; la racine de
  l'app ne monte aucune vue web.

Vérifié à blanc le 24/11 : le build 31 (`95a987f2`) et `main` sont refusés par `lots` seulement (treize
ports en attente aux lots 4 et 5, auxquels la garde corrigée ajoute `recovery` au lot 1), aucun refus
`apple-4.2` ni `ota`.

## D9 — Captures App Store

Les scripts existants (`scripts/capture-google-play.mjs`) photographient le site web : ils ne valent pas
pour l'app Swift (source A1, 2.3.3). La production des captures depuis l'app Swift en mode démo n'est pas
livrée par cette branche : un XCUITest ne peut être ni compilé ni exécuté sans `xcodebuild`, et son job
ne peut pas tourner avant d'être sur `main`. La marche à suivre est écrite dans `LOT6_PLAN.md`, tranche
T5 : cible de test à part, hors des éclats de `ios-swift-ci.yml`, job lancé à la main.

## D10 — Version Android

La branche laisse Android en 1.0.7 (24). Le passage à 1.0.8 (25) touche `android/app/build.gradle`,
`config/mobile-release.json` et le texte « Nouveautés » de Google Play (500 caractères au plus, source
G12) : c'est une PR de release, à ouvrir quand le contenu web à livrer est recetté sur Android.

## En attente de la fondatrice

1. Valider le texte de `config/mobile-release-notes-ios.txt`.
2. Choisir la mise en vente après approbation : automatique (défaut) ou manuelle.
3. Créer le secret `SENTRY_DSN_IOS` avant le build à soumettre, sinon aucun taux de crash ne sera mesuré
   pendant la publication progressive (`docs/mobile-swift/SENTRY_IOS.md`).
4. Faire dans App Store Connect et Play Console les saisies listées dans `LOT6_PLAN.md` §3 et §4.
5. Publication Android à 100 % dès l'approbation (lane actuelle, `release_status: 'completed'`, source
   G13) ou déploiement par étapes (source G7) : inchangé par défaut.
6. OTA Android pendant le chantier Swift : garder la règle stricte (défaut) ou la rendre indifférente aux
   chemins sans effet sur Android.
7. Retour arrière iOS : le tester une fois, ou l'abandonner explicitement.
8. `recovery` (réinitialisation native du mot de passe, lot 1) : le faire câbler avant la soumission
   (recommandé), ou accepter par écrit de soumettre sans lui. Tant que rien n'est décidé, la garde `lots`
   refuse (`LOT6_PLAN.md` §2).
9. Réglage du dépôt : environnement GitHub restreint à `main` pour les secrets Apple et Google
   (`APP_STORE.md`, « Secrets et droits »).

## Sources

« Vérifié » : page officielle lue le 24/11/2026. « Vérifié (résumé) » : page lue, passage extrait par
résumé automatique et non relu mot à mot. « Non vérifié » : la page ne s'est pas chargée ou ne le dit pas.

| # | Exigence | Page officielle | État |
|---|---|---|---|
| A1 | Règles de revue : 2.1(a) compte de démonstration et backend actif ; 2.3.1(a) nouveautés décrites dans les notes pour la revue ; 2.3.3 captures montrant l'app en usage ; 2.5.2 pas de code téléchargé qui change l'app ; 4.2 plus qu'un site réemballé ; 5.1.1(i) politique de confidentialité dans la fiche et dans l'app ; 5.1.1(v) suppression de compte dans l'app | https://developer.apple.com/app-store/review/guidelines/ | vérifié (5.1.1(i) : résumé) |
| A2 | Captures : iPhone à grand écran avec Dynamic Island 1260×2736, 1290×2796 ou 1320×2868 ; iPad 13 pouces 2064×2752 ou 2048×2732, exigé si l'app tourne sur iPad ; 1 à 10 par format | https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/ | vérifié pour les dimensions ; **non vérifié** : lequel des formats iPhone (grand ou moyen écran) est obligatoire |
| A3 | Publication progressive : 7 jours, 1 %, 2 %, 5 %, 10 %, 20 %, 50 %, 100 % ; pause jusqu'à 30 jours ; mise à jour manuelle toujours possible | https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/ | vérifié (résumé) |
| A4 | Confidentialité de l'app : réponses exigées pour soumettre une app ou une mise à jour, à tenir exactes | https://developer.apple.com/app-store/app-privacy-details/ | vérifié |
| A5 | Classification : 4+, 9+, 13+, 16+, 18+ ; une app non classée ne peut pas être publiée | https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/ | vérifié (résumé) |
| A6 | Exigences en vigueur : Xcode 26 et SDK iOS 26 depuis le 28/04/2026 ; raisons d'API déclarées ; nouvelles questions de classification à remplir avant le 31/01/2026 pour continuer à soumettre | https://developer.apple.com/news/upcoming-requirements/ | vérifié |
| A7 | Suppression de compte lancée depuis l'app | https://developer.apple.com/support/offering-account-deletion-in-your-app/ | vérifié (date d'effet : non vérifiée) |
| A8 | Mise en vente manuelle, automatique ou programmée ; attente en « Pending Developer Release » | https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option | vérifié (résumé) |
| A9 | Numéro de version supérieur au précédent | https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/ | **non vérifié** (la page dit « incremental ») |
| A10 | Informations pour la revue : identifiants de démonstration valides à la soumission | https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review | vérifié |
| A11 | Conformité export : rôle de `ITSAppUsesNonExemptEncryption` | https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations | **non vérifié** (page non chargée) |
| A12 | Manifestes de confidentialité des SDK tiers | https://developer.apple.com/documentation/bundleresources/privacy-manifest-files | **non vérifié** (page non chargée) |
| G1 | Niveau d'API cible : 36 pour les mises à jour depuis le 31/08/2026 (le projet cible 36) | https://support.google.com/googleplay/android-developer/answer/11926878 | vérifié |
| G2 | Pages mémoire de 16 Ko : à partir du 01/02/2027, plus de mise à jour sans compatibilité (apps avec bibliothèques natives ciblant l'API 35 ou plus) | https://developer.android.com/guide/practices/page-sizes | vérifié ; conformité de notre bundle **non vérifiée** |
| G3 | Sécurité des données : formulaire obligatoire, à tenir exact | https://support.google.com/googleplay/android-developer/answer/10787469 | vérifié (conséquences : résumé) |
| G4 | Contenu de l'app : politique de confidentialité, annonces, identifiants de connexion pour la revue, public cible, classification, formulaire des autorisations | https://support.google.com/googleplay/android-developer/answer/9859455 | vérifié |
| G5 | Déclaration « applis de santé » : toutes les apps publiées, y compris sans fonction de santé | https://support.google.com/googleplay/android-developer/answer/14738291 | vérifié |
| G6 | Suppression de compte : chemin dans l'app et lien web, déclarés dans la sécurité des données | https://support.google.com/googleplay/android-developer/answer/13327111 | vérifié |
| G7 | Déploiement par étapes : pourcentage choisi, non automatique, arrêt possible | https://support.google.com/googleplay/android-developer/answer/6346149 | vérifié |
| G8 | Publication gérée : sans elle, les changements approuvés sont publiés automatiquement | https://support.google.com/googleplay/android-developer/answer/9859654 | vérifié |
| G9 | Classification du contenu (questionnaire IARC) : sans elle, l'app est retirée | https://support.google.com/googleplay/android-developer/answer/9898843 | vérifié |
| G10 | Captures : 2 au moins, 320 à 3 840 px par côté ; image de présentation 1024×500 ; icône 512×512 | https://support.google.com/googleplay/android-developer/answer/9866151 | vérifié |
| G11 | Test fermé de 12 testeurs pendant 14 jours : comptes personnels créés après le 13/11/2023, pour obtenir l'accès à la production | https://support.google.com/googleplay/android-developer/answer/14151465 | vérifié ; la page ne dit rien d'une app déjà en production |
| G12 | `versionCode` croissant à chaque mise à jour ; notes de version de 500 caractères au plus | https://support.google.com/googleplay/android-developer/answer/9859152 et https://support.google.com/googleplay/android-developer/answer/9859348 | vérifié |
| G13 | API de publication : `completed` sert tous les utilisateurs, `inProgress` une fraction | https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks | vérifié |
| G14 | Politique de confidentialité dans la fiche et dans l'app | https://support.google.com/googleplay/android-developer/answer/9888076 | vérifié |

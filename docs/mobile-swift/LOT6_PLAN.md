# Plan du lot 6 — soumettre l'app Swift à l'App Store, publier Android à part

> Préparé le 24 novembre 2026 sur `lot6/preparation` (base `main` `f6e6be49`). Décisions et sources
> officielles : `docs/mobile-swift/DECISIONS_LOT6.md` (les renvois A1…A12 et G1…G14 pointent vers son
> tableau des sources). Mode d'emploi de la soumission : `docs/mobile-swift/APP_STORE.md`.
> Rien n'a été publié, soumis ni déclenché pour écrire ce plan.

## 1. Où on en est

| Question | Réponse au 24/11/2026 |
|---|---|
| Peut-on soumettre l'app Swift aujourd'hui ? | Non. Quatorze ports sont en attente sur `main` : `recovery` au lot 1, onze au lot 4, deux au lot 5. La garde `lots` exige les cinq listes vides et refuse le build 31 et tout build fait depuis `main`. |
| Que manque-t-il côté code ? | Le câblage de `recovery` (réinitialisation native du mot de passe, ci-dessous), la clôture des lots 4 et 5, une CI iOS verte sur le commit du build, puis un nouvel envoi TestFlight (build 32 ou plus). Le reste du chemin est écrit et testé sur cette branche. |
| Que manque-t-il côté consoles ? | Les saisies de la fondatrice dans App Store Connect (§3). |
| Peut-on publier Android aujourd'hui ? | Pas avant le merge de cette branche : sur `main`, le mode `native` construit et soumet aussi la coquille iOS. Ensuite, par un build natif 1.0.8 (25) ; pas par OTA (§5). |

## 2. Périmètre « Lot 6 » du plan général : état de chaque élément

Plan §5 « Lot 6 », l.225 à l.234.

| Élément du plan | État | Où |
|---|---|---|
| `config/mobile-release.json` scindé par plateforme (iOS 2.0.0, Android 1.0.x) | **fait** | `config/mobile-release.json`, `scripts/mobile/release-config.mjs` ; iOS : plancher de build 32 |
| `mobile-delivery.yml` : job iOS en `xcodebuild archive` du projet Swift | **fait autrement** (D2) | l'archive Swift reste dans `ios-native-testflight.yml` ; `mobile-delivery.yml` ne livre plus qu'Android |
| `check-mobile-build-alignment.mjs` pointé vers le nouveau projet | **fait** | Android ↔ `build.gradle`, iOS ↔ `ios-native/Config/Base.xcconfig`, coquille iOS gelée |
| `delivery-plan.mjs` : `ios-native` dans les chemins natifs, aucun diff `ios-native` en mode ota | **fait** | plus : iOS refusé dans tous les modes, OTA refusée sur le runtime 24 (D5) |
| `release-state.mjs` : tags scindés sans exiger les deux | **fait** | D4 |
| Captures iPhone et iPad refaites depuis l'app Swift | **à faire** | tranche T5 |
| App Privacy recalculée | **à faire** (fondatrice) | §3, action 4 ; base : `ios-native/Jolene/PrivacyInfo.xcprivacy` (22 types de données) |
| Notes de version annonçant la reconnexion et Face ID | **fait, à valider** | `config/mobile-release-notes-ios.txt` (D7) |
| Notes pour la revue | **fait**, validé par Claude sur délégation de Gabrielle (26/11/2026) ; comptes de revue **à vérifier** (fondatrice) | §3, action 3 ; bloc `config/ios-review-notes-2.0.txt`, écrit en tête des notes par la lane, fiche de vérification copiée de 1.0.7 si la 2.0.0 n'a pas de compte de démonstration (`APP_STORE.md`) |
| Écran d'accueil après la mise à jour | **à faire** | aucun écran de ce type dans `ios-native/` ; tranche T6 |
| Déploiement progressif sur 7 jours | **fait** | lane `ios submit_native`, `phased_release: true` (A3) |
| Suivi par `mobile-store-status.yml` | **fait** (existant) | lit l'état de la version et de la publication progressive, en lecture seule |
| Bêta externe, 14 jours de bêta (lots 3 et 4) | **abandonné** sur décision du 24/11 | D1 |
| **Prérequis de soumission : réinitialisation native du mot de passe (`recovery`)** | **manquant**, sans tranche | `DemoWorldTests.portsEnAttenteLot1 = ["recovery"]` ; voir ci-dessous |

**Manque connu, bloquant pour la soumission : `recovery`.** La réinitialisation native du mot de passe
(« Mot de passe oublié ? » sur la connexion, `SupabaseRecoveryGateway`, `ResetPasswordScreen`,
quarantaine de la session de récupération) est absente de l'app Swift : `UnwiredRecoveryPort` dans les
deux mondes, aucun « Mot de passe oublié ? » sous `ios-native/Jolene`. Reste de L1-T10, elle n'a de
tranche ni au lot 1 ni au lot 3 (`DECISIONS_LOT3.md`, « À planifier ») ; son préalable était fixé
« avant TestFlight externe », étape que D1 supprime. Or `config/mobile-release-notes-ios.txt` annonce à
tous les utilisateurs une reconnexion par mot de passe : sans réinitialisation native, celui qui l'a
oublié passe par le site. La garde `lots` exige les cinq listes vides (revue M2 de #1177) et refuse donc
toute soumission tant que `recovery` n'est pas câblé. Deux issues : câbler `recovery` dans une tranche
dédiée avant la soumission (recommandé), ou une décision écrite de la fondatrice dans `DECISIONS_LOT6.md`
qui l'accepte, suivie d'une PR qui modifie la garde. Le code Swift n'est pas modifié par cette branche.

Critères de sortie du plan (l.228 à l.234) :

| Critère | État |
|---|---|
| Garde Apple 4.2 écrite et respectée | **écrite** (gardes `apple-4.2` et `lots`, rejouées sur la source du build, et `ci-ios` : CI de l'app Swift verte sur ce commit) ; respectée à chaque soumission |
| Garde fastlane : version > 1.0.7, build > 24, `uses_non_exempt_encryption = false` | **fait** (garde `build`, lane, `ios_review_submission.rb`) |
| AASA inchangée | **fait** : aucun changement de `public/.well-known/apple-app-site-association` depuis le 07/09/2026, antérieur à 1.0.7 (24) |
| Liens universels vérifiés sur le build de production (reset, invitation, PSC, Stripe Connect) | **à faire**, sur iPhone, avec le build à soumettre — non vérifié |
| Push de production reçu sur un token enregistré par 2.0.0 | **à faire**, sur iPhone — non vérifié |
| Publication progressive non interrompue, crash-free ≥ 99,5 %, taux de reconnexion suivi | **après la mise en vente** ; exige le secret `SENTRY_DSN_IOS`, absent aujourd'hui |
| Retour arrière écrit et testé une fois | **écrit, non testé** (T7 ; écart, D6) |
| Aucune soumission automatique | **fait** (tests de `ios-native-app-store.yml`) |

## 3. Ce que seule la fondatrice peut faire dans App Store Connect, dans l'ordre

Le code ne fait aucune de ces saisies. Le workflow de soumission ne touche que le champ « Nouveautés ».

| # | Action | Pourquoi | Source |
|---|---|---|---|
| 1 | Créer le secret GitHub `SENTRY_DSN_IOS` (hors App Store Connect, mais avant le build à soumettre) | sans lui, l'app part sans Sentry et le taux de crash de la publication progressive n'est pas mesurable | `SENTRY_IOS.md` |
| 2 | Fiche de la version 2.0.0 : vérifier nom, sous-titre, description, mots-clés, URL de support et de confidentialité ; adapter le texte promotionnel si besoin | la version reprend la fiche de 1.0.7 ; la description doit décrire l'app livrée | A1 (2.3) ; textes de référence : `docs/STORE_METADATA_FR.md` |
| 3 | Notes pour la revue et compte de démonstration : mettre à jour les notes (app réécrite en natif ; rôles administrateur et groupe renvoyés vers jolene.app ; un pointage réel exige d'être sur place) ; vérifier que les comptes de revue soignant et établissement se connectent en production et montrent des missions, un contrat et une présence | Apple exige des identifiants valides au moment de la soumission, un backend actif et la description précise des nouveautés | A1 (2.1(a), 2.3.1(a)), A10 |
| 4 | Confidentialité de l'app : relire les réponses contre le manifeste de l'app Swift (22 types de données, aucune donnée de pistage) et corriger les écarts avec la coquille | réponses exigées pour toute mise à jour, à tenir exactes | A4 |
| 5 | Classification : vérifier que le questionnaire à cinq paliers est rempli | une app non classée ne se publie pas ; les nouvelles questions étaient à remplir avant le 31/01/2026 | A5, A6 |
| 6 | Captures : remplacer les captures iPhone et iPad par des captures de l'app Swift | les captures doivent montrer l'app en usage ; format iPad exigé puisque l'app tourne sur iPad | A1 (2.3.3), A2 |
| 7 | Conformité export : rien à saisir si le build affiche « false » ; la garde `build` le vérifie | — | A11 (non vérifié) |
| 8 | Lancer la soumission : Actions → « iOS Swift — soumission App Store » → d'abord en mode `verifier` (gardes seules), puis en mode `soumettre` avec le numéro du build, la phrase de confirmation et le mode de publication | geste manuel décidé le 24/11 | D1, `APP_STORE.md` |
| 8 bis | Propriétaire du dépôt : créer un environnement GitHub restreint à `main` et y placer les secrets App Store Connect (réglage hors code, non fait) | sans lui, « depuis `main` seulement » n'est garanti que par le fichier du workflow | `APP_STORE.md`, « Secrets et droits » |
| 9 | Si la mise en vente est « manuelle » : cliquer « Release this version » après l'approbation | la version attend sinon en « Pending Developer Release » | A8 |
| 10 | Pendant les sept jours : suivre Sentry et `mobile-store-status.yml` ; mettre la publication progressive en pause si besoin (30 jours au plus) | sans bêta, c'est le premier signal d'usage réel | A3 |

## 4. Ce que seule la fondatrice peut faire dans Play Console, dans l'ordre

| # | Action | Pourquoi | Source |
|---|---|---|---|
| 1 | Publication gérée : décider si les changements approuvés attendent un clic ou partent seuls | sans publication gérée, tout part dès l'approbation | G8 |
| 2 | Contenu de l'app : vérifier politique de confidentialité, identifiants de connexion pour la revue (jusqu'à cinq jeux, consignes pour un code à usage unique), public cible, annonces, classification IARC | déclarations obligatoires, à tenir à jour | G4, G9, G14 |
| 3 | Sécurité des données : relire le formulaire, dont les questions de suppression de compte (chemin dans l'app et lien `https://jolene.app/supprimer-mon-compte`) | obligatoire et à tenir exact | G3, G6 |
| 4 | Déclaration « applis de santé » : vérifier qu'elle est remplie | exigée de toute app publiée | G5 |
| 5 | Fiche : captures téléphone (2 au moins) et tablette, image de présentation, si l'interface a changé depuis le 5 octobre | — | G10 |
| 6 | Après le run `native` : suivre la revue, puis publier si la publication gérée est active | la lane publie à 100 % dès l'approbation (`completed`) ; un déploiement par étapes se règle ici | G7, G13 |

Sans objet : le test fermé de 12 testeurs pendant 14 jours ne concerne que l'obtention de l'accès à la
production pour un compte personnel récent ; l'app est déjà en production (G11, déduction : la page ne le
dit pas en toutes lettres).

Non vérifié : la compatibilité du bundle Android avec les pages mémoire de 16 Ko, exigée pour les mises à
jour à partir du 01/02/2027 (G2). À lire dans Play Console (explorateur d'app bundle) après le prochain
build.

## 5. Publier Android aujourd'hui

**Par OTA : impossible.** Trois raisons, chacune suffisante :

1. le runtime 24 est aussi celui de la coquille iOS 1.0.7 (24) encore installée (D5) ;
2. depuis le tag `mobile-native-android-24`, `package.json`, `package-lock.json`, `vite.config.ts` et
   `scripts/mobile/` ont changé : la règle existante exige un build store ;
3. 183 commits ont été mergés depuis, dont la plupart sans label `mobile:ota`, et beaucoup hors de
   `src/`, `public/`, `tests/`, `e2e/`, `docs/`.

**Par livraison native : possible après ces étapes.**

| # | Étape | Qui |
|---|---|---|
| 1 | Merger cette branche (sinon le mode `native` construit et soumet aussi la coquille iOS, et attend les deux) | PR, CI, revue |
| 2 | PR de release : `android.marketingVersion` 1.0.8 et `android.buildNumber` 25 dans `config/mobile-release.json` ; `versionCode 25` et `versionName "1.0.8"` dans `android/app/build.gradle` ; texte `fastlane/metadata/android/fr-FR/changelogs/25.txt` (500 caractères au plus, G12) | code + texte validé par la fondatrice |
| 3 | Recette Android sur appareil du site tel qu'il est sur `main` (183 commits depuis le dernier bundle livré) | `CLAUDE.md`, recette frontend |
| 4 | Sur le commit exact de `main` : `validate-pr`, `playwright-e2e`, `lighthouse`, `android-native-recette` verts sur l'événement `push`, Vercel vert, déploiement Supabase vert et à jour | CI ; `mobile-delivery.yml` mode `check` le confirme |
| 5 | Lancer `mobile-delivery.yml` mode `native` depuis `main` | fondatrice |
| 6 | Play Console (§4) | fondatrice |

Ce qui peut encore gêner : `main` avance souvent, et le planificateur refuse un commit qui n'est plus la
tête de `main` ; le contrôle Playwright est instable (relancer, ne pas contourner). Les secrets Android
existent sous leurs noms attendus ; leur validité n'a pas été vérifiée.

## 6. Tranches

Courtes, dans l'ordre. T1 à T4 sont sur cette branche.

| Tranche | Contenu | État | Preuve |
|---|---|---|---|
| T1 | Décisions et plan du lot 6, sources officielles | fait | ce document, `DECISIONS_LOT6.md` |
| T2 | Scission : configuration, tags, planificateur, OTA Android seul, alignement des versions, `mobile-delivery.yml` Android seul | fait | `tests/node/mobile-delivery-plan.node.mjs` |
| T3 | Soumission App Store : `ios-native-app-store.yml`, gardes, lane `submit_native`, notes de version | fait | `tests/node/ios-native-app-store.node.mjs` ; provenance et source rejouées à blanc sur le build 31 |
| T4 | Documentation de livraison à jour (`MOBILE_DELIVERY.md`, `TESTFLIGHT.md`, `APP_STORE.md`, renvois du plan général) | fait | — |
| T5 | Captures App Store depuis l'app Swift en mode démo (détail ci-dessous) | à faire | PNG contrôlés en dimensions |
| T6 | Écran d'accueil après la mise à jour (reconnexion, Face ID), sans texte juridique nouveau | à faire | XCUITest démo |
| T7 | Retour arrière iOS : procédure ci-dessous, à tester une fois ou à abandonner | écrit, non testé | — |
| T8 | Câblage de `recovery` (lot 1), clôture des lots 4 et 5, CI iOS verte sur le commit, envoi TestFlight du build à soumettre (soumis dans les 14 jours), recette sur iPhone (liens universels, push de production) | dépend de `recovery` et des lots 4 et 5 | `RECETTE_DEVICE_LOT4.md`, `RECETTE_DEVICE_LOT5.md` |
| T9 | Soumission (geste de la fondatrice), puis suivi de la publication progressive | après T8 et §3 | tag `mobile-native-ios-N`, `mobile-store-status.yml` |
| T10 | PR de release Android 1.0.8 (25), puis livraison native (§5) | indépendant d'iOS | tag `mobile-native-android-25` |

### T5 — Captures App Store (à faire)

Non livré par cette branche : un test XCUITest ne se compile ni ne s'exécute sans `xcodebuild`, et le
job ne peut pas être lancé tant que son workflow n'est pas sur `main`. Le livrer sans l'avoir vu tourner
aurait été une promesse, pas une preuve. Ce qu'il faut faire :

- **Une cible de test à part** (par exemple `JoleneCapturesUITests`, avec son scheme), déclarée dans
  `ios-native/project.yml`. Pas une classe de plus dans `JoleneUITests` : l'éclat « socle » de
  `ios-swift-ci.yml` exécute toute classe qu'il n'exclut pas nommément, et la garde
  `tests/node/ios-swift-ci-eclats.node.mjs` refuse toute exclusion autre que les classes STAGING et
  celles des autres éclats. Une cible séparée ne touche ni ce workflow ni cette garde.
- **Un workflow lancé à la main** (`workflow_dispatch`), qui lance l'app avec `-JOLENE_MODE demo` et
  enregistre les captures en pièces jointes du résultat de test.
- **Deux simulateurs** aux dimensions acceptées (A2) : un iPhone à grand écran avec Dynamic Island pour
  du 1320 × 2868 (par exemple iPhone 17 Pro Max) et un iPad 13 pouces pour du 2064 × 2752. La chaîne de
  CI n'utilise aujourd'hui que « iPhone 17 » et « iPad (A16) » : le second n'est pas un 13 pouces, et
  l'acceptation du format du premier n'a pas été vérifiée. La présence des deux autres simulateurs sur
  le runner est à vérifier.
- **Un contrôle des dimensions** des PNG (`mobile-native/scripts/png-dimensions.mjs`, déjà repris par la
  CI) avant de les proposer au téléversement.
- **Des écrans qui montrent l'app en usage** (A1, 2.3.3) : tableau de bord, recherche, détail d'une
  mission, Mes missions, pointage, revenus ; pas l'écran de connexion.

Le téléversement des captures reste une saisie de la fondatrice dans App Store Connect (§3, action 6).

### T7 — Retour arrière iOS (écrit, non testé)

Si 2.0.0 doit être retirée après sa mise en vente :

1. mettre la publication progressive en pause dans App Store Connect (30 jours au plus, A3) : les
   appareils non encore mis à jour restent en 1.0.7 ;
2. corriger en Swift et soumettre une 2.0.1 par le chemin normal : c'est la voie par défaut ;
3. en dernier recours, republier la coquille Capacitor : restaurer le job iOS de `mobile-delivery.yml` et
   la lane `ios submit` depuis le commit `f6e6be49`, donner à `ios/` une version supérieure à la version
   en vente et un build supérieur au dernier build d'App Store Connect, mettre à jour la constante
   `COQUILLE_IOS_FIGEE`, puis lancer la livraison. Il faut aussi défaire, dans la même PR, ce qui
   verrouille aujourd'hui iOS sur l'app Swift : `release-config.mjs` (qui exige `ios.runtime = swift` et
   interdit `ios.buildNumber`), le refus d'iOS par le planificateur (`plateformeMobileDelivery` dans
   `delivery-plan.mjs`) et `release-state.mjs` (pour iOS : aucune réservation de source, numéro lu dans
   `RELEASE_BUILD_NUMBER`, au moins `ios.minimumBuildNumber`). Les utilisateurs devraient se reconnecter une seconde fois. Cette voie n'a jamais été exécutée
   depuis la scission, et ces retraits ne sont pas testés.

## 7. Écarts avec le plan général

| Écart | Raison |
|---|---|
| `mobile-delivery.yml` ne porte pas l'archive Swift | l'envoi TestFlight existe avec ses gardes ; un seul chemin de signature (D2) |
| Soumission d'un build déjà sur TestFlight, pas d'un binaire construit au moment de soumettre | le build soumis est celui qui a été traité par Apple et recetté sur appareil |
| Build minimal 32 au lieu de « 25 ou plus » | 25 à 31 sont pris par TestFlight et précèdent la clôture des lots 4 et 5 |
| Bêta externe et critère des 14 jours abandonnés | décision du 24/11 (D1) |
| OTA refusée sur le runtime 24 | elle atteindrait la coquille iOS encore installée (D5) |
| Retour arrière « 1.0.8 (26) » non tenu | numéros pris, version à dépasser, procédure non testée (D6) |
| Version Android inchangée dans cette branche | la montée de version est une PR de release avec son texte (D10) |

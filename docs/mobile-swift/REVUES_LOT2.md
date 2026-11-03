# Revues fraîches B8 — lot 2 (app iOS Swift native)

Rapports des revues à contexte vierge (CLAUDE.md, B8) des tranches du lot 2, consignés par l'intégrateur sur
`feat/ios-lot2`. Une section par tranche, dans l'ordre d'intégration. Les rapports sont reproduits tels que
rendus ; seuls les niveaux de titre sont décalés pour tenir sous le titre de la tranche.

## L2-TL

### Revue fraîche B8 — L2-TL

**Verdict : CLÔTURABLE.** Aucun bloquant ni majeur. Il reste 7 mineurs, dont le n°3 est à traiter avant d'ouvrir la PR.

#### Ce que j'ai relu
- `git diff origin/feat/ios-lot1...origin/lot2/l2-tl` en entier (8 commits, de d041c49c à 54aab54a, 8 fichiers) :
  - `TextesWeb.swift` et `LibellesWeb.swift`, avec leurs tests Swift ;
  - la garde `check-textes-juridiques-ios.mjs` et `textes-web-ios-rendus.json` ;
  - la suite Node ;
  - `validate-pr.yml`.
- Le cadre : LOT2_PLAN v2 §3 TL, §1.2 et §7 (Q4, Q5, Q9, Q15, Q18, Q19), corrections 5, 12-15 et 21 ; LOTS_2_5_DECISIONS ; CLAUDE.md (HARD STOP n°4, B9) ; PRINCIPES.md ; DECISIONS_LOT2 de T0.

#### Comment j'ai vérifié
- Lecture seule : aucun build, aucun test lancé, aucun appel MCP.
- Aucune requête SQL : la tranche ne touche ni `supabase/` ni `src/`, donc il n'y avait aucune définition live à comparer.

#### Ce qui est vérifié
- **Textes identiques au web.** J'ai comparé chaque constante de TextesWeb.swift à sa ligne dans les 12 fichiers web. Les espaces JSX, apostrophes droites et courbes (’), emoji et `\u{FE0F}` du ⚠️ sont identiques. Je n'ai trouvé aucune reformulation. Les huit textes tutoyés sont gardés tels quels et signalés.
- **Couverture du blueprint v2 §3 TL.** Tous les textes listés sont présents, y compris :
  - DocumentsSoignant l.112 (art. 441-7 du Code pénal) ;
  - les trois variantes du pied de page l.831-837 ;
  - SignerContratOtp l.242-246, l.288 et l.326-327 ;
  - CertificatSignaturePage l.214-215 ;
  - SectionPreferences l.129-136, l.140 et l.161.
- **Assemblages.** J'ai confronté chaque fonction au rendu React :
  - `piedDePage` (`{!texteEmployeur && …}`) ;
  - `documentOfficielFige` (empreinte 8…4, rien si elle est vide) ;
  - `message` (`MESSAGES_ERREUR[code]`, puis `error || fallback`, puis le défaut) ;
  - `tentativesRestantes` (rien à partir de 5, message des tentatives épuisées à 0 ou en dessous) ;
  - le compte à rebours (paliers 48 h / 24 h) ;
  - `smsRestants`, `codeEnvoye`, `minuteur`, `infobulleRenvoi`, `messageRelance` (`??`) ;
  - `libelleStatut` ;
  - le certificat.

  Tous sont conformes. Les 26 zones ancrent bien les conditions et les séparateurs.
- **Verrou Q9.** Aucun texte de délai de contestation n'est repris. Les ancres sont retrouvées par leur texte, et tout texte qui associe contestation ou litige et délai est refusé dans les deux fichiers. C'est conforme à §1.2, à la correction 14 et à §7 Q9.
- **Workflow.** La garde est ajoutée à l'étape « Garde de livraison mobile » du job Typecheck + build, sans filtre de chemins.
- **Hors périmètre.** Aucun changement web, aucune migration, aucun secret.
- **Compatibilité avec les autres branches.**
  - Le merge d'essai avec origin/lot2/l2-t0 est propre (merge-tree).
  - Depuis la base, feat/ios-lot1 n'a modifié aucun fichier surveillé : sources web, Info.plist, project.yml.
- **Tests.** Ils testent réellement :
  - mutation rejouée sur chaque constante et sur chaque texte web ;
  - mutation de chaque zone ;
  - décalages simples et doubles, avec `--corriger-lignes` ;
  - permutations dans les dictionnaires ;
  - verrous Q9 et Info.plist.

#### Constats mineurs
1. **La garde accepte un texte qui n'est pas le bon** (`check-textes-juridiques-ios.mjs` l.619-623 et l.494-497).
   - Constat :
     - Une phrase longue unique, prise n'importe où dans le même fichier, est classée « décalée » sans regarder le décalage des voisines. Exemple : `Contrat.originalIndisponible` (annotée l.636) remplacée par le texte de ContratMission l.629 donne un simple avertissement, et `--corriger-lignes` réécrirait l'annotation.
     - Un littéral non affiché compte comme un texte : `Certificat.dateHeure` remplacée par « text-muted-foreground » (l.128) est « exacte ».
   - À faire : n'accepter une phrase longue comme appui que si son décalage concorde avec celui des voisines déjà situées ; exclure className, key, type, etc. des unités ; ajouter un test « remplacé par un autre texte du même fichier » qui doit rougir.
2. **Des zones contiennent des lignes de pure présentation** (className, disabled), environ 12 sur 26.
   - Constat : une PR web qui ne touche que le style rougit le check requis, avec un message qui renvoie au HARD STOP. C'est fréquent ici (migrations Y2K).
   - À faire : retirer ces attributs à la normalisation, ou préciser dans le message que recopier une zone n'est pas une PR HARD STOP.
3. **La liste à faire valider par Gabrielle est périmée.**
   - Constat : `tl/liste.md` date du 2/11 à 23:32 (147 lignes, sans nature ni rendus). Le rapport donne aussi des décomptes incohérents (93, 147, 117). La liste réelle à 54aab54a compte 117 textes HARD STOP, 44 libellés et 53 rendus.
   - À faire : régénérer le corps de PR avec `--liste` sur le commit final, avant d'ouvrir la PR.
4. **Classement incohérent** (LibellesWeb.swift l.48-58).
   - Constat : « Contester cette présence » et « Envoyer la contestation » ouvrent un litige mais restent hors HARD STOP, alors que les boutons « Signer » y sont. L'impact est faible, puisque T5b est HARD STOP de toute façon.
   - À faire : les passer dans TextesWeb, ou préciser le critère.
5. **Détection hors TL** (l.1042).
   - Constat : tout littéral sans espace est ignoré. « Consentement » ou « RGPD » écrit seul dans un fichier du lot 2 n'est pas détecté.
   - À faire : ne dispenser que les littéraux qui ont la forme d'un identifiant (snake_case, kebab-case, MAJUSCULES_).
6. **Lien « rendu asserté » faible** (test Node l.299-304).
   - Constat : il vérifie seulement que le texte apparaît comme littéral dans le fichier de test Swift, pas qu'il soit le résultat de l'appel annoncé. Deux détails aussi :
     - l'appel « <64 caractères hexadécimaux » ne correspond pas à la valeur de test (…wxyz) ;
     - le test de vouvoiement ne voit pas l'impératif tutoyé (« Demande… »).
7. **Inventaire des surfaces non couvertes à compléter pour T9a.**
   - Constat : il manque la section « Signatures » de ContratMission l.666-699, « Chargement du certificat… » (CertificatSignature l.69) et le « 'à' » des formats de date.

#### Note de process (sans effet sur le verdict)
Le blueprint autorise le merge sur CI verte et une revue B8 clôturable, et la règle 3 du cadre ne cite pas TL parmi les PR B9. En revanche, CLAUDE.md B9 classe « légal / mentions / consentement » parmi les catégories qui exigent un go humain. La file de merge doit trancher explicitement. Dans tous les cas, la validation écrite de Gabrielle sur la liste régénérée reste nécessaire avant de déclarer T4b, T7, T9a et T9b livrées. Q9 et T5b attendent toujours son go.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-03)

- Branche créée depuis `origin/feat/ios-lot1` (`3c0eed95`, avec T3, T4a et T8 du lot 1 ; `origin/feat/ios-lot2`
  n'existait pas), puis `git merge --no-ff origin/lot2/l2-tl` (`54aab54a`), commit de fusion `759229e1`.
- Aucun conflit textuel : TL ne touche que ses 8 fichiers, dont `validate-pr.yml`, que le lot 1 n'a pas modifié
  depuis la base commune `c509224a`.
- Constats mineurs 1 à 7 : non traités par l'intégration (aucun ne casse une vérification). Ils restent à la
  charge de la tranche TL (correctif) ou de la tranche suivante qui touche le fichier. Le n°3 (liste `--liste`
  régénérée sur le commit final) reste un préalable à l'ouverture de la PR, et la question B9 de la note de
  process reste à trancher par la file de merge.

## L2-T2

### Revue fraîche B8 — L2-T2

**Verdict : CLÔTURABLE.** Aucun constat bloquant ni majeur, huit mineurs.

**Ce qui a été relu :** tout le diff `origin/feat/ios-lot1...origin/lot2/l2-t2`, soit les commits `8ee0be9d` (tests d'abord) et `f2242c1d` (ports Swift), 26 fichiers.

**Méthode :** lecture seule. Je n'ai lancé ni build, ni test, ni appel MCP. Il n'y avait rien à comparer au live, car la tranche ne touche ni le backend ni le SQL. Chaque port Swift a été confronté ligne à ligne à son module web sur la même base : `synthese-presence-mission.ts`, `presencesSoignantUi.ts`, `documentUpload.ts`, `documents.ts`, `contratMissionUi.ts`, `signatureSmsStagingAdmission.ts`, et `Countdown72hSignature.tsx` l.79-84. J'ai aussi échantillonné les vecteurs golden.

#### Conformité au cadre
- **Périmètre** : seuls `JoleneCore`, l'exporteur et `ios-swift-ci.yml` sont touchés. Aucun fichier `src/`, `supabase/` ou `docs/` ne bouge, et les golden des lots 0 et 1 sont inchangés. Le seul fichier des lots précédents modifié est `RulesGoldenTests.swift` : il gagne six noms (13 au total) et `rejouerAsync`.
- **Décision « Lot 2 T2 » de `LOTS_2_5_DECISIONS.md` respectée** : les deux règles qu'extrait W1 sont renvoyées à T2b. Le renvoi est commenté à cinq endroits, et `ListesPresences.swift` est absent comme prévu. Il y a 6 fichiers golden au lieu des 8 du blueprint, conformément à cette décision.
- **Filtres de chemins de la CI** : les blocs `pull_request` et `push` couvrent les six modules et leurs dépendances (`disponibilite-pointage.ts`, `constantes.ts`, `profession-hierarchy.ts`, déjà présents).
- **Comptes** : 62 + 40 + 449 + 186 + 154 + 65 = 956 vecteurs. Les cas vitest des cinq modules qui en ont sont repris ; `signatureSmsStagingAdmission` n'a pas de vitest et n'est couvert que par une grille.
- **Fuseau** : l'exporteur force `TZ=Europe/Paris`. La date legacy `2026-11-02T11:30:00` est donc lue comme 10:30Z, comme le fait `instantJolene`.
- **B9 / HARD STOP n°4** : aucun. Les seuls textes affichés sont les sept messages de `documentUpload.ts`, vérifiés verbatim un par un (dont l'apostrophe typographique de « n’est »). Les annotations `// source:` pointent les bonnes lignes : 135, 139, 147, 154, 166, 174 et 180.
- **Littéraux sensibles** : rien qui ressemble à une clé (`eyJ…`, `sb_secret_`, `sk_`, SID Twilio, téléphone). Les refs de projet présentes sont publiques et déjà dans l'allowlist. Aucun littéral `"fn_…"` n'apparaît dans les nouvelles sources Swift.

#### Exactitude des ports (vérifiée ligne à ligne)
- **Synthèse de présence** : mêmes filtres que le web (`Boolean(fin)`, pauses exclues, types inconnus ignorés), tri stable par début, fin du planning donnée par le dernier créneau prévu, borne illisible ⇒ `nil` et planning non terminé. `formatDureeMinutes` reproduit le `%` et le `Math.round` JavaScript, y compris « 1h60 » et « -1h-30 ».
- **Historique des présences** : `mission_id` nuls ou vides ignorés, établissement nul quand l'identifiant est vide, `pointage_depart_le` pris sur le dernier segment trié par début. Les vecteurs GPS non numériques sont refusés comme avec `typeof`.
- **Classement des documents** :
  - classement MIME/extension, recherche de l'extension, signatures sur 12 octets (WebP ≥ 12) ;
  - ordre des contrôles identique : taille, format, type autorisé, lecture, signature ;
  - nom de fichier assaini : NFD, suites de caractères fusionnées, tirets de bord, 80 caractères ;
  - `trim` JavaScript exact (U+FEFF, Zs).
- **Contrats** : `contientVariablesContratNonRendues` est équivalent à la regex `/\{\{\s*[^}]+\s*\}\}/` (démonstration : le premier `}` doit être doublé). Les deux autres règles sont alignées sur le web.
- **Admission OTP de recette** : contrôles stricts sur les types JSON grâce à `ValeurJSON`, `Number.isInteger`, bornes de 60 min et 10 min, otp borné par la capacité, `!= null` hors validation.
- **Règles natives** : `PayloadQR` et le compte à rebours 72 h sont conformes à §7 Q3 et à la correction 13. Pour le compte à rebours, un `cree_le` illisible vaut délai expiré, en échec fermé ; les tests vérifient les seuils 48/24 h et l'arrondi.

#### Constats mineurs (non bloquants)
1. `scripts/mobile/export-golden-vectors.mjs:1764-1774` : `clesExactes` ne s'applique pas au résultat de l'admission, contrairement à ce qu'annonce le résumé. → Ajouter `clesExactes('signature-sms-staging-admission', r, ['expiresAt','canSend','canValidate','otpExpiresAt'])` quand `r !== null`.
2. `AdmissionRecette.swift:36-48` : la garde compare des chaînes d'URL exactes. Une URL configurée avec une barre finale passe `JoleneEnvironment`, qui ne vérifie que l'hôte, mais l'admission la refuse sans aucun signal. → En T8 : normaliser l'URL, ou ajouter une surcharge `JoleneEnvironment` (mode et hôte), avec un test « barre finale ».
3. `RulesAdmissionRecetteTests.swift:39` : le test fabrique lui-même `appels`. Le golden prouve le nombre d'appels et l'identifiant transmis, pas le nom de la RPC ni la clé `p_contrat_id`. → En T8, `SupabaseContratsGatewayTests` doit les vérifier sur la requête réelle.
4. `SynthesePresence.swift:57-61` : `Int(heures)` fait planter l'app si l'entrée est non finie (le web affiche « NaNhNaN »). → Garde `isFinite` avec un repli, et un test.
5. `ClassementDocument.swift:66/102` : écart non vectorisé. Le web lit la chaîne de prototypes (`photo.constructor` avec un MIME vide est classé SUPPORTED, puis refusé par « Ce type de fichier n’est pas autorisé ici. »). Le natif renvoie « Format non pris en charge… » ; le code de refus est le même. → Consigner l'écart comme assumé, ou corriger le web dans une PR séparée. Ne pas reproduire le bug.
6. `PayloadQRTests.swift:30-52` : l'écart Vision → `CIDetector`, limité à macOS, est justifié. → Il reste à le consigner dans le corps de PR et dans `DECISIONS_LOT2.md` (T0).
7. `AdmissionRecette.swift:6` : `AdmissionSignatureRecette` fait doublon avec `AdmissionOtp`, prévu par T1. → Un seul type à l'intégration T1/T8 (principe « État dérivé ») ; un typealias n'est acceptable qu'en transition.
8. Réutilisation : `triStableCroissant` (`SynthesePresence.swift:83`) duplique `DisponibilitePointage.triStable`, et `ValeurJSON` duplique le `JSONValue` des tests. → Mutualiser.

#### Reste à prouver par la CI
Je n'ai rien exécuté. Il faut un `ios-swift-ci.yml` vert sur trois jobs :
- **cœur** : export puis `git diff --exit-code` en Node 24 ;
- **packages** : `swift build --build-tests` et `swift test` avec `-strict-concurrency=complete` et 0 avertissement. C'est ce job qui confirmera l'absence d'avertissement de dépréciation de `CIDetector` sous macOS 26 et l'absence d'avertissement de concurrence sur les fermetures passées à `AdmissionRecette.lire` et `rejouerAsync` ;
- **interface** : `JoleneCoreTests` sur le simulateur, sur les trois formats.

La décision de merge reste soumise à cette CI et à la file sérielle de la session principale.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-03)

- `git merge --no-ff origin/lot2/l2-t2` (`f2242c1d`) après TL, commit de fusion `ada1de26`. Aucun conflit
  textuel : `RulesGoldenTests.swift`, `export-golden-vectors.mjs` et `ios-swift-ci.yml` n'ont pas été modifiés par
  le lot 1 depuis la base commune `c509224a`, et TL ne touche aucun fichier de T2.
- Point de jonction TL ↔ T2 vérifié : la détection « aucun texte juridique en dur hors TextesWeb.swift » de TL
  (`DOSSIERS_LOT2`) couvre désormais les dossiers `Pointage/`, `Documents/` et `Contrats/` que T2 crée sous
  `JoleneCore`. Elle passe : les sept messages de `documentUpload.ts` ne portent aucune marque juridique. Les
  messages de `ClassementDocument.swift` ne sont repris ni dans `LibellesWeb.swift` ni dans `TextesWeb.swift`
  (aucun doublon de source).
- Constats mineurs 1 à 8 : non traités par l'intégration (aucun ne casse une vérification). Ils restent à la
  charge de T2 (correctif) ou des tranches qu'ils nomment (T8 pour 2, 3 et 7 ; T0 pour 6).

## Vérifications après les deux fusions (intégrateur, 2026-11-03)

Exécutées en local sur `feat/ios-lot2` (Node 24.14.0 ; Swift 6.1.2 de Xcode 16.4 sur le poste, alors que la CI
utilise Xcode 26.4.1), sans écriture en production ni sur STAGING, sans Playwright ni dispatch de workflow :

- `node --test tests/node/*.node.mjs` : 1 790 tests, 0 échec, 0 ignoré. L'étape « Garde de livraison mobile » de
  `validate-pr.yml` (`mobile-delivery-plan`, `check-rpc-contracts`, `textes-juridiques-ios`) compte 130 tests verts.
- `node scripts/mobile/check-textes-juridiques-ios.mjs` : 117 textes HARD STOP et 44 libellés identiques au web,
  26 zones de rendu retrouvées.
- `node scripts/mobile/check-rpc-contracts.mjs` : 27 RPC, aucune dérive ; `--update` ne produit aucun diff.
- `node scripts/mobile/export-golden-vectors.mjs` (2 569 vecteurs) et `export-demo-fixtures.mjs` : aucun diff.
- `JoleneCore` : `swift build --build-tests -Xswiftc -strict-concurrency=complete` sans erreur ni avertissement ;
  `swift test -Xswiftc -strict-concurrency=complete` : 369 tests XCTest, 0 échec.
- `JoleneSupabase`, `JoleneDesign` et l'app ne sont touchés par aucune des deux tranches et n'ont pas été
  recompilés ici. Aucun des noms publics que TL et T2 ajoutent à `JoleneCore` n'apparaît dans ces cibles : il n'y
  a pas de collision de noms possible.
- Reste à prouver par la CI : le job « interface » d'`ios-swift-ci.yml` (simulateur, trois formats) et l'absence
  d'avertissement `CIDetector` sous macOS 26 (job « packages », Xcode 26.4.1).

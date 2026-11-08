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

## L2-T1

### Revue fraîche B8 — L2-T1

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur. Il reste 8 mineurs, de documentation et de durcissement. M1 et M2 sont à trancher avant T3.

#### Ce que j'ai relu
- **Le diff** : `git diff origin/feat/ios-lot2...origin/lot2/l2-t1-v2` en entier (6 commits, de 2dffa2ea à f24affb3 ; 37 fichiers, +4 623 / −25).
- **Le cadre** :
  - LOT2_PLAN v2 : §1.3, §2.1 à §2.8, §3 T1 et T3, §7 Q23 ;
  - LOTS_2_5_DECISIONS ;
  - DECISIONS_LOT2 et PRINCIPES sur la base ;
  - CLAUDE.md (HARD STOP n°4, B8 et B9).

#### Comment j'ai vérifié
- **Lecture seule** : aucun build, aucun test, aucun appel MCP. Le dump versionné `supabase/schema/public.sql` suffisait.
- **Le SDK** : supabase-swift v2.55.5 relu dans le checkout DerivedData.
- **Le web et le pilote** : `DocumentsSoignant.tsx`, `PointageRotatifSoignant.tsx`, `mobile-native/.../attemptJournal.ts` et `rpcOutcome.ts`.

#### Ce qui est vérifié
- **Les décodeurs filtrent bien.**
  - `ScanEnregistre` ne lit jamais `nouveau_code` ni `nouveau_hmac`, et exige `numero_scan`. Une réponse de refus restituée ne peut donc pas se décoder en succès.
  - `EtatPointage` ne lit ni `code_pointage_actif` ni `est_etab`. Il refuse `{error}` et l'absence de `nb_scans` ou `prochain_type_scan`, clés que `jsonb_build_object` émet toujours (l.35180-35190). Chaque segment est toléré séparément.
  - `ResumePresencesServeur` exige le booléen `pointage_effectue`, présent dans les deux formes de succès (l.48928, l.48939).
  - `PreuveScan` ne projette ni `code_saisi`, ni l'IP, ni les coordonnées, et lit `mission_id`.
  - `SignatureCertificat.colonnes` reprend exactement les 14 colonnes accordées par GRANT (l.86518-86570).
- **Exceptions métier.**
  - Les 14 messages du test correspondent mot pour mot au dump : l.55649, 55652, 55662, 55677, 55686, 55775, 55778, l.35867-35926 et l.1961 (P0001 par défaut).
  - L'ordre est respecté : `[CODE DU TRAVAIL]`, puis exceptions déclarées, puis `SupabaseErrorMapping`, qui reste inchangé.
  - « permission denied for » devient `.contract`. PGRST202 donne une seule requête.
  - Les statuts des stubs correspondent à la table de PostgREST (classes 40 et 57 → 500).
- **`appelerMutation` classe correctement les échecs.**
  - Dans le SDK (`PostgrestBuilder.swift` l.230-256), une erreur de décodage sur un 2xx, une `PostgrestError` à `code` optionnel et un `HTTPError` sont bien distincts. Aucun POST n'est rejoué (l.262-275).
  - Une erreur de décodage sur un 2xx est classée incertaine, ce qui est juste : le scan a été validé.
  - La double traduction est sans effet, car `map` laisse passer une `JoleneError` telle quelle.
  - L'exclusion de PGRST103, PGRST111 et PGRST112 est fondée : la réponse est construite après le COMMIT.
- **Journal de reçus.**
  - Les opérations sont sérialisées par l'acteur global ; l'écriture est relue, effacement compris.
  - Les échecs bloquent (fail-closed), sans réparation. `recuEnCours` et la succession des phases sont contrôlés.
  - Une panne à chaque étape (prepared, started, refused, stored) retombe toujours sur une relecture sûre.
  - Le test d'entrelacement distingue bien les deux cas : la sonde de l'auteur le montre rouge sans sérialisation.
- **Keychain.**
  - Services distincts, accès AfterFirstUnlockThisDeviceOnly, jamais synchronisé, aucun groupe d'accès.
  - Aucun `SecItemDelete` global dans les sources : la déconnexion ne purge que `app.jolene.session`.
  - `errSecDuplicateItem` est relu, et une valeur illisible n'est jamais réécrite.
- **Reçu de justificatif.**
  - La clé Storage reprend celle du web (l.372). Le nom assaini ne contient aucun point, donc jamais `..`.
  - Les bornes de l.53103-53116 sont reprises : points de code, et `btrim`, qui ne retire que les espaces.
  - Le `userId` est en minuscules (`SupabaseAuthGateway` l.97 et l.126), il satisfait donc le `LIKE v_uid::text`.
- **Ports.**
  - Les 5 champs sont additifs, les inits des lots 0 et 1 sont intacts, et `câblerLot2` est testé avec un port témoin, donc pas de façon tautologique.
  - `EcranNatif` gagne 3 écrans ; leurs clés existent dans la migration 20261102204450, et l'app n'utilise pas `allCases`.
  - `RPCResponse.swift`, `RPCResponse+ExceptionsMetier.swift` et la surcharge `erreur(port:tranche:lot:)` sont identiques octet pour octet à `feat/ios-lot3`.
- **Gardes.**
  - `nouveau_code` n'apparaît que dans les tests, ce qui est autorisé.
  - Tous les littéraux `"fn_…"` sont dans `RPC_SUIVIES`.
  - Aucun littéral `"""` ni aucune marque juridique dans les fichiers de `DOSSIERS_LOT2`.
  - Les textes du pilote sont repris mot pour mot (l.16 et l.71). Les 3 messages Keychain sont opérationnels et inventoriés.
- **Aucune régression des lots 0 et 1.**
  - Le cœur n'importe que Foundation : DemoNoNetworkTests reste vert.
  - Aucun changement dans l'app, l'UI ou les identifiants d'accessibilité, aucun XCUITest : pas de fragilité iPad possible.
  - Les tests du lot 1 sont adaptés de façon cohérente.
  - Aucun littéral ressemblant à un secret. Rien hors périmètre (ni `supabase/`, ni `src/`, ni `mobile-native/`).

#### Constats
##### Bloquants
Aucun.

##### Majeurs
Aucun.

##### Mineurs
1. **Règle des 8 s** (`RecuScan.swift:17` et `:169-170`, décision 2). Une requête peut attendre une connexion PostgREST jusqu'à 10 s avant que les 8 s ne commencent (PGRST003). Une horloge d'appareil qui avance donne aussi un faux « non reçu ». L'anti-rejeu serveur de 2 min (l.55661) limite l'impact. Correction : amender la décision 2, soit en passant à 20 s au moins avec un test, soit en consignant le risque résiduel, et mesurer l'écoulement sur une horloge monotone dans le même processus.
2. **Consignes T3 et T6 incomplètes** (`DECISIONS_LOT2.md:215-250`). Elles ne disent pas quoi faire d'un reçu `prepared` orphelin (sortie sûre : `marquerNonEnvoye`), ni d'un justificatif `registered` sans vérification, qui bloque les envois suivants jusqu'à son effacement.
3. **Consigne T3 sur `{error}` de l'état** (`:238-241`). Elle écrit `.refuse`, qui n'existe que dans `IssueScan`, alors que `etat` rend `EtatPointage` (`Lot2Ports.swift:17`). Il faut décrire la `JoleneError` verbatim attendue.
4. **Écarts au blueprint non consignés** dans le tableau des amendements :
   - champs `version` et `demarre_le` de RecuScan ;
   - signatures de `admissionRecette` et `fichierOriginal` ;
   - `LocationPort.autorisation()` async ;
   - fichier `RecuDurable.swift` ;
   - emplacement d'`Appareil.demo`.
5. **Exceptions de §2.4 non couvertes.** Celles de `fn_creer_notation_mission` (P0001, l.27425 et l.27439) ne sont ni déclarées ni testées. Celle du trigger santé (P0001, l.62577) porte un texte juridique : il faut consigner qu'elle ne doit jamais être déclarée pour `fn_remplacer_document_soignant`.
6. **Coordonnées journalisables.** `MetadonneesScan` (`Lot2Results.swift:197`) devrait masquer les coordonnées dans ses descriptions et sa réflexion, avec un test.
7. **Message d'effacement trompeur.** `ReceiptJournal.effacer` (`:102`) lève `recuEnCours` alors que le reçu stocké est un autre essai déjà terminé.
8. **Références et garde.**
   - Deux numéros de ligne du pilote sont décalés d'une ligne (`RecuScan.swift:14`, `RecuDurable.swift:60`).
   - L'en-tête de `DOSSIERS_LOT2` affirme qu'aucun fichier du lot 1 n'est couvert, alors que le dossier `Receipts/` l'est et accueillera le reçu de lot 1 T7 (`check-textes-juridiques-ios.mjs:91` et `:113`).

#### Conclusion
La fondation est conforme au blueprint v2 et aux décisions, Q23 étant appliquée par son repli prévu. Les ports sont figés, les décodeurs ne lisent que des clés autorisées, et les exceptions sont interceptées avant `SupabaseErrorMapping`. Le journal reste fermé en cas d'échec, et tout succès suppose une relecture. Aucun texte juridique n'est ajouté. La CI doit confirmer le build et les tests. Avant de démarrer T3, il faut traiter M1 à M3.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- Branche d'intégration `int-lot2` créée depuis `origin/feat/ios-lot2` (`6126fa52`, T0 compris), puis
  `git merge --no-ff origin/lot2/l2-t1-v2` (`f24affb3`), commit de fusion `a0ff30d8`.
- Aucun conflit textuel : `feat/ios-lot2` n'avait pas bougé depuis la base de la tranche (merge-base `6126fa52`).
- Point de jonction avec la base : `check-textes-juridiques-ios.mjs` étend `DOSSIERS_LOT2` au dossier `Receipts/`
  et aux fichiers `Models/Lot2Results.swift`, `Ports/Lot2Ports.swift`, `Ports/AppareilPorts.swift`,
  `Keychain/KeychainTerminalIdentity.swift` et `Keychain/KeychainReceiptStore.swift`. La garde passe sur
  l'ensemble fusionné, `Pointage/` et `Documents/` de T2 et T2b compris.
- Les renvois de ligne de la revue portent sur `origin/lot2/l2-t1-v2`. Après la fusion de T2b, M3 (`:238-241`)
  reste juste ; les consignes T6 visées par M2 sont décalées de 10 lignes (`DECISIONS_LOT2.md` l.215-260 sur
  `feat/ios-lot2`), à cause de l'insertion des deux consignes T3 de T2b.
- Constats mineurs 1 à 8 : non traités par l'intégration (aucun ne casse une vérification). M1 à M3 restent un
  préalable à T3 ; les autres restent à la charge de T1 (correctif) ou des tranches qu'ils nomment.

## L2-T2b

### Revue fraîche B8 — L2-T2b

**Verdict : CLOTURABLE.** Aucun constat bloquant ni majeur, quatre mineurs.

#### Périmètre relu
`git diff origin/feat/ios-lot2...origin/lot2/l2-t2b-v2` relu en entier : 4 commits (28d2e97a, cea95b54, df8344b8, 0f9b7018), 13 fichiers. La branche part de la pointe actuelle de `feat/ios-lot2` (6126fa52, merge-base identique) ; W1 (#1112, 12d50b7d) y est déjà. Aucun fichier `src/` n'est modifié. Les deux golden ont été relus en scratchpad, sans aucune écriture dans le dépôt.

#### Vérifications
- **Parité web ↔ Swift, ligne à ligne.**
  - `filtrerDocumentsRequis` : régimes, `!!type_exercice`, `PROFESSIONS_SANS_RPPS.includes(null)`, dispense diplôme, RPPS_ADELI et AUTORISATION_EXERCICE, repli `|| 'TOUS'`, ordre reçu.
  - `documentValidePourExigence` : type, `=== 'VERIFIE'`, diplôme de spécialité seulement pour DIPLOME, `!valide_jusqua` → valide, `new Date(...) > maintenant` (date seule = minuit UTC, microsecondes tronquées).
  - `construireListesPresences` : bornes du jour civil de Paris, segment ouvert `!fin`, prochain créneau `>= demain`, durée (avec repli `duree_heures` en pratique mort), « à confirmer » ASSIGNEE sans prévisionnel, tri stable (datées puis +∞), `slice(0,20)`, `filtrerMissionsEnCours`, choix du contrat.
  - Je n'ai trouvé aucune divergence. Les trois écarts de domaine annoncés (`mission_id` nul écarté, durée NaN → nil, ordre des clés non comparé) sont documentés et sûrs : échec fermé, et le `JSONValue` compare des dictionnaires.
- **Vecteurs.** 181 + 43, total 2 793 (2 569 + 224). Les 16 cas vitest de `documents-requis.test.ts` et les 16 de `presences-soignant-listes.test.ts` sont tous repris. Sondages concordants à la main : DST de mars et d'octobre, `legacy-sans-decalage-demain`, `formats`, `date-nulle`, `ide` en minuscules, `grille/statut/null`.
- **Renvois `public.sql` et `types.ts`, tous exacts** : l.408, 68776, 68786, 69059, 69060, 69065, 69066, 70567 ; `statut: string | null` l.1129. `missions.debut_le` et `fin_le` sont NOT NULL, `statut` est NULLable (couvert par la consigne T3 de type tolérant). Les renvois `PresencesSoignant.tsx` l.112-115 et `DocumentsSoignant.tsx` l.199-201 sont justes ; `documents.ts` l.26 est juste.
- **Décodage tolérant.** `DocumentSoignantExigence.statutVerification: String?` (NULLable), `RegleDocumentRequis.typeExerciceRequis: String?`, profil entièrement optionnel ; les colonnes non optionnelles sont NOT NULL. Les deux reports en T3 (`ContratPointage.statut` nul, `profession_requise` absent du select) sont consignés dans DECISIONS_LOT2.md et dans l'exporteur.
- **CI `paths`.** Les deux modules W1 sont ajoutés aux deux listes. Leurs dépendances transitives (`constantes.ts`, `documents.ts`, `profession-hierarchy.ts`, `date-heure-paris.ts`, `disponibilite-pointage.ts`) y figuraient déjà.
- **Swift 6.** Règles pures, `Sendable` conditionnels corrects, conformance de `MissionRecord` dans son propre module, aucune collision de noms dans `ios-native/`.
- **Rien d'applicable dans la liste de recherche.**
  - Aucun code réseau : ni PostgREST, ni `SupabaseErrorMapping`, ni `{error}` en 200, ni relecture serveur.
  - Aucun écran, aucun XCUITest, aucun identifiant d'accessibilité touché.
  - Démo, `DemoNoNetworkTests` et sentinelle intacts. Le passage de `triStable` de `private` à `internal` ne change aucun comportement.
- **Aucun texte affiché** : pas de HARD STOP n°4.
- **Aucun littéral ressemblant à un secret.**
- **Aucun fichier hors périmètre** : DECISIONS_LOT2.md (consignes T3), un commentaire de HistoriquePresences et un de RulesExigencesDocumentsTests, la visibilité de `triStable`.
- **Tests.** Les 14 + 1 XCTest assertent tous un comportement réel, aucun n'est vide.

#### Constats mineurs
1. `ExigencesDocuments.swift:145-146` : le commentaire « jamais dépassée … échec fermé » est trompeur ; c'est la parité web, et la pièce n'est pas valide.
2. `export-golden-vectors.mjs:1859-1861` : « tout autre format de date est hors domaine » n'est pas contrôlé (l.1884) et contredit le vecteur `illisible` (l.2036).
3. `RulesListesPresencesTests.swift:129` : le nom du test en dit trop ; on pourrait figer par un test le `keyNotFound(profession_requise)` consigné pour T3.
4. `ListesPresences.swift:119` : la valeur par défaut `[:]` ne permet pas d'inférer `Etablissement` (ergonomie).

#### Points d'attention, hors tranche
- `ios-swift-ci.yml` ne se déclenche que sur PR ou push vers `main` : cette branche n'a encore été vérifiée par aucune CI. Je me fonde sur les journaux de l'auteur (`t2bfix-test.log` : 384 tests, 0 échec ; `t2bfix-build.log` : 0 avertissement ; `t2bfix-node.log` : 155/155). L'export suivi du diff golden et `swift test` ne seront rejoués qu'à la PR vers `main`.
- Il reste un doublon `triStableCroissant` (`Pointage/SynthesePresence.swift:83`) à côté de `DisponibilitePointage.triStable`, désormais `internal`. C'est le mineur 8 de la revue T2, à traiter dans une tranche de suivi.
- Pour T3, deux consignes : `ContratPointage.statut` nul → `""`, puis un vecteur `statut: null` ; `profession_requise` à ajouter au select, ou un type de mission tolérant (statut NULLable compris).

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot2/l2-t2b-v2` (`0f9b7018`) après T1, commit de fusion `2e3dc380`.
- Un conflit, documentaire seulement, dans `docs/mobile-swift/DECISIONS_LOT2.md` (consignes aux tranches
  suivantes) : T1 et T2b insèrent leurs consignes au même endroit, après la consigne T3 `est_etab: null`. T1 apporte
  les consignes T3, T6 (deux), « Versions des reçus », T4b et « Lot 1 T7 » ; T2b apporte deux consignes T3
  (`contrats_mission.statut` NULLable, `profession_requise` absent du select de `missions`). Résolution : les deux
  côtés sont gardés mot pour mot. Les deux consignes T3 de T2b sont placées juste après la consigne T3 de T1 et
  avant les consignes T6, pour que les trois consignes T3 se suivent.
- Aucun autre fichier n'est touché par les deux tranches. T1 rend `MimeDocument` `Codable`
  (`Documents/ClassementDocument.swift`) ; T2b modifie `Documents/ExigencesDocuments.swift` et crée
  `Pointage/ListesPresences.swift` : ces fichiers sont disjoints. Aucun nom public ne se recoupe. Le seul nom de
  premier niveau en double, `ElementTolerant`, est `private` dans `Models/Lot2Results.swift` (T1) et dans
  `Models/Dashboard.swift` (lot 1), donc local à chaque fichier.
- Point de jonction T1 ↔ T2b : les nouveaux fichiers de T2b (`Pointage/`, `Documents/`) sont couverts par
  `DOSSIERS_LOT2`, et la garde passe, puisqu'ils n'affichent aucun texte.
- Constats mineurs 1 à 4 et points d'attention : non traités par l'intégration (aucun ne casse une vérification).
  Les deux consignes T3 sont consignées dans `DECISIONS_LOT2.md`.

## Vérifications après les fusions de T1 et T2b (intégrateur, 2026-11-08)

Exécutées en local sur la branche d'intégration poussée vers `feat/ios-lot2` (Node 24.14.0 ; Swift 6.1.2 de
Xcode 16.4 sur le poste, alors que la CI utilise Xcode 26.4.1). Rien n'a été écrit en production ni sur STAGING,
et ni Playwright ni dispatch de workflow n'ont été lancés.

- `node --test` des tests touchés (`check-rpc-contracts`, `textes-juridiques-ios`, `mobile-delivery-plan`) :
  155 tests, 0 échec. La suite entière `tests/node/*.node.mjs` donne 1 815 tests, 0 échec, 0 ignoré.
- `node scripts/mobile/check-textes-juridiques-ios.mjs` : 117 textes HARD STOP et 44 libellés identiques au web,
  26 zones de rendu retrouvées.
- `node scripts/mobile/check-rpc-contracts.mjs` : 33 RPC, aucune dérive ; `--update` ne produit aucun diff.
- `node scripts/mobile/export-golden-vectors.mjs` (2 793 vecteurs, dont 181 `documents-requis` et 43
  `presences-soignant-listes`) et `export-demo-fixtures.mjs` : aucun diff.
- `JoleneCore` : `swift build --build-tests -Xswiftc -strict-concurrency=complete` sans erreur ni avertissement ;
  `swift test -Xswiftc -strict-concurrency=complete` : 454 tests XCTest, 0 échec.
- `JoleneSupabase` : même build, sans erreur ni avertissement ; `swift test` : 200 tests XCTest, 0 échec. Les
  lignes `CoreData: error: Failed to create NSXPCConnection` viennent de l'environnement local (elles figurent
  aussi dans le journal de l'intégration du lot 3) et ne sont pas des échecs.
- App : `xcodebuild build-for-testing` (schéma `Jolene`, Debug, `iphonesimulator`, simulateur existant « Jolene
  iPhone 16 Pro Max » iOS 18.6, `-derivedDataPath` dans le worktree, sans signature ni index) donne
  `TEST BUILD SUCCEEDED` avec 0 avertissement hors dépendances ; les sources de T1 et T2b y sont compilées. Aucun
  test UI n'a été lancé. `project.pbxproj` n'était pas en conflit et aucune tranche n'ajoute de fichier à l'app :
  `xcodegen generate` n'a pas été nécessaire.
- Aucun correctif d'intégration n'a été nécessaire.
- Reste à prouver par la CI, à la PR vers `main` : le job « interface » d'`ios-swift-ci.yml` (simulateur, trois
  formats) et le job « packages » sous Xcode 26.4.1.

## L2-T3

### Revue fraîche B8 — L2-T3 (vague 2 bis, n°2)

**Verdict : CLÔTURABLE.** Je n'ai trouvé ni bloquant ni majeur, et sept mineurs, détaillés plus bas.

#### Ce que j'ai relu

J'ai relu en entier `git diff origin/feat/ios-lot2...origin/lot2/l2-t3-v2` :
- base `a4add843`, pointe `a4dfbc2e` ;
- 10 commits, 28 fichiers, +4 467 / −47 lignes ;
- à chaque passe, les tests sont commités avant le code (`844e387b`, `4f946f8a`, `30f8edc0`).

La revue s'est faite en lecture seule : aucun build, aucun test, aucun appel MCP. Pour le SQL, `supabase/schema/public.sql` de la branche a suffi.

Sur la vérification de l'auteur : son résumé cite la pointe `177efeef`, alors que sa phase rouge cite `30f8edc0`. La CI de la PR doit donc confirmer `a4dfbc2e`, et avec Xcode 26.4.1 (en local, il a utilisé Xcode 16.4).

#### Points vérifiés sans constat

**MJ-1 (reçu commun soldé par un autre bloc).**
- Quand le bloc d'une autre mission solde l'essai, il transmet l'issue (`.enregistre` ou `.nonRecu`) au bloc qui l'affiche.
- Si le reçu disparaît sans issue transmise, la vérification est levée, juste après une relecture de l'état.
- Un seul modèle par processus réconcilie un essai : le test sur `essaisEnVol` et l'insertion se font sans suspension entre les deux.
- Les cinq tests ont du sens : ils montrent qu'aucun second scan ne part et que B ne publie rien pour l'essai de A.

**mi-1 (requête et relectures bornées à part).**
- Un HTTP 200 n'aboutit qu'à `.enregistre`, `.enregistreSurAutreMission` ou `.accepteSansPreuve`, jamais `.incertain`, et aucune relecture ne relance le scan.
- Les défauts en extension restent sûrs : `envoyerScan` passe par `scanner`, `relireScanAccepte` refuse (« non câblé »), et `UnwiredPointagePort` est couvert par `Lot2PortsTests`.

**mi-2 (première relecture et attente).**
- La première relecture part tout de suite. Le « non reçu » n'est rendu qu'après l'attente monotone : sortie, plus 10 s, plus 8 s.
- `envoiEnCours` retombe pendant la vérification ; `peutEnvoyer` et la garde de `pointer` bloquent tout de même un nouvel envoi.
- Il y a au plus une réconciliation par génération.
- `systemUptime` ne compte pas le temps de veille, ce qui ne peut que retarder le verdict, donc reste prudent.

**mi-3, mi-4, mi-6.**
- mi-3 : la levée intervient après une réapparition.
- mi-4 : après un envoi pendant lequel le bloc a été réactivé, l'état est relu dans la génération courante. Le test passé de 2 à 3 lectures d'état est un changement demandé, pas un affaiblissement.
- mi-6 : la démo vérifie que le terminal du reçu est celui des métadonnées.

**Supabase.**
- `{error}` en HTTP 200 est lu avant le décodage, pour l'état comme pour la synthèse.
- Les exceptions métier sont traitées avant `SupabaseErrorMapping`. Rollback prouvé et réponse incertaine sont bien distingués, et PGRST301 à 303 remontent en `.unauthorized`.
- `localiser` interroge sans filtre de mission (`sp_select` l.79931) avec la projection `PreuveScan` : jamais `code_saisi`, `ip_address`, `latitude` ni `longitude`.
- Le code suivant n'est jamais décodé : il n'apparaît dans aucune source Swift, et `ScanEnregistre` est ré-encodé avec ses 7 clés seulement.

**Concurrence Swift 6.**
- Le modèle est `@MainActor`, ses états partagés `static` sont isolés sur le même acteur, et les ports sont `Sendable`.
- `bounded` n'est pas structuré, donc un enfant bloqué ne retient pas l'appelant.
- Une réponse tardive après un changement d'epoch ou de vue est ignorée. Si l'epoch n'a pas changé, le reçu est quand même soldé.

**HARD STOP n°4 : non déclenché.**
- Aucun texte juridique nouveau.
- Les messages serveur repris par la démo sont mot pour mot ceux du SQL : relance (l.53052 et l.53071), anti-rejeu, P0002 et « Mission introuvable ».
- Les replis ajoutés sont opérationnels et inventoriés.

**Données sensibles.**
- Ni coordonnées, ni code saisi, ni code suivant ne sont journalisés.
- `MetadonneesScan` masque les coordonnées dans `description`, `debugDescription` et `customMirror`, test `dump` à l'appui.
- Aucun `print` ni `Logger` ajouté, et aucun littéral qui ressemble à un secret (`f00dbabe` n'est qu'une valeur factice dans un test).

**Lots 0 et 1.**
- `ContratPointage` garde son initialiseur explicite, et le statut nul est lu `""`.
- Le câblage `pointage` est fait dans les deux mondes ; `portsEnAttenteLot2` est à jour.
- Aucun usage dans l'app, aucun identifiant d'accessibilité touché, aucun XCUITest (la tranche n'a pas d'écran).
- La démo n'utilise pas le réseau ; la garde sur le système de pointage ① est conservée.

**Coordinateur de liens.** Rien dans T3 ne gêne son branchement : `ongletInitial(parametre:)` et `filtreAValider(_:)` prennent les valeurs brutes de `?tab=` et `?filtre=`. Le seul point lié est m-5.

#### Constats mineurs

| n° | Constat | Où | Correction attendue |
|---|---|---|---|
| m-1 | Une issue transmise peut être appliquée par le mauvais bloc (trois blocs et une heure reculée). Le bloc B affiche alors le succès ou le « non reçu » de la mission A. | `PointageModel.swift:567-569`, `585-592`, `692-703` | Enregistrer la mission avec la conclusion, et ne l'appliquer que si elle est celle du bloc. |
| m-2 | Hors ligne, l'essai n'est pas « en vol ». Une réconciliation concurrente efface le reçu `prepared`, et le bloc reste en `.suiviIllisible` pour toujours. | `PointageModel.swift:276-291`, `285`, `509-512` | Inscrire l'essai dans `essaisEnVol` autour des deux écritures, comme en ligne. |
| m-3 | Un essai prouvé par un HTTP 200 reste réconciliable : fenêtre entre `oublier` et `effacer`, et échec d'effacement avalé. Un bloc de la même mission peut alors conclure « non reçu ». | `PointageModel.swift:434-435`, `477-478`, `507`, `570-571` | Effacer avant `oublier`, ou tenir un ensemble des essais soldés ; échec d'effacement → `.suiviIllisible`. |
| m-4 | Un `.unauthorized` pendant les relectures d'un 200 est avalé par des `try?`, et la branche `sessionExpired` est morte. | `SupabasePointageGateway.swift:210-216` ; `PointageModel.swift:379-381` | Laisser remonter `.unauthorized`, avec un test, ou retirer le commentaire. |
| m-5 | La levée mi-3 exige une disparition du bloc, ce que le renvoi Safari (feuille) ne provoque pas. | `PointageModel.swift:653-659` ; `DECISIONS_LOT2.md:352-353` ; `PresentateurRenvoiWeb.swift:3-13` | Préciser la consigne T4b/T10, ou exposer une méthode explicite de levée. |
| m-6 | Un test repose sur l'horloge réelle, avec une marge de 0,4 s : risque d'échec aléatoire en CI. | `PointageModelTests.swift:703-704` | Utiliser des `Gate`, ou élargir la marge. |
| m-7 | La doc dit encore que la réponse brute « ne sort jamais de `scanner` ». | `CONTRATS_RPC_SOIGNANT.md:1272-1273` | Remplacer par `envoyerScan`. |

Ces sept mineurs ne bloquent pas la clôture. m-1 à m-3 exigent des conditions de course ou des pannes rares, mais touchent l'invariant « jamais de faux non reçu » : je recommande de les corriger avant T4b.

#### Limites consignées (non comptées)

Ces limites sont consignées dans `DECISIONS_LOT2.md` et acceptées par les revues précédentes :
- une réponse perdue pour un scan appliqué sur une autre mission ne se résout que par un reçu v2 ou une clé d'idempotence serveur (B9) ;
- un HTTP 200 arrivé après le délai `bounded` compte comme une réponse perdue ;
- m6 (la relecture de `fin_le`) est confiée à T5a ;
- T4b doit associer chaque `Issue` à son libellé web.

#### Avant le merge

- La CI de la PR doit être verte sur `a4dfbc2e`, avec Xcode 26.4.1, y compris `strict-concurrency=complete`.
- Faire attention à m-6, qui peut faire échouer la CI sans rapport avec le code.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- Branche d'intégration `int-lot2-v2b` créée depuis `origin/feat/ios-lot2` (`a4add843`). D'abord
  `git merge --no-ff origin/main` (`404fc012` : PR B9 #1114, #1117 et #1118 mergées depuis le 8/11), commit de
  fusion `e8cb2f44`, sans conflit. Puis `git merge --no-ff origin/lot2/l2-t3-v2` (`a4dfbc2e`), commit de fusion
  `4f025533`, sans conflit (T3 est la première des trois tranches fusionnées sur la base).
- Point de jonction avec `main` : B1 (#1117) retire `nouveau_code` et `nouveau_hmac` de `fn_scanner_code_pointage`
  et re-baseline le dump (numéros de ligne décalés de +43 à +51 après l.25743). Deux gardes de
  `tests/node/check-rpc-contracts.node.mjs` rougissaient, comme le prévoit `DECISIONS_LOT2.md` « Ordonnancement
  et branches » : la garde « `nouveau_code` renvoyé tant que B1 n'est pas mergée » et les numéros de ligne de la
  fiche `fn_etat_pointage_mission`. Bascule faite par le commit `9a2efd02` (voir « Vérifications » ci-dessous).
  Le décodeur de T3, qui accepte déjà les deux formes de réponse, n'a pas eu à changer.
- Renvois de la revue après les fusions : les fichiers Swift de T3 n'ont été touchés ni par T6 ni par T8, donc les
  renvois `PointageModel.swift`, `SupabasePointageGateway.swift`, `PointageModelTests.swift` restent exacts.
  m-5 vise désormais `DECISIONS_LOT2.md` l.355-356, et m-7 `CONTRATS_RPC_SOIGNANT.md` l.1297-1298. Les numéros
  `public.sql` cités par la revue (l.79931, l.53052, l.53071) sont ceux du dump d'avant #1117 (+47 et +49 depuis).
- Constats mineurs m-1 à m-7 : non traités par l'intégration (aucun ne casse une vérification). La revue
  recommande de corriger m-1 à m-3 avant T4b. m-6 n'a pas échoué localement (655 tests, 0 échec), mais reste un
  risque d'échec aléatoire sur la CI.

## L2-T6

### Revue fraîche B8 — L2-T6 (vague 2 bis, n°2)

**Verdict : CLOTURABLE** (0 bloquant, 0 majeur, 6 mineurs).

#### Périmètre relu
- Diff relu en entier : `git diff origin/feat/ios-lot2...origin/lot2/l2-t6-v2`, soit 30 fichiers et environ 4 700 lignes.
- Sept commits, de `2e3c8cb9` à HEAD `3d86b95a`.
- Relus en complet sur la branche : DocumentsModel, EssaisDocumentsEnVol, DossierDocuments, FichierDocument, NormalisationImage, ConsultationDocuments, MessagesDocuments, DemoDocumentsGateway, SupabaseDocumentsGateway, ports et modèles T1, tests JoleneCore et Supabase, DECISIONS, CONTRATS, rpc-contracts et exporteur.
- Recoupements :
  - `Bounded.swift` : le perdant est annulé sans être attendu.
  - `ReceiptJournal` et `RPCResponse+MutationLot2`.
  - `fn_remplacer_document_soignant` dans `public.sql` (l.53079-53165).
  - `verify-document/index.ts` : limitation de débit 10/min (l.318-330) et `cleanup_orphan` (l.331-380).
  - Web `DocumentsSoignant.tsx` (l.276-332 et l.405-430).
- Lecture seule. Aucun build ni test lancé de ma part, aucun MCP interrogé. Mon dossier temporaire de revue est supprimé.

#### Constats précédents : tous vérifiés et corrigés
- **M1-bis.** `EssaisDocumentsEnVol` (main actor) contrôle puis inscrit sans aucune suspension intermédiaire, y compris à travers l'appel async isolé de `reconcilierEnAttente`.
  - L'envoi est inscrit avant le reçu `prepared` et retiré par sa propre tâche.
  - `charger()` et `envoyer()` d'une autre instance suivent l'envoi en vol (`.enCours`) au lieu de le réconcilier ou de le doubler.
  - La réconciliation est unique par clé et partagée par toutes les instances.
  - L'étape 1 de l'envoi rejoint la réconciliation en cours. J'ai parcouru tous les entrelacements (deux instances, charger ou envoyer) : aucune réconciliation de l'essai en vol, aucun second `verify-document`.
  - Le cas d'un délai dépassé tient aussi, alors que `bounded` n'attend pas le perdant : soit la garde `Task.isCancelled` bloque la vérification, soit la ligne relue l'interdit.
- **m-a** : la garde est posée avant la première suspension, et le test le prouve.
- **m-b** : le dossier est lu d'abord, la réconciliation est bornée à 4 × `resolutionTimeout`.
- **m-c** : `PreuveDocument.issue` est dérivée du statut relu, avec `.verdictRendu`.
- **m-d** : `verificationEchouee` observe l'issue sans jamais relancer l'appel. Parité avec le `.then` du web : erreur → vérification manuelle, réponse → relecture.
- **m-e** : la portée de `cleanup_orphan` est corrigée dans la documentation.
- **m-f** : rien n'est publié pour un epoch quitté. Un reçu impossible à effacer donne `.suiviIllisible`.
- **m-g** : -1009 est classé incertain. **m-h** : `oublierDossierComplet` ajouté. **m-i** : amendement réécrit.
- Les deux tests modifiés sont justifiés par m-b et m-g, et non affaiblis : `cannotFindHost` couvre toujours le chemin « jamais parti ».

#### Points contrôlés sans défaut
- **Corps `{error}` en HTTP 200** : traités pour `fn_remplacer` (`success:false`, `NON_AUTHENTIFIE`, `DOCUMENT_INACTIF`), l'attestation, la revue, la cohérence et `reverifier`.
- **Exceptions PostgREST** : lues brutes avant `SupabaseErrorMapping` (`appelerMutation`, `sessionExpiree`). PGRST301-303 donnent la session expirée, sans nettoyage.
- **Swift 6** : `Sendable` et MainActor respectés ; `deinit` passe par une boîte verrouillée ; le suivi garde le modèle en référence faible.
- **Succès** : toujours annoncé après relecture du dossier ; l'attestation est relue.
- **HARD STOP n°4** : aucun texte juridique ajouté ni reformulé. Les messages viennent du web, avec leur source ; les seuls textes propres à la démo sont fictifs.
- **Données sensibles** : aucun journal applicatif ; la fixture GPS est le centre de Paris (fictive) ; aucun littéral ressemblant à un secret.
- **Lots 0 et 1** : identifiants d'accessibilité et app intacts. Le monde démo passe sur `DemoDocumentsGateway`, sans réseau, et la sentinelle reste à 0 requête. Aucun XCUITest, donc aucun risque iPad.
- **Périmètre** : respecté. `Lot2Ports.swift` et `Lot2Results.swift` reçoivent des ajouts seulement, consignés dans DECISIONS.
- **T3b** : rien ne gêne son branchement. Le renvoi web `renvoiWeb` passe déjà par `PresentateurRenvoiWeb` (DECISIONS l.263), donc il n'est pas intercepté par la route native `/soignant/mes-documents`.

#### Mineurs (non bloquants)
- **m1** : une copie de consultation peut être écrite après un délai dépassé ou un changement d'epoch, et rester sur le disque sans rattachement.
- **m2** : `effacerTout()` est global ; la consigne T7 « à la fermeture de QuickLook » casse la consultation dans l'autre fenêtre iPad.
- **m3** : `source` a une valeur par défaut (`.fichiers`), alors qu'il est dit obligatoire. Un oubli enverrait les EXIF et le GPS de la photothèque sans erreur.
- **m4** : `reprendre` et `appliquer` publient une issue sans consulter le registre. Seul l'état affiché peut être faux ; aucun double envoi possible.
- **m5** : le registre global est partagé par les tests sans `tearDown` ; un test qui échoue avant d'ouvrir sa barrière fait échouer tous les suivants.
- **m6** : l'écart de calcul des jours (tranches de 24 h contre jours civils) n'est pas consigné dans DECISIONS.

Le détail, avec fichier:ligne et la correction attendue, figure dans `mineurs`.

#### Notes pour l'intégrateur
- Les notes de l'auteur citent encore « un 429 n'affiche la vérification manuelle qu'après 60 s ». C'est périmé : le code et DECISIONS l'affichent aussitôt (m-d), et le délai de 60 s ne reste qu'en dernier filet. À corriger dans REVUES_LOT2.md.
- `fn_ecrire_audit_safe` reste `a_venir` alors que les lots 1 et 2 l'appellent. Cette incohérence date du lot 1 et sort du périmètre de T6.
- La CI de la PR vers main doit encore prouver deux jobs : « interface » (simulateur, trois formats) et « packages » sous Xcode 26.4.1.
- Tiering : aucune catégorie B9 touchée (paiement, RLS, GRANT, légal). Aucun HARD STOP.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot2/l2-t6-v2` (`3d86b95a`) après T3, commit de fusion `5249d260`.
- Six fichiers en conflit, tous résolus en gardant les deux côtés :
  - `DemoWorldTests.portsEnAttenteLot2` : T3 retire `pointage`, T6 retire `documents` → `["contestation",
    "notation", "contrats"]` ; `testCablerLot2AssigneLesStubsSansToucherAuLot1` garde les assertions des deux
    tranches (`DemoPointageGateway`, `DemoDocumentsGateway`).
  - `SupabaseGateways.câblerLot2` : signature de T6 (`clock:` avec défaut, que `make(client:clock:enrich:)` passe
    déjà), ligne `pointage` de T3 (`SupabasePointageGateway(client:clock: gateways.clock)`) et ligne `documents` de
    T6 (`SupabaseDocumentsGateway(client:clock: clock)`). Dans `make`, les deux horloges sont la même.
  - `SupabaseGatewaysTests.testCablerLot2AssigneLesStubsDuLot2` : `suffix(3)` = `["contestation", "notation",
    "contrats"]`, plus l'absence de `pointage` (T3) et de `documents`.
  - `export-demo-fixtures.mjs` : `buildDemoPresences` (T3) puis `buildDemoDocuments` (T6), et les deux fichiers
    (`demo-presences.json`, `demo-documents.json`) dans `buildFixtures`.
  - `CONTRATS_RPC_SOIGNANT.md` (synthèse) : statuts « consommée » de T3 (`fn_consentir_gps`,
    `fn_relancer_validation_presence`, `fn_presences_detail_mission`) et de T6 (`fn_remplacer_document_soignant`).
  - `DECISIONS_LOT2.md` (« Amendements du blueprint ») : les lignes de T3 puis celles de T6, mot pour mot.
- Fusionnés sans conflit : `DemoWorld.swift`, `Models/Lot2Results.swift`, `Ports/Lot2Ports.swift` (ajouts
  disjoints), `rpc-contracts.json` et `check-rpc-contracts.mjs` (statuts de T6). Les fichiers Swift propres à T6
  (`Documents/`, `SupabaseDocumentsGateway.swift`) n'ont été touchés ni par T3 ni par T8 : les renvois de la revue
  restent exacts.
- Correction des notes de l'auteur (demandée par la revue) : un 429 de `verify-document` n'attend pas 60 s.
  L'issue de la vérification est observée aussitôt hors du chemin critique (`DocumentsPort.verificationEchouee`,
  m-d) et l'écran passe alors à « Document téléversé. Vérification manuelle en attente. » ; le délai de 60 s n'est
  que le dernier filet, pour une pièce encore `EN_ATTENTE` sans tentative (`DECISIONS_LOT2.md`, consigne T7).
- Mineurs m1 à m6 et note `fn_ecrire_audit_safe` : non traités par l'intégration (aucun ne casse une vérification).

## L2-T8

### Revue fraîche B8 — L2-T8 (vague 2 bis, n°1)

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur. Dix mineurs, dont deux à corriger de préférence avant T3b et T9a : la casse de l'id dans `certificat()`, et la réconciliation de la signature au niveau du modèle.

#### Périmètre lu
- Diff `origin/feat/ios-lot2...origin/lot2/l2-t8-v2` relu en entier : 31 fichiers, +3842 / −106, commits `844b78a1` (tests rouges), `3739dec1`, `aea91438` et `99dc952c`.
- Sources confrontées :
  - `public.sql` : `fn_signer_contrat_otp` l.56473-56607, `fn_envoyer_otp_signature`, INSERT et UPSERT de `signatures_contrats` l.33232, GRANT colonne par colonne l.86518-86570, GRANT des tables `soignants`, `contrats_mission` et `missions`, CHECK de `contrats_mission`.
  - Politique `pol_contrats_signes_select` (migration `20260729143000`).
  - Edge `generate-contrat-mission-pdf` : `buildVariables`, `wrapInDocument`, `repondreOriginal`, format des chemins Storage depuis #87.
  - Web : `ContratMission.tsx` (l.62-66, 200-440, 530-840), `SignerContratOtp.tsx`, `ListeContrats.tsx` l.69, `CertificatSignature.tsx` l.50, `contratMissionUi.ts`.
  - Pilote : `supabaseGateway.ts` l.21 et l.263, `business.ts` l.29-80.
  - Blueprint : `LOT2_PLAN.md` v2 (§2.3-2.8, T8, Q17-Q20), `LOTS_2_5_DECISIONS.md`, `CLAUDE.md`.

#### Ce qui est solide (vérifié)
- **Projections explicites partout, jamais `select=*`.**
  - Le détail n'inclut jamais `signature_image_*`, `signature_ip_*` ni `signature_navigateur_*`.
  - Le certificat se limite exactement aux 14 colonnes accordées (la correction 22 est respectée).
  - Le nom d'établissement passe seulement par `fn_etablissements_safe`.
  - Le compte TEST est relu dans `soignants` et échoue fermé.
- **Original contrôlé.**
  - Triple contrôle : SHA-256 UTF-8 = `hash_document` = octets Storage, sans normalisation, avec les mêmes conditions que `fn_signer_contrat_otp`.
  - Le chemin doit être `<id>/<nom>.html`. Les chemins historiques `<id>/<ISO-ts>.html` (avant #1000) passent la règle.
  - `signatureMismatch` est aligné sur le pilote.
  - Rendu : demandé une seule fois, jamais pour un CDD à préparer, corps `{contrat_id}` seulement, puis contrat relu. Le refus est restitué verbatim, sans renvoi.
- **OTP.**
  - Clés exactes ; `p_signature_image` est NULL.
  - L'empreinte est relue avant tout SMS.
  - Un succès n'est annoncé qu'après relecture du contrat **et** de la ligne `signatures_contrats` du compte.
  - Une réponse incertaine est réconciliée par relecture, sans renvoi. La correction `try?` de `99dc952c` est correcte et ses deux branches sont testées.
  - L'exception déclarée `23514` est lue avant `SupabaseErrorMapping`.
  - Les formes `{success:false,error_code,error}` en HTTP 200 sont traitées.
- **Session OTP.**
  - Clé (contrat, empreinte, document prêt) : consentement et code remis à zéro à chaque changement.
  - Une réponse dont la clé a changé est ignorée grâce au jeton.
  - Un double tap ne produit qu'une seule requête (testé au niveau du modèle).
  - Les refus bloquants et le minuteur dérivé de l'échéance sont conformes à `SignerContratOtp.tsx`.
- **Admission de recette.** Appelée seulement si l'origine du projet est STAGING. Le test prouve qu'en production aucune requête ne part.
- **Démo.**
  - Fixtures déterministes (fuseau Europe/Paris explicite, `wrapInDocument` extrait du source de l'edge, échec bruyant si sa forme change).
  - OTP `000000`, `111111` donne 4 essais restants, scénario `otp-expire`.
  - Refus `.demoOnly` pour tout autre compte. Aucun import réseau dans Core.
- **Câblage des deux mondes** et `portsEnAttenteLot2` cohérents.
- **Hygiène.**
  - Aucun journal, aucune donnée sensible exposée (OTP, URL signée, chemin, téléphone).
  - Aucun texte juridique ou de consentement ajouté (HARD STOP n°4 respecté).
  - Aucun littéral ressemblant à un secret ; aucun fichier hors périmètre.
  - Le commit de correction des tests garde ses 49 assertions.
- **Régressions des lots 0 et 1 :** aucune. Les inits de T1 sont conservés, pas de nouvel identifiant d'accessibilité ; `DemoNoNetworkTests` et le format des fixtures sont intacts. T8 n'ajoute pas de XCUITest, ce qui est normal sans écran.

#### Mineurs (fichier:ligne → correction)
1. **`SupabaseContratsGateway.swift:118`** : le filtre de `certificat()` respecte la casse, contrairement au reste du gateway (`meme`). Avec un id en majuscules (lien saisi, ou normalisation par `UUID.uuidString` dans T3b), le certificat sort vide et la signature réelle est annoncée « non confirmée ». Correction : `Self.meme`, ou id en minuscules à l'entrée, plus un test.
2. **`ContratModel.swift:175`, gateway l.184 et 198-204** : un seul budget de 15 s couvre la RPC et la réconciliation. Si le délai expire, la réconciliation est annulée ; une relecture en échec après succès remonte l'erreur réseau brute ; rien n'est relu après `DEJA_SIGNE`. Aucun faux succès, mais un état périmé à l'écran. Correction : relire depuis le modèle dans le catch et sur ces refus.
3. **Gateway l.146, 180 et 308** : le message de repli des mutations est un texte de chargement (« Les contrats ne peuvent pas être chargés »). Correction : utiliser les replis de `LibellesWeb.SignatureOtp`.
4. **`DECISIONS_LOT2.md:368-370`** : les trois textes opérationnels de T8 ne sont gardés par aucun test mot pour mot (aucune occurrence du littéral dans les tests). Correction : un test d'inventaire, et `messageIndisponible` déplacé dans `LibellesWeb` avec sa ligne `// source:`.
5. **`DECISIONS_LOT2.md:295-297`** : l'erreur web l.388 (« encore incomplet ») n'est pas restituable, car elle se confond avec `.nonFige` ; l'erreur l.394 fait passer tout l'écran en `.echec`. Correction : un motif distinct après tentative de rendu, ou une consigne T9a amendée.
6. **Gateway l.303-304** : un 401 de l'edge est traité comme un rendu refusé au lieu d'une session expirée.
7. **Gateway l.318** : la borne de 2 Mo est vérifiée après le téléchargement complet. Correction : contrôle de taille préalable, ou amendement consigné.
8. **`ContratModel.swift:60-69` et `SessionSignatureOtp.swift:217-227`** (STAGING seulement) : l'admission n'expire jamais localement, `actionsSuspendues` est absent, et `reprendre` avec une échéance passée efface consentement et code au lieu d'afficher « Expiré » comme le web.
9. **`ContratModel.swift:148-149, 169-171, 205-206`** : l'epoch n'est pas vérifié avant l'envoi d'une requête, ni dans le catch de `relireApresSignature`.
10. **À remonter à Gabrielle** (HARD STOP n°4, hors T8) : la mention de pied de page web, portée fidèlement (`ContratRules.swift:110-113`), qualifie un CDDU ou une VACATION de « contrat de prestation … libéral ». La PR doit aussi signaler que les originaux démo (texte du serveur, données fictives) seront visibles en mode démo et par l'App Review.

#### Pour les tranches suivantes
- **T3b :** `ContratModel(contratId:)` et `FiltreContrat.initial(statut:)` se branchent simplement. Il faut d'abord corriger le mineur 1 (casse), sinon un lien qui normalise l'UUID casse la confirmation de signature.
- **T9a :** suivre les mineurs 4 et 5.
- **T9b** (HARD STOP) : les mineurs 2 et 8 touchent sa parité.

#### Limites de cette revue
- Lecture seule : aucun build ni test lancé ; je me fie aux résultats de l'auteur (JoleneCore 524/0, JoleneSupabase 228/0, `build-for-testing` OK, exporteurs sans diff).
- Aucune requête MCP : la règle 4 de `LOTS_2_5_DECISIONS.md` ne permet en production que la relecture de définitions. La forme des données historiques (chemins, empreintes) a été vérifiée par l'historique git de l'edge, pas en base.

#### Nettoyage
- Mes trois copies de travail du scratchpad sont supprimées et le dépôt est propre.
- Le dossier DerivedData d'environ 111 Mo laissé par l'auteur, `~/Library/Developer/Xcode/DerivedData/Jolene-fwrofllbswdstueodzmjxhvvwydn`, est toujours là. Je n'y ai pas touché (revue en lecture seule) : il reste à supprimer à la main.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot2/l2-t8-v2` (`99dc952c`) après T3 et T6, commit de fusion `3097358e`.
- Huit fichiers en conflit, tous résolus en gardant les trois tranches :
  - `DemoWorld.câblerLot2` : `DemoDocumentsGateway()` (T6) et `DemoContratsGateway(clock: FixedClock(fixedNow))` (T8),
    après la ligne `pointage` de T3.
  - `DemoWorldTests.portsEnAttenteLot2` → `["contestation", "notation"]` ; `testCablerLot2…` affirme les trois
    gateways démo (pointage, documents, contrats).
  - `SupabaseGateways.câblerLot2` : `SupabaseDocumentsGateway(client:clock: clock)` (T6) et
    `SupabaseContratsGateway(client:clock: gateways.clock)` (T8).
  - `SupabaseGatewaysTests` : `testAucunPortNonCable` affirme l'absence de `pointage` (T3) et de `contrats` (T8) ;
    `testCablerLot2AssigneLesStubsDuLot2` : `suffix(2)` = `["contestation", "notation"]`, plus l'absence de
    `pointage`, `documents` et `contrats`.
  - `check-rpc-contracts.mjs` (`RPC_SUIVIES`) : « consommée » pour `fn_scanner_code_pointage` et
    `fn_etat_pointage_mission` (T3), `fn_envoyer_otp_signature` et `fn_signer_contrat_otp` (T8),
    `fn_remplacer_document_soignant` (T6).
  - `export-demo-fixtures.mjs` : la section « contrats démo » de T8 (moteur `cdd-employeur.ts`, gabarit
    `wrapInDocument` relu dans l'edge) après `buildDemoPresences` et `buildDemoDocuments` ; `buildFixtures`, devenu
    asynchrone avec T8, produit les neuf fichiers (missions, établissements, profil, tableau de bord, présences,
    documents, contrats et les deux originaux HTML). Aucun autre appelant de `buildFixtures` dans le dépôt.
  - `CONTRATS_RPC_SOIGNANT.md` (synthèse) : lignes de T3 et T6, et lignes de T8 pour `fn_envoyer_otp_signature`,
    `fn_signer_contrat_otp` (« T8 gateway, T9b écran ») et `fn_admission_otp_signature_recette` (« câblée T8 »).
  - `DECISIONS_LOT2.md` (« Amendements du blueprint ») : lignes de T3, puis de T6, puis de T8.
- Renvois de la revue après les fusions : les fichiers Swift de T8 (`Contrats/`, `SupabaseContratsGateway.swift`)
  n'ont été touchés par aucune autre tranche. Dans `DECISIONS_LOT2.md`, le mineur 4 vise désormais l.569-571
  (tableau « Textes opérationnels hors web (T8) », l.562) et le mineur 5 l.468-471. Les numéros `public.sql` cités
  (l.56473-56607, l.33232, l.86518-86570) sont ceux du dump d'avant #1117.
- Mineurs 1 à 9 : non traités par l'intégration (aucun ne casse une vérification) ; la revue recommande 1 et 2
  avant T3b et T9a. **Mineur 10, à remonter à Gabrielle (HARD STOP n°4)** : la mention de pied de page du web
  (`ContratRules.swift:110-113`) qualifie un CDDU ou une VACATION de « contrat de prestation … libéral » ; et les
  originaux démo seront visibles en mode démo et par l'App Review. Rien n'est changé côté natif sans sa décision.
- Nettoyage : le dossier `~/Library/Developer/Xcode/DerivedData/Jolene-fwrofllbswdstueodzmjxhvvwydn` (≈ 111 Mo,
  laissé par l'auteur de T8) a été supprimé par l'intégrateur, Gabrielle ayant autorisé la suppression des
  restes laissés par les agents. Un second dossier par défaut, `Jolene-eabyjxafhiwjuifakqgkxpvvdspl` (≈ 111 Mo,
  19:15, résolution de paquets seulement), n'a pas été supprimé : son auteur n'est pas établi.

## Vérifications après les fusions de T3, T6 et T8 (intégrateur, 2026-11-08)

Exécutées en local sur la branche d'intégration poussée vers `feat/ios-lot2` (Node 24 ; Swift 6.1.2 de Xcode 16.4
sur le poste, alors que la CI utilise Xcode 26.4.1). Rien n'a été écrit en production ni sur STAGING, aucun MCP
Supabase n'a été interrogé, et ni Playwright ni dispatch de workflow n'ont été lancés.

- Correctif d'intégration `9a2efd02` (« bascule de la garde et des fiches après B1 ») : le merge de `main` faisait
  rougir deux gardes de `tests/node/check-rpc-contracts.node.mjs`, comme prévu :
  - « `nouveau_code` renvoyé tant que B1 n'est pas mergée » : la garde exige désormais l'**absence** de
    `nouveau_code` et de `nouveau_hmac` dans le corps de `fn_scanner_code_pointage` (elle rougit sur un retour
    arrière de B1) et que la fiche consigne le merge de B1 et la bascule ; la liste blanche et l'absence de ces
    clés dans les sources Swift restent gardées. La garde n'est pas affaiblie : elle suit le nouvel état du dump.
  - fiche `fn_etat_pointage_mission` : les lignes citées (l.35165, l.35189) avaient bougé avec la re-baseline. Les
    numéros `public.sql` des fiches `fn_scanner_code_pointage` et `fn_etat_pointage_mission` sont recalculés à
    partir des hunks du diff du dump (l.35214, l.35238, etc.), et le contrat de réponse du scanner est écrit sans le
    code suivant. Les autres renvois `public.sql` des documents du lot 2 (blueprint, DECISIONS, autres fiches,
    commentaires Swift) citent encore le dump d'avant #1117 (+43 à +51 après l.25743) : aucune garde ne les lit.
  - `DECISIONS_LOT2.md` : B1 notée mergée (#1117) et bascule faite (« Ordonnancement et branches », B9).
- `node --test` des tests touchés (`check-rpc-contracts`, `textes-juridiques-ios`, `mobile-delivery-plan`,
  `contestation-paiement-soignant`, `paiements-staging-installed`) : 171 tests, 0 échec. La suite entière
  `tests/node/*.node.mjs` : 1 823 tests, 0 échec, 0 ignoré.
- `node scripts/mobile/check-textes-juridiques-ios.mjs` : 117 textes HARD STOP et 44 libellés identiques au web,
  26 zones de rendu retrouvées.
- `node scripts/mobile/check-rpc-contracts.mjs` : 33 RPC, aucune dérive ; `--update` ne produit aucun diff.
- `node scripts/mobile/export-golden-vectors.mjs` (2 793 vecteurs) et `export-demo-fixtures.mjs` (9 fichiers ;
  `--check` vert) : aucun diff.
- `JoleneCore` : `swift build --build-tests -Xswiftc -strict-concurrency=complete` sans erreur ni avertissement ;
  `swift test -Xswiftc -strict-concurrency=complete` : 655 tests XCTest, 0 échec (autant que de fonctions
  `test…` dans `Tests/`).
- `JoleneSupabase` : même build, sans erreur ni avertissement ; `swift test` : 274 tests XCTest, 0 échec. Les
  lignes `CoreData: error: Failed to create NSXPCConnection` viennent de l'environnement local, pas d'un échec.
- App : `xcodebuild build-for-testing` (schéma `Jolene`, Debug, `-destination 'generic/platform=iOS Simulator'`,
  `-derivedDataPath` dans le worktree, sans signature ni index) : `TEST BUILD SUCCEEDED`, cibles de tests UI
  comprises, sans erreur ni avertissement dans nos sources (seuls des avertissements de l'outil
  `appintentsmetadataprocessor`). Les sources de T3, T6 et T8 y sont compilées. Aucun test UI lancé. Aucune
  tranche n'ajoute ni ne retire de fichier à l'app : `xcodegen generate` a été lancé mais son seul écart (retrait
  du groupe vide `Jolene/Resources`, déjà présent sur `main`, dossier absent du dépôt) n'a pas été commité.
- Reste à prouver par la CI, à la PR vers `main` : le job « interface » d'`ios-swift-ci.yml` (simulateur, trois
  formats) et le job « packages » sous Xcode 26.4.1, y compris le test à horloge réelle signalé par m-6 de T3.

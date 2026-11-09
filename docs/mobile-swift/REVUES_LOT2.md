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

## L2-T4a

### Revue fraîche B8 — L2-T4a (n°1)

**Périmètre relu** : `git diff origin/feat/ios-lot2...origin/lot2/l2-t4a-v2`, 23 fichiers, +2602/−7, commits 8380f1cf (tests rouges) et 99c9014a (implémentation). Base 51b32cc8.

**Sources confrontées** :
- `src/pages/PresencesSoignant.tsx` et `src/components/pointage/BlocPointageMission.tsx` sur la base, numéros de ligne des `// source:` vérifiés un par un ;
- `PointageRotatifSoignant.tsx` ;
- `AccueilModel` et `AccueilScreen` du lot 1 ;
- `InstantanePresences`, `ListesPresences` et `PointageRules` de T3 ;
- `LOT2_PLAN.md` §3 T4a (v2), `LOTS_2_5_DECISIONS.md`, `DECISIONS_LOT2.md`, `PRINCIPES.md`, `CLAUDE.md`.

Revue en lecture seule : aucun build, aucun test, MCP non sollicité. Le diff ne touche ni le backend ni les gateways.

#### Verdict : **CLÔTURABLE**

Aucun bloquant, aucun majeur. Dix mineurs (détail dans `mineurs`).

#### Ce qui est correct

**Modèle (`PresencesModel`)**
- Il reproduit exactement les règles d'`AccueilModel` :
  - compteur `generation` : seul le dernier chargement publie et éteint `isRefreshing` ;
  - epoch relu après l'`await` ;
  - `CancellationError` et `.cancelled` ne sont jamais affichés en erreur ;
  - `.unauthorized` lève `sessionExpired` ;
  - un rafraîchissement ne démonte pas l'écran ;
  - pas de boucle de relecture après un échec ;
  - `verifierSession` relit l'instantané si l'epoch est inchangé.
- Concurrence propre : `@MainActor`, closure `@Sendable` pour `bounded`, aucune capture non Sendable.
- Onglet initial posé une seule fois, au premier succès, comme le `defaultValue` des onglets du web montés après le chargement.
- Listes calculées sur `InstantanePresences.chargeLe` (horloge figée l.107) ; blocs évalués sur l'horloge de l'appareil toutes les 30 s (décision 25).

**Parité web**
- `BlocPointageAffichage` couvre les trois motifs et la ligne « prochain créneau un autre jour » (l.84), avec le repli ponctuel réappliqué comme au l.43.
- `ResumeLignePresence` : segments EFFECTIF fermés hors pause, triés, avec repli sur les pointages de la présence legacy (l.664-682).
- `toFixed(1)` porté correctement : les égalités exactes sont les seuls x = impair/4.
- `getMethodeLabel`, `nom || 'Établissement'` et `· ville` sont conformes.
- Pas d'établissement de repli pour les présences validées (l.629), comme le web.
- États vides et actions vers les onglets conformes à `LinkRouter` : `/soignant/missions` et `/planning` vont vers Mes missions, `recherche-missions` vers Explorer.

**HARD STOP n°4**
- Aucun texte juridique nouveau ni reformulé.
- 50 libellés verbatim ; numéros de ligne vérifiés par échantillonnage, tous exacts.
- Vouvoiement limité à la personne (décision 9), et `LibellesPresencesTests` relit les sources web.
- « Contrat non signé » et sa phrase sont repris tels quels, comme l'exige le blueprint.
- `bandeauAValider` est verbatim (`TextesWeb`, l.658 du web), inscrit dans « En attente de Gabrielle ».

**Données sensibles**
- Aucune colonne `code_*` lue : le « Code : … » des l.722-726 est retiré, ce qui réduit le gap B1-ter.
- Aucune coordonnée, aucun log, aucun `attachText` de données métier.
- Seuls littéraux : les identifiants démo, déjà présents dans le dépôt (`DocumentsModelTests`, `UITestSupport`).

**Gaps verrouillés**
- Pas de bouton sans effet : la zone de pointage est un encart provisoire.
- « Voir le contrat », « Détail » et « Litige » ne s'affichent qu'avec le présentateur de T10, et l'XCUITest affirme leur absence.

**Tests**
- 42 tests unitaires pertinents, qui touchent des valeurs exactes, l'ordre, l'epoch, les chargements concurrents (portes `Gate`), le seuil des 60 s et le monde démo.
- 4 XCUITest sans attente fixe (tout passe par `require`), défilement borné dans le conteneur identifié. Ils tournent sur la matrice des 3 formats d'`ios-swift-ci.yml` : `-only-testing:JoleneUITests`, hors Staging uniquement.
- Les corrections après la phase rouge n'affaiblissent rien.

**Régressions lots 0 et 1**
- Déconnexion et sentinelle réseau ne bougent pas.
- `openDeletion` (2 à 6 glissements) absorbe les trois lignes ajoutées.
- `PlaceholderScreen` garde « Disponible au lot 1 » par défaut.
- `MainTabView` : une ligne modifiée.
- `pbxproj` : ajouts seuls.

#### Points à traiter (mineurs, non bloquants)

1. **m1** : `ZonePointageContexte` ne prévoit pas de relecture des présences après un scan. Le web relit après chaque scan (l.146-148) et la consigne T4b l'exige déjà. À ajouter maintenant, ou à attribuer explicitement à T4b.
2. **m2** : « Session à vérifier » et « Vérifier ma session » sont écrits en dur dans la vue et ne sont gardés par aucun test.
3. **m3** : une erreur qui n'est pas une `JoleneError` produit un message vide ; il faut un repli inventorié.
4. **m4** : le test « sans troncature » est en partie vide (libellé d'accessibilité forcé, texte non exposé).
5. **m5** : `model.listes` est recalculé 3 + n fois par affichage.
6. **m6** : filtres `paths` d'`ios-swift-ci.yml` incomplets (décision de l'intégrateur).
7. **m7** : la position de « Mon espace » sous « Application » est dictée par les tests ; à faire signer.
8. **m8** : le bandeau TL n'est protégé par aucun verrou en code avant T10.
9. **m9** : aucun XCUITest pour l'état d'erreur ni la reprise ; à confier à T4b avec les surcharges DEBUG.
10. **m10** : le rapport de l'auteur annonce 47 tests, le dépôt en compte 42.

#### Conditions de « livré » (hors verdict de code)

- Le xcresult CI doit être vert sur iphone, ipad-portrait et ipad-landscape, avec `DemoPresencesTests` en Passed et `skipped = 0`. Les XCUITest n'ont pas été lancés en local et PARITE les marque « à acquérir ».
- T4a ne pourra être déclarée livrée pour le bandeau « à valider » qu'après le go TL de Gabrielle (déjà consigné).

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- Branche d'intégration `int-lot2-v3` créée depuis `origin/feat/ios-lot2` (`51b32cc8`). Fusions `--no-ff`, dans
  l'ordre : `origin/main` (`2db9ac7c` : PR B9 #1119 et #1120), commit `0cd27dff`, sans conflit ;
  `origin/fix/ios-tests-instables` (`be551b66` : trois tests iOS instables du lot 1, dont `UITestSupport.swift`),
  commit `ecf3d6fd`, sans conflit ; `origin/lot2/l2-t4a-v2` (`99c9014a`), commit `334f2145`, sans conflit (T4a est la
  première des trois tranches fusionnées sur la base).
- #1119 réécrit `fn_etat_pointage_mission` par migration (`20261102210943`) sans re-baseline du dump
  `supabase/schema/public.sql` : aucune garde de `check-rpc-contracts.node.mjs` ne bascule à ce merge. La bascule
  éventuelle des fiches `fn_etat_pointage_mission` suivra la re-baseline (« Ordonnancement et branches »).
- La section « Mon espace » reste **sous « Application »** (choix de T4a ; m7, à faire signer) : T7 et T9a, écrits
  sans T4a, plaçaient leur ligne au-dessus de la déconnexion. Les aides de navigation de `DemoDocumentsTests` et de
  `DemoContratsTests` ont été adaptées à cette place à leur fusion (voir ci-dessous) ; celles des lots 0 et 1 lisent
  toujours la déconnexion et la sentinelle sans défilement.
- Mineurs m1 à m10 : non traités par l'intégration (aucun ne casse une vérification). m1 et m9 sont à attribuer
  à T4b.

## L2-T7

### Revue fraîche B8 — L2-T7 (n°1)

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur ; 11 mineurs, à corriger dans cette tranche ou à consigner.

#### Périmètre lu
- J'ai relu en entier `git diff origin/feat/ios-lot2...origin/lot2/l2-t7-v2` : 5 commits, 27 fichiers, +3 368 lignes.
- Fichiers ajoutés côté Core : `LibellesJustificatifs`, `PresentationJustificatifs`, `SelectionFichier`, `DemoSourcesDocument` et la ressource HEIC.
- Côté app : `MesDocumentsScreen`, `JustificatifsView`, `TeleversementSheet`, `AttestationSanteView`, `RecusJustificatifs`, les cinq vues médias, `EspaceSoignantSection` et `ProfileScreen`, `AppContainer`, le pbxproj (ajouts seulement).
- Composant : `StatusBadge`.
- Tests : 26 XCTest Core, 3 JoleneDesign, 7 XCUITest.
- Documentation : `DECISIONS_LOT2`, `PARITE_SOIGNANT`.
- Confrontés aux sources web `DocumentsSoignant.tsx`, `ModalTeleversement.tsx`, `MesDocuments.tsx` et `documents.ts`, à `DocumentsModel`, `DossierDocuments` et `DemoDocumentsGateway` (T6, inchangés), au blueprint v2 §3 T7, à D-FLAGS, aux consignes T7 de DECISIONS, à `LOTS_2_5_DECISIONS` et au CLAUDE.md.
- Supabase, en lecture seule :
  - aucun doublon `(profession, type_document)` dans `documents_requis_par_profession` ;
  - aucune exigence de type `CARTE_ORDRE`, `LICENCE_REMPLACEMENT` ou `ATTESTATION_SCOLARITE`, donc pas d'identifiants en double avec les documents complémentaires ;
  - les descriptions servies sont des données serveur, affichées telles quelles comme sur le web.

#### Points vérifiés, conformes
- **Parité des cartes** :
  - REJETE passe avant EXPIRE ; badges EN_ATTENTE en cours ou non conclue, REVUE_MANUELLE_REQUISE, API_INDISPONIBLE ; diplôme spécialisé à confirmer.
  - Ordre et conditions des boutons identiques au web : Revérifier, revue masquée pendant la vérification, Réessayer en bouton principal.
  - Séparateur « Documents optionnels », en-tête de progression, expirations à moins de 30 jours, incohérence (ponctuation du web reproduite à l'identique).
  - Documents complémentaires, `Statut à actualiser`, état « dossier à préparer ».
- **Écarts au blueprint** : tous consignés et justifiés, en particulier « Rejeté » et « Vérifié ✅ » sur les cartes (web l.763, l.697), suppression non portée, boutons vers le profil web retirés, encart RIB non porté.
- **HARD STOP n°4** :
  - Attestation reprise de `TextesWeb.AttestationSante`, mot pour mot, tutoiement compris.
  - Textes RCP et textes d'accès (l.623-634, l.866-869, l.882-884) non affichés et inscrits « En attente de Gabrielle ».
  - Vouvoiement limité aux libellés non juridiques (décision 9) et gardé par un test qui relit le web ligne à ligne.
  - 5 textes opérationnels inventoriés. Aucun texte juridique nouveau.
- **Envoi** :
  - Préparation hors du fil principal ; `source` toujours passée par le sélecteur.
  - Un seul envoi possible : garde `envoiLance` posée avant la suspension, feuille non fermable pendant l'envoi.
  - Issues relues par la gateway ; `nonEnvoye` vide la sélection.
  - `verify-document` n'est jamais relancé par l'écran ; compteur démo en DEBUG seulement.
- **Concurrence Swift 6** : coordinateurs `@MainActor`, closures `@MainActor @Sendable`, `IssueSelection` et `FichierSelectionne` `Sendable`, `CopiesConsultees` `@MainActor`.
- **Consultation** : seule la copie fermée est effacée (m2 de la revue T6), purge au nouvel epoch.
- **Sécurité et périmètre** :
  - Aucun log ni octet exposé, aucune chaîne ressemblant à un secret (identifiants du pbxproj de 24 caractères).
  - Aucun JoleneSupabase instancié en démo ; sentinelle réseau vérifiée en fin de parcours HEIC.
  - Section Profil ajoutée sans casser les recherches `network-sentinel` des lots 0-1 : environ 80 pt de plus, sentinelle toujours à l'écran.
- **XCUITest** :
  - Un seul jeu de tests pour les trois formats (`JOLENE_UI_ORIENTATION`, matrice CI), uniquement des `require` bornés, aucune attente par délai fixe.
  - Le verrou du gap « aucun bouton de renvoi sans présentateur » est asserté.

#### Constats mineurs (détail dans `mineurs`)
1. **Drapeau `ios_natif_documents_actif`** : l'écran natif démarre avant la lecture du drapeau ; pas de relecture au retour au premier plan (écart à D-FLAGS) ; pas de test de la valeur `false`.
2. **« cette page se mettra à jour »** : aucune réconciliation automatique ne suit une issue incertaine ; boutons d'envoi actifs dans cet état ; `suiviIllisible` laisse l'utilisateur sans recours.
3. **iPad à deux fenêtres** : la feuille se ferme sur l'issue de l'envoi d'une autre fenêtre ; le fichier choisi est perdu et un succès est annoncé.
4. **Attestation** : si la relecture échoue après une signature réussie, le bouton reste actif et une seconde signature réécrirait la date.
5. **Consultation tardive** : une copie orpheline reste sur disque jusqu'au prochain epoch.
6. **`messageAction` périmé** : il peut s'afficher dans la carte d'un autre document (remise à zéro faite après les gardes, dans le modèle T6).
7. **Bandeau d'incohérence** : il n'est pas relu après un envoi ou un verdict (le web le relit).
8. **Caméra** : une autorisation refusée n'affiche pas « Impossible d'accéder à la caméra. ».
9. **Démo** : une ressource HEIC absente devient une annulation silencieuse.
10. **XCUITest HEIC** : la vérification du verdict tombe pendant l'ouverture de la feuille suivante ; fragile.
11. **Release** : avertissement `var` jamais modifiée dans `AppContainer` (la CI ne compile pas Release).

#### Reste à prouver (hors verdict code)
- Par la CI sur Xcode 26.4.1 : XCUITest sur les trois formats et JoleneDesignTests, jamais lancés localement ; conversion HEIC → JPEG sur le simulateur de la CI.
- En recette appareil (T12) : les vrais sélecteurs (appareil photo, photothèque, Fichiers).
- Validation TL (P9) et relecture par Gabrielle des 5 textes opérationnels et des libellés vouvoyés, avant de déclarer T7 livrée.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot2/l2-t7-v2` (`d8fdb500`) après T4a, commit de fusion `ee95ef6a`. Trois conflits,
  tous résolus en gardant les deux tranches :
  - `Screens/Profil/EspaceSoignantSection.swift` (créé par T4a et par T7) : une seule section, avec l'en-tête de T4a
    (`LibellesPresences.EspaceSoignant.titreSection`, `profil-espace` ; même texte que `LibellesJustificatifs.monEspace`
    de T7, gardé à l'inventaire) et une ligne par tranche : `profil-presences` (T4a), `profil-documents` →
    `MesDocumentsScreen(container:session:snapshot:)` (T7, à la place de l'écran provisoire de T4a), `profil-contrats`.
    La section reçoit `container` (T7) et `ouvrirOnglet` (T4a).
  - `ProfileScreen.swift` (fusion automatique, deux insertions) : une seule insertion, sous « Application », à la
    place choisie par T4a ; la ligne de T7 au-dessus de la déconnexion est retirée.
  - `DECISIONS_LOT2.md` : lignes d'amendement de T4a puis de T7 ; dans « En attente de Gabrielle », le point TL de T4a
    (bandeau « à valider ») et le point T7 (bandeau RCP, textes d'accès, encart RIB).
  - `project.pbxproj` : régénéré par `xcodegen generate`, puis le groupe vide `Jolene/Resources` (présent sur `main` et
    sur toutes les branches du lot 2, retiré par xcodegen faute de dossier) réinséré : diff en ajouts seuls.
- Consigne T4a appliquée (règle 8) : `LibellesPresences.Provisoire.documents` est retiré, avec ses deux assertions de
  `LibellesPresencesTests`. `DemoPresencesTests.testMesDocumentsEtMesContratsProvisoiresJusquaT7EtT9a` migre vers
  `documents-screen` : onglet Justificatifs sélectionné, `placeholder-documents` absent. La ligne de l'inventaire est
  marquée « retiré à l'intégration de T7 ».
- `DemoDocumentsTests`, adapté à la place de la section : `ouvrirMesDocuments` exigeait que `profil-documents` existe
  avant de défiler, alors qu'une cellule hors écran d'une `List` est absente de l'arbre. Il défile désormais vers le bas
  de façon bornée, comme `DemoPresencesTests.tapDansProfil`. `retourAuProfilSansRequete` défilait vers le bas pour
  trouver la sentinelle, qui est maintenant au-dessus de « Mon espace » : `scrollTo(…, downward: false)`. Il exige
  la sentinelle entièrement visible, ce qui est plus strict qu'avant. Aucune assertion n'est retirée.
- Mineurs 1 à 11 : non traités par l'intégration (aucun ne casse une vérification).

## L2-T9a

### Revue fraîche B8 — L2-T9a (n°1)

**Verdict : CLÔTURABLE.** Aucun constat bloquant ni majeur, 8 mineurs.

**Périmètre relu.** J'ai lu en entier `git diff origin/feat/ios-lot2...origin/lot2/l2-t9a-v2` : 31 fichiers, +2 633/−8, commits `d03014a8` puis `eee12f05` sur la base `51b32cc8`. Je l'ai confronté aux sources web citées :
- `ListeContrats.tsx` et `ContratMission.tsx` (l.340-460 et l.520-841) ;
- `CertificatSignature.tsx`, `CertificatSignaturePage.tsx`, `Countdown72hSignature.tsx` ;
- `AccesEtablissement.tsx` l.75-88 et `SignerContratOtp.tsx` l.222-236.

Cadre de référence : le blueprint v2 §3 T9a, `LOTS_2_5_DECISIONS.md`, `DECISIONS_LOT2.md` et le CLAUDE.md du dépôt. Revue en lecture seule : aucun build, aucun test, aucun appel MCP Supabase.

#### Ce qui est correct

**Correction**
- Aucune écriture serveur dans T9a.
- `preparerPartage` vérifie l'epoch et efface la copie d'un epoch quitté. Une annulation n'est jamais affichée en erreur, et `.unauthorized` passe `sessionExpired` à vrai.
- Pas de double partage : garde `partageEnCours` et bouton désactivé.
- Les modèles appartiennent à leur vue (`@StateObject`, `.task`), donc une réponse tardive après un changement d'écran est abandonnée.
- Concurrence stricte respectée : `@MainActor` sur `Coordinateur`, `LecteurContratReference` et `ShareSheet`, saut explicite vers le fil principal depuis le KVO.
- Mineurs 1 et 4 de la revue de T8 corrigés : `meme` est utilisé dans `certificat()`, et le message vient de `LibellesWeb.Contrat.aucunTelechargeable`.

**Isolement du lecteur (décision 17)**
- JavaScript désactivé, stockage non persistant, aucun détecteur de données ni aperçu de lien.
- Six règles `WKContentRuleList` installées avant le chargement, sans alternative `|`. Si la compilation échoue, rien n'est chargé.
- CSP `default-src 'none'; style-src 'unsafe-inline'` injectée en tête du `<head>`, octets inchangés par ailleurs (testé, y compris sur les deux originaux de démo).
- `loadHTMLString(_, baseURL: nil)`, seul `about:blank` initial autorisé dans le cadre principal, nouvelles fenêtres refusées.

**Parité avec le web**
- Ordre de la page identique au web : bandeaux, compte à rebours, en-tête et statut, CDD à préparer, actions, document figé et lecteur, certificat, Signatures, zone « Votre signature », « déjà signé », pied de page.
- Règles `aSigner`, pastilles, états vides côté soignant, erreur `ErreurRubriqueEtablissement`, certificat en variante résumé (sans IP ni navigateur), page certificat avec empreinte, explication et mention.
- Dates en heure de Paris avec les masques date-fns du web.

**HARD STOP n°4**
- Chaque texte affiché vient de `TextesWeb` (TL, inchangé) ou de `LibellesWeb`. J'ai vérifié chaque `// source:` contre son fichier et sa ligne : tous sont exacts.
- La liste des fichiers épinglés par la garde Node est seulement complétée ; la garde n'est pas assouplie.
- Aucun texte juridique nouveau.

**Données sensibles et secrets**
- Aucun journal ajouté, aucune donnée OTP ou GPS. Le `storage_path` est affiché comme sur le web.
- Aucun littéral ressemblant à un secret.

**Régressions**
- `ProfileScreen` gagne une ligne, ce qui ajoute environ 80 pt à la liste. La sentinelle reste dans le premier écran sur iPhone 17 et sur iPad (A16) en portrait comme en paysage ; les tests du lot 1 qui la lisent sans défiler ne sont pas affectés.
- `MainTabView.onDisappear` s'exécute bien au changement d'epoch, car `RootView` applique `.id(snapshot.epoch)`.

**Tests**
- Les XCUITest sont attendus via les trois formats de la matrice CI, sans attente à durée fixe.
- Le gap « aucun bouton sans présentateur `.safari` » est verrouillé : le test affirme l'absence de `contrat-renvoi-web-action` et de `certificat-export`.

#### Constats mineurs

- **m1 — Point soumis à Gabrielle mal décrit.** Dans DECISIONS_LOT2 (l.554 et l.638), « Signature non disponible pour le moment » est présenté comme venant d'un contexte « document non prêt ». Sur le web, ce texte accompagne en réalité une erreur bloquante du serveur (CONTRAT_INACTIF, CONTRAT_DEJA_COMPLET, DEJA_SIGNE). La note dit aussi que le texte annonce la signature sur jolene.app, alors que l'écran natif ne le dit jamais. À corriger dans la doc pour que la décision soit éclairée.
- **m2 — Texte HARD STOP dans un contexte nouveau, non soumis.** Le lien `contrat-certificat-ouvrir` porte `TextesWeb.Certificat.titrePage` (texte juridique) dans un contexte que la page web du contrat n'a pas. À ajouter à « En attente de Gabrielle ».
- **m3 — « Imprimer » masqué sans original contrôlé.** Le web affiche toujours ce bouton. L'écart n'est pas documenté.
- **m4 — Dimensionnement du lecteur.**
  - La hauteur ne rétrécit jamais (grand blanc après une rotation iPad).
  - Un contenu plus large que la vue est coupé sans défilement possible.
  - Le test « sans débordement horizontal » ne vérifie que le cadre de la vue, pas le contenu.
- **m5 — Robustesse de la feuille de partage.**
  - `MainActor.assumeIsolated` dans le gestionnaire de fin plante si UIKit rappelle hors du fil principal.
  - Sur iPad multi-fenêtres, la scène choisie peut être la mauvaise.
  - La feuille est présentée sans vérifier que l'écran est encore affiché.
  - Le message affiché quand la présentation échoue est faux.
- **m6 — Effacement non testé, amendement inexact.** L'effacement de la copie au changement d'epoch et son déclenchement à la fermeture de la feuille ne sont pas testés. L'amendement l.558 surestime la preuve existante. Accessoirement, un test de JoleneDesign est tautologique.
- **m7 — Écarts de parité de la liste.**
  - `?statut=` n'est pas réappliqué sur une liste déjà montée (point d'attention pour T7 et T10).
  - Les puces de filtre restent affichées pendant le chargement et l'erreur.
  - « Réessayer » ne montre aucun chargement.
- **m8 — Rafraîchissement en échec.** Un tirer-pour-actualiser qui échoue remplace un contrat déjà chargé par « Contrat introuvable ».

#### Non prouvé, hors verdict

Aucun simulateur n'a tourné, et `ios-swift-ci` ne se déclenche que sur les PR et les pushs vers `main`. DemoContratsTests (lecture des textes de la WKWebView, identifiants `ActivityListView` / `UIActivityContentView` de la feuille système sous iOS 26) et JoleneDesignLot2Tests ne s'exécuteront donc qu'avec la PR du lot. T9a reste « en cours » tant que les xcresult des trois formats ne sont pas acquis et que Gabrielle n'a pas validé par écrit les textes TL, comme l'auteur l'indique. Le coupe-circuit `ios_natif_contrats_actif` (D-FLAGS) n'est consommé par aucun écran du dépôt, lot 1 compris : c'est un gap du lot entier, hors périmètre de T9a. Ce n'est pas une tranche B9.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot2/l2-t9a-v2` (`eee12f05`) après T4a et T7, commit de fusion `8734cf9a`. Six conflits,
  tous résolus en gardant les tranches :
  - `JoleneDesignLot2Tests.swift` (créé par T7 et par T9a) : une seule classe, avec les trois tests `StatusBadge` de T7
    puis les quatre tests `CountdownLabel` de T9a (7 tests), et les imports des deux côtés (`JoleneCore`).
  - `LibellesWebTests.swift` : le test de la page Présences (T4a) et les deux tests des contrats (T9a) ; 9 tests.
  - `tests/node/textes-juridiques-ios.node.mjs` : liste triée des fichiers web épinglés, `ListeContrats.tsx` (T4a et T9a)
    et `MesDocuments.tsx` (T4a). Elle est seulement complétée ; la garde n'est pas assouplie.
  - `PARITE_SOIGNANT.md` : lignes « Mes documents », « Justificatifs » et « DPAE » de T7, ligne « Contrats » de T9a,
    mises à jour pour le branchement ci-dessous et le test migré.
  - `DECISIONS_LOT2.md` : lignes d'amendement de T4a, T7 puis T9a.
  - `project.pbxproj` : régénéré par `xcodegen generate`, groupe `Jolene/Resources` réinséré, diff en ajouts seuls.
- Consigne « Intégration de T9a » (`DECISIONS_LOT2.md`), appliquée selon la règle 8 :
  - la ligne `profil-contrats` d'`EspaceSoignantSection` ouvre `ContratsDestination.liste(session:snapshot:)` ;
  - `ContratsEntreeProfil.swift` et sa ligne de `ProfileScreen` sont supprimés : sinon deux `profil-contrats`
    auraient coexisté ;
  - l'onglet Contrats de `MesDocumentsScreen` monte `ContratsDestination.liste(…, presentation: .onglet)` à la place du
    renvoi web, et `lienContrats` est retiré ;
  - `LibellesPresences.Provisoire.contrats` est retiré avec ses deux assertions ;
  - tests migrés :
    - `DemoPresencesTests.testMesDocumentsEtMesContratsNatifsDepuisMonEspace` : `contrats-liste` puis la carte
      `demo-contrat-001`, `placeholder-contrats` absent ;
    - `DemoDocumentsTests.testOngletContratsNatifEtDpaeEnRenvoiWeb` : liste native et carte, onglet sélectionné,
      `documents-contrats-renvoi` absent ;
  - `DemoContratsTests` est adapté à la place de la section : `openContrats` défile vers `profil-contrats` (borné) et
    `assertNoNetworkRequest` défile vers le haut jusqu'à la sentinelle entièrement visible. Aucune assertion n'est retirée.
  - **Non appliqué : « Voir le contrat » de `BlocPointageView`**. La mission c du monde démo a pour contrat
    `demo-contrat-pointage-c`, absent de `demo-contrats.json` : un bouton natif ouvrirait « Contrat introuvable » en
    démo. Le bouton reste un renvoi web rendu seulement avec le présentateur de T10 (gap verrouillé, absence affirmée
    par `DemoPresencesTests`). La consigne est complétée dans DECISIONS (« État après l'intégration du 8 novembre
    2026 ») : il faut ajouter ce contrat aux fixtures démo (T8), à confier à T4b ou à T10.
- Correctif d'intégration `b6f575f5`. T4a (`LibellesWeb.EspaceSoignant.mesContrats`) et T9a
  (`LibellesWeb.Contrats.titre`) annotaient tous deux `ListeContrats.tsx:101`. La garde n'attribue chaque occurrence web
  qu'à une constante : `check-textes-juridiques-ios.mjs` rougissait. La ligne du Profil lit désormais `Contrats.titre`.
  Le doublon est retiré du catalogue. `LibellesWebTests` affirme la même valeur et la présence de `Contrats.titre` au
  catalogue. Aucun texte affiché ne change.
- Mineurs : m1 et m2 sont traités dans `DECISIONS_LOT2.md`, puisqu'ils touchent la décision juridique de Gabrielle.
  Pour m1, la description du point « Signature non disponible pour le moment » est corrigée dans la ligne
  d'amendement et dans « En attente de Gabrielle » (erreur bloquante du serveur, l.222-236). Pour m2, le lien
  `contrat-certificat-ouvrir` est ajouté à « En attente de Gabrielle ». Aucun code n'est changé. m3 à m8 ne sont pas
  traités, aucun ne cassant une vérification. Les numéros de ligne de `DECISIONS_LOT2.md` cités par les trois revues
  sont ceux des branches des tranches ; ils ont bougé avec les fusions.
- Remarque sur « Non prouvé » : `ios-swift-ci.yml` accepte `workflow_dispatch`, et l'intégrateur l'a lancé sur
  `feat/ios-lot2` (section « Recette CI » ci-dessous).

## Vérifications après les fusions de T4a, T7 et T9a (intégrateur, 2026-11-08 et 2026-11-09)

Exécutées en local sur la branche d'intégration `int-lot2-v3`, poussée vers `feat/ios-lot2` (Node 24 ; Swift 6.1.2 de
Xcode 16.4 sur le poste, la CI utilisant Xcode 26.4.1). Rien n'a été écrit en production ni sur STAGING. Aucun MCP
Supabase n'a été interrogé et Playwright n'a pas été lancé. Seul `ios-swift-ci.yml` a été déclenché, par
`workflow_dispatch` (section suivante).

- Exporteurs, sans diff : `export-golden-vectors.mjs` (2 793 vecteurs), `export-demo-fixtures.mjs` (9 fichiers),
  `check-rpc-contracts.mjs` (33 RPC, aucune dérive ; `--update` ne change rien). Aucune RPC nouvelle n'est câblée par
  T4a, T7 ou T9a.
- Garde textes-juridiques-ios (`check-textes-juridiques-ios.mjs`) : rouge après la fusion de T9a (doublon « Mes
  contrats », correctif `b6f575f5`), puis verte : 117 textes HARD STOP, 137 libellés identiques au web, 38 zones de
  rendu retrouvées.
- `node --test` : tests touchés (`textes-juridiques-ios`, `check-rpc-contracts`, `allouer-capacite-sms-signature-staging`,
  `visibilite-etablissement-permission`, `mobile-delivery-plan`) : 194 tests, 0 échec. Suite entière
  `tests/node/*.node.mjs` : 1 862 tests, 0 échec, 0 ignoré. Après les corrections de DECISIONS, les gardes qui la
  relisent ont été rejouées : 155 tests, 0 échec.
- `JoleneCore` : `swift build --build-tests -Xswiftc -strict-concurrency=complete` sans avertissement ; `swift test` :
  750 tests XCTest, 0 échec (avant et après le correctif `26d04fbb`).
- `JoleneSupabase` : même build, sans avertissement ; `swift test` : 276 tests XCTest, 0 échec.
- App : `xcodebuild build-for-testing` (schéma `Jolene`, Debug, `generic/platform=iOS Simulator`, `-derivedDataPath`
  dans le worktree, sans signature ni index) : `TEST BUILD SUCCEEDED`. Toutes les cibles sont compilées : Jolene,
  JoleneCoreTests, JoleneSupabaseTests, JoleneDesignTests, JoleneUITests. Aucun avertissement dans nos sources (seuls
  ceux d'`appintentsmetadataprocessor`). Relancé après le correctif `826b466e`, avec le même résultat.
- `xcodegen generate` relancé à chaque fusion. Le pbxproj ne comporte que des ajouts : le groupe vide
  `Jolene/Resources`, retiré par xcodegen, a été réinséré.
- Correctifs d'intégration révélés par la CI :
  - `26d04fbb` : `DocumentsModelTests.swift:659` (T6) : `weak var` jamais réaffecté, signalé par Swift 6.2
    (#WeakMutability), qui faisait rougir le job « Packages ». La référence faible passe par une liste de capture ;
    l'assertion est identique.
  - `826b466e` : `DemoPresencesTests.testOngletsDesPresencesLisiblesSansTroncature` (T4a). **Le test était faux, pas
    le code** : il comparait au plus près une hauteur relue en virgule flottante (43,99999999999997 pt pour
    `minHeight: 44` sur iPhone 17). La comparaison se fait désormais au millième de point, très en deçà d'un pixel.
  - `ce5f5e3e` : `ios-swift-ci.yml`. Les tests UI passent en deux éclats successifs (« socle », « lot2 ») bornés à
    30 min chacun, comme le prévoit la décision 22. Le résumé additionne les deux xcresult et garde toute la porte. Il
    a été rejoué en local sur le résumé et les captures réels du run 42532108708 : vert, puis rouge sur un code
    absent, une orientation fausse ou une classe non démarrée. Le plafond du job passe à 75 min. Aucun test n'est
    retiré ni ignoré : 818 tests par format avant et après le découpage.
- Nettoyage : chaque `.build`, chaque `DerivedData` du worktree et chaque artefact CI téléchargé ont été supprimés
  après usage. Le lien `node_modules` est retiré à la fin.

## Recette CI `ios-swift-ci.yml` sur `feat/ios-lot2` (intégrateur, 2026-11-08 et 2026-11-09)

Déclenchée par `gh workflow run ios-swift-ci.yml --ref feat/ios-lot2` (Xcode 26.4.1, iOS 26.2, iPhone 17 et iPad (A16)).

| Run | Commit | Cœur | Packages | UI iphone | UI ipad-portrait | UI ipad-landscape |
|---|---|---|---|---|---|---|
| [42528556340](https://github.com/Gabpcd/JJJJJ/actions/runs/42528556340) | `b6f575f5` | vert | rouge (1 avertissement Swift 6.2, `DocumentsModelTests.swift:659`) | rouge : 817 réussis, 1 échoué (44 pt, test faux), 0 ignoré, 818 au total | vert : 818 / 0 / 0 / 818 | vert : 818 / 0 / 0 / 818 |
| [42532108708](https://github.com/Gabpcd/JJJJJ/actions/runs/42532108708) | `826b466e` | vert | vert (750 + 276 tests, 0 avertissement) | rouge : étape de tests au-delà de 30 min (815 réussis au moment de la coupure, aucun échec) | vert : 818 / 0 / 0 / 818 | rouge : étape de tests au-delà de 30 min (aucun échec avant la coupure) |
| [**42536866359**](https://github.com/Gabpcd/JJJJJ/actions/runs/42536866359) | `ce5f5e3e` | **vert** | **vert** : JoleneCoreTests 750, JoleneSupabaseTests 276, 0 avertissement | **vert** : socle 804 + lot2 14 = 818 réussis, 0 échoué, 0 ignoré, 53 captures portrait | **vert** : 804 + 14 = 818 réussis, 0 / 0, 53 captures portrait | **vert** : 804 + 14 = 818 réussis, 0 / 0, 53 captures paysage |

- Run 42536866359 : `result = Passed` pour chaque éclat, `skipped = 0`, `failed = 0`, `passed = total`. Les classes
  `DemoPresencesTests` (4 tests), `DemoDocumentsTests` (7) et `DemoContratsTests` (3) ont démarré et réussi sur les
  trois formats ; c'est la première exécution des XCUITest de T4a, T7 et T9a (« à acquérir » dans PARITE), ainsi que
  des tests `JoleneDesignLot2Tests`.
- Durées des éclats, socle puis lot2 : iphone 13,3 puis 19,7 min ; ipad-portrait 10,7 puis 11,2 min ; ipad-landscape
  13,1 puis 20,7 min. L'éclat « lot2 » dépasse le seuil de 20 min de la décision 22 en paysage : il est à séparer par
  domaine avant que T4b y ajoute ses tests (consigne dans DECISIONS, décision 22). Durées de build-for-testing :
  249 s, 299 s, 223 s.
- Ce que la CI ne prouve pas : la recette appareil (T12), les écrans STAGING (T11) et la validation des textes par
  Gabrielle (TL, P9). Les points HARD STOP de T4a, T7 et T9a restent dans « En attente de Gabrielle ».

## L2-T4b

### Revue fraîche B8 — L2-T4b (n°3)

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur ; 7 mineurs et 1 remarque de forme.

Périmètre lu : `git diff origin/feat/ios-lot2...origin/lot2/l2-t4b-v2`, soit 13 commits et 60 fichiers, de `855753a3` à `3775f75c`. J'ai relu en particulier le delta de la revue n°2 (`885fa96e..3775f75c`). En complément :
- sources web relues sur la branche : ConsentementGPS, PresencesSoignant, PointageRotatifSoignant, BandeauHorsLigne, BandeauSansGPS, SectionPreferences, ProfilSoignant, platform.ts ;
- dump `public.sql` relu ;
- MCP Supabase en lecture seule, deux requêtes `SELECT` en production : `pg_get_functiondef` et un balayage de `pg_proc`.

#### Vérifié et conforme

##### Corrections de la revue n°2
- **MJ1 (course entre XCUITest et feuille du scanner)** : en DEBUG, `DemoQRScannerView` ne lit plus rien seul ; la lecture part de `pointage-scanner-demo-lire`. `ouvrirScanner` attend un état stable (feuille ouverte et bouton présent). Les trois scénarios QR sont sans course. Les étapes communes sont dans `DemoPointageUITestCase`, classe sans test.
- **m1 (Profil)** : `LigneProfil.sessionAVerifier` l'emporte sur tout autre état ; `verifierSession`, puis `reprendreApresSession`, sans rejeu ; pas de doublon du message.
- **m2 (simulation d'interface)** : scénarios démo réalistes. `ExpirationSessionDemo` est partagée avec `DemoAuthGateway.restoreSession`. Le 401 arrive après application du scan, ce qui prouve qu'il n'y a pas de renvoi. `SessionController.start()` garde l'epoch pour la même identité : la reprise est cohérente.
- **m3 (coupe-circuit)** : `ios_natif_presences_actif` est lu, fail-open. La surcharge `-JOLENE_FLAG_` n'existe qu'en DEBUG.
- **m6 (CI)** : build borné à 25 min ; cinq éclats de 30 min ; plafond du job à 195 min. Chaque nouvelle classe figure dans les `-skip-testing` du socle et dans les `classes` du résumé.
- **m7** : la garde d'environnement passe avant la construction de l'appareil.
- **m8 et m9** : traités.

##### Correction et concurrence
- **Envoi unique** : `enCours` et `preparation` sont posés avant tout `await`, et le code en attente est pris et vidé de façon synchrone. Le Toggle passe par un `Task`, mais la garde `!enCours` laisse un seul `fn_consentir_gps`.
- **Valeur relue** : elle fait foi partout (`enregistrer`, puis relecture par la gateway).
- **Changement d'identité ou de vue** : `estCourant` est vérifié après la RPC et l'audit, et `nil` est rendu sans demander l'autorisation iOS. `PointageModel` reste protégé par `actif` et par la génération.
- **Aucune hypothèse locale** :
  - en cas d'échec, rien n'est envoyé et la feuille revient au pointage suivant ;
  - un consentement illisible donne un pointage sans position ;
  - la précision réduite n'envoie aucune coordonnée.
- **Session expirée** : `AffichageZonePointage` donne la priorité au bloc « Session à vérifier ». `verifierSession` relit sans renvoyer le code (tests Core et XCUITest).
- **Swift 6** : les objets observés sont `@MainActor`. `DiffusionDernierEtat` diffuse sous verrou et appelle `finish()` hors du verrou, ce qui évite un interblocage. `DemandesPosition` ne reprend sa suite qu'une seule fois. Aucune `CLLocation` ne traverse la frontière d'isolement.
- **Démo** : `NWPathMonitor`, `CLLocationManager` et le trousseau ne sont pas créés en démo. `DemoNoNetworkTests` reste valable : JoleneCore n'importe pas `Network`.

##### Serveur (définition live, 09/11)
- `fn_scanner_code_pointage` contient bien le verrou `FOR UPDATE`, l'anti-rejeu de 2 min (dump l.55710-55713) et la boucle `sp.code_saisi = v_new_code` (l.55885). Ne pas mettre de file hors ligne est donc justifié (décision 2).
- La seule fonction qui met à jour `scans_pointage` est `fn_supprimer_mon_compte`, et aucun cron ne la purge : le constat de D-T4b-0 et D-T4b-3 est confirmé.

##### Juridique (délégation du 08/11)
- **Textes verbatim** : les textes TL (feuille, bandeau, retours, Profil) sont repris mot pour mot ; les XCUITest les affirment au caractère près.
- **Sources RGPD** : exactes, à la réserve de m2 sur la glose de l'art. 7 §1.
  - art. 4 point 11, art. 6 §1 a), art. 7 §1 et §3, art. 13 §1 c), §2 a) et c), art. 5 §1 e) ;
  - considérants 32 et 42 ;
  - CJUE, 1er octobre 2019, *Planet49*, C-673/17 (JUGÉ).
- La ligne « Décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026 » figure sous D-T4b-0, D-T4b-1 (et son amendement), D-T4b-2 et D-T4b-3.
- **Lignes web citées** : exactes (ConsentementGPS l.18, 25-64, 38, 50 ; PresencesSoignant l.67-76, 87-95, 306-313, 509 ; ProfilSoignant l.194 ; SectionPreferences l.128-168 ; BandeauHorsLigne l.71-81), sauf `pointerDepart` (m1).
- **Textes opérationnels** : inventoriés et vouvoyés, sans marque juridique.

##### Tests
- Les tests Core sont substantiels : double toucher, epoch quitté pendant la RPC puis pendant l'audit, diffusion concurrente répétée 200 fois, scénarios de bout en bout dans le monde démo.
- Les XCUITest couvrent les trois formats via la matrice, sans aucun `XCTSkip` ni attente par délai fixe.
- Les affirmations de compte passent par `compteursRelus`, qui exige une lecture postérieure à l'action.
- Les tests migrés (DemoPresencesTests, DemoContratsTests) ne sont pas affaiblis.

##### Sécurité et données
- Aucune coordonnée, aucun code, aucun payload QR n'est journalisé ; `FixPosition` masque sa description et sa réflexion.
- Aucun littéral de type secret : seuls le mot de passe démo (motif existant) et un `hash_document` SHA-256 de même nature que T8.
- Aucun fichier hors périmètre.

#### Mineurs (ne bloquent pas la clôture)
1. **m1** — Source inexacte : `pointerDepart` (l.386) n'ouvre pas la feuille. À corriger dans ConsentementGpsModel.swift l.11-13, DECISIONS_LOT2 (amendements) et PARITE (d).
2. **m2** — D-T4b-3 : écrire que la purge B9 (ou une correction du texte web) bloque toute diffusion de T4b à de vrais utilisateurs. Le natif est le seul parcours qui sollicite activement ce consentement, sur une durée « 1 an » que la production ne respecte pas pour `scans_pointage`. Corriger aussi la glose de l'art. 7 §1.
3. **m3** — Aperçu caméra non orienté sur iPad en paysage (QRScannerView.swift l.84-87 et l.130-135) : RotationCoordinator, et vérification en recette T12.
4. **m4** — Références périmées : PointageRules.swift l.14 (l.55649 → l.55698) et Lot1Results.swift l.175 (l.70243 → l.70290).
5. **m5** — Message 401 affiché deux fois en tête de la page Présences (PresencesScreen.swift l.159-163) : filtrer comme `retourLigneProfil`.
6. **m6** — `LocationService.demanderAutorisation` sans borne (l.36-42) : la feuille de consentement peut rester bloquée si CoreLocation ne rappelle jamais.
7. **m7** — `tapDansProfil("profil-presences")` après un défilement vers le bas (DemoPointageTests l.291) : défiler vers le haut.
8. **Remarque de forme** — le pbxproj retire un groupe `Resources` vide (sans effet).

#### Reste à prouver (hors verdict de code)
- Premier run `ios-swift-ci.yml` vert sur les trois formats, avec la durée de chaque éclat : `DemoPointageTests` (10 tests) et `DemoPointageEtatsTests` (4 tests) n'ont été que compilés.
- Recette appareil T12 et revue P9 de Gabrielle sur iPhone.
- PR B9 de purge (D-T4b-3), PR web pour NULL coché (ProfilSoignant.tsx l.194), drapeau `ios_natif_contrats_actif` confié à T10.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-09)

- Ordre de la vague 4, sur la branche d'intégration `int-lot2-v4` créée depuis `origin/feat/ios-lot2` (`855753a3`) :
  `origin/main` (`f9a8c236`, #1122 et #1115, sans conflit, commit `58769fdb`), puis `origin/fix/ios-tests-instables`
  (#1125, deux derniers commits `a0c61c0b` et `454c88ec`, commit `2ff5c7fd` : seul le pbxproj était en conflit,
  `RequireWait.swift` gardé avec les fichiers du lot 2), puis T4b.
- `git merge --no-ff origin/lot2/l2-t4b-v2` (`3775f75c`), commit de fusion `580ea910`. Un seul conflit, le pbxproj,
  résolu par `xcodegen generate` : `RequireWait.swift` de #1125 et les fichiers de T4b. Le groupe vide `Jolene/Resources`
  disparaît, comme sur la branche de T4b (remarque de forme de la revue) : il n'est plus réinséré, `xcodegen` fait foi et
  le dossier n'existe pas. `ios-swift-ci.yml` a fusionné seul : éclats par domaine de T4b et relevé des attentes bloquées
  de #1125 (voir le correctif `bff6be3c` ci-dessous).
- T4b est intégrée **avant** T5a, comme le demande le mineur 8 de la revue de T5a.
- Mineurs m1 à m7 non traités par l'intégrateur : aucun ne casse une vérification. Ils restent à la tranche du pointage
  suivante (m3 et m6 relèvent aussi de la recette appareil T12).

## L2-T5a

### Revue fraîche B8 — L2-T5a (n°2)

**Verdict : CLÔTURABLE** : aucun bloquant, aucun majeur, 9 mineurs.

J'ai relu en entier `git diff origin/feat/ios-lot2...origin/lot2/l2-t5a-v2` (54 fichiers, 6 commits jusqu'à `b56902d3`). Rien n'a été modifié, compilé ni testé. En production (projet `flripxtsyegjshnhzjkz`), je n'ai fait que des `SELECT` de catalogue (`pg_get_functiondef`).

#### Ce qui a été vérifié et tient

- **Correction et concurrence**
  - `NotationModel` :
    - un seul envoi à la fois : la garde `peutEnvoyer` est synchrone sur le MainActor ;
    - pendant l'envoi, la saisie et « Plus tard » sont bloqués, et la feuille ne se ferme pas par glissement ;
    - si l'epoch change pendant la relecture de `fin_le` ou pendant l'envoi, rien n'est publié ;
    - si la tâche est annulée, rien n'est mémorisé ;
    - « déjà notée » est silencieux, un refus serveur est affiché tel quel, une erreur de transport affiche un texte inventorié ;
    - une fermeture décidée par le modèle n'efface plus le remerciement.
  - `DetailPresencesModel` :
    - la lecture la plus récente gagne (compteur de génération) ;
    - une annulation n'est jamais affichée comme une erreur ;
    - `.introuvable` et la carte masquée sur `{error}` fonctionnent ;
    - la relance n'envoie qu'une demande à la fois, avec le message serveur tel quel.
- **Gateway Supabase**
  - Les sept clés exactes sont envoyées, avec `p_commentaire: null`, en un seul POST.
  - `P0001` est déclarée. Messages et contrat relus en live : « Mission déjà notée pour ce sens », « La notation n’a pas pu être enregistrée. Veuillez réessayer. », « Non authentifié ».
  - `ficheDetail` lit des projections imposées : ni `select=*`, ni coordonnées, ni code. `ResumePresencesServeur` n'a pas de champ `heures_reelles`.
- **Parité avec `DetailPresencesMission.tsx` l.193-703**
  - En-tête, progression, synthèse (retard, départ anticipé, pauses, distance, déficit à 90 %, bilans), segments par jour, statuts de validation, contrôles et `presenceEnAttente` : relus ligne à ligne, conformes.
  - Écarts consignés : taux horaire de l'en-tête et récapitulatif financier non portés, « Planning indisponible » remplacé par l'écran d'erreur, ligne « ⏱ » omise si la durée est nulle.
- **Parité avec `WidgetAllerPointer` et `missionProchaine`** (DashboardSoignant l.282-320) : conforme, sauf le rafraîchissement (m2).
- **Juridique délégué** — sources primaires vérifiées :
  - PageCGU l.48, l.50, l.109 et l.115 : texte exact ;
  - `dec_definir_type_paiement` l.1537-1564 et l.1550-1555, relu en live (`BULLETIN_PAIE`/`DIRECT`) ;
  - `fn_valider_presences_72h_auto` : paramètre `delai_autovalidation_presence_h`, s'applique à toutes les présences, exclusions conformes à ce qui est écrit ;
  - `fn_etablissements_safe` l.35093 et l.35116-35120, `pol_mission_select` l.79410 ;
  - lecteurs de `heures_ajustees_litige` : l.13334-13338, l.14074-14079 et l.14702-14706.
  - La force de chaque source est indiquée, la déduction sur la phrase « salarié » est explicitée, et la ligne « Décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026 » est présente.
  - Les textes de relance sont affichés tels que le web les écrit, tutoiement compris. Aucun texte juridique n'est reformulé.
- **Notes jamais lues**
  - La garde Node `lecture-notes-ios` est solide : découpage lexical, exclusion unique et comptée, test de mutation permanent, lancée par `validate-pr`.
  - Aucune requête du diff ne vise `notations_missions`.
- **Données sensibles** : aucun log, aucun littéral ressemblant à un secret, aucune coordonnée GPS ni aucun code lu.
- **Correction de M3** : le récapitulatif financier est une route forcée web, l'identifiant est restreint à `[A-Za-z0-9-]`, et un test prouve que ce renvoi ne dépend pas de `LinkRouter`.
- **XCUITest**
  - Attentes par `require` (sondage), jamais par délai fixe.
  - La sentinelle « 0 requête » est relue à la fin des deux parcours.
  - La classe est ajoutée à l'éclat `lot2`, contrôlé par la gate pour chaque format.
- **Régressions** : identifiants migrés (`accueil-oubli-pointage-action` retiré, `accueil-oubli-depart` et `accueil-pointer` affirmés absents en démo normale) ; `portsEnAttenteLot2` vaut `["contestation"]` ; retrait sans effet du groupe vide `Resources` du `pbxproj`.

#### Mineurs (détail dans `mineurs`)

1. **Hors périmètre, à remonter en B9.** `fn_presences_detail_mission` (live) : avec `mon_etablissement_id()` NULL, la garde d'accès vaut NULL et laisse passer. Tout soignant connecté peut lire les données de présence de n'importe quelle mission dont il connaît l'id. À consigner, puis PR serveur séparée.
2. **Widget « Aller pointer » figé.** Aucune minuterie, alors que le web recalcule toutes les 30 s ; le texte de l'écart est inexact.
3. **Relecture en échec.** Elle remplace le détail affiché par l'écran d'erreur, ce qui contredit le choix fait en T4a.
4. **Lignes de `public.sql` périmées** (décalage d'environ 43) dans quatre commentaires de gateway et de démo.
5. **`@StateObject` de la notation lié à l'identité de la vue**, pas à `missionId` : ajouter `.id(missionId)` ou une consigne à T4b.
6. **Titre de navigation** « Synthèse des présences » au lieu du titre de la page web.
7. **Retours silencieux** de `proposer()` et `envoyer()` quand il n'y a pas de gateways (cosmétique).
8. **Ordre d'intégration** : intégrer T4b avant T5a, sinon « Pointer mon départ maintenant » mène à une page où le départ ne peut pas être pointé.
9. **Mentions périmées** dans la documentation et un commentaire (`PresentateurRenvoiWeb.swift` l.18, `LOT1_PLAN.md` l.306, `DECISIONS_LOT2.md` l.756).

#### Reste à acquérir avant « livré » (déjà consigné)

- `DemoPresenceDetailTests` est compilé mais pas lancé : l'éclat `lot2` doit passer au vert sur iPhone, iPad portrait et iPad paysage.
- P10 « notation » attend la ligne `.notationAuDepart` de T4b, la fixture `fin_le` ≤ 00h30 UTC et le XCUITest sur les trois formats.
- Revue de l'écran sur iPhone par Gabrielle (P9).

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-09)

- `git merge --no-ff origin/lot2/l2-t5a-v2` (`b56902d3`) après T4b (mineur 8), commit de fusion `dd42b263`. Sept conflits,
  tous résolus en gardant les deux tranches :
  - `ios-swift-ci.yml` : l'éclat « lot2 » de T5a n'existe plus (découpage par domaine de T4b) ; `DemoPresenceDetailTests`
    rejoint l'éclat de son domaine, « presences » (`DemoPresencesTests`, `DemoPointageEtatsTests`,
    `DemoPresenceDetailTests` : 4 + 4 + 4 tests), est exclue du socle et exigée par le résumé (règle de T4b : « une nouvelle
    classe démo du lot 2 rejoint l'éclat de son domaine ») ;
  - `AppContainer.swift` : scénarios de pointage de T4b (`DemoPointageGateway.Scenario`) puis scénario `accueil-pointage`
    de T5a, dans le même bloc DEBUG ;
  - `DemoPresencesTests.swift` : en-tête des deux tranches (« Voir le contrat » natif depuis T4b, « Détail » natif depuis
    T5a ; seul « Voir ou signaler un litige » reste un gap verrouillé). Le corps du test a fusionné seul : l'assertion
    positive de T5a sur `presence-historique-detail-…` et les assertions de T4b sur la zone de pointage et « Voir le
    contrat » sont toutes gardées ;
  - `tests/node/textes-juridiques-ios.node.mjs` : `BandeauHorsLigne.tsx` (T4b) et `BandeauOubliDepart.tsx` (T5a) dans la
    liste des fichiers web épinglés, qui n'est que complétée ;
  - `DECISIONS_LOT2.md` : lignes d'amendement des deux tranches, section « Textes opérationnels hors web (T5a) » et une
    seule section « Décisions déléguées du 8 novembre 2026 » (T5a l'avait recréée après « Actions manuelles ») ;
  - `PARITE_SOIGNANT.md` : ligne Présences de T4b, écarts (3) et (5) de T4a mis à jour pour T5a ; la ligne du détail cite
    l'éclat « presences » ;
  - `project.pbxproj` : `xcodegen generate`.
- **Conflit sémantique révélé par la compilation** (correctif `bff6be3c`) : `DemoPointageGateway.ficheDetail` (T5a)
  appelait `verifier(context)` sans `await`, alors que T4b a rendu `verifier` asynchrone (session démo expirée). Erreur de
  compilation de JoleneCore sur le résultat fusionné, corrigée par `try await verifier(context)` ; le comportement est
  celui des autres lectures de la gateway démo.
- **Consigne restée ouverte : la notation au départ final.** `.notationAuDepart` (point d'extension de T5a) n'est posé
  nulle part : T4b a été développée sans `NotationSheet.swift`. La brancher est une fonctionnalité avec ses propres tests
  (ligne dans `PointageCodeView`, mission démo à `fin_le` ≤ 00h30 UTC, XCUITest sur trois formats) : elle n'est pas
  ajoutée par l'intégrateur et reste consignée dans `DECISIONS_LOT2.md` (« État après l'intégration du 9 novembre
  2026 »). P10 « notation » n'est pas livrée.
- Mineurs : m8 appliqué (ordre d'intégration) ; m1 (garde NULL de `fn_presences_detail_mission`) est déjà couvert par le
  renvoi B9 « Gardes NULL des fonctions `SECURITY DEFINER` » de `DECISIONS_LOT2.md`, qui cite cette fonction ; m2 à m7
  et m9 ne cassent aucune vérification et ne sont pas traités.

## L2-T9b

### Revue fraîche B8 — L2-T9b (n°2)

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur, 5 mineurs.

**Périmètre relu** : `git diff origin/feat/ios-lot2...origin/lot2/l2-t9b-v2` en entier.
- Base `855753a3`, commits `dd977dcc` → `44fda8db`, 24 fichiers.
- Confronté au web : `SignerContratOtp.tsx` l.1-355 ; `ContratMission.tsx` l.280-330 et l.700-840.
- Confronté au blueprint v2 (§3 T9b), à `LOTS_2_5_DECISIONS.md` et à `DECISIONS_LOT2.md`.
- Lecture seule, aucun build ni test lancé.
- MCP Supabase, lecture seule en production : les longueurs live de `fn_envoyer_otp_signature(uuid)` (8 349) et de `fn_signer_contrat_otp(uuid,text,text,text)` (7 364) correspondent à celles consignées. La branche `otp_envoye_a < now() - interval '10 minutes'` → `statut_signature = 'expire'` + `OTP_EXPIRE` est confirmée, ainsi que `x-forwarded-for`, `JOLENE_OTP` et les 5 tentatives.

#### Corrections de la revue n°1 : vérifiées
- **M1, éclat CI « contrats »**
  - Il porte `DemoContratsTests` et `DemoSignatureContratTests` en `-only-testing`.
  - Les deux classes sont retirées de « lot2 », exclues du socle et exigées par le résumé.
  - L'éclat est relié à `CODE_CONTRATS`, à la boucle xcresult et à l'artefact. Il est borné à 30 min, tourne avec `if: always() && …` et le plafond du job est de 105 min.
  - La garde `tests/node/ios-swift-ci-eclats.node.mjs` est cohérente et tourne dans le job Cœur ; elle est ajoutée aux filtres de chemins.
- **m1, relecture après `.signee`**
  - La relecture est relancée une fois, puis « Réessayer » est proposé ; l'écran n'est jamais démonté et le code n'est jamais renvoyé.
  - `.unauthorized` → `sessionExpired` ; une annulation ne publie rien.
  - `charger()` remet à zéro `sessionExpired` et `erreurRelecture`.
  - Les tests couvrent ces chemins.
- **m2** : admission ouverte jusqu'à `canSend ? expiresAt : otpExpiresAt`, conforme aux l.310-312. Comme `otpExpiresAt` est borné par la capacité, cela équivaut au web.
- **m3** : l'ordre des conditions du `guard` est correct, et `demanderEnvoi`/`demanderSignature` sont synchrones sur le MainActor. Un double appui donne une seule requête (test `async let`).
- **m4** : corrigé dans la source et dans DECISIONS ; il reste un commentaire de test (mineur 4).
- **m5, m6** : appliqués ; une glose subsiste sur eIDAS 25 §2 (mineur 5).
- **m7** : placeholder « 123456 » (l.316), gardé par TL.
- **m8** : `annonceALApparition` ajouté.
- **m9** : le test se termine par `goBack` ×2 puis `assertNoNetworkRequest`.
- **m10, m11** : consignés.

#### Points contrôlés sans défaut
- **Parité web**
  - Conditions `disabled` respectées : l.284, 317, 335 et 344.
  - Tentatives affichées seulement sous 5 (l.322).
  - Alerte bloquante qui masque le retour (l.250-264).
  - Indisponibilité réservée à `CONTRAT_INACTIF`, `CONTRAT_DEJA_COMPLET` et `DEJA_SIGNE` (l.223-235).
  - Minuteur dérivé de l'échéance, « Expiré », « Recevoir un nouveau code ».
  - « numéro masqué » quand le numéro manque.
  - `actionsSuspendues` (l.265 et l.271).
- **Écarts au web** : tous consignés dans les Amendements (confirmation persistante, `OTP_EXPIRE` local, scénario `compte-test`, case de consentement en bouton, champ du code).
- **Aucun succès supposé**
  - La gateway relit la preuve, puis le modèle relit le contrat et le certificat avant de publier.
  - Après un échec de transport, un délai épuisé ou un refus de fermeture, l'état est relu, sans second envoi.
- **Concurrence et identité**
  - L'epoch est vérifié avant et après chaque requête OTP.
  - Une réponse caduque est ignorée grâce au jeton et à la clé de session.
  - L'opération en cours désactive les boutons (anti double envoi).
- **Données sensibles**
  - Le code est masqué dans `description`, `debugDescription` et `Mirror` (session, demande, nature), et effacé après la signature.
  - Le champ n'a ni correction automatique ni vérification orthographique.
  - Aucun journal.
  - Aucun littéral ressemblant à un secret ; seuls figurent les identifiants démo déjà existants.
- **Juridique**
  - Tous les textes affichés sont verbatim (TL).
  - La décision déléguée est consignée avec la ligne « Décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026 ».
  - Les références fichier:ligne du web ont été vérifiées : l.216, 230, 242-245, 265, 276, 288, 316, 319, 348 ; ContratMission l.721/724/729/740/741/743/749-750/836 ; CertificatSignaturePage l.214.
  - C. civ. 1366, 1367 al.1-2 et 1174 al.1, le décret 2017-1416 (présomption réservée à la signature qualifiée, abrogation du décret 2001-272) et eIDAS 25 §1 et 26 sont cités exactement.
  - CPC 287 dernier alinéa, rédaction du décret 2017-892, et C. civ. 1353 al.1 sont conformes à ma connaissance des textes ; un contrôle Légifrance reste conseillé.
- **XCUITest**
  - Les 3 cas tournent sur les 3 formats via la matrice.
  - Les attentes se font par `require` (sondage), sans délai fixe.
  - Le minuteur est déterministe (horloge démo fixée).
  - La sentinelle « 0 requête » est contrôlée dans les 3 cas.
- **Régressions** : la migration d'identifiants est documentée ; `OTPField` garde les défauts du lot 0.

#### Mineurs
1. `ContratModel.actualiser()` : une lecture ancienne en échec peut reposer `erreurRelecture` après une lecture plus récente réussie. Le bouton reste actif pendant la lecture. Correction : jeton de demande, plus bouton désactivé avec chargement.
2. `DemoContratsTests.swift:107` et `:161` : les assertions négatives sur `contrat-zone-signature` ne reposent sur aucune preuve positive de cet identifiant. Correction : assertion positive dans le cas « en attente », et négatifs complétés par `contrat-signature-otp` / `contrat-otp-envoyer`.
3. `relireAdmission`, `try?` (l.392) : un jeton refusé en STAGING bascule en renvoi web sans « Session à vérifier ». Correction : poser `sessionExpired` sur `.unauthorized`.
4. `SessionSignatureOtpTests.swift:226` : le commentaire cite encore la « décision 25 ».
5. `DECISIONS_LOT2.md:862` et `:851-852` : glose « seule » sur eIDAS 25 §2 (considérant 49) et exemple L.1242-12 imprécis (requalification, pas nullité).

#### Conditions de merge (hors constats)
- **CI** : l'éclat « contrats » doit être vert sur iphone, ipad-portrait et ipad-landscape, avec la classe `DemoSignatureContratTests` démarrée et `skipped = 0`. Les 3 XCUITest et la migration de `DemoContratsTests` n'ont jamais été exécutés. L'intégrateur reporte la durée des trois éclats par format (décision 22).
- **File de merge** : `AppContainer.swift` et `ios-swift-ci.yml` sont sériels avec T4b ; garder les deux blocs, la garde Node tranche la cohérence.
- **« Livré » au sens de CLAUDE.md** : restent P9, la revue de l'écran sur iPhone par Gabrielle (T12), et P5, la signature STAGING réelle. Le go juridique est donné par délégation et consigné.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-09)

- `git merge --no-ff origin/lot2/l2-t9b-v2` (`44fda8db`) après T4b et T5a, commit de fusion `3b76275e`. Quatre conflits,
  résolus en gardant les deux côtés :
  - `ios-swift-ci.yml` : la structure en éclats par domaine de T4b est gardée, et T9b y est reportée :
    `DemoSignatureContratTests` dans l'éclat « contrats » (`-only-testing`), exclue du socle, exigée par le résumé ; étape
    « Éclats des tests UI cohérents » dans le job Cœur ; garde ajoutée aux deux filtres de chemins. Le plafond du job reste
    à 195 min, au-dessus du minimum de la garde (5 × 30 + 15 = 165 min) ;
  - `AppContainer.swift` : scénarios démo de T4b, T5a puis T9b (`ScenarioDemoContrats`, `otp-expire`, `compte-test`),
    comme le demande la condition « File de merge » ;
  - `JoleneDesignLot2Tests.swift` : tests `NumericCodeField` (T4b) puis `AnnonceALApparition` (T9b) ;
  - `DECISIONS_LOT2.md` : décision 22 (paragraphes de T4b et de T9b, plus une note d'intégration), applications de T5a et
    de T9b, sections des textes opérationnels de T5a et de T9b, sous-section T9b des décisions déléguées.
- **La garde Node `tests/node/ios-swift-ci-eclats.node.mjs` rougissait sur le résultat fusionné : c'était le test qui
  était faux pour la structure fusionnée, pas le code.** Rejouée telle quelle, elle échouait sur deux points. D'abord,
  « éclat « lot2 » absent » : son premier test cherchait encore l'éclat « lot2 », que T4b a découpé. Ensuite,
  « DemoPointageTests n existe pas » : `classesUi()` ne reconnaissait que les sous-classes directes de `JoleneUITestCase`,
  alors que `DemoPointageTests` et `DemoPointageEtatsTests` héritent de `DemoPointageUITestCase`. La garde n'est pas
  affaiblie :
  - elle exige toujours exactement les deux classes des contrats dans « contrats », et désormais leur absence de **tous**
    les autres éclats ;
  - elle suit l'héritage jusqu'à `JoleneUITestCase` ;
  - un test est ajouté : `DemoPointageTests`, `DemoPointageEtatsTests` et `DemoPresenceDetailTests` reconnues et rangées
    chacune dans un seul éclat de domaine, la classe de base sans test exclue.

  5 tests sur 5 passent.
- Défaut d'intégration corrigé dans le même correctif `bff6be3c` : le nom de l'étape de l'éclat « contrats », complété à
  la fusion par « : lecture et signature », rendait le workflow invalide en YAML (« Nested mappings are not allowed in
  compact mappings », relevé par l'analyse `yaml` du fichier avant le push). Il devient « (XCUITest Contrats, lecture et
  signature) ».
- Mineurs 1 à 5 non traités : aucun ne casse une vérification.

## L2-TJ

### Revue fraîche B8 — L2-TJ (n°1)

**Verdict : CLÔTURABLE** — aucun constat bloquant ni majeur, 11 constats mineurs.

Diff relu en entier : `git diff origin/feat/ios-lot2...origin/lot2/l2-tj-v2`, 41 fichiers. Lecture seule : aucun build, aucun test, aucun appel au MCP Supabase. Le dump `supabase/schema/public.sql` de la branche a été relu.

#### Périmètre
- Le merge `89447a41` ne touche que 20 fichiers web (SEO #1115 et mention #1122). Chacun est **identique octet pour octet** à `origin/main` (`f9a8c236`). La tranche n'a rédigé aucun fichier web.
- Les commits propres à la tranche touchent 21 fichiers, tous annoncés par l'auteur.
- Aucun littéral ressemblant à un secret. Aucune donnée sensible : pas de code de pointage, d'OTP, de coordonnées GPS ni d'octets de fichier dans un log.

#### (a) Mention du pied de page CDDU / VACATION
- `ContratRules.mentionPiedDePage` lit `TextesWeb.Contrat.typesMentionSalariee`, qui contient {CDD, SALARIE, CDDU, VACATION}.
- C'est exactement la constante `TYPES_CONTRAT_MENTION_SALARIEE` de `ContratMission.tsx` l.65 (vérifié), comparée sans transformation (équivalent de `Array.includes`).
- Le cadre employeur reste réservé au CDD (l.540-542). Les lignes 837-840 et 836-842 sont exactes.
- Aucune autre liste « salarié » ne décide de la mention côté natif (vérifié par `git grep`).
- L'extension de la garde (`const NOM = [...]`, `deballer` tolère l'absence d'initialiseur) est correcte. Les mutations (retrait, ajout, oubli côté Swift) sont testées.
- La règle juridique elle-même est celle de Gabrielle (#1122) ; D6 la reprend correctement.

#### (b) Bandeau RCP et textes d'accès (T7)
- **Textes repris mot pour mot**, lignes vérifiées dans `DocumentsSoignant.tsx` : l.623, 624, 634, 867-868 et 882-883 (espaces JSX réduites à une).
- **Règle** : c'est celle de T6 (`alerteRcp`) : libéral ou mixte seulement, date passée quel que soit le statut, sinon RCP absente ou non vérifiée.
- **Ordre** : expirations → RCP → incohérence, comme le web.
- **Couleurs** : rouge (destructive) pour une RCP expirée, ambre pour une RCP manquante.
- **Accessibilité** : icône masquée, conteneur `.contain`.
- **Scénario démo** `rcp-expiree` : DEBUG, sans réseau, ne modifie que la date de la RCP. Un test unitaire garantit que rien d'autre ne change.
- **XCUITest** : le dossier chargé est attendu par `require` avant toute assertion d'absence ; `scrollTo` est borné ; aucune attente par délai fixe ; la classe tourne dans l'éclat lot2 sur les 3 formats.
- **Tests modifiés** : ils suivent #1122 et D4, aucun n'est affaibli.
- **Non-régression** : DemoNoNetworkTests, sentinelle réseau et identifiants existants sont intacts.

#### Décisions déléguées D1 à D12
Chaque point porte la ligne de délégation. Sources primaires vérifiées, toutes conformes aux fichier:ligne cités :
- **Fonctions SQL** : `fn_documents_ok_pour_mission` l.31652-31730 et ses appels l.5178, 32857, 36806, 49361 ; `dec_verifier_docs_avant_debut` l.3903-3926 ; `fn_admin_moderer_document` l.11260-11284 ; licence ≤ 13 mois l.52125-52150 ; `fn_fenetre_contestation_ouverte` l.36627 (défaut 48 l.36649-36657) ; `fn_litiges_escalader_auto` l.40761-40884 ; `fn_valider_presences_72h_auto` l.65474 ; cron 72 h l.53042-53045 ; RIB l.25619.
- **Textes web** : CGU l.48, 97-104, 109, 115, 182 ; `PanneauContestation` l.43-46, 347, 354, 394 ; certificat l.172 et 214 ; semence 48 h l.158.
- **Textes de loi**, cohérents : CSP L.1142-2, L.1142-25, L.4131-2, L.3111-4 ; C. civ. 1104, 1110, 1190, 1366, 1367, 2254 ; C. trav. L.1242-12, L.1242-2 3°, L.3245-1 ; RGPD art. 6, 7, 13 ; eIDAS art. 25.
- **Jurisprudence** : Cass. crim. 7 mars 2012, n° 11-82.153, F-P+B. Son attendu (« seules les déclarations établies en faveur d'un tiers bénéficiaire… ») est confirmé par [Dalloz actualité](https://www.dalloz-actualite.fr/document/crim-7-mars-2012-f-pb-n-11-82153).
- **Juridique et serveur** : aucun texte reformulé ni inventé, aucune écriture serveur, Q9 seulement préparée comme PR B9.

Les constats mineurs portent surtout sur des sources incomplètes (D3, D4, D12), des renvois périmés (S1, l.36600, commentaires +5 lignes), le tutoiement et le vouvoiement côte à côte sur le scénario RCP expirée, et un ancien test Node devenu sans objet.

#### Conditions avant « livré » (ce ne sont pas des défauts)
- Les 2 XCUITest sont seulement compilés : il faut un run CI vert de l'éclat lot2 sur iphone, ipad-portrait et ipad-landscape, captures comprises.
- P9 (revue sur iPhone par Gabrielle) reste ouvert.
- Les PR web HARD STOP et la PR B9 Q9 restent à ouvrir.

### Intégration sur `feat/ios-lot2` (intégrateur, 2026-11-09)

- `git merge --no-ff origin/lot2/l2-tj-v2` (`2cdfda3e`) en dernier, commit de fusion `7660c483`. La reprise de `main` de la
  tranche (`89447a41`) était déjà sur la branche d'intégration : elle n'apporte rien de plus. Deux conflits, résolus en
  gardant les deux côtés :
  - `TextesWeb.swift` : commentaires de `relanceTitre` et `relanceExplication`, qui renvoient maintenant à D2 de TJ et à la
    décision « Relance de l'établissement » de T5a. Les valeurs sont identiques des deux côtés, et la ligne `// source:`
    reste juste au-dessus de chaque constante ;
  - `DECISIONS_LOT2.md` : une seule section « Décisions déléguées du 8 novembre 2026 ». Elle reprend l'introduction de TJ,
    complétée d'une phrase sur les sous-sections des tranches, puis D1 à D12 et les sous-sections T4b (D-T4b-0 à
    D-T4b-3), T5a et T9b, chacune avec sa ligne de délégation. « En attente de Gabrielle » prend la forme réduite de TJ
    (présence physique et B9). Le point P9 y gagne la signature réelle STAGING de T9b (P5), qui exige le téléphone de
    Gabrielle. Les points HARD STOP de T4b, T7, T9a, T9b, T5b et Q9 sont tranchés par D1 à D12, D-T4b-0 à D-T4b-3 et la
    décision T9b.
- Les XCUITest de TJ (`DemoDocumentsTests`, bandeau RCP et textes d'accès) tournent désormais dans l'éclat « documents »,
  qui a remplacé l'éclat « lot2 » depuis T4b.
- Garde textes-juridiques-ios après la fusion, verte : 122 textes HARD STOP et 273 libellés identiques au web, 38 zones de
  rendu retrouvées. La mention CDDU/VACATION (#1122) de `ContratMission.tsx` est suivie par
  `TextesWeb.Contrat.typesMentionSalariee`.
- Mineurs non traités : aucun ne casse une vérification.

## Vérifications après les fusions de T4b, T5a, T9b et TJ (intégrateur, 2026-11-09)

Exécutées en local sur la branche d'intégration `int-lot2-v4`, poussée vers `feat/ios-lot2` à `bff6be3c` puis, après les
correctifs révélés par la recette CI, à `ba41296b`, `1ec8d4a3` et `eaf8caf0` (Node 24.14 ;
Swift 6.1.2 de Xcode 16.4 sur le poste, la CI utilisant Xcode 26.4.1). Rien n'a été écrit en production ni sur STAGING,
aucun MCP Supabase n'a été interrogé, Playwright n'a pas été lancé. Seul `ios-swift-ci.yml` a été déclenché, par
`workflow_dispatch` (section suivante).

- Exporteurs, sans diff : `export-golden-vectors.mjs` (2 793 vecteurs), `export-demo-fixtures.mjs` (10 fichiers, dont
  `demo-contrat-pointage-c.html` de T4b), `check-rpc-contracts.mjs` (33 RPC, aucune dérive ; `--update` ne change rien).
  Les RPC câblées par les tranches sont déjà `consommee` : `fn_consentir_gps`, `fn_creer_notation_mission` (T5a),
  `fn_envoyer_otp_signature`, `fn_signer_contrat_otp`.
- Garde textes-juridiques-ios (`check-textes-juridiques-ios.mjs`) : verte, 122 textes HARD STOP, 273 libellés identiques
  au web, 38 zones de rendu retrouvées.
- `node --test` :
  - gardes touchées (`check-rpc-contracts`, `textes-juridiques-ios`, `lecture-notes-ios`, `mobile-delivery-plan`,
    `ios-swift-ci-eclats`) : 168 tests, 0 échec ;
  - suite entière `tests/node/*.node.mjs` : 1 875 tests, 0 échec, 0 ignoré ;
  - `ios-swift-ci-eclats` : 5 tests après son adaptation (section L2-T9b). Sa version d'origine échouait sur 2 tests sur 4
    contre le workflow fusionné.
- `JoleneCore` : `swift build --build-tests -Xswiftc -strict-concurrency=complete` rouge sur le résultat fusionné
  (`DemoPointageGateway.swift:229`, `verifier` asynchrone de T4b appelé sans `await` par T5a), vert après le correctif
  `bff6be3c`, sans avertissement (build propre, `.build` supprimé avant) ; `swift test` : 936 tests XCTest, 0 échec.
- `JoleneSupabase` : même build, sans avertissement ; `swift test` : 284 tests XCTest, 0 échec.
- App : `xcodebuild build-for-testing` (schéma `Jolene`, Debug, `generic/platform=iOS Simulator`, `-derivedDataPath` dans
  le worktree, sans signature ni index) : `TEST BUILD SUCCEEDED`. Toutes les cibles sont compilées (Jolene,
  JoleneCoreTests, JoleneSupabaseTests, JoleneDesignTests, JoleneUITests), dont les tests de #1125 (`RequireWait`) et les
  XCUITest de T4b, T5a, T9b et TJ. Aucun avertissement dans nos sources ; seuls restent ceux
  d'`appintentsmetadataprocessor`.
- `xcodegen generate` à chaque fusion : le pbxproj suit `project.yml`, sans le groupe vide `Jolene/Resources`.
- Workflows : `ios-swift-ci.yml` et `validate-pr.yml` relus par l'analyseur `yaml` avant le push. Le premier était
  invalide après la fusion de T9b, à cause du nom d'étape de l'éclat « contrats » ; c'est corrigé dans `bff6be3c`.
- Correctif d'intégration `bff6be3c`, outre les deux points ci-dessus : le relevé « Attentes bloquées absorbées » de #1125
  lit le `manifest.json` de **chaque** éclat (`attachments/<éclat>/`). Il ne lisait que `attachments/manifest.json`, qui
  n'existe pas quand les tests UI tournent en éclats : il aurait toujours conclu « NON relevées ». Il a été essayé en local
  sur des pièces jointes synthétiques : un blocage relevé dans « pointage », « contrats » signalé sans manifeste, puis
  aucun dossier. Il reste `continue-on-error`.
- Littéraux : aucun nouveau littéral de type secret dans les fichiers écrits par l'intégrateur. Le seul hexadécimal de
  64 caractères apporté par les fusions est le `hash_document` SHA-256 de `demo-contrat-pointage-c` dans
  `demo-contrats.json`, fixture produite par l'exporteur et de même nature que ceux de T8 (relevé par la revue de T4b).
- Après chacun des correctifs `ba41296b`, `1ec8d4a3` et `eaf8caf0` (app et XCUITest seulement), `xcodebuild
  build-for-testing` a été relancé : `TEST BUILD SUCCEEDED`, sans avertissement dans nos sources ; la garde
  `ios-swift-ci-eclats` reste verte (5 tests sur 5), et la suite Node entière aussi (1 875 tests). JoleneCore et
  JoleneSupabase ne sont pas touchés par ces correctifs.
- Nettoyage : chaque `.build`, chaque `DerivedData` du worktree et chaque artefact CI téléchargé (extrait dans le
  worktree pour lire les xcresult) ont été supprimés après usage. Le lien `node_modules` est retiré à la fin.

## Recette CI `ios-swift-ci.yml` après les fusions de T4b, T5a, T9b et TJ (intégrateur, 2026-11-09)

Déclenchée par `gh workflow run ios-swift-ci.yml --ref feat/ios-lot2` (Xcode 26.4.1, iOS 26.2, iPhone 17 et iPad (A16)).
Cinq éclats par format : socle, presences, pointage, documents, contrats. Le résumé exige, pour chaque éclat, un code 0,
`Passed`, au moins un test, `failed = 0`, `skipped = 0` et chacune de ses classes démarrée. Les tests de T4b, T5a et T9b
tournent ici pour la première fois. Deux essais de correction au plus. Le run 42567602201 a été annulé par l'intégrateur
une dizaine de minutes après son lancement, avant toute exécution des éclats du lot 2 : il ne comportait pas encore le
correctif de défilement. Il n'a rien testé et n'est donc pas compté comme un essai.

| Run | Commit | Cœur | Packages | UI iphone | UI ipad-portrait | UI ipad-landscape |
|---|---|---|---|---|---|---|
| [42559541711](https://github.com/Gabpcd/JJJJJ/actions/runs/42559541711) (recette) | `bff6be3c` | vert | vert | rouge : 1 028 / 3 / 0 / 1 031 | rouge : 1 030 / 1 / 0 / 1 031 | rouge : 1 028 / 3 / 0 / 1 031 |
| [42567602201](https://github.com/Gabpcd/JJJJJ/actions/runs/42567602201) | `ba41296b` | vert | vert | annulé | annulé | annulé |
| [42568134868](https://github.com/Gabpcd/JJJJJ/actions/runs/42568134868), tentative 1 (essai 1) | `1ec8d4a3` | **vert** | **vert** : JoleneCoreTests 936, JoleneSupabaseTests 284, 0 avertissement | rouge : simulateur bloqué, sans xcresult pour pointage, documents et contrats | **vert** : 1 031 / 0 / 0 / 1 031, 95 captures portrait | **vert** : 1 031 / 0 / 0 / 1 031, 95 captures paysage |
| [42568134868](https://github.com/Gabpcd/JJJJJ/actions/runs/42568134868), tentative 2 (essai 2, job iPhone seul, sans changement) | `1ec8d4a3` | — | — | rouge : 1 030 / 1 / 0 / 1 031, 94 captures portrait | — | — |

Notation : réussis / échoués / ignorés / total, éclats additionnés.

### Échecs du run de recette 42559541711, causes et correctifs

Chaque échec a été lu dans le journal du job et dans l'xcresult (arbre d'accessibilité de l'échec, activités, et images
extraites de l'enregistrement d'écran pour le partage).

- **`DemoPointageTests.swift:67`** (iPad portrait et paysage), « En service depuis l'ouverture » : **défaut du code**.
  L'identifiant `pointage-en-service-<m>` était posé sur un `Label` ; SwiftUI le recopiait sur l'icône (« Horloge ») et
  sur le texte, si bien que deux éléments le portaient. Correction dans `ba41296b` (`PointageCodeView`) : un seul
  élément d'accessibilité, au libellé du texte. Aucun autre identifiant en double dans les instantanés.
- **`DemoPointageUITestCase.swift:100`** (iPhone), « Le champ est vide avant la saisie » : **test faux**. Le toucher à
  97 % de la largeur tombait dans le rembourrage de `NumericCodeField` (12 pt), hors du champ de texte (254 pt sur 262) ;
  les effacements restaient sans effet. Correction dans `ba41296b` : toucher à 85 %, après le dernier chiffre, dans le
  champ.
- **`testHorsLigneDesactiveLePointageSansAucunEnvoi`** (iPad paysage) et
  **`DemoContratsTests.testContratSigneCertificatEtPartageDuFichierOriginal`** (iPad paysage, « La feuille de partage du
  système est présentée ») : **test faux**, même cause. `scrollTo` prenait pour zone visible le cadre du `ScrollView`, qui
  passe sous la barre de navigation translucide d'iOS 26. Le bouton restait sous la barre : dans le premier test, la page
  était poussée jusqu'à la fin du contenu ; dans le second, le toucher atteignait la barre, qui ramenait le défilement en
  haut (images de l'enregistrement d'écran), et aucune feuille de partage n'était présentée. Corrections :
  - `ba41296b` : une cible masquée est ramenée vers le centre ;
  - `1ec8d4a3` : `basDesBarresDeNavigation` et `visibleSousLesBarres` exigent que la cible soit sous les barres ;
    l'assertion finale de `scrollTo` devient plus stricte, jamais plus lâche.
- **`DemoConsultationTests.swift:106`** (iPhone, socle), « observateur ou thread principal bloqué 47,2 s » au-delà du budget
  de 15 s de #1125, puis **`DemoExplorerTests.testCarteEnLectureSeuleDansLeDetailSansRequete`** (iPhone, socle, champ de
  connexion non atteint juste après) : blocage du runner, pas un échec de code. Aucune ligne de ces tests du lot 1 n'est
  touchée par les fusions, et les deux sont verts au run 42568134868 sur les trois formats.

### Échecs du run 42568134868 (iPhone)

- **Tentative 1** : simulateur bloqué, ce n'est pas un échec d'assertion. Dans l'éclat « pointage », 8 tests sur 10 passent,
  dont les trois corrigés. Pendant `testRefusDeLaCameraRendLaSaisieManuelle`, la boucle d'événements de l'app cesse de
  répondre (« App event loop idle notification not received »), puis « Timed out while evaluating UI query ». Le test
  suivant ne peut plus lancer l'app (« Failed to get launch progress »). Les éclats « documents » et « contrats » restent
  bloqués sur l'installation de `JoleneUITests-Runner.app` (journal de session) et sont coupés à 30 min sans avoir
  démarré un seul test. Le même test passe sur iPhone au run 42559541711 et à la tentative 2. Le job iPhone est relancé
  seul, sans changement (`gh run rerun --failed`).
- **Tentative 2** : 1 030 réussis sur 1 031. Seul échoue `DemoSignatureContratTests.testCodeExpireProposeUnNouveauCode`,
  sur « Le contrôle contrat-otp-envoyer est atteignable » : **test faux** (T9b). Le test amenait la case de consentement à
  l'écran, puis touchait « Recevoir le code SMS pour signer » sans l'y amener ; sur iPhone, le bouton était sous le bord de
  l'écran et sous la barre d'onglets (y = 839,7 pour 874 pt). Le correctif de défilement n'y est pour rien : la case est
  dans la moitié basse, et le sens choisi est celui d'avant. Le test passait sur iPhone au run 42559541711, parce que la
  position atteinte après les glissements varie. Correction dans `eaf8caf0`, comme dans
  `testSignatureOtpCodeFauxPuisCodeAccepteRelu` : le bouton est amené à l'écran avant d'être touché. Ce correctif est
  compilé (`TEST BUILD SUCCEEDED`) mais **pas exécuté en CI** : les deux essais sont épuisés.

### Ce qui est acquis, ce qui reste

- **Acquis sur iPad portrait et iPad paysage** (run 42568134868, `1ec8d4a3`) : 1 031 tests, 0 échec, 0 ignoré. Toutes
  les classes ont démarré : `DemoPointageTests` (10), `DemoPointageEtatsTests` (4), `DemoPresenceDetailTests` (4),
  `DemoSignatureContratTests` (3), ainsi que les XCUITest de TJ dans `DemoDocumentsTests`.
- **iPhone** (tentative 2) : socle, presences, pointage et documents verts (994, 12, 10 et 9 tests) ; contrats à 5 sur 6.
  `DemoPointageTests`, `DemoPointageEtatsTests` et `DemoPresenceDetailTests` sont donc verts sur les trois formats.
- **Reste à prouver** : un run vert de l'éclat « contrats » sur iPhone avec `eaf8caf0`. Une seule relance du job iPhone
  suffit (`gh run rerun` sur un nouveau run de `feat/ios-lot2`).
- Durées des éclats au run 42568134868 (minutes ; socle, presences, pointage, documents, contrats) :
  - ipad-portrait : 12,5, 14,2, 14,9, 9,8, 10,1 (build-for-testing : 2,8) ;
  - ipad-landscape : 12,8, 13,4, 15,4, 8,6, 13,7 (build : 2,6) ;
  - iphone, tentative 2 : 16,0, 16,9, **21,9**, 12,7, 17,2 (build : 5,5).

  Au run 42559541711, l'éclat « pointage » mesurait 18,2 min sur iPhone et 19,1 min en paysage. Il dépasse le seuil de
  20 min de la décision 22 sur iPhone à la tentative 2, dont le runner relevait 33 attentes bloquées absorbées. À séparer
  si la mesure se confirme au prochain run (consigne de la décision 22).
- Le relevé « Attentes bloquées absorbées » de #1125, adapté aux éclats dans `bff6be3c`, fonctionne :
  - iPad paysage : 1 attente ;
  - iPad portrait : 9 attentes ;
  - iPhone : 16 attentes au run 42559541711, 33 à la tentative 2.

  Toutes sont relevées par éclat, en annotation et dans le résumé.
- Ce que la CI ne prouve pas : la recette appareil (T12), les écrans STAGING (T11), la revue P9 sur iPhone par Gabrielle
  et la notation au départ final (`.notationAuDepart`, non branchée).

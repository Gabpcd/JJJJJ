# Revues fraîches B8 — lot 4 (app iOS Swift native)

Rapports des revues à contexte vierge (CLAUDE.md, B8) des tranches du lot 4, consignés par l'intégrateur sur
`feat/ios-lot4`. Une section par tranche, dans l'ordre d'intégration. Les rapports sont reproduits tels que
rendus ; seuls les niveaux de titre sont décalés d'un cran pour tenir sous le titre de la tranche.

## L4-T0

### Revue fraîche B8 — L4-T0

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur, 7 mineurs.

**Périmètre relu :** `git diff origin/feat/ios-lot1...origin/lot4/l4-t0` en entier, soit 6 commits, de 5bd78c0e à 2df30865, sur 10 fichiers. Lecture seule : aucun test lancé, conformément à la consigne. Je n'ai fait aucun appel MCP : la PR ne touche pas `supabase/`, ce n'est donc pas une PR backend.

#### Vérifications faites
- **Périmètre.** Les fichiers touchés sont exactement ceux du §3 T0 du blueprint v2. Le diff ne contient aucune ligne Swift, aucune migration, aucun SQL, aucune modification web ni edge. Aucun littéral ne ressemble à un secret (balayage sb_secret, eyJ, sk_, IBAN, hex ≥ 40).
- **`rpc-contracts.json`.** J'ai régénéré le contrat en mémoire avec le `buildContracts` de la branche et ses sources. Le résultat est **identique octet pour octet** au fichier versionné : 69 RPC, zéro dérive. Le diff ne fait qu'ajouter des entrées.
- **Contenu du JSON.** Il y a 41 RPC en `lot: 4` plus `fn_ouvrir_litige_rate_limited`, dont les trois surcharges sont sous contrat. Toutes sont SECURITY DEFINER et accordées à `authenticated`. Dix ont `types: null` et deux sont hors manifeste, comme le dit la synthèse.
- **RPC partagée.** Le mécanisme `RPC_PARTAGEES_LOT4` / `ajouterPartageesLot4` est compatible avec `origin/lot2/l2-t0`, qui suit cette RPC en `lot: 2` dans le tableau littéral. Il l'est aussi avec le T0 du lot 5, qui déduplique `fn_obtenir_conversation` au profit du lot 4. Le test lot 1 « noms uniques » attrape tout doublon.
- **Lignes du dump.** J'ai relu 30 renvois de lignes de `public.sql` : messages 42501, 28000, 22023 et P0001, `COALESCE(score_global, 0)`, `SUPER_LIKE` → `FAVORI`, GRANT `service_role` seul sur `evaluations_publiees`, REVOKE de `fn_envoyer_message`. Tous sont exacts.
- **Extracteurs SQL.** Ils sont cohérents avec le dump : 21 ERRCODE, aucune forme RAISE hors `EXCEPTION` et `RAISE;`, aucun dollar-quote nommé dans les 42 corps. Seule forme `'error'` non littérale : `v_planning->>'message'` (`fn_enregistrer_swipe`), et la fiche la documente.
- **Double-aveugle.** Aucune insertion dans `evenements_score_soignant` ne dérive d'une notation (types `NOTE_BASSE_RECUE` et `EVALUATION_NEGATIVE` jamais insérés). La liste `events` affichée pour la première fois par le natif ne révèle donc pas de note non publiée. `fn_documents_ok_pour_mission`, qui lève 42501, n'est atteignable que depuis un SECURITY DEFINER (`current_user` = postgres).
- **Garde-fous 18 et 19.** Ce sont des ajouts purs : 1 à 17 inchangés, `set -uo pipefail` sans `-e`, donc `RC=$?` est sûr. Ils échouent fermés (dossier absent, code 2 de grep, aucun Swift). Le motif 19 exclut seulement `fn_envoyer_message_contact`. Ils sont verts sur l'arbre de la branche (`git grep` vide).
- **Tests node.**
  - Pas de test vide : témoins positifs et négatifs pour chaque extracteur.
  - Arbres temporaires exécutés pour les garde-fous.
  - Égalité exacte sur les six messages 42501.
  - Les comptes de lectures et de filtres de `notations_missions` sont exacts.
  - L'adaptation `verdictLitteralSwift` reprend la règle de `verifierExclusions`.
  - Les imports en milieu de fichier sont valides : les imports ESM sont remontés en tête.
- **Drapeaux D-FLAGS.** `origin/feat/drapeaux-ios-natif-lots-2-4-5` à 7aa3a1db pose 23 clés, dont les **13 clés du lot 4**, `exclusions` et `serie` comprises. La précision 1 est exacte.
- **Documentation.**
  - `LOT4_PLAN.md` est le blueprint v2 à l'identique, plus l'en-tête de renvoi.
  - Le §7 de `LOT1_PLAN.md` porte les décisions 1 à 19 avec la numérotation de `LOT1_DECISIONS.md`.
  - Les statuts PARITE suivent le §1.3 ligne à ligne, et le tableau principal est intact.
  - Les textes web cités mot pour mot sont présents aux lignes indiquées.
  - Aucun texte juridique nouveau, aucune catégorie B9 touchée.

#### Mineurs (non bloquants)
1. **`CONTRATS_RPC_SOIGNANT.md` l.3, l.21, l.32.** L'en-tête et la procédure de re-baseline parlent encore de « vingt-sept RPC ». Il y en a 69, plus les sources edge, migration et `guards.sh`. Le blocage voulu de `auto/schema-baseline` couvre désormais les 42 RPC du lot 4. Mettre le nombre à jour et renvoyer à « Sources lues par la garde (lot 4) ».
2. **`DECISIONS_LOT4.md` l.167 (point n°4 de « En attente »).** Le point est passé en « pour information, non bloquant ». Or le §6.4 du blueprint demande à Gabrielle d'acter ce report, et D17 annule une décision qu'elle a prise elle-même (`DECISIONS_LOT0.md` l.12, « WKWebView authentifiée bornée »). Écrire « adoptée sur mandat, à acter par Gabrielle ».
3. **`CONTRATS` l.1739 (fiche edge `copies-bulletins`).** `verify_jwt = true` est tiré de `config.toml`, que `--use-api` ne lit pas (CLAUDE.md). Reprendre la réserve de la fiche `messagerie-validate`, ou relever la valeur réelle.
4. **`DECISIONS_LOT4.md` l.50 (D10) et `CONTRATS` l.1287.** Le garde-fou 8 est cité comme verrou du « jamais de justificatif ». Il ne lit que `src/` (`ARRET_MALADIE`). Citer le test T9 « jamais `p_justificatif_storage_path` », ou ajouter ce motif sur `ios-native/` dans `guards.sh`.
5. **`CONTRATS` l.897 (table d'interception).** La garde 42501 ne lit que les corps directs. Les triggers qui lèvent 42501 tomberaient en « session expirée » :
   - sur `soignants` : verrou de transition libérale, provenance IBAN, preuves SIRET ;
   - sur `reclamations_score` : verrou de justificatif ;
   - sur `candidatures` : RBAC.

   Aucun n'est atteignable aujourd'hui. Écrire cette portée dans la table.
6. **`RECETTE_DEVICE_LOT4.md` l.40.** En mode avion, la requête ne part pas : l'échec est local (`notConnectedToInternet`). L'attendu « envoi non confirmé » reste prudent, mais l'étape est à reformuler.
7. **`DECISIONS_LOT4.md` l.85-88 et `LOT4_PLAN.md` l.7.** Les renvois vers `DECISIONS_LOT5.md`, `LOT2_PLAN.md`, `LOT3_PLAN.md` et le test D-FLAGS visent des fichiers absents de cette branche. Préciser la branche d'origine, ou vérifier ces renvois à l'intégration.

#### Points d'intégration (rappel, pas des défauts)
La fusion avec le T0 du lot 2 doit se faire à la main pour la fiche `fn_ouvrir_litige_rate_limited`, jamais en « gardant les deux côtés ». La garde exige un seul titre `##`. La procédure est consignée en précision 10, ainsi que les trois autres endroits à fusionner à la main. Ensuite, lancer `--update` et ne jamais retoucher le JSON à la main.

### Intégration sur `feat/ios-lot4` (intégrateur, 2026-11-03)

- `origin/feat/ios-lot4` n'existait pas : branche créée depuis `origin/feat/ios-lot1` (`3c0eed95`, avec T3, T4a et
  T8 du lot 1), puis `git merge --no-ff origin/lot4/l4-t0` (`2df30865`, commit de fusion `545cad18`). Le T0 du lot 4
  partait de `c509224a` (T0 du lot 1) : 22 commits de retard sur le lot 1.
- **Deux conflits, résolus en gardant les deux côtés :**
  - `PARITE_SOIGNANT.md`, ligne « Dernière mise à jour » (même cas que le point (c) de la précision 10) : la
    mention du T0 du lot 4 (2026-11-03) précède celle du lot 1 (T3 revue B8, 2e passe, T0) et la règle « aucune
    ligne n'est statuée natif sans l'URL d'un run vert » du lot 1, gardée intacte ;
  - `tests/node/check-rpc-contracts.node.mjs` : le test du lot 1 « `fn_suggestions_missions_pour_soignant`
    reclassée lot 4 (revue B8 de T3) » est conservé ; l'ancien test du lot 1 « aucune RPC interdite ou
    prématurée » est remplacé par sa réécriture du T0 du lot 4 (« aucune RPC interdite, aucune RPC du lot 4
    classée avant le lot 4 »), qui en garde les deux contrôles.
  - Fusion automatique, relue : `check-rpc-contracts.mjs` (reclassements du lot 1 puis bloc des 41 RPC et
    `RPC_PARTAGEES_LOT4`), `CONTRATS_RPC_SOIGNANT.md`, `guards.sh`. `rpc-contracts.json` régénéré par
    `check-rpc-contracts.mjs --update` : identique à la fusion automatique (69 RPC).
- **Ce qui cassait après fusion, corrigé** (`6d3f72cb` test rouge, puis `76469ca1`
  `fix(ios-native): intégration lot 4 …`) : la revue B8 du T3 du lot 1 a reclassé
  `fn_suggestions_missions_pour_soignant` en `a_venir`, `lot: 4` après l'écriture du T0 du lot 4 ; les deux gardes
  « 41 RPC propres au lot 4 » en comptaient donc 42. La garde la tient désormais hors des 41 (`LOT4_RECLASSEES`),
  exige `a_venir`, `lot: 4`, son absence des 42 RPC du blueprint, et sa mention dans la synthèse du lot 4 de
  `CONTRATS_RPC_SOIGNANT.md` et dans la nouvelle précision 11 de `DECISIONS_LOT4.md` (sort au lot 4 statué en T15 ;
  sa fiche reste celle du lot 1, sans `42501` dans son corps).
- **Vérifications après fusion :**
  - `node --test tests/node/mobile-delivery-plan.node.mjs tests/node/check-rpc-contracts.node.mjs` : 130 tests,
    130 verts (dont 53 de `check-rpc-contracts.node.mjs`) ;
  - `node scripts/mobile/check-rpc-contracts.mjs` : 69 RPC, aucune dérive ;
  - `bash tests/non-regression/guards.sh` : les 19 garde-fous passent, 18 et 19 compris sur le Swift des T3, T4a et
    T8 du lot 1 ;
  - `export-golden-vectors.mjs` (1 613 vecteurs) et `export-demo-fixtures.mjs` : aucun diff.
  - Non relancés : `swift test` (JoleneCore, JoleneSupabase) et `xcodebuild` (JoleneDesign, app) — aucun fichier
    Swift ni `project.pbxproj` ne diffère de `origin/feat/ios-lot1` (seul `ios-native/rpc-contracts.json` change sous
    `ios-native/`, et aucun code Swift ne le lit) ; `npx tsc -b` et vitest — aucun fichier sous `src/` ni
    `supabase/` n'est modifié.
- **Mineur 7, vérifié à l'intégration :** `DECISIONS_LOT5.md`, `LOT2_PLAN.md`, `LOT3_PLAN.md` et
  `src/lib/__tests__/drapeauxIosNatifMigration.test.ts` restent absents de `feat/ios-lot4` (ils vivent sur
  `origin/lot5/l5-t0`, les branches des lots 2 et 3 et `origin/feat/drapeaux-ios-natif-lots-2-4-5`) ; les renvois
  deviennent vérifiables à la reprise de ces branches, ou à préciser par la tranche qui retouche ces fichiers.
- Les mineurs 1 à 6 restent ouverts : à traiter par un correctif du T0 ou par la tranche qui touche le fichier
  (T1 pour la table d'interception, T9 pour le justificatif, T10 pour la fiche `copies-bulletins`), pas par
  l'intégration.
  Aucune PR n'est ouverte et rien n'est mergé ; HARD STOP n°4 et B9 restent tels que décrits par la revue.

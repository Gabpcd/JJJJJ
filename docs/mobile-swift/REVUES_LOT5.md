# Revues fraîches B8 — lot 5 (app iOS Swift native)

Rapports des revues à contexte vierge (CLAUDE.md, B8) des tranches du lot 5, consignés par l'intégrateur sur
`feat/ios-lot5`. Une section par tranche, dans l'ordre d'intégration. Les rapports sont reproduits tels que
rendus ; seuls les niveaux de titre sont décalés d'un cran pour tenir sous le titre de la tranche.

## L5-T0

### Revue fraîche B8 — L5-T0

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur, 9 mineurs.

**Périmètre relu.** `git diff origin/feat/ios-lot1...origin/lot5/l5-t0` en entier : 19 fichiers, +4731, base de fusion `c509224a`.
- Commits TL repris : `d041c49c`, `3e25f507`, fusion `2d3f17c6`.
- Commits propres au T0 : test rouge `ee1af253`, puis implémentation `b5b04835`.

**Cadre.** LOT5_PLAN v2 (§2.5, §2.7, §2.9, §3 T0, §6, §7), LOTS_2_5_DECISIONS, CLAUDE.md, PRINCIPES.md.

Je n'ai lancé ni build ni test, et fait aucun appel MCP : ce n'est pas une PR backend (aucune migration, aucune redéfinition SQL, aucun fichier sous `src/` ou `supabase/`). J'ai seulement relancé en lecture seule, dans le scratchpad, les fonctions d'extraction et la garde contre `public.sql` et les migrations de la branche.

#### Vérifié, conforme

- **Fusion TL.** Le commit `2d3f17c6` est pur : son arbre est identique à `3e25f507`. Le message suit Conventional Commits. D30 est respecté : un seul mécanisme de textes verbatim.
- **Blueprint versionné.** `LOT5_PLAN.md` est identique octet pour octet au blueprint v2.
- **RPC suivies.** Les 14 RPC sont en `a_venir` lot 5, les 7 partagées sont annotées `aussi_etablissement`.
- **Dédoublonnage.** Il fonctionne contre les branches sœurs réelles : `origin/lot2/l2-t0` suit `fn_creer_notation_mission` en lot 2, `origin/lot4/l4-t0` suit `fn_obtenir_conversation` en lot 4.
- **Classements.** Le classement manuel « hors manifeste » et `types: null` sont conformes au §3 T0.
- **Listes blanches recalculées depuis le dump.** Elles sont identiques au JSON et aux attendus figés du test :
  - le RBAC `'pointage'` est bien instancié via `TG_ARGV` ;
  - les 4 P0001 et le 23503 (forme `USING MESSAGE`) de `dec_bloquer_validation_presence_avant_fin_planning` sont présents ;
  - les 2 P0001 de la garde de paiement sont présents ;
  - P0002, 42501 et 23514 de la clôture rétroactive sont présents.
- **Autres triggers de `presences`.** `dec_depart_apres_arrivee`, l'anti-fraude, l'intégrité et l'escrow ne lèvent rien sur le chemin de validation.
- **Délégués de la publication et de l'acceptation.** Les exceptions de `_v2` sont avalées, `_internal_20260810` et `fn_finaliser_attribution_mission` ne lèvent rien.
- **Matrice rôle × permission.** Elle égale le `CASE` de `fn_a_permission_etablissement` : 11 clés et 5 rôles du CHECK, conformes au §2.7.
- **Codes de blocage.** `fn_blocage_publication_etab` renvoie 5 codes ; l'amendement 5 est fondé.
- **Matrice de parité.** Les 47 routes et leurs lignes correspondent à `src/App.tsx`, avec 13 routes natives, 34 renvois web et zéro « abandonné ».
- **Textes du lot 5.** Ils sont verbatim aux lignes annoncées :
  - `ListeCandidatures.tsx` l.393-397, mention CGV assemblée exactement comme React rend `{' '}` puis le texte collé au lien ;
  - `BandeauBlocageAuto.tsx` l.61 ;
  - `DashboardEtablissement.tsx` l.564-565 ;
  - `FormulaireMission.tsx` l.766.

  La mention art. 1366-1367 n'est pas dupliquée. Il n'y a aucun wording nouveau ni reformulé.
- **Garde des littéraux juridiques.** Les valeurs interdites sont lues dans le dump et dans les 6 migrations de la matrice, sans liste figée : 11 valeurs CHECK en égalité exacte, 18 sources et 4 noms en sous-chaîne.
  - Les exceptions sont exactes : la constante seule pour `RPCResponse`.
  - Le test négatif couvre chaque famille de valeurs.
  - Rejouée sur la pointe lot 5 (82 fichiers) et sur `origin/feat/ios-lot1` (102 fichiers), elle ne trouve aucune faute.
- **CI.**
  - `ios-swift-ci.yml`, job Cœur : 2 étapes, sans `if` ni `continue-on-error`, avec filtres de chemins.
  - `validate-pr.yml` : le nouveau test est bien exécuté par le check requis.
- **Ordre TDD.** Le commit d'implémentation ne fait que resserrer les tests : `plat()`, plus un test sur les 5 codes de blocage. Aucun `skip` ni `only`. D'après le journal Swift de l'auteur, 209 tests passent, 0 échec.
- **Secrets.** Aucun littéral ne ressemble à un secret.

#### Mineurs

1. **`DECISIONS_LOT5.md:97`, amendement 9 périmé.** LOTS_2_5_DECISIONS dit déjà « 7 clés ». Écrire : « D-FLAGS = 7 clés, conforme à D14 ».
2. **`contrats-etablissement-ios.node.mjs:417`, lignes de App.tsx figées dans le check requis.** Un import ajouté sur le web rougit la garde sans rapport avec le lot 5. Contrôler l'ensemble des chemins et leur nombre ; garder la ligne comme information, ou documenter la procédure de mise à jour.
3. **`check-rpc-contracts.mjs:161-176`, triggers RBAC des autres tables absents de la configuration.**
   - `fn_traiter_candidature_planning_v1` atteint `trg_p0_rbac_missions`, `trg_p0_rbac_contrats_mission` et `trg_p0_rbac_candidatures`.
   - `fn_declarer_fin_retroactive` atteint `trg_p0_rbac_presences` et `trg_p0_rbac_missions`.

   Ces chemins sont inatteignables avec le CASE actuel. Mais la matrice est paramétrée : si elle évolue, ces 42501 retomberaient en « session expirée » (correction 5) sans que le contrat ne rougisse. Les ajouter puis lancer `--update`.
4. **`CONTRATS_RPC_ETABLISSEMENT.md:449`, 42501 systématique pour POINTAGE_ONLY sur la clôture rétroactive.** `est_admin_etablissement()` ne retient que PROPRIETAIRE, ADMIN_GROUPE et RH (public.sql l.28692-28697), alors que §2.7 associe « clôturer » à `pointage`. Le web a le même comportement. À consigner, avec un amendement pour T8.
5. **`CONTRATS_RPC_ETABLISSEMENT.md:277` et JSON, entrée « Notification d'acceptation impossible : % ».** La fiche dit « générique », mais l'entrée est dans la liste verbatim. T1 l'afficherait telle quelle, avec un détail interne (PRINCIPES §3). Retirer l'entrée, ou ajouter un champ de traitement.
6. **`check-litteraux-juridiques.mjs:54`, motif des articles incomplet.** Il laisse passer `art. R.`/`D.` et le pluriel « articles ». Remplacer par `/\bart(?:icles?|\.)\s*(?:[LRD]\.?\s*)?\d/i`. À envisager aussi : scanner les JSON livrés sous `Resources`.
7. **Docs.**
   - `CONTRATS_RPC_ETABLISSEMENT.md:561-566` affirme que la garde « refuse déjà » les RPC de la liste « jamais » : faux pour `fn_generer_qr_mission` et `fn_ouvrir_litige_rate_limited`, suivies par d'autres lots.
   - `CONTRATS_RPC_SOIGNANT.md:792-795`, section « Hors périmètre » périmée.
   - Les renvois « (D8) » des lignes 34 et 204 visent en réalité §2.8.
8. **`TextesWebEtablissementTests.swift:30`, assertion qui ne teste rien.** Elle recopie l'implémentation de `cgvMention`. La supprimer, ou comparer à la chaîne attendue.
9. **Intégration et processus.**
   - La branche est en retard de 22 commits sur `origin/feat/ios-lot1` (T3/T4a/T8), avec 4 fichiers en commun : fusionner, puis lancer `--update`.
   - La branche dépend de TL, pas encore intégré : n'intégrer qu'après le verdict CLÔTURABLE de TL.
   - Les mentions légales ajoutées à `TextesWeb.swift` sont inertes, mais relèvent de la catégorie B9 « légal / mentions » : consigner dans la PR que T0 est classé hors B9 (blueprint, mandat), ou demander le go de Gabrielle.

#### Points d'arrêt maintenus

- HARD STOP n°4 : chaque texte du lot 5 attend la validation d'écran de Gabrielle dans sa tranche (T4, T6, T9, T10 ; §6.4).
- Rien n'est mergé.

Les mineurs 3 à 5 sont à traiter au plus tard en T1, qui consommera le champ `exceptions`.

## L5-T3

### Revue fraîche B8 — L5-T3

**Verdict : CLÔTURABLE.** 0 bloquant, 0 majeur, 6 mineurs.

Périmètre relu : `git diff origin/feat/ios-lot1...origin/lot5/l5-t3`, soit 3 commits et 11 fichiers, lus en entier.

#### Ce qui a été vérifié

- **Périmètre.** Tous les fichiers relèvent de T3 : exporter, golden, `Golden.fichiers`, `PlanningDerive.swift`, `PlanningExactEtab.swift`, `Etablissement/Pointage/CodeRotatifRules.swift` (chemin v2), les quatre fichiers de tests et les filtres de `ios-swift-ci.yml`.
  - Aucun fichier sous `src/` n'est modifié, aucun SQL, aucune migration.
  - Pas de B9, pas d'appel MCP (PR non backend), aucun littéral ressemblant à un secret.
- **Golden `planning-derive.json`.**
  - 658 vecteurs, noms uniques, répartis sur 7 fonctions. Grille DST complète : 384 vecteurs, 2 transitions × 2 jours × 48 heures × 2 fins. Périodes de 0 à 368 jours (plafond à 367 dates conforme à l.93).
  - Aucune occurrence de `PLAFOND`, `REPOS_11H`, `DUREE_LONGUE`, « 48 h », « 11 h », « 12 h », « légal » ou « Art. » : D9 est respecté et `testGoldenSansRegleDuTravail` le garde.
  - L'exporter tourne en `TZ=Europe/Paris`. L'ajout est sans effet sur les autres vecteurs ; le job « Cœur » régénère et compare.
- **Port de `planning-derive.ts`, comparé ligne à ligne.**
  - Expressions régulières en ASCII ; comparaison de chaînes en UTF-16.
  - `jourSemaineISO` reproduit la normalisation de `Date.UTC` (`CalendrierCivil` gère le mois 13 et le 30 février).
  - `resoudreBorne` : une `RangeError` correspond à `DateHeureParisError` ; le cas ambigu et le cas inexistant donnent les mêmes messages que le web.
  - `dateFinCreneau` est appelé hors du `try`, comme dans le web. Le tri est stable ; l'ordre des erreurs reste celui du web une fois `DUREE_LONGUE` filtré.
  - Un journal local de l'auteur montre 253 tests verts et 0 avertissement ; c'est une preuve indicative, la CI fait foi.
- **Re-dérivation (FormulaireRecurrence.tsx l.164-280 et l.395-402).**
  - Un jour qui reste dans la période est conservé tel quel, exceptions comprises ; un jour sorti est supprimé ; un jour nouveau est inactif avec le créneau 07:00-19:00.
  - En cas de doublon de date, la dernière entrée l'emporte (comme `new Map`).
  - Les présélections et la validation de période (l.180-218) sont fidèles. C'est conforme au principe « état dérivé / récurrences » de CLAUDE.md.
- **PlanningExactEtab.**
  - Les branches de l.65-97 sont prises dans l'ordre, y compris « premier fautif » pour `some`.
  - L'empreinte (id, debut, fin) se compare en égalité stricte de chaînes.
  - `p_creneaux_confirmes` est l'écho exact des chaînes relues (D26) : microsecondes et décalage conservés, `nil` si le planning n'est pas exact.
  - La durée vient de `Math.max(0, …)`. Les 4 cas planning de `ListeCandidatures.test.tsx` sont rejoués.
- **CodeRotatifRules.**
  - Décision d'affichage l.166-314 portée sur `DisponibilitePointage` et `CompletudePlanning`.
  - La permission `pointage` est vérifiée en premier, fail-closed (§2.7).
  - `trouverCreneauAssocie` utilise une fin exclusive puis le début le plus proche ; « Reprise » s'applique au même jour et au même créneau.
  - Les clés de `fn_etat_pointage_mission` sont conformes au dump. 12 scénarios vitest sont rejoués, plus celui de la permission.
- **HARD STOP n°4.**
  - Aucun texte juridique n'est ajouté ni reformulé. Le seul texte natif (« Code réservé aux membres habilités au pointage ») vient du blueprint §2.7 et n'est pas juridique.
  - La garde `check-litteraux-juridiques` de T0 ne serait déclenchée par aucun littéral : les valeurs CHECK de la matrice sont absentes.
  - Le serveur applique bien le plafond 48 h (salariat), le repos 11 h et le chevauchement (`fn_valider_creneaux_mission_json`, dump).
- **Intégration.** `git merge-tree` ne montre aucun conflit avec `lot5/l5-t0` ni avec `lot2/l2-t2`. Les filtres de chemins CI couvrent les 4 sources web gardées.

#### Mineurs (non bloquants)

1. **SynthesePresence non porté.**
   - L'écart au blueprint est justifié : le fichier existe sur `lot2/l2-t2`, au même chemin.
   - Mais `DECISIONS_LOT5.md` (« En attente » n°8) ne cite pas T8 parmi les tranches qui attendent le lot 2.
   - → Consigner dans la PR et dans DECISIONS_LOT5 que T8 attend l'intégration de lot2/l2-t2.
2. **`SourceWebLot5.swift:34-42` : garde `contains` seulement.**
   - Les annotations `// source: fichier:ligne` (même syntaxe que TL) ne sont pas vérifiées à la ligne et peuvent dériver ; il y a aussi une ambiguïté avec D30.
   - → Vérifier la ligne annotée, ou utiliser un autre marqueur que `// source:`.
3. **`CodeRotatifRulesTests.swift:126-132` : test mal nommé.**
   - Le test injecte `.indisponible` ; la règle « signature non booléenne → indisponible » (web l.120) n'est donc pas testée.
   - → Renommer le test et ajouter ce cas dans `SupabaseEtabPointageGatewayTests` (T7).
4. **`CodeRotatifRules.swift:212` : écart non consigné.**
   - Le message générique remplace `extraireMessageErreur(etatErreur)` du web (l.174) sans être listé dans les écarts assumés (l.17-18).
   - → L'ajouter au commentaire.
5. **`PlanningDerive.swift:366-376` : parité web à surveiller pour T9.**
   - Une période transitoirement invalide fait perdre toutes les exceptions saisies.
   - → À reporter dans T9 : borner le sélecteur de fin (`min` l.318) ou garder les jours précédents.
6. **`PlanningExactEtabTests.swift:102-107` : assertion faible.**
   - Le cas vitest l.135 n'asserte que `erreur != nil`.
   - → Asserter le message exact `messageIncomplet(attendus: 1, charges: 0)`.

Aucune correction n'est exigée avant le merge. Les points 1 à 4 et 6 peuvent être traités dans la PR ou par la tranche consommatrice (T7, T8, T9).

## Intégration sur `feat/ios-lot5` (intégrateur, 2026-11-03)

- `origin/feat/ios-lot5` n'existait pas : branche créée depuis `origin/feat/ios-lot1` (`3c0eed95`, avec T3, T4a et
  T8 du lot 1), puis, dans l'ordre, `git merge --no-ff origin/lot5/l5-t0` (`b5b04835`, commit de fusion `5bd5d163`)
  et `git merge --no-ff origin/lot5/l5-t3` (`0fa08a15`, commit de fusion `a9238316`).
- **Aucun conflit.** Les 4 fichiers communs à T0 et au lot 1 (`check-rpc-contracts.mjs`,
  `tests/node/check-rpc-contracts.node.mjs`, `rpc-contracts.json`, `CONTRATS_RPC_SOIGNANT.md`) ont été fusionnés
  automatiquement : le reclassement lot 4 de `fn_suggestions_missions_pour_soignant` et le passage en `consommee` de
  `fn_dashboard_soignant_complet` (lot 1) coexistent avec les 14 RPC du lot 5. `ios-swift-ci.yml` cumule les ajouts
  de T0 (filtres de chemins + deux étapes du job Cœur) et de T3 (filtres de chemins des 4 sources web gardées).
  Le mineur 9, premier point, de la revue L5-T0 (retard de 22 commits, `--update` à relancer) est ainsi traité :
  `check-rpc-contracts.mjs --update` régénère `rpc-contracts.json` à l'identique (41 RPC).
- **Vérifications après les deux fusions** (ce que les revues n'avaient pas fait) :
  - `node --test tests/node/mobile-delivery-plan.node.mjs tests/node/check-rpc-contracts.node.mjs
    tests/node/textes-juridiques-ios.node.mjs tests/node/contrats-etablissement-ios.node.mjs
    scripts/mobile/check-litteraux-juridiques.test.mjs` : 146 tests, 146 verts, 0 échec ;
  - `node scripts/mobile/check-rpc-contracts.mjs` : 41 RPC, aucune dérive ;
  - `node scripts/mobile/check-litteraux-juridiques.mjs` : 106 fichiers Swift livrés sans littéral juridique (T3
    compris) ; `node scripts/mobile/check-textes-juridiques-ios.mjs` : 102 textes identiques au web ;
  - `export-golden-vectors.mjs` (2 271 vecteurs, dont 658 `planning-derive`) et `export-demo-fixtures.mjs` : aucun
    diff ;
  - JoleneCore : `swift build --build-tests -Xswiftc -strict-concurrency=complete` sans avertissement, puis
    `swift test -Xswiftc -strict-concurrency=complete` : 390 tests XCTest, 0 échec.
  - Non relancés : `swift test` de JoleneSupabase et `xcodebuild` (JoleneDesign, app) — aucune des deux tranches ne
    touche ces cibles, et les 5 symboles publics de premier niveau ajoutés à JoleneCore (`TextesWeb`,
    `EntreeTexteWeb`, `PlanningDerive`, `PlanningExactEtab`, `CodeRotatifRules`) n'apparaissent nulle part ailleurs
    sous `ios-native/` ; `npx tsc -b` et vitest — aucun fichier sous `src/` ni `supabase/` n'est modifié.
- **Point ouvert pour la suite (mineur 9, deuxième point, de L5-T0).** `feat/ios-lot5` porte TL à `3e25f507` (repris
  par T0), alors que `origin/lot2/l2-tl` a avancé depuis à `79f1917d` (`0b7ab88e` puis `79f1917d` : verrou Q9 et
  textes du blueprint v2). `git merge-tree` annonce un conflit dans `Legal/TextesWeb.swift` (section lot 5 de T0
  contre compléments v2 de TL) à la reprise de TL ou de `feat/ios-lot2` : le résoudre en gardant les deux côtés,
  puis relancer `textes-juridiques-ios.node.mjs` et `contrats-etablissement-ios.node.mjs`.
- Les mineurs des deux revues restent ouverts : ils sont à traiter par la tranche (correctif) ou par la tranche
  consommatrice qui touche le fichier (T1, T7, T8, T9), pas par l'intégration. Aucune PR n'est ouverte et rien n'est
  mergé ; HARD STOP n°4 et B9 restent tels que décrits par les revues.

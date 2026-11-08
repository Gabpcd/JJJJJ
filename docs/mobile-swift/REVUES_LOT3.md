# Revues fraîches B8 — lot 3 (app iOS Swift native)

Rapports des revues à contexte vierge (CLAUDE.md, B8) des tranches du lot 3, consignés par l'intégrateur sur
`feat/ios-lot3`. Une section par tranche, dans l'ordre d'intégration. Les rapports sont reproduits tels que
rendus ; seuls les niveaux de titre sont décalés d'un cran pour tenir sous le titre de la tranche.

## L3-T0

### Revue fraîche B8 — L3-T0

**Verdict : CLÔTURABLE.** Ni bloquant ni majeur. Dix constats mineurs, à corriger dans la tranche ou dans la suivante.

Périmètre relu : `git diff origin/feat/ios-lot1...origin/lot3/l3-t0`, commits `85d9a8f6` (test) puis `65f0c27e` (docs), soit 11 fichiers et +3 062/−27 lignes. La revue s'est faite en lecture seule. Je n'ai lancé aucun build ni test et fait aucun appel MCP, car ce n'est pas une PR backend. Le dump `supabase/schema/public.sql`, les edges et le web cités sont identiques entre `main` et la branche, et toutes les confrontations ont été faites sur ces fichiers.

#### Ce qui a été vérifié

- **Périmètre.** Aucune ligne Swift, rien sous `supabase/`, `src/`, `ios/`, `android/` ou `mobile-native/`, aucune migration. Pas de SQL redéfini, pas d'ACL touchée. Les fichiers correspondent à la liste T0 du blueprint, plus la garde et la ligne `run:` de `validate-pr.yml`. La garde du lot 1 ne change que par l'ajout à `INTERDITES_NATIF`, ce qui est cohérent.
- **`RPC_SUIVIES`.** Les 14 RPC sont en `a_venir`, lot 3, dans l'ordre du blueprint, juste après `fn_upsert_token_push`. `fn_lier_iban_verifie_document` est dans `RPC_JAMAIS_SUIVIES` : son seul GRANT va à `service_role` (l.83209-83210), et sa garde 42501 passe par `current_user = postgres` quand elle est appelée depuis `fn_enregistrer_mon_iban` (SECURITY DEFINER, l.32305).
- **`rpc-contracts.json`.** Uniquement des ajouts, 41 entrées dans l'ordre des RPC suivies. `types: null` pour `fn_demarrer_inscription`, `fn_enregistrer_parcours_inscription` et `fn_mes_paiements_escrow`, `manifeste: null` pour les deux RPC d'inscription : c'est conforme à `types.ts` et au manifeste. Le GRANT de `fn_types_exercice_autorises` inclut `anon` (`PUBLIC_VOLONTAIRE`).
- **Fiches RPC.** J'ai contrôlé une soixantaine de numéros de ligne cités : tous exacts. Corps confrontés :
  - push (`void`, 6 RAISE, `{success:false,error}`) ;
  - préférences (création de la ligne par défaut, défauts de colonne, enums à 4 et 18 valeurs) ;
  - inscription (4 et 6 exceptions, 7 codes `ACCOUNT_*`, message web du 23505) ;
  - profil (clés sensibles) ;
  - export RGPD ;
  - confirmation de paiement (5 refus) ;
  - contestation (23514 sur `notifications_type_check` l.70815, index l.75280, trigger l.76080) ;
  - IBAN (9 `error_code`, dont 2 avec `error`) ;
  - revenus et escrow (7 états).

  Les REVOKE et GRANT annoncés correspondent au dump pour les 16 RPC du lot 3.
- **Fiches edge.** `register-soignant` : 16 réponses littérales, 2 replis RPPS, 4 messages de l'annuaire, 3 messages de réservation. `stripe-connect-status` : POST, `force=true`, 7 erreurs, `verifyUserOrServiceRole`, 6 statuts du CHECK. `stripe-connect-onboard` : `Origin` obligatoire, 6 erreurs, `return_url`/`refresh_url`. Payload `send-push` : `ALLOWED_DATA_KEYS` (14 clés), clés racine à côté de `aps`, aucun badge. Fiche PSC. Tout est conforme aux sources.
- **Garde `check-rpc-contracts-lot3.node.mjs`.** Relecture à la main des regex contre les sources (délimiteurs `$$`/`$_$`, messages sur plusieurs lignes, `\'` JS) : elles devraient passer. Elles restent fail-closed sur toute re-baseline, comme au lot 1. **Non exécutée ici** : la CI le confirmera à l'ouverture de la PR.
- **Documents.** `LOT3_PLAN.md` est identique au blueprint v2, préambule mis à part (vérifié par `diff`). `DECISIONS_LOT3.md` reprend D1 à D25, toutes « Adoptée » et fidèles au §7. Il contient aussi les critères amendés (l.196-200, plus PSC l.193), la liste B9 (B3, T7, T8, T12, T13, T14a, T14b, T16), les règles HARD STOP n°4 (verbatim, aucun texte juridique nouveau) et les points §6.1 à §6.11 en attente. `RECETTE_DEVICE_LOT3.md` et `PORTE_LOT3.md` sont présents.
- **HARD STOP n°4 et B9.** Aucun texte juridique nouveau ou reformulé. Le classement B9 de la T0 (non B9) est justifié.
- **Secrets.** Aucun littéral sensible. L'IBAN d'exemple ISO 13616 et les refs de projet sont déjà publics dans le dépôt.

#### Notes de l'auteur

1. **Fuite dans l'export RGPD.** Confirmée **dans le dump** : à la l.55300, `notations_recues` est lu sur `notations_missions` avec `note_id = v_uid AND masque = false`, sans `publie_le IS NOT NULL`, contrairement à `evaluations_publiees` (l.69517). Le point est bien renvoyé à Gabrielle. Il reste à confirmer sur la définition live, ce qui sort du cadre d'une revue non backend.
2. **Audit en double.** Confirmé : l.55304-55311 côté serveur, `SectionConfidentialite.tsx` l.42-48 côté web.
3. **Écarts blueprint/dump.** Confirmés : 6 exceptions, 16 réponses. Le 503 `TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE` figurait déjà, en abrégé, au §2.4 du blueprint (« 503 classification »).

#### Constats mineurs

1. `PARITE_SOIGNANT.md:52` — l'IBAN est placé sous `/soignant/mes-gains`, alors que le web monte `SectionPaiements` dans `/soignant/mon-compte` (`MonCompteSoignant.tsx` l.162-164). Écart de placement à déclarer comme « assumé », comme pour l'export RGPD, ou sous-ligne à déplacer, avec mise à jour du test.
2. `PARITE_SOIGNANT.md:33` — `MonCompteSoignant l.37-48` ne pointe pas les entrées du hub, qui sont vers l.60-120.
3. `PARITE_SOIGNANT.md:27` — la route `/soignant/mon-compte` a pour lot cible « 1 » alors qu'elle porte des sous-lignes du lot 3 → « 1 (T8, T9), 3 (T11) ».
4. `CONTRATS_RPC_SOIGNANT.md:987` — « aucun champ ne peut être vidé » est inexact : une chaîne `''` écrase les champs texte, seuls prénom et nom sont protégés. Le web envoie `|| null`. À préciser pour que T9 envoie `nil`.
5. `CONTRATS_RPC_SOIGNANT.md:1229/1280/1315` — `verify_jwt = false` vient de `config.toml`, qui n'est qu'un mémo selon `CLAUDE.md`. Annoter, et prévoir dans `EdgeResponse` un 401 de passerelle au corps non conforme.
6. `CONTRATS_RPC_SOIGNANT.md:499-500` — « JSON requis » se déclenche avec `p_plateforme = 'WEB'` sans JSON, pas pour un token commençant par `{`.
7. `PORTE_LOT3.md:25` — le critère d'inscription est présenté comme amendé alors que la reformulation attend la validation de Gabrielle (§6.4).
8. `PORTE_LOT3.md:63` — le décompte « 41 RPC » sera faux après L2-T0 : à ajouter à la liste des conflits ou à retirer.
9. `check-rpc-contracts-lot3.node.mjs:312, :370` — deux boucles n'affirment rien si la regex ne trouve rien → remplacer par un `deepEqual` sur les refus attendus.
10. `LOT3_PLAN.md:7` — le renvoi à `LOT2_PLAN.md` est mort jusqu'au merge de L2-T0.

#### Conditions avant merge

- CI verte sur la PR (`validate-pr` avec la « Garde de livraison mobile » à trois fichiers, et la dérive `check-rpc-contracts.mjs` de `ios-swift-ci.yml`). Ces gardes n'ont pas été exécutées pendant cette revue.
- Conflits avec L2-T0 à résoudre en gardant les deux côtés, comme l'auteur l'annonce : `RPC_SUIVIES`, `INTERDITES_NATIF`/« Jamais suivies », `run:`, en-tête et décompte de CONTRATS, `PORTE_LOT3` 6.1, « Dernière mise à jour » de PARITE.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-02)

- Branche créée depuis `origin/feat/ios-lot1` (`3c0eed95`, avec T3, T4a et T8 du lot 1), puis
  `git merge --no-ff origin/lot3/l3-t0` (`65f0c27e`).
- Conflits résolus en gardant les deux côtés : commentaire de `RPC_SUIVIES` dans `check-rpc-contracts.mjs`
  (paragraphe « Lot 3 (T0) » et reclassements du lot 1, dont `fn_suggestions_missions_pour_soignant` en lot 4) ;
  `PARITE_SOIGNANT.md` (« Dernière mise à jour » du lot 1 suivie de la ligne « Lot 3, T0 », ligne Accueil du
  lot 1, ligne `/soignant/profil` du lot 3 et ses trois sous-lignes). `rpc-contracts.json` fusionné
  automatiquement, puis régénéré par `check-rpc-contracts.mjs --update` : 41 RPC, aucun écart.
- Garde exécutée après fusion (ce que la revue n'avait pas fait) : `node --test tests/node/mobile-delivery-plan.node.mjs
  tests/node/check-rpc-contracts.node.mjs tests/node/check-rpc-contracts-lot3.node.mjs` vert (136 tests, 0 échec,
  0 ignoré) ; `check-rpc-contracts.mjs` sans dérive ; `export-golden-vectors.mjs` (1 613 vecteurs) et
  `export-demo-fixtures.mjs` sans diff. Aucun fichier Swift ni web n'est touché par T0 : ni `swift test` ni
  `npx tsc -b` n'ont été relancés pour cette intégration.
- Les dix constats mineurs restent ouverts : ils sont à traiter par T0 (correctif) ou par la tranche suivante qui
  touche le fichier, pas par l'intégration. Le conflit annoncé avec L2-T0 ne se pose pas sur cette branche :
  `origin/lot2/l2-t0` n'est contenu dans aucune autre branche distante (ni `main`, ni `feat/ios-lot1`) ; il se
  résoudra à la reprise de `main` ou de `feat/ios-lot1` quand L2-T0 y sera fusionné.

## L3-T1

### Consignes de l'auteur pour l'intégration (corrections de la revue B8)

Consignées par l'auteur de la tranche, à la demande de la revue fraîche ; le rapport de revue lui-même reste à
reproduire ici par l'intégrateur.

- **`UnwiredPorts.erreur(port:tranche:lot:)`** vit dans `ios-native/Packages/JoleneCore/Sources/JoleneCore/Ports/Lot1Ports.swift`,
  à côté de `erreur(port:tranche:)`, et non dans `Lot3Ports.swift`. L2-T1 la réutilise et ne la redéclare pas dans
  `Lot2Ports.swift` : deux déclarations identiques ne compilent pas (`DECISIONS_LOT3.md`, « Précisions du mémo »).
- **Exceptions métier** (`ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/RPC/RPCResponse+ExceptionsMetier.swift`) :
  `appeler(…, exceptionsMetier:)`, `executer(fallback:exceptionsMetier:_:)` et la visibilité interne de
  `RPCResponse.executer(fallback:_:)` sont posés par L3-T1 ; L2-T1 les réutilise sans les redéclarer. Le helper suit
  désormais `LOT2_PLAN.md` §2.4 et la liste de tests de son T1 : un SQLSTATE déclaré dont le message commence par
  « permission denied for » (GRANT manquant, incident #835) lève `.contract` au lieu d'être restitué
  (`test42501PrivilegeManquantDeclareEstUneErreurDeContrat`) ; 42501 non déclaré reste une session expirée (lot 1,
  `SupabaseErrorMapping` inchangé). Une seule déclaration subsiste à l'intégration ; en cas d'écart entre les deux
  copies, le comportement exigé par `LOT2_PLAN.md` §2.4 fait foi.
- **`NotificationPreferencesPort.enregistrer(_:context:)`** : écart assumé avec le tableau §2.3 de `LOT3_PLAN.md`
  (`enregistrer(_:, smsAlertes: Bool?, context:)`). Le paramètre `smsAlertes` est retiré :
  `PreferencesNotifications.smsAlertesActives` est la seule source de l'alerte SMS (principe « État dérivé ») ; nil =
  colonne non écrite (parité web `profilSmsPresent`, `PageParametresNotifications.tsx` l.230). T6 implémente cette
  signature.
- **Critère de clôture du lot 1 (L1-T12)** : aucun nom du lot 1 dans `unwiredPorts`
  (`unwiredPorts.filter(Lot1PortsTests.portsLot1.contains).isEmpty`), jamais `unwiredPorts.isEmpty`, qui reste faux
  tant que le lot 3 est ouvert (`PRINCIPES.md` §2). Le test de clôture de L1-T12 prend cette forme.
- **`EdgeResponse`** : un 2xx dont le corps n'est pas un objet JSON (portail captif, proxy, corps vide, `null`,
  tableau, scalaire) est un refus au `fallback`, sans code. `estSucces` reste plus faible que `RPCResponse.estSucces`
  (aucun drapeau exigé, à cause de `stripe-connect-status`) : chaque gateway exige ensuite ses propres clés.
  `delete-account` n'est pas concerné (`issue(corps:)` exige `success == true`).

### Revue fraîche B8 — L3-T1

**Verdict : CLÔTURABLE.** Aucun constat bloquant ni majeur. Six constats mineurs, à traiter dans cette tranche ou dans la suivante.

#### Périmètre

J'ai relu en entier `git diff origin/feat/ios-lot3...origin/lot3/l3-t1` (base `79ad1a81`, identique à la pointe de `feat/ios-lot3`), soit cinq commits :
- `3f211b30` : tests ;
- `020ef84e` : implémentation ;
- `c2f6099d` : docs ;
- `e633ffb6` : tests des corrections ;
- `452973c6` : corrections.

Cela fait 22 fichiers, +1 900/−27. La branche se fusionne sans conflit dans `feat/ios-lot3`.

Méthode : lecture seule, sans build, sans test et sans appel MCP.
- J'ai confronté le code au SDK supabase-swift **v2.55.5** extrait dans DerivedData : `FunctionsClient.rawInvoke` (le relais est vérifié avant `httpError`) et les deux surcharges de `PostgrestBuilder.execute` (Void et Decodable ; rejeu limité à GET et HEAD).
- J'ai confronté les citations au dump `supabase/schema/public.sql` de la branche et aux edges `register-soignant`, `stripe-connect-status`, `stripe-connect-onboard` et `_shared/errors.ts`, ainsi qu'à `_shared/stripe-errors.ts`.

#### Ce qui a été vérifié

##### Conformité au blueprint v2 (T1)

**Fichiers.** Tous les fichiers listés par T1 sont présents :
- les 13 ports backend, chacun avec son stub `Unwired…` ;
- les 4 capacités système hors `Gateways` ;
- `Lot3Results` avec les 9 types exigés ;
- `AuditAction` avec 3 cas de plus ;
- `câblerLot3` dans les deux mondes, sans troisième init (les deux inits du lot 1 sont restés mot pour mot) ;
- `unwiredPorts` étendu ;
- la surcharge `erreur(port:tranche:lot:)`, qui rend pour `lot: 1` le même texte que l'ancienne version ;
- PRINCIPES §2.

**Écarts annoncés par l'auteur.** Je les juge tous acceptables et alignés sur `LOT2_PLAN.md` §2.4 :
- fichiers séparés `RPCResponse+ExceptionsMetier.swift` et `RPCResponse+SansCorps.swift` ;
- `executer` passé en interne ;
- `IssueDesactivationPush` ;
- `statut(force:)` (correction 17) ;
- `ExportDonneesRGPD` ;
- `enregistrer(_:context:)` avec une seule source pour l'alerte SMS.

**Aucun fichier hors périmètre.** `SupabaseAccountGateway` est bien attribué à L3-T1 par le tableau des dépendances. Rien sous `supabase/`, `src/` ni dans l'app ; aucune migration.

##### `EdgeResponse`
- Le corps de `FunctionsError.httpError` est lu avant tout mapping.
- Un 401 donne `.unauthorized`, quel que soit le corps.
- Les refus se lisent à la fois dans un 2xx (drapeaux, ou `error` sans drapeau vrai) et hors 2xx.
- Un 2xx dont le corps n'est pas un objet JSON est un refus au `fallback`. C'était le majeur de la revue précédente : il est corrigé et testé (HTML, vide, `[]`, `null`, scalaires, 201 et 204 vides).
- Un objet sans drapeau n'est pas un refus, ce qui convient à `stripe-connect-status`.
- `x-relay-error` donne `.unknown`, jamais un succès, conformément à l'ordre du SDK.
- Les options sont transmises telles quelles (`force=true`, `Origin`).
- Les codes machine ne sont jamais affichés. J'ai vérifié chaque forme réelle : `_shared/errors.ts` (`error` est le miroir de `message`), `{error:'CODE'}`, `mapStripeError` (`{error: code, message}` toujours accompagné d'un `userMessage`), et `{error, error_code}` de `delete-account`.

##### `SupabaseAccountGateway`
Comportement inchangé :
- `success == true` reste exigé ;
- seuls `error` et `error_code` sont lus ;
- un 401 reste un refus affiché, ce qui est voulu au lot 1.

Aucun autre appelant de `lire` ou de `refus(RPCResponse)`, ni sur la branche ni sur les branches `lot1/*` non intégrées.

##### Exceptions métier
- Ordre respecté : `[CODE DU TRAVAIL]` (exclu dans le `where`, restitué par l'`executer` du lot 1), puis les exceptions déclarées, puis `SupabaseErrorMapping`, inchangé.
- Le refus produit a la forme `{success:false, ok:false, code:"SQLSTATE_x", error}`, comme au lot 2.
- Un SQLSTATE déclaré dont le message commence par « permission denied for » donne `.contract`. Sans déclaration, un 42501 garde le comportement du lot 1.
- Un `JoleneError` levé à l'intérieur traverse `map` sans être modifié.
- Pour les RPC `void`, la surcharge `execute()` → `Void` est bien celle choisie, et 204, 200 vide et `null` donnent un succès. Le contrat `RETURNS void` de `fn_upsert_token_push` est suivi dans `rpc-contracts.json`.
- Les messages et numéros de ligne cités ont été recoupés dans le dump : 30110, 30118, 30127, 32456, 55649, 55652, 64642 et 64645, plus la liste blanche l.32436-32442.

##### Tests
Chaque test porte une règle réelle :
- les gardes de dump (CHECK `journaux_audit_action_check` l.70243, `stripe_connect_onboarding_statut_check` l.72036, enum `canal_notification` l.22-27) ont été vérifiées sur le fichier ;
- `return_url` et `refresh_url` l.202-203 ;
- la liste blanche par `Mirror` ;
- « une seule requête » est comptée partout.

La lecture de fichiers du dépôt par `#filePath` dans JoleneCoreTests sur le simulateur suit un usage déjà établi (`DemoNoNetworkTests`, `LinksAASATests`), compatible avec la porte `skipped === 0`.

##### Régressions des lots 0 et 1
- `DemoNoNetworkTests` : ni `URLSession` ni import réseau dans JoleneCore.
- Sentinelle démo : les stubs lèvent sans aucun réseau.
- Aucun identifiant d'accessibilité, aucun XCUITest et aucun écran touchés ; le comportement dans les trois formats ne change pas.
- Aucun `switch` exhaustif sur `AuditAction`.
- Aucun nom en collision dans l'app, dans JoleneDesign ni sur les branches `lot2/*`, `lot3/*`, `feat/ios-lot{1,2,4,5}`.
- `AppContainer` passe bien par `DemoWorld.gateways()` et `SupabaseGateways.make`, qui appellent tous deux `câblerLot3`.

##### Concurrence (Swift 6)
- Tous les ports sont `Sendable`, de même que les types d'échange.
- Les closures de décodage ne s'échappent pas.
- Aucun `MainActor` n'est requis à ce stade.

##### Juridique, B9 et secrets
- **HARD STOP n°4** : aucun texte nouveau affiché à l'utilisateur, aucun wording juridique.
- **B9** : aucun selon le blueprint. Les ports Stripe, paiements et IBAN ne sont que des interfaces dont les stubs lèvent une erreur, sans aucun flux monétaire.
- **Secrets** : aucun littéral suspect. L'IBAN de test est l'exemple ISO 13616 prévu au §2.7.

#### Constats mineurs
Le détail (fichier:ligne et correction attendue) est dans la liste `mineurs` :
1. Des erreurs de la plateforme Supabase (`BOOT_ERROR`, `WORKER_LIMIT`, `NOT_FOUND`) seraient affichées telles quelles. Point à confirmer selon la présence de `x-relay-error`.
2. Un `error` qui n'est pas du texte, dans un 2xx sans drapeau, n'est pas traité comme un refus.
3. Le garde sur la source de l'edge `stripe-connect-onboard` est absent du filtre `paths` de `ios-swift-ci.yml`.
4. Trois écarts de signature (`desactiver`, `statut(force:)`, `exporter`) ne sont pas consignés dans REVUES_LOT3.
5. Les assertions à liste exacte sur `unwiredPorts` casseront à l'arrivée du bloc du lot 2, et la consigne de coordination n'existe que côté lot 3.
6. L'en-tête de `Lot3Ports.swift` dit que toutes les méthodes reçoivent un contexte, mais `desactiver(token:)` n'en reçoit pas, sans que ce soit expliqué.

#### Pour l'intégrateur
- Si L2-T1 est intégré lui aussi : conserver une seule copie de `RPCResponse+ExceptionsMetier.swift` (conflit add/add) et une seule déclaration de `UnwiredPorts.erreur(port:tranche:lot:)`. Comme le consigne REVUES_LOT3, c'est `LOT2_PLAN.md` §2.4 qui fait foi.
- Lot 1 n'est pas clos (T4b, T5, T6, T10, T12) : à chaque reprise de `feat/ios-lot1`, ajuster les listes `portsEnAttenteLot1` en gardant le bloc du lot 3, et formuler le critère de L1-T12 comme un filtre, jamais comme `unwiredPorts.isEmpty`.
- Ni build ni test n'ont été lancés pour cette revue. La CI, `swift test` en concurrence stricte et les trois formats du simulateur, fait la preuve.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-03)

- `int-lot3` créée depuis `origin/feat/ios-lot3` (`79ad1a81`). `git merge --no-ff origin/feat/ios-lot1` : déjà à jour
  (`3c0eed95`, déjà contenu depuis l'intégration de L3-T0 ; aucune avancée du lot 1 à reprendre, donc aucune liste
  `portsEnAttenteLot1` à ajuster).
- `git merge --no-ff origin/lot3/l3-t1` (`452973c6`) → `2f893735`, sans conflit.
- Consignes « Pour l'intégrateur » : aucune branche `lot2/*` n'est contenue dans `feat/ios-lot3`, la déduplication de
  `RPCResponse+ExceptionsMetier.swift` et de `UnwiredPorts.erreur(port:tranche:lot:)` ne se pose donc pas ici ; elle
  s'appliquera à la rencontre avec L2-T1 (`LOT2_PLAN.md` §2.4 fait foi).
- La liste `mineurs` citée par le rapport (fichier:ligne de chaque constat) n'accompagnait pas le texte transmis à
  l'intégrateur ; les six constats restent ouverts, à traiter par T1 (correctif) ou par la tranche suivante qui touche
  le fichier.

## L3-T1b

### Revue fraîche B8 — L3-T1b

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur, huit constats mineurs.

#### Périmètre

J'ai relu `git diff origin/feat/ios-lot3...origin/lot3/l3-t1b` en entier : 9 fichiers, +1 766 lignes.
- La base de fusion est bien la pointe actuelle de `feat/ios-lot3` (79ad1a81).
- Quatre commits, tests d'abord : b9701f71 (tests) puis fbdd76a0 (code), et 81daa073 (tests des corrections) puis 65cbd9a4 (corrections).
- Fichiers touchés : les sept composants et leur fichier de tests, tous nouveaux sous `JoleneDesign`, plus une puce dans `DECISIONS_LOT3.md`. Cette puce est un bloc séparé du bloc modifié par L3-T1 (vers la l.151 contre l.115-122), sans conflit attendu.
- Rien sous `src/`, `supabase/`, `ios/`, `android/` ni `mobile-native/`, aucun fichier d'app, pas de CI.

La revue s'est faite en lecture seule, sans build, sans test du projet et sans appel MCP.
- Pour recouper, j'ai copié les six sources web dans le scratchpad et lancé deux petits scripts Node v24.14.0 hors dépôt : vecteurs de hachage et d'initiales, et rapports de contraste.
- `LOTS_2_5_DECISIONS.md` du scratchpad a été effacé. Le cadre a donc été lu dans les copies du dépôt : `LOT3_PLAN.md` (§2.1, T1b, T4-T6, T11, T12), `DECISIONS_LOT3.md`, `PRINCIPES.md` et `CLAUDE.md`. Pour le lot 4, j'ai lu directement la branche `origin/lot4/l4-t1b`.

#### Ce qui a été vérifié

- **Blueprint T1b.** Les sept fichiers prévus sont là, avec tests de contraste clair et sombre, de cibles 44 pt et d'identifiants. Le critère « XCUITest indirect » est respecté. Les composants n'utilisent que des API iOS 16 (`ViewThatFits`, `dynamicTypeSize`, `.tint`, `overlay {}`) et les jetons dynamiques existants.
- **Gardes de dérive.** J'ai relu dans les fichiers web chacune des 28 chaînes cherchées par les tests, ainsi que les blocs relus par extraction (`TEXTES.soignant`, liste `FALLBACK_COLORS`, lignes à 14 espaces de la note et des boutons) : toutes présentes à l'identique. Tous les numéros de ligne cités dans les docs sont exacts (ToggleCanal l.442-461, matrice l.402-413, `aria-label` l.410, MesGains l.664 et l.748, DemandePermissionPush l.20-28, l.149, l.158, l.164, ChangementMotDePasse l.198-242, AvatarUpload l.10-31, l.78, l.117, l.179).
- **Vecteurs Avatar.** J'ai recalculé avec le code web sous Node les 22 hachages (et leurs index de couleur) et les 15 jeux d'initiales : 0 écart. J'ai contrôlé que les accents du fichier de tests sont précomposés (`É` = C3 89). Le port Swift (`&<<`, `&-`, `&+` sur `Int32`, puis `Int(magnitude)`) est équivalent à `| 0` suivi de `Math.abs`, y compris pour `Int32.min`. L'emoji donne `\ud83d` sur le web : c'est l'écart documenté.
- **Contrastes.** J'ai recalculé chaque assertion. Toutes tiennent, par exemple :
  - rose / cloud 2,51 ;
  - rose-700 / rose100 3,54 ;
  - bubblegum / lavender 5,18 ;
  - butter-800 / butter100 4,09 ;
  - blanc sur émeraude 4,87 (le minimum) ;
  - `#2B183D` sur les arrêts du dégradé : de 4,95 à 10,81 ;
  - raison du blocage sous voile : 2,04 à 2,12, donc bien sous AA comme le test l'affirme ;
  - remplissage de la jauge sur mauve-100 : de 3,12 à 6,10 en clair.

  `bubblegum` sur rose100 (4,44) reste exclu, selon le précédent `SlotList` du lot 1.
- **Swift 6 et concurrence.** Les motifs sont ceux du lot 1, déjà verts en CI sous Xcode 26.4.1 :
  - types imbriqués `Presentation` et `Appearance` non isolés, appelés depuis des tests non `@MainActor` ;
  - `nonisolated static` uniquement sur des types `Sendable` ;
  - tests de rendu marqués `@MainActor`.

  Aucun `@unchecked`, `nonisolated(unsafe)`, `Task` ni `try!`.
- **HARD STOP n°4.** Aucun texte juridique nouveau ni reformulé. Les textes repris (pré-prompt, libellés de force, critères, « Changer ma photo de profil ») sont verbatim et gardés par un test. Les textes seulement vocalisés (« environ », « Montant indisponible », « critère rempli / non rempli ») sont listés dans `DECISIONS_LOT3.md` pour relecture par Gabrielle (§6.7). Le texte affiché reste verbatim. B9 n'est pas touché.
- **Corrections de la revue précédente.** M1 et m1 à m4, m7 à m9 sont effectifs dans le code et les tests :
  - identifiants `push-preprompt-activer` / `-plus-tard` / `push-ouvrir-reglages`, avec surcharge et dérivation ;
  - capsule sur une ligne, rectangle arrondi de rayon 8 au-delà (8 ≤ marge horizontale, le raisonnement est juste) ;
  - fond de PermissionCard posé sur la carte bornée ;
  - raison du blocage dans le libellé et hors du voile ;
  - règle commune `spokenText` ;
  - identifiants `compte-mdp-*`.

  Le XCUITest `app.switches[id].tap()` touche le centre de la ligne, donc le libellé, ce qui bascule l'interrupteur une seule fois.
- **Régressions lots 0 et 1.** Aucun identifiant existant touché ; DemoNoNetworkTests, sentinelle démo et matrice des trois formats sont inchangés. Seule collision de nom dans les branches : `StatusPill` du lot 4 (constat 1). `Segment` du lot 5 est imbriqué dans un type du cœur, sans conflit.
- **Divers.** Aucun réseau, aucun littéral qui ressemble à un secret. `XCTSkip` sur une source absente est bien bloqué par la porte `skipped === 0` de la CI.

#### Constats mineurs

1. **`StatusPill.swift:28` — doublon du lot 4.** `origin/lot4/l4-t1b` contient déjà `Components/StatusPill.swift`, copie exacte de la version d'avant revue (fbdd76a0) ; la version corrigée (65cbd9a4) en diverge. À la rencontre des deux branches sur main, il y aura un conflit add/add. Avec la règle « garder les deux côtés », `public struct StatusPill` serait déclaré deux fois et le build casserait.
   - **Correction :** écrire dans la PR et dans DECISIONS que la version lot 3 l'emporte et que la copie du lot 4 est supprimée. L'API utilisée par le lot 4 reste compatible.
2. **`AmountRow.swift:108-126` — disposition instable.** `ViewThatFits` juge sur la largeur idéale du texte sur une ligne : un titre long fait passer la ligne en colonne. Dans T12, les lignes alterneront entre les deux dispositions, alors que le web garde toujours le montant à droite (MesGains l.736-737).
   - **Correction :** disposition en ligne par défaut, titre flexible, colonne montant en `fixedSize` ; colonne seulement aux tailles d'accessibilité. Ajouter un test avec un titre long.
3. **`AmountRow.swift:115-118` et `StatusPill.swift:120` — testabilité pour T12.** Avec `children: .ignore` et aucun trait, le montant affiché tel quel est illisible par XCUITest (le libellé est « environ … »), il n'y a qu'un identifiant pour les trois prévus par T12 (l.703-704), et les éléments sortent en `otherElements`.
   - **Correction :** documenter le montage et le contrat d'assertion, et ajouter `.isStaticText`.
4. **`AvatarView.swift:95,109-110` — zone de tap.** `scaledToFill` déborde ; `clipShape` ne coupe pas la zone de toucher, ce qui l'étendrait hors du cercle dans le bouton de T10.
   - **Correction :** `.contentShape(forme)`.
5. **`PermissionCard.swift:85-86` — largeur.** La doc dit 448 px (`sm:max-w-md`) mais la valeur est 480, figée par le test (l.521).
   - **Correction :** aligner sur 448 ou justifier 480.
6. **`PasswordCriteriaList.swift:101-102` — « Force : ».** Deux `Text` dans un `HStack` : l'espace dépend de l'espace final du premier, et le tout ne passe pas à la ligne comme une phrase aux tailles d'accessibilité.
   - **Correction :** concaténer les `Text`, avec `foregroundColor` (cible iOS 16).
7. **`JoleneDesignLot3Tests.swift:20` — angle mort de la CI.** Les six sources web relues ne sont pas dans les `paths` d'ios-swift-ci.yml (l.13-33, l.36-56), pas plus que `src/index.css` du lot 1. Une PR web merge sans rouge et le natif reste figé jusqu'à la prochaine PR iOS. Le report à T17 n'est noté que dans le scratchpad.
   - **Correction :** l'inscrire dans DECISIONS_LOT3 ou PORTE_LOT3.
8. **`AvatarView.swift:9` — promesse « aucun réseau » non verrouillée.** Aucune garde ne couvre JoleneDesign ; DemoNoNetworkTests ne lit que JoleneCore.
   - **Correction :** garde statique sur `Sources/JoleneDesign` (aucun `URLSession`, `AsyncImage` ni `URL(string:`).

#### Notes pour les tranches suivantes (pas des défauts de T1b)

- **T12.** Sur le web, le montant « net salarié » est un bouton « Voir le détail de l'estimation salariale » (MesGains l.738-744), qui ouvre le détail des cotisations. Ce bouton n'apparaît ni dans LOT3_PLAN ni dans PARITE_SOIGNANT, et AmountRow n'a pas d'emplacement d'action. Il faut le porter (bouton autour de la ligne ou action dédiée) ou le déclarer comme écart assumé.
- **T12 (opacité).** La matrice web utilise `opacity-40`, ToggleRow 0,5 partout. L'écart est insignifiant, à consigner si T6 veut la parité stricte.
- **Autres tranches.** Les notes de l'auteur pour T5, T9, T10, T11 et T12 sont justes : T5 utilise `pushSoignant`, T9 et T10 fournissent une `Image` déjà chargée, T11 passe les critères de JoleneCore, T12 passe les chaînes de `MontantMission`.

#### Conditions avant merge

- **CI.** ios-swift-ci verte sur les trois formats (iphone, ipad-portrait, ipad-landscape), avec JoleneDesignTests exécutés, `skipped == 0` et `failed == 0`. Ce sera la **première exécution iOS réelle** des 28 tests : rendu UIHostingController, mesures 44 pt, retour à la ligne de StatusPill.
- **Corps de PR.**
  - Toolchain locale Xcode 16.4 / iOS 18.6 contre Xcode 26.4.1 en CI.
  - Tests jamais exécutés sur iOS, seulement build-for-testing.
  - « Livré ≠ mergé » : aucun XCUITest visible à cette tranche.
  - Résolution du doublon StatusPill avec le lot 4 (constat 1).
- **Gabrielle.** Les trois textes seulement vocalisés sont à relire (§6.7). Ce n'est ni un HARD STOP ni du B9.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-03)

- `git merge --no-ff origin/lot3/l3-t1b` (`65cbd9a4`) → `eee72265`. `DECISIONS_LOT3.md` fusionné automatiquement : la puce
  de T1b et le bloc modifié par T1 sont distincts, comme la revue l'annonçait. Aucun autre fichier commun.
- Constat 1 (doublon `StatusPill`) : `feat/ios-lot3` ne contient aucune branche du lot 4, le conflit add/add ne se pose
  pas ici. Il reste à résoudre à la rencontre avec `lot4/l4-t1b` selon la correction proposée par la revue (une seule
  déclaration, la version du lot 3) ; « garder les deux côtés » ne s'applique pas à ce fichier, puisque deux
  `public struct StatusPill` ne compilent pas.
- Les huit constats mineurs restent ouverts, à traiter par T1b ou par la tranche consommatrice (T5, T6, T10, T11, T12).
  Les JoleneDesignTests (dont `JoleneDesignLot3Tests`) ont été compilés par `build-for-testing` (voir L3-T2), mais pas
  exécutés : la première exécution iOS reste celle de la CI.

## L3-T2

### Revue fraîche B8 — L3-T2

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur. Cinq mineurs sont à traiter dans la tranche ou dans le corps de PR.

Branche relue : `origin/lot3/l3-t2` (e834ef0c), comparée à `origin/feat/ios-lot3` (79ad1a81) avec `git diff A...B`. 26 fichiers, dont 7 JSON golden.
Mode : lecture seule (aucun build, aucun test projet, aucun MCP, aucune écriture). Le cadre scratchpad (LOTS_2_5_DECISIONS.md, LOT3_PLAN.md) est absent du disque. J'ai relu à la place `docs/mobile-swift/LOT3_PLAN.md` (§T2, v2), `DECISIONS_LOT3.md`, `PRINCIPES.md` et `CLAUDE.md` sur la base.

#### Ce qui a été vérifié

- **Exporteur** (`scripts/mobile/export-golden-vectors.mjs`)
  - L'exception nommée D22 est bornée à `pushNative.ts`, clé = URL du parent. Les modules inertes lèvent à l'appel, à la lecture ou à la conversion. `./nativeLinks` reste réel.
  - Garde des imports : présente (voir mineur 1).
  - Les `case` sont extraits par l'AST TypeScript, bornés au corps de `navigationPathForEvent`, avec échec sur un `case` non littéral.
  - `canon()` suit `JSON.stringify` (undefined, trous, toJSON, nombres non finis) ; sa garde de démarrage est relue.
  - `canonEcrit` refuse `undefined` et vérifie l'aller-retour JSON. `verifieVitest` compare la forme écrite.
  - Les cas vitest des 6 modules sont recopiés fidèlement : 15 attentes pushNative, paiement, finance, profil, modes.
  - La CI fait bien `npm ci`. `typescript` et `@capacitor/core` sont des dépendances du dépôt.
- **Ports Swift comparés ligne à ligne au web**
  - `navigationPathForEvent` + `valeurTexte` / `segment` / `lienExplicite`.
  - `missionFinanceDisplay` : contrat effectif, correction Rist, `??` JS, `Math.round`.
  - `paiementSoignantUi` : `Number()`, `toFixed(2)` exact avec égalités vers la plus grande valeur absolue, `localeCompare` sur un domaine uuid, `??` contre texte vide.
  - `valider-profil-soignant`, `{error}` en HTTP 200 compris.
  - `session-count` : `parseInt`, `String(n)` aux chiffres les plus courts.
  - `preferencesModesExercice` et listes RPPS (constantes.ts l.55, l.61 ; register-soignant l.49, l.260-261).
- **Émulation hors disque de la logique Swift relue, contre les vecteurs versionnés : 0 divergence**
  - paiement : 284 répartitions + 344 classements ;
  - finance : 560, y compris les assertions de type strict, aucun montant texte ;
  - push : 873 vecteurs sans lien ;
  - session : 72 (seuls écarts : −0 contre 0, égaux en Swift) ;
  - profil : 277.
  - `typesRoutes` du web est identique à `PushRouting.typesRoutes` : 32 types, même ordre.
  - Les liens explicites (139 vecteurs) dépendent de `JoleneLink.normalize` du lot 0, non modifié. Le contrôle à la main des 25 formes de `LIENS` ne montre aucun écart.
- **Libellés (HARD STOP n°4)**
  - Ils sont verbatim, octet pour octet, et en NFC des deux côtés : missionFinanceDisplay.ts l.103-104, l.115-116, l.126-127 ; paiementSoignantUi.ts l.103-114. Les citations de lignes sont exactes.
  - Aucun texte nouveau. Modes d'exercice et RPPS : codes et listes seulement, aucun blocage de mode d'exercice. L'exception AS (`InscriptionSoignant.tsx` l.221-222) est bien renvoyée à T8.
- **Décisions et blueprint**
  - D5 : les colonnes exactes de `MesGains.tsx` l.95 sont vérifiées, la correction reste inactive ; un témoin à 336,96 est présent.
  - D11 et D22 sont respectées.
  - Écarts déclarés et acceptables : 7 fichiers au lieu de 6, rôles en plus, `incrementerSession`, code unique `PROFIL_INVALIDE`.
- **Intégration**
  - `ValeurJSON.swift` a le même blob que L2-T2 (ce9754d3).
  - Aucune collision de type avec la base, L2-T2, L3-T0, L3-T1 ou L3-T1b.
  - Le filtre de chemins `ios-swift-ci.yml` couvre les 6 modules (pull_request et push).
- **Concurrence**
  - Types `Sendable`, règles statiques pures, aucun état partagé.
  - Je n'ai pas repéré d'erreur de compilation ni de `var` non muté (le job CI exige 0 avertissement).
- **Non-régression lots 0 et 1** : ni UI, ni identifiants d'accessibilité, ni DemoNoNetworkTests, ni sentinelle démo, ni formats de lien ne sont touchés. Aucun littéral ressemblant à un secret. Aucun fichier hors périmètre.

#### Mineurs

1. **Garde des imports de `pushNative.ts` par regex** (`export-golden-vectors.mjs:139`). Elle ignore les guillemets doubles, les imports à effet de bord et `export … from`. → Passer par l'AST TypeScript.
2. **Le rejeu golden du push contourne `path(userInfo:)`** (`RulesPushRoutingTests.swift:15`, `PushRouting.swift:83`). → Rejouer via `userInfo` (String/NSNumber).
3. **`montantRestant` calculé côté client** (`EtatPaiement.swift:95`). Il est en tension avec PRINCIPES §3 / D4, et D5 ne couvre que la correction Rist. → Le consigner pour T12/T13.
4. **Primitive `trim` en double avec `JSTexte` de L2-T2** (`PrimitivesJS.swift:24-26`). → Tâche d'intégration tracée : un seul port.
5. **Précisions de doc** (`ValidationProfil.swift:10, :65`). → Citer le `catch` l.197-198 ; parler de « toute unité de substitution non appariée ».

#### Ce que je n'ai pas pu prouver (laissé à la CI)

- `swift build --build-tests` / `swift test` de JoleneCore sur macOS et sur le simulateur.
- `node scripts/mobile/export-golden-vectors.mjs` suivi de `git diff --exit-code`, en particulier pour l'absence de changement des fichiers lots 0 et 1 avec le nouveau `Collecteur`.
- Les 139 vecteurs de liens rejoués contre `JoleneLink.normalize`.

#### Pour le corps de PR

Reprendre les conflits annoncés avec L2-T2 :
- la double déclaration de `constantes` ;
- les sections de règles à prendre entières de chaque branche ;
- `fichiers` ;
- `Golden.fichiers` ;
- le filtre de chemins de `ios-swift-ci.yml`.

Y ajouter les mineurs 3 et 4.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-03)

- `git merge --no-ff origin/lot3/l3-t2` (`e834ef0c`) → `32e2d0f7`, sans conflit. Aucune branche `lot2/*` n'étant
  contenue dans `feat/ios-lot3`, les conflits annoncés avec L2-T2 (`constantes`, sections de règles, `fichiers`,
  `Golden.fichiers`, filtre de chemins de `ios-swift-ci.yml`) et le mineur 4 (un seul port de `trim`/`JSTexte`) se
  poseront à la rencontre avec le lot 2, pas ici. Les cinq mineurs restent ouverts.
- **Vérifications exécutées sur `32e2d0f7`** (pointe contenant T1, T1b et T2 ; c'est ce que les trois revues avaient
  laissé à la CI) :
  - `node --test tests/node/mobile-delivery-plan.node.mjs tests/node/check-rpc-contracts.node.mjs
    tests/node/check-rpc-contracts-lot3.node.mjs` : 136 tests, 0 échec, 0 ignoré. Aucun test Node n'est dédié à
    `export-golden-vectors.mjs` : ses gardes (`canon`, `canonEcrit`, `verifieVitest`, `case` bornés) s'exécutent à
    l'export ci-dessous.
  - `node scripts/mobile/export-golden-vectors.mjs` : 4 306 vecteurs, dont ceux du lot 3 (`push-routing` 1 013,
    `session-count` 72, `mission-finance-display` 560, `paiement-soignant-ui` 651, `valider-profil-soignant` 277,
    `preferences-modes-exercice` 97, `professions-rpps` 23). Aucun diff sous `ios-native/` ni `scripts/mobile/`, aucun
    fichier non versionné : les fichiers des lots 0 et 1 sont inchangés avec le nouveau `Collecteur`.
  - `node scripts/mobile/export-demo-fixtures.mjs` : aucun diff.
  - `node scripts/mobile/check-rpc-contracts.mjs` : 41 RPC, aucune dérive.
  - `swift build --build-tests` puis `swift test`, avec `-Xswiftc -strict-concurrency=complete`, toolchain locale
    Xcode 16.4 (16F6) : JoleneCore 356 tests XCTest, 0 échec, 0 ignoré, 0 avertissement ; JoleneSupabase 200 tests,
    0 échec, 0 ignoré, 0 avertissement (hors `.build/checkouts/`).
  - `xcodebuild build-for-testing -scheme Jolene` sur le simulateur existant « Jolene iPhone 16 Pro Max » (iOS 18.6),
    `-derivedDataPath` dans le worktree, `COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO` : `TEST BUILD
    SUCCEEDED`, 0 avertissement de compilation (seules les notes « Metadata extraction skipped » de
    `appintentsmetadataprocessor`). Cibles compilées : app, JoleneUITests, JoleneCoreTests, JoleneSupabaseTests et
    JoleneDesignTests.
- **Non exécuté** : aucun test sur simulateur, ni unitaire iOS ni XCUITest (disque presque plein, consigne de la
  tâche). L'exécution sur les trois formats (iphone, ipad-portrait, ipad-landscape) avec `skipped == 0` reste la preuve
  apportée par la CI, en Xcode 26.4.1 (16.4 en local).
- Aucun correctif d'intégration n'a été nécessaire, donc pas de commit `fix(ios-native): intégration lot 3 …`. Les
  dossiers de build (`.build` des packages, `-derivedDataPath`) ont été supprimés après vérification.

## L3-T3

> **Intégrée sous le nom « L3-T3a » seulement** (livraison partielle). T3 reste ouverte jusqu'à T3b (coordinateur de
> liens de L1-T10, XCUITest sur trois formats) et sa propre revue fraîche B8.

### Revue fraîche B8 — L3-T3

**Verdict : CLÔTURABLE, pour la livraison partielle L3-T3a seulement.** Aucun bloquant, aucun majeur, sept mineurs. **T3 n'est pas close** : le critère « Universal Links complets » n'est pas atteint tant que T3b n'est pas faite (coordinateur et XCUITest sur 3 formats). L'auteur le dit lui-même et le consigne.

#### Périmètre

J'ai relu `git diff origin/feat/ios-lot3...origin/lot3/l3-t3-v2` en entier : base `2297747d`, HEAD `84ece4a4`, 7 commits, 10 fichiers, +1 039/−33. Ordre des commits : tests d'abord à chaque passe (`35c1fa97`, `16bc5253`, `df5a5b30`), puis le code, puis la doc (`84ece4a4`). La revue s'est faite en lecture seule : ni build, ni test, ni appel MCP, car rien ne touche au backend. Les journaux de l'auteur (`t3fix-test*.log` : 376 tests, 0 échec, 0 avertissement) sont un indice, pas une preuve ; la CI tranchera.

#### Ce qui a été vérifié

- **Absence de L1-T10, confirmée.** Aucune branche distante n'a `onOpenURL`, `onContinueUserActivity`, `DeepLinkCoordinator.swift` ou `DeepLinkIntent.swift`. Les seules occurrences sont des commentaires (`PresentateurRenvoiWeb.swift`, qui n'est qu'un protocole sans implémentation). Il était donc impossible de livrer T3 en entier ; requalifier la branche en T3a avec un reliquat T3b est honnête : PARITE ne change aucun statut et aucun critère n'est revendiqué.
- **Nom `DestinationLien`.** Le renommage est justifié : LOT1_PLAN l.53 et l.304-305 attribuent `Links/DeepLinkIntent.swift` et `DeepLinkIntentTests` à L1-T10, avec un autre rôle (intention différée, epoch). Les branches WIP du lot 3 (`wip/lot3-l3-t6`, `t9`) ne font référence ni à l'ancien nom ni au nouveau.
- **Table de routage.** Toutes les sources web citées sont exactes :
  - `src/App.tsx` : l.286, 290, 291, 313, 314, 325, 327, 335, 339, 341, 393, 395-397, 399-400, 417-418, 433, 437 ;
  - `MesGains.tsx` : l.833 et l.899-900 ;
  - `PageStripeConnect.tsx` : `success === 'true'` ;
  - `stripe-connect-onboard` : l.202-203 ;
  - `pushNative.ts` : l.294-296 ;
  - `BarreNavigation.tsx` : l.37 ;
  - `InscriptionRapide.tsx` : l.35-42 ;
  - `InscriptionSoignant.tsx` : l.109-117.

  PSC, `/inscription/etablissement`, `/inscription/soignant/completion` et `/inscription/succes` restent dans Safari. L'AASA garde ses 15 motifs. La séparation `.profil` / `.monCompte` et le maintien de score et fiabilité sur le hub suivent le blueprint v2, et l'écart est consigné.
- **`DestinationLien.ecranNatifLivre`.** Les `switch` sont exhaustifs, y compris sur `SectionRevenus` et `EtapeInscription.Page` : un nouveau cas ou la fusion de `.favoris` (L1-T4b) ne compilera pas sans sa ligne, ce qui verrouille bien le gap. `.serieDetail` part en Safari, conformément à la décision 11 du lot 1. Factures, bulletins et avances restent web (D4).
- **Vecteurs push.** J'ai recalculé les familles depuis `push-routing.json` : 890 chemins non nuls, mêmes 15 familles et mêmes décomptes, avec 448 destinations natives et 442 renvois web. Le test n'est plus tautologique : la famille se lit sur le texte du chemin, indépendamment du routeur.
- **Masquage (PRINCIPES §7).** Tout segment hors vocabulaire est masqué. La query et le fragment ne sont signalés que par leur présence. Les identifiants de rappel passent par la description déjà masquée d'`AuthCallbackCredentials`. Les tests couvrent les jetons de chemin (`/etab/invitation`, `/contrat`, missions, série) et de query/fragment, sous trois formes : `describing`, `reflecting` et l'interpolation.
- **Comportement à l'exécution.** `AccueilPresentation.renvoiWeb` rend les mêmes valeurs qu'avant pour `/soignant/presences` et `/soignant/notifications`. Sans ce passage par `DestinationLien`, le bouton de notifications de l'Accueil aurait disparu dès T3a. Aucun autre consommateur de `JoleneRoute` n'existe dans l'app ni dans JoleneSupabase, et l'app n'est pas modifiée.
- **Points de fusion avec le lot 1.** Ils sont exacts :
  - `lot1/t9` `EcransNatifs.swift` l.42-50 : `/soignant/mon-compte` y donnerait `nil` en silence ;
  - `FeatureFlagsTests` l.147 ;
  - `lot1/t4b` `case favoris` ;
  - `lot1/t5` `MesMissionsPresentationTests` : non affecté ;
  - `lot3/l3-t4-v2` : aucun fichier commun.
- **Concurrence Swift 6.** Tous les types sont des valeurs `Sendable`, les `static let` portent des types `Sendable`, rien n'est `@MainActor` et aucune erreur n'est avalée.
- **HARD STOP n°4 et B9.** Aucun texte visible par l'utilisateur ni texte juridique. Aucune RPC, aucune logique Stripe : `RetourConnect` ne fait que lire une query, et sa doc impose de relire le statut. Je ne classe pas la tranche en B9.
- **Régressions des lots 0 et 1.** Identifiants d'accessibilité, `DemoNoNetworkTests` (imports Foundation seuls, pas d'`URLSession`), sentinelle réseau démo et XCUITest sur les 3 formats : rien n'est touché. Aucun XCUITest n'est ajouté, donc aucune fragilité iPad n'est introduite.
- **Secrets.** Seulement des littéraux de test (`SECRET1`…`SECRET10`, `ABCD-12`, `XY12`).

#### Constats mineurs

1. **Numéros de ligne de PARITE décalés d'une ligne** : `DECISIONS_LOT3.md:193`, `:196` et `DestinationLienTests.swift:73`. Le détail de série est à la l.49 (et non l.48), `/soignant/score` à la l.63 (et non l.62). Citer la route plutôt que le numéro.
2. **Commentaires qui renvoient à la route brute** : `PushRouting.swift:5` et `LinkRouter.swift:43-44` (et `AccueilScreen.swift:15`, hors diff) orientent encore vers `LinkRouter.resolve(link:)`, contre la règle de `JoleneRoute.swift:10-11`. Pointer vers `DestinationLien(link:)?.destination`. En T3b, l'API du coordinateur et des taps ne doit accepter qu'une `DestinationLien`.
3. **En-tête de `DestinationLien.swift:9`** : il promet « la page web au lieu d'un écran vide », mais les onglets provisoires Mes missions et Revenus (l.78-83) comptent comme livrés. Reformuler l'en-tête.
4. **Masquage limité à `description`** : `dump()` et `Mirror` exposent encore `canonique`, les identifiants et la query d'inscription (`LienMasque.swift:48`, `:81` ; `DestinationLien.swift:28`). Ajouter `CustomReflectable` avec un test, ou au moins étendre la règle écrite.
5. **`LienMasque.swift:32`** : `url.path` décode `%2F`, ce qui coupe un segment dynamique en plusieurs. Préférer `url.path(percentEncoded: true)`.
6. **`DECISIONS_LOT3.md:178`** : l'IBAN n'est pas une sous-ligne de `/soignant/mes-gains`. Le web le monte dans `MonCompteSoignant.tsx` l.164. Corriger la justification de T14b ; la conclusion « sans objet » ne change pas.
7. **Suivi de T3b** : il ne figure que dans `DECISIONS_LOT3.md`. Ajouter une ligne dans `PORTE_LOT3.md` (ou dans la clôture T17), et faire consigner par l'intégrateur « L3-T3a seulement » dans `REVUES_LOT3.md`.

#### Notes pour T3b (pas des défauts de T3a)

- Le libellé DEBUG `deeplink-route` attendu par T5 ne doit pas reprendre `description` : celle-ci masque les identifiants, et T5 ne pourrait plus vérifier vers quelle mission un tap mène. Prévoir un format propre au DEBUG.
- Depuis le masquage, les messages d'échec d'`XCTAssertEqual` montrent deux `.safari` différents sous le même gabarit. Les tests contournent le problème en passant le lien en message ; garder cette habitude.

#### Conditions avant merge

- CI verte : `swift test` des deux packages en `strict-concurrency=complete` sans avertissement, et exporteurs sans diff.
- L'intégration sur `feat/ios-lot3` porte le nom « L3-T3a » ; T3 reste ouverte jusqu'à T3b et sa propre revue B8.
- Les tranches T5, T7 et T14a restent bloquées par L1-T10, qu'il faudra fusionner selon les points consignés dans `DECISIONS_LOT3.md`.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot3/l3-t3-v2` (`84ece4a4`) → `4ed3f5a0`, sans conflit, sous le titre « Merge branch
  'lot3/l3-t3-v2' into feat/ios-lot3 (L3-T3a seulement) ». **Ce qui est intégré est la livraison partielle L3-T3a**
  (`DestinationLien`, `LienMasque`, table de routage du lot 3, vecteurs push par famille) ; **T3 n'est pas close** :
  T3b (coordinateur de liens de L1-T10, `onOpenURL`/`onContinueUserActivity`, XCUITest `DemoLiensLot3Tests` sur
  iphone, ipad-portrait et ipad-landscape) reste à livrer, avec sa propre revue fraîche B8 (condition 2 et mineur 7
  de la revue, part de l'intégrateur). Les tranches T5, T7 et T14a restent bloquées par L1-T10.
- Les sept mineurs restent ouverts pour l'auteur (ou pour T3b) ; la ligne de suivi de T3b dans `PORTE_LOT3.md` (ou
  dans la clôture T17), demandée par le mineur 7, n'est pas ajoutée par l'intégration.
- Vérifications : exécutées sur la pointe qui contient T3a et T4 (section L3-T4 ci-dessous, `c57d0a0d`).

## L3-T3b

### Consignes de l'auteur pour l'intégration

Branche `lot3/l3-t3b-v2` (base `origin/feat/ios-lot3` `14fe31fa`) ; écarts, choix et consignes aux tranches suivantes
détaillés dans `DECISIONS_LOT3.md`, section « T3b — coordinateur des liens et points d'entrée ». À faire relire par une
revue fraîche B8 : T3 n'est close qu'avec elle et la CI trois formats.

- **Fichiers propres** : `JoleneCore/Links/DeepLinkIntent.swift` (+ `DeepLinkIntentTests`), `JoleneRoute.swift`,
  `LinkRouter.swift` (onglet `?tab=confidentialite` du profil → hub ; commentaires vers `DestinationLien`, mineur 2 de
  la revue de T3a), `Jolene/Composition/DeepLinkCoordinator.swift`, `PresentateurRenvoiWeb.swift` (L1-T10),
  `JoleneUITests/DemoLiensLot3Tests.swift`.
- **Fichiers partagés, retouches localisées** : `DestinationLien.swift` (lignes reset et confirmation à `false`,
  en-tête), `AppContainer.swift` (`liens`, `-JOLENE_OPEN_URL`), `JoleneApp.swift` (une ligne : `PointDEntreeLiens`),
  `MainTabView.swift` (consommation des taps reprise par le coordinateur, `push-tap-cible` retiré : au conflit avec T12,
  garder les deux côtés, T12 ne remplace que le contenu de l'onglet Revenus), commentaires de `PushTapIntent.swift`,
  `CentreNotifications.swift`, `NotificationCenterDelegate.swift`, `AccueilScreen.swift`, `NotificationsScreen.swift`.
- **Tests d'autres tranches changés, et pourquoi** : `DestinationLienTests` et `CentreNotificationsTests` (reset et
  confirmation en renvoi web, exclusion nommée réduite à `connexion`, `?tab=confidentialite` → hub) ; XCUITest migrés
  (règle 8) : `DemoPushTests`, `DemoNotificationsTests`, `DemoProfilTests`, `DemoAccueilTests`, `DemoPreferencesTests`
  (commentaire). Aucun test sauté, désactivé ni affaibli : chaque assertion d'absence « sans présentateur » devient la
  présence du bouton et la présentation du renvoi, URL vérifiée sur le double démo.
- **Projet** : `project.pbxproj` régénéré par `xcodegen generate` (deux fichiers ajoutés, diff limité à eux ; groupe
  vide `Jolene/Resources` recréé localement le temps de la génération).
- **Condition de merge** : XCUITest compilés, jamais lancés (consigne) — CI trois formats verte relue dans le `xcresult`
  (`DemoLiensLot3Tests` 5 tests, `DemoPushTests`, `DemoNotificationsTests`, `DemoProfilTests`, `DemoAccueilTests` ;
  0 échec, `skipped = 0`). Pas de B9 (aucune RPC, aucun texte juridique) ; le refus du reset `?code=` applique la
  décision 7 du lot 1.

### Consignes de l'auteur pour l'intégration (corrections de la revue fraîche B8, 08/11/2026)

Revue fraîche : aucun bloquant, un majeur (M1), huit mineurs (m1 à m8). Tous corrigés sur `lot3/l3-t3b-v2` ; choix et
écarts dans `DECISIONS_LOT3.md`, section T3b, « corrections de la revue fraîche B8 ». Tests d'abord (niveau 1 puis
XCUITest), puis code.

- **M1** : port `FinIdentiteWebPort` (`JoleneCore/Session/FinIdentiteWeb.swift`) injecté dans `SessionStore`
  (`init(controller:push:finIdentiteWeb:)`, défaut nil) et implémenté par `DeepLinkCoordinator` (feuille fermée,
  `SFSafariViewController.DataStore.default.clearWebsiteData` hors démo, renvoi différé pendant l'effacement).
  `SessionStore.suivrePush` devient `suivreIdentite` (même déclencheur `didSet`, push inchangé) : **au merge de
  L1-T9**, garder ce nom dans la consigne « garder le `didSet` de T4 » (section L3-T4 ci-dessous). Nouveaux tests :
  `SessionStoreFinIdentiteWebTests` (13).
- **m1, m7** : `JoleneCore/Links/PresentationsRacine.swift` (+ `PresentationsRacineTests`, 10) ; le coordinateur ne
  pose l'anti-boucle et `deeplink-route` qu'à la présentation effective ; alerte numérotée, hôte recréé par `.id`.
  DEBUG démo : `-JOLENE_OPEN_URL_SUIVANT` et bouton `renvoi-web-lien-suivant` du double (aucun texte : libellé = URL).
- **m2** : `CibleNotification.init` (`.aucune` pour `?code=`). **m3** : `LinkRouter` (`?tab=confidentialite` →
  `.safari`), garde liée au port `exportRGPD` (T11 l'inverse). **m4** : `DemoDashboardGateway(missionsOubliees:)`,
  surcharge DEBUG `JOLENE_FORCE_OUBLI_POINTAGE` (`AppContainer`). **m5** : `cheminExplorer` (`MainTabView`). **m6** :
  docstrings. **m8** : `requireAbsence` (`UITestSupport.swift`), nouveaux XCUITest.
- **XCUITest ajoutés** (compilés, jamais lancés) : `DemoLiensLot3Tests.testLienDetailDeMissionOuvreLeDetailNatif`,
  `.testLienDeReinitialisationPkceRefuseParUneAlerte`, `.testRenvoiAffichePuisLienDeReinitialisationAlerteApresLaFermeture`
  (8 tests au total dans la classe) ; `DemoAccueilTests.testOubliDePointageOuvreLesPresencesSurLeWeb`. Condition de
  merge inchangée : CI trois formats verte, `xcresult` relu (`DemoLiensLot3Tests` 8 tests, `DemoAccueilTests` 3 tests,
  0 échec, `skipped = 0`).
- **Projet** : aucun fichier ajouté ni retiré dans l'app ou les XCUITest (nouveaux fichiers dans le paquet JoleneCore
  seulement) : `project.pbxproj` inchangé, `xcodegen generate` sans objet.

## L3-T4

### Consignes de l'auteur pour l'intégration (corrections de la revue B8)

Consignées par l'auteur de la tranche (`lot3/l3-t4-v2`), à la demande de la revue fraîche du 08/11/2026, puis
complétées après la deuxième revue fraîche du même jour (majeur : fin de session confirmée par le contrôleur ;
mineurs : verrou biométrique de L1-T9, délais du test de parallélisme, réentrance, écart l.346, test de la
déconnexion retenue, `RootView` parmi les écarts, preuve niveau 2) ; les rapports de revue eux-mêmes restent à
reproduire ici par l'intégrateur.

- **D3 — audit `DECONNEXION` et désactivation du token en parallèle, au merge de L1-T9.** L1-T9 (`origin/lot1/t9`)
  n'est ni sur `main` ni sur `feat/ios-lot3` : T4 n'a ni `async let` ni test d'ordre (écart consigné sous D3 dans
  `DECISIONS_LOT3.md`). Au merge de L1-T9 dans `feat/ios-lot3`, le conflit de
  `ios-native/Packages/JoleneCore/Sources/JoleneCore/Session/SessionStore.swift` **ne se résout pas en gardant les
  deux côtés** : `await auditerDeconnexion()` (borné à `resolutionTimeout`, 15 s) suivi de
  `await desactiverPushAvantDeconnexion()` (borné à 2,5 s) mettrait les deux appels en série, contre D3 (« ne jamais
  bloquer une déconnexion hors ligne »), et aucun test de T4 ne le verrait. Résolution attendue :

  ```swift
  public func signOut() async {
      guard !deconnexionEnCours else { return }
      deconnexionEnCours = true
      finsDeSessionVoulues += 1
      defer {
          finsDeSessionVoulues -= 1
          deconnexionEnCours = false
      }
      canRetryRestore = false
      // D3 : deux appels JWT indépendants, lancés ensemble ; la révocation suit dès que les deux ont rendu ou expiré.
      async let audit: Void = auditerDeconnexion()
      async let push: Void = desactiverPushAvantDeconnexion()
      _ = await (audit, push)
      state = await controller.signOut()
      canRetryRestore = await controller.canRetryRestore
      biometrie.oublierIdentite()
  }
  ```

  - `deconnexionEnCours` : une seule déclaration, celle de T4 (`@Published public private(set)`, lue par l'écran
    bloqué de `RootView`) ; la variable privée de L1-T9 disparaît, sa garde est la même.
  - `state` : garder le `didSet { suivrePush(depuis: oldValue) }` de T4 sur la déclaration de L1-T9. **La cause
    d'un `.signedOut` vient du contrôleur, jamais du texte du message ni de `canRetryRestore`** (publié après
    `state`, donc périmé dans le `didSet`) : `SessionController.Publication` porte l'état et le compteur
    `absencesConfirmees`, incrémenté **seulement** par une restauration sans session (`restoreSession()` → nil)
    et par un `.signedOut` du SDK avec une identité active. Les publications de L1-T9 se raccordent ainsi :
    - `publier()` de L1-T9 lit `await controller.publication` et passe par `appliquer(_:)` de T4, au lieu de
      `state = await controller.state` (une absence confirmée pendant `controller.start()` reste portée par le
      compteur jusqu'à cette lecture, après `preparer`) ;
    - boucle d'événements : `controller.handleAuthEventPublication(event)` ; la branche `.ready` garde
      `preparer` puis `publier()`, la branche « sinon » appelle `self.appliquer(publication)` ;
    - `refresh()` : celui de T4 (`appliquer(await controller.publication)`) ;
    - **`lockForBiometrics()`** (`origin/lot1/t9`, `SessionController` l.161-166) publie `.signedOut(nil)` avec
      `restoreRetryable = true` alors que la session Keychain reste intacte : il **n'incrémente pas**
      `absencesConfirmees`, et `SessionStore.start()` garde `state = await controller.lockForBiometrics()` (sans
      `appliquer`). Le crochet push le traite donc comme un `.signedOut` transitoire : ni
      `unregisterForRemoteNotifications()`, ni oubli du token, identité suivie conservée — parité web, le push
      reste actif pour une session verrouillée par la biométrie. Une affirmation « rien d'autre à ajouter »
      (version précédente de cette consigne) était fausse : sans cette exclusion, un Face ID annulé
      désinscrirait l'appareil pendant tout le verrouillage.
  - `observeAuthEvents` : garder la boucle de L1-T9 (`preparer`/`publier`, `biometrie.oublierIdentite()`), avec
    `handleAuthEventPublication` et `appliquer` comme ci-dessus, et y ajouter `self.evenementsAuthTraites += 1`
    en fin d'itération (preuve des tests de T4).
  - `auditerDeconnexion()` lit `state` avant toute mutation ; `epochDeLIdentiteOuverte()` de T4 fait la même lecture
    et peut la remplacer.
  - Tests à ajouter dans `SessionStorePushTests` (avec le double d'audit de L1-T9) :
    `testSignOutLanceAuditEtDesactivationEnParallele` — `audit.deconnexion()` et `desactiver` retenus chacun par une
    `Gate` : les deux appels sont observés commencés alors qu'aucun n'a rendu et `auth.signOut` est absent ;
    ouverture de la première barrière → toujours aucun `auth.signOut` ; ouverture de la seconde → `auth.signOut`
    en dernier ; `testSignOutHorsLigneBorneParLePlusLongDesDeuxDelais` — audit muet (`resolutionTimeout` 1 s)
    et désactivation muette (`delaiDesactivation` 1 s) : `signOut` dure moins de 1,8 s, soit le plus long des
    deux délais (1 s) et non leur somme (2 s) ; la marge de 0,8 s tient sur un runner CI chargé (des délais de
    0,2 s avec une borne de 0,35 s ne laissaient que 150 ms) ; `testVerrouBiometriqueApresReadyConserveLeToken` —
    espace prêt, token enregistré, reprise avec biométrie refusée → `.signedOut(nil)`, aucun `desinscrire`, token
    conservé, `finDeSessionPush` nil, puis déverrouillage → `.ready` sans désinscription ; et
    `testVerrouBiometriqueAuLancementConserveLeToken` — lancement à froid, token mémorisé, biométrie refusée →
    aucun `desinscrire`, token conservé.
- **Fin de session subie (mineurs 1 et 2 ; corrigé par la deuxième revue, majeur).** La désinscription locale ne
  suit qu'une absence de session **confirmée par `SessionController`** (compteur `absencesConfirmees` de
  `SessionController.Publication` : restauration sans session, `.signedOut` du SDK avec une identité active),
  hors `signOut`/`signOutLocally` : après une identité (`.ready` ou `.blocked`) → `surDeconnexionSubie(epoch:)` ;
  sans identité (lancement à froid, « Réessayer » qui ne trouve plus de session) → `surSessionAbsente`, qui oublie
  un token laissé par une session précédente, sans RPC. Elle part après la publication (`finDeSessionPush`) :
  l'écran de connexion n'attend pas la désinscription. Un `.signedOut` transitoire — restauration impossible hors
  ligne (`restoreFailedMessage`, « Réessayer » sans mot de passe), rôle ou profil illisible
  (`sessionCheckFailedMessage`, `profileLoadFailedMessage`), connexion refusée, plus tard le verrou biométrique —
  ne désinscrit rien et ne touche ni au token ni à l'identité suivie : le SDK détient encore la session et
  l'appareil doit continuer de recevoir les push (D2 : « déconnexion subie » seulement ; fiche
  `fn_desactiver_mon_token_push` : « le SDK n'a rien restauré »). Une même absence publiée deux fois (retour de
  `start()` et boucle d'événements) n'est traitée qu'une fois. `surDeconnexionSubie(epoch:)` ferme l'epoch perdu
  sans lire l'epoch courant du contrôleur (une identité suivante n'est jamais fermée) ; l'enregistrement d'un
  nouvel espace attend la fin de la désinscription précédente. Tests : `SessionStorePushTests` (lancement à froid
  hors ligne et profil illisible avec token mémorisé, espace bloqué revalidé hors ligne : aucun `desinscrire`,
  token conservé ; relance en ligne sans session : oubli ; `testSeulesLesAbsencesConfirmeesComptent`).
- **`.signedOut` du SDK pendant la désactivation (deuxième revue, mineur).** Le cas gardé par
  `finsDeSessionVoulues` — révocation reçue pendant la RPC de 2,5 s, identité encore active — est testé avec la RPC
  retenue par une `Gate` (`testSignedOutEmisPendantLaDesactivationNeDesinscritQuUneFois` : une seule
  désinscription, aucune `finDeSessionPush`) ; l'ancien test, qui émettait après `signOut()`, s'appelle
  `testSignedOutEmisApresUneDeconnexionVolontaireEstIgnore`.
- **Réentrance de `PushCoordinator.executer` (deuxième revue, mineur).** La génération (`actif(courante)`) est
  relue après la lecture `await controller.epoch`, sans suspension avant d'écrire `confirme` et le token
  mémorisé : une déconnexion exécutée pendant cette lecture n'est jamais suivie d'une mémorisation. Fenêtre non
  reproductible par un test déterministe (lecture d'acteur sans point d'injection) : garde vérifiée à la lecture.
- **Double tap sur « Se déconnecter » (mineur 3).** `SessionStore.signOut` ignore un second appel pendant la
  déconnexion (`deconnexionEnCours`, publié) ; l'écran bloqué (`access-blocked`, `logout-button`) montre l'attente
  et désactive le bouton (`BlockingScreen(secondaryIsLoading:)`).
- **Tests sans délai arbitraire (mineur 8).** `PushCoordinatorTests` attend `enregistrementsRejoints` au lieu de
  50 ms ; `SessionStorePushTests` attend `evenementsAuthTraites` et `finDeSessionPush` au lieu de yields et 50 ms.
- **Carte « Autorisation du téléphone » : une seule surface (T6, T11 ; mineur 4).** L'hôte prévu par le blueprint est l'écran
  de préférences de T6 (§3 T6 : `push-etat-appareil` de T4 dans `PreferencesScreen`), et le hub
  `Jolene/Screens/ProfileScreen.swift` appartient au seul T11. T4 monte la carte dans le hub **à titre provisoire**
  (section « Notifications », après « Application ») avec le modèle `EtatNotificationsAppareilModel` (JoleneCore,
  lu à l'affichage et au retour au premier plan) et la vue `Jolene/Screens/Profil/EtatNotificationsAppareilRow.swift`.
  - **T6** monte la carte dans `PreferencesScreen` avec `model.canalPush` lu des préférences (`global.canal_push`)
    et **retire la section provisoire du hub dans la même tranche**, en migrant `DemoPushTests` (identifiants
    `push-etat-appareil`, `push-etat-appareil-message`, `push-ouvrir-reglages`) vers l'écran de préférences.
  - **T11** n'ajoute pas de seconde carte : l'entrée « Notifications » du hub ouvre les préférences
    (`.parametresNotifications`). Si T11 passe avant T6, T11 garde la section provisoire telle quelle et T6 la retire.
  - Règles d'affichage (`EtatNotificationsAppareil`, testées) : autorisation jamais demandée → texte l.349 (« Le canal
    est actif dans Jolene… ») **seulement si `canal_push` est connu vrai** ; dans le hub (canal inconnu) comme avec un
    canal coupé, aucune carte. Le web affiche l.349 quel que soit le canal : écart à confirmer par T6. Autorisé et
    enregistré : l.346 (« Les notifications sont autorisées sur cet appareil. »), ou l.347 si `canal_push` est connu
    faux ; **dans le hub (canal inconnu), l.346** — le web n'affiche l.346 que si `global.canal_push` est vrai
    (sinon l.347, `PageParametresNotifications.tsx` l.345-347) : second écart du hub provisoire (texte verbatim,
    règle de choix différente), consigné par la deuxième revue B8 et levé par T6, qui passe `canalPush` lu des
    préférences ; T6 vérifie les deux écarts (l.346/l.347 et l.349) avant de retirer la section du hub. Bouton
    « Ouvrir les réglages » seulement si refusé, ou autorisé sans enregistrement confirmé ; absent quand
    l'autorisation n'a jamais été demandée (Réglages n'a pas d'entrée Notifications tant que l'app n'a rien demandé,
    l'activation relève de T5/T6) et quand tout est en ordre.
- **Libellé « Ouvrir les réglages » (mineur 5).** Sans source web (le web n'ouvre pas les réglages système) ; nommé
  au §1.1 du blueprint, déjà employé par les tests de T1b ; action non juridique. Constante
  `EtatNotificationsAppareil.ouvrirReglages`, épinglée par `EtatNotificationsAppareilTests` ; listé à relire par
  Gabrielle dans `DECISIONS_LOT3.md` (HARD STOP n°4, textes sans équivalent web).
- **Ce que `DemoPushTests` prouve (mineurs 6 et 7).** Niveau 2 : carte et bouton selon l'autorisation, retour à la
  connexion sans attente ni erreur. L'ordre « désactivation → désinscription → oubli → révocation » et l'absence de
  demande système sont prouvés au niveau 1 (`SessionStorePushTests`, `PushCoordinatorTests`,
  `EtatNotificationsAppareilModelTests`) ; en démo, l'absence de feuille SpringBoard ne garde que contre un câblage
  du centre de notifications réel. Chaque contrôle exigé est amené à l'écran par `scrollTo` borné. Ces XCUITest
  n'ont pas été exécutés localement : la CI trois formats doit les confirmer. **Condition de merge (deuxième
  revue B8)** : les `DemoPushTests` (3 tests, iPhone, iPad portrait, iPad paysage) et les nouveaux cas de
  `JoleneDesignLot3Tests` (carte d'état sans action principale, écran bloqué pendant la déconnexion) n'ont jamais
  tourné ; le merge n'est possible qu'après une CI trois formats verte **relue** (rapport `xcresult` : 0 échec,
  `skipped = 0`).
- **Journal DEBUG (mineur 9).** `PushCoordinator` journalise (`Logger`, `app.jolene`, catégorie `push`, DEBUG
  seulement) l'étape et la catégorie d'erreur (`motif(_:)` : genre de `JoleneError`, « délai dépassé », domaine et
  code APNs), jamais le token, l'identifiant ni le message.
- **Contrats (mineur 10).** Les fiches `fn_upsert_token_push` et `fn_desactiver_mon_token_push` de
  `CONTRATS_RPC_SOIGNANT.md` ne citent plus de relecture en production (règle 4 du mémo des lots 2 à 5 : lecture
  live réservée aux PR backend) ; elles renvoient au dump du 01/11/2026 (sécurité, `search_path`, GRANT).
- **Fichiers d'autres tranches touchés par T4 (écarts au §4 du blueprint ; liste complétée par la deuxième revue
  B8).** Chacun est une retouche minimale, gardée par un test, à conserver telle quelle au merge du propriétaire :
  - `ios-native/Jolene/Screens/ProfileScreen.swift` (**T11 seul**) : section provisoire « Notifications » (carte
    `push-etat-appareil`) après « Application » ; T6 la retire, T11 la garde s'il passe avant T6 (puce « Carte
    « Autorisation du téléphone » » ci-dessus).
  - `ios-native/Jolene/Screens/RootView.swift` (**T7 seul**, l.42-51 réécrites par l'aiguillage d'onboarding) :
    **une ligne**, `secondaryIsLoading: session.deconnexionEnCours` sur le `BlockingScreen` `access-blocked`
    (l.68 : « Se déconnecter » montre l'attente de la désactivation, jusqu'à 2,5 s, et refuse un second tap).
    Consigne d'intégration : au conflit avec T7, garder les deux côtés — l'argument reste sur tout
    `BlockingScreen` qui offre `logout-button`, et si `OnboardingRootView` (T7) propose « Se déconnecter », son
    bouton lit aussi `session.deconnexionEnCours` (attente visible, bouton désactivé). `SessionStore.signOut`
    ignore de toute façon un second appel (`testDoubleTapSurSeDeconnecterUneSeuleDeconnexion`) ; l'état visuel
    est épinglé par `JoleneDesignLot3Tests` (`BlockingScreen.isSecondaryEnabled`).
  - `ios-native/Packages/JoleneCore/Sources/JoleneCore/Compte/CompteModel.swift` (**L1-T8**) :
    `await session.signOutLocally()` remplace `controller.signOutLocally()` suivi de `session.refresh()`
    (désinscription push locale avant la purge ; `testSuppressionDeCompteDesinscritLocalementSansRPC`).
  - API `JoleneDesign` (**T1b**) : `PermissionCard(onPrimary:)` devient optionnel (nil : aucun bouton principal,
    `showsPrimary(onPrimary:)`) ; `BlockingScreen(secondaryIsLoading:)` (défaut `false`,
    `isSecondaryEnabled(isLoading:)`). Appels existants inchangés.
  - `ios-native/Packages/JoleneCore/Sources/JoleneCore/Session/SessionController.swift` (lot 0, modifié aussi par
    **L1-T9**) : compteur `absencesConfirmees`, `Publication`, `publication`, `startPublication()`,
    `handleAuthEventPublication(_:)` (internes au module). Au merge de L1-T9, garder les deux côtés ;
    `lockForBiometrics()` n'incrémente pas le compteur (puce D3 ci-dessus).

### Revue fraîche B8 — L3-T4

**Verdict : CLOTURABLE.** Aucun constat bloquant ni majeur, 7 constats mineurs. Le merge reste soumis à la CI trois formats : voir « Conditions de merge ».

#### Ce que j'ai relu

- Le diff complet `origin/feat/ios-lot3...origin/lot3/l3-t4-v2` : 42 fichiers, +3 232 / −47, six commits de `9ff6e265` à `3b94f927`.
- Le cadre : `LOT3_PLAN.md` v2 (§1.1, §2.3 à 2.7, corrections 11, 12, 16, §3 T4), `LOTS_2_5_DECISIONS.md`, `DECISIONS_LOT3.md` (D1 à D3), `PRINCIPES.md`, `CLAUDE.md`.
- Le dump `supabase/schema/public.sql` : l.30176-30223, l.64628-64696, et les GRANT l.82446-82448 et l.85471-85473.
- Les sources web : `pushNative.ts`, `pushDeviceToken.ts`, `AuthContext.tsx` l.140-277, `PageParametresNotifications.tsx` l.100-200 et l.320-360, `MonCompteSoignant.tsx` l.115.
- `origin/lot1/t9`, pour vérifier les consignes de merge.

Lecture seule : aucun build, aucun test, aucun appel Supabase.

#### Points vérifiés, conformes

##### Contrat RPC
- **`fn_upsert_token_push`** (`void`) passe par `appelerSansCorps` (`execute()` sans décodage, conforme à la correction 16) : 204 et 200 vide valent succès.
  - 22023 est traité par `exceptionsMetier` avant `SupabaseErrorMapping`, puis rendu en `.contract`, sans renvoi.
  - 42501 devient `.unauthorized`. Le coordinateur avale l'erreur, sans jamais déconnecter.
- **`fn_desactiver_mon_token_push`** (jsonb en 200) :
  - `{success:false}` rend `.nonDesactive` avant `leverSiErreur`, donc jamais « session expirée ».
  - `{}` et `{success:true, error}` ne sont jamais traités comme des succès.
- Les corps SQL du dump correspondent aux bornes 16-4096, aux messages et au périmètre `auth.uid()`.
- Les 11 tests `StubURLProtocol` sont pertinents.

##### PushCoordinator
- **Garde-fous** : epoch plus génération ; contrôle d'identité via `gateways(for:)` avant l'appel ; nouvelle lecture de `actif` après `await controller.epoch`.
- **Rejoindre plutôt que doubler** : un enregistrement déjà en cours est rejoint.
- **Délais** : 15 s pour obtenir le token APNs, 2,5 s pour la RPC puis 2,5 s pour la désinscription, comme le web.
- **Ordre du logout** : RPC, puis désinscription, puis oubli, puis `controller.signOut()`. C'est conforme à D2 et à la correction 11.
- **Journal DEBUG** : sans token ni message.

##### Fin de session subie
- Elle n'est déclenchée que sur une absence **confirmée** (`absencesConfirmees`).
- J'ai vérifié `SupabaseAuthGateway.restoreSession` : il ne rend `nil` que sans session, sur `sessionMissing` ou sur une réponse 4xx. Les erreurs réseau lèvent bien une erreur, donc un lancement hors ligne ne désinscrit rien.
- Les cas transitoires (restauration, rôle, profil) et la double publication sont couverts par des tests synchronisés sur des conditions observables.

##### Concurrence (Swift 5 + StrictConcurrency)
- Types `Sendable`, `PushRegistrar` en `@MainActor` avec une continuation par appel.
- L'annulation est reprise par `onCancel`, et `bounded` annule le perdant.
- `didSet` sur `@Published` est appelé dans le main actor.

##### Textes (HARD STOP n°4)
- Les 8 textes de la carte sont verbatim de l.341 à l.352, apostrophes typographiques comprises ; je les ai comparés ligne à ligne et un test les épingle.
- « Notifications » vient de `MonCompteSoignant.tsx` l.115.
- Seul « Ouvrir les réglages » n'a pas de source web ; il est consigné pour Gabrielle. Aucun texte juridique nouveau.

##### Régressions des lots 0 et 1
- Les identifiants de `ProfileScreen` sont inchangés.
- En démo par défaut (`nonDemandee`), aucune section n'apparaît, donc DemoCompteTests et les autres tests ne bougent pas.
- La démo n'utilise que des doubles : ni `UNUserNotificationCenter` ni APNs. DemoNoNetworkTests reste satisfait (ni import réseau ni `URLSession`), et la sentinelle reste à 0.
- `CompteModel` garde un comportement équivalent (une ligne).
- Les changements d'API JoleneDesign sont additifs.
- `-JOLENE_PUSH_*` est réservé à DEBUG, et le token factice au mode staging.

##### Contrats, projet, secrets
- Contrats : `rpc-contracts.json`, `check-rpc-contracts.mjs`, les fiches, le tableau de synthèse et le test node sont cohérents.
- `pbxproj` ne contient que des ajouts de fichiers. L'entitlement `aps-environment` existait déjà.
- Aucun littéral ressemblant à un secret : les tokens sont calculés.

#### Constats mineurs

1. **D3 / L1-T9, dette de merge** (`SessionStore.swift:87-101`).
   - Il n'y a ni audit ni `async let`, et le test « ordre audit → push → signOut » manque.
   - L'écart est justifié (`origin/lot1/t9` absent de `main` et de `feat/ios-lot3`) et consigné.
   - À faire : condition explicite du merge de L1-T9. Appliquer la résolution documentée dans `REVUES_LOT3.md` et ajouter les 4 tests listés.
2. **Garantie documentée mais pas imposée** (`PushCoordinator.swift:201-210`).
   - « Le nouvel enregistrement attend la désinscription précédente » n'est vrai que pour `surReady` (`SessionStore.swift:166-170`).
   - `surActive` (`JoleneApp.swift:30-31`, `EtatNotificationsAppareilModel.swift:56`) peut s'intercaler pendant `desinscrireLocalement` :
     - `desinscrire()` annule alors sa continuation (`PushRegistrar.swift:40-43`) ;
     - `oublier()` efface son token.
   - La fenêtre est quasi nulle en pratique.
   - À faire : faire attendre la fin de session en cours par `enregistrer()`, ou corriger la doc. Ajouter un test.
3. **`PermissionCard.showsPrimary` n'est pas utilisé par `body`** (`PermissionCard.swift:86` et `:137`).
   - Les assertions `JoleneDesignLot3Tests.swift:517-518` ne gardent donc pas le rendu.
   - À faire : utiliser le helper dans `body`, ou le supprimer avec son test.
4. **« Ouvrir les réglages » sur une erreur d'enregistrement** (`EtatNotificationsAppareil.swift:72-77`).
   - Le texte l.352 dit « Vérifiez votre connexion puis réessayez. » et le web propose une relance (l.356-360) ; Réglages ne corrige rien ici.
   - À trancher en T6 et à ajouter à la liste de Gabrielle.
5. **Surface provisoire dans le hub** (`ProfileScreen.swift:54-64`, fichier de T11).
   - Deux écarts de règle sont documentés : l.346 au lieu de l.347 quand le canal est inconnu ; « jamais demandée » masquée alors que le web affiche l.349.
   - Risque de « deux surfaces » : T6 doit retirer la section et migrer DemoPushTests dans la même tranche.
6. **Traçabilité du commit `4908b8d4`**.
   - Son message affirme une lecture live en production, ce qui contredit la règle 4 et la déclaration finale de l'auteur.
   - À faire : rectifier dans le message d'intégration et dans `REVUES_LOT3.md`, sans force-push.
7. **Preuve niveau 2 jamais exécutée**.
   - DemoPushTests (3 tests × 3 formats) et les nouveaux cas JoleneDesign n'ont jamais tourné.
   - Le build-for-testing complet n'a pas été relancé après `3b94f927`.

#### Conditions de merge

- CI trois formats verte, relue dans le `xcresult` : 0 échec, `skipped = 0`, `passed = total`.
- Au merge de L1-T9 dans `feat/ios-lot3` : résolution `async let` et les 4 tests de `REVUES_LOT3.md` §L3-T4. Ne jamais garder audit et désactivation en série.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-08)

- `git merge --no-ff origin/lot3/l3-t4-v2` (`3b94f927`) → `c57d0a0d`, après L3-T3a, sans conflit. Le seul fichier
  commun avec L3-T3a, `docs/mobile-swift/DECISIONS_LOT3.md`, a été fusionné automatiquement : les ajouts de T3a
  (requalification en T3a, reliquat T3b, points de fusion) et ceux de T4 (écart D3, libellé « Ouvrir les réglages »
  parmi les textes à relire par Gabrielle) sont tous conservés. Aucun conflit sémantique : les deux tranches ne
  partagent aucun fichier Swift, et aucun consommateur de `JoleneRoute` (`.profil` scindé en `.profil`/`.monCompte`
  par T3a) n'existe dans les fichiers de T4 (compilation et tests ci-dessous). `project.pbxproj` n'étant pas en
  conflit, `xcodegen generate` n'était pas requis ; lancé quand même pour contrôle, il reproduit les ajouts de T4 à
  l'identique et ne diffère que par le groupe vide `Resources` (dossier `ios-native/Jolene/Resources` vide, donc non
  versionné et absent d'un worktree neuf ; groupe déjà présent sur la base) : régénération annulée, aucun diff
  commité.
- **Rectification de traçabilité (mineur 6).** Le message du commit `4908b8d4` affirme que les définitions live de
  `fn_upsert_token_push` et `fn_desactiver_mon_token_push` ont été relues en lecture seule en production. Cette
  affirmation contredit la règle 4 des décisions des lots 2 à 5 (lecture seule en production réservée aux PR
  backend) et la déclaration finale de l'auteur ; **elle n'est pas retenue comme preuve**. La conformité du contrat
  repose sur le dump `supabase/schema/public.sql` (l.30176-30223, l.64628-64696 ; GRANT l.82446-82448 et
  l.85471-85473), relu par la revue B8 ci-dessus ; les fiches de `CONTRATS_RPC_SOIGNANT.md` renvoient au dump
  (mineur 10 des consignes de l'auteur). Rectification portée aussi par le message du merge `c57d0a0d` ; l'historique
  de la branche n'est pas réécrit (aucun force-push).
- **Vérifications exécutées sur `c57d0a0d`** (pointe contenant L3-T3a et L3-T4) :
  - `node --test tests/node/mobile-delivery-plan.node.mjs tests/node/check-rpc-contracts.node.mjs
    tests/node/check-rpc-contracts-lot3.node.mjs` : 137 tests, 0 échec, 0 ignoré.
  - Exporteurs relancés en écriture puis en contrôle : `export-golden-vectors.mjs` (4 306 vecteurs) et
    `export-demo-fixtures.mjs` (4 fichiers) sans diff ; `check-rpc-contracts.mjs --update` puis
    `check-rpc-contracts.mjs` : 41 RPC, aucune dérive, aucun diff ; `fn_upsert_token_push` et
    `fn_desactiver_mon_token_push` en `consommee` (lot 3), câblées par T4.
  - `swift build --build-tests` puis `swift test`, avec `-Xswiftc -strict-concurrency=complete`, toolchain locale
    Xcode 16.4 (16F6) : JoleneCore 449 tests XCTest, 0 échec, 0 ignoré, 0 avertissement ; JoleneSupabase 217 tests,
    0 échec, 0 ignoré, 0 avertissement (hors `.build/checkouts/` ; les messages « CoreData: error: Failed to create
    NSXPCConnection » du runner xctest sont du bruit du bac à sable, sans échec associé).
  - `xcodebuild build-for-testing -scheme Jolene` sur le simulateur existant « Jolene iPhone 16 Pro Max » (iOS 18.6),
    `-derivedDataPath` dans le worktree, `COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO` : `TEST BUILD
    SUCCEEDED`, 0 avertissement de compilation (seules les notes « Metadata extraction skipped » de
    `appintentsmetadataprocessor`). Cibles compilées : app, JoleneUITests (dont `DemoPushTests`), JoleneCoreTests,
    JoleneSupabaseTests et JoleneDesignTests (dont les nouveaux cas de `JoleneDesignLot3Tests`). C'est le
    build-for-testing complet que le mineur 7 disait non relancé après `3b94f927`.
- **Non exécuté** : aucun test sur simulateur, ni unitaire iOS ni XCUITest (disque presque plein, consigne de la
  tâche). `DemoPushTests` (3 tests × iphone, ipad-portrait, ipad-landscape) et les nouveaux cas de
  `JoleneDesignLot3Tests` n'ont donc toujours pas tourné : **condition de merge maintenue**, CI trois formats verte
  relue dans le `xcresult` (0 échec, `skipped = 0`, `passed = total`), en Xcode 26.4.1 (16.4 en local).
- Mineurs 1 à 5 ouverts : le 1 est une condition du merge de L1-T9 dans `feat/ios-lot3` (résolution `async let` et
  quatre tests, consignes de l'auteur ci-dessus ; jamais audit et désactivation en série) ; le 4 est à trancher en T6
  et à ajouter à la liste de Gabrielle ; le 5 est levé par T6 (retrait de la section provisoire du hub et migration de
  `DemoPushTests` dans la même tranche).
- Aucun correctif d'intégration n'a été nécessaire, donc pas de commit `fix(ios-native): intégration lot 3 …`. Les
  dossiers de build (`.build` des packages, `-derivedDataPath`) ont été supprimés après vérification.

## L3-T5

### Consignes de l'auteur pour l'intégration

Consignées par l'auteur de la tranche (`lot3/l3-t5-v2`) ; écarts et point de fusion détaillés dans
`DECISIONS_LOT3.md`, section « T5 livrée sans le coordinateur de liens de L1-T10 ».

- **Dépendance absente.** `DeepLinkCoordinator`, `DeepLinkIntent` et le présentateur `.safari` (L1-T10, reliquat
  T3b) n'existent sur aucune branche : T5 livre un point d'extension (`BoiteTapsPush`, `CibleNotification`,
  `MainTabView.presenter`) et ne revendique pas la présentation d'un renvoi web. Le critère « tap ouvrant l'écran
  attendu pour au moins six types » est visé au niveau 2 pour six types natifs (`DemoPushTests`), le litige
  (renvoi web) par la route présentée seulement.
- **Fichiers d'autres tranches touchés (retouches minimales, gardées par un test)** :
  - `Jolene/Screens/MainTabView.swift` (T5 surcouche puis T12 onglet Revenus) : init explicite (même signature),
    pile de l'Accueil avec chemin (`cheminAccueil`), destination `CentreNotificationsRoute`, surcouches du
    pré-prompt et de son issue, consommation des taps. Au conflit avec T12 : garder les deux côtés (T12 ne remplace
    que le contenu de l'onglet Revenus).
  - `Jolene/Screens/Accueil/AccueilScreen.swift` (L1-T3) : « Voir » natif (point de fusion de T3a) ;
    `JoleneUITests/DemoAccueilTests.swift` migré.
  - `Jolene/Composition/PushAppDelegate.swift`, `AppContainer.swift` (T4) : délégué posé au lancement, boîte des
    taps, contexte du pré-prompt (ajouts localisés).
  - `JoleneUITests/StagingConnexionTests.swift` (lot 0) : `-JOLENE_SESSION_COUNT 1` au lancement STAGING.
  - `Jolene/Composition/PresentateurRenvoiWeb.swift` (L1-T10) : commentaire seulement.
  - Corrections de la revue fraîche : `JoleneCore/Accueil/AccueilModel.swift` (L1-T3, ajout additif
    `loadIfStale(peremption:)`), `AccueilPresentation.swift` (commentaires), `Links/DestinationLien.swift` (T3a,
    commentaire seulement).
- **Ligne de DestinationLien** : `.notifications` à `true` ; les tranches T6, T7, T8, T9, T13, T14a qui passent leur
  ligne ajoutent aussi leur cible dans `CibleNotification` et `MainTabView.presenter`. Depuis la correction de la
  revue fraîche (M1, ci-dessous), c'est verrouillé : la garde `CentreNotificationsTests` rougit sinon, et l'écran
  retombe sur son renvoi web (jamais un tap sans effet). À l'intégration de T6 et T9 avec T5, la garde est rouge
  tant que leurs cibles ne sont pas ajoutées (voulu).
- **Vérifications de l'auteur** : voir la sortie de la tranche (commandes et résultats) ; les XCUITest n'ont pas été
  lancés (consigne de la tâche) : CI trois formats à relire dans le `xcresult` (0 échec, `skipped = 0`).

### Vérification de compilation et des tests unitaires (08/11/2026, pointe `4f56f2eb`)

L'auteur n'avait pu lancer aucun build (disque plein à la vague 2). Vérification refaite sur la pointe de
`lot3/l3-t5-v2`, toolchain locale Xcode 16.4 (16F6) ; **aucun correctif de code n'a été nécessaire**.

- `swift build --build-tests -Xswiftc -strict-concurrency=complete` puis `swift test -Xswiftc
  -strict-concurrency=complete` :
  - JoleneCore : 499 tests XCTest, 0 échec, 0 ignoré, 0 avertissement ; dont les suites de T5 `PushTapIntentTests`
    (13), `PushPolicyTests` (16), `CentreNotificationsTests` (13), `DistanceRelativeTests` (3),
    `DemoNotificationsGatewayTests` (5), et les suites retouchées `DestinationLienTests` (12),
    `AccueilAssemblageTests` (20), `DemoWorldTests` (12).
  - JoleneSupabase : 227 tests XCTest, 0 échec, 0 ignoré, 0 avertissement (hors `.build/checkouts/`), dont
    `SupabaseNotificationsGatewayTests` (10) ; « CoreData: error: Failed to create NSXPCConnection » = bruit du bac à
    sable du runner xctest, sans échec associé.
- `xcodegen generate` : seul écart, le groupe vide `Jolene/Resources` (présent sur la base, dossier vide non suivi
  par git) ; le `project.pbxproj` versionné est gardé tel quel (il référence déjà les fichiers de T5).
- `xcodebuild build-for-testing -scheme Jolene -configuration Debug -sdk iphonesimulator -destination
  'generic/platform=iOS Simulator'`, `-derivedDataPath` dans le worktree, `CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO` (comme la CI : signé en local, le bundle de ressources `JoleneCore_JoleneCore.bundle`
  est refusé par `codesign`, « bundle format unrecognized », sans rapport avec T5) : `TEST BUILD SUCCEEDED`, 0
  avertissement de compilation (seules les notes « Metadata extraction skipped » de `appintentsmetadataprocessor`).
  Cibles compilées : app (dont `NotificationCenterDelegate`, `NotificationsScreen`, `PrePromptPushScreen`,
  `StockageAppareil`, `MainTabView`), JoleneUITests (dont `DemoPushTests`, `DemoNotificationsTests`,
  `DemoAccueilTests`, `StagingConnexionTests`), JoleneCoreTests, JoleneSupabaseTests, JoleneDesignTests.
- Exporteurs en contrôle, sans diff : `export-demo-fixtures.mjs --check` (5 fichiers, dont
  `demo-notifications.json`), `export-golden-vectors.mjs --check` (4 306 vecteurs), `check-rpc-contracts.mjs`
  (41 RPC, aucune dérive) ; `node --test tests/node/check-rpc-contracts.node.mjs
  tests/node/check-rpc-contracts-lot3.node.mjs` : 60 tests, 0 échec, 0 ignoré.
- Textes : les douze constantes `// source:` de `CentreNotificationsTextes` (9) et `PrePromptPush` (3) relues contre
  `PageNotifications.tsx` (l.93, 101, 124, 140, 142, 146, 165), `PanneauNotifications.tsx` (l.160) et
  `DemandePermissionPush.tsx` (l.106, 107, 119) : identiques au caractère près.
- **Non exécuté** : aucun test sur simulateur (consigne de la tâche). Les XCUITest de T5 (`DemoPushTests` +9,
  `DemoNotificationsTests`, `DemoAccueilTests` migré) sont compilés mais n'ont jamais tourné : **condition de merge
  maintenue**, CI trois formats verte relue dans le `xcresult` (0 échec, `skipped = 0`, `passed = total`).

### Corrections de la revue fraîche (08/11/2026)

Revue fraîche : aucun bloquant, un majeur (M1), douze mineurs (m1-m12). Tests d'abord (commit `test(ios-native):
L3-T5 — garde…`), puis code et documentation. Tous les mineurs sont corrigés, sauf m12, consigné dans
`DECISIONS_LOT3.md`.

- **M1** : nouvelle garde `CentreNotificationsTests.testToutEcranNatifLivreAUneCibleNativePresentable`. Elle prend un
  lien par genre de route (switch exhaustif sans `default`) et toute la famille push golden, puis exige pour chaque
  route où `ecranNatifLivre == true` une cible native présentable (ni `.aucune` ni `.web`), hors exclusion nommée
  `connexion`, `resetPassword`, `confirmerInscription`. Vérifiée rouge en simulant la ligne de T9 passée à `true`
  sans cible : 7 échecs `/soignant/profil`, puis ligne remise.
  - La cible Revenus porte sa section (`.revenus(section:)`) ; seule `.apercu` est présentable avant T13.
  - Repli d'exécution : un écran livré sans cible retombe sur `.web(.safari(canonique))`, jamais sur `.aucune`.
- **m1** : `AccueilModel.loadIfStale(peremption:)` (jeton avancé à chaque lecture relue dans le centre,
  `CentreNotificationsModel.lectures`) ; `AccueilScreen` utilise `.task(id: peremption)`. Prouvé au niveau 1 : le
  compteur démo est figé par `demo-dashboard.json`.
- **m2** : un marquage en échec ou en délai dépassé relit la liste, silencieusement et en gardant le message.
- **m3** : `rafraichir()` ajoute l'encart `notifications-refresh-error`, au texte web `erreurChargement`.
- **m4** : la tâche d'ouverture est annulée à la disparition du centre. Le modèle ne rend aucune cible et n'affiche
  ni message ni relecture après une annulation.
- **m5** : `estPresentable(…, depuisCentre:)` : le centre n'est pas présentable depuis le centre. `.accueil` vide
  `cheminAccueil`. `presenter` ne présente qu'une cible présentable.
- **m6** : `DemoPushTests.testTapContratASignerVersLeWebDuContrat`.
- **m7** : chaque ligne déjà lue est amenée à l'écran et exigée rendue avant l'assertion « pas un bouton ».
  L'absence du pré-prompt n'est affirmée qu'après le délai de 5 s, plus une marge (attente inversée bornée).
- **m8** : `push-tap-cible` n'est exposé qu'en DEBUG et en démo (`container.isDemo`).
- **m9** : `OngletEspace` (JoleneCore) ; `MainTabView.Tab` en est un alias. La correspondance depuis `EcranNatif` est
  supprimée.
- **m10** :
  - la démo trie en NULLS FIRST (`plusRecenteDAbord`, test dédié) ;
  - `notification-voir-<id>` est retiré de la doc et du code, car il n'était pas exposé ;
  - la carte du pré-prompt n'a plus d'`isLoading`, car elle n'était jamais visible ;
  - les commentaires d'`AccueilPresentation` sont mis à jour.
- **m11** : l'indication est gardée, en attente de Gabrielle. Elle est désormais la constante
  `CentreNotificationsTextes.indicationOuvrirCentre`, épinglée par un test.
- **m12** : consigné (parité web, RLS ; écarter ce tap supposerait de distinguer la déconnexion volontaire dans
  `SessionStore`, fichier de T4).
- **Tests ajustés, et pourquoi** :
  - `testEchecDuMarquageNOuvreRien` : le script fournit les relectures de réconciliation. Sinon le port rendrait une
    liste vide et la ligne disparaîtrait : c'est le nouveau comportement voulu par m2, pas un affaiblissement ;
  - `testVoirEtLigneActionnable` affirmait « Voir » sur une ligne vers le centre, qui n'ouvrait rien (m5) ;
  - les cas `.onglet(…)` deviennent les cibles explicites (m9).
- **Vérification** (Xcode 16.4, Swift 6.1.2) :
  - JoleneCore : 510 tests, 0 échec, 0 avertissement (build propre `--build-tests -strict-concurrency=complete`) ;
  - JoleneSupabase : 227 tests, 0 échec, 0 avertissement hors `checkouts/` ;
  - `xcodegen generate` : seul écart, le groupe vide `Jolene/Resources`, non retenu ;
  - `xcodebuild build-for-testing` : `TEST BUILD SUCCEEDED`, 0 avertissement de nos sources ;
  - exporteurs `--check` sans diff ; `node --test` des contrats : 60 tests, 0 échec.
- **Non exécuté** : XCUITest (compilés seulement). La condition de merge sur la CI trois formats est maintenue.

### Revue fraîche B8 — L3-T5 (vague 2 bis, n°2)

**Verdict : CLÔTURABLE.** Aucun bloquant, aucun majeur, 9 mineurs. La condition de merge ne change pas : CI verte sur les trois formats (iphone, ipad-portrait, ipad-landscape), relue dans le xcresult avec 0 échec et `skipped = 0`. Les XCUITest de T5 n'ont encore jamais tourné.

#### Ce qui a été relu
J'ai relu en entier `git diff origin/feat/ios-lot3...origin/lot3/l3-t5-v2` à la pointe `94df9e05` : 42 fichiers, 4 326 lignes de diff. La base `847e31c6` est à jour, c'est le merge-base. En lecture seule, sans build, sans test et sans appel Supabase. J'ai aussi relu :
- le blueprint v2, section T5 et §2.5-2.7 ;
- LOTS_2_5_DECISIONS, PRINCIPES et DECISIONS_LOT3 ;
- les sources web : `PageNotifications.tsx`, `DemandePermissionPush.tsx`, `pushNative.ts`, `session-count.ts`, `PanneauNotifications.tsx` ;
- dans `supabase/schema/public.sql` : la table `notifications`, les politiques `pol_notif_*` et les déclencheurs `fn_protect_notification_update` et `dec_proteger_contenu_notification` ;
- `PushCoordinator` (T4), `bounded`, `DateHeureParis` et `DestinationLien`.

#### Corrections de la revue n°1, vérifiées
- **M1 corrigé.** La garde `testToutEcranNatifLivreAUneCibleNativePresentable` est solide. Elle prend un lien par genre de route, recense les genres par un switch exhaustif et vérifie que tous sont couverts. Elle parcourt aussi toute la famille push des vecteurs golden, avec une exclusion nommée et fermée. Les `switch` de `CibleNotification` et de `presenter` n'ont pas de `default` : une nouvelle cible ne compile pas sans sa présentation. Les repères relus de m1 à m10 tiennent. m12 est consigné.
- **Tests modifiés.** Les deux tests réécrits (`testEchecDuMarquageNOuvreRien`, `testVoirEtLigneActionnable`) sont justifiés et n'ont pas été affaiblis : les nouvelles assertions comptent les relectures de m2 et l'absence de bouton sans effet.

#### Points de contrôle passés sans constat
- **Correction des données.** Le décodage tolère `lue` à null ; `titre` et `corps`, NOT NULL en base, sont stricts. Toute erreur PostgREST passe par `SupabaseErrorMapping` avec un texte web en repli. Le filtre `destinataire_id` est explicite : `pol_notif_select` laisse les admins tout lire, il ne suffirait pas. Le PATCH ne touche que `lue` et `lue_le`, puis la ligne est **relue** ; une mise à jour sans effet ou une ligne invisible n'est jamais un succès. Pas de forme `{error}` en HTTP 200 : aucune RPC.
- **Concurrence Swift 6.** Chaque réponse est contrôlée sur l'epoch et la génération, et l'annulation n'est jamais traitée comme une erreur. Le double envoi est empêché par `ouvertureEnCours`, `tacheOuverture` et le bouton désactivé. Le délégué est `nonisolated` et ne remet au main actor que des valeurs `Sendable`. `limite` est `nonisolated`.
- **Pré-prompt.** Parité avec le web : marque lue avant tout, compteur à froid, marque `accepted` ou `denied` posée sans affichage, délai de 5 s et marque relue avant d'afficher. Après « Activer », un enregistrement confirmé par `PushCoordinator` est exigé ; sans lui, c'est un échec et la marque n'est pas posée.
- **Mode démo.** Le compteur est en mémoire vive, si bien que les suites démo et `DemoNoNetworkTests` n'ont pas de pré-prompt. La sentinelle « 0 requête » est affirmée. STAGING est lancé avec `-JOLENE_SESSION_COUNT 1`. `push-tap-cible` n'existe qu'en DEBUG et en démo.
- **Textes (HARD STOP n°4).** Les 12 constantes `// source:` sont identiques au web au caractère près, sans texte juridique nouveau. Le seul texte sans source web est une indication VoiceOver non juridique, en attente de Gabrielle.
- **Sécurité.** Pas de littéral qui ressemble à un secret, pas de journalisation. Les descriptions masquent les identifiants et les liens. Les dates relatives portées de date-fns sont exactes, y compris le calcul du décalage horaire.
- **Périmètre.** Les retouches hors tranche sont minimes et additives : AccueilModel, StagingConnexionTests et des commentaires. Rien n'a changé sous `ios/`, `android/` ou `supabase/`.

#### Mineurs
Le détail est dans le champ `mineurs`.
1. Un tap à chaud vers Explorer ou Profil ne revient pas à la racine de l'onglet : les piles n'ont pas de chemin.
2. Un tap vers le centre déjà affiché ne relit pas la liste ; le web traite ce cas avec `OUVERTURE_NOTIFICATION`.
3. Le repli des sections de Revenus contredit la doc : à l'exécution, le tap n'ouvre rien au lieu de retomber sur le web.
4. Une ouverture annulée par un changement d'onglet laisse une ligne périmée.
5. Le message d'échec d'action est inséré en tête du défilement et peut rester hors écran.
6. Le test du toast du pré-prompt est fragile face à son effacement automatique au bout de 6 s.
7. `push-tap-cible` affirme « présenté » alors que la route n'est que résolue, sans verrou pour L1-T10.
8. Le verrou n°2 du lot 1 (LOT1_PLAN l.306 et l.322) est rendu caduc par le « Voir » natif, sans que ce point de fusion soit consigné.
9. L'indication vocale attend la relecture de Gabrielle.

#### Branchement de T3b
Le coordinateur absent n'est pas compté comme défaut. Trois points rendront son branchement plus coûteux, et il vaut mieux les traiter avant ou avec L1-T10 :
- `presenter` est privé et lié aux `@State` de `MainTabView` : il faudra un modèle de navigation partagé.
- Les piles Explorer, Mes missions, Revenus et Profil n'ont pas de chemin (m1).
- Le libellé `push-tap-cible` ne fera pas rougir les tests au passage à la vraie présentation (m7).

La règle d'epoch de `BoiteTapsPush` (un tap reçu sans espace ouvert est rejoué par le premier espace prêt) est compatible avec « intention mémorisée avant `.ready` » du lot 1.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-08, vague 2 bis)

- Base : `origin/feat/ios-lot3` (`847e31c6`), puis `git merge --no-ff origin/main` (`404fc012` : PR B9 #1114, #1117,
  #1118) → `0c17a21b`, sans conflit (aucun fichier sous `ios-native/`).
- `git merge --no-ff origin/lot3/l3-t5-v2` (`94df9e05`) → `b0400108`, sans conflit textuel : `DECISIONS_LOT3.md`,
  `REVUES_LOT3.md` et `PARITE_SOIGNANT.md` fusionnés automatiquement, ajouts conservés.
- La garde de T5 (`CentreNotificationsTests.testToutEcranNatifLivreAUneCibleNativePresentable`) a joué son rôle à
  l'arrivée de T6 et T9 : leurs cibles ont été ajoutées par l'intégrateur (sections L3-T6 et L3-T9 ci-dessous).
- Mineur 1 de la revue n°2 **en partie levé** par l'intégration : la pile de l'onglet Profil a désormais un chemin
  (`cheminProfil`) et `.monCompte` la ramène à sa racine ; Explorer, Mes missions et Revenus restent sans chemin
  (point de branchement de T3b). Mineurs 2 à 9 ouverts.
- Vérifications : sur la pointe finale, voir la section L3-T9.

## L3-T6

### Revue fraîche B8 — L3-T6 (vague 2 bis, n°1)

**Périmètre relu.** `git diff origin/feat/ios-lot3...origin/lot3/l3-t6-v2`, soit 33 fichiers (+2684/−215), lu en entier, pointe `e83a9b74`. J'ai confronté le code à plusieurs sources :
- la page web `src/pages/PageParametresNotifications.tsx` (l.1-460) et `MonCompteSoignant.tsx` (l.113-115) ;
- le dump `supabase/schema/public.sql` : les deux RPC l.44100 et l.45986, `preferences_notifications_par_evenement` (`actif NOT NULL`), et les GRANT `soignants` l.85722 et l.85758 ;
- `RPCResponse` et `RPCResponse+ExceptionsMetier`, `bounded`, `ToggleRow`, `PermissionCard`, `InlineNotice`, `EmptyState` ;
- `MainTabView`, `AccueilModel`, `UITestSupport` ;
- les documents de cadre : LOT3_PLAN v2 §3 T6, LOTS_2_5_DECISIONS, DECISIONS_LOT3 (D1, D18, HARD STOP), REVUES_LOT3 §L3-T4 et PRINCIPES §3, §5 et §6.

Lecture seule : aucun build, aucun test, aucun MCP.

**Verdict : CLÔTURABLE.** Aucun bloquant ni majeur. Neuf constats mineurs, détaillés plus bas. **Condition de merge** : CI trois formats verte avec le xcresult relu (DemoPreferencesTests 2 tests et DemoPushTests 3 tests, 0 échec, `skipped = 0`). Ces XCUITest n'ont jamais tourné.

#### Vérifié conforme
- **Contrat serveur.**
  - `fn_obtenir…` renvoie toujours `par_evenement` (`COALESCE(…,'[]')`), donc le décodage strict ne casse pas un compte sans exception.
  - `{error:'Non authentifié'}` en HTTP 200 donne `.unauthorized`. `{success:true}` est le seul succès.
  - 22P02 (casts l.44130-44131) passe par `exceptionsMetier`, est intercepté avant `SupabaseErrorMapping` et donne `.contract`, sans détail technique.
  - Le PATCH ne porte que `sms_alertes_actives` (GRANT de colonne), filtré `eq(id, context.userId)`, et seulement si la ligne a été lue.
  - Le SELECT `soignants` est couvert par le GRANT de table.
- **Aucun succès fabriqué.**
  - « Préférences enregistrées » n'est annoncé qu'après une relecture concordante. Une alerte SMS non relue donne l'échec partiel verbatim l.237.
  - Un refus `{error}` est affiché verbatim et le brouillon est conservé.
  - Il n'y a ni renvoi automatique ni double envoi (garde `.enCours` testée).
  - Les réponses d'un epoch périmé sont ignorées : `generation` en lecture, epoch en écriture.
- **Parité web.**
  - Le catalogue `EVENTS_SOIGNANT` est relu dans le fichier web par une regex (13 entrées, dans l'ordre, avec le régime). Le filtre de régime fait une comparaison stricte.
  - Une ligne absente vaut « actif ». Un canal coupé grise la case et ignore le clic.
  - `sms_alertes_actives ?? true`. Une ligne `soignants` absente masque l'alerte et ne l'écrit pas.
  - Seuls les types du catalogue sont envoyés ; le serveur fait un upsert par clé.
- **D1.**
  - `verifier()` ne demande jamais l'autorisation : `demander()` n'est appelé que dans `activer()`, au tap.
  - « Activer sur cet appareil » apparaît dans les conditions du web l.356, et le second tap est ignoré.
  - « Ouvrir les réglages » n'est proposé que sur refus (mineur 4 de T4 tranché).
- **Une seule surface.** La carte n'est plus montée que dans `PreferencesScreen`. `sectionHub` et `proposeReglages` sont retirés, et `DemoPushTests` est migré.
- **HARD STOP n°4.** Aucun texte nouveau. Les textes sont verbatim et gardés par des tests qui relisent les fichiers web ; seuls les deux textes tutoyés passent au vouvoiement (décision 9). « Session à vérifier » reprend le lot 1. B9 non concerné (D18).
- **Lien.** La ligne `DestinationLien.ecranNatifLivre(.parametresNotifications)` passe à true, ce qui suit la consigne. Aucun consommateur vivant n'est affecté : le seul lecteur hors tests est `AccueilPresentation.renvoiWeb`, qui ne vise que `/presences` et `/notifications`, et aucune notification du dump ne pointe vers les préférences.
- **Lots 0 et 1.** `logout-button`, `profile-*` et `network-sentinel` sont inchangés et restent à la même place ; la nouvelle section se trouve après « Application ». Le monde démo n'émet aucune requête réseau. Les tests de T4 sont remplacés par des tests plus stricts, sans affaiblissement.
- **Fuites et périmètre.** Aucun secret, aucun log de données sensibles. Les fichiers hors tranche (ProfileScreen de T11, fichiers T4, DestinationLien) sont des retouches consignées.

#### Constats mineurs (à traiter avant ou avec le merge de T11/T3b)
1. **`PreferencesModel.swift:163-171`.**
   - Problème : la relecture qui suit une issue inconnue publie sans garde. Elle écrase les modifications faites pendant la relecture, peut afficher une relecture périmée sous « Préférences enregistrées » si un second envoi se termine avant elle, et garde l'échec même quand la relecture concorde.
   - Correction : un jeton d'opération ou la garde `preferences == demande`, puis la concordance sur la relecture.
2. **`PreferencesModel.swift:75-80`.**
   - Problème : `sessionExpired` n'est jamais remis à false sur un échec d'un autre type.
   - Correction : l'aligner sur `AccueilModel`.
3. **`PreferencesModelTests`.**
   - Problème : aucun test sur une réponse tardive après changement d'identité, ni en lecture ni en écriture, et aucun test de `verifierSession`.
   - Correction : ajouter ces cas.
4. **`PreferencesScreen.swift:77-79`.**
   - Problème : `canalPush` est une copie recopiée par `onChange`, en écart au principe « État dérivé ». Sur le premier rendu, l.346 peut s'afficher à tort.
   - Correction : dériver le canal au rendu.
5. **`ProfileScreen.swift:49-55`.**
   - Problème : le `NavigationLink` à destination fermée empêchera T3b de pousser l'écran par programme.
   - Correction : `NavigationLink(value:)` et `.navigationDestination(for:)`, comme `MissionRoute`.
6. **`PreferencesScreen.swift:179-185`.**
   - Problème : les cases sont vocalisées par le seul canal.
   - Correction : reprendre le patron web l.410 (« ${c} pour ${e.label} »).
7. **`DemoPushTests.swift:100-113`.**
   - Problème : l'absence de carte dans le hub n'est plus vérifiée en état « refusé ».
   - Correction : ajouter `aucuneCarteDansLeHub()`.
8. **Traçabilité de HARD STOP n°4.**
   - Problème : « Coût supporté par Jolene. Vous pouvez désactiver… » est vouvoyé, et le mineur 4 de T4 est tranché, mais aucun des deux ne figure dans la liste de Gabrielle (§6.7).
   - Correction : les y ajouter.
9. **Preuve de niveau 2 non acquise.**
   - Problème : sur iPad, le tap à `dx 0.9` tombe sur le libellé et dépend de l'`onTapGesture` de ToggleRow.
   - Correction : CI trois formats relue avant le merge.

#### Points de fusion à conserver
- Au merge de T11 : garder `profile-preferences-notifications` et ne jamais ajouter de seconde carte.
- T3b doit mapper `.parametresNotifications` : onglet Profil, puis `PreferencesScreen(session:snapshot:push:permission:)`. Il doit aussi ajouter le cas de tap vers `prefs-screen` prévu au §3 T5 du blueprint.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-08, vague 2 bis)

- `git merge --no-ff origin/lot3/l3-t6-v2` (`e83a9b74`) → `0ce5f398`, après L3-T5. Conflits résolus en gardant les
  deux côtés :
  - `DemoWorld.câblerLot3` et `SupabaseGateways.câblerLot3` : notifications (T5) et préférences (T6) câblées ;
  - `DemoWorldTests.portsEnAttenteLot3` : `notifications` et `preferences` retirés ;
  - `DestinationLienTests` : les deux écrans sortent des renvois Safari, `ecranNatifLivre` vrai pour les deux ;
  - `export-demo-fixtures.mjs` : `buildDemoNotifications` et `buildDemoPreferences` ;
  - `DemoPushTests` : tests d'autorisation de T6 (carte dans les préférences) + taps et pré-prompt de T5 ; l'absence
    du pré-prompt en 1re session (T5) est affirmée dans le test « jamais demandé » de T6, avant « Activer sur cet
    appareil » ; les deux tests du pré-prompt lisent la carte dans l'écran des préférences (« Plus tard » : l.349 et
    « Activer sur cet appareil » toujours proposés, au lieu de l'absence de carte au hub) ;
  - `project.pbxproj` régénéré par `xcodegen generate` (groupe vide `Jolene/Resources` recréé localement pour un
    diff limité aux fichiers de T6).
- **Correctif d'intégration `9a869e8d`** (garde de T5 rouge sans lui, comme prévu par `DECISIONS_LOT3.md`) :
  - `CibleNotification.preferences`, onglet Profil, présentable depuis le centre ;
  - `MainTabView` : pile du Profil en `NavigationStack(path:)`, destination `PreferencesNotificationsRoute`, cas
    `.preferences` de `presenter` ;
  - `ProfileScreen` : entrée « Réglages › Notifications » en lien par valeur (**mineur 5 levé**), même identifiant ;
  - point de fusion « cas de tap vers `prefs-screen` » **fait** : `DemoPushTests.testTapLienExpliciteOuvreLesPreferences` ;
    `DemoNotificationsTests.testLigneLueVersLesPreferencesOuvreLEcranNatif` (ligne 005 : bouton « Voir », écran natif) ;
  - test changé, et pourquoi : `PushTapIntentTests.testCiblesDesTypesPrincipaux` attendait le renvoi web des
    préférences, état d'avant T6 ; il attend désormais `.preferences`. `DemoNotificationsTests` sort la ligne 005 de la
    boucle des lignes sans action, puisqu'elle en a une, et la vérifie dans son propre test.
- Mineurs 1 à 4 et 6 à 9 ouverts. Condition de merge inchangée : CI trois formats verte, `xcresult` relu
  (`DemoPreferencesTests`, `DemoPushTests`, `DemoNotificationsTests`), `skipped = 0`.
- Vérifications : sur la pointe finale, voir la section L3-T9.

## L3-T9

### Revue fraîche B8 — L3-T9 (branche `lot3/l3-t9-v2`, 08/11/2026)

Verdict : aucun bloquant ; un majeur ; dix mineurs. Synthèse (détail et corrections ci-dessous) :

- **Majeur** — `SupabaseProfilGateway.modifier` appelait `fn_modifier_mon_profil` sans `exceptionsMetier` : 23514
  `chk_telephone_format`, 23505 `soignants_numero_rpps_key` et P0001 `dec_verifier_age_minimum` étaient réduits à
  « Votre profil n'a pas pu être enregistré. Réessayez. » (correction 12 et §2.4 du blueprint non respectés).
- **Mineurs** — (1) commentaire de revalidation d'Explorer inexact ; (2) date par défaut écrite à l'ouverture du
  sélecteur ; (3) relecture seulement après `.network` ; (4) `sessionExpiree` non lu par la vue ; (5) identifiants des
  champs en lecture seule posés sur un enfant fondu ; (6) `NavigationLink` à fermeture non poussable par T3b ;
  (7) description par réflexion de `ProfilComplet` (position GPS, téléphone) ; (8) effacement du prénom instable dans
  `DemoProfilTests` ; (9) audit attendu avant la vérification des modes ; (10) état `.nonCable` à tenir en liste de
  contrôle pour T8.

### Corrections de l'auteur (tests d'abord)

- **Majeur, corrigé.** `exceptionsMetier: ["23514", "23505", "P0001"]` (`ProfilEdition.exceptionsMetier`), refus
  restitué traité avant `estSucces`, messages par `ProfilEdition.messageExceptionMetier` : textes web
  `src/lib/erreurs.ts` l.510, l.511, l.514, message serveur verbatim pour P0001 (écart avec le web consigné dans
  `DECISIONS_LOT3.md`, T9). Définitions relues en lecture seule sur la base live (contraintes, trigger, fonction),
  identiques au dump. Tests : trois cas dans `SupabaseProfilGatewayTests` (une requête, aucune relecture, message
  attendu), rouges sans la correction, plus le cas « erreur ambiguë » ; `ProfilVerbatimTests` épingle les sources.
- **Mineur 3, corrigé** avec un type de refus certain `RefusEnregistrementProfil` (JoleneCore, levé par les deux
  mondes) : relecture après toute issue ambiguë (tout sauf refus certain, `.unauthorized`, `.contract`,
  `.cancelled`). Test rouge sans la correction (`testIssueAmbigueHorsReseauRelitAussiLeProfil`). Deux tests
  existants changés de `JoleneError(.unknown, …)` en `RefusEnregistrementProfil` (gateway et démo), parce que le
  refus est désormais typé : même message, même absence de relecture, assertion de non-relecture ajoutée.
- **Mineur 9, corrigé** : modes vérifiés avant l'audit (`testUnAuditLentNeRetardePasLaVerificationDesModes`, rouge
  sans la correction).
- **Mineur 4, corrigé** : « Session à vérifier » / « Vérifier ma session » (libellés du lot 1) au chargement et sous
  le refus d'enregistrement ; `ProfilEditionModel.verifierSession` (trois tests).
- **Mineur 5, corrigé** : identifiant sur l'élément combiné ; XCUITest `testIdentiteVerrouilleeApresLeControleRppsExposeeEnLectureSeule`
  sur la variante démo DEBUG `JOLENE_DEMO_PROFIL=identite-verrouillee`.
- **Mineur 2, corrigé** : le sélecteur affiche le défaut sans l'écrire ; XCUITest
  `testDateDeNaissanceNonRenseigneeJamaisEcriteSansChoix` (variante `sans-date-naissance`).
- **Mineur 7, corrigé** : description masquée (test `testDescriptionMasqueeSansIdentiteNiCoordonneesNiPosition`).
- **Mineur 8, corrigé** : curseur placé en fin de texte par un appui sur le bord droit, effacement répété borné
  jusqu'au champ vide.
- **Mineurs 1, 6 et 10, consignés** dans `DECISIONS_LOT3.md` (T9) : manque des onglets déjà montés (point de fusion :
  lecture de `session.state.snapshot`), point de fusion T11/T3b de la navigation programmée (`JoleneRoute` non
  `Hashable`, hub de T11), liste de contrôle T8 (retrait de `.nonCable` et de l'assertion de `DemoProfilTests`,
  `feat/ios-lot3` pas sur `main` avant T8). Commentaire du modèle reformulé (mineur 1).
- **Non exécuté** : XCUITest (compilés par `build-for-testing`, jamais lancés : consigne de la tâche). Condition de
  merge : CI trois formats verte, relue dans le `xcresult`.

### Revue fraîche B8 — L3-T9 (vague 2 bis, n°2)

**Branche** `origin/lot3/l3-t9-v2` (99a38bd5), comparée à `origin/feat/ios-lot3` (847e31c6). J'ai relu le diff en entier : 37 fichiers, +3 442 / −91. Revue en lecture seule : aucun build, aucun test, aucun appel Supabase. Les définitions SQL ont été relues dans le dump versionné de la base.

#### Verdict : **CLÔTURABLE**
Aucun bloquant, aucun majeur, 10 mineurs. Une condition de merge : la CI doit être verte sur les trois formats. Les XCUITest sont compilés mais n'ont jamais été lancés.

#### Ce qui a été vérifié et tient

##### Gateway (`SupabaseProfilGateway`)
- **Exceptions métier lues avant le mapping générique.** `exceptionsMetier` vaut `["23514", "23505", "P0001"]`. Ces exceptions sont restituées avant `SupabaseErrorMapping`, et le `sqlstate` est examiné avant `estSucces`.
- **Refus HTTP 200.** Un `{error}` en HTTP 200 donne un refus certain (`RefusEnregistrementProfil`). « Non authentifié » est traité à part : session expirée.
- **Autres erreurs.** 5xx, 504 et SQLSTATE non déclarés sont des issues ambiguës : l'écran relit le profil, sans jamais renvoyer la demande.
- **Pas de faux succès.** `{}` est traité comme une erreur de contrat. Un succès est toujours suivi d'une relecture : une requête d'écriture, puis une de lecture.
- **Corps SQL relus** (`fn_modifier_mon_profil` l.43891-44018, `fn_mon_profil_soignant_complet` l.44659-44684, triggers BEFORE UPDATE de `soignants`) :
  - le `COALESCE` est respecté ;
  - aucun texte vide n'est envoyé, sauf le prénom ou le nom (refusés par le serveur) ;
  - un RPPS vérifié n'est jamais envoyé.

##### Lecture
- Décodage en liste blanche, après la garde du web `validerProfilSoignant` rejouée par les vecteurs golden.
- Aucune propriété pour une clé sensible.
- Description masquée : ni position GPS ni identité.
- L'identifiant utilisateur est comparé en minuscules dans les deux mondes.

##### Modèle (`ProfilEditionModel`)
- Lecture bornée dans le temps. Les lectures sont numérotées : une réponse plus ancienne ne publie rien.
- Epoch d'identité vérifié après chaque attente.
- Un seul audit `DONNEES_PERSO_CONSULTATION` par ouverture, best-effort, après la vérification des modes.
- Pas de double envoi : verrou et garde.
- La revalidation silencieuse de la session garde le même epoch et ne démonte pas l'espace (`SessionController.start`, `MainTabView.id(epoch)`).
- « Vérifier ma session » reprend les libellés du lot 1.

##### HARD STOP n°4
- Type d'exercice et attestation L1222-5 ne sont pas portés : `p_type_exercice` et `p_attestation_*` ne sont jamais envoyés.
- Les textes web sont repris tels quels, à leur ligne source (`ProfilVerbatimTests`).
- Les modes d'exercice sont dérivés de la table paramétrée. L'état « non câblé » reste conservateur : le libéral n'est jamais ajouté.
- Deux textes natifs non juridiques sont listés pour relecture par Gabrielle.

##### Périmètre
- `ProfileScreen` : une seule ligne ajoutée.
- `AppContainer` : un seul bloc DEBUG ajouté.
- pbxproj : ajouts seulement.
- Aucun littéral qui ressemble à un secret.
- Identifiants d'accessibilité conformes au blueprint.
- La sentinelle réseau de la démo est vérifiée dans `DemoProfilTests`.
- Lots 0 et 1 : les identifiants ne bougent pas. `DemoCompteTests` atteint toujours la suppression grâce à ses glissements bornés.

##### Tests
- Les tests ne sont pas affaiblis : les trois tests passés au type `RefusEnregistrementProfil` gagnent une assertion de non-relecture.
- Le motif de retour arrière sur iPad est le même que dans les XCUITest déjà verts (`navigationBars.buttons.firstMatch`).

#### Mineurs (détail dans la liste structurée)
1. Une saisie faite pendant un enregistrement est effacée par le succès relu, alors que la branche ambiguë la conserve.
2. Point de fusion T3b : tous les `/soignant/profil?tab=*` vont vers l'édition native, y compris `?tab=confidentialite` (RGPD et suppression du web). À consigner et à tester.
3. Les 23505 ne suivent pas l'ordre du web : l'exemple `soignants_email_key` diverge de `erreurs.ts` l.508.
4. P0001 couvre aussi `dec_valider_type_exercice_soignant` et `dec_verifier_type_exercice_profession`, dont les messages s'afficheraient tels quels. C'est la parité avec le web, mais ce n'est ni documenté ni testé.
5. Aucun test sur un changement d'epoch pendant un enregistrement.
6. `extension ValeurJSON` déclarée dans un fichier de gateway : risque de doublon avec T8.
7. `ModificationProfil` et `FormulaireProfil` gardent une description non masquée.
8. Explorer et Accueil gardent un snapshot périmé après un enregistrement. Le manque est consigné mais pas verrouillé par un test.
9. Le commentaire de la fixture démo ne correspond pas à son contenu (`specialites`).
10. Condition de merge : CI verte sur iphone, ipad-portrait et ipad-landscape (xcresult). Textes natifs à relire par Gabrielle.

#### Notes T3b
- `ProfilEntreeSection` garde un `NavigationLink` à fermeture, et la pile de l'onglet Profil n'a pas de chemin de navigation. T3b devra rendre `JoleneRoute` `Hashable`, donner un chemin à la pile et poser une `navigationDestination` sur la `List` de `ProfileScreen`. C'est consigné dans DECISIONS_LOT3 et ne pose pas de difficulté.
- Le renvoi du type d'exercice construit lui-même son `.safari`, sans passer par `DestinationLien`. C'est correct, à condition que le présentateur de L1-T10 utilise `SFSafariViewController` et jamais `openURL`, sinon le lien universel reviendrait dans l'app.

Seul nettoyage côté Claude : mes propres extractions de revue dans le scratchpad. Rien d'autre n'a été supprimé.

### Intégration sur `feat/ios-lot3` (intégrateur, 2026-11-08, vague 2 bis)

- `git merge --no-ff origin/lot3/l3-t9-v2` (`99a38bd5`) → `cabbf29e`, après L3-T5 et L3-T6. Conflits résolus en
  gardant les deux côtés :
  - `AppContainer.demoGateways` : surcharges DEBUG `JOLENE_FORCE_PREFERENCES_ECHEC` (T6) et `JOLENE_DEMO_PROFIL` (T9)
    dans le même monde démo ;
  - `ProfileScreen` : ligne « Mon profil » de T9 puis l'entrée « Réglages › Notifications » de T6 (la carte
    provisoire de T4, encore présente sur la base de T9, n'est plus au hub) ;
  - `DemoWorldTests.portsEnAttenteLot3` (`profil` câblé en plus), `SupabaseGatewaysTests` (assertions de T5 et T9) ;
  - `DestinationLienTests` : routes natives de T5 et T9, familles push `/soignant/notifications` et
    `/soignant/profil` natives, totaux combinés **461** destinations natives et **429** renvois web
    (448 + 6 + 7 ; 442 − 13) ;
  - `export-demo-fixtures.mjs` (notifications, préférences, profil complet), `check-rpc-contracts-lot3.node.mjs`
    (RPC consommées de T6 et T9) ;
  - `DECISIONS_LOT3.md`, `PARITE_SOIGNANT.md` (ligne tableau de bord de T5, lignes profil de T9), `REVUES_LOT3.md` :
    sections des deux côtés ; `project.pbxproj` régénéré par `xcodegen generate`.
- **Correctif d'intégration `6181cfdd`** (garde de T5 rouge sans lui : 7 vecteurs push `/soignant/profil`) :
  `CibleNotification.profil` (tout `?tab=`, alias `reputation`), destination `ProfilEditionRoute` sur la pile du
  Profil, cas `.profil` de `presenter`, « Mon profil » en lien par valeur (même identifiant `profil-ouvrir` ; la note
  T3b « pile sans chemin, lien à fermeture » est levée sans rendre `JoleneRoute` `Hashable`) ;
  `DemoPushTests.testTapLienExpliciteOuvreLEditionDuProfil` (cas de tap du §3 T5 pour l'écran de T9). **Mineur 2**
  consigné (`DECISIONS_LOT3.md`, section d'intégration) et caractérisé par `CentreNotificationsTests`
  (`?tab=confidentialite` → `.profil`) ; à trancher par T3b / T11.
- **Correctif d'intégration `10f197ca`** : `ProfilVerbatimTests.testLibelleDuRenvoiDuTypeDExerciceEpingleSansSourceWeb`
  rougissait. Il justifiait « Voir sur jolene.app » par sa présence dans `AccueilScreen.swift`, que T5 retire (centre
  natif) : test juste pour sa base, faux pour la base fusionnée. Le libellé (non juridique, sans équivalent web)
  rejoint la liste des textes à relire par Gabrielle ; le test épingle sa valeur, sa présence dans cette liste et son
  absence de la page web. Aucun texte affiché ne change.
- **Reprise de `main` et correctif `e9e11948`** : `git merge --no-ff origin/main` (`01d0be09`, PR B9 #1119, hors
  `ios-native/` et hors dump) → `9f89723b`. La reprise du 1er merge apporte B3 (#1118) : la garde T0
  `check-rpc-contracts-lot3.node.mjs` (« contestation cassée », témoin du dump) rougissait, comme prévu, en demandant
  de relire la fiche. Fiche `fn_contester_paiement_soignant` réécrite depuis le dump (l.25741-25839 : huit
  `error_code`, verrou `FOR UPDATE`, 23505 restituée en `LITIGE_DEJA_OUVERT`, plus d'INSERT `CONTESTATION_PAIEMENT`) ;
  le test garde le contrat d'après B3 avec la même force. T13 (B9) reste à livrer.
- **Vérifications exécutées sur la pointe poussée** (Xcode 16.4, Swift 6.1.2 ; disque libre ≈ 30 Go) :
  - `swift build --build-tests -Xswiftc -strict-concurrency=complete` puis `swift test -Xswiftc
    -strict-concurrency=complete` : **JoleneCore 625 tests, 0 échec**, 0 avertissement ; **JoleneSupabase 258 tests,
    0 échec**, 0 avertissement hors `.build/checkouts/` (« CoreData: error: Failed to create NSXPCConnection » : bruit
    du bac à sable du runner xctest, sans échec associé). `.build` supprimé après chaque package.
  - `xcodegen generate` : aucun diff ; `xcodebuild build-for-testing -scheme Jolene -configuration Debug
    -destination 'generic/platform=iOS Simulator'`, `-derivedDataPath` dans le worktree, `CODE_SIGNING_ALLOWED=NO` :
    **TEST BUILD SUCCEEDED**, 0 erreur, 0 avertissement de nos sources (seules les notes « Metadata extraction
    skipped » d'`appintentsmetadataprocessor`) ; cibles compilées : Jolene, JoleneUITests (dont `DemoPushTests` 15,
    `DemoNotificationsTests` 2, `DemoPreferencesTests` 2, `DemoProfilTests` 5), JoleneCore(Tests),
    JoleneSupabase(Tests), JoleneDesign(Tests). DerivedData supprimé.
  - Exporteurs en écriture puis en contrôle, sans diff : `export-demo-fixtures.mjs` (7 fichiers),
    `export-golden-vectors.mjs` (4 306 vecteurs), `check-rpc-contracts.mjs --update` puis contrôle (41 RPC, aucune
    dérive) ; `node --test tests/node/check-rpc-contracts.node.mjs tests/node/check-rpc-contracts-lot3.node.mjs
    tests/node/mobile-delivery-plan.node.mjs` : **137 tests, 0 échec, 0 ignoré**.
- **Non exécuté** : aucun test sur simulateur (consigne). Les XCUITest de T5, T6 et T9, et les trois ajoutés à
  l'intégration, sont compilés mais n'ont jamais tourné : **condition de merge maintenue**, CI trois formats verte
  relue dans le `xcresult` (0 échec, `skipped = 0`, `passed = total`). Mineurs 1 et 3 à 10 ouverts.

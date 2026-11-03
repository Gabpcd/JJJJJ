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

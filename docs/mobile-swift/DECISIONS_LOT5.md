# Décisions du lot 5 — application iOS Swift native, espace établissement terrain

> Tranchées le 2 novembre 2026 sur le mandat de Gabrielle (« finis et prends les décisions seul », « je suis tous
> tes conseils ») consigné dans les décisions des lots 2 à 5 (`LOTS_2_5_DECISIONS`) : **toutes les recommandations
> fermes du §7 de `docs/mobile-swift/LOT5_PLAN.md` sont adoptées telles quelles**. Ce mémo fait foi ; ni
> `docs/PLAN_APP_NATIVE_SWIFT.md` ni le blueprint versionné ne sont réécrits. Rédigé par la tranche T0
> (`LOT5_PLAN.md` §3 T0) ; les décisions juridiques ou B9 que le blueprint renvoie à Gabrielle ne sont **pas**
> implémentées : elles sont listées en fin de document.

## Règles transverses (décisions des lots 2 à 5)

- **HARD STOP n°4.** Le natif n'affiche que des textes **verbatim** du web ou du serveur, chacun relié à sa source
  (`fichier:ligne`) et gardé par un test (`JoleneCore/Legal/TextesWeb.swift` + `tests/node/textes-juridiques-ios.node.mjs`,
  D30). Aucune reformulation, aucun texte juridique nouveau, aucun changement de délai ou de règle juridique côté
  serveur. Chaque écran portant un tel texte attend la validation d'écran de Gabrielle (§6.4).
- **B9.** T8 (présences : escrow), T13 (STAGING : secrets et données) et B5b (SECURITY DEFINER) sont préparées et
  poussées avec leurs tests, **jamais mergées** sans le go explicite de Gabrielle. T6 reste hors B9 tant que D25
  limite l'acceptation native aux missions `SALARIE`.
- **Aucune écriture** en production ni sur STAGING par les agents ; lecture seule en production uniquement pour
  relire une définition live (`pg_get_functiondef`, `list_migrations`) dans les PR backend (B5a, B5b).
- **Merges** sur `main` sériels, CI verte et revue fraîche B8 clôturable, par la file de merge de la session
  principale ; branche d'intégration `feat/ios-lot5` (depuis `origin/feat/ios-lot1`, reprise de `main` puis de
  `feat/ios-lot1` par merge, jamais de rebase ni de force-push).
- **D-FLAGS.** Une seule migration non-B9 pose les drapeaux d'écran des lots 2, 4 et 5 (`INSERT … ON CONFLICT (cle)
  DO NOTHING`, modèle B0 `20261102150000`) ; pour le lot 5 elle remplace B5a.

## Décisions du §7 (D1 à D30)

| # | Objet | Statut | Conséquence |
|---|---|---|---|
| D1 | Modèle de session | adoptée | Cas additif `SessionState.readyEtablissement(EtablissementSessionSnapshot)` ; aucun `SoignantProfile` fabriqué, `SessionSnapshot` inchangé (T2a). |
| D2 | Source du périmètre | adoptée | `fn_mes_permissions_etab(p_etablissement_id: NULL)` fait foi ; candidat différent → blocage « scope divergent » + renvoi web (T2a). |
| D3 | Fichiers gelés | adoptée | `MobileAccess.validate` inchangé, remplacé dans le contrôleur par `EspaceResolution` ; `UserRole.isNativelyServed` → `true` pour l'établissement, exception consignée dans `PRINCIPES.md` §2 par T2a. |
| D4 | QR | adoptée | QR du `code_pointage_actif` en plein écran ; `fn_generer_qr_mission` et code de secours non exposés ; critère plan l.218 réécrit — **validation de Gabrielle requise** (§6.9). |
| D5 | Preuve de décodage | adoptée | Un seul décodeur pour les lots 2 et 5 (celui des `PayloadQRTests` du lot 2, ou `CIDetector` pour les deux) + `sha256` comparé à la valeur SQL ; `verify-presence-qr.mjs` non repris (§6.9). |
| D6 | Note à la validation | adoptée | Note 1-5 obligatoire, envoyée après la validation relue, best-effort (T8). |
| D7 | Catégorie B9 de T8 | adoptée | T8 = B9 paiements/escrow : go explicite de Gabrielle avant merge (§6.1). |
| D8 | Périmètre de publication native | adoptée | Salarié, taux horaire, toutes professions sauf `MEDECIN` ; le reste en renvoi web au texte neutre — **texte et périmètre soumis à Gabrielle** (§6.4). |
| D9 | Planning | adoptée | Dérivation structurelle portée avec golden (T3) ; 48 h / 11 h / 12 h laissés au serveur, refus verbatim. |
| D10 | Candidatures, textes | adoptée | Mention CGV art. 8 verbatim + lien Safari ; étudiant AS et mission `MEDECIN` → renvoi web ; badge « hors profession » non porté ; seul `CADRE_ETUDIANT_A_CONFIRMER` renvoie au web. |
| D11 | Trous serveur | adoptée | B5b proposée (B9), non bloquante ; filtrage d'affichage par permission côté natif (§6.3). |
| D12 | Refus 42501 | adoptée | Liste blanche par RPC extraite du dump (`rpc-contracts.json`, champ `exceptions`, posé par T0) → `accesRefuse` + relecture des permissions ; 42501 hors liste inchangé. |
| D13 | Barre d'onglets | adoptée | Accueil · Missions · Présences · Messages · Compte ; « Publier » en bouton masqué sans `missions`. |
| D14 | Drapeaux | adoptée | 7 clés `ios_natif_etab_{accueil,missions,publier,presences,pointage,messages,compte}_actif`, `OPERATIONS`, fail-open, enum additive `EcranNatifEtablissement` (voir amendement 9). |
| D15 | Montants | adoptée | Aucun montant financier en natif établissement ; compteurs seulement sous `lecture_paiement` ∨ `paiement`. |
| D16 | Canal de renvoi | adoptée | Safari (`SFSafariViewController`) pour tous les renvois établissement ; reconnexion web annoncée par le texte du renvoi. |
| D17 | Suppression du compte établissement | adoptée | Lien direct `https://jolene.app/etablissement/parametres?tab=securite#suppression-compte`, visible pour tout membre. |
| D18 | Messagerie et contrats | adoptée | Réemploi strict des ports des lots 4 et 2 ; aucun port partiel ; manuscrit et CDD à préparer en renvoi web. |
| D19 | Audit | adoptée | `DONNEES_PERSO_CONSULTATION` à l'ouverture de l'Accueil ; aucun doublon d'audit serveur ; `fn_maj_activite_soignant` jamais appelée pour un établissement. |
| D20 | Mode démo | adoptée | `-JOLENE_DEMO_ESPACE`, `-JOLENE_DEMO_ROLE_ETAB`, `-JOLENE_DEMO_LEGACY`, `-JOLENE_POLL_INTERVAL` (DEBUG) ; permissions démo générées depuis le `CASE` SQL (T1). |
| D21 | Fixture STAGING | adoptée | D5 dédiée (catalogue md5 propre, nettoyage élargi) ; présence par le chemin métier réel (T13, B9, §6.2). |
| D22 | Workflow STAGING | adoptée | Jumeau `ios-swift-lot5-staging.yml`, même environnement protégé, groupe `jolene-supabase-staging-writes`. |
| D23 | Polling du code | adoptée | 5 s, écran visible et scène active seulement, backoff 30 s après 3 erreurs. |
| D24 | Durée du job UI | adoptée | Mesure à T2 ; au-delà de 25 min, deux `test-without-building` (soignant / établissement), chacun avec sa gate. |
| D25 | Périmètre d'acceptation native | adoptée | Acceptation seulement pour `type_contrat_recherche = SALARIE` et `profession_requise ≠ MEDECIN` ; sinon « Accepter sur jolene.app » ; refus natif partout — **accord de Gabrielle sur ce périmètre** (§6.10). |
| D26 | `p_creneaux_confirmes` de l'établissement | adoptée | Écho des chaînes `debut`/`fin` relues (voie `lus` de `CreneauConfirme`), jamais `pourAction` ; écart consigné dans `CONTRATS_RPC_ETABLISSEMENT.md`. |
| D27 | Alerte de requalification CDD | adoptée | Non portée ; ligne de parité « renvoi web » (surface de `/etablissement/missions/:id`). |
| D28 | Clôture rétroactive | adoptée | Sélecteur borné à [début du segment ouvert, maintenant] ; refus serveur `p_heure_fin > now()` proposé dans B5b. |
| D29 | Découpage de T2 | adoptée | T2a (session, coquille, drapeaux, registre de destinations) en vague 2 ; T2b (liens) en vague 3. |
| D30 | Textes verbatim | adoptée | Mécanisme TL du lot 2 seul ; constantes du lot 5 ajoutées par T0 (amendement 6). |

## Amendements et précisions relevés par la tranche T0

1. **TL du lot 2 réutilisée par fusion.** `Legal/TextesWeb.swift` n'existe pas sur `origin/feat/ios-lot1` : la
   branche du T0 fusionne `origin/lot2/l2-tl` (`3e25f507`) au lieu de recopier les fichiers (« réutilise TL »,
   D30) ; l'intégration du lot 5 suppose TL intégré (même commit, aucun conflit si TL évolue par commits ajoutés).
2. **Quatorze RPC suivies, dédoublonnées.** Les 13 RPC du T0 plus `fn_obtenir_conversation` (« si le lot 4 ne
   l'a pas ajoutée ») entrent dans `RPC_SUIVIES_ETABLISSEMENT` ; l'ajout à `RPC_SUIVIES` saute toute RPC déjà suivie
   par un lot antérieur, qui garde son lot et devient partagée (`aussi_etablissement`). Le T0 du lot 2 suit
   `fn_creer_notation_mission` en lot 2 et le T0 du lot 4 `fn_obtenir_conversation` en lot 4 : les fusions ne
   créent aucun doublon ; `rpc-contracts.json` est régénéré (`--update`) après chaque fusion, comme prévu au §4.
3. **Sept RPC partagées.** Outre les cinq du T0 (`fn_get_my_role`, `fn_ecrire_audit_safe`,
   `fn_etat_pointage_mission`, `fn_envoyer_otp_signature`, `fn_signer_contrat_otp`), `fn_audit_connexion` (audit de
   session conservé, §2.2) et `fn_param_bool` (drapeaux `ios_natif_etab_*`, §2.8) sont annotées.
4. **Listes blanches.** Extraites pour toutes les RPC du lot 5 (vides quand le corps ne lève rien), y compris
   `fn_creer_notation_mission` (`P0001` d'audit en échec, l.27425) et `fn_obtenir_conversation` (`28000`, `22023`,
   `42501`). Les fonctions appelées et les triggers sont nommés par RPC (`EXCEPTIONS_ETABLISSEMENT`) ; extraction
   fail-closed (message entièrement dynamique, condition inconnue, `%%`, `E''`, trigger absent).
5. **Codes de blocage de publication.** `fn_blocage_publication_etab` en renvoie cinq (`ETABLISSEMENT_NON_VERIFIE`,
   `VERIFICATION_INCOMPLETE`, `CONTRAT_SERVICE_REQUIS`, `PUBLICATION_SUSPENDUE`, `FACTURES_IMPAYEES`), chacun avec son
   `message` ; la correction 8 en citait quatre. La fiche et la garde les listent tous.
6. **Textes du lot 5 dans `TextesWeb.swift`.** Mention CGV art. 8 = trois nœuds de texte du web (l.393, l.395,
   l.397) et le chemin du lien (l.394), assemblés comme React (`cgvMention`) ; titre de suspension à la l.61 (le nœud
   de texte du `<h3>` l.60-62) ; bandeau de vérification l.564-565 ; option « Salarié » (libellé et description,
   l.766). La mention « Conforme art. 1366-1367 Code civil » de l'écran de signature est déjà `Contrat.otpDescription`
   (TL) : non dupliquée. La garde TL fixe la liste des fichiers sources ; ses quatre fichiers du lot 5 y sont ajoutés.
7. **Périmètre de `check-litteraux-juridiques.mjs`.** Le blueprint vise `ios-native/**/*.swift` ; la garde lit le
   Swift **livré** et exclut les cibles de test (dossiers `*Tests`), qui rejouent verbatim des refus serveur
   (`RPCResponseTests`, « [CODE DU TRAVAIL] … Art. L3121-20 ») et des textes de `TextesWeb` (`TextesWebTests`) :
   aucune règle n'y est livrée. Exceptions exactes : `Legal/TextesWeb.swift` et la seule constante
   `RPCResponse.marqueurCodeDuTravail`. Les sources de la matrice incluent aussi les paires `'source_libelle', '…'`
   du dump (repli live de `fn_mode_exercice`). Filtres de chemins de `ios-swift-ci.yml` : la garde et son test ;
   pas `supabase/migrations/**` (un littéral Swift n'apparaît qu'avec un changement sous `ios-native/`, qui déclenche
   le job ; éviter de lancer les jobs macOS sur chaque migration).
8. **Matrice de parité initiale.** Les 47 lignes portent `à faire` en statut et la cible (`natif` / `renvoi web
   assumé`) dans une colonne dédiée : aucune ligne n'est statuée avant la preuve de sa tranche (pratique du lot 1).
9. **Nombre de drapeaux.** D-FLAGS mentionne « 6 clés `ios_natif_etab_*` » (v1 du blueprint) ; D14 (v2, adoptée
   telle quelle par la règle générale) en compte **7** avec `pointage`, coupe-circuit du polling 5 s. La migration
   D-FLAGS doit poser les 7 ; à vérifier par la tranche qui l'écrit (aucune migration dans le T0).
10. **Matrice des permissions.** Documentée dans `CONTRATS_RPC_ETABLISSEMENT.md` (5 rôles × 11 clés) et comparée au
    `CASE` de `fn_a_permission_etablissement` par la garde ; `matricePermissionsEtablissement` (export de
    `check-rpc-contracts.mjs`) est le lecteur que T1 réutilise pour `demo-etab-permissions.json`.

## Précisions relevées par la tranche T1

Aucune ne change une décision du §7 ni une règle juridique ; elles fixent ce que le blueprint laissait ouvert.

1. **Session sans contexte, identité démo injectée.** `EtabSessionPort.permissions(etablissementId:)` et `profil()`
   gardent la signature du blueprint (§2.4 : le serveur lit le JWT). Le monde démo lit l'utilisateur de la session
   démo courante par une fermeture `identite` (branchée sur `DemoAuthGateway.restoreSession` dans `DemoWorld`) et
   refuse tout autre compte que `demo-etablissement` (`.demoOnly`) ; aucune valeur d'utilisateur n'est supposée.
2. **Établissement démo = `demo-etab-1` du monde soignant.** Le blueprint (§2.10) nomme l'établissement « Clinique
   de démonstration » ; `demo-etab-1` porte déjà le nom « Établissement fictif République » dans
   `demo-etablissements.json`. L'exporteur dérive l'établissement démo de `DEMO_ETABLISSEMENTS[0]` : un seul nom par
   identifiant (état dérivé). Le compte legacy démo garde l'utilisateur `demo-etablissement` (identifiant d'utilisateur
   ≠ identifiant d'établissement, contrairement à un vrai compte legacy) : T2 sert l'établissement confirmé par le rôle
   démo, comme `fn_get_my_role` le fait pour un legacy réel (correction 2).
3. **Audit démo.** `DemoEtabAuditGateway` (journal en mémoire) est ajouté au monde démo : un port câblé côté Supabase
   l'est dans les deux mondes (`SupabaseGatewaysTests`).
4. **Issues complétées.** `TraitementCandidatureOutcome.refusEnregistre` (refus d'une candidature répondu
   `success:true`, absent de la liste du §2.4) ; `MotifRenvoiWebCandidature` nomme les trois renvois (D10, D25) ; les
   contrats de domaine (`EtabDashboardSnapshot`, `EtabMissionResume`, `LectureCandidaturesHabilitee`, `PresenceEtab`,
   `PublicationMission`…) sont **minimaux**, complétés par leur tranche, sans aucun champ monétaire ni note ;
   `EtatPointageEtab` réutilise `CodeRotatifRules.Etat` (T3).
5. **Traitement des exceptions dans les listes Swift.** Chaque entrée de `ListesBlanchesEtablissement` porte son
   traitement (verbatim, message neutre, générique, session) ; la liste (SQLSTATE, message) est comparée au JSON.
   « Notification d'acceptation impossible : % » est `générique` : jamais interceptée ni affichée (revue B8 de T0,
   mineur 5).
6. **Triggers RBAC des tables écrites** (revue B8 de T0, mineur 3) : `fn_traiter_candidature_planning_v1` →
   `trg_p0_rbac_missions`, `trg_p0_rbac_contrats_mission`, `trg_p0_rbac_candidatures` ; `fn_declarer_fin_retroactive` →
   `trg_p0_rbac_presences`, `trg_p0_rbac_missions` ; extraits par `check-rpc-contracts.mjs` (`--update`), message neutre.
7. **Clôture rétroactive et `POINTAGE_ONLY`** (revue B8 de T0, mineur 4) : amendement pour T8 consigné dans la fiche
   `fn_declarer_fin_retroactive` de `CONTRATS_RPC_ETABLISSEMENT.md`.
8. **`fn_ecrire_audit_safe` reste `a_venir` lot 1.** RPC partagée, propriété du lot 1, déjà appelée par
   `SupabaseAuditGateway` sans être passée en `consommee` ; T1 ne modifie pas l'entrée d'un autre lot (pas de conflit
   avec les tranches du lot 1). `fn_mes_permissions_etab` et `fn_mon_etablissement_complet` passent en `consommee`.

## Précisions relevées par la tranche T2a

Aucune ne change une décision du §7 ni une règle juridique ; elles fixent ce que le blueprint laissait ouvert.

1. **Registre de destinations dans `JoleneCore`.** `enum EtabDestination` vit dans
   `JoleneCore/Etablissement/EtabDestination.swift` (et non dans l'app) : il est testé sans cible de tests de
   l'app, et T2b le rendra depuis `LinkRouter.etablissementDestination`. L'app ne garde que le `switch`
   (`Screens/Etablissement/EtabDestinations.swift`, une ligne par tranche). Chaque destination nomme sa
   permission (§2.7) et son drapeau ; le contrat suit le drapeau `missions` (aucune des sept clés de D14 ne
   vise les contrats).
2. **Drapeaux.** `EcranNatifEtablissement` et `EcransEtablissementModel` (`JoleneCore/Session/EcransEtablissement.swift`)
   ; valeurs propres à un epoch (une lecture d'une autre identité ne s'applique jamais). La méthode s'appelle
   `ecranEtablissementActif(_:)` : une surcharge de `ecranActif(_:)` rendait ambigus les appels `.accueil` /
   `.missions` du lot 1. Amendement 9 vérifié : la migration D-FLAGS (#1111) pose les sept clés
   (`EtabFeatureFlagsTests` relit la migration).
3. **Lot 1 T9 non intégré.** `DrapeauxLancement` est porté au même chemin que T9 (`Session/EcransNatifs.swift`,
   code identique) : à la fusion de T9, garder la version de T9. *Report sur main (18/11/2026, `feat/ios-lot5-v2`)* :
   main lit ces surcharges par `DemoFlagsGateway.surcharges(arguments:)` (lot 2 T4b) ; `EcransNatifs.swift` est
   retiré et l'espace établissement emprunte ce lecteur unique. `SessionStore` lit les drapeaux établissement
   avant de publier `.readyEtablissement` (ajout localisé) ; à la fusion, l'audit de session de T9 doit traiter
   `.readyEtablissement` : `connexion()` et `deconnexion()` oui, `activite()` jamais (correction 12, garde
   `testAucuneActiviteSoignantNiProfilSoignantPourUnEtablissement`).
4. **Frontières d'epoch en revalidation silencieuse** (le blueprint ne les fixait que pour la relecture après
   refus) : autre établissement → « périmètre divergent », epoch + 1 ; accès retiré ou compte inactif →
   epoch + 1 ; soignant ↔ établissement → epoch + 1 et instantané ré-étiqueté ; même établissement → rôle et
   permissions remplacés à epoch constant.
5. **Relecture après refus.** `SessionStore.refreshEtablissementScope()` (→ `SessionController.refreshEtablissementScope(epoch:)`) :
   une lecture de `fn_mes_permissions_etab(NULL)` par appel, l'écran appelle une fois par refus ; deux refus
   concurrents ne sont pas fusionnés (deux lectures, sans effet de bord). Erreur transitoire : état conservé,
   jamais de déconnexion.
6. **Textes natifs ajoutés (non juridiques)** : messages `ETAB_SANS_ACCES` et `ETAB_SCOPE_DIVERGENT`, titre
   « Établissement à confirmer », écran d'accès refusé, renvoi web (annonce de la reconnexion, D16), contenus
   provisoires « Disponible au lot 5 ». Libellés des rôles d'équipe repris de `EquipeEtablissement.tsx`
   l.45-49 (garde de dérive dans `DemoEspaceTests`).
7. **Monde démo à deux espaces.** Avec `-JOLENE_DEMO_ESPACE etablissement`, tout email ouvre le compte
   établissement fictif, sauf celui du soignant fictif, qui ouvre l'espace soignant (frontière d'epoch prouvée
   dans la même session). `DemoRoleEspaceGateway` sert `demo-etab-1` au compte legacy comme au membre (mineur 7
   de la revue T1). La bannière de connexion démo cite toujours l'email du soignant fictif.
8. **« Publier » dans la barre de l'onglet Missions** (`etab-missions-publier`, permission `missions`, destination
   `.publication`) est posé par la coquille ; T5 le garde en remplissant le contenu de l'onglet, T4 pose celui
   de l'Accueil.
9. **Compte provisoire** (nom, rôle, email, déconnexion, version, sentinelle réseau) jusqu'à T12 ; le lien de
   suppression du compte (D17) arrive avec T12 : l'espace établissement n'est pas à exposer hors démo avant T12
   (Apple 5.1.1(v)).
10. **Renvoi web sans présentateur `.safari`** (lot 1 T10 non intégré) : le bouton ouvre la racine
    `https://jolene.app` (hors AASA), comme le renvoi de T9 ; l'URL exacte du renvoi est exposée en valeur
    d'accessibilité de `etab-renvoi-web-ouvrir`.
11. **D24** : durée du job UI non mesurée par la tranche (aucun test UI lancé localement, consigne disque) ; à
    relever sur le premier run CI qui inclut `DemoEtabSessionTests`.

## Report sur `main` et tranche T2b (18/11/2026)

1. **Espace fermé hors démo** (fail-closed, ajout du report) : `OuvertureEspaceEtablissement.pour(mode:)` — démo
   ouvert, staging et production fermés. Fermé, un rôle établissement reçoit `.blocked(.unsupportedRole(<rôle>))`,
   le refus d'avant le lot 5, sans appel établissement (`SessionControllerEtablissementTests`). Motif : les drapeaux
   D14 valent 1 et sont lus fail-open ; ils ne masquent donc pas une coquille encore provisoire. T13 ouvre STAGING,
   T14 ouvre la production ; chaque ouverture est une ligne de `pour(mode:)` et un test.
2. **T2b, choix par espace** : la table établissement (`LinkRouter.etablissementDestination`) ne sert que l'espace
   établissement ouvert ; l'espace soignant garde sa table (lien établissement → renvoi web). `/contrat/{id}` mène au
   contrat de l'espace courant ; tant que T10 n'est pas livrée, renvoi web dans l'espace établissement.
3. **T2b, écrans livrés** : `EtabDestination.ecranLivre`, une ligne par tranche (T5-T11), toutes à `false` ; chaque
   tranche passe sa ligne à `true` avec sa ligne de `EtabDestinations.swift` et ajuste `EtabRouteTests`.
4. **Revue B8 de #1147 (CLÔTURABLE), mineurs traités** :
   - m1 : sans espace, seul un lien établissement à route **native** est mémorisé ; `/etab/invitation/{token}` et les
     routes en renvoi web assumé restent présentés aussitôt (règle du lot 3). Limite consignée : un lien natif mémorisé
     est perdu si la session s'arrête sur `.blocked` (même règle que les liens soignant) ; corrigé par T13 (section T13,
     point 3) pour les liens établissement ;
   - m2 : fixtures de test fermées par défaut (configuration de production), assertions de `main` rétablies ; espace
     fermé prouvé pour la restauration, `signIn`, la revalidation silencieuse, `.session(autre)` et le legacy (refus
     exact, aucun appel établissement), et `SessionStore` ne lit aucun drapeau `ios_natif_etab_*` ;
   - m3 : garde Node du câblage d'`AppContainer` (`.pour(mode: environment.mode)`), `ouvrirEspaceEtablissement`
     ignoré quand l'espace est fermé ;
   - m4 : dossiers du lot 5 sous la garde « aucun texte juridique en dur » (`DOSSIERS_LOT2`), marques `48 h` et
     « plafond légal », textes `[juridique]` de TextesWeb refusés en sous-chaîne hors de TextesWeb.swift
     (`check-litteraux-juridiques`), et verrou : aucun source livré ne référence `CandidaturesEtablissement`,
     `BlocageEtablissement` ni `PublicationEtablissement` avant la validation de Gabrielle (liste `VALIDES` de
     `contrats-etablissement-ios.node.mjs`) ;
   - m5 : XCUITest du lot 5 hors du socle, répartis dans deux éclats légers.

## Précisions relevées par la tranche T4 (Accueil, 18/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; elles fixent ce que le blueprint laissait ouvert.

1. **Titre de suspension et bandeau de vérification non affichés** (HARD STOP n°4, §6.4) : `TextesWeb.BlocageEtablissement`
   reste hors des sources livrées (`VALIDES` vide dans `contrats-etablissement-ios.node.mjs`). En attendant la validation
   d'écran de Gabrielle, les actions « blocage » et « vérification » portent des textes natifs de navigation, sans
   qualification de l'état du compte (« Action requise sur jolene.app », « Vérification de l'établissement ») et mènent
   aux pages web qui l'expliquent (`/etablissement/facturation`, `/etablissement/activer`). La validation remplacera ces
   textes par les constantes verbatim et ajoutera `BlocageEtablissement` à `VALIDES`. Levé à l'intégration de la vague D (point 1 de
   sa section) ; textes validés explicitement par la fondatrice le 24/11/2026 (« Oui, je valide », référence au point 1).
2. **Litiges et évaluations sous `missions`** : aucune clé de `fn_mes_permissions_etab` ne vise ces deux pages web. Choix
   d'affichage fail-closed (pas une règle) : membres qui gèrent les missions (PROPRIETAIRE, ADMIN_GROUPE, RH) ; un
   POINTAGE_ONLY ou un LECTURE_SEULE ne les voit pas. Blocage et vérification restent visibles de tout membre, comme le
   bandeau du web.
3. **Factures à régler** : compteur seul (`nb_factures_impayees`, `${n} facture(s) à régler` du web), sous
   `lecture_paiement` ∨ `paiement`, placé après les litiges ; aucun montant.
4. **Actions résolues par la table des liens** : chaque action, « Publier une mission » et chaque ligne du planning portent
   le chemin web du web ; `LinkRouter.etablissementDestination` décide (onglet de la coquille, écran livré, sinon renvoi
   Safari). Publication (T9) et détail de mission (T5) sont donc des renvois web jusqu'à ce que leur tranche passe
   `EtabDestination.ecranLivre` à `true` ; aucun écran provisoire n'est ouvert depuis l'Accueil.
5. **Planning à venir** : port de `construireOccurrencesPlanning` (fenêtre de 31 jours, repli ponctuel ≤ 24 h, missions
   « à confirmer ») en liste, sans vue mois/semaine ni nom de soignant ; dix occurrences affichées, le compteur garde le
   total. Lecture PostgREST (`missions` + `mission_creneaux` par `MissionSlotPager`) ; son échec rend l'Accueil partiel.
6. **Audit `DONNEES_PERSO_CONSULTATION`** écrit par `EtabAccueilModel` après chaque lecture réussie (les deux mondes),
   jamais attendu par l'écran. Le profil (blocage, vérification) est celui de l'instantané de session (relu à la
   revalidation 30 min) ; le serveur refuse de toute façon une publication bloquée.
7. **XCUITest** `DemoEtabAccueilTests` (3 tests) dans l'éclat « lot3-profil-photo », avec `DemoEtabSessionTests` ; gardes
   `ios-swift-ci-eclats.node.mjs` et `check-rpc-contracts-lot3.node.mjs` mises à jour, aucun douzième éclat.

## Précisions relevées par la tranche T5 (missions : liste et détail, 18/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; aucun texte juridique n'est ajouté (libellés d'interface
du web repris, refus serveur verbatim).

1. **Contrats de domaine complétés en place** (`Models/EtablissementResults.swift`) : `EtabMissionResume`,
   `EtabMissionsPage`, `EtabMissionDetail` et `SoignantPourEtab` reçoivent des champs optionnels à défaut (signatures
   des protocoles et initialiseurs existants inchangés) ; décodage tolérant, filtres et compteurs dans
   `Etablissement/Missions/EtabMission.swift`. Colonnes lues = `EtabMissionResume.clesDecodees`, sans aucun montant
   (D15) ; `fn_soignant_pour_etablissement` réduite à `SoignantPourEtab.clesDecodees` (jamais `note_moyenne`,
   `nb_evaluations`, `type_exercice`, `internat`).
2. **Pages cumulatives** (comme « Mes missions » du lot 1) : la page `n` relit les lignes 0…(n + 1) × 50 − 1, ordre
   `debut_le` décroissant puis `id` (pagination stable ; le web ne pagine pas côté serveur et trie sur `debut_le` seul).
3. **Compteurs exacts** : `select=statut` par pages de 1 000 avec compte exact (le web s'arrête à la limite de lignes de
   PostgREST) ; un échec laisse les pastilles **sans nombre**, jamais un « (0) » supposé ; les derniers compteurs relus
   restent affichés.
4. **Candidatures en attente** (pastille de carte, bandeau et lien du détail) lues seulement avec la permission
   `candidatures` (fail-closed, §2.7) : plus strict que le web, où la RLS `lecture_candidatures` les sert aussi à
   `LECTURE_SEULE`.
5. **Planning** : complétude de `CompletudePlanning` (source contractuelle) sur la carte comme au détail ; un planning
   non exact est « Planning détaillé à confirmer » (le web affiche sur la carte un repli ponctuel tiré de
   `debut_le`/`fin_le` ; M3 de la démo). Au détail, l'échec de lecture du planning n'efface pas la mission
   (« Planning détaillé momentanément indisponible : … », message serveur verbatim).
6. **Liens du détail** : chaque lien pousse la destination du registre si sa tranche l'a livrée
   (`EtabDestination.ecranLivre`), sinon ouvre la page web équivalente par le présentateur de renvoi (Safari, D16) :
   candidatures (T6) → `/etablissement/missions/{id}`, code de pointage (T7) et présences (T8) →
   `/etablissement/presences/mission/{id}`, contrat (T10) → `/etablissement/contrats` et message (T11) →
   `/etablissement/messagerie` (identifiants de contrat et de conversation non lus avant leur tranche). Modifier,
   dupliquer, annuler : renvois web sous la permission `missions` (RLS `pol_mission_update`). Sans présentateur,
   aucun bouton de renvoi (règle du lot 3).
7. **`EtabDestination.detailMission.ecranLivre = true`** : `/etablissement/missions/{id}` ouvre le détail natif
   (`EtabRouteTests`, `DeepLinkCoordinatorTests`, `DemoEtabLiensTests` migrés) ; `?statut=` d'un lien vers la liste
   sélectionne le filtre (insertion dans `EtablissementTabView`, jeton `DemandeFiltreMissions`) ; `?periode=mois`
   n'est pas porté (renvoi implicite : liste complète).
8. **Monde démo** : onze missions M1…M11 du §2.10 (`demo-etab-missions.json`, `scripts/mobile/demo-etab-missions.mjs`),
   soignant assigné principal = le soignant fictif du monde soignant (`demo-soignant`, projeté depuis son profil démo :
   une identité par identifiant) ; candidatures réduites à `mission_id`/`statut`/`cree_le`, compteurs **dérivés** par
   la gateway (T6 complète ces lignes, sans second compteur).
9. **XCUITest** `DemoEtabMissionsTests` (deux tests) dans l'éclat « presences » (place laissée par `DemoFavorisTests`),
   jamais dans le socle (garde `ios-swift-ci-eclats`). Non exécuté localement (aucun simulateur) : preuve CI.

## Précisions relevées par la tranche T6 (candidatures, 18/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; aucun texte juridique n'est ajouté (libellés d'interface
du web repris, refus serveur verbatim, quelques textes natifs de navigation).

1. **Mention CGV art. 8 non affichée (HARD STOP n°4).** `TextesWeb.CandidaturesEtablissement` reste verrouillée
   (`VALIDES` vide dans `contrats-etablissement-ios.node.mjs`) : l'écran montre un lien de navigation neutre,
   « Conditions générales de vente sur jolene.app » (`https://jolene.app/cgv#art8`, ancre du web l.394), sans résumer
   les clauses. Après la validation d'écran de Gabrielle : la mention verbatim remplace ce lien (identifiant
   `etab-candidatures-cgv`) et `CandidaturesEtablissement` entre dans `VALIDES`. Levé à l'intégration de la vague D (point 1 de sa
   section) ; texte validé explicitement par la fondatrice le 24/11/2026 (« Oui, je valide », référence au point 1).
2. **D25 gardé deux fois.** Le modèle aiguille avant tout appel (contrat recherché relu par `EtabMissionsPort.mission`,
   profession de la lecture habilitée, étudiant aide-soignant) ; la gateway Supabase relit en plus, sous RLS, la
   candidature puis sa mission (`id, etablissement_id, type_contrat_recherche, profession_requise`) juste avant l'appel :
   hors `SALARIE` ou `MEDECIN` → `.renvoiWeb`, aucun appel RPC ; ligne illisible → aucun envoi. La signature du port
   (T1) est inchangée. T6 reste hors B9 : `fn_traiter_candidature_planning_v1` n'est jamais appelée pour une mission où
   un escrow est possible.
3. **Refus de droit des lectures** : nouvelle erreur `RefusAccesEtablissement` (message serveur verbatim) pour la lecture
   habilitée (42501 de la liste blanche) ; les mutations gardent l'issue `.accesRefuse`. L'écran relit le périmètre une
   fois (`SessionStore.refreshEtablissementScope`), jamais une déconnexion. `JoleneError.Kind` non étendu.
4. **Issue jamais tenue pour confirmée** : toute issue (succès, délai, transport, `{error}` sans drapeau) est suivie
   d'une relecture ; succès = `ACCEPTEE` + mission `ASSIGNEE`, ou `REFUSEE`. `PLANNING_*_RECONFIRMER` relit et remplace
   le récapitulatif avec le message serveur, sans renvoi automatique. « Cette candidature a déjà été traitée. » est
   affiché tel quel après relecture.
5. **Textes natifs ajoutés (non juridiques)** : « Accepter sur jolene.app », « L'acceptation de cette candidature se fait
   sur jolene.app, où une nouvelle connexion peut vous être demandée. » (D16), « Voir sur jolene.app » (facturation),
   « Conditions générales de vente sur jolene.app », « La décision n'a pas pu être confirmée par une relecture.
   Vérifiez les candidatures avant de recommencer. », « Cette candidature n'est plus en attente. ».
6. **Statut des candidatures traitées** : parité du web (l.524), tout statut autre qu'`ACCEPTEE` s'affiche « ❌ Refusée ».
7. **Monde démo** : candidatures de `demo-etab-missions.json` complétées (`soignant_id`, `message`) et `candidats` (la
   lecture habilitée des mêmes soignants, nom à l'initiale) **dérivés** de `soignants` par le générateur ; troisième
   soignant fictif (étudiante aide-soignante) ; `DemoEtabEtatCandidatures` partage les décisions de la session entre les
   gateways démo des missions et des candidatures (mission acceptée relue `ASSIGNEE` des deux côtés) ;
   `-JOLENE_DEMO_PLANNING_MODIFIE 1` (première acceptation à reconfirmer). L'étudiante est renvoyée au web par
   l'aiguillage (la démo ne reproduit pas le texte serveur `CADRE_ETUDIANT_A_CONFIRMER`).
8. **`EtabDestination.candidatures.ecranLivre = true`** ; `DemoEtabMissionsTests` migré (le lien du détail ouvre l'écran
   natif ; la preuve du renvoi web d'un lien non livré passe au lien de message, T11). XCUITest
   `DemoEtabCandidaturesTests` (deux tests) dans l'éclat « presences », jamais dans le socle (garde
   `ios-swift-ci-eclats`). Non exécuté localement (aucun simulateur) : preuve CI.

## Précisions relevées par la tranche T7 (pointage terrain, 18/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; aucun texte juridique n'est ajouté (libellés d'interface
du web repris, refus serveur verbatim, quelques textes natifs de navigation).

1. **Code lu au serveur, jamais calculé.** `code_pointage_actif` de `fn_etat_pointage_mission`, relu à chaque tic ; aucun
   secret ni code suivant côté client (aucune clé de la réponse du scanner n'est lue, garde
   `scripts/ci/scanner-code-sans-code-suivant-pg17.py`). Une valeur qui n'est pas exactement six chiffres ASCII
   (`PayloadQR.codePointage`, règle du scanner natif du lot 2) n'est jamais présentée : « Code momentanément
   indisponible », plus strict que le web.
2. **Cadence (D23).** 5 s, écran visible et scène active seulement (tâche de l'écran relancée à chaque changement de
   `scenePhase`, annulée à la disparition ; première lecture immédiate au retour) ; planning et signature relus à
   l'ouverture puis toutes les 60 s, et à chaque tic tant qu'ils n'ont pas pu être lus ; attente découpée en tics de
   15 s qui réévaluent l'affichage sans réponse nouvelle (web l.119-123). Seul le monde démo change la cadence
   (`EtabPointagePort.cadenceLecture`, `-JOLENE_POLL_INTERVAL <s>`, entre 1 s et 5 s exclus) ; le port Supabase garde 5 s.
3. **Erreurs.** Les deux premiers échecs consécutifs gardent la dernière lecture (le web les absorbe par trois relances) ;
   au troisième, le code est retiré (bloc « Code de pointage indisponible » avec le message de l'erreur,
   `etab-pointage-indisponible`, « Réessayer ») et la cadence passe à 30 s ; une lecture réussie rétablit 5 s. Un refus
   jsonb (`{error:'Mission introuvable'|'Accès interdit'}`) est affiché verbatim, sans aucune autre clé. Signature : le
   42501 de la liste blanche vaut `false` (fiche) ; planning illisible : code d'arrivée masqué (fail-closed, web l.231-255).
4. **B5b déjà côté serveur.** Le dump re-baseliné ne sert le code qu'aux membres habilités au pointage, et le web filtre
   aussi par la permission (l.102-115) : sans elle, aucune lecture ni polling ; le texte de `.reservePointage` devient
   celui du web (l.110) au lieu du texte natif du blueprint (§2.7, non juridique).
5. **Écran sans veille.** `IdleTimerController` vit dans `JoleneCore/Etablissement/Pointage/` (testé par `swift test` :
   la cible app n'a pas de tests unitaires), l'app ne porte que l'adaptateur `ReglageVeilleApplication`
   (`Jolene/Composition/VeilleEcran.swift`, `UIApplication.isIdleTimerDisabled`). Demandes comptées par demandeur,
   valeur d'avant la première demande rétablie à la dernière libération. La veille est désactivée tant qu'un code est
   présenté (écran du code ou plein écran) sur un écran visible d'une scène active — lecture de « pendant l'affichage »,
   plus large que le plein écran seul du blueprint ; rétablie à la disparition, en arrière-plan et dès que le code est
   masqué (le plein écran se ferme alors de lui-même).
6. **Plein écran dans la même vue.** `FullScreenCodeView` (JoleneDesign) remplace le contenu de l'écran, barres de
   navigation et d'onglets masquées, plutôt qu'un `fullScreenCover` : une seule tâche de lecture, aucune course entre la
   disparition de l'écran et l'apparition de la couverture. QR de `QRCodeImage` (lot 4 : correction M, sans lissage) au
   plus grand, 70 % du petit côté, en portrait comme en paysage.
7. **D4/D5.** Le QR encode `code_pointage_actif` relu ; `DemoEtabPointageTests` le décode par `CIDetector` (le décodeur
   de `PayloadQRTests` du lot 2 et des tests de `QRCodeImage` du lot 4) sur la capture de l'élément, en la valeur
   affichée, avant puis après le scan démo. Le critère réécrit attend toujours la validation de Gabrielle (§6.9) ; la
   comparaison `sha256` à la valeur SQL relève de T13 (STAGING).
8. **Monde démo.** `demo-etab-pointage.json` (`scripts/mobile/demo-etab-pointage.mjs`) **dérive** horaires et statuts de
   `demo-etab-missions.json` : M4 rejoue `123456` deux lectures puis l'état relu après le scan d'arrivée (`EN_COURS`,
   segment ouvert, `100002`) ; M5 sans contrat signé ; M6 hors créneau, premier créneau pointé. Écart démo assumé : le
   statut `EN_COURS` rejoué de M4 n'est pas reporté sur la gateway des missions (le détail reste « Assignée »).
9. **Non porté** : « Clôturer le segment » (fin rétroactive, `fn_declarer_fin_retroactive`), présences T8 (B9).
10. **`EtabDestination.pointage.ecranLivre = true`** : le lien « Code de pointage » du détail ouvre l'écran natif.
    XCUITest `DemoEtabPointageTests` (deux tests) dans l'éclat « lot3-profil-photo », jamais dans le socle (gardes
    `ios-swift-ci-eclats`, `check-rpc-contracts-lot3`). Non exécuté localement (aucun simulateur) : preuve CI.
11. **Textes natifs ajoutés (non juridiques)** : « Afficher en plein écran », « Fermer », « QR du code de pointage »,
    « Aucun code de pointage n’est à présenter pour cette mission. », « Le planning de cette mission n'a pas pu être
    relu. », « Impossible de charger le planning détaillé. Réessayez. ».

## Précisions relevées par la tranche T11 (messagerie établissement, 24/11/2026)

Base : `lot4/l4-t7b` (messagerie du lot 4, pas encore sur `main`). Aucune décision du §7 ni règle juridique changée ;
aucun texte à portée contractuelle ajouté ; textes du web établissement repris mot pour mot.

1. **Extension additive du port** : `MessageriePort` reçoit les mêmes méthodes avec `etab: EtablissementReadContext`
   (défaut : refus « non câblé » T11, aucun double à retoucher) et `conversationPourSoignant(missionId:soignantId:etab:)`
   (`fn_obtenir_conversation(p_autre_id := soignant assigné, p_mission_id)`, sans `fn_user_id_pour_etablissement`,
   comme `DetailMission.tsx` l.1083). Les modèles du lot 4 (`ConversationsModel`, `FilModel`, `BlocageModel`,
   `SignalementModel`, `CycleRealtime`) prennent un `ContexteMessagerie` (soignant ou établissement) ; les écrans du
   lot 4 sont réemployés tels quels (`ContexteEcranMessagerie`), aucun second écran.
2. **Auteur = utilisateur courant** : `moi` est `user.id` de la session dans les deux espaces ; la gateway refuse tout
   envoi dont `etab.userId` n'est pas l'utilisateur du JWT ; l'edge pose `auteur_id = auth.uid()`. Règles d'affichage du
   rôle `ADMIN_ETABLISSEMENT` (web l.305-307, l.738-748) : non-lu = message du soignant seul ; bulle d'un collègue du
   côté de l'établissement avec « Équipe établissement ».
3. **Compteurs relus** : l'Accueil garde `messages_non_lus` de `fn_stats_dashboard_etablissement` ; l'onglet Messages
   porte le badge `fn_messages_non_lus()` du cycle. En démo, l'Accueil relit les non-lus de la messagerie démo (état
   dérivé, plus la valeur figée de la fixture). Cycle Realtime ouvert aussi pour `.readyEtablissement`, coupe-circuit
   `ios_natif_etab_messages_actif`.
4. **Écarts au web assumés** : « Contacter le soignant » (libellé du bouton web, l.1085) est une ligne de lien du détail
   et empile le fil sur la pile courante (le web navigue vers `/etablissement/messagerie?conv=`) ; signalement depuis le
   fil (le web ne le propose que sur le profil du soignant, `ProfilSoignantEtablissement.tsx` l.145 : cible
   `SOIGNANT`, sans mission), comme T7b pour Apple 1.2 ; libellé de cible du blocage « cet utilisateur » (défaut web hors
   rôle soignant). L'écriture n'est pas filtrée par une permission côté natif : le web n'en filtre aucune, le serveur
   juge (`CONVERSATION_NON_AUTORISEE` → libellé générique du web).
5. **Monde démo** : `demo-etab-messagerie.json` (`scripts/mobile/demo-etab-messagerie.mjs`, dérivé des missions démo) ;
   `EtabDestination.conversation.ecranLivre = true`. XCUITest `DemoEtabMessagerieTests` (deux tests) dans l'éclat
   « lot4 » du job `ui-lot1` ; `DemoEtabMissionsTests` (fil natif au lieu du renvoi web), `DemoEtabLiensTests`,
   `DemoEtabAccueilTests`, `DemoEtabSessionTests` migrés vers `messagerie-screen`. Non exécutés localement : preuve CI.

## Précisions de l'intégration de la vague C (19/11/2026)

Branche `integration/ios-vague-c` (T4 à T7 réunies avec le lot 4). Aucune ne change une décision du §7 ni une règle
juridique ; aucun texte juridique n'est ajouté.

1. **Action « candidatures » de l'Accueil** (revues B8 de #1160 et #1162, m1) : la mise à jour du filtre `?statut=` de la
   liste des missions (`DemandeFiltreMissions`, T5) est faite par `EtablissementTabView.ouvrir(_ cible:)`, chemin commun
   des liens et des actions de l'Accueil : `/etablissement/missions?statut=OUVERTE` ouvre Missions sur « Ouvertes »
   (assertion `DemoEtabAccueilTests`).
2. **Libellés neutres** (#1160, m3) : « Valider les présences » et « Évaluer vos soignants » remplacent « Présences à
   valider » et « Soignants à évaluer », actions sans compteur (correction 20) dont le titre n'affirme plus un fait que
   l'app ne connaît pas. Textes d'interface, non juridiques.
3. **« Planning à confirmer » : un seul prédicat** (#1160, m4 ; principe « État dérivé ») : l'Accueil
   (`EtabPlanningAccueil.planningExact`) utilise `CompletudePlanning.analyser`, comme la liste et le détail des missions,
   le code de pointage et l'espace soignant. Écart assumé au critère local de `DashboardEtablissement.tsx` l.354-363 :
   bornes lisibles et `fin > debut` exigées, repli ponctuel accepté quand `nb_creneaux` vaut 0 ou manque.
4. **Liste des missions** (#1162, m2) : un changement de filtre repart de `.chargement` ; son échec rend `.echec`, jamais
   l'ancienne liste sous la nouvelle pastille. Le même filtre relu garde sa liste (erreur de rafraîchissement seule).
5. **Détail de mission** (#1162, m4 et m6) : uuid canonique exigé avant tout appel (`/etablissement/missions/abc` →
   « Mission introuvable », aucune requête) ; la relecture du soignant a sa propre génération et n'abandonne plus une
   relecture de la mission en vol (`rafraichissement` retombe à faux).
6. **Candidatures** (#1164, m2) : une lecture habilitée sans `etablissement_id` est refusée (fail-closed).
7. **Code de pointage** (#1166, m1 et m3 ; revue B8 de #1168, m1) : la veille est libérée explicitement à la
   disparition et quand la scène devient inactive (garde node `contrats-etablissement-ios`). Une seule lecture à la fois
   par génération : la réservation est posée de façon synchrone **avant** la première suspension (`contexte()`) par
   « Réessayer » comme par le suivi (première lecture et tic). Un second toucher, le tic ou la première lecture qui la
   trouvent posée ne lancent rien : deux lectures ne partent jamais en parallèle, et une panne ne compte qu'un échec
   (`CodeRotatifModelTests.testReessayerVerrouillePendantUneLectureEnVol`, `testDeuxReessayerSimultanesUneSeuleLecture`).
8. **Écart connu, veille sous une feuille** (revue B8 de #1168, m2) : une feuille présentée par-dessus
   `CodePointageScreen` (par exemple le renvoi web du coordinateur après un tap sur une notification push) ne déclenche
   pas `onDisappear`. La veille reste donc coupée tant que la feuille couvre le code ; elle est rétablie à la fermeture de
   l'écran, en arrière-plan, quand la scène devient inactive ou quand le code est masqué. Aucun code natif ne le détecte
   aujourd'hui (SwiftUI ne signale pas la couverture par une feuille d'un autre niveau) : ligne dédiée de
   `RECETTE_DEVICE_LOT5.md` §1, à observer sur appareil avant T13.

## Précisions relevées par la tranche T12 (compte minimal et renvois web, 24/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; aucun texte juridique n'est ajouté (libellés du menu web
repris, deux libellés de navigation nommés au point 4).

1. **Table dans `JoleneCore`** (`Etablissement/Compte/RenvoisWebEtab.swift`, et non sous `Jolene/Screens/` comme l'écrit
   le blueprint) : la cible app n'a pas de tests unitaires (même motif que le registre de destinations, T2a point 1).
   L'app ne porte que l'écran (`EtabCompteScreen.swift`, monté par `EtabCompteRoot`), sans aucune règle.
2. **Vingt-trois clés**, celles du §3 T12 : `parametres` mène à `?tab=profil` sous le libellé du menu web « Mon
   établissement » (l.63), `notifications` au centre de notifications (`/etablissement/notifications`, ligne de la
   matrice), `api` à la redirection `/etablissement/api`. Cinq routes que la matrice confie à T12 n'ont pas d'entrée
   dans le Compte, parce que le menu web ne les propose pas : `/etablissement/mes-reclamations`,
   `/etablissement/reclamations`, `/etablissement/parametres/notifications`,
   `/etablissement/parametres/recherches-sauvegardees` (atteintes depuis leur page parente) et `/etablissement/activer`
   (action de l'Accueil, T4). `RenvoisWebEtabTests.testRoutesDeLaMatriceAttribueesAT12` prouve pour chacune des vingt et
   une routes sa présence dans `App.tsx` et son renvoi web, et exige une entrée ou une absence motivée.
3. **Entrées réservées** (§2.7, fail-closed ; booléens servis, aucune table rôle → permission) : équipe sous
   `gerer_equipe` (blueprint) ; factures et prélèvement SEPA sous `lecture_paiement` ∨ `paiement` — le `canReadFinance`
   du web, qui masque « Facturation » dans sa barre latérale (`BarreNavigation.tsx` l.217) ; plus strict que le menu web
   du compte, qui montre « Mes factures » à tout membre — ; litiges et évaluations sous `missions` (même choix que
   l'Accueil, T4 point 2) ; configuration Chorus Pro sous la condition des factures **et** `est_secteur_public` servi
   vrai (le web ne propose ce lien qu'au secteur public, `FacturationEtablissement.tsx` l.1765 ; valeur absente :
   masqué). Tout le reste, suppression du compte comprise (D17), est offert à tout membre, comme le menu web.
4. **Libellés.** Dix-huit lignes du menu web (libellé et route sur la même ligne de `MonCompteEtablissement.tsx`, garde
   `RenvoisWebEtabTests`), ses titres de section, « Configuration Chorus Pro » (titre de `ChorusConfig.tsx`), « API REST
   Jolene » (titre de section d'`APIEtablissement.tsx`), « Notifications » (libellé du menu, page du centre). Deux
   libellés ne viennent pas d'une ligne du menu ; `RenvoisWebEtab.libellesNatifs` les nomme : « Évaluer vos soignants »
   (libellé neutre de l'Accueil, vague C point 2) et « Prélèvement SEPA » — libellé de navigation : le blueprint demande
   un renvoi « SEPA » vers `/etablissement/facturation` que le menu web ne nomme pas ; le mot est celui du mode de
   paiement sur le web (`DetailFacture.tsx` l.44). Non repris : les autres onglets de la page Paramètres (« Facturation &
   contrat », « Opérations », « Sécurité & RGPD »), le thème, « Contacter Jolene » (modale sans page), le type
   d'établissement en sous-titre.
5. **Textes natifs ajoutés (non juridiques)** : « Les pages ci-dessous s'ouvrent sur jolene.app, où une nouvelle
   connexion peut vous être demandée. » (D16, formule de l'Accueil et du détail d'une mission), « Application »,
   « Version ».
6. **Logo** : emblème de bâtiment, comme le web (`MonCompteEtablissement.tsx` l.97-102 lit `logo_url` sans l'afficher).
   Aucune image distante n'est chargée (l'app n'a pas de chargeur d'image distante).
7. **Ouverture** : chaque entrée rend sa route externe (`.etablissement(url)` sous l'AASA, `.safari(url)` pour une page
   légale), présentée par le présentateur `.safari` du coordinateur des liens ; jamais `openURL`. Sans présentateur,
   aucune entrée (règle du lot 3). L'URL est une constante de la table : ni jeton, ni identifiant, ni donnée de session
   (`testUnRenvoiEstUnLienConstantSansJetonNiDonneePersonnelle`).
8. **Sources web relues par les tests Swift** : `src/App.tsx`, `src/pages/MonCompteEtablissement.tsx`,
   `src/pages/ChorusConfig.tsx` et `src/pages/APIEtablissement.tsx` entrent dans les filtres `pull_request` et `push` de
   `ios-swift-ci.yml` (garde `check-sources-web-ios-ci`). Coût : une PR web qui touche `App.tsx` relance la CI iOS.
9. **Monde démo** : `-JOLENE_DEMO_SECTEUR_PUBLIC 1` (`DemoEtablissementWorld.Configuration.secteurPublic`) sert le même
   établissement fictif comme relevant du secteur public, pour prouver le renvoi Chorus Pro au niveau 2 ; la fixture
   n'est pas modifiée.
10. **Identifiants** : `etab-compte-screen` remplace `etab-compte-list` (pile non paresseuse : chaque entrée existe dans
    l'arbre d'accessibilité, même hors écran) ; `DemoEtabSessionTests` migré. XCUITest `DemoEtabCompteTests` (deux tests)
    dans l'éclat « lot5-etablissement » du job `ui-lot1`, jamais dans le socle (garde `ios-swift-ci-eclats`). Non exécuté
    localement (aucun simulateur) : preuve CI.
11. **Point 9 de T2a** : le lien de suppression du compte (D17) est livré ; l'ouverture de l'espace hors démo reste
    décidée par T13 (STAGING) et T14 (production). Compte coupé par son drapeau : comportement de T2a inchangé (renvoi
    vers `/etablissement/mon-compte`, déconnexion offerte).

## Précisions relevées par la tranche T8 (présences, 24/11/2026)

**B9 paiements/escrow (D7)** : valider une présence déclenche côté serveur la libération du séquestre
(`trg_escrow_release_on_validation`), contester la bloque (`motif_litige`). La tranche est poussée avec ses tests,
**jamais mergée sans l'accord explicite de Gabrielle**. Aucune précision ne change une décision du §7 ni une règle
juridique ; aucun texte juridique n'est ajouté (libellés d'interface du web repris, refus serveur verbatim, quelques
textes natifs de navigation). Lignes citées : web et dump de `main` au 24/11/2026 (après #1153 et le re-baseline #1174).

1. **RPC appelées telles quelles, une requête par geste, jamais renvoyée.** `fn_valider_presence(p_presence_id)`,
   `fn_valider_presences_lot(p_ids)`, `fn_contester_presence(p_presence_id, p_motif)`,
   `fn_creer_notation_mission(p_mission_id, 'ETAB_VERS_SOIGNANT', note ×4, NULL)`,
   `fn_declarer_fin_retroactive(p_mission_id, p_heure_fin, p_raison)`, puis les relectures (`presences` par identifiant,
   `fn_etat_pointage_mission.segment_ouvert`). Aucun montant ni aucune durée n'est lu, calculé ou envoyé ; aucun audit
   doublé (le serveur écrit `PRESENCE_VALIDATION`, `PRESENCE_VALIDATION_LOT`, `PRESENCE_CONTESTATION` ; le web les double).
2. **« Validée » après relecture seulement.** La gateway relit `valide_par_etablissement` et `valide_le` avant de rendre
   `.validee` (relecture fausse → erreur, jamais un succès) ; le modèle n'écrit aucun état local (la mise à jour
   optimiste du web, l.265-267, n'est pas portée) et relit la liste après chaque action. Issue inconnue (délai,
   transport) : liste relue, jamais la mutation renvoyée. `enCours` est posé avant tout `await` : double toucher = un appel.
3. **Lecture en liste blanche.** `presences` : `PresenceEtab.clesDecodees` + `missions!inner(id, intitule, service,
   debut_le, fin_le, nb_creneaux, etablissement_id)` — jamais `arrivee_lat/lng`, `depart_lat/lng`, `coherence_incidents`,
   `duree_heures`, `heures_reelles`, `alertes_fraude`, précisions GPS, ni aucun montant. « Prévu » et « Réel » sont les
   sommes de `SynthesePresence` (lot 2, port doré) sur les créneaux relus : des durées planifiée et pointée, jamais une
   durée facturée. **Écart** : l'écart en minutes du web (`CarteValidation.tsx` l.144-148) n'est pas affiché.
4. **Nom du soignant** : le blueprint ne le lisait pas ; `fn_soignant_pour_etablissement` (port de T5, déjà consommée)
   est appelée une fois par soignant listé (25 au plus par lecture, au mieux) ; en échec, « Soignant » (repli du web
   l.430). `fn_mes_soignants_etablissement` et la table `soignants` ne sont pas lues.
5. **Contestation** : proposée pour une présence « à valider » seulement ; motif de 3 caractères au moins après
   nettoyage (borne et message du serveur, sans requête en dessous), saisie bornée à 500 caractères (choix natif). La
   contestation d'une présence **validée** (`PanneauContestation`, fenêtre lue au serveur depuis #1153), l'ouverture d'un
   litige et le fil de litige restent sur jolene.app : aucun texte de délai n'est affiché.
6. **Clôture rétroactive** : action offerte avec la permission `pointage` servie (§2.7), sans table de rôles côté natif.
   Le serveur exige en plus `est_admin_etablissement()` : un membre `POINTAGE_ONLY` reçoit son refus 42501 mot pour mot,
   comme sur le web (amendement de la fiche, revue B8 de T0, mineur 4). **D28 verrouillé deux fois** : `ClotureSegment`
   (modèle) et la gateway refusent une heure postérieure à maintenant avant tout envoi ; le sélecteur est borné à
   [début du segment ouvert, maintenant], en heure de Paris. La saisie passe par `DateHeureParis.instantDepuisSaisie`
   comme le web : une heure que le fuseau refuse (inexistante au printemps, répétée à l'automne) reçoit le message du web.
   Le dump actuel ne sert plus `nouveau_code` ni `nouveau_hmac` ; la gateway ne lit que `creneau_effectif_id`.
7. **Note (D6)** : obligatoire avant la validation unitaire, envoyée après la validation relue, au mieux ; un refus
   serveur de la note (« Seules les missions TERMINEE peuvent être notées »…) s'affiche à part, mot pour mot, sans
   défaire la validation. La validation en lot ne note pas (parité web). Le détail par critère du web n'est pas porté
   (la note est répliquée sur les quatre critères).
8. **Compteur de l'Accueil non branché** (écart au blueprint) : le web n'a pas ce compteur (correction 20) et le
   brancher imposerait de relire toutes les présences et leurs créneaux à chaque ouverture de l'Accueil, sur une base à
   CPU partagé. L'action « Valider les présences » reste sans compteur ; `PresencesEtabRules.repartir` le fournirait.
9. **Monde démo** : `demo-etab-presences.json` (`scripts/mobile/demo-etab-presences.mjs`) **dérive** l'embed et le planning
   de `demo-etab-missions.json` et les segments de M4 et M6 du dernier état de `demo-etab-pointage.json`. Écarts au
   §2.10 : le segment à clôturer est celui de **M4** (T7 a livré M6 avec son premier créneau fermé) ; aucune présence
   validée au départ (pas de douzième mission dans la fixture commune) ; les écritures de la session vivent dans un
   acteur et sont relues. Écart démo assumé : une clôture faite dans Présences n'est pas reportée sur l'écran du code de
   pointage de M4 (gateway de T7 inchangée). Le serveur fictif reproduit les refus du serveur mot pour mot.
10. **`EtabDestination.presencesMission.ecranLivre = true`** : `/etablissement/presences/mission/{id}` ouvre les présences
    de la mission (même écran, sans onglets ni lot) ; `?tab=` d'un lien vers la page sélectionne l'onglet (insertion dans
    `EtablissementTabView`, jeton `DemandeOngletPresences`). Port étendu de deux lectures (`missionsTerminees`,
    `creneaux(missionId:)`), signatures existantes inchangées.
11. **Identifiants ajoutés au blueprint** : `etab-presence-litige-{id}`, `etab-presence-note-refus`,
    `etab-presences-{succes|avertissement|erreur}`, feuilles `etab-{validation|contestation|cloture|presences-lot}-feuille`.
    `ContestationEtabSheet` (et non `ContestationSheet`, déjà pris par l'espace soignant).
12. **XCUITest** `DemoEtabPresencesTests` (quatre tests) dans l'éclat « lot5-etablissement » du job `ui-lot1`, jamais dans
    le socle. Non compilé ni exécuté localement (Xcode local 16.4, aucun simulateur) : preuve CI. Les cibles iOS seules
    (`JoleneDesign`, app) ne sont pas compilées localement non plus.
13. **Textes natifs ajoutés (non juridiques)** : « Chargement des présences… », « Contester la présence », « Annuler »,
    « L'heure de fin ne peut pas être postérieure à l'heure actuelle. », « N présence(s) validée(s) sur M
    sélectionnée(s). », « L'action n'a pas pu être confirmée par une relecture. Vérifiez les présences avant de
    recommencer. ».

## Précisions relevées par la tranche T9 (publication d'une mission, 24/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; aucun texte juridique n'est ajouté (libellés d'interface
du web repris, refus serveur verbatim, quelques textes natifs de navigation).

1. **Mention du type de contrat (HARD STOP n°4) — état à la livraison de T9, levé à l'intégration.** À la livraison de
   T9, la description de l'option « Salarié » (`TextesWeb.PublicationEtablissement`, `FormulaireMission.tsx` l.766)
   restait verrouillée et le récapitulatif n'affichait aucun type de contrat. Depuis l'intégration de la vague D
   (point 1 ; textes validés explicitement par la fondatrice le 24/11/2026, « Oui, je valide »),
   `mentionContrat` rend les deux constantes verbatim et `publier-recap-contrat` est affiché.
   **Gap verrouillé** (toujours en vigueur) : sans la mention, l'espace établissement ne s'ouvre pas hors démo
   (`PublicationPresentationTests.testMentionContratExigeeAvantToutEspaceOuvertHorsDemo`) ; T13 et T14 ne peuvent pas
   ouvrir STAGING ni la production sans elle. La carte de la mission publiée porte, elle, le libellé de contrat de la
   liste des missions (T5, `badgeContrat`).
2. **Périmètre fixé par la charge (D8).** `PublicationPayload` envoie les seize paramètres de la signature SQL, dont sept
   constants : `p_type_contrat_recherche 'SALARIE'`, `p_mode_remuneration 'TAUX_HORAIRE'`, rétrocession, nature de TVA et
   spécialité `NULL`, `p_accepte_internes false`. L'écran ne propose ni n'affiche aucun type de contrat ni mode
   d'exercice ; `fn_mode_exercice` n'est ni appelée ni décodée. Une profession `MEDECIN` n'est jamais retenue par le
   modèle et est refusée avant réseau par les deux gateways.
3. **Renvois web (D8).** Quatre lignes « Autres options », texte neutre du blueprint mot pour mot (« Cette option se
   configure sur jolene.app. »), titres composés des libellés du web : « Type de contrat proposé : Tous profils ou
   Libéral », « Profession requise : Médecin », « Sélection rapide des dates : Lundi–vendredi, 1 semaine civile sur 2 »,
   « Dupliquer une mission ». Les trois premières ouvrent `/etablissement/missions/creer`, la duplication
   `/etablissement/missions` (elle part d'une mission). Un lien `…/missions/creer?dupliquer=<id>` reste un renvoi web
   (`LinkRouter.etablissementDestination`), le formulaire natif ne reprenant aucune mission source. « Récurrence
   avancée » = la sélection rapide du web (« Toutes les dates », « Lundi–vendredi », « 1 semaine civile sur 2 »,
   « Aucune ») ; « Appliquer le 1er horaire aux jours sélectionnés » est natif.
4. **État dérivé.** Dates vides au départ (aucune date fictive) ; « Choisir la date » pose le jour civil de Paris de
   l'horloge de la session (la dernière date reprend la première si elle existe) ; boutons « Jour précédent » / « Jour
   suivant » et sélecteur. Toute modification d'une borne re-dérive les jours par `PlanningDerive.rederiver` : jour
   resté dans la période conservé (état, créneaux, exceptions), jour nouveau au repos avec le créneau 07:00-19:00 du
   web, jour sorti supprimé, période vide ou inversée sans aucun jour (parité `FormulaireRecurrence.tsx` l.164-178).
   Erreurs, créneaux matérialisés et total d'heures sont recalculés à chaque lecture, jamais stockés.
5. **Validation locale structurelle seulement (D9).** Champs obligatoires (intitulé d'au moins trois caractères,
   profession de la liste, taux supérieur à zéro, niveau 1 à 3 si urgente), période, jour travaillé sans créneau, créneau
   invalide, chevauchement. Non portés : « créneau déjà commencé », taux conseillé, estimation, commission, contrôle par
   semaine civile, couleurs de durée : le serveur refuse, son texte est affiché mot pour mot. **Corrigé** (revue B8 des
   textes de la vague D, M4) : le minimum du champ taux du web (`min`, l.921) n'était tenu par aucune couche (le serveur
   ne refuse qu'un taux ≤ 0) ; il est désormais repris (section « Corrections des revues B8 de l'intégration de la
   vague D », textes M4).
6. **Issue `.nonConfirmee(missionId)` ajoutée à `PublicationOutcome`** : le serveur a répondu `success:true` mais la
   relecture est impossible ou différente de l'envoi (comparaison par instants, `PublicationRelecture.confirme`). Le
   blueprint disait « erreur » ; l'issue porte l'identifiant et n'est jamais un succès. Une erreur levée pendant l'envoi
   (délai, transport) est une issue inconnue : « La publication n'a pas pu être confirmée par une relecture. Vérifiez
   vos missions avant de recommencer. », aucun renvoi automatique. Seul un refus de session (`28000`, « Non
   authentifié ») dit que rien n'a été publié.
7. **Relecture par la gateway.** `missions` (`id, etablissement_id, statut, nb_creneaux, debut_le, fin_le,
   type_contrat_recherche`, établissement confirmé) puis `mission_creneaux` PREVISIONNEL par le pager exact de T5 ;
   aucun montant relu. Le modèle ne relit pas une seconde fois : le port ne rend `.publiee` qu'après cette relecture.
8. **Niveaux d'urgence.** Libellés réduits au premier mot des options du web (« Modéré », « Élevé », « Critique ») : la
   suite (« — besoin sous 48h ») porte la marque d'un plafond d'heures que la garde des textes refuse hors de
   `TextesWeb.swift`. À reprendre en entier par une constante de `TextesWeb.swift` si Gabrielle le souhaite.
9. **Blocage de publication.** Pas de pré-contrôle natif (les textes de blocage de l'Accueil sont verrouillés, T4) : le
   blocage vient du serveur à l'envoi (`fn_blocage_publication_etab`, `message` mot pour mot, `publier-blocage`), avec
   « Voir sur jolene.app » vers `/etablissement/facturation` (`PUBLICATION_SUSPENDUE`, `FACTURES_IMPAYEES`) ou
   `/etablissement/activer` (les trois autres codes), comme les liens du web.
10. **Identifiants.** Récapitulatif sur `ConfirmationSheet` : `publier-recap` (+ `-title`, `-message`, `-confirm`,
    `-cancel`) au lieu de `publier-confirmer` ; bouton du formulaire `publier-ouvrir-recap` ; créneaux
    `publier-creneau-{date}-{i}` avec `i` à partir de 0 (comme le `data-testid` du web), lignes du récapitulatif
    `publier-recap-creneau-{n}` à partir de 1 (`SlotList`) ; dates `publier-date-{debut|fin}` (+ `-choisir`,
    `-precedent`, `-suivant`).
11. **Monde démo.** Aucune fixture JSON nouvelle : `DemoEtabEtatPublication` (acteur de session) reçoit la mission
    créée et journalise la charge ; les gateways démo des missions et des candidatures le relisent (la mission apparaît
    « Ouverte »). `-JOLENE_DEMO_BLOCAGE 1` → `PUBLICATION_SUSPENDUE` au texte du serveur. Refus rejoués : aucun créneau,
    début dans le passé (horloge démo), droit `missions` absent (`CREATION_MISSION_INDISPONIBLE`) ; aucune règle du
    temps de travail n'est rejouée.
12. **`EtabDestination.publication.ecranLivre = true`** : « Publier » (barre de Missions), « Publier une mission »
    (Accueil) et `/etablissement/missions/creer` ouvrent l'écran natif (`EtabRouteTests`, `DeepLinkCoordinatorTests`,
    `DemoEtabSessionTests` migrés). XCUITest `DemoEtabPublicationTests` (quatre tests) dans l'éclat
    « lot5-etablissement » du job `ui-lot1`, jamais dans le socle (garde `ios-swift-ci-eclats`). Non exécuté localement
    (aucun simulateur) : preuve CI ; durée de l'éclat à relever au premier run. Niveau 1 vérifié en local le 24/11
    (Xcode 16.4, `swift build --build-tests` puis `swift test`, concurrence stricte) : JoleneCore 2 394 tests et
    JoleneSupabase 713 tests, aucun échec, aucun avertissement. Les trois écrans de `Screens/Etablissement/Publication/`
    et la classe XCUITest ne sont **pas** compilés en local (cible app, `xcodebuild` exclu) : première compilation en CI.
13. **Textes natifs ajoutés (non juridiques)** : « Autres options », « Ouvrir sur jolene.app », « Choisir la date »,
    « Jour précédent », « Jour suivant », « Voir mes missions », « Voir la mission », « Publier une autre mission »,
    « Voir sur jolene.app », « La publication n'a pas pu être confirmée par une relecture. Vérifiez vos missions avant
    de recommencer. », « Le planning n'a pas pu être préparé. Vérifiez les dates et les horaires. », « La publication
    n'a pas pu aboutir. Vérifiez votre connexion. », et les quatre titres de renvoi du point 3. Émojis décoratifs du web
    non repris (titre du récapitulatif, « Publier », « Modifier », succès).

## Précisions relevées par la tranche T10 (contrats et signature OTP établissement, 24/11/2026)

Aucune ne change une décision du §7 ni une règle juridique ; aucun texte juridique nouveau (textes du web repris par
`TextesWeb` et `LibellesWeb`, refus serveur traduits comme le web, quelques libellés natifs de navigation).

1. **Port étendu, écrans réemployés (D18).** `ContratsPort` reçoit huit méthodes à contexte `EtablissementReadContext`
   (défaut « non câblé » pour les conformances antérieures) ; `ContratModel`, `ContratsListeModel`, `ContratScreen`,
   `ContratsListeView` et `SignatureOtpView` du lot 2 servent les deux espaces, aiguillés par `PartieContrat`. Aucun
   appel sans la permission `contrats` servie (`ContratsEtablissement.verifier`, fail-closed). Supabase : extension
   `Etablissement/SupabaseEtabContratsGateway.swift` du gateway du lot 2 (liste `eq(etablissement_id)`, détail borné à
   l'établissement, compte TEST sur `etablissements.est_compte_test` ; la mission n'est pas relue, ses montants non
   plus, D15) ; succès de signature annoncé seulement après relecture de `signature_etablissement_le` non nul et de la
   preuve `signatures_contrats` du membre.
2. **Identifiants.** Écran du lot 2 réemployé : ses identifiants restent (`contract-otp` pour le champ du code,
   `contrat-signer` pour la validation, au lieu de `contrat-otp` et `contrat-otp-valider` du plan) ; racine
   `contrat-detail` dans l'espace établissement (jamais `contrat-screen`) ; `etab-contrats-screen`, `etab-contrat-{id}`,
   `etab-contrat-statut-{id}` (pastille, dans le bouton de la carte), `contrat-otp-envoyer`, `contrat-signe`,
   `contrat-preparer-web` comme prévu ; `contrat-mode-otp` pour le mode de signature.
3. **Point d'entrée (D13).** Aucun onglet « Contrats » : bouton « Contrats » de la barre de Missions
   (`etab-missions-contrats`) et lien « Contrats » du détail d'une mission assignée, tous deux masqués sans la
   permission `contrats` (absents pour POINTAGE_ONLY et LECTURE_SEULE). Liens `/etablissement/contrats?statut=` et
   `/contrat/{id}` natifs dans l'espace établissement ; `/contrat/{id}/certificat` reste un renvoi web (§1.2), le résumé
   du certificat restant affiché sur le contrat.
4. **Mode de signature affiché (HARD STOP n°4, validé le 24/11/2026).** Au-dessus du formulaire OTP, l'écran établissement montre
   `TextesWeb.Contrat.otpLibelle` et `TextesWeb.Contrat.otpDescription` (`ContratMission.tsx` l.742 et l.745, mention
   « Conforme art. 1366-1367 Code civil »), verbatim, comme le web ; la signature manuscrite n'est pas proposée. Ces
   textes sont ceux du lot 2 et ne sont pas sous le verrou `VALIDES` de `contrats-etablissement-ios.node.mjs`. Ils
   figurent dans la liste validée explicitement par la fondatrice le 24/11/2026 (point 1 de l'intégration de la vague D,
   « Oui, je valide »).

## Précisions de l'intégration de la vague D (24/11/2026)

Décisions prises par Claude sur délégation de Gabrielle du 24/11/2026 (« t'as mon go pour tout faire et tout merger
meme paiements etc », « comme tu veux, tu es maitre prends tes décisions »), une par point.

1. **Textes établissement déjà affichés par le web : repris mot pour mot et affichés (décision c).** Les trois blocs
   ci-dessous, d'abord affichés sur délégation générale, font partie de la liste des textes à portée juridique de la
   revue B8 du tour 2 (section 6, groupes A à E), **validés explicitement par la fondatrice le 24/11/2026** (« Oui, je
   valide », consigné dans la PR : https://github.com/Gabpcd/JJJJJ/pull/1179#issuecomment-7142442809) au titre du HARD STOP n°4.
   **Ce que la validation ne couvre pas** : tout texte ajouté après cette liste (il repasse par une validation) ; le
   site, où les trois promesses du groupe D (« +10 points », « sous 72h », « validation étab sous 1h ») restent
   affichées (suivi web à part : seuls leurs retraits natifs sont validés) ; l'ouverture de l'espace établissement hors
   démo, qui fera l'objet d'une PR dédiée. La garde
   `tests/node/contrats-etablissement-ios.node.mjs` retenait ces blocs de `TextesWeb` hors des écrans. Chacun est un
   texte que le web affiche aujourd'hui tel quel (constante égale au texte du web, au caractère près, par
   `check-textes-juridiques-ios`) ; la liste `VALIDES` les reçoit, et la garde exige leur référence dans ce point 1
   (revue B8 d'assemblage de la vague D, M2 : une simple mention ailleurs dans ce fichier ne suffit plus) :
   - `TextesWeb.PublicationEtablissement` : « Salarié » et « Vous êtes l’employeur : CDD, bulletin de paie, plafond
     légal 48 h/semaine » (`src/components/FormulaireMission.tsx` l.766, description de l'option « Salarié » du
     formulaire de publication), affichés dans le récapitulatif avant publication (`PublicationPresentation.mentionContrat`,
     identifiant `publier-recap-contrat`). Précision T9 n°1 levée.
   - `TextesWeb.CandidaturesEtablissement` : mention « Avant d’accepter un candidat, consultez les conditions de
     non-contournement et de recrutement direct — CGV art. 8. Elles précisent les situations concernées, les durées
     applicables et le calcul des frais de recrutement. » (`src/components/ListeCandidatures.tsx` l.390-398, montée par
     `DetailMission.tsx` au-dessus des candidatures en attente), affichée à la même place au-dessus des candidatures en
     attente ; le lien « non-contournement et de recrutement direct — CGV art. 8 » est souligné et la mention ouvre
     `https://jolene.app/cgv#art8` (identifiant `etab-candidatures-cgv-lien` ; `etab-candidatures-cgv` sans
     présentateur). Le lien neutre « Conditions générales de vente sur jolene.app » est retiré. Précision T6 levée.
   - `TextesWeb.BlocageEtablissement` : « Publication de missions suspendue » (`BandeauBlocageAuto.tsx` l.61, titre du
     bandeau de suspension automatique), « Votre compte est en cours de vérification » et « Vérifiez votre
     établissement (FINESS + rattachement du représentant) pour pouvoir publier des missions. À défaut, l'équipe Jolene
     valide votre dossier. » (`DashboardEtablissement.tsx` l.564-565), titres et détail des actions « blocage » et
     « vérification » de l'Accueil (`PrioriteActions.Textes`). Le détail de l'action « blocage » reste le texte natif
     de navigation « Consultez la situation de votre établissement sur jolene.app. » ; la date de blocage, les raisons
     et les montants du bandeau web (l.63-88) ne sont toujours pas portés. Précision T4 levée.
   Aucun texte retenu par la garde n'est absent du web : aucun n'est resté non affiché pour ce motif.

## Corrections des revues B8 de l'intégration de la vague D (24/11/2026)

Trois revues fraîches de la PR #1179 (assemblage et CI, sécurité et argent, textes et règles métier), toutes « À
CORRIGER ». Un commit par constat ou petit groupe ; les réponses constat par constat sont postées dans la PR.

**Assemblage et CI.**
- B1 : `DemoEtabMessagerieTests` attend `etab-compte-screen` (L5-T12) ; relevé par script de tous les identifiants
  littéraux des XCUITest contre les sources de l'app : aucun autre manquant.
- M1, m1 : « lot5-etablissement » (22 méthodes) scindé en « lot5-etablissement » (liens, missions, candidatures, compte :
  11) et « lot5-etablissement-ecrans » (présences, publication, contrats : 11). Plafond du job `ui-lot1` : 25 + 1 + 1 +
  7 × 30 + 15 = 252, porté à 255 min ; en-tête réécrit. La garde exige au plus 17 méthodes par éclat du job et un
  en-tête qui énonce le plafond posé. Les précisions T8 n°12, T9 n°12 et T10 qui citent « lot5-etablissement » datent
  d'avant la scission.
- M2 : voir le point 1 de l'intégration de la vague D ; garde durcie (référence au point 1 de la section de décision),
  puis adaptée à la validation explicite du 24/11/2026 (mention datée et référence exigées, aucun bloc validé encore
  « en attente »).

**Sécurité et argent.**
- M1 : une série dont les missions ne viennent pas toutes du même établissement n'est pas un pack
  (`SerieRegles.unSeulEtablissement`, gateway et modèle) : « Pack introuvable », rien n'est présenté ni coché. Le web
  et le serveur ne sont pas modifiés (le web garde le comportement relevé, à corriger hors chantier iOS).
- m1 à m6 : retrait des balises jusqu'à stabilité sans tenir compte de la casse ; `\`, `%` et `_` échappés dans
  l'ILIKE de la série ; formulaire bloqué après une publication non confirmée (`relectureRequise`) ; jeton de tentative
  de la session de récupération (un nouveau lien révoque d'abord, une vérification tardive n'ouvre rien) ; lien
  implicite de récupération gardé, en parité avec le site (m5, constat et raison dans `DECISIONS_LOT3.md`, « Reste de
  L1-T10 ») ; copies temporaires de contrats et de bulletins
  purgées au lancement et à la sortie des deux espaces.
- m7 (choix consigné, aligné sur l'existant) : le coupe-circuit de la messagerie (`ios_natif_messagerie_actif`,
  `ios_natif_etab_messages_actif`) reste **ouvert par défaut** : drapeau absent ou illisible = messagerie servie,
  Realtime compris (`CycleRealtime`). C'est la règle de tous les drapeaux d'écran natifs (D18 de `DECISIONS_LOT4.md`,
  D14 ci-dessus : « fail-open ») ; ils servent à couper un écran en production, pas à protéger une donnée. Les
  contrôles de sécurité de la messagerie sont au serveur (edge `messagerie-validate`, RLS) et ne dépendent pas du
  drapeau. Passer ce seul drapeau en fermé par défaut ferait de la messagerie l'exception ; à décider avec D18 si
  Gabrielle le souhaite.

**Textes et règles métier.**
- M1, M2, M3 (lot 4) : voir `DECISIONS_LOT4.md`, précisions 16 (motif corrigé) et 21.
- M4 : la publication native applique le plancher du taux horaire du web (`min` du champ hors libéral,
  `FormulaireMission.tsx` l.921), repris par `LibellesWeb.Publication.tauxMinimumHorsLiberal` et épinglé à sa ligne
  (`PublicationPayloadTests`), jamais recopié dans la logique. **Parité provisoire** : le serveur ne refuse qu'un taux
  ≤ 0 (`fn_creer_mission_multi_jours*`, `public.sql` l.27427) et le dump ne contient aucun contrôle de ce plancher. Un
  suivi serveur est à ouvrir (contrôle paramétré dans `fn_creer_mission_multi_jours*`, aucun seuil en dur, HARD STOP
  n°4) ; **non fait ici**. Le web n'a pas de texte propre (refus natif du navigateur) : l'avis sous le champ est un
  texte natif neutre, sans référence légale, valeur tirée de la constante (« Le taux horaire doit être d'au moins
  11,65 €/h. », nombre formaté en `fr_FR` depuis la constante), validé explicitement par la fondatrice le 24/11/2026
  (point 1 de l'intégration de la vague D, groupes A et E).
  **Suivi du 25/11/2026 (PR `fix/taux-minimal-salarie-smic`, HARD STOP n°4, en attente de validation)** : 11,65 €/h était
  sous le SMIC horaire brut en vigueur (12,31 € depuis le 1er juin 2026, arrêté du 22 mai 2026). Le plancher devient le
  paramètre serveur `taux_horaire_minimum_salarie` (migration `20261125120000`, verrou différé sur `missions`, SALARIE et
  TOUS, libéral exclu) ; le web le lit (`fn_taux_horaire_minimum_salarie`, repli `src/lib/tauxHoraireMinimumSalarie.ts`),
  l'app garde la constante (12.31, aucun port numérique de paramètres) ; la garde `tests/node/taux-horaire-minimum-salarie.node.mjs`
  lie les trois valeurs. Même texte partout : « Le taux horaire doit être d'au moins 12,31 €/h. ».
  **Suivi du 26/11/2026 (après le re-baseline #1193)** : l'app lit le plancher par `fn_taux_horaire_minimum_salarie()`
  (`SupabaseEtabPublicationGateway.tauxMinimumSalarie`, fiche `CONTRATS_RPC_ETABLISSEMENT.md`), seul plancher de la
  validation et de l'avis (même phrase, montant lu). Fermé : plancher non lu ou illisible → aucun taux publiable, message
  générique existant (« La publication n'a pas pu aboutir. Vérifiez votre connexion. »), relecture par « tirer pour
  actualiser » ; aucune constante substituée. Le monde démo rend sa valeur de fixture. La constante iOS ne sert plus
  qu'à cette fixture et au contrôle structurel de la passerelle avant envoi ; elle reste liée à la migration par la
  garde node. Refus serveur prouvé à travers le vrai PostgREST par la préparation STAGING du lot 5
  (`prouverRefusTauxMinimum`) et sur le schéma du dépôt par le banc L5. **Limites connues** : un administrateur peut
  abaisser le paramètre par écriture directe sur `parametres_systeme` (les bornes ne sont imposées que par
  `fn_admin_maj_parametre`) ; sur le site, l'attribut `min` du champ porte le plancher, et hors parcours le navigateur
  refuserait l'envoi d'une mission ouverte existante sous le plancher même sans changement de taux ni de contrat.
- M5 : une présence validée propose « Contester cette présence » (libellé du web, `PanneauContestation.tsx` l.365) en
  renvoi web vers `/etablissement/presences` ; aucune RPC, aucun texte de délai ; le serveur juge la fenêtre.
- M6 : l'écran contrat de l'établissement affiche le statut (`DPAEStatus.tsx`) et le rappel (`BandeauRappelDPAE.tsx`)
  DPAE du web, mot pour mot (`TextesWeb.DPAE`), sur les champs que le web lit (`dpae_numero`, `dpae_effectuee`,
  `dpae_effectuee_le`, ajoutés à la lecture, jamais écrits) ; préparation et saisie du numéro en renvoi web.
- M7 : voir M2 de l'assemblage.
- Mineurs corrigés : 8 (texte du serveur sous un motif de contestation trop court), 9 (bornes de clôture : dernier
  créneau EFFECTIF ouvert pause comprise, et minute qui suit son début, comme `fn_declarer_fin_retroactive` ; précision
  T8 n°6 à lire avec cette borne), 13 (score : « Non noté » seul sans compte servi), 14 (« ne vous a exclu. »).
- Mineurs non corrigés, une ligne chacun :
  - 6 (niveaux d'urgence sans « besoin sous 48h / 24h / 6h ») : le texte porte un délai que la garde des textes refuse
    hors de `TextesWeb.swift` (précision T9 n°8) ; à porter par une constante `TextesWeb` si Gabrielle le valide.
  - 7 (« Écart : ±N min » non affiché) : écart calculé côté client par le web ; à porter avec la synthèse, tranche à
    part, précision T8 n°3.
  - 10 (officine qui n'apprend le blocage qu'à l'envoi) : le pré-contrôle du web lit l'activité de l'établissement ;
    le refus du serveur est affiché mot pour mot ; tranche à part.
  - 11 (Compte établissement : « Notifications » vers le centre natif, « Prélèvement SEPA », « revérifier » du bandeau
    de suspension non porté) : choix de navigation de T12 ; « revérifier » déclenche une écriture serveur (RPC de
    re-vérification) hors du périmètre de cette correction.

## Mineurs du tour 2 de la revue B8 de l'intégration de la vague D (24/11/2026)

Revue fraîche du tour 2 « CLÔTURABLE », cinq mineurs ; aucun texte affiché ajouté, aucune RPC nouvelle.

1. m5 (lien implicite de récupération) : motif réécrit dans `DECISIONS_LOT3.md` (« Reste de L1-T10 »), décision
   inchangée ; renvoi corrigé en §6.6 du plan du lot 1.
2. « Contester cette présence » : le web n'affiche ce bouton que si `dansFenetre && !litige`
   (`PanneauContestation.tsx` l.105-108). L'app masque désormais le renvoi quand un litige est attaché à la carte
   (`motif_litige` relu, `PresencesEtabPresentation.carte`, test
   `PresencesEtabRulesTests.testPresenceValideeOffreLeRecoursDuWebEnRenvoi`). **Écart restant** : la fenêtre de
   contestation n'est pas connue de l'app. Le web la lit par `fn_fenetre_contestation_ouverte`, que la gateway
   établissement n'appelle pas ; la recalculer en local depuis `valide_le` recopierait le délai
   `parametres_litiges.delai_contestation_pointage_h` et son défaut serveur (interdit par D12 de `DECISIONS_LOT2.md`,
   « aucune constante de délai côté client »). Après la fenêtre, l'app propose donc encore le renvoi ; la page web
   ouverte n'affiche alors plus le bouton. Second écart : le web cherche une ligne `litiges` de la présence, quel que
   soit son statut, alors que l'app ne voit que `presences.motif_litige` ; un litige ouvert sans ce motif n'est pas
   détecté. Lever ces deux écarts suppose d'appeler la RPC de fenêtre et de lire `litiges` côté établissement
   (contrat RPC du lot 5 à étendre) : tranche à part.
3. Commentaires de documentation remis au-dessus de leur enum (`TextesWeb.CandidaturesEtablissement`,
   `LibellesWeb.DetailMission`) ; `TextesWeb.DPAE` et `LibellesWeb.Publication` gardent leur propre commentaire.
4. « Préparer les données DPAE » (`LibellesWeb.DPAE.preparer`, écran contrat, `statutDPAE`) : libellé gardé (liste
   des textes) ; **écart consigné** : sur le site, le bouton appelle `fn_generer_donnees_dpae` sur place ; dans l'app,
   il renvoie à la page du contrat sur jolene.app, où l'établissement touche le bouton une seconde fois. Aucune RPC
   DPAE n'est appelée par l'app.
5. Double réception d'un même lien de récupération : le routage ne dédoublonnait pas (`onOpenURL` et
   `onContinueUserActivity` appellent tous deux `DeepLinkCoordinator.recevoir`, et `BoiteLiensInscription` créait une
   nouvelle demande par lien). La boîte ignore désormais un lien strictement identique à celui de la demande
   présentée (vérification en cours ou formulaire ouvert) ; tout autre lien, ou le même après fermeture de l'écran,
   ouvre une nouvelle tentative, et les correctifs m4 du port (jeton de tentative, révocation de la session
   précédente) sont inchangés. Rien n'est journalisé. Test :
   `ReinitialisationTests.testMemeLienRecuDeuxFoisNOuvreQuUneTentative`.

## Suivis ouverts de la revue fraîche du delta de la vague D (25/11/2026)

- **m3 — garde des durées des éclats, iPad seulement** : `DUREES_UI_LOT1` (`tests/node/ios-swift-ci-eclats.node.mjs`
  l.523) ne mesure que `ipad-landscape` et `ipad-portrait`, alors que le job « UI lot 1 » tourne aussi sur `iphone`.
  Le plafond de 18 min n'est donc pas gardé sur iPhone. Suivi : ajouter la colonne iPhone (mesures d'un run complet) ou
  écrire dans l'en-tête de la garde que l'iPhone n'est pas gardé.
- **m1 — test Realtime, seconde tolérance sans fondement** :
  `SupabaseRealtimeGatewayTests.swift` l.240-243 accepte que l'état global saute `.connexion`. Le flux global
  (`DiffusionEvenements`, sans rejeu) reçoit pourtant chaque état publié, et son abonné est inscrit avant l'ouverture du
  canal. Avec cette tolérance, une régression qui cesserait d'émettre `.connexion` à l'échelle globale passerait. La
  première tolérance (l.185-191, flux par conversation qui garde le dernier état) reste légitime. Suivi : rétablir
  l'égalité `[.connexion, .rejoint]` sur le flux global, ou documenter un cas réel observé.

## Tranche T13 — espace établissement ouvert en STAGING et preuves contre le serveur de test (24/11/2026)

Fondement : délégation de la fondatrice du 24/11/2026 (« je t'autorise a tout, finis sans t'interrompre »). Les
décisions ci-dessous sont prises sur ce fondement et consignées sans être rediscutées. Branche `lot5/l5-t13-staging`,
partie de la tête d'assemblage de la vague D ; aucune exécution contre le STAGING dans la tranche (voir point 9).

1. **Ouverture par mode** : `OuvertureEspaceEtablissement.pour(mode:)` rend `.ouvert` en démo et en staging,
   `.ferme` en production. La production reste fermée jusqu'à T14, qui l'ouvrira après la preuve STAGING. Tests :
   `SessionControllerEtablissementTests.testOuvertureParModeDeLancement` et
   `testStagingOuvreLEspaceEtLaProductionLeRefuse` (même compte établissement : espace ouvert avec la table de
   staging, refus d'avant le lot 5 sans appel établissement avec celle de production). La garde Node
   (`tests/node/contrats-etablissement-ios.node.mjs`) lit la table : démo et staging ouverts, production fermée, trois
   cas exactement, aucun `default` ; elle échoue si la production est ouverte (vérifié en mutant la ligne). Le verrou
   de la mention de contrat (`PublicationPresentationTests.testMentionContratExigeeAvantToutEspaceOuvertHorsDemo`,
   section T9) reste en vigueur : sans la mention, ce test échouerait désormais, puisque STAGING est ouvert.
2. **Aucun texte nouveau affiché.** Un compte établissement en STAGING voit les écrans déjà livrés (T4 à T12) au lieu
   de l'écran « Espace non disponible » ; un compte soignant n'est pas concerné.
3. **Point m1 de la revue B8 de #1147, corrigé** : un lien établissement à route native, mémorisé faute d'espace
   ouvert, était perdu si la session s'arrêtait sur `.blocked` (rôle non servi, email non confirmé, compte inactif,
   périmètre divergent, onboarding). Ouvrir STAGING rendait le cas réel. `AiguillageLiens.sessionRefusee()` rend
   alors ce lien en renvoi web, comme avant le lot 5, une seule fois ; `RootView` l'appelle à chaque passage à
   `.blocked` (`DeepLinkCoordinator.sessionRefusee`). Un lien de l'espace soignant garde la règle du lot 3 (il attend
   la prochaine identité ouverte) ; le renvoi déjà affiché n'est pas redemandé. Tests :
   `DeepLinkCoordinatorTests.testLienEtablissementMemoriseRedevientUnRenvoiQuandLaSessionEstRefusee` et
   `testSessionRefuseeSansEffetHorsLienEtablissementMemorise` ; câblage de l'app lu par la garde Node (la cible app
   n'a pas de tests unitaires).
4. **Cohorte D5** (`scripts/mobile/staging-lot5-fixture.mjs`, tests `tests/node/staging-lot5-fixture.node.mjs` sur
   transport simulé, ajoutés à l'étape « Garde de livraison mobile » de validate-pr) : E1 propriétaire legacy (rôle
   `ETABLISSEMENT`, sans `etablissement_id`, sans ligne `membres_etablissement`), vérifié, commission en
   `FACTURE_MENSUELLE` sans mandat ; S1 aide-soignant salarié avec deux justificatifs `VERIFIE` ; M1 `SALARIE` en
   candidature à J+3 et la candidature `EN_ATTENTE` de S1 déposée par `fn_postuler_mission` sous son JWT ; M2
   `SALARIE` assignée à S1 par `fn_test_update_mission`, créneau de 6 minutes qui commence 12 minutes après la
   préparation, code de pointage actif, contrat `SIGNE_COMPLET` inséré côté service. Marqueur `RECETTE-L5-<run>`,
   adresses `@example.invalid`, `est_compte_test` partout, transports de notification fermés, aucun téléphone : aucun
   SMS, aucun OTP. **Verrou** : toute action refuse, avant le moindre appel réseau, la référence de production
   (`flripxtsyegjshnhzjkz`, nommée dans le message) et toute référence qui n'est pas explicitement celle du STAGING
   (`mejpriaetwgtcstbgfid`) ; chaque requête est ensuite bornée à la Management API du STAGING et au projet STAGING ;
   les actions qui écrivent exigent `LOT5_STAGING_ECRITURE=COHORTE_D5`, posé par le workflow seulement.
5. **XCUITest** `StagingEtabParcoursTests` en deux phases séparées par les scans du job : (a) connexion d'E1, nom
   affiché égal au marqueur ; (b) M1 et M2 listées ; (c) candidature de S1 acceptée, relue « Acceptée » ; (d) contrat
   de M2 lu « Statut : ✅ Signé » ; (e) code de pointage affiché, son empreinte SHA-256 égale à celle du code relu côté
   service à la préparation, QR décodé égal au code affiché ; puis, après les scans d'arrivée et de départ de S1 et la
   fin du créneau planifié, présence validée avec une note de 4 et relue « Validée ». Assertions sur texte et
   identifiants ; le code n'apparaît jamais en clair dans un message. Exclu de l'éclat socle de `ios-swift-ci.yml`.
6. **Relectures et nettoyage** : candidature `ACCEPTEE` et `traite_le`, M1 `ASSIGNEE` à S1, contrat créé pour M1,
   contrat de M2 `SIGNE_COMPLET`, `presences.valide_par_etablissement` et `valide_le`, une note
   `ETAB_VERS_SOIGNANT`, aucune ligne `paiements_escrow` ni `escrow_release_queue` pour M1 et M2, aucune notification
   de M1 ou M2 hors de la cohorte, aucune ligne `email_queue` pour la cohorte, transports fermés. Le nettoyage est une
   transaction : appartenance au run contrôlée, enfants connus supprimés, toute autre dépendance (clé étrangère
   restrictive vers une ligne de la cohorte) refusée nommément avant la suppression des parents, puis comptes Auth
   supprimés et compte final des objets marqués exigé à 0 ; il tourne même si le parcours échoue. `journaux_audit` est
   conservé (immuable).
7. **Workflow** `.github/workflows/ios-swift-lot5-staging.yml` : dispatch manuel sur `main`, SHA relu égal au SHA
   dispatché, environnement `native-staging-auth`, concurrence `jolene-supabase-staging-writes`, Xcode 26.4.1 épinglé,
   actions épinglées par SHA. Il n'utilise que des secrets existants (`STAGING_SUPABASE_ACCESS_TOKEN`,
   `STAGING_SUPABASE_PROJECT_REF`) : la clé publishable, la clé anon et la clé service_role sont relues par la
   Management API à chaque étape du script ; la clé service_role n'est jamais écrite dans `GITHUB_ENV` ni donnée à
   xcodebuild. L'xcresult n'est exporté que si le nettoyage a réussi (il contient la saisie du mot de passe du compte
   du run, alors supprimé). **Constat** : l'environnement `native-staging-auth` n'exige aujourd'hui aucune approbation
   (règle de branche `main` seulement) ; le « go B9 » de T13 est donc le geste de lancer le workflow, pas une
   approbation imposée par GitHub. Ajouter un relecteur obligatoire à l'environnement est recommandé.
8. **Reports et abandons** (décisions prises, non rediscutées) : l'étape (f) du blueprint (membre E2
   `POINTAGE_ONLY`) est reportée après la soumission aux stores ; les critères « 14 jours de bêta » et « crash-free »
   sont abandonnés (D1 de `DECISIONS_LOT6.md`, sur `main`).
9. **Ce qui n'est pas prouvé par la tranche** : rien n'a tourné contre le STAGING (aucun workflow lancé, aucune
   écriture en base depuis un poste). Le SQL de la cohorte n'a été exécuté sur aucune base ; il suit le dump
   `supabase/schema/public.sql` et sera confronté au serveur au premier run. Écarts assumés au blueprint : un seul
   script sous `scripts/mobile/` au lieu de `staging-lot5-fixture.mjs` + `scripts/ci/etablissement-fixture-sql.mjs`,
   sans empreinte md5 du catalogue (`catalogueD5`) ; l'empreinte du code est donnée au test au lieu d'être jointe à
   l'xcresult ; la publication native d'une mission (étape (e) du blueprint) n'est pas jouée ; les assertions relatives
   sur `journaux_audit` (`PRESENCE_VALIDATION`, `MISSION_CREATION`) et la notification `PRESENCE_VALIDEE` ne sont pas
   relues. Chacun est un ajout possible à la tranche, sans changer son verrou.
10. **Corrections de la revue fraîche de #1183 (25/11/2026)** :
    - M1 (nettoyage non reprenable en CI) : le manifeste disparaît avec le runner hébergé et les identifiants de la
      cohorte sont aléatoires ; « manifeste conservé pour reprise » était faux. Reprise par étiquette :
      `staging-lot5-fixture.mjs nettoyer_run` (`LOT5_NETTOYER_RUN`), exposé par l'entrée `nettoyer_run` du workflow
      (job « reprise », mêmes garde-fous : main, SHA relu, `native-staging-auth`, concurrence partagée). La cohorte est
      retrouvée par le nom exact `RECETTE-L5-<run>` de l'établissement, par les adresses
      `recette-l5-{e1,s1}-<run>@example.invalid` et par les métadonnées Auth du run ; refus avant tout appel réseau si
      l'étiquette n'a pas la forme attendue, refus sans suppression si plus d'un établissement ou d'un soignant
      correspond, si une ligne n'est pas un compte TEST, si une identité Auth est d'un autre run, d'un autre rôle ou
      d'une autre adresse, ou si un profil diverge de son compte Auth. Aucun secret publié : l'étiquette (identifiant et
      tentative du run GitHub) est affichée par le résumé et par l'erreur, qui disent désormais « reprise : relancer
      ios-swift-lot5-staging.yml avec l'entrée nettoyer_run=<run> ».
    - m2 (tables enfants) : la liste écrite à la main est remplacée par `GRAPHE_NETTOYAGE`, fermeture des clés
      étrangères du dump vers `missions`, `etablissements` et `soignants` (83 tables, enfants `CASCADE` compris pour
      leurs propres enfants restrictifs, hors `SET NULL`/`SET DEFAULT` et auto-références). Le nettoyage collecte les
      identifiants des parents vers les enfants puis supprime des enfants vers les parents. Le test Node recalcule la
      fermeture depuis `supabase/schema/public.sql` et échoue à la moindre différence (régénération hors réseau :
      `node scripts/mobile/staging-lot5-fixture.mjs graphe`) ; il vérifie aussi, indépendamment, chaque FK restrictive
      et l'ordre des suppressions. Le contrôle des dépendances inconnues reste en place (dérive du STAGING vers le dump).
    - m3 (notifications) : les notifications des missions du run sont comptées et supprimées quel que soit leur
      destinataire (`id_ressource`), en plus de celles de la cohorte.
    - m1 (QR) : le QR est décodé en plein écran, comme `DemoEtabPointageTests` ; le code du plein écran est comparé à la
      même empreinte serveur.
    - m4 (aucune approbation imposée par `native-staging-auth`) : constat consigné au point 7, inchangé.
    - m5 (textes en attente visibles en STAGING) : voir « En attente », point 4, précisé ce jour.
11. **Tour 2 de la revue de #1183 (25/11/2026)** :
    - B1 : la pagination de `scripts/ci/wait-for-supabase-deploy.mjs` est retirée (revert). L'API compare ne sert les
      fichiers qu'en page 1, 300 au plus ; `page`/`per_page` ne paginent que les commits, et le correctif aurait laissé
      passer une migration au-delà du 300ᵉ fichier. Le faux rouge des pushes de 300 fichiers et plus reste un défaut
      connu, suivi dans une PR dédiée.
    - m-A : les intitulés des missions du run sont comparés sur leur début exact `RECETTE-L5-<run> · ` : le run `N-1` ne
      reconnaît plus les missions de `N-10`.
    - m-B : six tables du graphe ne sont pas supprimables dans le contexte du nettoyage (`NON_SUPPRIMABLES` :
      `bulletins_paie`, `factures` liées à un avoir, `factures_honoraires_documents`,
      `factures_honoraires_rectifications`, `invoice_audit_log`, `mandats_facturation_signatures`). Leurs lignes de la
      cohorte sont comptées avant toute suppression et jamais supprimées ; le reste est nettoyé, et un parent encore
      référencé est conservé. Le message nomme le résidu et ses identifiants, sans proposer de relance. Aucun
      déclencheur n'est contourné. **Lecture du dump** : le parcours lui-même n'écrit dans aucune de ces tables
      (acceptation salariée : candidature, mission, contrat, notifications ; scans : présence, créneaux effectifs,
      scans ; validation : présence, note). Une seule voie y mène : le cron `auto-transitions-missions`
      (`fn_auto_transitions_missions`, toutes les 10 min en production) passe M2 `EN_COURS` à `TERMINEE` quinze minutes
      après la fin de son créneau, et `trg_auto_creer_bulletin_paie` crée alors un bulletin de paie (mission salariée).
      Si ce cron est actif en STAGING et que la phase 2, les relectures et le nettoyage dépassent ces quinze minutes,
      un bulletin de test restera, nommé par le message.
    - m-C : la suppression descend de la cohorte. Elle emporte aussi les lignes d'autres comptes qui pointent vers elle
      (parrainage dont E1 est filleul, favoris, conversations, scores de matching de S1) ; avec des identifiants neufs à
      chaque run, aucune n'est attendue.

## Second parcours STAGING, refus à la connexion (run 45575772791, 25/11/2026)

1. **Constat prouvé** (pièces de l'xcresult de la phase 1) : à l'échec, l'app affiche l'écran de connexion avec
   `login-error` « Impossible de vérifier votre accès. Vérifiez votre connexion puis réessayez. »
   (`SessionController.sessionCheckFailedMessage`) et le bouton « Se connecter » désactivé. L'enregistrement d'écran
   montre « Chargement de votre espace » pendant environ 3 s après l'envoi, puis ce message : l'identifiant et le mot de
   passe sont acceptés (sinon le message générique de connexion), le refus vient de la résolution de l'espace, pas d'un
   délai (15 s par appel). Dans `SessionController`, ce texte n'a que trois origines : échec de `fn_get_my_role` sans
   rôle signé (exclu : `app_metadata.role = ETABLISSEMENT` donne un rôle provisoire), erreur levée par
   `fn_mes_permissions_etab`, ou réponse `success:false` de celle-ci (compte inactif ou sans session). Le profil, lu
   ensuite, aurait donné « Impossible de charger votre profil… ».
2. **Ce qui est écarté** : sur le schéma du dépôt (banc SQL local), sous le rôle `authenticated` et le JWT d'E1 (les
   GRANT du dump sont donc éprouvés : une fonction réservée au rôle de service y est refusée), les trois lectures de la
   session rendent ce que l'app attend (rôle `ADMIN_ETABLISSEMENT` et E1, `PROPRIETAIRE` et E1 avec toutes les
   permissions, profil d'E1) ; le banc ne prouve rien du STAGING (données, droits, écarts au dump, Auth réel). Le décodage
   de cette forme est couvert par `SupabaseEtabSessionGatewayTests`. En production (lecture seule du 25/11/2026), les six
   fonctions de session (`fn_get_my_role`, `fn_mes_permissions_etab(uuid)`, `fn_mon_etablissement_complet`,
   `fn_a_permission_etablissement(text,uuid)`, `fn_role_etablissement_courant(uuid)`, `fn_param_bool(text,boolean)`) sont
   SECURITY DEFINER, exécutables par `authenticated` et refusées à `anon` ; la base STAGING n'a pas pu être lue. Drapeaux distants : lus après
   l'ouverture et fail-open, hors cause. Aucun écran intermédiaire n'a été montré.
3. **Ce qui n'est pas prouvé** : laquelle des deux causes restantes (erreur levée ou `success:false`) a eu lieu sur le
   STAGING, et pourquoi. L'app native n'avait jamais été connectée au PostgREST du STAGING (`PORTE_LOT0.md` 1.1 : jamais
   exécuté). Aucun journal de l'app n'est joint à l'xcresult.
4. **Correctif en avant** : (a) pré-vol dans `staging-lot5-fixture.mjs preparer` : les trois lectures de la session
   établissement sous le JWT d'E1, avec la clé publishable de l'app et le même corps ; un écart arrête la préparation avec
   la cause serveur, avant le XCUITest ; (b) diagnostic DEBUG : `SessionController.diagnostic` (étape, nature, message
   déjà mappé, jamais d'adresse ni de secret) publié par `SessionStore.diagnosticConnexion` comme valeur d'accessibilité
   de `login-error`, jamais affiché ; le XCUITest s'arrête aussitôt sur un refus et le nomme ; (c) banc SQL : pré-vol et
   acceptation de la candidature par E1 exécutés sur le schéma du dépôt.
5. **Revue de #1187 (six mineurs, traités avant le run)** : diagnostic publié avant l'état (m1) ; seul un `login-error`
   portant un diagnostic de cette connexion arrête le XCUITest, qui s'arrête aussi sur un écran de refus d'espace (m2) ;
   diagnostic, son calcul et sa valeur d'accessibilité sous `#if DEBUG` (m3) ; pré-vol avec la clé que reçoit l'app
   (`JOLENE_STAGING_PUBLISHABLE_KEY`, présente dans l'environnement de `preparer` par `GITHUB_ENV` ; workflow inchangé),
   clé employée dite sans valeur, statut HTTP et code PostgREST ou Postgres brut de chaque échec, écarts classés en
   « refus que l'app aurait aussi subi » et « contrôle plus strict que l'app » (m4) ; banc sous `SET ROLE authenticated`
   (m5) ; défaut de décodage nommé par sa clé (`JoleneError.detail`, hors égalité, jamais affiché ; diagnostic
   `permissions:contract:<clé>`) (m6).
6. **Revue du delta de #1187 (r1, r2)** : r2, le refus en HTTP 200 (`{success:false, error}` ou `{error}`) n'est plus
   classé sur une cause supposée : le pré-vol recopie, à côté de `HTTP 200`, le message `error` renvoyé par la fonction
   (« sans message serveur » s'il n'y en a pas), et l'app le porte dans son diagnostic DEBUG
   (`permissions:refus:<message>` pour un `success:false` ; `permissions:unknown:<message>` pour un `{error}` seul, déjà
   recopié). Même règle des deux côtés (`messageServeur` du script, `DiagnosticServeur.masquer` de JoleneCore, sous
   `#if DEBUG`) : jeton, clé, uuid et adresse masqués avant la troncature à 160 caractères, jamais un fragment
   d'identifiant. Le message suit `PermissionsEtabResult.messageServeur`, hors égalité et hors encodage, jamais affiché ;
   l'état de session est inchangé. r1, laissé tel quel : la clé fautive d'un défaut de décodage
   (`JoleneError.detail`) est calculée aussi en Release, mais elle n'est lue que par le diagnostic, absent en Release ;
   elle n'est donc jamais exposée.

## Troisième parcours STAGING, « session expirée » sur la première lecture (run 45677331174, 25/11/2026)

1. **Constat** : le pré-vol passe (les trois lectures de session sous le JWT d'E1, avec la clé de l'app). L'app, elle,
   échoue en 53,6 s avec le diagnostic `permissions:unauthorized:Votre session a expiré. Reconnectez-vous.` : Auth
   accepte les identifiants, puis `fn_mes_permissions_etab` est refusée. Le schéma n'est pas en cause : c'est la
   requête de l'app qui diffère de celle de la fixture.
2. **Cause PROBABLE (revue de #1191, M1) : établie dans le code, pas sur le runner** :
   - (a) les workflows STAGING construisent l'app de simulateur avec `CODE_SIGNING_ALLOWED=NO`
     (`ios-swift-lot5-staging.yml`, `ios-swift-staging.yml`) : seule la signature ad hoc de l'éditeur de liens, sans
     entitlement ni `application-identifier` ;
   - (b) dans ce cas, le trousseau du simulateur refuse l'écriture. Sonde du 25/11 : `SecItemAdd` rend -34018
     (`errSecMissingEntitlement`) pour un binaire signé ad hoc sans entitlement, sur le simulateur iOS 18.6 ;
   - (c) `KeychainSessionStorage.store` lève l'erreur, mais supabase-swift 2.55.5 se contente de la journaliser
     (`Sources/Auth/Internal/SessionStorage.swift`, `store`) et le SDK ne garde la session nulle part ailleurs : `session()`
     et `currentSession` relisent le stockage ;
   - (d) `SupabaseAuthGateway.signIn` renvoyait l'utilisateur de la réponse sans vérifier que la session avait été
     enregistrée ;
   - (e) à chaque requête, `adaptRequest` (`Sources/Supabase/SupabaseClient.swift`) fait `try?` sur `auth.session`.
     Faute de session, il garde l'en-tête par défaut `Authorization: Bearer <clé publishable>` : PostgREST exécute
     alors la requête sous le rôle `anon` ;
   - (f) les fonctions de session ne sont pas exécutables par `anon` (lecture de production du 25/11 ; le STAGING
     provient du même dump). Le refus 42501 ou 401 est traduit en `.unauthorized` (`SupabaseErrorMapping`) ;
   - (g) `fn_get_my_role` échoue de la même façon, mais l'échec est masqué par le repli sur le rôle signé.
   La fixture passe parce qu'elle envoie explicitement le JWT d'E1. Le mécanisme (c)→(e) est reproduit par
   `StockageSessionRefuseTests.testSansSessionStockeeLeSDKEnvoieLaClePublishable`.

   **Prouvé** :
   - le mécanisme du SDK (c)→(e), lu dans les sources 2.55.5 et reproduit par le vrai client sur un double du
     trousseau qui refuse l'écriture ;
   - les builds de recette sont construits avec `CODE_SIGNING_ALLOWED=NO` ;
   - le symptôme est cohérent avec une requête partie sous `anon`.

   **Non prouvé** : le refus effectif du trousseau sur le runner (Xcode 26.4.1, simulateur iOS 26, app lancée par
   XCUITest). La sonde locale portait sur un simulateur iOS 18.6, avec un binaire nu lancé par `simctl spawn`, et sa
   contre-épreuve (un binaire porteur d'un `application-identifier`) n'a pas pu être lancée.

   **Historique CI** :
   - `ios-swift-staging.yml` n'a jamais été exécuté ;
   - `native-auth-staging.yml` a été exécuté une fois et s'est arrêté avant les tests UI ;
   - aucun parcours XCUITest authentifié n'a encore réussi en CI.

   La cause n'est donc ni contredite ni confirmée par la CI. Le parcours n° 4 tranchera grâce à la ligne de stockage
   (point 5).
3. **Production** : une app TestFlight ou App Store est signée avec son profil, qui porte l'`application-identifier`,
   et le trousseau accepte la session. C'est le cas des builds 25 à 31, où des soignants se connectent et lisent leurs
   données. Un compte établissement passe par le même client, le même stockage et le même transport. La cause (a) est
   donc propre aux builds de simulateur non signés. En production subsiste un risque résiduel : tout refus d'écriture
   du trousseau produirait le même faux « session expirée ». Il est désormais refusé dès la connexion (point 4).
4. **Correctifs** :
   - connexion refusée nommément quand la session n'est pas relue après `signIn` (message propre, `detail`
     `session-non-enregistree`, diagnostic `connexion:unknown:session-non-enregistree`), en DEBUG comme en Release ;
   - en build DEBUG et en mode `staging` seulement, si la sonde du trousseau échoue, session gardée en mémoire du
     processus (`SupabaseGateways.stockageSession`). Rien ne survit à l'arrêt de l'app ; jamais en Release ni en
     production. Conséquence : le critère « restauration après arrêt » de `StagingConnexionTests` (PORTE_LOT0 1.1) ne
     peut pas être prouvé par un build non signé. Il demande un build de simulateur signé, ce qui reste à décider ;
   - diagnostic DEBUG d'un refus « non autorisé » des lectures de session : code brut (`postgrest=<code>` ou
     `http=<statut>` ; le SDK n'expose pas le statut d'une erreur PostgREST décodée), `jwt=oui|non`, secondes avant
     `exp`, hôte émetteur du jeton égal à l'hôte REST. Ni jeton ni adresse ;
   - pré-vol : témoin non bloquant, la lecture de `fn_mes_permissions_etab` rejouée avec les en-têtes de l'app sans
     session (clé publishable en `apikey` et en `Authorization`). Un refus confirme le mécanisme côté STAGING, une
     acceptation le dément. Les autres en-têtes (`X-Client-Info`, en-têtes du SDK) ne changent pas le rôle PostgREST.
5. **Revue fraîche de #1191** :
   - **M1, traité** : le choix du stockage est observable en DEBUG.
     - Forme : `stockage=memoire;sonde=<OSStatus>` (staging, trousseau refusé), `stockage=trousseau;sonde=ok`
       (staging, trousseau accepté) ou `stockage=trousseau;sonde=non-lancee` (autres modes, aucune écriture témoin).
     - Journal DEBUG au démarrage du client : `Jolene diagnostic stockage-session : <forme>`.
     - Diagnostic de session : la forme suit chaque diagnostic d'échec, après « | ».
     - Écran de connexion : valeur d'accessibilité de `login-scroll`. Le XCUITest STAGING la relit avant la connexion
       et l'écrit en une ligne au même préfixe, publiée par le filtre du journal du job (`ios-swift-lot5-staging.yml`),
       que la connexion réussisse ou échoue.
     - Rien en Release. Garde Node : même préfixe dans l'app, le XCUITest et les deux filtres du workflow.
   - **m2, traité** : `codeBrut` garde le message serveur, masqué (`DiagnosticServeur`), à côté du code
     (`;message=…`, placé en dernier par `DiagnosticTransport`). Toutes les erreurs RPC passent par le même point :
     limiter `codeBrut` aux lectures de session aurait demandé de dupliquer `executer`. Garder le message rend aux
     autres diagnostics DEBUG ce qu'ils montraient avant.
   - **m3, traité** : le témoin lit le corps d'une réponse 2xx. Il n'est « ACCEPTÉE » que si le corps ouvre un
     périmètre, comme l'app le lirait. Une erreur sans statut HTTP (réseau, délai) est dite sans conclusion, jamais
     « refus attendu du rôle anon ».
   - **Suivis ouverts, hors périmètre, aucun texte affiché modifié** :
     - m1 : les autres entrées de session (`verifyOTP`, `setSession` et `exchangeCodeForSession` de
       `SupabaseInscriptionGateway`, ré-authentification de `SupabaseMotDePasseGateway`, rafraîchissement) gardent la
       dégradation silencieuse vers `anon` si l'écriture du trousseau échoue. Elles sont à verrouiller comme `signIn`
       (principe « un gap connu reste verrouillé ») ;
     - m4 : le refus « Impossible d'enregistrer votre session sur cet appareil. Réessayez. » n'offre que « Réessayez »,
       sans renvoi vers le support ni vers jolene.app. L'issue est à décider avec le texte.

## En attente de Gabrielle

Reprise du §6 de `LOT5_PLAN.md` (« Ce qui exige Gabrielle ») ; rien de ce qui suit n'est implémenté sans son accord.

1. **Go B9 de T8** (validation, lot, contestation, clôture rétroactive : libération ou blocage d'escrow) au moment du
   merge, après revue fraîche CLÔTURABLE.
2. **Go B9 de T13** : secrets STAGING (Management API, service_role) exposés à `native-staging-auth`, création et
   suppression des données de la cohorte D5 ; dispatch manuel sur `main`. Workflow prêt (`ios-swift-lot5-staging.yml`, section T13) ;
   l'environnement n'impose aucune approbation (section T13, point 7).
3. **B5b** (facultative, B9 SECURITY DEFINER) : accord ou refus explicite (visibilité du code de pointage, des
   finances et des identifiants Stripe par permission ; refus d'une heure de fin future ; refus de contester une
   présence validée).
4. **Validations HARD STOP n°4** (écran, captures et texte source dans la PR), hors textes de la liste validée.
   Précisé le 25/11/2026 (revue de #1183, m5) : la validation du 24/11 porte sur des **textes** ; elle ne tranche ni les
   choix de périmètre ci-dessous, ni le seul texte affiché qui n'y figure pas. Restent donc, à soumettre à la fondatrice
   avant l'ouverture en production (T14), visibles en STAGING depuis T13 :
   - **choix sans texte nouveau** (règles exposées à l'utilisateur) : publication native limitée au salariat (T9,
     restriction d'un mode d'exercice ; les autres types passent par le renvoi « Autres options » / « Cette option se
     configure sur jolene.app. », textes du groupe E) ; absence de la case « cadre étudiant » et renvoi web neutre de
     l'acceptation (T6, « Accepter sur jolene.app ») ; absence native de l'alerte de requalification en CDI (D27) et
     des statuts d'internat (D10, D25) ;
   - **un texte affiché hors de la liste validée** : « Taux horaire brut * (€/h) »
     (`ios-native/Packages/JoleneCore/Sources/JoleneCore/Etablissement/Publication/PublicationPresentation.swift`
     l.44, source `src/components/FormulaireMission.tsx` l.917), libellé du champ de rémunération de l'écran de
     publication (salarié : « brut » qualifie la rémunération du contrat de travail) ; repris mot pour mot du web,
     mais absent des groupes A à E ;
   - tout texte ajouté après la liste.
   **Textes validés le 24/11/2026** (plus en attente) : la liste de la revue B8 du tour 2 (section 6, groupes A à E),
   validée explicitement par la fondatrice (« Oui, je valide », point 1 de l'intégration de la vague D) : statut et
   rappel DPAE de l'écran contrat, avis du plancher du taux, renvoi « Contester cette présence », mention de signature
   OTP art. 1366-1367 (T10), les trois blocs du point 1 et les titres de renvoi web de T9 (dont « libéral / tous
   contrats », précision T9 n°13). Hors validation : les promesses du groupe D toujours affichées par le site (suivi
   web à part) et l'ouverture de l'espace établissement hors démo (PR dédiée : STAGING ouvert par T13, production
   par T14).
5. **STAGING** : numéro de recette SMS pour `etablissements.telephone_contact` (preuve OTP établissement facultative
   de T10) ; confirmation qu'aucun abonnement SMS/e-mail réel n'existe sur les comptes de recette ; valeur de
   `parametres_systeme.inscriptions_publiques_actives`.
6. **Appareils** : iPhone et iPad physiques avec TestFlight (même build), second iPhone avec l'app soignant pour
   scanner le QR plein écran ; accès en lecture à un compte établissement legacy réel pour vérifier en production que
   `fn_mes_permissions_etab` le confirme, sans aucune écriture.
7. **Signature** de `PARITE_ETABLISSEMENT.md` (47 lignes) et de `PORTE_LOT5.md`.
8. **Lots amont** : lots 2 (OTP, synthèse de présence, pointage STAGING) et 4 (messagerie) mergés avant T10, T11 et
   T13.
9. **Critère de sortie réécrit** (D4, D5) : « QR du code rotatif décodé = `code_pointage_actif` relu » au lieu du QR
   de `fn_generer_qr_mission` ; consigné dans `PORTE_LOT5.md` seulement avec son accord explicite.
10. **Périmètre d'acceptation (D25)** : acceptation native limitée aux missions `SALARIE` hors `MEDECIN` ; refusé,
    T6 passe en B9 (escrow).

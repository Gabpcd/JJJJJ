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

## En attente de Gabrielle

Reprise du §6 de `LOT5_PLAN.md` (« Ce qui exige Gabrielle ») ; rien de ce qui suit n'est implémenté sans son accord.

1. **Go B9 de T8** (validation, lot, contestation, clôture rétroactive : libération ou blocage d'escrow) au moment du
   merge, après revue fraîche CLÔTURABLE.
2. **Go B9 de T13** : secrets STAGING (Management API, service_role) exposés à `native-staging-auth`, création et
   suppression des données de la cohorte D5 ; dispatch manuel sur `main`.
3. **B5b** (facultative, B9 SECURITY DEFINER) : accord ou refus explicite (visibilité du code de pointage, des
   finances et des identifiants Stripe par permission ; refus d'une heure de fin future ; refus de contester une
   présence validée).
4. **Validations HARD STOP n°4** (écran, captures et texte source dans la PR) : mention CGV art. 8 (T6) ; absence
   de case « cadre étudiant » et renvoi web (T6) ; publication native limitée au salariat et texte du renvoi
   « libéral / tous contrats » (T9) ; titre de suspension de publication (T4) ; écran de signature OTP établissement
   avec la mention art. 1366-1367 (T10) ; description verbatim de l'option « Salarié » au récapitulatif (T9) ;
   absence native de l'alerte de requalification (D27) et des statuts d'internat (D10, D25).
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

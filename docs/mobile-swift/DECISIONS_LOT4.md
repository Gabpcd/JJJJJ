# Décisions du lot 4 — application iOS Swift native

> Tranchées le 2 novembre 2026 sur mandat de Gabrielle (« finis et prends les décisions seul », « je suis tous
> tes conseils »), selon la règle générale des décisions des lots 2 à 5 du même jour, transcrite ci-dessous :
> **toutes les recommandations fermes du §7 de `docs/mobile-swift/LOT4_PLAN.md` sont adoptées telles
> quelles.** Ce mémo prime sur les questions ouvertes du blueprint et fait foi pour les tranches du lot 4 ;
> ni `docs/PLAN_APP_NATIVE_SWIFT.md` ni le blueprint ne sont réécrits. Les renvois « lot 1 décision n » se
> lisent dans `docs/mobile-swift/LOT1_PLAN.md` §7 « Décisions (02/11/2026) ».

## Règles générales (décisions des lots 2 à 5, 2 novembre 2026)

1. **Adoption du §7** : chaque recommandation ferme du §7 du blueprint est adoptée ; les critères du plan
   amendés par ces décisions sont consignés ici, avec renvoi au blueprint.
2. **HARD STOP n°4 (juridique exposé à l'utilisateur)** : l'app n'affiche que des textes **verbatim** du web
   ou du serveur, chacun relié à sa source (fichier:ligne) et gardé par un test. Aucune reformulation, aucun
   texte juridique nouveau, aucun changement de délai ou de règle juridique côté serveur. Les décisions
   juridiques que le blueprint renvoie à Gabrielle ne sont **pas implémentées** : elles figurent sous
   « En attente de Gabrielle ».
3. **B9** (paiements, migrations destructives, RLS/auth/GRANT/SECURITY DEFINER, légal, données prod) : la PR
   est préparée et poussée (branche et corps de PR prêts, tests compris) mais **jamais mergée** sans le go
   explicite de Gabrielle. Au lot 4 : **B1** (`fn_obtenir_missions_swipe` qui renvoie `score = NULL`,
   redéfinition d'une fonction SECURITY DEFINER depuis la définition LIVE) et le **dispatch STAGING de T14**.
4. **Aucune écriture** en production ni sur STAGING par les agents. Lecture seule en production autorisée
   uniquement pour relire une définition live (`pg_get_functiondef`, `pg_get_constraintdef`,
   `list_migrations`) dans les PR backend.
5. **Merges** sur `main` : sériels, CI verte et revue fraîche B8 clôturable, par la file de merge de la
   session principale.
6. **Branche d'intégration** `feat/ios-lot4`, créée depuis `origin/feat/ios-lot1`, qui reprend `main` puis
   `feat/ios-lot1` par merge (jamais de rebase ni de force-push) ; aucune PR ouverte sur elle avant la fin
   du lot 1 (chaque PR lance la recette Playwright sur la base partagée).
7. **D-FLAGS** : une seule migration non B9 pose tous les drapeaux d'écran des lots 2, 4 et 5
   (`INSERT … ON CONFLICT (cle) DO NOTHING`, modèle B0 `20261102150000`), B0-bis du lot 4 compris.
8. **W0 (lot 4) et W1 (lot 2)** : une seule PR web d'extraction de règles pures, comportement inchangé,
   tests vitest et recette frontend (dump texte avant/après) exigée par `CLAUDE.md`.

## Décisions §7 (02/11/2026)

Numérotation du §7 du blueprint ; chaque ligne reprend la recommandation, suivie des précisions apportées par
les règles générales.

1. **D1 — Extension de `Gateways`** : Adoptée. Treize champs `public var` additifs dans le corps de `Gateways`, sans troisième init, câblés par une fabrique par domaine et par monde depuis un unique `cabler` (T1) ; les treize noms s'ajoutent à `unwiredPorts`, liste attendue `DemoWorldTests.portsEnAttenteLot4`, vidée tranche par tranche ; `unwiredPorts.isEmpty` en T15.
2. **D2 — `ActionPlanning`** : Adoptée. `.swipeLike = "SWIPE_LIKE"` et `.urgence = "URGENCE"` ajoutés à l'enum du lot 1, `Lot1PortsTests.swift` mis à jour volontairement (T1).
3. **D3 — Super-like, streaks, badges** : Adoptée. Aucune interface native ; effets serveur prouvés en SQL (`badges_soignant`, `streaks_soignant`) ; compteur « Nᵉ candidature aujourd'hui » non porté.
4. **D4 — Retrait après ❤️** : Adoptée. Toast de 5 s « Annuler » → `fn_retirer_candidature`, carte **non** remise dans le paquet, message « Candidature retirée » et accès au détail.
5. **D5 — Score « 0/100 »** : Adoptée. Valeur serveur affichée (`Int?`) ; **B1 est B9** : PR préparée et poussée, jamais mergée sans le go explicite de Gabrielle ; non bloquante pour les tranches iOS.
6. **D6 — Quiz de préférences** : Adoptée. Porté au premier contact (aucun swipe en base), une fois par userId.
7. **D7 — Portée Realtime** : Adoptée. `messages_chat` (liste et fil), `typing_status` et `presence_status` fil ouvert seulement, battement de 30 s fil visible seulement, rien en arrière-plan, aucun abonnement `conversations`.
8. **D8 — Messagerie soignant** : Adoptée. Pas de création libre de conversation (parité), blocage et signalement inclus (Apple 1.2), envoi sans renvoi automatique (« envoi non confirmé » puis relecture).
9. **D9 — Litiges** : Adoptée. Natif = liste, fil, ouverture `AUTRE` par la signature à 3 arguments ; accords amiables et litiges typés sur facture en renvoi web (gel et dégel de facture, wording de clôture).
10. **D10 — Contestation de score** : Adoptée. Native **sans** justificatif (données de santé, garde-fou 8) ; sous-ligne « justificatif : renvoi web assumé ».
11. **D11 — Évaluations** : Adoptée. Lecture et signalement, pas d'édition (chemin mort du web).
12. **D12 — Bulletins** : Adoptée. Copies officielles natives (intégrité SHA-256, partage, signalement) ; simulations de paie en renvoi web ; preuve STAGING des copies non exigée au lot 4 (démo et tests de gateway).
13. **D13 — Pool urgence** : Adoptée. Natif complet, consentement verbatim (relecture HARD STOP n°4), `choixRequis` → détail de la mission.
14. **D14 — Parrainage** : Adoptée. Natif, capture `?ref=` / `?parrain=` sur 30 jours, application après authentification, montants serveur, bloc de conditions isolé en T6-HS (HARD STOP n°4, en attente), message serveur de succès jamais affiché.
15. **D15 — Statuts de §1.3** : Adoptée. Statuts proposés consignés dans `PARITE_SOIGNANT.md`, section « Lot 4 — statuts proposés », marqués « proposé — à signer » ; statués avec preuve en T15.
16. **D16 — Onze parcours cœur** : Adoptée. (1) connexion, session et reset, (2) tableau de bord, (3) Explorer, détail et candidature, (4) Mes missions (annulation, confirmation de présence), (5) pointage, (6) documents, (7) contrats et signature OTP, (8) revenus, (9) profil et compte (suppression comprise), (10) notifications push, (11) messagerie ; liste consignée dans `PARITE_SOIGNANT.md`, validée formellement par la signature de la matrice (en attente, point 9).
17. **D17 — WebView bornée** : Adoptée. Reportée hors lot 4 (branche « embarquée » du bootstrap d'auth web = B9 auth) ; renvois par `SFSafariViewController` sans transmission de jeton ; réexamen après la bascule (lot 6) avec PR web dédiée, projet Playwright « embarqué » et go de Gabrielle. La décision 3 du lot 0 est amendée en conséquence pour le lot 4.
18. **D18 — Drapeaux lot 4** : Adoptée, **13 clés** : `ios_natif_swipe_actif`, `ios_natif_recherches_actif`, `ios_natif_disponibilites_actif`, `ios_natif_parrainage_actif`, `ios_natif_litiges_actif`, `ios_natif_reclamations_actif`, `ios_natif_messagerie_actif`, `ios_natif_bulletins_actif`, `ios_natif_evaluations_actif`, `ios_natif_score_actif`, `ios_natif_pool_urgence_actif`, `ios_natif_exclusions_actif`, `ios_natif_serie_actif` ; défaut fail-open, catégorie `OPERATIONS`, sans GRANT `anon`, posées par la migration unique D-FLAGS (voir « Précisions », n°1).
19. **D19 — CI UI** : Adoptée. Matrice par format inchangée, un seul `build-for-testing` par format, deux étapes `test-without-building` (`coeur` seuil `total ≥ 100`, `secondaires` seuil `total ≥ 30`), chacune bornée à 15 min avec son gate ; matrice `format × groupe` seulement si le timeout de job de 60 min est dépassé.
20. **D20 — Preuves STAGING** : Adoptée. Obligatoires : Realtime bidirectionnel (app et pair établissement) et litige ouvert puis relu ; recommandées dans le même run : `LIKE` et effets serveur, favori, double-aveugle N1 / N2, disponibilité ; fixture D4 distincte de D3. Le dispatch de T14 est B9 (secrets STAGING, données de test) : go explicite de Gabrielle (en attente, point 2).
21. **D21 — Mesure crash-free** : Adoptée. 14 jours sur le build TestFlight externe qui contient T3b à T13, release Sentry exacte, au moins 400 sessions ; en dessous, critère « non mesurable », lot non clos ; un correctif de crash redémarre la fenêtre.
22. **D22 — Gestes XCUITest** : Adoptée. Boutons et actions d'accessibilité pour la couverture, un seul test de geste réel vérifié par le compteur `swipe-restantes`.
23. **D23 — W0** : Adoptée. Extraction de `raisonsScore`, du filtre du paquet et de la partie pure de `statutLitige.ts` vers `src/lib/`, comportement web inchangé, dans la PR web commune avec W1 du lot 2 (règle générale 8).
24. **D24 — Ton et textes** : Adoptée. Vouvoiement sobre pour les seuls textes natifs nouveaux et non juridiques (libellés de refus techniques, écran de renvoi) ; textes juridiques ou d'engagement verbatim du web ; messages serveur verbatim (lot 1 décision 9).
25. **D25 — Détail de mission, actions lot 4** : Adoptée. « Écrire à l'établissement » (`fn_user_id_pour_etablissement` → `fn_obtenir_conversation`), « Signaler » et « Ne plus travailler ensemble » (`fn_exclure_utilisateur`) portés, mêmes statuts et textes que le web, insérés une fois par T1c, implémentés par T7b et T11.
26. **D26 — Quiz : question « dispo urgence »** : Adoptée. Non portée (écriture directe de `soignants.disponible_urgence`), lien vers l'écran Pool urgence à la place ; correctif web proposé hors lot.
27. **D27 — Briques communes avec le lot 3** : Adoptée. `EdgeResponse`, surcharge `exceptionsMetier:` de `RPCResponse`, `ExternalFlowPresenter`, route `.inscription` et `DeepLinkIntent` des onglets Revenus : une seule implémentation, propriété du lot 3, étendue sans duplication ; le premier lot qui les livre le fait sous les noms et signatures de `LOT3_PLAN.md`.

## Précisions apportées par les règles générales et par le T0

1. **Nombre de drapeaux (D18 et D-FLAGS) : aucun écart.** Les décisions des lots 2 à 5 (D-FLAGS) citent
   « lot 4 B0-bis (13 clés, blueprint v2) », comme D18 : `ios_natif_exclusions_actif` et `ios_natif_serie_actif`
   comprises, sans lesquelles deux écrans natifs du lot 4 ne pourraient pas être coupés (décision 9 du lot 0).
   Critère amendé de B0-bis, porté sur les seules clés du lot 4 (le « `cle LIKE 'ios_natif_%'` = 18 » du
   blueprint compterait aussi les drapeaux des lots 2 et 5 posés par la même migration), sur STAGING puis en
   production après la migration D-FLAGS :
   `SELECT count(*) FROM parametres_systeme WHERE cle IN ('ios_natif_swipe_actif', 'ios_natif_recherches_actif',
   'ios_natif_disponibilites_actif', 'ios_natif_parrainage_actif', 'ios_natif_litiges_actif',
   'ios_natif_reclamations_actif', 'ios_natif_messagerie_actif', 'ios_natif_bulletins_actif',
   'ios_natif_evaluations_actif', 'ios_natif_score_actif', 'ios_natif_pool_urgence_actif',
   'ios_natif_exclusions_actif', 'ios_natif_serie_actif')` = **13**.
   Total global, pour information : `cle LIKE 'ios_natif_%'` = **28** (5 du lot 1 posés par B0, 3 du lot 2
   `ios_natif_{presences,documents,contrats}_actif`, 13 du lot 4, 7 du lot 5 `ios_natif_etab_*` dont
   `ios_natif_etab_pointage_actif`) ; ce total relève des décisions du lot 5 (`LOT5_PLAN.md` v2 D14,
   `DECISIONS_LOT5.md` amendement 9, `origin/lot5/l5-t0`) et de la garde de la migration D-FLAGS, pas du lot 4.
   Hors périmètre du T0 (aucune migration ici) : la branche D-FLAGS `origin/feat/drapeaux-ios-natif-lots-2-4-5`
   ne posait que 20 clés à `3542f7b2` (sans `exclusions`, `serie` ni `etab_pointage`) ; relue à `7aa3a1db`
   (2 novembre, 23 h 06), elle en pose 23 (28 avec B0, garde `src/lib/__tests__/drapeauxIosNatifMigration.test.ts`) ;
   à revérifier contre les 13 clés ci-dessus à son merge.
2. **Exceptions `42501` métier** : le dump en compte six dans les RPC du lot 4, pas trois — `Accès refusé`,
   `Conversation non autorisée`, `COPIE_ACCES_REFUSE`, plus `Non autorisé` (`fn_user_id_pour_etablissement`),
   `NON_AUTORISE` (`fn_typing_start`) et `Compte inactif` (`fn_interlocuteurs_conversations`). La liste
   d'interception de T1 est celle de `CONTRATS_RPC_SOIGNANT.md`, « Lot 4 — lecture des exceptions », gardée
   par le test node (tout `42501` d'un corps du lot 4 doit y figurer).
3. **Codes edge** absents du §2.4 du blueprint et consignés dans les fiches : `copies-bulletins` 405
   `METHODE_INTERDITE`, 409 `COPIE_RESERVATION_EXPIREE` / `COPIE_VERSION_CONFLIT` / `COPIE_MISSIONS_INVALIDES`
   (propres à `finaliser`) ; `messagerie-validate` 413 avec la clé `max`, 403 qui relaie toute erreur métier.
4. **`fn_enregistrer_swipe`** renvoie aussi deux messages rédigés (`'Vous avez déjà candidaté à cette mission'`,
   refus documentaire libéral avec `documents_requis_pour`) en plus des codes techniques : verbatim, hors table
   `SwipeRefus`.
5. **`fn_definir_disponibilite`** admet aussi `MATIN` et `APRES_MIDI` ; l'app n'envoie que `JOURNEE` et `NUIT`
   (parité web).
6. **`types: null`** pour dix RPC du lot 4, dont `fn_ouvrir_litige_rate_limited`, déclarée dans `types.ts` en
   union de surcharges que l'extracteur ne lit pas (précédent du lot 1 accepté).
7. **Garde-fous 18 et 19** (`tests/non-regression/guards.sh`) : motifs en variables (`MOTIF_NOTATIONS`,
   `MOTIF_ENVOI`) relus par le test node ; le garde-fou 19 vise `fn_envoyer_message` et
   `fn_envoyer_message_valide` (le formulaire d'aide `fn_envoyer_message_contact` n'est pas un envoi de
   messagerie) ; les deux excluent les dossiers `.build` locaux.
8. **Relevé Realtime STAGING** prévu par T0 « si l'accès Management API du lot 1 T11 est ouvert » : non fait,
   l'accès n'étant pas ouvert à la tranche ; il rejoint le relevé de production (en attente, point 6).
9. **`LOT1_DECISIONS.md`** n'est pas versionné en double : ses décisions 1 à 19 sont celles de
   `LOT1_PLAN.md` §7, même numérotation.
10. **RPC partagée avec le lot 2 : `fn_ouvrir_litige_rate_limited`** (écart aux deux blueprints).
   `LOT4_PLAN.md` §3 T0 la range parmi les « 42 RPC en `a_venir`, `lot: 4` » ; `LOT2_PLAN.md` v2 §3 T0 (l.292,
   branche `origin/lot2/l2-t0`) la fait suivre par le T0 du lot 2 en `lot: 2` (surcharge à 3 arguments,
   `DESACCORD_HEURES_POINTAGE`, T5b), avec sa fiche `## fn_ouvrir_litige_rate_limited`. Deux entrées
   casseraient « noms uniques » de `RPC_SUIVIES`, et deux fiches feraient lire la première à `section()`.
   Retenu, sur le précédent du T0 du lot 5 (« une RPC déjà suivie par un lot antérieur garde son entrée et son
   lot ») : le lot 4 suit **41** RPC propres en `lot: 4` ; la 42e figure dans `RPC_PARTAGEES_LOT4`
   (`scripts/mobile/check-rpc-contracts.mjs`), qui ne l'ajoute en `a_venir`, `lot: 4` qu'en l'absence de
   l'entrée d'un lot antérieur. La garde admet pour elle `lot ≤ 4` et `a_venir` ou `consommee` (passage en
   `consommee` par la tranche T5b du lot 2, ou par T15 du lot 4 si l'entrée est la sienne). Fiche unique :
   l'usage du lot 4 (type `AUTRE`, refus inatteignables avec `AUTRE`) en est la sous-section « Usage du
   lot 4 ». **Fusion avec le T0 du lot 2, jamais « garder les deux côtés » pour cette fiche** : garder
   l'en-tête et les sous-fiches par surcharge du lot 2, y déplacer telle quelle la sous-section « Usage du
   lot 4 », supprimer l'en-tête provisoire du lot 4, puis `node scripts/mobile/check-rpc-contracts.mjs --update`
   (l'entrée du JSON passe en `lot: 2`) ; la garde exige un seul titre `## fn_ouvrir_litige_rate_limited`.
   `RPC_SUIVIES` se fusionne sans doublon, le bloc du lot 4 n'y écrivant plus cette RPC. Autres
   recouvrements, relevés par fusions d'essai locales (non poussées) avec `origin/lot2/l2-t0`,
   `origin/lot3/l3-t0` et `origin/lot5/l5-t0` : juxtaposition des deux côtés pour les blocs ajoutés (fin de
   `RPC_SUIVIES`, sections de `CONTRATS_RPC_SOIGNANT.md`, tests node) ; **fusion de sens**, et non « garder
   les deux côtés », pour (a) le test « tout littéral "fn_…" du Swift », réécrit par les T0 des lots 2 et 4
   (contrôle du système de pointage ① d'abord, puis `verdictLitteralSwift`), (b) le paragraphe des exclusions
   en tête de `CONTRATS_RPC_SOIGNANT.md` (version du lot 2 ou 3, plus la mention du T0 du lot 4), (c) la ligne
   « Dernière mise à jour » de `PARITE_SOIGNANT.md` avec le lot 3 (les deux mentions gardées) ;
   `ios-native/rpc-contracts.json` se régénère (`--update`) après toute fusion, jamais à la main. Ainsi
   résolues, les fusions d'essai passent : lot 2, 75 tests de `check-rpc-contracts.node.mjs`, une seule fiche,
   entrée `lot: 2` ; lot 3, 52 + 27 tests ; lot 5, seul le JSON en conflit, 52 + 20 tests.
11. **RPC reclassée en lot 4 par le lot 1 : `fn_suggestions_missions_pour_soignant`** (relevé à l'intégration
   `feat/ios-lot4`, 3 novembre). La revue B8 du T3 du lot 1 l'a sortie du lot 1 et suivie en `a_venir`,
   `lot: 4` (son seul appelant web, `src/components/dashboard/SuggestionsMissions.tsx`, n'est monté par
   aucune page ; l'Accueil natif ne la consomme pas), après l'écriture de ce T0. Elle n'est pas l'une des
   42 RPC du blueprint et aucune tranche de `LOT4_PLAN.md` ne la cite : la garde du lot 4 la tient hors
   des 41 RPC propres (`LOT4_RECLASSEES` de `tests/node/check-rpc-contracts.node.mjs`), sans fiche confrontée
   au SQL du lot 4 (sa fiche reste celle du lot 1). Son sort au lot 4, consommée par une tranche ou retirée de
   `RPC_SUIVIES`, est statué en T15 avec les autres statuts.

## Critères du plan amendés (`docs/PLAN_APP_NATIVE_SWIFT.md` §5 « Lot 4 », l.202-210)

- **Périmètre (l.204)** : « soit par Safari, soit par la WebView bornée » devient : renvois par
  `SFSafariViewController` seul, WebView bornée reportée (D17). Périmètre étendu à la série
  `/soignant/missions/serie/:id` (lot 1 décision 11) et aux routes `/soignant/score`,
  `/soignant/attestation-heures`, `/soignant/passer-en-liberal`, `/soignant/exclusions`, `/soignant/classement`
  (statuts proposés de `LOT4_PLAN.md` §1.3, D15) et aux actions du détail de mission (D25).
- **Matrice (l.207)** : « 100 % des lignes statuées » porte sur les 50 routes et leurs sous-lignes ; les onze
  parcours cœur sont ceux de D16 ; « abandonné » exige une décision écrite de Gabrielle ; signature en T15.
- **Crash-free (l.208)** : mesuré selon D21 (14 jours, release Sentry exacte, au moins 400 sessions, fenêtre
  redémarrée par tout correctif de crash).
- **STAGING (l.209)** : preuves obligatoires et recommandées de D20 ; dispatch de T14 sous go B9 de Gabrielle.
- **Bêta (l.210)** : « aucun retour bloquant ouvert » s'apprécie dans `BETA_LOT4.md`, arbitrage bloquant /
  non bloquant par Gabrielle.
- **Realtime (plan §4.1 l.106)** : pas d'abonnement `conversations` (absente de la publication versionnée,
  correction 3, D7).
- **B0-bis** : 13 clés ; critère `SELECT count(*) FROM parametres_systeme WHERE cle IN (<les 13 clés du
  lot 4>)` = 13 sur STAGING puis en production, après la migration D-FLAGS (précision 1) ; le total global
  de 28 drapeaux `ios_natif_%` renvoie aux décisions du lot 5.
- **T0 (`LOT4_PLAN.md` §3)** : 42 RPC consommées par le lot 4, dont 41 suivies en `lot: 4` et
  `fn_ouvrir_litige_rate_limited` partagée avec le lot 2 (précision 10).

## En attente de Gabrielle (blueprint §6)

1. **Prérequis lots 1 à 3** : clôture des critères du lot 3 nécessaires au lot 4 (TestFlight externe ouvert, Sentry Cocoa avec suivi de sessions, clé APNs sous `GDU5AA28M9` pour le tap des notifications de message, décision 7 du lot 0) ; statuts des lignes des lots 1 à 3 dans `PARITE_SOIGNANT.md`.
2. **Go B9** : PR **B1** (redéfinition SECURITY DEFINER de `fn_obtenir_missions_swipe`, `score = NULL`), préparée et poussée, jamais mergée sans go ; dispatch de **T14** (secrets STAGING, données de test, modèle lot 1 décision 13). B0-bis n'en relève pas (INSERT idempotent, migration D-FLAGS couverte par le mandat).
3. **HARD STOP n°4** : validation du bloc « conditions de la prime » (**T6-HS**, montants serveur, sources jointes) et décision sur la contradiction entre la promesse serveur (`fn_appliquer_parrainage` l.19115) et la page web (`PageParrainage.tsx` l.187, l.300) ; relecture, sans reformulation, des textes repris verbatim : feuille « première candidature » (T3b), consentement du pool urgence et opt-in SMS (T11), anti-fuite et blocage (T7b), signalement depuis la messagerie (T7b, surface nouvelle, textes web), mention employeur et avertissement de retrait d'une copie `DESTINATAIRE` (T10), textes « Ne plus travailler ensemble » (T11) ; promesse « +10 points de fiabilité » du pool, reprise verbatim mais incohérente avec le score v2.
4. **Décision 3 du lot 0 amendée** (report de la WebView bornée, renvois par `SFSafariViewController`) : tranchée par le mandat (D17) ; pour information, non bloquant.
5. **Onze parcours cœur** : liste tranchée par le mandat (D16) ; validation formelle à la signature de la matrice (point 9).
6. **Relevé de la publication Realtime en production**, en lecture seule (`SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime'`), hors du périmètre de lecture autorisé aux agents (règle générale 4) : à exécuter par Gabrielle ou à autoriser explicitement ; même relevé sur STAGING quand l'accès du lot 1 T11 est ouvert. Résultat à consigner dans la fiche Realtime de `CONTRATS_RPC_SOIGNANT.md`.
7. **Bêta externe** : groupes TestFlight, soumission Beta App Review, collecte des retours, arbitrage bloquant / non bloquant dans `BETA_LOT4.md` ; accès en lecture au projet Sentry pour la mesure crash-free.
8. **Appareil** : un iPhone physique, et un second téléphone pour le QR et le pair de messagerie, pour `RECETTE_DEVICE_LOT4.md`.
9. **Signature** de `PARITE_SOIGNANT.md` à 100 % (critère plan l.207, T15).
10. **Points ouverts web et backend, hors lot** (aucun n'est corrigé par le lot 4) : bouton « Éditer » mort des évaluations ; annulation « réversible à l'infini » du swipe, fausse ; abonnement web aux INSERT `conversations` sans effet ; `LIMIT` sans effet de `fn_lister_notations_recues` (appliqué après `jsonb_agg`) ; codes techniques bruts affichés par le web ; liste des événements de score jamais affichée par le web (clé `events` lue `evenements`) ; quiz web qui active le pool urgence par `UPDATE soignants` direct, sans contrôle documentaire ni consentement ; défauts de prime de parrainage divergents (50 / 25) et condition « commission ≥ 4 × prime » absente du texte web ; promesse « +10 points de fiabilité » du pool alignée sur le trigger legacy `dec_bonus_urgence` et non sur le bonus du score v2.

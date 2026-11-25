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
12. **Code de parrainage d'un lien universel perdu avant T6** (revue B8 de #1159, m7 ; décision sur mandat,
   18 novembre). Un lien `https://jolene.app/inscription/soignant?ref=<code>` (ou tout lien qui porte `?ref=` ou
   `?parrain=`) ouvert alors que l'app est installée arrive dans l'app : `/inscription/soignant` y est natif depuis
   le lot 3, qui ne lit pas le code. Le crochet posé par L4-T1c (`ParrainageApplicateur.capturer(depuis:)`, appelé
   par `DeepLinkCoordinator` sur tout lien) ne capture rien tant que T6 n'a pas livré `ParrainageCapture`
   (`VerrousLot4.codeParrainageACapturer` rend `nil`, figé par `SecondairesLot4Tests` et la garde node m6) : le
   code est donc ignoré, comme avant T1c. **Décision : écart consigné, pas de renvoi web.** Renvoyer vers le web
   tout lien qui porte un code changerait le parcours d'inscription natif du lot 3 (création du compte sur le web,
   reconnexion dans l'app) pour couvrir un manque que T6 ferme ; la tranche parallèle T6 lève l'écart. Le filleul
   n'est pas bloqué : il s'inscrit, et le parrainage ne lui est pas rattaché. Ce cas reste à vérifier sur appareil
   en T15 (`RECETTE_DEVICE_LOT4.md`, lien ouvert depuis Messages et WhatsApp), après T6.
13. **T12 — détail de série : quatorzième port, écarts assumés, constat sur la route web** (L4-T12, 24 novembre ;
   décision sur mandat).
   - **Port `serie`.** Le blueprint §2.2 compte treize ports et aucun ne lit les missions d'une série. T12 ajoute un
     quatorzième champ additif, `Gateways.serie` (`Ports/SeriePort.swift`, stub `UnwiredSeriePort`), câblé dans les
     deux mondes par sa fabrique dans la même PR : il n'entre jamais dans `portsEnAttenteLot4`. L'acceptation passe
     par ce port (`accepter`), qui rend l'issue du lot 1 (`CandidatureOutcome`) : le monde Supabase délègue à
     `CandidaturePort.confirmer(action: .accepter)` (RPC, relecture, audit du lot 1, aucun code dupliqué) ; le monde
     démo rejoue d'abord les réponses scriptées de `demo-serie.json`, au format du serveur.
   - **Conformité (décision 2 du lot 1).** Le bloc « Vérification de compatibilité » du web
     (`DetailSerieSoignant.tsx` l.376-428 : repos et durées calculés côté client, articles de loi) et la modale
     d'explication d'un article ne sont pas portés ; aucune règle de durée du travail n'est écrite en Swift. Une
     mission n'est « en conflit » pour la sélection que si le serveur vient de la refuser par un refus structuré
     (`code`) ou par l'exception d'un trigger ; ce refus s'affiche tel que servi.
   - **Arrêts de la boucle.** Comme le web, arrêt sur le refus `[CODE DU TRAVAIL]`. En plus du web (qui poursuit) :
     arrêt sur une session expirée et sur une réponse perdue (délai, réseau, relecture), l'état du serveur étant
     alors inconnu ; la série est relue et une mission relue attribuée au soignant est rangée acceptée, jamais
     renvoyée (PRINCIPES §4).
   - **Audit.** Un `MISSION_ASSIGNATION` par mission acceptée, écrit par la gateway de candidature du lot 1 avec ses
     détails (`intitule`, `etablissement`, `debut`, `fin`) ; les détails `type: 'acceptation_serie'` et `serie_id` du
     web (l.330) ne sont pas repris (`SupabaseCandidatureGateway.swift` n'est pas modifié par une tranche du lot 4).
   - **Non portés.** Totaux par régime et leurs mentions (l.499-509 : aucun montant additionné côté client),
     redirection automatique vers les contrats (le bilan reste affiché, bouton « Voir mes contrats »), lien « Voir
     dans mon planning ».
   - **Textes.** Textes du web à leur ligne (`SerieVerbatimTests`), ceux que le web tutoie vouvoyés comme le
     récapitulatif de candidature du lot 1 (décision 9 du lot 1, D24) : « Décochez les missions en conflit pour
     continuer », « Vérifiez tous vos engagements », « Confirmez uniquement si vous pouvez assurer chacun des créneaux
     exacts sélectionnés. », « Corrigez la sélection : aucune mission en conflit ou au planning incomplet ne sera
     omise automatiquement. », « La mission "…" accepte salarié ou libéral : ouvrez son détail pour choisir votre
     mode de contrat avant d'accepter. ». Textes natifs sans équivalent web, opérationnels et non juridiques (D24), à
     relire : « Non envoyée », « L’acceptation s’est arrêtée sur ce refus. Les missions suivantes n’ont pas été
     envoyées. », « Ouvrir le détail de la mission », « Voir mes contrats », « L’acceptation de cette mission n’a pas
     pu être confirmée. Vérifiez Mes missions avant de réessayer. ». Aucun texte juridique n'est écrit en Swift : les
     refus affichés sont ceux du serveur, mot pour mot.
   - **Constat hors lot, à arbitrer par Gabrielle.** Plus rien n'écrit le marqueur `[SERIE_ID:…]` dans
     `missions.description` : la migration CP3 (`db/migrations_archive/20260416140000_cp3_migrate_data_creneaux.sql`)
     l'a retiré au profit de `missions.serie_id` et `mission_series`, et `FormulaireMission.tsx` (l.415, l.519) le
     retire encore. La page web lit toujours le marqueur (l.95) : elle affiche « Pack introuvable » pour toute
     mission créée depuis, et aucun lien du web n'y mène plus (`CarteSerie.tsx` l.68-72 exige le marqueur). L'écran
     natif, à parité de requête, rend le même résultat. Porter la lecture sur `missions.serie_id` (identifiant uuid,
     autre contrat de route) ou retirer la route est une décision web et produit, hors chantier iOS.

14. **T7a — messagerie, cœur sans écran** (décisions de tranche, 24 novembre). (a) **Ports étendus de façon
   additive**, avec une implémentation par défaut (aucun double ni stub existant à retoucher) :
   `RealtimePort.etat(conversationId:)` (état du canal d'un fil, `nil` pour la liste — sans lui, le « premier
   battement après l'abonnement du canal du fil » ne distinguerait pas le canal du fil de celui de la liste) et
   `MessageriePort.messages(conversationId:depuis:context:)` (relecture après « rejoint » bornée par
   `cree_le ≥ depuis`). (b) **Les treize RPC de la messagerie passent en `consommee` en T7a**, y compris les sept
   que le T0 rangeait en T7b (`fn_messages_non_lus`, `fn_est_bloque`, `fn_bloquer_utilisateur`,
   `fn_debloquer_utilisateur`, `fn_signaler_utilisateur`, `fn_user_id_pour_etablissement`,
   `fn_obtenir_conversation`) : le port les exige toutes et la règle est « consommée par la PR qui câble la
   gateway » ; T7b n'appelle aucune RPC de plus. (c) **Cycle Realtime inactif tant que l'écran n'est pas livré** :
   `CycleRealtime` n'ouvre aucun canal et ne lit aucun badge tant que la ligne `messagerie` de
   `DestinationLien.ecranNatifLivre` vaut `false` (T7b la passe à `true`, le cycle s'active alors sans autre
   changement), puis lit le coupe-circuit `ios_natif_messagerie_actif` avant tout canal (messagerie coupée : ni
   Realtime ni badge). Écart assumé au plan, qui activait le cycle dès T7a : aucun WebSocket ni RPC en production
   pour un écran qui n'existe pas encore, et un coupe-circuit qui coupe aussi le Realtime. (d) **Issues de l'edge
   `messagerie-validate`** : `INTERNAL_ERROR` (500) et `ENVOI_INDISPONIBLE` (503) sont « non confirmés » (issue de
   l'insertion inconnue : fil relu, aucun renvoi), `AUTORISATION_INDISPONIBLE` (503, avant toute insertion) est un
   refus ; fiche mise à jour. (e) **Aucun texte nouveau** : repli des erreurs = message générique du web déjà porté
   (`MessagesDocuments.erreurGenerique`) ; les libellés par code de refus sont repris du web par T7b. (f) **Canal
   perdu** : le SDK ne signale un canal fermé par le serveur que par son retrait du client ; la passerelle le
   contrôle toutes les 5 s et remplace aussi un canal resté désabonné 30 s. Délais non mesurés sur un serveur
   réel : à confirmer par T14 (STAGING) et par la recette sur appareil. (g) **Écarts au web assumés** : pas de
   lecture initiale de `typing_status` (l'indicateur suit le prochain changement, au plus 2 s plus tard) ; le fil
   est relu à chaque « rejoint », premier abonnement compris (le web laisse un trou entre sa lecture et
   l'abonnement).

15. **T7b — messagerie, écrans** (décisions de tranche, 24 novembre). (a) **Textes** : tous repris du web, source à
   la ligne dans `JoleneCore/Messagerie/MessagerieTextes.swift`, prouvés par `MessagerieVerbatimTests` (qui relit les
   fichiers web, ajoutés aux filtres de `ios-swift-ci.yml`) ; anti-fuite, blocage et signalement sous HARD STOP n°4,
   validés explicitement par la fondatrice le 24/11/2026 (groupe C de la liste, précision 21). Deux libellés sans équivalent web, non contractuels : « Écrire à l'établissement » (D25 ; le web
   incruste le fil dans le détail) et « Envoi non confirmé » (mention déjà portée par `ChatBubble`, T1b). (b)
   **Signalement depuis le fil** : le fil web ne propose que le blocage ; le natif y ajoute « Signaler » (composant et
   textes du web, cible de l'établissement et mission) pour l'exigence Apple 1.2, comme le plan. (c) **Refus d'envoi** :
   libellés par code du web (`InputMessage.tsx` l.110-124), message serveur jamais affiché, comme le web. (d) **Repli
   « Autres actions »** du détail d'une mission ouverte non assignée posé dans `ActionsEtablissementMission` (partagé avec
   T11), commun aux deux boutons. (e) **Écarts au web assumés** : navigation empilée liste → fil sur tous les formats (pas
   de vue scindée sur iPad) ; avatars par initiales, sans image distante ; ouverture « Écrire à l'établissement »
   refusée → « Impossible d'ouvrir la conversation. » quel que soit le refus serveur, comme le web.
16. **Score (T9) : phrase d'engagement « sous 72h » non affichée** (intégration de la vague D, 24/11/2026 ; décision
   prise par Claude sur délégation de Gabrielle du 24/11/2026 (« t'as mon go pour tout faire et tout merger meme
   paiements etc », « comme tu veux, tu es maitre prends tes décisions »)). « Les événements contestables peuvent être
   soumis à un admin Jolene qui décidera MAINTENIR / RÉDUIRE / ANNULER la pénalité sous 72h. » (`PageScoreSoignant.tsx`
   l.223, `SectionEvenementsScore.tsx` l.121) : l'écran natif ne l'affiche plus (`ScoreScreen`, identifiant
   `score-evenements-delai` retiré), la constante `ScoreTextes.decisionSous72h` et son épinglage verbatim
   (`EvaluationsScoreVerbatimTests`) sont retirés. Aucun autre texte de l'écran ne change. **Motif corrigé** (revue B8
   des textes de la vague D, M2) : le motif initial, « montrée à aucun soignant par le web », était faux. Il est vrai
   sur `/soignant/score` (clé `evenements` lue, `events` servie), mais le profil du soignant monte
   `SectionEvenementsScore` (`ProfilSoignant.tsx` l.381-385), qui lit `events` et affiche la phrase dès qu'un
   événement existe. Le retrait natif est maintenu **par prudence** : aucun mécanisme serveur ne garantit ce délai
   (`supabase/schema/public.sql` au 24/11/2026 : `reclamations_score` n'a ni échéance ni décision automatique ; seule
   `fn_alerte_reclamations_pending_old` alerte les admins sur une réclamation `PENDING` depuis plus de 14 jours).
   **Retrait natif validé explicitement par la fondatrice le 24/11/2026 (« Oui, je valide », liste des textes de la revue B8 du tour 2, section 6 ; référence au point 1 de l'intégration de la vague D de `DECISIONS_LOT5.md`)** (groupe D). La validation ne couvre pas le site : la phrase y reste affichée et l'app
   et le web promettent donc des choses différentes au même soignant ; retrait ou garantie du 72 h sur le web
   (`SectionEvenementsScore.tsx` l.121, `PageScoreSoignant.tsx` l.223, `MesReclamationsEtab.tsx` l.86) : suivi web à
   part (« En attente », point 10).
17. **Pool urgence (T11) : promesses « +10 points de fiabilité » non affichées** (intégration de la vague D, 24/11/2026 ;
   décision prise par Claude sur délégation de Gabrielle du 24/11/2026 (« t'as mon go pour tout faire et tout merger
   meme paiements etc », « comme tu veux, tu es maitre prends tes décisions »)). En production le score applique un
   bonus de 5 par mission urgence, pas de 10 (`LOT4_PLAN.md` §3 T11, écart jusqu'ici signalé et non arbitré) : l'écran
   natif n'affiche ni l'avantage « +10 points fiabilité par mission urgence terminée » (`PoolUrgenceToggle.tsx`
   l.215), ni la dernière phrase du texte d'engagement, « Chaque mission urgence terminée te rapporte +10 points de
   fiabilité. » (l.230). Le reste du texte d'engagement est affiché mot pour mot (« En activant le pool d'urgence, tu
   acceptes d'être contacté(e) pour des remplacements de dernière minute dans ton rayon. Tu restes libre de
   refuser. »), dérivé de la constante verbatim `TextesWeb.PoolUrgence.engagementDebut` par
   `PoolUrgenceTextes.engagementAffiche` (aucun texte réécrit). Les constantes `avantageFiabilite`,
   `engagementPoints`, `engagementFin` et `engagement` restent dans `TextesWeb`, non affichées, pour que la garde des
   textes suive toujours le web (raison en commentaire). Preuves : `TextesWebTests` (texte affiché exact, sans
   « points »), `DemoPoolUrgenceTests` (libellé du consentement, avantage absent). **Retrait natif et texte
   d'engagement tronqué validé explicitement par la fondatrice le 24/11/2026 (« Oui, je valide », liste des textes de la revue B8 du tour 2, section 6 ; référence au point 1 de l'intégration de la vague D de `DECISIONS_LOT5.md`)** (groupes C et D). Le web garde sa promesse, que la validation ne couvre pas : à
   corriger côté web ou côté score, suivi web à part, hors lot.
18. **Points d'entrée des écrans livrés** (intégration de la vague D, 24/11/2026 ; décision prise par Claude sur
   délégation de Gabrielle du 24/11/2026 (« t'as mon go pour tout faire et tout merger meme paiements etc », « comme tu
   veux, tu es maitre prends tes décisions »)). Revue B8 de #1159, m3, laissée à l'intégration (`LOT4_PLAN.md`,
   précision 12 « Hub ») : chaque écran livré est atteignable depuis l'interface, à l'emplacement du web quand il en a
   un. Table et garde : `EntreesHubLot4.sections()` (hub du Profil) et `EntreesHubLot4.pointsDEntreeHorsHub`,
   `SecondairesLot4Tests.testChaqueEcranLivreAUnPointDEntreeOuEstListe` (un écran livré sans point d'entrée ni
   exemption listée fait rougir le test).
   - **Hub du Profil, sections du hub web** (inchangées) : Recherches sauvegardées, Établissements exclus, Parrainage,
     Litiges & contestations (onglet Réclamations dans l'écran des litiges).
   - **Hub du Profil, entrées de la barre latérale web** (`BarreNavigation.tsx`, absente de l'app), ajoutées après les
     sections du hub web sous les titres de leurs groupes : « Missions » › « Pool urgence » (l.60) ; « Activité » ›
     « Mon score » (l.68) et « Mes évaluations ». Les évaluations reçues n'ont aucune entrée dans l'interface web
     (atteintes par lien, push ou centre) : entrée posée avec le score, libellé = titre de la page web
     (`EvaluationsSoignant.tsx` l.58).
   - **Explorer** : icône calendrier « Mes disponibilités » (`RechercheMissions.tsx` l.309-316), en tête de la rangée de
     chips sur tous les formats (`ExplorerDisponibilitesButton`, identifiant `explorer-disponibilites`) : la barre de
     navigation tient déjà la cloche de l'alerte rapide, « Mes favoris » et « Filtres » (débordement iPad relevé à
     l'intégration de la vague C). Ouvre l'écran empilé sur le Profil, comme un lien.
   - **Inchangés** : messagerie (bouton Messages de la barre de navigation, T7b), bulletins (Revenus › Paie, T10), vue
     Swipe (commande d'Explorer, T3b).
   - **Non relié** : le détail de série. Le web l'ouvre depuis la carte de série (`CarteSerie.tsx` l.66-73) des listes de
     missions (`MissionsSoignant.tsx` l.299-320, `ListeMissions.tsx`), qui regroupe les missions d'une série et affiche
     leurs montants ; Explorer et Mes missions natifs n'ont pas de regroupement par série (surfaces du lot 1). Porter la
     carte de série est une tranche à part ; d'ici là, la série reste atteinte par lien universel, tap push et centre de
     notifications (listée `nil` dans `pointsDEntreeHorsHub`).
   - **Non prouvé par XCUITest** : les XCUITest existants passent encore par les entrées qu'ils connaissaient
     (`DemoDisponibilitesTests` par lien) ; les nouvelles entrées sont prouvées par les tests JoleneCore et la
     compilation, pas par un parcours d'interface.
19. **Détail de mission : repli « Autres actions » harmonisé (T7b / T11)** (intégration de la vague D, 24/11/2026 ;
   décision prise par Claude sur délégation de Gabrielle du 24/11/2026 (« t'as mon go pour tout faire et tout merger
   meme paiements etc », « comme tu veux, tu es maitre prends tes décisions »)). Comme le web
   (`DetailMissionSoignant.tsx` l.1160-1183) : pour une mission ouverte non assignée qui a un établissement, « Ne plus
   travailler ensemble » (T11) et « Signaler » (T7b) sont tous deux rangés sous « Autres actions »
   (`mission-autres-actions`) ; pour toute autre mission, ils sont à plat au bas du bloc de l'établissement.
   `ActionsEtablissementMission` replie dès que l'une des deux actions est livrée (et non plus seulement la
   messagerie), et vérifie l'établissement comme le web ; l'écart consigné par T11 (« bouton hors du repli ») est levé.
   « Écrire à l'établissement » reste hors du repli : le web le propose au soignant assigné, après « Annuler ma
   participation » (l.1550-1558, `MissionContactButton`), jamais sur une mission ouverte. `DemoPoolUrgenceTests`
   (mission ouverte `demo-mission-002`) ouvre désormais le repli avant l'exclusion.
20. **T13 — renvois web assumés, contenu définitif (faite à l'intégration de la vague D)** (24/11/2026 ; décision prise
   par Claude sur délégation de Gabrielle du 24/11/2026 (« t'as mon go pour tout faire et tout merger meme paiements
   etc », « comme tu veux, tu es maitre prends tes décisions »)). Table `RenvoisWebLot4` (JoleneCore), aucun texte
   juridique, aucun jeton transmis :
   - **`RenvoiWebScreen`** (écran secondaire dont le coupe-circuit est lu faux) : titre de la page web de l'écran
     (`usePageTitle` : « Trouver une mission », « Mes recherches sauvegardées », « Mes disponibilités », « Litiges &
     contestations », « Messagerie », « Revenus », « Mes évaluations », « Mon score », « Pool urgence », « Exclusions » ;
     aucun titre pour le parrainage et la série, dont les pages web n'en ont pas), phrase neutre et bouton inchangés
     (§3 T1c), présentation `.safari`.
   - **« Documents & protection »** (`RenvoisWebHubSection`, stub de T1c remplacé, `MonCompteSoignant.tsx` l.80-89) :
     « Prévoyance » seule (`hub-renvoi-prevoyance` → `https://jolene.app/soignant/prevoyance`), la ligne que le web
     montre à tous. « Passer en libéral » et « Attestation d'heures » dépendent de `estEligibleLiberal`
     (`src/lib/regles-installation-liberal.ts`), règle de restriction d'un mode d'exercice (HARD STOP n°4) : jamais
     recalculée en natif, ces deux lignes ne sont pas affichées (choix prudent) ; leurs pages restent atteintes par lien
     (renvoi web canonique).
   - **Autres renvois de §1.3** : déjà posés par leurs tranches (Revenus : avances, charges, factures ; bulletins :
     simulations de paie ; Paiements & facturation : mandat ; litiges : accords amiables et litiges typés) ; premium et
     classement n'ont pas d'entrée dans le hub web et restent atteints par lien.
   - **Vérification ajoutée** (§5) : `RenvoisWebSourcesAppTests` (JoleneSupabase) — aucun `UIApplication.shared.open` dans
     l'app, et aucun fichier qui appelle `openURL(` ne nomme un chemin `/soignant/`.
   - **Non fait** : `JoleneUITests/DemoRenvoisWebTests.swift` du §3 T13 (une URL journalisée par entrée) n'est pas
     écrit : aucun simulateur n'a tourné à l'intégration ; preuves par `RenvoisWebLot4Tests` et la garde de source.

21. **Revue B8 des textes de l'intégration de la vague D, constats du lot 4** (24/11/2026 ; corrections arrêtées par la
   consigne de correction de la PR #1179). Réponses détaillées dans la PR.
   - **M1, pool urgence** : l'écran n'affiche plus « Acceptation 1-clic, validation étab sous 1h. »
     (`PoolUrgenceSoignant.tsx` l.136) : aucun mécanisme serveur ne garantit ce délai (même classe que le « sous 72h »
     de la précision 16). `PoolUrgenceTextes.sousTitreAffiche` rend la première phrase, dérivée de la constante
     verbatim, qui reste pour suivre le web (`TextesWebTests`). Retrait natif validé explicitement par la fondatrice
     le 24/11/2026 (groupe D) ; le site affiche toujours la phrase (suivi web à part).
   - **M2** : motif de la précision 16 corrigé (voir cette précision).
   - **M3, litiges** : une proposition d'accord de l'établissement en attente de la réponse du soignant
     (`accord_etablissement` vrai, `accord_soignant` pas vrai, statut où le web propose un accord) est signalée dans la
     liste et le fil par le texte du web, « Proposition de résolution reçue — votre réponse est attendue »
     (`LitigesSoignant.tsx` l.270), au-dessus de la carte « Accord amiable sur jolene.app » existante ; aucun délai.
     Seuls les deux booléens sont lus ; le web exige en plus `payload_modifications` sur sa liste, colonne qui porte
     des montants et n'est jamais lue : l'avis apparaît aussi pour un accord sans modification, où le fil du web
     annonce de même « L'établissement propose un accord » (`FilDiscussionLitige.tsx` l.110). Texte validé
     explicitement par la fondatrice le 24/11/2026 (groupe A).
   - **Mineurs non corrigés**, une ligne chacun :
     - 1 (série, acceptation partielle) : un avertissement écrirait un texte d'engagement nouveau, à valider par
       Gabrielle ; un pré-contrôle serveur de la sélection entière est une RPC nouvelle (hors chantier iOS). Route
       quasi inatteignable (précision 13).
     - 2 (série, « Vérifiez tous vos engagements » vouvoyés et classés non juridiques) : classement validé
       explicitement par la fondatrice le 24/11/2026 (groupe C : vouvoyés, non juridiques).
     - 3 (tutoiement juridique et vouvoiement natif dans un même écran : pool urgence, litiges, swipe) : les textes
       juridiques ne sont jamais reformulés ; l'alignement passe par le vouvoiement du web d'abord, avec la validation
       de Gabrielle.
     - 4 (engagement du pool tronqué) : validé explicitement par la fondatrice le 24/11/2026 (précision 17, groupe C).
     - 5 (« archivées 30 jours après la fin d'une mission ») : `fn_archiver_conversations_anciennes` archive les
       conversations dont la mission est terminée depuis 30 jours (commentaire du dump : cron quotidien à 3 h) ; la
       programmation du cron en production n'est pas vérifiée ici (lecture production non autorisée aux agents).
     - 12 (écarts soignant non déclarés : « Recommander à mon cadre », mémorisation du choix MIXTE, quiz seulement en
       vue Swipe, MATIN / APRES_MIDI non comptés dans les disponibilités, justificatif de contestation sans renvoi,
       bandeau de médiation « 7 jours ») : déclarés ici, à porter par tranches. Le serveur ne garantit pas les 7 jours
       de médiation aux parties : `fn_alerter_mediation_prioritaire` alerte seulement les admins après 7 jours ; le
       bandeau reste non porté.
     - 14 (« Activez le réglage ci-dessus… » pour « Active le toggle à gauche… ») : la position du réglage diffère
       dans l'app ; texte non juridique gardé, « (e) » ajouté à « exclu » retiré (corrigé).
     - 15 (précision 20, « Passer en libéral » et « Attestation d'heures » masqués pour tous) : l'éligibilité devrait
       être servie par le serveur ; choix prudent maintenu.

22. **Paquet de swipe : « Voir le détail » des cartes de fond encore exposé (écart OUVERT, 25/11/2026 ; revue fraîche du
   delta de la vague D, M1).**
   - **Observé** : en local, sur simulateur iOS 18.6 (iPad paysage), par le relevé de l'arbre XCUITest de
     `DemoSwipeTests.testLienVersLeSwipePuisDetailDUneCarte` (commits `22fa810f` et `5916d63e`), XCUITest voit encore le
     bouton « Voir le détail » (`swipe-detail`) des cartes de fond du paquet, malgré les deux
     `accessibilityHidden(!dessus)` de `SwipeCardStack.carte` (`SwipeCardStack.swift` l.337 et l.350-351, commit
     `22fa810f`) et le passage des cartes de fond en `.ignore`. La première correspondance globale de `swipe-detail`
     est celle d'une carte de fond, inatteignable ; `DemoSwipeTests.toucherDetail` (`DemoSwipeTests.swift` l.449-458,
     commit `5916d63e`) cherche donc le bouton dans `swipe-card-<id>` de la carte du dessus. Ce contournement garde la
     même preuve pour le test, mais il ne corrige pas l'app.
   - **Non vérifié** : le comportement réel sous VoiceOver. Si VoiceOver atteint ces boutons, un utilisateur
     entendrait plusieurs « Voir le détail ». Ceux des cartes de fond ouvriraient le détail d'une autre mission que
     celle du dessus, et `allowsHitTesting(false)` ne bloque pas l'activation par VoiceOver.
   - **Correction prévue** : ne plus rendre le bouton de détail dans les cartes de fond. La carte reçoit son rang (la
     vue de carte sait si elle est au-dessus) et ne construit le bouton que pour la carte du dessus ; `toucherDetail`
     redevient alors superflu.
   - **Échéance** : avant le build soumis à l'App Store, dans la prochaine PR iOS, avec un relevé d'accessibilité sur
     simulateur (arbre XCUITest et passage VoiceOver) joint à la PR. Aucune correction de code dans la PR #1179.

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
3. **HARD STOP n°4** : validation du bloc « conditions de la prime » (**T6-HS**, montants serveur, sources jointes) et décision sur la contradiction entre la promesse serveur (`fn_appliquer_parrainage` l.19115) et la page web (`PageParrainage.tsx` l.187, l.300) ; tout texte ajouté après la liste validée. **Validés explicitement par la fondatrice le 24/11/2026** (« Oui, je valide », liste des textes de la revue B8 du tour 2, groupes A à E ; référence au point 1 de l'intégration de la vague D de `DECISIONS_LOT5.md`), plus en attente : feuille « première candidature » (T3b), consentement du pool urgence et opt-in SMS (T11), anti-fuite et blocage (T7b), signalement depuis la messagerie (T7b), mention employeur et avertissement de retrait d'une copie `DESTINATAIRE` (T10), textes « Ne plus travailler ensemble » (T11), avis « Proposition de résolution reçue — votre réponse est attendue » des litiges (précision 21), classement des textes de la série « Vérifiez tous vos engagements » / « Confirmez uniquement si vous pouvez assurer chacun des créneaux exacts sélectionnés. », vouvoyés et rangés non juridiques (précision 13), et les retraits natifs du sous-titre « Acceptation 1-clic, validation étab sous 1h. », de la phrase « sous 72h » et des promesses « +10 points de fiabilité » (précisions 16, 17 et 21). La validation ne couvre pas le site, qui affiche toujours ces trois promesses (point 10).
4. **Décision 3 du lot 0 amendée** (report de la WebView bornée, renvois par `SFSafariViewController`) : tranchée par le mandat (D17) ; pour information, non bloquant.
5. **Onze parcours cœur** : liste tranchée par le mandat (D16) ; validation formelle à la signature de la matrice (point 9).
6. **Relevé de la publication Realtime en production**, en lecture seule (`SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime'`), hors du périmètre de lecture autorisé aux agents (règle générale 4) : à exécuter par Gabrielle ou à autoriser explicitement ; même relevé sur STAGING quand l'accès du lot 1 T11 est ouvert. Résultat à consigner dans la fiche Realtime de `CONTRATS_RPC_SOIGNANT.md`.
7. **Bêta externe** : groupes TestFlight, soumission Beta App Review, collecte des retours, arbitrage bloquant / non bloquant dans `BETA_LOT4.md` ; accès en lecture au projet Sentry pour la mesure crash-free.
8. **Appareil** : un iPhone physique, et un second téléphone pour le QR et le pair de messagerie, pour `RECETTE_DEVICE_LOT4.md`.
9. **Signature** de `PARITE_SOIGNANT.md` à 100 % (critère plan l.207, T15).
10. **Points ouverts web et backend, hors lot** (aucun n'est corrigé par le lot 4) : bouton « Éditer » mort des évaluations ; annulation « réversible à l'infini » du swipe, fausse ; abonnement web aux INSERT `conversations` sans effet ; `LIMIT` sans effet de `fn_lister_notations_recues` (appliqué après `jsonb_agg`) ; codes techniques bruts affichés par le web ; liste des événements de score non affichée par `/soignant/score` (clé `events` lue `evenements`), mais affichée sur le profil (`SectionEvenementsScore`), avec la promesse « sous 72h » qu'aucun mécanisme serveur ne garantit : retrait ou garantie à décider côté web (retrait natif validé le 24/11/2026, précision 16 ; `SectionEvenementsScore.tsx` l.121, `PageScoreSoignant.tsx` l.223, `MesReclamationsEtab.tsx` l.86) ; quiz web qui active le pool urgence par `UPDATE soignants` direct, sans contrôle documentaire ni consentement ; défauts de prime de parrainage divergents (50 / 25) et condition « commission ≥ 4 × prime » absente du texte web ; promesse « +10 points de fiabilité » du pool alignée sur le trigger legacy `dec_bonus_urgence` et non sur le bonus du score v2 (retrait natif validé le 24/11/2026, précision 17) ; sous-titre « validation étab sous 1h » du pool sur le web (retrait natif validé le 24/11/2026, précision 21).

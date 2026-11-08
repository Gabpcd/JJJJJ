# Décisions du lot 2 — application iOS Swift native

> Tranchées le 2 novembre 2026 sur le mandat de Gabrielle (« finis et prends les décisions seul », « je suis tous
> tes conseils », consigné dans `LOTS_2_5_DECISIONS.md` de la session principale) pour les vingt-cinq questions du
> §7 de `docs/mobile-swift/LOT2_PLAN.md` (blueprint du lot 2, v2 du 2026-11-02). Règle générale : **toutes les
> recommandations fermes du §7 sont adoptées telles quelles**, y compris Q1 (système de pointage ① non porté, garde
> qui l'interdit côté Swift) et Q2 (aucune file hors ligne pour le code rotatif). Ce mémo fait foi ; le plan
> `docs/PLAN_APP_NATIVE_SWIFT.md` n'est pas réécrit (l.62, l.180, l.183 et l.186 portent un renvoi ici).
> Les décisions juridiques que le blueprint renvoie à Gabrielle (HARD STOP n°4) et les PR de catégorie B9 **ne sont
> pas implémentées** : elles sont listées sous « En attente de Gabrielle ».

## Règles d'application

- **HARD STOP n°4 (juridique exposé)** : le natif n'affiche que des textes **verbatim** du web ou du serveur, chacun
  relié à sa source (fichier:ligne) et gardé par un test (tranche TL, `JoleneCore/Legal/TextesWeb.swift`). Aucune
  reformulation, aucun texte juridique nouveau, aucun changement de délai ou de règle juridique côté serveur.
- **B9** (paiements, migrations destructives, RLS/auth/GRANT/SECURITY DEFINER, légal, données prod) : la PR est
  préparée et poussée, tests compris, mais jamais mergée sans le go explicite de Gabrielle (B1, S1, dispatch de T11).
- **Aucune écriture** en production ni sur STAGING par les agents ; lecture seule en production seulement pour
  relire une définition live dans une PR backend (`pg_get_functiondef`, `list_migrations`).
- Merges sur `main` sériels, CI verte et revue fraîche B8 clôturable, par la file de merge de la session principale.

## Décisions (§7 du blueprint)

1. **Système de pointage ① : non porté.** `fn_pointer_*`, `fn_valider_scan_qr`, `fn_generer_qr_mission`,
   `fn_valider_code_secours`, `fn_codes_pointage_mission`, `fn_generer_code_secours_mission` et
   `qr-offline-queue.ts` ne sont jamais appelés par le Swift : liste `RPC_POINTAGE_SYSTEME_1` (neuf RPC) refusée par
   `verifierExclusions` et par la garde des littéraux `"fn_…"` (T0). **Amendement** (seconde revue fraîche de T0) :
   `fn_generer_code_secours_mission`, absente de la liste du blueprint (`LOT2_PLAN.md` §3 T0), y entre ; c'est le
   générateur du code de secours que consomme `fn_valider_code_secours`, appelé seulement par `QRPointageEtab`
   (monté par aucun écran) et troisième chaîne de pointage à distance du constat B9 (« En attente de Gabrielle »).
   Motifs : plus monté côté web depuis la PR #664 ; contrôle « contrat signé » absent de `fn_valider_scan_qr` et
   de `fn_valider_code_secours` elles-mêmes (`fn_pointer_arrivee` et `fn_scanner_code_pointage` le font), assuré
   pour elles seulement par le trigger de première arrivée `trg_01_exiger_conformite_premier_pointage`
   (`fn_exiger_conformite_demarrage_mission`) ; missions multi-jours bloquées. Critères amendés : P2 (QR rotatif
   décodé, niveau 1, puis scanné sur iPhone, niveau 5) remplace « QR `fn_generer_qr_mission` accepté par
   `fn_valider_scan_qr` » ; P6 (« aucun scan mis en file ni rejoué ») remplace « QR expiré jamais remis en file ».
   Une garde Node rougit si le web rappelle le système ① (la décision est alors à revoir). Le commentaire de `Rules/DisponibilitePointage.swift` l.106-107, qui
   cite encore `fn_pointer_arrivee` / `fn_pointer_depart`, est corrigé par T3 (T0 n'écrit aucune ligne Swift).
2. **Hors connexion : aucune file pour le code rotatif.** Bouton désactivé et bandeau hors ligne ; reçu `not_sent` ;
   réponse perdue → réconciliation par relecture de `scans_pointage` (verdict « non reçu » seulement ≥ 8 s après le
   passage `started`) ; jamais de renvoi automatique. Le pointage « sans téléphone » reste la déclaration de fin
   rétroactive côté établissement (web). `PRINCIPES.md` §4 est amendé en conséquence.
3. **QR : `AVCaptureMetadataOutput`**, pas VisionKit ; payload accepté seulement s'il vaut exactement six chiffres
   après `trim` (plus strict que le web) ; refus caméra → saisie manuelle, toujours disponible.
4. **Consentement GPS : texte verbatim de `ConsentementGPS.tsx` au premier pointage** quand `consentement_gps IS NULL`,
   enregistré par `fn_consentir_gps` puis relu, audit `RGPD_CONSENTEMENT_DONNE` (parité web) ; autorisation iOS
   « Lorsque l'app est active » demandée seulement après « Autoriser » ; un refus ne bloque jamais le pointage.
   **Retrait et réactivation depuis le Profil natif portés au lot 2** (T4b : le texte promet le retrait « depuis
   votre profil ») avec les textes de `SectionPreferences.tsx` (tutoyés, verbatim tant que non validés) et sans
   audit `GPS_CONSENTEMENT_*` (absent du CHECK `journaux_audit_action_check`).
5. **Précision réduite iOS : aucune coordonnée envoyée** quand `accuracyAuthorization == .reducedAccuracy` (scan sans
   GPS + encart « Position exacte ») ; pas de `requestTemporaryFullAccuracyAuthorization` (nouvelle chaîne
   `Info.plist`, donc nouveau texte).
6. **Messages de refus du pointage : messages serveur verbatim** (décision 9 du lot 1) ; une seule surcharge, celle
   du web pour `P0002` (`src/components/pointage/PointageRotatifSoignant.tsx` l.136 : « Code de pointage invalide ou
   expiré. Demande le code actuel à l’établissement. »), dont seule la personne du verbe change (vouvoiement) :
   « Code de pointage invalide ou expiré. Demandez le code actuel à l’établissement. » — forme exacte affichée par
   T4b, apostrophe typographique ’ du web comprise (le §7 Q6 du blueprint l'écrit avec une apostrophe droite).
   Garde : `tests/node/check-rpc-contracts.node.mjs` relit la ligne du web et rougit si elle change.
7. **Identifiant terminal : `TERM_IOS_` + 20 caractères base32 aléatoires**, générés une fois, Keychain
   `ThisDeviceOnly`, non synchronisé, conservé à la déconnexion ; jamais `identifierForVendor` ni empreinte d'appareil.
8. **`nouveau_code` : faire B1** (PR backend séparée, B9 → en attente du go) ; d'ici là le décodeur Swift est une liste
   blanche qui ne lit jamais `nouveau_code` ni `nouveau_hmac` (fiche dédiée de `CONTRATS_RPC_SOIGNANT.md`, garde
   Node qui bascule avec B1).
9. **Litige depuis une présence : ouverture portée, fenêtre décidée par le serveur, aucun texte de délai.** Bouton si
   `valide_le` est non nul, qu'aucun litige n'existe et que `fn_fenetre_contestation_ouverte('DESACCORD_HEURES_POINTAGE',
   mission)` renvoie vrai (aucune constante 72 h dans le Swift) ; appel de `fn_ouvrir_litige_rate_limited` par trois
   clés exactes, audit `PRESENCE_CONTESTATION`, **sans** l'appel client `fn_creer_notification` (`RPC_JAMAIS_SUIVIES`) ;
   réponse et clôture : renvoi web. Les textes de délai du panneau web (l.347, l.354, l.394) ne sont pas affichés.
   La décision juridique (aligner `delai_contestation_pointage_h` sur 72 h, retirer la phrase d'escalade du web)
   relève de Gabrielle : **non implémentée**, voir « En attente de Gabrielle ». T5b attend ce go ; le reste du lot
   n'en dépend pas.
10. **Notation rapide : parité web** (une fois par mission, après une FERMETURE quand `now ≥ fin_le − 30 min`, note
    globale répliquée sur les quatre critères, détail optionnel, « Plus tard ») ; mémoire locale par utilisateur ;
    aucune lecture de `notations_missions` ; pas d'invite de parrainage (lot 4).
11. **Détail des présences : synthèse, segments et relance en natif** (avec `fn_presences_detail_mission` en lecture
    tolérante) ; **récapitulatif financier non porté** (calculé côté client sur le web) → lien Revenus (renvoi web
    jusqu'au lot 3).
12. **Exigences documentaires : faire W1** (extraction web sans changement de comportement) et porter le filtre avec
    vecteurs golden (T2b) ; candidat à une RPC serveur plus tard.
13. **Médias** : caméra `UIImagePickerController`, photothèque `PHPickerViewController` (sans permission), Fichiers
    `UIDocumentPickerViewController` ; HEIC/HEIF → JPEG 0,8, orientation appliquée, métadonnées GPS retirées ;
    au-delà de 10 Mo, réduction à 4 096 px puis qualité 0,6, sinon refus avec le message du web.
14. **Reçus d'envoi** : reçu avant Storage avec la clé déterministe ; réconciliation par `s3_cle` (et `exists(path:)`) ;
    seule `fn_remplacer_document_soignant` (idempotente) peut être rejouée après relecture ; `verify-document` une
    seule fois par document ; aucun octet de document conservé sur disque.
15. **Attestation santé : portée verbatim dans l'onglet Justificatifs** (deux cases, `fn_signer_attestation_sante`,
    relecture), textes en TL.
16. **DPAE et Conformité : renvoi web au lot 2**, port en lecture au lot 4 avec revue HARD STOP des libellés.
17. **Lecture du contrat : HTML serveur dans un lecteur `WKWebView` isolé** (sans script, sans réseau, navigation
    bloquée, data store non persistant) après triple contrôle de l'empreinte ; pas de PDFKit ; partage = fichier HTML
    original contrôlé ; impression par la feuille système. Ce lecteur ne charge jamais d'URL.
18. **Mode de signature : OTP SMS seulement** (seul mode lié à l'empreinte) ; signature manuscrite non portée ; compte
    TEST sans admission de recette → « continuer sur jolene.app » (renvoi web vers `/contrat/:id`).
19. **CDD sans original : message du web** (« Le contrat doit être préparé et confirmé par un représentant autorisé de
    l'employeur avant les signatures. », `ContratMission.tsx` l.603), aucune action soignant, aucun `donnees_cdd`
    envoyé par l'app.
20. **Preuve OTP STAGING : S1 + numéros de recette** (soignant : Gabrielle ; établissement : second numéro) ;
    capacité allouée après le rendu du contrat, une par contrat et par séance ; l'XCUITest STAGING prouve l'envoi
    (`otp_envoye`) ; la signature complète est faite par Gabrielle sur iPhone (T12) sur une fixture « appareil » et
    une capacité dédiées, puis relue en SQL. Sans S1, P5 reste ouvert et le lot n'est pas livré.
    `fn_admission_otp_signature_recette` est suivie avec le statut `staging_seulement` (jamais en production).
21. **Preuve GPS** : « comparée à une présence issue de la coquille » est remplacé par « clés de `p_metadata`
    identiques à `PointageRotatifSoignant.tsx` l.122-126 (test de forme) + précision relue dans `scans_pointage` et
    `presences` sur STAGING » ; aucune donnée de production.
22. **Durée de la CI UI** : matrice actuelle conservée (3 formats, une étape) ; découpage en éclats par domaine
    (`-only-testing` Présences / Documents / Contrats) dès qu'un format dépasse 20 min mesurées.
23. **Journal de reçus : celui du lot 1 T7 est réutilisé** ; si T1 du lot 2 démarrait avant son intégration, T1
    livrerait le journal générique et T7 le consommerait sans changer son API. Ordonnancement retenu : T1 attendait
    l'intégration de T7 et démarrait dans la vague 1 du lot 2, pas dans la vague 0.
    **Application (revue fraîche de L2-T1, 8 novembre 2026)** : T7 n'existe sur aucune branche (`main`,
    `feat/ios-lot1`, `lot1/*`, `feat/ios-lot2`) et T1 a démarré sans lui : T1 livre donc le repli prévu, sans
    décision nouvelle. Livré : `JoleneCore/Receipts/ReceiptJournal.swift` (`ReceiptJournal<Recu: RecuDurable>`, une
    clé `CleRecu` par (utilisateur, domaine) ; lire, écrire, effacer ; écriture refusée, `RecuErreur.recuEnCours`, si
    un reçu non terminé d'un autre `attemptId` existe ; succession des phases du même essai ; relecture après écriture
    et après effacement ; tout échec du magasin ou reçu illisible → `RecuErreur.illisible`, sans réparation (recours :
    renvoi web du domaine, « Consignes aux tranches suivantes ») ;
    opérations sérialisées par l'acteur global `JournalRecusActeur` ; protocole `ReceiptStorePort` et magasin démo
    `MagasinRecusEnMemoire`), `RecuDurable.attemptId` et `verifierSuccession(apres:)`, champ `Appareil.recus`
    (`Appareil.demo` : magasin en mémoire vierge), `JoleneSupabase/Keychain/KeychainReceiptStore.swift` (service
    `app.jolene.receipts`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non synchronisé, conservé à la
    déconnexion) ; tests `ReceiptJournalTests` et `KeychainReceiptStoreTests`. T3 et T6 peuvent démarrer ; reprise
    par lot 1 T7 : « Consignes aux tranches suivantes ».
24. **Points d'entrée : pas de sixième onglet** ; section « Mon espace » du Profil (Présences, Documents, Contrats),
    widget « Aller pointer » et bandeau d'oubli de départ sur l'Accueil, boutons du détail de mission, liens
    universels.
25. **Horloge de la fenêtre de pointage : horloge de l'appareil**, comme le web ; le serveur fait foi et son refus
    s'affiche ; pas d'horloge serveur.

## D-FLAGS — drapeaux d'écran du lot 2

- **Clés** : `ios_natif_presences_actif` (présences et pointage : Profil › Mes présences, widget « Aller pointer »,
  boutons du détail de mission), `ios_natif_documents_actif` (Mes documents, onglet Justificatifs),
  `ios_natif_contrats_actif` (liste, lecteur et signature des contrats). Absentes du blueprint, ajoutées pour que le
  lot 6 dispose d'un coupe-circuit sur le pointage et la signature.
- **Migration** : une seule migration non-B9 pose tous les drapeaux d'écran des lots 2, 4 et 5 (`INSERT … ON CONFLICT
  (cle) DO NOTHING`), sur le modèle de B0 `supabase/migrations/20261102150000_drapeaux_ios_natif.sql` ; PR séparée,
  hors chantier iOS (aucune écriture sous `supabase/` par les tranches iOS). Catégorie `OPERATIONS`, aucun GRANT `anon`.
- **Client** : la tranche T1 du lot 2 étend `EcranNatif` (lot 1, `JoleneCore/Ports/Lot1Ports.swift`) avec ces trois
  écrans ; lecture par `fn_param_bool` après `.ready` et à la reprise, **fail-open** comme au lot 1 (toute erreur ou
  clé absente → écran natif actif) ; `false` → renvoi web de l'écran concerné.

## Scission T2 / T2b

- **T2** (vague 0, dès l'intégration de lot 1 T2) livre les vecteurs golden qui ne dépendent pas de W1 :
  `synthese-presence-mission.ts`, `presencesSoignantUi.ts`, `documentUpload.ts`, `documents.ts`,
  `contratMissionUi.ts`, `signatureSmsStagingAdmission.ts`, plus les règles natives sans golden (`PayloadQR`,
  `CompteARebours72h`).
- **T2b** (après le merge de W1 sur `main`) vectorise les deux règles extraites par W1 : `src/lib/documents-requis.ts`
  (`filtrerDocumentsRequis`, `documentValidePourExigence`) et `src/lib/presences-soignant-listes.ts`
  (`construireListesPresences`). **W1** (lot 2) et **W0** (lot 4) forment une seule PR web d'extraction de règles
  pures, comportement inchangé, tests vitest.

## Ordonnancement et branches

- **T0** (cette tranche) est préalable à toutes les autres. **B1** vise `main` et n'attend pas T0 (amende
  `LOT2_PLAN.md` §3 B1 « Fichiers » et §4, vague 0), voir « Amendements du blueprint » ; tant que le lot 2 n'est
  pas sur `main`, la fiche « `nouveau_code` jamais lu » de `CONTRATS_RPC_SOIGNANT.md` et sa garde n'existent que
  sur `feat/ios-lot2`. Elles basculent donc au **merge de `main` dans `feat/ios-lot2`** qui suit la re-baseline du
  dump après B1 : la garde rougit à ce merge, et le commit de merge (ou celui qui le suit sur `feat/ios-lot2`) met à
  jour la fiche et la garde. Si T0 est déjà sur `main` quand B1 arrive, la PR B1 les bascule elle-même.
- **Bascule des gardes confrontées à `main` (règle générale, B1 en est un cas).** Les gardes de
  `tests/node/check-rpc-contracts.node.mjs` relisent des sources que des PR de `main` peuvent changer avant que le
  lot 2 y soit : le dump `supabase/schema/public.sql` (re-baseliné après chaque PR backend) et le web `src/`. Tant
  que T0 n'est que sur `feat/ios-lot2`, une telle PR ne peut pas mettre à jour ces gardes ni les fiches : elles
  rougissent au **merge de `main` dans `feat/ios-lot2`** qui l'amène (après la re-baseline du dump pour une PR
  backend), et ce commit de merge, ou celui qui le suit sur `feat/ios-lot2`, bascule la garde, la fiche de
  `CONTRATS_RPC_SOIGNANT.md` et le constat de ce mémo. Si T0 est déjà sur `main`, la PR elle-même les bascule.
  Cas connus :
  - **B1** (`nouveau_code` retiré) : garde « `nouveau_code` renvoyé tant que B1 n'est pas mergée », fiche
    « `nouveau_code` jamais lu ». **Basculées le 8 novembre 2026** (B1 mergée sur `main` par #1117, merge de `main`
    dans `feat/ios-lot2` à l'intégration de T3, T6 et T8) : la garde exige l'absence de `nouveau_code` et de
    `nouveau_hmac` dans le dump ; les fiches `fn_scanner_code_pointage` et `fn_etat_pointage_mission` citent les
    numéros de ligne du dump re-baseliné.
  - **PR backend B9 des constats ci-dessous** : `REVOKE` des neuf RPC ① ou correction des gardes ternaires
    (`IS DISTINCT FROM`, `COALESCE`) de `fn_codes_pointage_mission`, `fn_generer_qr_mission`,
    `fn_generer_code_secours_mission`, `fn_presences_detail_mission`, `fn_etat_pointage_mission` et des autres RPC
    du « Motif à auditer » ; `REVOKE` de `fn_creer_notification` ou contrôle de son destinataire. Gardes « B9
    RLS/auth » (constats et « Motif à auditer ») et « `fn_etat_pointage_mission` » ; fiches ①, `fn_creer_notification`,
    `fn_etat_pointage_mission`, `fn_presences_detail_mission` ; sous-section B9 de ce mémo.
  - **PR web des propositions B9** : retrait de l'appel `fn_creer_notification` de `PanneauContestation.tsx` (garde
    « `RPC_JAMAIS_SUIVIES` : `fn_creer_notification` », témoin de l'appel web, et gardes qui relisent ce fichier :
    trois clés de `fn_ouvrir_litige_rate_limited`, constante 72 h ; fiche `fn_creer_notification`) ; retrait de
    `SyncHorsLigne` / `src/lib/horsLigne.ts` (garde « Web : le système ① reste mort », fiche ①, « Points consignés
    hors lot 2 »).
  - **W1** (extraction dans `PresencesSoignant.tsx` et `DocumentsSoignant.tsx`) : garde « Web : le système ① reste
    mort », qui lit `PresencesSoignant.tsx` (`pointerArrivee`, `pointerDepart`, `stockerPointageHorsLigne`,
    `<BlocPointageMission`), et numéros de ligne de ces deux fichiers cités par les fiches et par la scission T2/T2b.
  Les messages d'échec des témoins concernés (constats B9, « Motif à auditer », `est_etab`, appel web de
  `fn_creer_notification`, rejoueur ①, `nouveau_code`) nomment la fiche ou le constat à basculer et renvoient à ce
  paragraphe (suffixe `BASCULE_MAIN` de la garde).
- **T1** (vague 1) livre le journal générique de reçus, lot 1 T7 n'existant sur aucune branche (décision 23,
  « Application ») ; T3 et T6 en dépendent.
- **Références du code partagé avec le lot 3** : `RPC/RPCResponse.swift` (commentaire de `executer`, qui cite
  `RPCResponse+SansCorps`) et `RPC/RPCResponse+ExceptionsMetier.swift` (en-tête, qui cite
  `docs/mobile-swift/LOT3_PLAN.md`) nomment deux fichiers absents du lot 2. Accepté pour garder ces deux fichiers
  identiques octet pour octet à ceux du lot 3 (blobs `58a4f9a8` et `ab974ea1` respectivement, identiques sur
  `lot3/l3-t1` et `feat/ios-lot3`) ; les références se résolvent au merge du lot 3. Le classement des mutations du lot 2
  (`RPC/RPCResponse+MutationLot2.swift`) vit dans un fichier à part pour ne pas toucher le fichier partagé.
- Branche d'intégration `feat/ios-lot2`, créée depuis `origin/feat/ios-lot1` ; elle reprend `main` puis `feat/ios-lot1`
  par merge (jamais de rebase ni de force-push). Aucune PR n'est ouverte sur cette branche avant la fin du lot 1
  (chaque PR lance la recette Playwright sur la base partagée).

## Consignes aux tranches suivantes

- **T2** (qui modifie les filtres de chemins de `.github/workflows/ios-swift-ci.yml`) : ajouter
  `scripts/ci/sms-signature-staging.sql` aux deux listes `paths` (`pull_request` et `push`). Depuis T0,
  `node scripts/mobile/check-rpc-contracts.mjs` (étape « Contrats RPC sans dérive », l.116) lit ce supplément pour
  `fn_admission_otp_signature_recette` (statut `staging_seulement`). D'ici là, la garde Node de `validate-pr.yml`
  couvre une modification du supplément ; `tests/node/check-rpc-contracts.node.mjs` exige cette consigne tant que le
  filtre manque.
- **T3** : stubs de test et fixtures de démo de `fn_etat_pointage_mission` avec `est_etab: null` (forme réelle de
  la réponse pour tout soignant, assigné compris : `false OR NULL`, `public.sql` l.35165 et l.35189), jamais
  `false` ; `est_etab` n'est pas décodé (ou `Bool?` ignoré), comme `code_pointage_actif` (fiche
  `fn_etat_pointage_mission` de `CONTRATS_RPC_SOIGNANT.md`). La garde rougit si une fixture ou un stub de
  `ios-native/` ou `scripts/mobile/export-demo-fixtures.mjs` pose `est_etab: false`.
- **T3** (revue fraîche de T1) :
  - reçu par `ReceiptJournal<RecuScan>(store: appareil.recus)` : `prepared` écrit AVANT tout appel, `started` juste
    avant l'unique requête, effacé (`ReceiptJournal.effacer`) après la relecture du succès, du refus ou du verdict
    « non reçu ». `RecuErreur.recuEnCours` → `RecuScan.messageRecuEnCours` ; `RecuErreur.illisible` → écran bloquant
    `RecuScan.messageIllisible`, aucun scan, **voie de récupération** = renvoi web `/soignant/presences` par
    `PresentateurRenvoiWeb` (le pointage web n'utilise pas ce journal), comme l'identifiant terminal (consigne T4b) ;
    le reçu illisible n'est jamais réécrit ni effacé par l'app (seconde revue fraîche de T1) ;
  - le scan passe par `RPCResponse.appelerMutation(…, exceptionsMetier: ExceptionsMetierLot2.scannerCodePointage)`,
    jamais par `appeler` : `JoleneError(.unknown)` d'`appeler` mêle une exception non déclarée (rollback prouvé) et
    une passerelle 502/504 (incertaine, corps HTML ou `{"message"}` décodé en `PostgrestError(code: nil)` par
    supabase-swift 2.55.5). `.reponse` → succès relu ou refus restitué ; `.refusDefinitif(code:erreur:)` (rollback
    prouvé : `code` SQLSTATE, ou code PostgREST de `RPCResponse.codePostgRESTSansTransaction`, amendement de la
    correction 10) → refus, reçu `refused` si `code` est un SQLSTATE (`RecuScan.sqlstateValide`, même prédicat), sinon
    effacé (code `PGRST…` émis avant toute transaction ou après son annulation) ; `.incertain` (réseau, passerelle,
    `PGRST001`, tout autre code) et délai `bounded` → `IssueScan.incertain`, reçu `started` conservé,
    réconciliation par relecture ;
  - relecture `scans_pointage?select=<PreuveScan.selection>&mission_id=eq.<mission du reçu>` : la projection porte
    `mission_id`, que `RecuScan.reconcilier` vérifie aussi (avec `numero_scan > nb_scans_avant`). Le verdict est
    rendu par `IssueScan(reconciliation:)` : `.recu` → `.enregistre` (reçu effacé) ; `.aRelire` → `.incertain`
    (reçu `started` gardé, nouvelle relecture) ; `.nonRecu` → `.nonRecu` (reçu effacé après cette relecture, saisie
    du code courant demandée) ; `.horlogeIncoherente` (heure de l'appareil reculée) → `IssueScan.horlogeIncoherente`,
    affichée comme `messageIllisible` avec le même renvoi web, sans relecture en boucle ; le reçu reste `started`
    et le verdict redevient « non reçu » dès que l'horloge dépasse `demarreLe + 8 s` ;
  - `fn_etat_pointage_mission` et `fn_presences_detail_mission` : la gateway lit `RPCResponse.estRefus` et
    `erreur` AVANT de décoder (`{error}` → `.refuse` verbatim pour l'état ; carte de synthèse masquée pour le
    détail) ; `EtatPointage` et `ResumePresencesServeur` refusent eux-mêmes `{error}` et un objet sans leurs clés
    discriminantes.
- **T3** (revue fraîche de T2b) : `contrats_mission.statut` est NULLable (`supabase/schema/public.sql` l.68786,
  `types.ts` `statut: string | null`) ; le web retient un contrat à statut nul (non terminal, priorité 0), qui bloque
  alors le pointage avec le motif CONTRAT. `ContratPointage.statut: String` (`Rules/DisponibilitePointage.swift`) ne le
  décode pas : T3 rend le décodage tolérant (nul → `""`, même effet que le web), puis ajoute un contrat `statut: null`
  à `grille/contrats/choix` de `scripts/mobile/export-golden-vectors.mjs`, dont le domaine refuse aujourd'hui ce cas.
- **T3** (revue fraîche de T2b) : la projection `missions` de `PresencesSoignant.tsx` (l.114-115) ne sélectionne pas
  `profession_requise`, que `MissionRecord.init(from:)` exige (`Models/Mission.swift`) : la décoder en `MissionRecord`
  lèverait `keyNotFound`. T3 ajoute `profession_requise` à son select, ou décode son propre type tolérant conforme à
  `MissionPresenceRepresentable` (`Pointage/ListesPresences.swift`).
- **T3 — application (L2-T3, 8 novembre 2026)**, réponse aux mineurs M1 à M3 de la revue fraîche de T1 :
  - M1, règle des 8 s : `RecuScan.delaiAbsenceProuvee` reste 8 s (décision 2). `PointageModel` attend EN PLUS 8 s
    sur l'horloge monotone du processus (`ProcessInfo.systemUptime`) quand l'essai y a démarré : une horloge
    d'appareil avancée ne raccourcit pas l'attente ; pour un essai d'un autre processus (app relancée), seul l'écart
    d'horloge murale de la gateway s'applique. L'attente du pool PostgREST (`PGRST003`, jusqu'à 10 s avant la
    transaction) est chiffrée par la revue fraîche de L2-T3 (m2, ci-dessous) : un essai sorti sans réponse n'est
    déclaré « non reçu » qu'après sa sortie + 10 s + 8 s monotones. Un scan appliqué malgré tout après un verdict
    « non reçu » (essai d'un autre processus) est rattrapé par le suivi de l'état (15 s) et, si le soignant ressaisit
    le code, par le refus anti-rejeu `23514` (2 min, `public.sql` l.55661) qui relance la réconciliation
    (`PointageRules.estAntiRejeu`).
  - M2 : reçu `prepared` orphelin → `marquerNonEnvoye`, journalisé, puis effacé (`started` précède toujours l'unique
    requête) ; reçu terminal (`refused`, `not_sent`) → effacé ; un essai en vol dans le processus (autre bloc de
    pointage) n'est jamais réconcilié par un autre modèle (`PointageModel`, ensemble des essais en vol).
  - M3 : `{error}` de `fn_etat_pointage_mission` → `JoleneError(.unknown, <message serveur verbatim>)` (« Mission
    introuvable », « Accès interdit ») ; « Non authentifié » → `.unauthorized` ; objet sans clé discriminante →
    `.contract`. Le modèle publie `PointageModel.Chargement.indisponible(message)`, l'envoi reste impossible.
  - Réponse de `fn_scanner_code_pointage` : la forme d'après B1 (sans code suivant) et celle d'avant donnent le même
    succès (liste blanche `ScanEnregistre`) ; la réponse brute ne sort jamais de la gateway.
- **T3 — revue fraîche de L2-T3 (8 novembre 2026)**, réponse aux majeurs M-A, M-B et aux mineurs m1 à m8 :
  - M-A, HTTP 200 jamais « non reçu » : `fn_scanner_code_pointage` trouve la mission par le seul code (`public.sql`
    l.55639-55644) ; le code de la mission A saisi dans le bloc B pointe A. Un HTTP 200 prouve le COMMIT (amendement de
    la correction 10). La gateway confirme d'abord sur la mission du reçu (preuve hors base ET état), puis relit la
    ligne du scan sans filtre de mission (`creneau_effectif_id` et `numero_scan` de la réponse, `soignant_id`,
    `id_terminal` ; `sp_select` l.79931) et l'état de sa mission → `IssueScan.enregistreSurAutreMission(missionId:…)` ;
    à défaut (lecture en échec, réponse hors contrat, ligne introuvable, état non basculé) → `IssueScan.accepteSansPreuve`,
    jamais `.incertain`. Le modèle solde le reçu dans les deux cas, sans réconciliation (filtrée sur la mission du reçu,
    elle conclurait « non reçu ») : `Issue.enregistreSurAutreMission(type, missionId:)`, ou `Issue.suiviIllisible`
    (renvoi web `/soignant/presences`, ce bloc n'envoie plus rien). La démo applique la même règle (code de la mission
    a saisi dans le bloc b → enregistré sur a ; jamais bloqué en vérification par l'horloge fixe).
  - M-A, limite consignée (réponse perdue) : un scan appliqué sur une AUTRE mission dont la réponse est perdue
    (transport, délai `bounded` de la requête seule depuis mi-1 de la seconde revue) reste réconcilié sur la mission du
    reçu ; après l'attente (m2), le verdict est
    « non reçu » sur cette mission. Le reçu v1 ne porte la base des preuves que de sa mission (`preuvesAvant`) : sans
    base pour les autres missions, une ligne d'une autre mission ne se distingue pas d'un scan antérieur, sauf à
    comparer l'heure du serveur à celle de l'appareil (non fiable). Atténuations : l'état de l'autre bloc (15 s) et la
    liste des présences montrent le segment ouvert ; une ressaisie dans les 2 min est refusée par l'anti-rejeu
    `23514`. Risque résiduel : une ressaisie du code courant de A (dans un bloc ou l'autre) plus de 2 min après
    pointerait A une seconde fois. Levée possible, hors lot 2 : reçu v2 avec la base des preuves du terminal sur toutes les missions
    `ASSIGNEE`/`EN_COURS` du soignant, relue avant l'envoi (règle des versions ci-dessous), ou clé d'idempotence côté
    serveur (B9).
  - M-B, réapparition : `PointageModel.activer()` (appelée aussi par `charger()` et `suivre()`) rend le bloc de nouveau
    opérant après `desactiver()` ; une génération avance à chaque disparition et toute opération commencée avant ne
    publie plus rien. Une issue décidée par le serveur (succès, refus, « non reçu », M-A) solde quand même le reçu si
    l'epoch n'a pas changé (même utilisateur) ; un epoch périmé garde le reçu pour la réconciliation au retour.
  - m1 : `PGRST301`-`PGRST303` au scan (rollback prouvé), session absente ou 401/403 hors PostgREST →
    `JoleneError(.unauthorized)` levée par la gateway ; le modèle publie `sessionExpired` et `.verification`, garde le
    reçu `started` (réconcilié au retour de l'utilisateur, nouvel epoch), sans relecture ni renvoi ; `.unauthorized`
    pendant la réconciliation arrête les relectures et publie `sessionExpired` aussitôt ; `NON_AUTHENTIFIE` de
    `fn_relancer_validation_presence` (l.53023) → `.unauthorized`, jamais « Relance impossible. ».
  - m2, chiffrage : un essai sorti sans réponse (délai `bounded`, transport, `.incertain`, session expirée) n'est
    déclaré « non reçu » qu'après, sur l'horloge monotone, son instant de sortie (au moins le délai `bounded` s'il est
    dépassé) + 10 s (`PointageModel.attentePoolPostgREST`, attente du pool, `PGRST003`) + 8 s
    (`RecuScan.delaiAbsenceProuvee`, `statement_timeout`) ; 15 + 10 + 8 = 33 s pour un délai `bounded` de 15 s. Risque
    résiduel : un essai d'un autre processus (app relancée moins de 18 s après l'envoi) n'a que l'écart de 8 s de
    l'horloge murale.
  - m5 : `fn_etablissements_safe` en échec → instantané sans noms (`[:]`, repli du web à l'affichage), comme
    `fetchEtablissementsSafe` (`src/lib/etablissements.ts` l.31-38) ; session expirée et annulation remontent.
  - m6 : `finLe` reste celui de l'init du modèle ; la relecture de `missions.fin_le` après la FERMETURE (web l.156)
    relève de T5a (consigne T5a).
  - m7 : `charger()` ne relit rien pendant un envoi (l'envoi relit lui-même l'état).
  - m8 : `MetadonneesScan` masque coordonnées et précision dans `description`, `debugDescription` et sa réflexion
    (`customMirror`) ; seul `encode` les écrit, pour `p_metadata`.
- **T3 — seconde revue fraîche de L2-T3 (8 novembre 2026)**, réponse au majeur MJ-1 et aux mineurs mi-1 à mi-6 :
  - MJ-1, reçu commun soldé par un autre bloc : le journal tient un reçu par utilisateur et tous les blocs le
    réconcilient. `PointageModel` attache à `.verification` (et au `.suiviIllisible` d'une horloge incohérente) l'essai
    qu'ils concernent ; quand le bloc d'une autre mission solde cet essai, il transmet son issue (`.enregistre`,
    `.nonRecu`, …) au bloc qui l'affiche, qui la publie à sa prochaine réconciliation (`charger()`, tic de 15 s, retour
    au premier plan) ; reçu effacé sans issue transmise → vérification levée (l'état vient d'être relu ; tout nouvel
    envoi relit sa base), jamais un succès supposé. Un reçu `started` n'est réconcilié que par un modèle à la fois
    dans le processus (ensemble des essais en vol, réconciliations comprises). Le `.suiviIllisible` d'un journal
    illisible n'est jamais levé.
  - mi-1 : `PointagePort` gagne `envoyerScan` (l'unique requête seule → `EnvoiScan.issue(IssueScan)` ou
    `.accepte(ScanEnregistre?)`) et `relireScanAccepte` (relectures d'un HTTP 200) ; le modèle borne chacune par
    `bounded` ; des relectures en échec ou hors délai donnent `.accepteSansPreuve`, jamais `.incertain`. Défauts en
    extension (`envoyerScan` → `.issue(scanner(…))`, `relireScanAccepte` → refus « non câblé ») : démo, doubles et stub
    inchangés ; `SupabasePointageGateway.scanner` enchaîne les deux moitiés. Limite restante (M-A) : une requête dont
    le HTTP 200 arrive APRÈS le délai `bounded` reste une réponse perdue.
  - mi-2 : première relecture immédiate (blueprint §2.5) ; un « non reçu » relu avant la fin de l'attente monotone de
    l'essai (m2) reste « à relire » : le modèle attend le reste de cette attente, puis relit. La vérification se
    poursuit hors de l'envoi : `envoiEnCours` retombe dès la réponse perdue, `charger()` et `rafraichir()` relisent
    l'état pendant l'attente, `reconcilier()` n'en lance pas une seconde (une par génération).
  - mi-3 : le `.suiviIllisible` d'un HTTP 200 sans preuve est levé par le premier `charger()` réussi d'une génération
    ultérieure (le bloc a disparu puis réapparu) ; dans la même génération il reste affiché (message lisible, aucun
    envoi). Consigne T4b ci-dessous (renvoi web explicite).
  - mi-4 : un bloc réactivé pendant l'envoi (son `charger()` a sauté la lecture) relit son état dès la fin de l'envoi,
    dans sa génération, et réconcilie un reçu resté `started` ; la réponse de l'envoi reste ignorée (M-B).
  - mi-5 : fiche `fn_scanner_code_pointage` de `CONTRATS_RPC_SOIGNANT.md` alignée (un HTTP 200 non confirmé n'est
    jamais `.incertain`).
  - mi-6 : `DemoPointageGateway.scanner` exige, comme la gateway Supabase, que le terminal du reçu soit celui des
    métadonnées envoyées (`.contract` sinon, rien n'est appliqué).
- **T4a** (après T3) : instantané par `gateways.pointage.presences(context:)` ; onglets par
  `InstantanePresences.listes(maintenant:)` (horloge `chargeLe`), historique par `lignesHistorique(soignantId:)`,
  `PointageRules.ongletInitial(parametre:missionsAujourdhui:missionsEnCours:)`, `filtreAValider`,
  `historiqueAffiche`. Aucun texte dans `Pointage/` : les libellés des onglets et des lignes viennent du web.
- **T4a — application (L2-T4a, 8 novembre 2026)** : `Pointage/PresencesModel.swift` (instantané, onglet initial posé au
  premier chargement réussi seulement — `defaultValue` des onglets du web, montés après le chargement —, échec sans texte,
  règles d'état d'`AccueilModel`, relecture à 60 s et au retour au premier plan) et `Pointage/PresencesAffichage.swift`
  (`BlocPointageAffichage`, `ResumeLignePresence`, mission et établissement d'une ligne, `PresencesRenvois`), sans
  texte ; libellés verbatim dans `LibellesWeb` (`ListePresences`, `LignePresence`, `BlocPointage`, `EspaceSoignant`,
  garde Node au caractère près) ; textes que le web tutoie (vouvoyés), assemblages et textes opérationnels dans
  `Libelles/LibellesPresences.swift` (ajouté à `DOSSIERS_LOT2` de la garde). Écrans : `Screens/Presences/`
  (`PresencesScreen`, `BlocPointageView`, `PresenceAVenirRow`, `PresenceValideeRow`, `PresenceHistoriqueRow`) et
  `Screens/Profil/EspaceSoignantSection.swift`, insérée dans `ProfileScreen` après « Application » (déconnexion et
  sentinelle réseau, lues sans défilement par les XCUITest des lots 0 et 1, ne bougent pas). Consignes :
  - **T4b** : la zone de pointage est le point d'extension `FabriqueZonePointage` (`BlocPointageView.swift`), injecté par
    `.environment(\.fabriqueZonePointage, …)` au-dessus des onglets avec l'`Appareil` d'`AppContainer` ; la zone reçoit
    `ZonePointageContexte` (mission, fin prévue, action de la fenêtre, session) et possède le `PointageModel`
    (`@StateObject`, cycle de vie de la consigne T4b). T4b retire l'encart provisoire `pointage-zone-provisoire-<mission>`
    (`LibellesPresences.Provisoire.pointage`) et migre l'assertion de `DemoPresencesTests.testMesPresencesDepuisLeProfilOuvreAujourdhui`
    vers ses identifiants ; il ajoute les bandeaux hors ligne et sans GPS en tête de `PresencesScreen` et la ligne
    `profil-gps-consentement` dans `EspaceSoignantSection` ;
  - **T5a** : points d'entrée vers le détail — les cartes des blocs, des missions à venir et des lignes d'historique ne
    sont pas cliquables (le web ouvre `/soignant/missions/:id` et `/soignant/presences/mission/:id`) ; « Détail »
    (`presence-historique-detail-<ligne>`) est aujourd'hui un renvoi web (`PresencesRenvois.detail`), rendu seulement
    avec le présentateur de T10 : T5a le remplace par `DetailPresencesScreen`. Les missions de `demo-presences.json`
    n'existent pas dans `DemoMissionsGateway` : ouvrir `MissionDetailScreen` depuis un bloc afficherait « Mission
    indisponible » en démo ;
  - **T5b** : le panneau de contestation se monte dans `PresenceValideeRow` (sous la date) et dans
    `PresenceHistoriqueRow` (présence non validée et non reconstruite, sous la grille) ; aucun texte de délai (Q9) ;
  - **T7, T9a** : « Mes documents » et « Mes contrats » ouvrent `PlaceholderScreen(etat: LibellesPresences.Provisoire.etat)`
    (`placeholder-documents`, `placeholder-contrats`) ; chaque tranche remplace sa destination dans
    `EspaceSoignantSection`, retire son texte de `LibellesPresences.Provisoire` et migre
    `DemoPresencesTests.testMesDocumentsEtMesContratsProvisoiresJusquaT7EtT9a`. T9a remplace aussi le renvoi web de
    « Voir le contrat » (`pointage-voir-contrat-<mission>`, `PresencesRenvois.contrat`) par le contrat natif ;
  - **T10** : `PresencesScreen(…, parametreOnglet:, parametreFiltre:)` reçoit `?tab=` et `?filtre=` de la route
    `/soignant/presences` (aujourd'hui `.safari` dans `LinkRouter`) ; le bandeau « à valider »
    (`TextesWeb.Presences.bandeauAValider`, HARD STOP n°4 de TL, `presences-bandeau-a-valider`) ne s'affiche qu'avec ce
    filtre, donc pas avant T10. L'injection du présentateur fait apparaître « Voir le contrat », « Détail » et « Voir ou
    signaler un litige » : T10 remplace les absences affirmées par `DemoPresencesTests` par leur présence ;
  - **CI** : `LibellesPresencesTests` relit `src/pages/PresencesSoignant.tsx` et
    `src/components/pointage/BlocPointageMission.tsx`, absents des filtres `paths` d'`ios-swift-ci.yml` (comme
    `DocumentsSoignant.tsx` pour `MessagesDocumentsTests`) : un changement web de ces textes vouvoyés n'est vu qu'à la
    PR iOS suivante ; les libellés verbatim restent gardés par `validate-pr.yml` (garde Node). Ajout des deux chemins
    aux filtres à décider par l'intégrateur (fichier partagé).
- **T4b** (après T3) : `PointageModel` n'affiche aucun texte. `Issue.refuse(message:codeInvalide: true)` → forme
  vouvoyée de la décision 6, sinon le message serveur tel quel ; `.recuEnCours` → `RecuScan.messageRecuEnCours` ;
  `.suiviIllisible` → `RecuScan.messageIllisible` et renvoi web `/soignant/presences` ; `.horsLigne`,
  `.verification`, `.nonRecu`, `.enregistre` → textes du web (`PointageRotatifSoignant.tsx` l.143) ou à inventorier
  ici ; `.enregistreSurAutreMission(type, missionId:)` (revue fraîche de L2-T3, M-A) → même succès du web (l.143),
  puis rechargement de l'instantané des présences (le bloc de la mission pointée change d'état) ; toute précision sur
  la mission pointée est un texte opérationnel à inventorier ici ; `.suiviIllisible` couvre aussi un HTTP 200 sans
  preuve relue : son renvoi web est un bouton explicite (jamais une redirection automatique), et le modèle lève ce
  suivi au premier `charger()` réussi après une réapparition du bloc (seconde revue fraîche de L2-T3, mi-3) ;
  `.verification` peut se changer, au tic suivant, en l'issue conclue par un autre bloc (MJ-1) ; `envoiEnCours`
  retombe pendant la vérification d'une réponse perdue (mi-2) : le bouton reste désactivé par `peutEnvoyer` ;
  `sessionExpired` → écran de reconnexion du lot 1 ; `PointageRules.action` → libellés l.106-108.
  Cycle de vie (revue fraîche de L2-T3, M-B) : `.task { await model.charger(); await model.suivre() }` (l'un et
  l'autre réactivent le bloc : en SwiftUI, une vue poussée dans un `NavigationStack` sous un `TabView` reçoit
  `onDisappear` puis `onAppear` à chaque changement d'onglet et garde son `@StateObject`), `desactiver()` à la
  disparition, `reconcilier()` au retour au premier plan ; `charger()` ne relit rien pendant un envoi. La position est
  demandée par l'écran (consentement, `LocationPort`) et passée à `pointer(code:gps:)` ; nil = jamais demandée.
  `MetadonneesScan` ne s'affiche ni ne se journalise (ses descriptions masquent les coordonnées).
  `DemoPointageGateway.Scenario` (`scan-incertain`) est lu de `-JOLENE_DEMO_SCENARIO` par `AppContainer`.
- **T5a** (après T3) : `PointageModel.notationAProposer` ne tient pas la mémoire « une fois par mission et par
  utilisateur » (clé de la notation) ; `finLe` est celui de l'init du modèle, alors que le web relit `missions.fin_le`
  juste après la FERMETURE (`PointageRotatifSoignant.tsx` l.156) : T5a relit la fin prévue avant de proposer la note
  (revue fraîche de L2-T3, m6) ; aucune note n'est proposée par `.enregistreSurAutreMission` (la mission notée serait
  celle du code, pas celle du bloc) ; détail par `gateways.pointage.detail` (créneaux tous types, `resume` nil sur
  `{error}`) ; `relancerValidation` → `IssueRelance.envoyee(message: nil)` : repli du web « Établissement relancé. »
  (`DetailPresencesMission.tsx` l.122).
- **T6** : reçu par `ReceiptJournal<RecuDocument>(store: appareil.recus)` (domaine `document`, essai = `s3Cle`),
  mêmes règles que T3 ; `MimeDocument` est `Codable` dans sa déclaration (`Documents/ClassementDocument.swift`),
  ne pas y ajouter de conformité rétroactive.
- **T6** (seconde revue fraîche de T1) :
  - `RecuDocument.preparer(…, fichier:, libelle:, …)` garde dès la v1 le nom d'origine (`nomFichier` = `fichier.nom`,
    non blanc, ≤ 255 points de code) et le libellé saisi (`libelle`, ≤ 500), bornes de `fn_remplacer_document_soignant`
    (`public.sql` l.53114-53116). Le rejeu après arrêt forcé (objet présent, aucune ligne) repasse
    `p_nom_fichier: recu.nomFichier` et `p_libelle: recu.libelle ?? ""` (parité `DocumentsSoignant.tsx` l.386-388 :
    `libelle || ''`, `fichier.name`) : aucun écart de parité, aucune v2 du reçu. Un nom ou un libellé hors bornes est
    refusé par `preparer` (`RecuErreur.champInvalide`) avant tout envoi ; T6/T7 l'affichent avec le message du web
    pour `METADONNEES_DOCUMENT_INVALIDES` (`DocumentsSoignant.tsx` l.400-402), sans objet orphelin à nettoyer ;
  - `RecuErreur.illisible` (domaine `document`) : envoi bloqué, **voie de récupération** = renvoi web
    `/soignant/mes-documents?tab=justificatifs` par `PresentateurRenvoiWeb` (l'envoi web n'utilise pas ce journal) ;
    le reçu n'est jamais réécrit ni effacé par l'app.
- **Versions des reçus (T3, T6, lot 1 T7)** : une version N+1 d'un reçu relit la version N (son décodeur est
  conservé, l'essai en vol se termine avec la version lue, jamais réécrit dans une autre version) ; la version N ne
  relit jamais la N+1 (fail-closed). Un retour à un build antérieur (TestFlight) après qu'un build plus récent a écrit
  une version N+1 rend le reçu illisible : renvoi web du domaine jusqu'au retour au build récent, qui le relit et le
  réconcilie. L'élément Keychain survit à la réinstallation (`ThisDeviceOnly`) ; une remise à zéro explicite d'un
  reçu illisible n'est pas prévue au lot 2 : si la recette appareil (T12) rencontre ce cas, elle se décide alors,
  avec son texte (même règle que l'identifiant terminal, consigne T4b).
- **T4b** : la surcharge `P0002` affiche exactement la forme de la décision 6 (apostrophe ’).
- **T4b** (revue fraîche de T1) : une `JoleneError(.environment)` de `KeychainTerminalIdentity` s'affiche telle
  quelle dans le bloc de pointage, bouton désactivé. `messageVerrouille` et `messageIndisponible` : nouvel essai à
  la tentative suivante (aucun échec mémorisé). `messageIllisible` (valeur stockée hors format) : **voie de
  récupération** = renvoi web `/soignant/presences` par `PresentateurRenvoiWeb` (le pointage web n'utilise pas cet
  identifiant, `src/lib/terminal.ts`) ; l'élément `app.jolene.terminal` n'est jamais réécrit ni effacé par l'app
  (décision 7) et survit à la réinstallation (seul un effacement de l'appareil le retire). Une remise à zéro
  explicite de l'identifiant n'est pas prévue au lot 2 ; si la recette appareil (T12) rencontre ce cas, elle se
  décide alors, avec son texte.
- **Lot 1 T7** (annulation avec justificatif) : consomme le journal sans changer son API. Domaine `justificatif`,
  reçu conforme à `RecuDurable` (`attemptId`, `verifierSuccession(apres:)`, `estTermine`, encodage strict).
  `Receipts/RecuDurable.swift`, `Receipts/ReceiptJournal.swift` et `Keychain/KeychainReceiptStore.swift` ne
  dépendent d'aucun autre fichier du lot 2 : sur une base sans le lot 2, T7 les reprend octet pour octet ; le
  magasin y est injecté par son `AppContainer` (`Appareil.recus` est un champ du lot 2). Leurs tests s'appuient sur
  `RecuScan`, `RecuDocument` et le trousseau en mémoire de `KeychainTerminalIdentityTests` : T7 les rejoue avec
  son propre reçu. `RecuErreur.illisible` (domaine `justificatif`) : annulation avec justificatif bloquée dans
  l'app, **voie de récupération** = renvoi web `/soignant/missions/:id` (annulation depuis le détail web, qui
  n'utilise pas ce journal) par `PresentateurRenvoiWeb` ; règle des versions ci-dessus.
- **T7** (écrans des justificatifs, livré par T6 : `Documents/DocumentsModel.swift`, `DossierDocuments.swift`,
  `FichierDocument.swift`, `NormalisationImage.swift`, `ConsultationDocuments.swift`, `MessagesDocuments.swift`,
  `Demo/DemoDocumentsGateway.swift`, `JoleneSupabase/Documents/SupabaseDocumentsGateway.swift`) :
  - modèle `DocumentsModel(controller:snapshot:recus: appareil.recus)` ; tout fichier choisi passe par
    `FichierDocument.preparer(nom:type:octets:source:)` avant `envoyer(typeDocument:fichier:libelle:)` (HEIC/HEIF → JPEG
    sans métadonnée ; refus local avec le message du web, aucun reçu). `source` est **obligatoire** dans l'écran
    (revue fraîche de T6, m10) : `.phototheque` pour `PHPickerViewController` — toute image y est ré-encodée en JPEG sans
    métadonnée (ni GPS, ni EXIF, ni MakerNote), comme le web natif (Capacitor, qualité 80, `ModalTeleversement.tsx`
    l.144-154) ; `.camera` pour `UIImagePickerController` (`jpegData(0.8)`, pixels seuls) ; `.fichiers` pour
    `UIDocumentPickerViewController` (octets inchangés). Aucun écart de parité ;
  - types envoyables : `DossierDocuments.peutEnvoyer(typeDocument:maintenant: model.horloge.now())` — exigences
    affichées, cartes « Étudiant / interne en santé » (`typesComplementaires`, ordre et règle de
    `src/lib/documents-complementaires.ts`, textes du web `DocumentsSoignant.tsx` l.866-898) et bouton « Mettre à jour → »
    du bandeau d'expiration (`expirantBientot`, l.600-608) ; aucun écart de parité (revue fraîche de T6, m2) ;
  - cycle de l'écran : `charger()` à l'apparition, au tirer-pour-rafraîchir et au retour au premier plan (dossier lu
    d'abord, puis réconciliation du reçu en attente bornée à quatre lectures ; sans effet sur un envoi en vol) ;
    `arreterSuivi()` à la disparition (parité du démontage web, l.254 ; le suivi s'arrête aussi à la disparition du
    modèle) ; `oublierDossierComplet()` après la célébration (2,5 s sur le web, l.268-269), comme
    `oublierExigenceSuivante()` à l'ouverture de l'exigence proposée ;
  - instances multiples (seconde revue fraîche de T6, M1-bis) : le modèle vit avec l'écran (`@StateObject`), et un
    envoi lancé dans une tâche continue après sa fermeture. Plusieurs `DocumentsModel` d'un même utilisateur peuvent
    donc coexister (écran rouvert pendant un upload, deux fenêtres sur iPad, nouvel epoch de la même personne) : ils
    partagent le registre du processus `EssaisDocumentsEnVol` (implicite, aucun paramètre), seule garde du « un seul
    envoi » et de « une seule réconciliation ». Un modèle qui trouve l'envoi d'un autre en vol l'affiche
    `.enCours(typeDocument:)` (boutons d'envoi désactivés, comme pour son propre envoi), ignore tout nouvel envoi, ne
    le réconcilie jamais, puis en reprend l'issue (dossier relu, suivi du verdict) ;
  - attestation santé : `signerAttestation()` rend faux sans appel si `attestationSanteSigneeLe` est déjà posée (web :
    `canSign = … && !signedAt`, l.69) ; l'écran affiche alors `attestation-signee`, jamais « Signer » ;
  - textes des issues (aucun dans T6, hors messages levés par les ports) : `.verificationDemandee` → « Document téléversé
    — vérification en cours (~30 s). » (`DocumentsSoignant.tsx` l.428) ; `.enregistre` → « Document téléversé.
    Vérification manuelle en attente. » (l.419). Pendant le suivi, `.termine(.verificationDemandee(id))` devient
    `.termine(.enregistre(id))` dès que `verify-document` répond en erreur (429, 403, 503… : issue observée hors du
    chemin critique par `DocumentsPort.verificationEchouee(documentId:)`, aussitôt, comme le `.then` du web l.413-425 ;
    seconde revue fraîche de T6, m-d), quand le statut relu est `REVUE_MANUELLE_REQUISE` (503 `AI_NOT_CONFIGURED` ou
    erreur après le début de la tentative, `verify-document/index.ts` l.444-457, l.1360-1370) ou, en dernier filet,
    quand la pièce est encore `EN_ATTENTE` sans tentative après 60 s : T7 affiche alors le second message, comme le
    second toast du web (l.416-419 ; revue fraîche de T6, m11). Une réponse de `verify-document` relance aussitôt une
    relecture (le web recharge, l.420). Écart consigné : un verdict `REVUE_MANUELLE_REQUISE` rendu avec succès (IA en
    délai ou indisponible, l.653-710) donne aussi ce message, là où le web n'affiche que le badge de la carte ;
    `.verdictRendu` (ligne relue après un relancement, verdict déjà rendu : `VERIFIE`, `REJETE`, `EXPIRE`… ; seconde
    revue fraîche de T6, m-c) : aucun équivalent web, jamais « vérification en cours » ; T7 n'annonce rien de plus que
    le badge de la carte, ou un texte opérationnel inventorié comme ci-dessous ;
    `.refuse` `CHEMIN_DOCUMENT_INVALIDE` / `METADONNEES_DOCUMENT_INVALIDES`
    → `MessagesDocuments.enregistrementImpossible` ; `.refuse("STOCKAGE_<statut>")` : le web affiche « Téléversement
    impossible : » suivi du message brut de Storage (l.377), que le natif ne transporte pas ; `.nonEnvoye`, `.incertain`,
    `EtatEnvoi.recuEnCours` et `.suiviIllisible` n'ont pas d'équivalent web : textes opérationnels à inventorier dans
    « Textes opérationnels hors web » avec leur test (même règle que `RecuScan.messageRecuEnCours` / `messageIllisible`),
    `.suiviIllisible` avec le renvoi web `DocumentsModel.renvoiWeb` ;
  - `ConsultationDocuments.effacerTout()` à la fermeture de QuickLook et au changement d'epoch ;
  - démo : `-JOLENE_DEMO_SCENARIO upload-incertain` → `DemoDocumentsGateway(scenario: .uploadIncertain)` posé par
    `AppContainer` (DEBUG) ; `DemoWorld.gateways()` garde `.normal`.

- **T9a** (lecture, livrée par T8 côté données) : `ContratModel` (`JoleneCore/Contrats/ContratModel.swift`) et
  `ContratsListeModel` portent l'état ; bandeaux, compte à rebours, statut, pied de page, certificat et zone de
  signature par `ContratRules` (aucune règle locale à l'écran). `MotifOriginalIndisponible` → texte du web :
  `.cddAPreparer` → `TextesWeb.Contrat.cddAPreparer` ; autre motif → `originalIndisponible` si
  `ContratMissionUi.contratPossedeSignature`, sinon `contenuPasDisponible` ; `.renduRefuse(messageServeur:)` → les
  textes de rendu du web (`ContratMission.tsx` l.377, l.388, l.394, l.715) sont **absents de `LibellesWeb`** :
  T9a les y ajoute verbatim avec leur source (hors HARD STOP : aucune marque juridique) avant de les afficher.
  `FichierContratTemporaire.effacer(_:)` à la fermeture de la feuille de partage, `effacerTout()` au changement
  d'epoch. Démo : `demo-contrat-001` (62 h restantes), `demo-contrat-002` (signé, original partageable, deux lignes
  de certificat), `demo-contrat-003` (CDD sans original). Les originaux démo sont rendus par le moteur serveur
  (`rendreCddEmployeur` + `wrapInDocument`) : leur texte est celui du serveur, seules les données « employeur »
  sont fictives et le disent.
- **T9b** (HARD STOP, signature) : la session est `ContratModel.session` (`SessionSignatureOtp`) ; l'écran ne fait
  qu'appeler `accepter(_:)`, `saisirCode(_:)`, `envoyerCode()`, `signer()` et lire `etape`, `retour`,
  `erreurBloquante`, `secondesRestantes(maintenant: horloge.now())`, `tentativesRestantes`, `smsRestants` ;
  `ContratModel.signature == .renvoiWeb` (compte TEST sans admission) → renvoi web `/contrat/:id` (décision 18).
  `-JOLENE_DEMO_SCENARIO otp-expire` : `AppContainer` construit `DemoContratsGateway(scenario:
  ScenarioDemoContrats(argument:))` à la place du défaut de `DemoWorld.câblerLot2` (`.nominal`). T8 n'écrit aucun
  texte de consentement ni de signature : tous viennent de `TextesWeb.SignatureOtp` (TL).

## Amendements du blueprint (`LOT2_PLAN.md`)

Le blueprint versionné n'est pas réécrit ; ces écarts font foi.

| Passage du blueprint | Formulation initiale | Retenu | Motif |
|---|---|---|---|
| §3 B1 « Fichiers » ; §4, vague 0 | fiche « `nouveau_code` jamais lu » et garde de T0 « basculées dans la même PR » ; « B1 se merge **après** T0 », « B1 **après T0** » | B1 vise `main` et n'attend pas T0 ; fiche et garde basculent au merge de `main` dans `feat/ios-lot2` (« Ordonnancement et branches ») | revue fraîche de T0 : tant que le lot 2 n'est pas sur `main`, la PR B1 ne peut pas modifier deux fichiers qui n'y existent pas |
| §3 T0 (`RPC_POINTAGE_SYSTEME_1`) ; §1.2 « Système de pointage ① » | huit RPC | neuf RPC : + `fn_generer_code_secours_mission` | seconde revue fraîche de T0 : générateur du code de secours de ①, troisième chaîne de pointage à distance (décision 1 amendée) |
| §1.3 P10 (porte du lot 2) | « `unwiredPorts.isEmpty` » | `unwiredPorts.filter(Lot2PortsTests.portsLot2.contains).isEmpty` : aucun port du lot 2 non câblé, dans les deux mondes | revue fraîche de T1 : `unwiredPorts` nomme aussi les ports des lots suivants ; si le lot 3 est intégré avant la clôture du lot 2, `isEmpty` est faux pour le lot 2 lui-même (même règle que la clôture du lot 1, PRINCIPES §2) |
| §2.2 (`ReceiptStorePort` « lot 1 T7 », `KeychainReceiptStore` « (T7) ») ; §2.6 (« Le journal est celui de T7 ») ; §3 T1 « Dépendances » | journal et magasin Keychain livrés par lot 1 T7 | livrés par T1 du lot 2 (décision 23, « Application ») ; protocole `ReceiptStorePort` dans `Receipts/ReceiptJournal.swift`, champ `Appareil.recus` ; Keychain `AfterFirstUnlockThisDeviceOnly` (le pilote prenait `WhenUnlocked`) | T7 n'existe sur aucune branche ; une réponse reçue écran verrouillé doit encore se journaliser, et un reçu ne porte aucun secret |
| §2.4 et correction 10 (« seuls `URLError`, délai `bounded` et `HTTPError` sans corps PostgREST sont incertains ») | une `PostgrestError` décodée prouve un rollback | seule une `PostgrestError` dont le `code` est un SQLSTATE (`^[0-9A-Z]{5}$`, `RecuScan.sqlstateValide`) ou un code PostgREST émis avant toute transaction ou après son annulation (`PGRST000`, `PGRST002`, `PGRST003`, `PGRST1xx` sauf `PGRST103`, `PGRST111`, `PGRST112`, `PGRST2xx`, `PGRST3xx` : `RPCResponse.codePostgRESTSansTransaction`) le prouve ; `PostgrestError(code: nil)` (corps `{"message"}` d'une passerelle), `PGRST001`, `PGRSTX00` et tout autre code sont incertains ; classement par `RPCResponse.appelerMutation` (lot 2), le fichier partagé avec le lot 3 restant inchangé | revue fraîche de T1 : supabase-swift 2.55.5 décode tout corps d'erreur JSON à `message` en `PostgrestError`, `code` optionnel ; seconde revue fraîche : `PGRST001` (503) signale une connexion à la base cassée en cours de session, COMMIT compris, et une passerelle peut renvoyer un `code` texte ; PostgREST construit la réponse après le COMMIT, d'où `PGRST103` (plage 416), `PGRST111` et `PGRST112` (en-têtes et statut posés par la fonction) exclus de la liste blanche |
| §2.4 (statuts des stubs de test) | `42501` → 403, `23503` → 409, `P0001`, `22023`, `23514` → 400, autres `P0…` → 500 | + classes `40` (rollback de transaction) et `57` (dont `57014`, `statement_timeout`) → 500 | revue fraîche de T1 : statuts réels de PostgREST |
| §2.5 « Réconciliation » | preuve : `mission_id` = reçu, id hors baseline, même `id_terminal` | + `numero_scan > nb_scans_avant`, mission vérifiée par `RecuScan.reconcilier` lui-même (projection `PreuveScan` avec `mission_id`) ; relecture datée avant `started` (heure reculée) → verdict `horlogeIncoherente`, fail-closed, jamais « non reçu » ; §2.3 : `IssueScan.horlogeIncoherente` ajoutée, verdicts traduits par `IssueScan(reconciliation:)` (`.aRelire` → `.incertain`) ; reçu effacé après « non reçu » | revue fraîche de T1 : un oubli du filtre `mission_id` par la requête de T3 aurait donné un faux succès ; une horloge reculée laissait un `aRelire` sans fin ; seconde revue : `IssueScan` ne savait pas exprimer ce verdict et aucune phase terminale n'était atteignable après « non reçu » |
| §2.6 (`RecuDocument` v1 : `userId`, `epoch`, `s3Cle`, `typeDocument`, `mime`, `tailleOctets`, `documentId?`, `phase`) | aucun nom de fichier ni libellé | + `nomFichier` (nom d'origine, non blanc, ≤ 255 points de code) et `libelle?` (≤ 500), immuables pour un même essai | seconde revue fraîche de T1 : le rejeu de `fn_remplacer_document_soignant` exige `p_nom_fichier` non vide (`public.sql` l.53114) et perdrait le libellé saisi ; ajoutés dès la v1 pour ne pas imposer une v2 à T6 |
| §2.3 (`PointagePort`) | huit méthodes | + `preuvesScan(missionId:context:) -> [PreuveScan]` (projection `PreuveScan.colonnes`), défaut « non câblé » en extension du protocole | T3 : la base `preuvesAvant` du reçu (§2.5) doit être relue avant l'envoi et aucune méthode du port ne la rendait ; le défaut garde les doubles de test et le stub de T1 inchangés |
| §3 T3 « Fichiers » (`EtatPointage.swift`, `InstantanePresences.swift`) | `EtatPointage.swift` créé par T3 ; `InstantanePresences` décodé en `MissionRecord` | `EtatPointage` reste dans `Models/Lot2Results.swift` (posé et testé par T1, non redéfini) ; relecture qui confirme un scan dans `PointageRules.etatConfirme` ; `InstantanePresences` déplacé dans `Pointage/InstantanePresences.swift`, lignes `MissionPresenceLue`, `PresenceLue`, `MissionDePresence` décodées une à une (projections réduites : aucun montant, aucune colonne `code_pointage_*`) | consigne T3 de T2b (`profession_requise` absent du select du web, `statut` NULLable) ; gap « B1-ter » de la migration B1 |
| §2.4 (`fn_scanner_code_pointage`, succès) | réponse avec le code suivant et sa signature | deux formes décodées à l'identique : celle d'après B1 (`fix/scanner-code-sans-code-suivant`) et celle d'avant ; `fn_declarer_fin_retroactive` (même retrait par B1) n'est pas appelée par le natif | B1 validée par Gabrielle, dans la chaîne de merge sériel |
| §2.3 (`IssueScan`) ; §2.5 « succès → relecture etat + scans_pointage » | succès relu sur la mission du reçu, sinon incertain | + `IssueScan.enregistreSurAutreMission(missionId:typeScan:numeroScan:)` (ligne du scan relue sans filtre de mission par `creneau_effectif_id` et `numero_scan`, état de sa mission confirmé) et `IssueScan.accepteSansPreuve` (HTTP 200 non confirmé) ; un HTTP 200 n'est jamais `.incertain` ni réconcilié ; `PointageModel.Issue.enregistreSurAutreMission` | revue fraîche de T3 (M-A) : la RPC trouve la mission par le seul code ; un 200 relu sur la seule mission du reçu finissait en « non reçu » et invitait à pointer une seconde fois |
| §2.5 « absent → « non reçu » seulement si la relecture a lieu ≥ 8 s après `started` » | 8 s | 8 s, et pour un essai sorti sans réponse : instant de sortie (au moins le délai `bounded`) + 10 s (pool PostgREST) + 8 s, monotones | revue fraîche de T3 (m2) : PostgREST peut encore valider pendant l'attente du pool puis le `statement_timeout` |
| §3 T3 (`PointageModel` : « réponse ignorée si l'écran ou l'epoch a changé ») | écran disparu → modèle inerte | `activer()` (et `charger()`, `suivre()`) réactive le bloc ; génération : une opération d'avant la disparition ne publie rien, une issue décidée solde quand même le reçu (même epoch) | revue fraîche de T3 (M-B) : en SwiftUI, le `@StateObject` survit à un changement d'onglet |
| §2.3 (`PointagePort`) | `scanner` : requête et relectures en un appel, borné en bloc par le modèle | + `envoyerScan(code:metadonnees:recu:context:) -> EnvoiScan` et `relireScanAccepte(_:recu:context:) -> IssueScan`, défauts en extension ; `scanner` conservé (les deux moitiés enchaînées) | seconde revue fraîche de T3 (mi-1) : un HTTP 200 tardif suivi de relectures pouvait dépasser le délai et finir en « non reçu » |
| §2.5 « transport → réconciliation immédiate par relecture » | appliqué tel quel | première relecture immédiate ; « non reçu » relu avant l'attente monotone → « à relire » ; vérification menée hors de l'envoi (`envoiEnCours` retombé) | seconde revue fraîche de T3 (mi-2) : l'attente précédait toute relecture et neutralisait `charger()` |
| §2.6 (`RecuScan` : « un second reçu pour le même utilisateur tant que le premier n'est pas réconcilié » refusé) | reçu réconcilié par le bloc qui l'affiche | reçu réconciliable par tout bloc (un modèle à la fois), issue transmise au bloc de la mission du reçu, vérification levée quand l'essai est soldé | seconde revue fraîche de T3 (MJ-1) : un bloc restait figé en vérification quand un autre soldait le reçu commun |
| §2.5 « Justificatif » (`started → stored → registered → verification_demandee`) | chaque phase journalisée | `DocumentsModel` journalise `prepared` puis `started` AVANT l'unique `DocumentsPort.envoyer` (port de T1 : un seul appel), puis efface le reçu sur toute issue relue autre que `.incertain` ; un reçu `prepared` orphelin → `not_sent` puis effacé, sans appel ; un reçu en vol → réconcilié avant tout nouvel envoi. « Une seule fois » pour `verify-document` : appelé seulement juste après un `fn_remplacer_document_soignant` accepté par CETTE requête ; une ligne relue par `s3_cle` interdit toute vérification automatique (`.enregistre` → « Revérifier ») | T6 : la gateway n'a pas accès au journal (`Appareil.recus`) ; la relecture serveur rend les phases intermédiaires inutiles à la reprise. Répond au mineur M2 de la revue de T1 (`REVUES_LOT2.md`) |
| §2.5 réconciliation (« `resultat_ia` ou `verification_attempt_id` non nuls ») | `resultat_ia` lu | vérification engagée = statut ≠ `EN_ATTENTE` ou `verification_attempt_id` non nul (`PreuveDocument`) ; `resultat_ia` jamais lu (seule `profession_certifiee` l'est, projection du web) | minimisation (identité extraite par l'IA) ; sans effet sur « aucun appel » : une ligne présente n'en déclenche jamais |
| §3 T6 « `createSignedURL(path:expiresIn: 3600)` + audit » | URL signée | `download(path:)` sous le JWT (même politique SELECT), copie temporaire protégée, puis le même audit `DOCUMENT_CONSULTATION` (`p_cle_s3` compris) | l'app n'ouvre pas de lien : aucune URL signée créée ni gardée |
| §3 T6 attestation (« `fn_signer_attestation_sante` ») ; profil (« `prenom, nom` ») | audit client `ATTESTATION_SANTE_SIGNEE` du web ; `prenom`, `nom` lus | aucun audit client (le serveur écrit déjà `ATTESTATION_SANTE_SIGNEE`, l.56335-56352) ; `prenom`, `nom` non lus | doublon d'audit (même règle que `fn_creer_notification`, décision 9) ; données non affichées par la page |
| §3 T6 `NormalisationImage` (« taille ≤ 10 Mo sinon réduction ») ; fixture « `une-image.heic` produite par `sips` » | réduction pour toute image | toute image ré-encodée en JPEG sans métadonnée (qualité 0,8, puis une réduction à 4 096 px et qualité 0,6 au-delà de 10 Mo, puis refus avec le message du web) : un HEIC/HEIF quelle que soit sa source, et toute image de la photothèque (`FichierDocument.preparer(…, source: .phototheque)`, JPEG, PNG et WebP compris, revue fraîche de T6, m10) ; depuis Fichiers ou l'appareil photo, un JPEG/PNG/WebP/PDF n'est jamais ré-encodé (octets inchangés) et, au-delà de 10 Mo, il est refusé avec le message du web ; un PDF ne l'est jamais ; fixture HEIC écrite par ImageIO (GPS et orientation 6), empreintes figées par `NormalisationImageTests` | « PNG/JPEG/PDF inchangés » (tests du blueprint) depuis Fichiers ; photothèque : jamais d'EXIF ni de GPS jusqu'à Storage et à l'IA, comme le web natif (Capacitor, qualité 80) ; `sips` ne sait pas poser de GPS ; ligne mise à jour par la seconde revue fraîche de T6 (m-i) |
| `PRINCIPES.md` l.107-114 (« les modèles d'écran bornent leurs lectures et mutations au même délai ») ; §2.3 (« tous bornés par `bounded(timeout: resolutionTimeout)` ») ; §2.5 (`verify-document` puis relecture avant le verdict) | 15 s pour tout appel de port des justificatifs ; `verify-document` attendu dans l'envoi | upload, revérification et consultation bornés par `DocumentsModel.delaiTransfert(octets:)` = max(120 s ; 30 s + taille ÷ 50 000 o/s), soit ≈ 240 s pour 10 Mo, jamais moins que `resolutionTimeout` ; réconciliation (ligne relue, HEAD, rejeu de l'enregistrement, nettoyage best-effort : aucun transfert) bornée à `DocumentsModel.requetesReconciliation` (4) fois `resolutionTimeout`, soit 60 s, et lancée APRÈS la lecture du dossier par `charger()` (seconde revue fraîche de T6, m-b) ; lecture du dossier, préparation du reçu, cohérence, revue et attestation restent à 15 s ; `verify-document` lancé une fois par une tâche non structurée (ni bornée ni annulée par l'appelant), jamais attendu par l'envoi, son issue observée hors du chemin critique (`DocumentsPort.verificationEchouee`, m-d), verdict relu dans la ligne par le suivi (parité `DocumentsSoignant.tsx` l.410-426). Un délai dépassé reste incertain et impose la relecture (PRINCIPES §3-§4) | revue fraîche de T6 (M2) : l'edge sonde 10 s puis appelle l'IA 20 s (`index.ts` l.286-287, l.625-626) et le web annonce « ~30 s » ; un upload de 3 Mo à 1,5 Mbit/s (≈ 16 s) était annulé à 15 s puis réconcilié « non envoyé » à chaque essai, et `verify-document` annulé côté client ; seconde revue (m-b) : la réconciliation, bornée comme un transfert (≥ 120 s) et lancée avant la lecture du dossier, pouvait laisser l'écran plusieurs minutes en chargement |
| §2.5 « un envoi à la fois » ; réconciliation « au lancement, retour au premier plan, ouverture de l'écran » | garde lue dans l'état publié (`envoi == .enCours`) | registre du processus `EssaisDocumentsEnVol` (main actor), une entrée par `CleRecu` (domaine `document`, utilisateur) : l'envoi y est inscrit AVANT le reçu `prepared` et retiré par sa propre tâche à sa fin ; aucune instance de `DocumentsModel` ne réconcilie tant qu'un envoi est inscrit pour l'utilisateur, ni n'en lance un second (elle affiche l'envoi en vol `.enCours`, puis en reprend l'issue) ; une seule réconciliation à la fois par utilisateur, partagée par toutes les instances (les appelants suivants attendent la même, chacun en applique le résultat) ; l'issue d'une réconciliation n'est jamais publiée pendant un envoi ; un reçu qui ne s'efface pas après son issue garde l'envoi bloqué (`.suiviIllisible`) ; aucun état d'erreur ni de session publié pour un epoch quitté | revue fraîche de T6 (M1) : un `charger()` pendant l'upload réconciliait le reçu de l'envoi en vol (« non envoyé » prématuré, ou second `verify-document` pour le même `document_id`) et l'issue publiée de l'étape 1 levait la garde ; seconde revue (M1-bis, m-f) : le drapeau privé `envoiEnVol` ne protégeait qu'une instance, alors que le reçu est partagé par le processus (écran rouvert pendant l'upload, deux fenêtres iPad : réconciliation et `cleanup_orphan` de l'essai en vol, deux vérifications) |
| §2.5 réconciliation (« objet absent → `not_sent` ») | reçu effacé, rien d'autre | + `cleanup_orphan` best-effort, une fois, juste après le HEAD (sans effet sur un objet absent ou déjà référencé). Portée limitée : il ne rattrape qu'un objet devenu visible entre le HEAD et lui, jamais un objet que le serveur finit d'écrire plus tard (l'upload annulé par le délai a pu être reçu en entier) : celui-ci reste non référencé (limite connue, aucun second HEAD différé) | revue fraîche de T6 (m7) ; portée corrigée par la seconde revue (m-e) : le texte précédent promettait de rattraper un upload terminé après le HEAD |
| §2.5 (« réponse perdue → réconciliation ») ; échec d'upload | « requête jamais partie » ⇒ `not_sent` | « non envoyé » seulement pour `cannotFindHost`, `cannotConnectToHost`, `dnsLookupFailed` ; `notConnectedToInternet` (-1009), comme tout autre échec de transport, est incertain et tranché par le HEAD | seconde revue fraîche de T6 (m-g) : sur iOS, -1009 peut survenir en cours de transfert ; le reçu était effacé et l'objet pouvait rester orphelin |
| §2.5 réconciliation (issue d'une ligne relue) | vérification engagée → `verification_demandee` | issue dérivée du statut relu (`PreuveDocument.issue`) : `EN_ATTENTE` avec tentative → `.verificationDemandee` (suivi) ; `REVUE_MANUELLE_REQUISE`, ou aucune tentative → `.enregistre` ; verdict déjà rendu (`VERIFIE`, `REJETE`, `EXPIRE`…) → `.verdictRendu` (nouvelle issue, sans suivi) | seconde revue fraîche de T6 (m-c) : après un relancement, une pièce déjà jugée aurait été annoncée « vérification en cours (~30 s) » |
| §3 T6 consultation ; projection documents (« sans `s3_bucket` ») | clé `<uid>/documents/…`, bucket `jolene-documents` fixe | garde de la politique Storage (premier segment = uid, segments non vides, sans `..` ni `\`), bucket lu dans `s3_bucket` (projeté), `jolene-documents` à défaut ; jeton refusé (PostgREST `PGRST301`-`PGRST303`, `NON_AUTHENTIFIE`, Storage `InvalidJWT`, HTTP 401) → session expirée, jamais un refus ordinaire ni un nettoyage | revue fraîche de T6 (m1, m5) : les pièces encore actives envoyées avant 02e957ea (`<uid>/<TYPE>/<ms>_<nom>`) devenaient « Impossible d’ouvrir le document » ; une session expirée nettoyait l'objet puis rendait un refus |
| correction 21 (« un envoi `AUTRE` est impossible par l'interface ») ; `peutEnvoyer` « exigence affichée » | exigences affichées seulement | + documents complémentaires étudiant / interne visibles (`ComplementairesVisibles`, règle de `src/lib/documents-complementaires.ts`) et pièces du bandeau « expire bientôt » ; pièces de santé toujours exclues | revue fraîche de T6 (m2) : `ATTESTATION_SCOLARITE`, `LICENCE_REMPLACEMENT`, `CARTE_ORDRE` (l.851-900) et « Mettre à jour → » (l.606) étaient refusés |
| §3 T8 « détail : `contrats_mission` complet » (`select('*')` du web) | toutes les colonnes | projection explicite `ContratDetail.colonnes` (17 colonnes lues par `ContratMission.tsx`), jamais `signature_image_*`, `signature_ip_*` ni `signature_navigateur_*` | T8 : moindre donnée, aucune image en base64 décodée pour rien ; même règle que la correction 22 |
| §3 T8 certificat « projection **exacte** de `CertificatSignature.tsx` l.50 » | 13 colonnes du web | les 14 colonnes accordées (`SignatureCertificat.colonnes` de T1, `contrat_id` en plus, GRANT l.86518-86570) | T1 : `contrat_id` permet d'écarter une ligne d'un autre contrat ; aucune colonne non accordée |
| §3 T8 `OriginalContrat.swift` (motifs `hash_mismatch`, `storage_mismatch`, `variables_non_rendues`, `non_fige`) | quatre motifs | + `signatureMismatch` (pilote `business.ts` l.43-44 : signature ou OTP validé sur une autre empreinte), `cddAPreparer` (décision 19), `renduRefuse(messageServeur:)` (edge ≠ 200) ; chemin hors `<contratId>/<nom>.html` ou objet > 2 Mo → `storageMismatch` | T8 : un original n'est jamais supposé ; refus porté par l'erreur typée `ContratOriginalIndisponible`, protocole `ContratsPort` inchangé |
| §3 T8 `envoyerOtp(contratId:, empreinte:, …)` | un appel `fn_envoyer_otp_signature` | relecture `contrats_mission?select=id,hash_document` **avant** l'appel : empreinte différente → refus local `HASH_DOCUMENT_CHANGE` (bloquant), aucun SMS | T8 : un SMS (3 par 24 h) ne doit pas partir pour une révision que la signature refuserait (l.56563) |
| §2.8 « `demo-contrat-001.html` » | un original démo | + `demo-contrat-002.html` (original du contrat `SIGNE_COMPLET`) | T8 : le partage d'un contrat signé (T9a) exige un original contrôlé |
| §3 T8 « `ContratModels.swift` » ; `Models/Lot2Results.swift` | types posés par T1 dans `Lot2Results.swift` | `ContratResume`, `ContratDetail`, `OriginalContrat` déplacés dans `Contrats/ContratModels.swift` (champs additifs, inits de T1 conservés) ; issues OTP et `SignatureCertificat` restent dans `Lot2Results.swift` | en-tête de `Lot2Results.swift` (« le déplace dans son dossier ») |
| Revue fraîche de T2, constats 2, 3 et 7 | URL STAGING comparée exactement ; nom de RPC et clé non prouvés ; `AdmissionSignatureRecette` en doublon d'`AdmissionOtp` | `AdmissionRecette.origine(_:)` (barre finale, chemin, casse ignorés) et `lire(projet:…)` ; `SupabaseContratsGatewayTests` vérifie RPC et `p_contrat_id` ; type unique `AdmissionSignatureRecette` (`AdmissionOtp` n'a jamais été créé) | T8 |
| Tri `cree_le` de la liste (web `order('cree_le', { ascending: false })`) | — | `order=cree_le.desc.nullsfirst` (supabase-swift ajoute toujours la clause NULLS ; NULLS FIRST est le défaut PostgreSQL de `DESC`) ; certificat `cree_le.asc.nullslast` | T8 : même tri que le web |
| §3 T4a « Fichiers » | `PresencesScreen`, `BlocPointageView`, `PresenceHistoriqueRow`, `PresenceValideeRow`, `EspaceSoignantSection`, `ProfileScreen` ; aucun modèle Core nommé | + `Pointage/PresencesModel.swift`, `Pointage/PresencesAffichage.swift` (sans texte), `Libelles/LibellesPresences.swift`, `Screens/Presences/PresenceAVenirRow.swift` ; libellés verbatim dans `LibellesWeb` ; `PlaceholderScreen` gagne `etat` (défaut « Disponible au lot 1 », inchangé pour le lot 0) | T4a : `PresencesModelTests` exige un modèle testable ; un texte que le web tutoie ne peut pas être verbatim dans `LibellesWeb` (égalité au caractère près et test du vouvoiement) |
| §3 T4a identifiants | `presences-empty-<onglet>` | `presences-empty-avenir`, `-actives`, `-aujourdhui`, `-historique` (suffixes des onglets `presences-tab-*`) ; + `presences-loading`, `presences-refresh-error`, `presences-session-expired`, `presences-session-check`, `presences-bandeau-a-valider`, `presence-avenir-<mission>`, `presence-validee-<presence>`, `presence-historique-detail-<ligne>`, `presence-historique-litige-<ligne>`, `pointage-zone-provisoire-<mission>`, `profil-espace`, `placeholder-documents`, `placeholder-contrats` | T4a : chaque contrôle ou état atteint par un XCUITest porte un identifiant (PRINCIPES §6) |
| §3 T4a « BlocPointageView » (carte mission) ; « PresenceHistoriqueRow » (ligne) | carte et ligne ouvrent la mission (web l.57, l.685) | non cliquables jusqu'à T5a ; « Détail », « Voir ou signaler un litige » et « Voir le contrat » : renvois web rendus seulement avec le présentateur de T10 | gap verrouillé : en démo, le détail d'une mission de `demo-presences.json` est introuvable ; aucun bouton sans effet avant T10 |
| `PresencesSoignant.tsx` l.722-726 (« Code : … » d'une présence) | code de pointage de la présence affiché | non affiché | aucune colonne `code_*` n'est lue (gap « B1-ter » de la migration B1, projection `PresenceLue`) |
| `PresencesSoignant.tsx` l.459-477 (écran d'erreur) | une relecture en échec affiche l'écran d'erreur (`isError`) | présences gardées, encart `presences-refresh-error` ; écran d'erreur au premier chargement seulement | règle du lot 1 (`AccueilModel`, `MissionsListModel`) : jamais de démontage sur un rafraîchissement |

## Critères du plan amendés (`docs/PLAN_APP_NATIVE_SWIFT.md` §5 « Lot 2 »)

Le critère P10 de la porte du blueprint (§1.3) est amendé dans « Amendements du blueprint » ci-dessus :
`unwiredPorts.filter(Lot2PortsTests.portsLot2.contains).isEmpty` remplace `unwiredPorts.isEmpty`.

| Ligne du plan | Formulation initiale | Critère retenu | Décision |
|---|---|---|---|
| l.62 | « deux systèmes … Les deux doivent être reproduits » | seul le système rotatif est porté ; ① interdit par garde | 1 |
| l.180 | pointage par `fn_pointer_*`, QR `fn_generer_qr_mission` / `fn_valider_scan_qr`, file hors ligne, « PDF serveur » | `fn_scanner_code_pointage` seul, pauses par alternance, code de secours = six chiffres, aucune file ; HTML serveur contrôlé | 1, 2, 3, 17 |
| l.183 | QR `fn_generer_qr_mission` accepté ; précision « comparée à une présence issue de la coquille » | P2 (QR rotatif, niveaux 1 et 5) ; P3 (clés `p_metadata` + précision relue sur STAGING) | 1, 21 |
| l.186 | « File hors-ligne testée … QR expiré jamais remis en file » | P6 : aucun scan mis en file ni rejoué, réconciliation par relecture | 2 |

## Textes opérationnels hors web (T1)

Textes affichables, non juridiques (aucune marque de `MARQUES_JURIDIQUES` de
`scripts/mobile/check-textes-juridiques-ios.mjs`), sans ligne web à reprendre verbatim : le web n'a ni journal de
reçus ni trousseau (`src/lib/terminal.ts` recalcule une empreinte navigateur à chaque appel). Vouvoiement ;
aucun ne cite de valeur stockée. Gardés mot pour mot par les tests indiqués.

| Constante | Texte | Source | Test |
|---|---|---|---|
| `RecuScan.messageRecuEnCours` | « Un autre pointage doit être réconcilié avant de continuer. » | pilote `mobile-native/src/workflows/presence/attemptJournal.ts` l.71, repris tel quel | `RecuScanTests` |
| `RecuScan.messageIllisible` | « Le suivi sécurisé du pointage ne peut pas être vérifié. Aucun nouveau scan ne peut être envoyé. » | pilote `attemptJournal.ts` l.16, repris tel quel | `RecuScanTests.testAllerRetourEtRelectureFailClosed` |
| `KeychainTerminalIdentity.messageVerrouille` | « Le trousseau de cet appareil est verrouillé. Déverrouillez l'appareil puis réessayez. » | nouveau (T1, revue fraîche) : `errSecInteractionNotAllowed`, transitoire | `KeychainTerminalIdentityTests.testTextesOperationnelsInventories` |
| `KeychainTerminalIdentity.messageIndisponible` | « L'identifiant de cet appareil n'a pas pu être lu. Le pointage est momentanément indisponible : réessayez. » | nouveau (T1) ; remplace « … redémarrez l'application. », faux pour une valeur illisible | idem |
| `KeychainTerminalIdentity.messageIllisible` | « L'identifiant de cet appareil est illisible. Le pointage n'est pas disponible dans l'application sur cet appareil : pointez depuis jolene.app. » | nouveau (T1, revue fraîche) : valeur stockée hors format, jamais réécrite ; recours web (consigne T4b) | idem |
| `PointageModel.messageEtatIndisponible`, `PointageQuery.fallbackEtat` | « Impossible de charger son état. » | web `PointageRotatifSoignant.tsx` l.86, repris tel quel (T3) | `PointageModelTests`, `SupabasePointageGatewayTests` |
| `PointageQuery.fallbackRelance` | « Relance impossible. » | web `DetailPresencesMission.tsx` l.123, repris tel quel (T3) | `SupabasePointageGatewayTests.testDetailCarteMasqueeSurErreurEtRelanceVerbatim` |
| `PointageQuery.fallbackPresences` | « Impossible de charger vos présences. Réessayez. » | nouveau (T3) : échec de lecture, modèle des replis du lot 1 | `SupabasePointageGatewayTests` |
| `PointageQuery.fallbackScan` | « Impossible d'enregistrer le pointage. Réessayez. » | nouveau (T3) : rollback prouvé hors exceptions déclarées (repli de `SupabaseErrorMapping`) | `SupabasePointageGatewayTests.testRollbacksHorsListeEtContrat` |
| `PointageQuery.fallbackLocalisation` | « Impossible d'enregistrer votre choix de localisation. Réessayez. » | nouveau (T3) : `fn_consentir_gps` en échec ou relecture vide (aucune hypothèse locale) | `SupabasePointageGatewayTests.testConsentementLuPuisEnregistreEtRelu` |
| `PointageQuery.fallbackDetail` | « Impossible de charger le détail des présences. Réessayez. » | nouveau (T3) : repli de la synthèse serveur, jamais affiché (carte masquée) | `SupabasePointageGatewayTests` |

## Textes opérationnels hors web (T4a)

Non juridiques (aucune marque de `MARQUES_JURIDIQUES`), vouvoyés ; `LibellesPresences.swift` est dans `DOSSIERS_LOT2`.
Les libellés repris tels quels du web sont dans `LibellesWeb` (`ListePresences`, `LignePresence`, `BlocPointage`,
`EspaceSoignant`), gardés au caractère près par `tests/node/textes-juridiques-ios.node.mjs`. Les textes que le web
tutoie sont vouvoyés, seule la personne change (décision 9 du lot 1) : sous-titre de la page (l.515), titre de
l'erreur (l.467), descriptions des quatre états vides (l.565, l.588, l.611, l.764), motif « Aucun créneau planifié »
(`BlocPointageMission.tsx` l.105) ; `LibellesPresencesTests` relit chaque source web. Les titres « Session à
vérifier » et « Vérifier ma session » sont ceux de l'Accueil du lot 1 (`AccueilScreen`).

| Constante | Texte | Source | Test |
|---|---|---|---|
| `LibellesPresences.EspaceSoignant.titreSection` | « Mon espace » | décision 24 du lot 2 (section du Profil ; aucune page web ne regroupe ces trois écrans) | `LibellesPresencesTests.testTextesOperationnelsInventories` |
| `LibellesPresences.Provisoire.etat` | « Disponible au lot 2 » | provisoire (forme de l'onglet provisoire du lot 0), retiré par T4b, T7 et T9a | idem |
| `LibellesPresences.Provisoire.pointage` | « Le pointage dans l'application arrive avec la suite du lot 2. » | provisoire, retiré par T4b | idem |
| `LibellesPresences.Provisoire.documents` | « Vos justificatifs arrivent dans l'application avec la suite du lot 2. » | provisoire, retiré par T7 | idem |
| `LibellesPresences.Provisoire.contrats` | « Vos contrats arrivent dans l'application avec la suite du lot 2. » | provisoire, retiré par T9a | idem |

## Textes opérationnels hors web (T8)

Non juridiques (aucune marque de `MARQUES_JURIDIQUES`), vouvoyés, repris tels quels de leur source ; T8 n'ajoute
aucun texte de consentement, de signature ni de contrat (HARD STOP n°4 : tous viennent de `TextesWeb`).

| Constante | Texte | Source | Test |
|---|---|---|---|
| `MessagesContrats.indisponible` | « Les contrats ne peuvent pas être chargés. Réessayez. » | pilote `mobile-native/src/workflows/contracts/supabaseGateway.ts` l.21 | `ContratModelTests`, `SupabaseContratsGatewayTests` |
| `SupabaseContratsGateway.messageSignatureNonConfirmee` | « La signature ne peut pas être confirmée. Rechargez son état ; ne renvoyez pas automatiquement le code. » | pilote `supabaseGateway.ts` l.263 | `SupabaseContratsGatewayTests.testSuccesNonConfirmeParLaRelectureNEstPasUnSucces` |
| `FichierContratTemporaire.messageIndisponible` | « Aucun contrat téléchargeable pour le moment. » | web `src/pages/ContratMission.tsx` l.428 | `OriginalContratTests` |

Écart assumé : sans `telephone_masked` ni `expire_dans_minutes` dans un succès d'envoi, la session annonce « Code
envoyé au numéro masqué. Valide 10 min. » (`LibellesWeb.SignatureOtp.numeroMasque`, l.296, et la durée du minuteur,
l.145) là où le web afficherait `undefined`.

## En attente de Gabrielle

Rien de ce qui suit n'est implémenté par les tranches iOS ; chaque point bloque seulement la tranche indiquée.

### HARD STOP n°4 (juridique exposé à l'utilisateur)

- **TL** : validation écrite des textes juridiques et de consentement listés avec leur source dans la PR TL
  (consentement GPS et retrait, attestation santé avec la mention de l'art. 441-7 du Code pénal, bandeaux et mentions
  du contrat, art. 1366-1367 du Code civil, art. L.1242-12 du Code du travail, `MESSAGES_ERREUR`, compte à rebours
  72 h, certificat) avant que T4b, T7, T9a et T9b soient déclarées livrées, ainsi que T4a pour le bandeau du filtre
  « à valider » (`TextesWeb.Presences.bandeauAValider`, affiché par `PresencesScreen` avec `?filtre=a_valider`, donc
  atteignable seulement après T10). Les textes tutoyés du web restent verbatim tant qu'un wording vouvoyé n'est pas
  validé.
- **T9b** (écran de signature OTP) : go explicite avant merge (captures xcresult des trois formats, liste des textes).
- **T5b** (contestation depuis une présence) : go explicite avant merge.
- **Décision Q9 — délai de contestation** (sources primaires : `PanneauContestation.tsx` l.43-46 et l.347, l.354,
  l.394 ; `fn_fenetre_contestation_ouverte` l.36600-36622 ; `fn_litiges_escalader_auto` l.40712, l.40726-40730 ;
  `PageCGU.tsx` l.114-115). Le web affiche 72 h, le serveur applique `parametres_litiges.delai_contestation_pointage_h`,
  défaut **48 h**, et la « CGU §4.6 » invoquée ne fixe aucun délai de contestation. Recommandation soumise (non
  implémentée) : aligner `delai_contestation_pointage_h` sur 72 h par une PR de paramétrage séparée (`INSERT … ON
  CONFLICT (cle) DO UPDATE`, B9 données prod) et retirer côté web la phrase d'escalade « l'admin plateforme
  tranchera » (fausse en salarié), sans la remplacer tant qu'aucun texte n'est validé.
- **P9** : revue sur iPhone des écrans de consentement GPS, d'attestation santé et de signature avant de déclarer le
  lot livré.

### B9 (PR préparées et poussées, jamais mergées sans go)

- **B1** — `fn_scanner_code_pointage` sans `nouveau_code` ni `nouveau_hmac` (fonction `SECURITY DEFINER`, depuis la
  définition live) ; bascule de la fiche et de la garde de T0 : « Ordonnancement et branches ». La PR B1
  (`fix/scanner-code-sans-code-suivant`) couvre aussi `fn_declarer_fin_retroactive` : même retrait de `nouveau_code`
  et `nouveau_hmac` de sa réponse (le soignant assigné peut l'appeler lui-même en PostgREST) et verrou de sa garde
  d'autorisation, qui vaut NULL pour un compte sans lien avec la mission. **Mergée sur `main`** après le go du
  8 novembre 2026 (#1117) ; fiche et garde basculées dans `feat/ios-lot2` le même jour.
- **S1** — allocateur STAGING de capacité SMS de signature (`scripts/ci/allouer-capacite-sms-signature-staging.mjs`,
  workflow protégé) : secrets STAGING, fonctions `SECURITY DEFINER` du supplément, données.
- **T11** — go au dispatch du workflow STAGING du lot 2 et du mode `--appareil` de sa fixture pour T12 (secrets
  service_role et comptes TEST exposés à l'environnement protégé, création et nettoyage de données STAGING).
- **Go du 8 novembre 2026** : les PR B9 du 3 novembre — B1 du lot 2 (scanner, `fix/scanner-code-sans-code-suivant`),
  B3 du lot 3 (contestation de paiement, `fix/contestation-paiement-soignant`), B4 (score de matching, B1 du lot 4,
  `fix/score-matching-inconnu-null`), B5b du lot 5 (visibilité établissement par permission,
  `fix/visibilite-etablissement-par-permission`) et S1 du lot 2 (allocateur SMS, `feat/staging-capacite-sms-signature`)
  — ont reçu le go de Gabrielle le 8 novembre 2026 et passent en merge sériel sur `main` (CI verte et revue fraîche B8
  clôturable, par la file de merge de la session principale : `LOTS_2_5_DECISIONS`, règle 5).
- **Système ① toujours appelable** (constat T0 sur le dump `public.sql`, RLS/auth) : les neuf RPC ① de
  `RPC_POINTAGE_SYSTEME_1` (décision 1 amendée) ne sont plus montées côté web, mais gardent le `GRANT … TO
  authenticated` en production (l.81953, l.83013, l.83079, l.83997, l.84003, l.84009, l.84015, l.85495, l.85523) :
  PostgREST les sert à tout compte connecté. Avec les gardes NULL de `fn_codes_pointage_mission`,
  `fn_generer_qr_mission` et `fn_generer_code_secours_mission`, elles permettent à un soignant de **pointer à
  distance** (chaînes et verdicts : renvoi « Gardes NULL » ci-dessous). Les fiches ① de `CONTRATS_RPC_SOIGNANT.md`
  les décrivent comme mortes côté web : elles restent appelables.
  **Proposition** (PR backend séparée, B9, depuis la définition live, garde-fou 9.0 n°2) : `REVOKE EXECUTE ON
  FUNCTION … FROM authenticated` sur les neuf RPC ①, `fn_generer_code_secours_mission` comprise, après vérification
  que `SyncHorsLigne` (monté par `LayoutApp.tsx`, rejoue `fn_pointer_*` depuis `src/lib/horsLigne.ts`) ne porte
  plus aucun pointage réel ; à défaut, des gardes `IS DISTINCT FROM` / `COALESCE` qui refusent quand
  `mon_etablissement_id()` est NULL, dans `fn_codes_pointage_mission`, `fn_generer_qr_mission` et
  `fn_generer_code_secours_mission`. Dans les deux cas, un rejet explicite qui renvoie à ce constat (principe « un
  gap connu reste verrouillé »).
- **Constat T0 (nouveau, RLS/auth) — `fn_creer_notification`** (revue fraîche de T0) : tout compte authentifié peut
  écrire une notification arbitraire (destinataire, type, titre, corps, `lien`) à n'importe quel destinataire :
  fonction `SECURITY DEFINER` (l.27450-27475), `GRANT … TO authenticated` (l.82276), seul contrôle
  `auth.uid() IS NULL` (refus des appels anonymes hors cron). `docs/audit-fonctionnel-pre-lancement.md` l.177 la
  marque pourtant « ✅ FIXÉ » : le correctif n'a ajouté que ce contrôle d'authentification. Le natif ne l'appelle
  jamais (décision 9, `RPC_JAMAIS_SUIVIES`) ; le web l'appelle encore (`PanneauContestation.tsx` l.147-155).
  **Proposition** (PR backend séparée, B9, depuis la définition live) : retirer l'appel web (le trigger
  `trg_notifier_creation_litige` notifie déjà) puis `REVOKE EXECUTE … FROM authenticated`, ou contrôler le
  destinataire et le type, avec un rejet explicite.
- **Gardes NULL des fonctions `SECURITY DEFINER` — renvoi unique à l'audit du 3 novembre 2026** : les listes
  partielles de constats de T0 (gardes ternaires de `fn_presences_detail_mission` et `fn_etat_pointage_mission`,
  chaînes de pointage à distance du système ①, « Motif à auditer ») sont remplacées par l'audit des gardes NULL du
  3 novembre 2026, relu en lecture seule sur la définition live de chaque fonction en production : rapport en annexe,
  `docs/mobile-swift/AUDIT_GARDES_NULL_2026-11-03.md` (verdict, gravité et correction proposée par fonction).
  Corrections : PR B9 dédiée `fix/gardes-null-security-definer`, hors lot 2. Garde de T0 : plancher documenté,
  **≥ 18 RPC** `GRANT … TO authenticated` dont une condition compare nûment à `mon_etablissement_id()` au dump
  (méthode `gardesNuesEtablissement` de `tests/node/check-rpc-contracts.node.mjs`, plus l'affectation de `v_is_etab`
  de `fn_etat_pointage_mission`) ; un décompte plus élevé ne la fait pas rougir, la correction d'une garde relevée par
  T0 la fait basculer (« Ordonnancement et branches »). Le natif n'appelle `fn_etat_pointage_mission` et
  `fn_presences_detail_mission` que pour ses missions et n'en dépend pas.
- **Remontée** : ces constats sont à remonter à Gabrielle par la session principale, hors branche, sans attendre la PR
  de `feat/ios-lot2` (aucune PR n'est ouverte sur cette branche avant la fin du lot 1).

### Actions manuelles (STAGING, appareil, Apple)

- Dispatcher `install-sms-staging-closed.yml` (supplément de recette, jamais fait par un agent) puis le workflow de S1 ;
  relire en lecture seule le MD5 de `fn_envoyer_otp_signature` STAGING épinglé par le supplément.
- Fournir deux numéros de téléphone réels (soignant et établissement de recette) et le compte Twilio de recette en
  secrets d'environnement ; confirmer `canal_sms` et des comptes TEST confirmés pour la portée.
- Indiquer si `ANTHROPIC_API_KEY` est configurée sur STAGING (sinon P4 se prouve par la file de revue manuelle).
- Relever `parametres_litiges.delai_contestation_pointage_h` sur STAGING et en production (lecture seule).
- Recette appareil T12 : iPhone avec TestFlight Staging 2.0.0 (26), front web lancé localement contre STAGING pour
  afficher le QR, SMS reçu, arrêts forcés, photo HEIC non identitaire ; archive et upload du build 26.
- Hors lot 2, à anticiper : clé APNs sous `GDU5AA28M9` (lot 3) ; compte de démonstration capable de signer, ou mention
  dans les notes de review Apple (lot 6).

## Points consignés hors lot 2

- `dec_fenetre_pointage` (`public.sql` l.1961) formate l'heure sans fuseau (UTC) dans « Pointage trop tôt. La mission
  commence à %. » : affiché verbatim ; correctif backend à proposer (consigné dans `PORTE_LOT2.md` à la clôture).
- `SyncHorsLigne` (monté par `LayoutApp.tsx`) rejoue `fn_pointer_*` depuis `src/lib/horsLigne.ts`, alimenté seulement
  par `stockerPointageHorsLigne`, appelée uniquement dans les fonctions web mortes `pointerArrivee` / `pointerDepart` :
  résidu web du système ①, non reproduit (retrait à proposer côté web, préalable au REVOKE du constat B9). Une garde
  Node rougit si `stockerPointageHorsLigne` gagne un importeur ou un appel ailleurs.
- Le web journalise le retrait du consentement GPS sous `GPS_CONSENTEMENT_ACTIVE` / `GPS_CONSENTEMENT_RETIRE`, absents
  du CHECK `journaux_audit_action_check` : son audit échoue en silence (la trace serveur `DONNEES_PERSO_MODIFICATION`
  existe).

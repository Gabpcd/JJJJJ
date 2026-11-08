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
    et après effacement ; tout échec du magasin ou reçu illisible → `RecuErreur.illisible`, sans réparation ;
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
    « `nouveau_code` jamais lu ».
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
    avant l'unique requête, effacé après la relecture du succès ou du refus. `RecuErreur.recuEnCours` →
    `RecuScan.messageRecuEnCours` ; `RecuErreur.illisible` → écran bloquant `RecuScan.messageIllisible`, aucun scan ;
  - le scan passe par `RPCResponse.appelerMutation(…, exceptionsMetier: ExceptionsMetierLot2.scannerCodePointage)`,
    jamais par `appeler` : `JoleneError(.unknown)` d'`appeler` mêle une exception non déclarée (rollback prouvé) et
    une passerelle 502/504 (incertaine, corps HTML ou `{"message"}` décodé en `PostgrestError(code: nil)` par
    supabase-swift 2.55.5). `.reponse` → succès relu ou refus restitué ; `.refusDefinitif(code:erreur:)` → refus,
    reçu `refused` si `code` est un SQLSTATE (cinq caractères), sinon effacé ; `.incertain` et délai `bounded` →
    `IssueScan.incertain`, reçu `started` conservé, réconciliation par relecture ;
  - relecture `scans_pointage?select=<PreuveScan.selection>&mission_id=eq.<mission du reçu>` : la projection porte
    `mission_id`, que `RecuScan.reconcilier` vérifie aussi (avec `numero_scan > nb_scans_avant`) ;
    `.horlogeIncoherente` (heure de l'appareil reculée) s'affiche comme `messageIllisible`, sans relecture en
    boucle ; le reçu reste `started` ;
  - `fn_etat_pointage_mission` et `fn_presences_detail_mission` : la gateway lit `RPCResponse.estRefus` et
    `erreur` AVANT de décoder (`{error}` → `.refuse` verbatim pour l'état ; carte de synthèse masquée pour le
    détail) ; `EtatPointage` et `ResumePresencesServeur` refusent eux-mêmes `{error}` et un objet sans leurs clés
    discriminantes.
- **T6** : reçu par `ReceiptJournal<RecuDocument>(store: appareil.recus)` (domaine `document`, essai = `s3Cle`),
  mêmes règles que T3 ; `MimeDocument` est `Codable` dans sa déclaration (`Documents/ClassementDocument.swift`),
  ne pas y ajouter de conformité rétroactive.
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
  son propre reçu.

## Amendements du blueprint (`LOT2_PLAN.md`)

Le blueprint versionné n'est pas réécrit ; ces écarts font foi.

| Passage du blueprint | Formulation initiale | Retenu | Motif |
|---|---|---|---|
| §3 B1 « Fichiers » ; §4, vague 0 | fiche « `nouveau_code` jamais lu » et garde de T0 « basculées dans la même PR » ; « B1 se merge **après** T0 », « B1 **après T0** » | B1 vise `main` et n'attend pas T0 ; fiche et garde basculent au merge de `main` dans `feat/ios-lot2` (« Ordonnancement et branches ») | revue fraîche de T0 : tant que le lot 2 n'est pas sur `main`, la PR B1 ne peut pas modifier deux fichiers qui n'y existent pas |
| §3 T0 (`RPC_POINTAGE_SYSTEME_1`) ; §1.2 « Système de pointage ① » | huit RPC | neuf RPC : + `fn_generer_code_secours_mission` | seconde revue fraîche de T0 : générateur du code de secours de ①, troisième chaîne de pointage à distance (décision 1 amendée) |
| §1.3 P10 (porte du lot 2) | « `unwiredPorts.isEmpty` » | `unwiredPorts.filter(Lot2PortsTests.portsLot2.contains).isEmpty` : aucun port du lot 2 non câblé, dans les deux mondes | revue fraîche de T1 : `unwiredPorts` nomme aussi les ports des lots suivants ; si le lot 3 est intégré avant la clôture du lot 2, `isEmpty` est faux pour le lot 2 lui-même (même règle que la clôture du lot 1, PRINCIPES §2) |
| §2.2 (`ReceiptStorePort` « lot 1 T7 », `KeychainReceiptStore` « (T7) ») ; §2.6 (« Le journal est celui de T7 ») ; §3 T1 « Dépendances » | journal et magasin Keychain livrés par lot 1 T7 | livrés par T1 du lot 2 (décision 23, « Application ») ; protocole `ReceiptStorePort` dans `Receipts/ReceiptJournal.swift`, champ `Appareil.recus` ; Keychain `AfterFirstUnlockThisDeviceOnly` (le pilote prenait `WhenUnlocked`) | T7 n'existe sur aucune branche ; une réponse reçue écran verrouillé doit encore se journaliser, et un reçu ne porte aucun secret |
| §2.4 et correction 10 (« seuls `URLError`, délai `bounded` et `HTTPError` sans corps PostgREST sont incertains ») | une `PostgrestError` décodée prouve un rollback | seule une `PostgrestError` portant un `code` le prouve ; `PostgrestError(code: nil)` (corps `{"message"}` d'une passerelle) est incertaine ; classement par `RPCResponse.appelerMutation` (lot 2), le fichier partagé avec le lot 3 restant inchangé | revue fraîche de T1 : supabase-swift 2.55.5 décode tout corps d'erreur JSON à `message` en `PostgrestError`, `code` optionnel |
| §2.4 (statuts des stubs de test) | `42501` → 403, `23503` → 409, `P0001`, `22023`, `23514` → 400, autres `P0…` → 500 | + classes `40` (rollback de transaction) et `57` (dont `57014`, `statement_timeout`) → 500 | revue fraîche de T1 : statuts réels de PostgREST |
| §2.5 « Réconciliation » | preuve : `mission_id` = reçu, id hors baseline, même `id_terminal` | + `numero_scan > nb_scans_avant`, mission vérifiée par `RecuScan.reconcilier` lui-même (projection `PreuveScan` avec `mission_id`) ; relecture datée avant `started` (heure reculée) → verdict `horlogeIncoherente`, fail-closed, jamais « non reçu » | revue fraîche de T1 : un oubli du filtre `mission_id` par la requête de T3 aurait donné un faux succès ; une horloge reculée laissait un `aRelire` sans fin |

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

## En attente de Gabrielle

Rien de ce qui suit n'est implémenté par les tranches iOS ; chaque point bloque seulement la tranche indiquée.

### HARD STOP n°4 (juridique exposé à l'utilisateur)

- **TL** : validation écrite des textes juridiques et de consentement listés avec leur source dans la PR TL
  (consentement GPS et retrait, attestation santé avec la mention de l'art. 441-7 du Code pénal, bandeaux et mentions
  du contrat, art. 1366-1367 du Code civil, art. L.1242-12 du Code du travail, `MESSAGES_ERREUR`, compte à rebours
  72 h, certificat) avant que T4b, T7, T9a et T9b soient déclarées livrées. Les textes tutoyés du web restent verbatim
  tant qu'un wording vouvoyé n'est pas validé.
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
  d'autorisation, qui vaut NULL pour un compte sans lien avec la mission.
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

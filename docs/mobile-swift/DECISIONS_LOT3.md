# Décisions du lot 3 — application iOS Swift native

> Tranchées le 2 novembre 2026 par Claude Code, sur mandat de Gabrielle du même jour (« finis et prends les
> décisions seul », « je suis tous tes conseils ») et selon le mémo « Décisions des lots 2 à 5 » de la session
> principale : **toutes les recommandations fermes du §7 du blueprint `docs/mobile-swift/LOT3_PLAN.md` sont
> adoptées telles quelles**. Ce mémo fait foi pour le lot 3. Le plan `docs/PLAN_APP_NATIVE_SWIFT.md` n'est pas réécrit :
> ses critères de sortie amendés sont consignés ci-dessous. Les décisions juridiques, les réglages hors dépôt et
> les go B9 restent à Gabrielle (« En attente de Gabrielle »).

Numérotation : `N.` reprend la question N du §7 du blueprint, citée `DN`. Chaque décision nomme la ou les
tranches qui la mettent en œuvre (§3 du blueprint).

## Décisions (§7 du blueprint, tranchées le 02/11/2026)

1. **Prompt de notification** (D1) — **Adoptée** : jamais au login ; pré-prompt natif à partir du 2e lancement à
   froid, masqué si l'autorisation est déjà accordée ou refusée, plus l'activation depuis Préférences ; parité web
   (`DemandePermissionPush.tsx`, `session-count.ts`). Tranche T5.
2. **Logout** (D2) — **Adoptée** : `fn_desactiver_mon_token_push` puis `unregisterForRemoteNotifications()`
   toujours, oubli du token ; déconnexion subie : désinscription locale seule (parité `pushDeviceToken.ts`
   l.108-120). Tranche T4.
3. **Délai de désactivation** (D3) — **Adoptée** : 2,5 s comme le web au lieu des 15 s de la décision 14 du lot 1,
   seule exception consignée ; l'audit `DECONNEXION` (L1-T9) et la désactivation partent **en parallèle**
   (`async let`, deux appels JWT indépendants) et `controller.signOut()` suit dès que les deux ont rendu ou expiré —
   amendement local de L1-T9 à faire accepter par la revue de T4. Tranche T4.
   **Écart de T4 (revue B8 du 08/11/2026)** : L1-T9 (`origin/lot1/t9`) n'est ni sur `main` ni sur `feat/ios-lot3` ;
   T4 livre la désactivation bornée à 2,5 s avant `controller.signOut()`, sans audit. **Parallélisation et test
   d'ordre reportés au merge de L1-T9 dans `feat/ios-lot3`** ; résolution du conflit de `SessionStore.signOut` et
   tests à ajouter : `REVUES_LOT3.md`, section L3-T4 (jamais l'audit et la désactivation en série).
4. **Revenus au lot 3** (D4) — **Adoptée** : totaux serveur (`fn_mes_revenus_connect`), paiements rapides,
   missions terminées, paiements déclarés, Stripe et IBAN natifs ; factures, bulletins et avances en renvoi web ;
   aucun KPI calculé côté client. Tranches T12, T13, T14a, T14b.
5. **Montant par mission** (D5) — **Adoptée** : port de `montantFinanceAfficheMission` (correction du plafond Rist
   historique comprise) avec vecteurs golden, en lisant **exactement** les colonnes de `MesGains.tsx` l.95 (sans
   colonnes Rist) : la correction reste inactive comme sur le web (correction 19), aucun montant n'est recalculé
   côté client, PRINCIPES §3 n'est pas amendé ; règle consignée comme candidate RPC. Tranches T2, T12.
6. **Stripe sans Origin** (D6) — **Adoptée** : l'app envoie `Origin: https://jolene.app` ; aucune modification de
   `stripe-connect-onboard` (correction 1). Tranche T14a.
7. **Présentation des flux hébergés** (D7) — **Adoptée** : `ASWebAuthenticationSession` éphémère à rappel `.https`
   dès iOS 17.4, `SFSafariViewController` en dessous ; dans tous les cas, succès = statut relu (`force=true`). Le
   retour par Universal Link n'est prouvé que sur iOS ≥ 17.4 ; dessous, la recette consigne « retour par fermeture
   de la feuille + statut relu ». Tranches T14a, T17.
8. **PSC** (D8) — **Adoptée** : non construit au lot 3 (credentials ANS absents, pas d'environnement de test,
   rappel https iOS 17.4) ; `/auth/psc/callback` reste à Safari ; tranche ouverte le jour J. Fiche
   « PSC (Pro Santé Connect) : non consommé au lot 3 » de `CONTRATS_RPC_SOIGNANT.md`.
9. **Onboarding** (D9) — **Adoptée** : pas d'exploration des missions avant le profil complet (écart assumé avec
   `ParcoursInscription.tsx` l.144-145) ; écran de complétion bloquant avec « Se déconnecter ». Tranches T7, T8.
10. **Formats du lien de confirmation** (D10) — **Adoptée** : `token_hash`, implicit et `code` acceptés (échange
    `code` tenté une fois, repli « Se connecter », le compte étant confirmé par `/verify`) ; modèle d'e-mail visé au
    format `token_hash` — réglage Dashboard en attente (§6.4). Tranche T7.
11. **Étudiants et RPPS temps réel** (D11) — **Adoptée** : parcours étudiant en renvoi web ; vérification RPPS par
    `register-soignant` seul (aucun appel `verify-rpps` depuis l'app), refus verbatim ; obligation de saisie selon
    la même liste que le web et le serveur (`PROFESSIONS_RPPS_REQUIS`, correction 20), portée en vecteur golden.
    Tranches T2, T8.
12. **Périmètre du profil** (D12) — **Adoptée** : identité, coordonnées, préférences de recherche, bio, expérience,
    avatar, localisation ; type d'exercice, cumul (L1222-5), spécialité, GPS, pool urgence en renvoi web ou dans
    d'autres lots. Tranches T9, T10.
13. **Mot de passe** (D13) — **Adoptée** : parité (ancien vérifié, 12 caractères et 5 critères) ; si le nonce est
    exigé, refus verrouillé vers « Mot de passe oublié ? », pas de flux `reauthenticate` OTP au lot 3. Tranche T11.
14. **Avatar** (D14) — **Adoptée** : JPEG 256 px qualité 0,8, `<uid>/avatar-<ts>.jpg`, URL signée 5 ans comme le web ;
    le WebP du web (`AvatarUpload.tsx` l.51, l.136-140) est un écart assumé (MIME autorisé par le bucket, encodage
    WebP non garanti par ImageIO en iOS 16). Tranche T10.
15. **Géocodage** (D15) — **Adoptée** : `api-adresse.data.gouv.fr` (mêmes libellés que le web) plutôt que
    `CLGeocoder` ; best-effort, aucun identifiant envoyé. Tranche T10.
16. **Thème** (D16) — **Adoptée** : Système / Clair / Sombre par appareil, défaut Système. Tranche T11.
17. **Preuves push et Stripe sur STAGING** (D17) — **Adoptée** : cohorte non-test D5-R créée par **bascule
    transactionnelle** dans la transaction backend de la fixture (`inscriptions_publiques_actives` 0 → 1, INSERT des
    trois acteurs avec `est_compte_test = false`, retour à 0, assertion, COMMIT — modèle
    `finance-cohortes-rollback.sql` l.18-62), jamais un passage durable à 1 ; acteurs D5-R nettoyés en fin de recette.
    Exécution soumise au go B9 du dispatch de T16 ; sans ce go, les deux preuves restent « non mesurables ».
    Tranche T16.
18. **Classement B9 du lot 3** (D18) — **Adoptée** : go humain pour B3, T7, T8, T12, T13, T14a, T14b et T16 ;
    auto-merge (CI verte + revue fraîche B8 clôturable) pour les autres tranches, préférences de notification
    comprises (préférence, pas un consentement juridique). Voir « B9 » ci-dessous.
19. **Contestation** (D19) — **Adoptée** : B3 (depuis la définition live) avant l'ouverture du bouton, verrou
    explicite d'ici là ; option **sans DDL destructif** : retrait de l'INSERT `CONTESTATION_PAIEMENT` redondant avec
    `trg_notifier_creation_litige`, garde `auth.uid() IS NOT NULL AND fn_compte_auth_actif()`, `FOR UPDATE`, statut
    `DECLARE` ou `EN_ATTENTE` et `NOT conteste AND NOT confirme_par_soignant`, motif `btrim` de 1 à 500 caractères,
    `{error}` explicite si un litige ouvert sans facture existe déjà sur la mission (critère de B3 ; le rattachement
    au litige existant n'est pas retenu au lot 3). Élargissement du CHECK seulement si Gabrielle demande une
    notification dédiée. Tranches B3, T13.
20. **IBAN** (D20) — **Adoptée** : le natif confirme l'IBAN du RIB vérifié (règle serveur), succès strict
    (`success == true` puis relecture) ; PR web séparée pour le faux succès de `SectionPaiements.tsx` l.259-262 (B9,
    go humain). Tranche T14b.
21. **Sentry** (D21) — **Adoptée** : projet iOS séparé `jolene-ios`, aucune PII, ni capture d'écran ni breadcrumbs
    réseau, traces à 0, crash de test en DEBUG uniquement. Tranche T15.
22. **Exporter golden du push** (D22) — **Adoptée** : modules inertes nommés pour `pushNative.ts`, sans modifier
    `src/` ; exception explicite à la règle du hook de L1-T2 (« tout alias `@/` hors `@/lib/` est refusé »), limitée
    à `pushNative.ts`, chaque module inerte lève s'il est appelé. Tranche T2.
23. **Centre de notifications** (D23) — **Adoptée** : liste, lecture, tap ; ni suppression (RLS admin,
    correction 9) ni Realtime (lot 4). Tranche T5.
24. **Workflow STAGING** (D24) — **Adoptée** : workflow jumeau `ios-swift-lot3-staging.yml` (mêmes
    `policy.mjs`/`admit.mjs` non modifiés, groupe `jolene-supabase-staging-writes`, environnement protégé), comme le
    lot 2 ; le fichier du lot 1 n'est pas édité. Tranche T16.
25. **Captcha GoTrue refusé** (D25) — **Adoptée** (conditionnelle) : si `PORTE_LOT0.md` 3.1 ou 3.2 renvoie un refus
    captcha, T7 livre « Créer un compte » en renvoi web (`/inscription/soignant` dans Safari), confirmation et
    complétion natives conservées pour un compte créé sur le web ; ni SDK captcha natif ni exemption serveur au
    lot 3. Tranche T7.

## Critères de sortie du plan amendés (`PLAN_APP_NATIVE_SWIFT.md` §5 « Lot 3 », l.196-200)

| Critère du plan | Critère retenu pour le lot 3 | Fondement | Tranches |
|---|---|---|---|
| Push réel reçu sur iPhone physique depuis `send-push` en sandbox, tap ouvrant l'écran attendu pour au moins six types d'événements ; table de routage testée sur `src/lib/pushNative.test.ts` (l.196) | Inchangé sur le fond. Niveaux 1-3 d'abord (golden, XCUITest `-JOLENE_SIMULER_PUSH`, upsert puis désactivation relus sur STAGING) ; le niveau 5 exige la clé APNs sous `GDU5AA28M9`, `APNS_ENVIRONMENT = sandbox` sur STAGING, un build Debug installé par Xcode et la cohorte non-test D5-R ; sans eux, « non mesurable », jamais simulé | D1-D3, D17 ; corrections 2 et 5 | T2, T4, T5, T16, T17 |
| Inscription STAGING de bout en bout par Universal Link : email reçu, PKCE échangé, profil créé (l.197) | « Email reçu, lien `token_hash` vérifié dans l'app (`verifyOTP`), profil créé » ; l'échange `code` (PKCE) reste couvert aux niveaux 1-2 ; niveau 3 en CI (lien relu en SQL puis injecté par `-JOLENE_OPEN_URL`), niveau 5 sur iPhone avec une adresse de Gabrielle. Reformulation à valider par Gabrielle (§6.4) | D10, D25 ; corrections 10 et 14 | T7, T8, T16, T17 |
| Onboarding Connect STAGING ouvert et retour dans l'app par Universal Link (l.198) | Ouverture et statut relu (`force=true`) sur STAGING avec la cohorte D5-R ; retour par Universal Link prouvé sur iPhone en **iOS ≥ 17.4** ; sous 17.4, « retour par fermeture de la feuille + statut relu » consigné | D6, D7, D17 ; corrections 1, 6 et 17 | T14a, T16, T17 |
| Sentry reçoit un crash de test taggé release 2.0.0 (25) (l.199) | Inchangé ; projet `jolene-ios`, release construite depuis les clés du bundle | D21 | T15, T17 |
| TestFlight externe ouvert à une cohorte de soignants pilotes (l.200) | Inchangé ; décision explicite de Gabrielle après la porte du lot 3 signée (le build parle à la production) | §6.10 | hors tranche |
| Périmètre « PSC si credentials ANS présents » (l.193) | PSC non construit au lot 3 (credentials absents) | D8 | — |

## Précisions du mémo des lots 2 à 5 applicables au lot 3

- **Branche d'intégration** `feat/ios-lot3`, créée depuis `origin/feat/ios-lot1` ; elle reprend `main` puis
  `feat/ios-lot1` par merge, jamais par rebase ni force-push. Aucune PR n'est ouverte sur cette branche avant la fin
  du lot 1 (chaque PR lance la recette Playwright sur la base partagée).
- **Drapeaux (D-FLAGS)** : aucun nouveau drapeau au lot 3 ; Revenus et Profil restent pilotés par
  `ios_natif_revenus_actif` et `ios_natif_profil_actif` (B0 du lot 1).
- **Aucune écriture** en production ni sur STAGING par les agents ; lecture seule en production uniquement pour
  relire une définition live (`pg_get_functiondef`, `pg_get_constraintdef`, `list_migrations`) dans la PR backend B3.
- **Merges sur `main`** : sériels, CI verte et revue fraîche B8 clôturable, par la file de merge de la session
  principale.
- **Surcharge `UnwiredPorts.erreur(port:tranche:lot:)`** : ajoutée par la première T1 mergée (lot 2 ou lot 3),
  réutilisée par l'autre (deux déclarations identiques ne compilent pas). L3-T1 la pose dans
  `JoleneCore/Ports/Lot1Ports.swift` ; L2-T1 ne la redéclare pas dans `Lot2Ports.swift` (`REVUES_LOT3.md`, L3-T1).

## T3 livrée en deux temps : T3a (cœur) et reliquat T3b (revue fraîche du 08/11/2026)

- **Écart.** Le blueprint fait dépendre T3 de L1-T10 (§3 T3 : « Dépendances : T1, lot 1 T10 » ; §4, vague 2). Or
  L1-T10 n'existe sur aucune branche : ni `onOpenURL`, ni `onContinueUserActivity`, ni `DeepLinkCoordinator` sur
  `origin/feat/ios-lot1` ni sur `origin/lot1/*` (vérifié le 08/11/2026). La branche `lot3/l3-t3-v2` est donc une
  **livraison partielle, T3a (cœur)**, et **T3 n'est pas close**. Le critère « Universal Links complets » côté
  soignant n'est pas atteint : à l'exécution, rien ne change, hormis `AccueilPresentation.renvoiWeb`.
- **T3a livre** (JoleneCore seul) :
  - les routes du lot 3 dans `JoleneRoute` et `LinkRouter` : notifications, préférences, Stripe Connect, inscription
    avec sa query, sections Revenus lues dans `?tab=`, `.profil` (édition) séparé de `.monCompte` (hub) ;
  - `Links/DestinationLien.swift` (destination effective : la route si son écran est livré, sinon
    `.safari(canonique)`) ;
  - `Links/LienMasque.swift` (descriptions masquées) ;
  - les tests `LinksRouterTests`, `LinksAASATests` et `DestinationLienTests`.
- **Reliquat T3b**, une fois L1-T10 sur la base du lot 3 :
  - `Jolene/Composition/DeepLinkCoordinator.swift`, qui ne présente que `DestinationLien.destination`. Une route
    native sans écran passe par le présentateur `.safari`. Le coordinateur expose aussi le libellé DEBUG
    `deeplink-route`, attendu par T5.
  - `JoleneUITests/DemoLiensLot3Tests.swift`, écrit pour iphone, ipad-portrait et ipad-landscape avec les helpers de
    `UITestSupport.swift`. Cas à couvrir :
    - `-JOLENE_OPEN_URL https://jolene.app/soignant/notifications` donne un renvoi Safari (URL vérifiée par le
      double d'ouverture) tant que T5 n'a pas basculé sa ligne, puis l'écran natif ;
    - même contrôle pour `/soignant/parametres/notifications`, `/soignant/stripe-connect?success=true` et
      `/inscription/soignant` ;
    - `/soignant/mes-gains?tab=factures` reste un renvoi web ;
    - `/soignant/mon-compte` ouvre le hub natif.

  T3 est close par T3b, après sa revue B8.
- **Nom du type et point de fusion avec L1-T10.** Le type s'appelle `DestinationLien` et non `DeepLinkIntent`, le
  nom du blueprint. Raison : `LOT1_PLAN.md` (l.53, l.304-305) attribue `JoleneCore/Links/DeepLinkIntent.swift` et
  `DeepLinkIntentTests` à L1-T10, avec un autre rôle (13 routes, lien reçu avant `.ready` différé, epoch), et L1-T10
  part d'une base qui n'a pas ce fichier. Garder le nom ici donnait un conflit add/add certain et un même nom pour
  deux sémantiques. Au merge de L1-T10 :
  - `DeepLinkIntent` garde son rôle (intention mémorisée, epoch) et porte une `DestinationLien`, ou l'URL reçue,
    résolue en `DestinationLien` au moment du rejeu ;
  - le coordinateur ne présente que `destination` ;
  - les « 13 routes » de T10 se lisent dans la table de `DestinationLienTests` (natif ou web) ;
  - `DeepLinkIntentTests` reste à T10.
- **Nouvelle consigne pour T5 à T14b.** Elle remplace « une ligne de `DeepLinkCoordinator.swift` » (blueprint §3 T3
  et §4).
  - La tranche qui livre un écran passe **sa ligne de `DestinationLien.ecranNatifLivre`** à `true`.
  - Dans `DestinationLienTests`, elle ajuste trois tests :
    - sa ligne de `testTableDesEcransLivres` ;
    - son cas dans `testRoutesLot3SansEcranRenvoyeesVersSafariCanonique`, qui passe dans les routes natives ;
    - dans `testDestinationsDuRoutagePushParFamille`, la destination de sa famille et les deux totaux.
  - Si T3b est déjà mergée, elle ajoute en plus la ligne de mappage de son écran dans `DeepLinkCoordinator`.

  Ligne de chaque tranche :
  - T5 : `.notifications`. C'est ainsi que se lit « `DeepLinkCoordinator` (`.notifications` natif) » du §3 T5.
  - T6 : `.parametresNotifications`.
  - T7 : `.inscription` (pages `soignant` et `reprendre`).
  - T8 : `.inscription` (page `completer`).
  - T9 : `.profil`, alias `reputation` compris.
  - T11 : les entrées du hub passent par `JoleneRoute` puis `DestinationLien.destination`.
  - T12 : `.revenus(section: .apercu)` est déjà à `true` ; T12 remplace le placeholder.
  - T13 : `.revenus(section: .paiementsAConfirmer)`.
  - T14a : `.stripeConnect`.
  - T14b : aucune route IBAN dans la table (l'IBAN est une sous-ligne de `/soignant/mes-gains`, `PARITE_SOIGNANT.md`).
    Sa « ligne » est sans objet tant qu'aucune route n'est ajoutée ; un ajout éventuel passe par le propriétaire de
    `JoleneRoute` et `LinkRouter`.
- **Point de fusion L3-T5 (Accueil).** `AccueilPresentation.renvoiWeb` passe désormais par
  `DestinationLien.destination`. Ce fichier ne figure pas dans la liste du blueprint, et c'est voulu : sans ce
  changement, `renvoiWeb(lienNotifications)` deviendrait `nil` dès T3a, puisque `/soignant/notifications` est une
  route native. Quand T5 passera `.notifications` à `true`, `renvoiWeb(lienNotifications)` rendra `nil`. T5 devra
  alors :
  - mettre à jour `AccueilAssemblageTests.testRenvoisWebDeLAccueilSontDesRoutesSafariCanoniques` (l'attendu
    `.safari(https://jolene.app/soignant/notifications)` devient `nil`) ;
  - remplacer le bouton `accueil-notifications-action` (« Voir sur jolene.app », `AccueilScreen.swift`) par une
    navigation vers le centre natif ;
  - migrer les identifiants lus par `DemoAccueilTests`.
- **Écart assumé : score et fiabilité sur le hub.** `/soignant/score`, `/soignant/fiabilite` et
  `/soignant/fiabilite-legacy` mènent à `.monCompte`, comme le veut le blueprint v2 (§3 T3, qui fait foi). C'est
  contraire au principe de `DestinationLien` : `ProfileScreen` n'affiche aucun score (`PARITE_SOIGNANT.md` l.62, score
  au lot 4), alors que Safari afficherait la page. Le lot 4, avec la page score, les sortira du hub.
- **Écart : détail de série.** `.serieDetail` part en renvoi Safari (`ecranNatifLivre` vaut `false`), conformément à
  la décision 11 du lot 1 et à `PARITE_SOIGNANT.md` l.48 (détail natif au lot 4). `LOT1_PLAN.md` l.142 (T10) le
  confiait pourtant au coordinateur. La tranche qui livrera un écran de série passera sa ligne à `true`.
- **Journalisation (PRINCIPES §7).** Une destination de lien ne se journalise que par `description` :
  - descriptions autorisées : celles de `DestinationLien`, `JoleneRoute` et `EtapeInscription`. Elles sont masquées
    par `LienMasque` : nom du cas de route et gabarit du chemin, dont tout segment hors du vocabulaire des routes
    devient `‹masqué›` ;
  - à ne jamais journaliser : `canonique`, `externalURL`, `EtapeInscription.query`, un identifiant extrait.

  Le chemin peut porter un jeton (`/etab/invitation/:token`, `src/App.tsx` l.433, consommé par
  `fn_accepter_invitation_membre`) ou un identifiant (`/contrat/:id`, `/soignant/missions/:id`).

## T5 livrée sans le coordinateur de liens de L1-T10 (branche `lot3/l3-t5-v2`, 08/11/2026)

- **Manque.** Le blueprint fait passer les taps par `DeepLinkCoordinator` (« une ligne », §3 T5) et la tranche
  dépend de T3 (T3b). Ni `DeepLinkCoordinator`, ni `DeepLinkIntent`, ni présentateur `.safari` n'existent sur une
  branche (L1-T10 absent, reliquat T3b ouvert). T5 n'invente pas ce coordinateur : elle livre la partie faisable
  et pose un **point d'extension minimal**, à reprendre par L1-T10 / T3b :
  - `JoleneCore/Push/PushTapIntent.swift` : `PushTapIntent` (payload → `PushRouting` → `DestinationLien`) et
    `BoiteTapsPush` (dernier tap mémorisé, rejoué par le premier espace prêt avec le rôle du snapshot ; un tap reçu
    pendant l'espace d'un epoch est écarté par un autre epoch) ;
  - `JoleneCore/Notifications/CentreNotifications.swift` : `CibleNotification`, construite depuis une
    `DestinationLien` seulement (jamais la route brute) : Accueil, Explorer, Mes missions, Revenus **avec sa
    section**, hub Profil, détail de mission, centre, renvoi web, aucune ; onglet porteur donné par
    `OngletEspace` (`JoleneCore/Navigation/OngletEspace.swift`, enum dédié : les drapeaux `EcranNatif`, étendus
    par le lot 2 aux présences, documents et contrats, ne sont pas des onglets) ;
  - `MainTabView.presenter(_:depuisCentre:)` : présentation de ces cibles dans l'espace prêt (onglet, retour à la
    racine de l'Accueil, détail empilé sur l'Accueil, centre), seulement si `CibleNotification.estPresentable` ; un
    renvoi web n'est présenté que par `PresentateurRenvoiWeb` s'il est injecté (nil avant L1-T10 : rien n'est
    ouvert, jamais `openURL`).
- **Ligne de T5** : `DestinationLien.ecranNatifLivre(.notifications) = true` (consigne de T3a), avec
  `DestinationLienTests` (table, famille push `/soignant/notifications` → natif, totaux 454 / 436) et le point de
  fusion de l'Accueil (`renvoiWeb(lienNotifications)` = nil, « Voir » `accueil-notifications-action` ouvre le
  centre natif, `DemoAccueilTests` migré).
- **Au merge de L1-T10 / T3b** : le coordinateur consomme `BoiteTapsPush` (même règle d'epoch) et reprend
  `MainTabView.presenter` ; le libellé DEBUG `push-tap-cible` (route présentée, XCUITest de T5) peut alors céder la
  place à `deeplink-route` ; `DemoPushTests.testTapLitigeVersLeWebSansEcranBloquant` passe à la présentation réelle
  du renvoi (URL vérifiée par le double d'ouverture).
- **Verrou des tranches suivantes (T6, T7, T8, T9, T13, T14a ; revue fraîche de T5, M1)** : en plus de leur
  ligne de `ecranNatifLivre`, elles ajoutent leur cible à `CibleNotification.init`, sa présentation
  (`CibleNotification.estPresentable`) et son cas dans `MainTabView.presenter`, avec un cas de tap dans
  `DemoPushTests` (blueprint §3 T5, corrigé v2). Ce n'est plus une simple consigne :
  - la garde `CentreNotificationsTests.testToutEcranNatifLivreAUneCibleNativePresentable` parcourt la table des
    routes (un lien par genre de route, switch exhaustif) et toute la famille push des vecteurs golden ; toute route
    dont `ecranNatifLivre` vaut `true` doit y donner une cible native présentable (ni `.aucune`, ni `.web`) ; seule
    exception, la liste nommée et fermée `connexion`, `resetPassword`, `confirmerInscription` (liens consommés hors
    de l'espace par L1-T10) — une tranche n'y ajoute une route qu'avec sa justification ici ;
  - repli d'exécution : un écran passé à `true` sans cible retombe sur son renvoi web canonique
    (`.web(.safari(canonique))`), jamais un tap qui n'ouvre rien ;
  - **à l'intégration** de `lot3/l3-t6-v2` (`.parametresNotifications`) et `lot3/l3-t9-v2` (`.profil`, 7 vecteurs
    golden `/soignant/profil`) avec T5, la garde est **rouge tant que leurs cibles ne sont pas ajoutées** : c'est
    voulu. L'intégrateur ajoute par exemple `.preferences` et `.profil` (onglet Profil, écran empilé sur la pile du
    hub, qui devient une `NavigationStack(path:)` comme celle de l'Accueil) ; T14a ajoute `.stripeConnect(retour:)`
    (6 vecteurs) ;
  - **section de Revenus** : `.revenus(section:)` porte la section ; seule `.apercu` est présentable aujourd'hui.
    T13 rend `.paiementsAConfirmer` présentable et ouvre `revenus-paiements-declares` (PAIEMENT_RECU, correction 15) ;
    T12 remplace le placeholder de l'onglet. T12 garde la surcouche du pré-prompt de `MainTabView`.
- **Taps à chaud** : prouvés au niveau 1 (`BoiteTapsPush`) ; le délégué `UNUserNotificationCenter`
  (`NotificationCenterDelegate`, posé par `PushAppDelegate.didFinishLaunching`) n'est exercé que sur appareil (T17).
- **Tap reçu après une déconnexion (écart consigné, revue de T5 m12)** : un tap reçu sur l'écran de connexion
  après une déconnexion, volontaire ou subie, n'a pas d'espace ouvert ; `BoiteTapsPush` le rejoue pour l'identité
  qui se connecte ensuite. C'est la parité du web (redirection vers le chemin du tap après connexion) ; la
  destination est relue sous la RLS de la nouvelle identité, rien n'est exposé. Écarter ce tap supposerait de
  distinguer la déconnexion volontaire dans `SessionStore` (T4) : non retenu au lot 3.
- **Centre de notifications, corrections de la revue de T5** : depuis le centre, une ligne qui vise le centre n'a ni
  « Voir » ni bouton une fois lue (non lue : marquée lue, sans navigation) ; une ligne qui vise l'Accueil ramène à
  sa racine (m5). Un marquage en échec ou en délai dépassé relit la liste sans la retirer, message gardé (PRINCIPES
  §5, m2). L'échec d'un tirer-pour-rafraîchir est dit par l'encart `notifications-refresh-error` au texte web
  « Impossible de charger vos notifications. » (m3). La tâche d'ouverture est annulée à la disparition du centre :
  jamais de navigation tardive (m4). Une lecture relue avance le jeton de péremption de l'Accueil
  (`AccueilModel.loadIfStale(peremption:)`) : le compteur des non lues est relu à l'apparition suivante, même avant
  60 s (m1). Prouvé au niveau 1 seulement : en démo, le compteur est figé par `demo-dashboard.json`.
- **XCUITest « contrat à signer » (m6)** : `DemoPushTests.testTapContratASignerVersLeWebDuContrat`
  (`CONTRAT_A_SIGNER:contrat_id=demo-contrat-001` → `safari https://jolene.app/contrat/demo-contrat-001`, renvoi web
  tant que l'écran contrats du lot 2 n'est pas intégré). Le libellé `push-tap-cible` n'est exposé qu'en build DEBUG
  **et** en démo (m8).
- **Pré-prompt** : `MainTabView` (surcouche) ; compteur `jolene.sessionCount` et marque `jolene.pushPrePrompt` en
  `UserDefaults` (staging/production), en mémoire vive en démo (chaque lancement démo est une 1re session) ;
  `-JOLENE_SESSION_COUNT <n>` (DEBUG) impose le numéro de session sans persistance — `StagingConnexionTests` le passe
  à 1 pour qu'un 2e lancement du simulateur ne recouvre pas son parcours. T6 (activation depuis les préférences) :
  le pré-prompt relit la marque avant de s'afficher ; poser `accepted` après une activation réussie évite un
  pré-prompt sans objet.
- **Fixture démo** : `demo-notifications.json` compte **deux** non lues (et non « 1 lue » du §2.7) pour rester égal
  au compteur `notifs_non_lues` de `demo-dashboard.json` (« 2 notifications non lues » de l'Accueil démo).
- **Garde des textes** : `scripts/mobile/check-textes-juridiques-ios.mjs` (L2-TL) n'est pas sur la base du lot 3 ;
  les textes de T5 portent leur `// source: fichier:ligne` et sont épinglés par les tests Swift. Aucun texte
  juridique. Textes sans équivalent web (non juridiques, à relire par Gabrielle) : l'indication vocale
  « Ouvre le centre de notifications » (`accueil-notifications-action`, constante
  `CentreNotificationsTextes.indicationOuvrirCentre` épinglée par `CentreNotificationsTests`, gardée en attendant
  sa relecture, comme les indications du lot 1) ; le libellé DEBUG `push-tap-cible` n'est jamais affiché.

## Points de fusion inter-lots des liens (branches du lot 1 non intégrées)

T3a change le sens de `JoleneRoute.profil` : la route visait le hub, elle vise désormais l'édition, et le hub
devient `.monCompte`. T3a donne aussi une section à `.revenus`. Plusieurs branches du lot 1 consomment
`JoleneRoute` ; aucune n'est sur la base du lot 3. À leur reprise dans `feat/ios-lot3` :

- **`origin/lot1/t9`, `Session/EcransNatifs.swift` l.40-50.** `EcranNatif.init?(route:)` y est décrit comme le
  « point d'entrée du coordinateur de liens, T10 ». Après fusion, ce code compile mais rend `nil` pour `.monCompte`,
  c'est-à-dire `/soignant/mon-compte`, l'onglet Profil du web (`BarreNavigation.tsx` l.37). Le lien sortirait alors de
  l'onglet et du drapeau `ios_natif_profil_actif`, en silence. À corriger lors de la reprise :
  - `EcranNatif(route: .monCompte)` rend `.profil` ;
  - `EcranNatif(route: .profil)` rend aussi `.profil` : l'édition (L3-T9) vit dans l'onglet Profil, sous le même
    drapeau (aucun nouveau drapeau au lot 3). Tant que T9 n'est pas livrée, `DestinationLien` rend `.safari` et
    `EcranNatif` n'est pas atteint ;
  - le `cheminWeb` de l'onglet Profil devient `/soignant/mon-compte`. `FeatureFlagsTests.testTitresCheminsEtRoutesDesEcrans`
    passe par `DestinationLien(link:)?.destination` au lieu de `LinkRouter.resolve`, et vérifie que
    `/soignant/mon-compte` donne `.profil` ;
  - `EcranNatif.init?(route:)` ne s'applique qu'à `DestinationLien.destination`, jamais à la route brute.
    `case .revenus:` y couvre toutes les sections : appliqué à la route brute, `.revenus(section: .factures)`
    ouvrirait l'onglet natif au lieu du renvoi web assumé (D4).
- **`origin/lot1/t4b` (`.favoris`, `/soignant/mes-favoris`).** Conflit textuel sur `JoleneRoute.swift` et
  `LinkRouter.swift` : il faut garder les deux côtés. À ajouter ensuite :
  - `case .favoris: return true` dans `DestinationLien.ecranNatifLivre` ;
  - `case .favoris: return "favoris"` dans `JoleneRoute.description` (`LienMasque.swift`). Les deux `switch` sont
    exhaustifs : sans ces cas, le code ne compile pas ;
  - une ligne dans `testTableDesEcransLivres`. `mes-favoris` figure déjà dans le vocabulaire de `LienMasque`.
- **`LOT1_PLAN.md` l.142-143 (T10)** se lit désormais ainsi :
  - `.missionDetail`, `.accueil`, `.explorer`, `.missions` et `.monCompte` mènent à leur onglet, de même que
    `.profil` après L3-T9 ;
  - `.revenus(section: .apercu)` mène à l'onglet Revenus (placeholder jusqu'à L3-T12) ;
  - `.serieDetail` part vers Safari (décision 11) ;
  - toute route consommée par le lot 1 (coordinateur, `EcranNatif`, taps push) passe par
    `DestinationLien.destination`.

## T6 — préférences de notifications : écarts et points de fusion (08/11/2026)

- **Ligne de T6.** `DestinationLien.ecranNatifLivre(.parametresNotifications)` vaut `true` (consigne « Nouvelle
  consigne pour T5 à T14b » ci-dessus) ; `DestinationLienTests` déplace le cas de T6 dans
  `testRoutesLot3AvecEcranLivreSontNatives`. Aucun chemin du vecteur push ne mène aux préférences :
  `testDestinationsDuRoutagePushParFamille` est inchangé (448 destinations natives, 442 renvois web).
  `Jolene/Composition/DeepLinkCoordinator.swift` n'existe pas sur la base (L1-T10 absent, reliquat T3b) : la ligne de
  mappage du coordinateur reste à écrire par T3b, qui ouvre l'onglet Profil et pousse
  `PreferencesScreen(session:snapshot:push:permission:)` dans sa pile, comme l'entrée du hub.
- **Entrée du hub posée par T6 (écart au §4 du blueprint : `ProfileScreen.swift` appartient à T11).** La consigne de
  T4 (`REVUES_LOT3.md`, section L3-T4) impose à T6 de retirer la carte provisoire du hub dans la même tranche. Sans
  coordinateur de liens, l'écran des préférences serait alors inatteignable et la carte d'autorisation disparaîtrait
  de l'app. T6 remplace donc la section provisoire, au même emplacement (après « Application »), par la section
  « Réglages » et la ligne « Notifications » du hub web (`MonCompteSoignant.tsx` l.113, l.115, verbatim), identifiant
  `profile-preferences-notifications`. **Au merge de T11** : garder cette entrée (ou celle de T11, si elle passe par
  `JoleneRoute.parametresNotifications` puis `DestinationLien.destination`) avec le même identifiant, lu par
  `DemoPreferencesTests` et `DemoPushTests` ; jamais de seconde carte d'autorisation dans le hub.
- **Carte « Autorisation du téléphone » (mineurs 4 et 5 de la revue B8 de T4).** Elle vit désormais sous les canaux
  globaux de `PreferencesScreen`, comme le web (l.326-368), avec `canalPush` lu du brouillon (`global.canal_push`) ;
  `DemoPushTests` est migré vers cet écran (mêmes identifiants `push-etat-appareil`, `push-etat-appareil-message`,
  `push-ouvrir-reglages`).
  - Écart l.346/l.347 du hub provisoire : **levé** (canal connu, même règle que le web).
  - Écart l.349 : **conservé et assumé**. « Le canal est actif dans Jolene… » n'est affiché que si le canal push est
    actif dans le brouillon ; le web l'affiche aussi canal coupé, où le texte est faux. Canal coupé et autorisation
    jamais demandée : aucune carte (le web n'y propose de toute façon aucun bouton, l.356).
  - Mineur 4 **tranché** : sur un enregistrement en échec, l'action est « Activer sur cet appareil » (verbatim l.365,
    conditions du web l.356 : `prompt`, `registration-error` ou `unavailable`, canal push actif), qui relance
    l'enregistrement ; « Ouvrir les réglages » n'est plus proposé que si l'autorisation est refusée.
  - Activation au tap (D1 : « plus l'activation depuis Préférences ») : `EtatNotificationsAppareilModel.activer()`
    demande l'autorisation, puis relit et enregistre comme `verifier()` ; une demande en échec affiche l.351 jusqu'à
    la lecture suivante ; un second tap pendant l'activation est ignoré. Les toasts du web (l.176, l.178, l.182) ne
    sont pas portés : la carte affiche l'état relu (l.346, l.350, l.351).
  - `EtatNotificationsAppareil.sectionHub` (titre de la section provisoire) est retiré ; les libellés du hub sont
    `HubCompte.titreReglages` (seule source du titre « Réglages » depuis la revue B8 de T11, m7 :
    `PreferencesTextes.sectionHub` retiré) et `PreferencesTextes.entreeHub`.
- **Écarts au web assumés (non juridiques).**
  - Après `{success:true}`, l'app relit les préférences et n'annonce « Préférences enregistrées » que si la relecture
    concorde avec la demande (PRINCIPES §3) ; relecture non concordante → « Erreur enregistrement » (repli verbatim
    l.244). Le web annonce sans relire.
  - Seuls les types du catalogue soignant sont envoyés à `fn_modifier_preferences_notifications` ; le web renvoie
    toutes les lignes lues. Comme la RPC met à jour par clé sans rien supprimer, le résultat serveur est le même.
  - Échec d'enregistrement : message natif de `JoleneError` (réseau, session, contrat), jamais le `err.message` brut
    de PostgREST (détail technique) ; refus `{error}` du serveur : verbatim.
  - Alerte SMS en échec alors que la valeur relue est déjà celle demandée : « Préférences enregistrées » (l'état
    serveur est celui voulu) ; le web annoncerait l'échec partiel (l.237).
  - Matrice rendue en cartes par événement (un interrupteur par canal de l'événement) au lieu d'un tableau à trois
    colonnes ; libellé vocalisé d'une case : canal et, si grisée, la raison verbatim (l.409), l'événement étant le
    titre de sa carte. Cases grisées à l'opacité 0,5 de `ToggleRow` au lieu de `opacity-40` (note de la revue T1b).
  - Vouvoiement des deux textes tutoyés (l.297, l.301 ; décision 9 du lot 1) ; emoji « ⚠️ » du titre d'urgence
    remplacé par l'icône du ton « Attention » d'`InlineNotice`.
- **HARD STOP n°4.** Aucun texte nouveau : textes verbatim de `PageParametresNotifications.tsx` et
  `MonCompteSoignant.tsx` (gardés par `PreferencesNotificationsTests` et `EtatNotificationsAppareilTests`), et
  « Session à vérifier » / « Vérifier ma session » repris des écrans du lot 1. **B9** : non (D18).

## T9 — profil : écarts assumés, manques et points de fusion (08/11/2026)

- **Envoi par différence.** Le web renvoie tout le formulaire à chaque enregistrement (`ProfilSoignant.tsx`
  l.258-278, `champ || null`, rayon et années d'expérience toujours) ; le natif n'envoie que les champs modifiés
  (`ModificationProfil.depuis`), jamais un défaut d'affichage (rayon 30 km, 0 année) écrit en silence. Avec le
  `COALESCE` serveur, le résultat est le même pour tout champ modifié.
- **Prénom ou nom vidé** : envoyé vide, refusé par le serveur avec son message verbatim (l.43906-43909), au lieu du
  faux succès du web. « Supprimer » du taux minimum (web `SectionPreferences.tsx` l.78-82) non porté : le web envoie
  `null`, que le `COALESCE` ignore (aucun effet serveur).
- **Entrée du hub** : `ProfilEntreeSection` (une ligne de `ProfileScreen`, après « Application » pour ne déplacer ni
  « Se déconnecter » ni les identifiants du lot 0) ; T11 la remet en tête, dans l'ordre du hub web.
- **Liens** : `DestinationLien.ecranNatifLivre(.profil)` vaut `true` (alias `reputation` compris). Le
  `DeepLinkCoordinator` n'existe pas encore (L1-T10, reliquat T3b) : aucune ligne de mappage n'est ajoutée ; à son
  arrivée, `.profil` ouvre l'onglet Profil puis pousse `ProfilEditionScreen`, sous `ios_natif_profil_actif`.
- **Manque — référentiel des modes d'exercice.** `fn_types_exercice_autorises` est lue par
  `InscriptionPort.typesExercice`, câblé par T8 (`SupabaseInscriptionGateway` est un fichier de T7/T8) : tant que le
  port est non câblé, l'écran affiche l'état « indisponible » du web (salarié proposé, libéral conservé s'il est
  coché, jamais ajouté) sans « Réessayer la vérification » (aucun bouton sans effet), verrouillé par
  `DemoProfilTests` ; T8 remplace cette assertion par les modes autorisés.
- **Manque — renvoi du type d'exercice.** Le bouton `profil-exercice-web-action` n'existe qu'avec le présentateur
  `.safari` de L1-T10 ; d'ici là, seul l'encart `profil-exercice-web` est affiché.

### T9 — corrections de la revue fraîche B8 (08/11/2026)

- **Exceptions métier de l'enregistrement (majeur).** L'UPDATE de `soignants` dans `fn_modifier_mon_profil` peut
  lever trois exceptions PostgREST que l'écran sait provoquer (définitions live relues en lecture seule le
  08/11/2026, identiques au dump) : 23514 `chk_telephone_format` (`public.sql` l.68090, téléphone en saisie libre),
  23505 `soignants_numero_rpps_key` (l.73502), P0001 `dec_verifier_age_minimum` (l.3887-3895, trigger
  `dec_age_minimum`). L'UPDATE entier est annulé : aucun champ n'est enregistré. Elles sont restituées avant
  `SupabaseErrorMapping` (`exceptionsMetier`, correction 12, §2.4) et traduites par
  `ProfilEdition.messageExceptionMetier` :
  - 23505 sur `numero_rpps` → « Ce numéro RPPS est déjà enregistré. » (`src/lib/erreurs.ts` l.510), autre 23505 →
    « Cette valeur existe déjà dans le système. » (l.511) ; 23514 → « La valeur saisie est hors des limites
    autorisées. » (l.514) : textes web verbatim, épinglés par `ProfilVerbatimTests` ;
  - P0001 → message serveur **verbatim** (« Vous devez avoir au moins 18 ans pour vous inscrire. ») : texte serveur
    autorisé (règle 2 du mémo des lots 2 à 5). **Écart avec le web** : `extraireMessageErreur` ne reconnaît pas ce
    message (aucun préfixe de `TRIGGER_PREFIXES` ne le couvre) et affiche son message générique « Une erreur est
    survenue. Veuillez réessayer. » (l.532), qui invite à refaire un essai voué au même échec. Aucun texte nouveau.
- **Refus certain contre issue ambiguë.** Un refus certain (`{error}` en HTTP 200, exception métier) est levé en
  `RefusEnregistrementProfil` (JoleneCore) par la gateway Supabase comme par le monde démo : message affiché, aucune
  relecture. Toute autre erreur d'enregistrement hors session expirée, contrat et annulation (délai, réseau, HTTP
  5xx, 504 de la passerelle, SQLSTATE non déclaré) est ambiguë : le profil est relu, jamais renvoyé (la relecture
  n'avait lieu qu'après `.network`).
- **Session expirée.** L'écran propose « Vérifier ma session » (revalidation `session.start()`, puis relecture ou
  effacement du refus si la session reste prête pour l'epoch), avec les libellés natifs du lot 1 (« Session à
  vérifier », « Vérifier ma session », `AccueilScreen.swift`), au lieu d'un « Réessayer » sans effet.
- **Date de naissance non renseignée.** Ouvrir le sélecteur n'écrit plus `DateNaissance.parDefaut` dans le
  formulaire : le défaut est seulement affiché, seul un choix de l'utilisateur remplit la date (principe « État
  dérivé »). Limite assumée : le sélecteur compact n'écrit rien si l'utilisateur valide le jour affiché sans le
  changer ; une date choisie ne revient pas à « non renseignée » sans quitter l'écran (le `COALESCE` serveur ne
  l'effacerait de toute façon pas).
- **Manque — profil des onglets déjà montés.** Après un enregistrement, `session.start()` relit
  `session.state.snapshot.profile`, mais `MissionsListModel` (créé par `MissionsListScreen.swift` l.30,
  `ExplorerFiltres.initiaux(profile: snapshot.profile)` en `MissionsListModel.swift` l.68) et l'Accueil gardent en
  `@StateObject` le snapshot reçu à leur création : un
  onglet déjà visité reste sur l'ancien profil (rayon, contrats, taux) jusqu'à la session suivante. Point de fusion
  (lot 1 / T12) : ces modèles lisent `session.state.snapshot` au lieu du snapshot figé à leur création. Aucun test
  ne prétend le contraire (le test de T9 prouve seulement la relecture de la session).
- **Point de fusion T11/T3b — navigation programmée vers l'édition.** `ProfilEntreeSection` garde un
  `NavigationLink` à fermeture : ni `JoleneRoute` (`Equatable` seulement, fichier de T3) ni le hub (`ProfileScreen`,
  propriété de T11, une ligne pour T9) ne sont modifiés par T9, et une `.navigationDestination` posée dans la `List`
  (conteneur paresseux) serait ignorée. À la reprise : T3b rend `JoleneRoute` `Hashable` et pousse `.profil` sur la
  pile de l'onglet Profil ; T11 remplace le lien par `NavigationLink(value: JoleneRoute.profil)` et pose
  `.navigationDestination(for: JoleneRoute.self)` sur la `List` de `ProfileScreen` (modèle `MissionRoute`).
- **Variantes démo DEBUG.** `JOLENE_DEMO_PROFIL=identite-verrouillee|sans-date-naissance` (variable d'environnement
  du processus, lue par `AppContainer` en DEBUG seulement, comme `JOLENE_FORCE_ACCUEIL_ECHEC`) sert le profil démo
  avec `rpps_verifie = true` ou `date_naissance = null` (`VarianteProfilDemo`), pour les XCUITest des champs en
  lecture seule et de la date non renseignée. Aucun numéro RPPS fictif n'est inventé.
- **Description masquée.** `ProfilComplet` (identité, coordonnées, date de naissance, position GPS) se décrit
  « ProfilComplet(valeurs masquées, …) » : aucune interpolation dans un journal ou un fil d'Ariane Sentry ne
  restitue ces valeurs (§2.6). `Mirror` n'est pas redéfini (gardes de liste blanche inchangées).
- **Liste de contrôle T8 (modes d'exercice).** L'état `.nonCable` (« Vérification temporairement indisponible… »
  permanent, `fn_types_exercice_autorises` non consommée) est verrouillé et documenté, mais le plan se contredit :
  T9 est en vague 3 et le port `InscriptionPort` n'est câblé que par T8 en vague 4. À la livraison de T8 :
  1. `SupabaseInscriptionGateway.typesExercice` câblé dans les deux mondes ;
  2. le cas `ProfilEditionModel.Modes.nonCable` retiré (avec sa branche de `verifierModes`) ;
  3. l'assertion « référentiel non câblé » de `DemoProfilTests.testTypeDExerciceEnRenvoiEtModesSansReferentiel`
     remplacée par les modes autorisés ;
  4. `feat/ios-lot3` n'atteint pas `main` avant T8.

## Intégration de T5, T6 et T9 sur `feat/ios-lot3` (vague 2 bis, 08/11/2026)

T6 et T9 passent leur ligne de `ecranNatifLivre` à `true` sur une base sans T5 ; une fois réunies avec T5, la garde
`CentreNotificationsTests.testToutEcranNatifLivreAUneCibleNativePresentable` exige leurs cibles (section T5
ci-dessus, « à l'intégration »). Ajoutées par l'intégrateur, sans changer aucune règle :

- **Cibles** : `CibleNotification.preferences` (`.parametresNotifications`) et `CibleNotification.profil` (`.profil`,
  tout `?tab=` et l'alias `reputation`), onglet Profil, présentables y compris depuis le centre.
- **Pile de l'onglet Profil** : `NavigationStack(path: $cheminProfil)` dans `MainTabView`, comme l'Accueil ; routes
  `PreferencesNotificationsRoute` (`PreferencesScreen.swift`) et `ProfilEditionRoute` (`ProfilEditionScreen.swift`),
  destinations enregistrées par `MainTabView` sur `ProfileScreen`, hors de la `List`. `presenter` ramène le Profil à
  sa racine puis empile l'écran ; `.monCompte` ramène aussi le Profil à sa racine.
- **Entrées du hub en liens par valeur** (revues L3-T6 m5 et L3-T9 m6) : « Réglages › Notifications »
  (`profile-preferences-notifications`) et « Mon profil » (`profil-ouvrir`), mêmes identifiants, même écran ; elles
  restent à leur place (T11 garde la main sur l'ordre du hub). `JoleneRoute` n'est pas rendue `Hashable` : le
  coordinateur de T3b peut reprendre ces deux routes telles quelles ou les remplacer par `JoleneRoute`.
- **Preuves ajoutées** : `DemoPushTests.testTapLienExpliciteOuvreLesPreferences` et
  `.testTapLienExpliciteOuvreLEditionDuProfil` (cas de tap prévus au §3 T5 du blueprint pour l'écran livré par la
  tranche) ; `DemoNotificationsTests.testLigneLueVersLesPreferencesOuvreLEcranNatif` (la ligne 005 de la fixture,
  déjà lue, devient un bouton « Voir » qui ouvre les préférences). Compilés, jamais lancés : condition de merge
  maintenue (CI trois formats, `xcresult` relu, `skipped = 0`).
- **Point de fusion T3b maintenu (revue L3-T9 m2)** : `/soignant/profil?tab=confidentialite` (RGPD et suppression
  sur le web) ouvre aussi l'édition native ; aucune notification du dump ne pointe vers ce `?tab=` (vecteurs push :
  `/soignant/profil` et `?tab=a` seulement). À trancher par T3b / T11 (renvoi vers le hub, qui porte la suppression).
  **Tranché par T3b** (section suivante) : renvoi web jusqu'à T11, puis le hub (revue B8 de T3b, m3).

## T3b — coordinateur des liens et points d'entrée (reliquat L1-T10, fin de T3 ; branche `lot3/l3-t3b-v2`, 08/11/2026)

T3b ferme T3 (sous réserve de sa revue fraîche B8 et de la CI trois formats) en livrant la partie « liens » de L1-T10,
absente de toutes les branches : point d'entrée unique des liens universels et des taps push.

- **Livré.**
  - JoleneCore `Links/DeepLinkIntent.swift` : `DeepLinkIntent` (classement d'un lien : `.espace`, `.renvoiWeb`,
    `.horsEspace`, `.reinitialisationRefusee`), `AiguillageLiens` (mémorisation avant `.ready`, rejeu une seule fois
    par le premier espace prêt, epoch, taps push par `BoiteTapsPush`, anti-boucle du renvoi web), argument DEBUG
    `-JOLENE_OPEN_URL`, texte du refus.
  - App `Composition/DeepLinkCoordinator.swift` : coordinateur (`ObservableObject`, implémentation de
    `PresentateurRenvoiWeb`), modificateur `PointDEntreeLiens` posé par `JoleneApp` (`onOpenURL`,
    `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`, présentateur dans l'environnement, feuille du renvoi web,
    alerte du refus, libellé DEBUG `deeplink-route`), `SFSafariViewController` en staging/production, double démo sans
    réseau `renvoi-web-demo` (URL dans `renvoi-web-url`, « Fermer » `renvoi-web-fermer`).
  - `AppContainer` : `liens` + `-JOLENE_OPEN_URL` (DEBUG, démo et staging) ; `MainTabView` : l'espace signale son
    ouverture, chaque tap et sa fermeture au coordinateur, et exécute ses demandes de navigation par `presenter`
    (inchangé ; `CibleNotification` `.preferences` et `.profil` compris).
- **Mappage de chaque route** : écran natif si `DestinationLien.ecranNatifLivre`, sinon `.safari(canonique)` par le
  présentateur de renvoi web, jamais `openURL`. Natifs aujourd'hui : Accueil, Explorer, Mes missions (placeholder),
  détail de mission, Revenus aperçu (placeholder), hub `mon-compte`, édition du profil, centre de notifications,
  préférences. Web : sections factures/bulletins/avances (D4) et paiements (T13), Stripe Connect (T14a), inscription
  (T7/T8), détail de série (lot 4), reset et confirmation (ci-dessous), tout chemin servi par Safari, espace
  établissement.
- **Choix et écarts (non juridiques).**
  1. **Renvoi web présenté aussitôt, avec ou sans session.** `LOT1_PLAN.md` §2.5 mémorise tout lien jusqu'à
     `.ready` ; T3b ne mémorise que les destinations de l'espace. Un renvoi n'a pas besoin de l'espace, et un lien
     d'inscription, d'établissement ou reçu sur un compte bloqué ne serait sinon jamais présenté (aucun `.ready`).
     Conséquence traitée par la revue B8 (M1, ci-dessous) : une session web ouverte dans le renvoi sans identité
     native ne survit pas à la connexion suivante (magasin effacé avant chaque `signIn`).
  2. **Reset du mot de passe.** L'écran natif de L1-T10 (`SupabaseRecoveryGateway`, `ResetPasswordScreen`,
     quarantaine de la session de recovery, « Mot de passe oublié ? ») n'est sur aucune branche et n'est pas livré
     ici (point d'extension) : `ecranNatifLivre(.resetPassword)` passe de `true` (« vrai à l'arrivée de L1-T10 ») à
     `false`. Un lien `token_hash` ou implicit ouvre la page web canonique (qui sait le vérifier) ; **option B**
     (décision 7 du lot 1) : un lien `?code=` est refusé dans l'app, jamais échangé ni servi par Safari (le verifier
     n'existe que dans le navigateur demandeur), par une alerte au texte de la décision 7
     (`DeepLinkIntent.Textes.reinitialisationRefusee`, `LOT1_PLAN.md` l.403). Le refus est lu sur la route : il
     survivra à la livraison de l'écran natif.
  3. **Confirmation d'inscription** : `ecranNatifLivre(.confirmerInscription)` passe à `false` jusqu'à T7 (renvoi web
     canonique, la page web vérifie le lien).
  4. Tests changés, et pourquoi (tests faux pour la base fusionnée, pas affaiblis) : `DestinationLienTests`
     (`testTableDesEcransLivres` ; reset et confirmation sortent de `testRoutesDesLots0Et1InchangeesEtNatives` vers
     `testLiensDeRappelSansEcranNatifRenvoyesVersSafariCanonique`) et `CentreNotificationsTests` (exclusion nommée
     réduite à `connexion` ; lien de reset depuis l'espace : renvoi web au lieu de `.aucune`). Les lignes à `true`
     décrivaient des écrans que T3b n'apporte pas : avec le coordinateur branché, ces liens n'auraient rien ouvert.
  5. **Lien et tap en attente** : le plus récent l'emporte à l'ouverture de l'espace, l'autre sert de repli s'il ne
     mène nulle part ; les deux sont consommés. La règle d'epoch de `BoiteTapsPush` (L3-T5) est inchangée.
  6. **Anti-boucle** : tant qu'un renvoi est **effectivement affiché** (apparition du contenu de la feuille, revue B8
     m1), le même lien revenu par lien universel est ignoré (« un `.safari` issu de l'app n'est jamais rejoué comme
     lien universel », `LOT1_PLAN.md` §3 T10).
  7. **Repli d'une cible non présentable** sur le renvoi web canonique (revue L3-T5, m3, levé dans l'aiguillage).
  8. **`push-tap-cible` remplacé par `deeplink-route`** (consigne de T5 ; revue L3-T5 m7 levé). Le libellé est posé à
     la présentation effective (revue B8 de T3b, m7) : quand l'espace exécute la navigation (`demandeTraitee`) et à
     l'apparition de la feuille d'un renvoi. Démo seulement (m8), à la racine de la fenêtre.
  9. Une navigation ou un refus ferment d'abord le renvoi web affiché (le dernier lien reçu reste visible) ; un refus
     reçu pendant un renvoi affiché est présenté après la fin de sa présentation (`onDismiss`, revue B8 m1).
  10. `/soignant/profil?tab=confidentialite` (point de fusion de la revue L3-T9, m2) **reste un renvoi web**
      (`.safari(canonique)`, ligne de `LinkRouter`) jusqu'à ce que L3-T11 livre l'export RGPD au hub (revue B8 de
      T3b, m3) : sur le web, cet onglet porte l'export RGPD et la suppression de compte (`SectionConfidentialite`) ; le
      hub natif n'a que la suppression (L1-T8, `SuppressionCompteSection`) ; « Supprimer mon compte » du hub web y
      renvoie (`MonCompteSoignant.tsx` l.135). Aucune notification du dump ne vise ce `?tab=` (décomptes push
      inchangés). Garde : `LinksRouterTests.testOngletConfidentialiteSuitLExportRGPDDuHub` exige le hub dès que le
      port `exportRGPD` est câblé.
  11. `.horsEspace` (route native livrée sans cible dans l'espace) : liste nommée et fermée réduite à `/connexion`
      (rien à ouvrir), gardée par `DeepLinkIntentTests.testToutLienHorsEspaceAppartientALaListeNommee`.
- **Limites connues.** Une seule feuille par niveau en SwiftUI : un lien reçu pendant qu'une autre feuille est
  ouverte (filtres d'Explorer) n'affiche ni son renvoi web ni l'alerte d'un refus ; depuis la revue B8 (m1), aucun
  état n'en reste collé (le même lien est redemandé sous un nouvel item, un refus suivant est un nouvel item,
  `PresentationsRacine`). Les drapeaux `ios_natif_*_actif` ne filtrent pas encore les liens (`EcransNatifs` de
  `origin/lot1/t9` absent de la base, point de fusion inchangé). Remise réelle d'un lien universel (AASA, CDN Apple,
  Mail) et effacement réel du magasin `SFSafariViewController` : niveau 5 seulement (`RECETTE_DEVICE_LOT3.md`).
- **Migrations d'identifiants XCUITest (règle 8)** : `DemoPushTests` (`push-tap-cible` → `deeplink-route` ; contrat
  et litige : présentation réelle du renvoi, URL vérifiée sur le double démo) ; `DemoNotificationsTests` (lignes lues
  003, 004, 006 vers le web : boutons « Voir », 006 ouvre sa page ; 007 sans lien inchangée) ; `DemoProfilTests`
  (`profil-exercice-web-action` présent, ouvre `/soignant/profil?tab=principal`) ; `DemoAccueilTests` (absence de
  `accueil-oubli-pointage-action` gardée pour la démo par défaut, sans oubli de pointage ; le bouton et son renvoi sont
  prouvés par la variante `JOLENE_FORCE_OUBLI_POINTAGE`, revue B8 m4 : **verrou T12 n°2 du lot 1 levé**).
- **Consignes aux tranches suivantes** (remplacent « une ligne de `DeepLinkCoordinator.swift` ») : la tranche qui
  livre un écran passe sa ligne de `ecranNatifLivre`, ajoute sa cible (`CibleNotification`, `estPresentable`,
  `MainTabView.presenter`) et un cas de tap ; le coordinateur ne change pas. **T7** : inscription et confirmation sont
  consommées hors de l'espace — passer leurs lignes à `true` fait rougir
  `DeepLinkIntentTests.testToutLienHorsEspaceAppartientALaListeNommee` tant que leur présentation hors espace
  (`AiguillageLiens`, `DeepLinkCoordinator`, `RootView`) n'est pas ajoutée. **Reset natif** (reste de L1-T10, sans
  tranche au lot 3) : même verrou ; le refus `?code=` est déjà en place. **T11** : les entrées du hub passent par
  `JoleneRoute` puis `DestinationLien.destination` ; en câblant l'export RGPD (port `exportRGPD`), T11 passe la ligne
  `?tab=confidentialite` de `LinkRouter` à `.monCompte` et ajuste les cas de `DeepLinkIntentTests`
  (`testRoutesSansEcranOuExternesSontDesRenvoisWebCanoniques` → `testRoutesNativesLivreesVontDansLEspace`),
  `CentreNotificationsTests.testCibleDesDestinations` et `LinksRouterTests` — la garde
  `testOngletConfidentialiteSuitLExportRGPDDuHub` est rouge sinon. **T14a** : le retour `?success=true` arrive par le
  même coordinateur (relecture `force=true`, jamais une preuve). **Toute tranche qui ajoute une fin d'identité**
  (verrou biométrique de L1-T9 compris, s'il ferme l'identité) : elle passe par `SessionStore`, qui appelle
  `FinIdentiteWebPort.identiteTerminee()` (une fin transitoire ne l'appelle jamais) ; un nouveau
  `SFSafariViewController` de l'app est présenté par le coordinateur (`presenter`), jamais à part, pour que la fin
  d'identité le ferme.
- **HARD STOP n°4** : aucun texte juridique ; textes repris : refus du reset (décision 7 du lot 1), « Fermer »
  (`FiltresSheet.swift` l.64). Le double démo n'affiche que des URL (données de démonstration), son bouton DEBUG
  `renvoi-web-lien-suivant` compris (libellé = l'URL remise).

### T3b — corrections de la revue fraîche B8 (08/11/2026)

- **M1 — aucune session web ne survit à la fin de l'identité native.** Le `SFSafariViewController` de T3b est le
  premier de l'app ; son magasin (cookies, cache, `localStorage` où le web Supabase garde sa session) appartient à
  l'app et persiste (`SFSafariViewControllerDataStore.h`, SDK iOS 18.5 : « website data accrued from browsing activity
  within your app »). Choix :
  - port injecté `FinIdentiteWebPort` (`JoleneCore/Session/FinIdentiteWeb.swift`), implémenté par `DeepLinkCoordinator`
    et appelé par `SessionStore` **une fois par fin d'identité** : déconnexion volontaire (après la révocation, double
    tap et `.signedOut` du SDK émis pendant la déconnexion compris), fin de compte (`signOutLocally`, après la purge),
    absence de session confirmée par le contrôleur après une identité (espace prêt ou bloqué : `.signedOut` subi,
    revalidation qui ne trouve plus de session) ;
  - **jamais** sur une fin transitoire (restauration hors ligne, profil illisible, connexion refusée : le SDK détient
    encore la session) ;
  - **pas** au lancement à froid sans session (aucune identité dans ce processus) : l'écart n°1 y présente un renvoi
    ouvert par le lien de lancement, que la confirmation de l'absence de session (`start()`, ordre non garanti avec
    `racineVisible`) fermerait sous les yeux de l'utilisateur ;
  - **en plus, avant chaque connexion par mot de passe** (`signIn`) : c'est le seul point par lequel une autre
    identité s'ouvre ; il couvre les trois cas que les fins ne voient pas — identité close hors de l'app (session
    révoquée app fermée, puis lancement sans session), session web ouverte sans identité native (écart n°1), identité
    remplacée après une fin transitoire (connexion d'un autre compte depuis « Réessayer »). Coût : une connexion native
    explicite repart d'un magasin web vide (reconnexion web au prochain renvoi), sans effet sur une restauration ;
  - effet (app) : le renvoi affiché est fermé (`fermerRenvoiWeb()`, la feuille posée sur la racine ne survit plus au
    changement d'état), puis, hors démo, `SFSafariViewController.DataStore.default.clearWebsiteData` (iOS 16.0, cible
    16.0) ; un renvoi demandé pendant l'effacement est **différé jusqu'à sa fin** (`PresentationsRacine`), une nouvelle
    fin d'identité l'abandonne. En démo, aucun effacement (le double n'a ni réseau ni données ; « sans effet en démo »),
    la feuille du double est fermée comme ailleurs ;
  - preuves niveau 1 : `SessionStoreFinIdentiteWebTests` (13 tests : un appel par fin, port indépendant du push, zéro
    sur les fins transitoires et le lancement sans session, appel avant `signIn`) et `PresentationsRacineTests`
    (report pendant l'effacement). L'effacement réel n'est mesurable que sur appareil (`RECETTE_DEVICE_LOT3.md`).
  - Renommage : `SessionStore.suivrePush` devient `suivreIdentite` (l'identité est suivie avec ou sans push ; les
    appels push sont inchangés) ; la consigne de fusion de L1-T9 (`REVUES_LOT3.md`, section L3-T4, « garder le
    `didSet { suivrePush… }` ») se lit avec ce nom.
- **m1 — présentation à la racine sans état collé.** `JoleneCore/Links/PresentationsRacine.swift` (niveau 1,
  `PresentationsRacineTests`) : l'anti-boucle et `deeplink-route` sont posés à l'apparition effective du contenu de la
  feuille (`onAppear`), levés à sa disparition (`onDisappear`), par numéro d'item ; un refus reçu pendant un renvoi
  affiché attend la fin de sa présentation (`onDismiss`) ; chaque refus est un nouvel item numéroté, présenté par un
  hôte recréé (`.id`), si bien qu'un refus jamais affiché ne fait plus taire les suivants. Preuve niveau 2 :
  `DemoLiensLot3Tests.testRenvoiAffichePuisLienDeReinitialisationAlerteApresLaFermeture` (lien remis pendant le renvoi
  par le bouton DEBUG `renvoi-web-lien-suivant` du double, argument `-JOLENE_OPEN_URL_SUIVANT`, démo seulement) et
  `testLienDeReinitialisationPkceRefuseParUneAlerte`.
- **m2 — le centre ne contourne plus l'option B** : `CibleNotification.init` rend `.aucune` pour
  `/reset-password?code=…` (lu sur la route, comme `DeepLinkIntent`) ; ni « Voir » ni bouton sur une ligne lue, une
  ligne non lue est marquée lue sans rien ouvrir (`CentreNotificationsTests.testLienDeReinitialisationPkceJamaisServiParLeCentre`).
- **m3 — `?tab=confidentialite`** : renvoi web jusqu'à L3-T11 (point 10 ci-dessus), garde automatique liée au port
  `exportRGPD`.
- **m4 — verrou T12 n°2 du lot 1 levé** : variante démo `JOLENE_FORCE_OUBLI_POINTAGE=1`
  (`DemoDashboardGateway(missionsOubliees: 1)`, `DemoDashboardTests.testVarianteOubliDePointageNeChangeQueLeCompteur`)
  et XCUITest trois formats `DemoAccueilTests.testOubliDePointageOuvreLesPresencesSurLeWeb`
  (`accueil-oubli-pointage-action` → `renvoi-web-demo` sur `https://jolene.app/soignant/presences`).
- **m5 — Explorer revient à sa racine** : `NavigationStack(path: cheminExplorer)` dans `MainTabView`, vidée par
  `presenter(.explorer)` (lien universel ou tap). Mes missions et Revenus n'ont pas encore de pile (placeholders) : leur
  tranche (L1-T5, L3-T12) leur donne un chemin vidé de la même façon. Prouvé par le code seulement (aucun moyen démo de
  remettre un lien pendant un détail d'Explorer ; niveau 5 au besoin).
- **m6 — docstrings alignées** : `PushTapIntent.libelleDebug` (`deeplink-route`, posé par le coordinateur à la
  racine) ; `CibleNotification` (`.profil` hors `confidentialite`, `.web` pour reset et confirmation, `.aucune` pour la
  connexion et `?code=`, présentateur injecté depuis L3-T3b).
- **m7** : libellé à la présentation effective (point 8 ci-dessus).
- **m8 — couverture** : absence bornée (attente inversée `requireAbsence`, `UITestSupport.swift`) dans
  `liensAucunePresentationSurLaConnexion` ; XCUITest du lien universel vers un détail de mission
  (`testLienDetailDeMissionOuvreLeDetailNatif`, `LOT1_PLAN.md` §3 T10) ; niveau 1 « tap plus récent écarté par
  l'epoch → repli sur le lien mémorisé » (`DeepLinkIntentTests.testTapPlusRecentEcarteParLEpochRepliSurLeLienMemorise`).
- Aucun texte nouveau, aucun texte juridique ; aucune RPC ; aucun test sauté, désactivé ni affaibli. Tests changés,
  et pourquoi : `?tab=confidentialite` passe du hub au renvoi web dans `LinksRouterTests`, `DeepLinkIntentTests` et
  `CentreNotificationsTests` (le hub n'a pas l'export : l'attendu « hub » était faux pour la base) ; l'absence
  instantanée de `liensAucunePresentationSurLaConnexion` devient une absence bornée (plus stricte).

## T7 — inscription : compte rapide, confirmation, aiguillage onboarding (branche `lot3/l3-t7-v2`, 08/11/2026)

- **Livré.** Cœur (`JoleneCore/Inscription/`) : `InscriptionRules` (validation `InscriptionRapide.tsx` l.58-70,
  intention et `user_metadata.inscription_progressive` l.46-52 et l.74, refus GoTrue traduits comme
  `mapperErreurInscription`, exceptions 22023 / 23505 de `fn_demarrer_inscription`), `OnboardingResolution`
  (`registrationIntent`, `registrationDraft`, décision de `ParcoursInscription.tsx` l.39-75), modèles
  `InscriptionRapideModel`, `ConfirmationInscriptionModel` (échange tenté une seule fois, D10), `OnboardingModel`
  (epoch), `BoiteLiensInscription` ; monde démo `DemoInscriptionGateway` ; gateway `SupabaseInscriptionGateway`
  (`signUp` sans captcha vers `https://jolene.app/inscription/confirmer`, `verifyOTP` / `setSession` /
  `exchangeCodeForSession`, `GET /auth/v1/user`, `parcours_inscription` sous RLS, `fn_demarrer_inscription` avec
  `exceptionsMetier`). Écrans : « Créer un compte soignant » sur la connexion (`login-create-account`), compte rapide
  (`InscriptionRapideScreen`), lien de confirmation (`ConfirmationInscriptionScreen`), aiguillage
  (`OnboardingRootView`) ; `RootView` sert `.blocked(.unsupportedRole(nil | "PROFIL_INCOMPLET"))` par l'aiguillage,
  tout autre `.blocked` garde l'écran du lot 0. `fn_demarrer_inscription` passe en `consommee` (définition live relue
  en lecture seule le 08/11/2026, identique au dump l.30148-30189 ; politique `parcours_inscription_proprietaire`
  identique).
- **Préalable non mesuré (§3 T7, §6.11, D25).** `PORTE_LOT0.md` 3.1 (STAGING) et 3.2 (production) sont « non
  mesurées » : aucun dispatch n'est permis à cette tranche. T7 livre donc le `signUp` natif sans jeton captcha ; un
  refus captcha (`captcha_failed`, message contenant « captcha ») rend le message générique du web
  (`erreurs.ts` l.178) avec le code `CAPTCHA_FAILED`, et le renvoi vers `/inscription/soignant` n'est proposé que
  par le présentateur `.safari` de L1-T10 (absent : aucun bouton). **Si la mesure 3.1 ou 3.2 renvoie un refus
  captcha, D25 s'applique avant le merge** : « Créer un compte » devient un renvoi web, la confirmation et
  l'aiguillage restent natifs.
- **Manque — coordinateur de liens (L1-T10 / T3b).** Ni `onOpenURL`, ni `onContinueUserActivity`, ni
  `-JOLENE_OPEN_URL` sur la base : à l'exécution, un lien `/inscription/confirmer` n'atteint pas l'app. Point
  d'extension minimal : `AppContainer.liensInscription` (`BoiteLiensInscription`) ; le coordinateur y dépose la
  `DestinationLien` reçue (`recevoir(_:)` rend vrai pour `.confirmerInscription` et `.inscription`, faux pour toute
  autre destination, qu'il présente lui-même) ; `RootView` présente la confirmation au-dessus de tout état puis relit
  la session, et `/inscription/soignant` hors session ouvre le compte rapide (profession du lien pré-remplie comme
  `lireCriteresInscription`). L'XCUITest « lien démo → onboarding » du blueprint attend `-JOLENE_OPEN_URL` : la
  confirmation est prouvée au niveau 1 (`InscriptionModelsTests`, `DemoInscriptionGatewayTests`,
  `SupabaseInscriptionGatewayTests`) ; le monde démo accepte déjà
  `https://jolene.app/inscription/confirmer?token_hash=demo&type=signup`. À l'arrivée du coordinateur : un
  `DemoLiensLot3Tests` couvre ce lien et `/inscription/soignant?profession=IDE`.
- **Ligne de T7.** `DestinationLien.ecranNatifLivre(.inscription(soignant | reprendre))` vaut `true` ;
  `DestinationLienTests` déplace les deux cas vers `testRoutesLot3AvecEcranLivreSontNatives` (aucun vecteur push ne
  mène à l'inscription : totaux inchangés). **Exclusion nommée ajoutée** à
  `CentreNotificationsTests.sansCibleDansLEspace` : `inscriptionSoignant`, `inscriptionReprendre`. Justification : ces
  pages sont consommées hors de l'espace prêt (écran de connexion, aiguillage d'onboarding), comme la connexion et
  les liens de rappel ; une identité qui a un espace prêt n'a pas d'inscription à faire. `CibleNotification` rend
  `.aucune` pour `.inscription` (rien n'est présenté depuis l'espace). T8 ajoutera `inscriptionCompleter` avec sa
  propre ligne.
- **Écarts assumés (non juridiques).**
  - « J’ai confirmé mon email » et « Se connecter et continuer » (web l.63-68 : `signInWithPassword`) passent par
    `SessionStore.signIn` : un refus affiche les messages de connexion du lot 0 sur l'écran de connexion, adresse
    reprise, et non les deux textes web propres à ce chemin (l.103, l.105). Le parcours est ensuite démarré par
    l'aiguillage depuis `user_metadata` (repli de `ParcoursInscription.tsx`), jamais par la seule intention locale.
  - « Je suis soignant » (session déjà ouverte) : formulaire réduit à la profession et au consentement (adresse de la
    session affichée), puis `fn_demarrer_inscription` ; le web réaffiche adresse et mot de passe, ignorés pour une
    session de même adresse (`creerCompteRapide` l.56-62).
  - Pas de bouton « Afficher le mot de passe » ; la `ville` d'un lien de recherche publique
    (`memoriserRecherchePublique`) n'est pas mémorisée pour Explorer.
  - Un `signUp` qui ouvre une session puis un démarrage refusé : message affiché, session SDK conservée sans
    `start()` (comme le web, qui reste sur le formulaire) ; un nouvel appui ne refait pas de `signUp`
    (`creerCompte` reconnaît la session de même adresse).
  - « Je représente un établissement » n'existe qu'avec le présentateur `.safari` ; un parcours ou une intention
    établissement affiche l'écran bloquant du lot 0 (message de rôle non servi), sans jamais réserver un compte
    établissement depuis l'app.
  - Mention du lot 0 « Pas encore de compte ? L'inscription se fait sur jolene.app. » retirée de la connexion.
  - Démo : aucun e-mail, la confirmation est réputée faite (le compte créé se connecte aussitôt) ; le parcours est
    construit en mémoire depuis l'intention (pas de `demo-parcours.json`) ; `DemoRoleGateway` reste SOIGNANT, si bien
    que le nouveau compte démo passe par « profil incomplet » (le serveur rend `INCONNU`) : même aiguillage.
- **Point d'extension T8 (complétion).** L'état `OnboardingModel.Etat.completerSoignant` affiche l'écran bloquant
  du lot 0 (titre « Espace non disponible », message « Votre profil soignant n'est pas encore complet… »,
  identifiant `onboarding-completion`, « Se déconnecter »). T8 :
  1. remplace ce rendu par `CompletionProfilScreen` ;
  2. câble `enregistrerBrouillon`, `typesExercice` et `finaliser` dans `SupabaseInscriptionGateway` et
     `DemoInscriptionGateway` (elles lèvent aujourd'hui « …livré par la tranche T8 du lot 3 », verrou testé dans les
     deux mondes) ;
  3. remplace dans `DemoInscriptionTests.testCreationPuisConfirmationOuvreLAiguillageEtLaCompletionEnAttente`
     l'assertion `onboarding-completion` par l'écran de complétion ;
  4. ajoute ses codes à `RefusInscriptionDemo` (`-JOLENE_DEMO_INSCRIPTION_REFUS`).
- **Consigne de T4 (`RootView`)** : `secondaryIsLoading: session.deconnexionEnCours` conservé sur `access-blocked` ;
  chaque « Se déconnecter » de l'aiguillage (`logout-button`) lit aussi `deconnexionEnCours` (attente visible,
  second tap ignoré).
- **HARD STOP n°4.** Aucun texte nouveau ni reformulé : textes web verbatim de `InscriptionRapide.tsx`,
  `ConfirmationInscription.tsx`, `ParcoursInscription.tsx`, `PageConnexion.tsx` l.334 et `src/lib/erreurs.ts`,
  messages serveur verbatim de `fn_demarrer_inscription` (22023), libellés natifs du lot 0 réutilisés tels quels.
  La phrase de consentement est l'assemblage exact du JSX l.264-284 (« J’accepte les CGU et la politique de
  confidentialité. »), ses liens ouvrent `/cgu` et `/confidentialite` dans `SFSafariViewController`. Garde locale
  `InscriptionVerbatimTests` (chaque annotation `// source:` relue contre son fichier, en attendant
  `check-textes-juridiques-ios.mjs` de L2-TL, absent de la base du lot 3). **À relire par Gabrielle** : la phrase de
  consentement et ses deux liens ; le choix du message générique (au lieu du texte captcha du web, « Rafraîchissez
  la page… ») pour un refus captcha.
- **B9.** Go humain requis (D18) : consentement CGU transmis par `p_cgu` à `fn_demarrer_inscription`.

## T11 — hub Compte : mot de passe, thème, export RGPD (branche `lot3/l3-t11-v2`, 08/11/2026)

- **Livré.** Hub `ProfileScreen.swift` étendu (seule surface, correction 18) :
  - « Réglages » : « Notifications » (préférences de T6, `profile-preferences-notifications`, inchangée, aucune
    seconde carte d'autorisation) et le thème Système / Clair / Sombre (D16, `compte-theme-*`) ;
  - « Connexion & sécurité » › « Changer mon mot de passe » (`compte-mdp-ouvrir` → `MotDePasseScreen`) ;
  - « Mes données (RGPD) » : export JSON / CSV (`compte-export-*`) par la feuille de partage ;
  - « Aide & légal » (centre d'aide, confidentialité, CGU, mentions légales), servie par Safari ;
  - « Mon profil » (T9) et « Suppression de compte » (L1-T8, dernière section) conservées.
  Ports `motDePasse` et `exportRGPD` câblés dans les deux mondes (`DemoMotDePasseGateway`, `DemoExportRGPDGateway`,
  `SupabaseMotDePasseGateway`, `SupabaseExportGateway`) ; `fn_rgpd_exporter_rate_limited` consommée.
- **Ordre du hub (écart assumé).** Le bloc du lot 0 (« Compte », « Se déconnecter », « Application ») reste en tête :
  les XCUITest des lots 0 à 3 lisent `profile-email`, `logout-button` et `network-sentinel` sans défilement, et ces
  tests ne sont pas exécutables localement. Le reste suit l'ordre du hub web ; le web place « Se déconnecter » après
  « Aide & légal ». Aucun identifiant existant n'a été déplacé ni renommé (règle 8 sans objet).
- **Mot de passe (D13).**
  - Ancien vérifié par `signIn` sur l'email de la session courante, si cette session est celle de l'écran ; un
    utilisateur renvoyé différent est un refus.
  - `.session(même id)` émis par `signIn` puis `update(user:)` n'avance pas l'epoch (test
    `MotDePasseModelTests.testSessionDuMemeUtilisateurNeChangePasDEpoch`).
  - Refus GoTrue traduits comme `extraireMessageErreur` (table `traductions`, `weak_password`, message générique) ;
    jamais le message anglais.
  - Réauthentification exigée (`reauthentication_needed` / `_not_valid`) : refus verrouillé pour la durée de
    l'écran, sans flux OTP. Ce cas est presque inaccessible : la vérification ouvre une session neuve, et GoTrue
    n'exige le nonce que pour une session de plus de 24 h.
  - Écarts assumés : pas de bouton « Afficher / Cacher » (champs sécurisés iOS) ; toasts web rendus en encarts
    annoncés ; délai ou coupure → message natif « non confirmé » (le serveur a pu changer le mot de passe), jamais
    un succès.
  - Garde d'identité (revue B8, m2) : le port reçoit `identiteCourante` (epoch de l'écran), consultée une fois entre
    la vérification et la mise à jour. Si un `.signedOut` (révocation, refresh refusé) arrive pendant le `signIn` de
    vérification, ce `signIn` recrée une session dans le SDK alors que l'app affiche la connexion
    (`SessionController` ignore `.session` sans identité active) : aucune mise à jour ne part, et cette session est
    retirée par `signOut(scope: .local)`, seulement si le SDK tient encore le jeton de la vérification (une connexion
    arrivée après n'est jamais retirée). Course résiduelle consignée : une reconnexion du même utilisateur entre la
    révocation et la réponse du `signIn` voit sa session remplacée par celle de la vérification, puis retirée ;
    l'écran de connexion s'affiche à nouveau (aucun changement de mot de passe).
  - Modèle tenu par le hub (revue B8, m3) : `MainTabView` remet la pile du Profil à sa racine sur un tap push ou une
    ligne du centre (`.monCompte`, `.preferences`, `.profil`), ce qui dépile `MotDePasseScreen` en pleine demande
    (`navigationBarBackButtonHidden` ne couvre pas un retour programmé). La demande continue, et son issue est
    annoncée par le hub (`compte-mdp-issue-hub`, textes de l'écran) jusqu'à la réouverture de l'écran. Un retrait
    hors demande efface formulaire, issue et verrou (démontage du composant web) ; un changement d'onglet ne retire
    pas l'écran (jeton `JetonEcranMotDePasse`, état de l'instance). `MainTabView` n'est pas modifié. Preuve
    niveau 1 (`MotDePasseModelTests`, `testEcranRetirePendant…`, `testRetrait…`).
- **Rejeu du SDK (revue B8, m1 ; remplace la « limite du SDK » de la première livraison).** Le client
  d'authentification de supabase-swift 2.55.5 rejoue une fois un PUT ou un POST sur une erreur réseau transitoire ou
  un 408/5xx (`RetryRequestInterceptor`, `Auth/Internal/APIClient.swift` l.11-16 ; délai d'une seconde). La gateway
  n'appelle `update(user:)` qu'une fois et le rejeu porte le même corps. Le transport n'est pas changé ; la gateway
  interprète désormais les deux issues ambiguës :
  - `same_password` alors que l'ancien vient d'être vérifié et que le nouveau en diffère (octets UTF-8, sur les
    72 octets que lit bcrypt : `MotDePasse.memeMotDePasseProuveLaModification`) prouve que le mot de passe vaut déjà
    le nouveau (rejeu d'un PUT abouti dont la réponse a été perdue) → `.modifie`, « Mot de passe modifié avec
    succès. » ; un nouveau égal à l'ancien (ou de mêmes 72 premiers octets) reste le refus web générique ;
  - 5xx ou 408 sur le PUT (après le rejeu) : issue inconnue (`JoleneError(.unknown)` →
    `confirmationIndisponible`), jamais « Une erreur est survenue. Veuillez réessayer. ». Sur la vérification
    (`signIn`), rien n'a changé : le refus générique du web reste juste.
  Le cas `same_password` de la table des refus de la première livraison était faux pour un nouveau distinct :
  déplacé vers des tests dédiés (`SupabaseMotDePasseGatewayTests`, « Rejeu du SDK et issue inconnue »). Les autres
  appels GoTrue de l'app (connexion du lot 0) ne mutent rien : un rejeu y est sans effet de bord.
- **Thème (D16).**
  - Le choix est appliqué à la racine par `ThemeRacine` (une ligne de `JoleneApp.swift`) : `preferredColorScheme`,
    plus le style des fenêtres de la scène. Ce second réglage couvre le retour à « Système » sous iOS 16 et les
    contrôleurs UIKit présentés.
  - Persistance par appareil (`UserDefaults`, clé `jolene.theme`, sans identifiant de compte) en staging et
    production, en mémoire vive en démo, comme le pré-prompt de T5. Elle est prouvée au niveau 1
    (`PreferenceThemeTests`) ; le XCUITest prouve l'application (`compte-theme-effectif`, DEBUG et démo).
- **Export RGPD.**
  - Contrat serveur relu sur la définition live (lecture seule, 08/11/2026) : corps identiques au dump.
  - Corps lu octet pour octet, puis relu dans l'ordre des clés d'un objet JavaScript (`JSONOrdonne`). JSON
    `JSON.stringify(…, null, 2)` et CSV `flatten` sont identiques au web ; les attendus des tests ont été produits
    par le code web lui-même, sous Node.
  - Fichier écrit avec `NSFileProtectionComplete` dans un dossier propre à l'export, supprimé à la fin de la
    feuille ; les résidus d'un arrêt brutal sont purgés au lancement (`AppContainer`) et à la création du hub ; une
    fin de session feuille ouverte (epoch avancé, hub détruit) supprime le fichier sans attendre et ferme la feuille
    (revue B8, m8).
  - Feuille de partage, une seule source de fin (revue B8, M1) : `UIActivityViewController` présenté par UIKit
    depuis le contrôleur au sommet de la fenêtre (popover centré sans flèche sur iPad), fin UNIQUEMENT dans
    `completionWithItemsHandler`, relayée de façon synchrone (`MainActor.assumeIsolated`) à
    `ExportRGPDModel.partageTermine(complete:)`. La `.sheet` SwiftUI de la première livraison est retirée : quand une
    activité aboutit, le contrôleur se ferme lui-même, et le setter du binding (`complete: false`) arrivait avant le
    handler, qui tombait sur un fichier déjà retiré — « Données exportées en JSON. » ne s'affichait jamais.
  - Présentation seulement hub à l'écran (revue B8, m3) : un export abouti pendant qu'un autre onglet ou un écran
    empilé est affiché attend le retour du hub (`ExportRGPDModel.fichierAPresenter`, `hubAffiche`), boutons inactifs
    entre-temps ; jamais une feuille présentée depuis un onglet caché, jamais deux feuilles.
  - Preuves : niveau 1 (`ExportRGPDModelTests`, présentation, fin unique, fin de session, purge) ; niveau 2
    (`DemoCompteLot3Tests`, trois formats, compilé, non lancé localement) : feuille fermée sans partage → aucun
    succès, boutons réactivés, fichier supprimé (libellé DEBUG `compte-export-residus` = « 0 »), « 0 requête » ;
    « Copier » → « Données exportées en JSON. ».
  - Écarts assumés : « Données exportées en JSON. » seulement après un partage abouti (le web l'annonce aussi
    feuille fermée) ; audit `RGPD_EXPORT_DONNEES` après l'écriture du fichier (le web l'écrit avant) ; corps non
    objet → refus de contrat (le web l'exporterait).
  - Unicode (revue B8, m4) : doublement des `"` du CSV scalaire par scalaire (un `"` suivi d'une marque combinante
    est doublé, comme `replace(/"/g, '""')`), clés et chaînes comparées octet pour octet (deux clés « é » NFC et NFD,
    distinctes pour `JSON.parse` et le jsonb, ne sont plus fusionnées) ; vecteur produit par le web sous Node
    (`ExportRGPDTests.testUnicodeSansEquivalenceCanoniqueCommeJavaScript`).
  - Variante de recette DEBUG `JOLENE_FORCE_EXPORT_ECHEC=1` : refus serveur verbatim en démo.
- **Signalement `notations_recues` (confirmé live).** L'écran n'expose rien du contenu : il transmet à la feuille de
  partage le fichier du serveur, comme le web. Les notes reçues non publiées passent donc par le fichier, sur les
  deux surfaces. Ce point est serveur et n'est pas corrigé ici (voir « En attente de Gabrielle »).
- **Manques et points d'extension (aucune entrée sans écran ni présentateur : jamais un lien sans effet).**
  - « Aide & légal » n'est monté qu'avec le présentateur `.safari` de L1-T10 (absent de la base).
    `DemoCompteLot3Tests` affirme son absence ; T10 remplace cette assertion par l'ouverture Safari.
  - Paiements et Stripe (T14a) : aucune entrée. La règle web `estLiberal` (l.45-48) lit aussi `statut_liberal`,
    absent du snapshot.
  - Coordonnées bancaires (T14b) : sous-ligne de `/soignant/mon-compte`, sans route ; T14b pose son entrée.
  - Sécurité biométrique : L1-T9 absent de la base.
  - « Contacter Jolene » : modale web `ModalContacterJolene`, sans page ni équivalent natif.
  - Centre de notifications : pas d'entrée au hub (le web n'en a pas, il s'ouvre depuis l'Accueil).
  - Renvoi « Mot de passe oublié ? » du refus verrouillé (revue B8, m6) : ce lien de l'écran de connexion
    (`login-forgot`) n'existe pas sur `LoginScreen.swift` dans cette base ; il arrive avec L1-T10, et ne s'atteint
    qu'après une déconnexion. Dépendance à L1-T10 ; le texte (`MotDePasse.Textes.reauthentificationRequise`) reste à
    relire par Gabrielle (section HARD STOP). Le cas est presque inaccessible (session de vérification neuve).
- **Écarts au blueprint v2 §3 T11, à acter par l'intégrateur (revue B8, m9).**
  - Pas d'entrée `.notifications` (centre) au hub : le hub web n'en a pas, le centre s'ouvre depuis l'Accueil (T5).
  - Pas d'entrées Paiements / Stripe ni Coordonnées bancaires, même en renvoi Safari : reprises T14a et T14b.
  - « Aide & légal » masqué tant que le présentateur `.safari` de L1-T10 manque : reprise T10.
  - Bloc du lot 0 en tête du hub (ordre ci-dessus).
- **Point de fusion T3b.** `/soignant/profil?tab=confidentialite` (RGPD et suppression sur le web) ouvre toujours
  l'édition native. Le hub porte désormais l'export et la suppression : recommandation pour T3b, router ce `?tab=`
  vers `.monCompte` (fichiers de T3, non modifiés ici).
- **HARD STOP n°4.** Textes repris du web à leur ligne (`CompteVerbatimTests`), textes RGPD de l'export en tutoiement
  verbatim, aucun texte juridique nouveau. Refus serveur de l'export localisés dans le corps de
  `fn_rgpd_exporter_rate_limited` (en-tête de la fonction dans le dump), ligne du dump seulement indicative : un
  `schema-snapshot` ne fait plus rougir JoleneCore (revue B8, m5). Textes natifs sans équivalent web : puce « T11 — textes sans équivalent
  web » de la section HARD STOP ci-dessous. **B9** : non (D18).

## Intégration de T3b, T7 et T11 sur `feat/ios-lot3` (vague 3, 09/11/2026)

Fusions `--no-ff`, dans l'ordre : `origin/main` (#1120, #1122, hors `ios-native/`), `origin/fix/ios-tests-instables`
(trois tests iOS instables du lot 1 : `require` borné et tracé, `dragSliderPastMinimum`, annulations du port Explorer),
`lot3/l3-t3b-v2`, `lot3/l3-t7-v2`, `lot3/l3-t11-v2`. T7 et T11 ont été écrites sur une base sans le coordinateur de
T3b : leurs points d'extension « en attendant L1-T10 / T3b » sont branchés ici, sans changer aucune règle ni aucun
texte. Correctif d'intégration (tests d'abord), chaque test changé étant faux pour la base fusionnée, jamais affaibli :

- **Confirmation et inscription présentées hors de l'espace (T7 × T3b, consigne de T3b).**
  - `DestinationLien.ecranNatifLivre(.confirmerInscription)` repasse à `true` : T3b l'avait mise à `false`
    « jusqu'à T7 », qui livre `ConfirmationInscriptionScreen` (`InscriptionModelsTests` et la garde de
    `CentreNotificationsTests` étaient rouges à la fusion).
  - `AiguillageLiens.Action.inscription(DestinationLien)` : un lien `.horsEspace` de confirmation ou de page
    `soignant` / `reprendre` rend cette action aussitôt, avec ou sans espace, jamais mémorisée ni rejouée ; la
    connexion reste sans action. `DeepLinkCoordinator` (initialisé avec `AppContainer.liensInscription`) ferme le
    renvoi affiché puis dépose le lien dans `BoiteLiensInscription`, que `RootView` présente (confirmation au-dessus
    de tout état ; compte rapide hors session). La liste nommée de
    `DeepLinkIntentTests.testToutLienHorsEspaceAppartientALaListeNommee` devient connexion, confirmation, inscription ;
    nouveau test `testLiensDInscriptionEtDeConfirmationPresentesHorsDeLEspace` ; exclusion nommée de
    `CentreNotificationsTests` : connexion, confirmation, pages `soignant` et `reprendre` (le reset, renvoi web depuis
    T3b, n'y est plus).
  - `RootView` : un lien `/inscription/soignant` reçu pendant la restauration (lancement à froid, `-JOLENE_OPEN_URL`)
    reste dans la boîte jusqu'à l'issue de la session (`onChange(of: session.state)`) ; T7 l'écartait avant de savoir
    s'il y avait une identité, ce qui rendait le lien de lancement inerte.
  - Revue B8 de T3b, m4 (T7) : `SessionStore.ouvrirIdentiteInscription()` vide le navigateur intégré
    (`FinIdentiteWebPort`) avant la relecture d'une identité ouverte **hors de `signIn`** — compte créé avec session
    puis parcours démarré, lien de confirmation échangé (y compris celui d'un autre compte reçu dans un espace ouvert).
    `RootView` l'appelle à la place de `start()` dans ces deux cas ; test
    `SessionStoreFinIdentiteWebTests.testOuvertureDIdentiteParLInscriptionEstPrecedeeDUnAppel`. **Restent** :
    `refreshSession` de T8 et le reset natif (même appel avant d'ouvrir l'identité, consigne inchangée de T3b).
  - Écart consigné (non juridique) : les pages `/cgu` et `/confidentialite` de la phrase de consentement restent un
    `SFSafariViewController` présenté par une feuille du formulaire (T7), et non par le présentateur de T3b : le
    formulaire est lui-même une feuille dans l'aiguillage d'onboarding (« Je suis soignant ») et la racine ne peut pas
    présenter par-dessus (une seule feuille par niveau, limite connue de T3b). Cette feuille disparaît avec son hôte à
    toute fin d'identité, et le magasin effacé est le même (`SFSafariViewController.DataStore.default`). En démo, ces
    deux liens ouvriraient la page réelle : aucun XCUITest ne les touche ; à reprendre si une recette démo les exerce.
- **`?tab=confidentialite` → hub (T11 × T3b, consigne de T3b et recommandation de T11).** La ligne de `LinkRouter`
  passe de `.safari(canonique)` à `.monCompte` dès que le port `exportRGPD` est câblé (garde
  `LinksRouterTests.testOngletConfidentialiteSuitLExportRGPDDuHub`, rouge à la fusion) ; cas déplacés dans
  `LinksRouterTests`, `DeepLinkIntentTests` (`testRoutesNativesLivreesVontDansLEspace`) et
  `CentreNotificationsTests.testCibleDesDestinations`. Aucune notification du dump ne vise ce `?tab=`.
- **« Aide & légal » monté (T11 × T3b).** Le présentateur `.safari` est injecté à la racine : la section du hub
  s'affiche. `DemoCompteLot3Tests` affirmait son absence ; remplacé (règle 8, consigne de T11) par
  `testAideEtLegalOuvreLesPagesPubliquesParLeRenvoiWeb` (quatre pages, URL canonique sur le double démo).
  `DemoInscriptionTests` : le renvoi web du refus captcha (D25, `inscription-renvoi-web`) existe désormais —
  `testRefusCaptchaAfficheLeMessageGeneriqueSansRenvoi` devient `…EtLeRenvoiWeb` (bouton, puis page
  `/inscription/soignant` sur le double). « Je représente un établissement » de l'aiguillage apparaît de même.
- **XCUITest ajoutés à `DemoLiensLot3Tests`** (trois formats, compilés, non lancés localement) : `/soignant/mon-compte`
  → hub (revue n°2 de T3b, m5) ; `?tab=confidentialite#suppression-compte` → hub avec l'export ;
  `/inscription/soignant?profession=IDE` → compte rapide, profession pré-remplie (formulaire accepté sans choisir la
  profession) ; `/inscription/confirmer?token_hash=demo&type=signup` → confirmation, puis aiguillage et complétion en
  attente (consigne de T7 « à l'arrivée du coordinateur »).
- **Écarts au blueprint v2 §3 T11 actés par l'intégrateur (revue B8 de T11, m9)** : pas d'entrée centre de
  notifications au hub (le hub web n'en a pas) ; pas d'entrées Paiements / Stripe ni Coordonnées bancaires (reprises
  par T14a et T14b) ; bloc du lot 0 en tête du hub. « Aide & légal » n'est plus un écart (monté ci-dessus). Écarts non
  juridiques, sans texte nouveau.
- Aucun texte nouveau, aucun texte juridique, aucune RPC, aucune écriture serveur. B9 inchangé : T7 reste soumise au
  go de Gabrielle et au préalable captcha (section T7).
- **Durée de la CI UI : quatre éclats (même règle que DECISIONS_LOT2, décision 22).** Au run 42536888984 (première
  recette de la base fusionnée), l'étape unique `test-without-building` a dépassé ses 30 min sur iphone et
  ipad-portrait après 35 des 58 XCUITest, tous réussis sur ipad-portrait ; au run 42541548740 (trois éclats), l'éclat
  push + centre + préférences + profil prenait 27,5 min sur iphone (push 11 min, profil 7, préférences 5,
  centre 3). `ios-swift-ci.yml` exécute désormais, dans chaque job de format, quatre éclats successifs bornés à 30 min
  chacun (job à 140 min) : « socle » (JoleneCoreTests, JoleneDesignTests, XCUITest des lots 0 et 1, et toute classe
  nouvelle non rangée), « lot3-compte » (`DemoLiensLot3Tests`, `DemoInscriptionTests`, `DemoCompteLot3Tests`),
  « lot3-push » (`DemoPushTests`) et « lot3-notifications » (`DemoNotificationsTests`, `DemoPreferencesTests`,
  `DemoProfilTests`). Le résumé exige chaque éclat vert, chaque classe de lot démarrée, 0 échec, `skipped = 0`,
  `passed = total`, ≥ 100 tests, orientation des captures. Aucun test retiré. **Point de fusion avec le lot 2**
  (éclats « socle » + « lot2 », même structure) : garder les éclats des deux lots et unir les `-skip-testing` de
  l'éclat socle.
- **Run 42541548740, UI — iphone : `DemoProfilTests.testTypeDExerciceEnRenvoiEtModesSansReferentiel` rouge (défaut
  du code, T7 × T9).** L'édition du profil (T9) tenait les modes d'exercice pour « non câblés » seulement si le port
  `inscription` était un `UnwiredPort` ; T7 le câble (`DemoInscriptionGateway`, `SupabaseInscriptionGateway`) tout en
  refusant la complétion jusqu'à T8 : le refus donnait l'état « indisponible » avec « Réessayer la vérification »,
  bouton qui échouerait toujours. `InscriptionPort.completionLivree` (défaut `true`, `false` pour le stub et pour les
  deux gateways de T7 ; **T8 le passe à `true`** avec ses trois appels) ; `ProfilEditionModel.verifierModes` rend
  `.nonCable` sans appel. Tests : `ProfilEditionModelTests`, `DemoInscriptionGatewayTests`,
  `SupabaseInscriptionGatewayTests` (verrou T8).
- **Même run, UI — iphone** : `DemoCompteLot3Tests.testExportJSONFeuilleFermeeSansPartageAucunSucces` (T11, jamais
  exécuté avant) échouait : la feuille de partage iPhone (iOS 26.2) n'a pas de bouton « Close » / « Fermer », et le
  tap visait le coin bas gauche du voile (`PopoverDismissRegion`), sous la feuille. Défaut du test, pas du code : le
  geste vise désormais le voile au-dessus du bord haut de la feuille, puis, si elle est encore là, la glisse vers le
  bas ; l'assertion de fermeture et les suivantes sont inchangées.

## T12 — revenus en lecture (branche `lot3/l3-t12-v2`, 09/11/2026 ; B9, jamais mergée sans go)

- **Livré.** Onglet Revenus natif (`Jolene/Screens/Revenus/RevenusScreen.swift`), à la place du placeholder du lot 0,
  port de l'aperçu réellement monté par `/soignant/mes-gains` (`MesGainsApercuContent`, onglet par défaut de
  `MesGains.tsx`) restreint à D4 :
  - totaux serveur `fn_mes_revenus_connect` (« Ce mois », « Total réglé », « Autres paiements en attente » et leur note,
    `PageStripeConnect.tsx` l.392-417), lus comme le web seulement pour `LIBERAL`, `MIXTE` ou `statut_liberal = ACTIF`
    (l.104), trois nombres finis exigés ;
  - bloc « Paiement rapide » `fn_mes_paiements_escrow` (sept états, groupes « À venir », « Récemment versé » (trois au
    plus), « Annulés », section absente sans ligne, litige → détail natif de la mission empilé sur l'onglet) ;
  - missions TERMINEE paginées par 50 avec **exactement** les colonnes de `MesGains.tsx` l.95 (D5, test-garde contre la
    source web), montant de `montantFinanceAfficheMission` (golden T2, correction Rist inactive : témoin démo 280 €),
    régime de la mission (`type_contrat_applique ?? type_contrat_recherche`, jamais `soignants.type_exercice`), état
    de la dernière déclaration (`indexerDernierPaiementParMission` + `classerPaiementSalaire`, golden T2), noms
    d'établissement par `fn_etablissements_safe` seul ; notes « net estimé » verbatim ;
  - renvois web « Factures » et « Paie » (D4), présences d'une mission (`/soignant/presences/mission/:id`, lot 2) ;
    audit `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`) une fois par ouverture ; état d'erreur et reprise de la page
    demandée en dernier ; « Vérifier ma session » ; pile `cheminRevenus` vidée par un lien ou un tap (revue B8 de T3b,
    m5).
  - Cœur : `Revenus/RevenusLecture.swift` (décodeurs partagés démo/Supabase, `ExerciceRevenus`, `PaiementSoignantLu`,
    `RevenusAssemblage`), `Revenus/RevenusPresentation.swift` (textes sourcés, sept états, lignes), `Revenus/RevenusModel.swift`
    (trois sections indépendantes, epoch, pagination, audit) ; démo `Demo/DemoRevenusGateway.swift` (fixtures
    `demo-revenus.json`, `demo-escrow.json`, `demo-missions-terminees.json`, variante `JOLENE_FORCE_REVENUS_ECHEC=1`) ;
    Supabase `Revenus/SupabaseRevenusGateway.swift`. `RevenusPort.totaux` rend désormais `TotauxRevenus?` (nil =
    section sans objet), `MissionTerminee` porte durée, taux, service, statut, nom d'établissement et dernière déclaration.
  - RPC passées en `consommee` (lot 3, T12) : `fn_mes_revenus_connect`, `fn_mes_paiements_escrow` (`check-rpc-contracts.mjs`,
    `rpc-contracts.json`, fiches de `CONTRATS_RPC_SOIGNANT.md`, garde `check-rpc-contracts-lot3.node.mjs`). Définitions
    live relues en lecture seule le 09/11/2026 (`pg_get_functiondef`) : identiques au dump ; GRANT EXECUTE `authenticated`,
    RLS `pol_paie_soig_select` et `pol_pres_select`, droits de colonne `authenticated` sur `missions`,
    `paiements_soignant` et `soignants` vérifiés. Aucun constat serveur.
- **Routes et coordinateur (consigne de T3a/T3b).** `.revenus(section: .apercu)` était déjà à `true` (placeholder) ; T12
  remplace l'écran, la ligne de `ecranNatifLivre` ne change pas (libellé de `DestinationLienTests` mis à jour). Les
  sections `factures`, `bulletins`, `avances` restent des renvois web (D4) et `paiements` reste à T13 : aucune autre
  route n'est livrée par T12, donc aucune nouvelle cible (`CibleNotification.revenus` présentable pour `.apercu`
  seulement, inchangé).
- **Écart au blueprint (§3 T12) : tap `FACTURE_EMISE`.** Le blueprint attend `revenus-screen` ; or `FACTURE_EMISE` mène à
  `/soignant/mes-gains?tab=factures` (`pushNative.ts` l.291-293), section en renvoi web assumé (D4, déjà prouvé par
  `PushTapIntentTests` et `DestinationLienTests`). Ouvrir l'onglet natif à la place de la section réduirait en silence
  la section à l'onglet (`CibleNotification`, « jamais réduite en silence »). Le cas reporté de T5 est prouvé tel que
  le produit le fait : `DemoRevenusTests.testTapPushFactureEmiseOuvreLesFacturesSurLeWeb` (renvoi web de la page
  canonique des factures).
- **Écarts au web (non juridiques, consignés).**
  1. Pas de filtre de période (« Ce mois » par défaut sur le web) : la liste native équivaut à « Tous les mois » — le
     filtre exige les créneaux et `construireExportPaiePeriode` (non portés) ; KPI d'estimation, pipeline des honoraires
     (dont `repartirPaiementConfirme`, mineur 3 de la revue de T2), honoraires facturés, graphique, rappels fiscaux,
     CSV, attestation, recherche et « Déclarations de salaire par mission » non portés (D4 : aucun KPI calculé côté
     client ; l'état par mission couvre le suivi des déclarations).
  2. État d'une mission libérale : le web le déduit des factures d'honoraires (`resumerFacturesMission`, lot 4) ; le
     natif n'en déduit rien et affiche « Paiement suivi dans Factures » (texte nouveau), plutôt qu'un état de paiement
     qui pourrait contredire les factures ; « Facturé sur la mission : … TTC » non porté pour la même raison.
  3. « Voir le détail de l'estimation salariale » (`ModalCotisations`, l.738-744 ; note de la revue de T1b) non porté :
     le montant net estimé reste affiché, sans le détail des cotisations (lot 4).
  4. « Avance de trésorerie » absente : le web ne l'affiche que si `affacturage_actif` (`fn_param_bool`, défaut `false`,
     affacturage non ouvert en production) ; lire ce drapeau consommerait `fn_param_bool` (lot 1, L1-T9 absent). Le lien
     `?tab=avances` reste un renvoi web. Le sous-titre suit la variante sans avance.
  5. « Factures » et « Paie » sont toujours proposés : la visibilité des onglets du web dépend de pièces que le natif ne
     lit pas (`fn_mes_factures_honoraires`, `fn_mes_bulletins_paie`, copies) ; la page web décide (elle retombe sur
     l'aperçu si l'onglet est masqué pour le profil).
  6. Le jour `jj/mm` du paiement rapide est à l'heure de Paris (le web : heure locale de l'appareil, identique en France) ;
     les textes du web tronqués (`truncate`) passent à la ligne en natif ; les notes de bas de page ne sont affichées
     qu'avec au moins une mission.
  7. Drapeau `ios_natif_revenus_actif` toujours non consommé (aucun écran ne lit encore `EcranNatif` : point de fusion
     de `origin/lot1/t9` inchangé).
  8. Carte des gains de l'Accueil (écart (5) de `PARITE_SOIGNANT.md`) toujours non cliquable : `AccueilScreen` n'est pas
     dans le périmètre de T12 ; à brancher sur `.revenus` par la tranche qui reprend l'Accueil.
- **Mineurs des revues antérieures adressés aux consommateurs.** T1b n°2 (`AmountRow`, disposition `ViewThatFits`) et
  n°3 (lecture XCUITest) : non modifiés (JoleneDesign hors périmètre) ; les XCUITest lisent le libellé vocalisé de
  `AmountRow` (`revenus-mission-montant-<id>`) et l'état par `StatusPill` (`revenus-mission-etat-<id>`), identifiants
  distincts. T2 n°3 : sans objet (aucun montant restant calculé).
- **Textes (HARD STOP n°4, délégué).** Repris verbatim avec leur source (`// source: fichier:ligne`, garde
  `RevenusPresentationTests.testChaqueTexteRepriseDuWebEstVerbatimASaLigne`) : libellés et aides des sept états du
  paiement rapide (tutoiement compris : « le montant de ta confirmation, mis de côté », « l'établissement valide tes
  heures (automatique sous 72 h) », « ton virement est en route », « contacte le support si besoin »), notes « net
  estimé » (`NoteNetEstime.tsx`, l.664-666), libellés de montant, totaux et leur note. La garde
  `check-textes-juridiques-ios` (L2-TL) n'est pas sur la base du lot 3 : épinglage par les tests Swift, comme T5 et T11.
  Aucune décision juridique n'a été nécessaire (aucun texte juridique nouveau ni reformulé ; aucune règle de mode
  d'exercice : la visibilité des totaux reprend la condition du web). Wording escrow : aucun « garanti », aucun
  « stationne » (test).
- **CI UI : cinquième éclat `lot3-revenus`** (`DemoRevenusTests`, domaine de T12, T13, T14a, T14b), « lot3-notifications »
  atteignant déjà 15 min sur iphone ; socle `-skip-testing:JoleneUITests/DemoRevenusTests`, résumé à cinq éclats, job
  porté à 175 min. Point de fusion avec le lot 2 : garder les éclats des deux lots, unir les `-skip-testing` du socle.
- **Migrations d'identifiants XCUITest (règle 8)** : `DemoConsultationTests.assertFiveTabs` (`placeholder-revenus` →
  `revenus-screen`, absence du placeholder affirmée) ; `DemoLiensLot3Tests.testSectionFacturesDeRevenusEnRenvoiWeb`
  (absence de `revenus-screen` pour la section factures).

## B9 — PR préparées et poussées, jamais mergées sans go explicite de Gabrielle

Pour chacune : branche poussée, tests verts, corps de PR prêt ; « CI verte + revue fraîche » ne remplace pas le go.

- **B3** — PR backend de la contestation de paiement (paiements ; `CREATE OR REPLACE` depuis la définition live,
  garde-fou 9.0 n°2 ; `test:escrow`, `test:regression` et `guards` requis, B7). **Mergée sur `main` (#1118)**,
  reprise dans `feat/ios-lot3` le 08/11/2026 : fiche `fn_contester_paiement_soignant` de `CONTRATS_RPC_SOIGNANT.md`
  et garde `check-rpc-contracts-lot3.node.mjs` mises au contrat d'après B3 ; T13 (B9) reste à livrer.
- **T7** — compte rapide et confirmation (consentement CGU transmis par `fn_demarrer_inscription p_cgu`) ; branche
  `lot3/l3-t7-v2` poussée (section T7 ci-dessus), préalable captcha `PORTE_LOT0.md` 3.1 / 3.2 non mesuré.
- **T8** — complétion et `register-soignant` (inscription, audit `RGPD_CONSENTEMENT_DONNE` côté serveur).
- **T12** — revenus en lecture (paiements, escrow) ; branche `lot3/l3-t12-v2` poussée (section T12 ci-dessus), lecture
  seule, aucune action de paiement.
- **T13** — paiements déclarés (confirmation ; contestation après B3).
- **T14a** — Stripe Connect.
- **T14b** — IBAN (données bancaires).
- **T16** — dispatch STAGING (secrets STAGING, suppression des comptes jetables, bascule transactionnelle de la
  cohorte D5-R).
- **Signalements sans correction au lot 3** (chacun B9 si une PR est ouverte) : RLS `pol_paie_soig_update`, qui
  permet au soignant un UPDATE direct de `paiements_soignant` (borné par `trg_protect_paiement_soignant` mais
  contournant les effets de la RPC — le natif n'écrit que par RPC) ; faux succès IBAN du web
  (`SectionPaiements.tsx` l.259-262, D20) ; export RGPD qui inclut les notes reçues non publiées (voir « En attente
  de Gabrielle »).

## HARD STOP n°4 — textes affichés

- Le natif n'affiche que des textes **verbatim** du web ou du serveur, chacun relié à sa source (fichier:ligne) et
  gardé par un test ; aucun texte juridique nouveau ni reformulé, aucun changement de délai ou de règle juridique
  côté serveur.
- Restent verbatim web tant que Gabrielle ne les a pas validés : CGU et confidentialité de l'inscription,
  avertissement d'exclusivité, libellés de mode d'exercice, libellés escrow et note « net estimé », textes Stripe,
  textes RGPD de l'export, textes de la contestation de paiement.
- Non portés, renvoi web libellé : type d'exercice et attestation de cumul d'activité (art. L1222-5,
  `ProfilSoignant.tsx` l.252-256, l.274-278, correction 8).
- Textes **sans équivalent web** (non juridiques, à relire par Gabrielle) : messages natifs des sept `error_code`
  IBAN qui arrivent sans `error` (T14b) ; message du verrou de contestation (T13) ; libellé d'action
  « Ouvrir les réglages » de la carte « Autorisation du téléphone » (T4 : le web n'ouvre pas les réglages système ;
  nommé au §1.1 du blueprint, constante `EtatNotificationsAppareil.ouvrirReglages` épinglée par
  `EtatNotificationsAppareilTests`) ; (T9) libellé du renvoi web du type d'exercice
  « Le type d'exercice se modifie sur jolene.app. » (encart `profil-exercice-web` sous le titre web « Type
  d'exercice » : le web affiche la section elle-même, que le natif ne porte pas, correction 8) et message de repli
  d'un enregistrement refusé sans message serveur « Votre profil n'a pas pu être enregistré. Réessayez. » (le web
  passe par `extraireMessageErreur`), constantes `ProfilEdition.Textes.typeExerciceWeb` et `.enregistrementEchec`
  épinglées par `ProfilVerbatimTests` ; (intégration du lot 3, T5 × T9) libellé « Voir sur jolene.app » du bouton
  `profil-exercice-web-action` (affiché seulement avec le présentateur `.safari` de L1-T10) : repris du renvoi web
  des notifications de l'Accueil au lot 1, que T5 remplace par le centre natif, il n'existe plus que dans l'édition
  du profil (constante `ProfilEdition.Textes.voirSurLeWeb`, épinglée par `ProfilVerbatimTests`).
- (T9, revue B8) Refus d'enregistrement du profil : textes web verbatim d'`extraireMessageErreur`
  (`src/lib/erreurs.ts` l.510, l.511, l.514) pour 23505 et 23514, message serveur verbatim pour `{error}` et P0001
  (`dec_verifier_age_minimum`, `public.sql` l.3893), épinglés par `ProfilVerbatimTests` ; libellés natifs du lot 1
  « Session à vérifier » / « Vérifier ma session » réutilisés tels quels. Aucun texte nouveau, aucun texte juridique.
- Textes d'accessibilité **sans équivalent web** (vocalisés seulement, jamais affichés ; non juridiques, à relire
  par Gabrielle, L3-T1b) : « environ » (lecture de « ~ » devant un montant et dans une note, `AmountRow`) ;
  « Montant indisponible » (lecture du tiret « — », `AmountRow`) ; « critère rempli » / « critère non rempli »
  (`PasswordCriteriaList`, le web n'a que la coche) ; « Ouvre le centre de notifications » (indication de « Voir »
  sur le compteur de l'Accueil, L3-T5, `CentreNotificationsTextes.indicationOuvrirCentre`). Le texte affiché reste
  verbatim web.
- **T12 — textes adaptés ou sans équivalent web** (non juridiques, à relire par Gabrielle ; constantes
  `RevenusTextes`, épinglées par `RevenusPresentationTests.testTextesAdaptesOuSansEquivalentWeb`), un texte par ligne :
  - sous-titre, adapté au vouvoiement de `MesGains.tsx` l.918 : « Vos gains, factures et documents de paie au même endroit »
  - état vide, adapté de l.804 : « Vos gains apparaîtront ici après votre première mission terminée. »
  - totaux indisponibles, adapté de `PageStripeConnect.tsx` l.389 : « Vos revenus sont temporairement indisponibles. »
  - en-tête de la liste (sans équivalent) : « Missions terminées »
  - état d'une mission libérale (sans équivalent) : « Paiement suivi dans Factures »

  Restent verbatim web, tutoiement compris (HARD STOP, décision du 09/11/2026) : libellés et aides des sept états du
  paiement rapide et notes « net estimé » (section T12 ci-dessus).
- **T11 — textes sans équivalent web** (non juridiques, à relire par Gabrielle), un texte par ligne :
  - refus verrouillé de la réauthentification (`MotDePasse.Textes.reauthentificationRequise`) :
    « Ce changement exige une nouvelle vérification de votre identité. Utilisez « Mot de passe oublié ? » pour choisir un nouveau mot de passe. »
  - issue inconnue du changement (`MotDePasse.Textes.confirmationIndisponible`) :
    « Le changement de votre mot de passe n'a pas pu être confirmé. Vérifiez votre connexion puis réessayez. »
  - libellés du thème (D16 ; le web n'a que « Passer en thème clair / sombre ») : « Thème », « Système », « Clair », « Sombre ».

  Constantes épinglées par `CompteVerbatimTests`. Textes RGPD de l'export (« Mes données (RGPD) », « Télécharge
  l'intégralité de tes données personnelles dans le format de ton choix. ») : verbatim web en tutoiement, à valider
  avant tout vouvoiement (§6.7).
- Seuls les textes non juridiques passent du tutoiement web au vouvoiement (décision 9 du lot 1).
- (T3b) Texte **sans équivalent web**, non juridique, déjà décidé (décision 7 du lot 1, `LOT1_PLAN.md` l.403) et repris
  mot pour mot : « Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application. » (refus d'un lien de
  réinitialisation `?code=`, `DeepLinkIntent.Textes.reinitialisationRefusee`, épinglé par `DeepLinkIntentTests`) ;
  bouton « Fermer » repris de `FiltresSheet.swift` l.64.

## En attente de Gabrielle (§6 du blueprint)

- **§6.1 APNs** : constater que `APNS_KEY_P8`, `APNS_KEY_ID` et `APNS_TEAM_ID` existent sur STAGING (la sonde ne vise
  que la production) ; créer une clé APNs sous `GDU5AA28M9`, tourner les trois secrets (STAGING et production) ;
  `APNS_ENVIRONMENT = sandbox` sur STAGING, `production` en production ; relancer `apns-probe.yml` en mode témoin.
- **§6.2 iPhone physique** : appareil enregistré, profil de développement `app.jolene` (Push + Associated Domains),
  build Debug « Jolene-Staging » installé par Xcode, iOS ≥ 17.4, clé publishable STAGING dans un xcconfig local non
  versionné, signature manuelle ; recette `RECETTE_DEVICE_LOT3.md`.
- **§6.3 Cohorte STAGING non-test** : go pour la bascule transactionnelle de la fixture D5-R (jamais de passage
  durable de `inscriptions_publiques_actives` à 1) ; confirmer que `STRIPE_SECRET_KEY` STAGING est une clé de test.
- **§6.4 Dashboard Auth (STAGING puis production, B9 auth)** : modèle « Confirm signup » au format
  `{{ .SiteURL }}/inscription/confirmer?token_hash={{ .TokenHash }}&type=signup` ;
  `https://jolene.app/inscription/confirmer` dans Redirect URLs ; `Site URL` STAGING égal à `https://jolene.app` (ou
  hôte écrit en dur dans le modèle) ; mesures `PORTE_LOT0.md` 3.1 (STAGING) et 3.2 (production, manuelle) ; réglage
  « secure password change » ; validation de la reformulation du critère d'inscription (« PKCE échangé » → « lien
  `token_hash` vérifié dans l'app »).
- **§6.5 Sentry** : créer le projet `jolene-ios` (org `jolene-z6`), fournir le DSN, lire l'événement de crash de test ;
  jeton dSYM local si la symbolication est voulue.
- **§6.6 Go B9** : B3, T7, T8, T12, T13, T14a, T14b, dispatch de T16, et les signalements de la section B9.
- **§6.7 Textes (HARD STOP)** : validation des textes listés dans la section HARD STOP, relecture des sept messages
  IBAN et du message de verrou de contestation.
- **§6.8 Stripe TEST sur appareil** : parcourir l'onboarding hébergé avec les valeurs de test publiées par Stripe
  (saisie par Gabrielle), constater le retour et le statut relu.
- **§6.9 Boîte mail** : une adresse contrôlée par Gabrielle pour l'inscription STAGING depuis Mail (Universal Link
  réel).
- **§6.10 TestFlight externe** : groupe de soignants pilotes, informations de test, Beta App Review ; décision
  explicite, le build parlant à la production.
- **§6.11 Captcha** : mesurer `PORTE_LOT0.md` 3.1 et 3.2 avant d'ouvrir T7 ; en cas de refus captcha, D25 s'applique.
  (T7, 08/11/2026) Toujours « non mesurées » : T7 est livrée en natif sous réserve de ces mesures, à faire avant son
  merge ; un refus captcha mesuré impose D25 (renvoi web de « Créer un compte »).
- **Signalé par T3b (hors §6)** : le reset natif du mot de passe (reste de L1-T10 : `SupabaseRecoveryGateway`,
  `ResetPasswordScreen`, quarantaine de la session de recovery, « Mot de passe oublié ? ») n'a de tranche ni au lot 1
  (mergé sans T10) ni au lot 3 ; en attendant, le lien `token_hash` ouvre la page web et `?code=` est refusé
  (option B). À planifier (préalable inchangé : modèle d'e-mail « Reset Password » au format `token_hash`, §6.6 du
  lot 1).
- **Signalé par la T0 (hors §6)** : `fn_rgpd_exporter_donnees_soignant` (`public.sql` l.55300, dump du 01/11/2026) lit
  `notations_missions` avec `masque = false` **sans** `publie_le IS NOT NULL` : l'export RGPD contient les notes
  reçues non publiées (double-aveugle D8), contrairement à la vue canonique `evaluations_publiees` et au principe
  « Publication différée » de `CLAUDE.md`. À confirmer sur la définition live, puis à arbitrer (droit d'accès RGPD
  contre double-aveugle) avant toute PR backend ; aucune correction au lot 3, le natif ne fait que transmettre le
  fichier par la feuille de partage. **Confirmé sur la définition live** par T11 (lecture seule
  `pg_get_functiondef`, 08/11/2026) : l'écran natif n'affiche rien du contenu, le fichier transmis à la feuille de
  partage contient ces notes, comme sur le web.

## Ce qui n'est pas une décision de ce mémo

- Aucun texte juridique, aucune règle de mode d'exercice, aucun délai serveur n'est décidé ici (HARD STOP n°4).
- Les réglages hors dépôt (Dashboard Auth, secrets APNs et Stripe, projet Sentry, appareil) et les go B9 sont à
  Gabrielle ; ce mémo ne les présume pas acquis.
- Le plan `docs/PLAN_APP_NATIVE_SWIFT.md` et le blueprint versionné ne sont pas modifiés par ces décisions.

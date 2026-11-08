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
    `PreferencesTextes.sectionHub` et `PreferencesTextes.entreeHub`.
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

## B9 — PR préparées et poussées, jamais mergées sans go explicite de Gabrielle

Pour chacune : branche poussée, tests verts, corps de PR prêt ; « CI verte + revue fraîche » ne remplace pas le go.

- **B3** — PR backend de la contestation de paiement (paiements ; `CREATE OR REPLACE` depuis la définition live,
  garde-fou 9.0 n°2 ; `test:escrow`, `test:regression` et `guards` requis, B7).
- **T7** — compte rapide et confirmation (consentement CGU transmis par `fn_demarrer_inscription p_cgu`).
- **T8** — complétion et `register-soignant` (inscription, audit `RGPD_CONSENTEMENT_DONNE` côté serveur).
- **T12** — revenus en lecture (paiements, escrow).
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
  `EtatNotificationsAppareilTests`).
- Textes d'accessibilité **sans équivalent web** (vocalisés seulement, jamais affichés ; non juridiques, à relire
  par Gabrielle, L3-T1b) : « environ » (lecture de « ~ » devant un montant et dans une note, `AmountRow`) ;
  « Montant indisponible » (lecture du tiret « — », `AmountRow`) ; « critère rempli » / « critère non rempli »
  (`PasswordCriteriaList`, le web n'a que la coche) ; « Ouvre le centre de notifications » (indication de « Voir »
  sur le compteur de l'Accueil, L3-T5, `CentreNotificationsTextes.indicationOuvrirCentre`). Le texte affiché reste
  verbatim web.
- Seuls les textes non juridiques passent du tutoiement web au vouvoiement (décision 9 du lot 1).

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
- **Signalé par la T0 (hors §6)** : `fn_rgpd_exporter_donnees_soignant` (`public.sql` l.55300, dump du 01/11/2026) lit
  `notations_missions` avec `masque = false` **sans** `publie_le IS NOT NULL` : l'export RGPD contient les notes
  reçues non publiées (double-aveugle D8), contrairement à la vue canonique `evaluations_publiees` et au principe
  « Publication différée » de `CLAUDE.md`. À confirmer sur la définition live, puis à arbitrer (droit d'accès RGPD
  contre double-aveugle) avant toute PR backend ; aucune correction au lot 3, le natif ne fait que transmettre le
  fichier par la feuille de partage.

## Ce qui n'est pas une décision de ce mémo

- Aucun texte juridique, aucune règle de mode d'exercice, aucun délai serveur n'est décidé ici (HARD STOP n°4).
- Les réglages hors dépôt (Dashboard Auth, secrets APNs et Stripe, projet Sentry, appareil) et les go B9 sont à
  Gabrielle ; ce mémo ne les présume pas acquis.
- Le plan `docs/PLAN_APP_NATIVE_SWIFT.md` et le blueprint versionné ne sont pas modifiés par ces décisions.

# Décisions du lot 3 — application iOS Swift native

> Tranchées le 2 novembre 2026 par Claude Code, sur mandat de Gabrielle du même jour (« finis et prends les
> décisions seul », « je suis tous tes conseils ») et selon le mémo « Décisions des lots 2 à 5 » de la session
> principale : **toutes les recommandations fermes du §7 du blueprint `docs/mobile-swift/LOT3_PLAN.md` sont
> adoptées telles quelles**. Ce mémo fait foi pour le lot 3. Le plan `docs/PLAN_APP_NATIVE_SWIFT.md` n'est pas réécrit :
> ses critères de sortie amendés sont consignés ci-dessous. Les décisions juridiques, les réglages hors dépôt et
> les go B9 restent à Gabrielle (« En attente de Gabrielle »). **Mise à jour du 9 novembre 2026** : Gabrielle a
> délégué toutes les décisions, juridiques comprises, le 8 novembre 2026 ; les points juridiques et les textes du lot 3
> qui ne dépendent d'aucune tranche hors vague sont tranchés sous « Décisions déléguées du 8 novembre 2026 » (tranche
> L3-TJ) ; restent en attente les go B9 au merge et ce qui exige la présence ou les comptes de Gabrielle.

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
  juridique. Texte sans équivalent web (non juridique), tranché par délégation (L3-TJ, TJ5) : l'indication vocale
  « Ouvre le centre de notifications » (`accueil-notifications-action`, constante
  `CentreNotificationsTextes.indicationOuvrirCentre` épinglée par `CentreNotificationsTests`) ; le libellé DEBUG
  `push-tap-cible` n'est jamais affiché.

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
  `check-textes-juridiques-ios.mjs` de L2-TL, absent de la base du lot 3). **Tranchés par délégation** (L3-TJ,
  TJ1) : la phrase de consentement et ses deux liens, le consentement transmis par `p_cgu`, et le choix du message
  générique (au lieu du texte captcha du web, « Rafraîchissez la page… ») pour un refus captcha.
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
  deux surfaces. Ce point est serveur et n'est pas corrigé ici ; tranché par délégation (L3-TJ, TJ4 : notes
  différées jusqu'à leur publication, PR backend B9 à préparer hors lot).
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
    qu'après une déconnexion. Dépendance à L1-T10 ; le texte (`MotDePasse.Textes.reauthentificationRequise`) est
    tranché par délégation (L3-TJ, TJ2, avec la condition de ce libellé sur la connexion native avant TestFlight
    externe). Le cas est presque inaccessible (session de vérification neuve).
- **Écarts au blueprint v2 §3 T11, à acter par l'intégrateur (revue B8, m9).**
  - Pas d'entrée `.notifications` (centre) au hub : le hub web n'en a pas, le centre s'ouvre depuis l'Accueil (T5).
  - Pas d'entrées Paiements / Stripe ni Coordonnées bancaires, même en renvoi Safari : reprises T14a et T14b.
  - « Aide & légal » masqué tant que le présentateur `.safari` de L1-T10 manque : reprise T10.
  - Bloc du lot 0 en tête du hub (ordre ci-dessus).
- **Point de fusion T3b.** `/soignant/profil?tab=confidentialite` (RGPD et suppression sur le web) ouvre toujours
  l'édition native. Le hub porte désormais l'export et la suppression : recommandation pour T3b, router ce `?tab=`
  vers `.monCompte` (fichiers de T3, non modifiés ici).
- **HARD STOP n°4.** Textes repris du web à leur ligne (`CompteVerbatimTests`), textes RGPD de l'export en tutoiement
  verbatim (depuis L3-TJ, TJ2 : titre seul, la description web inexacte n'est plus portée), aucun texte juridique
  nouveau. Refus serveur de l'export localisés dans le corps de
  `fn_rgpd_exporter_rate_limited` (en-tête de la fonction dans le dump), ligne du dump seulement indicative : un
  `schema-snapshot` ne fait plus rougir JoleneCore (revue B8, m5). Textes RGPD et textes natifs sans équivalent web :
  tranchés par délégation (L3-TJ, TJ2). **B9** : non (D18).

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
    deux liens ouvraient la page réelle : repris par L3-TJ (TJ3), la feuille locale montre désormais le double démo du
    coordinateur (`PageWebLocale`), XCUITest `DemoInscriptionTests.testLienCGUDuConsentementOuvreLeDoubleDemoSansReseau`
    et, depuis la revue fraîche B8 de L3-TJ, `…DepuisLAiguillageSessionOuverte…` (formulaire en feuille de l'aiguillage).
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
  l'éclat socle. (L3-TJ, revue fraîche B8, mineur 4) Cinquième éclat « lot3-inscription » (`DemoInscriptionTests`,
  sorti de « lot3-compte », 19,1 min sur ipad-landscape au run 42549855710 avant les deux XCUITest d'inscription de
  L3-TJ) ; job à 170 min ; structure gardée par `check-rpc-contracts-lot3.node.mjs` (chaque classe dans un seul
  éclat, sautée par le socle, attendue par le résumé, xcresult conservé).
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

## T8 — complétion du profil et `register-soignant` (branche `lot3/l3-t8-v2`, 09/11/2026)

- **Livré.** Cœur (`JoleneCore/Inscription/`) : `CompletionProfil.swift` (`CompletionTextes` verbatim, `CompletionRules` :
  garde du formulaire web l.214-233 et l.354-357, téléphone l.228, RPPS par profession, borne du sélecteur de date
  l.554, phrase du type unique l.68, modes après le référentiel l.191-199, brouillon et corps de `register-soignant` en
  liste blanche) et `CompletionProfilModel.swift` (référentiel, brouillon, finalisation relue). Monde démo :
  `DemoInscriptionGateway` (brouillon fusionné, référentiel `demo-types-exercice.json` exporté depuis le seed
  `20260714084802_synchroniser_regles_profil_exercice.sql`, `register-soignant` simulée avec ses contrôles et messages
  verbatim, bascule vers `demo-soignant`), refus `UNDERAGE`, `RPPS_ALREADY_REGISTERED`, `ACCOUNT_FINALIZATION_PENDING`,
  `TYPES_EXERCICE_INDISPONIBLE` (`-JOLENE_DEMO_INSCRIPTION_REFUS`), variante DEBUG `JOLENE_DEMO_BROUILLON=complet`
  (brouillon serveur repris, sans piloter le sélecteur de date). Gateway `SupabaseInscriptionGateway` :
  `fn_enregistrer_parcours_inscription` (22023, P0002 restitués), `fn_types_exercice_autorises` (tableau de chaînes, sinon
  indisponible), `register-soignant` par `EdgeResponse` puis `refreshSession()`. Écran `CompletionProfilScreen` monté par
  `OnboardingRootView` à la place de l'écran bloquant provisoire (`onboarding-completion` → `completion-screen`,
  règle 8) ; `RootView` affiche à la connexion le message d'une déconnexion locale.
- **Consignes de l'intégration appliquées.** `InscriptionPort.completionLivree` vaut `true` dans les deux mondes (défaut du
  protocole ; le stub non câblé reste à `false`) : « Réessayer la vérification » de l'édition du profil devient effectif.
  Après `register-soignant` 200 puis `refreshSession()`, le rôle est relu (`fn_get_my_role`) puis l'identité est rouverte
  par `SessionStore.ouvrirIdentiteInscription()` (navigateur intégré vidé, puis `start()` ; `.ready` relu = preuve),
  consigne de T3b « même appel avant d'ouvrir l'identité ». `DestinationLien.ecranNatifLivre(.inscription(.completer))`
  vaut `true` ; la complétion est consommée hors de l'espace comme la reprise (`BoiteLiensInscription`,
  `AiguillageLiens.Action.inscription`) ; exclusion nommée `inscriptionCompleter` ajoutée à
  `CentreNotificationsTests.sansCibleDansLEspace` (même justification que T7 : une identité qui a un espace prêt n'a pas
  d'inscription à compléter ; aucune notification du dump ne vise `/inscription/*`). `fn_enregistrer_parcours_inscription`
  et `fn_types_exercice_autorises` passent en `consommee` (définitions live relues en lecture seule le 09/11/2026,
  identiques au dump ; edge `register-soignant` déployée, version 876, identique au dépôt).
- **Liste de contrôle T8 de T9.** 1 : `typesExercice` câblé dans les deux mondes ; 3 : assertion « référentiel non câblé »
  de `DemoProfilTests` remplacée par les modes autorisés (`testTypeDExerciceEnRenvoiEtModesAutorisesParLeReferentiel`) ;
  4 : inchangé (`feat/ios-lot3` n'atteint pas `main` avant les go de T7/T8). **Écart au point 2** : le cas
  `ProfilEditionModel.Modes.nonCable` est conservé, car le stub `UnwiredInscriptionPort` existe toujours (doubles de test,
  monde incomplet) et ne doit jamais offrir un « Réessayer » sans effet ; il n'est plus atteint dans les deux mondes.
- **Écarts assumés (non juridiques).**
  - Profession **figée** du parcours (le web la laisse modifiable dans la complétion) : blueprint §3 T8, principe « État
    dérivé » ; une profession hors catalogue (contrat rompu : `fn_demarrer_inscription` l'exige) bloque l'écran avec le
    texte web « Votre espace est momentanément indisponible. Réessayez. ».
  - Pas d'aperçu du marché (`ApercuMarche`), pas de vérification RPPS en temps réel (D11 : `register-soignant` seul, refus
    verbatim), pas de bandeau Pro Santé Connect (D8), pas de champ rayon (correction 21 ; le rayon d'un brouillon web est
    retransmis, sinon le serveur applique ses 30 km).
  - Le message « Vérification des modes d'exercice autorisés… » d'`ExerciceTypeSection` (l.88-90) n'est pas répété : le
    même message de `ChoixModesExercice` (l.41) est affiché juste au-dessus.
  - « Enregistrer et continuer plus tard » relit le parcours (le web navigue vers `/inscription/reprendre`, même effet).
  - `?ref=` d'un lien `/inscription/completer` n'est pas capté (le web le range en `sessionStorage` pour l'assistant de
    profil) : parrainage non porté au lot 3.
  - Corps de `register-soignant` sans `navigateur` ni `attribution` (aucune chaîne d'agent inventée) : `navigateur_acteur`
    des audits `INSCRIPTION` et `RGPD_CONSENTEMENT_DONNE` vaut `null` ; la preuve du consentement reste
    `parcours_inscription.consentement_cgu_le` (l.376-387).
  - Échec de `refreshSession()` après un 200 : déconnexion locale et message web « Votre profil est enregistré.
    Reconnectez-vous pour ouvrir votre espace. » (`inscriptionProgressive.ts` l.236 ; le web reste sur la page) ; issue
    inconnue (délai, réseau, réponse illisible) : relecture du rôle, l'espace s'ouvre si le profil existe, sinon texte
    réseau du web ou « Votre saisie est conservée. Réessayez. » (l.224), jamais de renvoi.
  - Délai de la finalisation : deux fois `resolutionTimeout` (brouillon, edge qui peut interroger l'Annuaire Santé jusqu'à
    10 s, `refreshSession`) ; un dépassement n'est jamais un échec supposé.
- **CI.** Nouvelle classe `DemoCompletionInscriptionTests` (6 XCUITest × 3 formats) dans un **nouvel éclat**
  « lot3-inscription » : « lot3-compte » était à 19,1 min sur ipad-landscape au run 42549855710 (seuil de 20 min) ; job
  porté à 170 min (cinq éclats de 30 min et le build) ; le résumé exige les cinq éclats verts. Compilé, non lancé
  localement.
- **HARD STOP n°4.** Aucun texte nouveau : textes web verbatim d'`InscriptionSoignant.tsx` (mode parcours),
  `DeclarationEtudiant.tsx` l.105, `inscriptionProgressive.ts` l.177, l.224, l.236, `ChoixModesExercice.tsx`, messages
  serveur verbatim (`register-soignant`, `fn_enregistrer_parcours_inscription`), épinglés par `CompletionVerbatimTests`
  (46 annotations) et `InscriptionVerbatimTests` (52). Décisions juridiques prises par délégation : section suivante.
- **B9.** Inscription (consentement relayé par l'audit `RGPD_CONSENTEMENT_DONNE` côté serveur) : branche poussée, jamais
  mergée sans le go de Gabrielle (D18).

### T8 — corrections de la revue fraîche B8 (09/11/2026)

Tests d'abord (commit de tests rouge à la compilation : API absente), puis correction. Tests changés parce qu'ils
épinglaient le défaut relevé, jamais affaiblis : `SupabaseInscriptionGatewayTests` (409 `ACCOUNT_ALREADY_REGISTERED`,
503, 500 et 502 illisible tenus pour des refus certains ; corps 2xx `[]` refus certain), `OnboardingResolutionTests` et
`CompletionProfilModelTests` (réponse « salarié(e) » ni restaurée ni enregistrée), `InscriptionVerbatimTests`
(53 annotations : + le message serveur du 409 rejoué en démo).

- **B1 — brouillon étudiant (option a de la revue : verrou, aucun texte nouveau).** `estEtudiant` (et la réponse
  « salarié(e) ») sont lus dans `parcours_inscription.donnees` en booléens seuls, comme `restaurerFormulaire`
  (`inscriptionProgressive.ts` l.126-149). Un brouillon `estEtudiant: true` n'est **jamais** finalisé en natif :
  `CompletionProfilModel.parcoursEtudiant` (parcours lu à l'ouverture) masque le formulaire et « Enregistrer mon
  profil », et l'écran ne propose que le bouton existant « 🎓 Je suis étudiant(e) en santé » (complétion web,
  `/inscription/completer`) ; sans présentateur `.safari`, le texte web « Votre espace est momentanément indisponible.
  Réessayez. ». Défense en profondeur : `finaliser` des deux gateways relit le brouillon fusionné par le serveur et rend
  `ResultatFinalisation.parcoursEtudiant` **sans appeler** `register-soignant` (déclaration faite sur le web pendant que
  l'écran natif restait ouvert) ; le modèle bascule alors l'écran. Le natif n'écrit jamais `estEtudiant` ni
  `scolarite*` (le serveur les conserve : `donnees || p_donnees`). Motif du choix (a) plutôt que (b) : D11 et T8-J5
  renvoient le parcours étudiant au web ; transmettre `est_etudiant: true` sans afficher ni permettre de modifier la
  déclaration (formation, année, conditions de `DeclarationEtudiant.tsx`) ferait du natif une déclaration silencieuse ;
  le verrou rend le chemin cassé impossible (`CLAUDE.md`, « un gap connu reste verrouillé »). Conséquence évitée :
  `register-soignant` écrivait `est_etudiant = false` (index.ts l.309) — l'établissement ne voyait plus le cadre
  étudiant ni la confirmation `CADRE_ETUDIANT_AS_CONFIRME` (`ListeCandidatures.tsx` l.287), et
  `dec_verifier_profession_etudiant` (`public.sql` l.4518) ne s'appliquait plus. Tests : `OnboardingResolutionTests`,
  `CompletionProfilRulesTests` (règle, clés du brouillon et du corps), `CompletionProfilModelTests` (verrou initial et
  bascule serveur), `SupabaseInscriptionGatewayTests` (aucune requête vers l'edge, `"true"` et `false` ne sont pas des
  déclarations), `DemoInscriptionGatewayTests` et XCUITest `testBrouillonEtudiantNeProposeQueLaCompletionWebPuisRelitAuRetour`
  (variante démo `JOLENE_DEMO_BROUILLON=etudiant`).
- **M1 — issues inconnues relues.** `CompletionRules.issueIndeterminee(statut:code:)` : tout statut ≥ 500 (passerelle,
  délai de l'edge, `catch` final l.404-407 qui peut suivre l'INSERT), une réponse 2xx illisible, et les 409
  `ACCOUNT_ALREADY_REGISTERED`, `ACCOUNT_REGISTRATION_IN_PROGRESS` (index.ts l.205-212) et `USER_ALREADY_REGISTERED`
  (contrainte de `soignants` hors RPPS, clé primaire comprise, l.329-332) rendent `ResultatFinalisation.indeterminee`
  (le 503 `ACCOUNT_FINALIZATION_PENDING` garde la déconnexion locale). Le modèle relit alors le rôle
  (`fn_get_my_role` ne rend `SOIGNANT` qu'avec une ligne `soignants`, `public.sql` l.38295-38301) : profil relu →
  `ouvrirIdentiteInscription`, sinon message serveur verbatim en repli (« Votre saisie est conservée. Réessayez. » pour
  un corps illisible). Extension assumée au-delà de « ≥ 500 sans code » : un 5xx codé (`INTERNAL_ERROR`, erreurs du
  runtime) n'exclut pas davantage un profil créé, et la relecture n'ouvre jamais un espace sans ligne `soignants`.
  **Retour du renvoi web étudiant** : `PresentationsRacine.fermetures` (compteur des renvois affichés puis fermés,
  injecté par `PointDEntreeLiens` dans l'environnement `fermeturesRenvoiWeb`) ; l'écran qui a ouvert la complétion web
  relit le rôle au retour (`relireApresRenvoiWeb`) — profil créé sur le web → espace ouvert ; sinon, pour un parcours
  étudiant, relecture du parcours (le brouillon a pu changer sur le web), aucun message. Tests : `CompletionProfilRulesTests`,
  `SupabaseInscriptionGatewayTests`, `CompletionProfilModelTests`, `PresentationsRacineTests`, `DemoInscriptionGatewayTests`
  et XCUITest `testCompteDejaFinaliseOuvreLEspaceApresRelectureDuRole` (refus démo `ACCOUNT_ALREADY_REGISTERED`).
- **m1** : Bearer de `register-soignant` pris de `client.auth.session` (rafraîchie si expirée, comme
  `SupabaseAccountGateway`), session absente → « Reconnectez-vous pour reprendre votre inscription. ». Comportement
  observable inchangé tant que le brouillon (PostgREST) précède l'edge : le test épingle le Bearer frais, il n'était pas
  rouge avant la correction.
- **m2** : une lecture du référentiel annulée (`.task` coupé) remet `modes` à `.inactif` si elle est la plus récente ;
  le `.task` suivant la relance (test rouge avant : l'écran restait sur « Vérification… »).
- **m3 — consigné, non porté (écart de parité non juridique).** Après la complétion, le web ouvre
  `/soignant/missions/<missionChoisie>` quand le brouillon en contient une (UUID, `InscriptionSoignant.tsx`
  l.369-370 ; posée par l'exploration avant inscription, `explorationInscription.ts` l.32), sinon
  `/soignant/recherche-missions` ; le natif ouvre l'espace par défaut (Accueil). Motif : le natif n'a pas
  d'exploration avant le profil complet (D9), `missionChoisie` ne vient donc que d'une exploration web ; la porter
  exige une entrée du coordinateur de liens depuis l'onboarding (intention mémorisée avant `.ready`), hors de cette
  correction. À reprendre avec l'exploration (lot 4) ; la mission reste accessible depuis l'espace.
- **m4** : la réponse « salarié(e) » est enregistrée dans le brouillon (`estSalarieEtablissement`, liste blanche
  serveur) et restaurée comme le web (`donneesFormulaire` l.152-167, `restaurerFormulaire` l.135-138), jamais
  transmise à `register-soignant` ; T8-J2 corrigée en conséquence.
- **m5** : profil créé (200) mais rôle relu sans espace → même issue que l'échec de `refreshSession` : message web
  « Votre profil est enregistré. Reconnectez-vous pour ouvrir votre espace. » annoncé à la connexion, puis déconnexion
  locale. Documentation de `Issue.espaceOuvert` corrigée : ce n'est pas la preuve de l'espace, l'interface suit l'état
  de session (`.ready` relu).
- **m6** : l'epoch n'est capturé que si l'identité active est celle du parcours (`SessionController.epoch(identite:)`,
  accesseur en lecture seule, aucun effet sur l'état ni sur l'epoch) ; sinon aucun envoi.
- **m7** : `DemoCompletionInscriptionTests` relit la sentinelle « 0 requête » du hub dès que l'espace est ouvert
  (complétion nominale et 409 démo) ; elle n'est exposée que par le hub Profil. Huit XCUITest × trois formats, compilés,
  jamais lancés localement : **le run CI vert de l'éclat « lot3-inscription » reste un préalable au merge**.
- **m8** : `CompletionRules.dateMaximale` calcule la borne dans le calendrier UTC du sélecteur (défaut et appel de
  l'écran) ; test du 28 février 2026 à 23:30 UTC (borne 28/02/2008, celle de Paris serait le 29).
- Aucun texte nouveau, aucun texte juridique : textes existants (bouton étudiant, `espaceIndisponible`) et message
  serveur verbatim du 409 (`register-soignant/index.ts` l.208, rejoué par la démo). Aucune RPC nouvelle, aucune
  écriture serveur ; B9 inchangé (go de Gabrielle).

## T10 — photo de profil et localisation (branche `lot3/l3-t10-v2`, 09/11/2026)

- **Livré.**
  - Photo : `JoleneCore/Profil/AvatarProfil.swift` (règles d'`AvatarUpload.tsx` l.33-61, l.116-170 : bucket
    `jolene-documents`, chemin `<uid>/avatar-<ms>.jpg`, 256 px sans agrandissement, qualité 0,8, 2 Mo, URL signée de
    5 ans ; `ConversionAvatar` : tout format lu par ImageIO, HEIC compris, réduit par
    `CGImageSourceCreateThumbnailAtIndex` sans décoder l'original en pleine taille, orientation EXIF appliquée, fond
    blanc sous la transparence, AUCUNE métadonnée recopiée — position GPS de la photo comprise), `EnvoiAvatar.swift`
    (enchaînement des deux mondes : reçu durable, dépôt, URL signée, `fn_modifier_mon_profil(p_avatar_url)` par le
    port du profil, relecture de `avatar_url`), `RecuAvatar.swift`, `AvatarProfilModel.swift` ; JoleneSupabase
    `Profil/SupabaseAvatarStorage.swift` (Storage, `upsert: false`, 4xx = refus certain, 5xx et réseau = issue
    inconnue) et `Keychain/KeychainRecusAvatar.swift` ; app `Composition/AvatarPicker.swift` (`PHPickerViewController`
    hors processus, sans autorisation photothèque ; `UIImagePickerController` pour l'appareil photo) et
    `Screens/Profil/AvatarProfilSection.swift`.
  - Localisation : `JoleneCore/Ports/LocalisationPort.swift` (port minimal provisoire, démo
    `DemoLocalisationProfil`), `Profil/GeocodageInverse.swift` et `Profil/ProfilLocalisation.swift` (port de
    `reverseGeocode`, `src/lib/geocodage.ts` l.16-34, et de `demanderGeolocalisation`, `SectionProfilPrincipal.tsx`
    l.625-643), `ProfilEditionModel.localiser()` ; JoleneSupabase `Geo/ApiAdresseGeocodage.swift` (GET
    `https://api-adresse.data.gouv.fr/reverse/?lon=&lat=`, en-tête `Accept` seul, session éphémère sans cookie, tout
    échec → nil) ; app `Composition/LocalisationProfilProvisoire.swift` (CoreLocation, `requestLocation`, 15 s) et
    `Screens/Profil/AdresseProfilSection.swift`. `ModificationProfil` envoie désormais `p_adresse_lat` /
    `p_adresse_lng` (en paire, jamais effacées) ; `p_adresse_rue`, `p_adresse_ville`, `p_adresse_code_postal` restent
    interdits (le web les envoie à `null`, sans effet sous `COALESCE`, `public.sql` l.43992-43994).
  - Câblage des deux mondes (`DemoWorld.câblerLot3`, `SupabaseGateways.câblerLot3`) : `avatar` et `geocodage` sortent
    de `DemoWorldTests.portsEnAttenteLot3`. Démo sans réseau : objets en mémoire, URL signée sur l'hôte réservé
    `demo.invalid` lue par le port (jamais résolue), géocodage « Place Bellecour 69002 Lyon », photo source HEIC de
    synthèse (`Resources/media-demo/avatar-demo.heic`) ; DEBUG : `-JOLENE_DEMO_AVATAR refus`,
    `-JOLENE_DEMO_LOCALISATION accordee|refusee|indisponible`, `-JOLENE_DEMO_GEOCODAGE echec`.
- **Reçu et réconciliation (PRINCIPES §3-§4).** Reçu `prepared` écrit puis RELU avant toute requête (échec du
  trousseau ou reçu illisible : rien n'est envoyé, message d'échec du web) ; `started` avant le dépôt ; refus 4xx du
  stockage → `refused`, aucune URL signée ni `p_avatar_url` ; `stored` après le dépôt ; succès annoncé seulement si
  `avatar_url` relue est l'URL envoyée, puis reçu effacé. Délai, coupure ou 5xx laissent le reçu en `started` ou
  `stored` : la réconciliation (ouverture de l'écran, ou juste après l'erreur) relit `avatar_url` — URL du reçu →
  « Photo mise à jour ! », sinon essai clos `not_sent` et message d'échec ; jamais de second dépôt ni de
  `p_avatar_url` rejoué. Un essai encore en vol dans le processus (écran rouvert pendant l'envoi) n'est jamais
  réconcilié (`RegistreEnvoisAvatar`). Un nouvel envoi choisi par l'utilisateur solde d'abord le reçu précédent.
- **Écarts assumés (non juridiques).**
  1. JPEG au lieu du WebP du web (D14) ; limite de 2 Mo appliquée au JPEG envoyé (blueprint v2), pas au fichier
     d'origine.
  2. Les « coordonnées techniques » du web (`SectionProfilPrincipal.tsx` l.875) ne sont jamais affichées (§2.6) ;
     pictogrammes décoratifs « 📍 » retirés (comme en T9) ; un libellé d'adresse vide donne « Position récupérée. »
     (le web afficherait « 📍 » seul).
  3. La position, comme sur le web, n'est écrite qu'avec « Enregistrer les modifications » ; la photo est enregistrée
     dès son choix (le web aussi, `AvatarUpload` l.153-155).
  4. Choix de la source en ligne sous le bouton (photothèque ; appareil photo s'il existe, toujours en démo) plutôt
     qu'une feuille système : identifiants stables sur iPhone et iPad (PRINCIPES §6). Textes sans équivalent web
     (non juridiques, à relire) : « Choisir dans la photothèque », « Prendre une photo » ; « Annuler » est repris de
     `ConfirmationSheet.swift` l.34 (L1-T1b).
  5. Démo : reçus en mémoire vive (`RecusAvatarEnMemoire`, comme les reçus démo du lot 2), pas dans le trousseau
     (« reçu Keychain réel » du blueprint §2.7) : le mode démo reste sans état entre deux lancements et le simulateur
     non signé de la CI n'a pas d'accès fiable au trousseau ; nom d'objet démo daté par l'horloge système (deux photos
     d'une session ne partagent jamais un chemin, `upsert: false`). Libellé DEBUG démo `profil-avatar-etat`
     (« photo » / « initiales », jamais l'URL), même modèle que `deeplink-route`.
  6. Le web limite l'origine aux PNG, JPEG, WebP (`accept`, l.209) ; le natif accepte tout format lu par ImageIO
     (HEIC d'iPhone d'abord) puisqu'il ne transmet que le JPEG converti.
- **Manques et points de fusion des lots (aucun ne dépend de `feat/ios-lot2`).**
  1. **Localisation.** Le blueprint v2 réutilise `LocationPort` du lot 2 (`Ports/AppareilPorts.swift`, L2-T1 ;
     `LocationService`, L2-T4b), absent de la base. Aucun second service n'est créé : un port MINIMAL
     (`LocalisationPort.localiser(delai:)`) et une implémentation isolée `LocalisationProfilProvisoire`, seule
     utilisatrice de CoreLocation hors lot 2, injectée par `AppContainer.localisationProfil` dans le seul écran du
     profil. À la fusion : supprimer `LocalisationProfilProvisoire.swift`, servir `LocalisationPort` par un adaptateur
     sur `Appareil.localisation` (`autorisation()` → `demanderAutorisation()` si `.nonDeterminee` →
     `positionUnique(delai:)` ; `.disponible` → `.disponible`, `.refusee` → `.refusee`, `.indisponible` →
     `.indisponible`, `.precisionReduite` → `.indisponible` (`LocalisationPolicy.issuePrecisionReduite`)), et
     `DemoLocalisationProfil` par `DemoLocationPort` si sa position convient. Aucun nom ne recouvre un type du lot 2.
     (Revue B8, m1) Écart au blueprint acté par décision (« Décisions déléguées du 8 novembre 2026 », « T10 —
     localisation du profil livrée sans le port du lot 2 ») ; point de fusion VERROUILLÉ par
     `FusionLocalisationLot2Tests` (rouge dès que le port du lot 2 arrive dans JoleneCore alors que l'implémentation
     provisoire existe encore) ; règle de la précision réduite tranchée avant la fusion (même décision) :
     l'implémentation provisoire rend déjà `.indisponible`, comme le lot 2, et la recette appareil le dit.
     **Réalisé à la fusion des lots 2 et 3 (12 novembre 2026)** : implémentation provisoire supprimée ;
     `LocalisationProfilAppareil` (JoleneCore, `Ports/LocalisationPort.swift`) sert `LocalisationPort` sur
     `Appareil.localisation` en staging et en production, avec l'attente bornée de l'autorisation (m12) et la
     correspondance ci-dessus (tests `FusionLocalisationLot2Tests`). `DemoLocalisationProfil` est conservé en démo : la
     position de `DemoLocationPort` est l'adresse du profil fictif, et l'enregistrement ne changerait plus la position
     relue (`DemoPhotoPositionTests`). Écart connu : `LocationService` clôt `.indisponible` une demande encore ouverte
     quand une autre arrive (pointage et profil partagent le service) ; l'écran du profil n'en lance qu'une à la fois.
  2. **Journal des reçus.** Le blueprint utilise `ReceiptJournal` « du lot 1 T7 », qui n'existe sur aucune branche
     du lot 1 ; il est livré par L2-T1 (`Receipts/ReceiptJournal.swift`, `RecuDurable.swift`, `KeychainReceiptStore`).
     Point d'extension : `RecuAvatar` porte déjà les membres de `RecuDurable` (domaine `avatar`, `userId`,
     `attemptId`, `estTermine`, `verifierSuccession(apres:)`, `encoder()`, `decoder(_:userId:)`), `RecusAvatarPort`
     est le seul magasin, et `KeychainRecusAvatar` (provisoire) reprend le service `app.jolene.receipts` et le compte
     `avatar.<userId>` du magasin du lot 2. À la fusion : `extension RecuAvatar: RecuDurable {}`, `RecuAvatar.Erreur`
     → `RecuErreur`, `RecusAvatarPort` servi par `ReceiptJournal<RecuAvatar>` sur `KeychainReceiptStore`, suppression
     de `KeychainRecusAvatar` ; un reçu écrit avant la fusion reste relisible (mêmes service, compte et JSON).
  3. **Sélecteurs de photo.** `AvatarPicker.swift` (profil) et `Media/PhotoPickerView.swift` (justificatifs, lot 2)
     coexistent : usages distincts, à unifier à la fusion si leurs contrats convergent.
  4. **Chaîne `NSCameraUsageDescription`** (lot 0) : « … photographier vos documents professionnels et scanner les QR
     codes de pointage. » ne nomme pas la photo de profil. Non modifiée : la garde `check-textes-juridiques-ios` du
     lot 2 (`CHAINES_INFO_PLIST`) verrouille ces chaînes mot pour mot, et l'app Capacitor sert déjà la photo de profil
     avec la même chaîne. Texte proposé pour la tranche qui la changera avec sa garde (texte opérationnel, vouvoyé) :
     « Jolene utilise la caméra pour photographier vos documents professionnels, prendre votre photo de profil et
     scanner les QR codes de pointage. » `NSLocationWhenInUseUsageDescription` nomme déjà la localisation du profil ;
     la photothèque passe par `PHPickerViewController`, sans autorisation. (Revue B8, m3) **Prérequis BLOQUANT de
     toute soumission** (TestFlight externe compris) : section « Prérequis bloquants de soumission (lot 6) » et
     `PORTE_LOT3.md` 6.7.
  5. **CI.** Nouvel éclat « lot3-profil-photo » (`DemoPhotoPositionTests`, six XCUITest depuis la revue B8, trois formats) : l'éclat
     « lot3-notifications » (15 min sur iphone au run 42541548740) aurait dépassé 20 min ; job porté à 170 min (cinq
     éclats de 30 min et le build), résumé et artefact étendus. Point de fusion avec le lot 2 : garder tous les éclats
     et unir les `-skip-testing` de l'éclat socle.
- **Contrat relu en lecture seule sur la production le 09/11/2026** (MCP, `SELECT` sur `storage.buckets` et
  `pg_policies`, `pg_get_functiondef`) : bucket `jolene-documents` privé, limite 25 Mo, MIME autorisés dont
  `image/jpeg` (les types XML ajoutés par `20260718130836` sont aussi présents) ; seules politiques
  `pol_storage_jolene_insert` (INSERT, `fn_peut_gerer_objet_jolene(name)`) et `pol_storage_jolene_select` (SELECT) ;
  `fn_peut_gerer_objet_jolene` exige le premier segment du chemin égal à `auth.uid()` ; `fn_modifier_mon_profil`
  garde `adresse_lat = COALESCE(p_adresse_lat, adresse_lat)` et `avatar_url = COALESCE(p_avatar_url, avatar_url)`.
  Conforme au contrat des gateways ; aucune écriture.
- **Constats serveur (aucune correction écrite).**
  - Un dépôt réussi suivi d'un refus ou d'une coupure de `fn_modifier_mon_profil` laisse un objet orphelin dans
    `jolene-documents` : aucune politique UPDATE/DELETE (`20260713222000` l.1395-1412), comme sur le web. Rien n'est
    exposé (URL signée jamais liée) ; un nettoyage serveur des avatars non référencés serait une tranche backend (B9,
    données) — non ouverte.
  - `api-adresse.data.gouv.fr` répondait 200 au format attendu le 09/11/2026 (requête de contrôle sur un lieu public,
    sans identifiant) ; la migration annoncée vers la Géoplateforme n'est pas vérifiée ici : si le service s'arrête,
    le web et le natif rendent « Position récupérée. » sans ville (best-effort), rien ne casse.
- **Tests.** JoleneCore : `ConversionAvatarTests` (fixture HEIC de synthèse `Resources/media/avatar-source.heic`,
  orientation EXIF 6 et GPS fictif), `RecuAvatarTests`, `EnvoiAvatarTests` (403 → `refused`, aucun `p_avatar_url` ;
  arrêt entre dépôt et RPC → relecture, aucun second envoi ; perte de réponse confirmée par relecture ; essai en vol),
  `AvatarLocalisationModelTests`, `AvatarLocalisationVerbatimTests`, `DemoAvatarLocalisationTests`,
  `ModificationPositionTests`, et les gardes `DemoWorldTests` / `Lot3PortsTests` mises à jour ; JoleneSupabase :
  `SupabaseAvatarStorageTests`, `ApiAdresseGeocodageTests`, `KeychainRecusAvatarTests`, `SupabaseGatewaysTests`
  (mondes comparés) ; XCUITest `DemoPhotoPositionTests` (trois formats, compilés, non lancés localement). Tests T9
  inchangés (aucun affaibli) ; `p_adresse_lat` / `p_adresse_lng` passent des paramètres interdits aux autorisés
  (périmètre T10 du blueprint), la garde « 29 paramètres classés une fois » reste verte.
- **HARD STOP n°4.** Aucun texte juridique ; textes repris verbatim (`AvatarUpload.tsx` l.164, l.166, l.179 ;
  `documentUpload.ts` l.135, l.139, l.174 ; `SectionProfilPrincipal.tsx` l.637, l.861, l.871) ou vouvoyés (l.640,
  l.875, l.876), épinglés par `AvatarLocalisationVerbatimTests`. Décision déléguée sur le destinataire des
  coordonnées : section « Décisions déléguées du 8 novembre 2026 ».

### T10 — corrections de la revue fraîche B8 (09/11/2026)

Tests d'abord pour le majeur, puis correction ; aucun test existant sauté, désactivé ni affaibli : les tests
d'`EnvoiAvatarTests` gardent leurs assertions d'origine et sont RENFORCÉS par l'espion des phases (état initial posé
par `semer` au lieu d'`ecrire`) ; les doubles gagnent des barrières (lecture, écriture, dépôt lent) et le profil
simulé applique aussi bio, ville et position écrites (relecture réaliste). Rouges avant correction : les nouveaux
tests (API absente, puis gardes de la documentation tant que la recette et la décision n'étaient pas écrites).

- **M1 — l'échec de lecture n'est plus une annulation.** `SelectionPhotoAvatar` (JoleneCore) : `annulee` (aucun
  résultat de la photothèque, « Annuler » de l'appareil photo : ni message ni envoi), `lectureEnCours` (une photo est
  choisie, ses octets sont en cours de lecture), `octets(Data)`, `illisible` (fournisseur présent mais données nil ou
  erreur, résultat qui n'est pas une image, prise de vue non encodable). `AvatarProfilModel.recevoir(_:)` publie
  « Impossible de lire le fichier sélectionné. » (`AvatarProfil.Textes.fichierIllisible`, verbatim `documentUpload.ts`
  l.174, déjà épinglé) pour `illisible`, après contrôle de l'epoch ; `lectureCommencee()` pose `lectureEnCours`
  (indicateur de la vignette et du bouton) — la photothèque se ferme dès le choix au lieu de rester ouverte sans
  indicateur pendant le téléchargement iCloud. `.lectureEnCours` est rendue de façon synchrone sur le fil principal
  avant la lecture : l'issue finale arrive toujours après. Démo : `-JOLENE_DEMO_AVATAR illisible`
  (`DemoFixtures.selectionAvatarDemo`, ressource absente comprise : jamais une annulation silencieuse). Tests :
  `AvatarLocalisationModelTests` (`testFichierChoisiIllisibleAfficheLeMessageDuWebSansEnvoi`,
  `testAnnulationDuSelecteurNiMessageNiEnvoi`, `testOctetsLusApresLIndicateurEnvoyesEtAnnonces`,
  `testFichierIllisibleApresChangementDIdentiteRienNEstPublie`), `DemoAvatarLocalisationTests`
  (`testSelectionDemoPhotoOuLectureImpossible`) ; XCUITest
  `DemoPhotoPositionTests.testPhotoIllisibleAfficheLeMessageDuWebSansEnvoi` (trois formats, compilé, non lancé),
  éclat « lot3-profil-photo » inchangé (six tests). Feuilles système réelles : `RECETTE_DEVICE_LOT3.md` §6 (photo
  iCloud en mode Avion).
- **m1** — décision explicite « T10 — localisation du profil livrée sans le port du lot 2 » (section « Décisions
  déléguées »), rattachée à la consigne de l'orchestrateur ; garde `FusionLocalisationLot2Tests` ; règle de la
  précision réduite tranchée (`.indisponible`, `LocalisationPolicy.issuePrecisionReduite`), appliquée dès maintenant
  par l'implémentation provisoire, recette appareil corrigée (« ville renseignée » retiré).
- **m2** — PR web du §3.2 de `PageConfidentialite.tsx` tracée dans « B9 — PR préparées » (à préparer, fichier et
  lignes).
- **m3** — `NSCameraUsageDescription` : prérequis bloquant de soumission (section « Prérequis bloquants de soumission
  (lot 6) », `PORTE_LOT3.md` 6.7, « En attente de Gabrielle » §6.10).
- **m4** — jeton d'annonce dédié `ProfilEditionModel.annoncesLocalisation` (avis de la localisation), distinct de
  `annonces` (encarts de l'enregistrement) ; `AdresseProfilSection` le lit. Test
  `testAnnoncesDeLaLocalisationDistinctesDeCellesDeLEnregistrement`.
- **m5** — verrou mutuel : `peutLocaliser` faux pendant `enregistrementEnCours`, `peutEnregistrer` faux pendant
  `localisationEnCours`, et les deux méthodes refusent d'agir dans ces états (pas seulement les boutons). Tests
  `testEnregistrementVerrouillePendantLaLocalisation`, `testLocalisationVerrouilleePendantLEnregistrement`.
- **m6** — `AvatarProfilModel.reconciliationEnCours` pendant la réconciliation d'ouverture ; `peutChanger` faux
  (bouton inactif) et `changer` sans effet jusque-là. Au niveau du port, `EnvoiAvatar.reconcilier` RÉSERVE l'essai dans
  `RegistreEnvoisAvatar` (comme un envoi en vol) : une seconde réconciliation simultanée du même reçu rend `.aucune`
  sans rien écrire (plus de `transitionInterdite` ni d'échec parasite). Tests
  `testChangerInactifPendantLaReconciliationDOuverture`, `EnvoiAvatarTests.testDeuxReconciliationsSimultaneesUnSeulSolde`.
- **m7** — budget PROPRE à l'envoi : `AvatarProfil.delaiEnvoi(resolution:)` = `etapesReseauEnvoi` (5 : relecture
  d'un reçu interrompu, dépôt ≤ 2 Mo, URL signée, `fn_modifier_mon_profil`, relecture du profil) × délai de
  résolution, soit 75 s en production, au lieu d'un seul délai de 15 s pour toute la chaîne. La borne demeure ; une
  issue inconnue reste relue (réconciliation) avant toute annonce, jamais rejouée. Le web n'a aucun délai sur cet
  envoi. Tests `testEnvoiLentAuDelaDUnDelaiDeResolutionAboutit`, `testEnvoiBloqueAuDelaDuBudgetFinitEnEchec`.
- **m8 — voie de reprise d'un reçu illisible.** `EnvoiAvatar.reconcilier` (ouverture de l'écran) RETIRE un reçu
  illisible (`RecuAvatar.Erreur.illisible` ou `.utilisateurDifferent` : JSON altéré, version inconnue, autre
  utilisateur) par effacement brut de la clé `avatar.<userId>`, essai inconnu clos sans requête ni `p_avatar_url` ;
  la photo affichée reste `avatar_url` relue à l'ouverture (`ProfilEditionModel.charger`) ; le prochain envoi part
  d'un reçu neuf. L'envoi lui-même reste fail-closed (`testReçuIllisibleOuMagasinEnPanneRienNEstEnvoye` inchangé). Une
  erreur du MAGASIN (trousseau verrouillé, refus du système) n'est pas un reçu illisible : rien n'est effacé, la
  réconciliation échoue fermée, et l'ouverture n'affiche rien (aucun envoi n'a été demandé) ; impasse résiduelle
  consignée : un trousseau durablement en panne bloque l'envoi natif (comme tous les reçus du lot 2), la photo reste
  modifiable sur jolene.app. Point de fusion : `RecusAvatarPort.effacer(userId:)` doit rester un effacement brut par
  clé (`ReceiptStorePort.effacer(CleRecu)` du lot 2), jamais `ReceiptJournal.effacer`, qui exige un reçu lisible.
  Tests `testReçuIllisibleRetireParLaReconciliationPuisNouvelEnvoiPossible`,
  `testMagasinEnPanneALaReconciliationRienNEstEfface`.
- **m9** — espion `RecusAvatarEspion` (journal ordonné des phases écrites et des effacements) : les tests du refus
  403 (`prepared, started, refused, effacé`), du refus serveur (`… stored, refused, effacé`), des réconciliations
  (`not_sent, effacé`) et des succès (aucun `not_sent`) échoueraient si le code effaçait le reçu sans journaliser la
  phase terminale.
- **m10** — tests de changement d'identité PENDANT un envoi (`testIdentiteRemplaceePendantLEnvoiRienNEstPublie`) et
  PENDANT la réconciliation d'ouverture (`testIdentiteRemplaceePendantLaReconciliationRienNEstPublie`) ; les erreurs
  de conversion vérifient aussi l'epoch avant publication.
- **m11** — `SupabaseAvatarStorage.sessionParDefaut` : session éphémère unique, `urlCache = nil`,
  `reloadIgnoringLocalCacheData`, ni cookie ni identifiant mémorisé ; la requête elle-même ignore tout cache local.
  `URLSession.shared` conservait l'URL signée (jeton de 5 ans) et les octets de l'image dans le cache disque partagé.
  Test `testLectureDeLImageSansCacheNiCookie`.
- **m12** — `LocalisationProfilProvisoire` (code provisoire, corrigé) : attente de la feuille d'autorisation bornée
  (`LocalisationPolicy.delaiAutorisationProfil`, 60 s ; une réponse plus tardive vaut pour l'appui suivant) ; une
  demande faite pendant une autre en attente (second écran, instance partagée) attend la MÊME issue, au lieu de rendre
  `.indisponible`. Pas de test unitaire possible (cible app, CoreLocation) : recette appareil §6 et garde de fusion.
- **m13** — appareil photo présenté par `fullScreenCover` (photothèque toujours en feuille) ; à vérifier en recette
  appareil sur iPad (§6).
- Aucun texte nouveau (le message de M1 est le texte web déjà épinglé), aucun texte juridique, aucune RPC, aucune
  écriture serveur.

## T12 — revenus en lecture (branche `lot3/l3-t12-v2`, 09/11/2026 ; B9, jamais mergée sans go)

- **Livré.** Onglet Revenus natif (`Jolene/Screens/Revenus/RevenusScreen.swift`), à la place du placeholder du lot 0,
  port de l'aperçu réellement monté par `/soignant/mes-gains` (`MesGainsApercuContent`, onglet par défaut de
  `MesGains.tsx`) restreint à D4 :
  - totaux serveur `fn_mes_revenus_connect` (« Ce mois », « Total réglé », « Autres paiements en attente » et leur note,
    `PageStripeConnect.tsx` l.392-417), affichés seulement là où le web rend ses cartes (revue B8, M1, ci-dessous) :
    `LIBERAL` ou `MIXTE` (l.178, l.300), hors compte de test (l.302, l.367), compte Connect complet
    (`stripe_connect_actif`, l.367) ; trois nombres finis exigés ;
  - bloc « Paiement rapide » `fn_mes_paiements_escrow` (sept états, groupes « À venir », « Récemment versé » (trois au
    plus), « Annulés », section absente sans ligne, litige → page web de la mission par le présentateur `.safari`,
    revue B8 n°2, M1 ci-dessous) ;
  - missions TERMINEE paginées par 50 avec **exactement** les colonnes de `MesGains.tsx` l.95 (D5, test-garde contre la
    source web), montant de `montantFinanceAfficheMission` (golden T2, correction Rist inactive : témoin démo 280 €),
    régime de la mission (`type_contrat_applique ?? type_contrat_recherche`, jamais `soignants.type_exercice`), état
    de la dernière déclaration (`indexerDernierPaiementParMission` + `classerPaiementSalaire`, golden T2), noms
    d'établissement par `fn_etablissements_safe` seul ; notes « net estimé » verbatim ;
  - renvois web « Factures » et « Paie » (D4), présences d'une mission (`/soignant/presences/mission/:id`, lot 2) ;
    audit `DONNEES_PERSO_CONSULTATION` (`page: mes_gains`) une fois par session (epoch ; revue B8 n°2, m3, écart
    11) ; état d'erreur et reprise de la page
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
  remplace l'écran, la ligne de `ecranNatifLivre` ne change pas (libellé de `DestinationLienTests` et, revue B8 n°2,
  m1, commentaire de la ligne mis à jour : « T12 — RevenusScreen »). Les
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
  9. (revue B8, m6) « Derniers versements Stripe » (`<SuiviVersementsConnect />`, monté par l'aperçu `MesGains.tsx`
     l.428, juste sous le paiement rapide : 20 derniers `stripe_transfers` `CHARGE_REUSSI` / `TRANSFERE` / `PAYE` du
     soignant, état du versement bancaire, lien vers la mission) non porté : c'est le suivi des versements Connect,
     repris par **T14a** (Stripe Connect) avec l'écran `/soignant/stripe-connect`, qui le monte aussi (l.418).
  10. (revue B8, M1) Résidus non juridiques de la visibilité des totaux, après correction : le web décide « COMPLET »
      par l'edge `stripe-connect-status` (l.45-69, cache 5 min, rafraîchi chez Stripe sur un cache périmé), le natif
      par `stripe_connect_actif` de la même réponse RPC (`fn_soignant_stripe_connect_actif`, `public.sql` l.57303 :
      la ligne `stripe_connect_onboarding` que cette edge relit et réécrit) — un compte complété ou suspendu chez Stripe
      depuis la dernière lecture de l'edge peut donc différer jusqu'à la prochaine ; le web masque aussi les cartes
      quand l'edge échoue (`erreurStatut`, l.367), le natif n'appelle pas l'edge (T14a) ; enfin, quand la RPC
      elle-même échoue, le natif ne connaît pas le statut Connect et affiche « Vos revenus sont temporairement
      indisponibles. » à un libéral hors compte de test, là où le web montre la carte de son statut Stripe (T14a).
  11. (revue B8 n°2, m3) Trace de consultation moins fréquente que le web : l'audit `DONNEES_PERSO_CONSULTATION`
      (`page: mes_gains`) est écrit **une fois par session (epoch)** — le modèle vit autant que l'onglet, toujours monté
      (`StateObject` de `RevenusScreen` dans `MainTabView`) —, alors que le web l'écrit à chaque chargement réussi
      (montage, page, `reloadKey` : `MesGains.tsx` l.147-153, dans `load`). Depuis la revue B8 n°1 (m1), une relecture
      au-delà de 60 s ou par jeton de péremption est assimilée à un montage web pour les **données**, pas pour la trace ;
      « Charger plus » et « Réessayer » ne la réécrivent pas non plus. Conforme au plan v2 (« audit consultation une
      fois », §3 T12) ; pas un défaut du code. Choix de conformité Jolene, sans texte affiché ni règle exposée à
      l'utilisateur (trace interne `journaux_audit`, best-effort sur le web comme en natif) : aucune décision juridique
      n'a été nécessaire. Test `RevenusModelTests.testAuditUneSeuleFoisParSessionMemeApresRelecturesEtPages`.
  12. (revue B8 n°2, M1) Le détail natif de la mission (lot 0/1, `MissionDetailScreen`) ne porte pas le bloc litige du
      web (`fn_litige_pour_mission`, « Litige en cours sur cette mission » / « Décision du litige », « Voir le litige »
      vers `/soignant/litiges?litige=…`, `DetailMissionSoignant.tsx` l.444-458, l.1241-1271) : le paiement rapide en
      litige ouvre donc la page web de la mission (ci-dessous) ; ce bloc et `/soignant/litiges` restent au lot 4
      (`PARITE_SOIGNANT.md`).
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
  d'exercice : la visibilité des totaux reprend les conditions d'affichage du web, l.178, l.300, l.302, l.367, revue
  B8 M1). Wording escrow : aucun « garanti », aucun « stationne » (test).
- **CI UI : cinquième éclat `lot3-revenus`** (`DemoRevenusTests`, domaine de T12, T13, T14a, T14b), « lot3-notifications »
  atteignant déjà 15 min sur iphone ; socle `-skip-testing:JoleneUITests/DemoRevenusTests`, résumé à cinq éclats, job
  porté à 175 min. Point de fusion avec le lot 2 : garder les éclats des deux lots, unir les `-skip-testing` du socle.
- **Migrations d'identifiants XCUITest (règle 8)** : `DemoConsultationTests.assertFiveTabs` (`placeholder-revenus` →
  `revenus-screen`, absence du placeholder affirmée) ; `DemoLiensLot3Tests.testSectionFacturesDeRevenusEnRenvoiWeb`
  (absence de `revenus-screen` pour la section factures).

### T12 — corrections de la revue fraîche B8 (09/11/2026)

Tests d'abord (commit séparé), puis correction ; aucun test sauté, désactivé ni affaibli. Chaque test changé était
faux au regard du web (M1) ou ajouté.

- **M1 — visibilité des totaux (défaut du code et test faux).** `PageStripeConnect.tsx` l.106 n'est que la condition de
  CHARGEMENT (`LIBERAL || MIXTE || statut_liberal === 'ACTIF'`) ; l'AFFICHAGE des cartes (l.392-417) exige `isLiberal`
  (l.178, `LIBERAL || MIXTE`, appliqué l.300 ; `statut_liberal` ignoré), puis `!estCompteTest && !erreurStatut &&
  statut === 'COMPLET'` (l.367). Le natif affichait les totaux à trois profils que le web ne voit jamais : salarié
  `statut_liberal = ACTIF` (dont `fn_mes_revenus_connect` additionne les réceptions de salaire `paiements_soignant`
  CONFIRME hors Connect, présentées comme « Total réglé ») — cas que `RevenusLectureTests` figeait à tort
  (`("SALARIE", "ACTIF", true)`, test faux, corrigé à `false`) —, libéral sans compte Connect complet, compte de test.
  Correction : `ExerciceRevenus.afficheTotaux` = `type_exercice ∈ {LIBERAL, MIXTE}` et `est_compte_test ≠ true`
  (lecture `soignants(type_exercice, est_compte_test)`, sous-ensemble des colonnes de l.95 ; `statut_liberal` n'est plus
  lu), RPC non appelée sinon ; `TotauxRevenus.visibles` : cartes seulement si `stripe_connect_actif = true` (même
  réponse, `fn_soignant_stripe_connect_actif` = ligne `stripe_connect_onboarding` COMPLET + `onboarding_complete`,
  `charges_enabled`, `payouts_enabled`), `false` → section absente même sans les trois nombres, drapeau inconnu →
  absente, `true` sans les trois nombres finis → « indisponible ». Mêmes règles en démo (fixture `demo-revenus.json` :
  `est_compte_test: false`). Vérifié en lecture seule sur la production le 09/11/2026 : définition live de
  `fn_soignant_stripe_connect_actif` identique au dump (l.57303-57326), appelée par `fn_mes_revenus_connect` ;
  `has_column_privilege('authenticated', 'public.soignants', 'est_compte_test', 'SELECT')` vrai (colonne
  `boolean NOT NULL`, l.68108). Test-garde des lignes web citées (`RevenusLectureTests.testConditionsDuWebCiteesASaLigne`,
  l.93, l.95, l.106, l.178, l.300, l.367, l.392 ; `SupabaseRevenusGatewayTests.testSelectIdentiqueALaSourceWeb`).
  Écarts restants, non juridiques : écart 10 ci-dessus. Aucune décision juridique (affichage aligné sur le web).
- **m1 — données périmées (défaut du code).** `RevenusModel.chargerSiNecessaire(peremption:)` relit à l'apparition
  (retour sur l'onglet, retour au premier plan par `scenePhase`, onglet affiché seulement) chaque section lue il y a
  plus de `delaiRelecture` (= `AccueilModel.delaiRelecture`, 60 s ; missions depuis la page 0, comme un montage
  web), et toutes dès que le jeton avance : `MainTabView.presenter(.revenus)` (lien universel `/soignant/mes-gains`,
  tap) l'incrémente. Un échec attend toujours « Réessayer » ; une relecture annulée reste due. En démo l'horloge est
  fixée : seule la relecture par jeton s'y observe. Tests `RevenusModelTests` (horloge réglable, jeton).
- **m2 — audit (défaut du code).** L'audit `DONNEES_PERSO_CONSULTATION` part après la publication dans une tâche non
  structurée (borne de la session, échec silencieux, comme le `.then(undefined, …)` du web) : la lecture se termine
  aussitôt (« Charger plus », « Réessayer », tirer pour actualiser libres) et l'annulation de la vue ne l'interrompt
  plus (`auditTente` posé au lancement d'une écriture que plus rien n'annule). Test
  `testAuditNeRetientJamaisLEcranEtSurvitALAnnulationDeLaVue`.
- **m3 — page sautée (défaut du code, reproduit du web l.797-798).** « Charger plus » masqué tant que le bandeau
  d'erreur est affiché (`afficheChargerPlus`) ; appelé quand même, `chargerPlus` relit la page en échec. Test
  `testChargerPlusApresUnEchecRelitLaPageEnEchecSansEnSauter`. Écart volontaire au web (non juridique).
- **m4 — XCUITest en course (défaut du test).** `DemoRevenusTests` attend les cartes (`require`, 30 s) avant d'en lire
  les libellés, et dans la variante d'échec avant d'affirmer qu'elles restent lues.
- **m5 — accessibilité de la ligne de mission (défaut du code).** Un vrai bouton dans la ligne (chevron, 44 × 44,
  `revenus-mission-ouvrir-<id>`), nommé comme le `aria-label` du web (« Voir mission … », `MesGains.tsx` l.703 ; le
  web : `role="button"`, `tabIndex`, Entrée/Espace, l.701-706) : atteignable par VoiceOver, le Contrôle vocal et le
  clavier. L'action nommée posée sur le conteneur `contain` (jamais focalisé) est retirée ; le tap de la ligne et les
  identifiants internes sont inchangés. XCUITest : `testMissionOuvreSesPresencesSurLeWeb` touche aussi le bouton.
  Aucun texte affiché nouveau (libellé vocalisé = `aria-label` web).
- **m6** : `SuiviVersementsConnect` consigné (écart 9, T14a) et dans `PARITE_SOIGNANT.md`.
- **m7 — sources.** `PageStripeConnect.tsx` l.104 → l.106 (et conditions d'affichage citées) ; « web l.92 » → l.93 ;
  « l.95-108 » → l.94-111 ; `MesGains.tsx` l.55-58 → l.56-59 ; l.249-250 → l.243-244 ; l.632-633 → l.564-565 (lignes
  épinglées par `RevenusPresentationTests.testChaqueTexteRepriseDuWebEstVerbatimASaLigne`) ; dump (`CONTRATS`)
  l.42347 → l.42396, l.42205 → l.42254, l.42184 → l.42233, et dans les mêmes fiches l.42411-42416 → l.42460-42465,
  l.42234-42248 → l.42283-42297, l.42220-42230 → l.42269-42279 (aussi `RevenusPresentation`, l.42272-42283) ;
  « décision du 09/11/2026 » reformulée : le tutoiement des libellés escrow applique la règle 2 de
  `LOTS_2_5_DECISIONS` et la décision 9 du lot 1, ce n'est pas une décision nouvelle ; commentaire périmé de
  `MainTabView` (« Revenus n'a pas de pile ») corrigé ; l'assertion d'absence de `revenus-avances-web` est gardée
  comme documentation (identifiant jamais codé, elle passe à coup sûr ; commentaire dans le test).

### T12 — corrections de la revue fraîche B8 n°2 (09/11/2026)

Tests d'abord (commit séparé), puis correction ; aucun test sauté, désactivé ni affaibli. Aucun texte nouveau (affiché
ou vocalisé), aucun texte juridique, aucune RPC nouvelle, aucune écriture serveur.

- **M1 — litige du paiement rapide (défaut du code, et test faux).** Sur le web, la ligne « Paiement en litige · voir le
  litige de la mission » est un `Link` vers `/soignant/missions/${l.mission_id}` (`PaiementsEscrowAVenir.tsx`
  l.152-155) : cette page (`DetailMissionSoignant.tsx`) lit le litige (`fn_litige_pour_mission`, l.444-458) et affiche
  « Litige en cours sur cette mission » ou « Décision du litige », avec « Voir le litige » / « Consulter la décision »
  vers `/soignant/litiges?litige=…` (l.1241-1271). Le natif empilait `MissionDetailScreen` (lecture du lot 0/1), sans
  bloc litige ni chemin vers `/soignant/litiges` (renvoi web) : une impasse, dans un domaine B9, sous un libellé verbatim
  qui promettait le litige. `DemoRevenusTests` figeait ce comportement (« jamais un renvoi web ») : test faux.
  **Option (a) retenue** : tant que le détail natif ne porte pas le bloc litige, la ligne ouvre la **page web
  canonique de la mission** (`https://jolene.app/soignant/missions/<id>`) par le présentateur `.safari` du
  coordinateur des liens (cible `CibleNotification.web`, `MainTabView.presenter`), jamais le détail natif.
  **Choix de la page (consigné)** : la page de la mission plutôt que `/soignant/litiges` — c'est la destination exacte
  du lien web ; le serveur y choisit le litige de **cette** mission et son état (ouvert ou clos, décision), alors que
  `fn_mes_paiements_escrow` ne fournit pas `litige_id` (seulement `a_litige`) : `/soignant/litiges` n'ouvrirait que la
  liste, sans le litige ciblé (`?litige=` impossible à construire). Renvoi construit hors `LinkRouter`, comme
  `ProfilEdition.renvoiTypeExercice` (T9) : la route `/soignant/missions/:id` est native, son bloc litige ne l'est pas ;
  identifiant serveur encodé comme un segment de chemin. Code : `LigneEscrowAffichee.renvoiLitige` (remplace
  `ouvreMission`), `RevenusPresentation.lienLitige` / `renvoiLitige`, `RevenusScreen` (bouton seulement avec le
  présentateur `.safari` ; `navigationDestination(for: MissionRoute.self)` retirée, pile `cheminRevenus` gardée pour
  T13/T14). Tests : `RevenusPresentationTests.testLitigeOuvreLaPageWebDeLaMissionTantQueLeDetailNatifNePortePasLeBloc`,
  `.testSourcesWebDuRenvoiDuLitigeASaLigne` (lien du web et bloc litige de la page épinglés à leur ligne : si le web
  change de destination ou retire le bloc, le test rougit), `.testLibelleEtAideDeChaqueEtat` (seul le litige porte le
  renvoi) ; XCUITest `DemoRevenusTests.testLigneEnLitigeOuvreLaPageWebDeLaMission` (remplace
  `testLigneEnLitigeOuvreLeDetailDeLaMission`, trois formats, compilé, non lancé ; page canonique sur le double démo,
  détail natif jamais empilé, ligne « retardé » non cliquable). Écart 12 ci-dessus ; `PARITE_SOIGNANT.md` (lignes
  `/soignant/missions/:id` et paiements rapides). La tranche qui portera le bloc litige dans le détail natif (lot 4,
  avec `/soignant/litiges`) remplace ce renvoi et ces tests.
- **m1 — commentaire périmé.** `DestinationLien.ecranNatifLivre(.revenus(section: .apercu))` : « T12 — RevenusScreen
  (onglet Revenus) ».
- **m2 — état des lignes des pages précédentes (défaut du code).** Chaque page relit **toutes** les déclarations du
  soignant (`paiements_soignant` sans filtre de mission, l.102-107), mais `RevenusModel.fusionner` ne remplaçait que les
  lignes de la page courante : une déclaration confirmée entre la page 0 et la page 1 restait « Réception à confirmer »
  en natif, « Réception confirmée » sur le web, qui remplace sa carte entière à chaque chargement (`setPaiementsMap`,
  l.140-142). Correction : `PageMissionsTerminees.derniersPaiements` (index de toutes les déclarations relues, rempli
  par `RevenusAssemblage.page`, démo et Supabase) ; `RevenusModel.appliquer` réindexe **toutes** les lignes affichées
  à chaque lecture réussie (une mission absente de l'index n'a plus de déclaration, comme sur le web). Tests
  `RevenusModelTests.testChargerPlusRelitLEtatDesLignesDesPagesPrecedentes` (rouge sur l'ancien code : quatre
  assertions, l'exemple de la revue) et `RevenusLectureTests.testPageIndexeLaDerniereDeclarationEtLeNomDEtablissement`.
- **m3 — fréquence de l'audit (documentation ; pas un défaut du code).** « Une fois par ouverture » devient « une fois
  par session (epoch) » (section T12, `RevenusModel`, `RevenusModelTests`) ; trace RGPD moins fréquente que le web
  consignée (écart 11). Test d'épinglage `testAuditUneSeuleFoisParSessionMemeApresRelecturesEtPages` (vert dès
  l'écriture : il fige le comportement documenté).

## Intégration de T8, T10, T12 et L3-TJ sur `feat/ios-lot3` (vague 4, 09/11/2026)

Fusions `--no-ff` sur la base `origin/feat/ios-lot3` (`01473089`), dans l'ordre : `origin/main` (`f9a8c236`, #1115,
hors `ios-native/`), `origin/fix/ios-tests-instables` (`454c88ec`, PR #1125 : ses deux derniers commits, budget de
blocage distinct du délai et relevé des attentes bloquées), `lot3/l3-t8-v2` (`beea994e`), `lot3/l3-t10-v2`
(`8ab5b69c`), `lot3/l3-t12-v2` (`e2c54698`), `lot3/l3-tj-v2` (`dc71c33b`). Conflits résolus en gardant les deux côtés,
sans changer aucune règle ni aucun texte affiché :

- **CI UI, sept éclats.** T8, T10, T12 et L3-TJ ajoutaient chacune un éclat au même endroit, T8 et L3-TJ sous le
  même nom « lot3-inscription » (T8 : `DemoCompletionInscriptionTests` ; L3-TJ : `DemoInscriptionTests`, sorti de
  « lot3-compte », 19,1 min sur ipad-landscape au run 42549855710). Un seul éclat « lot3-inscription » porte les
  deux classes (domaine de l'inscription, 15 XCUITest) ; « lot3-profil-photo » (T10) et « lot3-revenus » (T12)
  s'ajoutent ; socle (`-skip-testing`), résumé, boucle des xcresult et artefact couvrent les sept éclats, job à
  230 min (7 × 30 + 20). Aucun test retiré ni déplacé hors d'un éclat.
- **Relevé des attentes bloquées (#1125 × vague 3, défaut révélé par la fusion).** L'étape de #1125 lisait
  `attachments/manifest.json`, alors que l'éclatement de la vague 3 exporte les pièces jointes par éclat
  (`attachments/<éclat>/`) : le relevé aurait toujours conclu « aucun manifest.json exporté », sans jamais rien
  relever. Il lit désormais le manifest de chaque éclat (liste `ECLATS`, celle de la boucle des xcresult), avec une
  colonne « Éclat » ; toujours informatif (`continue-on-error`). Garde : `check-rpc-contracts-lot3.node.mjs`
  (même liste que la boucle, un manifest par éclat) ; script vérifié sur un jeu de pièces jointes simulé.
- **Monde démo et composition.** `DemoWorldTests.portsEnAttenteLot3` : `avatar` et `geocodage` (T10), `revenus`
  (T12) câblés, restent `paiements`, `iban`, `stripeConnect`. `AppContainer` : surcharges démo de T8
  (`JOLENE_DEMO_BROUILLON`), T11 et T12 (`JOLENE_FORCE_REVENUS_ECHEC`). `PointDEntreeLiens` injecte
  `fermeturesRenvoiWeb` (T8, retour d'un renvoi) et `presentationPageWeb` (L3-TJ, TJ3). `DemoInscriptionGateway` :
  complétion de T8 et jeton `demo-sans-intention` de L3-TJ. `export-demo-fixtures.mjs` : fixtures de T8
  (`demo-types-exercice.json`) et de T12 (`demo-revenus.json`, `demo-escrow.json`, `demo-missions-terminees.json`),
  régénérées sans diff.
- **Documents.** `PARITE_SOIGNANT.md` : ligne « Avatar et localisation » de T10, ligne « Type d'exercice » de T8.
  Ce mémo : sections T8, T10, T12 dans cet ordre ; section HARD STOP : puces d'accessibilité et de T11 retirées par
  L3-TJ (reprises par TJ5 et TJ2), puces de T10 et T12 tranchées par délégation ; §6.6, §6.7 et §6.10 réunis.
  **Section « Décisions déléguées du 8 novembre 2026 » unique** : TJ1 à TJ8, puis T8-J1 à T8-J5 (écrites par T8 dans
  sa section, déplacées sans changement de fond ; ligne de délégation au libellé exact de la règle, sans majuscule
  initiale) et les deux décisions de T10, puis deux décisions prises à l'intégration : textes non juridiques de la
  photo de profil (T10) et instruction, selon TJ8, des libellés escrow et de la note « net estimé » (T12, écrite
  avant TJ8). Aucun texte n'attend plus la relecture de Gabrielle (garde de L3-TJ).
- **Gardes rouges à la fusion (tests faux pour la base fusionnée, étendus, jamais affaiblis)** :
  `check-rpc-contracts-lot3.node.mjs` « décisions déléguées » exigeait exactement TJ1 à TJ8 (état de L3-TJ seule) :
  il exige TJ1 à TJ8 d'abord, puis la liste nommée des décisions des tranches, chacune avec sa ligne de délégation,
  et épingle les sources de la décision T12 (`PageCGU.tsx` l.115, `PaiementsEscrowAVenir.tsx` l.56) ; « éclats UI du
  lot 3 » ne connaissait que les quatre éclats de L3-TJ : carte étendue aux six éclats de lot, plus la liste
  `ECLATS` du relevé.
- `project.pbxproj` régénéré par `xcodegen generate` après chaque fusion. Aucune RPC nouvelle (contrats : 41 RPC,
  aucune dérive), aucune écriture serveur ; B9 inchangé (T8 et T12 restent soumises au go de Gabrielle).
- **Recette CI, run 42579729412 (`85ea5968`) : ipad-portrait vert (1 147 tests), trois défauts de TEST révélés**
  (aucun défaut du code de l'app ; correctif tests d'abord, aucun test affaibli) :
  - `DemoPreferencesTests.testPreferencesDemoModifieesEnregistreesPuisRelues` (ipad-landscape ; vert mais 308 s
    au run 42549855710, 442 s sur iphone ici) : `scrollTo` reprenait la direction de recherche quand la cible
    revenait dans le cadre du conteneur sans être atteignable — `prefs-canal-sms` remonté à y = 109,5…153,5, sous la
    barre de navigation translucide (32…140), puis renvoyé à y = −167,5 : vingt glissements en alternance (relevés
    dans les « Synthesized Event » du xcresult). Règle extraite en fonction pure partagée
    (`PartageUITests/PasDeDefilement.swift`, testée par `PasDeDefilementTests`) : cible dans le cadre → pas court
    vers le centre, jamais la direction de recherche ;
  - `DemoProfilTests.testEditionDeLaVilleDeRechercheEnregistreeRelueEtRetrouvee` (ipad-landscape ; défaut révélé par
    T10, qui ajoute la photo et la position au-dessus du champ) : `profil-ville-recherche` à y = 104…145 sous la
    barre de navigation, atteignable par une bande de 4 pt, touché deux fois sans focus. `focus` redescend désormais
    un champ recouvert par une barre de navigation ATTEIGNABLE (celle de l'écran au premier plan) avant de le
    toucher, comme il remontait déjà un champ recouvert par le clavier ;
  - `DemoRevenusTests.testErreurPuisReprise` (T12, jamais lancé avant ; iphone et ipad-landscape) : « Réessayer »
    sous la ligne de flottaison (y = 1 061,5 pour 820 pt) touché sans défilement ; `scrollTo` avant le tap.
  - Même run, iphone : la même attente de `DemoProfilTests` (ville) a aussi échoué sur un blocage unique de 20,9 s
    (budget de blocage de 15 s, #1125), condition vraie à la dernière évaluation ; runner surchargé (44 attentes
    bloquées absorbées sur ce job, tests 2 à 4 fois plus lents qu'ipad-portrait). Aucun changement : le budget
    n'est pas relevé ; la recette suivante tranche.
- **Recette CI, run 42593592247 (`4aaa18a1`) : iphone vert (1 154 tests, dont la même attente de la ville), les
  trois défauts ci-dessus corrigés ; ipad-landscape, un quatrième défaut de TEST** :
  `DemoProfilTests.testPrenomVideRefuseAvecLeMessageServeur` — les vingt glissements de `scrollTo` vers
  « Enregistrer les modifications » partaient de (590 ; 564,4), sur le curseur `profil-rayon` (262…918 × 538…569) :
  le curseur captait le geste (sa valeur passait à 50 km, le milieu de la piste) et la page ne défilait pas. Le
  point de départ d'un glissement ne tombe plus jamais sur un curseur (zone tactile comprise) : couloir gauche,
  sinon droit (`PasDeDefilement.abscisseDeGlissement`, testée). Défaut latent de `drag`, révélé par la position du
  curseur après l'ajout de la photo et de la position (T10).
- **Recette CI, run 42606279978 (`738b10c6`, deuxième et dernier essai)** : iphone et ipad-landscape verts
  (1 158 tests chacun, 0 ignoré) ; ipad-portrait rouge sur deux tests de l'éclat « lot3-compte », verts au même run
  sur les deux autres formats et au run 42579729412 sur ipad-portrait : `DemoCompteLot3Tests`
  (`testExportJSONFeuilleFermeeSansPartageAucunSucces`, tap unique hors popover tombé dans le cadre du bouton source,
  popover resté ouvert) et `DemoLiensLot3Tests` (`testRouteNonLivreeRenvoiWebAussitotSansSession`, « Se connecter »
  touché sans effet visible). Défauts de TEST (geste unique non confirmé), sans lien avec les fusions ni avec les
  correctifs ci-dessus ; corrections proposées dans `REVUES_LOT3.md` (section d'intégration de la vague 4), à
  livrer avec une nouvelle recette des trois formats avant tout merge du lot.

## B9 — PR préparées et poussées, jamais mergées sans go explicite de Gabrielle

Pour chacune : branche poussée, tests verts, corps de PR prêt ; « CI verte + revue fraîche » ne remplace pas le go.

- **B3** — PR backend de la contestation de paiement (paiements ; `CREATE OR REPLACE` depuis la définition live,
  garde-fou 9.0 n°2 ; `test:escrow`, `test:regression` et `guards` requis, B7). **Mergée sur `main` (#1118)**,
  reprise dans `feat/ios-lot3` le 08/11/2026 : fiche `fn_contester_paiement_soignant` de `CONTRATS_RPC_SOIGNANT.md`
  et garde `check-rpc-contracts-lot3.node.mjs` mises au contrat d'après B3 ; T13 (B9) reste à livrer.
- **T7** — compte rapide et confirmation (consentement CGU transmis par `fn_demarrer_inscription p_cgu`) ; branche
  `lot3/l3-t7-v2` poussée (section T7 ci-dessus), préalable captcha `PORTE_LOT0.md` 3.1 / 3.2 non mesuré.
- **T8** — complétion et `register-soignant` (inscription, audit `RGPD_CONSENTEMENT_DONNE` côté serveur) ; branche
  `lot3/l3-t8-v2` poussée (section T8 ci-dessus), décisions juridiques déléguées T8-J1 à T8-J5.
- **T12** — revenus en lecture (paiements, escrow) ; branche `lot3/l3-t12-v2` poussée (section T12 ci-dessus), lecture
  seule, aucune action de paiement.
- **T13** — paiements déclarés (confirmation ; contestation après B3).
- **T14a** — Stripe Connect.
- **T14b** — IBAN (données bancaires).
- **T16** — dispatch STAGING (secrets STAGING, suppression des comptes jetables, bascule transactionnelle de la
  cohorte D5-R).
- **PR web « destinataire du géocodage inverse » (légal exposé ; À PRÉPARER, hors du chantier iOS)** — suite de la
  décision déléguée « T10 — coordonnées du profil transmises au géocodage inverse » (revue B8 de T10, m2) : nommer le
  service d'adresse de l'État (`api-adresse.data.gouv.fr`, appelé par `src/lib/geocodage.ts` l.18) parmi les
  destinataires de la politique de confidentialité, dans `src/pages/PageConfidentialite.tsx` — tableau du §3.2
  « Sous-traitants et processeurs de données » (titre l.92, `<tbody>` l.97-107 : une ligne à ajouter après celle
  d'APNs / FCM, l.106) et, si la PR le juge utile, la mention de la localisation volontaire du profil au §2.3
  (l.49-52). Sources primaires : RGPD art. 4, points 1 et 9, art. 13, paragraphe 1, point e). À instruire dans la PR,
  sur la documentation publiée du service : son opérateur, sa localisation et la qualification (sous-traitant ou
  destinataire responsable de son traitement : le tableau est intitulé « Sous-traitants », la ligne peut devoir aller
  dans une mention distincte). Préparée sur une branche, jamais mergée sans le go de Gabrielle ; le natif n'a rien à
  changer (la page est servie par le renvoi web du hub). Non préparée à ce jour : les tranches iOS ne touchent pas
  `src/`.
- **Signalements sans correction au lot 3** (chacun B9 si une PR est ouverte) : RLS `pol_paie_soig_update`, qui
  permet au soignant un UPDATE direct de `paiements_soignant` (borné par `trg_protect_paiement_soignant` mais
  contournant les effets de la RPC — le natif n'écrit que par RPC) ; faux succès IBAN du web
  (`SectionPaiements.tsx` l.259-262, D20) ; export RGPD qui inclut les notes reçues non publiées (tranché par
  délégation, L3-TJ TJ4 : PR backend B9 à préparer hors lot, go au merge).
- **PR web HARD STOP à préparer hors lot** (TJ1, TJ2, TJ6 ; le natif suivra par ses gardes) : phrase de consentement
  (CGU acceptées, politique de confidentialité portée à la connaissance), « l'intégralité » de l'export, l.280 de
  `SectionPaiements.tsx` (destinataires de l'IBAN).

## HARD STOP n°4 — textes affichés

- Le natif n'affiche que des textes **verbatim** du web ou du serveur, chacun relié à sa source (fichier:ligne) et
  gardé par un test ; aucun texte juridique nouveau ni reformulé, aucun changement de délai ou de règle juridique
  côté serveur. Depuis la délégation du 8 novembre 2026, les décisions juridiques sont instruites et tranchées avec
  leurs sources sous « Décisions déléguées du 8 novembre 2026 » ; la règle verbatim ne change pas (le natif suit le
  web mot pour mot, tutoiement compris).
- Tranchés par délégation (L3-TJ, 9 novembre 2026) : CGU et confidentialité de l'inscription, consentement transmis
  par `p_cgu` et refus captcha (TJ1) ; titre RGPD de l'export (description du web inexacte, non portée, critère de
  TJ8) et textes natifs de T11 (TJ2) ; pages `/cgu` et
  `/confidentialite` en démo (TJ3) ; export RGPD et notes reçues non publiées (TJ4) ; textes natifs sans équivalent
  web de T1b, T4, T5 et T9 (TJ5).
- Tranchés par leur tranche selon TJ8 (intégration du lot 3, 9 novembre 2026) : avertissement d'exclusivité et libellés
  de mode d'exercice (T8, T8-J2 et T8-J3), libellés escrow et note « net estimé » (T12, « T12 — textes de l'onglet
  Revenus »). À trancher par leur tranche, selon les règles TJ6 à TJ8 : textes de la contestation de paiement (T13,
  TJ7 : verrou caduc depuis B3), textes Stripe (T14a), messages des sept `error_code` IBAN qui arrivent sans `error`
  (T14b, TJ6).
- Non portés, renvoi web libellé : type d'exercice et attestation de cumul d'activité (art. L1222-5,
  `ProfilSoignant.tsx` l.252-256, l.274-278, correction 8).
- (T9, revue B8) Refus d'enregistrement du profil : textes web verbatim d'`extraireMessageErreur`
  (`src/lib/erreurs.ts` l.510, l.511, l.514) pour 23505 et 23514, message serveur verbatim pour `{error}` et P0001
  (`dec_verifier_age_minimum`, `public.sql` l.3893), épinglés par `ProfilVerbatimTests` ; libellés natifs du lot 1
  « Session à vérifier » / « Vérifier ma session » réutilisés tels quels. Aucun texte nouveau, aucun texte juridique.
- **T12 — textes adaptés ou sans équivalent web** (non juridiques, tranchés par délégation : « Décisions déléguées
  du 8 novembre 2026 », « T12 — textes de l'onglet Revenus » ; constantes `RevenusTextes`, épinglées par
  `RevenusPresentationTests.testTextesAdaptesOuSansEquivalentWeb`), un texte par ligne :
  - sous-titre, adapté au vouvoiement de `MesGains.tsx` l.918 : « Vos gains, factures et documents de paie au même endroit »
  - état vide, adapté de l.804 : « Vos gains apparaîtront ici après votre première mission terminée. »
  - totaux indisponibles, adapté de `PageStripeConnect.tsx` l.389 : « Vos revenus sont temporairement indisponibles. »
  - en-tête de la liste (sans équivalent) : « Missions terminées »
  - état d'une mission libérale (sans équivalent) : « Paiement suivi dans Factures »

  Restent verbatim web, tutoiement compris (HARD STOP ; application de la règle 2 de `LOTS_2_5_DECISIONS` et de la
  décision 9 du lot 1, qui ne fait passer au vouvoiement que les textes non juridiques — pas une décision nouvelle) :
  libellés et aides des sept états du paiement rapide et notes « net estimé » (section T12 ci-dessus ; instruits selon
  TJ8 sous « T12 — textes de l'onglet Revenus »).
  (Revue B8, m5) Libellé vocalisé du bouton de ligne `revenus-mission-ouvrir-<id>` : « Voir mission … », `aria-label`
  du web repris tel quel (`RevenusTextes.voirMission`, `MesGains.tsx` l.703) ; aucun texte affiché nouveau.
- Seuls les textes non juridiques passent du tutoiement web au vouvoiement (décision 9 du lot 1).
- **T10 — textes sans équivalent web** (non juridiques, tranchés par délégation : « Décisions déléguées du
  8 novembre 2026 », « T10 — textes natifs sans équivalent web de la photo de profil ») : « Choisir dans la photothèque »,
  « Prendre une photo » (choix de la source de la photo de profil, `AvatarProfil.Textes`) ; « Annuler » repris de
  `ConfirmationSheet.swift` l.34 ; libellé DEBUG démo `profil-avatar-etat` (« photo » / « initiales », jamais en
  Release). Textes web verbatim ou vouvoyés : section T10, épinglés par `AvatarLocalisationVerbatimTests`.
- (T3b) Texte **sans équivalent web**, non juridique, déjà décidé (décision 7 du lot 1, `LOT1_PLAN.md` l.403) et repris
  mot pour mot : « Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application. » (refus d'un lien de
  réinitialisation `?code=`, `DeepLinkIntent.Textes.reinitialisationRefusee`, épinglé par `DeepLinkIntentTests`) ;
  bouton « Fermer » repris de `FiltresSheet.swift` l.64.

## Décisions déléguées du 8 novembre 2026

Mandat : le 8 novembre 2026, Gabrielle a délégué toutes les décisions, juridiques comprises
(« arrête de me demander et prends les décisions, avance seul »). Les points juridiques et les textes du lot 3 jusqu'ici
« En attente de Gabrielle » (section HARD STOP, §6.7, signalement de l'export RGPD) qui ne dépendent d'aucune tranche
hors vague sont instruits et tranchés ci-dessous par la tranche L3-TJ (branche `lot3/l3-tj-v2`, 9 novembre 2026, TJ1 à
TJ5) ; pour les tranches à venir (T8, T12, T13, T14a, T14b), TJ6 à TJ8 fixent la règle qu'elles appliquent. Restent
hors de cette délégation : le go explicite au merge des PR B9 (règle 3 de `LOTS_2_5_DECISIONS`) et ce qui exige la
présence ou les comptes de Gabrielle (appareil, boîte mail, Dashboard, secrets, Apple, Stripe, Sentry), toujours sous
« En attente de Gabrielle ».

Règles appliquées à chaque point (mêmes règles que la section de même titre de `DECISIONS_LOT2.md`) :
- **le natif suit le web mot pour mot** (décision du 9 novembre 2026) : tout texte juridique ou de consentement est
  repris verbatim du web ou du serveur, tutoiement compris, avec sa source (fichier:ligne), et gardé au caractère près.
  Au lot 3, les gardes sont locales (`InscriptionVerbatimTests`, `CompteVerbatimTests`, `ProfilVerbatimTests`) : la
  garde `tests/node/textes-juridiques-ios.node.mjs` de L2-TL vit sur `feat/ios-lot2` ; à la fusion des deux lots, les
  textes du lot 3 y sont ajoutés. Le passage des textes juridiques au vouvoiement se fera d'abord sur le web (PR HARD
  STOP), puis le natif suivra par la garde. Aucun wording juridique n'est inventé par le natif ;
- **force des sources** : TEXTE (loi, règlement : source primaire), JUGÉ (jurisprudence publiée), doctrine (autorité
  administrative, Apple), choix de conformité Jolene (CGU et politique de confidentialité de production dans `src/`,
  règle serveur relue dans `supabase/schema/public.sql`). Textes relus le 9 novembre 2026 : règlement (UE) 2016/679
  (RGPD) en version française sur EUR-Lex, Code civil art. 1119 sur Légifrance. Aucun arrêt ni avis d'autorité n'est
  cité : aucun n'a pu être relu ici ;
- aucune écriture en production ni sur STAGING ; une seule lecture de définition live (`pg_get_functiondef`, TJ4). Les
  corrections hors natif sont consignées comme PR à préparer, hors lot 3.

(Intégration du lot 3, 9 novembre 2026.) Les décisions déléguées des tranches T8 (T8-J1 à T8-J5, écrites dans la
section T8 sur sa branche, comme le prévoit TJ8) et T10 sont regroupées ici, après TJ1 à TJ8, sans changement de
fond ; deux décisions s'y ajoutent à l'intégration : les textes non juridiques de la photo de profil (T10) et
l'instruction, selon TJ8, des textes de l'onglet Revenus (T12, écrite avant TJ8). Une seule section, une ligne de
délégation par décision (garde `tests/node/check-rpc-contracts-lot3.node.mjs`).

### TJ1 — T7 : consentement transmis par `p_cgu`, phrase de consentement et ses liens, refus captcha

- **Phrase de consentement** (T7), validée verbatim : « J’accepte les CGU et la politique de confidentialité. »
  (`src/pages/InscriptionRapide.tsx` l.264-284, fragments l.265, l.272, l.274, l.281, l.283), liens `/cgu` (l.267) et
  `/confidentialite` (l.276) ouverts dans l'app avant l'acceptation ; refus local « Acceptez les conditions pour créer
  votre compte. » (l.68). Relue le 9 novembre 2026 contre le JSX : identique, aucun tutoiement à reprendre ; gardée par
  `InscriptionVerbatimTests` (`testPhraseDeConsentementAssembleeCommeLeJSX`).
- **Consentement transmis par `p_cgu`** (faits, sources primaires du dépôt) :
  - le natif n'envoie `p_cgu` que depuis la case cochée par l'utilisateur, jamais en dur
    (`InscriptionRules.intention(profession:cgu:)`, `SupabaseInscriptionGateway` : `"p_cgu": .bool(intention.cgu)`) ;
    case non cochée → refus local, aucun appel ; même chaîne que le web (`src/lib/inscriptionProgressive.ts` l.33-34,
    l.50-51) ;
  - serveur : `fn_demarrer_inscription` refuse `p_cgu IS NOT TRUE` (22023, `public.sql` l.30161-30163) avant toute
    réservation ; `parcours_inscription.consentement_cgu_le` vaut `now()` à l'insertion (l.71018) ;
    `register-soignant` n'écrit l'audit `RGPD_CONSENTEMENT_DONNE` (`cgu: true, confidentialite: true`,
    `consentement_cgu_le`) que si cette date existe (`supabase/functions/register-soignant/index.ts` l.216-226,
    l.376-387) : la preuve d'acceptation est la même pour une inscription native et une inscription web ;
  - bases juridiques publiées : la création du compte repose sur l'exécution du contrat (`PageConfidentialite.tsx`
    l.62, « article 6.1.b du RGPD »), non sur le consentement.
- **Droit** :
  - TEXTE — Code civil, art. 1119, al. 1 : « Les conditions générales invoquées par une partie n'ont effet à l'égard de
    l'autre » que si elles ont été portées à sa connaissance et acceptées. Case non pré-cochée, acceptation positive,
    pages lisibles avant l'acceptation : conditions remplies, sur les deux surfaces ;
  - TEXTE — RGPD, art. 13, § 1 (information de la personne lors de la collecte) et art. 7, § 2 (un consentement donné
    dans une déclaration écrite qui concerne d'autres questions doit s'en distinguer clairement) : la politique de
    confidentialité est une **information**, et la case ne fonde aucun traitement sur le consentement (art. 6, § 1, b)
    pour le compte). « J’accepte … la politique de confidentialité » vaut prise de connaissance, non consentement au
    sens de l'art. 7 ; le nom d'audit `RGPD_CONSENTEMENT_DONNE` est un choix de nommage Jolene, sans effet pour
    l'utilisateur. Aucun consentement RGPD n'est recueilli ni requis par ce formulaire.
- **Décision** : phrase, liens et chaîne `p_cgu` validés tels quels pour le natif. Observation non bloquante, pour une
  **PR web HARD STOP à préparer hors lot** : distinguer dans la phrase l'acceptation des CGU (contrat) de la prise de
  connaissance de la politique de confidentialité (information), puis le natif suivra par la garde ; aucun texte de
  remplacement n'est écrit ici. Le go B9 du merge de T7 reste à Gabrielle (D18), avec le préalable captcha (§6.11).
- **Refus captcha** (T7), message générique validé :
  « Une erreur inattendue est survenue. Réessayez ou contactez le support. » (`src/lib/erreurs.ts` l.178), suivi du
  renvoi « Créer un compte soignant » vers `/inscription/soignant` (D25, présentateur `.safari`). Non juridique (ni
  règle, ni loi, ni portée contractuelle) : le texte web propre au captcha (« Rafraîchissez la page et réessayez. »,
  l.132-137) n'a pas d'objet dans l'app. Validé.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ2 — T11 : textes RGPD de l'export, refus de réauthentification, « non confirmé », thème

- **Textes RGPD de l'export** (T11) : titre validé verbatim, description du web **non portée** (critère de TJ8).
  - « Mes données (RGPD) » (`src/components/profil-soignant/SectionConfidentialite.tsx` l.111), validé verbatim et
    gardé par `CompteVerbatimTests` ; boutons « Exporter JSON » et « Exporter CSV » (l.123, l.131) et succès
    « Données exportées en JSON. » (gabarit l.73), non juridiques, repris tels quels.
  - « Télécharge l'intégralité de tes données personnelles dans le format de ton choix. » (l.114) : inexacte (ci-dessous),
    **non portée**.
  - Sources : RGPD art. 15, § 3 (copie des données « faisant l'objet d'un traitement ») et art. 20, § 1 (données
    reçues « dans un format structuré, couramment utilisé et lisible par machine » : JSON et CSV conviennent) ;
    politique de confidentialité de production (`PageConfidentialite.tsx` l.196, l.200, l.208-209).
  - « l'intégralité » est inexact au sens strict : l'export omet par construction le numéro de sécurité sociale
    (`public.sql` l.55321), les données de connexion que la politique déclare (§ 2.5, `PageConfidentialite.tsx`
    l.57-58) et, après la PR backend de TJ4, le contenu des notes reçues non encore publiées. RGPD art. 5, § 1, a)
    (données traitées « de manière licite, loyale et transparente ») et art. 12, § 1 (information « d'une façon
    concise, transparente, compréhensible »).
  - **Décision** (corrigée par la revue fraîche B8 de L3-TJ, majeur 2 : la première version maintenait l'affichage
    natif de ce texte, à l'opposé du critère de TJ8 pour le même cas) : un seul critère pour un texte juridique du web
    inexact, le **critère de TJ8** — la description n'est plus affichée en natif tant que la PR web ne l'a pas
    corrigée ; le titre et les boutons sont conservés. Ne pas porter un texte n'est pas le reformuler : aucun texte de
    remplacement n'est écrit. Mise en œuvre : `ExportRGPD.Textes.description` et l'identifiant `compte-export-info`
    retirés (`CompteSections.swift`) ; `CompteVerbatimTests` épingle le titre, l'absence de la description dans les
    sources de l'app et un témoin de l.114 (il rougit quand la PR web corrige la ligne : le nouveau texte est alors
    instruit puis porté verbatim, tutoiement compris) ; `DemoCompteLot3Tests` exige l'absence à l'écran (trois
    formats). **PR web HARD STOP à préparer hors lot** : ne plus promettre « l'intégralité » dans l'export
    libre-service et renvoyer vers la demande formelle de la politique (`support@jolene.app`, réponse sous un mois)
    pour le reste ; à merger avec ou après la PR backend de TJ4.
- **T11 — textes sans équivalent web** (non juridiques), validés par délégation, un texte par ligne :
  - « Ce changement exige une nouvelle vérification de votre identité. Utilisez « Mot de passe oublié ? » pour choisir un nouveau mot de passe. »
    — exact sur le fond : GoTrue exige alors une réauthentification (`reauthentication_needed`), sans flux OTP au
    lot 3 (D13) ; « Mot de passe oublié ? » est le libellé de la connexion web (`src/pages/PageConnexion.tsx` l.345).
    Mais c'est un **renvoi sans effet** dans l'app (revue fraîche B8 de L3-TJ, mineur 2) : la connexion native n'a
    aucun contrôle de ce nom (aucun `login-forgot` dans `ios-native/Jolene` ; reset natif ou renvoi web, reste de
    L1-T10 sans tranche, signalé par T3b). **Accepté jusqu'à L1-T10**, pour trois motifs : (1) le cas est presque
    inaccessible : la vérification de l'ancien mot de passe ouvre une session neuve, et GoTrue n'exige le nonce que
    pour une session de plus de 24 h (section T11) ; (2) le refus est verrouillé et n'annonce rien de faux : le mot de
    passe reste inchangé, aucune action n'est perdue ni supposée ; (3) le libellé nomme le seul chemin qui existe
    aujourd'hui pour choisir un nouveau mot de passe sans réauthentification (connexion web) : un texte de
    remplacement n'offrirait aucune action de plus. Différence avec le message de verrou de T13 écarté par TJ7 :
    celui-là répondait à un état disparu (B3 mergé) et renvoyait vers « Contacter Jolene », modale sans équivalent
    natif, sur un parcours courant ; celui-ci répond à un refus réel du serveur, rare. **Préalable du §6.10**
    (TestFlight externe ; verrou « un gap connu reste verrouillé », gardé par `CompteVerbatimTests` et la garde Node
    du lot 3 tant que `login-forgot` manque) : la connexion native porte « Mot de passe oublié ? ».
  - « Le changement de votre mot de passe n'a pas pu être confirmé. Vérifiez votre connexion puis réessayez. »
    — exact : issue inconnue après un délai ou une coupure (PRINCIPES §3-§4), jamais un succès.
  - « Thème », « Système », « Clair », « Sombre » (D16) — termes de réglage d'iOS, sans portée juridique.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ3 — Pages `/cgu` et `/confidentialite` de l'inscription en démo (feuille locale)

- **Constat** (intégration de T3b, T7 et T11) : la phrase de consentement ouvre ses pages par une feuille locale du
  formulaire (le formulaire est lui-même une feuille dans l'aiguillage d'onboarding, la racine ne peut pas présenter
  par-dessus) ; cette feuille chargeait la vraie page dans `SFSafariViewController` **en démo aussi**, alors que tout
  renvoi web de la démo (pages légales du hub comprises) passe par le double sans réseau du coordinateur.
- **Sources** : choix de conformité Jolene — mode démo sans aucune requête réseau (`DECISIONS_LOT0.md`, mode démo ;
  PRINCIPES §7, niveau 2) ; le mode démo n'existe qu'en DEBUG (`JoleneEnvironment.load`, surcharges ignorées en
  Release) : un build de production ouvre toujours la vraie page, lisible avant l'acceptation (Code civil art. 1119,
  TJ1). Rien de juridique ne change pour un utilisateur réel.
- **Décision et mise en œuvre** (simple, appliquée par cette tranche) : en démo, la feuille locale montre le même double
  que le coordinateur (`renvoi-web-demo`, URL canonique `renvoi-web-url`, « Fermer » `renvoi-web-fermer`) ; en staging
  et production, toujours `SFSafariViewController`, désormais configuré comme le renvoi du coordinateur (lecteur
  désactivé, bouton « Fermer », fin relayée par son délégué). Vue `PageWebLocale`
  (`Jolene/Composition/DeepLinkCoordinator.swift`),
  valeur d'environnement `presentationPageWeb` posée à la racine par `PointDEntreeLiens` depuis
  `DeepLinkCoordinator.estDemo` (`PresentateurRenvoiWeb.swift`), consommée par `InscriptionRapideScreen` ; l'ancienne
  `PageWebSafari` privée est retirée. Preuve niveau 2 (trois formats, compilée, non lancée localement) :
  `DemoInscriptionTests.testLienCGUDuConsentementOuvreLeDoubleDemoSansReseau` (lien « CGU » → double sur
  `https://jolene.app/cgu` → « Fermer » → formulaire rendu tel quel, consentement non coché), hors session ; et,
  ajouté après la revue fraîche B8 de L3-TJ (mineur 4), le cas qui motive cette décision :
  `DemoInscriptionTests.testLienCGUDepuisLAiguillageSessionOuverteOuvreLeDoubleDemoSansReseau` (session ouverte,
  formulaire « Je suis soignant » présenté en feuille par `OnboardingRootView`, page « CGU » en feuille dans cette
  feuille). Ce cas devient atteignable en démo par un second lien de confirmation démo,
  `token_hash=demo-sans-intention` (`DemoInscriptionGateway.tokenHashSansIntention`, compte confirmé sans intention
  d'inscription ni parcours → « Choisissez votre espace… » ; `DemoInscriptionGatewayTests`). Les deux XCUITest
  tournent dans l'éclat « lot3-inscription » de `ios-swift-ci.yml`, créé par cette correction (« lot3-compte » durait
  19,1 min sur ipad-landscape au run 42549855710, seuil de 20 min, décision 22 de `DECISIONS_LOT2.md`).
  **Condition de clôture** : CI UI verte sur les trois formats (iphone, ipad-portrait, ipad-landscape), cinq éclats
  verts, ces deux XCUITest démarrés — à constater par l'intégrateur (`workflow_dispatch` de `ios-swift-ci.yml`).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ4 — Export RGPD : notes reçues non publiées (double-aveugle D8)

- **Constat** (définition live relue en lecture seule le 9 novembre 2026 par `pg_get_functiondef`, comme T0 et T11 :
  clé `notations_recues` toujours filtrée `note_id = v_uid AND masque = false`, sans `publie_le`, corps identique au
  dump `public.sql` l.55349) : `fn_rgpd_exporter_donnees_soignant` (l.55300-55364), appelée par
  `fn_rgpd_exporter_rate_limited` (l.55388) — export du hub natif (T11) comme de `SectionConfidentialite.tsx` —, met
  dans le fichier les critères et le commentaire d'une note reçue **avant sa publication**.
- **Double-aveugle D8** (choix de conformité Jolene,
  `supabase/migrations/20260709230000_lot15_d8_double_aveugle_score_etab.sql` l.1-17 ; motif écrit : sans
  publication différée, « représailles possibles », l.5-6) : une note part non publiée
  (`publie_le` NULL) ; publication simultanée des deux notes dès que les deux sens existent (`fn_creer_notation_mission`,
  `public.sql` l.27445-27455), sinon par `fn_publier_notations_echues` (l.51281-51296) après `notation_publication_jours`
  jours (défaut 7, migration l.24 ; cron quotidien `jolene_publier_notations_j7` à 05:30 UTC, l.398-399), soit au plus
  huit jours. Source unique de visibilité : vue `evaluations_publiees` (l.69564-69584, `publie_le IS NOT NULL AND masque =
  false`) et RLS `pol_notations_select` (l.79426) ; le soignant ne lit pas cette note par l'API, seul l'export la livre
  (principe « Publication différée » de `CLAUDE.md`).
- **Droit** (TEXTE, RGPD relu sur EUR-Lex le 9 novembre 2026) :
  - art. 4, 1) et art. 15, § 1 et § 3 : une note reçue sur sa prestation est une information se rapportant au soignant ;
    il a droit à la confirmation de son traitement et à une copie des données « faisant l'objet d'un traitement » ;
  - art. 15, § 4 : le droit d'obtenir une copie « ne porte pas atteinte aux droits et libertés d'autrui » ; considérant
    63 : ces considérations « ne devraient pas aboutir à refuser toute communication d'informations à la personne
    concernée » ;
  - art. 12, § 3 et considérant 59 : réponse « dans un délai d'un mois à compter de la réception de la demande »,
    prolongeable de deux mois ;
  - art. 23, § 1 : une limitation de la portée des droits (point i) : protection des droits et libertés d'autrui) exige
    une mesure **législative** de l'Union ou d'un État membre ; base non mobilisable par Jolene seule, et non invoquée :
    la décision ne limite pas le droit d'accès, elle fixe le moment de la communication, dans le délai de l'art. 12 ;
  - politique de confidentialité de production : droit d'accès et copie (`PageConfidentialite.tsx` l.196), portabilité
    JSON ou CSV (l.200), demande à `support@jolene.app` et réponse sous un mois (l.208-209) : le canal formel du droit
    d'accès reste ouvert et complet.
- **Arbitrage** :
  - « exporter les notes non publiées » rend le double-aveugle inopérant pour qui exporte : la note de l'autre partie,
    lue avant de noter soi-même, rouvre les représailles que D8 interdit, et contredit la source unique de visibilité ;
  - « les différer jusqu'à publication » protège l'autre partie (art. 15, § 4) sans refuser l'information (considérant
    63) : la note est publiée au plus huit jours après sa création, bien avant le mois de l'art. 12, § 3.
- **Décision** : **différer jusqu'à publication**, à deux conditions :
  1. l'export confirme l'existence de chaque note reçue non publiée, **sans son contenu** (mission, sens, date de
     création, date **au plus tôt** de la publication automatique) — art. 15, § 1 et considérant 63 ; la date permet
     un nouvel export une fois la note publiée, et une demande formelle (`support@jolene.app`) reste servie sous un
     mois, note publiée comprise ;
  2. le report ne dépasse jamais un mois : une note non publiée créée depuis plus d'un mois est exportée en entier,
     quelle que soit la valeur de `notation_publication_jours` (verrou « un gap connu reste verrouillé » : un paramètre
     relevé au-delà d'un mois ne peut pas allonger le report au-delà du délai de l'art. 12, § 3).
- **PR backend à préparer hors lot** (rien n'est écrit par cette tranche, règle 3 ; catégorie **B9** : redéfinition
  d'une fonction `SECURITY DEFINER` et texte RGPD → go explicite de Gabrielle au merge) :
  `supabase/migrations/<horodatage du jour>_export_rgpd_notes_publiees.sql`, `CREATE OR REPLACE FUNCTION
  public.fn_rgpd_exporter_donnees_soignant` **depuis la définition live** (`scripts/dump-live-def.sh fonction
  fn_rgpd_exporter_donnees_soignant`, garde-fou 9.0 n°2), ACL conservées ; seules modifications, dans le
  `jsonb_build_object` (clé `notations_recues` remplacée, clé suivante ajoutée, version d'audit `p_details` relevée) :

  ```sql
  'notations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'sens',sens,'critere_1',critere_1,'critere_2',critere_2,'critere_3',critere_3,'critere_4',critere_4,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb)
    FROM notations_missions WHERE note_id = v_uid AND masque = false
      AND (publie_le IS NOT NULL OR cree_le <= NOW() - interval '1 month')),
  'notations_recues_en_attente_de_publication', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'sens',sens,'cree_le',cree_le,
      'publication_automatique_au_plus_tot_le', cree_le + make_interval(days => public.fn_param_num('notation_publication_jours', 7)::int)) ORDER BY cree_le DESC), '[]'::jsonb)
    FROM notations_missions WHERE note_id = v_uid AND masque = false
      AND publie_le IS NULL AND cree_le > NOW() - interval '1 month'),
  ```

  `publication_automatique_au_plus_tot_le` est une date **au plus tôt** (revue fraîche B8 de L3-TJ, mineur 5 ; la
  première version nommait la clé `publication_automatique_le`) : `fn_publier_notations_echues` ne publie que si
  `cree_le + N jours < NOW()` (`public.sql` l.51292, définition live relue en lecture seule le 9 novembre 2026), au
  premier passage du cron quotidien `jolene_publier_notations_j7` (05:30 UTC) qui suit cette date, soit jusqu'à 24 h
  plus tard : le soignant qui réexporte à cette date peut encore trouver la note en attente. La PR backend garde ce
  nom de clé et le documente dans la fiche `fn_rgpd_exporter_rate_limited`.

  Tests de la PR : test SQL de régression transactionnel (une note reçue non publiée → présente dans
  `notations_recues_en_attente_de_publication` sans critère ni commentaire, absente de `notations_recues` ; après la note
  réciproque → dans `notations_recues` ; une note non publiée de plus d'un mois → dans `notations_recues`),
  `test:regression` et `guards` (B7) ; contrat : liste des clés de `scripts/mobile/export-demo-fixtures.mjs`
  (l.348-350) et `demo-export-rgpd.json` (33 clés), fiche `fn_rgpd_exporter_rate_limited` de
  `CONTRATS_RPC_SOIGNANT.md` ; `ExportRGPDTests` inchangés (aplatissement générique). Audit des quatre étages
  (`CLAUDE.md`) : `fn_exporter_rgpd_etablissement` (`public.sql` l.36254) ne lit pas `notations_missions` (vérifié dans
  le dump). **Second lecteur à visibilité conditionnelle** (omis par la première version de cet audit, revue fraîche
  B8 de L3-TJ, mineur 1) : la clé `evaluations_recues` du même export (`public.sql` l.55334) lit la table legacy
  `evaluations` sans filtre `visible`, alors que la RLS `pol_eval_select` (l.79230) n'ouvre au soignant noté que
  `visible = true` ; confirmé sur la définition live (lecture seule, `pg_get_functiondef` et `pg_policy`, 9 novembre
  2026). Table vide en production selon la revue : défaut **latent**, instruit par la même PR (observation
  ci-dessous), avec un test-garde qui énumère les lecteurs d'export (principe « Publication différée » de `CLAUDE.md`).
- **Observation hors arbitrage** (à instruire dans la même PR, non tranchée ici) : les notes masquées par la
  modération (`masque = true`) sont absentes de l'export depuis l'origine ; elles restent des données du soignant
  (art. 15, § 1). À l'inverse, `evaluations_recues` exporte les évaluations legacy non visibles (`visible = false`)
  que la RLS cache au soignant noté. La PR backend instruit les deux lecteurs ensemble, avec une seule règle (contenu
  masqué ou non, existence confirmée), jamais deux règles divergentes pour une même visibilité.
- **Natif** : aucun changement (l'écran transmet le fichier du serveur sans en rien afficher) ; il suit le contrat par
  `export-demo-fixtures.mjs`.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ5 — Textes natifs sans équivalent web des tranches T1b, T4, T5 et T9 (non juridiques)

- **Critère** (`CLAUDE.md`, HARD STOP n°4) : aucun de ces textes ne restreint un mode d'exercice, ne cite une loi ni
  n'a de portée contractuelle ; chacun décrit exactement l'action ou l'état de l'écran, au vouvoiement (décision 9 du
  lot 1), et reste épinglé par son test.
- Textes **sans équivalent web** (non juridiques), validés par délégation : « Ouvrir les réglages » (T4, carte
  « Autorisation du téléphone », nommé au §1.1 du blueprint, `EtatNotificationsAppareil.ouvrirReglages`,
  `EtatNotificationsAppareilTests`) ; « Le type d'exercice se modifie sur jolene.app. » et
  « Votre profil n'a pas pu être enregistré. Réessayez. » (T9, `ProfilEdition.Textes.typeExerciceWeb` et
  `.enregistrementEchec`) ; « Voir sur jolene.app » (bouton `profil-exercice-web-action`,
  `ProfilEdition.Textes.voirSurLeWeb`), épinglés par `ProfilVerbatimTests`.
- Textes d'accessibilité **sans équivalent web** (vocalisés seulement, jamais affichés), validés par délégation :
  « environ » et « Montant indisponible » (`AmountRow`, L3-T1b), « critère rempli » et « critère non rempli »
  (`PasswordCriteriaList`, L3-T1b), « Ouvre le centre de notifications » (indication de « Voir » sur le compteur de
  l'Accueil, L3-T5, `CentreNotificationsTextes.indicationOuvrirCentre`, `CentreNotificationsTests`).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ6 — Règle pour T14b : messages des sept `error_code` IBAN qui arrivent sans `error`

- **Faits** (`public.sql`, dump du 01/11/2026) : `fn_enregistrer_mon_iban` (l.32300-32357) rend `NON_AUTHENTIFIE`
  (l.32313) et `PROFIL_INTROUVABLE` (l.32319) sans `error`, puis `TITULAIRE_NON_CONCORDANT` et `RIB_VERIFIE_REQUIS`
  avec un `error` serveur (l.32333-32337, l.32348-32352) ; `fn_lier_iban_verifie_document` (l.39451-39569) rend sans
  `error` `IBAN_INVALIDE` (l.39470), `RIB_COURANT_REQUIS` (l.39482), `IDENTITE_VERIFIEE_REQUISE` (l.39492),
  `IDENTITE_COURANTE_REQUISE` (l.39510) et `RIB_NON_CONCORDANT` (l.39526).
- **Règle** (non juridique : aucun de ces refus n'énonce une règle de droit ; ce sont des conditions techniques du
  serveur) :
  1. un `error` serveur présent est affiché verbatim, toujours ;
  2. aucun texte nouveau quand un texte existe : `NON_AUTHENTIFIE` → parcours de session du lot 1 (« Session à
     vérifier », « Vérifier ma session ») ; `PROFIL_INTROUVABLE` → erreur de contrat, message générique web
     « Une erreur est survenue. Veuillez réessayer. » (`src/lib/erreurs.ts` l.532) ; `IBAN_INVALIDE` → « IBAN
     invalide » (`src/components/profil-soignant/SectionPaiements.tsx` l.339) ;
     `RIB_COURANT_REQUIS` et `RIB_NON_CONCORDANT` → texte serveur verbatim du refus voisin `RIB_VERIFIE_REQUIS`,
     « Téléversez puis faites vérifier le RIB correspondant. » (`public.sql` l.32351, déjà au vouvoiement), sous le
     titre « RIB vérifié requis » (l.306), avec l'action « Téléverser mon RIB » (l.316 : documents du lot 2 ou renvoi
     web) ; exact dans les deux cas : RIB vérifié retiré entre la lecture et la liaison (`RIB_COURANT_REQUIS`,
     l.39482), RIB vérifié qui ne porte pas cet IBAN ou dont les noms ne concordent pas (`RIB_NON_CONCORDANT`,
     l.39526) ;
  3. textes nouveaux pour `IDENTITE_VERIFIEE_REQUISE` et `IDENTITE_COURANTE_REQUISE` seulement : vouvoiement, une phrase
     qui dit la seule condition vérifiée par le serveur (identité vérifiée et cohérente ; pièce d'identité vérifiée
     dont les noms concordent) et l'action disponible dans l'app ou sur le web, jamais une règle que le serveur
     n'applique pas, jamais un chiffre de l'IBAN, jamais « IBAN enregistré » ;
  4. chaque message est une constante épinglée par un test (code → message) et listée dans la section de T14b de ce
     mémo, avec sa ligne de délégation : aucune relecture de Gabrielle n'est plus requise.
- **Texte de l.308 non retenu pour un refus** (revue fraîche B8 de L3-TJ, majeur 1 : la première version de la règle 2
  le donnait à `RIB_COURANT_REQUIS` et `RIB_NON_CONCORDANT`) : « L'ancien IBAN est conservé dans ton historique, mais
  aucun nouveau versement ne peut l'utiliser sans un RIB courant vérifié… » décrit l'état web
  `iban_renseigne && !iban_verifie` (`SectionPaiements.tsx` l.302), pas un refus. Après un refus, il serait faux dans
  les deux cas courants : premier IBAN (il n'y a pas d'« ancien IBAN ») ; IBAN déjà vérifié (chaque refus de
  `fn_lier_iban_verifie_document`, `RIB_NON_CONCORDANT` l.39526 compris, sort avant l'UPDATE de l.39533 : l'IBAN en
  place reste valable et sert toujours aux versements). Le reprendre contredirait la règle 3 et TJ8. Si T14b affiche
  l'état `iban_renseigne && !iban_verifie`, elle instruit ce texte pour cet état, contre `fn_consulter_mon_iban`, avant
  de le porter.
- **Texte web à ne pas porter** : « Ton IBAN est utilisé pour le versement de tes primes de parrainage. Il n'est jamais
  partagé avec l'établissement. » (`SectionPaiements.tsx` l.280). Information sur les destinataires (RGPD art. 13, § 1),
  inexacte : l'IBAN enregistré est celui du RIB vérifié (`fn_lier_iban_verifie_document`, l.39533-39534 :
  `SET iban_virement = v_iban`), et ce RIB est remis à l'établissement de la mission quand un partage est actif
  (`fn_consulter_rib_soignant_internal_20260801`, l.25619-25686, table `partages_rib`). T14b ne l'affiche pas ; **PR web
  HARD STOP à préparer hors lot** pour le corriger, le natif suivra par la garde.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ7 — Règle pour T13 : contestation d'un paiement déclaré

- **Le verrou est caduc** : B3 est sur `main` (#1118) et dans `feat/ios-lot3` ; la fiche
  `fn_contester_paiement_soignant` de `CONTRATS_RPC_SOIGNANT.md` décrit le contrat d'après B3 (huit `error_code`,
  idempotence, `LITIGE_DEJA_OUVERT`). Le message de verrou proposé par le blueprint (« La contestation d'un paiement est
  momentanément indisponible. Contactez Jolene depuis Mon compte › Contacter Jolene. ») **n'est pas retenu** : il ne
  répond plus à rien et renvoie vers « Contacter Jolene », modale web sans équivalent natif (jamais un renvoi sans
  effet).
- **Règle** : T13 relit d'abord la définition live de `fn_contester_paiement_soignant` (lecture seule) ; conforme à la
  fiche, « Contester » est ouvert dans sa PR (B9, go au merge) ; refus serveur `error` verbatim ; libellés web
  verbatim (`src/components/BandeauPaiementDeclare.tsx` : « Motif de contestation : » l.51, « Envoyer la contestation »
  l.62, « Annuler » l.64, « Confirmer la réception » l.397, « Contester » l.407) ; l'indication tutoyée « Décris pourquoi
  tu contestes ce paiement... » (l.55, non juridique) passe au vouvoiement (décision 9 du lot 1) ; le motif de repli du
  web `'Contesté par le soignant'` (l.61, l.190) n'est jamais envoyé (bouton inactif sans motif, refus serveur
  `MOTIF_INVALIDE`) ; « Paiement confirmé » ou « Contestation envoyée » seulement après relecture du statut. Le natif
  n'ajoute aucun texte sur la portée juridique d'une confirmation ou d'une contestation (ni renonciation, ni délai).
  Si la définition live diffère de la fiche, T13 garde « Contester » fermé sans texte nouveau et consigne l'écart.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### TJ8 — Règle pour les tranches hors vague (T8, T12, T13, T14a, T14b) : textes juridiques

- Chaque tranche instruit et tranche elle-même ses textes juridiques, par la même délégation, dans une sous-section de
  sa section de ce mémo, avec ses sources (fichier:ligne, texte de loi relu, force de la source) et la ligne de
  délégation, comme T4b, T5a et T9b au lot 2 ; aucun texte n'attend plus la relecture de Gabrielle.
- Texte juridique : verbatim web, tutoiement compris, gardé au caractère près ; texte non juridique : vouvoiement.
- **Critère unique pour un texte juridique du web inexact** (précisé après la revue fraîche B8 de L3-TJ, majeur 2) :
  un texte juridique du web **inexact** au regard du serveur ou des textes n'est **pas porté** — ni affiché, ni
  reformulé : ne pas porter un texte n'est pas le reformuler. L'écran garde ses titres et ses actions ; une PR web
  HARD STOP est à préparer, et le natif portera verbatim le texte corrigé, par sa garde (témoin de la ligne web qui
  rougit quand elle change). Aucune exception selon la nature de l'inexactitude : séparer une exhaustivité exagérée
  d'une affirmation fausse exigerait une doctrine que ce mémo ne peut pas sourcer, et RGPD art. 5, § 1, a) et
  art. 12, § 1 s'appliquent aux deux. Appliqué à l.280 de `SectionPaiements.tsx` (destinataires de l'IBAN, TJ6) comme
  à la description de l'export (« l'intégralité », TJ2) ; les tranches T8, T12, T13, T14a et T14b l'appliquent tel
  quel.
- Points à instruire, déjà repérés :
  - T8 : avertissement d'exclusivité (`src/pages/InscriptionSoignant.tsx` l.77, l.84) et libellés des modes
    d'exercice (`src/components/ChoixModesExercice.tsx`, lignes du blueprint §3 T8) : aucune règle de mode d'exercice
    en dur, matrice profession × mode lue au serveur (`fn_types_exercice_autorises`) ;
  - T12 : libellés escrow (`src/components/gains/PaiementsEscrowAVenir.tsx` l.44-80, invariant « jamais garanti ») et
    note « net estimé » (`src/lib/missionFinanceDisplay.ts`), relus contre le glossaire escrow de `CLAUDE.md`
    (honoraires figés à la confirmation, plancher ; « ne STATIONNENT jamais », jamais « ne transitent jamais ») ;
  - T14a : textes Stripe (`src/pages/PageStripeConnect.tsx` l.300-520, dont « Aucun frais pour le soignant » l.335, et
    `SectionPaiements.tsx` l.16-139), relus contre la définition live d'`escrow-debit-echeance` (commission en
    `application_fee_amount`, `docs/flux-monetaire-escrow.md`) ;
  - T13 et T14b : TJ7 et TJ6.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T8-J1 — Modes d'exercice de la complétion quand le référentiel est inconnu

- **Question** : blueprint v2 (§2.4, §3 T8) : « `LIBERAL` retiré tant que non confirmé (l.192-199) » ; le web actuel ne
  retire le libéral que si le référentiel est **connu** et ne le propose pas, le **conserve** pendant le chargement ou
  une indisponibilité (sans permettre de l'ajouter) et l'écrit : « Vos choix sont conservés ; l’ajout du libéral
  nécessite une vérification. ».
- **Sources** : `src/pages/InscriptionSoignant.tsx` l.187-199 (code du retrait) ; `src/components/ChoixModesExercice.tsx`
  l.12 (« Préférences de recherche uniquement : ne modifie pas le statut d’exercice déclaré »), l.15-16, l.29, l.43 ;
  `supabase/schema/public.sql`, `dec_verifier_type_exercice_profession` (le serveur contrôle `soignants.type_exercice`
  contre `regles_exercice_profession`, pas `types_contrat_acceptes`) ; `supabase/migrations/20260714084802_synchroniser_regles_profil_exercice.sql`
  (en-tête : « La décision d'une mission reste exclusivement fondée sur missions.profession_requise via
  fn_mode_exercice ») ; `supabase/functions/register-soignant/index.ts` l.296-298.
- **Force** : choix de conformité Jolene (ni JUGÉ ni doctrine) : la matrice des modes est une table paramétrée
  (`CLAUDE.md`, HARD STOP n°4 : « zéro règle juridique en dur »).
- **Décision** : le natif suit le web actuel (décision du 9 novembre : le natif suit le web mot pour mot ; même
  comportement que l'édition du profil, T9) : libéral retiré quand le référentiel connu ne le propose pas, conservé tant
  qu'il est inconnu, jamais ajoutable sans confirmation (option masquée). Motif : les modes cochés sont une préférence de
  recherche, pas le statut d'exercice déclaré, et chaque mission applique sa propre règle (`fn_mode_exercice`) ; retirer
  un choix conservé contredirait le texte verbatim affiché. Le blueprint décrivait le web de façon inexacte ; écart
  consigné ici et testé (`CompletionProfilRulesTests.testModesApresLeReferentiel`,
  `CompletionProfilModelTests.testReferentielIndisponibleConserveLesChoixSansAjoutDuLiberalPuisReessai`).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T8-J2 — Avertissement d'exclusivité et question « salarié(e) »

- **Question** : afficher à la complétion la question « Êtes-vous actuellement salarié(e) d'un établissement de
  santé ? » et l'avertissement « Vérifiez que votre contrat de travail n'inclut pas de clause d'exclusivité. ».
- **Sources** : `src/pages/InscriptionSoignant.tsx` l.75-86 (texte), l.134 (état du formulaire) ;
  `src/lib/inscriptionProgressive.ts` l.152-167 (`donneesFormulaire` : la réponse est enregistrée dans le brouillon),
  l.135-138 (`restaurerFormulaire` : restaurée), l.179-192 (non transmise à `register-soignant`, correction 21) ;
  liste blanche serveur `public.sql` l.32487.
- **Force** : choix de conformité Jolene (information de l'utilisateur, aucune règle ni aucun texte de loi cité).
- **Décision** : affichage verbatim du web ; réponse enregistrée dans le brouillon et restaurée comme le web, jamais
  transmise à `register-soignant` ; aucun ajout ni aucune reformulation (pas de citation d'article, pas de conséquence
  juridique annoncée). (Corrigé le 09/11/2026, revue B8 de T8, m4 : la première rédaction disait la réponse « ni
  enregistrée dans le brouillon », ce qui décrivait le web de façon inexacte.)
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T8-J3 — Libellés des modes et phrase du type d'exercice unique

- **Question** : afficher « Salarié (CDD compris) », « Libéral », « Modes d’exercice recherchés » et, pour une profession à
  type unique (ex. aide-soignant, salarié uniquement d'après le seed), « En tant que <profession>, votre type d'exercice
  est automatiquement défini comme salarié. ».
- **Sources** : `src/components/ChoixModesExercice.tsx` l.20-27 ; `src/pages/InscriptionSoignant.tsx` l.62-71 ;
  `src/hooks/useTypesExerciceAutorises.ts` l.57 (`uniqueType`) ; seed `20260714084802` (types par profession).
- **Force** : choix de conformité Jolene (table paramétrée `regles_exercice_profession`).
- **Décision** : textes verbatim, assemblés comme le JSX ; le type affiché vient exclusivement de
  `fn_types_exercice_autorises` (aucune règle en dur), jamais d'un défaut de l'app.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T8-J4 — Âge minimum et RPPS à l'inscription

- **Question** : gardes locales de l'âge (18 ans) et de l'obligation du RPPS avant l'envoi.
- **Sources** : `supabase/functions/register-soignant/index.ts` l.243-254 (`UNDERAGE`, contrôle serveur, message
  verbatim), l.255-271 (`PROFESSIONS_RPPS_REQUIS`) ; `src/lib/constantes.ts` l.55, l.61 ; `src/pages/InscriptionSoignant.tsx`
  l.201-233, l.554 ; `CLAUDE.md`, « Pièges vérification documents » (AS/AES : CNI et diplôme, ni RPPS ni RCP, ni KBIS
  ni casier).
- **Force** : règles serveur existantes, reprises sans changement (aucune règle nouvelle).
- **Décision** : le natif reprend la garde du formulaire web (18 × 365,25 jours, borne du sélecteur, RPPS obligatoire pour
  médecin, chirurgien-dentiste, sage-femme et pharmacien, optionnel pour les autres professions à RPPS et pour l'AS,
  masqué pour AES et auxiliaire de puériculture avec le texte web « Aucun RPPS n'est demandé pour ce profil. Votre
  diplôme et votre carte d'identité restent vérifiés avant toute mission. ») ; le serveur reste seul juge (`UNDERAGE`,
  `RPPS_*` affichés verbatim). Aucun document n'est demandé à la complétion (comme le web : les documents se déposent
  ensuite, lot 2).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T8-J5 — Parcours étudiant

- **Question** : porter la déclaration « étudiant(e) en santé » (pré-éligibilité à un emploi temporaire) ou la renvoyer au
  web.
- **Sources** : `src/components/inscription/DeclarationEtudiant.tsx` l.5-40, l.105-108 (conditions réglementaires par
  formation, mention d'un arrêté que l'auteur n'a pas relu dans sa version officielle) ; D11 (`DECISIONS_LOT3.md`).
- **Force** : choix de conformité Jolene.
- **Décision** : renvoi web (bouton « 🎓 Je suis étudiant(e) en santé », verbatim l.105, vers `/inscription/completer`
  par le présentateur `.safari`) ; aucune condition ni aucune référence réglementaire n'est affichée en natif.
  (Complété le 09/11/2026, revue B8 de T8, B1) Un brouillon déjà déclaré étudiant sur le web (`estEtudiant: true`) n'est
  jamais finalisé en natif : seul ce renvoi est proposé, `register-soignant` n'est pas appelée (elle écrirait
  `est_etudiant = false`, index.ts l.309) ; le rôle est relu au retour. Option retenue : verrou plutôt que transmission
  de `est_etudiant` / `etudiant_details` sans affichage ni modification possible de la déclaration (détail dans la
  section « T8 — corrections de la revue fraîche B8 »). Force : choix de conformité Jolene (D11).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T10 — coordonnées du profil transmises au géocodage inverse (`api-adresse.data.gouv.fr`)

- **Question.** « Utiliser ma position actuelle » envoie la latitude et la longitude de l'appareil (avec son adresse
  IP, inhérente à toute requête) au service public `api-adresse.data.gouv.fr`, hors Supabase. Faut-il bloquer ou
  différer ce flux dans le natif tant que la politique de confidentialité ne nomme pas ce destinataire ?
- **Faits du dépôt.** Le web fait exactement cet envoi depuis l'écran profil (`src/lib/geocodage.ts` l.16-19, appelé
  par `SectionProfilPrincipal.tsx` l.628-632) ; le natif le reproduit sans rien y ajouter (aucun identifiant, aucun
  jeton, aucun cookie : `ApiAdresseGeocodage`, `ApiAdresseGeocodageTests`). La politique de confidentialité
  (`src/pages/PageConfidentialite.tsx`) annonce la « localisation volontaire du profil » (§2.3, l.51) et sa base
  juridique (§2.6, l.65), mais son tableau des sous-traitants (§3.2, l.92-108) ne nomme pas ce service.
- **Sources primaires (vérifiées sur le texte publié du règlement (UE) 2016/679, EUR-Lex, CELEX 32016R0679, le
  09/11/2026).** Art. 4, point 1 : une personne est identifiable notamment « par référence à un identifiant, tel
  qu'un nom, un numéro d'identification, des données de localisation, un identifiant en ligne » — les coordonnées de
  l'appareil sont des données personnelles. Art. 4, point 9 : le « destinataire » est « la personne physique ou
  morale, l'autorité publique, le service ou tout autre organisme qui reçoit communication de données à caractère
  personnel, qu'il s'agisse ou non d'un tiers ». Art. 13, paragraphe 1, point e) : la personne concernée est informée
  des « destinataires ou les catégories de destinataires des données à caractère personnel, s'ils existent ».
- **Force des sources.** Texte du règlement (droit positif). Aucune jurisprudence ni doctrine citée : aucune n'a été
  vérifiée pour ce cas. La qualification du service (sous-traitant au sens de l'art. 4, point 8, ou destinataire
  responsable de son propre traitement) n'est pas tranchée ici : dans les deux cas, l'art. 13 impose d'informer du
  destinataire, et le tableau §3.2 ne le fait pas.
- **Décision (choix de conformité Jolene).** Le natif livre le géocodage à l'identique du web (D15), sans blocage :
  même flux, même minimisation (coordonnées seules, à l'appui explicite de l'utilisateur, jamais en tâche de fond,
  aucune conservation côté app), et aucun texte juridique nouveau dans l'app (la politique est une page web, servie
  par le renvoi web du hub). La lacune d'information est une lacune du **texte web** existant, commune aux deux
  surfaces : elle se corrige sur le web d'abord (ajout du service d'adresse de l'État parmi les destinataires du
  §3.2 de `PageConfidentialite.tsx`), puis le natif suit par la garde des textes — PR web séparée, hors de cette
  tranche (légal exposé, B9 : préparée sans merge). Ne pas différer le natif ne crée aucun flux nouveau : différer
  seulement le natif laisserait le web inchangé et n'améliorerait pas l'information des personnes.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T10 — localisation du profil livrée sans le port du lot 2 (écart au blueprint v2 §3 T10)

- **Question.** Le blueprint v2 (`LOT3_PLAN.md` §3 T10, §2.2 et « Dépendances ») prévoit la position du profil par
  `Appareil.location` du lot 2 **seulement** (« pas de `OneShotLocation.swift` : si L2-T1 n'est pas sur `main`,
  `profil-localiser` est absent et la localisation glisse dans une PR T10b après L2-T1 »). L2-T1 n'est pas sur la base
  du lot 3, et la consigne de l'orchestrateur du lot 3 interdit d'en dépendre (« Le lot 2 (pointage, justificatifs,
  contrats) vit sur feat/ios-lot2, pas ici : n'en dépends pas. », tâche de T10 et de sa correction du 09/11/2026).
  Fallait-il retirer « Utiliser ma position actuelle » de T10 (T10b plus tard) ou la livrer par un port provisoire ?
- **Faits.** Le web propose la localisation du profil (`SectionProfilPrincipal.tsx` l.625-643, l.871) ; aucun flux
  nouveau côté natif (mêmes coordonnées, même service, sur appui seulement : décision précédente). Le port du lot 2
  (`LocationPort`, `Appareil.localisation`, `LocationService`) existe sur `feat/ios-lot2` ; sa forme est connue
  (`autorisation()`, `demanderAutorisation()`, `positionUnique(delai:) -> ObservationGps`).
- **Force.** Choix d'architecture Jolene (aucune source juridique) qui déroge au blueprint v2, lequel fait foi sauf
  décision contraire (`LOTS_2_5_DECISIONS.md`).
- **Décision.** Livrer la localisation du profil dans T10 par un port MINIMAL (`LocalisationPort.localiser(delai:)`,
  JoleneCore) et une implémentation ISOLÉE (`LocalisationProfilProvisoire`, seule utilisatrice de CoreLocation de la
  cible app, injectée dans le seul écran du profil), remplacées à la fusion par un adaptateur sur
  `Appareil.localisation` (correspondance des issues : section T10, « Manques et points de fusion », point 1). Écart
  borné et verrouillé (principe « un gap connu reste verrouillé ») : `FusionLocalisationLot2Tests` échoue dès que
  `LocationPort` du lot 2 arrive dans JoleneCore alors que l'implémentation provisoire existe encore, et, avant la
  fusion, si une autre source de la cible app importe CoreLocation ; PRINCIPES §2 nomme l'exception. Raisons : parité
  web livrée aux soignants sans attendre la fusion ; coût de fusion d'un fichier supprimé et d'un adaptateur de
  quelques lignes ; oubli rendu impossible par la garde.
- **Règle de la précision réduite, tranchée avant la fusion.** Position approximative seule accordée (« Position
  exacte » coupée) → `.precisionReduite` → `.indisponible` (`LocalisationPolicy.issuePrecisionReduite`) : aucune
  coordonnée demandée ni transmise, message du web « Localisation refusée ou indisponible. Vous pouvez saisir votre
  adresse manuellement. », ville saisie à la main. Appliquée dès maintenant par l'implémentation provisoire, pour que
  le comportement ne change pas à la fusion. Raisons : le port du lot 2 ne rend aucune coordonnée en précision réduite
  (`ObservationGps.precisionReduite`, décision 5 du lot 2, qui refuse aussi `requestTemporaryFullAccuracyAuthorization`
  et sa chaîne `Info.plist` nouvelle) ; le blueprint interdit toute variante de ce port (§2.2 : « aucune signature
  parallèle », pas de `positionPonctuelle(precision:)`) ; obtenir une position approximative pour le profil
  modifierait `LocationService` du pointage, hors du lot 3. Écart web possible, non mesuré, consigné : le navigateur
  peut transmettre au web une position approximative, et la ville y serait renseignée. `RECETTE_DEVICE_LOT3.md` §6
  dit la même règle (garde `FusionLocalisationLot2Tests.testPrecisionReduiteTrancheeAvantLaFusion`).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T10 — textes natifs sans équivalent web de la photo de profil (non juridiques)

- **Critère** (celui de TJ5 ; `CLAUDE.md`, HARD STOP n°4) : aucun de ces textes ne restreint un mode d'exercice, ne
  cite une loi ni n'a de portée contractuelle ; chacun décrit exactement l'action de l'écran, au vouvoiement (décision
  9 du lot 1), et reste épinglé par son test.
- Textes **sans équivalent web** (le web n'ouvre qu'un sélecteur de fichier, `AvatarUpload.tsx`), validés par
  délégation : « Choisir dans la photothèque » et « Prendre une photo » (choix de la source de la photo de profil,
  `AvatarProfil.Textes`, épinglés par `AvatarLocalisationVerbatimTests.testTextesSansEquivalentWebListesPourRelecture`) ;
  « Annuler » repris tel quel de `ConfirmationSheet.swift` l.34 (L1-T1b, texte existant). Le libellé DEBUG démo
  `profil-avatar-etat` (« photo » / « initiales ») n'existe jamais en Release : ce n'est pas un texte affiché.
- Les textes web de T10 (messages d'`AvatarUpload.tsx`, de `documentUpload.ts` l.174 et de `SectionProfilPrincipal.tsx`)
  restent verbatim ou vouvoyés comme le dit la section T10 (aucun n'est juridique).
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

### T12 — textes de l'onglet Revenus : libellés escrow, note « net estimé », textes adaptés

Instruction faite à l'intégration du lot 3 (09/11/2026) : T12 a été écrite avant TJ8, qui lui demande d'instruire
ses libellés escrow et la note « net estimé » contre le glossaire escrow de `CLAUDE.md`.

- **Libellés et aides des sept états** (`src/components/gains/PaiementsEscrowAVenir.tsx` l.50-80, verbatim, tutoiement
  compris, épinglés par `RevenusPresentationTests.testChaqueTexteRepriseDuWebEstVerbatimASaLigne`) :
  - « Réservé » — « le montant de ta confirmation, mis de côté » : exact (`CLAUDE.md`, règle #11 : `honoraires_cents`
    figé à la confirmation, jamais recalculé ; séquestre libéré à la validation des présences). Ni « garanti » ni
    « stationne » (invariant épinglé par `RevenusPresentationTests`) ;
  - « En attente de validation des heures » — « l'établissement valide tes heures (automatique sous 72 h) » : exact
    au regard des CGU de production (`src/pages/PageCGU.tsx` l.115 : « En l'absence de contestation, les présences
    peuvent être validées automatiquement après 72 heures ») et du serveur (`fn_valider_presences_72h_auto`,
    `supabase/schema/public.sql` l.65474-65500 : validation automatique au seuil `delai_autovalidation_presence_h`,
    72 h par défaut, hors litige et alertes de fraude). L'état n'est rendu que hors litige (`LITIGE` est un autre
    état, l.67-70) ; « sous 72 h » donne le seuil du mécanisme contractuel, sans promettre une date de versement
    (le délai d'instruction du versement, 24 à 72 h, est un autre délai de la même ligne des CGU) ;
  - « Versement en cours », « Paiement retardé » (« nouvelle tentative le … » / « nous relançons le règlement »),
    « Paiement en litige » (« voir le litige de la mission »), « Versé le … », « Paiement annulé » (« contacte le
    support si besoin ») : description de l'état et de la date rendus par `fn_mes_paiements_escrow`
    (`public.sql` l.42233), exacts par construction ; aucune portée contractuelle propre.
  - Conclusion : aucun texte inexact au sens du critère de TJ8 ; verbatim maintenu.
- **Note « net estimé »** (`src/components/NoteNetEstime.tsx` l.13-16, verbatim) : estimation non contractuelle,
  exacte (le net du bulletin est établi par l'employeur, `CLAUDE.md`, Sprint 15 : l'établissement est seul
  responsable de la DPAE, Jolene n'est pas employeur) ; maintenue.
- **Textes adaptés ou sans équivalent web** (section HARD STOP, puce T12) : non juridiques (critère de TJ5), vouvoyés,
  épinglés par `RevenusPresentationTests.testTextesAdaptesOuSansEquivalentWeb` ; validés par délégation.
- Force des sources : choix de conformité Jolene (CGU de production et glossaire escrow de `CLAUDE.md`), règle serveur
  relue dans le dump. Aucun arrêt ni avis cité.
- décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026

## Prérequis bloquants de soumission (lot 6)

À lever avant toute soumission à Apple (TestFlight externe, qui passe la Beta App Review, comme App Store) ; ils ne
bloquent ni les merges du lot 3 ni la recette interne (build Debug installé par Xcode).

- **`NSCameraUsageDescription` doit nommer la photo de profil (revue B8 de T10, m3).** T10 utilise l'appareil photo
  pour la photo de profil (`SelecteurAppareilAvatar`) alors que la chaîne du lot 0 (`ios-native/Jolene/Info.plist`
  l.58-59) ne cite que les documents professionnels et les QR codes de pointage : risque de refus App Review (règle
  5.1.1, citée par la revue). Texte retenu (opérationnel, non juridique, vouvoyé) : « Jolene utilise la caméra pour
  photographier vos documents professionnels, prendre votre photo de profil et scanner les QR codes de pointage. » À
  changer à la fusion des lots 2 et 3, dans la même PR que la liste verrouillée `CHAINES_INFO_PLIST` de
  `scripts/mobile/check-textes-juridiques-ios.mjs` (lot 2, absente de la base du lot 3 : changer la chaîne ici seul
  ferait rougir la garde du lot 2 à la fusion). Mesure : `PORTE_LOT3.md` 6.7.

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
- **§6.6 Go B9** : B3, T7, T8, T12, T13, T14a, T14b, dispatch de T16, la PR backend de l'export RGPD (TJ4), et les
  signalements de la section B9 ; go au merge seulement, les décisions juridiques étant prises par délégation.
  (T8, 09/11/2026) Go de merge de `lot3/l3-t8-v2` ; la preuve STAGING de la complétion (ligne `soignants` relue après
  `register-soignant`, compte jetable nettoyé) reste au dispatch de T16 ; recette sur appareil de la complétion
  (sélecteur de date, clavier, VoiceOver) dans `RECETTE_DEVICE_LOT3.md`.
- **§6.7 Textes (HARD STOP)** : tranchés par délégation le 9 novembre 2026 (« Décisions déléguées du 8 novembre
  2026 », TJ1 à TJ5 ; règles TJ6 à TJ8 pour les textes des tranches à venir, dont les sept messages IBAN et la
  contestation) ; textes des tranches T8, T10 et T12 tranchés de même (T8-J1 à T8-J5, « T10 — textes natifs… »,
  « T12 — textes de l'onglet Revenus »). Reste la revue des écrans sur iPhone, qui exige la présence de Gabrielle
  (§6.2, `RECETTE_DEVICE_LOT3.md`).
- **§6.8 Stripe TEST sur appareil** : parcourir l'onboarding hébergé avec les valeurs de test publiées par Stripe
  (saisie par Gabrielle), constater le retour et le statut relu.
- **§6.9 Boîte mail** : une adresse contrôlée par Gabrielle pour l'inscription STAGING depuis Mail (Universal Link
  réel).
- **§6.10 TestFlight externe** : groupe de soignants pilotes, informations de test, Beta App Review ; décision
  explicite, le build parlant à la production. Préalable bloquant : section « Prérequis bloquants de soumission
  (lot 6) » (chaîne `NSCameraUsageDescription`, revue B8 de T10, m3).
  **Préalable** (verrou « un gap connu reste verrouillé », TJ2) : la connexion native porte « Mot de passe oublié ? »
  (`login-forgot` : reset natif ou renvoi web, reste de L1-T10) ;
  sans lui, le refus de réauthentification de T11 renvoie vers un contrôle absent de l'app. Gardé par
  `CompteVerbatimTests` et la garde Node du lot 3 tant que `login-forgot` manque à `LoginScreen.swift`.
- **T10 (appareil, §6.2)** : photo HEIC prise avec l'appareil photo et photo choisie dans la photothèque (feuilles
  système réelles), photo iCloud non téléchargée en mode Avion, appareil photo en plein écran sur iPad, autorisation
  de position réelle (accordée, refusée, précision réduite) et géocodage réel sur iPhone — `RECETTE_DEVICE_LOT3.md`
  §6 ; ces feuilles n'existent pas en démo.
- **§6.11 Captcha** : mesurer `PORTE_LOT0.md` 3.1 et 3.2 avant d'ouvrir T7 ; en cas de refus captcha, D25 s'applique.
  (T7, 08/11/2026) Toujours « non mesurées » : T7 est livrée en natif sous réserve de ces mesures, à faire avant son
  merge ; un refus captcha mesuré impose D25 (renvoi web de « Créer un compte »).
- **Signalé par T3b (hors §6)** : le reset natif du mot de passe (reste de L1-T10 : `SupabaseRecoveryGateway`,
  `ResetPasswordScreen`, quarantaine de la session de recovery, « Mot de passe oublié ? ») n'a de tranche ni au lot 1
  (mergé sans T10) ni au lot 3 ; en attendant, le lien `token_hash` ouvre la page web et `?code=` est refusé
  (option B). À planifier (préalable inchangé : modèle d'e-mail « Reset Password » au format `token_hash`, §6.6 du
  lot 1). Préalable du §6.10 (TJ2) : la connexion native porte « Mot de passe oublié ? » avant TestFlight externe.
- **Export RGPD et notes reçues non publiées** (signalé par la T0, confirmé live par T11) : tranché par délégation
  (L3-TJ, TJ4) ; seul le go B9 au merge de la PR backend reste à Gabrielle (§6.6).

## Ce qui n'est pas une décision de ce mémo

- Aucune règle de mode d'exercice ni aucun délai serveur n'est décidé ici ; les textes juridiques sont tranchés par
  délégation (« Décisions déléguées du 8 novembre 2026 »), toujours verbatim du web ou du serveur (HARD STOP n°4).
- Les réglages hors dépôt (Dashboard Auth, secrets APNs et Stripe, projet Sentry, appareil) et les go B9 sont à
  Gabrielle ; ce mémo ne les présume pas acquis.
- Le plan `docs/PLAN_APP_NATIVE_SWIFT.md` et le blueprint versionné ne sont pas modifiés par ces décisions.

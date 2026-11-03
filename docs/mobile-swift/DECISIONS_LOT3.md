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
  IBAN qui arrivent sans `error` (T14b) ; message du verrou de contestation (T13).
- Textes d'accessibilité **sans équivalent web** (vocalisés seulement, jamais affichés ; non juridiques, à relire
  par Gabrielle, L3-T1b) : « environ » (lecture de « ~ » devant un montant et dans une note, `AmountRow`) ;
  « Montant indisponible » (lecture du tiret « — », `AmountRow`) ; « critère rempli » / « critère non rempli »
  (`PasswordCriteriaList`, le web n'a que la coche). Le texte affiché reste verbatim web.
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

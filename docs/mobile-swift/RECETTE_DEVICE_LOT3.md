# Recette appareil physique — lot 3 (niveau de preuve 5)

> Créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT3_PLAN.md` §3 T0) pour que les réglages
> **non versionnables** (Dashboard Auth, secrets APNs et Stripe, projet Sentry) et les preuves **appareil** aient une
> trace dès le début du lot. Rempli par T17 (et par T16 pour les émissions STAGING) ; signé par Gabrielle à la
> clôture du lot 3. Niveau 5 de `PRINCIPES.md` §7. **Aucun niveau ne prouve les autres** : la CI (niveaux 1-2)
> prouve la navigation et le routage, STAGING (niveau 3) les mutations relues, cet appareil ce qu'un simulateur ne
> peut pas (APNs réel, Mail iOS, Universal Links via le CDN Apple, flux Stripe hébergé, crash réel, HEIC de
> l'appareil photo). Décisions applicables : `docs/mobile-swift/DECISIONS_LOT3.md`.

Règles de rédaction : une preuve est une **assertion observée** (texte exact à l'écran, requête SQL STAGING relue,
réponse APNs, événement Sentry), datée, avec l'identifiant du build et du projet Supabase ; les captures sont des
artefacts pour l'humain, jamais la preuve seule (`CLAUDE.md`, « Protocole de preuve »). Aucun jeton, mot de passe,
lien d'e-mail, IBAN complet ni identifiant de compte réel n'est collé ici ; les comptes sont ceux de la fixture D5 et
de la cohorte non-test D5-R (T16), ou l'adresse fournie par Gabrielle pour l'inscription (§6.9 du blueprint).

## 0. Appareil et builds

| Élément | Valeur | Date | Qui |
|---|---|---|---|
| iPhone (modèle, version iOS) — **iOS ≥ 17.4** exigé pour le retour Stripe par Universal Link (D7, correction 6) | — (à fournir par Gabrielle, §6.2) | — | — |
| Build Debug « Jolene-Staging » installé par Xcode (profil de développement `app.jolene`, Push + Associated Domains, signature manuelle) | — | — | — |
| xcconfig local non versionné portant la clé publishable STAGING (`Staging.xcconfig` l.2 : « injectée par la CI ») | présent / absent (jamais collé ici) | — | — |
| Entitlement `aps-environment` du build installé | `development` attendu (token sandbox) | — | — |
| Projet Supabase apparié au build | STAGING `mejpriaetwgtcstbgfid` — un build Release/TestFlight parle à la production et ne sert pas à cette recette (correction 5) | — | — |

## 1. Réglages non versionnés (actions de Gabrielle)

| Réglage | STAGING `mejpriaetwgtcstbgfid` | Prod `flripxtsyegjshnhzjkz` |
|---|---|---|
| Secrets APNs présents (`APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`) — sans eux `send-push` désactive tout token `IOS` (correction 5) | — | — |
| `APNS_TEAM_ID` = `GDU5AA28M9` après rotation de la clé (sonde `apns-probe.yml`, mode témoin) | — | — |
| `APNS_ENVIRONMENT` | `sandbox` attendu | `production` attendu |
| Modèle d'e-mail « Confirm signup » — format attendu : `{{ .SiteURL }}/inscription/confirmer?token_hash={{ .TokenHash }}&type=signup` | **à renseigner** (date, capture du modèle, texte exact du lien) | **à renseigner** (après validation STAGING) |
| « Site URL » (doit valoir `https://jolene.app`, seul domaine de l'AASA, ou hôte écrit en dur dans le modèle) | — | — |
| « Redirect URLs » contient `https://jolene.app/inscription/confirmer` | oui / non | oui / non |
| `mailer_autoconfirm` (lu par T16 avant la branche inscription) | — | — |
| Captcha GoTrue (`PORTE_LOT0.md` 3.1 et 3.2 ; refus → D25) | — | — |
| « Secure password change » (nonce exigé par `update(user:)`, D13) | — | — |
| `STRIPE_SECRET_KEY` STAGING en mode test (§6.3) | oui / non | — |
| Projet Sentry `jolene-ios` (org `jolene-z6`) et DSN fourni (§6.5) | — | — |

## 2. Push APNs sandbox reçu et tap (T17, critère « au moins six types »)

Préalables : §1 rempli ; cohorte non-test D5-R créée par T16 (bascule transactionnelle, D17) ; push émis par le
script service_role de T16 (`send-push` STAGING, destinataire D5-R, `idempotency_key` unique), jamais depuis la CI
simulateur. Après **chaque** envoi : `tokens_push.actif` relu pour le token de l'appareil (un token sandbox envoyé à
l'hôte de production reçoit `BadDeviceToken` et est désactivé).

| Type (`type_evenement`) | Données envoyées | Écran attendu au tap (app au premier plan, en arrière-plan, tuée) | `tokens_push.actif` relu | Observé |
|---|---|---|---|---|
| `CANDIDATURE_ACCEPTEE` | `mission_id` D5-R | détail mission natif `/soignant/missions/{id}` | — | — |
| `MISSION_ASSIGNEE` | `mission_id` D5-R | détail mission natif | — | — |
| `RAPPEL_MISSION` | `mission_id` D5-R | détail mission natif, bloc de confirmation de présence si J-1 | — | — |
| `MISSION_A_POURVOIR` | `mission_id` D5-R | détail mission natif (sans `mission_id` : Explorer) | — | — |
| `MISSION_ANNULEE_ETAB` | `mission_id` D5-R | détail mission natif | — | — |
| `PAIEMENT_RECU` | — | Revenus › « Paiements à confirmer » (correction 15) | — | — |
| `FACTURE_EMISE` | — | onglet Revenus (`revenus-screen`), factures en renvoi web | — | — |

Premier plan : bannière + son + liste (`willPresent`) ; aucun badge (le serveur n'en envoie pas). Pré-prompt : affiché
au 2e lancement à froid seulement, jamais au login (D1) — observé : —.

## 3. Inscription par Universal Link depuis Mail iOS (T17, critère inscription)

Conditions de validité : tap depuis **Mail iOS** ; AASA servi via le CDN Apple ; aucun choix « Ouvrir dans Safari »
mémorisé pour jolene.app ; lien non réécrit par un traceur SMTP ; build apparié au projet émetteur (§0).

| Étape | Attendu | Observé (texte exact, date, build) |
|---|---|---|
| « Créer un compte » natif (adresse de Gabrielle, profession, CGU verbatim) | message web verbatim de confirmation envoyée (`InscriptionRapide.tsx` l.320-326) | — |
| Tap sur le lien `token_hash` dans Mail iOS | l'app s'ouvre ; `verifyOTP(tokenHash:type:)` ; parcours relu ou démarré | — |
| Complétion (`register-soignant`) | `.ready` relu, onglets soignant ; ligne `soignants` relue en SQL STAGING | — |
| Lien `?code=` (si le modèle n'est pas encore au format `token_hash`) | échange tenté une fois, sinon repli « Se connecter » (D10) | — |

## 4. Stripe TEST — onboarding Connect et retour dans l'app (T17, critère Connect)

| Étape | Attendu | Observé |
|---|---|---|
| Ouverture de l'onboarding (cohorte D5-R, libéral non-test) | `ASWebAuthenticationSession` (iOS ≥ 17.4, rappel `.https` sur `jolene.app`) | — |
| Saisie des valeurs de test publiées par Stripe (par Gabrielle, §6.8) | parcours hébergé jusqu'au bout | — |
| Retour | l'app reprend la main sur `/soignant/stripe-connect?success=true` ; mécanisme consigné (rappel `.https` associé) | — |
| Statut relu (`stripe-connect-status?force=true`) | `EN_COURS` ou `COMPLET` (trois drapeaux vrais) affiché, identique à la ligne `stripe_connect_onboarding` relue | — |
| Compte test (fixture D5) | écran « Stripe désactivé sur ce compte de test », aucun appel d'edge | — |

## 5. Sentry — crash de test (T17, critère Sentry)

| Étape | Attendu | Observé |
|---|---|---|
| Lancement avec `-JOLENE_SENTRY_CRASH_TEST` (DEBUG) puis relance | événement reçu dans `jolene-ios`, release `app.jolene@2.0.0+25`, environnement `staging` | — |
| Contenu de l'événement | aucune PII : ni email, ni jeton, ni `token_hash`, ni IBAN, ni capture d'écran, ni breadcrumb réseau | — |

## 6. Profil, compte et thème sombre

| Étape | Attendu | Observé |
|---|---|---|
| Photo HEIC prise avec l'appareil photo, puis avatar | JPEG 256 px envoyé, `avatar_url` relu, image affichée après relancement (D14) | — |
| Reçu d'avatar après arrêt forcé entre l'upload et la RPC | relecture `avatar_url` au retour, pas de second upload automatique | — |
| Photo choisie dans la photothèque (`PHPickerViewController`, HEIC d'iPhone) | aucune demande d'accès aux photos ; JPEG 256 px sans métadonnée GPS dans l'objet Storage (lu en STAGING), « Photo mise à jour ! » | — |
| « Utiliser ma position actuelle », première fois (L3-T10) | feuille système avec la chaîne `NSLocationWhenInUseUsageDescription` du lot 0 ; accordée → ville renseignée par l'API Adresse, rien d'écrit avant « Enregistrer » ; refusée → « Localisation refusée ou indisponible. Vous pouvez saisir votre adresse manuellement. » | — |
| Position en précision réduite (Réglages › Confidentialité › Service de localisation › Jolene › Position exacte coupée) | ville renseignée (une ville suffit au profil) | — |
| Thème sombre (Réglages iOS sombre, puis choix « Sombre » dans l'app) | contrastes lisibles sur tous les écrans du lot 3 ; préférence conservée après relancement (D16) | — |
| Export RGPD partagé vers Fichiers | fichier JSON non vide, supprimé du conteneur temporaire après la feuille de partage | — |

## 6 bis. Renvoi web et fin d'identité (L3-T3b, revue B8 M1)

Le magasin du `SFSafariViewController` appartient à l'app et persiste ; il est effacé à chaque fin d'identité native et
avant chaque connexion (`DECISIONS_LOT3.md`, section T3b, corrections de la revue B8). Niveau 1 :
`SessionStoreFinIdentiteWebTests`, `PresentationsRacineTests` ; l'effacement réel ne se constate que sur appareil.

| Étape | Attendu | Observé |
|---|---|---|
| Compte A : ouvrir un renvoi (`/soignant/litiges` depuis un lien ou le centre), se connecter sur la page web dans la feuille, fermer | page web de A affichée dans la feuille | — |
| A se déconnecte de l'app (hub, « Se déconnecter »), puis le même lien universel est ouvert sans session | la feuille s'ouvre sur la page web **non connectée** (connexion web demandée), jamais l'espace de A | — |
| A connecté, renvoi affiché, session révoquée depuis le web (« Se déconnecter partout » ou changement de mot de passe) | la feuille se ferme avec le passage à l'écran de connexion ; un renvoi rouvert ensuite n'est pas connecté | — |
| Compte B se connecte sur le même appareil, puis ouvre `/soignant/mes-gains?tab=factures` | page web non connectée (ou session web de B après sa connexion web), jamais celle de A | — |
| Lien `?code=` de réinitialisation reçu pendant un renvoi affiché | la feuille se ferme, puis l'alerte « Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application. » | — |

## 7. Signature de clôture

| Élément | Valeur |
|---|---|
| Build final recetté | — |
| Lignes lot 3 de `docs/mobile-swift/PARITE_SOIGNANT.md` statuées avec preuve | — |
| Verdict Gabrielle (date) | — |

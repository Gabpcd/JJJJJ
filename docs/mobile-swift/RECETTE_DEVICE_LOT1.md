# Recette appareil physique — lot 1 (niveau de preuve 5)

> Créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT1_PLAN.md` §3 T0) pour que les réglages
> **non versionnables** (Dashboard Supabase Auth) et les preuves **appareil** aient une trace dès le début
> du lot. Rempli au fil des tranches T4a, T9, T10, T5, T6c et T12 ; signé par Gabrielle à la clôture du lot 1.
> Niveau 5 de `PRINCIPES.md` §7 : caméra, GPS, Keychain, Face ID, push, arrêt forcé. **Aucun niveau ne
> prouve les autres** : la CI (niveaux 1-2) prouve la navigation, STAGING (niveau 3) les mutations relues,
> cet appareil prouve ce qu'un simulateur ne peut pas (Mail iOS, AASA via CDN Apple, LocalAuthentication
> réelle, EventKit réel, push reçu par la coquille 1.0.7).

Règles de rédaction : une preuve est une **assertion observée** (texte exact à l'écran, requête SQL
STAGING, réponse APNs), datée, avec l'identifiant du build et du projet Supabase ; les captures sont des
artefacts pour l'humain, jamais la preuve seule (`CLAUDE.md`, « Protocole de preuve »). Aucun jeton,
mot de passe, lien de reset ni identifiant de compte réel n'est collé ici ; les comptes sont ceux de la
cohorte de recette (`native-test-<uuid>@example.invalid`, fixture D3 de T11).

## 0. Appareil et builds

| Élément | Valeur | Date | Qui |
|---|---|---|---|
| iPhone (modèle, version iOS) | — (à fournir par Gabrielle, `LOT1_PLAN.md` §6.5) | — | — |
| Face ID enrôlé | — | — | — |
| Build TestFlight 2.0.0 (25) — archive locale Xcode, `PRINCIPES.md` §8 | — (`CURRENT_PROJECT_VERSION` 26 si un build 25 existe déjà) | — | — |
| Projet Supabase apparié au build | STAGING `mejpriaetwgtcstbgfid` (`Config/Staging.xcconfig`) **ou** prod `flripxtsyegjshnhzjkz` (`Config/Production.xcconfig`) — un `token_hash` émis par l'un échoue sur un build de l'autre ; les deux partagent `applinks:jolene.app` | — | — |
| App 1.0.7 (coquille Capacitor) encore installée pour le test push `RAPPEL_MISSION` | oui / non | — | — |

## 1. Réglages Dashboard Auth non versionnés (B9 auth, action manuelle de Gabrielle)

Préalable à T10 (`LOT1_PLAN.md` §2.5, §6.6, décision 7). Aucun `supabase/templates/`, aucune section
`[auth]` dans `supabase/config.toml` : ces valeurs n'existent que dans le Dashboard, d'où cette trace.

| Réglage | STAGING `mejpriaetwgtcstbgfid` | Prod `flripxtsyegjshnhzjkz` |
|---|---|---|
| **Modèle d'e-mail « Reset Password »** — format attendu : `{{ .SiteURL }}/reset-password?token_hash={{ .TokenHash }}&type=recovery` (le défaut `{{ .ConfirmationURL }}` passe par `https://<ref>.supabase.co/auth/v1/verify?…&redirect_to=` et redirige en HTTP vers jolene.app → Safari, jamais l'app) | modèle d'e-mail reset = **à renseigner** (date, projet, capture du modèle dans le Dashboard, texte exact du lien) | modèle d'e-mail reset = **à renseigner** (après validation STAGING sur appareil) |
| « Site URL » | — | — |
| « Redirect URLs » contient `https://jolene.app/reset-password` | oui / non | oui / non |
| Captcha (Turnstile) actif sur sign-in / recovery | — (`captcha verification process failed` mappé en `.unauthorized` générique) | — |
| Durée de validité du lien recovery | — | — |
| « Secure password change » (nonce exigé par `update(user:)`) | — | — |
| SMTP personnalisé et suivi des clics (un lien réécrit par un tracker ne déclenche pas de Universal Link) | — | — |
| Modèle « Confirm signup » (lot 3, pour mémoire) | — | — |

## 2. Universal Link de reset mot de passe (T10, critère « testé et consigné »)

Conditions de validité (toutes requises) : tap depuis **Mail iOS** (pas une copie du lien dans Safari) ;
AASA servi via le CDN Apple (`https://app-site-association.cdn-apple.com/a/v1/jolene.app`) ; aucun choix
« Ouvrir dans Safari » mémorisé sur l'appareil pour jolene.app ; lien non réécrit par un tracker SMTP ;
build apparié au projet émetteur (§0).

| Étape | Attendu | Observé (texte exact, date, build, projet) |
|---|---|---|
| Demande depuis l'écran de connexion natif (« Mot de passe oublié ? », `resetPasswordForEmail`, `redirectTo: https://jolene.app/reset-password`) | message web verbatim (`PageConnexion.tsx` l.248-258), cooldown 60 s | — |
| Demande depuis le web (`PageConnexion.tsx` l.241) puis tap sur l'iPhone | l'app s'ouvre (format `token_hash`, indépendant de l'appareil) | — |
| Tap depuis Mail iOS | écran `ResetPasswordScreen` plein écran, hors TabView, « Vérification du lien… » puis formulaire | — |
| Lien `?code=` (`.pkce`) | refus « Ce lien ne permet pas de réinitialiser le mot de passe depuis l'application. » (décision 7, option B), aucun appel réseau | — |
| Lien expiré / `type=signup` sur `/reset-password` | « Lien invalide ou expiré », jamais le formulaire | — |
| Nouveau mot de passe (≥ 8, égalité) | « Mot de passe modifié avec succès. » → écran de connexion ; `signOut` effectué (quarantaine) | — |
| Abandon du modal | retour connexion, session de recovery **non** restaurée au relancement | — |
| Session déjà ouverte au tap | la session courante n'est pas écrasée silencieusement (modal bloquant, `signOut` à la fin) | — |

## 3. Face ID (T9, décision 1)

| Étape | Attendu | Observé |
|---|---|---|
| Activation dans Compte › Sécurité (`biometrie-toggle`) | préférence `jolene.biometrie.activee` par userId | — |
| Relancement à froid | `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` **avant** `restoreSession` | — |
| Annulation Face ID | `.signedOut(message: nil)`, Keychain intact (item non supprimé), reconnexion par mot de passe possible | — |
| Changement d'empreinte / nouveau visage | la session reste restaurable (pas de `SecAccessControl biometryCurrentSet`) | — |
| Appareil sans biométrie enrôlée | « Non disponible sur cet appareil », toggle grisé | — |

## 4. EventKit — ajout au calendrier (T5, décision 18)

Mécanisme fixé en T0 (revue B8, `LOT1_PLAN.md` §3 T5) : avec `requestWriteOnlyAccessToEvents` (iOS 17+),
l'app ne peut relire aucun événement, pas même les siens ; les doublons sont évités par un **journal local**
des créneaux ajoutés (`UserDefaults`, par `userId` : `missionId` + identifiant ou rang du créneau + `debut` +
`fin`), même mécanisme sous iOS 16. N = nombre de créneaux `PREVISIONNEL` hors pause dont `fin` est
renseignée (1 pour une mission ponctuelle de 24 h au plus sans créneau PREVISIONNEL), comme l'ICS web.

| Étape | Attendu | Observé |
|---|---|---|
| Premier tap `calendrier-{id}` (Mes missions › À venir ou Accueil) | demande d'accès système (iOS 16 `requestAccess(to:)`, iOS 17+ `requestWriteOnlyAccessToEvents`) | — |
| Refus | message, aucun événement, pas de nouvelle demande forcée | — |
| Accord | exactement N événements dans Calendrier (N noté avec la mission), un par créneau, alarmes -1440 / -60 min, URL `https://jolene.app/soignant/missions/{id}` | — |
| Second tap, mêmes horaires | 0 nouvel événement (toujours N dans Calendrier), message d'information de l'app | — |
| Créneau modifié par l'établissement, puis tap | 1 événement ajouté pour ce créneau ; l'ancien reste (écriture seule : ni relecture ni suppression possibles) — consigné | — |
| Réinstallation de l'app, puis tap | journal local vide : N doublons possibles, comme un second import du fichier ICS web — consigné | — |

## 5. Push `RAPPEL_MISSION` reçu par la coquille 1.0.7 → écran natif (T6c)

Aucun token APNs n'est enregistré par le build Swift au lot 1 (`fn_upsert_token_push` lot 3). Le test
porte sur le **lien** d'un push déjà reçu : `data.lien = /soignant/missions/{id}` (`fn_demander_confirmations_presence`).

| Étape | Attendu | Observé |
|---|---|---|
| Notification reçue | titre du push serveur « Ta mission demain — Je serai là ✓ » (`fn_demander_confirmations_presence` l.29924/29934 ; texte de la notification, jamais de l'écran) | — |
| Tap sur la notification (mission ASSIGNEE J-1 de la fixture D3) | `LinkRouter` → `.missionDetail(id)` → écran natif avec le bloc `presence-bloc` et le bouton « ✓ Je confirme ma présence » | — |
| Tap `presence-confirmer` | après relecture `presence_confirmee_le` : confirmation « Présence confirmée — l'établissement est prévenu. ✓ », puis état `presence-confirmee` « ✓ Présence confirmée — l'établissement est prévenu » ; bouton masqué (chaînes du web, `DetailMissionSoignant.tsx` l.1427-1438) | — |
| STAGING | `missions.presence_confirmee_le` non nul + notification étab `SYSTEM` « Présence confirmée ✓ » relues en SQL | — |

## 6. Arrêt forcé pendant un envoi de justificatif (T7, PRINCIPES §4)

| Étape | Attendu | Observé |
|---|---|---|
| Reçu Keychain `prepared` → `started` avant l'upload Storage `justificatifs` | reçu lisible après relancement | — |
| Arrêt forcé pendant l'upload | aucun renvoi automatique ; relecture serveur ; annulation rejouée uniquement si la relecture prouve qu'elle n'a pas été reçue | — |

## 7. Suppression de compte (T8, Apple 5.1.1)

| Étape | Attendu | Observé |
|---|---|---|
| Saisie « SUPPRIMER » puis confirmation | 200 `{success:true}` → écran « Compte supprimé » → connexion, jamais « Votre session a expiré » | — |
| Relancement | aucune session restaurée (Keychain purgé) | — |
| STAGING | `soignants.nom = 'Supprimé'` sur le compte jetable du run (go explicite Gabrielle, décision 13) | — |

## 8. Carte MapKit du détail mission (T4a, revue du 2026-11-02)

Ligne ajoutée le 2026-11-02 par la revue de T4a : la carte Apple Plans réelle (`CarteMapKit`, la seule que
verront les utilisateurs) n'est exercée par aucun test automatique — la démonstration montre l'aperçu hors
ligne (`mission-detail-carte-demo`, aucune requête), et `StagingConnexionTests` n'ouvre aucun détail (la
cohorte lot 0 n'a pas de profil `soignants`, `LOT1_PLAN.md` §3 T11). Cette ligne est **préalable** au passage
de `/soignant/recherche-missions` à « natif » dans `PARITE_SOIGNANT.md` ; l'assertion équivalente
(`mission-detail-carte-map` présent, `mission-detail-carte-demo` absent) est à reprendre dans
`StagingParcoursTests` (T11, fixture D3).

| Étape (build Staging ou Production, §0) | Attendu | Observé (texte exact, date, build, projet) |
|---|---|---|
| Explorer › une mission dont l'établissement a des coordonnées non nulles › détail | bloc « Localisation » `mission-detail-carte` avec la carte Apple Plans `mission-detail-carte-map` (tuiles chargées) ; **aucun** `mission-detail-carte-demo` ni texte « Aperçu de démonstration, sans fond de carte » | — (à faire) |
| Repère et cadrage | un repère rose centré sur l'établissement, étendue ≈ 1,5 km ; légende `mission-detail-carte-legende` = « nom · code postal ville » (valeurs `fn_etablissements_safe`) | — (à faire) |
| Lecture seule | ni déplacement ni zoom au geste ; aucune demande d'autorisation de localisation | — (à faire) |
| VoiceOver | un seul élément « Carte de la mission : nom, code postal ville » | — (à faire) |
| iOS 16 et iOS 17+ (si deux appareils) | iOS 16 : `Map(coordinateRegion:)` + `MapMarker` ; iOS 17+ : `Map(initialPosition:)` + `Marker` — même cadrage | — (à faire) |

## 9. Signature de clôture

| Élément | Valeur |
|---|---|
| Build final recetté | — |
| `docs/mobile-swift/PARITE_SOIGNANT.md` ≥ 45 % | — |
| Verdict Gabrielle (date) | — |

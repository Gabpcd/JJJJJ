# Recette appareil physique — lot 4 (niveau de preuve 5)

> Squelette créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT4_PLAN.md` §3 T0), rempli en T15
> (`LOT4_PLAN.md` §3 T15) et signé par Gabrielle à la clôture du lot 4. Niveau 5 de `PRINCIPES.md` §7 : ce
> qu'un simulateur ne prouve pas (socket Realtime sous iOS réel, Universal Link ouvert depuis une autre app,
> appareil photo d'un second téléphone, Fichiers, VoiceOver). **Aucun niveau ne prouve les autres** : la CI
> prouve la navigation démo, STAGING (T14) les mutations relues et le Realtime bidirectionnel, cet appareil
> le comportement réel.

Règles de rédaction : une preuve est une **assertion observée** (texte exact à l'écran, requête SQL STAGING,
fichier présent ou absent), datée, avec l'identifiant du build et du projet Supabase ; les captures ne sont
que des artefacts pour l'humain (`CLAUDE.md`, « Protocole de preuve »). Aucun jeton, mot de passe, code de
parrainage réel ni identifiant de compte réel n'est collé ici ; les comptes sont ceux de la fixture D4 (T14).
Contenu des messages de recette : alphabétique (pas de chiffres, faux positifs de l'anti-fuite).

## 0. Appareils et builds

| Élément | Valeur | Date | Qui |
|---|---|---|---|
| iPhone principal (modèle, version iOS) | — (à fournir par Gabrielle, `DECISIONS_LOT4.md` « En attente » n°8) | — | — |
| Second téléphone (QR, pair de messagerie) | — | — | — |
| Build TestFlight 2.0.0 (numéro) | — | — | — |
| Projet Supabase apparié au build | STAGING (`Config/Staging.xcconfig`) ou production (`Config/Production.xcconfig`) | — | — |
| Drapeaux `ios_natif_*_actif` du lot 4 lus à `true` | — | — | — |

## 1. Realtime : premier plan, arrière-plan, retour (T7a, T7b ; D7)

| Étape | Attendu | Observé |
|---|---|---|
| Fil ouvert au premier plan, le pair envoie un message | message affiché sans action, badge non incrémenté, `fn_marquer_messages_lus` relu | — |
| App en arrière-plan 2 min, le pair envoie un message | aucune socket ouverte (aucun `UIBackgroundModes`) | — |
| Retour au premier plan | réabonnement puis relecture du fil : le message manqué apparaît, sans doublon | — |
| Liste ouverte, message d'une conversation inconnue | relecture de la liste, nouvelle conversation affichée | — |

## 2. Mode avion : coupure réseau puis resynchronisation

| Étape | Attendu | Observé |
|---|---|---|
| Mode avion pendant que le fil est ouvert, le pair envoie deux messages | état « hors ligne » affiché ; le composeur reste actif (désactivé seulement pendant un appel en cours ou pour une conversation archivée, `LOT4_PLAN.md` T1b) | — |
| Envoi tenté pendant la coupure | l'appel à l'edge `messagerie-validate` part et échoue sans réponse : bulle « envoi non confirmé » (`EnvoiOutcome.nonConfirme`), texte conservé dans le composeur, **aucun renvoi automatique** (D8) ; relecture du fil au retour du réseau | — |
| Réseau rétabli | canal « rejoint » puis relecture : les deux messages apparaissent dans l'ordre | — |

## 3. Tap d'une notification de message (si le lot 3 a livré le coordinateur push)

| Étape | Attendu | Observé |
|---|---|---|
| Notification de message reçue app fermée, tap | écran Messagerie, conversation ouverte | — |

## 4. Lien de parrainage ouvert depuis Messages et WhatsApp (T6 ; D14)

| Étape | Attendu | Observé |
|---|---|---|
| `https://jolene.app/inscription/soignant?ref=<code de recette>` touché dans Messages | l'app s'ouvre (Universal Link), code capté en majuscules | — |
| Même lien touché dans WhatsApp | même résultat (ou ouverture Safari consignée si WhatsApp ouvre son navigateur interne) | — |
| Première session authentifiée qui suit | `fn_appliquer_parrainage` appelé une fois, toast « Code de parrainage enregistré. », `mon_parrain` relu | — |
| Code `ETB-…` | ignoré | — |

## 5. QR de parrainage scanné par l'appareil photo d'un second téléphone (T6)

| Étape | Attendu | Observé |
|---|---|---|
| QR affiché sur l'iPhone principal, scanné par l'appareil photo du second téléphone | URL exacte `https://jolene.app/inscription/soignant?ref=<code>` proposée | — |

## 6. Copie de bulletin partagée vers Fichiers puis supprimée (T10 ; D12)

| Étape | Attendu | Observé |
|---|---|---|
| Ouverture d'une copie valide | PDF affiché après contrôle type, taille et SHA-256 | — |
| Partage vers Fichiers | fichier présent dans Fichiers | — |
| Retour dans l'app | fichier temporaire supprimé du dossier `tmp` de l'app (protection `NSFileProtectionComplete`) | — |

## 7. VoiceOver sur le paquet de swipe (T3b ; D22)

| Étape | Attendu | Observé |
|---|---|---|
| VoiceOver activé sur la vue Swipe | carte lue en entier, actions d'accessibilité « Passer », « Sauvegarder », « Candidater » | — |
| Action « Candidater » | récapitulatif exact des créneaux avant confirmation | — |

## 8. Renvois web sans boucle Universal Link (T1c, T13 ; D17)

| Étape | Attendu | Observé |
|---|---|---|
| Entrée « Sur jolene.app » (par exemple premium) | `SFSafariViewController` sur `https://jolene.app/soignant/...`, l'app ne se rouvre pas elle-même | — |

## 9. Signature de clôture

| Élément | Valeur |
|---|---|
| Build final recetté | — |
| `docs/mobile-swift/PARITE_SOIGNANT.md` à 100 % | — |
| Verdict Gabrielle (date) | — |

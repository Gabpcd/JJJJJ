# Recette appareil physique — lot 5, espace établissement (niveau de preuve 5)

> Squelette créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT5_PLAN.md` §3 T0) ; rempli au fil des
> tranches T7 (pointage), T2b (liens), T10 (signature) et T14 (clôture), signé par Gabrielle à la clôture du lot 5.
> Niveau 5 de `PRINCIPES.md` §7 : ce qu'un simulateur ne prouve pas — un QR scanné par une vraie caméra, l'écran
> laissé allumé, un Universal Link ouvert depuis Mail iOS, un compte établissement legacy réel. **Aucun niveau ne
> prouve les autres** : la CI (démo) prouve la navigation et le décodage du QR, STAGING (T13) les mutations relues,
> cet appareil le reste.

Règles de rédaction : une preuve est une **assertion observée** (texte exact à l'écran, identifiant d'accessibilité,
requête SQL STAGING), datée, avec l'identifiant du build et du projet Supabase ; les captures sont des artefacts
pour l'humain, jamais la preuve seule (`CLAUDE.md`, « Protocole de preuve »). Aucun code de pointage en clair, aucun
jeton, mot de passe ni identifiant de compte réel n'est collé ici (empreinte `sha256` seulement).

## 0. Appareils et builds

| Élément | Valeur | Date | Qui |
|---|---|---|---|
| iPhone établissement (modèle, version iOS) | — (`LOT5_PLAN.md` §6.6) | — | — |
| iPad (modèle, version iPadOS), portrait et paysage | — | — | — |
| Second iPhone avec l'app soignant TestFlight (scanner du QR) | — | — | — |
| Build TestFlight (même build sur les trois appareils) | — | — | — |
| Projet Supabase apparié au build | STAGING ou production (lecture seule pour le compte legacy réel) | — | — |

## 1. Pointage terrain (T7)

| Étape | Attendu | Observé (texte exact, date, build, projet) |
|---|---|---|
| Code rotatif d'une mission du jour, contrat signé | `etab-pointage-code` affiche 6 chiffres ; `sha256` égal à celui de `code_pointage_actif` relu | — |
| QR plein écran (`etab-pointage-plein-ecran-vue`) scanné par l'app soignant du second iPhone | le scan aboutit (`fn_scanner_code_pointage`), code relu changé après le scan | — |
| QR plein écran sur iPad portrait puis paysage | QR lisible au premier essai dans les deux orientations | — |
| Écran laissé 10 min en plein écran, sans toucher | l'écran ne se met pas en veille | — |
| Retour à l'accueil iOS puis reprise | veille rétablie en arrière-plan ; polling 5 s arrêté puis repris au retour | — |
| Fermeture du plein écran | veille rétablie (`IdleTimerController` à compteur) | — |
| Membre LECTURE_SEULE sur la même mission | `etab-pointage-reserve`, aucun code affiché | — |

## 2. Liens (T2b)

Conditions : tap depuis **Mail iOS** ; AASA servi par le CDN Apple ; aucun choix « Ouvrir dans Safari » mémorisé.

| Étape | Attendu | Observé |
|---|---|---|
| Universal Link `/etablissement/missions/{id}` depuis Mail, espace établissement ouvert | détail natif de la mission | — |
| Universal Link `/contrat/{id}` depuis Mail, espace établissement ouvert | écran contrat natif de l'espace établissement | — |
| Même lien `/etablissement/missions/{id}` reçu dans l'espace soignant (même appareil) | ouverture Safari, jamais un écran établissement | — |
| Renvoi web (ex. facturation) | Safari s'ouvre ; reconnexion web demandée (session non partagée, D16) | — |

## 3. Compte établissement legacy réel (lecture seule, §6.6)

| Étape | Attendu | Observé |
|---|---|---|
| Connexion d'un compte legacy (`app_metadata.role = 'ETABLISSEMENT'`, sans `etablissement_id`) | `.readyEtablissement` : cinq onglets établissement ; nom d'établissement (`etab-compte-nom`) égal à celui du web, rôle « Propriétaire » (`etab-compte-role`) | — |
| `fn_mes_permissions_etab` (lecture) | `role = 'PROPRIETAIRE'`, `etablissement_id = user.id` ; aucune écriture effectuée | — |

## 4. Signature OTP établissement (T10, facultatif, SMS réel lu par Gabrielle)

| Étape | Attendu | Observé |
|---|---|---|
| Envoi de l'OTP | SMS reçu au `telephone_contact` de l'établissement (pas au téléphone du membre) | — |
| Signature | « signé » relu (`signature_etablissement_le` non nul) ; mention de l'écran identique au web | — |

## 5. Signature de la recette

| Rôle | Nom | Date | Décision |
|---|---|---|---|
| Gabrielle | — | — | — |

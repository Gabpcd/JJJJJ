# Recette appareil physique — lot 2 (niveau de preuve 5)

> Squelette créé le 2026-11-02 par la tranche T0 (`docs/mobile-swift/LOT2_PLAN.md` §3 T0, critère P8 de §1.3) ;
> rempli par la tranche T12 et signé par Gabrielle à la clôture du lot 2. Niveau 5 de `PRINCIPES.md` §7 : caméra,
> GPS, Keychain, arrêt forcé, SMS réel. **Aucun niveau ne prouve les autres** : la CI (niveaux 1-2) prouve la
> navigation et les règles, STAGING (niveau 3, T11) les mutations relues en SQL, cet appareil ce qu'un simulateur
> ne peut pas (vraie caméra, vrai GPS et « Position exacte », photothèque HEIC, Fichiers, arrêt forcé, SMS reçu).

Scénarios exigés par P8 : QR rotatif, GPS refusé puis accordé, « Position exacte » désactivée, photo HEIC, photo
caméra, PDF depuis Fichiers, arrêt forcé pendant un scan puis arrêt forcé pendant un envoi avec réconciliation sans
doublon relue en SQL, signature OTP réelle relue dans `signatures_contrats`.

Règles de rédaction : une preuve est une **assertion observée** (texte exact à l'écran, requête SQL STAGING relue),
datée, avec l'identifiant du build et du projet Supabase ; les captures sont des artefacts pour l'humain, jamais la
preuve seule (`CLAUDE.md`, « Protocole de preuve »). Aucun code de pointage, code OTP, numéro de téléphone, jeton,
chemin Storage ni URL signée n'est collé ici ; les comptes sont ceux de la fixture « appareil » de T11
(`staging-lot2-fixture.mjs --appareil`, cohorte TEST STAGING). Aucune vraie pièce d'identité en recette : la photo
HEIC est une photo personnelle **non** identitaire.

## 0. Appareil, builds et préalables

| Élément | Valeur | Date | Qui |
|---|---|---|---|
| iPhone (modèle, version iOS) | — (iPhone de Gabrielle, `LOT2_PLAN.md` §6.5) | — | — |
| Build TestFlight Staging 2.0.0 (26), projet `mejpriaetwgtcstbgfid` | — | — | — |
| Fixture « appareil » (`staging-lot2-fixture.mjs --appareil`, TTL explicite, nettoyage par seconde invocation ; go B9) | — | — | — |
| Front web lancé **localement** contre STAGING sur un ordinateur (`npm run dev`, `VITE_SUPABASE_URL` / `VITE_SUPABASE_PUBLISHABLE_KEY` STAGING ; aucun web STAGING déployé, `docs/staging.md` l.16), connecté à l'établissement TEST de la fixture | — | — | — |
| Capacité SMS S1 allouée pour le contrat de la fixture appareil, **après** son rendu (fenêtre 60 min, deux envois par acteur ; go B9) | — | — | — |

## 1. QR rotatif scanné sur iPhone (P2, niveau 5 ; décisions 1 et 3)

- Écran établissement `AffichageCodeRotatifEtab` ouvert dans le front local ; dans l'app, Présences › mission de la
  fixture › bouton QR : le QR affiché est lu par la vraie caméra (`AVCaptureMetadataOutput`), un seul scan envoyé
  malgré plusieurs détections.
- Attendu : « Pointage enregistré — segment ouvert » (vouvoiement) ; SQL : une ligne `scans_pointage`
  (`type_scan = 'OUVERTURE'`, `id_terminal ~ '^TERM_IOS_[A-Z2-7]{20}$'`) pour la mission.
- Refus caméra (Réglages) : message et saisie manuelle des six chiffres toujours disponibles.

| Étape | Observé (texte exact / SQL) | Date | Build |
|---|---|---|---|
| QR lu, un seul scan | — | — | — |
| Refus caméra → saisie manuelle | — | — | — |

## 2. GPS refusé puis accordé, « Position exacte » désactivée (décisions 4 et 5)

- Premier pointage avec `consentement_gps` NULL : écran de consentement verbatim (`ConsentementGPS.tsx`), « Autoriser »
  puis autorisation iOS « Lorsque l'app est active ».
- **GPS refusé puis accordé** : refus dans Réglages → pointage réussi sans coordonnées + bandeau sans GPS ; accord
  dans Réglages → pointage suivant avec `precision_gps_m` non nul (SQL `scans_pointage`).
- **« Position exacte » désactivée** (précision réduite) : aucune coordonnée envoyée, encart invitant à réactiver
  « Position exacte » ; SQL : `latitude`, `longitude`, `precision_gps_m` nuls pour ce scan.
- Retrait du consentement depuis le Profil natif puis réactivation : `soignants.consentement_gps` relu.

| Étape | Observé (texte exact / SQL) | Date | Build |
|---|---|---|---|
| Consentement accepté, autorisation iOS | — | — | — |
| GPS refusé puis accordé | — | — | — |
| « Position exacte » désactivée | — | — | — |
| Retrait puis réactivation depuis le Profil | — | — | — |

## 3. Justificatifs : HEIC, caméra, Fichiers (décisions 13 et 14)

- Photo **HEIC** de la photothèque (`PHPickerViewController`, sans permission photothèque) : envoyée en JPEG ; SQL :
  `documents_soignants.type_mime = 'image/jpeg'`, une seule vérification (`journaux_audit` `DOCUMENT_VERIFICATION_AUTO`
  ou une ligne `file_revue_manuelle` pour ce document).
- Photo prise à la **caméra** (`UIImagePickerController`) : même contrôle.
- PDF choisi dans **Fichiers** (`UIDocumentPickerViewController`) : même contrôle.

| Source | Observé (texte exact / SQL) | Date | Build |
|---|---|---|---|
| HEIC (photothèque) | — | — | — |
| Caméra | — | — | — |
| PDF (Fichiers) | — | — | — |

## 4. Arrêts forcés et réconciliation sans doublon (P6, `PRINCIPES.md` §4 ; décisions 2 et 14)

- **Arrêt forcé pendant un scan** (glisser l'app hors du sélecteur pendant « Vérification du pointage… ») puis
  relance : réconciliation par relecture, aucun second envoi ; SQL : une seule preuve `scans_pointage` pour la
  tentative.
- **Arrêt forcé pendant un envoi** de justificatif puis relance : réconciliation par `s3_cle` ; SQL : un seul
  document (`documents_soignants`) pour la clé, au plus une vérification.

| Scénario | Observé (texte exact / SQL « une preuve, un document ») | Date | Build |
|---|---|---|---|
| Arrêt forcé pendant un scan | — | — | — |
| Arrêt forcé pendant un envoi | — | — | — |

## 5. Signature OTP réelle (P5 complet ; décisions 18 et 20 ; HARD STOP n°4)

- Contrat de la fixture appareil ouvert dans l'app : empreinte affichée égale à `contrats_mission.hash_document`
  (SQL) ; consentement coché ; « Recevoir le code SMS pour signer » ; SMS reçu par Gabrielle ; code saisi dans le champ
  OTP.
- Attendu : contrat signé relu ; SQL : `signatures_contrats.statut_signature = 'signe'` et
  `signatures_contrats.hash_document = contrats_mission.hash_document` pour le soignant.
- La signature OTP n'est déclarée prouvée qu'après le go HARD STOP de Gabrielle sur T9b et sa revue des écrans (P9).

| Étape | Observé (texte exact / SQL) | Date | Build |
|---|---|---|---|
| Empreinte affichée = `hash_document` | — | — | — |
| SMS reçu, code saisi | — | — | — |
| `statut_signature = 'signe'` relu | — | — | — |

## 6. Signature de clôture

| Rôle | Nom | Date | Décision |
|---|---|---|---|
| Recette appareil | Gabrielle | — | — |
| Revue des écrans de consentement GPS, d'attestation santé et de signature (P9) | Gabrielle | — | — |

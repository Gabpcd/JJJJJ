# Conformité — Jolene

> Document de suivi conformité. **Rien n'est implémenté ici** : décisions actées
> + chantiers à câbler, avec base légale et échéance. Protocole de validation :
> **Gabrielle valide** (ce protocole tient lieu de relecture — pas d'avocat).

## 1. Audit des documents soignants + données de santé

### 1.1 Types de documents (enum `type_document`, prod 09/07/2026)

**Effectivement collectés / requis** (référentiel `documents_requis_par_profession`) :

| Type | Nature | Donnée de santé ? |
|---|---|---|
| `CARTE_IDENTITE` (+ `PASSEPORT`, `TITRE_SEJOUR`) | Identité | Non |
| `DIPLOME` | Qualification | Non |
| `RPPS_ADELI` / `CARTE_ORDRE` | Enregistrement professionnel | Non |
| `RCP_ASSURANCE` | Assurance responsabilité civile pro | Non |
| `RIB` | Coordonnées bancaires | Non |
| `ATTESTATION_URSSAF` | Situation sociale (libéral) | Non |
| `AUTORISATION_EXERCICE` / `LICENCE_REMPLACEMENT` | Droit d'exercer | Non |
| `KBIS` | Société (BNC/libéral) | Non |
| `NOTE_HONORAIRES`, `ATTESTATION_3200H`, `ATTESTATION_SCOLARITE`, `ATTESTATION_CPAM` | Administratif / parcours | Non |

### 1.2 Décision actée : Jolene ne stocke AUCUNE donnée de santé (par construction)

- **Aucun document de santé n'est collecté ni requis.** Jolene est **hors
  périmètre HDS** (hébergeur de données de santé), art. **L1111-8 CSP** : aucune
  donnée de santé à caractère personnel n'est hébergée pour le compte de tiers
  → **pas de sujet HDS**, pas de certification requise.
- Corollaire produit : documents requis = identité + qualification + assurance +
  situation administrative/bancaire uniquement.

### 1.3 ⚠️ SIGNALEMENT (sans suppression) — valeurs d'enum « santé » dormantes

L'enum `type_document` **contient** 3 valeurs qui seraient des données de santé
si utilisées — mais elles sont **dormantes** : exigées par **0** profession,
stockées **0** fois (vérifié prod 09/07/2026) :

- `VACCINATIONS` — certificat de vaccination (donnée de santé, RGPD art. 9)
- `MEDECINE_TRAVAIL` — aptitude médicale / médecine du travail (donnée de santé)
- `ARRET_MALADIE` — arrêt maladie (donnée de santé)

**Ne PAS supprimer maintenant** (instruction). **Risque latent** : un futur dev
pourrait câbler l'un d'eux → Jolene basculerait dans le périmètre HDS.
**Remplacement prévu** (si un besoin d'aptitude/vaccination émerge) :
**attestation sur l'honneur du soignant + vérification par l'établissement** (qui
lui est dans son rôle d'employeur/donneur d'ordre), jamais le stockage du
document médical par Jolene. **TODO** : retirer ces 3 valeurs de l'enum une fois
confirmé qu'aucun flux ne les vise (migration dédiée + audit `documents_soignants`).

## 2. DAC7 — déclaration annuelle des revenus des opérateurs de plateforme

- **Base** : directive (UE) 2021/514 (**DAC7**), transposée art. **1649 ter A et
  s. CGI** ; Jolene = opérateur de plateforme au sens de l'art. **242 bis CGI**.
- **Obligation** : déclaration annuelle à la **DGFiP en janvier** (au titre de
  l'année N-1) des revenus perçus par les soignants via la plateforme, avec leurs
  données d'identification fiscale.
- **À câbler AVANT la première clôture annuelle avec revenus** :
  1. **Collecte des données fiscales à l'onboarding** : NIF/numéro fiscal, date
     et lieu de naissance, adresse, n° TVA le cas échéant, État de résidence.
  2. Agrégation annuelle par soignant des montants encaissés + commissions.
  3. Génération du fichier déclaratif au format DGFiP + télétransmission janvier.
- **Statut** : NON implémenté. Chantier à planifier dès qu'il y a des revenus
  réels sur une année civile.

## 3. Art. 242 bis CGI — information des utilisateurs

- **Obligation** (art. **242 bis CGI**) : informer chaque utilisateur, à chaque
  transaction et via un **récapitulatif annuel**, de ses **obligations fiscales
  et sociales** relatives aux revenus perçus via la plateforme.
- **À câbler** :
  1. Mention des obligations fiscales/sociales (déjà partiellement présent côté
     revenus soignant — cf. module fiscal libéral) → **formaliser**.
  2. **Récapitulatif annuel** par soignant (somme des transactions de l'année,
     envoyé/téléchargeable) — **avant la première clôture annuelle**.
- **Statut** : partiellement couvert (info fiscale libérale existante) ;
  récapitulatif annuel formel NON implémenté.

## 4. Facturation électronique — réforme (généralisation)

> Réforme TVA / facturation électronique B2B. Deux volets distincts.

### 4.1 RÉCEPTION de factures via plateforme agréée (PA)

- **Échéance** : **1er septembre 2026** (toutes les entreprises doivent pouvoir
  **recevoir** des factures électroniques via une PA).
- **Action** : **hors code, Gabrielle, sous 15 jours** — choisir + raccorder une
  **plateforme agréée** pour la réception. (Action administrative, pas de dev.)

### 4.2 ÉMISSION de factures via PA

- **Échéance** : **septembre 2027** (émission via PA, y compris les factures
  **émises au nom des soignants** par Jolene en tant que mandataire de
  facturation).
- **Existant** : le format **Factur-X** déjà généré est **conforme**.
- **Chantier futur** : **raccordement à une PA pour l'émission** (transmission
  des Factur-X via la plateforme agréée). À planifier d'ici 2027.

### 4.3 Secteur public — Chorus Pro

- **Inchangé** : les factures vers le secteur public continuent de passer par
  **Chorus Pro** (déjà intégré). La réforme B2B ne modifie pas ce canal.

## Récapitulatif — à câbler avant échéance

| Sujet | Échéance | Type | Statut |
|---|---|---|---|
| DAC7 (collecte fiscale + déclaration) | 1ère clôture annuelle avec revenus | Dev | À faire |
| 242 bis — récapitulatif annuel | 1ère clôture annuelle | Dev | À faire |
| Réception factures via PA | 01/09/2026 | Admin (Gabrielle, 15 j) | À faire |
| Émission via PA (Factur-X → PA) | 09/2027 | Dev | À planifier |
| Retrait enum santé dormant | Post-confirmation | Dev (migration) | Signalé |

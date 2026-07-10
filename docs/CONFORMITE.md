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

### 1.3 Types de données « santé » de l'enum `type_document` — verrou (pas de retrait)

L'enum `type_document` **contient** 3 valeurs qui sont des données de santé
(RGPD art. 9). **On ne retire PAS les valeurs de l'enum** (drop d'une valeur
d'enum Postgres = migration à risque). À la place, un **trigger BEFORE INSERT**
(`fn_trg_bloquer_documents_sante`, migration `20260709180000`) **rejette** tout
stockage, avec un message renvoyant à ce document. **Le verrou remplace le
retrait.**

| Type | Statut | Verrou DB | Chemin frontend |
|---|---|---|---|
| `VACCINATIONS` | Dormant (0 requis, 0 stocké) | ✅ Verrouillé | Déjà exclu de l'upload (`src/lib/documents.ts` `TYPES_DOCUMENTS_EXCLUS_UPLOAD`) |
| `MEDECINE_TRAVAIL` | Dormant (0 requis, 0 stocké) | ✅ Verrouillé | Déjà exclu de l'upload |
| `ARRET_MALADIE` | Démantelé (0 stocké, chemin upload supprimé) | ✅ **Verrouillé** (migration `20260710090000`, voir §1.4) | Remplacé par `fn_declarer_empechement_imperieux` + `<DeclarationEmpechement>` |

**Remplacement de référence** (si un besoin santé émerge) : **attestation sur
l'honneur du soignant + vérification par l'établissement** (dans son rôle
d'employeur/donneur d'ordre), jamais de stockage du document médical par Jolene.

### 1.4 ⚠️ FINDING — `ARRET_MALADIE` est une fonctionnalité vivante (donnée de santé)

**Constat initial** : `ARRET_MALADIE` n'était pas dormant —
`src/pages/DetailMissionSoignant.tsx:863-899` téléversait un **certificat
médical** (`INSERT documents_soignants(type_document='ARRET_MALADIE')` +
vérification IA) pour justifier un désistement. C'était du stockage de donnée de
santé, contraire à la décision « zéro donnée de santé ».

### ✅ RÉSOLU — empêchement impérieux sur l'honneur, zéro donnée de santé, verrou 3/3

**Décision (Gabrielle, 09/07/2026)** : remplacer par une **attestation sur
l'honneur d'empêchement impérieux** (santé, urgence familiale…), **le motif
générique n'étant PAS stocké** — le seul fait d'être malade est déjà une donnée
de santé (RGPD art. 9) ; un motif générique sort Jolene entièrement du champ.

**Mini-PR EXÉCUTÉE le 10/07/2026** (migration `20260710090000_attestation_empechement_imperieux.sql`
+ `src/components/DeclarationEmpechement.tsx`) — périmètre livré, cf.
`docs/MINI_PR_ARRET_MALADIE.md` :
1. Déclaration **structurée** : case sur l'honneur + **dates d'indisponibilité**,
   **AUCUN champ libre**, aucune catégorie/justificatif stockés.
2. **Anti-abus** : attestation horodatée dans `journaux_audit` ; compteur par
   soignant en paramètre (`fn_param_num`, défaut **2** annulations justifiées /
   12 mois glissants) — au-delà, pénalité de score **malgré** l'attestation +
   revue. Fausse déclaration = responsabilité utilisateur (ligne CGU ajoutée au
   wagon §4.6 en cours).
3. **Démantèlement** : upload `ARRET_MALADIE` retiré de `DetailMissionSoignant`,
   pipeline IA débranché pour ce type, **0 document `ARRET_MALADIE` stocké**
   vérifié (prod = 0 au 09/07/2026 ; purger seeds si trouvés), puis
   `ARRET_MALADIE` **ajouté au verrou** trigger → **3/3**.
4. CGU : le wording d'annulation actuel **ne mentionne pas** « certificat
   médical » (vérifié) — rien à réaligner ; clause attestation ajoutée à
   l'amendement §4.6.

**Conséquence store** : privacy labels iOS/Android = **aucune donnée de santé
collectée** — d'où l'exécution de ce chantier **avant la soumission** aux stores.

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
| Verrou docs santé (VACCINATIONS/MEDECINE_TRAVAIL) | Fait | Dev (trigger) | ✅ Verrouillé |
| ARRET_MALADIE : attestation sur l'honneur + verrou | Fait (10/07/2026) | Produit + Dev | ✅ Livré — migration 20260710090000 (§1.4) |

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

- **Base** : Jolene est **opérateur de plateforme au sens des art. 1649 ter A et s.
  CGI** (directive (UE) 2021/514, **DAC7**), qui portent l'obligation **déclarative**
  DAC7 ; l'art. **242 bis CGI** porte, lui, l'obligation d'**information des
  utilisateurs** (cf. §3).
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

## 5. Matrice des modes d'exercice (profession × établissement) — ✅ GO GABRIELLE AVEC C1-C7 (12/07/2026)

> **Décision validée sous réserve de C1-C7**, intégrées ci-dessous. La migration
> initiale `20260712160000` a créé et seedé la table ; la migration corrective
> `20260712161000` prépare le câblage des consommateurs, corrige le seed public, ajoute les
> sources cliquables et supprime les règles juridiques clientes en dur.

### 5.0 Constat initial — règle en dur, binaire et sur-appliquée

- Avant la migration corrective, `fn_profession_peut_etre_liberal` (booléen en dur)
  autorisait le libéral pour IDE,
  **IADE, IBODE**, SAGE_FEMME, KINE, MEDECIN, PHARMACIEN, ORTHOPHONISTE, DIETETICIEN,
  ERGOTHERAPEUTE, PSYCHOMOTRICIEN, MANIPULATEUR_RADIO, **DENTISTE** ; bloque AS, AES,
  AUXILIAIRE_PUERICULTURE, PREPARATEUR_PHARMA.
- **Incohérences constatées** : IADE et IBODE étaient **autorisés libéral à tort** (ils font partie
  des 7 professions de la lettre du 30/12/2021) ; IDE et paramédicaux autorisés sans
  la nuance « risque de requalification » ; **aucune dimension type d'établissement**
  (centre de santé vs clinique privée).
- **Citations inexactes précédemment exposées à l'utilisateur** (4 surfaces, cf. recensement A3) :
  - `src/lib/constantes.ts:52-91` (`LIBERAL_COMPATIBILITY` / `PROFESSIONS_NON_LIBERAL` /
    `peutExercerLiberal()`) — la matrice en dur qui pilote tout.
  - `src/components/FormulaireMission.tsx:650-654` — « le mode libéral n'est pas autorisé
    par la réglementation (salariat déguisé, cf CE 11/02/2025 arrêt Mediflash) ».
  - `src/components/mission/ModalRecapMission.tsx:95-100, 221-238` — « la réglementation
    interdit le mode libéral … CE 11/02/2025 arrêt Mediflash ».
  - `src/components/BannerMediflashExplication.tsx:33-89` — cite l'arrêt **n°488367**.
  → Ces quatre surfaces sont corrigées par `20260712161000` et le présent diff : elles
    ne généralisent plus l'arrêt, qui ne juge **que les aides-soignants**.
- **✅ Numéro d'arrêt TRANCHÉ (C1)** : le bon numéro est **n°491128** (CE, 5e-6e chambres
  réunies, 11/02/2025 — Légifrance **CETATEXT000051156546**). Le **n°488367** cité par
  `BannerMediflashExplication` était **erroné** → corrigé sur les 4 surfaces. Le
  **n°491130** est l'**ordonnance de référé du 05/02/2024** (CETATEXT000049101638) :
  citable **en complément**, jamais à la place de l'arrêt au fond.

### 5.1 Sources primaires (C1-C2) — passages VERBATIM

**Arrêt CE, 5e-6e ch. réunies, 11/02/2025, n°491128** (Légifrance CETATEXT000051156546) :

> **Cons. 1** — « la lettre qu'ils avaient adressée, le 30 décembre 2021, aux directeurs
> des établissements sanitaires, sociaux et médico-sociaux sur le recours aux services de
> personnels paramédicaux sous un statut de travailleur indépendant, par l'intermédiaire de
> plateformes de mise en relation, **en tant qu'elle vise la profession d'aide-soignant**. »
>
> **Cons. 3** — « La lettre du 30 décembre 2021 … vise explicitement à mettre en garde les
> directeurs d'établissements de santé, sociaux et médico-sociaux quant au recours aux
> services de **certains professionnels paramédicaux, dont les aides-soignants**, sous un
> statut de travailleur indépendant. »
>
> **Cons. 6** — « lorsqu'ils exercent au sein d'un tel établissement, les aides-soignants
> doivent nécessairement être regardés comme étant **placés sous l'autorité et le contrôle
> de la hiérarchie** de cet établissement. »
>
> **Article 1er** — « La requête de la société Médiflash est **rejetée**. »

**Ce que l'arrêt JUGE réellement (C2)** : la seule profession **jugée** est
l'**aide-soignant** (Cons. 1 + Article 1er). L'arrêt **n'énumère PAS** la liste complète :
il renvoie à la lettre, qui vise « certains professionnels paramédicaux, dont les
aides-soignants ». La liste complète se vérifie dans la **copie primaire de la lettre
D21-031940 mise à disposition par la FEHAP** : aides-soignants, auxiliaires de
puériculture, infirmiers de bloc opératoire diplômés d'État, infirmiers anesthésistes
diplômés d'État, infirmiers en puériculture, conseillers en génétique et assistants
dentaires. Source primaire : [lettre interministérielle du 30/12/2021](https://www.fehap.fr/jcms/navigation-internet/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf).

**Mapping vers l'enum professions Jolene** (résout la divergence) : les 7 professions de
la lettre → **seules 4 existent dans Jolene** : `AS` (JUGÉ), `AUXILIAIRE_PUERICULTURE`,
`IBODE`, `IADE` (doctrine ministérielle). « Infirmier puériculteur », « conseiller en
génétique », « assistant dentaire » **ne sont pas des professions Jolene** → **sans objet**
(la divergence « infirmiers puériculteurs » ne concerne aucune cellule de la matrice).

- **Force des sources** : `AS` = **JUGÉ** (CE n°491128) ; `AUXILIAIRE_PUERICULTURE` / `IBODE`
  / `IADE` = **doctrine ministérielle** (lettre 30/12/2021) + absence de cadre d'exercice
  libéral. Centres de santé : **L.6323-1-5 CSP** (« Les professionnels qui exercent au sein
  des centres de santé sont **salariés** ») — **interdiction légale**, pas choix (C5).

#### Démonstration « ni statut autonome, ni nomenclature en propre » (professions de la lettre présentes dans Jolene)

| Profession | Cadre d'actes primaire | Nomenclature / statut libéral propre |
|---|---|---|
| `AUXILIAIRE_PUERICULTURE` | Depuis le 30/06/2026, **R.4311-5 CSP** : l'infirmier confie, sous sa responsabilité, certains actes aux auxiliaires qu'il encadre (la décision CE cite l'ancien R.4311-4, en vigueur lors du litige). | Aucun titre propre dans la NGAP ; l'auxiliaire n'est pas un facturant conventionnel autonome. |
| `IBODE` | **R.4311-11 et R.4311-11-1 CSP** : activité en bloc, présence de l'opérateur ; actes sur protocole signé par le chirurgien, en sa présence ou sur sa demande expresse selon l'acte. | Spécialisation du titre infirmier, sans statut conventionnel IBODE ni cotation NGAP IBODE en propre. |
| `IADE` | **R.4311-12 CSP** : activité sous le contrôle exclusif d'un médecin anesthésiste-réanimateur, présent sur site et pouvant intervenir à tout moment. | Spécialisation du titre infirmier, sans statut conventionnel IADE ni cotation NGAP IADE en propre. |

Référentiel de nomenclature contrôlé : [NGAP Assurance Maladie, version du 28/05/2026](https://www.ameli.fr/infirmier/exercice-liberal/facturation-remuneration/nomenclatures-ngap-lpp). L'absence est établie par la structure exhaustive de la NGAP (actes remboursables) combinée aux articles d'exercice ci-dessus ; elle ne transforme pas la doctrine ministérielle en décision juridictionnelle pour ces trois professions.

### 5.2 Matrice cible — 3 niveaux, TABLE PARAMÉTRÉE (zéro règle en dur), C3-C6

Lecture sur la **profession REQUISE PAR LA MISSION**, jamais sur les diplômes du soignant
(une IADE peut candidater à une mission IDE → règles **IDE** ; une mission IADE/IBODE est
salariée sans exception). **Défaut de la table (C6) : NON PROPOSÉ → salarié** — toute
combinaison absente tombe en salarié ; **AUTORISÉ n'existe que par cellule explicite et
sourcée**.

| Profession requise (mission) | Établissement privé (clinique…) | Centre de santé | Établissement public | Source / force |
|---|---|---|---|---|
| `AS` | **BLOQUÉ** | **BLOQUÉ** | **NON PROPOSÉ → salarié (défaut public)** | **JUGÉ** — CE n°491128 |
| `AUXILIAIRE_PUERICULTURE`, `IBODE`, `IADE` | **BLOQUÉ** | **BLOQUÉ** | **NON PROPOSÉ → salarié (défaut public)** | Doctrine — lettre 30/12/2021 (n° D21-031940), validée par CE n°491128 |
| `AES`, `PREPARATEUR_PHARMA` (sans exercice libéral) | **BLOQUÉ** | **BLOQUÉ** | **NON PROPOSÉ → salarié (défaut public)** | Absence de cadre libéral de la profession |
| **`MANIPULATEUR_RADIO`** (C4) | **BLOQUÉ** | **BLOQUÉ** | **NON PROPOSÉ → salarié (défaut public)** | L.4351-1 CSP : prescription et responsabilité d'un médecin ; aucune nomenclature d'actes en propre. |
| **`MEDECIN`, `DENTISTE`, `SAGE_FEMME`** (praticiens) | **AUTORISÉ** (contrat d'exercice libéral, honoraires facturés directement) | **BLOQUÉ** (C5) | salarié (défaut public — recrutement contractuel ; L.6146-2 CSP hors flux plateforme au lancement) | AUTORISÉ = cellule explicite ; centre de santé = **L.6323-1-5 CSP** |
| **`PHARMACIEN`** (C3) | **NON PROPOSÉ → salarié** | **NON PROPOSÉ → salarié** | salarié | Mission d'établissement = pharmacien de **PUI** (salarié) ; le remplacement de titulaire d'officine n'est pas une mission d'établissement Jolene |
| **`IDE`** + paramédicaux libéraux (`KINE`, `ORTHOPHONISTE`, `DIETETICIEN`, `ERGOTHERAPEUTE`, `PSYCHOMOTRICIEN`) | **NON PROPOSÉ → salarié par défaut** | **NON PROPOSÉ → salarié** | salarié | Faisceau : raisonnement CE transposable (subordination organisationnelle), soins inclus dans les tarifs de l'établissement, contrôles URSSAF — **choix de conformité Jolene** |
| *Toute combinaison absente* | **NON PROPOSÉ → salarié** (défaut C6) | idem | idem | Défaut table (testé) |

- **AUTORISÉ** = Jolene propose le libéral (cellule explicite sourcée uniquement).
- **NON PROPOSÉ** = Jolene ne propose que le salarié (risque de requalification), sans
  l'interdire juridiquement — choix de conformité.
- **BLOQUÉ** = interdiction sourcée, libéral non proposable.

### 5.3 Wordings par niveau (C7 — plus jamais de citation inexacte)

- **BLOQUÉ** :
  - `AS` : « L'exercice libéral n'est pas ouvert aux aides-soignants (**Conseil d'État,
    11/02/2025, n°491128**). Mission proposée en salarié. »
  - `AUXILIAIRE_PUERICULTURE` / `IBODE` / `IADE` (C7 — **double source, jamais « instruction »**) :
    « L'exercice libéral n'est pas prévu pour cette profession — **lettre interministérielle
    du 30 décembre 2021 (n° D21-031940), validée par le Conseil d'État (11/02/2025,
    n°491128)**. Mission proposée en salarié. »
    L'interface affiche séparément la **copie du texte original de la lettre** et
    l'**arrêt CE n°491128, cas aide-soignant uniquement** ; ce second lien ne vaut ni
    liste des professions ni jugement au fond pour les trois cellules de doctrine.
  - `AES` / `PREPARATEUR_PHARMA` / `MANIPULATEUR_RADIO` : « Cette profession n'a pas de cadre
    d'exercice libéral. Mission proposée en salarié. »
  - Praticien × **centre de santé** : « Au sein d'un centre de santé, les professionnels
    sont **salariés** (**art. L.6323-1-5 du code de la santé publique**). »
- **NON PROPOSÉ** : « Jolene propose cette mission en **salarié** : l'exercice libéral au
  sein d'un établissement expose à une **requalification**. » + lien **« comprendre pourquoi »**.
- **« Vacation »** : **retiré de l'UI** ou **défini comme un CDD court** (l'app n'a que
  **deux modes réels** : salarié / libéral). Retrait de la citation Mediflash générique des
  **4 surfaces** (`constantes.ts`, `FormulaireMission.tsx:650-654`, `ModalRecapMission.tsx`,
  `BannerMediflashExplication.tsx` — dont correction **n°488367 → n°491128**).
- **Reframe soignant IDE** (côté soignant) : « Tes missions **salariées** comptent dans les
  **3200 h** d'expérience requises pour l'installation en libéral. »

### 5.4 Encodage technique (C1-C7 intégrées — prêt pour relecture éclair)

- Table `matrice_modes_exercice(profession, type_etablissement, niveau, source_libelle,
  source_force)` — **seed cellule par cellule depuis 5.2**, **défaut = NON PROPOSÉ/salarié**
  (C6) ; **zéro règle juridique en dur** (`grep` doit le prouver). `fn_profession_peut_etre_liberal`
  et le trigger `dec_valider_compatibilite_mission_liberal` réécrits pour **lire la table** ;
  `fn_mode_exercice(profession, type_etablissement)` → `{niveau, source_libelle}` consommée
  par le formulaire.
- **Types d'établissement** : mapping `type` → catégorie {privé, centre_de_santé, public}
  (à dériver de `etablissements.type` / `finess_secteur`).
- **Tests** : un par niveau (`AS`→BLOQUÉ source CE n°491128 ; `DENTISTE`×clinique→AUTORISÉ ;
  `DENTISTE`×centre_de_santé→BLOQUÉ L.6323-1-5 ; `IDE`×clinique→NON PROPOSÉ ;
  `PHARMACIEN`→NON PROPOSÉ ; `MANIPULATEUR_RADIO`→BLOQUÉ) + **test du défaut** (combinaison
  inconnue → salarié) + « profil IADE × mission IDE → règles IDE » + e2e des 3 cas dans le
  formulaire.

**➡️ Dernière relecture éclair (Gabrielle)** : avant merge, la PR contiendra **(1) le diff
des wordings finaux tels qu'affichés** et **(2) le seed complet de la table** — relecture
sur ces deux artefacts uniquement, puis merge + cascade section D.

## Récapitulatif — à câbler avant échéance

| Sujet | Échéance | Type | Statut |
|---|---|---|---|
| DAC7 (collecte fiscale + déclaration) | 1ère clôture annuelle avec revenus | Dev | À faire |
| 242 bis — récapitulatif annuel | 1ère clôture annuelle | Dev | À faire |
| Réception factures via PA | 01/09/2026 | Admin (Gabrielle, 15 j) | À faire |
| Émission via PA (Factur-X → PA) | 09/2027 | Dev | À planifier |
| Verrou docs santé (VACCINATIONS/MEDECINE_TRAVAIL) | Fait | Dev (trigger) | ✅ Verrouillé |
| ARRET_MALADIE : attestation sur l'honneur + verrou | Fait (10/07/2026) | Produit + Dev | ✅ Livré — migration 20260710090000 (§1.4) |

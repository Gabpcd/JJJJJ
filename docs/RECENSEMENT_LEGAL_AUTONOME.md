# Recensement légal rétroactif — contenu à portée juridique exposé à l'utilisateur

> Section A3 de la règle **HARD STOP n°4 — légal utilisateur** (cf. CLAUDE.md).
> Recense ce qui a été shippé en mode autonome avec une portée juridique
> **exposée à l'utilisateur** (règle/citation/wording contractuel rendu en UI,
> toast, message RPC, email ou PDF). Objectif : traçabilité + statut par élément.
>
> **Statut** : `corrigé via section C` = fait partie de la matrice des modes
> d'exercice validée C1-C7 par Gabrielle (CONFORMITE.md §5) ·
> `à valider individuellement` = assertion juridique shippée en autonomie, à
> revalider par Gabrielle (hard stop n°4, rétroactif). Le GO donné porte sur C1-C7 ;
> les autres assertions restent hors de ce périmètre.

## Décompte

- Hits bruts examinés : ≈505 (grep légal `src/` + `supabase/`).
- Retenus **user-facing + portée juridique** : **28 items/groupes**.
  - → renvoyés à **C (matrice)** : **4**.
  - → **à valider individuellement** : **24**.
- Faux positifs écartés : ≈410 (erreurs d'auth « Non autorisé/Accès interdit » 401/403,
  démonstratif « ce/CE », enum technique `VACATION`, labels procéduraux URSSAF/CARPIMKO,
  noms de variables, commentaires internes).

## Bloc 1 — Restriction du mode d'exercice / jurisprudence Mediflash → **matrice (section C)**

| Élément (fichier:ligne) | Texte rendu (extrait) | Exposé où | Statut |
|---|---|---|---|
| `src/lib/constantes.ts:52-91` | `PROFESSIONS_NON_LIBERAL` + `LIBERAL_COMPATIBILITY` + `peutExercerLiberal()` ; commentaire « CE 11/02/2025 Mediflash + art. L8221-1 » | Logique pilotant toute l'UI de restriction | corrigé via C |
| `src/components/FormulaireMission.tsx:650-654` (filtre 628-634) | « Mode libéral non disponible : … non autorisé par la réglementation (salariat déguisé, cf CE 11/02/2025 arrêt Mediflash). » | Formulaire mission (étab) | corrigé via C |
| `src/components/mission/ModalRecapMission.tsx:95-100, 221-238` | « ⚠️ Mode libéral non autorisé … la réglementation interdit le mode libéral (salariat déguisé — CE 11/02/2025 arrêt Mediflash). » / « Salarié uniquement (CDD) » | Modale récap avant publication (étab) | corrigé via C |
| `src/components/BannerMediflashExplication.tsx:33-89` | « jurisprudence Mediflash (CE 11/02/2025) » ; « Conseil d'État … arrêt **n°488367** … salariat déguisé … ne peuvent pas être proposées en mode libéral » | Bannière pédagogique (soignant) | corrigé via C |

> ✅ **Incohérence tranchée et corrigée (C1)** : le numéro exact est **n°491128**
> (CE, 5e-6e chambres réunies, 11/02/2025, CETATEXT000051156546). Le n°488367
> était erroné ; le n°491130 désigne l'ordonnance de référé du 05/02/2024.

## Bloc 2 — Autres assertions juridiques user-facing → **à valider individuellement**

| # | Élément (fichier:ligne) | Portée juridique | Exposé où |
|---|---|---|---|
| 1 | `src/constantes/loi.ts:10-43` (+ `ModalCodeTravail.tsx`, `FormulaireRecurrence.tsx`, `CarteConformite.tsx`, `BlocConformite.tsx`, `BadgeMissionNuit.tsx`) | Repos 11h / 48h / travail de nuit (L3131-1, L3121-20, L3122-x) + **sanctions** (amende 750 €, arrêt DREETS) | Modales/cartes/badges conformité (étab) |
| 2 | `src/components/WarningRist.tsx` + `loi.ts:45-61` + `DecompositionFinanciere.tsx:159,168` | **Plafonds Loi Rist (décret 2023-920)** chiffrés par profession + auto-plafonnement | Saisie taux (étab) / décompte (soignant) |
| 3 | `src/pages/DetailMission.tsx:613-618` + `AdminConformite.tsx:133` | Requalification **CDI** au-delà de 150 j | Bandeau mission (étab) / admin |
| 4 | `supabase/functions/generate-invoice/index.ts:722-725` | Salarié → bulletin de paie, pas facture honoraires (mandat art. 289 I-2 CGI) | Message RPC bloquant |
| 5 | `src/components/etablissement/ModaleAnnulationMissionEtab.tsx:309-349` | **Obligation financière chiffrée** : indemnité précarité L1243-8 + clause pénale art. 1231-5 C. civ. | Modale annulation (étab) |
| 6 | `src/components/inscription/DeclarationEtudiant.tsx:76,110,119` | « tu ne peux pas encore exercer comme {X} … selon nos règles » (arrêté 03/02/2022) | Inscription soignant |
| 7 | `src/pages/ProfilSoignant.tsx:457,501` + `EditeurEquivalencesScolarite.tsx:93` | Équivalences « faisant fonction » (arrêté 03/02/2022) | Profil / éditeur admin |
| 8 | `src/components/parcours-liberal/QuizSecteurMedecin.tsx:82,92,116-117` | Éligibilité secteur conventionnel médecin (secteur 1/2) | Quiz parcours libéral |
| 9 | `src/components/parcours-liberal/CategorieSansHeuresCPAM.tsx:194` | « Art. R4322-71 CSP : exercice exclusif au domicile INTERDIT » | Checklist installation |
| 10 | `src/pages/DocumentsSoignant.tsx:546` | RCP obligatoire exercice libéral/mixte | Page documents |
| 11 | `src/pages/ContratMission.tsx:370,597` | CDD art. L1242-12/13 obligatoire | Page contrat |
| 12 | **Signature électronique** : `SignerContratOtp`, `CertificatSignature(Page)`, `ContratMission:515`, `MandatFacturation:317,452` | Valeur probante art. 1366-1367 C. civ. (eIDAS) | Flux signature |
| 13 | **Attestations pénales** : `DocumentsSoignant:108`, `FacturationEtablissement:1489`, `WorkflowPaiementMission:437`, `send-email:922` | Fausse déclaration → art. 441-1 / 441-7 C. pénal | Documents / paiement / email |
| 14 | `src/components/profil-soignant/SectionProfilPrincipal.tsx:958,523` | Cumul d'activités art. L1222-5 C. trav. | Profil soignant |
| 15 | **Mentions fiscales** : `FactureHonorairesCard`, `NoteHonoraires`, `facture-honoraires-pdf`, `mandat-facturation-pdf`, `MandatFacturation`, `generate-invoice` | TVA art. 293 B / 261-4 CGI ; mandataire 289 I-2 ; L441-9/10 C. com. | Factures/mandats (PDF+UI) |
| 16 | **Bulletin de paie** : `bulletin-paie-pdf:314-319`, `BulletinsPaie:282` | IFM L1243-8 / ICP L3141-22 / contestation L3245-1 / conservation L3243-4 | PDF paie |
| 17 | `src/components/ListeCandidatures.tsx:208-217` | Clause non-contournement (CGV art. 8) + grille dégressive | Liste candidatures (étab) |
| 18 | **RGPD** : `ConsentementGPS:50`, `DeclarationEmpechement:14`, `ConsentementPingGps`, `AdminDPIA`, `AdminRGPDTools:30,320` | Bases légales RGPD (6.1.a, art. 9, art. 17) | Consentements / admin |
| 19 | **DPAE** : `DPAEStatus:117`, `BandeauRappelDPAE:40`, `MesDPAE:199`, `SectionDpaeIdentite:134` | Obligation DPAE URSSAF (déjà cadrée CGU art. 4.5, Sprint 15) | Statuts/bandeaux DPAE |

*(19 lignes couvrant 24 items/groupes ; regroupements thématiques indiqués.)*

## Corpus légal officiel — hors périmètre A3 (documents légaux eux-mêmes)

`PageCGU`, `PageCGV` (non-contournement art. 6/8 + délais L.2192-10), `PageMentionsLegales`,
`PageConfidentialite`, `constantes/contratServiceEtablissement`, `constantes/mandatFacturation`,
`constantes/cessionCreance`. Relecture juriste souhaitable mais distincte du recensement A3.

## 5 items les plus à risque

1. **`FormulaireMission.tsx:652` + `ModalRecapMission.tsx:232`** — affirment + **bloquent** le libéral en citant l'arrêt Mediflash pour toute profession × étab.
2. **`BannerMediflashExplication.tsx` (historique, corrigé C1)** — citait l'arrêt n°488367 nominativement et généralisait le « CDD obligatoire ».
3. **`constantes.ts` (`LIBERAL_COMPATIBILITY`/`PROFESSIONS_NON_LIBERAL`)** — hard-bloque IBODE/IADE/PHARMACIEN, décisions produit habillées en contrainte réglementaire.
4. **`DeclarationEtudiant.tsx:110-119`** — restreint la profession déclarable en mêlant règle interne + arrêté 03/02/2022.
5. **`ModaleAnnulationMissionEtab.tsx:334,344`** — obligation financière chiffrée (L1243-8 + art. 1231-5 C. civ.) générée in-app.

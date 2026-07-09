# Mini-PR — Attestation d'empêchement impérieux (remplace l'arrêt maladie)

> **À exécuter** après la PR verrous/tests (#826) et la relecture-lot, **avant**
> la salve store-readiness. Décision validée (Gabrielle, 09/07/2026), cf.
> `docs/CONFORMITE.md §1.4`. **Ne rien coder avant ce jalon.**
>
> Objectif : supprimer tout stockage de donnée de santé (arrêt maladie) et le
> remplacer par une attestation sur l'honneur générique — zéro donnée de santé,
> verrou documents santé porté à 3/3.

## 1. Déclaration structurée (remplace l'upload certificat)

- Dans `src/pages/DetailMissionSoignant.tsx` (bloc « Je dois me désister pour
  raison médicale ») : **retirer** le `<input type=file>` + l'`INSERT
  documents_soignants(type_document='ARRET_MALADIE')` + l'appel `verify-document`.
- Remplacer par un formulaire **structuré, sans champ libre** :
  - Case **sur l'honneur** (« J'atteste sur l'honneur d'un empêchement
    impérieux m'empêchant d'assurer cette mission »).
  - **Dates d'indisponibilité** (début / fin).
  - Wording générique « **empêchement impérieux** » (santé, urgence
    familiale…) — **la nature/catégorie n'est ni demandée ni stockée** (le motif
    santé serait une donnée RGPD art. 9).
- Enregistrement : une déclaration d'annulation (dates + flag sur l'honneur),
  **aucun document, aucune catégorie de motif**.

## 2. Anti-abus (compteur paramétrable)

- **Audit** : chaque attestation horodatée dans `journaux_audit` (action ex.
  `ANNULATION_EMPECHEMENT_IMPERIEUX`, acteur = soignant, détails = dates + flag).
- **Compteur** : `fn_param_num('annulations_justifiees_max_12m', 2)`. Sur
  **12 mois glissants**, au-delà de N (défaut **2**) annulations justifiées :
  la **pénalité de score s'applique malgré l'attestation** + **passage en revue**
  (flag admin). En deçà : pas de pénalité.
- La logique de score d'annulation (fn existante) lit ce compteur au lieu de
  « certificat vérifié → pas de pénalité ».

## 3. Démantèlement + verrou 3/3

- Retirer `ARRET_MALADIE` de tout chemin d'upload frontend (grep :
  `DetailMissionSoignant.tsx`, `src/lib/documents.ts`, `ModalTeleversement.tsx`).
- Débrancher le pipeline `verify-document` pour ce type (plus jamais appelé).
- **Vérifier 0 document `ARRET_MALADIE` stocké** (prod = 0 au 09/07/2026 ;
  re-vérifier prod + purger d'éventuels seeds au moment de la PR).
- **Ajouter `ARRET_MALADIE`** à `fn_trg_bloquer_documents_sante`
  (migration `20260709180000`) → liste **3/3** :
  `('VACCINATIONS','MEDECINE_TRAVAIL','ARRET_MALADIE')`. Nouvelle migration
  (CREATE OR REPLACE de la fonction trigger).

## 4. CGU

- ✅ Vérifié : le wording d'annulation actuel des CGU **ne mentionne pas**
  « certificat médical » → rien à réaligner.
- ✅ Clause « Attestation d'empêchement impérieux » (fausse déclaration = respo
  utilisateur) **ajoutée** à l'amendement `docs/DRAFT_CGU_4_6_AMENDEMENT.md`.

## 5. Tests

- E2E : déclaration d'empêchement (dates + sur l'honneur) → pas de document créé,
  audit écrit ; au-delà du compteur → pénalité appliquée.
- Verrou : `INSERT documents_soignants(type_document='ARRET_MALADIE')` → **rejeté**
  (ajouter au spec `escrow-revenus-soignant.spec.ts` ou dédié).

## Ordre

PR verrous/tests (#826) → relecture-lot (session fraîche) → **cette mini-PR** →
salve store-readiness.

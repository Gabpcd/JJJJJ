# Annulation mission par l'établissement (Sprint 3.5 + Sprint 5.5 PR 3)

> Workflow d'annulation d'une mission par l'établissement avec **calcul transparent des conséquences financières** AVANT confirmation.
> Conforme art. **L1243-8 Code du travail** (indemnité précarité CDD) et art. **1231-5 Code civil** (clause pénale libéral).

## Grille 4 buckets Sprint 3.5

Détection automatique par `ModaleAnnulationMissionEtab` selon l'état de la mission + contrat + présences.

| Bucket | Conditions | Score étab | Indemnité soignant |
|---|---|---|---|
| **1. OUVERTE** | Mission non assignée | **0 pt** | 0 € |
| **2. ACCEPTEE sans contrat** | Soignant assigné, contrat non signé | **-3 pts** | 0 € |
| **3. CDD signé avant pointage** | Contrat CDD/CDDU/SALARIE `SIGNE_*` | **-10 pts** | **L1243-8** : durée × taux × 1.10 |
| **4. Libéral signé avant pointage** | Contrat REMPLACEMENT_LIBERAL `SIGNE_*` | **-10 pts** | **art. 1231-5** : 50/30/10% selon délai |
| **5. Après pointage** | Présence créée | **-20 pts** | Montant complet dû |

### Détail clause pénale libéral (art. 1231-5 Code civil)

| Délai jusqu'à mission | % du montant total |
|---|---|
| < 24h | **50%** |
| 24h-48h | **30%** |
| > 48h | **10%** |

## Calcul backend

Helper IMMUTABLE `fn_calculer_indemnite_annulation_etab(p_type_contrat, p_montant_total, p_duree_heures, p_taux_horaire, p_delta_mission)` retourne :

```json
{
  "montant": 220.00,
  "motif": "INDEMNITE_CDD_SIGNE_L1243_8",
  "base_calcul": "duree × taux × 1.10 (salaire + précarité 10%)",
  "type_contrat": "CDD"
}
```

### Motifs possibles
- `INDEMNITE_CDD_SIGNE_L1243_8` (CDD/CDDU/SALARIE)
- `CLAUSE_PENALE_LIBERAL_24H` (libéral, <24h)
- `CLAUSE_PENALE_LIBERAL_24_48H` (libéral, 24-48h)
- `CLAUSE_PENALE_LIBERAL_48H_PLUS` (libéral, >48h)
- `aucune_indemnite` (mission OUVERTE / ACCEPTEE sans contrat)

## Flux UI

### Composant `ModaleAnnulationMissionEtab` (`src/components/etablissement/ModaleAnnulationMissionEtab.tsx`)

1. **Récap mission** : intitulé, soignant, dates, durée × taux brut.
2. **Détection auto du bucket** :
   - Lookup `contrats_mission` (statut signature)
   - Lookup `presences` (pointage existant ?)
3. **Pré-calcul via `fn_calculer_indemnite_annulation_etab`** (IMMUTABLE, transparent).
4. **`ConsequencesBlock`** : affiche bucket + formule + montant + cadre légal cité.
5. **Motif structuré** (dropdown 6 valeurs) :
   - `BESOIN_DISPARU`, `BUDGET_REVU`, `REMPLACEMENT_INTERNE`, `CHANGEMENT_PLANNING`, `CAS_FORCE_MAJEURE`, `AUTRE`
6. **Texte libre** obligatoire (min 10 chars).
7. **Coche obligatoire** "J'ai compris les conséquences financières" si bucket impose pénalité.
8. Appel `fn_annuler_mission_etab(mission_id, motif_categorie, texte_libre)`.

### Intégrations

3 entry points migrés (suppression `handleAnnuler` legacy) :
- `DetailMission.tsx` (étab + admin)
- `ListeMissions.tsx`
- `DashboardEtablissement.tsx`

L'annulation **série** OUVERTE reste sur `ModalConfirmation` simple via `fn_annuler_serie_etablissement` (pas de pénalité applicable).

## RPC `fn_annuler_mission_etab`

### Signature
```sql
fn_annuler_mission_etab(p_mission_id uuid, p_motif_categorie text, p_texte_libre text) RETURNS jsonb
```

### Comportement
- Auth check (auth.uid() + mon_etablissement_id())
- Validation motif dans enum + texte ≥ 10 chars
- Détection du bucket via lookup contrats_mission + presences
- Calcul indemnité via helper IMMUTABLE
- Update mission → `ANNULEE_ETAB`
- Si présence → marque `motif_litige = 'ANNULEE_ETAB_APRES_POINTAGE'`
- Création `evenement_score_etab` (contestable=true)
- Enqueue `externalisation_actions` :
  - `STRIPE_REFUND` si paiement étab déjà encaissé
  - `STRIPE_PAYMENT` vers soignant si indemnité due
  - `AVOIR_PDF_GENERATION` si facture déjà émise
  - `DPAE_ANNULATION` si CDD signé
- Notification push + email au soignant
- Audit `MISSION_ANNULEE_ETAB`

### Codes erreur

| Code | Cas |
|---|---|
| `NON_AUTHENTIFIE` | Pas de session |
| `NON_AUTORISE` | Mission appartient à un autre étab |
| `MOTIF_INVALIDE` | Motif hors enum |
| `TEXTE_REQUIS` | Texte < 10 chars |
| `MISSION_INTROUVABLE` | UUID introuvable |
| `STATUT_INVALIDE` | Déjà annulée ou terminée |

## Tests Playwright (`e2e/flows/annulation-mission-etab.spec.ts`)

12 tests DB-level couvrant :
- 7 cas helper IMMUTABLE (CDD/CDDU/SALARIE × montants ; LIBERAL/REMPLACEMENT_LIBERAL × 3 plages délai ; type inconnu)
- 3 cas RPC : motif invalide, texte court, mission introuvable
- 2 E2E seed : mission OUVERTE, calcul 220€

Tests UI (modale + détection bucket auto) exclus, testés sur preview Vercel.

## Conformité légale

- **L1243-8 Code du travail** : indemnité de précarité 10% du salaire brut pour CDD rupture avant terme par l'employeur. Visible dans `base_calcul` retour helper.
- **art. 1231-5 Code civil** : clause pénale conventionnelle pour le libéral. Barème dégressif (50/30/10%) selon délai.
- **Score étab impacté contestable** via page score Sprint 3.5 (équivalent au workflow soignant).
- **Aucune action sans coche explicite** de compréhension par l'admin étab.

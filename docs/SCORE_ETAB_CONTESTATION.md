# Contestation événements score étab (Sprint 6)

> Fix **P1-9** audit Sprint 5. Permet à l'étab de contester les événements qui impactent son score qualité via la même infrastructure Sprint 3.5 que le soignant.

## Composants

- **`SectionEvenementsScore`** (nouveau Sprint 6 PR 4) — composant générique acceptant `type: 'SOIGNANT' | 'ETAB'`. Liste les événements 12 mois avec bouton "Contester" sur les contestables.
- **`MesReclamationsEtab`** (nouveau Sprint 6 PR 4) — page `/etablissement/mes-reclamations` listant les réclamations étab avec statut + décision admin.

## Réutilisation Sprint 3.5

L'infrastructure backend est intégralement réutilisée :

- **`fn_creer_reclamation_score(p_evenement_id, p_evenement_type, p_motif_categorie, p_texte_libre, p_justificatif?)`** : supporte déjà `p_evenement_type='ETAB'` depuis Sprint 3.5 PR 7.
- **`fn_mes_evenements_score(p_limit)`** : détecte automatiquement le rôle (soignant ou étab) via `mon_etablissement_id()` et renvoie les events de la bonne table.
- **`fn_mes_reclamations(p_statut)`** : renvoie les réclamations du `auth.uid()` quel que soit son rôle.
- **`ModaleReclamationScore`** : déjà générique avec prop `evenementType`.

## Workflow

```
Page /etablissement/score
  ↓
SectionEvenementsScore type="ETAB"
  → fn_mes_evenements_score → renvoie evenements_score_etab
  ↓
Pour chaque event impactant :
  • Affichage points (-X pts), motif, date
  • Si contestable : bouton "⚖️ Contester"
  • Si traité : badge décision admin
  ↓
Click "Contester" → ModaleReclamationScore evenementType="ETAB"
  • Sélection motif catégorie (URGENCE_MEDICALE, DEUIL, FORCE_MAJEURE, etc.)
  • Texte libre min 20 chars
  • Upload justificatif optionnel
  ↓
fn_creer_reclamation_score(p_evenement_type='ETAB', ...)
  → INSERT reclamations_score acteur=ETAB
  → notification admin via externalisation_actions
  ↓
Admin tranche via /admin/reclamations-score
  → MAINTENIR / REDUIRE / ANNULER
  → propagation event_score_etab.decision_admin
  → recalcul score étab
  ↓
Étab voit décision dans /etablissement/mes-reclamations
  → notification push + email
```

## Page mes réclamations

`MesReclamationsEtab` (`/etablissement/mes-reclamations`) :
- 2 KPI cards : nombre en attente / traitées
- Filtre statut (Toutes / En attente / Traitées)
- Liste cards : motif catégorie, texte libre, statut badge, justificatif (si joint)
- Si traitée : décision MAINTENIR/REDUIRE/ANNULER colorée + motif admin

## Garde-fous

- Réutilise UNIQUE constraint Sprint 3.5 : un événement = une seule réclamation simultanée
- 5 jours = expiration auto si admin pas traité (Sprint 3.5)
- Audit complet via `journaux_audit`
- Aucune action automatique sur compte ou score — décision admin uniquement

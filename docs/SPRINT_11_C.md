# Sprint 11-C — Admin mobile-first (AdminChorusPro + AdminDetailUtilisateur)

Troisième phase du Sprint 11 (admin complexes). 476L + 758L = 1234L au total. Audit-first appliqué : refactor ciblé sur les tables denses uniquement.

## PRs livrées

| PR | Titre | Approche | Fichier |
|---|---|---|---|
| #283 | `AdminChorusPro` mobile-first cards 3 tables | `hidden md:block` + cards parallèles sur Dashboard/Submissions/Config | `src/pages/admin/AdminChorusPro.tsx` |
| #284 | `AdminDetailUtilisateur` mobile-first 2 tables | `hidden md:block` + cards sur Documents+Missions | `src/pages/admin/AdminDetailUtilisateur.tsx` |
| #(this) | Doc Sprint 11-C | — | `docs/SPRINT_11_C.md` + CLAUDE.md |

## Décisions techniques

### AdminChorusPro — 3 tables refactorées

| Tab | Table desktop | Mobile cards |
|---|---|---|
| Dashboard | 5 cols (10 dernières submissions) | Facture + badge statut header, étab, type+date footer |
| Submissions | 8 cols (table principale) | Facture + badge statut header, grid label/value Étab/Soignant/Type, Créée+Sync footer, bouton "Voir le détail" plein largeur |
| Config étabs | 6 cols (SIRET + numéro structure + Actif switch) | Étab + Switch Actif header, grid SIRET (mono)/Num. structure/Code service, bouton "Éditer la configuration" plein largeur |

### AdminDetailUtilisateur — 2 tables refactorées, 4 tabs skip honnête

| Tab | Décision |
|---|---|
| Informations | Skip — InfoRow grid 1-2 cols déjà responsive |
| **Documents** | Refactor — Type+badge statut header, nom fichier break-words, footer Téléversé+Validité |
| **Missions** | Refactor — Intitulé+badge statut header, grid label/value Étab|Soignant/Début/Durée/Net (selon type), `statutLabel` mapping préservé |
| Score & Badges | Skip — 3 stat cards grid déjà responsive |
| Profil complet | Skip — 6 Cards grid 2 col + ProfileRow déjà responsive |
| Actions admin | Skip — 4 ActionCards grid 2 col déjà responsive |

## Pattern maintenu

Comme Sprint 11-A AdminGroupes / Sprint 11-B AdminModeration : `hidden md:block` + cards mobile parallèles. Pourquoi pas TableOuCartes :
- AdminChorusPro tables imbriquées dans Tabs avec sous-composants Dashboard/Submissions/Config (state local)
- AdminDetailUtilisateur tables imbriquées dans Tabs avec state global type='soignant'|'etablissement' affectant colonnes conditionnelles

## Préservé

- AdminChorusPro : 6 KPIs Dashboard, filtres Submissions, `ChorusSubmissionDetailDialog` + `ChorusConfigEtabDialog`, actions resubmit/toggleActif/setEditing/setDetail
- AdminDetailUtilisateur : 6 Tabs structure, banner alertes responsive, 2 ModalConfirmation, toutes actions admin (suspendre, réinitialiser mdp, promouvoir admin, supprimer compte, rappel documents), audit RGPD `ADMIN_CONSULTATION_*`, helpers VerifRow/STATUTS_VERIFICATION/TYPES_DOCUMENTS

## Reporté Sprint 11-D

| Sprint | Page | Justification |
|---|---|---|
| 11-D | AdminFacturation (544L tabs+bulk+expandable+multi-status) | La plus complexe — workflows Stripe Connect, Chorus Pro, bulk actions, expandable rows |

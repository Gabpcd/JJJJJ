# Sprint 11 — Admin mobile-first complet (A → D)

Sprint 11 finalise le mobile-first sur **les 7 pages admin reportées** Sprint 8.5. Pré-launch, Gabrielle voulait toutes les pages admin mobile-first AVANT mise en prod.

## Phases livrées

| Phase | Pages | PRs | Sha range |
|---|---|---|---|
| 11-A | AdminFinances + AdminGroupes | 3 (#277-#279) | 6a53a3b0 → 561dbcdc |
| 11-B | AdminConformite + AdminModeration | 3 (#280-#282) | 37f1c379 → 9013599f |
| 11-C | AdminChorusPro + AdminDetailUtilisateur | 3 (#283-#285) | f9351c1c → c99e88cf |
| 11-D | AdminFacturation (la plus complexe) | 2 (#286 + doc) | 6eb4d247 → (this) |
| **Total** | **7 pages** | **11 PRs** | — |

## Pages refactorées

| Page | Lignes | Tables refactorées | Approche |
|---|---|---|---|
| AdminFinances | 364 | 1 (9 cols) | `TableOuCartes` |
| AdminGroupes | 515 | 1 (9 cols inline edit) | `hidden md:block` + cards parallèles |
| AdminConformite | 304 | 1 (drill-down 5-6 cols × 7 indicateurs) | Refactor `champs[]` unifié |
| AdminModeration | 438 | 2 (Documents 4 cols, Identité 8 cols) | `hidden md:block` + cards |
| AdminChorusPro | 476 | 3 (Dashboard 5, Submissions 8, Config 6) | `hidden md:block` + cards |
| AdminDetailUtilisateur | 758 | 2 (Documents 5, Missions 6-7) | `hidden md:block` + cards |
| AdminFacturation | 544 | 1 + nested expandable (10 + 8 cols) | Extraction hook + component + `hidden md:block` |
| **Total** | **3399** | **11 tables** | — |

## Décisions techniques transversales

### Pattern `hidden md:block` privilégié sur TableOuCartes

`TableOuCartes` ne supporte pas :
- **Expansion** (drill-down state local, expandable rows) → AdminConformite, AdminFacturation, AdminGroupes
- **State local per-row** (édition inline, email form, bulk select avec expand) → AdminGroupes, AdminFacturation
- **Tabs imbriquées** (state global affectant colonnes conditionnelles) → AdminModeration, AdminChorusPro, AdminDetailUtilisateur

Solution : table desktop préservée via `hidden md:block` + cards mobile parallèles via `md:hidden`. Plus simple, préserve toutes les fonctionnalités.

### Refactor `champs[]` unifié (AdminConformite uniquement)

Quand la définition colonnes + rendu est **purement déclarative** (pas de state local par row), pattern `champs: Array<{ titre, render, primary? }>` partage 1 seule config entre table desktop et cards mobile. Élimine duplication des 7 indicateurs.

### Audit-first par tab (AdminModeration)

Page composite avec 6 tabs : audit lucide révèle Litiges + Évaluations déjà mobile-friendly (cards). Skip honnête. Refactor uniquement Documents (4 cols) + Identité (8 cols, la pire UX).

### Page-detail audit (AdminDetailUtilisateur)

758L, 6 tabs : audit révèle 4 tabs déjà responsive (Informations grid 1-2 cols, Score 3 stats, Profil 6 cards 2 cols, Actions admin ActionCards). Refactor uniquement Documents + Missions.

## Préservé transversalement

- **Toutes les actions admin RPC** : `fn_confirmer_virement_admin`, `fn_rejeter_virement_admin`, `fn_auto_facturation_mensuelle`, `fn_export_fec`, `fn_admin_conformite_detail`, `fn_admin_incoherences_identite`, etc.
- **Édition inline** (taux commission AdminGroupes, email forms) avec state local par row
- **Modales** existantes : ChorusSubmissionDetailDialog, ChorusConfigEtabDialog, LitigeResolutionModal, etc.
- **Bulk actions** : BoutonsBulkFactures (Stripe/Chorus/CSV) intact
- **PDF generation** client-side (jsPDF)
- **CSV exports** (FEC, Rapport mensuel, Cohérence)
- **Audit RGPD** ADMIN_CONSULTATION_SOIGNANT/ETABLISSEMENT
- **Navigation détails** `/admin/utilisateurs/{id}`, `/admin/missions?mission={id}`, `/admin/impayees`

## Bilan Sprint 11

- **11 PRs livrées en prod**
- **7 pages admin mobile-first 100%** (les 7 reportées Sprint 8.5)
- **11 tables denses refactorées** (3399 lignes touchées)
- **0 PR ouverte** post-Sprint
- **Audit-first appliqué systématiquement** : skip honnête sur ce qui était déjà responsive
- **Pas de bulk refactor TableOuCartes** : décisions ciblées par contrainte (expansion, state local, tabs)

## Reportés post-launch

Aucun reporté. Tous les chantiers admin mobile-first du backlog Sprint 8.5 ont été traités Sprint 11. Pages admin restantes (AdminDashboard, AdminReclamationsScore, AdminAlertesPointage, AdminExternalisationsActions) étaient déjà cards Sprint 8.5 ou ne nécessitaient pas de refactor.

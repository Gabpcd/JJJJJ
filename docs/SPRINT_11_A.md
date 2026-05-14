# Sprint 11-A — Admin mobile-first (AdminFinances + AdminGroupes)

Première phase du Sprint 11 (pages admin complexes reportées Sprint 8.5). Pré-launch : Gabrielle veut TOUTES les pages admin mobile-first.

## Contexte

Sprint 8.5 (Admin mobile-first) avait livré 8 PRs mais 7 pages reportées car composites (multi-tabs, expandable, bulk, etc.). Sprint 11 traite ces 7 pages en 4 sprints-thèmes (A → B → C → D).

Sprint 11-A : les deux pages les plus simples du backlog.

## PRs livrées

| PR | Titre | Approche | Fichier(s) |
|---|---|---|---|
| #277 | `AdminFinances` mobile-first TableOuCartes | TableOuCartes pattern | `src/pages/admin/AdminFinances.tsx` |
| #278 | `AdminGroupes` mobile-first cards par clinique | `hidden md:block` + cards parallèles | `src/pages/admin/AdminGroupes.tsx` |
| #(this) | Doc Sprint 11-A | — | `docs/SPRINT_11_A.md` + CLAUDE.md |

## Décisions techniques

### AdminFinances → TableOuCartes

Table "Détail par établissement" (9 colonnes) refactorée vers le pattern `<TableOuCartes>` Sprint 8 BIS PR 1. Renderings desktop/mobile séparés via le viewport hook interne. Tri par colonne **conservé** :
- Desktop : click header column → toggle sort
- Mobile : select dropdown + bouton ↑↓

Pas d'inline editing dans cette table → TableOuCartes était la bonne approche directe.

### AdminGroupes → cards parallèles

Tableau natif HTML "Détail par clinique" (9 colonnes) avec **email form inline en `colSpan=9`** et **édition taux per-row**. Ces patterns (expansion + state local par row) ne sont **pas supportés par TableOuCartes**.

Solution : `hidden md:block` sur la table desktop existante + section `md:hidden space-y-3` avec cards mobile équivalentes. Email form inline préservé sous chaque card mobile. Édition taux inline préservée avec Input compact.

## Préservé

- AdminFinances : tri par colonne (sortKey/sortDir), navigation `/admin/utilisateurs/{id}` et `/admin/impayees`, export CSV, KPIs grid responsive, chart 6 mois
- AdminGroupes : KPIs grid 2/4/7, header `flex-col sm:flex-row`, BFA banner, édition taux groupe, email groupe, navigation détail clinique

## Reportés Sprint 11-B/C/D

| Sprint | Pages | Justification |
|---|---|---|
| 11-B | AdminConformite (45 refs Table), AdminModeration (6 tabs) | Très élevée |
| 11-C | AdminChorusPro (3 tables workflow), AdminDetailUtilisateur (758L, multi-sections) | Élevée |
| 11-D | AdminFacturation (544L, tabs + expandable + bulk + multi-status) | La plus complexe |

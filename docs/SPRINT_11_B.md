# Sprint 11-B — Admin mobile-first (AdminConformite + AdminModeration)

Deuxième phase du Sprint 11 (admin complexes). 304L + 438L = 742L au total. Audit-first appliqué : décision refactor par section/tab, pas blanket TableOuCartes.

## PRs livrées

| PR | Titre | Approche | Fichier |
|---|---|---|---|
| #280 | `AdminConformite` mobile-first cards label/value | Refactor `Indicateur` interface vers `champs[]` unifié desktop+mobile | `src/pages/admin/AdminConformite.tsx` |
| #281 | `AdminModeration` mobile-first cards Documents+Identité | `hidden md:block` + cards parallèles sur 2 tabs (Documents 4 cols, Identité 8 cols) | `src/pages/admin/AdminModeration.tsx` |
| #(this) | Doc Sprint 11-B | — | `docs/SPRINT_11_B.md` + CLAUDE.md |

## Décisions techniques

### AdminConformite — Refactor unifié `champs[]`

Le contrat `Indicateur` original couplait colonnes (string) + renderRow (TableCell hardcodés). Impossible à réutiliser pour mobile sans dupliquer la logique 7 fois.

**Refactor** : `champs: Array<{ titre, render, primary? }>` — un seul endroit pour définir colonnes + rendus, partagé entre table desktop et cards mobile.

**Avantage** : 7 indicateurs (violations_repos_11h, alertes_48h, docs_expires, docs_en_attente, cddu_repetitifs, soignants_sans_docs, missions_sans_contrat) déclinés uniformément. Mobile cards = primary field en header bold + autres champs en label/value flex.

### AdminModeration — Refactor partiel par tab

Page composite avec 6 tabs et 2 sous-composants externes. Audit-first :

| Tab | État pré-refactor | Décision |
|---|---|---|
| Litiges | Déjà cards mobile-friendly | **Skip** |
| Évaluations | Déjà cards | **Skip** |
| Avoirs | Sous-composant `<AvoirsList>` externe | **Hors scope** ce fichier |
| Legacy | Sous-composant `<LitigesLegacyTab>` externe | **Hors scope** ce fichier |
| **Documents** | Table 4 cols scroll-x | **Refactor** : `hidden md:block` + cards |
| **Identité** | Table 8 cols (la pire UX mobile) | **Refactor** : `hidden md:block` + cards avec grid 3 cols pour matches ✓/✗ |

Bonus : `TabsList` wrappée dans `overflow-x-auto + w-max` (6 tabs ne tenaient pas en flex-wrap sur 375px → scroll horizontal natif).

## Pas TableOuCartes — pourquoi

Comme Sprint 11-A AdminGroupes, ces pages ont :
- Tables imbriquées dans des Cards d'expansion (drill-down state local) — AdminConformite
- Tables imbriquées dans des Tabs avec state complexe — AdminModeration

TableOuCartes wrap mal ces structures. Pattern `hidden md:block` + cards parallèles plus simple, préserve toutes les fonctionnalités existantes.

## Préservé

- AdminConformite : 7 indicateurs, drill-down toggle, helpers Lien*, stopPropagation, grid KPIs responsive
- AdminModeration : actions RPC (validerDocument, rejeterDocument), navigation `/admin/utilisateurs/{id}`, logique matches upper-case identité, sous-composants externes (Litiges, Avoirs, Legacy, Evaluations)

## Reportés Sprint 11-C/D

| Sprint | Pages | Justification |
|---|---|---|
| 11-C | AdminChorusPro (476L), AdminDetailUtilisateur (758L) | Élevée |
| 11-D | AdminFacturation (544L tabs+bulk+expandable) | La plus complexe |

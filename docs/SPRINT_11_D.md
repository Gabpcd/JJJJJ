# Sprint 11-D — Admin mobile-first AdminFacturation (final)

Quatrième et dernière phase du Sprint 11. La page admin **la plus complexe** : 544L, table 10 cols + nested expandable 8 cols + bulk actions Stripe Connect/Chorus Pro/CSV + multi-status workflows (BROUILLON, EMISE, VIREMENT_DECLARE, PAYEE, EN_RETARD, ANNULEE).

## Audit-first

Le brief initial du Sprint 11 supposait que AdminFacturation avait des tabs Soignants/Etablissements/Avoirs. L'audit révèle qu'il s'agit d'une **page unique** avec :
- 1 table principale 10 cols (Checkbox + Expand + N° + Étab + HT + TTC + Missions + Émise + Statut + Actions)
- 1 nested expandable table 8 cols (Intitulé + Soignant + Profession + Dates + Heures + Taux + Brut + Commission HT)
- Bulk selection via Checkbox row + master + composant externe `BoutonsBulkFactures` (Stripe/Chorus/CSV)
- Row-level actions : Confirmer/Rejeter pour `VIREMENT_DECLARE`, Download PDF pour tous

→ **2 PRs** au lieu des 3-4 prévues initialement (page unique = 1 entité logique).

## PRs livrées

| PR | Titre | Approche | Fichier |
|---|---|---|---|
| #286 | `AdminFacturation` mobile-first cards + expandable | Extraction logique fetch missions vers hook + extraction rendu vers component double-mode + `hidden md:block` cards mobile | `src/pages/admin/AdminFacturation.tsx` |
| #(this) | Doc Sprint 11-D + Sprint 11 FINAL (A→D) | — | `docs/SPRINT_11_D.md` + `docs/SPRINT_11_FINAL.md` + CLAUDE.md |

## Refactor structurel PR 1

1. **Extraction** logique fetch missions → hook `useMissionsFacture(factureId)` (réutilisable desktop + mobile)
2. **Extraction** rendu missions → `FactureDetailContenu` component avec `mode: 'desktop' | 'mobile'`
3. Desktop : `FactureDetailRow` (TableRow colSpan=10) wrappe le mode desktop
4. Mobile : `FactureDetailMobile` (div standalone) wrappe le mode mobile inline dans la card

Avantage : 1 fetch logic + 1 rendering logic partagés. Pas de duplication. La logique métier (clickable soignant/mission, formatage Euros, profession) reste centralisée.

## Cards mobile

- **Bandeau global** "Tout sélectionner" + compteur sélectionnés en haut (bulk control mobile-friendly)
- **Cards par facture** :
  * Checkbox + N° facture + badge statut header
  * Établissement clickable (navigate `/admin/utilisateurs/{id}`)
  * Grid 2x2 : HT / TTC / Missions / Émise
  * Ref virement (si VIREMENT_DECLARE)
  * 2 boutons grid 2 cols Confirmer + Rejeter si VIREMENT_DECLARE
  * Bouton "Voir/Masquer missions" flex-1 + Download PDF
  * Expand inline : `FactureDetailMobile` cards missions (nested cards label/value)
- Card highlight `border-primary bg-primary/5` si sélectionnée
- Touch targets 36px partout

## Préservé entièrement

- `BoutonsBulkFactures` composant externe (Stripe Connect, Chorus Pro, CSV export) inchangé, visible mobile+desktop
- KPIs Total HT/TTC `grid-cols-2 max-w-md`
- Filtres Recherche + Statut `flex-col sm:flex-row`
- 4 boutons header (Exporter FEC, Rapport PDF, Générer factures, Prélever SEPA) avec `flex-wrap` déjà responsive
- Toutes les RPC actions :
  - `fn_confirmer_virement_admin`
  - `fn_rejeter_virement_admin`
  - `fn_auto_facturation_mensuelle`
  - `fn_export_fec`
  - Edge function `sepa-auto-charge`
- PDF generation client-side (jsPDF) intact (`genererFacturePDF` + `genererRapportPDF`)

## Pas TableOuCartes — pourquoi

Page unique avec expandable rows + bulk selection state local (`selectedIds: Set<string>` + `expandedId: string | null`). TableOuCartes ne supporte pas l'expansion. Pattern `hidden md:block` + cards parallèles plus simple, préserve `expandedId` et permet d'utiliser le même hook `useMissionsFacture` pour les deux modes.

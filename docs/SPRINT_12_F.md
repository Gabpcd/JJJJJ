# Sprint 12-F — Migration Card shadcn → CardY2K complète

Sprint 12-F achève l'adoption Y2K en finalisant la migration `<Card>` shadcn → `<CardY2K>` qui était en pause depuis Sprint 12-D (skip pour refactor structurel risqué).

## PRs livrées

| PR | # | Chantier | Livré |
|---|---|---|---|
| 12-F-1 | #307 | Foundation CardY2K subcomponents | Drop-in shadcn (CardY2KHeader/Title/Description/Content/Footer) + prop `noPadding` |
| 12-F-2 | #308 | Migration Card user-facing | 17 Cards sur 4 pages (Premium x2 + ContratPlateforme + FacturationEtablissement) |
| 12-F-3 | #309 | Migration Card admin part 1 | 49 Cards sur 5 pages (AdminDetailUtilisateur 19 + AdminStatus 9 + AdminDashboard 8 + AdminFinances 7 + AdminAffacturage 6) |
| 12-F-4 | #310 | Migration Card admin part 2 + components | 19 Cards sur 9 fichiers (7 pages admin + 2 components admin/litiges) |
| 12-F-5 | (this) | Doc Sprint 12-F + audit final adoption Y2K | docs/SPRINT_12_F.md + docs/SPRINT_12_FINAL.md update + CLAUDE.md |
| **Total** | **5 PRs** | — | **85 Cards migrés + 1 foundation** |

## Détail PR 12-F-1 — Foundation subcomponents

Sprint 9-B avait créé `<CardY2K>` simple (variant default/holographic/glass) sans sous-composants. Le pattern shadcn avec `<CardHeader><CardTitle/></CardHeader><CardContent/>` n'était donc pas migrable drop-in.

PR #307 ajoute :
- `CardY2KHeader` : `flex flex-col space-y-1.5 p-6`
- `CardY2KTitle` : `text-2xl font-semibold leading-none tracking-tight`
- `CardY2KDescription` : `text-sm text-jolene-bubblegum` (palette Y2K rose)
- `CardY2KContent` : `p-6 pt-0`
- `CardY2KFooter` : `flex items-center p-6 pt-0`

Plus prop `noPadding` sur `<CardY2K>` pour désactiver le `p-5` par défaut quand les sous-composants apportent leur propre padding.

**Migration drop-in possible** sans refactor structurel :
```tsx
// before
<Card><CardHeader><CardTitle>X</CardTitle></CardHeader><CardContent>Y</CardContent></Card>
// after (drop-in pur)
<CardY2K noPadding>
  <CardY2KHeader><CardY2KTitle>X</CardY2KTitle></CardY2KHeader>
  <CardY2KContent>Y</CardY2KContent>
</CardY2K>
```

## Détail PR 12-F-2 — User-facing (17 Cards)

| Page | Cards | Variants | Notes |
|---|---|---|---|
| PremiumSoignant | 3 | 2 holographic + 1 default | Pricing Premium + Pack Libéral → hero holographic |
| PremiumEtablissement | 2 | 1 holographic + 1 default | Pack Étab Pro → holographic |
| ContratPlateforme | 3 | 3 default | Borders légales préservées (border-success/30, border-warning/30) |
| FacturationEtablissement | 9 | 9 default | Collapsible sections + empty states + historique + exports |

**Levée du blocage Sprint 12-D** : refactor structurel n'était plus nécessaire grâce aux sous-composants drop-in PR 1.

## Détail PR 12-F-3 — Admin part 1 (49 Cards / 5 fichiers)

| Page | Cards |
|---|---|
| AdminDetailUtilisateur | 19 |
| AdminStatus | 9 |
| AdminDashboard | 8 |
| AdminFinances | 7 (pré-migrés) |
| AdminAffacturage | 6 (pré-migrés) |

100% variant default + 100% `noPadding`. Borders sémantiques préservées (border-destructive/30, border-warning/30, border-primary/30).

## Détail PR 12-F-4 — Admin part 2 + components (19 Cards / 9 fichiers)

| Fichier | Cards |
|---|---|
| AdminMandatsFacturation | 5 |
| AdminAuditRLS | 4 |
| AdminConformite | 3 |
| AdminFacturation | 2 (pré-migrés) |
| AdminModeration | 1 |
| AdminImpayees | 1 |
| AdminGroupes | 1 |
| LitigesList | 1 |
| LegacyRecategorisation | 1 |

**Préservations E2E critiques** : `data-testid="litige-card"` / `data-litige-id` / `data-gravite` / `data-categorie` (sélecteurs E2E Playwright préservés sur LitigesList).

## Stratégie variant transversal Sprint 12-F

| Contexte | Variant Y2K | Cards concernées |
|---|---|---|
| Pricing hero (Premium, Pack) | `holographic` | 3 (PremiumSoignant + PremiumEtablissement) |
| Tous autres contextes (contrats / facturation / admin) | `default` | 82 |
| Modal overlay glassmorphism | `glass` | 0 (pas de cas trouvé) |

## Adoption Card finale (avant vs après Sprint 12-F)

| Composant | Avant Sprint 12 | Avant Sprint 12-F | Après Sprint 12-F |
|---|---|---|---|
| `<CardY2K>` ouvertures | 0 | 1 (foundation seule) | **~88-90 ouvertures** |
| `<Card>` shadcn ouvertures | 86 | 86 | **0** (100% migré) |

**Adoption CardY2K : 0% → 100%** sur user-facing + admin.

## Bilan Sprint 12-F

- **5 PRs livrées en prod**
- **85 Cards migrés** au total (17 user-facing + 49 admin part 1 + 19 admin part 2)
- **1 foundation** ajoutée (CardY2K subcomponents + noPadding)
- **0 PR ouverte** post-sprint
- **0 régression CI**
- **0 skip Card** Sprint 12-F (tous migrés, levée du blocage Sprint 12-D)

### Préservations critiques systématiques
- Bordures sémantiques (success/destructive/warning/orange/primary borders avec couleurs et opacités)
- E2E test selectors (data-testid, data-litige-id, data-gravite, data-categorie)
- Animations CSS (animate-in slide-in-from-top-2 fade-in-0)
- Dynamic className conditionnel (ring-2 ring-primary, urgence color computed)
- Padding modifiers internes (pt-4, pt-5, pt-6, space-y-3/4/5/6, p-0 wrapper table)
- Helpers TypeScript et composants custom (ActionCard non-shadcn intact)

## Conclusion Sprint 12 complet (A → F)

Sprint 12-F finalise l'adoption Y2K complète qui était l'objectif Sprint 9. Avec Sprint 12-F :
- **CardY2K passe de foundation seule à adoption 100%**
- Sprint 12 (A → F) cumule **~365 migrations Y2K** au total (66 boutons + 6 dashboards + 36 KPIs + 103 badges + 46 Mascotte + 85 Cards + 1 destructive variant + foundations + cleanup)
- **27 PRs livrées** sur Sprint 12 complet
- **0 dette Y2K** : aucun composant shadcn legacy restant sur les cas user-facing + admin migrables

Reportés post Sprint 12 (composants custom non-shadcn nécessitant réécriture interne) :
- BadgeRPPS / BadgeNiveau / BadgeStatut / BadgePalier (composants custom métier — réécrire en interne avec BadgeY2K)
- animations.ts spring élargi (DialogResponsive entrance, FAB scale, notifications slide)
- ListeSwipe adoption pages soignant (HistoriqueMissions, MesCandidatures)
- ~239 `<Button>` shadcn restants : composants partagés (header/footer/nav), icon-only back nav, variant=link, asChild dans dialogs/tooltips/dropdowns (cas légitime shadcn)

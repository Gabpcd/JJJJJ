# Sprint 12-C — Adoption Y2K Cards + KPIs visuels

Sprint 12-C continue l'adoption Y2K après Sprint 12-B (66 boutons critiques migrés). Focus : **CarteKPI dashboards + variant destructive BoutonY2K + refactor dashboards CSS legacy**.

## PRs livrées

| PR | # | Chantier | Livré |
|---|---|---|---|
| 12-C-1 | #294 | BoutonY2K variant destructive | Gradient `#FF4D6B → #FF6BBE` rouge-rose holographique, shadow rose vif. Foundation pour migrer les 3 destructive skippés Sprint 12-B. |
| 12-C-2 | #295 | Dashboards `.btn-primary` CSS → BoutonY2K | 6 quick actions header dashboards soignant + étab. Migration `<button className="btn-primary/secondary">` → `<BoutonY2K variant="primary/secondary">`. |
| 12-C-3 | #296 | CarteKPI → CarteKPIY2K | **36 KPIs sur 9 pages** : DashboardSoignant (3) + DashboardEtablissement (7) + DashboardGroupe (4) + MesGains (4) + PageStripeConnect (3) + PoolUrgenceEtablissement (3) + AdminDashboard (8) + AdminDemo (4) + FacturationEtablissement (import cleanup). Variants : 8 holographic, 26 default, 2 soft. |
| 12-C-4 | (this) | Documentation Sprint 12-C | docs/SPRINT_12_C.md + CLAUDE.md |
| **Total** | **4 PRs** | — | **42 migrations + 1 nouveau variant + 1 import cleanup** |

## Stratégie variant Y2K

### BoutonY2K destructive (#294)
- Gradient `#FF4D6B` (rouge) → `#FF6BBE` (rose Jolene signature) — agressif mais cohérent avec palette
- Shadow `rgba(255,77,107,0.45)` au repos, intensifiée hover
- focus-visible ring rouge sang `#FF4D6B`
- prefers-reduced-motion respecté (pas de scale)
- Usage typique : "Révoquer mandat", "Supprimer compte", "Annuler définitivement"

### Dashboards CSS → BoutonY2K (#295)
- 6 boutons CSS legacy (`<button className="btn-primary">`) refactorés vers `<BoutonY2K>` component-based
- Icônes lucide passées via `iconeGauche={<Icon className="h-4 w-4" />}` (cohérent API Y2K)
- Touch targets : `size="sm"` (36px) pour quick actions, `size="md"` (44px) pour CTA principaux

### CarteKPI tiering visuel (#296)
Règle d'attribution variant :
- **First KPI of a hero grid** → `holographic` (gradient hero rose→mauve, texte blanc, shadow holographique)
- **Most KPIs** → `default` (surface cloud + border rose subtile)
- **"Total tout temps" / "Total reçu"** → `soft` (gradient lavender→rose pâle, calme financier)

Distribution finale : **8 holographic, 26 default, 2 soft** sur 36 KPIs.

## Décisions techniques

### Mapping CarteKPI legacy → CarteKPIY2K

| Legacy | Y2K | Notes |
|---|---|---|
| `icone={Briefcase}` ref | `icone={<Briefcase className="h-4 w-4" />}` | LucideIcon ref → JSX element |
| `lien="/path"` | `onClick={() => navigate("/path")}` | useNavigate déjà importé partout |
| `sousLabel="..."` | `contexte="..."` | Sémantique conservée |
| `couleurIcone="text-warning"` | drop | Palette Y2K rose unifiée (perte semantic couleur acceptée) |
| `couleurFond="bg-warning/10"` | drop | Idem |

### Card → CardY2K — SKIPPED Sprint 12-C

L'audit a révélé que `<Card>` shadcn est utilisé sur :
- **4 pages user-facing** : PremiumSoignant, PremiumEtablissement, ContratPlateforme, FacturationEtablissement
- **15 pages admin** : reportées Sprint 12-E

Migration `<Card><CardHeader><CardTitle/></CardHeader><CardContent/></Card>` → `<CardY2K>` nécessite refactor structurel (flattening de la composition shadcn). Risque visuel significatif sur des pages contractuelles/finance où le layout doit rester stable. **Skip honnête** : reporté Sprint 12-E avec audit dédié par page.

### Pages skippées (Card)
- PremiumSoignant + PremiumEtablissement : layout grid 2-cols pricing — refactor visuel risqué
- ContratPlateforme : structure légale formelle — pas de raison de la changer maintenant
- FacturationEtablissement : déjà migré BoutonY2K Sprint 12-B (#290), Cards utilisées pour dialogs Stripe/Chorus — laisser shadcn dans contexte modal

## Bilan Sprint 12-C

- **4 PRs livrées en prod**
- **42 migrations Y2K** (36 CarteKPI + 6 BoutonY2K dashboards)
- **1 nouveau variant** (destructive BoutonY2K)
- **0 PR ouverte** post-sprint

### Adoption ratios (cumulé Sprint 12-B + 12-C)

| Composant Y2K | Avant Sprint 12 | Après 12-B | Après 12-C |
|---|---|---|---|
| `<BoutonY2K>` | 2 (0.9%) | 68 | 74 |
| `<CarteKPIY2K>` | 0 (0%) | 0 | 36 |
| `<CardY2K>` | 0 (0%) | 0 | 0 (reporté 12-E) |

### Restant cible Sprint 12-D/E
- **Card → CardY2K** : 19 fichiers (Sprint 12-E avec audit visuel par page)
- **BadgeY2K** : adoption EmptyState + cards mission (Sprint 12-D)
- **Mascotte** : ajout dans EmptyStates (Sprint 12-D)
- **ListeSwipe** : adoption pages soignant (HistoriqueMissions, MesCandidatures) — Sprint 12-D ou 12-E
- **animations.ts** : intégration `EASINGS.bouncy/soft/snap` sur interactions (Sprint 12-E)

## Reportés Sprint 12-D/E

- **12-D** : BadgeY2K + Mascotte sur EmptyState (44 EmptyStates audités Sprint 12)
- **12-E** : CardY2K admin pages (19 fichiers + 2 components) + animations.ts adoption + audit final

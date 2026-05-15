# Sprint 12-D — Mascotte EmptyState + animations + cards restantes

Sprint 12-D continue l'adoption Y2K post Sprint 12-C : Mascotte sur EmptyStates + animations.ts adoption sur composants Y2K core + audit honnête Card → CardY2K.

## PRs livrées

| PR | # | Chantier | Livré |
|---|---|---|---|
| 12-D-1 | #298 | EmptyState foundation `mascotte` prop | Nouvelle prop `mascotte` + auto-rendu Mascotte. Mapping variant→état (info→empty, success→happy, warning→thinking). Rétro-compat 100%. |
| 12-D-2 | #299 | animations.ts adoption Y2K core | 3 composants Y2K migrés vers `.transition-bouncy` / `.transition-snap` (spring physics cubic-bezier sans framer-motion) |
| 12-D-3 | #300 | Mascotte sur 9 EmptyState | Adoption Mascotte sur consumers user-facing : 4 thinking + 3 empty + 2 happy |
| 12-D-4 | (this) | Doc Sprint 12-D | docs/SPRINT_12_D.md + CLAUDE.md |
| **Total** | **4 PRs** | — | **9 Mascotte EmptyState + 3 transitions Y2K + 1 foundation prop** |

## Détail PR 12-D-1 — EmptyState foundation

Avant Sprint 12-D, le composant `<EmptyState>` (Sprint 8 BIS) n'avait que `icone` / `illustration`. Aucune intégration Mascotte. La Mascotte Y2K (Sprint 9-B) restait dépeuplée hors des dashboards.

PR #298 ajoute :
```tsx
mascotte?: boolean | "idle" | "happy" | "thinking" | "celebrating" | "empty"
```

Comportement :
- `mascotte={false}` → opt-out explicite (garde icone/illustration legacy)
- `mascotte={true}` → Mascotte avec état auto déduit du variant
- `mascotte="happy"` → Mascotte explicite avec etat précis
- non fourni → auto-Mascotte uniquement si **ni icone ni illustration** (rétro-compat 100%)

Mascotte taille `sm` en mode compact (TableOuCartes empty rows), `md` sinon.

## Détail PR 12-D-2 — animations.ts adoption

Audit : avant cette PR, `animations.ts` + classes CSS `.transition-bouncy/.transition-soft/.transition-snap` avaient **0 consumer** dans l'app.

Migration des transitions génériques :

| Composant | Avant | Après | Easing | Raison |
|---|---|---|---|---|
| `BoutonY2K` | `transition-all duration-200` | `transition-snap` | overshoot court (0.2, 0, 0.13, 1.5) | Réactivité tactile boutons |
| `CardY2K` | `transition-all duration-300` | `transition-bouncy` | overshoot doux (0.34, 1.56, 0.64, 1) | Lift effect ressort |
| `CarteKPIY2K` | `transition-all duration-300` | `transition-bouncy` | idem CardY2K | KPI hover cohérent |

Bénéfices :
- Spring physics sans dépendance framer-motion (~80KB économisés)
- `prefers-reduced-motion` géré dans `src/index.css` `@media reduce` (RGAA AA)
- Properties transitionées limitées (transform/shadow/bg/color/opacity) → meilleure perf vs `transition-all`

Impact : tous les 74 BoutonY2K (Sprint 12-B/C) + 36 CarteKPIY2K (Sprint 12-C) héritent automatiquement de l'animation Y2K spring.

## Détail PR 12-D-3 — Mascotte 9 EmptyState

Adoption Mascotte sur les EmptyStates user-facing à fort trafic.

| EmptyState | etat | Justification |
|---|---|---|
| RechercheMissions | `thinking` | CTA invite "élargir filtres" |
| MesAvances | `thinking` | CTA "Demander avance" |
| MesFavorisEtablissement | `thinking` | CTA "Ajoutez soignants" |
| ListeCandidatures | `thinking` | Invite vérification critères |
| HistoriqueMissions | `empty` | Historique vide neutre |
| ConformiteSoignant | `empty` | Pas encore de contrôles |
| MesReclamationsEtab | `empty` | Aucune réclamation neutre |
| LitigesSoignant | `happy` | variant=success, "Aucun litige" positif |
| LitigesEtablissement | `happy` | variant=success, "Aucun litige" positif |

**Distribution : 4 thinking, 3 empty, 2 happy.**

### Skipped (illustration intentionnelle Sprint 8 BIS)

- `MesGains` : `<IllustrationTirelire />` (artwork financier intentionnel)
- `PageNotifications` : `<IllustrationCloche />` (artwork notifications)
- `MesReclamations` : pattern empty alternatif (pas de `<EmptyState>`)

Ces EmptyStates conservent leur illustration vectorielle Sprint 8 BIS — pas de migration Mascotte.

## Audit Card → CardY2K — 4 pages user-facing SKIPPED

Skip honnête avec justification PRÉCISE par page.

| Page | Card count | Migration | Justification |
|---|---|---|---|
| **PremiumSoignant** | 3 | **SKIP** | Pricing layout avec borders sémantiques `border-primary/20` (Premium) + `border-warning/30` (Pack Libéral). Migrer perd la signalétique premium/warning. CardY2K n'a pas de variant `pricing`. Refactor nécessite création variant dédié → reporté Sprint 12-E. |
| **PremiumEtablissement** | 2 | **SKIP** | Idem PremiumSoignant — pricing Pack Établissement Pro avec `border-primary/20`. Décision UX dédiée requise. |
| **ContratPlateforme** | 3 | **SKIP** | Cards state-coded : `border-default` (non signé), `border-warning/30` (en vérification), `border-success/30` (actif). 3 états légaux distincts encodés visuellement via couleur. Y2K palette rose unifiée détruirait cette signalétique de statut contractuel. **Risque légal** : utilisateur doit voir le statut au coup d'œil. SKIP critique. |
| **FacturationEtablissement** | 11 | **SKIP** | 11 Cards utilisées dans des `<DialogResponsive>` (modales Stripe Connect / Chorus Pro / SEPA). Contexte modal → cohérence shadcn requise pour intégration Dialog. CardY2K dans Dialog créerait conflit `backdrop-blur` (glass déjà sur DialogResponsive). SKIP pour cohérence modal. |
| **Total** | **19 Cards** | **0 migrées** | **4 skips justifiés** |

### Conclusion audit Card

Aucune des 4 pages user-facing n'est candidate Card → CardY2K sans :
1. Création de nouveaux variants CardY2K (pricing, status-coded) — Sprint 12-E
2. Refactor du contexte modal `DialogResponsive` ↔ CardY2K (overlay glassmorphism stack) — Sprint 12-E
3. Décision UX produit sur la signalétique légale ContratPlateforme — discussion produit Gabrielle

**Migration Card user-facing : reportée Sprint 12-E avec audit dédié.** Les 15 pages admin restent également en Sprint 12-E.

## Bilan Sprint 12-D

- **4 PRs livrées en prod**
- **9 EmptyState avec Mascotte** (consumers user-facing)
- **1 foundation prop `mascotte`** (EmptyState)
- **3 composants Y2K core animés** spring (BoutonY2K + CardY2K + CarteKPIY2K)
- **0 PR ouverte** post-sprint
- **Card → CardY2K** : 4/4 user-facing pages skippées avec justification précise

### Adoption ratios cumulés (Sprint 12-B + 12-C + 12-D)

| Composant Y2K | Avant Sprint 12 | Après 12-B | Après 12-C | Après 12-D |
|---|---|---|---|---|
| `<BoutonY2K>` | 2 (0.9%) | 68 | 74 | 74 |
| `<CarteKPIY2K>` | 0 (0%) | 0 | 36 | 36 |
| `<CardY2K>` | 0 (0%) | 0 | 0 | 0 (skip 12-E) |
| `<Mascotte>` dans EmptyState | 0/66 (0%) | 0/66 | 0/66 | 9/66 (14%) |
| Foundation EmptyState mascotte prop | absent | absent | absent | ✓ |
| animations.ts cubic-bezier consumers | 0 | 0 | 0 | 3 (Y2K core) |

## Reportés Sprint 12-E

- **Card → CardY2K** user-facing 4 pages : refactor structurel + nouveaux variants CardY2K (pricing, status-coded) — décision UX produit
- **Card admin pages** : 15 fichiers + 2 composants admin — audit par page
- **Mascotte EmptyState reste** : ~57 instances non-migrées (mais 66 instances totales, dont la plupart avec icône ou illustration intentionnelle)
- **Animations spring élargies** : DialogResponsive entrance, notifications slide, FAB scale — au cas par cas
- **BadgeY2K adoption** : aucune adoption actuelle hors dashboards Sprint 9-C

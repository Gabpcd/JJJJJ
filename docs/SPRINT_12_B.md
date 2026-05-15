# Sprint 12-B — Adoption Y2K boutons critiques

Sprint 12-B lance l'adoption Y2K complète. L'audit Sprint 12 a révélé que les composants Y2K Sprint 9 (BoutonY2K, CardY2K, BadgeY2K, CarteKPIY2K, Mascotte, ListeSwipe) avaient été créés mais quasi jamais adoptés (0-5% selon composant).

12-B se concentre sur **BoutonY2K** sur 16 pages CTAs critiques flow soignant + étab + finance.

## PRs livrées

| PR | # | Pages | Boutons migrés | Skipped |
|---|---|---|---|---|
| 12-B-1 | #289 | HistoriqueMissions, RechercheMissions, MesFacturesHonoraires, BulletinsPaie | 14 | 2 (icon back nav) |
| 12-B-2 | #290 | FacturationEtablissement, FinaliserInscriptionEtab, LitigesEtablissement, ObligationsFinancieresEtab | 20 | 1 (icon back nav) |
| 12-B-3 | #291 | LitigesSoignant, MesReclamations, PageStripeConnect, ChorusConfig | 16 | 2 (destructive Stripe) |
| 12-B-4 | #292 | MandatFacturation, ContratPlateforme, ChargesSociales, MesGains | 16 | 2 (icon + destructive) |
| 12-B-5 | (this) | Doc | — | — |
| **Total** | **5 PRs** | **16 pages** | **66 boutons** | **7 skips justifiés** |

## Variant mapping appliqué

| shadcn `variant` | Y2K `variant` | Justification |
|---|---|---|
| `default` / absent | `primary` | CTA principal → gradient holographique rose→mauve |
| `secondary` | `secondary` | Surface neutre → border rose subtile |
| `outline` | `secondary` | Bordered shadcn ≈ secondary Y2K (avec border) |
| `ghost` | `ghost` | Transparent → transparent + hover bg-soft |
| `destructive` | **SKIP** | Pas d'équivalent Y2K destructive — garder shadcn (action irréversible signalée par red) |
| `link` | **SKIP** | Pas d'équivalent Y2K link |

## Size mapping

- `size="sm"` (36px) → `size="sm"` (Y2K 36px)
- `size="default"`/absent (40px) → `size="md"` (Y2K 44px — touch target mobile)
- `size="lg"` (44px) → `size="lg"` (Y2K 52px)
- `size="icon"` → **SKIP** (Y2K pas de mode icon-only)

## Skips détaillés (7 boutons préservés)

### Back navigation `size="icon"` (4)
- MesFacturesHonoraires : ArrowLeft retour
- BulletinsPaie : ArrowLeft retour
- FinaliserInscriptionEtab : ArrowLeft retour
- MandatFacturation : ArrowLeft retour

Justification : Y2K ne supporte pas `size="icon"`. Migrer changerait le layout (label sortant du min-height 44px sans children texte). Garder shadcn Button pour cohérence visuelle des back nav cross-app.

### Variant destructive (3)
- PageStripeConnect : 2 boutons `destructive` (onboarding échoué + expirée)
- MandatFacturation : 1 bouton `destructive` (Révoquer mandat = action irréversible)

Justification : pas d'équivalent Y2K destructive (rouge). Garder shadcn pour signal sémantique d'erreur/danger. Création d'un variant Y2K destructive reportée à Sprint 12-E si besoin avéré.

## Règles d'écriture (sub-agents)

Chaque PR a été migré via sub-agent général-purpose avec prompt strict :
1. **Preserve ALL other props** : className, onClick, disabled, type, key, ref, gap-* utility
2. **Add import BoutonY2K** alongside, **keep Button import** si des Buttons restent (skips)
3. **No behavior changes** — uniquement substitution du composant
4. **Skip rules respectées** : `asChild` (Radix Slot), `DialogTrigger`/`TooltipTrigger`/etc, destructive, link, icon
5. **Verify `npx tsc -b`** clean après chaque fichier

Pattern audit-first systématique : `grep -nE "<Button[ />]"` avant édition pour identifier les patterns.

## Bilan Sprint 12-B

- **5 PRs livrées en prod** (4 migration + 1 doc)
- **16 pages migrées** (8 soignant + 4 étab + 4 finance/légal)
- **66 boutons Y2K** (rose→mauve gradient + touch 44px)
- **7 skips honnêtes documentés** (icon back nav + destructive)
- **0 PR ouverte** post-sprint
- **0 régression CI** : tous les checks Typecheck+build / Drift / Lighthouse / Vercel restent verts

### Adoption ratio BoutonY2K

| | Avant Sprint 12-B | Après Sprint 12-B |
|---|---|---|
| `<BoutonY2K>` total | 2 (0.9%) | 68 |
| `<Button>` shadcn restants | 220 | ~154 |

Reste 154 occurrences `<Button>` shadcn dans le codebase, principalement :
- Pages admin (AdminUtilisateurs 29, AdminGroupes 13, AdminModeration 8, AdminChorusPro 6...) — **reporté Sprint 12-E** (Y2K dans admin = décision UX dédiée)
- Pages premium/static (BlogArticle, Parcours3200h, PremiumSoignant, PremiumEtablissement)
- Composants partagés (composants/**) — migration cascade possible Sprint 12-C
- Footer/Header navigation
- Cas `asChild` (Dialog/Tooltip/Dropdown trigger composition)
- `variant="destructive"` (action irréversible) + `size="icon"` (back nav)

## Reportés Sprint 12-C/D/E

- **12-C** : CardY2K + CarteKPIY2K adoption (composants visuels)
- **12-D** : BadgeY2K + Mascotte sur EmptyState (44 EmptyStates audités)
- **12-E** : Boutons secondaires (composants partagés, footer, header) + animations.ts + admin pages décision UX

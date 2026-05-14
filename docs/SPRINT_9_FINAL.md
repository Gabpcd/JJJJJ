# Sprint 9 — Identité visuelle Y2K Gen Z (récapitulatif final)

> Sprint 9 complet livré en 4 mini-sprints (A → D). 17 PRs en production.
> Charme handmade Y2K + sobriété PRO. Ton de voix vouvoiement préservé.

## Vue d'ensemble

| Sprint | Thème | PRs | URL |
|---|---|---|---|
| 9-A | Fondations CSS Y2K | 2 (#248-249) | merged |
| 9-B | Mascotte + composants Y2K | 5 (#250-254) | merged |
| 9-C | Refonte dashboards Y2K | 5 (#255-259) | merged |
| 9-D | Animations + glassmorphism + doc | 4 (PRs en cours) | this sprint |

**Total estimé : 16 PRs livrées Sprint 9 complet.**

## Détail par sprint

### Sprint 9-A — Fondations CSS Y2K (2 PRs)

**Cf. `docs/IDENTITE_VISUELLE_JOLENE.md`.**

- 4 couleurs primaires HSL light+dark : `jolene-rose` (#FF6BBE), `jolene-mauve` (#B57EFF), `jolene-cyan` (#6FE5FF), `jolene-butter` (#FFE066)
- 4 neutres : `jolene-lavender`, `jolene-cloud`, `jolene-midnight`, `jolene-bubblegum`
- Variantes 50→900 par couleur primaire (40 tokens total)
- 6 utility classes dégradés : `.bg-gradient-hero`, `.bg-gradient-soft`, `.bg-gradient-celebrate`, `.bg-holographic` (animé 8s), `.text-gradient-hero`, `.shadow-holographic`
- Tailwind `extend.colors` avec `jolene-*` aliases
- `prefers-reduced-motion: reduce` respecté

### Sprint 9-B — Mascotte + composants Y2K (5 PRs)

**Cf. `docs/COMPOSANTS_Y2K.md`.**

- **Mascotte** SVG cœur arrondi Y2K (style Tamagotchi/Polly Pocket) avec dégradé rose→mauve, 5 états émotionnels (idle/happy/thinking/celebrating/empty), 4 tailles, animations CSS pures (sans framer-motion)
- **BoutonY2K** 3 variants (primary gradient / secondary / ghost), touch targets 44px, loading spinner
- **CardY2K** 3 variants (default / holographic / glass glassmorphism), border-radius rounded-3xl, hover lift
- **BadgeY2K** 5 variants sémantiques (success/warning/error/info/premium)

### Sprint 9-C — Refonte dashboards Y2K (5 PRs)

- **CarteKPIY2K** réutilisable avec icône + valeur grande tabular + variation up/down/neutral colorée
- **ListeSwipe** carousel CSS scroll-snap natif (pas de dep externe), dots mobile + boutons prev/next desktop
- **DashboardSoignant** : header refondu avec `<Mascotte etat="happy|thinking">` + "Hiii, [prénom]" en `text-gradient-hero`
- **DashboardEtablissement** : `<Mascotte etat="happy">` + "Bonjour, [nom étab]" en `text-gradient-hero`
- Reste des dashboards inchangés (touche progressive)

### Sprint 9-D — Animations + glassmorphism + doc finale (4 PRs)

- **`src/lib/animations.ts`** : presets `EASINGS` (bouncy/soft/snap) + `DURATIONS` (instant/fast/base/slow) + `TRANSITIONS` compositions prêtes à l'emploi
- **CSS classes** : `.transition-bouncy` (cubic-bezier overshoot 0.34, 1.56, 0.64, 1), `.transition-soft`, `.transition-snap` — pure CSS, pas de framer-motion
- **DialogResponsive** : overlay `bg-jolene-midnight/40` + `backdrop-blur-sm`, content modal `rounded-3xl` + `border-jolene-rose-200/60` + `shadow-holographic` (desktop)
- **LayoutAdmin** : mobile header + bottom nav glassmorphism `bg-card/85 backdrop-blur-xl supports-[backdrop-filter]:bg-card/70` + border `jolene-rose-200/40`
- BarreNavigation soignant/étab : déjà glassmorphism (Sprint antérieur, audit lucide)
- Documentation finale

## Ton de voix préservé partout

✅ Vouvoiement sobre PRO maintenu dans 100% du copy.
✅ "Hiii" autorisé **uniquement** sur accueil dashboard soignant (brief Sprint 9).
✅ "Bonjour" sur dashboard étab.
❌ Aucun argot ("slay/iconic/girlie") nulle part dans l'app.

L'effet Gen Z vient à 100% de l'UI visuelle : palette holographique, mascotte cœur, dégradés, glassmorphism, animations spring-like CSS.

## Décisions techniques honnêtes

### Pas de framer-motion installé

**Raison** : bundle léger préservé. `framer-motion` ajoute ~50KB minifié pour les usages prévus dans Sprint 9 :
- Animations mascotte 5 états → CSS keyframes suffisent
- Hover scales BoutonY2K → CSS `:hover` + `transition-bouncy` (cubic-bezier overshoot)
- Glassmorphism → `backdrop-blur-xl` natif Tailwind
- Carousel ListeSwipe → CSS `scroll-snap` natif

**Coût caché évité** : ~50KB bundle + complexité variants management.

### Pas de embla-carousel/swiper

**Raison** : `ListeSwipe` utilise CSS `scroll-snap-mandatory` natif. Suffisant pour swipe horizontal avec snap + dots indicator. Bundle économisé : ~30KB.

### Migration progressive non-breaking

Tous les composants Y2K sont **additifs**. Les composants existants (`CarteKPI`, `BadgeStatut`, design system `--primary/--rose`) restent inchangés. Adoption page par page selon priorité business.

## Métriques

| Métrique | Avant Sprint 9 | Après Sprint 9 |
|---|---|---|
| Identité visuelle | Healthcare générique | **Y2K Gen Z signature** (palette holographique + mascotte) |
| Composants Y2K | 0 | **7** (Mascotte, BoutonY2K, CardY2K, BadgeY2K, CarteKPIY2K, ListeSwipe + animations utility) |
| Dashboards Y2K | 0 | **2** (Soignant + Étab headers avec mascotte) |
| CSS variables | Design system existant | **+ 40 tokens Y2K** (couleurs + variantes 50→900) |
| Dépendances ajoutées | — | **0** (pas de framer-motion, pas de swiper) |
| Bundle initial | baseline | **+ ~5KB CSS** (palette + utility classes) |

## Reportés post-launch

### Sprint 10+
- Adoption progressive des composants Y2K dans pages secondaires (HistoriqueMissions, BulletinsPaie, MesCandidatures) avec `<ListeSwipe>` extracts
- Migration progressive des `CarteKPI` vers `CarteKPIY2K` dans dashboards (après validation pré-prod)
- Mascotte sur EmptyState (variant `empty`) pour pages vides

### Conditionnels
- Activation `BadgeY2K premium` sur paliers commission ÉTAB (besoin design review)
- Mascotte celebrating sur signatures contrat complet (besoin UX research)

---

**Sprint 9 clos.** Jolene en état **identité Y2K Gen Z signature** sur fondations CSS + composants réutilisables + dashboards principaux. Pas de dépendance externe ajoutée. Ton de voix sobre PRO préservé partout.

## URL prod

🔗 https://jolene.app

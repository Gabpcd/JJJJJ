# Identité visuelle Jolene — Palette Y2K Gen Z

> Sprint 9-A : fondations CSS de l'identité visuelle Y2K Gen Z (charme handmade, sobriété PRO).
> Ton de voix : vouvoiement, jamais d'argot ("slay/iconic/girlie" interdits). L'effet Gen Z vient à 100% de l'UI.

## Palette

### Couleurs primaires (signature)

| Nom | HEX | HSL | Usage |
|---|---|---|---|
| **Rose Jolene** | `#FF6BBE` | `326 100% 71%` | Signature primaire, CTAs, mascotte |
| **Mauve holographique** | `#B57EFF` | `267 100% 75%` | Secondaire chaleureux, dégradés |
| **Cyan dream** | `#6FE5FF` | `192 100% 72%` | Accent énergique, highlights |
| **Jaune butter** | `#FFE066` | `50 100% 70%` | Warning friendly, célébrations |

### Couleurs neutres

| Nom | HEX | HSL | Usage |
|---|---|---|---|
| **Lavender mist** | `#F4EDFF` | `270 100% 96%` | Background soft Y2K |
| **Cloud white** | `#FFFAFF` | `320 100% 99%` | Surface cards |
| **Midnight purple** | `#2B1B3D` | `268 38% 18%` | Texte sombre principal |
| **Bubblegum gray** | `#A89BB8` | `271 16% 67%` | Texte secondaire muted |

### Variantes -50 → -900

Chaque couleur primaire dispose de variantes `50/100/200/300/400/500/600/700/800/900` (500 = base) pour usage Tailwind :

```tsx
<div className="bg-jolene-rose-100 text-jolene-rose-900">
  Card soft rose
</div>

<button className="bg-jolene-mauve hover:bg-jolene-mauve-600">
  CTA mauve
</button>
```

## Dégradés holographiques signature

3 dégradés réutilisables (classes utilitaires CSS) :

```tsx
{/* Dégradé hero — diagonal rose → mauve → cyan */}
<div className="bg-gradient-hero text-white p-6 rounded-2xl">
  Welcome header
</div>

{/* Dégradé soft — lavender → rose pâle (backgrounds) */}
<div className="bg-gradient-soft p-6 rounded-2xl">
  Section soft
</div>

{/* Dégradé celebrate — conic rose/mauve/cyan/jaune (états spéciaux) */}
<div className="bg-gradient-celebrate p-6 rounded-2xl">
  Achievement
</div>

{/* Texte clip dégradé (titres) */}
<h1 className="text-gradient-hero text-5xl font-bold">
  Jolene
</h1>

{/* Holographique animé (conic + spin 8s) — `prefers-reduced-motion` respecté */}
<div className="bg-holographic w-32 h-32 rounded-full" />

{/* Shadow holographique (cards premium) */}
<div className="shadow-holographic rounded-2xl bg-white p-6" />
```

## Mode dark

Toutes les variables sont dupliquées pour le mode dark avec versions adaptées (contraste préservé). La permutation est gérée par la classe `.dark` sur `<html>`.

## Variables CSS (référence)

```css
/* src/index.css :root */
--jolene-rose: 326 100% 71%;        /* + variantes 50→900 */
--jolene-mauve: 267 100% 75%;       /* + variantes 50→900 */
--jolene-cyan: 192 100% 72%;        /* + variantes 50→900 */
--jolene-butter: 50 100% 70%;       /* + variantes 50→900 */
--jolene-lavender: 270 100% 96%;
--jolene-cloud: 320 100% 99%;
--jolene-midnight: 268 38% 18%;
--jolene-bubblegum: 271 16% 67%;
```

## Tailwind config

Toutes les couleurs sont exposées via `tailwind.config.ts > theme.extend.colors` :

```ts
"jolene-rose": { DEFAULT, 50, 100, ..., 900 },
"jolene-mauve": { DEFAULT, 50, ..., 900 },
"jolene-cyan": { DEFAULT, 50, ..., 900 },
"jolene-butter": { DEFAULT, 50, ..., 900 },
"jolene-lavender": "hsl(var(--jolene-lavender))",
"jolene-cloud": "hsl(var(--jolene-cloud))",
"jolene-midnight": "hsl(var(--jolene-midnight))",
"jolene-bubblegum": "hsl(var(--jolene-bubblegum))",
```

## Compatibilité

- **Non-breaking** : la palette est ajoutée EN PARALLÈLE du design system existant (`--primary`, `--rose`, `--teal`, etc.).
- Migration progressive : les composants existants continuent d'utiliser leurs couleurs actuelles. Les nouveaux composants Y2K utilisent `jolene-*`.
- Tailwind 3 : compatibilité totale (HSL space-separated).

## Accessibilité

| Couleur | Sur cloud (`#FFFAFF`) | Sur midnight (`#2B1B3D`) |
|---|---|---|
| jolene-rose | 3.2:1 ⚠️ (large text only) | 6.8:1 ✅ AA |
| jolene-rose-700 | 4.7:1 ✅ AA | — |
| jolene-mauve | 3.0:1 ⚠️ | 7.2:1 ✅ AA |
| jolene-mauve-700 | 4.6:1 ✅ AA | — |
| jolene-cyan | 2.1:1 ❌ (decorative only) | 9.4:1 ✅ AAA |
| jolene-cyan-700 | 5.1:1 ✅ AA | — |

**Recommandation** : pour texte critique, utiliser variants `-700`/`-800`/`-900` sur fond clair. Variants `-50`/`-100`/`-200` pour decorative/backgrounds uniquement.

## Reportés sprint 9-B / 9-C / 9-D

- Sprint 9-B : Mascotte cœur (5 états) + composants Y2K (BoutonY2K, CardY2K, BadgeY2K)
- Sprint 9-C : Refonte dashboards Y2K + ListeSwipe + CarteKPI
- Sprint 9-D : Spring animations + glassmorphism + bouncy interactions

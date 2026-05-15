# Composants Y2K Jolene

> Sprint 9-B : briques visuelles Y2K Gen Z réutilisables. Charme handmade,
> sobriété PRO (vouvoiement, jamais d'argot dans le copy).

## Mascotte cœur

```tsx
import { Mascotte } from '@/components/mascotte/Mascotte';

<Mascotte etat="celebrating" taille="lg" />
<Mascotte etat="thinking" taille="md" />
<Mascotte etat="empty" taille="sm" animated={false} />
```

### Props

| Prop | Type | Défaut | Usage |
|---|---|---|---|
| `etat` | `'idle' \| 'happy' \| 'thinking' \| 'celebrating' \| 'empty'` | `'idle'` | État émotionnel |
| `taille` | `'sm' \| 'md' \| 'lg' \| 'xl'` | `'md'` | Tailles 48/80/128/192 px |
| `animated` | `boolean` | `true` | Animations CSS (blink, bounce, etc.) |
| `ariaLabel` | `string` | auto-généré | Texte alternatif AT |

### États émotionnels

- **idle** : neutre, blink subtil toutes les 4s + animation float douce
- **happy** : yeux fermés en arc + sourire + animation wiggle
- **thinking** : regard vers la droite + sourire pensif
- **celebrating** : étoiles colorées orbitant + bounce
- **empty** : yeux fermés tristes + blush effacé (états vides EmptyState)

### Style

- Corps : `<path>` cœur arrondi avec dégradé `#FF6BBE → #B57EFF` (rose → mauve)
- Yeux : cercles blancs + pupilles `#2B1B3D` + highlight blanc
- Blush : `<radialGradient>` rose semi-transparent sur joues
- Stroke : `#2B1B3D` (midnight purple) pour contour
- Étoiles celebrating : 4 étoiles (jaune butter / cyan / mauve / rose)

### Animations CSS (pas de framer-motion)

Définies dans `src/index.css` :
- `.animate-bounce-y2k` (0.8s ease-in-out)
- `.animate-wiggle-y2k` (2s ease-in-out)
- `.animate-float-y2k` (3s ease-in-out)
- `.animate-spin-slow-y2k` (8s linear, pour étoiles celebrating)

`prefers-reduced-motion: reduce` → toutes désactivées (RGAA AA).

## BoutonY2K

```tsx
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { ArrowRight } from 'lucide-react';

<BoutonY2K variant="primary" size="lg" iconeDroite={<ArrowRight />}>
  Continuer
</BoutonY2K>

<BoutonY2K variant="secondary" loading>Sauvegarde…</BoutonY2K>

<BoutonY2K variant="ghost" size="sm">Annuler</BoutonY2K>

<BoutonY2K variant="destructive" onClick={revoquer}>Révoquer</BoutonY2K>
```

### Variants

- **primary** : `.bg-gradient-hero` + `.shadow-holographic`, scale hover 1.03 / active 0.98
- **secondary** : surface `jolene-cloud` + border 2px `jolene-rose-300`, hover bg `jolene-rose-50`
- **ghost** : transparent, hover bg `jolene-rose-50`
- **destructive** : gradient `#FF4D6B → #FF6BBE` rouge-rose holographique + shadow rose vif (Sprint 12-C). Réservé aux actions irréversibles (révocation, suppression, annulation définitive).

Touch targets : `min-h-[36/44/52]px` selon size (sm/md/lg). Focus visible ring couleur du variant.

## CardY2K

```tsx
import { CardY2K } from '@/components/y2k/CardY2K';

<CardY2K variant="default">
  <h2>Card neutre</h2>
</CardY2K>

<CardY2K variant="holographic">
  <h2 className="text-white">Card hero</h2>
</CardY2K>

<CardY2K variant="glass" className="p-8">
  Glassmorphism subtle
</CardY2K>
```

### Variants

- **default** : `bg-jolene-cloud` + border 2px `jolene-rose-200` + shadow rose subtile
- **holographic** : `.bg-gradient-hero` + text-white + border white/30 + `.shadow-holographic`
- **glass** : `bg-jolene-cloud/75` + `backdrop-blur-xl` + border white/40 + shadow mauve

Border-radius `rounded-3xl`. Hover lift `-translate-y-1` (désactivable via `hoverLift={false}`).

## BadgeY2K

```tsx
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { Star, AlertTriangle } from 'lucide-react';

<BadgeY2K variant="premium" icone={<Star className="h-3 w-3" />}>
  PLATINE
</BadgeY2K>

<BadgeY2K variant="warning" icone={<AlertTriangle className="h-3 w-3" />}>
  Action requise
</BadgeY2K>
```

### Variants

| Variant | Couleur | Usage |
|---|---|---|
| `success` | cyan | Réussite, état vert |
| `warning` | butter | Avertissement bienveillant |
| `error` | destructive | Erreur (réutilise palette existante) |
| `info` | mauve | Information neutre |
| `premium` | `.bg-gradient-celebrate` | Achievement, récompense, niveau |

Tailles : `sm` (text-[10px]) / `md` (text-xs).

## Ton de voix dans les composants

**Rappel critique** : tous les composants Y2K sont **visuellement Gen Z** mais conservent le **vouvoiement sobre PRO** dans tout le copy :

✅ "Mission terminée. Votre paiement sera versé sous 48 heures."
❌ "Yass slay queen, ta mission est iconic 🔥"

L'effet Y2K vient à 100% de l'UI : palette, dégradés holographiques, mascotte. Le copy reste healthcare professionnel.

## CarteKPIY2K (Sprint 9-C PR 1)

```tsx
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { Briefcase } from 'lucide-react';

<CarteKPIY2K
  icone={<Briefcase className="h-4 w-4" />}
  label="Missions ce mois"
  valeur={12}
  variation={{ pct: 25, sens: 'up', label: 'vs mois dernier' }}
  variant="default"
  onClick={() => navigate('/missions')}
/>

<CarteKPIY2K
  label="Revenus du mois"
  valeur="1 250 €"
  variation={{ pct: -10, sens: 'down' }}
  variant="holographic"
/>
```

### Variants
- `default` : surface cloud + border rose subtile + shadow rose
- `holographic` : bg-gradient-hero + text-white + shadow-holographic
- `soft` : bg-gradient-soft + text-midnight

Hover : `-translate-y-1` + shadow upgrade si `onClick`. Variation flèche up/down/neutral colorée selon sens.

## ListeSwipe (Sprint 9-C PR 2)

```tsx
import { ListeSwipe } from '@/components/y2k/ListeSwipe';

<ListeSwipe titre="Missions ouvertes" voirToutHref="/soignant/missions">
  {missions.map(m => <CarteMission key={m.id} mission={m} />)}
</ListeSwipe>
```

### Comportement
- Mobile : 1 item par swipe, scroll-snap mandatory (CSS natif, pas de dep externe)
- Desktop : scroll horizontal libre + boutons précédent/suivant si overflow
- Dots indicator mobile (hidden sm:)
- IntersectionObserver pour détecter item actif (threshold 0.6)
- A11y : `aria-roledescription="carousel"`, boutons navigation accessibles

### Props
| Prop | Type | Défaut | Usage |
|---|---|---|---|
| `titre` | `string` | — | Header au-dessus |
| `voirToutHref` | `string` | — | Lien optionnel droite header |
| `boutonsNav` | `boolean` | `true` | Boutons prev/next desktop |
| `dots` | `boolean` | `true` | Indicateurs mobile |

## Intégrations dashboards Y2K (Sprint 9-C PR 3-4)

**DashboardSoignant** :
- Header avec `<Mascotte etat="happy|thinking" taille="md" />` à gauche
- "Hiii [prénom]" en `text-gradient-hero` (titre arc-en-ciel)
- État mascotte selon documents : `happy` si OK, `thinking` si incomplet

**DashboardEtablissement** :
- Header avec `<Mascotte etat="happy" taille="md" />`
- "Bonjour [nom étab]" en `text-gradient-hero`
- Fallback `etat="idle"` si pas d'étab chargé

## Reportés Sprint 9-D

- Spring animations + glassmorphism étendu nav/modales + bouncy interactions
- Adaptation pages soignant utilisant ListeSwipe (HistoriqueMissions, MesCandidatures, BulletinsPaie) — à faire au cas par cas après validation pattern

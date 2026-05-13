# UX Polish Standards — Sprint 8

Conventions UX issues du Sprint 8. Briques transversales utilisables dans toutes les nouvelles features.

## 1. Skeletons (chargement)

### Composant base `<Skeleton />`
`src/components/ui/skeleton.tsx`

```tsx
<Skeleton className="h-4 w-3/4" variant="shimmer" />
<Skeleton className="h-12 w-12 rounded-full" variant="pulse" />
```

- `variant="shimmer"` (défaut) : gradient animé 1.6s
- `variant="pulse"` : `animate-pulse` simple (utile contexte calme)
- `size="sm" | "md" | "lg"` (optionnel, applique `h-3 | h-4 | h-6`)
- A11y intégrée : `role="status"`, `aria-busy="true"`, `aria-live="polite"`

### Skeletons contextuels
`src/components/skeletons/index.tsx` — 11 composants prêts à l'emploi :

| Skeleton | Utilisation |
|---|---|
| `<CarteMissionSkeleton />` / `<ListeCarteMissionSkeleton count={N} />` | Recherche missions soignant |
| `<CandidatureSkeleton />` / `<ListeCandidatureSkeleton />` | Liste candidatures étab |
| `<ProfilSoignantSkeleton />` | Profil + dashboard soignant |
| `<DashboardKpiSkeleton kpis={4} />` | KPI dashboards 3 interfaces |
| `<TableauPaiementSkeleton rows={5} />` | Factures, bulletins, versements |
| `<ScoreSkeleton />` | Page score |
| `<MessagerieSkeleton count={5} />` | Conversations |
| `<AdminTableauSkeleton rows={8} cols={5} />` | Tableaux admin |
| `<ContratPdfSkeleton />` | Intégration PDF |
| `<PageContenuSkeleton />` | Générique |

Toujours préférer un skeleton contextuel à un spinner générique — préserve la perception de structure.

## 2. États vides (EmptyState)

### Composant `<EmptyState />`
`src/components/ui/EmptyState.tsx`

```tsx
<EmptyState
  icone={<Search />}
  titre="Aucune mission disponible"
  description="Élargissez vos critères pour voir plus de résultats."
  cta={{ label: "Modifier mes préférences", onClick: () => navigate('/soignant/preferences') }}
  variant="info"
/>
```

Variants :
- `info` (défaut) : neutre, recherche vide
- `success` : positif, à jour, pas de litige
- `warning` : action requise, profil à compléter

Touch targets boutons `min-h-[44px]` (RGAA AA).

## 3. Toasts unifiés

`afficherNotification` via `useNotification()` — hiérarchie durées par type :

| Type | Durée | Rôle ARIA |
|---|---|---|
| `info` | 3000ms | `status` |
| `succes` | 4000ms | `status` |
| `avertissement` | 5000ms | `status` |
| `erreur` | 7000ms | `alert` |

Action optionnelle (Undo, "Voir détails") :
```tsx
afficherNotification({
  type: 'succes',
  message: 'Candidature annulée',
  action: { label: 'Annuler', onClick: () => restaurer() },
});
```

Position responsive : `bottom-20 inset-x-4` mobile / `top-4 right-4 w-96` desktop.

## 4. Gestion erreurs API

### Dictionnaire `traduireErreur`
`src/lib/errorMessages.ts`

```ts
import { traduireErreur, estErreurReseau } from '@/lib/errorMessages';

const message = traduireErreur(error);
afficherNotification({ type: 'erreur', message });
```

Couvre SQLSTATE Postgres (23xxx, 42xxx, 22xxx), `P0001` raise custom, PostgREST (PGRST*), Supabase Auth, HTTP 401/403/404/429/5xx, codes métier Jolene (`NON_AUTORISE`, `ETAT_INVALIDE`, `DELAI_DEPASSE`, etc.).

### Hook `useApiCall`
`src/hooks/useApiCall.ts`

```tsx
const { executer, loading } = useApiCall();
const charger = () => executer(
  () => supabase.rpc('fn_xxx'),
  {
    onSuccess: (data) => setLignes(data),
    messageErreur: 'Impossible de charger les données.',
  }
);
```

Retry automatique 1s/2s/4s sur erreurs réseau (3 tentatives par défaut). Toast erreur auto via `afficherNotification`.

## 5. Briques mobile

### `useViewport()`
`src/hooks/useViewport.ts`

```tsx
const { estMobile, estTablette, estDesktop } = useViewport();
return estMobile ? <CartesEmpilees /> : <Tableau />;
```

Breakpoints alignés Tailwind (`md=768`, `lg=1024`).

### Presets `inputMode` mobile
`src/lib/inputMobile.ts`

```tsx
<input {...PROPS_INPUT_EMAIL} value={email} onChange={...} />
<input {...PROPS_INPUT_OTP} maxLength={6} />
<input {...PROPS_INPUT_NIR} />
```

13 presets : `EMAIL`, `TELEPHONE`, `OTP`, `MONTANT`, `ENTIER`, `NIR`, `SIRET`, `CODE_POSTAL`, `RECHERCHE`, `NOM`, `PRENOM`, `MDP`, `NOUVEAU_MDP`. Tous activent le bon clavier mobile + désactivent l'auto-capitalize sur les champs techniques.

## 6. Images optimisées

### `<ImageOptimisee />`
`src/components/ui/ImageOptimisee.tsx`

```tsx
<ImageOptimisee
  src="/images/illustration.png"
  srcWebp="/images/illustration.webp"
  alt="Description significative"
  width={400}
  height={300}
  prioritaire={false}
/>
```

WebP first + fallback automatique via `<picture>`, lazy loading natif, `aspect-ratio` CSS (anti-CLS Lighthouse), `decoding="async"`. Images décoratives : `alt=""`.

## 7. Compatibilité admin mobile

Le `LayoutAdmin` a :
- Sidebar desktop (`hidden md:flex`)
- Mobile bottom-nav (5 items) + overlay "Plus" qui flatten les groupes Finances/Conformité
- `BannerAdminMobile` (< 640px) : message dismissible "Vue optimisée pour ordinateur. Sprint 8.5 améliorera l'expérience mobile admin."
- `overflow-x-hidden` sur `<main>` pour garantir aucun débordement
- Toutes les actions admin restent accessibles via bottom-nav + "Plus"

## 8. A11y RGAA AA

`src/index.css` couvre déjà :
- `:focus-visible` : outline 2px solid + offset 2px
- `.skip-to-main` : lien "Aller au contenu principal" (visible au focus uniquement)
- `@media (prefers-reduced-motion: reduce)` : désactive `animate-shimmer`, `animate-slide-in`, etc.

Conventions composants Sprint 8 :
- Boutons : `min-h-[44px]` (touch target)
- `aria-label` sur icon-only buttons
- `aria-hidden="true"` sur icônes décoratives
- `role="alert"` pour erreurs, `role="status"` pour reste
- `<picture>` avec `<img alt>` obligatoire pour images

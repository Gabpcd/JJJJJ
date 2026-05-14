# EmptyState unifié — consolidation Sprint 8 ter-A BIS

## Contexte

L'app avait 2 composants équivalents :
- `<EtatVide>` (legacy, ~27 imports, avec illustrations vectorielles 100×100)
- `<EmptyState>` (Sprint 8, sans illustrations à l'origine)

Sprint 8 ter-A BIS a **unifié** ces deux composants en enrichissant `<EmptyState>` avec une prop `illustration` et en marquant `<EtatVide>` comme `@deprecated`.

## API unifiée `<EmptyState />`

`src/components/ui/EmptyState.tsx`

```tsx
<EmptyState
  // Mode "illustration" (priorité) : SVG line-art 100×100
  illustration={<IllustrationBoussole />}

  // OU mode "icône Lucide" (compact circulaire)
  icone={<Search />}

  // Texte (titre obligatoire, description optionnel)
  titre="Aucune mission disponible"
  description="Élargissez vos critères pour voir plus de résultats."

  // Variant (info / success / warning)
  variant="info"

  // CTA optionnel(s)
  cta={{ label: "Modifier", onClick: () => navigate('/...') }}
  ctaSecondaire={{ label: "Autre", onClick: ... }}

  // Compact pour usage inline (moins de padding)
  compact={false}
/>
```

## Illustrations disponibles

Re-exportées depuis `@/components/ui/EmptyState` (source : `@/components/ui/EmptyStateIllustrations`) :

| Illustration | Usage typique |
|---|---|
| `IllustrationBoussole` | Recherche missions / navigation |
| `IllustrationMegaphone` | Publier première mission étab |
| `IllustrationDossier` | Documents / contrats |
| `IllustrationStylo` | Signature / édition |
| `IllustrationCloche` | Notifications |
| `IllustrationBouclier` | Sécurité / litiges |
| `IllustrationTirelire` | Paiements / gains |
| `IllustrationCalculatrice` | Comptabilité / facturation |

Toutes les illustrations sont en `text-primary` avec `strokeWidth` uniforme. Sprint 9 Y2K Gen Z les remplacera par la mascotte Jolene.

## Migration progressive

Pages migrées Sprint 8 ter-A BIS :

| Page | PR |
|---|---|
| `ListeMissions.tsx` | #200 |
| `ListeContrats.tsx` | #200 |
| `LitigesEtablissement.tsx` | #200 |
| `PresencesEtablissement.tsx` (4 onglets) | #200 |
| `AdminLitiges.tsx` | #201 |
| `AdminMissions.tsx` | #201 |

**6 pages migrées sur 26 imports `EtatVide` au démarrage du Sprint.**

## Pages restantes (Sprint 8 ter-A TER)

20 pages utilisent toujours `<EtatVide>` (component @deprecated mais fonctionnel) :

### SOIGNANT (12)
- `RechercheMissions.tsx`
- `MissionsSoignant.tsx`
- `PresencesSoignant.tsx`
- `ConformiteSoignant.tsx`
- `DashboardSoignant.tsx`
- `EvaluationsSoignant.tsx`
- `ExclusionsSoignant.tsx`
- `HistoriqueMissions.tsx`
- `LitigesSoignant.tsx`
- `MesGains.tsx`
- `PageNotifications.tsx`
- `PageMessagerie.tsx`

### ÉTAB (6)
- `AssuranceMission.tsx`
- `DashboardEtablissement.tsx`
- `DashboardRH.tsx`
- `ExclusionsEtablissement.tsx`
- `ExportPaie.tsx`
- `FacturationEtablissement.tsx`
- `MesReclamationsEtab.tsx`
- `PoolUrgenceEtablissement.tsx`

## Workflow de migration par page

1. `import { EtatVide } from '@/components/EtatVide';` → `import { EmptyState } from '@/components/ui/EmptyState';`
2. Si illustration : `import { IllustrationXxx } from '@/components/EtatVide';` → `import { IllustrationXxx } from '@/components/ui/EmptyState';`
3. JSX :
   - `icone={Search}` (LucideIcon) → `icone={<Search />}` (JSX)
   - `sousTitre="..."` → `description="..."`
   - `boutonLabel="X" boutonRoute="/y"` → `cta={{ label: "X", onClick: () => navigate('/y') }}` (nécessite `useNavigate`)
4. Ajouter `variant="success"` sur les empty states positifs (pas de litige, pas d'alerte, etc.)

## Suppression définitive de `EtatVide.tsx`

`src/components/EtatVide.tsx` ne pourra être supprimé qu'**après** la migration des 20 pages restantes. Le fichier est marqué `@deprecated` en attendant.

Sprint 8 ter-A TER (session future) traitera ces 20 pages — ~3-5 PRs de 4-6 pages chacune.

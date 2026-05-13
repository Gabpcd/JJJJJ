# Responsive mobile — Sprint 8 BIS

Briques foundation pour mobile-first complet. Documenté pour wiring progressif.

## `<TableOuCartes />`
`src/components/ui/TableOuCartes.tsx`

Wrapper qui rend un tableau classique sur desktop et des cartes empilées sur mobile.

### Usage

```tsx
import { TableOuCartes, ColonneTableau } from '@/components/ui/TableOuCartes';
import { EmptyState } from '@/components/ui/EmptyState';

const colonnes: ColonneTableau<Facture>[] = [
  { cle: 'numero', titre: 'N° facture' },
  { cle: 'date', titre: 'Émise le' },
  { cle: 'montant', titre: 'Montant', align: 'right' },
  { cle: 'statut', titre: 'Statut' },
];

<TableOuCartes
  colonnes={colonnes}
  donnees={factures}
  getId={(f) => f.id}
  renduCellule={(f, col) => {
    if (col.cle === 'montant') return formatEur(f.montant_ttc);
    if (col.cle === 'statut') return <Badge>{f.statut}</Badge>;
    if (col.cle === 'date') return formatDate(f.date_emission);
    return f[col.cle];
  }}
  renduCarte={(f) => (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className="font-mono font-semibold">{f.numero}</span>
        <Badge>{f.statut}</Badge>
      </div>
      <p className="text-sm text-muted-foreground">{formatDate(f.date_emission)}</p>
      <p className="text-lg font-bold">{formatEur(f.montant_ttc)}</p>
    </div>
  )}
  onClickLigne={(f) => navigate(`/etablissement/factures/${f.id}`)}
  etatVide={<EmptyState titre="Aucune facture" />}
/>
```

### Comportement
- Détection viewport via `useViewport()` (Sprint 8 PR 5)
- Sous 768px : `role="list"/"listitem"` + cartes empilées via `renduCarte`
- 768px+ : Table shadcn classique via `renduCellule`
- Touch targets `min-h-[44px]` sur cartes cliquables

## `<DialogResponsive />`
`src/components/ui/DialogResponsive.tsx`

Wrap `@radix-ui/react-dialog` avec rendu fullscreen mobile / centered desktop.

### Usage

```tsx
import {
  DialogResponsive, DialogResponsiveContent,
  DialogResponsiveHeader, DialogResponsiveTitle,
  DialogResponsiveBody, DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';

<DialogResponsive open={open} onOpenChange={setOpen}>
  <DialogResponsiveContent maxWidth="lg">
    <DialogResponsiveHeader>
      <DialogResponsiveTitle>Confirmer l'annulation</DialogResponsiveTitle>
    </DialogResponsiveHeader>
    <DialogResponsiveBody>
      <p>Voulez-vous vraiment annuler cette candidature ?</p>
    </DialogResponsiveBody>
    <DialogResponsiveFooter>
      <Button variant="ghost" onClick={() => setOpen(false)}>Retour</Button>
      <Button variant="destructive" onClick={confirmer}>Confirmer</Button>
    </DialogResponsiveFooter>
  </DialogResponsiveContent>
</DialogResponsive>
```

### Comportement
- Mobile (< 768px) :
  - Fullscreen (`inset-0`, `h-full`)
  - Header sticky en haut avec safe-area-inset-top
  - Footer sticky en bas avec safe-area-inset-bottom
  - Scroll interne sur le body
  - Animation slide-in-from-bottom
- Desktop (>= 768px) :
  - Centered modal max-width configurable (`sm`/`md`/`lg`/`xl`/`2xl`)
  - Animation fade-in standard
  - max-height 85vh avec scroll interne body

### A11y
- `aria-label="Fermer"` sur le bouton X
- `focus-visible:ring-2` cohérent
- Min 32px tap target sur fermeture

## Pages migrées Sprint 8 BIS
- `MesAvances.tsx` — EmptyState
- `BulletinsPaie.tsx` — EmptyState (vide + filtres réinitialiser)
- `MesFacturesHonoraires.tsx` — EmptyState (variant info/warning selon mandat)

## Reste à faire (Sprint 8 ter ou Sprint 8.5)
- Migrer les tableaux SOIGNANT longs vers `<TableOuCartes>` (HistoriqueMissions, PageEvaluationsSoignant, MesDpae)
- Migrer les tableaux ÉTAB vers `<TableOuCartes>` (FacturationEtablissement, ListeContrats, PresencesEtablissement, AnalyticsEtablissement)
- Migrer modales lourdes vers `<DialogResponsive>` (SignerContratOtp, ModaleAnnulation*, ModaleEvaluer*)
- Wiring EmptyState dans ~20 autres contextes vides identifiés

# Score breakdown inline candidatures (Sprint 7)

> Fix **P1-5** audit Sprint 5. Décomposition du score soignant accessible directement dans ListeCandidatures sans navigation.

## Composant

`PopoverScoreSoignant` (`src/components/score/PopoverScoreSoignant.tsx`).

## Usage

```tsx
<PopoverScoreSoignant
  soignantId={c.soignant.id}
  scoreFiabilite={c.soignant.score_fiabilite}
  trigger="icon" // ou "inline"
/>
```

## 6 composantes affichées (Sprint 3.5)

| Composante | Poids |
|---|---|
| Notations reçues | 35% |
| Présentéisme | 20% |
| Ponctualité | 15% |
| Réactivité | 10% |
| Ancienneté | 10% |
| Notations données aux étabs | 10% |

## Accessibilité

- Ouvre au clic ET au focus
- Ferme via Escape ou clic extérieur
- `role="dialog"` pour lecteur d'écran
- Tab order preservé

## RPC backend

Charge `fn_soignant_score_breakdown(p_soignant_id)` (à créer si manquante, fallback affichage simplifié sinon).

## Intégration

Embarqué dans le badge score de `ListeCandidatures.tsx` (Sprint 3.5 candidatures étab).

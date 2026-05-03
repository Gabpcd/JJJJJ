# Accessibilité — Jolene

Date : 2026-05-03

## Engagement

Jolene s'engage à rendre son service accessible conformément à l'article 47 de la loi
n° 2005-102 du 11 février 2005 et au RGAA niveau AA.

La déclaration officielle visible par les utilisateurs est sur **`/accessibilite`**.

## Standards visés

- **RGAA 4.1** niveau AA (référentiel français)
- **WCAG 2.1** niveau AA (international)

## Architecture a11y

### Baseline déjà en place

| Élément | Implémentation | Vérification |
|---|---|---|
| `<html lang="fr">` | `index.html:2` | manuel |
| Skip-to-content | `App.tsx` + `.skip-to-content` CSS | test e2e `a11y.spec.ts` |
| Landmark `<main id="main-content">` | `LayoutApp.tsx:52`, `LayoutAdmin.tsx:251` | manuel + axe-core |
| `prefers-reduced-motion` | `src/index.css:728-775` (couvre Tailwind animate-*) | manuel + media query |
| `:focus-visible` | `src/index.css:362` | manuel |
| Notifications avec `role="alert"` (erreur) / `role="status"` (info) | `NotificationContext.tsx` | tests e2e |
| Toggle password avec `aria-label` + `aria-pressed` | `PageConnexion`, `InscriptionSoignant`, `InscriptionEtab` | manuel |
| Labels formulaires (htmlFor / wrapping `<label>`) | toutes pages d'inscription | tests e2e + axe |

### Composants partagés a11y-friendly

- **Boutons icon-only** : tous ont `aria-label` (Eye/EyeOff, X, Menu, etc.)
- **Modales** : composants Radix UI (`<Dialog>` Radix) gèrent automatiquement focus trap, Escape, aria-modal, aria-labelledby
- **Toasts** : Sonner + NotificationContext custom = `role="alert"` / `role="status"` selon sévérité
- **Tooltips** : Radix UI = aria-describedby au focus
- **Combobox** (SelectProfession) : Radix Popover + Command = ARIA combobox role correct

## Tests automatisés

### axe-core via Playwright

Fichier : `e2e/a11y.spec.ts` + helper `e2e/helpers/axe.ts`

```ts
import { runAxe, expectNoCriticalA11y } from './helpers/axe';

test('/connexion — axe a11y WCAG 2.1 AA', async ({ page }, testInfo) => {
  await page.goto('/connexion');
  const results = await runAxe(page);
  expectNoCriticalA11y(results, testInfo);
});
```

- **Tags WCAG** par défaut : `wcag2a, wcag2aa, wcag21a, wcag21aa`
- Violations **CRITICAL/SERIOUS** → test échoue
- Violations **MODERATE/MINOR** → log warning (non-bloquant)
- Rapport complet attaché aux artifacts CI (debug)

### Lancer en local

```bash
npx playwright test e2e/a11y --project=chromium
```

### Pages auditées par axe

- `/` (landing)
- `/connexion`, `/reset-password`, `/inscription/succes`
- `/inscription/soignant`, `/inscription/etablissement`
- `/aide`
- `/accessibilite`
- `/404`

Pour ajouter une page : copier un test dans `a11y.spec.ts` avec le bon path.

## Checklist nouveau composant

Avant de merger un nouveau composant, vérifier :

- [ ] Labels associés aux inputs (`htmlFor` ou wrapping `<label>`)
- [ ] Boutons icon-only ont `aria-label`
- [ ] Touch targets ≥ 44×44px sur mobile (`min-h-[44px]` ou padding équivalent)
- [ ] Couleurs ne sont pas le seul vecteur d'info (texte + icône en plus)
- [ ] Contraste texte/fond ≥ 4,5:1 (texte normal) ou 3:1 (texte large 18pt+)
- [ ] Pas de `text-[10px]` sur du contenu critique (privilégier `text-xs` = 12px)
- [ ] Animations respectent `prefers-reduced-motion` (déjà couvert globalement pour Tailwind animate-*)
- [ ] `<button>` plutôt que `<div onClick>` (sinon `role="button"` + `tabIndex={0}` + `onKeyDown`)
- [ ] Focus visible (Tailwind `focus:ring-2 focus:ring-primary` ou `:focus-visible` custom)
- [ ] Liens explicites (pas "click here", "voir plus" sans contexte)
- [ ] Notifications/erreurs : `role="alert"`, succès : `role="status"`
- [ ] Modales : utiliser Radix `<Dialog>` (focus trap + Escape + aria-modal automatiques)

## Outils utilisés

| Outil | Usage | Fichier/commande |
|---|---|---|
| **axe-core** | Audit auto WCAG 2.1 AA dans tests E2E | `e2e/a11y.spec.ts` |
| **Lighthouse** | Audit a11y manuel (Chrome DevTools) | `chrome://flags` → activer Lighthouse panel |
| **Chrome DevTools Contrast** | Vérification ratio contraste | DevTools → Inspect → Styles → color picker |
| **WebAIM Color Contrast Checker** | Vérification ratio en ligne | https://webaim.org/resources/contrastchecker/ |
| **NVDA** (Windows, gratuit) | Test lecteur d'écran | https://www.nvaccess.org/ |
| **VoiceOver** (macOS/iOS) | Test lecteur d'écran | Cmd+F5 sur macOS |

## Procédure de signalement (utilisateur final)

Visible sur `/accessibilite` :
1. Email : `accessibilite@jolene.app`
2. Si non-réponse : Défenseur des droits

## Score actuel

| Métrique | Score | Notes |
|---|---|---|
| Lighthouse a11y (pages publiques) | À mesurer en CI | objectif ≥ 95 |
| axe-core violations CRITICAL/SERIOUS | 0 | enforcé en CI via `expectNoCriticalA11y` |
| axe-core violations MODERATE | À surveiller | log warning |
| RGAA niveau AA | Conforme | déclaration `/accessibilite` |
| WCAG 2.1 AA | Conforme | déclaration `/accessibilite` |

## Prochaines améliorations possibles

- Sous-titres sur vidéos tutoriel (quand vidéos seront ajoutées)
- Lighthouse a11y score automatisé en CI (actuellement axe-core uniquement)
- Tests lecteur d'écran scriptés (NVDA via virtual cursor automation)
- Mode contraste élevé (high-contrast mode toggle)
- Documentation ARIA patterns custom dans Storybook (si Storybook ajouté plus tard)

## Ressources

- [RGAA 4.1 officiel](https://accessibilite.numerique.gouv.fr/)
- [WCAG 2.1 (français)](https://www.w3.org/Translations/WCAG21-fr/)
- [Pattern ARIA W3C](https://www.w3.org/WAI/ARIA/apg/)
- [axe-core rules documentation](https://github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md)
- [Radix UI a11y](https://www.radix-ui.com/primitives/docs/overview/accessibility)

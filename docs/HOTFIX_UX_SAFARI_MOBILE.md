# Hotfix UX Safari Mobile — pièges + remèdes globaux

Documentation issue de l'audit + fix Safari mobile (28+ fichiers) après symptômes en test prod Gabrielle iPhone Safari : pages auth qui sautent/scrollent au focus, layout casse au clavier.

## Pièges Safari iOS à connaître

### 1. `100vh` inclut la barre Safari dynamique

Sur Safari iOS, `100vh` est calculé incluant la barre d'adresse (qui apparaît/disparaît au scroll). Quand le clavier s'ouvre ou que la barre change d'état → la hauteur change brutalement → **layout saute**.

**Fix** : utiliser `100dvh` (dynamic viewport height) qui prend en compte la barre dynamique. Supporté Safari iOS 15.4+ / Chrome 108+.

```diff
- <div className="min-h-screen ...">       /* = 100vh, saute mobile */
+ <div className="min-h-[100dvh] ...">     /* = dvh, stable */
```

`100dvh` ≡ `100vh` sur desktop → **0 risque de régression desktop**.

### 2. Cascade Tailwind `@layer utilities` écrase `@layer base`

`src/index.css` impose globalement :
```css
@layer base {
  html, body { min-height: 100dvh; }
  input, textarea, select { font-size: max(16px, 1rem); }
}
```

**MAIS** Tailwind utilities (`.min-h-screen`, `.text-sm`) sont dans `@layer utilities` → cascade gagne. Donc :
- `<div className="min-h-screen">` → 100vh (utilities) écrase 100dvh (base)
- `<textarea className="text-sm">` → 14px (utilities) écrase 16px (base)

**Fix** : forcer la valeur correcte sur chaque composant/page. Ne pas se reposer uniquement sur `@layer base`.

### 3. Zoom auto Safari iOS sur input < 16px

Safari iOS zoom automatiquement quand on focus un input dont la font-size effective est `< 16px`. Désagréable + crée le sentiment de "saut".

**Pattern Jolene à respecter** :
- `Input` shadcn : `text-base md:text-sm` (16px mobile, 14px desktop ≥768px)
- `Textarea` shadcn : idem `text-base md:text-sm` (corrigé hotfix Safari PR 1)
- `.input-base` (classe CSS) : `text-base sm:text-sm` + override `@media (max-width: 768px) { font-size: 16px; }`

`Select` (shadcn/Radix) est un `<button>`, pas un input → pas de zoom même en `text-sm`.

### 4. `scrollIntoView({behavior:'smooth'})` au focus input crée des sauts

Safari iOS scrolle déjà nativement vers l'input focusé quand le clavier s'ouvre. Ajouter un `scrollIntoView smooth` JS + un `setTimeout` crée un **conflit** avec ce scroll natif → saut visible/désagréable.

```diff
- input.scrollIntoView({ behavior: 'smooth', block: 'center' });
- setTimeout(() => input.focus(), 400);
+ input.focus();  // Safari iOS scroll nativement
```

⚠ Ce pattern reste **valide** pour scroller vers une section/un message (cf. `FilDiscussionLitige`, `DashboardRH`, `FacturationEtablissement`) — **uniquement à éviter au focus d'un champ de saisie**.

### 5. Statuts distincts REJETE vs EXPIRE (rappel Sprint Hotfix UX Documents)

(voir docs/SPRINT_HOTFIX_UX_DOCUMENTS.md)

## Périmètre couvert par le hotfix

| PR | Fichiers | Action |
|---|---|---|
| #358 | 8 pages auth + Textarea shadcn + 2 retraits scrollIntoView | P0 fix critique bug Gabrielle |
| #359 | 16 fichiers (pages publiques + layouts + fallbacks + 1 modal) | Defense-in-depth `min-h-[100dvh]` global |

**Total : 24 fichiers** fixés sur les 28+ identifiés en audit. Restants déjà conformes :
- `LayoutApp.tsx:42` — `style={{ minHeight: '100dvh' }}` inline
- `ui/dialog.tsx` — `max-h-[calc(100dvh - safe-area)]` déjà OK
- `ui/toast.tsx` — `max-h-screen` mais positionné `fixed top-0/bottom-0` (pas un container plein écran)

## Tests E2E

Le hotfix Safari mobile n'a pas de tests E2E dédiés (Playwright ne simule pas la barre Safari dynamique de manière fiable). Validation manuelle iPhone Safari :
- Plus de saut au focus
- Plus de zoom auto sur inputs/textarea
- Layout stable à l'ouverture clavier

## Note Capacitor — Sprint 18

L'app va passer en Capacitor pour publication App Store / Play Store. Bonnes pratiques additionnelles à activer **Sprint 18** :

### Plugin `@capacitor/keyboard` déjà préparé
`src/lib/platform.ts:170-175` contient déjà :
```ts
Keyboard.setResizeMode({ mode: 'body' as any });  // iOS
Keyboard.setResizeMode({ mode: 'native' as any }); // Android
Keyboard.addListener('keyboardWillShow', () => {
  setTimeout(() => {
    const el = document.activeElement as HTMLElement | null;
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, 100);
});
```

⚠ **Attention** : ce listener `keyboardWillShow` n'est activé QUE en environnement Capacitor (`Capacitor.getPlatform() !== 'web'`). En web il ne s'exécute pas → pas de conflit avec le scroll natif Safari iOS web.

### Viewport meta WKWebView
Pour bloquer définitivement le zoom auto en Capacitor iOS (même si une régression font-size < 16px arrivait), ajouter dans `ios/App/App/Info.plist` ou `capacitor.config.ts` :

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
```

Le `user-scalable=no` empêche le zoom utilisateur sur les inputs. Sur le web, c'est déconseillé (accessibilité) — uniquement pour le wrapper Capacitor.

### Safe area
Déjà géré dans `index.css` avec `env(safe-area-inset-*)` sur body, dialogs, fixed-bottom-bar. Vérifier au Sprint 18 que ces protections fonctionnent bien en WKWebView iOS (notch / Dynamic Island).

## Validation post-hotfix

✅ Pages auth (connexion, inscription soignant/étab, reset password) : ne sautent plus, pas de zoom, layout stable au clavier
✅ Textarea shadcn : 16px sur mobile, plus de zoom auto (impact 7 formulaires utilisateurs)
✅ Pages publiques + layouts : `min-h-[100dvh]` cohérent partout
✅ Non-régression desktop : `100dvh ≡ 100vh` desktop, retraits JS invisibles, `text-base md:text-sm` conserve desktop

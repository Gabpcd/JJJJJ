# Tests E2E Playwright — Jolene

Date : 2026-05-03

## Vue d'ensemble

Les tests E2E utilisent **Playwright** pour simuler un vrai utilisateur naviguant
dans l'app via browser (Chromium, Firefox, WebKit, mobile iPhone/Pixel/iPad).

### Structure

```
e2e/
├── helpers/
│   ├── auth.ts        # loginAs(page, 'soignant'), generateTestUser(), TEST_ACCOUNTS
│   ├── db.ts          # adminClient, resetTestAccount, cleanupTestAccounts
│   └── wait.ts        # waitForToast, waitForLoadingDone, assertFastLoad
├── accueil.spec.ts            # tests landing
├── auth.spec.ts               # login, états page connexion
├── inscription.spec.ts        # inscription soignant + étab + reset password
├── missions.spec.ts           # navigation publique missions
├── navigation-publique.spec.ts # routes publiques
└── regression.spec.ts         # tests régression bugs critiques fixés
```

## Lancer en local

```bash
# Lancer la suite complète (chromium par défaut local)
npm run test:e2e

# Mode interactif (UI Mode — sélectionne tests, voit traces)
npm run test:e2e:ui

# Un fichier précis
npx playwright test e2e/inscription

# Un test précis (par titre)
npx playwright test -g "login invalide"

# Sur tous les browsers
npx playwright test --project=chromium --project=firefox --project=webkit

# Sur un device mobile
npx playwright test --project=mobile-iphone

# Mode debug (pause sur chaque step, inspecte le DOM)
npx playwright test --debug

# Re-générer les rapports
npx playwright show-report
```

## Variables d'environnement

À mettre dans **`.env.local`** (NE PAS committer) :

```bash
# URL cible des tests (par défaut http://localhost:5173 = Vite dev)
PLAYWRIGHT_BASE_URL=http://localhost:5173

# Pour tests qui appellent la DB (cleanup, seed) — service_role key
SUPABASE_URL=https://flripxtsyegjshnhzjkz.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...

# Pour login compte test fixe (playwright-soignant@jolene.app)
PLAYWRIGHT_TEST_PASSWORD=Playwright!Test2026
```

⚠️ **Le service_role key bypass RLS.** À utiliser uniquement en local ou CI, JAMAIS dans le code applicatif ou commité.

## Comptes test fixes (réutilisables)

Deux comptes sont seedés dans la DB pour les tests login :

| Email | Rôle | Mot de passe |
|---|---|---|
| `playwright-soignant@jolene.app` | SOIGNANT | `PLAYWRIGHT_TEST_PASSWORD` |
| `playwright-etab@jolene.app` | ADMIN_ETABLISSEMENT | idem |
| `admin@jolene.app` | ADMIN_PLATEFORME | `PLAYWRIGHT_ADMIN_PASSWORD` |

### Reset entre tests

```ts
import { resetTestAccount } from './helpers/db';

test.beforeEach(async () => {
  await resetTestAccount('SOIGNANT');
});
```

→ Appelle la RPC `fn_admin_reset_test_account('SOIGNANT')` qui :
- Supprime candidatures, notations, exclusions, notifications, parrainages
- Reset score_fiabilite à 50, missions terminées à 0, heures cumulées à 0

### Comptes éphémères (préfixe `playwright-test-`)

Pour les tests d'inscription qui créent de nouveaux comptes :

```ts
import { generateTestUser } from './helpers/auth';

const user = generateTestUser('soignant');
// → { email: 'playwright-test-soignant-1715-abc@jolene.app', password, prenom, nom, siret }
```

Ces comptes sont supprimés en bloc par `fn_admin_cleanup_test_accounts()` (à exécuter périodiquement via cron).

## Ajouter un nouveau test

1. Créer le fichier dans `e2e/<feature>.spec.ts`.
2. Importer les helpers nécessaires :

```ts
import { test, expect } from '@playwright/test';
import { loginAs } from './helpers/auth';
import { waitForToast } from './helpers/wait';
```

3. Suivre la convention :

```ts
test.describe('Feature X', () => {
  test('comportement attendu', async ({ page }) => {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/missions');
    // assertions...
    await waitForToast(page, 'success', 'Mission créée');
  });
});
```

## Conventions

- **Locators sémantiques** : `getByRole`, `getByText`, `getByLabel` plutôt que `locator('.css-class')` (résilient aux refactos).
- **Attendre explicitement** : `await expect(...).toBeVisible({ timeout: 10_000 })` plutôt que `waitForTimeout`.
- **Cleanup en `afterEach`** : `resetTestAccount` ou `cleanupTestAccounts` selon le besoin.
- **Toasts** : utiliser `waitForToast(page, 'success' | 'error', 'partial text')`.

## Debug d'un test qui échoue

```bash
# Mode debug interactif (pause + DevTools)
npx playwright test e2e/inscription --debug

# Mode UI (timeline visuelle des steps)
npx playwright test e2e/inscription --ui

# Voir le rapport HTML après échec
npx playwright show-report

# Trace viewer (zoom in sur un test précis)
npx playwright show-trace test-results/<test>-retry1/trace.zip
```

Sur CI (échec) :
- Artifacts uploadés : `playwright-report` (HTML) + `playwright-traces` (vidéos, screenshots).
- Télécharger depuis l'UI GitHub Actions → onglet Artifacts.

## Visual regression (à venir)

Pour ajouter des baselines visuelles :

```ts
test('dashboard soignant — visual', async ({ page }) => {
  await loginAs(page, 'soignant');
  await page.goto('/soignant/tableau-de-bord');
  await page.waitForLoadState('networkidle');
  await expect(page).toHaveScreenshot('dashboard-soignant.png');
});
```

Premier run : `npx playwright test --update-snapshots` pour créer les baselines.
Update intentionnel : même commande après vérification visuelle.

## CI GitHub Actions

Workflow : `.github/workflows/playwright.yml`.

- **Trigger** : push main, PR vers main, manuel.
- **Browsers** : Chromium uniquement (gain de temps CI). Cross-browser en local au besoin.
- **Secrets requis** (Settings → Secrets and variables → Actions) :
  - `VITE_SUPABASE_URL`
  - `VITE_SUPABASE_PUBLISHABLE_KEY`
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `PLAYWRIGHT_TEST_PASSWORD`
- **Artifacts** : rapport HTML + traces upload sur échec (rétention 7j).

### Statut commit

Si tests échouent, le commit est marqué rouge sur GitHub. Pour bloquer le merge :
Settings → Branches → main → "Require status checks: Playwright E2E (Chromium)".

## Performance tracking

Helper `assertFastLoad(page, 3_000)` mesure le Time-To-Interactive et soft-fail si > 3s.

```ts
test('dashboard charge rapidement', async ({ page }) => {
  await loginAs(page, 'soignant');
  await page.goto('/soignant/tableau-de-bord');
  const tti = await assertFastLoad(page, 3_000);
  console.log(`TTI: ${tti}ms`);
});
```

## Tests régression bugs critiques

Le fichier `e2e/regression.spec.ts` contient des tests dédiés aux bugs critiques fixés dans les sessions audit :

| Bug | Commit fix | Test |
|---|---|---|
| Page reset password manquante | `6bb3edef` | `Page /reset-password existe (404 si supprimée)` |
| PII email en URL inscription succes | `6bb3edef` | `PII email ne doit plus apparaître dans /inscription/succes URL` |
| Routes admin sans auth → leak | `iter1+` | `non-authentifié → redirection /connexion sur /admin` |
| XSS markdown links centre aide | `6fdda296` | `articles aide chargent sans crash sur les liens` |
| A11y labels htmlFor formulaires | `02470969` | `formulaire inscription a des labels associés aux inputs` |

Ajouter un nouveau test régression : commit fix de référence en commentaire.

## Troubleshooting

| Symptôme | Cause | Fix |
|---|---|---|
| `Error: SUPABASE_SERVICE_ROLE_KEY manquant` | `.env.local` pas chargé | Créer `.env.local` ou exporter la var |
| Tests `loginAs('soignant')` skip | `PLAYWRIGHT_TEST_PASSWORD` pas défini | Compte test pas seedé en DB → exécuter le seed manuel |
| Test timeout sur `waitForLoadState('networkidle')` | Realtime subscription en boucle | Augmenter le timeout ou skip pour ce test |
| `npx playwright install` échoue derrière proxy | Réseau corp | Configurer `HTTP_PROXY` ou `HTTPS_PROXY` |
| Capture vidéo grande | `video: 'on'` au lieu de `'retain-on-failure'` | Vérifier playwright.config.ts |

## Rythme recommandé

- **Local** : `npm run test:e2e` avant chaque commit qui touche le frontend.
- **PR** : workflow CI lance la suite automatiquement.
- **Production** : 1×/jour idéalement (cron CI sur preview Vercel) pour catch les drift backend.

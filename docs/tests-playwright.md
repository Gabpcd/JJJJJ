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
│   ├── seed.ts        # seedMission, seedCandidature, markMissionTerminee, hasTestAccount
│   ├── axe.ts         # runAxe, expectNoCriticalA11y (audit a11y WCAG 2.1 AA)
│   └── wait.ts        # waitForToast, waitForLoadingDone, assertFastLoad
├── flows/
│   ├── candidature.spec.ts          # Flow A — candidature soignant → étab
│   ├── pointage.spec.ts             # Flow B — pointage ouverture/fin
│   ├── notation.spec.ts             # Flow C — notation bidirectionnelle
│   ├── litige.spec.ts               # Flow D + E — litiges + cron 7j
│   ├── parrainage.spec.ts           # Flow F + G — parrainage soignant + étab
│   ├── pool-urgence.spec.ts         # Flow H — opt-in + missions urgentes
│   ├── centre-aide.spec.ts          # Flow I — recherche + article + filtres
│   ├── changer-password.spec.ts     # Flow J — modifier mot de passe
│   ├── suppression-compte.spec.ts   # Flow K — suppression RGPD
│   ├── export-rgpd.spec.ts          # Flow L — fn_exporter_mes_donnees
│   ├── notifications.spec.ts        # Flow M — bell icon + dropdown
│   └── recherche-missions.spec.ts   # Flow N — filtres + sauvegarde
├── a11y.spec.ts                # Audit accessibilité axe-core 9 pages publiques
├── accueil.spec.ts             # Tests landing
├── auth.spec.ts                # Login, états page connexion
├── inscription.spec.ts         # Inscription soignant + étab + reset password
├── missions.spec.ts            # Navigation publique missions
├── navigation-publique.spec.ts # Routes publiques
├── regression.spec.ts          # Tests régression bugs critiques (1ère vague)
└── regression-bugs.spec.ts     # Tests régression exhaustifs (XSS, RLS, etc.)
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

## Visual regression

Tests visuels dans `e2e/visual.spec.ts` (8 pages publiques critiques :
landing, connexion, reset-password, inscription soignant/étab étape 1,
aide, accessibilité, 404).

**Le fichier est exclu de la suite par défaut** (`testIgnore` dans
`playwright.config.ts`) car il nécessite des baselines commitées.

### Génération / mise à jour des baselines

**Workflow GitHub Actions automatique** (recommandé) :
1. Aller dans Actions → "Playwright visual baselines update" → Run workflow.
2. Le workflow lance `npx playwright test e2e/visual --update-snapshots` et
   crée une PR auto `chore/playwright-visual-baselines` avec les screenshots.
3. Reviewer les screenshots dans la PR (changements design intentionnels ?).
4. Merger.

**En local** :
```bash
PLAYWRIGHT_INCLUDE_VISUAL=true npx playwright test e2e/visual --project=chromium --update-snapshots
git add e2e/visual.spec.ts-snapshots/
git commit -m "chore(e2e): update visual baselines"
```

### Tolérance configurée
- `maxDiffPixels: 200` (absorbe le jitter d'antialiasing)
- `threshold: 0.15` (différence relative max par pixel)
- `animations: 'disabled'` (pas de race condition sur animate-pulse)

### Quand mettre à jour les baselines
- Changement design intentionnel sur une page critique
- Refonte composant partagé (Button, Card, Input) impactant le rendu
- Changement de couleur dans `--primary`, `--rose`, etc. (déjà fait dans le commit a11y)

## Lighthouse CI (perf + a11y + best-practices + SEO)

Workflow : `.github/workflows/lighthouse.yml` (PR + push main).
Config : `lighthouserc.cjs` (8 pages publiques auditées).

### Thresholds appliqués
| Catégorie | Min score | Niveau |
|---|---|---|
| Performance | 0.70 | warn (CI runners variables) |
| Accessibility | 0.95 | **error** (échec CI si <0.95) |
| Best Practices | 0.85 | warn |
| SEO | 0.85 | warn |

### Métriques individuelles
- FCP < 3000ms
- LCP < 4000ms
- TBT < 600ms
- CLS < 0.15

### Lancer en local
```bash
npm run build
npx vite preview --port 4173 &
npx lhci autorun
```

### Artifacts
Rapports HTML uploadés dans `lighthouse-reports` (rétention 14j).

## CI GitHub Actions

Workflow : `.github/workflows/playwright.yml`.

### Stratégie matrix

- **PR** → 1 job (`e2e-pr`) : Chromium uniquement pour rapidité (feedback < 5 min)
- **push main** → 5 jobs (`e2e-main` matrix) :
  - chromium
  - firefox
  - webkit (Safari)
  - mobile-iphone (375×812)
  - mobile-pixel (412×915)

`fail-fast: false` : un échec mobile ne stoppe pas Firefox.

### Secrets requis

Settings → Secrets and variables → Actions :
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PLAYWRIGHT_TEST_PASSWORD`

### Artifacts

Rapports HTML + traces (sur échec) uploadés par browser/projet. Rétention 7j.

## Helpers de seed (flows complexes)

Pour les tests qui nécessitent données préparées (mission, candidature, etc.) :

```ts
import { seedMission, markMissionTerminee, cleanupSeedData } from './helpers/seed';

test('mon flow', async ({ page }) => {
  const m = await seedMission({ intitule: '[playwright-test] X' });
  try {
    // ... test logic
    await markMissionTerminee(m!.id);
  } finally {
    await cleanupSeedData();
  }
});
```

Tous les seeds utilisent le préfixe `[playwright-test]` ou rattachent aux comptes test fixes (`playwright-soignant@jolene.app`, `playwright-etab@jolene.app`).

Cleanup automatique :
- `cleanupSeedData()` supprime les missions du compte test étab avec préfixe
- `cleanupTestAccounts()` supprime les comptes éphémères `playwright-test-%@%`
- Cron périodique recommandé pour garder la DB propre

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

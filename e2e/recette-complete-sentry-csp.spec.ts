import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';

// Build de recette : VITE_SENTRY_DSN=http://recette@127.0.0.2/1
// VITE_SUPABASE_URL=http://127.0.0.2 ; aucun fournisseur réel contacté.
const origin = 'http://127.0.0.2';
const preview = 'http://127.0.0.1:8890';
const configuration = JSON.parse(await readFile(new URL('../vercel.json', import.meta.url), 'utf8'));
const csp = configuration.headers[0].headers.find((h: { key: string }) => h.key === 'Content-Security-Policy').value;

test('connexion et aide PSC : CSP stricte, sonde externe filtrée et erreurs applicatives conservées', async ({ page }, info) => {
  const events: { exception?: { values?: { type?: string; value?: string }[] } }[] = [];
  const unexpected: string[] = [];
  const pageErrors: string[] = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.routeWebSocket('**/*', socket => socket.close());
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    // Worker Replay du SDK en mémoire : ce n’est pas une requête HTTP.
    if (url.protocol === 'blob:' && url.origin === origin) return route.continue();
    if (url.origin === origin && url.pathname === '/api/1/envelope/') {
      const lines = (route.request().postData() ?? '').split('\n');
      if (JSON.parse(lines[1] ?? '{}').type === 'event') events.push(JSON.parse(lines[2]));
      return route.fulfill({ json: {} });
    }
    if (url.hostname === 'fonts.googleapis.com') return route.fulfill({ contentType: 'text/css', body: '' });
    if (url.origin === origin && /^\/(auth|rest|functions)\/v1\//.test(url.pathname)) {
      // Ces deux pages sont publiques ; seule la vérification de disponibilité
      // réseau est permise. Une authentification réelle serait hors de ce banc.
      if (url.pathname === '/functions/v1/health-check' && route.request().method() === 'HEAD') return route.fulfill({ status: 200, body: '' });
      unexpected.push(`${route.request().method()} ${url.pathname}`);
      return route.abort();
    }
    if (url.origin === origin) {
      const response = await route.fetch({ url: `${preview}${url.pathname}${url.search}` });
      if (route.request().resourceType() === 'document') {
        const body = (await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
        return route.fulfill({ response, body, headers: { ...response.headers(), 'content-security-policy': csp } });
      }
      return route.fulfill({ response });
    }
    unexpected.push(`${url.origin}${url.pathname}`);
    return route.abort();
  });
  await page.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
  await page.goto(`${origin}/connexion`);
  await expect(page.getByRole('heading', { name: 'Connexion', exact: true })).toBeVisible();
  await expect(page.getByLabel('Email', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Créer un compte soignant', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Créer un compte établissement', exact: true })).toBeEnabled();
  await page.getByLabel('Mot de passe', { exact: true }).fill('Simulation-sans-compte');
  await page.getByRole('button', { name: 'Afficher le mot de passe' }).click();
  await expect(page.getByLabel('Mot de passe', { exact: true })).toHaveAttribute('type', 'text');
  await info.attach('connexion-aria', { body: await page.locator('#contenu-principal').ariaSnapshot(), contentType: 'text/plain' });
  await page.getByRole('link', { name: '🩺 Aide Pro Santé Connect', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Aide Pro Santé Connect', exact: true })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Questions fréquentes', exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Aide Pro Santé Connect', exact: true })).toBeVisible();
  await info.attach('aide-psc-aria', { body: await page.locator('#main-content').ariaSnapshot(), contentType: 'text/plain' });
  await page.screenshot({ path: info.outputPath('aide-psc.png'), fullPage: true });
  await page.getByRole('link', { name: 'Se connecter avec PSC', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Connexion', exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Connexion', exact: true })).toBeVisible();
  expect(pageErrors).toEqual([]);

  // Rejeu contrôlé de la signature capturée : vrai SDK de production et
  // transport Sentry intercepté localement, pas une réponse fournisseur réelle.
  await signaler(page, true);
  await signaler(page, false);
  await expect.poll(() => events.some(event => event.exception?.values?.some(value => value.value?.includes('Temoin application')))).toBe(true);
  expect(pageErrors.some(message => message.includes("'unsafe-eval'"))).toBe(true);
  expect(events.filter(event => event.exception?.values?.some(value => value.type === 'EvalError'))).toHaveLength(0);

  // Un eval réellement lancé par un script de la page doit toujours être
  // bloqué par le navigateur ET remonté par Sentry, même avec l’extension.
  await page.evaluate(() => {
    console.info('backpack: secure-background FromContentScriptTransportSender: Request [object Object]');
    const button = document.createElement('button');
    button.id = 'csp-probe'; button.textContent = 'Sonde CSP locale';
    document.body.append(button);
    const script = document.createElement('script');
    script.textContent = "document.getElementById('csp-probe').addEventListener('click', () => { void Promise.resolve().then(() => eval('document.documentElement.dataset.evalExecuted = 1')); });";
    document.head.append(script);
  });
  await page.getByRole('button', { name: 'Sonde CSP locale', exact: true }).click();
  await expect.poll(() => events.some(event => event.exception?.values?.some(value => value.type === 'EvalError'))).toBe(true);
  await expect(page.locator('html')).not.toHaveAttribute('data-eval-executed');
  await expect(page.getByRole('heading', { name: 'Connexion', exact: true })).toBeVisible();
  expect(unexpected).toEqual([]);
  await info.attach('sentry-recu-local.json', { body: JSON.stringify({ fournisseur: 'simulé', events, cspUnsafeEval: csp.includes("'unsafe-eval'") }, null, 2), contentType: 'application/json' });
});

async function signaler(page: Page, injected: boolean) {
  await page.evaluate(injected => {
    console.info('backpack: secure-background FromContentScriptTransportSender: Request [object Object]');
    if (injected) {
      const error = new EvalError("Refused to evaluate a string as JavaScript because 'unsafe-eval' is not an allowed source of script in the following Content Security Policy directive: \"script-src 'self'\".");
      error.stack = `${error.name}: ${error.message}\n    at eval (<anonymous>)\n    at predicate (<anonymous>:234:30)\n    at next (<anonymous>:234:30)`;
      setTimeout(() => { void Promise.reject(error); }, 0);
    } else {
      setTimeout(() => { throw new Error('Temoin application conservé'); }, 0);
    }
  }, injected);
}

import { expect } from '@playwright/test';
import { test } from './helpers/simulation-websocket-isolee';

// Vrai bundle de production et vrai helper Vite ; seul le transport d'un chunk
// est défaillant. Aucune API, session authentifiée ou transmission fournisseur.
for (const cible of ['page', 'dependance'] as const) {
for (const panne of ['temporaire', 'persistante', 'module'] as const) {
  test(`préchargement ${cible} — ${panne}, erreur d’origine et reprise visible`, async ({ page }, info) => {
    const documents: string[] = [];
    const erreursSecondaires: string[] = [];
    let appelsChunk = 0;
    let retabli = false;
    page.on('request', request => {
      if (request.resourceType() === 'document' && request.isNavigationRequest()
        && request.frame() === page.mainFrame()) documents.push(new URL(request.url()).pathname);
    });
    page.on('console', message => {
      if (message.type() === 'error' && /_result\.default|reading ['"]default|default.*undefined|undefined.*default/i.test(message.text())) {
        erreursSecondaires.push('module-undefined');
      }
    });
    await page.addInitScript(() => {
      localStorage.setItem('cookie-consent', 'refused');
      window.addEventListener('vite:preloadError', event => {
        queueMicrotask(() => {
          const precedente = JSON.parse(sessionStorage.getItem('recette-preload') || '[]');
          precedente.push({ cancelled: event.defaultPrevented });
          sessionStorage.setItem('recette-preload', JSON.stringify(precedente));
        });
      });
    });
    await page.route(cible === 'page' ? '**/assets/PageContact-*.js' : '**/assets/send-*.js', async route => {
      appelsChunk++;
      if (panne === 'module') {
        // Les octets restent identiques avant/après : simuler une exception
        // applicative, sans remplacer le contenu d'une URL immutable.
        const response = await route.fetch();
        return route.fulfill({ response, body: `if (sessionStorage.getItem('recette-module-retablie') !== '1') throw new Error("Erreur applicative de recette");\n${await response.text()}` });
      }
      if (retabli || (panne === 'temporaire' && appelsChunk > 1)) return route.continue();
      return route.fulfill({ status: 404, contentType: 'text/javascript', body: '' });
    });
    await page.goto('/contact?debug=1', { waitUntil: 'commit' });
    if (panne !== 'temporaire') {
      if (panne === 'persistante') {
        // Le second import appartient au document rechargé : ne pas inspecter
        // l'ErrorBoundary transitoire juste avant la navigation automatique.
        await expect.poll(() => appelsChunk).toBe(2);
      }
      await expect(page.getByRole('heading', { name: 'Une erreur est survenue' })).toBeVisible();
      await page.getByText('Détails techniques', { exact: true }).click();
      const details = page.locator('details');
      await expect(details).toContainText(panne === 'module'
        ? 'Erreur applicative de recette'
        : /Importing a module script failed|Failed to fetch dynamically imported module|modulepreload/i);
      await expect(details).not.toContainText(/_result\.default|undefined.*default|default.*undefined/i);
      expect(documents).toHaveLength(panne === 'module' ? 1 : 2);
      await page.screenshot({ path: info.outputPath('panne-visible.png'), animations: 'disabled' });
      await info.attach('panne-visible-aria', { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
      retabli = true;
      if (panne === 'module') await page.evaluate(() => sessionStorage.setItem('recette-module-retablie', '1'));
      await page.getByRole('button', { name: 'Rafraîchir la page' }).click();
    }
    await expect(page.getByRole('heading', { name: 'Une question ? Écrivez-nous.' })).toBeVisible();
    await expect(page.getByLabel('Votre nom *', { exact: true })).toBeVisible();
    expect(documents).toHaveLength(panne === 'persistante' ? 3 : 2);
    expect(appelsChunk).toBe(panne === 'persistante' ? 3 : 2);
    const evenements = await page.evaluate(() => JSON.parse(sessionStorage.getItem('recette-preload') || '[]'));
    expect(evenements.length).toBeGreaterThan(0);
    expect(evenements.every((e: { cancelled: boolean }) => e.cancelled === false)).toBe(true);
    expect(erreursSecondaires).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
    await page.screenshot({ path: info.outputPath('page-retablie.png'), animations: 'disabled' });
    await info.attach('page-retablie-aria', { body: await page.locator('body').ariaSnapshot(), contentType: 'text/plain' });
    await info.attach('reprise-chunk', { body: JSON.stringify({ simulationTransport: true, cible, panne,
      documents: documents.length, appelsChunk, evenements, erreursSecondaires, fournisseur: false }), contentType: 'application/json' });
  });
}
}

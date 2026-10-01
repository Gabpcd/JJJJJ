import { expect, test, type Locator } from '@playwright/test';
import { simulerEtablissement, ids, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Simulation fermée du vrai frontend. Aucun diagnostic cloud ni paiement.
const erreurFr = 'Le diagnostic financier est indisponible pour le moment. Réessayez dans quelques instants.';
const conforme = 'Aucun écart détecté dans les contrôles effectués.';
function resultat(cas: 'coherent' | 'avoir' | 'ecart') {
  return {
    success: true, controle_documentaire_version: 2, genere_le: '2026-10-01T12:00:00Z', factures_verifiees: 2,
    missions_incoherentes: { count: 0, echantillon: [] },
    stripe_transfers_orphelins: { count: 0, echantillon: [] },
    factures_ecart_mission: { count: cas === 'ecart' ? 1 : 0, echantillon: cas === 'ecart' ? [
      { facture_id: ids.facture, numero_facture: 'RECETTE-90', mission_id: ids.mission, montant_ht: 90, attendu_ht: 80, ecart: 10 },
    ] : [] },
    factures_non_verifiables: { count: cas === 'avoir' ? 1 : 0, echantillon: cas === 'avoir' ? [
      { facture_id: ids.facture, numero_facture: 'RECETTE-AVOIR-20', mission_id: ids.mission, motif: 'CORRECTION_MONETAIRE' },
    ] : [] },
  };
}

for (const cas of ['coherent', 'avoir', 'ecart'] as const) {
  test(`admin diagnostic — erreur, reprise, état ${cas} et rechargement`, async ({ page, context, isMobile }, info) => {
    const activer = (element: Locator) => isMobile ? element.tap() : element.click();
    const externes: string[] = [];
    await context.route('**/*', async route => {
      externes.push(`${route.request().method()} ${new URL(route.request().url()).pathname}`);
      await route.abort(); // Inclut la première requête éventuelle d'une popup.
    });
    const { etat } = await simulerEtablissement(page);
    // Le banc n'exerce pas le service worker. Rendre la capacité indisponible
    // évite les appels de registration que Playwright bloque, sans filtrer la console.
    await page.addInitScript(() => {
      if (!Reflect.deleteProperty(Object.getPrototypeOf(navigator), 'serviceWorker') || 'serviceWorker' in navigator)
        throw new Error('Service worker non isolé dans la simulation');
    });
    const consoleMessages: { type: string; text: string }[] = [];
    page.on('console', message => { if (['error', 'warning'].includes(message.type())) consoleMessages.push({ type: message.type(), text: message.text() }); });
    etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
    etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
    etat.overrides.set('factures', []);
    etat.overrides.set('missions', []);
    etat.overrides.set('stripe_refunds_queue', []);
    await page.route('**/*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (request.isNavigationRequest() && request.resourceType() === 'document' && ['127.0.0.1', 'localhost'].includes(url.hostname)) {
        const response = await route.fetch({ maxRedirects: 0 });
        expect(response.status()).toBeLessThan(300);
        const html = (await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
        return route.fulfill({ response, body: html });
      }
      return route.fallback();
    });
    // Les compteurs exacts des deux canaux sont simulés, sans file fournisseur.
    await page.route('**/rest/v1/stripe_refunds_queue?*', route => route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': '*/0' } }));
    await page.route('**/rest/v1/stripe_transfers?*', route => route.fulfill({ json: [], headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': '*/0' } }));
    let appels = 0;
    let terminer!: () => void;
    const attente = new Promise<void>(resolve => { terminer = resolve; });
    await page.route('**/rest/v1/rpc/fn_diagnostic_coherence_financiere', async route => {
      if (route.request().method() === 'OPTIONS') return route.fallback();
      expect(route.request().method()).toBe('POST');
      expect(route.request().postDataJSON()).toEqual({});
      appels++;
      const headers = { 'access-control-allow-origin': '*' };
      if (appels === 1) {
        await attente;
        return route.fulfill({ status: 400, headers, json: { code: '42703', message: 'column mc.fin_le does not exist', details: null, hint: null } });
      }
      if (appels === 2) {
        const ancien = { ...resultat(cas), controle_documentaire_version: undefined };
        return route.fulfill({ headers, json: ancien });
      }
      return route.fulfill({ headers, json: resultat(cas) });
    });
    await page.addInitScript(({ id }) => {
      sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
        user: { id, email: 'admin-diagnostic@example.invalid', email_confirmed_at: '2026-10-01T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
        access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
      }));
    }, { id: ids.user });
    try {
    await page.goto('/admin/finances');
    await expect(page.getByRole('heading', { name: 'Finances Jolene', exact: true })).toBeVisible();
    const panneau = page.locator('details').filter({ has: page.locator('summary').filter({ hasText: 'Diagnostic de cohérence financière' }) });
    await activer(panneau.locator('summary'));
    try {
      await activer(panneau.getByRole('button', { name: 'Lancer le diagnostic', exact: true }));
      await expect.poll(() => appels).toBe(1);
      await expect(panneau.getByRole('button', { name: 'Analyse en cours…', exact: true })).toBeDisabled();
    } finally { terminer(); }
    const erreur = panneau.getByRole('alert');
    await expect(erreur).toHaveText(erreurFr);
    await expect(panneau).not.toContainText('column mc.fin_le');
    await expect(panneau).not.toContainText('42703');
    await expect(panneau.getByText(conforme, { exact: true })).toHaveCount(0);
    // Le message reste après une autre interaction, sans dépendre d'un toast.
    await activer(panneau.locator('summary'));
    await activer(panneau.locator('summary'));
    await expect(erreur).toHaveText(erreurFr);
    await erreur.scrollIntoViewIfNeeded();
    await page.screenshot({ path: info.outputPath('erreur-persistante.png'), animations: 'disabled', scale: 'css' });
    const reprise = panneau.getByRole('button', { name: 'Réessayer le diagnostic', exact: true });
    await activer(reprise);
    await expect.poll(() => appels).toBe(2);
    await expect(erreur).toHaveText(erreurFr); // Une ancienne réponse n'est pas une preuve correcte.
    await activer(reprise);
    await expect.poll(() => appels).toBe(3);
    await expect(erreur).toHaveCount(0);
    const resultatVisible = cas === 'coherent'
      ? panneau.getByText(conforme, { exact: true })
      : cas === 'avoir'
        ? panneau.getByText('RECETTE-AVOIR-20', { exact: true })
        : panneau.getByText('RECETTE-90', { exact: true });
    const verifier = async () => {
      const notification = page.locator('[data-sonner-toast]').filter({ hasText: 'Diagnostic terminé' });
      await expect(notification).toBeVisible();
      await activer(notification.getByRole('button', { name: 'Close toast', exact: true }));
      await expect(notification).toHaveCount(0);
      await expect(panneau).toContainText('2 pièce(s) contrôlée(s)');
      await expect(panneau.getByText('Pièces avec écart documentaire', { exact: true })).toBeVisible();
      if (cas === 'coherent') await expect(panneau.getByText(conforme, { exact: true })).toBeVisible();
      else await expect(panneau.getByText(conforme, { exact: true })).toHaveCount(0);
      if (cas === 'avoir') {
        await expect(panneau).toContainText('Pièces non vérifiables : 1');
        await expect(panneau).toContainText('RECETTE-AVOIR-20');
        await expect(panneau).toContainText('Leur montant n’est pas déclaré cohérent ou incohérent');
      }
      if (cas === 'ecart') {
        await expect(panneau).toContainText('RECETTE-90');
        await expect(panneau).toContainText(/HT 90,00\s*€/);
        await expect(panneau).toContainText(/HT selon les données figées 80,00\s*€/);
        await expect(panneau).toContainText(/Écart 10,00\s*€/);
      }
      await resultatVisible.scrollIntoViewIfNeeded();
      await expect(resultatVisible).toBeInViewport({ ratio: 1 });
      expect(await resultatVisible.evaluate(element => {
        const rect = element.getBoundingClientRect();
        const dessus = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
        return dessus === element || element.contains(dessus);
      })).toBe(true);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
    };
    await verifier();
    await page.screenshot({ path: info.outputPath(`etat-${cas}.png`), animations: 'disabled', scale: 'css' });
    await stabiliserLectures(page);
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Finances Jolene', exact: true })).toBeVisible();
    await activer(panneau.locator('summary'));
    expect(appels).toBe(3);
    await activer(panneau.getByRole('button', { name: 'Lancer le diagnostic', exact: true }));
    await expect.poll(() => appels).toBe(4);
    await verifier();
    await page.screenshot({ path: info.outputPath(`recharge-${cas}.png`), animations: 'disabled', scale: 'css' });
    await stabiliserLectures(page);

    expect(consoleMessages.filter(m => m.type === 'error')).toHaveLength(1);
    expect(consoleMessages.filter(m => m.type === 'error')[0].text).toMatch(/400/);
    expect(consoleMessages.filter(m => m.type === 'warning')).toEqual([]);
    expect(etat.erreurs).toEqual([]);
    expect(etat.inconnues).toEqual([]);
    expect(externes).toEqual([]);
    expect(etat.operations).toEqual([]);
    expect(etat.ecritures).toEqual([]);
    } finally {
    await info.attach('reseau-console', { body: JSON.stringify({ appels, consoleMessages, inconnues: etat.inconnues, externes, operations: etat.operations, ecritures: etat.ecritures }, null, 2), contentType: 'application/json' });
    }
  });
}

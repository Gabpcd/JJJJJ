import { expect } from '@playwright/test';
import { test, isolerWebSocketsSimules } from './helpers/simulation-websocket-isolee';

test('aperçu public : affichage, indisponibilité sans blocage et reprise après recharge', async ({ page }, info) => {
  await isolerWebSocketsSimules(page);
  await page.addInitScript(() => {
    localStorage.setItem('cookie-consent', 'refused');
    sessionStorage.setItem('inscription_profession', 'IDE');
  });
  const erreurs: string[] = [], inconnues: string[] = [], consoleInattendue: string[] = [];
  page.on('pageerror', () => erreurs.push('javascript'));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const refusSimule = message.location().url.includes('/rpc/fn_apercu_marche_profession')
      && /503/.test(message.text());
    if (!refusSimule) consoleInattendue.push(message.text());
  });
  await page.route('https://fonts.googleapis.com/**', route => route.fulfill({ contentType: 'text/css', body: '' }));
  let panne = false, missions = 3, appels = 0;
  await page.route('**/rest/v1/**', async route => {
    const req = route.request(), nom = new URL(req.url()).pathname.split('/').pop();
    if (nom !== 'fn_apercu_marche_profession' || req.method() !== 'POST') {
      inconnues.push(`${req.method()} ${nom}`);
      return route.abort();
    }
    expect(req.postDataJSON()).toEqual({ p_profession: 'IDE', p_lat: null, p_lng: null, p_rayon_km: null });
    appels++;
    return route.fulfill(panne
      ? { status: 503, json: { message: 'Indisponible pour la simulation' } }
      : { json: { nb_missions: missions, nb_etablissements: 2, taux_max: 28, taux_moyen: 25, zone: 'national' } });
  });
  await page.goto('/inscription/succes?role=soignant');
  await expect(page.getByRole('heading', { name: 'Bienvenue sur Jolene !' })).toBeVisible();
  await expect(page.getByRole('status')).toContainText('3 missions');
  await expect(page.getByRole('status')).toContainText('28 €/h');
  await page.screenshot({ path: info.outputPath('apercu-public.png'), fullPage: true });
  panne = true;
  const refus = page.waitForResponse(r => r.url().includes('/rpc/fn_apercu_marche_profession') && r.status() === 503);
  await page.reload(); await refus;
  await expect(page.getByRole('status')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Accéder à mon espace' })).toBeEnabled();
  await expect(page.getByRole('heading', { name: 'Bienvenue sur Jolene !' })).toBeVisible();
  panne = false; missions = 0;
  await page.reload();
  await expect(page.getByRole('status')).toContainText('2 établissements de santé');
  await expect(page.getByRole('status')).not.toContainText('3 missions');
  await expect(page.getByRole('button', { name: 'Accéder à mon espace' })).toBeEnabled();
  await expect(page.getByRole('status')).toContainText('complétez votre dossier lorsque vous souhaitez candidater');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
  expect(appels).toBe(3);
  // Sur ce parcours explicitement anonyme, l'accès à l'espace conduit à la
  // connexion : vérifier l'action visible, sans fabriquer de session réelle.
  await page.getByRole('button', { name: 'Accéder à mon espace' }).click();
  await expect(page).toHaveURL(/\/connexion$/);
  await expect(page.getByLabel('Email', { exact: true })).toBeVisible();
  expect(inconnues).toEqual([]); expect(erreurs).toEqual([]); expect(consoleInattendue).toEqual([]);
  await info.attach('preuve-apercu-public', { body: JSON.stringify({ simulation: true, appels, erreurs, inconnues, consoleInattendue, reprise: true, accesConnexion: true }), contentType: 'application/json' });
});

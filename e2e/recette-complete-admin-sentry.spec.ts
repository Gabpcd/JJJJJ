import { expect, test, type Page } from '@playwright/test';
import { createServer, type Server } from 'node:http';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Deux builds de recette possibles : sans DSN (CI habituelle), ou avec le DSN
// local fictif http://recette@127.0.0.1:18997/1. Aucun fournisseur n'est contacté.
const configure = process.env.RECETTE_SENTRY_CONFIGURE === '1';
const evenements = new Set<string>();
const erreursTransport: string[] = [];
let statutReponse = 200;
let serveur: Server | undefined;

test.beforeAll(async () => {
  if (!configure) return;
  // Réponse HTTP locale réelle : le SDK conserve son transport keepalive au
  // rechargement, sans course d'interception Playwright lors du pagehide WebKit.
  serveur = createServer((req, res) => {
    const headers = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST,OPTIONS', 'content-type': 'application/json' };
    if (req.method === 'OPTIONS') { res.writeHead(204, headers).end(); return; }
    if (req.method !== 'POST' || !req.url?.startsWith('/api/1/envelope/?')) {
      erreursTransport.push('Requête locale imprévue'); res.writeHead(404, headers).end('{}'); return;
    }
    const morceaux: Buffer[] = [];
    req.on('data', morceau => morceaux.push(morceau));
    req.on('end', () => {
      try {
        const lignes = Buffer.concat(morceaux).toString('utf8').split('\n');
        // Replays/transactions peuvent contenir le texte de l'écran : seule
        // l'exception exacte compte ; un retry SDK conserve son identifiant.
        if (JSON.parse(lignes[1] ?? '{}').type === 'event') {
          const e = JSON.parse(lignes[2]);
          if (e.exception?.values?.some((v: { value?: string }) => v.value === 'Sentry test event from /admin/status')) {
            if (!/^[a-f0-9]{32}$/i.test(e.event_id) || e.tags?.test !== 'true' || e.tags?.source !== 'admin-diagnostic') erreursTransport.push('Événement local incomplet');
            evenements.add(e.event_id);
          }
        }
      } catch { erreursTransport.push('Enveloppe locale invalide'); }
      res.writeHead(statutReponse, headers).end('{}');
    });
  });
  await new Promise<void>((resolve, reject) => {
    serveur!.once('error', reject);
    serveur!.listen(18997, '127.0.0.1', resolve);
  });
});
test.afterAll(async () => {
  if (!serveur?.listening) return;
  serveur.closeAllConnections();
  await new Promise<void>((resolve, reject) => serveur!.close(error => error ? reject(error) : resolve()));
});
const warm: Record<string, unknown> = {
  'stripe-config-health': { authenticated: true, livemode: true, mode: 'live', production_ready: true },
  'send-sms': { warm: true }, 'send-email': { warm: true },
  'verify-document': { configured: true, reachable: true, model: 'simulation' },
  'psc-authorize': { configured: true },
  'test-piste-credentials': { success: true, diagnostics: [{ step: 'OAuth', status: 'OK' }] },
  'verify-rpps': { configured: true }, 'verify-finess': { configured: true },
};

async function preparer(page: Page, statutTransport = 200) {
  statutReponse = statutTransport; evenements.clear(); erreursTransport.length = 0;
  const { etat } = await simulerEtablissement(page);
  // Le produit exclut volontairement les traces provenant de localhost.
  // Cette origine virtuelle est entièrement servie depuis la preview locale,
  // sans changer cette protection ni résoudre/contacter un domaine externe.
  // Même protocole HTTP que les API locales : WebKit bloque sinon le contenu
  // mixte avant interception. Cette adresse loopback n'est jamais contactée.
  const origine = 'http://127.0.0.2';
  const preview = new URL(process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8890');
  expect(['127.0.0.1', 'localhost']).toContain(preview.hostname);
  if (configure) {
    if (page.context().browser()?.browserType().name() === 'chromium') {
      // Permission du contexte jetable limitée à l'origine de simulation ;
      // nécessaire pour le fournisseur fictif loopback, jamais en production.
      await page.context().grantPermissions(['local-network-access'], { origin: origine });
    }
    // Worker Replay créé en mémoire par le SDK ; aucune requête réseau.
    await page.route(`blob:${origine}/**`, route => route.continue());
    await page.route(`${origine}/**`, async route => {
      const url = new URL(route.request().url());
      const response = await route.fetch({ url: `${preview.origin}${url.pathname}${url.search}` });
      if (route.request().resourceType() === 'document') {
        const body = (await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, '');
        return route.fulfill({ response, body });
      }
      return route.fulfill({ response });
    });
  }
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('health_check', []);
  etat.overrides.set('fn_admin_health_check', {
    timestamp: '2026-09-30T08:00:00Z', database: { connected: true, version: 'simulation' },
    crons: { crons: [], alertes_emises: 0 }, alertes_actives: [],
    stripe_webhooks: { total_24h: 0, avec_erreur: 0, non_traites: 0, taux_erreur_pct: 0 },
    stats_temps_reel: { soignants_actifs_7j: 0, missions_ouvertes: 0, missions_assignees: 0, missions_en_cours: 0, candidatures_pending: 0, litiges_ouverts: 0 },
    logs_recents: { audit_24h: 0, emails_24h: 0, sms_24h: 0, notifications_24h: 0 },
  });
  await page.route('**/functions/v1/**', async route => {
    const req = route.request(), nom = new URL(req.url()).pathname.split('/').pop()!;
    if (nom === 'health-check' && req.method() === 'HEAD') return route.fulfill({ status: 200, body: '', headers: { 'access-control-allow-origin': '*' } });
    if (!(nom in warm) || req.method() !== 'POST') return route.fallback();
    const attendu = ['stripe-config-health', 'test-piste-credentials'].includes(nom)
      ? {} : nom === 'verify-document' ? { warm: true, probe: true } : { warm: true };
    expect(req.postDataJSON()).toEqual(attendu);
    return route.fulfill({ json: warm[nom], headers: { 'access-control-allow-origin': '*' } });
  });
  await page.route('http://127.0.0.1:18997/api/1/envelope/**', route => route.continue());
  await page.addInitScript(({ id }) => {
    sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-30T08:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
      expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    }));
  }, { id: ids.user });
  await page.goto(configure ? `${origine}/admin/status` : '/admin/status');
  await expect(page.getByRole('heading', { name: 'État du système', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Revérifier', exact: true })).toBeEnabled();
  return { etat };
}

for (const statut of configure ? [200, 500] : [null]) {
  test(`admin — Sentry ${statut === null ? 'non configuré' : `tentative avec transport simulé ${statut}`} et reprise`, async ({ page }, info) => {
    const { etat } = await preparer(page, statut ?? 200);
    const diagnostic = page.getByRole('region', { name: 'Diagnostic Sentry' });
    const bouton = diagnostic.getByRole('button', { name: 'Tester Sentry', exact: true });
    const carte = page.getByText('Sentry Monitoring', { exact: true }).locator('../..');
    await expect(carte).toContainText('Non vérifié');
    await expect(carte).not.toContainText('Opérationnel');
    await diagnostic.scrollIntoViewIfNeeded();
    if (configure) {
      await expect(bouton).toBeEnabled();
      await bouton.click();
      await expect(diagnostic.getByRole('status')).toContainText('Tentative d’envoi effectuée. La réception reste à confirmer dans Sentry.');
      await expect.poll(() => evenements.size).toBe(1);
    } else {
      await expect(diagnostic).toContainText('Sentry non configuré pour cette version.');
      await expect(bouton).toBeDisabled();
      await bouton.click({ force: true });
      expect(evenements.size).toBe(0);
    }
    await expect(page.getByText('Erreur test envoyée à Sentry. Vérifiez le dashboard.', { exact: true })).toHaveCount(0);
    await preuve(page, `sentry-${statut ?? 'absent'}-diagnostic`, info);
    await page.getByRole('button', { name: 'Revérifier', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Revérifier', exact: true })).toBeEnabled();
    await expect(carte).toContainText('Non vérifié');
    await stabiliserLectures(page);
    await page.reload();
    await expect(bouton).toBeVisible();
    await expect(diagnostic.getByRole('status')).toBeEmpty();
    await expect(page.getByRole('button', { name: 'Revérifier', exact: true })).toBeEnabled();
    await expect(carte).toContainText('Non vérifié');
    await stabiliserLectures(page);
    expect(evenements.size).toBe(configure ? 1 : 0);
    expect(erreursTransport).toEqual([]);
    expect(etat.inconnues).toEqual([]);
    expect(etat.erreurs).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)).toBe(true);
    await preuve(page, `sentry-${statut ?? 'absent'}-rechargement`, info);
  });
}

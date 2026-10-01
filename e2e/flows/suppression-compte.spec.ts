import { test, expect, type Request } from '@playwright/test';
import { loginAs } from '../helpers/auth';

// La suppression effective avec le service utilisateur est dans staging/comptes.spec.ts.
// Cette suite partagée ne supprime aucun compte et ne remplace jamais l'action
// utilisateur par auth.admin.deleteUser sous un titre trompeur.
test('le compte connecté accède à la confirmation réelle de suppression et peut annuler', async ({ page }, testInfo) => {
  // Le premier échec doit conserver les requêtes en attente, même quand la
  // trace du retry réussit. Ne collecter ni URL complète, ni en-tête, ni corps :
  // les comptes connectés et leurs jetons ne doivent pas entrer dans ce JSON.
  const startedAt = Date.now();
  const observed = new Map<Request, { name: string; startMs: number; endMs?: number; status?: number; failed?: boolean }>();
  const rpcNames = new Set([
    'fn_get_my_role', 'fn_mon_profil_soignant_complet', 'fn_note_moyenne',
    'fn_mes_evaluations_recues', 'fn_badge_stats', 'fn_mes_evenements_score',
  ]);
  let pageErrorCount = 0;
  const onPageError = () => { pageErrorCount += 1; };
  const onRequest = (request: Request) => {
    const pathname = new URL(request.url()).pathname;
    const rpc = pathname.startsWith('/rest/v1/rpc/') ? pathname.slice('/rest/v1/rpc/'.length) : '';
    const name = rpcNames.has(rpc) ? rpc
      : /^\/assets\/ProfilSoignant-[\w-]+\.js$/.test(pathname) ? 'module-profil-soignant' : null;
    if (name && observed.size < 100) observed.set(request, { name, startMs: Date.now() - startedAt });
  };
  const onResponse = (response: import('@playwright/test').Response) => {
    const entry = observed.get(response.request());
    if (entry) entry.status = response.status();
  };
  const onFinished = (request: Request) => {
    const entry = observed.get(request);
    if (entry) entry.endMs = Date.now() - startedAt;
  };
  const onFailed = (request: Request) => {
    const entry = observed.get(request);
    if (entry) { entry.failed = true; entry.endMs = Date.now() - startedAt; }
  };
  page.on('request', onRequest);
  page.on('response', onResponse);
  page.on('requestfinished', onFinished);
  page.on('requestfailed', onFailed);
  page.on('pageerror', onPageError);
  try {
    await loginAs(page, 'soignant');
    await page.goto('/soignant/profil?tab=confidentialite#suppression-compte');
    await expect(page.getByRole('heading', { name: 'Suppression de compte', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Supprimer mon compte', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toBeDisabled();
    await page.getByPlaceholder('Tape SUPPRIMER').fill('SUPPRIMER');
    await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toBeEnabled();
    await page.getByRole('button', { name: 'Annuler', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Supprimer définitivement' })).toHaveCount(0);
  } finally {
    page.off('request', onRequest);
    page.off('response', onResponse);
    page.off('requestfinished', onFinished);
    page.off('requestfailed', onFailed);
    page.off('pageerror', onPageError);
    await testInfo.attach('chargement-profil-diagnostic', {
      contentType: 'application/json',
      body: Buffer.from(JSON.stringify({
        durationMs: Date.now() - startedAt,
        pageErrorCount,
        requests: [...observed.values()],
      }, null, 2)),
    });
  }
});

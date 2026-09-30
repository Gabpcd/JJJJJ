import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Contrat d'affichage avec réponses simulées. Aucun cron ni fournisseur invoqué.
test('admin — pause nocturne Chorus sans fausse alerte, vrai retard puis reprise après rechargement', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('health_check', [{ id: 1 }]);
  const source = 'sync-chorus-status-hourly';
  const message = `Cron "${source}" en retard (dernier run : 2026-09-29 21:00:01+00)`;
  let lectures = 0;
  let instant = '2026-09-30T06:59:00Z';
  let dernier = '2026-09-29T21:00:01Z';
  let retard = false;
  await page.route('**/rest/v1/rpc/fn_admin_health_check', async route => {
    lectures++;
    await route.fulfill({ json: {
      timestamp: instant, database: { connected: true, version: '17.6' },
      crons: { crons: [{ jobid: 18, jobname: source, schedule: '0 7-22/2 * * *', dernier_run: dernier, dernier_statut: 'succeeded', retard, echec: false }], alertes_emises: retard ? 1 : 0 },
      stripe_webhooks: { total_24h: 0, avec_erreur: 0, non_traites: 0, taux_erreur_pct: 0 },
      alertes_actives: retard ? [{ id: '99023000-0000-4000-8000-000000000001', type: 'CRON_RETARD', severite: 'WARNING', source, message, cree_le: instant }] : [],
      stats_temps_reel: { soignants_actifs_7j: 0, missions_ouvertes: 0, missions_assignees: 0, missions_en_cours: 0, candidatures_pending: 0, litiges_ouverts: 0 },
      logs_recents: { audit_24h: 0, emails_24h: 0, sms_24h: 0, notifications_24h: 0 },
    } });
  });
  const reponsesServices: Record<string, unknown> = {
    'stripe-config-health': { authenticated: true, livemode: true, mode: 'live', production_ready: true },
    'send-sms': { warm: true }, 'verify-document': { configured: true, reachable: true, model: 'simulation' },
    'send-email': { warm: true }, 'psc-authorize': { configured: true },
    'test-piste-credentials': { success: true }, 'verify-rpps': { configured: true }, 'verify-finess': { configured: true },
  };
  await page.route('**/functions/v1/*', async route => {
    const nom = new URL(route.request().url()).pathname.split('/').pop()!;
    if (nom === 'health-check') { expect(route.request().method()).toBe('HEAD'); return route.fulfill({ status: 200 }); }
    expect(Object.keys(reponsesServices)).toContain(nom);
    return route.fulfill({ json: reponsesServices[nom] });
  });
  await page.addInitScript(({ id }) => {
    sessionStorage.setItem('sb-127-auth-token', JSON.stringify({
      user: { id, email: 'admin-recette@example.invalid', email_confirmed_at: '2026-09-28T12:00:00Z', app_metadata: { role: 'ADMIN_PLATEFORME' }, user_metadata: {}, aud: 'authenticated', role: 'authenticated' },
      access_token: 'simulation-admin', refresh_token: 'simulation-admin-refresh', token_type: 'bearer',
      expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
    }));
  }, { id: ids.user });
  await page.goto('/admin/status');
  await expect(page.getByRole('heading', { name: 'État du système', exact: true })).toBeVisible();
  await expect(page.getByText('1 OK', { exact: true })).toBeVisible();
  await expect(page.getByText(/Alertes actives/)).toHaveCount(0);
  await preuve(page, 'chorus-nuit-sans-fausse-alerte', info);
  await page.screenshot({ path: info.outputPath('chorus-nuit.png'), fullPage: false, animations: 'disabled' });
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText('1 OK', { exact: true })).toBeVisible();
  await expect(page.getByText(/Alertes actives/)).toHaveCount(0);

  instant = '2026-09-30T08:01:00Z'; retard = true;
  await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
  await expect(page.getByText('Alertes actives (1)', { exact: true })).toBeVisible();
  await expect(page.getByText('1 retard', { exact: true })).toBeVisible();
  await expect(page.getByText(message, { exact: true })).toBeVisible();
  await preuve(page, 'chorus-retard-reel', info);
  await page.screenshot({ path: info.outputPath('chorus-retard.png'), fullPage: false, animations: 'disabled' });
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText('Alertes actives (1)', { exact: true })).toBeVisible();
  await expect(page.getByText(message, { exact: true })).toBeVisible();

  // État après reprise et auto-résolution déjà opérée côté backend simulé.
  // On ne clique jamais sur Résoudre et on ne simule pas un changement de cron.
  instant = '2026-09-30T08:21:00Z'; dernier = '2026-09-30T07:00:01Z'; retard = false;
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText('1 OK', { exact: true })).toBeVisible();
  await expect(page.getByText(/Alertes actives/)).toHaveCount(0);
  await preuve(page, 'chorus-reprise-apres-auto-resolution', info);
  expect(lectures).toBeGreaterThanOrEqual(5);
  expect(etat.appels.some(a => a.includes('resoudre_alerte'))).toBe(false);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]);
});

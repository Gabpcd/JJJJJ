import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// RPC simulée sur la vraie page ; aucun cron ni fournisseur réel appelé.
test('admin — paiement Connect fermé, reprise et rechargement du diagnostic', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('health_check', [{ id: 1 }]);
  let ouvert = false;
  let lectures = 0;
  etat.overrides.set('fn_admin_health_check', {
    timestamp: '2026-10-16T12:00:00Z', database: { connected: true, version: '17' },
    crons: { crons: [], alertes_emises: 0 }, stripe_webhooks: { total_24h: 0, avec_erreur: 0, non_traites: 0, taux_erreur_pct: 0 },
    alertes_actives: [], stats_temps_reel: {}, logs_recents: {},
  });
  const services: Record<string, unknown> = {
    'stripe-config-health':{authenticated:true,livemode:true,mode:'live',production_ready:true},
    'send-sms':{warm:true},'verify-document':{configured:true,reachable:true,model:'simulation'},
    'send-email':{warm:true},'psc-authorize':{configured:true},'test-piste-credentials':{success:true},
    'verify-rpps':{configured:true},'verify-finess':{configured:true},
  };
  await page.route('**/functions/v1/*', async route => {
    const nom = new URL(route.request().url()).pathname.split('/').pop()!;
    if (nom==='health-check') { expect(route.request().method()).toBe('HEAD'); return route.fulfill({status:200}); }
    if (nom === 'stripe-config-health') {
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
      lectures++;
      return route.fulfill({ status: ouvert ? 200 : 503, json: { authenticated: true, livemode: true, mode: 'live',
        production_ready: ouvert, connect_release_checked: true, connect_release_open: ouvert,
        ...(!ouvert ? { error: 'Paiement groupé libéral indisponible : ouverture Connect non effectuée.' } : {}),
      } });
    }
    expect(Object.keys(services)).toContain(nom); return route.fulfill({json:services[nom]});
  });
  await page.addInitScript(({id}) => {
    sessionStorage.setItem('sb-127-auth-token',JSON.stringify({
      user:{id,email:'admin-recette@example.invalid',email_confirmed_at:'2026-09-28T12:00:00Z',app_metadata:{role:'ADMIN_PLATEFORME'},user_metadata:{},aud:'authenticated',role:'authenticated'},
      access_token:'simulation-admin',refresh_token:'simulation-admin-refresh',token_type:'bearer',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,
    }));
  },{id:ids.user});
  await page.goto('/admin/status');
  await expect(page.getByRole('heading',{name:'État du système',exact:true})).toBeVisible();
  const fermeture = page.getByText('Paiement groupé libéral indisponible : ouverture Connect non effectuée.', { exact: true });
  await expect(fermeture).toBeVisible();
  await expect(page.getByText('Tous les services sont opérationnels', { exact: true })).toHaveCount(0);
  await preuve(page, 'connect-ferme-diagnostic', info);
  await stabiliserLectures(page); await page.reload();
  await expect(fermeture).toBeVisible();
  ouvert = true;
  await page.getByRole('button', { name: 'Revérifier', exact: true }).click();
  await expect(fermeture).toHaveCount(0);
  await expect(page.getByText('Clé live authentifiée · webhook live actif et complet', { exact: true })).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText('Clé live authentifiée · webhook live actif et complet', { exact: true })).toBeVisible();
  await preuve(page, 'connect-ouvert-diagnostic', info);
  expect(lectures).toBeGreaterThanOrEqual(4);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

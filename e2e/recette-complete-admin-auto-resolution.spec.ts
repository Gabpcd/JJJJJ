import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// Réponses backend simulées : aucune exécution/acquittement réel de cron.
test('admin — reprise du propre cron, alerte financière conservée et échec persistant après reload', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('health_check', [{ id: 1 }]);
  const source = 'jolene_auto_resoudre_alertes';
  const technique = { id:'99023100-0000-4000-8000-000000000001',type:'CRON_FAILED',severite:'CRITICAL',source,
    message:'Échec technique du cron auto-résolution — simulation',cree_le:'2026-09-29T08:20:00Z' };
  const finance = { id:'99023100-0000-4000-8000-000000000002',type:'TRIPWIRE_PREMIER_EURO',severite:'CRITICAL',source:'stripe-webhook',
    message:'Alerte financière de simulation — vérification humaine requise',cree_le:'2026-09-29T08:21:00Z' };
  let etape: 'historique'|'reprise'|'echec' = 'historique';
  let lectures = 0;
  await page.route('**/rest/v1/rpc/fn_admin_health_check', async route => {
    lectures++;
    const resolue = etape === 'reprise';
    await route.fulfill({ json: {
      timestamp:'2026-09-30T08:20:01Z',database:{connected:true,version:'17.6'},
      crons:{crons:[{jobid:23,jobname:source,schedule:'20 */2 * * *',dernier_run:'2026-09-30T08:20:00Z',
        dernier_statut:etape==='echec'?'failed':'running',retard:false,echec:etape==='echec'}],alertes_emises:0},
      stripe_webhooks:{total_24h:0,avec_erreur:0,non_traites:0,taux_erreur_pct:0},
      alertes_actives:resolue?[finance]:[technique,finance],
      stats_temps_reel:{soignants_actifs_7j:0,missions_ouvertes:0,missions_assignees:0,missions_en_cours:0,candidatures_pending:0,litiges_ouverts:0},
      logs_recents:{audit_24h:0,emails_24h:0,sms_24h:0,notifications_24h:0},
    } });
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
  await expect(page.getByText('Alertes actives (2)',{exact:true})).toBeVisible();
  await expect(page.getByText(technique.message,{exact:true})).toBeVisible();
  await expect(page.getByText(finance.message,{exact:true})).toBeVisible();
  await preuve(page,'auto-resolution-historique',info);

  // Le backend a résolu la dernière alerte technique à partir du succès
  // terminé précédent, malgré le propre run actuellement running.
  etape='reprise';
  await page.getByRole('button',{name:'Actualiser',exact:true}).click();
  await expect(page.getByText('Alertes actives (1)',{exact:true})).toBeVisible();
  await expect(page.getByText(technique.message,{exact:true})).toHaveCount(0);
  await expect(page.getByText(finance.message,{exact:true})).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText('Alertes actives (1)',{exact:true})).toBeVisible();
  await expect(page.getByText(technique.message,{exact:true})).toHaveCount(0);
  await expect(page.getByText(finance.message,{exact:true})).toBeVisible();
  await preuve(page,'auto-resolution-reprise-finance-preservee',info);

  etape='echec';
  await page.getByRole('button',{name:'Actualiser',exact:true}).click();
  await expect(page.getByText('Alertes actives (2)',{exact:true})).toBeVisible();
  await expect(page.getByText('1 échec',{exact:true})).toBeVisible();
  await expect(page.getByText(technique.message,{exact:true})).toBeVisible();
  await stabiliserLectures(page); await page.reload();
  await expect(page.getByText('Alertes actives (2)',{exact:true})).toBeVisible();
  await expect(page.getByText(technique.message,{exact:true})).toBeVisible();
  await expect(page.getByText(finance.message,{exact:true})).toBeVisible();
  await preuve(page,'auto-resolution-vrai-echec-persistant',info);
  expect(lectures).toBeGreaterThanOrEqual(5);
  expect(etat.appels.some(a=>a.includes('resoudre_alerte'))).toBe(false);
  expect(etat.inconnues).toEqual([]);expect(etat.erreurs).toEqual([]);expect(etat.ecritures).toEqual([]);
});

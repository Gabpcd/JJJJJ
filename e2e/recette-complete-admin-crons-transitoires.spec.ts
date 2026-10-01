import { expect, test } from '@playwright/test';
import { simulerEtablissement, ids, preuve, stabiliserLectures } from './helpers/recette-complete-etablissement';

// RPC simulée sur la vraie page ; aucun cron ni fournisseur réel appelé.
test('admin — crons en démarrage, exécution, succès et vraies alertes après actualisation/reload', async ({ page }, info) => {
  const { etat } = await simulerEtablissement(page);
  etat.overrides.set('fn_get_my_role', { role: 'ADMIN_PLATEFORME' });
  etat.overrides.set('fn_admin_mes_acces', { acces_total: true, groupes: [] });
  etat.overrides.set('health_check', [{ id: 1 }]);
  const sources = ['email-cron-hourly-immediate', 'messagerie-cleanup', 'auto-transitions-missions',
    'vagues-notification-urgentes', 'jolene_verifier_pointages_incoherents'];
  let etape: 'demarrage' | 'execution' | 'succes' = 'demarrage';
  let lectures = 0;
  await page.route('**/rest/v1/rpc/fn_admin_health_check', async route => {
    lectures++;
    const crons = sources.map((jobname, index) => ({jobid:index+1,jobname,schedule:'* * * * *',
      dernier_demarrage:etape==='demarrage'?null:'2026-10-01T19:30:00Z',
      dernier_run:etape==='succes'?'2026-10-01T19:30:01Z':null,
      dernier_statut:etape==='demarrage'?['starting','connecting','sending','connecting','sending'][index]:etape==='execution'?'running':'succeeded',
      retard:false,echec:false}));
    crons.push({jobid:6,jobname:'recette-execution-bloquee',schedule:'* * * * *',dernier_demarrage:'2026-10-01T17:30:00Z',dernier_run:null,dernier_statut:'running',retard:true,echec:false},
      {jobid:7,jobname:'recette-echec-reel',schedule:'* * * * *',dernier_demarrage:'2026-10-01T19:30:00Z',dernier_run:'2026-10-01T19:30:01Z',dernier_statut:'failed',retard:false,echec:true});
    await route.fulfill({json:{timestamp:'2026-10-01T19:30:01Z',database:{connected:true,version:'17.6'},
      crons:{crons,alertes_emises:0},stripe_webhooks:{total_24h:0,avec_erreur:0,non_traites:0,taux_erreur_pct:0},
      alertes_actives:[{id:'99023200-0000-4000-8000-000000000002',type:'TRIPWIRE_PREMIER_EURO',severite:'CRITICAL',source:'stripe-webhook',
        message:'Alerte financière conservée — simulation',cree_le:'2026-07-27T08:21:00Z'}],
      stats_temps_reel:{soignants_actifs_7j:0,missions_ouvertes:0,missions_assignees:0,missions_en_cours:0,candidatures_pending:0,litiges_ouverts:0},
      logs_recents:{audit_24h:0,emails_24h:0,sms_24h:0,notifications_24h:0}}});
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
  const visible = (texte: string) => page.getByText(texte,{exact:true}).filter({visible:true});
  const verifier = async (statut: string, compteur: string) => {
    await expect(visible(statut)).toHaveCount(5);
    await expect(visible(compteur)).toBeVisible();
    await expect(visible('1 retard')).toBeVisible();
    await expect(visible('1 échec')).toBeVisible();
    await expect(visible('Retard')).toHaveCount(1);
    await expect(visible('Échec')).toHaveCount(1);
    await expect(visible('Alerte financière conservée — simulation')).toBeVisible();
    await expect(page.getByText('CRON_RETARD',{exact:false})).toHaveCount(0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
  };
  await verifier('En démarrage','5 en cours');
  await expect(visible('0 OK')).toBeVisible();
  await preuve(page,'crons-demarrage',info);
  await stabiliserLectures(page); await page.reload();
  await verifier('En démarrage','5 en cours');

  etape='execution';
  await page.getByRole('button',{name:'Actualiser',exact:true}).click();
  await verifier('En cours','5 en cours');
  await preuve(page,'crons-execution',info);

  etape='succes';
  await page.getByRole('button',{name:'Actualiser',exact:true}).click();
  await verifier('OK','5 OK');
  await expect(visible('5 en cours')).toHaveCount(0);
  await stabiliserLectures(page); await page.reload();
  await verifier('OK','5 OK');
  await preuve(page,'crons-succes-alertes-conservees',info);
  expect(lectures).toBeGreaterThanOrEqual(5);
  expect(etat.appels.some(a=>a.includes('resoudre_alerte'))).toBe(false);
  expect(etat.inconnues).toEqual([]); expect(etat.erreurs).toEqual([]); expect(etat.ecritures).toEqual([]);
});

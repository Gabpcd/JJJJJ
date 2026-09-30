import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { setTimeout as attendre } from 'node:timers/promises';
import { STAGING_REF, STAGING_URL } from './prepare-load-fixtures.mjs';
import { dashboardFixtureValide } from '../../tests/load/helpers/contrats.js';
import { configurationUI, ORIGINE_UI, projectionEtatUI, requeteUIAutorisee, sqlEtatUI, sqlGardeUI, verifierEtatUI, verifierGardeUI } from './dashboard-ui-contract.mjs';

const dossier = resolve('tests/load/results/dashboard-ui');
const sauver = (nom, valeur) => { mkdirSync(dossier, { recursive: true }); writeFileSync(`${dossier}/${nom}.json`, JSON.stringify(valeur, null, 2) + '\n'); };
export function dashboardUIValide(data, membre) {
  return dashboardFixtureValide(data, membre.userId)
    && ['missions_ouvertes','mes_missions','documents','gains_6mois','missions_semaine_cal','propositions'].every(k => data[k].length === 0)
    && data.heures_semaine === 0 && data.notifs_non_lues === 0
    && ['nb_missions','brut_total','net_total'].every(k => data.gains_mois[k] === 0);
}
export async function parcourirDashboard(page, membre, { expect, verifierReponse, capturer = async () => {} }) {
  const reponseDashboard = () => page.waitForResponse(r => r.url().endsWith('/rest/v1/rpc/fn_dashboard_soignant_complet') && r.request().method() === 'POST');
  await page.goto('/connexion');
  await page.getByLabel('Email', { exact: true }).fill(membre.email);
  await page.getByLabel('Mot de passe', { exact: true }).fill(membre.password);
  const [premiere] = await Promise.all([reponseDashboard(), page.getByRole('button', { name: 'Se connecter', exact: true }).click()]);
  await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
  await verifierReponse(premiere, membre);
  await expect(page.locator('main').getByRole('heading', { level: 1 })).toContainText('Recette');
  await page.waitForLoadState('networkidle');
  await capturer('dashboard');
  const [deuxieme] = await Promise.all([reponseDashboard(), page.reload()]);
  await verifierReponse(deuxieme, membre);
  await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
  await expect(page.locator('main').getByRole('heading', { level: 1 })).toContainText('Recette');
  await page.waitForLoadState('networkidle');
  await expect(page.getByLabel('Mot de passe', { exact: true })).toHaveCount(0);
  await capturer('recharge');
}

async function lireSQL(query, env) {
  let response;
  try { response = await fetch(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(35_000),
    headers: { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  }); } catch { throw new Error('Lecture backend UI indisponible.'); }
  if (!response.ok) throw new Error('Lecture backend UI refusée.');
  try { return await response.json(); } catch { throw new Error('Lecture backend UI invalide.'); }
}
export async function executerRecetteDashboard({ action = 'run', env = process.env } = {}) {
  const membres = configurationUI(env);
  if (!['run','verify-cleanup'].includes(action)) throw new Error('Action UI inconnue.');
  if (action === 'verify-cleanup') {
    const apres = await lireSQL(sqlEtatUI(membres), env);
    sauver('cleanup', { conforme: false, profils: projectionEtatUI(apres) });
    const avant = JSON.parse(readFileSync(`${dossier}/avant.json`, 'utf8'));
    verifierEtatUI(apres, avant, true); sauver('cleanup', { conforme: true, profils: projectionEtatUI(apres) }); return;
  }
  const [gardes] = await lireSQL(sqlGardeUI, env); verifierGardeUI(gardes);
  const avant = await lireSQL(sqlEtatUI(membres), env); verifierEtatUI(avant); sauver('avant', projectionEtatUI(avant));
  // Les hints DNS/TLS échappent au routage HTTP ; retirer ceux du build de recette.
  const index = resolve('dist/index.html');
  writeFileSync(index, readFileSync(index, 'utf8').replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi, ''));
  const { webkit, devices, expect } = await import('@playwright/test');
  const preview = spawn(process.execPath, ['node_modules/vite/bin/vite.js','preview','--host','localhost','--port','5173','--strictPort'],
    { stdio: 'ignore', env: { PATH: env.PATH, HOME: env.HOME } });
  let browser; const preuves = []; let succes = false;
  try {
    for (let i = 0; i < 60; i++) {
      if (preview.exitCode !== null) throw new Error('Preview UI indisponible.');
      try { if ((await fetch(ORIGINE_UI, { signal: AbortSignal.timeout(500) })).ok) break; } catch { /* lancement borné */ }
      if (i === 59) throw new Error('Preview UI non démarrée.');
      await attendre(200);
    }
    browser = await webkit.launch();
    for (const [slot, appareil] of ['iPhone 13','iPad Pro 11'].entries()) {
      const membre = membres[slot], anomalies = [], lectures = [];
      // Contextes privés en mémoire : aucun storageState, trace, vidéo ou HAR.
      const contexte = await browser.newContext({ ...devices[appareil], baseURL: ORIGINE_UI, locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block' });
      try {
        await contexte.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
        await contexte.routeWebSocket('**/*', socket => socket.close()); // Aucun parcours messagerie/realtime dans cette recette.
        await contexte.route('**/*', async route => {
          const r = route.request(); let body;
          try { body = r.postData() ? r.postDataJSON() : undefined; } catch { anomalies.push('body'); return route.abort(); }
          if (!requeteUIAutorisee({ url: r.url(), method: r.method(), body }, membre)) { anomalies.push('requete-refusee'); return route.abort(); }
          const u = new URL(r.url());
          if (u.origin === STAGING_URL) lectures.push({ methode: r.method(), endpoint: u.pathname });
          return route.continue();
        });
        const page = await contexte.newPage();
        page.setDefaultTimeout(20_000); page.setDefaultNavigationTimeout(25_000);
        page.on('pageerror', () => anomalies.push('javascript')); // Ne jamais sérialiser une exception navigateur.
        await parcourirDashboard(page, membre, { expect,
          verifierReponse: async response => {
            if (response.status() !== 200 || !dashboardUIValide(await response.json(), membre)) throw new Error('Dashboard réel différent du profil minimal attendu.');
          },
          capturer: async etape => {
            if (anomalies.length) throw new Error('Anomalie navigateur UI.');
            // Uniquement le main validé, sans écran de connexion ni données réseau.
            await page.locator('main').screenshot({ path: `${dossier}/slot-${slot}-${etape}.png`, animations: 'disabled' });
          },
        });
        const writes = lectures.filter(r => ['/rest/v1/rpc/fn_audit_connexion','/rest/v1/rpc/fn_maj_activite_soignant'].includes(r.endpoint));
        if (anomalies.length || writes.length !== 2 || new Set(writes.map(r => r.endpoint)).size !== 2) throw new Error('Écritures navigateur UI inattendues.');
        preuves.push({ slot, appareil, connexion_formulaire: true, dashboard_identite: true, recharge: true, anomalies: 0,
          lectures: [...new Set(lectures.map(r => `${r.methode} ${r.endpoint}`))].sort() });
      } finally { await contexte.close(); }
    }
    const apres = await lireSQL(sqlEtatUI(membres), env); sauver('apres', projectionEtatUI(apres)); verifierEtatUI(apres, avant);
    sauver('resultat', { mode: 'staging-reel', succes: true, preuves }); succes = true;
  } finally {
    await browser?.close(); preview.kill('SIGTERM');
    if (!succes) sauver('resultat', { mode: 'staging-reel', succes: false, profils_valides: preuves.length });
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  executerRecetteDashboard({ action: process.argv[2] }).then(() => console.log('Contrôle frontend staging confirmé.'))
    .catch(() => { console.error('Contrôle frontend staging non confirmé ; détails sensibles non publiés. Consulter les preuves structurées et le cleanup.'); process.exitCode = 1; });
}

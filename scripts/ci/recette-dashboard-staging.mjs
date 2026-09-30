import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { demarrerPreview } from './dashboard-ui-preview.mjs';
import { creerDiagnosticUI, bilanCleanupUI } from './dashboard-ui-diagnostic.mjs';
import { STAGING_REF, STAGING_URL } from './prepare-load-fixtures.mjs';
import { dashboardFixtureValide } from '../../tests/load/helpers/contrats.js';
import { configurationUI, ORIGINE_UI, projectionEtatUI, requeteUIAutorisee, sqlEtatUI, sqlGardeUI, verifierEtatUI, verifierGardeUI } from './dashboard-ui-contract.mjs';

const dossier = resolve('tests/load/results/dashboard-ui');
const sauver = (nom, valeur) => { mkdirSync(dossier, { recursive: true }); writeFileSync(`${dossier}/${nom}.json`, JSON.stringify(valeur, null, 2) + '\n'); };
/** Preview isolée : police système de secours, sans modifier le HTML produit. */
export function preparerHtmlPreview(html) {
  return html.replace(/<link\b[^>]*>/gi, balise => {
    const attribut = nom => {
      const valeur = balise.match(new RegExp(`\\b${nom}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i'));
      return valeur?.[1] ?? valeur?.[2] ?? valeur?.[3] ?? '';
    };
    const relations = attribut('rel').toLowerCase().split(/\s+/);
    // Ces hints DNS/TLS échappent au routage HTTP du navigateur.
    if (relations.some(rel => ['preconnect','dns-prefetch'].includes(rel))) return '';
    if (relations.includes('stylesheet') && new URL(attribut('href'), ORIGINE_UI).origin === 'https://fonts.googleapis.com') return '';
    return balise;
  });
}
export function dashboardUIValide(data, membre) {
  return dashboardFixtureValide(data, membre.userId)
    && ['missions_ouvertes','mes_missions','documents','gains_6mois','missions_semaine_cal','propositions'].every(k => data[k].length === 0)
    && data.heures_semaine === 0 && data.notifs_non_lues === 0
    && ['nb_missions','brut_total','net_total'].every(k => data.gains_mois[k] === 0);
}
export async function parcourirDashboard(page, membre, { expect, verifierReponse, capturer = async () => {}, marquerPhase = () => {} }) {
  const reponseDashboard = () => page.waitForResponse(r => r.url().endsWith('/rest/v1/rpc/fn_dashboard_soignant_complet') && r.request().method() === 'POST');
  marquerPhase('page');
  await page.goto('/connexion');
  marquerPhase('login');
  await page.getByLabel('Email', { exact: true }).fill(membre.email);
  await page.getByLabel('Mot de passe', { exact: true }).fill(membre.password);
  const [premiere] = await Promise.all([reponseDashboard(), page.getByRole('button', { name: 'Se connecter', exact: true }).click()]);
  marquerPhase('dashboard');
  await expect(page).toHaveURL(/\/soignant\/tableau-de-bord$/);
  await verifierReponse(premiere, membre);
  await expect(page.locator('main').getByRole('heading', { level: 1 })).toContainText('Recette');
  await page.waitForLoadState('networkidle');
  await capturer('dashboard');
  marquerPhase('reload');
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
  const diagnostic = creerDiagnosticUI();
  if (action === 'verify-preview') {
    diagnostic.phase('preview');
    let preview;
    try {
      preview = await demarrerPreview({ env, observer: etat => sauver('preview', etat) });
    } finally { preview?.kill('SIGTERM'); }
    return;
  }
  const membres = configurationUI(env);
  if (!['run','verify-cleanup'].includes(action)) throw new Error('Action UI inconnue.');
  if (action === 'verify-cleanup') {
    diagnostic.phase('cleanup');
    try {
      const apres = await lireSQL(sqlEtatUI(membres), env);
      const bilan = bilanCleanupUI(apres);
      sauver('cleanup', { conforme: false, ...bilan, profils: projectionEtatUI(apres) });
      const avant = JSON.parse(readFileSync(`${dossier}/avant.json`, 'utf8'));
      verifierEtatUI(apres, avant, true);
      sauver('cleanup', { conforme: true, ...bilan, profils: projectionEtatUI(apres) });
    } finally { sauver('diagnostic-cleanup', diagnostic.resultat()); }
    return;
  }
  let browser, preview; const preuves = []; let succes = false;
  try {
    const [gardes] = await lireSQL(sqlGardeUI, env); verifierGardeUI(gardes);
    const avant = await lireSQL(sqlEtatUI(membres), env); verifierEtatUI(avant); sauver('avant', projectionEtatUI(avant));
    diagnostic.phase('preview');
    // Seul le build éphémère de recette utilise la police système de secours.
    const index = resolve('dist/index.html');
    writeFileSync(index, preparerHtmlPreview(readFileSync(index, 'utf8')));
    const { webkit, devices, expect } = await import('@playwright/test');
    preview = await demarrerPreview({ env, observer: etat => sauver('preview', etat) });
    diagnostic.phase('browser');
    browser = await webkit.launch();
    for (const [slot, appareil] of ['iPhone 13','iPad Pro 11'].entries()) {
      diagnostic.phase('browser', slot);
      const membre = membres[slot], anomalies = [], lectures = [];
      // Contextes privés en mémoire : aucun storageState, trace, vidéo ou HAR.
      const contexte = await browser.newContext({ ...devices[appareil], baseURL: ORIGINE_UI, locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block' });
      try {
        await contexte.addInitScript(() => localStorage.setItem('cookie-consent', 'refused'));
        await contexte.routeWebSocket('**/*', socket => socket.close()); // Aucun parcours messagerie/realtime dans cette recette.
        await contexte.route('**/*', async route => {
          const r = route.request(); let body;
          try { body = r.postData() ? r.postDataJSON() : undefined; } catch { anomalies.push('body'); diagnostic.requete({ url: r.url(), method: r.method(), statut: 'corps-invalide' }); return route.abort(); }
          if (!requeteUIAutorisee({ url: r.url(), method: r.method(), body }, membre)) { anomalies.push('requete-refusee'); diagnostic.requete({ url: r.url(), method: r.method(), statut: 'refusee' }); return route.abort(); }
          const u = new URL(r.url());
          if (u.origin === STAGING_URL) lectures.push({ methode: r.method(), endpoint: u.pathname });
          return route.continue();
        });
        contexte.on('response', response => diagnostic.requete({ url: response.url(), method: response.request().method(), statut: response.status() }));
        contexte.on('requestfailed', request => diagnostic.requete({ url: request.url(), method: request.method(), statut: 'transport' }));
        const page = await contexte.newPage();
        page.setDefaultTimeout(20_000); page.setDefaultNavigationTimeout(25_000);
        page.on('pageerror', () => { anomalies.push('javascript'); diagnostic.javascript(); }); // Ne jamais sérialiser une exception navigateur.
        await parcourirDashboard(page, membre, { expect, marquerPhase: phase => diagnostic.phase(phase, slot),
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
    diagnostic.phase('backend', null);
    const apres = await lireSQL(sqlEtatUI(membres), env); sauver('apres', projectionEtatUI(apres)); verifierEtatUI(apres, avant);
    sauver('resultat', { mode: 'staging-reel', succes: true, preuves, diagnostic: diagnostic.resultat() }); succes = true;
  } finally {
    // Écrire avant la fermeture pour conserver la phase même si le navigateur tombe.
    if (!succes) sauver('resultat', { mode: 'staging-reel', succes: false, profils_valides: preuves.length, diagnostic: diagnostic.resultat() });
    try { await browser?.close(); } finally { preview?.kill('SIGTERM'); }
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const action = process.argv[2];
  executerRecetteDashboard({ action }).then(() => console.log(action === 'verify-preview'
    ? 'Preview locale disponible ; aucune connexion UI effectuée.'
    : action === 'verify-cleanup' ? 'Nettoyage et audits frontend confirmés.' : 'Contrôle frontend staging confirmé.'))
    .catch(() => { console.error('Contrôle frontend staging non confirmé ; détails sensibles non publiés. Consulter les preuves structurées et le cleanup.'); process.exitCode = 1; });
}

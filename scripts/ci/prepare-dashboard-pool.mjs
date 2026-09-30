import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { configurationDashboard, executerFixtureDashboard, manifesteDashboard } from './prepare-dashboard-fixture.mjs';
import { lirePoolDashboard, NOMBRE_PROFILS_DASHBOARD, runDashboardMembre } from '../../tests/load/helpers/dashboard-pool.js';

const statuts = ['not-started', 'planned', 'auth-created', 'prepared', 'cleanup-started', 'cleaned'];
export function manifestePoolDashboard(runId) {
  return { version: 2, runId, membres: Array.from({ length: NOMBRE_PROFILS_DASHBOARD }, (_, slot) =>
    ({ ...manifesteDashboard({ runId: runDashboardMembre(runId, slot) }), slot, status: 'not-started' })) };
}

export async function executerPoolDashboard({ action, env = process.env, fetchImpl = fetch,
  log = console.log, genererMotDePasse } = {}) {
  if (!['prepare', 'cleanup'].includes(action)) throw new Error('Action du pool attendue : prepare ou cleanup.');
  const c = configurationDashboard(env), attendu = manifestePoolDashboard(c.runId);
  const dossier = `${c.manifestPath}.members`;
  const chemin = slot => `${dossier}/${slot}.json`;
  const enregistrer = (m, exclusif = false) => writeFileSync(c.manifestPath, JSON.stringify(m, null, 2) + '\n',
    { mode: 0o600, ...(exclusif ? { flag: 'wx' } : {}) });
  const chargerMembre = slot => {
    const a = attendu.membres[slot];
    if (!existsSync(chemin(slot))) return { ...a };
    let fichier; try { fichier = JSON.parse(readFileSync(chemin(slot), 'utf8')); } catch { throw new Error('Manifeste membre illisible.'); }
    const { slot: _slot, status: _status, ...identite } = a;
    if (Object.keys(fichier).sort().join(',') !== [...Object.keys(identite), 'status'].sort().join(',')
      || Object.keys(identite).some(k => JSON.stringify(fichier[k]) !== JSON.stringify(identite[k]))
      || !statuts.slice(1).includes(fichier.status)) throw new Error('Manifeste membre incohérent.');
    return { ...fichier, slot };
  };
  const actualiser = statut => {
    const m = { ...attendu, status: statut, membres: attendu.membres.map((_, slot) => chargerMembre(slot)) };
    enregistrer(m); return m;
  };
  const membreEnv = slot => ({ ...env, LOAD_TEST_RUN_ID: attendu.membres[slot].runId, LOAD_DASHBOARD_MANIFEST: chemin(slot) });
  if (action === 'prepare') {
    if (!env.GITHUB_ENV || !env.STAGING_SUPABASE_ACCESS_TOKEN || !env.STAGING_SUPABASE_SERVICE_ROLE_KEY || !env.STAGING_SUPABASE_ANON_KEY) {
      throw new Error('Accès staging et canal privé GITHUB_ENV requis.');
    }
    if (existsSync(dossier)) throw new Error('Pool déjà commencé : aucune réutilisation.');
    mkdirSync(dirname(c.manifestPath), { recursive: true });
    enregistrer({ ...attendu, status: 'planned' }, true);
    mkdirSync(dossier, { mode: 0o700 });
    const identites = [];
    try {
      for (let slot = 0; slot < NOMBRE_PROFILS_DASHBOARD; slot++) {
        await executerFixtureDashboard({ action, env: membreEnv(slot), fetchImpl, log, genererMotDePasse,
          transmettreIdentite: p => identites.push({ ...p, slot }) });
        actualiser('planned');
      }
      lirePoolDashboard(JSON.stringify(identites), c.runId);
      appendFileSync(env.GITHUB_ENV, `LOAD_DASHBOARD_POOL_JSON=${JSON.stringify(identites)}\n`, { mode: 0o600 });
      actualiser('prepared');
    } catch (error) {
      actualiser('partial');
      throw error;
    }
    log('Pool E préparé : dix profils AS minimaux distincts, sans qualification vérifiée.');
    return { identites: identites.length, profession: 'AS' };
  }

  if (!existsSync(c.manifestPath)) {
    if (existsSync(dossier)) throw new Error('Manifeste global absent : conserver les membres pour contrôle.');
    log('Aucun manifeste de pool : aucune suppression.'); return { skipped: true };
  }
  let fichier; try { fichier = JSON.parse(readFileSync(c.manifestPath, 'utf8')); } catch { throw new Error('Manifeste de pool illisible.'); }
  if (Object.keys(fichier).sort().join(',') !== 'membres,runId,status,version'
    || fichier.version !== attendu.version || fichier.runId !== c.runId
    || !['planned', 'partial', 'prepared', 'cleanup-started', 'cleaned'].includes(fichier.status)
    || !Array.isArray(fichier.membres) || fichier.membres.length !== NOMBRE_PROFILS_DASHBOARD
    || fichier.membres.some((m, slot) => Object.keys(m).sort().join(',') !== Object.keys(attendu.membres[slot]).sort().join(',')
      || !statuts.includes(m.status) || Object.keys(attendu.membres[slot]).some(k => k !== 'status' && JSON.stringify(m[k]) !== JSON.stringify(attendu.membres[slot][k])))) {
    throw new Error('Manifeste de pool incohérent : aucune suppression.');
  }
  if (existsSync(dossier) && readdirSync(dossier).some(n => !/^[0-9]\.json$/.test(n))) throw new Error('Membre de pool inattendu.');
  // Tout le manifeste est vérifié avant la première suppression, même un membre
  // tardif. Un fichier absent après une préparation attestée ne vaut pas zéro.
  const membres = attendu.membres.map((_, slot) => chargerMembre(slot));
  if (membres.some((m, slot) => m.status === 'not-started' && fichier.membres[slot].status !== 'not-started')) {
    throw new Error('Manifeste membre manquant : aucune suppression.');
  }
  const echecs = [];
  actualiser('cleanup-started');
  for (let slot = 0; slot < NOMBRE_PROFILS_DASHBOARD; slot++) {
    if (membres[slot].status === 'not-started') continue; // Aucun POST n'a précédé le manifeste membre.
    try { await executerFixtureDashboard({ action, env: membreEnv(slot), fetchImpl, log }); }
    catch (error) { echecs.push({ slot, message: error.message }); }
  }
  const fin = actualiser(echecs.length ? 'partial' : 'cleaned');
  if (echecs.length) throw new Error(`Nettoyage du pool incomplet (${echecs.map(e => `${e.slot}: ${e.message}`).join(' ; ')}).`);
  log('Pool E nettoyé : tous les membres commencés ont confirmé zéro compte, profil et préférence.');
  return { membres_nettoyes: fin.membres.filter(m => m.status === 'cleaned').length,
    membres_non_commences: fin.membres.filter(m => m.status === 'not-started').length };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { await executerPoolDashboard({ action: process.argv[2] }); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}

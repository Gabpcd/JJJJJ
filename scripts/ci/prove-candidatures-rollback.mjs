import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { catalogueD, sqlCatalogueD, STAGING_REF, STAGING_URL, validerCatalogueD } from './candidatures-fixture-contract.mjs';
import { sqlRecetteRollbackD } from './generate-candidatures-rollback.mjs';

class RefusD2 extends Error {
  constructor(code) { super(code); this.code = code; }
}
const refuser = code => { throw new RefusD2(code); };
const resultatPath = 'tests/load/results/d2-sql-rollback.json';

export function configurationPreuveD2(env, now = Date.now()) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || env.GITHUB_REPOSITORY !== 'Gabpcd/JJJJJ') refuser('CONTEXTE_MANUEL_REQUIS');
  if (env.LOAD_D_SQL_ONLY !== 'true' || env.LOAD_TEST_SCENARIO !== '04-candidatures-simultanees'
    || env.DASHBOARD_FIXTURE_ONLY !== 'false' || env.DIAGNOSTIC_SQL !== 'false'
    || env.LOAD_TEST_VUS || env.LOAD_TEST_DURATION || env.LOAD_FIXTURE_COUNT) refuser('MODE_SQL_D2_EXCLUSIF_REQUIS');
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING_REF || env.STAGING_SUPABASE_URL !== STAGING_URL) refuser('DESTINATION_STAGING_EXACTE_REQUISE');
  if (env.STAGING_SUPABASE_SERVICE_ROLE_KEY || env.STAGING_SUPABASE_ANON_KEY
    || env.LOAD_CANDIDATURES_JSON || env.LOAD_D_EXECUTION_APPROUVEE) refuser('ACCES_AUTH_INTERDIT_EN_MODE_SQL');
  if (!/^[1-9][0-9]{0,19}$/.test(env.GITHUB_RUN_ID || '')
    || !/^[1-9][0-9]{0,5}$/.test(env.GITHUB_RUN_ATTEMPT || '')
    || !/^[a-f0-9]{40}$/.test(env.GITHUB_SHA || '')) refuser('RUN_ET_SHA_EXPLICITES_REQUIS');
  const jour = env.LOAD_D_SQL_JOUR;
  const debut = /^\d{4}-\d{2}-\d{2}$/.test(jour || '') ? Date.parse(`${jour}T09:00:00Z`) : NaN;
  if (!Number.isFinite(now) || !Number.isFinite(debut) || new Date(debut).toISOString().slice(0, 10) !== jour
    || debut <= now + 86_400_000 || debut > now + 31 * 86_400_000) refuser('JOUR_FUTUR_ENTRE_UN_ET_31_JOURS_REQUIS');
  return { suffixe: `ci-${env.GITHUB_RUN_ID}-${env.GITHUB_RUN_ATTEMPT}`, jour, sha: env.GITHUB_SHA };
}

export async function prouverD2({ env = process.env, fetchImpl = fetch, now = Date.now() } = {}) {
  const c = configurationPreuveD2(env, now);
  if (!env.STAGING_SUPABASE_ACCESS_TOKEN) refuser('ACCES_MANAGEMENT_REQUIS');
  // Deux POST SQL seulement. Aucun client Auth, aucune lecture de clés,
  // aucune migration et aucun retry de la transaction, même après timeout.
  const query = async (sql, phase) => {
    let response;
    try {
      response = await fetchImpl(`https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(35_000),
        headers: { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: sql }),
      });
    } catch { refuser(`${phase}_REPONSE_AMBIGUE_SANS_REESSAI`); }
    if (!response.ok) refuser(`${phase}_HTTP_REFUSE`);
    try { return await response.json(); }
    catch { refuser(`${phase}_JSON_INVALIDE`); }
  };
  const catalogue = await query(sqlCatalogueD, 'CATALOGUE');
  if (!Array.isArray(catalogue) || catalogue.length !== 1) refuser('CATALOGUE_INCOMPLET');
  try { validerCatalogueD(catalogue[0]); }
  catch { refuser('CATALOGUE_DIVERGENT'); }
  // Le générateur répète les gardes catalogue/cron sous verrou SQL, avant
  // ses écritures. Le texte envoyé reste exactement celui du générateur.
  const sql = sqlRecetteRollbackD(c.suffixe, c.jour);
  const resultat = await query(sql, 'ROLLBACK');
  if (!Array.isArray(resultat) || resultat.length !== 1 || !resultat[0]
    || Object.keys(resultat[0]).sort().join(',') !== 'annule,preuve'
    || resultat[0].preuve !== 'D2_SQL_ROLLBACK' || resultat[0].annule !== true) refuser('SENTINELLE_ROLLBACK_ABSENTE');
  return {
    version: 1, mode: 'D2_SQL_ROLLBACK', status: 'success', sha: c.sha,
    runId: `sql-d2-${c.suffixe}`, jour: c.jour, projectRef: STAGING_REF,
    catalogue: { ...catalogueD, crons_actifs: 0, audit_fk: 0 },
    sqlSha256: createHash('sha256').update(sql).digest('hex'),
    preuve: 'D2_SQL_ROLLBACK', annule: true,
    authHttp: false, k6: false, frontendReel: false,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let resultat;
  try {
    if (process.argv[2] === 'check') {
      configurationPreuveD2(process.env);
      console.log('Paramètres SQL D2 acceptés ; aucun accès distant effectué.');
    } else if (process.argv[2] === 'run') {
      resultat = await prouverD2();
      console.log('D2 SQL : sentinelle et annulation confirmées ; aucune preuve Auth HTTP ou frontend.');
    } else refuser('ACTION_SQL_D2_INCONNUE');
  } catch (error) {
    const code = error instanceof RefusD2 ? error.code : 'ERREUR_LOCALE_SQL_D2';
    resultat = { version: 1, mode: 'D2_SQL_ROLLBACK', status: 'failed', code };
    console.error(`Preuve SQL D2 refusée : ${code}.`);
    process.exitCode = 1;
  }
  if (resultat) {
    mkdirSync(dirname(resultatPath), { recursive: true });
    writeFileSync(resultatPath, JSON.stringify(resultat, null, 2) + '\n', { mode: 0o600 });
  }
}

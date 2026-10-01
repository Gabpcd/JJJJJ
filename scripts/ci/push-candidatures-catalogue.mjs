import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

const compteurs = ['auth_users', 'soignants', 'etablissements', 'membres', 'types_comptes', 'missions', 'creneaux', 'candidatures', 'notifications', 'preferences', 'preferences_evenements', 'swipes', 'sauvegardes', 'badges', 'streaks', 'audits', 'conformite', 'suivi', 'scoring', 'emails', 'externalisations', 'push_tokens', 'net_requests', 'cron_actifs'].sort();

export async function controlerCataloguePushCandidatures(phase, { env=process.env, fetcher=fetch,
  read=readFileSync, write=writeFileSync }={}) {
  if (!['avant','apres'].includes(phase) || env.STAGING_SUPABASE_PROJECT_REF !== 'mejpriaetwgtcstbgfid'
    || !env.STAGING_SUPABASE_ACCESS_TOKEN || !env.RUNNER_TEMP) throw new Error('PUSH_CATALOGUE_CONTEXTE_REFUSE');
  const source=read('tests/fixtures/push-candidatures/catalogue.sql','utf8');
  const response=await fetcher('https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query', {
    method:'POST', redirect:'error', signal:AbortSignal.timeout(30000),
    headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},
    body:JSON.stringify({query:source}),
  });
  if (!response.ok) throw new Error(`PUSH_CATALOGUE_HTTP_${response.status}`);
  let rows;
  try { rows=await response.json(); } catch { throw new Error('PUSH_CATALOGUE_JSON_REFUSE'); }
  const row=Array.isArray(rows) && rows.length===1 ? rows[0] : null;
  if (!row || row.residus!==0 || row.compteurs?.net_requests!==0 || row.compteurs?.cron_actifs!==0
    || !isDeepStrictEqual(Object.keys(row).sort(), ['compteurs','contraintes_md5','externalisations_md5','indexes_md5','inventaire_md5','parametre_md5','residus','routines_md5','triggers_md5'])
    || !['routines_md5','triggers_md5','inventaire_md5','contraintes_md5','externalisations_md5','indexes_md5','parametre_md5'].every(k=>/^[a-f0-9]{32}$/.test(row[k]))
    || !isDeepStrictEqual(Object.keys(row.compteurs).sort(),compteurs)
    || !Object.values(row.compteurs).every(n=>Number.isSafeInteger(n) && n>=0)) throw new Error('PUSH_CATALOGUE_ETAT_REFUSE');
  const file=join(env.RUNNER_TEMP,'push-candidatures-catalogue-avant.json');
  if (phase==='avant') write(file,JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  else {
    if (!isDeepStrictEqual(JSON.parse(read(file,'utf8')),rows)) throw new Error('PUSH_CATALOGUE_MODIFIE');
    write(join(env.RUNNER_TEMP,'push-candidatures-catalogue-apres.json'),JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  }
  return `PUSH_CATALOGUE_${phase.toUpperCase()}_OK : 24 compteurs, corps/droits/triggers/inventaire/indexes/contraintes/paramètre et lignes complètes de la file identiques, zéro résidu.`;
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try { console.log(await controlerCataloguePushCandidatures(process.argv[2])); }
  catch(error) { console.error(error.message?.startsWith('PUSH_CATALOGUE_')?error.message:'PUSH_CATALOGUE_TRANSPORT_OU_PREUVE_REFUSE'); process.exitCode=1; }
}

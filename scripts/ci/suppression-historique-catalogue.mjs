import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

const compteurs = ['auth_users','soignants','etablissements','missions','creneaux','presences',
  'paiements','transferts','honoraires','commissions','audits_pieces','audits','recus','preferences',
  'notifications','emails','externalisations','refunds','cessions','escrow','escrow_release',
  'scoring','rate_limits','net_requests'].sort();

export async function controlerCatalogueSuppression(phase, { env=process.env, fetcher=fetch,
  read=readFileSync, write=writeFileSync }={}) {
  if (!['avant','apres'].includes(phase) || env.STAGING_SUPABASE_PROJECT_REF !== 'mejpriaetwgtcstbgfid'
    || !env.STAGING_SUPABASE_ACCESS_TOKEN || !env.RUNNER_TEMP) throw new Error('SUPPRESSION_CATALOGUE_CONTEXTE_REFUSE');
  const source=read('tests/fixtures/suppression-historique-financier/catalogue.sql','utf8');
  const response=await fetcher('https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query', {
    method:'POST', redirect:'error', signal:AbortSignal.timeout(30000),
    headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},
    body:JSON.stringify({query:source}),
  });
  if (!response.ok) throw new Error(`SUPPRESSION_CATALOGUE_HTTP_${response.status}`);
  let rows;
  try { rows=await response.json(); } catch { throw new Error('SUPPRESSION_CATALOGUE_JSON_REFUSE'); }
  const row=Array.isArray(rows) && rows.length===1 ? rows[0] : null;
  if (!row || row.residus!==0 || row.compteurs?.net_requests!==0
    || !['routines_md5','triggers_md5','inventaire_md5'].every(k=>/^[a-f0-9]{32}$/.test(row[k]))
    || !isDeepStrictEqual(Object.keys(row.compteurs).sort(),compteurs)
    || !Object.values(row.compteurs).every(n=>Number.isSafeInteger(n) && n>=0)) throw new Error('SUPPRESSION_CATALOGUE_ETAT_REFUSE');
  const file=join(env.RUNNER_TEMP,'suppression-historique-catalogue-avant.json');
  if (phase==='avant') write(file,JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  else {
    if (!isDeepStrictEqual(JSON.parse(read(file,'utf8')),rows)) throw new Error('SUPPRESSION_CATALOGUE_MODIFIE');
    write(join(env.RUNNER_TEMP,'suppression-historique-catalogue-apres.json'),JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  }
  return `SUPPRESSION_CATALOGUE_${phase.toUpperCase()}_OK : 24 compteurs, corps/droits/triggers/inventaire identiques, zéro résidu.`;
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try { console.log(await controlerCatalogueSuppression(process.argv[2])); }
  catch(error) { console.error(error.message?.startsWith('SUPPRESSION_CATALOGUE_')?error.message:'SUPPRESSION_CATALOGUE_TRANSPORT_OU_PREUVE_REFUSE'); process.exitCode=1; }
}

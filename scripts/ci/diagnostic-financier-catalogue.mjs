import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

const compteurs = ['litiges','equipe_admin','auth_users','soignants','etablissements','missions','creneaux','presences',
  'paiements','transferts','honoraires','commissions','audits_pieces','audits','recus','preferences',
  'notifications','emails','externalisations','refunds','cessions','escrow','escrow_release',
  'scoring','rate_limits','net_requests'].sort();

export async function controlerCatalogueDiagnostic(phase, { env=process.env, fetcher=fetch,
  read=readFileSync, write=writeFileSync }={}) {
  if (!['avant','apres'].includes(phase) || env.STAGING_SUPABASE_PROJECT_REF !== 'mejpriaetwgtcstbgfid'
    || !env.STAGING_SUPABASE_ACCESS_TOKEN || !env.RUNNER_TEMP) throw new Error('DIAGNOSTIC_CATALOGUE_CONTEXTE_REFUSE');
  const source=read('tests/fixtures/diagnostic-financier/catalogue.sql','utf8');
  const response=await fetcher('https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query', {
    method:'POST', redirect:'error', signal:AbortSignal.timeout(30000),
    headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},
    body:JSON.stringify({query:source}),
  });
  if (!response.ok) throw new Error(`DIAGNOSTIC_CATALOGUE_HTTP_${response.status}`);
  let rows;
  try { rows=await response.json(); } catch { throw new Error('DIAGNOSTIC_CATALOGUE_JSON_REFUSE'); }
  const row=Array.isArray(rows) && rows.length===1 ? rows[0] : null;
  if (!row || row.residus!==0 || row.compteurs?.net_requests!==0
    || !['routines_md5','triggers_md5','inventaire_md5'].every(k=>/^[a-f0-9]{32}$/.test(row[k]))
    || !isDeepStrictEqual(Object.keys(row.compteurs).sort(),compteurs)
    || !Object.values(row.compteurs).every(n=>Number.isSafeInteger(n) && n>=0)) throw new Error('DIAGNOSTIC_CATALOGUE_ETAT_REFUSE');
  const file=join(env.RUNNER_TEMP,'diagnostic-financier-catalogue-avant.json');
  if (phase==='avant') write(file,JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  else {
    if (!isDeepStrictEqual(JSON.parse(read(file,'utf8')),rows)) throw new Error('DIAGNOSTIC_CATALOGUE_MODIFIE');
    write(join(env.RUNNER_TEMP,'diagnostic-financier-catalogue-apres.json'),JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  }
  return `DIAGNOSTIC_CATALOGUE_${phase.toUpperCase()}_OK : 26 compteurs, corps/droits/triggers/inventaire identiques, zéro résidu.`;
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try { console.log(await controlerCatalogueDiagnostic(process.argv[2])); }
  catch(error) { console.error(error.message?.startsWith('DIAGNOSTIC_CATALOGUE_')?error.message:'DIAGNOSTIC_CATALOGUE_TRANSPORT_OU_PREUVE_REFUSE'); process.exitCode=1; }
}

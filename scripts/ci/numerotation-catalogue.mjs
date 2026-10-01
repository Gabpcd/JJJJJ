import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

const compteurKeys='auth_users soignants etablissements missions presences creneaux equipes litiges honoraires commissions audit_factures audits notifications preferences conformite suivi emails externalisations escrow refunds cessions scoring escrow_release stripe_transfers paiements_soignant claims archives net_requests baux'.split(' ');
const rowKeys=['residus','compteurs','routines_md5','triggers_md5','inventaire_md5','baux_schema_md5'];
export async function controlerCatalogueNumerotation(phase, {env=process.env, fetcher=fetch, read=readFileSync, write=writeFileSync}={}) {
  if (!['avant','apres'].includes(phase) || env.STAGING_SUPABASE_PROJECT_REF !== 'mejpriaetwgtcstbgfid'
    || !env.STAGING_SUPABASE_ACCESS_TOKEN || !env.RUNNER_TEMP) throw new Error('NUMEROTATION_CATALOGUE_CONTEXTE_REFUSE');
  const source=read('tests/fixtures/numerotation-catalogue.sql','utf8');
  const response=await fetcher('https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query', {
    method:'POST', redirect:'error', signal:AbortSignal.timeout(30000),
    headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`,'Content-Type':'application/json'},
    body:JSON.stringify({query:source}),
  });
  if (!response.ok) throw new Error(`NUMEROTATION_CATALOGUE_HTTP_${response.status}`);
  let rows;
  try { rows=await response.json(); } catch { throw new Error('NUMEROTATION_CATALOGUE_JSON_REFUSE'); }
  if (!Array.isArray(rows) || rows.length!==1 || rows[0].residus!==0 || rows[0].compteurs?.net_requests!==0
    || !['routines_md5','triggers_md5','inventaire_md5','baux_schema_md5'].every(k=>/^[a-f0-9]{32}$/.test(rows[0][k]))
    || !isDeepStrictEqual(Object.keys(rows[0]).sort(),rowKeys.toSorted())
    || !isDeepStrictEqual(Object.keys(rows[0].compteurs).sort(),compteurKeys.toSorted())
    || !Object.values(rows[0].compteurs).every(n=>Number.isSafeInteger(n) && n>=0)) throw new Error('NUMEROTATION_CATALOGUE_ETAT_REFUSE');
  const file=join(env.RUNNER_TEMP,'numerotation-catalogue-avant.json');
  if (phase==='avant') write(file,JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  else {
    if (!isDeepStrictEqual(JSON.parse(read(file,'utf8')),rows)) throw new Error('NUMEROTATION_CATALOGUE_MODIFIE');
    write(join(env.RUNNER_TEMP,'numerotation-catalogue-apres.json'),JSON.stringify(rows)+'\n',{mode:0o600,flag:'wx'});
  }
  return `NUMEROTATION_CATALOGUE_${phase.toUpperCase()}_OK : 29 compteurs, corps/droits/triggers/inventaire et zéro résidu.`;
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try { console.log(await controlerCatalogueNumerotation(process.argv[2])); }
  catch(error) { console.error(error.message?.startsWith('NUMEROTATION_')?error.message:'NUMEROTATION_CATALOGUE_TRANSPORT_OU_PREUVE_REFUSE'); process.exitCode=1; }
}

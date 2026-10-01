import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const SOURCE = 'tests/security/facturation-heures-ajustees-chainage-f1.test.sql';
export const CATALOGUE = 'tests/fixtures/facturation-heures-ajustees-f1/catalogue.sql';
export const HASH_SOURCE = '66beb3a107d9151d7a1fdd16183370e5cd1daef1bd56aa4c3786a3f3b22039d4';
export const HASH_CATALOGUE = 'ea0c60bbfa4117d2ca5bd0e92dc9b765b90d191212e9cb6eb0b065765f9cb687';
const STAGING = 'mejpriaetwgtcstbgfid';
const PREFIXE = 'F1_HEURES_CHAINE_COMMISSION_INCOHERENTE attendu suivante=12/2.40/14.40 cumul=140/21 ; observe=';
const COMPTEURS = ['auth_users','soignants','etablissements','missions','presences','creneaux','equipes','litiges','honoraires','commissions','audit_factures','audits','notifications','preferences','conformite','suivi','emails','externalisations','escrow','refunds','cessions','scoring','escrow_release','stripe_transfers','net_requests'].sort();
const finance = (ht, tva, ttc) => ({ net:160, brut:160, commission_ht:ht, commission_tva:tva, commission_ttc:ttc });
export const ATTENDUS = Object.freeze([
  { cas:'intermediaire', apres_correction:finance(21,4.2,25.2), apres_cloture:null,
    commission_suivante_ht:10.5, commission_suivante_tva:2.1, commission_suivante_ttc:12.6,
    cumul_honoraires_ht:140, cumul_commissions_ht:19.5 },
  { cas:'finale', apres_correction:finance(21,4.2,25.2), apres_cloture:finance(24,4.8,28.8),
    commission_suivante_ht:15, commission_suivante_tva:3, commission_suivante_ttc:18,
    cumul_honoraires_ht:140, cumul_commissions_ht:24 },
]);
const canonical = x => Array.isArray(x) ? x.map(canonical) : x && typeof x === 'object'
  ? Object.fromEntries(Object.keys(x).sort().map(k => [k,canonical(x[k])])) : x;
const equal = (a,b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const hash = x => createHash('sha256').update(x).digest('hex');
const check = (ok,code) => { if (!ok) throw new Error(code); };

export function verifierCatalogue(rows) {
  const c = rows?.[0];
  check(Array.isArray(rows) && rows.length === 1 && c
    && equal(Object.keys(c).sort(), ['compteurs','helper_remplacement_md5','residus','routines_md5','triggers_md5'])
    && c.helper_remplacement_md5 === 'c793ac81eaef0fe18fb5920c9264c675'
    && /^[a-f0-9]{32}$/.test(c.routines_md5) && /^[a-f0-9]{32}$/.test(c.triggers_md5)
    && c.residus === 0 && c.compteurs && equal(Object.keys(c.compteurs).sort(),COMPTEURS)
    && Object.values(c.compteurs).every(n => Number.isSafeInteger(n) && n >= 0)
    && c.compteurs.net_requests === 0, 'F1_TEMOIN_CATALOGUE_REFUSE');
  return rows;
}

export function verifierRouge(http, body) {
  check(http === 400 && body && typeof body.message === 'string'
    && (body.code === undefined || body.code === 'P0001'), 'F1_TEMOIN_ERREUR_INATTENDUE');
  // Format Management API constaté sur les rouges F1 précédents. Ni timeout,
  // ni préflight, ni une autre erreur P0001 ne constitue la reproduction.
  const match = /^Failed to run sql query: ERROR: {1,2}P0001: ([^\n]+)\nCONTEXT: {1,2}PL\/pgSQL function inline_code_block line [1-9][0-9]* at RAISE\n?$/.exec(body.message);
  check(match && match[1].startsWith(PREFIXE), 'F1_TEMOIN_ERREUR_INATTENDUE');
  const raw = match[1].slice(PREFIXE.length);
  let diagnostics;
  try { diagnostics = JSON.parse(raw); } catch { throw new Error('F1_TEMOIN_DIAGNOSTIC_INVALIDE'); }
  // Le JSON provient de jsonb PostgreSQL : rejeter aussi les clés dupliquées
  // plutôt que laisser JSON.parse remplacer silencieusement une valeur.
  const keys = s => [...s.matchAll(/"([a-z_]+)"\s*:/g)].map(x => x[1]).sort();
  check(equal(diagnostics,ATTENDUS) && equal(keys(raw),keys(JSON.stringify(ATTENDUS))), 'F1_TEMOIN_DIAGNOSTIC_INATTENDU');
  return diagnostics;
}

export async function executerTemoin({ env = process.env, fetcher = fetch, lire = readFile, ecrire = writeFile } = {}) {
  check(env.STAGING_SUPABASE_PROJECT_REF === STAGING && typeof env.STAGING_SUPABASE_ACCESS_TOKEN === 'string'
    && env.STAGING_SUPABASE_ACCESS_TOKEN.length > 0 && env.RUNNER_TEMP, 'F1_TEMOIN_ENV_REFUSE');
  const [sql, catalogue, avantRaw] = await Promise.all([
    lire(SOURCE,'utf8'), lire(CATALOGUE,'utf8'), lire(join(env.RUNNER_TEMP,'f1-catalogue-avant.json'),'utf8'),
  ]);
  check(hash(sql) === HASH_SOURCE && hash(catalogue) === HASH_CATALOGUE, 'F1_TEMOIN_SOURCE_MODIFIEE');
  const avant = verifierCatalogue(JSON.parse(avantRaw));
  const query = async (sql, readOnly) => {
    const response = await fetcher(`https://api.supabase.com/v1/projects/${STAGING}/database/query`, {
      method:'POST', redirect:'error', signal:AbortSignal.timeout(readOnly ? 30000 : 60000),
      headers:{ Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type':'application/json' },
      body:JSON.stringify({ query:sql, read_only:readOnly }),
    });
    check(!response.redirected, 'F1_TEMOIN_REDIRECTION');
    const raw = await response.text();
    check(raw.length <= 65536, 'F1_TEMOIN_REPONSE_TROP_GRANDE');
    let body;
    try { body = JSON.parse(raw); } catch { throw new Error('F1_TEMOIN_REPONSE_INVALIDE'); }
    return { status:response.status, body, hash:hash(raw) };
  };
  let erreur, preuve;
  try {
    const response = await query(sql,false);
    const diagnostics = verifierRouge(response.status,response.body);
    preuve = { statut:'ROUGE_ATTENDU_PROUVE', sqlstateExterne:'P0001', sentinelleInterne:'JF141',
      sourceSha256:HASH_SOURCE, catalogueSha256:HASH_CATALOGUE, reponseSha256:response.hash, diagnostics };
  } catch { erreur = new Error('F1_TEMOIN_ROUGE_NON_PROUVE'); }
  // Même après réponse perdue/erreur : nouvelle requête READ ONLY, aucun retry
  // de la fixture. L'application des migrations est impossible sans ce contrôle.
  const apres = await query(catalogue,true);
  check(apres.status >= 200 && apres.status < 300, 'F1_TEMOIN_CONTROLE_INDEPENDANT_REFUSE');
  verifierCatalogue(apres.body);
  check(equal(avant,apres.body), 'F1_TEMOIN_CATALOGUE_OU_COMPTEURS_MODIFIES');
  if (erreur) throw erreur;
  preuve.catalogueAvantApresSha256 = hash(JSON.stringify(canonical(avant)));
  preuve.compteursVerifies = 25;
  await ecrire(join(env.RUNNER_TEMP,'f1-heures-temoin-rouge.json'),JSON.stringify(preuve,null,2)+'\n',{mode:0o600});
  return preuve;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  executerTemoin().then(p => console.log(JSON.stringify(p))).catch(() => {
    // Ne jamais imprimer un corps fournisseur inconnu ou une valeur de secret.
    console.error('F1_TEMOIN_REFUSE : reproduction exacte ou annulation indépendante non prouvée.');
    process.exitCode = 1;
  });
}

// Recette de draft uniquement : aucun bootstrap, session Auth ou fournisseur.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

export const STAGING_REF = 'mejpriaetwgtcstbgfid';
export const DRAFT_SHA256 = '534a2efae44ba72270868cd182efd9f1b1e8246e2f413dbe1bb1391d735b169e';
const SUITE_SHA256 = '993de56a51846556ee9084bce13fd55f4faa08504950afd57273ddbc6c472aee';
const CATALOGUE_SHA256 = '526d2c57717bdc69684f1724c2bee1c9362fc0ff7225128129a61cc49ccf180f';
const ATTENDU_SHA256 = 'dd73a31d3eb8868a9c7cb7af2f44e5160e57623acdd4ed626188b58d11c8266a';
const ENDPOINT = `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`;
const root = fileURLToPath(new URL('../../', import.meta.url));
const sha = text => createHash('sha256').update(text).digest('hex');
class Refus extends Error { constructor(code) { super(code); this.code = code; } }
const refuser = code => { throw new Refus(code); };

export function contexte(env) {
  if (env.STAGING_SUPABASE_PROJECT_REF !== STAGING_REF) refuser('destination_refusee');
  if (typeof env.STAGING_SUPABASE_ACCESS_TOKEN !== 'string' || !env.STAGING_SUPABASE_ACCESS_TOKEN.trim()) refuser('acces_absent');
  if (env.GITHUB_EVENT_NAME !== 'pull_request'
    || !/^[a-f0-9]{40}$/.test(env.BASE_SHA || '') || !/^[a-f0-9]{40}$/.test(env.GITHUB_SHA || '')
    || !/^\d{1,20}$/.test(env.GITHUB_RUN_ID || '') || !/^[1-9]\d{0,3}$/.test(env.GITHUB_RUN_ATTEMPT || '')) refuser('contexte_ci_refuse');
  return { run: env.GITHUB_RUN_ID, tentative: Number(env.GITHUB_RUN_ATTEMPT), sha: env.GITHUB_SHA, base: env.BASE_SHA, projet: STAGING_REF };
}

export function chargerEntrees() {
  const fixture = resolve(root, 'tests/fixtures/contrat-service-v11');
  return {
    draft: readFileSync(resolve(fixture, 'draft.sql'), 'utf8'),
    suite: readFileSync(resolve(root, 'tests/security/contrat-service-v11.test.sql'), 'utf8'),
    catalogueSql: readFileSync(resolve(fixture, 'catalogue.sql'), 'utf8'),
    attendu: JSON.parse(readFileSync(resolve(fixture, 'catalogue-attendu.json'), 'utf8')),
  };
}

export function assembler({ draft, suite, catalogueSql, attendu }) {
  if (sha(draft) !== DRAFT_SHA256) refuser('draft_altere');
  if (sha(suite) !== SUITE_SHA256) refuser('suite_alteree');
  if (sha(catalogueSql) !== CATALOGUE_SHA256 || sha(JSON.stringify(attendu)) !== ATTENDU_SHA256) refuser('catalogue_altere');
  // Le fichier de test est une transaction autonome. Seuls ses deux délimiteurs
  // sont retirés ; un autre COMMIT/ROLLBACK/commande psql fait refuser le lot.
  if (!/^BEGIN;$/m.test(suite) || !/\nROLLBACK;\s*$/.test(suite)) refuser('transaction_suite_invalide');
  const corps = suite.replace(/^BEGIN;\s*$/m, '').replace(/\nROLLBACK;\s*$/, '\n');
  if (/^[ \t]*(?:BEGIN|COMMIT|ROLLBACK)[ \t]*;[ \t]*$|^[ \t]*\\/im.test(corps)) refuser('transaction_suite_invalide');
  if (!catalogueSql.startsWith('WITH ') || /;\s*\S/.test(catalogueSql)) refuser('catalogue_invalide');
  const literal = JSON.stringify(attendu).replaceAll("'", "''");
  const garde = `DO $catalogue_v11$ DECLARE v_catalogue_v11 jsonb; BEGIN
SELECT to_jsonb(c) INTO v_catalogue_v11 FROM (${catalogueSql.trim().replace(/;$/, '')}) c;
IF v_catalogue_v11 IS DISTINCT FROM '${literal}'::jsonb THEN
  RAISE EXCEPTION 'Contrat v11 : catalogue ou residus divergents';
END IF; END $catalogue_v11$;`;
  return `BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='10s';
${garde}
SAVEPOINT contrat_v11_draft;
${draft}
${corps}
ROLLBACK TO SAVEPOINT contrat_v11_draft;
${garde}
RELEASE SAVEPOINT contrat_v11_draft;
SELECT 'CONTRAT_V11_SQL_ROLLBACK' AS preuve,true AS annule;
ROLLBACK;
`;
}

function catalogueValide(rows, attendu) {
  if (!Array.isArray(rows) || rows.length !== 1 || !isDeepStrictEqual(rows[0], attendu)) refuser('catalogue_divergent');
}
function sentinelleValide(rows) {
  if (!isDeepStrictEqual(rows, [{ preuve: 'CONTRAT_V11_SQL_ROLLBACK', annule: true }])) refuser('sentinelle_invalide');
}

export async function executerPreuve(env, { fetchImpl = fetch, entrees = chargerEntrees(), conserver = () => {} } = {}) {
  // La destination et les entrées locales sont validées avant tout transport.
  const execution = contexte(env);
  const sql = assembler(entrees);
  const rapport = { ...execution, draft_sha256: sha(entrees.draft), suite_sha256: sha(entrees.suite),
    catalogue_sha256: sha(entrees.catalogueSql), attendu_sha256: sha(JSON.stringify(entrees.attendu)), phase: 'preflight', succes: false,
    transaction_tentee: false, sentinelle: false, controle_independant: false, erreur_transaction: null, erreur_controle: null, erreur: null };
  async function requete(query, timeout) {
    let response;
    try {
      response = await fetchImpl(ENDPOINT, { method: 'POST', redirect: 'error',
        headers: { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }), signal: AbortSignal.timeout(timeout) });
    } catch { refuser('transport_refuse'); }
    if (!response.ok) refuser('reponse_http_refusee');
    try { return await response.json(); } catch { refuser('reponse_json_invalide'); }
  }
  try {
    catalogueValide(await requete(entrees.catalogueSql, 35000), entrees.attendu);
    rapport.phase = 'transaction';
    rapport.transaction_tentee = true;
    try {
      sentinelleValide(await requete(sql, 155000));
      rapport.sentinelle = true;
    } catch (erreur) {
      rapport.erreur_transaction = erreur instanceof Refus ? erreur.code : 'erreur_interne';
      throw erreur;
    } finally {
      // Requête SELECT distincte même après refus/réponse perdue. Aucune reprise
      // de la transaction, suppression compensatoire ou appel Auth Admin.
      rapport.phase = 'controle_independant';
      try {
        catalogueValide(await requete(entrees.catalogueSql, 35000), entrees.attendu);
        rapport.controle_independant = true;
      } catch (erreur) {
        rapport.erreur_controle = erreur instanceof Refus ? erreur.code : 'erreur_interne';
        throw erreur;
      }
    }
    rapport.phase = 'termine';
    rapport.succes = true;
    return rapport;
  } catch (erreur) {
    rapport.erreur = erreur instanceof Refus ? erreur.code : 'erreur_interne';
    throw new Refus(rapport.erreur);
  } finally {
    // Jamais de corps fournisseur, SQL, URL, exception libre ou jeton publié.
    conserver(rapport);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const conserver = rapport => {
    const filtre = `${JSON.stringify(rapport)}\n`;
    if (process.env.RUNNER_TEMP) writeFileSync(resolve(process.env.RUNNER_TEMP, 'contrat-v11-sql-proof.json'), filtre, { mode: 0o600 });
    process.stdout.write(filtre);
  };
  try { await executerPreuve(process.env, { conserver }); }
  catch (erreur) {
    process.stderr.write(`Contrat v11 : ${erreur instanceof Refus ? erreur.code : 'erreur_interne'}.\n`);
    process.exitCode = 1;
  }
}

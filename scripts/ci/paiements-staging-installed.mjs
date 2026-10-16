// Read-only recognition of the six manually deployed PR1063 migrations.
// No bootstrap, SQL replay, repair, provider call or automatic repin.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual as same } from 'node:util';
import { catalogueSqlFixture } from './connect-test-fixture-sql.mjs';
import { readOnlySql, PROJECT } from './connect-test-fixture.mjs';

export const REVIEWED_INSTALLATION = Object.freeze({
  sourceSha: '204d352df7998f820f7f3437c5ed4c9476d625d9',
  catalogue: { routines: 'f5a1148c69cd5d79f5447829d218b3b8', triggers: '3d6ef14ab83acb02a8ca0df3bc36231d', columns: 'b715fc97721c97f9a788b8cdc45a5e09' },
  migrations: [
    ['20261016125441_aligner_relances_commission_echeance.sql', '3d3de03113eab292b81f6ae04c7e82cf932f3e6ca6b8c29c816e72ec42512c2c', 8],
    ['20261016125451_diagnostic_disponibilite_connect.sql', 'ed5f1ae477f221ebd32a5088b769fb533fd4527695e4d3dcc8e0fa009fe255d6', 7],
    ['20261016125516_securiser_beneficiaire_connect_et_versements_standard.sql', 'e53564c6a2107299e25822d91569cbc6f3b4a9f9eefe038deeb8a6611bcba810', 26],
    ['20261016125521_fiabiliser_emails_factures.sql', 'a929e9f09e3265da6e7499497952339c2992d77914bec9599bd69f4531dd4e94', 18],
    ['20261016125632_securiser_reglement_commission_separee_et_taux_groupe.sql', '7ac23bfd7885839c78d106eb3dddf82f29f45eeb287ae7a9d3454e9438880b13', 20],
    ['20261016144756_fermer_replays_payout_et_isoler_sources_facturation.sql', 'dc3fe609b61c25d64bdb171e96687b7e83cf3bd0c7bbfa64e13be9cfbcaec202', 7],
  ],
});
const requireThat = (ok, code) => { if (!ok) throw new Error(`PAIEMENTS_INSTALLED_${code}`); };
const digest = value => createHash('sha256').update(value).digest('hex');
const files = REVIEWED_INSTALLATION.migrations.map(([name]) => `supabase/migrations/${name}`);
const versions = REVIEWED_INSTALLATION.migrations.map(([name]) => name.slice(0, 14));
const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();

export function checkScope(changes, sources) {
  if (!changes.some(([, path]) => files.includes(path))) return false;
  requireThat(same(changes, files.map(path => ['A', path])), 'EXACT_SIX_REQUIRED');
  REVIEWED_INSTALLATION.migrations.forEach(([name, hash]) => {
    requireThat(typeof sources[name] === 'string' && digest(sources[name]) === hash, 'SOURCE_CHANGED');
  });
  return true;
}

// Match stored statements byte for byte in order. Only SQL delimiters and
// whitespace BETWEEN statements are consumed; function bodies are untouched.
export function statementsMatch(source, statements) {
  if (typeof source !== 'string' || !Array.isArray(statements) || !statements.length) return false;
  let rest = source;
  for (const statement of statements) {
    if (typeof statement !== 'string' || !statement.length) return false;
    rest = rest.trimStart();
    if (!rest.startsWith(statement)) return false;
    rest = rest.slice(statement.length);
    if (rest.startsWith(';')) rest = rest.slice(1);
    else if (rest.trim()) return false;
  }
  return rest.trim() === '';
}

export function inspectionSql() {
  return readOnlySql(`SELECT jsonb_build_object(
    'readOnly',current_setting('transaction_read_only')='on',
    'versions',(SELECT jsonb_agg(version ORDER BY version) FROM supabase_migrations.schema_migrations),
    'migrations',(SELECT coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name,'statements',statements) ORDER BY version),'[]'::jsonb)
      FROM supabase_migrations.schema_migrations WHERE version IN (${versions.map(v => `'${v}'`).join(',')})),
    'catalogue',c.catalogue,
    'gateClosed',(SELECT count(*)=1 AND bool_and(protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE) FROM private.stripe_connect_release_gate),
    'capacitiesClosed',NOT EXISTS(SELECT 1 FROM private.stripe_connect_test_capacities WHERE enabled OR revoked_at IS NULL)
  ) AS installation FROM (${catalogueSqlFixture().replace(/;\s*$/, '')}) c;`);
}

export function checkInstallation(rows, baseVersions, sources, requireInstalled = false) {
  requireThat(Array.isArray(rows) && rows.length === 1 && same(Object.keys(rows[0] ?? {}), ['installation']), 'RESPONSE_SHAPE');
  const s = rows[0].installation;
  requireThat(s?.readOnly === true && Array.isArray(s.versions) && s.versions.length > 0
    && s.versions.every(v => typeof v === 'string' && /^\d{14}$/.test(v))
    && same(s.versions, [...new Set(s.versions)].sort()) && Array.isArray(s.migrations), 'REGISTRY_SHAPE');
  const present = versions.filter(v => s.versions.includes(v));
  if (present.length === 0) {
    requireThat(!requireInstalled && s.migrations.length === 0, 'INSTALLATION_DISAPPEARED');
    return 'empty'; // The existing main-only bootstrap still checks all versions.
  }
  requireThat(present.length === 6 && s.migrations.length === 6, 'PARTIAL_INSTALLATION');
  requireThat(baseVersions.length > 0 && baseVersions.every(v => /^\d{14}$/.test(v))
    && new Set(baseVersions).size === baseVersions.length && !baseVersions.some(v => versions.includes(v))
    && same(s.versions, [...baseVersions, ...versions].sort()), 'REGISTRY_DRIFT');
  REVIEWED_INSTALLATION.migrations.forEach(([name, hash, count], i) => {
    const row = s.migrations[i], source = sources[name];
    requireThat(typeof source === 'string' && digest(source) === hash, 'SOURCE_CHANGED');
    requireThat(row?.version === name.slice(0, 14) && row.name === name.slice(15, -4)
      && row.statements?.length === count && statementsMatch(source, row.statements), 'STATEMENTS_CHANGED');
  });
  requireThat(Object.entries(REVIEWED_INSTALLATION.catalogue).every(([k, v]) => s.catalogue?.[k] === v)
    && s.catalogue.commissionHelper === 'c736c66d76001b64ba425484f77c6ea2'
    && ['queuedRequests', 'activeCrons', 'runningCrons'].every(k => s.catalogue[k] === 0)
    && s.catalogue.generationUrlAbsent === true && s.catalogue.supportStagingExact === true
    && s.gateClosed === true && s.capacitiesClosed === true, 'CATALOGUE_OR_CHANNEL_DRIFT');
  return 'installed';
}

export function checkContext(env, head) {
  requireThat(env.GITHUB_ACTIONS === 'true' && env.GITHUB_EVENT_NAME === 'pull_request'
    && env.GITHUB_REPOSITORY === 'Gabpcd/JJJJJ' && env.PR_HEAD_REPOSITORY === 'Gabpcd/JJJJJ'
    && env.STAGING_SUPABASE_PROJECT_REF === PROJECT && /^[a-f0-9]{40}$/.test(env.BASE_SHA ?? '')
    && /^[a-f0-9]{40}$/.test(head) && env.CANDIDATE_SHA === head
    && typeof env.STAGING_SUPABASE_ACCESS_TOKEN === 'string' && env.STAGING_SUPABASE_ACCESS_TOKEN.length > 10, 'CONTEXT');
}

export async function inspect({ env, changes, sources, baseVersions, head, fetcher = fetch, requireInstalled = false }) {
  checkContext(env, head);
  const recognized = checkScope(changes, sources);
  if (!recognized) {
    requireThat(!requireInstalled, 'SCOPE_DISAPPEARED');
    return 'unrecognized';
  }
  const response = await fetcher(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(40000),
    headers: { Authorization: `Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: inspectionSql() }),
  });
  requireThat(response.ok && !response.redirected, 'READ_FAILED');
  return checkInstallation(await response.json(), baseVersions, sources, requireInstalled);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const command = process.argv[2];
    requireThat(['inspect', 'verify'].includes(command), 'COMMAND');
    const env = process.env, head = git('rev-parse', 'HEAD');
    checkContext(env, head);
    const diff = git('diff', '--name-status', '--no-renames', `${env.BASE_SHA}...HEAD`, '--', 'supabase/migrations/*.sql');
    const changes = diff ? diff.split('\n').map(line => line.split('\t')) : [];
    const sources = Object.fromEntries(REVIEWED_INSTALLATION.migrations.map(([name]) => [name, readFileSync(`supabase/migrations/${name}`, 'utf8')]));
    const baseNames = git('ls-tree', '-r', '--name-only', env.BASE_SHA, '--', 'supabase/migrations').split('\n').filter(n => n.endsWith('.sql'));
    requireThat(baseNames.every(n => /^supabase\/migrations\/\d{14}_[A-Za-z0-9_-]+\.sql$/.test(n)), 'BASE_NAMES');
    const baseVersions = baseNames.map(n => n.split('/').at(-1).slice(0, 14));
    const mode = await inspect({ env, changes, sources, baseVersions, head, requireInstalled: command === 'verify' });
    if (command === 'inspect' && env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, `mode=${mode}\n`);
    console.log(`Paiements staging : ${mode}; lecture seule, aucune migration rejouée par ce contrôle.`);
  } catch (error) {
    // Never print remote SQL text, request credentials or raw provider responses.
    console.error(`::error::${/^PAIEMENTS_INSTALLED_[A-Z_]+$/.test(error?.message ?? '') ? error.message : 'PAIEMENTS_INSTALLED_READ_OR_SOURCE_FAILED'}`);
    process.exitCode = 1;
  }
}

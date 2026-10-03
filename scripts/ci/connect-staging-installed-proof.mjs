// Existing installation only: no bootstrap, migration replay, provider or repair.
// The fresh isolated PG17 witness remains the authority for the Connect delta.
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual as same } from 'node:util';
import { PROJECT, REPOSITORY, MIGRATION, checkContract, digest, git } from './connect-staging-closed.mjs';
import { structuralJsonSql, catalogueSelect } from './connect-staging-closed-sql.mjs';
import { sourceManifest, checkReference, partitionSql } from './connect-staging-catalogue-proof.mjs';

export const VERSION = '20261001201055';
const hex = (v, n) => typeof v === 'string' && new RegExp(`^[a-f0-9]{${n}}$`).test(v);
const refuse = code => { throw new Error(`CONNECT_INSTALLED_${code}`); };
const requireThat = (condition, code) => { if (!condition) refuse(code); };
const keys = value => Object.keys(value ?? {}).sort();
const relationNames = ['private.stripe_connect_avant_transfert', 'private.stripe_connect_release_gate', 'private.stripe_connect_test_capacities'];
const countKeys = ['capacity_count', 'operation_count'];
const hashKeys = ['catalogue', 'registry', 'rows', 'all_rows', 'connect_rows', 'delta_md5', 'default_acl_md5', 'sequences_md5'];
const flagKeys = ['quiescent', 'gate_closed', 'capacity_revoked', 'operation_terminal', 'cohort_known', 'no_transfer', 'read_only'];

export function checkContext(env, source, contract, reference, versions, changes, installed = true) {
  requireThat(env.GITHUB_ACTIONS === 'true' && env.GITHUB_EVENT_NAME === 'pull_request'
    && env.GITHUB_REPOSITORY === REPOSITORY && env.STAGING_SUPABASE_PROJECT_REF === PROJECT
    && typeof env.STAGING_SUPABASE_ACCESS_TOKEN === 'string' && env.STAGING_SUPABASE_ACCESS_TOKEN.trim()
    && env.CANDIDATE_SHA === source.candidate.sha && hex(env.BASE_SHA, 40), 'CONTEXT_REFUSED');
  checkReference(reference, source);
  requireThat(Array.isArray(versions) && versions.length > 0 && !versions.includes(VERSION)
    && versions.every(v => /^\d{14}$/.test(v)) && same([...new Set(versions)].sort(), versions), 'BASE_VERSIONS_REFUSED');
  if (installed) {
    checkContract(contract);
    requireThat(same(changes, [['A', MIGRATION]]), 'MIGRATION_SCOPE_REFUSED');
    for (const field of ['migrationSha256', 'capacitySha256', 'admissionSha256'])
      requireThat(source[field] === contract.reviewedManifest[field], 'INSTALLED_SOURCE_CHANGED');
  }
}

export function presenceSql() {
  return `BEGIN READ ONLY; SET LOCAL statement_timeout='20s';
    SELECT count(*)::integer AS present FROM unnest(ARRAY[${relationNames.map(n => `'${n}'`).join(',')}]) n
    WHERE to_regclass(n) IS NOT NULL; ROLLBACK;`;
}

export function installedSql(json = false) {
  // Historical catalogue hash stays byte-identical. The extra fingerprints
  // prove preservation during this run, not identity to an unavailable old pin.
  const defaults = `(SELECT md5(COALESCE(jsonb_agg(jsonb_build_array(pg_get_userbyid(d.defaclrole),
    n.nspname,d.defaclobjtype,d.defaclacl) ORDER BY d.defaclrole,d.defaclnamespace,d.defaclobjtype)::text,'[]'))
    FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace)`;
  const allRows = `(SELECT md5(COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,
    xpath('/table/row/digest/text()',query_to_xml(format(
      'SELECT md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,''[]'')) AS digest FROM %I.%I t',
      n.nspname,c.relname),false,false,''))::text) ORDER BY n.nspname,c.relname)::text,'[]'))
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN('public','private','auth') AND c.relkind IN('r','p'))`;
  const sequences = `(SELECT md5(COALESCE(jsonb_agg(jsonb_build_array(n.nspname,c.relname,
    pg_get_userbyid(c.relowner),c.relacl,s.seqtypid,s.seqstart,s.seqincrement,s.seqmax,s.seqmin,s.seqcache,s.seqcycle,
    xpath('/table/row/digest/text()',query_to_xml(format(
      'SELECT md5(jsonb_build_array(last_value,is_called)::text) AS digest FROM %I.%I',n.nspname,c.relname),false,false,''))::text)
    ORDER BY n.nspname,c.relname)::text,'[]')) FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','auth'))`;
  const connectRows = `md5(jsonb_build_array(
    (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM private.stripe_connect_test_capacities c),
    (SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) FROM private.stripe_connect_avant_transfert o),
    (SELECT jsonb_agg(to_jsonb(g) ORDER BY g.protocol) FROM private.stripe_connect_release_gate g))::text)`;
  const select = `SELECT s.catalogue,s.registry,s.versions,s.rows,s.quiescent,${allRows} AS all_rows,
      current_user AS database_role,current_setting('transaction_read_only')='on' AS read_only,
      ${connectRows} AS connect_rows,md5((${partitionSql(structuralJsonSql, true)})::text) AS delta_md5,
      ${defaults} AS default_acl_md5,${sequences} AS sequences_md5,
      (SELECT count(*) FROM private.stripe_connect_test_capacities) AS capacity_count,
      (SELECT count(*) FROM private.stripe_connect_avant_transfert) AS operation_count,
      (SELECT count(*)=1 AND bool_and(protocol='CONNECT_PRETRANSFER_V1' AND enabled IS FALSE)
        FROM private.stripe_connect_release_gate) AS gate_closed,
      (SELECT bool_and(enabled IS FALSE AND revoked_at IS NOT NULL AND revoked_at<=clock_timestamp()
        AND livemode IS FALSE AND transfers_allowed IS FALSE AND max_checkouts=1 AND max_refunds=1
        AND checkout_reserved_at IS NOT NULL AND refund_reserved_at IS NOT NULL AND claim_reserved_at IS NOT NULL)
        FROM private.stripe_connect_test_capacities) AS capacity_revoked,
      (SELECT bool_and(orientation='REFUND' AND refund_status='SUCCEEDED' AND refund_id IS NOT NULL
        AND succeeded_at IS NOT NULL AND review_code IS NULL AND owner_token IS NULL AND lease_until IS NULL
        AND livemode IS FALSE) FROM private.stripe_connect_avant_transfert) AS operation_terminal,
      (SELECT count(*)=1 AND bool_and(private.fn_connect_test_operation_connue(o.id)
        AND private.fn_connect_test_cohorte(c.etablissement_id,c.soignant_id))
        FROM private.stripe_connect_test_capacities c JOIN private.stripe_connect_avant_transfert o ON o.id=c.operation_id) AS cohort_known,
      (SELECT count(*)=1 AND bool_and(t.stripe_transfer_id IS NULL AND t.statut='REMBOURSE'
        AND t.stripe_checkout_session_id=o.session_id)
        FROM private.stripe_connect_avant_transfert o JOIN public.stripe_transfers t ON t.id=o.trace_id) AS no_transfer
    FROM (${catalogueSelect(true)}) s`;
  return `BEGIN READ ONLY; SET LOCAL search_path=pg_catalog; SET LOCAL row_security=off; SET LOCAL statement_timeout='30s'; SET LOCAL TIME ZONE 'UTC';
    ${json ? `SELECT to_jsonb(snapshot) FROM (${select}) snapshot` : select}; ROLLBACK;`;
}

export function checkInstalled(rows, contract, reference, versions) {
  requireThat(Array.isArray(rows) && rows.length === 1 && rows[0]
    && same(keys(rows[0]), [...hashKeys, ...flagKeys, ...countKeys, 'versions', 'database_role'].sort()), 'SNAPSHOT_SHAPE');
  const s = rows[0];
  requireThat(s.database_role === 'postgres' && hashKeys.every(k => hex(s[k], 32)) && flagKeys.every(k => s[k] === true)
    && countKeys.every(k => s[k] === 1), 'CLOSED_TERMINAL_COHORT_REQUIRED');
  requireThat(s.catalogue === contract.expectedAfter.catalogue && s.registry === contract.expectedAfter.registry
    && s.delta_md5 === reference.deltaMd5 && same(s.versions, [...versions, VERSION].sort()), 'CATALOGUE_OR_REGISTRY_DRIFT');
  return s;
}

function transport(env, fetcher) {
  return async (sql, readOnly, phase) => {
    requireThat(!readOnly || (sql.startsWith('BEGIN READ ONLY;') && sql.trimEnd().endsWith('ROLLBACK;')), 'READ_ONLY_SQL_REQUIRED');
    let response, body;
    // Only fixed phase names, HTTP status, byte count and known SQLSTATE codes
    // may escape. Never emit a response body, SQL, headers or an exception text.
    try {
      response = await fetcher(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
        method:'POST', redirect:'error', signal:AbortSignal.timeout(180000),
        headers:{Authorization:`Bearer ${env.STAGING_SUPABASE_ACCESS_TOKEN}`, 'Content-Type':'application/json'},
        // As in connect-test-fixture: retain the existing operator role.
        // PostgreSQL enforces READ ONLY; the API flag would select its
        // restricted role. No ACL change, role switch or fallback is used.
        body:JSON.stringify({query:sql, read_only:false}),
      });
      body = await response.text();
    } catch { refuse(`${phase}_TRANSPORT_REFUSED`); }
    const status = Number.isInteger(response.status) && response.status >= 100 && response.status <= 599
      ? response.status : 'UNKNOWN';
    const bytes = Buffer.byteLength(body);
    const diagnostic = `${phase}_HTTP_${status}_BYTES_${bytes}`;
    requireThat(bytes < 100000, `${diagnostic}_RESPONSE_TOO_LARGE`);
    let parsed;
    try { parsed = JSON.parse(body); } catch { refuse(`${diagnostic}_INVALID_JSON`); }
    if (!response.ok) {
      const code = parsed?.code ?? parsed?.error?.code;
      const known = new Set(['42501','25006','42P01','42883','42703','57014','40001','40P01','42601','0A000','53300','08000','08006','57P01']);
      refuse(`${diagnostic}_SQLSTATE_${known.has(code) ? code : 'UNAVAILABLE'}_QUERY_REFUSED`);
    }
    return parsed;
  };
}

export async function inspectInstallation(args) {
  const {env, source, contract, reference, versions, changes, fetcher=fetch} = args;
  checkContext(env, source, contract, reference, versions, changes, false);
  const query = transport(env, fetcher), presence = await query(presenceSql(), true, 'PRESENCE');
  requireThat(Array.isArray(presence) && presence.length === 1 && same(keys(presence[0]), ['present'])
    && [0,3].includes(presence[0].present), 'PARTIAL_INSTALLATION_REFUSED');
  if (presence[0].present === 0) return {mode:'empty'};
  checkContext(env, source, contract, reference, versions, changes);
  const snapshot = checkInstalled(await query(installedSql(), true, 'INSPECT'), contract, reference, versions);
  return {mode:'installed', snapshot};
}

export async function proveInstalledRegressions(args) {
  const {env, source, contract, reference, versions, changes, sql, fetcher=fetch} = args;
  checkContext(env, source, contract, reference, versions, changes);
  requireThat(typeof sql === 'string' && sql.startsWith('BEGIN;\n') && sql.trimEnd().endsWith('ROLLBACK;')
    && (sql.match(/^\s*BEGIN;\s*$/gm) ?? []).length === 1
    && (sql.match(/^\s*ROLLBACK;\s*$/gm) ?? []).length === 1
    && !/^\s*COMMIT;\s*$/im.test(sql) && !sql.includes('-- migration:'), 'REGRESSION_TRANSACTION_REFUSED');
  const query = transport(env, fetcher);
  const before = checkInstalled(await query(installedSql(), true, 'BEFORE'), contract, reference, versions);
  let transactionError;
  try { await query(sql, false, 'REGRESSIONS'); } catch (error) { transactionError = error; }
  // Independent read even if the transaction response was lost. Never retry it.
  const after = checkInstalled(await query(installedSql(), true, 'AFTER'), contract, reference, versions);
  requireThat(same(before, after), 'ROLLBACK_NOT_RESTORED');
  if (transactionError) throw transactionError;
  return {schemaVersion:1, mode:'installed', projectRef:PROJECT, candidate:source.candidate,
    sourcePins:Object.fromEntries(['migrationSha256','capacitySha256','admissionSha256'].map(k=>[k,source[k]])),
    referenceDeltaMd5:reference.deltaMd5, catalogue:after.catalogue, registry:after.registry,
    regressionSqlSha256:digest(sql), snapshots:{before,after}, rollbackVerified:true,
    installedCatalogueVerified:true, extraFingerprintsPreserved:true, protocolEnabled:false,
    capabilityEnabled:false, providerInvoked:false, migrationReapplied:false};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const mode = process.argv[2];
    if (mode === 'probe-sql' && process.argv.length === 3) {
      process.stdout.write(installedSql(true));
    } else {
    requireThat(['inspect','regressions'].includes(mode) && process.argv.length === (mode==='inspect'?3:4), 'MODE_REFUSED');
    const env = process.env, root = process.cwd(), dir = env.RUNNER_TEMP;
    requireThat(dir && isAbsolute(dir), 'PATH_REFUSED');
    const source = sourceManifest(root, env.CANDIDATE_SHA);
    const contract = JSON.parse(readFileSync(resolve(root,'scripts/ci/connect-staging-closed.contract.json'),'utf8'));
    const reference = JSON.parse(readFileSync(resolve(dir,'connect-catalogue-reference.json'),'utf8'));
    const versions = git(root,['ls-tree','-r','--name-only',env.BASE_SHA,'supabase/migrations'])
      .split('\n').map(x=>/^supabase\/migrations\/(\d{14})_[^/]+\.sql$/.exec(x)?.[1]).filter(Boolean).sort();
    const diff = git(root,['diff','--name-status','--no-renames',`${env.BASE_SHA}...HEAD`,'--','supabase/migrations/*.sql']);
    const changes = diff.split('\n').filter(Boolean).map(line=>line.split('\t'));
    const args = {env,source,contract,reference,versions,changes};
    if (mode === 'inspect') {
      requireThat(env.GITHUB_OUTPUT && isAbsolute(env.GITHUB_OUTPUT), 'OUTPUT_PATH_REFUSED');
      const result = await inspectInstallation(args);
      writeFileSync(resolve(dir,'connect-installed-inspection.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx',mode:0o600});
      appendFileSync(env.GITHUB_OUTPUT,`mode=${result.mode}\n`);
      console.log(`CONNECT_INSTALLED_MODE_${result.mode.toUpperCase()}_VERIFIED`);
    } else {
      const sql = readFileSync(resolve(process.argv[3]),'utf8');
      const proof = await proveInstalledRegressions({...args,sql});
      writeFileSync(resolve(dir,'connect-installed-proof.json'),JSON.stringify(proof,null,2)+'\n',{flag:'wx',mode:0o600});
      console.log('CONNECT_INSTALLED_CATALOGUE_ET_ROLLBACK_VERIFIES');
    }
    }
  } catch (error) {
    console.error(error.message?.startsWith('CONNECT_INSTALLED_') ? error.message : 'CONNECT_INSTALLED_LOCAL_REFUSED');
    process.exitCode=1;
  }
}

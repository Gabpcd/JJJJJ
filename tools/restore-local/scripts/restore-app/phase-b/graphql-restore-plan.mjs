// PREPARATION ONLY. This module has no CLI or database/process/network API.
// The private native candidate remains blocked until an independent review approves
// the new source witness, complete partition, and one-transaction psql path.
import { createHash } from 'node:crypto';
import { GRAPHQL_WITNESS_FLAGS as WITNESS_FLAGS, GRAPHQL_COMPONENTS, GRAPHQL_COMPONENT_LABELS, projectGraphqlDiagnostic } from './contract.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const fail = (reason, context, details = {}) => { throw Object.assign(Error('B_GRAPHQL_RESTORE_REFUSED'),
  { code: 'B_GRAPHQL_RESTORE_REFUSED', graphql: projectGraphqlDiagnostic({ ...details, reason, context }) }); };
const requireValue = (ok, reason, context, details) => { if (!ok) fail(reason, context, details); };
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
export const GRAPHQL_SOURCE = Object.freeze({
  postgresCommit: 'a431c10a356be4c700d2e3f2af8551e2fec5e250',
  migration: '20231017062225_grant_pg_graphql_permissions_for_custom_roles.sql',
  migrationSha256: '1833af7170c97bc444cfe9f823be73d3ff3f9b18e47c2ee1181ff33a1fbbb673',
  hookBodySha256: 'ad8bfb866513170056bbc1f817103be550cd62efcb589fa2a3807718efb3eb6a',
  wrapperBodySha256: '03b36c9655c8688b452fba90346ce43dafa2ded68bffb9250da6c236133d467e',
});

// These are archive descriptions, not SQL reconstructed from catalogue rows.
// Functions' default privileges must precede creation of the wrapper too.
export const GRAPHQL_PREREQUISITES = Object.freeze([
  'SCHEMA - extensions postgres',
  'SCHEMA - graphql_public supabase_admin',
  'FUNCTION extensions grant_pg_graphql_access() supabase_admin',
  'DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS supabase_admin',
  'EVENT TRIGGER - issue_pg_graphql_access supabase_admin',
]);
export function assertGraphqlWitness(value, context = 'SOURCE_SNAPSHOT') {
  const keys = ['schemaVersion', ...WITNESS_FLAGS, 'initialPrivilegesCount', 'fingerprint', 'components'];
  requireValue(plain(value) && Object.keys(value).length === keys.length
    && keys.every(key => Object.hasOwn(value, key)) && value.schemaVersion === 2, 'WITNESS_SHAPE', context);
  const failedFlags = WITNESS_FLAGS.filter(key => value[key] !== true);
  requireValue(failedFlags.length === 0, 'WITNESS_FLAGS', context, { failedFlags });
  requireValue([0, 1].includes(value.initialPrivilegesCount), 'WITNESS_INITIAL_PRIVILEGES', context);
  requireValue(sha(value.fingerprint), 'WITNESS_FINGERPRINT', context);
  requireValue(plain(value.components) && Object.keys(value.components).length === GRAPHQL_COMPONENTS.length
    && GRAPHQL_COMPONENTS.every(key => Object.hasOwn(value.components, key) && sha(value.components[key])), 'WITNESS_COMPONENTS', context);
  return value;
}
export function assertGraphqlRestored(source, target) {
  assertGraphqlWitness(source, 'SOURCE_SNAPSHOT'); assertGraphqlWitness(target, 'TARGET_RESTORED');
  requireValue(source.initialPrivilegesCount === target.initialPrivilegesCount, 'PARITY_INITIAL_PRIVILEGES', 'TARGET_COMPARE');
  const mismatchedComponents = GRAPHQL_COMPONENTS.filter(key => source.components[key] !== target.components[key]).map(key => GRAPHQL_COMPONENT_LABELS[key]);
  requireValue(source.fingerprint === target.fingerprint && mismatchedComponents.length === 0,
    'PARITY_FINGERPRINT', 'TARGET_COMPARE', { mismatchedComponents });
  return { nativeGraphqlPrerequisiteVerified: true, nativeGraphqlRestoredExact: true };
}

function entriesOf(toc, context) {
  requireValue(Buffer.isBuffer(toc) && toc.length > 0 && toc.length <= 4 * 1024 * 1024, 'TOC_BUFFER', context);
  const text = toc.toString('utf8'); requireValue(Buffer.from(text).equals(toc), 'TOC_UTF8', context);
  const ids = new Set(), entries = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line || line.startsWith(';')) continue;
    requireValue(!/[\x00-\x1f\x7f]/.test(line), 'TOC_CONTROL', context);
    const match = /^([1-9][0-9]{0,6}); ([0-9]+) ([0-9]+) (.+)$/.exec(line);
    requireValue(match, 'TOC_FORMAT', context);
    requireValue(!ids.has(match[1]), 'TOC_DUPLICATE_ID', context); ids.add(match[1]);
    requireValue(!/^(DATABASE|DATABASE PROPERTIES|SUBSCRIPTION) /.test(match[4]), 'TOC_SCOPE', context);
    entries.push({ id: match[1], line, description: match[4] });
  }
  requireValue(entries.length > 100 && entries.length < 30_000, 'TOC_COUNT', context);
  return entries;
}
export function normalizedGraphqlTocHash(toc, context = 'NORMALIZE') {
  return hash(entriesOf(toc, context).map(entry => entry.description).sort().join('\n') + '\n');
}

export function partitionGraphqlRestore({ archive, archiveSha256, toc, witness, review }) {
  const context = 'PARTITION';
  // Approval is a pinned review field, never inferred from the current run.
  requireValue(review?.nativeGraphqlRepairReviewed === true && sha(review.nativeRestoreTocSha256), 'REVIEW', context);
  assertGraphqlWitness(witness, 'SOURCE_SNAPSHOT');
  requireValue(Buffer.isBuffer(archive) && archive.length > 5 && archive.length < 64 * 1024 * 1024, 'ARCHIVE_BUFFER', context);
  requireValue(archive.subarray(0, 5).toString() === 'PGDMP', 'ARCHIVE_MAGIC', context);
  requireValue(sha(archiveSha256) && hash(archive) === archiveSha256, 'ARCHIVE_HASH', context);
  const all = entriesOf(toc, context);
  requireValue(normalizedGraphqlTocHash(toc, context) === review.nativeRestoreTocSha256, 'TOC_REVIEW_HASH', context);
  const requiredReasons = ['REQUIRED_EXTENSION_SCHEMA','REQUIRED_WRAPPER_SCHEMA','REQUIRED_HOOK','REQUIRED_DEFAULT_ACL','REQUIRED_TRIGGER'];
  const prerequisites = GRAPHQL_PREREQUISITES.map((description, index) => {
    const found = all.filter(entry => entry.description === description);
    requireValue(found.length === 1, requiredReasons[index], context); return found[0];
  });
  // All B14 selectors are unchanged. Diagnostics never broaden their matches.
  requireValue(all.filter(entry => /^FUNCTION extensions grant_pg_graphql_access\(/.test(entry.description)).length === 1, 'HOOK_COUNT', context);
  requireValue(all.filter(entry => /^EVENT TRIGGER - issue_pg_graphql_access(?: |$)/.test(entry.description)).length === 1, 'TRIGGER_COUNT', context);
  requireValue(all.filter(entry => /^DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS /.test(entry.description)).length === 1, 'DEFAULT_ACL_COUNT', context);
  requireValue(!all.some(entry => /^FUNCTION graphql_public /.test(entry.description)), 'WRAPPER_DEFINITION', context);
  requireValue(all.filter(entry => /^EXTENSION - pg_graphql $/.test(entry.description)).length === 1, 'EXTENSION_COUNT', context);
  requireValue(all.some(entry => /^ACL graphql_public FUNCTION graphql\("operationName" text, query text, variables jsonb, extensions jsonb\) supabase_admin$/.test(entry.description)), 'WRAPPER_ACL', context);
  const selected = new Set(prerequisites.map(entry => entry.id));
  const remainder = all.filter(entry => !selected.has(entry.id));
  // Prove the union over original lines and IDs, not only a count/hash of tags.
  const joined = [...prerequisites, ...remainder];
  requireValue(joined.length === all.length && new Set(joined.map(entry => entry.id)).size === all.length
    && JSON.stringify(joined.map(entry => entry.line).sort()) === JSON.stringify(all.map(entry => entry.line).sort()), 'PARTITION_EXHAUSTIVE', context);
  const list = rows => Buffer.from(rows.map(entry => entry.line).join('\n') + '\n');
  return Object.freeze({ archive, sourceWitness: Object.freeze({ ...witness, components: Object.freeze({ ...witness.components }) }), prerequisites: list(prerequisites), remainder: list(remainder),
    proof: Object.freeze({ schemaVersion: 1, exactArchiveReused: true, allEntriesPreservedExactlyOnce: true,
      prerequisites: prerequisites.length, entries: all.length, nativeGraphqlPrerequisiteVerified: true,
      restored: false, appVerified: false }) });
}

// Fixed private paths in the independently inspected disposable target only.
// Lists must be written with 0600, exclusively, and read back/hash-checked by the
// native adapter. No host credentials/database/connection arguments in exports.
export function graphqlExportArgs(partition) {
  requireValue(['prerequisites', 'remainder'].includes(partition), 'EXPORT_PARTITION', 'EXPORT_ASSEMBLY');
  return ['--exit-on-error', '--no-password', '--file=-', '--use-list=/tmp/jolene-graphql-' + partition + '.list'];
}
export function graphqlTransactionArgs() {
  return ['-X', '-q', '-A', '-t', '--single-transaction', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
    '-U', 'supabase_admin', '-h', '/var/run/postgresql', '-d', 'jolene_candidatures_pg17_test', '-f', '-'];
}

export async function prepareGraphqlRestore(input, exportSql) {
  const plan = partitionGraphqlRestore(input);
  requireValue(typeof exportSql === 'function', 'EXPORT_CALLBACK', 'EXPORT_ASSEMBLY');
  const parts = [];
  for (const partition of ['prerequisites', 'remainder']) {
    // Each exporter receives the unchanged archive and a complete disjoint list.
    // It must invoke the pinned pg_restore without any database or -1 option.
    const context = partition === 'prerequisites' ? 'EXPORT_PREREQUISITES' : 'EXPORT_REMAINDER';
    const listHash = hash(plan[partition]);
    requireValue(hash(plan.archive) === input.archiveSha256, 'EXPORT_ARCHIVE_MUTATED', context);
    const sql = await exportSql({ partition, archive: plan.archive, list: plan[partition], args: graphqlExportArgs(partition) });
    requireValue(hash(plan.archive) === input.archiveSha256, 'EXPORT_ARCHIVE_MUTATED', context);
    requireValue(hash(plan[partition]) === listHash, 'EXPORT_LIST_MUTATED', context);
    requireValue(Buffer.isBuffer(sql) && sql.length > 0 && sql.length <= 64 * 1024 * 1024, 'EXPORT_SQL_BUFFER', context);
    requireValue(!sql.includes(Buffer.from('\0')), 'EXPORT_SQL_NUL', context);
    parts.push(sql);
  }
  requireValue(parts[0].length + parts[1].length < 64 * 1024 * 1024, 'EXPORT_TOTAL_BOUND', 'EXPORT_ASSEMBLY');
  // No SQL rewriting, sanitizing, owner substitution, or ACL filtering. The
  // official exporter emits both fragments; psql -1 must execute this once.
  return { sql: Buffer.concat([parts[0], Buffer.from('\n'), parts[1], Buffer.from('\n')]),
    sourceWitness: plan.sourceWitness, proof: plan.proof, transactionArgs: graphqlTransactionArgs() };
}

// PREPARATION ONLY. This module has no CLI or database/process/network API.
// The private native candidate remains blocked until an independent review approves
// the new source witness, complete partition, and one-transaction psql path.
import { createHash } from 'node:crypto';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const fail = () => { throw Object.assign(Error('B_GRAPHQL_RESTORE_REFUSED'), { code: 'B_GRAPHQL_RESTORE_REFUSED' }); };
const requireValue = ok => { if (!ok) fail(); };
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
const WITNESS_FLAGS = Object.freeze([
  'context', 'nativeExtensionExact', 'wrapperSignatureExact', 'wrapperBodyExact',
  'wrapperMembershipExact', 'wrapperOwnerExact', 'hookSignatureExact',
  'hookBodyExact', 'hookOwnerExact', 'hookNotExtensionMember', 'triggerExact',
  'schemaOwnersExact', 'defaultFunctionAclExact', 'noGlobalFunctionDefaultAcl',
]);
export function assertGraphqlWitness(value) {
  const keys = ['schemaVersion', ...WITNESS_FLAGS, 'initialPrivilegesCount', 'fingerprint'];
  requireValue(plain(value) && Object.keys(value).length === keys.length
    && keys.every(key => Object.hasOwn(value, key)) && value.schemaVersion === 1
    && WITNESS_FLAGS.every(key => value[key] === true)
    && [0, 1].includes(value.initialPrivilegesCount) && sha(value.fingerprint));
  return value;
}
export function assertGraphqlRestored(source, target) {
  assertGraphqlWitness(source); assertGraphqlWitness(target);
  requireValue(source.initialPrivilegesCount === target.initialPrivilegesCount
    && source.fingerprint === target.fingerprint);
  return { nativeGraphqlPrerequisiteVerified: true, nativeGraphqlRestoredExact: true };
}

function entriesOf(toc) {
  requireValue(Buffer.isBuffer(toc) && toc.length > 0 && toc.length <= 4 * 1024 * 1024);
  const text = toc.toString('utf8'); requireValue(Buffer.from(text).equals(toc));
  const ids = new Set(), entries = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line || line.startsWith(';')) continue;
    requireValue(!/[\x00-\x1f\x7f]/.test(line));
    const match = /^([1-9][0-9]{0,6}); ([0-9]+) ([0-9]+) (.+)$/.exec(line);
    requireValue(match && !ids.has(match[1])); ids.add(match[1]);
    requireValue(!/^(DATABASE|DATABASE PROPERTIES|SUBSCRIPTION) /.test(match[4]));
    entries.push({ id: match[1], line, description: match[4] });
  }
  requireValue(entries.length > 100 && entries.length < 30_000);
  return entries;
}
export function normalizedGraphqlTocHash(toc) {
  return hash(entriesOf(toc).map(entry => entry.description).sort().join('\n') + '\n');
}

export function partitionGraphqlRestore({ archive, archiveSha256, toc, witness, review }) {
  // Approval is a pinned review field, never inferred from the current run.
  requireValue(review?.nativeGraphqlRepairReviewed === true && sha(review.nativeRestoreTocSha256));
  assertGraphqlWitness(witness);
  requireValue(Buffer.isBuffer(archive) && archive.length > 5 && archive.length < 64 * 1024 * 1024
    && archive.subarray(0, 5).toString() === 'PGDMP' && sha(archiveSha256) && hash(archive) === archiveSha256);
  const all = entriesOf(toc);
  requireValue(normalizedGraphqlTocHash(toc) === review.nativeRestoreTocSha256);
  const prerequisites = GRAPHQL_PREREQUISITES.map(description => {
    const found = all.filter(entry => entry.description === description);
    requireValue(found.length === 1); return found[0];
  });
  // A wrapper definition in the dump, another overload, or a second hook is a
  // different recovery problem. Never relax the match to make a run proceed.
  requireValue(all.filter(entry => /^FUNCTION extensions grant_pg_graphql_access\(/.test(entry.description)).length === 1
    && all.filter(entry => /^EVENT TRIGGER - issue_pg_graphql_access(?: |$)/.test(entry.description)).length === 1
    && all.filter(entry => /^DEFAULT ACL graphql_public DEFAULT PRIVILEGES FOR FUNCTIONS /.test(entry.description)).length === 1
    && !all.some(entry => /^FUNCTION graphql_public /.test(entry.description))
    && all.filter(entry => /^EXTENSION - pg_graphql $/.test(entry.description)).length === 1
    && all.some(entry => /^ACL graphql_public FUNCTION graphql\("operationName" text, query text, variables jsonb, extensions jsonb\) supabase_admin$/.test(entry.description)));
  const selected = new Set(prerequisites.map(entry => entry.id));
  const remainder = all.filter(entry => !selected.has(entry.id));
  // Prove the union over original lines and IDs, not only a count/hash of tags.
  const joined = [...prerequisites, ...remainder];
  requireValue(joined.length === all.length && new Set(joined.map(entry => entry.id)).size === all.length
    && JSON.stringify(joined.map(entry => entry.line).sort()) === JSON.stringify(all.map(entry => entry.line).sort()));
  const list = rows => Buffer.from(rows.map(entry => entry.line).join('\n') + '\n');
  return Object.freeze({ archive, sourceWitness: Object.freeze({ ...witness }), prerequisites: list(prerequisites), remainder: list(remainder),
    proof: Object.freeze({ schemaVersion: 1, exactArchiveReused: true, allEntriesPreservedExactlyOnce: true,
      prerequisites: prerequisites.length, entries: all.length, nativeGraphqlPrerequisiteVerified: true,
      restored: false, appVerified: false }) });
}

// Fixed private paths in the independently inspected disposable target only.
// Lists must be written with 0600, exclusively, and read back/hash-checked by the
// native adapter. No host credentials/database/connection arguments in exports.
export function graphqlExportArgs(partition) {
  requireValue(['prerequisites', 'remainder'].includes(partition));
  return ['--exit-on-error', '--no-password', '--file=-', '--use-list=/tmp/jolene-graphql-' + partition + '.list'];
}
export function graphqlTransactionArgs() {
  return ['-X', '-q', '-A', '-t', '--single-transaction', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
    '-U', 'supabase_admin', '-h', '/var/run/postgresql', '-d', 'jolene_candidatures_pg17_test', '-f', '-'];
}

export async function prepareGraphqlRestore(input, exportSql) {
  const plan = partitionGraphqlRestore(input);
  requireValue(typeof exportSql === 'function');
  const parts = [];
  for (const partition of ['prerequisites', 'remainder']) {
    // Each exporter receives the unchanged archive and a complete disjoint list.
    // It must invoke the pinned pg_restore without any database or -1 option.
    const listHash = hash(plan[partition]);
    requireValue(hash(plan.archive) === input.archiveSha256);
    const sql = await exportSql({ partition, archive: plan.archive, list: plan[partition], args: graphqlExportArgs(partition) });
    requireValue(hash(plan.archive) === input.archiveSha256 && hash(plan[partition]) === listHash);
    requireValue(Buffer.isBuffer(sql) && sql.length > 0 && sql.length <= 64 * 1024 * 1024
      && !sql.includes(Buffer.from('\0')));
    parts.push(sql);
  }
  requireValue(parts[0].length + parts[1].length < 64 * 1024 * 1024);
  // No SQL rewriting, sanitizing, owner substitution, or ACL filtering. The
  // official exporter emits both fragments; psql -1 must execute this once.
  return { sql: Buffer.concat([parts[0], Buffer.from('\n'), parts[1], Buffer.from('\n')]),
    sourceWitness: plan.sourceWitness, proof: plan.proof, transactionArgs: graphqlTransactionArgs() };
}

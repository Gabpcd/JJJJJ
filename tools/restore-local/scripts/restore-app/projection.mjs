import { phaseFailure, FAILURE_CODES } from './failure.mjs';
import { hash } from './identity.mjs';
import { CAPTURE_STAGES } from './snapshot-restore.mjs';
const required = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
const SHA = /^[a-f0-9]{64}$/;
export const STAGES = Object.freeze(['identity', 'units', 'plan', 'preload', 'preflight', 'up', 'inspect', 'extensions',
  'import', 'current_product_witness', 'source_api_restart', 'source_seed', 'object_readback', 'capture', ...CAPTURE_STAGES, 'source_off', 'complete', 'cleanup', 'absence']);
const KINDS = Object.freeze(['ENCODING', 'STDSTRINGS', 'SEARCHPATH', 'MATERIALIZED VIEW DATA', 'MATERIALIZED VIEW', 'SEQUENCE OWNED BY', 'DEFAULT ACL', 'TABLE DATA',
  'SEQUENCE SET', 'FK CONSTRAINT', 'ROW SECURITY', 'EVENT TRIGGER', 'PUBLICATION TABLE', 'PUBLICATION', 'PROCEDURE',
  'SCHEMA', 'EXTENSION', 'COMMENT', 'TYPE', 'DOMAIN', 'FUNCTION', 'AGGREGATE', 'OPERATOR CLASS', 'OPERATOR FAMILY', 'OPERATOR',
  'TABLE', 'SEQUENCE', 'VIEW', 'CONSTRAINT', 'INDEX', 'TRIGGER', 'RULE', 'POLICY', 'ACL', 'COLLATION', 'TEXT SEARCH CONFIGURATION',
  'TEXT SEARCH DICTIONARY', 'TEXT SEARCH PARSER', 'TEXT SEARCH TEMPLATE', 'TRANSFORM', 'CAST', 'ACCESS METHOD']);
const SCHEMAS = new Set(['-', 'auth', 'storage', 'public', 'private', 'extensions', 'vault', 'net', 'cron', 'pg_catalog',
  'graphql', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'pgsodium', 'pgsodium_masks']);
const REQUIRED_TABLES = Object.freeze(['auth.users', 'auth.identities', 'auth.sessions', 'auth.refresh_tokens',
  'storage.objects', 'storage.buckets', 'public.factures_honoraires', 'public.factures_honoraires_documents']);
export function projectToc(bytes) {
  const counts = {}, schemas = {}, requiredTables = Object.fromEntries(REQUIRED_TABLES.map(name => [name, { table: 0, data: 0 }]));
  const normalized = [];
  for (const line of bytes.toString('utf8').split(/\r?\n/)) {
    if (!line || line.startsWith(';')) continue;
    const match = /^\d+; \d+ \d+ (.+)$/.exec(line); required(match, 'PHASE_A_TOC_FORMAT');
    const value = match[1], kind = KINDS.find(item => value.startsWith(item + ' '));
    required(kind, 'PHASE_A_TOC_KIND');
    const rest = value.slice(kind.length + 1), schema = rest.split(' ')[0];
    required(SCHEMAS.has(schema), 'PHASE_A_TOC_SCHEMA');
    normalized.push(value); counts[kind] = (counts[kind] ?? 0) + 1; schemas[schema] = (schemas[schema] ?? 0) + 1;
    if (kind === 'TABLE' || kind === 'TABLE DATA') {
      const tokens = rest.split(' '), name = tokens[0] + '.' + tokens[1];
      if (Object.hasOwn(requiredTables, name)) requiredTables[name][kind === 'TABLE' ? 'table' : 'data']++;
    }
  }
  required(normalized.length > 100 && normalized.length < 30_000, 'PHASE_A_TOC_COUNT');
  required(Object.values(requiredTables).every(value => value.table === 1 && value.data === 1), 'PHASE_A_TOC_REQUIRED_TABLE');
  return { normalizedSha256: hash(Buffer.from(normalized.sort().join('\n') + '\n')), entries: normalized.length,
    kinds: counts, schemas, requiredTables, rawTocExported: false };
}
export function closedFailure(error, stage) {
  const diagnostic = error?.diagnostic;
  return { result: 'PHASE_A_REFUSED', stage: STAGES.includes(stage) ? stage : 'identity',
    code: FAILURE_CODES.has(error?.publicCode) ? error.publicCode : 'PHASE_A_FAILED',
    httpStatus: FAILURE_CODES.has(error?.publicCode) && Number.isInteger(error?.httpStatus)
      && error.httpStatus >= 100 && error.httpStatus <= 599 ? error.httpStatus : null,
    sqlstate: /^[A-Z0-9]{5}$/.test(diagnostic?.sqlstate ?? '') ? diagnostic.sqlstate : null,
    sqlLine: Number.isSafeInteger(diagnostic?.line) && diagnostic.line > 0 && diagnostic.line < 1_000_000 ? diagnostic.line : null,
    readyForRestore: false, readyForDispatchPhaseB: false, restored: false, appVerified: false };
}
export function projectSnapshot(snapshot, fixture) {
  required(SHA.test(snapshot.archiveSha256) && SHA.test(snapshot.tocSha256) && snapshot.files.length >= 2
    && snapshot.files.length <= 32 && snapshot.before && snapshot.catalogue, 'PHASE_A_SNAPSHOT_SHAPE');
  for (const file of fixture.files) required(snapshot.files.filter(value => value.sha256 === hash(file.bytes)
    && value.bytes === file.bytes.length).length === 1, 'PHASE_A_STORAGE_BYTES');
  const counts = { users: 5, identities: 5, soignants: 2, etablissements: 2, missions: 1, invoices: 1, versions: 1, objects: 2 };
  const tables = ['auth.users', 'auth.identities', 'public.soignants', 'public.etablissements', 'public.missions',
    'public.factures_honoraires', 'public.factures_honoraires_documents', 'storage.objects'];
  Object.keys(counts).forEach((key, index) => required(snapshot.before[tables[index]]?.count === counts[key], 'PHASE_A_ROW_COUNTS'));
  required(snapshot.before['auth.sessions']?.count === 0 && snapshot.before['auth.refresh_tokens']?.count === 0, 'PHASE_A_SESSIONS_PRESENT');
  return { archiveSha256: snapshot.archiveSha256, tocSha256: snapshot.tocSha256,
    tableDigestCount: Object.keys(snapshot.before).length, sourceCheckpointStable: true,
    fileCount: snapshot.files.length, fileBytes: snapshot.files.reduce((sum, file) => sum + file.bytes, 0),
    expectedObjectBytesPresent: 2, counts, sessions: 0, refreshTokens: 0,
    privateSnapshotsExported: false, passwordsOrIdentitiesExported: false };
}

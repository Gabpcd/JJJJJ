import { phaseFailure, FAILURE_CODES } from './failure.mjs';
import { hash } from './identity.mjs';
import { CAPTURE_STAGES } from './snapshot-restore.mjs';
const required = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
const SHA = /^[a-f0-9]{64}$/;
export const STAGES = Object.freeze(['identity', 'units', 'plan', 'preload', 'preflight', 'up', 'inspect', 'extensions',
  'import', 'current_product_witness', 'source_api_restart', 'source_seed', 'object_readback', 'capture', ...CAPTURE_STAGES, 'project_toc', 'source_off', 'complete', 'cleanup', 'absence']);
// PostgreSQL REL_17_6 pg_dump.c ArchiveEntry descriptions; provenance is pinned
// in toc-pg17-descriptors.json. This projects metadata, never authorizes restore.
export const PG17_TOC_KINDS = Object.freeze([
  "PUBLICATION TABLES IN SCHEMA",
  "TEXT SEARCH CONFIGURATION",
  "MATERIALIZED VIEW DATA",
  "TEXT SEARCH DICTIONARY",
  "FOREIGN DATA WRAPPER",
  "TEXT SEARCH TEMPLATE",
  "DATABASE PROPERTIES",
  "PROCEDURAL LANGUAGE",
  "SUBSCRIPTION TABLE",
  "TEXT SEARCH PARSER",
  "MATERIALIZED VIEW",
  "PUBLICATION TABLE",
  "SEQUENCE OWNED BY",
  "CHECK CONSTRAINT",
  "OPERATOR FAMILY",
  "OPERATOR CLASS",
  "SECURITY LABEL",
  "pg_largeobject",
  "ACCESS METHOD",
  "BLOB METADATA",
  "EVENT TRIGGER",
  "FK CONSTRAINT",
  "FOREIGN TABLE",
  "INDEX ATTACH",
  "ROW SECURITY",
  "SEQUENCE SET",
  "SUBSCRIPTION",
  "TABLE ATTACH",
  "USER MAPPING",
  "DEFAULT ACL",
  "PUBLICATION",
  "CONSTRAINT",
  "CONVERSION",
  "SEARCHPATH",
  "SHELL TYPE",
  "STATISTICS",
  "STDSTRINGS",
  "TABLE DATA",
  "AGGREGATE",
  "COLLATION",
  "EXTENSION",
  "PROCEDURE",
  "TRANSFORM",
  "DATABASE",
  "ENCODING",
  "FUNCTION",
  "OPERATOR",
  "SEQUENCE",
  "COMMENT",
  "DEFAULT",
  "TRIGGER",
  "DOMAIN",
  "POLICY",
  "SCHEMA",
  "SERVER",
  "BLOBS",
  "INDEX",
  "TABLE",
  "CAST",
  "RULE",
  "TYPE",
  "VIEW",
  "ACL"
]);
// Always longest match, independent of inventory/source order (DEFAULT ACL vs DEFAULT).
const KINDS = [...PG17_TOC_KINDS].sort((a,b)=>b.length-a.length||(a<b?-1:a>b?1:0));
const LEGACY_KIND_CANDIDATES = Object.freeze(['BLOB COMMENTS','ACL LANGUAGE','WARNING','BLOB']);
const SCHEMAS = new Set(['-', 'auth', 'storage', 'public', 'private', 'extensions', 'vault', 'net', 'cron', 'pg_catalog',
  'graphql', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'pgsodium', 'pgsodium_masks', 'pgbouncer']);
const REQUIRED_TABLES = Object.freeze(['auth.users', 'auth.identities', 'auth.sessions', 'auth.refresh_tokens',
  'storage.objects', 'storage.buckets', 'public.factures_honoraires', 'public.factures_honoraires_documents']);
// Diagnostic labels only. None of these candidates is added to SCHEMAS or accepted.
const NATIVE_SCHEMA_CANDIDATES = Object.freeze(['_realtime', '_analytics', 'pgmq', 'pgmq_public']);
const TOKEN_CLASSES = Object.freeze(['empty_token', 'attach_after_table_or_index', 'quoted_token',
  'known_native_candidate', 'other_identifier', 'invalid_token']);
function tocSchemaDiagnostic(entryOrdinal, kind, token) {
  const candidate = NATIVE_SCHEMA_CANDIDATES.find(value => value === token) ?? null;
  const tokenClass = token === '' ? 'empty_token'
    : ['TABLE', 'INDEX'].includes(kind) && token === 'ATTACH' ? 'attach_after_table_or_index'
    : token.startsWith('"') ? 'quoted_token'
    : candidate !== null ? 'known_native_candidate'
    : /^[a-z_][a-z0-9_$]*$/.test(token) ? 'other_identifier' : 'invalid_token';
  return { entryOrdinal: Math.min(entryOrdinal, 30_000), kind, tokenClass, candidate,
    tokenSha256: candidate === null ? hash(token) : null };
}
function closedTocDiagnostic(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || JSON.stringify(Object.keys(value).sort()) !== JSON.stringify(['candidate', 'entryOrdinal', 'kind', 'tokenClass', 'tokenSha256'])
    || !Number.isSafeInteger(value.entryOrdinal) || value.entryOrdinal < 1 || value.entryOrdinal > 30_000
    || !KINDS.includes(value.kind) || !TOKEN_CLASSES.includes(value.tokenClass)) return null;
  const known = value.tokenClass === 'known_native_candidate';
  if (known ? !NATIVE_SCHEMA_CANDIDATES.includes(value.candidate) || value.tokenSha256 !== null
    : value.candidate !== null || typeof value.tokenSha256 !== 'string' || !SHA.test(value.tokenSha256)) return null;
  // Never spread the input: arbitrary fields, free tokens and toJSON stay private.
  return { entryOrdinal: value.entryOrdinal, kind: value.kind, tokenClass: value.tokenClass,
    candidate: value.candidate, tokenSha256: value.tokenSha256 };
}
function tocKindDiagnostic(entryOrdinal, value) {
  // These four names are understood for old archives by PG17's archive reader;
  // they are diagnostics only, not added to pg_dump17's emitting descriptor set.
  const candidate=LEGACY_KIND_CANDIDATES.find(kind=>value.startsWith(kind+' '))??null;
  return {entryOrdinal:Math.min(entryOrdinal,30_000),candidate,
    prefixSha256:hash(value.split(' ').slice(0,4).join(' '))};
}
function closedKindDiagnostic(value) {
  if(!value||typeof value!=='object'||Array.isArray(value)
    ||JSON.stringify(Object.keys(value).sort())!==JSON.stringify(['candidate','entryOrdinal','prefixSha256'])
    ||!Number.isSafeInteger(value.entryOrdinal)||value.entryOrdinal<1||value.entryOrdinal>30_000
    ||!(value.candidate===null||LEGACY_KIND_CANDIDATES.includes(value.candidate))
    ||typeof value.prefixSha256!=='string'||!SHA.test(value.prefixSha256))return null;
  return {entryOrdinal:value.entryOrdinal,candidate:value.candidate,prefixSha256:value.prefixSha256};
}
export function projectToc(bytes) {
  const counts = {}, schemas = {}, requiredTables = Object.fromEntries(REQUIRED_TABLES.map(name => [name, { table: 0, data: 0 }]));
  const normalized = [];
  for (const line of bytes.toString('utf8').split(/\r?\n/)) {
    if (!line || line.startsWith(';')) continue;
    const match = /^\d+; \d+ \d+ (.+)$/.exec(line); required(match, 'PHASE_A_TOC_FORMAT');
    const value = match[1], legacy=LEGACY_KIND_CANDIDATES.find(item=>value.startsWith(item+' '));
    const knownKind=KINDS.find(item => value.startsWith(item+' '));
    const kind=legacy&&(!knownKind||legacy.length>knownKind.length)?undefined:knownKind;
    required(kind, 'PHASE_A_TOC_KIND', {tocDiagnostic:tocKindDiagnostic(normalized.length+1,value)});
    const rest = value.slice(kind.length + 1), schema = rest.split(' ')[0];
    required(SCHEMAS.has(schema), 'PHASE_A_TOC_SCHEMA', {
      tocDiagnostic: tocSchemaDiagnostic(normalized.length + 1, kind, schema),
    });
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
    toc: error?.publicCode === 'PHASE_A_TOC_SCHEMA' ? closedTocDiagnostic(error?.tocDiagnostic)
      : error?.publicCode === 'PHASE_A_TOC_KIND' ? closedKindDiagnostic(error?.tocDiagnostic) : null,
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

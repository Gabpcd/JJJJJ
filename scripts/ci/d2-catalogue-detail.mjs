// Diagnostic séparé du produit : une requête de catalogue READ ONLY, aucun rebaselining.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const SOURCE_SHA = 'bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84';
const STAGE = 'mejpriaetwgtcstbgfid';
const MAX_BYTES = 2 * 1024 * 1024;
const here = dirname(fileURLToPath(import.meta.url));
const product = resolve(process.env.D2_PRODUCT_CHECKOUT || 'product');
const output = resolve('d2-catalogue-detail-proof');
const receipt = {
  observedAt: new Date().toISOString(), sourceSha: SOURCE_SHA, version: '1.0.7', build: 24,
  readOnly: true, qualification: 'NON_QUALIFIE', baselineChanged: false,
  realUiExecuted: false, authCreated: false, status: 'NOT_RUN',
};
const fail = code => { throw new Error(code); };
const object = (value, keys) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || Object.keys(value).sort().join('|') !== [...keys].sort().join('|')) fail('RESPONSE_SHAPE');
  return value;
};
const text = (value, max = 1024) => {
  if (typeof value !== 'string' || value.length > max
    || !/^[A-Za-z0-9_$ .,"()[\]:+-]+$/.test(value)) fail('RESPONSE_SHAPE');
  return value;
};
const hash = value => {
  if (typeof value !== 'string' || !/^[a-f0-9]{32}$/.test(value)) fail('RESPONSE_SHAPE');
  return value;
};
const maybeHash = value => value === null ? null : hash(value);
const bool = value => { if (typeof value !== 'boolean') fail('RESPONSE_SHAPE'); return value; };
const integer = value => {
  if (!Number.isSafeInteger(value) || value < 0 || value > 1000000) fail('RESPONSE_SHAPE');
  return value;
};
const list = (value, limit, map) => {
  if (!Array.isArray(value) || value.length > limit) fail('RESPONSE_SHAPE');
  return value.map(map);
};
const fields = (value, validators) => {
  object(value, Object.keys(validators));
  return Object.fromEntries(Object.entries(validators).map(([key, validate]) => [key, validate(value[key])]));
};
const aggregate = value => fields(value, {
  schema: hash, fonctions: hash, triggers: hash, crons_actifs: integer, audit_fk: integer,
});
const digest = value => createHash('sha256').update(value).digest('hex');
function readSelect(filename) {
  const sql = readFileSync(resolve(here, filename), 'utf8');
  const trimmed = sql.replace(/^\s*--[^\n]*\n/gm, '').trim();
  if (Buffer.byteLength(sql) > 16000 || !trimmed.startsWith('WITH\n')
    || !trimmed.endsWith(';') || trimmed.slice(0, -1).includes(';')
    || /\b(insert|update|delete|create|alter|drop|truncate|grant|revoke|call|do|copy|set|reset|vacuum|refresh)\b/i.test(trimmed)) fail('QUERY_CONTRACT');
  return { sql: trimmed.slice(0, -1), sha256: digest(sql) };
}
async function boundedJson(response) {
  const declared = response.headers.get('content-length');
  if (declared && Number(declared) > MAX_BYTES) fail('RESPONSE_TOO_LARGE');
  if (!response.body) fail('RESPONSE_SHAPE');
  const reader = response.body.getReader(), chunks = [];
  let bytes = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > MAX_BYTES) { await reader.cancel(); fail('RESPONSE_TOO_LARGE'); }
    chunks.push(Buffer.from(value));
  }
  receipt.responseBytes = bytes;
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

try {
  const workflowSha = process.env.GITHUB_SHA;
  if (!/^[a-f0-9]{40}$/.test(workflowSha || '')
    || !/^\d+$/.test(process.env.GITHUB_RUN_ID || '')
    || !/^\d+$/.test(process.env.GITHUB_RUN_ATTEMPT || '')) fail('CONFIGURATION');
  receipt.workflowSha = workflowSha;
  receipt.runId = process.env.GITHUB_RUN_ID;
  receipt.runAttempt = process.env.GITHUB_RUN_ATTEMPT;
  const actualSha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: product, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  if (actualSha !== SOURCE_SHA || process.env.STAGING_REF_SECRET !== STAGE || !process.env.STAGING_TOKEN) fail('CONFIGURATION');
  const { sqlCatalogueD, catalogueD, STAGING_REF } = await import(pathToFileURL(resolve(product, 'scripts/ci/candidatures-fixture-contract.mjs')).href);
  if (STAGING_REF !== STAGE) fail('CONFIGURATION');
  const decomposed = readSelect('d2-catalogue-decompose-readonly.sql');
  const projection = readSelect('d2-schema-projection-readonly.sql');
  receipt.queries = { decomposedSha256: decomposed.sha256, projectionSha256: projection.sha256, originalGuardSqlSha256: digest(sqlCatalogueD) };
  receipt.expected = aggregate({ ...catalogueD, crons_actifs: 0, audit_fk: 0 });
  // Les trois sous-requêtes partagent le même snapshot de cette instruction SELECT.
  const query = `SELECT (SELECT row_to_json(g) FROM (${sqlCatalogueD}) g) AS guard_catalogue,\n(${decomposed.sql}) AS catalogue_detail,\n(${projection.sql}) AS schema_projection`;
  const response = await fetch(`https://api.supabase.com/v1/projects/${STAGE}/database/query`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(35000),
    headers: { Authorization: `Bearer ${process.env.STAGING_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, read_only: true }),
  });
  receipt.httpStatus = response.status;
  if (!response.ok) { await response.body?.cancel(); fail('HTTP_REFUSED'); }
  const rows = await boundedJson(response);
  if (!Array.isArray(rows) || rows.length !== 1) fail('RESPONSE_SHAPE');
  const row = object(rows[0], ['guard_catalogue', 'catalogue_detail', 'schema_projection']);
  const detail = fields(row.catalogue_detail, {
    observed_at: value => { text(value, 64); if (!Number.isFinite(Date.parse(value))) fail('RESPONSE_SHAPE'); return value; },
    transaction_read_only: value => { if (value !== 'on') fail('READ_ONLY_NOT_CONFIRMED'); return value; },
    server_version_num: value => { if (!/^\d{5,7}$/.test(value)) fail('RESPONSE_SHAPE'); return value; },
    search_path_md5: hash,
    scope: value => { if (value !== 'D2_CATALOGUE_METADATA_AND_HASHES_ONLY') fail('RESPONSE_SHAPE'); return value; },
    aggregate,
    columns: value => list(value, 10000, item => fields(item, {
      relation: text, position: integer, name: text, type: text, not_null: bool, default_md5: maybeHash, row_md5: hash,
    })),
    constraints: value => list(value, 10000, item => fields(item, {
      relation: text, name: text, type: text,
      referenced_relation: value => value === null ? null : text(value), definition_md5: hash, row_md5: hash,
    })),
    functions: value => list(value, 10000, item => fields(item, {
      schema: text, signature: text, body_md5: hash, definition_md5: hash, acl_md5: hash, row_md5: hash,
    })),
    triggers: value => list(value, 2000, item => fields(item, {
      relation: text, name: text, enabled: text, function: text, definition_md5: hash, function_definition_md5: hash, row_md5: hash,
    })),
  });
  const projected = fields(row.schema_projection, {
    scope: value => { if (value !== 'D2_SCHEMA_EXPECTED_CONNECT_FK_PROJECTION_ONLY') fail('RESPONSE_SHAPE'); return value; },
    transaction_read_only: value => { if (value !== 'on') fail('READ_ONLY_NOT_CONFIRMED'); return value; },
    expected_source_migration: value => { if (value !== '20261001201055_reserver_remboursement_connect_avant_transfert.sql') fail('RESPONSE_SHAPE'); return value; },
    baseline_schema: hash, current_schema: hash, expected_fk_shapes_match: bool,
    schema_without_three_expected_fk: maybeHash, projection_matches_baseline: bool,
    expected_fk: value => list(value, 3, item => fields(item, {
      name: text, column: text, referenced_relation: text, found: bool, shape_matches: bool, definition_md5: maybeHash,
    })),
  });
  const original = aggregate(row.guard_catalogue);
  if (JSON.stringify(original) !== JSON.stringify(detail.aggregate)
    || projected.current_schema !== original.schema
    || projected.baseline_schema !== catalogueD.schema
    || projected.expected_fk.length !== 3
    || projected.projection_matches_baseline !== (projected.schema_without_three_expected_fk === catalogueD.schema)
    || projected.expected_fk_shapes_match !== projected.expected_fk.every(item => item.found && item.shape_matches)) fail('CATALOGUE_CONSISTENCY');
  receipt.observed = original;
  receipt.schemaHypothesis = projected.projection_matches_baseline ? 'THREE_EXPECTED_CONNECT_FK_EXPLAIN_SCHEMA_HASH' : 'SCHEMA_NOT_EXPLAINED';
  receipt.drift = Object.keys(receipt.expected).filter(key => receipt.expected[key] !== original[key]);
  receipt.counts = Object.fromEntries(['columns', 'constraints', 'functions', 'triggers'].map(key => [key, detail[key].length]));
  receipt.status = 'COLLECTED_NON_QUALIFIE';
  // Seules les structures explicitement validées ci-dessus sont écrites, jamais la réponse brute.
  mkdirSync(output, { recursive: true });
  writeFileSync(resolve(output, 'catalogue-detail.json'), JSON.stringify({ ...receipt, catalogue: detail, schemaProjection: projected }, null, 2) + '\n');
} catch (error) {
  const known = ['CONFIGURATION', 'QUERY_CONTRACT', 'HTTP_REFUSED', 'RESPONSE_SHAPE', 'RESPONSE_TOO_LARGE', 'READ_ONLY_NOT_CONFIRMED', 'CATALOGUE_CONSISTENCY'];
  receipt.status = known.includes(error?.message) ? error.message : 'TRANSPORT_OR_PARSE_FAILURE';
  process.exitCode = 1;
}
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify({ status: receipt.status, qualification: receipt.qualification, schemaHypothesis: receipt.schemaHypothesis, counts: receipt.counts }));

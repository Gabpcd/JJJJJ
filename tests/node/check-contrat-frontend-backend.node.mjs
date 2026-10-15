import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const checker = join(root, 'scripts/check-contrat-frontend-backend.mjs');
const helperPath = 'src/lib/signatureSmsStagingAdmission.ts';
const sqlPath = 'scripts/ci/sms-signature-staging.sql';
const helper = readFileSync(join(root, helperPath), 'utf8');
const sql = readFileSync(join(root, sqlPath), 'utf8');
const rpc = 'fn_admission_otp_signature_recette';

// Run the real CLI against a disposable miniature checkout. The empty or
// explicit introspection file prevents all Management API/network requests.
function checkFixture({ frontend = helper, backend = sql, extra = '', production = [], migration = '' } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-contract-staging-'));
  try {
    for (const path of ['src/lib', 'scripts/ci', 'supabase/migrations']) mkdirSync(join(dir, path), { recursive: true });
    writeFileSync(join(dir, helperPath), frontend);
    if (backend !== null) writeFileSync(join(dir, sqlPath), backend);
    if (extra) writeFileSync(join(dir, 'src/unguarded.ts'), extra);
    if (migration) writeFileSync(join(dir, 'supabase/migrations/fixture.sql'), migration);
    const introspection = join(dir, 'introspection.json');
    writeFileSync(introspection, JSON.stringify({ functions: production, buckets: [], edgeFunctions: [] }));
    const result = spawnSync(process.execPath, [checker], {
      cwd: dir,
      env: { CONTRAT_INTROSPECTION_FILE: introspection },
      encoding: 'utf8',
      timeout: 10_000,
    });
    assert.equal(result.error, undefined);
    return { status: result.status, output: result.stdout + result.stderr };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('recognizes only the reviewed staging helper and versioned supplement, without claiming deployment', () => {
  const result = checkFixture();
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /appel et supplément SQL versionnés vérifiés, déploiement non attesté/);
});

test('missing staging SQL stays a broken frontend/backend connection', () => {
  const result = checkFixture({ backend: null });
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, new RegExp(rpc));
});

test('removing the frontend project guard invalidates the pinned reference', () => {
  assert.ok(helper.includes('url !== STAGING_URL || '));
  const result = checkFixture({ frontend: helper.replace('url !== STAGING_URL || ', '') });
  assert.equal(result.status, 1, result.output);
});

test('changing the SQL project preflight invalidates the pinned backend source', () => {
  assert.ok(sql.includes('https://mejpriaetwgtcstbgfid.supabase.co'));
  const result = checkFixture({ backend: sql.replace('https://mejpriaetwgtcstbgfid.supabase.co', 'https://other-project.supabase.co') });
  assert.equal(result.status, 1, result.output);
});

test('the same RPC in another file is rejected even if production reports that name', () => {
  const result = checkFixture({ extra: `client.rpc('${rpc}', {});`, production: [rpc] });
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /src\/unguarded\.ts/);
});

test('a production report cannot hide an altered staging helper', () => {
  const result = checkFixture({ frontend: helper.replace('url !== STAGING_URL || ', ''), production: [rpc] });
  assert.equal(result.status, 1, result.output);
});

test('ordinary production and migration RPC resolution remains supported', () => {
  const result = checkFixture({
    extra: "client.rpc('fn_production_fixture', {}); client.rpc('fn_migration_fixture', {});",
    production: ['fn_production_fixture'],
    migration: 'CREATE FUNCTION public.fn_migration_fixture() RETURNS void LANGUAGE sql AS $$ SELECT NULL $$;',
  });
  assert.equal(result.status, 0, result.output);
});

for (const [kind, extra, missing] of [
  ['RPC', "client.rpc('fn_backend_unknown', {});", 'fn_backend_unknown'],
  ['Edge function', `client.functions.invoke('${rpc}', {});`, rpc],
  ['storage bucket', `client.storage.from('${rpc}');`, rpc],
]) {
  test(`unknown ${kind} remains a hard failure alongside the staging reference`, () => {
    const result = checkFixture({ extra });
    assert.equal(result.status, 1, result.output);
    assert.match(result.output, new RegExp(missing));
  });
}

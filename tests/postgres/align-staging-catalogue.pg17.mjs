import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { assets, transaction } from '../../scripts/ci/align-staging-107.mjs';
import { tablesD } from '../../scripts/ci/candidatures-fixture-contract.mjs';

// Exercise the declaration and SELECT emitted by the real deployment script,
// without executing its mutations or accessing any remote database.
test('alignment catalogue compiles on PG17 while the historical record alias fails', () => {
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'paiements_concurrence');
  const c = JSON.parse(readFileSync(new URL('../../scripts/ci/align-staging-107.contract.json', import.meta.url)));
  const root = new URL('../../', import.meta.url).pathname;
  const sql = transaction(c, assets(root, c), false);
  const declarations = [...sql.matchAll(/DO \$align_before\$ (DECLARE (\w+) record;) BEGIN/g)];
  const assignments = [...sql.matchAll(/SELECT \* INTO \w+ FROM \([\s\S]*?\) q;/g)];
  assert.equal(declarations.length, 1);
  assert.equal(assignments.length, 1);
  const [, declaration, variable] = declarations[0];
  const assignment = assignments[0][0];
  const block = `DO $probe$ ${declaration} BEGIN
${assignment}
IF ${variable}.schema !~ '^[a-f0-9]{32}$'
 OR ${variable}.fonctions !~ '^[a-f0-9]{32}$'
 OR ${variable}.triggers !~ '^[a-f0-9]{32}$'
 OR ${variable}.crons_actifs <> 0 OR ${variable}.audit_fk <> 0
 THEN RAISE EXCEPTION 'CATALOGUE_PROBE_FAILED'; END IF;
END $probe$;`;
  const setup = `BEGIN; SET LOCAL search_path=public,pg_catalog;
SET LOCAL statement_timeout='5s'; SET LOCAL plpgsql.variable_conflict=error;
CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS cron;
${tablesD.map(t => `CREATE TABLE IF NOT EXISTS ${t}(id uuid PRIMARY KEY);`).join('\n')}
CREATE TABLE IF NOT EXISTS cron.job(active boolean);
CREATE TABLE public.align_catalogue_probe(id integer PRIMARY KEY);
CREATE FUNCTION public.align_catalogue_probe() RETURNS trigger LANGUAGE plpgsql
 AS $fn$ BEGIN RETURN NEW; END $fn$;
CREATE TRIGGER align_catalogue_probe BEFORE INSERT ON public.soignants
 FOR EACH ROW EXECUTE FUNCTION public.align_catalogue_probe();`;
  const run = input => spawnSync('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], {
    input, encoding: 'utf8', timeout: 15000,
    env: { PATH: process.env.PATH, PGHOST: '127.0.0.1', PGPORT: '5432',
      PGDATABASE: 'paiements_concurrence', PGUSER: 'postgres',
      PGPASSWORD: 'fixture-ci-ephemere', PGCONNECT_TIMEOUT: '5' },
  });
  const historical = block.replaceAll(variable, 'c');
  const red = run(`${setup}\n${historical}\nROLLBACK;`);
  assert.ifError(red.error);
  assert.notEqual(red.status, 0);
  assert.match(red.stderr, /55000/, 'the historical record shadows pg_constraint alias c');
  const green = run(`${setup}\n${block}
SELECT current_setting('server_version_num')::int/10000;
ROLLBACK;
SELECT to_regclass('public.align_catalogue_probe') IS NULL
 AND to_regprocedure('public.align_catalogue_probe()') IS NULL;`);
  assert.ifError(green.error);
  assert.equal(green.status, 0, green.stderr);
  assert.deepEqual(green.stdout.trim().split('\n'), ['17', 't']);
});

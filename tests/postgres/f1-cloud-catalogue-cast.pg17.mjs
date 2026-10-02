import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { catalogueSqlF1 } from '../../scripts/ci/f1-cloud-sql.mjs';

// Run in the existing paiements-concurrence CI job, against its disposable PG17.
// This test never prepares F1 actors, calls a provider or invokes its probe trigger.
test('real F1 trigger catalogue compiles and fingerprints O/D/R/A under PostgreSQL 17', () => {
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'paiements_concurrence');
  const run = input => spawnSync('psql', ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], {
    input, encoding: 'utf8', timeout: 15000,
    env: { PATH: process.env.PATH, PGHOST: '127.0.0.1', PGPORT: '5432',
      PGDATABASE: 'paiements_concurrence', PGUSER: 'postgres',
      PGPASSWORD: 'fixture-ci-ephemere', PGCONNECT_TIMEOUT: '5' },
  });
  const matches = [...catalogueSqlF1().matchAll(/'triggers', \((SELECT[\s\S]*?)\),\n    'columns'/g)];
  assert.equal(matches.length, 1, 'select the actual trigger subquery, without recreating its expression');
  const query = matches[0][1];
  const setup = `BEGIN; SET LOCAL statement_timeout='5s';
CREATE TABLE public.f1_catalogue_cast_probe(id integer);
CREATE FUNCTION public.f1_catalogue_cast_probe() RETURNS trigger LANGUAGE plpgsql
  AS $probe$ BEGIN RETURN NEW; END; $probe$;
CREATE TRIGGER f1_catalogue_cast_probe BEFORE INSERT ON public.f1_catalogue_cast_probe
  FOR EACH ROW EXECUTE FUNCTION public.f1_catalogue_cast_probe();`;

  // Retain the historical red control: removing the cast must produce 42725.
  const historical = query.replaceAll('t.tgenabled::text', 't.tgenabled');
  const red = run(`${setup}\nSELECT (${historical});\nROLLBACK;`);
  assert.ifError(red.error);
  assert.notEqual(red.status, 0);
  assert.match(red.stderr, /42725/, 'the historical SQL fails on ambiguous text || "char"');

  const green = run(`${setup}
SELECT current_setting('server_version_num')::int/10000;
SELECT (${query});
ALTER TABLE public.f1_catalogue_cast_probe DISABLE TRIGGER f1_catalogue_cast_probe;
SELECT (${query});
ALTER TABLE public.f1_catalogue_cast_probe ENABLE REPLICA TRIGGER f1_catalogue_cast_probe;
SELECT (${query});
ALTER TABLE public.f1_catalogue_cast_probe ENABLE ALWAYS TRIGGER f1_catalogue_cast_probe;
SELECT (${query});
ALTER TABLE public.f1_catalogue_cast_probe ENABLE TRIGGER f1_catalogue_cast_probe;
SELECT (${query});
ROLLBACK;
SELECT to_regclass('public.f1_catalogue_cast_probe') IS NULL
  AND to_regprocedure('public.f1_catalogue_cast_probe()') IS NULL;`);
  assert.ifError(green.error);
  assert.equal(green.status, 0, green.stderr);
  const [version, origin, disabled, replica, always, restored, absent, ...extra] = green.stdout.trim().split('\n');
  assert.equal(version, '17');
  for (const digest of [origin, disabled, replica, always]) assert.match(digest, /^[a-f0-9]{32}$/);
  assert.equal(new Set([origin, disabled, replica, always]).size, 4, 'enabled state must remain fingerprinted');
  assert.equal(restored, origin);
  assert.equal(absent, 't', 'rollback removes the entire probe');
  assert.deepEqual(extra, []);
});

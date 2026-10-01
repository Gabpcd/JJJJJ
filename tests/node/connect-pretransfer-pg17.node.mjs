import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const runner = 'scripts/ci/connect-pretransfer-pg17.py';
const permitted = {
  PATH: process.env.PATH,
  TMPDIR: process.env.TMPDIR || '/tmp',
  JOLENE_CONNECT_WITNESS: 'CI_EPHEMERE',
  PGHOST: '127.0.0.1', PGPORT: '54329',
  PGDATABASE: 'connect_pretransfer_temoin', PGUSER: 'postgres',
};
// Chaque cas doit s'arrêter AVANT de lire un fichier de schéma ou d'appeler
// psql. Aucun cas positif ne s'exécute ici : seul le job isolé le fera.
for (const [label, delta] of [
  ['autorisation absente', { JOLENE_CONNECT_WITNESS: '' }],
  ['adresse distante', { PGHOST: 'db.exemple.invalid' }],
  ['alias localhost non admis', { PGHOST: 'localhost' }],
  ['autre port', { PGPORT: '5432' }],
  ['base générique', { PGDATABASE: 'postgres' }],
  ['autre rôle', { PGUSER: 'service_role' }],
  ['PGHOSTADDR substitué', { PGHOSTADDR: '192.0.2.1' }],
  ['profil libpq substitué', { PGSERVICE: 'interdit' }],
  ['fichier de profil substitué', { PGSERVICEFILE: '/interdit' }],
  ['options SQL injectées', { PGOPTIONS: '-c search_path=public' }],
]) test(`destination refusée : ${label}`, () => {
  const result = spawnSync('python3', [runner], {
    env: { ...permitted, ...delta }, encoding: 'utf8', timeout: 2000,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr.trim(), 'CONNECT_WITNESS_DESTINATION_REFUSED');
});

test('le corps relu est celui encapsulé dans la migration entière', () => {
  const fixture = readFileSync('tests/fixtures/connect-pretransfer-schema-candidate.sql', 'utf8');
  const migration = readFileSync('supabase/migrations/20261001171439_reserver_remboursement_connect_avant_transfert.sql', 'utf8');
  assert.ok(migration.includes(fixture.slice(fixture.indexOf('CREATE TABLE'))));
  assert.equal(migration.match(/\nBEGIN;\n/g)?.length, 1);
  assert.ok(migration.endsWith('COMMIT;\n'));
});

test('la barrière fermée est dans le même COMMIT que le moteur', () => {
  const source = readFileSync('tests/fixtures/connect-pretransfer-release-gate-candidate.sql', 'utf8');
  assert.equal(source.match(/\nBEGIN;\n/g)?.length, 1);
  const body = source.replace('\nBEGIN;\n', '\n').replace(/COMMIT;\n$/, '');
  const migration = readFileSync('supabase/migrations/20261001171439_reserver_remboursement_connect_avant_transfert.sql', 'utf8');
  assert.ok(migration.includes(body));
  assert.ok(migration.indexOf('$postflight$;') < migration.indexOf('$barrier_preflight$;'));
  assert.ok(migration.includes("VALUES('CONNECT_PRETRANSFER_V1',false)"));
});


test('le cadre de lecture exact vient après la barrière, dans le COMMIT unique', () => {
  const source = readFileSync('tests/fixtures/connect-pretransfer-suivi-installation.sql', 'utf8');
  const migration = readFileSync('supabase/migrations/20261001171439_reserver_remboursement_connect_avant_transfert.sql', 'utf8');
  assert.ok(migration.includes(source));
  const barrierEnd = migration.indexOf('$barrier_installation$;');
  const suiviStart = migration.indexOf('$suivi_preflight$;');
  assert.ok(barrierEnd >= 0 && suiviStart > barrierEnd);
  assert.equal(migration.match(/\nBEGIN;\n/g)?.length, 1);
  assert.equal(migration.match(/\nCOMMIT;\n/g)?.length, 1);
});

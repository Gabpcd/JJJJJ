import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { parse } from 'yaml';
import { validateMigrationBase } from '../../scripts/ci/check-staging-migration-base.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const workflow = parse(readFileSync(path.join(root, '.github/workflows/validate-pr.yml'), 'utf8'));
const sqlJob = workflow.jobs['sql-transaction'];
const bootstrap = sqlJob.steps.find(step => step.name === 'Synchroniser le schéma main vers le staging').run;
const rollback = sqlJob.steps.find(step => step.name === 'Exécuter les migrations ajoutées et les régressions SQL sans persister').run;
const main = '20260901000000_main.sql', pending = '20260902000000_pending_main.sql', proposed = '20260903000000_unapproved_contract.sql';
const baseInput = { baseFiles: [main, pending], remoteRows: [{ version: main.slice(0, 14) }],
  changes: [{ status: 'A', path: `supabase/migrations/${proposed}` }] };

test('accepte un staging en retard sur main sans y inclure la migration PR', () => {
  assert.deepEqual(validateMigrationBase(baseInput), { baseCount: 2, remoteCount: 1, addedCount: 1 });
  assert.deepEqual(validateMigrationBase({ ...baseInput, remoteRows: [] }), { baseCount: 2, remoteCount: 0, addedCount: 1 });
});
test('refuse les migrations PR déjà appliquées et celles d’un main plus récent', () => {
  for (const version of [proposed.slice(0, 14), '20260904000000']) {
    assert.throws(() => validateMigrationBase({ ...baseInput, remoteRows: [{ version }] }), /hors de la base main/);
  }
});
test('refuse modification, suppression et renommage de l’historique, sans faux vert', () => {
  for (const status of ['M', 'D', 'R', 'T']) {
    assert.throws(() => validateMigrationBase({ ...baseInput, changes: [{ status, path: `supabase/migrations/${main}` }] }), /migration historique/);
  }
});
test('refuse un registre illisible et les collisions de version ou chemins ambigus', () => {
  for (const remoteRows of [null, {}, { error: 'private message' }, [null], [{ version: 20260901000000 }], [{ version: '../main' }]]) {
    assert.throws(() => validateMigrationBase({ ...baseInput, remoteRows }), /registre staging invalide/);
  }
  for (const changes of [
    [{ status: 'A', path: `supabase/migrations/${main.slice(0, 14)}_duplicate.sql` }],
    [...baseInput.changes, { status: 'A', path: `supabase/migrations/${proposed.slice(0, 14)}_duplicate.sql` }],
    [{ status: 'A', path: `supabase/migrations/nested/${proposed}` }],
  ]) assert.throws(() => validateMigrationBase({ ...baseInput, changes }), /ambigu/);
});

// Exécute les vrais blocs shell du workflow dans un petit dépôt Git, avec les
// deux transports externes remplacés. Aucun secret, réseau ni PostgreSQL réel.
function fixture(t, options = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'jolene-staging-base-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const repo = path.join(dir, 'repo'), bin = path.join(dir, 'bin'), runner = path.join(dir, 'runner');
  for (const name of [repo, bin, runner]) mkdirSync(name);
  function write(name, text) {
    const target = path.join(repo, name); mkdirSync(path.dirname(target), { recursive: true }); writeFileSync(target, text);
  }
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '-q'); git('config', 'user.email', 'fixture@example.invalid'); git('config', 'user.name', 'Fixture');
  write(`supabase/migrations/${main}`, 'CREATE TABLE public.existing_main(id int);\n');
  write(`supabase/migrations/${pending}`, 'CREATE TABLE public.pending_main(id int);\n');
  write('supabase/config.toml', 'project_id = "fixture"\n');
  write('scripts/ci/check-staging-migration-base.mjs', readFileSync(path.join(root, 'scripts/ci/check-staging-migration-base.mjs'), 'utf8'));
  write('scripts/ci/reconcile-staging-litige-base.mjs', readFileSync(path.join(root, 'scripts/ci/reconcile-staging-litige-base.mjs'), 'utf8'));
  git('add', '.'); git('commit', '-qm', 'main fixture'); const baseSha = git('rev-parse', 'HEAD');
  write(`supabase/migrations/${proposed}`, 'CREATE TABLE public.unapproved_contract(id int);\n');
  if (options.modifyHistory) write(`supabase/migrations/${main}`, 'CREATE TABLE public.changed_history(id int);\n');
  // La liste de suites vient du workflow : aucune suite manquante n'est ignorée.
  const suites = [...rollback.matchAll(/^\s+(tests\/[^\s]+\.sql)$/gm)].map(match => match[1]);
  assert.ok(suites.length > 10);
  for (const name of suites) write(name, "BEGIN;\nSELECT 'fixture assertion';\nROLLBACK;\n");
  git('add', '.'); git('commit', '-qm', 'PR fixture');
  const stateFile = path.join(dir, 'state.json');
  writeFileSync(stateFile, JSON.stringify({ registry: options.registry ?? baseInput.remoteRows, requests: [], cli: [], persisted: [], transactions: [] }));
  const transport = `#!/usr/bin/env node
const fs = require('node:fs'), path = require('node:path');
const stateFile = process.env.FIXTURE_STATE, state = JSON.parse(fs.readFileSync(stateFile));
const args = process.argv.slice(2), get = flag => args[args.indexOf(flag) + 1];
if (path.basename(process.argv[1]) === 'supabase') {
  const dir = get('--workdir');
  state.cli.push(args.slice(0, 2).join(' '));
  if (args[0] === 'db' && args[1] === 'push') {
    const migrationDir = path.join(dir, 'supabase/migrations');
    for (const name of fs.readdirSync(migrationDir).filter(n => n.endsWith('.sql')).sort()) {
      const version = name.slice(0, 14);
      if (!state.registry.some(row => row.version === version)) {
        state.persisted.push({ name, sql: fs.readFileSync(path.join(migrationDir, name), 'utf8') });
        state.registry.push({ version });
      }
    }
  }
  fs.writeFileSync(stateFile, JSON.stringify(state));
} else {
  const payload = args.includes('--data-binary') ? fs.readFileSync(get('--data-binary').slice(1), 'utf8') : get('--data');
  const query = JSON.parse(payload).query;
  state.requests.push({ url: args.find(arg => arg.startsWith('https:')), query });
  const registry = query.startsWith('SELECT version FROM supabase_migrations');
  const code = registry ? process.env.FIXTURE_REGISTRY_STATUS || '200' : '200';
  if (query.includes('unapproved_contract')) state.transactions.push(query);
  fs.writeFileSync(get('-o'), JSON.stringify(registry ? state.registry : []));
  fs.writeFileSync(stateFile, JSON.stringify(state)); process.stdout.write(code);
}
`;
  for (const name of ['curl', 'supabase']) { writeFileSync(path.join(bin, name), transport); chmodSync(path.join(bin, name), 0o755); }
  const env = { ...process.env, BASE_SHA: baseSha, RUNNER_TEMP: runner, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
    STAGING_SUPABASE_ACCESS_TOKEN: 'fake-token-never-log', STAGING_SUPABASE_PROJECT_REF: 'mejpriaetwgtcstbgfid',
    STAGING_SUPABASE_DB_PASSWORD: 'fake-password-never-log', FIXTURE_STATE: stateFile,
    FIXTURE_REGISTRY_STATUS: String(options.registryStatus ?? 200) };
  function run(script, extraEnv = {}) {
    // macOS fournit Bash 3 ; l'équivalent de mapfile permet d'exécuter le même
    // bloc prévu pour Bash 5 sur le runner, sans changer ses commandes SQL.
    const compat = 'if ! type mapfile >/dev/null 2>&1; then mapfile() { shift; local name="$1" line; eval "$name=()"; while IFS= read -r line; do eval "$name+=(\\"\\$line\\")"; done; }; fi\n';
    // L'étape existante emploie /tmp ; isoler seulement ses fichiers de sortie.
    const isolated = script.replaceAll('/tmp/jolene-', `${runner}/jolene-`);
    const result = spawnSync('bash', ['-c', compat + isolated], { cwd: repo, env: { ...env, ...extraEnv }, encoding: 'utf8' });
    assert.ok(!`${result.stdout}${result.stderr}`.includes(env.STAGING_SUPABASE_ACCESS_TOKEN));
    assert.ok(!`${result.stdout}${result.stderr}`.includes(env.STAGING_SUPABASE_DB_PASSWORD));
    return result;
  }
  return { run, state: () => JSON.parse(readFileSync(stateFile)), repo, runner, env, git };
}

test('workflow simulé : main seul persiste, CREATE TABLE de PR envoyé une fois sous rollback', t => {
  const f = fixture(t);
  const boot = f.run(bootstrap); assert.equal(boot.status, 0, boot.stderr + boot.stdout);
  let state = f.state();
  assert.deepEqual(state.persisted.map(item => item.name), [pending]);
  assert.deepEqual(state.registry.map(item => item.version), [main.slice(0, 14), pending.slice(0, 14)]);
  assert.ok(state.requests[0].query.startsWith('SELECT version'));
  assert.ok(state.requests[1].query.startsWith('CREATE EXTENSION IF NOT EXISTS pg_cron'));
  assert.ok(!JSON.stringify(state.persisted).includes('unapproved_contract'));
  const testSql = f.run(rollback); assert.equal(testSql.status, 0, testSql.stderr + testSql.stdout);
  state = f.state(); assert.equal(state.transactions.length, 1);
  const sql = state.transactions[0];
  assert.ok(sql.startsWith('BEGIN;\n')); assert.ok(sql.endsWith('ROLLBACK;\n'));
  assert.equal(sql.match(/CREATE TABLE public\.unapproved_contract/g)?.length, 1);
  assert.ok(!sql.includes('CREATE TABLE public.pending_main')); assert.ok(!sql.includes('COMMIT;'));
  assert.ok(sql.includes('SAVEPOINT jolene_sql_test_1;')); assert.ok(sql.includes('ROLLBACK TO SAVEPOINT jolene_sql_test_1;'));
  assert.deepEqual(state.persisted.map(item => item.name), [pending]);
  assert.ok(state.requests.every(request => request.url === 'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query'));
});
test('workflow : staging avec une version PR ou main plus récent échoue avant toute DDL/CLI', t => {
  for (const version of [proposed.slice(0, 14), '20260904000000']) {
    const f = fixture(t, { registry: [...baseInput.remoteRows, { version }] });
    const result = f.run(bootstrap); assert.notEqual(result.status, 0); assert.match(result.stderr, /hors de la base main/);
    const state = f.state(); assert.equal(state.requests.length, 1); assert.deepEqual(state.cli, []); assert.deepEqual(state.persisted, []);
  }
});
test('workflow : historique modifié ou registre invalide n’applique rien', t => {
  for (const options of [{ modifyHistory: true }, { registry: { error: 'private server content' } }, { registryStatus: 503 }]) {
    const f = fixture(t, options); const result = f.run(bootstrap); assert.notEqual(result.status, 0);
    const state = f.state(); assert.equal(state.requests.length, 1); assert.deepEqual(state.cli, []); assert.deepEqual(state.persisted, []);
    assert.ok(!`${result.stdout}${result.stderr}`.includes('private server content'));
  }
});
test('workflow : aucune requête avec cible production ou accès manquant', t => {
  const f = fixture(t);
  for (const env of [{ STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' }, { STAGING_SUPABASE_ACCESS_TOKEN: '' }]) {
    const result = f.run(bootstrap, env); assert.notEqual(result.status, 0); assert.equal(f.state().requests.length, 0);
  }
});
test('un fichier PR recopié dans le worktree main est refusé même sans version distante', t => {
  const f = fixture(t), baseDir = path.join(f.runner, 'tampered-base');
  f.git('worktree', 'add', '--detach', baseDir, f.env.BASE_SHA);
  copyFileSync(path.join(f.repo, 'supabase/migrations', proposed), path.join(baseDir, 'supabase/migrations', proposed));
  const registry = path.join(f.runner, 'registry.json'); writeFileSync(registry, JSON.stringify(baseInput.remoteRows));
  const result = spawnSync(process.execPath, ['scripts/ci/check-staging-migration-base.mjs', baseDir, registry], { cwd: f.repo, env: f.env, encoding: 'utf8' });
  assert.notEqual(result.status, 0); assert.match(result.stderr, /worktree de base ont été modifiées/);
});
test('workflow conserve le verrou staging et exécute ces simulations en CI', () => {
  assert.deepEqual(sqlJob.concurrency, { group: 'jolene-supabase-staging-writes', 'cancel-in-progress': false });
  assert.ok(workflow.jobs['typecheck-and-build'].steps.some(step => step.run === 'node --test tests/node/staging-migration-base.node.mjs tests/node/staging-litige-reconciliation.node.mjs'));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parse } from 'yaml';
import { REVIEWED_INSTALLATION as reviewed, statementsMatch, checkScope, checkInstallation, checkContext, inspect, inspectionSql } from '../../scripts/ci/paiements-staging-installed.mjs';
import { REVIEWED_CATALOGUE } from '../../scripts/ci/connect-test-fixture-rollback.mjs';

const sources = Object.fromEntries(reviewed.migrations.map(([name]) => [name, readFileSync(new URL(`../../supabase/migrations/${name}`, import.meta.url), 'utf8')]));
const changes = reviewed.migrations.map(([name]) => ['A', `supabase/migrations/${name}`]);
const base = ['20261006144619'];
const env = { GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'pull_request', GITHUB_REPOSITORY: 'Gabpcd/JJJJJ',
  PR_HEAD_REPOSITORY: 'Gabpcd/JJJJJ', STAGING_SUPABASE_PROJECT_REF: 'mejpriaetwgtcstbgfid',
  BASE_SHA: 'a'.repeat(40), CANDIDATE_SHA: 'b'.repeat(40), STAGING_SUPABASE_ACCESS_TOKEN: 'fixture-never-real-token' };

// Independent SQL tokenizer for the fixture response. Keep every byte inside
// strings, comments and dollar bodies; only top-level delimiters split it.
function splitStatements(source) {
  const result = []; let start = 0, i = 0, quote = null;
  while (i < source.length) {
    if (quote) {
      if (source.startsWith(quote, i)) {
        if (quote.length === 1 && source[i + 1] === quote) { i += 2; continue; }
        i += quote.length; quote = null;
      } else i++;
      continue;
    }
    if (source.startsWith('--', i)) { const end = source.indexOf('\n', i); i = end < 0 ? source.length : end + 1; continue; }
    if (source.startsWith('/*', i)) { const end = source.indexOf('*/', i + 2); assert.ok(end >= 0); i = end + 2; continue; }
    const dollar = /^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/.exec(source.slice(i));
    if (dollar) { quote = dollar[0]; i += quote.length; continue; }
    if (source[i] === "'" || source[i] === '"') { quote = source[i++]; continue; }
    if (source[i] === ';') { const s = source.slice(start, i).trim(); if (s) result.push(s); start = i + 1; }
    i++;
  }
  const rest = source.slice(start).trim(); if (rest) result.push(rest);
  return result;
}
function snapshot() {
  return [{ installation: { readOnly: true,
    versions: [...base, ...reviewed.migrations.map(([n]) => n.slice(0, 14))].sort(),
    migrations: reviewed.migrations.map(([n]) => ({ version: n.slice(0, 14), name: n.slice(15, -4), statements: splitStatements(sources[n]) })),
    catalogue: { ...reviewed.catalogue, commissionHelper: 'c736c66d76001b64ba425484f77c6ea2',
      queuedRequests: 0, activeCrons: 0, runningCrons: 0, generationUrlAbsent: true, supportStagingExact: true },
    gateClosed: true, capacitiesClosed: true,
  } }];
}

test('les sept sources reconnues totalisent exactement 90 statements ; le catalogue est commun au témoin seed', () => {
  assert.equal(checkScope(changes, sources), true);
  assert.equal(snapshot()[0].installation.migrations.reduce((sum, r) => sum + r.statements.length, 0), 90);
  assert.equal(checkInstallation(snapshot(), base, sources), 'installed');
  assert.deepEqual(reviewed.catalogue, REVIEWED_CATALOGUE);
});
test('comparaison exacte des corps et de l’ordre, y compris commentaires ; aucun hash de registre seul', () => {
  assert.ok(statementsMatch("BEGIN;\nDO $$BEGIN\n SELECT 'a; b';\nEND$$; COMMIT;\n", ['BEGIN', "DO $$BEGIN\n SELECT 'a; b';\nEND$$", 'COMMIT']));
  for (const mutate of [
    s => { s.migrations[0].statements[2] = s.migrations[0].statements[2].replace('EUR', 'USD'); },
    s => { s.migrations[0].statements.reverse(); },
    s => { s.migrations[1].statements.pop(); },
    s => { s.migrations[1].name += '_other'; },
    s => { s.migrations[1].statements[0] += '\n'; },
  ]) {
    const rows = snapshot(); mutate(rows[0].installation);
    assert.throws(() => checkInstallation(rows, base, sources), /STATEMENTS_CHANGED/);
  }
});
test('historique, huitième migration ou sources modifiées refusés avant tout appel', () => {
  for (const scope of [changes.slice(1), [...changes, ['A', 'supabase/migrations/20261017120000_other.sql']],
    changes.map((r, i) => i === 0 ? ['M', r[1]] : r)]) assert.throws(() => checkScope(scope, sources), /EXACT_SEVEN_REQUIRED/);
  assert.throws(() => checkScope(changes, { ...sources, [reviewed.migrations[0][0]]: sources[reviewed.migrations[0][0]] + '\n' }), /SOURCE_CHANGED/);
  assert.equal(checkScope([['A', 'supabase/migrations/20261017120000_other.sql']], {}), false);
});
test('une installation partielle, un main manquant ou un registre étranger ne permet aucun skip', () => {
  for (const mutate of [
    s => { s.migrations.pop(); s.versions.pop(); },
    s => { s.versions.shift(); }, s => { s.versions.push('20261017120000'); },
    s => { s.versions.push(s.versions[0]); }, s => { s.migrations = null; },
    s => { s.readOnly = false; },
  ]) { const rows = snapshot(); mutate(rows[0].installation); assert.throws(() => checkInstallation(rows, base, sources)); }
});
test('catalogue, droits via empreinte et canaux fermés sont exigés à chaque lecture', () => {
  for (const mutate of [
    ...['routines', 'triggers', 'columns', 'commissionHelper'].map(k => s => { s.catalogue[k] = '0'.repeat(32); }),
    ...['queuedRequests', 'activeCrons', 'runningCrons'].map(k => s => { s.catalogue[k] = 1; }),
    s => { s.catalogue.generationUrlAbsent = false; }, s => { s.catalogue.supportStagingExact = false; },
    s => { s.gateClosed = false; }, s => { s.capacitiesClosed = false; },
  ]) { const rows = snapshot(); mutate(rows[0].installation); assert.throws(() => checkInstallation(rows, base, sources), /CATALOGUE_OR_CHANNEL_DRIFT/); }
});
test('absence complète conserve le bootstrap normal, disparition après reconnaissance refuse', () => {
  const rows = snapshot(); rows[0].installation.versions = base; rows[0].installation.migrations = [];
  assert.equal(checkInstallation(rows, base, sources), 'empty');
  assert.throws(() => checkInstallation(rows, base, sources, true), /INSTALLATION_DISAPPEARED/);
});
test('PROD, fork, mauvais SHA ou contexte non CI refusés ; transport uniquement SELECT staging', async () => {
  for (const patch of [{ STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' }, { PR_HEAD_REPOSITORY: 'other/repo' },
    { GITHUB_ACTIONS: 'false' }, { GITHUB_EVENT_NAME: 'push' }, { CANDIDATE_SHA: 'c'.repeat(40) }, { STAGING_SUPABASE_ACCESS_TOKEN: '' }]) {
    assert.throws(() => checkContext({ ...env, ...patch }, env.CANDIDATE_SHA), /CONTEXT/);
  }
  let requests = 0;
  const args = { env, changes, sources, baseVersions: base, head: env.CANDIDATE_SHA,
    fetcher: async (url, options) => {
      requests++;
      assert.equal(url, 'https://api.supabase.com/v1/projects/mejpriaetwgtcstbgfid/database/query');
      assert.equal(options.redirect, 'error');
      assert.equal(JSON.parse(options.body).query, inspectionSql());
      assert.ok(inspectionSql().startsWith('BEGIN READ ONLY;'));
      assert.ok(inspectionSql().endsWith('ROLLBACK;'));
      assert.doesNotMatch(inspectionSql(), /\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|COMMIT)\b/);
      return { ok: true, redirected: false, json: async () => snapshot() };
    } };
  assert.equal(await inspect(args), 'installed'); assert.equal(requests, 1);
  assert.equal(await inspect({ ...args, changes: [] }), 'unrecognized'); assert.equal(requests, 1);
  await assert.rejects(inspect({ ...args, fetcher: async () => ({ ok: false }) }), /READ_FAILED/);
  await assert.rejects(inspect({ ...args, fetcher: async () => ({ ok: true, redirected: true }) }), /READ_FAILED/);
});
test('workflow conserve les 62 suites, le bootstrap normal et la relecture même après échec', () => {
  const workflow = parse(readFileSync(new URL('../../.github/workflows/validate-pr.yml', import.meta.url), 'utf8'));
  const steps = workflow.jobs['sql-transaction'].steps;
  const bootstrap = steps.find(s => s.name === 'Synchroniser le schéma main vers le staging');
  assert.match(bootstrap.if, /paiements_installation.outputs.mode != 'installed'/);
  assert.match(bootstrap.run, /check-staging-migration-base\.mjs/);
  const rollback = steps.find(s => s.name === 'Exécuter les migrations ajoutées et les régressions SQL sans persister');
  assert.equal([...rollback.run.matchAll(/^\s+tests\/[^\s]+\.sql$/gm)].length, 62);
  assert.match(rollback.run, /^\s+tests\/security\/avoirs-imputation-staging\.test\.sql$/m);
  assert.match(rollback.run, /paiements-staging-installed\.mjs verify\n\s+MIGRATIONS=\(\)/);
  assert.match(rollback.run, /SAVEPOINT %s/); assert.match(rollback.run, /ROLLBACK TO SAVEPOINT/);
  const post = steps.find(s => s.name === 'Paiements — relecture indépendante de l’installation après succès ou échec SQL');
  assert.equal(post.if, "always() && steps.paiements_installation.outputs.mode == 'installed'");
  assert.equal(post.run, 'node scripts/ci/paiements-staging-installed.mjs verify');
});

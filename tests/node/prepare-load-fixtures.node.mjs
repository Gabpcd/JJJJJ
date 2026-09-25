import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { configuration, creerManifeste, executerFixtures, sqlNettoyage, sqlPreparation, STAGING_REF, STAGING_URL } from '../../scripts/ci/prepare-load-fixtures.mjs';

function environnement(extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-fixtures-node-'));
  return { STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_URL: STAGING_URL,
    STAGING_SUPABASE_ACCESS_TOKEN: 'faux-token-test-ne-jamais-utiliser', STAGING_SUPABASE_ANON_KEY: 'fausse-cle-test',
    LOAD_TEST_RUN_ID: 'node-test-123-1', LOAD_FIXTURE_COUNT: '100', LOAD_FIXTURE_MANIFEST: join(dir, 'manifest.json'),
    GITHUB_ENV: join(dir, 'github-env'), ...extra };
}
const reponse = data => ({ ok: true, json: async () => data });
const silence = () => {};

test('seuls URL et ref exacts de staging sont autorisés', async () => {
  for (const extra of [{ STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' }, { STAGING_SUPABASE_URL: 'https://flripxtsyegjshnhzjkz.supabase.co' }, { STAGING_SUPABASE_URL: STAGING_URL + '.evil.invalid' }]) {
    let appels = 0;
    await assert.rejects(executerFixtures({ action: 'prepare', env: environnement(extra), fetchImpl: () => { appels++; }, log: silence }), /Destination refusée/);
    assert.equal(appels, 0);
  }
});
test('taille bornée, run explicite et entrées non exécutables', () => {
  for (const LOAD_FIXTURE_COUNT of ['0', '99', '1001', '500;delete', 'NaN']) assert.throws(() => configuration(environnement({ LOAD_FIXTURE_COUNT })), /100 et 1000/);
  for (const LOAD_TEST_RUN_ID of ['', "run'; DROP TABLE", '../run', 'x\nrun']) assert.throws(() => configuration(environnement({ LOAD_TEST_RUN_ID })), /RUN_ID/);
  assert.equal(configuration(environnement()).count, 100);
});
test('1000 missions stables, 10 villes et 100 combinaisons profession-ville', () => {
  const m = creerManifeste({ runId: '500-2', count: 1000 });
  assert.equal(new Set(m.missions.map(row => row.id)).size, 1000);
  assert.equal(new Set(m.etabs.map(row => row.id)).size, 10);
  assert.equal(new Set(m.missions.map(row => `${row.etablissementId}:${row.profession}`)).size, 100);
  assert.ok(m.etabs.every(row => row.email.endsWith('@example.invalid') && /^99\d{12}$/.test(row.siret)));
  assert.ok(m.missions.every(row => row.intitule.startsWith('RECETTE CHARGE ') && !row.intitule.startsWith('[')));
  assert.deepEqual(m, creerManifeste({ runId: '500-2', count: 1000 }));
  assert.notEqual(m.missions[0].id, creerManifeste({ runId: '500-3', count: 1000 }).missions[0].id);
});
test('préparation SQL transactionnelle, FK préservées et aucun compte Auth', () => {
  const sql = sqlPreparation(creerManifeste({ runId: '500-1', count: 100 }));
  assert.match(sql, /^BEGIN;/);
  assert.match(sql, /LOCK TABLE public.etablissements, public.missions IN ACCESS EXCLUSIVE MODE/);
  assert.match(sql, /NOT tgisinternal AND tgenabled='O'/);
  assert.ok(sql.indexOf('DISABLE TRIGGER %I') < sql.indexOf('INSERT INTO public.etablissements'));
  assert.ok(sql.indexOf('INSERT INTO public.missions') < sql.indexOf('ENABLE TRIGGER %I'));
  assert.ok(sql.indexOf('ENABLE TRIGGER %I') < sql.indexOf('COMMIT;'));
  assert.match(sql, /cron\.job WHERE active/); assert.match(sql, /tgenabled IN \('R', 'A'\)/);
  assert.match(sql, /Parent de mission absent ou hors fixture/); assert.match(sql, /fn_missions_publiques_recherche\(NULL, NULL\)/);
  assert.doesNotMatch(sql, /INSERT INTO auth\.|DISABLE TRIGGER ALL|session_replication_role|cron\.(schedule|alter)|net\.http|send-email|stripe/i);
});
test('nettoyage par UUID exacts, FK conservées et dépendances tierces refusées', () => {
  const sql = sqlNettoyage(creerManifeste({ runId: '500-1', count: 100 }));
  assert.doesNotMatch(sql, /session_replication_role|DISABLE TRIGGER/);
  assert.match(sql, /DELETE FROM public\.missions WHERE id = ANY\(v_ids\)/);
  assert.match(sql, /DELETE FROM public\.etablissements WHERE id = ANY\(v_ids\)/);
  assert.doesNotMatch(sql, /DELETE[^;]*LIKE|\bCASCADE\b/);
  assert.match(sql, /Dépendance métier/); assert.match(sql, /soignant_assigne_id IS NOT NULL/);
});
test('même verrou transactionnel avant toute lecture, confirmation sous verrou et clé isolée par run', () => {
  const m = creerManifeste({ runId: 'run-lock-1', count: 100 });
  const prepare = sqlPreparation(m); const cleanup = sqlNettoyage(m);
  const verrou = /pg_advisory_xact_lock\((\d+)::bigint\)/;
  assert.equal(prepare.match(verrou)[1], cleanup.match(verrou)[1]);
  assert.notEqual(prepare.match(verrou)[1], sqlPreparation(creerManifeste({ runId: 'run-lock-2', count: 100 })).match(verrou)[1]);
  for (const sql of [prepare, cleanup]) {
    assert.ok(sql.indexOf('BEGIN;') < sql.indexOf('pg_advisory_xact_lock'));
    assert.ok(sql.indexOf('pg_advisory_xact_lock') < sql.indexOf('SELECT 1 FROM'));
    assert.match(sql, /SET LOCAL lock_timeout = '5s'/);
    assert.doesNotMatch(sql, /pg_advisory_(?:unlock|lock)\(/);
  }
  assert.ok(cleanup.indexOf('Nettoyage incomplet') < cleanup.indexOf('COMMIT;'));
  assert.doesNotMatch(cleanup.slice(cleanup.indexOf('COMMIT;')), /FROM public\./);
});
test('reçu immuable partagé bloque prepare tardif, y compris après un cleanup sans ligne', () => {
  const m = creerManifeste({ runId: 'run-recu-1', count: 100 });
  const prepare = sqlPreparation(m); const cleanup = sqlNettoyage(m);
  const receipt = prepare.match(/journaux_audit WHERE id = '([a-f0-9-]+)'::uuid/)[1];
  assert.ok(prepare.indexOf('Run déjà nettoyé') < prepare.indexOf('INSERT INTO public.etablissements'));
  assert.ok(cleanup.includes(`VALUES ('${receipt}'::uuid, NULL, 'SYSTEME', 'SYSTEM', 'RECETTE_CHARGE'`));
  assert.ok(cleanup.indexOf('INSERT INTO public.journaux_audit') < cleanup.indexOf('COMMIT;'));
  assert.match(cleanup, /ON CONFLICT \(id\) DO NOTHING/);
  assert.match(cleanup, /Reçu de nettoyage incohérent/);
  assert.match(cleanup, /rolsuper OR rolbypassrls/);
  assert.doesNotMatch(cleanup, /(?:UPDATE|DELETE FROM) public\.journaux_audit/);
});
test('manifeste écrit avant SQL, validation anonyme réelle du nombre et environnement k6', async () => {
  const env = environnement(); const manifest = creerManifeste(configuration(env)); const appels = [];
  const result = await executerFixtures({ action: 'prepare', env, log: silence, fetchImpl: async (url, options) => {
    appels.push(url);
    assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'planned');
    if (url.includes('/database/query')) {
      assert.match(JSON.parse(options.body).query, /INSERT INTO public\.missions/);
      return reponse([{ missions_preparees: 100, etablissements_prepares: 10 }]);
    }
    assert.equal(url, `${STAGING_URL}/rest/v1/rpc/fn_missions_publiques_recherche`);
    assert.equal(options.headers.apikey, env.STAGING_SUPABASE_ANON_KEY);
    assert.equal(options.body, '{}');
    return reponse(manifest.missions.map(m => ({ id: m.id })));
  } });
  assert.equal(appels.length, 2); assert.equal(result.missions_visibles, 100);
  assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'prepared');
  assert.equal(readFileSync(env.GITHUB_ENV, 'utf8'), 'LOAD_TEST_EXPECTED_MISSIONS=100\n');
  assert.ok(!readFileSync(env.LOAD_FIXTURE_MANIFEST, 'utf8').includes(env.STAGING_SUPABASE_ACCESS_TOKEN));
});
test('un résultat vide ou incomplet échoue et garde les IDs pour cleanup', async () => {
  for (const nombre of [0, 99]) {
    const env = environnement(); const m = creerManifeste(configuration(env));
    await assert.rejects(executerFixtures({ action: 'prepare', env, log: silence, fetchImpl: async url => url.includes('/database/query')
      ? reponse([{ missions_preparees: 100, etablissements_prepares: 10 }]) : reponse(m.missions.slice(0, nombre)) }), /Catalogue public incomplet/);
    assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).missions.length, 100);
  }
});
test('erreur Management API conserve un manifeste utilisable, sans imprimer le corps', async () => {
  const env = environnement();
  await assert.rejects(executerFixtures({ action: 'prepare', env, log: silence, fetchImpl: async () => ({ ok: false, status: 503 }) }), /HTTP 503/);
  assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'planned');
  let appels = 0;
  await executerFixtures({ action: 'cleanup', env, log: silence, fetchImpl: async (_, options) => {
    appels++; assert.match(JSON.parse(options.body).query, /DELETE FROM public\.missions/);
    return reponse([{ missions_restantes: 0, etablissements_restants: 0 }]);
  } });
  assert.equal(appels, 1); assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'cleaned');
});
test('réponse SQL inattendue interdit un faux succès', async () => {
  const env = environnement();
  await assert.rejects(executerFixtures({ action: 'prepare', env, log: silence, fetchImpl: async () => reponse([{ missions_preparees: 99, etablissements_prepares: 10 }]) }), /Quantité/);
});
test('nettoyage d’un manifeste modifié refuse toute requête', async () => {
  const env = environnement(); const m = creerManifeste(configuration(env)); m.missions[0].id = '00000000-0000-4000-8000-000000000001';
  writeFileSync(env.LOAD_FIXTURE_MANIFEST, JSON.stringify(m)); let appels = 0;
  await assert.rejects(executerFixtures({ action: 'cleanup', env, log: silence, fetchImpl: async () => { appels++; } }), /Manifeste incohérent/);
  assert.equal(appels, 0);
});
test('préparation ne remplace jamais un manifeste existant', async () => {
  const env = environnement(); writeFileSync(env.LOAD_FIXTURE_MANIFEST, 'manifeste à préserver');
  let appels = 0;
  await assert.rejects(executerFixtures({ action: 'prepare', env, log: silence, fetchImpl: async () => { appels++; } }), /EEXIST/);
  assert.equal(appels, 0); assert.equal(readFileSync(env.LOAD_FIXTURE_MANIFEST, 'utf8'), 'manifeste à préserver');
});
test('cleanup sans manifeste ne touche aucune donnée', async () => {
  let appels = 0;
  assert.deepEqual(await executerFixtures({ action: 'cleanup', env: environnement(), log: silence, fetchImpl: async () => { appels++; } }), { skipped: true });
  assert.equal(appels, 0);
});
test('timeout prepare puis verrou occupé : cleanup attend un réessai avant de confirmer le commit tardif', async () => {
  const env = environnement(); let enVol = false; let missions = 0; let appelsPrepare = 0; const logs = [];
  await assert.rejects(executerFixtures({ action: 'prepare', env, log: silence, fetchImpl: async () => {
    appelsPrepare++; enVol = true; throw new DOMException('Réponse perdue', 'TimeoutError');
  } }), /interrompue ou expirée/);
  assert.equal(appelsPrepare, 1); // La préparation ambiguë n’est jamais rejouée.
  let appelsCleanup = 0; const attentes = [];
  await executerFixtures({ action: 'cleanup', env, log: value => logs.push(value), attendre: async ms => {
    attentes.push(ms);
    assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'planned');
    // Injection d’un commit serveur après le timeout HTTP, avant le second cleanup.
    missions = 100; enVol = false;
  }, fetchImpl: async (_, options) => {
    appelsCleanup++;
    assert.match(JSON.parse(options.body).query, /pg_advisory_xact_lock/);
    if (enVol) return { ok: false, status: 400, text: async () => '{"code":"55P03","message":"canceling statement due to lock timeout SECRET_NE_PAS_LOGUER"}' };
    assert.equal(missions, 100); missions = 0;
    return reponse([{ missions_restantes: 0, etablissements_restants: 0 }]);
  } });
  assert.equal(appelsCleanup, 2); assert.deepEqual(attentes, [1000]); assert.equal(missions, 0);
  assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'cleaned');
  assert.ok(logs.every(value => !value.includes('SECRET_NE_PAS_LOGUER')));
});
test('cleanup ambigu après commit est rejoué sans supprimer au-delà du lot', async () => {
  const env = environnement(); const m = creerManifeste(configuration(env));
  writeFileSync(env.LOAD_FIXTURE_MANIFEST, JSON.stringify({ ...m, status: 'prepared' }));
  let appels = 0; const queries = [];
  await executerFixtures({ action: 'cleanup', env, log: silence, attendre: async () => {}, fetchImpl: async (_, options) => {
    appels++; queries.push(JSON.parse(options.body).query);
    if (appels === 1) throw new TypeError('fetch failed après commit');
    return reponse([{ missions_restantes: 0, etablissements_restants: 0 }]);
  } });
  assert.equal(appels, 2); assert.equal(queries[0], queries[1]);
  assert.equal(JSON.parse(readFileSync(env.LOAD_FIXTURE_MANIFEST)).status, 'cleaned');
});
test('trois échecs transitoires bornent cleanup et laissent le manifeste intact', async () => {
  const env = environnement(); const original = JSON.stringify({ ...creerManifeste(configuration(env)), status: 'planned' });
  writeFileSync(env.LOAD_FIXTURE_MANIFEST, original); let appels = 0; const attentes = [];
  await assert.rejects(executerFixtures({ action: 'cleanup', env, log: silence, attendre: async ms => attentes.push(ms), fetchImpl: async () => {
    appels++; return { ok: false, status: 503, text: async () => 'secret backend response' };
  } }), /HTTP 503/);
  assert.equal(appels, 3); assert.deepEqual(attentes, [1000, 2000]);
  assert.equal(readFileSync(env.LOAD_FIXTURE_MANIFEST, 'utf8'), original);
});
test('refus SQL métier ne se rejoue pas et ne révèle pas le corps', async () => {
  const env = environnement(); const original = JSON.stringify({ ...creerManifeste(configuration(env)), status: 'prepared' });
  writeFileSync(env.LOAD_FIXTURE_MANIFEST, original); let appels = 0;
  await assert.rejects(executerFixtures({ action: 'cleanup', env, log: silence, attendre: async () => assert.fail('Pas de retry métier'), fetchImpl: async () => {
    appels++; return { ok: false, status: 400, text: async () => '{"code":"P0001","message":"Dépendance métier secret"}' };
  } }), error => /HTTP 400/.test(error.message) && !/secret/.test(error.message));
  assert.equal(appels, 1); assert.equal(readFileSync(env.LOAD_FIXTURE_MANIFEST, 'utf8'), original);
});
test('cleanup 200 avec reliquat ne marque jamais le manifeste cleaned', async () => {
  const env = environnement(); const original = JSON.stringify({ ...creerManifeste(configuration(env)), status: 'planned' });
  writeFileSync(env.LOAD_FIXTURE_MANIFEST, original);
  await assert.rejects(executerFixtures({ action: 'cleanup', env, log: silence, fetchImpl: async () => reponse([{ missions_restantes: 1, etablissements_restants: 0 }]) }), /Nettoyage non confirmé/);
  assert.equal(readFileSync(env.LOAD_FIXTURE_MANIFEST, 'utf8'), original);
});

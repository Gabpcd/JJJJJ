import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { parse } from 'yaml';
import { SQL_JOB_NAME, waitStagingSchema } from '../../scripts/ci/wait-staging-schema.mjs';

const sha = 'a'.repeat(40), mergeSha = 'b'.repeat(40);
const env = { GITHUB_TOKEN: 'jeton-fictif', GITHUB_REPOSITORY: 'Gabpcd/JJJJJ', GITHUB_SHA: mergeSha,
  STAGING_SCHEMA_SHA: sha, STAGING_SCHEMA_BRANCH: 'fix/test-schema', GITHUB_EVENT_NAME: 'pull_request' };
const run = { id: 100, run_attempt: 1, head_sha: sha, head_branch: env.STAGING_SCHEMA_BRANCH,
  event: 'pull_request', path: '.github/workflows/validate-pr.yml', head_repository: { full_name: env.GITHUB_REPOSITORY },
  status: 'in_progress', conclusion: null };
const job = { id: 200, run_id: run.id, head_sha: sha, name: SQL_JOB_NAME, status: 'completed', conclusion: 'success' };
function simulation(options = {}) {
  let heure = 0;
  const appels = [], attentes = [], messages = [];
  const fetchImpl = async (url, init) => {
    const u = new URL(url); appels.push(u);
    assert.equal(u.origin, 'https://api.github.com'); assert.equal(init.method, 'GET');
    assert.equal(init.redirect, 'error'); assert.equal(init.headers.Authorization, 'Bearer jeton-fictif');
    assert.ok(init.signal instanceof AbortSignal);
    if (options.fetch) return options.fetch(u, init);
    if (u.pathname.endsWith('/workflows/validate-pr.yml/runs')) {
      assert.equal(u.searchParams.get('head_sha'), options.env?.STAGING_SCHEMA_SHA || sha);
      assert.equal(u.searchParams.get('branch'), options.env?.STAGING_SCHEMA_BRANCH || env.STAGING_SCHEMA_BRANCH);
      assert.equal(u.searchParams.get('event'), 'pull_request');
      return { ok: true, json: async () => ({ workflow_runs: (options.runs || (() => [run]))(attentes.length, u) }) };
    }
    if (/\/attempts\/\d+\/jobs$/.test(u.pathname)) return { ok: true, json: async () => ({ jobs: (options.jobs || (() => [job]))(attentes.length, u) }) };
    if (u.pathname.endsWith('/runs/100')) return { ok: true, json: async () => (options.current || (() => run))(attentes.length) };
    throw new Error(`Appel non préparé : ${u.pathname}`);
  };
  return { appels, attentes, messages, lancer: (extra = {}) => waitStagingSchema({
    env: { ...env, ...options.env }, fetchImpl, now: () => heure,
    sleep: async ms => { attentes.push(ms); heure += ms; }, log: value => messages.push(value),
    maxWaitMs: 15_000, ...extra,
  }) };
}

test('succès SQL du head de PR exact, même si les autres jobs sont encore en cours', async () => {
  const s = simulation();
  assert.deepEqual(await s.lancer(), { sha, branch: env.STAGING_SCHEMA_BRANCH, runId: 100, runAttempt: 1, jobId: 200 });
  assert.equal(s.attentes.length, 0); assert.equal(s.appels.length, 3);
  assert.ok(s.messages[0].includes(sha)); assert.ok(!s.messages.join('').includes(env.GITHUB_TOKEN));
});
test('attend le vrai job SQL toutes les 5 s avant toute réussite', async () => {
  const s = simulation({ jobs: n => [{ ...job, status: n < 2 ? 'in_progress' : 'completed', conclusion: n < 2 ? null : 'success' }] });
  await s.lancer(); assert.deepEqual(s.attentes, [5000, 5000]);
});
test('dépôt public ou privé : mêmes exigences SHA, branche, workflow et propriétaire', async () => {
  for (const prive of [false, true]) {
    const s = simulation({ runs: () => [{ ...run, head_repository: { full_name: env.GITHUB_REPOSITORY, private: prive } }] });
    assert.equal((await s.lancer()).sha, sha);
  }
});
test('ignore ancien SHA, mauvaise branche, fork, push et workflow ressemblant', async () => {
  for (const incorrect of [{ head_sha: mergeSha }, { head_branch: 'main' },
    { head_repository: { full_name: 'Autre/JJJJJ' } }, { event: 'push' }, { path: '.github/workflows/deploy-supabase.yml' }]) {
    const s = simulation({ runs: () => [{ ...run, ...incorrect, status: 'completed', conclusion: 'success' }] });
    await assert.rejects(s.lancer(), /Aucun run validate-pr.yml de cette branche et de ce SHA/);
    assert.ok(s.appels.every(u => u.pathname.endsWith('/workflows/validate-pr.yml/runs')));
  }
});
test('échec, annulation, timeout, skipped et neutral du job ne deviennent jamais succès', async () => {
  for (const conclusion of ['failure', 'cancelled', 'timed_out', 'skipped', 'neutral', null]) {
    const s = simulation({ jobs: () => [{ ...job, conclusion }] });
    await assert.rejects(s.lancer(), /Validation SQL.*terminée/); assert.equal(s.attentes.length, 0);
  }
});
test('prend le run le plus récent et ne retombe pas sur un ancien succès', async () => {
  const s = simulation({ runs: () => [{ ...run, id: 99, status: 'completed', conclusion: 'success' }, run],
    jobs: () => [{ ...job, conclusion: 'failure' }] });
  await assert.rejects(s.lancer(), /failure/);
  assert.ok(s.appels.some(u => u.pathname.includes('/runs/100/attempts/1/jobs')));
  assert.ok(!s.appels.some(u => u.pathname.includes('/runs/99/')));
});
test('lit uniquement les jobs de la tentative courante', async () => {
  const s = simulation({ runs: () => [{ ...run, run_attempt: 2 }], current: () => ({ ...run, run_attempt: 2 }),
    jobs: (_, u) => { assert.ok(u.pathname.includes('/attempts/2/')); return [job]; } });
  assert.equal((await s.lancer()).runAttempt, 2);
});
test('une relance pendant la lecture impose la nouvelle tentative', async () => {
  const s = simulation({ runs: n => [{ ...run, run_attempt: n === 0 ? 1 : 2 }], current: () => ({ ...run, run_attempt: 2 }) });
  const resultat = await s.lancer(); assert.equal(resultat.runAttempt, 2); assert.deepEqual(s.attentes, [5000]);
});
test('un job d’un autre SHA/run, un homonyme partiel ou un doublon est refusé', async () => {
  for (const jobs of [[{ ...job, head_sha: mergeSha }], [{ ...job, run_id: 99 }], [{ ...job, name: SQL_JOB_NAME + ' copie' }]]) {
    const s = simulation({ runs: () => [{ ...run, status: 'completed', conclusion: 'success' }], jobs: () => jobs });
    await assert.rejects(s.lancer(), /sans succès du job SQL/);
  }
  await assert.rejects(simulation({ jobs: () => [job, { ...job, id: 201 }] }).lancer(), /homonymes/);
});
test('workflow terminé avant réussite SQL échoue immédiatement', async () => {
  for (const conclusion of ['failure', 'cancelled', 'success']) {
    const s = simulation({ runs: () => [{ ...run, status: 'completed', conclusion }], jobs: () => [] });
    await assert.rejects(s.lancer(), /sans succès du job SQL/); assert.deepEqual(s.attentes, []);
  }
});
test('lancement manuel sans validation ne fabrique pas un succès', async () => {
  const s = simulation({ env: { GITHUB_EVENT_NAME: 'workflow_dispatch' }, runs: () => [] });
  await assert.rejects(s.lancer(), /Un lancement manuel ne remplace pas une validation SQL réussie/);
  assert.deepEqual(s.attentes, [5000, 5000, 5000]);
});
test('borne absolue 15 minutes sans augmenter le polling de 5 s', async () => {
  const s = simulation({ runs: () => [] });
  await assert.rejects(s.lancer({ maxWaitMs: 900_000 }), /après 900 s/);
  assert.equal(s.attentes.length, 180); assert.ok(s.attentes.every(ms => ms === 5000));
  await assert.rejects(simulation().lancer({ maxWaitMs: 900_001 }), /bornée à 15 minutes/);
});
test('absence de permission et erreur API échouent sans exposer le corps ou le jeton', async () => {
  const s = simulation({ fetch: () => ({ ok: false, status: 403, text: () => { throw new Error('Le corps ne doit pas être lu'); } }) });
  await assert.rejects(s.lancer(), /HTTP 403/);
  assert.ok(!s.messages.join('').includes(env.GITHUB_TOKEN));
  await assert.rejects(simulation({ env: { GITHUB_TOKEN: '' } }).lancer(), /actions:read/);
});
test('configuration invalide ou API détournée refusée avant toute requête', async () => {
  for (const extra of [{ STAGING_SCHEMA_SHA: 'main' }, { STAGING_SCHEMA_BRANCH: '\n' }, { GITHUB_REPOSITORY: 'Gabpcd/JJJJJ/evil' },
    { GITHUB_API_URL: 'https://example.invalid' }]) {
    const s = simulation({ env: extra }); await assert.rejects(s.lancer()); assert.equal(s.appels.length, 0);
  }
});
test('pagination retrouve le job SQL sans accepter un autre intitulé', async () => {
  const s = simulation({ jobs: (_, u) => u.searchParams.get('page') === '1'
    ? Array.from({ length: 100 }, (_, id) => ({ ...job, id, name: 'Autre job' })) : [job] });
  assert.equal((await s.lancer()).jobId, job.id);
  assert.ok(s.appels.some(u => u.searchParams.get('page') === '2'));
});
test('YAML : aucun verrou pendant attente, verrou seulement après needs et accès Actions lecture', () => {
  const workflow = parse(readFileSync(new URL('../../.github/workflows/staging-comptes.yml', import.meta.url), 'utf8'));
  assert.equal(workflow.concurrency, undefined);
  assert.equal(workflow.permissions.actions, 'read'); assert.equal(workflow.permissions.contents, 'read');
  const attente = workflow.jobs['schema-staging'], comptes = workflow.jobs.comptes;
  assert.equal(attente.concurrency, undefined); assert.equal(comptes.needs, 'schema-staging');
  assert.deepEqual(comptes.concurrency, { group: 'jolene-supabase-staging-writes', 'cancel-in-progress': false });
  assert.equal(attente['timeout-minutes'], 17);
  const step = attente.steps.find(s => s.run === 'node scripts/ci/wait-staging-schema.mjs');
  assert.equal(step.env.STAGING_SCHEMA_SHA, '${{ github.event.pull_request.head.sha || github.sha }}');
  assert.equal(step.env.STAGING_SCHEMA_BRANCH, '${{ github.head_ref || github.ref_name }}');
  assert.equal(step.env.GITHUB_TOKEN, '${{ github.token }}');
  assert.equal(attente.if, comptes.if); assert.ok(attente.if.includes('head.repo.full_name == github.repository'));
  assert.ok(!JSON.stringify(attente).includes('SUPABASE')); // Aucun accès SQL, staging ou production, dans l’attente.
  for (const travail of [attente, comptes]) assert.equal(travail.steps.find(s => s.uses === 'actions/checkout@v5').with.ref, step.env.STAGING_SCHEMA_SHA);
});

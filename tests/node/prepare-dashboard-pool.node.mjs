import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { STAGING_REF, STAGING_URL } from '../../scripts/ci/prepare-load-fixtures.mjs';
import { executerPoolDashboard, manifestePoolDashboard } from '../../scripts/ci/prepare-dashboard-pool.mjs';
import { lirePoolDashboard } from '../load/helpers/dashboard-pool.js';

const response = (body, status = 200) => new Response(JSON.stringify(body), { status });
const secret = slot => `Aa1!canari-prive-profil-${slot}-jamais-artifact`;
function banc() {
  const dir = mkdtempSync(join(tmpdir(), 'jolene-dashboard-pool-node-'));
  const env = { STAGING_SUPABASE_PROJECT_REF: STAGING_REF, STAGING_SUPABASE_URL: STAGING_URL,
    STAGING_SUPABASE_ACCESS_TOKEN: 'management-fictif', STAGING_SUPABASE_SERVICE_ROLE_KEY: 'service-fictif',
    STAGING_SUPABASE_ANON_KEY: 'anon-fictif', LOAD_TEST_RUN_ID: 'pool-123-1',
    LOAD_DASHBOARD_MANIFEST: join(dir, 'pool.json'), GITHUB_ENV: join(dir, 'private-env') };
  const attendu = manifestePoolDashboard(env.LOAD_TEST_RUN_ID);
  const membres = attendu.membres.map(m => ({ ...m, user: null, profile: false, created: 0, deleted: 0 }));
  const calls = [], logs = []; let passwordIndex = 0;
  const fetchImpl = async (url, options = {}) => {
    const body = options.body ? JSON.parse(options.body) : null, method = options.method;
    calls.push({ url, method, body });
    assert.ok(options.signal instanceof AbortSignal); assert.equal(options.redirect, 'error');
    assert.ok(url.startsWith(STAGING_URL + '/') || url === `https://api.supabase.com/v1/projects/${STAGING_REF}/database/query`);
    const m = membres.find(m => url.includes(m.userId) || body?.id === m.userId || body?.email === m.email
      || body?.query?.includes(m.userId) || options.headers.Authorization === `Bearer jwt-fictif-${m.slot}`);
    assert.ok(m, 'Requête exclusivement liée à un membre exact');
    if (url.endsWith('/database/query')) {
      const q = body.query;
      if (q.includes('SELECT true AS pret')) return response([{ pret: true }]);
      if (q.includes('SELECT true AS profil_prepare')) { m.profile = true; return response([{ profil_prepare: true }]); }
      if (q.includes('DO $fixture_cleanup$')) {
        m.profile = false; if (m.user) m.user.app_metadata.load_cleanup_pending = true;
        return response([{ profils_restants: 0 }]);
      }
      if (q.includes('AS auth_restants')) return response([{ auth_restants: m.user ? 1 : 0,
        profils_restants: m.profile ? 1 : 0, preferences_restantes: m.profile ? 1 : 0 }]);
    }
    if (url.endsWith('/admin/users') && method === 'POST') {
      const global = JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST));
      const membre = JSON.parse(readFileSync(`${env.LOAD_DASHBOARD_MANIFEST}.members/${m.slot}.json`));
      assert.equal(global.membres.length, 10); assert.equal(membre.status, 'planned');
      assert.equal(body.email_confirm, true); assert.equal(body.password, secret(m.slot));
      m.created++; m.user = { id: body.id, email: body.email, app_metadata: body.app_metadata };
      return response(m.user);
    }
    if (url.endsWith('/admin/users/' + m.userId)) {
      if (method === 'GET') return m.user ? response(m.user) : response({}, 404);
      if (method === 'DELETE') {
        assert.equal(m.profile, false); assert.equal(m.user.app_metadata.load_cleanup_pending, true);
        m.deleted++; m.user = null; return response({});
      }
    }
    if (url.endsWith('/token?grant_type=password')) return response({ access_token: `jwt-fictif-${m.slot}`, user: m.user });
    if (url.endsWith('/rpc/fn_dashboard_soignant_complet')) return response({
      profil: { prenom: m.prenom, nom: m.nom, profession: 'AS', identite_verifiee: false, tous_documents_valides: false },
      missions_ouvertes: [], mes_missions: [], documents: [], gains_6mois: [], missions_semaine_cal: [], propositions: [],
      heures_semaine: 0, notifs_non_lues: 0, gains_mois: { net_total: 0, brut_total: 0, nb_missions: 0 },
    });
    throw new Error('Endpoint non simulé');
  };
  const run = (action, fetcher = fetchImpl, override = {}) => executerPoolDashboard({ action, env: { ...env, ...override },
    fetchImpl: fetcher, log: s => logs.push(s), genererMotDePasse: () => secret(passwordIndex++) });
  return { env, membres, calls, logs, fetchImpl, run,
    manifeste: () => JSON.parse(readFileSync(env.LOAD_DASHBOARD_MANIFEST, 'utf8')) };
}

test('pool déterministe : dix membres/identités uniques, run et destination contrôlés avant réseau', async () => {
  const m = manifestePoolDashboard('run-1');
  assert.deepEqual(m, manifestePoolDashboard('run-1')); assert.equal(new Set(m.membres.map(m => m.userId)).size, 10);
  for (const runId of ['', 'x\ny', 'a'.repeat(76)]) assert.throws(() => manifestePoolDashboard(runId));
  for (const override of [{ STAGING_SUPABASE_PROJECT_REF: 'flripxtsyegjshnhzjkz' }, { STAGING_SUPABASE_URL: 'https://prod.invalid' },
    { STAGING_SUPABASE_ACCESS_TOKEN: '' }, { GITHUB_ENV: '' }]) {
    const t = banc(); await assert.rejects(t.run('prepare', t.fetchImpl, override)); assert.equal(t.calls.length, 0);
  }
});
test('dix créations séquentielles, export privé atomique du lot, zéro secret dans tous les manifests et logs hors masques', async () => {
  const t = banc(); assert.deepEqual(await t.run('prepare'), { identites: 10, profession: 'AS' });
  assert.equal(t.calls.length, 50); assert.equal(t.manifeste().status, 'prepared');
  const raw = readFileSync(t.env.GITHUB_ENV, 'utf8').trim().replace(/^LOAD_DASHBOARD_POOL_JSON=/, '');
  const pool = lirePoolDashboard(raw, t.env.LOAD_TEST_RUN_ID);
  assert.equal(pool.length, 10); assert.equal(new Set(pool.map(p => p.password)).size, 10);
  const manifests = readFileSync(t.env.LOAD_DASHBOARD_MANIFEST, 'utf8') + readdirSync(`${t.env.LOAD_DASHBOARD_MANIFEST}.members`)
    .map(name => readFileSync(`${t.env.LOAD_DASHBOARD_MANIFEST}.members/${name}`, 'utf8')).join('');
  const logs = t.logs.filter(s => !s.startsWith('::add-mask::')).join('\n');
  for (let i = 0; i < 10; i++) { assert.ok(!manifests.includes(secret(i))); assert.ok(!logs.includes(secret(i))); }
  assert.doesNotMatch(manifests, /jwt-fictif|service-fictif|management-fictif/);
  assert.ok(t.calls.every(c => !/signup|invite|recover|send-email|send-sms/.test(c.url)));
  const before = t.calls.length; await assert.rejects(t.run('prepare'), /déjà commencé/); assert.equal(t.calls.length, before);
});
test('cleanup des dix membres, comptage exact et reprise sans deuxième suppression', async () => {
  const t = banc(); await t.run('prepare');
  assert.deepEqual(await t.run('cleanup'), { membres_nettoyes: 10, membres_non_commences: 0 });
  assert.equal(t.calls.length, 100); assert.equal(t.manifeste().status, 'cleaned');
  await t.run('cleanup');
  assert.ok(t.membres.every(m => m.deleted === 1 && !m.user && !m.profile));
});
test('échec de création/seed/login aux membres 1, 5, 10 : nettoyer ceux commencés, jamais créer les suivants ni exporter le pool', async () => {
  for (const slot of [0, 4, 9]) for (const etape of ['auth', 'sql', 'login']) {
    const t = banc(), id = t.membres[slot].userId, email = t.membres[slot].email;
    await assert.rejects(t.run('prepare', async (url, options) => {
      const body = JSON.parse(options.body || '{}'); const result = await t.fetchImpl(url, options);
      if ((etape === 'auth' && body.id === id) || (etape === 'sql' && body.query?.includes(id) && body.query.includes('AS profil_prepare'))
        || (etape === 'login' && body.email === email && url.includes('/token?'))) throw new Error(secret(slot));
      return result;
    }), /ambiguë/);
    assert.equal(t.manifeste().status, 'partial');
    assert.throws(() => readFileSync(t.env.GITHUB_ENV));
    assert.deepEqual(await t.run('cleanup'), { membres_nettoyes: slot + 1, membres_non_commences: 9 - slot });
    assert.ok(t.membres.slice(0, slot + 1).every(m => m.deleted === 1));
    assert.ok(t.membres.slice(slot + 1).every(m => m.created === 0));
  }
});
test('création Auth encore absente après timeout : garder le membre ambigu et nettoyer les quatre premiers', async () => {
  const t = banc(), id = t.membres[4].userId;
  await assert.rejects(t.run('prepare', async (url, options) => {
    if (JSON.parse(options.body || '{}').id === id) throw new Error(secret(4));
    return t.fetchImpl(url, options);
  }), /ambiguë/);
  await assert.rejects(t.run('cleanup'), /Création Auth ambiguë/);
  assert.equal(t.manifeste().status, 'partial'); assert.equal(t.manifeste().membres[4].status, 'planned');
  assert.ok(t.membres.slice(0, 4).every(m => m.deleted === 1));
});
test('un membre modifié ou une dépendance bloque cet ID seulement ; neuf autres nettoyés et échec global', async () => {
  for (const cas of ['metadata', 'dependance']) {
    const t = banc(); await t.run('prepare');
    if (cas === 'metadata') t.membres[4].user.app_metadata.est_compte_test = false;
    await assert.rejects(t.run('cleanup', async (url, options) => {
      const q = JSON.parse(options.body || '{}').query;
      if (cas === 'dependance' && q?.includes(t.membres[4].userId) && q.includes('DO $fixture_cleanup$')) return response({ error: secret(4) }, 500);
      return t.fetchImpl(url, options);
    }), /Nettoyage du pool incomplet/);
    assert.equal(t.manifeste().status, 'partial'); assert.equal(t.membres[4].deleted, 0);
    assert.ok(t.membres.filter(m => m.slot !== 4).every(m => m.deleted === 1));
  }
});
test('DELETE perdu : neuf autres nettoyés immédiatement, reprise GET/SQL sans double DELETE', async () => {
  const t = banc(); await t.run('prepare');
  await assert.rejects(t.run('cleanup', async (url, options) => {
    const result = await t.fetchImpl(url, options);
    if (options.method === 'DELETE' && url.endsWith(t.membres[4].userId)) throw new Error(secret(4));
    return result;
  }), /ambiguë/);
  assert.equal(t.manifeste().status, 'partial'); assert.ok(t.membres.every(m => m.deleted === 1));
  await t.run('cleanup'); assert.equal(t.manifeste().status, 'cleaned'); assert.ok(t.membres.every(m => m.deleted === 1));
});
test('manifeste altéré global ou dixième membre : aucun appel réseau ni suppression partielle', async () => {
  for (const cas of ['duplicate', 'extra', 'member', 'unknown-file']) {
    const t = banc(); await t.run('prepare'); const m = t.manifeste();
    if (cas === 'duplicate') m.membres[9] = m.membres[0];
    if (cas === 'extra') m.membres.push(m.membres[0]);
    if (cas === 'member') writeFileSync(`${t.env.LOAD_DASHBOARD_MANIFEST}.members/9.json`, '{}');
    if (cas === 'unknown-file') writeFileSync(`${t.env.LOAD_DASHBOARD_MANIFEST}.members/10.json`, '{}');
    writeFileSync(t.env.LOAD_DASHBOARD_MANIFEST, JSON.stringify(m));
    const n = t.calls.length; await assert.rejects(t.run('cleanup')); assert.equal(t.calls.length, n);
    assert.ok(t.membres.every(m => m.deleted === 0));
  }
});
test('mode workflow sans charge garde prepare/cleanup et le verrou staging, aucun k6 dans ce mode', () => {
  const w = readFileSync(new URL('../../.github/workflows/load-tests.yml', import.meta.url), 'utf8');
  assert.match(w, /group: jolene-supabase-staging-writes/); assert.match(w, /cancel-in-progress: false/);
  assert.match(w, /- name: Run scenario\n\s+if: \$\{\{ !inputs.dashboard_fixture_only \}\}/);
  assert.match(w, /if: always\(\) && \(inputs.scenario == '05-dashboard-concurrent' \|\| inputs.scenario == 'all'\)/);
  assert.match(w, /prepare-dashboard-pool.mjs prepare/); assert.match(w, /prepare-dashboard-pool.mjs cleanup/);
});

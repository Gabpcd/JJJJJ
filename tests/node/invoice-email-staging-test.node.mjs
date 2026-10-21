import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';
import { webcrypto, createHash } from 'node:crypto';

const require = createRequire(import.meta.url);
const ts = require('typescript');
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = path => readFileSync(`${ROOT}/${path}`, 'utf8');
const compile = (source, module = ts.ModuleKind.ESNext) => {
  const result = ts.transpileModule(source, { compilerOptions: { module, target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true });
  assert.deepEqual(result.diagnostics, []);
  return result.outputText;
};
const asUrl = source => `data:text/javascript;base64,${Buffer.from(compile(source)).toString('base64')}`;
const h = await import(asUrl(read('supabase/functions/_shared/invoice-email-staging-test.ts')));
const E = 'fcaa6c97-46c1-4da9-8f74-1395aed616c5', S = 'abba3c93-5408-47bf-96e3-0864c7de3cb7';
const M = 'f1660000-0000-4000-8000-000000000001', F = 'f1660000-0000-4000-8000-000000000002';
const H = 'f1660000-0000-4000-8000-000000000006';
const OWNER = 'connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915';
const Q = ['f1660000-0000-4000-8000-000000000003', 'f1660000-0000-4000-8000-000000000004', 'f1660000-0000-4000-8000-000000000005'];
const SCOPES = [['HONORAIRES', 'SOIGNANT', S, H], ['HONORAIRES', 'ETABLISSEMENT', E, H], ['COMMISSION', 'ETABLISSEMENT', E, F]];
const KEYS = [`facture-emise-soignant:${H}`, `facture-emise-etablissement:${H}`, `facture-emise-commission:${F}:${E}`];
const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';

async function fixture(isolated = false) {
  const S = isolated ? '1de96e4c-9be8-4897-a5bb-7640c05d5706' : 'abba3c93-5408-47bf-96e3-0864c7de3cb7';
  const M = isolated ? '6bf15d0e-e2a0-4fd7-a903-767679b280bb' : 'f1660000-0000-4000-8000-000000000001';
  const SCOPES = [['HONORAIRES', 'SOIGNANT', S, H], ['HONORAIRES', 'ETABLISSEMENT', E, H], ['COMMISSION', 'ETABLISSEMENT', E, F]];
  const calls = [], mutations = [], ledger = new Map(), provider = new Map(), posts = [];
  const users = Object.fromEntries([[E, 'ADMIN_ETABLISSEMENT'], [S, 'SOIGNANT']].map(([id, role]) => [id, {
    id, email_confirmed_at: '2026-10-16T00:00:00Z', app_metadata: { role, est_compte_test: true,
      jolene_connect_fixture_owner: OWNER, ...(id === E ? { etablissement_id: E } : {}) },
  }]));
  const bodies = SCOPES.map(([family, role, recipient, document]) => ({ type: 'FACTURE_EMISE', destinataire_id: recipient, data: {
    facture_id: document, famille_document: family, destinataire_role: role, numero: 'SYNTHETIC-ONLY',
    mission_id: M, etablissement_id: E, soignant_id: S,
    montant_ht: '14.52', montant_tva: '2.90', montant_ttc: '17.42', montant_avoirs_imputes: '0.00', montant_a_payer: '17.42',
    mode_paiement: null, date_echeance: '31/10/2026',
  } }));
  const now = Date.now();
  const config = { serverSha: 'a'.repeat(40), manifestSha256: 'b'.repeat(64), missionId: M, honorairesId: H, commissionId: F,
    createdAt: new Date(now - 1000).toISOString(), expiresAt: new Date(now + 59 * 60_000).toISOString(),
    events: await Promise.all(bodies.map(async (body, i) => ({ family: body.data.famille_document,
      recipientRole: body.data.destinataire_role, emailId: Q[i], bodySha256: await h.invoiceEmailBodySha256(body) }))),
  };
  const env = { SUPABASE_URL: STAGE, SUPABASE_ENV: 'staging', APP_URL: 'http://127.0.0.1:8085', SUPABASE_ANON_KEY: 'SYNTHETIC_ANON',
    SUPABASE_SERVICE_ROLE_KEY: 'SYNTHETIC_SERVICE', RESEND_API_KEY: 'SYNTHETIC_PROVIDER',
    INVOICE_EMAIL_STAGING_TEST_RUN: JSON.stringify(config) };
  const rows = {
    etablissements: [{ id: E, est_compte_test: true, supprime_le: null }],
    soignants: [{ id: S, est_compte_test: true, supprime_le: null }],
    factures: [{ id: F, etablissement_id: E, mission_id: M, facture_honoraire_id: H, type_document: 'FACTURE', statut: 'EMISE',
      stripe_payment_intent_id: null, date_paiement: null }],
    factures_honoraires: [{ id: H, etablissement_id: E, soignant_id: S, mission_id: M, type_document: 'FACTURE',
      nature_correction: 'ORIGINALE', statut: 'EMISE', est_facture_finale_mission: true, pdf_s3_key: 'synthetic.pdf',
      facturx_xml_url: 'synthetic.xml', emise_le: '2026-10-20T00:00:00Z', stripe_payment_intent_id: null, date_paiement: null }],
    missions: [{ id: M, etablissement_id: E, soignant_assigne_id: S, type_contrat_applique: 'LIBERAL', statut: 'TERMINEE' }],
    email_queue: bodies.map((body, i) => ({ id: Q[i], type: 'FACTURATION_DOCUMENT', destinataire_id: body.destinataire_id,
      data: structuredClone(body), statut: 'EN_ATTENTE' })),
    journaux_audit: [], preferences_notifications: [],
    // Ancre explicite de l'opérateur après preuve privée vierge, jamais un succès.
    emails_envoyes: bodies.map((body, i) => ({ type: body.type, destinataire_id: body.destinataire_id,
      destinataire_email: 'gabrielle@jolene.app', idempotency_key: KEYS[i], sujet: '[TEST] Ancre de tentative de transport',
      statut: 'ERREUR', provider_id: null, cree_le: new Date(now - 1000).toISOString() })),
  };
  const state = { preference: true, loseProviderResponse: false, classificationError: false };
  const sb = {
    auth: { async getUser(token) { return { data: { user: token === 'SYNTHETIC_USER' ? users[E] : null }, error: null }; },
      admin: { async getUserById(id) { calls.push(`auth:${id}`); return { data: { user: structuredClone(users[id]) }, error: null }; } } },
    from(table) {
      assert.ok(rows[table], `table inconnue ${table}`); calls.push(`read:${table}`);
      const filters = []; let limit = Infinity, write;
      const result = () => ({ data: structuredClone(rows[table].filter(row => filters.every(f => f(row))).slice(0, limit)), error: null });
      const q = { select() { return q; }, eq(k, v) { filters.push(row => row[k] === v); return q; },
        neq(k, v) { filters.push(row => row[k] !== v); return q; }, limit(n) { limit = n; return q; },
        insert(value) { write = value; mutations.push(`insert:${table}`); return q; },
        upsert(value) {
          write = value; mutations.push(`upsert:${table}`);
          if (table === 'emails_envoyes') {
            const old = rows[table].find(row => row.idempotency_key === value.idempotency_key);
            if (old) Object.assign(old, structuredClone(value));
            else rows[table].push({ ...structuredClone(value), cree_le: new Date().toISOString() });
          }
          return q;
        },
        async single() { const r = result(); return { data: r.data.length === 1 ? r.data[0] : null, error: r.data.length === 1 ? null : { message: 'synthetic missing' } }; },
        maybeSingle() { return q.single(); },
        then(yes, no) { return Promise.resolve(write ? { data: null, error: null } : result()).then(yes, no); } };
      return q;
    },
    async rpc(name, args) {
      calls.push(`rpc:${name}`);
      if (name === 'fn_lire_secret_cron') return { data: null, error: null };
      if (name === 'fn_reserver_envoi_email_idempotent') {
        const old = ledger.get(args.p_idempotency_key);
        if (old?.fingerprint !== undefined && old.fingerprint !== args.p_request_fingerprint) return { data: { statut: 'CONFLIT' }, error: null };
        if (old?.statut === 'ENVOYE') return { data: { statut: 'DEJA_ENVOYE' }, error: null };
        if (old?.statut === 'EN_COURS') return { data: { statut: 'EN_COURS' }, error: null };
        ledger.set(args.p_idempotency_key, { fingerprint: args.p_request_fingerprint, statut: 'EN_COURS' });
        state.afterReservation?.();
        return { data: { statut: 'RESERVE' }, error: null };
      }
      assert.equal(name, 'fn_finaliser_envoi_email_idempotent');
      const entry = ledger.get(args.p_idempotency_key);
      assert.equal(entry.fingerprint, args.p_request_fingerprint);
      entry.statut = args.p_succes ? 'ENVOYE' : 'ERREUR';
      return { data: null, error: null };
    },
  };
  const requestBody = (index = 0) => ({ ...structuredClone(bodies[index]), idempotency_key:
    KEYS[index] });
  return { calls, mutations, ledger, provider, posts, state, sb, rows, users, config, env, requestBody,
    admit(body = requestBody(), service = true) { return h.admitStagingInvoiceEmail(sb, body, service, key => env[key]); },
    configure(change) { change(config); env.INVOICE_EMAIL_STAGING_TEST_RUN = JSON.stringify(config); } };
}

function handler(s) {
  let serve;
  const modules = {
    '../_shared/invoice-email-staging-test.ts': h,
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => s.sb },
    '../_shared/rate-limit.ts': { applyRateLimit: () => false, getClientIp: () => 'synthetic' },
    '../_shared/admin-auth.ts': { verifyAdminOrServiceRole: async () => ({ ok: true }) },
    '../_shared/preferences-alertes-email.ts': { verifierPreferencesEvenementsEmail: async () => { s.calls.push('preferences'); return s.state.preference; } },
    '../_shared/test-account.ts': { resolveOperationalTestAccount: async () => { s.calls.push('classification:recipient'); return s.state.classificationError ? { ok: false } : { ok: true, isTest: true }; },
      resolveOperationalTestSource: async () => ({ ok: true, isTest: true }) },
    '../_shared/facturation-email-source.ts': { resolveFacturationEmailSource: async () => { s.calls.push('classification:source'); return { ok: true, isTest: true }; } },
    '../_shared/commission-email.ts': { aSoldeCommissionEmail: () => true, montantsCommissionEmail: () => '17.42 EUR',
      verifierSoldeCommissionEmail: async () => { s.calls.push('solde'); } },
  };
  const exports = {};
  runInNewContext(compile(read('supabase/functions/send-email/index.ts'), ts.ModuleKind.CommonJS), {
    exports, require: name => { assert.ok(modules[name], `import inconnu ${name}`); return modules[name]; },
    Deno: { env: { get: key => s.env[key] }, serve: value => { serve = value; } },
    Request, Response, Headers, TextEncoder, Uint8Array, crypto: webcrypto, Date, AbortSignal,
    console: { log() {}, warn() {}, error() {} },
    fetch: async (url, options) => {
      assert.equal(url, 'https://api.resend.com/emails');
      const key = options.headers['Idempotency-Key'], body = JSON.parse(options.body);
      s.posts.push({ key, body });
      if (s.provider.has(key)) assert.deepEqual(s.provider.get(key), body);
      else s.provider.set(key, body);
      if (s.state.loseProviderResponse) { s.state.loseProviderResponse = false; throw Error('synthetic interrupted response'); }
      return new Response(JSON.stringify({ id: 'synthetic-provider-id' }), { status: 200 });
    },
  });
  return (index = 0, token = 'SYNTHETIC_SERVICE', body = s.requestBody(index)) => serve(new Request(`${STAGE}/functions/v1/send-email`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }));
}

test('sans capacité et appel utilisateur : aucune admission ni lecture', async () => {
  const s = await fixture(); delete s.env.INVOICE_EMAIL_STAGING_TEST_RUN;
  assert.equal(await s.admit(), null); assert.equal(await s.admit(s.requestBody(), false), null); assert.deepEqual(s.calls, []);
});
test('trois émissions exactes de deux pièces : lecture seule, une adresse autorisée', async () => {
  const s = await fixture(); for (let i = 0; i < 3; i++) assert.deepEqual(await s.admit(s.requestBody(i)), { recipient: 'gabrielle@jolene.app' });
  assert.deepEqual(s.mutations, []); assert.equal(s.calls.some(x => x.startsWith('rpc:')), false);
});
test('SHA du corps canonique : clés triées, ordre des tableaux conservé', async () => {
  const expected = createHash('sha256').update('{"a":{"b":1,"c":2},"z":[{"x":0,"y":1}]}').digest('hex');
  assert.equal(await h.invoiceEmailBodySha256({ z: [{ y: 1, x: 0 }], a: { c: 2, b: 1 } }), expected);
});
for (const [label, change] of [
  ['JSON invalide', s => { s.env.INVOICE_EMAIL_STAGING_TEST_RUN = '{'; }],
  ['PROD', s => { s.env.SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
  ['environnement production', s => { s.env.SUPABASE_ENV = 'production'; }],
  ['APP_URL absent', s => { delete s.env.APP_URL; }],
  ['APP_URL production', s => { s.env.APP_URL = 'https://jolene.app'; }],
  ['génération encore ouverte', s => { s.env.HONORAIRES_STAGING_TEST_RUN = '{}'; }],
  ['paiement encore ouvert', s => { s.env.INVOICE_STAGING_TEST_RUN = '{}'; }],
  ['Connect encore ouvert', s => { s.env.CONNECT_STAGING_TEST_RUN = '{}'; }],
  ['SMS encore ouvert', s => { s.env.SIGNATURE_SMS_STAGING_TEST_RUN = '{}'; }],
  ['plus de 60 min', s => s.configure(c => { c.expiresAt = new Date(Date.parse(c.createdAt) + 3_600_001).toISOString(); })],
  ['expiration', s => s.configure(c => { c.createdAt = new Date(Date.now() - 3600_000).toISOString(); c.expiresAt = new Date(Date.now() - 1000).toISOString(); })],
  ['création future', s => s.configure(c => { c.createdAt = new Date(Date.now() + 60_000).toISOString(); })],
  ['clé config supplémentaire', s => s.configure(c => { c.recipient = 'foreign@example.invalid'; })],
  ['quatrième événement', s => s.configure(c => c.events.push(c.events[0]))],
  ['file dupliquée', s => s.configure(c => { c.events[1].emailId = c.events[0].emailId; })],
  ['pièce dupliquée', s => s.configure(c => { c.commissionId = c.honorairesId; })],
  ['famille permutée', s => s.configure(c => { c.events[0].family = 'COMMISSION'; })],
  ['rôle permuté', s => s.configure(c => { c.events[0].recipientRole = 'ETABLISSEMENT'; })],
  ['empreinte différente', s => s.configure(c => { c.events[0].bodySha256 = '0'.repeat(64); })],
  ['file absente', s => { s.rows.email_queue = []; }],
  ['autre destinataire de file', s => { s.rows.email_queue[0].destinataire_id = E; }],
  ['autre type de file', s => { s.rows.email_queue[0].type = 'FACTURE_EMISE'; }],
  ['corps de file modifié', s => { s.rows.email_queue[0].data.data.numero = 'FOREIGN'; }],
  ['file annulée', s => { s.rows.email_queue[0].statut = 'ANNULE'; }],
  ['file en erreur', s => { s.rows.email_queue[0].statut = 'ERREUR'; }],
  ['profil non TEST', s => { s.rows.soignants[0].est_compte_test = false; }],
  ['Auth non TEST', s => { s.users[E].app_metadata.est_compte_test = false; }],
  ['owner étranger', s => { s.users[S].app_metadata.jolene_connect_fixture_owner = 'FOREIGN'; }],
  ['compte supprimé', s => { s.users[S].deleted_at = '2026-10-18'; }],
  ['compte banni', s => { s.users[S].banned_until = new Date(Date.now() + 3600_000).toISOString(); }],
  ['autre soignant', s => { s.rows.missions[0].soignant_assigne_id = E; }],
  ['mission inachevée', s => { s.rows.missions[0].statut = 'EN_COURS'; }],
  ['mission salariée', s => { s.rows.missions[0].type_contrat_applique = 'SALARIE'; }],
  ['FH étrangère', s => { s.rows.factures_honoraires[0].mission_id = F; }],
  ['FH annulée', s => { s.rows.factures_honoraires[0].statut = 'ANNULEE'; }],
  ['FH payée', s => { s.rows.factures_honoraires[0].date_paiement = '2026-10-20'; }],
  ['FH en paiement', s => { s.rows.factures_honoraires[0].stripe_payment_intent_id = 'pi_Synthetic'; }],
  ['FH avoir', s => { s.rows.factures_honoraires[0].type_document = 'AVOIR'; }],
  ['FH corrigée', s => { s.rows.factures_honoraires[0].nature_correction = 'REMPLACEMENT'; }],
  ['FH intermédiaire', s => { s.rows.factures_honoraires[0].est_facture_finale_mission = false; }],
  ['FH sans PDF', s => { s.rows.factures_honoraires[0].pdf_s3_key = null; }],
  ['FH sans XML', s => { s.rows.factures_honoraires[0].facturx_xml_url = null; }],
  ['FH non émise', s => { s.rows.factures_honoraires[0].emise_le = null; }],
  ['commission non liée', s => { s.rows.factures[0].facture_honoraire_id = null; }],
  ['commission autre mission', s => { s.rows.factures[0].mission_id = H; }],
  ['commission annulée', s => { s.rows.factures[0].statut = 'ANNULEE'; }],
  ['commission avoir', s => { s.rows.factures[0].type_document = 'AVOIR'; }],
  ['commission payée', s => { s.rows.factures[0].date_paiement = '2026-10-20'; }],
  ['ancre absente', s => { s.rows.emails_envoyes = []; }],
  ['autre clé ancre', s => { s.rows.emails_envoyes[0].idempotency_key += ':foreign'; }],
  ['autre destinataire ancre', s => { s.rows.emails_envoyes[0].destinataire_id = E; }],
  ['autre email ancre', s => { s.rows.emails_envoyes[0].destinataire_email = 'foreign@example.invalid'; }],
  ['autre type ancre', s => { s.rows.emails_envoyes[0].type = 'FACTURE_PAYEE'; }],
  ['date ancre absente', s => { s.rows.emails_envoyes[0].cree_le = null; }],
  ['date ancre invalide', s => { s.rows.emails_envoyes[0].cree_le = 'invalid'; }],
  ['ancre future', s => { s.rows.emails_envoyes[0].cree_le = new Date(Date.now() + 60_000).toISOString(); }],
  ['ancre expirée', s => { s.rows.emails_envoyes[0].cree_le = new Date(Date.now() - 20 * 3600_000).toISOString(); }],
]) test(`ferme ${label}`, async () => { const s = await fixture(); change(s); await assert.rejects(() => s.admit()); assert.equal(s.posts.length, 0); });

for (const [label, change] of [
  ['destinataire arbitraire', b => { b.destinataire_id = M; }],
  ['adresse dans payload', b => { b.destinataire_email = 'foreign@example.invalid'; }],
  ['autre facture', b => { b.data.facture_id = M; }],
  ['autre mission', b => { b.data.mission_id = F; }],
  ['autre soignant déclaré', b => { b.data.soignant_id = E; }],
  ['commission au soignant', b => { b.data.famille_document = 'COMMISSION'; }],
  ['clé nouvelle', b => { b.idempotency_key += ':retry'; }],
]) test(`refuse requête ${label}`, async () => { const s = await fixture(), b = s.requestBody(); change(b); await assert.rejects(() => s.admit(b)); });
test('aucune admission pour une confirmation de paiement', async () => {
  const s = await fixture(), b = s.requestBody(); b.type = 'FACTURE_PAYEE';
  assert.equal(await s.admit(b), null); assert.deepEqual(s.calls, []);
});
test('vrai handler : trois émissions, mêmes clés/empreintes au rejeu', async () => {
  const s = await fixture(), invoke = handler(s);
  for (let i = 0; i < 3; i++) { const res = await invoke(i); assert.equal(res.status, 200); assert.deepEqual(await res.json(), { success: true }); }
  assert.equal(s.posts.length, 3); assert.equal(s.provider.size, 3);
  for (const post of s.posts) { assert.deepEqual(post.body.to, ['gabrielle@jolene.app']); assert.match(post.body.subject, /^\[TEST\]/); assert.match(post.body.html, /RECETTE TEST/); }
  assert.match(s.posts[0].body.html, /http:\/\/127\.0\.0\.1:8085\/soignant\/mes-gains/);
  for (const post of s.posts.slice(1)) assert.match(post.body.html, /http:\/\/127\.0\.0\.1:8085\/etablissement\/facturation/);
  const before = structuredClone([...s.ledger]);
  for (let i = 0; i < 3; i++) { const res = await invoke(i); assert.equal(res.status, 200); assert.equal((await res.json()).reason, 'idempotency_already_sent'); }
  assert.equal(s.posts.length, 3); assert.deepEqual([...s.ledger], before);
  assert.ok(s.calls.includes('classification:recipient')); assert.ok(s.calls.includes('classification:source'));
  assert.ok(s.calls.includes('solde'));
});
for (const [label, change, token, index = 0] of [
  ['sans capacité', s => { delete s.env.INVOICE_EMAIL_STAGING_TEST_RUN; }],
  ['capacité invalide', s => { s.env.INVOICE_EMAIL_STAGING_TEST_RUN = '{'; }],
  ['PROD', s => { s.env.SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
  ['utilisateur authentifié', () => {}, 'SYNTHETIC_USER'],
  ['classification indisponible', s => { s.state.classificationError = true; }],
  ['révocation juste avant transport', s => { s.state.afterReservation = () => { delete s.env.INVOICE_EMAIL_STAGING_TEST_RUN; }; }],
]) test(`vrai handler sans fournisseur : ${label}`, async () => { const s = await fixture(); change(s); const invoke = handler(s); await invoke(index, token); assert.equal(s.posts.length, 0); });
test('vrai handler : refus du conflit de fingerprint avant tout fournisseur', async () => {
  const s = await fixture(); s.ledger.set(s.requestBody().idempotency_key, { fingerprint: 'different', statut: 'ERREUR' });
  assert.equal((await handler(s)()).status, 409); assert.equal(s.posts.length, 0);
});
test('vrai handler : résultat fournisseur interrompu, reprise même clé/corps sans deuxième livraison simulée', async () => {
  const s = await fixture(), invoke = handler(s); s.state.loseProviderResponse = true;
  const created = s.rows.emails_envoyes[0].cree_le;
  assert.equal((await invoke()).status, 502); assert.equal((await invoke()).status, 200);
  assert.equal(s.posts.length, 2); assert.equal(s.provider.size, 1);
  assert.equal(s.posts[0].key, s.posts[1].key); assert.deepEqual(s.posts[0].body, s.posts[1].body);
  assert.equal(s.rows.emails_envoyes[0].cree_le, created);
});
test('contrôles de source sans ancre : aucune admission ni création implicite', async () => {
  const s = await fixture(); s.rows.emails_envoyes = [];
  const scope = await h.stagingInvoiceEmailScope(s.sb, s.requestBody(), true, key => s.env[key]);
  assert.equal(scope.emailId, Q[0]); assert.equal(scope.key, s.requestBody().idempotency_key);
  await assert.rejects(() => s.admit()); assert.deepEqual(s.mutations, []);
  assert.equal(s.rows.emails_envoyes.length, 0);
});
test('admission concurrente et double relecture : ancre serveur conservée, aucune mutation', async () => {
  const s = await fixture(), before = structuredClone(s.rows.emails_envoyes);
  await Promise.all([s.admit(), s.admit()]);
  await s.admit(); assert.deepEqual(s.rows.emails_envoyes, before); assert.deepEqual(s.mutations, []);
});
test('nouvelle capacité : reprise ambiguë à 19 h, même clé et origine temporelle conservées', async () => {
  const s = await fixture(), invoke = handler(s); s.state.loseProviderResponse = true;
  assert.equal((await invoke()).status, 502);
  // Passage du temps simulé côté base ; aucune date ne vient du payload client.
  const first = new Date(Date.now() - 19 * 3600_000).toISOString(); s.rows.emails_envoyes[0].cree_le = first;
  s.configure(c => { c.createdAt = new Date(Date.now() - 100).toISOString(); c.expiresAt = new Date(Date.now() + 59 * 60_000).toISOString(); c.manifestSha256 = 'c'.repeat(64); });
  assert.equal((await invoke()).status, 200);
  assert.equal(s.provider.size, 1); assert.equal(s.posts.length, 2);
  assert.equal(s.posts[0].key, s.posts[1].key); assert.deepEqual(s.posts[0].body, s.posts[1].body);
  assert.equal(s.rows.emails_envoyes[0].cree_le, first);
});
test('régression P2 : réponse Resend perdue, nouvelle capacité après 21 h refusée avant réservation', async () => {
  const s = await fixture(), invoke = handler(s); s.state.loseProviderResponse = true;
  assert.equal((await invoke()).status, 502);
  assert.equal(s.ledger.get(s.requestBody().idempotency_key).statut, 'ERREUR');
  assert.equal(s.rows.email_queue[0].statut, 'EN_ATTENTE');
  const first = new Date(Date.now() - 21 * 3600_000).toISOString(); s.rows.emails_envoyes[0].cree_le = first;
  s.configure(c => { c.createdAt = new Date(Date.now() - 100).toISOString(); c.expiresAt = new Date(Date.now() + 59 * 60_000).toISOString(); c.manifestSha256 = 'd'.repeat(64); });
  const reserved = s.calls.filter(x => x === 'rpc:fn_reserver_envoi_email_idempotent').length;
  assert.equal((await invoke()).status, 500);
  assert.equal(s.calls.filter(x => x === 'rpc:fn_reserver_envoi_email_idempotent').length, reserved);
  assert.equal(s.posts.length, 1); assert.equal(s.provider.size, 1);
  assert.equal(s.rows.emails_envoyes[0].cree_le, first);
  assert.equal(s.ledger.get(s.requestBody().idempotency_key).statut, 'ERREUR');
});
test('ambiguïté historique sans ancre : capacité renouvelée ne recrée aucune origine', async () => {
  const s = await fixture(), invoke = handler(s); s.state.loseProviderResponse = true;
  assert.equal((await invoke()).status, 502); s.rows.emails_envoyes = [];
  s.configure(c => { c.createdAt = new Date(Date.now() - 100).toISOString(); c.manifestSha256 = 'e'.repeat(64); });
  const calls = s.calls.length; assert.equal((await invoke()).status, 500);
  assert.equal(s.posts.length, 1); assert.equal(s.rows.emails_envoyes.length, 0);
  assert.equal(s.calls.slice(calls).includes('rpc:fn_reserver_envoi_email_idempotent'), false);
});
test('vrai handler concurrent : même ancre et ledger, au plus une livraison simulée', async () => {
  const s = await fixture(), invoke = handler(s), first = s.rows.emails_envoyes[0].cree_le;
  const results = await Promise.all([invoke(), invoke()]);
  assert.ok(results.every(result => [200, 202].includes(result.status)));
  assert.equal(s.posts.length, 1); assert.equal(s.provider.size, 1);
  assert.equal(s.rows.emails_envoyes.filter(row => row.idempotency_key === KEYS[0]).length, 1);
  assert.equal(s.rows.emails_envoyes[0].cree_le, first);
});

// Cohorte isolée : transport synthétique uniquement, aucun appel externe.
const ISOLATED_S = '1de96e4c-9be8-4897-a5bb-7640c05d5706', ISOLATED_M = '6bf15d0e-e2a0-4fd7-a903-767679b280bb';
const isolatedClock = t => t.mock.method(Date, 'now', () => Date.parse('2026-10-21T12:00:00.000Z'));
test('tuple TEST isolé exact : les trois émissions et le destinataire restent bornés', async t => {
  isolatedClock(t); const s = await fixture(true), invoke = handler(s);
  for (let i = 0; i < 3; i++) assert.equal((await invoke(i)).status, 200);
  assert.equal(s.posts.length, 3); assert.equal(s.provider.size, 3);
  for (const post of s.posts) assert.deepEqual(post.body.to, ['gabrielle@jolene.app']);
});
for (const [label, change] of [
  ['échéance absolue dépassée', s => s.configure(c => { c.createdAt = '2026-10-21T23:45:00.000Z'; c.expiresAt = '2026-10-22T00:15:00.000Z'; })],
  ['ancien soignant substitué', s => { s.rows.missions[0].soignant_assigne_id = S; }],
  ['autre mission avec le nouvel acteur', s => { s.rows.missions[0].id = M; }],
  ['owner étranger sur nouvel acteur', s => { s.users[ISOLATED_S].app_metadata.jolene_connect_fixture_owner = 'FOREIGN'; }],
  ['capacité de génération encore ouverte', s => { s.env.HONORAIRES_STAGING_TEST_RUN = '{}'; }],
  ['PROD avec tuple isolé', s => { s.env.SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
]) test(`tuple isolé fermé : ${label}`, async t => {
  isolatedClock(t); const s = await fixture(true); change(s);
  await assert.rejects(() => s.admit()); assert.equal(s.posts.length, 0);
});
test('tuple isolé : borne absolue testée sans ambiguïté avec une capacité de moins de 60 min', async t => {
  t.mock.method(Date, 'now', () => Date.parse('2026-10-21T23:50:00.000Z'));
  const s = await fixture(true); s.configure(c => { c.createdAt = '2026-10-21T23:45:00.000Z'; c.expiresAt = '2026-10-22T00:15:00.000Z'; });
  assert.throws(() => h.invoiceEmailStagingConfig(key => s.env[key])); assert.deepEqual(s.calls, []);
});
test('tuple isolé : actor et mission ne sont pas des paramètres de runtime extensibles', async t => {
  isolatedClock(t); const s = await fixture(true); s.configure(c => { c.soignantId = ISOLATED_S; });
  assert.throws(() => h.invoiceEmailStagingConfig(key => s.env[key])); assert.deepEqual(s.calls, []);
});

for (const [label, change, token] of [
  ['credential incorrect', () => {}, 'SYNTHETIC_WRONG_CREDENTIAL'],
  ['projet PROD', s => { s.env.SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
  ['expiration atteinte', s => s.configure(c => { c.expiresAt = new Date(Date.now()).toISOString(); })],
  ['profil non TEST', s => { s.rows.soignants[0].est_compte_test = false; }],
  ['ancien soignant dans la mission', s => { s.rows.missions[0].soignant_assigne_id = S; }],
  ['autre adresse dans l’ancre', s => { s.rows.emails_envoyes[0].destinataire_email = 'foreign@example.invalid'; }],
]) test(`handler isolé fermé avant réservation/fournisseur : ${label}`, async t => {
  isolatedClock(t); const s = await fixture(true); change(s);
  await handler(s)(0, token); assert.equal(s.posts.length, 0); assert.equal(s.ledger.size, 0);
});
for (const [label, change] of [
  ['ancien soignant destinataire', b => { b.destinataire_id = S; }],
  ['autre mission', b => { b.data.mission_id = M; }],
  ['autre soignant dans le corps', b => { b.data.soignant_id = S; }],
  ['adresse arbitraire', b => { b.destinataire_email = 'foreign@example.invalid'; }],
  ['autre facture', b => { b.data.facture_id = M; }],
]) test(`handler isolé refuse la substitution : ${label}`, async t => {
  isolatedClock(t); const s = await fixture(true), body = s.requestBody(); change(body);
  await handler(s)(0, 'SYNTHETIC_SERVICE', body);
  assert.equal(s.posts.length, 0); assert.equal(s.ledger.size, 0);
});
test('tuple isolé : borne de fin de journée exacte, puis expiration refusée sans lecture', async t => {
  const now = Date.parse('2026-10-21T23:50:00.000Z'); t.mock.method(Date, 'now', () => now);
  const s = await fixture(true);
  s.configure(c => { c.createdAt = '2026-10-21T23:49:59.000Z'; c.expiresAt = '2026-10-21T23:59:59.000Z'; });
  assert.ok(h.invoiceEmailStagingConfig(key => s.env[key]));
  s.configure(c => { c.expiresAt = '2026-10-21T23:59:59.001Z'; });
  assert.throws(() => h.invoiceEmailStagingConfig(key => s.env[key])); assert.deepEqual(s.calls, []);
});

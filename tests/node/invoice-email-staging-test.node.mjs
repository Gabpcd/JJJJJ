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
const balanceUrl = asUrl(read('supabase/functions/_shared/commission-balance.ts'));
const scopeUrl = asUrl(read('supabase/functions/_shared/stripe-invoice-staging-test.ts').replace('./commission-balance.ts', balanceUrl));
const h = await import(asUrl(read('supabase/functions/_shared/invoice-email-staging-test.ts').replace('./stripe-invoice-staging-test.ts', scopeUrl)));
const E = 'fcaa6c97-46c1-4da9-8f74-1395aed616c5', S = 'abba3c93-5408-47bf-96e3-0864c7de3cb7';
const M = 'f1660000-0000-4000-8000-000000000001', F = 'f1660000-0000-4000-8000-000000000002';
const OWNER = 'connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915';
const Q = ['f1660000-0000-4000-8000-000000000003', 'f1660000-0000-4000-8000-000000000004'];
const TYPES = ['FACTURE_EMISE', 'FACTURE_PAYEE'];
const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';

async function fixture() {
  const calls = [], mutations = [], ledger = new Map(), provider = new Map(), posts = [];
  const users = Object.fromEntries([[E, 'ADMIN_ETABLISSEMENT'], [S, 'SOIGNANT']].map(([id, role]) => [id, {
    id, email_confirmed_at: '2026-10-16T00:00:00Z', app_metadata: { role, est_compte_test: true,
      jolene_connect_fixture_owner: OWNER, ...(id === E ? { etablissement_id: E } : {}) },
  }]));
  const bodies = TYPES.map((type, i) => ({ type, destinataire_id: E, data: {
    facture_id: F, famille_document: 'COMMISSION', destinataire_role: 'ETABLISSEMENT', numero: 'SYNTHETIC-ONLY',
    montant_ht: '14.52', montant_tva: '2.90', montant_ttc: '17.42', montant_avoirs_imputes: '0.00', montant_a_payer: '17.42',
    mode_paiement: null, date_echeance: '31/10/2026', ...(i ? { date_paiement: '19/10/2026',
      stripe_payment_intent_id: 'pi_Synthetic', stripe_checkout_session_id: 'cs_test_Synthetic' } : {}),
  } }));
  const now = Date.now();
  const config = { serverSha: 'a'.repeat(40), manifestSha256: 'b'.repeat(64), missionId: M, factureId: F,
    createdAt: new Date(now - 1000).toISOString(), expiresAt: new Date(now + 59 * 60_000).toISOString(),
    events: await Promise.all(bodies.map(async (body, i) => ({ type: body.type, emailId: Q[i], bodySha256: await h.invoiceEmailBodySha256(body) }))),
  };
  const env = { SUPABASE_URL: STAGE, SUPABASE_ENV: 'staging', APP_URL: 'http://127.0.0.1:8085', SUPABASE_ANON_KEY: 'SYNTHETIC_ANON',
    SUPABASE_SERVICE_ROLE_KEY: 'SYNTHETIC_SERVICE', RESEND_API_KEY: 'SYNTHETIC_PROVIDER',
    INVOICE_EMAIL_STAGING_TEST_RUN: JSON.stringify(config) };
  const rows = {
    etablissements: [{ id: E, est_compte_test: true, supprime_le: null, stripe_customer_id: 'cus_VMjraPs5wJ1GBO' }],
    soignants: [{ id: S, est_compte_test: true, supprime_le: null, stripe_account_id: 'acct_1UM0NlI8RIUZoi0j' }],
    factures: [{ id: F, etablissement_id: E, mission_id: null, facture_honoraire_id: null, type_document: 'FACTURE', statut: 'PAYEE',
      nombre_missions: 1, montant_ht: 14.52, montant_tva: 2.90, montant_ttc: 17.42, montant_avoirs_imputes: 0,
      montant_a_payer: 17.42, rapprochement_paiement_requis: false, stripe_payment_intent_id: 'pi_Synthetic', date_paiement: '2026-10-19T09:00:00Z' }],
    missions: [{ id: M, etablissement_id: E, soignant_assigne_id: S, type_contrat_applique: 'SALARIE', statut: 'TERMINEE',
      facture_id: F, commission_facturee: true, montant_commission_ht: 14.52, montant_commission_tva: 2.90, montant_commission_ttc: 17.42 }],
    stripe_transfers: [],
    stripe_payment_flow_claims: [{ resource_key: `FACTURE:${F}`, flow: 'CHECKOUT_INVOICE', owner_token: `invoice:${F}`,
      stripe_checkout_session_id: 'cs_test_Synthetic', stripe_payment_intent_id: null }],
    email_queue: bodies.map((body, i) => ({ id: Q[i], type: 'FACTURATION_DOCUMENT', destinataire_id: E, data: structuredClone(body), statut: 'EN_ATTENTE' })),
    journaux_audit: [], emails_envoyes: [], preferences_notifications: [],
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
        upsert(value) { write = value; mutations.push(`upsert:${table}`); return q; },
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
    `${index ? 'facture-payee' : 'facture-emise'}-commission:${F}:${E}` });
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

test('absence et appel utilisateur ne créent aucune admission ni lecture', async () => {
  const s = await fixture(); delete s.env.INVOICE_EMAIL_STAGING_TEST_RUN;
  assert.equal(await s.admit(), null); assert.equal(await s.admit(s.requestBody(), false), null); assert.deepEqual(s.calls, []);
});
test('deux corps durables exacts : lectures seules, adresse unique fixée serveur', async () => {
  const s = await fixture(); for (let i = 0; i < 2; i++) assert.deepEqual(await s.admit(s.requestBody(i)), { recipient: 'gabrielle@jolene.app' });
  assert.deepEqual(s.mutations, []); assert.equal(s.calls.some(x => x.startsWith('rpc:')), false);
});
test('SHA du corps : JSON canonique JS, ordre des clés ignoré sans changer les tableaux', async () => {
  const expected = createHash('sha256').update('{"a":{"b":1,"c":2},"z":[{"x":0,"y":1}]}').digest('hex');
  assert.equal(await h.invoiceEmailBodySha256({ z: [{ y: 1, x: 0 }], a: { c: 2, b: 1 } }), expected);
});
for (const [label, change] of [
  ['JSON invalide', s => { s.env.INVOICE_EMAIL_STAGING_TEST_RUN = '{'; }],
  ['PROD', s => { s.env.SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
  ['environnement production', s => { s.env.SUPABASE_ENV = 'production'; }],
  ['APP_URL absent', s => { delete s.env.APP_URL; }],
  ['APP_URL production', s => { s.env.APP_URL = 'https://jolene.app'; }],
  ['durée supérieure à 60 min', s => s.configure(c => { c.expiresAt = new Date(Date.parse(c.createdAt) + 3_600_001).toISOString(); })],
  ['expiration', s => s.configure(c => { c.createdAt = new Date(Date.now() - 3600_000).toISOString(); c.expiresAt = new Date(Date.now() - 1000).toISOString(); })],
  ['création future', s => s.configure(c => { c.createdAt = new Date(Date.now() + 60_000).toISOString(); })],
  ['clé config supplémentaire', s => s.configure(c => { c.recipient = 'foreign@example.invalid'; })],
  ['événement en plus', s => s.configure(c => c.events.push(c.events[0]))],
  ['identité de file dupliquée', s => s.configure(c => { c.events[1].emailId = c.events[0].emailId; })],
  ['mauvais type configuré', s => s.configure(c => { c.events[0].type = 'AVOIR_EMIS'; })],
  ['empreinte différente', s => s.configure(c => { c.events[0].bodySha256 = '0'.repeat(64); })],
  ['file absente', s => { s.rows.email_queue = []; }],
  ['autre identifiant de file', s => { s.rows.email_queue[0].id = M; }],
  ['autre destinataire de file', s => { s.rows.email_queue[0].destinataire_id = S; }],
  ['autre type de file', s => { s.rows.email_queue[0].type = 'FACTURE_EMISE'; }],
  ['corps de file modifié', s => { s.rows.email_queue[0].data.data.numero = 'FOREIGN'; }],
  ['file annulée', s => { s.rows.email_queue[0].statut = 'ANNULE'; }],
  ['file en erreur', s => { s.rows.email_queue[0].statut = 'ERREUR'; }],
  ['profil non TEST', s => { s.rows.soignants[0].est_compte_test = false; }],
  ['Auth non TEST', s => { s.users[E].app_metadata.est_compte_test = false; }],
  ['owner étranger', s => { s.users[S].app_metadata.jolene_connect_fixture_owner = 'FOREIGN'; }],
  ['compte supprimé', s => { s.users[S].deleted_at = '2026-10-18'; }],
  ['autre mission', s => { s.rows.missions[0].soignant_assigne_id = E; }],
  ['mission inachevée', s => { s.rows.missions[0].statut = 'EN_COURS'; }],
  ['montant étranger', s => { s.rows.factures[0].montant_ttc = 17.43; }],
  ['plusieurs missions', s => { s.rows.factures[0].nombre_missions = 2; }],
  ['avoir imputé', s => { s.rows.factures[0].montant_avoirs_imputes = 1; }],
  ['trace Connect', s => { s.rows.stripe_transfers.push({ id: F, mission_id: M }); }],
]) test(`ferme ${label}`, async () => { const s = await fixture(); change(s); await assert.rejects(() => s.admit()); assert.equal(s.posts.length, 0); });

for (const [label, change] of [
  ['destinataire arbitraire', b => { b.destinataire_id = S; }],
  ['adresse dans payload', b => { b.destinataire_email = 'foreign@example.invalid'; }],
  ['autre facture', b => { b.data.facture_id = M; }],
  ['honoraires', b => { b.data.famille_document = 'HONORAIRES'; }],
  ['clé nouvelle', b => { b.idempotency_key += ':retry'; }],
]) test(`refuse requête ${label}`, async () => { const s = await fixture(), b = s.requestBody(); change(b); await assert.rejects(() => s.admit(b)); });
for (const [label, change] of [
  ['facture non payée', s => { s.rows.factures[0].statut = 'EMISE'; }],
  ['PI différent', s => { s.rows.factures[0].stripe_payment_intent_id = 'pi_Foreign'; }],
  ['Session LIVE', s => { s.rows.stripe_payment_flow_claims[0].stripe_checkout_session_id = 'cs_live_Foreign'; }],
  ['claim concurrent', s => { s.rows.stripe_payment_flow_claims[0].flow = 'SEPA_INVOICE'; }],
  ['claim absent', s => { s.rows.stripe_payment_flow_claims = []; }],
]) test(`confirmation ferme ${label}`, async () => { const s = await fixture(); change(s); await assert.rejects(() => s.admit(s.requestBody(1))); });

test('vrai handler : deux emails TEST, mêmes clés et empreintes lors du rejeu', async () => {
  const s = await fixture(), invoke = handler(s);
  for (let i = 0; i < 2; i++) { const res = await invoke(i); assert.equal(res.status, 200); assert.deepEqual(await res.json(), { success: true }); }
  assert.equal(s.posts.length, 2); assert.equal(s.provider.size, 2);
  for (const post of s.posts) { assert.deepEqual(post.body.to, ['gabrielle@jolene.app']); assert.match(post.body.subject, /^\[TEST\]/); assert.match(post.body.html, /RECETTE TEST/); }
  for (const post of s.posts) assert.match(post.body.html, /http:\/\/127\.0\.0\.1:8085\/etablissement\/facturation/);
  const before = structuredClone([...s.ledger]);
  for (let i = 0; i < 2; i++) { const res = await invoke(i); assert.equal(res.status, 200); assert.equal((await res.json()).reason, 'idempotency_already_sent'); }
  assert.equal(s.posts.length, 2); assert.deepEqual([...s.ledger], before);
  assert.ok(s.calls.includes('classification:recipient')); assert.ok(s.calls.includes('classification:source'));
  assert.ok(s.calls.includes('preferences')); assert.ok(s.calls.includes('solde'));
});
for (const [label, change, token, index = 0] of [
  ['sans capacité', s => { delete s.env.INVOICE_EMAIL_STAGING_TEST_RUN; }],
  ['capacité invalide', s => { s.env.INVOICE_EMAIL_STAGING_TEST_RUN = '{'; }],
  ['PROD', s => { s.env.SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co'; }],
  ['utilisateur authentifié', () => {}, 'SYNTHETIC_USER'],
  ['préférence paiement désactivée', s => { s.state.preference = false; }, undefined, 1],
  ['classification indisponible', s => { s.state.classificationError = true; }],
  ['révocation juste avant transport', s => { s.state.afterReservation = () => { delete s.env.INVOICE_EMAIL_STAGING_TEST_RUN; }; }],
]) test(`vrai handler sans fournisseur : ${label}`, async () => { const s = await fixture(); change(s); const invoke = handler(s); await invoke(index, token); assert.equal(s.posts.length, 0); });
test('vrai handler : refus du conflit de fingerprint avant tout fournisseur', async () => {
  const s = await fixture(); s.ledger.set(s.requestBody().idempotency_key, { fingerprint: 'different', statut: 'ERREUR' });
  assert.equal((await handler(s)()).status, 409); assert.equal(s.posts.length, 0);
});
test('vrai handler : résultat fournisseur interrompu, reprise même clé/corps sans deuxième livraison simulée', async () => {
  const s = await fixture(), invoke = handler(s); s.state.loseProviderResponse = true;
  assert.equal((await invoke()).status, 502); assert.equal((await invoke()).status, 200);
  assert.equal(s.posts.length, 2); assert.equal(s.provider.size, 1);
  assert.equal(s.posts[0].key, s.posts[1].key); assert.deepEqual(s.posts[0].body, s.posts[1].body);
});

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { CONTRACTS_STAGING_ORIGIN, MAX_CONTRACT_BYTES, canOfferSignature, exactUtf8, inspectOriginal, validContractStoragePath } from './business';
import { createContractOriginalTransport } from './originalTransport';
import { SupabaseContractGateway } from './supabaseGateway';
import type { ContractContext, ContractOriginalTransport, ContractSignature, StoredContractRecord } from './types';

// Transport doubles only. These tests never contact Supabase, Storage, Twilio or a phone.
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const userId = id(1), etabId = id(2), contractId = id(3), missionId = id(4), otherUser = id(5);
const now = Date.parse('2026-10-27T11:00:00Z'), date = new Date(now).toISOString();
const context: ContractContext = { kind: 'soignant', userId };
const html = '<!doctype html>\n<html lang="fr"><body>Contrat fictif — Éléonore 🩺\r\nAucune donnée réelle.</body></html>';
const digest = async (text: string) => createHash('sha256').update(text, 'utf8').digest('hex');
const hash = createHash('sha256').update(html, 'utf8').digest('hex');
const storagePath = `${contractId}/document-unit-test.html`;
const revision = { contractId, sha256: hash, storagePath };
const consent = () => ({ accepted: true as const, revision: { ...revision } });
const code = () => [1, 2, 3, 4, 5, 6].join('');
function fixture(): StoredContractRecord {
  return { id: contractId, mission_id: missionId, soignant_id: userId, etablissement_id: etabId,
    numero_contrat: 'TEST-UNIT-001', type_contrat: 'REMPLACEMENT_LIBERAL', statut: 'EN_ATTENTE_SIGNATURES', cree_le: date,
    signature_soignant: false, signature_soignant_le: null, signature_etablissement: false, signature_etablissement_le: null,
    contenu_html: html, hash_document: hash, storage_path: storagePath, contenu_html_rendu_le: date, mode_signature: null };
}
function proof(actor = userId, party: 'soignant' | 'etablissement' = 'soignant'): ContractSignature {
  return { id: id(6), contrat_id: contractId, signataire_user_id: actor, signataire_role: party,
    statut_signature: 'otp_envoye', signe_a: null, otp_valide_a: null, hash_document: null, cree_le: date };
}
interface Reply { data: any; error: unknown; count?: number | null }
interface Call { name: string; args?: any; operations: Array<[string, ...any[]]> }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => { resolve = done; }); return { promise, resolve }; }
function transport(options: { kind?: 'soignant' | 'etablissement'; lecture?: boolean; signPermission?: boolean; testAccount?: boolean;
  admission?: boolean; roleEtab?: string; resolvedEtab?: string; initialOtp?: boolean; record?: Partial<StoredContractRecord>;
  rejected?: string; lostResponse?: boolean; omitProof?: boolean; unreadableAfterWrite?: boolean;
  onAuth?: (state: any) => void; onOriginal?: (state: any) => void; beforeMutation?: () => Promise<void> } = {}) {
  const kind = options.kind ?? 'soignant'; const actor = kind === 'soignant' ? userId : otherUser;
  const ctx: ContractContext = kind === 'soignant' ? { kind, userId: actor } : { kind, userId: actor, etablissementId: etabId };
  const calls: Call[] = []; const storageCalls: Array<{ contractId: string; storagePath: string; authorization: string }> = [];
  const state = { userId: actor, token: 'unit-test-original-session', record: { ...fixture(), ...options.record },
    otp: options.initialOtp ?? true, signed: false, wrote: false, signature: proof(actor, kind) };
  const handle = async (call: Call): Promise<Reply> => {
    if (options.unreadableAfterWrite && state.wrote) return { data: null, error: 'unit-test-read-failure' };
    if (call.name === 'fn_get_my_role') return { data: { role: kind === 'soignant' ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT',
      user_id: actor, etablissement_id: kind === 'etablissement' ? options.roleEtab ?? etabId : null, parcours_incomplet: false }, error: null };
    if (call.name === 'fn_mes_permissions_etab') return { data: { success: true,
      etablissement_id: options.resolvedEtab ?? etabId, role: 'RH', permissions: { lecture: true, contrats: true } }, error: null };
    if (call.name === 'fn_a_permission_etablissement') return { data: call.args.p_permission === 'lecture_contrats'
      ? options.lecture !== false : options.signPermission !== false, error: null };
    if (call.name === 'soignants' || call.name === 'etablissements') return {
      data: { id: kind === 'soignant' ? actor : etabId, est_compte_test: options.testAccount !== false }, error: null };
    if (call.name === 'contrats_mission') {
      const single = call.operations.some(([op]) => op === 'maybeSingle');
      if (single) return { data: { ...state.record }, error: null };
      const start = call.operations.find(([op]) => op === 'range')?.[1] ?? 0;
      return { data: start === 0 ? [{ ...state.record }] : [], error: null, count: 1 };
    }
    if (call.name === 'signatures_contrats') {
      const values = options.omitProof || !state.otp ? [] : [{ ...state.signature }];
      return { data: values, error: null, count: values.length };
    }
    if (call.name === 'fn_contrat_storage_path') return { data: { success: true, storage_path: state.record.storage_path,
      hash_document: state.record.hash_document, rendu_le: state.record.contenu_html_rendu_le }, error: null };
    if (call.name === 'fn_admission_otp_signature_recette') return { data: options.admission === false ? { admitted: false } : {
      admitted: true, remaining: 1, can_send: true, can_validate: state.otp && !state.signed,
      expires_at: new Date(now + 30 * 60_000).toISOString(), otp_expires_at: state.otp && !state.signed ? new Date(now + 9 * 60_000).toISOString() : null,
    }, error: null };
    if (call.name === 'fn_envoyer_otp_signature' || call.name === 'fn_signer_contrat_otp') {
      await options.beforeMutation?.();
      if (options.rejected) return { data: { success: false, error_code: options.rejected, tentatives_restantes: 4,
        reset_le: new Date(now + 24 * 60 * 60_000).toISOString() }, error: null };
      state.wrote = true; state.otp = true;
      if (call.name === 'fn_signer_contrat_otp') {
        state.signed = true; state.signature = { ...state.signature, statut_signature: 'signe', signe_a: date, otp_valide_a: date, hash_document: hash };
        state.record = { ...state.record, [`signature_${kind}`]: true, [`signature_${kind}_le`]: date,
          statut: kind === 'soignant' ? 'SIGNE_SOIGNANT' : 'SIGNE_ETABLISSEMENT', mode_signature: 'JOLENE_OTP' };
      }
      return options.lostResponse ? { data: null, error: 'unit-test-response-lost-after-server-commit' }
        : { data: { success: true, role: kind, sms_envoyes: 1, sms_restants: 2, telephone_masked: '******00' }, error: null };
    }
    throw new Error(`Unexpected test transport call: ${call.name}`);
  };
  class Query implements PromiseLike<Reply> {
    constructor(private readonly call: Call) { calls.push(call); }
    op(name: string, ...args: any[]) { this.call.operations.push([name, ...args]); return this; }
    select(...args: any[]) { return this.op('select', ...args); } eq(...args: any[]) { return this.op('eq', ...args); }
    order(...args: any[]) { return this.op('order', ...args); } range(...args: any[]) { return this.op('range', ...args); }
    setHeader(...args: any[]) { return this.op('setHeader', ...args); } abortSignal(...args: any[]) { return this.op('abortSignal', ...args); }
    maybeSingle(...args: any[]) { return this.op('maybeSingle', ...args); }
    then<A = Reply, B = never>(fulfilled?: ((value: Reply) => A | PromiseLike<A>) | null,
      rejected?: ((reason: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
      return Promise.resolve().then(() => handle(this.call)).then(fulfilled, rejected);
    }
  }
  const client = { from: (name: string) => new Query({ name, operations: [] }),
    rpc: (name: string, args?: any) => new Query({ name, args, operations: [] }),
    auth: { getSession: async () => ({ data: { session: { access_token: state.token, user: { id: state.userId } } }, error: null }),
      getUser: async () => { options.onAuth?.(state); return { data: { user: { id: actor, email_confirmed_at: date } }, error: null }; } },
    storage: { from: () => ({ getPublicUrl: (path: string) => ({ data: {
      publicUrl: `${CONTRACTS_STAGING_ORIGIN}/storage/v1/object/public/contrats-signes/${path}` } }) }) },
  } as unknown as SupabaseClient;
  const originals: ContractOriginalTransport = { read: async input => {
    storageCalls.push({ contractId: input.contractId, storagePath: input.storagePath, authorization: input.authorization });
    options.onOriginal?.(state); return exactUtf8(html);
  } };
  return { gateway: new SupabaseContractGateway(client, originals, digest, () => now), calls, storageCalls, state, context: ctx };
}

test('original preserves exact UTF-8, line endings and byte identity; a storage mismatch cannot sign', async () => {
  assert.deepEqual(exactUtf8(html), new Uint8Array(Buffer.from(html, 'utf8')));
  const valid = await inspectOriginal(fixture(), [], digest, exactUtf8(html)); assert.equal(valid.original?.html, html);
  assert.equal(valid.original?.source, 'database-and-storage'); assert.equal(valid.originalIssue, null);
  assert.equal((await inspectOriginal(fixture(), [], digest, exactUtf8(html.replace('\r\n', '\n')))).originalIssue, 'hash_mismatch');
  assert.equal((await inspectOriginal({ ...fixture(), hash_document: 'a'.repeat(64) }, [], digest, exactUtf8(html))).originalIssue, 'hash_mismatch');
  assert.throws(() => exactUtf8('\ud800'), /encodage/); assert.throws(() => exactUtf8('\udc00'), /encodage/);
});

test('unrendered placeholders and inconsistent signed proofs remain unavailable', async () => {
  assert.equal((await inspectOriginal({ ...fixture(), contenu_html: '<p>{{ nom }}</p>' }, [], digest, exactUtf8(html))).originalIssue, 'incomplete');
  assert.equal((await inspectOriginal({ ...fixture(), storage_path: null }, [], digest, exactUtf8(html))).originalIssue, 'unprepared');
  assert.equal((await inspectOriginal(fixture(), [{ ...proof(), statut_signature: 'signe', signe_a: date,
    hash_document: 'b'.repeat(64) }], digest, exactUtf8(html))).originalIssue, 'signature_mismatch');
});

test('Storage GET uses the exact private object, fixed JWT and public key without signing a URL', async () => {
  const requests: Array<{ uri: string; options: RequestInit }> = [];
  const key = `sb_publishable_${'unit_test_public_'.repeat(3)}`;
  const fetcher: typeof fetch = async (uri, options) => {
    requests.push({ uri: String(uri), options: options! }); return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
  };
  const original = createContractOriginalTransport({ url: CONTRACTS_STAGING_ORIGIN, publishableKey: key }, fetcher);
  assert.deepEqual(await original.read({ contractId, storagePath, authorization: 'Bearer unit-test-jwt' }), exactUtf8(html));
  assert.equal(requests[0].uri, `${CONTRACTS_STAGING_ORIGIN}/storage/v1/object/contrats-signes/${storagePath}`);
  assert.deepEqual(requests[0].options.headers, { Authorization: 'Bearer unit-test-jwt', apikey: key, Accept: 'text/html' });
  assert.equal(requests[0].options.method, 'GET'); assert.equal(requests[0].options.redirect, 'error');
  for (const invalid of [`${contractId}/../x.html`, `${contractId}/x.html?token=x`, `${id(99)}/x.html`, `${contractId}/x.pdf`]) {
    assert.equal(validContractStoragePath(invalid, contractId), false);
    await assert.rejects(original.read({ contractId, storagePath: invalid, authorization: 'Bearer unit-test-jwt' }));
  }
  assert.equal(requests.length, 1);
  assert.throws(() => createContractOriginalTransport({ url: 'https://production.invalid', publishableKey: key }, fetcher));
});

test('Storage rejects redirects, wrong content type, oversized response and prior cancellation', async () => {
  const config = { url: CONTRACTS_STAGING_ORIGIN, publishableKey: `sb_publishable_${'unit_test_public_'.repeat(3)}` };
  for (const make of [() => new Response('oops', { headers: { 'content-type': 'application/json' } }),
    () => new Response(html, { headers: { 'content-type': 'text/html', 'content-length': String(MAX_CONTRACT_BYTES + 1) } }),
    () => Object.assign(new Response(html, { headers: { 'content-type': 'text/html' } }), {})]) {
    const response = make(); if (response.headers.get('content-type') === 'text/html' && !response.headers.has('content-length')) {
      Object.defineProperty(response, 'redirected', { value: true });
    }
    const gateway = createContractOriginalTransport(config, async () => response);
    await assert.rejects(gateway.read({ contractId, storagePath, authorization: 'Bearer unit-test-jwt' }), /original/);
  }
  let requests = 0; const controller = new AbortController(); controller.abort();
  const gateway = createContractOriginalTransport(config, async () => { requests++; return new Response(html); });
  await assert.rejects(gateway.read({ contractId, storagePath, authorization: 'Bearer unit-test-jwt', signal: controller.signal }), { name: 'AbortError' });
  assert.equal(requests, 0);
});

test('Supabase text/plain HTML is accepted only as original bytes, then checked against frozen HTML and SHA', async () => {
  const config = { url: CONTRACTS_STAGING_ORIGIN, publishableKey: `sb_publishable_${'unit_test_public_'.repeat(3)}` };
  const transport = createContractOriginalTransport(config, async () => new Response(html, { headers: { 'content-type': 'text/plain; charset=utf-8' } }));
  const bytes = await transport.read({ contractId, storagePath, authorization: 'Bearer unit-test-jwt' });
  assert.deepEqual(bytes, exactUtf8(html));
  assert.equal((await inspectOriginal(fixture(), [], digest, bytes)).original?.sha256, hash);
  const changed = createContractOriginalTransport(config, async () => new Response(`${html}\n`, { headers: { 'content-type': 'text/plain' } }));
  const changedBytes = await changed.read({ contractId, storagePath, authorization: 'Bearer unit-test-jwt' });
  assert.equal((await inspectOriginal(fixture(), [], digest, changedBytes)).originalIssue, 'hash_mismatch');
  assert.equal((await inspectOriginal({ ...fixture(), hash_document: 'c'.repeat(64) }, [], digest, bytes)).originalIssue, 'hash_mismatch');
});

test('establishment members list canonical establishment contracts, never contracts by auth user fallback', async () => {
  const f = transport({ kind: 'etablissement' }); const page = await f.gateway.list(f.context);
  assert.equal(page.total, 1); assert.equal(page.nextPage, null); assert.equal((await f.gateway.list(f.context, 1)).rows.length, 0);
  for (const call of f.calls.filter(call => call.name === 'contrats_mission')) {
    assert.ok(call.operations.some(op => op[0] === 'eq' && op[1] === 'etablissement_id' && op[2] === etabId));
    assert.ok(!call.operations.some(op => op[0] === 'eq' && op[2] === otherUser));
  }
  for (const options of [{ lecture: false }, { roleEtab: id(90) }, { resolvedEtab: id(91) }]) {
    const refused = transport({ kind: 'etablissement', ...options }); await assert.rejects(refused.gateway.list(refused.context));
    assert.equal(refused.calls.filter(call => call.name === 'contrats_mission').length, 0);
  }
});

test('general lecture cannot grant contract reading, and contract read permission does not grant signing', async () => {
  const f = transport({ kind: 'etablissement', signPermission: false }); const detail = await f.gateway.read(f.context, contractId);
  assert.ok(detail.original); assert.equal(detail.permissions.sign, false); assert.equal(canOfferSignature(detail), false);
  await assert.rejects(f.gateway.requestOtp(f.context, consent()), /signature n’est pas disponible/);
  assert.equal(f.calls.filter(call => call.name === 'fn_envoyer_otp_signature').length, 0);
});

test('all table and RPC requests pin the captured JWT even when its same-user refresh occurs during Storage', async () => {
  const f = transport({ onOriginal: state => { state.token = 'unit-test-refreshed-session'; } });
  const detail = await f.gateway.read(context, contractId); assert.ok(detail.original);
  assert.ok(f.calls.every(call => call.operations.some(op => op[0] === 'setHeader' && op[1] === 'Authorization' && op[2] === 'Bearer unit-test-original-session')));
  assert.equal(f.storageCalls[0].authorization, 'Bearer unit-test-original-session');
});

test('changed account before role lookup or during Storage discards the result and never mutates', async () => {
  const early = transport({ onAuth: state => { state.userId = otherUser; } });
  await assert.rejects(early.gateway.read(context, contractId), /session a changé/); assert.equal(early.calls.length, 0);
  const late = transport({ onOriginal: state => { state.userId = otherUser; } });
  await assert.rejects(late.gateway.sign(context, { ...consent(), code: code() }), /session a changé/);
  assert.equal(late.calls.filter(call => call.name === 'fn_signer_contrat_otp').length, 0);
});

test('unexpected owner and document revision changes during read fail closed', async () => {
  const owner = transport({ record: { soignant_id: otherUser } }); await assert.rejects(owner.gateway.read(context, contractId));
  assert.equal(owner.storageCalls.length, 0);
  const changed = transport({ onOriginal: state => { state.record = { ...state.record, contenu_html: `${html}\n` }; } });
  await assert.rejects(changed.gateway.read(context, contractId), /contrat a changé/);
});

test('OTP request is recorded only after public proof and admission reread; it never claims SMS delivery', async () => {
  const f = transport({ initialOtp: false }); const result = await f.gateway.requestOtp(context, consent());
  assert.equal(result.kind, 'queued'); assert.equal(result.delivery, 'unverified'); assert.equal(result.phoneMasked, '******00');
  assert.match(result.message, /réception n’est pas encore confirmée/); assert.ok(result.expiresAt! > now);
  const writes = f.calls.filter(call => call.name === 'fn_envoyer_otp_signature'); assert.equal(writes.length, 1);
  assert.deepEqual(writes[0].args, { p_contrat_id: contractId });
  const forbidden = new Set(['otp_code_hash', 'otp_envoye_a', 'otp_tentatives', 'sms_envoyes_count', 'sms_premier_envoi_a', 'ip_signature', 'user_agent']);
  for (const call of f.calls.filter(call => call.name === 'signatures_contrats')) {
    const projection = call.operations.find(([op]) => op === 'select')?.[1] as string;
    assert.ok(!projection.split(',').some(column => forbidden.has(column)));
  }
});

test('unknown OTP result is not retried and remains distinct from an explicit rate-limit rejection', async () => {
  const lost = transport({ lostResponse: true }); const result = await lost.gateway.requestOtp(context, consent());
  assert.equal(result.kind, 'unconfirmed'); assert.equal(result.delivery, 'unverified');
  assert.equal(lost.calls.filter(call => call.name === 'fn_envoyer_otp_signature').length, 1);
  const limited = transport({ rejected: 'TROP_DE_SMS' }); const rejection = await limited.gateway.requestOtp(context, consent());
  assert.equal(rejection.kind, 'rejected'); assert.equal(rejection.issue?.code, 'TROP_DE_SMS'); assert.ok(rejection.issue?.retryAt);
  assert.equal(limited.calls.filter(call => call.name === 'fn_envoyer_otp_signature').length, 1);
});

test('signature sends exact displayed hash and null image, then confirms own OTP proof and contract flags', async () => {
  const f = transport(); const result = await f.gateway.sign(context, { ...consent(), code: code() });
  assert.equal(result.kind, 'confirmed'); assert.equal(result.contract?.record.signature_soignant, true);
  const writes = f.calls.filter(call => call.name === 'fn_signer_contrat_otp'); assert.equal(writes.length, 1);
  assert.deepEqual(writes[0].args, { p_contrat_id: contractId, p_otp_code: code(), p_hash_document: hash, p_signature_image: null });
  assert.ok(writes[0].operations.some(op => op[0] === 'setHeader' && op[2] === 'Bearer unit-test-original-session'));
  assert.ok(!f.calls.some(call => /generer|generate|canvas|fn_signer_contrat$/.test(call.name)));
});

test('lost signature response can be confirmed by persisted proof; a readback error cannot be success', async () => {
  assert.equal((await transport({ lostResponse: true }).gateway.sign(context, { ...consent(), code: code() })).kind, 'confirmed');
  const unreadable = transport({ unreadableAfterWrite: true });
  assert.equal((await unreadable.gateway.sign(context, { ...consent(), code: code() })).kind, 'unconfirmed');
  assert.equal(unreadable.calls.filter(call => call.name === 'fn_signer_contrat_otp').length, 1);
  assert.equal((await transport({ omitProof: true }).gateway.sign(context, { ...consent(), code: code() })).kind, 'unconfirmed');
});

test('existing signatures including legacy canvas remain untouched and terminal/unknown statuses cannot sign', async () => {
  const signed = transport({ record: { signature_soignant: true, signature_soignant_le: date, statut: 'SIGNE_SOIGNANT', mode_signature: 'CANVAS' }, omitProof: true });
  assert.equal((await signed.gateway.sign(context, { ...consent(), code: code() })).kind, 'already_signed');
  assert.equal(signed.calls.filter(call => call.name === 'fn_signer_contrat_otp').length, 0);
  for (const statut of [null, 'REFUSE', 'ANNULE', 'EXPIRE', 'FUTURE_STATUS']) {
    const f = transport({ record: { statut } }); await assert.rejects(f.gateway.sign(context, { ...consent(), code: code() }), /signature n’est pas disponible/);
    assert.equal(f.calls.filter(call => call.name === 'fn_signer_contrat_otp').length, 0);
  }
});

test('real accounts and missing TEST admission cannot send SMS or sign', async () => {
  for (const options of [{ testAccount: false }, { admission: false }]) {
    const f = transport(options); await assert.rejects(f.gateway.requestOtp(context, consent()));
    await assert.rejects(f.gateway.sign(context, { ...consent(), code: code() }));
    assert.equal(f.calls.filter(call => ['fn_envoyer_otp_signature', 'fn_signer_contrat_otp'].includes(call.name)).length, 0);
  }
});

test('double tap is serialized; caller mutation cannot replace captured consent or account', async () => {
  const started = deferred<void>(), release = deferred<void>();
  const f = transport({ beforeMutation: async () => { started.resolve(); await release.promise; } });
  const input = { ...consent(), code: code() }; const callerContext: ContractContext = { ...context };
  const first = f.gateway.sign(callerContext, input);
  input.code = '000000'; input.revision.contractId = id(99); callerContext.userId = otherUser;
  await started.promise;
  await assert.rejects(f.gateway.sign(context, { ...consent(), code: code() }), /déjà en cours/);
  release.resolve(); assert.equal((await first).kind, 'confirmed');
  const mutation = f.calls.find(call => call.name === 'fn_signer_contrat_otp'); assert.equal(mutation?.args.p_contrat_id, contractId);
  assert.equal(mutation?.args.p_otp_code, code());
});

test('invalid code or unaccepted consent makes no transport call', async () => {
  const f = transport(); await assert.rejects(f.gateway.sign(context, { ...consent(), code: '123' }));
  await assert.rejects(f.gateway.requestOtp(context, { ...consent(), accepted: false } as any));
  assert.equal(f.calls.length, 0); assert.equal(f.storageCalls.length, 0);
});

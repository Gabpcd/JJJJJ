import assert from 'node:assert/strict';
import test from 'node:test';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { validateDocumentBytes } from './bytes';
import { createOriginalSigningTransport } from './originalTransport';
import { visibleDocumentRequirements } from './requirements';
import { SupabaseDocumentGateway } from './supabaseGateway';
import { createDocumentUploadJournal } from '../../documents/uploadJournal';
import type { CaregiverDocument, DocumentContext, DocumentProfile, DocumentRequirement, OriginalSigningTransport } from './types';

const UID = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const DOC = '33333333-3333-4333-8333-333333333333';
const NEW_DOC = '44444444-4444-4444-8444-444444444444';
const UPLOAD = '55555555-5555-4555-8555-555555555555';
const ORIGIN = 'https://mejpriaetwgtcstbgfid.supabase.co';
const context: DocumentContext = { userId: UID };
const now = new Date('2026-10-27T10:00:00Z');
const pdf = () => ({ name: 'diplome.pdf', mime: 'application/pdf', bytes: new TextEncoder().encode('%PDF-1.7\nfictif') });
const profile: DocumentProfile = { id: UID, profession: 'IDE', prenom: 'Camille', nom: 'Fictif', type_exercice: 'MIXTE',
  rpps_verifie: false, adeli_verifie: false, attestation_sante_signee_le: null };
const original: CaregiverDocument = {
  id: DOC, soignant_id: UID, type_document: 'DIPLOME', nom_fichier: 'ancien.pdf', statut_verification: 'VERIFIE',
  valide_depuis: null, valide_jusqua: null, televerse_le: now.toISOString(), motif_rejet: null, est_critique: true,
  libelle: null, s3_cle: `${UID}/documents/DIPLOME/original.pdf`, s3_bucket: 'jolene-documents',
  type_mime: 'application/pdf', taille_octets: 20, profession_certifiee: null, supprime_le: null, revoque_le: null,
};

interface Call { source: string; args?: any; ops: Array<[string, ...any[]]> }
interface Response { data: any; error: unknown; count?: number | null }
/** Transport doubles only: no database, RLS, Storage object or AI/human provider is contacted. */
function fixture(options: { role?: string; origin?: string; profile?: DocumentProfile | null; foreignRow?: boolean;
  registrationRefused?: boolean; lostRegistrationResponse?: boolean; unreadableAfterRegister?: boolean;
  verificationFails?: boolean; unknownStatus?: string; zeroDelete?: boolean; auditFails?: boolean;
  switchDuringUpload?: boolean; switchDuringIdentity?: boolean; countMismatch?: boolean;
  signingUri?: string; staleAfterSign?: boolean; nullableLegacyRow?: boolean; numericDocumentType?: boolean } = {}) {
  const calls: Call[] = []; const documents: CaregiverDocument[] = [structuredClone(original)];
  if (options.nullableLegacyRow) Object.assign(documents[0]!, { statut_verification: null, televerse_le: null,
    taille_octets: null, type_mime: null, est_critique: null });
  if (options.numericDocumentType) Object.assign(documents[0]!, { type_document: 'ATTESTATION_3200H',
    s3_cle: `${UID}/documents/ATTESTATION_3200H/original.pdf` });
  let currentUser = UID; let registered = false;
  const active = () => documents.filter(row => row.supprime_le === null && row.revoque_le === null);
  const equal = (call: Call, field: string) => call.ops.find(op => op[0] === 'eq' && op[1] === field)?.[2];
  const handle = (call: Call): Response => {
    if (call.source === 'fn_get_my_role') return { data: { role: options.role ?? 'SOIGNANT', user_id: UID }, error: null };
    if (call.source === 'soignants') return { data: options.profile === null ? null : options.profile ?? structuredClone(profile), error: null };
    if (call.source === 'documents_requis_par_profession') return { data: [], error: null, count: 0 };
    if (call.source === 'documents_soignants') {
      if (registered && options.unreadableAfterRegister) return { data: null, error: true };
      const id = equal(call, 'id');
      const row = active().find(item => item.id === id);
      const update = call.ops.find(op => op[0] === 'update');
      if (update) {
        if (!row || options.zeroDelete) return { data: null, error: null };
        row.supprime_le = update[1].supprime_le;
        return { data: { id: row.id, soignant_id: row.soignant_id, supprime_le: row.supprime_le }, error: null };
      }
      if (id) return { data: row ? structuredClone(row) : null, error: null };
      const rows = active().map(item => ({ ...item,
        ...(options.foreignRow ? { soignant_id: OTHER } : {}),
        ...(options.unknownStatus ? { statut_verification: options.unknownStatus } : {}),
      }));
      const range = call.ops.find(op => op[0] === 'range')!;
      return { data: rows.slice(range[1], range[2] + 1), error: null, count: rows.length + (options.countMismatch ? 1 : 0) };
    }
    if (call.source === 'fn_remplacer_document_soignant') {
      if (options.registrationRefused) return { data: { success: false, error_code: 'DOCUMENT_INACTIF' }, error: null };
      registered = true;
      for (const doc of active()) if (doc.type_document === call.args.p_type_document) doc.revoque_le = now.toISOString();
      documents.push({ ...structuredClone(original), id: NEW_DOC, s3_cle: call.args.p_s3_cle,
        nom_fichier: call.args.p_nom_fichier, taille_octets: call.args.p_taille_octets,
        statut_verification: 'EN_ATTENTE', supprime_le: null, revoque_le: null });
      return options.lostRegistrationResponse ? { data: null, error: true }
        : { data: { success: true, document_id: NEW_DOC }, error: null };
    }
    if (call.source === 'fn_demander_revue_document') {
      const row = active().find(doc => doc.id === call.args.p_document_id)!;
      row.statut_verification = 'REVUE_MANUELLE_REQUISE';
      return { data: { success: true, revue_id: 'review-test' }, error: null };
    }
    if (call.source === 'fn_ecrire_audit_safe') return { data: null, error: options.auditFails ? true : null };
    throw new Error(`Unexpected transport: ${call.source}`);
  };
  class Query implements PromiseLike<Response> {
    constructor(readonly call: Call) { calls.push(call); }
    op(name: string, ...args: any[]) { this.call.ops.push([name, ...args]); return this; }
    select(...args: any[]) { return this.op('select', ...args); } eq(...args: any[]) { return this.op('eq', ...args); }
    is(...args: any[]) { return this.op('is', ...args); } order(...args: any[]) { return this.op('order', ...args); }
    range(...args: any[]) { return this.op('range', ...args); } update(...args: any[]) { return this.op('update', ...args); }
    setHeader(...args: any[]) { return this.op('setHeader', ...args); } abortSignal(...args: any[]) { return this.op('abortSignal', ...args); }
    maybeSingle() { return this; }
    then<T = Response, E = never>(fulfilled?: ((value: Response) => T | PromiseLike<T>) | null,
      rejected?: ((error: unknown) => E | PromiseLike<E>) | null): PromiseLike<T | E> {
      return Promise.resolve().then(() => handle(this.call)).then(fulfilled, rejected);
    }
  }
  const client = {
    auth: {
      getSession: async () => ({ data: { session: { access_token: 'user-jwt-test', user: { id: currentUser } } }, error: null }),
      getUser: async () => { if (options.switchDuringIdentity) currentUser = OTHER; return { data: { user: { id: UID } }, error: null }; },
    },
    from: (source: string) => new Query({ source, ops: [] }),
    rpc: (source: string, args?: any) => new Query({ source, args, ops: [] }),
    storage: { from: (bucket: string) => ({
      getPublicUrl: (path: string) => ({ data: { publicUrl: `${options.origin ?? ORIGIN}/storage/v1/object/public/${bucket}/${path}` } }),
      upload: async (path: string, bytes: ArrayBuffer, args: any) => {
        calls.push({ source: 'storage.upload', args: { bucket, path, bytes, ...args }, ops: [] });
        if (options.switchDuringUpload) currentUser = OTHER;
        return { data: { path }, error: null };
      },
      remove: () => { throw new Error('Original objects must never be removed'); },
    }) },
    functions: { invoke: async (source: string, args: any) => {
      calls.push({ source, args, ops: [] });
      if (options.verificationFails) return { data: null, error: true };
      const row = active().find(doc => doc.id === args.body.document_id)!;
      row.statut_verification = 'REJETE'; row.motif_rejet = 'Motif serveur fictif';
      return { data: { verdict: 'REJETE' }, error: null };
    } },
  } as unknown as SupabaseClient;
  const signer: OriginalSigningTransport = { sign: async args => {
    calls.push({ source: 'original.sign', args, ops: [] });
    if (options.staleAfterSign) documents[0]!.revoque_le = now.toISOString();
    return options.signingUri ?? `${ORIGIN}/storage/v1/object/sign/jolene-documents/${args.storageKey}?token=fake-test-signature`;
  } };
  const gateway = new SupabaseDocumentGateway(client, () => UPLOAD, signer, () => now);
  return { gateway, calls, documents };
}

test('native byte adapter uses exact Uint8Array view, copies it, and rejects mismatched formats', async () => {
  const padded = new Uint8Array([0, ...pdf().bytes, 0]);
  const view = padded.subarray(1, padded.length - 1);
  const promise = validateDocumentBytes({ name: '../Diplôme.pdf', mime: 'application/pdf', bytes: view });
  view.fill(0); const validated = await promise;
  assert.equal(new TextDecoder().decode(validated.bytes), '%PDF-1.7\nfictif');
  assert.equal(validated.safeName, 'Diplome.pdf');
  await assert.rejects(validateDocumentBytes({ ...pdf(), name: 'photo.jpg', mime: 'image/jpeg' }), /contenu/);
  await assert.rejects(validateDocumentBytes({ ...pdf(), name: 'photo.heic', mime: 'image/heic' }), /HEIC/);
  await assert.rejects(validateDocumentBytes({ ...pdf(), bytes: new Uint8Array(0) }), /non vide/);
  await assert.rejects(validateDocumentBytes({ ...pdf(), bytes: new Uint8Array(10 * 1024 * 1024 + 1) }), /10 Mo/);
});

test('read preserves unknown server status and sends explicit owner/active filters under one JWT', async () => {
  const { gateway, calls } = fixture({ unknownStatus: 'FUTUR_STATUT_SERVEUR' });
  const dossier = await gateway.readDossier(context);
  assert.equal(dossier.documents[0]!.statut_verification, 'FUTUR_STATUT_SERVEUR');
  for (const call of calls) assert.deepEqual(call.ops.find(op => op[0] === 'setHeader'), ['setHeader', 'Authorization', 'Bearer user-jwt-test']);
  const read = calls.find(call => call.source === 'documents_soignants')!;
  assert.ok(read.ops.some(op => op[0] === 'eq' && op[1] === 'soignant_id' && op[2] === UID));
  assert.ok(read.ops.some(op => op[0] === 'is' && op[1] === 'supprime_le' && op[2] === null));
  assert.ok(read.ops.some(op => op[0] === 'is' && op[1] === 'revoque_le' && op[2] === null));
  const legacy = await fixture({ nullableLegacyRow: true }).gateway.readDossier(context);
  assert.equal(legacy.documents[0]!.statut_verification, null); assert.equal(legacy.documents[0]!.televerse_le, null);
  assert.equal((await fixture({ numericDocumentType: true }).gateway.readDossier(context)).documents[0]!.type_document, 'ATTESTATION_3200H');
});

test('foreign rows, changed account, wrong role, truncated collection, and production origin fail closed', async () => {
  await assert.rejects(fixture({ foreignRow: true }).gateway.readDossier(context), /compte/);
  await assert.rejects(fixture({ role: 'ETABLISSEMENT' }).gateway.readDossier(context), /compte/);
  await assert.rejects(fixture({ switchDuringIdentity: true }).gateway.readDossier(context), /session a changé/);
  await assert.rejects(fixture({ countMismatch: true }).gateway.readDossier(context), /indisponibles/);
  assert.throws(() => fixture({ origin: 'https://production.invalid' }), /serveur/);
});

test('replacement uploads a new immutable object, atomically registers it, and preserves the original', async () => {
  const { gateway, calls, documents } = fixture();
  const result = await gateway.upload(context, { typeDocument: 'DIPLOME', label: 'Diplôme fictif', file: pdf(), replacesDocumentId: DOC });
  assert.equal(result.kind, 'confirmed'); assert.equal(result.document?.statut_verification, 'EN_ATTENTE');
  assert.equal(documents.length, 2); assert.equal(documents[0]!.s3_cle, original.s3_cle);
  assert.ok(documents[0]!.revoque_le); assert.equal(documents[0]!.supprime_le, null);
  const upload = calls.find(call => call.source === 'storage.upload')!;
  assert.equal(upload.args.upsert, false); assert.equal(upload.args.headers.Authorization, 'Bearer user-jwt-test');
  assert.notEqual(upload.args.path, original.s3_cle); assert.ok(upload.args.bytes instanceof ArrayBuffer);
  const rpc = calls.find(call => call.source === 'fn_remplacer_document_soignant')!;
  assert.deepEqual(Object.keys(rpc.args).sort(), ['p_libelle', 'p_nom_fichier', 'p_s3_cle', 'p_taille_octets', 'p_type_document', 'p_type_mime']);
  assert.equal(calls.filter(call => call.source === 'verify-document').length, 0); // Upload is never a verification verdict.
});

test('double tap performs one upload, and a switched account stops before registration', async () => {
  const { gateway, calls } = fixture();
  const first = gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf() });
  await assert.rejects(gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf() }), /déjà en cours/);
  await first; assert.equal(calls.filter(call => call.source === 'storage.upload').length, 1);
  const switched = fixture({ switchDuringUpload: true });
  let preparedPath: string | undefined;
  await assert.rejects(switched.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: ({ storageKey }) => { preparedPath = storageKey; } }), /session a changé/);
  assert.equal(preparedPath, switched.calls.find(call => call.source === 'storage.upload')!.args.path);
  assert.equal(switched.calls.filter(call => call.source === 'fn_remplacer_document_soignant').length, 0);
});

test('lost registration response is reconciled by the saved path; unreadable state never becomes success', async () => {
  const lost = fixture({ lostRegistrationResponse: true });
  assert.equal((await lost.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf() })).kind, 'confirmed');
  assert.equal(lost.calls.filter(call => call.source === 'fn_remplacer_document_soignant').length, 1);
  const unreadable = fixture({ unreadableAfterRegister: true });
  const result = await unreadable.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf() });
  assert.equal(result.kind, 'unconfirmed'); assert.ok(result.reconciliation?.storageKey);
  assert.equal(unreadable.calls.filter(call => call.source === 'verify-document').length, 0);
  const refused = fixture({ registrationRefused: true });
  assert.equal((await refused.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf() })).kind, 'rejected');
  assert.equal(refused.documents[0]!.revoque_le, null);
});

test('expired/cancelled view cannot upload, and unknown replacement IDs cannot replace another original', async () => {
  const aborted = new AbortController(); aborted.abort(); const sample = fixture();
  await assert.rejects(sample.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf() }, aborted.signal), { name: 'AbortError' });
  assert.equal(sample.calls.length, 0);
  await assert.rejects(sample.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(), replacesDocumentId: NEW_DOC }), /remplacé ou supprimé/);
  assert.equal(sample.calls.filter(call => call.source === 'storage.upload').length, 0);
});

test('receipt persistence must finish before upload; a journal failure leaves original and Storage untouched', async () => {
  const sample = fixture();
  await assert.rejects(sample.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: async () => { throw new Error('Journal indisponible'); } }), /Journal/);
  assert.equal(sample.calls.filter(call => call.source === 'storage.upload').length, 0);
  assert.equal(sample.documents[0]!.revoque_le, null);
  const successful = fixture();
  let persisted = false;
  await successful.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(), onPrepared: async () => {
    await Promise.resolve(); assert.equal(successful.calls.filter(call => call.source === 'storage.upload').length, 0); persisted = true;
  } });
  assert.ok(persisted); assert.equal(successful.calls.filter(call => call.source === 'storage.upload').length, 1);
});

test('a journal persisted before failed read-back is cleared before any Storage request; another receipt survives', async () => {
  const sample = fixture(); let stored: string | null = null; let failRead = false;
  const journal = createDocumentUploadJournal({
    getItem: async () => { if (failRead) { failRead = false; throw new Error('Keychain read failed'); } return stored; },
    setItem: async (_key, value) => { stored = value; failRead = true; },
    removeItem: async () => { stored = null; },
  });
  await assert.rejects(sample.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: receipt => journal.write(UID, receipt),
    onNotStarted: receipt => journal.clear(UID, receipt.storageKey),
  }), /Keychain read failed/);
  assert.equal(stored, null); assert.equal(sample.calls.filter(call => call.source === 'storage.upload').length, 0);
  const otherPath = `${UID}/documents/DIPLOME/other-pending.pdf`;
  stored = JSON.stringify({ version: 1, userId: UID, storageKey: otherPath });
  await assert.rejects(sample.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: receipt => journal.write(UID, receipt),
    onNotStarted: receipt => journal.clear(UID, receipt.storageKey),
  }), /reçu reste conservé/);
  assert.equal((await journal.read(UID))?.storageKey, otherPath);
  assert.equal(sample.calls.filter(call => call.source === 'storage.upload').length, 0);
  assert.equal(sample.documents[0]!.revoque_le, null);
});

test('pre-Storage cancellation awaits exact local receipt cleanup; post-Storage change never clears it', async () => {
  const sample = fixture(); const controller = new AbortController(); let prepared: string | undefined; let cleared = false;
  await assert.rejects(sample.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: ({ storageKey }) => { prepared = storageKey; controller.abort(); },
    onNotStarted: async ({ storageKey }) => {
      assert.equal(storageKey, prepared); await Promise.resolve(); cleared = true;
    },
  }, controller.signal), { name: 'AbortError' });
  assert.equal(cleared, true); assert.equal(sample.calls.filter(call => call.source === 'storage.upload').length, 0);
  const failed = fixture(); const abort = new AbortController(); const cleanupCause = new Error('Local journal failed');
  await assert.rejects(failed.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: () => { abort.abort(); }, onNotStarted: async () => { throw cleanupCause; },
  }, abort.signal), (error: any) => error.cause.name === 'AbortError'
    && error.cleanupCause === cleanupCause && !!error.reconciliation?.storageKey && /reçu reste conservé/.test(error.message));
  assert.equal(failed.calls.filter(call => call.source === 'storage.upload').length, 0);
  const started = fixture({ switchDuringUpload: true }); let incorrectlyCleared = false;
  await assert.rejects(started.gateway.upload(context, { typeDocument: 'DIPLOME', file: pdf(),
    onPrepared: () => undefined, onNotStarted: () => { incorrectlyCleared = true; },
  }), /session a changé/);
  assert.equal(incorrectlyCleared, false); assert.equal(started.calls.filter(call => call.source === 'storage.upload').length, 1);
});

test('verification uses pinned Edge JWT, re-reads rejection, and never invents human review after a network error', async () => {
  const success = fixture(); const result = await success.gateway.verify(context, DOC);
  assert.equal(result.kind, 'confirmed'); assert.equal(result.document?.statut_verification, 'REJETE');
  assert.equal(result.document?.motif_rejet, 'Motif serveur fictif');
  const edge = success.calls.find(call => call.source === 'verify-document')!;
  assert.deepEqual(edge.args.body, { document_id: DOC }); assert.equal(edge.args.headers.Authorization, 'Bearer user-jwt-test');
  const failure = await fixture({ verificationFails: true }).gateway.verify(context, DOC);
  assert.equal(failure.kind, 'unconfirmed'); assert.equal(failure.document?.statut_verification, 'VERIFIE');
});

test('review is confirmed only by successful RPC plus manual-review server state', async () => {
  const { gateway, calls } = fixture();
  await assert.rejects(gateway.requestReview(context, DOC, 'court'), /motif/); assert.equal(calls.length, 0);
  const result = await gateway.requestReview(context, DOC, 'Je souhaite une relecture humaine.');
  assert.equal(result.kind, 'confirmed'); assert.equal(result.document?.statut_verification, 'REVUE_MANUELLE_REQUISE');
  const request = calls.find(call => call.source === 'fn_demander_revue_document')!;
  assert.equal(request.args.p_document_id, DOC); assert.ok(request.ops.some(op => op[0] === 'setHeader'));
});

test('logical deletion changes only supprime_le, preserves the object, audits and does not hide zero-row or audit failure', async () => {
  const success = fixture(); const result = await success.gateway.logicalDelete(context, DOC);
  assert.equal(result.kind, 'confirmed'); assert.deepEqual(result.dossier?.documents, []);
  assert.equal(success.documents[0]!.s3_cle, original.s3_cle);
  const update = success.calls.flatMap(call => call.ops).find(op => op[0] === 'update')!;
  assert.deepEqual(Object.keys(update[1]), ['supprime_le']);
  assert.equal(success.calls.find(call => call.source === 'fn_ecrire_audit_safe')!.args.p_action, 'DOCUMENT_SUPPRESSION');
  assert.equal((await fixture({ zeroDelete: true }).gateway.logicalDelete(context, DOC)).kind, 'unconfirmed');
  assert.ok((await fixture({ auditFails: true }).gateway.logicalDelete(context, DOC)).warning);
});

test('original link is scoped, read twice, audited and bounded; stale/foreign URLs and failed audit are refused', async () => {
  const success = fixture(); const result = await success.gateway.getOriginal(context, DOC);
  assert.equal(result.mime, 'application/pdf'); assert.equal(result.expiresAt, '2026-10-27T11:00:00.000Z');
  const sign = success.calls.find(call => call.source === 'original.sign')!;
  assert.equal(sign.args.expiresIn, 3600); assert.equal(sign.args.authorization, 'Bearer user-jwt-test');
  assert.equal(success.calls.find(call => call.source === 'fn_ecrire_audit_safe')!.args.p_action, 'DOCUMENT_CONSULTATION');
  await assert.rejects(fixture({ staleAfterSign: true }).gateway.getOriginal(context, DOC), /remplacé ou supprimé/);
  await assert.rejects(fixture({ signingUri: 'https://other.invalid/file?token=fake' }).gateway.getOriginal(context, DOC), /compte/);
  await assert.rejects(fixture({ auditFails: true }).gateway.getOriginal(context, DOC), /indisponibles/);
});

test('dedicated signing transport sends requested TTL and pinned JWT without auth persistence or provider request', async () => {
  const requests: Array<{ url: string; init?: RequestInit }> = [];
  const transport = createOriginalSigningTransport({ url: ORIGIN, publishableKey: 'sb_publishable_unit_test_public_key' },
    (async (input: string | URL | Request, init?: RequestInit) => {
      requests.push({ url: String(input), init });
      return new Response(JSON.stringify({ signedURL: `/object/sign/jolene-documents/${original.s3_cle}?token=fake-test-signature` }),
        { status: 200, headers: { 'Content-Type': 'application/json' } });
    }) as typeof fetch);
  const result = await transport.sign({ storageKey: original.s3_cle, authorization: 'Bearer test-pinned-jwt', expiresIn: 3600 });
  assert.equal(requests.length, 1);
  assert.equal(requests[0]!.url, `${ORIGIN}/storage/v1/object/sign/jolene-documents/${original.s3_cle}`);
  assert.equal(new Headers(requests[0]!.init?.headers).get('authorization'), 'Bearer test-pinned-jwt');
  assert.deepEqual(JSON.parse(String(requests[0]!.init?.body)), { expiresIn: 3600 });
  assert.ok(result.startsWith(`${ORIGIN}/storage/v1/object/sign/`));
  await assert.rejects(transport.sign({ storageKey: original.s3_cle, authorization: 'Bearer test-pinned-jwt', expiresIn: 3601 }), /invalide/);
  assert.equal(requests.length, 1);
});

test('locked Supabase Storage SDK preserves ArrayBuffer bytes, no-upsert and explicit JWT in the final HTTP request', async () => {
  const requests: RequestInit[] = [];
  const client = createClient(ORIGIN, 'sb_publishable_unit_test_public_key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: (async (_input: string | URL | Request, init?: RequestInit) => {
      requests.push(init ?? {});
      return new Response(JSON.stringify({ Id: 'storage-test', Key: `jolene-documents/${original.s3_cle}` }),
        { status: 200, headers: { 'Content-Type': 'application/json' } });
    }) as typeof fetch },
  });
  const file = await validateDocumentBytes(pdf());
  const result = await client.storage.from('jolene-documents').upload(original.s3_cle, file.bytes,
    { contentType: file.mime, upsert: false, headers: { Authorization: 'Bearer test-pinned-jwt' } });
  assert.equal(result.error, null); assert.equal(requests.length, 1);
  const headers = new Headers(requests[0]!.headers);
  assert.equal(headers.get('authorization'), 'Bearer test-pinned-jwt');
  assert.equal(headers.get('x-upsert'), 'false'); assert.equal(headers.get('content-type'), 'application/pdf');
  assert.deepEqual(new Uint8Array(requests[0]!.body as ArrayBuffer), new Uint8Array(file.bytes));
});

test('requirement visibility retains existing mixed-exercise and specialised-diploma semantics', () => {
  const rule = (type: string, exercise: string): DocumentRequirement => ({ id: type, profession: 'IDE', type_document: type,
    description: null, a_expiration: false, duree_validite_mois: null, est_critique: true, type_exercice_requis: exercise });
  const rules = [rule('RCP_ASSURANCE', 'LIBERAL_ONLY'), rule('CASIER_JUDICIAIRE', 'SALARIE_ONLY'), rule('DIPLOME', 'TOUS'), rule('VACCINATIONS', 'TOUS')];
  assert.deepEqual(visibleDocumentRequirements(profile, rules).map(row => row.type_document), ['RCP_ASSURANCE', 'CASIER_JUDICIAIRE', 'DIPLOME']);
  assert.deepEqual(visibleDocumentRequirements({ ...profile, rpps_verifie: true }, rules).map(row => row.type_document), ['RCP_ASSURANCE', 'CASIER_JUDICIAIRE']);
  const specialised = { ...profile, profession: 'IADE', rpps_verifie: true };
  assert.equal(visibleDocumentRequirements(specialised, [{ ...rule('DIPLOME', 'TOUS'), profession: 'IADE' }]).length, 1);
});

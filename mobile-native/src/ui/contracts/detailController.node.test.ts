import assert from 'node:assert/strict';
import test from 'node:test';
import type { ContractContext, ContractDetails, ContractGateway, ContractSignResult, OtpRequestResult } from '../../workflows/contracts/types';
import { createContractDetailController } from './detailController';

const USER = '00000000-0000-4000-8000-000000000001', CONTRACT = '00000000-0000-4000-8000-000000000002';
const ETAB = '00000000-0000-4000-8000-000000000003';
const context: ContractContext = { kind: 'soignant', userId: USER };
const sha = 'a'.repeat(64), storagePath = `${CONTRACT}/original.html`;
const fixture = (): ContractDetails => ({ userId: USER, party: 'soignant', permissions: { read: true, sign: true }, isTestAccount: true,
  record: { id: CONTRACT, mission_id: '00000000-0000-4000-8000-000000000004', soignant_id: USER, etablissement_id: ETAB,
    numero_contrat: 'FICTIF-TEST', type_contrat: 'LIBERAL', statut: 'EN_ATTENTE_SIGNATURES', cree_le: '2026-10-27T10:00:00Z',
    signature_soignant: false, signature_soignant_le: null, signature_etablissement: false, signature_etablissement_le: null,
    contenu_html: '<p>Fixture contrôleur uniquement</p>', hash_document: sha, storage_path: storagePath,
    contenu_html_rendu_le: '2026-10-27T10:00:00Z', mode_signature: 'OTP' }, signatures: [], originalIssue: null,
  original: { contractId: CONTRACT, html: '<p>Fixture contrôleur uniquement</p>', sha256: sha, storagePath,
    renderedAt: '2026-10-27T10:00:00Z', source: 'database-and-storage' },
  otpAdmission: { expiresAt: Date.now() + 60_000, canSend: true, canValidate: true, otpExpiresAt: Date.now() + 60_000 } });
const queued = (contract = fixture()): OtpRequestResult => ({ kind: 'queued', delivery: 'unverified', contract,
  phoneMasked: null, expiresAt: null, sendsRemaining: null, issue: null, message: 'Demande enregistrée, réception non confirmée.' });
const signed = (contract = fixture()): ContractSignResult => {
  contract.record.signature_soignant = true; contract.record.signature_soignant_le = '2026-10-27T10:05:00Z'; contract.record.statut = 'SIGNE_SOIGNANT';
  return { kind: 'confirmed', contract, issue: null, message: 'Signature confirmée après relecture.' };
};
function deferred<T>() { let resolve!: (value: T) => void; let reject!: (reason: Error) => void;
  const promise = new Promise<T>((ok, fail) => { resolve = ok; reject = fail; }); return { promise, resolve, reject }; }
const tick = () => new Promise<void>(resolve => setImmediate(resolve));
function setup(overrides: Partial<ContractGateway> = {}, actor = context) {
  const calls = { read: 0, request: 0, sign: 0 };
  const gateway: ContractGateway = { mode: 'supabase', list: async () => ({ rows: [], total: 0, page: 0, nextPage: null }),
    read: async () => { calls.read++; return fixture(); }, requestOtp: async () => { calls.request++; return queued(); },
    sign: async () => { calls.sign++; return signed(); }, ...overrides };
  const controller = createContractDetailController(gateway, actor, CONTRACT);
  return { controller, calls };
}
type Controller = ReturnType<typeof createContractDetailController>;
async function ready(controller: Controller) { controller.activate(); await tick(); assert.ok(controller.getSnapshot().details); }
function consent(controller: Controller) { const original = controller.getSnapshot().details?.original; assert.ok(original);
  controller.presented(original); controller.accept(true); assert.ok(controller.getSnapshot().accepted); }

test('no request or signing before complete original presentation and explicit acceptance', async t => {
  const { controller, calls } = setup(); t.after(() => controller.dispose()); await ready(controller);
  controller.accept(true); await controller.requestOtp(); await controller.sign('123456');
  assert.equal(calls.request, 0); assert.equal(calls.sign, 0);
  controller.presented(controller.getSnapshot().details!.original!); await controller.requestOtp();
  assert.equal(calls.request, 0);
  controller.accept(true); await controller.requestOtp(); assert.equal(calls.request, 1);
  assert.equal(controller.getSnapshot().result?.kind, 'queued');
  assert.equal((controller.getSnapshot().result as OtpRequestResult).delivery, 'unverified');
});

test('unsupported reader and late callback from another revision cannot authorize the contract', async t => {
  const { controller, calls } = setup(); t.after(() => controller.dispose()); await ready(controller); consent(controller);
  const original = controller.getSnapshot().details!.original!;
  controller.unavailable({ ...original, sha256: 'b'.repeat(64) }, 'Autre révision');
  assert.ok(controller.getSnapshot().accepted);
  controller.unavailable(original, 'Format non pris en charge');
  controller.accept(true); await controller.requestOtp();
  assert.equal(controller.getSnapshot().accepted, null); assert.equal(calls.request, 0);
});

test('refresh discards consent, and stale original presentation cannot accept a new hash', async t => {
  let result = fixture(); const { controller, calls } = setup({ read: async () => result });
  t.after(() => controller.dispose()); await ready(controller); consent(controller);
  const old = result.original!; result = fixture(); result.original = { ...result.original!, sha256: 'b'.repeat(64) };
  await controller.reload(); assert.equal(controller.getSnapshot().accepted, null);
  controller.presented(old); controller.accept(true); await controller.requestOtp();
  assert.equal(calls.request, 0); assert.equal(controller.getSnapshot().presented, null);
});

test('double tap queues one request and never represents queueing as SMS delivery', async t => {
  const response = deferred<OtpRequestResult>(); let count = 0;
  const { controller } = setup({ requestOtp: () => { count++; return response.promise; } });
  t.after(() => controller.dispose()); await ready(controller); consent(controller);
  const first = controller.requestOtp(); await controller.requestOtp(); assert.equal(count, 1);
  response.resolve(queued()); await first;
  assert.equal(controller.getSnapshot().busy, null); assert.equal(controller.getSnapshot().result?.kind, 'queued');
  assert.equal((controller.getSnapshot().result as OtpRequestResult).delivery, 'unverified');
});

test('OTP code requires six digits; confirmed reread removes old consent', async t => {
  const { controller, calls } = setup(); t.after(() => controller.dispose()); await ready(controller); consent(controller);
  await controller.sign('12345'); await controller.sign('ABCDEF'); assert.equal(calls.sign, 0);
  await controller.sign('123456'); assert.equal(calls.sign, 1);
  assert.equal(controller.getSnapshot().result?.kind, 'confirmed'); assert.equal(controller.getSnapshot().accepted, null);
  assert.equal(controller.getSnapshot().details?.record.signature_soignant, true);
  await controller.sign('123456'); assert.equal(calls.sign, 1);
});

test('unknown mutation outcome requires read and never automatically repeats the request', async t => {
  let count = 0; const { controller } = setup({ sign: async () => { count++; throw new Error('Network unavailable'); } });
  t.after(() => controller.dispose()); await ready(controller); consent(controller); await controller.sign('123456');
  assert.equal(controller.getSnapshot().needsRead, true); assert.ok(controller.getSnapshot().error);
  await controller.sign('123456'); assert.equal(count, 1);
  await controller.reload(); assert.equal(controller.getSnapshot().needsRead, false); assert.equal(controller.getSnapshot().accepted, null);
});

test('response without reread contract keeps reconciliation visible and blocks another mutation', async t => {
  let count = 0; const { controller } = setup({ requestOtp: async () => { count++; return { ...queued(), kind: 'rejected', contract: null }; } });
  t.after(() => controller.dispose()); await ready(controller); consent(controller); await controller.requestOtp();
  assert.equal(controller.getSnapshot().needsRead, true); await controller.requestOtp(); assert.equal(count, 1);
});

test('backgrounding immediately clears original/consent and ignores a late mutation response', async t => {
  const response = deferred<ContractSignResult>(); const { controller } = setup({ sign: () => response.promise });
  t.after(() => controller.dispose()); await ready(controller); consent(controller); const pending = controller.sign('123456');
  controller.deactivate(); assert.equal(controller.getSnapshot().details, null); assert.equal(controller.getSnapshot().accepted, null);
  response.resolve(signed()); await pending; assert.equal(controller.getSnapshot().result, null);
  await ready(controller); assert.equal(controller.getSnapshot().accepted, null); assert.equal(controller.getSnapshot().result, null);
});

test('stale read from before focus/Strict Mode restart cannot replace the new contract snapshot', async t => {
  const old = deferred<ContractDetails>(); let count = 0; const fresh = fixture(); fresh.record.numero_contrat = 'FICTIF-ACTUEL';
  const { controller } = setup({ read: () => ++count === 1 ? old.promise : Promise.resolve(fresh) });
  t.after(() => controller.dispose()); controller.activate(); controller.deactivate(); await ready(controller);
  old.resolve(fixture()); await tick(); assert.equal(controller.getSnapshot().details?.record.numero_contrat, 'FICTIF-ACTUEL');
});

test('another user/establishment in a reread is rejected before the original or success appears', async t => {
  const foreign = fixture(); foreign.userId = ETAB;
  const { controller } = setup({ read: async () => foreign }); t.after(() => controller.dispose());
  controller.activate(); await tick(); assert.equal(controller.getSnapshot().details, null); assert.ok(controller.getSnapshot().error);
  const second = setup({ sign: async () => signed(foreign) }); t.after(() => second.controller.dispose());
  await ready(second.controller); consent(second.controller); await second.controller.sign('123456');
  assert.equal(second.controller.getSnapshot().result, null); assert.equal(second.controller.getSnapshot().needsRead, true);
});

for (const mode of ['read-only', 'already-signed', 'non-test', 'unknown-status', 'no-original']) test(`${mode} never enables a mutation`, async t => {
  const detail = fixture();
  if (mode === 'read-only') detail.permissions.sign = false;
  if (mode === 'already-signed') detail.record.signature_soignant = true;
  if (mode === 'non-test') detail.isTestAccount = false;
  if (mode === 'unknown-status') detail.record.statut = 'UNKNOWN';
  if (mode === 'no-original') detail.original = null;
  const { controller, calls } = setup({ read: async () => detail }); t.after(() => controller.dispose()); await ready(controller);
  controller.presented(fixture().original!); controller.accept(true); await controller.requestOtp(); await controller.sign('123456');
  assert.equal(calls.request, 0); assert.equal(calls.sign, 0);
});

test('establishment context must match the canonical establishment returned in the record', async t => {
  const detail = fixture(); detail.party = 'etablissement'; detail.record.etablissement_id = USER;
  const { controller } = setup({ read: async () => detail }, { kind: 'etablissement', userId: USER, etablissementId: ETAB });
  t.after(() => controller.dispose()); controller.activate(); await tick();
  assert.equal(controller.getSnapshot().details, null); assert.ok(controller.getSnapshot().error);
});

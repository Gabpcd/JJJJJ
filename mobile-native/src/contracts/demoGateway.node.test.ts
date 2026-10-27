import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { DemoContractGateway, type DemoContractSession } from './demoGateway';
import { DEMO_CONTRACT_CODE, DEMO_CONTRACT_ID, DEMO_CONTRACT_LAST_LINE, demoContractHtml } from './demoFixture';
import { parseNativeContract } from '../ui/contracts/readerModel';
import { contractScenario, nativeContractContext, readOnlyContractDemo } from './runtime';
import { createContractDetailController } from '../ui/contracts/detailController';
import type { ContractContext } from '../workflows/contracts/types';
import { DEMO_ESTABLISHMENT_CONTEXT } from '../establishment/demo';

const soignant: ContractContext = { kind: 'soignant', userId: 'demo-soignant' };
const etablissement: ContractContext = { kind: 'etablissement', userId: 'demo-etablissement-user', etablissementId: 'demo-etablissement' };
const digest = async (value: string) => createHash('sha256').update(value).digest('hex');
function harness(uncertainSignature = false) {
  let session: DemoContractSession | null = { context: soignant, epoch: 1, canRead: true, canSign: true };
  let now = Date.parse('2026-10-27T10:00:00Z');
  const gateway = new DemoContractGateway({ currentSession: () => session, digestUtf8: digest, uncertainSignature, now: () => now });
  return { gateway, update: (value: DemoContractSession | null) => { session = value; }, advance: (milliseconds: number) => { now += milliseconds; } };
}
test('contract scenario is explicit and cannot be enabled in STAGING', () => {
  assert.equal(contractScenario('demo', undefined), false); assert.equal(contractScenario('demo', '1'), true);
  assert.throws(() => contractScenario('staging', '1')); assert.throws(() => contractScenario('demo', 'yes'));
  assert.equal(nativeContractContext(null), null);
});
test('synthetic original uses actual template and displays its final line without pretending to come from Storage', async () => {
  const { gateway } = harness(); const detail = await gateway.read(soignant, DEMO_CONTRACT_ID);
  assert.equal(detail.original?.source, 'synthetic'); assert.equal(detail.original?.html, demoContractHtml());
  assert.equal(detail.original?.sha256, await digest(demoContractHtml()));
  const model = parseNativeContract(detail.original!.html); assert.ok(model.supported);
  const text = model.blocks.map(block => block.runs.map(run => run.text).join('')).join('\n');
  assert.ok(text.includes(DEMO_CONTRACT_LAST_LINE)); assert.ok(text.includes('DOCUMENT FICTIF — AUCUN ENGAGEMENT RÉEL'));
});
test('queued demo code is explicit, expires without refresh renewal, and is never a real delivery', async () => {
  const { gateway, advance } = harness(); const detail = await gateway.read(soignant, DEMO_CONTRACT_ID);
  const input = { revision: detail.original!, accepted: true as const };
  const request = await gateway.requestOtp(soignant, input);
  assert.equal(request.delivery, 'unverified'); assert.match(request.message, /Aucun SMS/);
  const expiry = request.expiresAt; advance(1000);
  assert.equal((await gateway.read(soignant, DEMO_CONTRACT_ID)).otpAdmission?.otpExpiresAt, expiry);
  advance(600_000); assert.equal((await gateway.read(soignant, DEMO_CONTRACT_ID)).otpAdmission?.canValidate, false);
  assert.equal((await gateway.sign(soignant, { ...input, code: DEMO_CONTRACT_CODE })).kind, 'rejected');
});
test('uncertain demo signature is retained and discovered by a read, with immutable original', async () => {
  const { gateway } = harness(true); const original = (await gateway.read(soignant, DEMO_CONTRACT_ID)).original!;
  const input = { revision: original, accepted: true as const }; await gateway.requestOtp(soignant, input);
  const result = await gateway.sign(soignant, { ...input, code: DEMO_CONTRACT_CODE });
  assert.equal(result.kind, 'unconfirmed'); assert.equal(result.contract, null);
  const fresh = await gateway.read(soignant, DEMO_CONTRACT_ID);
  assert.equal(fresh.record.signature_soignant, true); assert.equal(fresh.signatures.length, 1); assert.deepEqual(fresh.original, original);
});
test('same epoch resumes synthetic state; a different epoch or account cannot reuse consent/OTP', async () => {
  const { gateway, update } = harness(); const input = { revision: (await gateway.read(soignant, DEMO_CONTRACT_ID)).original!, accepted: true as const };
  await gateway.requestOtp(soignant, input); assert.equal((await gateway.read(soignant, DEMO_CONTRACT_ID)).otpAdmission?.canValidate, true);
  update(null); await assert.rejects(gateway.read(soignant, DEMO_CONTRACT_ID));
  update({ context: soignant, epoch: 2, canRead: true, canSign: true });
  assert.equal((await gateway.read(soignant, DEMO_CONTRACT_ID)).otpAdmission?.canValidate, false);
  update({ context: etablissement, epoch: 3, canRead: true, canSign: false });
  await assert.rejects(gateway.read(soignant, DEMO_CONTRACT_ID));
});
test('read-only establishment can read its synthetic contract but neither request nor sign', async () => {
  const { gateway, update } = harness(); const account = readOnlyContractDemo({ ...DEMO_ESTABLISHMENT_CONTEXT, kind: 'etablissement' });
  assert.equal(account.permissions.contrats, false); assert.equal(account.permissions.lecture, true); assert.equal(account.membershipRole, 'LECTURE_SEULE');
  update({ context: etablissement, epoch: 2, canRead: true, canSign: false });
  const detail = await gateway.read(etablissement, DEMO_CONTRACT_ID); assert.equal(detail.permissions.sign, false);
  const input = { revision: detail.original!, accepted: true as const };
  await assert.rejects(gateway.requestOtp(etablissement, input)); await assert.rejects(gateway.sign(etablissement, { ...input, code: DEMO_CONTRACT_CODE }));
  assert.equal((await gateway.list(etablissement)).rows.length, 1);
});
test('authenticated UI refuses a synthetic original returned by a STAGING gateway', async t => {
  const { gateway } = harness(); const controller = createContractDetailController({ mode: 'supabase',
    list: gateway.list.bind(gateway), read: gateway.read.bind(gateway), requestOtp: gateway.requestOtp.bind(gateway), sign: gateway.sign.bind(gateway) }, soignant, DEMO_CONTRACT_ID);
  t.after(() => controller.dispose()); controller.activate(); await new Promise<void>(resolve => setImmediate(resolve));
  assert.equal(controller.getSnapshot().details, null); assert.ok(controller.getSnapshot().error);
});


test('both authorized demo parties sign one immutable contract; read-only actor preserves first signature without OTP rights', async () => {
  const { gateway, update } = harness(true);
  const original = (await gateway.read(soignant, DEMO_CONTRACT_ID)).original!;
  const input = { revision: original, accepted: true as const };
  await gateway.requestOtp(soignant, input);
  assert.equal((await gateway.sign(soignant, { ...input, code: DEMO_CONTRACT_CODE })).kind, 'unconfirmed');
  update({ context: etablissement, epoch: 2, canRead: true, canSign: false });
  const readOnly = await gateway.read(etablissement, DEMO_CONTRACT_ID);
  assert.equal(readOnly.userId, etablissement.userId); assert.equal(readOnly.party, 'etablissement');
  assert.equal(readOnly.record.signature_soignant, true); assert.equal(readOnly.record.signature_etablissement, false);
  assert.equal(readOnly.otpAdmission, null); assert.equal(readOnly.permissions.sign, false);
  await assert.rejects(gateway.requestOtp(etablissement, input));
  await assert.rejects(gateway.sign(etablissement, { ...input, code: DEMO_CONTRACT_CODE }));
  update({ context: etablissement, epoch: 3, canRead: true, canSign: true });
  assert.equal((await gateway.sign(etablissement, { ...input, code: DEMO_CONTRACT_CODE })).kind, 'rejected', 'Caregiver code cannot cross actors');
  await gateway.requestOtp(etablissement, input);
  assert.equal((await gateway.sign(etablissement, { ...input, code: DEMO_CONTRACT_CODE })).kind, 'unconfirmed');
  const both = await gateway.read(etablissement, DEMO_CONTRACT_ID);
  assert.equal(both.record.statut, 'SIGNE_COMPLET'); assert.equal(both.record.signature_soignant, true); assert.equal(both.record.signature_etablissement, true);
  assert.equal(both.signatures.length, 2); assert.deepEqual(both.signatures.map(row => row.signataire_role), ['soignant', 'etablissement']);
  assert.deepEqual(both.original, original); assert.equal(both.otpAdmission?.canValidate, false);
  await assert.rejects(gateway.sign(etablissement, { ...input, code: DEMO_CONTRACT_CODE }));
  update({ context: soignant, epoch: 4, canRead: true, canSign: true });
  const reread = await gateway.read(soignant, DEMO_CONTRACT_ID);
  assert.equal(reread.userId, soignant.userId); assert.equal(reread.record.statut, 'SIGNE_COMPLET'); assert.equal(reread.signatures.length, 2);
});

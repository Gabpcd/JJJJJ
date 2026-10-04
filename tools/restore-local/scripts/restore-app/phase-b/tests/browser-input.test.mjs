import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { validateBrowserInput, readBrowserInput, writeBrowserInput } from '../browser-input.mjs';

const token = role => Buffer.from(JSON.stringify({ alg: 'HS256' })).toString('base64url') + '.'
  + Buffer.from(JSON.stringify({ role })).toString('base64url') + '.' + randomBytes(32).toString('base64url');
function input(side = 'source') {
  const invoiceId = randomUUID();
  return { version: 1, run: 'jolene-restore-drill-12345-1', side, appUrl: 'http://127.0.0.1:4173',
    apiUrl: `http://jolene-restore-drill-12345-1-${side}-api:8000`, anonKey: token('anon'),
    members: ['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'SOIGNANT', 'ADMIN_ETABLISSEMENT'].map(role => {
      const id = randomUUID(); return { id, role, email: `restore-${id}@example.invalid`, password: 'Rs!' + randomBytes(36).toString('base64url') };
    }), missionId: randomUUID(), invoiceId, invoiceNumber: 'FH-2026-00001',
    pdfKey: `invoices/restore/${invoiceId}/invoice.pdf`, pdfBytes: 10, pdfSha256: randomBytes(32).toString('hex') };
}
const refused = action => assert.throws(action, error => error.message === 'RESTORE_BROWSER_INPUT_REFUSED');

test('only the four source-owned synthetic actors and the matching local side are admitted', () => {
  for (const side of ['source', 'target']) {
    const value = input(side);
    assert.equal(validateBrowserInput(value), value);
  }
});

test('remote origins, duplicate actors, admin/service key and unprojected fields refuse', () => {
  const mutations = [
    value => { value.apiUrl = 'https://example.invalid'; },
    value => { value.side = 'production'; },
    value => { value.appUrl = 'http://localhost:4173'; },
    value => { value.members[2] = { ...value.members[0] }; },
    value => { value.members[0].role = 'ADMIN_PLATEFORME'; },
    value => { value.members[0].email = 'not-owned@example.invalid'; },
    value => { value.anonKey = token('service_role'); },
    value => { value.serviceKey = randomBytes(20).toString('hex'); },
    value => { value.members[0].session = {}; },
    value => { value.pdfKey = '../private'; },
    value => { value.pdfBytes = 100 * 1024; },
  ];
  for (const mutate of mutations) { const value = input(); mutate(value); refused(() => validateBrowserInput(value)); }
});

test('malformed input errors are constant, without random private content; arbitrary files are never read', () => {
  const canary = randomBytes(32).toString('hex');
  const value = input(); value.anonKey = canary;
  for (const action of [() => validateBrowserInput(value), () => readBrowserInput('/private/' + canary)]) {
    assert.throws(action, error => error.message === 'RESTORE_BROWSER_INPUT_REFUSED' && !String(error).includes(canary));
  }
});

function runtimeFixture() {
  const value = input(), bytes = Buffer.from('synthetic owned document'), admin = { id: randomUUID(), role: 'ADMIN_PLATEFORME', password: randomBytes(32).toString('hex') };
  const source = { run: value.run, sql: { document: { id: value.invoiceId }, ids: { mission: value.missionId } },
    files: [{ kind: 'pdf', key: value.pdfKey, bytes }],
    members: [value.members[0], value.members[1], admin, value.members[2], value.members[3]] };
  let written, reads = 0;
  const runtime = { run: value.run, plan: { services: { 'source-storage': { environment: { ANON_KEY: value.anonKey, SERVICE_KEY: token('service_role') } } } },
    sqlJson: async (side, sql) => {
      reads++; assert.equal(side, 'source'); assert.match(sql, /^BEGIN READ ONLY;/);
      assert.match(sql, /FROM public\.factures_honoraires WHERE id='[a-f0-9-]{36}'::uuid;/);
      assert.match(sql, /ROLLBACK;$/);
      return { id: value.invoiceId, mission: value.missionId, number: value.invoiceNumber, pdf: value.pdfKey };
    }, privateWrite: async (path, data) => { assert.equal(path, '/owned/input.json'); written = JSON.parse(data); } };
  return { source, runtime, admin, value, bytes, getWritten: () => written, getReads: () => reads };
}

test('writer projects exact indices 0,1,3,4 and hashes the existing bytes, never the admin or service key', async () => {
  const f = runtimeFixture();
  assert.deepEqual(await writeBrowserInput(f.runtime, f.source, 'source', '/owned/input.json'),
    { written: true, members: 4, adminIncluded: false, serverKeyIncluded: false });
  const written = f.getWritten();
  assert.equal(f.getReads(), 1);
  assert.deepEqual(written.members, f.value.members);
  assert.equal(written.pdfSha256, createHash('sha256').update(f.bytes).digest('hex'));
  const serialized = JSON.stringify(written);
  assert.equal(serialized.includes(f.admin.id), false);
  assert.equal(serialized.includes(f.runtime.plan.services['source-storage'].environment.SERVICE_KEY), false);
});

test('invalid IDs refuse before SQL; mismatched invoice and SQL failure never write input or disclose errors', async () => {
  for (const mode of ['id', 'mismatch', 'failure']) {
    const f = runtimeFixture(), canary = randomBytes(32).toString('hex');
    if (mode === 'id') f.source.sql.document.id = canary + "'";
    if (mode === 'mismatch') f.runtime.sqlJson = async () => ({ id: randomUUID() });
    if (mode === 'failure') f.runtime.sqlJson = async () => { throw new Error(canary); };
    await assert.rejects(writeBrowserInput(f.runtime, f.source, 'source', '/owned/input.json'),
      error => error.message === 'RESTORE_BROWSER_INPUT_REFUSED' && !String(error).includes(canary));
    assert.equal(f.getWritten(), undefined);
    if (mode === 'id') assert.equal(f.getReads(), 0);
  }
});

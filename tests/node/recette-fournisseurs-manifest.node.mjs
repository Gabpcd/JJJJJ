import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { chmodSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createManifest, openManifest, STAGING_REF } from '../../scripts/recette-fournisseurs/lib/manifest.mjs';

const moduleUrl = new URL('../../scripts/recette-fournisseurs/lib/manifest.mjs', import.meta.url).href;
const context = () => ({ projectRef: STAGING_REF, runId: randomUUID(), sha: 'a'.repeat(40), stripeAccountId: 'acct_sandbox123456' });
const intent = (overrides = {}) => ({ operationId: randomUUID(), kind: 'stripe_customer', requestDigest: 'b'.repeat(64), parentId: null, ...overrides });
function fixture(t, options) {
  const root = mkdtempSync(join(tmpdir(), 'jolene-manifest-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const directory = join(root, 'journal'), identity = context();
  return { root, directory, identity, journal: createManifest(directory, identity, options) };
}
const receipt = (f, resourceId = 'cus_example123456') => ({ ...f.identity, ownerTag: f.journal.read().ownerTag, livemode: false, resourceId });
const raw = directory => readdirSync(directory).sort().map(name => readFileSync(join(directory, name), 'utf8')).join('\n');
const makeCreated = (f, i = intent()) => {
  f.journal.plan(i); f.journal.begin(i.operationId); f.journal.confirmCreated(i.operationId, receipt(f)); return i;
};

test('intent and in-flight marker are durable before a fake creation; replay keeps one resource', t => {
  const f = fixture(t), i = intent(), provider = new Map();
  const planned = f.journal.plan(i), revision = f.journal.read().revision;
  assert.equal(planned.status, 'planned');
  assert.deepEqual(f.journal.plan(i), planned);
  assert.equal(f.journal.read().revision, revision);
  const attempt = f.journal.begin(i.operationId);
  const onDisk = openManifest(f.directory, f.identity).read().operations[0];
  assert.equal(onDisk.status, 'in_flight');
  assert.equal(onDisk.idempotencyKey, attempt.idempotencyKey);
  provider.set(attempt.idempotencyKey, receipt(f)); // fake provider accepts, response is lost
  f.journal.markAmbiguous(i.operationId, 'TRANSPORT_INTERRUPTED');
  const resumed = openManifest(f.directory, f.identity).begin(i.operationId);
  assert.equal(resumed.idempotencyKey, attempt.idempotencyKey);
  assert.equal(resumed.attempts, 2);
  const result = provider.get(resumed.idempotencyKey); // same key retrieves the single created object
  f.journal.confirmCreated(i.operationId, result);
  const confirmedRevision = f.journal.read().revision;
  f.journal.confirmCreated(i.operationId, result);
  assert.equal(f.journal.read().revision, confirmedRevision);
  assert.equal(provider.size, 1);
});

test('identity binds project, run, commit and sandbox; foreign handles cannot append', t => {
  const f = fixture(t), before = raw(f.directory);
  for (const changed of [
    { projectRef: 'flripxtsyegjshnhzjkz' }, { projectRef: 'wnepopwygokbhlqghydb' },
    { runId: randomUUID() }, { sha: 'c'.repeat(40) }, { stripeAccountId: 'acct_another123456' },
    { runId: [f.identity.runId] }, { secret: 'forbidden-payload' },
  ]) assert.throws(() => openManifest(f.directory, { ...f.identity, ...changed }));
  assert.throws(() => createManifest(f.directory, f.identity), /EEXIST/);
  assert.equal(raw(f.directory), before);
});

test('unknown fields and sensitive data are rejected before persistence without echoing values', t => {
  const f = fixture(t), before = raw(f.directory), secret = 'sk_test_NEVER_PERSIST_THIS_SECRET';
  for (const input of [
    intent({ request: { Authorization: secret } }), intent({ requestDigest: secret }),
    intent({ operationId: '123456' }), intent({ kind: 'gabrielle@example.invalid' }),
    intent({ parentId: '+33612345678' }), intent({ operationId: [randomUUID()] }),
  ]) assert.throws(() => f.journal.plan(input), error => !error.message.includes(secret));
  assert.equal(raw(f.directory), before);
  const i = intent(); f.journal.plan(i); f.journal.begin(i.operationId);
  assert.throws(() => f.journal.confirmCreated(i.operationId, { ...receipt(f), client_secret: secret }), /INVALID_FIELDS/);
  assert.throws(() => f.journal.markAmbiguous(i.operationId, secret), /INVALID_TRANSITION/);
  assert.equal(raw(f.directory).includes(secret), false);
});

test('changed intent, unconfirmed parent and confirmation before begin are rejected', t => {
  const f = fixture(t), i = intent(); f.journal.plan(i);
  for (const changed of [{ kind: 'stripe_account' }, { requestDigest: 'd'.repeat(64) }, { parentId: randomUUID() }]) {
    assert.throws(() => f.journal.plan({ ...i, ...changed }), /INTENT_CONFLICT/);
  }
  assert.throws(() => f.journal.plan(intent({ parentId: i.operationId })), /PARENT_UNCONFIRMED/);
  assert.throws(() => f.journal.confirmCreated(i.operationId, receipt(f)), /INVALID_TRANSITION/);
  f.journal.begin(i.operationId);
  assert.throws(() => f.journal.begin(i.operationId), /RECONCILIATION_REQUIRED/);
  f.journal.confirmCreated(i.operationId, receipt(f));
  assert.equal(f.journal.plan(intent({ kind: 'stripe_payment_method', parentId: i.operationId })).status, 'planned');
});

test('receipts must match owner, resource type, run, SHA, project, sandbox and test mode', t => {
  const f = fixture(t), i = intent(); f.journal.plan(i); f.journal.begin(i.operationId);
  const before = raw(f.directory);
  for (const changed of [
    { ownerTag: 'another-owner' }, { runId: randomUUID() }, { sha: 'e'.repeat(40) },
    { projectRef: 'flripxtsyegjshnhzjkz' }, { stripeAccountId: 'acct_other12345678' },
    { livemode: true }, { resourceId: 'pi_other12345678' }, { resourceId: ['cus_example123456'] },
  ]) assert.throws(() => f.journal.confirmCreated(i.operationId, { ...receipt(f), ...changed }));
  assert.equal(raw(f.directory), before);
  f.journal.confirmCreated(i.operationId, receipt(f));
  assert.throws(() => f.journal.confirmCreated(i.operationId, receipt(f, 'cus_conflict123456')), /RESOURCE_CONFLICT/);
  const second = intent(); f.journal.plan(second); f.journal.begin(second.operationId);
  assert.throws(() => f.journal.confirmCreated(second.operationId, receipt(f)), /ALREADY_OWNED/);
});

for (const phase of ['beforeCommit', 'afterCommit']) test(`process crash ${phase} leaves a recoverable complete history`, t => {
  const f = fixture(t), i = intent(); f.journal.plan(i);
  const script = `import { openManifest } from ${JSON.stringify(moduleUrl)};
    const journal = openManifest(process.argv[1], JSON.parse(process.argv[2]), {
      checkpoint(phase) { if (phase === process.argv[4]) process.exit(23); }
    }); journal.begin(process.argv[3]);`;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', script, f.directory, JSON.stringify(f.identity), i.operationId, phase], { encoding: 'utf8', timeout: 5000 });
  assert.equal(child.status, 23, child.stderr);
  const reopened = openManifest(f.directory, f.identity);
  assert.equal(reopened.read().operations[0].status, phase === 'beforeCommit' ? 'planned' : 'in_flight');
  assert.ok(readdirSync(f.directory).some(name => name.startsWith('.pending-')));
  if (phase === 'afterCommit') {
    assert.throws(() => reopened.begin(i.operationId), /RECONCILIATION_REQUIRED/);
    reopened.markAmbiguous(i.operationId, 'PROCESS_INTERRUPTED');
  }
  const resumed = reopened.begin(i.operationId);
  assert.equal(resumed.attempts, phase === 'beforeCommit' ? 1 : 2);
  assert.equal(resumed.idempotencyKey, f.journal.read().operations[0].idempotencyKey);
});

test('lost persistence acknowledgement after a creation receipt is reconciled without duplication', t => {
  const f = fixture(t), i = intent(); f.journal.plan(i); f.journal.begin(i.operationId);
  const faulty = openManifest(f.directory, f.identity, { checkpoint(phase) { if (phase === 'afterCommit') throw new Error('disk acknowledgement lost'); } });
  assert.throws(() => faulty.confirmCreated(i.operationId, receipt(f)), /WRITE_UNCERTAIN/);
  const reopened = openManifest(f.directory, f.identity), revision = reopened.read().revision;
  assert.equal(reopened.read().operations[0].status, 'created');
  reopened.confirmCreated(i.operationId, receipt(f));
  assert.equal(reopened.read().revision, revision);
});

test('closure wins over a stale concurrent attempt and persists as a tombstone after reopen', t => {
  const f = fixture(t), i = intent(); f.journal.plan(i);
  let once = false;
  const stale = openManifest(f.directory, f.identity, { checkpoint(phase) {
    if (phase === 'beforeCommit' && !once) { once = true; f.journal.close(); }
  } });
  assert.throws(() => stale.begin(i.operationId), /CONCURRENT_WRITE/);
  const reopened = openManifest(f.directory, f.identity);
  assert.equal(reopened.read().status, 'closed');
  assert.equal(reopened.read().operations[0].status, 'cancelled');
  assert.throws(() => reopened.plan(i), /CLOSED/);
  assert.throws(() => reopened.plan(intent()), /CLOSED/);
  assert.throws(() => reopened.begin(i.operationId), /CLOSED/);
  const revision = reopened.read().revision; reopened.close();
  assert.equal(reopened.read().revision, revision);
});

test('two writers cannot overwrite each other and the loser can re-read before retrying', t => {
  const f = fixture(t), first = intent(), second = intent();
  let once = false;
  const stale = openManifest(f.directory, f.identity, { checkpoint(phase) {
    if (phase === 'beforeCommit' && !once) { once = true; f.journal.plan(second); }
  } });
  assert.throws(() => stale.plan(first), /CONCURRENT_WRITE/);
  assert.deepEqual(f.journal.read().operations.map(item => item.operationId), [second.operationId]);
  stale.plan(first);
  assert.deepEqual(f.journal.read().operations.map(item => item.operationId), [second.operationId, first.operationId]);
});

test('a failed intention write cannot authorize the fake transport', t => {
  const f = fixture(t), i = intent();
  let calls = 0;
  const faulty = openManifest(f.directory, f.identity, { checkpoint(phase) {
    if (phase === 'beforeCommit') throw new Error('local disk error');
  } });
  assert.throws(() => {
    faulty.plan(i); faulty.begin(i.operationId); calls += 1;
  }, /WRITE_UNCERTAIN/);
  assert.equal(calls, 0);
  assert.deepEqual(openManifest(f.directory, f.identity).read().operations, []);
});

test('late response after closure is retained for cleanup; closure is never a cleanup verdict', t => {
  const f = fixture(t), i = intent(); f.journal.plan(i); f.journal.begin(i.operationId);
  f.journal.close();
  assert.equal(f.journal.read().operations[0].status, 'ambiguous');
  assert.equal(f.journal.read().operations[0].reason, 'RUN_CLOSED');
  assert.throws(() => f.journal.begin(i.operationId), /CLOSED/);
  f.journal.confirmCreated(i.operationId, receipt(f));
  assert.equal(f.journal.read().status, 'closed');
  assert.equal(f.journal.read().operations[0].status, 'created');
});

test('fake cleanup failure preserves the ID; only an exact positive receipt marks removal', t => {
  const f = fixture(t), i = makeCreated(f), provider = new Map([['cus_example123456', true]]);
  f.journal.close();
  for (const changed of [{ deleted: false }, { resourceId: 'cus_foreign123456' }, { runId: randomUUID() }, { livemode: true }]) {
    assert.throws(() => f.journal.confirmRemoved(i.operationId, { ...receipt(f), deleted: true, ...changed }));
  }
  assert.equal(f.journal.read().operations[0].status, 'created');
  const deleted = provider.delete('cus_example123456'); // fake deletion is actually confirmed
  f.journal.confirmRemoved(i.operationId, { ...receipt(f), deleted });
  const reopened = openManifest(f.directory, f.identity), revision = reopened.read().revision;
  reopened.confirmRemoved(i.operationId, { ...receipt(f), deleted: true });
  assert.equal(reopened.read().revision, revision);
  assert.equal(reopened.read().operations[0].status, 'removed');
  assert.equal(reopened.read().operations[0].resourceId, 'cus_example123456');
  assert.equal(provider.size, 0);
});

test('removal requires closure, and created descendants must be removed before their parent', t => {
  const f = fixture(t), parent = makeCreated(f);
  const parentReceipt = { ...receipt(f), deleted: true };
  assert.throws(() => f.journal.confirmRemoved(parent.operationId, parentReceipt), /CLOSE_REQUIRED/);
  assert.equal(f.journal.read().operations[0].status, 'created');
  const child = intent({ kind: 'stripe_payment_method', parentId: parent.operationId });
  f.journal.plan(child); f.journal.begin(child.operationId);
  const childReceipt = receipt(f, 'pm_child12345678');
  f.journal.confirmCreated(child.operationId, childReceipt);
  f.journal.close();
  assert.throws(() => f.journal.confirmRemoved(parent.operationId, parentReceipt), /CHILD_UNRESOLVED/);
  f.journal.confirmRemoved(child.operationId, { ...childReceipt, deleted: true });
  f.journal.confirmRemoved(parent.operationId, parentReceipt);
  assert.deepEqual(f.journal.read().operations.map(item => item.status), ['removed', 'removed']);
});

test('ambiguous children block parent removal; cancelled unsent children do not', t => {
  for (const started of [false, true]) {
    const f = fixture(t), parent = makeCreated(f);
    const child = intent({ kind: 'stripe_payment_method', parentId: parent.operationId });
    f.journal.plan(child);
    if (started) f.journal.begin(child.operationId);
    f.journal.close();
    const removeParent = () => f.journal.confirmRemoved(parent.operationId, { ...receipt(f), deleted: true });
    if (started) {
      assert.throws(removeParent, /CHILD_UNRESOLVED/);
      assert.equal(f.journal.read().operations[1].status, 'ambiguous');
      assert.equal(f.journal.read().operations[0].status, 'created');
    } else {
      assert.equal(f.journal.read().operations[1].status, 'cancelled');
      removeParent();
      assert.equal(f.journal.read().operations[0].status, 'removed');
    }
  }
});

test('history gap, malformed JSON and altered hash chain fail closed', t => {
  for (const corruption of ['gap', 'json', 'chain']) {
    const f = fixture(t); f.journal.plan(intent()); f.journal.close();
    if (corruption === 'gap') rmSync(join(f.directory, '00000001.json'));
    if (corruption === 'json') writeFileSync(join(f.directory, '00000002.json'), '{');
    if (corruption === 'chain') {
      const path = join(f.directory, '00000001.json'), record = JSON.parse(readFileSync(path, 'utf8'));
      record.event.intent.requestDigest = 'c'.repeat(64); writeFileSync(path, JSON.stringify(record));
    }
    assert.throws(() => openManifest(f.directory, f.identity), /MANIFEST_/);
  }
});

test('private files and symlink refusal prevent adopting a foreign path', t => {
  const f = fixture(t);
  assert.equal(statSync(f.directory).mode & 0o077, 0);
  assert.equal(statSync(join(f.directory, '00000000.json')).mode & 0o077, 0);
  const alias = join(f.root, 'alias'); symlinkSync(f.directory, alias);
  assert.throws(() => openManifest(alias, f.identity), /UNSAFE_DIRECTORY/);
  const record = join(f.directory, '00000000.json'), copy = join(f.root, 'copy.json');
  writeFileSync(copy, readFileSync(record)); rmSync(record); symlinkSync(copy, record);
  assert.throws(() => openManifest(f.directory, f.identity));
  rmSync(record); writeFileSync(record, readFileSync(copy), { mode: 0o600 });
  chmodSync(f.directory, 0o755);
  assert.throws(() => openManifest(f.directory, f.identity), /UNSAFE_DIRECTORY/);
});

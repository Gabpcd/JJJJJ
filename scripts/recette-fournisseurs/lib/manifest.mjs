import { createHash, randomUUID } from 'node:crypto';
import { constants, closeSync, fsyncSync, fstatSync, linkSync, lstatSync, mkdirSync,
  openSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

// Local journal only: no transport, credential, provider cleanup or legacy gate.
// Each immutable revision is fsynced then linked exclusively into its final name.
// A crash leaves either the previous revision or the complete next revision,
// never an overwritten/partial manifest. A failed write must be resolved by read().
// Callers must keep this private directory: losing it loses the local tombstone.
export const STAGING_REF = 'mejpriaetwgtcstbgfid';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA = /^[0-9a-f]{40}$/;
const DIGEST = /^[0-9a-f]{64}$/;
const ACCOUNT = /^acct_[A-Za-z0-9]{8,64}$/;
const CONTEXT_KEYS = ['projectRef', 'runId', 'sha', 'stripeAccountId'];
const RESOURCE_IDS = {
  stripe_customer: /^cus_[A-Za-z0-9]{8,64}$/,
  stripe_payment_method: /^pm_[A-Za-z0-9]{8,64}$/,
  stripe_setup_intent: /^seti_[A-Za-z0-9]{8,64}$/,
  stripe_account: ACCOUNT,
  stripe_payment_intent: /^pi_[A-Za-z0-9]{8,64}$/,
  stripe_webhook: /^we_[A-Za-z0-9]{8,64}$/,
  supabase_auth_user: UUID,
  sql_mission: UUID,
};
const REASONS = ['TRANSPORT_INTERRUPTED', 'RESPONSE_INVALID', 'PERSISTENCE_UNCERTAIN', 'PROCESS_INTERRUPTED'];
const REVISION = /^\d{8}\.json$/;
const PENDING = /^\.pending-[0-9a-f-]{36}\.json$/;
const fail = code => { throw new Error(code); };
const hash = value => createHash('sha256').update(value).digest('hex');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function fields(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || !equal(Object.keys(value).sort(), [...keys].sort())) fail('MANIFEST_INVALID_FIELDS');
}
function contextOf(value) {
  fields(value, CONTEXT_KEYS);
  if (CONTEXT_KEYS.some(key => typeof value[key] !== 'string')
    || value.projectRef !== STAGING_REF || !UUID.test(value.runId) || !SHA.test(value.sha)
    || /^0+$/.test(value.sha) || !ACCOUNT.test(value.stripeAccountId)) fail('MANIFEST_INVALID_CONTEXT');
  return Object.fromEntries(CONTEXT_KEYS.map(key => [key, value[key]]));
}
const ownerOf = context => `jolene-recette-v1-${hash(JSON.stringify(context))}`;
const keyOf = (context, operationId) => `jolene-recette-v1/${hash(JSON.stringify(context))}/${operationId}`;
function intentOf(value) {
  fields(value, ['operationId', 'kind', 'requestDigest', 'parentId']);
  if (typeof value.operationId !== 'string' || !UUID.test(value.operationId)
    || typeof value.kind !== 'string' || !Object.hasOwn(RESOURCE_IDS, value.kind)
    || typeof value.requestDigest !== 'string' || !DIGEST.test(value.requestDigest)
    || (value.parentId !== null && (typeof value.parentId !== 'string' || !UUID.test(value.parentId)))) {
    fail('MANIFEST_INVALID_INTENT');
  }
  return { operationId: value.operationId, kind: value.kind, requestDigest: value.requestDigest, parentId: value.parentId };
}
function receiptOf(value, context, kind) {
  fields(value, [...CONTEXT_KEYS, 'ownerTag', 'livemode', 'resourceId']);
  if (!equal(contextOf(Object.fromEntries(CONTEXT_KEYS.map(key => [key, value[key]]))), context)
    || value.ownerTag !== ownerOf(context) || value.livemode !== false
    || typeof value.resourceId !== 'string' || !RESOURCE_IDS[kind]?.test(value.resourceId)) fail('MANIFEST_FOREIGN_RESOURCE');
  return value.resourceId;
}

// States: planned -> in_flight -> created | ambiguous -> in_flight (same key).
// created -> removed records a deletion receipt; it does not run cleanup.
// Opening never retries an in-flight operation. The runner must first prove its
// previous worker stopped, then explicitly mark it ambiguous and reconcile.
// closed is a permanent creation barrier, NOT a claim that resources are clean.
// Late responses may still be recorded after closure so cleanup cannot lose IDs.
function apply(state, event, context) {
  if (!state) {
    fields(event, ['type']);
    if (event.type !== 'init') fail('MANIFEST_INVALID_INITIAL_EVENT');
    return { status: 'open', operations: [] };
  }
  const next = structuredClone(state);
  if (event.type === 'close') {
    fields(event, ['type']);
    if (state.status !== 'open') fail('MANIFEST_INVALID_TRANSITION');
    next.status = 'closed';
    for (const item of next.operations) {
      if (item.status === 'planned') item.status = 'cancelled';
      if (item.status === 'in_flight') { item.status = 'ambiguous'; item.reason = 'RUN_CLOSED'; }
    }
    return next;
  }
  if (event.type === 'plan') {
    fields(event, ['type', 'intent']);
    const intent = intentOf(event.intent);
    if (state.status !== 'open') fail('MANIFEST_CLOSED');
    if (next.operations.some(item => item.operationId === intent.operationId)) fail('MANIFEST_OPERATION_EXISTS');
    if (intent.parentId !== null && !next.operations.some(item => item.operationId === intent.parentId && item.status === 'created')) {
      fail('MANIFEST_PARENT_UNCONFIRMED');
    }
    next.operations.push({ ...intent, idempotencyKey: keyOf(context, intent.operationId), status: 'planned', attempts: 0, resourceId: null, reason: null });
    return next;
  }
  if (typeof event.operationId !== 'string' || !UUID.test(event.operationId)) fail('MANIFEST_INVALID_OPERATION');
  const item = next.operations.find(entry => entry.operationId === event.operationId);
  if (!item) fail('MANIFEST_OPERATION_MISSING');
  if (event.type === 'begin') {
    fields(event, ['type', 'operationId']);
    if (state.status !== 'open') fail('MANIFEST_CLOSED');
    if (!['planned', 'ambiguous'].includes(item.status)) fail('MANIFEST_RECONCILIATION_REQUIRED');
    item.status = 'in_flight'; item.attempts += 1; item.reason = null;
  } else if (event.type === 'ambiguous') {
    fields(event, ['type', 'operationId', 'reason']);
    if (!REASONS.includes(event.reason) || !['in_flight', 'ambiguous'].includes(item.status)) fail('MANIFEST_INVALID_TRANSITION');
    item.status = 'ambiguous'; item.reason = event.reason;
  } else if (event.type === 'created') {
    fields(event, ['type', 'operationId', 'receipt']);
    if (!['in_flight', 'ambiguous'].includes(item.status)) fail('MANIFEST_INVALID_TRANSITION');
    const id = receiptOf(event.receipt, context, item.kind);
    if (next.operations.some(other => other.operationId !== item.operationId && other.resourceId === id)) fail('MANIFEST_RESOURCE_ALREADY_OWNED');
    item.status = 'created'; item.resourceId = id; item.reason = null;
  } else if (event.type === 'removed') {
    fields(event, ['type', 'operationId', 'receipt']);
    fields(event.receipt, [...CONTEXT_KEYS, 'ownerTag', 'livemode', 'resourceId', 'deleted']);
    if (state.status !== 'closed') fail('MANIFEST_CLOSE_REQUIRED');
    if (next.operations.some(child => child.parentId === item.operationId
      && !['cancelled', 'removed'].includes(child.status))) fail('MANIFEST_CHILD_UNRESOLVED');
    const { deleted, ...receipt } = event.receipt;
    if (deleted !== true || item.status !== 'created'
      || receiptOf(receipt, context, item.kind) !== item.resourceId) fail('MANIFEST_REMOVAL_UNCONFIRMED');
    item.status = 'removed';
  } else fail('MANIFEST_INVALID_EVENT');
  return next;
}

function privateDirectory(directory) {
  const stat = lstatSync(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0
    || (process.getuid && stat.uid !== process.getuid())) fail('MANIFEST_UNSAFE_DIRECTORY');
}
function readRecord(path) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || stat.size > 16_384 || (stat.mode & 0o077) !== 0) fail('MANIFEST_UNSAFE_RECORD');
    return readFileSync(fd, 'utf8');
  } finally { closeSync(fd); }
}
function load(directory, context) {
  privateDirectory(directory);
  const names = readdirSync(directory);
  if (names.some(name => !REVISION.test(name) && !PENDING.test(name))) fail('MANIFEST_UNKNOWN_FILE');
  const records = names.filter(name => REVISION.test(name)).sort();
  if (!records.length || records.length > 100_000) fail('MANIFEST_INVALID_HISTORY');
  let state = null, previousHash = null;
  for (let revision = 0; revision < records.length; revision += 1) {
    if (records[revision] !== `${String(revision).padStart(8, '0')}.json`) fail('MANIFEST_HISTORY_GAP');
    const raw = readRecord(join(directory, records[revision]));
    let record;
    try { record = JSON.parse(raw); } catch { fail('MANIFEST_INVALID_JSON'); }
    fields(record, ['version', 'revision', 'previousHash', 'context', 'at', 'event']);
    if (record.version !== 1 || record.revision !== revision || record.previousHash !== previousHash
      || !equal(contextOf(record.context), context)
      || typeof record.at !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(record.at)) fail('MANIFEST_FOREIGN_OR_CORRUPT_HISTORY');
    state = apply(state, record.event, context);
    previousHash = hash(raw);
  }
  return { ...state, context: structuredClone(context), ownerTag: ownerOf(context), revision: records.length - 1, previousHash };
}
function syncDirectory(directory) {
  const fd = openSync(directory, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { fsyncSync(fd); } finally { closeSync(fd); }
}
function append(directory, context, current, event, checkpoint) {
  // Validate before writing; only a fixed schema of non-secret metadata is stored.
  apply(current, event, context);
  const revision = current ? current.revision + 1 : 0;
  const record = { version: 1, revision, previousHash: current?.previousHash ?? null,
    context, at: new Date().toISOString(), event };
  const temporary = join(directory, `.pending-${randomUUID()}.json`);
  let fd;
  try {
    fd = openSync(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    writeFileSync(fd, `${JSON.stringify(record)}\n`); fsyncSync(fd); closeSync(fd); fd = undefined;
    checkpoint('beforeCommit');
    // link, unlike rename, refuses an existing revision. Concurrent writers
    // cannot replace a winning revision, even when based on a stale snapshot.
    linkSync(temporary, join(directory, `${String(revision).padStart(8, '0')}.json`));
    syncDirectory(directory);
    checkpoint('afterCommit');
    unlinkSync(temporary); syncDirectory(directory);
  } catch (error) {
    if (fd !== undefined) closeSync(fd);
    // Keep pending files on uncertain writes for diagnosis; never infer rollback.
    if (error.code === 'EEXIST') fail('MANIFEST_CONCURRENT_WRITE');
    fail('MANIFEST_WRITE_UNCERTAIN');
  }
  return load(directory, context);
}

function handle(directory, context, checkpoint) {
  const read = () => load(directory, context);
  const commit = (current, event) => append(directory, context, current, event, checkpoint);
  const operation = (current, id) => current.operations.find(item => item.operationId === id);
  return Object.freeze({
    read,
    plan(value) {
      const intent = intentOf(value), current = read();
      if (current.status !== 'open') fail('MANIFEST_CLOSED');
      const existing = operation(current, intent.operationId);
      if (existing) {
        if (!equal(intentOf(Object.fromEntries(Object.keys(intent).map(key => [key, existing[key]]))), intent)) fail('MANIFEST_INTENT_CONFLICT');
        return structuredClone(existing);
      }
      return operation(commit(current, { type: 'plan', intent }), intent.operationId);
    },
    begin(operationId) {
      return operation(commit(read(), { type: 'begin', operationId }), operationId);
    },
    markAmbiguous(operationId, reason) {
      return operation(commit(read(), { type: 'ambiguous', operationId, reason }), operationId);
    },
    confirmCreated(operationId, receipt) {
      // Checks receipt consistency, not actual provider ownership. A future
      // adapter must re-read the resource on the expected TEST account first.
      const current = read(), existing = operation(current, operationId);
      if (!existing) fail('MANIFEST_OPERATION_MISSING');
      const resourceId = receiptOf(receipt, context, existing.kind);
      if (existing.status === 'created') {
        if (existing.resourceId !== resourceId) fail('MANIFEST_RESOURCE_CONFLICT');
        return structuredClone(existing);
      }
      // Persist only the validated allowlisted receipt, never a provider response.
      const safeReceipt = { ...context, ownerTag: ownerOf(context), livemode: false, resourceId };
      return operation(commit(current, { type: 'created', operationId, receipt: safeReceipt }), operationId);
    },
    // This records an adapter's explicit deletion receipt, not a DELETE request.
    // The journal cannot independently verify a provider; no cleanup is executed.
    confirmRemoved(operationId, receipt) {
      const current = read(), existing = operation(current, operationId);
      if (!existing) fail('MANIFEST_OPERATION_MISSING');
      fields(receipt, [...CONTEXT_KEYS, 'ownerTag', 'livemode', 'resourceId', 'deleted']);
      const { deleted, ...resource } = receipt;
      if (deleted !== true || receiptOf(resource, context, existing.kind) !== existing.resourceId) fail('MANIFEST_REMOVAL_UNCONFIRMED');
      if (existing.status === 'removed') return structuredClone(existing);
      const safeReceipt = { ...context, ownerTag: ownerOf(context), livemode: false, resourceId: existing.resourceId, deleted: true };
      return operation(commit(current, { type: 'removed', operationId, receipt: safeReceipt }), operationId);
    },
    close() {
      const current = read();
      return current.status === 'closed' ? current : commit(current, { type: 'close' });
    },
  });
}

// checkpoint is synchronous fault injection for local tests; it receives only
// a phase name. A provider adapter must not use this hook as a transport.
export function createManifest(directory, expectedContext, { checkpoint = () => {} } = {}) {
  const context = contextOf(expectedContext), path = resolve(directory);
  mkdirSync(path, { mode: 0o700 }); // Exclusive: never adopt or overwrite an existing directory.
  syncDirectory(dirname(path));
  privateDirectory(path);
  append(path, context, null, { type: 'init' }, checkpoint);
  return handle(path, context, checkpoint);
}
export function openManifest(directory, expectedContext, { checkpoint = () => {} } = {}) {
  const context = contextOf(expectedContext), path = resolve(directory);
  load(path, context);
  return handle(path, context, checkpoint);
}

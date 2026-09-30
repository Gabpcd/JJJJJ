import assert from 'node:assert/strict';
import { test } from 'node:test';
import { collectBackupStatus, backupSummary, ENDPOINT } from '../../scripts/ops/collect-backup-status.mjs';

const now = '2026-09-30T08:00:00.000Z';
const data = () => ({ region: 'eu-west-1', walg_enabled: true, pitr_enabled: false,
  backups: [{ status: 'COMPLETED', inserted_at: '2026-09-30T02:00:00Z', is_physical_backup: true }] });
const run = value => collectBackupStatus({ token: 'private-token', now,
  fetchImpl: async () => ({ ok: true, json: async () => value }) });

test('fixed GET only, no redirect and no credential in report', async () => {
  let calls = 0;
  const report = await collectBackupStatus({ token: 'private-token', now, fetchImpl: async (url, init) => {
    calls++; assert.equal(url, ENDPOINT); assert.equal(init.method, 'GET');
    assert.equal(init.redirect, 'error'); assert.equal(init.body, undefined);
    assert.equal(init.headers.Authorization, 'Bearer private-token'); assert.ok(init.signal);
    return { ok: true, json: async () => ({ ...data(), url: 'secret-download', key: 'private-token' }) };
  } });
  assert.equal(calls, 1); assert.equal(report.status, 'OBSERVED');
  assert.equal(report.restoreVerified, false); assert.equal(report.storageObjectsBackupVerified, false);
  assert.equal(report.latestCompletedAt, '2026-09-30T02:00:00.000Z');
  assert.ok(report.issues.includes('PITR_DISABLED'));
  assert.doesNotMatch(JSON.stringify(report) + backupSummary(report), /private-token|secret-download/);
});
test('absent credentials/time fail without network', async () => {
  const fetchImpl = () => { throw Error('must not call'); };
  assert.deepEqual((await collectBackupStatus({ now, fetchImpl })).issues, ['TOKEN_ABSENT']);
  assert.deepEqual((await collectBackupStatus({ token: 'x', now: 'bad', fetchImpl })).issues, ['INVALID_TIME']);
});
test('provider failure never emits body or stack', async () => {
  const report = await collectBackupStatus({ token: 'x', now,
    fetchImpl: async () => { throw Error('private-token provider trace'); } });
  assert.equal(report.status, 'UNKNOWN'); assert.doesNotMatch(JSON.stringify(report), /private-token/);
});
test('HTTP failure is unknown even with plausible body', async () => {
  const report = await collectBackupStatus({ token: 'x', now,
    fetchImpl: async () => ({ ok: false, json: async () => data() }) });
  assert.equal(report.status, 'UNKNOWN'); assert.equal(report.pitrEnabled, null);
});
test('malformed metadata does not turn unknown into disabled or verified', async () => {
  for (const bad of [null, {}, { ...data(), pitr_enabled: 'true' }, { ...data(), region: 'secret-value' },
    { ...data(), backups: [{ status: 'COMPLETED', inserted_at: 'bad', is_physical_backup: true }] }]) {
    const report = await run(bad); assert.equal(report.status, 'UNKNOWN'); assert.equal(report.pitrEnabled, null);
  }
});
test('select completed, not latest pending/failed; allow empty without claiming restore', async () => {
  const report = await run({ ...data(), backups: [...data().backups,
    { status: 'FAILED', inserted_at: '2026-09-30T04:00:00Z', is_physical_backup: false }] });
  assert.equal(report.latestCompletedAt, '2026-09-30T02:00:00.000Z');
  const empty = await run({ ...data(), backups: [] });
  assert.equal(empty.latestCompletedAt, null); assert.ok(empty.issues.includes('NO_COMPLETED_BACKUP_LISTED'));
});
test('valid PITR window is an observation, never a recovery guarantee', async () => {
  const report = await run({ ...data(), pitr_enabled: true, physical_backup_data: {
    earliest_physical_backup_date_unix: 1790704800, latest_physical_backup_date_unix: 1790751600,
    url: 'secret-download' } });
  assert.ok(report.physicalWindow); assert.equal(report.restoreVerified, false);
  assert.doesNotMatch(JSON.stringify(report), /secret-download/);
  assert.match(backupSummary(report), /ne valide ni une restauration ni un RPO\/RTO/);
});
test('unknown or invalid PITR window is explicit', async () => {
  for (const physical_backup_data of [undefined, { earliest_physical_backup_date_unix: 20, latest_physical_backup_date_unix: 10 }]) {
    const report = await run({ ...data(), pitr_enabled: true, physical_backup_data });
    assert.equal(report.physicalWindow, null); assert.ok(report.issues.includes('PITR_WINDOW_UNAVAILABLE'));
  }
});

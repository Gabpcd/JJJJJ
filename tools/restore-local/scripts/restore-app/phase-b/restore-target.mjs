import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { digest, fileTree } from '../snapshot-restore.mjs';
import { requireValue } from './contract.mjs';
const DB = 'jolene_candidatures_pg17_test';

export async function restoreTarget(runtime, privateDir, snapshot, reviewed, checkpointSql) {
  requireValue(snapshot.run === runtime.run && reviewed.nativeRestoreTocSha256 === snapshot.tocSha256
    && reviewed.nativeRoleSettingsReviewed === true, 'B_REVIEW');
  // Source has been exercised AFTER backup, with a post-backup marker; now all
  // five source services, including its DB, must remain stopped through target UI.
  await runtime.verifyState({ source: 'off', target: 'db-only', browser: 'absent' });
  await runtime.assertTargetNativeEmpty();
  await runtime.assertTargetFilesEmpty(); // Refuse existing bytes before any DROP/restore.
  const dump = readFileSync(join(privateDir, 'database.dump'));
  requireValue(digest(dump) === snapshot.archiveSha256
    && JSON.stringify(fileTree(join(privateDir, 'files'))) === JSON.stringify(snapshot.files), 'B_SNAPSHOT');
  // This ONLY replaces the named disposable database inside the independently
  // inspected target container. No DROP SCHEMA inside a populated target and no
  // --clean collisions with pre-existing native Auth/Storage schemas.
  await runtime.recreateOwnedEmptyTargetDatabase(DB);
  await runtime.databaseTool('target', 'pg_restore', [
    '--exit-on-error', '--single-transaction', '--no-password', '-U', 'supabase_admin',
    '-h', '/var/run/postgresql', '-d', DB,
  ], dump);
  // Archive order is pre-data / data / post-data, retaining native/product triggers,
  // policies, owners and ACLs. No --disable-triggers, no re-seed or substitutions.
  await runtime.applyReviewedRoleSettings();
  await runtime.assertTargetFilesEmpty(); // Recheck after restore, immediately before copy.
  await runtime.copyFilesIn('target', join(privateDir, 'files'));
  const restored = await runtime.sqlJson('target', checkpointSql);
  requireValue(JSON.stringify(restored) === JSON.stringify(snapshot.before), 'B_RESTORE');
  await runtime.assertSourceOffAndTargetCatalogExact(snapshot);
  // Explicit restart, not implicit assumption after the import qualifier's stop.
  await runtime.startApis('target');
  await runtime.assertApiHealthy('target');
  requireValue(JSON.stringify(await runtime.sqlJson('target', checkpointSql)) === JSON.stringify(snapshot.before),
    'B_RESTORE');
  return { restored: true, sourceOff: true, rowDigestsEqual: true, targetSeeded: false, providerContacted: false };
}

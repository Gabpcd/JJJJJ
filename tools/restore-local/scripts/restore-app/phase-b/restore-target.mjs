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
  const prepared = await runtime.prepareTargetArchiveRestore({archive:dump,archiveSha256:snapshot.archiveSha256,
    toc:readFileSync(join(privateDir,'archive-toc.private.txt')),witness:snapshot.catalogue.nativeGraphql,review:reviewed});
  // This ONLY replaces the named disposable database inside the independently
  // inspected target container. No DROP SCHEMA inside a populated target and no
  // --clean collisions with pre-existing native Auth/Storage schemas.
  await runtime.recreateOwnedEmptyTargetDatabase(DB);
  await runtime.executePreparedTargetRestore(prepared);
  // Native GraphQL archive prerequisites, the guarded vendor schema baseline,
  // then the complete complementary archive export execute in ONE transaction.
  // Every TOC entry remains present exactly once; both exports stay byte-exact.
  await runtime.applyReviewedRoleSettings();
  await runtime.assertTargetFilesEmpty(); // Recheck after restore, immediately before copy.
  await runtime.copyFilesIn('target', join(privateDir, 'files'));
  const restored = await runtime.sqlJson('target', checkpointSql);
  requireValue(JSON.stringify(restored) === JSON.stringify(snapshot.before), 'B_RESTORE');
  const graphql=await runtime.assertSourceOffAndTargetCatalogExact(snapshot);
  requireValue(graphql?.nativeGraphqlPrerequisiteVerified===true&&graphql.nativeGraphqlRestoredExact===true
    &&graphql.nativeGraphqlWrapperSchemaSemanticEqual===true&&typeof graphql.nativeGraphqlWrapperSchemaRawEqual==='boolean','B_RESTORE');
  // Explicit restart, not implicit assumption after the import qualifier's stop.
  await runtime.startApis('target');
  await runtime.assertApiHealthy('target');
  requireValue(JSON.stringify(await runtime.sqlJson('target', checkpointSql)) === JSON.stringify(snapshot.before),
    'B_RESTORE');
  return { restored: true, sourceOff: true, rowDigestsEqual: true, targetSeeded: false, providerContacted: false,
    nativeGraphqlPrerequisiteVerified:true,nativeGraphqlRestoredExact:true,
    nativeGraphqlWrapperSchemaRawEqual:graphql.nativeGraphqlWrapperSchemaRawEqual,nativeGraphqlWrapperSchemaSemanticEqual:true };
}

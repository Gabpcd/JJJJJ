import { phaseFailure } from './failure.mjs';
import { readFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { qualifiedSession } from '../restore/bootstrap.mjs';
import { qualify } from '../restore/qualify-import.mjs';
import { localRuntime } from './local-runtime.mjs';
import { newSourceFixture, seedSource } from './source-fixture.mjs';
import { captureSource, fileTree } from './snapshot-restore.mjs';
import { projectSnapshot, projectToc } from './projection.mjs';
import { hash, MIGRATION_COUNT } from './identity.mjs';

const required = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
// Imported dependency seams are for pure contract tests only; no CLI/env override.
export async function runPhaseA(evidence, paths, save, dependencies = {}) {
  const enter = stage => save({ stage, result: 'PHASE_A_IN_PROGRESS', readyForRestore: false,
    readyForDispatchPhaseB: false, restored: false, appVerified: false });
  const importer = dependencies.importer ?? (() => qualify({
    product_sha: evidence.productSha, harness_sha: evidence.harnessSha, run: evidence.run,
    migrations: evidence.migrations, test: evidence.test,
  }, qualifiedSession(paths.stack),
  readFileSync(new URL('../restore/preflight-extensions.sql', import.meta.url)),
  JSON.parse(readFileSync(new URL('../export/scope.json', import.meta.url))).extensions,
  report => dependencies.saveImport(report)));
  enter('import');
  const imported = await importer();
  required(imported?.result === 'ISOLATED_IMPORT_AND_SQL_TEST_PASSED' && imported.canonical_test_passed === true
    && imported.rollback_verified === true && imported.migrations.length === MIGRATION_COUNT
    && imported.product_sha === evidence.productSha
    && imported.migrations.every((file, index) => file.completed === true
      && file.path === evidence.migrations[index]?.path && file.sha256 === evidence.migrations[index]?.sha256),
    'PHASE_A_IMPORT_REQUIRED');
  const runtime = (dependencies.makeRuntime ?? localRuntime)(paths.stack);
  required(runtime.run === evidence.run, 'PHASE_A_RUNTIME_RUN');
  await runtime.verifyState({ source: 'db-only', target: 'db-only', browser: 'absent' });
  await runtime.assertTargetNativeEmpty();
  enter('current_product_witness');
  const currentProduct = await runtime.sqlJson('source', dependencies.currentProductSql
    ?? readFileSync(new URL('./sql/current-product-witness.sql', import.meta.url), 'utf8'));
  required(currentProduct && typeof currentProduct === 'object' && !Array.isArray(currentProduct)
    && JSON.stringify(Object.keys(currentProduct).sort()) === JSON.stringify(['certificateExact', 'functionsExact', 'localContext'])
    && Object.values(currentProduct).every(value => value === true), 'PHASE_A_CURRENT_PRODUCT_WITNESS');
  enter('source_api_restart');
  await runtime.startApis('source');
  await runtime.assertApiHealthy('source');
  const fixture = (dependencies.makeFixture ?? newSourceFixture)(evidence.productSha, evidence.run);
  await runtime.privateWrite(join(paths.stack, 'fixture.private.json'), Buffer.from(JSON.stringify(fixture)));
  enter('source_seed');
  const seeded = await (dependencies.seed ?? seedSource)(runtime, fixture);
  required(seeded.users === 5 && seeded.invoices === 1 && seeded.objects === 2, 'PHASE_A_SEED_REQUIRED');
  enter('object_readback');
  required((await runtime.verifyDocumentBytes(fixture)).verified === 2, 'PHASE_A_OBJECT_BYTES_REQUIRED');
  enter('capture');
  const snapshotDirectory = join(paths.stack, 'snapshot');
  (dependencies.makeDirectory ?? (path => mkdirSync(path, { mode: 0o700 })))(snapshotDirectory);
  const checkpoint = dependencies.checkpointSql ?? readFileSync(new URL('./sql/checkpoint.sql', import.meta.url), 'utf8');
  const snapshot = await (dependencies.capture ?? captureSource)(runtime, snapshotDirectory, checkpoint, enter);
  const snapshotReceipt = projectSnapshot(snapshot, fixture);
  const toc = projectToc((dependencies.readToc ?? (directory => readFileSync(join(directory, 'archive-toc.private.txt'))))(snapshotDirectory));
  required(toc.normalizedSha256 === snapshot.tocSha256, 'PHASE_A_TOC_HASH_CHANGED');
  const native = await runtime.sqlJson('source', dependencies.nativeSql ?? readFileSync(new URL('./sql/native-versions.sql', import.meta.url), 'utf8'));
  required(Number.isSafeInteger(native.postgresVersionNum) && native.postgresVersionNum >= 170000 && native.postgresVersionNum < 180000
    && ['auth', 'storage'].every(key => Number.isSafeInteger(native[key]?.count) && native[key].count > 0
      && /^[a-f0-9]{64}$/.test(native[key].sha256)), 'PHASE_A_NATIVE_INVENTORY');
  enter('source_off');
  await runtime.stopSource();
  await runtime.verifyState({ source: 'off', target: 'db-only', browser: 'absent' });
  await runtime.assertTargetNativeEmpty();
  const targetFiles = join(paths.stack, 'target-native-files');
  await runtime.copyFilesOut('target', targetFiles);
  required((dependencies.readFileTree ?? fileTree)(targetFiles).length === 0, 'PHASE_A_TARGET_FILES_NOT_EMPTY');
  const result = { result: 'PHASE_A_NATIVE_CAPTURE_PASSED', stage: 'complete',
    productSha: evidence.productSha, harnessSha: evidence.harnessSha,
    migrationCount: MIGRATION_COUNT, orderedMigrationsSha256: hash(JSON.stringify(evidence.migrations.map(({ path, sha256 }) => ({ path, sha256 })))),
    pinnedImportWitnessPassed: true, currentProductWitnessPassed: true, snapshot: snapshotReceipt, toc,
    native: { postgresVersionNum: native.postgresVersionNum,
      auth: { count: native.auth.count, sha256: native.auth.sha256 },
      storage: { count: native.storage.count, sha256: native.storage.sha256 } },
    sourceStopped: true, targetNativeEmpty: true, targetFilesEmpty: true,
    targetSeeded: false, restored: false, appVerified: false, providerContacted: false,
    readyForRestore: false, readyForDispatchPhaseB: false };
  save(result); return result;
}

import { phaseFailure } from './failure.mjs';
// Exact same-image local recovery candidate. No CLI entry point and no provider.
// The reviewed adapter must verify exact owned resources before every mutation.
import { createHash } from 'node:crypto';
import { lstatSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const DB = 'jolene_candidatures_pg17_test';
const requireValue = (ok, code, diagnostic) => { if (!ok) throw phaseFailure(code, diagnostic); };
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function normalizedToc(bytes) {
  const lines = bytes.toString('utf8').split(/\r?\n/).filter(line => line && !line.startsWith(';'));
  requireValue(lines.length > 100, 'RESTORE_TOC_MISSING');
  const entries = lines.map(line => {
    requireValue(/^\d+; \d+ \d+ /.test(line), 'RESTORE_TOC_FORMAT');
    return line.replace(/^\d+; \d+ \d+ /, '');
  }).sort();
  // Neither CREATE DATABASE nor global roles/passwords may enter this archive.
  requireValue(!entries.some(line => /^(DATABASE|DATABASE PROPERTIES|SUBSCRIPTION) /.test(line)), 'RESTORE_TOC_SCOPE');
  for (const table of ['auth users', 'auth identities', 'storage objects', 'public factures_honoraires', 'public factures_honoraires_documents']) {
    requireValue(entries.some(line => line.startsWith('TABLE DATA ' + table + ' ')), 'RESTORE_TOC_REQUIRED_DATA');
  }
  return Buffer.from(entries.join('\n') + '\n');
}
export function fileTree(directory) {
  const result = []; let total = 0;
  const visit = (where, relative) => {
    for (const name of readdirSync(where).sort()) {
      requireValue(name !== '.' && name !== '..' && !/[\x00-\x1f]/.test(name), 'RESTORE_FILE_NAME');
      const path = join(where, name), stat = lstatSync(path), rel = relative ? relative + '/' + name : name;
      requireValue(!stat.isSymbolicLink(), 'RESTORE_FILE_SYMLINK');
      if (stat.isDirectory()) visit(path, rel);
      else {
        requireValue(stat.isFile() && stat.nlink === 1 && stat.size <= 2 * 1024 * 1024, 'RESTORE_FILE_KIND');
        total += stat.size; requireValue(total <= 8 * 1024 * 1024 && result.length < 32, 'RESTORE_FILE_BOUND');
        result.push({ path: rel, bytes: stat.size, sha256: digest(readFileSync(path)) });
      }
    }
  };
  visit(directory, ''); return result;
}

export function assertEmptyFileTree(directory) {
  requireValue(fileTree(directory).length === 0, 'RESTORE_TARGET_FILES_NOT_EMPTY');
}

export async function captureSource(runtime, privateDir, checkpointSql) {
  // Snapshot PRECEDES all UI logins, so session/refresh tables are genuinely empty.
  await runtime.stopApis('source');
  await runtime.verifyState({ source: 'db-only', target: 'db-only', browser: 'absent' });
  const before = await runtime.sqlJson('source', checkpointSql);
  const catalogue = await runtime.catalogue('source');
  const dump = await runtime.databaseTool('source', 'pg_dump', [
    '-Fc', '--no-password', '-U', 'supabase_admin', '-h', '/var/run/postgresql', '-d', DB,
  ]);
  requireValue(dump.subarray(0, 5).toString() === 'PGDMP' && dump.length < 64 * 1024 * 1024, 'RESTORE_ARCHIVE_FORMAT');
  await runtime.privateWrite(join(privateDir, 'database.dump'), dump);
  const toc = await runtime.archiveList('source', dump);
  const normalized = normalizedToc(toc);
  await runtime.privateWrite(join(privateDir, 'archive-toc.private.txt'), toc);
  await runtime.privateWrite(join(privateDir, 'archive-toc-normalized.private.txt'), normalized);
  // docker cp reads the already stopped Storage container's mounted file volume.
  // All bytes, versions and internal layout are preserved; no API re-upload target.
  await runtime.copyFilesOut('source', join(privateDir, 'files'));
  const files = fileTree(join(privateDir, 'files'));
  requireValue(files.length >= 2, 'RESTORE_STORAGE_BYTES_MISSING');
  const after = await runtime.sqlJson('source', checkpointSql);
  requireValue(JSON.stringify(before) === JSON.stringify(after), 'RESTORE_SOURCE_CHANGED_DURING_BACKUP');
  const snapshot = { before, catalogue, files, archiveSha256: digest(dump), tocSha256: digest(normalized), run: runtime.run };
  await runtime.privateWrite(join(privateDir, 'snapshot.private.json'), Buffer.from(JSON.stringify(snapshot)));
  return snapshot;
}

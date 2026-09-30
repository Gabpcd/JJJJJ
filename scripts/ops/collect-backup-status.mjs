// Read-only inventory. A listed backup is not proof of a successful restore.
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PROJECT = 'flripxtsyegjshnhzjkz';
export const ENDPOINT = `https://api.supabase.com/v1/projects/${PROJECT}/database/backups`;
const STATUSES = new Set(['COMPLETED', 'FAILED', 'PENDING', 'REMOVED', 'ARCHIVED', 'CANCELLED']);
const isoDate = value => typeof value === 'string' && /^\d{4}-\d\d-\d\d[T ][\d:.+-]+Z?$/.test(value)
  && Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : null;
const unixDate = value => typeof value === 'number' && Number.isSafeInteger(value)
  && value > 0 && value <= 253402300799 ? new Date(value * 1000).toISOString() : null;

export async function collectBackupStatus({ token, fetchImpl = fetch, now = new Date().toISOString() }) {
  const report = {
    version: 1, projectRef: PROJECT, observedAt: isoDate(now), readOnly: true,
    status: 'UNKNOWN', pitrEnabled: null, walGEnabled: null, region: null,
    backups: [], physicalWindow: null, latestCompletedAt: null,
    restoreVerified: false, storageObjectsBackupVerified: false, issues: [],
  };
  if (!report.observedAt) { report.issues.push('INVALID_TIME'); return report; }
  if (typeof token !== 'string' || !token.trim()) { report.issues.push('TOKEN_ABSENT'); return report; }
  try {
    const response = await fetchImpl(ENDPOINT, {
      method: 'GET', redirect: 'error', signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    });
    if (!response.ok) {
      // Never emit provider error bodies, headers, URLs, credentials or stack traces.
      report.issues.push('BACKUP_API_UNAVAILABLE'); return report;
    }
    const data = await response.json();
    if (!data || typeof data.pitr_enabled !== 'boolean' || typeof data.walg_enabled !== 'boolean'
      || typeof data.region !== 'string' || !/^[a-z]{2}(?:-[a-z]+)+-\d$/.test(data.region)
      || !Array.isArray(data.backups) || data.backups.length > 10000
      || data.backups.some(b => !b || !STATUSES.has(b.status) || !isoDate(b.inserted_at)
        || typeof b.is_physical_backup !== 'boolean')) {
      report.issues.push('BACKUP_METADATA_INVALID'); return report;
    }
    report.status = 'OBSERVED';
    report.pitrEnabled = data.pitr_enabled;
    report.walGEnabled = data.walg_enabled;
    report.region = data.region;
    report.backups = data.backups.map(b => ({
      status: b.status, insertedAt: isoDate(b.inserted_at), physical: b.is_physical_backup,
    })).sort((a, b) => b.insertedAt.localeCompare(a.insertedAt));
    report.latestCompletedAt = report.backups.find(b => b.status === 'COMPLETED')?.insertedAt ?? null;
    const first = unixDate(data.physical_backup_data?.earliest_physical_backup_date_unix);
    const last = unixDate(data.physical_backup_data?.latest_physical_backup_date_unix);
    if (first && last && first <= last) report.physicalWindow = { from: first, to: last };
    if (!report.latestCompletedAt) report.issues.push('NO_COMPLETED_BACKUP_LISTED');
    if (!report.pitrEnabled) report.issues.push('PITR_DISABLED');
    if (report.pitrEnabled && !report.physicalWindow) report.issues.push('PITR_WINDOW_UNAVAILABLE');
    report.issues.push('RESTORE_NOT_TESTED', 'STORAGE_OBJECTS_NOT_COVERED_BY_DB_BACKUP');
  } catch {
    report.issues.push('BACKUP_API_UNAVAILABLE_OR_INVALID');
  }
  return report;
}

export function backupSummary(report) {
  return [
    '# Sauvegardes Supabase — inventaire en lecture seule', '',
    `Projet : ${PROJECT}. Observation : ${report.observedAt ?? 'indisponible'}.`,
    `Métadonnées : ${report.status}. PITR : ${report.pitrEnabled === null ? 'inconnu' : report.pitrEnabled ? 'activé' : 'désactivé'}.`,
    `Dernière sauvegarde listée COMPLETED : ${report.latestCompletedAt ?? 'aucune observée'}.`,
    `Fenêtre physique exposée par l’API : ${report.physicalWindow ? `${report.physicalWindow.from} → ${report.physicalWindow.to}` : 'indisponible'}.`, '',
    '**Ce rapport ne valide ni une restauration ni un RPO/RTO. Les octets des fichiers Storage ne sont pas inclus dans les sauvegardes de la base.**', '',
    `Points à traiter : ${report.issues.join(', ') || 'aucun dans ce périmètre'}.`, '',
  ].join('\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const out = process.argv[2];
  if (!out) { console.error('OUTPUT_DIRECTORY_REQUIRED'); process.exitCode = 1; }
  else {
    const report = await collectBackupStatus({ token: process.env.SUPABASE_ACCESS_TOKEN });
    mkdirSync(out, { recursive: true, mode: 0o700 });
    writeFileSync(resolve(out, 'backup-status.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
    writeFileSync(resolve(out, 'backup-status.md'), backupSummary(report), { mode: 0o600 });
    console.log(`BACKUP_INVENTORY_${report.status}`);
    if (report.status !== 'OBSERVED') process.exitCode = 1;
  }
}

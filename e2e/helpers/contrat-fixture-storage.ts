import type { SupabaseClient } from '@supabase/supabase-js';
import { createHash, randomUUID } from 'node:crypto';
import { constants, closeSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
type Original = { schema: 'playwright-contract-cleanup/v1'; projectRef: string; missionId: string; contratId: string; storagePath: string; recordedAt: string; sourceSha: string | null };
const defaultUrl = process.env.SUPABASE_URL || process.env.PLAYWRIGHT_SUPABASE_URL || process.env.E2E_SUPABASE_URL || '';

/** Registre local sans contenu, écrit avant purge et archivable avec le résumé CI.
 * Un fichier par original évite tout écrasement entre workers. Les anciens
 * artefacts peuvent être restaurés dans ce même dossier pour reprise ciblée.
 */
export function registreOriginauxFixture(url = defaultUrl, root = path.resolve('playwright-public/fixture-contract-cleanup')) {
  if (!/^https:\/\/[a-z]{20}\.supabase\.co\/?$/.test(url)) throw new Error('[cleanup original] projet refusé');
  const projectRef = new URL(url).hostname.split('.')[0];
  const directory = path.join(root, projectRef);
  function dossier() {
    // Refuser les symlinks de chaque composant avant toute lecture/écriture.
    let current = path.parse(path.resolve(directory)).root;
    for (const part of path.resolve(directory).slice(current.length).split(path.sep)) {
      current = path.join(current, part);
      try { mkdirSync(current, { mode: 0o700 }); }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
      const stat = lstatSync(current);
      if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('[cleanup original] dossier refusé');
    }
  }
  function syncDirectory() {
    const fd = openSync(directory, constants.O_RDONLY);
    try { fsyncSync(fd); } finally { closeSync(fd); }
  }
  function valider(value: Original) {
    if (Object.keys(value).sort().join(',') !== 'contratId,missionId,projectRef,recordedAt,schema,sourceSha,storagePath'
      || value.schema !== 'playwright-contract-cleanup/v1' || !Number.isFinite(Date.parse(value.recordedAt))
      || (value.sourceSha !== null && !/^[a-f0-9]{40}$/.test(value.sourceSha))
      || value.projectRef !== projectRef || !UUID.test(value.missionId) || !UUID.test(value.contratId)
      || typeof value.storagePath !== 'string' || !value.storagePath.startsWith(`${value.contratId}/`)
      || !UUID.test(value.storagePath.slice(value.contratId.length + 1, -5)) || !value.storagePath.endsWith('.html')) {
      throw new Error('[cleanup original] référence refusée');
    }
  }
  function filename(value: Original) { return `${value.missionId}-${createHash('sha256').update(value.storagePath).digest('hex')}.json`; }
  function lire(file: string): Original {
    const full = path.join(directory, file), stat = lstatSync(full);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 2048) throw new Error('[cleanup original] fichier refusé');
    const fd = openSync(full, constants.O_RDONLY | constants.O_NOFOLLOW);
    let value: Original;
    try { value = JSON.parse(readFileSync(fd, 'utf8')); } finally { closeSync(fd); }
    valider(value);
    if (filename(value) !== file) throw new Error('[cleanup original] nom refusé');
    return value;
  }
  return {
    enregistrer(missionId: string, contratId: string, storagePath: string) {
      const value: Original = { schema: 'playwright-contract-cleanup/v1', projectRef, missionId, contratId, storagePath,
        recordedAt: new Date().toISOString(), sourceSha: /^[a-f0-9]{40}$/.test(process.env.GITHUB_SHA ?? '') ? process.env.GITHUB_SHA! : null };
      valider(value); dossier();
      const file = filename(value), destination = path.join(directory, file);
      try {
        const previous = lire(file);
        if (previous.missionId !== missionId || previous.contratId !== contratId || previous.storagePath !== storagePath) throw new Error('[cleanup original] collision registre');
        return;
      } catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
      const temporary = path.join(directory, `.${randomUUID()}.tmp`);
      const fd = openSync(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      try { writeFileSync(fd, JSON.stringify(value) + '\n'); fsyncSync(fd); } finally { closeSync(fd); }
      renameSync(temporary, destination); syncDirectory();
    },
    lire(missionId?: string) {
      if (missionId !== undefined && !UUID.test(missionId)) throw new Error('[cleanup original] mission refusée');
      dossier();
      const files = readdirSync(directory).filter(file => file.endsWith('.json'));
      if (files.length > 2000) throw new Error('[cleanup original] registre trop grand');
      return files.map(lire).filter(value => missionId === undefined || value.missionId === missionId);
    },
    terminer(value: Original) { valider(value); dossier(); lire(filename(value)); unlinkSync(path.join(directory, filename(value))); syncDirectory(); },
  };
}

/** Appeler uniquement APRÈS les gardes de preparerMissionTechniquePourPurge. */
export async function memoriserOriginauxContratsFixture(admin: SupabaseClient, missionId: string, registre = registreOriginauxFixture()) {
  const { data, error } = await admin.from('contrats_mission' as any).select('id, mission_id, storage_path').eq('mission_id', missionId);
  if (error || !Array.isArray(data)) throw new Error('[cleanup mission] références des originaux indisponibles');
  for (const contrat of data) {
    if (contrat.mission_id !== missionId) throw new Error('[cleanup mission] contrat hors mission technique');
    if (contrat.storage_path != null) registre.enregistrer(missionId, contrat.id, contrat.storage_path);
  }
}

export async function supprimerOriginauxFixtureApresPurge(admin: SupabaseClient, missionId: string, registre = registreOriginauxFixture()) {
  const entries = registre.lire(missionId);
  if (!entries.length) return;
  const paths = entries.map(entry => entry.storagePath);
  const [mission, contrats, references] = await Promise.all([
    admin.from('missions' as any).select('id').eq('id', missionId).maybeSingle(),
    admin.from('contrats_mission' as any).select('id').eq('mission_id', missionId).limit(1),
    admin.from('contrats_mission' as any).select('id').in('storage_path', paths).limit(1),
  ]);
  if (mission.error || contrats.error || references.error || mission.data !== null
    || !Array.isArray(contrats.data) || contrats.data.length !== 0
    || !Array.isArray(references.data) || references.data.length !== 0) {
    throw new Error('[cleanup mission] purge non confirmée, originaux Storage conservés');
  }
  const { error } = await admin.storage.from('contrats-signes').remove(paths);
  if (error) throw new Error('[cleanup mission] retrait des originaux Storage non confirmé');
  for (const entry of entries) registre.terminer(entry);
}

export async function reprendreOriginauxContratsFixture(admin: SupabaseClient, url = defaultUrl, registre = registreOriginauxFixture(url)) {
  for (const missionId of new Set(registre.lire().map(entry => entry.missionId))) {
    const { data, error } = await admin.from('missions' as any).select('id').eq('id', missionId).maybeSingle();
    if (error) throw new Error('[cleanup original] état de mission indisponible');
    // Une quarantaine reste intacte. Le setup normal décidera de la purge DB.
    if (data === null) await supprimerOriginauxFixtureApresPurge(admin, missionId, registre);
  }
}

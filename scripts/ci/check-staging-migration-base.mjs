#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const migrationName = /^(\d{14})_[A-Za-z0-9_-]+\.sql$/;

/** Aucun SQL : borne le bootstrap persistant au contenu exact de la base main. */
export function validateMigrationBase({ baseFiles, remoteRows, changes }) {
  const versions = new Set();
  for (const name of baseFiles) {
    const match = migrationName.exec(name);
    if (!match || versions.has(match[1])) throw new Error('Noms ou versions des migrations de base ambigus.');
    versions.add(match[1]);
  }
  if (!versions.size) throw new Error('La base main ne contient aucune migration vérifiable.');
  for (const { status, path } of changes) {
    if (status !== 'A') {
      throw new Error('La PR modifie ou supprime une migration historique. Ajouter une nouvelle migration ; le SQL historique ne sera ni remplacé ni ignoré.');
    }
    const match = migrationName.exec(basename(path));
    if (!match || path !== `supabase/migrations/${match[0]}` || versions.has(match[1])) {
      throw new Error('Version ou chemin de migration PR ambigu : un nouveau fichier et une version distincte sont requis.');
    }
    // Repère aussi deux migrations nouvelles portant le même timestamp.
    versions.add(match[1]);
  }
  if (!Array.isArray(remoteRows) || remoteRows.some(row => !row || typeof row.version !== 'string' || !/^\d{14}$/.test(row.version))) {
    throw new Error('Réponse du registre staging invalide : aucune synchronisation autorisée.');
  }
  const baseVersions = new Set(baseFiles.map(name => name.slice(0, 14)));
  const outsideBase = [...new Set(remoteRows.map(row => row.version))].filter(version => !baseVersions.has(version));
  if (outsideBase.length) {
    throw new Error(`Le staging contient des migrations hors de la base main : ${outsideBase.sort().join(', ')}. Actualiser la base de la PR ou faire réconcilier le staging après revue ; aucun repair, reset ou déploiement PR automatique.`);
  }
  return { baseCount: baseVersions.size, remoteCount: remoteRows.length, addedCount: changes.length };
}

export function checkStagingMigrationBase({ baseDir, registryPath, baseSha = process.env.BASE_SHA, cwd = process.cwd() }) {
  if (!/^[a-f0-9]{40}$/.test(baseSha ?? '')) throw new Error('BASE_SHA exact requis pour vérifier les migrations.');
  const baseHead = execFileSync('git', ['-C', baseDir, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  if (baseHead !== baseSha) throw new Error('Le worktree de bootstrap ne correspond pas à BASE_SHA.');
  if (execFileSync('git', ['-C', baseDir, 'status', '--porcelain', '--untracked-files=all', '--', 'supabase/migrations'], { encoding: 'utf8' }).trim()) {
    throw new Error('Les migrations du worktree de base ont été modifiées : bootstrap refusé.');
  }
  const diff = execFileSync('git', ['diff', '--name-status', '--no-renames', '-z', `${baseSha}...HEAD`, '--', 'supabase/migrations/*.sql'], { cwd, encoding: 'utf8' });
  const parts = diff.split('\0');
  parts.pop();
  if (parts.length % 2) throw new Error('Diff des migrations illisible.');
  const changes = [];
  for (let i = 0; i < parts.length; i += 2) changes.push({ status: parts[i], path: parts[i + 1] });
  let remoteRows;
  try { remoteRows = JSON.parse(readFileSync(registryPath, 'utf8')); }
  catch { throw new Error('Registre staging JSON illisible : aucune synchronisation autorisée.'); }
  return validateMigrationBase({
    baseFiles: readdirSync(resolve(baseDir, 'supabase/migrations')).filter(name => name.endsWith('.sql')),
    remoteRows,
    changes,
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const [baseDir, registryPath] = process.argv.slice(2);
    if (!baseDir || !registryPath) throw new Error('Worktree de base et registre staging requis.');
    const result = checkStagingMigrationBase({ baseDir, registryPath });
    console.log(`Bootstrap main vérifié : ${result.baseCount} migrations de base, ${result.remoteCount} appliquées ; ${result.addedCount} migrations PR réservées au rollback.`);
  } catch (error) {
    console.error(`::error::${error instanceof Error ? error.message : 'Vérification du bootstrap impossible.'}`);
    process.exitCode = 1;
  }
}

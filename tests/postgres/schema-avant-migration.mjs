// Schéma du dépôt tel qu'il était AVANT une migration, pour les bancs qui rejouent cette migration.
//
// supabase/schema/public.sql est re-baseliné après chaque déploiement : il contient alors les corps APRÈS migration,
// et le préflight de la migration (empreintes LIVE d'avant) refuse de la rejouer (PR #1204, 27/11/2026). Un banc qui
// prouve « LIVE avant → migration → post-condition » charge donc le dump d'une révision épinglée, antérieure à la
// migration : commit, blob git et SHA-256 vérifiés, jamais un fichier de travail. Les migrations restent celles du
// dépôt (fichiers immuables, appliqués en production).
//
// La CI clone en profondeur 1 : l'étape du banc récupère le commit épinglé (`git fetch --depth=1 origin <commit>`).
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';

const CHEMIN = 'supabase/schema/public.sql';

/**
 * Dump avant #1198 et #1200 : re-baseline du 25/11/2026 après #1188 (#1193), dernière version de
 * supabase/schema/public.sql avant celle du 27/11/2026 qui intègre ces deux PR.
 */
export const DUMP_AVANT_REVUE_ET_SUPPRESSION = Object.freeze({
  commit: '739f3fcb4a97cbbc2fb8ec8734f74bd03f7a4a11',
  blob: '32bd710aeb7e03132c14a244d507e1655c7f8286',
  sha256: '6e2a0f85ec1ea1812bb31c72b662b69d11419a231e68649d74bd86a60bd2a2bf',
});

/**
 * Dump avant les migrations 20261128140000 et 20261128140100 (effacement des pièces à la suppression du compte
 * soignant) : re-baseline du 27/11/2026 après #1198 et #1200 (#1204).
 */
export const DUMP_AVANT_EFFACEMENT_PIECES = Object.freeze({
  commit: '1bfb14e8c3bf2ccf08a0d6164300a1acb067d2d9',
  blob: 'dc04e5dac3dbd7d63a22bc7c6f8b9ae06e28005b',
  sha256: '8ed217585fbbf50683fa87bd01c2c1aac9162cb3e796daf915e61488310f531c',
});

/**
 * Dump avant la migration 20261128120000 (B9, notifications et classement) : re-baseline du 27/11/2026 (#1204),
 * identique à main au 28/11/2026.
 */
export const DUMP_AVANT_B9_NOTIFICATIONS = Object.freeze({
  commit: '1bfb14e8c3bf2ccf08a0d6164300a1acb067d2d9',
  blob: 'dc04e5dac3dbd7d63a22bc7c6f8b9ae06e28005b',
  sha256: '8ed217585fbbf50683fa87bd01c2c1aac9162cb3e796daf915e61488310f531c',
});

const git = args => execFileSync('git', args, { cwd: RACINE, encoding: 'utf8', maxBuffer: 1 << 28,
  stdio: ['ignore', 'pipe', 'pipe'], env: { PATH: process.env.PATH, LC_ALL: 'C', GIT_TERMINAL_PROMPT: '0' } });

/** Contenu vérifié du dump épinglé ; erreur explicite si le commit n'est pas dans le clone. */
export function dumpEpingle({ commit, blob, sha256 }, lire = git) {
  let objet;
  try {
    objet = lire(['rev-parse', '--verify', '--quiet', `${commit}:${CHEMIN}`]).trim();
  } catch {
    throw new Error(`Dump épinglé introuvable : commit ${commit} absent du clone. En CI : git fetch --no-tags --depth=1 origin ${commit}`);
  }
  if (objet !== blob) throw new Error(`Dump épinglé : blob ${objet} au lieu de ${blob} pour ${commit}:${CHEMIN}`);
  const contenu = lire(['cat-file', 'blob', blob]);
  const empreinte = createHash('sha256').update(contenu, 'utf8').digest('hex');
  if (empreinte !== sha256) throw new Error(`Dump épinglé : SHA-256 ${empreinte} au lieu de ${sha256}`);
  return contenu;
}

/**
 * Racine temporaire pour `charger(…, { racine })` : le dump épinglé, et un lien vers les migrations du dépôt.
 * Rendue avec `nettoyer()`.
 */
export function racineAvant(epingle, { lire = git } = {}) {
  const dossier = mkdtempSync(join(tmpdir(), 'jolene-schema-avant-'));
  try {
    mkdirSync(join(dossier, 'supabase/schema'), { recursive: true });
    writeFileSync(join(dossier, CHEMIN), dumpEpingle(epingle, lire));
    symlinkSync(join(RACINE, 'supabase/migrations'), join(dossier, 'supabase/migrations'), 'dir');
  } catch (e) {
    rmSync(dossier, { recursive: true, force: true });
    throw e;
  }
  return { racine: dossier, nettoyer: () => rmSync(dossier, { recursive: true, force: true }) };
}

/**
 * Corps (pg_proc.prosrc) de `schema.nom` dans un dump pg_dump (noms entre guillemets ; délimiteur `$$` ou `$_$`
 * quand le corps contient `$$`) ; null si absente.
 */
export function corpsDuDump(dump, schema, nom) {
  const i = dump.indexOf(`CREATE OR REPLACE FUNCTION "${schema}"."${nom}"(`);
  if (i < 0) return null;
  const suite = dump.slice(i);
  const ouverture = /\bAS\s+(\$[A-Za-z0-9_]*\$)/.exec(suite);
  if (!ouverture) return null;
  const debut = ouverture.index + ouverture[0].length;
  return suite.slice(debut, suite.indexOf(ouverture[1], debut));
}

export const md5 = texte => createHash('md5').update(texte, 'utf8').digest('hex');

/**
 * État du dump courant pour des fonctions redéfinies par une migration : tout LIVE d'avant (migration pas encore
 * re-baselinée) ou tout APRÈS (re-baseline fidèle) ; jamais un mélange ni une troisième version.
 */
export function etatDuDumpCourant(fonctions, dump = readFileSync(join(RACINE, CHEMIN), 'utf8')) {
  const lus = fonctions.map(({ schema, nom, avant, apres }) => {
    const corps = corpsDuDump(dump, schema, nom);
    const empreinte = corps === null ? null : md5(corps);
    return { fonction: `${schema}.${nom}`, empreinte, etat: empreinte === avant ? 'AVANT' : empreinte === apres ? 'APRES' : 'AUTRE' };
  });
  const etats = new Set(lus.map(l => l.etat));
  return { etat: etats.size === 1 ? [...etats][0] : 'MELANGE', fonctions: lus };
}

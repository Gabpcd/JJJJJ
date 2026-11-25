#!/usr/bin/env node
/**
 * Banc SQL local de la cohorte STAGING du lot 5 (`staging-lot5-fixture.mjs`) : exécute TOUT le SQL que le script
 * génère sur une vraie base PostgreSQL chargée avec le schéma du dépôt, sans réseau ni projet Supabase.
 *
 * Pourquoi (premier run STAGING, 25/11/2026) : deux défauts n'apparaissaient qu'à l'exécution — un type
 * (`uuid = uuid[]` sur `ANY(sous-requête)`) et un déclencheur (`trg_zz_geler_mission` régénère le code de pointage à
 * l'assignation). Aucun test sur transport simulé ne pouvait les voir.
 *
 * Ce que fait le banc :
 *   1. socle Supabase minimal : rôles `anon`, `authenticated`, `service_role` ; schémas `auth` (table `users`,
 *      `auth.uid()`, `auth.role()`, `auth.jwt()` lus dans `request.jwt.claim*`), `extensions` (pgcrypto, uuid-ossp,
 *      pg_trgm), `net` (`http_post` sans effet), `vault` (`decrypted_secrets` vide), `cron` (tables et `schedule`
 *      sans effet), `storage` ;
 *   2. `supabase/schema/public.sql` instruction par instruction (corps de fonction non validés à la création, comme le
 *      dump l'impose), puis la dernière définition de chaque fonction `private.*` qu'il référence, relue dans
 *      `supabase/migrations/` ; les instructions qui échouent faute d'objet hors du dépôt sont comptées, jamais
 *      ignorées en silence : le banc exige que toutes les tables et fonctions touchées par la cohorte soient chargées ;
 *   3. le parcours complet de la cohorte avec le SQL EXACT du script : préparation (déclencheurs réels), candidature et
 *      scans sous JWT simulé, relectures, résidus, nettoyage par graphe, compte final à 0 ; puis une cohorte PARTIELLE
 *      (comptes Auth seuls, comme après l'échec du premier run) retrouvée par étiquette et nettoyée ; enfin une cohorte
 *      dont M2 porte un bulletin de paie (table non supprimable) : résidu compté, conservé avec ses parents, reste supprimé.
 *
 * Moteurs : PGlite (local, `--pglite <dossier node_modules>`) ou PostgreSQL 17 éphémère de la CI (`psql`, voir
 * `tests/postgres/staging-lot5-fixture.pg17.mjs`). Aide au développement et garde de CI : la preuve d'intégration
 * reste le workflow `ios-swift-lot5-staging.yml` sur le STAGING.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  manifeste, sqlPreparer, sqlCode, sqlCandidature, sqlPresence, sqlVerifier, sqlNettoyer, sqlCompter, sqlResidus,
  sqlRetrouverRun, cibleDepuisRecherche, lireResidus, totalMarques, GRAPHE_NETTOYAGE, lireGraphe, KIND,
} from './staging-lot5-fixture.mjs';

export const RACINE = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Découpe un script SQL en instructions (guillemets, identifiants, dollar-quotes et commentaires respectés). */
export function decouper(sql) {
  const sortie = [];
  let debut = 0, i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    if (c === '-' && sql[i + 1] === '-') { const fin = sql.indexOf('\n', i); i = fin < 0 ? n : fin + 1; continue; }
    if (c === '/' && sql[i + 1] === '*') { const fin = sql.indexOf('*/', i + 2); i = fin < 0 ? n : fin + 2; continue; }
    if (c === "'") { i += 1; while (i < n) { if (sql[i] === "'") { if (sql[i + 1] === "'") { i += 2; continue; } break; } i += 1; } i += 1; continue; }
    if (c === '"') { const fin = sql.indexOf('"', i + 1); i = fin < 0 ? n : fin + 1; continue; }
    if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 64));
      if (m) { const fin = sql.indexOf(m[0], i + m[0].length); i = fin < 0 ? n : fin + m[0].length; continue; }
    }
    if (c === ';') { const s = sql.slice(debut, i + 1).trim(); if (s.replace(/;$/, '').trim()) sortie.push(s); debut = i + 1; }
    i += 1;
  }
  const reste = sql.slice(debut).trim();
  if (reste) sortie.push(reste);
  return sortie;
}

/** Socle Supabase minimal, sans aucun objet de `public`. */
export const SOCLE = `
DO $r$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
END $r$;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS net;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE SCHEMA IF NOT EXISTS cron;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY, instance_id uuid, aud text, role text, email text, phone text, encrypted_password text,
  email_confirmed_at timestamptz, phone_confirmed_at timestamptz, last_sign_in_at timestamptz,
  raw_app_meta_data jsonb DEFAULT '{}'::jsonb, raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(), banned_until timestamptz,
  deleted_at timestamptz, is_anonymous boolean DEFAULT false, is_sso_user boolean DEFAULT false);
CREATE TABLE IF NOT EXISTS auth.sessions (id uuid PRIMARY KEY, user_id uuid, created_at timestamptz);
CREATE TABLE IF NOT EXISTS auth.identities (id uuid PRIMARY KEY, user_id uuid);
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $f$
  SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $f$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $f$
  SELECT nullif(coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), auth.jwt()->>'sub'), '')::uuid $f$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), auth.jwt()->>'role') $f$;
CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $f$ SELECT auth.jwt()->>'email' $f$;
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000) RETURNS bigint LANGUAGE sql AS $f$ SELECT 0::bigint $f$;
CREATE TABLE IF NOT EXISTS net._http_response (id bigint, status_code integer, created timestamptz, content text, error_msg text);
CREATE TABLE IF NOT EXISTS vault.secrets (name text, secret text);
CREATE OR REPLACE VIEW vault.decrypted_secrets AS SELECT name, secret AS decrypted_secret FROM vault.secrets;
CREATE TABLE IF NOT EXISTS cron.job (jobid bigint, jobname text, schedule text, command text, active boolean);
CREATE TABLE IF NOT EXISTS cron.job_run_details (jobid bigint, status text, start_time timestamptz, end_time timestamptz, return_message text);
CREATE OR REPLACE FUNCTION cron.schedule(text, text, text) RETURNS bigint LANGUAGE sql AS $f$ SELECT 0::bigint $f$;
CREATE OR REPLACE FUNCTION cron.unschedule(text) RETURNS boolean LANGUAGE sql AS $f$ SELECT true $f$;
CREATE TABLE IF NOT EXISTS storage.objects (id uuid, bucket_id text, name text);
GRANT USAGE ON SCHEMA auth, extensions, public, private TO anon, authenticated, service_role;
`;

/** Tables et fonctions sans lesquelles le parcours ne prouve rien : leur absence fait échouer le banc. */
export const REQUIS = {
  tables: ['etablissements', 'soignants', 'missions', 'mission_creneaux', 'candidatures', 'contrats_mission', 'presences',
    'scans_pointage', 'notifications', 'preferences_notifications', 'documents_soignants', 'paiements_escrow',
    'escrow_release_queue', 'notations_missions', 'email_queue', 'membres_etablissement'],
  fonctions: ['fn_test_update_mission', 'fn_blocage_publication_etab', 'fn_postuler_mission', 'fn_scanner_code_pointage',
    'fn_geler_mission_a_assignation', 'dec_proteger_mission_soignant'],
};

/** Instruction sans ses commentaires de tête. */
const sansCommentairesDeTete = instr => instr.replace(/^(?:\s*(?:--[^\n]*\n|\/\*[\s\S]*?\*\/))*\s*/, '');

/**
 * Objets du schéma `private` relus dans les migrations du dépôt (le dump ne couvre que `public`) : tables, types,
 * séquences, index et ALTER TABLE dans l'ordre des migrations, puis la DERNIÈRE définition de chaque fonction.
 */
export function objetsPrives(racine = RACINE) {
  const structure = [];
  const fonctions = new Map();
  const dossier = join(racine, 'supabase/migrations');
  for (const fichier of readdirSync(dossier).filter(f => f.endsWith('.sql')).sort()) {
    for (const brute of decouper(readFileSync(join(dossier, fichier), 'utf8'))) {
      const instr = sansCommentairesDeTete(brute);
      const f = /^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+"?private"?\."?([a-z0-9_]+)"?\s*\(/i.exec(instr);
      if (f) { fonctions.set(f[1], instr.replace(/^CREATE\s+FUNCTION/i, 'CREATE OR REPLACE FUNCTION')); continue; }
      if (/^(?:CREATE\s+(?:TABLE|TYPE|SEQUENCE|(?:UNIQUE\s+)?INDEX)\b[^;(]*?\bprivate\.|ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?private\.)/i.test(instr)) {
        structure.push(instr);
      }
    }
  }
  return { structure, fonctions: [...fonctions.values()] };
}

/**
 * Charge le schéma : `executer(sql)` lève sur une erreur. Rend le nombre d'instructions et les échecs (par motif).
 */
export async function charger(executer, { racine = RACINE, journal = () => {}, lot } = {}) {
  const dump = decouper(readFileSync(join(racine, 'supabase/schema/public.sql'), 'utf8'))
    .filter(s => !/^SELECT pg_catalog\.set_config\('search_path'/.test(s));
  const prives = objetsPrives(racine);
  // Ordre : socle, `private` (avant le dump : types et tables dont public dépend), le dump, puis `private` de nouveau
  // (objets qui dépendent de public) ; corps de fonction non validés à la création, comme le dump l'impose.
  const instructions = [...decouper(SOCLE), 'SET check_function_bodies = false', 'SET search_path = public, extensions',
    ...prives.structure, ...prives.fonctions, ...dump, ...prives.structure, ...prives.fonctions,
    'RESET check_function_bodies', 'SET search_path = public, extensions'];
  const executerLot = lot ?? (async liste => {
    const echecs = [];
    let passe = 0;
    for (const instr of liste) {
      try { await executer(instr); passe += 1; } catch (e) { echecs.push(String(e?.message ?? e).slice(0, 200)); }
    }
    return { passe, echecs };
  });
  const { passe, echecs } = await executerLot(instructions);
  journal(`schéma chargé : ${instructions.length} instruction(s), ${passe} exécutée(s), ${echecs.length} en échec `
    + '(objets hors du dépôt, ou objets `private` rejoués avant leurs dépendances puis rechargés)');
  const requis = [...REQUIS.tables.map(t => `public.${t}`), ...lireGraphe(GRAPHE_NETTOYAGE).map(t => `public.${t.table}`)];
  const [verif] = await executer(`SELECT
    (SELECT coalesce(json_agg(t), '[]') FROM unnest(ARRAY[${requis.map(t => `'${t}'`).join(', ')}]) t WHERE to_regclass(t) IS NULL) AS tables,
    (SELECT coalesce(json_agg(f), '[]') FROM unnest(ARRAY[${REQUIS.fonctions.map(f => `'${f}'`).join(', ')}]) f
       WHERE NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = f)) AS fonctions;`);
  const lire = v => (typeof v === 'string' ? JSON.parse(v) : v) ?? [];
  const manquants = [...lire(verif?.tables), ...lire(verif?.fonctions).map(f => `${f}()`)];
  if (manquants.length) throw new Error(`Banc L5 : objets requis non chargés : ${manquants.join(', ')}`);
  return { instructions: instructions.length, passe, echecs };
}

/** Exécute une requête en contexte utilisateur simulé (JWT `authenticated`), dans une transaction annulée ou validée. */
const sousJwt = (sub, sql) => `BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '${sub}', true), set_config('request.jwt.claim.role', 'authenticated', true),
  set_config('request.jwt.claims', '{"sub":"${sub}","role":"authenticated"}', true);
${sql}
COMMIT;`;

/** Comptes Auth du run tels que l'API d'administration les crée (`preparer`). */
const sqlAuth = m => [['etablissement', 'ETABLISSEMENT'], ['soignant', 'SOIGNANT']].map(([qui, role]) =>
  `INSERT INTO auth.users (id, email, email_confirmed_at, raw_app_meta_data, role, aud)
   VALUES ('${m[qui].id}', '${m[qui].email}', now(), '${JSON.stringify({ role, est_compte_test: true, is_test_playwright: true,
     load_fixture_kind: KIND, load_fixture_run: m.runId })}'::jsonb, 'authenticated', 'authenticated');`).join('\n');

/**
 * Parcours complet. `executer(sql)` rend les lignes de la dernière instruction. Chaque étape est le SQL EXACT du script
 * (préparation, relectures, résidus, nettoyage, compte, recherche par étiquette) ; seules les étapes jouées côté
 * client par le script (API Auth, RPC sous JWT) sont reproduites ici en SQL.
 */
export async function parcours(executer, { journal = () => {}, maintenant = new Date() } = {}) {
  const etapes = [];
  const pas = async (nom, sql) => {
    try {
      const lignes = await executer(sql);
      etapes.push({ nom, ok: true });
      return lignes;
    } catch (e) {
      etapes.push({ nom, ok: false, erreur: String(e?.message ?? e) });
      throw new Error(`Banc L5, étape « ${nom} » : ${String(e?.message ?? e)}`);
    }
  };

  // 1. Cohorte complète.
  const m = manifeste(`banc-${maintenant.getTime().toString(36)}`, maintenant);
  await pas('comptes Auth', sqlAuth(m));
  const [prep] = await pas('préparation (sqlPreparer)', sqlPreparer(m));
  if (prep?.prepare !== true) throw new Error('Banc L5 : préparation non confirmée.');
  await pas('candidature de S1 (fn_postuler_mission sous JWT)', sousJwt(m.soignant.id,
    `SELECT public.fn_postuler_mission('${m.m1.id}'::uuid, '${m.marker}', 'SALARIE');`));
  const candidatures = await pas('relecture de la candidature (sqlCandidature)', sqlCandidature(m));
  if (candidatures.length !== 1 || candidatures[0].statut !== 'EN_ATTENTE') {
    throw new Error(`Banc L5 : candidature EN_ATTENTE attendue, relu ${JSON.stringify(candidatures)}.`);
  }
  m.candidatureId = candidatures[0].id;
  const [code] = await pas('code de pointage (sqlCode)', sqlCode(m));
  if (!/^\d{6}$/.test(code?.code ?? '') || code.statut !== 'ASSIGNEE' || code.prochain_type_scan !== 'OUVERTURE') {
    throw new Error(`Banc L5 : M2 non prête au pointage (${JSON.stringify({ ...code, code: code?.code ? 'six chiffres ?' : null })}).`);
  }
  await pas('scan d arrivée de S1 (fn_scanner_code_pointage sous JWT)', sousJwt(m.soignant.id,
    `SELECT public.fn_scanner_code_pointage('${code.code}', '{"id_terminal":"banc-l5"}'::jsonb);`));
  // L'anti-rejeu serveur exige deux minutes entre deux scans : le banc recule l'horodatage du premier (banc seul).
  await pas('recul du premier scan (banc)', `UPDATE public.scans_pointage SET scanne_le = scanne_le - interval '3 minutes'
    WHERE mission_id = '${m.m2.id}';`);
  const [milieu] = await pas('code après l arrivée (sqlCode)', sqlCode(m));
  if (milieu?.prochain_type_scan !== 'FERMETURE') throw new Error('Banc L5 : arrivée non relue.');
  await pas('scan de départ de S1 (fn_scanner_code_pointage sous JWT)', sousJwt(m.soignant.id,
    `SELECT public.fn_scanner_code_pointage('${milieu.code}', '{"id_terminal":"banc-l5"}'::jsonb);`));
  const presences = await pas('présence de S1 (sqlPresence)', sqlPresence(m));
  if (presences.length !== 1 || presences[0].arrivee !== true || presences[0].depart !== true) {
    throw new Error(`Banc L5 : présence attendue, relu ${JSON.stringify(presences)}.`);
  }
  m.presenceId = presences[0].id;
  const [relu] = await pas('relectures (sqlVerifier)', sqlVerifier(m));
  for (const cle of ['escrow', 'escrow_file', 'emails_cohorte', 'canaux_ouverts']) {
    if (relu?.[cle] !== 0) throw new Error(`Banc L5 : relecture ${cle} = ${relu?.[cle]}, attendu 0.`);
  }
  const residus = lireResidus((await pas('résidus non supprimables (sqlResidus)', sqlResidus(m)))[0]);
  if (residus.length) throw new Error(`Banc L5 : résidus inattendus ${JSON.stringify(residus)}.`);
  const [nettoye] = await pas('nettoyage (sqlNettoyer)', sqlNettoyer(m));
  if (nettoye?.nettoye !== true) throw new Error('Banc L5 : nettoyage non confirmé.');
  await pas('suppression Auth (API d administration)', `DELETE FROM auth.users WHERE id IN ('${m.etablissement.id}', '${m.soignant.id}');`);
  const [compte] = await pas('compte final (sqlCompter)', sqlCompter(m));
  const total = totalMarques(compte);
  if (total !== 0) throw new Error(`Banc L5 : ${total} objet(s) marqué(s) restant(s) : ${JSON.stringify(compte)}.`);
  journal(`cohorte complète : préparée, parcourue, nettoyée, 0 objet marqué`);

  // 2. Cohorte PARTIELLE (comptes Auth seuls, comme après l'échec de la préparation du premier run) : reprise par étiquette.
  const p = manifeste(`banc-p-${maintenant.getTime().toString(36)}`, maintenant);
  await pas('comptes Auth (cohorte partielle)', sqlAuth(p));
  const [trouve] = await pas('recherche par étiquette (sqlRetrouverRun)', sqlRetrouverRun(p.runId));
  const cible = cibleDepuisRecherche(p.runId, trouve);
  if (cible.auth.length !== 2 || cible.etablissement.id !== p.etablissement.id || cible.soignant.id !== p.soignant.id) {
    throw new Error(`Banc L5 : cohorte partielle mal retrouvée (${cible.auth.length} identité(s)).`);
  }
  lireResidus((await pas('résidus (cohorte partielle)', sqlResidus(cible)))[0]);
  await pas('nettoyage (cohorte partielle)', sqlNettoyer(cible));
  await pas('suppression Auth (cohorte partielle)', `DELETE FROM auth.users WHERE id IN ('${p.etablissement.id}', '${p.soignant.id}');`);
  const [comptePartiel] = await pas('compte final (cohorte partielle)', sqlCompter(cible));
  if (totalMarques(comptePartiel) !== 0) throw new Error('Banc L5 : cohorte partielle non nettoyée.');
  const [vide] = await pas('recherche après nettoyage', sqlRetrouverRun(p.runId));
  const apres = cibleDepuisRecherche(p.runId, vide);
  if (apres.auth.length || apres.etablissement.id || apres.soignant.id) throw new Error('Banc L5 : la recherche retrouve encore le run.');
  journal('cohorte partielle : retrouvée par étiquette, nettoyée, 0 objet marqué');

  // 3. Résidu non supprimable : un bulletin de paie de M2 (créé ici par le banc, comme le ferait le passage TERMINEE).
  //    Il est compté avant, jamais supprimé ; ses parents (M2, S1, E1) restent ; tout le reste de la cohorte part.
  const r = manifeste(`banc-r-${maintenant.getTime().toString(36)}`, maintenant);
  await pas('comptes Auth (résidu)', sqlAuth(r));
  await pas('préparation (résidu)', sqlPreparer(r));
  await pas('bulletin de paie de M2 (banc)', `INSERT INTO public.bulletins_paie (numero_bulletin, soignant_id, mission_id,
    etablissement_id, periode_debut, periode_fin, salaire_brut, net_avant_impot)
    VALUES ('${r.marker}-BP', '${r.soignant.id}', '${r.m2.id}', '${r.etablissement.id}', current_date, current_date, 0, 0);`);
  const residusR = lireResidus((await pas('résidus (résidu)', sqlResidus(r)))[0]);
  if (residusR.length !== 1 || residusR[0][0] !== 'bulletins_paie' || residusR[0][1].length !== 1) {
    throw new Error(`Banc L5 : résidu attendu dans bulletins_paie, relu ${JSON.stringify(residusR)}.`);
  }
  await pas('nettoyage (résidu)', sqlNettoyer(r));
  const [compteR] = await pas('compte final (résidu)', sqlCompter(r));
  // Restent les parents du bulletin et ce qui part par cascade avec eux (créneau PREVISIONNEL de M2, justificatifs de S1).
  const attendu = { missions: 1, creneaux: 1, soignants: 1, etablissements: 1, auth: 2, documents: 2 };
  for (const [cle, n] of Object.entries(compteR)) {
    if ((attendu[cle] ?? 0) !== n) throw new Error(`Banc L5 : après nettoyage avec résidu, ${cle} = ${n} (attendu ${attendu[cle] ?? 0}).`);
  }
  journal('résidu non supprimable : compté avant, conservé avec ses parents (M2, S1, E1), reste de la cohorte supprimé');
  return etapes;
}

/** Moteur PGlite : `executer` rend les lignes de la dernière instruction qui en rend. */
export async function moteurPglite(dossierModules) {
  const base = pathToFileURL(join(resolve(dossierModules), '@electric-sql/pglite/dist/'));
  const { PGlite } = await import(new URL('index.js', base).href);
  const extensions = {};
  for (const nom of ['pgcrypto', 'uuid_ossp', 'pg_trgm']) {
    const mod = await import(new URL(`contrib/${nom}.js`, base).href);
    extensions[nom] = mod[nom];
  }
  const db = await PGlite.create({ extensions });
  return {
    executer: async sql => {
      const resultats = await db.exec(sql);
      const avecLignes = resultats.filter(r => Array.isArray(r.rows) && r.fields?.length);
      return avecLignes.length ? avecLignes.at(-1).rows : [];
    },
    fermer: () => db.close(),
  };
}

/**
 * Moteur `psql` (PostgreSQL 17 éphémère de la CI) : une invocation par étape. Seule la dernière instruction de l'étape
 * est relue (sortie JSON) ; les autres s'exécutent dans la même session, sortie écartée. Le chargement du schéma passe en
 * une seule invocation, sans arrêt sur erreur, échecs comptés sur la sortie d'erreur.
 */
export function moteurPsql({ spawn, env = process.env }) {
  const lancer = (script, arreter = true) => spawn('psql', ['-X', '-qAt', '-v', `ON_ERROR_STOP=${arreter ? 1 : 0}`, '-f', '-'],
    { input: script, env, encoding: 'utf8', maxBuffer: 1 << 28, timeout: 240_000 });
  const executer = async sql => {
    const instructions = decouper(sql);
    const derniere = instructions.pop() ?? '';
    const lisible = /^(SELECT|WITH)\b/i.test(derniere.trim());
    const script = `\\o /dev/null\n${instructions.join('\n')}\n\\o\n`
      + (lisible ? `SELECT coalesce(json_agg(r), '[]') FROM (${derniere.replace(/;\s*$/, '')}) r;\n` : `${derniere}\n`);
    const r = lancer(script);
    if (r.status !== 0) throw new Error((r.stderr || r.error?.message || 'psql en échec').trim().split('\n').filter(l => /ERROR|ERREUR/.test(l)).join(' ') || r.stderr);
    return lisible ? JSON.parse(r.stdout.trim().split('\n').at(-1) || '[]') : [];
  };
  const lot = async liste => {
    const r = lancer(liste.map(i => (i.endsWith(';') ? i : `${i};`)).join('\n'), false);
    const echecs = (r.stderr || '').split('\n').filter(l => /ERROR:/.test(l));
    return { passe: liste.length - echecs.length, echecs };
  };
  return { executer, lot };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const i = process.argv.indexOf('--pglite');
  if (i < 0 || !process.argv[i + 1]) {
    console.error('Usage : node scripts/mobile/staging-lot5-banc-sql.mjs --pglite <dossier node_modules contenant @electric-sql/pglite>');
    process.exit(2);
  }
  const debut = Date.now();
  const moteur = await moteurPglite(process.argv[i + 1]);
  try {
    const { passe, echecs } = await charger(moteur.executer, { journal: console.log });
    const motifs = new Map();
    for (const e of echecs) { const k = e.replace(/"[^"]*"/g, '"…"').slice(0, 90); motifs.set(k, (motifs.get(k) ?? 0) + 1); }
    for (const [k, v] of [...motifs].sort((a, b) => b[1] - a[1]).slice(0, 15)) console.log(`  échec ×${v} : ${k}`);
    const etapes = await parcours(moteur.executer, { journal: console.log });
    console.log(`Banc L5 : ${passe} instruction(s) de schéma exécutée(s), ${etapes.length} étape(s) du parcours exécutée(s), `
      + `toutes réussies (${Math.round((Date.now() - debut) / 1000)} s au total).`);
  } catch (e) {
    console.error(String(e?.message ?? e));
    process.exitCode = 1;
  } finally {
    await moteur.fermer();
  }
}

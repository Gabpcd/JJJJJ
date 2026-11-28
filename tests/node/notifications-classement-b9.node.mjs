// B9 : notifications écrites par les clients et classement des soignants (20261128150000), contrôle hors réseau.
// Ne remplace ni la suite SQL du staging (tests/security/notifications-classement-b9.test.sql, ROLLBACK) ni le banc
// PostgreSQL 17 / PGlite (tests/postgres/notifications-classement-b9.pg17.mjs) ; verrouille :
//   * la forme de la migration (horodatage, aucun BEGIN/COMMIT, délimiteurs nommés, préflight, post-condition) ;
//   * fn_creer_notification : REVOKE à PUBLIC, anon et authenticated, corps LIVE inchangé (dump), aucune redéfinition ;
//   * les RPC de remplacement : gardes, texte et lien posés par le serveur, droits explicites ;
//   * le classement : réservé, cohorte de l'appelant, pseudonymisé, sans identifiant, borne conservée ;
//   * aucun appel client de fn_creer_notification (web, natif, edge) ;
//   * le câblage CI : suite dans SQL_TESTS, banc PG17 sur dump épinglé, ce contrôle.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const RACINE = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(join(RACINE, path), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261128150000_borner_notifications_et_classement.sql';
const PRECEDENTE = '20261127100000'; // dernière version connue avant celle-ci (suppression du compte soignant, #1200)
const sql = read(`supabase/migrations/${MIGRATION}`);
const suite = read('tests/security/notifications-classement-b9.test.sql');
const banc = read('tests/postgres/notifications-classement-b9.pg17.mjs');
const workflow = read('.github/workflows/validate-pr.yml');
const schema = read('supabase/schema/public.sql');

const NOTIF_LIVE = 'bc337810f500768fed6748fac74265e8';
const TOP_LIVE = '1565a9c0a7908e833f8bdae9f96f852e';
const SIGNATURE_NOTIF = 'public.fn_creer_notification(uuid, text, text, text, text, text, text, uuid)';

/** Corps (texte entre délimiteurs, comme pg_proc.prosrc) de la définition de `nom` dans `texte` (migration ou dump). */
function corps(texte, nom) {
  let i = texte.indexOf(`FUNCTION public.${nom}(`);
  if (i < 0) i = texte.indexOf(`CREATE OR REPLACE FUNCTION "public"."${nom}"(`);
  assert.ok(i >= 0, `${nom} : définition absente`);
  const tail = texte.slice(i);
  const ouverture = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/.exec(tail);
  const debut = ouverture.index + ouverture[0].length;
  return tail.slice(debut, tail.indexOf(ouverture[1], debut));
}

/** Empreinte attendue d'une fonction dans la post-condition de la migration. */
const empreintePost = signature => new RegExp(`\\('public\\.${signature.replace(/[()]/g, '\\$&')}', '([0-9a-f]{32})', (?:true|false)\\)`)
  .exec(sql.slice(sql.indexOf('$b9_notifications_apres$')))?.[1];

test('migration : horodatage, transaction possédée par l’appelant, délimiteurs nommés', () => {
  const versions = readdirSync(join(RACINE, 'supabase/migrations')).filter(f => f.endsWith('.sql')).map(f => f.slice(0, 14)).sort();
  assert.match(MIGRATION, /^\d{14}_[a-z0-9_]+\.sql$/);
  assert.ok(versions.includes(PRECEDENTE));
  assert.ok(versions.indexOf(MIGRATION.slice(0, 14)) > versions.indexOf(PRECEDENTE), 'version postérieure à la précédente');
  assert.equal(new Set(versions).size, versions.length, 'version unique');
  assert.doesNotMatch(sql, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im);
  assert.doesNotMatch(sql, /AS \$\$/, 'délimiteurs nommés seulement');
  assert.ok(sql.indexOf('$b9_notifications_avant$') < sql.indexOf('REVOKE ALL ON FUNCTION public.fn_creer_notification'), 'préflight avant tout DDL');
  assert.ok(sql.lastIndexOf('$b9_notifications_apres$') > sql.lastIndexOf('INSERT INTO private.security_definer_inventory'), 'post-condition en dernier');
  assert.match(sql, /go écrit de Gabrielle du 24\/11\/2026/);
});

test('fn_creer_notification : EXECUTE retiré, corps LIVE inchangé, appelants serveur seulement', () => {
  for (const role of ['PUBLIC', 'anon', 'authenticated']) {
    assert.ok(sql.includes(`REVOKE ALL ON FUNCTION ${SIGNATURE_NOTIF} FROM ${role};`), `REVOKE ${role}`);
  }
  assert.ok(sql.includes(`GRANT EXECUTE ON FUNCTION ${SIGNATURE_NOTIF} TO service_role;`));
  assert.doesNotMatch(sql, /CREATE (OR REPLACE )?FUNCTION public\.fn_creer_notification\(/, 'aucune redéfinition');
  assert.ok(sql.includes(`'public.fn_creer_notification(uuid,text,text,text,text,text,text,uuid)', '${NOTIF_LIVE}', 'search_path=public'`));
  // Corps du dump : AVANT (re-baseline #1204) et APRÈS sont le même corps ; seul le GRANT authenticated change.
  assert.equal(md5(corps(schema, 'fn_creer_notification')), NOTIF_LIVE);
  // Le préflight refuse tout appelant qui s'exécuterait sous un rôle utilisateur.
  assert.ok(sql.includes("B9_NOTIFICATIONS_APPELANT_UTILISATEUR"));
  assert.match(sql, /p\.prorettype = 'trigger'::pg_catalog\.regtype/);
  assert.ok(suite.includes("RAISE EXCEPTION 'B9_NOTIFICATIONS A0 : appelant exécuté sous un rôle utilisateur"));
});

test('aucun appel client de fn_creer_notification (web, natif, edge)', () => {
  const fichiers = [];
  const parcourir = dossier => {
    for (const nom of readdirSync(join(RACINE, dossier))) {
      const chemin = join(dossier, nom);
      if (nom === 'node_modules' || nom.startsWith('.')) continue;
      if (statSync(join(RACINE, chemin)).isDirectory()) parcourir(chemin);
      else if (/\.(tsx?|jsx?|mjs|swift)$/.test(nom)) fichiers.push(chemin);
    }
  };
  for (const dossier of ['src', 'supabase/functions', 'ios-native/Packages']) parcourir(dossier);
  const appels = fichiers.filter(f => /\.rpc\(\s*['"]fn_creer_notification['"]|rpc\(\s*"fn_creer_notification"|"fn_creer_notification"\s*,/.test(read(f)));
  assert.deepEqual(appels, [], 'appel client de fn_creer_notification');
  assert.ok(read('src/pages/DetailMission.tsx').includes("supabase.rpc('fn_alerter_pool_urgence', { p_mission_id: missionId })"));
  assert.ok(read('src/pages/admin/AdminMandatsFacturation.tsx').includes("supabase.rpc('fn_admin_relancer_mandat_facturation', { p_soignant_id: s.id })"));
  const panneau = read('src/components/PanneauContestation.tsx');
  assert.doesNotMatch(panneau, /p_type:\s*'CONTESTATION_PRESENCE'/, 'contestation : notification laissée au trigger');
  // Numérotation conservée : des tests Swift relisent ce fichier par ligne (PresencesEtabRulesTests l.108 et l.365).
  const lignes = panneau.split('\n');
  assert.equal(lignes[108 - 1].trim(), 'const peutContester = dansFenetre && !litige;');
  assert.match(lignes[365 - 1], /Contester cette présence/);
  assert.ok(schema.includes('CREATE OR REPLACE TRIGGER "trg_notifier_creation_litige" AFTER INSERT ON "public"."litiges"'));
});

test('RPC de remplacement : gardes, texte serveur, droits explicites, empreintes', () => {
  const alerte = corps(sql, 'fn_alerter_pool_urgence');
  assert.ok(alerte.includes("OR NOT (public.est_admin() OR COALESCE(v_mission.etablissement_id = public.mon_etablissement_id(), false))"),
    'garde NULL-safe de fn_soignants_urgence');
  assert.ok(alerte.includes("IF v_mission.statut IS DISTINCT FROM 'OUVERTE' OR v_mission.est_urgente IS NOT TRUE THEN"));
  assert.ok(alerte.includes('FROM public.fn_soignants_urgence(p_mission_id) u'), 'mêmes destinataires que la liste de l’établissement');
  // Porte exigée de tout émetteur de diffusion de mission (tests/security/revue-store-missions-isolees.test.sql, A1).
  assert.ok(alerte.includes('WHERE private.fn_comptes_meme_cohorte_test(u.soignant_id, v_mission.etablissement_id)'), 'prédicat de cohorte canonique');
  assert.match(alerte, /n\.type = 'MISSION_URGENTE'\s+AND n\.id_ressource = p_mission_id/, 'aucun doublon');
  // Contrôle « déjà notifié » atomique face à deux alertes simultanées (revue B8) : verrou avant toute lecture.
  assert.ok(alerte.indexOf("pg_advisory_xact_lock(\n    pg_catalog.hashtextextended('fn_alerter_pool_urgence:' || p_mission_id::text, 0))") > 0
    && alerte.indexOf('pg_advisory_xact_lock') < alerte.indexOf('FROM public.notifications n'), 'verrou par mission avant le contrôle de doublon');
  assert.ok(sql.includes("pg_catalog.to_regprocedure('private.fn_comptes_meme_cohorte_test(uuid,uuid)') IS NULL"), 'préflight : prédicat de cohorte');
  assert.ok(alerte.includes("'/soignant/missions/' || p_mission_id::text"));
  const relance = corps(sql, 'fn_admin_relancer_mandat_facturation');
  assert.match(relance, /IF NOT public\.est_admin\(\) THEN\s+RAISE EXCEPTION 'Accès réservé aux administrateurs' USING ERRCODE = '42501';/);
  assert.ok(relance.includes("'/soignant/mandat-facturation', NULL, NULL"));
  // Texte repris mot pour mot de l'appel web retiré (aucun nouveau wording).
  assert.ok(relance.includes("'Votre mandat de facturation attend votre signature. Il permet la génération de vos factures d''honoraires ; pour une mission explicitement éligible au paiement accéléré, il fait partie des prérequis.'"));
  for (const [nom, signature] of [['fn_alerter_pool_urgence', 'fn_alerter_pool_urgence(uuid)'],
    ['fn_admin_relancer_mandat_facturation', 'fn_admin_relancer_mandat_facturation(uuid)'], ['fn_top_soignants', 'fn_top_soignants(text,integer)']]) {
    const args = nom === 'fn_top_soignants' ? '(text, integer)' : '(uuid)';
    for (const ligne of [`REVOKE ALL ON FUNCTION public.${nom}${args} FROM PUBLIC;`, `REVOKE ALL ON FUNCTION public.${nom}${args} FROM anon;`,
      `GRANT EXECUTE ON FUNCTION public.${nom}${args} TO authenticated;`, `GRANT EXECUTE ON FUNCTION public.${nom}${args} TO service_role;`]) {
      assert.ok(sql.includes(ligne), ligne);
    }
    const empreinte = md5(corps(sql, nom));
    assert.equal(empreintePost(signature), empreinte, `${nom} : post-condition sur l'empreinte du corps installé`);
    assert.ok(suite.includes(`('public.${signature}', '${empreinte}', true)`), `${nom} : même empreinte dans la suite`);
  }
  assert.ok(banc.includes(`apres: '${md5(corps(sql, 'fn_top_soignants'))}'`), 'banc : empreinte APRÈS du classement');
});

test('classement : réservé, cohorte de l’appelant, pseudonymisé, sans identifiant, borne conservée', () => {
  assert.equal(md5(corps(schema, 'fn_top_soignants')) === TOP_LIVE || md5(corps(schema, 'fn_top_soignants')) === md5(corps(sql, 'fn_top_soignants')), true,
    'dump : corps LIVE d’avant ou corps installé');
  assert.ok(sql.includes(`'public.fn_top_soignants(text,integer)', '${TOP_LIVE}', 'search_path=public'`));
  assert.ok(sql.includes('DROP FUNCTION public.fn_top_soignants(text, integer);'));
  const top = corps(sql, 'fn_top_soignants');
  assert.ok(top.includes('v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);') && top.includes('LIMIT v_limit;'));
  assert.match(top, /IF public\.est_admin\(\) THEN\s+v_cohorte_test := false;/);
  assert.match(top, /WHERE s\.id = auth\.uid\(\)\s+AND s\.supprime_le IS NULL;/);
  assert.match(top, /IF v_cohorte_test IS NULL THEN\s+RETURN;/);
  assert.ok(top.includes('AND s.est_compte_test = v_cohorte_test'));
  assert.ok(top.includes("NULLIF(upper(left(btrim(s.nom), 1)), '') || '.'"), 'initiale du nom');
  const colonnes = top.slice(top.indexOf('RETURN QUERY'), top.indexOf('FROM public.soignants s\n  WHERE s.supprime_le IS NULL'));
  assert.ok(colonnes.includes('s.prenom,'), 'liste des colonnes du classement');
  assert.doesNotMatch(colonnes, /\bs\.id\b|nb_evaluations|\bs\.nom,/, 'ni identifiant, ni nom complet, ni nombre d’évaluations');
  assert.ok(sql.includes("'TABLE(prenom text, nom text, profession text, note_moyenne numeric, score_fiabilite integer, total_missions_terminees integer)'"));
  // La page n'affiche que ces colonnes (clé de liste : le rang).
  const page = read('src/pages/ClassementSoignants.tsx');
  assert.ok(page.includes('{s.prenom} {s.nom}') && page.includes('key={s.rang}') && !/s\.id\b/.test(page));
  // Lecteur unique : la page web ; aucun natif.
  assert.doesNotMatch(read('ios-native/rpc-contracts.json'), /fn_top_soignants/);
});

test('suite SQL, banc et câblage CI', () => {
  assert.match(suite, /^(--[^\n]*\n)+BEGIN;\n/);
  assert.match(suite, /\nROLLBACK;\n$/);
  assert.doesNotMatch(suite, /^\s*COMMIT\s*;/im);
  for (const garde of ["'B9_NOTIFICATIONS A1 : ", "'B9_NOTIFICATIONS A2 : ", "'B9_NOTIFICATIONS A3 : ", "'B9_NOTIFICATIONS B1 : ",
    "'B9_NOTIFICATIONS B2 : ", "'B9_NOTIFICATIONS B3 : ", "'B9_NOTIFICATIONS B4 : ", "'B9_NOTIFICATIONS B5 : ",
    "'B9_NOTIFICATIONS C1 : ", "'B9_NOTIFICATIONS C2 : ", "'B9_NOTIFICATIONS D1 : ", "'B9_NOTIFICATIONS D2 : "]) {
    assert.ok(suite.includes(garde), `suite : ${garde}`);
  }
  const run = workflow.split('name: Exécuter les migrations ajoutées et les régressions SQL sans persister')[1];
  assert.match(run, /^\s+tests\/security\/notifications-classement-b9\.test\.sql$/m, 'suite dans SQL_TESTS');
  assert.ok(workflow.includes("psql -X -v ON_ERROR_STOP=1 -c 'CREATE DATABASE notifications_b9_banc'"));
  assert.ok(workflow.includes('PGDATABASE=notifications_b9_banc node --test tests/postgres/notifications-classement-b9.pg17.mjs'));
  assert.ok(workflow.includes('node --test tests/node/notifications-classement-b9.node.mjs'));
  const epingle = /DUMP_AVANT_B9_NOTIFICATIONS = Object\.freeze\(\{\s+commit: '([0-9a-f]{40})'/.exec(read('tests/postgres/schema-avant-migration.mjs'))?.[1];
  const recuperation = workflow.indexOf(`git fetch --no-tags --depth=1 origin ${epingle}`);
  assert.ok(epingle && recuperation > 0 && recuperation < workflow.indexOf('PGDATABASE=notifications_b9_banc'), 'commit épinglé récupéré avant le banc');
  assert.ok(banc.includes('racineAvant(DUMP_AVANT_B9_NOTIFICATIONS)'));
  assert.ok(banc.includes(`export const MIGRATION = 'supabase/migrations/${MIGRATION}';`));
  assert.ok(banc.includes("export const SUITE = 'tests/security/notifications-classement-b9.test.sql';"));
});

// Missions de revue des stores et cloisonnement des missions (20261126100000, 20261126100100), contrôle hors réseau.
// Ne remplace ni la suite SQL du staging (tests/security/revue-store-missions-isolees.test.sql, ROLLBACK) ni le
// banc PostgreSQL 17 / PGlite (tests/postgres/revue-store-missions.pg17.mjs) ; verrouille ce qu'ils ne voient pas :
//   * forme des migrations (horodatage, aucun BEGIN/COMMIT, délimiteurs nommés, préflight et post-condition) ;
//   * empreinte de chaque corps installé = celle que vérifient la post-condition et la suite ; ligne par ligne,
//     les règles posées (éligibilité, réponse, pool, alertes, relance, favoris, posts, nettoyage, suppression) ;
//   * désignation par tables privées, jamais d'identifiant ni d'e-mail dans un corps de fonction ; les deux e-mails
//     publics (docs/STORE_METADATA_FR.md) n'apparaissent que dans leur instruction de désignation ;
//   * visibilité : politique RESTRICTIVE, source REVUE_STORE protégée, droits EXECUTE ;
//   * crons gardés (pg_cron) et alignés sur la posture de l'environnement, retrait distinct de la garantie ;
//   * étages src/ et supabase/functions/ : aucun code applicatif ne pose REVUE_STORE ; les envois du navigateur
//     et des fonctions edge passent par une porte (pool d'urgence, éligibilité, comptes de test écartés) ;
//   * câblage CI : suite dans SQL_TESTS (avant la dernière), banc PG17, ce contrôle.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const RACINE = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(join(RACINE, path), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const M1 = '20261126100000_cloisonner_missions_cohorte_et_revue.sql';
const M2 = '20261126100100_missions_revue_store.sql';
const DERNIERE_VERSION_DISTANTE = '20261125130000'; // list_migrations de la production, 26/11/2026
const m1 = read(`supabase/migrations/${M1}`);
const m2 = read(`supabase/migrations/${M2}`);
const suite = read('tests/security/revue-store-missions-isolees.test.sql');
const banc = read('tests/postgres/revue-store-missions.pg17.mjs');
const workflow = read('.github/workflows/validate-pr.yml');

/** Corps (texte entre délimiteurs, comme pg_proc.prosrc) de chaque CREATE FUNCTION d'un script. */
function corps(sql) {
  const resultat = new Map();
  const re = /CREATE OR REPLACE FUNCTION ([a-z_]+\.[a-z0-9_]+)\([^]*?\bAS (\$[a-z_]+\$)/g;
  let m;
  while ((m = re.exec(sql))) {
    const debut = m.index + m[0].length;
    const fin = sql.indexOf(m[2], debut);
    assert.ok(fin > debut, `${m[1]} : fin de corps introuvable`);
    resultat.set(m[1], sql.slice(debut, fin));
    re.lastIndex = fin + m[2].length;
  }
  return resultat;
}
const corpsM1 = corps(m1);
const corpsM2 = corps(m2);

// Corps LIVE relus en lecture seule le 26/11/2026 (préflight) et corps installés (post-condition, suite).
const REDEFINITIONS = {
  'public.fn_soignant_eligible_mission': [M1, 'f10aeb9ced376cae6ef5a4a863a2cf6b', '6db2aebbc7342bb721108b66688b62bc'],
  'public.fn_resoudre_contrat_mission': [M1, 'e39388880b3e026e8b81b0d94d0de777', '91bf0908b53aaca7b5b4ea2cefaf4110'],
  'public.fn_pool_urgence_etablissement': [M1, '178dbb066ceb8720c38c30ab0fb74f7d', 'a4308cb167e6c0d895efda615c5da297'],
  'private.fn_soignant_visible_pool_etablissement': [M1, '4eb5e4ba20268e667e33c0c57a209f77', 'e2d9b4f46afb52b8278c0f71018b2539'],
  'public.fn_notifier_favoris_expirants': [M1, 'd44ae13e1e450ab85942c1863d107b7e', '8d3fa4597fb5835e8658bc4f31a3730c'],
  'public.fn_relancer_missions_sans_candidat': [M1, '49ae7d9e38110b4009e70af2d3a77c9f', '6d9af12f3446ccdabe4f840d93debfc7'],
  'private.fn_resultats_filtre_missions': [M1, '0e83167df94ef8d1d64019af1f4fe6ae', 'bf44aa1996cebc52ea272622000876c5'],
  'public.fn_mes_favoris_etablissements': [M1, '26c080a4e6e197018a5b27195981473a', '100f3988e20a0446673267ce804bb3b0'],
  'public.fn_admin_generer_posts': [M1, 'fd4a9e677fa1cdae1c0a75a061b789c4', 'f822983bb47bd93f1d984cdcb41a4b15'],
  'public.fn_cleanup_missions_test': [M2, '5a25967b3550051aedbd5cd02dec44e6', 'ee0c90c2fa777643b8261956ef7e3d6f'],
  'public.fn_supprimer_mon_compte_etablissement': [M2, 'a43978aee09ef1ae4a157dbee9911b2f', 'a5dd6e6858e7ad641f4bd353753f3223'],
};

test('migrations : horodatage, transaction possédée par l’appelant, délimiteurs nommés', () => {
  const versions = readdirSync(join(RACINE, 'supabase/migrations')).filter(f => f.endsWith('.sql')).sort();
  for (const f of [M1, M2]) {
    assert.match(f, /^\d{14}_[a-z0-9_]+\.sql$/);
    assert.ok(f.slice(0, 14) > DERNIERE_VERSION_DISTANTE, `${f} doit suivre la dernière version distante`);
  }
  assert.deepEqual(versions.slice(-2), [M1, M2], 'les deux migrations ferment la liste, dans cet ordre');
  for (const [nom, sql] of [[M1, m1], [M2, m2]]) {
    assert.doesNotMatch(sql, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im, `${nom} : aucun BEGIN/COMMIT interne`);
    assert.doesNotMatch(sql, /\$\$/, `${nom} : délimiteurs de dollar nommés seulement`);
    assert.match(sql, /SET LOCAL lock_timeout = '5s';/);
    assert.match(sql, /B9 \(RLS \+ SECURITY DEFINER\) : go écrits de Gabrielle du 24\/11\/2026 et du 26\/11\/2026\./);
  }
  assert.doesNotMatch(m1 + m2, /\b(DROP\s+(TABLE|FUNCTION|POLICY)|TRUNCATE|DROP\s+COLUMN)\b/i, 'aucune suppression d’objet ni de colonne');
});

test('redéfinitions : préflight sur les corps LIVE, post-condition et suite sur les nouveaux corps', () => {
  for (const [nom, [fichier, live, nouveau]] of Object.entries(REDEFINITIONS)) {
    const sql = fichier === M1 ? m1 : m2;
    const installe = (fichier === M1 ? corpsM1 : corpsM2).get(nom);
    assert.ok(installe, `${nom} redéfinie dans ${fichier}`);
    assert.equal(md5(installe), nouveau, `${nom} : empreinte du corps installé`);
    assert.ok(sql.includes(`'${live}'`), `${nom} : préflight sur l’empreinte LIVE`);
    assert.ok(sql.includes(`'${nouveau}'`), `${nom} : post-condition sur le nouveau corps`);
    assert.ok(suite.includes(`'${nouveau}'`), `${nom} : la suite vérifie le corps installé`);
  }
  const ligne = (nom, motif) => assert.ok((corpsM1.get(nom) ?? corpsM2.get(nom)).includes(motif), `${nom} : ${motif}`);
  // Éligibilité : jamais une mission de revue, cohorte par le seul prédicat de la RLS.
  ligne('public.fn_soignant_eligible_mission', "IF v_mission.mission_source IS NOT DISTINCT FROM 'REVUE_STORE' THEN\n    RETURN false;\n  END IF;");
  ligne('public.fn_soignant_eligible_mission', 'IF NOT private.fn_comptes_meme_cohorte_test(p_soignant_id, v_mission.etablissement_id) THEN');
  assert.doesNotMatch(corpsM1.get('public.fn_soignant_eligible_mission'), /est_compte_test/);
  // Réponse : soignant de revue désigné seulement.
  ligne('public.fn_resoudre_contrat_mission', "IF v_mission.mission_source IS NOT DISTINCT FROM 'REVUE_STORE'\n     AND NOT private.fn_est_soignant_revue_store(p_soignant_id) THEN");
  // Pool d'urgence et son jumeau : même cohorte, vide pour un établissement de revue.
  ligne('public.fn_pool_urgence_etablissement', 'AND private.fn_soignant_contactable_par_etablissement(s.id, p_etablissement_id)');
  ligne('private.fn_soignant_visible_pool_etablissement', 'AND private.fn_soignant_contactable_par_etablissement(s.id, e.id)');
  ligne('public.fn_notifier_favoris_expirants', 'AND private.fn_comptes_meme_cohorte_test(ms.soignant_id, m.etablissement_id)');
  ligne('public.fn_notifier_favoris_expirants', "AND m.mission_source IS DISTINCT FROM 'REVUE_STORE'");
  ligne('public.fn_relancer_missions_sans_candidat', "AND m.mission_source IS DISTINCT FROM 'REVUE_STORE'");
  ligne('private.fn_resultats_filtre_missions', "AND m.mission_source IS DISTINCT FROM 'REVUE_STORE'");
  ligne('public.fn_mes_favoris_etablissements', 'AND private.fn_soignant_voit_mission(v_uid, m.etablissement_id, m.mission_source)');
  ligne('public.fn_admin_generer_posts', 'AND NOT private.fn_mission_lie_compte_test(m.id)');
  ligne('public.fn_admin_generer_posts', 'AND NOT private.fn_mission_lie_compte_test(m3.id)');
  ligne('public.fn_cleanup_missions_test', "AND NOT (m.mission_source IS NOT DISTINCT FROM 'REVUE_STORE'\n             AND private.fn_est_etablissement_revue_store(m.etablissement_id));");
  const suppression = corpsM2.get('public.fn_supprimer_mon_compte_etablissement');
  assert.ok(suppression.includes("AND NOT (statut = 'OUVERTE' AND mission_source IS NOT DISTINCT FROM 'REVUE_STORE');"));
  assert.ok(suppression.indexOf('PERFORM private.fn_liberer_revue_store_etablissement(v_etab_id);') > 0
    && suppression.indexOf('PERFORM private.fn_liberer_revue_store_etablissement(v_etab_id);') < suppression.indexOf('supprime_le = NOW()'),
    'missions de revue retirées et désignation levée avant l’anonymisation');
  // Inventaire SECURITY DEFINER réaligné.
  assert.match(m1, /UPDATE private\.security_definer_inventory i\s+SET definition_md5 = pg_catalog\.md5\(p\.prosrc\)/);
  assert.match(m2, /UPDATE private\.security_definer_inventory i\s+SET definition_md5 = pg_catalog\.md5\(p\.prosrc\)/);
});

test('désignation, visibilité et droits : tables privées, comptes de test seulement, RLS RESTRICTIVE', () => {
  for (const [nom, texte] of [...corpsM1, ...corpsM2]) {
    assert.doesNotMatch(texte, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, `${nom} : aucun identifiant en dur`);
    // (le suffixe d'anonymisation '@supprime.jolene.app' du corps LIVE de suppression n'est pas une adresse)
    assert.doesNotMatch(texte, /[A-Za-z0-9._%+-]@[A-Za-z0-9-]+\./, `${nom} : aucun e-mail en dur`);
  }
  const doc = read('docs/STORE_METADATA_FR.md');
  for (const email of ['etab@jolene.app', 'marie.lefevre@jolene-demo.dev']) {
    assert.ok(doc.includes(email), `${email} : déjà public dans docs/STORE_METADATA_FR.md`);
    assert.equal(m2.split(email).length - 1, 1, `${email} : une seule occurrence, dans sa désignation`);
    assert.ok(!m1.includes(email) && !suite.includes(email), `${email} : absent de la migration de règles et de la suite`);
  }
  assert.match(m2, /JOIN auth\.users u ON u\.id = e\.id\s+WHERE pg_catalog\.lower\(u\.email\) = 'etab@jolene\.app'\s+AND e\.supprime_le IS NULL\s+ON CONFLICT \(etablissement_id\) DO NOTHING;/);
  assert.match(m2, /JOIN auth\.users u ON u\.id = s\.id\s+WHERE pg_catalog\.lower\(u\.email\) = 'marie\.lefevre@jolene-demo\.dev'\s+AND s\.supprime_le IS NULL\s+ON CONFLICT \(soignant_id\) DO NOTHING;/);
  for (const table of ['etablissements_revue_store', 'soignants_revue_store']) {
    assert.match(m1, new RegExp(`REVOKE ALL ON TABLE private\\.${table} FROM PUBLIC, anon, authenticated, service_role;`));
  }
  assert.ok(corpsM1.get('private.fn_verifier_etablissement_revue_store').includes("HINT = 'REVUE_STORE_ETABLISSEMENT_REEL'"));
  assert.ok(corpsM1.get('private.fn_verifier_soignant_revue_store').includes("HINT = 'REVUE_STORE_SOIGNANT_REEL'"));
  const declencheur = corpsM1.get('private.fn_trg_verifier_designation_revue_store');
  assert.ok(declencheur.includes('PERFORM private.fn_verifier_etablissement_revue_store(NEW.etablissement_id);'));
  assert.ok(declencheur.includes('PERFORM private.fn_verifier_soignant_revue_store(NEW.soignant_id);'));
  for (const helper of ['fn_est_etablissement_revue_store', 'fn_est_soignant_revue_store']) {
    assert.match(corpsM1.get(`private.${helper}`), /est_compte_test IS TRUE/, `${helper} : compte de test seulement`);
    assert.match(corpsM1.get(`private.${helper}`), /supprime_le IS NULL/, `${helper} : compte non supprimé`);
  }
  // Un seul prédicat lisible par authenticated (RLS) ; il ne rend qu'un booléen.
  assert.equal((m1 + m2).match(/^GRANT\b.*$/gm)?.join('\n'),
    'GRANT EXECUTE ON FUNCTION private.fn_est_soignant_revue_store(uuid) TO authenticated, service_role;');
  for (const f of ['fn_est_etablissement_revue_store(uuid)', 'fn_soignant_voit_mission(uuid, uuid, text)',
    'fn_soignant_contactable_par_etablissement(uuid, uuid)', 'fn_trg_proteger_mission_source_revue_store()']) {
    assert.ok(m1.includes(`REVOKE ALL ON FUNCTION private.${f} FROM PUBLIC, anon, authenticated, service_role;`), `${f} : EXECUTE retiré`);
  }
  for (const f of ['fn_garantir_missions_revue_store()', 'fn_retirer_missions_revue_store(uuid[], text)',
    'fn_retirer_missions_revue_store_non_conformes()', 'fn_liberer_revue_store_etablissement(uuid)']) {
    assert.ok(m2.includes(`REVOKE ALL ON FUNCTION private.${f} FROM PUBLIC, anon, authenticated, service_role;`), `${f} : EXECUTE retiré`);
  }
  assert.match(m1, /CREATE POLICY missions_revue_store_soignant_designe ON public\.missions\s+AS RESTRICTIVE\s+FOR SELECT\s+TO authenticated\s+USING \(\s+mission_source IS DISTINCT FROM 'REVUE_STORE'\s+OR NOT \(SELECT public\.est_soignant\(\) AS est_soignant\)\s+OR \(SELECT private\.fn_est_soignant_revue_store\(\(SELECT auth\.uid\(\) AS uid\)\)\)\s+\);/);
  assert.match(corpsM1.get('private.fn_soignant_voit_mission'), /private\.fn_comptes_meme_cohorte_test\(p_soignant_id, p_etablissement_id\)\s+AND \(p_mission_source IS DISTINCT FROM 'REVUE_STORE'\s+OR private\.fn_est_soignant_revue_store\(p_soignant_id\)\)/);
  assert.match(corpsM1.get('private.fn_soignant_contactable_par_etablissement'), /private\.fn_comptes_meme_cohorte_test\(p_soignant_id, p_etablissement_id\)\s+AND NOT private\.fn_est_etablissement_revue_store\(p_etablissement_id\)/);
  const protection = corpsM1.get('private.fn_trg_proteger_mission_source_revue_store');
  assert.match(protection, /auth\.uid\(\) IS NULL/, 'contexte système seulement');
  assert.match(protection, /HINT = 'REVUE_STORE_SOURCE_PROTEGEE'/);
  assert.match(m1, /CREATE TRIGGER trg_00_proteger_mission_source_revue_store\s+BEFORE INSERT OR UPDATE OF mission_source ON public\.missions/);
});

test('stock de revue : garantie, retrait distinct, crons gardés, premier remplissage', () => {
  const garantie = corpsM2.get('private.fn_garantir_missions_revue_store');
  for (const motif of [
    'v_hors_designation := private.fn_retirer_missions_revue_store_non_conformes();',
    "RAISE LOG 'REVUE_STORE : établissement désigné % supprimé ou absent, ignoré'",
    'PERFORM private.fn_verifier_etablissement_revue_store(v_etab.etablissement_id);',
    "'IDE'", "'CANDIDATURE', 'TOUS', 'TAUX_HORAIRE', false, 'REVUE_STORE'", 'GREATEST(v_modele.taux, v_minimum)',
    'c_jours constant integer[] := ARRAY[7, 14, 21, 10, 17, 12, 19, 8, 15, 9, 16, 11, 18, 13, 20];',
    "time '08:00', time '14:00'", "time '07:00', time '13:00'", "time '13:00', time '19:00'",
    'public.fn_valider_creneaux_mission_json(v_creneaux, true)',
    "pg_catalog.set_config('jolene.creer_mission_context', 'true', true)",
    "pg_catalog.set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)",
    'FOR v_reglage IN SELECT r.key, r.value FROM pg_catalog.jsonb_each_text(v_reglages)']) {
    assert.ok(garantie.includes(motif), `garantie : ${motif}`);
  }
  assert.doesNotMatch(garantie, /fn_blocage_publication_etab\(/, 'la garantie ne simule pas une publication vérifiée');
  const retrait = corpsM2.get('private.fn_retirer_missions_revue_store');
  assert.ok(retrait.includes("SET statut = 'EXPIREE'"));
  assert.ok(retrait.includes('INSERT INTO private.candidature_transition_context'));
  assert.ok(retrait.includes("AND c.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');"));
  assert.ok(corpsM2.get('private.fn_retirer_missions_revue_store_non_conformes').includes('AND NOT private.fn_est_etablissement_revue_store(m.etablissement_id);'));
  assert.doesNotMatch(corpsM2.get('private.fn_retirer_missions_revue_store_non_conformes'), /RAISE/, 'le retrait ne lève jamais');
  const cron = m2.slice(m2.indexOf('DO $revue_store_cron$'), m2.indexOf('$revue_store_cron$;'));
  assert.match(cron, /IF NOT EXISTS \(SELECT 1 FROM pg_catalog\.pg_extension WHERE extname = 'pg_cron'\) THEN\s+RETURN;/);
  assert.match(cron, /v_actif := EXISTS \(SELECT 1 FROM cron\.job j\s+WHERE j\.active AND j\.jobname NOT IN \('jolene_missions_revue_store_retrait',\s+'jolene_missions_revue_store_quotidien'\)\);/);
  assert.match(cron, /cron\.schedule\('jolene_missions_revue_store_retrait', '35 4 \* \* \*',\s+\$job\$SELECT private\.fn_retirer_missions_revue_store_non_conformes\(\)\$job\$\)/);
  assert.match(cron, /cron\.schedule\('jolene_missions_revue_store_quotidien', '40 4 \* \* \*',\s+\$job\$SELECT private\.fn_garantir_missions_revue_store\(\)\$job\$\)/);
  assert.equal(cron.split('cron.alter_job(job_id := v_jobid, active := v_actif)').length - 1, 2);
  const designation = m2.indexOf('INSERT INTO private.etablissements_revue_store');
  const remplissage = m2.indexOf('\nSELECT private.fn_garantir_missions_revue_store();');
  assert.ok(designation > m2.indexOf('$revue_store_cron$;') && remplissage > m2.indexOf('INSERT INTO private.soignants_revue_store'),
    'désignations puis premier remplissage, en fin de migration');
  assert.match(m1, /missions_mission_source_check\s+CHECK \(mission_source = ANY \(ARRAY\['SWIPE'::text, 'CANDIDATURE'::text, 'REBOOK'::text,\s+'PROPOSITION_DIRECTE'::text, 'REMPLACEMENT'::text, 'REPUBLICATION'::text, 'REVUE_STORE'::text\]\)\)/);
});

function fichiers(dossier) {
  return readdirSync(join(RACINE, dossier)).flatMap(nom => {
    const chemin = `${dossier}/${nom}`;
    return statSync(join(RACINE, chemin)).isDirectory() ? fichiers(chemin) : [chemin];
  });
}

test('étages src/ et supabase/functions/ : REVUE_STORE jamais posée, chaque envoi passe par une porte', () => {
  for (const chemin of [...fichiers('src'), ...fichiers('supabase/functions')].filter(f => /\.(ts|tsx|js|mjs)$/.test(f))) {
    assert.ok(!read(chemin).includes('REVUE_STORE'), `${chemin} : aucun code applicatif ne pose ni ne lit REVUE_STORE`);
  }
  for (const fonction of ['send-push', 'send-sms']) {
    const source = read(`supabase/functions/${fonction}/index.ts`);
    assert.match(source, /userClient\.rpc\('fn_pool_urgence_etablissement'/, `${fonction} : cible d’un établissement bornée au pool`);
  }
  const notifMatch = read('supabase/functions/notif-match/index.ts');
  assert.ok(notifMatch.indexOf('"fn_soignant_eligible_mission"') > 0
    && notifMatch.indexOf('"fn_soignant_eligible_mission"') < notifMatch.indexOf('.from("notifications")'), 'notif-match : éligibilité avant tout envoi');
  for (const fonction of ['digest-hebdo', 'relance-inactifs']) {
    const source = read(`supabase/functions/${fonction}/index.ts`);
    assert.match(source, /resolveOperationalTestAccount\(admin, s\.id\)/, `${fonction} : comptes de test écartés`);
  }
  const pool = read('src/pages/PoolUrgenceEtablissement.tsx');
  assert.match(pool, /supabase\.rpc\('fn_pool_urgence_etablissement'/);
  assert.match(pool, /supabase\.functions\.invoke\('send-push'/);
  const detail = read('src/pages/DetailMission.tsx');
  assert.ok(detail.indexOf("'fn_soignants_urgence'") > 0 && detail.indexOf("'fn_soignants_urgence'") < detail.indexOf("p_type: 'MISSION_URGENTE'"),
    'alerte pool d’une mission : destinataires lus par fn_soignants_urgence (éligibilité)');
  // La suite vérifie ces portes sur la base.
  assert.ok(suite.includes("('public.fn_soignants_urgence(uuid)', 'fn_soignant_eligible_mission(')"));
  assert.ok(suite.includes("('public.fn_pool_urgence_etablissement(uuid)', 'private.fn_soignant_contactable_par_etablissement(s.id, p_etablissement_id)')"));
});

test('suite SQL et câblage CI', () => {
  assert.match(suite, /^(--[^\n]*\n)+BEGIN;\n/);
  assert.match(suite, /\nROLLBACK;\n$/);
  assert.doesNotMatch(suite, /^\s*COMMIT\s*;/im);
  assert.match(suite, /EXISTS \(SELECT 1 FROM cron\.job WHERE active\)/, 'refus hors base isolée');
  for (const garde of [
    "RAISE EXCEPTION 'REVUE_STORE test-garde : % émet une diffusion de mission sans le prédicat de cohorte",
    "RAISE EXCEPTION 'REVUE_STORE test-garde : % lit des missions ouvertes sans filtre de visibilité",
    "EXECUTE 'SET LOCAL ROLE authenticated';",
    "RAISE EXCEPTION 'REVUE_STORE F1 : % lit % mission(s) de revue",
    "RAISE EXCEPTION 'REVUE_STORE G1 : suppression du compte de revue",
  ]) assert.ok(suite.includes(garde), `suite : ${garde}`);
  const run = workflow.split('name: Exécuter les migrations ajoutées et les régressions SQL sans persister')[1];
  assert.ok(run.includes('            tests/security/revue-store-missions-isolees.test.sql\n            tests/non-regression/sql/contestation-paiement-soignant.test.sql\n          )'),
    'suite dans SQL_TESTS, juste avant la dernière');
  assert.match(workflow, /createdb revue_store_banc|CREATE DATABASE revue_store_banc/);
  assert.ok(workflow.includes('PGDATABASE=revue_store_banc node --test tests/postgres/revue-store-missions.pg17.mjs'));
  assert.ok(workflow.includes('node --test tests/node/revue-store-missions.node.mjs'));
  assert.ok(banc.includes("export const SUITE = 'tests/security/revue-store-missions-isolees.test.sql';"));
  for (const f of [M1, M2]) assert.ok(banc.includes(`supabase/migrations/${f}`), `banc : ${f}`);
});

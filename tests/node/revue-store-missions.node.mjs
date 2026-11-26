// Missions de revue App Store et cloisonnement des envois (20261126100000, 20261126100100), contrôle hors réseau.
// Ne remplace ni la suite SQL du staging (tests/security/revue-store-missions-isolees.test.sql, ROLLBACK) ni le
// banc PostgreSQL 17 / PGlite (tests/postgres/revue-store-missions.pg17.mjs) ; verrouille ce qu'ils ne voient pas :
//   * forme des migrations (horodatage, aucun BEGIN/COMMIT, délimiteurs nommés, préflight et post-condition) ;
//   * empreinte de chaque corps installé = celle que vérifient la post-condition et la suite ;
//   * aucun identifiant ni e-mail dans un corps de fonction : la désignation passe par la table privée, l'e-mail de
//     rôle n'apparaît que dans l'instruction de désignation ;
//   * EXECUTE retiré, cron gardé (pg_cron) et aligné sur la posture de l'environnement, premier remplissage ;
//   * étages src/ et supabase/functions/ de l'audit : les envois du navigateur et des fonctions edge passent par une
//     porte qui lit le prédicat de cohorte (pool d'urgence, éligibilité, comptes de test écartés) ;
//   * câblage CI : suite dans SQL_TESTS (avant la dernière), banc PG17, ce contrôle.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const M1 = '20261126100000_isoler_envois_missions_cohorte_test.sql';
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

const NOUVEAUX = {
  'public.fn_soignant_eligible_mission': 'f15ef90fcd8a867ecfb375bb37c8d739',
  'public.fn_pool_urgence_etablissement': '057e327862ee12a7c7cbaacaff8b3ab8',
  'public.fn_notifier_favoris_expirants': 'ad2f2d6c4887de12458807a1b4213bfb',
  'public.fn_cleanup_missions_test': '65b1b5874bd9eb6ce2a6715554cf51ab',
};
const LIVE = {
  'public.fn_soignant_eligible_mission': 'f10aeb9ced376cae6ef5a4a863a2cf6b',
  'public.fn_pool_urgence_etablissement': '178dbb066ceb8720c38c30ab0fb74f7d',
  'public.fn_notifier_favoris_expirants': 'd44ae13e1e450ab85942c1863d107b7e',
  'public.fn_cleanup_missions_test': '5a25967b3550051aedbd5cd02dec44e6',
};

test('migrations : horodatage, transaction possédée par l’appelant, délimiteurs nommés', () => {
  const versions = readdirSync(new URL('../../supabase/migrations/', import.meta.url)).filter(f => f.endsWith('.sql')).sort();
  for (const f of [M1, M2]) {
    assert.match(f, /^\d{14}_[a-z0-9_]+\.sql$/);
    assert.ok(f.slice(0, 14) > DERNIERE_VERSION_DISTANTE, `${f} doit suivre la dernière version distante`);
  }
  assert.deepEqual(versions.slice(-2), [M1, M2], 'les deux migrations ferment la liste, dans cet ordre');
  for (const [nom, sql] of [[M1, m1], [M2, m2]]) {
    assert.doesNotMatch(sql, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im, `${nom} : aucun BEGIN/COMMIT interne`);
    assert.doesNotMatch(sql, /\$\$/, `${nom} : délimiteurs de dollar nommés seulement`);
    assert.match(sql, /SET LOCAL lock_timeout = '5s';/);
    assert.match(sql, /B9 \(SECURITY DEFINER\) : go écrit de Gabrielle du 24\/11\/2026/);
  }
});

test('redéfinitions : préflight sur les corps LIVE, post-condition et suite sur les nouveaux corps', () => {
  for (const [nom, live] of Object.entries(LIVE)) {
    const sql = nom === 'public.fn_cleanup_missions_test' ? m2 : m1;
    const installe = nom === 'public.fn_cleanup_missions_test' ? corpsM2.get(nom) : corpsM1.get(nom);
    assert.ok(installe, `${nom} redéfinie`);
    assert.equal(md5(installe), NOUVEAUX[nom], `${nom} : empreinte du corps installé`);
    assert.ok(sql.includes(`'${live}'`), `${nom} : préflight sur l’empreinte LIVE`);
    assert.ok(sql.includes(`'${NOUVEAUX[nom]}'`), `${nom} : post-condition sur le nouveau corps`);
    assert.ok(suite.includes(`'${NOUVEAUX[nom]}'`), `${nom} : la suite vérifie le corps installé`);
  }
  // Une seule règle de cohorte : le prédicat de la RLS, plus de comparaison locale.
  const eligibilite = corpsM1.get('public.fn_soignant_eligible_mission');
  assert.ok(eligibilite.includes('IF NOT private.fn_comptes_meme_cohorte_test(p_soignant_id, v_mission.etablissement_id) THEN'));
  assert.doesNotMatch(eligibilite, /est_compte_test/);
  assert.ok(corpsM1.get('public.fn_pool_urgence_etablissement').includes('AND private.fn_comptes_meme_cohorte_test(s.id, p_etablissement_id)'));
  assert.ok(corpsM1.get('public.fn_notifier_favoris_expirants').includes('AND private.fn_comptes_meme_cohorte_test(ms.soignant_id, m.etablissement_id)'));
  assert.ok(corpsM2.get('public.fn_cleanup_missions_test').includes("AND m.mission_source IS DISTINCT FROM 'REVUE_STORE';"));
  assert.match(m1, /UPDATE private\.security_definer_inventory i\s+SET definition_md5 = pg_catalog\.md5\(p\.prosrc\)/);
  assert.doesNotMatch(m1, /^\s*(GRANT|REVOKE)\b/m, 'CREATE OR REPLACE conserve les ACL : aucun GRANT ni REVOKE');
});

test('missions de revue : désignation paramétrée, verrou compte réel, droits, cron et premier remplissage', () => {
  for (const [nom, texte] of corpsM2) {
    assert.doesNotMatch(texte, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, `${nom} : aucun identifiant en dur`);
    assert.doesNotMatch(texte, /@/, `${nom} : aucun e-mail en dur`);
  }
  assert.equal((m2.match(/etab@jolene\.app/g) ?? []).length, 1, 'l’e-mail de rôle n’apparaît qu’une fois');
  assert.match(m2, /JOIN auth\.users u ON u\.id = e\.id\s+WHERE pg_catalog\.lower\(u\.email\) = 'etab@jolene\.app'\s+AND e\.supprime_le IS NULL\s+ON CONFLICT \(etablissement_id\) DO NOTHING;/);
  const garantie = corpsM2.get('private.fn_garantir_missions_revue_store');
  assert.ok(garantie.includes('PERFORM private.fn_verifier_etablissement_revue_store(v_etab.etablissement_id);'));
  assert.ok(corpsM2.get('private.fn_verifier_etablissement_revue_store').includes("HINT = 'REVUE_STORE_ETABLISSEMENT_REEL'"));
  assert.ok(corpsM2.get('private.fn_trg_verifier_designation_revue_store').includes('PERFORM private.fn_verifier_etablissement_revue_store(NEW.etablissement_id);'));
  for (const motif of ["'IDE'", "'CANDIDATURE', 'TOUS', 'TAUX_HORAIRE', false, 'REVUE_STORE'", 'GREATEST(v_modele.taux, v_minimum)',
    "c_jours constant integer[] := ARRAY[7, 14, 21, 10, 17, 12, 19, 8, 15, 9, 16, 11, 18, 13, 20];", 'public.fn_valider_creneaux_mission_json(v_creneaux, true)',
    "pg_catalog.set_config('jolene.creer_mission_context', 'true', true)", "pg_catalog.set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)",
    'FOR v_reglage IN SELECT r.key, r.value FROM pg_catalog.jsonb_each_text(v_reglages)']) {
    assert.ok(garantie.includes(motif), `garantie : ${motif}`);
  }
  assert.doesNotMatch(garantie, /fn_blocage_publication_etab\(/, 'la garantie ne simule pas une publication vérifiée');
  assert.match(m2, /REVOKE ALL ON FUNCTION private\.fn_garantir_missions_revue_store\(\) FROM PUBLIC, anon, authenticated, service_role;/);
  assert.match(m2, /REVOKE ALL ON TABLE private\.etablissements_revue_store FROM PUBLIC, anon, authenticated, service_role;/);
  assert.match(m2, /SELECT 'private\.fn_garantir_missions_revue_store\(\)', 'SERVICE_ONLY_REVOQUE'/);
  assert.doesNotMatch(m2, /^\s*GRANT\b/m);
  const cron = m2.slice(m2.indexOf('DO $revue_store_cron$'), m2.indexOf('$revue_store_cron$;'));
  assert.match(cron, /IF NOT EXISTS \(SELECT 1 FROM pg_catalog\.pg_extension WHERE extname = 'pg_cron'\) THEN\s+RETURN;/);
  assert.match(cron, /v_actif := EXISTS \(SELECT 1 FROM cron\.job j\s+WHERE j\.active AND j\.jobname IS DISTINCT FROM 'jolene_missions_revue_store_quotidien'\);/);
  assert.match(cron, /cron\.schedule\('jolene_missions_revue_store_quotidien', '40 4 \* \* \*',\s+\$job\$SELECT private\.fn_garantir_missions_revue_store\(\)\$job\$\)/);
  assert.match(cron, /cron\.alter_job\(job_id := v_jobid, active := v_actif\)/);
  const designation = m2.indexOf('INSERT INTO private.etablissements_revue_store');
  const remplissage = m2.indexOf('\nSELECT private.fn_garantir_missions_revue_store();');
  assert.ok(designation > m2.indexOf('$revue_store_cron$;') && remplissage > designation, 'désignation puis premier remplissage, en fin de migration');
  assert.match(m2, /missions_mission_source_check\s+CHECK \(mission_source = ANY \(ARRAY\['SWIPE'::text, 'CANDIDATURE'::text, 'REBOOK'::text,\s+'PROPOSITION_DIRECTE'::text, 'REMPLACEMENT'::text, 'REPUBLICATION'::text, 'REVUE_STORE'::text\]\)\)/);
});

test('étages src/ et supabase/functions/ : chaque envoi passe par une porte de cohorte', () => {
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
  // La suite vérifie ces deux portes sur la base.
  assert.ok(suite.includes("('public.fn_soignants_urgence(uuid)', 'fn_soignant_eligible_mission(')"));
  assert.ok(suite.includes("('public.fn_pool_urgence_etablissement(uuid)', 'private.fn_comptes_meme_cohorte_test(')"));
});

test('suite SQL et câblage CI', () => {
  assert.match(suite, /^(--[^\n]*\n)+BEGIN;\n/);
  assert.match(suite, /\nROLLBACK;\n$/);
  assert.doesNotMatch(suite, /^\s*COMMIT\s*;/im);
  assert.match(suite, /EXISTS \(SELECT 1 FROM cron\.job WHERE active\)/, 'refus hors base isolée');
  assert.match(suite, /RAISE EXCEPTION 'REVUE_STORE test-garde : % émet une diffusion de mission sans le prédicat de cohorte/);
  const run = workflow.split('name: Exécuter les migrations ajoutées et les régressions SQL sans persister')[1];
  assert.ok(run.includes('            tests/security/revue-store-missions-isolees.test.sql\n            tests/non-regression/sql/contestation-paiement-soignant.test.sql\n          )'),
    'suite dans SQL_TESTS, juste avant la dernière');
  assert.match(workflow, /createdb revue_store_banc|CREATE DATABASE revue_store_banc/);
  assert.ok(workflow.includes('PGDATABASE=revue_store_banc node --test tests/postgres/revue-store-missions.pg17.mjs'));
  assert.ok(workflow.includes('node --test tests/node/revue-store-missions.node.mjs'));
  assert.ok(banc.includes("export const SUITE = 'tests/security/revue-store-missions-isolees.test.sql';"));
  for (const f of [M1, M2]) assert.ok(banc.includes(`supabase/migrations/${f}`), `banc : ${f}`);
});

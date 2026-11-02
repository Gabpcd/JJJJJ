// B5b (lot 5, B9) — visibilité établissement par permission.
// Contrôle hors réseau de la migration, de sa fixture LIVE et de son banc PG17 :
// corps LIVE d'origine, empreintes avant/après, diff minimal, clés masquées,
// absence de DDL de droits et câblage CI. Ne remplace pas le banc PostgreSQL.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body).digest('hex');

const NOM = 'visibilite_etablissement_par_permission';
const migrations = readdirSync(new URL('../../supabase/migrations/', import.meta.url))
  .filter(name => name.endsWith(`_${NOM}.sql`));
const migrationPath = `supabase/migrations/${migrations[0]}`;
const migration = migrations.length === 1 ? read(migrationPath) : '';
const fixture = read('tests/security/fixtures/visibilite-etablissement-permission-live.sql');
const banc = read('tests/security/fixtures/visibilite-etablissement-permission-banc.sql');
const bancTest = read('tests/security/visibilite-etablissement-permission-isolated.test.sql');
const rejeuTest = read('tests/security/visibilite-etablissement-permission-rejeu.test.sql');
const schema = read('supabase/schema/public.sql');
const workflow = read('.github/workflows/validate-pr.yml');

// md5(prosrc) LIVE relus en production (lecture seule) le 02/11/2026.
const LIVE = {
  'fn_etat_pointage_mission(uuid)': '3fe46580ddb6d871b4331e41a31a9e05',
  'fn_stats_dashboard_etablissement()': '3b6e1d770f15c3d788236f2b57b77a9a',
  'fn_mon_etablissement_complet()': 'adec3cf8c4d9bc8c317500222ed2675d',
  'fn_a_permission_etablissement(text,uuid)': '1ee98c0e7094db4e98277b85ce71c6ec',
  'fn_role_etablissement_courant(uuid)': 'ceb4e333f4b7f69a3be422b9753b559a',
  'mon_etablissement_id()': 'dc3ef839d2920fb33cf6d7b320842c10',
  'fn_compte_auth_actif()': '8246c4c1f1b0a8053adb176a06c96766',
  'est_admin_valide()': '7954bb4e079865c63c4ba1096bd1fc76',
  'est_admin()': 'ef86d65809c3f76a1ac08eb737796fad',
};
const CIBLES = ['fn_etat_pointage_mission(uuid)', 'fn_stats_dashboard_etablissement()', 'fn_mon_etablissement_complet()'];
const nomDe = signature => signature.split('(')[0];

function sourceBody(sql, name) {
  const unquoted = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  const start = unquoted >= 0 ? unquoted : sql.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
  assert.ok(start >= 0, `${name}: définition explicite absente`);
  const tail = sql.slice(start);
  const opening = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/i.exec(tail);
  assert.ok(opening, `${name}: corps dollar-quoted absent`);
  const offset = opening.index + opening[0].length;
  const end = tail.indexOf(opening[1], offset);
  assert.ok(end >= 0, `${name}: fin du corps absente`);
  return tail.slice(offset, end);
}

function valeurs(bloc, colonnes) {
  // Lignes « (ordre, 'signature', 'md5'[, 'md5'], … ) » d'un bloc VALUES.
  return [...bloc.matchAll(/^\s*\((\d+), '([^']+)', '([0-9a-f]{32})'(?:, '([0-9a-f]{32})')?/gm)]
    .map(m => colonnes === 2
      ? { ordre: Number(m[1]), signature: m[2], ancien: m[3], nouveau: m[4] }
      : { ordre: Number(m[1]), signature: m[2], ancien: m[3] });
}
const bloc = tag => {
  const start = migration.indexOf(`DO $${tag}$`);
  assert.ok(start >= 0, `bloc ${tag} absent`);
  const end = migration.indexOf(`$${tag}$;`, start);
  assert.ok(end > start, `fin du bloc ${tag} absente`);
  return migration.slice(start, end);
};

function retraits(avant, apres) {
  // Lignes du corps LIVE absentes du nouveau corps (multiensemble).
  const restantes = new Map();
  for (const ligne of apres.split('\n')) restantes.set(ligne, (restantes.get(ligne) ?? 0) + 1);
  const retirees = [];
  for (const ligne of avant.split('\n')) {
    const n = restantes.get(ligne) ?? 0;
    if (n > 0) restantes.set(ligne, n - 1); else retirees.push(ligne);
  }
  return retirees;
}

test('une seule migration B5b, horodatée après la dernière version distante, sans transaction interne', () => {
  assert.equal(migrations.length, 1, migrations.join(', '));
  assert.match(migrations[0], /^\d{14}_visibilite_etablissement_par_permission\.sql$/);
  assert.ok(migrations[0].slice(0, 14) > '20261102150000');
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im);
  assert.doesNotMatch(migration, /\$\$/, 'dollar-quoting anonyme interdit');
  const tags = [...migration.matchAll(/\bAS (\$[a-z_]+\$)|DO (\$[a-z_]+\$)/g)].map(m => m[1] ?? m[2]);
  assert.deepEqual(tags, ['$preflight_b5b$', '$etat_pointage$', '$stats_dashboard$', '$etablissement_complet$', '$postflight_b5b$']);
  assert.equal(new Set(tags).size, tags.length);
});

test('aucun GRANT, REVOKE, DROP, ALTER, INSERT ni DELETE ; trois redéfinitions et une mise à jour d’inventaire', () => {
  let squelette = migration.replace(/--[^\n]*/g, '');
  for (const tag of ['etat_pointage', 'stats_dashboard', 'etablissement_complet']) {
    squelette = squelette.replace(new RegExp(`\\$${tag}\\$[\\s\\S]*?\\$${tag}\\$`), "'corps'");
  }
  assert.doesNotMatch(squelette, /\b(GRANT|REVOKE|DROP|ALTER|TRUNCATE|DELETE|INSERT)\b/i);
  assert.deepEqual([...squelette.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\(/g)].map(m => m[1]),
    CIBLES.map(nomDe));
  assert.deepEqual([...squelette.matchAll(/\bUPDATE\s+([\w.]+)/gi)].map(m => m[1]), ['private.security_definer_inventory']);
  assert.match(squelette, /SET definition_md5 = v_attendu\.nouveau_md5, recense_le = pg_catalog\.now\(\)/);
  assert.match(squelette, /AND i\.definition_md5 = v_attendu\.ancien_md5;/);
  assert.match(squelette, /NOTIFY pgrst, 'reload schema';\s*$/);
  // Les qualificatifs LIVE sont reconduits à l'identique.
  assert.match(migration, /public\.fn_etat_pointage_mission\(p_mission_id uuid\)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS \$etat_pointage\$/);
  assert.match(migration, /public\.fn_stats_dashboard_etablissement\(\)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS \$stats_dashboard\$/);
  assert.match(migration, /public\.fn_mon_etablissement_complet\(\)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'pg_catalog', 'public'\nAS \$etablissement_complet\$/);
});

test('préflight : corps LIVE des trois RPC et des trois gardes, inventaire et droits vérifiés', () => {
  const pre = valeurs(bloc('preflight_b5b'), 1);
  assert.deepEqual(pre.map(v => v.ordre), [1, 2, 3, 4, 5, 6]);
  for (const v of pre) assert.equal(v.ancien, LIVE[v.signature], v.signature);
  assert.deepEqual(pre.slice(0, 3).map(v => v.signature), CIBLES);
  const texte = bloc('preflight_b5b');
  for (const code of ['VISIBILITE_ETAB_PREFLIGHT_SOURCE_DRIFT', 'VISIBILITE_ETAB_PREFLIGHT_ACL_DRIFT', 'VISIBILITE_ETAB_PREFLIGHT_INVENTORY_DRIFT']) {
    assert.ok(texte.includes(`RAISE EXCEPTION '${code}: %'`), code);
  }
  assert.match(texte, /pg_catalog\.md5\(v_proc\.prosrc\) IS DISTINCT FROM v_attendu\.ancien_md5/);
  assert.match(texte, /v_proc\.proconfig IS DISTINCT FROM v_attendu\.config/);
  assert.match(texte, /has_function_privilege\('anon', v_proc\.oid, 'EXECUTE'\)/);
  assert.match(texte, /CREATE TEMP TABLE _visibilite_etab_acl_avant ON COMMIT DROP/);
  assert.ok(texte.indexOf('END LOOP;') < texte.indexOf('CREATE TEMP TABLE'), 'ACL capturées après les contrôles');
});

test('postflight : nouvelles empreintes = corps de la migration, ACL exactes et inventaire', () => {
  const post = valeurs(bloc('postflight_b5b'), 2);
  assert.deepEqual(post.map(v => v.signature), CIBLES);
  for (const v of post) {
    assert.equal(v.ancien, LIVE[v.signature], v.signature);
    assert.equal(v.nouveau, md5(sourceBody(migration, nomDe(v.signature))), v.signature);
    assert.notEqual(v.nouveau, v.ancien);
  }
  const texte = bloc('postflight_b5b');
  assert.match(texte, /v_proc\.proacl::text IS DISTINCT FROM \(\s*SELECT a\.acl FROM pg_temp\._visibilite_etab_acl_avant a WHERE a\.oid = v_proc\.oid\)/);
  assert.ok(texte.includes("RAISE EXCEPTION 'VISIBILITE_ETAB_POSTFLIGHT_DRIFT: %'"));
  assert.ok(texte.includes("RAISE EXCEPTION 'VISIBILITE_ETAB_INVENTORY_NOT_UPDATED: %'"));
});

test('fixture : corps LIVE exacts, propriétaire et ACL du dump, aucune donnée', () => {
  for (const [signature, attendu] of Object.entries(LIVE)) {
    const corps = sourceBody(fixture, nomDe(signature));
    assert.equal(md5(corps), attendu, signature);
    assert.notEqual(md5(`${corps} `), attendu, 'une dérive blanche change le verrou');
    const dansSchema = md5(sourceBody(schema, nomDe(signature)));
    if (CIBLES.includes(signature)) {
      // Avant déploiement : corps LIVE ; après re-baseline : corps de la migration.
      assert.ok([attendu, md5(sourceBody(migration, nomDe(signature)))].includes(dansSchema), signature);
    }
    if (dansSchema === attendu) assert.equal(corps, sourceBody(schema, nomDe(signature)));
  }
  assert.doesNotMatch(fixture, /^\s*(INSERT|UPDATE|DELETE)\b/im);
  for (const ligne of fixture.split('\n').filter(l => /^(REVOKE|GRANT|ALTER FUNCTION|COMMENT ON)/.test(l))) {
    assert.ok(schema.includes(`${ligne}\n`), `ligne absente du dump : ${ligne}`);
  }
});

test('diff minimal depuis le LIVE : seules les lignes prévues sont retirées', () => {
  const attendus = {
    'fn_etat_pointage_mission(uuid)': [
      '  IF NOT v_is_etab AND NOT v_is_soignant THEN',
      "    -- Visible uniquement par l'établissement (l'affiche au soignant à pointer).",
      "    'code_pointage_actif', CASE WHEN v_is_etab THEN v_mission.code_pointage_actif ELSE NULL END,",
    ],
    'fn_stats_dashboard_etablissement()': [
      "        'commissions_cumulees', COALESCE((SELECT SUM(montant_ht) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0),",
      "        'commissions_impayees', v_commissions_impayees,",
      "        'candidatures_recentes', COALESCE((",
      "        ), '[]'::JSONB),",
    ],
    'fn_mon_etablissement_complet()': [
      '      et.stripe_customer_id, et.stripe_account_id,',
      '      et.rib_s3_key, et.rib_ia_coherent, et.iban_last4, et.sms_actif,',
    ],
  };
  for (const signature of CIBLES) {
    const avant = sourceBody(fixture, nomDe(signature));
    const apres = sourceBody(migration, nomDe(signature));
    assert.deepEqual(retraits(avant, apres), attendus[signature], signature);
  }
});

test('règles de visibilité : permissions du serveur, clés conservées, rôles habilités inchangés', () => {
  const etat = sourceBody(migration, 'fn_etat_pointage_mission');
  assert.ok(etat.includes("v_peut_voir_code := public.fn_a_permission_etablissement('pointage', v_mission.etablissement_id) IS TRUE;"));
  assert.ok(etat.includes("'code_pointage_actif', CASE WHEN v_peut_voir_code THEN v_mission.code_pointage_actif ELSE NULL END,"));
  assert.ok(etat.includes('IF NOT COALESCE(v_is_etab, false) AND NOT COALESCE(v_is_soignant, false) THEN'));
  assert.ok(etat.includes("'est_etab', v_is_etab"), 'est_etab inchangé (null pour le soignant affecté)');

  const stats = sourceBody(migration, 'fn_stats_dashboard_etablissement');
  assert.ok(stats.includes("v_lecture_finances := public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS TRUE\n        OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS TRUE;"));
  assert.ok(stats.includes("v_lecture_candidatures := public.fn_a_permission_etablissement('lecture_candidatures', v_etab_id) IS TRUE;"));
  assert.ok(stats.includes("'nb_factures_impayees', v_nb_factures_impayees,"), 'compteur sans montant conservé');
  assert.ok(stats.includes("'candidatures_en_attente', ("), 'compteur de candidatures conservé');

  const profil = sourceBody(migration, 'fn_mon_etablissement_complet');
  assert.ok(profil.includes("v_lecture_finances := public.fn_a_permission_etablissement('lecture_paiement', v_etab_id) IS TRUE\n    OR public.fn_a_permission_etablissement('paiement', v_etab_id) IS TRUE;"));
  assert.ok(profil.includes('      et.rib_s3_key, et.rib_ia_coherent,\n'), 'rib_s3_key et rib_ia_coherent inchangés');

  // Clés masquées par la migration = clés masquées attendues par le banc PG17.
  const masquees = new Set([
    ...[...stats.matchAll(/'(\w+)', CASE WHEN v_lecture_\w+ THEN/g)].map(m => m[1]),
    ...[...profil.matchAll(/CASE WHEN v_lecture_finances THEN et\.\w+ END AS (\w+)/g)].map(m => m[1]),
    ...[...etat.matchAll(/'(\w+)', CASE WHEN v_peut_voir_code THEN/g)].map(m => m[1]),
  ]);
  assert.deepEqual([...masquees].sort(), ['candidatures_recentes', 'code_pointage_actif', 'commissions_cumulees',
    'commissions_impayees', 'iban_last4', 'stripe_account_id', 'stripe_customer_id']);
  const dansBanc = new Set([...bancTest.matchAll(/^\s*\('[a-z_]+', '[a-z_0-9]+', '(\w+)', 'null'\)/gm)].map(m => m[1]));
  assert.deepEqual([...dansBanc].sort(), [...masquees].sort());
});

test('bancs PG17 : vraie migration, fixture commune, garde base vide et câblage CI', () => {
  for (const [texte, base] of [[bancTest, 'visibilite_etab_permission'], [rejeuTest, 'visibilite_etab_rejeu']]) {
    assert.ok(texte.includes(`current_database() <> '${base}'`));
    assert.ok(texte.includes('\\ir fixtures/visibilite-etablissement-permission-banc.sql'));
    assert.ok(texte.includes(`\\ir ../../${migrationPath}`));
    assert.match(texte, /ROLLBACK;\s*$/);
  }
  assert.equal(rejeuTest.split(`\\ir ../../${migrationPath}`).length - 1, 2);
  assert.ok(banc.includes('\\ir visibilite-etablissement-permission-live.sql'));
  for (const role of ['PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE']) {
    assert.ok(banc.includes(`'${role}', true)`), role);
  }
  assert.ok(workflow.includes('node --test tests/node/visibilite-etablissement-permission.node.mjs'));
  assert.ok(workflow.includes('createdb visibilite_etab_permission'));
  assert.ok(workflow.includes('-d visibilite_etab_permission -f tests/security/visibilite-etablissement-permission-isolated.test.sql'));
  assert.ok(workflow.includes('createdb visibilite_etab_rejeu'));
  assert.ok(workflow.includes("grep -Fq 'VISIBILITE_ETAB_PREFLIGHT_SOURCE_DRIFT: fn_etat_pointage_mission(uuid)'"));
  assert.ok(workflow.includes("grep -Fq 'VISIBILITE_ETAB_PREMIERE_APPLICATION_OK'"));
});

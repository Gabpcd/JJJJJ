// B3 (lot 3 app iOS native, B9) — contestation d'un paiement déclaré exécutable
// et idempotente. Contrôle statique sans réseau ni base : la migration part de la
// définition LIVE capturée (tests/fixtures/contestation-paiement-live-20261102.json),
// l'instantané supabase/schema/public.sql suit exactement le nouveau corps, et la
// régression SQL (job sql-transaction) attend les mêmes empreintes.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = text => createHash('md5').update(text, 'utf8').digest('hex');

const live = JSON.parse(read('tests/fixtures/contestation-paiement-live-20261102.json'));
const migrations = readdirSync(new URL('../../supabase/migrations/', import.meta.url))
  .filter(name => name.endsWith('_contestation_paiement_soignant.sql'));
const migrationName = migrations[0];
const migration = migrationName ? read(`supabase/migrations/${migrationName}`) : '';
const schema = read('supabase/schema/public.sql');
const sqlTestPath = 'tests/non-regression/sql/contestation-paiement-soignant.test.sql';
const sqlTest = read(sqlTestPath);
const workflow = read('.github/workflows/validate-pr.yml');

const LIVE_PROSRC_MD5 = 'fbd951f42e23cf3d8ea13b47bb442325';
const LIVE_DEF_MD5 = 'dba3ad2b65e08e731189cade270a2734';
const LIVE_CHECK_MD5 = '9abaa9884a7cba5a880244fb4a877d8c';
const DERNIERE_VERSION_DISTANTE = '20261102150000';

function corpsDollar(sql, ouverture) {
  const debut = sql.indexOf(ouverture);
  assert.ok(debut >= 0, `ouverture absente : ${ouverture}`);
  const tail = sql.slice(debut);
  const tag = /\bAS\s+(\$[A-Za-z_0-9]*\$)/.exec(tail);
  assert.ok(tag, 'corps dollar-quoted absent');
  const offset = tag.index + tag[0].length;
  const fin = tail.indexOf(tag[1], offset);
  assert.ok(fin > offset, 'fin du corps absente');
  return { tag: tag[1], body: tail.slice(offset, fin) };
}

const literaux = arrayText => [...arrayText.matchAll(/'([A-Z0-9_]+)'/g)].map(m => m[1]);
const listeLive = literaux(live.constraint.definition);
const definitionCheck = types => `CHECK ((type = ANY (ARRAY[${types.map(t => `'${t}'::text`).join(', ')}])))`;

function corpsMigration() {
  return corpsDollar(migration, 'CREATE OR REPLACE FUNCTION public.fn_contester_paiement_soignant(');
}

test('la capture LIVE est fidèle (empreintes Postgres recalculées)', () => {
  assert.equal(md5(live.function.definition), LIVE_DEF_MD5);
  assert.equal(live.function.definition_md5, LIVE_DEF_MD5);
  const { body } = corpsDollar(live.function.definition, 'CREATE OR REPLACE FUNCTION public.fn_contester_paiement_soignant(');
  assert.equal(md5(body), LIVE_PROSRC_MD5);
  assert.equal(live.function.prosrc_md5, LIVE_PROSRC_MD5);
  assert.equal(md5(live.constraint.definition), LIVE_CHECK_MD5);
  assert.equal(definitionCheck(listeLive), live.constraint.definition, 'la liste LIVE se reconstruit à l’identique');
  assert.equal(listeLive.length, 57);
  assert.ok(!listeLive.includes('CONTESTATION_PAIEMENT'), 'le défaut LIVE : type absent du CHECK');
  assert.match(live.function.definition, /'CONTESTATION_PAIEMENT'/);
  assert.deepEqual(live.function.proconfig, ['search_path=public']);
});

test('la dernière migration du CHECK dans le dépôt produit la même liste que la production', () => {
  const source = read('supabase/migrations/20260709210000_presences_audit_sql_notif_validation.sql');
  const bloc = source.split('ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[')[1].split(']))')[0];
  assert.deepEqual(literaux(bloc), listeLive);
});

test('une seule migration B3, horodatée après la dernière version distante, sans transaction interne', () => {
  assert.equal(migrations.length, 1, 'exactement un fichier *_contestation_paiement_soignant.sql');
  assert.match(migrationName, /^\d{14}_contestation_paiement_soignant\.sql$/);
  assert.ok(migrationName.slice(0, 14) > DERNIERE_VERSION_DISTANTE);
  const toutes = readdirSync(new URL('../../supabase/migrations/', import.meta.url)).filter(n => n.endsWith('.sql')).sort();
  assert.equal(toutes.at(-1), migrationName, 'la migration B3 est la plus récente du dépôt');
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im);
  assert.doesNotMatch(migration, /\b(GRANT|REVOKE)\b/, 'ACL conservées par CREATE OR REPLACE');
  assert.doesNotMatch(migration, /\bDROP\s+FUNCTION\b/i);
  const tags = [...migration.matchAll(/\$([A-Za-z_][A-Za-z_0-9]*)\$/g)].map(m => m[1]);
  assert.ok(!migration.includes('$$'), 'aucun dollar-quoting anonyme');
  const ouvertures = new Map();
  for (const tag of tags) ouvertures.set(tag, (ouvertures.get(tag) ?? 0) + 1);
  for (const [tag, n] of ouvertures) assert.equal(n, 2, `étiquette $${tag}$ utilisée une seule fois (ouverture + fermeture)`);
  assert.ok(ouvertures.size >= 3, 'préflight, corps et postflight ont chacun leur étiquette');
});

test('le préflight refuse tout départ différent de la définition LIVE', () => {
  const preflight = migration.split('$contestation_preflight$')[1] ?? '';
  assert.ok(migration.indexOf('$contestation_preflight$') < migration.indexOf('ALTER TABLE public.notifications'));
  assert.ok(preflight.includes(`'${LIVE_PROSRC_MD5}'`));
  assert.ok(preflight.includes(`'${LIVE_CHECK_MD5}'`));
  assert.match(preflight, /has_function_privilege\('anon'/);
  assert.match(preflight, /security_definer_inventory/);
});

test('CHECK notifications = liste LIVE + CONTESTATION_PAIEMENT, sans autre changement', () => {
  const alter = migration.split('ALTER TABLE public.notifications')[1].split(';')[0];
  assert.match(alter, /DROP CONSTRAINT notifications_type_check,\s+ADD CONSTRAINT notifications_type_check CHECK \(type = ANY \(ARRAY\[/);
  const attendue = [...listeLive, 'CONTESTATION_PAIEMENT'];
  assert.deepEqual(literaux(alter), attendue);
  const md5Nouveau = md5(definitionCheck(attendue));
  const postflight = migration.split('$contestation_postflight$')[1] ?? '';
  assert.ok(postflight.includes(`'${md5Nouveau}'`), 'postflight : empreinte du nouveau CHECK');
  assert.ok(sqlTest.includes(`'${md5Nouveau}'`), 'régression SQL : même empreinte du CHECK');
  // Instantané prod : même liste, format pg_dump.
  const ligne = schema.split('\n').find(l => l.includes('CONSTRAINT "notifications_type_check"'));
  assert.deepEqual(literaux(ligne), attendue);
  assert.ok(ligne.endsWith(`'CONTESTATION_PAIEMENT'::"text"]))),`));
});

test('le nouveau corps garde les textes serveur LIVE et ajoute gardes, verrou et idempotence', () => {
  const { tag, body } = corpsMigration();
  assert.equal(tag, '$fn_contester$');
  const enTete = migration.split('CREATE OR REPLACE FUNCTION public.fn_contester_paiement_soignant(')[1].split(tag)[0];
  assert.match(enTete, /^p_paiement_id uuid, p_motif text\)\s+RETURNS jsonb\s+LANGUAGE plpgsql\s+SECURITY DEFINER\s+SET search_path TO 'public'\s+AS $/);
  // Textes LIVE conservés à l'identique (litige, notifications, erreurs historiques).
  for (const texte of [
    "'Paiement contesté — ' || v_motif",
    "'CONTESTATION_PAIEMENT',\n        'Paiement contesté ⚠️',\n        'Le soignant conteste un paiement. Motif : ' || v_motif,\n        '/etablissement/facturation',\n        'ETABLISSEMENT',",
    "SELECT id, 'SYSTEM', 'Paiement contesté ⚠️',\n        'Un soignant conteste un paiement. Motif : ' || v_motif,\n        '/admin/facturation', 'ADMIN',",
    "FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'\n    LIMIT 1;",
    "'error', 'Paiement introuvable'",
    "'error', 'Accès refusé'",
    "RETURN jsonb_build_object('success', true, 'litige_id', v_litige_id);",
  ]) assert.ok(body.includes(texte), `texte absent : ${texte}`);
  // Gardes B3.
  assert.match(body, /IF v_uid IS NULL OR NOT public\.fn_compte_auth_actif\(\) THEN/);
  assert.match(body, /'Non authentifié ou compte inactif', 'error_code', 'NON_AUTHENTIFIE'/);
  assert.match(body, /v_motif TEXT := btrim\(COALESCE\(p_motif, ''\)\);/);
  assert.match(body, /IF v_motif = '' THEN\s+RETURN jsonb_build_object\('error', 'Motif requis', 'error_code', 'MOTIF_INVALIDE'\);/);
  assert.match(body, /IF char_length\(v_motif\) > 500 THEN/);
  assert.match(body, /FROM public\.paiements_soignant\s+WHERE id = p_paiement_id\s+FOR UPDATE;/);
  assert.match(body, /IF v_paiement\.id IS NULL THEN/, 'jamais RECORD IS NULL (incident Sprint 17)');
  assert.doesNotMatch(body, /v_paiement IS NULL/);
  assert.match(body, /IF v_paiement\.statut = 'CONTESTE' OR v_paiement\.conteste IS TRUE THEN\s+RETURN jsonb_build_object\('error', 'Paiement déjà contesté', 'error_code', 'DEJA_CONTESTE'\);/);
  assert.match(body, /IF v_paiement\.statut NOT IN \('DECLARE', 'EN_ATTENTE'\) THEN/);
  assert.match(body, /EXCEPTION WHEN unique_violation THEN/);
  assert.match(body, /IS DISTINCT FROM 'uq_litige_mission_type_ouvert_legacy' THEN\s+RAISE;/);
  // Ordre : toutes les gardes avant la première écriture.
  const premiereEcriture = body.indexOf('UPDATE public.paiements_soignant');
  for (const garde of ['fn_compte_auth_actif', "'MOTIF_INVALIDE'", 'FOR UPDATE', "'ACCES_REFUSE'", "'DEJA_CONTESTE'", "'DEJA_CONFIRME'", "'STATUT_INVALIDE'"]) {
    const i = body.indexOf(garde);
    assert.ok(i >= 0 && i < premiereEcriture, `garde ${garde} avant toute écriture`);
  }
  // UPDATE + INSERT litige dans le même sous-bloc atomique ; notifications après.
  const sousBloc = body.slice(body.indexOf('    BEGIN\n'), body.indexOf('EXCEPTION WHEN unique_violation'));
  assert.ok(sousBloc.includes('UPDATE public.paiements_soignant') && sousBloc.includes('INSERT INTO public.litiges'));
  assert.ok(body.indexOf("'CONTESTATION_PAIEMENT'") > body.indexOf('EXCEPTION WHEN unique_violation'));
  assert.doesNotMatch(body, /\$\$|\$[A-Za-z_]+\$/, 'corps sans dollar-quoting imbriqué');
});

test('instantané public.sql = corps de la migration (drift-check) et empreinte partagée', () => {
  const { body } = corpsMigration();
  const instantane = corpsDollar(schema, 'CREATE OR REPLACE FUNCTION "public"."fn_contester_paiement_soignant"(');
  assert.equal(instantane.tag, '$$');
  assert.equal(instantane.body, body);
  assert.ok(schema.includes(`CREATE OR REPLACE FUNCTION "public"."fn_contester_paiement_soignant"("p_paiement_id" "uuid", "p_motif" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$`));
  const nouveau = md5(body);
  assert.notEqual(nouveau, LIVE_PROSRC_MD5);
  const postflight = migration.split('$contestation_postflight$')[1] ?? '';
  assert.ok(postflight.includes(`'${nouveau}'`), 'postflight : empreinte du nouveau corps');
  assert.ok(sqlTest.includes(`'${nouveau}'`), 'régression SQL : empreinte du nouveau corps');
  // Inventaire SECURITY DEFINER : seule l'empreinte (et sa justification) suit le corps.
  const inventaire = migration.split('UPDATE private.security_definer_inventory')[1].split(';')[0];
  assert.match(inventaire, /definition_md5 = \(SELECT md5\(p\.prosrc\) FROM pg_proc p/);
  assert.ok(inventaire.includes(`AND definition_md5 = '${LIVE_PROSRC_MD5}'`));
  assert.doesNotMatch(inventaire, /categorie\s*=/);
  // ACL et grants inchangés dans l'instantané.
  for (const ligne of [
    'REVOKE ALL ON FUNCTION "public"."fn_contester_paiement_soignant"("p_paiement_id" "uuid", "p_motif" "text") FROM PUBLIC;',
    'GRANT ALL ON FUNCTION "public"."fn_contester_paiement_soignant"("p_paiement_id" "uuid", "p_motif" "text") TO "authenticated";',
    'GRANT ALL ON FUNCTION "public"."fn_contester_paiement_soignant"("p_paiement_id" "uuid", "p_motif" "text") TO "service_role";',
  ]) assert.ok(schema.includes(ligne), ligne);
});

test('les bornes serveur restent compatibles avec le client web (motif non vide ≤ 500)', () => {
  const bandeau = read('src/components/BandeauPaiementDeclare.tsx');
  assert.match(bandeau, /maxLength=\{500\}/);
  assert.match(bandeau, /disabled=\{!motif\.trim\(\)\}/);
  assert.match(bandeau, /p_motif: motif \|\| 'Contesté par le soignant'/);
  assert.match(bandeau, /\.eq\('statut', 'DECLARE'\)/);
});

test('la régression SQL est raccordée au job sql-transaction et toujours annulée', () => {
  assert.match(sqlTest, /^(--[^\n]*\n)+BEGIN;\n/);
  assert.match(sqlTest, /\nROLLBACK;\n$/);
  assert.doesNotMatch(sqlTest, /^\s*COMMIT\s*;/im);
  assert.match(sqlTest, /EXISTS\(SELECT 1 FROM cron\.job WHERE active\)/, 'refus hors staging isolé');
  const run = workflow.split('name: Exécuter les migrations ajoutées et les régressions SQL sans persister')[1];
  assert.ok(run.includes(`            ${sqlTestPath}\n          )`), 'suite ajoutée en fin de SQL_TESTS');
  assert.ok(workflow.includes('node --test tests/node/contestation-paiement-soignant.node.mjs'));
});

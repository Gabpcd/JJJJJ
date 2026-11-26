// Banc SQL de la cohorte STAGING du lot 5 : découpage, socle, objets `private` et moteur psql, hors base (le banc lui-même
// tourne sur PostgreSQL 17 dans tests/postgres/staging-lot5-fixture.pg17.mjs, et en local sur PGlite).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decouper, SOCLE, objetsPrives, moteurPsql, REQUIS, tupleDeCle, parametresRequis } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';

test('découpage : dollar-quotes, chaînes, identifiants et commentaires respectés', () => {
  const sql = `SELECT 'a;b' AS "x;y"; -- c;d
DO $l5$ BEGIN PERFORM 1; END $l5$;
CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $$ SELECT 1; $$; /* e;f */ SELECT 'it''s;'`;
  assert.deepEqual(decouper(sql).map(s => s.replace(/\s+/g, ' ').trim()), [
    `SELECT 'a;b' AS "x;y";`,
    '-- c;d DO $l5$ BEGIN PERFORM 1; END $l5$;',
    'CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $$ SELECT 1; $$;',
    `/* e;f */ SELECT 'it''s;'`,
  ]);
  const dump = readFileSync(new URL('../../supabase/schema/public.sql', import.meta.url), 'utf8');
  const instructions = decouper(dump);
  assert.ok(instructions.length > 7000, `${instructions.length} instructions`);
  assert.ok(instructions.some(i => i.startsWith('CREATE OR REPLACE FUNCTION "public"."fn_test_update_mission"')));
});

test('socle : aucun objet de public, stubs Supabase présents', () => {
  assert.doesNotMatch(SOCLE, /\bpublic\.\w+\s*\(/i);
  for (const attendu of ['auth.users', 'auth.uid()', 'auth.role()', 'net.http_post', 'vault.decrypted_secrets', 'pgcrypto']) {
    assert.ok(SOCLE.includes(attendu), attendu);
  }
});

test('objets private : relus dans les migrations, dernière définition de chaque fonction', () => {
  const { structure, fonctions } = objetsPrives();
  assert.ok(fonctions.some(f => /FUNCTION private\.fn_comptes_meme_cohorte_test\(/.test(f)));
  assert.ok(fonctions.some(f => /FUNCTION private\.fn_garder_facture_imputation\(/.test(f)));
  assert.ok(structure.some(i => /private\.mission_internat_intent/.test(i)));
  assert.ok(fonctions.every(f => f.startsWith('CREATE OR REPLACE FUNCTION')));
  assert.ok(REQUIS.fonctions.includes('fn_geler_mission_a_assignation'));
});

test('moteur psql : seule la dernière instruction est relue (JSON), arrêt sur erreur, chargement sans arrêt', async () => {
  const appels = [];
  const spawn = (cmd, args, opts) => {
    appels.push({ cmd, args, input: opts.input });
    if (opts.input.includes('boom')) return { status: 3, stdout: '', stderr: 'psql:<stdin>:4: ERROR:  boom\n' };
    if (args.includes('ON_ERROR_STOP=0')) return { status: 0, stdout: '', stderr: 'psql:<stdin>:2: ERROR:  x\n' };
    return { status: 0, stdout: '[{"ok" : true}]\n', stderr: '' };
  };
  const m = moteurPsql({ spawn, env: {} });
  assert.deepEqual(await m.executer('BEGIN; SET LOCAL a = 1; COMMIT; SELECT true AS ok;'), [{ ok: true }]);
  const script = appels[0].input;
  assert.ok(script.startsWith('\\o /dev/null\n'), script);
  assert.ok(script.includes("\\o\nSELECT coalesce(json_agg(l5_banc_ligne), '[]') FROM (SELECT true AS ok) l5_banc_ligne;"), script);
  // Une colonne nommée comme un alias court ne masque jamais la ligne : alias réservé (job PostgreSQL 17 de #1187).
  await m.executer('SELECT 1 AS r;');
  assert.ok(appels.at(-1).input.includes('FROM (SELECT 1 AS r) l5_banc_ligne;'), appels.at(-1).input);
  assert.deepEqual(appels[0].args, ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-f', '-']);
  assert.deepEqual(await m.executer('DELETE FROM t;'), [], 'dernière instruction sans lignes');
  await assert.rejects(m.executer('SELECT boom;'), /ERROR:  boom/);
  const lot = await m.lot(['SELECT 1', 'SELECT 2;']);
  assert.deepEqual(lot, { passe: 1, echecs: ['psql:<stdin>:2: ERROR:  x'] });
  assert.ok(appels.at(-1).args.includes('ON_ERROR_STOP=0'));
});

test('validate-pr : le banc tourne sur PostgreSQL 17 dans une base dédiée', () => {
  const ci = readFileSync(new URL('../../.github/workflows/validate-pr.yml', import.meta.url), 'utf8');
  assert.match(ci, /psql -X -v ON_ERROR_STOP=1 -c 'CREATE DATABASE staging_lot5_banc'\n\s+PGDATABASE=staging_lot5_banc node --test tests\/postgres\/staging-lot5-fixture\.pg17\.mjs/);
});

test('paramètres requis : la clé ouvre un tuple de VALUES, jamais une occurrence quelconque (revue de #1193, m3)', () => {
  const re = tupleDeCle('taux_horaire_minimum_salarie');
  assert.ok(re.test("INSERT INTO public.parametres_systeme(cle,valeur,label) VALUES('taux_horaire_minimum_salarie',12.31,'x') ON CONFLICT(cle) DO NOTHING;"));
  assert.ok(re.test("INSERT INTO parametres_systeme (cle, valeur) VALUES\n  ('a', 1),\n  ('taux_horaire_minimum_salarie', 12.31);"), 'tuple suivant');
  assert.ok(!re.test("INSERT INTO public.parametres_systeme(cle,valeur,description) VALUES('autre',1,'voir ''taux_horaire_minimum_salarie''');"), 'description d un autre paramètre');
  assert.ok(!re.test("INSERT INTO public.parametres_systeme(valeur,cle) VALUES(12.31,'taux_horaire_minimum_salarie');"), 'colonne cle non en tête');
  assert.ok(!re.test("INSERT INTO public.autre_table(cle,valeur) VALUES('taux_horaire_minimum_salarie',1);"));
  const lignes = parametresRequis();
  assert.equal(lignes.length, 1);
  assert.match(lignes[0], /VALUES\('taux_horaire_minimum_salarie',12\.31,/);
  assert.throws(() => parametresRequis(undefined, ['cle_inexistante_xyz']), /cle_inexistante_xyz/);
});

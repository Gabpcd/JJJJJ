// Prospection sans Apicrypt (20261117060000, B9) — contrôle hors réseau.
// Ne remplace pas la suite SQL (tests/security/agents-croissance-brouillons.test.sql,
// section 10, exécutée sur le staging sous ROLLBACK) ; verrouille ce qu'elle ne
// peut pas voir :
//   * l'empreinte du préflight est bien celle du corps de 20261116143942
//     (md5 du texte entre les deux délimiteurs $body$, comme pg_proc.prosrc) ;
//   * seule la règle unique est redéfinie, en-tête identique, et son nouveau
//     corps n'ajoute que apicrypt.org à mssante.fr ;
//   * le préflight précède toute écriture ; l'expiration réutilise la fonction
//     de 20261116143942, appelée une fois, sans DELETE ni copie de l'UPDATE ;
//   * aucun SECURITY DEFINER ni GRANT, câblage CI présent.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261117060000_prospection_sans_apicrypt.sql';
const ORIGINE = '20261116143942_prospection_sans_mssante.sql';
const SUITE = 'tests/security/agents-croissance-brouillons.test.sql';
const migration = read(`supabase/migrations/${MIGRATION}`);
const origine = read(`supabase/migrations/${ORIGINE}`);
const suite = read(SUITE);
const workflow = read('.github/workflows/validate-pr.yml');

// md5(prosrc) relu en prod le 17/11/2026 (flripxtsyegjshnhzjkz) : identique au corps du dépôt.
const EMPREINTE = 'b3e53f83ac32ed999ced5d7e66c83d4a';
// Dernière version du registre de production au 17/11/2026 (description de la PR).
const DERNIERE_VERSION_DISTANTE = '20261116143942';

function definition(sql, nom) {
  const marqueur = `CREATE OR REPLACE FUNCTION ${nom}(`;
  const debut = sql.indexOf(marqueur);
  assert.ok(debut >= 0, `${nom} : définition absente`);
  assert.equal(sql.indexOf(marqueur, debut + 1), -1, `${nom} : définie deux fois`);
  const reste = sql.slice(debut);
  const ouverture = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/.exec(reste);
  assert.ok(ouverture, `${nom} : corps dollar-quoted absent`);
  const corpsDebut = ouverture.index + ouverture[0].length;
  const corpsFin = reste.indexOf(ouverture[1], corpsDebut);
  assert.ok(corpsFin > corpsDebut, `${nom} : fin du corps absente`);
  return { entete: reste.slice(0, ouverture.index), corps: reste.slice(corpsDebut, corpsFin) };
}

const sansCommentaires = sql => sql.replace(/--[^\n]*/g, '');

test('une seule migration, horodatée après le registre distant, sans transaction interne ni $$', () => {
  const noms = readdirSync(new URL('../../supabase/migrations/', import.meta.url)).filter(n => n.endsWith('.sql')).sort();
  assert.equal(noms.filter(n => n.endsWith('_prospection_sans_apicrypt.sql')).length, 1);
  assert.match(MIGRATION, /^\d{14}_/);
  assert.ok(MIGRATION.slice(0, 14) > DERNIERE_VERSION_DISTANTE);
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK);\s*$/m);
  assert.doesNotMatch(migration, /\$\$/);
  assert.doesNotMatch(migration, /\r/);
});

test(`préflight : empreinte de fn_growth_email_mssante = corps de ${ORIGINE}`, () => {
  const { corps } = definition(origine, 'private.fn_growth_email_mssante');
  assert.equal(md5(corps), EMPREINTE);
  assert.notEqual(md5(`${corps} `), EMPREINTE, 'une dérive blanche change l\'empreinte');
  const bloc = migration.slice(migration.indexOf("to_regprocedure('private.fn_growth_email_mssante(text)')"));
  assert.ok(bloc.length < migration.length, 'préflight absent');
  const verif = bloc.slice(0, bloc.indexOf('END IF;'));
  assert.match(verif, new RegExp(`md5\\(p\\.prosrc\\) <> '${EMPREINTE}'`));
  assert.match(verif, /p\.prosecdef IS DISTINCT FROM false/);
  assert.match(verif, /p\.provolatile <> 'i'/);
  assert.match(verif, /p\.proconfig IS DISTINCT FROM ARRAY\['search_path=""'\]::text\[\]/);
  assert.match(verif, /RAISE EXCEPTION '[^']*CLAUDE\.md, garde-fous 9\.0 n°2/);
});

test('le préflight précède toute écriture et exige la fonction d\'expiration', () => {
  const code = sansCommentaires(migration);
  const finPreflight = code.indexOf('$prospection_sans_apicrypt_avant$;');
  assert.ok(finPreflight > 0);
  assert.ok(finPreflight < code.search(/\b(CREATE|REVOKE|UPDATE|INSERT|DELETE)\b/));
  assert.match(code.slice(0, finPreflight),
    /to_regprocedure\('private\.fn_growth_expirer_brouillons_mssante\(\)'\) IS NULL THEN\s+RAISE EXCEPTION/);
});

test('seule la règle unique est redéfinie : en-tête identique, apicrypt.org ajouté à mssante.fr', () => {
  const code = sansCommentaires(migration);
  const definitions = [...code.matchAll(/CREATE OR REPLACE FUNCTION ([a-z_.]+)\(/g)].map(m => m[1]);
  assert.deepEqual(definitions, ['private.fn_growth_email_mssante']);
  const avant = definition(origine, 'private.fn_growth_email_mssante');
  const apres = definition(migration, 'private.fn_growth_email_mssante');
  assert.equal(apres.entete, avant.entete);
  assert.equal(apres.corps.replace('[@.](mssante\\.fr|apicrypt\\.org)$', '[@.]mssante\\.fr$'), avant.corps,
    'seule l\'expression régulière change');
  assert.equal(apres.corps.trim(),
    "SELECT COALESCE(lower(btrim(p_email, E' \\t\\r\\n')) ~ '[@.](mssante\\.fr|apicrypt\\.org)$', false);");
  assert.ok(migration.includes('REVOKE ALL ON FUNCTION private.fn_growth_email_mssante(text) FROM PUBLIC, anon, authenticated;'));
});

test('expiration : la fonction de 20261116143942, appelée une fois après la règle, sans DELETE', () => {
  const code = sansCommentaires(migration);
  const appels = [...code.matchAll(/private\.fn_growth_expirer_brouillons_mssante\(\);/g)];
  assert.equal(appels.length, 1);
  assert.ok(appels[0].index > code.indexOf('CREATE OR REPLACE FUNCTION private.fn_growth_email_mssante('));
  assert.doesNotMatch(code, /\bUPDATE\b/);
  assert.doesNotMatch(code, /\bDELETE\b/);
});

test('la suite SQL couvre Apicrypt sans recopier la règle', () => {
  assert.doesNotMatch(sansCommentaires(suite), /apicrypt\\\.org/, 'la suite SQL recopie la règle');
  for (const attendu of ['@interop-mssante.apicrypt.org', '@pasapicrypt.org', '@apicrypt.org.exemple.com',
    "'Apicrypt : fn_growth_email_mssante juste sur % cas sur 9'", "cible_id = 'ZZGROW051'",
    "'recette-apicrypt:ZZGROW053:expire:' || id"]) {
    assert.ok(suite.includes(attendu), attendu);
  }
});

test('aucun SECURITY DEFINER ni GRANT : rien à inventorier, ACL d\'origine conservées', () => {
  const code = sansCommentaires(migration);
  assert.doesNotMatch(code, /SECURITY\s+DEFINER/i);
  assert.doesNotMatch(code, /\bGRANT\b/i);
  assert.doesNotMatch(code, /security_definer_inventory/);
});

test('câblage CI : garde Node et suite SQL sous ROLLBACK', () => {
  assert.match(workflow, /run: node --test tests\/node\/prospection-sans-apicrypt\.node\.mjs/);
  assert.match(workflow, new RegExp(`^\\s+${SUITE.replace(/[.]/g, '\\.')}$`, 'm'));
});

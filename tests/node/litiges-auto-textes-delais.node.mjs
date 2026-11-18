// Litiges auto-créés : textes de délai dérivés des paramètres (20261118152150,
// suite de D12, B9 + HARD STOP n°4) — contrôle hors réseau.
// Ne remplace pas le banc psql tests/litiges/fix-textes-delais-auto-creation.test.sql
// (staging ou base locale, ROLLBACK) ; verrouille ce qu'il ne peut pas voir :
//   * les empreintes du préflight sont celles des corps LIVE, identiques aux
//     corps de 20260729121442 (md5 du texte entre les délimiteurs, comme
//     pg_proc.prosrc), relues en production le 18/11/2026 ;
//   * les nouveaux corps = corps LIVE + les seuls remplacements de texte
//     listés ici (aucun autre changement), en-têtes identiques ;
//   * le délai du motif et de l'audit vient de la variable qui filtre les
//     présences (paramètre delai_contestation_pointage_h), plus aucun
//     « 48h » ni « Répondez sous 72h » en dur ;
//   * le miroir SMS de tests/sms/litige-length.test.ts suit le SQL ;
//   * aucun GRANT ni REVOKE, câblage CI présent.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261118152150_litiges_auto_textes_delais.sql';
const ORIGINE = '20260729121442_securiser_auth_et_crons_critiques.sql';
const migration = read(`supabase/migrations/${MIGRATION}`);
const origine = read(`supabase/migrations/${ORIGINE}`);
const miroirSms = read('tests/sms/litige-length.test.ts');
const banc = read('tests/litiges/fix-textes-delais-auto-creation.test.sql');
const workflow = read('.github/workflows/validate-pr.yml');

// Dernière version du registre de production relue le 18/11/2026, et
// migration de paramétrage de #1140 (delai_contestation_pointage_h = 72).
const DERNIERE_VERSION_DISTANTE = '20261117060000';
const VERSION_PR_1140 = '20261118145614';

const AUTO = 'public.fn_auto_creation_litiges_presence';
const PUSH = 'public.fn_litige_push_notification';
// md5(prosrc) relus en production (flripxtsyegjshnhzjkz) le 18/11/2026.
const EMPREINTES_LIVE = {
  [AUTO]: 'b418c1958bbb5489d220315c2763f0b3',
  [PUSH]: '8e6fd51152b7b15f5673fe13872df5e9',
};

// Seuls changements autorisés (texte avant -> texte après), chacun présent
// exactement une fois dans le corps LIVE.
const REMPLACEMENTS = {
  [AUTO]: [
    [
      `      v_motif :=
        'Auto-création : soignant marqué absent sans contestation dans les 48h';`,
      `      v_motif := format(
        'Auto-création : soignant marqué absent sans contestation dans les %sh',
        v_delai_pointage_h
      );`,
    ],
    [
      `      v_notif_corps :=
        'Votre établissement a signalé une absence. Répondez sous 72h pour éviter l''escalade automatique.';`,
      `      v_notif_corps :=
        'Votre établissement a signalé une absence.';`,
    ],
    [
      `      v_notif_corps :=
        'Votre établissement a signalé un départ anticipé. Répondez sous 72h pour éviter l''escalade automatique.';`,
      `      v_notif_corps :=
        'Votre établissement a signalé un départ anticipé.';`,
    ],
    [
      `          WHEN 'ABSENCE_SOIGNANT' THEN
            'Absence non contestée dans les 48h post-validation présence'
          WHEN 'DEPART_ANTICIPE' THEN
            'Départ anticipé (< 80 % heures prévues) non contesté dans les 48h'`,
      `          WHEN 'ABSENCE_SOIGNANT' THEN
            format(
              'Absence non contestée dans les %sh post-validation présence',
              v_delai_pointage_h
            )
          WHEN 'DEPART_ANTICIPE' THEN
            format(
              'Départ anticipé (< 80 %% heures prévues) non contesté dans les %sh',
              v_delai_pointage_h
            )`,
    ],
  ],
  [PUSH]: [
    [
      `        || ' a été ouvert sur votre mission. Répondez sous 72h.'`,
      `        || ' a été ouvert sur votre mission.'`,
    ],
  ],
};

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
  return { entete: reste.slice(0, ouverture.index), tag: ouverture[1], corps: reste.slice(corpsDebut, corpsFin) };
}

function occurrences(texte, fragment) {
  return texte.split(fragment).length - 1;
}

const sansCommentaires = sql => sql.replace(/--[^\n]*/g, '');

test('une seule migration, horodatée après le registre distant et #1140, sans transaction interne ni $$', () => {
  const noms = readdirSync(new URL('../../supabase/migrations/', import.meta.url)).filter(n => n.endsWith('.sql'));
  assert.equal(noms.filter(n => n.endsWith('_litiges_auto_textes_delais.sql')).length, 1);
  assert.match(MIGRATION, /^\d{14}_/);
  assert.ok(MIGRATION.slice(0, 14) > DERNIERE_VERSION_DISTANTE);
  assert.ok(MIGRATION.slice(0, 14) > VERSION_PR_1140);
  assert.ok(MIGRATION.startsWith('20261118'), 'date courante du 18/11/2026');
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK);\s*$/m);
  assert.doesNotMatch(migration, /\$\$/);
  assert.doesNotMatch(migration, /\r/);
});

for (const nom of [AUTO, PUSH]) {
  test(`préflight : empreinte LIVE de ${nom} = corps de ${ORIGINE}`, () => {
    const { corps } = definition(origine, nom);
    assert.equal(md5(corps), EMPREINTES_LIVE[nom]);
    assert.notEqual(md5(`${corps} `), EMPREINTES_LIVE[nom], 'une dérive blanche change l\'empreinte');
    const code = sansCommentaires(migration);
    const finPreflight = code.indexOf('$litiges_textes_delais_avant$;');
    assert.ok(finPreflight > 0, 'préflight absent');
    assert.ok(finPreflight < code.indexOf('CREATE OR REPLACE FUNCTION'), 'le préflight précède toute écriture');
    assert.ok(code.slice(0, finPreflight).includes(`'${EMPREINTES_LIVE[nom]}'`), `empreinte ${EMPREINTES_LIVE[nom]} absente du préflight`);
  });

  test(`${nom} : en-tête identique, seuls les remplacements de texte listés`, () => {
    const avant = definition(origine, nom);
    const apres = definition(migration, nom);
    assert.equal(apres.entete, avant.entete, 'en-tête (signature, SECURITY DEFINER, search_path) inchangé');
    assert.notEqual(apres.tag, '$$');
    let attendu = avant.corps;
    for (const [ancien, nouveau] of REMPLACEMENTS[nom]) {
      assert.equal(occurrences(attendu, ancien), 1, `texte LIVE attendu une fois : ${ancien}`);
      attendu = attendu.replace(ancien, () => nouveau);
    }
    assert.equal(apres.corps, attendu, 'aucun autre changement que les textes');
    const post = sansCommentaires(migration).slice(sansCommentaires(migration).indexOf('$litiges_textes_delais_apres$'));
    assert.ok(post.includes(`'${md5(apres.corps)}'`), `post-condition : empreinte ${md5(apres.corps)} absente`);
  });
}

test('le délai affiché vient du paramètre qui filtre les présences, plus aucun délai en dur', () => {
  const { corps } = definition(migration, AUTO);
  assert.equal(occurrences(corps, "WHERE pl.cle = 'delai_contestation_pointage_h'"), 1);
  assert.equal(occurrences(corps, 'make_interval(hours => v_delai_pointage_h)'), 1);
  assert.equal(occurrences(corps, '%sh\',\n        v_delai_pointage_h\n      );'), 1, 'motif formaté depuis le paramètre');
  assert.equal(occurrences(corps, 'v_delai_pointage_h\n            )'), 2, 'raisons d\'audit formatées depuis le paramètre');
  assert.doesNotMatch(corps, /\b\d+\s?h\b/i, 'aucun délai chiffré en dur');
  assert.doesNotMatch(corps, /Répondez/);
  assert.doesNotMatch(corps, /escalade/i);
  // Le motif du départ anticipé garde son format (heures effectuées / prévues).
  assert.ok(corps.includes("'Auto-création : départ anticipé (%sh effectuées sur %sh prévues, soit %s %%).'"));
  // « % » littéral échappé dans format() (sinon spécificateur invalide).
  assert.ok(corps.includes("'Départ anticipé (< 80 %% heures prévues) non contesté dans les %sh'"));
});

test('SMS LITIGE_OUVERTURE sans promesse chiffrée ; autres SMS inchangés (rappel J1 : point ouvert)', () => {
  const { corps } = definition(migration, PUSH);
  assert.doesNotMatch(corps, /Répondez sous 72h/);
  assert.equal(occurrences(corps, "|| ' a été ouvert sur votre mission.'"), 1);
  // Rappel J1 hors périmètre (signalé dans la PR) : texte LIVE conservé tel quel.
  assert.equal(occurrences(corps, "'litige en attente depuis 1j. Répondez sous 24h pour éviter l''escalade.'"), 1);
  assert.match(miroirSms,
    /case 'LITIGE_OUVERTURE':[\s\S]*?return `un litige \$\{data\.type_litige \?\? ''\} a été ouvert sur votre mission\.`;/,
    'le miroir TS du SMS suit le SQL');
  assert.doesNotMatch(miroirSms, /Répondez sous 72h/);
});

test('commentaire de fonction : nom du paramètre au lieu de « 48h »', () => {
  const code = sansCommentaires(migration);
  const ligne = code.split('\n').find(l => l.startsWith('COMMENT ON FUNCTION public.fn_auto_creation_litiges_presence() IS '));
  assert.ok(ligne, 'COMMENT ON FUNCTION absent');
  assert.ok(ligne.includes('dans le délai parametres_litiges.delai_contestation_pointage_h post-validation étab'));
  assert.doesNotMatch(ligne, /48h/);
  assert.ok(code.includes("pg_catalog.obj_description(\n       pg_catalog.to_regprocedure('public.fn_auto_creation_litiges_presence()'), 'pg_proc')"));
});

test('aucun GRANT ni REVOKE, deux redéfinitions seulement, ACL vérifiées avant et après', () => {
  const code = sansCommentaires(migration);
  // Squelette : blocs dollar-quoted (corps de fonctions, DO) remplacés.
  const squelette = code.replace(/\$([a-z_]+)\$[\s\S]*?\$\1\$/g, "'bloc'");
  assert.doesNotMatch(squelette, /\bGRANT\b/);
  assert.doesNotMatch(squelette, /\bREVOKE\b/);
  assert.doesNotMatch(squelette, /\b(UPDATE|DELETE|INSERT|DROP|TRUNCATE|ALTER)\b/,
    'aucune écriture de données ni DDL hors des deux CREATE OR REPLACE et du COMMENT');
  const instructions = squelette.split(';').map(s => s.trim().split(/\s+/).slice(0, 2).join(' ')).filter(Boolean);
  assert.deepEqual(instructions, ['SET LOCAL', "DO 'bloc'", 'CREATE OR', 'CREATE OR', 'COMMENT ON', "DO 'bloc'"]);
  const definitions = [...squelette.matchAll(/CREATE OR REPLACE FUNCTION ([a-z_.]+)\(/g)].map(m => m[1]);
  assert.deepEqual(definitions, [AUTO, PUSH]);
  assert.equal(occurrences(code, "pg_catalog.has_function_privilege('authenticated', v_proc.oid, 'EXECUTE')"), 2);
  assert.equal(occurrences(code, 'FROM private.security_definer_inventory i'), 1, 'inventaire contrôlé au préflight');
});

test('banc psql : délai lu dans le paramètre, assertions sur motif, notification et SMS', () => {
  assert.match(banc, /WHERE cle = 'delai_contestation_pointage_h'/);
  assert.match(banc, /make_interval\(hours => v_delai \+ 1\)/);
  assert.doesNotMatch(banc, /INTERVAL '49 hours'/, 'aucun délai figé dans le banc');
  for (const attendu of [
    "format('Auto-création : soignant marqué absent sans contestation dans les %sh', v_delai)",
    "'Votre établissement a signalé une absence.'",
    "'un litige ABSENCE_SOIGNANT a été ouvert sur votre mission.'",
  ]) {
    assert.ok(banc.includes(attendu), attendu);
  }
  assert.match(banc, /^ROLLBACK;$/m);
});

test('câblage CI : garde Node', () => {
  assert.match(workflow, /run: node --test tests\/node\/litiges-auto-textes-delais\.node\.mjs/);
});

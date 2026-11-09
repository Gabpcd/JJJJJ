// B9 — la DPAE couvre les contrats CDDU et VACATION dans les cinq fonctions
// serveur qui les excluaient (migration 20261108223500). Contrôle statique sans
// réseau ni base :
//   * la migration redéfinit chaque fonction depuis son corps LIVE (fixture du
//     banc PG17, générée depuis supabase/schema/public.sql dont les md5 ont
//     été relus en production le 08/11/2026) et n'y change QUE la liste ;
//   * l'instantané public.sql suit exactement les nouveaux corps et le helper ;
//   * les autres listes de types (CDD seul, SALARIE, REMPLACEMENT_LIBERAL,
//     fonctions hors périmètre) ne régressent pas ;
//   * les bancs sont câblés dans validate-pr.
// Aucune empreinte n'est écrite en dur : toutes sont calculées.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import { parse } from 'yaml';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = text => createHash('md5').update(text, 'utf8').digest('hex');
const occurrences = (text, fragment) => text.split(fragment).length - 1;

const MIGRATION = 'supabase/migrations/20261108223500_dpae_contrats_cddu_vacation.sql';
const LIVE = 'tests/security/fixtures/dpae-contrats-cddu-vacation-live.sql';
const BANC = 'tests/security/fixtures/dpae-contrats-cddu-vacation-banc.sql';
const ISOLE = 'tests/security/dpae-contrats-cddu-vacation-isolated.test.sql';
const REJEU = 'tests/security/dpae-contrats-cddu-vacation-rejeu.test.sql';
const STAGING = 'tests/security/dpae-contrats-cddu-vacation.test.sql';
const DERNIERE_VERSION_DISTANTE = '20261102210943';
const TYPES_SALARIES = ['CDD', 'SALARIE', 'CDDU', 'VACATION'];
const HELPER = 'public.fn_type_contrat_salarie(';

const migration = read(MIGRATION);
const live = read(LIVE);
const schema = read('supabase/schema/public.sql');
const workflow = read('.github/workflows/validate-pr.yml');

const FONCTIONS = [
  { nom: 'fn_mes_dpae', ancienne: "cm.type_contrat IN ('CDD', 'CDD', 'SALARIE')", colonne: 'cm.type_contrat' },
  { nom: 'fn_rappel_dpae_quotidien', ancienne: "cm.type_contrat IN ('CDD', 'CDD', 'SALARIE')", colonne: 'cm.type_contrat' },
  { nom: 'fn_pointer_arrivee', ancienne: "v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')", colonne: 'v_contrat.type_contrat' },
  { nom: 'fn_annuler_candidature_soignant', ancienne: "v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')", colonne: 'v_contrat.type_contrat' },
  { nom: 'dec_email_contrat_signe_complet', ancienne: "(NEW.type_contrat IN ('CDD', 'CDD'))", colonne: 'NEW.type_contrat' },
].map(f => ({ ...f, nouvelle: `${HELPER}${f.colonne})` }));

// Corps d'une définition pg_get_functiondef (migration, fixture LIVE).
function corpsDefinition(sql, nom) {
  const ouverture = `CREATE OR REPLACE FUNCTION public.${nom}(`;
  const debut = sql.indexOf(ouverture);
  assert.ok(debut >= 0, `${nom} : définition absente`);
  assert.equal(sql.indexOf(ouverture, debut + 1), -1, `${nom} : définition en double`);
  const tail = sql.slice(debut);
  const tag = /\nAS (\$[A-Za-z_0-9]*\$)/.exec(tail);
  assert.ok(tag, `${nom} : corps dollar-quoted absent`);
  const offset = tag.index + tag[0].length;
  const fin = tail.indexOf(tag[1], offset);
  assert.ok(fin > offset, `${nom} : fin du corps absente`);
  return { entete: tail.slice(0, tag.index), tag: tag[1], corps: tail.slice(offset, fin) };
}

// Corps d'une fonction de l'instantané pg_dump.
function corpsInstantane(sql, nom) {
  const ouverture = `CREATE OR REPLACE FUNCTION "public"."${nom}"(`;
  const debut = sql.indexOf(ouverture);
  assert.ok(debut >= 0, `${nom} : absente de l'instantané`);
  assert.equal(sql.indexOf(ouverture, debut + 1), -1, `${nom} : en double dans l'instantané`);
  const as = sql.indexOf('    AS $$', debut);
  const offset = as + '    AS $$'.length;
  return sql.slice(offset, sql.indexOf('$$;', offset));
}

// Tous les corps de fonctions de l'instantané, par nom (surcharges concaténées).
function corpsTousInstantane(sql) {
  const resultat = new Map();
  for (const m of sql.matchAll(/^CREATE OR REPLACE FUNCTION "([a-z_]+)"\."([a-z_0-9]+)"\(/gm)) {
    const fin = sql.indexOf('\nALTER FUNCTION ', m.index);
    const segment = sql.slice(m.index, fin < 0 ? undefined : fin);
    const as = /\n    AS (\$[A-Za-z_]*\$)/.exec(segment);
    if (!as) continue;
    const offset = as.index + as[0].length;
    const nom = `${m[1]}.${m[2]}`;
    resultat.set(nom, (resultat.get(nom) ?? '') + segment.slice(offset, segment.indexOf(as[1], offset)));
  }
  return resultat;
}

const sansCommentaires = sql => sql.replace(/--[^\n]*/g, '');
// Squelette exécutable hors corps de fonctions (les DO restent visibles).
const squelette = sql => sansCommentaires(sql).replace(/\bAS (\$[A-Za-z_]+\$)[\s\S]*?\1/g, "AS 'corps'");

// PL/pgSQL : un CASE au niveau 0 d'une condition IF/ELSIF voit son THEN clore
// la condition. Renvoie chaque condition fautive (hors littéraux et commentaires).
function casesNonParentheses(sql) {
  const fautes = [];
  const code = sansCommentaires(sql);
  let dansIf = false, profondeur = 0, caseNu = false, debut = 0;
  for (const m of code.matchAll(/'(?:[^']|'')*'|\(|\)|\b(?:ELSIF|IF|THEN|CASE)\b/gi)) {
    const jeton = m[0].toUpperCase();
    if (jeton.startsWith("'")) continue;
    if (!dansIf) {
      if ((jeton === 'IF' || jeton === 'ELSIF') && !/END\s*$/i.test(code.slice(Math.max(0, m.index - 8), m.index))) {
        dansIf = true; profondeur = 0; caseNu = false; debut = m.index;
      }
      continue;
    }
    if (jeton === '(') profondeur += 1;
    else if (jeton === ')') profondeur -= 1;
    else if (jeton === 'CASE' && profondeur === 0) caseNu = true;
    else if (jeton === 'THEN' && profondeur === 0) {
      if (caseNu) fautes.push(code.slice(debut, m.index + 4));
      dansIf = false;
    }
  }
  return fautes;
}

test('une seule migration, horodatage postérieur à la dernière version distante', () => {
  const fichiers = readdirSync(new URL('../../supabase/migrations/', import.meta.url))
    .filter(nom => nom.endsWith('_dpae_contrats_cddu_vacation.sql'));
  assert.deepEqual(fichiers, ['20261108223500_dpae_contrats_cddu_vacation.sql']);
  const version = fichiers[0].slice(0, 14);
  assert.match(version, /^\d{14}$/);
  assert.ok(version > DERNIERE_VERSION_DISTANTE);
});

test('aucune empreinte hexadécimale en dur ni BEGIN/COMMIT nu', () => {
  for (const chemin of [MIGRATION, LIVE, BANC, ISOLE, REJEU, STAGING]) {
    const texte = read(chemin);
    assert.doesNotMatch(texte, /[0-9a-fA-F]{32,}/, `${chemin} : chaîne hexadécimale ≥ 32`);
  }
  // Le wrapper CI supprime ces lignes : aucune ne doit vivre dans un corps.
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK);\s*$/m);
  assert.doesNotMatch(live, /^\s*(BEGIN|COMMIT|ROLLBACK);\s*$/m);
});

for (const f of FONCTIONS) {
  test(`${f.nom} : corps LIVE, seule la liste change, instantané aligné`, () => {
    const avant = corpsDefinition(live, f.nom);
    const apres = corpsDefinition(migration, f.nom);
    // En-tête pg_get_functiondef identique (signature, langage, sécurité, search_path).
    assert.equal(apres.entete, avant.entete);
    assert.match(apres.entete, /\n SECURITY DEFINER|\n STABLE SECURITY DEFINER/);
    // Corps LIVE : l'ancienne liste une fois, aucun type ajouté ni helper.
    assert.equal(occurrences(avant.corps, f.ancienne), 1);
    assert.equal(occurrences(avant.corps, 'fn_type_contrat_salarie'), 0);
    assert.doesNotMatch(avant.corps, /CDDU|VACATION/);
    // Nouveau corps : un seul appel au helper, plus aucune liste héritée.
    assert.equal(occurrences(apres.corps, f.nouvelle), 1);
    assert.equal(occurrences(apres.corps, HELPER), 1);
    assert.equal(occurrences(apres.corps, "IN ('CDD', 'CDD'"), 0);
    // Seule différence : l'expression (même calcul que le postflight SQL).
    assert.notEqual(md5(apres.corps), md5(avant.corps));
    assert.equal(md5(apres.corps.split(f.nouvelle).join(f.ancienne)), md5(avant.corps));
    assert.equal(md5(avant.corps.split(f.ancienne).join(f.nouvelle)), md5(apres.corps));
    // L'instantané porte exactement le nouveau corps.
    assert.equal(md5(corpsInstantane(schema, f.nom)), md5(apres.corps));
  });
}

test('helper : source unique des types salariés, attributs et droits', () => {
  const helper = /CREATE FUNCTION public\.fn_type_contrat_salarie\(p_type_contrat text\)\n RETURNS boolean\n LANGUAGE sql\n IMMUTABLE PARALLEL SAFE\n SET search_path TO ''\nAS (\$[a-z_]+\$)([\s\S]*?)\1;/.exec(migration);
  assert.ok(helper, 'définition du helper absente ou attributs modifiés');
  assert.doesNotMatch(helper[0], /SECURITY DEFINER/);
  const liste = /ARRAY\[([^\]]*)\]::text\[\]/.exec(helper[2]);
  assert.ok(liste);
  assert.deepEqual([...liste[1].matchAll(/'([A-Z_]+)'/g)].map(m => m[1]), TYPES_SALARIES);
  assert.ok(!liste[1].includes('LIBERAL'));
  // Instantané : même corps, même ordre de droits que pg_dump.
  assert.equal(corpsInstantane(schema, 'fn_type_contrat_salarie'), helper[2]);
  assert.match(schema, /CREATE OR REPLACE FUNCTION "public"\."fn_type_contrat_salarie"\("p_type_contrat" "text"\) RETURNS boolean\n    LANGUAGE "sql" IMMUTABLE PARALLEL SAFE\n    SET "search_path" TO ''\n/);
  assert.match(schema, /ALTER FUNCTION "public"\."fn_type_contrat_salarie"\("p_type_contrat" "text"\) OWNER TO "postgres";/);
  assert.match(schema, /COMMENT ON FUNCTION "public"\."fn_type_contrat_salarie"\("p_type_contrat" "text"\) IS 'Source unique SQL/);
  assert.match(schema, /REVOKE ALL ON FUNCTION "public"\."fn_type_contrat_salarie"\("p_type_contrat" "text"\) FROM PUBLIC;\nGRANT ALL ON FUNCTION "public"\."fn_type_contrat_salarie"\("p_type_contrat" "text"\) TO "service_role";\nGRANT ALL ON FUNCTION "public"\."fn_type_contrat_salarie"\("p_type_contrat" "text"\) TO "authenticated";\n/);
  assert.doesNotMatch(schema, /fn_type_contrat_salarie"\("p_type_contrat" "text"\) TO "anon"/);
  // Migration : propriétaire, commentaire, REVOKE PUBLIC/anon, GRANT minimal.
  assert.match(migration, /^ALTER FUNCTION public\.fn_type_contrat_salarie\(text\) OWNER TO postgres;$/m);
  assert.match(migration, /^REVOKE ALL ON FUNCTION public\.fn_type_contrat_salarie\(text\) FROM PUBLIC;$/m);
  assert.match(migration, /^REVOKE ALL ON FUNCTION public\.fn_type_contrat_salarie\(text\) FROM anon;$/m);
  const grants = [...sansCommentaires(migration).matchAll(/^\s*GRANT\b[^;]*;/gm)].map(m => m[0].trim());
  assert.deepEqual(grants, [
    'GRANT EXECUTE ON FUNCTION public.fn_type_contrat_salarie(text) TO authenticated;',
    'GRANT EXECUTE ON FUNCTION public.fn_type_contrat_salarie(text) TO service_role;',
  ]);
  const revokes = [...sansCommentaires(migration).matchAll(/^\s*REVOKE\b[^;]*;/gm)].map(m => m[0].trim());
  assert.ok(revokes.every(r => r.includes('public.fn_type_contrat_salarie(text)')), 'aucun REVOKE sur les cinq fonctions');
});

test('miroir du web : même liste que TYPES_CONTRAT_SALARIES quand elle existe', () => {
  const chemin = new URL('../../src/lib/typesContrat.ts', import.meta.url);
  if (!existsSync(chemin)) return; // branche web fix/dpae-contrats-cddu-vacation pas encore mergée
  const source = readFileSync(chemin, 'utf8');
  const constante = /TYPES_CONTRAT_SALARIES\s*=\s*Object\.freeze\(\[([^\]]*)\]/.exec(source);
  assert.ok(constante, 'TYPES_CONTRAT_SALARIES introuvable');
  assert.deepEqual([...constante[1].matchAll(/'([A-Z_]+)'/g)].map(m => m[1]).sort(), [...TYPES_SALARIES].sort());
});

test('structure de la migration : gardes avant/après, aucune autre écriture', () => {
  const code = sansCommentaires(migration);
  const hors = squelette(migration);
  const preflight = code.indexOf('DO $dpae_salarie_avant$');
  const postflight = code.indexOf('DO $dpae_salarie_apres$');
  const premierCreate = code.search(/\bCREATE (OR REPLACE )?FUNCTION\b/);
  const dernierCreate = Math.max(...[...code.matchAll(/\bCREATE (OR REPLACE )?FUNCTION public\./g)].map(m => m.index));
  assert.ok(preflight >= 0 && preflight < premierCreate, 'le préflight précède toute redéfinition');
  assert.ok(postflight > dernierCreate, 'le postflight suit toutes les redéfinitions');
  assert.equal([...code.matchAll(/\bCREATE (OR REPLACE )?FUNCTION public\./g)].length, 6);
  assert.deepEqual([...code.matchAll(/\bCREATE TEMP TABLE (\w+)/g)].map(m => m[1]), ['_dpae_salarie_avant']);
  assert.match(code, /CREATE TEMP TABLE _dpae_salarie_avant \([\s\S]*?\) ON COMMIT DROP;/);
  // Hors des corps redéfinis : aucune écriture métier ni DDL de table.
  assert.doesNotMatch(hors.replace(/\) ON COMMIT DROP;/, ');'), /\b(DROP|TRUNCATE|DELETE|ALTER TABLE|ADD CONSTRAINT|VALIDATE CONSTRAINT)\b/i);
  assert.deepEqual([...hors.matchAll(/\bUPDATE ([\w.]+)/g)].map(m => m[1]), ['private.security_definer_inventory']);
  assert.deepEqual([...hors.matchAll(/\bINSERT INTO ([\w.]+)/g)].map(m => m[1]), ['_dpae_salarie_avant']);
  assert.equal([...hors.matchAll(/AS 'corps'/g)].length, 6);
  // Garde calculée : md5(nouveau corps ramené à l'ancienne liste) = md5(corps LIVE).
  assert.match(code, /pg_catalog\.md5\(pg_catalog\.replace\(r\.nouveau_prosrc, r\.nouvelle_expression, r\.ancienne_expression\)\)\s+IS DISTINCT FROM pg_catalog\.md5\(r\.ancien_prosrc\)/);
  assert.match(code, /DPAE_SALARIE_PREFLIGHT_HELPER_DEJA_PRESENT/);
  assert.match(code, /DPAE_SALARIE_PREFLIGHT_SOURCE_DRIFT/);
  assert.match(code, /DPAE_SALARIE_POSTFLIGHT_CORPS_OU_ATTRIBUTS/);
  // Les cinq attentes du préflight sont celles du test.
  for (const f of FONCTIONS) {
    assert.ok(code.includes(f.ancienne.replaceAll("'", "''")), `${f.nom} : ancienne expression absente du préflight`);
    assert.ok(code.includes(`'${f.colonne}'`), `${f.nom} : colonne absente du préflight`);
  }
  // Aucun DDL de CHECK, notification ou audit : les valeurs écrites existent déjà.
  assert.doesNotMatch(code, /notifications_type_check|journaux_audit_action_check|externalisation_actions_type_action_check/);
});

test('instantané : plus aucune liste héritée hors périmètre, autres listes intactes', () => {
  const corps = corpsTousInstantane(schema);
  const avecListeHeritee = [...corps].filter(([, c]) => c.includes("'CDD', 'CDD'")).map(([n]) => n).sort();
  // Hors périmètre, listés dans la PR et volontairement non modifiés.
  assert.deepEqual(avecListeHeritee, ['public.fn_calculer_indemnite_annulation_etab', 'public.peut_exercer']);
  assert.ok(corps.get('public.fn_calculer_indemnite_annulation_etab').includes("p_type_contrat IN ('CDD', 'CDD', 'SALARIE')"));
  assert.ok(corps.get('public.peut_exercer').includes("p_type_exercice IN ('SALARIE', 'CDD', 'CDD', 'VACATION')"));
  // Déjà conformes, inchangés.
  assert.ok(corps.get('public.fn_annuler_mission_etab').includes("v_contrat.type_contrat IN ('CDD', 'CDDU', 'VACATION')"));
  assert.ok(corps.get('public.fn_declarer_empechement_imperieux').includes("cm.type_contrat IN ('CDD', 'CDDU', 'VACATION')"));
  assert.ok(corps.get('public.dec_appliquer_plafond_rist').includes("rp.type_contrat IN ('CDD', 'SALARIE', 'VACATION')"));
  // Le helper n'est appelé que par les cinq fonctions corrigées.
  const appelants = [...corps].filter(([, c]) => c.includes(HELPER)).map(([n]) => n).sort();
  assert.deepEqual(appelants, FONCTIONS.map(f => `public.${f.nom}`).sort());
  // CHECK LIVE inchangés : CDDU et VACATION admis, SALARIE non (type de contrat).
  assert.match(schema, /CONSTRAINT "contrats_mission_type_contrat_check" CHECK \(\("type_contrat" = ANY \(ARRAY\['CDDU'::"text", 'VACATION'::"text", 'REMPLACEMENT_LIBERAL'::"text", 'CDD'::"text"\]\)\)\)/);
  assert.match(schema, /'DPAE_ANNULATION'::"text"/);
});

test('bancs : vrais corps LIVE, vraie migration, cas attendus et câblage CI', () => {
  const banc = read(BANC);
  const isole = read(ISOLE);
  const rejeu = read(REJEU);
  const staging = read(STAGING);
  assert.match(banc, /^\\ir dpae-contrats-cddu-vacation-live\.sql$/m);
  for (const t of [isole, rejeu]) {
    assert.match(t, /^\\ir fixtures\/dpae-contrats-cddu-vacation-banc\.sql$/m);
    assert.match(t, /^\\ir \.\.\/\.\.\/supabase\/migrations\/20261108223500_dpae_contrats_cddu_vacation\.sql$/m);
    assert.match(t, /^ROLLBACK;$/m);
  }
  // Cinq fonctions, cas fermés : REMPLACEMENT_LIBERAL jamais déclenché.
  for (const f of FONCTIONS) {
    assert.match(isole, new RegExp(`\\('${f.nom}', \\d, 'REMPLACEMENT_LIBERAL', false, false\\)`));
    assert.match(isole, new RegExp(`\\('${f.nom}', \\d, 'CDD', true, true\\)`));
    assert.match(isole, new RegExp(`\\('${f.nom}', \\d, 'CDDU', false, true\\)`));
    assert.match(isole, new RegExp(`\\('${f.nom}', \\d, 'VACATION', false, true\\)`));
  }
  assert.match(isole, /public\.fn_type_contrat_salarie\('SALARIE'\) IS NOT TRUE/);
  assert.match(staging, /public\.fn_type_contrat_salarie\('SALARIE'\) IS NOT TRUE/);
  assert.match(staging, /RAISE EXCEPTION 'DPAE_SALARIE_ROLLBACK' USING ERRCODE = 'ZX108'/);
  // PL/pgSQL : aucun CASE … THEN non parenthésé dans une condition IF.
  for (const [chemin, t] of [[ISOLE, isole], [REJEU, rejeu], [STAGING, staging], [BANC, banc], [MIGRATION, migration]]) {
    assert.deepEqual(casesNonParentheses(t), [], `${chemin} : CASE non parenthésé dans un IF`);
  }
  // Le détecteur reconnaît bien la faute et la forme parenthésée.
  assert.equal(casesNonParentheses("IF a = CASE WHEN b THEN 1 END THEN x; END IF;").length, 1);
  assert.equal(casesNonParentheses("IF a = (CASE WHEN b THEN 1 END) THEN x; END IF;").length, 0);

  const wf = parse(workflow);
  const steps = Object.values(wf.jobs).flatMap(job => job.steps ?? []);
  const node = steps.find(s => s.run === 'node --test tests/node/dpae-contrats-cddu-vacation.node.mjs');
  assert.ok(node, 'contrôle statique non câblé');
  const pg17 = wf.jobs['paiements-concurrence'].steps.find(s => (s.run ?? '').includes(ISOLE));
  assert.ok(pg17, 'banc PG17 non câblé');
  assert.equal(pg17.env.PGOPTIONS, '-c jolene.isolated_sql_test=on');
  assert.match(pg17.run, /createdb dpae_salarie\n/);
  assert.match(pg17.run, /for scenario in rejeu rejeu_sans_helper corps_derive; do/);
  assert.match(pg17.run, /DPAE_SALARIE_PREFLIGHT_HELPER_DEJA_PRESENT/);
  assert.match(pg17.run, /DPAE_SALARIE_PREFLIGHT_SOURCE_DRIFT: fn_mes_dpae\(\)/);
  assert.match(pg17.run, /DPAE_SALARIE_POSTFLIGHT_CORPS_OU_ATTRIBUTS: fn_rappel_dpae_quotidien\(\)/);
  assert.match(pg17.run, /-f tests\/security\/dpae-contrats-cddu-vacation-rejeu\.test\.sql/);
  const rollback = wf.jobs['sql-transaction'].steps
    .find(s => s.name === 'Exécuter les migrations ajoutées et les régressions SQL sans persister');
  assert.match(rollback.run, /^\s+tests\/security\/dpae-contrats-cddu-vacation\.test\.sql$/m);
  // La suite staging qui épingle dec_email_contrat_signe_complet accepte ce seul successeur.
  const canvas = read('tests/security/signature-canvas-controles.test.sql');
  assert.ok(canvas.includes("corps:=replace(corps,'public.fn_type_contrat_salarie(NEW.type_contrat)','(NEW.type_contrat IN (''CDD'', ''CDD''))');"));
});

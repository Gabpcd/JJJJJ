// Prospection sans MSSanté (20261116143942, B9) — contrôle hors réseau.
// Ne remplace pas la suite SQL (tests/security/agents-croissance-brouillons.test.sql,
// exécutée sur le staging sous ROLLBACK) ; verrouille ce qu'elle ne peut pas voir :
//   * les empreintes du préflight sont bien celles des corps de 20261109140000
//     (md5 du texte entre les deux délimiteurs $body$, comme pg_proc.prosrc) ;
//   * les deux corps redéfinis sont ceux d'origine plus des lignes ajoutées,
//     sans aucune ligne modifiée ni retirée, en-têtes identiques ;
//   * une seule définition de la règle MSSanté, une seule source d'expiration,
//     appelée par la migration et par la suite SQL ;
//   * aucun SECURITY DEFINER (rien à inventorier), câblage CI présent.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261116143942_prospection_sans_mssante.sql';
const ORIGINE = '20261109140000_agents_croissance_brouillons.sql';
const SUITE = 'tests/security/agents-croissance-brouillons.test.sql';
const migration = read(`supabase/migrations/${MIGRATION}`);
const origine = read(`supabase/migrations/${ORIGINE}`);
const suite = read(SUITE);
const workflow = read('.github/workflows/validate-pr.yml');

const EMPREINTES = {
  'private.fn_growth_agent_prospection': 'f7fe0ee536b4e2bcf737c10194744b06',
  'private.fn_growth_destinataire_bloque': '0e27c9a65a314a4b70af2c0df4923031',
};

function definition(sql, nom) {
  const marqueur = `CREATE OR REPLACE FUNCTION ${nom}(`;
  const debut = sql.indexOf(marqueur);
  assert.ok(debut >= 0, `${nom} : définition absente`);
  assert.equal(sql.indexOf(marqueur, debut + 1), -1, `${nom} : définie deux fois`);
  const suite = sql.slice(debut);
  const ouverture = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/.exec(suite);
  assert.ok(ouverture, `${nom} : corps dollar-quoted absent`);
  const corpsDebut = ouverture.index + ouverture[0].length;
  const corpsFin = suite.indexOf(ouverture[1], corpsDebut);
  assert.ok(corpsFin > corpsDebut, `${nom} : fin du corps absente`);
  return { entete: suite.slice(0, ouverture.index), corps: suite.slice(corpsDebut, corpsFin) };
}

// Lignes du nouveau corps absentes de l'ancien, dans l'ordre (sous-suite) :
// échoue si une ligne d'origine manque ou a changé.
function lignesAjoutees(avant, apres) {
  const a = avant.split('\n');
  const ajoutees = [];
  let i = 0;
  for (const ligne of apres.split('\n')) {
    if (i < a.length && ligne === a[i]) i += 1;
    else ajoutees.push(ligne);
  }
  assert.equal(i, a.length, `ligne d'origine absente ou modifiée : ${JSON.stringify(a[i])}`);
  return ajoutees;
}

const sansCommentaires = sql => sql.replace(/--[^\n]*/g, '');

// Dernière version du registre de production au 16/11/2026 (description de la PR).
const DERNIERE_VERSION_DISTANTE = '20261109140000';

test('une seule migration, horodatée après le registre distant, sans transaction interne ni $$', () => {
  const noms = readdirSync(new URL('../../supabase/migrations/', import.meta.url)).filter(n => n.endsWith('.sql')).sort();
  assert.equal(noms.filter(n => n.endsWith('_prospection_sans_mssante.sql')).length, 1);
  assert.match(MIGRATION, /^\d{14}_/);
  assert.ok(MIGRATION.slice(0, 14) > DERNIERE_VERSION_DISTANTE);
  assert.doesNotMatch(migration, /^\s*(BEGIN|COMMIT|ROLLBACK);\s*$/m);
  assert.doesNotMatch(migration, /\$\$/);
  assert.doesNotMatch(migration, /\r/);
});

for (const [nom, empreinte] of Object.entries(EMPREINTES)) {
  test(`préflight : empreinte de ${nom} = corps de ${ORIGINE}`, () => {
    const { corps } = definition(origine, nom);
    assert.equal(md5(corps), empreinte);
    assert.notEqual(md5(`${corps} `), empreinte, 'une dérive blanche change l\'empreinte');
    const signature = nom === 'private.fn_growth_agent_prospection'
      ? 'private.fn_growth_agent_prospection()'
      : 'private.fn_growth_destinataire_bloque(text,text,text,text,text)';
    const bloc = migration.slice(migration.indexOf(`to_regprocedure('${signature}')`));
    assert.ok(bloc.length < migration.length, `${signature} : préflight absent`);
    const verif = bloc.slice(0, bloc.indexOf('END IF;'));
    assert.match(verif, new RegExp(`md5\\(p\\.prosrc\\) <> '${empreinte}'`));
    assert.match(verif, /p\.prosecdef IS DISTINCT FROM false/);
    assert.match(verif, /p\.proconfig IS DISTINCT FROM ARRAY\['search_path=""'\]::text\[\]/);
    assert.match(verif, /RAISE EXCEPTION '[^']*CLAUDE\.md, garde-fous 9\.0 n°2/);
  });
}

test('le préflight précède toute écriture et refuse aussi un homonyme des fonctions neuves', () => {
  const finPreflight = migration.indexOf('$prospection_sans_mssante_avant$;');
  assert.ok(finPreflight > 0);
  const premiereEcriture = sansCommentaires(migration).search(/\b(CREATE|REVOKE|UPDATE|INSERT|DELETE)\b/);
  assert.ok(sansCommentaires(migration).indexOf('$prospection_sans_mssante_avant$;') < premiereEcriture);
  for (const sig of ['private.fn_growth_email_mssante(text)', 'private.fn_growth_motif_expiration_mssante()',
    'private.fn_growth_expirer_brouillons_mssante()']) {
    assert.ok(migration.slice(0, finPreflight).includes(`to_regprocedure('${sig}') IS NOT NULL`), sig);
  }
});

test('fn_growth_destinataire_bloque : corps d\'origine + motif MSSANTE, en-tête identique', () => {
  const avant = definition(origine, 'private.fn_growth_destinataire_bloque');
  const apres = definition(migration, 'private.fn_growth_destinataire_bloque');
  assert.equal(apres.entete, avant.entete);
  const bloc4 = ['    -- MSSanté (20261116143942) : messagerie fermée, un envoi depuis Gmail est rejeté.',
    '    IF private.fn_growth_email_mssante(p_email) THEN', "      RETURN 'MSSANTE';", '    END IF;'];
  const bloc2 = bloc4.map(l => l.slice(2));
  assert.deepEqual(lignesAjoutees(avant.corps, apres.corps), [...bloc4, ...bloc4, ...bloc2]);
  // Les motifs existants gardent la priorité : chaque ajout suit le contrôle STOP.
  const lignes = apres.corps.split('\n');
  const positions = lignes.flatMap((l, i) => l.includes("RETURN 'MSSANTE'") ? [i] : []);
  assert.equal(positions.length, 3);
  assert.ok(positions[0] > lignes.findIndex(l => l.includes("RETURN 'STOP'")));
  assert.ok(positions[1] > lignes.findLastIndex(l => l.includes("RETURN 'STOP'")));
});

test('fn_growth_agent_prospection : corps d\'origine + exclusions MSSanté et quota, en-tête identique', () => {
  const avant = definition(origine, 'private.fn_growth_agent_prospection');
  const apres = definition(migration, 'private.fn_growth_agent_prospection');
  assert.equal(apres.entete, avant.entete);
  assert.deepEqual(lignesAjoutees(avant.corps, apres.corps), [
    '    -- Un brouillon expiré par la correction MSSanté (20261116143942) ne consomme pas le quota du jour.',
    "    AND NOT (b.statut = 'EXPIRE' AND b.motif_rejet IS NOT DISTINCT FROM private.fn_growth_motif_expiration_mssante())",
    '        -- MSSanté : espace de confiance fermé, un envoi depuis Gmail est rejeté.',
    '        AND NOT private.fn_growth_email_mssante(p.email)',
    '      -- MSSanté : une relance y serait rejetée comme le premier email.',
    '      AND NOT private.fn_growth_email_mssante(sc.email)',
  ]);
  // Postflight hors base : empreinte du nouveau corps, pour relecture LIVE après déploiement.
  assert.match(md5(apres.corps), /^[0-9a-f]{32}$/);
});

test('une seule définition de la règle MSSanté, utilisée partout', () => {
  const code = sansCommentaires(migration);
  assert.equal(code.match(/mssante\\\.fr/g)?.length, 1, 'littéral de la règle recopié');
  const { corps, entete } = definition(migration, 'private.fn_growth_email_mssante');
  assert.match(entete, /RETURNS boolean\s+LANGUAGE sql\s+IMMUTABLE\s+SET search_path TO ''/);
  assert.equal(corps.trim(), "SELECT COALESCE(lower(btrim(p_email, E' \\t\\r\\n')) ~ '[@.]mssante\\.fr$', false);");
  // Appels : prédicat (3), agent (2), expiration (1) ; aucun autre usage.
  const appels = [...code.matchAll(/private\.fn_growth_email_mssante\(([^)]*)\)/g)].map(m => m[1]);
  assert.deepEqual(appels.filter(a => !/^(p_email text|text)$/.test(a)),
    ['p_email', 'p_email', 'p_email', 'p.email', 'sc.email', 'b.destinataire_email']);
  assert.doesNotMatch(sansCommentaires(suite), /mssante\\\.fr/, 'la suite SQL recopie la règle');
  for (const sig of ['fn_growth_email_mssante(text)', 'fn_growth_motif_expiration_mssante()',
    'fn_growth_expirer_brouillons_mssante()']) {
    assert.ok(migration.includes(`REVOKE ALL ON FUNCTION private.${sig} FROM PUBLIC, anon, authenticated;`), sig);
  }
});

test('une seule source d\'expiration : BROUILLON et VALIDE, clé libérée comme l\'orchestrateur', () => {
  const { corps } = definition(migration, 'private.fn_growth_expirer_brouillons_mssante');
  assert.match(corps, /AND b\.statut IN \('BROUILLON', 'VALIDE'\)/);
  assert.match(corps, /AND private\.fn_growth_email_mssante\(b\.destinataire_email\)/);
  assert.match(corps, /motif_rejet = private\.fn_growth_motif_expiration_mssante\(\)/);
  const cas = texte => /idempotence_key = (CASE WHEN [\s\S]*? END)/.exec(texte)[1].replace(/\bb\./g, '').replace(/\s+/g, ' ');
  const orchestrateur = definition(origine, 'private.fn_growth_agents_executer').corps;
  assert.equal(cas(corps), cas(orchestrateur));
  // La migration l'exécute une fois, après sa définition ; la suite SQL aussi,
  // sans copie de l'UPDATE.
  const code = sansCommentaires(migration);
  const appels = [...code.matchAll(/private\.fn_growth_expirer_brouillons_mssante\(\);/g)];
  assert.equal(appels.length, 1);
  assert.ok(appels[0].index > code.indexOf('CREATE OR REPLACE FUNCTION private.fn_growth_expirer_brouillons_mssante()'));
  assert.match(suite, /v_n := private\.fn_growth_expirer_brouillons_mssante\(\);/);
  assert.doesNotMatch(suite, /UPDATE public\.growth_brouillons[^;]*motif_rejet/);
  assert.doesNotMatch(code, /\bDELETE\b/);
});

test('la suite SQL couvre les faux amis, le VALIDE expiré, le quota et la revalidation', () => {
  for (const attendu of ['@mssante.fr.exemple.com', '@pasmssante.fr', '@recette-pasmssante.fr',
    "cible_id = 'ZZGROW032' AND statut = 'EXPIRE'", 'v_places_avant + 2',
    "fn_admin_growth_brouillon_decider(v_id_mss, 'VALIDER')",
    "fn_admin_growth_brouillon_decider(v_id_mss_valide, 'MARQUER_ENVOYE')"]) {
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
  assert.match(workflow, /run: node --test tests\/node\/prospection-sans-mssante\.node\.mjs/);
  assert.match(workflow, new RegExp(`^\\s+${SUITE.replace(/[.]/g, '\\.')}$`, 'm'));
});

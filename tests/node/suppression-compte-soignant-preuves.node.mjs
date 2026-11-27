// Suppression du compte soignant avec pièces vérifiées (20261127100000), contrôle hors réseau.
// Ne remplace ni la suite SQL du staging (tests/security/suppression-compte-soignant-preuves.test.sql, ROLLBACK) ni
// le banc PostgreSQL 17 / PGlite (tests/postgres/suppression-compte-soignant-preuves.pg17.mjs) ; verrouille :
//   * la forme de la migration (horodatage, aucun BEGIN/COMMIT, délimiteurs nommés, préflight, post-condition) ;
//   * le corps installé = corps LIVE (20260713223000, md5 121864ac…) où seul l'UPDATE des pièces passe sous la
//     condition « pas une suppression » ; le nettoyage du profil (noms des registres, spécialité, cohérence) reste ;
//   * aucune autre fonction redéfinie, aucun droit modifié : les protections restent celles du LIVE ;
//   * le chemin réel de suppression (edge delete-account → fn_supprimer_compte_rate_limited → fn_supprimer_mon_compte) ;
//   * le câblage CI : suite dans SQL_TESTS, banc PG17, ce contrôle.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const RACINE = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(join(RACINE, path), 'utf8');
const md5 = body => createHash('md5').update(body, 'utf8').digest('hex');

const MIGRATION = '20261127100000_suppression_compte_soignant_sans_revalidation.sql';
const PRECEDENTE = '20261126100100'; // dernière version connue avant celle-ci (missions de revue, #1198)
const sql = read(`supabase/migrations/${MIGRATION}`);
const suite = read('tests/security/suppression-compte-soignant-preuves.test.sql');
const banc = read('tests/postgres/suppression-compte-soignant-preuves.pg17.mjs');
const workflow = read('.github/workflows/validate-pr.yml');

const LIVE = '121864acbb7a1bd4c800de32eaa75292';
const NOUVEAU = 'bb93c49d6187ee007b964acab6bf0809';
const PROTECTIONS = {
  'public.fn_proteger_ecriture_document_soignant()': 'c490ce823768b0a23cd264ab17601155',
  'public.fn_protect_soignant_verification()': 'ff5e753f785f2c7ca08ae22771812e95',
  'public.fn_supprimer_mon_compte()': 'f3af23aeeb4e30aba07e422c0e819aeb',
  'public.fn_supprimer_compte_rate_limited()': 'f283e828e173bf12d8f633be28431c97',
};
const CONDITION = `    -- Suppression du compte (supprime_le posé dans cette même mise à jour) : les
    -- pièces ne sont pas repassées en attente, elles n'ont plus d'objet à
    -- re-vérifier et la suppression les marque elle-même supprimées. Le
    -- nettoyage du profil ci-dessous (noms RPPS et ADELI, spécialité,
    -- cohérence, drapeaux de vérification) reste dû. Transition réservée aux
    -- fonctions serveur : fn_protect_soignant_verification rétablit
    -- supprime_le pour toute écriture d'un utilisateur (migration 20261127100000).
    IF NOT (OLD.supprime_le IS NULL AND NEW.supprime_le IS NOT NULL) THEN
`;
const DEBUT_PIECES = '    UPDATE public.documents_soignants\n';
const FIN_PIECES = '    GET DIAGNOSTICS v_documents_invalides = ROW_COUNT;\n';

/** Corps (texte entre délimiteurs, comme pg_proc.prosrc) de la première définition de `nom` dans `texte`. */
function corps(texte, nom) {
  const i = texte.indexOf(`CREATE OR REPLACE FUNCTION public.${nom}(`);
  assert.ok(i >= 0, `${nom} : définition absente`);
  const tail = texte.slice(i);
  const ouverture = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/.exec(tail);
  const debut = ouverture.index + ouverture[0].length;
  return tail.slice(debut, tail.indexOf(ouverture[1], debut));
}

test('migration : horodatage, transaction possédée par l’appelant, délimiteurs nommés', () => {
  const versions = readdirSync(join(RACINE, 'supabase/migrations')).filter(f => f.endsWith('.sql')).sort();
  assert.match(MIGRATION, /^\d{14}_[a-z0-9_]+\.sql$/);
  assert.ok(MIGRATION.slice(0, 14) > PRECEDENTE, 'la migration suit la dernière version connue');
  assert.ok(versions.includes(MIGRATION));
  assert.doesNotMatch(sql, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im, 'aucun BEGIN/COMMIT interne');
  assert.doesNotMatch(sql, /\$\$/, 'délimiteurs de dollar nommés seulement');
  assert.match(sql, /SET LOCAL lock_timeout = '5s';/);
  assert.match(sql, /B9 \(suppression de données personnelles\) : go écrits de Gabrielle du 24\/11\/2026 et du 26\/11\/2026\./);
});

test('redéfinition : corps LIVE + le seul bloc de coupure, préflight et post-condition', () => {
  const live = corps(read('supabase/migrations/20260713223000_durcir_identite_soignant_documents.sql'),
    'fn_invalider_preuves_identite_sur_changement');
  assert.equal(md5(live), LIVE, 'corps LIVE de référence');
  const installe = corps(sql, 'fn_invalider_preuves_identite_sur_changement');
  assert.equal(md5(installe), NOUVEAU, 'empreinte du corps installé');
  // Attendu : le LIVE où seul le bloc de l'UPDATE des pièces (UPDATE … GET DIAGNOSTICS) est réindenté sous la condition.
  const d = live.indexOf(DEBUT_PIECES);
  const f = live.indexOf(FIN_PIECES) + FIN_PIECES.length;
  assert.ok(d > 0 && f > d && live.indexOf(DEBUT_PIECES, d + 1) < 0, 'bloc des pièces unique dans le LIVE');
  const pieces = live.slice(d, f);
  const attendu = live.slice(0, d) + CONDITION + pieces.split('\n').map(l => (l ? `  ${l}` : l)).join('\n') + '    END IF;\n' + live.slice(f);
  assert.equal(installe, attendu, 'seul l’UPDATE des pièces diffère du LIVE, sous la condition');
  // Le nettoyage du profil (second UPDATE, audit) n'est pas sous la condition et suit le bloc des pièces.
  const nettoyage = installe.indexOf('    UPDATE public.soignants\n    SET identite_verifiee = false,');
  assert.ok(nettoyage > installe.indexOf('    END IF;\n', installe.indexOf(CONDITION)), 'nettoyage du profil hors de la condition');
  for (const colonne of ['rpps_nom_api', 'rpps_prenom_api', 'adeli_nom_api', 'adeli_prenom_api', 'specialite_code', 'coherence_details']) {
    assert.ok(installe.slice(nettoyage).includes(colonne), `nettoyage du profil : ${colonne}`);
  }
  assert.doesNotMatch(installe, /supprime_le IS NOT NULL THEN\s+RETURN NEW;/, 'aucun retour anticipé avant le nettoyage');
  assert.ok(sql.includes(`'public.fn_invalider_preuves_identite_sur_changement()', '${LIVE}'`), 'préflight sur l’empreinte LIVE');
  assert.ok(sql.includes(`IS DISTINCT FROM '${NOUVEAU}'`), 'post-condition sur le nouveau corps');
  for (const [signature, empreinte] of Object.entries(PROTECTIONS)) {
    assert.ok(sql.includes(`('${signature}', '${empreinte}'`), `${signature} : verrou LIVE au préflight`);
  }
  assert.ok(suite.includes(`IS DISTINCT FROM '${NOUVEAU}'`), 'la suite vérifie le corps installé');
});

test('périmètre : une seule fonction redéfinie, aucun droit ni déclencheur modifié', () => {
  assert.deepEqual([...sql.matchAll(/CREATE OR REPLACE FUNCTION ([a-z_.]+)\(/g)].map(m => m[1]),
    ['public.fn_invalider_preuves_identite_sur_changement']);
  // Hors du corps redéfini (qui reprend le LIVE), aucune autre instruction d'écriture ou de droits.
  const code = sql.replace(/--[^\n]*/g, '')
    .replace(/\$fn_invalider_preuves_identite_sur_changement\$[\s\S]*?\$fn_invalider_preuves_identite_sur_changement\$/, "'corps'");
  assert.doesNotMatch(code,/\b(GRANT|REVOKE|DROP|TRUNCATE|DELETE|ALTER|CREATE\s+TRIGGER|CREATE\s+POLICY|INSERT|UPDATE\s+public\.)\b/i);
  assert.ok(!/fn_proteger_ecriture_document_soignant\(\)\s*\nRETURNS/.test(sql), 'protection des preuves non redéfinie');
});

test('chemin réel : edge delete-account → fn_supprimer_compte_rate_limited → fn_supprimer_mon_compte', () => {
  const edge = read('supabase/functions/delete-account/index.ts');
  assert.match(edge, /userClient\.rpc\('fn_supprimer_compte_rate_limited'\)/, 'session utilisateur, pas le rôle de service');
  const schema = read('supabase/schema/public.sql');
  const rateLimited = schema.slice(schema.indexOf('CREATE OR REPLACE FUNCTION "public"."fn_supprimer_compte_rate_limited"()'));
  assert.match(rateLimited.slice(0, 1200), /RETURN public\.fn_supprimer_mon_compte\(\);/);
  assert.ok(banc.includes('SELECT public.fn_supprimer_compte_rate_limited() AS resultat;'), 'le banc reproduit le constat par ce chemin');
  assert.ok(suite.includes('v_res := public.fn_supprimer_compte_rate_limited();'), 'la suite supprime par ce chemin');
});

test('suite SQL et câblage CI', () => {
  assert.match(suite, /^(--[^\n]*\n)+BEGIN;\n/);
  assert.match(suite, /\nROLLBACK;\n$/);
  assert.doesNotMatch(suite, /^\s*COMMIT\s*;/im);
  for (const garde of ["'SUPPRESSION_PREUVES A1 : ", "'SUPPRESSION_PREUVES A6 : ", "'SUPPRESSION_PREUVES B1 : ", "'SUPPRESSION_PREUVES C1 : ",
    "'SUPPRESSION_PREUVES D1 : ", "'SUPPRESSION_PREUVES D2 : "]) {
    assert.ok(suite.includes(garde), `suite : ${garde}`);
  }
  const run = workflow.split('name: Exécuter les migrations ajoutées et les régressions SQL sans persister')[1];
  assert.match(run, /^\s+tests\/security\/suppression-compte-soignant-preuves\.test\.sql$/m, 'suite dans SQL_TESTS');
  assert.ok(workflow.includes("psql -X -v ON_ERROR_STOP=1 -c 'CREATE DATABASE suppression_preuves_banc'"));
  assert.ok(workflow.includes('PGDATABASE=suppression_preuves_banc node --test tests/postgres/suppression-compte-soignant-preuves.pg17.mjs'));
  assert.ok(workflow.includes('node --test tests/node/suppression-compte-soignant-preuves.node.mjs'));
  assert.ok(banc.includes(`export const MIGRATION = 'supabase/migrations/${MIGRATION}';`));
  assert.ok(banc.includes("export const SUITE = 'tests/security/suppression-compte-soignant-preuves.test.sql';"));
});

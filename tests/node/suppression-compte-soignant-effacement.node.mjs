// Garde statique, sans réseau, des migrations 20261128140000 (CHECK du journal d'audit) et 20261128140100 (effacement
// des fichiers et des noms lus par l'IA à la suppression du compte soignant). Ne remplace ni la suite SQL du staging
// (tests/security/suppression-compte-soignant-effacement.test.sql, ROLLBACK) ni le banc PostgreSQL 17 / PGlite
// (tests/postgres/suppression-compte-soignant-effacement.pg17.mjs) ; verrouille :
//   * la contrainte : liste LIVE (empreinte relue en production) + trois actions, dans le même ordre ;
//   * fn_supprimer_mon_compte : corps LIVE + trois ajouts exactement, aucun appel réseau dans la suppression ;
//   * chaque corps installé correspond à l'empreinte de post-condition, citée aussi par la suite ;
//   * aucune suppression SQL de storage.objects (API Storage seulement), buckets conservés jamais purgés ;
//   * purge des inactifs verrouillée, cron, inventaire, droits, câblage CI, décision documentée.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { RACINE } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';

const read = chemin => readFileSync(join(RACINE, chemin), 'utf8');
const md5 = texte => createHash('md5').update(texte, 'utf8').digest('hex');

const M1 = '20261128140000_audit_actions_identite_et_suppression.sql';
const M2 = '20261128140100_suppression_compte_soignant_effacement_pieces.sql';
const PRECEDENTE = '20261127100000';
const sql1 = read(`supabase/migrations/${M1}`);
const sql2 = read(`supabase/migrations/${M2}`);
const suite = read('tests/security/suppression-compte-soignant-effacement.test.sql');
const banc = read('tests/postgres/suppression-compte-soignant-effacement.pg17.mjs');
const workflow = read('.github/workflows/validate-pr.yml');

const LIVE_SUPPRESSION = 'f3af23aeeb4e30aba07e422c0e819aeb';
const NOUVELLE_SUPPRESSION = 'bd8df04463ed3b683de237d78b6ecea3';
const CHECK_LIVE = '5d8ca35986765f1530b47d63b9f8f432';
const CHECK_NOUVEAU = 'd34d197dbf9da68e8ba340e0824ce765';
const ACTIONS_AJOUTEES = ['IDENTITE_PROFIL_MODIFIEE', 'RGPD_SUPPRESSION_COMPTE_MEMBRE_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ADMIN_GROUPE'];

/** Les trois ajouts au corps LIVE de fn_supprimer_mon_compte, rien d'autre. */
const AJOUTS = [
  ["    v_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');\n",
    "    v_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');\n    v_effacement jsonb;\n"],
  ['    UPDATE documents_soignants SET supprime_le = NOW() WHERE soignant_id = v_uid;\n',
    "    -- Pièces (migration 20261128140100) : fichiers mis en file d'effacement,\n    -- contenu lu par l'IA et champs dérivés effacés, attestations d'heures\n"
    + "    -- externes supprimées, revues anonymisées. Lève si un résidu subsiste.\n"
    + "    v_effacement := private.fn_rgpd_effacer_pieces_soignant(v_uid, 'SUPPRESSION_COMPTE');\n"],
  ["            'messages_litige'],\n            'tables_financieres_conservees', ARRAY['stripe_transfers','paiements_soignant']));\n",
    "            'messages_litige','heures_externes_soignants','file_revue_manuelle'],\n            'pieces', v_effacement,\n"
    + "            'tables_financieres_conservees', ARRAY['stripe_transfers','paiements_soignant']));\n"],
];

/** Corps (texte entre délimiteurs, comme pg_proc.prosrc) de la définition de `schema.nom` dans `texte`. */
function corps(texte, schema, nom) {
  const i = texte.indexOf(`CREATE OR REPLACE FUNCTION ${schema}.${nom}(`);
  assert.ok(i >= 0, `${schema}.${nom} : définition absente`);
  const tail = texte.slice(i);
  const ouverture = /\bAS\s+(\$[a-zA-Z_0-9]*\$)/.exec(tail);
  const debut = ouverture.index + ouverture[0].length;
  return tail.slice(debut, tail.indexOf(ouverture[1], debut));
}

test('migrations : horodatage, transaction possédée par l’appelant, délimiteurs nommés, B9 cité', () => {
  const versions = readdirSync(join(RACINE, 'supabase/migrations')).filter(f => f.endsWith('.sql')).sort();
  for (const [fichier, texte] of [[M1, sql1], [M2, sql2]]) {
    assert.ok(versions.includes(fichier));
    assert.ok(fichier.slice(0, 14) > PRECEDENTE, 'la migration suit la dernière version connue');
    assert.doesNotMatch(texte, /^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im, 'aucun BEGIN/COMMIT interne');
    assert.doesNotMatch(texte, /\$\$/, 'délimiteurs de dollar nommés seulement');
    assert.match(texte, /SET LOCAL lock_timeout = '5s';/);
  }
  assert.ok(M1 < M2, 'le CHECK précède l’effacement (l’audit d’identité de la suppression doit passer)');
  assert.match(sql2, /B9 \(suppression de données personnelles, SECURITY DEFINER\) : go écrit de Gabrielle du 24\/11\/2026\./);
});

test('CHECK du journal : liste LIVE + trois actions, empreintes avant et après', () => {
  const liste = /ADD CONSTRAINT journaux_audit_action_check CHECK \(\(action = ANY \(ARRAY\[\n([\s\S]*?)\n\]\)\)\);/.exec(sql1);
  assert.ok(liste, 'ajout de contrainte explicite');
  const actions = [...liste[1].matchAll(/'([A-Z0-9_]+)'::text/g)].map(m => m[1]);
  assert.equal(actions.length, 163);
  assert.equal(new Set(actions).size, 163, 'aucune action en double');
  assert.deepEqual(actions.slice(-3), ACTIONS_AJOUTEES);
  const def = valeurs => `CHECK ((action = ANY (ARRAY[${valeurs.map(a => `'${a}'::text`).join(', ')}])))`;
  assert.equal(md5(def(actions.slice(0, -3))), CHECK_LIVE, 'les 160 premières actions sont la contrainte LIVE, dans le même ordre');
  assert.equal(md5(def(actions)), CHECK_NOUVEAU);
  assert.ok(sql1.includes(`IS DISTINCT FROM '${CHECK_LIVE}'`), 'préflight sur la contrainte LIVE');
  assert.ok(sql1.includes(`IS DISTINCT FROM '${CHECK_NOUVEAU}'`), 'post-condition sur la contrainte installée');
  assert.match(sql1, /c\.convalidated/, 'contrainte validée sur toutes les lignes');
  assert.doesNotMatch(sql1.replace(/--[^\n]*/g, ''), /\b(INSERT|UPDATE|DELETE|TRUNCATE)\b/i, 'journal immuable : aucune ligne touchée');
  // Écrivains réels des trois actions.
  assert.match(read('supabase/schema/public.sql'), /p_action := 'IDENTITE_PROFIL_MODIFIEE'/);
  const edge = read('supabase/functions/delete-account/index.ts');
  for (const action of ACTIONS_AJOUTEES.slice(1)) assert.ok(edge.includes(`action: '${action}'`), `écrivain edge : ${action}`);
  assert.ok(suite.includes(`IS DISTINCT FROM '${CHECK_NOUVEAU}'`), 'la suite vérifie la contrainte installée');
});

test('fn_supprimer_mon_compte : corps LIVE + trois ajouts exactement, aucun appel réseau', () => {
  const live = corps(read('supabase/migrations/20261001131013_conserver_historique_financier_suppression_soignant.sql'),
    'public', 'fn_supprimer_mon_compte');
  assert.equal(md5(live), LIVE_SUPPRESSION, 'corps LIVE de référence');
  let attendu = live;
  for (const [avant, apres] of AJOUTS) {
    assert.equal(attendu.split(avant).length - 1, 1, `fragment LIVE unique : ${avant.slice(0, 60)}`);
    attendu = attendu.replace(avant, () => apres);
  }
  const installe = corps(sql2, 'public', 'fn_supprimer_mon_compte');
  assert.equal(installe, attendu, 'seuls les trois ajouts diffèrent du LIVE');
  assert.equal(md5(installe), NOUVELLE_SUPPRESSION);
  assert.doesNotMatch(installe, /net\.|http_post|fn_lancer_purge/, 'aucun appel réseau dans la suppression');
  assert.ok(sql2.includes(`('public.fn_supprimer_mon_compte()', '${LIVE_SUPPRESSION}', 'search_path=public, extensions', true)`));
  assert.match(sql2, /CREATE OR REPLACE FUNCTION public\.fn_supprimer_mon_compte\(\)\nRETURNS jsonb\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path TO 'public', 'extensions'\n/);
});

test('post-condition : chaque corps installé a l’empreinte citée, reprise par la suite et le banc', () => {
  const bloc = sql2.split('DO $effacement_pieces_apres$')[1];
  const lignes = [...bloc.matchAll(/\('((?:public|private)\.([a-z_]+)\([^)]*\))', '([0-9a-f]{32})', (true|false)\)/g)];
  assert.equal(lignes.length, 8);
  for (const [, , nom, empreinte, definer] of lignes) {
    const schema = sql2.includes(`CREATE OR REPLACE FUNCTION private.${nom}(`) ? 'private' : 'public';
    assert.equal(md5(corps(sql2, schema, nom)), empreinte, `${schema}.${nom} : empreinte de post-condition`);
    const entete = sql2.slice(sql2.indexOf(`CREATE OR REPLACE FUNCTION ${schema}.${nom}(`)).split(/\nAS \$/)[0];
    assert.equal(/\nSECURITY DEFINER\n/.test(entete), definer === 'true', `${nom} : SECURITY DEFINER`);
  }
  for (const nom of ['fn_supprimer_mon_compte', 'fn_rgpd_effacer_pieces_soignant', 'fn_rgpd_purges_stockage_confirmer',
    'fn_rgpd_purges_stockage_reserver']) {
    const empreinte = lignes.find(l => l[2] === nom)[3];
    assert.ok(suite.includes(`IS DISTINCT FROM '${empreinte}'`), `la suite vérifie ${nom}`);
  }
  assert.ok(banc.includes(`apres: '${NOUVELLE_SUPPRESSION}'`), 'le banc connaît le corps APRÈS');
  assert.ok(read('tests/security/suppression-compte-soignant-preuves.test.sql')
    .includes(`NOT IN ('${LIVE_SUPPRESSION}', '${NOUVELLE_SUPPRESSION}')`), 'suite #1200 : corps LIVE ou successeur seulement');
});

test('effacement : contenu lu, noms de fichier et attestations effacés, post-condition fail-closed', () => {
  const effacer = corps(sql2, 'private', 'fn_rgpd_effacer_pieces_soignant');
  const miseAJour = effacer.slice(effacer.indexOf('UPDATE public.documents_soignants d'), effacer.indexOf('GET DIAGNOSTICS v_pieces'));
  for (const colonne of ['resultat_ia', 'nom_extrait_ia', 'prenom_extrait_ia', 'coherence_nom', 'score_confiance_ia',
    'motif_rejet', 'libelle', 's3_version_id', 'verification_attempt_id']) {
    assert.match(miseAJour, new RegExp(`\\n\\s+${colonne} = NULL`), `${colonne} effacé`);
  }
  assert.match(miseAJour, /nom_fichier = 'fichier-efface'/);
  assert.doesNotMatch(miseAJour, /revoque_raison/, 'raison de révocation (REMPLACEMENT ou RETRAIT) conservée : CHECK de cohérence');
  // Chemins référencés : même classement que le préfixe, jamais hors du préfixe ni d’un dossier connu.
  assert.equal(effacer.match(/AND private\.fn_rgpd_decision_objet_soignant\([^;]*?\) = 'EFFACER'/g)?.length, 3, 'trois origines classées');
  // Revues : pièces et cohérence d’identité seulement ; alertes de fraude et suspensions conservées.
  assert.doesNotMatch(effacer, /donnees_originales ->> 'soignant_id'/);
  assert.match(effacer, /f\.type_entite = 'TELEVERSEMENT_DOCUMENT' AND f\.id_entite = ANY/);
  assert.match(effacer, /WHERE r\.revue_id = ANY \(COALESCE\(v_revues, '\{\}'::uuid\[\]\)\);/);
  // Revues d'identité : cohérence et SIRET (type SOIGNANT, identité déclarée), toutes celles du compte.
  assert.match(effacer, /OR \(f\.id_entite = p_soignant_id AND f\.type_entite = 'SOIGNANT'\);/);
  assert.doesNotMatch(effacer, /ALERTE_FRAUDE'\)/, 'alertes de fraude jamais sélectionnées');
  // Fichiers à classer : consignés avant la réécriture des références, liste privée.
  assert.ok(effacer.indexOf('INSERT INTO private.rgpd_fichiers_a_classer') < effacer.indexOf('UPDATE public.documents_soignants d'));
  assert.match(sql2, /REVOKE ALL ON TABLE private\.rgpd_fichiers_a_classer FROM PUBLIC, anon, authenticated, service_role;/);
  assert.match(sql2, /CONSTRAINT rgpd_fichiers_a_classer_unique UNIQUE NULLS NOT DISTINCT \(bucket, chemin\)/);
  assert.match(miseAJour, /s3_cle = p_soignant_id::text \|\| '\/documents\/efface\/' \|\| d\.id::text/);
  assert.match(effacer, /DELETE FROM public\.heures_externes_soignants h WHERE h\.soignant_id = p_soignant_id;/);
  assert.match(effacer, /UPDATE public\.file_revue_manuelle f/);
  assert.match(effacer, /UPDATE private\.revue_manuelle_decisions r/);
  assert.match(effacer, /RAISE EXCEPTION 'RGPD_EFFACEMENT_PIECES_INCOMPLET : /);
  assert.match(effacer, /RAISE EXCEPTION 'RGPD_EFFACEMENT_PIECES_PROFIL_ACTIF : /);
  assert.ok(effacer.indexOf('INSERT INTO private.rgpd_purges_stockage') < effacer.indexOf('UPDATE public.documents_soignants d'),
    'chemins mis en file avant leur réécriture');
  // L'alerte ne porte aucun nom de fichier.
  const alerte = effacer.slice(effacer.indexOf("'RGPD_PURGE_STOCKAGE_DOSSIER_INCONNU'"));
  assert.doesNotMatch(alerte.slice(0, alerte.indexOf(';')), /o\.name|chemin/);
});

test('Storage : aucune suppression SQL, buckets conservés jamais purgés, confirmation par la base', () => {
  const code = sql2.replace(/--[^\n]*/g, '');
  assert.doesNotMatch(code, /DELETE\s+FROM\s+storage\./i, 'aucune suppression SQL de storage.objects');
  assert.doesNotMatch(code, /allow_delete_query/);
  const decision = corps(sql2, 'private', 'fn_rgpd_decision_objet_soignant');
  assert.match(decision, /p_bucket NOT IN \('jolene-documents', 'attestations-heures-externes', 'justificatifs'\)/);
  assert.doesNotMatch(decision, /contrats-signes|copies-bulletins-paie/);
  assert.match(decision, /= 'retrocession' THEN 'CONSERVER'/);
  assert.match(decision, /substr\(p_nom, 38\) ~ '\^avatar-\[0-9\]\+\\\.\(webp\|jpg\|jpeg\|png\|heic\)\$' THEN 'EFFACER'/, 'photos de profil effacées');
  assert.match(read('src/components/AvatarUpload.tsx'), /const path = `\$\{user\.id\}\/\$\{assetPrefix\}-\$\{Date\.now\(\)\}\.webp`;/, 'chemin web des photos');
  const confirmer = corps(sql2, 'public', 'fn_rgpd_purges_stockage_confirmer');
  assert.match(confirmer, /AND NOT EXISTS \(SELECT 1 FROM storage\.objects o WHERE o\.bucket_id = q\.bucket AND o\.name = q\.chemin\)/);
  assert.match(confirmer, /chemin = NULL/);
  assert.match(confirmer, /SET reserve_jusqua = pg_catalog\.now\(\) \+ interval '50 minutes'/, 'échec repoussé au passage suivant');
  assert.match(corps(sql2, 'public', 'fn_rgpd_purges_stockage_reserver'), /ORDER BY q\.tentatives, q\.demande_le, q\.id/, 'nouveaux fichiers avant les échecs');
  assert.match(corps(sql2, 'private', 'fn_rgpd_signaler_purge_stockage'), /COALESCE\(a\.details -> 'soignants', '\[\]'::jsonb\) \|\| \(EXCLUDED\.details -> 'soignants'\)/, 'alerte cumulative');
  for (const rpc of [confirmer, corps(sql2, 'public', 'fn_rgpd_purges_stockage_reserver')]) {
    assert.match(rpc, /IF COALESCE\(auth\.role\(\), ''\) IS DISTINCT FROM 'service_role' THEN\n\s+RAISE EXCEPTION 'Rôle de service requis' USING ERRCODE = '42501';/);
  }
  const partage = read('supabase/functions/_shared/rgpd-purge-stockage.ts');
  assert.match(partage, /\.storage\.from\(bucket\)\.remove\(/);
  assert.match(partage, /BUCKETS_PURGEABLES = Object\.freeze\(\['jolene-documents', 'attestations-heures-externes', 'justificatifs'\]\)/);
});

test('purge des inactifs verrouillée, cron horaire, droits et inventaire', () => {
  const inactifs = corps(sql2, 'public', 'fn_rgpd_purge_automatique_inactifs');
  assert.match(inactifs, /RAISE EXCEPTION 'RGPD_PURGE_INACTIFS_VERROUILLEE : [^']*docs\/CONFORMITE\.md §6\.5\.'\n\s+USING ERRCODE = '0A000';/);
  assert.doesNotMatch(inactifs, /\b(UPDATE|INSERT|DELETE)\b/);
  assert.match(sql2, /cron\.schedule\('jolene_rgpd_purge_stockage', '41 \* \* \* \*',\n\s+\$job\$SELECT private\.fn_lancer_purge_stockage_rgpd\(\)\$job\$\);/);
  assert.match(sql2, /IF NOT EXISTS \(SELECT 1 FROM pg_catalog\.pg_extension WHERE extname = 'pg_cron'\) THEN\n\s+RETURN;/);
  assert.match(sql2, /v_actif := EXISTS \(SELECT 1 FROM cron\.job j WHERE j\.active AND j\.jobname <> 'jolene_rgpd_purge_stockage'\);/);
  const lancer = corps(sql2, 'private', 'fn_lancer_purge_stockage_rgpd');
  assert.match(lancer, /url := v_url \|\| '\/functions\/v1\/purge-stockage-rgpd'/);
  assert.match(lancer, /'x-jolene-cron-secret', v_secret/);
  assert.match(lancer, /'RGPD_PURGE_STOCKAGE_EN_RETARD'/);
  assert.match(lancer, /'RGPD_PURGE_STOCKAGE_CONFIGURATION'/);
  for (const signature of ['private.fn_rgpd_decision_objet_soignant(text, text, uuid)', 'private.fn_rgpd_signaler_purge_stockage(text, text, jsonb)',
    'private.fn_rgpd_effacer_pieces_soignant(uuid, text)', 'private.fn_lancer_purge_stockage_rgpd()']) {
    assert.ok(sql2.includes(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC, anon, authenticated, service_role;`), signature);
  }
  for (const signature of ['public.fn_rgpd_purges_stockage_reserver(integer)', 'public.fn_rgpd_purges_stockage_confirmer(uuid[], text)']) {
    assert.ok(sql2.includes(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC, anon, authenticated;`), signature);
    assert.ok(sql2.includes(`GRANT EXECUTE ON FUNCTION ${signature} TO service_role;`), signature);
  }
  assert.match(sql2, /REVOKE ALL ON TABLE private\.rgpd_purges_stockage FROM PUBLIC, anon, authenticated, service_role;/);
  for (const signature of ['private.fn_rgpd_effacer_pieces_soignant(uuid,text)', 'private.fn_lancer_purge_stockage_rgpd()',
    'fn_rgpd_purges_stockage_reserver(integer)', 'fn_rgpd_purges_stockage_confirmer(uuid[],text)']) {
    assert.ok(sql2.includes(`    ('${signature}',\n`), `inventaire SECURITY DEFINER : ${signature}`);
  }
});

test('câblage CI, edge déclarée, décision documentée', () => {
  const run = workflow.split('name: Exécuter les migrations ajoutées et les régressions SQL sans persister')[1];
  assert.match(run, /^\s+tests\/security\/suppression-compte-soignant-effacement\.test\.sql$/m, 'suite dans SQL_TESTS');
  assert.ok(workflow.includes("psql -X -v ON_ERROR_STOP=1 -c 'CREATE DATABASE effacement_pieces_banc'"));
  assert.ok(workflow.includes('PGDATABASE=effacement_pieces_banc node --test tests/postgres/suppression-compte-soignant-effacement.pg17.mjs'));
  assert.ok(workflow.includes('git fetch --no-tags --depth=1 origin 1bfb14e8c3bf2ccf08a0d6164300a1acb067d2d9'));
  assert.ok(workflow.includes('node --test tests/node/suppression-compte-soignant-effacement.node.mjs tests/node/rgpd-purge-stockage.node.mjs'));
  assert.ok(banc.includes(`'supabase/migrations/${M1}',\n  'supabase/migrations/${M2}',`));
  assert.ok(banc.includes("export const SUITE = 'tests/security/suppression-compte-soignant-effacement.test.sql';"));
  assert.match(read('supabase/config.toml'), /\[functions\.purge-stockage-rgpd\]\nverify_jwt = false\n/);
  const manifeste = JSON.parse(read('supabase/EDGE_AUTH_MANIFEST.json'));
  assert.deepEqual(manifeste.entries.find(e => e.slug === 'purge-stockage-rgpd')?.guard_all, ['verifyCronServiceAuth', 'isCronAuthProbe']);
  const conformite = read('docs/CONFORMITE.md');
  assert.match(conformite, /^## 6\. Suppression du compte soignant/m);
  for (const source of ['art. 17.1 a', 'art. 17.3 b', 'art. 17.3 e', 'art. 5.1 c', 'art. 5.1 e', 'art. 12.3',
    'L123-22', 'L102 B', '2224', 'L1221-10', '32016R0679']) {
    assert.ok(conformite.includes(source), `source citée : ${source}`);
  }
  assert.match(conformite, /### 6\.5 /);
});

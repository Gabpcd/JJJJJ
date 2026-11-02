import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  CONTRACTS_PATH,
  RPC_SUIVIES,
  SOURCES,
  buildContracts,
  diffContracts,
} from '../../scripts/mobile/check-rpc-contracts.mjs';

// Garde du lot 1, tranche T0 (docs/mobile-swift/LOT1_PLAN.md §3 T0) : les RPC du lot 1 sont
// sous contrat AVANT toute gateway Swift, le JSON versionné ne dérive pas des sources du dépôt,
// et chaque RPC suivie a sa fiche dans CONTRATS_RPC_SOIGNANT.md. Aucun réseau, aucun secret :
// le test ne lit que des fichiers du dépôt.

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = relative => readFileSync(join(root, relative), 'utf8');

const LOT0 = ['fn_get_my_role', 'fn_etablissements_safe'];

// Ordre et contenu attendus pour le lot 1 (blueprint §3 T0 + décision 5 : audit via
// fn_audit_connexion / fn_maj_activite_soignant, et fn_ecrire_audit_safe pour MISSION_ASSIGNATION).
const LOT1 = [
  'fn_dashboard_soignant_complet',
  'fn_confirmer_action_planning_v1',
  'fn_suggestions_missions_pour_soignant',
  'fn_annuler_candidature_soignant',
  'fn_annuler_mission_soignant',
  'fn_repondre_proposition',
  'fn_toggle_favori_etablissement',
  'fn_mes_favoris_etablissements',
  'fn_audit_connexion',
  'fn_maj_activite_soignant',
  'fn_ecrire_audit_safe',
  'fn_supprimer_compte_rate_limited',
  'fn_param_bool',
  'fn_confirmer_presence_mission',
];

// Jamais côté natif : exclut `est_compte_test = true` (NULL pour tout établissement de recette
// STAGING) ; le nom d'établissement vient exclusivement de fn_etablissements_safe.
const INTERDITES_NATIF = ['fn_etablissement_public'];
// Lot 4 (swipe) : pas avant.
const PAS_AVANT_LOT4 = ['fn_retirer_candidature'];

const byName = new Map(RPC_SUIVIES.map(r => [r.name, r]));

/** Texte d'une section `## <titre>` d'un document Markdown, jusqu'à la section suivante. */
function section(doc, heading) {
  const start = doc.indexOf(`\n## ${heading}`);
  assert.ok(start >= 0, `section « ${heading} » introuvable`);
  const next = doc.indexOf('\n## ', start + 1);
  return doc.slice(start, next < 0 ? undefined : next);
}

/** Corps d'une fonction SQL du dump : de son `CREATE OR REPLACE FUNCTION` au `$$;` qui la ferme. */
function sqlBody(schema, name) {
  const start = schema.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
  assert.ok(start >= 0, `${name} absente de public.sql`);
  const end = schema.indexOf('\n$$;', start);
  assert.ok(end > start, `${name} : fin de corps introuvable`);
  return schema.slice(start, end);
}

/** Littéraux `'error', '…'` d'un corps SQL, apostrophes doublées ramenées à la valeur JSON réelle. */
const sqlErrors = body => [...body.matchAll(/'error',\s*'((?:[^']|'')*)'/g)].map(m => m[1].replaceAll("''", "'"));
/** Codes `'code', 'X'` et `'code', COALESCE(…, 'X')` d'un corps SQL. */
const sqlCodes = body => [...body.matchAll(/'code',\s*(?:COALESCE\([^,]+,\s*)?'([A-Z0-9_]+)'/g)].map(m => m[1]);
/** Texte Markdown hors blocs de code clôturés (les signatures SQL y gardent leurs `''`). */
const horsBlocs = doc => doc.replace(/```[\s\S]*?```/g, '');

const DECISIONS_HEADING = '\n## 7. Décisions (02/11/2026)\n';
/** Texte du §7 de LOT1_PLAN.md (dernière section), sans le §6 dont les items sont aussi numérotés. */
function decisionsDu(plan) {
  const at = plan.indexOf(DECISIONS_HEADING);
  assert.ok(at >= 0, 'section 7 « Décisions (02/11/2026) » introuvable');
  return plan.slice(at + DECISIONS_HEADING.length);
}

test('RPC_SUIVIES : noms uniques, statuts et lots valides', () => {
  assert.equal(byName.size, RPC_SUIVIES.length, 'doublon dans RPC_SUIVIES');
  for (const r of RPC_SUIVIES) {
    assert.ok(['lot0', 'a_venir'].includes(r.statut), `${r.name} : statut inconnu ${r.statut}`);
    assert.ok(Number.isInteger(r.lot) && r.lot >= 0 && r.lot <= 6, `${r.name} : lot invalide ${r.lot}`);
    if (r.statut === 'lot0') assert.equal(r.lot, 0, `${r.name} : statut lot0 implique lot 0`);
  }
});

test('RPC_SUIVIES : les deux RPC du lot 0 restent consommées lot 0', () => {
  for (const name of LOT0) {
    assert.deepEqual(byName.get(name), { name, statut: 'lot0', lot: 0 });
  }
});

test('RPC_SUIVIES : toutes les RPC du lot 1 sont suivies en a_venir lot 1', () => {
  for (const name of LOT1) {
    const entry = byName.get(name);
    assert.ok(entry, `${name} absente de RPC_SUIVIES (lot 1, T0)`);
    assert.equal(entry.statut, 'a_venir', `${name} : statut attendu a_venir`);
    assert.equal(entry.lot, 1, `${name} : lot attendu 1`);
  }
});

test('RPC_SUIVIES : fn_mon_profil_soignant_complet est reclassée lot 3 (correction v2 n°4)', () => {
  assert.deepEqual(byName.get('fn_mon_profil_soignant_complet'), {
    name: 'fn_mon_profil_soignant_complet', statut: 'a_venir', lot: 3,
  });
});

test('RPC_SUIVIES : aucune RPC interdite ou prématurée', () => {
  for (const name of [...INTERDITES_NATIF, ...PAS_AVANT_LOT4]) {
    assert.ok(!byName.has(name), `${name} ne doit pas figurer dans RPC_SUIVIES`);
  }
});

test('RPC_SUIVIES : les RPC des lots 2 et 3 du lot 0 sont conservées', () => {
  const lot2 = RPC_SUIVIES.filter(r => r.lot === 2).map(r => r.name);
  assert.deepEqual(lot2, [
    'fn_pointer_arrivee', 'fn_pointer_depart', 'fn_scanner_code_pointage', 'fn_valider_scan_qr',
    'fn_generer_qr_mission', 'fn_etat_pointage_mission', 'fn_envoyer_otp_signature',
    'fn_signer_contrat_otp', 'fn_remplacer_document_soignant',
  ]);
  assert.equal(byName.get('fn_upsert_token_push')?.lot, 3);
});

test('rpc-contracts.json : aucune dérive avec types.ts, public.sql et le manifeste', () => {
  const actual = buildContracts({
    typesSource: read(SOURCES.types),
    schemaSource: read(SOURCES.schema),
    manifest: JSON.parse(read(SOURCES.manifest)),
  });
  const expected = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  assert.deepEqual(diffContracts(expected, actual), []);
  assert.equal(actual.rpcs.length, RPC_SUIVIES.length);
  // Chaque RPC suivie a au moins une définition SQL : le contrat n'est jamais tenu par types.ts seul.
  for (const r of actual.rpcs) assert.ok(r.sql.length >= 1, `${r.name} : aucune définition SQL`);
  // Toutes sont appelables avec le JWT utilisateur (GRANT authenticated) : aucune RPC admin/service.
  for (const r of actual.rpcs) assert.ok(r.grants.includes('authenticated'), `${r.name} : pas de GRANT authenticated`);
});

test('rpc-contracts.json : fn_param_bool est tenue par public.sql seul (absente de types.ts)', () => {
  const expected = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  const entry = expected.rpcs.find(r => r.name === 'fn_param_bool');
  assert.ok(entry);
  assert.equal(entry.types, null);
  assert.equal(entry.sql[0].signature, 'fn_param_bool("p_cle" "text", "p_defaut" boolean)');
  assert.equal(entry.sql[0].returns, 'boolean');
  assert.ok(!entry.grants.includes('anon'), 'fn_param_bool ne doit pas être ouverte à anon (décision 15)');
});

test('diffContracts : un changement de lot ou de statut est une dérive', () => {
  const base = { schema_version: 1, rpcs: [{ name: 'fn_x', statut: 'a_venir', lot: 1, types: null, sql: [], grants: [], manifeste: null }] };
  const changed = { schema_version: 1, rpcs: [{ ...base.rpcs[0], lot: 3 }] };
  const problems = diffContracts(base, changed);
  assert.equal(problems.length, 1);
  assert.match(problems[0], /fn_x\.lot/);
  assert.deepEqual(diffContracts(base, base), []);
});

test('CONTRATS_RPC_SOIGNANT.md : une fiche par RPC suivie, fiche edge delete-account, interdiction fn_etablissement_public', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md');
  for (const r of RPC_SUIVIES) {
    assert.ok(doc.includes(`\n## ${r.name}\n`), `fiche manquante pour ${r.name}`);
    assert.ok(doc.includes(`| \`${r.name}\` |`), `ligne de synthèse manquante pour ${r.name}`);
  }
  assert.ok(doc.includes('\n## Edge `delete-account`'), 'fiche edge delete-account manquante');
  for (const code of ['401', '403', '409', '429', '503']) {
    assert.ok(doc.includes(`**${code}**`), `code HTTP ${code} absent de la fiche delete-account`);
  }
  assert.ok(doc.includes('verify_jwt = false'), 'verify_jwt = false non consigné pour delete-account');
  assert.ok(doc.includes('\n## Interdite côté natif : `fn_etablissement_public`'), 'fiche interdiction fn_etablissement_public manquante');
  assert.ok(doc.includes('est_compte_test'), 'motif de l interdiction (est_compte_test) absent');
});

test('LOT1_PLAN.md versionné : §7 = décisions du 02/11/2026, plus aucune question ouverte', () => {
  const plan = read('docs/mobile-swift/LOT1_PLAN.md');
  assert.ok(plan.includes(DECISIONS_HEADING), 'section 7 non remplacée par les décisions');
  assert.ok(!plan.includes('## 7. Questions ouvertes'), 'la section « Questions ouvertes » subsiste');
  const decisions = decisionsDu(plan);
  assert.ok(!decisions.includes('\n## '), 'le §7 doit rester la dernière section du plan');
  // Les 19 questions ouvertes du blueprint v2 + la question 20 (exception PRINCIPES §2), dans l'ordre.
  let from = 0;
  for (let i = 1; i <= 20; i++) {
    const at = decisions.slice(from).search(new RegExp(`\\n${i}\\. \\*\\*`));
    assert.ok(at >= 0, `décision ${i} absente du §7 (ou hors ordre)`);
    from += at + 1;
  }
  assert.ok(!/\n21\. \*\*/.test(decisions), 'décision 21 inattendue');
});

test('LOT1_PLAN.md : la recherche des décisions est bornée au §7 (le §6 numérote aussi 1. à 10.)', () => {
  const plan = read('docs/mobile-swift/LOT1_PLAN.md');
  // Témoin : retirer la décision 3 du §7 laisse un item « 3. ** » au §6 ; seule une recherche
  // bornée au §7 détecte le retrait.
  const sans3 = plan.replace('\n3. **Gating profil**', '\n3bis. Gating profil');
  assert.ok(sans3 !== plan, 'témoin : décision 3 introuvable');
  assert.ok(/\n3\. \*\*/.test(sans3), 'témoin : le §6 garde un item 3.');
  assert.ok(!/\n3\. \*\*/.test(decisionsDu(sans3)), 'la recherche bornée au §7 doit échouer');
});

test('PARITE_SOIGNANT.md : sous-lignes lot 1 (Mes missions, Favoris, détail mission)', () => {
  const parite = read('docs/mobile-swift/PARITE_SOIGNANT.md');
  for (const needle of [
    '`/soignant/missions` › Candidatures',
    '`/soignant/missions` › À venir',
    '`/soignant/missions` › Passées',
    '`/soignant/mes-favoris` › Missions',
    '`/soignant/mes-favoris` › Établissements',
    'confirmation de présence (lot 1), pointage (lot 2)',
  ]) assert.ok(parite.includes(needle), `PARITE : « ${needle} » absent`);
});

test('RECETTE_DEVICE_LOT1.md : ligne du modèle d e-mail reset (réglage non versionnable)', () => {
  const recette = read('docs/mobile-swift/RECETTE_DEVICE_LOT1.md');
  assert.ok(recette.includes('token_hash={{ .TokenHash }}&type=recovery'), 'format token_hash attendu absent');
  assert.ok(/mod[èe]le d['’]e-mail/i.test(recette), 'ligne « modèle d e-mail reset » absente');
});

test('PLAN_APP_NATIVE_SWIFT.md l.~173 : critère d audit amendé (décision 5)', () => {
  const plan = read('docs/PLAN_APP_NATIVE_SWIFT.md');
  assert.ok(plan.includes("`fn_audit_connexion('CONNEXION'"), 'critère lot 1 non amendé vers fn_audit_connexion');
  assert.ok(!plan.includes('- `fn_ecrire_audit_safe` émis pour connexion et candidature, vérifié par requête STAGING.\n'),
    'ancien critère (fn_ecrire_audit_safe pour la connexion) toujours présent tel quel');
});

// Revue B8 de T0 : les fiches servent de base aux tests « une forme de réponse = un test » de
// T6a, T6c et T8. Les listes sont donc comparées aux sources (corps SQL du dump, edge function),
// pas recopiées : une forme ajoutée côté serveur sans fiche fait échouer la garde.

test('CONTRATS : fn_confirmer_action_planning_v1 liste toutes les formes de réponse du corps SQL (clé `code`)', () => {
  const schema = read(SOURCES.schema);
  const body = sqlBody(schema, 'fn_confirmer_action_planning_v1');
  const conflit = sqlBody(schema, 'fn_conflit_planning_soignant');
  const fiche = section(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'), 'fn_confirmer_action_planning_v1');
  const erreurs = sqlErrors(body);
  // Témoin : les six refus propres à la RPC (l.24157, 24168, 24181, 24200, 24248 et 24306 du dump).
  assert.equal(erreurs.length, 6, `refus SQL attendus : 6, lus : ${erreurs.length}`);
  for (const message of erreurs) assert.ok(fiche.includes(message), `refus SQL absent de la fiche : « ${message} »`);
  // Repli du conflit de planning : COALESCE(v_conflit->>'message', '<repli>').
  const repli = body.match(/v_conflit->>'message',\s*'((?:[^']|'')*)'/)?.[1]?.replaceAll("''", "'");
  assert.ok(repli && fiche.includes(repli), 'message de repli CONFLIT_PLANNING absent de la fiche');
  const codes = [...new Set([...sqlCodes(body), ...sqlCodes(conflit)])];
  assert.deepEqual(codes, [
    'PLANNING_A_RECONFIRMER', 'PLANNING_MODIFIE_RECONFIRMER', 'CONFLIT_PLANNING',
    'PLANNING_DETAILLE_INDISPONIBLE', 'PLANNING_EXISTANT_INDISPONIBLE', 'REPOS_11H',
  ]);
  for (const code of codes) assert.ok(fiche.includes(`'${code}'`) || fiche.includes(`\`${code}\``), `code ${code} absent de la fiche`);
  // Ni la RPC ni fn_conflit_planning_soignant ne posent `error_code` : le décodeur lit `code`.
  assert.ok(!body.includes('error_code') && !conflit.includes('error_code'), 'error_code inattendu dans le corps SQL');
  assert.ok(/clé `code`[^.]*jamais `error_code`/.test(fiche), 'la fiche doit préciser : clé `code`, jamais `error_code`');
});

test('CONTRATS : fn_confirmer_presence_mission cite ses refus en valeur JSON, sans apostrophe SQL doublée', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md');
  const body = sqlBody(read(SOURCES.schema), 'fn_confirmer_presence_mission');
  const fiche = section(doc, 'fn_confirmer_presence_mission');
  const erreurs = sqlErrors(body);
  assert.deepEqual(erreurs, ['Mission introuvable', "Cette mission n'est plus active."]);
  for (const message of erreurs) {
    assert.ok(fiche.includes(`'${message}'`) || fiche.includes(`"${message}"`), `valeur JSON absente : ${message}`);
  }
  // Hors blocs SQL, aucune valeur ne garde l'échappement `''` du littéral SQL : un vecteur de test
  // Swift copié depuis la fiche ne correspondrait pas à la réponse réelle.
  const doublee = /\p{L}''\p{L}/u;
  for (const [nom, texte] of [['CONTRATS_RPC_SOIGNANT.md', doc], ['LOT1_PLAN.md', read('docs/mobile-swift/LOT1_PLAN.md')]]) {
    const trouve = horsBlocs(texte).match(doublee);
    assert.equal(trouve, null, `${nom} : apostrophe SQL doublée hors bloc de code (« ${trouve?.[0]} »)`);
  }
});

test('CONTRATS : fn_ecrire_audit_safe — auth.uid() nul donne {success:false} en HTTP 200, pas une exception', () => {
  const body = sqlBody(read(SOURCES.schema), 'fn_ecrire_audit_safe');
  // Témoin SQL : le RAISE 28000 est intercepté par le EXCEPTION WHEN OTHERS de la même fonction.
  assert.match(body, /RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000'/);
  assert.match(body, /EXCEPTION WHEN OTHERS THEN\s+RETURN jsonb_build_object\('success', false, 'error', SQLERRM\)/);
  const fiche = section(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'), 'fn_ecrire_audit_safe');
  assert.ok(!/nul → exception `28000`/.test(fiche), 'la fiche présente encore 28000 comme une erreur PostgREST');
  assert.ok(fiche.includes("{success:false, error:'Non authentifié'}"), 'réponse réelle (HTTP 200) absente de la fiche');
});

test('CONTRATS : edge delete-account — chaque statut et chaque message de index.ts et de verifyUserOrServiceRole', () => {
  const fiche = section(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'), 'Edge `delete-account`');
  const index = read('supabase/functions/delete-account/index.ts');
  const auth = read('supabase/functions/_shared/admin-auth.ts');
  const debut = auth.indexOf('export async function verifyUserOrServiceRole');
  const verify = auth.slice(debut, auth.indexOf('export async function verifyAdminOrServiceRole'));
  assert.ok(debut >= 0 && verify.length > 0, 'verifyUserOrServiceRole introuvable');
  const messages = [...index.matchAll(/error:\s*(['"])((?:(?!\1).)+)\1/g)].map(m => m[2]);
  messages.push(...[...index.matchAll(/\|\|\s*'([^']+)'/g)].map(m => m[1]));
  const statuts = new Set([...index.matchAll(/\},\s*(\d{3})\);/g)].map(m => m[1]));
  for (const [, statut, message] of verify.matchAll(/status:\s*(\d{3}),\s*error:\s*'([^']+)'/g)) {
    statuts.add(statut);
    messages.push(message);
  }
  // Témoins : index.ts émet 405/403/429/500/503/409, verifyUserOrServiceRole 401/500/403.
  assert.deepEqual([...statuts].sort(), ['401', '403', '405', '409', '429', '500', '503']);
  assert.ok(messages.length >= 20, `messages lus : ${messages.length}`);
  for (const statut of ['200', ...statuts]) assert.ok(fiche.includes(`**${statut}**`), `statut ${statut} absent de la fiche`);
  for (const message of new Set(messages)) assert.ok(fiche.includes(message), `message absent de la fiche : « ${message} »`);
  for (const [, code] of index.matchAll(/error_code:\s*'([A-Z_]+)'/g)) {
    assert.ok(fiche.includes(`'${code}'`), `error_code ${code} absent de la fiche`);
  }
});

test('CONTRATS : fn_mes_favoris_etablissements fait un JOIN interne (jamais présenté comme LEFT JOIN)', () => {
  const body = sqlBody(read(SOURCES.schema), 'fn_mes_favoris_etablissements');
  assert.match(body, /\n\s*JOIN etablissements e ON e\.id = f\.etablissement_id/);
  assert.doesNotMatch(body, /LEFT\s+JOIN/);
  const doc = horsBlocs(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'));
  assert.ok(!/`fn_mes_favoris_etablissements\.nom`\s*\(LEFT/.test(doc), 'favoris présentés comme LEFT JOIN');
  assert.ok(/`fn_mes_favoris_etablissements\.nom`\s*\(JOIN interne/.test(doc), 'JOIN interne des favoris non consigné');
  assert.ok(/JOIN interne/.test(section(doc, 'fn_mes_favoris_etablissements')), 'fiche favoris : JOIN interne non consigné');
});

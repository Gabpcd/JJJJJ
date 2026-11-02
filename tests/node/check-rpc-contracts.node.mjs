import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  CONTRACTS_PATH,
  RPC_JAMAIS_SUIVIES,
  RPC_PAS_AVANT_LOT4,
  RPC_SUIVIES,
  SOURCES,
  buildContracts,
  diffContracts,
  extractTypesSignature,
  verifierExclusions,
} from '../../scripts/mobile/check-rpc-contracts.mjs';
// Exports ajoutés par le lot 2 (T0) : lus par espace de noms pour qu'une absence fasse échouer
// les seuls tests concernés, pas le chargement du fichier.
import * as contratsRpc from '../../scripts/mobile/check-rpc-contracts.mjs';

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

// Jamais côté natif : `fn_etablissement_public` exclut `est_compte_test = true` (NULL pour tout
// établissement de recette STAGING) ; le nom d'établissement vient exclusivement de
// fn_etablissements_safe. `fn_creer_notification` (lot 2, décision 9) : notification arbitraire
// écrite par le client, doublon du trigger `trg_notifier_creation_litige`.
const INTERDITES_NATIF = ['fn_etablissement_public', 'fn_creer_notification'];
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
    // `staging_seulement` (lot 2, T0) : RPC de recette définie par un supplément STAGING, jamais en production.
    assert.ok(['lot0', 'a_venir', 'consommee', 'staging_seulement'].includes(r.statut), `${r.name} : statut inconnu ${r.statut}`);
    assert.ok(Number.isInteger(r.lot) && r.lot >= 0 && r.lot <= 6, `${r.name} : lot invalide ${r.lot}`);
    if (r.statut === 'lot0') assert.equal(r.lot, 0, `${r.name} : statut lot0 implique lot 0`);
    // Une source hors dump n'est admise que pour une RPC de recette STAGING, et elle est alors obligatoire.
    if (r.statut === 'staging_seulement') {
      assert.ok(typeof r.source === 'string' && r.source.startsWith('scripts/ci/'), `${r.name} : source du supplément STAGING absente`);
    } else {
      assert.equal(r.source, undefined, `${r.name} : seule une RPC staging_seulement porte une source`);
    }
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

// Amendé par le lot 2 (T0, décision 1 de DECISIONS_LOT2.md) : les quatre RPC du système de pointage ①
// que le lot 0 listait (`fn_pointer_arrivee`, `fn_pointer_depart`, `fn_valider_scan_qr`,
// `fn_generer_qr_mission`) sortent de RPC_SUIVIES ; la liste complète du lot 2 est gardée plus bas.
test('RPC_SUIVIES : les RPC du lot 2 conservées depuis le lot 0, et celle du lot 3', () => {
  const lot2 = RPC_SUIVIES.filter(r => r.lot === 2).map(r => r.name);
  assert.deepEqual(lot2.slice(0, 5), [
    'fn_scanner_code_pointage', 'fn_etat_pointage_mission', 'fn_envoyer_otp_signature',
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

test('rpc-contracts.json : fn_param_bool garde sa signature SQL et reste fermée à anon', () => {
  const expected = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  const entry = expected.rpcs.find(r => r.name === 'fn_param_bool');
  assert.ok(entry);
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

// Revue B8 n°2 de T0 : la règle de décodage `RPCResponse` (LOT1_PLAN §2.4) est normative pour T1 et
// T6a ; elle est confrontée au SQL des délégués (réponses sans clé `success`). Mêmes exigences pour les
// chaînes de la confirmation de présence (confrontées au web), le dédoublonnage EventKit, la procédure
// de re-baseline et l'exécution de cette garde par le check requis « Typecheck + build ».

/** Texte d'une sous-section `### <titre>` d'un document Markdown, jusqu'à la (sous-)section suivante. */
function sousSection(doc, heading) {
  const start = doc.indexOf(`\n### ${heading}`);
  assert.ok(start >= 0, `sous-section « ${heading} » introuvable`);
  const fins = [doc.indexOf('\n### ', start + 1), doc.indexOf('\n## ', start + 1)].filter(i => i >= 0);
  return doc.slice(start, fins.length ? Math.min(...fins) : undefined);
}

const RATE_LIMIT_CANDIDATURE = 'Trop de candidatures en peu de temps. Réessayez plus tard.';
// Chaînes affichées par le web après `fn_confirmer_presence_mission` (bouton, confirmation, état).
const WEB_PRESENCE = [
  '✓ Je confirme ma présence',
  "Présence confirmée — l'établissement est prévenu. ✓",
  "✓ Présence confirmée — l'établissement est prévenu",
];

test('script : listes d exclusion exportées et fail-closed (jamais / pas avant le lot 4)', () => {
  assert.deepEqual(RPC_JAMAIS_SUIVIES, INTERDITES_NATIF);
  assert.deepEqual(RPC_PAS_AVANT_LOT4, PAS_AVANT_LOT4);
  assert.doesNotThrow(() => verifierExclusions(RPC_SUIVIES));
  assert.throws(
    () => verifierExclusions([...RPC_SUIVIES, { name: 'fn_etablissement_public', statut: 'a_venir', lot: 1 }]),
    /jamais/,
  );
  assert.throws(
    () => verifierExclusions([...RPC_SUIVIES, { name: 'fn_retirer_candidature', statut: 'a_venir', lot: 3 }]),
    /lot 4/,
  );
  assert.doesNotThrow(() => verifierExclusions([...RPC_SUIVIES, { name: 'fn_retirer_candidature', statut: 'a_venir', lot: 4 }]));
  // Le bloc « Jamais suivies » du script ne mélange plus une RPC suivie (lot 3) ni une RPC du lot 4.
  const source = read('scripts/mobile/check-rpc-contracts.mjs');
  const debut = source.indexOf('Jamais suivies');
  const fin = source.indexOf('Pas avant le lot 4');
  assert.ok(debut >= 0 && fin > debut, 'blocs « Jamais suivies » puis « Pas avant le lot 4 » attendus');
  const jamais = source.slice(debut, fin);
  assert.ok(jamais.includes('fn_etablissement_public'));
  for (const intrus of ['fn_retirer_candidature', 'fn_mon_profil_soignant_complet']) {
    assert.ok(!jamais.includes(intrus), `« Jamais suivies » cite encore ${intrus}`);
  }
});

test('LOT1_PLAN §2.4 : décodage par clés indépendant de `success`, dans l ordre du web, confronté au SQL', () => {
  const schema = read(SOURCES.schema);
  const postuler = sqlBody(schema, 'fn_postuler_mission');
  const finaliser = sqlBody(schema, 'fn_finaliser_attribution_mission');
  const resoudre = sqlBody(schema, 'fn_resoudre_contrat_mission');
  // Témoins SQL : les délégués renvoient le choix de contrat et le refus documentaire sans clé `success`.
  for (const body of [postuler, finaliser]) {
    assert.match(body, /RETURN v_resolution - 'ok';/);
    assert.match(body, /'documents_requis_pour', [^\n]+\n\s*'lien_documents', '\/soignant\/mes-documents'/);
  }
  assert.match(resoudre, /'ok', false,\s*'choix_requis', true,/);
  // Le succès POSTULER porte AUSSI `documents_requis_pour` (contrat retenu) : la règle documents exige `error`.
  assert.match(postuler, /'success', true,[\s\S]*?'documents_requis_pour', v_choix\s*\)/);
  const codesFinaliser = sqlCodes(finaliser);
  assert.deepEqual(codesFinaliser, ['PLANNING_HEBDOMADAIRE_INDISPONIBLE', 'PLAFOND_48H_HEBDO']);
  // Témoin web : `choix_requis` est testé avant `error`, sur POSTULER comme sur ACCEPTER.
  const tsx = read('src/pages/DetailMissionSoignant.tsx');
  const choix = [...tsx.matchAll(/data\?\.choix_requis/g)].map(m => m.index);
  assert.equal(choix.length, 2, 'témoin web : deux tests `data?.choix_requis` attendus');
  for (const at of choix) {
    const suite = tsx.slice(at).indexOf('data?.error');
    assert.ok(suite > 0 && suite < 400, 'témoin web : `data?.error` suit `data?.choix_requis`');
  }

  const s24 = sousSection(read('docs/mobile-swift/LOT1_PLAN.md'), '2.4 ');
  assert.ok(s24.includes('indépendante de `success`'), '§2.4 : discrimination indépendante de `success` non énoncée');
  assert.ok(/`choix_requis[^`]*`[^\n]*sans clé `success`/.test(s24), '§2.4 : choix_requis sans clé `success` non consigné');
  const regles = ['1. `choix_requis', '2. `code`', '3. `documents_requis_pour`', '4. `success == true`', '5. `error`', '6. '];
  let precedente = -1;
  for (const regle of regles) {
    const at = s24.indexOf(`\n${regle}`);
    assert.ok(at > precedente, `§2.4 : règle « ${regle} » absente ou hors ordre`);
    precedente = at;
  }
  const regle3 = s24.slice(s24.indexOf('\n3. `documents_requis_pour`'), s24.indexOf('\n4. '));
  assert.ok(regle3.includes('**et** `error`'), '§2.4 règle 3 : `error` requis (le succès POSTULER porte documents_requis_pour)');
  assert.ok(regle3.includes('lien_documents'), '§2.4 règle 3 : lien_documents absent');
  for (const code of [...codesFinaliser, 'PLANNING_A_RECONFIRMER', 'PLANNING_MODIFIE_RECONFIRMER', 'CONFLIT_PLANNING', 'REPOS_11H']) {
    assert.ok(s24.includes(`\`${code}\``), `§2.4 : code ${code} absent`);
  }
  assert.ok(s24.includes(RATE_LIMIT_CANDIDATURE), '§2.4 : rate-limit de candidature (HTTP 200) absent');
  assert.ok(!s24.includes('429'), '§2.4 : le rate-limit de candidature n est pas un HTTP 429');
  assert.ok(!s24.includes('`{success:false, error, error_code?, code?, documents_requis_pour?, choix_requis?, options?}` → `CandidatureOutcome`'),
    '§2.4 : ancienne règle (refus lus seulement sous success:false)');
  assert.ok(s24.includes('fiche `fn_confirmer_action_planning_v1`'), '§2.4 : renvoi à la fiche absent');
});

test('LOT1_PLAN T6a : renvoi à la fiche pour les formes de réponse, rate-limit en HTTP 200 (pas un 429)', () => {
  const rate = sqlBody(read(SOURCES.schema), 'fn_postuler_mission_rate_limited');
  assert.ok(rate.includes(`RETURN jsonb_build_object('error', '${RATE_LIMIT_CANDIDATURE}');`), 'témoin SQL : rate-limit en {error} HTTP 200');
  const t6a = sousSection(read('docs/mobile-swift/LOT1_PLAN.md'), 'T6a ');
  assert.ok(!t6a.includes('429'), 'T6a : « 429 » pour le rate-limit de candidature');
  assert.ok(!/\b3 formes de réponse\b/.test(t6a), 'T6a : « 3 formes de réponse » alors que la fiche en liste davantage');
  assert.ok(t6a.includes(`{error:'${RATE_LIMIT_CANDIDATURE}'}`) && t6a.includes('HTTP 200'), 'T6a : rate-limit en {error} HTTP 200 absent');
  assert.ok(t6a.includes('fiche `fn_confirmer_action_planning_v1`'), 'T6a : renvoi à la fiche absent');
});

test('CONTRATS : fiche fn_confirmer_action_planning_v1 — délégués sans `success`, lien_documents, plafond 48 h, classe', () => {
  const schema = read(SOURCES.schema);
  const finaliser = sqlBody(schema, 'fn_finaliser_attribution_mission');
  const resoudre = sqlBody(schema, 'fn_resoudre_contrat_mission');
  const fiche = section(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'), 'fn_confirmer_action_planning_v1');
  // Une forme « documents » par délégué qui la renvoie (POSTULER libéral, ACCEPTER/PROPOSITION), chacune avec lien_documents.
  const lienSql = "'lien_documents', '/soignant/mes-documents'";
  const nbSql = [sqlBody(schema, 'fn_postuler_mission'), finaliser].filter(b => b.includes(lienSql)).length;
  assert.equal(nbSql, 2, 'témoin SQL : deux délégués posent lien_documents');
  const nbFiche = fiche.split("lien_documents:'/soignant/mes-documents'").length - 1;
  assert.ok(nbFiche >= nbSql, `clé lien_documents : ${nbFiche} forme(s) dans la fiche pour ${nbSql} délégués`);
  for (const code of sqlCodes(finaliser)) assert.ok(fiche.includes(`'${code}'`), `code ${code} (fn_finaliser_attribution_mission) absent`);
  const messageChoix = resoudre.match(/'choix_requis', true,\s*'error', '([^']+)'/)?.[1];
  assert.ok(messageChoix && fiche.includes(`error:'${messageChoix}'`), 'message du choix de contrat absent');
  const options = [...resoudre.matchAll(/'value', '([A-Z]+)',\s*'label', '((?:[^']|'')*)'/g)];
  assert.equal(options.length, 2, 'témoin SQL : deux options de contrat');
  for (const [, value, label] of options) {
    assert.ok(fiche.includes(`'${value}'`) && fiche.includes(label.replaceAll("''", "'")), `option ${value} absente de la fiche`);
  }
  assert.ok(fiche.includes(RATE_LIMIT_CANDIDATURE), 'rate-limit absent');
  assert.ok(fiche.includes('sans clé `success`'), 'délégués sans clé `success` non consignés');
  assert.ok(fiche.includes('`LOT1_PLAN.md` §2.4'), 'renvoi à l ordre de décodage §2.4 absent');
  const classe = fiche.split('\n').find(l => l.startsWith("- **Classe d'authentification (manifeste)**"));
  assert.ok(classe, 'ligne « Classe d authentification » absente');
  assert.ok(!classe.includes('à classer avant consommation'), 'classe : « à classer avant consommation » alors que la décision 6 est prise');
  assert.ok(classe.includes('`RPC_UTILISATEUR_AUTH_INTERNE`') && classe.includes('décision 6'), 'classe : classement manuel de la décision 6 absent');
});

test('CONTRATS en-tête : formes polymorphes complètes et procédure de re-baseline (garde dans le check requis)', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md');
  const entete = doc.slice(0, doc.indexOf('\n## Synthèse'));
  for (const forme of [
    '`{error}` seul', '`{success:false, ok:false, error, code?}`', '`{success:false, error_code, …}`',
    '`{choix_requis:true, error, options}`', '`{error, code, …}`', '`{error, documents_requis_pour, lien_documents}`',
    '`{success:true, …}`',
  ]) assert.ok(entete.includes(forme), `en-tête : forme ${forme} absente`);
  assert.ok(entete.includes('sans clé `success`'), 'en-tête : réponses sans clé `success` non signalées');
  assert.ok(entete.includes('auto/schema-baseline'), 'en-tête : re-baseline automatique non évoquée');
  assert.ok(entete.includes('PR humaine') && entete.includes('--update'), 'en-tête : procédure « PR humaine + --update + fiche » absente');
  assert.ok(!/Deux RPC ne sont pas suivies et ne doivent jamais/.test(doc), 'fn_retirer_candidature présentée comme « jamais » suivie');
});

test('LOT1_PLAN T0 : fn_confirmer_action_planning_v1 classée par la décision 6 (plus de « tant que Q6 »)', () => {
  const t0 = sousSection(read('docs/mobile-swift/LOT1_PLAN.md'), 'T0 ');
  assert.ok(!t0.includes("tant que §7 Q6 n'est pas tranchée"), 'T0 : Q6 présentée comme ouverte');
  assert.ok(t0.includes('décision 6 : classement documentaire, manifeste non régénéré'), 'T0 : décision 6 non citée');
});

test('Présence : chaînes exactes du web citées, « Je serai là ✓ » réservé au titre du push serveur', () => {
  const tsx = read('src/pages/DetailMissionSoignant.tsx').replaceAll("\\'", "'");
  for (const texte of WEB_PRESENCE) assert.ok(tsx.includes(texte), `témoin web : « ${texte} » absent de DetailMissionSoignant.tsx`);
  const push = sqlBody(read(SOURCES.schema), 'fn_demander_confirmations_presence');
  assert.ok(push.includes("'Ta mission demain — Je serai là ✓'"), 'témoin SQL : titre du push RAPPEL_MISSION');
  const plan = read('docs/mobile-swift/LOT1_PLAN.md');
  const contrats = read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md');
  const recette = read('docs/mobile-swift/RECETTE_DEVICE_LOT1.md');
  for (const [nom, texte] of [
    ['LOT1_PLAN.md T6c', sousSection(plan, 'T6c ')],
    ['CONTRATS fn_confirmer_presence_mission', section(contrats, 'fn_confirmer_presence_mission')],
    ['RECETTE §5', section(recette, '5. ')],
  ]) {
    for (const web of WEB_PRESENCE) assert.ok(texte.includes(web), `${nom} : « ${web} » absent`);
  }
  for (const [nom, texte] of [['LOT1_PLAN.md', plan], ['CONTRATS_RPC_SOIGNANT.md', contrats], ['RECETTE_DEVICE_LOT1.md', recette]]) {
    for (const ligne of texte.split('\n').filter(l => l.includes('Je serai là'))) {
      assert.ok(ligne.includes('push'), `${nom} : « Je serai là » cité hors du titre du push : ${ligne.slice(0, 160)}`);
    }
  }
});

test('EventKit : dédoublonnage fixé (journal local, écriture seule iOS 17+), N défini', () => {
  const recette = section(read('docs/mobile-swift/RECETTE_DEVICE_LOT1.md'), '4. ');
  assert.ok(!recette.includes('pas de doublon (comportement consigné'), 'promesse « pas de doublon » intenable en écriture seule');
  assert.ok(!recette.includes('N événements au total'), 'ambiguïté « N événements au total »');
  for (const [nom, texte] of [['RECETTE §4', recette], ['LOT1_PLAN T5', sousSection(read('docs/mobile-swift/LOT1_PLAN.md'), 'T5 ')]]) {
    assert.ok(texte.includes('requestWriteOnlyAccessToEvents'), `${nom} : accès en écriture seule non consigné`);
    assert.ok(texte.includes('journal local'), `${nom} : mécanisme de dédoublonnage (journal local) absent`);
    assert.ok(texte.includes('N = ') && texte.includes('hors pause'), `${nom} : N non défini (créneaux PREVISIONNEL hors pause)`);
  }
});

test('validate-pr.yml : l étape « Garde de livraison mobile » du job Typecheck + build exécute cette garde', () => {
  const wf = read('.github/workflows/validate-pr.yml');
  const job = wf.indexOf('\n  typecheck-and-build:\n');
  assert.ok(job >= 0, 'job typecheck-and-build introuvable');
  const finJob = wf.slice(job + 1).search(/\n {2}[a-z][a-z0-9-]*:\n/);
  const corps = wf.slice(job, finJob < 0 ? undefined : job + 1 + finJob);
  assert.ok(corps.includes('name: Typecheck + build'), 'nom du check requis modifié');
  const etape = corps.indexOf('\n      - name: Garde de livraison mobile\n');
  assert.ok(etape >= 0, 'étape « Garde de livraison mobile » absente du job Typecheck + build');
  const suite = corps.slice(etape + 1);
  const fin = suite.search(/\n {6}- name: /);
  const bloc = suite.slice(0, fin < 0 ? undefined : fin);
  const run = bloc.split('\n').find(l => /^\s+run: /.test(l));
  assert.ok(run, 'ligne run: absente');
  assert.ok(run.includes('node --test') && run.includes('tests/node/check-rpc-contracts.node.mjs'), `run: n exécute pas la garde : ${run}`);
  assert.ok(!/^\s+if: /m.test(bloc) && !bloc.includes('continue-on-error'), 'étape conditionnelle ou non bloquante');
});

// Revue B8 n°3 de T0 : SupabaseErrorMapping ne garde pas PostgrestError.message. La règle des
// exceptions PostgREST doit donc lire le message AVANT le mapping (texte [CODE DU TRAVAIL]
// restitué mot pour mot, « 0 rows » / « déjà prise » → mission déjà attribuée).
test('LOT1_PLAN §2.4 : les exceptions PostgREST sont lues avant SupabaseErrorMapping', () => {
  const plan = read('docs/mobile-swift/LOT1_PLAN.md');
  const s = plan.slice(plan.indexOf('### 2.4 '), plan.indexOf('### 2.5 '));
  assert.ok(!s.includes('mappée par `SupabaseErrorMapping`, puis `.refusee`'),
    'la chaîne « SupabaseErrorMapping puis .refusee » perd le texte légal');
  assert.match(s, /`PostgrestError\.message` \*\*avant\*\*/);
  assert.ok(s.includes('`[CODE DU TRAVAIL]`') && s.includes("code:'CODE_DU_TRAVAIL'"));
  assert.ok(s.includes('`0 rows`') && s.includes('`déjà prise`') && s.includes('mission déjà attribuée'));
  const contrats = read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md');
  assert.ok(contrats.includes("**avant** `SupabaseErrorMapping.map`"), 'forme 14 non alignée');
  const web = read('src/pages/DetailMissionSoignant.tsx');
  assert.ok(web.includes("error.message?.includes('0 rows') || error.message?.includes('déjà prise')"),
    'le web ne classe plus « mission perdue » comme décrit : mettre la fiche à jour');
  assert.ok(read('src/lib/erreurs.ts').includes("msg.includes('[CODE DU TRAVAIL]')"));
});

/** Fichiers `.swift` sous un dossier, récursivement (hors `.build`). */
function swiftFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    if (name === '.build' || name.startsWith('.')) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...swiftFiles(full));
    else if (name.endsWith('.swift')) out.push(full);
  }
  return out;
}

// Un gap connu reste verrouillé : un appel RPC écrit en dur dans le code Swift doit viser une
// RPC sous contrat, jamais une RPC interdite côté natif ni une RPC du lot 4 avant son heure.
// Lot 2 (T0) : le système de pointage ① a son propre message (décision 1 de DECISIONS_LOT2.md).
test('ios-native : tout littéral "fn_…" du Swift est une RPC suivie et autorisée', () => {
  const suivies = new Set(RPC_SUIVIES.map(r => r.name));
  const interdites = new Set([...RPC_JAMAIS_SUIVIES, ...RPC_PAS_AVANT_LOT4]);
  const systeme1 = new Set(contratsRpc.RPC_POINTAGE_SYSTEME_1 ?? []);
  assert.ok(systeme1.size > 0, 'RPC_POINTAGE_SYSTEME_1 non exportée par le script');
  const fautes = [];
  for (const file of swiftFiles(join(root, 'ios-native'))) {
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/"(fn_[a-z0-9_]+)"/g)) {
      const rel = file.slice(root.length + 1);
      if (systeme1.has(m[1])) fautes.push(`${rel} : ${m[1]} appartient au système de pointage ①, interdit côté natif (DECISIONS_LOT2.md, décision 1)`);
      else if (interdites.has(m[1])) fautes.push(`${rel} : ${m[1]} interdite côté natif`);
      else if (!suivies.has(m[1])) fautes.push(`${rel} : ${m[1]} absente de RPC_SUIVIES`);
    }
  }
  assert.deepEqual(fautes, []);
});

// ---------------------------------------------------------------------------------------------
// Lot 2, tranche T0 (docs/mobile-swift/LOT2_PLAN.md §3 T0, docs/mobile-swift/DECISIONS_LOT2.md).
// Les RPC du lot 2 sont sous contrat avant toute gateway ; le système de pointage ① est interdit
// côté natif ; chaque forme de réponse citée par les fiches est confrontée à sa source (dump de
// production, supplément STAGING, edge functions, web). Aucun réseau, aucun secret.
// ---------------------------------------------------------------------------------------------

// Ordre de RPC_SUIVIES pour le lot 2 : les cinq RPC listées dès le lot 0, puis les dix ajoutées par T0.
const LOT2_SUIVIES = [
  'fn_scanner_code_pointage', 'fn_etat_pointage_mission', 'fn_envoyer_otp_signature',
  'fn_signer_contrat_otp', 'fn_remplacer_document_soignant',
  'fn_consentir_gps', 'fn_relancer_validation_presence', 'fn_presences_detail_mission',
  'fn_fenetre_contestation_ouverte', 'fn_ouvrir_litige_rate_limited', 'fn_creer_notation_mission',
  'fn_demander_revue_document', 'fn_verifier_coherence_documents', 'fn_signer_attestation_sante',
  'fn_admission_otp_signature_recette',
];
// Système de pointage ① (décision 1) : plus monté côté web depuis #664, jamais appelé par le natif.
const POINTAGE_SYSTEME_1 = [
  'fn_pointer_arrivee', 'fn_pointer_depart', 'fn_pointer_debut_pause', 'fn_pointer_fin_pause',
  'fn_valider_scan_qr', 'fn_generer_qr_mission', 'fn_valider_code_secours', 'fn_codes_pointage_mission',
];
const SUPPLEMENT_SMS = 'scripts/ci/sms-signature-staging.sql';
const DOC_CONTRATS = 'docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md';

/**
 * Corps d'une fonction du dump, quel que soit son délimiteur (`$$`, `$_$`, …). `entete` est le début
 * exact de la ligne `CREATE OR REPLACE FUNCTION` (nom seul, ou nom + arguments pour une surcharge).
 */
function corpsSql(schema, entete) {
  const start = schema.indexOf(entete);
  assert.ok(start >= 0, `définition introuvable : ${entete}`);
  const as = schema.slice(start).match(/\n\s*AS (\$[A-Za-z_]*\$)\n/);
  assert.ok(as, `délimiteur de corps introuvable : ${entete}`);
  const debut = start + as.index + as[0].length;
  const fin = schema.indexOf(`\n${as[1]};`, debut);
  assert.ok(fin > debut, `fin de corps introuvable : ${entete}`);
  return schema.slice(debut, fin);
}
const enteteFn = name => `CREATE OR REPLACE FUNCTION "public"."${name}"(`;

// Noms de condition PL/pgSQL employés dans le dump → SQLSTATE renvoyé par PostgREST.
const CONDITIONS_SQLSTATE = { no_data_found: 'P0002', insufficient_privilege: '42501', check_violation: '23514' };
/** `RAISE EXCEPTION '<message>' … [USING ERRCODE = '<x>']` d'un corps SQL ; sans ERRCODE : `P0001`. */
function sqlRaises(body) {
  return [...body.matchAll(/RAISE EXCEPTION\s+'((?:[^']|'')*)'([^;]*);/g)].map(([, message, suite]) => {
    const code = suite.match(/ERRCODE = '([A-Za-z0-9_]+)'/)?.[1];
    return { sqlstate: code ? (CONDITIONS_SQLSTATE[code] ?? code) : 'P0001', message: message.replaceAll("''", "'") };
  });
}
/** Codes `'error_code', 'X'` d'un corps SQL. */
const sqlErrorCodes = body => [...new Set([...body.matchAll(/'error_code',\s*'([A-Z0-9_]+)'/g)].map(m => m[1]))];
/** Littéraux `'message', '…'` d'un corps SQL (apostrophes doublées ramenées à la valeur JSON). */
const sqlMessages = body => [...body.matchAll(/'message',\s*'((?:[^']|'')*)'/g)].map(m => m[1].replaceAll("''", "'"));

/** Fichiers `.ts`/`.tsx` de `src/`, hors tests. */
function webFiles(dir = join(root, 'src')) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...webFiles(full));
    else if (/\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name)) out.push(full);
  }
  return out;
}
const relatif = file => file.slice(root.length + 1);
/** Texte Markdown aplati : un retour à la ligne dans un paragraphe vaut une espace. */
const aplati = texte => texte.replace(/\s+/g, ' ');
/** Section `## <titre>` de CONTRATS_RPC_SOIGNANT.md, aplatie. */
const sectionContrats = heading => aplati(section(read(DOC_CONTRATS), heading));

test('RPC_SUIVIES lot 2 : système rotatif, justificatifs, contrats et admission de recette, dans l ordre', () => {
  const lot2 = RPC_SUIVIES.filter(r => r.lot === 2);
  assert.deepEqual(lot2.map(r => r.name), LOT2_SUIVIES);
  for (const r of lot2) {
    if (r.name === 'fn_admission_otp_signature_recette') {
      assert.deepEqual(r, { name: r.name, statut: 'staging_seulement', lot: 2, source: SUPPLEMENT_SMS });
    } else {
      assert.ok(['a_venir', 'consommee'].includes(r.statut), `${r.name} : statut ${r.statut}`);
    }
  }
});

test('RPC_POINTAGE_SYSTEME_1 : huit RPC du système ①, jamais suivies, présentes au dump, refusées par verifierExclusions', () => {
  assert.deepEqual(contratsRpc.RPC_POINTAGE_SYSTEME_1, POINTAGE_SYSTEME_1);
  const schema = read(SOURCES.schema);
  for (const name of POINTAGE_SYSTEME_1) {
    assert.ok(!byName.has(name), `${name} ne doit plus figurer dans RPC_SUIVIES (décision 1)`);
    // Une RPC retirée du dump rend la liste périmée : la retirer d'ici et de la fiche dans la même PR.
    assert.ok(schema.includes(enteteFn(name)), `${name} absente de public.sql`);
    assert.throws(
      () => verifierExclusions([...RPC_SUIVIES, { name, statut: 'a_venir', lot: 2 }]),
      /système de pointage ①/,
      `${name} : verifierExclusions doit refuser le système ①`,
    );
  }
  for (const name of POINTAGE_SYSTEME_1) assert.ok(!RPC_JAMAIS_SUIVIES.includes(name), `${name} : liste dédiée, pas RPC_JAMAIS_SUIVIES`);
});

test('RPC_JAMAIS_SUIVIES : fn_creer_notification refusée (décision 9) et fiche « Interdite côté natif »', () => {
  assert.ok(RPC_JAMAIS_SUIVIES.includes('fn_creer_notification'));
  assert.throws(() => verifierExclusions([...RPC_SUIVIES, { name: 'fn_creer_notification', statut: 'a_venir', lot: 2 }]), /jamais/);
  const schema = read(SOURCES.schema);
  // Témoins : le trigger notifie déjà l'établissement à l'ouverture d'un litige ; le web appelle encore la RPC.
  assert.ok(schema.includes('CREATE OR REPLACE TRIGGER "trg_notifier_creation_litige" AFTER INSERT ON "public"."litiges"'));
  assert.ok(read('src/components/PanneauContestation.tsx').includes("supabase.rpc('fn_creer_notification'"));
  const fiche = sectionContrats('Interdite côté natif : `fn_creer_notification`');
  for (const temoin of ['trg_notifier_creation_litige', 'CONTESTATION_PRESENCE', 'PanneauContestation.tsx']) {
    assert.ok(fiche.includes(temoin), `fiche fn_creer_notification : ${temoin} absent`);
  }
});

test('fn_admission_otp_signature_recette : staging_seulement, définie par le supplément STAGING, absente de la production', () => {
  const supplement = read(SUPPLEMENT_SMS);
  assert.match(supplement.split('\n')[0], /^-- STAGING-ONLY supplement\. Not a production migration/);
  assert.ok(!read(SOURCES.schema).includes('fn_admission_otp_signature_recette'), 'présente dans le dump de production');
  assert.equal(extractTypesSignature(read(SOURCES.types), 'fn_admission_otp_signature_recette'), null);
  const entry = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8')).rpcs.find(r => r.name === 'fn_admission_otp_signature_recette');
  assert.ok(entry, 'absente de rpc-contracts.json');
  assert.equal(entry.statut, 'staging_seulement');
  assert.equal(entry.source, SUPPLEMENT_SMS);
  assert.equal(entry.types, null);
  assert.equal(entry.manifeste, null);
  assert.deepEqual(entry.sql, [{
    signature: 'fn_admission_otp_signature_recette(p_contrat_id uuid)',
    returns: 'jsonb', language: 'plpgsql', security: 'DEFINER', volatility: 'STABLE', search_path: "''",
  }]);
  assert.deepEqual(entry.grants, ['authenticated']);
  assert.match(supplement, /REVOKE ALL ON FUNCTION public\.fn_admission_otp_signature_recette\(uuid\) FROM PUBLIC,anon,service_role;/);
  // Réponse : clés de l'objet renvoyé, toutes citées par la fiche ; `{admitted:false}` sur toute erreur.
  const corps = supplement.slice(supplement.indexOf('CREATE FUNCTION public.fn_admission_otp_signature_recette('), supplement.indexOf('END; $admission$;'));
  const fiche = sectionContrats('fn_admission_otp_signature_recette');
  for (const cle of ['admitted', 'can_send', 'can_validate', 'otp_expires_at', 'expires_at', 'remaining']) {
    assert.ok(corps.includes(`'${cle}'`), `témoin SQL : clé ${cle}`);
    assert.ok(fiche.includes(`\`${cle}\``), `fiche : clé ${cle} absente`);
  }
  assert.match(corps, /EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object\('admitted',false\);/);
  // Garde du web : URL STAGING exacte testée avant tout appel.
  const web = read('src/lib/signatureSmsStagingAdmission.ts');
  assert.ok(web.includes("const STAGING_URL = 'https://mejpriaetwgtcstbgfid.supabase.co';"));
  const garde = web.indexOf('url !== STAGING_URL');
  assert.ok(garde > 0 && garde < web.indexOf("client.rpc('fn_admission_otp_signature_recette'"), 'garde d URL STAGING après l appel');
  assert.ok(fiche.includes('mejpriaetwgtcstbgfid') && fiche.includes('PGRST202'), 'fiche : garde d environnement non consignée');
});

test('buildContracts : une RPC staging_seulement présente en production ou absente du supplément fait échouer la CI', () => {
  const base = {
    typesSource: read(SOURCES.types),
    schemaSource: read(SOURCES.schema),
    manifest: JSON.parse(read(SOURCES.manifest)),
  };
  assert.doesNotThrow(() => buildContracts(base));
  const enProduction = `${base.schemaSource}\nCREATE OR REPLACE FUNCTION "public"."fn_admission_otp_signature_recette"("p_contrat_id" "uuid") RETURNS "jsonb"\n    LANGUAGE "plpgsql"\n    AS $$\n`;
  assert.throws(() => buildContracts({ ...base, schemaSource: enProduction }), /production/);
  assert.throws(() => buildContracts({ ...base, lireSource: () => '-- supplément vide\n' }), /supplément/);
});

test('CONTRATS fn_scanner_code_pointage : exceptions de la RPC et des triggers de la première OUVERTURE, avec leur SQLSTATE', () => {
  const schema = read(SOURCES.schema);
  const scanner = sqlRaises(corpsSql(schema, enteteFn('fn_scanner_code_pointage')));
  assert.deepEqual(scanner, [
    { sqlstate: 'P0002', message: 'Code de pointage invalide ou expiré.' },
    { sqlstate: '42501', message: "Vous n'êtes pas assigné(e) à cette mission." },
    { sqlstate: '23514', message: 'Scan déjà pris en compte. Prochain scan possible dans % secondes.' },
    { sqlstate: '23514', message: 'Le contrat doit être signé avant le pointage.' },
    { sqlstate: '23514', message: 'Pointage trop tôt. Mission commence à %. Possible à partir de %.' },
    { sqlstate: 'P0002', message: 'Aucun créneau effectif ouvert à fermer.' },
    { sqlstate: '23514', message: 'La fin réelle doit être postérieure au début réel du créneau.' },
  ]);
  // Triggers déclenchés par la première OUVERTURE (INSERT presences, UPDATE missions → EN_COURS).
  assert.ok(schema.includes('CREATE OR REPLACE TRIGGER "dec_fenetre_pointage" BEFORE INSERT ON "public"."presences"'));
  assert.ok(schema.includes('CREATE OR REPLACE TRIGGER "trg_01_exiger_conformite_premier_pointage" BEFORE INSERT OR UPDATE OF "pointage_arrivee_le" ON "public"."presences"'));
  assert.ok(schema.includes('CREATE OR REPLACE TRIGGER "trg_01_exiger_conformite_mission_en_cours" BEFORE UPDATE OF "statut" ON "public"."missions"'));
  assert.ok(corpsSql(schema, enteteFn('trg_exiger_conformite_premier_pointage')).includes('public.fn_exiger_conformite_demarrage_mission('));
  const conformite = sqlRaises(corpsSql(schema, enteteFn('fn_exiger_conformite_demarrage_mission')));
  const fenetre = sqlRaises(corpsSql(schema, enteteFn('dec_fenetre_pointage')));
  assert.deepEqual(fenetre, [{ sqlstate: 'P0001', message: 'Pointage trop tôt. La mission commence à %.' }]);
  assert.deepEqual([...new Set(conformite.map(r => r.sqlstate))].sort(), ['22023', '23503', '23514', '42501']);
  const fiche = sectionContrats('fn_scanner_code_pointage');
  for (const { sqlstate, message } of [...scanner, ...conformite, ...fenetre]) {
    assert.ok(fiche.includes(message), `message absent de la fiche : « ${message} »`);
    assert.ok(fiche.includes(`\`${sqlstate}\``), `SQLSTATE ${sqlstate} absent de la fiche`);
  }
  // L'ensemble déclaré à l'interception (LOT2_PLAN §2.4) est exactement l'union observée.
  const union = [...new Set([...scanner, ...conformite, ...fenetre].map(r => r.sqlstate))].sort();
  assert.deepEqual(union, ['22023', '23503', '23514', '42501', 'P0001', 'P0002']);
  assert.ok(fiche.includes('`["P0001", "P0002", "22023", "23503", "23514", "42501"]`'), 'ensemble exceptionsMetier absent de la fiche');
  // Surcharge du web pour P0002, reprise en vouvoiement (décision 6).
  const rotatif = read('src/components/pointage/PointageRotatifSoignant.tsx');
  assert.ok(rotatif.includes("error.message === 'Code de pointage invalide ou expiré.'"));
  assert.ok(fiche.includes("Code de pointage invalide ou expiré. Demandez le code actuel à l'établissement."));
});

test('CONTRATS fn_scanner_code_pointage : nouveau_code renvoyé tant que B1 n est pas mergée, jamais lu par le natif', () => {
  const body = corpsSql(read(SOURCES.schema), enteteFn('fn_scanner_code_pointage'));
  // Bascule avec B1 (LOT2_PLAN §3 B1) : la PR B1 met à jour cette garde et la fiche dans la même PR.
  assert.ok(body.includes("'nouveau_code', v_new_code") && body.includes("'nouveau_hmac', v_new_hmac"),
    'nouveau_code n est plus renvoyé : B1 mergée, basculer la fiche « nouveau_code jamais lu » et cette garde');
  const fiche = sectionContrats('`fn_scanner_code_pointage` : `nouveau_code` jamais lu');
  assert.ok(fiche.includes('B1') && fiche.includes('liste blanche'), 'fiche nouveau_code : B1 / liste blanche absents');
  for (const cle of ['type_scan_effectue', 'prochain_type_scan', 'creneau_effectif_id', 'horodatage_effectif',
    'horodatage_arrondi', 'numero_scan', 'validation_etab_requise']) {
    assert.ok(body.includes(`'${cle}'`), `témoin SQL : clé ${cle}`);
    assert.ok(fiche.includes(`\`${cle}\``), `liste blanche : ${cle} absente de la fiche`);
  }
  assert.ok(!read('src/components/pointage/PointageRotatifSoignant.tsx').includes('nouveau_code'), 'le web lit nouveau_code');
  // Le code des sources Swift ne mentionne jamais ces clés (les tests peuvent les injecter pour prouver qu'elles sont ignorées).
  const fautes = swiftFiles(join(root, 'ios-native'))
    .filter(f => !f.includes('/Tests/') && !f.includes('/JoleneUITests/'))
    .filter(f => /nouveau_code|nouveau_hmac/.test(readFileSync(f, 'utf8')))
    .map(relatif);
  assert.deepEqual(fautes, []);
});

test('CONTRATS fn_etat_pointage_mission : clés de réponse et refus du dump, code_pointage_actif jamais décodé', () => {
  const body = corpsSql(read(SOURCES.schema), enteteFn('fn_etat_pointage_mission'));
  const fiche = sectionContrats('fn_etat_pointage_mission');
  assert.deepEqual(sqlErrors(body), ['Mission introuvable', 'Accès interdit']);
  for (const message of sqlErrors(body)) assert.ok(fiche.includes(`'${message}'`), `refus absent : ${message}`);
  for (const cle of ['statut', 'intitule', 'prochain_type_scan', 'nb_scans', 'segment_ouvert', 'segments', 'code_pointage_actif', 'est_etab']) {
    assert.ok(body.includes(`'${cle}'`), `témoin SQL : clé ${cle}`);
    assert.ok(fiche.includes(`\`${cle}\``), `clé ${cle} absente de la fiche`);
  }
  assert.match(body, /'code_pointage_actif', CASE WHEN v_is_etab THEN v_mission\.code_pointage_actif ELSE NULL END/);
  assert.ok(fiche.includes('jamais décodé'), 'code_pointage_actif : « jamais décodé » absent');
});

// Une forme de réponse = un test côté Swift : chaque refus, code et message du corps SQL figure dans la fiche.
const FICHES_CONFRONTEES = [
  'fn_consentir_gps', 'fn_relancer_validation_presence', 'fn_presences_detail_mission', 'fn_creer_notation_mission',
  'fn_demander_revue_document', 'fn_verifier_coherence_documents', 'fn_signer_attestation_sante',
  'fn_envoyer_otp_signature', 'fn_signer_contrat_otp', 'fn_remplacer_document_soignant',
];
test('CONTRATS lot 2 : refus, codes, messages et exceptions de chaque RPC confrontés au dump', () => {
  const schema = read(SOURCES.schema);
  const doc = read(DOC_CONTRATS);
  let total = 0;
  for (const name of FICHES_CONFRONTEES) {
    const body = corpsSql(schema, enteteFn(name));
    const fiche = aplati(section(doc, name));
    for (const message of [...sqlErrors(body), ...sqlMessages(body)]) {
      total++;
      assert.ok(fiche.includes(message), `${name} : « ${message} » absent de la fiche`);
    }
    for (const code of sqlErrorCodes(body)) {
      total++;
      assert.ok(fiche.includes(`\`${code}\``), `${name} : error_code ${code} absent de la fiche`);
    }
    for (const { sqlstate, message } of sqlRaises(body)) {
      total++;
      assert.ok(fiche.includes(message) && fiche.includes(`\`${sqlstate}\``), `${name} : exception ${sqlstate} « ${message} » absente`);
    }
    assert.ok(fiche.includes('**Contrat de réponse'), `${name} : section « Contrat de réponse » absente`);
  }
  // Témoin : les dix corps réunis portent plus de soixante formes ; une extraction vide passerait sans rien vérifier.
  assert.ok(total >= 60, `formes confrontées : ${total}`);
});

test('CONTRATS fn_ouvrir_litige_rate_limited : une sous-fiche par surcharge, appel du web à trois clés exactes', () => {
  const schema = read(SOURCES.schema);
  const ficheBrute = section(read(DOC_CONTRATS), 'fn_ouvrir_litige_rate_limited'); // brute : sous-sections lues ensuite
  const fiche = aplati(ficheBrute);
  const surcharges = [
    ['"p_mission_id" "uuid", "p_motif" "text")', '(uuid, text)'],
    ['"p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text")', '(uuid, type_litige, text)'],
    ['"p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text", "p_facture_id" "uuid")', '(uuid, type_litige, text, uuid)'],
  ];
  for (const [args, titre] of surcharges) {
    const body = corpsSql(schema, `${enteteFn('fn_ouvrir_litige_rate_limited')}${args}`);
    const sous = aplati(sousSection(ficheBrute, `Surcharge \`${titre}\``));
    for (const message of sqlErrors(body)) assert.ok(sous.includes(message), `${titre} : « ${message} » absent`);
  }
  // La surcharge à deux clés ouvre un litige AUTRE, dont la fenêtre est toujours ouverte.
  assert.ok(corpsSql(schema, `${enteteFn('fn_ouvrir_litige_rate_limited')}${surcharges[0][0]}`).includes("'AUTRE'::public.type_litige"));
  assert.match(corpsSql(schema, enteteFn('fn_fenetre_contestation_ouverte')), /IF p_type_litige IN \('SECURITE_DANGER', 'NON_PAIEMENT', 'AUTRE'\) THEN\s+RETURN TRUE;/);
  // Appel du web : trois clés exactes (surcharge canonique).
  const panneau = read('src/components/PanneauContestation.tsx');
  const appel = panneau.slice(panneau.indexOf("supabase.rpc('fn_ouvrir_litige_rate_limited'"), panneau.indexOf('if (error) throw error;', panneau.indexOf("supabase.rpc('fn_ouvrir_litige_rate_limited'")));
  assert.deepEqual([...appel.matchAll(/\b(p_[a-z_]+):/g)].map(m => m[1]), ['p_mission_id', 'p_type_litige', 'p_motif']);
  assert.ok(appel.includes("p_type_litige: 'DESACCORD_HEURES_POINTAGE'"));
  assert.ok(fiche.includes('trois clés exactes') && fiche.includes('PGRST203'), 'fiche : règle des trois clés absente');
});

test('CONTRATS fn_fenetre_contestation_ouverte : délai lu au serveur (défaut 48 h), aucune constante côté natif', () => {
  const body = corpsSql(read(SOURCES.schema), enteteFn('fn_fenetre_contestation_ouverte'));
  assert.match(body, /SELECT COALESCE\(valeur::integer, 48\) INTO v_delai_pointage\s+FROM public\.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';/);
  assert.match(body, /IF v_presence_validee IS NULL THEN RETURN TRUE; END IF;/);
  const fiche = sectionContrats('fn_fenetre_contestation_ouverte');
  for (const temoin of ['delai_contestation_pointage_h', '48 h', 'INVOKER', 'valide_le', 'fail-closed', 'HARD STOP']) {
    assert.ok(fiche.includes(temoin), `fiche fenêtre de contestation : ${temoin} absent`);
  }
  // Le web garde une constante client de 72 h (écart consigné, décision 9) : la fiche le dit.
  assert.ok(read('src/components/PanneauContestation.tsx').includes('const DELAI_CONTESTATION_MS = 72 * 60 * 60 * 1000;'));
  assert.ok(fiche.includes('DELAI_CONTESTATION_MS'));
});

test('Web : le système ① reste mort (sinon la décision 1 du lot 2 est à revoir)', () => {
  const presences = read('src/pages/PresencesSoignant.tsx');
  for (const fn of ['pointerArrivee', 'pointerDepart']) {
    const occurrences = presences.split(fn).length - 1;
    assert.equal(occurrences, 1, `${fn} : ${occurrences} occurrence(s) dans PresencesSoignant.tsx, définition seule attendue — revoir la décision 1`);
  }
  assert.ok(presences.includes('<BlocPointageMission'), 'BlocPointageMission n est plus monté');
  assert.ok(read('src/components/pointage/BlocPointageMission.tsx')
    .includes("import { PointageRotatifSoignant } from '@/components/pointage/PointageRotatifSoignant';"));
  const importeurs = motif => webFiles().filter(f => motif.test(readFileSync(f, 'utf8'))).map(relatif).sort();
  assert.deepEqual(importeurs(/from '[^']*\/CartePointage'/), [], 'CartePointage (système ①) est de nouveau importé');
  assert.deepEqual(importeurs(/from '[^']*\/qr-offline-queue'/), ['src/components/CartePointage.tsx']);
  // Le composant vivant n'appelle que le système rotatif, avec les clés p_metadata reprises par le natif.
  const rotatif = read('src/components/pointage/PointageRotatifSoignant.tsx');
  assert.deepEqual([...new Set([...rotatif.matchAll(/rpc\('([a-z0-9_]+)'/g)].map(m => m[1]))].sort(),
    ['fn_etat_pointage_mission', 'fn_scanner_code_pointage']);
  assert.ok(rotatif.includes('let meta: Record<string, unknown> = { id_terminal: genererIdTerminal() };'));
  assert.ok(rotatif.includes('meta = { ...meta, latitude: pos.lat, longitude: pos.lng, precision_gps_m: pos.precisionM };'));
  const fiche = sectionContrats('Interdit côté natif : système de pointage ①');
  for (const name of POINTAGE_SYSTEME_1) assert.ok(fiche.includes(`\`${name}\``), `fiche système ① : ${name} absente`);
  for (const temoin of ['qr-offline-queue.ts', 'SyncHorsLigne', '#664', 'contrat signé']) assert.ok(fiche.includes(temoin), `fiche système ① : ${temoin}`);
});

test('CONTRATS edge verify-document : chaque statut et chaque message de index.ts, un seul appel par document', () => {
  const index = read('supabase/functions/verify-document/index.ts');
  const fiche = sectionContrats('Edge `verify-document`');
  const messages = [...index.matchAll(/error:\s*(['"])((?:(?!\1).)+)\1/g)].map(m => m[2]);
  messages.push(...[...index.matchAll(/e\?\.message \|\| "([^"]+)"/g)].map(m => m[1]));
  messages.push(...[...index.matchAll(/throw new Error\("([^"$`]+)"\)/g)].map(m => m[1]));
  assert.ok(messages.length >= 12, `messages lus : ${messages.length}`);
  for (const message of new Set(messages)) assert.ok(fiche.includes(message), `message absent de la fiche : « ${message} »`);
  const statuts = new Set([...index.matchAll(/status:\s*(\d{3})/g)].map(m => m[1]));
  assert.deepEqual([...statuts].sort(), ['403', '409', '429', '500', '503']);
  for (const statut of ['200', '401', '403', '409', '429', '500', '503']) assert.ok(fiche.includes(`**${statut}**`), `statut ${statut} absent`);
  for (const verdict of ['VERIFIE', 'REJETE', 'EN_ATTENTE', 'REVUE_MANUELLE_REQUISE']) assert.ok(fiche.includes(`\`${verdict}\``), `verdict ${verdict}`);
  assert.ok(index.includes('verification_attempt_id') && fiche.includes('verification_attempt_id'));
  assert.ok(index.includes("applyRateLimit('verify-document', getClientIp(req), { max: 10, windowMs: 60_000 })"));
  assert.ok(fiche.includes('cleanup_orphan') && fiche.includes('une seule fois'));
  assert.match(read('supabase/config.toml'), /\[functions\.verify-document\]\nverify_jwt = false/);
  assert.ok(fiche.includes('verify_jwt = false'));
});

test('CONTRATS edge generate-contrat-mission-pdf : statuts, messages et codes de index.ts ; HTML, pas PDF', () => {
  const index = read('supabase/functions/generate-contrat-mission-pdf/index.ts');
  const fiche = sectionContrats('Edge `generate-contrat-mission-pdf`');
  const reponses = [...index.matchAll(/repondre\((\d{3}),\s*\{\s*error:\s*'([^']+)'/g)].map(m => [m[1], m[2]]);
  assert.ok(reponses.length >= 15, `réponses lues : ${reponses.length}`);
  for (const [statut, message] of reponses) {
    assert.ok(fiche.includes(`**${statut}**`), `statut ${statut} absent`);
    assert.ok(fiche.includes(message), `message absent : « ${message} »`);
  }
  for (const [, code] of index.matchAll(/code:\s*'([A-Z_]+)'/g)) assert.ok(fiche.includes(`\`${code}\``), `code ${code} absent`);
  for (const cle of ['contrat_id', 'storage_path', 'hash_document', 'signed_url', 'ttl_seconds']) assert.ok(fiche.includes(`\`${cle}\``), `clé ${cle}`);
  assert.ok(index.includes("{ contentType: 'text/html', upsert: false }") && fiche.includes('text/html'));
  assert.ok(index.includes("createSignedUrl(contrat.storage_path, 24 * 3600)") && fiche.includes('24 h'));
  assert.ok(fiche.includes('donnees_cdd'), 'fiche : aucun donnees_cdd côté soignant non consigné');
});

test('CONTRATS Storage du lot 2 : jolene-documents INSERT/SELECT sans UPDATE/DELETE client, contrats-signes SELECT', () => {
  const dir = join(root, 'supabase', 'migrations');
  const migrations = readdirSync(dir).filter(n => n.endsWith('.sql')).sort();
  /** Dernière instruction (CREATE ou DROP) qui vise une politique, par ordre des migrations. */
  const derniere = politique => {
    let etat = null;
    for (const m of migrations) {
      const sql = readFileSync(join(dir, m), 'utf8');
      for (const [, verbe] of sql.matchAll(new RegExp(`(CREATE|DROP) POLICY (?:IF EXISTS )?"?${politique}"?\\s+ON\\s+storage\\.objects`, 'g'))) etat = { verbe, m };
    }
    return etat;
  };
  for (const politique of ['pol_storage_jolene_insert', 'pol_storage_jolene_select', 'pol_contrats_signes_select']) {
    assert.equal(derniere(politique)?.verbe, 'CREATE', `${politique} : politique absente`);
  }
  for (const politique of ['pol_storage_jolene_update', 'pol_storage_jolene_delete']) {
    const etat = derniere(politique);
    assert.ok(etat === null || etat.verbe === 'DROP', `${politique} recréée par ${etat?.m} : la fiche Storage est à revoir`);
  }
  const fiche = sectionContrats('Storage du lot 2');
  for (const temoin of ['jolene-documents', 'contrats-signes', 'pol_storage_jolene_insert', 'pol_storage_jolene_select',
    'pol_contrats_signes_select', 'upsert: false', 'exists(path:)', '20260729143000']) {
    assert.ok(fiche.includes(temoin), `fiche Storage : ${temoin} absent`);
  }
});

test('CONTRATS : sources lues par la garde du lot 2 listées dans l en-tête', () => {
  const doc = read(DOC_CONTRATS);
  const entete = doc.slice(0, doc.indexOf('\n## Synthèse'));
  for (const source of [
    'src/components/pointage/PointageRotatifSoignant.tsx', 'src/components/SignerContratOtp.tsx',
    'src/lib/signatureSmsStagingAdmission.ts', 'scripts/ci/sms-signature-staging.sql',
    'supabase/functions/verify-document/index.ts', 'supabase/functions/generate-contrat-mission-pdf/index.ts',
    'src/pages/PresencesSoignant.tsx', 'src/components/PanneauContestation.tsx',
  ]) assert.ok(entete.includes(source), `en-tête : source ${source} non listée`);
  // Les MESSAGES_ERREUR du web cités par la fiche OTP existent toujours tels quels.
  const otp = read('src/components/SignerContratOtp.tsx');
  const fiche = aplati(section(doc, 'fn_envoyer_otp_signature'));
  for (const [, code, message] of otp.slice(otp.indexOf('const MESSAGES_ERREUR'), otp.indexOf('function messageDepuisCode')).matchAll(/([A-Z_]+): '((?:[^'\\]|\\')+)'/g)) {
    assert.ok(fiche.includes(`\`${code}\``) && fiche.includes(message.replaceAll("\\'", "'")), `MESSAGES_ERREUR ${code} absent de la fiche OTP`);
  }
});

test('DECISIONS_LOT2.md : vingt-cinq décisions dans l ordre, D-FLAGS, scission T2/T2b, attente de Gabrielle', () => {
  const decisions = read('docs/mobile-swift/DECISIONS_LOT2.md');
  const corps = section(decisions, 'Décisions (§7 du blueprint)');
  let from = 0;
  for (let i = 1; i <= 25; i++) {
    const at = corps.slice(from).search(new RegExp(`\\n${i}\\. \\*\\*`));
    assert.ok(at >= 0, `décision ${i} absente (ou hors ordre)`);
    from += at + 1;
  }
  assert.ok(!/\n26\. \*\*/.test(corps), 'décision 26 inattendue');
  const flags = section(decisions, 'D-FLAGS');
  for (const cle of ['ios_natif_presences_actif', 'ios_natif_documents_actif', 'ios_natif_contrats_actif', '20261102150000', 'fail-open', 'EcranNatif']) {
    assert.ok(flags.includes(cle), `D-FLAGS : ${cle} absent`);
  }
  const t2 = section(decisions, 'Scission T2 / T2b');
  assert.ok(t2.includes('W1') && t2.includes('documents-requis.ts') && t2.includes('presences-soignant-listes.ts'));
  const attente = section(decisions, 'En attente de Gabrielle');
  for (const point of ['HARD STOP n°4', 'B9', 'TL', 'T5b', 'T9b', 'delai_contestation_pointage_h', 'B1', 'S1', 'T11', 'fn_presences_detail_mission']) {
    assert.ok(attente.includes(point), `En attente de Gabrielle : ${point} absent`);
  }
  assert.ok(decisions.includes('LOT2_PLAN.md') && decisions.includes('LOTS_2_5_DECISIONS'), 'renvois au blueprint et au mandat absents');
});

test('LOT2_PLAN.md versionné : blueprint du 02/11/2026, vingt-cinq questions au §7', () => {
  const plan = read('docs/mobile-swift/LOT2_PLAN.md');
  assert.ok(plan.startsWith('# Blueprint du lot 2'), 'titre du blueprint absent');
  assert.ok(plan.includes('> Préparé le 2026-11-02'), 'en-tête « Préparé le 2026-11-02 » absent');
  const at = plan.indexOf('\n## 7. Décisions à prendre');
  assert.ok(at >= 0, '§7 absent');
  const s7 = plan.slice(at);
  for (let i = 1; i <= 25; i++) assert.ok(new RegExp(`\\n${i}\\. \\*\\*`).test(s7), `question ${i} absente du §7`);
});

test('RECETTE_DEVICE_LOT2.md : squelette P8 (QR, GPS, HEIC, caméra, Fichiers, arrêts forcés, OTP)', () => {
  const recette = read('docs/mobile-swift/RECETTE_DEVICE_LOT2.md');
  for (const point of ['QR', 'GPS refusé puis accordé', 'Position exacte', 'HEIC', 'caméra', 'Fichiers',
    'arrêt forcé pendant un scan', 'arrêt forcé pendant un envoi', 'signature OTP', 'npm run dev', 'signatures_contrats']) {
    assert.ok(recette.includes(point), `RECETTE_DEVICE_LOT2 : ${point} absent`);
  }
});

test('PARITE_SOIGNANT.md : lignes et sous-lignes du lot 2', () => {
  const parite = read('docs/mobile-swift/PARITE_SOIGNANT.md');
  for (const needle of [
    '| `/contrat/:id` (l.437) |', '| `/contrat/:id/certificat` (l.438) |',
    '`/soignant/mes-documents` › Justificatifs', '`/soignant/mes-documents` › Contrats', '`/soignant/mes-documents` › DPAE',
    '`/soignant/presences/mission/:id` › Récapitulatif financier', '`/soignant/presences` › Réponse et clôture de litige',
    '`/soignant/missions/:id` › Contrat de travail externe', '`/soignant/missions/:id` › Empêchement impérieux',
  ]) assert.ok(parite.includes(needle), `PARITE : « ${needle} » absent`);
  assert.ok(!parite.includes('pointage `fn_pointer_*` lot 2'), 'PARITE : pointage encore décrit par fn_pointer_* (décision 1)');
});

test('PRINCIPES §4 et plan : file hors ligne QR retirée, critères du lot 2 amendés par renvoi', () => {
  const principes = read('docs/mobile-swift/PRINCIPES.md');
  assert.ok(!principes.includes('La file hors-ligne QR garde la sémantique'), 'PRINCIPES §4 : ancienne phrase toujours présente');
  assert.ok(principes.includes('Aucun scan n\'est mis en file : le code rotatif est horodaté par le serveur ; un scan hors ligne est refusé avant envoi, un scan incertain est réconcilié par relecture de `scans_pointage`'));
  const plan = read('docs/PLAN_APP_NATIVE_SWIFT.md').split('\n');
  const amendees = plan.filter(l => l.includes('*(Amendé le 2026-11-02') && l.includes('DECISIONS_LOT2.md'));
  assert.ok(amendees.length >= 4, `lignes du plan amendées par DECISIONS_LOT2.md : ${amendees.length}`);
  for (const temoin of ['Le pointage web repose sur deux systèmes', 'Périmètre, pointage :', '- STAGING : scan de code rotatif', '- File hors-ligne testée']) {
    const ligne = plan.find(l => l.startsWith(temoin) || l.includes(temoin));
    assert.ok(ligne && ligne.includes('DECISIONS_LOT2.md'), `plan : « ${temoin} » non amendée`);
  }
});

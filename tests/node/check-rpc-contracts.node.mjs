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
  verifierExclusions,
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
    assert.ok(['lot0', 'a_venir', 'consommee'].includes(r.statut), `${r.name} : statut inconnu ${r.statut}`);
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

// Lot 4, T0 (LOT4_PLAN.md §3 T0) : une RPC « pas avant le lot 4 » peut être suivie, mais seulement
// avec `lot >= 4` (même règle que `verifierExclusions`) ; une RPC « jamais » ne l'est jamais.
test('RPC_SUIVIES : aucune RPC interdite, aucune RPC du lot 4 classée avant le lot 4', () => {
  for (const name of INTERDITES_NATIF) {
    assert.ok(!byName.has(name), `${name} ne doit pas figurer dans RPC_SUIVIES`);
  }
  for (const name of PAS_AVANT_LOT4) {
    const entry = byName.get(name);
    assert.ok(!entry || (Number.isInteger(entry.lot) && entry.lot >= 4), `${name} suivie avant le lot 4 (lot ${entry?.lot})`);
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

/**
 * Verdict sur un littéral `"fn_…"` du Swift au regard d'une liste de RPC suivies : `null` si l'appel est
 * autorisé, sinon le motif. Une RPC « jamais » est toujours interdite ; une RPC « pas avant le lot 4 »
 * n'est autorisée que suivie avec `lot >= 4` (règle de `verifierExclusions`, adaptée par le T0 du lot 4 :
 * sans elle, le littéral `"fn_retirer_candidature"` de la tranche T3a rougirait la CI même suivi en lot 4).
 */
function verdictLitteralSwift(name, suivies) {
  if (RPC_JAMAIS_SUIVIES.includes(name)) return 'interdite côté natif';
  const entry = suivies.find(r => r.name === name);
  if (RPC_PAS_AVANT_LOT4.includes(name) && !(entry && Number.isInteger(entry.lot) && entry.lot >= 4)) {
    return 'interdite côté natif avant le lot 4';
  }
  return entry ? null : 'absente de RPC_SUIVIES';
}

test('verdictLitteralSwift : une RPC « pas avant le lot 4 » est admise à partir de lot: 4, jamais avant', () => {
  const avec = lot => [{ name: 'fn_retirer_candidature', statut: 'a_venir', lot }];
  assert.equal(verdictLitteralSwift('fn_retirer_candidature', avec(4)), null);
  assert.equal(verdictLitteralSwift('fn_retirer_candidature', avec(5)), null);
  assert.match(verdictLitteralSwift('fn_retirer_candidature', avec(3)), /avant le lot 4/);
  assert.match(verdictLitteralSwift('fn_retirer_candidature', []), /avant le lot 4/);
  assert.match(verdictLitteralSwift('fn_etablissement_public', [{ name: 'fn_etablissement_public', lot: 4 }]), /interdite/);
  assert.match(verdictLitteralSwift('fn_inconnue', []), /absente/);
});

// Un gap connu reste verrouillé : un appel RPC écrit en dur dans le code Swift doit viser une
// RPC sous contrat, jamais une RPC interdite côté natif ni une RPC du lot 4 avant son heure.
test('ios-native : tout littéral "fn_…" du Swift est une RPC suivie et autorisée', () => {
  const fautes = [];
  for (const file of swiftFiles(join(root, 'ios-native'))) {
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/"(fn_[a-z0-9_]+)"/g)) {
      const rel = file.slice(root.length + 1);
      const verdict = verdictLitteralSwift(m[1], RPC_SUIVIES);
      if (verdict) fautes.push(`${rel} : ${m[1]} ${verdict}`);
    }
  }
  assert.deepEqual(fautes, []);
});

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Lot 4, tranche T0 (docs/mobile-swift/LOT4_PLAN.md §3 T0 ; décisions docs/mobile-swift/DECISIONS_LOT4.md).
// Les 42 RPC du lot 4 sont sous contrat avant toute gateway Swift ; chaque fiche cite toutes les
// réponses littérales du corps SQL (confrontées au dump, pas recopiées) ; les deux edges, le
// Realtime, le double-aveugle et les surcharges du litige ont leur fiche ; garde-fous 18 et 19.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// Ordre des tranches du lot 4 (LOT4_PLAN.md §3) : T3a swipe, T4 filtres, T5 disponibilités,
// T6 parrainage, T8 litiges et réclamations, T9 score et évaluations, T7a/T7b messagerie (et entrées
// du détail de mission, correction 20), T10 bulletins, T11 pool urgence et exclusions.
const LOT4 = [
  'fn_obtenir_missions_swipe', 'fn_enregistrer_swipe', 'fn_retirer_candidature', 'fn_initialiser_preferences_matching',
  'fn_lister_mes_filtres_sauvegardes', 'fn_creer_filtre_sauvegarde', 'fn_modifier_filtre_sauvegarde', 'fn_supprimer_filtre_sauvegarde',
  'fn_definir_disponibilite',
  'fn_obtenir_mes_parrainages', 'fn_appliquer_parrainage',
  'fn_ouvrir_litige_rate_limited', 'fn_ajouter_message_litige', 'fn_soumettre_reclamation',
  'fn_mon_breakdown_actuel', 'fn_mes_evenements_score', 'fn_evolution_score_soignant', 'fn_lister_notations_recues',
  'fn_creer_reclamation_score', 'fn_mes_notations_recues_avec_stats', 'fn_signaler_notation',
  'fn_lister_conversations_messagerie', 'fn_interlocuteurs_conversations', 'fn_marquer_messages_lus', 'fn_messages_non_lus',
  'fn_typing_start', 'fn_typing_stop', 'fn_update_presence', 'fn_est_bloque', 'fn_bloquer_utilisateur',
  'fn_debloquer_utilisateur', 'fn_signaler_utilisateur', 'fn_user_id_pour_etablissement', 'fn_obtenir_conversation',
  'fn_lister_copies_bulletins', 'fn_signaler_copie_bulletin',
  'fn_pool_urgence_missions_pour_soignant', 'fn_toggle_pool_urgence', 'fn_toggle_pool_urgence_sms',
  'fn_mes_exclusions_recues', 'fn_retirer_exclusion', 'fn_exclure_utilisateur',
];

// RPC du lot 4 absentes de `types.ts` (ou illisibles par `extractTypesSignature`) : `types: null` accepté
// (précédent du lot 1). `fn_ouvrir_litige_rate_limited` y figure (l.10147) mais en union de surcharges.
const LOT4_TYPES_NULL = [
  'fn_retirer_candidature', 'fn_initialiser_preferences_matching', 'fn_definir_disponibilite',
  'fn_ouvrir_litige_rate_limited', 'fn_lister_conversations_messagerie', 'fn_est_bloque', 'fn_bloquer_utilisateur',
  'fn_debloquer_utilisateur', 'fn_lister_copies_bulletins', 'fn_signaler_copie_bulletin',
];

/**
 * Corps SQL de chaque surcharge d'une fonction du dump : du `AS $$` qui suit le `CREATE OR REPLACE
 * FUNCTION` au `$$` qui le ferme. Contrairement à `sqlBody`, la fin est le premier `$$` et non la
 * première ligne `$$;` : deux corps du lot 4 tiennent sur une ligne (`… END; $$;`).
 */
function sqlBodiesAvecSignature(schema, name) {
  const prefix = `CREATE OR REPLACE FUNCTION "public"."${name}"(`;
  const out = [];
  for (let from = schema.indexOf(prefix); from >= 0; from = schema.indexOf(prefix, from + 1)) {
    const ligne = schema.slice(from, schema.indexOf('\n', from));
    const open = schema.indexOf('AS $$', from);
    const suivante = schema.indexOf('\nCREATE ', from + 1);
    assert.ok(open > from && (suivante < 0 || open < suivante), `${name} : corps sans « AS $$ » (dollar-quote nommé ?)`);
    const close = schema.indexOf('$$', open + 'AS $$'.length);
    assert.ok(close > open, `${name} : fin de corps introuvable`);
    out.push({ signature: ligne, body: schema.slice(open + 'AS $$'.length, close) });
  }
  assert.ok(out.length >= 1, `${name} absente de public.sql`);
  return out;
}

const unquoteSql = s => s.replaceAll("''", "'");
/**
 * Messages littéraux qu'un corps SQL peut renvoyer au client : `'error', '…'`, `'message', '…'`,
 * JSON `{"error":"…"}`, `RAISE EXCEPTION '…'` et `MESSAGE='…'`, apostrophes SQL doublées ramenées à la
 * valeur réelle.
 */
function messagesSql(body) {
  return [...new Set([
    ...[...body.matchAll(/'(?:error|message)',\s*'((?:[^']|'')*)'/g)].map(m => unquoteSql(m[1])),
    ...[...body.matchAll(/'\{"error":"([^"]+)"\}'::jsonb/gi)].map(m => m[1]),
    ...[...body.matchAll(/RAISE EXCEPTION '((?:[^']|'')*)'/g)].map(m => unquoteSql(m[1])),
    ...[...body.matchAll(/MESSAGE\s*=\s*'([^']+)'/g)].map(m => m[1]),
  ])];
}
const codesErreurSql = body => [...new Set([...body.matchAll(/'error_code',\s*'([A-Z_]+)'/g)].map(m => m[1]))];
const sqlstatesSql = body => [...new Set([...body.matchAll(/ERRCODE\s*=\s*'([0-9A-Z]{5})'/g)].map(m => m[1]))];
/** Messages levés avec le SQLSTATE 42501 : `RAISE EXCEPTION '…' USING ERRCODE = '42501'` ou `USING ERRCODE='42501',MESSAGE='…'`. */
function refus42501(body) {
  return [
    ...[...body.matchAll(/RAISE EXCEPTION '((?:[^']|'')*)' USING ERRCODE = '42501'/g)].map(m => unquoteSql(m[1])),
    ...[...body.matchAll(/ERRCODE='42501',\s*MESSAGE='([^']+)'/g)].map(m => m[1]),
  ];
}

/** Surcharges confrontées pour une RPC : toutes, sauf la 4 arguments du litige (jamais appelée, fiche dédiée). */
function corpsConfrontes(schema, name) {
  const all = sqlBodiesAvecSignature(schema, name);
  return name === 'fn_ouvrir_litige_rate_limited' ? all.filter(d => !d.signature.includes('"p_facture_id"')) : all;
}

const CONTRATS_DOC = 'docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md';

test('Lot 4 — RPC_SUIVIES : les 42 RPC du lot 4 suivies en a_venir lot 4, dans l ordre des tranches', () => {
  assert.equal(LOT4.length, 42);
  assert.equal(new Set(LOT4).size, 42);
  assert.deepEqual(RPC_SUIVIES.filter(r => r.lot === 4).map(r => r.name), LOT4);
  // Les statuts du lot 4 ne bougent qu'en T0 (a_venir) et en T15 (consommee, en une fois) : LOT4_PLAN §3.
  for (const name of LOT4) assert.deepEqual(byName.get(name), { name, statut: 'a_venir', lot: 4 });
});

test('Lot 4 — rpc-contracts.json : définition SQL SECURITY DEFINER, GRANT authenticated, types null attendus', () => {
  const actual = buildContracts({
    typesSource: read(SOURCES.types),
    schemaSource: read(SOURCES.schema),
    manifest: JSON.parse(read(SOURCES.manifest)),
  });
  const lot4 = actual.rpcs.filter(r => r.lot === 4);
  assert.equal(lot4.length, 42);
  for (const r of lot4) {
    assert.ok(r.sql.length >= 1, `${r.name} : aucune définition SQL`);
    assert.ok(r.grants.includes('authenticated'), `${r.name} : pas de GRANT authenticated`);
    assert.ok(r.sql.every(d => d.security === 'DEFINER'), `${r.name} : surcharge non SECURITY DEFINER`);
  }
  assert.deepEqual(lot4.filter(r => r.types === null).map(r => r.name).sort(), [...LOT4_TYPES_NULL].sort());
  assert.equal(lot4.find(r => r.name === 'fn_ouvrir_litige_rate_limited').sql.length, 3, 'les trois surcharges du litige sont sous contrat');
  const synthese = section(read(CONTRATS_DOC), 'Lot 4 — synthèse');
  for (const name of LOT4_TYPES_NULL) assert.ok(synthese.includes(`\`${name}\``), `synthèse lot 4 : ${name} (types null) non signalée`);
});

test('Lot 4 — confrontation : les extracteurs bornent les corps et lisent toutes les formes (témoins)', () => {
  const schema = read(SOURCES.schema);
  // Corps d'une ligne terminé par « END; $$; » : la fonction suivante du dump n'est pas lue.
  assert.deepEqual(messagesSql(corpsConfrontes(schema, 'fn_soumettre_reclamation')[0].body), ['Non authentifié', 'Rôle non autorisé']);
  assert.ok(!messagesSql(corpsConfrontes(schema, 'fn_signaler_utilisateur')[0].body).includes('Soignant introuvable'));
  // JSON littéral `'{"error":"…"}'::JSONB` et RAISE sans SQLSTATE.
  const parrainage = messagesSql(corpsConfrontes(schema, 'fn_appliquer_parrainage')[0].body);
  for (const m of ['Code de parrainage invalide', 'Vous avez déjà appliqué un code de parrainage', 'Attribution du parrain non persistée']) {
    assert.ok(parrainage.includes(m), `témoin parrainage : ${m}`);
  }
  // MESSAGE='…' et apostrophes doublées.
  assert.deepEqual(messagesSql(corpsConfrontes(schema, 'fn_signaler_copie_bulletin')[0].body), ['COPIE_ACCES_REFUSE', 'COPIE_MOTIF_INVALIDE']);
  assert.ok(messagesSql(corpsConfrontes(schema, 'fn_exclure_utilisateur')[0].body).includes("Impossible de s'exclure soi-même"));
  // Les deux surcharges confrontées du litige : wrapper 2 arguments et signature canonique 3 arguments.
  assert.equal(corpsConfrontes(schema, 'fn_ouvrir_litige_rate_limited').length, 2);
});

test('Lot 4 — CONTRATS : chaque fiche cite toutes les réponses littérales, codes et SQLSTATE de son corps SQL', () => {
  const schema = read(SOURCES.schema);
  const doc = read(CONTRATS_DOC);
  let total = 0;
  for (const name of LOT4) {
    const fiche = section(doc, `${name}\n`);
    assert.ok(fiche.includes('- **Statut natif** : à venir (lot 4'), `${name} : statut natif lot 4 absent`);
    for (const { body } of corpsConfrontes(schema, name)) {
      for (const message of messagesSql(body)) {
        total++;
        assert.ok(fiche.includes(message), `${name} : réponse absente de la fiche : « ${message} »`);
      }
      for (const code of codesErreurSql(body)) assert.ok(fiche.includes(`'${code}'`) || fiche.includes(`\`${code}\``), `${name} : error_code ${code} absent`);
      for (const etat of sqlstatesSql(body)) assert.ok(fiche.includes(`\`${etat}\``), `${name} : SQLSTATE ${etat} absent`);
    }
  }
  assert.ok(total >= 100, `réponses confrontées : ${total}`);
});

test('Lot 4 — CONTRATS : tout refus 42501 du lot 4 est un refus métier connu, jamais « session expirée »', () => {
  const schema = read(SOURCES.schema);
  const messages = new Set();
  for (const name of LOT4) for (const { body } of corpsConfrontes(schema, name)) for (const m of refus42501(body)) messages.add(m);
  // Témoins : fn_interlocuteurs_conversations, fn_marquer_messages_lus, fn_typing_start, fn_user_id_pour_etablissement,
  // fn_obtenir_conversation, fn_lister_copies_bulletins et fn_signaler_copie_bulletin.
  assert.deepEqual([...messages].sort(), ['Accès refusé', 'COPIE_ACCES_REFUSE', 'Compte inactif', 'Conversation non autorisée', 'NON_AUTORISE', 'Non autorisé'].sort());
  const fiche = section(read(CONTRATS_DOC), 'Lot 4 — lecture des exceptions PostgREST et des réponses edge');
  for (const m of messages) assert.ok(fiche.includes(`\`${m}\``), `42501 « ${m} » absent de la table d interception`);
  assert.ok(fiche.includes('`28000`') && fiche.includes('`.unauthorized`'), '28000 → .unauthorized non consigné');
  assert.ok(fiche.includes('`SupabaseErrorMapping.map`') && fiche.includes('exceptionsMetier:'), 'interception avant le mapping (surcharge exceptionsMetier:) non consignée');
  assert.ok(fiche.includes('`FunctionsError.httpError(code:data:)`') && fiche.includes('`EdgeResponse`'), 'corps des réponses edge non consigné');
  for (const etat of ['22023', '23514', 'P0001']) assert.ok(fiche.includes(`\`${etat}\``), `SQLSTATE ${etat} absent`);
});

test('Lot 4 — CONTRATS : actions SWIPE_LIKE et URGENCE de fn_confirmer_action_planning_v1 (délégués confrontés)', () => {
  const schema = read(SOURCES.schema);
  const planning = sqlBody(schema, 'fn_confirmer_action_planning_v1');
  // Témoins SQL : SWIPE_LIKE relaie p_choix_contrat ; URGENCE l'ignore (correction 10).
  assert.match(planning, /WHEN 'SWIPE_LIKE' THEN\s+RETURN public\.fn_enregistrer_swipe\(\s*p_mission_id,\s*'LIKE',\s*p_choix_contrat\s*\);/);
  assert.match(planning, /WHEN 'URGENCE' THEN\s+RETURN public\.fn_accepter_mission_urgence\(p_mission_id\);/);
  const urgence = corpsConfrontes(schema, 'fn_accepter_mission_urgence')[0].body;
  assert.match(urgence, /fn_resoudre_contrat_mission\(p_mission_id, v_uid, NULL\)/);
  const fiche = section(read(CONTRATS_DOC), 'Lot 4 — actions `SWIPE_LIKE` et `URGENCE` de `fn_confirmer_action_planning_v1`');
  for (const message of messagesSql(urgence)) assert.ok(fiche.includes(message), `URGENCE : réponse absente : « ${message} »`);
  for (const cle of ['EN_ATTENTE_VALIDATION_ETAB', 'choix_requis', 'documents_requis_pour', 'candidature_id', 'p_choix_contrat']) {
    assert.ok(fiche.includes(cle), `fiche SWIPE_LIKE/URGENCE : ${cle} absent`);
  }
  assert.ok(fiche.includes('pas de `success`'), 'SWIPE_LIKE répond {ok:…} sans success : non consigné');
});

test('Lot 4 — CONTRATS : edge messagerie-validate, chaque statut et chaque code de index.ts', () => {
  const fiche = section(read(CONTRATS_DOC), 'Edge `messagerie-validate`');
  const index = read('supabase/functions/messagerie-validate/index.ts');
  const statuts = [...new Set([...index.matchAll(/status:\s*(\d{3})/g)].map(m => m[1]))].sort();
  assert.deepEqual(statuts, ['200', '400', '401', '403', '405', '409', '413', '429', '500', '503']);
  const codes = new Set([
    ...[...index.matchAll(/error:\s*"([A-Z_]+)"/g)].map(m => m[1]),
    ...[...index.matchAll(/\|\|\s*"([A-Z_]+)"/g)].map(m => m[1]),
  ]);
  assert.ok(codes.size >= 13, `codes lus : ${codes.size}`);
  for (const statut of statuts) assert.ok(fiche.includes(`**${statut}**`), `statut ${statut} absent de la fiche`);
  for (const code of codes) assert.ok(fiche.includes(`\`${code}\``), `code ${code} absent de la fiche`);
  const types = read('supabase/functions/_shared/anti-leak.ts').match(/export type DetectedType = ([^;]+);/)[1];
  for (const [, t] of types.matchAll(/"([A-Z]+)"/g)) assert.ok(fiche.includes(`\`${t}\``), `detected_type ${t} absent`);
  assert.ok(read('supabase/config.toml').includes('[functions.messagerie-validate]\nverify_jwt = false'), 'témoin config.toml');
  for (const attendu of ['verify_jwt = false', 'fn_envoyer_message_valide', '`message_id`', '`max`', 'nonConfirme']) {
    assert.ok(fiche.includes(attendu), `fiche messagerie-validate : ${attendu} absent`);
  }
});

test('Lot 4 — CONTRATS : edge copies-bulletins, chaque code d erreur du handler et de fn_acces_copie_bulletin', () => {
  const fiche = section(read(CONTRATS_DOC), 'Edge `copies-bulletins`');
  const handler = read('supabase/functions/copies-bulletins/handler.ts');
  const table = handler.match(/const ERREURS[^=]*=\s*\{([\s\S]*?)\};/)[1];
  const paires = [...table.matchAll(/([A-Z_]+):\s*(\d{3})/g)].map(m => [m[1], m[2]]);
  paires.push(...[...handler.matchAll(/json\((\d{3}),\s*\{\s*error:\s*'([A-Z_]+)'/g)].map(m => [m[2], m[1]]));
  assert.match(handler, /'COPIE_SERVICE_INDISPONIBLE'[\s\S]*\|\| 503/);
  paires.push(['COPIE_SERVICE_INDISPONIBLE', '503']);
  assert.ok(paires.length >= 12, `codes lus : ${paires.length}`);
  for (const [code, statut] of paires) {
    assert.ok(fiche.includes(`\`${code}\``), `code ${code} absent de la fiche`);
    assert.ok(fiche.includes(`**${statut}**`), `statut ${statut} absent de la fiche`);
  }
  const acces = corpsConfrontes(read(SOURCES.schema), 'fn_acces_copie_bulletin')[0].body;
  for (const m of messagesSql(acces)) assert.ok(fiche.includes(`\`${m}\``), `fn_acces_copie_bulletin : ${m} absent`);
  for (const attendu of ['application/pdf', 'no-store', 'verify_jwt = true', 'SHA-256', 'telecharger']) {
    assert.ok(fiche.includes(attendu), `fiche copies-bulletins : ${attendu} absent`);
  }
});

test('Lot 4 — CONTRATS : fiche Realtime confrontée à la publication versionnée (conversations absente)', () => {
  const migration = read('supabase/migrations/20260729143000_reinstaller_dependances_auth_storage_apres_bootstrap.sql');
  const liste = migration.match(/FOREACH v_table IN ARRAY ARRAY\[([\s\S]*?)\]::text\[\]/)[1];
  const tables = [...liste.matchAll(/'([a-z_]+)'/g)].map(m => m[1]);
  assert.deepEqual(tables, ['messages_chat', 'messages_mission', 'notifications', 'presence_status', 'typing_status']);
  const schema = read(SOURCES.schema);
  const fiche = section(read(CONTRATS_DOC), 'Realtime : tables, RLS, filtres, cycle de vie');
  for (const table of tables) assert.ok(fiche.includes(`\`${table}\``), `table ${table} absente de la fiche`);
  for (const politique of ['pol_msg_select', 'pol_typing_status_select', 'pol_presence_status_select']) {
    assert.ok(schema.includes(`CREATE POLICY "${politique}"`), `témoin : politique ${politique} absente du dump`);
    assert.ok(fiche.includes(`\`${politique}\``), `politique ${politique} absente de la fiche`);
  }
  assert.ok(/`conversations`[^\n]*absente/.test(fiche), 'absence de `conversations` dans la publication non consignée');
  for (const attendu of ['pg_publication_tables', 'realtimeV2', 'subscribeWithError', 'removeAllChannels', 'UIBackgroundModes', 'fermerTout']) {
    assert.ok(fiche.includes(attendu), `fiche Realtime : ${attendu} absent`);
  }
});

test('Lot 4 — CONTRATS : double-aveugle, jamais notations_missions / evaluations / evaluations_publiees côté natif', () => {
  const schema = read(SOURCES.schema);
  const grants = [...schema.matchAll(/^GRANT [A-Z ,]+ ON TABLE "public"\."evaluations_publiees" TO "([a-z_]+)";$/gm)].map(m => m[1]);
  assert.deepEqual(grants, ['service_role'], 'témoin : evaluations_publiees accordée au seul service_role');
  for (const [name, attendu] of [['fn_mes_notations_recues_avec_stats', 5], ['fn_lister_notations_recues', 1]]) {
    const body = corpsConfrontes(schema, name)[0].body;
    const lectures = body.match(/FROM (?:public\.)?notations_missions n\b/g) ?? [];
    assert.equal(lectures.length, attendu, `${name} : lectures de notations_missions`);
    assert.equal((body.match(/n\.publie_le IS NOT NULL/g) ?? []).length, attendu, `${name} : filtre publie_le manquant sur une lecture`);
    assert.equal((body.match(/n\.masque = false/g) ?? []).length, attendu, `${name} : filtre masque manquant sur une lecture`);
  }
  const fiche = section(read(CONTRATS_DOC), 'Jamais `notations_missions` / `evaluations` / `evaluations_publiees` côté natif');
  for (const attendu of ['fn_mes_notations_recues_avec_stats', 'fn_lister_notations_recues', 'garde-fou 18', 'EvaluationsSourceGuardTests', 'service_role', 'publie_le IS NOT NULL']) {
    assert.ok(fiche.includes(attendu), `fiche double-aveugle : ${attendu} absent`);
  }
});

test('Lot 4 — CONTRATS : surcharges de fn_ouvrir_litige_rate_limited, seule la 3 arguments est appelée', () => {
  const schema = read(SOURCES.schema);
  const defs = sqlBodiesAvecSignature(schema, 'fn_ouvrir_litige_rate_limited');
  assert.equal(defs.length, 3);
  const quatre = defs.find(d => d.signature.includes('"p_facture_id"'));
  assert.ok(quatre && !quatre.signature.includes('DEFAULT'), 'la 4 arguments n a pas de défaut sur p_facture_id (aucune ambiguïté PostgREST)');
  assert.ok(schema.includes('COMMENT ON FUNCTION "public"."fn_ouvrir_litige_rate_limited"("p_mission_id" "uuid", "p_motif" "text") IS \'DEPRECATED'),
    'témoin : wrapper 2 arguments déprécié');
  const fiche = section(read(CONTRATS_DOC), 'Surcharges de `fn_ouvrir_litige_rate_limited` : seule la 3 arguments est appelée');
  for (const attendu of ['"p_type_litige" "public"."type_litige"', '"p_facture_id" "uuid"', 'DEPRECATED', 'AUTRE', 'jamais appelée']) {
    assert.ok(fiche.includes(attendu), `fiche surcharges : ${attendu} absent`);
  }
});

test('Lot 4 — CONTRATS : classement manuel des RPC hors manifeste (modèle lot 1 décision 6), synthèse complète', () => {
  const expected = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  const doc = read(CONTRATS_DOC);
  for (const name of ['fn_lister_copies_bulletins', 'fn_signaler_copie_bulletin']) {
    assert.equal(expected.rpcs.find(r => r.name === name)?.manifeste, null, `${name} : le JSON garde le fait observé (hors manifeste)`);
    const classe = section(doc, `${name}\n`).split('\n').find(l => l.startsWith("- **Classe d'authentification (manifeste)**"));
    assert.ok(classe && classe.includes('`RPC_UTILISATEUR_AUTH_INTERNE`') && classe.includes('classement manuel'), `${name} : classement manuel absent`);
  }
  const synthese = section(doc, 'Lot 4 — synthèse');
  for (const name of LOT4) assert.ok(synthese.includes(`| \`${name}\` |`), `synthèse lot 4 : ligne ${name} absente`);
});

test('Lot 4 — guards.sh : garde-fous 18 (aucun lecteur natif de notations) et 19 (aucun envoi hors edge)', () => {
  const guards = read('tests/non-regression/guards.sh');
  const bloc = n => {
    const at = guards.indexOf(`echo "── Garde-fou ${n} :`);
    assert.ok(at >= 0, `garde-fou ${n} absent`);
    const next = guards.indexOf('echo "── Garde-fou ', at + 1);
    return guards.slice(at, next < 0 ? guards.indexOf('\nif [ "$FAIL" -ne 0 ]', at) : next);
  };
  const motif = (texte, nom) => {
    const m = texte.match(new RegExp(`${nom}='([^']+)'`));
    assert.ok(m, `variable ${nom} absente`);
    return new RegExp(m[1]);
  };
  const b18 = bloc(18);
  assert.ok(b18.includes('ios-native/Packages') && b18.includes('ios-native/Jolene') && b18.includes('FAIL=1'));
  const notations = motif(b18, 'MOTIF_NOTATIONS');
  for (const lecteur of ['.from("notations_missions")', 'table: "evaluations"', '.from("evaluations_publiees")']) assert.ok(notations.test(lecteur), `18 : ${lecteur} non détecté`);
  for (const licite of ['"total_evaluations"', '"ios_natif_\\(rawValue)_actif"', '"fn_mes_notations_recues_avec_stats"']) assert.ok(!notations.test(licite), `18 : faux positif ${licite}`);
  const b19 = bloc(19);
  assert.ok(b19.includes('ios-native/') && b19.includes('FAIL=1'));
  const envoi = motif(b19, 'MOTIF_ENVOI');
  for (const appel of ['rpc("fn_envoyer_message", params:', '"fn_envoyer_message_valide"', 'fn_envoyer_message']) assert.ok(envoi.test(appel), `19 : ${appel} non détecté`);
  assert.ok(!envoi.test('"fn_envoyer_message_contact"'), '19 : le formulaire de contact n est pas un envoi de messagerie');
  assert.ok(guards.includes('les 19 garde-fous passent') && !guards.includes('les 17 garde-fous'), 'message final non mis à jour');
  // Aucun motif affaibli : les 17 premiers garde-fous restent présents.
  for (let n = 1; n <= 17; n++) assert.ok(guards.includes(`echo "── Garde-fou ${n} :`), `garde-fou ${n} disparu`);
  // Fail-closed dès aujourd'hui sur le Swift du dépôt.
  for (const dir of ['ios-native/Packages', 'ios-native/Jolene']) {
    for (const file of swiftFiles(join(root, dir))) assert.ok(!notations.test(readFileSync(file, 'utf8')), `${file} lit une table de notations`);
  }
  for (const file of swiftFiles(join(root, 'ios-native'))) assert.ok(!envoi.test(readFileSync(file, 'utf8')), `${file} envoie un message hors edge`);
});

test('Lot 4 — PARITE : statuts proposés de LOT4_PLAN §1.3 marqués « proposé — à signer », onze parcours cœur', () => {
  const parite = read('docs/mobile-swift/PARITE_SOIGNANT.md');
  const s = section(parite, 'Lot 4 — statuts proposés');
  const routes = [
    '/soignant/swipe-missions', '/soignant/disponibilites', '/soignant/mandat-facturation', '/soignant/score',
    '/soignant/evaluations', '/soignant/prevoyance', '/soignant/attestation-heures', '/soignant/passer-en-liberal',
    '/soignant/exclusions', '/soignant/premium', '/soignant/charges', '/soignant/parrainage', '/soignant/messagerie',
    '/soignant/litiges', '/soignant/classement', '/soignant/parametres/recherches-sauvegardees', '/soignant/pool-urgence',
    '/soignant/missions/serie/:serieId', '/soignant/mes-gains?tab=bulletins', '/soignant/mes-gains?tab=avances',
    '/soignant/missions/:id', '/soignant/recherche-missions?vue=swipe',
  ];
  const lignes = s.split('\n').filter(l => l.startsWith('| `/soignant/'));
  for (const route of routes) {
    const ligne = lignes.find(l => l.startsWith(`| \`${route}\``));
    assert.ok(ligne, `ligne lot 4 absente : ${route}`);
    assert.ok(ligne.includes('proposé — à signer'), `${route} : statut non marqué « proposé — à signer »`);
    assert.ok(!/abandonné/.test(ligne), `${route} : « abandonné » exige une décision écrite de Gabrielle`);
  }
  const at = s.indexOf('Onze parcours cœur');
  assert.ok(at >= 0, 'liste des onze parcours cœur absente');
  const parcours = s.slice(at);
  for (let i = 1; i <= 11; i++) assert.ok(new RegExp(`\\n${i}\\. \\*\\*`).test(parcours), `parcours cœur ${i} absent`);
  assert.ok(!/\n12\. \*\*/.test(parcours), 'douzième parcours inattendu');
  // T0 ne statue rien : aucune ligne du tableau principal ciblant le lot 4 n'est passée « natif ».
  const principal = parite.slice(0, parite.indexOf('\n## '));
  for (const l of principal.split('\n').filter(x => /^\| `\/soignant\//.test(x))) {
    const cols = l.split('|').map(c => c.trim());
    if (/^4\b/.test(cols[4] ?? '')) assert.ok(!/^natif\b/.test(cols[3]), `ligne lot 4 statuée avant les preuves : ${cols[1]}`);
  }
});

test('Lot 4 — DECISIONS_LOT4.md : §7 tranché (D1 à D27), « En attente de Gabrielle » = §6 (10 points)', () => {
  const dec = read('docs/mobile-swift/DECISIONS_LOT4.md');
  const s7 = section(dec, 'Décisions §7');
  let from = 0;
  for (let i = 1; i <= 27; i++) {
    const at = s7.slice(from).search(new RegExp(`\\n${i}\\. \\*\\*D${i} `));
    assert.ok(at >= 0, `décision D${i} absente ou hors ordre`);
    from += at + 1;
    const ligne = s7.slice(from).split('\n')[0];
    assert.ok(/Adoptée/.test(ligne), `D${i} : verdict « Adoptée » absent`);
  }
  assert.ok(!/\n28\. \*\*/.test(s7), 'décision 28 inattendue');
  const attente = section(dec, 'En attente de Gabrielle');
  for (let i = 1; i <= 10; i++) assert.ok(new RegExp(`\\n${i}\\. \\*\\*`).test(attente), `point §6.${i} absent`);
  for (const attendu of ['B1', 'T14', 'T6-HS', 'HARD STOP n°4', 'pg_publication_tables', 'PARITE_SOIGNANT.md']) {
    assert.ok(attente.includes(attendu), `En attente : ${attendu} absent`);
  }
  for (const attendu of ['LOT4_PLAN.md', 'LOT1_PLAN.md', 'ios_natif_exclusions_actif', 'ios_natif_serie_actif', 'jamais mergée']) {
    assert.ok(dec.includes(attendu), `DECISIONS_LOT4 : ${attendu} absent`);
  }
});

test('Lot 4 — LOT4_PLAN.md versionné, squelettes RECETTE_DEVICE_LOT4 et BETA_LOT4', () => {
  const plan = read('docs/mobile-swift/LOT4_PLAN.md');
  for (const attendu of ['# Blueprint du lot 4', '### T0 — Contrats et documentation du lot 4', '## 6. Ce qui exige Gabrielle', '## 7. Décisions à prendre', 'DECISIONS_LOT4.md']) {
    assert.ok(plan.includes(attendu), `LOT4_PLAN.md : ${attendu} absent`);
  }
  const recette = read('docs/mobile-swift/RECETTE_DEVICE_LOT4.md');
  for (const attendu of ['Realtime', 'arrière-plan', 'coupure réseau', 'WhatsApp', 'QR', 'Fichiers', 'VoiceOver', 'Signature de clôture']) {
    assert.ok(recette.includes(attendu), `RECETTE_DEVICE_LOT4.md : ${attendu} absent`);
  }
  const beta = read('docs/mobile-swift/BETA_LOT4.md');
  for (const attendu of ['bloquant', 'non bloquant', '14 jours', '400 sessions', '99,5 %', 'Beta App Review']) {
    assert.ok(beta.includes(attendu), `BETA_LOT4.md : ${attendu} absent`);
  }
});

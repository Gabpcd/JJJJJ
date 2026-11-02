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
// STAGING) ; le nom d'établissement vient exclusivement de fn_etablissements_safe. Lot 3 (T0) :
// fn_lier_iban_verifie_document, service_role seul (garde détaillée : check-rpc-contracts-lot3.node.mjs).
const INTERDITES_NATIF = ['fn_etablissement_public', 'fn_lier_iban_verifie_document'];
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
test('ios-native : tout littéral "fn_…" du Swift est une RPC suivie et autorisée', () => {
  const suivies = new Set(RPC_SUIVIES.map(r => r.name));
  const interdites = new Set([...RPC_JAMAIS_SUIVIES, ...RPC_PAS_AVANT_LOT4]);
  const fautes = [];
  for (const file of swiftFiles(join(root, 'ios-native'))) {
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/"(fn_[a-z0-9_]+)"/g)) {
      const rel = file.slice(root.length + 1);
      if (interdites.has(m[1])) fautes.push(`${rel} : ${m[1]} interdite côté natif`);
      else if (!suivies.has(m[1])) fautes.push(`${rel} : ${m[1]} absente de RPC_SUIVIES`);
    }
  }
  assert.deepEqual(fautes, []);
});

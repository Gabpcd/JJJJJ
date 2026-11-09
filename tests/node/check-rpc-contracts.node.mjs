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
// Chaque tranche qui câble une gateway passe sa RPC en `consommee` et l'ajoute à LOT1_CONSOMMEES.
const LOT1_CONSOMMEES = ['fn_dashboard_soignant_complet']; // T3
// `fn_suggestions_missions_pour_soignant` en est sortie (revue B8 de T3) : reclassée lot 4.
const LOT1 = [
  'fn_dashboard_soignant_complet',
  'fn_confirmer_action_planning_v1',
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

test('RPC_SUIVIES : toutes les RPC du lot 1 sont suivies en lot 1, a_venir sauf celles déjà câblées', () => {
  for (const name of LOT1) {
    const entry = byName.get(name);
    assert.ok(entry, `${name} absente de RPC_SUIVIES (lot 1, T0)`);
    const attendu = LOT1_CONSOMMEES.includes(name) ? 'consommee' : 'a_venir';
    assert.equal(entry.statut, attendu, `${name} : statut attendu ${attendu}`);
    assert.equal(entry.lot, 1, `${name} : lot attendu 1`);
  }
});

test('RPC_SUIVIES : fn_mon_profil_soignant_complet est reclassée lot 3 (correction v2 n°4)', () => {
  assert.deepEqual(byName.get('fn_mon_profil_soignant_complet'), {
    name: 'fn_mon_profil_soignant_complet', statut: 'a_venir', lot: 3,
  });
});

test('RPC_SUIVIES : fn_suggestions_missions_pour_soignant est reclassée lot 4 (revue B8 de T3)', () => {
  assert.deepEqual(byName.get('fn_suggestions_missions_pour_soignant'), {
    name: 'fn_suggestions_missions_pour_soignant', statut: 'a_venir', lot: 4,
  });
  // Motif : son seul appelant web n'est monté par aucune page ; l'Accueil natif ne la consomme pas.
  const appelant = read('src/components/dashboard/SuggestionsMissions.tsx');
  assert.ok(appelant.includes("'fn_suggestions_missions_pour_soignant'"), 'appelant web attendu : SuggestionsMissions.tsx');
  const dashboard = read('src/pages/DashboardSoignant.tsx');
  assert.ok(!dashboard.includes('SuggestionsMissions'),
    'DashboardSoignant monte désormais SuggestionsMissions : revoir le reclassement (parité de l Accueil)');
  const fiche = section(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'), 'fn_suggestions_missions_pour_soignant');
  assert.ok(fiche.includes('à venir (lot 4)'), 'fiche : statut « à venir (lot 4) » attendu');
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
/** Sources et fixtures texte (`.swift`, `.json`) d'un dossier, hors `.build` et dossiers cachés. */
function fichiersTexte(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    if (name === '.build' || name === 'DerivedData' || name.startsWith('.')) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...fichiersTexte(full));
    else if (/\.(swift|json)$/.test(name)) out.push(full);
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
// `fn_generer_code_secours_mission` (générateur du code de secours, `QRPointageEtab`, non monté) y entre par
// l'amendement de la décision 1 (revue fraîche de T0 : troisième chaîne de pointage à distance).
const POINTAGE_SYSTEME_1 = [
  'fn_pointer_arrivee', 'fn_pointer_depart', 'fn_pointer_debut_pause', 'fn_pointer_fin_pause',
  'fn_valider_scan_qr', 'fn_generer_qr_mission', 'fn_valider_code_secours', 'fn_codes_pointage_mission',
  'fn_generer_code_secours_mission',
];
const SUPPLEMENT_SMS = 'scripts/ci/sms-signature-staging.sql';
// Suffixe des messages d'échec des gardes confrontées à des sources de `main` (dump, web) : où et quand basculer.
const BASCULE_MAIN = 'basculer au merge de main dans feat/ios-lot2 qui amène la re-baseline du dump ou la PR web (ou dans cette PR elle-même si T0 est déjà sur main) — DECISIONS_LOT2.md « Ordonnancement et branches »';
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

test('RPC_POINTAGE_SYSTEME_1 : neuf RPC du système ①, jamais suivies, présentes au dump, refusées par verifierExclusions', () => {
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
  assert.ok(read('src/components/PanneauContestation.tsx').includes("supabase.rpc('fn_creer_notification'"),
    `le web n appelle plus fn_creer_notification : fiche « Interdite côté natif : fn_creer_notification » et constat B9 à ${BASCULE_MAIN}`);
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
  // Surcharge du web pour P0002, reprise en vouvoiement (décision 6) : seule la personne du verbe change
  // (« Demande » → « Demandez »), apostrophe typographique ’ du web comprise. T4b affiche exactement cette forme.
  const rotatif = read('src/components/pointage/PointageRotatifSoignant.tsx');
  const surcharge = rotatif.match(/error\.message === 'Code de pointage invalide ou expiré\.'\s*\?\s*'([^']+)'/);
  assert.ok(surcharge, 'surcharge P0002 introuvable dans PointageRotatifSoignant.tsx : revoir la décision 6 et la fiche');
  const web = surcharge[1];
  assert.equal(web, 'Code de pointage invalide ou expiré. Demande le code actuel à l’établissement.',
    'surcharge P0002 du web modifiée : revoir la décision 6 et la fiche');
  const natif = web.replace('Demande le code', 'Demandez le code');
  assert.notEqual(natif, web);
  const decisions = aplati(read('docs/mobile-swift/DECISIONS_LOT2.md'));
  for (const [nom, texte] of [['fiche fn_scanner_code_pointage', fiche], ['DECISIONS_LOT2.md', decisions]]) {
    assert.ok(texte.includes(`« ${natif} »`), `${nom} : forme vouvoyée exacte absente (« ${natif} »)`);
    assert.ok(!texte.includes("Demandez le code actuel à l'établissement"), `${nom} : apostrophe ASCII, le web écrit ’`);
  }
});

test('CONTRATS fn_scanner_code_pointage : nouveau_code retiré par B1 (#1117), jamais lu par le natif', () => {
  const body = corpsSql(read(SOURCES.schema), enteteFn('fn_scanner_code_pointage'));
  // Bascule faite (intégration du lot 2, 8 novembre 2026) : B1 est mergée sur `main` (#1117) et le dump re-baseliné ne
  // renvoie plus le code suivant ; la garde a basculé au merge de `main` dans `feat/ios-lot2`, comme prévu par
  // DECISIONS_LOT2.md « Ordonnancement et branches ». Elle rougit désormais sur un retour arrière de B1.
  assert.ok(!body.includes("'nouveau_code'") && !body.includes("'nouveau_hmac'"),
    'fn_scanner_code_pointage renvoie de nouveau nouveau_code ou nouveau_hmac (retour arrière de B1 ?) : revoir la fiche « nouveau_code jamais lu » de CONTRATS_RPC_SOIGNANT.md et le décodeur en liste blanche');
  const fiche = sectionContrats('`fn_scanner_code_pointage` : `nouveau_code` jamais lu');
  assert.ok(fiche.includes('B1') && fiche.includes('liste blanche'), 'fiche nouveau_code : B1 / liste blanche absents');
  assert.ok(fiche.includes('**B1 est mergée sur `main`** (#1117') && fiche.includes('**Bascule faite**'),
    'fiche nouveau_code : merge de B1 (#1117) et bascule de la garde non consignés');
  // Revue de T0 : une bascule « dans la PR B1 » est irréalisable tant que T0 n'est pas sur `main`. Le tableau
  // « Amendements du blueprint » de DECISIONS_LOT2.md cite la formulation amendée : il est exclu du contrôle.
  const decisions = read('docs/mobile-swift/DECISIONS_LOT2.md');
  const horsAmendements = aplati(decisions.replace(section(decisions, 'Amendements du blueprint'), ''));
  for (const [nom, texte] of [['fiche nouveau_code', fiche], ['DECISIONS_LOT2.md', horsAmendements]]) {
    assert.ok(texte.includes('merge de `main` dans `feat/ios-lot2`') && texte.includes('re-baseline'), `${nom} : moment de la bascule B1 absent`);
    assert.ok(!texte.includes('dans la même PR') && !texte.includes('B1 se merge après T0') && !texte.includes('mergée après T0'),
      `${nom} : bascule « dans la PR B1 » irréalisable (B1 vise main)`);
  }
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
  // Revue fraîche de T0 : `est_etab` vaut JSON null pour tout compte sans établissement (false OR NULL = NULL),
  // soignant assigné compris, et jamais false pour lui : un décodage en Bool non optionnel échouerait sur 100 % des
  // réponses réelles. `est_admin()` rend un booléen non nul (COALESCE), `mon_etablissement_id()` NULL hors établissement.
  assert.ok(body.includes('v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id();'),
    `fn_etat_pointage_mission : affectation de v_is_etab changée — fiche (est_etab null côté soignant), consigne T3 et « Motif à auditer » : ${BASCULE_MAIN}`);
  assert.ok(body.includes("'est_etab', v_is_etab"), `fn_etat_pointage_mission : est_etab n est plus renvoyé tel quel — fiche et consigne T3 : ${BASCULE_MAIN}`);
  assert.ok(corpsSql(read(SOURCES.schema), enteteFn('est_admin_valide')).includes('SELECT COALESCE(EXISTS ('), 'est_admin_valide : plus de COALESCE');
  for (const temoin of ['est_etab vaut null pour tout compte sans établissement (soignant assigné compris), jamais false ; non décodé côté soignant',
    'jamais décodé côté soignant', '`Bool?`']) {
    assert.ok(fiche.includes(temoin), `fiche fn_etat_pointage_mission : « ${temoin} » absent`);
  }
  // Clôture de T0 : garde sur les deux lignes SQL citées par la fiche, l'affectation de v_is_etab et le renvoi de
  // est_etab. La fiche cite leurs numéros exacts au dump ; un décalage (re-baseline) ou une correction de la garde
  // (PR B9 des gardes NULL : `COALESCE`, est_etab deviendrait false) la fait rougir.
  const lignesDump = read(SOURCES.schema).split('\n');
  const enteteEtat = lignesDump.findIndex(l => l.startsWith(enteteFn('fn_etat_pointage_mission')));
  assert.ok(enteteEtat >= 0, 'fn_etat_pointage_mission absente du dump');
  const numeros = ['v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id();', "'est_etab', v_is_etab"]
    .map(sql => {
      const i = lignesDump.findIndex((l, n) => n > enteteEtat && l.trim() === sql);
      assert.ok(i > enteteEtat, `fn_etat_pointage_mission : ligne « ${sql} » absente du dump — fiche (est_etab) et consigne T3 : ${BASCULE_MAIN}`);
      return i + 1;
    });
  for (const n of numeros) {
    assert.ok(fiche.includes(`l.${n}`), `fiche fn_etat_pointage_mission : ligne SQL l.${n} non citée (numéros du dump décalés ?) : ${BASCULE_MAIN}`);
  }
  assert.ok(fiche.includes(`garde \`tests/node/check-rpc-contracts.node.mjs\` sur l.${numeros[0]} et l.${numeros[1]}`),
    `fiche fn_etat_pointage_mission : garde sur l.${numeros[0]} et l.${numeros[1]} non annoncée`);
  const consignes = aplati(section(read('docs/mobile-swift/DECISIONS_LOT2.md'), 'Consignes aux tranches suivantes'));
  assert.ok(consignes.includes('**T3**') && consignes.includes('`est_etab: null`') && consignes.includes('fn_etat_pointage_mission'),
    'consigne T3 (stubs et fixtures de fn_etat_pointage_mission avec est_etab: null) absente');
  // Aucun stub ni fixture soignant ne pose `est_etab: false` (forme que le serveur ne renvoie jamais à un soignant).
  const fixtures = [join(root, 'scripts/mobile/export-demo-fixtures.mjs'), ...fichiersTexte(join(root, 'ios-native'))];
  const fautes = fixtures.filter(f => /"?est_etab"?\s*[:=]\s*false\b/.test(readFileSync(f, 'utf8'))).map(relatif);
  assert.deepEqual(fautes, [], 'est_etab: false dans un stub ou une fixture : le serveur renvoie null à un soignant (consigne T3)');
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
  // Rejoueur ① encore monté (revue de T0) : `SyncHorsLigne` (LayoutApp) rejoue `fn_pointer_*` depuis la file de
  // `src/lib/horsLigne.ts`, alimentée seulement par `stockerPointageHorsLigne`, elle-même appelée uniquement dans
  // pointerArrivee / pointerDepart (morts). Un nouvel appelant remettrait ① en service sans signal.
  const usages = motif => webFiles().filter(f => motif.test(readFileSync(f, 'utf8'))).map(relatif).sort();
  assert.deepEqual(usages(/\bstockerPointageHorsLigne\b/), ['src/lib/horsLigne.ts', 'src/pages/PresencesSoignant.tsx'],
    'stockerPointageHorsLigne : nouvel importeur — revoir la décision 1');
  const corpsFleche = nom => {
    const debut = presences.indexOf(`\n  const ${nom} = async (`);
    assert.ok(debut >= 0, `${nom} introuvable dans PresencesSoignant.tsx (extraction W1 ou retrait du code mort ?) : garde et fiche ① à ${BASCULE_MAIN}`);
    const fin = presences.indexOf('\n  };\n', debut);
    assert.ok(fin > debut, `${nom} : fin de corps introuvable`);
    return [debut, fin];
  };
  const bornes = ['pointerArrivee', 'pointerDepart'].map(corpsFleche);
  const appels = [...presences.matchAll(/\bstockerPointageHorsLigne\(/g)].map(m => m.index);
  assert.equal(appels.length, 2, `stockerPointageHorsLigne : ${appels.length} appel(s) dans PresencesSoignant.tsx, 2 attendus`);
  for (const at of appels) {
    assert.ok(bornes.some(([d, f]) => at > d && at < f), 'stockerPointageHorsLigne appelée hors de pointerArrivee / pointerDepart — revoir la décision 1');
  }
  assert.deepEqual(usages(/from '[^']*\/horsLigne'/), ['src/components/SyncHorsLigne.tsx', 'src/pages/PresencesSoignant.tsx'],
    `importeurs de horsLigne changés (retrait du rejoueur ① ?) : fiche ①, constat B9 et « Points consignés hors lot 2 » à ${BASCULE_MAIN}`);
  assert.deepEqual(usages(/from '[^']*\/SyncHorsLigne'/), ['src/components/LayoutApp.tsx'],
    `SyncHorsLigne n est plus monté par LayoutApp : fiche ① et constat B9 à ${BASCULE_MAIN}`);
  // Code de secours (amendement de la décision 1) : le générateur n'est appelé que par `QRPointageEtab` (importé par
  // aucun écran, seulement par un test) et la saisie que par `SaisieCodeSecours` (montée par `CartePointage`, mort).
  const appelants = rpc => webFiles().filter(f => readFileSync(f, 'utf8').includes(`rpc('${rpc}'`)).map(relatif).sort();
  assert.deepEqual(appelants('fn_generer_code_secours_mission'), ['src/components/etablissement/QRPointageEtab.tsx']);
  assert.deepEqual(appelants('fn_valider_code_secours'), ['src/components/soignant/SaisieCodeSecours.tsx']);
  assert.deepEqual(importeurs(/from '[^']*\/QRPointageEtab'/), [], 'QRPointageEtab (code de secours, système ①) est de nouveau monté — revoir la décision 1');
  assert.deepEqual(importeurs(/from '[^']*\/SaisieCodeSecours'/), ['src/components/CartePointage.tsx']);
  const fiche = sectionContrats('Interdit côté natif : système de pointage ①');
  for (const name of POINTAGE_SYSTEME_1) assert.ok(fiche.includes(`\`${name}\``), `fiche système ① : ${name} absente`);
  for (const temoin of ['qr-offline-queue.ts', 'SyncHorsLigne', 'stockerPointageHorsLigne', '#664', 'contrat signé',
    'QRPointageEtab', 'SaisieCodeSecours']) {
    assert.ok(fiche.includes(temoin), `fiche système ① : ${temoin}`);
  }
  // Revue fraîche de T0 : ① n'est pas « sans contrôle contrat signé » ; le contrôle n'est pas dans ses RPC, mais le
  // trigger de première arrivée le fait (fn_exiger_conformite_demarrage_mission : SIGNE_COMPLET, deux signatures).
  const schema = read(SOURCES.schema);
  assert.ok(schema.includes('CREATE OR REPLACE TRIGGER "trg_01_exiger_conformite_premier_pointage" BEFORE INSERT OR UPDATE OF "pointage_arrivee_le" ON "public"."presences"'));
  assert.ok(corpsSql(schema, enteteFn('trg_exiger_conformite_premier_pointage')).includes('PERFORM public.fn_exiger_conformite_demarrage_mission('));
  assert.ok(corpsSql(schema, enteteFn('fn_exiger_conformite_demarrage_mission')).includes("AND cm.statut = 'SIGNE_COMPLET'"));
  for (const name of ['fn_valider_scan_qr', 'fn_valider_code_secours']) {
    assert.ok(!/SIGNE_COMPLET|fn_exiger_conformite/.test(corpsSql(schema, enteteFn(name))), `${name} contrôle désormais le contrat : revoir la fiche ①`);
  }
  // fn_pointer_arrivee, elle, le vérifie dans la RPC (la fiche le dit).
  assert.ok(corpsSql(schema, enteteFn('fn_pointer_arrivee')).includes("SELECT * INTO v_contrat FROM contrats_mission WHERE mission_id = p_mission_id AND statut = 'SIGNE_COMPLET';"));
  assert.match(corpsSql(schema, enteteFn('fn_scanner_code_pointage')),
    /IF v_mission\.prochain_type_scan = 'OUVERTURE' THEN\s+IF NOT EXISTS \(\s+SELECT 1\s+FROM contrats_mission[\s\S]*?statut = 'SIGNE_COMPLET'/);
  const decision1 = aplati(section(read('docs/mobile-swift/DECISIONS_LOT2.md'), 'Décisions (§7 du blueprint)')).split(' 2. **')[0];
  for (const [nom, texte] of [['fiche ①', fiche], ['décision 1', decision1], ['RPC_POINTAGE_SYSTEME_1 (script)', aplati(read('scripts/mobile/check-rpc-contracts.mjs'))]]) {
    assert.ok(texte.includes('trg_01_exiger_conformite_premier_pointage'), `${nom} : trigger de première arrivée absent`);
    assert.ok(!/aucun contrôle « contrat signé »|sans contrôle « contrat signé »/.test(texte), `${nom} : « aucun contrôle contrat signé » inexact (trigger de première arrivée)`);
  }
  assert.ok(decision1.includes('fn_generer_code_secours_mission') && decision1.includes('amend'), 'décision 1 : amendement (neuvième RPC ①) absent');
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
  const codes = [...index.matchAll(/code:\s*'([A-Z_]+)'/g)].map(m => m[1]);
  assert.ok(codes.length >= 2, `codes lus : ${codes.length}`); // témoin : un format de guillemets changé ne vérifierait plus rien
  for (const code of codes) assert.ok(fiche.includes(`\`${code}\``), `code ${code} absent`);
  for (const cle of ['contrat_id', 'storage_path', 'hash_document', 'signed_url', 'ttl_seconds']) assert.ok(fiche.includes(`\`${cle}\``), `clé ${cle}`);
  assert.ok(index.includes("{ contentType: 'text/html', upsert: false }") && fiche.includes('text/html'));
  assert.ok(index.includes("createSignedUrl(contrat.storage_path, 24 * 3600)") && fiche.includes('24 h'));
  assert.ok(fiche.includes('donnees_cdd'), 'fiche : aucun donnees_cdd côté soignant non consigné');
});

/**
 * Politiques de `storage.objects` encore actives après le rejeu, dans l'ordre, des instructions écrites en clair dans
 * `sources` (paires [migration, sql], commentaires `--` retirés) : CREATE pose le texte, ALTER le complète ou le
 * renomme, DROP le retire. Une politique créée par SQL dynamique (`EXECUTE format(…)`) ou hors migration n'est pas vue.
 */
function politiquesStorageActives(sources) {
  const IDENT = '("(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_$]*)';
  const nom = brut => (brut.startsWith('"') ? brut.slice(1, -1).replaceAll('""', '"') : brut.toLowerCase());
  const instruction = new RegExp(
    `\\b(CREATE|ALTER|DROP)\\s+POLICY\\s+(?:IF\\s+EXISTS\\s+)?${IDENT}\\s+ON\\s+(?:storage|"storage")\\.(?:objects|"objects")(?![A-Za-z0-9_])[^;]*;`, 'gi');
  const actives = new Map();
  for (const [migration, sql] of sources) {
    for (const [texte, verbe, brut] of sql.replace(/--[^\n]*/g, '').matchAll(instruction)) {
      const cle = nom(brut);
      const v = verbe.toUpperCase();
      if (v === 'DROP') actives.delete(cle);
      else if (v === 'CREATE') actives.set(cle, { texte, migration });
      else {
        const avant = actives.get(cle);
        const renomme = texte.match(new RegExp(`\\bRENAME\\s+TO\\s+${IDENT}`, 'i'));
        if (renomme) {
          actives.delete(cle);
          if (avant) actives.set(nom(renomme[1]), avant);
        } else actives.set(cle, { texte: `${avant?.texte ?? ''}\n${texte}`, migration });
      }
    }
  }
  return actives;
}
/** Commande d'une politique (ALL par défaut) et caractère restrictif (une politique RESTRICTIVE n'ouvre rien). */
function commandePolitique(texte) {
  const tete = texte.split(/\b(?:USING|WITH\s+CHECK)\s*\(/i)[0];
  return {
    cmd: (tete.match(/\bFOR\s+(ALL|SELECT|INSERT|UPDATE|DELETE)\b/i)?.[1] ?? 'ALL').toUpperCase(),
    restrictive: /\bAS\s+RESTRICTIVE\b/i.test(tete),
  };
}
/**
 * Écritures client ouvertes par les politiques permissives actives, quel que soit leur nom : UPDATE, DELETE ou ALL
 * sur `jolene-documents`, toute écriture sur `contrats-signes`. Une politique qui ne restreint aucun `bucket_id`
 * vaut pour tous les buckets.
 */
function ouverturesStorage(actives) {
  const vise = (texte, bucket) => texte.includes(`'${bucket}'`) || !/\bbucket_id\b/.test(texte);
  const interdits = { 'jolene-documents': ['UPDATE', 'DELETE', 'ALL'], 'contrats-signes': ['INSERT', 'UPDATE', 'DELETE', 'ALL'] };
  const out = [];
  for (const [nom, { texte, migration }] of actives) {
    const { cmd, restrictive } = commandePolitique(texte);
    if (restrictive) continue;
    for (const [bucket, cmds] of Object.entries(interdits)) {
      if (cmds.includes(cmd) && vise(texte, bucket)) out.push(`${nom} (${migration}) : ${cmd} sur ${bucket}`);
    }
  }
  return out;
}

test('CONTRATS Storage du lot 2 : jolene-documents INSERT/SELECT sans UPDATE/DELETE client, contrats-signes SELECT', () => {
  const dir = join(root, 'supabase', 'migrations');
  const sources = readdirSync(dir).filter(n => n.endsWith('.sql')).sort().map(n => [n, readFileSync(join(dir, n), 'utf8')]);
  const actives = politiquesStorageActives(sources);
  // Témoin : l'extraction voit les politiques actuelles (une regex muette passerait sans rien vérifier).
  assert.ok(actives.size >= 10, `politiques storage.objects actives lues : ${actives.size}`);
  for (const [politique, cmd, bucket] of [
    ['pol_storage_jolene_insert', 'INSERT', 'jolene-documents'],
    ['pol_storage_jolene_select', 'SELECT', 'jolene-documents'],
    ['pol_contrats_signes_select', 'SELECT', 'contrats-signes'],
  ]) {
    const p = actives.get(politique);
    assert.ok(p, `${politique} : politique absente de l'état final des migrations`);
    assert.equal(commandePolitique(p.texte).cmd, cmd, `${politique} : commande`);
    assert.ok(p.texte.includes(`'${bucket}'`), `${politique} : bucket ${bucket}`);
  }
  assert.deepEqual(ouverturesStorage(actives), [], 'écriture client ouverte sur un bucket du lot 2 : la fiche Storage est à revoir');
  // Revue de T0 : la garde vaut quel que soit le nom de la politique (mutations synthétiques ajoutées aux migrations).
  const avec = sql => ouverturesStorage(politiquesStorageActives([...sources, ['99999999999999_mutation.sql', sql]]));
  assert.equal(avec("CREATE POLICY autre_nom ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'jolene-documents');").length, 1);
  assert.equal(avec('CREATE POLICY "Tout supprimer" ON storage.objects FOR DELETE TO authenticated USING (auth.uid() IS NOT NULL);').length, 2);
  assert.equal(avec("CREATE POLICY depot_contrat\nON storage.objects\nFOR INSERT TO authenticated\nWITH CHECK (bucket_id = 'contrats-signes');").length, 1);
  assert.equal(avec("CREATE POLICY tout_jolene ON storage.objects USING (bucket_id = 'jolene-documents');").length, 1);
  assert.equal(avec("CREATE POLICY garde ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated USING (bucket_id <> 'jolene-documents');").length, 0);
  assert.equal(avec("CREATE POLICY x ON storage.objects FOR UPDATE USING (bucket_id = 'jolene-documents');\nDROP POLICY IF EXISTS x ON storage.objects;").length, 0);
  assert.equal(avec("CREATE POLICY x ON storage.objects FOR UPDATE USING (bucket_id = 'jolene-documents');\nALTER POLICY x ON storage.objects RENAME TO y;").length, 1);
  assert.equal(avec("-- CREATE POLICY commentee ON storage.objects FOR UPDATE USING (bucket_id = 'jolene-documents');").length, 0);
  const fiche = sectionContrats('Storage du lot 2');
  for (const temoin of ['jolene-documents', 'contrats-signes', 'pol_storage_jolene_insert', 'pol_storage_jolene_select',
    'pol_contrats_signes_select', 'upsert: false', 'exists(path:)', '20260729143000', 'quel que soit son nom', 'EXECUTE format']) {
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
    // Revue fraîche de T0 : rejoueur ①, constats B9, filtres de chemins.
    'src/lib/horsLigne.ts', 'src/components/SyncHorsLigne.tsx', 'src/components/LayoutApp.tsx',
    'docs/audit-fonctionnel-pre-lancement.md', '.github/workflows/ios-swift-ci.yml', 'fn_codes_pointage_mission',
    // Seconde revue de T0 : code de secours (troisième chaîne), gardes nues, est_etab, fixtures.
    'fn_generer_code_secours_mission', 'fn_valider_code_secours', 'src/components/etablissement/QRPointageEtab.tsx',
    'src/components/soignant/SaisieCodeSecours.tsx', 'GRANT `authenticated`', 'mon_etablissement_id()', 'est_admin_valide',
    'scripts/mobile/export-demo-fixtures.mjs',
  ]) assert.ok(entete.includes(source), `en-tête : source ${source} non listée`);
  // Les MESSAGES_ERREUR du web cités par la fiche OTP existent toujours tels quels.
  const otp = read('src/components/SignerContratOtp.tsx');
  const fiche = aplati(section(doc, 'fn_envoyer_otp_signature'));
  const messagesErreur = [...otp.slice(otp.indexOf('const MESSAGES_ERREUR'), otp.indexOf('function messageDepuisCode'))
    .matchAll(/([A-Z_]+): '((?:[^'\\]|\\')+)'/g)];
  assert.ok(messagesErreur.length >= 13, `MESSAGES_ERREUR lus : ${messagesErreur.length}`); // témoin de cardinalité
  for (const [, code, message] of messagesErreur) {
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
  // L2-TJ : depuis la délégation du 8 novembre 2026, les HARD STOP n°4 du lot 2 sont tranchés (D1 à D12), chacun avec
  // ses sources et la ligne de délégation ; « En attente de Gabrielle » ne garde que la présence physique (P9) et B9.
  const deleguees = aplati(section(decisions, 'Décisions déléguées du 8 novembre 2026'));
  const LIGNE_DELEGATION = 'décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026';
  for (let i = 1; i <= 12; i++) {
    const debut = deleguees.indexOf(`### D${i} — `);
    assert.ok(debut >= 0, `décision déléguée D${i} absente`);
    const suivante = deleguees.indexOf(`### D${i + 1} — `);
    const corps = deleguees.slice(debut, suivante < 0 ? undefined : suivante);
    assert.ok(corps.includes(LIGNE_DELEGATION), `D${i} : ligne « ${LIGNE_DELEGATION} » absente`);
  }
  for (const source of ['art. 441-7', '11-82.153', 'art. 1366', 'art. 1367', 'L.1242-12', 'L.1142-2', 'L.4131-2',
    'art. 1190', 'L.3245-1', 'RGPD', 'TYPES_CONTRAT_MENTION_SALARIEE', '#1122', 'fn_documents_ok_pour_mission',
    'fn_fenetre_contestation_ouverte', 'delai_contestation_pointage_h', 'ON CONFLICT (cle) DO UPDATE', 'PageCGU.tsx']) {
    assert.ok(deleguees.includes(source), `Décisions déléguées : source ${source} absente`);
  }
  const hardStopAttente = aplati(sousSection(attente, 'HARD STOP n°4 — revue sur appareil (présence physique)'));
  assert.ok(hardStopAttente.includes('P9') && !/\*\*T5b\*\*|\*\*T9b\*\*|\*\*TL\*\*|Décision Q9/.test(hardStopAttente),
    'En attente de Gabrielle : seuls les points qui exigent sa présence physique restent sous HARD STOP n°4');
  assert.ok(decisions.includes('LOT2_PLAN.md') && decisions.includes('LOTS_2_5_DECISIONS'), 'renvois au blueprint et au mandat absents');
});

// Revue fraîche de T0 : tout écart au blueprint versionné est déclaré (tableau « Amendements du blueprint »), et la
// bascule des gardes confrontées à des sources de `main` est décrite pour chaque PR connue, pas seulement pour B1.
test('DECISIONS_LOT2.md : amendements du blueprint déclarés, bascule des gardes confrontées à main généralisée', () => {
  const decisions = read('docs/mobile-swift/DECISIONS_LOT2.md');
  const amendements = aplati(section(decisions, 'Amendements du blueprint'));
  for (const temoin of ['§3 B1 « Fichiers »', '§4, vague 0', 'B1 vise `main`', '§3 T0', '`RPC_POINTAGE_SYSTEME_1`',
    'fn_generer_code_secours_mission', 'décision 1']) {
    assert.ok(amendements.includes(temoin), `Amendements du blueprint : ${temoin} absent`);
  }
  // Le blueprint versionné dit toujours le contraire (sinon la ligne d'amendement est à retirer).
  const plan = aplati(read('docs/mobile-swift/LOT2_PLAN.md'));
  assert.ok(plan.includes('B1 se merge **après** T0') && plan.includes('B1 **après T0**'), 'LOT2_PLAN.md : formulation amendée introuvable');
  const ordre = aplati(section(decisions, 'Ordonnancement et branches'));
  assert.ok(ordre.includes('(amende `LOT2_PLAN.md` §3 B1 « Fichiers » et §4, vague 0)'), 'Ordonnancement : amendement de B1 non déclaré');
  for (const temoin of ['merge de `main` dans `feat/ios-lot2`', 're-baseline', 'B1', 'REVOKE', 'IS DISTINCT FROM', 'Motif à auditer',
    'fn_creer_notification', 'PanneauContestation.tsx', 'SyncHorsLigne', 'W1', 'PresencesSoignant.tsx', 'DocumentsSoignant.tsx',
    'messages d\'échec', 'BASCULE_MAIN']) {
    assert.ok(ordre.includes(temoin), `Ordonnancement et branches : bascule généralisée — ${temoin} absent`);
  }
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

// Revue fraîche de T0 : les constats RLS/auth relevés sur le dump sont consignés sous « En attente de Gabrielle › B9 »
// et confrontés à leurs sources. Chaque témoin SQL rougit quand une PR backend (B9) corrige le constat : basculer
// alors le constat de DECISIONS_LOT2.md et la fiche concernée de CONTRATS_RPC_SOIGNANT.md, au moment fixé par
// DECISIONS_LOT2.md « Ordonnancement et branches » (BASCULE_MAIN).
test('B9 RLS/auth : constats de T0 (système ① appelable, gardes ternaires, fn_creer_notification) confrontés au dump et consignés', () => {
  const schema = read(SOURCES.schema);
  const grantAuthenticated = name => new RegExp(`\\nGRANT ALL ON FUNCTION "public"\\."${name}"\\([^\\n]*\\) TO "authenticated";\\n`).test(schema);
  // (b) Les neuf RPC ① restent appelables par PostgREST.
  for (const name of POINTAGE_SYSTEME_1) {
    assert.ok(grantAuthenticated(name), `${name} : plus de GRANT authenticated au dump (REVOKE appliqué ?) : fiche ① « Toujours appelables » et constat B9 à ${BASCULE_MAIN}`);
  }
  // Chaîne 1, « code sans GPS » : garde ternaire de fn_codes_pointage_mission (mon_etablissement_id() NULL pour un
  // soignant), codes rendus et créés ; fn_pointer_arrivee accepte le code avec perimetre_gps_valide = true ;
  // dec_antifraude_presence ne recalcule rien sans coordonnées.
  const codes = corpsSql(schema, enteteFn('fn_codes_pointage_mission'));
  assert.ok(codes.includes('IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN'), `fn_codes_pointage_mission : garde corrigée, chaîne 1 du constat B9 à ${BASCULE_MAIN}`);
  assert.ok(codes.includes("'code_arrivee', v_mission.code_arrivee") && codes.includes("'code_depart', v_mission.code_depart") && codes.includes('UPDATE missions SET'));
  assert.match(corpsSql(schema, enteteFn('fn_pointer_arrivee')), /IF p_code_arrivee IS NOT NULL THEN[\s\S]*?v_methode := 'CODE';\s*v_perimetre_ok := true;/);
  assert.ok(corpsSql(schema, enteteFn('dec_antifraude_presence')).includes('IF NEW.pointage_arrivee_le IS NOT NULL AND NEW.arrivee_lat IS NOT NULL THEN'));
  // Chaîne 2, « jeton auto-généré » : garde ternaire de fn_generer_qr_mission, puis fn_valider_scan_qr (soignant
  // assigné, GPS non bloquant).
  assert.ok(corpsSql(schema, enteteFn('fn_generer_qr_mission')).includes('IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN'),
    `fn_generer_qr_mission : garde corrigée, chaîne 2 du constat B9 à ${BASCULE_MAIN}`);
  const scan = corpsSql(schema, enteteFn('fn_valider_scan_qr'));
  assert.ok(scan.includes('soignant_assigne_id IS DISTINCT FROM v_uid') && scan.includes('QR = source de vérité'));
  // Chaîne 3, « code de secours auto-généré » : même garde ternaire dans fn_generer_code_secours_mission, qui rend le
  // code en clair ; fn_valider_code_secours ne vérifie que l'affectation (aucun contrôle GPS) et insère la présence
  // CODE_SECOURS.
  const secours = corpsSql(schema, enteteFn('fn_generer_code_secours_mission'));
  assert.ok(secours.includes('IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN'),
    `fn_generer_code_secours_mission : garde corrigée, chaîne 3 du constat B9 à ${BASCULE_MAIN}`);
  assert.ok(secours.includes("'code', v_code") && secours.includes('Retourne le code EN CLAIR'), 'fn_generer_code_secours_mission : code plus rendu en clair');
  const validation = corpsSql(schema, enteteFn('fn_valider_code_secours'));
  assert.ok(validation.includes('IF v_mission IS NULL OR v_mission.soignant_assigne_id != v_uid THEN'));
  assert.ok(validation.includes("p_terminal_id, 'CODE_SECOURS');"), 'fn_valider_code_secours : présence CODE_SECOURS plus insérée');
  assert.ok(!/perimetre|distance|rayon|p_lat IS (?:NOT )?NULL/i.test(validation), `fn_valider_code_secours contrôle désormais la position : chaîne 3 du constat B9 à ${BASCULE_MAIN}`);
  // (a) fn_creer_notification : tout compte authentifié écrit une notification arbitraire (destinataire, titre,
  // corps, lien) ; seul contrôle : auth.uid() non nul. L'audit pré-lancement la marque « FIXÉ ».
  assert.ok(grantAuthenticated('fn_creer_notification'), `fn_creer_notification : plus de GRANT authenticated, constat B9 et fiche à ${BASCULE_MAIN}`);
  const notif = corpsSql(schema, enteteFn('fn_creer_notification'));
  assert.ok(notif.includes('IF auth.uid() IS NULL AND NOT fn_est_contexte_cron_ou_admin() THEN'));
  assert.ok(!/p_destinataire_id\s*(?:<>|!=|=|IS DISTINCT FROM|IS NOT DISTINCT FROM)/.test(notif) && notif.includes('p_lien'),
    `fn_creer_notification contrôle désormais le destinataire : constat B9 et fiche à ${BASCULE_MAIN}`);
  assert.ok(read('docs/audit-fonctionnel-pre-lancement.md').includes('| 4 | `fn_creer_notification` exposée sans check auth → spam notifications | MAJEUR | ✅ FIXÉ |'));
  // Consignation : DECISIONS_LOT2.md › En attente de Gabrielle › B9, fiche ① et fiche fn_creer_notification.
  const b9 = aplati(sousSection(section(read('docs/mobile-swift/DECISIONS_LOT2.md'), 'En attente de Gabrielle'),
    'B9 (PR préparées et poussées, jamais mergées sans go)'));
  for (const temoin of ['fn_creer_notification', 'l.82276', '`auth.uid() IS NULL`', 'FIXÉ', 'docs/audit-fonctionnel-pre-lancement.md',
    'fn_codes_pointage_mission', 'fn_generer_qr_mission', 'fn_generer_code_secours_mission',
    'pointer à distance', 'REVOKE EXECUTE', 'FROM authenticated', 'neuf RPC ①', 'SyncHorsLigne', 'IS DISTINCT FROM', 'COALESCE',
    'un gap connu reste verrouillé', 'définition live', 'PR backend séparée', 'fn_presences_detail_mission', 'fn_etat_pointage_mission']) {
    assert.ok(b9.includes(temoin), `En attente de Gabrielle › B9 : ${temoin} absent`);
  }
  assert.ok(!/Deux chaînes|huit RPC/.test(b9), 'En attente de Gabrielle › B9 : décompte périmé (neuf RPC ①)');
  // Clôture de T0 : l'audit des gardes NULL est traité à part (PR B9 dédiée). Les listes partielles de constats de T0
  // (gardes ternaires, chaînes de pointage à distance, « Motif à auditer ») laissent place à un renvoi unique et daté.
  assert.equal((b9.match(/docs\/mobile-swift\/AUDIT_GARDES_NULL_2026-11-03\.md/g) ?? []).length, 1,
    'En attente de Gabrielle › B9 : renvoi unique à l annexe AUDIT_GARDES_NULL_2026-11-03.md attendu');
  const renvoi = b9.slice(b9.indexOf('**Gardes NULL'), b9.indexOf('**Remontée**'));
  assert.ok(renvoi.length > 0, 'En attente de Gabrielle › B9 : renvoi « Gardes NULL » absent (avant « Remontée »)');
  for (const temoin of ['3 novembre 2026', 'docs/mobile-swift/AUDIT_GARDES_NULL_2026-11-03.md', '`fix/gardes-null-security-definer`',
    'fn_presences_detail_mission', 'fn_etat_pointage_mission', '« Motif à auditer »', 'définition live']) {
    assert.ok(renvoi.includes(temoin), `En attente de Gabrielle › B9 › Gardes NULL : ${temoin} absent`);
  }
  assert.ok(!/Trois chaînes|\*\*Motif à auditer|\*\*Constat T0 \(nouveau, RLS\/auth\)\*\* : `fn_presences_detail_mission`|l\.48920-48923|l\.65067-65072/.test(b9),
    'En attente de Gabrielle › B9 : liste partielle de constats de gardes NULL encore présente (remplacée par le renvoi à l audit)');
  // La PR B1 couvre aussi fn_declarer_fin_retroactive ; les PR B9 du 3/11 ont reçu le go du 8/11 (merge sériel).
  const b1 = b9.slice(b9.indexOf('**B1**'), b9.indexOf('**S1**'));
  assert.ok(b1.includes('`fn_declarer_fin_retroactive`'), 'En attente de Gabrielle › B9 › B1 : fn_declarer_fin_retroactive absente');
  const debutGo = b9.indexOf('**Go du 8 novembre 2026**');
  assert.ok(debutGo >= 0, 'En attente de Gabrielle › B9 : go du 8 novembre 2026 absent');
  const finGo = b9.indexOf(' - **', debutGo);
  const go = b9.slice(debutGo, finGo < 0 ? undefined : finGo);
  for (const temoin of ['3 novembre', 'B1', 'B3', 'B4', 'B5b', 'S1', 'merge sériel']) {
    assert.ok(go.includes(temoin), `go du 8 novembre 2026 : ${temoin} absent`);
  }
  // Les deux propositions (REVOKE ou gardes) couvrent le générateur du code de secours.
  const proposition = b9.slice(b9.indexOf('**Proposition**', b9.indexOf('neuf RPC ①')));
  assert.ok(proposition.includes('REVOKE EXECUTE') && proposition.includes('IS DISTINCT FROM'));
  assert.ok((proposition.slice(0, proposition.indexOf('un gap connu reste verrouillé')).match(/fn_generer_code_secours_mission/g) ?? []).length >= 2,
    'Proposition B9 : fn_generer_code_secours_mission absente de l une des deux options (REVOKE, gardes)');
  const fiche1 = sectionContrats('Interdit côté natif : système de pointage ①');
  // Décompte d'audit en plancher documenté (≥ 3) : l'audit des gardes NULL, traité à part, peut en relever davantage.
  for (const temoin of ['toujours GRANT `authenticated` en production', 'PostgREST', 'pointer à distance', 'B9', 'REVOKE EXECUTE',
    'Au moins trois gardes', '(≥ 3)', 'fn_generer_code_secours_mission', 'l.37478', 'l.83013', '`CODE_SECOURS`']) {
    assert.ok(fiche1.includes(temoin), `fiche système ① : ${temoin} absent`);
  }
  assert.ok(!/Deux gardes|huit RPC|\(huit,/.test(fiche1), 'fiche système ① : décompte périmé (trois gardes, neuf RPC)');
  const ficheNotif = sectionContrats('Interdite côté natif : `fn_creer_notification`');
  for (const temoin of ['GRANT `authenticated`', 'l.82276', '`auth.uid() IS NULL`', 'B9', 'FIXÉ']) {
    assert.ok(ficheNotif.includes(temoin), `fiche fn_creer_notification : ${temoin} absent`);
  }
});

// Revue fraîche de T0 : « Motif à auditer » — gardes d'accès des RPC GRANT authenticated dont une comparaison `=`, `!=`
// ou `<>` à mon_etablissement_id() est nue (ni IS DISTINCT FROM, ni IS NULL) : NULL pour tout compte sans
// établissement, la garde laisse passer. Méthode reproductible (gardesNuesEtablissement) : conditions `IF`/`ELSIF …
// THEN` du corps, moins deux exclusions motivées ; plus l'affectation de v_is_etab de fn_etat_pointage_mission.
const GARDES_NUES_ETAB = [
  ['fn_activer_garantie_mission', 'IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN'],
  ['fn_booster_mission', 'IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN'],
  ['fn_codes_pointage_mission', 'IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN'],
  ['fn_creer_reclamation_score', "IF p_evenement_type = 'ETAB' AND v_proprio_id != mon_etablissement_id() THEN"],
  ['fn_declarer_honoraires_retrocession', 'IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN'],
  ['fn_definir_retrocession_mission', 'IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN'],
  ['fn_deposer_chorus', 'IF v_facture.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN'],
  ['fn_diffuser_pool_urgence', 'OR v_etablissement_id = public.mon_etablissement_id()\n  ) THEN'],
  ['fn_enregistrer_numero_dpae', 'IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN'],
  ['fn_etablissement_pour_mission', ') AND mon_etablissement_id() != p_etablissement_id AND NOT est_admin() THEN'],
  ['fn_etat_pointage_mission', 'v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id();'],
  ['fn_generer_code_secours_mission', 'IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN'],
  ['fn_generer_donnees_dpae', 'IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN'],
  ['fn_generer_facture', 'IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN'],
  ['fn_generer_qr_mission', 'IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN'],
  ['fn_presences_detail_mission', 'IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin()'],
  ['fn_rebooker_soignant', 'IF v_m.etablissement_id <> public.mon_etablissement_id() AND NOT public.est_admin() THEN'],
  ['fn_soignants_urgence', 'IF NOT (public.est_admin() OR v_mission.etablissement_id = public.mon_etablissement_id()) THEN'],
];
// Relevées par la méthode mais sûres : la comparaison nue est neutralisée par le reste de la condition.
// Clé : nom de la RPC ; valeur : [début exact de l'en-tête de la surcharge concernée, témoin de la neutralisation].
const GARDES_NUES_EXCLUES = {
  // Surcharge « facture » : conjonction avec `fn_a_permission_etablissement('contrats', …) IS TRUE`, faux pour un soignant.
  fn_ouvrir_litige_rate_limited: [
    `${enteteFn('fn_ouvrir_litige_rate_limited')}"p_mission_id" "uuid", "p_type_litige" "public"."type_litige", "p_motif" "text", "p_facture_id" "uuid")`,
    "v_mission.etablissement_id = public.mon_etablissement_id()\n      AND public.fn_a_permission_etablissement(\n        'contrats', v_mission.etablissement_id\n      ) IS TRUE",
  ],
  // Comparaison dans le WHERE d'un NOT EXISTS : NULL ne sélectionne aucune ligne, la garde refuse.
  fn_soignant_stripe_connect_actif: [enteteFn('fn_soignant_stripe_connect_actif'),
    'AND NOT EXISTS(SELECT 1 FROM missions m WHERE m.soignant_assigne_id = p_soignant_id AND m.etablissement_id = mon_etablissement_id()'],
};
/** RPC GRANT authenticated dont une condition `IF`/`ELSIF … THEN` compare nûment à mon_etablissement_id(). */
function gardesNuesEtablissement(schema) {
  const auth = new Set([...schema.matchAll(/\nGRANT ALL ON FUNCTION "public"\."([a-z0-9_]+)"\([^\n]*\) TO "authenticated";\n/g)].map(m => m[1]));
  const nue = /(?:!=|<>|(?<![:<>!])=)\s*(?:public\.)?mon_etablissement_id\(\)|mon_etablissement_id\(\)\s*(?:!=|<>|=(?!>))/;
  const out = new Set();
  for (const bloc of schema.split('\nCREATE OR REPLACE FUNCTION "public"."').slice(1)) {
    const name = bloc.slice(0, bloc.indexOf('"'));
    if (!auth.has(name)) continue;
    const fin = bloc.indexOf('\nALTER FUNCTION ');
    for (const [, condition] of (fin < 0 ? bloc : bloc.slice(0, fin)).matchAll(/(?<!END )\b(?:IF|ELSIF)\b([\s\S]*?)\bTHEN\b/g)) {
      if (nue.test(condition) && !/mon_etablissement_id\(\)\s+IS\s+NULL/.test(condition)) out.add(name);
    }
  }
  return [...out].sort();
}
// Clôture de T0 : le décompte d'audit n'est plus une égalité stricte mais un plancher documenté (≥), annoncé par le
// renvoi « Gardes NULL » de DECISIONS_LOT2.md › En attente de Gabrielle › B9. L'audit des gardes NULL du 3 novembre
// 2026 (annexe AUDIT_GARDES_NULL_2026-11-03.md, PR B9 dédiée) en relève davantage : un décompte plus élevé au dump ne
// fait pas rougir T0 ; une garde de la liste corrigée (ou un plancher non atteint) la fait basculer (BASCULE_MAIN).
const PLANCHER_GARDES_NUES = 18; // relevé du dump #1097 : 17 conditions `IF`/`ELSIF` + l'affectation de v_is_etab
const ANNEXE_AUDIT_GARDES_NULL = 'docs/mobile-swift/AUDIT_GARDES_NULL_2026-11-03.md';
/** Fonctions qui ont une entrée (verdict) dans l'annexe : lignes `- <nom>[ / <nom> | , <nom> | + <nom>] — <verdict>`. */
function fonctionsAuditees(annexe) {
  const out = new Set();
  for (const [, noms] of annexe.matchAll(/^- ([a-z0-9_ ,/+]+?) — (?:EXPLOITABLE|non exploitable) \[/gm)) {
    for (const nom of noms.split(/\s*(?:\/|,|\+)\s*/)) if (nom) out.add(nom.trim());
  }
  return out;
}
test('B9 RLS/auth : gardes nues à mon_etablissement_id() des RPC authenticated — plancher documenté, renvoi à l audit', () => {
  const schema = read(SOURCES.schema);
  for (const [name, garde] of GARDES_NUES_ETAB) {
    assert.ok(corpsSql(schema, enteteFn(name)).includes(garde), `${name} : garde nue corrigée (« ${garde} ») : GARDES_NUES_ETAB et plancher à ${BASCULE_MAIN}`);
    assert.ok(new RegExp(`\\nGRANT ALL ON FUNCTION "public"\\."${name}"\\([^\\n]*\\) TO "authenticated";\\n`).test(schema), `${name} : plus de GRANT authenticated`);
  }
  for (const [name, [entete, temoin]] of Object.entries(GARDES_NUES_EXCLUES)) {
    assert.ok(corpsSql(schema, entete).includes(temoin), `${name} : exclusion à revoir (témoin « ${temoin} » absent)`);
  }
  // Plancher (≥), pas égalité : chaque garde relevée par T0 l'est encore par la méthode, et le total atteint le plancher.
  const trouvees = gardesNuesEtablissement(schema).filter(n => !(n in GARDES_NUES_EXCLUES));
  const attendu = GARDES_NUES_ETAB.map(([n]) => n).filter(n => n !== 'fn_etat_pointage_mission');
  assert.deepEqual(attendu.filter(n => !trouvees.includes(n)), [],
    `gardes nues à mon_etablissement_id() : une garde relevée par T0 n est plus nue — GARDES_NUES_ETAB et plancher (${BASCULE_MAIN})`);
  assert.ok(GARDES_NUES_ETAB.length >= PLANCHER_GARDES_NUES, `GARDES_NUES_ETAB sous le plancher documenté (≥ ${PLANCHER_GARDES_NUES})`);
  assert.ok(new Set([...trouvees, 'fn_etat_pointage_mission']).size >= PLANCHER_GARDES_NUES,
    `gardes nues au dump sous le plancher documenté (≥ ${PLANCHER_GARDES_NUES} RPC) : ${BASCULE_MAIN}`);
  // Renvoi unique et daté de DECISIONS_LOT2.md › En attente de Gabrielle › B9.
  const b9 = aplati(sousSection(section(read('docs/mobile-swift/DECISIONS_LOT2.md'), 'En attente de Gabrielle'),
    'B9 (PR préparées et poussées, jamais mergées sans go)'));
  const renvoi = b9.slice(b9.indexOf('**Gardes NULL'), b9.indexOf('**Remontée**'));
  assert.ok(renvoi.length > 0, 'renvoi « Gardes NULL » absent');
  assert.ok(renvoi.includes(`≥ ${PLANCHER_GARDES_NUES} RPC`), `renvoi « Gardes NULL » : plancher ≥ ${PLANCHER_GARDES_NUES} RPC non documenté`);
  assert.ok(!renvoi.includes('18 fois'), 'renvoi « Gardes NULL » : ancien décompte non reproductible');
  assert.ok(renvoi.includes('`gardesNuesEtablissement`') && renvoi.includes('tests/node/check-rpc-contracts.node.mjs'),
    'renvoi « Gardes NULL » : méthode reproductible non référencée');
  // Annexe : copie du rapport d'audit, avec un verdict pour chaque garde relevée par T0 et pour les deux exclusions.
  const annexe = read(ANNEXE_AUDIT_GARDES_NULL);
  assert.ok(annexe.includes('3 novembre 2026') && annexe.includes('`fix/gardes-null-security-definer`'), 'annexe : date ou PR B9 absente');
  const auditees = fonctionsAuditees(annexe);
  for (const name of [...GARDES_NUES_ETAB.map(([n]) => n), ...Object.keys(GARDES_NUES_EXCLUES), 'fn_declarer_fin_retroactive']) {
    assert.ok(auditees.has(name), `annexe ${ANNEXE_AUDIT_GARDES_NULL} : aucun verdict pour ${name}`);
  }
  assert.ok(auditees.size >= PLANCHER_GARDES_NUES, `annexe : ${auditees.size} fonctions auditées, plancher ${PLANCHER_GARDES_NUES}`);
});

// Revue fraîche de T0 : check-rpc-contracts.mjs lit le supplément STAGING (statut `staging_seulement`) ; tant que
// T2 ne l'a pas ajouté aux filtres de chemins de ios-swift-ci.yml, la consigne reste écrite dans DECISIONS_LOT2.md.
test('ios-swift-ci.yml : le supplément SMS lu par le script est dans les filtres de chemins, ou consigné pour T2', () => {
  assert.ok(read('scripts/mobile/check-rpc-contracts.mjs').includes(`'${SUPPLEMENT_SMS}'`), 'le script ne lit plus le supplément : retirer cette garde');
  const filtres = [...read('.github/workflows/ios-swift-ci.yml').matchAll(/^\s+- '([^']+)'$/gm)].map(m => m[1]);
  assert.ok(filtres.includes('scripts/mobile/check-rpc-contracts.mjs'), 'filtres de chemins de ios-swift-ci.yml non lus');
  if (filtres.filter(f => f === SUPPLEMENT_SMS).length >= 2) return; // pull_request et push
  const consignes = aplati(section(read('docs/mobile-swift/DECISIONS_LOT2.md'), 'Consignes aux tranches suivantes'));
  assert.ok(consignes.includes(`**T2**`) && consignes.includes(`\`${SUPPLEMENT_SMS}\``) && consignes.includes('ios-swift-ci.yml'),
    'supplément SMS absent des filtres de chemins de ios-swift-ci.yml et non consigné pour T2');
});

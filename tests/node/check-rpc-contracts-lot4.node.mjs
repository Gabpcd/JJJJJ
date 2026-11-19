import assert from 'node:assert/strict';
import * as processusLot4 from 'node:child_process';
import * as fsLot4 from 'node:fs';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import * as osLot4 from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import * as contratsLot4 from '../../scripts/mobile/check-rpc-contracts.mjs';
import {
  CONTRACTS_PATH,
  RPC_SUIVIES,
  SOURCES,
  buildContracts,
} from '../../scripts/mobile/check-rpc-contracts.mjs';

// Garde du lot 4, tranche T0 (docs/mobile-swift/LOT4_PLAN.md §3 T0, docs/mobile-swift/DECISIONS_LOT4.md).
// Fichier séparé de check-rpc-contracts.node.mjs (garde du lot 1) et de check-rpc-contracts-lot3.node.mjs,
// comme le lot 3 : les T0 des lots menés en parallèle n'éditent pas les mêmes lignes ; même étape CI
// (« Garde de livraison mobile » de validate-pr.yml). Écrit sur feat/ios-lot4 (2-3 novembre 2026, dans le
// fichier du lot 1) et porté tel quel sur main le 18 novembre, helpers du lot 1 recopiés ci-dessous.
// Aucun réseau, aucun secret : lecture de fichiers du dépôt seulement.

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = relative => readFileSync(join(root, relative), 'utf8');
const byName = new Map(RPC_SUIVIES.map(r => [r.name, r]));

/** Texte d'une section `## <titre>` d'un document Markdown, jusqu'à la section suivante. */
function section(doc, heading) {
  const start = doc.indexOf(`\n## ${heading}`);
  assert.ok(start >= 0, `section « ${heading} » introuvable`);
  const next = doc.indexOf('\n## ', start + 1);
  return doc.slice(start, next < 0 ? undefined : next);
}

/** Texte d'une sous-section `### <titre>` d'un document Markdown, jusqu'à la (sous-)section suivante. */
function sousSection(doc, heading) {
  const start = doc.indexOf(`\n### ${heading}`);
  assert.ok(start >= 0, `sous-section « ${heading} » introuvable`);
  const fins = [doc.indexOf('\n### ', start + 1), doc.indexOf('\n## ', start + 1)].filter(i => i >= 0);
  return doc.slice(start, fins.length ? Math.min(...fins) : undefined);
}

/** Corps d'une fonction SQL du dump : de son `CREATE OR REPLACE FUNCTION` au `$$;` qui la ferme. */
function sqlBody(schema, name) {
  const start = schema.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
  assert.ok(start >= 0, `${name} absente de public.sql`);
  const end = schema.indexOf('\n$$;', start);
  assert.ok(end > start, `${name} : fin de corps introuvable`);
  return schema.slice(start, end);
}

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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Lot 4, tranche T0 (docs/mobile-swift/LOT4_PLAN.md §3 T0 ; décisions docs/mobile-swift/DECISIONS_LOT4.md).
// Les 42 RPC consommées par le lot 4 (41 propres au lot, 1 partagée avec le lot 2) sont sous contrat
// avant toute gateway Swift ; chaque fiche cite toutes les réponses littérales du corps SQL
// (confrontées au dump, pas recopiées) ; les deux edges, le Realtime, le double-aveugle et les
// surcharges du litige ont leur fiche ; garde-fous 18 et 19.
// ═══════════════════════════════════════════════════════════════════════════════════════════════


// Ordre des tranches du lot 4 (LOT4_PLAN.md §3) : T3a swipe, T4 filtres, T5 disponibilités,
// T6 parrainage, T8 litiges et réclamations, T9 score et évaluations, T7a/T7b messagerie (et entrées
// du détail de mission, correction 20), T10 bulletins, T11 pool urgence et exclusions.
// Les 41 RPC propres au lot 4, suivies en `a_venir`, `lot: 4`.
const LOT4 = [
  'fn_obtenir_missions_swipe', 'fn_enregistrer_swipe', 'fn_retirer_candidature', 'fn_initialiser_preferences_matching',
  'fn_lister_mes_filtres_sauvegardes', 'fn_creer_filtre_sauvegarde', 'fn_modifier_filtre_sauvegarde', 'fn_supprimer_filtre_sauvegarde',
  'fn_definir_disponibilite',
  'fn_obtenir_mes_parrainages', 'fn_appliquer_parrainage',
  'fn_ajouter_message_litige', 'fn_soumettre_reclamation',
  'fn_mon_breakdown_actuel', 'fn_mes_evenements_score', 'fn_evolution_score_soignant', 'fn_lister_notations_recues',
  'fn_creer_reclamation_score', 'fn_mes_notations_recues_avec_stats', 'fn_signaler_notation',
  'fn_lister_conversations_messagerie', 'fn_interlocuteurs_conversations', 'fn_marquer_messages_lus', 'fn_messages_non_lus',
  'fn_typing_start', 'fn_typing_stop', 'fn_update_presence', 'fn_est_bloque', 'fn_bloquer_utilisateur',
  'fn_debloquer_utilisateur', 'fn_signaler_utilisateur', 'fn_user_id_pour_etablissement', 'fn_obtenir_conversation',
  'fn_lister_copies_bulletins', 'fn_signaler_copie_bulletin',
  'fn_pool_urgence_missions_pour_soignant', 'fn_toggle_pool_urgence', 'fn_toggle_pool_urgence_sms',
  'fn_mes_exclusions_recues', 'fn_retirer_exclusion', 'fn_exclure_utilisateur',
];
// Partagée avec un lot antérieur (DECISIONS_LOT4.md, précision 10 ; précédent du T0 du lot 5) : le T0 du
// lot 2 la suit en `lot: 2` (contestation d'une présence, `DESACCORD_HEURES_POINTAGE`, T5b) ; le lot 4
// l'appelle aussi (T8, type `AUTRE`). Une seule entrée dans RPC_SUIVIES, celle du lot antérieur ; à défaut
// (branche sans le T0 du lot 2), `ajouterPartageesLot4` l'ajoute en `a_venir`, `lot: 4`.
const LOT4_PARTAGEES = ['fn_ouvrir_litige_rate_limited'];
// Les 42 RPC consommées par le lot 4 (fiches confrontées au SQL, GRANT, refus 42501).
const LOT4_TOUTES = [...LOT4, ...LOT4_PARTAGEES];
// Reclassées en `lot: 4` par un lot antérieur après le T0 du lot 4 (intégration `feat/ios-lot4`) :
// `fn_suggestions_missions_pour_soignant` sort du lot 1 à la revue B8 de son T3 (fiche et ligne de la
// synthèse du lot 1). Hors des 41 RPC propres du blueprint (`LOT4_PLAN.md` §3 T0 ne la cite pas) ; son
// sort au lot 4 (consommée ou retirée de RPC_SUIVIES) relève de T15 (DECISIONS_LOT4.md, précision 11).
const LOT4_RECLASSEES = ['fn_suggestions_missions_pour_soignant'];
/** RPC suivies en `lot: 4` qui ne sont ni partagées ni reclassées : les 41 propres au lot. */
const propresLot4 = rpcs => rpcs.filter(r => r.lot === 4 && !LOT4_PARTAGEES.includes(r.name) && !LOT4_RECLASSEES.includes(r.name));

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

// Noms de condition PL/pgSQL qu'un corps peut écrire au lieu du code (`USING ERRCODE = 'insufficient_privilege'`),
// ramenés au SQLSTATE que PostgREST renvoie. Une condition absente de cette table n'est pas reconnue :
// `formesRaiseNonLues` la signale au lieu de laisser le refus hors de la table d'interception (fail-closed).
const CONDITIONS_SQLSTATE_LOT4 = Object.freeze({
  insufficient_privilege: '42501',
  invalid_authorization_specification: '28000',
  invalid_parameter_value: '22023',
  check_violation: '23514',
  raise_exception: 'P0001',
  no_data_found: 'P0002',
});
/** Valeur d'une option `ERRCODE` → SQLSTATE : code de cinq caractères (casse indifférente) ou nom de condition connu ; sinon `null`. */
function sqlstateLot4(valeur) {
  const v = valeur.trim();
  if (/^[0-9A-Z]{5}$/i.test(v)) return v.toUpperCase();
  return CONDITIONS_SQLSTATE_LOT4[v.toLowerCase()] ?? null;
}
/**
 * Instructions `RAISE EXCEPTION` d'un corps SQL, quels que soient les espaces et la casse : message littéral en
 * tête (`RAISE EXCEPTION '<m>' [USING …]`) ou option `MESSAGE = '<m>'`, option `ERRCODE = '<x>'` dans un ordre
 * quelconque ; un `;` entre apostrophes ne coupe pas l'instruction. `sqlstate` vaut `P0001` sans ERRCODE et
 * `null` pour une valeur non reconnue.
 */
function raisesLot4(body) {
  return [...body.matchAll(/\bRAISE\s+EXCEPTION\b((?:[^;']|'(?:[^']|'')*')*);/gi)].map(([instruction, suite]) => {
    const message = suite.match(/^\s*'((?:[^']|'')*)'/)?.[1] ?? suite.match(/\bMESSAGE\s*=\s*'((?:[^']|'')*)'/i)?.[1];
    const errcode = suite.match(/\bERRCODE\s*=\s*'([^']*)'/i)?.[1];
    return {
      instruction: instruction.replace(/\s+/g, ' '),
      message: message === undefined ? null : unquoteSql(message),
      errcode: errcode !== undefined,
      sqlstate: errcode === undefined ? 'P0001' : sqlstateLot4(errcode),
    };
  });
}
/**
 * Formes d'erreur qu'aucun extracteur ne lit : `RAISE <condition>` ou `RAISE SQLSTATE '…'` (tout ce qui n'est ni
 * `RAISE EXCEPTION`, ni un niveau NOTICE / WARNING / INFO / LOG / DEBUG, ni la re-levée `RAISE;`), un `ERRCODE`
 * hors d'un `RAISE EXCEPTION` lu, une valeur d'ERRCODE non reconnue, un refus 42501 sans message. Vide : tout
 * SQLSTATE du corps est lu par `sqlstatesSql` et `refus42501`.
 */
function formesRaiseNonLues(body) {
  const fautes = [];
  for (const [, mot] of body.matchAll(/\bRAISE\b\s*(;|[A-Za-z_]+)/gi)) {
    if (![';', 'EXCEPTION', 'NOTICE', 'WARNING', 'INFO', 'LOG', 'DEBUG'].includes(mot.toUpperCase())) fautes.push(`forme non lue : RAISE ${mot}`);
  }
  const raises = raisesLot4(body);
  const errcodes = [...body.matchAll(/\bERRCODE\b/gi)].length;
  const lus = raises.filter(r => r.errcode).length;
  if (errcodes !== lus) fautes.push(`ERRCODE lus : ${lus} sur ${errcodes}`);
  for (const r of raises) {
    if (r.sqlstate === null) fautes.push(`ERRCODE non reconnu : ${r.instruction}`);
    if (r.sqlstate === '42501' && r.message === null) fautes.push(`refus 42501 sans message : ${r.instruction}`);
  }
  return fautes;
}
/**
 * Messages littéraux qu'un corps SQL peut renvoyer au client : `'error', '…'`, `'message', '…'`,
 * JSON `{"error":"…"}`, message d'un `RAISE EXCEPTION` (en tête ou option `MESSAGE`), apostrophes SQL doublées
 * ramenées à la valeur réelle.
 */
function messagesSql(body) {
  return [...new Set([
    ...[...body.matchAll(/'(?:error|message)',\s*'((?:[^']|'')*)'/g)].map(m => unquoteSql(m[1])),
    ...[...body.matchAll(/'\{"error":"([^"]+)"\}'::jsonb/gi)].map(m => m[1]),
    ...raisesLot4(body).map(r => r.message).filter(m => m !== null),
  ])];
}
const codesErreurSql = body => [...new Set([...body.matchAll(/'error_code',\s*'([A-Z_]+)'/g)].map(m => m[1]))];
/** SQLSTATE explicites (`USING ERRCODE`) d'un corps SQL, noms de condition ramenés au code. */
const sqlstatesSql = body => [...new Set(raisesLot4(body).filter(r => r.errcode && r.sqlstate).map(r => r.sqlstate))];
/** Messages levés avec le SQLSTATE 42501 (code ou `insufficient_privilege`), quelle que soit la forme de l'instruction. */
const refus42501 = body => raisesLot4(body).filter(r => r.sqlstate === '42501').map(r => r.message);

/** Surcharges confrontées pour une RPC : toutes, sauf la 4 arguments du litige (jamais appelée, fiche dédiée). */
function corpsConfrontes(schema, name) {
  const all = sqlBodiesAvecSignature(schema, name);
  return name === 'fn_ouvrir_litige_rate_limited' ? all.filter(d => !d.signature.includes('"p_facture_id"')) : all;
}

const CONTRATS_DOC = 'docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md';

test('Lot 4 — RPC_SUIVIES : 41 RPC propres au lot 4 en a_venir lot 4, dans l ordre des tranches, et 1 partagée', () => {
  assert.equal(LOT4.length, 41);
  assert.equal(new Set(LOT4_TOUTES).size, 42);
  assert.deepEqual([...contratsLot4.RPC_PARTAGEES_LOT4], LOT4_PARTAGEES);
  assert.deepEqual(propresLot4(RPC_SUIVIES).map(r => r.name), LOT4);
  // Les statuts propres au lot 4 ne bougent qu'en T0 (a_venir) et en T15 (consommee, en une fois) : LOT4_PLAN §3.
  for (const name of LOT4) assert.deepEqual(byName.get(name), { name, statut: 'a_venir', lot: 4 });
  // Reclassées par un lot antérieur : `a_venir`, `lot: 4`, jamais comptées parmi les 42, consignées dans la
  // synthèse du lot 4 et dans les décisions (précision 11), pour que T15 les statue.
  const synthese = section(read(CONTRATS_DOC), 'Lot 4 — synthèse');
  const decisions = read('docs/mobile-swift/DECISIONS_LOT4.md');
  for (const name of LOT4_RECLASSEES) {
    assert.deepEqual(byName.get(name), { name, statut: 'a_venir', lot: 4 }, `${name} : reclassée attendue a_venir lot 4`);
    assert.ok(!LOT4_TOUTES.includes(name), `${name} : reclassée, hors des 42 RPC du blueprint`);
    assert.ok(synthese.includes(`\`${name}\``), `synthèse lot 4 : reclassée ${name} non signalée`);
    assert.ok(decisions.includes(`\`${name}\``), `DECISIONS_LOT4.md : reclassée ${name} non consignée`);
  }
  // Partagée : une seule entrée, celle du lot antérieur qui la suit (lot 2, statut porté par sa tranche T5b), ou
  // `a_venir` lot 4 par repli ; jamais un lot postérieur au lot 4.
  for (const name of LOT4_PARTAGEES) {
    const entrees = RPC_SUIVIES.filter(r => r.name === name);
    assert.equal(entrees.length, 1, `${name} : une seule entrée dans RPC_SUIVIES`);
    const [{ lot, statut }] = entrees;
    assert.ok(Number.isInteger(lot) && lot >= 1 && lot <= 4, `${name} : lot ${lot} (attendu ≤ 4)`);
    assert.ok(['a_venir', 'consommee'].includes(statut), `${name} : statut ${statut}`);
  }
});

test('Lot 4 — ajouterPartageesLot4 : l entrée d un lot antérieur est gardée, lot 4 seulement à défaut, jamais de doublon', () => {
  const { ajouterPartageesLot4 } = contratsLot4;
  assert.equal(typeof ajouterPartageesLot4, 'function', 'ajouterPartageesLot4 absente du script');
  const lot2 = [{ name: 'fn_ouvrir_litige_rate_limited', statut: 'consommee', lot: 2 }];
  assert.deepEqual(ajouterPartageesLot4(structuredClone(lot2)), lot2, 'l entrée du lot 2 garde son lot et son statut');
  const repli = ajouterPartageesLot4([]);
  assert.deepEqual(repli, [{ name: 'fn_ouvrir_litige_rate_limited', statut: 'a_venir', lot: 4 }]);
  assert.deepEqual(ajouterPartageesLot4(structuredClone(repli)), repli, 'idempotent');
});

test('Lot 4 — rpc-contracts.json : définition SQL SECURITY DEFINER, GRANT authenticated, types null attendus', () => {
  const actual = buildContracts({
    typesSource: read(SOURCES.types),
    schemaSource: read(SOURCES.schema),
    manifest: JSON.parse(read(SOURCES.manifest)),
  });
  const lot4 = actual.rpcs.filter(r => LOT4_TOUTES.includes(r.name));
  assert.equal(lot4.length, 42);
  assert.deepEqual(propresLot4(actual.rpcs).map(r => r.name), LOT4);
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

// Un gap connu reste verrouillé : une re-baseline qui écrirait `ERRCODE='42501'` sans espaces, `errcode` en
// minuscules ou `ERRCODE = 'insufficient_privilege'` ne doit pas sortir la RPC de la garde 42501 sans bruit.
test('Lot 4 — extracteurs SQLSTATE : espaces, casse et noms de condition tolérés, toute autre forme signalée', () => {
  const temoin = [
    "RAISE EXCEPTION 'A' USING ERRCODE='42501';",
    "raise exception 'B' using errcode = 'insufficient_privilege';",
    "RAISE EXCEPTION USING MESSAGE = 'C', ERRCODE = '42501';",
    "RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='D';",
    "RAISE EXCEPTION 'E ; point-virgule cité' USING ERRCODE = '22023';",
    "RAISE EXCEPTION 'l''apostrophe';",
    "RAISE NOTICE 'G';",
    'RAISE;',
  ].join('\n');
  assert.deepEqual(refus42501(temoin), ['A', 'B', 'C', 'D']);
  assert.deepEqual(sqlstatesSql(temoin), ['42501', '22023']);
  assert.deepEqual(messagesSql(temoin), ['A', 'B', 'C', 'D', 'E ; point-virgule cité', "l'apostrophe"]);
  assert.deepEqual(formesRaiseNonLues(temoin), []);
  for (const forme of [
    "RAISE insufficient_privilege USING MESSAGE = 'H';",
    "RAISE SQLSTATE '42501' USING MESSAGE = 'I';",
    "RAISE EXCEPTION 'J' USING ERRCODE = 'condition_inconnue';",
    "RAISE EXCEPTION USING ERRCODE = '42501';",
    "v := 1; -- USING ERRCODE = '42501'",
  ]) assert.notDeepEqual(formesRaiseNonLues(forme), [], `forme non signalée : ${forme}`);
});

test('Lot 4 — confrontation : chaque ERRCODE des 42 RPC (toutes surcharges) est lu, aucune forme RAISE ignorée', () => {
  const schema = read(SOURCES.schema);
  const fautes = [];
  let errcodes = 0;
  for (const name of LOT4_TOUTES) {
    for (const { signature, body } of sqlBodiesAvecSignature(schema, name)) {
      errcodes += raisesLot4(body).filter(r => r.errcode).length;
      for (const faute of formesRaiseNonLues(body)) fautes.push(`${name} ${signature.slice(signature.indexOf('('))} : ${faute}`);
    }
  }
  assert.deepEqual(fautes, []);
  // Témoin : le dump du 01/11 porte vingt et un ERRCODE dans ces corps ; zéro trahirait un extracteur muet.
  assert.ok(errcodes >= 20, `ERRCODE lus : ${errcodes}`);
});

test('Lot 4 — CONTRATS : chaque fiche cite toutes les réponses littérales, codes et SQLSTATE de son corps SQL', () => {
  const schema = read(SOURCES.schema);
  const doc = read(CONTRATS_DOC);
  let total = 0;
  for (const name of LOT4_TOUTES) {
    const partagee = LOT4_PARTAGEES.includes(name);
    // Fiche partagée (précision 10) : un seul titre `## <nom>` ; l'usage du lot 4 en est la sous-section
    // « Usage du lot 4 », déplacée telle quelle dans la fiche du lot 2 quand son T0 est fusionné.
    if (partagee) assert.equal(doc.split('\n').filter(l => l === `## ${name}`).length, 1, `${name} : fiche en double (fusion avec le T0 du lot 2 : voir sa fiche)`);
    const fiche = partagee ? sousSection(section(doc, `${name}\n`), 'Usage du lot 4') : section(doc, `${name}\n`);
    const statut = partagee ? '- **Statut natif (lot 4)** : à venir (lot 4, T8)' : '- **Statut natif** : à venir (lot 4';
    assert.ok(fiche.includes(statut), `${name} : statut natif lot 4 absent`);
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
  for (const name of LOT4_TOUTES) for (const { body } of corpsConfrontes(schema, name)) for (const m of refus42501(body)) messages.add(m);
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
  // Fiche unique partagée avec le lot 2 (précision 10) : les deux usages de la surcharge canonique sont nommés.
  for (const attendu of ['DESACCORD_HEURES_POINTAGE', 'lot 2', 'RPC_PARTAGEES_LOT4', 'Usage du lot 4']) {
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
  for (const name of LOT4_TOUTES) assert.ok(synthese.includes(`| \`${name}\` |`), `synthèse lot 4 : ligne ${name} absente`);
  // Décompte : 41 propres au lot 4 + 1 partagée avec le lot 2 (précision 10), plus « 42 en lot 4 ».
  const aplatie = synthese.replace(/\s+/g, ' ');
  assert.ok(aplatie.includes('**quarante et une RPC** propres au lot 4') && aplatie.includes('une RPC partagée'), 'synthèse : décompte 41 + 1 absent');
  assert.ok(!/quarante-deux RPC\*\* suivies en `a_venir`, `lot: 4`/.test(aplatie), 'synthèse : ancien décompte « 42 en lot 4 »');
  const ligne = synthese.split('\n').find(l => l.startsWith('| `fn_ouvrir_litige_rate_limited` |'));
  assert.ok(ligne.includes('partagée') && ligne.includes('lot 2'), 'synthèse : ligne de la RPC partagée sans renvoi au lot 2');
});

/** Texte du garde-fou `n` de guards.sh, de son `echo "── Garde-fou n :` au suivant (ou au verdict final). */
function blocGardeFou(guards, n) {
  const at = guards.indexOf(`echo "── Garde-fou ${n} :`);
  assert.ok(at >= 0, `garde-fou ${n} absent`);
  const next = guards.indexOf('echo "── Garde-fou ', at + 1);
  return guards.slice(at, next < 0 ? guards.indexOf('\nif [ "$FAIL" -ne 0 ]', at) : next);
}


/** Exécute un bloc de guards.sh dans `cwd` (même en-tête `set -uo pipefail`, FAIL=0) et renvoie FAIL. */
function executerGardeFou(bloc, cwd) {
  const r = processusLot4.spawnSync('bash', ['-c', `set -uo pipefail\nFAIL=0\n${bloc}\necho "FAIL=$FAIL"`], { cwd, encoding: 'utf8' });
  const m = r.stdout.match(/FAIL=(\d+)\s*$/);
  assert.ok(m, `bloc non exécuté : ${r.stderr}`);
  return Number(m[1]);
}

test('Lot 4 — guards.sh : garde-fous 18 (aucun lecteur natif de notations) et 19 (aucun envoi hors edge)', () => {
  const guards = read('tests/non-regression/guards.sh');
  const bloc = n => blocGardeFou(guards, n);
  const motif = (texte, nom) => {
    const m = texte.match(new RegExp(`${nom}='([^']+)'`));
    assert.ok(m, `variable ${nom} absente`);
    return new RegExp(m[1]);
  };
  const b18 = bloc(18);
  assert.ok(b18.includes('ios-native/Packages') && b18.includes('ios-native/Jolene') && b18.includes('FAIL=1'));
  // Littéral Swift seulement (fiche « Jamais notations_missions ») : fixtures, golden et Localizable hors motif.
  assert.ok(b18.includes("--include='*.swift'"), '18 : périmètre *.swift absent');
  // Code de retour de grep exploité : 2 (dossier absent ou illisible) n'est jamais « OK ».
  for (const n of [18, 19]) assert.ok(/-ne 1 \]/.test(bloc(n)), `${n} : code de retour 2 de grep non traité`);
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
  // Fail-closed dès aujourd'hui sur le Swift du dépôt, à l'exclusion unique près (portage sur main) : l'assertion
  // négative de SupabaseNotationGatewayTests (lot 2), la même que `EXCLUSIONS` de tests/node/lecture-notes-ios.node.mjs.
  const exclusion = new RegExp(motif(b18, 'EXCLUSION18').source);
  const extraitLot2 = '!$0.path.contains("notations_missions")';
  assert.ok(read('tests/node/lecture-notes-ios.node.mjs').includes(`extrait: '${extraitLot2}'`), '18 : exclusion absente de la garde du lot 2');
  let exclues = 0;
  for (const dir of ['ios-native/Packages', 'ios-native/Jolene']) {
    for (const file of swiftFiles(join(root, dir))) {
      readFileSync(file, 'utf8').split('\n').forEach((ligne, i) => {
        if (!notations.test(ligne)) return;
        const sortie = `${file.slice(root.length + 1)}:${i + 1}:${ligne}`;
        assert.ok(exclusion.test(sortie), `${sortie} : lit une table de notations`);
        exclues++;
      });
    }
  }
  assert.equal(exclues, 1, '18 : l exclusion couvre exactement une ligne');
  for (const file of swiftFiles(join(root, 'ios-native'))) assert.ok(!envoi.test(readFileSync(file, 'utf8')), `${file} envoie un message hors edge`);
});

// Un gap connu reste verrouillé : un dossier renommé (ex. `ios-native/Jolene`) rendait les garde-fous 18 et 19
// muets, `if grep …` lisant le code 2 de grep comme « aucune occurrence ».
test('Lot 4 — guards.sh : garde-fous 18 et 19 exécutés sur des arbres témoins (fail-closed, 18 limité au Swift)', () => {
  const guards = read('tests/non-regression/guards.sh');
  const [b18, b19] = [blocGardeFou(guards, 18), blocGardeFou(guards, 19)];
  const tmp = fsLot4.mkdtempSync(join(osLot4.tmpdir(), 'garde-fous-lot4-'));
  try {
    const arbre = (nom, fichiers) => {
      const dir = join(tmp, nom);
      for (const [rel, contenu] of Object.entries(fichiers)) {
        fsLot4.mkdirSync(dirname(join(dir, rel)), { recursive: true });
        fsLot4.writeFileSync(join(dir, rel), contenu);
      }
      return dir;
    };
    const propre = {
      'ios-native/Packages/A/Sources/A/A.swift': 'let total = "total_evaluations"\n',
      'ios-native/Jolene/App.swift': 'let cle = "ios_natif_\\(rawValue)_actif"\n',
    };
    const sain = arbre('propre', propre);
    assert.equal(executerGardeFou(b18, sain), 0, '18 : arbre propre');
    assert.equal(executerGardeFou(b19, sain), 0, '19 : arbre propre');
    // Fixture de démo, vecteur golden ou catalogue de chaînes portant la valeur brute : pas un lecteur de table.
    const fixtures = arbre('fixtures', {
      ...propre,
      'ios-native/Packages/A/Tests/A/Fixtures/liens.json': '{"ecran": "evaluations"}\n',
      'ios-native/Jolene/Resources/Localizable.xcstrings': '{"evaluations": {}}\n',
    });
    assert.equal(executerGardeFou(b18, fixtures), 0, '18 : une fixture JSON ou un catalogue de chaînes n est pas un lecteur');
    // Exclusion unique (assertion négative du lot 2) tolérée dans son fichier, jamais ailleurs.
    const negative = 'XCTAssertTrue(registry.requests.allSatisfy { !$0.path.contains("notations_missions") })\n';
    assert.equal(executerGardeFou(b18, arbre('exclusion', { ...propre, 'ios-native/Packages/JoleneSupabase/Tests/JoleneSupabaseTests/SupabaseNotationGatewayTests.swift': negative })), 0);
    assert.equal(executerGardeFou(b18, arbre('exclusion-ailleurs', { ...propre, 'ios-native/Packages/JoleneSupabase/Tests/JoleneSupabaseTests/AutreTests.swift': negative })), 1);
    assert.equal(executerGardeFou(b18, arbre('lecteur', { ...propre, 'ios-native/Jolene/Lecteur.swift': 'client.from("evaluations_publiees")\n' })), 1);
    assert.equal(executerGardeFou(b19, arbre('envoi', { ...propre, 'ios-native/Jolene/Envoi.swift': 'rpc("fn_envoyer_message", params: p)\n' })), 1);
    // Dossier absent (grep sort en 2) : rouge, jamais « OK ».
    assert.equal(executerGardeFou(b18, arbre('sans-app', { 'ios-native/Packages/A/Sources/A/A.swift': 'let x = 1\n' })), 1, '18 : ios-native/Jolene absent');
    assert.equal(executerGardeFou(b18, arbre('sans-swift', { 'ios-native/Packages/README.md': 'x\n', 'ios-native/Jolene/README.md': 'x\n' })), 1, '18 : aucun fichier Swift lu');
    assert.equal(executerGardeFou(b19, arbre('sans-ios', { 'README.md': 'x\n' })), 1, '19 : ios-native absent');
  } finally {
    fsLot4.rmSync(tmp, { recursive: true, force: true });
  }
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
  // Lecture : la décision 3 du lot 0 (WebView bornée ou Safari) est tranchée par D17 ; date de mise à jour du T0.
  const lot4Lecture = section(parite, 'Lecture').split('\n- ').find(l => l.startsWith('**Lot 4**'));
  assert.ok(lot4Lecture, 'Lecture : paragraphe lot 4 absent');
  for (const attendu of ['D17', 'SFSafariViewController', 'Lot 4 — statuts proposés']) assert.ok(lot4Lecture.includes(attendu), `Lecture lot 4 : ${attendu} absent`);
  assert.ok(!/à trancher par Gabrielle/.test(lot4Lecture), 'Lecture lot 4 : décision 3 encore « à trancher par Gabrielle » (D17 adoptée)');
  assert.match(parite, /\nDernière mise à jour : \d{4}-\d{2}-\d{2} \(lot 4, T0 /, '« Dernière mise à jour » non rafraîchie par le T0 du lot 4');
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
  const precisions = section(dec, 'Précisions apportées');
  const precision = n => {
    const at = precisions.indexOf(`\n${n}. **`);
    assert.ok(at >= 0, `précision ${n} absente`);
    const fin = precisions.indexOf(`\n${n + 1}. **`, at);
    return precisions.slice(at, fin < 0 ? undefined : fin).replace(/\s+/g, ' ');
  };
  // Précision 1 : D-FLAGS cite déjà 13 clés (aucun écart) ; critère du lot 4 sur ses seules clés, total global de
  // 28 renvoyé aux décisions du lot 5 (7 clés `ios_natif_etab_*`, `etab_pointage` comprise).
  const p1 = precision(1);
  for (const attendu of ['13 clés, blueprint v2', 'aucun écart', "cle IN ('ios_natif_swipe_actif'", '= **13**', '**28**', 'ios_natif_etab_pointage_actif', 'DECISIONS_LOT5.md']) {
    assert.ok(p1.includes(attendu), `précision 1 : ${attendu} absent`);
  }
  for (const cle of ['swipe', 'recherches', 'disponibilites', 'parrainage', 'litiges', 'reclamations', 'messagerie', 'bulletins', 'evaluations', 'score', 'pool_urgence', 'exclusions', 'serie']) {
    assert.ok(p1.includes(`'ios_natif_${cle}_actif'`), `précision 1 : clé ${cle} absente du critère`);
  }
  for (const faux of ['11 clés', '**27**', '6 du lot 5']) assert.ok(!dec.includes(faux), `DECISIONS_LOT4 : décompte faux « ${faux} »`);
  assert.ok(section(dec, 'Critères du plan amendés').includes('= 13'), 'critère B0-bis amendé non reporté');
  // Précision 10 : RPC partagée avec le lot 2, écart aux deux blueprints, fusion non mécanique de la fiche.
  const p10 = precision(10);
  for (const attendu of ['fn_ouvrir_litige_rate_limited', 'RPC_PARTAGEES_LOT4', 'LOT2_PLAN.md', 'LOT4_PLAN.md', 'origin/lot2/l2-t0', '41', 'Usage du lot 4', 'jamais « garder les deux côtés »']) {
    assert.ok(p10.includes(attendu), `précision 10 : ${attendu} absent`);
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
  // Mode avion cohérent avec D8 : l'envoi part, puis « envoi non confirmé » ; le composeur n'est pas désactivé hors ligne.
  const avion = section(recette, '2. Mode avion');
  assert.ok(!/aucun envoi accepté/.test(avion), 'mode avion : « aucun envoi accepté » contredit D8');
  for (const attendu of ['composeur reste actif', '`EnvoiOutcome.nonConfirme`', 'aucun renvoi automatique']) {
    assert.ok(avion.includes(attendu), `mode avion : ${attendu} absent`);
  }
  const beta = read('docs/mobile-swift/BETA_LOT4.md');
  for (const attendu of ['bloquant', 'non bloquant', '14 jours', '400 sessions', '99,5 %', 'Beta App Review']) {
    assert.ok(beta.includes(attendu), `BETA_LOT4.md : ${attendu} absent`);
  }
});

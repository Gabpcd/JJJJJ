#!/usr/bin/env node
/**
 * Test CI de dérive des contrats RPC consommés par le client Swift (plan §4.4, §11 jour 8).
 *
 * Pour chaque RPC listée dans `RPC_SUIVIES`, le script extrait :
 *   - la signature TypeScript `Args` / `Returns` de la section `Functions` de
 *     `src/integrations/supabase/types.ts` (ou `null` si la RPC n'y figure pas) ;
 *   - la signature SQL `CREATE OR REPLACE FUNCTION … RETURNS …` et ses qualificatifs
 *     (LANGUAGE, SECURITY, search_path) depuis `supabase/schema/public.sql` ;
 *   - les rôles GRANT EXECUTE connus dans le même fichier ;
 *   - la catégorie du manifeste `supabase/SECURITY_DEFINER_MANIFEST.json` (ou `null`).
 *
 * Il régénère ensuite `ios-native/rpc-contracts.json` en mémoire et le compare au
 * fichier versionné. Toute différence fait échouer le script avec un diff lisible,
 * champ par champ. Le fichier versionné est le contrat que le code Swift suppose ;
 * une divergence impose de relire les gateways avant de régénérer.
 *
 * Usage :
 *   node scripts/mobile/check-rpc-contracts.mjs            # compare, code 1 si dérive
 *   node scripts/mobile/check-rpc-contracts.mjs --update   # réécrit le JSON
 *
 * Aucune valeur secrète n'est lue ni écrite : le script ne lit que des fichiers du dépôt.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const SOURCES = {
  types: 'src/integrations/supabase/types.ts',
  schema: 'supabase/schema/public.sql',
  manifest: 'supabase/SECURITY_DEFINER_MANIFEST.json',
};
export const CONTRACTS_PATH = join(ROOT, 'ios-native', 'rpc-contracts.json');

/**
 * RPC consommées (ou à consommer) par le client Swift. `statut` :
 *   - `lot0`    : appelée par `JoleneSupabase` dès le lot 0 ;
 *   - `a_venir` : listée dans `docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md`, lot cible indiqué.
 *   - `consommee` : appelée par une gateway Swift livrée (lot indiqué), passée par la PR qui la câble.
 * L'ordre est celui du plan §11 jour 8, puis celui des tranches du lot 1
 * (`docs/mobile-swift/LOT1_PLAN.md` §3 : T3 accueil, T6 candidature/présence, T7 annulation,
 * T4b favoris, T9 audit/drapeaux, T8 compte). Chaque ajout est accompagné de `--update` et
 * d'une fiche dans CONTRATS_RPC_SOIGNANT.md dans la même PR (LOT1_PLAN §4) ; les statuts
 * passent en consommé au fil des PR qui câblent la gateway.
 *
 * Reclassements (suivies, mais pas au lot 1) : `fn_mon_profil_soignant_complet` passe en lot 3
 * (renvoie `numero_secu`, `siret_liberal`, `iban_last4` ; le soft-gate `peut_candidater` du lot 1
 * lit `soignants` par SELECT direct, LOT1_PLAN §2.6) ; `fn_suggestions_missions_pour_soignant`
 * passe en lot 4 (revue B8 de T3 : son seul appelant web, `SuggestionsMissions.tsx`, n'est monté
 * par aucune page ; l'Accueil natif ne la consomme pas).
 *
 * Les deux listes d'exclusion qui suivent sont vérifiées par `verifierExclusions` (fail-closed).
 */
export const RPC_SUIVIES = [
  { name: 'fn_get_my_role', statut: 'lot0', lot: 0 },
  { name: 'fn_etablissements_safe', statut: 'lot0', lot: 0 },
  { name: 'fn_mon_profil_soignant_complet', statut: 'a_venir', lot: 3 },
  { name: 'fn_dashboard_soignant_complet', statut: 'consommee', lot: 1 }, // T3 : SupabaseDashboardGateway
  { name: 'fn_confirmer_action_planning_v1', statut: 'a_venir', lot: 1 },
  { name: 'fn_suggestions_missions_pour_soignant', statut: 'a_venir', lot: 4 }, // reclassée (revue B8 de T3)
  { name: 'fn_annuler_candidature_soignant', statut: 'a_venir', lot: 1 },
  { name: 'fn_annuler_mission_soignant', statut: 'a_venir', lot: 1 },
  { name: 'fn_repondre_proposition', statut: 'a_venir', lot: 1 },
  { name: 'fn_toggle_favori_etablissement', statut: 'a_venir', lot: 1 },
  { name: 'fn_mes_favoris_etablissements', statut: 'a_venir', lot: 1 },
  { name: 'fn_audit_connexion', statut: 'a_venir', lot: 1 },
  { name: 'fn_maj_activite_soignant', statut: 'a_venir', lot: 1 },
  { name: 'fn_ecrire_audit_safe', statut: 'a_venir', lot: 1 },
  { name: 'fn_supprimer_compte_rate_limited', statut: 'a_venir', lot: 1 },
  { name: 'fn_param_bool', statut: 'a_venir', lot: 1 },
  { name: 'fn_confirmer_presence_mission', statut: 'a_venir', lot: 1 },
  { name: 'fn_pointer_arrivee', statut: 'a_venir', lot: 2 },
  { name: 'fn_pointer_depart', statut: 'a_venir', lot: 2 },
  { name: 'fn_scanner_code_pointage', statut: 'a_venir', lot: 2 },
  { name: 'fn_valider_scan_qr', statut: 'a_venir', lot: 2 },
  { name: 'fn_generer_qr_mission', statut: 'a_venir', lot: 2 },
  { name: 'fn_etat_pointage_mission', statut: 'a_venir', lot: 2 },
  { name: 'fn_envoyer_otp_signature', statut: 'a_venir', lot: 2 },
  { name: 'fn_signer_contrat_otp', statut: 'a_venir', lot: 2 },
  { name: 'fn_remplacer_document_soignant', statut: 'a_venir', lot: 2 },
  { name: 'fn_upsert_token_push', statut: 'a_venir', lot: 3 },
  // Lot 4 (`docs/mobile-swift/LOT4_PLAN.md` §3 T0, fiches « Lot 4 » de CONTRATS_RPC_SOIGNANT.md) : les
  // 41 RPC propres au lot, dans l'ordre des tranches ; la 42e, partagée avec le lot 2, est dans
  // `RPC_PARTAGEES_LOT4` ci-dessous. Écart assumé (LOT4_PLAN §3) : ces statuts passent en `consommee` en
  // une fois par T15, jamais par les onze tranches parallèles qui câblent les gateways.
  // T3a — swipe
  { name: 'fn_obtenir_missions_swipe', statut: 'a_venir', lot: 4 },
  { name: 'fn_enregistrer_swipe', statut: 'a_venir', lot: 4 },
  { name: 'fn_retirer_candidature', statut: 'a_venir', lot: 4 },
  { name: 'fn_initialiser_preferences_matching', statut: 'a_venir', lot: 4 },
  // T4 — filtres sauvegardés et alerte rapide
  { name: 'fn_lister_mes_filtres_sauvegardes', statut: 'a_venir', lot: 4 },
  { name: 'fn_creer_filtre_sauvegarde', statut: 'a_venir', lot: 4 },
  { name: 'fn_modifier_filtre_sauvegarde', statut: 'a_venir', lot: 4 },
  { name: 'fn_supprimer_filtre_sauvegarde', statut: 'a_venir', lot: 4 },
  // T5 — disponibilités
  { name: 'fn_definir_disponibilite', statut: 'a_venir', lot: 4 },
  // T6 — parrainage
  { name: 'fn_obtenir_mes_parrainages', statut: 'a_venir', lot: 4 },
  { name: 'fn_appliquer_parrainage', statut: 'a_venir', lot: 4 },
  // T8 — litiges et réclamations générales (`fn_ouvrir_litige_rate_limited` : RPC_PARTAGEES_LOT4)
  { name: 'fn_ajouter_message_litige', statut: 'a_venir', lot: 4 },
  { name: 'fn_soumettre_reclamation', statut: 'a_venir', lot: 4 },
  // T9 — score, contestation et évaluations
  { name: 'fn_mon_breakdown_actuel', statut: 'a_venir', lot: 4 },
  { name: 'fn_mes_evenements_score', statut: 'a_venir', lot: 4 },
  { name: 'fn_evolution_score_soignant', statut: 'a_venir', lot: 4 },
  { name: 'fn_lister_notations_recues', statut: 'a_venir', lot: 4 },
  { name: 'fn_creer_reclamation_score', statut: 'a_venir', lot: 4 },
  { name: 'fn_mes_notations_recues_avec_stats', statut: 'a_venir', lot: 4 },
  { name: 'fn_signaler_notation', statut: 'a_venir', lot: 4 },
  // T7a/T7b — messagerie, blocage, signalement, fil de mission (correction 20)
  { name: 'fn_lister_conversations_messagerie', statut: 'a_venir', lot: 4 },
  { name: 'fn_interlocuteurs_conversations', statut: 'a_venir', lot: 4 },
  { name: 'fn_marquer_messages_lus', statut: 'a_venir', lot: 4 },
  { name: 'fn_messages_non_lus', statut: 'a_venir', lot: 4 },
  { name: 'fn_typing_start', statut: 'a_venir', lot: 4 },
  { name: 'fn_typing_stop', statut: 'a_venir', lot: 4 },
  { name: 'fn_update_presence', statut: 'a_venir', lot: 4 },
  { name: 'fn_est_bloque', statut: 'a_venir', lot: 4 },
  { name: 'fn_bloquer_utilisateur', statut: 'a_venir', lot: 4 },
  { name: 'fn_debloquer_utilisateur', statut: 'a_venir', lot: 4 },
  { name: 'fn_signaler_utilisateur', statut: 'a_venir', lot: 4 },
  { name: 'fn_user_id_pour_etablissement', statut: 'a_venir', lot: 4 },
  { name: 'fn_obtenir_conversation', statut: 'a_venir', lot: 4 },
  // T10 — copies officielles des bulletins
  { name: 'fn_lister_copies_bulletins', statut: 'a_venir', lot: 4 },
  { name: 'fn_signaler_copie_bulletin', statut: 'a_venir', lot: 4 },
  // T11 — pool urgence et exclusions
  { name: 'fn_pool_urgence_missions_pour_soignant', statut: 'a_venir', lot: 4 },
  { name: 'fn_toggle_pool_urgence', statut: 'a_venir', lot: 4 },
  { name: 'fn_toggle_pool_urgence_sms', statut: 'a_venir', lot: 4 },
  { name: 'fn_mes_exclusions_recues', statut: 'a_venir', lot: 4 },
  { name: 'fn_retirer_exclusion', statut: 'a_venir', lot: 4 },
  { name: 'fn_exclure_utilisateur', statut: 'a_venir', lot: 4 },
];

/**
 * Consommées par le lot 4 mais suivies par un lot antérieur (précédent du T0 du lot 5,
 * `docs/mobile-swift/DECISIONS_LOT4.md` précision 10) : `fn_ouvrir_litige_rate_limited` est suivie par
 * le T0 du lot 2 en `lot: 2` (contestation d'une présence, `DESACCORD_HEURES_POINTAGE`, T5b) et appelée
 * aussi par le lot 4 (T8, litige `AUTRE`). Une seule entrée : celle du lot antérieur garde son lot et son
 * statut ; elle n'est ajoutée en `a_venir`, `lot: 4` qu'en son absence (branche sans le T0 du lot 2).
 * Les branches des deux lots se fusionnent donc sans doublon dans `RPC_SUIVIES`.
 */
export const RPC_PARTAGEES_LOT4 = Object.freeze(['fn_ouvrir_litige_rate_limited']);

/** Ajoute à `suivies` chaque RPC partagée du lot 4 qu'aucun lot antérieur ne suit encore ; renvoie `suivies`. */
export function ajouterPartageesLot4(suivies) {
  for (const name of RPC_PARTAGEES_LOT4) {
    if (!suivies.some(r => r.name === name)) suivies.push({ name, statut: 'a_venir', lot: 4 });
  }
  return suivies;
}
ajouterPartageesLot4(RPC_SUIVIES);

/**
 * Jamais suivies (donc jamais appelées par le client Swift) :
 *   - `fn_etablissement_public` : exclut `est_compte_test = true` → NULL pour tout établissement
 *     de recette STAGING ; le nom d'établissement vient exclusivement de `fn_etablissements_safe`.
 */
export const RPC_JAMAIS_SUIVIES = ['fn_etablissement_public'];

/**
 * Pas avant le lot 4 (suivie au plus tôt avec `lot: 4` ; ajoutée par le T0 du lot 4, `LOT4_PLAN.md` §3) :
 *   - `fn_retirer_candidature` (swipe).
 */
export const RPC_PAS_AVANT_LOT4 = ['fn_retirer_candidature'];

/**
 * Refuse une liste de RPC suivies qui contient une RPC interdite côté natif, ou une RPC du lot 4
 * classée dans un lot antérieur. Appelée par `buildContracts` : la CI échoue au lieu de régénérer
 * un contrat qui autoriserait l'appel.
 */
export function verifierExclusions(suivies) {
  for (const { name, lot } of suivies) {
    if (RPC_JAMAIS_SUIVIES.includes(name)) {
      throw new Error(`${name} ne doit jamais être suivie côté natif (voir CONTRATS_RPC_SOIGNANT.md, « Interdite côté natif »).`);
    }
    if (RPC_PAS_AVANT_LOT4.includes(name) && !(Number.isInteger(lot) && lot >= 4)) {
      throw new Error(`${name} n'est pas suivie avant le lot 4 (lot demandé : ${lot}).`);
    }
  }
}

const read = relative => readFileSync(join(ROOT, relative), 'utf8');

/** Retourne l'indice de l'accolade fermante équilibrée à partir de `open` (indice d'un `{`). */
function balancedEnd(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') { depth--; if (depth === 0) return i; }
  }
  throw new Error(`Accolade non équilibrée à partir de l'indice ${open}.`);
}

/** Normalise un fragment TypeScript multi-lignes en une seule ligne lisible. */
function compact(fragment) {
  return fragment
    .replace(/\r/g, '')
    .split('\n').map(l => l.trim()).filter(Boolean).join('; ')
    .replace(/\{;\s*/g, '{ ').replace(/;\s*\}/g, ' }')
    .replace(/;\s*;/g, ';').replace(/\s+/g, ' ').trim();
}

/**
 * Extrait `{ args, returns }` de la section `Functions` de types.ts pour une RPC,
 * ou `null` si elle n'y est pas déclarée (types.ts peut être en retard sur le schéma).
 */
export function extractTypesSignature(typesSource, name) {
  const functionsStart = typesSource.indexOf('\n    Functions: {');
  if (functionsStart < 0) throw new Error('Section `Functions` introuvable dans types.ts.');
  const functionsEnd = balancedEnd(typesSource, typesSource.indexOf('{', functionsStart + 1));
  const section = typesSource.slice(functionsStart, functionsEnd + 1);
  const marker = `\n      ${name}: `;
  const at = section.indexOf(marker);
  if (at < 0) return null;
  const open = section.indexOf('{', at + marker.length - 1);
  const block = section.slice(open, balancedEnd(section, open) + 1);
  const argsAt = block.indexOf('Args:');
  const returnsAt = block.indexOf('Returns:');
  if (argsAt < 0 || returnsAt < 0) throw new Error(`Bloc Args/Returns illisible pour ${name}.`);
  const argsRaw = block.slice(argsAt + 'Args:'.length, returnsAt).trim();
  const returnsRaw = block.slice(returnsAt + 'Returns:'.length, block.length - 1).trim();
  return { args: compact(argsRaw).replace(/;$/, ''), returns: compact(returnsRaw).replace(/;$/, '') };
}

/**
 * Extrait les définitions SQL (une par surcharge) d'une fonction publique depuis
 * le dump de schéma : signature complète, type de retour, qualificatifs.
 */
export function extractSqlDefinitions(schemaSource, name) {
  const lines = schemaSource.split('\n');
  const prefix = `CREATE OR REPLACE FUNCTION "public"."${name}"(`;
  const definitions = [];
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith(prefix)) continue;
    const line = lines[i];
    const returnsAt = line.lastIndexOf(') RETURNS ');
    if (returnsAt < 0) throw new Error(`Ligne CREATE FUNCTION sans RETURNS pour ${name} (ligne ${i + 1}).`);
    const args = line.slice(prefix.length, returnsAt);
    const returns = line.slice(returnsAt + ') RETURNS '.length).trim();
    const qualifiers = [];
    for (let j = i + 1; j < lines.length && !/^\s*AS \$/.test(lines[j]); j++) qualifiers.push(lines[j].trim());
    const qualifierText = qualifiers.join(' ');
    const language = (qualifierText.match(/LANGUAGE "?([a-z_]+)"?/) ?? [])[1] ?? null;
    const security = /SECURITY DEFINER/.test(qualifierText) ? 'DEFINER' : 'INVOKER';
    const volatility = (qualifierText.match(/\b(STABLE|IMMUTABLE|VOLATILE)\b/) ?? [])[1] ?? 'VOLATILE';
    const searchPath = (qualifierText.match(/SET "search_path" TO (.+?)(?:\s+SET |$)/) ?? [])[1] ?? null;
    definitions.push({
      signature: `${name}(${args})`,
      returns,
      language,
      security,
      volatility,
      search_path: searchPath,
      ligne: i + 1,
    });
  }
  return definitions;
}

/** Rôles ayant un GRANT sur la fonction dans le dump (toutes surcharges confondues). */
export function extractGrants(schemaSource, name) {
  const re = new RegExp(`^GRANT ALL ON FUNCTION "public"\\."${name}"\\([^\\n]*\\) TO "([a-z_]+)";$`, 'gm');
  const roles = new Set();
  for (const match of schemaSource.matchAll(re)) roles.add(match[1]);
  return [...roles].sort();
}

export function manifestCategory(manifest, name) {
  const entries = manifest.entries.filter(e => typeof e.signature === 'string' && e.signature.startsWith(`${name}(`));
  if (entries.length === 0) return null;
  return entries.map(e => ({ signature: e.signature, category: e.category }));
}

export function buildContracts({ typesSource, schemaSource, manifest }) {
  verifierExclusions(RPC_SUIVIES);
  const rpcs = RPC_SUIVIES.map(({ name, statut, lot }) => {
    const types = extractTypesSignature(typesSource, name);
    const sql = extractSqlDefinitions(schemaSource, name);
    if (types === null && sql.length === 0) {
      throw new Error(`RPC ${name} absente de types.ts ET de public.sql : contrat introuvable.`);
    }
    return {
      name,
      statut,
      lot,
      types,
      // La ligne du dump change à chaque re-baseline ; elle est utile au lecteur, pas au contrat.
      sql: sql.map(({ ligne, ...rest }) => rest),
      grants: extractGrants(schemaSource, name),
      manifeste: manifestCategory(manifest, name),
    };
  });
  return { schema_version: 1, sources: SOURCES, rpcs };
}

/** Diff lisible, champ par champ, entre deux contrats sérialisés. */
export function diffContracts(expected, actual) {
  const problems = [];
  const expectedByName = new Map((expected.rpcs ?? []).map(r => [r.name, r]));
  const actualByName = new Map(actual.rpcs.map(r => [r.name, r]));
  for (const name of new Set([...expectedByName.keys(), ...actualByName.keys()])) {
    const before = expectedByName.get(name);
    const after = actualByName.get(name);
    if (!before) { problems.push(`+ ${name} : nouvelle RPC suivie, absente du JSON versionné.`); continue; }
    if (!after) { problems.push(`- ${name} : présente dans le JSON versionné mais plus suivie par le script.`); continue; }
    for (const field of ['statut', 'lot', 'types', 'sql', 'grants', 'manifeste']) {
      const a = JSON.stringify(before[field] ?? null);
      const b = JSON.stringify(after[field] ?? null);
      if (a !== b) problems.push(`~ ${name}.${field}\n    versionné : ${a}\n    actuel    : ${b}`);
    }
  }
  if (expected.schema_version !== actual.schema_version) {
    problems.push(`~ schema_version : versionné ${expected.schema_version}, actuel ${actual.schema_version}`);
  }
  return problems;
}

export function main(argv = process.argv.slice(2)) {
  const update = argv.includes('--update');
  const actual = buildContracts({
    typesSource: read(SOURCES.types),
    schemaSource: read(SOURCES.schema),
    manifest: JSON.parse(read(SOURCES.manifest)),
  });
  const serialized = `${JSON.stringify(actual, null, 2)}\n`;
  if (update) {
    writeFileSync(CONTRACTS_PATH, serialized);
    console.log(`Contrats RPC réécrits : ${CONTRACTS_PATH} (${actual.rpcs.length} RPC).`);
    return 0;
  }
  let expected;
  try {
    expected = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  } catch (error) {
    console.error(`Fichier de contrats illisible (${CONTRACTS_PATH}) : ${error.message}`);
    console.error('Lancez `node scripts/mobile/check-rpc-contracts.mjs --update` après relecture des gateways Swift.');
    return 1;
  }
  const problems = diffContracts(expected, actual);
  const missingTypes = actual.rpcs.filter(r => r.types === null).map(r => r.name);
  if (missingTypes.length) {
    console.log(`Note : ${missingTypes.length} RPC absentes de types.ts (contrat tenu par public.sql seul) : ${missingTypes.join(', ')}.`);
  }
  if (problems.length === 0) {
    console.log(`Contrats RPC à jour : ${actual.rpcs.length} RPC, aucune dérive entre ${SOURCES.types}, ${SOURCES.schema} et ${CONTRACTS_PATH}.`);
    return 0;
  }
  console.error(`Dérive des contrats RPC (${problems.length} différence${problems.length > 1 ? 's' : ''}) :`);
  for (const problem of problems) console.error(problem);
  console.error('\nRelisez les gateways Swift concernées, puis `node scripts/mobile/check-rpc-contracts.mjs --update`.');
  return 1;
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  try {
    process.exitCode = main();
  } catch (error) {
    console.error(`check-rpc-contracts : ${error.message}`);
    process.exitCode = 1;
  }
}

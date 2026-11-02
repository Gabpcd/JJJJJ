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
 * Lot 2 (T0) : une RPC de recette STAGING (`statut: 'staging_seulement'`) n'existe ni dans
 * `public.sql` ni dans `types.ts` ; sa signature et ses GRANT sont lus dans le supplément SQL
 * indiqué par `source`, et sa présence dans le dump de production fait échouer le script.
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
 *   - `staging_seulement` : RPC de recette définie par un supplément STAGING (`source`), absente de
 *     la production ; appelée seulement sur STAGING (lot 2, `fn_admission_otp_signature_recette`).
 * L'ordre est celui du plan §11 jour 8, puis celui des tranches du lot 1
 * (`docs/mobile-swift/LOT1_PLAN.md` §3 : T3 accueil, T6 candidature/présence, T7 annulation,
 * T4b favoris, T9 audit/drapeaux, T8 compte). Chaque ajout est accompagné de `--update` et
 * d'une fiche dans CONTRATS_RPC_SOIGNANT.md dans la même PR (LOT1_PLAN §4) ; les statuts
 * passent en consommé au fil des PR qui câblent la gateway.
 *
 * Reclassement (suivie, mais pas au lot 1) : `fn_mon_profil_soignant_complet` passe en lot 3
 * (renvoie `numero_secu`, `siret_liberal`, `iban_last4` ; le soft-gate `peut_candidater` du lot 1
 * lit `soignants` par SELECT direct, LOT1_PLAN §2.6).
 *
 * Lot 2 (T0, `docs/mobile-swift/LOT2_PLAN.md` §3 T0 et `DECISIONS_LOT2.md`) : le pointage passe par
 * le seul système rotatif (`fn_scanner_code_pointage`) ; les RPC du système ① sortent de cette liste
 * (`RPC_POINTAGE_SYSTEME_1`, décision 1). Dix RPC sont ajoutées après `fn_remplacer_document_soignant`.
 *
 * Les listes d'exclusion qui suivent sont vérifiées par `verifierExclusions` (fail-closed).
 */
export const RPC_SUIVIES = [
  { name: 'fn_get_my_role', statut: 'lot0', lot: 0 },
  { name: 'fn_etablissements_safe', statut: 'lot0', lot: 0 },
  { name: 'fn_mon_profil_soignant_complet', statut: 'a_venir', lot: 3 },
  { name: 'fn_dashboard_soignant_complet', statut: 'a_venir', lot: 1 },
  { name: 'fn_confirmer_action_planning_v1', statut: 'a_venir', lot: 1 },
  { name: 'fn_suggestions_missions_pour_soignant', statut: 'a_venir', lot: 1 },
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
  { name: 'fn_scanner_code_pointage', statut: 'a_venir', lot: 2 },
  { name: 'fn_etat_pointage_mission', statut: 'a_venir', lot: 2 },
  { name: 'fn_envoyer_otp_signature', statut: 'a_venir', lot: 2 },
  { name: 'fn_signer_contrat_otp', statut: 'a_venir', lot: 2 },
  { name: 'fn_remplacer_document_soignant', statut: 'a_venir', lot: 2 },
  // Lot 2, T0 : présences (T3, T4b, T5a, T5b), justificatifs (T6), contrats (T8).
  { name: 'fn_consentir_gps', statut: 'a_venir', lot: 2 },
  { name: 'fn_relancer_validation_presence', statut: 'a_venir', lot: 2 },
  { name: 'fn_presences_detail_mission', statut: 'a_venir', lot: 2 },
  { name: 'fn_fenetre_contestation_ouverte', statut: 'a_venir', lot: 2 },
  { name: 'fn_ouvrir_litige_rate_limited', statut: 'a_venir', lot: 2 },
  { name: 'fn_creer_notation_mission', statut: 'a_venir', lot: 2 },
  { name: 'fn_demander_revue_document', statut: 'a_venir', lot: 2 },
  { name: 'fn_verifier_coherence_documents', statut: 'a_venir', lot: 2 },
  { name: 'fn_signer_attestation_sante', statut: 'a_venir', lot: 2 },
  { name: 'fn_admission_otp_signature_recette', statut: 'staging_seulement', lot: 2, source: 'scripts/ci/sms-signature-staging.sql' },
  { name: 'fn_upsert_token_push', statut: 'a_venir', lot: 3 },
];

/**
 * Jamais suivies (donc jamais appelées par le client Swift) :
 *   - `fn_etablissement_public` : exclut `est_compte_test = true` → NULL pour tout établissement
 *     de recette STAGING ; le nom d'établissement vient exclusivement de `fn_etablissements_safe`.
 *   - `fn_creer_notification` (lot 2, décision 9) : le web l'appelle après une contestation de
 *     présence ; le trigger `trg_notifier_creation_litige` notifie déjà l'établissement, et l'appel
 *     client suppose le droit d'écrire une notification arbitraire.
 */
export const RPC_JAMAIS_SUIVIES = ['fn_etablissement_public', 'fn_creer_notification'];

/**
 * Système de pointage ① (lot 2, décision 1) : plus monté côté web depuis la PR #664 (seul
 * `PointageRotatifSoignant` l'est), sans contrôle « contrat signé » côté `fn_valider_scan_qr` et
 * bloquant pour les missions multi-jours. Jamais suivi, donc jamais appelé par le client Swift.
 */
export const RPC_POINTAGE_SYSTEME_1 = [
  'fn_pointer_arrivee',
  'fn_pointer_depart',
  'fn_pointer_debut_pause',
  'fn_pointer_fin_pause',
  'fn_valider_scan_qr',
  'fn_generer_qr_mission',
  'fn_valider_code_secours',
  'fn_codes_pointage_mission',
];

/**
 * Pas avant le lot 4 (suivie au plus tôt avec `lot: 4`, quand la tranche qui la consomme l'ajoute) :
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
    if (RPC_POINTAGE_SYSTEME_1.includes(name)) {
      throw new Error(`${name} appartient au système de pointage ①, interdit côté natif (DECISIONS_LOT2.md, décision 1).`);
    }
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

/**
 * Définitions d'une fonction publique dans un supplément SQL STAGING, écrit à la main et non par
 * pg_dump : `CREATE [OR REPLACE] FUNCTION public.<name>(<args>)` puis `RETURNS … AS $tag$`.
 * Même forme de sortie que `extractSqlDefinitions` (sans numéro de ligne).
 */
export function extractStagingDefinitions(source, name) {
  const definitions = [];
  for (const match of source.matchAll(new RegExp(`^CREATE (?:OR REPLACE )?FUNCTION public\\.${name}\\(`, 'gm'))) {
    const debut = match.index + match[0].length;
    let profondeur = 1;
    let i = debut;
    for (; i < source.length && profondeur > 0; i++) {
      if (source[i] === '(') profondeur++;
      else if (source[i] === ')') profondeur--;
    }
    if (profondeur !== 0) throw new Error(`Arguments non équilibrés pour ${name} dans le supplément STAGING.`);
    const args = source.slice(debut, i - 1).replace(/\s+/g, ' ').trim();
    const finEntete = source.indexOf(' AS $', i);
    if (finEntete < 0) throw new Error(`Corps introuvable pour ${name} dans le supplément STAGING.`);
    const entete = source.slice(i, finEntete).replace(/\s+/g, ' ').trim();
    const returns = (entete.match(/^RETURNS (.+?) LANGUAGE /) ?? [])[1] ?? null;
    if (returns === null) throw new Error(`RETURNS illisible pour ${name} dans le supplément STAGING.`);
    definitions.push({
      signature: `${name}(${args})`,
      returns,
      language: (entete.match(/LANGUAGE "?([a-z_]+)"?/) ?? [])[1] ?? null,
      security: /SECURITY DEFINER/.test(entete) ? 'DEFINER' : 'INVOKER',
      volatility: (entete.match(/\b(STABLE|IMMUTABLE|VOLATILE)\b/) ?? [])[1] ?? 'VOLATILE',
      search_path: (entete.match(/SET "?search_path"?\s*(?:=|TO)\s*(.+?)(?:\s+SET |$)/) ?? [])[1] ?? null,
    });
  }
  return definitions;
}

/** Rôles ayant un GRANT sur la fonction dans un supplément SQL STAGING. */
export function extractStagingGrants(source, name) {
  const roles = new Set();
  const re = new RegExp(`^GRANT (?:ALL|EXECUTE) ON FUNCTION public\\.${name}\\([^)]*\\) TO ([a-z_, ]+);$`, 'gm');
  for (const match of source.matchAll(re)) for (const role of match[1].split(',')) roles.add(role.trim());
  return [...roles].sort();
}

/**
 * Contrat d'une RPC de recette STAGING (`statut: 'staging_seulement'`). Fail-closed : la RPC ne doit
 * exister ni dans le dump de production ni dans types.ts (généré depuis la production), et doit être
 * définie par le supplément indiqué.
 */
function contratStaging({ name, statut, lot, source, typesSource, schemaSource, lireSource }) {
  if (typeof source !== 'string' || source.length === 0) {
    throw new Error(`${name} : statut staging_seulement sans source de supplément STAGING.`);
  }
  if (extractSqlDefinitions(schemaSource, name).length > 0) {
    throw new Error(`${name} est une RPC de recette STAGING mais figure dans ${SOURCES.schema} (production) : jamais en production (DECISIONS_LOT2.md, décision 20).`);
  }
  if (extractTypesSignature(typesSource, name) !== null) {
    throw new Error(`${name} est une RPC de recette STAGING mais figure dans ${SOURCES.types} (types générés depuis la production).`);
  }
  const texte = lireSource(source);
  const sql = extractStagingDefinitions(texte, name);
  if (sql.length === 0) throw new Error(`${name} introuvable dans le supplément STAGING ${source}.`);
  return { name, statut, lot, source, types: null, sql, grants: extractStagingGrants(texte, name), manifeste: null };
}

export function manifestCategory(manifest, name) {
  const entries = manifest.entries.filter(e => typeof e.signature === 'string' && e.signature.startsWith(`${name}(`));
  if (entries.length === 0) return null;
  return entries.map(e => ({ signature: e.signature, category: e.category }));
}

export function buildContracts({ typesSource, schemaSource, manifest, lireSource = read }) {
  verifierExclusions(RPC_SUIVIES);
  const rpcs = RPC_SUIVIES.map(({ name, statut, lot, source }) => {
    if (statut === 'staging_seulement') {
      return contratStaging({ name, statut, lot, source, typesSource, schemaSource, lireSource });
    }
    if (source !== undefined) throw new Error(`${name} : une source hors dump est réservée aux RPC staging_seulement.`);
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
    for (const field of ['statut', 'lot', 'source', 'types', 'sql', 'grants', 'manifeste']) {
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
  // Une RPC de recette STAGING n'est jamais dans types.ts : ce n'est pas un retard des types.
  const missingTypes = actual.rpcs.filter(r => r.types === null && r.statut !== 'staging_seulement').map(r => r.name);
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

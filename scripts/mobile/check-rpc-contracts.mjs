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
 * Reclassement (suivie, mais pas au lot 1) : `fn_mon_profil_soignant_complet` passe en lot 3
 * (renvoie `numero_secu`, `siret_liberal`, `iban_last4` ; le soft-gate `peut_candidater` du lot 1
 * lit `soignants` par SELECT direct, LOT1_PLAN §2.6).
 *
 * Les deux listes d'exclusion qui suivent sont vérifiées par `verifierExclusions` (fail-closed).
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
];

/**
 * Jamais suivies (donc jamais appelées par le client Swift) :
 *   - `fn_etablissement_public` : exclut `est_compte_test = true` → NULL pour tout établissement
 *     de recette STAGING ; le nom d'établissement vient exclusivement de `fn_etablissements_safe`.
 */
export const RPC_JAMAIS_SUIVIES = ['fn_etablissement_public'];

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
    if (RPC_JAMAIS_SUIVIES.includes(name)) {
      throw new Error(`${name} ne doit jamais être suivie côté natif (voir CONTRATS_RPC_SOIGNANT.md, « Interdite côté natif »).`);
    }
    if (RPC_PAS_AVANT_LOT4.includes(name) && !(Number.isInteger(lot) && lot >= 4)) {
      throw new Error(`${name} n'est pas suivie avant le lot 4 (lot demandé : ${lot}).`);
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Lot 5 — espace établissement (docs/mobile-swift/LOT5_PLAN.md §3 T0 ; fiches dans
// docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md, gardées par tests/node/contrats-etablissement-ios.node.mjs).
// ---------------------------------------------------------------------------------------------

/**
 * RPC de l'espace établissement, suivies en `a_venir` lot 5. L'ajout est dédoublonné : une RPC déjà
 * suivie par un lot antérieur (le lot 2 suit `fn_creer_notation_mission`, le lot 4
 * `fn_obtenir_conversation`, LOT2_PLAN/LOT4_PLAN §3 T0) garde son entrée et son lot, et devient
 * « partagée » (`aussi_etablissement`). Les branches parallèles se fusionnent donc sans doublon.
 */
export const RPC_SUIVIES_ETABLISSEMENT = [
  { name: 'fn_mes_permissions_etab', statut: 'a_venir', lot: 5 },
  { name: 'fn_mon_etablissement_complet', statut: 'a_venir', lot: 5 },
  { name: 'fn_stats_dashboard_etablissement', statut: 'a_venir', lot: 5 },
  { name: 'fn_soignant_pour_etablissement', statut: 'a_venir', lot: 5 },
  { name: 'fn_lire_candidatures_mission_habilitee', statut: 'a_venir', lot: 5 },
  { name: 'fn_traiter_candidature_planning_v1', statut: 'a_venir', lot: 5 },
  { name: 'fn_contrat_signe_pour_pointage', statut: 'a_venir', lot: 5 },
  { name: 'fn_valider_presence', statut: 'a_venir', lot: 5 },
  { name: 'fn_valider_presences_lot', statut: 'a_venir', lot: 5 },
  { name: 'fn_contester_presence', statut: 'a_venir', lot: 5 },
  { name: 'fn_creer_notation_mission', statut: 'a_venir', lot: 5 },
  { name: 'fn_declarer_fin_retroactive', statut: 'a_venir', lot: 5 },
  { name: 'fn_creer_mission_multi_jours_v4', statut: 'a_venir', lot: 5 },
  { name: 'fn_obtenir_conversation', statut: 'a_venir', lot: 5 },
];

/**
 * Déjà suivies par un lot soignant et consommées aussi par l'établissement (LOT5_PLAN §2.2, §2.8,
 * T0) : annotées `aussi_etablissement` dans le JSON, jamais dupliquées.
 */
export const RPC_PARTAGEES_ETABLISSEMENT = Object.freeze([
  'fn_get_my_role', 'fn_audit_connexion', 'fn_ecrire_audit_safe', 'fn_param_bool',
  'fn_etat_pointage_mission', 'fn_envoyer_otp_signature', 'fn_signer_contrat_otp',
]);

for (const rpc of RPC_SUIVIES_ETABLISSEMENT) {
  if (!RPC_SUIVIES.some(r => r.name === rpc.name)) RPC_SUIVIES.push(rpc);
}

/**
 * Exceptions PostgREST que l'espace établissement intercepte avant `SupabaseErrorMapping`
 * (LOT5_PLAN §2.5, D12) : liste blanche extraite du dump pour chaque RPC de
 * `RPC_SUIVIES_ETABLISSEMENT`, dans son corps, puis dans les fonctions qu'elle appelle et les
 * fonctions de trigger qu'elle atteint, nommées ici par RPC. Un `%` est instancié par l'argument du
 * trigger quand le message le formate depuis `TG_ARGV[n]` ; sinon il reste un joker non vide.
 * Toute modification serveur d'un message ou d'un SQLSTATE rougit le contrat.
 */
export const EXCEPTIONS_ETABLISSEMENT = {
  // fn_traiter_candidature lève P0001 (notification) ; l'UPDATE missions de
  // fn_finaliser_attribution_mission déclenche la garde de paiement (LOT5_PLAN correction 16).
  fn_traiter_candidature_planning_v1: {
    fonctions: ['fn_traiter_candidature'],
    declencheurs: ['trg_gate_assignation_paiement'],
  },
  // UPDATE presences : RBAC `pointage` (correction 4) puis garde de fin de planning.
  fn_valider_presence: {
    declencheurs: ['trg_p0_rbac_presences', 'trg_bloquer_validation_presence_avant_fin_planning'],
  },
  fn_valider_presences_lot: {
    declencheurs: ['trg_p0_rbac_presences', 'trg_bloquer_validation_presence_avant_fin_planning'],
  },
  // UPDATE presences.motif_litige : RBAC seulement (valide_par_etablissement inchangé).
  fn_contester_presence: { declencheurs: ['trg_p0_rbac_presences'] },
};

/** SQLSTATE des noms de condition PL/pgSQL employés par `USING ERRCODE` (PostgreSQL, annexe A). */
const CONDITIONS_SQLSTATE = {
  raise_exception: 'P0001', no_data_found: 'P0002', too_many_rows: 'P0003', assert_failure: 'P0004',
  insufficient_privilege: '42501', invalid_authorization_specification: '28000',
  check_violation: '23514', foreign_key_violation: '23503', unique_violation: '23505',
  not_null_violation: '23502', restrict_violation: '23001', invalid_parameter_value: '22023',
  data_exception: '22000', invalid_text_representation: '22P02', invalid_datetime_format: '22007',
  numeric_value_out_of_range: '22003', object_not_in_prerequisite_state: '55000',
  lock_not_available: '55P03', serialization_failure: '40001', feature_not_supported: '0A000',
};

/**
 * Corps de la définition unique d'une fonction publique du dump : texte entre `AS $tag$` et la
 * ligne `$tag$;`. Lève si la fonction est absente ou surchargée (liste blanche ambiguë).
 */
export function corpsFonction(schemaSource, name) {
  const lines = schemaSource.split('\n');
  const prefix = `CREATE OR REPLACE FUNCTION "public"."${name}"(`;
  const debuts = lines.flatMap((l, i) => (l.startsWith(prefix) ? [i] : []));
  if (debuts.length !== 1) {
    throw new Error(`${name} : ${debuts.length} définition(s) dans public.sql, une seule attendue pour extraire ses exceptions.`);
  }
  for (let i = debuts[0] + 1; i < lines.length; i++) {
    const as = /^\s*AS (\$[A-Za-z_]*\$)\s*$/.exec(lines[i]);
    if (!as) continue;
    const fin = lines.indexOf(`${as[1]};`, i + 1);
    if (fin < 0) throw new Error(`${name} : fin de corps ${as[1]}; introuvable.`);
    return { corps: lines.slice(i + 1, fin).join('\n'), ligne: i + 2 };
  }
  throw new Error(`${name} : ligne « AS $tag$ » introuvable.`);
}

/** Littéraux SQL simples d'un fragment (`'…'`, `''` → `'`). */
function litterauxSql(fragment) {
  return [...fragment.matchAll(/'((?:[^']|'')*)'/g)].map(m => m[1].replaceAll("''", "'"));
}

/** Trigger du dump : table visée, fonction exécutée et arguments littéraux. Lève s'il est absent. */
export function declencheur(schemaSource, nom) {
  const re = new RegExp(`^CREATE OR REPLACE TRIGGER "${nom}" .* ON "public"\\."(\\w+)" .*EXECUTE FUNCTION "public"\\."(\\w+)"\\((.*)\\);$`, 'm');
  const m = re.exec(schemaSource);
  if (!m) throw new Error(`Trigger ${nom} introuvable dans public.sql : liste blanche impossible.`);
  return { table: m[1], fonction: m[2], arguments: litterauxSql(m[3]) };
}

/**
 * Masque un corps PL/pgSQL : commentaires retirés, chaînes remplacées par `\u0000<n>\u0000`
 * (valeurs décodées dans `chaines`). Lève sur une chaîne `E'…'` (échappements non pris en charge).
 */
function masquerSql(corps) {
  const chaines = [];
  let sortie = '';
  for (let i = 0; i < corps.length; i++) {
    const c = corps[i];
    if (c === '-' && corps[i + 1] === '-') { while (i < corps.length && corps[i] !== '\n') i++; sortie += '\n'; continue; }
    if (c === '/' && corps[i + 1] === '*') { const fin = corps.indexOf('*/', i + 2); i = fin < 0 ? corps.length : fin + 1; sortie += ' '; continue; }
    if (c === '$') {
      const tag = /^\$[A-Za-z_]*\$/.exec(corps.slice(i));
      if (tag) { const fin = corps.indexOf(tag[0], i + tag[0].length); i = (fin < 0 ? corps.length : fin + tag[0].length) - 1; sortie += ' '; continue; }
    }
    if (c === "'") {
      // Chaîne E'…' : la barre oblique échappe ; repérée pour être refusée si un RAISE l'emploie.
      const echappee = /(^|\W)[Ee]$/.test(sortie);
      if (echappee) sortie = sortie.slice(0, -1);
      let valeur = '';
      let j = i + 1;
      for (; j < corps.length; j++) {
        if (echappee && corps[j] === '\\') { valeur += corps[j] + (corps[j + 1] ?? ''); j++; continue; }
        if (corps[j] === "'" && corps[j + 1] === "'") { valeur += "'"; j++; } else if (corps[j] === "'") break; else valeur += corps[j];
      }
      chaines.push(echappee ? { echappee: valeur } : valeur);
      sortie += `\u0000${chaines.length - 1}\u0000`;
      i = j;
      continue;
    }
    sortie += c;
  }
  return { masque: sortie, chaines };
}

/** Découpe un fragment masqué sur les virgules de premier niveau (hors parenthèses). */
function virgulesHautes(fragment) {
  const parts = [];
  let profondeur = 0;
  let courant = '';
  for (const c of fragment) {
    if (c === '(' || c === '[') profondeur++;
    if (c === ')' || c === ']') profondeur--;
    if (c === ',' && profondeur === 0) { parts.push(courant.trim()); courant = ''; } else courant += c;
  }
  if (courant.trim()) parts.push(courant.trim());
  return parts;
}

const chaineMasquee = (fragment, chaines) => {
  const m = /^\u0000(\d+)\u0000$/.exec(fragment.trim());
  if (!m) return null;
  const valeur = chaines[Number(m[1])];
  if (typeof valeur !== 'string') throw new Error("chaîne E'' non prise en charge dans un RAISE (échappements).");
  return valeur;
};

/**
 * Exceptions levées par un corps PL/pgSQL (`RAISE EXCEPTION`, formes `'fmt'[, args] [USING …]` et
 * `USING ERRCODE = …, MESSAGE = '…'`). `RAISE NOTICE/WARNING/…` et `RAISE;` sont ignorés ; sans
 * `ERRCODE`, le SQLSTATE est `P0001`. `argumentsDeclencheur` instancie les `%` formatés depuis
 * `TG_ARGV[n]` (directement ou via une variable initialisée par `TG_ARGV[n]`). Fail-closed : message
 * entièrement dynamique, condition inconnue, `%%`, chaîne `E''` ou forme inconnue lèvent.
 */
export function exceptionsDuCorps(corps, { fonction, declencheur: nomDeclencheur, argumentsDeclencheur = null }) {
  const { masque, chaines } = masquerSql(corps);
  const variablesArgv = new Map([...masque.matchAll(/\b(\w+)\s+\w+(?:\s*\([^)]*\))?\s*:=\s*TG_ARGV\[(\d+)\]/g)].map(m => [m[1], Number(m[2])]));
  const sorties = [];
  for (const m of masque.matchAll(/\bRAISE\b([^;]*);/gi)) {
    let reste = m[1].trim();
    const niveau = /^(EXCEPTION|NOTICE|WARNING|INFO|LOG|DEBUG)\b/i.exec(reste);
    if (niveau && niveau[1].toUpperCase() !== 'EXCEPTION') continue;
    if (niveau) reste = reste.slice(niveau[0].length).trim();
    if (!reste) continue; // RAISE; (relance dans un bloc EXCEPTION)
    const using = /\bUSING\b/i.exec(reste);
    const tete = (using ? reste.slice(0, using.index) : reste).trim();
    const options = using ? virgulesHautes(reste.slice(using.index + using[0].length)) : [];
    let message = null;
    let args = [];
    if (tete) {
      const [format, ...suite] = virgulesHautes(tete);
      message = chaineMasquee(format, chaines);
      if (message === null) throw new Error(`${fonction} : forme RAISE non prise en charge « RAISE EXCEPTION ${tete} ».`);
      args = suite;
    }
    let sqlstate = 'P0001';
    for (const option of options) {
      const o = /^(\w+)\s*=\s*([\s\S]+)$/.exec(option);
      if (!o) throw new Error(`${fonction} : option USING illisible « ${option} ».`);
      const nom = o[1].toUpperCase();
      const valeur = chaineMasquee(o[2], chaines);
      if (nom === 'ERRCODE') {
        const code = valeur ?? o[2].trim();
        if (/^[0-9A-Z]{5}$/.test(code)) sqlstate = code;
        else if (CONDITIONS_SQLSTATE[code.toLowerCase()]) sqlstate = CONDITIONS_SQLSTATE[code.toLowerCase()];
        else throw new Error(`${fonction} : condition ${code} inconnue (table CONDITIONS_SQLSTATE).`);
      } else if (nom === 'MESSAGE') {
        if (valeur === null) throw new Error(`${fonction} : message entièrement dynamique (MESSAGE = ${o[2].trim()}) : liste blanche impossible.`);
        message = valeur;
      }
    }
    if (message === null) throw new Error(`${fonction} : RAISE EXCEPTION sans message.`);
    if (message.includes('%%')) throw new Error(`${fonction} : %% non pris en charge dans « ${message} ».`);
    let rang = 0;
    message = message.replace(/%/g, () => {
      const arg = (args[rang++] ?? '').trim();
      const direct = /^TG_ARGV\[(\d+)\]$/.exec(arg);
      const index = direct ? Number(direct[1]) : variablesArgv.get(arg);
      if (argumentsDeclencheur && index !== undefined && argumentsDeclencheur[index] !== undefined) return argumentsDeclencheur[index];
      return '%';
    });
    if (!message.replace(/%/g, '').trim()) throw new Error(`${fonction} : message entièrement dynamique « ${message} » : liste blanche impossible.`);
    const entree = { sqlstate, message, fonction };
    if (nomDeclencheur) entree.declencheur = nomDeclencheur;
    if (!sorties.some(e => JSON.stringify(e) === JSON.stringify(entree))) sorties.push(entree);
  }
  return sorties;
}

/** Liste blanche d'une RPC : son corps, puis `config.fonctions`, puis `config.declencheurs`. */
export function extraireExceptions(schemaSource, name, config = {}) {
  const sorties = [];
  const ajouter = liste => {
    for (const e of liste) if (!sorties.some(x => JSON.stringify(x) === JSON.stringify(e))) sorties.push(e);
  };
  for (const fonction of [name, ...(config.fonctions ?? [])]) {
    ajouter(exceptionsDuCorps(corpsFonction(schemaSource, fonction).corps, { fonction }));
  }
  for (const nom of config.declencheurs ?? []) {
    const t = declencheur(schemaSource, nom);
    ajouter(exceptionsDuCorps(corpsFonction(schemaSource, t.fonction).corps, {
      fonction: t.fonction, declencheur: nom, argumentsDeclencheur: t.arguments,
    }));
  }
  return sorties;
}

/**
 * Matrice rôle × permission de l'espace établissement, lue dans le dump : les 11 clés exposées par
 * `fn_mes_permissions_etab`, les rôles du CHECK `membres_etablissement_role_check` et le `CASE` de
 * `fn_a_permission_etablissement` (LOT5_PLAN §2.7). Documentation et fixtures démo seulement : le
 * natif lit les booléens servis, il n'écrit jamais cette correspondance.
 */
export function matricePermissionsEtablissement(schemaSource) {
  const permissions = corpsFonction(schemaSource, 'fn_mes_permissions_etab').corps;
  const cles = [...permissions.matchAll(/'(\w+)', public\.fn_a_permission_etablissement\('\1', v_etab_id\)/g)].map(m => m[1]);
  const check = /CONSTRAINT "membres_etablissement_role_check" CHECK \(\("role" = ANY \(ARRAY\[(.*)\]\)\)\)/.exec(schemaSource);
  if (!check || cles.length === 0) throw new Error('Matrice des permissions établissement illisible dans public.sql.');
  const roles = litterauxSql(check[1]);
  const casSql = corpsFonction(schemaSource, 'fn_a_permission_etablissement').corps;
  const branches = new Map([...casSql.matchAll(/^\s*WHEN '(\w+)' THEN (.+)$/gm)].map(m => [m[1], m[2].trim()]));
  const accorde = (expr, role) => {
    if (expr === 'true') return true;
    if (expr === 'false') return false;
    let m = /^v_role = '(\w+)'$/.exec(expr);
    if (m) return role === m[1];
    m = /^v_role <> '(\w+)'$/.exec(expr);
    if (m) return role !== m[1];
    m = /^v_role IN \((.+)\)$/.exec(expr);
    if (m) return litterauxSql(m[1]).includes(role);
    throw new Error(`fn_a_permission_etablissement : branche illisible « ${expr} ».`);
  };
  return {
    cles,
    roles: Object.fromEntries(roles.map(role => [role, Object.fromEntries(cles.map(cle => {
      if (!branches.has(cle)) throw new Error(`fn_a_permission_etablissement : clé ${cle} sans branche WHEN.`);
      return [cle, accorde(branches.get(cle), role)];
    }))])),
  };
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
    const contrat = {
      name,
      statut,
      lot,
      types,
      // La ligne du dump change à chaque re-baseline ; elle est utile au lecteur, pas au contrat.
      sql: sql.map(({ ligne, ...rest }) => rest),
      grants: extractGrants(schemaSource, name),
      manifeste: manifestCategory(manifest, name),
    };
    // Lot 5 : liste blanche des exceptions interceptées, annotation des RPC partagées.
    if (RPC_SUIVIES_ETABLISSEMENT.some(r => r.name === name)) {
      contrat.exceptions = extraireExceptions(schemaSource, name, EXCEPTIONS_ETABLISSEMENT[name]);
    }
    if (RPC_PARTAGEES_ETABLISSEMENT.includes(name) || (lot < 5 && RPC_SUIVIES_ETABLISSEMENT.some(r => r.name === name))) {
      contrat.aussi_etablissement = true;
    }
    return contrat;
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
    for (const field of ['statut', 'lot', 'types', 'sql', 'grants', 'manifeste', 'exceptions', 'aussi_etablissement']) {
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

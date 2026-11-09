import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  CONTRACTS_PATH,
  RPC_JAMAIS_SUIVIES,
  RPC_SUIVIES,
  SOURCES,
  extractGrants,
  verifierExclusions,
} from '../../scripts/mobile/check-rpc-contracts.mjs';

// Garde du lot 3, tranche T0 (docs/mobile-swift/LOT3_PLAN.md §3 T0) : les RPC et edges du lot 3 sont
// sous contrat AVANT toute gateway Swift, chaque forme de réponse citée par une fiche est confrontée à sa
// source (corps SQL du dump, edge function, page web), et les documents du lot (plan versionné, décisions,
// parité, squelettes de recette et de porte) existent. Aucun réseau, aucun secret : lecture de fichiers
// du dépôt seulement. Fichier séparé de check-rpc-contracts.node.mjs (garde du lot 1) pour que les T0 des
// lots 2 à 5, menées en parallèle, n'éditent pas les mêmes lignes ; même étape CI (validate-pr.yml).

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = relative => readFileSync(join(root, relative), 'utf8');
const SCHEMA = read(SOURCES.schema);
const CONTRATS_PATH = 'docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md';
const CONTRATS = read(CONTRATS_PATH);

// Ordre du blueprint (§3 T0) : ajoutées en `a_venir` lot 3 par cette tranche.
const LOT3_AJOUTS = [
  'fn_desactiver_mon_token_push',
  'fn_obtenir_mes_preferences_notifications',
  'fn_modifier_preferences_notifications',
  'fn_demarrer_inscription',
  'fn_enregistrer_parcours_inscription',
  'fn_types_exercice_autorises',
  'fn_modifier_mon_profil',
  'fn_rgpd_exporter_rate_limited',
  'fn_confirmer_paiement_soignant',
  'fn_contester_paiement_soignant',
  'fn_consulter_mon_iban',
  'fn_enregistrer_mon_iban',
  'fn_mes_revenus_connect',
  'fn_mes_paiements_escrow',
];
// Déjà suivies en lot 3 avant cette tranche (lot 0 pour le token push, T0 du lot 1 pour le profil).
const LOT3_DEJA = ['fn_mon_profil_soignant_complet', 'fn_upsert_token_push'];
const LOT3 = [...LOT3_DEJA, ...LOT3_AJOUTS];
// Câblées par une tranche livrée (statut `consommee`, ligne de synthèse « consommée lot 3 (Tn) ») :
// RPC → [tranche, gateway Swift qui l'appelle]. Chaque tranche qui câble une gateway l'ajoute ici.
const LOT3_CONSOMMEES = new Map([
  ['fn_upsert_token_push', ['T4', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Push/SupabasePushGateway.swift']],
  ['fn_desactiver_mon_token_push', ['T4', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Push/SupabasePushGateway.swift']],
  ['fn_obtenir_mes_preferences_notifications', ['T6', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Notifications/SupabasePreferencesGateway.swift']],
  ['fn_modifier_preferences_notifications', ['T6', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Notifications/SupabasePreferencesGateway.swift']],
  ['fn_mon_profil_soignant_complet', ['T9', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Profil/SupabaseProfilGateway.swift']],
  ['fn_modifier_mon_profil', ['T9', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Profil/SupabaseProfilGateway.swift']],
  ['fn_demarrer_inscription', ['T7', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Inscription/SupabaseInscriptionGateway.swift']],
  ['fn_rgpd_exporter_rate_limited', ['T11', 'ios-native/Packages/JoleneSupabase/Sources/JoleneSupabase/Compte/SupabaseExportGateway.swift']],
]);
// Hors manifeste (capture du 2026-07-29) : classement manuel documentaire (correction 13).
const HORS_MANIFESTE = ['fn_demarrer_inscription', 'fn_enregistrer_parcours_inscription'];
// Absentes de types.ts : contrat tenu par public.sql seul.
const HORS_TYPES = ['fn_demarrer_inscription', 'fn_enregistrer_parcours_inscription', 'fn_mes_paiements_escrow'];

// Sources lues par cette garde, hors RPC suivies : une PR qui en modifie une met la fiche à jour.
const SOURCES_LUES_LOT3 = [
  'supabase/functions/register-soignant/index.ts',
  'supabase/functions/stripe-connect-status/index.ts',
  'supabase/functions/stripe-connect-onboard/index.ts',
  'supabase/functions/send-push/index.ts',
  'supabase/functions/_shared/apns-client.ts',
  'supabase/functions/_shared/errors.ts',
  'supabase/functions/_shared/admin-auth.ts',
  'src/pages/InscriptionRapide.tsx',
  'src/pages/PageStripeConnect.tsx',
  'ios-native/Packages/JoleneCore/Sources/JoleneCore/Links/LinkRouter.swift',
  'fn_reserver_type_compte',
  'fn_lier_iban_verifie_document',
  'notifications_type_check',
  'uq_litige_mission_type_ouvert_legacy',
  'stripe_connect_onboarding_statut_check',
  'journaux_audit_action_check',
  'canal_notification',
  'type_evenement_notification',
];

const byName = new Map(RPC_SUIVIES.map(r => [r.name, r]));

/** Texte d'une section `## <titre>` d'un document Markdown, jusqu'à la section suivante. */
function section(doc, heading) {
  const start = doc.indexOf(`\n## ${heading}`);
  assert.ok(start >= 0, `section « ${heading} » introuvable`);
  const next = doc.indexOf('\n## ', start + 1);
  return doc.slice(start, next < 0 ? undefined : next);
}

/** Corps d'une fonction SQL du dump, quel que soit le délimiteur (`$$`, `$_$`…). */
function sqlBody(name) {
  const start = SCHEMA.indexOf(`CREATE OR REPLACE FUNCTION "public"."${name}"(`);
  assert.ok(start >= 0, `${name} absente de public.sql`);
  const as = SCHEMA.slice(start).match(/\n\s*AS (\$[A-Za-z_]*\$)/);
  assert.ok(as, `${name} : délimiteur de corps introuvable`);
  const end = SCHEMA.indexOf(`\n${as[1]};`, start + as.index + as[0].length);
  assert.ok(end > start, `${name} : fin de corps introuvable`);
  return SCHEMA.slice(start, end);
}

const unSql = s => s.replaceAll("''", "'");
/** Littéraux `'error', '…'` (valeur JSON réelle, apostrophes SQL ramenées à une seule). */
const sqlErrors = body => [...body.matchAll(/'error',\s*'((?:[^']|'')*)'/g)].map(m => unSql(m[1]));
/** Littéraux `'{"error":"…"}'::JSONB`. */
const sqlJsonErrors = body => [...body.matchAll(/'\{"error":"([^"]+)"\}'::JSONB/g)].map(m => m[1]);
/** Codes `'error_code', 'X'`. */
const sqlErrorCodes = body => [...body.matchAll(/'error_code',\s*'([A-Z_]+)'/g)].map(m => m[1]);
/** `RAISE EXCEPTION '<message>' USING ERRCODE = '<sqlstate>'` (hors gabarit `'%'`). */
const sqlRaises = body => [...body.matchAll(/RAISE EXCEPTION '((?:[^']|'')*)' USING ERRCODE\s*=\s*'([0-9A-Z]{5})'/g)]
  .map(m => ({ message: unSql(m[1]), errcode: m[2] }));
/** Texte Markdown hors blocs de code clôturés (les signatures SQL y gardent leurs `''`). */
const horsBlocs = doc => doc.replace(/```[\s\S]*?```/g, '');
/** Chaîne JS entre apostrophes, échappements `\'` ramenés à la valeur réelle. */
const unJs = s => s.replace(/\\'/g, "'");

function ficheContient(fiche, nom, valeurs, quoi) {
  for (const v of valeurs) assert.ok(fiche.includes(v), `${nom} : ${quoi} absent(e) de la fiche : « ${v} »`);
}

// ---------------------------------------------------------------------------------------------
// RPC_SUIVIES et rpc-contracts.json
// ---------------------------------------------------------------------------------------------

test('RPC_SUIVIES : les RPC du lot 3 sont suivies en lot 3, dans l ordre du blueprint (T0)', () => {
  const lot3 = RPC_SUIVIES.filter(r => r.lot === 3).map(r => r.name);
  assert.deepEqual(lot3, LOT3);
  for (const name of LOT3_AJOUTS) {
    const entry = byName.get(name);
    // `consommee` est admis : la PR qui câble la gateway passe le statut (même règle qu'au lot 1).
    assert.ok(['a_venir', 'consommee'].includes(entry.statut), `${name} : statut ${entry.statut}`);
  }
  // Pas de position absolue dans RPC_SUIVIES : les T0 des autres lots y ajoutent leurs propres entrées ; l'ordre
  // relatif du lot 3 est tenu par le deepEqual ci-dessus.
});

test('RPC_SUIVIES : les RPC câblées par une tranche du lot 3 sont consommées, appelées par leur gateway et fichées', () => {
  for (const name of LOT3) {
    const attendu = LOT3_CONSOMMEES.has(name) ? 'consommee' : 'a_venir';
    assert.equal(byName.get(name).statut, attendu, `${name} : statut attendu ${attendu}`);
  }
  const contrats = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  const parNom = new Map(contrats.rpcs.map(r => [r.name, r]));
  for (const [name, [tranche, gateway]] of LOT3_CONSOMMEES) {
    assert.equal(parNom.get(name)?.statut, 'consommee', `${name} : rpc-contracts.json non régénéré (--update)`);
    const source = read(gateway);
    assert.ok(source.includes(`"${name}"`), `${name} : littéral absent de ${gateway}`);
    const fiche = section(CONTRATS, name);
    const fichier = gateway.split('/Sources/')[1];
    assert.ok(fiche.includes(`- **Statut natif** : consommée (lot 3, ${tranche}) par \`${fichier}\``),
      `${name} : fiche « Statut natif » non mise à jour (consommée, ${tranche}, ${fichier})`);
  }
});

test('rpc-contracts.json : RPC du lot 3 — GRANT authenticated, manifeste et types.ts tels qu observés', () => {
  const contrats = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
  const parNom = new Map(contrats.rpcs.map(r => [r.name, r]));
  for (const name of LOT3) {
    const entry = parNom.get(name);
    assert.ok(entry, `${name} absente de rpc-contracts.json (lancer --update)`);
    assert.equal(entry.lot, 3, `${name} : lot ${entry.lot} dans le JSON`);
    assert.ok(entry.grants.includes('authenticated'), `${name} : pas de GRANT authenticated`);
    assert.equal(entry.manifeste === null, HORS_MANIFESTE.includes(name), `${name} : présence au manifeste inattendue`);
    assert.equal(entry.types === null, HORS_TYPES.includes(name), `${name} : présence dans types.ts inattendue`);
  }
  // Témoins cités par les fiches.
  assert.equal(parNom.get('fn_upsert_token_push').sql[0].returns, '"void"');
  assert.deepEqual(parNom.get('fn_types_exercice_autorises').grants, ['anon', 'authenticated', 'service_role']);
  assert.equal(parNom.get('fn_types_exercice_autorises').manifeste[0].category, 'PUBLIC_VOLONTAIRE');
  assert.equal(parNom.get('fn_contester_paiement_soignant').manifeste[0].category, 'MIXTE_TENANT_ADMIN');
});

test('RPC_JAMAIS_SUIVIES : fn_lier_iban_verifie_document (service_role seul, contournerait la garde IBAN)', () => {
  assert.ok(RPC_JAMAIS_SUIVIES.includes('fn_lier_iban_verifie_document'));
  assert.ok(RPC_JAMAIS_SUIVIES.includes('fn_etablissement_public'), 'l exclusion du lot 1 est conservée');
  assert.throws(
    () => verifierExclusions([...RPC_SUIVIES, { name: 'fn_lier_iban_verifie_document', statut: 'a_venir', lot: 3 }]),
    /jamais/,
  );
  // Témoins SQL : GRANT au seul service_role, garde interne, appel par fn_enregistrer_mon_iban (SECURITY DEFINER).
  assert.deepEqual(extractGrants(SCHEMA, 'fn_lier_iban_verifie_document'), ['service_role']);
  assert.match(sqlBody('fn_lier_iban_verifie_document'), /RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501'/);
  assert.match(sqlBody('fn_enregistrer_mon_iban'), /RETURN public\.fn_lier_iban_verifie_document\(v_rib\.id, v_rib\.s3_cle, p_iban\);/);
  const fiche = section(CONTRATS, 'Interdite côté natif : `fn_lier_iban_verifie_document`');
  ficheContient(fiche, 'fn_lier_iban_verifie_document', ['service_role', '42501', 'Service role requis', '`fn_enregistrer_mon_iban`'], 'fait');
  // Le bloc « Jamais suivies » du script cite la RPC et son motif.
  const source = read('scripts/mobile/check-rpc-contracts.mjs');
  const jamais = source.slice(source.indexOf('Jamais suivies'), source.indexOf('Pas avant le lot 4'));
  assert.ok(jamais.includes('fn_lier_iban_verifie_document') && jamais.includes('service_role'));
});

// ---------------------------------------------------------------------------------------------
// Fiches RPC : synthèse, classement, formes de réponse confrontées au corps SQL
// ---------------------------------------------------------------------------------------------

test('CONTRATS : en-tête et synthèse — lot 3 annoncé, une ligne par RPC, sources lues listées', () => {
  const entete = CONTRATS.slice(0, CONTRATS.indexOf('\n## Synthèse'));
  assert.ok(entete.includes('`docs/mobile-swift/LOT3_PLAN.md`'), 'en-tête : renvoi au plan du lot 3 absent');
  assert.ok(entete.includes('tests/node/check-rpc-contracts-lot3.node.mjs'), 'en-tête : garde du lot 3 non citée');
  const autres = entete.slice(entete.indexOf('**Autres sources lues par la garde.**'));
  for (const source of SOURCES_LUES_LOT3) assert.ok(autres.includes(source), `« Autres sources lues » : ${source} absent`);
  const synthese = section(CONTRATS, 'Synthèse');
  for (const name of LOT3_AJOUTS) {
    const ligne = synthese.split('\n').find(l => l.startsWith(`| \`${name}\` |`));
    assert.ok(ligne, `synthèse : ligne absente pour ${name}`);
    if (LOT3_CONSOMMEES.has(name)) {
      const [tranche] = LOT3_CONSOMMEES.get(name);
      assert.ok(ligne.includes(`| consommée lot 3 (${tranche}) | 3 (${tranche}) |`), `synthèse : ${name} doit être « consommée lot 3 (${tranche}) »`);
    } else {
      assert.ok(/\| à venir \| 3 /.test(ligne), `synthèse : ${name} doit être « à venir », lot 3`);
    }
  }
  for (const name of HORS_MANIFESTE) {
    const ligne = synthese.split('\n').find(l => l.startsWith(`| \`${name}\` |`));
    assert.ok(ligne.includes('hors manifeste — classée RPC_UTILISATEUR_AUTH_INTERNE (T0 du lot 3)'), `synthèse : classement de ${name}`);
  }
  // Actions d'audit écrites par l'app au lot 3 : présentes dans le CHECK (CLAUDE.md, migrations n°4).
  const check = SCHEMA.split('\n').find(l => l.includes('CONSTRAINT "journaux_audit_action_check"'));
  for (const action of ['DONNEES_PERSO_CONSULTATION', 'DONNEES_PERSO_MODIFICATION', 'RGPD_EXPORT_DONNEES']) {
    assert.ok(check.includes(`'${action}'::"text"`), `témoin SQL : ${action} absente de journaux_audit_action_check`);
    assert.ok(entete.includes(`\`${action}\``), `en-tête : action d audit ${action} non citée`);
  }
  assert.ok(entete.includes('Règles ajoutées au lot 3') && entete.includes('`exceptionsMetier`') && entete.includes('`EdgeResponse`'),
    'en-tête : règles du lot 3 (exceptions métier, EdgeResponse) absentes');
});

test('CONTRATS : fn_demarrer_inscription et fn_enregistrer_parcours_inscription classées dans la fiche seule', () => {
  for (const name of HORS_MANIFESTE) {
    const fiche = section(CONTRATS, name);
    const classe = fiche.split('\n').find(l => l.startsWith("- **Classe d'authentification (manifeste)**"));
    assert.ok(classe, `${name} : ligne « Classe d authentification » absente`);
    assert.ok(classe.includes('hors manifeste') && classe.includes('`RPC_UTILISATEUR_AUTH_INTERNE`'), `${name} : classement manuel absent`);
    assert.ok(classe.includes('aucun fichier sous `supabase/`'), `${name} : la fiche doit exclure toute régénération du manifeste`);
    // Témoins : SECURITY DEFINER, auth.uid(), GRANT authenticated.
    const body = sqlBody(name);
    assert.match(body, /SECURITY DEFINER/);
    assert.match(body, /auth\.uid\(\)/);
    assert.ok(extractGrants(SCHEMA, name).includes('authenticated'));
  }
});

test('CONTRATS : fn_upsert_token_push — void, exceptions 42501/22023 citées, appel sans décodage de corps', () => {
  const body = sqlBody('fn_upsert_token_push');
  const fiche = section(CONTRATS, 'fn_upsert_token_push');
  const raises = sqlRaises(body);
  assert.equal(raises.length, 6, `témoin : 6 RAISE, lus ${raises.length}`);
  for (const { message, errcode } of raises) {
    assert.ok(fiche.includes(`'${message}'`) && fiche.includes(errcode), `fiche : « ${message} » (${errcode}) absent`);
  }
  ficheContient(fiche, 'fn_upsert_token_push', ['`void`', '`execute()`', 'correction 16', "'IOS'", '`exceptionsMetier`'], 'élément');
});

test('CONTRATS : fn_desactiver_mon_token_push — refus {success:false, error} et succès CURRENT_DEVICE', () => {
  const body = sqlBody('fn_desactiver_mon_token_push');
  const fiche = section(CONTRATS, 'fn_desactiver_mon_token_push');
  const erreurs = sqlErrors(body);
  assert.deepEqual(erreurs, ['Non authentifie', 'Token push invalide']);
  for (const e of erreurs) assert.ok(fiche.includes(`error:'${e}'`), `refus absent : ${e}`);
  ficheContient(fiche, 'fn_desactiver_mon_token_push', ['tokens_desactives', "scope:'CURRENT_DEVICE'", '2,5 s'], 'élément');
});

test('CONTRATS : préférences de notifications — formes, enums et effet de bord de la lecture', () => {
  const lire = sqlBody('fn_obtenir_mes_preferences_notifications');
  const modifier = sqlBody('fn_modifier_preferences_notifications');
  const ficheLire = section(CONTRATS, 'fn_obtenir_mes_preferences_notifications');
  const ficheModifier = section(CONTRATS, 'fn_modifier_preferences_notifications');
  assert.deepEqual(sqlErrors(lire), ['Non authentifié']);
  assert.deepEqual(sqlErrors(modifier), ['Non authentifié']);
  assert.match(lire, /INSERT INTO preferences_notifications \(utilisateur_id\) VALUES \(v_uid\)/);
  ficheContient(ficheLire, 'fn_obtenir…', ["error:'Non authentifié'", 'global', 'par_evenement', 'canal_email', 'canal_sms', 'canal_push', 'canal_in_app', 'crée la ligne'], 'élément');
  ficheContient(ficheModifier, 'fn_modifier…', ["error:'Non authentifié'", '{success:true}', '22P02', 'PREFERENCE_NOTIFICATION_MODIFIEE'], 'élément');
  const enumValeurs = nom => {
    const at = SCHEMA.indexOf(`CREATE TYPE "public"."${nom}" AS ENUM (`);
    assert.ok(at >= 0, `enum ${nom} absente`);
    return [...SCHEMA.slice(at, SCHEMA.indexOf(');', at)).matchAll(/'([A-Z0-9_]+)'/g)].map(m => m[1]);
  };
  const canaux = enumValeurs('canal_notification');
  assert.deepEqual(canaux, ['EMAIL', 'SMS', 'PUSH', 'IN_APP']);
  ficheContient(ficheModifier, 'fn_modifier…', canaux.map(c => `\`${c}\``), 'canal');
  const types = enumValeurs('type_evenement_notification');
  assert.equal(types.length, 18, `témoin : 18 types d événement, lus ${types.length}`);
  ficheContient(ficheModifier, 'fn_modifier…', types.map(t => `\`${t}\``), 'type d événement');
});

test('CONTRATS : fn_demarrer_inscription — exceptions verbatim, codes de réservation, message web du 23505', () => {
  const body = sqlBody('fn_demarrer_inscription');
  const fiche = section(CONTRATS, 'fn_demarrer_inscription');
  const raises = sqlRaises(body);
  assert.equal(raises.length, 4, `témoin : 4 RAISE à message fixe, lus ${raises.length}`);
  for (const { message, errcode } of raises) {
    assert.ok(fiche.includes(`'${message}'`) && fiche.includes(errcode), `fiche : « ${message} » (${errcode}) absent`);
  }
  assert.match(body, /RAISE EXCEPTION '%', v_reservation ->> 'code' USING ERRCODE = '23505'/);
  const reservation = sqlBody('fn_reserver_type_compte');
  const codes = [...new Set([...reservation.matchAll(/'code',\s*'(ACCOUNT_[A-Z_]+)'/g)].map(m => m[1]))];
  assert.deepEqual(codes.sort(), [
    'ACCOUNT_ALREADY_REGISTERED', 'ACCOUNT_AUTH_INACTIVE', 'ACCOUNT_PROFILE_CONFLICT', 'ACCOUNT_REGISTRATION_INCOMPLETE',
    'ACCOUNT_REGISTRATION_IN_PROGRESS', 'ACCOUNT_TYPE_INVALID', 'ACCOUNT_TYPE_MISMATCH',
  ]);
  ficheContient(fiche, 'fn_demarrer_inscription', codes.map(c => `\`${c}\``), 'code de réservation');
  // Message web (InscriptionRapide.tsx) pour les trois codes qui signalent un espace existant.
  const web = read('src/pages/InscriptionRapide.tsx');
  const regle = web.match(/\/(ACCOUNT_ALREADY_REGISTERED\|ACCOUNT_TYPE_MISMATCH\|ACCOUNT_REGISTRATION_INCOMPLETE)\/\.test\(\s*message,?\s*\)\s*\?\s*"([^"]+)"/);
  assert.ok(regle, 'témoin web : règle 23505 de InscriptionRapide.tsx introuvable');
  assert.ok(fiche.includes(regle[2]), `message web absent : « ${regle[2]} »`);
  ficheContient(fiche, 'fn_demarrer_inscription', ['`parcours_inscription`', 'consentement_cgu_le', 'B9'], 'élément');
});

test('CONTRATS : fn_enregistrer_parcours_inscription — exceptions et liste blanche du brouillon', () => {
  const body = sqlBody('fn_enregistrer_parcours_inscription');
  const fiche = section(CONTRATS, 'fn_enregistrer_parcours_inscription');
  const raises = sqlRaises(body);
  assert.equal(raises.length, 6, `témoin : 6 RAISE, lus ${raises.length}`);
  for (const { message, errcode } of raises) {
    assert.ok(fiche.includes(`'${message}'`) && fiche.includes(errcode), `fiche : « ${message} » (${errcode}) absent`);
  }
  const liste = body.match(/WHERE k NOT IN \(([\s\S]*?)\)\) THEN RAISE EXCEPTION 'Champ non autorisé/);
  assert.ok(liste, 'témoin SQL : liste blanche introuvable');
  const cles = [...liste[1].matchAll(/'([A-Za-z]+)'/g)].map(m => m[1]);
  assert.equal(cles.length, 30, `témoin : 30 clés autorisées, lues ${cles.length}`);
  ficheContient(fiche, 'fn_enregistrer_parcours_inscription', cles.map(c => `\`${c}\``), 'clé autorisée');
  assert.ok(/jamais[^.]*mot de passe/.test(fiche), 'la fiche doit exclure mot de passe et email du brouillon');
});

test('CONTRATS : fn_types_exercice_autorises — défaut serveur et ouverture anon consignés', () => {
  const body = sqlBody('fn_types_exercice_autorises');
  assert.match(body, /RETURN COALESCE\(v_result, ARRAY\['SALARIE', 'LIBERAL', 'MIXTE'\]\);/);
  const fiche = section(CONTRATS, 'fn_types_exercice_autorises');
  ficheContient(fiche, 'fn_types_exercice_autorises', ['`SALARIE`', '`LIBERAL`', '`MIXTE`', '`regles_exercice_profession`', 'PUBLIC_VOLONTAIRE', 'anon'], 'élément');
});

test('CONTRATS : profil — refus de fn_modifier_mon_profil, COALESCE, clés sensibles de fn_mon_profil_soignant_complet', () => {
  const modifier = sqlBody('fn_modifier_mon_profil');
  const ficheModifier = section(CONTRATS, 'fn_modifier_mon_profil');
  const erreurs = sqlErrors(modifier);
  assert.deepEqual(erreurs, ['Non authentifié', 'Le prénom ne peut pas être vide', 'Le nom ne peut pas être vide']);
  for (const e of erreurs) assert.ok(ficheModifier.includes(`error:'${e}'`), `refus absent : ${e}`);
  ficheContient(ficheModifier, 'fn_modifier_mon_profil', ['COALESCE', 'MODIFICATION_PROFIL', 'rpps_verifie', '{success:true}'], 'élément');
  const lire = sqlBody('fn_mon_profil_soignant_complet');
  const ficheLire = section(CONTRATS, 'fn_mon_profil_soignant_complet');
  for (const e of sqlErrors(lire)) assert.ok(ficheLire.includes(`error:'${e}'`), `refus absent : ${e}`);
  const sensibles = ['numero_secu', 'numero_adeli', 'siret_liberal', 'code_ape', 'assujetti_tva', 'numero_tva', 'stripe_account_id', 'iban_last4'];
  for (const cle of sensibles) {
    assert.match(lire, new RegExp(`\\b${cle}\\b`), `témoin SQL : ${cle} n est plus sélectionnée`);
    assert.ok(ficheLire.includes(`\`${cle}\``), `fiche profil : clé sensible ${cle} non citée`);
  }
  assert.ok(ficheLire.includes('liste blanche'), 'fiche profil : décodage en liste blanche non consigné');
});

test('CONTRATS : fn_rgpd_exporter_rate_limited — refus en valeur JSON réelle', () => {
  const fiche = section(CONTRATS, 'fn_rgpd_exporter_rate_limited');
  const erreurs = sqlErrors(sqlBody('fn_rgpd_exporter_rate_limited'));
  assert.deepEqual(erreurs, ['Non authentifié', "Trop d'exports en peu de temps. Réessayez dans quelques minutes."]);
  for (const e of erreurs) assert.ok(fiche.includes(`"${e}"`) || fiche.includes(`'${e}'`), `refus absent : ${e}`);
  ficheContient(fiche, 'fn_rgpd_exporter_rate_limited', ['30', 'RGPD_EXPORT_DONNEES'], 'élément');
  // T11 : corps rendu octet pour octet (ordre des clés du jsonb jusqu'au fichier), signalement `publie_le` confirmé live.
  ficheContient(fiche, 'fn_rgpd_exporter_rate_limited', ['octet pour octet', 'publie_le IS NOT NULL', 'confirmé sur la définition live'], 'élément T11');
  // Revue fraîche B8 de L3-TJ (mineur 1) : second lecteur à visibilité conditionnelle, instruit par la même PR backend.
  ficheContient(fiche, 'fn_rgpd_exporter_rate_limited', ['`evaluations_recues`', '`pol_eval_select`', 'visible'], 'élément TJ4');
});

test('CONTRATS : paiements déclarés — refus de la confirmation, contestation corrigée par B3 (#1118)', () => {
  const confirmer = sqlBody('fn_confirmer_paiement_soignant');
  const ficheConfirmer = section(CONTRATS, 'fn_confirmer_paiement_soignant');
  const erreurs = sqlErrors(confirmer);
  assert.equal(erreurs.length, 5, `témoin : 5 refus, lus ${erreurs.length}`);
  for (const e of erreurs) assert.ok(ficheConfirmer.includes(e), `refus absent : ${e}`);
  ficheContient(ficheConfirmer, 'fn_confirmer_paiement_soignant', ['confirme_le', 'facture_honoraires_id', '`CONFIRME`'], 'élément');

  const contester = sqlBody('fn_contester_paiement_soignant');
  const ficheContester = section(CONTRATS, 'fn_contester_paiement_soignant');
  // B3 (#1118, migration 20261102205808) : tous les refus sont `{error, error_code}`, aucune forme `'{"error":…}'::JSONB`.
  assert.deepEqual(sqlJsonErrors(contester), [], 'témoin SQL : ancienne forme de refus revenue — relire la fiche');
  const codes = [...new Set(sqlErrorCodes(contester))];
  assert.deepEqual(codes, ['NON_AUTHENTIFIE', 'MOTIF_INVALIDE', 'PAIEMENT_INTROUVABLE', 'ACCES_REFUSE', 'DEJA_CONTESTE',
    'DEJA_CONFIRME', 'STATUT_INVALIDE', 'LITIGE_DEJA_OUVERT']);
  ficheContient(ficheContester, 'fn_contester_paiement_soignant', codes.map(c => `\`${c}\``), 'error_code');
  const refus = sqlErrors(contester);
  assert.equal(refus.length, 9, `témoin : 9 refus, lus ${refus.length}`);
  for (const e of refus) assert.ok(horsBlocs(ficheContester).includes(e.trim()), `refus absent : ${e}`);
  // Correction 3 levée : plus d'INSERT du type refusé par le CHECK des notifications (23514), qui ne l'autorise toujours pas.
  assert.ok(!contester.includes("'CONTESTATION_PAIEMENT'"), 'témoin SQL : INSERT CONTESTATION_PAIEMENT revenu (23514) — relire la fiche');
  const check = SCHEMA.split('\n').find(l => l.includes('CONSTRAINT "notifications_type_check"'));
  assert.ok(check && !check.includes("'CONTESTATION_PAIEMENT'"), 'témoin SQL : CONTESTATION_PAIEMENT désormais autorisé — relire la fiche');
  // Idempotence et concurrence : verrou de ligne, 23505 de l'index legacy restituée en refus, succès avec litige_id.
  assert.match(contester, /FROM public\.paiements_soignant\s+WHERE id = p_paiement_id\s+FOR UPDATE;/, 'témoin SQL : verrou de ligne');
  assert.ok(contester.includes('EXCEPTION WHEN unique_violation') && contester.includes("'uq_litige_mission_type_ouvert_legacy'"),
    'témoin SQL : 23505 de uq_litige_mission_type_ouvert_legacy non restituée');
  assert.ok(SCHEMA.includes('CREATE UNIQUE INDEX "uq_litige_mission_type_ouvert_legacy"'));
  assert.ok(contester.includes("jsonb_build_object('success', true, 'litige_id', v_litige_id)"), 'témoin SQL : forme du succès');
  ficheContient(ficheContester, 'fn_contester_paiement_soignant',
    ['23514', '23505', '`uq_litige_mission_type_ouvert_legacy`', 'B3', '#1118', '`FOR UPDATE`', 'verrou', '{success:true, litige_id}'], 'élément');
});

test('CONTRATS : IBAN — neuf error_code (dont sept sans error), deux messages serveur, formes de consultation', () => {
  const enregistrer = sqlBody('fn_enregistrer_mon_iban');
  const lier = sqlBody('fn_lier_iban_verifie_document');
  const fiche = section(CONTRATS, 'fn_enregistrer_mon_iban');
  const codes = [...sqlErrorCodes(enregistrer), ...sqlErrorCodes(lier)];
  assert.deepEqual(codes, [
    'NON_AUTHENTIFIE', 'PROFIL_INTROUVABLE', 'TITULAIRE_NON_CONCORDANT', 'RIB_VERIFIE_REQUIS',
    'IBAN_INVALIDE', 'RIB_COURANT_REQUIS', 'IDENTITE_VERIFIEE_REQUISE', 'IDENTITE_COURANTE_REQUISE', 'RIB_NON_CONCORDANT',
  ]);
  ficheContient(fiche, 'fn_enregistrer_mon_iban', codes.map(c => `\`${c}\``), 'error_code');
  const messages = sqlErrors(enregistrer);
  assert.equal(messages.length, 2, 'témoin : deux error_code seulement portent un `error`');
  for (const m of messages) assert.ok(fiche.includes(m), `message serveur absent : ${m}`);
  ficheContient(fiche, 'fn_enregistrer_mon_iban', ['`success == true`', 'SectionPaiements.tsx', 'iban_preuve_hash_v1', 'source_document_id'], 'élément');
  // Revue fraîche B8 de L3-TJ (mineur 3) : les messages des sept codes suivent TJ6, plus « à relire, §6.7 du blueprint ».
  assert.ok(!fiche.includes('à relire') && !fiche.includes('§6.7'), 'fiche IBAN : renvoi périmé (messages tranchés par TJ6)');
  ficheContient(fiche, 'fn_enregistrer_mon_iban', ['TJ6', 'Décisions déléguées du 8 novembre 2026'], 'renvoi');
  const consulter = sqlBody('fn_consulter_mon_iban');
  const ficheConsulter = section(CONTRATS, 'fn_consulter_mon_iban');
  for (const cle of ['iban_renseigne', 'iban_verifie', 'verification_requise', 'iban_last4', 'iban_titulaire']) {
    assert.ok(consulter.includes(`'${cle}'`), `témoin SQL : ${cle}`);
    assert.ok(ficheConsulter.includes(cle), `fiche consultation IBAN : ${cle} absent`);
  }
  for (const e of sqlErrors(consulter)) assert.ok(ficheConsulter.includes(`error:'${e}'`), `refus absent : ${e}`);
});

test('CONTRATS : revenus — clés de fn_mes_revenus_connect, sept états de fn_mes_paiements_escrow', () => {
  const revenus = sqlBody('fn_mes_revenus_connect');
  const ficheRevenus = section(CONTRATS, 'fn_mes_revenus_connect');
  for (const cle of ['mois_en_cours', 'total', 'en_attente', 'stripe_connect_actif']) {
    assert.ok(revenus.includes(`'${cle}'`), `témoin SQL : ${cle}`);
    assert.ok(ficheRevenus.includes(`\`${cle}\``), `fiche revenus : ${cle} absent`);
  }
  const escrow = sqlBody('fn_mes_paiements_escrow');
  const ficheEscrow = section(CONTRATS, 'fn_mes_paiements_escrow');
  const calc = escrow.slice(escrow.indexOf('calc AS ('), escrow.indexOf('END AS etat'));
  const etats = [...new Set([...calc.matchAll(/(?:THEN|ELSE)\s+'([A-Z_]+)'/g)].map(m => m[1]))];
  assert.deepEqual([...etats].sort(), ['ANNULE', 'ATTENTE_VALIDATION', 'LITIGE', 'RESERVE', 'RETARDE', 'VERSE', 'VERSEMENT_EN_COURS']);
  ficheContient(ficheEscrow, 'fn_mes_paiements_escrow', etats.map(e => `\`${e}\``), 'état');
  for (const cle of ['mission_id', 'mission_intitule', 'etablissement_nom', 'honoraires_cents', 'etat', 'date_affichee', 'mission_date', 'a_litige']) {
    assert.ok(escrow.includes(`'${cle}',`), `témoin SQL : ${cle}`);
    assert.ok(ficheEscrow.includes(`\`${cle}\``), `fiche escrow : ${cle} absent`);
  }
});

// ---------------------------------------------------------------------------------------------
// Fiches edge : register-soignant, stripe-connect-status, stripe-connect-onboard, payload send-push, PSC
// ---------------------------------------------------------------------------------------------

/** Statuts et messages de `verifyUserOrServiceRole` (_shared/admin-auth.ts). */
function verifyUserOrServiceRole() {
  const auth = read('supabase/functions/_shared/admin-auth.ts');
  const debut = auth.indexOf('export async function verifyUserOrServiceRole');
  const verify = auth.slice(debut, auth.indexOf('export async function verifyAdminOrServiceRole'));
  assert.ok(debut >= 0 && verify.length > 0, 'verifyUserOrServiceRole introuvable');
  return [...verify.matchAll(/status:\s*(\d{3}),\s*error:\s*'([^']+)'/g)].map(m => ({ statut: m[1], message: m[2] }));
}

test('CONTRATS : edge register-soignant — chaque statut, code et message de index.ts', () => {
  const fiche = section(CONTRATS, 'Edge `register-soignant`');
  const src = read('supabase/functions/register-soignant/index.ts');
  // Témoin du format d'erreur partagé : `error` est le miroir de `message`.
  assert.match(read('supabase/functions/_shared/errors.ts'), /ok: false,\s*code,\s*message,\s*error: message,/);
  const triples = [...src.matchAll(/errorResponse\(cors,\s*(\d{3}),\s*'([A-Z_]+)',\s*'((?:[^'\\]|\\.)*)'/g)]
    .map(m => ({ statut: m[1], code: m[2], message: unJs(m[3]) }));
  const replis = [...src.matchAll(/errorResponse\(cors,\s*(\d{3}),\s*'([A-Z_]+)',\s*verification\.message \|\| '((?:[^'\\]|\\.)*)'/g)]
    .map(m => ({ statut: m[1], code: m[2], message: unJs(m[3]) }));
  const verifier = [...src.matchAll(/code: '(RPPS_[A-Z_]+)', message: '((?:[^'\\]|\\.)*)'/g)].map(m => ({ code: m[1], message: unJs(m[2]) }));
  const reservation = [...src.slice(src.indexOf("code === 'ACCOUNT_ALREADY_REGISTERED'"), src.indexOf('return errorResponse(cors, status, code, message);'))
    .matchAll(/[?:]\s*'((?:[^'\\]|\\.)*)'/g)].map(m => unJs(m[1]));
  // Témoins : 16 réponses littérales, 2 replis de vérification RPPS, 4 messages de l'annuaire, 3 messages de réservation.
  assert.equal(triples.length, 16, `réponses littérales lues : ${triples.length}`);
  assert.equal(replis.length, 2);
  assert.equal(verifier.length, 4);
  assert.equal(reservation.length, 3);
  for (const { statut, code, message } of [...triples, ...replis]) {
    assert.ok(fiche.includes(`**${statut}**`), `statut ${statut} absent`);
    assert.ok(fiche.includes(`'${code}'`), `code ${code} absent`);
    assert.ok(fiche.includes(message), `message absent : « ${message} »`);
  }
  for (const { code, message } of verifier) assert.ok(fiche.includes(code) && fiche.includes(message), `annuaire : ${code}`);
  for (const message of reservation) assert.ok(fiche.includes(message), `réservation : « ${message} »`);
  assert.match(src, /const status = code === 'ACCOUNT_AUTH_INACTIVE' \? 401 : 409;/);
  ficheContient(fiche, 'register-soignant', [
    '{ok:true, success:true, soignant_id}', 'verify_jwt = false', '`FunctionsError.httpError`', '`EdgeResponse`',
    "['MEDECIN', 'DENTISTE', 'SAGE_FEMME', 'PHARMACIEN']", '5 appels / 10 min', '`ACCOUNT_AUTH_INACTIVE`',
    'Ce numéro RPPS correspond à la profession «',
  ], 'élément');
  assert.ok(src.includes("const PROFESSIONS_RPPS_REQUIS = ['MEDECIN', 'DENTISTE', 'SAGE_FEMME', 'PHARMACIEN'];"), 'témoin edge : liste RPPS requis');
});

test('CONTRATS : edge stripe-connect-status — POST, force=true, six statuts, chaque erreur', () => {
  const fiche = section(CONTRATS, 'Edge `stripe-connect-status`');
  const src = read('supabase/functions/stripe-connect-status/index.ts');
  const erreurs = [...src.matchAll(/jsonResponse\(req,\s*\{\s*error:\s*'([^']+)'(?:,\s*message:\s*'([^']+)')?\s*\},\s*(\d{3})\)/g)]
    .map(m => ({ error: m[1], message: m[2] ?? null, statut: m[3] }));
  assert.equal(erreurs.length, 7, `témoin : 7 erreurs littérales, lues ${erreurs.length}`);
  for (const { error, message, statut } of erreurs) {
    assert.ok(fiche.includes(`**${statut}**`) && fiche.includes(error), `erreur absente : ${statut} ${error}`);
    if (message) assert.ok(fiche.includes(message), `message absent : ${message}`);
  }
  for (const { statut, message } of verifyUserOrServiceRole()) {
    assert.ok(fiche.includes(`**${statut}**`) && fiche.includes(message), `verifyUserOrServiceRole : ${statut} ${message}`);
  }
  const check = SCHEMA.split('\n').find(l => l.includes('CONSTRAINT "stripe_connect_onboarding_statut_check"'));
  const statuts = [...check.matchAll(/'([A-Z_]+)'::"text"/g)].map(m => m[1]);
  assert.deepEqual(statuts, ['NON_DEMANDE', 'EN_COURS', 'COMPLET', 'SUSPENDU', 'REJETE', 'SUPPRIME']);
  ficheContient(fiche, 'stripe-connect-status', statuts.map(s => `\`${s}\``), 'statut');
  assert.match(src, /const CACHE_TTL_MS = 5 \* 60 \* 1000;/);
  assert.match(src, /url\.searchParams\.get\("force"\) === "true"/);
  const supprime = src.match(/message: "(Votre compte Stripe Connect a été supprimé[^"]+)"/)[1];
  ficheContient(fiche, 'stripe-connect-status', ['`POST`', '`?force=true`', '5 min', 'correction 17', supprime, 'account_deleted', 'verify_jwt = false'], 'élément');
});

test('CONTRATS : edge stripe-connect-onboard — Origin requise, chaque erreur, return_url et refresh_url', () => {
  const fiche = section(CONTRATS, 'Edge `stripe-connect-onboard`');
  const src = read('supabase/functions/stripe-connect-onboard/index.ts');
  // Clé `error:` d'un objet littéral (le libellé de log « …onboard error: » n'est pas une réponse).
  const erreurs = [...new Set([...src.matchAll(/[{\s]error:\s*"([^"\n]+)"/g)].map(m => m[1]))];
  assert.deepEqual(erreurs, [
    'Non autorisé', 'ORIGINE_NON_AUTORISEE', 'Soignant introuvable', 'TEST_ACCOUNT_CLASSIFICATION_UNAVAILABLE',
    'TEST_ACCOUNT_PAYMENT_DISABLED', 'Stripe Connect est réservé aux soignants en exercice libéral ou mixte',
  ]);
  for (const e of erreurs) assert.ok(fiche.includes(e), `erreur absente : ${e}`);
  const statuts = [...new Set([...src.matchAll(/status:\s*(\d{3})/g)].map(m => m[1]))];
  assert.deepEqual(statuts.sort(), ['200', '401', '403', '404', '503']);
  for (const s of statuts) assert.ok(fiche.includes(`**${s}**`), `statut ${s} absent`);
  assert.match(src, /if \(!requestOrigin \|\| getCorsOrigin\(req\) !== requestOrigin\) return null;/);
  ficheContient(fiche, 'stripe-connect-onboard', [
    '`Origin: https://jolene.app`', 'correction 1', '/soignant/stripe-connect?success=true', '/soignant/stripe-connect?refresh=true',
    '{success:true, url, account_id}', 'Stripe désactivé sur ce compte de test', 'verify_jwt = false',
  ], 'élément');
  assert.ok(read('src/pages/PageStripeConnect.tsx').includes('Stripe désactivé sur ce compte de test'), 'témoin web : texte du compte de test');
});

test('CONTRATS : payload send-push — clés racine APNs, ALLOWED_DATA_KEYS, lien normalisé', () => {
  const fiche = section(CONTRATS, 'Payload `send-push` (taps de notification)');
  const src = read('supabase/functions/send-push/index.ts');
  const bloc = src.match(/const ALLOWED_DATA_KEYS = new Set\(\[([\s\S]*?)\]\);/);
  assert.ok(bloc, 'témoin edge : ALLOWED_DATA_KEYS introuvable');
  const cles = [...bloc[1].matchAll(/'([a-z_]+)'/g)].map(m => m[1]);
  assert.equal(cles.length, 14, `témoin : 14 clés, lues ${cles.length}`);
  ficheContient(fiche, 'send-push', cles.map(c => `\`${c}\``), 'clé de données');
  const apns = read('supabase/functions/_shared/apns-client.ts');
  assert.match(apns, /aps: \{\s*alert: \{ title: opts\.title, body: opts\.body \},\s*sound: "default",\s*\},\s*\.\.\.\(opts\.data \|\| \{\}\),/);
  ficheContient(fiche, 'send-push', [
    '`type_evenement`', '`lien`', '`aps`', 'BadDeviceToken', "reason: 'test_account'", '`navigationPathForEvent`',
    'src/lib/pushNative.test.ts', 'APNS_ENVIRONMENT', 'aucun badge',
  ], 'élément');
});

test('CONTRATS : PSC non consommé au lot 3 (décision 8)', () => {
  const fiche = section(CONTRATS, 'PSC (Pro Santé Connect) : non consommé au lot 3');
  ficheContient(fiche, 'PSC', ['`psc-authorize`', '`psc-callback`', '`psc-logout`', '`/auth/psc/callback`', '`.safari`', 'iOS 17.4', 'décision 8', 'PSC-BASCULE-PROD.md'], 'élément');
  assert.ok(read('ios-native/Packages/JoleneCore/Sources/JoleneCore/Links/LinkRouter.swift').includes('`/auth/psc/callback`'), 'témoin Swift : route PSC vers Safari');
});

test('CONTRATS et documents du lot 3 : aucune apostrophe SQL doublée hors bloc de code', () => {
  const doublee = /\p{L}''\p{L}/u;
  for (const chemin of [
    CONTRATS_PATH, 'docs/mobile-swift/LOT3_PLAN.md', 'docs/mobile-swift/DECISIONS_LOT3.md',
    'docs/mobile-swift/RECETTE_DEVICE_LOT3.md', 'docs/mobile-swift/PORTE_LOT3.md',
  ]) {
    const trouve = horsBlocs(read(chemin)).match(doublee);
    assert.equal(trouve, null, `${chemin} : apostrophe SQL doublée hors bloc de code (« ${trouve?.[0]} »)`);
  }
});

// ---------------------------------------------------------------------------------------------
// Documents du lot : plan versionné, décisions, parité, squelettes
// ---------------------------------------------------------------------------------------------

const PLAN_PATH = 'docs/mobile-swift/LOT3_PLAN.md';
const DECISIONS_PATH = 'docs/mobile-swift/DECISIONS_LOT3.md';

test('LOT3_PLAN.md : copie versionnée du blueprint (sections, tranches, 25 décisions du §7)', () => {
  const plan = read(PLAN_PATH);
  assert.ok(plan.startsWith('# Blueprint du lot 3'), 'titre du blueprint attendu en tête');
  assert.ok(plan.includes('`docs/mobile-swift/DECISIONS_LOT3.md`'), 'préambule : renvoi aux décisions absent');
  let from = 0;
  for (const titre of [
    '## Objectif', '## Dépendances au lot 1', '## Corrections vs plan', '## 1. Périmètre', '## 2. Architecture',
    '## 3. Tranches PR', '## 4. Ordre d', '## 5. Risques et parades', '## 6. Ce qui exige Gabrielle', '## 7. Décisions',
  ]) {
    const at = plan.indexOf(`\n${titre}`, from);
    assert.ok(at >= 0, `section « ${titre} » absente ou hors ordre`);
    from = at + 1;
  }
  for (const tranche of ['B3', 'T0', 'T1', 'T1b', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T12', 'T13', 'T14a', 'T14b', 'T15', 'T16', 'T17']) {
    assert.ok(plan.includes(`\n### ${tranche} — `), `tranche ${tranche} absente`);
  }
  const decisions = plan.slice(plan.indexOf('\n## 7. Décisions'));
  assert.ok(!decisions.slice(1).includes('\n## '), 'le §7 doit rester la dernière section');
  let pos = 0;
  for (let i = 1; i <= 25; i++) {
    const at = decisions.slice(pos).search(new RegExp(`\\n${i}\\. `));
    assert.ok(at >= 0, `décision ${i} absente du §7 (ou hors ordre)`);
    pos += at + 1;
  }
  assert.ok(!/\n26\. /.test(decisions), 'décision 26 inattendue');
});

test('DECISIONS_LOT3.md : §7 tranché (25 décisions adoptées), critères amendés, B9, HARD STOP, attente Gabrielle (§6)', () => {
  const doc = read(DECISIONS_PATH);
  assert.ok(doc.includes('`docs/mobile-swift/LOT3_PLAN.md`'), 'renvoi au blueprint absent');
  assert.ok(doc.includes("n'est pas réécrit"), 'le plan PLAN_APP_NATIVE_SWIFT.md ne doit pas être réécrit');
  const decisions = section(doc, 'Décisions');
  let pos = 0;
  for (let i = 1; i <= 25; i++) {
    const rel = decisions.slice(pos).search(new RegExp(`\\n${i}\\. \\*\\*`));
    assert.ok(rel >= 0, `décision ${i} absente (ou hors ordre)`);
    const debut = pos + rel + 1;
    const fin = decisions.slice(debut).search(/\n\d+\. \*\*/);
    const item = decisions.slice(debut, fin < 0 ? undefined : debut + fin);
    assert.ok(item.includes('Adoptée'), `décision ${i} : « Adoptée » attendu`);
    assert.ok(item.includes(`D${i}`), `décision ${i} : renvoi « D${i} » au blueprint attendu`);
    pos = debut;
  }
  assert.ok(!/\n26\. \*\*/.test(decisions), 'décision 26 inattendue');

  const criteres = section(doc, 'Critères de sortie du plan amendés');
  ficheContient(criteres, 'critères', ['l.196', 'six types', '`verifyOTP`', 'token_hash', 'iOS ≥ 17.4', '2.0.0 (25)', 'TestFlight externe', 'PSC'], 'élément');

  const b9 = section(doc, 'B9');
  for (const t of ['B3', 'T7', 'T8', 'T12', 'T13', 'T14a', 'T14b', 'T16']) assert.ok(b9.includes(`**${t}**`), `B9 : ${t} absent`);
  ficheContient(b9, 'B9', ['jamais mergée', '`pol_paie_soig_update`', 'SectionPaiements.tsx'], 'élément');

  const hardStop = section(doc, 'HARD STOP n°4');
  ficheContient(hardStop, 'HARD STOP', ['verbatim', 'fichier:ligne', 'L1222-5', 'IBAN'], 'élément');

  const attente = section(doc, 'En attente de Gabrielle');
  for (let i = 1; i <= 11; i++) assert.ok(attente.includes(`§6.${i}`), `attente : §6.${i} absent`);
  ficheContient(attente, 'attente', ['GDU5AA28M9', 'APNS_ENVIRONMENT', 'jolene-ios', 'token_hash={{ .TokenHash }}&type=signup', 'TestFlight'], 'élément');
});

test('DECISIONS_LOT3.md : décisions déléguées du 8 novembre 2026 (L3-TJ) — TJ1 à TJ8, sources, ligne de délégation, plus rien à relire', () => {
  const doc = read(DECISIONS_PATH);
  const titre = '\n## Décisions déléguées du 8 novembre 2026';
  assert.ok(doc.indexOf('\n## HARD STOP n°4') < doc.indexOf(titre), 'décisions déléguées après la section HARD STOP');
  assert.ok(doc.indexOf(titre) < doc.indexOf('\n## En attente de Gabrielle'), 'décisions déléguées avant « En attente »');
  const deleguees = section(doc, 'Décisions déléguées du 8 novembre 2026');
  ficheContient(deleguees, 'décisions déléguées', [
    '« arrête de me demander et prends les décisions, avance seul »', 'L3-TJ', '`lot3/l3-tj-v2`', 'tutoiement compris',
    'TEXTE', 'JUGÉ', 'choix de conformité Jolene', 'EUR-Lex', 'Légifrance', 'go explicite au merge des PR B9',
  ], 'élément');
  const ligne = 'décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026';
  const sousSections = deleguees.split('\n### ').slice(1);
  assert.deepEqual(sousSections.map(t => t.slice(0, t.indexOf(' — '))), ['TJ1', 'TJ2', 'TJ3', 'TJ4', 'TJ5', 'TJ6', 'TJ7', 'TJ8']);
  for (const sous of sousSections) assert.ok(sous.includes(`- ${ligne}`), `${sous.slice(0, 3)} : ligne de délégation absente`);
  const [tj1, tj2, tj3, tj4, tj5, tj6, tj7, tj8] = sousSections;

  // TJ1 (T7) : consentement p_cgu instruit sur le code natif, le serveur et l'edge ; art. 1119 et RGPD.
  ficheContient(tj1, 'TJ1', ['`p_cgu`', 'l.30161-30163', 'consentement_cgu_le', 'RGPD_CONSENTEMENT_DONNE', 'art. 1119',
    'art. 7, § 2', 'art. 13, § 1', 'InscriptionRapide.tsx', 'l.267', 'l.276', 'src/lib/erreurs.ts', 'l.178'], 'élément');
  assert.ok(SCHEMA.includes("OR p_cgu IS NOT TRUE OR (p_type_compte = 'ETABLISSEMENT' AND p_cgv IS NOT TRUE) THEN"),
    'témoin SQL : fn_demarrer_inscription ne refuse plus p_cgu faux — relire TJ1');
  const register = read('supabase/functions/register-soignant/index.ts');
  assert.ok(register.includes("const consentementInscriptionAtteste = !!parcours?.consentement_cgu_le;")
    && register.includes("action: 'RGPD_CONSENTEMENT_DONNE'"), 'témoin edge : preuve du consentement de register-soignant — relire TJ1');
  // TJ2 (T11) : textes RGPD et natifs, « l'intégralité » instruite, PR web consignée.
  ficheContient(tj2, 'TJ2', ['SectionConfidentialite.tsx', 'l.114', "l'intégralité", 'art. 20, § 1', 'art. 12, § 1',
    'PR web HARD STOP', 'PageConnexion.tsx', 'l.345'], 'élément');
  // Revue fraîche B8 de L3-TJ (majeur 2) : un seul critère pour un texte juridique inexact du web, celui de TJ8 — la
  // description de l'export n'est plus portée (titre et boutons conservés), jamais « maintenue » ni reformulée.
  ficheContient(tj2, 'TJ2', ['**non portée**', 'critère de TJ8', '`compte-export-info`', '`CompteVerbatimTests`',
    '`DemoCompteLot3Tests`'], 'élément');
  assert.ok(!tj2.includes('affichage natif verbatim maintenu'), 'TJ2 : la description inexacte n est plus maintenue en natif (critère de TJ8)');
  ficheContient(tj8, 'TJ8', ['TJ2', 'TJ6', 'ne pas porter un texte n\'est pas le reformuler'], 'élément');
  const confidentialite = read('src/components/profil-soignant/SectionConfidentialite.tsx').split('\n');
  assert.ok(confidentialite[114 - 1].includes("Télécharge l'intégralité de tes données personnelles dans le format de ton choix."),
    'témoin web : l.114 de SectionConfidentialite.tsx a changé (PR web de TJ2 ?) — instruire le nouveau texte et le porter verbatim');
  const exportSwift = read('ios-native/Packages/JoleneCore/Sources/JoleneCore/Compte/ExportRGPD.swift');
  const sectionsCompte = read('ios-native/Jolene/Screens/Compte/CompteSections.swift');
  assert.ok(!exportSwift.includes("l'intégralité") && !exportSwift.includes('SectionConfidentialite.tsx:114'),
    'témoin Swift : la description inexacte de l export (l.114) n est pas portée (TJ2, critère de TJ8)');
  assert.ok(!sectionsCompte.includes('Textes.description') && !sectionsCompte.includes('"compte-export-info"'),
    'témoin Swift : la section export n affiche plus de description (TJ2)');
  // Revue fraîche B8 de L3-TJ (mineur 2) : « Mot de passe oublié ? » est un renvoi sans effet tant que la connexion
  // native n'a pas ce contrôle (L1-T10) ; accepté avec ses motifs, préalable inscrit au §6.10 (TestFlight externe).
  ficheContient(tj2, 'TJ2', ['renvoi sans effet', 'L1-T10', '`login-forgot`', '§6.10', 'TJ7'], 'élément');
  assert.ok(!/pour choisir un nouveau mot de passe\. »\s*\n\s*— exact :/.test(tj2), 'TJ2 : le renvoi vers « Mot de passe oublié ? » n est pas « exact »');
  // TJ3 : double démo de la feuille locale, appliqué dans le code.
  ficheContient(tj3, 'TJ3', ['`PageWebLocale`', '`presentationPageWeb`', 'testLienCGUDuConsentementOuvreLeDoubleDemoSansReseau'], 'élément');
  const ecran = read('ios-native/Jolene/Screens/Inscription/InscriptionRapideScreen.swift');
  assert.ok(ecran.includes('PageWebLocale(url: page.url)') && !ecran.includes('SFSafariViewController(url:'),
    'témoin Swift : la feuille locale de l inscription passe par PageWebLocale');
  // TJ4 : export RGPD — sources primaires, arbitrage, PR backend B9 consignée (aucun fichier sous supabase/ écrit).
  ficheContient(tj4, 'TJ4', ['pg_get_functiondef', 'l.55349', '`evaluations_publiees`', '`pol_notations_select`',
    'notation_publication_jours', 'art. 15, § 4', 'considérant 63', 'art. 12, § 3', 'art. 23, § 1', 'PageConfidentialite.tsx',
    "différer jusqu'à publication", 'B9', 'dump-live-def.sh', 'notations_recues_en_attente_de_publication',
    "interval '1 month'", 'fn_exporter_rgpd_etablissement'], 'élément');
  const exportSoignant = sqlBody('fn_rgpd_exporter_donnees_soignant');
  assert.ok(exportSoignant.includes('FROM notations_missions WHERE note_id = v_uid AND masque = false)'),
    'témoin SQL : le filtre de notations_recues a changé (PR backend de TJ4 mergée ?) — mettre TJ4 et la fiche à jour');
  assert.ok(!sqlBody('fn_exporter_rgpd_etablissement').includes('notations_missions'), 'témoin SQL : export établissement');
  assert.match(SCHEMA, /WHERE \(\("publie_le" IS NOT NULL\) AND \("masque" = false\)\);/, 'témoin SQL : vue evaluations_publiees');
  // Revue fraîche B8 de L3-TJ (mineur 1) : second lecteur d'export à visibilité conditionnelle — `evaluations_recues`
  // lit la table legacy `evaluations` sans filtre `visible`, que la RLS `pol_eval_select` exige pour le soignant noté.
  assert.ok(exportSoignant.includes('FROM evaluations WHERE evalue_id = v_uid)'),
    'témoin SQL : evaluations_recues a changé (PR backend de TJ4 ?) — mettre TJ4 et la fiche à jour');
  assert.ok(SCHEMA.includes('CREATE POLICY "pol_eval_select" ON "public"."evaluations"')
    && SCHEMA.includes('(("evalue_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("visible" = true))'), 'témoin RLS : pol_eval_select');
  ficheContient(tj4, 'TJ4', ['`evaluations_recues`', '`pol_eval_select`', '`visible = true`', 'l.55334', 'l.79230',
    'latent'], 'élément');
  assert.ok(!tj4.includes("aucun autre lecteur d'export à corriger"), 'TJ4 : l audit des lecteurs d export omettait evaluations_recues');
  // Revue fraîche B8 de L3-TJ (mineur 5) : date « au plus tôt » — la publication attend le premier passage du cron.
  assert.ok(sqlBody('fn_publier_notations_echues').includes('AND cree_le + make_interval(days => v_jours::int) < NOW();'),
    'témoin SQL : condition de publication du cron');
  ficheContient(tj4, 'TJ4', ["'publication_automatique_au_plus_tot_le'", '05:30 UTC', 'premier passage', '24 h'], 'élément');
  assert.ok(!tj4.includes("'publication_automatique_le'"), 'TJ4 : la clé dit « au plus tôt »');
  // TJ5 : textes natifs non juridiques (T1b, T4, T5, T9).
  ficheContient(tj5, 'TJ5', ['« Ouvrir les réglages »', '« Le type d\'exercice se modifie sur jolene.app. »',
    '« Votre profil n\'a pas pu être enregistré. Réessayez. »', '« Voir sur jolene.app »', '« environ »',
    '« Montant indisponible »', '« critère rempli »', '« critère non rempli »', '« Ouvre le centre de notifications »'], 'texte');
  // Revue fraîche B8 de L3-TJ (mineur 3) : les commentaires des composants renvoient à TJ5, plus au §6.7.
  for (const composant of ['AmountRow', 'PasswordCriteriaList']) {
    const source = read(`ios-native/Packages/JoleneDesign/Sources/JoleneDesign/Components/${composant}.swift`);
    assert.ok(!source.includes('§6.7') && source.includes('TJ5'), `${composant}.swift : renvoi périmé au §6.7 (textes sous TJ5)`);
  }
  // TJ6 (T14b) : les sept codes sans `error` lus dans le dump, chacun cité ; l.280 instruite.
  const codesSansError = ['NON_AUTHENTIFIE', 'PROFIL_INTROUVABLE', 'IBAN_INVALIDE', 'RIB_COURANT_REQUIS',
    'IDENTITE_VERIFIEE_REQUISE', 'IDENTITE_COURANTE_REQUISE', 'RIB_NON_CONCORDANT'];
  const enregistrerIban = sqlBody('fn_enregistrer_mon_iban');
  const lierIban = sqlBody('fn_lier_iban_verifie_document');
  const iban = [...sqlErrorCodes(enregistrerIban), ...sqlErrorCodes(lierIban)];
  assert.deepEqual(iban.filter(c => !['TITULAIRE_NON_CONCORDANT', 'RIB_VERIFIE_REQUIS'].includes(c)), codesSansError);
  ficheContient(tj6, 'TJ6', codesSansError.map(c => `\`${c}\``), 'error_code');
  ficheContient(tj6, 'TJ6', ['SectionPaiements.tsx', 'l.280', 'fn_consulter_rib_soignant_internal_20260801', 'partages_rib'], 'élément');
  const paiements = read('src/components/profil-soignant/SectionPaiements.tsx').split('\n');
  assert.ok(paiements[280 - 1].includes("Il n'est jamais partagé avec l'établissement."), 'témoin web : l.280 de SectionPaiements.tsx');
  // Revue fraîche B8 de L3-TJ (majeur 1) : `RIB_COURANT_REQUIS` et `RIB_NON_CONCORDANT` reprennent le texte serveur du
  // refus voisin `RIB_VERIFIE_REQUIS`, exact dans les deux cas ; jamais le texte de l.308, qui décrit l'état
  // `iban_renseigne && !iban_verifie` (« l'ancien IBAN… ») : un refus sort avant l'UPDATE, l'IBAN en place reste.
  const texteRibVerifieRequis = 'Téléversez puis faites vérifier le RIB correspondant.';
  assert.ok(sqlErrors(enregistrerIban).includes(texteRibVerifieRequis), 'témoin SQL : texte serveur de RIB_VERIFIE_REQUIS');
  const miseAJour = lierIban.indexOf('SET iban_virement = v_iban');
  assert.ok(miseAJour > 0, 'témoin SQL : UPDATE de l IBAN dans fn_lier_iban_verifie_document');
  for (const code of ['IBAN_INVALIDE', 'RIB_COURANT_REQUIS', 'IDENTITE_VERIFIEE_REQUISE', 'IDENTITE_COURANTE_REQUISE', 'RIB_NON_CONCORDANT']) {
    const refus = lierIban.indexOf(`'error_code', '${code}'`);
    assert.ok(refus > 0 && refus < miseAJour, `témoin SQL : ${code} sort avant l UPDATE de l IBAN`);
  }
  assert.ok(paiements[302 - 1].includes('current?.iban_renseigne && !current.iban_verifie'), 'témoin web : état du texte de l.308');
  assert.ok(paiements[306 - 1].includes('RIB vérifié requis'), 'témoin web : titre l.306');
  assert.ok(paiements[308 - 1].includes("L'ancien IBAN est conservé dans ton historique"), 'témoin web : texte l.308');
  assert.ok(paiements[316 - 1].includes('Téléverser mon RIB'), 'témoin web : action l.316');
  const regle2 = tj6.slice(tj6.indexOf('\n  2. '), tj6.indexOf('\n  3. '));
  assert.ok(regle2.length > 0, 'TJ6 : règle 2 introuvable');
  ficheContient(regle2, 'TJ6 règle 2', ['`RIB_COURANT_REQUIS` et `RIB_NON_CONCORDANT`', `« ${texteRibVerifieRequis} »`,
    '`RIB_VERIFIE_REQUIS`', 'l.32351', '« RIB vérifié requis » (l.306)', '« Téléverser mon RIB » (l.316'], 'élément');
  assert.ok(!regle2.includes('l.308') && !regle2.includes("L'ancien IBAN"), 'TJ6 règle 2 : le texte de l.308 ne sert aucun refus');
  ficheContient(tj6, 'TJ6', ['l.308', '`iban_renseigne && !iban_verifie`', 'l.302', 'l.39526', 'l.39533'], 'élément');
  // TJ7 (T13) : verrou caduc depuis B3, libellés web à leur ligne.
  ficheContient(tj7, 'TJ7', ['#1118', "n'est pas retenu", 'BandeauPaiementDeclare.tsx', 'MOTIF_INVALIDE'], 'élément');
  const bandeau = read('src/components/BandeauPaiementDeclare.tsx').split('\n');
  for (const [texte, l] of [['Motif de contestation :', 51], ['Envoyer la contestation', 62], ['Confirmer la réception', 397], ['Contester', 407]]) {
    assert.ok(bandeau[l - 1].includes(texte), `témoin web : « ${texte} » l.${l} de BandeauPaiementDeclare.tsx`);
  }
  // TJ8 : règle des tranches à venir.
  ficheContient(tj8, 'TJ8', ['T8', 'T12', 'T13', 'T14a', 'T14b', 'fn_types_exercice_autorises', 'escrow-debit-echeance'], 'élément');

  // Plus aucun texte « à relire par Gabrielle » ; §6.7 renvoie aux décisions déléguées ; le signalement de la T0 est tranché.
  assert.ok(!/[àÀ] relire par Gabrielle/.test(doc), 'DECISIONS_LOT3.md : un texte reste « à relire par Gabrielle »');
  const attente = section(doc, 'En attente de Gabrielle');
  const p67 = attente.slice(attente.indexOf('§6.7'), attente.indexOf('§6.8'));
  ficheContient(p67, '§6.7', ['tranchés par délégation', 'Décisions déléguées du 8 novembre', 'TJ6 à TJ8', '§6.2'], 'élément');
  assert.ok(!attente.includes('relecture des sept messages'), '§6.7 : la relecture des messages IBAN est tranchée (TJ6)');
  ficheContient(attente, 'attente', ['TJ4', 'go B9'], 'élément');
  // Verrou « un gap connu reste verrouillé » (revue fraîche B8 de L3-TJ, mineur 2) : tant que la connexion native n'a pas
  // « Mot de passe oublié ? » (`login-forgot`, L1-T10), le préalable figure au §6.10 (TestFlight externe).
  const connexion = read('ios-native/Jolene/Screens/LoginScreen.swift');
  if (!connexion.includes('"login-forgot"')) {
    const p610 = attente.slice(attente.indexOf('§6.10'), attente.indexOf('§6.11'));
    ficheContient(p610, '§6.10', ['Préalable', '« Mot de passe oublié ? »', '`login-forgot`', 'L1-T10', 'TJ2',
      'un gap connu reste verrouillé'], 'élément');
  }
});

test('ios-swift-ci.yml : éclats UI du lot 3 — chaque classe dans un seul éclat, sautée par le socle, attendue par le résumé', () => {
  // Revue fraîche B8 de L3-TJ (mineur 4) : `DemoInscriptionTests` sort de « lot3-compte » (19,1 min sur ipad-landscape
  // au run 42549855710, avant les deux XCUITest de L3-TJ ; seuil de 20 min, décision 22 de DECISIONS_LOT2).
  const wf = read('.github/workflows/ios-swift-ci.yml');
  const eclats = new Map([
    ['lot3-compte', ['DemoLiensLot3Tests', 'DemoCompteLot3Tests']],
    ['lot3-inscription', ['DemoInscriptionTests']],
    ['lot3-push', ['DemoPushTests']],
    ['lot3-notifications', ['DemoNotificationsTests', 'DemoPreferencesTests', 'DemoProfilTests']],
  ]);
  const etapes = wf.split('\n      - name: ').slice(1);
  const etape = nom => etapes.find(e => e.startsWith(`test-without-building — éclat ${nom} `));
  const socle = etape('socle');
  assert.ok(socle, 'éclat socle absent');
  const toutes = [...eclats.values()].flat();
  for (const classe of toutes) {
    assert.ok(socle.includes(`-skip-testing:JoleneUITests/${classe} \\`), `éclat socle : ${classe} non sauté`);
  }
  for (const [nom, classes] of eclats) {
    const bloc = etape(nom);
    assert.ok(bloc, `éclat ${nom} absent`);
    assert.ok(bloc.includes('timeout-minutes: 30'), `éclat ${nom} : délai propre de 30 min`);
    const seules = [...bloc.matchAll(/-only-testing:JoleneUITests\/(\w+) \\/g)].map(m => m[1]);
    assert.deepEqual(seules, classes, `éclat ${nom} : classes -only-testing`);
    assert.ok(bloc.includes(`resultat="$RUNNER_TEMP/ui-$JOLENE_UI_FORMAT-${nom}.xcresult"`), `éclat ${nom} : xcresult`);
    assert.ok(bloc.includes(`test-without-building-${nom}.log`), `éclat ${nom} : journal`);
    assert.ok(wf.includes(`{ nom: "${nom}", code: process.env.CODE_${nom.replace(/-/g, '_').toUpperCase()}, classes: ${JSON.stringify(classes).replace(/,/g, ', ')} }`),
      `résumé : éclat ${nom} et ses classes attendus`);
    assert.ok(wf.includes(`\${{ runner.temp }}/ui-\${{ matrix.format }}-${nom}.xcresult`), `artefact : xcresult de ${nom} conservé`);
  }
  const boucle = wf.match(/for eclat in ([a-z0-9 -]+); do/);
  assert.ok(boucle, 'boucle des xcresult absente');
  assert.deepEqual(boucle[1].split(' '), ['socle', ...eclats.keys()], 'boucle des xcresult : tous les éclats');
  for (const classe of toutes) {
    assert.equal(wf.split(`-only-testing:JoleneUITests/${classe} \\`).length - 1, 1, `${classe} : un seul éclat`);
  }
  // Plafond du job au-dessus de la somme des éclats (5 × 30 min) et du build.
  const plafond = Number(wf.match(/\n {2}ui:\n[\s\S]*?\n {4}timeout-minutes: (\d+)/)[1]);
  assert.ok(plafond >= 30 * (eclats.size + 1) + 20, `plafond du job UI trop bas : ${plafond} min`);
});

test('PARITE_SOIGNANT.md : lignes du lot 3 (profil, revenus, notifications, Stripe, préférences, alias)', () => {
  const parite = read('docs/mobile-swift/PARITE_SOIGNANT.md');
  const ligne = route => parite.split('\n').find(l => l.startsWith(`| \`${route}\``));
  for (const route of ['/soignant/profil', '/soignant/mes-gains', '/soignant/notifications', '/soignant/stripe-connect', '/soignant/parametres/notifications']) {
    const l = ligne(route);
    assert.ok(l, `ligne ${route} absente`);
    assert.ok(/lot 3 T\d/.test(l), `${route} : tranche du lot 3 non citée`);
  }
  assert.ok(ligne('/soignant/reputation').includes('alias de /soignant/profil') && /\| 3 /.test(ligne('/soignant/reputation')));
  for (const alias of ['/soignant/mes-factures-honoraires', '/soignant/mes-avances', '/soignant/bulletins-paie']) {
    assert.ok(ligne(alias).includes("renvoi web assumé jusqu'au lot 4"), `${alias} : renvoi web assumé jusqu'au lot 4 attendu`);
  }
  for (const needle of [
    '`/soignant/mes-gains` › Paiements à confirmer', '`/soignant/mes-gains` › IBAN', '`/soignant/mes-gains` › Missions terminées',
    '`/soignant/mon-compte` › Mot de passe', '`/soignant/mon-compte` › Thème', '`/soignant/mon-compte` › Export RGPD',
    '`/soignant/profil` › Type d\'exercice', 'L1222-5',
  ]) assert.ok(parite.includes(needle), `PARITE : « ${needle} » absent`);
});

test('RECETTE_DEVICE_LOT3.md et PORTE_LOT3.md : squelettes créés dès T0', () => {
  const recette = read('docs/mobile-swift/RECETTE_DEVICE_LOT3.md');
  ficheContient(recette, 'RECETTE_DEVICE_LOT3', [
    'iOS ≥ 17.4', 'token_hash={{ .TokenHash }}&type=signup', 'tokens_push.actif', 'APNS_ENVIRONMENT', 'HEIC', 'Sentry',
    'Mail iOS', 'D5-R', 'Stripe TEST', 'thème sombre',
  ], 'élément');
  const types = recette.split('\n').filter(l => /^\| `[A-Z_]+` \|/.test(l));
  assert.ok(types.length >= 6, `recette push : au moins six types attendus, lus ${types.length}`);
  const porte = read('docs/mobile-swift/PORTE_LOT3.md');
  ficheContient(porte, 'PORTE_LOT3', ['go avec contrainte consignée', 'non mesurée', 'Signature finale', 'B3', 'D5-R', 'iOS ≥ 17.4', 'jolene-ios'], 'élément');
});

test('validate-pr.yml : l étape « Garde de livraison mobile » exécute aussi cette garde', () => {
  const wf = read('.github/workflows/validate-pr.yml');
  const etape = wf.indexOf('\n      - name: Garde de livraison mobile\n');
  assert.ok(etape >= 0, 'étape « Garde de livraison mobile » absente');
  const suite = wf.slice(etape + 1);
  const fin = suite.search(/\n {6}- name: /);
  const bloc = suite.slice(0, fin < 0 ? undefined : fin);
  const run = bloc.split('\n').find(l => /^\s+run: /.test(l));
  assert.ok(run && run.includes('node --test') && run.includes('tests/node/check-rpc-contracts-lot3.node.mjs'), `run: n exécute pas la garde du lot 3 : ${run}`);
  assert.ok(run.includes('tests/node/check-rpc-contracts.node.mjs'), 'la garde du lot 1 doit rester exécutée');
});

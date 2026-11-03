import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  CONTRACTS_PATH,
  EXCEPTIONS_ETABLISSEMENT,
  RPC_PARTAGEES_ETABLISSEMENT,
  RPC_SUIVIES,
  RPC_SUIVIES_ETABLISSEMENT,
  SOURCES,
  buildContracts,
  corpsFonction,
  declencheur,
  diffContracts,
  exceptionsDuCorps,
  extraireExceptions,
  matricePermissionsEtablissement,
} from '../../scripts/mobile/check-rpc-contracts.mjs';
import { lecteurWeb, lireTextesSwift, TEXTES_SWIFT } from '../../scripts/mobile/check-textes-juridiques-ios.mjs';
import { buildDemoEtabPermissions, FIXTURES_DIR } from '../../scripts/mobile/export-demo-fixtures.mjs';

// Garde du lot 5, tranche T0 (docs/mobile-swift/LOT5_PLAN.md §3 T0) : les RPC de l'espace
// établissement sont sous contrat avant toute gateway Swift, leurs exceptions interceptées sont des
// listes blanches extraites du dump (§2.5, D12), chaque RPC a sa fiche dans
// CONTRATS_RPC_ETABLISSEMENT.md, la matrice de parité couvre toutes les routes établissement du web et
// les textes du lot 5 passent par Legal/TextesWeb.swift (TL du lot 2, D30). Aucun réseau, aucun
// secret : le test ne lit que des fichiers du dépôt.

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = relative => readFileSync(join(root, relative), 'utf8');
const schema = read(SOURCES.schema);
const contrats = JSON.parse(readFileSync(CONTRACTS_PATH, 'utf8'));
const contratParNom = new Map(contrats.rpcs.map(r => [r.name, r]));
const suivieParNom = new Map(RPC_SUIVIES.map(r => [r.name, r]));

// Blueprint §3 T0 : 13 RPC propres à l'établissement + fn_obtenir_conversation (si le lot 4 ne l'a pas
// suivie : l'ajout est dédoublonné, une RPC déjà suivie par un lot antérieur garde son entrée).
const LOT5 = [
  'fn_mes_permissions_etab',
  'fn_mon_etablissement_complet',
  'fn_stats_dashboard_etablissement',
  'fn_soignant_pour_etablissement',
  'fn_lire_candidatures_mission_habilitee',
  'fn_traiter_candidature_planning_v1',
  'fn_contrat_signe_pour_pointage',
  'fn_valider_presence',
  'fn_valider_presences_lot',
  'fn_contester_presence',
  'fn_creer_notation_mission',
  'fn_declarer_fin_retroactive',
  'fn_creer_mission_multi_jours_v4',
  'fn_obtenir_conversation',
];
// Chaque tranche qui câble une gateway passe sa RPC en `consommee` et l'ajoute ici (modèle LOT1_CONSOMMEES).
const LOT5_CONSOMMEES = ['fn_mes_permissions_etab', 'fn_mon_etablissement_complet']; // T1 : SupabaseEtabSessionGateway
// Déjà suivies par un lot soignant, consommées aussi par l'établissement (annotation, jamais doublon).
const PARTAGEES = [
  'fn_get_my_role', 'fn_audit_connexion', 'fn_ecrire_audit_safe', 'fn_param_bool',
  'fn_etat_pointage_mission', 'fn_envoyer_otp_signature', 'fn_signer_contrat_otp',
];
// Classement manuel (absentes du manifeste SECURITY DEFINER, comme la décision 6 du lot 1).
const HORS_MANIFESTE = [
  'fn_lire_candidatures_mission_habilitee', 'fn_traiter_candidature_planning_v1',
  'fn_contrat_signe_pour_pointage', 'fn_creer_mission_multi_jours_v4',
];
const HORS_TYPES = ['fn_traiter_candidature_planning_v1', 'fn_contrat_signe_pour_pointage'];

const RBAC_POINTAGE = {
  sqlstate: '42501', message: 'Permission etablissement pointage requise',
  fonction: 'fn_enforce_etablissement_rbac_trigger', declencheur: 'trg_p0_rbac_presences',
};
const fin = (sqlstate, message) => ({
  sqlstate, message,
  fonction: 'dec_bloquer_validation_presence_avant_fin_planning',
  declencheur: 'trg_bloquer_validation_presence_avant_fin_planning',
});
const VALIDATION = [
  RBAC_POINTAGE,
  fin('23503', 'Mission introuvable pour cette présence.'),
  fin('P0001', 'La présence ne peut être validée avant la fin du dernier créneau planifié.'),
  fin('P0001', 'Le planning détaillé doit être terminé avant validation de la présence.'),
  fin('P0001', 'Un pointage est encore ouvert pour cette mission.'),
  fin('P0001', 'Aucun pointage terminé ne permet de valider cette présence.'),
];
const paiement = message => ({
  sqlstate: 'P0001', message, fonction: 'fn_trg_gate_assignation_paiement', declencheur: 'trg_gate_assignation_paiement',
});
// T1 (revue B8 de T0, mineur 3) : triggers RBAC des tables écrites, `%` instancié par l'argument du trigger.
const rbac = (permission, declencheur) => ({
  sqlstate: '42501', message: `Permission etablissement ${permission} requise`,
  fonction: 'fn_enforce_etablissement_rbac_trigger', declencheur,
});
const ATTENDUES = {
  fn_lire_candidatures_mission_habilitee: [
    { sqlstate: '42501', message: 'Mission indisponible ou accès refusé', fonction: 'fn_lire_candidatures_mission_habilitee' },
  ],
  fn_contrat_signe_pour_pointage: [
    { sqlstate: '42501', message: 'Lecture du pointage non autorisée.', fonction: 'fn_contrat_signe_pour_pointage' },
  ],
  fn_valider_presence: VALIDATION,
  fn_valider_presences_lot: VALIDATION,
  fn_contester_presence: [RBAC_POINTAGE],
  fn_traiter_candidature_planning_v1: [
    { sqlstate: 'P0001', message: "Notification d'acceptation impossible : %", fonction: 'fn_traiter_candidature' },
    paiement("Cette mission ne peut pas être attribuée : l'établissement doit d'abord configurer un mode de paiement (Paramètres → Facturation)."),
    paiement("Cette mission ne peut pas être attribuée : le mandat SEPA de l'établissement n'est pas encore posé (IBAN à ajouter dans Paramètres → Facturation)."),
    rbac('missions', 'trg_p0_rbac_missions'),
    rbac('contrats', 'trg_p0_rbac_contrats_mission'),
    rbac('candidatures', 'trg_p0_rbac_candidatures'),
  ],
  fn_declarer_fin_retroactive: [
    { sqlstate: 'P0002', message: 'Mission % introuvable ou dans un statut incompatible.', fonction: 'fn_declarer_fin_retroactive' },
    { sqlstate: '42501', message: "Vous n'êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission.", fonction: 'fn_declarer_fin_retroactive' },
    { sqlstate: 'P0002', message: 'Aucun créneau effectif ouvert à fermer pour cette mission.', fonction: 'fn_declarer_fin_retroactive' },
    { sqlstate: '23514', message: "L'heure de fin (%) doit être postérieure au début du créneau (%).", fonction: 'fn_declarer_fin_retroactive' },
    rbac('pointage', 'trg_p0_rbac_presences'),
    rbac('missions', 'trg_p0_rbac_missions'),
  ],
  fn_creer_mission_multi_jours_v4: [
    { sqlstate: '28000', message: 'Non authentifié', fonction: 'fn_creer_mission_multi_jours_v4' },
  ],
  fn_creer_notation_mission: [
    { sqlstate: 'P0001', message: 'La notation n’a pas pu être enregistrée. Veuillez réessayer.', fonction: 'fn_creer_notation_mission' },
  ],
  fn_mes_permissions_etab: [],
  fn_mon_etablissement_complet: [],
  fn_stats_dashboard_etablissement: [],
  fn_soignant_pour_etablissement: [],
};

/** Texte Markdown aplati : les retours à la ligne d'un paragraphe sont des espaces au rendu. */
const plat = texte => texte.replace(/\s+/g, ' ');

/** Texte d'une section `## <titre>` d'un document Markdown, jusqu'à la section suivante. */
function section(doc, heading) {
  const start = doc.indexOf(`\n## ${heading}`);
  assert.ok(start >= 0, `section « ${heading} » introuvable`);
  const next = doc.indexOf('\n## ', start + 1);
  return doc.slice(start, next < 0 ? undefined : next);
}

// ---------------------------------------------------------------------------------------------
// RPC_SUIVIES
// ---------------------------------------------------------------------------------------------

test('lot 5 : les 14 RPC établissement sont suivies, a_venir lot 5 (consommee une fois câblées) sauf si un lot antérieur les suit déjà', () => {
  assert.deepEqual(RPC_SUIVIES_ETABLISSEMENT.map(r => r.name), LOT5);
  for (const r of RPC_SUIVIES_ETABLISSEMENT) {
    const statut = LOT5_CONSOMMEES.includes(r.name) ? 'consommee' : 'a_venir';
    assert.deepEqual(r, { name: r.name, statut, lot: 5 });
  }
  for (const name of LOT5_CONSOMMEES) assert.equal(contratParNom.get(name)?.statut, 'consommee', `${name} : JSON non régénéré`);
  assert.equal(new Set(RPC_SUIVIES.map(r => r.name)).size, RPC_SUIVIES.length, 'doublon dans RPC_SUIVIES');
  for (const name of LOT5) {
    const suivie = suivieParNom.get(name);
    assert.ok(suivie, `${name} absente de RPC_SUIVIES`);
    assert.ok(suivie.lot <= 5, `${name} : lot ${suivie.lot}`);
  }
  // Une entrée lot 5 n'existe que pour une RPC qu'aucun lot antérieur ne suit.
  for (const r of RPC_SUIVIES.filter(x => x.lot === 5)) assert.ok(LOT5.includes(r.name), `${r.name} : lot 5 hors liste`);
});

test('lot 5 : les RPC partagées sont suivies par un lot soignant et annotées « aussi établissement »', () => {
  assert.deepEqual([...RPC_PARTAGEES_ETABLISSEMENT], PARTAGEES);
  for (const name of PARTAGEES) {
    assert.ok(suivieParNom.get(name)?.lot < 5, `${name} doit être suivie par un lot soignant`);
    assert.equal(contratParNom.get(name)?.aussi_etablissement, true, `${name} : aussi_etablissement absent du JSON`);
  }
  // Une RPC du lot 5 reprise par un lot antérieur (dédoublonnage) devient partagée.
  for (const name of LOT5) {
    const attendu = suivieParNom.get(name).lot < 5 ? true : undefined;
    assert.equal(contratParNom.get(name)?.aussi_etablissement, attendu, `${name} : aussi_etablissement`);
  }
  for (const r of contrats.rpcs) {
    if (r.aussi_etablissement) assert.ok(PARTAGEES.includes(r.name) || LOT5.includes(r.name), `${r.name} annotée à tort`);
  }
});

test('rpc-contracts.json : les RPC établissement sont sous contrat sans dérive, GRANT authenticated', () => {
  const actual = buildContracts({
    typesSource: read(SOURCES.types),
    schemaSource: schema,
    manifest: JSON.parse(read(SOURCES.manifest)),
  });
  assert.deepEqual(diffContracts(contrats, actual), []);
  for (const name of LOT5) {
    const c = contratParNom.get(name);
    assert.ok(c, `${name} absente du JSON versionné`);
    assert.ok(c.sql.length === 1, `${name} : une seule définition SQL attendue`);
    assert.ok(c.grants.includes('authenticated'), `${name} : pas de GRANT authenticated`);
    assert.ok(!c.grants.includes('anon'), `${name} : ouverte à anon`);
  }
  for (const name of HORS_MANIFESTE) assert.equal(contratParNom.get(name).manifeste, null, `${name} : manifeste`);
  for (const name of HORS_TYPES) assert.equal(contratParNom.get(name).types, null, `${name} : types.ts`);
});

test('diffContracts : une exception serveur modifiée ou l annotation établissement retirée est une dérive', () => {
  const entree = { name: 'fn_x', statut: 'a_venir', lot: 5, types: null, sql: [], grants: [], manifeste: null,
    exceptions: [{ sqlstate: '42501', message: 'Accès refusé', fonction: 'fn_x' }], aussi_etablissement: true };
  const base = { schema_version: 1, rpcs: [entree] };
  const message = { schema_version: 1, rpcs: [{ ...entree, exceptions: [{ ...entree.exceptions[0], message: 'Accès refusé.' }] }] };
  assert.match(diffContracts(base, message).join('\n'), /fn_x\.exceptions/);
  const sansAnnotation = { schema_version: 1, rpcs: [{ ...entree, aussi_etablissement: undefined }] };
  assert.match(diffContracts(base, sansAnnotation).join('\n'), /fn_x\.aussi_etablissement/);
  assert.deepEqual(diffContracts(base, base), []);
});

// ---------------------------------------------------------------------------------------------
// Listes blanches des exceptions (§2.5, D12)
// ---------------------------------------------------------------------------------------------

test('exceptions : listes blanches extraites du dump, corps, fonctions appelées et triggers nommés', () => {
  for (const [name, attendues] of Object.entries(ATTENDUES)) {
    assert.deepEqual(contratParNom.get(name)?.exceptions, attendues, `${name} : exceptions du JSON`);
    assert.deepEqual(extraireExceptions(schema, name, EXCEPTIONS_ETABLISSEMENT[name] ?? {}), attendues, `${name} : extraction`);
  }
  for (const name of LOT5) assert.ok(Array.isArray(contratParNom.get(name)?.exceptions), `${name} : exceptions absentes du JSON`);
  // Les RPC des autres lots ne reçoivent pas de liste (contrat inchangé).
  for (const r of contrats.rpcs) if (!LOT5.includes(r.name)) assert.equal(r.exceptions, undefined, `${r.name} : exceptions inattendues`);
  // Configuration nommée par RPC : triggers et fonctions appelées existent dans le dump.
  for (const config of Object.values(EXCEPTIONS_ETABLISSEMENT)) {
    for (const f of config.fonctions ?? []) assert.ok(corpsFonction(schema, f).corps.length > 0, f);
    for (const t of config.declencheurs ?? []) assert.ok(declencheur(schema, t).fonction, t);
  }
});

test('exceptions : le trigger RBAC est lu avec son argument et la table visée', () => {
  assert.deepEqual(declencheur(schema, 'trg_p0_rbac_presences'), {
    table: 'presences', fonction: 'fn_enforce_etablissement_rbac_trigger', arguments: ['pointage'],
  });
  assert.deepEqual(declencheur(schema, 'trg_gate_assignation_paiement'), {
    table: 'missions', fonction: 'fn_trg_gate_assignation_paiement', arguments: [],
  });
  assert.throws(() => declencheur(schema, 'trg_inexistant_lot5'), /trg_inexistant_lot5/);
  assert.throws(() => corpsFonction(schema, 'fn_inexistante_lot5'), /fn_inexistante_lot5/);
});

test('exceptions : formes RAISE (format, USING MESSAGE, nom de condition, défaut P0001, TG_ARGV, %)', () => {
  const corps = `
DECLARE
  v_perm text := TG_ARGV[0];
BEGIN
  RAISE NOTICE 'trace %', v_perm;
  RAISE EXCEPTION 'Permission % requise', v_perm USING ERRCODE = '42501';
  RAISE EXCEPTION 'Mission % absente', p_id USING ERRCODE = 'no_data_found';
  RAISE EXCEPTION USING
    ERRCODE = 'P0001',
    MESSAGE = 'L''heure ; choisie est invalide.';
  -- RAISE EXCEPTION 'commentaire ignoré';
  RAISE EXCEPTION 'Sans code : défaut P0001.';
  RAISE EXCEPTION 'Contrôle (%) : %', TG_ARGV[1], v_x USING ERRCODE = 'check_violation', HINT = 'h';
  RAISE;
END;`;
  assert.deepEqual(exceptionsDuCorps(corps, { fonction: 'f', declencheur: 't', argumentsDeclencheur: ['pointage', 'x'] }), [
    { sqlstate: '42501', message: 'Permission pointage requise', fonction: 'f', declencheur: 't' },
    { sqlstate: 'P0002', message: 'Mission % absente', fonction: 'f', declencheur: 't' },
    { sqlstate: 'P0001', message: "L'heure ; choisie est invalide.", fonction: 'f', declencheur: 't' },
    { sqlstate: 'P0001', message: 'Sans code : défaut P0001.', fonction: 'f', declencheur: 't' },
    { sqlstate: '23514', message: 'Contrôle (x) : %', fonction: 'f', declencheur: 't' },
  ]);
  // Sans trigger, `%` reste un joker.
  assert.deepEqual(exceptionsDuCorps("RAISE EXCEPTION 'P %', TG_ARGV[0];", { fonction: 'f' }),
    [{ sqlstate: 'P0001', message: 'P %', fonction: 'f' }]);
  // Fail-closed : message entièrement dynamique, condition inconnue, chaîne E'' ou %% non pris en charge.
  assert.throws(() => exceptionsDuCorps("RAISE EXCEPTION '%', v_msg;", { fonction: 'f' }), /dynamique/);
  assert.throws(() => exceptionsDuCorps("RAISE EXCEPTION 'x' USING ERRCODE = 'condition_inconnue';", { fonction: 'f' }), /condition_inconnue/);
  assert.throws(() => exceptionsDuCorps("RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = v_message;", { fonction: 'f' }), /dynamique/);
  assert.throws(() => exceptionsDuCorps("RAISE EXCEPTION E'x\\n';", { fonction: 'f' }), /E''/);
  assert.throws(() => exceptionsDuCorps("RAISE EXCEPTION '100 %% sûr';", { fonction: 'f' }), /%%/);
  assert.throws(() => exceptionsDuCorps('RAISE EXCEPTION no_data_found;', { fonction: 'f' }), /forme/);
});

// ---------------------------------------------------------------------------------------------
// Permissions établissement (§2.7) : 11 clés, 5 rôles, matrice lue dans le CASE SQL
// ---------------------------------------------------------------------------------------------

const CLES = ['gerer_equipe', 'supprimer_compte', 'profil_etab', 'paiement', 'lecture_paiement', 'missions',
  'candidatures', 'contrats', 'pointage', 'rh', 'lecture'];
const ROLES = ['PROPRIETAIRE', 'ADMIN_GROUPE', 'RH', 'POINTAGE_ONLY', 'LECTURE_SEULE'];

test('permissions : 11 clés identiques dans fn_mes_permissions_etab et useEtabPermissions.ts, 5 rôles du CHECK', () => {
  const matrice = matricePermissionsEtablissement(schema);
  assert.deepEqual(matrice.cles, CLES);
  assert.deepEqual(Object.keys(matrice.roles), ROLES);
  const hook = read('src/hooks/useEtabPermissions.ts');
  const vides = hook.slice(hook.indexOf('const PERMISSIONS_VIDES'), hook.indexOf('};', hook.indexOf('const PERMISSIONS_VIDES')));
  assert.deepEqual([...vides.matchAll(/^\s+(\w+): false,$/gm)].map(m => m[1]), CLES);
  assert.ok(hook.includes("export type RoleEtab = 'PROPRIETAIRE' | 'ADMIN_GROUPE' | 'RH' | 'POINTAGE_ONLY' | 'LECTURE_SEULE';"));
  // Rôles du §2.7 (aucune de ces correspondances n'est écrite en Swift).
  const vraies = role => CLES.filter(c => matrice.roles[role][c]);
  assert.deepEqual(vraies('POINTAGE_ONLY'), ['pointage', 'lecture']);
  assert.deepEqual(vraies('LECTURE_SEULE'), ['lecture_paiement', 'lecture']);
  assert.deepEqual(vraies('RH'), ['missions', 'candidatures', 'contrats', 'pointage', 'rh', 'lecture']);
  assert.deepEqual(vraies('PROPRIETAIRE'), CLES);
});

test('demo-etab-permissions.json : permissions démo générées depuis le CASE de fn_a_permission_etablissement (T1)', () => {
  const matrice = matricePermissionsEtablissement(schema);
  const genere = buildDemoEtabPermissions(schema);
  assert.deepEqual(genere.cles, matrice.cles);
  assert.deepEqual(genere.roles, matrice.roles);
  const versionne = JSON.parse(readFileSync(join(FIXTURES_DIR, 'demo-etab-permissions.json'), 'utf8'));
  assert.deepEqual(versionne, genere, 'fixture démo à régénérer (export-demo-fixtures.mjs)');
});

test('CONTRATS_RPC_ETABLISSEMENT.md : la matrice rôle × permission égale le CASE de fn_a_permission_etablissement', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md');
  const matrice = matricePermissionsEtablissement(schema);
  const bloc = section(doc, 'Permissions établissement');
  const entete = bloc.split('\n').find(l => l.startsWith('| Rôle |'));
  assert.ok(entete, 'en-tête de la matrice absent');
  assert.deepEqual(entete.split('|').slice(2, -1).map(c => c.trim().replaceAll('`', '')), CLES);
  for (const role of ROLES) {
    const ligne = bloc.split('\n').find(l => l.startsWith(`| \`${role}\` |`));
    assert.ok(ligne, `ligne ${role} absente`);
    const cellules = ligne.split('|').slice(2, -1).map(c => c.trim());
    assert.deepEqual(cellules, CLES.map(c => (matrice.roles[role][c] ? 'oui' : 'non')), `ligne ${role}`);
  }
});

// ---------------------------------------------------------------------------------------------
// CONTRATS_RPC_ETABLISSEMENT.md
// ---------------------------------------------------------------------------------------------

test('CONTRATS_RPC_ETABLISSEMENT.md : une fiche et une ligne de synthèse par RPC, exceptions verbatim', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md');
  const synthese = section(doc, 'Synthèse');
  for (const name of [...LOT5, ...PARTAGEES]) {
    assert.ok(doc.includes(`\n## ${name}\n`), `fiche manquante pour ${name}`);
    assert.ok(synthese.includes(`| \`${name}\` |`), `ligne de synthèse manquante pour ${name}`);
  }
  for (const name of LOT5) {
    const fiche = plat(section(doc, `${name}\n`));
    const sql = contratParNom.get(name).sql[0];
    assert.ok(fiche.includes(`"public"."${name}"(`), `${name} : signature SQL absente`);
    assert.ok(fiche.includes(sql.returns), `${name} : type de retour ${sql.returns} absent`);
    for (const forme of ['**Forme de réponse**', '**Exceptions**', '**Relecture**', "**Classe d'authentification (manifeste)**", '**GRANT**']) {
      assert.ok(fiche.includes(forme), `${name} : rubrique ${forme} absente`);
    }
    for (const e of contratParNom.get(name).exceptions) {
      assert.ok(fiche.includes(e.message), `${name} : exception « ${e.message} » absente de la fiche`);
      assert.ok(fiche.includes(`\`${e.sqlstate}\``), `${name} : SQLSTATE ${e.sqlstate} absent`);
    }
  }
  for (const name of HORS_MANIFESTE) {
    const classe = section(doc, `${name}\n`).split('\n').find(l => l.startsWith("- **Classe d'authentification (manifeste)**"));
    assert.ok(classe?.includes('`RPC_UTILISATEUR_AUTH_INTERNE`') && classe.includes('classement manuel'), `${name} : classement manuel`);
  }
  for (const name of PARTAGEES) {
    const fiche = section(doc, `${name}\n`);
    assert.ok(fiche.includes('CONTRATS_RPC_SOIGNANT.md'), `${name} : renvoi à la fiche soignant absent`);
  }
});

test('CONTRATS_RPC_ETABLISSEMENT.md : 18 clés du tableau de bord, montants et identifiants Stripe jamais décodés', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md');
  const corps = corpsFonction(schema, 'fn_stats_dashboard_etablissement').corps;
  const objet = corps.slice(corps.indexOf('SELECT jsonb_build_object('));
  const cles = [...objet.matchAll(/^\s{8}'([a-z_]+)',/gm)].map(m => m[1]);
  assert.equal(cles.length, 18);
  const fiche = section(doc, 'fn_stats_dashboard_etablissement\n');
  for (const cle of cles) assert.ok(fiche.includes(`\`${cle}\``), `clé ${cle} absente de la fiche`);
  const profil = plat(section(doc, 'fn_mon_etablissement_complet\n'));
  const exclus = profil.slice(profil.indexOf('**Jamais décodé**'));
  assert.ok(exclus.length < profil.length, 'rubrique « Jamais décodé » absente');
  for (const champ of ['stripe_customer_id', 'stripe_account_id', 'iban_last4', 'rib_s3_key', 'siret']) {
    assert.ok(exclus.includes(`\`${champ}\``), `${champ} : exclusion non consignée`);
  }
});

test('CONTRATS_RPC_ETABLISSEMENT.md : RPC jamais appelées par l espace établissement, écho exact des créneaux (D26)', () => {
  const doc = read('docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md');
  const jamais = section(doc, 'Jamais appelées par l’espace établissement natif');
  for (const nom of ['fn_mode_exercice', 'fn_generer_qr_mission', 'fn_generer_code_secours_mission',
    'fn_annuler_mission_etablissement', 'fn_ouvrir_litige_rate_limited', 'notations_missions']) {
    assert.ok(jamais.includes(`\`${nom}\``), `${nom} absente de la fiche « jamais »`);
  }
  const traiter = plat(section(doc, 'fn_traiter_candidature_planning_v1\n'));
  assert.ok(traiter.includes('D26') && traiter.includes('pourAction'), 'écart D26 avec CreneauxConfirmes.pourAction non consigné');
  for (const code of ['CADRE_ETUDIANT_A_CONFIRMER', 'CADRE_ETUDIANT_PROFESSION_INVALIDE', 'CADRE_ETUDIANT_SALARIAT_REQUIS',
    'CADRE_ETUDIANT_STRUCTURE_INELIGIBLE', 'PLANNING_A_RECONFIRMER', 'PLANNING_MODIFIE_RECONFIRMER']) {
    assert.ok(traiter.includes(code), `${code} absent de la fiche`);
    assert.ok(corpsFonction(schema, 'fn_traiter_candidature_planning_v1').corps.includes(code)
      || corpsFonction(schema, 'fn_traiter_candidature_planning_v1_internal_20260810').corps.includes(code), `${code} absent du dump`);
  }
  const fin = plat(section(doc, 'fn_declarer_fin_retroactive\n'));
  assert.ok(fin.includes('sans clé `success`') && fin.includes('`nouveau_code`'), 'succès sans `success` et nouveau_code non consignés');
});

test('CONTRATS_RPC_ETABLISSEMENT.md : chaque code de fn_blocage_publication_etab avec son message (correction 8)', () => {
  const fiche = plat(section(read('docs/mobile-swift/CONTRATS_RPC_ETABLISSEMENT.md'), 'fn_creer_mission_multi_jours_v4\n'));
  const corps = corpsFonction(schema, 'fn_blocage_publication_etab').corps;
  const codes = [...corps.matchAll(/'error', '([A-Z_]+)',\s*'message', '((?:[^']|'')*)'/g)]
    .map(m => ({ code: m[1], message: m[2].replaceAll("''", "'") }));
  assert.equal(codes.length, 5, 'codes de blocage lus dans le dump');
  for (const { code, message } of codes) {
    assert.ok(fiche.includes(`\`${code}\` (« ${message} »)`), `${code} : code ou message absent de la fiche`);
  }
  assert.ok(fiche.includes('`message` prioritaire') && fiche.includes('CREATION_MISSION_INDISPONIBLE'));
});

test('CONTRATS_RPC_SOIGNANT.md : fn_generer_qr_mission non exposée par le web (correction 1 du lot 5)', () => {
  const fiche = section(read('docs/mobile-swift/CONTRATS_RPC_SOIGNANT.md'), 'fn_generer_qr_mission\n');
  assert.ok(!fiche.includes('Génération du QR côté établissement (lot 5)'), 'usage « lot 5 » encore annoncé');
  assert.ok(fiche.includes('non exposée par le web') && fiche.includes('QRPointageEtab.tsx'), 'correction 1 non consignée');
  assert.ok(read('src/components/etablissement/QRPointageEtab.tsx').includes("supabase.rpc('fn_generer_qr_mission'"));
  assert.ok(read('src/components/pointage/AffichageCodeRotatifEtab.tsx').includes('<QRCodeSVG value={code}'));
});

// ---------------------------------------------------------------------------------------------
// Matrice de parité établissement
// ---------------------------------------------------------------------------------------------

/** Routes établissement de `src/App.tsx` avec leur ligne. */
function routesEtablissement() {
  const lignes = read('src/App.tsx').split('\n');
  const routes = [];
  lignes.forEach((l, i) => {
    const m = /<Route path="([^"]+)"/.exec(l);
    if (!m) return;
    const p = m[1];
    if (p.startsWith('/etablissement/') || p.startsWith('/etab/') || p === '/inscription/etablissement'
      || p === '/contrat/:id' || p === '/contrat/:id/certificat') routes.push({ chemin: p, ligne: i + 1 });
  });
  return routes;
}

const NATIF = ['/etablissement/tableau-de-bord', '/etablissement/dashboard', '/etablissement/missions',
  '/etablissement/missions/:id', '/etablissement/missions/creer', '/etablissement/presences',
  '/etablissement/presences/mission/:id', '/etablissement/contrats', '/etablissement/assurance',
  '/etablissement/contrat-plateforme', '/contrat/:id', '/etablissement/messagerie', '/etablissement/mon-compte'];

test('PARITE_ETABLISSEMENT.md : 47 routes du web, une ligne chacune avec sa ligne App.tsx, zéro « abandonné »', () => {
  const doc = read('docs/mobile-swift/PARITE_ETABLISSEMENT.md');
  const routes = routesEtablissement();
  assert.equal(routes.length, 47, 'nombre de routes établissement de App.tsx');
  const lignes = doc.split('\n').filter(l => l.startsWith('| `/'));
  assert.equal(lignes.length, 47, 'une ligne de matrice par route');
  for (const { chemin, ligne } of routes) {
    const row = lignes.find(l => l.startsWith(`| \`${chemin}\` (l.${ligne}) |`));
    assert.ok(row, `${chemin} (l.${ligne}) absente de la matrice`);
    const [, , , statut, cible] = row.split('|').map(c => c.trim());
    assert.equal(statut, 'à faire', `${chemin} : statut initial`);
    if (NATIF.includes(chemin)) assert.match(cible, /^natif/, `${chemin} : cible natif attendue`);
    else assert.match(cible, /^renvoi web assumé/, `${chemin} : cible renvoi web attendue`);
  }
  assert.ok(!/abandonn/i.test(lignes.join('\n')), 'ligne « abandonné »');
});

// ---------------------------------------------------------------------------------------------
// Plan, décisions, recette
// ---------------------------------------------------------------------------------------------

test('LOT5_PLAN.md versionné et DECISIONS_LOT5.md : 30 décisions adoptées, §6 en attente de Gabrielle', () => {
  const plan = read('docs/mobile-swift/LOT5_PLAN.md');
  assert.ok(plan.startsWith('# Blueprint du lot 5'), 'blueprint du lot 5 non copié');
  for (const titre of ['## Corrections vs plan', '## 1. Périmètre', '## 2. Architecture', '### T0 — Contrats, matrice, gardes',
    '## 6. Ce qui exige Gabrielle', '## 7. Décisions à prendre (recommandation ferme)']) {
    assert.ok(plan.includes(titre), `plan : ${titre} absent`);
  }
  const decisions = read('docs/mobile-swift/DECISIONS_LOT5.md');
  for (let n = 1; n <= 30; n += 1) {
    assert.match(decisions, new RegExp(`\\| D${n} \\|[^\\n]*\\| adoptée`), `D${n} non consignée comme adoptée`);
  }
  const attente = section(decisions, 'En attente de Gabrielle');
  for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) assert.match(attente, new RegExp(`\\n${n}\\. `), `§6 point ${n} absent`);
  assert.ok(attente.includes('LOT5_PLAN.md') && attente.includes('§6'), 'renvoi au §6 du blueprint absent');
  assert.ok(decisions.includes('LOTS_2_5_DECISIONS') || decisions.includes('2 novembre 2026'), 'mandat non cité');
});

test('RECETTE_DEVICE_LOT5.md : squelette des preuves appareil du lot 5', () => {
  const recette = read('docs/mobile-swift/RECETTE_DEVICE_LOT5.md');
  for (const ligne of ['QR', 'veille', 'Universal Link', 'legacy', 'iPad']) assert.ok(recette.includes(ligne), `${ligne} absent`);
});

// ---------------------------------------------------------------------------------------------
// Textes verbatim du lot 5 (TL du lot 2, D30) et CI
// ---------------------------------------------------------------------------------------------

test('TextesWeb.swift : textes du lot 5 annotés à leur source web, mention art. 1366-1367 héritée du lot 2', () => {
  const lu = lireTextesSwift(read(TEXTES_SWIFT));
  assert.deepEqual(lu.erreurs, []);
  const parNom = new Map(lu.constantes.map(c => [c.nom, c]));
  const attendues = {
    'CandidaturesEtablissement.cgvAvantLien': 'src/components/ListeCandidatures.tsx:393',
    'CandidaturesEtablissement.cgvCheminLien': 'src/components/ListeCandidatures.tsx:394',
    'CandidaturesEtablissement.cgvLien': 'src/components/ListeCandidatures.tsx:395',
    'CandidaturesEtablissement.cgvApresLien': 'src/components/ListeCandidatures.tsx:397',
    'BlocageEtablissement.publicationSuspendue': 'src/components/BandeauBlocageAuto.tsx:61',
    'BlocageEtablissement.verificationEnCoursTitre': 'src/pages/DashboardEtablissement.tsx:564',
    'BlocageEtablissement.verificationEnCoursDetail': 'src/pages/DashboardEtablissement.tsx:565',
    'PublicationEtablissement.optionSalarieLibelle': 'src/components/FormulaireMission.tsx:766',
    'PublicationEtablissement.optionSalarieDescription': 'src/components/FormulaireMission.tsx:766',
  };
  const lireWeb = lecteurWeb(f => read(f));
  for (const [nom, source] of Object.entries(attendues)) {
    const c = parNom.get(nom);
    assert.ok(c, `${nom} absente de TextesWeb.swift`);
    assert.equal(`${c.source.fichier}:${c.source.debut}`, source, `${nom} : source`);
    assert.ok(lireWeb(c.source.fichier).unites.some(u => u.valeur === c.valeur && u.debut === c.source.debut), `${nom} : texte web`);
    assert.ok(lu.catalogue.some(e => e.cle === nom), `${nom} absente du catalogue`);
  }
  // La mention OTP art. 1366-1367 (ContratMission.tsx l.743) est celle du lot 2 : jamais dupliquée.
  const otp = lu.constantes.filter(c => c.source.fichier === 'src/pages/ContratMission.tsx' && c.source.debut === 743);
  assert.deepEqual(otp.map(c => c.nom), ['Contrat.otpDescription']);
});

test('ios-swift-ci.yml : le job « Cœur » exécute la garde des littéraux juridiques et son test, sans condition', () => {
  const ci = read('.github/workflows/ios-swift-ci.yml');
  const coeur = ci.slice(ci.indexOf('\n  coeur:'), ci.indexOf('\n  packages:'));
  const etapes = coeur.split('\n      - ').slice(1);
  const garde = etapes.find(e => e.includes('run: node scripts/mobile/check-litteraux-juridiques.mjs'));
  const negatif = etapes.find(e => e.includes('run: node --test scripts/mobile/check-litteraux-juridiques.test.mjs'));
  for (const etape of [garde, negatif]) {
    assert.ok(etape, 'étape absente du job coeur');
    assert.ok(!/\n\s+if: /.test(etape) && !etape.includes('continue-on-error'), 'étape conditionnelle ou non bloquante');
  }
  for (const evenement of ['pull_request', 'push']) {
    const bloc = ci.slice(ci.indexOf(`  ${evenement}:`), ci.indexOf(evenement === 'pull_request' ? '  push:' : '  workflow_dispatch:'));
    for (const chemin of ['scripts/mobile/check-litteraux-juridiques.mjs', 'scripts/mobile/check-litteraux-juridiques.test.mjs']) {
      assert.ok(bloc.includes(`- '${chemin}'`), `${evenement} : filtre ${chemin} absent`);
    }
  }
});

test('validate-pr.yml : l étape « Garde de livraison mobile » exécute ce test', () => {
  const ci = read('.github/workflows/validate-pr.yml');
  const bloc = ci.slice(ci.indexOf('- name: Garde de livraison mobile'), ci.indexOf('- name:', ci.indexOf('- name: Garde de livraison mobile') + 5));
  const run = bloc.split('\n').find(l => /^\s+run: /.test(l));
  assert.ok(run?.includes('tests/node/contrats-etablissement-ios.node.mjs'), 'ce test n est pas exécuté par le check requis');
});

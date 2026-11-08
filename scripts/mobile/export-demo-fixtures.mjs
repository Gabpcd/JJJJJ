#!/usr/bin/env node
/**
 * Export déterministe du monde démo de l'app iOS native (plan §4.6).
 *
 * Reproduit à l'identique l'algorithme de `mobile-native/src/data/demoGateway.ts`
 * (30 missions, 3 établissements fictifs, profil DEMO_CONTEXT) avec une horloge
 * fixée, puis écrit les fichiers JSON à clés snake_case (contrat PostgREST),
 * lus par `JoleneCore` (DemoMissionsGateway, DemoDashboardGateway) et par les XCUITest.
 *
 * Horloge fixée : 2026-11-02T00:00:00Z. Les missions démarrent donc du
 * 2026-11-03 au 2026-12-02 (07:00 UTC, ou 20:00 UTC une mission sur quatre).
 * Toute l'arithmétique est en UTC, comme dans le pilote : le résultat ne
 * dépend ni du fuseau ni de la date de la machine qui exécute le script.
 *
 * Usage :
 *   node scripts/mobile/export-demo-fixtures.mjs          # écrit les fichiers
 *   node scripts/mobile/export-demo-fixtures.mjs --check  # échoue si un fichier diffère
 */
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const FIXED_NOW = '2026-11-02T00:00:00.000Z';
export const MISSION_COUNT = 30;

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const FIXTURES_DIR = join(
  ROOT, 'ios-native', 'Packages', 'JoleneCore', 'Sources', 'JoleneCore', 'Resources', 'fixtures',
);

/** Copie de DEMO_CONTEXT (demoGateway.ts). */
export const DEMO_PROFILE = {
  user_id: 'demo-soignant',
  email: 'demonstration@example.invalid',
  profile: {
    id: 'demo-soignant',
    profession: 'IDE',
    adresse_lat: 48.8566,
    adresse_lng: 2.3522,
    rayon_deplacement_km: 50,
    tous_documents_valides: false,
    type_contrat: 'CDD',
    types_contrat_acceptes: '["CDD","LIBERAL"]',
    type_exercice: 'MIXTE',
    taux_horaire_minimum: 0,
  },
};

/** Copie de ESTABLISHMENTS (demoGateway.ts). */
export const DEMO_ETABLISSEMENTS = [
  { id: 'demo-etab-1', nom: 'Établissement fictif République', adresse_ville: 'Paris', adresse_code_postal: '75011', adresse_lat: 48.867, adresse_lng: 2.363, type: 'CLINIQUE' },
  { id: 'demo-etab-2', nom: 'Établissement fictif des Lilas', adresse_ville: 'Les Lilas', adresse_code_postal: '93260', adresse_lat: 48.879, adresse_lng: 2.421, type: 'EHPAD' },
  { id: 'demo-etab-3', nom: 'Cabinet fictif du Parc', adresse_ville: 'Vincennes', adresse_code_postal: '94300', adresse_lat: 48.848, adresse_lng: 2.439, type: 'CABINET' },
];

/**
 * Même boucle que le constructeur de DemoGateway. Chaque mission porte ses
 * créneaux sous la clé `creneaux` (la table `mission_creneaux` du pilote).
 */
export function buildDemoMissions(now = new Date(FIXED_NOW)) {
  const missions = [];
  for (let index = 0; index < MISSION_COUNT; index += 1) {
    const day = new Date(now);
    day.setUTCDate(day.getUTCDate() + index + 1);
    day.setUTCHours(index % 4 === 3 ? 20 : 7, 0, 0, 0);
    const start = day.toISOString();
    const finish = new Date(day.getTime() + 8 * 3_600_000).toISOString();
    const id = `demo-mission-${String(index + 1).padStart(3, '0')}`;
    const multi = index % 6 === 5;
    const laterStart = new Date(day.getTime() + 2 * 86_400_000).toISOString();
    const laterFinish = new Date(day.getTime() + 2 * 86_400_000 + 8 * 3_600_000).toISOString();
    const hourly = 23 + (index % 8);
    const creneaux = [
      { id: `${id}-slot-1`, mission_id: id, debut: start, fin: finish, est_pause: false, type_creneau: 'PREVISIONNEL' },
    ];
    if (multi) {
      creneaux.push({ id: `${id}-slot-2`, mission_id: id, debut: laterStart, fin: laterFinish, est_pause: false, type_creneau: 'PREVISIONNEL' });
    }
    missions.push({
      id,
      intitule: `Démonstration · ${index % 2 ? 'Soins de suite' : 'Médecine polyvalente'} ${index + 1}`,
      description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
      service: index % 2 ? 'Soins de suite' : 'Médecine polyvalente',
      profession_requise: 'IDE',
      specialite_medicale_requise: null,
      accepte_non_specialises: null,
      debut_le: start,
      fin_le: multi ? laterFinish : finish,
      duree_heures: multi ? 16 : 8,
      nb_creneaux: multi ? 2 : 1,
      taux_horaire_base: hourly,
      taux_rist_plafonne: index === 0 ? hourly : null,
      rist_plafond_applique: index === 0,
      total_brut: null,
      net_a_payer: null,
      est_urgente: index % 5 === 0,
      niveau_urgence: index % 5 === 0 ? 1 : 0,
      statut: 'OUVERTE',
      etablissement_id: DEMO_ETABLISSEMENTS[index % DEMO_ETABLISSEMENTS.length].id,
      type_contrat_recherche: index % 3 === 2 ? 'LIBERAL' : 'SALARIE',
      boostee_le: null,
      mode_remuneration: 'HORAIRE',
      retrocession_pct: null,
      creneaux,
    });
  }
  return missions;
}

/** Instant UTC `jours` jours après `now`, à `heure`:00 (même arithmétique que buildDemoMissions). */
function instantDemo(now, jours, heure) {
  const day = new Date(now);
  day.setUTCDate(day.getUTCDate() + jours);
  day.setUTCHours(heure, 0, 0, 0);
  return day;
}

/**
 * Tableau de bord démo (lot 1, T3) : corps de `fn_dashboard_soignant_complet` (clés et ordre
 * des colonnes du dump `supabase/schema/public.sql` l.27920) pour le profil fictif, plus :
 *   - `missions_assignees` : fiches et créneaux des deux missions ASSIGNEE de `mes_missions`,
 *     lisibles en détail (DemoMissionsGateway.mission) mais jamais listées dans Explorer ;
 *   - `gains_missions` : missions TERMINEE du mois relues comme le web (décision 10).
 * `missions_ouvertes` = les trois premières missions démo (ORDER BY debut_le LIMIT 3) ; la
 * proposition PROPOSEE vise demo-mission-011 et date de 30 minutes avant l'horloge fixée.
 * `gains_mois.net_total` reste présent dans le corps (contrat serveur) mais n'est jamais affiché.
 */
export function buildDemoDashboard(now = new Date(FIXED_NOW), missions = buildDemoMissions(now)) {
  const nomEtab = (id) => DEMO_ETABLISSEMENTS.find((e) => e.id === id).nom;
  const assignee = (rang, service, etablissementId, taux, contrat, jours) => {
    const id = `demo-assignee-${String(rang).padStart(3, '0')}`;
    const creneaux = jours.map((jour, index) => {
      const debut = instantDemo(now, jour, 7);
      const fin = new Date(debut.getTime() + 8 * 3_600_000);
      return { id: `${id}-slot-${index + 1}`, mission_id: id, debut: debut.toISOString(), fin: fin.toISOString(), est_pause: false, type_creneau: 'PREVISIONNEL' };
    });
    return {
      id,
      intitule: `Démonstration · Mission assignée ${rang}`,
      description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
      service,
      profession_requise: 'IDE',
      specialite_medicale_requise: null,
      accepte_non_specialises: null,
      debut_le: creneaux[0].debut,
      fin_le: creneaux[creneaux.length - 1].fin,
      duree_heures: 8 * creneaux.length,
      nb_creneaux: creneaux.length,
      taux_horaire_base: taux,
      taux_rist_plafonne: null,
      rist_plafond_applique: false,
      total_brut: null,
      net_a_payer: null,
      est_urgente: false,
      niveau_urgence: 0,
      statut: 'ASSIGNEE',
      etablissement_id: etablissementId,
      type_contrat_recherche: contrat,
      boostee_le: null,
      mode_remuneration: 'HORAIRE',
      retrocession_pct: null,
      soignant_assigne_id: DEMO_PROFILE.user_id,
      presence_confirmee_le: null,
      creneaux,
    };
  };
  const missionsAssignees = [
    assignee(1, 'Médecine polyvalente', 'demo-etab-1', 27, 'SALARIE', [3]),
    assignee(2, 'Soins de suite', 'demo-etab-2', 30, 'LIBERAL', [7, 8]),
  ];
  const ouvertes = missions.slice(0, 3);
  const proposee = missions.find((m) => m.id === 'demo-mission-011');
  const termineeDebut = instantDemo(now, -1, 7);
  const lundi = instantDemo(now, 0, 0); // 2026-11-02 est un lundi
  const semaine = missionsAssignees.filter((m) => {
    const debut = new Date(m.debut_le).getTime();
    return debut >= lundi.getTime() && debut < lundi.getTime() + 7 * 86_400_000;
  });
  const dashboard = {
    profil: {
      prenom: 'Camille', nom: 'Démo', telephone: null, date_naissance: null,
      profession: DEMO_PROFILE.profile.profession, type_contrat: DEMO_PROFILE.profile.type_contrat,
      numero_rpps: null, numero_adeli: null, rpps_verifie: false,
      adresse_lat: DEMO_PROFILE.profile.adresse_lat, adresse_lng: DEMO_PROFILE.profile.adresse_lng,
      tous_documents_valides: DEMO_PROFILE.profile.tous_documents_valides, identite_verifiee: false,
      score_fiabilite: null, total_missions_terminees: 1, heures_cumulees: 8, eligible_conversion_3200h: false,
      type_exercice: DEMO_PROFILE.profile.type_exercice, mandat_facturation_signe: false,
    },
    missions_ouvertes: ouvertes.map((m) => ({
      id: m.id, intitule: m.intitule, service: m.service, debut_le: m.debut_le, fin_le: m.fin_le,
      duree_heures: m.duree_heures, nb_creneaux: m.nb_creneaux, taux_horaire_base: m.taux_horaire_base,
      total_brut: m.total_brut, net_a_payer: m.net_a_payer, net_estime: null,
      est_urgente: m.est_urgente, etablissement_id: m.etablissement_id, profession_requise: m.profession_requise,
      type_contrat_recherche: m.type_contrat_recherche, accepte_non_specialises: m.accepte_non_specialises,
      specialite_medicale_requise: m.specialite_medicale_requise, etab_nom: nomEtab(m.etablissement_id),
    })),
    mes_missions: missionsAssignees.map((m) => ({
      id: m.id, intitule: m.intitule, debut_le: m.debut_le, fin_le: m.fin_le, duree_heures: m.duree_heures,
      statut: m.statut, etablissement_id: m.etablissement_id, etab_nom: nomEtab(m.etablissement_id),
    })),
    documents: [
      { id: 'demo-document-001', type_document: 'CARTE_IDENTITE', valide_jusqua: '2030-06-30', statut_verification: 'VERIFIE' },
    ],
    heures_semaine: semaine.reduce((total, m) => total + m.duree_heures, 0),
    gains_mois: { net_total: 224.6, brut_total: 208, nb_missions: 1 },
    gains_6mois: [{ mois: termineeDebut.toISOString().slice(0, 7), net: 224.6 }],
    missions_semaine_cal: semaine.map((m) => ({ debut_le: m.debut_le, statut: m.statut })),
    propositions: [{
      id: 'demo-proposition-001',
      mission_id: proposee.id,
      cree_le: new Date(now.getTime() - 30 * 60_000).toISOString(),
      type_contrat_choisi: null,
      missions: {
        id: proposee.id, intitule: proposee.intitule, debut_le: proposee.debut_le, fin_le: proposee.fin_le,
        duree_heures: proposee.duree_heures, taux_horaire_base: proposee.taux_horaire_base, net_estime: null,
        type_contrat_recherche: proposee.type_contrat_recherche, etablissement_id: proposee.etablissement_id,
        est_urgente: proposee.est_urgente, etab_nom: nomEtab(proposee.etablissement_id),
      },
    }],
    heures_totales_terminees: 8,
    missions_oubliees_count: 0,
    notifs_non_lues: 2,
  };
  return {
    fixed_now: now.toISOString(),
    dashboard,
    missions_assignees: missionsAssignees,
    gains_missions: [
      { id: 'demo-terminee-001', type_contrat_applique: 'SALARIE', type_contrat_recherche: 'SALARIE', total_brut: 208, net_a_payer: 224.6, net_estime: 162.4 },
    ],
  };
}

// ---------------------------------------------------------------------------------------------
// Lot 2, T8 — contrats démo (docs/mobile-swift/LOT2_PLAN.md §2.8 « Contrats »).
// Les originaux sont rendus par le moteur serveur lui-même : `rendreCddEmployeur`
// (supabase/functions/_shared/cdd-employeur.ts, sans import, chargeable par Node) puis le gabarit
// `wrapInDocument` de supabase/functions/generate-contrat-mission-pdf/index.ts, relu tel quel dans le
// source (la fonction n'est pas exportable : le fichier importe des modules Deno). Aucun texte de
// contrat n'est écrit ici : seules les données déclarées par « l'employeur » sont fictives et le
// disent. L'empreinte est le SHA-256 des octets UTF-8 du document complet, comme `sha256Hex` de l'edge.
// ---------------------------------------------------------------------------------------------

export const EDGE_CONTRAT = 'supabase/functions/generate-contrat-mission-pdf/index.ts';
const ENTETE_WRAP = 'function wrapInDocument(htmlBody: string, contratNumero: string): string {\n  return `';

/** `escapeHtml` de l'edge (index.ts l.25-33), recopiée : même ordre des cinq remplacements. */
function escapeHtmlEdge(s) {
  if (s == null) return '';
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** Gabarit exact de `wrapInDocument`, extrait du source de l'edge (échoue si sa forme change). */
export function gabaritWrapInDocument(source = readFileSync(join(ROOT, EDGE_CONTRAT), 'utf8')) {
  const debut = source.indexOf(ENTETE_WRAP);
  if (debut < 0) throw new Error(`${EDGE_CONTRAT} : wrapInDocument introuvable (forme changée)`);
  const corps = source.slice(debut + ENTETE_WRAP.length);
  const fin = corps.indexOf('`;\n}');
  if (fin < 0) throw new Error(`${EDGE_CONTRAT} : fin du gabarit de wrapInDocument introuvable`);
  const gabarit = corps.slice(0, fin);
  const interpolations = gabarit.match(/\$\{[^}]*\}/g) ?? [];
  const attendues = ['${escapeHtml(contratNumero)}', '${htmlBody}'];
  // Sans échappement ni accent grave, le texte source du gabarit est sa valeur à l'exécution.
  if (interpolations.length !== attendues.length || interpolations.some((x, i) => x !== attendues[i])
    || gabarit.includes('`') || gabarit.includes('\\')) {
    throw new Error(`${EDGE_CONTRAT} : interpolations de wrapInDocument inattendues (${interpolations.join(', ')})`);
  }
  return gabarit;
}

export function wrapInDocument(htmlBody, contratNumero, gabarit = gabaritWrapInDocument()) {
  return gabarit.replace('${escapeHtml(contratNumero)}', () => escapeHtmlEdge(contratNumero))
    .replace('${htmlBody}', () => htmlBody);
}

/** Date et heure de Paris au format long de l'edge (`formatDate`, l.36-47), sans dépendre des littéraux ICU. */
function dateLongueParis(iso) {
  const parties = Object.fromEntries(new Intl.DateTimeFormat('fr-FR', {
    timeZone: 'Europe/Paris', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(iso)).map(p => [p.type, p.value]));
  return `${parties.day} ${parties.month} ${parties.year} à ${parties.hour}:${parties.minute}`;
}

const FICTIF = 'Donnée fictive de démonstration';

/** Données « employeur » fictives, cadre `PRIVE_TERME_PRECIS`, validées par `validerDonneesCdd` de l'edge. */
const DONNEES_CDD_DEMO = {
  cadre: 'PRIVE_TERME_PRECIS', confirme: true,
  representant_nom: 'Représentant fictif', representant_qualite: 'Direction fictive',
  motif_type: 'ACCROISSEMENT', motif_precis: FICTIF, poste: FICTIF, qualification: FICTIF, lieu_travail: FICTIF,
  risques: 'NON', convention_collective: FICTIF, renouvellement: FICTIF, essai: 'AUCUN', remuneration_accessoires: FICTIF,
  temps_partiel: 'NON', retraite_nom: FICTIF, retraite_adresse: FICTIF, prevoyance: 'NON',
};

/** Original démo complet : `rendreCddEmployeur` puis `wrapInDocument`, empreinte SHA-256 UTF-8. */
export function rendreOriginalDemo({ numero, mission, etablissement, prepareLe }, moteur) {
  const { donnees, champs } = moteur.validerDonneesCdd(DONNEES_CDD_DEMO);
  if (!donnees) throw new Error(`données CDD démo refusées par validerDonneesCdd : ${champs.join(', ')}`);
  // Variables de `buildVariables` (index.ts l.75-115) : valeurs échappées par `escapeHtml`.
  const vars = {
    numero_contrat: escapeHtmlEdge(numero),
    etablissement_nom: escapeHtmlEdge(etablissement.nom),
    etablissement_siret: escapeHtmlEdge(''),
    etablissement_adresse: escapeHtmlEdge([etablissement.adresse_code_postal, etablissement.adresse_ville].filter(Boolean).join(', ')),
    soignant_prenom: escapeHtmlEdge('Camille'),
    soignant_nom: escapeHtmlEdge('Démo'),
    soignant_date_naissance: escapeHtmlEdge('non renseignée'),
    soignant_adresse: escapeHtmlEdge(''),
    intitule_mission: escapeHtmlEdge(mission.intitule),
    debut_le: escapeHtmlEdge(dateLongueParis(mission.debut_le)),
    fin_le: escapeHtmlEdge(dateLongueParis(mission.fin_le)),
    duree_heures: escapeHtmlEdge(mission.duree_heures),
    taux_horaire: Number(mission.taux_horaire_base).toFixed(2),
  };
  const html = wrapInDocument(moteur.rendreCddEmployeur(vars, donnees, etablissement.id, prepareLe), numero);
  return { html, empreinte: createHash('sha256').update(html, 'utf8').digest('hex') };
}

/**
 * Contrats démo (§2.8) : `demo-contrat-001` CDD `EN_ATTENTE_SIGNATURES` créé 10 h avant l'horloge (62 h
 * restantes) avec original ; `demo-contrat-002` CDD `SIGNE_COMPLET` avec original et deux lignes de
 * certificat (projection `SignatureCertificat.colonnes`) ; `demo-contrat-003` CDD sans original (aucune
 * action soignant, décision 19). Lignes à la projection `ContratDetail.selection`, contexte de mission à
 * celle de `MissionContrat.selection`. Le second original sert au partage d'un contrat signé (T9a).
 */
export function buildDemoContrats(moteur, now = new Date(FIXED_NOW), dashboard = buildDemoDashboard(now)) {
  const etab = id => DEMO_ETABLISSEMENTS.find(e => e.id === id);
  const iso = ms => new Date(ms).toISOString();
  const heure = 3_600_000;
  const assignee = dashboard.missions_assignees.find(m => m.id === 'demo-assignee-001');
  const termineeDebut = instantDemo(now, -1, 7);
  const missions = [
    { id: assignee.id, intitule: assignee.intitule, service: assignee.service, debut_le: assignee.debut_le, fin_le: assignee.fin_le,
      duree_heures: assignee.duree_heures, taux_horaire_base: assignee.taux_horaire_base },
    { id: 'demo-terminee-001', intitule: 'Démonstration · Mission terminée 1', service: 'Médecine polyvalente',
      debut_le: termineeDebut.toISOString(), fin_le: iso(termineeDebut.getTime() + 8 * heure), duree_heures: 8, taux_horaire_base: 26 },
    { id: 'demo-contrat-mission-003', intitule: 'Démonstration · Mission à préparer 3', service: 'Soins de suite',
      debut_le: instantDemo(now, 12, 7).toISOString(), fin_le: iso(instantDemo(now, 12, 7).getTime() + 8 * heure), duree_heures: 8,
      taux_horaire_base: 27 },
  ];
  const ligne = (champs) => ({
    id: champs.id, mission_id: champs.mission.id, soignant_id: DEMO_PROFILE.user_id, etablissement_id: champs.etablissement,
    numero_contrat: champs.numero, type_contrat: 'CDD', statut: champs.statut, mode_signature: 'JOLENE_OTP',
    contenu_html: champs.original?.html ?? null, hash_document: champs.original?.empreinte ?? null,
    storage_path: champs.original ? `${champs.id}/original-${champs.id.slice(-3)}.html` : null,
    contenu_html_rendu_le: champs.original ? champs.renduLe : null,
    signature_soignant: champs.signeLe != null, signature_soignant_le: champs.signeLe ?? null,
    signature_etablissement: champs.signeEtabLe != null, signature_etablissement_le: champs.signeEtabLe ?? null,
    cree_le: champs.creeLe,
  });
  const creeLe1 = iso(now.getTime() - 10 * heure);
  const renduLe1 = iso(now.getTime() - 10 * heure + 5 * 60_000);
  const original1 = rendreOriginalDemo({ numero: 'DEMO-0001', mission: missions[0], etablissement: etab('demo-etab-1'), prepareLe: renduLe1 }, moteur);
  const creeLe2 = iso(now.getTime() - 96 * heure);
  const renduLe2 = iso(now.getTime() - 96 * heure + 5 * 60_000);
  const signeEtab2 = iso(now.getTime() - 95 * heure);
  const signeSoignant2 = iso(now.getTime() - 94 * heure);
  const original2 = rendreOriginalDemo({ numero: 'DEMO-0002', mission: missions[1], etablissement: etab('demo-etab-1'), prepareLe: renduLe2 }, moteur);
  const contrats = [
    ligne({ id: 'demo-contrat-001', mission: missions[0], etablissement: 'demo-etab-1', numero: 'DEMO-0001',
      statut: 'EN_ATTENTE_SIGNATURES', original: original1, renduLe: renduLe1, creeLe: creeLe1 }),
    ligne({ id: 'demo-contrat-002', mission: missions[1], etablissement: 'demo-etab-1', numero: 'DEMO-0002',
      statut: 'SIGNE_COMPLET', original: original2, renduLe: renduLe2, creeLe: creeLe2, signeLe: signeSoignant2, signeEtabLe: signeEtab2 }),
    ligne({ id: 'demo-contrat-003', mission: missions[2], etablissement: 'demo-etab-2', numero: 'DEMO-0003',
      statut: 'EN_ATTENTE_SIGNATURES', original: null, creeLe: iso(now.getTime() - 2 * heure) }),
  ];
  const signature = (id, role, userId, signeA) => ({
    id, contrat_id: 'demo-contrat-002', signataire_user_id: userId, signataire_role: role, signe_a: signeA,
    ip_signature: null, user_agent: null, hash_document: original2.empreinte, otp_valide_a: signeA,
    psc_session_active: false, rpps_verifie: false, traits_identite_verifies: false, statut_signature: 'signe', cree_le: signeA,
  });
  return {
    json: {
      fixed_now: now.toISOString(),
      contrats,
      missions,
      originaux: [
        { contrat_id: 'demo-contrat-001', storage_path: contrats[0].storage_path, fichier: 'demo-contrat-001.html' },
        { contrat_id: 'demo-contrat-002', storage_path: contrats[1].storage_path, fichier: 'demo-contrat-002.html' },
      ],
      signatures: [
        signature('demo-signature-002-etab', 'etablissement', 'demo-etab-1', signeEtab2),
        signature('demo-signature-002-soignant', 'soignant', DEMO_PROFILE.user_id, signeSoignant2),
      ],
    },
    fichiers: { 'demo-contrat-001.html': original1.html, 'demo-contrat-002.html': original2.html },
  };
}

/** Moteur de rendu serveur (`cdd-employeur.ts`), chargé par le décapage de types de Node 24. */
export async function chargerMoteurContrat() {
  return import(pathToFileURL(join(ROOT, 'supabase', 'functions', '_shared', 'cdd-employeur.ts')).href);
}

export async function buildFixtures() {
  const contrats = buildDemoContrats(await chargerMoteurContrat());
  return {
    'demo-missions.json': { fixed_now: FIXED_NOW, missions: buildDemoMissions() },
    'demo-etablissements.json': { fixed_now: FIXED_NOW, etablissements: DEMO_ETABLISSEMENTS },
    'demo-profile.json': { fixed_now: FIXED_NOW, ...DEMO_PROFILE },
    'demo-dashboard.json': buildDemoDashboard(),
    'demo-contrats.json': contrats.json,
    ...Object.fromEntries(Object.entries(contrats.fichiers).map(([nom, texte]) => [nom, { brut: texte }])),
  };
}

/** JSON indenté, ou texte brut tel quel pour un original de contrat (`{ brut }`, octets hachés). */
const serialize = (value) => (value && typeof value.brut === 'string' ? value.brut : `${JSON.stringify(value, null, 2)}\n`);

async function main(argv) {
  const check = argv.includes('--check');
  const fixtures = await buildFixtures();
  mkdirSync(FIXTURES_DIR, { recursive: true });
  let drift = 0;
  for (const [name, value] of Object.entries(fixtures)) {
    const path = join(FIXTURES_DIR, name);
    const expected = serialize(value);
    if (check) {
      let actual = null;
      try { actual = readFileSync(path, 'utf8'); } catch { actual = null; }
      if (actual !== expected) {
        drift += 1;
        console.error(`DIFF ${path}`);
      }
      continue;
    }
    writeFileSync(path, expected, 'utf8');
    console.log(`OK ${path}`);
  }
  if (check) {
    if (drift > 0) {
      console.error(`${drift} fichier(s) de fixtures démo divergent : relancer sans --check.`);
      process.exit(1);
    }
    console.log(`OK fixtures démo identiques (${Object.keys(fixtures).length} fichiers).`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main(process.argv.slice(2));
}

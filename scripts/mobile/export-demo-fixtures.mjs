#!/usr/bin/env node
/**
 * Export déterministe du monde démo de l'app iOS native (plan §4.6).
 *
 * Reproduit à l'identique l'algorithme de `mobile-native/src/data/demoGateway.ts`
 * (30 missions, 3 établissements fictifs, profil DEMO_CONTEXT) avec une horloge
 * fixée, puis écrit les fichiers JSON à clés snake_case (contrat PostgREST),
 * lus par `JoleneCore` (DemoMissionsGateway, DemoDashboardGateway, DemoMesMissionsGateway) et par les XCUITest.
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
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

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
 *   - `missions_assignees` : fiches et créneaux des dix missions ASSIGNEE du soignant (« À venir » de
 *     Mes missions, T5 : une liste plus haute que l'écran sur les trois formats, revue B8 2e passe),
 *     lisibles en détail (DemoMissionsGateway.mission) mais jamais listées dans Explorer ;
 *     `mes_missions` en garde les trois premières (ORDER BY debut_le LIMIT 3, comme le serveur) ;
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
    assignee(3, 'Médecine polyvalente', 'demo-etab-1', 28, 'SALARIE', [11]),
    assignee(4, 'Soins de suite', 'demo-etab-2', 26, 'SALARIE', [13]),
    assignee(5, 'Médecine polyvalente', 'demo-etab-3', 31, 'LIBERAL', [15, 16]),
    assignee(6, 'Soins de suite', 'demo-etab-1', 29, 'SALARIE', [18]),
    assignee(7, 'Médecine polyvalente', 'demo-etab-2', 25, 'SALARIE', [20]),
    assignee(8, 'Soins de suite', 'demo-etab-3', 32, 'LIBERAL', [22]),
    assignee(9, 'Médecine polyvalente', 'demo-etab-1', 27, 'SALARIE', [24]),
    assignee(10, 'Soins de suite', 'demo-etab-2', 30, 'LIBERAL', [26, 27]),
  ];
  // `mes_missions` : ORDER BY debut_le LIMIT 3 (public.sql, fn_dashboard_soignant_complet).
  const prochaines = [...missionsAssignees].sort((a, b) => a.debut_le.localeCompare(b.debut_le)).slice(0, 3);
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
    mes_missions: prochaines.map((m) => ({
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

/**
 * Mes missions démo (lot 1, T5) : candidatures EN_ATTENTE du profil fictif et missions passées.
 *   - `candidatures` : lignes `candidatures` (clés de la requête du web, `MissionsSoignant.tsx`
 *     l.181-184) sur deux missions ouvertes de `demo-missions.json` ; la seconde porte un message
 *     « super-like » (pastille « ★ Priorité historique ») et un choix de contrat libéral ;
 *   - `passees` : missions TERMINEE / ANNULEE_PAR_ETABLISSEMENT du soignant avec leurs créneaux et
 *     leurs colonnes financières (`net_estime`, `type_contrat_applique`). `demo-terminee-001` porte
 *     les montants de `gains_missions` de `demo-dashboard.json` (même mission, mêmes valeurs).
 * Les missions « À venir » sont les `missions_assignees` du tableau de bord : jamais recopiées ici.
 */
export function buildDemoMesMissions(now = new Date(FIXED_NOW), missions = buildDemoMissions(now)) {
  const candidature = (rang, missionId, heuresAvant, typeContrat, message) => {
    if (!missions.some((m) => m.id === missionId)) throw new Error(`mission démo absente : ${missionId}`);
    return {
      id: `demo-candidature-${String(rang).padStart(3, '0')}`,
      statut: 'EN_ATTENTE',
      message,
      type_contrat_choisi: typeContrat,
      cree_le: new Date(now.getTime() - heuresAvant * 3_600_000).toISOString(),
      mission_id: missionId,
    };
  };
  const passee = (id, intitule, service, etablissementId, statut, contrat, jours, heure, montants) => {
    const creneaux = jours.map((jour, index) => {
      const debut = instantDemo(now, jour, heure);
      const fin = new Date(debut.getTime() + 8 * 3_600_000);
      return { id: `${id}-slot-${index + 1}`, mission_id: id, debut: debut.toISOString(), fin: fin.toISOString(), est_pause: false, type_creneau: 'PREVISIONNEL' };
    });
    return {
      id,
      intitule,
      description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
      service,
      profession_requise: 'IDE',
      specialite_medicale_requise: null,
      accepte_non_specialises: null,
      debut_le: creneaux[0].debut,
      fin_le: creneaux[creneaux.length - 1].fin,
      duree_heures: 8 * creneaux.length,
      nb_creneaux: creneaux.length,
      taux_horaire_base: montants.taux,
      taux_rist_plafonne: null,
      rist_plafond_applique: false,
      total_brut: montants.total_brut,
      net_a_payer: montants.net_a_payer,
      est_urgente: false,
      niveau_urgence: 0,
      statut,
      etablissement_id: etablissementId,
      type_contrat_recherche: contrat,
      boostee_le: null,
      mode_remuneration: 'HORAIRE',
      retrocession_pct: null,
      soignant_assigne_id: DEMO_PROFILE.user_id,
      type_contrat_applique: montants.type_contrat_applique,
      net_estime: montants.net_estime,
      creneaux,
    };
  };
  return {
    fixed_now: now.toISOString(),
    candidatures: [
      candidature(1, 'demo-mission-004', 6, 'SALARIE', null),
      candidature(2, 'demo-mission-009', 14.5, 'LIBERAL', 'Super-like : disponible sur toute la période.'),
    ],
    passees: [
      passee('demo-terminee-001', 'Démonstration · Mission terminée 1', 'Médecine polyvalente', 'demo-etab-1', 'TERMINEE', 'SALARIE', [-1], 7,
        { taux: 26, total_brut: 208, net_a_payer: 224.6, net_estime: 162.4, type_contrat_applique: 'SALARIE' }),
      passee('demo-terminee-002', 'Démonstration · Mission terminée 2', 'Soins de suite', 'demo-etab-2', 'TERMINEE', 'LIBERAL', [-13, -12], 7,
        { taux: 28, total_brut: 448, net_a_payer: 448, net_estime: null, type_contrat_applique: 'LIBERAL' }),
      passee('demo-annulee-001', 'Démonstration · Mission annulée', 'Médecine polyvalente', 'demo-etab-3', 'ANNULEE_PAR_ETABLISSEMENT', 'SALARIE', [-21], 20,
        { taux: 25, total_brut: null, net_a_payer: null, net_estime: null, type_contrat_applique: 'SALARIE' }),
    ],
  };
}

export function buildFixtures() {
  return {
    'demo-missions.json': { fixed_now: FIXED_NOW, missions: buildDemoMissions() },
    'demo-etablissements.json': { fixed_now: FIXED_NOW, etablissements: DEMO_ETABLISSEMENTS },
    'demo-profile.json': { fixed_now: FIXED_NOW, ...DEMO_PROFILE },
    'demo-dashboard.json': buildDemoDashboard(),
    'demo-mes-missions.json': buildDemoMesMissions(),
  };
}

const serialize = (value) => `${JSON.stringify(value, null, 2)}\n`;

function main(argv) {
  const check = argv.includes('--check');
  const fixtures = buildFixtures();
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
  main(process.argv.slice(2));
}

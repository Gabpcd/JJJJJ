#!/usr/bin/env node
/**
 * Export déterministe du monde démo de l'app iOS native (plan §4.6).
 *
 * Reproduit à l'identique l'algorithme de `mobile-native/src/data/demoGateway.ts`
 * (30 missions, 3 établissements fictifs, profil DEMO_CONTEXT) avec une horloge
 * fixée, puis écrit trois fichiers JSON à clés snake_case (contrat PostgREST),
 * lus par `JoleneCore` (DemoMissionsGateway) et par les XCUITest.
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

export function buildFixtures() {
  return {
    'demo-missions.json': { fixed_now: FIXED_NOW, missions: buildDemoMissions() },
    'demo-etablissements.json': { fixed_now: FIXED_NOW, etablissements: DEMO_ETABLISSEMENTS },
    'demo-profile.json': { fixed_now: FIXED_NOW, ...DEMO_PROFILE },
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

// Génération de données de test pour les scénarios k6.
//
// Convention : tous les emails créés sont en `loadtest-<runId>-<vu>-<iter>@jolene.app`
// pour permettre un cleanup ciblé après les runs.

/** Identifiant unique pour ce run k6 (utilisé dans les emails seedés). */
export function runId() {
  // k6 ne donne pas d'ID de run natif → on utilise __ENV.LOAD_TEST_RUN_ID si fourni
  // par le workflow CI, sinon timestamp.
  return __ENV.LOAD_TEST_RUN_ID || `local${Date.now()}`;
}

/** Email unique par VU + iter (évite collision dans signup massif). */
export function uniqueEmail(scenario) {
  return `loadtest-${scenario}-${runId()}-vu${__VU}-it${__ITER}@jolene.app`;
}

/** Mot de passe valide selon les contraintes Supabase (>= 6 chars). */
export function strongPassword() {
  return 'LoadTest!2026';
}

/** Métadonnées soignant minimales pour signup test. */
export function soignantMetadata() {
  return {
    role: 'SOIGNANT',
    profession: 'IDE',
    prenom: 'Load',
    nom: `Test${__VU}`,
    via_loadtest: true,
  };
}

/** Métadonnées étab minimales pour signup test. */
export function etabMetadata() {
  return {
    role: 'ADMIN_ETABLISSEMENT',
    nom: `LoadTestEtab${__VU}`,
    siret: `${10000000000000 + __VU * 100 + __ITER}`.slice(-14),
    via_loadtest: true,
  };
}

/** Filtres recherche missions variés (cardinalité réaliste). */
export const PROFESSIONS = [
  'IDE', 'AS', 'IADE', 'IBODE', 'AES', 'PUER', 'KINE', 'SF',
  'INFIRMIER', 'AIDE_SOIGNANT', null, // null = pas de filtre
];

export const VILLES = [
  'Paris', 'Lyon', 'Marseille', 'Toulouse', 'Nice', 'Nantes',
  'Strasbourg', 'Bordeaux', 'Lille', 'Rennes', '75001', '69002',
  null,
];

/** Pioche aléatoire dans un tableau. */
export function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

/** Couple {profession, ville} aléatoire pour scenario recherche. */
export function randomFilters() {
  return {
    p_profession: pickRandom(PROFESSIONS),
    p_ville: pickRandom(VILLES),
  };
}

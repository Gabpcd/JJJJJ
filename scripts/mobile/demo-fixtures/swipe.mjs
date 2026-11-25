/**
 * Fixtures démo du domaine « swipe » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T3a.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `buildDemoSwipe` vient d'`export-demo-fixtures.mjs` (T3a, livré sur une base sans le découpage de T1c) : déplacé ici
 * à l'intégration de la vague C (revue B8 de #1165, m2), sortie identique (`export-demo-fixtures.mjs --check`). Les
 * missions, établissements et profil démo sont ceux de l'exporteur (une seule source) : l'import est cyclique
 * (exporteur → lot4.mjs → ce module → exporteur), sans effet tant que ces liaisons ne sont lues qu'à l'appel de
 * `fixtures()`, jamais au chargement du module.
 */
import { buildDemoMissions, DEMO_ETABLISSEMENTS, DEMO_PROFILE, FIXED_NOW } from '../export-demo-fixtures.mjs';

/**
 * Paquet de swipe démo (lot 4, T3a ; `docs/mobile-swift/LOT4_PLAN.md` §2.7), lu par `DemoSwipeGateway` : corps de
 * `fn_obtenir_missions_swipe` (`{missions:[…]}`, clés du `jsonb_build_object` du dump) pour douze cartes : dix missions
 * ouvertes de `demo-missions.json` (015 à 024, aucune n'est déjà favorite, candidatée ou proposée dans une autre
 * fixture) et deux missions de recette du paquet (T3b, ci-dessous). Le planning des dix premières n'est pas recopié : la
 * gateway démo lit les créneaux de `demo-missions.json`, comme la validation de `DemoCandidatureGateway`. Ordre
 * déterministe (score décroissant, score inconnu en dernier), jamais aléatoire.
 *   - deux cartes sans score calculé (`score: null`, migration `20261102204820`) : 019 et `demo-swipe-deja` ;
 *   - 018 (libérale) : `paiement_rapide` et breakdown portant `connaissance_etab` et `paiement_rapide` (raisons épinglées) ;
 *   - distance serveur arrondie au dixième depuis l'adresse du profil démo ; montants à 0 comme les `COALESCE` du serveur.
 *
 * Missions de recette du paquet (T3b, `missions_recette`) : deux missions ouvertes qui n'existent que pour le swipe,
 * jamais listées par Explorer (comme la mission de recette de la confirmation de présence du lot 1, ouverte par lien
 * seulement), servies avec leurs créneaux sous la forme de `demo-missions.json` :
 *   - `demo-swipe-choix` : contrat `TOUS` ; le profil démo étant `MIXTE`, le ❤️ répond `choix_requis` puis est rejoué
 *     avec l'option choisie (aucune mission de `demo-missions.json` n'est `TOUS`) ;
 *   - `demo-swipe-deja` : déjà swipée ailleurs (`deja_swipees`), servie quand même par ce paquet lu avant : toute
 *     réponse y est refusée par `mission_deja_swipee`, puis la carte quitte le paquet.
 * Les mondes démo qui relisent une mission par son identifiant (candidature, favoris, Mes missions, détail) les
 * connaissent par `DemoFixtures.missionsRecetteSwipe()`.
 */
export const SWIPE_CHOIX = 'demo-swipe-choix';
export const SWIPE_DEJA = 'demo-swipe-deja';
export const SWIPE_MISSIONS = [
  ...Array.from({ length: 10 }, (_, i) => `demo-mission-${String(15 + i).padStart(3, '0')}`),
  SWIPE_CHOIX,
  SWIPE_DEJA,
];
const SWIPE_SANS_SCORE = new Set(['demo-mission-019', SWIPE_DEJA]);
/** Score servi des missions de recette (les autres : `94 - rang × 3`, inchangé depuis T3a). */
const SWIPE_SCORE_RECETTE = { [SWIPE_CHOIX]: 92 };
// `e.score_qualite` du serveur, sur 100 (le web l'arrondit et l'affiche « N/100 ») ; `null` : établissement sans score.
const SWIPE_ETAB_SCORE = { 'demo-etab-1': 92, 'demo-etab-2': 84, 'demo-etab-3': null };

/** Mission de recette du paquet : même forme qu'une mission de `buildDemoMissions`, un créneau PREVISIONNEL de 8 h. */
function missionRecette(now, { id, jours, service, etablissementId, contrat, taux }) {
  const debut = new Date(now);
  debut.setUTCDate(debut.getUTCDate() + jours);
  debut.setUTCHours(7, 0, 0, 0);
  const fin = new Date(debut.getTime() + 8 * 3_600_000);
  return {
    id,
    intitule: `Démonstration · ${service}`,
    description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
    service,
    profession_requise: 'IDE',
    specialite_medicale_requise: null,
    accepte_non_specialises: null,
    debut_le: debut.toISOString(),
    fin_le: fin.toISOString(),
    duree_heures: 8,
    nb_creneaux: 1,
    taux_horaire_base: taux,
    taux_rist_plafonne: null,
    rist_plafond_applique: false,
    total_brut: null,
    net_a_payer: null,
    est_urgente: false,
    niveau_urgence: 0,
    statut: 'OUVERTE',
    etablissement_id: etablissementId,
    type_contrat_recherche: contrat,
    boostee_le: null,
    mode_remuneration: 'HORAIRE',
    retrocession_pct: null,
    mode_attribution: 'CANDIDATURE',
    presence_confirmee_le: null,
    soignant_assigne_id: null,
    creneaux: [
      { id: `${id}-slot-1`, mission_id: id, debut: debut.toISOString(), fin: fin.toISOString(), est_pause: false, type_creneau: 'PREVISIONNEL' },
    ],
  };
}

/** Les deux missions de recette du paquet (T3b), dans l'ordre de `SWIPE_MISSIONS`. */
export function buildMissionsRecetteSwipe(now = new Date(FIXED_NOW)) {
  return [
    missionRecette(now, { id: SWIPE_CHOIX, jours: 18, service: 'Chirurgie ambulatoire', etablissementId: 'demo-etab-1', contrat: 'TOUS', taux: 31 }),
    missionRecette(now, { id: SWIPE_DEJA, jours: 27, service: 'Gériatrie', etablissementId: 'demo-etab-2', contrat: 'SALARIE', taux: 27 }),
  ];
}

function distanceDemoKm(lat1, lng1, lat2, lng2) {
  const rad = (x) => (x * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return Math.round(6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10;
}

export function buildDemoSwipe(now = new Date(FIXED_NOW), missions = buildDemoMissions(now)) {
  const recette = buildMissionsRecetteSwipe(now);
  const lignes = SWIPE_MISSIONS.map((id, rang) => {
    const m = [...missions, ...recette].find((mission) => mission.id === id);
    const e = DEMO_ETABLISSEMENTS.find((etab) => etab.id === m.etablissement_id);
    const sansScore = SWIPE_SANS_SCORE.has(id);
    const score = sansScore ? null : SWIPE_SCORE_RECETTE[id] ?? 94 - rang * 3;
    const breakdown = sansScore ? {} : {
      distance: 24 - (rang % 5) * 3,
      tarif: 12 + (rang % 4) * 3,
      horaire: 10 + (rang % 3) * 2,
      etablissement: 8 + (rang % 2) * 4,
      urgence: m.est_urgente ? 10 : 0,
      soignant_fiabilite: 9,
      ...(id === 'demo-mission-018' ? { connaissance_etab: 3, paiement_rapide: 2 } : {}),
    };
    return {
      mission_id: m.id,
      intitule: m.intitule,
      profession_requise: m.profession_requise,
      etablissement_id: e.id,
      etablissement_nom: e.nom,
      etablissement_ville: e.adresse_ville,
      etablissement_code_postal: e.adresse_code_postal,
      etablissement_logo_url: null,
      etablissement_score: SWIPE_ETAB_SCORE[e.id],
      taux_horaire_base: m.taux_horaire_base,
      duree_heures: m.duree_heures,
      debut_le: m.debut_le,
      fin_le: m.fin_le,
      est_urgente: m.est_urgente,
      service: m.service,
      type_contrat_applique: null,
      type_contrat_recherche: m.type_contrat_recherche,
      nb_creneaux: m.nb_creneaux,
      total_brut: m.total_brut,
      net_a_payer: m.net_a_payer,
      net_estime: null,
      montant_ifm: 0,
      montant_icp: 0,
      montant_majoration_nuit: 0,
      montant_majoration_dimanche: 0,
      montant_majoration_ferie: 0,
      score,
      breakdown,
      paiement_rapide: id === 'demo-mission-018',
      distance_km: distanceDemoKm(DEMO_PROFILE.profile.adresse_lat, DEMO_PROFILE.profile.adresse_lng, e.adresse_lat, e.adresse_lng),
    };
  });
  lignes.sort((a, b) => (b.score ?? -1) - (a.score ?? -1));
  return { fixed_now: now.toISOString(), missions: lignes, missions_recette: recette, deja_swipees: [SWIPE_DEJA] };
}

/**
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  return { 'demo-swipe.json': buildDemoSwipe(contexte.now) };
}

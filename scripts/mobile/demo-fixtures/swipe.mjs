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
 * `fn_obtenir_missions_swipe` (`{missions:[…]}`, clés du `jsonb_build_object` du dump) pour douze missions ouvertes
 * de `demo-missions.json` (015 à 026, aucune n'est déjà favorite, candidatée ou proposée dans une autre fixture). Le
 * planning n'est pas recopié : la gateway démo lit les créneaux de `demo-missions.json`, comme la validation de
 * `DemoCandidatureGateway`. Ordre déterministe (score décroissant, score inconnu en dernier), jamais aléatoire.
 *   - deux missions sans score calculé (`score: null`, migration `20261102204820`) : 019 et 025 ;
 *   - 018 (libérale) : `paiement_rapide` et breakdown portant `connaissance_etab` et `paiement_rapide` (raisons épinglées) ;
 *   - distance serveur arrondie au dixième depuis l'adresse du profil démo ; montants à 0 comme les `COALESCE` du serveur.
 */
export const SWIPE_MISSIONS = Array.from({ length: 12 }, (_, i) => `demo-mission-${String(15 + i).padStart(3, '0')}`);
const SWIPE_SANS_SCORE = new Set(['demo-mission-019', 'demo-mission-025']);
const SWIPE_ETAB_SCORE = { 'demo-etab-1': 4.6, 'demo-etab-2': 4.2, 'demo-etab-3': null };

function distanceDemoKm(lat1, lng1, lat2, lng2) {
  const rad = (x) => (x * Math.PI) / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return Math.round(6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10;
}

export function buildDemoSwipe(now = new Date(FIXED_NOW), missions = buildDemoMissions(now)) {
  const lignes = SWIPE_MISSIONS.map((id, rang) => {
    const m = missions.find((mission) => mission.id === id);
    const e = DEMO_ETABLISSEMENTS.find((etab) => etab.id === m.etablissement_id);
    const sansScore = SWIPE_SANS_SCORE.has(id);
    const score = sansScore ? null : 94 - rang * 3;
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
  return { fixed_now: now.toISOString(), missions: lignes };
}

/**
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  return { 'demo-swipe.json': buildDemoSwipe(contexte.now) };
}

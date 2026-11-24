/**
 * Lot 5, T8 — présences de l'établissement démo (`docs/mobile-swift/LOT5_PLAN.md` §2.10 et §3 T8, fixture
 * `demo-etab-presences.json`), écrites par `export-demo-fixtures.mjs` (job « Cœur » : sortie diffée).
 *
 * Lignes `presences` de l'établissement démo (colonnes décodées par `PresenceEtab` : ni position, ni
 * `coherence_incidents`, ni durée servie, ni montant) avec l'embed `missions` **dérivé** de `demo-etab-missions.json`,
 * et créneaux EFFECTIF de `mission_creneaux` :
 *   M4 (nuit en cours) et M6 (mission active) : segments **dérivés** du dernier état enregistré de
 *     `demo-etab-pointage.json` (T7) — M4 a un segment ouvert depuis le scan d'arrivée (clôture rétroactive), M6 a son
 *     premier créneau pointé et attend le second (« en cours ») ;
 *   M7 (terminée) : pointée dans le périmètre → « à valider », seule éligible à la validation en lot ;
 *   M8 (terminée) : pointée hors périmètre (distance servie, alerte « hors zone ») → « à valider » et « alertes »,
 *     exclue du lot, contestable ;
 *   M11 (terminée, salariée, attribuée) n'a aucune présence : alerte « Missions terminées sans pointage », **dérivée**
 *     par la gateway démo des missions de `demo-etab-missions.json`.
 * Les créneaux PREVISIONNEL restent ceux de `demo-etab-missions.json` (une seule source pour le planning). Aucune
 * présence validée au départ : valider, valider en lot, contester et clôturer vivent dans la session démo (acteur de la
 * gateway), relus comme sur le serveur. Aucune donnée réelle.
 */

/** Instant ISO décalé de `minutes` minutes. */
function decaler(iso, minutes) {
  return new Date(new Date(iso).getTime() + minutes * 60_000).toISOString();
}

/**
 * @param {{ now: Date, missions: { missions: object[], creneaux: object[] }, pointage: { scenarios: object[] } }} entree
 *   `missions` : fixture `demo-etab-missions.json` ; `pointage` : fixture `demo-etab-pointage.json`.
 */
export function buildDemoEtabPresences({ now, missions, pointage }) {
  const mission = (id) => {
    const ligne = missions.missions.find(m => m.id === id);
    if (!ligne) throw new Error(`Mission ${id} absente de demo-etab-missions.json`);
    return ligne;
  };
  const creneau = (missionId, rang) => {
    const ligne = missions.creneaux.find(c => c.id === `${missionId}-slot-${rang}`);
    if (!ligne) throw new Error(`Créneau ${rang} de ${missionId} absent de demo-etab-missions.json`);
    return ligne;
  };
  const effectif = (missionId, rang, debut, fin) => ({
    id: `${missionId}-effectif-${rang}`, mission_id: missionId, debut, fin, est_pause: false, type_creneau: 'EFFECTIF',
  });
  /** Segments du dernier état enregistré de `fn_etat_pointage_mission` (T7) : la même histoire, vue des présences. */
  const depuisPointage = (missionId) => {
    const scenario = pointage.scenarios.find(s => s.mission_id === missionId);
    const etat = scenario?.etats.at(-1)?.etat;
    if (!etat || etat.segments.length === 0) throw new Error(`Aucun segment enregistré pour ${missionId} dans demo-etab-pointage.json`);
    // Même ligne `mission_creneaux` : l'identifiant du segment servi par l'état du pointage est conservé.
    return etat.segments.map((segment, index) => ({ ...effectif(missionId, index + 1, segment.debut, segment.fin), id: segment.id }));
  };
  const presence = (rang, champs = {}) => {
    const id = `demo-etab-m${String(rang).padStart(2, '0')}`;
    const m = mission(id);
    if (!m.soignant_assigne_id) throw new Error(`${id} n'a pas de soignant assigné`);
    return {
      id: `demo-etab-p${String(rang).padStart(2, '0')}`,
      mission_id: id,
      soignant_id: m.soignant_assigne_id,
      distance_etablissement_m: champs.distance ?? 35,
      perimetre_gps_valide: champs.perimetre ?? true,
      alerte_teleportation: false,
      arrivee_mock_detected: false,
      depart_mock_detected: false,
      valide_par_etablissement: false,
      valide_le: null,
      motif_litige: null,
      missions: {
        id, intitule: m.intitule, service: m.service, debut_le: m.debut_le, fin_le: m.fin_le,
        nb_creneaux: m.nb_creneaux, etablissement_id: m.etablissement_id,
      },
    };
  };
  const m4 = depuisPointage('demo-etab-m04');
  const m6 = depuisPointage('demo-etab-m06');
  if (m4.at(-1).fin !== null) throw new Error('M4 doit garder un segment ouvert (clôture rétroactive de la démo)');
  if (m6.some(s => s.fin === null)) throw new Error('M6 ne doit avoir aucun segment ouvert (T7 : hors créneau)');
  const m7 = creneau('demo-etab-m07', 1);
  const m8 = creneau('demo-etab-m08', 1);
  for (const [nom, c] of [['M7', m7], ['M8', m8]]) {
    if (!(new Date(c.fin) < now)) throw new Error(`${nom} doit être terminée à l'horloge fixée du monde démo`);
  }
  return {
    fixed_now: now.toISOString(),
    // Ordre du web : arrivée pointée la plus récente d'abord (`PresencesEtablissement.tsx` l.81).
    presences: [
      presence(4),
      presence(6),
      presence(7),
      presence(8, { distance: 420, perimetre: false }),
    ],
    effectifs: [
      ...m4,
      ...m6,
      effectif('demo-etab-m07', 1, decaler(m7.debut, 1), decaler(m7.fin, 3)),
      effectif('demo-etab-m08', 1, decaler(m8.debut, 4), decaler(m8.fin, -2)),
    ],
  };
}

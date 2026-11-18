/**
 * Lot 5, T5 — missions de l'établissement démo (`docs/mobile-swift/LOT5_PLAN.md` §2.10, fixture
 * `demo-etab-missions.json`), écrites par `export-demo-fixtures.mjs` (job « Cœur » : sortie diffée).
 *
 * Les onze missions M1…M11 du blueprint, toutes à l'établissement démo (`demo-etab-1`), dates relatives à
 * l'horloge fixée du monde démo (créneaux en UTC, novembre = UTC+1 à Paris) :
 *   M1 OUVERTE candidature (3 candidatures en attente), M2 OUVERTE premier arrivé urgente, M3 OUVERTE planning
 *   incomplet (`nb_creneaux` 2, 1 créneau), M4 ASSIGNEE de nuit (2026-11-01T23:00Z → 2026-11-02T07:00Z), M5 ASSIGNEE
 *   (contrat à signer), M6 EN_COURS sur deux créneaux, M7 et M8 TERMINEE (présences à valider / hors zone, T8),
 *   M9 OUVERTE « tous profils » et M10 OUVERTE `MEDECIN` (acceptation renvoyée au web, D25), M11 TERMINEE sans
 *   pointage (T8).
 * Lignes `missions` réduites aux colonnes décodées par `EtabMissionResume` (aucun montant, D15) ; créneaux
 * PREVISIONNEL de `mission_creneaux` ; candidatures réduites à ce que lit la liste (`mission_id`, `statut`,
 * `cree_le`) : les compteurs en sont **dérivés** par la gateway démo, jamais saisis (T6 complète ces lignes) ;
 * soignants réduits aux clés décodées de `fn_soignant_pour_etablissement` (jamais `note_moyenne`,
 * `nb_evaluations`, `type_exercice`, `internat`). Aucune donnée réelle.
 */

/** Instant UTC `jours` jours après `now`, à `heure`:00 UTC. */
function instant(now, jours, heure) {
  const day = new Date(now);
  day.setUTCDate(day.getUTCDate() + jours);
  day.setUTCHours(heure, 0, 0, 0);
  return day.toISOString();
}

/**
 * @param {{ now: Date, etablissementId: string, soignantPrincipal: object, creeLe: string }} entree
 *   `soignantPrincipal` : soignant fictif du monde soignant (`demo-soignant`), projeté sur les clés décodées.
 */
export function buildDemoEtabMissions({ now, etablissementId, soignantPrincipal }) {
  const soignant2 = {
    id: 'demo-soignant-etab-2',
    prenom: 'Alex',
    nom: 'Fictif',
    nom_anonymise: false,
    profession: 'AS',
    telephone: null,
    numero_rpps: null,
    score_fiabilite: 74,
    total_missions_terminees: 6,
  };
  const s1 = soignantPrincipal.id;
  const s2 = soignant2.id;
  const missions = [];
  const creneaux = [];
  const ajouter = (rang, champs, plages) => {
    const id = `demo-etab-m${String(rang).padStart(2, '0')}`;
    const lignes = plages.map(([jours, debutH, dureeH], index) => {
      const debut = instant(now, jours, debutH);
      const fin = new Date(new Date(debut).getTime() + dureeH * 3_600_000).toISOString();
      return { id: `${id}-slot-${index + 1}`, mission_id: id, debut, fin, est_pause: false, type_creneau: 'PREVISIONNEL' };
    });
    creneaux.push(...lignes);
    missions.push({
      id,
      etablissement_id: etablissementId,
      intitule: champs.intitule,
      description: 'Mission entièrement fictive de l’établissement de démonstration. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
      service: champs.service,
      profession_requise: champs.profession ?? 'IDE',
      debut_le: lignes[0].debut,
      fin_le: lignes[lignes.length - 1].fin,
      nb_creneaux: champs.nbCreneaux ?? lignes.length,
      statut: champs.statut,
      est_urgente: champs.niveauUrgence > 0,
      niveau_urgence: champs.niveauUrgence ?? 0,
      soignant_assigne_id: champs.soignant ?? null,
      mode_attribution: champs.mode ?? 'CANDIDATURE',
      type_contrat_recherche: champs.contrat ?? 'SALARIE',
      cree_le: instant(now, champs.creeJours ?? -4, 8),
    });
  };
  ajouter(1, { intitule: 'Démonstration · Candidatures à examiner', service: 'Médecine polyvalente', statut: 'OUVERTE', creeJours: -3 }, [[3, 6, 12]]);
  ajouter(2, { intitule: 'Démonstration · Renfort urgent', service: 'Soins de suite', profession: 'AS', statut: 'OUVERTE', mode: 'PREMIER_ARRIVE', niveauUrgence: 2, creeJours: -1 }, [[5, 6, 8]]);
  ajouter(3, { intitule: 'Démonstration · Planning à compléter', service: 'Médecine polyvalente', statut: 'OUVERTE', nbCreneaux: 2, creeJours: -2 }, [[7, 6, 8]]);
  ajouter(4, { intitule: 'Démonstration · Nuit en cours', service: 'Médecine polyvalente', statut: 'ASSIGNEE', soignant: s1, creeJours: -9 }, [[-1, 23, 8]]);
  ajouter(5, { intitule: 'Démonstration · Contrat à signer', service: 'Soins de suite', profession: 'AS', statut: 'ASSIGNEE', soignant: s2, creeJours: -6 }, [[2, 6, 8]]);
  ajouter(6, { intitule: 'Démonstration · Mission active', service: 'Soins de suite', statut: 'EN_COURS', soignant: s1, creeJours: -12 }, [[-1, 6, 8], [1, 6, 8]]);
  ajouter(7, { intitule: 'Démonstration · Présence à valider', service: 'Médecine polyvalente', statut: 'TERMINEE', soignant: s1, creeJours: -14 }, [[-2, 6, 8]]);
  ajouter(8, { intitule: 'Démonstration · Présence hors zone', service: 'Soins de suite', profession: 'AS', statut: 'TERMINEE', soignant: s2, creeJours: -15 }, [[-3, 6, 8]]);
  ajouter(9, { intitule: 'Démonstration · Tous profils', service: 'Consultations', statut: 'OUVERTE', contrat: 'TOUS', creeJours: -2 }, [[9, 6, 8]]);
  ajouter(10, { intitule: 'Démonstration · Médecin de garde', service: 'Urgences', profession: 'MEDECIN', statut: 'OUVERTE', creeJours: -1 }, [[10, 6, 12]]);
  ajouter(11, { intitule: 'Démonstration · Terminée sans pointage', service: 'Médecine polyvalente', statut: 'TERMINEE', soignant: s2, creeJours: -20 }, [[-6, 6, 8]]);
  // Ordre du web : `debut_le` décroissant (l.88).
  missions.sort((a, b) => b.debut_le.localeCompare(a.debut_le) || a.id.localeCompare(b.id));

  const candidature = (missionId, rang, heuresAvant) => ({
    id: `${missionId}-cand-${rang}`,
    mission_id: missionId,
    statut: 'EN_ATTENTE',
    cree_le: new Date(now.getTime() - heuresAvant * 3_600_000).toISOString(),
  });
  const candidatures = [
    candidature('demo-etab-m01', 1, 30), candidature('demo-etab-m01', 2, 20), candidature('demo-etab-m01', 3, 5),
    candidature('demo-etab-m03', 1, 12),
    candidature('demo-etab-m09', 1, 9),
    candidature('demo-etab-m10', 1, 4),
  ];

  return {
    fixed_now: now.toISOString(),
    etablissement_id: etablissementId,
    missions,
    creneaux,
    candidatures,
    soignants: [soignantPrincipal, soignant2],
  };
}

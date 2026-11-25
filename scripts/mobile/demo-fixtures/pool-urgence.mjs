/**
 * Fixtures démo du domaine « pool-urgence » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T11.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais export-demo-fixtures.mjs ni
 * les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier (`demo-<nom>.json`) → valeur JSON, ou
 * `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-pool-urgence.json`, lu par `DemoPoolUrgenceGateway` (et `DemoCandidatureGateway.missionsDesFixtures`) :
 * - `etat` : pool inactif, rayon 30 km (`COALESCE(urgence_rayon_km, 30)` de fn_pool_urgence_missions_pour_soignant),
 *   SMS refusés ;
 * - `missions` : missions urgentes servies, identifiant et distance seulement (la ligne `missions` et ses créneaux sont
 *   ceux de `demo-missions.json`, même source que la validation du planning de `DemoCandidatureGateway`) : deux missions
 *   à moins de 15 km, une à 22 km (sortie du pool quand le rayon passe à 15 km) ;
 * - `missions_supplementaires` : une mission urgente propre au pool, contrat `TOUS` (seule mission démo dont
 *   l'acceptation rapide demande un choix de contrat au profil MIXTE : renvoi au détail de la mission, jamais rejoué).
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const heure = 3_600_000;
  const iso = (decalageHeures) => new Date(contexte.now.getTime() + decalageHeures * heure).toISOString();
  const id = 'demo-mission-urgence-tous';
  return {
    'demo-pool-urgence.json': {
      fixed_now: contexte.now.toISOString(),
      etat: { pool_actif: false, rayon_km: 30, sms_opt_in: false },
      missions: [
        { mission_id: 'demo-mission-001', distance_km: 4.2 },
        { mission_id: id, distance_km: 8 },
        { mission_id: 'demo-mission-016', distance_km: 12.5 },
        { mission_id: 'demo-mission-021', distance_km: 22 },
      ],
      missions_supplementaires: [
        {
          id,
          intitule: 'Démonstration · Urgence de nuit (contrat au choix)',
          description: 'Mission entièrement fictive pour découvrir le pool urgence. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
          service: 'Médecine polyvalente',
          profession_requise: 'IDE',
          specialite_medicale_requise: null,
          accepte_non_specialises: null,
          debut_le: iso(24 * 3 + 7),
          fin_le: iso(24 * 3 + 15),
          duree_heures: 8,
          nb_creneaux: 1,
          taux_horaire_base: 27,
          taux_rist_plafonne: null,
          rist_plafond_applique: false,
          total_brut: null,
          net_a_payer: null,
          est_urgente: true,
          niveau_urgence: 2,
          statut: 'OUVERTE',
          etablissement_id: 'demo-etab-2',
          type_contrat_recherche: 'TOUS',
          boostee_le: null,
          mode_remuneration: 'HORAIRE',
          retrocession_pct: null,
          mode_attribution: 'PREMIER_ARRIVE',
          presence_confirmee_le: null,
          soignant_assigne_id: null,
          creneaux: [
            {
              id: `${id}-slot-1`,
              mission_id: id,
              debut: iso(24 * 3 + 7),
              fin: iso(24 * 3 + 15),
              est_pause: false,
              type_creneau: 'PREVISIONNEL',
            },
          ],
        },
      ],
    },
  };
}

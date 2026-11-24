/**
 * Fixtures démo du domaine « score » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T9.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-score.json`, lu par `DemoScoreGateway`, aux formats exacts du serveur (supabase/schema/public.sql) :
 *   - `breakdown` : ligne `scoring_breakdown` rendue par `fn_mon_breakdown_actuel` (`to_jsonb(b.*)`) — cinq composantes
 *     actives, une inactive (réactivité, poids redistribué), un malus d'absence ;
 *   - `soignant` : colonnes `soignants` lues par la page (`total_missions_terminees`, `score_fiabilite`, `niveau`,
 *     `en_periode_probatoire`) ;
 *   - `evolution` : tableau de `fn_evolution_score_soignant(6)`, six points, un par mois ;
 *   - `evenements` : réponse de `fn_mes_evenements_score`, **sous la clé `events`** (correction 16 du plan : le web lit
 *     `evenements` et n'affiche rien) — trois événements, un seul contestable ; `contestable` est la valeur calculée par
 *     le serveur (`contestable AND decision_admin IS NULL AND reclamation_id IS NULL`).
 * Les notations reçues de « Mon score » (`fn_lister_notations_recues`) sont celles de `demo-evaluations.json` : une seule
 * source de notes publiées dans le monde démo.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const jour = 86_400_000;
  const iso = (decalageJours) => new Date(contexte.now.getTime() + decalageJours * jour).toISOString();
  /** Premier jour, midi UTC, du mois situé `recul` mois avant l'horloge. */
  const mois = (recul) => {
    const date = new Date(Date.UTC(contexte.now.getUTCFullYear(), contexte.now.getUTCMonth() - recul, 1, 12));
    return { label: date.toISOString().slice(0, 7), cree_le: date.toISOString() };
  };
  const evolution = [
    { recul: 5, score: 64, niveau: 'ARGENT' },
    { recul: 4, score: 66.5, niveau: 'ARGENT' },
    { recul: 3, score: 70.2, niveau: 'OR' },
    { recul: 2, score: 74, niveau: 'OR' },
    { recul: 1, score: 77.6, niveau: 'OR' },
    { recul: 0, score: 72.6, niveau: 'OR' },
  ].map(({ recul, score, niveau }) => ({ mois: mois(recul).label, score, niveau, cree_le: mois(recul).cree_le }));

  return {
    'demo-score.json': {
      fixed_now: contexte.now.toISOString(),
      breakdown: {
        id: 'demo-breakdown-001',
        soignant_id: 'demo-soignant',
        score_total: 72.6,
        niveau: 'OR',
        en_periode_probatoire: false,
        notation_etab_soignant_pct: 88.8,
        notation_etab_soignant_poids: 38.9,
        presentisme_pct: 95,
        presentisme_poids: 22.2,
        ponctualite_pct: 72,
        ponctualite_poids: 16.7,
        reactivite_pct: null,
        reactivite_poids: null,
        anciennete_volume_pct: 40,
        anciennete_volume_poids: 11.1,
        notation_soignant_etab_pct: 50,
        notation_soignant_etab_poids: 11.1,
        litiges_malus: 0,
        absence_sans_prevenir_malus: -5,
        bonus_super_actif: 0,
        composantes_inactives_json: [{ composante: 'reactivite', poids_initial: 10 }],
        composantes_actives_count: 5,
        redistribution_json: { facteur: 1.111, total_poids_actifs: 90 },
        raison_recalcul: 'MISSION_TERMINEE',
        cree_le: mois(0).cree_le,
      },
      soignant: {
        total_missions_terminees: 12,
        score_fiabilite: 72.6,
        niveau: 'OR',
        en_periode_probatoire: false,
      },
      evolution,
      evenements: {
        success: true,
        type: 'SOIGNANT',
        events: [
          {
            id: 'demo-evenement-001',
            type_evenement: 'ANNULATION_12_24H',
            points: -5,
            points_corriges: null,
            motif: 'Annulation entre 12 h et 24 h avant le début de la mission',
            contestable: true,
            decision_admin: null,
            cree_le: iso(-10),
            mission_id: 'demo-mission-notee-005',
          },
          {
            id: 'demo-evenement-002',
            type_evenement: 'LITIGE_TORT_RECONNU',
            points: -8,
            points_corriges: -4,
            motif: 'Litige clos : tort partagé',
            contestable: false,
            decision_admin: 'REDUIRE',
            cree_le: iso(-45),
            mission_id: null,
          },
          {
            id: 'demo-evenement-003',
            type_evenement: 'BONUS_FIDELITE',
            points: 5,
            points_corriges: null,
            motif: 'Dix missions terminées sans annulation',
            contestable: false,
            decision_admin: null,
            cree_le: iso(-80),
            mission_id: null,
          },
        ],
      },
    },
  };
}

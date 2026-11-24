/**
 * Fixtures démo du domaine « parrainage » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T6.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-parrainage.json`, lu par `DemoParrainageGateway` :
 * - `soignant` : colonnes `code_parrainage, badge_ambassadeur` de la ligne `soignants` du compte démo ;
 * - `mes_parrainages` : réponse de `fn_obtenir_mes_parrainages` (supabase/schema/public.sql, mêmes clés, filleuls
 *   triés par `cree_le` décroissant, `mon_parrain` JSON `null`) : trois filleuls fictifs, un par statut affiché
 *   (première mission faite, en attente, inscrit) ;
 * - `parrains` : codes de parrains fictifs acceptés par l'application démo (code → prénom) ; tout autre code est
 *   refusé comme par la RPC (« Code de parrainage invalide »).
 * Aucune donnée réelle, aucun montant affiché par l'écran natif (bloc T6-HS).
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const jour = 86_400_000;
  const iso = (decalageJours) => new Date(contexte.now.getTime() + decalageJours * jour).toISOString();
  const filleul = (n, prenom, statut, creeLe, premiereMission, gmv) => ({
    id: `demo-parrainage-00${n}`,
    filleul_id: `demo-filleul-00${n}`,
    prenom,
    statut,
    cree_le: creeLe,
    filleul_active_le: premiereMission,
    commission_cumulee_filleul: 0,
    gmv_cumule_filleul: gmv,
    reste_gmv_avant_prime: Math.max(0, 500 - gmv),
    seuil_gmv: 500,
    seuil_atteint: false,
    prime_versee_le: null,
    premiere_mission_le: premiereMission,
    bonus_heures: 0,
  });
  return {
    'demo-parrainage.json': {
      fixed_now: contexte.now.toISOString(),
      soignant: { code_parrainage: 'JOLENE-DEMO', badge_ambassadeur: false },
      mes_parrainages: {
        filleuls: [
          filleul(3, 'Lina', 'INSCRIT', iso(-2), null, 0),
          filleul(2, 'Hugo', 'EN_ATTENTE', iso(-6), null, 0),
          filleul(1, 'Inès', 'VALIDE', iso(-20), iso(-12), 180),
        ],
        total_gains_eur: 0,
        nb_primes_versees: 0,
        prime_eur: 25,
        seuil_gmv_eur: 500,
        mon_parrain: null,
      },
      parrains: { 'DEMO-XYZ': 'Camille' },
    },
  };
}

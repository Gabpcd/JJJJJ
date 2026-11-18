/**
 * Fixtures démo du domaine « filtres » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T4.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-filtres.json` : deux recherches sauvegardées du compte démo (`demo-soignant`), au format exact de
 * `fn_lister_mes_filtres_sauvegardes` (supabase/schema/public.sql, tri `mis_a_jour_le` décroissant), lues par
 * `DemoFiltresGateway` : une recherche de nuit en alerte toutes les heures (trois résultats au dernier passage), une
 * recherche de week-end en CDD sans alerte. Critères au format `CriteresAlerteMissions`
 * (src/lib/alertes-recherche-missions.ts, sept clés camelCase), aucune identique aux critères initiaux d'Explorer :
 * la première alerte rapide du compte démo crée une recherche, la seconde la réutilise.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const heure = 3_600_000;
  const iso = (decalageHeures) => new Date(contexte.now.getTime() + decalageHeures * heure).toISOString();
  return {
    'demo-filtres.json': {
      fixed_now: contexte.now.toISOString(),
      filtres_sauvegardes: [
        {
          id: 'demo-recherche-001',
          nom: 'Nuits autour de Paris',
          audience: 'SOIGNANT_RECHERCHE_MISSIONS',
          filtres: {
            profession: '', rayonKm: 30, tauxMin: 0, typeContrat: 'TOUS', urgentesOnly: false, horaire: 'NUIT',
            villeRecherche: '',
          },
          alerte_active: true,
          frequence_alerte: 'IMMEDIATE',
          dernier_check_le: iso(-6),
          nb_resultats_dernier_check: 3,
          cree_le: iso(-24 * 9),
          mis_a_jour_le: iso(-24 * 2),
        },
        {
          id: 'demo-recherche-002',
          nom: 'Week-ends en CDD',
          audience: 'SOIGNANT_RECHERCHE_MISSIONS',
          filtres: {
            profession: '', rayonKm: 50, tauxMin: 30, typeContrat: 'CDD', urgentesOnly: false, horaire: 'WEEKEND',
            villeRecherche: '',
          },
          alerte_active: false,
          frequence_alerte: 'QUOTIDIENNE',
          dernier_check_le: iso(-24 * 4),
          nb_resultats_dernier_check: 0,
          cree_le: iso(-24 * 12),
          mis_a_jour_le: iso(-24 * 4),
        },
      ],
    },
  };
}

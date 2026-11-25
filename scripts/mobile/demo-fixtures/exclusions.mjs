/**
 * Fixtures démo du domaine « exclusions » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T11.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais export-demo-fixtures.mjs ni
 * les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier (`demo-<nom>.json`) → valeur JSON, ou
 * `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-exclusions.json`, lu par `DemoExclusionsGateway` :
 * - `envoyees` : une ligne PostgREST `exclusions` posée par le compte démo (colonnes de ExclusionsSoignant.tsx l.45),
 *   envers un établissement fictif qui ne publie aucune mission démo (Explorer reste inchangé) ;
 * - `recues` : une ligne au format de `fn_mes_exclusions_recues` (supabase/schema/public.sql) ;
 * - `noms` : nom de l'établissement exclu, comme `fn_etablissements_safe`.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const jour = 24 * 3_600_000;
  const iso = (decalageJours) => new Date(contexte.now.getTime() + decalageJours * jour).toISOString();
  return {
    'demo-exclusions.json': {
      fixed_now: contexte.now.toISOString(),
      envoyees: [
        {
          id: 'demo-exclusion-001',
          exclu_id: 'demo-etab-ancien',
          exclu_par: 'demo-soignant',
          motif: 'Planning modifié trop souvent',
          type_exclu_par: 'SOIGNANT',
          cree_le: iso(-20),
        },
      ],
      recues: [
        {
          id: 'demo-exclusion-recue-001',
          exclu_par: 'demo-etab-tilleuls',
          type_exclu_par: 'ETABLISSEMENT',
          motif: null,
          etablissement_nom: 'Clinique fictive des Tilleuls',
          cree_le: iso(-45),
        },
      ],
      noms: { 'demo-etab-ancien': 'Résidence fictive des Acacias' },
    },
  };
}

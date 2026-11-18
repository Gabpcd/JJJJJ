/**
 * Fixtures démo du domaine « swipe » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T3a.
 *
 * Module vide posé par L4-T1c : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  void contexte;
  return {};
}

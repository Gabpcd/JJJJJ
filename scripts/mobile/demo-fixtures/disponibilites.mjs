/**
 * Fixtures démo du domaine « disponibilites » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T5.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-disponibilites.json` : trois créneaux posés par le compte démo (`demo-soignant`), au format exact des lignes
 * PostgREST de `disponibilites_soignant` lues par le web (`select('jour, creneau')`, src/pages/MesDisponibilites.tsx),
 * lues par `DemoDisponibilitesGateway`. Les jours sont dérivés de l'horloge (lendemain en journée, J+3 de nuit, J+12 en
 * journée) : tous dans la grille de quatre semaines, aucun passé. La nuit du lendemain reste libre : c'est la case que
 * bascule l'XCUITest (`dispo-2026-11-03-NUIT`).
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const jour = (decalageJours) => new Date(contexte.now.getTime() + decalageJours * 86_400_000).toISOString().slice(0, 10);
  return {
    'demo-disponibilites.json': {
      fixed_now: contexte.now.toISOString(),
      disponibilites_soignant: [
        { jour: jour(1), creneau: 'JOURNEE' },
        { jour: jour(3), creneau: 'NUIT' },
        { jour: jour(12), creneau: 'JOURNEE' },
      ],
    },
  };
}

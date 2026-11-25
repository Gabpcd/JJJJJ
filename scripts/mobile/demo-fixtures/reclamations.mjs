/**
 * Fixtures démo du domaine « reclamations » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T8.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-reclamations.json` : deux réclamations générales du compte démo (`demo-soignant`), aux colonnes lues par le web
 * et par `SupabaseReclamationsGateway` (`id, categorie, sujet, details, statut, reponse_admin, cree_le, traite_le`),
 * triées par `cree_le` décroissant : une `EN_ATTENTE` sans réponse, une `RESOLUE` avec la réponse de l'équipe. Aucun
 * montant, aucune donnée de santé.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const heure = 3_600_000;
  const iso = (decalageHeures) => new Date(contexte.now.getTime() + decalageHeures * heure).toISOString();
  return {
    'demo-reclamations.json': {
      fixed_now: contexte.now.toISOString(),
      reclamations: [
        {
          id: 'demo-reclamation-001',
          categorie: 'TECHNIQUE',
          sujet: 'Démonstration · Notification reçue en double',
          details: 'Démonstration · La même notification est arrivée deux fois sur mon téléphone.',
          statut: 'EN_ATTENTE',
          reponse_admin: null,
          cree_le: iso(-30),
          traite_le: null,
        },
        {
          id: 'demo-reclamation-002',
          categorie: 'MISSION',
          sujet: 'Démonstration · Horaire affiché différent du planning',
          details: 'Démonstration · L’horaire de la mission ne correspondait pas au planning reçu.',
          statut: 'RESOLUE',
          reponse_admin: 'Démonstration · L’horaire a été corrigé, merci de votre signalement.',
          cree_le: iso(-24 * 12),
          traite_le: iso(-24 * 10),
        },
      ],
    },
  };
}

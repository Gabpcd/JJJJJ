/**
 * Fixtures démo du domaine « evaluations » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T9.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-evaluations.json` : réponse de `fn_mes_notations_recues_avec_stats` (supabase/schema/public.sql) du compte démo
 * (`demo-soignant`), sans filtre, lue par `DemoEvaluationsGateway` : quatre notations PUBLIÉES (le filtre de
 * visibilité est celui du serveur : une note non publiée n'existe pas dans la réponse, donc pas dans la fixture), une
 * déjà signalée. Statistiques, évolution et établissements calculés ici comme le fait la RPC (ce module joue le
 * serveur), jamais par l'app :
 *   - `note_moyenne` d'une notation : ROUND((c1 + c2 + c3 + c4) / 4.0, 1) ;
 *   - `stats` : toutes périodes, sans filtre — moyenne des notes, total, part des notations dont la somme vaut 19 ou 20 ;
 *   - `evolution_6m` : moyenne par mois des notations de moins de six mois ;
 *   - `etabs_disponibles` : établissements ayant noté.
 * La moyenne globale (4,4) n'est la moyenne d'aucune page filtrée : un recalcul côté app se verrait.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const jour = 86_400_000;
  const iso = (decalageJours) => new Date(contexte.now.getTime() + decalageJours * jour).toISOString();
  /** ROUND(x, 1) de PostgreSQL sur un numeric exact : demi vers l'extérieur (4,25 → 4,3). */
  const arrondi1 = (valeur) => Math.round(valeur * 10 + 1e-9) / 10;

  const etablissements = {
    'demo-etab-1': 'Établissement fictif République',
    'demo-etab-2': 'Établissement fictif des Lilas',
    'demo-etab-3': 'Cabinet fictif du Parc',
  };
  const brutes = [
    { n: 1, etab: 'demo-etab-1', intitule: 'Remplacement IDE de jour', criteres: [5, 5, 5, 5], age: 5, signale: false,
      commentaire: 'Très professionnelle, équipe ravie.' },
    { n: 2, etab: 'demo-etab-2', intitule: 'Renfort IDE de nuit', criteres: [4, 5, 4, 5], age: 40, signale: false,
      commentaire: null },
    { n: 3, etab: 'demo-etab-1', intitule: 'Remplacement IDE week-end', criteres: [4, 4, 4, 4], age: 100, signale: false,
      commentaire: 'Ponctuelle et à l’écoute.' },
    { n: 4, etab: 'demo-etab-3', intitule: 'Vacation IDE en cabinet', criteres: [4, 4, 5, 4], age: 200, signale: true,
      commentaire: 'Mission écourtée.' },
  ];
  const moyenne = (criteres) => criteres.reduce((somme, c) => somme + c, 0) / 4;
  const notations = brutes.map((b) => ({
    id: `demo-notation-00${b.n}`,
    mission_id: `demo-mission-notee-00${b.n}`,
    mission_intitule: b.intitule,
    mission_fin_le: iso(-b.age - 2),
    etablissement_id: b.etab,
    etablissement_nom: etablissements[b.etab],
    critere_1: b.criteres[0],
    critere_2: b.criteres[1],
    critere_3: b.criteres[2],
    critere_4: b.criteres[3],
    note_moyenne: arrondi1(moyenne(b.criteres)),
    commentaire: b.commentaire,
    signale: b.signale,
    cree_le: iso(-b.age),
  }));

  const moyennes = brutes.map((b) => moyenne(b.criteres));
  const stats = {
    note_moyenne_globale: arrondi1(moyennes.reduce((somme, m) => somme + m, 0) / moyennes.length),
    total_evaluations: brutes.length,
    pct_5_etoiles: arrondi1((100 * brutes.filter((b) => b.criteres.reduce((s, c) => s + c, 0) >= 19).length) / brutes.length),
  };

  const sixMois = new Date(contexte.now);
  sixMois.setUTCMonth(sixMois.getUTCMonth() - 6);
  const parMois = new Map();
  for (const b of brutes) {
    const cree = new Date(contexte.now.getTime() - b.age * jour);
    if (cree <= sixMois) continue;
    const mois = cree.toISOString().slice(0, 7);
    parMois.set(mois, [...(parMois.get(mois) ?? []), moyenne(b.criteres)]);
  }
  const evolution = [...parMois.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([mois, notes]) => ({
    mois,
    note_moyenne: arrondi1(notes.reduce((somme, m) => somme + m, 0) / notes.length),
    nb: notes.length,
  }));

  const etabsDisponibles = [...new Set(brutes.map((b) => b.etab))].sort().map((id) => ({ id, nom: etablissements[id] }));

  return {
    'demo-evaluations.json': {
      fixed_now: contexte.now.toISOString(),
      reponse: {
        success: true,
        total: notations.length,
        limit: 20,
        offset: 0,
        notations,
        stats,
        evolution_6m: evolution,
        etabs_disponibles: etabsDisponibles,
      },
    },
  };
}

/**
 * Fixtures démo du domaine « litiges » du lot 4 (docs/mobile-swift/LOT4_PLAN.md §2.7), remplies par T8.
 *
 * Module du domaine : chaque tranche du lot 4 n'écrit que le module de son domaine, jamais
 * export-demo-fixtures.mjs ni les modules des autres (§4). Même contrat que buildFixtures() : nom de fichier
 * (`demo-<nom>.json`) → valeur JSON, ou `{ brut }` pour un texte tel quel. Horloge fixée : contexte.now.
 *
 * `demo-litiges.json` : trois litiges du compte démo (`demo-soignant`), au format de la lecture PostgREST de
 * `SupabaseLitigesGateway` (`litiges` par colonnes explicites, jamais `*`, mission jointe `missions(id,intitule,debut_le)`),
 * triés par `cree_le` décroissant : un `OUVERT`, un `EN_MEDIATION`, un `RESOLU_ACCORD_PARTIES` (son `resolution` est le
 * texte de clôture du serveur). Aucun montant. Le nom de l'établissement n'y figure pas : `DemoLitigesGateway` le lit
 * dans `demo-etablissements.json`, comme la gateway réelle le lit par `fn_etablissements_safe`.
 *
 * `demo-litige-fil.json` : messages de ces litiges (`messages_litige`, colonnes `id, litige_id, auteur_id, type_auteur,
 * contenu, cree_le`), ordre chronologique : le soignant démo, un établissement fictif et l'équipe Jolene (`ADMIN`).
 *
 * Les deux missions proposées à l'ouverture d'un litige ne sont pas ici : ce sont les missions `TERMINEE` de
 * `demo-mes-missions.json` (une seule source, lue par `DemoLitigesGateway`), aucune n'ayant de litige.
 *
 * @param {{ now: Date }} contexte
 * @returns {Record<string, unknown>}
 */
export function fixtures(contexte) {
  const heure = 3_600_000;
  const iso = (decalageHeures) => new Date(contexte.now.getTime() + decalageHeures * heure).toISOString();
  const fixedNow = contexte.now.toISOString();
  const litige = (numero, etablissement, statut, motif, creeLe, debutMission, resolution = null) => ({
    id: `demo-litige-00${numero}`,
    mission_id: `demo-litige-mission-00${numero}`,
    etablissement_id: `demo-etab-${etablissement}`,
    statut,
    type_litige: 'AUTRE',
    motif,
    resolution,
    cree_le: creeLe,
    missions: {
      id: `demo-litige-mission-00${numero}`,
      intitule: `Démonstration · Mission en litige ${numero}`,
      debut_le: debutMission,
    },
  });
  const message = (numero, litigeNumero, auteur, type, contenu, creeLe) => ({
    id: `demo-litige-message-00${numero}`,
    litige_id: `demo-litige-00${litigeNumero}`,
    auteur_id: auteur,
    type_auteur: type,
    contenu,
    cree_le: creeLe,
  });
  return {
    'demo-litiges.json': {
      fixed_now: fixedNow,
      litiges: [
        litige(1, 1, 'OUVERT', 'Démonstration · Désaccord sur le poste occupé pendant la mission.', iso(-20), iso(-24 * 3 + 7)),
        litige(2, 2, 'EN_MEDIATION', 'Démonstration · Désaccord sur l’heure de fin de la mission.', iso(-24 * 6), iso(-24 * 9 + 7)),
        litige(3, 3, 'RESOLU_ACCORD_PARTIES', 'Démonstration · Désaccord sur la durée de la pause.', iso(-24 * 20),
          iso(-24 * 24 + 7), 'Démonstration · Accord trouvé entre les parties.'),
      ],
    },
    'demo-litige-fil.json': {
      fixed_now: fixedNow,
      messages: [
        message(1, 3, 'demo-etablissement-3', 'ETABLISSEMENT', 'Démonstration · Nous confirmons la durée de pause retenue.', iso(-24 * 19)),
        message(2, 2, 'demo-jolene', 'ADMIN', 'Démonstration · L’équipe Jolene suit ce dossier.', iso(-24 * 5)),
        message(3, 1, 'demo-soignant', 'SOIGNANT', 'Démonstration · Bonjour, je souhaite revenir sur le poste occupé.', iso(-19)),
        message(4, 1, 'demo-etablissement-1', 'ETABLISSEMENT', 'Démonstration · Bonjour, nous regardons votre demande.', iso(-18)),
      ],
    },
  };
}

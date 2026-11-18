/**
 * Fixtures démo du lot 4, un module par domaine (L4-T1c, docs/mobile-swift/LOT4_PLAN.md §2.1 et §2.7) : les onze
 * tranches parallèles de la vague 2 écrivent chacune le module de leur domaine, jamais export-demo-fixtures.mjs.
 * Assemblées par buildFixtures() après les fixtures des lots 0 à 3 ; sortie inchangée tant que les modules sont vides
 * (diff CI vide, job « Cœur » de ios-swift-ci.yml).
 *
 * Gap verrouillé : un fichier déjà écrit par un autre lot ou un autre domaine, ou un nom hors `demo-<nom>.<ext>`, lève
 * une erreur nommant le domaine (jamais un écrasement silencieux d'une fixture d'un autre lot).
 */
import * as bulletins from './bulletins.mjs';
import * as disponibilites from './disponibilites.mjs';
import * as evaluations from './evaluations.mjs';
import * as exclusions from './exclusions.mjs';
import * as filtres from './filtres.mjs';
import * as litiges from './litiges.mjs';
import * as messagerie from './messagerie.mjs';
import * as parrainage from './parrainage.mjs';
import * as poolUrgence from './pool-urgence.mjs';
import * as reclamations from './reclamations.mjs';
import * as score from './score.mjs';
import * as serie from './serie.mjs';
import * as swipe from './swipe.mjs';

/** Domaines du lot 4 dans l'ordre des tranches (T3a … T12) : [nom du module, module]. */
export const DOMAINES_LOT4 = [
  ['swipe', swipe],
  ['filtres', filtres],
  ['disponibilites', disponibilites],
  ['parrainage', parrainage],
  ['messagerie', messagerie],
  ['litiges', litiges],
  ['reclamations', reclamations],
  ['evaluations', evaluations],
  ['score', score],
  ['bulletins', bulletins],
  ['pool-urgence', poolUrgence],
  ['exclusions', exclusions],
  ['serie', serie],
];

const NOM_FIXTURE = /^demo-[a-z0-9-]+\.(json|html|pdf)$/;

/**
 * Fixtures des domaines du lot 4, refusées si elles écrivent un fichier de `existantes` ou d'un autre domaine.
 * @param {{ now: Date }} contexte
 * @param {Record<string, unknown>} existantes fixtures déjà assemblées (lots 0 à 3)
 * @param {Array<[string, { fixtures: (contexte: { now: Date }) => Record<string, unknown> }]>} domaines
 */
export function fixturesLot4(contexte, existantes = {}, domaines = DOMAINES_LOT4) {
  const sortie = {};
  const auteurs = new Map();
  for (const [domaine, module] of domaines) {
    for (const [nom, valeur] of Object.entries(module.fixtures(contexte))) {
      if (!NOM_FIXTURE.test(nom)) {
        throw new Error(`fixtures démo du lot 4 (${domaine}) : nom « ${nom} » hors du motif demo-<nom>.<json|html|pdf>`);
      }
      if (Object.hasOwn(existantes, nom)) {
        throw new Error(`fixtures démo du lot 4 (${domaine}) : « ${nom} » est déjà écrit par un lot antérieur`);
      }
      if (auteurs.has(nom)) {
        throw new Error(`fixtures démo du lot 4 (${domaine}) : « ${nom} » est déjà écrit par le domaine ${auteurs.get(nom)}`);
      }
      auteurs.set(nom, domaine);
      sortie[nom] = valeur;
    }
  }
  return sortie;
}

/**
 * Pages « Recruter des soignants » par type d'établissement (`/recruter-soignants/<slug>`).
 *
 * Règles de rédaction (docs/SEO_STRATEGIE_ACQUISITION.md §5), gardées par `seo-contenus.test.ts` :
 *  - chaque page ne porte que ce qui est propre à son type (situations, professions, une
 *    question) ; ce qui vaut pour tous les établissements (vérification des profils, contrat,
 *    suivi des présences, facturation, tarif) reste sur `/recruter-soignants` et `/tarifs`,
 *    vers lesquels la page renvoie. Cinq pages qui répéteraient le même texte seraient des
 *    pages satellites (revue B8 de #1170) ;
 *  - des situations et des conseils, pas de constats sur le secteur ;
 *  - les seules affirmations sur le produit sont celles déjà publiées sur le site ;
 *  - aucune promesse de délai ni de volume de candidatures ;
 *  - aucun chiffre hors FINESS (ajouté par `seo-routes` avec sa date d'extraction) ;
 *  - rien sur l'intérim, rien qui suggère d'enchaîner des contrats sur un poste permanent.
 * Module pur (aucun import React/DOM).
 */
import type { QuestionSEO } from './types';

/** Clés de `seo-finess.json` (colonnes). */
export type CleFiness = 'ehpad' | 'ssiad' | 'masfam' | 'ime' | 'centreSante';

export interface SituationSEO { titre: string; texte: string }

export interface TypeEtablissementSEO {
  slug: string;
  /** Nom court, pour les liens et le fil d'Ariane. */
  nom: string;
  title: string;
  description: string;
  h1: string;
  accroche: string;
  /** Paragraphe d'ouverture, propre au type d'établissement. */
  contexte: string;
  /** Situations de remplacement propres à ce type d'établissement. */
  situations: SituationSEO[];
  /** Valeurs de profession (`PROFESSIONS_SEO`) citées : liens vers les pages métier. */
  professions: string[];
  /** Catégories FINESS dont le nombre national est cité. */
  finess: CleFiness[];
  /** Question propre au type (une question sur les professions est ajoutée par `seo-routes`). */
  question: QuestionSEO;
}

/** Étapes de publication, identiques pour tous les types (reprises de `/recruter-soignants`). */
export const ETAPES_PUBLICATION: string[] = [
  'Créez votre espace. Inscription gratuite avec SIRET et FINESS.',
  'Publiez une mission. Renseignez la profession, les dates, les horaires et le taux horaire. La mission est visible immédiatement.',
  'Recevez des candidatures. Les soignants vérifiés postulent. Vous validez, le contrat est généré et signé électroniquement.',
];

/** Renvoi vers les pages qui décrivent ce qui est commun à tous les établissements. */
export const RENVOI_COMMUN = 'La vérification des profils, le contrat signé en ligne, le suivi des présences et la facturation sont décrits sur la page « Recruter des soignants ». La commission est de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sans abonnement : le détail est sur la page « Tarifs ».';

export const TYPES_ETABLISSEMENT_SEO: TypeEtablissementSEO[] = [
  {
    slug: 'ehpad',
    nom: 'EHPAD',
    title: 'Remplacement de soignants en EHPAD | Jolene Santé',
    description: 'EHPAD : aide-soignant, infirmier ou AES absent ? Publiez votre besoin et recevez les candidatures de soignants vérifiés. Commission de 15 % HT, sans abonnement.',
    h1: 'Remplacer un soignant en EHPAD',
    accroche: 'Une absence de dernière minute, des congés à couvrir : publiez votre besoin et contractualisez directement avec un soignant dont l’identité et le diplôme ont été vérifiés.',
    contexte: 'Aide-soignant de nuit absent, infirmière en arrêt, congés d’été : en EHPAD, un remplacement peut porter sur une seule nuit comme sur plusieurs semaines. Vous décrivez le poste tel qu’il est, vous choisissez parmi les candidatures, et les documents de la mission sont produits pour vous.',
    situations: [
      { titre: 'L’absence imprévue', texte: 'Un arrêt signalé la veille ou le matin même. Publiez la mission dès que l’absence est connue : elle est visible immédiatement.' },
      { titre: 'Les congés', texte: 'Été, fêtes de fin d’année, ponts. Publiez à l’avance les journées à couvrir, une par une ou sur toute une période.' },
      { titre: 'Les nuits et les week-ends', texte: 'Indiquez les horaires réels du poste, de jour comme de nuit. Le soignant les voit, avec le taux horaire, avant de postuler.' },
    ],
    professions: ['AS', 'IDE', 'AES', 'KINE', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN'],
    finess: ['ehpad'],
    question: { q: 'Peut-on publier une mission de nuit ou de week-end en EHPAD ?', r: 'Oui. Vous renseignez les dates et les horaires réels du poste, de jour comme de nuit, en semaine comme le week-end. Le soignant voit ces horaires et le taux horaire avant de postuler.' },
  },
  {
    slug: 'clinique',
    nom: 'Clinique',
    title: 'Renfort de soignants en clinique | Jolene Santé',
    description: 'Infirmiers, infirmiers de bloc, infirmiers anesthésistes, aides-soignants : publiez vos besoins de renfort en clinique. Commission de 15 % HT, sans abonnement.',
    h1: 'Renforcer vos équipes soignantes en clinique',
    accroche: 'Bloc opératoire, hospitalisation, maternité, soins de suite : publiez le poste à pourvoir et recevez les candidatures de professionnels dont les qualifications ont été vérifiées.',
    contexte: 'Jolene s’adresse aux cliniques privées comme aux établissements de santé privés d’intérêt collectif. Vous précisez la profession recherchée, les horaires et le taux horaire, et vous décrivez le service et la spécialité dans la mission.',
    situations: [
      { titre: 'Le bloc opératoire', texte: 'Infirmier de bloc opératoire (IBODE) ou infirmier anesthésiste (IADE) : décrivez les spécialités chirurgicales concernées pour recevoir des candidatures adaptées.' },
      { titre: 'Les services d’hospitalisation', texte: 'Infirmiers et aides-soignants de jour ou de nuit, pour une vacation ou pour la durée d’un arrêt.' },
      { titre: 'La maternité', texte: 'Sages-femmes et auxiliaires de puériculture pour couvrir un congé ou un surcroît d’activité.' },
    ],
    professions: ['IDE', 'IBODE', 'IADE', 'AS', 'SAGE_FEMME', 'MANIPULATEUR_RADIO', 'KINE'],
    finess: [],
    question: { q: 'Peut-on rechercher un infirmier de bloc ou un infirmier anesthésiste ?', r: 'Oui. Les professions d’infirmier de bloc opératoire (IBODE) et d’infirmier anesthésiste (IADE) se choisissent séparément de celle d’infirmier lorsque vous publiez une mission.' },
  },
  {
    slug: 'hopital',
    nom: 'Hôpital public',
    title: 'Renfort de soignants à l’hôpital public | Jolene Santé',
    description: 'Centres hospitaliers et hôpitaux de proximité : publiez vos besoins de renfort, suivez les présences et recevez vos documents de facturation, avec suivi Chorus Pro.',
    h1: 'Renforcer vos équipes soignantes à l’hôpital public',
    accroche: 'Publiez vos besoins de renfort, suivez les présences et retrouvez vos documents de facturation par période, avec le suivi Chorus Pro prévu pour le secteur public.',
    contexte: 'Médecine, chirurgie, gériatrie, urgences, plateaux techniques : vous publiez le poste à couvrir, de jour comme de nuit. Le type de contrat proposé est indiqué sur chaque mission, et les documents de facturation sont établis par période avec un suivi Chorus Pro.',
    situations: [
      { titre: 'Les services de soins', texte: 'Infirmiers et aides-soignants pour la médecine, la chirurgie, la gériatrie ou les urgences, de jour comme de nuit.' },
      { titre: 'Les plateaux techniques', texte: 'Infirmiers de bloc, infirmiers anesthésistes, manipulateurs en électroradiologie : précisez le plateau et les horaires du poste.' },
      { titre: 'Les hôpitaux de proximité', texte: 'Médecine, soins de suite, unité de soins de longue durée : publiez le besoin dès qu’il est connu, en indiquant le service concerné.' },
      { titre: 'Les périodes de tension', texte: 'Congés d’été, épidémies hivernales, ouverture de lits : plusieurs missions peuvent être publiées sur la même période.' },
    ],
    professions: ['IDE', 'AS', 'IBODE', 'IADE', 'MANIPULATEUR_RADIO', 'SAGE_FEMME', 'MEDECIN'],
    finess: [],
    question: { q: 'La facturation est-elle compatible avec Chorus Pro ?', r: 'Oui. Les documents de facturation sont établis par période et un suivi Chorus Pro est prévu pour les établissements du secteur public.' },
  },
  {
    slug: 'soins-a-domicile',
    nom: 'Soins à domicile',
    title: 'Renfort de soignants à domicile (SSIAD, HAD) | Jolene',
    description: 'Services de soins infirmiers à domicile et hospitalisation à domicile : publiez vos tournées à couvrir et recevez les candidatures de soignants vérifiés.',
    h1: 'Trouver un renfort pour vos soins à domicile',
    accroche: 'Une tournée à couvrir, un congé, un surcroît d’activité : publiez le besoin de votre service de soins à domicile et recevez les candidatures de soignants dont le diplôme a été vérifié.',
    contexte: 'Service de soins infirmiers à domicile ou hospitalisation à domicile : décrivez la mission telle qu’elle se présente (horaires, secteur d’intervention, conditions de déplacement) pour que le soignant sache à quoi s’attendre avant de postuler.',
    situations: [
      { titre: 'La tournée à couvrir', texte: 'Aide-soignant ou infirmier absent : publiez la tournée du matin ou du soir avec ses horaires réels.' },
      { titre: 'Les congés', texte: 'Publiez à l’avance les journées à couvrir pendant les congés de l’équipe.' },
      { titre: 'Le surcroît d’activité', texte: 'De nouvelles prises en charge à assurer pendant quelques jours ou quelques semaines.' },
    ],
    professions: ['AS', 'IDE', 'AES'],
    finess: ['ssiad'],
    question: { q: 'Que faut-il indiquer pour une mission à domicile ?', r: 'Les dates, les horaires et le taux horaire, comme pour toute mission, ainsi que ce qui est propre à votre service dans la description : secteur d’intervention, véhicule fourni ou non, permis demandé.' },
  },
  {
    slug: 'handicap',
    nom: 'Établissements du handicap',
    title: 'Renfort de soignants en MAS, FAM et IME | Jolene Santé',
    description: 'Maisons d’accueil spécialisées, foyers d’accueil médicalisés, instituts médico-éducatifs : publiez vos besoins, recevez les candidatures de professionnels vérifiés.',
    h1: 'Trouver un renfort en MAS, FAM ou IME',
    accroche: 'Accompagnants éducatifs et sociaux, aides-soignants, infirmiers, rééducateurs : publiez le poste à pourvoir et contractualisez directement avec un professionnel vérifié.',
    contexte: 'Maison d’accueil spécialisée, foyer d’accueil médicalisé, institut médico-éducatif : vous publiez un besoin ponctuel ou une série de journées, en indiquant le public accueilli et les particularités du poste dans la description de la mission.',
    situations: [
      { titre: 'L’accompagnement au quotidien', texte: 'Accompagnants éducatifs et sociaux et aides-soignants, en journée, en soirée ou la nuit.' },
      { titre: 'Les soins', texte: 'Infirmiers pour assurer la continuité des soins pendant un congé ou un arrêt.' },
      { titre: 'La rééducation', texte: 'Kinésithérapeutes, ergothérapeutes, psychomotriciens et orthophonistes pendant l’absence d’un professionnel.' },
    ],
    professions: ['AES', 'AS', 'IDE', 'KINE', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'],
    finess: ['masfam', 'ime'],
    question: { q: 'Peut-on décrire le public accueilli ?', r: 'Oui. La description de la mission est libre : vous y indiquez le public accueilli, l’organisation de l’unité et ce qui est attendu du professionnel, pour qu’il postule en connaissance de cause.' },
  },
];

export function getTypeEtablissementBySlug(slug: string): TypeEtablissementSEO | undefined {
  return TYPES_ETABLISSEMENT_SEO.find((t) => t.slug === slug);
}

/**
 * Pages « Recruter des soignants » par type d'établissement (`/recruter-soignants/<slug>`).
 *
 * Règles de rédaction (docs/SEO_STRATEGIE_ACQUISITION.md §5) :
 *  - les seules affirmations sur le produit sont celles déjà publiées sur l'accueil,
 *    `/tarifs` et `/recruter-soignants` (commission, vérifications, contrats, pointage,
 *    DPAE transmise par l'établissement, facturation, Chorus Pro) ;
 *  - aucune promesse de délai ni de volume de candidatures ;
 *  - aucun chiffre hors FINESS (ajouté par `seo-routes` avec sa date d'extraction) ;
 *  - Jolene n'est jamais présentée comme une agence d'intérim.
 * Module pur (aucun import React/DOM).
 */
import type { QuestionSEO } from './types';

/** Clés de `seo-finess.json` (colonnes). */
export type CleFiness = 'ehpad' | 'hopital' | 'ssiad' | 'had' | 'masfam' | 'ime' | 'centreSante';

export interface SituationSEO { titre: string; texte: string }

export interface TypeEtablissementSEO {
  slug: string;
  /** Nom court, pour les liens et le fil d'Ariane. */
  nom: string;
  title: string;
  description: string;
  h1: string;
  accroche: string;
  /** Paragraphes d'ouverture, propres au type d'établissement. */
  contexte: string[];
  /** Situations de remplacement typiques de ce type d'établissement. */
  situations: SituationSEO[];
  /** Valeurs de profession (`PROFESSIONS_SEO`) les plus demandées : liens vers les pages métier. */
  professions: string[];
  /** Catégories FINESS dont le nombre national est cité. */
  finess: CleFiness[];
  faq: QuestionSEO[];
}

/** Ce que la plateforme prend en charge, identique pour tous les types (faits déjà publiés). */
export const PRISE_EN_CHARGE: SituationSEO[] = [
  { titre: 'Des profils vérifiés', texte: 'L’identité professionnelle, le diplôme, le numéro RPPS lorsqu’il existe et les pièces requises par le contrat sont contrôlés.' },
  { titre: 'Un contrat prêt à signer', texte: 'Le contrat est prérempli à partir de la mission, puis signé électroniquement par les deux parties. Il est conclu directement entre votre établissement et le soignant.' },
  { titre: 'Le suivi des présences', texte: 'Le soignant pointe son arrivée et son départ depuis l’application. Vous validez les heures dans votre espace.' },
  { titre: 'Un plan de secours', texte: 'Un plan de secours est activé en cas de désistement ou de non-présentation.' },
  { titre: 'Un coût connu d’avance', texte: 'Commission de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sur la base financière validée de la mission. Aucun abonnement, aucun frais d’inscription.' },
];

/** Étapes de publication, identiques pour tous les types (reprises de `/recruter-soignants`). */
export const ETAPES_PUBLICATION: string[] = [
  'Créez votre espace. Inscription gratuite avec SIRET et FINESS.',
  'Publiez une mission. Renseignez la profession, les dates, les horaires et le taux horaire. La mission est visible immédiatement.',
  'Recevez des candidatures. Les soignants vérifiés postulent. Vous validez, le contrat est généré et signé électroniquement.',
];

const FAQ_COUT: QuestionSEO = {
  q: 'Combien coûte le service ?',
  r: 'Jolene facture à l’établissement une commission de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sur la base financière validée de la mission. Il n’y a ni abonnement ni frais d’inscription : vous ne payez que lorsque vous recrutez. Aucun frais n’est demandé au soignant.',
};
const FAQ_INTERIM: QuestionSEO = {
  q: 'Jolene est-elle une agence d’intérim ?',
  r: 'Non. Jolene est une plateforme de mise en relation : le contrat est signé directement entre votre établissement et le soignant, et Jolene n’est pas l’employeur.',
};
const FAQ_VERIFICATION: QuestionSEO = {
  q: 'Comment les soignants sont-ils vérifiés ?',
  r: 'Le numéro RPPS, lorsqu’il existe, est rapproché de l’Annuaire Santé officiel. Les pièces requises selon la profession et le contrat sont ensuite contrôlées. L’assurance de responsabilité civile professionnelle est demandée pour les missions libérales.',
};

export const TYPES_ETABLISSEMENT_SEO: TypeEtablissementSEO[] = [
  {
    slug: 'ehpad',
    nom: 'EHPAD',
    title: 'Remplacement de soignants en EHPAD | Jolene Santé',
    description: 'EHPAD : aide-soignant, infirmier ou AES absent ? Publiez votre besoin et recevez les candidatures de soignants vérifiés. Commission de 15 % HT, sans abonnement.',
    h1: 'Remplacer un soignant en EHPAD',
    accroche: 'Une absence de dernière minute, des congés à couvrir, un poste vacant : publiez votre besoin et contractualisez directement avec un soignant dont l’identité et le diplôme ont été vérifiés.',
    contexte: [
      'En EHPAD, la continuité des soins repose sur des équipes resserrées. L’absence d’un aide-soignant ou d’un infirmier se répercute aussitôt sur les collègues présents et sur les résidents. Les besoins de remplacement y sont fréquents, souvent connus tard, et vont de la nuit isolée à l’arrêt de plusieurs semaines.',
      'Jolene met votre établissement en relation avec des soignants disponibles près de chez vous. Vous décrivez le poste tel qu’il est, vous choisissez parmi les candidatures, et les documents de la mission sont produits pour vous.',
    ],
    situations: [
      { titre: 'L’absence imprévue', texte: 'Un arrêt signalé la veille ou le matin même. Publiez la mission dès que l’absence est connue : elle est visible immédiatement.' },
      { titre: 'Les congés et les périodes tendues', texte: 'Été, fêtes de fin d’année, ponts. Publiez à l’avance les journées à couvrir, une par une ou sur toute une période.' },
      { titre: 'Les nuits et les week-ends', texte: 'Indiquez les horaires réels du poste, de jour comme de nuit. Le soignant les voit, avec le taux horaire, avant de postuler.' },
      { titre: 'Le poste vacant', texte: 'En attendant l’arrivée d’un titulaire, une succession de missions évite de laisser l’équipe à découvert.' },
    ],
    professions: ['AS', 'IDE', 'AES', 'KINE', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN'],
    finess: ['ehpad'],
    faq: [
      FAQ_COUT,
      FAQ_INTERIM,
      FAQ_VERIFICATION,
      { q: 'Peut-on publier une mission de nuit ou de week-end ?', r: 'Oui. Vous renseignez les dates et les horaires réels du poste, de jour comme de nuit, en semaine comme le week-end. Le soignant voit ces horaires et le taux horaire avant de postuler.' },
    ],
  },
  {
    slug: 'clinique',
    nom: 'Clinique',
    title: 'Renfort de soignants en clinique | Jolene Santé',
    description: 'Infirmiers, infirmiers de bloc, anesthésistes, aides-soignants : publiez vos besoins de renfort en clinique et contractualisez directement. Commission de 15 % HT.',
    h1: 'Renforcer vos équipes soignantes en clinique',
    accroche: 'Bloc opératoire, hospitalisation, maternité, soins de suite : publiez le poste à pourvoir et recevez les candidatures de professionnels dont les qualifications ont été vérifiées.',
    contexte: [
      'En clinique, l’activité se programme à l’avance et se décale difficilement. L’absence d’un infirmier de bloc opératoire ou d’un infirmier anesthésiste pèse sur toute une journée d’interventions ; celle d’un infirmier ou d’un aide-soignant en hospitalisation, sur le service entier.',
      'Jolene s’adresse aux cliniques privées comme aux établissements de santé privés d’intérêt collectif. Vous précisez la profession recherchée, les horaires et le taux horaire, et vous décrivez le service dans la mission.',
    ],
    situations: [
      { titre: 'Le bloc opératoire', texte: 'Infirmier de bloc opératoire (IBODE) ou infirmier anesthésiste (IADE) : décrivez les spécialités chirurgicales concernées pour recevoir des candidatures adaptées.' },
      { titre: 'Les services d’hospitalisation', texte: 'Infirmiers et aides-soignants de jour ou de nuit, pour une vacation ou pour la durée d’un arrêt.' },
      { titre: 'La maternité', texte: 'Sages-femmes et auxiliaires de puériculture pour couvrir un congé ou un pic d’activité.' },
      { titre: 'Les pics d’activité', texte: 'Ouverture de lits, reprise après une fermeture estivale, épidémie hivernale : publiez plusieurs missions sur la même période.' },
    ],
    professions: ['IDE', 'IBODE', 'IADE', 'AS', 'SAGE_FEMME', 'MANIPULATEUR_RADIO', 'KINE'],
    finess: [],
    faq: [
      FAQ_COUT,
      FAQ_INTERIM,
      FAQ_VERIFICATION,
      { q: 'Peut-on rechercher un infirmier de bloc ou un infirmier anesthésiste ?', r: 'Oui. Les professions d’infirmier de bloc opératoire (IBODE) et d’infirmier anesthésiste (IADE) se choisissent séparément de celle d’infirmier lorsque vous publiez une mission.' },
    ],
  },
  {
    slug: 'hopital',
    nom: 'Hôpital public',
    title: 'Renfort de soignants à l’hôpital public | Jolene Santé',
    description: 'Centres hospitaliers et hôpitaux de proximité : publiez vos besoins de renfort, suivez les présences et recevez vos documents de facturation, avec suivi Chorus Pro.',
    h1: 'Renforcer vos équipes soignantes à l’hôpital public',
    accroche: 'Publiez vos besoins de renfort, suivez les présences et retrouvez vos documents de facturation par période, avec le suivi Chorus Pro prévu pour le secteur public.',
    contexte: [
      'À l’hôpital public, un service fonctionne en continu et un poste vacant se compense souvent par des heures supplémentaires ou des rappels sur repos. Trouver un renfort extérieur demande du temps que les cadres de santé n’ont pas toujours.',
      'Jolene centralise la publication du besoin, les candidatures, le suivi des présences et la facturation. Le type de contrat proposé est indiqué sur chaque mission, et les documents de facturation sont établis par période avec un suivi Chorus Pro.',
    ],
    situations: [
      { titre: 'Les services de soins', texte: 'Infirmiers et aides-soignants pour la médecine, la chirurgie, la gériatrie ou les urgences, de jour comme de nuit.' },
      { titre: 'Les plateaux techniques', texte: 'Infirmiers de bloc, infirmiers anesthésistes, manipulateurs en électroradiologie.' },
      { titre: 'Les hôpitaux de proximité', texte: 'Des équipes réduites où une seule absence déséquilibre le planning : publiez le besoin dès qu’il est connu.' },
      { titre: 'Les périodes de tension', texte: 'Congés d’été, épidémies hivernales, ouverture de lits : plusieurs missions peuvent être publiées sur la même période.' },
    ],
    professions: ['IDE', 'AS', 'IBODE', 'IADE', 'MANIPULATEUR_RADIO', 'SAGE_FEMME', 'MEDECIN'],
    finess: ['hopital'],
    faq: [
      FAQ_COUT,
      FAQ_INTERIM,
      FAQ_VERIFICATION,
      { q: 'La facturation est-elle compatible avec Chorus Pro ?', r: 'Oui. Les documents de facturation sont établis par période et un suivi Chorus Pro est prévu pour les établissements du secteur public.' },
    ],
  },
  {
    slug: 'soins-a-domicile',
    nom: 'Soins à domicile',
    title: 'Renfort de soignants à domicile (SSIAD, HAD) | Jolene',
    description: 'Services de soins infirmiers à domicile et hospitalisation à domicile : publiez vos tournées à couvrir et recevez les candidatures de soignants vérifiés.',
    h1: 'Trouver un renfort pour vos soins à domicile',
    accroche: 'Une tournée à couvrir, un congé, un surcroît d’activité : publiez le besoin de votre service de soins à domicile et recevez les candidatures de soignants dont le diplôme a été vérifié.',
    contexte: [
      'Dans un service de soins infirmiers à domicile ou en hospitalisation à domicile, une absence ne se répartit pas entre collègues comme dans un service hospitalier : une tournée non couverte, ce sont des patients qui ne sont pas vus. Le remplacement doit être trouvé vite et pour des horaires précis.',
      'Jolene vous permet de décrire la mission telle qu’elle se présente (horaires, secteur d’intervention, conditions de déplacement) pour que le soignant sache à quoi s’attendre avant de postuler.',
    ],
    situations: [
      { titre: 'La tournée à couvrir', texte: 'Aide-soignant ou infirmier absent : publiez la tournée du matin ou du soir avec ses horaires réels.' },
      { titre: 'Les congés', texte: 'Publiez à l’avance les journées à couvrir pendant les congés de l’équipe.' },
      { titre: 'Le surcroît d’activité', texte: 'De nouvelles prises en charge à assurer avant un recrutement durable.' },
    ],
    professions: ['AS', 'IDE', 'AES'],
    finess: ['ssiad', 'had'],
    faq: [
      FAQ_COUT,
      FAQ_INTERIM,
      FAQ_VERIFICATION,
      { q: 'Que faut-il indiquer pour une mission à domicile ?', r: 'Les dates, les horaires et le taux horaire, comme pour toute mission, ainsi que tout ce qui est propre à votre service dans la description : secteur d’intervention, véhicule fourni ou non, permis demandé.' },
    ],
  },
  {
    slug: 'handicap',
    nom: 'Établissements du handicap',
    title: 'Renfort de soignants en MAS, FAM et IME | Jolene Santé',
    description: 'Maisons d’accueil spécialisées, foyers d’accueil médicalisés, instituts médico-éducatifs : publiez vos besoins, recevez les candidatures de professionnels vérifiés.',
    h1: 'Trouver un renfort en MAS, FAM ou IME',
    accroche: 'Accompagnants éducatifs et sociaux, aides-soignants, infirmiers, rééducateurs : publiez le poste à pourvoir et contractualisez directement avec un professionnel vérifié.',
    contexte: [
      'Dans les établissements qui accueillent des personnes en situation de handicap, la stabilité des équipes compte autant que les effectifs : les personnes accompagnées ont leurs repères, et un remplaçant doit être présenté et guidé. Mieux vaut donc anticiper les absences prévisibles et décrire précisément le poste.',
      'Jolene vous permet de publier un besoin ponctuel ou une série de journées, en indiquant le public accueilli et les particularités du poste dans la description de la mission.',
    ],
    situations: [
      { titre: 'L’accompagnement au quotidien', texte: 'Accompagnants éducatifs et sociaux et aides-soignants, en journée, en soirée ou la nuit.' },
      { titre: 'Les soins', texte: 'Infirmiers pour assurer la continuité des soins pendant un congé ou un arrêt.' },
      { titre: 'La rééducation', texte: 'Kinésithérapeutes, ergothérapeutes, psychomotriciens et orthophonistes pour maintenir les prises en charge.' },
      { titre: 'Les week-ends et les vacances', texte: 'Des périodes où les titulaires sont moins nombreux : publiez à l’avance les journées à couvrir.' },
    ],
    professions: ['AES', 'AS', 'IDE', 'KINE', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'],
    finess: ['masfam', 'ime'],
    faq: [
      FAQ_COUT,
      FAQ_INTERIM,
      FAQ_VERIFICATION,
      { q: 'Peut-on décrire le public accueilli ?', r: 'Oui. La description de la mission est libre : vous y indiquez le public accueilli, l’organisation de l’unité et ce qui est attendu du professionnel, pour qu’il postule en connaissance de cause.' },
    ],
  },
];

export function getTypeEtablissementBySlug(slug: string): TypeEtablissementSEO | undefined {
  return TYPES_ETABLISSEMENT_SEO.find((t) => t.slug === slug);
}

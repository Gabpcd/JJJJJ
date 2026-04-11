import { PROFESSIONS } from '@/lib/constantes';

export interface VilleSEO {
  slug: string;
  nom: string;
  departement: string;
}

export const VILLES_SEO: VilleSEO[] = [
  { slug: 'paris', nom: 'Paris', departement: '75' },
  { slug: 'lyon', nom: 'Lyon', departement: '69' },
  { slug: 'marseille', nom: 'Marseille', departement: '13' },
  { slug: 'toulouse', nom: 'Toulouse', departement: '31' },
  { slug: 'nice', nom: 'Nice', departement: '06' },
  { slug: 'nantes', nom: 'Nantes', departement: '44' },
  { slug: 'montpellier', nom: 'Montpellier', departement: '34' },
  { slug: 'strasbourg', nom: 'Strasbourg', departement: '67' },
  { slug: 'bordeaux', nom: 'Bordeaux', departement: '33' },
  { slug: 'lille', nom: 'Lille', departement: '59' },
  { slug: 'rennes', nom: 'Rennes', departement: '35' },
  { slug: 'reims', nom: 'Reims', departement: '51' },
  { slug: 'saint-etienne', nom: 'Saint-Étienne', departement: '42' },
  { slug: 'toulon', nom: 'Toulon', departement: '83' },
  { slug: 'le-havre', nom: 'Le Havre', departement: '76' },
  { slug: 'grenoble', nom: 'Grenoble', departement: '38' },
  { slug: 'dijon', nom: 'Dijon', departement: '21' },
  { slug: 'angers', nom: 'Angers', departement: '49' },
  { slug: 'nimes', nom: 'Nîmes', departement: '30' },
  { slug: 'clermont-ferrand', nom: 'Clermont-Ferrand', departement: '63' },
];

export interface ProfessionSEO {
  valeur: string;
  label: string;
  slug: string;
  description: string;
  salaire_moyen: string;
}

export const PROFESSIONS_SEO: ProfessionSEO[] = [
  {
    valeur: 'IDE',
    label: "Infirmier(ère) Diplômé(e) d'État (IDE)",
    slug: 'infirmier-ide',
    description: "L'infirmier(ère) diplômé(e) d'État réalise des soins techniques et relationnels auprès des patients. Profession la plus demandée en intérim de santé.",
    salaire_moyen: '25-35\u20AC/h',
  },
  {
    valeur: 'AS',
    label: 'Aide-Soignant(e) (AS)',
    slug: 'aide-soignant',
    description: "L'aide-soignant(e) accompagne les patients dans les gestes de la vie quotidienne et assiste l'infirmier(ère) dans les soins d'hygiène.",
    salaire_moyen: '16-22\u20AC/h',
  },
  {
    valeur: 'AES',
    label: 'Accompagnant Éducatif et Social (AES)',
    slug: 'accompagnant-educatif-social',
    description: "L'AES intervient auprès de personnes en situation de handicap ou de dépendance pour favoriser leur autonomie et leur inclusion sociale.",
    salaire_moyen: '15-20\u20AC/h',
  },
  {
    valeur: 'IBODE',
    label: 'Infirmier(ère) de Bloc Opératoire (IBODE)',
    slug: 'infirmier-bloc-operatoire',
    description: "L'IBODE assiste le chirurgien au bloc opératoire en assurant l'instrumentation, la circulation et la gestion du matériel stérile.",
    salaire_moyen: '30-42\u20AC/h',
  },
  {
    valeur: 'IADE',
    label: 'Infirmier(ère) Anesthésiste (IADE)',
    slug: 'infirmier-anesthesiste',
    description: "L'IADE pratique l'anesthésie sous la responsabilité du médecin anesthésiste-réanimateur. Spécialisation très recherchée en intérim.",
    salaire_moyen: '32-48\u20AC/h',
  },
  {
    valeur: 'SAGE_FEMME',
    label: 'Sage-Femme',
    slug: 'sage-femme',
    description: 'La sage-femme accompagne les femmes pendant la grossesse, l\'accouchement et le post-partum. Elle assure également le suivi gynécologique.',
    salaire_moyen: '28-40\u20AC/h',
  },
  {
    valeur: 'KINE',
    label: 'Kinésithérapeute',
    slug: 'kinesitherapeute',
    description: 'Le kinésithérapeute rééduque les patients par le mouvement et les techniques manuelles. Forte demande en EHPAD et en établissements SSR.',
    salaire_moyen: '28-38\u20AC/h',
  },
  {
    valeur: 'MEDECIN',
    label: 'Médecin',
    slug: 'medecin',
    description: 'Le médecin diagnostique et traite les pathologies des patients. Les remplacements concernent la médecine générale et les spécialités hospitalières.',
    salaire_moyen: '50-80\u20AC/h',
  },
  {
    valeur: 'PHARMACIEN',
    label: 'Pharmacien(ne)',
    slug: 'pharmacien',
    description: 'Le pharmacien délivre les médicaments et assure le conseil pharmaceutique. Remplacements fréquents en officine et en pharmacie hospitalière.',
    salaire_moyen: '30-45\u20AC/h',
  },
  {
    valeur: 'MANIPULATEUR_RADIO',
    label: 'Manipulateur Radio',
    slug: 'manipulateur-radio',
    description: 'Le manipulateur en électroradiologie réalise les examens d\'imagerie médicale (radiographie, scanner, IRM) sous la responsabilité du radiologue.',
    salaire_moyen: '25-35\u20AC/h',
  },
  {
    valeur: 'PREPARATEUR_PHARMA',
    label: 'Préparateur en Pharmacie',
    slug: 'preparateur-pharmacie',
    description: 'Le préparateur en pharmacie seconde le pharmacien dans la délivrance des médicaments et la gestion des stocks.',
    salaire_moyen: '16-22\u20AC/h',
  },
  {
    valeur: 'DIETETICIEN',
    label: 'Diététicien(ne)',
    slug: 'dieteticien',
    description: 'Le diététicien élabore des programmes nutritionnels adaptés aux patients hospitalisés et accompagne la prise en charge nutritionnelle.',
    salaire_moyen: '20-28\u20AC/h',
  },
  {
    valeur: 'ERGOTHERAPEUTE',
    label: 'Ergothérapeute',
    slug: 'ergotherapeute',
    description: 'L\'ergothérapeute aide les patients à retrouver leur autonomie dans les activités quotidiennes grâce à des techniques de rééducation et d\'adaptation.',
    salaire_moyen: '24-32\u20AC/h',
  },
  {
    valeur: 'PSYCHOMOTRICIEN',
    label: 'Psychomotricien(ne)',
    slug: 'psychomotricien',
    description: 'Le psychomotricien intervient sur les troubles psychomoteurs par des techniques de relaxation, de stimulation sensorielle et de médiation corporelle.',
    salaire_moyen: '22-30\u20AC/h',
  },
  {
    valeur: 'ORTHOPHONISTE',
    label: 'Orthophoniste',
    slug: 'orthophoniste',
    description: 'L\'orthophoniste prévient, évalue et traite les troubles de la communication orale et écrite, ainsi que les troubles de la déglutition.',
    salaire_moyen: '26-36\u20AC/h',
  },
];

export function getVilleBySlug(slug: string): VilleSEO | undefined {
  return VILLES_SEO.find(v => v.slug === slug);
}

export function getProfessionBySlug(slug: string): ProfessionSEO | undefined {
  return PROFESSIONS_SEO.find(p => p.slug === slug);
}

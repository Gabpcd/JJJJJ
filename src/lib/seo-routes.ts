/**
 * Source de vérité unique des pages SEO publiques (titres, descriptions, H1,
 * textes d'introduction, maillage interne, indexabilité).
 *
 * Consommée par les composants React (PageAccueil, Tarifs, VilleLanding,
 * ProfessionLanding, VilleProfessionLanding…) ET par
 * `scripts/seo/generer-pages-statiques.mjs` (HTML statique crawlable, sitemap,
 * llms.txt). Module pur : aucun import React/DOM.
 *
 * Règle : une page n'a de HTML statique que si son composant React lit ici son
 * titre, sa description, son H1 et ses données structurées. Les deux versions
 * (avec et sans JavaScript) disent ainsi la même chose.
 *
 * Aucune affirmation juridique, aucune donnée personnelle. Seul chiffre
 * ajouté aux données déjà présentes dans seo-data : l'enquête BMO 2026
 * (France Travail, Licence Ouverte), uniquement pour AS et MEDECIN.
 */
import {
  VILLES_SEO,
  PROFESSIONS_SEO,
  getVilleBySlug,
  getProfessionBySlug,
  type VilleSEO,
  type ProfessionSEO,
} from './seo-data';
import bmoBrut from './seo-bmo-2026.json';
import { ACCROCHE_ACCUEIL, ATOUTS_ETABLISSEMENTS, ATOUTS_SOIGNANTS, ETAPES_ACCUEIL, FAQ_ACCUEIL, TITRE_ACCUEIL } from './seo-contenu/accueil';
import { FAQ_DEVENIR_SOIGNANT } from './seo-contenu/devenir-soignant';
import { FAQ_RECRUTER_SOIGNANTS } from './seo-contenu/recruter-soignants';
import { INCLUS_TARIFS, TAUX_HT, TAUX_TTC, TITRE_COMMISSION } from './seo-contenu/tarifs';
import type { QuestionSEO, SectionSEO } from './seo-contenu/types';

export const SITE_URL = 'https://jolene.app';

// ─── Pages ville × métier : périmètre volontairement restreint ───────────────
// (pas de 100 × 17 : risque « doorway pages »). VILLES_SEO est trié par taille.
export const NB_VILLES_VILLE_METIER = 30;
export const VILLES_VILLE_METIER: VilleSEO[] = VILLES_SEO.slice(0, NB_VILLES_VILLE_METIER);

export const PROFESSIONS_VILLE_METIER = ['IDE', 'AS', 'AES', 'MEDECIN', 'KINE', 'SAGE_FEMME'] as const;

/** court : titres et liens ; phrase : forme employée en milieu de phrase (sigles conservés en capitales). */
interface NomsMetier { court: string; phrase: string; pluriel: string }
const NOMS_METIER: Record<string, NomsMetier> = {
  IDE: { court: 'Infirmier (IDE)', phrase: 'infirmier (IDE)', pluriel: 'infirmiers' },
  AS: { court: 'Aide-soignant', phrase: 'aide-soignant', pluriel: 'aides-soignants' },
  AES: { court: 'Accompagnant éducatif et social (AES)', phrase: 'accompagnant éducatif et social (AES)', pluriel: 'accompagnants éducatifs et sociaux' },
  MEDECIN: { court: 'Médecin', phrase: 'médecin', pluriel: 'médecins' },
  KINE: { court: 'Kinésithérapeute', phrase: 'kinésithérapeute', pluriel: 'kinésithérapeutes' },
  SAGE_FEMME: { court: 'Sage-femme', phrase: 'sage-femme', pluriel: 'sages-femmes' },
  IBODE: { court: 'Infirmier de bloc opératoire (IBODE)', phrase: 'infirmier de bloc opératoire (IBODE)', pluriel: 'infirmiers de bloc opératoire' },
  IADE: { court: 'Infirmier anesthésiste (IADE)', phrase: 'infirmier anesthésiste (IADE)', pluriel: 'infirmiers anesthésistes' },
  PHARMACIEN: { court: 'Pharmacien', phrase: 'pharmacien', pluriel: 'pharmaciens' },
  MANIPULATEUR_RADIO: { court: 'Manipulateur radio', phrase: 'manipulateur radio', pluriel: 'manipulateurs radio' },
  PREPARATEUR_PHARMA: { court: 'Préparateur en pharmacie', phrase: 'préparateur en pharmacie', pluriel: 'préparateurs en pharmacie' },
  DIETETICIEN: { court: 'Diététicien', phrase: 'diététicien', pluriel: 'diététiciens' },
  ERGOTHERAPEUTE: { court: 'Ergothérapeute', phrase: 'ergothérapeute', pluriel: 'ergothérapeutes' },
  PSYCHOMOTRICIEN: { court: 'Psychomotricien', phrase: 'psychomotricien', pluriel: 'psychomotriciens' },
  ORTHOPHONISTE: { court: 'Orthophoniste', phrase: 'orthophoniste', pluriel: 'orthophonistes' },
};

/** Longueur au-delà de laquelle Google tronque un titre dans ses résultats (ordre de grandeur). */
export const LONGUEUR_TITRE_MAX = 60;

/**
 * Titre d'une page métier : la forme la plus complète qui tient dans LONGUEUR_TITRE_MAX.
 * L'ancien titre (« Missions {libellé long} — remplacements & CDD courts | Jolene Santé »)
 * atteignait 90 caractères et était tronqué.
 */
export function titreMetier(professionValeur: string, libelle: string): string {
  const nom = NOMS_METIER[professionValeur]?.court ?? libelle;
  const candidats = [
    `${nom} : missions et remplacements | Jolene Santé`,
    `${nom} : missions et remplacements | Jolene`,
    `Missions ${nom} | Jolene Santé`,
    `Missions ${nom} | Jolene`,
  ];
  return candidats.find((t) => t.length <= LONGUEUR_TITRE_MAX) ?? candidats[candidats.length - 1];
}

export const PROFESSIONS_SEO_VILLE_METIER: ProfessionSEO[] = PROFESSIONS_VILLE_METIER
  .map((v) => PROFESSIONS_SEO.find((p) => p.valeur === v))
  .filter((p): p is ProfessionSEO => !!p);

export function estVilleVilleMetier(villeSlug: string): boolean {
  return VILLES_VILLE_METIER.some((v) => v.slug === villeSlug);
}
export function estProfessionVilleMetier(professionSlug: string): boolean {
  return PROFESSIONS_SEO_VILLE_METIER.some((p) => p.slug === professionSlug);
}

// ─── Régions (voisinage pour le maillage) : table administrative publique ───
const REGIONS: Record<string, string[]> = {
  'ile-de-france': ['75', '77', '78', '91', '92', '93', '94', '95'],
  paca: ['13', '06', '83', '84'],
  'auvergne-rhone-alpes': ['69', '42', '38', '63', '74', '26', '73'],
  occitanie: ['31', '34', '30', '66', '82'],
  'pays-de-la-loire': ['44', '49', '72', '85', '53'],
  'nouvelle-aquitaine': ['33', '87', '86', '64', '17', '79', '16'],
  'grand-est': ['67', '51', '10', '57', '68', '54'],
  'hauts-de-france': ['59', '80', '62', '02', '60'],
  bretagne: ['35', '29', '56'],
  normandie: ['76', '14'],
  'bourgogne-franche-comte': ['21', '25'],
  'centre-val-de-loire': ['37', '45', '18'],
  corse: ['2A'],
};
const REGION_PAR_DEPARTEMENT: Record<string, string> = {};
for (const [region, depts] of Object.entries(REGIONS)) {
  for (const d of depts) REGION_PAR_DEPARTEMENT[d] = region;
}

export function regionDeDepartement(dept: string): string | undefined {
  return REGION_PAR_DEPARTEMENT[dept];
}

/** Villes du même département puis de la même région (pages ville × métier d'abord). */
export function villesVoisines(ville: VilleSEO, max = 5): VilleSEO[] {
  const region = regionDeDepartement(ville.departement);
  const rang = (v: VilleSEO) => (v.departement === ville.departement ? 0 : 2) + (estVilleVilleMetier(v.slug) ? 0 : 1);
  return VILLES_SEO
    .filter((v) => v.slug !== ville.slug)
    .filter((v) => v.departement === ville.departement || (!!region && regionDeDepartement(v.departement) === region))
    .map((v, i) => ({ v, i }))
    .sort((a, b) => rang(a.v) - rang(b.v) || a.i - b.i)
    .slice(0, max)
    .map((x) => x.v);
}

// ─── Données BMO 2026 (AS et MEDECIN uniquement) ─────────────────────────────
export type MetierBmo = 'AS' | 'MEDECIN';
/** [projets de recrutement, % jugés difficiles (null = non communiqué)] */
export type EntreeBmo = [number, number | null];
export type TableBmo = Record<string, Partial<Record<MetierBmo, EntreeBmo | null>>>;
export const BMO_2026: TableBmo = bmoBrut as unknown as TableBmo;

export const SOURCE_BMO = 'Enquête BMO 2026, France Travail';
const LIBELLE_BMO: Record<MetierBmo, string> = { AS: 'd’aides-soignants', MEDECIN: 'de médecins' };

function espaceMilliers(n: number): string {
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

/** Phrase de tension du département, ou null si la donnée est absente, nulle ou sans pourcentage. */
export function phraseBmo(departement: string, professionValeur: string, table: TableBmo = BMO_2026): string | null {
  if (professionValeur !== 'AS' && professionValeur !== 'MEDECIN') return null;
  const e = table[departement]?.[professionValeur];
  if (!e) return null;
  const [projets, pct] = e;
  if (typeof projets !== 'number' || !(projets > 0)) return null;
  if (typeof pct !== 'number' || !Number.isFinite(pct)) return null;
  const nb = `${espaceMilliers(projets)} projet${projets > 1 ? 's' : ''}`;
  return `Dans le département ${departement}, les employeurs déclarent ${nb} de recrutement ${LIBELLE_BMO[professionValeur]} en 2026, dont ${Math.round(pct)} % jugés difficiles (${SOURCE_BMO}).`;
}

// ─── Modèle de page ──────────────────────────────────────────────────────────
export interface LienSEO { href: string; label: string }
export interface PageSEO {
  type: 'accueil' | 'institutionnel' | 'devenir' | 'recruter' | 'ville' | 'metier' | 'ville-metier';
  path: string;
  title: string;
  description: string;
  h1: string;
  intro: string[];
  /** Blocs de contenu statique sous l'introduction (titre de niveau 2, paragraphes, liste). */
  sections?: SectionSEO[];
  /** Questions fréquentes : rendues en HTML statique et déclarées en FAQPage. */
  faq?: QuestionSEO[];
  /** Pages situées entre l'accueil et celle-ci (fil d'Ariane). Absent : page de premier niveau. */
  filAriane?: LienSEO[];
  /** Données structurées propres à la page, ajoutées à celles dérivées (fil d'Ariane, FAQ). */
  donneesStructurees?: Record<string, unknown>[];
  liens: LienSEO[];
  indexable: boolean;
  priorite: string;
  frequence: string;
}

export const urlAbsolue = (path: string) => `${SITE_URL}${path}`;
export const cheminVille = (villeSlug: string) => `/emploi-soignant/${villeSlug}`;
export const cheminMetier = (professionSlug: string) => `/metier/${professionSlug}`;
export const cheminVilleMetier = (villeSlug: string, professionSlug: string) => `/emploi-soignant/${villeSlug}/${professionSlug}`;

/** UTM du CTA d'inscription des pages ville × métier. */
export const UTM_VILLE_METIER = { source: 'seo', medium: 'organic', campaign: 'seo-ville-metier' } as const;
export const contenuUtmVilleMetier = (villeSlug: string, professionSlug: string) => `${villeSlug}-${professionSlug}`;

/** Villes et métiers cités dans le maillage de l'accueil : les plus grandes villes, les métiers ville × métier. */
const NB_VILLES_ACCUEIL = 12;

export function metaAccueil(): PageSEO {
  return {
    type: 'accueil', path: '/',
    title: 'Jolene Santé — Missions soignants & remplacements vérifiés',
    description: 'Jolene Santé connecte établissements de santé et soignants vérifiés (diplôme, RPPS, assurance) pour des missions et remplacements ponctuels. Inscription gratuite, contrats automatisés.',
    h1: TITRE_ACCUEIL,
    intro: [ACCROCHE_ACCUEIL],
    sections: [
      { titre: 'Pour les soignants', liste: ATOUTS_SOIGNANTS.map((a) => a.text) },
      { titre: 'Pour les établissements', liste: ATOUTS_ETABLISSEMENTS.map((a) => a.text) },
      { titre: 'Comment ça marche', liste: ETAPES_ACCUEIL.map((e) => `${e.titre}. ${e.desc}`) },
    ],
    faq: FAQ_ACCUEIL,
    donneesStructurees: [
      {
        '@context': 'https://schema.org',
        '@type': 'WebSite',
        name: 'Jolene Santé',
        alternateName: 'Jolene',
        url: `${SITE_URL}/`,
        inLanguage: 'fr-FR',
      },
      {
        '@context': 'https://schema.org',
        '@type': 'WebApplication',
        name: 'Jolene',
        url: SITE_URL,
        description: 'Plateforme de staffing médical pour établissements de santé et soignants qualifiés en France.',
        applicationCategory: 'HealthApplication',
        operatingSystem: 'Web, iOS, Android',
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR', description: 'Inscription gratuite pour les soignants' },
        creator: { '@type': 'Organization', name: 'Jolene SASU', url: SITE_URL, address: { '@type': 'PostalAddress', streetAddress: '103 rue de Vaugirard', addressLocality: 'Paris', postalCode: '75006', addressCountry: 'FR' } },
      },
    ],
    liens: [
      { href: '/inscription/soignant', label: 'Je suis soignant : créer mon compte' },
      { href: '/inscription/etablissement', label: 'Je suis un établissement : créer mon espace' },
      { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' },
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/tarifs', label: 'Tarifs' },
      { href: '/infirmiere-liberale', label: 'Passer infirmière libérale' },
      { href: '/telecharger', label: 'Télécharger l’application' },
      { href: '/a-propos', label: 'À propos de Jolene' },
      { href: '/aide', label: 'Centre d’aide' },
      ...PROFESSIONS_SEO_VILLE_METIER.map((p) => ({ href: cheminMetier(p.slug), label: `Missions ${NOMS_METIER[p.valeur].court}` })),
      ...VILLES_SEO.slice(0, NB_VILLES_ACCUEIL).map((v) => ({ href: cheminVille(v.slug), label: `Missions soignants à ${v.nom}` })),
    ],
    indexable: true, priorite: '1.0', frequence: 'weekly',
  };
}

// ─── Pages institutionnelles : même titre, même H1 et même accroche que leur composant ───
export type CleInstitutionnelle = 'tarifs' | 'a-propos' | 'infirmiere-liberale' | 'telecharger' | 'contact';

const LIENS_INSTITUTIONNELS: LienSEO[] = [
  { href: '/inscription/soignant', label: 'Créer un compte soignant' },
  { href: '/inscription/etablissement', label: 'Créer un espace établissement' },
  { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' },
  { href: '/recruter-soignants', label: 'Recruter des soignants' },
];

const PAGES_INSTITUTIONNELLES: Record<CleInstitutionnelle, Omit<PageSEO, 'type' | 'indexable' | 'frequence'>> = {
  tarifs: {
    path: '/tarifs',
    title: 'Tarifs Jolene | Commission de 15 % HT (18 % TTC)',
    description: 'Une commission de 15 % HT, soit 18 % TTC avec une TVA de 20 %, sur les honoraires HT libéraux ou la rémunération brute salariée validée. Sans abonnement.',
    h1: 'Nos tarifs — Transparence totale',
    intro: [
      'Une commission unique sur la base financière validée de la mission. Pas d\'abonnement.',
      'Aucun frais pour les soignants, quel que soit le contrat.',
    ],
    sections: [{ titre: TITRE_COMMISSION, paragraphes: [TAUX_HT, TAUX_TTC], liste: INCLUS_TARIFS }],
    liens: [{ href: '/inscription/etablissement', label: 'S’inscrire gratuitement' }, { href: '/recruter-soignants', label: 'Recruter des soignants' }, { href: '/contact', label: 'Nous contacter' }],
    priorite: '0.8',
  },
  'a-propos': {
    path: '/a-propos',
    title: 'À propos de Jolene | Staffing médical digital',
    description: 'Découvrez la mission de Jolene : simplifier le staffing médical en connectant établissements de santé et soignants qualifiés, en toute conformité.',
    h1: 'Simplifier le staffing médical. Pour de bon.',
    intro: [
      'Jolene est née d\'un constat simple : trouver un soignant remplaçant ne devrait pas prendre des heures d\'appels téléphoniques.',
      'Nous connectons les établissements de santé avec des soignants qualifiés et vérifiés, en automatisant tout ce qui peut l\'être : contrats, conformité, pointage, facturation. Notre objectif : que chaque établissement trouve le bon soignant, sans passer des heures au téléphone.',
    ],
    liens: [...LIENS_INSTITUTIONNELS, { href: '/contact', label: 'Nous contacter' }],
    priorite: '0.7',
  },
  'infirmiere-liberale': {
    path: '/infirmiere-liberale',
    title: 'Devenir infirmière libérale | Jolene Santé',
    description: 'Passez infirmière libérale avec Jolene Santé : parcours 3 200 h suivi heure par heure, missions de remplacement, étapes installation CPAM, Ordre, URSSAF.',
    h1: 'Passer infirmière libérale avec Jolene',
    intro: ['Cumulez vos 3 200 heures, suivez votre progression heure par heure et installez-vous en libéral en toute sérénité.'],
    liens: [{ href: '/inscription/soignant', label: 'Commencer mon parcours' }, { href: cheminMetier('infirmier-ide'), label: 'Missions Infirmier (IDE)' }, { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' }],
    priorite: '0.8',
  },
  telecharger: {
    path: '/telecharger',
    title: 'Télécharger Jolene | App iOS et Android',
    description: 'Téléchargez Jolene sur iPhone et Android. Trouvez des missions, signez vos contrats et pointez votre arrivée depuis votre téléphone.',
    h1: 'Jolene dans votre poche',
    intro: ['Trouvez des missions, signez vos contrats et pointez votre arrivée — tout depuis votre téléphone.'],
    liens: LIENS_INSTITUTIONNELS,
    priorite: '0.6',
  },
  contact: {
    path: '/contact',
    title: 'Contact | Jolene Santé',
    description: 'Une question sur Jolene Santé ? Contactez l\'équipe directement via le formulaire ou par email à support@jolene.app.',
    h1: 'Une question ? Écrivez-nous.',
    intro: ['L\'équipe Jolene Santé vous répond rapidement — établissements, soignants, presse ou partenariats.'],
    liens: [...LIENS_INSTITUTIONNELS, { href: '/aide', label: 'Centre d’aide' }],
    priorite: '0.5',
  },
};

export const CLES_INSTITUTIONNELLES = Object.keys(PAGES_INSTITUTIONNELLES) as CleInstitutionnelle[];

export function metaInstitutionnelle(cle: CleInstitutionnelle): PageSEO {
  return { type: 'institutionnel', indexable: true, frequence: 'monthly', ...PAGES_INSTITUTIONNELLES[cle] };
}

export function metaDevenirSoignant(): PageSEO {
  return {
    type: 'devenir', path: '/devenir-soignant',
    title: 'Devenir soignant remplaçant | Jolene Santé',
    description: 'Missions de remplacement santé pour infirmiers, aides-soignants et professionnels de santé. Inscription gratuite, rémunération transparente et contrat indiqué avant candidature.',
    h1: 'Devenir soignant sur Jolene',
    // « des centaines de missions » retiré : aucune mission n'était publiée (constat du 20/11/2026).
    intro: ['Accédez à des missions de remplacement en santé près de chez vous, choisissez vos horaires et construisez votre parcours professionnel.'],
    faq: FAQ_DEVENIR_SOIGNANT,
    liens: [{ href: '/inscription/soignant', label: 'M’inscrire gratuitement' }],
    indexable: true, priorite: '0.9', frequence: 'monthly',
  };
}

export function metaRecruterSoignants(): PageSEO {
  return {
    type: 'recruter', path: '/recruter-soignants',
    title: 'Recruter des soignants qualifiés | Jolene Santé',
    description: 'Recrutez infirmiers, aides-soignants et professionnels de santé vérifiés pour vos remplacements. Commission 15 % HT (18 % TTC), contrats et facturation automatiques.',
    h1: 'Recrutez des soignants qualifiés, sans intermédiaire',
    intro: ['Fini les agences de remplacement coûteuses. Publiez vos missions et recevez des candidatures de professionnels vérifiés, en toute conformité.'],
    faq: FAQ_RECRUTER_SOIGNANTS,
    liens: [{ href: '/inscription/etablissement', label: 'Créer un compte établissement' }, { href: '/tarifs', label: 'Tarifs' }],
    indexable: true, priorite: '0.9', frequence: 'monthly',
  };
}

/** Pilier soignants : parent des pages ville, métier et ville × métier dans le fil d'Ariane. */
const FIL_DEVENIR: LienSEO = { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' };

export function metaVille(ville: VilleSEO): PageSEO {
  const dept = ville.departement ? ` (${ville.departement})` : '';
  const liens: LienSEO[] = [];
  if (estVilleVilleMetier(ville.slug)) {
    for (const p of PROFESSIONS_SEO_VILLE_METIER) {
      liens.push({ href: cheminVilleMetier(ville.slug, p.slug), label: `${NOMS_METIER[p.valeur].court} : missions à ${ville.nom}` });
    }
  }
  liens.push(...VILLES_SEO.filter((v) => v.slug !== ville.slug).slice(0, 12)
    .map((v) => ({ href: cheminVille(v.slug), label: `Missions soignants à ${v.nom}` })));
  return {
    type: 'ville', path: cheminVille(ville.slug),
    title: `Missions soignants à ${ville.nom} | Jolene Santé`,
    description: `Missions de remplacement santé à ${ville.nom}${dept} : infirmiers, aides-soignants et professionnels de santé. Inscription gratuite et contrats clairement indiqués.`,
    h1: `Missions soignants à ${ville.nom}`,
    intro: [`Trouvez des remplacements et CDD courts en santé à ${ville.nom}${dept}. Hôpitaux, cliniques, EHPAD et établissements médico-sociaux.`],
    filAriane: [FIL_DEVENIR],
    liens, indexable: true, priorite: '0.6', frequence: 'monthly',
  };
}

export function metaMetier(p: ProfessionSEO): PageSEO {
  const liens: LienSEO[] = [];
  if (estProfessionVilleMetier(p.slug)) {
    for (const v of VILLES_VILLE_METIER) {
      liens.push({ href: cheminVilleMetier(v.slug, p.slug), label: `${NOMS_METIER[p.valeur].court} : missions à ${v.nom}` });
    }
  }
  liens.push(...PROFESSIONS_SEO.filter((x) => x.slug !== p.slug).slice(0, 10)
    .map((x) => ({ href: cheminMetier(x.slug), label: x.label })));
  return {
    type: 'metier', path: cheminMetier(p.slug),
    title: titreMetier(p.valeur, p.label),
    description: `${p.description} Taux horaire moyen : ${p.salaire_moyen}. Inscription gratuite, profils vérifiés et modalités de paiement affichées avant candidature.`,
    h1: `Missions ${p.label}`,
    intro: [p.description],
    filAriane: [FIL_DEVENIR],
    liens, indexable: true, priorite: '0.7', frequence: 'monthly',
  };
}

/** null si la ville n'est pas dans le périmètre ou si le métier n'est pas retenu → page noindex. */
export function resoudreVilleMetier(villeSlug?: string, professionSlug?: string): { ville: VilleSEO; profession: ProfessionSEO } | null {
  if (!villeSlug || !professionSlug) return null;
  if (!estVilleVilleMetier(villeSlug) || !estProfessionVilleMetier(professionSlug)) return null;
  const ville = getVilleBySlug(villeSlug);
  const profession = getProfessionBySlug(professionSlug);
  return ville && profession ? { ville, profession } : null;
}

export function metaVilleMetier(ville: VilleSEO, p: ProfessionSEO): PageSEO {
  const noms = NOMS_METIER[p.valeur];
  const bmo = phraseBmo(ville.departement, p.valeur);
  const intro = [
    `Vous êtes ${noms.phrase} et cherchez une mission à ${ville.nom} (département ${ville.departement}) ? Jolene met en relation des professionnels de santé vérifiés et des établissements de santé et médico-sociaux (hôpitaux, cliniques, EHPAD) pour des vacations, des CDD courts et des remplacements.`,
    p.description,
    'Le type de contrat et le taux horaire sont affichés sur chaque annonce, avant votre candidature.',
  ];
  if (bmo) intro.push(bmo);
  const liens: LienSEO[] = [
    { href: cheminVille(ville.slug), label: `Toutes les missions soignants à ${ville.nom}` },
    { href: cheminMetier(p.slug), label: `Missions ${p.label}` },
    ...villesVoisines(ville, 5).map((v) => estVilleVilleMetier(v.slug)
      ? { href: cheminVilleMetier(v.slug, p.slug), label: `${noms.court} : missions à ${v.nom}` }
      : { href: cheminVille(v.slug), label: `Missions soignants à ${v.nom}` }),
  ];
  return {
    type: 'ville-metier', path: cheminVilleMetier(ville.slug, p.slug),
    title: `${noms.court} à ${ville.nom} : missions et remplacements | Jolene Santé`,
    description: `Missions pour ${noms.pluriel} à ${ville.nom} (${ville.departement}) : remplacements, vacations et CDD courts. Inscription gratuite, contrat et taux horaire affichés avant candidature.`,
    h1: `${noms.court} : missions à ${ville.nom}`,
    // Indexée seulement si elle porte une donnée BMO propre à son département : sans elle,
    // le texte ne change que par le nom de ville (risque de pages satellites, revue B8 A2
    // de #1115). Les autres restent en ligne, en noindex et hors sitemap.
    filAriane: [FIL_DEVENIR, { href: cheminVille(ville.slug), label: `Missions soignants à ${ville.nom}` }],
    intro, liens, indexable: bmo !== null, priorite: '0.5', frequence: 'monthly',
  };
}

// ─── Données structurées (JSON-LD) ───────────────────────────────────────────
/**
 * Données structurées d'une page : celles qui lui sont propres, son fil d'Ariane et sa FAQ.
 * Même valeur dans le HTML statique (script `data-jolene-ld`) et dans `SEOHead` au montage.
 */
export function jsonLdPage(page: PageSEO): Record<string, unknown>[] {
  const blocs: Record<string, unknown>[] = [...(page.donneesStructurees ?? [])];
  if (page.type !== 'accueil') {
    const etapes: LienSEO[] = [{ href: '/', label: 'Accueil' }, ...(page.filAriane ?? []), { href: page.path, label: page.h1 }];
    blocs.push({
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      itemListElement: etapes.map((e, i) => ({ '@type': 'ListItem', position: i + 1, name: e.label, item: urlAbsolue(e.href) })),
    });
  }
  if (page.faq?.length) {
    blocs.push({
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: page.faq.map((f) => ({ '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.r } })),
    });
  }
  return blocs;
}

/** Toutes les routes SEO générées, indexables ou non (accueil compris). */
export function toutesLesRoutesSeo(): PageSEO[] {
  const pages: PageSEO[] = [metaAccueil(), ...CLES_INSTITUTIONNELLES.map(metaInstitutionnelle), metaDevenirSoignant(), metaRecruterSoignants()];
  for (const v of VILLES_SEO) pages.push(metaVille(v));
  for (const p of PROFESSIONS_SEO) pages.push(metaMetier(p));
  for (const v of VILLES_VILLE_METIER) {
    for (const p of PROFESSIONS_SEO_VILLE_METIER) pages.push(metaVilleMetier(v, p));
  }
  return pages;
}

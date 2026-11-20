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
import { ETAPES_PUBLICATION, RENVOI_COMMUN, TYPES_ETABLISSEMENT_SEO, type CleFiness, type TypeEtablissementSEO } from './seo-contenu/etablissements';
import { GUIDES_SEO, type GuideSEO } from './seo-contenu/guides';
import type { QuestionSEO, SectionSEO, SourceSEO } from './seo-contenu/types';
import { CODES_DEPARTEMENTS, DEPARTEMENTS } from './seo-departements';
import finessBrut from './seo-finess.json';

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

/** « à Lyon », « au Havre », « aux Sables-d'Olonne » : la préposition contractée avec l'article du nom. */
export function aVille(ville: Pick<VilleSEO, 'nom'>): string {
  if (ville.nom.startsWith('Le ')) return `au ${ville.nom.slice(3)}`;
  if (ville.nom.startsWith('Les ')) return `aux ${ville.nom.slice(4)}`;
  return `à ${ville.nom}`;
}
const majuscule = (texte: string) => texte.charAt(0).toUpperCase() + texte.slice(1);

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

// ─── Données BMO 2026 ────────────────────────────────────────────────────────
// Écrites par `scripts/seo/extraire-bmo.mjs` à partir du classeur officiel, publié par bassin
// d'emploi. Le total départemental est une somme faite par Jolene ; il est dit « au moins »
// quand une valeur de bassin est masquée, et la part difficile n'est donnée que si aucune
// valeur du département n'est masquée (sinon elle serait fausse, revue B8 de #1170).
// AS et MEDECIN : catégories exactes de l'enquête. IDE : l'enquête ne publie qu'un agrégat
// « Infirmiers et sages-femmes » (code V1X80) ; la phrase le dit tel quel, et la page
// sage-femme ne l'affiche pas (les infirmiers y pèsent l'essentiel). Les autres métiers
// n'ont que des agrégats trop larges (« Autres professionnels para-médicaux ») : rien n'est affiché.
export type MetierBmo = 'AS' | 'MEDECIN' | 'IDE';
/** [projets de recrutement publiés, % jugés difficiles (null = non calculable), 1 si le total est un minimum] */
export type EntreeBmo = [projets: number, part: number | null, partiel?: 0 | 1];
export type TableBmo = Record<string, Partial<Record<MetierBmo, EntreeBmo | null>>>;
export const BMO_2026: TableBmo = bmoBrut as unknown as TableBmo;

export const SOURCE_BMO = 'Enquête BMO 2026, France Travail';
export const URL_BMO = 'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo';
const LIBELLE_BMO: Record<MetierBmo, string> = { AS: 'd’aides-soignants', MEDECIN: 'de médecins', IDE: 'd’infirmiers et de sages-femmes' };
const estMetierBmo = (valeur: string): valeur is MetierBmo => valeur in LIBELLE_BMO;
const partConnue = (part: number | null | undefined): part is number => typeof part === 'number' && Number.isFinite(part);

function espaceMilliers(n: number): string {
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

/**
 * Phrase des projets de recrutement du département, ou null si aucun projet n'est publié.
 * « au moins » quand le total est un minimum ; la part difficile seulement quand elle est calculable.
 */
export function phraseBmo(departement: string, professionValeur: string, table: TableBmo = BMO_2026): string | null {
  if (!estMetierBmo(professionValeur)) return null;
  const e = table[departement]?.[professionValeur];
  if (!e) return null;
  const [projets, part, partiel] = e;
  if (typeof projets !== 'number' || !(projets > 0)) return null;
  const nb = `${partiel ? 'au moins ' : ''}${espaceMilliers(projets)} projet${projets > 1 ? 's' : ''}`;
  const difficiles = partConnue(part) ? `, dont ${Math.round(part)} % jugés difficiles` : '';
  return `Dans le département ${departement}, les employeurs déclarent ${nb} de recrutement ${LIBELLE_BMO[professionValeur]} en 2026${difficiles} (${SOURCE_BMO}).`;
}

// ─── Données FINESS (établissements recensés par ville, par département, en France) ───
// Écrites par `scripts/seo/extraire-finess.mjs` ; la date affichée est celle de l'extraction.
export interface DonneesFiness {
  source: string;
  sourceUrl: string;
  extractionDu: string;
  fichierPublieLe: string;
  colonnes: CleFiness[];
  national: number[];
  departements: Record<string, number[]>;
  villes: Record<string, number[]>;
}
export const FINESS = finessBrut as unknown as DonneesFiness;
export const URL_FINESS = 'https://www.data.gouv.fr/datasets/finess-extraction-du-fichier-des-etablissements';

const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
/** « 2026-05-04 » → « 4 mai 2026 ». */
export function dateLongue(iso: string): string {
  const [annee, mois, jour] = iso.split('-').map(Number);
  return `${jour === 1 ? '1er' : jour} ${MOIS[mois - 1]} ${annee}`;
}
export const SOURCE_FINESS = `Répertoire FINESS, extraction du ${dateLongue(FINESS.extractionDu)}`;
export const SOURCES_LOCALES: SourceSEO[] = [
  { href: URL_BMO, label: 'Enquête Besoins en main-d’œuvre 2026, France Travail (data.gouv.fr)' },
  { href: URL_FINESS, label: 'Répertoire FINESS, extraction du fichier des établissements (data.gouv.fr)' },
];

// Les hôpitaux ne sont pas cités : la catégorie FINESS des centres hospitaliers compte aussi des hôpitaux
// de jour, des CMP et des centres de dépistage, et pas la psychiatrie spécialisée (cf. extraire-finess.mjs).
const LIBELLES_FINESS: Record<CleFiness, [singulier: string, pluriel: string]> = {
  ehpad: ['EHPAD', 'EHPAD'],
  ssiad: ['service de soins infirmiers à domicile (SSIAD)', 'services de soins infirmiers à domicile (SSIAD)'],
  masfam: ['maison d’accueil spécialisée ou foyer d’accueil médicalisé', 'maisons d’accueil spécialisées et foyers d’accueil médicalisés'],
  ime: ['institut médico-éducatif (IME)', 'instituts médico-éducatifs (IME)'],
  centreSante: ['centre de santé', 'centres de santé'],
};

/** Catégories citées sur une page ville × métier : les structures où ce métier exerce le plus souvent (choix éditorial). */
const FINESS_PAR_METIER: Record<string, CleFiness[]> = {
  IDE: ['ehpad', 'ssiad', 'masfam', 'centreSante'],
  AS: ['ehpad', 'ssiad', 'masfam', 'ime'],
  AES: ['ehpad', 'masfam', 'ime'],
  MEDECIN: ['ehpad', 'centreSante'],
  KINE: ['ehpad', 'masfam', 'ime'],
  SAGE_FEMME: ['centreSante'],
};

/** « a », « a et b », « a, b et c ». */
export function enumerer(elements: string[]): string {
  if (elements.length <= 1) return elements.join('');
  return `${elements.slice(0, -1).join(', ')} et ${elements[elements.length - 1]}`;
}

/** « 44 EHPAD », « 1 centre de santé »… pour les catégories demandées dont le compte n'est pas nul. */
export function comptesFiness(compte: number[] | undefined, cles: CleFiness[], donnees: DonneesFiness = FINESS): string[] {
  if (!compte) return [];
  return cles.flatMap((cle) => {
    const n = compte[donnees.colonnes.indexOf(cle)];
    return n > 0 ? [`${espaceMilliers(n)} ${LIBELLES_FINESS[cle][n > 1 ? 1 : 0]}`] : [];
  });
}

/** Phrase des établissements recensés dans la ville, ou null si aucun n'est compté (nom de commune non rapproché). */
export function phraseFiness(ville: VilleSEO, professionValeur?: string, donnees: DonneesFiness = FINESS): string | null {
  const cles = professionValeur ? FINESS_PAR_METIER[professionValeur] ?? [] : donnees.colonnes;
  const elements = comptesFiness(donnees.villes[ville.slug], cles, donnees);
  if (elements.length === 0) return null;
  return `${majuscule(aVille(ville))}, le répertoire FINESS recense ${enumerer(elements)} (extraction du ${dateLongue(donnees.extractionDu)}).`;
}

/** Phrase du nombre national d'établissements d'un type, ou null si aucune catégorie n'est demandée. */
export function phraseFinessNationale(cles: CleFiness[], donnees: DonneesFiness = FINESS): string | null {
  const elements = comptesFiness(donnees.national, cles, donnees);
  if (elements.length === 0) return null;
  return `Le répertoire FINESS recense ${enumerer(elements)} en France (extraction du ${dateLongue(donnees.extractionDu)}).`;
}

// ─── Modèle de page ──────────────────────────────────────────────────────────
export interface LienSEO { href: string; label: string }
export interface PageSEO {
  type: 'accueil' | 'institutionnel' | 'devenir' | 'recruter' | 'etablissement' | 'ville' | 'metier' | 'ville-metier' | 'barometre' | 'guides' | 'guide';
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
  /** Date de dernière révision éditoriale (AAAA-MM-JJ) : `lastmod` du sitemap. Absente = pas de lastmod. */
  lastmod?: string;
}

export const urlAbsolue = (path: string) => `${SITE_URL}${path}`;
export const cheminVille = (villeSlug: string) => `/emploi-soignant/${villeSlug}`;
export const cheminMetier = (professionSlug: string) => `/metier/${professionSlug}`;
export const cheminVilleMetier = (villeSlug: string, professionSlug: string) => `/emploi-soignant/${villeSlug}/${professionSlug}`;
export const cheminEtablissement = (slug: string) => `/recruter-soignants/${slug}`;
export const CHEMIN_GUIDES = '/guides';
export const cheminGuide = (slug: string) => `${CHEMIN_GUIDES}/${slug}`;
export const CHEMIN_BAROMETRE = '/barometre-recrutement-soignants-2026';

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
      { href: CHEMIN_GUIDES, label: 'Guides pour soignants et établissements' },
      { href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants' },
      ...TYPES_ETABLISSEMENT_SEO.map((t) => ({ href: cheminEtablissement(t.slug), label: t.h1 })),
      ...PROFESSIONS_SEO_VILLE_METIER.map((p) => ({ href: cheminMetier(p.slug), label: `Missions ${NOMS_METIER[p.valeur].court}` })),
      ...VILLES_SEO.slice(0, NB_VILLES_ACCUEIL).map((v) => ({ href: cheminVille(v.slug), label: `Missions soignants ${aVille(v)}` })),
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
    liens: [
      { href: '/inscription/soignant', label: 'M’inscrire gratuitement' },
      ...GUIDES_SEO.filter((g) => g.public === 'soignant').map((g) => ({ href: cheminGuide(g.slug), label: g.titre })),
      { href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants' },
    ],
    indexable: true, priorite: '0.9', frequence: 'monthly',
  };
}

export function metaRecruterSoignants(): PageSEO {
  return {
    type: 'recruter', path: '/recruter-soignants',
    title: 'Recruter des soignants qualifiés | Jolene Santé',
    description: 'Recrutez infirmiers, aides-soignants et professionnels de santé vérifiés pour vos remplacements. Commission 15 % HT (18 % TTC), contrats et facturation automatiques.',
    h1: 'Recrutez des soignants qualifiés, sans intermédiaire',
    // « Fini les agences de remplacement coûteuses. » retiré : jugement sans source sur des tiers.
    intro: ['Publiez vos missions et recevez des candidatures de professionnels vérifiés, en toute conformité.'],
    faq: FAQ_RECRUTER_SOIGNANTS,
    liens: [
      { href: '/inscription/etablissement', label: 'Créer un compte établissement' },
      { href: '/tarifs', label: 'Tarifs' },
      ...TYPES_ETABLISSEMENT_SEO.map((t) => ({ href: cheminEtablissement(t.slug), label: t.h1 })),
      ...GUIDES_SEO.filter((g) => g.public === 'etablissement').map((g) => ({ href: cheminGuide(g.slug), label: g.titre })),
      { href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants' },
    ],
    indexable: true, priorite: '0.9', frequence: 'monthly',
  };
}

/** Pilier soignants : parent des pages ville, métier et ville × métier dans le fil d'Ariane. */
const FIL_DEVENIR: LienSEO = { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' };

export function metaVille(ville: VilleSEO): PageSEO {
  const dept = ville.departement ? ` (${ville.departement})` : '';
  const ou = aVille(ville);
  const liens: LienSEO[] = [];
  if (estVilleVilleMetier(ville.slug)) {
    for (const p of PROFESSIONS_SEO_VILLE_METIER) {
      liens.push({ href: cheminVilleMetier(ville.slug, p.slug), label: `${NOMS_METIER[p.valeur].court} : missions ${ou}` });
    }
  }
  liens.push(...VILLES_SEO.filter((v) => v.slug !== ville.slug).slice(0, 12)
    .map((v) => ({ href: cheminVille(v.slug), label: `Missions soignants ${aVille(v)}` })));
  liens.push({ href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants par département' });
  liens.push({ href: '/recruter-soignants', label: `Vous recrutez ${ou} ? Publier une mission` });
  const intro = [`Trouvez des remplacements et CDD courts en santé ${ou}${dept}. Hôpitaux, cliniques, EHPAD et établissements médico-sociaux.`];
  // Chiffres propres à la ville : sans eux, les 100 pages ne différeraient que par le nom de la ville.
  const finess = phraseFiness(ville);
  if (finess) intro.push(finess);
  return {
    type: 'ville', path: cheminVille(ville.slug),
    title: `Missions soignants ${ou} | Jolene Santé`,
    description: `Missions de remplacement santé ${ou}${dept} : infirmiers, aides-soignants et professionnels de santé. Inscription gratuite et contrats clairement indiqués.`,
    h1: `Missions soignants ${ou}`,
    intro,
    filAriane: [FIL_DEVENIR],
    liens, indexable: true, priorite: '0.6', frequence: 'monthly',
  };
}

export function metaMetier(p: ProfessionSEO): PageSEO {
  const liens: LienSEO[] = [];
  if (estProfessionVilleMetier(p.slug)) {
    for (const v of VILLES_VILLE_METIER) {
      liens.push({ href: cheminVilleMetier(v.slug, p.slug), label: `${NOMS_METIER[p.valeur].court} : missions ${aVille(v)}` });
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
  const ou = aVille(ville);
  const bmo = phraseBmo(ville.departement, p.valeur);
  const finess = phraseFiness(ville, p.valeur);
  const intro = [
    `Vous êtes ${noms.phrase} et cherchez une mission ${ou} (département ${ville.departement}) ? Jolene met en relation des professionnels de santé vérifiés et des établissements de santé et médico-sociaux (hôpitaux, cliniques, EHPAD) pour des vacations, des CDD courts et des remplacements.`,
    p.description,
    'Le type de contrat et le taux horaire sont affichés sur chaque annonce, avant votre candidature.',
  ];
  if (bmo) intro.push(bmo);
  if (finess) intro.push(finess);
  const liens: LienSEO[] = [
    { href: cheminVille(ville.slug), label: `Toutes les missions soignants ${ou}` },
    { href: cheminMetier(p.slug), label: `Missions ${p.label}` },
    ...villesVoisines(ville, 5).map((v) => estVilleVilleMetier(v.slug)
      ? { href: cheminVilleMetier(v.slug, p.slug), label: `${noms.court} : missions ${aVille(v)}` }
      : { href: cheminVille(v.slug), label: `Missions soignants ${aVille(v)}` }),
    { href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants par département' },
  ];
  return {
    type: 'ville-metier', path: cheminVilleMetier(ville.slug, p.slug),
    title: `${noms.court} ${ou} : missions et remplacements | Jolene Santé`,
    description: `Missions pour ${noms.pluriel} ${ou} (${ville.departement}) : remplacements, vacations et CDD courts. Inscription gratuite, contrat et taux horaire affichés avant candidature.`,
    h1: `${noms.court} : missions ${ou}`,
    filAriane: [FIL_DEVENIR, { href: cheminVille(ville.slug), label: `Missions soignants ${ou}` }],
    // Indexée seulement si elle porte une donnée BMO propre à son métier et à son département
    // (aides-soignants, médecins, infirmiers) : sans elle, le texte ne changerait que par la ville
    // et par les comptes FINESS, les mêmes pour tous les métiers de la ville (risque de pages
    // satellites, revue B8 A2 de #1115). Les autres restent en ligne, en noindex et hors sitemap.
    intro, liens, indexable: bmo !== null, priorite: '0.5', frequence: 'monthly',
  };
}

// ─── Pages « Recruter des soignants » par type d'établissement ───────────────
const FIL_RECRUTER: LienSEO = { href: '/recruter-soignants', label: 'Recruter des soignants' };

export function metaEtablissement(t: TypeEtablissementSEO): PageSEO {
  const finess = phraseFinessNationale(t.finess);
  const metiers = t.professions
    .map((valeur) => PROFESSIONS_SEO.find((p) => p.valeur === valeur))
    .filter((p): p is ProfessionSEO => !!p);
  const nomMetier = (p: ProfessionSEO) => NOMS_METIER[p.valeur]?.court ?? p.label;
  return {
    type: 'etablissement', path: cheminEtablissement(t.slug),
    title: t.title, description: t.description, h1: t.h1,
    intro: [t.accroche, t.contexte, ...(finess ? [finess] : [])],
    // Seul ce qui est propre au type est développé ici ; le reste renvoie au pilier et aux tarifs
    // (cinq pages au texte commun seraient des pages satellites).
    sections: [
      { titre: 'Les situations couvertes', points: t.situations },
      { titre: 'Les professions recherchées', liens: metiers.map((p) => ({ href: cheminMetier(p.slug), label: nomMetier(p) })) },
      { titre: 'Publier une mission en trois étapes', liste: ETAPES_PUBLICATION, ordonnee: true },
      { titre: 'Vérification, contrat, facturation et tarif', paragraphes: [RENVOI_COMMUN], liens: [FIL_RECRUTER, { href: '/tarifs', label: 'Tarifs' }] },
    ],
    faq: [
      t.question,
      { q: 'Quelles professions peut-on rechercher ?', r: `Notamment : ${enumerer(metiers.map((p) => NOMS_METIER[p.valeur]?.phrase ?? p.label))}. La profession se choisit au moment de publier la mission.` },
    ],
    filAriane: [FIL_RECRUTER],
    liens: [
      { href: '/inscription/etablissement', label: 'Créer mon espace établissement' },
      ...TYPES_ETABLISSEMENT_SEO.filter((x) => x.slug !== t.slug).map((x) => ({ href: cheminEtablissement(x.slug), label: x.h1 })),
      ...GUIDES_SEO.filter((g) => g.public === 'etablissement').map((g) => ({ href: cheminGuide(g.slug), label: g.titre })),
      { href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants' },
    ],
    indexable: true, priorite: '0.8', frequence: 'monthly',
  };
}

export function resoudreEtablissement(slug?: string): TypeEtablissementSEO | null {
  return TYPES_ETABLISSEMENT_SEO.find((t) => t.slug === slug) ?? null;
}

// ─── Guides ──────────────────────────────────────────────────────────────────
const FIL_GUIDES: LienSEO = { href: CHEMIN_GUIDES, label: 'Guides' };
/** Date de dernière révision du baromètre (données et texte) : `lastmod` du sitemap. */
export const DATE_BAROMETRE = '2026-11-20';
// Sans logo : le garde-fou 12 réserve toute référence au logo au composant LogoJolene (l'entité Organization d'index.html le porte déjà).
const ORGANISATION = { '@type': 'Organization', name: 'Jolene Santé', url: SITE_URL };

function sectionChiffres(guide: GuideSEO): SectionSEO | null {
  const phrases: string[] = [];
  const sources: SourceSEO[] = [];
  for (const c of guide.chiffres ?? []) {
    if (c === 'bmo-as-national') {
      phrases.push(`Les employeurs déclarent ${totalEnToutesLettres(totalBmo('AS'))} projets de recrutement d’aides-soignants pour 2026, en additionnant les valeurs publiées par bassin d’emploi (${SOURCE_BMO}).`);
      sources.push(SOURCES_LOCALES[0]);
    }
    if (c === 'finess-ehpad-national') {
      const phrase = phraseFinessNationale(['ehpad']);
      if (phrase) { phrases.push(phrase); sources.push(SOURCES_LOCALES[1]); }
    }
  }
  return phrases.length ? { titre: 'En chiffres', paragraphes: phrases, sources } : null;
}

export function metaGuide(g: GuideSEO): PageSEO {
  const chiffres = sectionChiffres(g);
  const [premiere, ...suite] = g.sections;
  return {
    type: 'guide', path: cheminGuide(g.slug),
    title: g.title, description: g.description, h1: g.titre,
    intro: [...g.resume, `Guide mis à jour le ${dateLongue(g.maj)}.`],
    sections: [premiere, ...(chiffres ? [chiffres] : []), ...suite],
    faq: g.faq,
    filAriane: [FIL_GUIDES],
    donneesStructurees: [{
      '@context': 'https://schema.org',
      '@type': 'Article',
      headline: g.titre,
      description: g.description,
      inLanguage: 'fr-FR',
      datePublished: g.publie,
      dateModified: g.maj,
      author: ORGANISATION,
      publisher: ORGANISATION,
      mainEntityOfPage: urlAbsolue(cheminGuide(g.slug)),
    }],
    liens: [
      ...g.liens,
      g.public === 'soignant'
        ? { href: '/inscription/soignant', label: 'Créer mon compte soignant' }
        : { href: '/inscription/etablissement', label: 'Créer mon espace établissement' },
      { href: CHEMIN_GUIDES, label: 'Tous les guides' },
    ],
    indexable: true, priorite: '0.6', frequence: 'monthly', lastmod: g.maj,
  };
}

export function resoudreGuide(slug?: string): GuideSEO | null {
  return GUIDES_SEO.find((g) => g.slug === slug) ?? null;
}

export function metaGuides(): PageSEO {
  const points = (cible: GuideSEO['public']) => GUIDES_SEO.filter((g) => g.public === cible)
    .map((g) => ({ titre: g.titre, texte: g.description, href: cheminGuide(g.slug) }));
  return {
    type: 'guides', path: CHEMIN_GUIDES,
    title: 'Guides pour soignants et établissements | Jolene Santé',
    description: 'Guides pratiques sur le remplacement en santé : chercher des vacations, préparer une première mission, remplacer un aide-soignant en EHPAD, faire face à une absence.',
    h1: 'Guides du remplacement en santé',
    intro: ['Des guides pratiques, écrits pour être utiles le jour où l’on en a besoin. Les questions de droit renvoient vers les fiches officielles ; les chiffres cités viennent de sources publiques nommées.'],
    sections: [
      { titre: 'Pour les soignants', points: points('soignant') },
      { titre: 'Pour les établissements', points: points('etablissement') },
    ],
    liens: [
      { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' },
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: CHEMIN_BAROMETRE, label: 'Baromètre 2026 du recrutement de soignants' },
    ],
    indexable: true, priorite: '0.7', frequence: 'weekly',
    lastmod: GUIDES_SEO.map((g) => g.maj).sort().at(-1),
  };
}

// ─── Baromètre par département (BMO + FINESS) ────────────────────────────────
/** Seuil de projets en dessous duquel un département n'entre pas dans le classement (petits effectifs). */
export const SEUIL_CLASSEMENT_BMO = 200;
/** Part à partir de laquelle un département est compté parmi les plus tendus. */
export const SEUIL_PART_DIFFICILE = 80;
export const NON_COMMUNIQUE = 'n.c.';
const METIERS_BAROMETRE: { metier: MetierBmo; nom: string }[] = [
  { metier: 'AS', nom: 'Aides-soignants' },
  { metier: 'IDE', nom: 'Infirmiers et sages-femmes' },
  { metier: 'MEDECIN', nom: 'Médecins' },
];
const nomDepartement = (code: string) => `${DEPARTEMENTS[code]} (${code})`;
/** Part telle que le tableau l'affiche : c'est sur cette valeur arrondie que portent les chiffres clés. */
const partAffichee = (e: EntreeBmo | null | undefined): number | null => (e && e[0] > 0 && partConnue(e[1]) ? Math.round(e[1]) : null);

/** Total national des projets publiés d'un métier, et s'il est un minimum (au moins une valeur masquée). */
export function totalBmo(metier: MetierBmo, table: TableBmo = BMO_2026): { projets: number; partiel: boolean } {
  const entrees = Object.values(table).map((d) => d[metier]).filter((e): e is EntreeBmo => !!e);
  return { projets: entrees.reduce((somme, e) => somme + e[0], 0), partiel: entrees.some((e) => !!e[2]) };
}
const totalEnToutesLettres = (t: { projets: number; partiel: boolean }) => `${t.partiel ? 'au moins ' : ''}${espaceMilliers(t.projets)}`;

export function metaBarometre(table: TableBmo = BMO_2026, finess: DonneesFiness = FINESS): PageSEO {
  const codes = CODES_DEPARTEMENTS.filter((c) => table[c]);
  const iEhpad = finess.colonnes.indexOf('ehpad');
  const ehpad = (c: string) => finess.departements[c]?.[iEhpad] ?? 0;
  const cellules = (c: string, m: MetierBmo) => {
    const e = table[c]?.[m];
    if (!e) return [NON_COMMUNIQUE, NON_COMMUNIQUE];
    // « ≥ » : total minimal, une valeur de bassin est masquée. Zéro publié et valeur masquée : on ne sait pas.
    const projets = e[2] ? (e[0] > 0 ? `≥ ${espaceMilliers(e[0])}` : NON_COMMUNIQUE) : espaceMilliers(e[0]);
    const part = partAffichee(e);
    return [projets, part === null ? NON_COMMUNIQUE : `${part} %`];
  };
  const partAs = (c: string) => partAffichee(table[c]?.AS);
  const calculables = codes.filter((c) => partAs(c) !== null);
  const tendus = calculables.filter((c) => (partAs(c) as number) >= SEUIL_PART_DIFFICILE);
  const classement = calculables
    .filter((c) => table[c]!.AS![0] >= SEUIL_CLASSEMENT_BMO)
    .sort((a, b) => (partAs(b) as number) - (partAs(a) as number) || table[b]!.AS![0] - table[a]!.AS![0])
    .slice(0, 5);
  const plusEhpad = [...codes].sort((a, b) => ehpad(b) - ehpad(a)).slice(0, 3);
  const totalEhpad = codes.reduce((somme, c) => somme + ehpad(c), 0);
  const [as, ide, medecin] = METIERS_BAROMETRE.map((m) => totalBmo(m.metier, table));
  return {
    type: 'barometre', path: CHEMIN_BAROMETRE,
    title: 'Recrutement de soignants : baromètre 2026 par département',
    description: 'Projets de recrutement d’aides-soignants, d’infirmiers et sages-femmes et de médecins déclarés pour 2026, part jugée difficile et nombre d’EHPAD, par département.',
    h1: 'Baromètre 2026 du recrutement de soignants, département par département',
    intro: [
      'Où les employeurs prévoient-ils de recruter des soignants en 2026, et où disent-ils avoir le plus de mal à y parvenir ? Ce baromètre réunit, pour chaque département, les intentions d’embauche déclarées à France Travail et le nombre d’EHPAD recensés.',
      'Les chiffres viennent de deux sources publiques, citées en bas de page. Jolene les a seulement additionnés par département, selon la méthode décrite sous le tableau.',
    ],
    sections: [
      {
        titre: 'Les chiffres clés',
        liste: [
          `Dans les ${codes.length} départements du tableau, les employeurs déclarent ${totalEnToutesLettres(as)} projets de recrutement d’aides-soignants pour 2026, ${totalEnToutesLettres(ide)} pour les infirmiers et sages-femmes et ${totalEnToutesLettres(medecin)} pour les médecins.`,
          `Dans ${tendus.length} des ${calculables.length} départements où cette part peut être calculée, au moins ${SEUIL_PART_DIFFICILE} % des projets de recrutement d’aides-soignants sont jugés difficiles par les employeurs.`,
          `Parmi ces départements, ceux qui comptent au moins ${SEUIL_CLASSEMENT_BMO} projets et où le recrutement d’aides-soignants est jugé le plus difficile : ${enumerer(classement.map((c) => `${nomDepartement(c)}, ${partAs(c)} %`))}.`,
          `Le répertoire FINESS recense ${espaceMilliers(totalEhpad)} EHPAD dans ces ${codes.length} départements ; ceux qui en comptent le plus sont ${enumerer(plusEhpad.map((c) => `${nomDepartement(c)}, ${espaceMilliers(ehpad(c))}`))}.`,
        ],
      },
      {
        titre: 'Le tableau par département',
        tableau: {
          legende: 'Projets de recrutement déclarés pour 2026 et part jugée difficile, par département, et nombre d’EHPAD',
          entetes: ['Département', ...METIERS_BAROMETRE.flatMap((m) => [`${m.nom} : projets`, `${m.nom} : part difficile`]), 'EHPAD'],
          lignes: codes.map((c) => [nomDepartement(c), ...METIERS_BAROMETRE.flatMap((m) => cellules(c, m.metier)), espaceMilliers(ehpad(c))]),
        },
      },
      {
        titre: 'Comment lire ces chiffres',
        paragraphes: [
          'L’enquête Besoins en main-d’œuvre (BMO) de France Travail interroge chaque année les employeurs sur leurs intentions d’embauche pour l’année à venir. Un projet de recrutement est une intention déclarée, pas une embauche réalisée. Il est dit difficile quand l’employeur s’attend à avoir du mal à le pourvoir.',
          'L’enquête est publiée par bassin d’emploi. Pour chaque département, Jolene a additionné les projets publiés de ses bassins ; un bassin qui n’a pas de ligne pour un métier est compté pour zéro.',
          'Le fichier remplace certaines valeurs par un astérisque. Quand c’est un nombre de projets, le total du département est un minimum, noté « ≥ ». Quand c’est un nombre de projets difficiles, le total reste exact mais la part n’est pas calculée, notée « n.c. ». Une part n’est donnée que lorsque toutes les valeurs du département sont publiées.',
          'L’enquête range les infirmiers et les sages-femmes dans une seule catégorie : le tableau ne peut pas les distinguer.',
          `Le nombre d’EHPAD est celui des établissements d’hébergement pour personnes âgées dépendantes inscrits au répertoire FINESS (extraction du ${dateLongue(finess.extractionDu)}).`,
        ],
        sources: SOURCES_LOCALES,
      },
      {
        titre: 'Ce que ces chiffres changent pour vous',
        paragraphes: [
          'Vous dirigez un établissement : là où la plupart des projets sont jugés difficiles, mieux vaut anticiper les absences prévisibles et ne pas compter sur un seul canal de remplacement.',
          'Vous êtes soignant : ces chiffres indiquent où les employeurs disent avoir le plus de mal à recruter. Ils ne garantissent ni un volume de missions ni un niveau de rémunération.',
        ],
      },
    ],
    donneesStructurees: [{
      '@context': 'https://schema.org',
      '@type': 'Dataset',
      name: 'Baromètre 2026 du recrutement de soignants par département',
      description: 'Projets de recrutement d’aides-soignants, d’infirmiers et sages-femmes et de médecins déclarés pour 2026 (enquête BMO de France Travail, publiée par bassin d’emploi et additionnée par département), part jugée difficile lorsqu’elle est calculable, et nombre d’EHPAD (répertoire FINESS).',
      url: urlAbsolue(CHEMIN_BAROMETRE),
      inLanguage: 'fr-FR',
      temporalCoverage: '2026',
      spatialCoverage: { '@type': 'Place', name: 'France' },
      isBasedOn: [URL_BMO, URL_FINESS],
      creator: ORGANISATION,
    }],
    liens: [
      { href: '/recruter-soignants', label: 'Recruter des soignants' },
      { href: '/devenir-soignant', label: 'Devenir soignant sur Jolene' },
      { href: CHEMIN_GUIDES, label: 'Guides du remplacement en santé' },
      ...VILLES_VILLE_METIER.slice(0, 12).map((v) => ({ href: cheminVille(v.slug), label: `Missions soignants ${aVille(v)}` })),
    ],
    indexable: true, priorite: '0.7', frequence: 'yearly', lastmod: DATE_BAROMETRE,
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
  for (const t of TYPES_ETABLISSEMENT_SEO) pages.push(metaEtablissement(t));
  pages.push(metaBarometre(), metaGuides(), ...GUIDES_SEO.map(metaGuide));
  return pages;
}

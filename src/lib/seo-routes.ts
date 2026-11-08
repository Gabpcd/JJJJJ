/**
 * Source de vérité unique des pages SEO publiques (titres, descriptions, H1,
 * textes d'introduction, maillage interne, indexabilité).
 *
 * Consommée par les composants React (VilleLanding, ProfessionLanding,
 * VilleProfessionLanding) ET par `scripts/seo/generer-pages-statiques.mjs`
 * (HTML statique crawlable + sitemap). Module pur : aucun import React/DOM.
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
};

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
  type: 'devenir' | 'recruter' | 'ville' | 'metier' | 'ville-metier';
  path: string;
  title: string;
  description: string;
  h1: string;
  intro: string[];
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

export function metaDevenirSoignant(): PageSEO {
  return {
    type: 'devenir', path: '/devenir-soignant',
    title: 'Devenir soignant remplaçant | Jolene Santé',
    description: 'Missions de remplacement santé pour infirmiers, aides-soignants et professionnels de santé. Inscription gratuite, rémunération transparente et contrat indiqué avant candidature.',
    h1: 'Devenir soignant sur Jolene',
    intro: ['Accédez à des centaines de missions de remplacement en santé, choisissez vos horaires et construisez votre parcours professionnel.'],
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
    liens: [{ href: '/inscription/etablissement', label: 'Créer un compte établissement' }],
    indexable: true, priorite: '0.9', frequence: 'monthly',
  };
}

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
    title: `Missions ${p.label} — remplacements & CDD courts | Jolene Santé`,
    description: `${p.description} Taux horaire moyen : ${p.salaire_moyen}. Inscription gratuite, profils vérifiés et modalités de paiement affichées avant candidature.`,
    h1: `Missions ${p.label}`,
    intro: [p.description],
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
    intro, liens, indexable: bmo !== null, priorite: '0.5', frequence: 'monthly',
  };
}

/** Toutes les routes SEO générées, indexables ou non (accueil exclu). */
export function toutesLesRoutesSeo(): PageSEO[] {
  const pages: PageSEO[] = [metaDevenirSoignant(), metaRecruterSoignants()];
  for (const v of VILLES_SEO) pages.push(metaVille(v));
  for (const p of PROFESSIONS_SEO) pages.push(metaMetier(p));
  for (const v of VILLES_VILLE_METIER) {
    for (const p of PROFESSIONS_SEO_VILLE_METIER) pages.push(metaVilleMetier(v, p));
  }
  return pages;
}

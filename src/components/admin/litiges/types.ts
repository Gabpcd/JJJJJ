/**
 * CP-LITIGES-7b-2 — types + constantes front pour la refonte UI
 * AdminModeration. Les types Supabase générés sont stale pour les
 * colonnes ajoutées en CP1-CP7a (type_litige, categorie_litige,
 * est_informatif, montant_tresorerie_bloquee, facture_id...). On
 * définit ici la shape utile côté front jusqu'à regénération.
 */

export const TYPES_LITIGE = [
  'ABSENCE_SOIGNANT',
  'DEPART_ANTICIPE',
  'RETARD_IMPORTANT',
  'DESACCORD_MONTANT_FACTURE',
  'DESACCORD_HEURES_POINTAGE',
  'NON_PAIEMENT',
  'FRAIS_COMPLEMENTAIRES',
  'CONDITIONS_MISSION_NON_RESPECTEES',
  'SECURITE_DANGER',
  'COMPORTEMENT_SOIGNANT',
  'COMPORTEMENT_ETABLISSEMENT',
  'AUTRE',
] as const;
export type TypeLitige = (typeof TYPES_LITIGE)[number];

export const CATEGORIES_LITIGE = [
  'PRESENCE',
  'FINANCIER',
  'CONDITIONS',
  'COMPORTEMENT',
  'AUTRE',
] as const;
export type CategorieLitige = (typeof CATEGORIES_LITIGE)[number];

export const STATUTS_OUVERTS = [
  'OUVERT',
  'EN_DISCUSSION',
  'EN_MEDIATION',
  'CONTESTEE',
] as const;
export type StatutLitigeOuvert = (typeof STATUTS_OUVERTS)[number];

export const ACTIONS_FINANCIERES = [
  'AUTO',
  'RECALCUL',
  'ANNULER_REEMETTRE',
  'AVOIR',
  'COMPLEMENT',
] as const;
export type ActionFinanciere = (typeof ACTIONS_FINANCIERES)[number];

export const EN_FAVEUR_DE = ['SOIGNANT', 'ETABLISSEMENT', 'NEUTRE'] as const;
export type EnFaveurDe = (typeof EN_FAVEUR_DE)[number];

export const LABELS_TYPE_LITIGE: Record<TypeLitige, string> = {
  ABSENCE_SOIGNANT: 'Absence du soignant',
  DEPART_ANTICIPE: 'Départ anticipé',
  RETARD_IMPORTANT: 'Retard important',
  DESACCORD_MONTANT_FACTURE: 'Désaccord montant facture',
  DESACCORD_HEURES_POINTAGE: 'Désaccord heures pointage',
  NON_PAIEMENT: 'Non-paiement',
  FRAIS_COMPLEMENTAIRES: 'Frais complémentaires',
  CONDITIONS_MISSION_NON_RESPECTEES: 'Conditions mission non respectées',
  SECURITE_DANGER: 'Sécurité / danger',
  COMPORTEMENT_SOIGNANT: 'Comportement soignant',
  COMPORTEMENT_ETABLISSEMENT: 'Comportement établissement',
  AUTRE: 'Autre',
};

export const LABELS_CATEGORIE: Record<CategorieLitige, string> = {
  PRESENCE: 'Présence',
  FINANCIER: 'Financier',
  CONDITIONS: 'Conditions',
  COMPORTEMENT: 'Comportement',
  AUTRE: 'Autre',
};

export const LABELS_STATUT: Record<StatutLitigeOuvert, string> = {
  OUVERT: 'Ouvert',
  EN_DISCUSSION: 'En discussion',
  EN_MEDIATION: 'En médiation',
  CONTESTEE: 'Contestée',
};

export const LABELS_ACTION_FINANCIERE: Record<
  ActionFinanciere,
  { label: string; tooltip: string }
> = {
  AUTO: {
    label: 'Auto (par défaut)',
    tooltip:
      'Le serveur choisit : recalcul du brouillon, remplacement avant paiement, avoir si le payé baisse, facture complémentaire s’il augmente, ou rectification descriptive si le total payé ne change pas.',
  },
  RECALCUL: {
    label: 'Recalcul',
    tooltip:
      'Modifie la facture en BROUILLON directement. Disponible immédiatement, sans émettre de document comptable.',
  },
  ANNULER_REEMETTRE: {
    label: 'Annuler + réémettre',
    tooltip:
      'Remplace la facture courante (ÉMISE ou EN RETARD) par une nouvelle facture avec les montants ajustés.',
  },
  AVOIR: {
    label: 'Avoir partiel',
    tooltip:
      'Émet un avoir sur une facture payée pour une correction à la baisse. Une hausse est refusée.',
  },
  COMPLEMENT: {
    label: 'Facture complémentaire',
    tooltip:
      'Sur une facture déjà payée corrigée à la hausse, facture uniquement le delta supplémentaire et conserve l’originale.',
  },
};

export const LABELS_EN_FAVEUR_DE: Record<EnFaveurDe, string> = {
  SOIGNANT: 'Soignant',
  ETABLISSEMENT: 'Établissement',
  NEUTRE: 'Neutre',
};

/**
 * Ordre de gravité (rang 1 = le plus grave, en tête de liste).
 * SECURITE_DANGER > COMPORTEMENT_* > FINANCIER (NON_PAIEMENT d'abord)
 *  > PRESENCE > CONDITIONS > AUTRE
 */
export function rangGravite(l: {
  type_litige?: string | null;
  categorie_litige?: string | null;
}): number {
  if (l.type_litige === 'SECURITE_DANGER') return 1;
  if (
    l.type_litige === 'COMPORTEMENT_SOIGNANT' ||
    l.type_litige === 'COMPORTEMENT_ETABLISSEMENT' ||
    l.categorie_litige === 'COMPORTEMENT'
  )
    return 2;
  if (l.type_litige === 'NON_PAIEMENT') return 3;
  if (l.categorie_litige === 'FINANCIER') return 4;
  if (l.categorie_litige === 'PRESENCE') return 5;
  if (l.categorie_litige === 'CONDITIONS') return 6;
  return 7;
}

export type BadgeCouleur = 'rouge' | 'orange' | 'jaune' | 'vert' | 'gris';

export function couleurBadgeCategorie(
  categorie?: string | null,
  type?: string | null,
): BadgeCouleur {
  if (type === 'SECURITE_DANGER') return 'rouge';
  if (categorie === 'COMPORTEMENT') return 'rouge';
  if (categorie === 'FINANCIER') return 'orange';
  if (categorie === 'PRESENCE') return 'jaune';
  if (categorie === 'CONDITIONS') return 'vert';
  return 'gris';
}

export const CLASSES_BADGE_COULEUR: Record<BadgeCouleur, string> = {
  rouge: 'bg-red-100 text-red-800 border-red-200',
  orange: 'bg-orange-100 text-orange-800 border-orange-200',
  jaune: 'bg-yellow-100 text-yellow-800 border-yellow-200',
  vert: 'bg-green-100 text-green-800 border-green-200',
  gris: 'bg-gray-100 text-gray-800 border-gray-200',
};

export type LitigeEnrichi = {
  id: string;
  motif: string;
  reponse: string | null;
  statut: string;
  cree_le: string;
  soignant_id: string;
  etablissement_id: string;
  mission_id: string;
  initie_par: 'SOIGNANT' | 'ETABLISSEMENT' | 'SYSTEME';
  resolution: string | null;
  resolu_le: string | null;
  type_litige?: TypeLitige | null;
  categorie_litige?: CategorieLitige | null;
  est_informatif?: boolean | null;
  montant_tresorerie_bloquee?: number | null;
  facture_id?: string | null;
  escalade_auto_le?: string | null;
  payload_modifications?: {
    type: string;
    modifications: Record<string, string | number | boolean | null>;
    justification: string;
  } | null;
  soignant?: {
    id: string;
    prenom: string | null;
    nom: string | null;
    email: string | null;
    telephone: string | null;
    profession: string | null;
  } | null;
  etablissement?: {
    id: string;
    nom: string;
    email_contact: string | null;
    telephone_contact: string | null;
    type: string | null;
  } | null;
  mission?: {
    id: string;
    intitule: string;
    profession_requise: string;
    service: string | null;
    debut_le: string;
    fin_le: string;
    statut: string | null;
    duree_heures: number | null;
    taux_horaire_base: number | null;
    taux_horaire_base_fige: number | null;
    taux_rist_plafonne: number | null;
    rist_plafond_applique: boolean | null;
    type_contrat_applique: string | null;
  } | null;
};

export type FiltresLitiges = {
  type_litige: TypeLitige | 'TOUS';
  categorie_litige: CategorieLitige | 'TOUTES';
  statut: StatutLitigeOuvert | 'TOUS_OUVERTS';
  tri: 'GRAVITE' | 'TRESORERIE' | 'ESCALADE_MEDIATION';
};

export const FILTRES_DEFAUT: FiltresLitiges = {
  type_litige: 'TOUS',
  categorie_litige: 'TOUTES',
  statut: 'TOUS_OUVERTS',
  tri: 'GRAVITE',
};

export function joursDepuis(dateIso: string | null | undefined): number {
  if (!dateIso) return 0;
  const diff = Date.now() - new Date(dateIso).getTime();
  return Math.max(0, Math.floor(diff / (1000 * 60 * 60 * 24)));
}

export function alerteTresorerie(litige: {
  cree_le: string;
  montant_tresorerie_bloquee?: number | null;
}): boolean {
  const j = joursDepuis(litige.cree_le);
  const m = Number(litige.montant_tresorerie_bloquee ?? 0);
  return j > 5 && m > 500;
}

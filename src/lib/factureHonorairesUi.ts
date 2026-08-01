export type StatutFactureHonoraires =
  | 'BROUILLON'
  | 'EN_GENERATION'
  | 'EMISE'
  | 'EN_ATTENTE_PAIEMENT'
  | 'EN_RETARD'
  | 'PAYEE'
  | 'FACTORISEE'
  | 'ANNULEE'
  | 'REMPLACEE'
  | 'ERREUR_GENERATION'
  | 'REMBOURSE';

export interface FactureHonorairesPourUi {
  id: string;
  mission_id?: string | null;
  numero_facture?: string | null;
  type_document?: string | null;
  montant_signe?: number | string | null;
  statut?: string | null;
  montant_ttc?: number | string | null;
  date_emission?: string | null;
  cree_le?: string | null;
}

export interface ResumeFacturesMission {
  montantPaye: number;
  montantEnAttente: number;
  nbPayees: number;
  nbEnAttente: number;
  nbEnRetard: number;
  nbFacturesValides: number;
}

export const LIBELLES_STATUT_FACTURE: Record<StatutFactureHonoraires, string> = {
  BROUILLON: 'Brouillon',
  EN_GENERATION: 'Génération en cours',
  EMISE: 'Émise',
  EN_ATTENTE_PAIEMENT: 'En attente de paiement',
  EN_RETARD: 'En retard',
  PAYEE: 'Payée',
  FACTORISEE: 'Avance reçue',
  ANNULEE: 'Annulée',
  REMPLACEE: 'Remplacée',
  ERREUR_GENERATION: 'Erreur de génération',
  REMBOURSE: 'Remboursée',
};

const STATUTS_COMPTABILISABLES = new Set<string>([
  'EMISE',
  'EN_ATTENTE_PAIEMENT',
  'EN_RETARD',
  'PAYEE',
  'FACTORISEE',
]);

const STATUTS_PAYES = new Set<string>(['PAYEE', 'FACTORISEE']);
const STATUTS_EN_ATTENTE = new Set<string>(['EMISE', 'EN_ATTENTE_PAIEMENT', 'EN_RETARD']);
const STATUTS_AVOIRS_NON_COMPTABILISABLES = new Set<string>([
  'BROUILLON',
  'EN_GENERATION',
  'ANNULEE',
  'REMPLACEE',
  'ERREUR_GENERATION',
]);

export function statutFactureConnu(statut: string | null | undefined): statut is StatutFactureHonoraires {
  return statut != null && Object.prototype.hasOwnProperty.call(LIBELLES_STATUT_FACTURE, statut);
}

export function libelleStatutFacture(statut: string | null | undefined): string {
  return statutFactureConnu(statut) ? LIBELLES_STATUT_FACTURE[statut] : `Statut inconnu (${statut || '—'})`;
}

/** Un PDF n'existe qu'après une génération terminée avec succès. */
export function facturePdfDisponible(statut: string | null | undefined): boolean {
  return statutFactureConnu(statut)
    && !['BROUILLON', 'EN_GENERATION', 'ERREUR_GENERATION'].includes(statut);
}

/**
 * Le RPC historique `fn_mes_factures_honoraires` ne renvoie pas encore le type
 * du document. Les consommateurs l'enrichissent avec la table RLS, mais ce
 * garde-fou sait aussi reconnaître les numéros d'avoirs historiques `AV-*` et
 * le montant HT signé. Un type explicite inconnu est traité comme un document
 * d'ajustement : il ne doit jamais gonfler un revenu par défaut.
 */
export function factureEstAvoir(facture: FactureHonorairesPourUi): boolean {
  if (facture.type_document === 'AVOIR') return true;
  if (facture.type_document === 'FACTURE') return false;
  if (facture.type_document) return true;

  const montantSigne = Number(facture.montant_signe);
  if (Number.isFinite(montantSigne) && montantSigne !== 0) return montantSigne < 0;

  return /^AV(?:OIR)?[-_/]/i.test(facture.numero_facture?.trim() ?? '');
}

/** Montant TTC signé pour les agrégats : un avoir diminue toujours le total. */
export function montantTtcSigneFacture(facture: FactureHonorairesPourUi): number {
  const montant = Math.abs(Number(facture.montant_ttc) || 0);
  return factureEstAvoir(facture) ? -montant : montant;
}

/**
 * Fusionne les champs absents du RPC avec une lecture directe protégée par RLS.
 * Les valeurs métier du RPC restent prioritaires, sauf les métadonnées qui ne
 * font pas partie de son contrat historique.
 */
export function enrichirFacturesHonoraires<T extends FactureHonorairesPourUi>(
  factures: T[],
  metadonnees: Array<Partial<FactureHonorairesPourUi> & { id: string }>,
): T[] {
  const parId = new Map(metadonnees.map((metadata) => [metadata.id, metadata]));
  return factures.map((facture) => {
    const metadata = parId.get(facture.id);
    return metadata ? { ...facture, ...metadata, id: facture.id } : facture;
  });
}

export function factureCompteDansTotal(facture: FactureHonorairesPourUi): boolean {
  if (factureEstAvoir(facture)) {
    return !STATUTS_AVOIRS_NON_COMPTABILISABLES.has(facture.statut ?? '');
  }
  return STATUTS_COMPTABILISABLES.has(facture.statut ?? '');
}

export function totalFacturesComptabilisables(factures: FactureHonorairesPourUi[]): number {
  return factures.reduce(
    (total, facture) => total + (factureCompteDansTotal(facture) ? montantTtcSigneFacture(facture) : 0),
    0,
  );
}

export function totalFacturesPayees(factures: FactureHonorairesPourUi[]): number {
  return factures.reduce(
    (total, facture) => total + (
      !factureEstAvoir(facture) && STATUTS_PAYES.has(facture.statut ?? '')
        ? Math.abs(Number(facture.montant_ttc) || 0)
        : 0
    ),
    0,
  );
}

export function totalFacturesEnAttente(factures: FactureHonorairesPourUi[]): number {
  return factures.reduce(
    (total, facture) => total + (
      !factureEstAvoir(facture) && STATUTS_EN_ATTENTE.has(facture.statut ?? '')
        ? Math.abs(Number(facture.montant_ttc) || 0)
        : 0
    ),
    0,
  );
}

/**
 * Agrège toutes les factures hebdomadaires d'une mission. Aucune facture
 * unique n'est choisie : une facture payée et une autre en retard restent
 * visibles dans deux étapes distinctes avec leurs montants exacts.
 */
export function resumerFacturesMission(
  factures: FactureHonorairesPourUi[],
): ResumeFacturesMission {
  return factures.reduce<ResumeFacturesMission>((resume, facture) => {
    if (factureEstAvoir(facture)) return resume;

    const statut = facture.statut ?? '';
    const montant = Math.abs(Number(facture.montant_ttc) || 0);
    if (STATUTS_PAYES.has(statut)) {
      resume.montantPaye += montant;
      resume.nbPayees += 1;
      resume.nbFacturesValides += 1;
    } else if (STATUTS_EN_ATTENTE.has(statut)) {
      resume.montantEnAttente += montant;
      resume.nbEnAttente += 1;
      resume.nbEnRetard += Number(statut === 'EN_RETARD');
      resume.nbFacturesValides += 1;
    }
    return resume;
  }, {
    montantPaye: 0,
    montantEnAttente: 0,
    nbPayees: 0,
    nbEnAttente: 0,
    nbEnRetard: 0,
    nbFacturesValides: 0,
  });
}

export function regrouperFacturesParMission<T extends FactureHonorairesPourUi>(
  factures: T[],
): Record<string, T[]> {
  const groupes: Record<string, T[]> = {};
  factures.forEach((facture) => {
    if (!facture.mission_id) return;
    (groupes[facture.mission_id] ??= []).push(facture);
  });
  return groupes;
}

const PRIORITE_AFFICHAGE: Record<string, number> = {
  PAYEE: 100,
  FACTORISEE: 95,
  EN_RETARD: 90,
  EN_ATTENTE_PAIEMENT: 85,
  EMISE: 80,
  EN_GENERATION: 50,
  BROUILLON: 40,
  REMBOURSE: 30,
  REMPLACEE: 20,
  ANNULEE: 10,
  ERREUR_GENERATION: 0,
};

function instantTri(facture: FactureHonorairesPourUi): number {
  const valeur = facture.cree_le ?? facture.date_emission;
  const instant = valeur ? new Date(valeur).getTime() : 0;
  return Number.isFinite(instant) ? instant : 0;
}

/**
 * Choisit la facture métier la plus utile, puis départage de façon stable par
 * date de création et identifiant. Une erreur technique du même jour ne masque
 * ainsi jamais une facture émise ou payée.
 */
export function selectionnerFactureAffichable<T extends FactureHonorairesPourUi>(factures: T[]): T | null {
  if (factures.length === 0) return null;
  return [...factures].sort((a, b) => {
    const priorite = (PRIORITE_AFFICHAGE[b.statut ?? ''] ?? -1) - (PRIORITE_AFFICHAGE[a.statut ?? ''] ?? -1);
    if (priorite !== 0) return priorite;
    const date = instantTri(b) - instantTri(a);
    if (date !== 0) return date;
    return b.id.localeCompare(a.id);
  })[0];
}

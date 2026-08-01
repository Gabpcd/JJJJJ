export interface AdminInvoiceAccountingRow {
  statut?: string | null;
  type_document?: string | null;
  date_echeance?: string | null;
  montant_signe?: number | null;
  montant_ht?: number | null;
  montant_tva?: number | null;
  montant_ttc?: number | null;
}

export type InvoiceAmountField = 'ht' | 'tva' | 'ttc';

const STATUTS_EXCLUS_COMPTABILITE = new Set(['BROUILLON', 'ANNULEE']);

const montantNombre = (valeur: number | null | undefined): number =>
  typeof valeur === 'number' && Number.isFinite(valeur) ? valeur : 0;

/** Un brouillon ou un document annulé ne contribue jamais aux indicateurs comptables. */
export function estDocumentComptabilise(facture: AdminInvoiceAccountingRow): boolean {
  return !STATUTS_EXCLUS_COMPTABILITE.has(facture.statut ?? '');
}

export function jourCivilParis(date: Date): string | null {
  if (Number.isNaN(date.getTime())) return null;
  const parts = new Intl.DateTimeFormat('fr-FR', {
    timeZone: 'Europe/Paris',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find(item => item.type === type)?.value;
  const annee = part('year');
  const mois = part('month');
  const jour = part('day');
  return annee && mois && jour ? `${annee}-${mois}-${jour}` : null;
}

/**
 * Une facture n'est relançable qu'après son échéance.
 *
 * `EMISE` signifie « envoyée », pas « impayée ». Le statut `EN_RETARD` reste
 * accepté sans date d'échéance pour les anciennes lignes déjà qualifiées par
 * le back-office, mais une date future gagne toujours sur ce statut afin de ne
 * jamais relancer prématurément un établissement.
 */
export function estFactureRelancable(
  facture: AdminInvoiceAccountingRow,
  maintenant: Date = new Date(),
): boolean {
  if (facture.type_document !== 'FACTURE') return false;
  if (facture.statut !== 'EMISE' && facture.statut !== 'EN_RETARD') return false;

  if (!facture.date_echeance) return facture.statut === 'EN_RETARD';
  const echeance = facture.date_echeance.match(/^\d{4}-\d{2}-\d{2}/)?.[0];
  const aujourdhui = jourCivilParis(maintenant);
  if (!echeance || !aujourdhui) return false;
  return echeance < aujourdhui;
}

function signeDocument(facture: AdminInvoiceAccountingRow): 1 | -1 {
  if (facture.type_document === 'AVOIR') return -1;
  return montantNombre(facture.montant_signe) < 0 ? -1 : 1;
}

/**
 * Retourne le montant signé à utiliser dans les totaux, graphiques et exports.
 * `montant_signe` est la source de vérité du HT ; TVA/TTC héritent du signe du
 * document puisque leurs colonnes sont stockées en valeur absolue.
 */
export function montantDocumentComptable(
  facture: AdminInvoiceAccountingRow,
  champ: InvoiceAmountField,
): number {
  if (!estDocumentComptabilise(facture)) return 0;

  const signe = signeDocument(facture);
  if (champ === 'ht') {
    const montantSigne = facture.montant_signe;
    if (typeof montantSigne === 'number' && Number.isFinite(montantSigne)) {
      return facture.type_document === 'AVOIR' ? -Math.abs(montantSigne) : montantSigne;
    }
    return signe * Math.abs(montantNombre(facture.montant_ht));
  }

  const montant = champ === 'tva' ? facture.montant_tva : facture.montant_ttc;
  return signe * Math.abs(montantNombre(montant));
}

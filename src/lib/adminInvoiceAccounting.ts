export interface AdminInvoiceAccountingRow {
  statut?: string | null;
  type_document?: string | null;
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

/** Les relances ne concernent que les factures, jamais les avoirs. */
export function estFactureRelancable(facture: AdminInvoiceAccountingRow): boolean {
  return facture.type_document === 'FACTURE'
    && (facture.statut === 'EMISE' || facture.statut === 'EN_RETARD');
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

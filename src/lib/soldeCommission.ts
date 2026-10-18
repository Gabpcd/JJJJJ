import { lireSoldeCommission, type FactureSoldeCommission } from '../../supabase/functions/_shared/commission-balance';

export { lireSoldeCommission };

/** Une projection absente ne vaut jamais zéro crédit ou autorisation de payer. */
export function soldeCommissionPourAffichage(facture: Partial<FactureSoldeCommission>) {
  try { return lireSoldeCommission(facture as FactureSoldeCommission); } catch { return null; }
}

export const formatMontantCommission = (centimes: number) =>
  new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(centimes / 100);

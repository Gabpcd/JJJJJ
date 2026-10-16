/** Même cascade que le gel financier : établissement, groupe, puis 15 % HT. */
export function tauxCommissionEtablissement(etablissement: {
  taux_commission_effectif?: number | null;
  taux_commission_negocie?: number | null;
  groupes_sante?: { taux_commission_negocie?: number | null } | null;
} | null | undefined): number {
  return Number(etablissement?.taux_commission_effectif
    ?? etablissement?.taux_commission_negocie
    ?? etablissement?.groupes_sante?.taux_commission_negocie
    ?? 15);
}

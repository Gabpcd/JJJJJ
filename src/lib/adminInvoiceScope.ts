export type FactureAvecPerimetre = {
  etablissements?: {
    nom?: string | null;
    est_compte_test?: boolean | null;
  } | null;
};

export function estFactureProduction(facture: FactureAvecPerimetre): boolean {
  return facture.etablissements?.est_compte_test === false;
}

export function perimetreFacture(
  facture: FactureAvecPerimetre,
): 'PRODUCTION' | 'TEST' | 'A_VERIFIER' {
  if (estFactureProduction(facture)) return 'PRODUCTION';
  if (facture.etablissements?.est_compte_test === true) return 'TEST';
  return 'A_VERIFIER';
}

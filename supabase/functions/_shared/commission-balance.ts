/** Montants documentaires et montant externe figé, y compris après règlement. */
export type FactureSoldeCommission = {
  montant_ttc: unknown;
  montant_avoirs_imputes: unknown;
  montant_a_payer: unknown;
  statut: unknown;
  type_document: unknown;
  rapprochement_paiement_requis: unknown;
};

function centimes(value: unknown): number {
  if ((typeof value !== "number" && typeof value !== "string")
    || typeof value === "string" && !/^\d+(?:\.\d{1,2})?$/.test(value)
    || !Number.isFinite(Number(value)) || Number(value) < 0) {
    throw new Error("SOLDE_COMMISSION_INVALIDE");
  }
  const cents = Math.round(Number(value) * 100);
  if (!Number.isSafeInteger(cents) || Math.abs(Number(value) * 100 - cents) > 1e-7) {
    throw new Error("SOLDE_COMMISSION_INVALIDE");
  }
  return cents;
}

export function lireSoldeCommission(facture: FactureSoldeCommission): {
  montantDocumentCents: number; avoirsImputesCents: number; montantExterneCents: number;
  resteDuCents: number; rapprochementRequis: boolean;
} {
  // Aucun repli sur le TTC : une projection SQL incomplète doit échouer fermée.
  const ttcCents = centimes(facture.montant_ttc);
  const avoirsCents = centimes(facture.montant_avoirs_imputes);
  const aPayerCents = centimes(facture.montant_a_payer);
  if (avoirsCents > ttcCents || aPayerCents !== ttcCents - avoirsCents) {
    throw new Error("SOLDE_COMMISSION_INCOHERENT");
  }
  if (typeof facture.rapprochement_paiement_requis !== "boolean"
    || typeof facture.statut !== "string"
    || !["BROUILLON", "EMISE", "EN_RETARD", "VIREMENT_DECLARE", "PAYEE", "ANNULEE", "REMPLACEE", "ERREUR_GENERATION"].includes(facture.statut)
    || typeof facture.type_document !== "string"
    || !["FACTURE", "FACTURE_COMPLEMENTAIRE", "AVOIR"].includes(String(facture.type_document))) {
    throw new Error("SOLDE_COMMISSION_INVALIDE");
  }
  return {
    montantDocumentCents: ttcCents, avoirsImputesCents: avoirsCents, montantExterneCents: aPayerCents,
    resteDuCents: facture.type_document !== "AVOIR"
      && ["EMISE", "EN_RETARD", "VIREMENT_DECLARE"].includes(facture.statut) ? aPayerCents : 0,
    rapprochementRequis: facture.rapprochement_paiement_requis,
  };
}

export function estSoldeeParAvoir(facture: FactureSoldeCommission & {
  statut: unknown; mode_paiement: unknown; stripe_payment_intent_id?: unknown;
}): boolean {
  const solde = lireSoldeCommission(facture);
  return solde.montantExterneCents === 0 && solde.avoirsImputesCents > 0
    && facture.statut === "PAYEE" && facture.mode_paiement === "AVOIR"
    && facture.stripe_payment_intent_id == null;
}

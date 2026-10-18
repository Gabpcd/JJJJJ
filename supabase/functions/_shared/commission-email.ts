import { lireSoldeCommission } from "./commission-balance.ts";

export function aSoldeCommissionEmail(data: Record<string, unknown>): boolean {
  return Object.hasOwn(data, "montant_avoirs_imputes") || Object.hasOwn(data, "montant_a_payer");
}

/** Vérifie aussi les anciens corps sans les réécrire (idempotence fournisseur). */
export async function verifierSoldeCommissionEmail(
  client: { from(table: string): any }, type: string, data: Record<string, unknown>, destinataireId: unknown,
): Promise<void> {
  if (!["FACTURE_EMISE", "FACTURE_PAYEE", "RAPPEL_FACTURE", "CHARGE_FAILED_ETAB", "RAPPEL_PAIEMENT_J7", "PAIEMENT_RETARD_J21"].includes(type)
    || data.famille_document === "HONORAIRES"
    || ["RAPPEL_PAIEMENT_J7", "PAIEMENT_RETARD_J21"].includes(type) && data.type_obligation !== "FACTURE_COMMISSION") return;
  let query = client.from("factures").select("id, etablissement_id, type_document, statut, mode_paiement, montant_ttc, montant_avoirs_imputes, montant_a_payer, rapprochement_paiement_requis");
  if (typeof data.facture_id === "string" && data.facture_id) query = query.eq("id", data.facture_id);
  else if (typeof (data.numero_facture ?? data.numero) === "string") {
    query = query.eq("numero_facture", data.numero_facture ?? data.numero).eq("etablissement_id", destinataireId);
  } else throw new Error("SOLDE_COMMISSION_EMAIL_SOURCE_ABSENTE");
  const { data: facture, error } = await query.maybeSingle();
  // L'ancien corps honoraires sans famille a déjà une source documentaire unique
  // vérifiée par resolveFacturationEmailSource, avant d'arriver ici.
  if (!error && !facture && type === "FACTURE_EMISE" && data.famille_document == null) return;
  if (error || !facture || facture.etablissement_id !== destinataireId) throw new Error("SOLDE_COMMISSION_EMAIL_SOURCE_INCOHERENTE");
  const solde = lireSoldeCommission(facture);
  if (solde.rapprochementRequis) throw new Error("RAPPROCHEMENT_PAIEMENT_REQUIS");
  const nouveau = aSoldeCommissionEmail(data);
  const corps = lireSoldeCommission({ ...facture,
    montant_ttc: data.montant_ttc,
    montant_avoirs_imputes: nouveau ? data.montant_avoirs_imputes : 0,
    montant_a_payer: nouveau ? data.montant_a_payer : data.montant_ttc,
  });
  // L'agrégat est garanti par SQL égal à toutes les IMPUTATION de la cible,
  // y compris après restitution : zéro prouve l'absence de consommation.
  if (corps.montantDocumentCents !== solde.montantDocumentCents
    || corps.avoirsImputesCents !== solde.avoirsImputesCents
    || corps.montantExterneCents !== solde.montantExterneCents
    || data.mode_paiement === "AVOIR" && (facture.mode_paiement !== "AVOIR" || solde.montantExterneCents !== 0)) {
    throw new Error("SOLDE_COMMISSION_EMAIL_INCOHERENT");
  }
}

/** L'email détaille le document et son règlement sans réduire HT/TVA/TTC. */
export function montantsCommissionEmail(data: Record<string, unknown>, payee = false): string {
  const solde = lireSoldeCommission({
    montant_ttc: data.montant_ttc,
    montant_avoirs_imputes: data.montant_avoirs_imputes,
    montant_a_payer: data.montant_a_payer,
    statut: payee ? "PAYEE" : "EMISE",
    type_document: "FACTURE", rapprochement_paiement_requis: false,
  });
  if (data.mode_paiement === "AVOIR" && (solde.montantExterneCents !== 0 || solde.avoirsImputesCents === 0)) {
    throw new Error("SOLDE_COMMISSION_INCOHERENT");
  }
  const euros = (cents: number) => (cents / 100).toFixed(2);
  return `<span>Montant TTC du document : <strong>${euros(solde.montantDocumentCents)} €</strong></span><br/>
    <span>Avoirs imputés : <strong>−${euros(solde.avoirsImputesCents)} €</strong></span><br/>
    <span>${payee ? "Montant réglé hors avoir" : "Net à payer"} : <strong>${euros(solde.montantExterneCents)} €</strong></span><br/>`;
}

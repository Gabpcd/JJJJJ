import { describe, expect, it } from 'vitest';
import { lireSoldeCommission, estSoldeeParAvoir } from '../../../supabase/functions/_shared/commission-balance';
import { generateCiiXml, type FacturXInvoice } from '../../../supabase/functions/_shared/facturx-builder';
import { montantsCommissionEmail, verifierSoldeCommissionEmail } from '../../../supabase/functions/_shared/commission-email';

const facture = { montant_ttc: '120.00', montant_avoirs_imputes: '30.00', montant_a_payer: '90.00',
  statut: 'EMISE', type_document: 'FACTURE', rapprochement_paiement_requis: false };

describe('Solde commission canonique', () => {
  it('sépare document, avoir, externe et dette sans perdre les montants après PAYEE', () => {
    expect(lireSoldeCommission(facture)).toEqual({ montantDocumentCents: 12000, avoirsImputesCents: 3000,
      montantExterneCents: 9000, resteDuCents: 9000, rapprochementRequis: false });
    expect(lireSoldeCommission({ ...facture, statut: 'PAYEE' })).toMatchObject({ montantExterneCents: 9000, resteDuCents: 0 });
    expect(lireSoldeCommission({ ...facture, type_document: 'AVOIR' }).resteDuCents).toBe(0);
    expect(lireSoldeCommission({ ...facture, type_document: 'FACTURE_COMPLEMENTAIRE' }).resteDuCents).toBe(9000);
  });
  it.each(['montant_ttc', 'montant_avoirs_imputes', 'montant_a_payer', 'rapprochement_paiement_requis'])('refuse %s absent ou null', key => {
    for (const value of [undefined, null]) expect(() => lireSoldeCommission({ ...facture, [key]: value })).toThrow();
  });
  it.each(['REMPLACEE', 'ERREUR_GENERATION', 'ANNULEE', 'BROUILLON'])('ne demande aucun paiement pour le statut documentaire %s', statut => {
    expect(lireSoldeCommission({ ...facture, statut }).resteDuCents).toBe(0);
  });
  it.each([NaN, Infinity, -1, 0.001, '', '1e2', ' 120 ', true])('refuse une valeur non monétaire %s', value => {
    expect(() => lireSoldeCommission({ ...facture, montant_ttc: value })).toThrow();
  });
  it('refuse une imputation excessive et un net différent, même payé', () => {
    expect(() => lireSoldeCommission({ ...facture, montant_avoirs_imputes: 121 })).toThrow();
    expect(() => lireSoldeCommission({ ...facture, montant_a_payer: 120, statut: 'PAYEE' })).toThrow();
  });
  it('reconnaît seulement le zéro soldé par SQL sans PaymentIntent', () => {
    const zero = { ...facture, montant_avoirs_imputes: 120, montant_a_payer: 0, statut: 'PAYEE', mode_paiement: 'AVOIR', stripe_payment_intent_id: null };
    expect(estSoldeeParAvoir(zero)).toBe(true);
    expect(estSoldeeParAvoir({ ...zero, statut: 'EMISE' })).toBe(false);
    expect(estSoldeeParAvoir({ ...zero, stripe_payment_intent_id: 'pi_interdit' })).toBe(false);
    expect(estSoldeeParAvoir({ ...zero, mode_paiement: 'STRIPE' })).toBe(false);
  });
});

describe('CII réel : crédit imputé sans réécriture du document', () => {
  const inv: FacturXInvoice = { invoiceNumber: 'C-1', issueDate: '2026-10-18', dueDate: '2026-11-18',
    sellerName: 'Jolene', sellerSiret: '12345678901234', sellerAddress: 'Rue', sellerCity: 'Paris', sellerPostalCode: '75001',
    buyerName: 'Établissement', buyerSiret: '98765432109876', buyerAddress: 'Rue', buyerCity: 'Paris', buyerPostalCode: '75001',
    description: 'Commission', amountHt: 100, amountTva: 20, amountTtc: 120, vatRate: 20 };
  it.each([[30, 90], [120, 0]])('BT113=%s et BT115=%s, HT/TVA/BT112 inchangés', (credit, due) => {
    const xml = generateCiiXml({ ...inv, amountPrepaid: credit, amountDue: due });
    expect(xml).toContain('<ram:TaxBasisTotalAmount>100.00</ram:TaxBasisTotalAmount>');
    expect(xml).toContain('<ram:TaxTotalAmount currencyID="EUR">20.00</ram:TaxTotalAmount>');
    expect(xml).toContain('<ram:GrandTotalAmount>120.00</ram:GrandTotalAmount>');
    expect(xml).toContain(`<ram:TotalPrepaidAmount>${credit.toFixed(2)}</ram:TotalPrepaidAmount>`);
    expect(xml).toContain(`<ram:DuePayableAmount>${due.toFixed(2)}</ram:DuePayableAmount>`);
    expect(xml.indexOf('TotalPrepaidAmount')).toBeLessThan(xml.indexOf('DuePayableAmount'));
  });
  it('conserve les honoraires sans imputation et les avoirs documentaires', () => {
    expect(generateCiiXml(inv)).not.toContain('TotalPrepaidAmount');
    expect(generateCiiXml({ ...inv, isAvoir: true })).toContain('<ram:TypeCode>381</ram:TypeCode>');
  });
  it('refuse un net incohérent ou une consommation sur un avoir documentaire', () => {
    expect(() => generateCiiXml({ ...inv, amountPrepaid: 30, amountDue: 120 })).toThrow('FACTURX_SOLDE_INCOHERENT');
    expect(() => generateCiiXml({ ...inv, amountPrepaid: 30, amountDue: 90, isAvoir: true })).toThrow();
  });
});

describe('Emails commission : preuve DB et ancien corps immuable', () => {
  const db = { ...facture, id: 'commission-1', etablissement_id: 'etab-1', mode_paiement: null };
  const client = (row: unknown, error: unknown = null) => ({ from: () => {
    const query = { select: () => query, eq: () => query, maybeSingle: async () => ({ data: row, error }) }; return query;
  } });
  it('affiche TTC, avoir et net distinctement', () => {
    const html = montantsCommissionEmail(facture);
    expect(html).toContain('120.00 €'); expect(html).toContain('−30.00 €'); expect(html).toContain('90.00 €');
    expect(html).toContain('Net à payer');
  });
  it('accepte le nouveau corps seulement si ses montants sont canoniques', async () => {
    const body = { ...facture, facture_id: db.id };
    await expect(verifierSoldeCommissionEmail(client(db), 'FACTURE_EMISE', body, 'etab-1')).resolves.toBeUndefined();
    await expect(verifierSoldeCommissionEmail(client(db), 'FACTURE_EMISE', { ...body, montant_a_payer: 120 }, 'etab-1')).rejects.toThrow();
    await expect(verifierSoldeCommissionEmail(client(db), 'FACTURE_EMISE', body, 'autre-etab')).rejects.toThrow();
  });
  it('garde un ancien corps inchangé seulement après preuve agrégat0/netTTC', async () => {
    const body = { facture_id: db.id, montant_ttc: '120.00' }; const before = JSON.stringify(body);
    await expect(verifierSoldeCommissionEmail(client({ ...db, montant_avoirs_imputes: 0, montant_a_payer: 120 }), 'FACTURE_PAYEE', body, 'etab-1')).resolves.toBeUndefined();
    expect(JSON.stringify(body)).toBe(before);
    await expect(verifierSoldeCommissionEmail(client(db), 'FACTURE_PAYEE', body, 'etab-1')).rejects.toThrow();
    await expect(verifierSoldeCommissionEmail(client(null, { message: 'indisponible' }), 'FACTURE_PAYEE', body, 'etab-1')).rejects.toThrow();
  });
  it('bloque toute relance après incident de remboursement', async () => {
    await expect(verifierSoldeCommissionEmail(client({ ...db, rapprochement_paiement_requis: true }), 'RAPPEL_FACTURE', { ...facture, facture_id: db.id }, 'etab-1')).rejects.toThrow('RAPPROCHEMENT_PAIEMENT_REQUIS');
  });
});

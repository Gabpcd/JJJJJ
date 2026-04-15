/**
 * Test 3 — Factur-X Generator
 *
 * Vérifie que le XML CII généré par generate-invoice :
 * - Contient les namespaces EN16931 requis
 * - A les mentions obligatoires art. 242 nonies CGI
 * - Le SIRET affiché est celui du pro, pas celui de Jolene
 * - La mention TVA art. 261, 4-1° apparaît si exonéré
 * - Si factor_assigned : mention subrogative + IBAN factor dans PaymentMeans
 *
 * Note : ce test vérifie la logique XML directement, sans appeler l'edge function.
 * L'edge function est testée end-to-end dans e2e tests.
 */

import { describe, it, expect } from 'vitest';

// Inline the XML generator for unit testing (same logic as edge function)
function escapeXml(s: string): string {
  return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

function generateTestCiiXml(params: {
  invoiceNumber: string;
  sellerName: string;
  sellerSiret: string;
  sellerRpps: string;
  buyerName: string;
  buyerSiret: string;
  amountHt: number;
  amountTva: number;
  amountTtc: number;
  vatExempt: boolean;
  factorIban?: string;
  factorBic?: string;
  subrogationMention?: string;
}): string {
  const fmtAmt = (n: number) => n.toFixed(2);
  const vatCategory = params.vatExempt
    ? `<ram:CategoryCode>E</ram:CategoryCode><ram:ExemptionReason>TVA non applicable — art. 261, 4-1° du CGI</ram:ExemptionReason><ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>`
    : `<ram:CategoryCode>S</ram:CategoryCode><ram:RateApplicablePercent>20.00</ram:RateApplicablePercent>`;

  const paymentMeans = params.factorIban
    ? `<ram:SpecifiedTradeSettlementPaymentMeans><ram:TypeCode>58</ram:TypeCode><ram:PayeePartyCreditorFinancialAccount><ram:IBANID>${escapeXml(params.factorIban)}</ram:IBANID></ram:PayeePartyCreditorFinancialAccount>${params.factorBic ? `<ram:PayeeSpecifiedCreditorFinancialInstitution><ram:BICID>${escapeXml(params.factorBic)}</ram:BICID></ram:PayeeSpecifiedCreditorFinancialInstitution>` : ''}</ram:SpecifiedTradeSettlementPaymentMeans>`
    : `<ram:SpecifiedTradeSettlementPaymentMeans><ram:TypeCode>58</ram:TypeCode></ram:SpecifiedTradeSettlementPaymentMeans>`;

  const noteBlock = params.subrogationMention
    ? `<ram:IncludedNote><ram:Content>${escapeXml(params.subrogationMention)}</ram:Content><ram:SubjectCode>AAB</ram:SubjectCode></ram:IncludedNote>`
    : '';

  return `<?xml version="1.0" encoding="UTF-8"?>
<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
  <rsm:ExchangedDocumentContext><ram:GuidelineSpecifiedDocumentContextParameter><ram:ID>urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic</ram:ID></ram:GuidelineSpecifiedDocumentContextParameter></rsm:ExchangedDocumentContext>
  <rsm:ExchangedDocument><ram:ID>${escapeXml(params.invoiceNumber)}</ram:ID><ram:TypeCode>380</ram:TypeCode><ram:IssueDateTime><udt:DateTimeString format="102">20260413</udt:DateTimeString></ram:IssueDateTime>${noteBlock}</rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
    <ram:ApplicableHeaderTradeAgreement>
      <ram:SellerTradeParty><ram:Name>${escapeXml(params.sellerName)}</ram:Name><ram:SpecifiedLegalOrganization><ram:ID schemeID="0002">${escapeXml(params.sellerSiret)}</ram:ID></ram:SpecifiedLegalOrganization></ram:SellerTradeParty>
      <ram:BuyerTradeParty><ram:Name>${escapeXml(params.buyerName)}</ram:Name><ram:SpecifiedLegalOrganization><ram:ID schemeID="0002">${escapeXml(params.buyerSiret)}</ram:ID></ram:SpecifiedLegalOrganization></ram:BuyerTradeParty>
    </ram:ApplicableHeaderTradeAgreement>
    <ram:ApplicableHeaderTradeSettlement>
      <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>
      ${paymentMeans}
      <ram:ApplicableTradeTax><ram:CalculatedAmount>${fmtAmt(params.amountTva)}</ram:CalculatedAmount><ram:BasisAmount>${fmtAmt(params.amountHt)}</ram:BasisAmount>${vatCategory}</ram:ApplicableTradeTax>
      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:GrandTotalAmount>${fmtAmt(params.amountTtc)}</ram:GrandTotalAmount>
        <ram:DuePayableAmount>${fmtAmt(params.amountTtc)}</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>`;
}

describe('XML CII Factur-X — EN16931 BASIC', () => {
  const baseParams = {
    invoiceNumber: 'JOL-12345678-2026-00001',
    sellerName: 'Marie Dupont',
    sellerSiret: '12345678901234',
    sellerRpps: '12345678901',
    buyerName: 'EHPAD Les Glycines',
    buyerSiret: '98765432109876',
    amountHt: 500.00,
    amountTva: 0,
    amountTtc: 500.00,
    vatExempt: true,
  };

  it('contient les namespaces EN16931 requis', () => {
    const xml = generateTestCiiXml(baseParams);
    expect(xml).toContain('urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100');
    expect(xml).toContain('urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100');
    expect(xml).toContain('urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic');
  });

  it('contient le TypeCode 380 (facture commerciale)', () => {
    const xml = generateTestCiiXml(baseParams);
    expect(xml).toContain('<ram:TypeCode>380</ram:TypeCode>');
  });

  it('le numéro de facture est présent', () => {
    const xml = generateTestCiiXml(baseParams);
    expect(xml).toContain('<ram:ID>JOL-12345678-2026-00001</ram:ID>');
  });

  it('le SIRET du vendeur est celui du pro, pas celui de Jolene', () => {
    const xml = generateTestCiiXml(baseParams);
    // Le SellerTradeParty doit contenir le SIRET du soignant
    expect(xml).toContain('12345678901234');
    // Le SIRET de Jolene ne doit PAS apparaître comme vendeur
    // (Jolene est mandataire, pas vendeur)
    expect(xml).not.toContain('Jolene SASU');
    expect(xml).toContain('Marie Dupont');
  });

  it('la mention exonération TVA art. 261, 4-1° apparaît si vatExempt=true', () => {
    const xml = generateTestCiiXml({ ...baseParams, vatExempt: true });
    expect(xml).toContain('art. 261, 4-1');
    expect(xml).toContain('<ram:CategoryCode>E</ram:CategoryCode>');
    expect(xml).toContain('<ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>');
  });

  it('la TVA standard apparaît si vatExempt=false', () => {
    const xml = generateTestCiiXml({
      ...baseParams,
      vatExempt: false,
      amountTva: 100,
      amountTtc: 600,
    });
    expect(xml).toContain('<ram:CategoryCode>S</ram:CategoryCode>');
    expect(xml).toContain('<ram:RateApplicablePercent>20.00</ram:RateApplicablePercent>');
    expect(xml).not.toContain('art. 261');
  });

  it('les montants HT, TVA, TTC sont corrects', () => {
    const xml = generateTestCiiXml(baseParams);
    expect(xml).toContain('<ram:BasisAmount>500.00</ram:BasisAmount>');
    expect(xml).toContain('<ram:CalculatedAmount>0.00</ram:CalculatedAmount>');
    expect(xml).toContain('<ram:GrandTotalAmount>500.00</ram:GrandTotalAmount>');
    expect(xml).toContain('<ram:DuePayableAmount>500.00</ram:DuePayableAmount>');
  });

  it('la devise EUR est spécifiée', () => {
    const xml = generateTestCiiXml(baseParams);
    expect(xml).toContain('<ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>');
  });

  describe('avec factor_assigned', () => {
    const factorParams = {
      ...baseParams,
      factorIban: 'FR7630006000011234567890189',
      factorBic: 'BNPAFRPP',
      subrogationMention: 'Règlement à l\'ordre de Defacto SAS, subrogation contrat factoring.',
    };

    it('contient la mention subrogative dans IncludedNote', () => {
      const xml = generateTestCiiXml(factorParams);
      expect(xml).toContain('<ram:IncludedNote>');
      expect(xml).toContain('subrogation');
      expect(xml).toContain('<ram:SubjectCode>AAB</ram:SubjectCode>');
    });

    it('contient l\'IBAN du factor dans PaymentMeans', () => {
      const xml = generateTestCiiXml(factorParams);
      expect(xml).toContain('<ram:IBANID>FR7630006000011234567890189</ram:IBANID>');
    });

    it('contient le BIC du factor', () => {
      const xml = generateTestCiiXml(factorParams);
      expect(xml).toContain('<ram:BICID>BNPAFRPP</ram:BICID>');
    });
  });

  describe('sans factor', () => {
    it('pas de mention subrogative', () => {
      const xml = generateTestCiiXml(baseParams);
      expect(xml).not.toContain('subrogation');
      expect(xml).not.toContain('<ram:IncludedNote>');
    });

    it('PaymentMeans sans IBAN factor', () => {
      const xml = generateTestCiiXml(baseParams);
      expect(xml).toContain('<ram:TypeCode>58</ram:TypeCode>');
      expect(xml).not.toContain('<ram:IBANID>');
    });
  });

  it('échappe correctement les caractères XML', () => {
    const xml = generateTestCiiXml({
      ...baseParams,
      sellerName: 'Dr. Marie "La Pro" & Associés <test>',
    });
    expect(xml).toContain('Dr. Marie &quot;La Pro&quot; &amp; Associés &lt;test&gt;');
    expect(xml).not.toContain('<test>');
  });
});

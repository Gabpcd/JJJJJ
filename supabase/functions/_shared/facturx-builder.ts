/**
 * facturx-builder.ts — Générateur XML CII (Factur-X BASIC / EN16931)
 *
 * Extrait de generate-invoice/index.ts pour réutilisation dans chorus-pro-deposit
 * et submit-to-chorus.
 *
 * Le XML reste distinct du PDF lisible. Son dépôt Chorus est autorisé seulement
 * après qualification explicite de la syntaxe configurée.
 */

export interface FacturXInvoice {
  invoiceNumber: string;
  issueDate: string; // YYYY-MM-DD
  dueDate: string;
  sellerName: string;
  sellerSiret: string;
  sellerVatId?: string;
  sellerRpps?: string;
  sellerAdeli?: string;
  sellerAddress: string;
  sellerCity: string;
  sellerPostalCode: string;
  sellerEmail?: string;
  buyerName: string;
  buyerSiret: string;
  buyerAddress: string;
  buyerCity: string;
  buyerPostalCode: string;
  serviceDate?: string;
  serviceCode?: string;
  description: string;
  amountHt: number;
  amountTva: number;
  amountTtc: number;
  vatRate: number;
  vatExempt?: boolean;
  vatExemptionReason?: string;
  currencyCode?: string;
  factorIban?: string;
  factorBic?: string;
  factorName?: string;
  subrogationMention?: string;
  isAvoir?: boolean;
  precedingInvoiceNumber?: string;
  precedingInvoiceIssueDate?: string;
}

export function escapeXml(s: string | undefined | null): string {
  return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

export function generateCiiXml(inv: FacturXInvoice): string {
  const fmtDate = (d: string) => d.replace(/-/g, '');
  const fmtAmt = (n: number) => n.toFixed(2);
  const typeCode = inv.isAvoir ? '381' : '380';
  const currency = inv.currencyCode ?? 'EUR';
  const sellerSiret = String(inv.sellerSiret || '').replace(/\D/g, '');
  const buyerSiret = String(inv.buyerSiret || '').replace(/\D/g, '');
  if (!/^\d{14}$/.test(sellerSiret) || !/^\d{14}$/.test(buyerSiret)) {
    throw new Error('SIRET_EMETTEUR_OU_DESTINATAIRE_INVALIDE');
  }
  const sellerSiren = sellerSiret.slice(0, 9);
  const buyerSiren = buyerSiret.slice(0, 9);
  const sellerTaxRegistration = inv.sellerVatId
    ? `<ram:SpecifiedTaxRegistration><ram:ID schemeID="VA">${escapeXml(inv.sellerVatId)}</ram:ID></ram:SpecifiedTaxRegistration>`
    : `<ram:SpecifiedTaxRegistration><ram:ID schemeID="FC">${sellerSiren}</ram:ID></ram:SpecifiedTaxRegistration>`;

  const precedingRef = inv.isAvoir && inv.precedingInvoiceNumber
    ? `<ram:InvoiceReferencedDocument>
        <ram:IssuerAssignedID>${escapeXml(inv.precedingInvoiceNumber)}</ram:IssuerAssignedID>
        ${inv.precedingInvoiceIssueDate ? `<ram:FormattedIssueDateTime><qdt:DateTimeString format="102">${fmtDate(inv.precedingInvoiceIssueDate)}</qdt:DateTimeString></ram:FormattedIssueDateTime>` : ''}
      </ram:InvoiceReferencedDocument>`
    : '';

  const paymentMeans = inv.factorIban
    ? `<ram:SpecifiedTradeSettlementPaymentMeans>
        <ram:TypeCode>58</ram:TypeCode>
        <ram:PayeePartyCreditorFinancialAccount>
          <ram:IBANID>${escapeXml(inv.factorIban)}</ram:IBANID>
        </ram:PayeePartyCreditorFinancialAccount>
        ${inv.factorBic ? `<ram:PayeeSpecifiedCreditorFinancialInstitution><ram:BICID>${escapeXml(inv.factorBic)}</ram:BICID></ram:PayeeSpecifiedCreditorFinancialInstitution>` : ''}
      </ram:SpecifiedTradeSettlementPaymentMeans>`
    : `<ram:SpecifiedTradeSettlementPaymentMeans>
        <ram:TypeCode>68</ram:TypeCode>
      </ram:SpecifiedTradeSettlementPaymentMeans>`;

  const lineVatTax = inv.vatExempt
    ? `<ram:TypeCode>VAT</ram:TypeCode>
       <ram:ExemptionReason>${escapeXml(inv.vatExemptionReason ?? 'Exonere')}</ram:ExemptionReason>
       <ram:CategoryCode>E</ram:CategoryCode>
       <ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>`
    : `<ram:TypeCode>VAT</ram:TypeCode>
       <ram:CategoryCode>S</ram:CategoryCode>
       <ram:RateApplicablePercent>${fmtAmt(inv.vatRate)}</ram:RateApplicablePercent>`;
  const headerVatTax = inv.vatExempt
    ? `<ram:CalculatedAmount>${fmtAmt(inv.amountTva)}</ram:CalculatedAmount>
       <ram:TypeCode>VAT</ram:TypeCode>
       <ram:ExemptionReason>${escapeXml(inv.vatExemptionReason ?? 'Exonere')}</ram:ExemptionReason>
       <ram:BasisAmount>${fmtAmt(inv.amountHt)}</ram:BasisAmount>
       <ram:CategoryCode>E</ram:CategoryCode>
       <ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>`
    : `<ram:CalculatedAmount>${fmtAmt(inv.amountTva)}</ram:CalculatedAmount>
       <ram:TypeCode>VAT</ram:TypeCode>
       <ram:BasisAmount>${fmtAmt(inv.amountHt)}</ram:BasisAmount>
       <ram:CategoryCode>S</ram:CategoryCode>
       <ram:RateApplicablePercent>${fmtAmt(inv.vatRate)}</ram:RateApplicablePercent>`;

  const noteBlock = inv.subrogationMention
    ? `<ram:IncludedNote><ram:Content>${escapeXml(inv.subrogationMention)}</ram:Content></ram:IncludedNote>`
    : '';
  const paymentLegalNotes = `
    <ram:IncludedNote><ram:Content>Escompte pour paiement anticipe : neant.</ram:Content><ram:SubjectCode>AAB</ram:SubjectCode></ram:IncludedNote>
    <ram:IncludedNote><ram:Content>Penalites de retard exigibles sans rappel : taux de refinancement de la BCE majore de 10 points.</ram:Content><ram:SubjectCode>PMD</ram:SubjectCode></ram:IncludedNote>
    <ram:IncludedNote><ram:Content>Indemnite forfaitaire pour frais de recouvrement en cas de retard : 40 EUR.</ram:Content><ram:SubjectCode>PMT</ram:SubjectCode></ram:IncludedNote>`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
  xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
  xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
  xmlns:qdt="urn:un:unece:uncefact:data:standard:QualifiedDataType:100">
  <rsm:ExchangedDocumentContext>
    <ram:GuidelineSpecifiedDocumentContextParameter>
      <ram:ID>urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic</ram:ID>
    </ram:GuidelineSpecifiedDocumentContextParameter>
  </rsm:ExchangedDocumentContext>
  <rsm:ExchangedDocument>
    <ram:ID>${escapeXml(inv.invoiceNumber)}</ram:ID>
    <ram:TypeCode>${typeCode}</ram:TypeCode>
    <ram:IssueDateTime><udt:DateTimeString format="102">${fmtDate(inv.issueDate)}</udt:DateTimeString></ram:IssueDateTime>
    ${noteBlock}
    ${paymentLegalNotes}
  </rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
    <ram:IncludedSupplyChainTradeLineItem>
      <ram:AssociatedDocumentLineDocument><ram:LineID>1</ram:LineID></ram:AssociatedDocumentLineDocument>
      <ram:SpecifiedTradeProduct>
        <ram:Name>${escapeXml(inv.description)}</ram:Name>
      </ram:SpecifiedTradeProduct>
      <ram:SpecifiedLineTradeAgreement>
        <ram:NetPriceProductTradePrice><ram:ChargeAmount>${fmtAmt(inv.amountHt)}</ram:ChargeAmount></ram:NetPriceProductTradePrice>
      </ram:SpecifiedLineTradeAgreement>
      <ram:SpecifiedLineTradeDelivery><ram:BilledQuantity unitCode="C62">1</ram:BilledQuantity></ram:SpecifiedLineTradeDelivery>
      <ram:SpecifiedLineTradeSettlement>
        <ram:ApplicableTradeTax>
          ${lineVatTax}
        </ram:ApplicableTradeTax>
        <ram:SpecifiedTradeSettlementLineMonetarySummation>
          <ram:LineTotalAmount>${fmtAmt(inv.amountHt)}</ram:LineTotalAmount>
        </ram:SpecifiedTradeSettlementLineMonetarySummation>
      </ram:SpecifiedLineTradeSettlement>
    </ram:IncludedSupplyChainTradeLineItem>
    <ram:ApplicableHeaderTradeAgreement>
      ${inv.serviceCode ? `<ram:BuyerReference>${escapeXml(inv.serviceCode)}</ram:BuyerReference>` : ''}
      <ram:SellerTradeParty>
        <ram:Name>${escapeXml(inv.sellerName)}</ram:Name>
        <ram:SpecifiedLegalOrganization><ram:ID schemeID="0002">${sellerSiren}</ram:ID></ram:SpecifiedLegalOrganization>
        <ram:PostalTradeAddress>
          <ram:PostcodeCode>${escapeXml(inv.sellerPostalCode)}</ram:PostcodeCode>
          <ram:LineOne>${escapeXml(inv.sellerAddress)}</ram:LineOne>
          <ram:CityName>${escapeXml(inv.sellerCity)}</ram:CityName>
          <ram:CountryID>FR</ram:CountryID>
        </ram:PostalTradeAddress>
        ${inv.sellerEmail ? `<ram:URIUniversalCommunication><ram:URIID schemeID="EM">${escapeXml(inv.sellerEmail)}</ram:URIID></ram:URIUniversalCommunication>` : ''}
        ${sellerTaxRegistration}
      </ram:SellerTradeParty>
      <ram:BuyerTradeParty>
        <ram:Name>${escapeXml(inv.buyerName)}</ram:Name>
        <ram:SpecifiedLegalOrganization><ram:ID schemeID="0002">${buyerSiren}</ram:ID></ram:SpecifiedLegalOrganization>
        <ram:PostalTradeAddress>
          <ram:PostcodeCode>${escapeXml(inv.buyerPostalCode)}</ram:PostcodeCode>
          <ram:LineOne>${escapeXml(inv.buyerAddress)}</ram:LineOne>
          <ram:CityName>${escapeXml(inv.buyerCity)}</ram:CityName>
          <ram:CountryID>FR</ram:CountryID>
        </ram:PostalTradeAddress>
        <ram:URIUniversalCommunication><ram:URIID schemeID="0002">${buyerSiret}</ram:URIID></ram:URIUniversalCommunication>
      </ram:BuyerTradeParty>
    </ram:ApplicableHeaderTradeAgreement>
    <ram:ApplicableHeaderTradeDelivery>
      <ram:ActualDeliverySupplyChainEvent>
        <ram:OccurrenceDateTime><udt:DateTimeString format="102">${fmtDate(inv.serviceDate || inv.issueDate)}</udt:DateTimeString></ram:OccurrenceDateTime>
      </ram:ActualDeliverySupplyChainEvent>
    </ram:ApplicableHeaderTradeDelivery>
    <ram:ApplicableHeaderTradeSettlement>
      <ram:InvoiceCurrencyCode>${currency}</ram:InvoiceCurrencyCode>
      ${paymentMeans}
      <ram:ApplicableTradeTax>
        ${headerVatTax}
      </ram:ApplicableTradeTax>
      <ram:SpecifiedTradePaymentTerms>
        <ram:DueDateDateTime><udt:DateTimeString format="102">${fmtDate(inv.dueDate)}</udt:DateTimeString></ram:DueDateDateTime>
      </ram:SpecifiedTradePaymentTerms>
      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>${fmtAmt(inv.amountHt)}</ram:LineTotalAmount>
        <ram:TaxBasisTotalAmount>${fmtAmt(inv.amountHt)}</ram:TaxBasisTotalAmount>
        <ram:TaxTotalAmount currencyID="${currency}">${fmtAmt(inv.amountTva)}</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>${fmtAmt(inv.amountTtc)}</ram:GrandTotalAmount>
        <ram:DuePayableAmount>${fmtAmt(inv.amountTtc)}</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
      ${precedingRef}
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>`;
}

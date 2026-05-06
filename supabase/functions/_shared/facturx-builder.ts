/**
 * facturx-builder.ts — Générateur XML CII (EN16931 BASIC WL / Factur-X 1p0 basic)
 *
 * Extrait de generate-invoice/index.ts pour réutilisation dans chorus-pro-deposit
 * et submit-to-chorus.
 *
 * Format compatible Chorus Pro (syntaxeFlux=IN_DP_E2_CII_FACTURX).
 */

export interface FacturXInvoice {
  invoiceNumber: string;
  issueDate: string; // YYYY-MM-DD
  dueDate: string;
  sellerName: string;
  sellerSiret: string;
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
  const sign = inv.isAvoir ? -1 : 1;
  const signed = (n: number) => fmtAmt(n * sign);
  const currency = inv.currencyCode ?? 'EUR';

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
        <ram:TypeCode>58</ram:TypeCode>
      </ram:SpecifiedTradeSettlementPaymentMeans>`;

  const vatCategory = inv.vatExempt
    ? `<ram:CategoryCode>E</ram:CategoryCode>
       <ram:ExemptionReason>${escapeXml(inv.vatExemptionReason ?? 'Exonere')}</ram:ExemptionReason>
       <ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>`
    : `<ram:CategoryCode>S</ram:CategoryCode>
       <ram:RateApplicablePercent>${fmtAmt(inv.vatRate)}</ram:RateApplicablePercent>`;

  const noteBlock = inv.subrogationMention
    ? `<ram:IncludedNote><ram:Content>${escapeXml(inv.subrogationMention)}</ram:Content><ram:SubjectCode>AAB</ram:SubjectCode></ram:IncludedNote>`
    : '';

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
          ${vatCategory}
        </ram:ApplicableTradeTax>
        <ram:SpecifiedTradeSettlementLineMonetarySummation>
          <ram:LineTotalAmount>${fmtAmt(inv.amountHt)}</ram:LineTotalAmount>
        </ram:SpecifiedTradeSettlementLineMonetarySummation>
      </ram:SpecifiedLineTradeSettlement>
    </ram:IncludedSupplyChainTradeLineItem>
    <ram:ApplicableHeaderTradeAgreement>
      <ram:SellerTradeParty>
        <ram:Name>${escapeXml(inv.sellerName)}</ram:Name>
        <ram:SpecifiedLegalOrganization><ram:ID schemeID="0002">${escapeXml(inv.sellerSiret)}</ram:ID></ram:SpecifiedLegalOrganization>
        <ram:PostalTradeAddress>
          <ram:LineOne>${escapeXml(inv.sellerAddress)}</ram:LineOne>
          <ram:PostcodeCode>${escapeXml(inv.sellerPostalCode)}</ram:PostcodeCode>
          <ram:CityName>${escapeXml(inv.sellerCity)}</ram:CityName>
          <ram:CountryID>FR</ram:CountryID>
        </ram:PostalTradeAddress>
        ${inv.sellerEmail ? `<ram:URIUniversalCommunication><ram:URIID schemeID="EM">${escapeXml(inv.sellerEmail)}</ram:URIID></ram:URIUniversalCommunication>` : ''}
      </ram:SellerTradeParty>
      <ram:BuyerTradeParty>
        <ram:Name>${escapeXml(inv.buyerName)}</ram:Name>
        <ram:SpecifiedLegalOrganization><ram:ID schemeID="0002">${escapeXml(inv.buyerSiret)}</ram:ID></ram:SpecifiedLegalOrganization>
        <ram:PostalTradeAddress>
          <ram:LineOne>${escapeXml(inv.buyerAddress)}</ram:LineOne>
          <ram:PostcodeCode>${escapeXml(inv.buyerPostalCode)}</ram:PostcodeCode>
          <ram:CityName>${escapeXml(inv.buyerCity)}</ram:CityName>
          <ram:CountryID>FR</ram:CountryID>
        </ram:PostalTradeAddress>
      </ram:BuyerTradeParty>
      ${precedingRef}
    </ram:ApplicableHeaderTradeAgreement>
    <ram:ApplicableHeaderTradeDelivery/>
    <ram:ApplicableHeaderTradeSettlement>
      <ram:InvoiceCurrencyCode>${currency}</ram:InvoiceCurrencyCode>
      ${paymentMeans}
      <ram:ApplicableTradeTax>
        <ram:CalculatedAmount>${fmtAmt(inv.amountTva)}</ram:CalculatedAmount>
        <ram:BasisAmount>${fmtAmt(inv.amountHt)}</ram:BasisAmount>
        ${vatCategory}
      </ram:ApplicableTradeTax>
      <ram:SpecifiedTradePaymentTerms>
        <ram:DueDateDateTime><udt:DateTimeString format="102">${fmtDate(inv.dueDate)}</udt:DateTimeString></ram:DueDateDateTime>
      </ram:SpecifiedTradePaymentTerms>
      <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        <ram:LineTotalAmount>${signed(inv.amountHt)}</ram:LineTotalAmount>
        <ram:TaxBasisTotalAmount>${signed(inv.amountHt)}</ram:TaxBasisTotalAmount>
        <ram:TaxTotalAmount currencyID="${currency}">${signed(inv.amountTva)}</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>${signed(inv.amountTtc)}</ram:GrandTotalAmount>
        <ram:DuePayableAmount>${signed(inv.amountTtc)}</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>`;
}

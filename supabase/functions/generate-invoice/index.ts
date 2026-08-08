/**
 * generate-invoice — Génération de facture honoraire PDF + XML CII
 *
 * AUTH :
 * - JWT utilisateur (soignant) : vérifié via auth.getUser()
 * - Service_role key : bypass auth, mais TOUTES les règles métier restent actives :
 *   - Mission doit être TERMINEE
 *   - Mandat actif signé pour le soignant
 *   - Pas de double génération (idempotence)
 *   - Tous les triggers Postgres (immutabilité, auto-audit)
 *   Le bypass service_role requiert un `service_role_reason` valide.
 *   Max 10 appels/min en service_role (rate limit).
 */

import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { PDFDocument, StandardFonts, rgb, degrees } from 'npm:pdf-lib@1.17.1';
import { corsHeaders } from '../_shared/cors.ts';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';

/* ── Rate limit state (in-memory, per isolate) ── */
const serviceRoleCallLog: number[] = [];
const SERVICE_ROLE_MAX_PER_MIN = 10;

const VALID_REASON_PATTERNS = [
  /^cron_auto_generation$/,
  /^admin_replay_[0-9a-f-]{36}$/,
  /^ops_test_.+$/,
  /^admin_invoke_[0-9a-f-]{36}:.+$/,
  /^admin_resoudre_litige_immediate$/,
];

function validateServiceRoleReason(reason: string | undefined): { valid: boolean; error?: string } {
  if (!reason || typeof reason !== 'string' || reason.trim().length === 0) {
    return { valid: false, error: 'service_role_reason requis pour les appels service_role' };
  }
  if (!VALID_REASON_PATTERNS.some(p => p.test(reason))) {
    return { valid: false, error: `service_role_invalid_reason: "${reason}" ne match aucun pattern autorisé (cron_auto_generation, admin_replay_<uuid>, ops_test_<purpose>, admin_resoudre_litige_immediate)` };
  }
  return { valid: true };
}

function checkServiceRoleRateLimit(): boolean {
  const now = Date.now();
  // Purge entries older than 60s
  while (serviceRoleCallLog.length > 0 && serviceRoleCallLog[0] < now - 60_000) {
    serviceRoleCallLog.shift();
  }
  if (serviceRoleCallLog.length >= SERVICE_ROLE_MAX_PER_MIN) {
    return false; // rate limited
  }
  serviceRoleCallLog.push(now);
  return true;
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
}

function creerBlobPdf(pdfBytes: Uint8Array): Blob {
  // pdf-lib expose un Uint8Array<ArrayBufferLike>; Blob exige un ArrayBuffer
  // concret avec les définitions DOM récentes de Deno/TypeScript.
  const buffer = new ArrayBuffer(pdfBytes.byteLength);
  new Uint8Array(buffer).set(pdfBytes);
  return new Blob([buffer], { type: 'application/pdf' });
}

async function notifierEmissionDocument(
  supabaseAdmin: ReturnType<typeof createClient>,
  facture: {
    id: string;
    numero_facture: string;
    soignant_id: string;
    etablissement_id: string;
    montant_ht?: number;
    montant_tva?: number;
    montant_ttc: number;
    periode_debut?: string | null;
    periode_fin?: string | null;
    type_document?: string | null;
  },
  soignant: { prenom?: string | null },
  delaiVerificationHeures: number,
): Promise<void> {
  const montantTtc = Number(facture.montant_ttc || 0).toFixed(2);
  const periode = facture.periode_debut || facture.periode_fin
    ? `${facture.periode_debut || '—'} → ${facture.periode_fin || '—'}`
    : '—';
  const payloadCommun = {
    numero: facture.numero_facture,
    facture_id: facture.id,
    montant_ttc: montantTtc,
    periode,
  };
  const envois = await Promise.allSettled([
    supabaseAdmin.functions.invoke('send-email', {
      body: {
        type: 'FACTURE_EMISE',
        destinataire_id: facture.soignant_id,
        idempotency_key: `facture-emise-soignant:${facture.id}`,
        data: {
          ...payloadCommun,
          destinataire_role: 'SOIGNANT',
          prenom: soignant.prenom || '',
          libelle_document: facture.type_document === 'AVOIR'
            ? 'Avoir d\'honoraires'
            : 'Facture d\'honoraires',
          delai_verification_heures: String(delaiVerificationHeures),
        },
      },
    }),
    supabaseAdmin.functions.invoke('send-email', {
      body: {
        type: 'FACTURE_EMISE',
        destinataire_id: facture.etablissement_id,
        idempotency_key: `facture-emise-etablissement:${facture.id}`,
        data: {
          ...payloadCommun,
          destinataire_role: 'ETABLISSEMENT',
          montant_ht: Number(facture.montant_ht || 0).toFixed(2),
          montant_tva: Number(facture.montant_tva || 0).toFixed(2),
        },
      },
    }),
  ]);

  const erreurs = envois.flatMap((resultat, index) => {
    if (resultat.status === 'rejected') {
      return [{ destinataire: index === 0 ? 'SOIGNANT' : 'ETABLISSEMENT', erreur: String(resultat.reason) }];
    }
    const erreur = (resultat.value as { error?: { message?: string } }).error?.message;
    return erreur
      ? [{ destinataire: index === 0 ? 'SOIGNANT' : 'ETABLISSEMENT', erreur }]
      : [];
  });
  if (erreurs.length > 0) {
    console.warn('[generate-invoice] email emission differe', erreurs);
    await supabaseAdmin.from('invoice_audit_log').insert({
      invoice_id: facture.id,
      action: 'EMAIL_EMISSION_A_REESSAYER',
      actor_id: null,
      payload_before: null,
      payload_after: { erreurs },
    });
  }
}

type RegimeTvaHonoraires =
  | 'EXONERE_ART_261_4_1'
  | 'FRANCHISE_EN_BASE_ART_293_B'
  | 'ASSUJETTI_TVA';

type StatutTvaHonoraires = 'FRANCHISE_EN_BASE' | 'REDEVABLE_TVA';
type NatureTvaPrestation = 'SOIN_THERAPEUTIQUE_EXONERE' | 'PRESTATION_TAXABLE';

type TraitementTva = {
  regime: RegimeTvaHonoraires;
  vatExempt: boolean;
  vatRate: number;
  exemptionReason: string;
  legalBasis: string;
  serviceNature: string;
};

function traitementTvaDepuisRegimeSnapshot(
  regime: string | null | undefined,
  issueDate: string,
): TraitementTva {
  const cibSApplicable = issueDate >= '2026-09-01';
  if (regime === 'EXONERE_ART_261_4_1') {
    return {
      regime,
      vatExempt: true,
      vatRate: 0,
      exemptionReason: cibSApplicable
        ? 'Exoneration de TVA - article L. 213-98 du CIBS - soins a finalite therapeutique'
        : 'Exoneration de TVA - article 261, 4, 1 du CGI - soins a la personne a finalite therapeutique',
      legalBasis: cibSApplicable
        ? 'Article L. 213-98 du CIBS'
        : 'Article 261, 4, 1° du CGI',
      serviceNature: 'SOINS_A_LA_PERSONNE_FINALITE_THERAPEUTIQUE',
    };
  }
  if (regime === 'FRANCHISE_EN_BASE_ART_293_B') {
    return {
      regime,
      vatExempt: true,
      vatRate: 0,
      exemptionReason: 'TVA non applicable, art. 293 B du CGI',
      legalBasis: 'Article 293 B du CGI',
      serviceNature: 'HONORAIRES_EN_FRANCHISE_EN_BASE',
    };
  }
  if (regime === 'ASSUJETTI_TVA') {
    return {
      regime,
      vatExempt: false,
      vatRate: 20,
      exemptionReason: '',
      legalBasis: cibSApplicable
        ? 'Article L. 213-151 du CIBS'
        : 'Article 278 du CGI',
      serviceNature: 'PRESTATION_HORS_EXONERATION_DE_SOIN',
    };
  }
  throw new Error('REGIME_TVA_HONORAIRES_INVALIDE');
}

function traitementTva(
  statut: string | null | undefined,
  nature: string | null | undefined,
  issueDate: string,
): TraitementTva {
  if (nature === 'SOIN_THERAPEUTIQUE_EXONERE') {
    return traitementTvaDepuisRegimeSnapshot('EXONERE_ART_261_4_1', issueDate);
  }
  if (nature !== 'PRESTATION_TAXABLE') {
    throw new Error('NATURE_TVA_PRESTATION_INVALIDE');
  }
  if (statut === 'FRANCHISE_EN_BASE') {
    return traitementTvaDepuisRegimeSnapshot('FRANCHISE_EN_BASE_ART_293_B', issueDate);
  }
  if (statut === 'REDEVABLE_TVA') {
    return traitementTvaDepuisRegimeSnapshot('ASSUJETTI_TVA', issueDate);
  }
  throw new Error('STATUT_TVA_HONORAIRES_INVALIDE');
}

async function sha256Hex(value: Uint8Array | string): Promise<string> {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function cheminDocumentVersionne(
  repertoire: 'invoices' | 'avoirs',
  soignantId: string,
  numeroFacture: string,
  extension: 'pdf' | 'xml',
): string {
  return `${repertoire}/${soignantId}/${numeroFacture}/${crypto.randomUUID()}.${extension}`;
}

/* ── XML CII Generator (Factur-X BASIC / EN16931) ── */

/** Construire la mention du mandat avec la référence en vigueur à l'émission. */
function buildSubrogationMention(
  soignant: { prenom: string; nom: string; siret_liberal?: string | null },
  issueDate: string,
): string {
  const joleneSiret = Deno.env.get('JOLENE_SIRET') || '';
  const soignantFullName = `${soignant.prenom} ${soignant.nom}`.trim();
  const soignantSiret = soignant.siret_liberal || '(SIRET non renseigne)';
  const referenceMandat = issueDate >= '2026-09-01'
    ? "l'article L. 216-43 du Code des impositions sur les biens et services"
    : "l'article 289 I-2 du CGI";
  return `Facture emise par JOLENE SASU (SIRET ${joleneSiret}) en qualite de mandataire de facturation au nom et pour le compte de ${soignantFullName} (SIRET ${soignantSiret}), conformement a ${referenceMandat} et a l'article 242 nonies A de l'annexe II au CGI.`;
}

function generateCiiXml(inv: {
  invoiceNumber: string;
  issueDate: string;
  dueDate: string;
  sellerName: string;
  sellerSiret: string;
  sellerVatId?: string;
  sellerRpps: string;
  sellerAdeli: string;
  sellerAddress: string;
  sellerCity: string;
  sellerPostalCode: string;
  sellerEmail: string;
  buyerName: string;
  buyerSiret: string;
  buyerAddress: string;
  buyerCity: string;
  buyerPostalCode: string;
  serviceDate?: string;
  serviceCode: string;
  description: string;
  quantity?: number | null;
  unitPriceHt?: number | null;
  amountHt: number;
  amountTva: number;
  amountTtc: number;
  vatRate: number;
  vatExempt: boolean;
  vatExemptionReason: string;
  currencyCode: string;
  factorIban?: string;
  factorBic?: string;
  factorName?: string;
  subrogationMention?: string;
  // CP-LITIGES-6 : mode AVOIR (BT-3=381 + BT-25/BT-26)
  isAvoir?: boolean;
  precedingInvoiceNumber?: string;  // BT-25
  precedingInvoiceIssueDate?: string; // BT-26 (YYYY-MM-DD)
}): string {
  const fmtDate = (d: string) => d.replace(/-/g, '');
  const fmtAmt = (n: number) => n.toFixed(2);
  const sellerSiret = String(inv.sellerSiret || '').replace(/\D/g, '');
  const buyerSiret = String(inv.buyerSiret || '').replace(/\D/g, '');
  if (!/^\d{14}$/.test(sellerSiret) || !/^\d{14}$/.test(buyerSiret)) {
    throw new Error('SIRET_EMETTEUR_OU_DESTINATAIRE_INVALIDE');
  }
  const sellerSiren = sellerSiret.slice(0, 9);
  const buyerSiren = buyerSiret.slice(0, 9);
  const sellerEmailBlock = inv.sellerEmail
    ? `<ram:URIUniversalCommunication><ram:URIID schemeID="EM">${escapeXml(inv.sellerEmail)}</ram:URIID></ram:URIUniversalCommunication>`
    : '';
  const sellerTaxRegistration = inv.sellerVatId
    ? `<ram:SpecifiedTaxRegistration><ram:ID schemeID="VA">${escapeXml(inv.sellerVatId)}</ram:ID></ram:SpecifiedTaxRegistration>`
    : `<ram:SpecifiedTaxRegistration><ram:ID schemeID="FC">${sellerSiren}</ram:ID></ram:SpecifiedTaxRegistration>`;
  const hourlyLineIsConsistent = Number.isFinite(inv.quantity)
    && Number.isFinite(inv.unitPriceHt)
    && Number(inv.quantity) > 0
    && Number(inv.unitPriceHt) > 0
    && Math.abs(Number(inv.quantity) * Number(inv.unitPriceHt) - inv.amountHt) <= 0.02;
  const billedQuantity = hourlyLineIsConsistent ? Number(inv.quantity) : 1;
  const unitPriceHt = hourlyLineIsConsistent ? Number(inv.unitPriceHt) : inv.amountHt;
  const unitCode = hourlyLineIsConsistent ? 'HUR' : 'C62';
  // AVOIR : le code 381 porte le sens créditeur. En EN 16931/Factur-X, les
  // quantités et montants d'un avoir classique gardent le même signe positif
  // que la facture annulée ; un type 381 avec totaux négatifs inverserait deux
  // fois le sens et casserait aussi la réconciliation ligne/en-tête.
  const typeCode = inv.isAvoir ? '381' : '380';
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
       <ram:ExemptionReason>${escapeXml(inv.vatExemptionReason)}</ram:ExemptionReason>
       <ram:CategoryCode>E</ram:CategoryCode>
       <ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>`
    : `<ram:TypeCode>VAT</ram:TypeCode>
       <ram:CategoryCode>S</ram:CategoryCode>
       <ram:RateApplicablePercent>${fmtAmt(inv.vatRate)}</ram:RateApplicablePercent>`;
  const headerVatTax = inv.vatExempt
    ? `<ram:CalculatedAmount>${fmtAmt(inv.amountTva)}</ram:CalculatedAmount>
       <ram:TypeCode>VAT</ram:TypeCode>
       <ram:ExemptionReason>${escapeXml(inv.vatExemptionReason)}</ram:ExemptionReason>
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
        <ram:NetPriceProductTradePrice><ram:ChargeAmount>${fmtAmt(unitPriceHt)}</ram:ChargeAmount></ram:NetPriceProductTradePrice>
      </ram:SpecifiedLineTradeAgreement>
      <ram:SpecifiedLineTradeDelivery><ram:BilledQuantity unitCode="${unitCode}">${fmtAmt(billedQuantity)}</ram:BilledQuantity></ram:SpecifiedLineTradeDelivery>
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
        ${sellerEmailBlock}
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
      <ram:InvoiceCurrencyCode>${inv.currencyCode}</ram:InvoiceCurrencyCode>
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
        <ram:TaxTotalAmount currencyID="${inv.currencyCode}">${fmtAmt(inv.amountTva)}</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>${fmtAmt(inv.amountTtc)}</ram:GrandTotalAmount>
        <ram:DuePayableAmount>${fmtAmt(inv.amountTtc)}</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
      ${precedingRef}
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>`;
}

function escapeXml(s: string): string {
  return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

/* ── PDF Generator (pdf-lib, mentions légales art. 242 nonies CGI) ── */
async function generateInvoicePdf(inv: {
  invoiceNumber: string;
  issueDate: string;
  dueDate: string;
  sellerName: string;
  sellerProfession: string;
  sellerSiret: string;
  sellerRpps: string;
  sellerAdeli: string;
  sellerAddress: string;
  buyerName: string;
  buyerSiret: string;
  buyerAddress: string;
  description: string;
  quantity?: number | null;
  unitPriceHt?: number | null;
  amountHt: number;
  amountTva: number;
  amountTtc: number;
  vatExempt: boolean;
  vatExemptionReason: string;
  subrogationMention?: string;
  factorName?: string;
  factorIban?: string;
  mandatVersion: string;
  // CP-LITIGES-6 : mode AVOIR
  isAvoir?: boolean;
  precedingInvoiceNumber?: string;
  precedingInvoiceIssueDate?: string;
  motifAvoir?: string;  // issu de litiges.resolution
  // CP-LITIGES-7a FIX 7 : tampons ANNULEE / REMPLACEE
  statut?: string;
  replacedByInvoiceNumber?: string;
}): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([595, 842]); // A4
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const fontSize = 9;
  const titleSize = 14;
  const sectionSize = 10;
  const black = rgb(0, 0, 0);
  const grey = rgb(0.4, 0.4, 0.4);
  const pink = rgb(0.878, 0.271, 0.565); // #E04590
  const red = rgb(0.86, 0.15, 0.15);     // AVOIR title
  const sign = inv.isAvoir ? -1 : 1;
  const signedAmt = (n: number) => `${(n * sign).toFixed(2)} EUR`;
  const mandateLegalReference = inv.issueDate >= '2026-09-01'
    ? 'art. L. 216-43 du CIBS'
    : 'art. 289 I-2 du CGI';
  const w = page.getWidth();
  let y = 800;
  const margin = 50;

  function drawText(text: string, x: number, yPos: number, options?: { font?: typeof font; size?: number; color?: typeof black }) {
    page.drawText(text, {
      x, y: yPos,
      font: options?.font || font,
      size: options?.size || fontSize,
      color: options?.color || black,
    });
  }

  function drawLine(yPos: number) {
    page.drawLine({ start: { x: margin, y: yPos }, end: { x: w - margin, y: yPos }, thickness: 0.5, color: grey });
  }

  // Header
  drawText('Jolene', margin, y, { font: fontBold, size: 18, color: pink });
  const titleText = inv.isAvoir ? 'AVOIR' : "FACTURE D'HONORAIRES";
  const titleColor = inv.isAvoir ? red : black;
  const titleOffset = inv.isAvoir ? 80 : 180;
  drawText(titleText, w - margin - titleOffset, y, { font: fontBold, size: titleSize, color: titleColor });
  y -= 25;
  drawLine(y);
  y -= 20;

  // Invoice meta
  drawText(`Numero : ${inv.invoiceNumber}`, margin, y, { font: fontBold, size: sectionSize });
  y -= 14;
  drawText(`Date d'emission : ${inv.issueDate}`, margin, y);
  drawText(`Date d'echeance : ${inv.dueDate}`, margin + 200, y);
  y -= 14;

  // CP-LITIGES-6 : mention obligatoire AVOIR (art. L441-10 C. com.)
  if (inv.isAvoir && inv.precedingInvoiceNumber) {
    drawText(
      `Avoir emis sur facture n. ${inv.precedingInvoiceNumber}${inv.precedingInvoiceIssueDate ? ` du ${inv.precedingInvoiceIssueDate}` : ''}`,
      margin, y, { font: fontBold, size: sectionSize, color: red }
    );
    y -= 14;
    if (inv.motifAvoir) {
      drawText(`Motif : ${inv.motifAvoir.substring(0, 90)}`, margin, y, { size: 8, color: grey });
      y -= 12;
    }
  }
  // CP-LITIGES-7a FIX 7 : mention rectification pour facture REMPLACEE
  if (inv.statut === 'REMPLACEE') {
    const orange = rgb(0.95, 0.55, 0.05);
    const mentionReplace = inv.replacedByInvoiceNumber
      ? `Facture rectificative remplacee par ${inv.replacedByInvoiceNumber} (art. L441-9 C. com.).`
      : `Facture rectifiee et remplacee (art. L441-9 C. com.).`;
    drawText(mentionReplace, margin, y, { font: fontBold, size: sectionSize, color: orange });
    y -= 14;
  }
  y -= 10;

  // Seller block
  drawText('EMETTEUR (Professionnel de sante)', margin, y, { font: fontBold, size: sectionSize });
  y -= 14;
  drawText(inv.sellerName, margin, y, { font: fontBold });
  y -= 12;
  drawText(`Profession : ${inv.sellerProfession}`, margin, y);
  y -= 12;
  drawText(`SIRET : ${inv.sellerSiret}`, margin, y);
  y -= 12;
  if (inv.sellerRpps) { drawText(`N. RPPS : ${inv.sellerRpps}`, margin, y); y -= 12; }
  if (inv.sellerAdeli) { drawText(`N. ADELI : ${inv.sellerAdeli}`, margin, y); y -= 12; }
  drawText(`Adresse : ${inv.sellerAddress}`, margin, y);
  y -= 16;
  drawText(`Facture emise par Jolene SASU en qualite de mandataire`, margin, y, { color: grey, size: 8 });
  y -= 10;
  drawText(`de facturation (${mandateLegalReference}), mandat v${inv.mandatVersion}.`, margin, y, { color: grey, size: 8 });
  y -= 20;

  // Buyer block
  drawLine(y); y -= 15;
  drawText('DESTINATAIRE', margin, y, { font: fontBold, size: sectionSize });
  y -= 14;
  drawText(inv.buyerName, margin, y, { font: fontBold });
  y -= 12;
  drawText(`SIRET : ${inv.buyerSiret}`, margin, y);
  y -= 12;
  drawText(`Adresse : ${inv.buyerAddress}`, margin, y);
  y -= 25;

  // Description
  drawLine(y); y -= 15;
  drawText('DETAIL DE LA PRESTATION', margin, y, { font: fontBold, size: sectionSize });
  y -= 14;
  // Wrap long description
  const descWords = inv.description.split(' ');
  let line = '';
  for (const word of descWords) {
    const test = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(test, fontSize) > w - 2 * margin) {
      drawText(line, margin, y); y -= 12;
      line = word;
    } else {
      line = test;
    }
  }
  if (line) { drawText(line, margin, y); y -= 20; }

  const hourlyLineIsConsistent = Number.isFinite(inv.quantity)
    && Number.isFinite(inv.unitPriceHt)
    && Number(inv.quantity) > 0
    && Number(inv.unitPriceHt) > 0
    && Math.abs(Number(inv.quantity) * Number(inv.unitPriceHt) - inv.amountHt) <= 0.02;
  if (hourlyLineIsConsistent) {
    drawText(
      `Quantite : ${Number(inv.quantity).toFixed(2)} h · Prix unitaire HT : ${Number(inv.unitPriceHt).toFixed(2)} EUR/h`,
      margin,
      y,
      { size: 8, color: grey },
    );
    y -= 18;
  }

  // Amounts table
  drawLine(y); y -= 15;
  drawText('MONTANTS', margin, y, { font: fontBold, size: sectionSize });
  y -= 18;
  // Table header
  drawText('Designation', margin, y, { font: fontBold, size: 8 });
  drawText('HT', w - margin - 180, y, { font: fontBold, size: 8 });
  drawText('TVA', w - margin - 120, y, { font: fontBold, size: 8 });
  drawText('TTC', w - margin - 60, y, { font: fontBold, size: 8 });
  y -= 4; drawLine(y); y -= 12;
  // Table row (amounts signés pour AVOIR)
  drawText(inv.isAvoir ? 'Avoir' : 'Honoraires', margin, y, { size: 8 });
  drawText(signedAmt(inv.amountHt), w - margin - 180, y, { size: 8 });
  drawText(signedAmt(inv.amountTva), w - margin - 120, y, { size: 8 });
  drawText(signedAmt(inv.amountTtc), w - margin - 60, y, { size: 8 });
  y -= 4; drawLine(y); y -= 12;
  // Totals
  drawText('TOTAL', margin, y, { font: fontBold });
  drawText(signedAmt(inv.amountHt), w - margin - 180, y, { font: fontBold });
  drawText(signedAmt(inv.amountTva), w - margin - 120, y, { font: fontBold });
  drawText(signedAmt(inv.amountTtc), w - margin - 60, y, { font: fontBold });
  y -= 20;

  // VAT exemption
  if (inv.vatExempt && inv.vatExemptionReason) {
    drawText(inv.vatExemptionReason, margin, y, { size: 8, color: grey });
    y -= 18;
  }

  // Subrogation
  if (inv.subrogationMention) {
    drawLine(y); y -= 15;
    drawText('MENTION SUBROGATIVE', margin, y, { font: fontBold, size: sectionSize });
    y -= 14;
    drawText(inv.subrogationMention, margin, y, { size: 8 });
    y -= 12;
    if (inv.factorName) { drawText(`Paiement a l'ordre de : ${inv.factorName}`, margin, y, { size: 8 }); y -= 12; }
    if (inv.factorIban) { drawText(`IBAN : ${inv.factorIban}`, margin, y, { size: 8 }); y -= 12; }
    y -= 10;
  }

  if (!inv.isAvoir) {
    drawText('Escompte pour paiement anticipe : neant.', margin, y, { size: 7, color: grey });
    y -= 10;
    drawText('Penalites de retard : taux de refinancement BCE majore de 10 points, exigibles sans rappel.', margin, y, { size: 7, color: grey });
    y -= 10;
    drawText('Indemnite forfaitaire pour frais de recouvrement en cas de retard : 40 EUR.', margin, y, { size: 7, color: grey });
    y -= 12;
  }

  // Footer
  drawLine(y); y -= 15;
  drawText('Jolene SASU - Mandataire de facturation', margin, y, { size: 7, color: grey });
  y -= 10;
  drawText(mandateLegalReference, margin, y, { size: 7, color: grey });

  // CP-LITIGES-7a FIX 7 : tampon diagonal ANNULEE / REMPLACEE
  if (inv.statut === 'ANNULEE' || inv.statut === 'REMPLACEE') {
    const isAnnulee = inv.statut === 'ANNULEE';
    const stampColor = isAnnulee
      ? rgb(0.86, 0.15, 0.15)  // red
      : rgb(0.95, 0.55, 0.05); // orange
    const stampMain = isAnnulee ? 'ANNULEE' : 'REMPLACEE';
    const stampSub = !isAnnulee && inv.replacedByInvoiceNumber
      ? `par facture ${inv.replacedByInvoiceNumber}`
      : null;
    const rot = degrees(30);
    // Anchor tuned for visual centering of a diagonal stamp on A4 (595x842).
    page.drawText(stampMain, {
      x: 90, y: 320,
      font: fontBold, size: 100,
      color: stampColor, opacity: 0.35,
      rotate: rot,
    });
    if (stampSub) {
      page.drawText(stampSub, {
        x: 170, y: 280,
        font: fontBold, size: 22,
        color: stampColor, opacity: 0.45,
        rotate: rot,
      });
    }
  }

  return await pdfDoc.save();
}

/* ── Main Handler ── */

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(req) });

  // Rate-limit IP : 30 générations facture/min/IP (en plus du rate-limit
  // service_role spécifique plus bas pour les appels cron).
  if (applyRateLimit('generate-invoice', getClientIp(req), { max: 30, windowMs: 60_000 })) {
    return json(req, { error: 'Trop de demandes. Réessayez dans 1 minute.' }, 429);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json(req, { error: 'Non autorisé' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const token = authHeader.replace('Bearer ', '');
    const isServiceRole = token === serviceRoleKey;
    let authenticatedUserId: string | null = null;
    // Le client porte le JWT utilisateur pour que le RPC RBAC évalue son rôle,
    // et non le service_role utilisé pour la génération des artefacts.
    let authenticatedClient: any = null;

    const body = await req.json();
    const {
      mission_id,
      facture_id,
      service_role_reason,
      // Partie 2 — facturation hebdomadaire libérale (optionnels)
      // Quand fournis, génère une facture hebdo intermédiaire ou finale partielle
      // pour la période donnée. Quand absents, comportement actuel (mission entière).
      periode_debut,        // 'YYYY-MM-DD' ou undefined
      periode_fin,          // 'YYYY-MM-DD' ou undefined
      numero_semaine_iso,   // smallint ou undefined (NULL pour finale unique)
      annee_iso,            // smallint ou undefined
      est_facture_finale_mission, // boolean (default true si périodes absentes)
    } = body;
    if (!mission_id && !facture_id) {
      return json(req, { error: 'mission_id ou facture_id requis' }, 400);
    }
    const isHebdoMode = !!(mission_id && periode_debut && periode_fin);
    const isFinaleFromHebdo = !!(mission_id && periode_debut && periode_fin && est_facture_finale_mission === true);

    // ── Service_role bypass: validate reason + rate limit ──
    if (isServiceRole) {
      const reasonCheck = validateServiceRoleReason(service_role_reason);
      if (!reasonCheck.valid) {
        console.warn(`[generate-invoice] service_role rejected: ${reasonCheck.error}`);
        if (reasonCheck.error?.includes('invalid_reason')) {
          return json(req, { error: reasonCheck.error }, 403);
        }
        return json(req, { error: reasonCheck.error }, 400);
      }
      if (!checkServiceRoleRateLimit()) {
        console.warn(`[generate-invoice] service_role rate limited (>${SERVICE_ROLE_MAX_PER_MIN}/min)`);
        return json(req, { error: 'Rate limit: max 10 appels service_role par minute' }, 429);
      }
      console.log(`[generate-invoice] service_role call: reason="${service_role_reason}"`);
    } else {
      // ── JWT user validation ──
      const supabaseUser = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: userData, error: authError } = await supabaseUser.auth.getUser(token);
      if (authError || !userData?.user) return json(req, { error: 'Token invalide' }, 401);
      authenticatedUserId = userData.user.id;
      authenticatedClient = supabaseUser;
    }

    // ═══════════════════════════════════════════════════════════
    // MODE REGEN (CP-LITIGES-6) — facture_id fourni
    // Regénère PDF + XML CII + upload S3 + éventuelle resoumission Chorus
    // pour une facture existante (cas AVOIR ou ANNULER_REEMETTRE).
    // ═══════════════════════════════════════════════════════════
    if (facture_id && !mission_id) {
      const { data: facture, error: fErr } = await supabaseAdmin
        .from('factures_honoraires')
        .select('id, numero_facture, soignant_id, etablissement_id, mission_id, montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva, date_emission, date_echeance, statut, mandat_version, type_document, facture_precedente_id, litige_id, is_public_sector, service_code_chorus, periode_debut, periode_fin, numero_semaine_iso, annee_iso, est_facture_finale_mission, nature_correction, regime_tva_snapshot, base_legale_tva_snapshot, nature_prestation_snapshot, description_prestation_snapshot, quantite_heures_snapshot, taux_horaire_snapshot, emetteur_identite_snapshot, emetteur_profession_snapshot, emetteur_siret_snapshot, emetteur_numero_professionnel_snapshot, emetteur_adresse_snapshot, emetteur_adresse_rue_snapshot, emetteur_adresse_code_postal_snapshot, emetteur_adresse_ville_snapshot, emetteur_email_snapshot, emetteur_numero_tva_snapshot, destinataire_nom_snapshot, destinataire_siret_snapshot, destinataire_adresse_rue_snapshot, destinataire_adresse_code_postal_snapshot, destinataire_adresse_ville_snapshot')
        .eq('id', facture_id)
        .single();
      if (fErr || !facture) return json(req, { error: 'Facture introuvable' }, 404);

      if (!isServiceRole) {
        const { data: canManagePayment, error: permissionError } = await authenticatedClient!.rpc(
          'fn_a_permission_etablissement',
          { p_permission: 'paiement', p_etablissement_id: facture.etablissement_id },
        );
        if (permissionError || (!canManagePayment && authenticatedUserId !== facture.soignant_id)) {
          return json(req, { error: 'Accès refusé à cette facture' }, 403);
        }
      }

      // Charger soignant + etab + mission (lookup pour description)
      const [{ data: sg }, { data: et }, { data: ms }] = await Promise.all([
        supabaseAdmin.from('soignants').select('id, prenom, nom, profession, numero_rpps, numero_adeli, siret_liberal, email, adresse_rue, adresse_ville, adresse_code_postal, assujetti_tva, numero_tva, regime_tva_honoraires').eq('id', facture.soignant_id).single(),
        supabaseAdmin.from('etablissements').select('id, nom, siret, adresse_rue, adresse_ville, adresse_code_postal, est_secteur_public, chorus_pro_actif').eq('id', facture.etablissement_id).single(),
        supabaseAdmin.from('missions').select('id, intitule, service, debut_le, fin_le, duree_heures').eq('id', facture.mission_id).maybeSingle(),
      ]);
      if (!sg || !et) return json(req, { error: 'Soignant/établissement introuvable' }, 404);

      const isAvoir = facture.type_document === 'AVOIR';
      let precedingNumero: string | null = null;
      let precedingDate: string | null = null;
      let motifAvoir: string | null = null;
      let replacedByNumero: string | null = null;

      if (isAvoir && !facture.facture_precedente_id) {
          return json(req, { error: 'AVOIR sans facture_precedente_id — incohérence critique' }, 400);
      }
      if (facture.facture_precedente_id) {
        const { data: prec } = await supabaseAdmin
          .from('factures_honoraires')
          .select('numero_facture, date_emission')
          .eq('id', facture.facture_precedente_id)
          .single();
        precedingNumero = prec?.numero_facture ?? null;
        precedingDate = prec?.date_emission ?? null;

        if (isAvoir && facture.litige_id) {
          const { data: lit } = await supabaseAdmin
            .from('litiges')
            .select('resolution')
            .eq('id', facture.litige_id)
            .single();
          motifAvoir = lit?.resolution ?? null;
        }
      }

      // CP-LITIGES-7a FIX 7 : pour tampon REMPLACEE, lookup successeur
      if (facture.statut === 'REMPLACEE') {
        const { data: succ } = await supabaseAdmin
          .from('factures_honoraires')
          .select('numero_facture, cree_le')
          .eq('facture_precedente_id', facture.id)
          .order('cree_le', { ascending: false })
          .limit(1)
          .maybeSingle();
        replacedByNumero = succ?.numero_facture ?? null;
      }

      const regimeSnapshot = facture.regime_tva_snapshot
        || sg.regime_tva_honoraires
        || (facture.exoneration_tva ? 'EXONERE_ART_261_4_1' : 'ASSUJETTI_TVA');
      const vat = traitementTvaDepuisRegimeSnapshot(regimeSnapshot, facture.date_emission);
      const sellerName = facture.emetteur_identite_snapshot || `${sg.prenom} ${sg.nom}`.trim();
      const sellerProfession = facture.emetteur_profession_snapshot || sg.profession || '';
      const sellerSiret = facture.emetteur_siret_snapshot || sg.siret_liberal || '';
      const sellerProfessionalNumber = facture.emetteur_numero_professionnel_snapshot || sg.numero_rpps || sg.numero_adeli || '';
      const sellerStreet = facture.emetteur_adresse_rue_snapshot || sg.adresse_rue || '';
      const sellerPostalCode = facture.emetteur_adresse_code_postal_snapshot || sg.adresse_code_postal || '';
      const sellerCity = facture.emetteur_adresse_ville_snapshot || sg.adresse_ville || '';
      const sellerEmail = facture.emetteur_email_snapshot || sg.email || '';
      const sellerVatId = facture.emetteur_numero_tva_snapshot || sg.numero_tva || '';
      const sellerAddress = facture.emetteur_adresse_snapshot
        || [sellerStreet, sellerPostalCode, sellerCity].filter(Boolean).join(', ');
      const buyerName = facture.destinataire_nom_snapshot || et.nom;
      const buyerSiret = facture.destinataire_siret_snapshot || et.siret || '';
      const buyerStreet = facture.destinataire_adresse_rue_snapshot || et.adresse_rue || '';
      const buyerPostalCode = facture.destinataire_adresse_code_postal_snapshot || et.adresse_code_postal || '';
      const buyerCity = facture.destinataire_adresse_ville_snapshot || et.adresse_ville || '';
      const buyerAddress = [buyerStreet, buyerPostalCode, buyerCity].filter(Boolean).join(', ');
      const description = facture.description_prestation_snapshot || (isAvoir
        ? `Avoir sur facture ${precedingNumero ?? ''}${motifAvoir ? ' — ' + motifAvoir.substring(0, 100) : ''}`
        : facture.nature_correction === 'COMPLEMENT'
        ? `Complement d'honoraires apres litige sur facture ${precedingNumero ?? ''}`
        : facture.est_facture_finale_mission === false && facture.numero_semaine_iso
        ? `Facture hebdomadaire S${facture.numero_semaine_iso}/${facture.annee_iso} — ${ms?.intitule || 'Mission'} — Periode du ${facture.periode_debut} au ${facture.periode_fin}`
        : facture.est_facture_finale_mission && facture.periode_debut && facture.periode_fin
        ? `Facture finale — ${ms?.intitule || 'Mission'} — Periode du ${facture.periode_debut} au ${facture.periode_fin}`
        : `Honoraires — ${ms?.intitule || 'Mission'} (${ms?.service || ''}) du ${ms?.debut_le || ''} au ${ms?.fin_le || ''} — ${ms?.duree_heures || 0}h`);

      const subrogationMention = buildSubrogationMention({
        prenom: sellerName,
        nom: '',
        siret_liberal: sellerSiret,
      }, facture.date_emission);

      const xmlCii = generateCiiXml({
        invoiceNumber: facture.numero_facture,
        issueDate: facture.date_emission,
        dueDate: facture.date_echeance,
        sellerName,
        sellerSiret,
        sellerVatId,
        sellerRpps: sellerProfessionalNumber,
        sellerAdeli: '',
        sellerAddress: sellerStreet,
        sellerCity,
        sellerPostalCode,
        sellerEmail,
        buyerName,
        buyerSiret,
        buyerAddress: buyerStreet,
        buyerCity,
        buyerPostalCode,
        serviceDate: facture.periode_fin || (ms?.fin_le ? String(ms.fin_le).slice(0, 10) : facture.date_emission),
        serviceCode: facture.service_code_chorus || '',
        description,
        quantity: Number(facture.quantite_heures_snapshot) || null,
        unitPriceHt: Number(facture.taux_horaire_snapshot) || null,
        amountHt: Number(facture.montant_ht) || 0,
        amountTva: Number(facture.montant_tva) || 0,
        amountTtc: Number(facture.montant_ttc) || 0,
        vatRate: Number(facture.taux_tva) || vat.vatRate,
        vatExempt: !!facture.exoneration_tva,
        vatExemptionReason: facture.exoneration_tva ? vat.exemptionReason : '',
        currencyCode: 'EUR',
        subrogationMention,
        isAvoir,
        precedingInvoiceNumber: precedingNumero ?? undefined,
        precedingInvoiceIssueDate: precedingDate ?? undefined,
      });

      const pdfBytes = await generateInvoicePdf({
        invoiceNumber: facture.numero_facture,
        issueDate: facture.date_emission,
        dueDate: facture.date_echeance,
        sellerName,
        sellerProfession,
        sellerSiret,
        sellerRpps: sellerProfessionalNumber,
        sellerAdeli: '',
        sellerAddress,
        buyerName,
        buyerSiret,
        buyerAddress,
        description,
        quantity: Number(facture.quantite_heures_snapshot) || null,
        unitPriceHt: Number(facture.taux_horaire_snapshot) || null,
        amountHt: Number(facture.montant_ht) || 0,
        amountTva: Number(facture.montant_tva) || 0,
        amountTtc: Number(facture.montant_ttc) || 0,
        vatExempt: !!facture.exoneration_tva,
        vatExemptionReason: facture.exoneration_tva ? vat.exemptionReason : '',
        mandatVersion: facture.mandat_version || '1.1',
        subrogationMention,
        isAvoir,
        precedingInvoiceNumber: precedingNumero ?? undefined,
        precedingInvoiceIssueDate: precedingDate ?? undefined,
        motifAvoir: motifAvoir ?? undefined,
        statut: facture.statut,
        replacedByInvoiceNumber: replacedByNumero ?? undefined,
      });

      const subDir = isAvoir ? 'avoirs' : 'invoices';
      const storagePath = cheminDocumentVersionne(subDir, sg.id, facture.numero_facture, 'pdf');
      const xmlPath = cheminDocumentVersionne(subDir, sg.id, facture.numero_facture, 'xml');

      const { error: regenPdfUploadError } = await supabaseAdmin.storage.from('jolene-documents')
        .upload(storagePath, creerBlobPdf(pdfBytes), { upsert: false });
      const { error: regenXmlUploadError } = await supabaseAdmin.storage.from('jolene-documents')
        .upload(xmlPath, new Blob([xmlCii], { type: 'application/xml' }), { upsert: false });
      if (regenPdfUploadError || regenXmlUploadError) {
        if (['BROUILLON', 'EN_GENERATION'].includes(facture.statut)) {
          await supabaseAdmin.from('factures_honoraires')
            .update({ statut: 'ERREUR_GENERATION' })
            .eq('id', facture_id)
            .in('statut', ['BROUILLON', 'EN_GENERATION']);
        }
        return json(req, {
          error: `Échec régénération stockage : ${regenPdfUploadError?.message || regenXmlUploadError?.message}`,
        }, 500);
      }

      const [pdfSha256, xmlSha256] = await Promise.all([
        sha256Hex(pdfBytes),
        sha256Hex(xmlCii),
      ]);
      const { error: documentLedgerError } = await supabaseAdmin
        .from('factures_honoraires_documents')
        .insert({
          facture_honoraire_id: facture_id,
          pdf_s3_key: storagePath,
          facturx_xml_url: xmlPath,
          pdf_sha256: pdfSha256,
          xml_sha256: xmlSha256,
          motif_generation: ['BROUILLON', 'EN_GENERATION'].includes(facture.statut)
            ? 'EMISSION_DOCUMENT_CORRECTION'
            : 'REGENERATION_DOCUMENT_IMMUABLE',
        });
      if (documentLedgerError) {
        console.error('[generate-invoice] ledger regen error', documentLedgerError.message);
        if (['BROUILLON', 'EN_GENERATION'].includes(facture.statut)) {
          await supabaseAdmin.from('factures_honoraires')
            .update({ statut: 'ERREUR_GENERATION' })
            .eq('id', facture_id)
            .in('statut', ['BROUILLON', 'EN_GENERATION']);
        }
        return json(req, { error: 'Version documentaire non enregistrée — émission interrompue' }, 500);
      }

      const estPremiereEmission = ['BROUILLON', 'EN_GENERATION'].includes(facture.statut);
      let delaiVerificationHeures = 48;
      if (estPremiereEmission) {
        if (isAvoir) {
          const { error: avoirReferenceError } = await supabaseAdmin
            .from('factures_honoraires')
            .update({ chorus_avoir_reference_invoice: precedingNumero })
            .eq('id', facture_id);
          if (avoirReferenceError) {
            return json(req, {
              error: `Référence de l'avoir non enregistrée : ${avoirReferenceError.message}`,
            }, 500);
          }
        }
        const { data: emission, error: emissionError } = await supabaseAdmin.rpc(
          'fn_emettre_document_facturation_honoraires',
          {
            p_facture_id: facture_id,
            p_pdf_s3_key: storagePath,
            p_facturx_xml_url: xmlPath,
          },
        );
        if (emissionError || !(emission as any)?.success) {
          await supabaseAdmin.from('factures_honoraires')
            .update({ statut: 'ERREUR_GENERATION' })
            .eq('id', facture_id)
            .in('statut', ['BROUILLON', 'EN_GENERATION']);
          return json(req, {
            error: `Emission atomique échouée : ${emissionError?.message || 'réponse invalide'}`,
          }, 500);
        }
        delaiVerificationHeures = Number((emission as any).delai_verification_heures) || 48;
      } else {
        const { error: upErr } = await supabaseAdmin
          .from('factures_honoraires')
          .update({
            pdf_s3_key: storagePath,
            facturx_xml_url: xmlPath,
            pdf_a_regenerer: false,
            chorus_avoir_reference_invoice: isAvoir ? precedingNumero : null,
          })
          .eq('id', facture_id);
        if (upErr) return json(req, { error: `UPDATE facture échoué : ${upErr.message}` }, 500);
      }

      let commissionCorrection: Record<string, unknown> | null = null;
      if (isAvoir || ['COMPLEMENT', 'REMPLACEMENT'].includes(facture.nature_correction)) {
        const commissionRpc = isAvoir
          ? 'fn_preparer_avoir_commission_honoraires'
          : facture.nature_correction === 'COMPLEMENT'
            ? 'fn_preparer_commission_complement_honoraires'
            : 'fn_preparer_commission_remplacement_honoraires';
        const { data: commissionData, error: commissionError } = await supabaseAdmin
          .rpc(commissionRpc, {
            ...(isAvoir
              ? { p_avoir_honoraires_id: facture_id }
              : { p_facture_honoraire_id: facture_id }),
          });
        if (commissionError || !(commissionData as any)?.facture_id) {
          console.error('[generate-invoice] commission correction error', commissionError?.message);
          return json(req, {
            error: 'Facture corrigée émise mais facture de services Jolene à réparer',
            facture_id,
          }, 500);
        }
        commissionCorrection = commissionData as Record<string, unknown>;
      }

      if (facture.is_public_sector) {
        try {
          await supabaseAdmin.functions.invoke('submit-to-chorus', {
            body: { facture_honoraire_id: facture_id, type_document: facture.type_document },
          });
          if (commissionCorrection?.facture_id) {
            await supabaseAdmin.functions.invoke('chorus-pro-deposit', {
              body: { facture_id: commissionCorrection.facture_id, action: 'deposer' },
            });
          }
        } catch (e) { console.warn('Chorus regen deferred:', e); }
      }

      if (estPremiereEmission) {
        await notifierEmissionDocument(
          supabaseAdmin,
          {
            id: facture.id,
            numero_facture: facture.numero_facture,
            soignant_id: facture.soignant_id,
            etablissement_id: facture.etablissement_id,
            montant_ht: Number(facture.montant_ht),
            montant_tva: Number(facture.montant_tva),
            montant_ttc: Number(facture.montant_ttc),
            periode_debut: facture.periode_debut,
            periode_fin: facture.periode_fin,
            type_document: facture.type_document,
          },
          sg,
          delaiVerificationHeures,
        );
      }

      console.log(`[generate-invoice] REGEN ${facture.type_document} ${facture.numero_facture} (id=${facture_id})`);
      return json(req, {
        success: true,
        mode: 'regen',
        facture_id,
        type_document: facture.type_document,
        numero_facture: facture.numero_facture,
        pdf_path: storagePath,
        xml_path: xmlPath,
        facture_commission_id: commissionCorrection?.facture_id || null,
      });
    }

    if (!mission_id) return json(req, { error: 'mission_id requis' }, 400);

    // 1. Vérifier l'état de la mission. Une facture hebdomadaire intermédiaire
    // est volontairement émise pendant que la mission longue est EN_COURS ;
    // une facture unique/finale exige toujours TERMINEE.
    const { data: mission, error: mErr } = await supabaseAdmin
      .from('missions')
      .select('id, intitule, service, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, net_a_payer, montant_commission_ht, soignant_assigne_id, etablissement_id, statut, type_contrat_applique, strategie_facturation, nature_tva_prestation, nature_tva_confirmee_soignant, nature_tva_confirmee_par, statut_validation_tva')
      .eq('id', mission_id)
      .single();

    if (mErr || !mission) return json(req, { error: 'Mission introuvable' }, 404);
    if (!isServiceRole) {
      const { data: canManagePayment, error: permissionError } = await authenticatedClient!.rpc(
        'fn_a_permission_etablissement',
        { p_permission: 'paiement', p_etablissement_id: mission.etablissement_id },
      );
      if (permissionError || (!canManagePayment && authenticatedUserId !== mission.soignant_assigne_id)) {
        return json(req, { error: 'Accès refusé à cette mission' }, 403);
      }
    }
    if (!isHebdoMode && mission.statut !== 'TERMINEE') {
      return json(req, { error: `Mission en statut ${mission.statut}, doit être TERMINEE` }, 400);
    }
    if (isHebdoMode) {
      const debutMission = String(mission.debut_le || '').slice(0, 10);
      const finMission = String(mission.fin_le || '').slice(0, 10);
      const periodeValide = /^\d{4}-\d{2}-\d{2}$/.test(String(periode_debut))
        && /^\d{4}-\d{2}-\d{2}$/.test(String(periode_fin))
        && periode_debut <= periode_fin
        && periode_debut >= debutMission
        && periode_fin <= finMission;
      if (
        mission.strategie_facturation !== 'HEBDO_ET_FINALE'
        || !['EN_COURS', 'TERMINEE'].includes(mission.statut)
        || !periodeValide
      ) {
        return json(req, {
          error: 'PERIODE_HEBDOMADAIRE_INVALIDE',
          message: 'La période doit appartenir à une mission longue en cours ou terminée.',
        }, 400);
      }
      const aujourdHui = new Date().toISOString().slice(0, 10);
      if (est_facture_finale_mission === true) {
        if (mission.statut !== 'TERMINEE') {
          return json(req, { error: 'La facture finale exige une mission terminée.' }, 400);
        }
      } else if (periode_fin >= aujourdHui) {
        return json(req, { error: 'Une semaine doit être close avant facturation.' }, 400);
      }
    }

    // Fix E — garde type_contrat_applique selon docs/logique-paiements-v1 §1.
    // Jolene est mandataire de facturation UNIQUEMENT pour les missions LIBERAL
    // (art. 289 I-2 CGI). Les missions SALARIE passent par bulletin de paie,
    // pas par facture honoraires (sinon risque de requalification intérim).
    if (mission.type_contrat_applique === 'SALARIE') {
      return json(req, {
        error: 'CONTRAT_SALARIE_NON_FACTURE_HONORAIRES',
        message: "Les missions en contrat salarié passent par bulletin de paie, pas par facture honoraires. Seules les missions libérales génèrent une facture honoraires sous mandat de facturation.",
      }, 400);
    }
    if (mission.type_contrat_applique == null) {
      return json(req, {
        error: 'CONTRAT_NON_FIGE',
        message: "Le type de contrat doit être figé (mission assignée) avant de générer une facture honoraires. Assignez un soignant d'abord.",
      }, 400);
    }
    if (
      mission.statut_validation_tva !== 'CONFIRMEE'
      || !['SOIN_THERAPEUTIQUE_EXONERE', 'PRESTATION_TAXABLE'].includes(
        String(mission.nature_tva_prestation || ''),
      )
      || mission.nature_tva_confirmee_soignant !== mission.nature_tva_prestation
      || mission.nature_tva_confirmee_par !== mission.soignant_assigne_id
    ) {
      return json(req, {
        error: 'VALIDATION_TVA_MISSION_REQUISE',
        message: 'La nature TVA doit être confirmée par le soignant assigné. La mission et ses litiges restent actifs ; seule l’émission de la facture est suspendue.',
        statut_validation_tva: mission.statut_validation_tva,
      }, 409);
    }

    // 1b. Garde-fou pré-facturation CP5b (créneaux ouverts + écart > 10%)
    //     Partie 2 : passe la période si mode hebdo, sinon mission entière.
    const { data: preCheck, error: preCheckErr } = await supabaseAdmin
      .rpc('fn_verifier_pre_facturation', isHebdoMode
        ? { p_mission_id: mission_id, p_periode_debut: periode_debut, p_periode_fin: periode_fin }
        : { p_mission_id: mission_id });

    if (preCheckErr) {
      console.warn(`[generate-invoice] pré-facturation bloquée: ${preCheckErr.message}`);
      return json(req, { error: preCheckErr.message }, 400);
    }

    // 2. Vérifier mandat actif
    const { data: soignant } = await supabaseAdmin
      .from('soignants')
      .select('id, prenom, nom, profession, numero_rpps, numero_adeli, siret_liberal, email, adresse_rue, adresse_ville, adresse_code_postal, assujetti_tva, numero_tva, statut_tva_honoraires, mandat_facturation_signe, mandat_facturation_version')
      .eq('id', mission.soignant_assigne_id)
      .single();

    if (!soignant) return json(req, { error: 'Soignant introuvable' }, 404);
    if (!soignant.mandat_facturation_signe) {
      return json(req, { error: 'Mandat de facturation non signé. Le soignant doit signer le mandat avant de pouvoir générer une facture.' }, 400);
    }
    if (soignant.mandat_facturation_version !== '1.4') {
      return json(req, {
        error: 'MANDAT_FACTURATION_A_RENOUVELER',
        message: 'Le soignant doit signer la version 1.4 du mandat avant toute nouvelle facture.',
      }, 409);
    }
    if (!['FRANCHISE_EN_BASE', 'REDEVABLE_TVA'].includes(String(soignant.statut_tva_honoraires || ''))) {
      return json(req, {
        error: 'STATUT_TVA_HONORAIRES_MANQUANT',
        message: 'Le statut TVA de l’activité libérale doit être déclaré avant facturation.',
      }, 409);
    }
    const professionsRppsObligatoire = new Set([
      'MEDECIN',
      'DENTISTE',
      'SAGE_FEMME',
      'PHARMACIEN',
    ]);
    const profilFacturationIncomplet = [
      soignant.prenom,
      soignant.nom,
      soignant.profession,
      soignant.siret_liberal,
      soignant.email,
      soignant.adresse_rue,
      soignant.adresse_code_postal,
      soignant.adresse_ville,
    ].some((value) => !String(value || '').trim());
    if (profilFacturationIncomplet
      || (professionsRppsObligatoire.has(soignant.profession) && !soignant.numero_rpps)
      || !/^\d{14}$/.test(String(soignant.siret_liberal || '').replace(/\D/g, ''))
      || (soignant.statut_tva_honoraires === 'REDEVABLE_TVA' && !soignant.numero_tva)) {
      return json(req, {
        error: 'PROFIL_FACTURATION_INCOMPLET',
        message: 'Le profil professionnel est incomplet pour émettre une facture.',
      }, 409);
    }

    // 3. Vérifier établissement
    const { data: etab } = await supabaseAdmin
      .from('etablissements')
      .select('id, nom, siret, adresse_rue, adresse_ville, adresse_code_postal, est_secteur_public, chorus_pro_actif')
      .eq('id', mission.etablissement_id)
      .single();

    if (!etab) return json(req, { error: 'Établissement introuvable' }, 404);

    // 4. Vérifier pas de doublon
    //    - Mode finale unique (mission entière) : un seul est_facture_finale_mission=true par mission
    //    - Mode hebdo : un seul (mission, annee_iso, num_sem) avec est_facture_finale_mission=false
    {
      let q = supabaseAdmin
        .from('factures_honoraires')
        .select('id, numero_facture, est_facture_finale_mission, periode_debut, periode_fin')
        .eq('mission_id', mission_id)
        .neq('nature_correction', 'COMPLEMENT')
        .not('statut', 'in', '("ANNULEE","REMPLACEE","ERREUR_GENERATION")');
      if (isHebdoMode && est_facture_finale_mission !== true) {
        // doublon hebdo
        q = q.eq('annee_iso', annee_iso).eq('numero_semaine_iso', numero_semaine_iso).eq('est_facture_finale_mission', false);
      } else {
        // doublon finale (FINALE_UNIQUE ou facture finale partielle d'une mission HEBDO_ET_FINALE)
        q = q.eq('est_facture_finale_mission', true);
      }
      const { data: existing } = await q.maybeSingle();
      if (existing) {
        // Un retry du cron peut intervenir après l'émission de la note mais
        // avant la création de la facture de commission. Réparer ce second
        // artefact avant de répondre idempotent.
        const { error: commissionRepairError } = await supabaseAdmin.rpc(
          'fn_preparer_facture_commission_periode',
          { p_facture_honoraire_id: existing.id },
        );
        if (commissionRepairError) {
          return json(req, {
            error: `Facture honoraires existante mais commission non préparée : ${commissionRepairError.message}`,
            facture_id: existing.id,
          }, 500);
        }
        return json(req, { error: `Une facture existe déjà : ${existing.numero_facture}`, facture_id: existing.id }, 409);
      }
    }

    // 5. Générer le numéro de facture
    const { data: invoiceNumber, error: numErr } = await supabaseAdmin.rpc('next_invoice_number', {
      p_soignant_id: soignant.id,
    });
    if (numErr || !invoiceNumber) return json(req, { error: 'Erreur génération numéro de facture' }, 500);

    // 6. Calculer les montants
    //    - Mode finale unique : amountHt = mission.net_a_payer (comme avant)
    //    - Mode hebdo / finale partielle : appel fn_calculer_montant_periode
    let amountHt: number;
    let cumulHt = 0;
    let cumulNbFactures = 0;
    let quantiteHeures: number | null = null;
    let tauxHoraireSnapshot: number | null = Number(mission.taux_horaire_base) || null;
    if (isHebdoMode) {
      const { data: calc, error: calcErr } = await supabaseAdmin
        .rpc('fn_calculer_montant_periode', {
          p_mission_id: mission_id, p_periode_debut: periode_debut, p_periode_fin: periode_fin,
        });
      if (calcErr) return json(req, { error: `Erreur calcul montant période : ${calcErr.message}` }, 500);
      amountHt = Number((calc as any)?.montant_ht_periode) || 0;
      quantiteHeures = Number((calc as any)?.duree_periode_heures) || null;
      tauxHoraireSnapshot = Number((calc as any)?.taux_horaire_base_fige)
        || tauxHoraireSnapshot;
      const { data: cumul } = await supabaseAdmin
        .rpc('fn_cumul_factures_mission', { p_mission_id: mission_id, p_jusqu_au: periode_debut });
      cumulHt = Number((cumul as any)?.cumul_ht) || 0;
      cumulNbFactures = Number((cumul as any)?.nb_factures) || 0;
    } else {
      amountHt = Number(mission.net_a_payer) || Number(mission.total_brut) || 0;
      quantiteHeures = Number(mission.duree_heures)
        || (tauxHoraireSnapshot && tauxHoraireSnapshot > 0
          ? Math.round((amountHt / tauxHoraireSnapshot) * 100) / 100
          : null);
    }
    const issueDate = new Date().toISOString().split('T')[0];
    const vat = traitementTva(
      soignant.statut_tva_honoraires as StatutTvaHonoraires,
      mission.nature_tva_prestation as NatureTvaPrestation,
      issueDate,
    );
    const vatExempt = vat.vatExempt;
    const vatRate = vat.vatRate;
    const amountTva = vatExempt ? 0 : Math.round(amountHt * vatRate) / 100;
    const amountTtc = amountHt + amountTva;

    // Échéance configurable (Config système) : privé 30 j / public 50 j (Code commande publique L.2192-10).
    const cleDelai = etab.est_secteur_public ? 'delai_paiement_public_j' : 'delai_paiement_prive_j';
    const defautDelai = etab.est_secteur_public ? 50 : 30;
    const { data: delaiParam } = await supabaseAdmin.rpc('fn_param_num', { p_cle: cleDelai, p_defaut: defautDelai });
    const delaiJours = Number(delaiParam) || defautDelai;
    const dueDate = new Date(Date.now() + delaiJours * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

    // 7. Check factor
    const factorData: any = null;
    let subrogationMention: string | null = null;
    // Factor assignment is done post-creation; here we just check if pre-assigned

    // 8. Get Chorus config if public sector
    let serviceCodeChorus: string | null = null;
    if (etab.est_secteur_public && etab.chorus_pro_actif) {
      const { data: chorusConfig } = await supabaseAdmin
        .from('chorus_pro_config')
        .select('code_service')
        .eq('etablissement_id', etab.id)
        .eq('actif', true)
        .maybeSingle();
      serviceCodeChorus = chorusConfig?.code_service || null;
    }

    // 9. Generate XML CII
    const sellerAddress = [soignant.adresse_rue, soignant.adresse_code_postal, soignant.adresse_ville].filter(Boolean).join(', ');
    const buyerAddress = [etab.adresse_rue, etab.adresse_code_postal, etab.adresse_ville].filter(Boolean).join(', ');
    // Description avec mention hebdo + cumul si applicable
    let description: string;
    if (isHebdoMode && est_facture_finale_mission !== true) {
      const cumulMention = cumulNbFactures > 0
        ? ` — Cumul mission depuis début : ${cumulHt.toFixed(2)} EUR HT (${cumulNbFactures} facture(s) precedente(s))`
        : '';
      description = `Facture hebdomadaire S${numero_semaine_iso}/${annee_iso} — ${mission.intitule || 'Mission'} — Periode du ${periode_debut} au ${periode_fin}${cumulMention}`;
    } else if (isFinaleFromHebdo) {
      const cumulMention = cumulNbFactures > 0
        ? ` — Cumul deja facture : ${cumulHt.toFixed(2)} EUR HT (${cumulNbFactures} facture(s) hebdo)`
        : '';
      description = `Facture finale — ${mission.intitule || 'Mission'} — Periode du ${periode_debut} au ${periode_fin}${cumulMention}`;
    } else {
      description = `Honoraires — ${mission.intitule || 'Mission'} (${mission.service || ''}) du ${mission.debut_le || ''} au ${mission.fin_le || ''} — ${mission.duree_heures || 0}h`;
    }
    if (quantiteHeures && tauxHoraireSnapshot) {
      description += ` — ${quantiteHeures.toFixed(2)} h x ${tauxHoraireSnapshot.toFixed(2)} EUR/h`;
    }

    subrogationMention = buildSubrogationMention(soignant, issueDate);

    const xmlCii = generateCiiXml({
      invoiceNumber: invoiceNumber as string,
      issueDate,
      dueDate,
      sellerName: `${soignant.prenom} ${soignant.nom}`,
      sellerSiret: soignant.siret_liberal || '',
      sellerVatId: soignant.numero_tva || '',
      sellerRpps: soignant.numero_rpps || '',
      sellerAdeli: soignant.numero_adeli || '',
      sellerAddress: soignant.adresse_rue || '',
      sellerCity: soignant.adresse_ville || '',
      sellerPostalCode: soignant.adresse_code_postal || '',
      sellerEmail: soignant.email || '',
      buyerName: etab.nom,
      buyerSiret: etab.siret || '',
      buyerAddress: etab.adresse_rue || '',
      buyerCity: etab.adresse_ville || '',
      buyerPostalCode: etab.adresse_code_postal || '',
      serviceDate: isHebdoMode
        ? periode_fin
        : (mission.fin_le ? String(mission.fin_le).slice(0, 10) : issueDate),
      serviceCode: serviceCodeChorus || '',
      description,
      quantity: quantiteHeures,
      unitPriceHt: tauxHoraireSnapshot,
      amountHt,
      amountTva,
      amountTtc,
      vatRate,
      vatExempt,
      vatExemptionReason: vatExempt ? vat.exemptionReason : '',
      currencyCode: 'EUR',
      subrogationMention,
    });

    // 10. Generate real PDF binary via pdf-lib
    const pdfBytes = await generateInvoicePdf({
      invoiceNumber: invoiceNumber as string,
      issueDate,
      dueDate,
      sellerName: `${soignant.prenom} ${soignant.nom}`,
      sellerProfession: soignant.profession || '',
      sellerSiret: soignant.siret_liberal || '',
      sellerRpps: soignant.numero_rpps || '',
      sellerAdeli: soignant.numero_adeli || '',
      sellerAddress,
      buyerName: etab.nom,
      buyerSiret: etab.siret || '',
      buyerAddress,
      description,
      quantity: quantiteHeures,
      unitPriceHt: tauxHoraireSnapshot,
      amountHt,
      amountTva,
      amountTtc,
      vatExempt,
      vatExemptionReason: vatExempt ? vat.exemptionReason : '',
      mandatVersion: soignant.mandat_facturation_version || '1.1',
      subrogationMention,
    });

    // 11. Upload to Supabase Storage
    const storagePath = cheminDocumentVersionne('invoices', soignant.id, invoiceNumber as string, 'pdf');
    const xmlPath = cheminDocumentVersionne('invoices', soignant.id, invoiceNumber as string, 'xml');

    // 11b. Lookup facture précédente pour chaînage hebdo (Partie 2)
    let facturePrecedenteId: string | null = null;
    if (isHebdoMode) {
      const { data: prev } = await supabaseAdmin
        .from('factures_honoraires')
        .select('id')
        .eq('mission_id', mission_id)
        .not('statut', 'in', '("ANNULEE","REMPLACEE","ERREUR_GENERATION","EN_GENERATION")')
        .lt('periode_fin', periode_debut)
        .order('periode_fin', { ascending: false })
        .limit(1)
        .maybeSingle();
      facturePrecedenteId = prev?.id ?? null;
    }

    // 12. Insert facture en statut EN_GENERATION (D11) — réserve le slot
    //     et empêche tout doublon hebdo concurrent. Sera passée à EMISE
    //     après succès upload PDF/XML, ou ERREUR_GENERATION sinon.
    const finalFlag = isHebdoMode ? (est_facture_finale_mission === true) : true;
    const { data: facture, error: insertErr } = await supabaseAdmin
      .from('factures_honoraires')
      .insert({
        numero_facture: invoiceNumber as string,
        soignant_id: soignant.id,
        etablissement_id: etab.id,
        mission_id: mission.id,
        montant_ht: amountHt,
        montant_tva: amountTva,
        montant_ttc: amountTtc,
        taux_tva: vatRate,
        exoneration_tva: vatExempt,
        date_emission: issueDate,
        date_echeance: dueDate,
        statut: 'EN_GENERATION',
        mandat_version: soignant.mandat_facturation_version || '1.1',
        template_version: 'v2_facturx',
        is_public_sector: etab.est_secteur_public || false,
        siret_client: etab.siret || null,
        service_code_chorus: serviceCodeChorus,
        periode_debut: isHebdoMode ? periode_debut : (mission.debut_le ? String(mission.debut_le).slice(0,10) : issueDate),
        periode_fin: isHebdoMode ? periode_fin : (mission.fin_le ? String(mission.fin_le).slice(0,10) : issueDate),
        numero_semaine_iso: (isHebdoMode && !finalFlag) ? numero_semaine_iso : null,
        annee_iso: (isHebdoMode && !finalFlag) ? annee_iso : null,
        est_facture_finale_mission: finalFlag,
        facture_precedente_id: facturePrecedenteId,
        nature_correction: 'ORIGINALE',
        regime_tva_snapshot: vat.regime,
        base_legale_tva_snapshot: vat.legalBasis,
        nature_prestation_snapshot: vat.serviceNature,
        description_prestation_snapshot: description,
        quantite_heures_snapshot: quantiteHeures,
        taux_horaire_snapshot: tauxHoraireSnapshot,
        emetteur_identite_snapshot: `${soignant.prenom} ${soignant.nom}`.trim(),
        emetteur_profession_snapshot: soignant.profession,
        emetteur_siret_snapshot: soignant.siret_liberal,
        emetteur_numero_professionnel_snapshot: soignant.numero_rpps || soignant.numero_adeli,
        emetteur_adresse_snapshot: sellerAddress,
        emetteur_adresse_rue_snapshot: soignant.adresse_rue,
        emetteur_adresse_code_postal_snapshot: soignant.adresse_code_postal,
        emetteur_adresse_ville_snapshot: soignant.adresse_ville,
        emetteur_email_snapshot: soignant.email,
        emetteur_numero_tva_snapshot: soignant.numero_tva,
        destinataire_nom_snapshot: etab.nom,
        destinataire_siret_snapshot: etab.siret,
        destinataire_adresse_rue_snapshot: etab.adresse_rue,
        destinataire_adresse_code_postal_snapshot: etab.adresse_code_postal,
        destinataire_adresse_ville_snapshot: etab.adresse_ville,
      })
      .select('id, numero_facture')
      .single();

    if (insertErr) {
      console.error('Insert facture error:', insertErr);
      return json(req, { error: `Erreur insertion facture : ${insertErr.message}` }, 500);
    }

    // Upload PDF + XML, puis UPDATE → EMISE. En cas d'échec, ERREUR_GENERATION.
    const { error: uploadErr } = await supabaseAdmin.storage
      .from('jolene-documents')
      .upload(storagePath, creerBlobPdf(pdfBytes), { upsert: false });

    const { error: xmlUploadErr } = await supabaseAdmin.storage
      .from('jolene-documents')
      .upload(xmlPath, new Blob([xmlCii], { type: 'application/xml' }), { upsert: false });

    if (uploadErr || xmlUploadErr) {
      console.error('Upload error:', uploadErr || xmlUploadErr);
      await supabaseAdmin.from('factures_honoraires').update({
        statut: 'ERREUR_GENERATION',
      }).eq('id', facture!.id);
      // Audit alerte admin
      await supabaseAdmin.from('journaux_audit').insert({
        acteur_id: null, type_acteur: 'SYSTEME',
        action: 'ADMIN_ACTION', type_ressource: 'facture_honoraire',
        id_ressource: facture!.id,
        details: { event: 'GENERATION_INVOICE_FAIL', error: String(uploadErr || xmlUploadErr), mission_id, periode_debut, periode_fin },
      });
      return json(req, { error: 'Echec upload PDF/XML — facture en ERREUR_GENERATION', facture_id: facture!.id }, 500);
    }

    const [pdfSha256, xmlSha256] = await Promise.all([
      sha256Hex(pdfBytes),
      sha256Hex(xmlCii),
    ]);
    const { error: documentLedgerError } = await supabaseAdmin
      .from('factures_honoraires_documents')
      .insert({
        facture_honoraire_id: facture!.id,
        pdf_s3_key: storagePath,
        facturx_xml_url: xmlPath,
        pdf_sha256: pdfSha256,
        xml_sha256: xmlSha256,
        motif_generation: 'EMISSION_INITIALE',
      });
    if (documentLedgerError) {
      console.error('Document ledger error:', documentLedgerError.message);
      await supabaseAdmin.from('factures_honoraires')
        .update({ statut: 'ERREUR_GENERATION' })
        .eq('id', facture!.id)
        .eq('statut', 'EN_GENERATION');
      return json(req, {
        error: 'Version documentaire non enregistrée — facture non émise',
        facture_id: facture!.id,
      }, 500);
    }

    // Tout est ok → émission + remise de copie in-app dans une seule
    // transaction SQL. Le délai de vérification part de cet instant exact.
    const { data: emission, error: updErr } = await supabaseAdmin.rpc(
      'fn_emettre_document_facturation_honoraires',
      {
        p_facture_id: facture!.id,
        p_pdf_s3_key: storagePath,
        p_facturx_xml_url: xmlPath,
      },
    );
    if (updErr || !(emission as any)?.success) {
      console.error('Emission atomique error:', updErr);
      // Ne jamais laisser un slot EN_GENERATION bloquer toutes les reprises du
      // cron. Le retry suivant pourra régénérer une facture proprement.
      await supabaseAdmin
        .from('factures_honoraires')
        .update({ statut: 'ERREUR_GENERATION' })
        .eq('id', facture!.id)
        .eq('statut', 'EN_GENERATION');
      return json(req, {
        error: `Erreur passage EMISE : ${updErr?.message || 'réponse invalide'}`,
        facture_id: facture!.id,
      }, 500);
    }

    // D6 — la commission Jolene suit exactement la même période que la note
    // d'honoraires. Cette facture est celle qui sera payée par Stripe (privé)
    // ou déposée sur Chorus Pro (public).
    const { data: commissionPrepared, error: commissionPrepareError } = await supabaseAdmin
      .rpc('fn_preparer_facture_commission_periode', {
        p_facture_honoraire_id: facture!.id,
      });
    if (commissionPrepareError || !(commissionPrepared as any)?.facture_id) {
      console.error('Commission invoice preparation error:', commissionPrepareError);
      return json(req, {
        error: `Erreur génération facture commission : ${commissionPrepareError?.message || 'réponse invalide'}`,
        facture_id: facture!.id,
      }, 500);
    }

    // 13. Secteur public : la note d'honoraires et la facture de commission
    // sont deux documents distincts. La seconde est bien la facture Jolene
    // déposée via chorus-pro-deposit.
    if (etab.est_secteur_public) {
      try {
        await supabaseAdmin.functions.invoke('submit-to-chorus', {
          body: { facture_honoraire_id: facture!.id },
        });
        await supabaseAdmin.functions.invoke('chorus-pro-deposit', {
          body: { facture_id: (commissionPrepared as any).facture_id, action: 'deposer' },
        });
      } catch (e) {
        console.warn('Chorus submission deferred:', e);
      }
    }

    await notifierEmissionDocument(
      supabaseAdmin,
      {
        id: facture!.id,
        numero_facture: facture!.numero_facture,
        soignant_id: soignant.id,
        etablissement_id: etab.id,
        montant_ht: amountHt,
        montant_tva: amountTva,
        montant_ttc: amountTtc,
        periode_debut: isHebdoMode ? periode_debut : (mission.debut_le ? String(mission.debut_le).slice(0, 10) : issueDate),
        periode_fin: isHebdoMode ? periode_fin : (mission.fin_le ? String(mission.fin_le).slice(0, 10) : issueDate),
        type_document: 'FACTURE',
      },
      soignant,
      Number((emission as any).delai_verification_heures) || 48,
    );

    // 14. If service_role, insert explicit audit entry
    if (isServiceRole) {
      await supabaseAdmin.from('invoice_audit_log').insert({
        invoice_id: facture!.id,
        action: 'GENERATED_VIA_SERVICE_ROLE',
        actor_id: null,
        payload_before: { caller_context: 'service_role', mission_id, reason: service_role_reason },
        payload_after: { numero_facture: facture!.numero_facture, template_version: 'v2_facturx' },
      });
    }

    console.log(`[generate-invoice] Facture ${invoiceNumber} générée pour mission ${mission_id}${isServiceRole ? ` (service_role: ${service_role_reason})` : ''}`);

    return json(req, {
      success: true,
      facture_id: facture!.id,
      facture_commission_id: (commissionPrepared as any).facture_id,
      numero_facture: facture!.numero_facture,
      is_public_sector: etab.est_secteur_public || false,
      pdf_path: storagePath,
      xml_path: xmlPath,
    });

  } catch (err) {
    console.error('generate-invoice error:', err);
    return json(req, { error: err instanceof Error ? err.message : 'Erreur interne' }, 500);
  }
});

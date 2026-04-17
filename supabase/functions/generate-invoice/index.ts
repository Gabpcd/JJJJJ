/**
 * generate-invoice — Génération de facture honoraire Factur-X
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

import { createClient } from 'npm:@supabase/supabase-js@2';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

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

/* ── CORS ── */
function getCorsOrigin(req: Request): string {
  const origin = req.headers.get('origin') || '';
  if (['https://jolene.app', 'https://www.jolene.app', 'http://localhost:5173', 'http://localhost:8080'].includes(origin)) return origin;
  return 'https://jolene.app';
}
function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}
function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } });
}

/* ── XML CII Generator (EN16931 BASIC WL) ── */
function generateCiiXml(inv: {
  invoiceNumber: string;
  issueDate: string;
  dueDate: string;
  sellerName: string;
  sellerSiret: string;
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
  serviceCode: string;
  description: string;
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
  // CP-LITIGES-6 : AVOIR → TypeCode 381 + montants négatifs + référence facture origine
  const typeCode = inv.isAvoir ? '381' : '380';
  const sign = inv.isAvoir ? -1 : 1;
  const signed = (n: number) => fmtAmt(n * sign);
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
       <ram:ExemptionReason>${escapeXml(inv.vatExemptionReason)}</ram:ExemptionReason>
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
        <ram:URIUniversalCommunication><ram:URIID schemeID="EM">${escapeXml(inv.sellerEmail)}</ram:URIID></ram:URIUniversalCommunication>
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
      <ram:InvoiceCurrencyCode>${inv.currencyCode}</ram:InvoiceCurrencyCode>
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
        <ram:TaxTotalAmount currencyID="${inv.currencyCode}">${signed(inv.amountTva)}</ram:TaxTotalAmount>
        <ram:GrandTotalAmount>${signed(inv.amountTtc)}</ram:GrandTotalAmount>
        <ram:DuePayableAmount>${signed(inv.amountTtc)}</ram:DuePayableAmount>
      </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
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
  drawText(`de facturation (art. 289 I-2 CGI), mandat v${inv.mandatVersion}.`, margin, y, { color: grey, size: 8 });
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

  // Footer
  drawLine(y); y -= 15;
  drawText('Jolene SASU - Mandataire de facturation', margin, y, { size: 7, color: grey });
  y -= 10;
  drawText('art. 289 I-2 du Code General des Impots', margin, y, { size: 7, color: grey });

  return await pdfDoc.save();
}

/* ── Main Handler ── */

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders(req) });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json(req, { error: 'Non autorisé' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const token = authHeader.replace('Bearer ', '');
    const isServiceRole = token === serviceRoleKey;

    const body = await req.json();
    const { mission_id, facture_id, service_role_reason } = body;
    if (!mission_id && !facture_id) {
      return json(req, { error: 'mission_id ou facture_id requis' }, 400);
    }

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
    }

    // ═══════════════════════════════════════════════════════════
    // MODE REGEN (CP-LITIGES-6) — facture_id fourni
    // Regénère PDF + Factur-X XML + upload S3 + Chorus resubmission
    // pour une facture existante (cas AVOIR ou ANNULER_REEMETTRE).
    // ═══════════════════════════════════════════════════════════
    if (facture_id && !mission_id) {
      const { data: facture, error: fErr } = await supabaseAdmin
        .from('factures_honoraires')
        .select('id, numero_facture, soignant_id, etablissement_id, mission_id, montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva, date_emission, date_echeance, statut, mandat_version, type_document, facture_precedente_id, litige_id, is_public_sector, service_code_chorus')
        .eq('id', facture_id)
        .single();
      if (fErr || !facture) return json(req, { error: 'Facture introuvable' }, 404);

      // Charger soignant + etab + mission (lookup pour description)
      const [{ data: sg }, { data: et }, { data: ms }] = await Promise.all([
        supabaseAdmin.from('soignants').select('id, prenom, nom, profession, numero_rpps, numero_adeli, siret_liberal, email, adresse_rue, adresse_ville, adresse_code_postal, assujetti_tva, numero_tva').eq('id', facture.soignant_id).single(),
        supabaseAdmin.from('etablissements').select('id, nom, siret, adresse_rue, adresse_ville, adresse_code_postal, est_secteur_public, chorus_pro_actif').eq('id', facture.etablissement_id).single(),
        supabaseAdmin.from('missions').select('id, intitule, service, debut_le, fin_le, duree_heures').eq('id', facture.mission_id).maybeSingle(),
      ]);
      if (!sg || !et) return json(req, { error: 'Soignant/établissement introuvable' }, 404);

      const isAvoir = facture.type_document === 'AVOIR';
      let precedingNumero: string | null = null;
      let precedingDate: string | null = null;
      let motifAvoir: string | null = null;

      if (isAvoir) {
        if (!facture.facture_precedente_id) {
          return json(req, { error: 'AVOIR sans facture_precedente_id — incohérence critique' }, 400);
        }
        const { data: prec } = await supabaseAdmin
          .from('factures_honoraires')
          .select('numero_facture, date_emission')
          .eq('id', facture.facture_precedente_id)
          .single();
        precedingNumero = prec?.numero_facture ?? null;
        precedingDate = prec?.date_emission ?? null;

        if (facture.litige_id) {
          const { data: lit } = await supabaseAdmin
            .from('litiges')
            .select('resolution')
            .eq('id', facture.litige_id)
            .single();
          motifAvoir = lit?.resolution ?? null;
        }
      }

      const sellerAddress = [sg.adresse_rue, sg.adresse_code_postal, sg.adresse_ville].filter(Boolean).join(', ');
      const buyerAddress = [et.adresse_rue, et.adresse_code_postal, et.adresse_ville].filter(Boolean).join(', ');
      const description = isAvoir
        ? `Avoir sur facture ${precedingNumero ?? ''}${motifAvoir ? ' — ' + motifAvoir.substring(0, 100) : ''}`
        : `Honoraires — ${ms?.intitule || 'Mission'} (${ms?.service || ''}) du ${ms?.debut_le || ''} au ${ms?.fin_le || ''} — ${ms?.duree_heures || 0}h`;

      const xmlCii = generateCiiXml({
        invoiceNumber: facture.numero_facture,
        issueDate: facture.date_emission,
        dueDate: facture.date_echeance,
        sellerName: `${sg.prenom} ${sg.nom}`,
        sellerSiret: sg.siret_liberal || '',
        sellerRpps: sg.numero_rpps || '',
        sellerAdeli: sg.numero_adeli || '',
        sellerAddress: sg.adresse_rue || '',
        sellerCity: sg.adresse_ville || '',
        sellerPostalCode: sg.adresse_code_postal || '',
        sellerEmail: sg.email || '',
        buyerName: et.nom,
        buyerSiret: et.siret || '',
        buyerAddress: et.adresse_rue || '',
        buyerCity: et.adresse_ville || '',
        buyerPostalCode: et.adresse_code_postal || '',
        serviceCode: facture.service_code_chorus || '',
        description,
        amountHt: Number(facture.montant_ht) || 0,
        amountTva: Number(facture.montant_tva) || 0,
        amountTtc: Number(facture.montant_ttc) || 0,
        vatRate: Number(facture.taux_tva) || 0,
        vatExempt: !!facture.exoneration_tva,
        vatExemptionReason: facture.exoneration_tva ? 'TVA non applicable — art. 261, 4-1° du CGI (actes médicaux et paramédicaux)' : '',
        currencyCode: 'EUR',
        isAvoir,
        precedingInvoiceNumber: precedingNumero ?? undefined,
        precedingInvoiceIssueDate: precedingDate ?? undefined,
      });

      const pdfBytes = await generateInvoicePdf({
        invoiceNumber: facture.numero_facture,
        issueDate: facture.date_emission,
        dueDate: facture.date_echeance,
        sellerName: `${sg.prenom} ${sg.nom}`,
        sellerProfession: sg.profession || '',
        sellerSiret: sg.siret_liberal || '',
        sellerRpps: sg.numero_rpps || '',
        sellerAdeli: sg.numero_adeli || '',
        sellerAddress,
        buyerName: et.nom,
        buyerSiret: et.siret || '',
        buyerAddress,
        description,
        amountHt: Number(facture.montant_ht) || 0,
        amountTva: Number(facture.montant_tva) || 0,
        amountTtc: Number(facture.montant_ttc) || 0,
        vatExempt: !!facture.exoneration_tva,
        vatExemptionReason: facture.exoneration_tva ? 'TVA non applicable - art. 261, 4-1 du CGI (actes medicaux et paramedicaux)' : '',
        mandatVersion: facture.mandat_version || '1.1',
        isAvoir,
        precedingInvoiceNumber: precedingNumero ?? undefined,
        precedingInvoiceIssueDate: precedingDate ?? undefined,
        motifAvoir: motifAvoir ?? undefined,
      });

      const subDir = isAvoir ? 'avoirs' : 'invoices';
      const storagePath = `${subDir}/${sg.id}/${facture.numero_facture}.pdf`;
      const xmlPath = `${subDir}/${sg.id}/${facture.numero_facture}.xml`;

      await supabaseAdmin.storage.from('jolene-documents')
        .upload(storagePath, new Blob([pdfBytes], { type: 'application/pdf' }), { upsert: true });
      await supabaseAdmin.storage.from('jolene-documents')
        .upload(xmlPath, new Blob([xmlCii], { type: 'application/xml' }), { upsert: true });

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

      if (facture.is_public_sector) {
        try {
          await supabaseAdmin.functions.invoke('submit-to-chorus', {
            body: { facture_honoraire_id: facture_id, type_document: facture.type_document },
          });
        } catch (e) { console.warn('Chorus regen deferred:', e); }
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
      });
    }

    if (!mission_id) return json(req, { error: 'mission_id requis' }, 400);

    // 1. Vérifier mission TERMINEE
    const { data: mission, error: mErr } = await supabaseAdmin
      .from('missions')
      .select('id, intitule, service, debut_le, fin_le, duree_heures, taux_horaire_base, total_brut, net_a_payer, montant_commission_ht, soignant_assigne_id, etablissement_id, statut')
      .eq('id', mission_id)
      .single();

    if (mErr || !mission) return json(req, { error: 'Mission introuvable' }, 404);
    if (mission.statut !== 'TERMINEE') return json(req, { error: `Mission en statut ${mission.statut}, doit être TERMINEE` }, 400);

    // 1b. Garde-fou pré-facturation CP5b (créneaux ouverts + écart > 10%)
    const { data: preCheck, error: preCheckErr } = await supabaseAdmin
      .rpc('fn_verifier_pre_facturation', { p_mission_id: mission_id });

    if (preCheckErr) {
      console.warn(`[generate-invoice] pré-facturation bloquée: ${preCheckErr.message}`);
      return json(req, { error: preCheckErr.message }, 400);
    }

    // 2. Vérifier mandat actif
    const { data: soignant } = await supabaseAdmin
      .from('soignants')
      .select('id, prenom, nom, profession, numero_rpps, numero_adeli, siret_liberal, email, adresse_rue, adresse_ville, adresse_code_postal, assujetti_tva, numero_tva, mandat_facturation_signe, mandat_facturation_version')
      .eq('id', mission.soignant_assigne_id)
      .single();

    if (!soignant) return json(req, { error: 'Soignant introuvable' }, 404);
    if (!soignant.mandat_facturation_signe) {
      return json(req, { error: 'Mandat de facturation non signé. Le soignant doit signer le mandat avant de pouvoir générer une facture.' }, 400);
    }

    // 3. Vérifier établissement
    const { data: etab } = await supabaseAdmin
      .from('etablissements')
      .select('id, nom, siret, adresse_rue, adresse_ville, adresse_code_postal, est_secteur_public, chorus_pro_actif')
      .eq('id', mission.etablissement_id)
      .single();

    if (!etab) return json(req, { error: 'Établissement introuvable' }, 404);

    // 4. Vérifier pas de doublon
    const { data: existing } = await supabaseAdmin
      .from('factures_honoraires')
      .select('id, numero_facture')
      .eq('mission_id', mission_id)
      .not('statut', 'eq', 'ANNULEE')
      .maybeSingle();

    if (existing) {
      return json(req, { error: `Une facture existe déjà pour cette mission : ${existing.numero_facture}`, facture_id: existing.id }, 409);
    }

    // 5. Générer le numéro de facture
    const { data: invoiceNumber, error: numErr } = await supabaseAdmin.rpc('next_invoice_number', {
      p_soignant_id: soignant.id,
    });
    if (numErr || !invoiceNumber) return json(req, { error: 'Erreur génération numéro de facture' }, 500);

    // 6. Calculer les montants
    const amountHt = Number(mission.net_a_payer) || Number(mission.total_brut) || 0;
    const vatExempt = !soignant.assujetti_tva;
    const vatRate = vatExempt ? 0 : 20;
    const amountTva = vatExempt ? 0 : Math.round(amountHt * vatRate) / 100;
    const amountTtc = amountHt + amountTva;

    const issueDate = new Date().toISOString().split('T')[0];
    const dueDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

    // 7. Check factor
    let factorData: any = null;
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
    const description = `Honoraires — ${mission.intitule || 'Mission'} (${mission.service || ''}) du ${mission.debut_le || ''} au ${mission.fin_le || ''} — ${mission.duree_heures || 0}h`;

    const xmlCii = generateCiiXml({
      invoiceNumber: invoiceNumber as string,
      issueDate,
      dueDate,
      sellerName: `${soignant.prenom} ${soignant.nom}`,
      sellerSiret: soignant.siret_liberal || '',
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
      serviceCode: serviceCodeChorus || '',
      description,
      amountHt,
      amountTva,
      amountTtc,
      vatRate,
      vatExempt,
      vatExemptionReason: vatExempt ? 'TVA non applicable — art. 261, 4-1° du CGI (actes médicaux et paramédicaux)' : '',
      currencyCode: 'EUR',
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
      amountHt,
      amountTva,
      amountTtc,
      vatExempt,
      vatExemptionReason: vatExempt ? 'TVA non applicable - art. 261, 4-1 du CGI (actes medicaux et paramedicaux)' : '',
      mandatVersion: soignant.mandat_facturation_version || '1.1',
    });

    // 11. Upload to Supabase Storage
    const storagePath = `invoices/${soignant.id}/${invoiceNumber}.pdf`;
    const xmlPath = `invoices/${soignant.id}/${invoiceNumber}.xml`;

    const { error: uploadErr } = await supabaseAdmin.storage
      .from('jolene-documents')
      .upload(storagePath, new Blob([pdfBytes], { type: 'application/pdf' }), { upsert: true });

    const { error: xmlUploadErr } = await supabaseAdmin.storage
      .from('jolene-documents')
      .upload(xmlPath, new Blob([xmlCii], { type: 'application/xml' }), { upsert: true });

    if (uploadErr) console.error('PDF upload error:', uploadErr);
    if (xmlUploadErr) console.error('XML upload error:', xmlUploadErr);

    // 12. Insert facture honoraire
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
        statut: 'EMISE',
        mandat_version: soignant.mandat_facturation_version || '1.1',
        template_version: 'v2_facturx',
        pdf_s3_key: storagePath,
        facturx_xml_url: xmlPath,
        is_public_sector: etab.est_secteur_public || false,
        siret_client: etab.siret || null,
        service_code_chorus: serviceCodeChorus,
      })
      .select('id, numero_facture')
      .single();

    if (insertErr) {
      console.error('Insert facture error:', insertErr);
      return json(req, { error: `Erreur insertion facture : ${insertErr.message}` }, 500);
    }

    // 13. If public sector, trigger Chorus submission (stub)
    if (etab.est_secteur_public) {
      try {
        await supabaseAdmin.functions.invoke('submit-to-chorus', {
          body: { facture_honoraire_id: facture!.id },
        });
      } catch (e) {
        console.warn('Chorus submission deferred:', e);
      }
    }

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

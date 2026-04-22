/**
 * Design system PDF Jolene — helpers partagés pour tous les documents
 * (factures honoraires, factures commission, avoirs, attestations).
 *
 * Palette dérivée de src/index.css / tailwind.config.ts :
 *   primary        = HSL(330, 85%, 60%)  ≈ rose magenta principal
 *   primary-dark   = HSL(330, 85%, 52%)  ≈ rose profond
 *   rose           = HSL(340, 82%, 55%)
 *   rose-light     = HSL(340, 70%, 95%)
 *   teal           = HSL(174, 72%, 48%)
 *   success        = HSL(152, 70%, 48%)
 *   warning        = HSL(38, 95%, 55%)
 *   destructive    = HSL(0, 84%, 62%)
 *
 * Encodage : jsPDF (Helvetica) ne gère pas Unicode arbitraire. Les flèches
 * `→`, emojis, etc. sont remplacés par leurs équivalents ASCII via
 * `sanitizeForPdf()` avant insertion.
 */

import type jsPDF from 'jspdf';

export const JOLENE_COLORS = {
  primary: [232, 58, 140] as [number, number, number],
  primaryDark: [211, 41, 127] as [number, number, number],
  rose: [229, 53, 142] as [number, number, number],
  roseLight: [251, 229, 238] as [number, number, number],
  teal: [35, 183, 164] as [number, number, number],
  success: [39, 181, 113] as [number, number, number],
  warning: [251, 159, 19] as [number, number, number],
  destructive: [240, 68, 68] as [number, number, number],
  text: [30, 30, 40] as [number, number, number],
  textMuted: [120, 120, 130] as [number, number, number],
  border: [225, 225, 230] as [number, number, number],
  background: [250, 250, 252] as [number, number, number],
} as const;

export const PAGE = {
  width: 210,
  height: 297,
  margin: 14,
  contentWidth: 210 - 14 * 2,
} as const;

/**
 * Remplace les caractères Unicode non supportés par Helvetica jsPDF.
 * Bug connu : `→` (U+2192) s'affiche comme "!'" sans cette sanitation.
 */
export function sanitizeForPdf(s: string | null | undefined): string {
  if (s == null) return '';
  return String(s)
    .replace(/→/g, '->')
    .replace(/←/g, '<-')
    .replace(/↔/g, '<->')
    .replace(/⇒/g, '=>')
    .replace(/•/g, '-')
    .replace(/·/g, '-')
    .replace(/…/g, '...')
    .replace(/–/g, '-')
    .replace(/—/g, '-')
    .replace(/✓/g, '[OK]')
    .replace(/✅/g, '[OK]')
    .replace(/❌/g, '[X]')
    .replace(/⚠️?/g, '[!]')
    .replace(/ℹ️?/g, '[i]')
    .replace(/💳/g, '[Stripe]')
    .replace(/🏦/g, '[Virement]')
    .replace(/🏛️?/g, '[Chorus Pro]')
    .replace(/📄/g, '')
    .replace(/📋/g, '')
    .replace(/💶/g, '')
    .replace(/🏷️?/g, '')
    .replace(/⏱️?/g, '')
    // Retire tout emoji (plages Unicode > BMP + emojis BMP communs)
    .replace(/[\u{1F300}-\u{1FAFF}]/gu, '')
    .replace(/[\u{2600}-\u{27BF}]/gu, '')
    .replace(/[\u{1F000}-\u{1F9FF}]/gu, '');
}

export const fmtEur = (v: number | null | undefined) => {
  if (v == null) return '-';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(v) || 0);
};

/**
 * Bandeau en-tête Jolene — dégradé rose simulé avec empilement de 3 rectangles
 * (primary-dark bas → primary milieu → rose haut).
 */
export function createHeader(doc: jsPDF, opts: {
  title: string;
  subtitle?: string;
  statusLabel?: string;
  statusColor?: 'success' | 'warning' | 'destructive' | 'muted';
}) {
  const [r1, g1, b1] = JOLENE_COLORS.primaryDark;
  const [r2, g2, b2] = JOLENE_COLORS.primary;
  const [r3, g3, b3] = JOLENE_COLORS.rose;
  // Dégradé simulé en 3 bandes
  doc.setFillColor(r1, g1, b1);
  doc.rect(0, 0, PAGE.width, 12, 'F');
  doc.setFillColor(r2, g2, b2);
  doc.rect(0, 12, PAGE.width, 10, 'F');
  doc.setFillColor(r3, g3, b3);
  doc.rect(0, 22, PAGE.width, 8, 'F');

  doc.setTextColor(255, 255, 255);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(20);
  doc.text(sanitizeForPdf(opts.title), PAGE.margin, 17);

  if (opts.subtitle) {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.text(sanitizeForPdf(opts.subtitle), PAGE.margin, 25);
  }

  if (opts.statusLabel) {
    const colorMap = {
      success: JOLENE_COLORS.success,
      warning: JOLENE_COLORS.warning,
      destructive: JOLENE_COLORS.destructive,
      muted: JOLENE_COLORS.textMuted,
    };
    const [cr, cg, cb] = colorMap[opts.statusColor || 'muted'];
    const label = sanitizeForPdf(opts.statusLabel);
    const textWidth = doc.getTextWidth(label);
    doc.setFillColor(255, 255, 255);
    doc.roundedRect(PAGE.width - PAGE.margin - textWidth - 8, 8, textWidth + 6, 7, 1.5, 1.5, 'F');
    doc.setTextColor(cr, cg, cb);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(9);
    doc.text(label, PAGE.width - PAGE.margin - textWidth - 5, 13);
  }
}

/**
 * Bloc émetteur/destinataire : titre en minuscule + nom en gras + lignes d'adresse.
 */
export function createInfoBlock(doc: jsPDF, opts: {
  x: number;
  y: number;
  label: string;
  name: string;
  lines?: (string | null | undefined)[];
}): number {
  doc.setTextColor(...JOLENE_COLORS.textMuted);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.text(sanitizeForPdf(opts.label.toUpperCase()), opts.x, opts.y);

  doc.setTextColor(...JOLENE_COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.text(sanitizeForPdf(opts.name), opts.x, opts.y + 5);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  let y = opts.y + 10;
  for (const line of opts.lines || []) {
    if (!line) continue;
    doc.text(sanitizeForPdf(line), opts.x, y);
    y += 4;
  }
  return y;
}

/**
 * Ligne métadonnée (label en gras, valeur à côté).
 */
export function addInfoRow(doc: jsPDF, x: number, y: number, label: string, value: string, labelWidth = 38): void {
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(8);
  doc.setTextColor(...JOLENE_COLORS.text);
  doc.text(sanitizeForPdf(label), x, y);
  doc.setFont('helvetica', 'normal');
  doc.text(sanitizeForPdf(value), x + labelWidth, y);
}

/**
 * Bloc totaux (HT / TVA / TTC) en bas à droite.
 */
export function createTotalsBlock(doc: jsPDF, opts: {
  y: number;
  ht: number;
  tva: number;
  ttc: number;
  tauxTva?: number;
  exonerationTva?: boolean;
}): number {
  const xLabel = PAGE.width - 100;
  const xValue = PAGE.width - PAGE.margin;
  let y = opts.y;

  doc.setDrawColor(...JOLENE_COLORS.border);
  doc.setLineWidth(0.3);
  doc.line(xLabel, y, xValue, y);
  y += 7;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);
  doc.setTextColor(...JOLENE_COLORS.text);
  doc.text('Total HT', xLabel, y);
  doc.text(sanitizeForPdf(fmtEur(opts.ht)), xValue, y, { align: 'right' });
  y += 6;

  if (opts.exonerationTva) {
    doc.setFontSize(7);
    doc.setTextColor(...JOLENE_COLORS.textMuted);
    doc.setFont('helvetica', 'italic');
    doc.text(sanitizeForPdf('TVA non applicable - art. 261-4 CGI'), xLabel, y, { maxWidth: 100 });
    y += 5;
  } else {
    doc.text(`TVA (${opts.tauxTva ?? 20}%)`, xLabel, y);
    doc.text(sanitizeForPdf(fmtEur(opts.tva)), xValue, y, { align: 'right' });
    y += 6;
  }

  doc.setDrawColor(...JOLENE_COLORS.primary);
  doc.setLineWidth(0.5);
  doc.line(xLabel, y - 1, xValue, y - 1);
  y += 3;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(13);
  doc.setTextColor(...JOLENE_COLORS.primary);
  doc.text('TOTAL TTC', xLabel, y + 3);
  doc.text(sanitizeForPdf(fmtEur(opts.ttc)), xValue, y + 3, { align: 'right' });
  return y + 10;
}

/**
 * Pied de page — mentions légales + numéro de page éventuel.
 */
export function createFooter(doc: jsPDF, opts: {
  companyLine: string;
  contactLine?: string;
  extraLine?: string;
}) {
  const y = PAGE.height - 18;
  doc.setDrawColor(...JOLENE_COLORS.border);
  doc.setLineWidth(0.2);
  doc.line(PAGE.margin, y, PAGE.width - PAGE.margin, y);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(7);
  doc.setTextColor(...JOLENE_COLORS.textMuted);
  doc.text(sanitizeForPdf(opts.companyLine), PAGE.width / 2, y + 4, { align: 'center' });
  if (opts.contactLine) {
    doc.text(sanitizeForPdf(opts.contactLine), PAGE.width / 2, y + 8, { align: 'center' });
  }
  if (opts.extraLine) {
    doc.text(sanitizeForPdf(opts.extraLine), PAGE.width / 2, y + 12, { align: 'center' });
  }
}

/**
 * Encart contextuel (ex : "Capturée à la source par Stripe").
 */
export function createHighlightBox(doc: jsPDF, opts: {
  x: number;
  y: number;
  width: number;
  text: string;
  variant?: 'success' | 'info' | 'warning';
}): number {
  const bgMap = {
    success: [235, 250, 240] as [number, number, number],
    info: [240, 245, 255] as [number, number, number],
    warning: [255, 248, 232] as [number, number, number],
  };
  const fgMap = {
    success: JOLENE_COLORS.success,
    info: JOLENE_COLORS.teal,
    warning: JOLENE_COLORS.warning,
  };
  const variant = opts.variant || 'info';
  doc.setFillColor(...bgMap[variant]);
  doc.setDrawColor(...fgMap[variant]);
  doc.setLineWidth(0.3);
  doc.roundedRect(opts.x, opts.y, opts.width, 10, 1.5, 1.5, 'FD');
  doc.setTextColor(...fgMap[variant]);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.text(sanitizeForPdf(opts.text), opts.x + 3, opts.y + 6);
  doc.setTextColor(...JOLENE_COLORS.text);
  return opts.y + 12;
}

/**
 * Titre de section (ex : "MISSIONS FACTURÉES", "DÉTAIL DES PRESTATIONS").
 */
export function createSectionTitle(doc: jsPDF, y: number, title: string): number {
  doc.setTextColor(...JOLENE_COLORS.primary);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text(sanitizeForPdf(title.toUpperCase()), PAGE.margin, y);
  doc.setDrawColor(...JOLENE_COLORS.primary);
  doc.setLineWidth(0.6);
  doc.line(PAGE.margin, y + 1.5, PAGE.margin + 30, y + 1.5);
  doc.setTextColor(...JOLENE_COLORS.text);
  return y + 8;
}

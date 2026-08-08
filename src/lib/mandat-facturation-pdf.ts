import jsPDF from 'jspdf';
import { telechargerOuPartagerPdf } from './telechargement';
import { JOLENE_COLORS, PAGE, sanitizeForPdf, createHeader, createFooter } from './pdf-design-system';
import { buildMandatFacturationTexte, MANDAT_FACTURATION_VERSION, type SoignantMandatInfo } from '@/constantes/mandatFacturation';

export interface MandatPdfMetadata {
  signed_at: string;       // ISO timestamp
  version: string;
  contenu_hash?: string | null;
  ip_address?: string | null;
  user_agent?: string | null;
  contenu_texte?: string | null;
  statut_tva_honoraires?: string | null;
}

/**
 * Génère un PDF du mandat de facturation signé pour archivage par le soignant.
 * Inclut le texte complet du mandat tel qu'accepté + bloc de preuve signature
 * (date, version, IP, user-agent, hash SHA-256 du contenu).
 *
 * Conforme aux articles 1366 et 1367 du Code civil : la valeur probante de
 * la signature électronique repose sur l'identification du signataire et
 * l'intégrité du document — les deux assurées par les métadonnées du bloc
 * signature.
 */
export function genererMandatFacturationPdf(
  soignant: SoignantMandatInfo,
  meta: MandatPdfMetadata,
): jsPDF {
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  const margin = PAGE.margin;
  const contentWidth = PAGE.contentWidth;

  createHeader(doc, {
    title: 'Mandat de facturation',
    subtitle: `Article 289 I-2 du CGI · Version ${meta.version}`,
  });
  // Le header occupe les 30 premiers mm de la page (3 bandes 12+10+8).
  let y = 36;

  // Bloc statut signature
  doc.setFillColor(...JOLENE_COLORS.roseLight);
  doc.setDrawColor(...JOLENE_COLORS.primary);
  doc.setLineWidth(0.5);
  doc.roundedRect(margin, y, contentWidth, 16, 2, 2, 'FD');
  doc.setTextColor(...JOLENE_COLORS.primaryDark);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  const dateSignature = new Date(meta.signed_at).toLocaleString('fr-FR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris',
  });
  doc.text(`Signe le ${sanitizeForPdf(dateSignature)} (heure de Paris)`, margin + 4, y + 6);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(...JOLENE_COLORS.text);
  doc.text(`Signataire : ${sanitizeForPdf([soignant.prenom, soignant.nom].filter(Boolean).join(' ') || '-')}`, margin + 4, y + 11);
  y += 22;

  // Texte du mandat
  // Une preuve doit reproduire le contenu effectivement accepté, même si le
  // profil du soignant change ensuite. Le rebuild n'est qu'un fallback legacy.
  const texteMandat = meta.contenu_texte || buildMandatFacturationTexte(soignant);
  y = renderMarkdown(doc, texteMandat, y, margin, contentWidth);

  // Bloc preuve de signature électronique en bas
  if (y > PAGE.height - 60) { doc.addPage(); y = margin; }
  y += 8;
  doc.setDrawColor(...JOLENE_COLORS.border);
  doc.setLineWidth(0.3);
  doc.line(margin, y, margin + contentWidth, y);
  y += 6;

  doc.setFontSize(11);
  doc.setFont('helvetica', 'bold');
  doc.setTextColor(...JOLENE_COLORS.primaryDark);
  doc.text('Preuve de signature electronique', margin, y);
  y += 6;

  doc.setFontSize(9);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...JOLENE_COLORS.text);

  const blocLines: Array<[string, string]> = [
    ['Version du mandat', meta.version],
    ['Horodatage', dateSignature + ' (heure de Paris)'],
    ['Adresse IP', meta.ip_address || 'non transmise'],
    ['Navigateur', truncate(meta.user_agent || 'non transmis', 80)],
    ['Hash contenu (SHA-256)', meta.contenu_hash || 'non disponible'],
    ['Statut TVA de l\'activité libérale', meta.statut_tva_honoraires || 'non disponible'],
  ];
  for (const [label, value] of blocLines) {
    doc.setFont('helvetica', 'bold');
    doc.text(`${sanitizeForPdf(label)} :`, margin, y);
    doc.setFont('helvetica', 'normal');
    const wrapped = doc.splitTextToSize(sanitizeForPdf(value), contentWidth - 50);
    doc.text(wrapped, margin + 50, y);
    y += Array.isArray(wrapped) ? Math.max(5, wrapped.length * 4) : 5;
  }

  y += 4;
  doc.setFontSize(8);
  doc.setTextColor(...JOLENE_COLORS.textMuted);
  const lignesProbantes = doc.splitTextToSize(
    sanitizeForPdf(
      "Ce document constitue la preuve juridique de l'acceptation du mandat de facturation. " +
      'Sa valeur probante decoule des articles 1366 et 1367 du Code civil : la signature ' +
      "electronique permet d'identifier le signataire et de garantir le lien entre la " +
      'signature et le document, l\'integrite etant attestee par le hash SHA-256 ci-dessus.',
    ),
    contentWidth,
  );
  doc.text(lignesProbantes, margin, y);

  // Footer pour toutes les pages
  const total = doc.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    createFooter(doc, {
      companyLine: `Mandat Jolene - art. 289 I-2 CGI / L. 216-43 CIBS - page ${i}/${total}`,
      contactLine: 'jolene.app | support@jolene.app',
    });
  }

  return doc;
}

export function telechargerMandatFacturationPdf(
  soignant: SoignantMandatInfo,
  meta: MandatPdfMetadata,
) {
  const doc = genererMandatFacturationPdf(soignant, meta);
  const date = new Date(meta.signed_at).toISOString().slice(0, 10);
  const nomFichier = `mandat-facturation-jolene-${date}-v${meta.version}.pdf`;
  void telechargerOuPartagerPdf(doc, nomFichier);
}

// ─────────────────────────────────────────────────────────────────────────
// Markdown → PDF (très simple : titres, paragraphes, listes, gras inline, hr)

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n - 3) + '...' : s;
}

function renderMarkdown(
  doc: jsPDF,
  source: string,
  startY: number,
  margin: number,
  width: number,
): number {
  let y = startY;
  const lineHeight = 5;
  const lines = source.split(/\r?\n/);

  const ensureSpace = (mm: number) => {
    if (y + mm > PAGE.height - 18) {
      doc.addPage();
      y = margin;
    }
  };

  for (const raw of lines) {
    const line = raw.trim();

    if (!line) { y += 3; continue; }

    if (line === '---') {
      ensureSpace(6);
      doc.setDrawColor(...JOLENE_COLORS.border);
      doc.setLineWidth(0.3);
      doc.line(margin, y, margin + width, y);
      y += 4;
      continue;
    }

    // Titre h1
    if (line.startsWith('# ')) {
      ensureSpace(12);
      y += 3;
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(14);
      doc.setTextColor(...JOLENE_COLORS.primaryDark);
      doc.text(sanitizeForPdf(line.slice(2)), margin, y);
      y += 7;
      continue;
    }

    // Titre h2
    if (line.startsWith('## ')) {
      ensureSpace(10);
      y += 2;
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(11);
      doc.setTextColor(...JOLENE_COLORS.primaryDark);
      doc.text(sanitizeForPdf(line.slice(3)), margin, y);
      y += 6;
      continue;
    }

    // Liste numérotée ou tirée
    const liste = /^(\d+\.\s+|-\s+)/.exec(line);
    if (liste) {
      const contenu = line.slice(liste[0].length);
      ensureSpace(6);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(9.5);
      doc.setTextColor(...JOLENE_COLORS.text);
      const puce = liste[0].startsWith('-') ? '-' : liste[0].trim();
      const wrapped = doc.splitTextToSize(sanitizeForPdf(contenu), width - 8);
      doc.text(puce, margin, y);
      const arr = Array.isArray(wrapped) ? wrapped : [wrapped];
      arr.forEach((seg: string, i: number) => {
        doc.text(seg, margin + 6, y + i * lineHeight);
      });
      y += arr.length * lineHeight + 1;
      continue;
    }

    // Paragraphe normal — gestion gras inline **...**
    ensureSpace(6);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9.5);
    doc.setTextColor(...JOLENE_COLORS.text);
    const segments = parseInline(line);
    let cursorX = margin;
    let lineY = y;
    const maxX = margin + width;
    for (const seg of segments) {
      doc.setFont('helvetica', seg.bold ? 'bold' : 'normal');
      const words = seg.text.split(/(\s+)/);
      for (const word of words) {
        if (!word) continue;
        const wWidth = doc.getTextWidth(sanitizeForPdf(word));
        if (cursorX + wWidth > maxX && cursorX > margin) {
          lineY += lineHeight;
          ensureSpace(lineHeight);
          if (lineY + lineHeight > PAGE.height - 18) lineY = y; // post-pageBreak reset
          cursorX = margin;
          if (/^\s+$/.test(word)) continue;
        }
        doc.text(sanitizeForPdf(word), cursorX, lineY);
        cursorX += wWidth;
      }
    }
    y = lineY + lineHeight + 1;
  }

  return y;
}

interface InlineSeg { text: string; bold: boolean }
function parseInline(line: string): InlineSeg[] {
  const out: InlineSeg[] = [];
  const regex = /\*\*([^*]+)\*\*/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = regex.exec(line)) !== null) {
    if (m.index > last) out.push({ text: line.slice(last, m.index), bold: false });
    out.push({ text: m[1], bold: true });
    last = m.index + m[0].length;
  }
  if (last < line.length) out.push({ text: line.slice(last), bold: false });
  return out.length ? out : [{ text: line, bold: false }];
}

export { MANDAT_FACTURATION_VERSION };

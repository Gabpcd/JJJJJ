import { PDFDocument, PDFName, PDFString, PDFNumber } from 'npm:pdf-lib@1.17.1';
import { verifierPdfOfficiel } from '../../../supabase/functions/copies-bulletins/pdf';
import { installerAvertissementsCopies } from '../../../supabase/functions/copies-bulletins/avertissements';
import { test, expect, vi, beforeAll, afterAll, beforeEach } from 'vitest';
import { jsPDF } from 'jspdf';

const avertissements = vi.fn();
const avertirAvantSuite = console.warn;
// Reproduit le démarrage de l'Edge, une fois pour toutes les requêtes de la
// suite isolée. Aucune installation/restauration n'a lieu dans le parseur.
beforeAll(() => {
  console.warn = avertissements;
  installerAvertissementsCopies();
});
beforeEach(() => avertissements.mockClear());
afterAll(() => { console.warn = avertirAvantSuite; });

// PDF complet avec xref exact : le nombre adversarial est un objet structuré,
// pas un faux en-tête ni une chaîne ignorée dans un commentaire.
function pdfAvecNombreBrut(nombre: string): Uint8Array {
  const objets = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /NombreRecette ${nombre} >>`,
  ];
  let pdf = '%PDF-1.7\n';
  const positions: number[] = [];
  objets.forEach((objet, i) => {
    positions.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${objet}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf += `xref\n0 4\n0000000000 65535 f \n${positions.map((p) => `${String(p).padStart(10, '0')} 00000 n \n`).join('')}`;
  pdf += `trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  // TextEncoder vient de Node dans jsdom ; normaliser le realm comme les
  // octets Storage évite un rejet d'entrée avant le véritable parsing.
  return new Uint8Array(new TextEncoder().encode(pdf));
}

async function refuse(bytes: Uint8Array) {
  let rejet = false;
  try { await verifierPdfOfficiel(bytes); } catch (e) { rejet = e instanceof Error && e.message === 'COPIE_PDF_INVALIDE'; }
  if (!rejet) throw new Error('PDF interdit accepté');
}
test('PDF réel : une page et plusieurs pages acceptées sans modifier les octets', async () => {
  const pdf = await PDFDocument.create(); pdf.addPage(); pdf.addPage();
  const bytes = await pdf.save(); const before = bytes.slice();
  await verifierPdfOfficiel(bytes);
  if (bytes.some((b,i) => b!==before[i])) throw new Error('Octets modifiés');
});
test('en-tête et EOF ne constituent pas une structure PDF', async () => {
  await refuse(new TextEncoder().encode('%PDF-1.7\nCette chaîne ne possède ni catalogue ni pages\n%%EOF'));
  await refuse(new Uint8Array()); await refuse(new Uint8Array(10485761));
});
test('PDF tronqué ou sans page refusé', async () => {
  const pdf = await PDFDocument.create();
  await refuse(await pdf.save({ addDefaultPage: false }));
  pdf.addPage(); const bytes = await pdf.save(); await refuse(bytes.subarray(0,bytes.length-20));
});
test('programme dans le catalogue refusé', async () => {
  const pdf = await PDFDocument.create(); pdf.addPage();
  pdf.catalog.set(PDFName.of('OpenAction'), pdf.context.obj({ S: 'JavaScript', JS: PDFString.of('app.alert("fictif")') }));
  await refuse(await pdf.save());
});
test('OpenAction interne acceptée, action indirecte active et annexe refusées', async () => {
  const pdf = await PDFDocument.create(); const page = pdf.addPage();
  pdf.catalog.set(PDFName.of('OpenAction'), pdf.context.obj([page.ref, 'FitH', null]));
  await verifierPdfOfficiel(await pdf.save());
  pdf.catalog.set(PDFName.of('OpenAction'), pdf.context.register(pdf.context.obj({ S: 'Launch', F: 'fictif.exe' })));
  await refuse(await pdf.save());
  pdf.catalog.delete(PDFName.of('OpenAction'));
  pdf.catalog.set(PDFName.of('Names'), pdf.context.register(pdf.context.obj({ EmbeddedFiles: pdf.context.obj({ Names: [] }) })));
  await refuse(await pdf.save());
});
test('URI active et arbre JavaScript indirect refusés', async () => {
  const pdf = await PDFDocument.create(); pdf.addPage();
  pdf.catalog.set(PDFName.of('OpenAction'), pdf.context.obj({ S: 'URI', URI: PDFString.of('javascript:alert(1)') }));
  await refuse(await pdf.save());
  pdf.catalog.delete(PDFName.of('OpenAction'));
  const arbre = pdf.context.register(pdf.context.obj({ Names: [PDFString.of('script'), pdf.context.obj({ S: 'JavaScript', JS: PDFString.of('1') })] }));
  pdf.catalog.set(PDFName.of('Names'), pdf.context.register(pdf.context.obj({ JavaScript: arbre })));
  await refuse(await pdf.save());
});

test('PDF jsPDF réel avec OpenAction interne : octets conservés', async () => {
  const doc = new jsPDF();
  doc.text('Document fictif de recette', 10, 10);
  const bytes = new Uint8Array(doc.output('arraybuffer'));
  const before = bytes.slice();
  await verifierPdfOfficiel(bytes);
  expect(bytes).toEqual(before);
});

test('le vrai parseur avertit sans divulguer la valeur numérique du document refusé', async () => {
  const valeurPriveeFictive = '912345678901234567890';
  const bytes = pdfAvecNombreBrut(valeurPriveeFictive);
  const avant = bytes.slice();
  await expect(verifierPdfOfficiel(bytes)).rejects.toThrow(/^COPIE_PDF_INVALIDE$/);
  expect(avertissements).toHaveBeenCalled();
  expect(avertissements.mock.calls.every((args) => args.length === 1 && args[0] === 'COPIE_DOCUMENT_AVERTISSEMENT')).toBe(true);
  expect(JSON.stringify(avertissements.mock.calls)).not.toContain(valeurPriveeFictive);
  expect(bytes).toEqual(avant);
});

test('un nombre hors plage dans un objet compressé est refusé sans log brut ni modification des octets', async () => {
  const pdf = await PDFDocument.create(); pdf.addPage();
  pdf.catalog.set(PDFName.of('RecetteNombreFictif'), PDFNumber.of(123456789012345678));
  const bytes = await pdf.save({ useObjectStreams: true });
  const avant = bytes.slice();
  expect(new TextDecoder().decode(bytes)).toContain('/Type /ObjStm');
  await expect(verifierPdfOfficiel(bytes)).rejects.toThrow(/^COPIE_PDF_INVALIDE$/);
  expect(avertissements).toHaveBeenCalled();
  expect(avertissements.mock.calls.every((args) => args.length === 1 && args[0] === 'COPIE_DOCUMENT_AVERTISSEMENT')).toBe(true);
  expect(JSON.stringify(avertissements.mock.calls)).not.toContain('123456789012345680');
  expect(bytes).toEqual(avant);
});

test.each(['-912345678901234567890', '9'.repeat(310)])('refuse aussi nombre négatif hors plage ou non fini %#', async (nombre) => {
  const bytes = pdfAvecNombreBrut(nombre);
  const avant = bytes.slice();
  await expect(verifierPdfOfficiel(bytes)).rejects.toThrow(/^COPIE_PDF_INVALIDE$/);
  expect(bytes).toEqual(avant);
  expect(avertissements.mock.calls.every((args) => args.length === 1 && args[0] === 'COPIE_DOCUMENT_AVERTISSEMENT')).toBe(true);
});

test('la frontière permanente reste identique avec des documents bons et adversariaux concurrents', async () => {
  const warnStable = console.warn;
  const bons = Array.from({ length: 6 }, () => pdfAvecNombreBrut('595.28'));
  const mauvais = Array.from({ length: 6 }, () => pdfAvecNombreBrut('912345678901234567890'));
  const originaux = [...bons, ...mauvais].map((bytes) => bytes.slice());
  const resultats = await Promise.allSettled([...bons, ...mauvais].map(verifierPdfOfficiel));
  expect(resultats.slice(0, 6).every((r) => r.status === 'fulfilled')).toBe(true);
  expect(resultats.slice(6).every((r) => r.status === 'rejected' && r.reason.message === 'COPIE_PDF_INVALIDE')).toBe(true);
  expect(console.warn).toBe(warnStable);
  expect(avertissements).toHaveBeenCalledTimes(6);
  expect(avertissements.mock.calls).toEqual(Array.from({ length: 6 }, () => ['COPIE_DOCUMENT_AVERTISSEMENT']));
  [...bons, ...mauvais].forEach((bytes, i) => expect(bytes).toEqual(originaux[i]));
});

test('installation idempotente, arguments ignorés et autres niveaux de logs conservés', () => {
  const warn = vi.fn(); const error = vi.fn(); const info = vi.fn(); const log = vi.fn();
  const cible = { warn, error, info, log };
  installerAvertissementsCopies(cible);
  const frontiere = cible.warn;
  installerAvertissementsCopies(cible);
  expect(cible.warn).toBe(frontiere);
  const argumentPrive = { toString: () => { throw new Error('Argument évalué'); } };
  cible.warn('Valeur privée fictive', argumentPrive);
  expect(warn.mock.calls).toEqual([['COPIE_DOCUMENT_AVERTISSEMENT']]);
  expect(cible.error).toBe(error); expect(cible.info).toBe(info); expect(cible.log).toBe(log);
});

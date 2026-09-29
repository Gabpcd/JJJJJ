import { PDFDocument, PDFName, PDFString } from 'npm:pdf-lib@1.17.1';
import { verifierPdfOfficiel } from '../../../supabase/functions/copies-bulletins/pdf';
import { test, expect } from 'vitest';
import { jsPDF } from 'jspdf';

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

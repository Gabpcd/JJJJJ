import { PDFDocument } from 'npm:pdf-lib@1.17.1';
import { chargerPolicesFacture, verifierCaracteresFacture, ErreurPoliceFacture, fontkit } from '../../supabase/functions/generate-invoice/fonts.ts';

function verifier(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

// This complements the Node handler/IO tests: native Deno module loading and
// font embedding, with no server, credentials, database or runtime IO rights.
Deno.test('vrai module Edge chargé sans serveur ; polices embarquées dans un PDF Deno', async () => {
  for (const name of ['read', 'write', 'net', 'env', 'run', 'ffi', 'sys'] as const) {
    verifier((await Deno.permissions.query({ name })).state === 'denied', `Permission ${name} non refusée`);
  }
  const serve = Deno.serve;
  let handler: ((req: Request) => Response | Promise<Response>) | undefined;
  try {
    Deno.serve = ((fn: typeof handler) => {
      verifier(!handler && typeof fn === 'function', 'Un seul handler attendu');
      handler = fn;
    }) as typeof Deno.serve;
    await import('../../supabase/functions/generate-invoice/index.ts');
    verifier(handler, 'Handler réel absent');
    const response = await handler(new Request('http://127.0.0.1/generate-invoice', { method: 'OPTIONS' }));
    verifier(response.ok, 'Preflight réel invalide');
    await response.arrayBuffer();
  } finally { Deno.serve = serve; }

  const texte = "Łukasz İpek D'Été & Αλέξανδρος Жанна";
  await verifierCaracteresFacture([texte]);
  const polices = await chargerPolicesFacture();
  const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
  const page = pdf.addPage([595, 842]);
  for (const [i, bytes] of [polices.regular, polices.bold].entries()) {
    const font = await pdf.embedFont(bytes, { subset: true });
    verifier(font.widthOfTextAtSize(texte, 12) < 495, 'Mesure police invalide');
    page.drawText(texte, { x: 50, y: 790 - i * 20, font, size: 12 });
  }
  const bytes = await pdf.save();
  verifier((await PDFDocument.load(bytes)).getPageCount() === 1, 'PDF illisible');
  try {
    await verifierCaracteresFacture(['李']);
    throw new Error('Caractère non couvert accepté');
  } catch (error) {
    verifier(error instanceof ErreurPoliceFacture && error.code === 'CARACTERE_PDF_NON_PRIS_EN_CHARGE', 'Refus glyphe attendu');
  }
});

// Le même parseur épinglé que generate-invoice ; aucune réécriture du PDF reçu.
import { PDFDocument, PDFName, PDFDict, PDFArray, PDFRef, PDFStream, PDFObject, PDFString, PDFHexString } from 'npm:pdf-lib@1.17.1';

export const MAX_PDF_BYTES = 10 * 1024 * 1024;

export async function verifierPdfOfficiel(bytes: Uint8Array): Promise<void> {
  if (!bytes.length || bytes.length > MAX_PDF_BYTES) throw new Error('COPIE_PDF_INVALIDE');
  const debut = new TextDecoder('ascii').decode(bytes.subarray(0, 8));
  const fin = new TextDecoder('ascii').decode(bytes.subarray(Math.max(0, bytes.length - 1024)));
  if (!/^%PDF-1\.[0-7]/.test(debut) && !/^%PDF-2\.0/.test(debut)) throw new Error('COPIE_PDF_INVALIDE');
  if (!/%%EOF\s*$/.test(fin)) throw new Error('COPIE_PDF_INVALIDE');
  try {
    const pdf = await PDFDocument.load(bytes, {
      ignoreEncryption: false, throwOnInvalidObject: true, updateMetadata: false,
    });
    if (pdf.isEncrypted || pdf.getPageCount() < 1 || pdf.getPageCount() > 200) throw new Error();
    // Parcours structurel, références indirectes comprises. Une OpenAction de
    // navigation interne (ex. jsPDF /FitH) est licite ; pas de programme/annexe.
    const vus = new Set<PDFObject>();
    const references = new Set<string>();
    const visiter = (objet: PDFObject | undefined, profondeur = 0): void => {
      if (!objet || profondeur > 100 || vus.size > 100000) throw new Error();
      if (objet instanceof PDFRef) {
        if (references.has(objet.toString())) return;
        references.add(objet.toString());
        visiter(pdf.context.lookup(objet), profondeur + 1); return;
      }
      if (vus.has(objet)) return;
      vus.add(objet);
      if (objet instanceof PDFStream) { visiter(objet.dict, profondeur + 1); return; }
      if (objet instanceof PDFArray) {
        for (let i = 0; i < objet.size(); i++) visiter(objet.get(i), profondeur + 1);
      } else if (objet instanceof PDFDict) {
        for (const [cle, valeur] of objet.entries()) {
          if (['JS','JavaScript','EmbeddedFiles','XFA','RichMediaContent','RichMediaSettings'].includes(cle.decodeText())) throw new Error();
          visiter(valeur, profondeur + 1);
        }
        const type = objet.lookup(PDFName.of('Type'));
        if (type instanceof PDFName && type.decodeText() === 'EmbeddedFile') throw new Error();
        const action = objet.lookup(PDFName.of('S'));
        if (action instanceof PDFName && ['JavaScript','Launch','SubmitForm','ImportData','GoToR','GoToE','Rendition','Movie','Sound'].includes(action.decodeText())) throw new Error();
        if (action instanceof PDFName && action.decodeText() === 'URI') {
          const uri = objet.lookup(PDFName.of('URI'));
          if (!(uri instanceof PDFString || uri instanceof PDFHexString)
            || !/^(https?:|mailto:)/i.test(uri.decodeText()) || /[\x00-\x20]/.test(uri.decodeText())) throw new Error();
        }
      }
    };
    visiter(pdf.catalog);
    for (const [,objet] of pdf.context.enumerateIndirectObjects()) visiter(objet);
    for (const page of pdf.getPages()) {
      const { width, height } = page.getSize();
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0
        ) throw new Error();
    }
  } catch {
    // Ne jamais exposer les détails du parseur/contenu dans les logs ou erreurs.
    throw new Error('COPIE_PDF_INVALIDE');
  }
}

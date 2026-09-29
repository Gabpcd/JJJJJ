import './pdfCompat';
import { getDocument, PDFWorker, version, type PDFDocumentProxy, type RenderTask } from 'pdfjs-dist/legacy/build/pdf.mjs';
import LocalPdfWorker from './pdf.worker.copie.ts?worker';
import { avecDelai } from '@/lib/avecDelai';

export interface DocumentApercuPdf {
  nombrePages: number;
  rendrePage: (numero: number, canvas: HTMLCanvasElement, largeur: number, dpr: number, signal: AbortSignal) => Promise<void>;
  detruire: () => void;
}

const annulation = () => new DOMException('Aperçu annulé', 'AbortError');

/** One canvas, at most 2 million pixels (8 MB RGBA), and DPR at most 2. */
export function dimensionsApercuPdf(largeurPage: number, hauteurPage: number, largeurDisponible: number, dpr: number) {
  if (![largeurPage, hauteurPage, largeurDisponible].every(n => Number.isFinite(n) && n > 0)) throw new Error('Dimensions du PDF invalides.');
  const echelle = Math.min(Math.min(largeurDisponible, 900) / largeurPage, 1200 / hauteurPage);
  const largeur = largeurPage * echelle;
  const hauteur = hauteurPage * echelle;
  const densite = Math.min(Number.isFinite(dpr) ? Math.max(1, dpr) : 1, 2, Math.sqrt(2_000_000 / (largeur * hauteur)));
  return { echelle, largeur, hauteur, densite, pixelsLargeur: Math.max(1, Math.floor(largeur * densite)), pixelsHauteur: Math.max(1, Math.floor(hauteur * densite)) };
}

export async function chargerApercuPdf(file: File, signal: AbortSignal): Promise<DocumentApercuPdf> {
  if (file.size <= 0 || file.size > 10 * 1024 * 1024) throw new Error('Le PDF doit contenir entre 1 octet et 10 Mo.');
  const bytes = await file.arrayBuffer();
  if (signal.aborted) throw annulation();
  // The legacy build includes the compatibility polyfills needed by Safari.
  // Only canvas rendering is loaded: no PDFScriptingManager/QuickJS or viewer.
  // PDF.js 6 removed the old isEvalSupported/eval rendering path.
  const port = new LocalPdfWorker();
  const worker = PDFWorker.create({ port });
  const base = new URL(`${import.meta.env.BASE_URL}pdfjs-assets/${version}/`, window.location.href).href;
  const chargement = getDocument({ data: new Uint8Array(bytes), worker,
    enableXfa: false, useWasm: false, useWorkerFetch: false, stopAtErrors: true,
    isImageDecoderSupported: false, isOffscreenCanvasSupported: false, canvasMaxAreaInBytes: 8_000_000,
    cMapUrl: `${base}cmaps/`, cMapPacked: true, standardFontDataUrl: `${base}standard_fonts/`, wasmUrl: `${base}wasm/`,
  });
  let detruit = false;
  let rendu: RenderTask | null = null;
  let sequence: Promise<void> = Promise.resolve();
  const detruire = () => {
    if (detruit) return;
    detruit = true; rendu?.cancel();
    signal.removeEventListener('abort', detruire);
    // A broken worker must not keep resources alive while destroy awaits IPC.
    const arret = setTimeout(() => { worker.destroy(); port.terminate(); }, 500);
    void chargement.destroy().catch(() => undefined).finally(() => { clearTimeout(arret); worker.destroy(); port.terminate(); });
  };
  signal.addEventListener('abort', detruire, { once: true });
  try {
    const document: PDFDocumentProxy = await avecDelai(chargement.promise, 20_000, 'Le PDF n’a pas pu être chargé à temps.');
    if (detruit || signal.aborted) throw annulation();
    if (!Number.isSafeInteger(document.numPages) || document.numPages < 1) throw new Error('Le PDF ne contient aucune page lisible.');
    return {
      nombrePages: document.numPages, detruire,
      rendrePage(numero, canvas, largeur, dpr, renduSignal) {
        const afficher = async () => {
          if (detruit || renduSignal.aborted) throw annulation();
          const page = await avecDelai(document.getPage(numero), 20_000, 'Cette page n’a pas pu être chargée à temps.');
          if (detruit || renduSignal.aborted) { page.cleanup(); throw annulation(); }
          const initial = page.getViewport({ scale: 1 });
          const dimensions = dimensionsApercuPdf(initial.width, initial.height, largeur, dpr);
          const viewport = page.getViewport({ scale: dimensions.echelle });
          canvas.width = dimensions.pixelsLargeur; canvas.height = dimensions.pixelsHauteur;
          canvas.style.width = `${dimensions.largeur}px`; canvas.style.height = `${dimensions.hauteur}px`;
          const tache = page.render({ canvas, viewport,
            transform: [dimensions.densite, 0, 0, dimensions.densite, 0, 0], background: 'rgb(255,255,255)',
          });
          rendu = tache;
          const annuler = () => tache.cancel();
          renduSignal.addEventListener('abort', annuler, { once: true });
          try {
            await avecDelai(tache.promise, 20_000, 'Cette page n’a pas pu être affichée à temps.');
            if (detruit || renduSignal.aborted) throw annulation();
          } catch (error) { tache.cancel(); await tache.promise.catch(() => undefined); throw error; }
          finally { renduSignal.removeEventListener('abort', annuler); if (rendu === tache) rendu = null; page.cleanup(); }
        };
        // A cancelled page fully releases the canvas before another page uses it.
        const resultat = sequence.catch(() => undefined).then(afficher);
        sequence = resultat;
        return resultat;
      },
    };
  } catch (error) { detruire(); throw error; }
}

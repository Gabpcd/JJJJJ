import { beforeEach, describe, expect, it, vi } from 'vitest';
import { chargerApercuPdf, dimensionsApercuPdf } from '../apercuPdfCopie';

const banc = vi.hoisted(() => ({ charger: vi.fn(), creerWorker: vi.fn(), terminer: vi.fn() }));
vi.mock('pdfjs-dist/legacy/build/pdf.mjs', () => ({ getDocument: banc.charger, PDFWorker: { create: banc.creerWorker }, version: '6.3.289' }));
vi.mock('../pdf.worker.copie.ts?worker', () => ({ default: class { terminate = banc.terminer; } }));

beforeEach(() => { banc.charger.mockReset(); banc.creerWorker.mockReset().mockReturnValue({ destroy: vi.fn() }); banc.terminer.mockReset(); });

describe('aperçu PDF local : dimensions et ressources', () => {
  it.each([[600, 800, 360, 3], [600, 800, 1000, 2], [20, 100000, 900, 3], [100000, 20, 3000, 4]])('borne le canvas et conserve les proportions (%j)', (w, h, disponible, dpr) => {
    const d = dimensionsApercuPdf(w, h, disponible, dpr);
    expect(d.largeur).toBeLessThanOrEqual(Math.min(disponible, 900));
    expect(d.hauteur).toBeLessThanOrEqual(1200);
    expect(d.densite).toBeLessThanOrEqual(2);
    expect(d.pixelsLargeur * d.pixelsHauteur).toBeLessThanOrEqual(2_000_000);
    expect(d.largeur / d.hauteur).toBeCloseTo(w / h);
  });
  it.each([0, -1, Number.NaN, Number.POSITIVE_INFINITY])('refuse une dimension impossible %s', value => {
    expect(() => dimensionsApercuPdf(value, 800, 360, 2)).toThrow('Dimensions');
  });

  it('lit des octets locaux, sans scripting, wasm ou URL de document, puis libère worker et page', async () => {
    const bytes = new Uint8Array([37, 80, 68, 70, 45]);
    const file = { size: bytes.length, arrayBuffer: async () => bytes.slice().buffer } as File;
    const page = { getViewport: ({ scale }: { scale: number }) => ({ width: 600 * scale, height: 800 * scale }),
      render: vi.fn().mockReturnValue({ promise: Promise.resolve(), cancel: vi.fn() }), cleanup: vi.fn() };
    const destroy = vi.fn().mockResolvedValue(undefined);
    banc.charger.mockReturnValue({ promise: Promise.resolve({ numPages: 2, getPage: vi.fn().mockResolvedValue(page) }), destroy });
    const controleur = new AbortController();
    const pdf = await chargerApercuPdf(file, controleur.signal);
    expect(banc.charger).toHaveBeenCalledWith(expect.objectContaining({ data: bytes, enableXfa: false, useWasm: false, useWorkerFetch: false, stopAtErrors: true, isImageDecoderSupported: false, isOffscreenCanvasSupported: false }));
    expect(banc.charger.mock.calls[0][0]).not.toHaveProperty('url');
    expect(banc.charger.mock.calls[0][0].standardFontDataUrl).toContain('/pdfjs-assets/6.3.289/standard_fonts/');
    const canvas = document.createElement('canvas');
    await pdf.rendrePage(1, canvas, 360, 3, new AbortController().signal);
    expect(canvas.width).toBe(720); expect(canvas.height).toBe(960);
    expect(page.cleanup).toHaveBeenCalledOnce();
    expect(bytes).toEqual(new Uint8Array([37, 80, 68, 70, 45]));
    controleur.abort(); await Promise.resolve(); await Promise.resolve();
    expect(destroy).toHaveBeenCalledOnce(); expect(banc.terminer).toHaveBeenCalledOnce();
  });

  it('un PDF refusé ne donne aucun document prêt et détruit le chargement', async () => {
    const destroy = vi.fn().mockResolvedValue(undefined);
    banc.charger.mockReturnValue({ promise: Promise.reject(new Error('Invalid PDF')), destroy });
    const file = { size: 4, arrayBuffer: async () => new Uint8Array(4).buffer } as File;
    await expect(chargerApercuPdf(file, new AbortController().signal)).rejects.toThrow('Invalid PDF');
    expect(destroy).toHaveBeenCalledOnce();
  });
});

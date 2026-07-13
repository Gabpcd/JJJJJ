import { describe, expect, it } from 'vitest';
import {
  classerFormatDocument,
  sanitiserNomFichier,
  verifierFichierDocument,
} from './documentUpload';

describe('classerFormatDocument', () => {
  it.each([
    ['preuve.pdf', 'application/pdf'],
    ['photo.jpg', 'image/jpeg'],
    ['photo.png', 'image/png'],
    ['photo.webp', 'image/webp'],
    ['scan.PDF', 'application/octet-stream'],
  ])('accepte %s (%s)', (name, type) => {
    expect(classerFormatDocument({ name, type })).toBe('SUPPORTED');
  });

  it.each([
    ['photo.heic', 'image/heic'],
    ['photo.heif', 'image/heif'],
    ['photo.HEIC', ''],
  ])('isole HEIC/HEIF avec une erreur dédiée', (name, type) => {
    expect(classerFormatDocument({ name, type })).toBe('HEIC_UNSUPPORTED');
  });

  it('ne fait pas confiance à une extension image contredite par le MIME', () => {
    expect(classerFormatDocument({ name: 'malware.jpg', type: 'text/html' })).toBe('UNSUPPORTED');
  });

  it('rejette aussi deux formats supportés qui se contredisent', () => {
    expect(classerFormatDocument({ name: 'piece.jpg', type: 'application/pdf' })).toBe('UNSUPPORTED');
  });

  it('contrôle la signature binaire avant téléversement', async () => {
    const fauxPdf = new File([new Uint8Array([0xff, 0xd8, 0xff, 0x00])], 'piece.pdf', { type: 'application/pdf' });
    await expect(verifierFichierDocument(fauxPdf)).resolves.toMatchObject({
      ok: false,
      code: 'INVALID_SIGNATURE',
    });
  });

  it('renvoie un MIME canonique pour un PDF réel sans MIME navigateur', async () => {
    const pdf = new File([new TextEncoder().encode('%PDF-1.7\n')], 'SCAN.PDF', { type: '' });
    await expect(verifierFichierDocument(pdf)).resolves.toEqual({
      ok: true,
      mime: 'application/pdf',
      extension: 'pdf',
    });
  });

  it('applique le sous-ensemble autorisé à une surface PDF uniquement', async () => {
    const jpeg = new File([new Uint8Array([0xff, 0xd8, 0xff, 0x00])], 'photo.jpg', { type: 'image/jpeg' });
    await expect(verifierFichierDocument(jpeg, { allowedMimes: ['application/pdf'] })).resolves.toMatchObject({
      ok: false,
      code: 'UNSUPPORTED',
    });
  });

  it('rejette les fichiers vides et les fichiers trop lourds', async () => {
    const vide = new File([], 'vide.pdf', { type: 'application/pdf' });
    const lourd = new File([new TextEncoder().encode('%PDF-1.7')], 'lourd.pdf', { type: 'application/pdf' });
    await expect(verifierFichierDocument(vide)).resolves.toMatchObject({ code: 'EMPTY' });
    await expect(verifierFichierDocument(lourd, { maxBytes: 4 })).resolves.toMatchObject({ code: 'TOO_LARGE' });
  });

  it('assainit le nom sans chemin, points consécutifs ni extension trompeuse', () => {
    expect(sanitiserNomFichier('../../Pièce.. finale.jpg', 'application/pdf')).toBe('Piece-finale.pdf');
  });
});

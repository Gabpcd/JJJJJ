import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  normalizeIsoCivilDate,
  strictAiVerificationQuality,
  validateDocumentFile,
} from '../../../supabase/functions/_shared/verification-rules';

const source = (name: string) => readFileSync(
  `supabase/functions/${name}/index.ts`,
  'utf8',
);

describe('qualité IA établissement — fail closed', () => {
  it('exige une liste antifraude explicite, homogène et non ambiguë', () => {
    expect(strictAiVerificationQuality({
      confiance: 'HAUTE',
      score_confiance: 95,
    }).antifraudComplete).toBe(false);
    expect(strictAiVerificationQuality({
      confiance: 'HAUTE',
      score_confiance: 95,
      indices_falsification: 'aucun',
    }).antifraudComplete).toBe(false);
    expect(strictAiVerificationQuality({
      confiance: 'HAUTE',
      score_confiance: 95,
      indices_falsification: [42],
    }).antifraudComplete).toBe(false);
    expect(strictAiVerificationQuality({
      confiance: 'HAUTE',
      score_confiance: 95,
      indices_falsification: [''],
    }).antifraudComplete).toBe(false);
    expect(strictAiVerificationQuality({
      confiance: 'HAUTE',
      score_confiance: 95,
      indices_falsification: [],
    }).antifraudComplete).toBe(true);
  });

  it('exige simultanément confiance HAUTE et score numérique fini entre 85 et 100', () => {
    const quality = (confiance: unknown, score: unknown) => strictAiVerificationQuality({
      confiance,
      score_confiance: score,
      indices_falsification: [],
    }).highConfidence;

    expect(quality('HAUTE', 85)).toBe(true);
    expect(quality('HAUTE', 100)).toBe(true);
    expect(quality('MOYENNE', 99)).toBe(false);
    expect(quality('HAUTE', 84)).toBe(false);
    expect(quality('HAUTE', '99')).toBe(false);
    expect(quality('HAUTE', Number.NaN)).toBe(false);
    expect(quality('HAUTE', Number.POSITIVE_INFINITY)).toBe(false);
    expect(quality('HAUTE', 101)).toBe(false);
    expect(quality(' haute ', 99)).toBe(false);
  });
});

describe('date civile ISO de la pièce d’identité', () => {
  it('accepte uniquement une date réelle au format exact YYYY-MM-DD', () => {
    expect(normalizeIsoCivilDate('2024-02-29')).toBe('2024-02-29');
    expect(normalizeIsoCivilDate('2025-02-29')).toBeNull();
    expect(normalizeIsoCivilDate('2026-13-01')).toBeNull();
    expect(normalizeIsoCivilDate('2026-04-31')).toBeNull();
    expect(normalizeIsoCivilDate('2026-7-14')).toBeNull();
    expect(normalizeIsoCivilDate('2026-07-14T00:00:00Z')).toBeNull();
    expect(normalizeIsoCivilDate(null)).toBeNull();
  });
});

describe('authenticité binaire des documents établissement', () => {
  const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const webp = new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);

  it('accepte les signatures conformes à leur MIME déclaré', () => {
    expect(validateDocumentFile(pdf, 'application/pdf')).toEqual({ ok: true, mime: 'application/pdf' });
    expect(validateDocumentFile(jpeg, 'image/jpeg')).toEqual({ ok: true, mime: 'image/jpeg' });
    expect(validateDocumentFile(png, 'image/png')).toEqual({ ok: true, mime: 'image/png' });
    expect(validateDocumentFile(webp, 'image/webp')).toEqual({ ok: true, mime: 'image/webp' });
  });

  it('refuse un MIME absent, générique ou contredit par la signature', () => {
    expect(validateDocumentFile(pdf, null)).toEqual({ ok: false, code: 'UNSUPPORTED_MIME' });
    expect(validateDocumentFile(pdf, 'application/octet-stream')).toEqual({ ok: false, code: 'UNSUPPORTED_MIME' });
    expect(validateDocumentFile(pdf, 'image/jpeg')).toEqual({ ok: false, code: 'INVALID_SIGNATURE' });
    expect(validateDocumentFile(jpeg, 'application/pdf')).toEqual({ ok: false, code: 'INVALID_SIGNATURE' });
  });

  it('refuse les fichiers vides ou supérieurs à la limite avant l’appel IA', () => {
    expect(validateDocumentFile(new Uint8Array(), 'application/pdf')).toEqual({ ok: false, code: 'EMPTY' });
    expect(validateDocumentFile(pdf, 'application/pdf', pdf.byteLength - 1)).toEqual({ ok: false, code: 'TOO_LARGE' });
  });
});

describe('intégration des gates dans les fonctions établissement', () => {
  const aiFunctions = [
    'verify-piece-identite-etab',
    'verify-justificatif-fonction',
    'verify-rib-etablissement',
    'verify-contrat-etablissement',
  ];

  it.each(aiFunctions)('%s exige qualité stricte et antifraude complète', (name) => {
    const edge = source(name);
    expect(edge).toContain('strictAiVerificationQuality');
    expect(edge).toContain('quality.highConfidence');
    expect(edge).toContain('!quality.antifraudComplete');
    expect(edge).not.toMatch(/confiance[^\n]*=== ["']HAUTE["'][^\n]*\|\|/);
  });

  it.each([
    'verify-piece-identite-etab',
    'verify-justificatif-fonction',
    'verify-rib-etablissement',
  ])('%s vérifie taille, MIME déclaré et signature avant base64', (name) => {
    const edge = source(name);
    const validation = edge.indexOf('validateDocumentFile(');
    const conversion = edge.indexOf('const base64');
    expect(validation).toBeGreaterThan(0);
    expect(conversion).toBeGreaterThan(validation);
  });

  it('ne déduit plus le MIME du RIB et exige un document complet', () => {
    const rib = source('verify-rib-etablissement');
    expect(rib).not.toContain('devinerMime');
    expect(rib).toContain('validateDocumentFile(bytes, fileData.type)');
    expect(rib).toContain('analysis.document_complet === true');
    expect(rib).toContain('"document_complet": true/false');
  });

  it('normalise strictement la date de la pièce d’identité', () => {
    const identity = source('verify-piece-identite-etab');
    expect(identity).toContain('normalizeIsoCivilDate(result.date_expiration)');
    expect(identity).not.toContain('Date.parse(');
  });
});

import { describe, expect, it } from 'vitest';
import { resolveLicenseSpecialty } from '../../supabase/functions/_shared/licence-specialite';

describe('spécialité lue sur la licence', () => {
  const rows = [{ code: 'SM01', label: 'Médecine générale' }, { code: 'SM02', label: 'Cardiologie' }];
  it('accepte uniquement un code ou libellé exact normalisé', () => {
    expect(resolveLicenseSpecialty(' sm01 ', rows)).toBe('SM01');
    expect(resolveLicenseSpecialty(' MÉDECINE   générale ', rows)).toBe('SM01');
    expect(resolveLicenseSpecialty('médecine', rows)).toBeNull();
    expect(resolveLicenseSpecialty('SM03', rows)).toBeNull();
  });
  it('refuse une réponse ambiguë, un catalogue illisible et un libellé approchant', () => {
    expect(resolveLicenseSpecialty('Cardiologie', [...rows, { code: 'SM04', label: 'Cardiologie' }])).toBeNull();
    expect(resolveLicenseSpecialty('cardio', rows)).toBeNull();
    expect(resolveLicenseSpecialty('Cardiologie', null)).toBeNull();
    expect(resolveLicenseSpecialty(null, rows)).toBeNull();
  });
});

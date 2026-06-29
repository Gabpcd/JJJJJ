import { describe, it, expect } from 'vitest';
import { validerSiret } from '../luhn';

describe('validerSiret', () => {
  it('should validate Jolene SIRET (10330574400015)', () => {
    const result = validerSiret('10330574400015');
    expect(result.valide).toBe(true);
    expect(result.message).toBe('SIRET valide');
  });

  it('should reject SIRET with wrong length', () => {
    expect(validerSiret('1234567890').valide).toBe(false);
    expect(validerSiret('1234567890').message).toContain('14 chiffres');
  });

  it('should reject SIRET with letters', () => {
    expect(validerSiret('1234567890ABCD').valide).toBe(false);
  });

  it('should reject all-zeros SIRET', () => {
    expect(validerSiret('00000000000000').valide).toBe(false);
    expect(validerSiret('00000000000000').message).toBe('SIRET invalide');
  });

  it('should reject SIRET with bad checksum', () => {
    expect(validerSiret('10330574400016').valide).toBe(false);
    expect(validerSiret('10330574400016').message).toContain('invalide');
  });

  it('should handle spaces in SIRET', () => {
    const result = validerSiret('103 305 744 00015');
    expect(result.valide).toBe(true);
  });

  it('should reject empty string', () => {
    expect(validerSiret('').valide).toBe(false);
  });
});

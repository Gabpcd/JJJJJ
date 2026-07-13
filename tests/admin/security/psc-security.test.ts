import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  extractPscProfession,
  extractRppsEvidence,
  extractVerifiedEmail,
  isProfessionCompatible,
  mapPscProfessionCode,
  normalizeRpps,
  resolvePscEnvironment,
} from '../../../supabase/functions/_shared/psc-security';

describe('Pro Santé Connect — preuves déterministes', () => {
  it('échoue fermé sans environnement PSC explicite', () => {
    expect(resolvePscEnvironment(undefined)).toBeNull();
    expect(resolvePscEnvironment('')).toBeNull();
    expect(resolvePscEnvironment('prod')).toBeNull();
    expect(resolvePscEnvironment('sandbox')).toBe('sandbox');
    expect(resolvePscEnvironment('production')).toBe('production');
  });

  it('mappe uniquement les codes TRE_G15 supportés vers de vraies valeurs type_profession', () => {
    expect(mapPscProfessionCode('10')).toBe('MEDECIN');
    expect(mapPscProfessionCode('35')).toBe('AS');
    expect(mapPscProfessionCode('37')).toBe('AUXILIAIRE_PUERICULTURE');
    expect(mapPscProfessionCode('98')).toBe('MANIPULATEUR_RADIO');

    // 93 = Psychologue dans TRE_G15 : Jolene ne possède pas cette valeur.
    expect(mapPscProfessionCode('93')).toBeNull();
    expect(mapPscProfessionCode('infirmier')).toBeNull();
    expect(mapPscProfessionCode('99')).toBeNull();
  });

  it('ne transforme jamais une profession inconnue ou ambiguë en IDE', () => {
    expect(extractPscProfession({ codeProfession: '99' })).toBeNull();
    expect(extractPscProfession({ libelleProfession: 'Infirmier' })).toBeNull();
    expect(extractPscProfession({
      SubjectRefPro: {
        exercices: [{ codeProfession: '10' }, { codeProfession: '60' }],
      },
    })).toBeNull();
    expect(extractPscProfession({
      SubjectRefPro: {
        exercices: [{ codeProfession: '60' }, { codeProfession: '69' }],
      },
    })?.profession).toBe('IDE');
  });

  it('accepte seulement un RPPS complet de 11 chiffres avec clé de Luhn', () => {
    const validRpps = '10001234565';
    expect(normalizeRpps(validRpps)).toBe(validRpps);
    expect(normalizeRpps(`8${validRpps}`)).toBe(validRpps);
    expect(normalizeRpps('10001234567')).toBeNull();
    expect(normalizeRpps('00000000000')).toBeNull();
    expect(normalizeRpps(`8${validRpps}9`)).toBeNull();
    expect(normalizeRpps(`8${validRpps.slice(0, 8)}`)).toBeNull();
  });

  it('refuse les RPPS invalides, tronqués ou contradictoires entre claims', () => {
    const rppsA = '10001234565';
    const rppsB = '10101234564';
    expect(extractRppsEvidence({ SubjectNameID: `8${rppsA}` })).toEqual({
      status: 'verified',
      rpps: rppsA,
    });
    expect(extractRppsEvidence({ SubjectNameID: '810001234567' })).toEqual({ status: 'invalid' });
    expect(extractRppsEvidence({ SubjectNameID: '81000123' })).toEqual({ status: 'invalid' });
    expect(extractRppsEvidence(
      { SubjectNameID: `8${rppsA}` },
      { preferred_username: `8${rppsB}` },
    )).toEqual({ status: 'invalid' });
    expect(extractRppsEvidence({ preferred_username: 'ANS20210107161422' })).toEqual({ status: 'absent' });
  });

  it('n’utilise un email que si email_verified est le booléen true', () => {
    expect(extractVerifiedEmail({ email: 'Marie@Example.fr', email_verified: true })).toEqual({
      status: 'verified',
      email: 'marie@example.fr',
    });
    expect(extractVerifiedEmail({ email: 'marie@example.fr', email_verified: false })).toEqual({
      status: 'unverified',
    });
    expect(extractVerifiedEmail({ email: 'marie@example.fr', email_verified: 'true' })).toEqual({
      status: 'unverified',
    });
    expect(extractVerifiedEmail(
      { email: 'marie@example.fr', email_verified: true },
      { email: 'marion@example.fr', email_verified: true },
    )).toEqual({ status: 'invalid' });
    expect(extractVerifiedEmail(
      { email: 'marie@example.fr', email_verified: true },
      { email: 'marie@example.fr', email_verified: false },
    )).toEqual({ status: 'invalid' });
  });

  it('exige la compatibilité de profession du compte existant', () => {
    expect(isProfessionCompatible('IDE', 'IDE')).toBe(true);
    expect(isProfessionCompatible('IADE', 'IDE')).toBe(true);
    expect(isProfessionCompatible('IBODE', 'IDE')).toBe(true);
    expect(isProfessionCompatible('MEDECIN', 'IDE')).toBe(false);
    expect(isProfessionCompatible('IDE', 'MEDECIN')).toBe(false);
  });

  it('branche effectivement ces preuves dans authorize et callback', () => {
    const authorize = readFileSync('supabase/functions/psc-authorize/index.ts', 'utf8');
    const callback = readFileSync('supabase/functions/psc-callback/index.ts', 'utf8');

    expect(authorize).toContain('resolvePscEnvironment(Deno.env.get("PSC_ENVIRONMENT"))');
    expect(callback).toContain('resolvePscEnvironment(Deno.env.get("PSC_ENVIRONMENT"))');
    expect(authorize).not.toMatch(/PSC_ENVIRONMENT[^\n]+\|\|\s*["']sandbox["']/);
    expect(callback).not.toMatch(/PSC_ENVIRONMENT[^\n]+\|\|\s*["']sandbox["']/);
    expect(callback).toContain('extractRppsEvidence(signedClaims, userinfo)');
    expect(callback).toContain('extractVerifiedEmail(signedClaims, userinfo)');
    expect(callback).toContain('profileIsCompatible(existingProfile, profession, rpps, pscSub)');
    expect(callback).not.toContain('.ilike("email"');
    expect(callback).not.toContain('substring(0, 11)');
  });
});

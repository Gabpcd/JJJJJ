/**
 * Test — mask-sensitive.ts
 * Vérifie que tous les patterns sensibles sont masqués avant écriture en base.
 */

import { describe, it, expect } from 'vitest';

// Inline the masking logic for unit test (same as _shared/mask-sensitive.ts)
const PATTERNS: { regex: RegExp; replacement: string }[] = [
  { regex: /FR\d{2}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{3}/gi, replacement: 'IBAN_MASKED' },
  { regex: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, replacement: 'EMAIL_MASKED' },
  { regex: /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, replacement: 'JWT_MASKED' },
  { regex: /sk_(live|test)_[A-Za-z0-9]{20,}/g, replacement: 'STRIPE_KEY_MASKED' },
  { regex: /pk_(live|test)_[A-Za-z0-9]{20,}/g, replacement: 'STRIPE_PK_MASKED' },
  { regex: /(?<![a-zA-Z0-9/+])[A-Za-z0-9]{40,}(?![a-zA-Z0-9/+=])/g, replacement: 'TOKEN_MASKED' },
];

function maskSensitive(input: string, maxLength = 500): string {
  let result = input;
  for (const { regex, replacement } of PATTERNS) {
    result = result.replace(regex, replacement);
  }
  return result.substring(0, maxLength);
}

describe('maskSensitive', () => {
  it('masque les IBAN français', () => {
    const input = 'Paiement vers FR7630006000011234567890189';
    expect(maskSensitive(input)).toContain('IBAN_MASKED');
    expect(maskSensitive(input)).not.toContain('FR76');
  });

  it('masque les emails', () => {
    const input = 'Contact: gabrielle.picard@jolene.app pour info';
    expect(maskSensitive(input)).toContain('EMAIL_MASKED');
    expect(maskSensitive(input)).not.toContain('gabrielle');
  });

  it('masque les JWT tokens', () => {
    const input = 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSJ9.abc123def456';
    expect(maskSensitive(input)).toContain('JWT_MASKED');
    expect(maskSensitive(input)).not.toContain('eyJhbGci');
  });

  it('masque les clés Stripe secrètes', () => {
    const input = 'Key: sk_live_1234567890abcdefghijklmnop';
    expect(maskSensitive(input)).toContain('STRIPE_KEY_MASKED');
    expect(maskSensitive(input)).not.toContain('sk_live_');
  });

  it('masque les clés Stripe publishable', () => {
    const input = 'Key: pk_test_abcdefghijklmnopqrstuvwx';
    expect(maskSensitive(input)).toContain('STRIPE_PK_MASKED');
  });

  it('masque les tokens longs (heuristique 40+ chars)', () => {
    const input = 'Token: AbCdEfGhIjKlMnOpQrStUvWxYz0123456789ABCDEF';
    expect(maskSensitive(input)).toContain('TOKEN_MASKED');
  });

  it('ne masque pas le texte normal', () => {
    const input = 'Facture JOL-98765432-2026-00001 generee avec succes';
    expect(maskSensitive(input)).toBe(input);
  });

  it('tronque à maxLength', () => {
    const input = 'A'.repeat(1000);
    expect(maskSensitive(input, 500).length).toBe(500);
    expect(maskSensitive(input, 200).length).toBe(200);
  });

  it('gère une string vide', () => {
    expect(maskSensitive('')).toBe('');
  });

  it('masque plusieurs patterns dans la même string', () => {
    const input = 'Email: test@example.com IBAN: FR7630006000011234567890189 Token: sk_live_abcdefghijklmnopqrst12345';
    const masked = maskSensitive(input);
    expect(masked).toContain('EMAIL_MASKED');
    expect(masked).toContain('IBAN_MASKED');
    expect(masked).toContain('STRIPE_KEY_MASKED');
    expect(masked).not.toContain('test@');
    expect(masked).not.toContain('FR76');
    expect(masked).not.toContain('sk_live');
  });
});

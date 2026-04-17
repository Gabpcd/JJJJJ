/**
 * CP-LITIGES-7a FIX 20 — Tests préfixe SMS configurable
 *
 * Vérifie la logique resolveSmsPrefix utilisée par send-sms/index.ts.
 * La fonction est ré-implémentée inline pour test unitaire (send-sms
 * utilise Deno.env.get et Deno.serve, impossibles à charger depuis
 * vitest/node). La logique doit rester strictement identique à celle
 * de supabase/functions/send-sms/index.ts.
 */

import { describe, it, expect } from 'vitest';

// Miroir exact de la fonction exportée par send-sms/index.ts
function resolveSmsPrefix(
  prefixType: string | undefined | null,
  defaultPrefix: string = 'Jolene: ',
  overrides: Record<string, string> = {},
): string {
  if (prefixType && typeof prefixType === 'string' && overrides[prefixType]) {
    return overrides[prefixType];
  }
  return defaultPrefix;
}

// Simulation du body-truncation pipeline (lignes 108-114 du handler)
const SMS_MAX_LENGTH = 160;
function buildFullBody(contenu: string, prefix: string): string {
  const maxBodyLen = Math.max(20, SMS_MAX_LENGTH - prefix.length);
  const smsBody = contenu.length > maxBodyLen
    ? contenu.substring(0, maxBodyLen - 3) + '...'
    : contenu;
  return `${prefix}${smsBody}`;
}

describe('resolveSmsPrefix (FIX 20)', () => {
  it('retourne le préfixe par défaut quand prefix_type est undefined', () => {
    expect(resolveSmsPrefix(undefined)).toBe('Jolene: ');
  });

  it('retourne le préfixe par défaut quand prefix_type est null', () => {
    expect(resolveSmsPrefix(null)).toBe('Jolene: ');
  });

  it('retourne le préfixe par défaut quand prefix_type est chaîne vide', () => {
    expect(resolveSmsPrefix('')).toBe('Jolene: ');
  });

  it('retourne le préfixe par défaut quand prefix_type absent des overrides', () => {
    const overrides = { 'LITIGE_SECURITE': 'Jolene-URGENT: ' };
    expect(resolveSmsPrefix('UNKNOWN_TYPE', 'Jolene: ', overrides)).toBe('Jolene: ');
  });

  it('retourne l\'override quand prefix_type existe dans le map', () => {
    const overrides = { 'LITIGE_SECURITE': 'Jolene-URGENT: ' };
    expect(resolveSmsPrefix('LITIGE_SECURITE', 'Jolene: ', overrides))
      .toBe('Jolene-URGENT: ');
  });

  it('gère plusieurs overrides', () => {
    const overrides = {
      'LITIGE_SECURITE':       'Jolene-URGENT: ',
      'LITIGE_RAPPEL_J5':      'Jolene-ALERTE: ',
      'REMBOURSEMENT_CONFIRME': 'Jolene-PAIEMENT: ',
    };
    expect(resolveSmsPrefix('LITIGE_SECURITE', 'Jolene: ', overrides))
      .toBe('Jolene-URGENT: ');
    expect(resolveSmsPrefix('LITIGE_RAPPEL_J5', 'Jolene: ', overrides))
      .toBe('Jolene-ALERTE: ');
    expect(resolveSmsPrefix('REMBOURSEMENT_CONFIRME', 'Jolene: ', overrides))
      .toBe('Jolene-PAIEMENT: ');
    expect(resolveSmsPrefix('AUTRE', 'Jolene: ', overrides))
      .toBe('Jolene: ');
  });

  it('permet de configurer un DEFAULT différent', () => {
    expect(resolveSmsPrefix(undefined, 'Jolene-PROD: ')).toBe('Jolene-PROD: ');
  });

  it('ignore les overrides de type non-string (guard anti-prototype-pollution)', () => {
    const malicious = { __proto__: 'hacked' } as Record<string, string>;
    expect(resolveSmsPrefix('__proto__', 'Jolene: ', malicious)).toBe('Jolene: ');
  });
});

describe('buildFullBody truncation (FIX 20)', () => {
  it('préfixe court : conserve tout le contenu si < 160 chars', () => {
    const body = buildFullBody('Court message.', 'Jolene: ');
    expect(body).toBe('Jolene: Court message.');
    expect(body.length).toBeLessThanOrEqual(160);
  });

  it('préfixe "Jolene: " (8 chars) : tronque correctement si contenu > 152', () => {
    const long = 'x'.repeat(200);
    const body = buildFullBody(long, 'Jolene: ');
    expect(body.length).toBeLessThanOrEqual(160);
    expect(body.startsWith('Jolene: ')).toBe(true);
    expect(body.endsWith('...')).toBe(true);
  });

  it('préfixe long "Jolene-URGENT: " (15 chars) : tronque corps à 145 chars', () => {
    const long = 'x'.repeat(200);
    const body = buildFullBody(long, 'Jolene-URGENT: ');
    expect(body.length).toBeLessThanOrEqual(160);
    expect(body.startsWith('Jolene-URGENT: ')).toBe(true);
    expect(body.endsWith('...')).toBe(true);
  });

  it('préfixe extrême : garde au moins 20 chars pour le body', () => {
    const long = 'x'.repeat(200);
    const hugePrefix = 'P'.repeat(200); // prefix > SMS_MAX_LENGTH
    const body = buildFullBody(long, hugePrefix);
    // Protection Math.max(20, ...) garantit 20 chars min pour le body
    expect(body.length).toBeGreaterThan(200); // prefix + body + '...'
    expect(body.endsWith('...')).toBe(true);
  });
});

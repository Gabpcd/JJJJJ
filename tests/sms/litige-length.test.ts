/**
 * CP-LITIGES-7a Bloc 4 (FIX 14) — Tests longueur SMS litiges
 *
 * Vérifie que le corps SMS généré par fn_litige_push_notification (CP5
 * migration 20260417130500_cp_litiges_5_sms_extension.sql L91-97) reste
 * sous la limite Twilio (160 chars préfixe inclus, soit ~140 chars de
 * corps avec `Jolene: ` = 8 chars de préfixe).
 *
 * Les 5 types SMS éligibles (définis dans la whitelist CP5 L63-67) :
 *   - LITIGE_OUVERTURE
 *   - REMBOURSEMENT_CONFIRME
 *   - LITIGE_RAPPEL_J1
 *   - LITIGE_RAPPEL_J3
 *   - LITIGE_RAPPEL_J5
 *
 * La fonction SQL est mirror-ée en TS ci-dessous pour test unitaire (même
 * pattern que prefix.test.ts et mask-sensitive.test.ts : la source SQL
 * n'est pas exécutable depuis vitest/node).
 */

import { describe, it, expect } from 'vitest';

const SMS_BODY_MAX = 140; // 160 Twilio - 8 chars "Jolene: "
const SMS_TOTAL_MAX = 160;

/**
 * Miroir du CASE plpgsql fn_litige_push_notification (CP5 L91-97).
 * Renvoie uniquement le corps SMS (sans préfixe `Jolene: `).
 */
function buildLitigeSmsContent(
  typeNotif: string,
  data: Record<string, string>,
  corpsFallback: string = '',
): string {
  switch (typeNotif) {
    case 'LITIGE_OUVERTURE':
      return `un litige ${data.type_litige ?? ''} a été ouvert sur votre mission. Répondez sous 72h.`;
    case 'REMBOURSEMENT_CONFIRME':
      return `remboursement de ${data.montant ?? '?'}€ effectué (avoir ${data.numero_avoir ?? ''}). Délai bancaire 2-5j.`;
    case 'LITIGE_RAPPEL_J1':
      return `litige en attente depuis 1j. Répondez sous 24h pour éviter l'escalade.`;
    case 'LITIGE_RAPPEL_J3':
      return `litige en attente depuis 3j. Réponse urgente requise.`;
    case 'LITIGE_RAPPEL_J5':
      return `litige en attente depuis 5j ouvrés. Escalade imminente.`;
    default:
      return corpsFallback;
  }
}

describe('SMS litiges — longueur corps (FIX 14)', () => {
  it('LITIGE_OUVERTURE avec type_litige max : corps < 140 chars', () => {
    // Valeur la plus longue attendue pour type_litige (enum SQL CP1)
    const body = buildLitigeSmsContent('LITIGE_OUVERTURE', {
      type_litige: 'MISSION_NON_EFFECTUEE_OU_INCOMPLETE',
    });
    expect(body.length).toBeLessThanOrEqual(SMS_BODY_MAX);
    expect(`Jolene: ${body}`.length).toBeLessThanOrEqual(SMS_TOTAL_MAX);
  });

  it('REMBOURSEMENT_CONFIRME avec montant + avoir max : corps < 140 chars', () => {
    // Montant max plausible : 99999.99 (6 chars + .99), numero_avoir format AV-YYYY-MM-NNNN = 14 chars
    const body = buildLitigeSmsContent('REMBOURSEMENT_CONFIRME', {
      montant: '99999.99',
      numero_avoir: 'AV-2026-12-9999',
    });
    expect(body.length).toBeLessThanOrEqual(SMS_BODY_MAX);
    expect(`Jolene: ${body}`.length).toBeLessThanOrEqual(SMS_TOTAL_MAX);
  });

  it('LITIGE_RAPPEL_J1 : corps fixe < 140 chars', () => {
    const body = buildLitigeSmsContent('LITIGE_RAPPEL_J1', {});
    expect(body.length).toBeLessThanOrEqual(SMS_BODY_MAX);
    expect(`Jolene: ${body}`.length).toBeLessThanOrEqual(SMS_TOTAL_MAX);
  });

  it('LITIGE_RAPPEL_J3 : corps fixe < 140 chars', () => {
    const body = buildLitigeSmsContent('LITIGE_RAPPEL_J3', {});
    expect(body.length).toBeLessThanOrEqual(SMS_BODY_MAX);
    expect(`Jolene: ${body}`.length).toBeLessThanOrEqual(SMS_TOTAL_MAX);
  });

  it('LITIGE_RAPPEL_J5 : corps fixe < 140 chars', () => {
    const body = buildLitigeSmsContent('LITIGE_RAPPEL_J5', {});
    expect(body.length).toBeLessThanOrEqual(SMS_BODY_MAX);
    expect(`Jolene: ${body}`.length).toBeLessThanOrEqual(SMS_TOTAL_MAX);
  });

  it('tous les types éligibles : SMS complet (préfixe inclus) ≤ 160 chars', () => {
    const cases: Array<[string, Record<string, string>]> = [
      ['LITIGE_OUVERTURE', { type_litige: 'MISSION_NON_EFFECTUEE_OU_INCOMPLETE' }],
      ['REMBOURSEMENT_CONFIRME', { montant: '99999.99', numero_avoir: 'AV-2026-12-9999' }],
      ['LITIGE_RAPPEL_J1', {}],
      ['LITIGE_RAPPEL_J3', {}],
      ['LITIGE_RAPPEL_J5', {}],
    ];
    for (const [type, data] of cases) {
      const body = buildLitigeSmsContent(type, data);
      const full = `Jolene: ${body}`;
      expect(full.length, `${type} dépasse 160 chars : ${full.length} chars`).toBeLessThanOrEqual(SMS_TOTAL_MAX);
    }
  });

  it('type non éligible : retourne le corps fallback (non tronqué ici)', () => {
    // Les types hors whitelist passent par `ELSE p_corps` en SQL : longueur
    // non contrôlée par CP5 mais tronquée par send-sms (FIX 20 buildFullBody).
    const body = buildLitigeSmsContent('AUTRE_TYPE', {}, 'fallback corps');
    expect(body).toBe('fallback corps');
  });
});

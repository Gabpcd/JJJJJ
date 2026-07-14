import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714064000_securiser_otp_telephone.sql',
  'utf8',
);
const worker = readFileSync(
  'supabase/functions/process-externalisation-actions/index.ts',
  'utf8',
);
const sendSms = readFileSync('supabase/functions/send-sms/index.ts', 'utf8');

describe('OTP téléphone — émission et expurgation fail-closed', () => {
  it('génère un code non biaisé et fige sa cible métier', () => {
    expect(migration).toContain('extensions.gen_random_bytes(4)');
    expect(migration).toContain('IF v_value < 4294000000 THEN');
    expect(migration).toContain("cible_type IN ('SOIGNANT', 'ETABLISSEMENT')");
    expect(migration).toContain("pg_advisory_xact_lock(hashtextextended('otp-phone:'");
    expect(migration).toContain('v_code_hash := extensions.crypt(');
    expect(migration).not.toContain("floor(random() * 1000000)");
  });

  it('ne valide que le dernier OTP actif de la cible authentifiée', () => {
    const start = migration.indexOf(
      'CREATE OR REPLACE FUNCTION public.fn_verifier_otp_telephone',
    );
    const end = migration.indexOf(
      '-- Conserve les garanties',
      start,
    );
    const verification = migration.slice(start, end);

    expect(start).toBeGreaterThan(0);
    expect(verification).toContain('WHERE user_id = v_uid');
    expect(verification).toContain('AND utilise IS FALSE');
    expect(verification).toContain('AND expire_le > now()');
    expect(verification).toContain('LIMIT 1');
    expect(verification).toContain('FOR UPDATE');
    expect(verification).toContain('extensions.crypt(p_code, v_otp.code_hash)');
    expect(verification).toContain('public.mon_etablissement_id() IS DISTINCT FROM v_cible_id');
  });

  it('expurge le code après succès, expiration ou échec terminal', () => {
    expect(migration.match(/payload #- '\{data,code\}'/g)?.length).toBeGreaterThanOrEqual(3);
    expect(migration).toContain("ea.payload #>> '{data,code}' IS NOT NULL");
    expect(migration).toContain("WHEN v_new_statut = 'ERROR' AND v_action.type_action = 'SMS_NOTIF'");
    expect(migration).toContain("WHEN v_action.type_action = 'SMS_NOTIF' THEN jsonb_set(");
  });

  it('le worker relit la source OTP et exige un vrai succès fournisseur', () => {
    const start = worker.indexOf('async function dispatchSmsOtp');
    const end = worker.indexOf('async function dispatchPush', start);
    const dispatcher = worker.slice(start, end);

    expect(start).toBeGreaterThan(0);
    expect(dispatcher).toContain('.from("otps_telephone")');
    expect(dispatcher).toContain('otp.telephone !== telephone');
    expect(dispatcher).toContain('otp.utilise || Date.parse(otp.expire_le) <= Date.now()');
    expect(dispatcher).toContain('res.ok && responseBody?.success === true');
    expect(dispatcher).not.toContain('if (res.ok) return');
  });

  it('un OTP demandé contourne seulement les préférences facultatives et reste masqué en journal', () => {
    expect(sendSms).toContain("type !== 'OTP_VERIFICATION_TELEPHONE'");
    expect(sendSms).toContain("type === 'OTP_VERIFICATION_TELEPHONE'");
    expect(sendSms).toContain('[CODE OTP MASQUÉ]');
    expect(sendSms).not.toContain('contenu: fullBody,');
  });
});

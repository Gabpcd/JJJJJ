import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(
  'supabase/migrations/20260714064000_securiser_otp_telephone.sql',
  'utf8',
);
const worker = readFileSync('supabase/functions/process-externalisation-actions/index.ts', 'utf8');
const sms = readFileSync('supabase/functions/send-sms/index.ts', 'utf8');

describe('OTP téléphone sécurisé de bout en bout', () => {
  it('génère six chiffres avec un CSPRNG et rejet sans biais', () => {
    const generator = migration.match(
      /CREATE OR REPLACE FUNCTION public\.fn_generer_code_otp_6_chiffres[\s\S]*?\$function\$;/,
    )?.[0] ?? '';
    expect(generator).toContain('extensions.gen_random_bytes(4)');
    expect(generator).toContain('v_value < 4294000000');
    expect(generator).toContain('v_value % 1000000');
    expect(generator).not.toMatch(/\brandom\s*\(/i);
  });

  it('fige exactement une cible et limite les tentatives et envois', () => {
    expect(migration).toContain('cible_type text');
    expect(migration).toContain('cible_id uuid');
    expect(migration).toContain("cible_type IN ('SOIGNANT', 'ETABLISSEMENT')");
    expect(migration).toContain("v_cible_type := 'SOIGNANT'");
    expect(migration).toContain("v_cible_type := 'ETABLISSEMENT'");
    expect(migration).toContain('v_count_24h >= 3');
    expect(migration).toContain('v_otp.tentatives >= 5');
    expect(migration).toContain("extensions.gen_salt('bf', 10)");
  });

  it('met réellement le SMS en file et vérifie la source OTP avant l’envoi', () => {
    expect(migration).toContain("'SMS_NOTIF'");
    expect(worker).toContain('case "SMS_NOTIF"');
    expect(worker).toContain('dispatchSmsOtp(admin, action)');
    expect(worker).toContain('.from("otps_telephone")');
    expect(worker).toContain('otp.telephone !== telephone');
    expect(worker).toContain('otp.utilise || Date.parse(otp.expire_le) <= Date.now()');
  });

  it('expurge le code en clair après succès, erreur terminale, vérification ou expiration', () => {
    expect(migration.match(/payload #- '\{data,code\}'/g)?.length).toBeGreaterThanOrEqual(4);
    expect(migration).toContain("'{data,code_purge}'");
    expect(migration).toContain("v_new_statut = 'ERROR' AND v_action.type_action = 'SMS_NOTIF'");
  });

  it('ne journalise jamais le code OTP dans sms_envoyes', () => {
    expect(sms).toContain("type === 'OTP_VERIFICATION_TELEPHONE'");
    expect(sms).toContain('[CODE OTP MASQUÉ]');
    expect(sms).toContain('contenu: contenuJournal');
  });
});

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const webhook = readFileSync('supabase/functions/swan-webhook/index.ts', 'utf8');
const migration = readFileSync(
  'supabase/migrations/20260714061000_durcir_webhook_swan_fail_closed.sql',
  'utf8',
);
const signer = readFileSync('supabase/functions/_shared/swan-sign-s2s.ts', 'utf8');
const client = readFileSync('supabase/functions/_shared/swan-client.ts', 'utf8');

describe('Swan fail-closed launch boundary', () => {
  it('uses the official shared-secret header and canonical API lookup', () => {
    expect(webhook).toContain('x-swan-secret');
    expect(webhook).toContain('SWAN_WEBHOOK_SECRET');
    expect(webhook).toContain('transaction(id: $id)');
    expect(webhook).not.toContain('x-swan-signature');
    expect(webhook).not.toContain('createHmac');
  });

  it('does not infer a paid business state from an unbound transaction', () => {
    expect(webhook).toContain('fn_swan_webhook_reclamer');
    expect(webhook).toContain('fn_swan_webhook_finaliser');
    expect(webhook).toContain('await finalize("IGNORE", snapshot)');
    expect(webhook).not.toMatch(/from\(["']parrainages["']\)/);
    expect(webhook).not.toMatch(/from\(["']factures_honoraires["']\)/);
    expect(webhook).not.toContain('PRIME_VERSEE');
    expect(webhook).not.toContain('REMBOURSE');
  });

  it('persists idempotency without exposing the journal to app users', () => {
    expect(migration).toContain('event_id text PRIMARY KEY');
    expect(migration).toContain('resource_id text NOT NULL');
    expect(migration).toContain("event_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$'");
    expect(migration).toContain("statut IN ('RECU', 'PROCESSING', 'TRAITE', 'IGNORE', 'ERREUR')");
    expect(migration).toContain('FORCE ROW LEVEL SECURITY');
    expect(migration).toContain('REVOKE ALL ON TABLE public.swan_webhook_events FROM PUBLIC, anon, authenticated');
  });

  it('ne confirme jamais un lease non terminal et borne tout appel réseau', () => {
    expect(webhook).toMatch(/if \(claim\.claim === "DEJA_TRAITE"\)[\s\S]*?duplicate: true/);
    expect(webhook).toMatch(/if \(claim\.claim === "EN_COURS"\)[\s\S]*?retry: true[\s\S]*?503/);
    expect(webhook).not.toContain('claim.claim === "DEJA_TRAITE" || claim.claim === "EN_COURS"');
    expect(webhook).toContain('AbortSignal.timeout(6_000)');
    expect(client).toContain('signal: options?.signal ?? AbortSignal.timeout(2_500)');
    expect(client).toContain('getSwanAccessToken({ signal: options?.signal })');
  });

  it('signs the consent challenge as an ES256 JWT', () => {
    expect(signer).toContain('JSON.stringify({ alg: "ES256", typ: "JWT" })');
    expect(signer).toContain('JSON.stringify({ challenge })');
    expect(signer).toContain('`${signingInput}.${base64Url(bytes)}`');
  });
});

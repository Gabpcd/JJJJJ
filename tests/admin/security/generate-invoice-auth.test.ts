// @vitest-environment node
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

const transpile = (path: string) => ts.transpileModule(readFileSync(path, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const invoiceSource = transpile('supabase/functions/generate-invoice/index.ts');
const authSource = transpile('supabase/functions/_shared/cron-service-auth.ts');
const MISSION = '00000000-0000-4000-8000-000000000001';
const USER = '00000000-0000-4000-8000-000000000002';
const ESTABLISSEMENT = '00000000-0000-4000-8000-000000000003';
const LEGACY = 'unit-configured-legacy-service';
const SECRET = 'sb_secret_unit_configured_never_real';
const JWT = 'unit-auth-server-validated-user';
const body = { mission_id: MISSION, service_role_reason: 'ops_test_auth_closed_fixture' };

type Options = {
  env?: Record<string, string>;
  vaultSecret?: string;
  mission?: Record<string, unknown>;
  permission?: boolean;
};

/** Run the actual handler AND shared auth helper, with all IO closed. */
function simulation(options: Options = {}) {
  const env: Record<string, string> = {
    SUPABASE_URL: 'https://unit.invalid', SUPABASE_SERVICE_ROLE_KEY: LEGACY,
    SUPABASE_ANON_KEY: 'unit-anon-key', ...options.env,
  };
  const reads: string[] = [], userTokens: string[] = [], permissionCalls: unknown[] = [];
  const clientOptions: unknown[] = [];
  const admin = {
    rpc: async (name: string) => {
      if (!['fn_lire_secret_cron', 'fn_lire_secret_cron_automations'].includes(name)) {
        throw new Error('Unexpected RPC: ' + name);
      }
      return { data: name === 'fn_lire_secret_cron' ? options.vaultSecret ?? null : null, error: null };
    },
    from: (table: string) => {
      if (table !== 'missions') throw new Error('Unexpected business table: ' + table);
      reads.push(table);
      return {
        select() { return this; },
        eq(column: string, value: unknown) {
          if (column !== 'id' || value !== MISSION) throw new Error('Unexpected mission filter');
          return this;
        },
        async single() { return { data: options.mission ?? null, error: null }; },
      };
    },
  };
  const userClient = {
    auth: { getUser: async (token: string) => {
      userTokens.push(token);
      // Only the simulated Auth server decides. No claim decoding is accepted.
      return token === JWT
        ? { data: { user: { id: USER } }, error: null }
        : { data: { user: null }, error: { message: 'Invalid user token' } };
    } },
    rpc: async (name: string, args: unknown) => {
      if (name !== 'fn_a_permission_etablissement') throw new Error('Unexpected user RPC');
      permissionCalls.push(args);
      return { data: options.permission === true, error: null };
    },
  };
  const base = {
    Deno: { env: { get: (name: string) => env[name] } },
    Date, Request, Response, TextEncoder, crypto: webcrypto,
    console: { log() {}, warn() {}, error() {} },
    fetch() { throw new Error('Network forbidden in auth fixture'); },
  };
  const authExports: Record<string, unknown> = {};
  runInNewContext(authSource, { ...base, exports: authExports });
  let handler!: (request: Request) => Promise<Response>;
  class SimulatedFontError extends Error {}
  const modules: Record<string, unknown> = {
    'npm:@supabase/supabase-js@2.99.2': { createClient: (_url: string, key: string, opts: unknown) => {
      if (key === env.SUPABASE_ANON_KEY) { clientOptions.push(opts); return userClient; }
      if (key !== env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Unexpected SDK key');
      return admin;
    } },
    'npm:pdf-lib@1.17.1': {
      PDFDocument: { create() { throw new Error('PDF rendering forbidden in auth fixture'); } },
      rgb() { throw new Error('PDF rendering forbidden in auth fixture'); }, degrees() { return 0; },
    },
    './fonts.ts': { ErreurPoliceFacture: SimulatedFontError },
    '../_shared/cors.ts': { corsHeaders: () => ({}) },
    '../_shared/rate-limit.ts': { applyRateLimit: () => false, getClientIp: () => 'unit-ip' },
    '../_shared/cron-service-auth.ts': authExports,
  };
  runInNewContext(invoiceSource, {
    ...base, exports: {}, Deno: { ...base.Deno, serve: (fn: typeof handler) => { handler = fn; } },
    require: (name: string) => {
      if (!(name in modules)) throw new Error('Unexpected import: ' + name);
      return modules[name];
    },
  });
  return { reads, userTokens, permissionCalls, clientOptions,
    async call(headers: Record<string, string>, payload: Record<string, unknown> = body) {
      const response = await handler(new Request('https://unit.invalid/generate-invoice', {
        method: 'POST', headers, body: JSON.stringify(payload),
      }));
      return { status: response.status, data: await response.json() };
    },
  };
}

const openMission = {
  id: MISSION, statut: 'OUVERTE', etablissement_id: ESTABLISSEMENT,
  soignant_assigne_id: 'another-user', type_contrat_applique: 'LIBERAL',
};

describe('generate-invoice: real auth gates with closed IO', () => {
  it('accepts a configured legacy service bearer without asking Auth for a user', async () => {
    const s = simulation();
    expect(await s.call({ Authorization: 'Bearer ' + LEGACY })).toEqual({ status: 404, data: { error: 'Mission introuvable' } });
    expect(s.reads).toEqual(['missions']); expect(s.userTokens).toEqual([]);
  });
  it.each(['SUPABASE_SECRET_KEY', 'SB_SECRET_KEY'])('accepts a configured %s via apikey without a user bearer', async name => {
    const s = simulation({ env: { [name]: SECRET } });
    expect(await s.call({ apikey: SECRET })).toEqual({ status: 404, data: { error: 'Mission introuvable' } });
    expect(s.userTokens).toEqual([]); expect(s.reads).toEqual(['missions']);
  });
  it('accepts a named configured secret and the configured Vault secret independently of a different env key', async () => {
    for (const options of [
      { env: { SUPABASE_SECRET_KEYS: JSON.stringify({ default: SECRET }) } },
      { vaultSecret: SECRET },
    ]) {
      const s = simulation(options);
      expect((await s.call({ apikey: SECRET })).status).toBe(404);
      expect(s.userTokens).toEqual([]); expect(s.reads).toEqual(['missions']);
    }
  });
  it.each([
    { Authorization: 'Bearer ' + LEGACY },
    { apikey: SECRET },
  ])('requires the service reason before business reads', async headers => {
    const s = simulation({ env: { SUPABASE_SECRET_KEY: SECRET } });
    expect(await s.call(headers, { mission_id: MISSION })).toEqual({ status: 400, data: { error: 'service_role_reason requis pour les appels service_role' } });
    expect(s.reads).toEqual([]); expect(s.userTokens).toEqual([]);
  });
  it('rejects a nonallowlisted service reason and preserves the 10-per-minute service limit', async () => {
    const invalid = simulation();
    const denied = await invalid.call({ Authorization: 'Bearer ' + LEGACY }, { ...body, service_role_reason: 'forged' });
    expect(denied.status).toBe(403); expect(denied.data.error).toContain('service_role_invalid_reason');
    expect(invalid.reads).toEqual([]);
    const limited = simulation();
    for (let i = 0; i < 10; i++) expect((await limited.call({ apikey: LEGACY })).status).toBe(404);
    expect((await limited.call({ apikey: LEGACY })).status).toBe(429);
    expect(limited.reads).toHaveLength(10); expect(limited.userTokens).toEqual([]);
  });
  it('does not turn a valid user JWT into a service caller and keeps the tenant RPC mandatory', async () => {
    const s = simulation({ mission: openMission });
    expect(await s.call({ Authorization: 'Bearer ' + JWT }, { mission_id: MISSION })).toEqual({ status: 403, data: { error: 'Accès refusé à cette mission' } });
    expect(s.userTokens).toEqual([JWT]);
    expect(s.permissionCalls).toEqual([{ p_permission: 'paiement', p_etablissement_id: ESTABLISSEMENT }]);
    expect(s.clientOptions).toEqual([{ global: { headers: { Authorization: 'Bearer ' + JWT } } }]);
  });
  it('preserves establishment permission and assigned-soignant access, then applies business rules', async () => {
    for (const options of [
      { mission: openMission, permission: true },
      { mission: { ...openMission, soignant_assigne_id: USER } },
    ]) {
      const s = simulation(options);
      const result = await s.call({ Authorization: 'Bearer ' + JWT }, { mission_id: MISSION });
      expect(result.status).toBe(400); expect(result.data.error).toContain('doit être TERMINEE');
      expect(s.userTokens).toEqual([JWT]); expect(s.permissionCalls).toHaveLength(1);
    }
  });
  it.each([
    {}, { apikey: 'sb_secret_unit_forged_never_real' },
    { apikey: 'unit-anon-key' }, { Authorization: 'Bearer invalid-user-token' },
    { Authorization: 'Bearer eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.forged' },
  ])('refuses missing/forged keys and forged service claims before business reads', async headers => {
    const s = simulation({ env: { SUPABASE_SECRET_KEY: SECRET } });
    expect((await s.call(headers)).status).toBe(401); expect(s.reads).toEqual([]);
  });
  it('still verifies the user JWT when a different unconfigured API key is presented', async () => {
    const s = simulation({ mission: openMission });
    expect((await s.call({ Authorization: 'Bearer ' + JWT, apikey: 'sb_secret_unit_forged' })).status).toBe(403);
    expect(s.userTokens).toEqual([JWT]); expect(s.permissionCalls).toHaveLength(1);
  });
  it('does not accept an old unconfigured legacy API key merely because its payload is service_role', async () => {
    const s = simulation({ env: { SUPABASE_SERVICE_ROLE_KEY: 'unit-other-configured-service' } });
    expect(await s.call({ Authorization: 'Bearer ' + LEGACY, apikey: LEGACY })).toEqual({ status: 401, data: { error: 'Token invalide' } });
    expect(s.userTokens).toEqual([LEGACY]); expect(s.reads).toEqual([]);
  });
});

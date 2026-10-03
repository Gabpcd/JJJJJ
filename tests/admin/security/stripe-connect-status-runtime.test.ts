import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

type Row = Record<string, any>;
const userId = '69000000-0000-4000-8000-000000000071';
const accountId = 'acct_simulation';
const complete = { id: accountId, charges_enabled: true, payouts_enabled: true, details_submitted: true };
function simulation() {
  const state = {
    row: { id: 'onboarding', soignant_id: userId, stripe_account_id: accountId, statut: 'COMPLET',
      ...complete, onboarding_complete: false, modifie_le: new Date().toISOString() } as Row,
    account: { ...complete } as Row, writes: [] as Row[], filters: [] as [string, unknown][],
    isTest: false, classificationError: false, rpcs: [] as string[], errors: [] as unknown[][],
    loadedHelpers: [] as string[],
    reads: 0, deleted: false, writeError: false, missingRow: false, events: [] as Row[], processed: false,
  };
  const sb = { from(table: string) {
    if (!['stripe_connect_onboarding', 'stripe_webhook_events', 'etablissements'].includes(table)) throw new Error(`Table imprévue ${table}`);
    let patch: Row | undefined;
    const result = () => {
      if (table === 'etablissements') {
        if (patch) throw new Error('Mutation établissement interdite dans ce harnais');
        return { data: { id: userId }, error: null };
      }
      if (table === 'stripe_webhook_events') {
        if (patch) { state.events.push(patch); if (patch.traite_le) state.processed = true; }
        return { data: { event_id: 'evt_simulation' }, error: null };
      }
      if (patch) {
        state.writes.push(patch);
        if (state.writeError) return { data: null, error: { message: '503 persistence' } };
        if (state.missingRow) return { data: null, error: null };
        Object.assign(state.row, patch);
      }
      return { data: state.row, error: null };
    };
    const q = { select() { return q; }, update(p: Row) { patch = p; return q; },
      eq(k: string, v: unknown) { state.filters.push([k, v]); return q; }, is() { return q; },
      maybeSingle: async () => result(), then(resolve: any, reject: any) { return Promise.resolve(result()).then(resolve, reject); } };
    return q;
  }, rpc: async (name: string) => {
    state.rpcs.push(name);
    if (name === 'fn_stripe_webhook_event_claim') return { data: state.processed ? 'PROCESSED' : 'CLAIMED', error: null };
    if (name === 'fn_ecrire_audit_safe') return { data: { success: true }, error: null };
    throw new Error(`RPC imprévue ${name}`);
  } };
  let event: Row = { id: 'evt_simulation', type: 'account.updated',
    livemode: false, account: accountId, data: { object: { ...complete } } };
  class StripeStub {
    accounts = { retrieve: async () => {
      state.reads++;
      if (state.deleted) throw Object.assign(new Error('deleted'), { code: 'resource_missing' });
      return state.account;
    } };
    webhooks = { constructEventAsync: async (_body: string, _signature: string, secret: string) => {
      if (secret !== (event.account ? 'whsec_simulation' : 'whsec_platform_simulation')) throw new Error('Autre source');
      return event;
    } };
  }
  const env: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'simulation',
    STRIPE_SECRET_KEY: 'sk_test_simulation', STRIPE_CONNECT_WEBHOOK_SECRET: 'whsec_simulation',
    STRIPE_PLATFORM_WEBHOOK_SECRET: 'whsec_platform_simulation' };
  const modules: Record<string, unknown> = {
    'npm:stripe@20.4.1': { default: StripeStub },
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => sb },
    'npm:@supabase/supabase-js@2': { createClient: () => sb },
    'stripe-production.ts': { assertStripeSecretMode() {}, isProductionRuntime: () => false },
    'admin-auth.ts': { verifyUserOrServiceRole: async () => ({ ok: true, userId, isServiceRole: false }) },
    'stripe-errors.ts': { mapStripeError: () => ({ code: 'UNAVAILABLE', status: 503, logLevel: 'error', userMessage: 'Indisponible' }) },
    'cors.ts': { jsonResponse: (_: unknown, body: unknown, status = 200) => new Response(JSON.stringify(body), { status }) },
    'test-account.ts': { resolveOperationalTestAccount: async () => state.classificationError
      ? { ok: false, error: 'Classification indisponible' } : { ok: true, isTest: state.isTest } },
  };
  function load(file: string) {
    const output = ts.transpileModule(readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText;
    let handler!: (r: Request) => Promise<Response>;
    const exports: Row = {};
    runInNewContext(output, { exports, Request, Response, URL, Date, Error,
      require: (name: string) => {
        const basename = name.split('/').at(-1)!;
        // Exécuter les protections réellement importées par le webhook, avec le
        // même environnement que le handler ; ne pas simuler une admission réussie.
        if (['stripe-connect-staging-test.ts', 'financial-audit.ts'].includes(basename)) {
          state.loadedHelpers.push(basename);
          return load(resolve(dirname(file), name)).exports;
        }
        return modules[name] ?? modules[basename] ?? new Proxy({}, {
          get: (_, key) => { throw new Error(`Dépendance imprévue ${name}.${String(key)}`); },
        });
      },
      Deno: { env: { get: (key: string) => env[key] }, serve: (h: typeof handler) => { handler = h; } },
      console: { log() {}, info() {}, warn() {}, error(...args: unknown[]) { state.errors.push(args); } },
      fetch: () => { throw new Error('Réseau interdit'); },
    });
    return { handler, exports };
  }
  const status = load('supabase/functions/stripe-connect-status/index.ts').handler;
  const webhook = load('supabase/functions/_shared/stripe-webhook-handler.ts').exports.handleStripeWebhook;
  return { state, env, setEvent: (next: Row) => { event = next; }, status: (force = false) => status(new Request(`https://example.invalid/status${force ? '?force=true' : ''}`, { method: 'POST' })),
    webhook: (source: 'CONNECT' | 'PLATFORM' = 'CONNECT') => webhook(new Request('https://example.invalid/webhook', { method: 'POST', headers: { 'stripe-signature': 'simulation' }, body: '{}' }), source) as Promise<Response> };
}

describe('Connect : vrais handlers, persistance et réponse concordantes', () => {
  it('répare un cache incohérent après relecture Stripe, puis utilise le cache cohérent', async () => {
    const s = simulation(); const r = await s.status();
    expect(r.status).toBe(200); expect(await r.json()).toMatchObject({ statut: 'COMPLET', onboarding_complete: true, cached: false });
    expect(s.state.row.onboarding_complete).toBe(true); expect(s.state.reads).toBe(1);
    expect(s.state.filters).toContainEqual(['stripe_account_id', accountId]);
    expect(await (await s.status()).json()).toMatchObject({ onboarding_complete: true, cached: true });
    expect(s.state.reads).toBe(1); expect(s.state.writes).toHaveLength(1);
  });
  for (const flag of ['charges_enabled', 'payouts_enabled', 'details_submitted']) {
    it(`retire la complétude si Stripe retire ${flag}`, async () => {
      const s = simulation(); s.state.row.onboarding_complete = true; s.state.account[flag] = false;
      expect(await (await s.status(true)).json()).toMatchObject({ statut: 'EN_COURS', onboarding_complete: false });
      expect(s.state.row.onboarding_complete).toBe(false);
    });
  }
  it('retire tous les indicateurs après suppression du compte', async () => {
    const s = simulation(); s.state.deleted = true;
    expect(await (await s.status(true)).json()).toMatchObject({ statut: 'SUPPRIME', onboarding_complete: false });
    expect(s.state.row).toMatchObject({ statut: 'SUPPRIME', onboarding_complete: false, charges_enabled: false, payouts_enabled: false, details_submitted: false });
  });
  it.each(['writeError', 'missingRow'] as const)('ne confirme pas un statut non persisté : %s', async failure => {
    const s = simulation(); s.state[failure] = true;
    const r = await s.status(true); expect(r.status).toBe(503);
    expect(await r.json()).toMatchObject({ error: 'STRIPE_STATUS_UNAVAILABLE' });
    expect(s.state.row.onboarding_complete).toBe(false);
  });
  it('le webhook synchronise aussi la complétude et reste idempotent', async () => {
    const s = simulation(); expect((await s.webhook()).status).toBe(200);
    expect(s.state.row.onboarding_complete).toBe(true); expect(s.state.processed).toBe(true);
    expect((await s.webhook()).status).toBe(200); expect(s.state.writes).toHaveLength(1);
  });
  it('un ancien événement complet relit Stripe et ne réactive pas un compte depuis suspendu', async () => {
    const s = simulation(); s.state.row.onboarding_complete = true;
    s.state.account.payouts_enabled = false; s.state.account.requirements = { disabled_reason: 'requirements.past_due' };
    expect((await s.webhook()).status).toBe(200);
    expect(s.state.reads).toBe(1);
    expect(s.state.row).toMatchObject({ statut: 'SUSPENDU', onboarding_complete: false });
  });
  it('un échec de persistance webhook reste rejouable, sans faux acquittement', async () => {
    const s = simulation(); s.state.writeError = true;
    expect((await s.webhook()).status).toBe(500); expect(s.state.processed).toBe(false);
    s.state.writeError = false;
    expect((await s.webhook()).status).toBe(200); expect(s.state.processed).toBe(true);
    expect(s.state.row.onboarding_complete).toBe(true);
  });
});

describe('Webhooks TEST : aucun effet métier sans admission de recette', () => {
  for (const source of ['CONNECT', 'PLATFORM'] as const) {
    const setup = () => {
      const s = simulation();
      s.state.isTest = true;
      if (source === 'PLATFORM') s.setEvent({
        id: 'evt_simulation', type: 'checkout.session.completed', livemode: false,
        data: { object: { id: 'cs_test_simulation', customer: 'cus_simulation', metadata: { type: 'INVOICE_PAYMENT' } } },
      });
      return s;
    };
    it(`${source} : sans configuration, acquitte une fois sans relire Stripe ni muter le métier`, async () => {
      const s = setup();
      const result = await s.webhook(source);
      expect(result.status, JSON.stringify(s.state.errors)).toBe(200);
      expect(await result.json()).toEqual({ received: true, test_skipped: true });
      expect(s.state.loadedHelpers).toContain('stripe-connect-staging-test.ts');
      expect(s.state.loadedHelpers).toContain('financial-audit.ts');
      expect(s.state.rpcs).toEqual(['fn_stripe_webhook_event_claim', 'fn_ecrire_audit_safe']);
      expect(s.state.reads).toBe(0);
      expect(s.state.writes).toEqual([]);
      expect(s.state.row.onboarding_complete).toBe(false);
      expect(s.state.processed).toBe(true);
      expect(await (await s.webhook(source)).json()).toMatchObject({ skipped: 'already_processed' });
      expect(s.state.events).toHaveLength(1);
      expect(s.state.rpcs.filter(name => name === 'fn_ecrire_audit_safe')).toHaveLength(1);
    });
    it(`${source} : refuse une configuration TEST sur un autre projet avant le claim`, async () => {
      const s = setup();
      s.env.SUPABASE_ENV = 'staging';
      s.env.CONNECT_STAGING_TEST_RUN = JSON.stringify({
        serverSha: 'a'.repeat(40), uiSha: 'b'.repeat(40), manifestSha256: 'c'.repeat(64),
        platformAccountId: 'acct_simulation', capabilityId: '69000000-0000-4000-8000-000000000081',
        returnOrigin: 'http://127.0.0.1:8830',
      });
      const result = await s.webhook(source);
      expect(result.status).toBe(500);
      expect(JSON.stringify(s.state.errors)).toContain('CONNECT_STAGING_TEST_REFUSED');
      expect(s.state.rpcs).toEqual([]);
      expect(s.state.events).toEqual([]);
      expect(s.state.writes).toEqual([]);
      expect(s.state.reads).toBe(0);
    });
    it(`${source} : ne traite jamais une classification indisponible comme un compte réel`, async () => {
      const s = setup(); s.state.classificationError = true;
      expect((await s.webhook(source)).status).toBe(500);
      expect(JSON.stringify(s.state.errors)).toContain('Classification indisponible');
      expect(s.state.rpcs).toEqual([]);
      expect(s.state.events).toEqual([]);
      expect(s.state.writes).toEqual([]);
      expect(s.state.reads).toBe(0);
    });
  }
});

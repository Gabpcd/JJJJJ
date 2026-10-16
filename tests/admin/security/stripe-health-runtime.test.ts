import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

// Vrai handler, fournisseurs simulés et accès réseau interdits.
function simulation() {
  const state = { enabled: true, gateError: false, missingEvent: '', auth: true, calls: [] as string[] };
  let handler!: (r: Request) => Promise<Response>;
  const sb = {
    rpc: async (name: string) => {
      expect(name).toBe('fn_diagnostic_disponibilite_connect');
      state.calls.push(name);
      return state.gateError ? { error: { message: 'unavailable' }, data: null }
        : { error: null, data: { protocol: 'CONNECT_PRETRANSFER_V1', enabled: state.enabled } };
    },
    from: (table: string) => {
      expect(table).toBe('etablissements');
      const q = { select: () => q, is: () => q, not: () => q, order: () => q,
        range: async () => ({ data: [], error: null }) };
      return q;
    },
  };
  const platform = ['charge.dispute.closed', 'charge.dispute.created', 'charge.expired', 'charge.failed',
    'charge.pending', 'charge.refunded', 'charge.succeeded', 'checkout.session.expired', 'checkout.session.completed',
    'invoice.payment_failed', 'payment_intent.payment_failed', 'payment_intent.succeeded', 'refund.updated',
    'refund.failed', 'transfer.created', 'transfer.reversed', 'transfer.updated'];
  const modules: Record<string, unknown> = {
    '../_shared/cors.ts': { corsHeaders: () => ({ 'Content-Type': 'application/json' }) },
    '../_shared/admin-auth.ts': { verifyAdminOrServiceRole: async () => state.auth
      ? { ok: true } : { ok: false, status: 403, error: 'Accès refusé' } },
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => sb },
  };
  const env: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'simulation',
    STRIPE_SECRET_KEY: 'simulation', STRIPE_PLATFORM_WEBHOOK_SECRET: 'platform-fixture', STRIPE_CONNECT_WEBHOOK_SECRET: 'connect-fixture' };
  const source = ts.transpileModule(readFileSync('supabase/functions/stripe-config-health/index.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  runInNewContext(source, { exports: {}, Request, Response, AbortController, setTimeout, clearTimeout,
    console: { error() {} },
    require: (name: string) => { if (!(name in modules)) throw new Error(`Import imprévu ${name}`); return modules[name]; },
    Deno: { env: { get: (key: string) => env[key] }, serve: (h: typeof handler) => { handler = h; } },
    fetch: async (url: string, options: { method: string }) => {
      expect(options.method).toBe('GET'); state.calls.push(url);
      if (url === 'https://api.stripe.com/v1/balance') return Response.json({ object: 'balance', livemode: true });
      if (url === 'https://api.stripe.com/v1/webhook_endpoints?limit=100') return Response.json({ data: [
        { url: `${env.SUPABASE_URL}/functions/v1/stripe-webhook`, livemode: true, status: 'enabled', api_version: '2026-02-25.clover', enabled_events: platform.filter(e => e !== state.missingEvent) },
        { url: `${env.SUPABASE_URL}/functions/v1/stripe-connect-webhook`, livemode: true, status: 'enabled', api_version: '2026-02-25.clover', enabled_events: ['account.updated', 'payout.canceled', 'payout.created', 'payout.failed', 'payout.paid'] },
      ] });
      throw new Error(`Réseau imprévu ${url}`);
    },
  });
  return { state, run: () => handler(new Request('https://example.invalid/health', { method: 'POST' })) };
}

describe('Stripe health : disponibilité réelle du protocole', () => {
  it('refuse tout diagnostic sans autorisation, sans requête fournisseur', async () => {
    const s = simulation(); s.state.auth = false;
    expect((await s.run()).status).toBe(403); expect(s.state.calls).toEqual([]);
  });
  it('reste indisponible quand la clé et les webhooks sont bons mais Connect fermé', async () => {
    const s = simulation(); s.state.enabled = false; const r = await s.run();
    expect(r.status).toBe(503); expect(await r.json()).toMatchObject({ authenticated: true, webhook_events_complete: true,
      connect_release_checked: true, connect_release_open: false, production_ready: false,
      error: 'Paiement groupé libéral indisponible : ouverture Connect non effectuée.' });
  });
  it('ne présente pas une lecture échouée comme une ouverture', async () => {
    const s = simulation(); s.state.gateError = true; const r = await s.run();
    expect(r.status).toBe(503); expect(await r.json()).toMatchObject({ connect_release_checked: false, production_ready: false });
  });
  for (const event of ['refund.updated', 'refund.failed']) it(`exige ${event}`, async () => {
    const s = simulation(); s.state.missingEvent = event; const r = await s.run();
    expect(r.status).toBe(503); expect(await r.json()).toMatchObject({ platform_webhook_events_complete: false, production_ready: false });
  });
  it('devient prêt uniquement avec protocole ouvert et configuration complète', async () => {
    const s = simulation(); const r = await s.run(); expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ connect_release_checked: true, connect_release_open: true, production_ready: true });
  });
});

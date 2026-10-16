import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

// Vrai handler et vrai contrôle d'authentification ; fournisseurs simulés,
// sans accès réseau. Le mode Stripe est attesté par la réponse balance.
function simulation() {
  const state = { enabled: true, gateError: false, missingEvent: '', live: true, invalidKey: false,
    badVersion: false, missingConnect: false, customerError: false, linkedCustomer: true,
    customer: false, bearer: 'service-fixture', calls: [] as string[], authCalls: [] as string[] };
  let handler!: (r: Request) => Promise<Response>;
  const sb = {
    auth: { getUser: async (token: string) => {
      state.authCalls.push(token);
      return token === 'non-admin-fixture'
        ? { error: null, data: { user: { id: 'non-admin', app_metadata: { role: 'SOIGNANT' } } } }
        : { error: { message: 'invalid' }, data: { user: null } };
    } },
    rpc: async (name: string) => {
      expect(name).toBe('fn_diagnostic_disponibilite_connect');
      state.calls.push(name);
      return state.gateError ? { error: { message: 'unavailable' }, data: null }
        : { error: null, data: { protocol: 'CONNECT_PRETRANSFER_V1', enabled: state.enabled } };
    },
    from: (table: string) => {
      expect(table).toBe('etablissements');
      const q = { select: () => q, is: () => q, not: () => q, order: () => q,
        range: async () => state.customerError ? { data: null, error: { message: 'unavailable' } }
          : { data: state.customer ? [{ id: 'tenant-fixture', nom: 'Fixture', email_contact: null,
            stripe_customer_id: 'cus_fixture' }] : [], error: null } };
      return q;
    },
  };
  const platform = ['charge.dispute.closed', 'charge.dispute.created', 'charge.expired', 'charge.failed',
    'charge.pending', 'charge.refunded', 'charge.succeeded', 'checkout.session.expired', 'checkout.session.completed',
    'invoice.payment_failed', 'payment_intent.payment_failed', 'payment_intent.succeeded', 'refund.updated',
    'refund.failed', 'transfer.created', 'transfer.reversed', 'transfer.updated'];
  const modules: Record<string, unknown> = {
    '../_shared/cors.ts': { corsHeaders: () => ({ 'Content-Type': 'application/json' }) },
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => sb },
  };
  const env: Record<string, string> = { SUPABASE_URL: 'https://example.invalid', SUPABASE_ANON_KEY: 'anon-fixture',
    SUPABASE_SERVICE_ROLE_KEY: 'service-fixture', STRIPE_SECRET_KEY: 'stripe-fixture',
    STRIPE_PLATFORM_WEBHOOK_SECRET: 'platform-fixture', STRIPE_CONNECT_WEBHOOK_SECRET: 'connect-fixture' };
  const context = { Request, Response, AbortController, setTimeout, clearTimeout,
    console: { error() {} },
    require: (name: string) => { if (!(name in modules)) throw new Error(`Import imprévu ${name}`); return modules[name]; },
    Deno: { env: { get: (key: string) => env[key] }, serve: (h: typeof handler) => { handler = h; } },
    fetch: async (url: string, options: { method: string }) => {
      expect(options.method).toBe('GET'); state.calls.push(url);
      if (url === 'https://api.stripe.com/v1/balance') return state.invalidKey
        ? Response.json({ error: 'invalid-key-fixture' }, { status: 401 })
        : Response.json({ object: 'balance', livemode: state.live });
      if (url === 'https://api.stripe.com/v1/webhook_endpoints?limit=100') return Response.json({ data: [
        { url: `${env.SUPABASE_URL}/functions/v1/stripe-webhook`, livemode: true, status: 'enabled', api_version: state.badVersion ? 'incorrect' : '2026-02-25.clover', enabled_events: platform.filter(e => e !== state.missingEvent) },
        ...(!state.missingConnect ? [{ url: `${env.SUPABASE_URL}/functions/v1/stripe-connect-webhook`, livemode: true, status: 'enabled', api_version: '2026-02-25.clover', enabled_events: ['account.updated', 'payout.canceled', 'payout.created', 'payout.failed', 'payout.paid'] }] : []),
      ] });
      if (url === 'https://api.stripe.com/v1/customers/cus_fixture') return Response.json({
        metadata: { etablissement_id: state.linkedCustomer ? 'tenant-fixture' : 'foreign-tenant-fixture' },
      });
      throw new Error(`Réseau imprévu ${url}`);
    },
  };
  const load = (path: string) => {
    const exports = {};
    const source = ts.transpileModule(readFileSync(path, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText;
    runInNewContext(source, { ...context, exports });
    return exports;
  };
  modules['../_shared/admin-auth.ts'] = load('supabase/functions/_shared/admin-auth.ts');
  load('supabase/functions/stripe-config-health/index.ts');
  return { state, env, run: () => handler(new Request('https://example.invalid/health', { method: 'POST',
    headers: state.bearer ? { Authorization: `Bearer ${state.bearer}` } : {} })) };
}

describe('Stripe health : disponibilité réelle du protocole', () => {
  it.each([['', 401], ['forged-fixture', 401], ['non-admin-fixture', 403]] as const)(
    'refuse le bearer %s avec %s, sans requête fournisseur', async (bearer, status) => {
      const s = simulation(); s.state.bearer = bearer;
      expect((await s.run()).status).toBe(status); expect(s.state.calls).toEqual([]);
    });
  it('autorise le vrai bypass service_role configuré sans simulation de sa décision', async () => {
    const s = simulation(); expect((await s.run()).status).toBe(200); expect(s.state.authCalls).toEqual([]);
  });
  it('reste indisponible pour le produit mais déployable quand seul Connect est fermé', async () => {
    const s = simulation(); s.state.enabled = false; const r = await s.run();
    expect(r.status).toBe(503); expect(await r.json()).toMatchObject({ authenticated: true, webhook_events_complete: true,
      connect_release_checked: true, connect_release_open: false, deployment_ready: true, production_ready: false,
      error: 'Paiement groupé libéral indisponible : ouverture Connect non effectuée.' });
  });
  it('ne présente pas une lecture échouée comme une ouverture ou un déploiement prêt', async () => {
    const s = simulation(); s.state.gateError = true; const r = await s.run();
    expect(r.status).toBe(503); expect(await r.json()).toMatchObject({ connect_release_checked: false,
      deployment_ready: false, production_ready: false });
  });
  for (const event of ['refund.updated', 'refund.failed']) it(`exige ${event} même gate fermé`, async () => {
    const s = simulation(); s.state.enabled = false; s.state.missingEvent = event; const r = await s.run();
    expect(r.status).toBe(503); expect(await r.json()).toMatchObject({ platform_webhook_events_complete: false,
      deployment_ready: false, production_ready: false,
      error: 'Configuration Stripe incomplète : vérifier les webhooks et les comptes liés.' });
  });
  it.each(['live', 'version', 'connect', 'tenant', 'tenant-read', 'signing-secret'])(
    'refuse le déploiement si le prérequis %s manque même gate fermé', async (missing) => {
      const s = simulation(); s.state.enabled = false;
      if (missing === 'live') s.state.live = false;
      if (missing === 'version') s.state.badVersion = true;
      if (missing === 'connect') s.state.missingConnect = true;
      if (missing === 'tenant') { s.state.customer = true; s.state.linkedCustomer = false; }
      if (missing === 'tenant-read') s.state.customerError = true;
      if (missing === 'signing-secret') s.env.STRIPE_CONNECT_WEBHOOK_SECRET = s.env.STRIPE_PLATFORM_WEBHOOK_SECRET;
      const r = await s.run(); expect(r.status).toBe(503);
      expect(await r.json()).toMatchObject({ deployment_ready: false, production_ready: false });
    });
  it('refuse une clé rejetée sans présenter de contrat de déploiement valide', async () => {
    const s = simulation(); s.state.invalidKey = true; const r = await s.run(); expect(r.status).toBe(502);
    expect(await r.json()).toMatchObject({ authenticated: false, livemode: false, mode: 'invalid' });
    expect(s.state.calls).toEqual(['https://api.stripe.com/v1/balance']);
  });
  it('devient prêt uniquement avec protocole ouvert et configuration complète', async () => {
    const s = simulation(); const r = await s.run(); expect(r.status).toBe(200);
    expect(await r.json()).toMatchObject({ connect_release_checked: true, connect_release_open: true,
      deployment_ready: true, production_ready: true });
  });
});

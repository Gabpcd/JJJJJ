/**
 * Diagnostic Stripe sans effet de bord et sans exposition de secret.
 * Réservé aux administrateurs AAL2 et aux appels internes service_role.
 */
import { corsHeaders } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';
import { createClient } from 'npm:@supabase/supabase-js@2.99.2';

type StripeBalance = {
  livemode?: boolean;
  object?: string;
};

type StripeWebhookEndpoint = {
  api_version?: string | null;
  enabled_events?: string[];
  livemode?: boolean;
  status?: string;
  url?: string;
};

type StripeList<T> = {
  data?: T[];
};

type StripeCustomerHealth = {
  deleted?: boolean;
  name?: string | null;
  email?: string | null;
  metadata?: Record<string, string>;
};

type CustomerLinkHealth = {
  checked: boolean;
  total: number;
  valid: number;
  adoptable_legacy: number;
  indeterminate: number;
  all_valid: boolean;
};

// Les deux endpoints webhook et les requêtes de diagnostic sont alignés sur
// la version compilée et testée par stripe-node 20.4.1.
const WEBHOOK_API_VERSION = '2026-02-25.clover';

const REQUIRED_PLATFORM_WEBHOOK_EVENTS = [
  'charge.dispute.closed',
  'charge.dispute.created',
  'charge.expired',
  'charge.failed',
  'charge.pending',
  'charge.refunded',
  'charge.succeeded',
  'checkout.session.expired',
  'checkout.session.completed',
  'invoice.payment_failed',
  'payment_intent.payment_failed',
  'payment_intent.succeeded',
  'transfer.created',
  'transfer.reversed',
  'transfer.updated',
];

const REQUIRED_CONNECT_WEBHOOK_EVENTS = [
  'account.updated',
  'payout.canceled',
  'payout.created',
  'payout.failed',
  'payout.paid',
];

function eventsComplete(endpoint: StripeWebhookEndpoint | undefined, required: string[]): boolean {
  const enabled = endpoint?.enabled_events || [];
  return enabled.includes('*') || required.every((event) => enabled.includes(event));
}

function secretState() {
  const platform = (
    Deno.env.get('STRIPE_PLATFORM_WEBHOOK_SECRET')
    || Deno.env.get('STRIPE_WEBHOOK_SECRET')
    || ''
  ).trim();
  const connect = (Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET') || '').trim();
  return {
    platformConfigured: platform.length > 0,
    connectConfigured: connect.length > 0,
    distinct: platform.length > 0 && connect.length > 0 && platform !== connect,
  };
}

function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(req) });
}

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
  timeoutMs = 8_000,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function checkCustomerTenantLinks(
  stripeSecret: string,
  supabaseBase: string,
): Promise<CustomerLinkHealth> {
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseBase || !serviceRoleKey) {
    return {
      checked: false, total: 0, valid: 0,
      adoptable_legacy: 0, indeterminate: 0, all_valid: false,
    };
  }

  const admin = createClient(supabaseBase, serviceRoleKey, {
    auth: { persistSession: false },
  });
  type EtablissementCustomerRow = {
    id: string;
    nom: string | null;
    email_contact: string | null;
    stripe_customer_id: string;
  };
  const rows: EtablissementCustomerRow[] = [];
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin
      .from('etablissements')
      .select('id, nom, email_contact, stripe_customer_id')
      .is('supprime_le', null)
      .not('stripe_customer_id', 'is', null)
      .order('id')
      .range(offset, offset + pageSize - 1);
    if (error || !data) {
      console.error('[stripe-config-health] customer link inventory failed');
      return {
        checked: false, total: rows.length, valid: 0,
        adoptable_legacy: 0, indeterminate: 0, all_valid: false,
      };
    }
    rows.push(...data as EtablissementCustomerRow[]);
    if (data.length < pageSize) break;
  }

  let valid = 0;
  let adoptableLegacy = 0;
  let indeterminate = 0;
  const batchSize = 5;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const results = await Promise.all(rows.slice(offset, offset + batchSize).map(async (row) => {
      try {
        const response = await fetchWithTimeout(
          `https://api.stripe.com/v1/customers/${encodeURIComponent(row.stripe_customer_id)}`,
          {
            method: 'GET',
            headers: {
              Authorization: `Bearer ${stripeSecret}`,
              'Stripe-Version': WEBHOOK_API_VERSION,
            },
          },
        );
        if (response.status === 404) return 'invalid' as const;
        if (!response.ok) return 'indeterminate' as const;
        const customer = await response.json() as StripeCustomerHealth;
        if (customer.deleted === true) return 'invalid' as const;
        const linkedId = customer.metadata?.etablissement_id?.trim() || null;
        if (linkedId === row.id) return 'valid' as const;
        const legalName = (row.nom || '').trim();
        const legalEmail = (row.email_contact || '').trim().toLowerCase();
        const stripeName = (customer.name || '').trim();
        const stripeEmail = (customer.email || '').trim().toLowerCase();
        if (!linkedId && legalName && legalEmail
          && stripeName === legalName && stripeEmail === legalEmail) {
          return 'adoptable' as const;
        }
        return 'invalid' as const;
      } catch {
        // Fail closed sans journaliser l'identifiant établissement/Customer.
        return 'indeterminate' as const;
      }
    }));
    for (const result of results) {
      if (result === 'valid') valid += 1;
      else if (result === 'adoptable') adoptableLegacy += 1;
      else if (result === 'indeterminate') indeterminate += 1;
    }
  }

  const checked = indeterminate === 0;
  return {
    checked,
    total: rows.length,
    valid,
    adoptable_legacy: adoptableLegacy,
    indeterminate,
    // Un Customer sans metadata tenant n'est jamais adopté automatiquement :
    // le healthcheck doit donc rester bloquant jusqu'au backfill vérifié.
    all_valid: checked && valid === rows.length,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== 'POST' && req.method !== 'GET') {
    return json(req, { error: 'Méthode non autorisée' }, 405);
  }

  const auth = await verifyAdminOrServiceRole(req);
  if (!auth.ok) return json(req, { error: auth.error }, auth.status);

  const stripeSecret = Deno.env.get('STRIPE_SECRET_KEY')?.trim() || '';
  const secrets = secretState();
  if (!stripeSecret) {
    return json(req, {
      configured: false,
      livemode: false,
      mode: 'missing',
      webhook_secret_configured: secrets.platformConfigured && secrets.connectConfigured,
      platform_webhook_secret_configured: secrets.platformConfigured,
      connect_webhook_secret_configured: secrets.connectConfigured,
      webhook_secrets_distinct: secrets.distinct,
    }, 503);
  }

  try {
    // GET /v1/balance authentifie réellement la clé sans créer ni modifier
    // aucune ressource Stripe. Le préfixe de la clé n'est donc pas notre seule
    // preuve du mode live.
    const stripeResponse = await fetchWithTimeout('https://api.stripe.com/v1/balance', {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${stripeSecret}`,
        'Stripe-Version': WEBHOOK_API_VERSION,
      },
    });

    if (!stripeResponse.ok) {
      // Ne jamais renvoyer le corps Stripe : il peut contenir des détails de
      // compte. Le statut suffit au diagnostic d'exploitation.
      console.error('[stripe-config-health] Stripe rejected configured key', stripeResponse.status);
      return json(req, {
        configured: true,
        reachable: true,
        authenticated: false,
        livemode: false,
        mode: 'invalid',
        webhook_secret_configured: secrets.platformConfigured && secrets.connectConfigured,
        platform_webhook_secret_configured: secrets.platformConfigured,
        connect_webhook_secret_configured: secrets.connectConfigured,
        webhook_secrets_distinct: secrets.distinct,
      }, 502);
    }

    const balance = await stripeResponse.json() as StripeBalance;
    const livemode = balance.object === 'balance' && balance.livemode === true;
    const supabaseBase = (Deno.env.get('SUPABASE_URL') || '').replace(/\/+$/, '');
    const expectedPlatformWebhookUrl = `${supabaseBase}/functions/v1/stripe-webhook`;
    const expectedConnectWebhookUrl = `${supabaseBase}/functions/v1/stripe-connect-webhook`;
    let platformEndpoint: StripeWebhookEndpoint | undefined;
    let connectEndpoint: StripeWebhookEndpoint | undefined;

    if (livemode && expectedPlatformWebhookUrl.startsWith('https://')) {
      const endpointsResponse = await fetchWithTimeout('https://api.stripe.com/v1/webhook_endpoints?limit=100', {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${stripeSecret}`,
          'Stripe-Version': WEBHOOK_API_VERSION,
        },
      });
      if (endpointsResponse.ok) {
        const endpoints = await endpointsResponse.json() as StripeList<StripeWebhookEndpoint>;
        platformEndpoint = endpoints.data?.find((candidate) =>
          candidate.status === 'enabled'
          && candidate.livemode === true
          && candidate.url === expectedPlatformWebhookUrl
        );
        connectEndpoint = endpoints.data?.find((candidate) =>
          candidate.status === 'enabled'
          && candidate.livemode === true
          && candidate.url === expectedConnectWebhookUrl
        );
      } else {
        console.error('[stripe-config-health] Stripe webhook endpoint lookup failed', endpointsResponse.status);
      }
    }

    const platformEndpointActive = Boolean(platformEndpoint);
    const connectEndpointActive = Boolean(connectEndpoint);
    const platformEventsComplete = eventsComplete(platformEndpoint, REQUIRED_PLATFORM_WEBHOOK_EVENTS);
    const connectEventsComplete = eventsComplete(connectEndpoint, REQUIRED_CONNECT_WEBHOOK_EVENTS);
    const platformApiVersionOk = platformEndpoint?.api_version === WEBHOOK_API_VERSION;
    const connectApiVersionOk = connectEndpoint?.api_version === WEBHOOK_API_VERSION;
    const customerLinks = livemode
      ? await checkCustomerTenantLinks(stripeSecret, supabaseBase)
      : {
          checked: false, total: 0, valid: 0,
          adoptable_legacy: 0, indeterminate: 0, all_valid: false,
        };
    const webhookSecretConfigured = secrets.platformConfigured && secrets.connectConfigured;
    const webhookEndpointActive = platformEndpointActive && connectEndpointActive;
    const webhookEventsComplete = platformEventsComplete && connectEventsComplete;
    const productionReady = livemode
      && webhookSecretConfigured
      && secrets.distinct
      && webhookEndpointActive
      && webhookEventsComplete
      && platformApiVersionOk
      && connectApiVersionOk
      && customerLinks.checked
      && customerLinks.all_valid;
    return json(req, {
      configured: true,
      reachable: true,
      authenticated: true,
      livemode,
      mode: livemode ? 'live' : 'test',
      webhook_secret_configured: webhookSecretConfigured,
      platform_webhook_secret_configured: secrets.platformConfigured,
      connect_webhook_secret_configured: secrets.connectConfigured,
      webhook_secrets_distinct: secrets.distinct,
      webhook_endpoint_active: webhookEndpointActive,
      webhook_events_complete: webhookEventsComplete,
      platform_webhook_endpoint_active: platformEndpointActive,
      platform_webhook_events_complete: platformEventsComplete,
      platform_webhook_api_version_ok: platformApiVersionOk,
      connect_webhook_endpoint_active: connectEndpointActive,
      connect_webhook_events_complete: connectEventsComplete,
      connect_webhook_api_version_ok: connectApiVersionOk,
      customer_tenant_links_checked: customerLinks.checked,
      customer_tenant_links_total: customerLinks.total,
      customer_tenant_links_valid: customerLinks.valid,
      customer_tenant_links_adoptable_legacy: customerLinks.adoptable_legacy,
      customer_tenant_links_indeterminate: customerLinks.indeterminate,
      customer_tenant_links_ok: customerLinks.all_valid,
      expected_webhook_api_version: WEBHOOK_API_VERSION,
      production_ready: productionReady,
    }, productionReady ? 200 : 503);
  } catch (error) {
    console.error('[stripe-config-health] Stripe unreachable', error instanceof Error ? error.message : 'unknown');
    return json(req, {
      configured: true,
      reachable: false,
      authenticated: false,
      livemode: false,
      mode: 'unreachable',
      webhook_secret_configured: secrets.platformConfigured && secrets.connectConfigured,
      platform_webhook_secret_configured: secrets.platformConfigured,
      connect_webhook_secret_configured: secrets.connectConfigured,
      webhook_secrets_distinct: secrets.distinct,
    }, 503);
  }
});

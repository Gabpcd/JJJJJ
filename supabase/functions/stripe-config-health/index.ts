/**
 * Diagnostic Stripe sans effet de bord et sans exposition de secret.
 * Réservé aux administrateurs AAL2 et aux appels internes service_role.
 */
import { corsHeaders } from '../_shared/cors.ts';
import { verifyAdminOrServiceRole } from '../_shared/admin-auth.ts';

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

// Le schéma des événements doit rester identique à celui compilé et testé
// par stripe-node 18.5.0. Une migration vers Clover exige d'abord la mise à
// niveau du SDK et une recette complète des deux handlers webhook.
const WEBHOOK_API_VERSION = '2025-08-27.basil';

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
    const stripeResponse = await fetch('https://api.stripe.com/v1/balance', {
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
      const endpointsResponse = await fetch('https://api.stripe.com/v1/webhook_endpoints?limit=100', {
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
    const webhookSecretConfigured = secrets.platformConfigured && secrets.connectConfigured;
    const webhookEndpointActive = platformEndpointActive && connectEndpointActive;
    const webhookEventsComplete = platformEventsComplete && connectEventsComplete;
    const productionReady = livemode
      && webhookSecretConfigured
      && secrets.distinct
      && webhookEndpointActive
      && webhookEventsComplete
      && platformApiVersionOk
      && connectApiVersionOk;
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

import { requireStagingInvoiceScope } from './stripe-invoice-staging-test.ts';

// Exception de transport uniquement : les comptes et la facture restent TEST.
const STAGE = 'https://mejpriaetwgtcstbgfid.supabase.co';
const ETABLISSEMENT = 'fcaa6c97-46c1-4da9-8f74-1395aed616c5';
const RECIPIENT = 'gabrielle@jolene.app';
const TYPES = ['FACTURE_EMISE', 'FACTURE_PAYEE'] as const;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
type Row = Record<string, any>;
type Client = Parameters<typeof requireStagingInvoiceScope>[0];
type Event = { type: typeof TYPES[number]; emailId: string; bodySha256: string };
export type InvoiceEmailStagingConfig = {
  serverSha: string; manifestSha256: string; missionId: string; factureId: string;
  createdAt: string; expiresAt: string; events: [Event, Event];
};
const refuse = (): never => { throw new Error('INVOICE_EMAIL_STAGING_REFUSED'); };
const must = (value: unknown): void => { if (!value) refuse(); };
function exactKeys(value: unknown, keys: string[]): value is Row {
  return !!value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

/** Les SHA sont des références de revue, jamais une attestation de déploiement. */
export function invoiceEmailStagingConfig(
  get: (key: string) => string | undefined, now = Date.now(),
): InvoiceEmailStagingConfig | null {
  const raw = get('INVOICE_EMAIL_STAGING_TEST_RUN');
  if (!raw) return null;
  must(get('SUPABASE_URL') === STAGE && get('APP_URL') === 'http://127.0.0.1:8085'
    && [undefined, 'staging', 'test'].includes(get('SUPABASE_ENV')));
  let c: unknown; try { c = JSON.parse(raw); } catch { return refuse(); }
  must(exactKeys(c, ['serverSha', 'manifestSha256', 'missionId', 'factureId', 'createdAt', 'expiresAt', 'events']));
  const config = c as Row;
  must(typeof config.serverSha === 'string' && /^[a-f0-9]{40}$/.test(config.serverSha)
    && typeof config.manifestSha256 === 'string' && /^[a-f0-9]{64}$/.test(config.manifestSha256)
    && typeof config.missionId === 'string' && UUID.test(config.missionId)
    && typeof config.factureId === 'string' && UUID.test(config.factureId) && config.factureId !== config.missionId
    && typeof config.createdAt === 'string' && typeof config.expiresAt === 'string');
  const created = Date.parse(config.createdAt), expires = Date.parse(config.expiresAt);
  must(Number.isFinite(created) && Number.isFinite(expires) && created <= now && now < expires
    && expires > created && expires - created <= 60 * 60_000);
  must(Array.isArray(config.events) && config.events.length === 2);
  for (const [index, event] of config.events.entries()) {
    must(exactKeys(event, ['type', 'emailId', 'bodySha256']) && event.type === TYPES[index]
      && typeof event.emailId === 'string' && UUID.test(event.emailId)
      && typeof event.bodySha256 === 'string' && /^[a-f0-9]{64}$/.test(event.bodySha256));
  }
  must(config.events[0].emailId !== config.events[1].emailId);
  return Object.freeze(config) as InvoiceEmailStagingConfig;
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    const row = value as Row;
    return Object.fromEntries(Object.keys(row).sort().map(key => [key, canonical(row[key])]));
  }
  return value;
}
export async function invoiceEmailBodySha256(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(canonical(value)));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('');
}

/** Aucune mutation, aucun fournisseur ; la réservation reste celle de send-email. */
export async function admitStagingInvoiceEmail(
  sb: Client, body: Row, isServiceRole: boolean, get: (key: string) => string | undefined, now = Date.now(),
): Promise<{ recipient: string } | null> {
  if (!isServiceRole || !TYPES.includes(body.type) || !get('INVOICE_EMAIL_STAGING_TEST_RUN')) return null;
  const config = invoiceEmailStagingConfig(get, now)!;
  must(exactKeys(body, ['type', 'destinataire_id', 'data', 'idempotency_key'])
    && body.destinataire_id === ETABLISSEMENT
    && body.data && typeof body.data === 'object' && !Array.isArray(body.data)
    && body.data.facture_id === config.factureId && body.data.famille_document === 'COMMISSION'
    && body.data.destinataire_role === 'ETABLISSEMENT');
  const event = config.events.find(item => item.type === body.type)!;
  const key = `${body.type === 'FACTURE_EMISE' ? 'facture-emise' : 'facture-payee'}-commission:${config.factureId}:${ETABLISSEMENT}`;
  must(body.idempotency_key === key);
  const durableBody = { type: body.type, destinataire_id: body.destinataire_id, data: body.data };
  must(await invoiceEmailBodySha256(durableBody) === event.bodySha256);
  const queued = await sb.from('email_queue')
    .select('id,type,destinataire_id,data,statut').eq('id', event.emailId).single();
  must(!queued.error && queued.data?.id === event.emailId && queued.data.type === 'FACTURATION_DOCUMENT'
    && queued.data.destinataire_id === ETABLISSEMENT
    && ['EN_ATTENTE', 'ENVOYE'].includes(queued.data.statut)
    && await invoiceEmailBodySha256(queued.data.data) === event.bodySha256);
  // Réutilise les gardes existantes : Auth/profils E/S TEST exacts, owner,
  // Customer/Express, mission salariée terminée, facture 17,42 €, liens et solde.
  await requireStagingInvoiceScope(sb, {
    ...config, uiSha: config.serverSha, amountCents: 1742, returnOrigin: 'http://127.0.0.1:8085',
  }, config.factureId);
  if (body.type === 'FACTURE_PAYEE') {
    const invoice = await sb.from('factures').select('id,statut,stripe_payment_intent_id,date_paiement')
      .eq('id', config.factureId).single();
    const claim = await sb.from('stripe_payment_flow_claims')
      .select('resource_key,flow,owner_token,stripe_checkout_session_id,stripe_payment_intent_id')
      .eq('resource_key', `FACTURE:${config.factureId}`).single();
    must(!invoice.error && invoice.data?.id === config.factureId && invoice.data.statut === 'PAYEE' && !!invoice.data.date_paiement
      && typeof invoice.data.stripe_payment_intent_id === 'string'
      && /^pi_[A-Za-z0-9]+$/.test(invoice.data.stripe_payment_intent_id)
      && body.data.stripe_payment_intent_id === invoice.data.stripe_payment_intent_id
      && !claim.error && claim.data?.flow === 'CHECKOUT_INVOICE'
      && claim.data.owner_token === `invoice:${config.factureId}`
      && /^cs_test_[A-Za-z0-9]+$/.test(claim.data.stripe_checkout_session_id)
      && body.data.stripe_checkout_session_id === claim.data.stripe_checkout_session_id
      && (claim.data.stripe_payment_intent_id === null
        || claim.data.stripe_payment_intent_id === invoice.data.stripe_payment_intent_id));
  }
  must(Date.now() < Date.parse(config.expiresAt));
  return { recipient: RECIPIENT };
}

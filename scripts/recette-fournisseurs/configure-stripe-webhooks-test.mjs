import { createHmac } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Raccordement du seul bac à sable existant. Aucun paiement ni cron lancé.
export const PROJECT = 'mejpriaetwgtcstbgfid';
export const ACCOUNT = 'acct_1T9pt0EVhQ7cb53W';
export const API_VERSION = '2026-02-25.clover'; // Contrat du handler déployé, sans migration d'API.
export const ROUTES = [
  { slug: 'stripe-webhook', secretName: 'STRIPE_PLATFORM_WEBHOOK_SECRET', connect: false,
    events: ['charge.dispute.closed', 'charge.dispute.created', 'charge.expired', 'charge.failed',
      'charge.pending', 'charge.refunded', 'charge.succeeded', 'checkout.session.expired',
      'checkout.session.completed', 'invoice.payment_failed', 'payment_intent.payment_failed',
      'payment_intent.succeeded', 'transfer.created', 'transfer.reversed', 'transfer.updated'] },
  { slug: 'stripe-connect-webhook', secretName: 'STRIPE_CONNECT_WEBHOOK_SECRET', connect: true,
    events: ['account.updated', 'payout.canceled', 'payout.created', 'payout.failed', 'payout.paid'] },
];
export const FUNCTIONS = ['stripe-webhook', 'stripe-connect-webhook', 'process-stripe-refunds',
  'stripe-connect-pay-mission', 'generate-invoice'];
const base = `https://api.supabase.com/v1/projects/${PROJECT}`;
const endpointUrl = route => `https://${PROJECT}.supabase.co/functions/v1/${route.slug}`;
const prerequisites = `SELECT
  (SELECT count(*)::int FROM cron.job WHERE active) AS active_crons,
  (SELECT count(*)::int FROM public.escrow_release_queue WHERE statut IN ('EN_ATTENTE','EN_COURS')) AS releases,
  (SELECT count(*)::int FROM public.stripe_refunds_queue WHERE statut IN ('EN_ATTENTE','EN_COURS')) AS refunds;`;
const codes = new Set(['CREDENTIALS_INVALID', 'RUN_ID_INVALID', 'REQUEST_FAILED', 'REQUEST_REJECTED',
  'RESPONSE_INVALID', 'WRONG_STRIPE_ACCOUNT', 'NOT_TEST_MODE', 'STRIPE_TEST_RESTRICTED',
  'STAGING_NOT_QUIESCENT', 'KEY_NOT_CONFIGURED', 'EXISTING_WEBHOOK_CONFIG', 'AUTH_MODE_MISMATCH',
  'ENDPOINT_LIST_INCOMPLETE', 'ENDPOINT_RESPONSE_INVALID', 'SECRETS_NOT_DISTINCT',
  'SECRET_PRESENCE_UNCONFIRMED', 'SIGNATURE_PROBE_FAILED', 'REPORT_WRITE_FAILED']);
const fail = code => { throw new Error(code); };

export async function configureTestWebhooks({ token, stripeKey, runId, checkOnly = false,
  fetchImpl = fetch, checkpoint = () => {}, now = () => Date.now() }) {
  const report = { projectRef: PROJECT, stripeAccount: ACCOUNT, status: 'BLOCKED',
    integratedFlowReady: false, providerPaymentsCreated: 0, secretWriteAttempted: false,
    secretWriteAccepted: false, endpoints: [], issue: null };
  const save = () => { try { checkpoint(structuredClone(report)); } catch { fail('REPORT_WRITE_FAILED'); } };
  async function request(url, credential, { method = 'GET', json, form, idempotencyKey } = {}) {
    let response;
    try {
      response = await fetchImpl(url, { method, redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { Authorization: `Bearer ${credential}`,
          ...(json ? { 'Content-Type': 'application/json' } : {}),
          ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
          ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}) },
        ...(json ? { body: JSON.stringify(json) } : {}), ...(form ? { body: form.toString() } : {}) });
    } catch { fail('REQUEST_FAILED'); }
    if (!response.ok) fail('REQUEST_REJECTED');
    if (method === 'POST' && url.endsWith('/secrets')) return;
    try { return await response.json(); } catch { fail('RESPONSE_INVALID'); }
  }
  async function names() {
    const rows = await request(`${base}/secrets`, token);
    if (!Array.isArray(rows) || rows.some(row => typeof row?.name !== 'string')) fail('RESPONSE_INVALID');
    return rows.map(row => row.name);
  }
  try {
    if (!token?.trim() || !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey ?? '')) fail('CREDENTIALS_INVALID');
    if (!/^\d{6,20}$/.test(runId ?? '')) fail('RUN_ID_INVALID');
    const account = await request('https://api.stripe.com/v1/account', stripeKey);
    if (account?.id !== ACCOUNT) fail('WRONG_STRIPE_ACCOUNT');
    const balance = await request('https://api.stripe.com/v1/balance', stripeKey);
    if (balance?.livemode !== false) fail('NOT_TEST_MODE');
    if (account.charges_enabled !== true || account.payouts_enabled !== true
      || account.capabilities?.card_payments !== 'active' || account.capabilities?.transfers !== 'active') {
      fail('STRIPE_TEST_RESTRICTED');
    }
    const rows = await request(`${base}/database/query`, token, { method: 'POST', json: { query: prerequisites, read_only: true } });
    if (!Array.isArray(rows) || rows.length !== 1
      || !['active_crons', 'releases', 'refunds'].every(key => rows[0]?.[key] === 0)) fail('STAGING_NOT_QUIESCENT');
    const before = await names();
    if (!before.includes('STRIPE_SECRET_KEY')) fail('KEY_NOT_CONFIGURED');
    if (['STRIPE_WEBHOOK_SECRET', ...ROUTES.map(route => route.secretName)].some(name => before.includes(name))) {
      fail('EXISTING_WEBHOOK_CONFIG');
    }
    const functions = await request(`${base}/functions`, token);
    if (!Array.isArray(functions) || !FUNCTIONS.every(slug => {
      const matches = functions.filter(fn => (fn.slug ?? fn.name) === slug);
      return matches.length === 1 && matches[0].status === 'ACTIVE' && matches[0].verify_jwt === false;
    })) fail('AUTH_MODE_MISMATCH');
    let cursor = '', complete = false;
    const seen = new Set();
    for (let page = 0; page < 10; page++) {
      const list = await request(`https://api.stripe.com/v1/webhook_endpoints?limit=100${cursor ? `&starting_after=${cursor}` : ''}`, stripeKey);
      if (!Array.isArray(list?.data) || typeof list.has_more !== 'boolean') fail('ENDPOINT_LIST_INCOMPLETE');
      for (const endpoint of list.data) {
        if (!/^we_[A-Za-z0-9]+$/.test(endpoint?.id ?? '') || seen.has(endpoint.id)) fail('ENDPOINT_LIST_INCOMPLETE');
        seen.add(endpoint.id);
        if (ROUTES.some(route => endpoint.url === endpointUrl(route))) fail('EXISTING_WEBHOOK_CONFIG');
      }
      if (!list.has_more) { complete = true; break; }
      if (!list.data.length) fail('ENDPOINT_LIST_INCOMPLETE');
      cursor = list.data.at(-1).id;
    }
    if (!complete) fail('ENDPOINT_LIST_INCOMPLETE');
    if (checkOnly) { report.status = 'PREREQUISITES_OK'; save(); return report; }
    const secrets = [];
    for (const route of ROUTES) {
      const state = { route: route.slug, connect: route.connect, id: null, creationAttempted: true,
        created: false, signatureVerified: false, oppositeSignatureRejected: false };
      report.endpoints.push(state); report.status = 'CONFIGURATION_IN_PROGRESS'; save();
      const form = new URLSearchParams({ url: endpointUrl(route), connect: String(route.connect),
        api_version: API_VERSION, description: `Jolene STAGING TEST — ${route.slug}`,
        'metadata[jolene_project]': PROJECT, 'metadata[setup_run]': runId });
      route.events.forEach(event => form.append('enabled_events[]', event));
      const result = await request('https://api.stripe.com/v1/webhook_endpoints', stripeKey, {
        method: 'POST', form, idempotencyKey: `jolene-staging-webhooks/${runId}/${route.slug}` });
      if (typeof result?.id === 'string' && /^we_[A-Za-z0-9]+$/.test(result.id)) { state.id = result.id; save(); }
      if (!state.id || result.livemode !== false || result.url !== endpointUrl(route)
        || result.status !== 'enabled' || result.api_version !== API_VERSION
        || !Array.isArray(result.enabled_events)
        || JSON.stringify([...result.enabled_events].sort()) !== JSON.stringify([...route.events].sort())
        || !/^whsec_[A-Za-z0-9]+$/.test(result.secret ?? '')) fail('ENDPOINT_RESPONSE_INVALID');
      state.created = true; secrets.push({ name: route.secretName, value: result.secret }); save();
    }
    if (secrets[0].value === secrets[1].value) fail('SECRETS_NOT_DISTINCT');
    report.secretWriteAttempted = true; save();
    await request(`${base}/secrets`, token, { method: 'POST', json: secrets });
    report.secretWriteAccepted = true; save();
    const after = await names();
    if (!secrets.every(secret => after.includes(secret.name))) fail('SECRET_PRESENCE_UNCONFIRMED');

    // Événement volontairement hors allow-list : preuve de signature/routage,
    // jamais une preuve de paiement. Le handler retourne avant son premier accès DB.
    for (let i = 0; i < ROUTES.length; i++) {
      const route = ROUTES[i];
      const body = JSON.stringify({ id: `evt_jolene_configuration_${runId}_${i}`, object: 'event',
        type: 'jolene.configuration_probe', livemode: false, data: { object: {} },
        ...(route.connect ? { account: ACCOUNT } : {}) });
      for (const wrong of [false, true]) {
        const timestamp = Math.floor(now() / 1000);
        const signature = createHmac('sha256', secrets[wrong ? 1 - i : i].value)
          .update(`${timestamp}.${body}`).digest('hex');
        let response;
        try {
          response = await fetchImpl(endpointUrl(route), { method: 'POST', redirect: 'error',
            signal: AbortSignal.timeout(15000), body, headers: { 'Content-Type': 'application/json',
              'stripe-signature': `t=${timestamp},v1=${signature}` } });
        } catch { fail('SIGNATURE_PROBE_FAILED'); }
        let data;
        try { data = await response.json(); } catch { fail('SIGNATURE_PROBE_FAILED'); }
        if (wrong ? response.status !== 400 || data?.error !== 'Invalid signature'
          : response.status !== 200 || data?.skipped !== 'source_event_not_allowed') fail('SIGNATURE_PROBE_FAILED');
        report.endpoints[i][wrong ? 'oppositeSignatureRejected' : 'signatureVerified'] = true; save();
      }
    }
    report.status = 'WEBHOOK_SIGNATURES_CONFIGURED'; save();
  } catch (error) {
    report.issue = codes.has(error?.message) ? error.message : 'UNEXPECTED_ERROR';
    report.status = report.endpoints.length ? 'CONFIGURATION_REQUIRES_VERIFICATION' : 'BLOCKED';
    // Aucun retry, DELETE ou remplacement de secret après une réponse ambiguë.
    try { checkpoint(structuredClone(report)); } catch { /* Error state returned to caller. */ }
  }
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const checkpoint = report => writeFileSync('configuration-webhooks-staging.json', JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  const report = await configureTestWebhooks({ token: process.env.STAGING_SUPABASE_ACCESS_TOKEN,
    stripeKey: process.env.STRIPE_TEST_SECRET_KEY, runId: process.env.GITHUB_RUN_ID,
    checkOnly: process.argv.includes('--check-only'), checkpoint });
  console.log(`${report.status}: ${report.issue ?? 'recette paiement/remboursement restant à exécuter'}`);
  process.exitCode = ['PREREQUISITES_OK', 'WEBHOOK_SIGNATURES_CONFIGURED'].includes(report.status) ? 0 : 2;
}

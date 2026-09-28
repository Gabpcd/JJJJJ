import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Configuration partielle, manuelle : aucun paiement, webhook ou cron créé.
export const PROJECT = 'mejpriaetwgtcstbgfid';
export const ACCOUNT = 'acct_1T9pt0EVhQ7cb53W';
export const FUNCTIONS = ['send-sms', 'escrow-debit-echeance', 'escrow-release', 'process-stripe-refunds',
  'stripe-webhook', 'stripe-connect-webhook', 'stripe-connect-onboard'];
const BASE = `https://api.supabase.com/v1/projects/${PROJECT}`;
const prerequisites = `SELECT
  (SELECT count(*)::int FROM cron.job WHERE active) AS active_crons,
  (SELECT count(*)::int FROM public.escrow_release_queue WHERE statut IN ('EN_ATTENTE','EN_COURS')) AS releases,
  (SELECT count(*)::int FROM public.stripe_refunds_queue WHERE statut IN ('EN_ATTENTE','EN_COURS')) AS refunds;`;

export async function configureStripeTest({ token, stripeKey, checkOnly = false, fetchImpl = fetch }) {
  const report = { projectRef: PROJECT, stripeAccount: ACCOUNT, status: 'BLOCKED',
    secretWriteAttempted: false, secretWriteAccepted: false, secretPresent: false,
    readyForTransports: false, integratedFlowReady: false, issue: null };
  const fail = code => { throw new Error(code); };
  async function request(url, credential, method = 'GET', body) {
    let response;
    try {
      response = await fetchImpl(url, { method, redirect: 'error',
        headers: { Authorization: `Bearer ${credential}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(15000) });
    } catch { fail('REQUEST_FAILED'); }
    if (!response.ok) fail('REQUEST_REJECTED');
    // Never parse/print error bodies, which may contain supplied credentials.
    if (method === 'POST' && url.endsWith('/secrets')) return;
    try { return await response.json(); } catch { fail('INVALID_RESPONSE'); }
  }
  async function names() {
    const rows = await request(`${BASE}/secrets`, token);
    if (!Array.isArray(rows) || rows.some(row => typeof row?.name !== 'string')) fail('INVALID_SECRET_METADATA');
    return rows.map(row => row.name);
  }
  try {
    if (typeof token !== 'string' || !token.trim()) fail('STAGING_TOKEN_MISSING');
    if (typeof stripeKey !== 'string' || !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey)) fail('TEST_KEY_REQUIRED');
    const account = await request('https://api.stripe.com/v1/account', stripeKey);
    if (account?.id !== ACCOUNT) fail('STRIPE_ACCOUNT_MISMATCH');
    const balance = await request('https://api.stripe.com/v1/balance', stripeKey);
    if (balance?.livemode !== false) fail('STRIPE_TEST_MODE_UNCONFIRMED');
    const rows = await request(`${BASE}/database/query`, token, 'POST', { query: prerequisites, read_only: true });
    if (!Array.isArray(rows) || rows.length !== 1
      || !['active_crons', 'releases', 'refunds'].every(key => rows[0]?.[key] === 0)) fail('STAGING_NOT_QUIESCENT');
    const before = await names();
    // An existing key is never overwritten, even after an ambiguous first run.
    if (before.includes('STRIPE_SECRET_KEY')) fail('EXISTING_KEY_REQUIRES_VERIFICATION');
    if (before.some(name => ['STRIPE_WEBHOOK_SECRET', 'STRIPE_PLATFORM_WEBHOOK_SECRET', 'STRIPE_CONNECT_WEBHOOK_SECRET'].includes(name))) fail('WEBHOOKS_ALREADY_CONFIGURED');
    const functions = await request(`${BASE}/functions`, token);
    // Preserve the observed gateway setting; authentication remains inside
    // the handlers (user/service-role checks or signed Stripe webhook).
    if (!Array.isArray(functions) || !FUNCTIONS.every(slug => {
      const matches = functions.filter(fn => (fn.slug ?? fn.name) === slug);
      return matches.length === 1 && matches[0].status === 'ACTIVE' && matches[0].verify_jwt === false;
    })) fail('EXISTING_FUNCTION_AUTH_MODE_MISMATCH');
    if (checkOnly) {
      report.status = 'PREREQUISITES_OK';
      return report;
    }
    report.secretWriteAttempted = true;
    await request(`${BASE}/secrets`, token, 'POST', [{ name: 'STRIPE_SECRET_KEY', value: stripeKey }]);
    report.secretWriteAccepted = true;
    report.secretPresent = (await names()).includes('STRIPE_SECRET_KEY');
    if (!report.secretPresent) fail('SECRET_PRESENCE_UNCONFIRMED');
    report.status = 'KEY_CONFIGURED_ONLY';
  } catch (error) {
    // All errors emitted above are fixed codes. Never report provider values.
    const codes = new Set(['REQUEST_FAILED', 'REQUEST_REJECTED', 'INVALID_RESPONSE', 'INVALID_SECRET_METADATA',
      'STAGING_TOKEN_MISSING', 'TEST_KEY_REQUIRED', 'STRIPE_ACCOUNT_MISMATCH', 'STRIPE_TEST_MODE_UNCONFIRMED',
      'STAGING_NOT_QUIESCENT', 'EXISTING_KEY_REQUIRES_VERIFICATION', 'WEBHOOKS_ALREADY_CONFIGURED', 'SECRET_PRESENCE_UNCONFIRMED',
      'EXISTING_FUNCTION_AUTH_MODE_MISMATCH']);
    report.issue = codes.has(error?.message) ? error.message : 'UNEXPECTED_ERROR';
    if (report.secretWriteAttempted) report.status = 'WRITE_REQUIRES_VERIFICATION';
  }
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = await configureStripeTest({ token: process.env.STAGING_SUPABASE_ACCESS_TOKEN,
    stripeKey: process.env.STRIPE_TEST_SECRET_KEY, checkOnly: process.argv.includes('--check-only') });
  writeFileSync('configuration-stripe-staging.json', JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  console.log(`${report.status}: ${report.issue ?? 'circuit intégré toujours NON PRÊT'}`);
  process.exitCode = ['PREREQUISITES_OK', 'KEY_CONFIGURED_ONLY'].includes(report.status) ? 0 : 2;
}

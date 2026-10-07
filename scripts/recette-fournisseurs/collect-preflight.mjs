// Read-only discovery, deliberately incomplete. No transport or provider write.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { realpathSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PROJECT = 'mejpriaetwgtcstbgfid';
export const ACCOUNT = 'acct_1T9pt0EVhQ7cb53W';
export const EDGES = Object.freeze(['send-sms', 'escrow-debit-echeance', 'escrow-release',
  'process-stripe-refunds', 'stripe-webhook', 'stripe-connect-webhook', 'stripe-connect-onboard']);
export const SQL_FUNCTIONS = Object.freeze(['fn_envoyer_otp_signature', 'fn_escrow_debits_a_echeance',
  'fn_escrow_releases_a_traiter', 'fn_stripe_refunds_reels_a_traiter']);
const SECRET_NAMES = ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_FROM_NUMBER',
  'TWILIO_PHONE_NUMBER', 'STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET', 'STRIPE_PLATFORM_WEBHOOK_SECRET', 'STRIPE_CONNECT_WEBHOOK_SECRET'];
const VAULT_NAMES = ['supabase_url', 'service_role_key'];
const SHA = /^[a-f0-9]{40}$/;
const validSha = value => typeof value === 'string' && SHA.test(value) && !/^0+$/.test(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;
const requireValue = value => { if (!value) throw new Error('INVALID_METADATA'); };
const versionsValid = values => Array.isArray(values) && values.length > 0 && values.length <= 10000
  && values.every(v => typeof v === 'string' && /^\d{14}$/.test(v)) && new Set(values).size === values.length;
const fingerprint = value => createHash('sha256').update(value).digest('hex');

// Fixed SELECTs only; never invoke a business RPC or read a decrypted Vault view.
export const QUERIES = Object.freeze({
  migrations: 'SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;',
  sqlFunctions: `SELECT p.proname AS name, md5(pg_get_functiondef(p.oid)) AS digest
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f' AND p.proname IN
    ('fn_envoyer_otp_signature','fn_escrow_debits_a_echeance','fn_escrow_releases_a_traiter','fn_stripe_refunds_reels_a_traiter')
    ORDER BY p.proname;`,
  vaultNames: "SELECT name FROM vault.secrets WHERE name IN ('supabase_url','service_role_key') ORDER BY name;",
  crons: 'SELECT count(*)::int AS total, count(*) FILTER (WHERE active)::int AS active FROM cron.job;',
  queues: `SELECT 'escrow_release_queue' AS name, count(*)::int AS total,
    count(*) FILTER (WHERE statut IN ('EN_ATTENTE','EN_COURS'))::int AS pending FROM public.escrow_release_queue
    UNION ALL SELECT 'stripe_refunds_queue', count(*)::int,
    count(*) FILTER (WHERE statut IN ('EN_ATTENTE','EN_COURS'))::int FROM public.stripe_refunds_queue;`,
});

// git reads committed blobs, not the potentially modified working tree. These
// are source file hashes, never presented as equivalent to a deployed bundle.
export function sourceFromGit(expectedSha, cwd = process.cwd()) {
  requireValue(validSha(expectedSha));
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 32 * 1024 * 1024 });
  const actualSha = git(['rev-parse', 'HEAD']).trim();
  requireValue(actualSha === expectedSha);
  const paths = git(['ls-tree', '-r', '--name-only', '-z', actualSha, '--', 'supabase/migrations', 'supabase/functions', 'supabase/config.toml']).split('\0').filter(Boolean);
  const migrationFiles = paths.filter(p => p.startsWith('supabase/migrations/') && p.endsWith('.sql'));
  requireValue(migrationFiles.every(p => /^supabase\/migrations\/\d{14}_[A-Za-z0-9_-]+\.sql$/.test(p)));
  const migrations = migrationFiles.map(p => p.split('/').at(-1).slice(0, 14)).sort();
  requireValue(versionsValid(migrations));
  const files = paths.filter(p => p === 'supabase/config.toml' || new RegExp(`^supabase/functions/(?:${EDGES.join('|')}|_shared)/[A-Za-z0-9_./-]+\\.(?:ts|json)$`).test(p));
  requireValue(EDGES.every(name => files.includes(`supabase/functions/${name}/index.ts`)));
  return { repository: 'Gabpcd/JJJJJ', sha: actualSha, migrations,
    sourceFiles: files.sort().map(path => ({ path, sha256: fingerprint(git(['show', `${actualSha}:${path}`])) })) };
}

function projectionNames(rows, allowed) {
  requireValue(Array.isArray(rows) && rows.length <= 10000);
  // Only predefined names are emitted. API value/digest/description fields are
  // never inspected or persisted, including unexpected provider response fields.
  return Object.fromEntries(allowed.map(name => [name, rows.some(row => row?.name === name)]));
}

/** All credentials stay in request headers. Reports contain only projections. */
export async function collectPreflight({ source, token, stripeKey, fetchImpl = fetch, now = new Date().toISOString() }) {
  const report = { version: 1, status: 'NON_PRET', readyForTransports: false, integratedFlowReady: false,
    readOnly: true, providerMutations: 0, projectRef: PROJECT, expectedStripeAccount: ACCOUNT,
    observedAt: null, source: null, checks: {}, issues: [],
    unknowns: ['DEPLOYED_EDGE_CONTENT_NOT_COMPARED', 'SQL_DIGESTS_NOT_COMPARED_TO_CANDIDATE',
      'COHORT_GUARDS_NOT_ATTESTED', 'VAULT_VALUE_ROUTING_NOT_READ', 'SMS_DELIVERY_NOT_PROVEN',
      'EDGE_STRIPE_ACCOUNT_NOT_VERIFIED', 'CONNECT_WEBHOOK_SCOPE_NOT_PROVEN',
      'FOREIGN_QUEUE_OWNERSHIP_NOT_CLASSIFIED', 'SNAPSHOT_NOT_TRANSACTIONAL'],
  };
  const issue = code => report.issues.push(code);
  if (typeof now !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(now)
    || !Number.isFinite(Date.parse(now)) || new Date(now).toISOString() !== now) {
    issue('OBSERVATION_TIME_INVALID'); return report;
  }
  report.observedAt = now;
  // Re-project caller supplied metadata: unknown fields can never reach output.
  if (!source || source.repository !== 'Gabpcd/JJJJJ' || !validSha(source.sha)
    || !versionsValid(source.migrations) || !Array.isArray(source.sourceFiles)
    || !source.sourceFiles.length || source.sourceFiles.length > 10000
    || !source.sourceFiles.every(f => typeof f?.path === 'string'
      && /^supabase\/(?:config\.toml|functions\/[a-z0-9_-]+\/[A-Za-z0-9_./-]+\.(?:ts|json))$/.test(f.path)
      && typeof f.sha256 === 'string' && /^[a-f0-9]{64}$/.test(f.sha256) && !/^0+$/.test(f.sha256))) {
    issue('SOURCE_INVALID'); return report;
  }
  report.source = { repository: 'Gabpcd/JJJJJ', sha: source.sha, migrations: [...source.migrations].sort(),
    sourceFiles: source.sourceFiles.map(f => ({ path: f.path, sha256: f.sha256 })) };
  const supabaseBase = `https://api.supabase.com/v1/projects/${PROJECT}`;
  async function request(url, credential, query) {
    const response = await fetchImpl(url, { method: query ? 'POST' : 'GET', redirect: 'error',
      headers: { Authorization: `Bearer ${credential}`, ...(query ? { 'Content-Type': 'application/json' } : {}) },
      ...(query ? { body: JSON.stringify({ query, read_only: true }) } : {}), signal: AbortSignal.timeout(15000) });
    requireValue(response.ok);
    return response.json();
  }
  async function check(name, task) {
    try { report.checks[name] = { status: 'OBSERVED', ...await task() }; }
    catch { report.checks[name] = { status: 'UNKNOWN' }; issue(`${name.toUpperCase()}_UNAVAILABLE_OR_INVALID`); }
  }
  if (typeof token !== 'string' || !token.trim()) issue('STAGING_TOKEN_ABSENT');
  else {
    const sql = name => request(`${supabaseBase}/database/query`, token, QUERIES[name]);
    await check('migrations', async () => {
      const rows = await sql('migrations'), versions = Array.isArray(rows) ? rows.map(r => r?.version) : null;
      requireValue(versionsValid(versions));
      const matchesCandidate = JSON.stringify([...versions].sort()) === JSON.stringify(report.source.migrations);
      if (!matchesCandidate) issue('MIGRATIONS_MISMATCH');
      return { versions: [...versions].sort(), matchesCandidate };
    });
    await check('edgeFunctions', async () => {
      const rows = await request(`${supabaseBase}/functions`, token);
      requireValue(Array.isArray(rows) && rows.length <= 10000);
      const functions = EDGES.map(name => {
        const found = rows.filter(row => row?.slug === name);
        if (!found.length) return { name, present: false };
        requireValue(found.length === 1);
        const fn = found[0];
        requireValue(integer(fn.version) && typeof fn.verify_jwt === 'boolean');
        return { name, present: true, version: fn.version, active: fn.status === 'ACTIVE', verifyJwt: fn.verify_jwt };
      });
      if (functions.some(fn => !fn.present || !fn.active)) issue('EDGE_FUNCTION_MISSING_OR_INACTIVE');
      return { functions, deployedContentMatchesCandidate: null };
    });
    await check('sqlFunctions', async () => {
      const rows = await sql('sqlFunctions');
      requireValue(Array.isArray(rows) && rows.length === SQL_FUNCTIONS.length);
      const functions = SQL_FUNCTIONS.map(name => {
        const found = rows.filter(row => row?.name === name);
        requireValue(found.length === 1 && typeof found[0].digest === 'string'
          && /^[a-f0-9]{32}$/.test(found[0].digest) && !/^0+$/.test(found[0].digest));
        return { name, digestAlgorithm: 'md5', digest: found[0].digest };
      });
      return { functions, definitionsMatchCandidate: null };
    });
    await check('edgeSecretNames', async () => ({ present: projectionNames(await request(`${supabaseBase}/secrets`, token), SECRET_NAMES), valuesVerified: false }));
    await check('vaultNames', async () => ({ present: projectionNames(await sql('vaultNames'), VAULT_NAMES), valuesVerified: false, projectUrlMatches: null }));
    await check('crons', async () => {
      const rows = await sql('crons');
      requireValue(Array.isArray(rows) && rows.length === 1 && integer(rows[0].total) && integer(rows[0].active) && rows[0].active <= rows[0].total);
      if (rows[0].active) issue('ACTIVE_CRONS_PRESENT');
      return { total: rows[0].total, active: rows[0].active };
    });
    await check('queues', async () => {
      const rows = await sql('queues');
      requireValue(Array.isArray(rows) && rows.length === 2);
      return { queues: ['escrow_release_queue', 'stripe_refunds_queue'].map(name => {
        const found = rows.filter(row => row?.name === name);
        requireValue(found.length === 1 && integer(found[0].total) && integer(found[0].pending) && found[0].pending <= found[0].total);
        return { name, total: found[0].total, pending: found[0].pending };
      }), eligibleForeignQueueCount: null, unknownQueueCount: null };
    });
  }
  if (typeof stripeKey !== 'string' || !/^sk_test_[A-Za-z0-9]+$/.test(stripeKey)) issue('STRIPE_TEST_KEY_ABSENT_OR_INVALID');
  else {
    await check('stripeSandbox', async () => {
      const account = await request('https://api.stripe.com/v1/account', stripeKey);
      requireValue(account?.id === ACCOUNT);
      const balance = await request('https://api.stripe.com/v1/balance', stripeKey);
      requireValue(balance?.livemode === false);
      // Une clé authentifiée ne prouve pas qu'un paiement puisse aboutir.
      // Ne conserver aucun nom, champ d'identité ni identifiant de personne.
      const chargesEnabled = typeof account.charges_enabled === 'boolean' ? account.charges_enabled : null;
      const payoutsEnabled = typeof account.payouts_enabled === 'boolean' ? account.payouts_enabled : null;
      const cardPaymentsActive = typeof account.capabilities?.card_payments === 'string'
        ? account.capabilities.card_payments === 'active' : null;
      const transfersActive = typeof account.capabilities?.transfers === 'string'
        ? account.capabilities.transfers === 'active' : null;
      const pastDueCount = Array.isArray(account.requirements?.past_due)
        ? account.requirements.past_due.length : null;
      const requirementsPastDue = account.requirements?.disabled_reason === 'requirements.past_due';
      if ([chargesEnabled, payoutsEnabled, cardPaymentsActive, transfersActive].includes(false)
        || requirementsPastDue || (pastDueCount !== null && pastDueCount > 0)) issue('STRIPE_TEST_ACCOUNT_RESTRICTED');
      if ([chargesEnabled, payoutsEnabled, cardPaymentsActive, transfersActive, pastDueCount].includes(null)) {
        issue('STRIPE_TEST_CAPABILITIES_UNKNOWN');
      }
      return { accountMatches: true, livemode: false, chargesEnabled, payoutsEnabled,
        cardPaymentsActive, transfersActive, pastDueCount, requirementsPastDue };
    });
    // Do not inspect even test endpoints for a different or unconfirmed account.
    if (report.checks.stripeSandbox.status === 'OBSERVED') await check('stripeWebhooks', async () => {
      const routes = ['stripe-webhook', 'stripe-connect-webhook'];
      const events = ['payment_intent.succeeded', 'payment_intent.payment_failed', 'charge.refunded',
        'charge.dispute.created', 'payout.paid', 'payout.failed', 'payout.canceled', 'account.updated'];
      const found = Object.fromEntries(routes.map(route => [route, []]));
      const seen = new Set(); let cursor = '', complete = false, total = 0;
      for (let page = 0; page < 10; page++) {
        const result = await request(`https://api.stripe.com/v1/webhook_endpoints?limit=100${cursor ? `&starting_after=${encodeURIComponent(cursor)}` : ''}`, stripeKey);
        requireValue(Array.isArray(result?.data) && result.data.length <= 100 && typeof result.has_more === 'boolean');
        for (const endpoint of result.data) {
          requireValue(typeof endpoint?.id === 'string' && /^we_[A-Za-z0-9]+$/.test(endpoint.id) && !seen.has(endpoint.id));
          seen.add(endpoint.id); total++;
          for (const route of routes) if (endpoint.url === `https://${PROJECT}.supabase.co/functions/v1/${route}`) {
            requireValue(endpoint.livemode === false && Array.isArray(endpoint.enabled_events));
            found[route].push({ enabled: endpoint.status === 'enabled',
              events: Object.fromEntries(events.map(event => [event, endpoint.enabled_events.includes(event) || endpoint.enabled_events.includes('*')])) });
          }
        }
        if (!result.has_more) { complete = true; break; }
        requireValue(result.data.length > 0); cursor = result.data.at(-1).id;
      }
      requireValue(complete);
      if (routes.some(route => !found[route].some(endpoint => endpoint.enabled))) issue('STAGING_WEBHOOK_ROUTE_MISSING');
      return { total, routes: found, connectScopeConfirmed: null, signingSecretMatches: null };
    });
  }
  return report;
}

if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url))) {
  let report;
  try {
    const source = sourceFromGit(process.env.RECETTE_CANDIDATE_SHA);
    report = await collectPreflight({ source, token: process.env.STAGING_SUPABASE_ACCESS_TOKEN,
      stripeKey: process.env.STRIPE_TEST_SECRET_KEY });
  } catch {
    report = { status: 'NON_PRET', readyForTransports: false, integratedFlowReady: false,
      issues: ['COLLECTION_SOURCE_OR_RUNTIME_INVALID'] };
  }
  try {
    writeFileSync('recette-fournisseurs-preflight.json', `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    console.log('NON_PRET : inventaire en lecture seule enregistré ; aucune recette fournisseur exécutée.');
  } catch { console.error('RAPPORT_NON_ECRIT : aucune validation déduite.'); }
  // Partial discovery is never a successful preflight, including all HTTP 200s.
  process.exitCode = 2;
}

// Pure offline validation of supplied, non-secret metadata. No env, filesystem,
// fetch, provider client or mutation. A positive result authorizes NO transport.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const PROJECT = 'mejpriaetwgtcstbgfid';
const REPOSITORY = 'Gabpcd/JJJJJ';
const MAX_AGE_MS = 15 * 60 * 1000;
const SHA = /^[a-f0-9]{40}$/;
const ACCOUNT = /^acct_[A-Za-z0-9]{8,64}$/;
const CONFIGURATION = ['vaultProjectMatches', 'vaultBearerPresent', 'smsCredentialsPresent',
  'smsSenderReady', 'smsDeliveryCapable', 'stripeKeyPresent', 'platformWebhookPresent',
  'connectWebhookPresent', 'webhooksRouteToProject'];
const GUARDS = ['accountClassificationUnchanged', 'sourceClassificationUnchanged',
  'financeQueueFiltersUnchanged', 'webhookFixtureExclusionUnchanged'];
const RUNTIME = ['activeCronCount', 'eligibleForeignQueueCount', 'unknownQueueCount'];
const REQUIRED_FUNCTIONS = ['edge:send-sms', 'edge:escrow-debit-echeance', 'edge:escrow-release',
  'edge:process-stripe-refunds', 'edge:stripe-webhook', 'edge:stripe-connect-webhook',
  'edge:stripe-connect-onboard', 'sql:fn_envoyer_otp_signature',
  'sql:fn_escrow_debits_a_echeance', 'sql:fn_escrow_releases_a_traiter', 'sql:fn_stripe_refunds_reels_a_traiter'];
const MESSAGES = {
  EXPECTATION_INVALID: 'Référence attendue absente, inconnue ou incomplète.',
  OBSERVATION_INVALID: 'Métadonnées observées absentes ou schéma de champs invalide.',
  SOURCE_MISMATCH: 'Dépôt ou SHA observé différent de la source attendue.',
  TARGET_MISMATCH: 'La cible observée ne correspond pas au staging autorisé.',
  OBSERVATION_TIME_INVALID: 'Horodatage absent, invalide, futur ou trop ancien.',
  MIGRATIONS_INVALID: 'Inventaire migrations absent, invalide ou dupliqué.',
  MIGRATIONS_MISMATCH: 'Inventaire migrations différent de la candidate attendue.',
  FUNCTIONS_INVALID: 'Inventaire fonctions absent, incomplet, invalide ou dupliqué.',
  FUNCTIONS_MISMATCH: 'Définitions ou configuration des fonctions différentes de la candidate.',
  CONFIGURATION_UNCONFIRMED: 'Présence et routage de la configuration non entièrement confirmés.',
  GUARDS_UNCONFIRMED: 'Conservation de toutes les protections de cohortes non confirmée.',
  RUNTIME_UNCONFIRMED: 'État des crons ou des files non confirmé sans activité étrangère.',
  SANDBOX_UNCONFIRMED: 'Compte sandbox attendu ou mode TEST non confirmé.',
  METADATA_UNREADABLE: 'Métadonnées non lisibles ; aucune validation déduite.',
};
function object(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.getPrototypeOf(value) === Object.prototype
    && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
}
const text = (value, expression) => typeof value === 'string' && expression.test(value);
const sourceSha = value => text(value, SHA) && !/^0+$/.test(value);
function migrations(value) {
  return Array.isArray(value) && value.length > 0 && value.length <= 10_000
    && value.every(version => text(version, /^\d{14}$/)) && new Set(value).size === value.length;
}
function functions(value) {
  if (!Array.isArray(value) || !value.length || value.length > 10_000) return false;
  const keys = [];
  for (const fn of value) {
    if (!object(fn, ['kind', 'name', 'digestAlgorithm', 'digest', 'verifyJwt'])
      || !['edge', 'sql'].includes(fn.kind) || !text(fn.name, /^[a-z][a-z0-9_-]{1,80}$/)
      || !['sha256', 'md5'].includes(fn.digestAlgorithm)
      || !text(fn.digest, fn.digestAlgorithm === 'sha256' ? /^[a-f0-9]{64}$/ : /^[a-f0-9]{32}$/)
      || /^0+$/.test(fn.digest)
      || (fn.kind === 'edge' ? typeof fn.verifyJwt !== 'boolean' : fn.verifyJwt !== null)) return false;
    keys.push(`${fn.kind}:${fn.name}`);
  }
  return new Set(keys).size === keys.length && REQUIRED_FUNCTIONS.every(name => keys.includes(name));
}
function sameFunctions(a, b) {
  const canonical = values => values.map(fn => [fn.kind, fn.name, fn.digestAlgorithm, fn.digest, fn.verifyJwt])
    .sort((left, right) => `${left[0]}:${left[1]}`.localeCompare(`${right[0]}:${right[1]}`));
  return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
}
function expectedValid(expected) {
  return object(expected, ['repository', 'sha', 'projectRef', 'stripeAccountId', 'migrations', 'functions'])
    && expected.repository === REPOSITORY && expected.projectRef === PROJECT
    && sourceSha(expected.sha) && text(expected.stripeAccountId, ACCOUNT)
    && migrations(expected.migrations) && expected.migrations.includes('20260927152738')
    && functions(expected.functions);
}

/**
 * expected must be built from the reviewed candidate, never inferred from the
 * observed deployment. Digests and booleans remain the collector's assertions:
 * this validator neither verifies their provenance nor contacts their source.
 * now is explicit to make freshness checks deterministic and independently tested.
 */
export function validatePreflightMetadata(expected, observed, options = {}) {
  const codes = new Set();
  const add = code => codes.add(code);
  try {
    const validOptions = object(options, []) || object(options, ['now']);
    const now = validOptions ? (Object.hasOwn(options, 'now') ? options.now : Date.now()) : NaN;
    if (!validOptions) add('OBSERVATION_TIME_INVALID');
    const validExpected = expectedValid(expected);
    if (!validExpected) add('EXPECTATION_INVALID');
    if (!object(observed, ['repository', 'sha', 'projectRef', 'observedAt', 'migrations', 'functions',
      'configuration', 'guards', 'runtime', 'sandbox'])) add('OBSERVATION_INVALID');
    else {
      if (observed.repository !== REPOSITORY || !sourceSha(observed.sha)
        || (validExpected && observed.sha !== expected.sha)) add('SOURCE_MISMATCH');
      if (observed.projectRef !== PROJECT) add('TARGET_MISMATCH');
      const timestamp = typeof observed.observedAt === 'string' ? Date.parse(observed.observedAt) : NaN;
      if (!text(observed.observedAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/)
        || !Number.isFinite(timestamp) || new Date(timestamp).toISOString() !== observed.observedAt
        || !Number.isFinite(now) || timestamp > now || now - timestamp > MAX_AGE_MS) add('OBSERVATION_TIME_INVALID');
      if (!migrations(observed.migrations)) add('MIGRATIONS_INVALID');
      else if (validExpected && JSON.stringify([...observed.migrations].sort()) !== JSON.stringify([...expected.migrations].sort())) add('MIGRATIONS_MISMATCH');
      if (!functions(observed.functions)) add('FUNCTIONS_INVALID');
      else if (validExpected && !sameFunctions(expected.functions, observed.functions)) add('FUNCTIONS_MISMATCH');
      if (!object(observed.configuration, CONFIGURATION)
        || !CONFIGURATION.every(key => observed.configuration[key] === true)) add('CONFIGURATION_UNCONFIRMED');
      if (!object(observed.guards, GUARDS) || !GUARDS.every(key => observed.guards[key] === true)) add('GUARDS_UNCONFIRMED');
      if (!object(observed.runtime, RUNTIME)
        || !RUNTIME.every(key => Number.isSafeInteger(observed.runtime[key]) && observed.runtime[key] === 0)) add('RUNTIME_UNCONFIRMED');
      if (!object(observed.sandbox, ['accountId', 'livemode']) || observed.sandbox.livemode !== false
        || !text(observed.sandbox.accountId, ACCOUNT)
        || (validExpected && observed.sandbox.accountId !== expected.stripeAccountId)) add('SANDBOX_UNCONFIRMED');
    }
  } catch {
    // Never echo input, a provider body, getter exception or credential value.
    add('METADATA_UNREADABLE');
  }
  return {
    status: codes.size ? 'NON_PRET' : 'METADONNEES_COHERENTES',
    readyForTransports: false,
    integratedFlowReady: false,
    checkedOffline: true,
    reasons: [...codes].map(code => ({ code, message: MESSAGES[code] })),
    limits: ['Aucune vérification distante effectuée.',
      'Les fixtures restent exclues des prestataires ; aucun changement de cohorte autorisé.',
      'Un résultat local cohérent ne prouve ni réception, signature, paiement, ni nettoyage.'],
  };
}

// Portable entry-point check, including runtimes without import.meta.main.
// Resolving a path and converting its URL performs no filesystem access.
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  console.error('PREFLIGHT_NON_EXECUTABLE: collecteur/CLI absent ; aucune vérification effectuée.');
  process.exitCode = 1;
}

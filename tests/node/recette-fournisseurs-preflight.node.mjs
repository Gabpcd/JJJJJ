import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { validatePreflightMetadata } from '../../scripts/recette-fournisseurs/preflight.mjs';

const now = Date.parse('2026-09-28T02:00:00.000Z');
function fixture() {
  const functions = ['send-sms', 'escrow-debit-echeance', 'escrow-release', 'process-stripe-refunds',
    'stripe-webhook', 'stripe-connect-webhook', 'stripe-connect-onboard'].map(name => ({
      kind: 'edge', name, digestAlgorithm: 'sha256', digest: 'a'.repeat(64), verifyJwt: false,
    }));
  for (const name of ['fn_envoyer_otp_signature', 'fn_escrow_debits_a_echeance',
    'fn_escrow_releases_a_traiter', 'fn_stripe_refunds_reels_a_traiter']) {
    functions.push({ kind: 'sql', name, digestAlgorithm: 'md5', digest: 'b'.repeat(32), verifyJwt: null });
  }
  const expected = { repository: 'Gabpcd/JJJJJ', sha: 'c'.repeat(40), projectRef: 'mejpriaetwgtcstbgfid',
    stripeAccountId: 'acct_sandbox123456', migrations: ['20260927152738', '20260925143000'], functions };
  const observed = { repository: expected.repository, sha: expected.sha, projectRef: expected.projectRef,
    observedAt: new Date(now).toISOString(), migrations: [...expected.migrations], functions: structuredClone(functions),
    configuration: { vaultProjectMatches: true, vaultBearerPresent: true, smsCredentialsPresent: true,
      smsSenderReady: true, smsDeliveryCapable: true, stripeKeyPresent: true, platformWebhookPresent: true,
      connectWebhookPresent: true, webhooksRouteToProject: true },
    guards: { accountClassificationUnchanged: true, sourceClassificationUnchanged: true,
      financeQueueFiltersUnchanged: true, webhookFixtureExclusionUnchanged: true },
    runtime: { activeCronCount: 0, eligibleForeignQueueCount: 0, unknownQueueCount: 0 },
    sandbox: { accountId: expected.stripeAccountId, livemode: false } };
  return { expected, observed };
}
function refused(expected, observed, code, options = { now }) {
  const result = validatePreflightMetadata(expected, observed, options);
  assert.equal(result.status, 'NON_PRET');
  assert.equal(result.readyForTransports, false);
  assert.equal(result.integratedFlowReady, false);
  assert.ok(result.reasons.some(reason => reason.code === code), JSON.stringify(result.reasons));
  return result;
}

test('exact fresh metadata is coherent offline but never authorizes transports or claims integration', () => {
  const { expected, observed } = fixture(), snapshot = structuredClone({ expected, observed });
  const result = validatePreflightMetadata(expected, observed, { now });
  assert.equal(result.status, 'METADONNEES_COHERENTES');
  assert.deepEqual(result.reasons, []);
  assert.equal(result.checkedOffline, true);
  assert.equal(result.readyForTransports, false);
  assert.equal(result.integratedFlowReady, false);
  assert.deepEqual({ expected, observed }, snapshot);
  observed.migrations.reverse(); observed.functions.reverse();
  assert.equal(validatePreflightMetadata(expected, observed, { now }).status, 'METADONNEES_COHERENTES');
});

test('missing or unknown top-level fields and invalid expectations refuse closed', () => {
  for (const part of ['expected', 'observed']) {
    const valid = fixture()[part];
    for (const key of Object.keys(valid)) {
      const f = fixture(); delete f[part][key];
      refused(f.expected, f.observed, part === 'expected' ? 'EXPECTATION_INVALID' : 'OBSERVATION_INVALID');
    }
    for (const replacement of [null, undefined, [], { ...valid, credentials: 'do-not-retain' }]) {
      const f = fixture(); f[part] = replacement;
      refused(f.expected, f.observed, part === 'expected' ? 'EXPECTATION_INVALID' : 'OBSERVATION_INVALID');
    }
  }
});

test('production, old branch, wrong SHA and wrong repository never pass', () => {
  for (const [key, value, code] of [
    ['projectRef', 'flripxtsyegjshnhzjkz', 'TARGET_MISMATCH'],
    ['projectRef', 'wnepopwygokbhlqghydb', 'TARGET_MISMATCH'],
    ['sha', 'd'.repeat(40), 'SOURCE_MISMATCH'], ['sha', '0'.repeat(40), 'SOURCE_MISMATCH'],
    ['repository', 'other/JJJJJ', 'SOURCE_MISMATCH'],
  ]) { const f = fixture(); f.observed[key] = value; refused(f.expected, f.observed, code); }
  const f = fixture(); f.expected.projectRef = 'flripxtsyegjshnhzjkz';
  refused(f.expected, f.observed, 'EXPECTATION_INVALID');
});

test('migration list must be exact, nonempty, unique and well formed', () => {
  for (const value of [[], null, ['20260927152738', '20260927152738'], ['latest'], [20260927152738]]) {
    const f = fixture(); f.observed.migrations = value; refused(f.expected, f.observed, 'MIGRATIONS_INVALID');
  }
  for (const value of [['20260927152738'], ['20260927152738', '20260925143000', '20260928100000']]) {
    const f = fixture(); f.observed.migrations = value; refused(f.expected, f.observed, 'MIGRATIONS_MISMATCH');
  }
});

test('function inventory compares definitions and JWT configuration, not just names', () => {
  for (const changed of [{ digest: 'e'.repeat(64) }, { verifyJwt: true }]) {
    const f = fixture(); Object.assign(f.observed.functions[0], changed);
    refused(f.expected, f.observed, 'FUNCTIONS_MISMATCH');
  }
  for (const value of [[], null]) {
    const f = fixture(); f.observed.functions = value; refused(f.expected, f.observed, 'FUNCTIONS_INVALID');
  }
  const missing = fixture(); missing.observed.functions.pop(); refused(missing.expected, missing.observed, 'FUNCTIONS_INVALID');
  const duplicate = fixture(); duplicate.observed.functions.push(duplicate.observed.functions[0]);
  refused(duplicate.expected, duplicate.observed, 'FUNCTIONS_INVALID');
  const extra = fixture(); extra.observed.functions.push({ ...extra.observed.functions[0], name: 'another-function' });
  refused(extra.expected, extra.observed, 'FUNCTIONS_MISMATCH');
  const unknown = fixture(); unknown.observed.functions[0].source = 'raw-source-not-allowed';
  refused(unknown.expected, unknown.observed, 'FUNCTIONS_INVALID');
});

test('all configuration and cohort attestations must be explicit boolean true', () => {
  for (const [section, code] of [['configuration', 'CONFIGURATION_UNCONFIRMED'], ['guards', 'GUARDS_UNCONFIRMED']]) {
    for (const key of Object.keys(fixture().observed[section])) {
      for (const value of [false, null, undefined, 'true', 1]) {
        const f = fixture(); f.observed[section][key] = value; refused(f.expected, f.observed, code);
      }
    }
    const f = fixture(); f.observed[section].extra = true; refused(f.expected, f.observed, code);
  }
});

test('financial selectors cannot be omitted or replaced by matching zero digest placeholders', () => {
  for (const name of ['fn_escrow_debits_a_echeance', 'fn_escrow_releases_a_traiter', 'fn_stripe_refunds_reels_a_traiter']) {
    const f = fixture(); f.observed.functions = f.observed.functions.filter(fn => fn.name !== name);
    refused(f.expected, f.observed, 'FUNCTIONS_INVALID');
    f.expected.functions = f.expected.functions.filter(fn => fn.name !== name);
    refused(f.expected, f.observed, 'EXPECTATION_INVALID');
  }
  for (const algorithm of ['sha256', 'md5']) {
    const f = fixture();
    for (const source of [f.expected, f.observed]) {
      const fn = source.functions.find(item => item.digestAlgorithm === algorithm);
      fn.digest = '0'.repeat(algorithm === 'sha256' ? 64 : 32);
    }
    const result = refused(f.expected, f.observed, 'EXPECTATION_INVALID');
    assert.ok(result.reasons.some(reason => reason.code === 'FUNCTIONS_INVALID'));
  }
});

test('crons and foreign/unknown queues require known zero counts', () => {
  for (const key of Object.keys(fixture().observed.runtime)) {
    for (const value of [1, -1, 0.5, NaN, Infinity, '0', null, undefined]) {
      const f = fixture(); f.observed.runtime[key] = value; refused(f.expected, f.observed, 'RUNTIME_UNCONFIRMED');
    }
  }
});

test('sandbox identity and boolean livemode=false are both mandatory', () => {
  for (const changed of [{ accountId: 'acct_other12345678' }, { livemode: true }, { livemode: 'false' }, { livemode: null }]) {
    const f = fixture(); Object.assign(f.observed.sandbox, changed); refused(f.expected, f.observed, 'SANDBOX_UNCONFIRMED');
  }
});

test('stale, future and malformed timestamps are not treated as fresh', () => {
  for (const value of [new Date(now - 900001).toISOString(), new Date(now + 1).toISOString(),
    '2026-02-30T02:00:00.000Z', '2026-09-28', null, undefined]) {
    const f = fixture(); f.observed.observedAt = value; refused(f.expected, f.observed, 'OBSERVATION_TIME_INVALID');
  }
  const f = fixture(); refused(f.expected, f.observed, 'OBSERVATION_TIME_INVALID', { now: NaN });
  refused(f.expected, f.observed, 'OBSERVATION_TIME_INVALID', null);
  refused(f.expected, f.observed, 'OBSERVATION_TIME_INVALID', { now, extra: 'unknown' });
});

test('reasons accumulate without copying secrets, personal data or thrown messages', () => {
  const sensitive = 'sk_test_PRIVATE +33612345678 user@example.invalid OTP-123456';
  const f = fixture(); f.observed.configuration.vaultBearerPresent = sensitive;
  f.observed.runtime.unknownQueueCount = 1; f.observed.sandbox.livemode = true;
  const result = refused(f.expected, f.observed, 'CONFIGURATION_UNCONFIRMED');
  assert.equal(result.reasons.length, 3);
  assert.equal(JSON.stringify(result).includes(sensitive), false);
  const malicious = fixture();
  Object.defineProperty(malicious.observed, 'sha', { enumerable: true, get() { throw new Error(sensitive); } });
  const unreadable = refused(malicious.expected, malicious.observed, 'METADATA_UNREADABLE');
  assert.equal(JSON.stringify(unreadable).includes(sensitive), false);
});

test('validation does not call a transport even when metadata is coherent', () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => { throw new Error('NETWORK_FORBIDDEN'); };
  try {
    const f = fixture();
    assert.equal(validatePreflightMetadata(f.expected, f.observed, { now }).status, 'METADONNEES_COHERENTES');
  } finally { globalThis.fetch = original; }
});

test('direct execution refuses with a static error while importing remains side-effect free', () => {
  const url = new URL('../../scripts/recette-fournisseurs/preflight.mjs', import.meta.url);
  for (const args of [[], ['--local-only', '--token=sk_test_NEVER_ECHO']]) {
    const child = spawnSync(process.execPath, [fileURLToPath(url), ...args], {
      encoding: 'utf8', timeout: 5000, env: { PATH: process.env.PATH },
    });
    assert.ifError(child.error);
    assert.equal(child.signal, null);
    assert.equal(child.status, 1);
    assert.equal(child.stdout, '');
    assert.equal(child.stderr, 'PREFLIGHT_NON_EXECUTABLE: collecteur/CLI absent ; aucune vérification effectuée.\n');
  }
  const imported = spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(url.href)});`], {
    encoding: 'utf8', timeout: 5000, env: { PATH: process.env.PATH },
  });
  assert.ifError(imported.error);
  assert.equal(imported.status, 0);
  assert.equal(imported.stdout + imported.stderr, '');
});

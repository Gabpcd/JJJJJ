import { Transform } from 'node:stream';

export const PROJECT_REF = 'mejpriaetwgtcstbgfid';
export const PROJECT_URL = `https://${PROJECT_REF}.supabase.co`;
export const EXPO_URL = 'exp://127.0.0.1:8090';
export const PHASES = ['initial_signed_out', 'A_login', 'A_process_restart', 'A_logout', 'A_logout_process_restart',
  'B_login', 'B_process_restart', 'B_logout', 'B_logout_process_restart'];
export const CAPTURES = { A_login: 'auth-A-login.png', A_process_restart: 'auth-A-restart.png',
  B_login: 'auth-B-login.png', B_process_restart: 'auth-B-restart.png' };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA = /^[0-9a-f]{40}$/;
const exact = (value, keys) => value && !Array.isArray(value) && typeof value === 'object'
  && Object.keys(value).sort().join('|') === [...keys].sort().join('|');
function requireThat(ok, code) { if (!ok) throw new Error(code); }

// Values only arrive through stdin. This validates the new synthetic cohort; it does
// not open the previous closed harness, create users, or grant application roles.
export function parseCohort(bytes) {
  requireThat(Buffer.byteLength(bytes) <= 8192, 'COHORT_SIZE');
  let input; try { input = JSON.parse(bytes); } catch { throw new Error('COHORT_JSON'); }
  requireThat(exact(input, ['schemaVersion', 'purpose', 'projectRef', 'actors']) && input.schemaVersion === 1
    && input.purpose === 'native-auth-staging-v1' && input.projectRef === PROJECT_REF
    && Array.isArray(input.actors) && input.actors.length === 2, 'COHORT_SCOPE');
  for (const [index, actor] of input.actors.entries()) {
    requireThat(exact(actor, ['alias', 'userId', 'email', 'password']) && actor.alias === ['A', 'B'][index]
      && UUID.test(actor.userId) && actor.email === `native-test-${actor.userId}@example.invalid`
      // Exact generator alphabet also excludes Maestro ${...} interpolation.
      && typeof actor.password === 'string' && /^Nt![A-Za-z0-9_-]{48}$/.test(actor.password), 'COHORT_ACTOR');
  }
  requireThat(['userId', 'email', 'password'].every(key => input.actors[0][key] !== input.actors[1][key]), 'COHORT_DISTINCT');
  return input;
}

export function guardRun(input) {
  requireThat(input.actions === 'true' && input.event === 'workflow_dispatch' && input.ref === 'refs/heads/main', 'MANUAL_MAIN_ONLY');
  requireThat(SHA.test(input.sha) && input.sha === input.reviewedSha && input.sha === input.checkoutSha
    && input.sha === input.dispatchSha && input.sha === input.workflowSha, 'REVIEWED_SHA_REQUIRED');
  requireThat(input.projectRef === PROJECT_REF && input.url === PROJECT_URL, 'STAGING_ONLY');
  requireThat(/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(input.key), 'PUBLISHABLE_KEY_ONLY');
  requireThat(['iphone', 'ipad-portrait', 'ipad-landscape', 'android'].includes(input.format), 'FORMAT');
  return input;
}

// No blanket process.env spread: the Expo process never inherits credentials,
// GitHub tokens, admin keys, xctestrun data, or a developer's .env values.
export function publicEnvironment(source, config) {
  const keys = ['PATH', 'HOME', 'USER', 'TMPDIR', 'TEMP', 'TMP', 'LANG', 'LC_ALL', 'SHELL',
    'JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'DEVELOPER_DIR', 'SDKROOT', 'RUNNER_TEMP', 'GITHUB_ACTIONS'];
  return { ...Object.fromEntries(keys.filter(k => typeof source[k] === 'string').map(k => [k, source[k]])),
    CI: '1', EXPO_NO_DOTENV: '1', EXPO_NO_TELEMETRY: '1', MAESTRO_CLI_NO_ANALYTICS: '1',
    MAESTRO_DRIVER_STARTUP_TIMEOUT: '300000', NODE_OPTIONS: '--dns-result-order=ipv4first',
    NATIVE_IOS_SOURCE_SHA: config.sha, RCT_USE_PREBUILT_RNCORE: '0', RCT_USE_RN_DEP: '1',
    EXPO_PUBLIC_JOLENE_MODE: 'staging', EXPO_PUBLIC_SUPABASE_URL: PROJECT_URL,
    EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: config.key,
    EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: '0', EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: '0',
    EXPO_PUBLIC_JOLENE_PRESENCE_SCENARIO: '0', EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS: '0' };
}

export function sensitiveForms(cohort) {
  const originals = cohort.actors.flatMap(a => [a.userId, a.email, a.password]);
  return [...new Set(originals.flatMap(value => [value, JSON.stringify(value).slice(1, -1), encodeURIComponent(value),
    encodeURIComponent(encodeURIComponent(value)), Buffer.from(value).toString('base64'), Buffer.from(value).toString('base64url'),
    Buffer.from(value).toString('hex')]))].sort((a, b) => b.length - a.length);
}
export function redact(text, forms) {
  let safe = String(text);
  for (const form of forms) safe = safe.split(form).join('[PRIVATE]');
  return safe.replace(/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, '[JWT]')
    .replace(/Bearer\s+[^\s"']+/gi, 'Bearer [PRIVATE]');
}
export function privateLogFilter(forms) {
  // Buffer complete lines before writing, so stream chunk boundaries cannot split
  // a credential. Oversized lines are discarded, never partially emitted.
  let pending = '', discarded = false;
  return new Transform({
    transform(chunk, _encoding, done) {
      const parts = (pending + chunk.toString('utf8')).split('\n'); pending = parts.pop();
      for (const line of parts) {
        this.push(discarded || line.length > 1_048_576 ? '[OVERSIZED PRIVATE LINE]\n' : `${redact(line, forms)}\n`);
        discarded = false;
      }
      if (pending.length > 1_048_576) { pending = ''; discarded = true; }
      done();
    },
    flush(done) { if (pending || discarded) this.push(discarded ? '[OVERSIZED PRIVATE LINE]' : redact(pending, forms)); done(); },
  });
}

export function validatePhaseProof(value) {
  requireThat(exact(value, ['schemaVersion', 'phases']) && value.schemaVersion === 1 && Array.isArray(value.phases), 'PROOF_SCHEMA');
  requireThat(value.phases.length <= PHASES.length && value.phases.every((name, index) => name === PHASES[index]), 'PROOF_ORDER');
  return [...value.phases];
}

export function publicReport({ sha, format, phases = [], passed, failure = null, cleanup }, forms) {
  requireThat(SHA.test(sha) && ['iphone', 'ipad-portrait', 'ipad-landscape', 'android'].includes(format), 'REPORT_CONTEXT');
  validatePhaseProof({ schemaVersion: 1, phases });
  requireThat(typeof cleanup === 'boolean' && typeof passed === 'boolean'
    && (failure === null || ['preparation', 'driver', 'proof', 'cleanup'].includes(failure)), 'REPORT_STATUS');
  requireThat(!passed || (phases.length === PHASES.length && cleanup && failure === null), 'REPORT_SUCCESS');
  const report = { schemaVersion: 1, scenario: 'native-auth-staging-v1', sha, format, projectRef: PROJECT_REF,
    host: format === 'android' ? 'expo-go' : 'compiled-debug-source',
    integration: 'real-staging-auth', phases: PHASES.map(name => ({ name, passed: phases.includes(name) })),
    passed, cleanup, failure, scope: 'Auth; onboarding admission; process restart; local logout; A/B isolation',
    excludes: ['professional profiles', 'business permissions', 'documents', 'contracts', 'payments', 'physical devices', 'store binaries'] };
  const text = JSON.stringify(report, null, 2);
  requireThat(!forms.some(value => text.includes(value)), 'EXPORT_PRIVATE_VALUE');
  return text;
}

export function validatePublicDirectory(names, phases = []) {
  const expected = ['report.json', ...phases.flatMap(p => CAPTURES[p] ? [CAPTURES[p]] : [])].sort();
  requireThat(names.length === expected.length && [...names].sort().every((n, i) => n === expected[i]), 'PUBLIC_WHITELIST');
}

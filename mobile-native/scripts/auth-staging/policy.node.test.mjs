import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, mkdtemp, writeFile, stat, rm, link, symlink } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CAPTURES, EXPO_URL, PHASES, PROJECT_REF, PROJECT_URL, guardRun, parseCohort, publicEnvironment,
  sensitiveForms, redact, privateLogFilter, publicReport, validatePublicDirectory, validatePhaseProof } from './policy.mjs';
import { androidFlows } from './android-flow.mjs';

const actors = ['A', 'B'].map((alias, index) => ({ alias,
  userId: `00000000-0000-4000-8000-00000000000${index + 1}`,
  email: `native-test-00000000-0000-4000-8000-00000000000${index + 1}@example.invalid`,
  password: `Nt!${alias.repeat(48)}`,
}));
const cohort = { schemaVersion: 1, purpose: 'native-auth-staging-v1', projectRef: PROJECT_REF, actors };
const sha = 'a'.repeat(40);
const context = { actions: 'true', event: 'workflow_dispatch', ref: 'refs/heads/main', sha, reviewedSha: sha,
  checkoutSha: sha, dispatchSha: sha, workflowSha: sha,
  format: 'iphone', projectRef: PROJECT_REF, url: PROJECT_URL, key: `sb_publishable_${'x'.repeat(24)}` };
const source = async name => readFile(new URL(name, import.meta.url), 'utf8');

test('only two exact new-cohort identities, intended project and generator passwords', () => {
  assert.deepEqual(parseCohort(JSON.stringify(cohort)), cohort);
  const bad = [ { ...cohort, projectRef: 'production' }, { ...cohort, actors: actors.slice(0, 1) },
    { ...cohort, serviceKey: 'not-permitted' }, { ...cohort, actors: [...actors, actors[0]] },
    { ...cohort, actors: [actors[0], { ...actors[1], alias: 'A' }] },
    { ...cohort, actors: [actors[0], { ...actors[1], email: 'someone@jolene.app' }] },
    { ...cohort, actors: [actors[0], { ...actors[1], password: actors[0].password }] },
    { ...cohort, actors: [actors[0], { ...actors[1], password: 'Nt!${secret}' + 'x'.repeat(48) }] } ];
  for (const input of bad) assert.throws(() => parseCohort(JSON.stringify(input)));
  assert.throws(() => parseCohort('a'.repeat(8193)), /COHORT_SIZE/);
  assert.throws(() => parseCohort('{'), /COHORT_JSON/);
});

test('manual main, immutable reviewed checkout SHA and publishable TEST config required together', () => {
  assert.equal(guardRun(context), context);
  for (const patch of [ { actions: 'false' }, { event: 'pull_request' }, { ref: 'refs/heads/feature' },
    { sha: 'main' }, { reviewedSha: 'b'.repeat(40) }, { checkoutSha: 'b'.repeat(40) },
    { dispatchSha: 'b'.repeat(40) }, { workflowSha: 'b'.repeat(40) }, { workflowSha: undefined }, { projectRef: 'another' },
    { url: `${PROJECT_URL}/` }, { url: 'https://jolene.app' }, { key: 'sb_secret_notallowed' },
    { key: 'eyJlegacyJWT' }, { format: 'physical-iphone' } ]) assert.throws(() => guardRun({ ...context, ...patch }));
});

test('Expo child environment contains no private input, CI token, service key or arbitrary Expo flag', () => {
  const output = publicEnvironment({ PATH: '/bin', HOME: '/runner', JOLENE_NATIVE_AUTH_COHORT: JSON.stringify(cohort),
    GITHUB_TOKEN: 'private-ci-token', SUPABASE_SERVICE_ROLE_KEY: 'private-admin-key', EXPO_PUBLIC_PASSWORD: actors[0].password,
    RCT_USE_PREBUILT_RNCORE: '1', NATIVE_IOS_SOURCE_SHA: 'unreviewed',
    EXPO_PUBLIC_JOLENE_MODE: 'demo', EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: '1', NODE_OPTIONS: '--require malicious.js' }, context);
  assert.equal(output.EXPO_PUBLIC_JOLENE_MODE, 'staging');
  assert.equal(output.EXPO_PUBLIC_SUPABASE_URL, PROJECT_URL);
  assert.equal(output.EXPO_NO_DOTENV, '1');
  assert.equal(output.NATIVE_IOS_SOURCE_SHA, sha);
  assert.equal(output.RCT_USE_PREBUILT_RNCORE, '0');
  assert.equal(output.RCT_USE_RN_DEP, '1');
  assert.equal(output.EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO, '0');
  for (const key of ['JOLENE_NATIVE_AUTH_COHORT', 'GITHUB_TOKEN', 'SUPABASE_SERVICE_ROLE_KEY', 'EXPO_PUBLIC_PASSWORD']) assert.equal(output[key], undefined);
  assert.equal(JSON.stringify(output).includes(actors[0].password), false);
});

test('all direct, JSON, URL, double URL, base64/url and hex canaries are removed', () => {
  const privateExample = { actors: [{ userId: 'CANARY_ID_123456', email: 'canary+private@example.invalid', password: 'canary_"$\\private_123456789' }] };
  const forms = sensitiveForms(privateExample);
  const output = redact(forms.join('\n'), forms);
  for (const value of forms) assert.equal(output.includes(value), false);
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.abcdefgh12345678.ijklmnop12345678';
  assert.equal(redact(`Authorization: Bearer ${jwt}`, []).includes(jwt), false);
});

test('redaction remains safe across every stream split point', async () => {
  const forms = sensitiveForms(cohort);
  for (const form of forms) {
    for (let split = 1; split < form.length; split++) {
      const stream = privateLogFilter(forms); const chunks = [];
      stream.on('data', part => chunks.push(part));
      const done = new Promise(resolve => stream.on('end', resolve));
      stream.write(`before ${form.slice(0, split)}`); stream.write(form.slice(split)); stream.end(' after\n');
      await done;
      const output = Buffer.concat(chunks).toString();
      assert.equal(output, 'before [PRIVATE] after\n');
    }
  }
});

test('oversized output line is discarded instead of leaking a partial value', async () => {
  const stream = privateLogFilter(sensitiveForms(cohort)), output = [];
  stream.on('data', b => output.push(b)); const done = new Promise(resolve => stream.on('end', resolve));
  stream.write('z'.repeat(1_048_577)); stream.write(actors[0].password); stream.end('\nclean\n'); await done;
  assert.equal(Buffer.concat(output).toString(), '[OVERSIZED PRIVATE LINE]\nclean\n');
});

test('public reports accept only a verified phase prefix and never infer successful completion', () => {
  assert.deepEqual(validatePhaseProof({ schemaVersion: 1, phases: PHASES }), PHASES);
  for (const bad of [ { schemaVersion: 1, phases: ['A_login'] }, { schemaVersion: 1, phases: [PHASES[0], PHASES[0]] },
    { schemaVersion: 1, phases: PHASES, email: actors[0].email } ]) assert.throws(() => validatePhaseProof(bad));
  const report = { sha, format: 'android', phases: PHASES, passed: true, cleanup: true };
  const text = publicReport(report, sensitiveForms(cohort));
  assert.equal(JSON.parse(text).passed, true);
  for (const secret of sensitiveForms(cohort)) assert.equal(text.includes(secret), false);
  assert.throws(() => publicReport({ ...report, phases: [] }, []), /REPORT_SUCCESS/);
  assert.throws(() => publicReport({ ...report, cleanup: false }, []), /REPORT_SUCCESS/);
  assert.throws(() => publicReport({ ...report, failure: actors[0].email }, []), /REPORT_STATUS/);
});

test('public export refuses extra logs, hidden files, xcresult and private flow', () => {
  const allowed = ['report.json', ...Object.values(CAPTURES)];
  validatePublicDirectory(allowed, PHASES);
  for (const extra of ['.private', 'junit.xml', 'auth.xcresult', 'private.yaml', 'debug.log', '../auth-A-login.png']) {
    assert.throws(() => validatePublicDirectory([...allowed, extra], PHASES), /PUBLIC_WHITELIST/);
  }
  assert.throws(() => validatePublicDirectory(['report.json'], PHASES));
  validatePublicDirectory(['report.json'], []);
});

test('Android protocol has exactly two password submissions and four verified process-restoration phases', () => {
  const scenarios = androidFlows(cohort);
  assert.deepEqual(scenarios.map(s => s.phase), PHASES);
  assert.equal(scenarios.filter(s => s.restartProcess).length, 4);
  assert.deepEqual(scenarios.filter(s => s.capture).map(s => s.capture + '.png'), Object.values(CAPTURES));
  const whole = scenarios.map(s => s.flow).join('\n');
  for (const actor of actors) assert.equal(whole.split(`- inputText: ${JSON.stringify(actor.password)}`).length - 1, 1);
  assert.equal((whole.match(/id: "sign-in"/g) ?? []).length, 4); // scroll and single tap per actor
  assert.doesNotMatch(whole, /clearState: true|clearKeychain|resetApp|tapOn:\n\s+id: "onboarding-(?:start|save|complete)"/);
  for (const scenario of scenarios.filter(s => s.restartProcess)) {
    assert.match(scenario.flow, /clearState: false/);
    assert.doesNotMatch(scenario.flow, /inputText:/);
  }
});

test('Android takes screenshots only after authenticated identity assertions, never in login or logout steps', () => {
  for (const scenario of androidFlows(cohort)) {
    if (scenario.capture) {
      assert.ok(scenario.flow.indexOf('id: "account-environment"') < scenario.flow.indexOf('- takeScreenshot:'));
      assert.ok(scenario.flow.indexOf('- assertNotVisible:\n    id: "login-email"') < scenario.flow.indexOf('- takeScreenshot:'));
      assert.match(scenario.flow, /Reprendre mon inscription/);
    } else assert.doesNotMatch(scenario.flow, /takeScreenshot/);
  }
});

test('XCTest never types credentials or injects Auth; it uses its private environment and native Paste', async () => {
  const swift = await source('../../ios-auth-ui-tests/NativeAuthUITests/NativeAuthTests.swift');
  assert.match(swift, /JOLENE_AUTH_COHORT_JSON/); assert.match(swift, /UIPasteboard\.general\.setItems/);
  assert.match(swift, /defer \{ UIPasteboard\.general\.items = \[\] \}/);
  assert.doesNotMatch(swift, /typeText\(actor\.|typeText\(value|setSession|signInWithPassword|URLSession|debugDescription/);
  assert.match(swift, /self\.app\.state == \.notRunning/);
  assert.match(swift, /XCUIApplication\(bundleIdentifier: "app\.jolene\.nativepilot"\)/);
  assert.doesNotMatch(swift, /typeText\(|Enter URL|Add project by URL|app\.open\(/);
  assert.match(swift, /keyboardIntroductionChecked = true\s+try dismissFirstKeyboardIntroductionIfPresent\(\)/);
  assert.ok(swift.indexOf('try admitted(actor, excluding: other)') < swift.indexOf('record("auth-'));
});

test('driver does not print raw errors, credentials, args or export attachments wholesale', async () => {
  const runner = await source('./run.mjs');
  assert.doesNotMatch(runner, /console\.(?:log|error)|process\.stderr\.write\(error|JSON\.stringify\(error|exportedFileName\)\s*,\s*output/);
  assert.ok(runner.indexOf("'build-for-testing'") < runner.indexOf('JOLENE_AUTH_COHORT_JSON:'));
  assert.match(runner, /state\.code !== 1 \|\| state\.stdout\.trim\(\)/);
  assert.match(runner, /validatePublicDirectory\(await readdir\(output\), phases\)/);
  assert.match(runner, /rm\(temporary, \{ recursive: true, force: true \}\)/);
  assert.ok(runner.includes(EXPO_URL) === false); // URL comes from the fixed shared policy.
});

test('workflow is dispatch-only, main-only, reviewed SHA and protected environment; secret touches one step only', async () => {
  const workflow = await source('../../../.github/workflows/native-auth-staging.yml');
  assert.match(workflow, /workflow_dispatch:/); assert.doesNotMatch(workflow, /pull_request:|push:|schedule:/);
  assert.match(workflow, /environment: native-staging-auth/); assert.match(workflow, /cancel-in-progress: false/);
  assert.match(workflow, /max-parallel: 1/);
  assert.match(workflow, /e\.GITHUB_SHA,e\.GITHUB_WORKFLOW_SHA/);
  assert.ok(workflow.indexOf('node scripts/auth-staging/admit.mjs') < workflow.indexOf('run: npm ci'));
  assert.ok(workflow.indexOf('node scripts/auth-staging/admit.mjs') < workflow.indexOf('secrets.JOLENE_NATIVE_AUTH_COHORT_TEMP'));
  assert.equal((workflow.match(/secrets\.JOLENE_NATIVE_AUTH_COHORT_TEMP/g) ?? []).length, 1);
  assert.match(workflow, /node scripts\/auth-staging\/stage-input\.mjs cleanup/);
  assert.doesNotMatch(workflow, /path:.*(?:RUNNER_TEMP|xcresult|private)|actions: write|id-token: write/);
});

test('iOS initial bootstrap observes one prepared launch; four explicit restarts remain part of the protocol', async () => {
  const runner = await source('./run.mjs');
  const swift = await source('../../ios-auth-ui-tests/NativeAuthUITests/NativeAuthTests.swift');
  assert.match(runner, /\[\s*'simctl', 'launch', device, appId, '-RCT_jsLocation', '127\.0\.0\.1:8090',/);
  assert.match(runner, /await buildCompiledIosClient\(/);
  assert.match(runner, /platform === 'ios' \? COMPILED_APP_ID/);
  assert.equal((runner.match(/'simctl', 'launch'/g) ?? []).length, 1);
  assert.doesNotMatch(runner, /'simctl', 'openurl'/);
  const bootstrap = swift.split('private func prepareCompiledClient() throws {')[1].split('private func developerOverlaysAbsent')[0];
  assert.match(bootstrap, /self\.app\.state == \.runningForeground/);
  assert.ok(bootstrap.indexOf('self.app.state == .runningForeground') < bootstrap.indexOf('app.activate()'));
  assert.equal((swift.match(/app\.activate\(\)/g) ?? []).length, 1);
  assert.doesNotMatch(bootstrap, /app\.(?:launch|open)\(|\.tap\(|toolsSwitch|xmark/);
  assert.match(bootstrap, /self\.visible\(self\.element\("login-scroll"\)\)/);
  assert.match(bootstrap, /self\.developerOverlaysAbsent\(\)/);
  const overlays = swift.split('private func developerOverlaysAbsent() -> Bool {')[1].split('private func element')[0];
  assert.match(overlays, /return !proceed\.exists && !app\.staticTexts\["SDK version: 57\.0\.0"\]\.exists/);
  const restart = swift.split('private func restartProcess() throws {')[1].split('private func dismissFirstKeyboardIntroductionIfPresent')[0];
  assert.match(restart, /app\.launchArguments = \["-RCT_jsLocation", "127\.0\.0\.1:8090"\]/);
  assert.ok(restart.indexOf('app.terminate()') < restart.indexOf('self.app.state == .notRunning'));
  assert.ok(restart.indexOf('self.app.state == .notRunning') < restart.indexOf('app.launch()'));
  assert.doesNotMatch(restart, /login\(|paste\(|clearState|clearKeychain|app\.open\(/);
  const circuit = swift.split('for index in 0..<2 {')[1].split('private func login')[0];
  assert.equal((circuit.match(/try restartProcess\(\)/g) ?? []).length, 2); // two per actor = four, never retries
  assert.equal((circuit.match(/try login\(actor\)/g) ?? []).length, 1);
});

test('initial launch and four genuine relaunches carry only the local Metro address for the compiled client', async () => {
  const runner = await source('./run.mjs');
  const swift = await source('../../ios-auth-ui-tests/NativeAuthUITests/NativeAuthTests.swift');
  const initial = runner.match(/'simctl', 'launch', device, appId, ([\s\S]*?)\], \{ timeout: 120_000 \}/)?.[1];
  const restart = swift.match(/app\.launchArguments = \[([\s\S]*?)\]/)?.[1];
  assert.equal(initial?.replace(/\s/g, ''), "'-RCT_jsLocation','127.0.0.1:8090',");
  assert.equal(restart?.replace(/\s/g, ''), '"-RCT_jsLocation","127.0.0.1:8090"');
  for (const args of [initial, restart]) assert.doesNotMatch(args, /cohort|actor|password|email|token|process\.env|ProcessInfo/i);
  assert.doesNotMatch(swift, /UserDefaults|setPersistentDomain|app\.launchEnvironment/);
});

test('both drivers keep public captures outside credentials, professional spaces and overlays', async () => {
  const swift = await source('../../ios-auth-ui-tests/NativeAuthUITests/NativeAuthTests.swift');
  const record = swift.split('private func record(_ name: String) throws {')[1].split('private func visible')[0];
  assert.ok(record.indexOf('!self.element("login-password").exists') < record.indexOf('XCTAttachment(screenshot:'));
  assert.match(record, /self\.app\.keyboards\.count == 0/);
  assert.match(record, /com\.apple\.springboard/);
  assert.match(swift, /self\.app\.staticTexts\["Reprendre mon inscription"\]\.exists/);
  for (const flow of androidFlows(cohort).filter(s => s.capture).map(s => s.flow)) {
    for (const id of ['login-email', 'login-password', 'tab-establishment-home', 'tab-contracts']) {
      assert.ok(flow.indexOf(`- assertNotVisible:\n    id: "${id}"`) < flow.indexOf('- takeScreenshot:'));
    }
  }
});

test('private staging uses only synthetic canaries, restrictive files and generic failure text', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'jolene-auth-stage-canary-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const script = fileURLToPath(new URL('./stage-input.mjs', import.meta.url));
  const env = { RUNNER_TEMP: folder, JOLENE_NATIVE_AUTH_COHORT: JSON.stringify(cohort) };
  const staged = spawnSync(process.execPath, [script], { env, encoding: 'utf8' });
  assert.equal(staged.status, 0); assert.equal(staged.stdout, ''); assert.equal(staged.stderr, '');
  const path = join(folder, 'jolene-native-auth-input.private.json');
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), cohort);
  const duplicate = spawnSync(process.execPath, [script], { env, encoding: 'utf8' });
  assert.equal(duplicate.status, 1); assert.equal(duplicate.stdout, '');
  assert.equal(duplicate.stderr, 'AUTH_PRIVATE_INPUT_STEP_FAILED\n');
  const cleanup = spawnSync(process.execPath, [script, 'cleanup'], { env: { RUNNER_TEMP: folder }, encoding: 'utf8' });
  assert.equal(cleanup.status, 0); assert.equal(cleanup.stdout, ''); assert.equal(cleanup.stderr, '');
  await assert.rejects(stat(path), { code: 'ENOENT' });
});

test('empty, linked and public-readable private inputs fail closed before the runner starts', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'jolene-auth-empty-canary-'));
  t.after(() => rm(folder, { recursive: true, force: true }));
  const input = join(folder, 'jolene-native-auth-input.private.json');
  const target = join(folder, 'canary.json');
  await writeFile(target, JSON.stringify(cohort), { mode: 0o600, flag: 'wx' });
  const fixtures = [
    () => writeFile(input, '', { mode: 0o600, flag: 'wx' }),
    () => symlink(target, input),
    () => link(target, input),
    () => writeFile(input, JSON.stringify(cohort), { mode: 0o644, flag: 'wx' }),
  ];
  for (const fixture of fixtures) {
    await fixture();
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('./launch.mjs', import.meta.url))], {
      env: { RUNNER_TEMP: folder }, encoding: 'utf8', timeout: 5000,
    });
    assert.equal(result.status, 1); assert.equal(result.stdout, '');
    assert.equal(result.stderr, 'AUTH_PRIVATE_INPUT_REQUIRED\n');
    await rm(input);
  }
});

test('private xctestrun injection writes 0600, only into the single UI test runner, with no stdout', async t => {
  const folder = await mkdtemp(join(tmpdir(), 'jolene-auth-canary-')); t.after(() => rm(folder, { recursive: true, force: true }));
  const input = join(folder, 'original.xctestrun'), destination = join(folder, 'private.xctestrun');
  const fixture = { NativeAuthUITests: { TestBundlePath: '__TESTROOT__/NativeAuthUITests.xctest', IsUITestBundle: true }, __xctestrun_metadata__: { FormatVersion: 2 } };
  const write = spawnSync('python3', ['-c', 'import json,plistlib,sys;plistlib.dump(json.load(sys.stdin),open(sys.argv[1],"wb"))', input], { input: JSON.stringify(fixture) });
  assert.equal(write.status, 0);
  const payload = { source: input, destination, environment: { JOLENE_AUTH_COHORT_JSON: JSON.stringify(cohort), JOLENE_AUTH_FORMAT: 'iphone' } };
  const injected = spawnSync('python3', [fileURLToPath(new URL('./inject-xctestrun.py', import.meta.url))], { input: JSON.stringify(payload), encoding: 'utf8' });
  assert.equal(injected.status, 0); assert.equal(injected.stdout, ''); assert.equal(injected.stderr, '');
  assert.equal((await stat(destination)).mode & 0o777, 0o600);
  const contents = await readFile(destination, 'utf8');
  assert.match(contents, /JOLENE_AUTH_COHORT_JSON/); assert.doesNotMatch(contents, /UITargetAppEnvironmentVariables/);
  const repeat = spawnSync('python3', [fileURLToPath(new URL('./inject-xctestrun.py', import.meta.url))], { input: JSON.stringify(payload), encoding: 'utf8' });
  assert.equal(repeat.status, 1); assert.equal(repeat.stdout, '');
  assert.equal(repeat.stderr, 'PRIVATE_XCTEST_PREPARATION_FAILED\n');
});

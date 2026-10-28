import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, cpSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import patch from './rn-text-input-patch.cjs';
import plugin from '../plugins/with-rn-text-input-source.cjs';

const project = resolve(import.meta.dirname, '..');
const sourceProject = process.env.RN_PATCH_TEST_FIXTURE || project;
const manifest = JSON.parse(readFileSync(resolve(project, 'patches/react-native-0.86.3-text-input.json'), 'utf8'));
const env = { ...process.env };
for (const key of Object.keys(env)) if (key.startsWith('RCT_TESTONLY_RNCORE_') || ['RCT_USE_RN_DEP', 'RCT_USE_PREBUILT_RNCORE'].includes(key)) delete env[key];
function fixture(t) {
  const root = mkdtempSync(resolve(tmpdir(), 'rn-input-adoption-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const file of ['package.json', 'package-lock.json']) copyFileSync(resolve(project, file), resolve(root, file));
  for (const name of ['react-native', 'expo']) {
    mkdirSync(resolve(root, 'node_modules', name), { recursive: true });
    copyFileSync(resolve(sourceProject, 'node_modules', name, 'package.json'), resolve(root, 'node_modules', name, 'package.json'));
  }
  for (const file of manifest.files) {
    const target = resolve(root, 'node_modules/react-native', file.path);
    mkdirSync(dirname(target), { recursive: true });
    const installed = readFileSync(resolve(sourceProject, 'node_modules/react-native', file.path));
    // Both a clean installation and one already patched by npm postinstall are
    // supported as fixtures; restore only this temporary copy for baseline tests.
    writeFileSync(target, installed);
  }
  cpSync(resolve(project, 'patches'), resolve(root, 'patches'), { recursive: true });
  for (const file of ['scripts/rn-text-input-patch.cjs', 'plugins/with-rn-text-input-source.cjs']) {
    mkdirSync(dirname(resolve(root, file)), { recursive: true }); copyFileSync(resolve(project, file), resolve(root, file));
  }
  try { patch.verifyPatched(root, {}); execFileSync('git', ['apply', '--reverse', resolve(root, 'patches/react-native-0.86.3-text-input.patch')], { cwd: resolve(root, 'node_modules/react-native') }); } catch (error) {
    if (!error.message.includes('Correctif RN absent')) throw error;
  }
  return root;
}
const template = execFileSync('tar', ['-xOzf', resolve(sourceProject, 'node_modules/expo/template.tgz'), 'package/ios/Podfile'], { encoding: 'utf8' });
function iosFixture(root) {
  mkdirSync(resolve(root, 'ios/Pods/Pods.xcodeproj'), { recursive: true });
  writeFileSync(resolve(root, 'ios/Podfile'), plugin.configurePodfile(template));
  writeFileSync(resolve(root, 'ios/Podfile.properties.json'), JSON.stringify({ 'ios.buildReactNativeFromSource': 'true' }));
  writeFileSync(resolve(root, 'ios/Podfile.lock'), 'PODS:\n  - React-Core (0.86.3)\n');
  writeFileSync(resolve(root, 'ios/Pods/Pods.xcodeproj/project.pbxproj'), 'RCTTextInputComponentView.mm in Sources\nRCTAttributedTextUtils.mm in Sources\n');
}

test('postinstall applies exactly once and the build guard requires generated source Pods', t => {
  const root = fixture(t);
  assert.throws(() => patch.verifyPatched(root, {}), /Correctif RN absent/);
  const cli = resolve(root, 'scripts/rn-text-input-patch.cjs');
  assert.match(execFileSync(process.execPath, [cli], { env, encoding: 'utf8' }), /: patched/);
  assert.match(execFileSync(process.execPath, [cli], { env, encoding: 'utf8' }), /already-patched/);
  assert.equal(patch.verifyPatched(root, {}).state, 'patched');
  assert.throws(() => patch.verifyBuild(root, {}));
  iosFixture(root);
  assert.deepEqual(patch.verifyBuild(root, {}).files, manifest.files.map(file => ({ path: file.path, sha256: file.candidateSha256 })));
  writeFileSync(resolve(root, 'ios/Podfile.lock'), 'React-Core-prebuilt');
  assert.throws(() => patch.verifyBuild(root, {}), /Projet Pods/);
});

test('unknown, partial or newer sources fail without repairing other files', t => {
  const root = fixture(t);
  patch.applyPatch(root);
  const first = resolve(root, 'node_modules/react-native', manifest.files[0].path);
  const intact = readFileSync(first);
  writeFileSync(resolve(root, 'node_modules/react-native', manifest.files[1].path), 'unexpected');
  assert.throws(() => patch.applyPatch(root), /mixtes ou modifiées/);
  assert.deepEqual(readFileSync(first), intact);
  writeFileSync(resolve(root, 'node_modules/react-native/package.json'), '{"version":"0.86.4"}');
  assert.throws(() => patch.applyPatch(root), /réservé/);
});

test('a corrupted patch is rejected before any source write', t => {
  const root = fixture(t);
  const first = resolve(root, 'node_modules/react-native', manifest.files[0].path);
  const before = readFileSync(first);
  writeFileSync(resolve(root, 'patches/react-native-0.86.3-text-input.patch'), 'unexpected');
  assert.throws(() => patch.applyPatch(root), /Correctif ou manifeste/);
  assert.deepEqual(readFileSync(first), before);
});

test('source configuration accepts absent/default flags and rejects every contradictory override', () => {
  patch.requireBuildEnvironment({});
  patch.requireBuildEnvironment({ RCT_USE_PREBUILT_RNCORE: '0', RCT_USE_RN_DEP: '1' });
  for (const invalid of [{ RCT_USE_PREBUILT_RNCORE: '1' }, { RCT_USE_RN_DEP: '0' }, { RCT_USE_RN_DEP: '' },
    { RCT_TESTONLY_RNCORE_VERSION: '' }, { RCT_TESTONLY_RNCORE_TARBALL_PATH: 'other' }]) {
    assert.throws(() => patch.requireBuildEnvironment(invalid));
  }
});

test('Podfile transformation is idempotent and rejects changed templates or guard tampering', () => {
  const once = plugin.configurePodfile(template);
  assert.equal(plugin.configurePodfile(once), once);
  assert.equal(once.slice(plugin.podfileGuard.length), template);
  assert.throws(() => plugin.configurePodfile(template.replace("ENV['RCT_USE_RN_DEP'] ||=", "ENV['RCT_USE_RN_DEP'] =")));
  assert.throws(() => plugin.configurePodfile(once.replace("||= '1'", "||= '0'")));
});

test('the actual Ruby guard fixes defaults and rejects a changed environment at pod-install time', t => {
  const root = fixture(t); patch.applyPatch(root); iosFixture(root);
  const ruby = resolve(root, 'ios/guard-test.rb');
  // Run only the guard and exact environment assignments, not CocoaPods or the
  // template's requires; this is a pure subprocess check, never a native build.
  const assignments = template.split('\n').filter(line => /^ENV\['RCT_USE_(RN_DEP|PREBUILT_RNCORE)'\]/.test(line)).join('\n');
  writeFileSync(ruby, plugin.podfileGuard + assignments + '\nputs [ENV["RCT_USE_PREBUILT_RNCORE"], ENV["RCT_USE_RN_DEP"]].join(":")\n');
  assert.match(execFileSync('ruby', [ruby], { env, encoding: 'utf8' }), /0:1\n$/);
  for (const bad of [{ RCT_USE_PREBUILT_RNCORE: '1' }, { RCT_USE_RN_DEP: '0' }, { RCT_TESTONLY_RNCORE_VERSION: '' }]) {
    assert.throws(() => execFileSync('ruby', [ruby], { env: { ...env, ...bad }, stdio: 'pipe' }));
  }
});

test('locked Expo mods set only source configuration and preserve other Podfile properties', async t => {
  const root = fixture(t); patch.applyPatch(root);
  const configured = plugin({ name: 'Jolene', slug: 'jolene' });
  const properties = await configured.mods.ios.podfileProperties({ modRequest: { projectRoot: root }, modResults: { existing: 'retained' } });
  assert.deepEqual(properties.modResults, { existing: 'retained', 'ios.buildReactNativeFromSource': 'true' });
  const podfile = await configured.mods.ios.podfile({ modRequest: { projectRoot: root }, modResults: { language: 'rb', contents: template } });
  assert.equal(podfile.modResults.contents, plugin.podfileGuard + template);
  assert.equal(configured.mods.android, undefined);
});

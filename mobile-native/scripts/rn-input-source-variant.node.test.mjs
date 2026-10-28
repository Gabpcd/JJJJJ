import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, cpSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { requireSourceVariant, prepareSourceVariant, verifySourceVariant } from './rn-input-source-variant.mjs';

const env = { NATIVE_RN_SOURCE_VARIANT: 'baseline', RCT_USE_PREBUILT_RNCORE: '0', RCT_USE_RN_DEP: '1' };
test('source comparison refuses prebuilt, unknown and test-only core overrides', () => {
  for (const variant of ['baseline', 'patched']) assert.equal(requireSourceVariant({ ...env, NATIVE_RN_SOURCE_VARIANT: variant }), variant);
  for (const invalid of [{ NATIVE_RN_SOURCE_VARIANT: '' }, { RCT_USE_PREBUILT_RNCORE: '1' }, { RCT_USE_RN_DEP: '0' },
    { RCT_TESTONLY_RNCORE_TARBALL_PATH: '' }, { RCT_TESTONLY_RNCORE_VERSION: '0.86.3' }]) {
    assert.throws(() => requireSourceVariant({ ...env, ...invalid }));
  }
});

// Optional fixture root: copies only the three pinned files, never modifies the
// supplied installation. This also works in CI after a normal locked npm ci.
const installedRoot = process.env.RN_SOURCE_TEST_FIXTURE || resolve(import.meta.dirname, '../node_modules/react-native');
const reference = resolve(import.meta.dirname, '../input-reference');
function fixture(t) {
  const temporaryRoot = mkdtempSync(resolve(tmpdir(), 'rn-source-variant-test-'));
  t.after(() => rmSync(temporaryRoot, { recursive: true, force: true }));
  const root = resolve(temporaryRoot, 'react-native');
  const files = JSON.parse(readFileSync(resolve(reference, 'rn-source-manifest.json'), 'utf8')).files;
  for (const file of ['package.json', ...files.map(item => item.path)]) cpSync(resolve(installedRoot, file), resolve(root, file), { recursive: true });
  return { root, reference, temporaryRoot };
}
test('baseline is byte-identical; patched applies the pinned upstream delta in staging', t => {
  const options = fixture(t);
  const before = prepareSourceVariant({ ...options, env });
  assert.deepEqual(before.before, before.files);
  const patched = prepareSourceVariant({ ...options, env: { ...env, NATIVE_RN_SOURCE_VARIANT: 'patched' } });
  assert.deepEqual(patched.before, before.files);
  assert.equal(patched.files.length, 3);
  assert.ok(patched.files.every((file, i) => file.sha256 !== before.files[i].sha256));
  assert.deepEqual(verifySourceVariant({ ...options, variant: 'patched' }).files, patched.files);
  assert.throws(() => prepareSourceVariant({ ...options, env }));
});
test('source corruption aborts before writing any source', t => {
  const options = fixture(t);
  const manifest = JSON.parse(readFileSync(resolve(reference, 'rn-source-manifest.json'), 'utf8'));
  const intact = readFileSync(resolve(options.root, manifest.files[0].path));
  writeFileSync(resolve(options.root, manifest.files[2].path), 'unexpected source');
  assert.throws(() => prepareSourceVariant({ ...options, env: { ...env, NATIVE_RN_SOURCE_VARIANT: 'patched' } }));
  assert.deepEqual(readFileSync(resolve(options.root, manifest.files[0].path)), intact);
});
test('patch corruption is rejected even for a baseline', t => {
  const options = fixture(t);
  const badReference = resolve(options.temporaryRoot, 'reference');
  cpSync(reference, badReference, { recursive: true });
  writeFileSync(resolve(badReference, 'rn-0.86.3-noop-attributed-echo.patch'), 'unexpected patch');
  assert.throws(() => prepareSourceVariant({ ...options, reference: badReference, env }));
});

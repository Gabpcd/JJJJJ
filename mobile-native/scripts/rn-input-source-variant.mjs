import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const patchHash = '2a0d5e639d0593f02e585ea7b038384633e8519d188401e4a34155aad0d0d85a';
const paths = [
  'React/Fabric/Mounting/ComponentViews/TextInput/RCTTextInputComponentView.mm',
  ...['h', 'mm'].map(ext => `ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/RCTAttributedTextUtils.${ext}`),
];
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');

export function requireSourceVariant(env) {
  if (!['baseline', 'patched'].includes(env.NATIVE_RN_SOURCE_VARIANT)
    || env.RCT_USE_PREBUILT_RNCORE !== '0' || env.RCT_USE_RN_DEP !== '1'
    || Object.keys(env).some(key => key.startsWith('RCT_TESTONLY_RNCORE_'))) {
    throw new Error('La comparaison RN source exige baseline/patched, RNCore=0, RNDep=1 et aucun override RNCore.');
  }
  return env.NATIVE_RN_SOURCE_VARIANT;
}

export function verifySourceVariant({ root, reference, variant }) {
  if (!['baseline', 'patched'].includes(variant)) throw new Error('Variante RN inconnue.');
  const manifest = JSON.parse(readFileSync(resolve(reference, 'rn-source-manifest.json'), 'utf8'));
  const patch = resolve(reference, 'rn-0.86.3-noop-attributed-echo.patch');
  if (manifest.reactNativeVersion !== '0.86.3' || manifest.patchSha256 !== patchHash
    || hash(patch) !== patchHash || JSON.stringify(manifest.files.map(file => file.path)) !== JSON.stringify(paths)
    || JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8')).version !== '0.86.3') {
    throw new Error('Source RN ou correctif upstream différent de la comparaison verrouillée.');
  }
  const files = manifest.files.map(file => {
    const actual = hash(resolve(root, file.path));
    if (actual !== (variant === 'patched' ? file.candidateSha256 : file.sha256)) {
      throw new Error(`Empreinte source RN inattendue : ${file.path}`);
    }
    return { path: file.path, sha256: actual };
  });
  return { variant, reactNativeVersion: manifest.reactNativeVersion, upstreamPR: manifest.upstreamPR,
    upstreamHead: manifest.upstreamHead, patchSha256: patchHash, files };
}

// Only the caller's fresh CI npm installation is changed. Stage and verify every
// hunk before writing any source; both variants keep the exact package lock.
export function prepareSourceVariant({ root, reference, env, temporaryRoot }) {
  const variant = requireSourceVariant(env);
  const before = verifySourceVariant({ root, reference, variant: 'baseline' });
  if (variant === 'patched') {
    const stage = mkdtempSync(resolve(temporaryRoot, 'rn-source-patch-'));
    copyFileSync(resolve(root, 'package.json'), resolve(stage, 'package.json'));
    for (const file of before.files) {
      mkdirSync(dirname(resolve(stage, file.path)), { recursive: true });
      copyFileSync(resolve(root, file.path), resolve(stage, file.path));
    }
    const patch = resolve(reference, 'rn-0.86.3-noop-attributed-echo.patch');
    for (const args of [['apply', '--check', patch], ['apply', patch]]) {
      execFileSync('git', args, { cwd: stage, timeout: 10_000, stdio: 'pipe' });
    }
    verifySourceVariant({ root: stage, reference, variant });
    for (const file of before.files) copyFileSync(resolve(stage, file.path), resolve(root, file.path));
  }
  return { ...verifySourceVariant({ root, reference, variant }), before: before.files,
    nativeFlags: { RCT_USE_PREBUILT_RNCORE: '0', RCT_USE_RN_DEP: '1' } };
}

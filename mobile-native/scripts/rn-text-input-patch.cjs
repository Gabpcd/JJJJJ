const { execFileSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync } = require('node:fs');
const { dirname, resolve } = require('node:path');
const { tmpdir } = require('node:os');

const PATCH_SHA = '2a0d5e639d0593f02e585ea7b038384633e8519d188401e4a34155aad0d0d85a';
const SOURCE_PATHS = [
  'React/Fabric/Mounting/ComponentViews/TextInput/RCTTextInputComponentView.mm',
  ...['h', 'mm'].map(ext => `ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/RCTAttributedTextUtils.${ext}`),
];
const json = path => JSON.parse(readFileSync(path, 'utf8'));
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');

function requireBuildEnvironment(env) {
  for (const [key, value] of Object.entries({ RCT_USE_PREBUILT_RNCORE: '0', RCT_USE_RN_DEP: '1' })) {
    if (env[key] !== undefined && env[key] !== value) throw new Error(`${key} doit valoir ${value} ou être absent.`);
  }
  if (Object.keys(env).some(key => key.startsWith('RCT_TESTONLY_RNCORE_'))) {
    throw new Error('Les overrides RCT_TESTONLY_RNCORE_* sont incompatibles avec le correctif RN source.');
  }
}

function inspect(project) {
  const pkg = json(resolve(project, 'package.json'));
  const lock = json(resolve(project, 'package-lock.json'));
  for (const [name, version] of [['react-native', '0.86.3'], ['expo', '57.0.31']]) {
    if (pkg.dependencies[name] !== version || lock.packages['']?.dependencies?.[name] !== version
      || lock.packages[`node_modules/${name}`]?.version !== version
      || json(resolve(project, 'node_modules', name, 'package.json')).version !== version) {
      throw new Error(`Correctif RN source réservé à ${name}@${version} verrouillé et installé.`);
    }
  }
  const reference = resolve(project, 'patches/react-native-0.86.3-text-input.json');
  const patch = resolve(project, 'patches/react-native-0.86.3-text-input.patch');
  const manifest = json(reference);
  if (manifest.reactNativeVersion !== '0.86.3' || manifest.patchSha256 !== PATCH_SHA || hash(patch) !== PATCH_SHA
    || JSON.stringify(manifest.files.map(file => file.path)) !== JSON.stringify(SOURCE_PATHS)) {
    throw new Error('Correctif ou manifeste RN inconnu.');
  }
  const root = resolve(project, 'node_modules/react-native');
  const files = manifest.files.map(file => ({ ...file, actual: hash(resolve(root, file.path)) }));
  const state = files.every(file => file.actual === file.sha256) ? 'original'
    : files.every(file => file.actual === file.candidateSha256) ? 'patched' : 'unknown';
  if (state === 'unknown') throw new Error('Sources RN mixtes ou modifiées : aucune réparation partielle automatique.');
  return { root, patch, files, state };
}

function verifyPatched(project, env = process.env) {
  requireBuildEnvironment(env);
  const inspected = inspect(project);
  if (inspected.state !== 'patched') throw new Error('Correctif RN absent : exécuter npm ci avec ses scripts ou node scripts/rn-text-input-patch.cjs.');
  return inspected;
}

function applyPatch(project) {
  const inspected = inspect(project);
  if (inspected.state === 'patched') return { state: 'already-patched' };
  const stage = mkdtempSync(resolve(tmpdir(), 'jolene-rn-text-input-'));
  try {
    for (const file of inspected.files) {
      mkdirSync(dirname(resolve(stage, file.path)), { recursive: true });
      copyFileSync(resolve(inspected.root, file.path), resolve(stage, file.path));
    }
    for (const args of [['apply', '--check', inspected.patch], ['apply', inspected.patch]]) {
      execFileSync('git', args, { cwd: stage, timeout: 10_000, stdio: 'pipe' });
    }
    for (const file of inspected.files) {
      if (hash(resolve(stage, file.path)) !== file.candidateSha256) throw new Error('Résultat du patch RN inattendu.');
    }
    for (const file of inspected.files) copyFileSync(resolve(stage, file.path), resolve(inspected.root, file.path));
    if (inspect(project).state !== 'patched') throw new Error('Écriture du patch RN non confirmée.');
    return { state: 'patched' };
  } finally { rmSync(stage, { recursive: true, force: true }); }
}

function verifyBuild(project, env = process.env) {
  const inspected = verifyPatched(project, env);
  const properties = json(resolve(project, 'ios/Podfile.properties.json'));
  const podfile = readFileSync(resolve(project, 'ios/Podfile'), 'utf8');
  const { podfileGuard } = require('../plugins/with-rn-text-input-source.cjs');
  const lock = readFileSync(resolve(project, 'ios/Podfile.lock'), 'utf8');
  const pods = readFileSync(resolve(project, 'ios/Pods/Pods.xcodeproj/project.pbxproj'), 'utf8');
  if (properties['ios.buildReactNativeFromSource'] !== 'true' || !podfile.startsWith(podfileGuard)
    || lock.includes('React-Core-prebuilt')
    || !['RCTTextInputComponentView.mm', 'RCTAttributedTextUtils.mm'].every(name => pods.includes(`${name} in Sources`))) {
    throw new Error('Projet Pods absent ou incompatible avec les deux sources RN corrigées.');
  }
  return { reactNative: '0.86.3', expo: '57.0.31', source: true, patchSha256: PATCH_SHA,
    files: inspected.files.map(file => ({ path: file.path, sha256: file.actual })) };
}

module.exports = { requireBuildEnvironment, applyPatch, verifyPatched, verifyBuild };
if (require.main === module) {
  const project = resolve(__dirname, '..');
  try {
    const mode = process.argv[2];
    if (process.argv.length > 3 || (mode && !['--verify', '--verify-build'].includes(mode))) throw new Error('Mode correctif RN inconnu.');
    const result = mode === '--verify-build' ? verifyBuild(project) : mode === '--verify' ? verifyPatched(project) : applyPatch(project);
    console.log(`RN TextInput 0.86.3 : ${result.state || 'source-build-verified'}`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

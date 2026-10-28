import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Only creates a synthetic JS experience and reuses the existing CI simulator
// runner. No prebuild, native RN build, SDK installation, delivery or supplier.
if (process.env.GITHUB_ACTIONS !== 'true' || process.platform !== 'darwin'
  || process.env.NATIVE_PILOT_SCENARIO !== 'input-reference' || !process.env.RUNNER_TEMP) {
  throw new Error('Témoin input-reference réservé au runner macOS GitHub Actions.');
}
const sourceProject = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.env.INPUT_REFERENCE_OUTPUT_DIR || resolve(sourceProject, 'test-results', 'rn-input-reference'));
mkdirSync(output, { recursive: true });
const result = { source: 'synthetic-rn-input-reference', scenario: 'input-reference',
  started: new Date().toISOString(), stage: 'prepare', success: false,
  productScenario: false, contractsVerdictChanged: false, production: false, physicalDevice: false };
const sha256 = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const save = (name, value) => writeFileSync(resolve(output, name), JSON.stringify(value, null, 2));

try {
  const packageJson = JSON.parse(readFileSync(resolve(sourceProject, 'package.json'), 'utf8'));
  const lock = JSON.parse(readFileSync(resolve(sourceProject, 'package-lock.json'), 'utf8'));
  const modules = realpathSync(resolve(sourceProject, 'node_modules'));
  const versions = {};
  for (const name of ['expo', 'react', 'react-native']) {
    const installed = JSON.parse(readFileSync(resolve(modules, name, 'package.json'), 'utf8')).version;
    if (installed !== packageJson.dependencies[name] || installed !== lock.packages[`node_modules/${name}`]?.version) {
      throw new Error(`Le paquet ${name} installé ne correspond pas au verrouillage.`);
    }
    versions[name] = installed;
  }
  const sourceSha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: sourceProject, encoding: 'utf8', timeout: 10_000 }).trim();
  if (!/^[a-f0-9]{40}$/.test(sourceSha) || sourceSha !== process.env.INPUT_REFERENCE_SOURCE_SHA) {
    throw new Error('La tête du checkout ne correspond pas à la provenance demandée.');
  }
  const project = mkdtempSync(resolve(realpathSync(process.env.RUNNER_TEMP), 'jolene-rn-input-reference-'));
  cpSync(resolve(sourceProject, 'scripts'), resolve(project, 'scripts'), { recursive: true });
  cpSync(resolve(sourceProject, 'ios-ui-tests'), resolve(project, 'ios-ui-tests'), { recursive: true });
  copyFileSync(resolve(sourceProject, 'input-reference', 'index.tsx'), resolve(project, 'index.tsx'));
  // The copied Xcode project already lists this path. Replace only its temporary
  // copy with the separate reference class; the repository's Contracts test is intact.
  const syntheticTest = resolve(project, 'ios-ui-tests', 'NativePilotUITests', 'NativePilotTests.swift');
  copyFileSync(resolve(sourceProject, 'input-reference', 'NativeInputReferenceTests.swift'), syntheticTest);
  symlinkSync(modules, resolve(project, 'node_modules'), 'dir');
  writeFileSync(resolve(project, 'package.json'), JSON.stringify({
    name: 'jolene-input-reference-ci', version: '0.1.0', private: true, main: 'index.tsx',
    dependencies: packageJson.dependencies, devDependencies: packageJson.devDependencies,
  }, null, 2));
  writeFileSync(resolve(project, 'app.json'), JSON.stringify({ expo: {
    name: 'Jolene Input Reference', slug: 'jolene-input-reference-ci', version: '0.1.0',
    platforms: ['ios'], orientation: 'portrait',
  } }, null, 2));
  // Metro must watch the real target of node_modules, while resolving React only
  // from the locked native installation. No Jolene source is imported by the entry.
  writeFileSync(resolve(project, 'metro.config.js'), `
const { getDefaultConfig } = require('expo/metro-config');
const path = require('node:path');
const config = getDefaultConfig(__dirname);
config.watchFolders = [${JSON.stringify(modules)}];
config.resolver.nodeModulesPaths = [path.resolve(__dirname, 'node_modules')];
config.resolver.extraNodeModules = {
  react: path.resolve(__dirname, 'node_modules/react'),
  'react-native': path.resolve(__dirname, 'node_modules/react-native'),
};
module.exports = config;
`);
  save('provenance.json', { ...result, sourceSha, versions,
    xcode: execFileSync('xcodebuild', ['-version'], { encoding: 'utf8', timeout: 30_000 }).trim(),
    host: 'expo-go', appId: 'host.exp.Exponent', platform: 'iphonesimulator',
    test: 'NativePilotUITests/NativeInputReferenceTests/testFields',
    packageLockSha256: sha256(resolve(sourceProject, 'package-lock.json')),
    entrySha256: sha256(resolve(project, 'index.tsx')), testSha256: sha256(syntheticTest),
    originalContractsTestSha256: sha256(resolve(sourceProject, 'ios-ui-tests', 'NativePilotUITests', 'NativePilotTests.swift')),
    runnerSha256: sha256(resolve(project, 'scripts', 'run-pilot-ci.mjs')),
    selectorSha256: sha256(resolve(project, 'scripts', 'native-scenarios.mjs')),
    nodeModulesLinked: true, supplierCalls: false, nativeRnBuild: false,
  });
  result.stage = 'runner';
  const child = spawn(process.execPath, [resolve(project, 'scripts', 'run-pilot-ci.mjs'), 'ios'], {
    cwd: project, stdio: 'inherit', env: {
      ...process.env, PILOT_OUTPUT_DIR: output, NATIVE_PILOT_SCENARIO: 'input-reference',
      NATIVE_INPUT_REFERENCE_PROJECT: '1', NATIVE_IOS_HOST: 'expo-go', IOS_DEVICE_FAMILY: 'iphone',
      NATIVE_CONTRACTS_ORIENTATION: '', NATIVE_DOCUMENTS_ORIENTATION: '',
      EXPO_PUBLIC_JOLENE_MODE: 'demo', EXPO_PUBLIC_JOLENE_CONTRACTS_SCENARIO: '0',
      EXPO_PUBLIC_JOLENE_DOCUMENTS_SCENARIO: '0', EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS: '0',
      EXPO_PUBLIC_SUPABASE_URL: '', EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: '',
      EXPO_NO_DOTENV: '1', EXPO_NO_TELEMETRY: '1',
    },
  });
  const outcome = await new Promise((res, rej) => {
    child.once('error', rej);
    child.once('close', (code, signal) => res({ code, signal }));
  });
  result.command = outcome;
  const report = JSON.parse(readFileSync(resolve(output, 'result.json'), 'utf8'));
  if (outcome.code !== 0 || outcome.signal || report.success !== true || report.scenario !== 'input-reference'
    || report.evidence !== 'synthetic-rn-input-reference' || report.productScenario !== false
    || report.contractsVerdictChanged !== false || report.stage !== 'complete') {
    throw new Error('Le témoin RN ne confirme pas son unique XCTest réussi et ses six captures.');
  }
  result.success = true;
  result.stage = 'complete';
} catch (error) {
  result.error = String(error);
  console.error(error);
  process.exitCode = 1;
} finally {
  save('reference-result.json', { ...result, ended: new Date().toISOString() });
}

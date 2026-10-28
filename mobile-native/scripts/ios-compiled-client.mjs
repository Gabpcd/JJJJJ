import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, readFileSync, readdirSync, statSync, statfsSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import rnPatch from './rn-text-input-patch.cjs';

export const COMPILED_APP_ID = 'app.jolene.nativepilot';
const gib = 1024 ** 3;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export function requireSimulatorBuildSpace(project, minimumGiB = 5) {
  const disk = statfsSync(project);
  const available = disk.bavail * disk.bsize;
  if (available < minimumGiB * gib) throw new Error(`Compilation simulateur : moins de ${minimumGiB} Gio libres.`);
  return available;
}

/** Disposable CI checkout only. No delivery build, dependency upgrade or Expo Go fallback. */
export async function buildCompiledIosClient({ project, output, device, env, run }) {
  if (env.GITHUB_ACTIONS !== 'true' || process.platform !== 'darwin' || !env.RUNNER_TEMP
    || !/^[0-9A-F-]{36}$/i.test(device)) throw new Error('Compilation réservée au simulateur CI identifié.');
  rnPatch.verifyPatched(project, env);
  const sourceSha = (await run('git', ['rev-parse', 'HEAD'])).stdout.trim();
  if (!/^[a-f0-9]{40}$/.test(env.NATIVE_IOS_SOURCE_SHA || '') || sourceSha !== env.NATIVE_IOS_SOURCE_SHA) {
    throw new Error('SHA source du client iOS différente de la révision CI attendue.');
  }
  const availableBefore = requireSimulatorBuildSpace(project, 15);
  const ios = resolve(project, 'ios');
  if (existsSync(ios)) throw new Error('Le client comparé exige un dossier iOS généré neuf.');
  const packagePath = resolve(project, 'package.json');
  const lockPath = resolve(project, 'package-lock.json');
  const packageBytes = readFileSync(packagePath);
  const lockBytes = readFileSync(lockPath);
  const pkg = JSON.parse(packageBytes);
  const template = resolve(project, 'node_modules/expo/template.tgz');
  const templateHash = hash(readFileSync(template));
  const app = JSON.parse(readFileSync(resolve(project, 'app.json'), 'utf8')).expo;
  if (app.ios?.bundleIdentifier !== COMPILED_APP_ID || app.updates?.enabled !== false) {
    throw new Error('Identité native ou mises à jour incompatibles avec la comparaison isolée.');
  }
  const prebuild = await run('npx', ['--no-install', 'expo', 'prebuild', '--platform', 'ios', '--no-install',
    '--template', template, '--skip-dependency-update', 'expo,react,react-native'],
  { timeout: 300_000, logfile: 'compiled-prebuild.log', captureLimit: 64_000, allowFailure: true });
  const after = JSON.parse(readFileSync(packagePath, 'utf8'));
  const unchangedDependencies = ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies']
    .every(key => JSON.stringify(after[key]) === JSON.stringify(pkg[key]));
  const unchangedLock = readFileSync(lockPath).equals(lockBytes);
  // Prebuild rewrites launch scripts. The generated project is the only intended
  // output: restore the exact tracked package, and reject any dependency drift.
  writeFileSync(packagePath, packageBytes);
  if (prebuild.expired || prebuild.signal || prebuild.code !== 0 || !unchangedDependencies || !unchangedLock || after.main !== pkg.main) {
    throw new Error('Prebuild échoué ou package verrouillé modifié : aucune installation corrective permise.');
  }
  const nativeEnv = { RCT_METRO_PORT: '8090', RCT_NO_LAUNCH_PACKAGER: '1',
    RCT_USE_PREBUILT_RNCORE: '0', RCT_USE_RN_DEP: '1' };
  const versions = {
    xcode: (await run('xcodebuild', ['-version'])).stdout.trim(),
    cocoapods: (await run('pod', ['--version'])).stdout.trim(),
  };
  await run('pod', ['install', '--project-directory=' + ios],
    { timeout: 900_000, logfile: 'compiled-pods.log', captureLimit: 64_000, extraEnv: nativeEnv });
  requireSimulatorBuildSpace(project);
  copyFileSync(resolve(ios, 'Podfile.lock'), resolve(output, 'compiled-Podfile.lock'));
  const rnSource = rnPatch.verifyBuild(project, env);
  const workspaces = readdirSync(ios).filter(name => name.endsWith('.xcworkspace'));
  const projects = readdirSync(ios).filter(name => name.endsWith('.xcodeproj'));
  if (workspaces.length !== 1 || projects.length !== 1) throw new Error('Workspace iOS généré absent ou ambigu.');
  const scheme = basename(projects[0], '.xcodeproj');
  const workspace = resolve(ios, workspaces[0]);
  const inventoryArgs = ['-list', '-json', '-workspace', workspace];
  const inventoryTimeout = 180_000;
  const inventoryStarted = new Date().toISOString();
  const inventoryCommand = await run('xcodebuild', inventoryArgs, {
    timeout: inventoryTimeout, logfile: 'compiled-workspace-inventory.log', allowFailure: true,
  });
  writeFileSync(resolve(output, 'compiled-workspace-inventory-command.json'), JSON.stringify({
    phase: 'compiled-workspace-inventory', command: ['xcodebuild', ...inventoryArgs],
    started: inventoryStarted, ended: new Date().toISOString(), timeoutMs: inventoryTimeout,
    code: inventoryCommand.code, signal: inventoryCommand.signal,
    expired: inventoryCommand.expired, durationMs: inventoryCommand.durationMs,
  }, null, 2));
  if (inventoryCommand.expired || inventoryCommand.signal || inventoryCommand.code !== 0) {
    throw new Error('Inventaire du workspace Xcode échoué ; voir le reçu et le journal conservés.');
  }
  const inventory = JSON.parse(inventoryCommand.stdout);
  if (!inventory.workspace?.schemes?.includes(scheme)) throw new Error('Scheme de l’app générée introuvable.');
  const derived = resolve(env.RUNNER_TEMP, 'jolene-compiled-app-derived');
  if (existsSync(derived)) throw new Error('La compilation RN source exige un DerivedData neuf.');
  await run('xcodebuild', ['build', '-workspace', workspace, '-scheme', scheme, '-configuration', 'Debug',
    '-sdk', 'iphonesimulator', '-destination', `platform=iOS Simulator,id=${device}`,
    '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
    'RCT_METRO_PORT=8090', 'COMPILER_INDEX_STORE_ENABLE=NO'],
  { timeout: 2_400_000, logfile: 'compiled-build.log', captureLimit: 64_000, extraEnv: nativeEnv });
  requireSimulatorBuildSpace(project);
  const objectsRoot = resolve(derived, 'Build/Intermediates.noindex/Pods.build');
  const objects = readdirSync(objectsRoot, { recursive: true })
    .filter(path => ['RCTTextInputComponentView.o', 'RCTAttributedTextUtils.o'].includes(basename(path)))
    .map(path => ({ path, bytes: statSync(resolve(objectsRoot, path)).size }));
  if (!['RCTTextInputComponentView.o', 'RCTAttributedTextUtils.o'].every(name => objects.some(file => basename(file.path) === name && file.bytes > 0))) {
    throw new Error('Objets natifs du correctif RN absents après compilation.');
  }
  rnPatch.verifyPatched(project, env);
  writeFileSync(resolve(output, 'compiled-rn-source.json'), JSON.stringify({ ...rnSource, objects, freshDerivedData: true }, null, 2));
  const products = resolve(derived, 'Build/Products/Debug-iphonesimulator');
  const apps = readdirSync(products).filter(name => name.endsWith('.app'));
  if (apps.length !== 1) throw new Error('Binaire Debug simulateur absent ou ambigu.');
  const binary = resolve(products, apps[0]);
  const plist = resolve(binary, 'Info.plist');
  const value = async key => (await run('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, plist])).stdout.trim();
  const bundleId = await value('CFBundleIdentifier');
  const executable = await value('CFBundleExecutable');
  const iconName = await value('CFBundleDisplayName');
  const supportedPlatform = await value('CFBundleSupportedPlatforms:0');
  const metroPort = await value('RCTMetroPort');
  if (bundleId !== COMPILED_APP_ID || supportedPlatform !== 'iPhoneSimulator' || metroPort !== '8090'
    || !/^[A-Za-z0-9._ -]+$/.test(executable) || ['.', '..'].includes(executable)
    || !iconName || iconName.length > 100 || /[\r\n\0]/.test(iconName)) {
    throw new Error('Identité du binaire compilé inattendue.');
  }
  const deviceFamilies = (await value('UIDeviceFamily')).split('\n').map(line => line.trim()).filter(line => /^[12]$/.test(line)).map(Number).sort();
  if (JSON.stringify(deviceFamilies) !== '[1,2]') throw new Error('Le client doit prendre en charge iPhone et iPad.');
  const provenance = { host: 'compiled-debug', sourceSha, bundleId, executable, iconName, metroPort, configuration: 'Debug',
    platform: supportedPlatform, signingAllowed: false, sourceCore: true, rnSource, deviceFamilies, versions, dependencies: pkg.dependencies,
    lockSha256: hash(lockBytes), templateSha256: templateHash,
    podLockSha256: hash(readFileSync(resolve(ios, 'Podfile.lock'))),
    availableBefore, availableAfter: requireSimulatorBuildSpace(project),
    source: 'same-package-synthetic-simulator-source-build' };
  writeFileSync(resolve(output, 'compiled-client.json'), JSON.stringify(provenance, null, 2));
  await run('xcrun', ['simctl', 'install', device, binary], { timeout: 180_000, logfile: 'compiled-install.log' });
  return { bundleId, executable, iconName };
}

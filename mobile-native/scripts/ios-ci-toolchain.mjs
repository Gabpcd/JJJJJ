// Reproducible simulator baseline, already installed on the macos-26 image.
// Never silently switch Xcode/runtime when that hosted image is updated.
// Compiler and simulator runtime are independent: Expo SDK 57 needs Xcode >=26.4
// (https://docs.expo.dev/versions/latest/). Keep its compatible source compiler
// while running the fixed 26.2 simulator; UIKit and product tests remain required.
export const IOS_CI_DEVELOPER_DIR = '/Applications/Xcode_26.4.1.app/Contents/Developer';
export const IOS_CI_RUNTIME = '26.2';

export function verifyIosCiXcode(version) {
  if (version.trim() !== 'Xcode 26.4.1\nBuild version 17E202') {
    throw new Error('La CI native exige Xcode 26.4.1 (17E202), sans repli automatique.');
  }
  return { xcode: version.trim(), developerDir: IOS_CI_DEVELOPER_DIR, runtime: IOS_CI_RUNTIME };
}

export function selectIosCiSimulator(runtimes, devices, family) {
  if (!['iphone', 'ipad'].includes(family)) throw new Error('Famille de simulateur iOS invalide.');
  const matching = runtimes.filter(runtime => runtime.isAvailable
    && runtime.identifier === 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'
    && runtime.version === IOS_CI_RUNTIME && runtime.buildversion === '23C54');
  if (matching.length !== 1) throw new Error('Runtime iOS 26.2 (23C54) absent ou ambigu : aucun SDK ne sera installé.');
  const runtime = matching[0];
  const name = family === 'iphone' ? 'iPhone 17' : 'iPad (A16)';
  const candidates = (devices[runtime.identifier] ?? []).filter(device => device.isAvailable && device.name === name
    && (device.deviceTypeIdentifier || device.name).toLowerCase().includes(family));
  const device = candidates[0];
  if (candidates.length !== 1 || !device || !/^[0-9A-F-]{36}$/i.test(device.udid)) {
    throw new Error(`Simulateur ${name} iOS 26.2 absent ou ambigu : aucun SDK ne sera installé.`);
  }
  return { runtime, device };
}

// Reproducible simulator baseline, already installed on the macos-26 image.
// Never silently switch Xcode/runtime when that hosted image is updated.
// The independent UIKit contact witness completes on 26.2; 26.4.1 exhibited
// cancelled synthetic contacts even without React Native. Product tests remain required.
export const IOS_CI_DEVELOPER_DIR = '/Applications/Xcode_26.2.app/Contents/Developer';
export const IOS_CI_RUNTIME = '26.2';

export function verifyIosCiXcode(version) {
  if (version.trim() !== 'Xcode 26.2\nBuild version 17C52') {
    throw new Error('La CI native exige Xcode 26.2 (17C52), sans repli automatique.');
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

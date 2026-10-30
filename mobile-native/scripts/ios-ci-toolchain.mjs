// Reproducible simulator baseline, already installed on the macos-26 image.
// Never silently switch Xcode/runtime when that hosted image is updated.
export const IOS_CI_DEVELOPER_DIR = '/Applications/Xcode_26.4.1.app/Contents/Developer';
export const IOS_CI_RUNTIME = '26.4.1';

export function verifyIosCiXcode(version) {
  if (version.trim() !== 'Xcode 26.4.1\nBuild version 17E202') {
    throw new Error('La CI native exige Xcode 26.4.1 (17E202), sans repli automatique.');
  }
  return { xcode: version.trim(), developerDir: IOS_CI_DEVELOPER_DIR, runtime: IOS_CI_RUNTIME };
}

export function selectIosCiSimulator(runtimes, devices, family) {
  if (!['iphone', 'ipad'].includes(family)) throw new Error('Famille de simulateur iOS invalide.');
  const matching = runtimes.filter(runtime => runtime.isAvailable
    && runtime.identifier === 'com.apple.CoreSimulator.SimRuntime.iOS-26-4'
    && runtime.version === IOS_CI_RUNTIME && runtime.buildversion === '23E254a');
  if (matching.length !== 1) throw new Error('Runtime iOS 26.4.1 (23E254a) absent ou ambigu : aucun SDK ne sera installé.');
  const runtime = matching[0];
  const candidates = (devices[runtime.identifier] ?? []).filter(device => device.isAvailable
    && (device.deviceTypeIdentifier || device.name).toLowerCase().includes(family))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
  const device = candidates[0];
  if (!device || !/^[0-9A-F-]{36}$/i.test(device.udid)) {
    throw new Error(`Aucun simulateur ${family} iOS 26.4.1 valide : aucun SDK ne sera installé.`);
  }
  return { runtime, device };
}

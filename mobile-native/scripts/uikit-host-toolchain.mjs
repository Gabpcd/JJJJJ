// Diagnostic branch only: the same UIKit source and iPhone 17 on two hosts.
// Does not change the product CI baseline or provide a fallback runtime.
export const IOS_CI_DEVELOPER_DIR = '/Applications/Xcode_26.2.app/Contents/Developer';
export const IOS_CI_RUNTIME = '26.2';

export function verifyIosCiXcode(version) {
  if (version.trim() !== 'Xcode 26.2\nBuild version 17C52') {
    throw new Error('Le témoin exige Xcode 26.2 (17C52), sans repli.');
  }
  return { xcode: version.trim(), developerDir: IOS_CI_DEVELOPER_DIR, runtime: IOS_CI_RUNTIME };
}

export function selectIosCiSimulator(runtimes, devices, family) {
  if (family !== 'iphone') throw new Error('Comparaison réservée à iPhone 17.');
  const matching = runtimes.filter(runtime => runtime.isAvailable
    && runtime.identifier === 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'
    && runtime.version === IOS_CI_RUNTIME && runtime.buildversion === '23C54');
  if (matching.length !== 1) throw new Error('Runtime iOS 26.2 (23C54) absent ou ambigu : aucun téléchargement.');
  const runtime = matching[0];
  const candidates = (devices[runtime.identifier] ?? []).filter(device => device.isAvailable
    && device.name === 'iPhone 17' && device.deviceTypeIdentifier === 'com.apple.CoreSimulator.SimDeviceType.iPhone-17');
  if (candidates.length !== 1 || !/^[0-9A-F-]{36}$/i.test(candidates[0].udid)) {
    throw new Error('iPhone 17 absent ou ambigu : aucun changement de modèle.');
  }
  return { runtime, device: candidates[0] };
}

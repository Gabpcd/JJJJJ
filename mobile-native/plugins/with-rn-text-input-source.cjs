const { verifyPatched } = require('../scripts/rn-text-input-patch.cjs');

// This runs before Expo's ||= defaults. Validate again at pod install so a new
// shell cannot silently override the config-time environment or skip postinstall.
const podfileGuard = `# jolene-rn-text-input-source begin
jolene_project_root = File.expand_path('..', __dir__)
unless system('node', File.join(jolene_project_root, 'scripts/rn-text-input-patch.cjs'), '--verify', chdir: jolene_project_root)
  abort 'Jolene RN TextInput source guard failed; no Pods installation permitted.'
end
ENV['RCT_USE_PREBUILT_RNCORE'] ||= '0'
ENV['RCT_USE_RN_DEP'] ||= '1'
# jolene-rn-text-input-source end

`;
const anchors = [
  "ENV['RCT_USE_RN_DEP'] ||= podfile_properties['ios.buildReactNativeFromSource'] == 'true' ? '0' : '1'",
  "ENV['RCT_USE_PREBUILT_RNCORE'] ||= podfile_properties['ios.buildReactNativeFromSource'] == 'true' ? '0' : '1'",
];
function configurePodfile(contents) {
  const original = contents.startsWith(podfileGuard) ? contents.slice(podfileGuard.length) : contents;
  if (original.includes('jolene-rn-text-input-source') || !anchors.every(line => original.split(line).length === 2)) {
    throw new Error('Podfile Expo 57 différent du template vérifié : garde RN non appliquée.');
  }
  return podfileGuard + original;
}
function withRnTextInputSource(config) {
  // Use Expo's already-locked config API; no new plugin package is installed.
  const { withPodfile, withPodfileProperties } = require('expo/config-plugins');
  config = withPodfileProperties(config, mod => {
    verifyPatched(mod.modRequest.projectRoot);
    mod.modResults['ios.buildReactNativeFromSource'] = 'true';
    return mod;
  });
  return withPodfile(config, mod => {
    verifyPatched(mod.modRequest.projectRoot);
    if (mod.modResults.language !== 'rb') throw new Error('Format Podfile inattendu.');
    mod.modResults.contents = configurePodfile(mod.modResults.contents);
    return mod;
  });
}
module.exports = withRnTextInputSource;
module.exports.podfileGuard = podfileGuard;
module.exports.configurePodfile = configurePodfile;

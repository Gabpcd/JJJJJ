// Alignement des versions mobiles sur config/mobile-release.json, par plateforme (lot 6,
// docs/mobile-swift/DECISIONS_LOT6.md) :
//   - Android (coquille Capacitor) : versionCode et versionName de android/app/build.gradle ;
//   - iOS (app Swift) : MARKETING_VERSION de ios-native/Config/Base.xcconfig. Le numéro de build
//     n'est pas comparé : il est attribué à l'envoi TestFlight ;
//   - coquille Capacitor iOS (ios/) : gelée à sa dernière version publiée tant que le dossier existe.
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { COQUILLE_IOS_FIGEE, DOC, lireConfigLivraison } from './mobile/release-config.mjs';

/** Rend la liste des écarts ; vide quand tout est aligné. `coquilleIos` vaut null si ios/ n'existe plus. */
export function verifierAlignement({ config, androidGradle, baseXcconfig, coquilleIos }) {
  const failures = [];
  const androidBuild = Number(androidGradle.match(/\bversionCode\s+(\d+)/)?.[1]);
  const androidVersion = androidGradle.match(/\bversionName\s+"([^"]+)"/)?.[1];
  if (androidBuild !== config.android.buildNumber) {
    failures.push(`Android versionCode=${Number.isNaN(androidBuild) ? 'absent' : androidBuild}, attendu ${config.android.buildNumber}`);
  }
  if (androidVersion !== config.android.marketingVersion) {
    failures.push(`Android versionName=${androidVersion ?? 'absent'}, attendu ${config.android.marketingVersion}`);
  }
  const swiftVersion = baseXcconfig.match(/^MARKETING_VERSION\s*=\s*(\S+)\s*$/m)?.[1];
  if (swiftVersion !== config.ios.marketingVersion) {
    failures.push(`iOS Swift MARKETING_VERSION=${swiftVersion ?? 'absent'}, attendu ${config.ios.marketingVersion} (ios-native/Config/Base.xcconfig)`);
  }
  if (coquilleIos !== null) {
    const builds = [...coquilleIos.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)].map((match) => Number(match[1]));
    const versions = [...coquilleIos.matchAll(/MARKETING_VERSION = ([^;]+);/g)].map((match) => match[1].trim());
    const gelee = builds.length > 0 && versions.length > 0
      && builds.every((value) => value === COQUILLE_IOS_FIGEE.buildNumber)
      && versions.every((value) => value === COQUILLE_IOS_FIGEE.marketingVersion);
    if (!gelee) {
      failures.push(`coquille Capacitor iOS (ios/) en ${versions.join(',') || 'absent'} (${builds.join(',') || 'absent'}) : elle est gelée à ${COQUILLE_IOS_FIGEE.marketingVersion} (${COQUILLE_IOS_FIGEE.buildNumber}) et n'est plus livrée (voir ${DOC})`);
    }
  }
  return failures;
}

if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url))) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const read = (path) => readFileSync(join(root, path), 'utf8');
  const coquille = 'ios/App/App.xcodeproj/project.pbxproj';
  const config = lireConfigLivraison(read('config/mobile-release.json'));
  const failures = verifierAlignement({
    config,
    androidGradle: read('android/app/build.gradle'),
    baseXcconfig: read('ios-native/Config/Base.xcconfig'),
    coquilleIos: existsSync(join(root, coquille)) ? read(coquille) : null,
  });
  if (failures.length > 0) {
    console.error('Versions mobiles désalignées :');
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`✓ Android aligné sur ${config.android.marketingVersion} (${config.android.buildNumber}), iOS Swift sur ${config.ios.marketingVersion} (build TestFlight ≥ ${config.ios.minimumBuildNumber})`);
}

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const [releaseConfigSource, iosProject, androidGradle] = await Promise.all([
  readFile(join(root, 'config/mobile-release.json'), 'utf8'),
  readFile(join(root, 'ios/App/App.xcodeproj/project.pbxproj'), 'utf8'),
  readFile(join(root, 'android/app/build.gradle'), 'utf8'),
]);

const releaseConfig = JSON.parse(releaseConfigSource);
const expectedBuild = Number(releaseConfig.buildNumber);
const expectedVersion = String(releaseConfig.marketingVersion);

if (!Number.isSafeInteger(expectedBuild) || expectedBuild <= 0) {
  throw new Error('config/mobile-release.json: buildNumber doit être un entier positif');
}

const iosBuilds = [...iosProject.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)]
  .map((match) => Number(match[1]));
const iosVersions = [...iosProject.matchAll(/MARKETING_VERSION = ([^;]+);/g)]
  .map((match) => match[1].trim());
const androidBuild = Number(androidGradle.match(/\bversionCode\s+(\d+)/)?.[1]);
const androidVersion = androidGradle.match(/\bversionName\s+"([^"]+)"/)?.[1];

const failures = [];

if (iosBuilds.length === 0 || iosBuilds.some((value) => value !== expectedBuild)) {
  failures.push(`iOS CURRENT_PROJECT_VERSION=${iosBuilds.join(',') || 'absent'}, attendu ${expectedBuild}`);
}
if (iosVersions.length === 0 || iosVersions.some((value) => value !== expectedVersion)) {
  failures.push(`iOS MARKETING_VERSION=${iosVersions.join(',') || 'absent'}, attendu ${expectedVersion}`);
}
if (androidBuild !== expectedBuild) {
  failures.push(`Android versionCode=${Number.isNaN(androidBuild) ? 'absent' : androidBuild}, attendu ${expectedBuild}`);
}
if (androidVersion !== expectedVersion) {
  failures.push(`Android versionName=${androidVersion ?? 'absent'}, attendu ${expectedVersion}`);
}

if (failures.length > 0) {
  console.error('Versions mobiles désalignées :');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`✓ iOS et Android alignés sur ${expectedVersion} (${expectedBuild})`);

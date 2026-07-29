import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const manifestPath = join(root, 'scripts/brand-assets.sha256');
const failures = [];
const legacyHeartWordmark =
  /(?:(?:❤️|❤|♥|&hearts;|&#x?2665;)\s*Jolene|Jolene\s*(?:❤️|❤|♥|&hearts;|&#x?2665;))/iu;
const forbiddenLegacyHashes = new Set([
  // AppIcon iOS cœur
  '1dcc66f32d991d9c6068a8235cbac7614e77b954c9364556028e7446606ed00a',
  // Launcher Android cœur
  'cc22591a0c238a705220dc15c66aef9bf3b456dfc24bfb6cf87a7de82e7a7dd2',
  // Splashs clair et sombre avec cœur
  '578cfb535d0fea5e52ad9cded17a612f47b6828f7b2595a77a40e0190ce9715f',
  '40c0c87c593d51fd15ee0edc17ce867294e52adc5689ad25734337b5d140015d',
]);

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function walk(directory) {
  return readdirSync(directory)
    .flatMap((entry) => {
      const path = join(directory, entry);
      return statSync(path).isDirectory() ? walk(path) : [path];
    });
}

const manifest = readFileSync(manifestPath, 'utf8')
  .split('\n')
  .map((line) => line.trim())
  .filter(Boolean)
  .map((line) => {
    const match = line.match(/^([a-f0-9]{64})  (.+)$/);
    if (!match) {
      failures.push(`Manifeste invalide : ${line}`);
      return null;
    }
    return { expected: match[1], relativePath: match[2] };
  })
  .filter(Boolean);

for (const { expected, relativePath } of manifest) {
  const path = join(root, relativePath);
  if (!existsSync(path)) {
    failures.push(`Asset de marque absent : ${relativePath}`);
    continue;
  }
  const actual = sha256(path);
  if (actual !== expected) {
    failures.push(
      `Asset de marque divergent : ${relativePath}\n` +
      `  attendu ${expected}\n` +
      `  obtenu  ${actual}`,
    );
  }
}

const forbiddenLegacyFiles = [
  'public/icon-generator.html',
  'public/favicon.svg',
  'public/app-icon-option-b.png',
  'public/app-icon-option-c.png',
  'resources/icon.svg',
  'resources/splash.svg',
  'resources/splash-dark.svg',
  'android/app/src/main/res/drawable/ic_launcher_adaptive_background.xml',
  'android/app/src/main/res/drawable/ic_launcher_adaptive_foreground.xml',
  'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
];

for (const relativePath of forbiddenLegacyFiles) {
  if (existsSync(join(root, relativePath))) {
    failures.push(`Ancien branding réintroduit : ${relativePath}`);
  }
}

for (const directory of [
  'public',
  'resources',
  'ios/App/App/Assets.xcassets',
  'android/app/src/main/res',
]) {
  for (const path of walk(join(root, directory))) {
    if (!/\.(?:png|ico)$/i.test(path)) continue;
    if (forbiddenLegacyHashes.has(sha256(path))) {
      failures.push(`Ancien visuel cœur détecté : ${relative(root, path)}`);
    }
  }
}

for (const directory of [
  'public',
  'resources',
  'ios/App/App/Assets.xcassets',
  'android/app/src/main/res',
]) {
  for (const path of walk(join(root, directory))) {
    if (!/\.(?:html|svg|xml|js|json)$/i.test(path)) continue;
    const source = readFileSync(path, 'utf8');
    if (
      source.includes('HeartPulse') ||
      source.includes('M19 14c1.49-1.46') ||
      legacyHeartWordmark.test(source)
    ) {
      failures.push(`Ancien logo cœur détecté : ${relative(root, path)}`);
    }
  }
}

for (const path of walk(join(root, 'supabase/functions'))) {
  if (!/\.(?:ts|js|html)$/i.test(path)) continue;
  const source = readFileSync(path, 'utf8');
  if (legacyHeartWordmark.test(source)) {
    failures.push(`Ancien wordmark cœur détecté dans un email : ${relative(root, path)}`);
  }
}

for (const path of walk(join(root, 'src'))) {
  if (!/\.[cm]?[jt]sx?$/.test(path)) continue;
  const source = readFileSync(path, 'utf8');
  const relativePath = relative(root, path);

  if (source.includes('HeartPulse')) {
    failures.push(`HeartPulse interdit dans l'identité applicative : ${relativePath}`);
  }
  if (legacyHeartWordmark.test(source)) {
    failures.push(`Ancien wordmark cœur interdit : ${relativePath}`);
  }
  if (
    source.includes('M50 88 C18 65') ||
    source.toLocaleLowerCase('fr').includes('mascotte cœur')
  ) {
    failures.push(`Ancienne mascotte cœur interdite : ${relativePath}`);
  }
  if (
    source.includes('/logo-jolene-carre.png') &&
    relativePath !== 'src/components/LogoJolene.tsx'
  ) {
    failures.push(
      `Le logo doit passer par LogoJolene, référence directe interdite : ${relativePath}`,
    );
  }
}

const mascotSource = readFileSync(
  join(root, 'src/components/mascotte/Mascotte.tsx'),
  'utf8',
);
if (!mascotSource.includes('<LogoJolene')) {
  failures.push('Mascotte doit afficher le composant LogoJolene canonique');
}
if (/<path\s+[^>]*d=["']/.test(mascotSource)) {
  failures.push('Mascotte ne doit plus contenir de forme SVG de marque autonome');
}

for (const relativePath of [
  'android/app/src/main/res/mipmap-anydpi/ic_launcher.xml',
  'android/app/src/main/res/mipmap-anydpi/ic_launcher_round.xml',
]) {
  const source = readFileSync(join(root, relativePath), 'utf8');
  for (const required of [
    '@mipmap/ic_launcher_background',
    '@mipmap/ic_launcher_foreground',
  ]) {
    if (!source.includes(required)) {
      failures.push(`${relativePath} ne référence pas ${required}`);
    }
  }
  if (source.includes('@drawable/ic_launcher_adaptive')) {
    failures.push(`${relativePath} référence encore l'ancien launcher cœur`);
  }
}

if (failures.length > 0) {
  console.error(failures.map((failure) => `✗ ${failure}`).join('\n'));
  process.exit(1);
}

console.log(`✓ identité Jolene cohérente : ${manifest.length} assets verrouillés`);

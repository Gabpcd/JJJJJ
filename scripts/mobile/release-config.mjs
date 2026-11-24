// Configuration de livraison mobile, scindée par plateforme au lot 6
// (docs/mobile-swift/DECISIONS_LOT6.md, D3 à D6). Source unique : config/mobile-release.json.
//
//   ios      app Swift (ios-native/). La version vient d'ici et du xcconfig ; le numéro de build est
//            attribué à l'envoi TestFlight (App Store Connect), jamais figé : seul un plancher existe.
//            Aucune mise à jour à chaud : Apple 2.5.2 interdit de télécharger du code qui change l'app.
//   android  coquille Capacitor (android/). Livraison native Google Play et mises à jour OTA signées.
//
// La coquille Capacitor iOS (ios/, 1.0.7 build 24) est gelée : plus aucun workflow ne la construit
// ni ne la soumet. Principe CLAUDE.md « un gap connu reste verrouillé » : chaque refus est explicite
// et renvoie à la doc.
import { readFileSync } from 'node:fs';

export const DOC = 'docs/mobile-swift/DECISIONS_LOT6.md';
export const PLATEFORMES = Object.freeze(['ios', 'android']);

/** Dernière coquille Capacitor iOS publiée (App Store, 5 octobre 2026). Gelée jusqu'au lot 7. */
export const COQUILLE_IOS_FIGEE = Object.freeze({ marketingVersion: '1.0.7', buildNumber: 24 });

const refus = (message) => new Error(`${message} (voir ${DOC})`);
const estVersion = (value) => typeof value === 'string' && /^\d+(?:\.\d+){0,2}$/.test(value);
const estBuild = (value) => Number.isSafeInteger(value) && value > 0;

export function comparerVersions(a, b) {
  const pa = String(a).split('.').map(Number);
  const pb = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff) return Math.sign(diff);
  }
  return 0;
}

/** Valide le contenu de config/mobile-release.json et rend { ios, android }. */
export function lireConfigLivraison(source) {
  let config;
  try { config = JSON.parse(source); } catch { throw refus('config/mobile-release.json illisible'); }
  if (!config || typeof config !== 'object' || Array.isArray(config)) throw refus('config/mobile-release.json illisible');
  if ('marketingVersion' in config || 'buildNumber' in config) {
    throw refus('config/mobile-release.json : la configuration est scindée par plateforme (« ios », « android ») ; « marketingVersion » et « buildNumber » au premier niveau ne sont plus lus');
  }
  for (const key of Object.keys(config)) {
    if (!PLATEFORMES.includes(key)) throw refus(`config/mobile-release.json : clé inconnue « ${key} »`);
  }
  const { ios, android } = config;
  if (!ios || !android || typeof ios !== 'object' || typeof android !== 'object') {
    throw refus('config/mobile-release.json : les sections « ios » et « android » sont exigées');
  }
  if (ios.runtime !== 'swift') throw refus('config/mobile-release.json : ios.runtime doit valoir « swift » (la coquille Capacitor iOS n\'est plus livrée)');
  if (android.runtime !== 'capacitor') throw refus('config/mobile-release.json : android.runtime doit valoir « capacitor »');
  if ('buildNumber' in ios) {
    throw refus('config/mobile-release.json : ios.buildNumber n\'existe pas ; le build iOS est attribué par TestFlight, seul ios.minimumBuildNumber est configuré');
  }
  if (!estVersion(ios.marketingVersion) || comparerVersions(ios.marketingVersion, COQUILLE_IOS_FIGEE.marketingVersion) <= 0) {
    throw refus(`config/mobile-release.json : ios.marketingVersion « ${ios.marketingVersion} » doit dépasser ${COQUILLE_IOS_FIGEE.marketingVersion}, dernière version de la coquille publiée`);
  }
  if (!estBuild(ios.minimumBuildNumber) || ios.minimumBuildNumber <= COQUILLE_IOS_FIGEE.buildNumber) {
    throw refus(`config/mobile-release.json : ios.minimumBuildNumber « ${ios.minimumBuildNumber} » doit dépasser ${COQUILLE_IOS_FIGEE.buildNumber}, dernier build de la coquille publiée`);
  }
  if (!estVersion(android.marketingVersion)) throw refus(`config/mobile-release.json : android.marketingVersion « ${android.marketingVersion} » invalide`);
  if (!estBuild(android.buildNumber)) throw refus(`config/mobile-release.json : android.buildNumber « ${android.buildNumber} » doit être un entier positif (versionCode)`);
  return {
    ios: { runtime: 'swift', marketingVersion: ios.marketingVersion, minimumBuildNumber: ios.minimumBuildNumber },
    android: { runtime: 'capacitor', marketingVersion: android.marketingVersion, buildNumber: android.buildNumber },
  };
}

export function chargerConfigLivraison(path = 'config/mobile-release.json') {
  return lireConfigLivraison(readFileSync(path, 'utf8'));
}

/**
 * Plateforme servie par mobile-delivery.yml : Android seul. iOS natif est refusé ici, quel que soit
 * le mode : TestFlight et soumission ont leurs propres workflows, et il n'existe pas d'OTA iOS.
 */
export function plateformeMobileDelivery(value) {
  const platform = value === undefined || value === '' ? 'android' : value;
  if (platform === 'android') return 'android';
  if (platform === 'ios') {
    throw refus('iOS natif ne se livre pas par mobile-delivery.yml : envoi TestFlight par ios-native-testflight.yml, soumission à la revue par ios-native-app-store.yml, et aucune mise à jour OTA (règle Apple 2.5.2)');
  }
  throw refus(`Plateforme de livraison inconnue « ${platform} »`);
}

/** Tags de livraison d'une plateforme. iOS ne réserve pas de source : son build vient de TestFlight. */
export function tagsLivraison(platform, build) {
  if (!PLATEFORMES.includes(platform)) throw refus(`Plateforme inconnue « ${platform} »`);
  if (!estBuild(build)) throw refus(`Numéro de build invalide « ${build} »`);
  return {
    soumis: `mobile-native-${platform}-${build}`,
    source: platform === 'android' ? `mobile-native-source-android-${build}` : null,
  };
}

/**
 * Runtime visé par une mise à jour OTA : Android seul. Le client de mise à jour ne compare que le
 * bundle, la version et le build (src/lib/mobileUpdates.ts) : sur un build que la coquille Capacitor
 * iOS a aussi porté, le manifeste atteindrait les iPhone restés en 1.0.7 sans recette iOS.
 */
export function exigerOtaAndroidSeul(config) {
  const { marketingVersion, buildNumber } = config.android;
  if (buildNumber <= COQUILLE_IOS_FIGEE.buildNumber) {
    throw refus(`OTA refusée : le runtime ${buildNumber} est aussi celui de la coquille Capacitor iOS ${COQUILLE_IOS_FIGEE.marketingVersion} (${COQUILLE_IOS_FIGEE.buildNumber}) encore installée ; le manifeste l'atteindrait. Publier d'abord un build Android natif de versionCode supérieur à ${COQUILLE_IOS_FIGEE.buildNumber}`);
  }
  return { marketingVersion, buildNumber };
}

/** Numéro de build d'une soumission iOS Swift : celui du build TestFlight, jamais sous le plancher. */
export function buildIosSoumis(config, value) {
  const raw = String(value ?? '');
  if (!/^[1-9]\d{0,8}$/.test(raw) || Number(raw) < config.ios.minimumBuildNumber) {
    throw refus(`RELEASE_BUILD_NUMBER « ${raw} » invalide : numéro du build TestFlight soumis, au moins ${config.ios.minimumBuildNumber}`);
  }
  return Number(raw);
}

#!/usr/bin/env node
// Gardes et numérotation de la livraison TestFlight interne de l'app Swift (ios-native/).
// Utilisé par .github/workflows/ios-native-testflight.yml ; documentation :
// docs/mobile-swift/TESTFLIGHT.md. Principe CLAUDE.md « un gap connu reste verrouillé » :
// chaque garde échoue explicitement, nomme la règle violée et renvoie à la doc. Aucune valeur
// secrète n'est jamais affichée (clé ASC, mot de passe, contenu du .p12).
//
// Sous-commandes :
//   depot                      gardes statiques du dépôt (avant toute compilation)
//   build-number               numéro de build : entrée JOLENE_BUILD_INPUT ou max(ASC, plancher) + 1
//   verify-free <N>            relit App Store Connect juste avant l'envoi : N doit rester libre
//   profile <profil>           profil de distribution (nom, équipe, App ID, entitlements, certificat)
//   settings <json> --build N  réglages Release résolus (xcodebuild -showBuildSettings -json)
//   bundle <Jolene.app> --build N   Info.plist, manifeste de confidentialité et icône du binaire
//   signature <Jolene.app> --profile-uuid U   signature, entitlements signés et profil embarqué
//   processing <N>             attend le traitement App Store Connect (VALID) du build envoyé
import { appendFileSync, existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash, createPrivateKey, sign, X509Certificate } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const DOC = 'docs/mobile-swift/TESTFLIGHT.md';
export const APP = Object.freeze({
  appleId: '6774672845',
  bundleId: 'app.jolene',
  teamId: 'GDU5AA28M9',
  identity: 'Apple Distribution: Jolene App (GDU5AA28M9)',
  profile: 'Jolene App Store Distribution',
  productionUrl: 'https://flripxtsyegjshnhzjkz.supabase.co',
  stagingRef: 'mejpriaetwgtcstbgfid',
  // Dernier build Capacitor publié : 1.0.7 (24). Aucun build Swift ne descend à ce niveau.
  buildFloor: 24,
  minimumMarketingVersion: '2.0.0',
});

// Raisons admises par Apple pour chaque catégorie d'API « required reason »
// (TN3183 / « Describing use of required reason API »).
export const RAISONS_API = Object.freeze({
  NSPrivacyAccessedAPICategoryFileTimestamp: ['DDA9.1', 'C617.1', '3B52.1', '0A2A.1'],
  NSPrivacyAccessedAPICategorySystemBootTime: ['35F9.1', '8FFB.1', '3D61.1'],
  NSPrivacyAccessedAPICategoryDiskSpace: ['85F4.1', 'E174.1', '7D9E.1', 'B728.1'],
  NSPrivacyAccessedAPICategoryActiveKeyboards: ['3EC4.1', '54BD.1'],
  NSPrivacyAccessedAPICategoryUserDefaults: ['CA92.1', '1C8F.1', 'C56D.1', 'AC6B.1'],
});

// Détection volontairement large dans le code Swift de l'app et de ses packages : un faux
// positif impose seulement une déclaration ; un oubli ferait refuser l'envoi (ITMS-91053).
export const USAGES_API = Object.freeze({
  NSPrivacyAccessedAPICategoryUserDefaults: /\bUserDefaults\b|@AppStorage\b|\bNSUserDefaults\b/,
  NSPrivacyAccessedAPICategoryFileTimestamp: /\b(?:creationDate|contentModificationDate|modificationDate|contentAccessDate|attributeModificationDate)(?:Key)?\b|\battributesOfItem\b|\bNSFile(?:Creation|Modification)Date\b|\b[fl]?stat\s*\(|\bgetattrlist\b/,
  NSPrivacyAccessedAPICategorySystemBootTime: /\bsystemUptime\b|\bmach_(?:absolute|continuous)_time\b|\bContinuousClock\b|\bSuspendingClock\b|\bCACurrentMediaTime\b|kern\.boottime/,
  NSPrivacyAccessedAPICategoryDiskSpace: /\bvolume(?:Available|Total)Capacity\w*\b|\bsystem(?:Free)?Size\b|\bNSFileSystem(?:Free)?Size\b|\bstatv?fs\s*\(/,
  NSPrivacyAccessedAPICategoryActiveKeyboards: /\bactiveInputModes\b/,
});

export class GuardFailure extends Error {
  constructor(failures) {
    super(failures.join('\n'));
    this.failures = failures;
  }
}

/** Collecte des refus : chaque message nomme la garde et renvoie à la doc. */
function collector() {
  const failures = [];
  const fail = (garde, message) => failures.push(`[${garde}] ${message} (voir ${DOC}, garde « ${garde} »)`);
  const done = () => { if (failures.length) throw new GuardFailure(failures); };
  return { fail, done, failures };
}

// ---------------------------------------------------------------------------------------------
// Lecture : plist XML, xcconfig, versions, PNG
// ---------------------------------------------------------------------------------------------

const ENTITES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const decodeXml = (text) => text.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (all, name) => {
  if (name[0] === '#') return String.fromCodePoint(name[1] === 'x' || name[1] === 'X' ? parseInt(name.slice(2), 16) : Number(name.slice(1)));
  return ENTITES[name] ?? all;
});

/** Analyse un plist XML (Info.plist, entitlements, xcprivacy, profil décodé). */
export function parsePlist(xml) {
  const text = String(xml).replace(/<!--[\s\S]*?-->/g, '');
  const token = /<(key|string|integer|real|date|data)>([\s\S]*?)<\/\1>|<(key|string|data)\s*\/>|<(true|false)\s*\/>|<(dict|array)\s*\/>|<(\/?)(dict|array)>/g;
  const stack = [{ type: 'root', value: [], key: null }];
  const push = (value) => {
    const top = stack.at(-1);
    if (top.type === 'dict') {
      if (top.key === null) throw new Error('plist invalide : valeur sans clé');
      top.value[top.key] = value;
      top.key = null;
    } else top.value.push(value);
  };
  for (const [, tag, body, emptyTag, bool, emptyContainer, closing, container] of text.matchAll(token)) {
    const top = stack.at(-1);
    if (tag === 'key' || emptyTag === 'key') {
      if (top.type !== 'dict' || top.key !== null) throw new Error('plist invalide : clé hors dictionnaire');
      top.key = decodeXml(body ?? '');
    } else if (tag === 'string') push(decodeXml(body));
    else if (tag === 'integer' || tag === 'real') push(Number(body.trim()));
    else if (tag === 'date') push(new Date(body.trim()));
    else if (tag === 'data') push(Buffer.from(body.replace(/\s+/g, ''), 'base64'));
    else if (emptyTag) push(emptyTag === 'data' ? Buffer.alloc(0) : '');
    else if (bool) push(bool === 'true');
    else if (emptyContainer) push(emptyContainer === 'dict' ? {} : []);
    else if (!closing) stack.push({ type: container, value: container === 'dict' ? {} : [], key: null });
    else {
      const done = stack.pop();
      if (done.type !== container || stack.length === 0) throw new Error('plist invalide : balises déséquilibrées');
      push(done.value);
    }
  }
  if (stack.length !== 1 || stack[0].value.length !== 1) throw new Error('plist invalide : racine absente ou multiple');
  return stack[0].value[0];
}

/** Lit un fichier plist XML, binaire (plutil) ou un profil signé CMS (security cms). */
export function readPlistFile(path) {
  const buffer = readFileSync(path);
  const head = buffer.subarray(0, 64).toString('utf8').trimStart();
  if (head.startsWith('<?xml') || head.startsWith('<plist') || head.startsWith('<!DOCTYPE')) return parsePlist(buffer.toString('utf8'));
  if (head.startsWith('bplist')) return parsePlist(execFileSync('plutil', ['-convert', 'xml1', '-o', '-', path], { encoding: 'utf8' }));
  return parsePlist(execFileSync('security', ['cms', '-D', '-i', path], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
}

/** Analyse un xcconfig (sans #include) : commentaires `//` retirés, `$()` vide résolu. */
export function parseXcconfig(text) {
  const settings = {};
  for (const raw of String(text).split('\n')) {
    const line = raw.replace(/\/\/.*$/, '').trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^([A-Za-z_][\w]*(?:\[[^\]]*\])*)\s*=\s*(.*)$/);
    if (match) settings[match[1]] = match[2].replace(/\$\(\)/g, '').trim();
  }
  return settings;
}

/** Remplace `$(VAR)` par sa valeur (récursivement dans les objets et tableaux). */
export function resolveVariables(value, settings) {
  if (typeof value === 'string') return value.replace(/\$\(([A-Za-z_]\w*)\)/g, (_, name) => settings[name] ?? '');
  if (Array.isArray(value)) return value.map((item) => resolveVariables(item, settings));
  if (value && typeof value === 'object' && !(value instanceof Date) && !Buffer.isBuffer(value)) {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolveVariables(item, settings)]));
  }
  return value;
}

export function compareVersions(a, b) {
  const pa = String(a).split('.').map(Number);
  const pb = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff) return Math.sign(diff);
  }
  return 0;
}

export const isVersion = (value) => /^\d+(?:\.\d+){0,2}$/.test(String(value ?? ''));

/** Dimensions et canal alpha d'un PNG (en-tête IHDR et bloc tRNS). */
export function pngInfo(input) {
  const buffer = Buffer.from(input);
  if (buffer.length < 33 || buffer.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a' || buffer.subarray(12, 16).toString() !== 'IHDR') {
    throw new Error('fichier PNG invalide');
  }
  const colorType = buffer[25];
  let transparency = false;
  for (let offset = 8; offset + 8 <= buffer.length;) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.subarray(offset + 4, offset + 8).toString();
    if (type === 'tRNS') transparency = true;
    if (type === 'IEND') break;
    offset += 12 + length;
  }
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20), alpha: colorType === 4 || colorType === 6 || transparency };
}

// ---------------------------------------------------------------------------------------------
// Gardes partagées
// ---------------------------------------------------------------------------------------------

/** Valeurs d'environnement Release : production Supabase, jamais de staging ni de démo. */
function checkProduction(fail, garde, values, origine) {
  if (values.environment !== 'production') {
    fail(garde, `${origine} : environnement « ${values.environment || 'absent'} », « production » exigé (aucun mode démo ni staging par défaut en Release).`);
  }
  if (values.url !== APP.productionUrl) {
    fail(garde, `${origine} : URL Supabase « ${values.url || 'absente'} », ${APP.productionUrl} exigée.`);
  }
  const key = values.key || '';
  if (!key.startsWith('sb_publishable_') || key.startsWith('sb_secret_') || /service_role/i.test(key)) {
    fail(garde, `${origine} : la clé Supabase doit être une clé publishable de production (sb_publishable_…), jamais une clé secrète.`);
  }
  if (values.aps !== undefined && values.aps !== 'production') {
    fail(garde, `${origine} : APS_ENVIRONMENT « ${values.aps || 'absent'} », « production » exigé pour le push TestFlight.`);
  }
  if (JSON.stringify(values).includes(APP.stagingRef)) {
    fail(garde, `${origine} : référence au projet STAGING ${APP.stagingRef} interdite dans un build Release.`);
  }
}

/**
 * Vérifie qu'un jeu d'entitlements (profil ou binaire signé) couvre chaque entitlement exigé.
 * `*` (profil App Store) couvre toute valeur ; un tableau doit contenir chaque entrée exigée.
 */
export function entitlementsGaps(required, actual) {
  const gaps = [];
  for (const [key, expected] of Object.entries(required)) {
    const value = actual?.[key];
    if (value === undefined) { gaps.push(`${key} absent`); continue; }
    if (value === '*' || (Array.isArray(value) && value.includes('*'))) continue;
    if (Array.isArray(expected)) {
      const missing = expected.filter((item) => !(Array.isArray(value) ? value : [value]).includes(item));
      if (missing.length) gaps.push(`${key} sans ${missing.join(', ')}`);
    } else if (value !== expected) gaps.push(`${key} = ${JSON.stringify(value)}, ${JSON.stringify(expected)} attendu`);
  }
  return gaps;
}

/** Entitlements exigés : ceux de Jolene.entitlements résolus avec les réglages Release. */
export function requiredEntitlements(sourceEntitlements, settings) {
  return resolveVariables(sourceEntitlements, settings);
}

function checkDistributionEntitlements(fail, garde, entitlements, origine) {
  if (entitlements?.['application-identifier'] !== `${APP.teamId}.${APP.bundleId}`) {
    fail(garde, `${origine} : application-identifier « ${entitlements?.['application-identifier'] ?? 'absent'} », ${APP.teamId}.${APP.bundleId} exigé.`);
  }
  if (entitlements?.['com.apple.developer.team-identifier'] !== APP.teamId) {
    fail(garde, `${origine} : team-identifier ${APP.teamId} exigé.`);
  }
  if (entitlements?.['get-task-allow'] !== false) fail(garde, `${origine} : get-task-allow doit valoir false (profil de distribution).`);
  if (entitlements?.['beta-reports-active'] !== true) {
    fail(garde, `${origine} : beta-reports-active absent, ce n'est pas un profil App Store (TestFlight refuserait le build).`);
  }
}

// ---------------------------------------------------------------------------------------------
// Garde « source » : dépôt, avant compilation
// ---------------------------------------------------------------------------------------------

export function evaluateSources(files) {
  const { fail, done } = collector();
  const base = parseXcconfig(files.baseXcconfig);
  const production = parseXcconfig(files.productionXcconfig);
  const firstStatement = String(files.productionXcconfig).split('\n').map((line) => line.replace(/\/\/.*$/, '').trim()).find(Boolean);
  if (firstStatement !== '#include "Base.xcconfig"') {
    fail('environnement', 'Production.xcconfig doit commencer par #include "Base.xcconfig" : inclus plus bas, Base écraserait les valeurs de production.');
  }
  const settings = { ...base, ...production };
  checkProduction(fail, 'environnement', {
    environment: settings.JOLENE_ENVIRONMENT, url: settings.JOLENE_SUPABASE_URL,
    key: settings.JOLENE_SUPABASE_PUBLISHABLE_KEY, aps: settings.APS_ENVIRONMENT,
  }, 'Production.xcconfig');
  if (String(files.productionXcconfig).includes(APP.stagingRef)) fail('environnement', `Production.xcconfig cite le projet STAGING ${APP.stagingRef}.`);
  const release = String(files.pbxproj).match(/baseConfigurationReference = \w+ \/\* (\S+\.xcconfig) \*\/;(?:(?!isa = XCBuildConfiguration)[\s\S])*?name = Release;/);
  if (release?.[1] !== 'Production.xcconfig') {
    fail('environnement', `la configuration Release du projet doit reposer sur Production.xcconfig (trouvé : ${release?.[1] ?? 'aucune'}).`);
  }
  if (!/<ArchiveAction\s+buildConfiguration = "Release"/.test(files.scheme)) fail('environnement', 'le scheme Jolene doit archiver en configuration Release.');

  const info = parsePlist(files.infoPlist);
  if (info.ITSAppUsesNonExemptEncryption !== false) {
    fail('chiffrement', 'Info.plist doit déclarer ITSAppUsesNonExemptEncryption = false (sinon le build reste bloqué en « conformité export manquante »).');
  }
  for (const [key, variable] of [['CFBundleIdentifier', 'PRODUCT_BUNDLE_IDENTIFIER'], ['CFBundleShortVersionString', 'MARKETING_VERSION'],
    ['CFBundleVersion', 'CURRENT_PROJECT_VERSION'], ['JoleneEnvironment', 'JOLENE_ENVIRONMENT'], ['JoleneSupabaseURL', 'JOLENE_SUPABASE_URL'],
    ['JoleneSupabasePublishableKey', 'JOLENE_SUPABASE_PUBLISHABLE_KEY']]) {
    if (info[key] !== `$(${variable})`) fail('environnement', `Info.plist : ${key} doit valoir $(${variable}) (valeur figée interdite).`);
  }

  if (settings.PRODUCT_BUNDLE_IDENTIFIER !== APP.bundleId) fail('identite', `PRODUCT_BUNDLE_IDENTIFIER ${settings.PRODUCT_BUNDLE_IDENTIFIER}, ${APP.bundleId} exigé.`);
  if (settings.DEVELOPMENT_TEAM !== APP.teamId) fail('identite', `DEVELOPMENT_TEAM ${settings.DEVELOPMENT_TEAM}, ${APP.teamId} exigé.`);
  if (settings.CODE_SIGN_STYLE !== 'Manual') fail('identite', 'CODE_SIGN_STYLE doit valoir Manual.');
  if (settings.CODE_SIGN_IDENTITY !== '$(JOLENE_CODE_SIGN_IDENTITY)' || settings.PROVISIONING_PROFILE_SPECIFIER !== '$(JOLENE_PROVISIONING_PROFILE)') {
    fail('identite', 'Production.xcconfig doit relayer CODE_SIGN_IDENTITY et PROVISIONING_PROFILE_SPECIFIER depuis JOLENE_CODE_SIGN_IDENTITY / JOLENE_PROVISIONING_PROFILE.');
  }
  const marketing = settings.MARKETING_VERSION;
  const capacitor = files.mobileRelease ? JSON.parse(files.mobileRelease) : {};
  if (!isVersion(marketing) || compareVersions(marketing, APP.minimumMarketingVersion) < 0) {
    fail('identite', `MARKETING_VERSION ${marketing || 'absente'} : ${APP.minimumMarketingVersion} minimum (décision du plan, lot 6).`);
  } else if (isVersion(capacitor.marketingVersion) && compareVersions(marketing, capacitor.marketingVersion) <= 0) {
    fail('identite', `MARKETING_VERSION ${marketing} doit dépasser la coquille Capacitor ${capacitor.marketingVersion}.`);
  }

  const entitlements = parsePlist(files.entitlements);
  if (entitlements['aps-environment'] !== '$(APS_ENVIRONMENT)') fail('entitlements', 'Jolene.entitlements : aps-environment doit valoir $(APS_ENVIRONMENT).');
  if (!Array.isArray(entitlements['com.apple.developer.associated-domains']) || entitlements['com.apple.developer.associated-domains'].length === 0) {
    fail('entitlements', 'Jolene.entitlements : associated-domains absent (Universal Links).');
  }

  checkPrivacy(fail, files.privacyInfo, files.swiftSources, { inResources: /PrivacyInfo\.xcprivacy in Resources/.test(files.pbxproj) });
  checkIconSource(fail, files.iconContents, files.iconFiles);
  done();
  return { settings, entitlements };
}

function checkPrivacy(fail, privacyXml, swiftSources, { inResources }) {
  if (!privacyXml) { fail('confidentialite', 'ios-native/Jolene/PrivacyInfo.xcprivacy absent : App Store Connect refuse l\'envoi.'); return; }
  if (inResources === false) fail('confidentialite', 'PrivacyInfo.xcprivacy n\'est pas copié dans les ressources de la cible Jolene.');
  let privacy;
  try { privacy = parsePlist(privacyXml); } catch (error) { fail('confidentialite', `PrivacyInfo.xcprivacy illisible : ${error.message}.`); return; }
  if (privacy.NSPrivacyTracking !== false) fail('confidentialite', 'NSPrivacyTracking doit valoir false (Jolene ne piste pas).');
  if ((privacy.NSPrivacyTrackingDomains ?? []).length) fail('confidentialite', 'NSPrivacyTrackingDomains doit rester vide.');
  const declared = new Map();
  for (const entry of privacy.NSPrivacyAccessedAPITypes ?? []) {
    const category = entry.NSPrivacyAccessedAPIType;
    const reasons = entry.NSPrivacyAccessedAPITypeReasons ?? [];
    if (!RAISONS_API[category]) { fail('confidentialite', `catégorie d'API inconnue : ${category}.`); continue; }
    if (!reasons.length || reasons.some((reason) => !RAISONS_API[category].includes(reason))) {
      fail('confidentialite', `${category} : raisons ${JSON.stringify(reasons)} invalides (admises : ${RAISONS_API[category].join(', ')}).`);
    }
    declared.set(category, reasons);
  }
  for (const [category, pattern] of Object.entries(USAGES_API)) {
    const users = Object.entries(swiftSources ?? {}).filter(([, text]) => pattern.test(text.replace(/\/\/.*$/gm, ''))).map(([file]) => file);
    if (users.length && !declared.has(category)) {
      fail('confidentialite', `${category} utilisée (${users.slice(0, 3).join(', ')}) mais non déclarée dans PrivacyInfo.xcprivacy (refus ITMS-91053).`);
    }
  }
}

function checkIconSource(fail, contentsJson, iconFiles) {
  let contents;
  try { contents = JSON.parse(contentsJson); } catch { fail('icone', 'AppIcon.appiconset/Contents.json absent ou illisible.'); return; }
  const entry = (contents.images ?? []).find((image) => image.size === '1024x1024' && image.filename && ['universal', 'ios-marketing'].includes(image.idiom));
  if (!entry) { fail('icone', 'aucune icône 1024 × 1024 déclarée dans AppIcon.appiconset.'); return; }
  const buffer = iconFiles?.[entry.filename];
  if (!buffer) { fail('icone', `icône ${entry.filename} déclarée mais absente.`); return; }
  try {
    const png = pngInfo(buffer);
    if (png.width !== 1024 || png.height !== 1024) fail('icone', `icône ${entry.filename} en ${png.width} × ${png.height}, 1024 × 1024 exigé.`);
    if (png.alpha) fail('icone', `icône ${entry.filename} avec canal alpha : App Store Connect refuse une icône transparente (ITMS-90717).`);
  } catch (error) { fail('icone', `icône ${entry.filename} : ${error.message}.`); }
}

function listSwift(dir, root, out = {}) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (name === '.build' || name === 'Tests' || name === 'DerivedData') continue;
    const path = join(dir, name);
    if (statSync(path).isDirectory()) listSwift(path, root, out);
    else if (name.endsWith('.swift')) out[path.slice(root.length + 1)] = readFileSync(path, 'utf8');
  }
  return out;
}

export function loadSources(root) {
  const native = join(root, 'ios-native');
  const read = (path) => (existsSync(join(native, path)) ? readFileSync(join(native, path), 'utf8') : '');
  const iconDir = join(native, 'Jolene/Assets.xcassets/AppIcon.appiconset');
  const iconFiles = existsSync(iconDir) ? Object.fromEntries(readdirSync(iconDir).filter((f) => f.endsWith('.png')).map((f) => [f, readFileSync(join(iconDir, f))])) : {};
  const swiftSources = listSwift(join(native, 'Jolene'), root);
  const packages = join(native, 'Packages');
  for (const name of existsSync(packages) ? readdirSync(packages) : []) listSwift(join(packages, name, 'Sources'), root, swiftSources);
  return {
    baseXcconfig: read('Config/Base.xcconfig'),
    productionXcconfig: read('Config/Production.xcconfig'),
    pbxproj: read('Jolene.xcodeproj/project.pbxproj'),
    scheme: read('Jolene.xcodeproj/xcshareddata/xcschemes/Jolene.xcscheme'),
    infoPlist: read('Jolene/Info.plist'),
    entitlements: read('Jolene/Jolene.entitlements'),
    privacyInfo: read('Jolene/PrivacyInfo.xcprivacy'),
    iconContents: read('Jolene/Assets.xcassets/AppIcon.appiconset/Contents.json'),
    mobileRelease: existsSync(join(root, 'config/mobile-release.json')) ? readFileSync(join(root, 'config/mobile-release.json'), 'utf8') : '',
    iconFiles,
    swiftSources,
  };
}

// ---------------------------------------------------------------------------------------------
// Numérotation
// ---------------------------------------------------------------------------------------------

/** Plancher : dernier build Capacitor publié (24) ou celui que config/mobile-release.json réserve. */
export function buildFloor(mobileRelease) {
  const capacitor = Number(mobileRelease?.buildNumber);
  return Math.max(APP.buildFloor, Number.isSafeInteger(capacitor) ? capacitor : 0);
}

/**
 * Numéro de build : l'entrée facultative, sinon max(dernier build App Store Connect, plancher) + 1.
 * Refus net d'un numéro inférieur ou égal au plancher, supérieur au dernier build + MARGE_BUILD, ou
 * déjà présent dans App Store Connect.
 */
/** Écart maximal entre un numéro saisi et le dernier build connu (faute de frappe 3100 pour 31). */
export const MARGE_BUILD = 50;

export function resolveBuildNumber({ requested, existing, floor }) {
  const used = new Set(existing.map((version) => String(version).trim()));
  const latest = Math.max(floor, ...[...used].filter((v) => /^\d+$/.test(v)).map(Number));
  const raw = String(requested ?? '').trim();
  if (!raw) return latest + 1;
  if (!/^[1-9]\d{0,8}$/.test(raw)) throw new GuardFailure([`[numerotation] numéro de build « ${raw} » invalide : entier positif exigé (voir ${DOC}, garde « numerotation »)`]);
  const number = Number(raw);
  if (number <= floor) throw new GuardFailure([`[numerotation] build ${number} refusé : il doit dépasser ${floor}, dernier build de la coquille Capacitor (voir ${DOC}, garde « numerotation »)`]);
  if (number > latest + MARGE_BUILD) {
    throw new GuardFailure([`[numerotation] build ${number} refusé : au plus ${latest + MARGE_BUILD} (dernier build ${latest} + ${MARGE_BUILD}). Un numéro trop haut relèverait définitivement le plancher de tous les builds suivants (voir ${DOC}, garde « numerotation »)`]);
  }
  if (used.has(raw)) throw new GuardFailure([`[numerotation] build ${number} déjà présent dans App Store Connect (app ${APP.appleId}) : choisissez un numéro libre ou laissez le champ vide (voir ${DOC}, garde « numerotation »)`]);
  return number;
}

// ---------------------------------------------------------------------------------------------
// App Store Connect (lecture seule)
// ---------------------------------------------------------------------------------------------

/** Jeton ES256 de l'API App Store Connect (20 min max ; 15 min ici). */
export function ascToken({ keyId, issuerId, privateKeyBase64, now = Date.now() }) {
  if (!keyId || !issuerId || !privateKeyBase64) throw new Error('Secrets App Store Connect manquants (ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_BASE64).');
  const pem = Buffer.from(privateKeyBase64, 'base64').toString('utf8');
  if (!pem.includes('-----BEGIN PRIVATE KEY-----')) throw new Error('ASC_PRIVATE_KEY_BASE64 n\'est pas une clé .p8 encodée en base64.');
  const iat = Math.floor(now / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${encode({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.${encode({ iss: issuerId, iat, exp: iat + 900, aud: 'appstoreconnect-v1' })}`;
  const signature = sign('sha256', Buffer.from(input), { key: createPrivateKey(pem), dsaEncoding: 'ieee-p1363' });
  return `${input}.${signature.toString('base64url')}`;
}

export function ascClient({ fetchImpl = fetch, token }) {
  return async function get(path) {
    const url = new URL(path, 'https://api.appstoreconnect.apple.com');
    if (url.protocol !== 'https:' || url.host !== 'api.appstoreconnect.apple.com' || url.username || url.password || !url.pathname.startsWith('/v1/')) {
      throw new Error('URL App Store Connect refusée');
    }
    const response = await fetchImpl(url, { headers: { Authorization: `Bearer ${token()}`, Accept: 'application/json' } });
    if (!response.ok) {
      let detail = '';
      try { detail = ((await response.json()).errors ?? []).map((e) => `${e.code ?? ''} ${e.title ?? ''}`.trim()).join(' ; '); } catch { /* corps non JSON */ }
      throw new Error(`App Store Connect HTTP ${response.status}${detail ? ` : ${detail}` : ''}`);
    }
    return response.json();
  };
}

/** Tous les builds de l'app (toutes versions, y compris expirés et en traitement), pages comprises. */
export async function listBuilds(get, { filter = '' } = {}) {
  const app = await get(`/v1/apps/${APP.appleId}?fields[apps]=bundleId`);
  if (app?.data?.attributes?.bundleId !== APP.bundleId) {
    throw new Error(`L'app App Store Connect ${APP.appleId} ne correspond pas au bundle ${APP.bundleId}.`);
  }
  const builds = [];
  const seen = new Set();
  let next = `/v1/builds?filter[app]=${APP.appleId}${filter}&fields[builds]=version,processingState,expired,usesNonExemptEncryption&limit=200`;
  while (next) {
    if (seen.has(next) || seen.size >= 50) throw new Error('Pagination App Store Connect en boucle ou trop longue.');
    seen.add(next);
    const page = await get(next);
    if (!Array.isArray(page?.data)) throw new Error('Réponse App Store Connect sans liste de builds.');
    builds.push(...page.data);
    next = page.links?.next ?? null;
  }
  return builds;
}

/** État du build envoyé : absent, en traitement, prêt ; refus si invalide ou sans conformité export. */
export function evaluateProcessing(builds, number) {
  const matches = builds.filter((build) => build?.attributes?.version === String(number));
  if (matches.length === 0) return 'absent';
  if (matches.length > 1) throw new GuardFailure([`[traitement] plusieurs builds ${number} pour cette version (voir ${DOC}, garde « traitement »)`]);
  const { processingState, expired, usesNonExemptEncryption } = matches[0].attributes;
  if (processingState === 'PROCESSING') return 'processing';
  if (processingState !== 'VALID') {
    throw new GuardFailure([`[traitement] build ${number} en état ${processingState} : consultez l'e-mail d'App Store Connect (codes ITMS) (voir ${DOC}, garde « traitement »)`]);
  }
  if (expired !== false) throw new GuardFailure([`[traitement] build ${number} expiré ou d'expiration inconnue (voir ${DOC}, garde « traitement »)`]);
  if (usesNonExemptEncryption !== false) {
    throw new GuardFailure([`[traitement] build ${number} sans conformité export « false » : TestFlight le bloquera (voir ${DOC}, garde « traitement »)`]);
  }
  return 'valid';
}

// ---------------------------------------------------------------------------------------------
// Gardes du profil, des réglages résolus et du binaire
// ---------------------------------------------------------------------------------------------

export function evaluateProfile(profile, required, { now = new Date(), identitySha1 } = {}) {
  const { fail, done } = collector();
  if (profile?.Name !== APP.profile) fail('profil', `profil « ${profile?.Name ?? 'sans nom'} », « ${APP.profile} » exigé.`);
  if (!(profile?.TeamIdentifier ?? []).includes(APP.teamId)) fail('profil', `profil hors équipe ${APP.teamId}.`);
  if (profile?.ProvisionedDevices || profile?.ProvisionsAllDevices) fail('profil', 'profil de développement, ad hoc ou entreprise : un profil App Store est exigé.');
  const expiration = profile?.ExpirationDate instanceof Date ? profile.ExpirationDate : null;
  if (!expiration || expiration <= now) fail('profil', `profil expiré ou sans date d'expiration (${expiration?.toISOString() ?? 'absente'}).`);
  checkDistributionEntitlements(fail, 'profil', profile?.Entitlements, 'profil');
  const gaps = entitlementsGaps(required, profile?.Entitlements);
  if (gaps.length) {
    fail('profil', `le profil ne couvre pas les entitlements de Jolene.entitlements (${gaps.join(' ; ')}) : régénérez « ${APP.profile} » pour l'App ID ${APP.bundleId} avec Push et Associated Domains, puis remplacez IOS_PROFILE_BASE64.`);
  }
  const certificates = (profile?.DeveloperCertificates ?? []).map((der) => {
    try {
      const cert = new X509Certificate(der);
      return { subject: cert.subject, sha1: createHash('sha1').update(der).digest('hex').toUpperCase() };
    } catch { return null; }
  }).filter(Boolean);
  const matching = certificates.filter((cert) => cert.subject.split('\n').includes(`CN=${APP.identity}`));
  const empreinte = String(identitySha1 ?? '').replace(/:/g, '').trim().toUpperCase();
  if (!matching.length) fail('profil', `le profil n'inclut aucun certificat « ${APP.identity} ».`);
  else if (!/^[0-9A-F]{40}$/.test(empreinte)) {
    fail('profil', 'empreinte SHA-1 du certificat du .p12 absente ou invalide (IDENTITY_SHA1) : le contrôle « certificat du .p12 = certificat du profil » ne peut pas avoir lieu.');
  } else if (!matching.some((cert) => cert.sha1 === empreinte)) {
    fail('profil', 'le certificat du .p12 (IOS_DISTRIBUTION_P12_BASE64) n\'est pas celui que le profil autorise.');
  }
  done();
  const daysLeft = expiration ? Math.floor((expiration - now) / 86400000) : 0;
  return { uuid: profile.UUID, daysLeft };
}

export function evaluateBuildSettings(settings, { buildNumber }) {
  const { fail, done } = collector();
  if (settings.CONFIGURATION !== 'Release') fail('reglages', `configuration ${settings.CONFIGURATION}, Release exigée.`);
  for (const [key, expected] of [['PRODUCT_BUNDLE_IDENTIFIER', APP.bundleId], ['DEVELOPMENT_TEAM', APP.teamId], ['CODE_SIGN_STYLE', 'Manual'],
    ['CODE_SIGN_IDENTITY', APP.identity], ['PROVISIONING_PROFILE_SPECIFIER', APP.profile], ['CURRENT_PROJECT_VERSION', String(buildNumber)],
    ['CODE_SIGN_ENTITLEMENTS', 'Jolene/Jolene.entitlements'], ['INFOPLIST_FILE', 'Jolene/Info.plist'], ['ASSETCATALOG_COMPILER_APPICON_NAME', 'AppIcon']]) {
    if (settings[key] !== expected) fail('reglages', `${key} = « ${settings[key] ?? ''} », « ${expected} » attendu.`);
  }
  if (!isVersion(settings.MARKETING_VERSION) || compareVersions(settings.MARKETING_VERSION, APP.minimumMarketingVersion) < 0) {
    fail('reglages', `MARKETING_VERSION ${settings.MARKETING_VERSION ?? 'absente'} : ${APP.minimumMarketingVersion} minimum.`);
  }
  if (/\bDEBUG\b/.test(settings.SWIFT_ACTIVE_COMPILATION_CONDITIONS ?? '')) {
    fail('reglages', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS contient DEBUG : les surcharges -JOLENE_MODE (démo) seraient actives.');
  }
  if (/(?:^|\s)-D\s*DEBUG\b/.test(settings.OTHER_SWIFT_FLAGS ?? '')) {
    fail('reglages', 'OTHER_SWIFT_FLAGS contient -D DEBUG : les surcharges -JOLENE_MODE (démo) seraient actives.');
  }
  if (settings.SWIFT_OPTIMIZATION_LEVEL === '-Onone') fail('reglages', 'SWIFT_OPTIMIZATION_LEVEL = -Onone : réglage de débogage dans un build Release.');
  checkProduction(fail, 'reglages', {
    environment: settings.JOLENE_ENVIRONMENT, url: settings.JOLENE_SUPABASE_URL,
    key: settings.JOLENE_SUPABASE_PUBLISHABLE_KEY, aps: settings.APS_ENVIRONMENT,
  }, 'réglages Release');
  done();
}

export function evaluateBundle(info, { buildNumber, hasPrivacyInfo, privacyXml, hasAssetsCar, swiftSources }) {
  const { fail, done } = collector();
  if (info.CFBundleIdentifier !== APP.bundleId) fail('binaire', `CFBundleIdentifier ${info.CFBundleIdentifier}, ${APP.bundleId} exigé.`);
  if (!isVersion(info.CFBundleShortVersionString) || compareVersions(info.CFBundleShortVersionString, APP.minimumMarketingVersion) < 0) {
    fail('binaire', `CFBundleShortVersionString ${info.CFBundleShortVersionString}, ${APP.minimumMarketingVersion} minimum.`);
  }
  if (info.CFBundleVersion !== String(buildNumber)) fail('binaire', `CFBundleVersion ${info.CFBundleVersion}, ${buildNumber} attendu.`);
  if (info.ITSAppUsesNonExemptEncryption !== false) fail('chiffrement', 'le binaire doit déclarer ITSAppUsesNonExemptEncryption = false.');
  checkProduction(fail, 'environnement', {
    environment: info.JoleneEnvironment, url: info.JoleneSupabaseURL, key: info.JoleneSupabasePublishableKey,
  }, 'Info.plist du binaire');
  if (JSON.stringify(info).includes(APP.stagingRef)) fail('environnement', `Info.plist du binaire : référence STAGING ${APP.stagingRef}.`);
  if (info.CFBundleIcons?.CFBundlePrimaryIcon?.CFBundleIconName !== 'AppIcon' || !hasAssetsCar) {
    fail('icone', 'le binaire ne contient pas l\'icône compilée AppIcon (CFBundleIconName ou Assets.car absent).');
  }
  if (!hasPrivacyInfo) fail('confidentialite', 'PrivacyInfo.xcprivacy absent à la racine de Jolene.app.');
  else checkPrivacy(fail, privacyXml, swiftSources, {});
  done();
}

export function evaluateSignature({ entitlements, embeddedProfile, authorities, required, expectedProfileUuid }) {
  const { fail, done } = collector();
  if (!authorities.includes(APP.identity)) fail('signature', `Jolene.app n'est pas signée par « ${APP.identity} » (autorités : ${authorities.join(', ') || 'aucune'}).`);
  if (embeddedProfile?.Name !== APP.profile) fail('signature', `profil embarqué « ${embeddedProfile?.Name ?? 'absent'} », « ${APP.profile} » exigé.`);
  if (!expectedProfileUuid || embeddedProfile?.UUID !== expectedProfileUuid) {
    fail('signature', `profil embarqué ${embeddedProfile?.UUID ?? 'sans UUID'} différent du profil validé à l'étape « profil » (${expectedProfileUuid || 'UUID non transmis'}).`);
  }
  if (embeddedProfile?.ProvisionedDevices || embeddedProfile?.ProvisionsAllDevices) fail('signature', 'profil embarqué de développement, ad hoc ou entreprise.');
  checkDistributionEntitlements(fail, 'signature', entitlements, 'entitlements signés');
  const gaps = entitlementsGaps(required, entitlements);
  if (gaps.length) fail('signature', `entitlements signés incomplets (${gaps.join(' ; ')}).`);
  if (entitlements?.['aps-environment'] !== 'production') fail('signature', 'aps-environment signé doit valoir production.');
  done();
}

// ---------------------------------------------------------------------------------------------
// Interface en ligne de commande
// ---------------------------------------------------------------------------------------------

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');

function output(values) {
  if (!process.env.GITHUB_OUTPUT) return;
  appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join(''));
}

function summary(line) {
  console.log(line);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${line}\n`);
}

function optionValue(args, name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function requireBuild(args) {
  const value = optionValue(args, '--build');
  if (!/^[1-9]\d*$/.test(value ?? '')) throw new Error('--build <numéro> exigé');
  return Number(value);
}

function ascFromEnv() {
  const token = () => ascToken({ keyId: process.env.ASC_KEY_ID, issuerId: process.env.ASC_ISSUER_ID, privateKeyBase64: process.env.ASC_PRIVATE_KEY_BASE64 });
  token(); // Échoue tôt, sans rien afficher de la clé, si un secret manque.
  return ascClient({ token });
}

function sourceContext() {
  const files = loadSources(ROOT);
  const { settings, entitlements } = evaluateSources(files);
  return { files, settings, required: requiredEntitlements(entitlements, settings) };
}

async function main(command, args) {
  switch (command) {
    case 'depot': {
      const { settings } = sourceContext();
      summary(`✓ Gardes du dépôt : ${APP.bundleId} ${settings.MARKETING_VERSION}, production, chiffrement exempté, manifeste de confidentialité, icône 1024, entitlements.`);
      return;
    }
    case 'build-number': {
      const get = ascFromEnv();
      const builds = await listBuilds(get);
      const floor = buildFloor(JSON.parse(readFileSync(join(ROOT, 'config/mobile-release.json'), 'utf8')));
      const number = resolveBuildNumber({ requested: process.env.JOLENE_BUILD_INPUT, existing: builds.map((b) => b.attributes?.version), floor });
      output({ build_number: number });
      summary(`✓ Build ${number} (${process.env.JOLENE_BUILD_INPUT?.trim() ? 'saisi' : 'calculé'} ; ${builds.length} build(s) déjà dans App Store Connect, plancher ${floor}).`);
      return;
    }
    case 'verify-free': {
      const number = args[0];
      const builds = await listBuilds(ascFromEnv());
      const floor = buildFloor(JSON.parse(readFileSync(join(ROOT, 'config/mobile-release.json'), 'utf8')));
      resolveBuildNumber({ requested: number, existing: builds.map((b) => b.attributes?.version), floor });
      summary(`✓ Build ${number} toujours libre dans App Store Connect juste avant l'envoi.`);
      return;
    }
    case 'profile': {
      const { required } = sourceContext();
      const result = evaluateProfile(readPlistFile(args[0]), required, { identitySha1: process.env.IDENTITY_SHA1 });
      output({ uuid: result.uuid });
      if (result.daysLeft < 30) console.log(`::warning::Le profil « ${APP.profile} » expire dans ${result.daysLeft} jour(s).`);
      summary(`✓ Profil « ${APP.profile} » : App Store, ${APP.teamId}.${APP.bundleId}, entitlements couverts, certificat du .p12 autorisé (expire dans ${result.daysLeft} j).`);
      return;
    }
    case 'settings': {
      const buildNumber = requireBuild(args);
      const entries = JSON.parse(readFileSync(args[0], 'utf8'));
      const target = entries.find((entry) => entry.target === 'Jolene');
      if (!target) throw new Error('Cible Jolene absente de xcodebuild -showBuildSettings');
      evaluateBuildSettings(target.buildSettings, { buildNumber });
      summary(`✓ Réglages Release résolus : production, sans DEBUG, signature « ${APP.identity} » / « ${APP.profile} », build ${buildNumber}.`);
      return;
    }
    case 'bundle': {
      const buildNumber = requireBuild(args);
      const app = args[0];
      const privacyPath = join(app, 'PrivacyInfo.xcprivacy');
      const hasPrivacyInfo = existsSync(privacyPath);
      const privacyXml = hasPrivacyInfo ? (readFileSync(privacyPath).subarray(0, 6).toString() === 'bplist'
        ? execFileSync('plutil', ['-convert', 'xml1', '-o', '-', privacyPath], { encoding: 'utf8' }) : readFileSync(privacyPath, 'utf8')) : '';
      evaluateBundle(readPlistFile(join(app, 'Info.plist')), {
        buildNumber, hasPrivacyInfo, privacyXml, hasAssetsCar: existsSync(join(app, 'Assets.car')), swiftSources: loadSources(ROOT).swiftSources,
      });
      summary(`✓ Binaire : ${APP.bundleId} build ${buildNumber}, production, chiffrement exempté, PrivacyInfo.xcprivacy et icône embarqués.`);
      return;
    }
    case 'signature': {
      const app = args[0];
      const expectedProfileUuid = optionValue(args, '--profile-uuid');
      if (!/^[0-9A-Fa-f-]{36}$/.test(expectedProfileUuid ?? '')) throw new Error('--profile-uuid <UUID du profil validé> exigé');
      const { required } = sourceContext();
      execFileSync('codesign', ['--verify', '--deep', '--strict', app], { stdio: ['ignore', 'ignore', 'pipe'] });
      // codesign -dvv décrit la signature sur stderr.
      const described = spawnSync('codesign', ['-dvv', app], { encoding: 'utf8' });
      if (described.status !== 0) throw new Error('codesign -dvv a échoué sur Jolene.app');
      const authorities = [...described.stderr.matchAll(/^Authority=(.+)$/gm)].map((match) => match[1].trim());
      const entitlements = parsePlist(execFileSync('codesign', ['-d', '--entitlements', '-', '--xml', app], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
      evaluateSignature({ entitlements, embeddedProfile: readPlistFile(join(app, 'embedded.mobileprovision')), authorities, required, expectedProfileUuid });
      summary(`✓ Signature : « ${APP.identity} », profil embarqué « ${APP.profile} », entitlements de production (push, associated domains).`);
      return;
    }
    case 'processing': {
      const number = args[0];
      if (!/^[1-9]\d*$/.test(number ?? '')) throw new Error('processing <numéro> exigé');
      const get = ascFromEnv();
      const timeout = Number(process.env.JOLENE_PROCESSING_TIMEOUT_S || 3600) * 1000;
      const interval = Number(process.env.JOLENE_PROCESSING_INTERVAL_S || 60) * 1000;
      const start = Date.now();
      for (;;) {
        const state = evaluateProcessing(await listBuilds(get, { filter: `&filter[version]=${number}` }), number);
        if (state === 'valid') { summary(`✓ Build ${number} traité par App Store Connect (VALID, conformité export false) : disponible pour les testeurs internes.`); return; }
        if (Date.now() - start > timeout) {
          throw new GuardFailure([`[traitement] build ${number} toujours « ${state} » après ${Math.round(timeout / 60000)} min : vérifiez App Store Connect et l'e-mail d'Apple (voir ${DOC}, garde « traitement »)`]);
        }
        console.log(`Build ${number} : ${state}, nouvelle lecture dans ${interval / 1000} s.`);
        await new Promise((resolve) => { setTimeout(resolve, interval); });
      }
    }
    default:
      throw new Error(`Sous-commande inconnue : ${command ?? 'absente'}`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const [command, ...args] = process.argv.slice(2);
  main(command, args).catch((error) => {
    const prefix = process.env.GITHUB_ACTIONS ? '::error::' : '✗ ';
    for (const line of error.failures ?? [error.message]) console.error(`${prefix}${line}`);
    process.exit(1);
  });
}
